IMPLEMENTATION MODULE RuleListModule;

(* copyright (c) 1987-96 John Bradley, Lidio Presutti, University of Toronto *)

(* Licensed under the Apache License, Version 2.0 (the "License");             *)
(* you may not use this file except in compliance with the License.            *)
(* You may obtain a copy of the License at                                     *)
(* http://www.apache.org/licenses/LICENSE-2.0                                  *)
(*                                                                             *)
(* Unless required by applicable law or agreed to in writing, software         *)
(* distributed under the License is distributed on an "AS IS" BASIS,           *)
(* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.    *)
(* See the License for the specific language governing permissions and         *)
(* limitations under the License.                                              *)

IMPORT ASCII;
IMPORT FIO, Str ;
IMPORT Storage;
FROM SYSTEM IMPORT ADR;
FROM HyperDataModel IMPORT HyperData, HyperLength;
FROM GlobalDefs IMPORT StrAny;
FROM HyperBase IMPORT HRecPntr,HyperFile, IOModeType,
              SetTruncOK, OpenHyperFile, CloseHyperFile, GetBaseHyper,
              ReleaseBaseHyper, SetTruncOK, FIOFile;
FROM MemoryManagement IMPORT RealStoragePntr, ALLOCATE;
FROM MainLists IMPORT
   PoolNoForTDBTACTLists;
FROM TACTDataServices IMPORT
  (* procs *) DisposeDataItem;
FROM ListData IMPORT
  (* types *) DataItemPntr, ItemType,
              MarkAsUsed, MarkAsFreed, ReleaseRealStringData,
              MakeRealStringData;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage,
            ResAskUser;
FROM Utils IMPORT  Exist,StandardizeFileName, RemoveExtension, TrimBlanks;
FROM UtilsTwo IMPORT IOErrorMessage, OK;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ListData IMPORT MakeRuleItem;
FROM Translations IMPORT
 (* var  *) Int2File,File2Int,
 (* type *) XlateStrAny, CurrentModeType,
 (* proc *) XlateLine;
FROM WordBase IMPORT IntToSortWord, WordSepCode;
FROM StringIO IMPORT
   SWriteString, SWriteChar;
FROM TACTListModule IMPORT
   TACTListType, TACTList, TACTListData, TACTListItem, TACTListBaseData,
   GenericDisposeListItem, GenericDisposeList, GenericGetItemData,
   GenericReleaseItemHold, GenericNewListItem, DiscardList, GenericCopyListItem;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) VMAccess, VMModify, VMRelease, VMMarkChanged, RealToPool;

CONST
  RefNameSepChar = "#" ;

VAR
   RuleFile:      HyperFile;
   RuleFileOpen:  BOOLEAN;
   NoRuleRecs:    CARDINAL;
   LastRulePos:   CARDINAL;
   BadRules:      BOOLEAN;
   FirstTimeMsg:  BOOLEAN;

PROCEDURE GetSortRuleName( RuleName : ARRAY OF CHAR; VAR SortRuleName : ARRAY OF CHAR);
   VAR
	len, i, j, k	: CARDINAL ;
	PadStr		: ARRAY[0..5] OF CHAR ;
	NeedPadding	: BOOLEAN ;
	NamePart	: StrAny;
   BEGIN
	len := Str.Length( RuleName ) ;
	i := len - 1 ;
	WHILE (i > 0) AND ( ('0' <= RuleName[i]) AND (RuleName[i] <= '9') ) DO
	   DEC( i ) ;
	END ;
	IF RuleName[i] = RefNameSepChar THEN
	   Str.Slice( NamePart, RuleName, 0, i ) ;
	   PadStr[0] := WordSepCode ;
	   IF len - i > 6 THEN
	      IF FirstTimeMsg THEN	(* do this only once per rule file! *)
		 FirstTimeMsg := FALSE ;
		 (*RES OLD MSG 420
		 Query name "%0" has more than 5 digits. The .GIX File may be unusable within UseBase.
		 *)
		 MsgString( RuleName,0);
		 PutResWarning( (*RES REM INS*) 420 );
	      END ;
	      j := 1 ;		(* use only first 5 digits!! *)
	      len := i + 5 ;
	   ELSE
	      FOR j := 1 TO 6 - (len-i) DO  PadStr[j] := '0'  END ;
	   END ;
	   FOR k := i+1 TO len DO  PadStr[j] := RuleName[k] ; INC(j)  END ;
	   NeedPadding := TRUE ;
	ELSE
	   Str.Copy( NamePart, RuleName ) ;
	   NeedPadding := FALSE ;
	END ;
	IntToSortWord( NamePart, SortRuleName);
	IF NeedPadding THEN Str.Append( SortRuleName, PadStr )  END ;
   END GetSortRuleName ;

PROCEDURE CloseDownRuleFile;
   VAR
      ErrMsg:    StrAny;
