IMPLEMENTATION MODULE VariDisplay;

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


IMPORT TWB, Str, ASCII, Lib;
FROM SYSTEM IMPORT BYTE ;
FROM GlobalDefs IMPORT StrAny;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM Utils IMPORT Beep ;
FROM KeyTranslation IMPORT
  (* Const *) IntTab,IntEnhOn, IntEnhOff,
  (* Type  *) TabInfo, TabType,
  (* Procs *) FancyScreenDisplay, WriteScreenField;
FROM MainLists IMPORT
  (* type *) PosListStatusType,
  (* vars *) SelectedList, ListByPosition,
             PosListStatus, SelectedListPos, PositionListPos,
             SelectedListEmpty, ListByType, TypeListPos, ListByTypeMade;
FROM ScrollMessages IMPORT
   (* const*) SizeOfLineInfoHeader,
   (* type *) ScrollInstruction, ReturnInstruction, LineInformation,
              LineInfoPntr, ScrollInstructionPacket, ScrollKey;
FROM ListData IMPORT
  (* types *) ItemType,DataItemPntr;
FROM TACTListModule IMPORT
  (* types *) TACTList;
FROM PositionManagement IMPORT
  (* types *) PositionItem,
  (* procs *) GetPosData, FirstDisplayItem,
              LastDisplayItem, CopyDisplayItem, NextDisplayItem,
              PrevDisplayItem, FindDisplayItem, DiscardDisplayItem,
              InitialDisplayItem, PrepareDisplayForItem;
FROM ListUtils IMPORT MakePosList, MakeWordList;
IMPORT TACTProcesses;
FROM channels IMPORT
  (* type *) channel,
  (* proc *) open, close, attachsender, attachreceiver, send, receive,
             datawaiting;
FROM Windows IMPORT
  (* Const *) RegularAttr, BoldAttr,
  (* Procs *) ScrollUp, ScrollDown, ChangeColorOnScreen ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM StackWindows IMPORT WindowInfo;
FROM DisplayDialog IMPORT
  (* type *) DisplayType, DisplayDataType, DispOrg,
  (* vars *) DisplayData, CurrentDisplay;
FROM HyperBase IMPORT HRecPntr, CompareHRecs ;
FROM HyperDataModel IMPORT
  (* Types *) HTokenData, HTypeData, HNoTokens ;
FROM DBData IMPORT
    (* vars  *) BeginText, BeginToken, NoTokensInDB ;
FROM ResMessages IMPORT
   (*proc*)  GetResMessage, PutResError;
FROM TokenBase IMPORT
  (* Types *) HTokenHandle,
  (* procs *) GetTokenNo, GetPrevToken, GetToken, DecompressTokenInfo,
              FreeTokenHandle ;
FROM RefValBase IMPORT
  (* Procs *) CreateRef ;
FROM TACTDataServices IMPORT GetTDBTokenData;
FROM UnitBase IMPORT
  (* Procs *) GetUnitContext ;
IMPORT LineBase ;
FROM Translations IMPORT XFileType, XWrNXlate;
FROM PrintModule IMPORT AbortProc, WriteWithTabs, PrintDest, LinesPerPage,
		PrintActionType ;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMAccess, VMMarkChanged, VMRelease;

(*<Empty*)

CONST
   WSSize = 4000;
   MarkerSymbol = 020C;

TYPE
   GenInfoPntr = POINTER TO GenInfo;
   GenInfo = RECORD
      Next:              GenInfoPntr;
      ToVariableDispGen:    channel;
      FromVariableDispGen:  channel;
   END;

VAR
   QueueOfGenInfos:      GenInfoPntr;
   VariableDisplayTab:      ARRAY[0..0] OF TabInfo;
   InitLineProcs:        BOOLEAN;

   TopDat:       GenInfoPntr;
   BottomDat:    GenInfoPntr;
   PrintDat:     GenInfoPntr;
   TopLPtr:      LineInfoPntr;
   BottomLPtr:   LineInfoPntr;
   LinesBefore:  CARDINAL;
   LinesAfter:   CARDINAL;
   CurrentY:     CARDINAL;
   BotY:         CARDINAL;
   ScrollSize:   CARDINAL;
   PosOnLine:    ARRAY[0..26] OF PositionItem;
   WorkingList:  TACTList;
   CurPos:       PositionItem;

PROCEDURE VariableDisplayLineGenerator;
VAR
   MarchingOrders:     ScrollInstructionPacket;
   ThisGenInfo:        GenInfoPntr;

PROCEDURE ReturnNoLineIndicator;
VAR
   LinePntr:      LineInfoPntr;
BEGIN
   IF MarchingOrders.Return = ReturnLine THEN
      ALLOCATE(LinePntr,SizeOfLineInfoHeader+1);
      WITH LinePntr^ DO
         Size := SizeOfLineInfoHeader+1;
         LineGot := FALSE;
         Text[0] := 0C;
      END;
      send(ThisGenInfo^.FromVariableDispGen,LinePntr);
   END;
END ReturnNoLineIndicator;

PROCEDURE DoTheDisplay;
VAR
   ThisType:     ItemType;
   TokenVA:      VirtAddr;
   TypeVA:       VirtAddr;
   CatVA:        VirtAddr;
   ListPos:      PositionItem;
   NextDirection:ScrollInstruction;

PROCEDURE GenContextLine( VAR DispText : ARRAY OF CHAR; Len : CARDINAL );
   (* note: use "pass by ref" -- no modification of DispText *)
   VAR
	LPlen   : CARDINAL ;
	K	: CARDINAL ;
	LinePntr: LineInfoPntr;
   BEGIN
	IF MarchingOrders.Return = ReturnLine THEN
	   LPlen := Len + 3 + SizeOfLineInfoHeader ;  (* 2 spaces + 0C = 3 *)
	   ALLOCATE(LinePntr, LPlen);
	   WITH LinePntr^ DO
		Size := LPlen;
		Text[0] := ' ' ;
		Text[1] := ' ' ;
		IF Len > 0 THEN Lib.Move(ADR(DispText[0]),ADR(Text[2]),Len) END ;
		Text[Len+2] := 0C ;
		LineGot := TRUE;
		CopyDisplayItem(WorkingList,ListPos,From)
	    END;
	    send( ThisGenInfo^.FromVariableDispGen, LinePntr ) ;
	END ;
   END GenContextLine ;

