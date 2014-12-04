IMPLEMENTATION MODULE ColDisplay ;

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

(*V1=Production *)
(*V2=Empty *)

IMPORT Str, ASCII, MATHLIB ;
FROM TWB IMPORT WinType, Clear, SetAutoUpdate, GotoXY, ClrEol,
      SetManualUpdate, Use;
FROM KeyTranslation IMPORT
  (* Const *) IntTab,IntEnhOn, IntEnhOff,
  (* Type  *) TabInfo, TabType,
  (* Procs *) FancyScreenDisplay, WriteScreenField;
FROM StringIO IMPORT  SWriteString, SWriteCard, SWriteChar;
FROM HyperDataModel IMPORT  HLogDataType, HTypeData ;
FROM Utils IMPORT  Beep ;
FROM Windows IMPORT
  (* Const *) RegularAttr, BoldAttr, SpecialAttr,
  (* Procs *) ScrollUp, ScrollDown ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt;
FROM ScrollMessages IMPORT
   (* type *) ScrollKey;
FROM ListData IMPORT
  (* types *) ItemType, DataItemPntr,
  (* Procs *) MakeTokenDataItem, MakeColDataItem, CompareDataItems, MarkAsUsed;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, CopyListItem,
              DiscardList, FindItem, GetItemData, GetFirstItem,
              GetLastItem, GetNextItem, GetPrevItem, ItemDataPresent;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, InsertListItem;
FROM DBData IMPORT
    (* vars  *) BeginType, NoTokensInDB ;
FROM TokenBase IMPORT
  (* Types *) HTokenHandle,
  (* Procs *) GetTokenNo, GetToken, FreeTokenHandle, GetTokenHRec ;
FROM HyperBase IMPORT
  (* Types *) HRecPntr,
  (* Procs *) CompareHRecs;
FROM DisplayDialog IMPORT
  (* type *) DisplayType, DisplayDataType, ColDataType,
  (* vars *) DisplayData;
FROM PositionManagement IMPORT
  (* types *) PositionItem,
  (* procs *) GetPosData, FirstDisplayItem, NextMainItem,
              LastDisplayItem, CopyDisplayItem, NextDisplayItem,
              PrevDisplayItem, FindDisplayItem, DiscardDisplayItem,
              InitialDisplayItem;
FROM MainLists IMPORT
  (* type *) PosListStatusType,
  (* const*) PoolNoForCollDispSpace,
  (* vars *) SelectedList, ListByPosition,
             PosListStatus, SelectedListPos, PositionListPos, SelectedListEmpty ;
FROM ListUtils IMPORT MakePosList ;
FROM UnitBase IMPORT
   (* Procs *) GetUnitContext ;
FROM RefValBase IMPORT
  (* procs *) CreateRef;
FROM ResMessages IMPORT
   (*proc*)  GetResMessage, PutResError, PutResWarning, PutResMessage,
		MsgString, MsgCard, MsgLongInt ;
FROM WordBase IMPORT
  (* Procs *) SortToIntWord;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) GetType, FreeTypeHandle;
FROM PrintModule IMPORT AbortProc, WriteWithTabs, PrintDest, LinesPerPage,
		PrintActionType ;
FROM Translations IMPORT XlateLine, XFileType, XlateTablePointer,
           XlateStrAny, CurrentModeType, XWrNXlate;
FROM GlobalDefs IMPORT StrAny;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM TACTDataServices IMPORT
  (* procs *) VirtToTACTList, TACTListToVirt;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMAccess, VMMarkChanged, VMRelease,
     VMModify, GetSpace, FreePool;

(*<Empty*)

CONST
   MinScreenWidth = 76 ;
   MinScreenLen = 6 ;
   SelNodePos = 20 ;
   SelectAttr = SpecialAttr;
   BaseDisplayLine = 3 ;	(* we have 3 header lines *)

   (*RES OLD MSG 322
   Mini-text: %0 Total Text: %1
   *)
   TotalRes = (*RES REM INS*) 322 ;

   (*RES OLD MSG 323
Collocates          Sel. Collocate Type   Type   Expected  Standard  Z-score
   *)
   LongHeader1Res = (*RES REM INS*) 323 ;

(*RES OLD MSG 324
Node    Freq   Freq   Prob.   Observ.    Dev.
*)
   LongHeader2Res = (*RES REM INS*) 324 ;

   (*RES OLD MSG 331
Collocates          Sel. Collocate Type  Z-score
   *)
   Header1Res = (*RES REM INS*) 331 ;

(*RES OLD MSG 332
Node    Freq   Freq
*)
  Header2Res = (*RES REM INS*) 332 ;