BEGIN
   IF NOT CloseHyperFile(RuleFile, ErrMsg) THEN
      ProgramErrorAndHalt('Error closing Rule File');
   END;
   RuleFileOpen := FALSE;
END CloseDownRuleFile;

PROCEDURE StartUpRuleFile(VAR FileExists: BOOLEAN): BOOLEAN;
   VAR
      ErrMsg:    StrAny;
      temp:      LONGCARD;
      dummy:     BOOLEAN;
      tf:        FIO.File;

BEGIN
   FileExists := TRUE;
   FirstTimeMsg := TRUE;
   IF RuleFileOpen THEN CloseDownRuleFile END;
   BadRules := FALSE;
   IF ( NOT StandardizeFileName(RuleFileInfo.FileName, RuleFileExtension)) THEN
      (*RES OLD MSG 232
      Please revise the incorrect .GIX Name "%0".
      *)
      MsgString(RuleFileInfo.FileName,0);
      PutResError( (*RES REM INS*) 232 );
      RETURN FALSE;
   END;
   IF NOT Exist(RuleFileInfo.FileName) THEN
      FileExists := FALSE;
      RETURN FALSE;
   END;

   IF NOT OpenHyperFile(RuleFile, RuleFileInfo.FileName, readmode, ErrMsg) THEN
      (*RES OLD MSG 234
      An error occurred opening .GIX File %0: %1.
      *)
      MsgString(RuleFileInfo.FileName,0);
      MsgString(ErrMsg,0);
      PutResError( (*RES REM INS*) 234 );
      RETURN FALSE;
   END;

   FIOFile(RuleFile,tf);
   temp := FIO.Size(tf);
   IF temp = 0 THEN
      (*RES OLD MSG 233
      "%0" is empty.
      *)
      MsgString(RuleFileInfo.FileName,0);
      PutResError( (*RES REM INS*) 233 );
      dummy := CloseHyperFile(RuleFile, ErrMsg);
      RETURN FALSE;
   END;
   DEC(temp);
   NoRuleRecs := VAL(CARDINAL,temp DIV VAL(LONGCARD,HyperLength)) + 1;
   LastRulePos := VAL(CARDINAL,temp MOD VAL(LONGCARD,HyperLength));

   SetTruncOK(RuleFile);
   RuleFileOpen := TRUE;
   RETURN TRUE;
END StartUpRuleFile;

PROCEDURE GetLineData(VAR Pos:    HRecPntr;
                      VAR Result: ARRAY OF CHAR);
VAR
   P:         RealStoragePntr;
   Pos2:      HRecPntr;
   i:         CARDINAL;
BEGIN
   GetBaseHyper(Pos.Rec,P,RuleFile);
   REPEAT
      IF Pos.Idx > 0 THEN DEC(Pos.Idx)
      ELSE
         IF Pos.Rec > 0 THEN
            ReleaseBaseHyper(RuleFile, P);
            DEC(Pos.Rec);
            GetBaseHyper(Pos.Rec,P,RuleFile);
            Pos.Idx := HyperLength - 1;
         END;
      END;
   UNTIL ((Pos.Rec = 0) AND (Pos.Idx = 0)) OR
   (P^.HRecord.TextData[Pos.Idx] = ASCII.cr);

   IF P^.HRecord.TextData[Pos.Idx] = ASCII.cr THEN
     INC(Pos.Idx);
     IF Pos.Idx >= HyperLength THEN
        ReleaseBaseHyper(RuleFile, P);
        INC(Pos.Rec);
        GetBaseHyper(Pos.Rec,P,RuleFile);
        Pos.Idx := 0;
     END;
   END;
   Pos2 := Pos;
   i := 0;
   WHILE (Pos2.Rec < NoRuleRecs) AND
   (P^.HRecord.TextData[Pos2.Idx] <> ASCII.cr)
   AND (P^.HRecord.TextData[Pos2.Idx] <> ASCII.sub) AND (i <= HIGH(Result)) DO
      WITH P^.HRecord DO
         IF TextData[Pos2.Idx] <> ASCII.lf THEN
             Result[i] := TextData[Pos2.Idx];
             INC(i);
         END;
         INC(Pos2.Idx);
         IF Pos2.Idx >= HyperLength THEN
            ReleaseBaseHyper(RuleFile, P);
            INC(Pos2.Rec);
            IF (Pos2.Rec < NoRuleRecs) THEN (* Pos2.Rec is 0 based *)
               GetBaseHyper(Pos2.Rec,P,RuleFile);
               Pos2.Idx := 0;
            END;
         END;
      END;
   END;
   IF i <= HIGH(Result) THEN Result[i] := 0C END;
   ReleaseBaseHyper(RuleFile, P);
END GetLineData;

PROCEDURE GetNextRecLine(VAR Pos:   HRecPntr): BOOLEAN;
VAR
   P:         RealStoragePntr;
   Pos2:      HRecPntr;
   i:         CARDINAL;