PROCEDURE DoContext() ;
   VAR
	TokenPntr: DataItemPntr;
	loop	: BOOLEAN ;
	K	: CARDINAL ;
	Len	: CARDINAL ;
	TempLen	: CARDINAL ;
	Offset	: CARDINAL ;
	LText		: StrAny ;
	TempLText	: StrAny ;
	LineDisplayed	: CARDINAL ;
	Limit		: CARDINAL ;
	HighLite	: CARDINAL ;
	DataPtr		: LineBase.LineDataType ;
	TempDataPtr	: LineBase.LineDataType ;
	VariableLineStart	: HRecPntr ;
	BeforeLineStart	: HRecPntr ;
	AfterLineStart	: HRecPntr ;
	HLinePtr	: HRecPntr ;
	TempHLinePtr	: HRecPntr ;
	TokenStart	: HRecPntr ;
	TokenEnd	: HRecPntr ;
	BefOffset	: CARDINAL ;
	AftOffset	: CARDINAL ;
	NotFirstTokenInFile : BOOLEAN ;


   PROCEDURE HighLiteVariable() ;
	VAR
	   I, J	: CARDINAL ;
	BEGIN
	   IF Len + 2 <= HIGH(LText) THEN
	      I := Offset ;
	      WHILE (I <= Len) AND (LText[I] <> ' ') DO
		INC( I ) ;
	      END ;
	      IF I > Len THEN
		 (* highlite to end of line *)
		 LText[Len+1] := IntEnhOff ;
		 LText[Len+2] := 0C ;
		 DEC(I);
	      ELSE
		 (* shift text at end of highlite word *)
		 FOR J := Len TO I BY -1 DO
		    LText[J+2] := LText[J]
		 END ;
		 LText[I+1] := IntEnhOff ;
	      END ;
	      FOR J := I - 1 TO Offset BY -1 DO
		 LText[J+1] := LText[J]
	      END ;
	      LText[Offset] := IntEnhOn ;
	      INC( Len, 2 ) ;
	   (* else will not fit on VAR -- ignore highlighting *)
	   END ;
	END HighLiteVariable ;
	
   PROCEDURE GetGivenTokenInfo(PosData  : HRecPntr;
                           VAR Offset	: CARDINAL) ;
   VAR
      Handle:    HTokenHandle;
      Data:      HTokenData;
   BEGIN
      GetToken(PosData, Handle);
      DecompressTokenInfo(Handle, Data);
      FreeTokenHandle(Handle);
      WITH Data DO
	HLinePtr.Rec := TRecNo ;
	HLinePtr.Idx := TRecPos ;
      END ;
      LineBase.GetLine( HLinePtr, TempLText, TempLen, Offset, TempDataPtr );
   END GetGivenTokenInfo;

   PROCEDURE FindRangeForTokens;
   VAR
	VariableTokenNo:    LONGINT;
	BeforeTokenNo:  LONGINT;
	AfterTokenNo:	LONGINT;
   BEGIN
      GetTokenNo( TokenPntr^.FilePos, VariableTokenNo ) ;
      BeforeTokenNo := VariableTokenNo - VAL(LONGINT,DisplayData[Variable].DispBefore+1) ;
      IF BeforeTokenNo < VAL(LONGINT, 0) THEN
	 BeforeTokenNo := VAL(LONGINT, 0)
      END ;
      WITH TokenStart DO
	Rec := VAL( CARDINAL, BeforeTokenNo DIV VAL(LONGINT,HNoTokens)) + BeginToken ;
	Idx := VAL( CARDINAL, BeforeTokenNo MOD VAL(LONGINT,HNoTokens)) ;
      END ;
      GetGivenTokenInfo(TokenStart, BefOffset);
      BeforeLineStart := TempDataPtr.Start ;

      AfterTokenNo := VariableTokenNo + VAL(LONGINT, DisplayData[Variable].DispAfter) ;
      DEC( AfterTokenNo ) ;  (* use Kludgy form -- Logitech bug in VAL(...) *)
      IF AfterTokenNo > NoTokensInDB THEN
	 AfterTokenNo := NoTokensInDB
      END ;
      WITH TokenStart DO
	Rec := VAL(CARDINAL, AfterTokenNo DIV VAL(LONGINT,HNoTokens)) + BeginToken ;
	Idx := VAL(CARDINAL, AfterTokenNo MOD VAL(LONGINT,HNoTokens)) ;
      END ;
      GetGivenTokenInfo(TokenStart, AftOffset);
      AfterLineStart := TempDataPtr.Start ;
      NotFirstTokenInFile := TRUE;
   END FindRangeForTokens;

   PROCEDURE FindRangeForOthers;
   BEGIN
      WITH DisplayData[Variable] DO
	   GetUnitContext( TokenVA, UnitID, DispBefore, DispAfter,
		      TokenStart, TokenEnd );
      END ;

      (* >>> backup to previous token before range here <<< *)
      IF GetPrevToken( TokenStart, HLinePtr ) THEN
        GetGivenTokenInfo(HLinePtr, BefOffset);
	NotFirstTokenInFile := TRUE ;
      ELSE (* no previous token available *)
	HLinePtr.Rec := 0 ;
	HLinePtr.Idx := 0;
	NotFirstTokenInFile := FALSE ;
        LineBase.GetLine( HLinePtr, TempLText, TempLen, BefOffset, TempDataPtr );
      END ;
      BeforeLineStart := TempDataPtr.Start ;

      GetGivenTokenInfo(TokenEnd, AftOffset);
      AfterLineStart := TempDataPtr.Start ;
   END FindRangeForOthers;

   BEGIN  (* DoContext *)
	TokenPntr := VMAccess(TokenVA);
        IF NOT TokenPntr^.TokenDataLoaded THEN
	   VMMarkChanged(TokenVA);
	   GetTDBTokenData(TokenPntr)
	END;
	WITH TokenPntr^.TokenFileData DO
	   HLinePtr.Rec := TRecNo ;
	   HLinePtr.Idx := TRecPos ;
	END ;
	LineBase.GetLine( HLinePtr, LText, Len, Offset, DataPtr ) ;

	IF DisplayData[Variable].UnitID = 1 (* lines *) THEN
	   VMRelease(TokenVA);
	   WITH DisplayData[Variable] DO
		HighLite := DispBefore + 1 ;
		Limit := HighLite + DispAfter ;
	   END ;
	   LineDisplayed := HighLite ;
	   loop := TRUE ;
	   CASE MarchingOrders.Scroll OF
		Initialize,Top : |
		Down:
		   WHILE loop AND (LineDisplayed > 1) DO
			IF LineBase.GetPrevLine( DataPtr, LText, Len ) THEN
			   DEC( LineDisplayed ) ;
			ELSE
			   loop := FALSE ;
			END ;
		   END ; |
		Up:
		   WHILE loop AND (LineDisplayed < Limit) DO
			IF LineBase.GetNextLine( DataPtr, LText, Len ) THEN
			   INC( LineDisplayed ) ;
			ELSE
			   loop := FALSE ;
			END ;
		   END ;
	   END ;
	
	   LOOP
		IF LineDisplayed = HighLite THEN
		   HighLiteVariable() ;
	        END ;

		GenContextLine( LText, Len ) ;

		receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders ) ;
		CASE MarchingOrders.Scroll OF
