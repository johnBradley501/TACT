IMPLEMENTATION MODULE DistDisplay;
(* copyright (c) 1989-96 John Bradley, Geoffrey Rockwell, Lidio Presutti, University of Toronto *)

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


(*V1=Production *)

IMPORT Str, ASCII, MATHLIB;
IMPORT WordBase, BitOps ;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteChar, SWriteLongCard;
FROM HyperDataModel IMPORT HLogDataType;
FROM Utils IMPORT Beep, ConstStr;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt;
FROM ListData IMPORT
  (* types *) ItemType, DataItemPntr,
  (* procs *) CompareDataItems;
FROM ListUtils IMPORT MakePosList;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, CopyListItem,
              DiscardList, FindItem, GetItemData, GetFirstItem,
              GetLastItem, GetNextItem, GetPrevItem;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, InsertListItem;
FROM DBData IMPORT
    (* vars  *) BeginType, EndTokenRec, EndTokenIdx, FolioID, NoTokensInDB;
FROM TokenBase IMPORT
  (* procs *) GetTokenNo;
FROM HyperBase IMPORT
  (* Types *) HRecPntr,
  (* Procs *) CompareHRecs;
FROM DisplayDialog IMPORT
  (* type *) DisplayType, DisplayDataType,DistType, DistDataType,
  (* vars *) DisplayData;
FROM PositionManagement IMPORT
  (* types *) PositionItem,
  (* procs *) GetPosData, FirstDisplayItem, NextMainItem,
              LastDisplayItem, CopyDisplayItem, NextDisplayItem,
              PrevDisplayItem, FindDisplayItem, DiscardDisplayItem,
              InitialDisplayItem;
FROM MainLists IMPORT
  (* const*) PoolNoForDistDispSpace,
  (* types*) PosListStatusType,
  (* vars *) SelectedList, ListByPosition, SelectedListPos, SelectedListEmpty,
             PosListStatus;
FROM RefValBase IMPORT
  (* procs *) GetLogDataForToken, GetLogDataIntStr, CreateRef;
FROM ResMessages IMPORT
   (*proc*)  GetResMessage, PutResError, PutResWarning, PutResMessage,
		MsgString, MsgCard, MsgLongInt ;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) GetType, FreeTypeHandle;
FROM Translations IMPORT XlateLine, XFileType, XlateTablePointer, XWrNXlate,
           XlateStrAny, CurrentModeType, IntTab, TabInfo, TabType,
           WriteWithTabs, XWrStr, XWrLn;
FROM GlobalDefs IMPORT StrAny;
FROM TACTDataServices IMPORT GetTDBTokenData, VirtToTACTList, TACTListToVirt;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMAccess, VMMarkChanged, VMRelease,
     VMModify, GetSpace, FreePool;

CONST
   MaxDistID=40;
   MaxCountSize=5;
(* HistChar=036C; (* Internal Character set: "BlockChar" *) *)   HistChar=036C; (* Internal Character set: "BlockChar" *)
(*RES OLD MSG 88
Total: %0, Total in Database: %1.
*)
   TotalRes = (*RES REM INS*) 88 ;