BEGIN
   Pos2 := Pos;
   GetBaseHyper(Pos2.Rec,P,RuleFile);
   WHILE (Pos2.Rec < NoRuleRecs) AND
	 (P^.HRecord.TextData[Pos2.Idx] <> ASCII.cr)
	 AND (P^.HRecord.TextData[Pos2.Idx] <> ASCII.sub) DO
      WITH P^.HRecord DO
         INC(Pos2.Idx);
         IF Pos2.Idx >= HyperLength THEN
            ReleaseBaseHyper(RuleFile, P);
            INC(Pos2.Rec);
            IF (Pos2.Rec < NoRuleRecs) THEN (* Pos2.Rec is 0 based *)
               GetBaseHyper(Pos2.Rec,P,RuleFile);
               Pos2.Idx := 0;
            END;
         END;
      END;
   END;
   IF (P^.HRecord.TextData[Pos2.Idx] = ASCII.sub) THEN
      ReleaseBaseHyper(RuleFile, P);
      RETURN FALSE
   END;
   ReleaseBaseHyper(RuleFile, P);
   INC(Pos2.Idx);
   IF (Pos2.Idx >= HyperLength) THEN
      INC(Pos2.Rec);
      IF Pos2.Rec >= NoRuleRecs THEN RETURN FALSE END;
      Pos2.Idx := 0;
   END;
   Pos := Pos2;
   RETURN TRUE;
END GetNextRecLine;

PROCEDURE GetPrevRecLine(VAR Pos:   HRecPntr): BOOLEAN;
VAR
   P:         RealStoragePntr;
   Pos2:      HRecPntr;
   i:         CARDINAL;
BEGIN
   Pos2 := Pos;
   GetBaseHyper(Pos2.Rec,P,RuleFile);
   WHILE (P^.HRecord.TextData[Pos2.Idx] <> ASCII.cr) DO
      WITH P^.HRecord DO
         IF Pos2.Idx > 0 THEN DEC(Pos2.Idx)
         ELSE
            ReleaseBaseHyper(RuleFile, P);
            IF Pos2.Rec = 0 THEN RETURN FALSE END;

            DEC(Pos2.Rec);
            GetBaseHyper(Pos2.Rec,P,RuleFile);
            Pos2.Idx := HyperLength - 1 ;
         END;
      END;
   END;
   ReleaseBaseHyper(RuleFile, P);
   IF (Pos2.Idx > 1) THEN DEC(Pos2.Idx,2)
   ELSE
      DEC(Pos2.Rec);
      Pos2.Idx := HyperLength - 2 + Pos2.Idx ;
   END;
   Pos := Pos2;
   RETURN TRUE;
END GetPrevRecLine;

PROCEDURE GetRuleLines(Pos:   HRecPntr;
                   VAR RuleName: ARRAY OF CHAR;
                   VAR RuleText: ARRAY OF CHAR) : BOOLEAN;
TYPE
    StrPtr = POINTER TO StrAny;
VAR
    Line:    StrAny;
    tLine:   StrAny;
    i:       CARDINAL;
    Rest:    StrPtr;
    ch:      CHAR;
    AL,NS:   CARDINAL;
    LD:      XlateStrAny;
    ED:      BOOLEAN;
    cm:      CurrentModeType;
    pos:     CARDINAL;