(*		     Initialize,Top,Terminate, CloseDown : *)
		     Initialize,Top,Terminate :
			RETURN  |
		     Down :
			INC( LineDisplayed ) ;
			IF LineDisplayed > Limit THEN RETURN  END ;
			IF NOT LineBase.GetNextLine( DataPtr, LText, Len ) THEN
			   RETURN
			END ; |
		     Up :
			DEC( LineDisplayed ) ;
			IF LineDisplayed < 1 THEN RETURN  END ;
			IF NOT LineBase.GetPrevLine( DataPtr, LText, Len ) THEN
			   RETURN  
			END ; 
		END ; 
	   END ; (* LOOP *)

	ELSE (* handle all other units *)

	   VariableLineStart := DataPtr.Start ; (* start of line with Variable *)
	   IF DisplayData[Variable].ContextCount <> TokenPntr^.CurrentContextCount THEN
	      IF DisplayData[Variable].UnitID = 0 (* lines *) THEN FindRangeForTokens
	      ELSE FindRangeForOthers END;

	      VMMarkChanged(TokenVA);
	      TokenPntr^.CurrentContextCount := DisplayData[Variable].ContextCount ;
	      TokenPntr^.StartContext := BeforeLineStart ;
	      TokenPntr^.FinishContext := AfterLineStart ;
	      TokenPntr^.BefOffset := CHR(BefOffset) ;
	      TokenPntr^.AftOffset := CHR(AftOffset) ;
	   ELSE
	      BeforeLineStart	:= TokenPntr^.StartContext ;
	      AfterLineStart	:= TokenPntr^.FinishContext ;
	      BefOffset		:= ORD( TokenPntr^.BefOffset ) ;
	      AftOffset		:= ORD( TokenPntr^.AftOffset ) ;
	      NotFirstTokenInFile :=
		(BeforeLineStart.Rec <> 0) OR (BeforeLineStart.Idx <> 1);
	   END ;
	   VMRelease(TokenVA);
	   loop := TRUE ;
	   CASE MarchingOrders.Scroll OF
	     Initialize,Top : |
	     Down :
		WHILE loop AND ( CompareHRecs(DataPtr.Start, BeforeLineStart) > 0 ) DO
		    loop := LineBase.GetPrevLine( DataPtr, LText, Len ) 
		END ; |
	     Up :
		WHILE loop AND ( CompareHRecs(DataPtr.Start, AfterLineStart) < 0 ) DO
		    loop := LineBase.GetNextLine( DataPtr, LText, Len ) 
		END ; 
	   END ;
	
	   LOOP
		IF (CompareHRecs( DataPtr.Start, BeforeLineStart ) = 0) AND NotFirstTokenInFile THEN
		   IF BefOffset > 0 THEN Lib.Fill(ADR(LText),BefOffset,' ') END;
		   IF DisplayData[Variable].UnitID <> 0 (* words *) THEN
		      K := BefOffset ;
		      WHILE (K <= Len) AND (LText[K] <> ' ') DO
			LText[K] := ' ' ;
			INC( K ) ;
		      END ;   
		      IF (K > Len) THEN
		         IF MarchingOrders.Scroll = Up THEN RETURN  (* no more context here *)
		         ELSE (* Down *)
			   IF NOT LineBase.GetNextLine( DataPtr, LText, Len ) THEN
			      RETURN  
			   END ; 
			 END;
		      END ;
		   END ; 
		END ;
		IF CompareHRecs( DataPtr.Start, AfterLineStart ) = 0 THEN
		   (* blank out from after the last Token to end of line *)
		   K := AftOffset ;
		   WHILE (K <= Len) AND (LText[K] <> ' ') DO
			INC( K ) ;
		   END ;
		   IF (K < Len) THEN
		      LText[K] := 0C;
		      Len := K;
		      END;