TYPE
   LineRecPntr = POINTER TO LineListRecord ;
   LineListRecord = RECORD
       CASE : BOOLEAN OF (* these two won't both be present at the same time *)
          TRUE:  LogID:       HLogDataType;
        | FALSE: WordPntr:    HRecPntr;
       END;
       Next,
       Prev:	     VirtAddr; (* to LineRecRecord *)
       LineListVA:  VirtAddr;
       NumberInLine:CARDINAL;
       NoWords:     LONGCARD;
       LineID:      ARRAY[0..255] OF CHAR;
   END;

CONST
   LLRecBase = SIZE(LineListRecord) - 255;

VAR
   HistOffset:   CARDINAL;
   LinesBefore:  CARDINAL;
   LinesAfter:   CARDINAL;
   FirstLineVA,
   LastLineVA,
   CurrLineVA,
   DistVA:       VirtAddr; (* to LineRecRecord *)
   CurrLineRec:  LineRecPntr;
   MaxLineLen:   CARDINAL;
   NoLinesUsed:  CARDINAL;
   OldDistXSize: CARDINAL;
   (*   OldDistYSize: CARDINAL; 	*LP* *)
   CurrentLine:  CARDINAL;
   CurrentItemNo:CARDINAL;
   CurrentItem:  PositionItem;
   CurrentLineList: TACTList;
   WorkingList: TACTList;
   CurrentMoved: BOOLEAN;
(* D:            CARDINAL; *)
   CurHist:      CHAR;
   TotalWordsInList : CARDINAL ;	(* <--- LONGINT ??? *)
   MaxTokenNo:     LONGINT;

PROCEDURE AllocLineRec( VAR DataVA  : VirtAddr (* to LineRecRecord *);
                        VAR DataPtr : LineRecPntr;
                            PrevPtr : VirtAddr (* to LineRecRecord *);
                            Name    : ARRAY OF CHAR ) ;
VAR tList : TACTList;
BEGIN
   DataPtr := GetSpace(LLRecBase + Str.Length(Name), PoolNoForDistDispSpace, DataVA);
	WITH DataPtr^ DO
		tList := NewMemoryList(PoolNoForDistDispSpace);
		TACTListToVirt( tList, PoolNoForDistDispSpace, LineListVA );
		DiscardList( tList ) ;
		NumberInLine := 0 ;
		Prev := PrevPtr ;
		Next := NILVirt ;
      Str.Copy(LineID, Name);
	END ;
   END AllocLineRec ;

PROCEDURE InitializeData(DD: DistDataType);
VAR
   CurTokenNo:     LONGINT;
   Slot:           CARDINAL;
   MaxTokenPntr:   HRecPntr;
   CurPos:         PositionItem;
   TempListPos:    PositionItem;
   Pos,i,i2,j:	   CARDINAL;
   StartWord:      LONGINT;
   EndWord:        LONGINT;
   WordRange:      LONGINT;
   LongIntNoSlots: LONGINT;
   Type:           ItemType;
   TokenPntr:      DataItemPntr;
   TokenVA:        VirtAddr;
   TypeVA:         VirtAddr;
   CatVA:          VirtAddr;
   TempVA:	   VirtAddr;
   LineList:	   TACTList;

PROCEDURE PercentToWord(Prcnt: CARDINAL; VAR Word:  LONGINT);
   BEGIN
	Word := VAL(LONGINT,Prcnt) * MaxTokenNo DIV VAL(LONGINT,100);
   END PercentToWord;

PROCEDURE InitDistByPos;
VAR
  PrevL:    LineRecPntr;
  CurL:     LineRecPntr;
  PrevVA:   VirtAddr;
  id:       ARRAY[0..10] OF CHAR;

PROCEDURE BuildID( No1, No2 : CARDINAL; VAR Txt: ARRAY OF CHAR );
VAR pos:   CARDINAL;
BEGIN
   Txt[0] := 0C;
   pos := 0;
   SWriteCard(Txt,pos,No1,0);
   SWriteChar(Txt,pos,'-',0);
   SWriteCard(Txt,pos,No2,0);
   SWriteChar(Txt,pos,'%',0);
END BuildID;

BEGIN (* InitDistByPos *)
   MaxTokenPntr.Rec := EndTokenRec;
   MaxTokenPntr.Idx := EndTokenIdx;
   GetTokenNo(MaxTokenPntr,MaxTokenNo);
   WITH DD DO
      PercentToWord(Start,StartWord);
      PercentToWord(End,EndWord);
      WordRange := EndWord - StartWord + VAL(LONGINT,1);
      NoLinesUsed := (End-Start+ByValue-1) DIV ByValue;
   END;
   WITH DD DO
      i := Start;
      i2 := End-ByValue;
      PrevVA := NILVirt ;
      PrevL := NIL;
      WHILE i <= i2 DO
         BuildID(i,i + ByValue, id);
         AllocLineRec( DistVA, CurL, PrevVA, id ) ;
	 IF PrevL <> NIL THEN
            PrevL^.Next := DistVA;
            VMRelease(PrevVA);
         END;
         IF FirstLineVA = NILVirt THEN FirstLineVA := DistVA END;
         PrevVA := DistVA;
         PrevL := CurL;
         INC(i,ByValue);
      END;
      LastLineVA := PrevVA ;
      VMRelease(PrevVA);
   END;
   LongIntNoSlots := VAL(LONGINT,NoLinesUsed);
END InitDistByPos;

PROCEDURE AddToSlot( VAR DistDataVA :   VirtAddr (* to LineRecRecord *) ;
                         DIVA:          VirtAddr (* to DataItem *) );
   VAR DistDataNode:   LineRecPntr;
   BEGIN
        DistDataNode := VMModify(DistDataVA);
	WITH DistDataNode^ DO
	   VirtToTACTList( LineListVA, LineList ) ;
	   IF InsertListItem(DIVA,LineList) THEN
	      INC(NumberInLine);
	      IF NumberInLine > MaxLineLen THEN MaxLineLen := NumberInLine END;
	   END;
	   DiscardList(LineList); (* get rid real reference *)
	END;
        VMRelease(DistDataVA);
   END AddToSlot;

PROCEDURE InsertByPos;
VAR  DistData:  LineRecPntr;
BEGIN
	GetTokenNo(TokenPntr^.FilePos,CurTokenNo);
	IF (CurTokenNo <= EndWord) AND (CurTokenNo >= StartWord) THEN
	   Slot := VAL(CARDINAL, (CurTokenNo - StartWord) * LongIntNoSlots DIV WordRange);
	   (* position to proper Linked record -- sinced it was allocated previously *)
	   DistVA := FirstLineVA ;
	   FOR i := 1 TO Slot DO
		DistData := VMAccess(DistVA);
		TempVA := DistVA ;
		DistVA := DistData^.Next ;
                VMRelease( TempVA );
		IF DistVA = NILVirt THEN
		   ProgramErrorAndHalt('Error in InsertByPos')
		END ;
	   END ;
	   AddToSlot(DistVA, TokenVA);
	END;
END InsertByPos;

PROCEDURE HLogCompare(Log1 : HLogDataType; Log2 : HLogDataType): INTEGER;
BEGIN
	IF Log1.StructID <> Log2.StructID THEN
	   ProgramErrorAndHalt('StructIDs Dont Match')
	END;
	IF Log1.StructID > 0 THEN (* Log type is a Count *)
	   IF Log1.Count < Log2.Count THEN RETURN 1
	   ELSIF Log1.Count = Log2.Count THEN RETURN 0
	   ELSE RETURN -1 END;
	ELSE
	   IF Log1.SRecNo < Log2.SRecNo THEN RETURN 1
	   ELSIF Log1.SRecNo > Log2.SRecNo THEN RETURN -1
	   ELSE
	      IF Log1.SRecPos < Log2.SRecPos THEN RETURN 1
	      ELSIF Log1.SRecPos = Log2.SRecPos THEN RETURN 0
	      ELSE RETURN -1 END;
	   END;
	END;
END HLogCompare;

PROCEDURE InsertNewLine( VAR DistDataVA :  VirtAddr; (* to LineListRecord *)
                         VAR DistDataNode: LineRecPntr;
                         VAR txt :         ARRAY OF CHAR;
                             nowords:      LONGCARD);
VAR
	OldLineRec :  LineRecPntr ;
	OldLineVA:    VirtAddr;

PROCEDURE InsertIt(Where: VirtAddr (* to LineListRecord *) );
VAR
	TempLineRec:    LineRecPntr;
BEGIN
(*  Notice Sideffects ----V------------V  j.b. *)
	AllocLineRec( DistDataVA, DistDataNode, Where, txt ) ;
	IF FirstLineVA = NILVirt THEN FirstLineVA := DistDataVA
	ELSIF Where <> NILVirt THEN
	   TempLineRec := VMModify(Where);
	   TempLineRec^.Next := DistDataVA;
	   VMRelease(Where);
	ELSE
	   (* inserting before first line, make note of it *)
	   FirstLineVA := DistDataVA
	END ;
END InsertIt;

BEGIN
	INC(NoLinesUsed);
	IF DistDataVA = NILVirt THEN	(* add it to the end *)
		InsertIt( LastLineVA);
		LastLineVA := DistDataVA ;
	ELSE	(* insert it in between the lists *)
		OldLineVA := DistDataVA;
		OldLineRec := VMModify(OldLineVA) ;	(* remember point to insert before *)
		InsertIt( OldLineRec^.Prev );
		OldLineRec^.Prev := DistDataVA ;
		VMRelease(OldLineVA);
		DistDataNode^.Next := OldLineVA ;
	END ;
	WITH DistDataNode^ DO
	   NumberInLine := 0;
(*	   Str.Copy(LineID,txt); *)
      NoWords := nowords;
	END;
END InsertNewLine;

PROCEDURE InsertByRef;
VAR
	LogData:  HLogDataType;
	HLC:      INTEGER;
	TempName: ARRAY[0..MaxDistID-1] OF CHAR;
	dummy:    BOOLEAN;
	DistData: LineRecPntr;
	Pos:    CARDINAL;
	Side:   CHAR;
        nowords:  LONGCARD;

BEGIN
	GetLogDataForToken(TokenVA,DD.DistRefID,LogData);
	HLC := -1;
	DistVA := FirstLineVA ;
        dummy := TRUE ;
	WHILE (DistVA <> NILVirt) AND (HLC < 0) DO
	   DistData := VMAccess(DistVA);
	   TempVA := DistVA;
	   HLC := HLogCompare(LogData,DistData^.LogID);
	   IF DD.RefOrder AND (HLC > 0) THEN
	      HLC := -1 ; (* m.s. - check whole list for item *)
	   END ;
	   IF (HLC < 0) THEN  DistVA := DistData^.Next END ;
	   VMRelease(TempVA);
	END;
        nowords := 0;
	IF (DistVA = NILVirt) OR (HLC <> 0) THEN (* Item not currently in list *)
	   IF LogData.StructID < 0 THEN (* Log type is a String *)
		GetLogDataIntStr(LogData,TempName,i (* as dummy *), nowords )
	   ELSE
	      IF NOT (VAL(CARDINAL,LogData.StructID) IN FolioID) THEN
		 Str.CardToStr(LONGCARD(LogData.Count),TempName,10,dummy)
	      ELSIF LogData.Count = 0 THEN
		 TempName := '???' ;
	      ELSE
		 Pos := 0;
		 SWriteCard(TempName, Pos, (LogData.Count+1) DIV 2, 0);
		 IF (LogData.Count MOD 2) = 1 THEN Side := 'r'
		 ELSE Side := 'v' END;
		 SWriteString(TempName, Pos, Side, 0);
	      END;
	   END;
	   InsertNewLine( DistVA, DistData, TempName, nowords );
	   DistData^.LogID := LogData;
	   VMRelease(DistVA);
	END;
	AddToSlot( DistVA, TokenVA)
END InsertByRef;

PROCEDURE InsertByType;
VAR
	TypeHPntr: HRecPntr;
	HLC:       INTEGER;
	HeadPtr:   DataItemPntr;
	TempName:  ARRAY[0..MaxDistID-1] OF CHAR;
	TypeHandl: HTypeHandle;
	TempListPos : PositionItem;
	DistData:  LineRecPntr;
	SortTempStr : StrAny;
BEGIN
	IF TokenPntr^.HeadWord = NILVirt THEN
           IF NOT TokenPntr^.TokenDataLoaded THEN
              VMMarkChanged(TokenVA);
              GetTDBTokenData(TokenPntr)
           END;
	   TypeHPntr.Rec := TokenPntr^.TokenFileData.HRecNo + BeginType;
	   TypeHPntr.Idx := ORD(TokenPntr^.TokenFileData.HRecPos);
	ELSE
	   HeadPtr := VMAccess(TokenPntr^.HeadWord);
	   TypeHPntr := HeadPtr^.FilePos;
           VMRelease(TokenPntr^.HeadWord);
	END;
	HLC := -1;
	DistVA := FirstLineVA ;
	WHILE (DistVA <> NILVirt) AND (HLC < 0) DO
	   TempVA := DistVA;
	   DistData := VMAccess(DistVA);
	   HLC := CompareHRecs(DistData^.WordPntr,TypeHPntr);
	   IF HLC < 0 THEN  DistVA := DistData^.Next  END;
	   VMRelease(TempVA);
	END;
	IF (DistVA = NILVirt) OR (HLC <> 0) THEN (* Item not currently in list *)
	   IF TokenPntr^.HeadWord <> NILVirt THEN
	      HeadPtr := VMAccess(TokenPntr^.HeadWord);
	      WordBase.SortToIntWord(HeadPtr^.TypeFileData.Word,TempName);
         VMRelease(TokenPntr^.HeadWord);
	   ELSE
	      GetType(TypeHPntr,TypeHandl);
	      BitOps.UnPack( TypeHandl^^.PackedWord, SortTempStr, WordBase.SortNoBitsPerChar ) ;
	      WordBase.SortToIntWord(SortTempStr,TempName);
	      FreeTypeHandle(TypeHandl);
	   END;
	   InsertNewLine( DistVA, DistData, TempName, 0 );
	   DistData^.WordPntr := TypeHPntr;
      VMRelease(DistVA);
	END;
	AddToSlot( DistVA, TokenVA)
END InsertByType;

BEGIN (* InitializeData *)

   MaxLineLen := 0;
   NoLinesUsed := 0;
   IF DD.Type = DistByPos THEN InitDistByPos END;

   TotalWordsInList := 0 ;
   InitialDisplayItem(CurPos);
   IF NOT FirstDisplayItem(WorkingList,CurPos) THEN
      ProgramErrorAndHalt('No list in InitDispByPos')
   END;
   REPEAT
      GetPosData(CurPos, Type, TokenVA, TypeVA, CatVA);
      IF TokenVA <> NILVirt THEN
         TokenPntr := VMAccess(TokenVA);
         INC( TotalWordsInList );
         CASE DD.Type OF
           DistByPos:  InsertByPos
         | DistByRef,
           NormalizedDist:  InsertByRef
         | DistByType: InsertByType
         ELSE ProgramErrorAndHalt('Bad DistData.Type')
         END;
         VMRelease(TokenVA);
      END;
   UNTIL NOT NextDisplayItem(WorkingList, CurPos);
   DiscardDisplayItem(WorkingList,CurPos);

END InitializeData;

PROCEDURE OutputDistDisplay(VAR file : XFileType);

(* start of OldStyle Dist Display j.b. ...

PROCEDURE OldStyle();
VAR
   ts:         StrAny;
   PrtLine:    StrAny;
   Pos,j:      CARDINAL;
   TabSetting: ARRAY[0..0] OF TabInfo;
   DP:         CARDINAL;
   DistData:   LineRecPntr;
   TempVA:     VirtAddr;
   NoLines:    CARDINAL;

PROCEDURE TruncateIfNecessary;
VAR
   al:		CARDINAL;
   ld:		XlateStrAny ;
   ns:		CARDINAL;
   ed:		BOOLEAN;
   cm:		CurrentModeType;
BEGIN
   cm := file.ModeData;
   XlateLine(file.XP,' ',PrtLine,cm,al,ld,ns,ed,ts) ;
   DEC(ns);
(* WHILE al > DisplayData[Distribution].DistData.MaxDistIDSize DO *)
   WHILE al > MaxDistID DO
      DEC(al,ld[ns].ApprOut);
      DEC(Pos,ld[ns].Int);
      DEC(ns);
   END;
   PrtLine[Pos] := 0C;
   SWriteChar(PrtLine,Pos,IntTab,0)
END TruncateIfNecessary;

BEGIN
   WITH DisplayData[Distribution] DO
(*     D := MaxLineLen DIV (78-HistOffset-4) + 1; *)
		DP := MaxLineLen DIV (78 - HistOffset - 4) + 1; (* was ... DIV 70 *)
   END ;
   WITH TabSetting[0] DO
      Type := Left;
      Pos := MaxDistID + 1;
      FilPat := ' ' ;
   END;

   NoLines := 1 ;
   DistVA := FirstLineVA ;
   WHILE DistVA <> NILVirt DO
      PrtLine := 0C;
      Pos := 0;
      DistData := VMAccess(DistVA);
      WITH DistData^ DO
         SWriteString(PrtLine,Pos,LineID,0);
         TruncateIfNecessary;

         SWriteChar(PrtLine,Pos,'|',0);
         SWriteCard(PrtLine,Pos,NumberInLine,MaxCountSize);
         SWriteChar(PrtLine,Pos,'|',0);
         j := (NumberInLine+DP-1) DIV DP;
         ConstStr(CurHist,j,ts);
         SWriteString(PrtLine,Pos,ts,0);
      END;
      IF NOT WriteWithTabs(file,PrtLine,TabSetting) THEN
		    VMRelease(DistVA);
          RETURN
      END;
      INC( NoLines ) ;
      TempVA := DistVA;
      DistVA := DistData^.Next ;
      VMRelease(TempVA);
   END;
   PrtLine[0] := 0C ; (* same as a blank line *)
   IF NOT WriteWithTabs(file,PrtLine,TabSetting) (*OR CheckAbort()*) THEN
      RETURN
   END;
   Pos := 0 ;
   IF DP > 1 THEN
        SWriteChar(PrtLine, Pos, CurHist, 0);
        SWriteString(PrtLine, Pos, ' = ', 0);
        SWriteCard(PrtLine, Pos, DP, 0);
        SWriteString(PrtLine, Pos, ', ', 0);
   END ;
   MsgCard( TotalWordsInList, 0 ) ;
   GetResMessage( TotalRes, ts ) ;
   SWriteString(PrtLine, Pos, ts, 0);
   IF NOT WriteWithTabs(file,PrtLine,TabSetting) THEN
      RETURN
   END;
END OldStyle;

...end of OldStyle Dist Display j.b. *)

PROCEDURE DoBasicDist();
VAR
   IOR,s:      CARDINAL;
   PrtLine:    StrAny;
   Pos, j:     CARDINAL;
   DP:         CARDINAL;
   DistData:   LineRecPntr;
   TempVA:     VirtAddr;
   ts:         StrAny;

BEGIN
   WITH DisplayData[Distribution] DO
(*     D := MaxLineLen DIV (78-HistOffset-4) + 1; *)
		DP := MaxLineLen DIV (78 - HistOffset - 4) + 1; (* was ... DIV 70 *)
   END ;
   XWrNXlate(file, '<TABLE BORDER>', IOR);
   XWrLn(file, IOR);
   XWrNXlate(file,'<TR><TH>', IOR);
   s := XWrStr(file, DisplayData[Distribution].DistData.DistRefName,IOR);
   XWrNXlate(file,'</TH><TH>#</TH><TH>Graph</TH>', IOR); XWrLn(file,IOR);
(* NoLines := 1 ; *)
   DistVA := FirstLineVA ;
   WHILE DistVA <> NILVirt DO
      PrtLine := 0C;
      Pos := 0;
      DistData := VMAccess(DistVA);
      WITH DistData^ DO
         SWriteString(PrtLine, Pos, 'ú<TRú>ú<TDú>', 0);
         SWriteString(PrtLine,Pos,LineID,0);

         SWriteString(PrtLine,Pos,' ú</TDú>ú<TD ALIGN=RIGHTú> ',0);
         SWriteCard(PrtLine,Pos,NumberInLine,0);
         SWriteString(PrtLine,Pos,' ú</TDú>ú<TDú>ú<TTú>',0);
         j := (NumberInLine+DP-1) DIV DP;
         IF j <> 0 THEN
           ConstStr(CurHist,j,ts);
           SWriteString(PrtLine,Pos,ts,0);
         ELSE
           SWriteString(PrtLine,Pos,'ú&nbsp;',0);
         END;
         SWriteString(PrtLine,Pos,' ú</TTú>ú</TDú>ú</TRú>',0);
      END;
      s := XWrStr(file, PrtLine, IOR); XWrLn(file, IOR);
(*    INC( NoLines ) ; *)
      TempVA := DistVA;
      DistVA := DistData^.Next ;
      VMRelease(TempVA);
   END;
   
   XWrNXlate(file, '</TABLE>', IOR);
   XWrLn(file, IOR);
   XWrNXlate(file, '<P>', IOR);

   Pos := 0 ;
   IF DP > 1 THEN
        SWriteChar(PrtLine, Pos, CurHist, 0);
        SWriteString(PrtLine, Pos, ' = ', 0);
        SWriteCard(PrtLine, Pos, DP, 0);
        SWriteString(PrtLine, Pos, ', ', 0);
   END ;
   MsgCard( TotalWordsInList, 0 ) ;
   MsgLongInt(VAL(LONGINT, NoTokensInDB), 0);
   GetResMessage( TotalRes, ts ) ;
   SWriteString(PrtLine, Pos, ts, 0);
   s := XWrStr(file, PrtLine, IOR); XWrLn(file, IOR);
END DoBasicDist;

PROCEDURE DoNormalizedDist();
VAR
   MaxRatio,wr:   REAL;
   Work:          ARRAY[0..90] OF CHAR;
   OK:            BOOLEAN;
   IOR,s:      CARDINAL;
   PrtLine:    StrAny;
   Pos, j:     CARDINAL;
   DistData:   LineRecPntr;
   TempVA:     VirtAddr;
   ts:         StrAny;
	NoToksInDBLR: LONGREAL;
   NoSelectedToksLR: LONGREAL;
	TokenProb :     LONGREAL ;
	StdDev	 :    LONGREAL ;

PROCEDURE CalcZScore(DistData: LineRecPntr): LONGREAL;
VAR
	ExpectedFreq : LONGREAL ;
BEGIN
   WITH DistData^ DO
      (* Exp. Freq = TypeProb * NoToksInMiniText 		*)
      ExpectedFreq := TokenProb * VAL(LONGREAL, NoWords);
      RETURN (VAL(LONGREAL,NumberInLine) - ExpectedFreq) / StdDev ;
   END;
END CalcZScore ;

BEGIN
   NoToksInDBLR := VAL( LONGREAL, NoTokensInDB ) ;
   NoSelectedToksLR := VAL (LONGREAL, TotalWordsInList);
   TokenProb := NoSelectedToksLR / NoToksInDBLR ;
   StdDev := MATHLIB.Sqrt(NoSelectedToksLR * TokenProb * (1.0-TokenProb)) ;

   XWrLn(file, IOR);
(* XWrNXlate(file, '<TABLE BORDER=0>', IOR); *)
   XWrNXlate(file, '<TABLE BORDER>', IOR);
   XWrLn(file, IOR);
   XWrNXlate(file,'<TR><TH>', IOR);
   s := XWrStr(file, DisplayData[Distribution].DistData.DistRefName,IOR);
   XWrNXlate(file,'</TH><TH>#</TH><TH>Size</TH><TH># / Size</TH><TH>Z-Score</TH><TH>Graph (# / Size)</TH>', IOR);
   XWrLn(file,IOR);
(* NoLines := 1 ; *)
   MaxRatio := 0.0;
   DistVA := FirstLineVA ;
   WHILE DistVA <> NILVirt DO
      DistData := VMAccess(DistVA);
      WITH DistData^ DO
         wr := FLOAT(NumberInLine)/FLOAT(NoWords);
         IF (wr > MaxRatio) THEN MaxRatio := wr; END;
      END;
      TempVA := DistVA;
      DistVA := DistData^.Next ;
      VMRelease(TempVA);
   END;
   DistVA := FirstLineVA ;
   WHILE DistVA <> NILVirt DO
      PrtLine := 0C;
      Pos := 0;
      DistData := VMAccess(DistVA);
      WITH DistData^ DO
         SWriteString(PrtLine, Pos,'ú<TRú>ú<TDú>', 0);
         SWriteString(PrtLine,Pos,LineID,0);

         SWriteString(PrtLine,Pos,'ú</TDú>ú<TD ALIGN=RIGHTú> ',0);
         SWriteCard(PrtLine,Pos,NumberInLine,0);
         SWriteString(PrtLine,Pos,'ú</TDú>ú<TD ALIGN=RIGHTú> ',0);
         SWriteLongCard(PrtLine,Pos,NoWords,0);
         SWriteString(PrtLine,Pos,'ú</TDú>ú<TD ALIGN=RIGHTú> ',0);
         wr := FLOAT(NumberInLine)/FLOAT(NoWords);
         Str.RealToStr(VAL(LONGREAL,wr), 5, TRUE, Work, OK);
         SWriteString(PrtLine,Pos,Work,0);
         SWriteString(PrtLine,Pos,'ú</TDú>',0);
         s := XWrStr(file, PrtLine, IOR); XWrLn(file, IOR); Pos := 0;
         SWriteString(PrtLine,Pos,'ú<TD ALIGN=RIGHTú> ',0);
         Str.FixRealToStr(CalcZScore(DistData), 5, Work, OK);
         SWriteString(PrtLine,Pos,Work,0);
         SWriteString(PrtLine,Pos,'ú</TDú>ú<TDú>ú<TTú>',0);
         j := TRUNC(wr / MaxRatio * 80.0+ 0.5);
         ConstStr(CurHist,j,ts);
         SWriteString(PrtLine,Pos,ts,0);
         SWriteString(PrtLine,Pos,'ú</TTú>ú</TDú>ú</TRú>',0);
      END;
      s := XWrStr(file, PrtLine, IOR); XWrLn(file, IOR);
(*    INC( NoLines ) ; *)
      TempVA := DistVA;
      DistVA := DistData^.Next ;
      VMRelease(TempVA);
   END;
   
   XWrNXlate(file, '</TABLE>', IOR);
   XWrLn(file, IOR);
   MsgCard( TotalWordsInList, 0 ) ;
   MsgLongInt(VAL(LONGINT, NoTokensInDB), 0);
   GetResMessage( TotalRes, PrtLine ) ;
   s := XWrStr(file, PrtLine, IOR); XWrLn(file, IOR);
END DoNormalizedDist;

BEGIN
   IF DisplayData[Distribution].DistData.Type = NormalizedDist THEN
      IF DisplayData[Distribution].DistData.DistRefID >= 0 THEN
         (*RES OLD MSG 604
         TACT ID type "%0" cannot generate a Normalized Distribution.
         *)
         MsgString(DisplayData[Distribution].DistData.DistRefName,0);
         PutResError((*RES REM INS*) 604 );
         RETURN;
      END;
   END;

   FirstLineVA := NILVirt ;
   LastLineVA  := NILVirt ;
   CurrLineVA  := NILVirt ;
   CurHist := '*';
(* HistOffset := DisplayData[Distribution].DistData.MaxDistIDSize + MaxCountSize + 2 (* for 2 "|"s *); *)
   HistOffset := MaxDistID + MaxCountSize + 2 (* for 2 "|"s *);
   IF SelectedListEmpty THEN
      (*RES OLD MSG 248
      There is are no words selected in the Distribution Display to be printed
      or written to a file.
      *)
      PutResError( (*RES REM INS*) 248 );
      RETURN
   END;

   IF DisplayData[Distribution].DistData.RefOrder THEN
      IF PosListStatus = NoPos THEN
         PosListStatus := PosMade;
         MakePosList(SelectedList, ListByPosition);
      END;
      WorkingList := ListByPosition;
   ELSE
      WorkingList := SelectedList;
   END;

   InitializeData(DisplayData[Distribution].DistData);
   IF DisplayData[Distribution].DistData.Type = NormalizedDist THEN
      DoNormalizedDist();
   ELSE DoBasicDist(); END;
END OutputDistDisplay;

END DistDisplay.