BEGIN
   cm.ModeIn := '0'; cm.ModeOut := '0';
   RuleName[0] := 0C;
   RuleText[0] := 0C;
   pos := 0;

   GetLineData(Pos,Line);
   WHILE Line[0] = 0C DO
      IF NOT GetNextRecLine(Pos) THEN
         ProgramErrorAndHalt('Unexpected EOF in GetRuleLines');
      END;
      GetLineData(Pos,Line);
   END;
   IF (Line[0] = ASCII.ht) OR (Line[0] = ' ') THEN
      (*RES OLD MSG 235
      There is an incorrectly-formed line in .GIX File %0: %1.
      *)
      MsgString(RuleFileInfo.FileName,0);
      MsgString(Line,0);
      PutResError( (*RES REM INS*) 235 );
      REPEAT
         IF NOT GetNextRecLine(Pos) THEN RETURN FALSE END;
         GetLineData(Pos,Line);
      UNTIL (Line[0] <> 0C) AND (Line[0] <> ASCII.ht) AND (Line[0] <> ' ');
   END;
   i := 0;
   WHILE (Line[i] <> 0C) AND (Line[i] <> ' ') AND (Line[i] <> ASCII.ht) DO
      INC(i)
   END;
   IF Line[i] <> 0C THEN
      Line[i] := 0C;
      INC(i)
   END;
   XlateLine(File2Int,'?',Line,cm,AL,LD,NS,ED,RuleName);
   WHILE (Line[i] <> 0C) AND ((Line[i] = ' ') OR (Line[i] = ASCII.ht)) DO
      INC(i)
   END;
   IF Line[i] = 0C THEN
      REPEAT
         REPEAT
            IF NOT GetNextRecLine(Pos) THEN
               Line[0] := 'A' (* anything but a space or tab j.b. *)
            ELSE
               GetLineData(Pos,Line)
            END;
         UNTIL (Line[0] <> 0C);
         IF (Line[0] <> ' ') AND (Line[0] <> ASCII.ht) THEN
            (*RES OLD MSG 236
            Name "%1" in .GIX File %1 has no Query attached to it.
            *)
            MsgString(RuleName,0);
            MsgString(RuleFileInfo.FileName,0);
            PutResError( (*RES REM INS*) 236 );
            RETURN FALSE
         END;
         i := 0;
         WHILE (Line[i] <> 0C) AND ((Line[i] = ' ') OR (Line[i] = ASCII.ht)) DO
            INC(i)
         END;
      UNTIL (Line[i] <> 0C);
   END;
   Rest := ADR(Line[i]);
   XlateLine(File2Int,'?',Rest^,cm, AL,LD,NS,ED,tLine);
   SWriteString(RuleText,pos,tLine,0);
   LOOP
      REPEAT
         IF NOT GetNextRecLine(Pos) THEN RETURN TRUE END;
         GetLineData(Pos,Line);
         IF (Line[0] <> ' ') AND (Line[0] <> ASCII.ht) THEN RETURN TRUE END;
         i := 0;
         WHILE (Line[i] = ' ') OR (Line[i] = ASCII.ht) DO INC(i) END;
      UNTIL Line[i] <> 0C;
      Rest := ADR(Line[i]);
      XlateLine(File2Int,'?',Rest^,cm, AL,LD,NS,ED,tLine);
      SWriteChar(RuleText,pos,' ',0);
      SWriteString(RuleText,pos,tLine,0);
(* RETURN TRUE; whats this doing here?!?!? j.b. 3/29/91 *)
   END;
END GetRuleLines;

PROCEDURE ChangeOverData(VAR VA:    VirtAddr (* DataItem VA *);
                            Pos:    HRecPntr;
                           Name:    ARRAY OF CHAR;
                       VAR Text:    ARRAY OF CHAR); (* read only *)
VAR
    temp:    StrAny;
    A:       DataItemPntr;
BEGIN
    IF VA = NILVirt THEN
       MakeRuleItem(Name,Text, PoolNoForTDBTACTLists, VA, A);
       MarkAsUsed(A)
    ELSE
       A := VMModify(VA);
       IF A^.UsageCount = 1 THEN
          WITH A^ DO
             ReleaseRealStringData(RuleName);
             MakeRealStringData(Name,RuleName);
             IF SortRuleName <> NIL THEN ReleaseRealStringData(SortRuleName) END;
             ReleaseRealStringData(RuleLine);
             MakeRealStringData(Text,RuleLine);
          END;
       ELSE
          MarkAsFreed( A ) ;
          VMRelease(VA);
          MakeRuleItem(Name,Text, PoolNoForTDBTACTLists, VA, A);
          MarkAsUsed(A)
       END;
    END;
    GetSortRuleName( A^.RuleName^.String, temp ) ;
    MakeRealStringData(temp,A^.SortRuleName);
    A^.FilePos := Pos;
    VMRelease(VA);
END ChangeOverData;

PROCEDURE GetPrevRule(List:    ADDRESS; (* ignored here *)
                  VAR Item: TACTListItem): BOOLEAN;
VAR
   Name:      StrAny;
   tLine1:    StrAny;
   Pos:       HRecPntr;
   Data:      DataItemPntr;
BEGIN
   IF BadRules THEN RETURN FALSE END;
   IF Item.DataVA = NILVirt THEN ProgramErrorAndHalt('NILVirt Item.DataVA in MoveUpRule') END;
   Data := VMAccess(Item.DataVA);
   Pos := Data^.FilePos;
   VMRelease(Item.DataVA);
   REPEAT
      IF NOT GetPrevRecLine(Pos) THEN RETURN FALSE END;
      GetLineData(Pos,tLine1);
   UNTIL (tLine1[0] <> 0C) AND (tLine1[0] <> ASCII.ht) AND (tLine1[0] <> ' ');

   IF NOT GetRuleLines(Pos,Name,tLine1) THEN
      ProgramErrorAndHalt('Unexpected bad GetRuleLines in MoveDnRule')
   END;
   ChangeOverData(Item.DataVA,Pos,Name,tLine1);
   RETURN TRUE;
END GetPrevRule;

PROCEDURE GetNextRule(List:    ADDRESS; (* ignored here *)
                  VAR Item: TACTListItem): BOOLEAN;
VAR
   Name:      StrAny;
   tLine1:    StrAny;
   Pos:       HRecPntr;
   Data:      DataItemPntr;