(*		   Lib.Fill(ADR(LText[K],Len - K + 1, ' '); *)
		END ;
		IF CompareHRecs( DataPtr.Start, VariableLineStart ) = 0 THEN
		   HighLiteVariable()
		END ;
		GenContextLine( LText, Len ) ;	
		receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders ) ;
		CASE MarchingOrders.Scroll OF
(*		     Initialize,Top, Terminate, CloseDown : *)
		     Initialize,Top, Terminate :
			RETURN  |
		     Down :
			IF CompareHRecs(DataPtr.Start, AfterLineStart) >= 0 THEN RETURN  END ;
			IF NOT LineBase.GetNextLine( DataPtr, LText, Len ) THEN
			   RETURN  
			END ; |
		     Up :
			IF CompareHRecs(DataPtr.Start, BeforeLineStart) <= 0 THEN RETURN  END ;
			IF NOT LineBase.GetPrevLine( DataPtr, LText, Len ) THEN
			   RETURN
			END ;
		END ;
	   END ;
	END ;
   END DoContext ;

PROCEDURE DoRef( FlushType : TabType );
   VAR
	RefText:	StrAny;
	Line:		StrAny;
	LP:		CARDINAL;
	len:		CARDINAL;
	RefLen:		CARDINAL;
	LinePntr:	LineInfoPntr;
   BEGIN
	IF MarchingOrders.Return <> ReturnLine THEN RETURN END;
	
	LP := 0;
	SWriteString(Line, LP, '  ', 0);
	CreateRef( DisplayData[Variable].EncodedRefInfo,
		DisplayData[Variable].EncodedRefLen, TokenVA, RefText, RefLen,
		DisplayData[Variable].DisplayWordCountWord ) ;
	Line[LP] := IntEnhOn ;
	INC( LP ) ;
	
	IF (FlushType = Right) AND (DisplayData[Variable].WindInfo.XSize - 2 >= RefLen) THEN
	   WITH VariableDisplayTab[0] DO
		Pos := DisplayData[Variable].WindInfo.XSize - 2 ;
		FilPat := 304C ; (* should use IntRuleChar - not exported ... yet JB?? *)
		Type := Right ;
	   END ;	
	   Line[LP] := IntTab ;
	   INC( LP ) ;
	   Line[LP] := ' ' ; (* a blank after rule line *)
	   INC( LP ) ;
	ELSE  (* Left or does not fit in window size -- make it flush Left *)
	   WITH VariableDisplayTab[0] DO
		Pos := 0 ;
		FilPat := '' ;
		Type := Left ;
	   END ;
	END ;
	SWriteString(Line, LP, RefText, 0);
	Line[LP] := IntEnhOff ;
	INC( LP ) ;
	Line[LP] := 0C ;

	len := LP + SizeOfLineInfoHeader + 1;
	ALLOCATE(LinePntr,len);
	WITH LinePntr^ DO
	   Size := len;
	   Str.Copy( Text, Line );
	   LineGot := TRUE;
	   CopyDisplayItem(WorkingList,ListPos,From)
	END;
	send(ThisGenInfo^.FromVariableDispGen,LinePntr);
    END DoRef ;

PROCEDURE DoBar() ;
   VAR
	len:		CARDINAL;
	LinePntr:	LineInfoPntr;
   BEGIN
	IF MarchingOrders.Return <> ReturnLine THEN RETURN END;	

	VariableDisplayTab[0].Pos := DisplayData[Variable].WindInfo.XSize - 3 ;
	VariableDisplayTab[0].FilPat := 304C ; (* should use IntRuleChar - not exported ... yet JB?? *)  
	VariableDisplayTab[0].Type := Right ;

	len := 5 + SizeOfLineInfoHeader;
	ALLOCATE(LinePntr,len);
	WITH LinePntr^ DO
	   Size := len;
	   Text[0] := ' ' ;
	   Text[1] := ' ' ;
	   Text[2] := IntTab ;
	   Text[3] := ' ' ; (* a blank after rule Line *) 
	   Text[4] := 0C ;
	   LineGot := TRUE;
	   CopyDisplayItem(WorkingList,ListPos,From)
	END;
	send(ThisGenInfo^.FromVariableDispGen,LinePntr);
    END DoBar ;

PROCEDURE GetNewPosInfo(MoveDir:   ScrollInstruction): BOOLEAN;
VAR
   NextExists:   BOOLEAN;
BEGIN
   IF MoveDir = Down THEN
      NextExists := NextDisplayItem(WorkingList, ListPos)
   ELSIF MoveDir = Up THEN
      NextExists := PrevDisplayItem(WorkingList, ListPos)
   ELSE
      NextExists := TRUE;
   END;

   IF NextExists THEN
      GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);
      RETURN TRUE
   ELSE
      ReturnNoLineIndicator;
      RETURN FALSE
   END;
END GetNewPosInfo;

PROCEDURE DoTypeItem();
   VAR  Dummy : BOOLEAN ;
   BEGIN
	CASE MarchingOrders.Scroll OF
	   Initialize,Top,
	   Down :
		LOOP 
		   DoContext() ;
		   CASE MarchingOrders.Scroll OF
(*			Initialize,Top, Terminate, CloseDown, Up : *)
			Initialize,Top, Terminate, Up :
			   RETURN  |
			Down :
			   DoRef( (* Flush *) Right ) ;
			   receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders );
			   IF MarchingOrders.Scroll <> Up THEN
				RETURN
			   END ;
		   END ;
		END ; (* LOOP *)  |
	   Up :
		LOOP 
		   DoRef( (* Flush *) Right ) ;
		   receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders );
		   CASE MarchingOrders.Scroll OF
(*			Initialize,Top, Terminate, CloseDown, Down : *)
			Initialize,Top, Terminate, Down :
			   RETURN  |
			Up :
			   DoContext() ;
			   IF MarchingOrders.Scroll <> Down THEN
				RETURN
			   END ;
		   END ;
		END ; (* LOOP *)  
	END ; 
   END DoTypeItem;