(* --- not used anymore, see ListData ColType DataItem
TYPE
   LineRecPntr = POINTER TO LineListRecord ; (* Collocation data structure *)
   LineListRecord = RECORD
	ColTypePtrVA	: VirtAddr ;	(* --> DataItemPntr; so we have HeadWord + # occur *)
	LineListVA	: VirtAddr ;	(* --> TACTList; for syncronising with other displays *)
	NumberInLine	: CARDINAL ;	(* # of LineList items  *)
	Freq		: CARDINAL ;	(* of Collocate		*)
	ZScore		: REAL ;	(* for sorting records	*)
	Next,
	Prev		: VirtAddr ;	(* --> LineRecPntr *)
   END;
--- *)

VAR
   TWBId:        WinType;
   CurrentTop:   CARDINAL;
   LinesBefore:  CARDINAL;
   LinesAfter:   CARDINAL;
   DisplaySize:  CARDINAL;
   OldColSpecs:  ColDataType;
   OldColXSize : CARDINAL ;
   OldColYSize : CARDINAL ;
   OldShowIntRslt : BOOLEAN ;
   FirstLineVA,
   LastLineVA,
   CollDataVA,			(* used as a temporary var	*)
   CurrLineVA	: VirtAddr;	(* current line in the display	*)
   RefDisplayTab: ARRAY[0..0] OF TabInfo;
   ListsMade:    BOOLEAN;
   NoLinesUsed:  CARDINAL;
   CurrentLine:  CARDINAL;
   CurrentItemNo:CARDINAL;
   CurrentItem:  PositionItem;
   CurrentLineList: TACTList;
   CollocateList: TACTList;
   SortedList:    TACTList;
   CurrentMoved: BOOLEAN;
   NoToksInMiniText   : CARDINAL;
   NoToksInMiniTextLR : LONGREAL ;
   NoToksInDBLR  : LONGREAL ;
   TabSetting:   ARRAY[0..5] OF TabInfo;
   LastCurrent:  HRecPntr;

PROCEDURE ClearOutLists;
   BEGIN
	CurrentTop := 0;
	ListsMade := FALSE;
	DiscardDisplayItem(SelectedList, CurrentItem);
	DiscardList( CurrentLineList ) ;
	FreePool( PoolNoForCollDispSpace );
	DiscardList( CollocateList ) ;		(* <-- ??? *)
	DiscardList( SortedList ) ;		(* <-- ??? *)
	FirstLineVA := NILVirt ;
	LastLineVA  := NILVirt ;
	CollDataVA  := NILVirt ;
	CurrentLine := NoLinesUsed + 1;
	CurrentTop  := NoLinesUsed + 1;
   END ClearOutLists;

PROCEDURE DisplayEmptyMessage;
   VAR
	temp : ARRAY[0..80] OF CHAR;
   BEGIN
	Clear;
	(*RES OLD MSG 325
	Collocates data cannot be displayed until you select some words.
	*)
	GetResMessage( (*RES REM INS*) 325 , temp);
	WriteScreenField( TWBId,0, 0,0, temp, RegularAttr, TRUE);
   END DisplayEmptyMessage;

PROCEDURE GenDisplayLine(CollocateDataNode : DataItemPntr; VAR ScrLineStr : ARRAY OF CHAR) ;
   VAR
	Pos	: CARDINAL;
	TypeProb : LONGREAL ;
	ExpectedFreq : LONGREAL ;
	StdDev	: LONGREAL ;
	ZScoreLR: LONGREAL ;
	OK	: BOOLEAN ;
	TempStr : ARRAY[0..12] OF CHAR ;
	HeadWordStr : ARRAY[0..SelNodePos] OF CHAR ;
   BEGIN
      WITH CollocateDataNode^ DO
	 Pos := 0;
	 SortToIntWord( HeadWordData.Word, HeadWordStr ) ;
	 SWriteString( ScrLineStr, Pos, HeadWordStr, 0);	(* collocate *)
	 SWriteChar( ScrLineStr, Pos, IntTab, 0);	(* skip over Selected Node pos *)
	 SWriteCard( ScrLineStr, Pos, Freq, 0);		(* collocate freq. 	*)
	 SWriteChar( ScrLineStr, Pos, IntTab, 0);
	 SWriteCard( ScrLineStr, Pos, HeadWordData.NoOccur, 0); (* Type freq *)
	 SWriteChar( ScrLineStr, Pos, IntTab, 0);

	 IF DisplayData[Collocate].ColData.ColShowIntRslt THEN
		TypeProb := VAL(LONGREAL,HeadWordData.NoOccur) / NoToksInDBLR ;
		Str.FixRealToStr( TypeProb, 5, TempStr, OK ) ;
		SWriteString( ScrLineStr, Pos, TempStr, 0);	(* Type Probability	*)
		SWriteChar( ScrLineStr, Pos, IntTab, 0);

		(* Exp. Freq = TypeProb * NoToksInMiniText 		*)
		ExpectedFreq := VAL(LONGREAL,HeadWordData.NoOccur) * NoToksInMiniTextLR
			/ NoToksInDBLR  ;
		Str.FixRealToStr( ExpectedFreq, 4, TempStr, OK ) ;
		SWriteString( ScrLineStr, Pos, TempStr, 0);	(* Expected Prob of collocate *)
		SWriteChar( ScrLineStr, Pos, IntTab, 0);

		StdDev := MATHLIB.Sqrt(NoToksInMiniTextLR * TypeProb * (1.0-TypeProb)) ;
		Str.FixRealToStr( StdDev, 6, TempStr, OK ) ;
		SWriteString( ScrLineStr, Pos, TempStr, 0);	(* Standard Deviation	*)
		SWriteChar( ScrLineStr, Pos, IntTab, 0);
	 END ;

	 ZScoreLR := VAL( LONGREAL, ZScore ) ;
         Str.FixRealToStr( ZScoreLR, 3, TempStr, OK ) ;
         SWriteString( ScrLineStr, Pos, TempStr, 0);	(* Z-Score	*)
      END;
   END GenDisplayLine ;
(*Empty>*)

PROCEDURE HandleCollocateDisplay(KeyInstruction: ScrollKey);
(*<Empty*)
VAR
   Type:           ItemType;
   TokenPntr:      DataItemPntr;
   TokenVA	:  VirtAddr;
   TypeVA	:  VirtAddr;
   CatVA	:  VirtAddr;
   TempVA	:  VirtAddr;
   ScrLineStr:     ARRAY[0..79] OF CHAR;
   TempStr:        ARRAY[0..80] OF CHAR;
   OldCurrent:     CARDINAL;
   OldTop:         CARDINAL;
   ScrollUpDn:     BOOLEAN;
   Slot:	   CARDINAL;
   NextLine, k	:  CARDINAL;
   CollData	:  DataItemPntr;

PROCEDURE SetTabs() ;
   VAR i : CARDINAL ;
   BEGIN
	FOR i := 0 TO 5 DO	(* fill with defaults *)
	   WITH TabSetting[i] DO
		Type := Right ;
		Pos  := 1 ;
		FilPat := ' ' ;
	  END ;
	END ;
	TabSetting[0].Pos := 32 ; 	(* obs. collocate *)
	TabSetting[1].Pos := 40 ; 	(* Type freq	  *)

	IF DisplayData[Collocate].ColData.ColShowIntRslt THEN
	   TabSetting[2].Pos := 50 ;	(* Type prob.	  *)
	   TabSetting[3].Pos := 59 ;	(* Exp. prob.	  *)
	   TabSetting[4].Pos := 71 ;	(* Std dev	  *)
	   TabSetting[5].Pos := 81 ;	(* Z-Score	  *)
	ELSE
	   TabSetting[2].Pos := 50 ;	(* Z-Score	  *)
	END ;
   END SetTabs ;

PROCEDURE PutUpDisplay;
   VAR
	Line	: CARDINAL;
   BEGIN
	Clear;
	CollDataVA := CurrLineVA ;
	Slot := CurrentLine ;
	WHILE (Slot > CurrentTop) AND (CollDataVA <> NILVirt) DO
	   DEC( Slot ) ;
	   CollData := VMAccess( CollDataVA ) ;
	   TempVA   := CollData^.PrevColVA ;
	   VMRelease( CollDataVA ) ;
	   CollDataVA := TempVA ;
	END ;
	IF CollDataVA = NILVirt THEN  CollDataVA := FirstLineVA  END ;
	Line := BaseDisplayLine;
	WHILE (Line < DisplaySize) AND (CollDataVA <> NILVirt) DO
	   CollData := VMAccess( CollDataVA ) ;
	   GenDisplayLine( CollData, ScrLineStr ) ;
	   FancyScreenDisplay(TWBId, 0, Line, ScrLineStr, TabSetting, FALSE);
	   INC(Line);
	   TempVA := CollData^.NextColVA ;
	   VMRelease( CollDataVA ) ;
	   CollDataVA := TempVA ;
	END;
   END PutUpDisplay;

PROCEDURE InitializeData;
   VAR
	CurPos	: PositionItem;
	LastEndRange : LONGINT;
	PrevLastEndRange : LONGINT;
	PrevNodeTok  : LONGINT;

PROCEDURE DoSpanCollection ;
   VAR
	NodePos		: LONGINT ;
	StartRange,
	EndRange	: LONGINT ;
	TokenNo		: LONGINT ;
	StartToken	: HRecPntr ;
	EndToken	: HRecPntr ;

    PROCEDURE AddToken( TokNo : LONGINT ) ;
	VAR
	   LineList	: TACTList;
	   Item		: TACTListItem;
	   TokHandle	: HTokenHandle ;
	   TokFilePos	: HRecPntr ;
	   TypeFilePos	: HRecPntr ;
	   TypeHandl	: HTypeHandle;
	BEGIN
		GetTokenHRec( TokNo, TokFilePos ) ;
		GetToken( TokFilePos, TokHandle ) ;
		TypeFilePos.Rec := TokHandle^^.HRecNo + BeginType;
		TypeFilePos.Idx := ORD(TokHandle^^.HRecPos);
		FreeTokenHandle( TokHandle ) ;

		IF NOT ItemDataPresent(CollocateList, ColDataItemType, TypeFilePos, Item) THEN
		   INC( NoLinesUsed );
		   (* now get the real data for the type=headword (just once!) *)
		   GetType( TypeFilePos, TypeHandl );
		   MakeColDataItem( TypeHandl, PoolNoForCollDispSpace, CollDataVA, CollData );
		   FreeTypeHandle(TypeHandl);
		   CollData^.FilePos := TypeFilePos ;
		   LineList := NewMemoryList(PoolNoForCollDispSpace);
		   TACTListToVirt( LineList, PoolNoForCollDispSpace, CollData^.Contents);
		   DiscardList( LineList ) ;
		   IF NOT InsertListItem( CollDataVA, CollocateList ) THEN
			ProgramErrorAndHalt( 'Unable to insert in collocation list.' )
		   END ;
		ELSE
		   GetItemData( CollocateList, Item, CollDataVA, CollData) ;
		   VMMarkChanged( CollDataVA ) ;
		END;
		WITH CollData^ DO
		   INC(Freq);
		   VirtToTACTList( Contents, LineList) ;
		   IF InsertListItem(TokenVA (* = Node Word *), LineList) THEN
			INC( NoContents );
		   END;
		   DiscardList( LineList ) ;
		END;
		VMRelease( CollDataVA ) ;
		INC( NoToksInMiniText ) ;
	END AddToken ;
	
   BEGIN
	GetTokenNo( TokenPntr^.FilePos, NodePos) ;
	WITH DisplayData[Collocate].ColData DO
	   IF ColUnitID = 0 (* word context *) THEN
		StartRange := NodePos - VAL(LONGINT, ColBefore ) ;
		EndRange   := NodePos + VAL(LONGINT, ColAfter ) ;
	   ELSE
		GetUnitContext( TokenVA, ColUnitID, ColBefore, ColAfter,
					StartToken, EndToken ) ;
		GetTokenNo( StartToken, StartRange ) ;
		GetTokenNo( EndToken, EndRange ) ;
	   END ;
	   IF StartRange < 1 THEN  StartRange := 1  END ;
	   IF EndRange > NoTokensInDB THEN  EndRange := NoTokensInDB  END ;
	   IF NOT ColOverLaps THEN
		IF (PrevNodeTok >= StartRange) AND (PrevNodeTok > PrevLastEndRange) THEN
		   AddToken( PrevNodeTok )
		END ;
		PrevNodeTok := NodePos ;
		IF LastEndRange >= StartRange THEN
		   StartRange := LastEndRange + 1
		END ;
		PrevLastEndRange := LastEndRange ;  (* to prevent multiple overlap count of nodes *)
		LastEndRange := EndRange ;
	   END ;
	END ;
	FOR TokenNo := StartRange TO EndRange DO
	   IF TokenNo <> NodePos THEN  (* don't include the Node token itself *)
		AddToken( TokenNo )
	   END ;
	END;
   END DoSpanCollection ;

PROCEDURE CalcZScores ;
   VAR
	TypeProb : LONGREAL ;
	ExpectedFreq : LONGREAL ;
	StdDev	 : LONGREAL ;
	ZScoreLR : LONGREAL ;
	Item     : TACTListItem ;
   BEGIN
	NoToksInMiniTextLR := VAL( LONGREAL, NoToksInMiniText ) ; (* do conversions once *)
	NoToksInDBLR := VAL( LONGREAL, NoTokensInDB ) ;
	
	IF GetFirstItem( CollocateList, Item) THEN
	   REPEAT
	     GetItemData( CollocateList, Item, CollDataVA, CollData ) ;
	     VMMarkChanged( CollDataVA ) ;
	     WITH CollData^ DO

		TypeProb := VAL(LONGREAL,HeadWordData.NoOccur) / NoToksInDBLR ;
		(* Exp. Freq = TypeProb * NoToksInMiniText 		*)
		ExpectedFreq := VAL(LONGREAL,HeadWordData.NoOccur) * NoToksInMiniTextLR
				/ NoToksInDBLR  ;
		StdDev := MATHLIB.Sqrt(NoToksInMiniTextLR * TypeProb * (1.0-TypeProb)) ;

		ZScore := VAL(REAL, (VAL(LONGREAL,Freq) - ExpectedFreq) / StdDev ) ;
	     END;
	     VMRelease( CollDataVA ) ;
	   UNTIL NOT GetNextItem( CollocateList, Item) ;
	END ;
   END CalcZScores ;

PROCEDURE SortByZScores ;
   VAR
	NextCollData   	: DataItemPntr ;
	NextCollDataVA 	: VirtAddr ;
	tItem		: TACTListItem ;
   BEGIN
	SortedList := NewMemoryList(PoolNoForCollDispSpace);
	(* start a new sorted linked list *)
	IF GetFirstItem( CollocateList, tItem) THEN
	   REPEAT
		GetItemData( CollocateList, tItem, CollDataVA, CollData ) ;
		CollData^.DataType := ZScoreType ;
		VMMarkChanged( CollDataVA ) ;
		IF NOT InsertListItem( CollDataVA, SortedList ) THEN
			ProgramErrorAndHalt( 'Unable to insert collocation sorted list.' )
		END ;
		VMRelease( CollDataVA ) ;
	   UNTIL NOT GetNextItem( CollocateList, tItem) ;
	END ;

	IF GetFirstItem( SortedList, tItem) THEN
	   (* now make a linked list *)
	   GetItemData( SortedList, tItem, CollDataVA, CollData ) ;
	   FirstLineVA := CollDataVA ;
	   WHILE GetNextItem( SortedList, tItem) DO
		GetItemData( SortedList, tItem, NextCollDataVA, NextCollData ) ;
		CollData^.NextColVA := NextCollDataVA ;
		NextCollData^.PrevColVA := CollDataVA ;
		VMMarkChanged( CollDataVA ) ;
		VMRelease( CollDataVA ) ;
		CollDataVA := NextCollDataVA ;
		CollData   := NextCollData ;
	   END ;
	   VMMarkChanged( CollDataVA ) ;
	   VMRelease( CollDataVA ) ;
	   LastLineVA := CollDataVA ;
	END ;
   END SortByZScores ;

BEGIN (* InitializeData *)
   IF ListsMade THEN  ClearOutLists  END;
   CollocateList := NewMemoryList(PoolNoForCollDispSpace);
   OldCurrent := MAX(CARDINAL) ; (* this ensures redisplay *)
   NoLinesUsed := 0;
   NoToksInMiniText := 0 ;
   LastEndRange := 0 ;		(* for overlap checks *)
   PrevNodeTok  := 0 ;		(* for overlap checks *)
   PrevLastEndRange := 0 ;	(* for overlap checks *)

   SetAutoUpdate(TWBId);
   GotoXY(0,0);
   ClrEol;
   (*RES OLD MSG 328
   UseBase is collecting Collocates now ... Please wait.
   *)
   GetResMessage( (*RES REM INS *) 328, TempStr ) ;
   WriteScreenField( TWBId,0, 0,0, TempStr, BoldAttr, TRUE);

   IF PosListStatus = NoPos THEN
	PosListStatus := PosMade;
	MakePosList(SelectedList, ListByPosition);
   END;

   InitialDisplayItem(CurPos);
   IF NOT FirstDisplayItem(ListByPosition,CurPos) THEN
      ProgramErrorAndHalt('No list in InitializeData')
   END;
   REPEAT
      GetPosData(CurPos, Type, TokenVA, TypeVA, CatVA);
      IF TokenVA <> NILVirt THEN
	 TokenPntr := VMAccess( TokenVA ) ;
         DoSpanCollection ;
 	 VMRelease( TokenVA ) ;
      END;
   UNTIL NOT NextDisplayItem(ListByPosition, CurPos);
   DiscardDisplayItem(ListByPosition,CurPos);
   ListsMade := TRUE;

   GotoXY(0,0);
   ClrEol;
   (*RES OLD MSG 329
   UseBase is calculating Z-Scores now ... Please wait.
   *)
   GetResMessage( (*RES REM INS *) 329, TempStr ) ;
   WriteScreenField( TWBId,0, 0,0, TempStr, BoldAttr, TRUE);
   CalcZScores ;

   GotoXY(0,0);
   ClrEol;
   (*RES OLD MSG 330
   UseBase is sorting by Z-Scores now ... Please wait.
   *)
   GetResMessage( (*RES REM INS *) 330, TempStr ) ;
   WriteScreenField( TWBId,0, 0,0, TempStr, BoldAttr, TRUE);
   SortByZScores ;
   SetManualUpdate(TWBId);

   OldColSpecs := DisplayData[Collocate].ColData ;
   OldColXSize := DisplayData[Collocate].WindInfo.XSize ;
   OldColYSize := DisplayData[Collocate].WindInfo.YSize ;
END InitializeData;

PROCEDURE WindowSizeChanged() : BOOLEAN ;
    BEGIN
	IF (OldColXSize <> DisplayData[Collocate].WindInfo.XSize) OR
	   (OldColYSize <> DisplayData[Collocate].WindInfo.YSize) OR
	   (OldColSpecs.ColShowIntRslt <> DisplayData[Collocate].ColData.ColShowIntRslt) THEN
		OldColXSize := DisplayData[Collocate].WindInfo.XSize ;
		OldColYSize := DisplayData[Collocate].WindInfo.YSize ;
		OldColSpecs.ColShowIntRslt := DisplayData[Collocate].ColData.ColShowIntRslt ;
		RETURN TRUE
	ELSE
		RETURN FALSE
	END ;
    END WindowSizeChanged;

PROCEDURE SetHighLight(CLine, CPoint: CARDINAL ) ;
    VAR
	Pos : CARDINAL ;
	TempStr : ARRAY[0..10] OF CHAR ;
    BEGIN
	IF CLine > NoLinesUsed THEN  RETURN  END;
	Pos := 0 ;
	SWriteCard( TempStr, Pos, CPoint+1, 4);	(* Selected Node No. 	*)
	WriteScreenField( TWBId, 0, SelNodePos,CLine+BaseDisplayLine-CurrentTop,
			TempStr, RegularAttr, FALSE);
    END SetHighLight;

PROCEDURE UnHighLight( CLine : CARDINAL ) ;
    VAR  j : CARDINAL;
    BEGIN
	IF (CLine > NoLinesUsed) OR (CLine+BaseDisplayLine-CurrentTop>DisplaySize) THEN  RETURN  END;
	WriteScreenField( TWBId, 0, SelNodePos,CLine+BaseDisplayLine-CurrentTop,
			'    ', RegularAttr, FALSE);
    END UnHighLight;

PROCEDURE PutUpRefLine(TokenVA : VirtAddr);
   VAR
	LP	: CARDINAL;
	TempLen	: CARDINAL;
	Header	: CARDINAL;
   BEGIN
	GotoXY(0,0);
	ClrEol;
	RefDisplayTab[0].Pos := DisplayData[Collocate].WindInfo.XSize - 3 ;
	CreateRef( DisplayData[Collocate].EncodedRefInfo,
		DisplayData[Collocate].EncodedRefLen, TokenVA, TempStr, TempLen,
		DisplayData[Collocate].DisplayWordCountWord ) ;
	ScrLineStr[0] := IntEnhOn ;
	LP := 1 ;
	SWriteString(ScrLineStr, LP, TempStr, 0);
	ScrLineStr[LP] := IntTab ;
	INC( LP ) ;
	MsgCard( NoToksInMiniText, 0 ) ;
	MsgLongInt( NoTokensInDB, 0 ) ;
	GetResMessage( TotalRes, TempStr ) ;
	SWriteString(ScrLineStr, LP, TempStr, 0);
	FancyScreenDisplay( TWBId, 0,0, ScrLineStr, RefDisplayTab,FALSE);

	IF DisplayData[Collocate].ColData.ColShowIntRslt THEN
	   Header := LongHeader1Res
	ELSE
	   Header := Header1Res
	END ;
	GetResMessage( Header, TempStr ) ;
	GotoXY(0,1);
	ClrEol;
	WriteScreenField( TWBId,0, 0,1, TempStr, BoldAttr, FALSE);

	IF DisplayData[Collocate].ColData.ColShowIntRslt THEN
	   Header := LongHeader2Res
	ELSE
	   Header := Header2Res
	END ;
	GetResMessage( Header, TempStr ) ;
	GotoXY(0,2);
	ClrEol;
	WriteScreenField( TWBId,0, SelNodePos,2, TempStr, BoldAttr, FALSE);
   END PutUpRefLine;

PROCEDURE FindCurrentPoint;
VAR
   Type		: ItemType;
   TempPItem	: PositionItem;
   TrialPntr	: DataItemPntr;
   TokenPntr	: DataItemPntr;
   TokenVA	: VirtAddr ;
   TypeVA	: VirtAddr ;
   CatVA	: VirtAddr ;
   TempItem	: TACTListItem;

   PROCEDURE ErrorFound;
	BEGIN
	   ProgramErrorAndHalt('Error in FindCurrentPoint');
	END ErrorFound;

BEGIN
   UnHighLight( CurrentLine ) ;

   InitialDisplayItem(TempPItem);
   CopyDisplayItem(SelectedList,SelectedListPos,TempPItem);
   GetPosData(TempPItem, Type, TokenVA, TypeVA, CatVA);
   WHILE TokenVA = NILVirt DO
	IF NOT NextDisplayItem(SelectedList, TempPItem) THEN ErrorFound END;
	GetPosData(TempPItem, Type, TokenVA, TypeVA, CatVA);
   END;
   CurrentMoved := TRUE;

   CurrentLine := 0;
   CollDataVA := FirstLineVA ;
   IF CollDataVA <> NILVirt THEN
	CollData := VMAccess( CollDataVA ) ;
	VirtToTACTList( CollData^.Contents, CurrentLineList ) ;
   END;
   WHILE (CollDataVA <> NILVirt) AND NOT FindItem(CurrentLineList,TokenVA,TempItem) DO
      INC(CurrentLine) ;
      TempVA := CollDataVA ;
      CollDataVA := CollData^.NextColVA ;
      VMRelease( TempVA ) ;
      DiscardList( CurrentLineList ) ;
      IF CollDataVA <> NILVirt THEN
	 CollData := VMAccess( CollDataVA ) ;
	 VirtToTACTList( CollData^.Contents, CurrentLineList ) ;
      END;
   END;
   DisposeListItem(SelectedList,TempItem);

   IF (CurrentLine >= NoLinesUsed) OR (CollDataVA = NILVirt) THEN  ErrorFound  END;

   TokenPntr := VMAccess( TokenVA ) ;
   TempVA    := TokenVA ;
   CurrLineVA := CollDataVA ;

   WITH CollData^ DO
      IF NOT FirstDisplayItem(CurrentLineList, CurrentItem) THEN  ErrorFound  END;
      GetPosData(CurrentItem, Type, TokenVA, TypeVA, CatVA);
      TrialPntr := VMAccess( TokenVA ) ;
      CurrentItemNo := 0;
      WHILE CompareDataItems(TrialPntr,TokenPntr) <> 0 DO
         INC(CurrentItemNo);
         IF NOT NextDisplayItem(CurrentLineList, CurrentItem) THEN ErrorFound END;
	 VMRelease( TokenVA ) ;
	 GetPosData(CurrentItem, Type, TokenVA, TypeVA, CatVA);
	 TrialPntr := VMAccess( TokenVA ) ;
      END;
      VMRelease( TokenVA ) ;
   END;
   VMRelease( TempVA ) ;
   VMRelease( CollDataVA ) ;
   DiscardDisplayItem(SelectedList, TempPItem);
END FindCurrentPoint;

PROCEDURE SetToEndOfLine( CollDataVA : VirtAddr; NewLine : CARDINAL );
    BEGIN
	CurrentMoved := TRUE;
        UnHighLight( CurrentLine ) ;
        CurrentLine := NextLine;
	DiscardDisplayItem(CurrentLineList, CurrentItem);
	DiscardList(CurrentLineList); (* get rid real reference *)
	CollData := VMAccess( CollDataVA ) ;
	VirtToTACTList( CollData^.Contents, CurrentLineList ) ;
        IF NOT LastDisplayItem(CurrentLineList, CurrentItem) THEN
	   ProgramErrorAndHalt('Problem Finding last item in list');
        END;
        CurrentItemNo := CollData^.NoContents-1;
	VMRelease( CollDataVA ) ;
	CurrLineVA := CollDataVA ;
    END SetToEndOfLine ;

PROCEDURE SetToFrontOfLine( CollDataVA : VirtAddr; NewLine : CARDINAL );
    BEGIN
	CurrentMoved := TRUE;
	UnHighLight( CurrentLine ) ;
	CurrentLine := NewLine;
	DiscardDisplayItem(CurrentLineList, CurrentItem);
	DiscardList(CurrentLineList); (* get rid real reference *)
	CollData := VMAccess( CollDataVA ) ;
	VirtToTACTList( CollData^.Contents, CurrentLineList ) ;
	IF NOT FirstDisplayItem(CurrentLineList, CurrentItem) THEN
	   ProgramErrorAndHalt('Problem Finding first item in list');
	END;
	VMRelease( CollDataVA ) ;
	CurrLineVA := CollDataVA ;
	CurrentItemNo := 0;
    END SetToFrontOfLine;

PROCEDURE CheckCurrentTop ;
   BEGIN
	OldTop := CurrentTop;
	IF NoLinesUsed < DisplaySize THEN
	   CurrentTop := 0
	ELSIF (CurrentLine < LinesBefore + CurrentTop) THEN
	   IF CurrentLine < LinesBefore THEN CurrentTop := 0
	   ELSE
		CurrentTop := CurrentLine - LinesBefore ;
		IF CurrentTop+DisplaySize-BaseDisplayLine > NoLinesUsed THEN
		   CurrentTop := NoLinesUsed + BaseDisplayLine - DisplaySize
		END;
	   END;
	ELSIF (CurrentLine > LinesAfter + CurrentTop - BaseDisplayLine) THEN
	   CurrentTop := CurrentLine + BaseDisplayLine - LinesAfter ;
	   IF CurrentTop+DisplaySize-BaseDisplayLine > NoLinesUsed THEN
		CurrentTop := NoLinesUsed + BaseDisplayLine - DisplaySize
	   END;
	END;
   END CheckCurrentTop ;

PROCEDURE SetScrnDisplay( NewCollVA : VirtAddr; Loc : CARDINAL ) ;
    BEGIN
	IF CollDataVA = NILVirt THEN   CollDataVA := NewCollVA  END ;
	CollData := VMAccess( CollDataVA ) ;
	GenDisplayLine( CollData, ScrLineStr ) ;
	VMRelease( CollDataVA ) ;
	FancyScreenDisplay(TWBId, 0, Loc, ScrLineStr, TabSetting, FALSE);
    END SetScrnDisplay;

PROCEDURE DoDownKey;
    BEGIN
	NextLine := CurrentLine+1;
	CollData := VMAccess( CurrLineVA ) ;
	CollDataVA := CollData^.NextColVA ;
	VMRelease( CurrLineVA ) ;
	IF (NextLine >= NoLinesUsed) OR (CollDataVA = NILVirt) THEN Beep
	ELSE
	   SetToFrontOfLine(CollDataVA, NextLine) ;
	   ScrollUpDn := TRUE ;
	   CheckCurrentTop ;
	   IF OldTop <> CurrentTop THEN
		ScrollUp(TWBId, 1) ;
		(* find the bottom line record data *)
		Slot := CurrentLine + BaseDisplayLine - OldTop ;
		WHILE (Slot < DisplaySize) AND (CollDataVA <> NILVirt) DO
		   CollData	:= VMAccess( CollDataVA ) ;
		   TempVA	:= CollDataVA ;
		   CollDataVA	:= CollData^.NextColVA ;
		   VMRelease( TempVA ) ;
		   INC( Slot ) ;
		END ;
		SetScrnDisplay( LastLineVA, DisplaySize-1 ) ;
	   END ;
	END;
    END DoDownKey;

PROCEDURE ColSpecsChanged() : BOOLEAN ;
   BEGIN
	WITH DisplayData[Collocate].ColData DO
	   IF (OldColSpecs.ColUnitID <> ColUnitID) OR (OldColSpecs.ColBefore <> ColBefore) OR
	      (OldColSpecs.ColAfter  <> ColAfter ) OR (OldColSpecs.ColOverLaps <> ColOverLaps) THEN
	      RETURN TRUE
	   ELSE
	      RETURN FALSE
	   END ;
	END ;
   END ColSpecsChanged ;

PROCEDURE CurrentPointChanged(): BOOLEAN;
VAR rc : BOOLEAN ;
BEGIN
   GetPosData(SelectedListPos, Type, TokenVA, TypeVA, CatVA);
   IF TokenVA = NILVirt THEN RETURN TRUE END;
   TokenPntr := VMAccess( TokenVA ) ;
   rc := TokenPntr^.FilePos <> LastCurrent;
   VMRelease( TokenVA ) ;
   RETURN rc ;
END CurrentPointChanged;
(*Empty>*)

BEGIN	(* HandleDisplay *)
(*<Empty*)
   OldCurrent := CurrentLine;
   CurrentMoved := FALSE;
   ScrollUpDn := FALSE;
   TWBId := DisplayData[Collocate].WindID;
   Use(TWBId);

   IF (DisplayData[Collocate].WindInfo.XSize < MinScreenWidth)
	AND DisplayData[Collocate].ColData.ColShowIntRslt THEN
      Clear;
      (*RES OLD MSG 326
      Please use the full Display Screen. The current Screen is too narrow to
      show the Collocates data.
      *)
      PutResError( (*RES REM INS*) 326 );
      Beep;
      RETURN;
   END;

   IF (DisplayData[Collocate].WindInfo.YSize < MinScreenLen) THEN
         Clear;
         (*RES OLD MSG 333
         Please use a Display Screen at least %0 lines deep. The Current Screen
         is too short to show Collocates data.
         *)
         MsgCard( MinScreenLen, 0 ) ;
         PutResError( (*RES REM INS*) 333 );
      Beep;
      RETURN;
   END;

   IF SelectedListEmpty THEN
      IF KeyInstruction = InitKey THEN DisplayEmptyMessage
      ELSIF KeyInstruction <> TermKey THEN Beep END ;
      SetAutoUpdate(TWBId);
      RETURN
   END;
   SetManualUpdate(TWBId);
   CASE KeyInstruction OF
     InitKey:
	 DisplaySize := DisplayData[Collocate].WindInfo.YSize;
         LinesBefore := DisplaySize DIV 4;
         LinesAfter := DisplaySize - LinesBefore;
         SetTabs() ;
         IF NOT ListsMade OR ColSpecsChanged() THEN
            InitializeData;
            FindCurrentPoint;
         ELSIF CurrentPointChanged() THEN
            FindCurrentPoint;
         ELSIF WindowSizeChanged() THEN
		CheckCurrentTop ;
		PutUpDisplay ;
                PutUpRefLine(TokenVA);
	 END;
   | TermKey, CloseDownKey:
	 ClearOutLists;
	 RETURN ;
   | UpKey:
       IF CurrentLine = 0 THEN Beep
       ELSE
          NextLine := CurrentLine-1;
          CollData := VMAccess( CurrLineVA ) ;
          CollDataVA := CollData^.PrevColVA ;
          VMRelease( CurrLineVA ) ;
          IF (CollDataVA = NILVirt) THEN Beep
          ELSE
		SetToFrontOfLine(CollDataVA, NextLine) ;
		ScrollUpDn := TRUE ;
		CheckCurrentTop ;
		IF OldTop <> CurrentTop THEN
		   ScrollDown(TWBId, 1) ;
		   (* find the top line record data *)
		   Slot := CurrentLine ;
		   WHILE (Slot >= OldTop) AND (CollDataVA <> NILVirt) DO
			CollData	:= VMAccess( CollDataVA ) ;
			TempVA		:= CollDataVA ;
			CollDataVA	:= CollData^.PrevColVA ;
			VMRelease( TempVA ) ;
			DEC( Slot ) ;
		   END ;
		   SetScrnDisplay( FirstLineVA, BaseDisplayLine ) ;
		END ;
	  END;
       END;
   | DownKey: DoDownKey;
   | HomeKey:
       NextLine := 0;
       CollDataVA := FirstLineVA ;
       SetToFrontOfLine(CollDataVA, NextLine) ;
   | EndKey:
       NextLine := NoLinesUsed - 1;
       CollDataVA := LastLineVA ;
       SetToFrontOfLine(CollDataVA, NextLine) ;
   | RightKey:
	CurrentMoved := TRUE;
	IF NextDisplayItem(CurrentLineList, CurrentItem) THEN
	    UnHighLight( CurrentLine ) ;
            INC(CurrentItemNo);
        ELSE DoDownKey
        END;
   | LeftKey:
	CurrentMoved := TRUE;
        IF PrevDisplayItem(CurrentLineList, CurrentItem) THEN
            UnHighLight( CurrentLine ) ;
            DEC(CurrentItemNo);
        ELSE
	   (* note: this is similar to UpKey but places current to last item on list! *)
           IF CurrLineVA = FirstLineVA THEN Beep
           ELSE
              NextLine := CurrentLine-1;
	      CollData := VMAccess( CurrLineVA ) ;
              CollDataVA := CollData^.PrevColVA ;
	      VMRelease( CurrLineVA ) ;
              IF (CollDataVA = NILVirt) THEN Beep
              ELSE
		 SetToEndOfLine( CollDataVA, NextLine ) ;
              END;
           END;
        END;
   | REndKey:
	SetToEndOfLine( CurrLineVA, CurrentLine ) ;
   | LEndKey:
	SetToFrontOfLine( CurrLineVA, CurrentLine) ;
   | PgUpKey:
       IF CurrentLine = 0 THEN Beep	(* already at top of list *)
       ELSE
          IF CurrentLine > DisplaySize THEN
		NextLine := CurrentLine + BaseDisplayLine - DisplaySize + 1 ;
		CollDataVA := CurrLineVA ;
		k := CurrentLine ;
		WHILE (k > NextLine) AND (CollDataVA <> NILVirt) DO
		   CollData := VMAccess( CollDataVA ) ;
		   TempVA := CollDataVA ;
		   CollDataVA := CollData^.PrevColVA ;
		   VMRelease( TempVA ) ;
		   DEC( k ) ;
		END ;
		IF (CollDataVA = NILVirt) THEN
		   CollDataVA := FirstLineVA ;
		   NextLine := 0 ;
		END ;
	  ELSE
		CollDataVA := FirstLineVA ;
		NextLine := 0 ;
	  END ;
          SetToFrontOfLine(CollDataVA, NextLine) ;
       END;
   | PgDnKey:	
       IF CurrentLine >= NoLinesUsed-1 THEN Beep  (* already at bottom of list *)
       ELSE
          NextLine := CurrentLine + DisplaySize - BaseDisplayLine - 1 ;
          CollDataVA := CurrLineVA ;
          k := CurrentLine ;
          WHILE (k < NextLine) AND (CollDataVA <> NILVirt) DO
		CollData := VMAccess( CollDataVA ) ;
		TempVA := CollDataVA ;
		CollDataVA := CollData^.NextColVA ;
		VMRelease( TempVA ) ;
		INC( k ) ;
          END ;
          IF (CollDataVA = NILVirt) THEN	(* reached end of list *)
		CollDataVA := LastLineVA ;
		NextLine := NoLinesUsed - 1 ;
          END ;
          SetToFrontOfLine(CollDataVA, NextLine) ;
       END;
   ELSE Beep;
   END;

   IF (OldCurrent <> CurrentLine) AND NOT ScrollUpDn THEN
      CheckCurrentTop ;
      IF OldTop <> CurrentTop THEN  PutUpDisplay  END;
   END;

   IF CurrentMoved THEN
      GetPosData(CurrentItem, Type, TokenVA, TypeVA, CatVA);
      PutUpRefLine(TokenVA);
      TokenPntr   := VMAccess( TokenVA ) ;
      LastCurrent := TokenPntr^.FilePos;
      VMRelease( TokenVA ) ;
      DiscardDisplayItem(SelectedList,SelectedListPos);
      IF NOT FindDisplayItem( CurrentLineList, CurrentItem, SelectedList, SelectedListPos) THEN
         ProgramErrorAndHalt('Could not find corresponding item')
      END
   END;

   SetHighLight(CurrentLine, CurrentItemNo );
   SetAutoUpdate(TWBId);
(*Empty>*)
END HandleCollocateDisplay;


PROCEDURE OutputCollocateDisplay(VAR file : XFileType; CheckAbort : AbortProc);
   VAR
	PrtLine	: StrAny;
	Pos	: CARDINAL;
	Header	: CARDINAL;
	HeaderTabSetting: ARRAY[0..0] OF TabInfo;
	TempStr : StrAny;
	NoLines	: CARDINAL;
	result	: CARDINAL;
	TempVA	: VirtAddr;
	CollData: DataItemPntr;
   BEGIN
(*<Empty*)
	IF SelectedListEmpty THEN
	   (*RES OLD MSG 327
	   Collocates data cannot be Printed or Written to File until you select
	   some words.
	   *)
	   PutResError( (*RES REM INS*) 327 );
	   RETURN
	END;
	WITH HeaderTabSetting[0] DO
	   Type := Left;
	   Pos  := 1;
	   FilPat := ' ' ; (* should use IntRuleChar - not exported ... yet JB?? *)
	END;

	IF DisplayData[Collocate].ColData.ColShowIntRslt THEN
	   Header := LongHeader1Res
	ELSE
	   Header := Header1Res
	END ;
	GetResMessage( Header, PrtLine ) ;
	IF NOT WriteWithTabs(file,PrtLine,HeaderTabSetting) OR CheckAbort() THEN  RETURN  END;

	IF DisplayData[Collocate].ColData.ColShowIntRslt THEN
	   Header := LongHeader2Res
	ELSE
	   Header := Header2Res
	END ;
	GetResMessage( Header, TempStr) ;
	HeaderTabSetting[0].Pos := SelNodePos + 1 ;
	PrtLine[0] := IntTab ;
	PrtLine[1] := 0C ;
	Str.Append( PrtLine, TempStr ) ;
	IF NOT WriteWithTabs(file,PrtLine,HeaderTabSetting) OR CheckAbort() THEN  RETURN  END;
	HeaderTabSetting[0].Pos := 1 ;

	NoLines := 3 ;
	CollDataVA := FirstLineVA ;
	WHILE CollDataVA <> NILVirt DO
	   CollData := VMAccess( CollDataVA ) ;
	   TempVA   := CollDataVA ;
	   GenDisplayLine( CollData, PrtLine ) ;
	   CollDataVA := CollData^.NextColVA ;
	   VMRelease( TempVA ) ;
	   IF NOT WriteWithTabs(file,PrtLine,TabSetting) OR CheckAbort() THEN  RETURN  END;
	   INC( NoLines ) ;
	   IF (PrintDest = ToPrinter) AND (NoLines > LinesPerPage) THEN
	      XWrNXlate( file, ASCII.ff, result);
	      NoLines := 1 ;
	   END ;
	END;
	PrtLine[0] := 0C ; (* same as a blank line *)
	IF NOT WriteWithTabs(file,PrtLine,HeaderTabSetting) OR CheckAbort() THEN  RETURN  END;
	Pos := 0 ;
	MsgCard( NoToksInMiniText, 0 ) ;
	MsgLongInt( NoTokensInDB, 0 ) ;
	GetResMessage( TotalRes, TempStr ) ;
	SWriteString( PrtLine, Pos, TempStr, 0);
	IF NOT WriteWithTabs(file,PrtLine,HeaderTabSetting) OR CheckAbort() THEN  RETURN  END;
(*Empty>*)
   END OutputCollocateDisplay;

PROCEDURE InitializeCollocateDisplay;
BEGIN
(*<Empty*)
   ListsMade := FALSE;
   CurrentLine := MAX(CARDINAL);
   InitialDisplayItem(CurrentItem);
   WITH RefDisplayTab[0] DO
      Type := Right;
      FilPat := ' ' ; (* should use IntRuleChar - not exported ... yet JB?? *)
   END;
   CurrentTop := MAX(INTEGER) ;
   FirstLineVA := NILVirt ;
   LastLineVA  := NILVirt ;
   CurrLineVA  := NILVirt ;
   OldColXSize  := 0 ;
   OldColYSize  := 0 ;
   OldColSpecs.ColShowIntRslt := FALSE ;
   LastCurrent.Rec := 0;
   LastCurrent.Idx := 0;
(*Empty>*)
END InitializeCollocateDisplay;

END ColDisplay .