BEGIN
   IF BadRules THEN RETURN FALSE END;
   IF Item.DataVA = NILVirt THEN ProgramErrorAndHalt('NILVirt Item.DataVA in MoveDnRule') END;
   Data := VMAccess(Item.DataVA);
   Pos := Data^.FilePos;
   VMRelease(Item.DataVA);
   REPEAT
      IF NOT GetNextRecLine(Pos) THEN RETURN FALSE END;
      GetLineData(Pos,tLine1);
   UNTIL (tLine1[0] <> 0C) AND (tLine1[0] <> ASCII.ht) AND (tLine1[0] <> ' ');

   IF NOT GetRuleLines(Pos,Name,tLine1) THEN
      ProgramErrorAndHalt('Unexpected bad GetRuleLines in MoveDnRule')
   END;
   ChangeOverData(Item.DataVA,Pos,Name,tLine1);
   RETURN TRUE;
END GetNextRule;

PROCEDURE GetFirstRule(List:    ADDRESS; (* ignored here *)
                   VAR Item: TACTListItem): BOOLEAN;
VAR
   Name:      StrAny;
   tLine1:    StrAny;
   Pos:       HRecPntr;
BEGIN
    IF BadRules THEN
       IF Item.DataVA <> NILVirt THEN DisposeDataItem(Item.DataVA) END;
       RETURN FALSE
    END;
    Pos.Rec := 0; Pos.Idx := 0;
    IF NOT GetRuleLines(Pos,Name,tLine1) THEN
       BadRules := TRUE;
       IF Item.DataVA <> NILVirt THEN DisposeDataItem(Item.DataVA) END;
       RETURN FALSE;
    END;
    Pos.Rec := 0; Pos.Idx := 0;
    ChangeOverData(Item.DataVA,Pos, Name,tLine1);
    RETURN TRUE;
END GetFirstRule;

PROCEDURE GetLastRule(List:    ADDRESS; (* ignored here *)
                  VAR Item: TACTListItem): BOOLEAN;
VAR
   Name:      StrAny;
   tLine1, tLine2:   StrAny;
   Pos:       HRecPntr;
   Data:      DataItemPntr;
BEGIN
    IF BadRules THEN
       IF Item.DataVA <> NILVirt THEN DisposeDataItem(Item.DataVA) END;
       Data := NIL;
       RETURN FALSE;
    END;
    Pos.Rec := NoRuleRecs-1; Pos.Idx := LastRulePos;
    GetLineData(Pos,tLine1);
    WHILE (tLine1[0] = 0C) OR (tLine1[0] = ASCII.ht) OR (tLine1[0] = ' ') DO
       IF NOT GetPrevRecLine(Pos) THEN
          BadRules := TRUE;
          IF Item.DataVA <> NILVirt THEN DisposeDataItem(Item.DataVA) END;
          Data := NIL;
          RETURN FALSE;
       END;
       GetLineData(Pos,tLine1);
    END;
    IF NOT GetRuleLines(Pos,Name,tLine1) THEN
       BadRules := TRUE;
       IF Item.DataVA <> NILVirt THEN DisposeDataItem(Item.DataVA) END;
       RETURN FALSE;
    END;
    ChangeOverData(Item.DataVA, Pos, Name,tLine1);
    RETURN TRUE;
END GetLastRule;

PROCEDURE DivideRange(Low,High: HRecPntr;
                  VAR Result: HRecPntr);
   VAR
     LowC,HighC,MiddleC:  LONGCARD;
BEGIN
   LowC := VAL(LONGCARD,Low.Rec) * VAL(LONGCARD,HyperLength) +
           VAL(LONGCARD,Low.Idx);
   HighC := VAL(LONGCARD,High.Rec) * VAL(LONGCARD,HyperLength) +
           VAL(LONGCARD,High.Idx);
   MiddleC := (LowC + HighC) DIV VAL(LONGCARD,2);
   Result.Rec := VAL(CARDINAL,(MiddleC DIV VAL(LONGCARD,HyperLength)));
   Result.Idx := VAL(CARDINAL,(MiddleC MOD VAL(LONGCARD,HyperLength)));
END DivideRange;

PROCEDURE FindNearestRule(VAR Pos:  HRecPntr;
                          VAR VA:   VirtAddr (* DataItem VA *));
VAR
   tLine1:   StrAny;
   Name:     ARRAY[0..40] OF CHAR;
   A:        DataItemPntr;
BEGIN
   GetLineData(Pos,tLine1);
   WHILE (tLine1[0] = 0C) OR (tLine1[0] = ASCII.ht) OR (tLine1[0] = ' ') DO
      IF (Pos.Idx = 0) AND (Pos.Rec = 0) THEN
         tLine1[0] := 'A'
      ELSE
         IF NOT GetPrevRecLine(Pos) THEN
            ProgramErrorAndHalt('Unexpected Beginning of File In FindNearestRuleName')
         END;
         GetLineData(Pos,tLine1);
      END;
   END;
   IF NOT GetRuleLines(Pos,Name,tLine1) THEN
      BadRules := TRUE;
      IF VA <> NILVirt THEN DisposeDataItem(VA) END;
      RETURN;
   END;
   ChangeOverData(VA,Pos,Name,tLine1);