PROCEDURE DoTypeHeader();
VAR
   len:           CARDINAL;
   TString:       StrAny;
   LP:            CARDINAL;
   LinePntr:      LineInfoPntr;
BEGIN
   IF MarchingOrders.Return <> ReturnLine THEN RETURN END;

   PrepareDisplayForItem(ListPos,99,'',0,TString);
   len := Str.Length(TString) + SizeOfLineInfoHeader + 3 ;
   ALLOCATE(LinePntr,len);

   WITH LinePntr^ DO
      Size := len;
      LP := 0;
      SWriteString(Text,LP,'  ',0);
      SWriteString(Text,LP,TString,0);
      LineGot := TRUE;
      CopyDisplayItem(WorkingList,ListPos,From);
   END;
   send(ThisGenInfo^.FromVariableDispGen,LinePntr);
END DoTypeHeader;

PROCEDURE HandleType(): ScrollInstruction;
VAR
   CurrentType:     VirtAddr;
BEGIN
   CurrentType := TypeVA;
   WHILE TypeVA = CurrentType DO
      IF TokenVA = NILVirt THEN 
	 DoTypeHeader();
	 receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders );
      ELSE 
	 DoTypeItem()
      END;
      IF (MarchingOrders.Scroll = Initialize) OR
(*    (MarchingOrders.Scroll = Top) OR (MarchingOrders.Scroll = CloseDown) OR *)
      (MarchingOrders.Scroll = Top) OR
	 (MarchingOrders.Scroll = Terminate) THEN RETURN MarchingOrders.Scroll END ;
      WHILE NOT GetNewPosInfo(MarchingOrders.Scroll) DO
         receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders );
	 IF (MarchingOrders.Scroll = Initialize) OR
(*       (MarchingOrders.Scroll = Top) OR (MarchingOrders.Scroll = CloseDown) OR *)
         (MarchingOrders.Scroll = Top) OR
	    (MarchingOrders.Scroll = Terminate) THEN RETURN MarchingOrders.Scroll END ;
      END ;
   END;
   RETURN MarchingOrders.Scroll;
END HandleType;

PROCEDURE HandleToken(): ScrollInstruction;

   PROCEDURE DoTokenItem ;
      TYPE 
	 States = ( context, ref, bar ) ;
      VAR
	 State : States ;
      BEGIN  
	CASE MarchingOrders.Scroll OF
	   Initialize : State := context |
	   Down,Top : State := ref |
	   Up :   State := bar ;
	END ;
	LOOP 
	   CASE State OF
	      ref:
		   DoRef( (* Flush *) Left ) ;
		   receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders );
		   CASE MarchingOrders.Scroll OF
(*			Initialize,Terminate, CloseDown, Top, Up : *)
			Initialize,Terminate, Top, Up :
			   RETURN  |
			Down :
			   State := context ;
		   END |
	      context:
		   DoContext() ;
		   CASE MarchingOrders.Scroll OF
(*			Initialize,Top,Terminate, CloseDown : *)
			Initialize,Top,Terminate :
			   RETURN  |
			Down :
			   State := bar |
			Up :
			   State := ref ;
		   END |
	      bar: 
		   DoBar() ;
		   receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders );
		   IF MarchingOrders.Scroll = Up THEN
			State := context 
		   ELSE
			RETURN 
		   END ;
	   END ;
	END ; (* LOOP *)
      END DoTokenItem ;
      
   BEGIN
	DoTokenItem ;
	IF (MarchingOrders.Scroll = Initialize) OR
(*         (MarchingOrders.Scroll = Top) OR (MarchingOrders.Scroll = CloseDown) OR *)
           (MarchingOrders.Scroll = Top) OR
	   (MarchingOrders.Scroll = Terminate) THEN RETURN MarchingOrders.Scroll END ;
	WHILE NOT GetNewPosInfo(MarchingOrders.Scroll) DO
	   receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders ) ;
	END ;
	RETURN MarchingOrders.Scroll;
   END HandleToken;

BEGIN  (* DoTheDisplay *)
   LOOP (* permanently *)
      InitialDisplayItem(ListPos);
      CASE MarchingOrders.Scroll OF
        Initialize: CopyDisplayItem(WorkingList,CurPos, ListPos)
      | Top:
           IF NOT FirstDisplayItem(WorkingList, ListPos) THEN
               ProgramErrorAndHalt('unexpected problem in DoNewItem')
           END;
      ELSE ProgramErrorAndHalt('unexpected beginning to DoNewItem')
      END;
      GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);

      NextDirection := Down;
      REPEAT
         CASE ThisType OF
           CatType:    ProgramErrorAndHalt('CatType not yet supported here!')
         | TypeType:
              NextDirection := HandleType();
         | TokenType:
              NextDirection := HandleToken();
         ELSE
              ProgramErrorAndHalt('Illegal DataType in List')
         END;
      UNTIL (NextDirection = Initialize) OR (NextDirection = Terminate) OR
      (NextDirection = Top) OR (NextDirection = CloseDown);
      DiscardDisplayItem(WorkingList,ListPos);
      
      IF NextDirection = Terminate THEN
         ReturnNoLineIndicator;
         receive( ThisGenInfo^.ToVariableDispGen, MarchingOrders );
      END;
      IF MarchingOrders.Scroll = CloseDown THEN TACTProcesses.Terminate END;
   END;
END DoTheDisplay;

