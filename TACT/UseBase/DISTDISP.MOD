IMPLEMENTATION MODULE DistDisplay;

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

(*--------------------------------------------------------------------------*)
(* History:                                                                 *)
(*               `Woe be to whom has to maintain this'                      *)
(*--------------------------------------------------------------------------*)

(*V1=Production *)
(*V2=Empty *)

IMPORT TWB, Str, ASCII;
IMPORT WordBase, BitOps ;
FROM KeyTranslation IMPORT
  (* Const *) IntTab,IntEnhOn, IntEnhOff,
  (* Type  *) TabInfo, TabType,
  (* Procs *) FancyScreenDisplay, WriteScreenField;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteChar;
FROM HyperDataModel IMPORT HLogDataType;
FROM Utils IMPORT Beep, ConstStr;
FROM Windows IMPORT
  (* Const *) RegularAttr, BoldAttr, SpecialAttr,
  (* Procs *) ChangeColorOnScreen ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt;
FROM ScrollMessages IMPORT
   (* type *) ScrollKey;
FROM ListData IMPORT
  (* types *) ItemType, DataItemPntr,
  (* procs *) CompareDataItems;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, CopyListItem,
              DiscardList, FindItem, GetItemData, GetFirstItem,
              GetLastItem, GetNextItem, GetPrevItem;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, InsertListItem;
FROM DBData IMPORT
    (* vars  *) BeginType, EndTokenRec, EndTokenIdx, FolioID;
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
  (* vars *) SelectedList, SelectedListPos, SelectedListEmpty;
FROM RefValBase IMPORT
  (* procs *) GetLogDataForToken, GetLogDataIntStr, CreateRef;
FROM ResMessages IMPORT
   (*proc*)  GetResMessage, PutResError, PutResWarning, PutResMessage,
		MsgString, MsgCard ;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) GetType, FreeTypeHandle;
FROM Translations IMPORT XlateLine, XFileType, XlateTablePointer, XWrNXlate,
           XlateStrAny, CurrentModeType;
FROM PrintModule IMPORT AbortProc, WriteWithTabs, PrintDest, LinesPerPage,
		PrintActionType ;
FROM GlobalDefs IMPORT StrAny;
FROM TACTDataServices IMPORT GetTDBTokenData, VirtToTACTList, TACTListToVirt;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMAccess, VMMarkChanged, VMRelease,
     VMModify, GetSpace, FreePool;

(*<Empty*)

CONST
   MaxNumberOfLines=  25;
   MaxDistID=10;
   MaxCountSize=5;
   HistOffset=MaxDistID + MaxCountSize + 2 (* for 2 "|"s *);
   MinScreenWidth=HistOffset + 12;
   HistChar=036C; (* Internal Character set: "BlockChar" *)
   SelectAttr = SpecialAttr;
(*RES OLD MSG 88
Total: %0.
*)
   TotalRes = (*RES REM INS*) 88 ;

TYPE
   LineRecPntr = POINTER TO LineListRecord ;
   LineListRecord = RECORD
       CASE : BOOLEAN OF (* these two won't both be present at the same time *)
          TRUE:  LogID:       HLogDataType;
        | FALSE: WordPntr:    HRecPntr;
       END;
       LineListVA:  VirtAddr;
       NumberInLine:CARDINAL;
       LineID:      ARRAY[0..MaxDistID-1] OF CHAR;
       Next,
       Prev:	    VirtAddr; (* to LineRecRecord *)
   END;

VAR
   TWBId:        TWB.WinType;
   CurrentTop:   CARDINAL;
   LinesBefore:  CARDINAL;
   LinesAfter:   CARDINAL;
   DisplaySize:  CARDINAL;
   FirstLineVA,
   LastLineVA,
   CurrLineVA,
   DistVA:       VirtAddr; (* to LineRecRecord *)
   CurrLineRec:  LineRecPntr;
   RefDisplayTab: ARRAY[0..0] OF TabInfo;
   ListsMade:    BOOLEAN;
   MaxLineLen:   CARDINAL;
   NoLinesUsed:  CARDINAL;
   OldDistSpecs: DistDataType;
   OldDistXSize: CARDINAL;
   (*   OldDistYSize: CARDINAL; 	*LP* *)
   CurrentLine:  CARDINAL;
   CurrentItemNo:CARDINAL;
   CurrentItem:  PositionItem;
   CurrentLineList: TACTList;
   CurrentMoved: BOOLEAN;
   D:            CARDINAL;
   CurHist:      CHAR;
   OldDistChar:  CHAR;
   TotalWordsInList : CARDINAL ;	(* <--- LONGINT ??? *)
   MaxTokenNo:     LONGINT;

PROCEDURE AllocLineRec( VAR DataVA  : VirtAddr (* to LineRecRecord *);
                        VAR DataPtr : LineRecPntr;
                            PrevPtr : VirtAddr (* to LineRecRecord *) ) ;
   VAR tList : TACTList;
   BEGIN
        DataPtr := GetSpace(SIZE(LineListRecord), PoolNoForDistDispSpace, DataVA);
	WITH DataPtr^ DO
		tList := NewMemoryList(PoolNoForDistDispSpace);
		TACTListToVirt( tList, PoolNoForDistDispSpace, LineListVA );
		DiscardList( tList ) ;
		NumberInLine := 0 ;
		Prev := PrevPtr ;
		Next := NILVirt ;
	END ;
   END AllocLineRec ;

PROCEDURE ClearOutLists;
   VAR
	DistData : LineRecPntr;
	TempVA	 : VirtAddr;
   BEGIN
	ListsMade := FALSE;
	DiscardDisplayItem(SelectedList, CurrentItem);
	DiscardList(CurrentLineList);
        FreePool(PoolNoForDistDispSpace);
	DistVA	    := NILVirt ;
	FirstLineVA := NILVirt ;
	LastLineVA  := NILVirt ;
	CurrentLine := NoLinesUsed + 1 ;
	CurrentTop := CurrentLine ;
   END ClearOutLists;

PROCEDURE DisplayEmptyMessage;
VAR temp:  ARRAY[0..60] OF CHAR;
BEGIN
   WITH DisplayData[Distribution] DO
      TWB.Clear;
      (*RES OLD MSG 187
      You do not have the Distribution Display currently active.
      *)
      GetResMessage( (*RES REM INS*) 187 , temp);
      WriteScreenField(TWBId,0,0,0,temp,RegularAttr,TRUE);
   END;
END DisplayEmptyMessage;

(*Empty>*)

PROCEDURE HandleDistDisplay(KeyInstruction: ScrollKey);
(*<Empty*)
VAR
   Type:           ItemType;
   TokenPntr:      DataItemPntr;
   TokenVA:        VirtAddr;
   TypeVA:         VirtAddr;
   CatVA:          VirtAddr;
   TempVA:	   VirtAddr;
   OldCurrent:     CARDINAL;
   OldTop:         CARDINAL;
   NextLine:	   CARDINAL;
   LineList:	   TACTList;
   ScreenLine:     ARRAY[0..79] OF CHAR;
   TempStr:        ARRAY[0..80] OF CHAR;

   (* these were in InitializeData *)
   CurTokenNo:     LONGINT;
   Slot:           CARDINAL;

PROCEDURE PutUpDisplay;
VAR
   Pos,j,Line:     CARDINAL;
   Slot:           CARDINAL;
   DistData:       LineRecPntr;
BEGIN
   TWB.Clear;
   DistVA := CurrLineVA ;
   Slot := CurrentLine ;
   WHILE (Slot > CurrentTop) AND (DistVA <> NILVirt) DO
        DistData := VMAccess(DistVA);
	TempVA := DistData^.Prev ;
        VMRelease(DistVA);
        DistVA := TempVA;
	DEC( Slot ) ;
   END ;
   IF DistVA = NILVirt THEN DistVA := FirstLineVA END ;
   Line := 1;
   WHILE (Line < DisplaySize) AND (DistVA <> NILVirt) DO
      DistData := VMAccess(DistVA);
      WITH DistData^ DO
         WriteScreenField(TWBId, DisplayData[Distribution].WindInfo.XSize,
                          0,Line,LineID,RegularAttr,FALSE);
         ScreenLine := 0C;
         Pos := 0;
         SWriteChar(ScreenLine,Pos,'|',0);
         SWriteCard(ScreenLine,Pos,NumberInLine,MaxCountSize);
         SWriteChar(ScreenLine,Pos,'|',0);
         j := (NumberInLine+D-1) DIV D;
         ConstStr(CurHist,j,TempStr);
         SWriteString(ScreenLine,Pos,TempStr,0);
      END;
      WITH DisplayData[Distribution] DO
         WriteScreenField(WindID,WindInfo.XSize,MaxDistID,Line,ScreenLine,RegularAttr,FALSE);
      END;
      INC(Line);
      TempVA := DistData^.Next ;
      VMRelease(DistVA);
      DistVA := TempVA;
   END;
END PutUpDisplay;

PROCEDURE InitializeData;
VAR
   MaxTokenPntr:   HRecPntr;
   CurPos:         PositionItem;
   TempListPos:    PositionItem;
   Pos,i,i2,j:	   CARDINAL;
   StartWord:      LONGINT;
   EndWord:        LONGINT;
   WordRange:      LONGINT;
   LongIntNoSlots: LONGINT;

PROCEDURE PercentToWord(Prcnt: CARDINAL; VAR Word:  LONGINT);
   BEGIN
	Word := VAL(LONGINT,Prcnt) * MaxTokenNo DIV VAL(LONGINT,100);
   END PercentToWord;

PROCEDURE InitDistByPos;
VAR
  PrevL:    LineRecPntr;
  CurL:     LineRecPntr;
  PrevVA:   VirtAddr;

PROCEDURE BuildID( No1, No2 : CARDINAL; VAR DistDataNode : LineRecPntr );
    VAR pos:   CARDINAL;
    BEGIN
	WITH DistDataNode^ DO
	     LineID[0] := 0C;
	     pos := 0;
	     SWriteCard(LineID,pos,No1,0);
	     SWriteChar(LineID,pos,'-',0);
	     SWriteCard(LineID,pos,No2,0);
	     SWriteChar(LineID,pos,'%',0);
	END;
    END BuildID;

BEGIN (* InitDistByPos *)
   MaxTokenPntr.Rec := EndTokenRec;
   MaxTokenPntr.Idx := EndTokenIdx;
   GetTokenNo(MaxTokenPntr,MaxTokenNo);
   WITH DisplayData[Distribution].DistData DO
      PercentToWord(Start,StartWord);
      PercentToWord(End,EndWord);
      WordRange := EndWord - StartWord + VAL(LONGINT,1);
      NoLinesUsed := (End-Start+ByValue-1) DIV ByValue;
   END;
   IF NoLinesUsed > MaxNumberOfLines THEN
      (*RES OLD MSG 188
      You have given a very fine division in your Distribution Specifications.
      *)
      PutResWarning( (*RES REM INS*) 188 );
   END;
   WITH DisplayData[Distribution].DistData DO
      i := Start;
      i2 := End-ByValue;
      AllocLineRec( FirstLineVA, PrevL, NILVirt ) ;
      PrevVA := FirstLineVA ;
      WHILE i < i2 DO
         BuildID(i,i + ByValue, PrevL);
	 AllocLineRec( DistVA, CurL, PrevVA ) ;
	 PrevL^.Next := DistVA ;
         VMRelease(PrevVA);
         PrevVA := DistVA;
         PrevL := CurL;
         INC(i,ByValue);
      END;
      BuildID(i,End, PrevL);
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
                         VAR txt :         ARRAY OF CHAR);
    VAR
	OldLineRec :  LineRecPntr ;
	OldLineVA:    VirtAddr;

    PROCEDURE InsertIt(Where: VirtAddr (* to LineListRecord *) );
    VAR
	TempLineRec:    LineRecPntr;
    BEGIN
(*  Notice Sideffects ----V------------V  j.b. *)
	AllocLineRec( DistDataVA, DistDataNode, Where ) ;
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
	   Str.Copy(LineID,txt);
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

    BEGIN
	GetLogDataForToken(TokenVA,DisplayData[Distribution].DistData.DistRefID,LogData);
	HLC := -1;
	DistVA := FirstLineVA ;
        dummy := TRUE ;
	WHILE (DistVA <> NILVirt) AND (HLC < 0) DO
	   DistData := VMAccess(DistVA);
	   TempVA := DistVA;
	   HLC := HLogCompare(LogData,DistData^.LogID);
	   IF DisplayData[Distribution].DistData.RefOrder AND (HLC > 0) THEN
	      HLC := -1 ; (* m.s. - check whole list for item *)
	   END ;
	   IF (HLC < 0) THEN  DistVA := DistData^.Next END ;
	   VMRelease(TempVA);
	END;
	IF (DistVA = NILVirt) OR (HLC <> 0) THEN (* Item not currently in list *)
	   IF LogData.StructID < 0 THEN (* Log type is a String *)
		GetLogDataIntStr(LogData,TempName,i (* as dummy *) )
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
	   InsertNewLine( DistVA, DistData, TempName );
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
	   InsertNewLine( DistVA, DistData, TempName );
	   DistData^.WordPntr := TypeHPntr;
           VMRelease(DistVA);
	END;
	AddToSlot( DistVA, TokenVA)
    END InsertByType;

BEGIN (* InitializeData *)

   IF ListsMade THEN ClearOutLists END;
   OldCurrent := MAX(CARDINAL) ; (* this ensures redisplay *)
   MaxLineLen := 0;
   NoLinesUsed := 0;
   IF DisplayData[Distribution].DistData.Type = DistByPos THEN InitDistByPos END;

   TotalWordsInList := 0 ;
   InitialDisplayItem(CurPos);
   IF NOT FirstDisplayItem(SelectedList,CurPos) THEN
      ProgramErrorAndHalt('No list in InitDispByPos')
   END;
   REPEAT
      GetPosData(CurPos, Type, TokenVA, TypeVA, CatVA);
      IF TokenVA <> NILVirt THEN
         TokenPntr := VMAccess(TokenVA);
         INC( TotalWordsInList );
         CASE DisplayData[Distribution].DistData.Type OF
           DistByPos:  InsertByPos
         | DistByRef:  InsertByRef
         | DistByType: InsertByType
         ELSE ProgramErrorAndHalt('Bad DistData.Type')
         END;
         VMRelease(TokenVA);
      END;
   UNTIL NOT NextDisplayItem(SelectedList, CurPos);
   DiscardDisplayItem(SelectedList,CurPos);
   ListsMade := TRUE;

   WITH DisplayData[Distribution] DO
     D := MaxLineLen DIV (WindInfo.XSize-HistOffset-4) + 1;
     OldDistSpecs := DistData;
     OldDistXSize := WindInfo.XSize ;
     (* OldDistYSize := WindInfo.YSize ;	*LP* *)
   END;
END InitializeData;

PROCEDURE SetHighLight(CLine, CPoint: CARDINAL; Type: TWB.PaletteRange);
    VAR  j : CARDINAL;
    BEGIN
	IF CLine > NoLinesUsed THEN  RETURN  END;
	j := ( (CPoint+D) DIV D ) - 1;
	ChangeColorOnScreen(CARDINAL(Type), j + HistOffset, (CLine+1-CurrentTop), 1);
    END SetHighLight;

PROCEDURE PutUpRefLine(TokenVA : VirtAddr);
VAR
   LP		: CARDINAL;
   TempLen	: CARDINAL;
BEGIN
   TWB.GotoXY(0,0);
   TWB.ClrEol;
   RefDisplayTab[0].Pos := DisplayData[Distribution].WindInfo.XSize - 3 ;
   CreateRef( DisplayData[Distribution].EncodedRefInfo,
	DisplayData[Distribution].EncodedRefLen, TokenVA, TempStr, TempLen,
	DisplayData[Distribution].DisplayWordCountWord ) ;
   ScreenLine[0] := IntEnhOn ;
   LP := 1 ;
   SWriteString(ScreenLine, LP, TempStr, 0);
   ScreenLine[LP] := IntTab ;
   INC( LP ) ;
   IF D > 1 THEN
        SWriteChar(ScreenLine, LP, CurHist, 0);
        SWriteString(ScreenLine, LP, ' = ', 0);
        SWriteCard(ScreenLine, LP, D, 0);
        SWriteString(ScreenLine, LP, ', ', 0);
   END ;
   MsgCard( TotalWordsInList, 0 ) ;
   GetResMessage( TotalRes, TempStr ) ;
   SWriteString(ScreenLine, LP, TempStr, 0);

   FancyScreenDisplay( TWBId,0,0,ScreenLine, RefDisplayTab,FALSE);
END PutUpRefLine;

PROCEDURE DistSpecsChanged(): BOOLEAN;
BEGIN
   WITH DisplayData[Distribution].DistData DO
      IF OldDistSpecs.Type <> Type THEN RETURN TRUE
      ELSIF (OldDistXSize <> DisplayData[Distribution].WindInfo.XSize) THEN
(*	    OR (OldDistYSize <> DisplayData[Distribution].WindInfo.YSize) THEN  *LP* *)
	 RETURN TRUE
      ELSIF Type = DistByPos THEN
         IF OldDistSpecs.Start <> Start THEN RETURN TRUE END;
         IF OldDistSpecs.End <> End THEN RETURN TRUE END;
         IF OldDistSpecs.ByValue <> ByValue THEN RETURN TRUE END;
      ELSIF (Type = DistByRef) AND (OldDistSpecs.RefOrder <> RefOrder) THEN RETURN TRUE ; (* m.s. *)
      ELSE
         IF OldDistSpecs.DistRefID <> DistRefID THEN RETURN TRUE END;

      END;
   END;
   RETURN FALSE
END DistSpecsChanged;

PROCEDURE DoInit ;
VAR
   TheTokenVA : VirtAddr ;
   TokenPntr:      DataItemPntr;

PROCEDURE FindCurrentPoint() : BOOLEAN ;
VAR
   Type:           ItemType;
   DistData:       LineRecPntr;
   TrialPntr:      DataItemPntr;
   TempItem:       TACTListItem;
   TempPItem:      PositionItem;
   TokenVA:        VirtAddr;
   TypeVA:         VirtAddr;
   CatVA:          VirtAddr;

PROCEDURE CleanUp ;
   BEGIN
	DiscardDisplayItem(SelectedList, TempPItem);
	VMRelease(DistVA);
	VMRelease(TheTokenVA);
   END CleanUp ;

BEGIN	(* FindCurrentPoint *)
   InitialDisplayItem(TempPItem);
   CopyDisplayItem(SelectedList,SelectedListPos,TempPItem);
   GetPosData(TempPItem, Type, TheTokenVA, TypeVA, CatVA);
   WHILE TheTokenVA = NILVirt DO
	IF NOT NextDisplayItem(SelectedList, TempPItem) THEN
	   ProgramErrorAndHalt( "Distribution -- unable to initialize." );
	END;
       GetPosData(TempPItem, Type, TheTokenVA, TypeVA, CatVA);
   END;
   CurrentMoved := TRUE;

   CurrentLine := 0;
   DistVA := FirstLineVA ;
   DistData := VMAccess(DistVA);
   IF DistData <> NIL THEN VirtToTACTList( DistData^.LineListVA, LineList )  END;
   WHILE (DistData <> NIL) AND ( (DistData^.NumberInLine = 0) OR
	 (NOT FindItem(LineList, TheTokenVA, TempItem)) ) DO
      TempVA := DistVA;
      INC(CurrentLine) ;
      DistVA := DistData^.Next ;
      VMRelease(TempVA);
      DistData := VMAccess(DistVA);
      DiscardList(LineList); (* get rid real reference *)
      IF DistData <> NIL THEN VirtToTACTList( DistData^.LineListVA, LineList )  END;
   END;
   DisposeListItem(SelectedList,TempItem);
   DiscardList(LineList); (* get rid real reference *)

   IF (CurrentLine >= NoLinesUsed) OR (DistData = NIL) THEN
	DiscardDisplayItem(SelectedList, TempPItem);
	RETURN FALSE
   END;

   TokenPntr := VMAccess(TheTokenVA);
   CurrLineVA := DistVA ;

   IF CurrentLineList <> NIL THEN	(* cleanup memory pointers first *)
	DiscardDisplayItem(SelectedList, CurrentItem);
	DiscardList(CurrentLineList);
   END ;

   WITH DistData^ DO
      VirtToTACTList( LineListVA, CurrentLineList ) ;
      IF NOT FirstDisplayItem(CurrentLineList, CurrentItem) THEN
	 CleanUp ;
	 RETURN FALSE
      END;
      GetPosData(CurrentItem, Type, TokenVA, TypeVA, CatVA);
      CurrentItemNo := 0;
      TrialPntr := VMAccess(TokenVA);
      WHILE CompareDataItems(TrialPntr,TokenPntr) <> 0 DO
	 VMRelease(TokenVA);
         INC(CurrentItemNo);
         IF NOT NextDisplayItem(CurrentLineList, CurrentItem) THEN
	    CleanUp ;
	    RETURN FALSE
	 END;
         GetPosData(CurrentItem, Type, TokenVA, TypeVA, CatVA);
         TrialPntr := VMAccess(TokenVA);
      END;
      VMRelease(TokenVA);
   END;
   CleanUp ;
   RETURN TRUE ;
END FindCurrentPoint;

    BEGIN	(* DoInit *)
	WITH DisplayData[Distribution] DO
	   IF (BlockChar = ' ') OR (BlockChar = 0C) THEN CurHist := HistChar
	   ELSE CurHist := BlockChar
	   END;
	   DisplaySize := WindInfo.YSize;
	END;
	LinesBefore := DisplaySize DIV 4;
	LinesAfter := DisplaySize - LinesBefore;
	IF (NOT ListsMade) OR DistSpecsChanged() OR (CurHist <> OldDistChar) THEN
	    InitializeData
	END;
	OldDistChar := CurHist;
	CurrentTop := MAX(INTEGER) ;  (* force a PutUpDisplay.  Added  *LP* *)
	OldCurrent := MAX(CARDINAL);  (* force a PutUpDisplay.  Added  *LP* *)

	IF NOT FindCurrentPoint() THEN
	   (* unable to syncronize with this display -- adjust the Start/End params *)
	   TokenPntr := VMAccess( TheTokenVA ) ;
	   GetTokenNo(TokenPntr^.FilePos, CurTokenNo);
	   VMRelease( TheTokenVA ) ;

	   Slot := VAL(CARDINAL, (CurTokenNo * 100 DIV MaxTokenNo));
	   WITH DisplayData[Distribution].DistData DO
	      IF Slot < Start THEN
		 Start := Slot DIV ByValue * ByValue
	      ELSIF Slot > End THEN
		 End := (Slot + ByValue - 1) DIV ByValue * ByValue
	      END ;
	   END ;
	   (* now try again -- it has to work!! *)
	   DoInit ;
	END ;
    END DoInit ;

PROCEDURE SetToFrontOfLine( DistDataVA: VirtAddr (* to LineListRecord *);
                            NewLine:    CARDINAL );
VAR
   DistDataNode:  LineRecPntr;
BEGIN
   DistDataNode := VMAccess(DistDataVA);
   CurrentMoved := TRUE;
   CurrentLine := NewLine;
   DiscardDisplayItem(CurrentLineList, CurrentItem);
   DiscardList(CurrentLineList); (* get rid real reference *)
   VirtToTACTList( DistDataNode^.LineListVA, CurrentLineList ) ;
   IF NOT FirstDisplayItem(CurrentLineList, CurrentItem) THEN
      ProgramErrorAndHalt('Problem Finding first item in list');
   END;
   VMRelease(DistDataVA);
   CurrLineVA := DistDataVA ;
   CurrentItemNo := 0;
END SetToFrontOfLine;

PROCEDURE SetToEndOfLine( DistDataVA: VirtAddr (* to LineListRecord *);
                          NewLine:    CARDINAL );
VAR
   DistDataNode:  LineRecPntr;
BEGIN
   DistDataNode := VMAccess(DistDataVA);
   CurrentMoved := TRUE;
   CurrentLine := NewLine;
   DiscardDisplayItem(CurrentLineList, CurrentItem);
   DiscardList(CurrentLineList); (* get rid real reference *)
   VirtToTACTList( DistDataNode^.LineListVA, CurrentLineList ) ;
   IF NOT LastDisplayItem(CurrentLineList, CurrentItem) THEN
      ProgramErrorAndHalt('Problem Finding last item in list');
   END;
   CurrentItemNo := DistDataNode^.NumberInLine-1;
   VMRelease(DistDataVA);
   CurrLineVA := DistDataVA ;
END SetToEndOfLine;

PROCEDURE FindGoodLineDown;
VAR
    DistData:  LineRecPntr;
BEGIN
   DistData := VMAccess(DistVA);
   WHILE (NextLine < NoLinesUsed) AND (DistData <> NIL) AND  (DistData^.NumberInLine = 0) DO
      INC(NextLine) ;
      TempVA := DistVA;
      DistVA := DistData^.Next ;
      VMRelease(TempVA);
      DistData := VMAccess(DistVA);
   END;
   IF DistVA <> NILVirt THEN  VMRelease(DistVA)  END ;
   IF (NextLine >= NoLinesUsed) OR (DistData = NIL) THEN Beep
   ELSE SetToFrontOfLine(DistVA, NextLine) END;
END FindGoodLineDown;

PROCEDURE DoDownKey;
VAR
    DistData:  LineRecPntr;
BEGIN
   NextLine := CurrentLine+1;
   DistData := VMAccess(CurrLineVA);
   DistVA := DistData^.Next ;
   VMRelease(CurrLineVA);
   FindGoodLineDown;
END DoDownKey;

PROCEDURE DoHomeKey;
BEGIN
   NextLine := 0;
   DistVA := FirstLineVA;
   FindGoodLineDown;
END DoHomeKey;

PROCEDURE FindGoodLineUp(): BOOLEAN;
VAR
    DistData	: LineRecPntr;
    rc		: BOOLEAN ;
BEGIN
   DistData := VMAccess(DistVA);
   WHILE (NextLine > 0) AND (DistData <> NIL)  AND (DistData^.NumberInLine = 0)  DO
      DEC(NextLine) ;
      TempVA := DistVA;
      DistVA := DistData^.Prev ;
      VMRelease(TempVA);
      DistData := VMAccess(DistVA);
   END;
   rc := (DistData <> NIL) AND (DistData^.NumberInLine<> 0) ;
   IF DistVA <> NILVirt THEN  VMRelease(DistVA);  END ;
   RETURN rc ;
END FindGoodLineUp;

PROCEDURE DoUpKey;
VAR
    DistData:  LineRecPntr;
BEGIN
   IF CurrentLine = 0 THEN
      Beep;
      RETURN
   END;
   NextLine := CurrentLine-1;
   DistData := VMAccess(CurrLineVA);
   DistVA := DistData^.Prev ;
   VMRelease(CurrLineVA);
   IF FindGoodLineUp() THEN SetToFrontOfLine(DistVA, NextLine)
   ELSE Beep END;
END DoUpKey;

PROCEDURE DoEndKey;
BEGIN
   NextLine := NoLinesUsed - 1;
   DistVA := LastLineVA;
   IF FindGoodLineUp() THEN SetToEndOfLine(DistVA, NextLine)
   ELSE Beep END;
END DoEndKey;

(*Empty>*)

BEGIN	(* HandleDisplay *)
(*<Empty*)
   OldCurrent := CurrentLine;
   CurrentMoved := FALSE;
   TWBId := DisplayData[Distribution].WindID;
   TWB.Use(TWBId);

   IF (DisplayData[Distribution].WindInfo.XSize < MinScreenWidth) THEN
      IF OldDistXSize <> DisplayData[Distribution].WindInfo.XSize THEN
         TWB.Clear;
         (*RES OLD MSG 67
         The Display Screen is too narrow to show the Distribution.
         *)
         PutResError( (*RES REM INS*) 67 );
         OldDistXSize := DisplayData[Distribution].WindInfo.XSize ;
      END;
      Beep;
      RETURN;
   END;

   IF SelectedListEmpty THEN
      IF KeyInstruction = InitKey THEN DisplayEmptyMessage
      ELSIF KeyInstruction <> TermKey THEN Beep END ;
      TWB.SetAutoUpdate(TWBId);
      RETURN
   END;
   TWB.SetManualUpdate(TWBId);
   SetHighLight(CurrentLine, CurrentItemNo,RegularAttr);
   CASE KeyInstruction OF
     InitKey: DoInit ;
   | TermKey,CloseDownKey:
	ClearOutLists;
	RETURN ;
   | UpKey: DoUpKey;
   | DownKey: DoDownKey;
   | HomeKey: DoHomeKey;
   | EndKey:  DoEndKey;
   | RightKey:
      CurrentMoved := TRUE;
      IF NextDisplayItem(CurrentLineList, CurrentItem) THEN
	 INC(CurrentItemNo) ;
      ELSE
	 DoDownKey
      END;
   | LeftKey:
      CurrentMoved := TRUE;
      IF PrevDisplayItem(CurrentLineList, CurrentItem) THEN
	 DEC(CurrentItemNo) ;
      ELSE
	 IF CurrLineVA = FirstLineVA THEN Beep
         ELSE
	    DoUpKey ;
	    SetToEndOfLine(CurrLineVA, CurrentLine) ;
         END;
      END;
   | REndKey:  SetToEndOfLine(CurrLineVA, CurrentLine)
   | LEndKey:  SetToFrontOfLine(CurrLineVA, CurrentLine)
   ELSE Beep;
   END;

   IF OldCurrent <> CurrentLine THEN
      OldTop := CurrentTop;
      IF NoLinesUsed < DisplaySize THEN		(* was "<=" *LP* *)
         CurrentTop := 0
      ELSIF (CurrentLine < LinesBefore + CurrentTop) THEN
         IF CurrentLine < LinesBefore THEN CurrentTop := 0
         ELSE
	    CurrentTop := CurrentLine - LinesBefore ;
	    IF CurrentTop+DisplaySize >= NoLinesUsed THEN	(* added *LP* *)
		CurrentTop := NoLinesUsed - DisplaySize +1
	    END;
	 END;
      ELSIF (CurrentLine >= LinesAfter + CurrentTop) THEN
         CurrentTop := CurrentLine - LinesAfter + 1;
         IF CurrentTop+DisplaySize >= NoLinesUsed THEN
	    CurrentTop := NoLinesUsed - DisplaySize +1
	 END;
      END;
      IF OldTop <> CurrentTop THEN PutUpDisplay END;
   END;

   IF CurrentMoved THEN
      GetPosData(CurrentItem, Type, TokenVA, TypeVA, CatVA);
      PutUpRefLine(TokenVA);
      IF KeyInstruction <> InitKey THEN	(* *LP* don't need to reset with Init *)
	 DiscardDisplayItem(SelectedList,SelectedListPos);
	 IF NOT FindDisplayItem( CurrentLineList, CurrentItem, SelectedList, SelectedListPos) THEN
	    ProgramErrorAndHalt('Could not find corresponding item')
	 END ;
      END ;
   END;

   SetHighLight(CurrentLine, CurrentItemNo,SelectAttr);
   TWB.SetAutoUpdate(TWBId);

(*Empty>*)

END HandleDistDisplay;

PROCEDURE OutputDistDisplay(VAR file : XFileType; CheckAbort : AbortProc);
(*<Empty*)
VAR
   PrtLine:    StrAny;
   bdummy:     BOOLEAN;
   Slot:       CARDINAL;
   Pos,j:      CARDINAL;
   DistData:   LineRecPntr;
   TempVA:     VirtAddr;
   TabSetting: ARRAY[0..0] OF TabInfo;
   ts:         StrAny;
   TempStr:	StrAny;
   DP:          CARDINAL;
   NoLines:    CARDINAL;
   result:     CARDINAL;

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
   WHILE al > MaxDistID DO
      DEC(al,ld[ns].ApprOut);
      DEC(Pos,ld[ns].Int);
      DEC(ns);
   END;
   PrtLine[Pos] := 0C;
   SWriteChar(PrtLine,Pos,IntTab,0)
END TruncateIfNecessary;

(*Empty>*)

BEGIN
(*<Empty*)
   IF SelectedListEmpty THEN
      (*RES OLD MSG 248
      There is are no words selected in the Distribution Display to be printed
      or written to a file.
      *)
      PutResError( (*RES REM INS*) 248 );
      RETURN
   END;
   WITH DisplayData[Distribution] DO
	DP := MaxLineLen DIV (WindInfo.XSize - HistOffset - 4) + 1; (* was ... DIV 70 *)
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
      IF NOT WriteWithTabs(file,PrtLine,TabSetting) OR CheckAbort() THEN
	  VMRelease(DistVA);
          RETURN
      END;
      INC( NoLines ) ;
      IF (PrintDest = ToPrinter) AND (NoLines > LinesPerPage) THEN
         XWrNXlate( file, ASCII.ff, result);
         NoLines := 1 ;
      END ;
      TempVA := DistVA;
      DistVA := DistData^.Next ;
      VMRelease(TempVA);
   END;
   PrtLine[0] := 0C ; (* same as a blank line *)
   IF NOT WriteWithTabs(file,PrtLine,TabSetting) OR CheckAbort() THEN
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
   GetResMessage( TotalRes, TempStr ) ;
   SWriteString(PrtLine, Pos, TempStr, 0);
   IF NOT WriteWithTabs(file,PrtLine,TabSetting) OR CheckAbort() THEN
      RETURN
   END;

(*Empty>*)

END OutputDistDisplay;

PROCEDURE InitializeDistDisplay;
BEGIN
(*<Empty*)
   ListsMade := FALSE;
   WITH OldDistSpecs DO;
      Type := DistByPos;
      Start := 0; End := 0; ByValue := 0;
   END;
   OldDistXSize := 0 ;
   (*   OldDistYSize := 0 ;	*LP* *)
   TotalWordsInList := 0 ;
   CurrentLine := MAX(CARDINAL);
   CurrentLineList := NIL ;
   NoLinesUsed := 0 ;
   InitialDisplayItem (CurrentItem);
   WITH RefDisplayTab[0] DO
      Type := Right;
      FilPat := ' ' ;
   END;
   CurrentTop := MAX(INTEGER) ;
   FirstLineVA := NILVirt ;
   LastLineVA  := NILVirt ;
   CurrLineVA  := NILVirt ;
   OldDistChar := ' ';
(*Empty>*)
END InitializeDistDisplay;

END DistDisplay.