END FindNearestRule;

PROCEDURE FindRuleItem(List:    ADDRESS; (* ignored here *)
                       Data:    VirtAddr; (* as DataItem VA *)
                   VAR Item: TACTListItem): BOOLEAN;
VAR Pntr:   DataItemPntr;
    rslt:   BOOLEAN;
BEGIN
   Pntr := VMAccess(Data);
   rslt := Pntr^.DataType = RuleType;
   VMRelease(Data);
   IF NOT rslt THEN RETURN FALSE END;
   Item.DataVA := Data;
   RETURN TRUE;
END FindRuleItem;

PROCEDURE RuleItemDataPresent(List:   ADDRESS; (* not used *)
                              Type:   ItemType;
                              Pos:    HRecPntr;
                          VAR Item:   TACTListItem): BOOLEAN;
BEGIN
   IF Type <> RuleType THEN RETURN FALSE END;

   IF BadRules THEN
      IF Item.DataVA <> NILVirt THEN DisposeDataItem(Item.DataVA) END;
      RETURN FALSE
   END;
   FindNearestRule(Pos,Item.DataVA);
   RETURN TRUE;
END RuleItemDataPresent;

PROCEDURE FindRuleFromString(Name:   ARRAY OF CHAR; (* Sort Format *)
                             Type:   ItemType;
                             List:   ADDRESS; (* ignored *)
                         VAR Item:   TACTListItem): BOOLEAN;
VAR
    UIdx, LIdx:    HRecPntr;
    IIdx:          HRecPntr;
    UItem,LItem,IItem: TACTListItem;
    ICmp:          INTEGER;
    dummy:         BOOLEAN;
    Pntr:          DataItemPntr;
BEGIN
   IF Type <> RuleType THEN RETURN FALSE END;
   IF Item.DataVA <> NILVirt THEN DisposeDataItem(Item.DataVA) END;
   IF BadRules THEN RETURN FALSE END;

   LIdx.Rec := 0; LIdx.Idx := 0;
   UIdx.Rec := NoRuleRecs - 1; UIdx.Idx := LastRulePos;
   LItem.DataVA := NILVirt; UItem.DataVA := NILVirt;
   FindNearestRule(LIdx,LItem.DataVA);
   FindNearestRule(UIdx,UItem.DataVA);
   LOOP
      IF (UIdx.Rec < LIdx.Rec) OR
	 ((UIdx.Rec = LIdx.Rec) AND (UIdx.Idx < LIdx.Idx)) THEN
          Item := UItem;
          DisposeDataItem(LItem.DataVA);
          dummy := GetNextRule(List,Item); (* move to next item if any there *)
          RETURN FALSE;
      ELSE
         DivideRange(LIdx,UIdx,IIdx);
         IItem.DataVA := NILVirt;
         FindNearestRule(IIdx,IItem.DataVA);
         Pntr := VMAccess(IItem.DataVA);
         ICmp := Str.Compare(Name,Pntr^.SortRuleName^.String);
         VMRelease(IItem.DataVA);
         IF ICmp < 0 THEN
            IF NOT GetPrevRule(List,IItem) THEN
               Item := IItem;
               DisposeDataItem(UItem.DataVA);
               DisposeDataItem(LItem.DataVA);
               RETURN FALSE
            END;
            DisposeDataItem(UItem.DataVA);
            UItem := IItem;
	    Pntr := VMAccess(IItem.DataVA);	(* *LP* *)
	    UIdx := Pntr^.FilePos;
	    VMRelease(IItem.DataVA);
         ELSIF ICmp > 0 THEN
            IF NOT GetNextRule(List,IItem) THEN
               Item := IItem;
               DisposeDataItem(UItem.DataVA);
               DisposeDataItem(LItem.DataVA);
               RETURN FALSE
            END;
            DisposeDataItem(LItem.DataVA);
            LItem := IItem;
	    Pntr := VMAccess(IItem.DataVA);	(* *LP* *)
	    LIdx := Pntr^.FilePos;
	    VMRelease(IItem.DataVA);
         ELSE
            Item := IItem;
            DisposeDataItem(UItem.DataVA);
            DisposeDataItem(LItem.DataVA);
            RETURN TRUE;
         END;
      END
   END;
END FindRuleFromString;

PROCEDURE AddNewRuleToFile(Name:  ARRAY OF CHAR; (* in Int Encoding *)
                       VAR RuleText: ARRAY OF CHAR);