BEGIN  (* VariableDisplayLineGenerator *)
   ThisGenInfo := QueueOfGenInfos;
   IF ThisGenInfo = NIL THEN
      ProgramErrorAndHalt('No GenInfos Available')
   END;
   QueueOfGenInfos := QueueOfGenInfos^.Next;

   attachreceiver (ThisGenInfo^.ToVariableDispGen);
   attachsender (ThisGenInfo^.FromVariableDispGen);

   receive(ThisGenInfo^.ToVariableDispGen,MarchingOrders);
   IF (MarchingOrders.Scroll <> Initialize) AND
   (MarchingOrders.Scroll <> Top) THEN
       ProgramErrorAndHalt('Bad initial MarchingOrders')
   END;

   DoTheDisplay;  (* never returns from this routine *)
END VariableDisplayLineGenerator;

PROCEDURE LaunchVariableDisplayLineGenerator(VAR Info: GenInfoPntr);
BEGIN
   NEW(Info);
   Info^.Next := QueueOfGenInfos;
   QueueOfGenInfos := Info;
   WITH Info^ DO
      open (ToVariableDispGen);
      open (FromVariableDispGen);
      TACTProcesses.StartProcess (VariableDisplayLineGenerator, WSSize);
      attachsender(ToVariableDispGen);
      attachreceiver(FromVariableDispGen);
   END;
END LaunchVariableDisplayLineGenerator;

PROCEDURE GetLine(Type:   ScrollInstruction;
                  TB:     GenInfoPntr;
              VAR Ptr:    LineInfoPntr):BOOLEAN;
VAR
   MarchingOrders:     ScrollInstructionPacket;
BEGIN
   MarchingOrders.Scroll := Type;
   MarchingOrders.Return := ReturnLine;
   send(TB^.ToVariableDispGen,MarchingOrders);
   receive(TB^.FromVariableDispGen,Ptr);
   RETURN Ptr^.LineGot;
END GetLine;

PROCEDURE MoveLine(Type:   ScrollInstruction;
                   TB:     GenInfoPntr);
VAR
   MarchingOrders:     ScrollInstructionPacket;
BEGIN
   MarchingOrders.Scroll := Type;
   MarchingOrders.Return := NoReturnLine;
   send(TB^.ToVariableDispGen,MarchingOrders);
END MoveLine;

PROCEDURE CloseDownVariableDisplayLineGenerator(VAR Info: GenInfoPntr);
BEGIN
   MoveLine(CloseDown,Info);  (* this terminates remote processes *)
   TACTProcesses.YIELD;
   WITH Info^ DO
      close (ToVariableDispGen);
      close (FromVariableDispGen);
   END;
   DISPOSE(Info);
   Info := NIL;
END CloseDownVariableDisplayLineGenerator;
(*Empty>*)

PROCEDURE HandleVariableDisplay(KeyInstruction: ScrollKey);
(*<Empty*)
VAR
   rc, I:           CARDINAL;

PROCEDURE ScrollDisplayDown(): BOOLEAN;
VAR i:    CARDINAL;
BEGIN
   ScrollDown(DisplayData[Variable].WindID,1);
   FOR i := BotY TO 0 BY -1 DO
     PosOnLine[i+1] := PosOnLine[i];
   END;
   InitialDisplayItem(PosOnLine[0]);
   IF BotY >= DisplayData[Variable].WindInfo.YSize-1 THEN
      DiscardDisplayItem(WorkingList,PosOnLine[BotY+1]);
      RETURN TRUE;
   ELSE
      INC(BotY);
      RETURN FALSE;
   END;
END ScrollDisplayDown;

PROCEDURE ScrollDisplayUp;
VAR i:    CARDINAL;
BEGIN
   ScrollUp(DisplayData[Variable].WindID,1);
   DiscardDisplayItem(WorkingList,PosOnLine[0]);
   FOR i := 1 TO BotY DO
     PosOnLine[i-1] := PosOnLine[i];
   END;
   InitialDisplayItem(PosOnLine[BotY]);
END ScrollDisplayUp;

PROCEDURE InitialDisplay;
VAR i:     CARDINAL;
    dummy: BOOLEAN;
BEGIN
   WITH DisplayData[Variable] DO
      TWB.SetManualUpdate(WindID);
      TWB.Clear;
      LinesBefore := WindInfo.YSize DIV 4;
      LinesAfter := WindInfo.YSize - LinesBefore;
      ScrollSize := WindInfo.YSize DIV 2;
      FOR CurrentY := 0 TO 26 DO
          DiscardDisplayItem(WorkingList,PosOnLine[CurrentY])
      END;

      IF NOT GetLine(Initialize,TopDat,TopLPtr) THEN
         ProgramErrorAndHalt('Error Initializing')
      END;
      FancyScreenDisplay(WindID,0,0,TopLPtr^.Text,VariableDisplayTab,FALSE);
      PosOnLine[0] := TopLPtr^.From;
      DEALLOCATE(TopLPtr,TopLPtr^.Size);
      CurrentY := 0;
      BotY := 0;
      WHILE (CurrentY <= LinesBefore) AND GetLine(Up,TopDat,TopLPtr) DO
         dummy := ScrollDisplayDown();
         INC(CurrentY);
         PosOnLine[0] := TopLPtr^.From;
         FancyScreenDisplay(WindID,0,0,TopLPtr^.Text,VariableDisplayTab,FALSE);
         DEALLOCATE(TopLPtr,TopLPtr^.Size);
      END;
      ChangeColorOnScreen(BoldAttr,0,CurrentY,1);
      TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
      IF (CurrentY <= LinesBefore) THEN
         DEALLOCATE(TopLPtr,TopLPtr^.Size)
      END ;

      BotY := CurrentY+1;
      MoveLine(Initialize,BottomDat);
      WHILE (BotY < WindInfo.YSize) AND GetLine(Down,BottomDat,BottomLPtr) DO
         FancyScreenDisplay(WindID,0,BotY,BottomLPtr^.Text,VariableDisplayTab, FALSE);
         PosOnLine[BotY] := BottomLPtr^.From;
         DEALLOCATE(BottomLPtr,BottomLPtr^.Size);
         INC(BotY);
      END;
      IF BotY < WindInfo.YSize THEN
         DEALLOCATE(BottomLPtr,BottomLPtr^.Size)
      END ;
      DEC(BotY);

      TWB.GotoXY(0,0);
      TWB.SetAutoUpdate(WindID);
   END;