VAR
   NewName:     ARRAY[0..40] OF CHAR;
   RList:       TACTList;
   Item:        TACTListItem;
   A:           DataItemPntr;
   SortName:    ARRAY[0..40] OF CHAR;
   FID:         FIO.File;
   FIDIn:       FIO.File;
   StopBefore:  LONGCARD;
   From:        LONGCARD;
   FileLen:     LONGCARD;
   FileExists:  BOOLEAN;
   ch2:         ARRAY[0..1] OF CHAR;
   i:           CARDINAL;

PROCEDURE WriteOutRule;
VAR
   tStr:    StrAny;
   tStr2:   StrAny;
   AL,NS:   CARDINAL;
   LD:      XlateStrAny;
   ED:      BOOLEAN;
   cm:      CurrentModeType;
BEGIN
   TrimBlanks(RuleText,RuleText);
   Str.Copy(tStr, Name);
   IF RuleText[0] <> 0C THEN
      Str.Append(tStr,'   ');
      Str.Append(tStr,RuleText (*==> tStr *) )
   END;
   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine(Int2File,'?',tStr,cm, AL,LD,NS,ED,tStr2);
   FIO.WrStr(FID,tStr2);
   FIO.WrLn(FID);
END WriteOutRule;

PROCEDURE HRecPntr2LONGCARD(HRec:  HRecPntr): LONGCARD;
BEGIN
   RETURN VAL(LONGCARD,HRec.Rec) * VAL(LONGCARD,HyperLength)
          + VAL(LONGCARD,HRec.Idx);
END HRecPntr2LONGCARD;

PROCEDURE FailCreate(VAR Name : ARRAY OF CHAR) : BOOLEAN ;
   VAR
	res	: CARDINAL;
	MsgStr	: StrAny;
   BEGIN
	res := FIO.IOresult();
	IF res <> OK THEN
	   IOErrorMessage(res,MsgStr);
	   (*  RES OLD MSG 25  <--- from UTILSTWO.MOD
	   File "%0": %1
	   *)
	   MsgString(Name,0);
	   MsgString(MsgStr,0);
	   PutResError( (*RES REM INS*) 25 );
	   RETURN FALSE ;
	END;
	RETURN TRUE;
   END FailCreate;

PROCEDURE OpenNewFile() : BOOLEAN ;
BEGIN
   RemoveExtension(RuleFileInfo.FileName,NewName);
   IF NOT StandardizeFileName(NewName,'.$$$') THEN
      ProgramErrorAndHalt('Unexpected error standardizing NewName')
   END;
   FID := FIO.Create(NewName);
   RETURN FailCreate(NewName) ;
END OpenNewFile;

PROCEDURE CopyRange(From,To: LONGCARD);
TYPE
   dataptr = POINTER TO ARRAY[0..MAX(CARDINAL)-1] OF CHAR;
VAR
   i:       LONGCARD;
   sz1,sz2: CARDINAL;
   size:    LONGCARD;
   step:    LONGCARD;
   dp:      dataptr;
   hpsize:  LONGCARD;