END InitialDisplay;

PROCEDURE ResetSelectedListPos;
BEGIN
   IF ((PosListStatus = PosMade) AND (DisplayData[Variable].VariableDispOrg = DispPosition))
	OR (DisplayData[Variable].VariableDispOrg = DispType) THEN
      DiscardDisplayItem(SelectedList,SelectedListPos);
      IF NOT FindDisplayItem(WorkingList,CurPos,
                             SelectedList, SelectedListPos) THEN
         ProgramErrorAndHalt('Could not find corresponding item')
      END
   END;
END ResetSelectedListPos;

PROCEDURE ResetCurrentPositions;
BEGIN
   DiscardDisplayItem(WorkingList,CurPos);
   CopyDisplayItem(WorkingList,PosOnLine[CurrentY],CurPos);
   ResetSelectedListPos;
END ResetCurrentPositions;

PROCEDURE DoCursorDown(): BOOLEAN;
BEGIN
   WITH DisplayData[Variable] DO
      TWB.InitTextOnScreen(' ',0,CurrentY,1);
      ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
      INC(CurrentY);
      IF (CurrentY > LinesAfter) OR (CurrentY > BotY) THEN
        IF GetLine(Down,BottomDat,BottomLPtr) THEN
          ScrollDisplayUp;
          DEC(CurrentY);
          FancyScreenDisplay(WindID,0,BotY,BottomLPtr^.Text,VariableDisplayTab,FALSE);
          PosOnLine[BotY] := BottomLPtr^.From;
          DEALLOCATE(BottomLPtr,BottomLPtr^.Size);
          MoveLine(Down,TopDat)
        ELSE
          IF CurrentY > BotY THEN
             DEC(CurrentY);
             ChangeColorOnScreen(BoldAttr, 0,CurrentY,1);
             TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
             RETURN FALSE
          END
        END;
      END;
      TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
      ChangeColorOnScreen(BoldAttr,0,CurrentY,1);
      TWB.GotoXY(0,0);
      ResetCurrentPositions;
   END;
   RETURN TRUE
END DoCursorDown;

PROCEDURE DoCursorUp(): BOOLEAN;
BEGIN
   WITH DisplayData[Variable] DO
      IF CurrentY = 0 THEN RETURN FALSE END;
      TWB.InitTextOnScreen(' ',0,CurrentY,1);
      ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
      DEC(CurrentY);
      IF (CurrentY < LinesBefore) THEN
        IF GetLine(Up,TopDat,TopLPtr) THEN
          IF ScrollDisplayDown() THEN MoveLine(Up,BottomDat) END;
          INC(CurrentY);
          FancyScreenDisplay(WindID,0,0,TopLPtr^.Text,VariableDisplayTab,FALSE);
          PosOnLine[0] := TopLPtr^.From;
          DEALLOCATE(TopLPtr,TopLPtr^.Size);
        END;
      END;
      TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
      ChangeColorOnScreen(BoldAttr,0,CurrentY,1);
      TWB.GotoXY(0,0);
      ResetCurrentPositions;
   END;
   RETURN TRUE
END DoCursorUp;

PROCEDURE DisplayEmptyMessage;
VAR rc:    CARDINAL;
    temp:  StrAny;
BEGIN
   WITH DisplayData[Variable] DO
      TWB.Clear;
      (*RES OLD MSG 180
      No Variable Context can be displayed.
      *)
      GetResMessage( (*RES REM INS*) 180 , temp);
      WriteScreenField(WindID,0,0,0,temp,RegularAttr,TRUE);
   END;
END DisplayEmptyMessage;

PROCEDURE TerminateDisplay;
   VAR
      dummy:   BOOLEAN;
      temp:    LineInfoPntr;
   BEGIN
      FOR CurrentY := 0 TO 26 DO
          DiscardDisplayItem(WorkingList,PosOnLine[CurrentY])
      END;
      dummy := GetLine(Terminate,TopDat,temp);
      DEALLOCATE(temp,temp^.Size);
      dummy := GetLine(Terminate,BottomDat,temp);
      DEALLOCATE(temp,temp^.Size);
   END TerminateDisplay ;

PROCEDURE InitialLists;
BEGIN
   IF (DisplayData[Variable].VariableDispOrg = DispType) THEN
      IF NOT ListByTypeMade THEN
         MakeWordList(SelectedList, ListByType);
         ListByTypeMade := TRUE
      END;
      WorkingList := ListByType;
      CurPos := TypeListPos;
   ELSIF (DisplayData[Variable].VariableDispOrg = DispPosition) AND
	 (PosListStatus <> PosOnly) THEN
      IF PosListStatus = NoPos THEN
         PosListStatus := PosMade;
         MakePosList(SelectedList, ListByPosition);
      END;
      WorkingList := ListByPosition;
      CurPos := PositionListPos;
   ELSE
      WorkingList := SelectedList;
      CurPos := SelectedListPos;
      RETURN
   END;
   DiscardDisplayItem( WorkingList, CurPos );
   IF NOT FindDisplayItem(SelectedList, SelectedListPos,
			  WorkingList, CurPos) THEN
          ProgramErrorAndHalt('Could not synchonize Selected & Working list')
   END;
END InitialLists;
(*Empty>*)

BEGIN  (* HandleVariableDisplay *)
(*<Empty*)
   TWB.Use(DisplayData[Variable].WindID);
   IF SelectedListEmpty THEN
      IF KeyInstruction = InitKey THEN DisplayEmptyMessage
      ELSIF KeyInstruction <> TermKey THEN Beep END;
      RETURN
   END;
   IF InitLineProcs THEN
      InitLineProcs := FALSE;
      LaunchVariableDisplayLineGenerator(TopDat);
      LaunchVariableDisplayLineGenerator(BottomDat);
   END;
   CASE KeyInstruction OF
     InitKey:
        InitialLists;
        InitialDisplay;
   | TermKey:
	TerminateDisplay ;
	RETURN ;
   | CloseDownKey:
       TerminateDisplay;
       InitLineProcs := TRUE;
       CloseDownVariableDisplayLineGenerator(TopDat);
       CloseDownVariableDisplayLineGenerator(BottomDat);
       RETURN;
   | UpKey:
       IF NOT DoCursorUp() THEN  Beep ; RETURN  END;
   | DownKey:
       IF NOT DoCursorDown() THEN  Beep ; RETURN  END;
   | HomeKey:
	DiscardDisplayItem(WorkingList, CurPos);
	IF NOT FirstDisplayItem(WorkingList, CurPos) THEN
	   ProgramErrorAndHalt('Problem finding first item in list')
	END;
	InitialDisplay;
	ResetSelectedListPos;
   | EndKey:
	DiscardDisplayItem(WorkingList, CurPos);
	IF NOT LastDisplayItem(WorkingList, CurPos) THEN
	   ProgramErrorAndHalt('Problem finding last item in list')
	END;
	InitialDisplay;
	ResetSelectedListPos;
   | PgUpKey:
       TWB.SetManualUpdate( DisplayData[Variable].WindID ) ;
       TWB.InitTextOnScreen(' ',0,CurrentY,1);
       ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
       CurrentY := 2 ;
       FOR I := 1 TO DisplayData[Variable].WindInfo.YSize - 1 DO
          IF NOT DoCursorUp() THEN Beep ;
             TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
             ChangeColorOnScreen(BoldAttr,0,CurrentY,1);
             TWB.SetAutoUpdate( DisplayData[Variable].WindID ) ;
             RETURN END;
       END ;
       TWB.SetAutoUpdate( DisplayData[Variable].WindID ) ;
   | PgDnKey:
       TWB.SetManualUpdate( DisplayData[Variable].WindID ) ;
       TWB.InitTextOnScreen(' ',0,CurrentY,1);
       ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
       CurrentY := BotY ;
       FOR I := 1 TO DisplayData[Variable].WindInfo.YSize - 1 DO
          IF NOT DoCursorDown() THEN  Beep ;
            TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
            ChangeColorOnScreen(BoldAttr,0,CurrentY,1);
            TWB.SetAutoUpdate( DisplayData[Variable].WindID ) ;
            RETURN END;
       END ;
       TWB.SetAutoUpdate( DisplayData[Variable].WindID ) ;
   | AltPgUpKey:
	IF NOT PrevDisplayItem(WorkingList, CurPos) THEN
	   Beep;
	   RETURN
	END;
	InitialDisplay;
	ResetSelectedListPos;
   | AltPgDnKey:
	IF NOT NextDisplayItem(WorkingList, CurPos) THEN
	   Beep;
	   RETURN
	END;
	InitialDisplay;
	ResetSelectedListPos;
   ELSE
      Beep ; RETURN
   END;
   IF NOT SelectedListEmpty THEN
      IF (DisplayData[Variable].VariableDispOrg = DispType) THEN
(*       ResetSelectedListPos; *)
         TypeListPos := CurPos
      ELSIF (DisplayData[Variable].VariableDispOrg = DispPosition) AND (PosListStatus <> PosOnly) THEN
(*       ResetSelectedListPos; *)
         PositionListPos := CurPos
      ELSE SelectedListPos := CurPos
      END
   END;
(*Empty>*)
END HandleVariableDisplay ;

PROCEDURE OutputVariableDisplay(VAR file: XFileType; CheckAbort: AbortProc);
VAR
   LineInfo:   LineInfoPntr;
   status:     BOOLEAN;
   NoLines:    CARDINAL;
   result:     CARDINAL;
BEGIN
(*<Empty*)
   IF SelectedListEmpty THEN
      (*RES OLD MSG 250
      There is no Variable Context Display for printing or writing to a file.
      *)
      PutResError( (*RES REM INS*) 250 );
      RETURN
   END;

   LaunchVariableDisplayLineGenerator(PrintDat);
   status := GetLine(Top,PrintDat,LineInfo);
   NoLines := 1 ;
   REPEAT
      status := WriteWithTabs(file, LineInfo^.Text,VariableDisplayTab);
      DiscardDisplayItem(WorkingList, LineInfo^.From);
      DEALLOCATE(LineInfo,LineInfo^.Size);
      INC( NoLines ) ;
      IF (PrintDest = ToPrinter) AND (NoLines > LinesPerPage) THEN
         XWrNXlate( file, ASCII.ff, result);
         NoLines := 1 ;
      END ;
   UNTIL (NOT status) OR CheckAbort() OR (NOT GetLine(Down,PrintDat,LineInfo));
   DEALLOCATE(LineInfo,LineInfo^.Size);  (* return mem from failure in GetLine - ReturnNoLineIndicator *)
   status := GetLine(Terminate,PrintDat,LineInfo);
   DEALLOCATE(LineInfo,LineInfo^.Size);
   CloseDownVariableDisplayLineGenerator(PrintDat);
(*Empty>*)
END OutputVariableDisplay;

PROCEDURE InitializeVariableDisplay;
BEGIN
(*<Empty*)
   InitLineProcs := TRUE;
   QueueOfGenInfos := NIL;
   WITH VariableDisplayTab[0] DO
      Pos := 3 ;
      Type := Left;
      FilPat := '';
   END;
   FOR CurrentY := 0 TO 26 DO InitialDisplayItem(PosOnLine[CurrentY]) END;
(*Empty>*)
END InitializeVariableDisplay;
END VariDisplay.