BEGIN
   size := To - From;
   IF size = 0 THEN RETURN END;

   (* the following code only works with JPI's storage module *)

   step := size;
   IF step > VAL(LONGCARD,MAX(CARDINAL)) THEN
      step := VAL(LONGCARD,MAX(CARDINAL))
   END;
   hpsize := VAL(LONGCARD, Storage.HeapAvail(Storage.MainHeap)) * 16;
   IF step > hpsize THEN
      step := hpsize ;
   END;
   Storage.ALLOCATE(dp,VAL(CARDINAL,step));

   FIO.Seek(FIDIn,From);
   sz1 := VAL(CARDINAL,step);
   i := From;
   WHILE i < To DO;
      IF i+step > To THEN
         (* doing last copy step, only partial file read needed *)
         sz1 := VAL(CARDINAL,size MOD step);
      END;
      sz2 := FIO.RdBin(FIDIn,dp^,sz1);
      FIO.WrBin(FID,dp^,sz2);
      INC(i,step);
   END;
   Storage.DEALLOCATE(dp,VAL(CARDINAL,step));
END CopyRange;

PROCEDURE RenameFiles;
VAR   bkup:    ARRAY[0..50] OF CHAR;
BEGIN
   FIO.Close(FIDIn);
   FIO.Close(FID);

(* following code supports a maintained backup version of the rule file
   if this is wanted, remove comments, and comment out following IF group j.b.

   RemoveExtension(RuleFileInfo.FileName,bkup);
   IF NOT StandardizeFileName(bkup,'.BKR') THEN
      ProgramErrorAndHalt('Unexpected error standardizing backup name')
   END;
   IF FIO.Exists(bkup) THEN FIO.Erase(bkup) END;
   FIO.Rename(RuleFileInfo.FileName,bkup);
*)
   IF FIO.Exists(RuleFileInfo.FileName) THEN
      FIO.Erase(RuleFileInfo.FileName)
   END;
   FIO.Rename(NewName,RuleFileInfo.FileName);
END RenameFiles;

PROCEDURE GetRealBeginning(Item: TACTListItem): LONGCARD;
VAR
   tpos:    LONGCARD;
   ch:      CHAR;
   sz:      CARDINAL;
   A:       DataItemPntr;
BEGIN
   A := VMAccess(Item.DataVA);
   tpos := HRecPntr2LONGCARD(A^.FilePos);
   VMRelease(Item.DataVA);
   FIO.Seek(FIDIn,tpos);
   REPEAT
      ch := ' ';
      sz := FIO.RdBin(FIDIn,ch,1);
      INC(tpos);
   UNTIL (ch <> ASCII.cr) AND (ch <> ASCII.lf);
   RETURN tpos - VAL(LONGCARD,1);
END GetRealBeginning;

BEGIN
   IF NOT StartUpRuleFile(FileExists) THEN
      IF NOT FileExists THEN
         FID := FIO.Create(RuleFileInfo.FileName);
         IF NOT FailCreate(RuleFileInfo.FileName) THEN  RETURN  END ;
         WriteOutRule;
         FIO.Close(FID)
      ELSE
         ProgramErrorAndHalt('Bad situation in AddNewRuleToFile')
      END;
   ELSE
      FIDIn := FIO.Open(RuleFileInfo.FileName);
      FileLen := FIO.Size(FIDIn);
      GetSortRuleName( Name, SortName ) ;

      Item.DataVA := NILVirt;
      RList := InitializeRuleList();
      IF FindRuleFromString(SortName, RuleType, RList, Item) THEN
         StopBefore := GetRealBeginning(Item);
         IF NOT GetNextRule(RList, Item) THEN (* replacing last entry *)
            DisposeDataItem(Item.DataVA);
            CloseDownRuleFile;
            FID := FIDIn;
            FIO.Seek(FID,StopBefore - VAL(LONGCARD,1));
            FIO.Truncate(FID);
            WriteOutRule;
            FIO.Close(FID);
            RETURN;
         ELSE
            From := GetRealBeginning(Item);
         END;
      ELSE
         A := VMAccess(Item.DataVA);
         IF Str.Compare(SortName,A^.SortRuleName^.String) > 0 THEN
         (* appending after last entry *)
            DiscardList(RList);
            DisposeDataItem(Item.DataVA);
            CloseDownRuleFile;
            FID := FIDIn;
            FIO.Seek(FID,FileLen - VAL(LONGCARD,2));
            i := FIO.RdBin(FID,ch2,2);
            i := 1;
            IF ch2[1] = 036C (* ^Z *) THEN
               FIO.Seek(FID,FileLen - VAL(LONGCARD,1));
               FIO.Truncate(FID);
               i := 0
            END;
            IF ((ch2[i] <> ASCII.lf)) AND (ch2[i] <> ASCII.cr) THEN
               FIO.WrLn(FID)
            END;
            WriteOutRule;
            FIO.Close(FID);
            RETURN;
         ELSE
            StopBefore := GetRealBeginning(Item);
            From := StopBefore;
         END;
         VMRelease(Item.DataVA);
      END;
      DiscardList(RList);
      DisposeDataItem(Item.DataVA);
      CloseDownRuleFile;

      (* do insert by copying up to insertion point, writing new records
      and doing copy after insertion point to new file *)

      IF OpenNewFile() THEN
	 CopyRange(VAL(LONGCARD,0),StopBefore);
	 WriteOutRule;
	 CopyRange(From,FileLen+1);
	 RenameFiles;
      END ;
   END;
END AddNewRuleToFile;

PROCEDURE InitializeRuleList(): TACTList;
VAR TList:   TACTList;
BEGIN
   NEW(TList);
   WITH TList^ DO
      LDataSize := SIZE(TACTListData);
      BaseData := ADR(OfficialRuleListData);
      Type := RuleList;
   END;
   RETURN TList;
END InitializeRuleList;


BEGIN
   WITH RuleFileInfo DO
      FileName := '';
      RuleName := '';
   END;
   RuleFileOpen := FALSE;
   FirstTimeMsg := TRUE;
   WITH OfficialRuleListData DO
      NewItemProc :=      GenericNewListItem;
      CopyListItemProc := GenericCopyListItem;
      DispListItemProc := GenericDisposeListItem;
      DisposeListProc :=  GenericDisposeList;
      GetItemDataProc :=  GenericGetItemData;
      ReleaseItemProc :=  GenericReleaseItemHold;
      GetFirstItemProc := GetFirstRule;
      GetLastItemProc  := GetLastRule;
      GetNextItemProc :=  GetNextRule;
      GetPrevItemProc :=  GetPrevRule;
      FindItemProc :=     FindRuleItem;
      ItemDataPresProc := RuleItemDataPresent;
      FindFromStrProc :=  FindRuleFromString;
   END;
END RuleListModule.
