IMPLEMENTATION MODULE KWICDisplay;

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
(*V3=Debug *)


FROM Translations IMPORT Int2Scr;
FROM ScrollMessages IMPORT
   (* const*) SizeOfLineInfoHeader,
   (* type *) ScrollInstruction, ReturnInstruction, LineInformation,
              LineInfoPntr, ScrollInstructionPacket, ScrollKey;
FROM PrintModule IMPORT AbortProc, WriteWithTabs, PrintDest, LinesPerPage,
		PrintActionType ;

(*<Empty*)

IMPORT TWB, Str, ASCII ;
IMPORT TACTProcesses;
FROM GlobalDefs IMPORT StrAny;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM Utils IMPORT Beep ;
FROM KeyTranslation IMPORT
  (* Const *) IntTab,
  (* Type  *) TabInfo, TabType,
  (* Procs *) FancyScreenDisplay, WriteScreenField;
FROM MainLists IMPORT
  (* type *) PosListStatusType,
  (* vars *) SelectedList, ListByPosition,
             PosListStatus, SelectedListPos, PositionListPos,
             SelectedListEmpty, ListByType, TypeListPos, ListByTypeMade;
FROM ListData IMPORT
  (* types *) ItemType,DataItemPntr,
  (* procs *) MakeStringData;
FROM TACTListModule IMPORT
  (* types *) TACTList;
FROM PositionManagement IMPORT
  (* types *) PositionItem,
  (* procs *) GetPosData, FirstDisplayItem,
              LastDisplayItem, CopyDisplayItem, NextDisplayItem,
              PrevDisplayItem, GetParentMainItem, NextMainItem, PrevMainItem,
              FindDisplayItem, DiscardDisplayItem,
              InitialDisplayItem, PrepareDisplayForItem;
FROM ListUtils IMPORT MakePosList, MakeWordList;
FROM WordBase IMPORT
              SortToIntWord;
FROM channels IMPORT
  (* type *) channel,
  (* proc *) open, close, attachsender, attachreceiver, send, receive,
             datawaiting;
FROM Windows IMPORT
  (* Const *) RegularAttr, BoldAttr,
  (* Procs *) ScrollUp, ScrollDown, ChangeColorOnScreen;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM StackWindows IMPORT WindowInfo;
FROM DisplayDialog IMPORT
  (* type *) DisplayType, DisplayDataType, DispOrg,
  (* vars *) DisplayData, CurrentDisplay;
FROM HyperBase IMPORT HRecPntr;
FROM HyperDataModel IMPORT
  (* Types *) HTypeData;
FROM DBData IMPORT
    (* vars  *) BeginText;
FROM ResMessages IMPORT
   (*proc*)  GetResMessage, PutResError;
FROM TokenBase IMPORT
  (* procs *) GetTokenNo;
FROM RefValBase IMPORT
  (* Procs *) CreateRef ;
FROM CitationTools IMPORT
  (* procs*) FillOutWithCitation;
FROM Translations IMPORT XFileType, XWrNXlate;
FROM TACTDataServices IMPORT GetTDBTokenData;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMAccess, VMMarkChanged, VMRelease;

CONST
   WSSize = 5000;
   MarkerSymbol = 020C;

TYPE
   GenInfoPntr = POINTER TO GenInfo;
   GenInfo = RECORD
      Next:              GenInfoPntr;
      ToKWICDispGen:    channel;
      FromKWICDispGen:  channel;
   END;

VAR
   QueueOfGenInfos:      GenInfoPntr;
   KWICDisplayTab:      ARRAY[0..0] OF TabInfo;
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
   XLength:      CARDINAL;
   CitCentre:    CARDINAL;
   WorkingList:  TACTList;
   CurPos:       PositionItem;
   (*<Debug
   DummyThisType: ItemType;
   DummyTokenVA:  VirtAddr;
   DummyTypeVA:   VirtAddr;
   DummyCatVA:    VirtAddr;
   Debug>*)

PROCEDURE KWICDisplayLineGenerator;
VAR
   MarchingOrders:     ScrollInstructionPacket;
   ThisGenInfo:        GenInfoPntr;
(* CurrentPos:         PositionItem; *)

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
      send(ThisGenInfo^.FromKWICDispGen,LinePntr);
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

PROCEDURE ReturnTokenLine(TokenVA:   VirtAddr);
VAR
   TokenPntr:      DataItemPntr;
   TokenNo:        LONGINT;
   RefText:	   StrAny;
   Line:           StrAny;
   LP:             CARDINAL;
   RefLen:	   CARDINAL;
   len:            CARDINAL;
   LinePntr:       LineInfoPntr;
   FP:             HRecPntr;
BEGIN
   IF MarchingOrders.Return <> ReturnLine THEN RETURN END;

   LP := 0;
   SWriteString(Line, LP, '  ', 0);
   CreateRef( DisplayData[KWIC].EncodedRefInfo,
		DisplayData[KWIC].EncodedRefLen, TokenVA, RefText, RefLen,
		DisplayData[KWIC].DisplayWordCountWord ) ;
   SWriteString(Line, LP, RefText, 0);

   IF DisplayData[KWIC].ShowText THEN
      IF LP > CitCentre - 2 THEN (* added j.b. Feb 28/91 *)
         LP := CitCentre - 2;
         Line[LP] := 0C;
         Line[LP-1] := '.';
         Line[LP-2] := '.';
         Line[LP-3] := '.';
      END;
      TokenPntr := VMAccess(TokenVA);
      IF NOT TokenPntr^.TokenDataLoaded THEN
         VMMarkChanged(TokenVA);
         GetTDBTokenData(TokenPntr)
      END;
      FP.Rec := TokenPntr^.TokenFileData.TRecNo;
      FP.Idx := TokenPntr^.TokenFileData.TRecPos;
      VMRelease(TokenVA);
      FillOutWithCitation(FP,Int2Scr,XLength,CitCentre,FALSE,Line)
   END;

   len := Str.Length(Line) + SizeOfLineInfoHeader + 1;
   ALLOCATE(LinePntr,len);
   WITH LinePntr^ DO
      Size := len;
      Str.Copy(Text,Line);
      LineGot := TRUE;
      CopyDisplayItem(WorkingList,ListPos,From)
   END;
   send(ThisGenInfo^.FromKWICDispGen,LinePntr);
END ReturnTokenLine;

PROCEDURE ReturnTypeHeader(TypeVA:     VirtAddr);
VAR
   len:           CARDINAL;
   TString:       StrAny;
   LP:            CARDINAL;
   LinePntr:      LineInfoPntr;
BEGIN
   IF MarchingOrders.Return <> ReturnLine THEN RETURN END;

   PrepareDisplayForItem( ListPos, 99, DisplayData[KWIC].EncodedRefInfo,
	   DisplayData[KWIC].EncodedRefLen, TString );
   len := Str.Length(TString) + SizeOfLineInfoHeader + 3;
   ALLOCATE(LinePntr,len);
   WITH LinePntr^ DO
      Size := len;
      LP := 0;
      SWriteString(Text,LP,'  ',0);
      SWriteString(Text,LP,TString,0);
      LineGot := TRUE;
      CopyDisplayItem(WorkingList,ListPos,From);
   END;
   send(ThisGenInfo^.FromKWICDispGen,LinePntr);
END ReturnTypeHeader;

PROCEDURE GetNewPosInfo(MoveDir:   ScrollInstruction): BOOLEAN;
VAR
   NextExists:   BOOLEAN;
BEGIN
   IF DisplayData[KWIC].KWICDispOrg = DispTypeOnly THEN
	IF MoveDir = Down THEN
	   NextExists := NextMainItem(WorkingList, ListPos)
	ELSIF MoveDir = Up THEN
	   NextExists := PrevMainItem(WorkingList, ListPos)
	ELSE
	   NextExists := TRUE;
	END;
   ELSE
	IF MoveDir = Down THEN
	   NextExists := NextDisplayItem(WorkingList, ListPos)
	ELSIF MoveDir = Up THEN
	   NextExists := PrevDisplayItem(WorkingList, ListPos)
	ELSE
	   NextExists := TRUE;
	END;
   END ;

   IF NextExists THEN
      GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);
      RETURN TRUE
   ELSE
      ReturnNoLineIndicator;
      RETURN FALSE
   END;
END GetNewPosInfo;

PROCEDURE HandleToken(): ScrollInstruction;
BEGIN
   ReturnTokenLine(TokenVA);

   REPEAT
      receive(ThisGenInfo^.ToKWICDispGen,MarchingOrders);
      IF (MarchingOrders.Scroll = Initialize) OR
      (MarchingOrders.Scroll = Top) OR
      (MarchingOrders.Scroll = Terminate) THEN
          RETURN MarchingOrders.Scroll
      END;
   UNTIL GetNewPosInfo(MarchingOrders.Scroll);

   RETURN MarchingOrders.Scroll;
END HandleToken;

PROCEDURE HandleType() : ScrollInstruction;
VAR
   CurrentType:     VirtAddr;
   NextDir:         ScrollInstruction;
BEGIN
   CurrentType := TypeVA;
   WHILE TypeVA = CurrentType DO
      IF (TokenVA = NILVirt) OR (DisplayData[KWIC].KWICDispOrg = DispTypeOnly) THEN
	 IF (DisplayData[KWIC].KWICDispOrg = DispTypeOnly) THEN
	    GetParentMainItem( WorkingList, ListPos ) ;
	    GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);
	 END ;
	 ReturnTypeHeader(TypeVA)
      ELSE
	 ReturnTokenLine(TokenVA)
      END;
      REPEAT
         receive(ThisGenInfo^.ToKWICDispGen,MarchingOrders);
         NextDir := MarchingOrders.Scroll;
         IF (NextDir = Initialize) OR (NextDir = Top) OR (NextDir = Terminate) THEN
            RETURN NextDir
         END;
      UNTIL GetNewPosInfo(NextDir);
   END;
   RETURN MarchingOrders.Scroll;
END HandleType;

BEGIN
   LOOP
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
         receive(ThisGenInfo^.ToKWICDispGen,MarchingOrders);
         IF MarchingOrders.Scroll = CloseDown THEN TACTProcesses.Terminate END;
         IF (MarchingOrders.Scroll <> Initialize) AND
         (MarchingOrders.Scroll <> Top) THEN
             ProgramErrorAndHalt('Bad MarchingOrders after Terminate')
         END;
      END;
   END;
END DoTheDisplay;

BEGIN
   ThisGenInfo := QueueOfGenInfos;
   IF ThisGenInfo = NIL THEN
      ProgramErrorAndHalt('No GenInfos Available')
   END;
   QueueOfGenInfos := QueueOfGenInfos^.Next;

   attachreceiver (ThisGenInfo^.ToKWICDispGen);
   attachsender (ThisGenInfo^.FromKWICDispGen);

   receive(ThisGenInfo^.ToKWICDispGen,MarchingOrders);
   IF (MarchingOrders.Scroll <> Initialize) AND
   (MarchingOrders.Scroll <> Top) THEN
       ProgramErrorAndHalt('Bad initial MarchingOrders')
   END;

   DoTheDisplay;
END KWICDisplayLineGenerator;

PROCEDURE LaunchKWICDisplayLineGenerator(VAR Info: GenInfoPntr);
BEGIN
   NEW(Info);
   Info^.Next := QueueOfGenInfos;
   QueueOfGenInfos := Info;
   WITH Info^ DO
      open (ToKWICDispGen);
      open (FromKWICDispGen);
      TACTProcesses.StartProcess (KWICDisplayLineGenerator, WSSize);
      attachsender(ToKWICDispGen);
      attachreceiver(FromKWICDispGen);
   END;
END LaunchKWICDisplayLineGenerator;

PROCEDURE GetLine(Type:   ScrollInstruction;
                  TB:     GenInfoPntr;
              VAR Ptr:    LineInfoPntr):BOOLEAN;
VAR
   MarchingOrders:     ScrollInstructionPacket;
BEGIN
   MarchingOrders.Scroll := Type;
   MarchingOrders.Return := ReturnLine;
   send(TB^.ToKWICDispGen,MarchingOrders);
   receive(TB^.FromKWICDispGen,Ptr);
   RETURN Ptr^.LineGot;
END GetLine;

PROCEDURE MoveLine(Type:   ScrollInstruction;
                   TB:     GenInfoPntr);
VAR
   MarchingOrders:     ScrollInstructionPacket;
BEGIN
   MarchingOrders.Scroll := Type;
   MarchingOrders.Return := NoReturnLine;
   send(TB^.ToKWICDispGen,MarchingOrders);
END MoveLine;

PROCEDURE CloseDownKWICDisplayLineGenerator(VAR Info: GenInfoPntr);
BEGIN
   MoveLine(CloseDown,Info);  (* this terminates remote processes *)
   TACTProcesses.YIELD;
   WITH Info^ DO
      close (ToKWICDispGen);
      close (FromKWICDispGen);
   END;
   DISPOSE(Info);
   Info := NIL;
END CloseDownKWICDisplayLineGenerator;
(*Empty>*)

PROCEDURE HandleKWICDisplay(KeyInstruction: ScrollKey);
(*<Empty*)
VAR
   rc, I:           CARDINAL;

PROCEDURE ScrollDisplayDown(): BOOLEAN;
VAR i:    CARDINAL;
BEGIN
   ScrollDown(DisplayData[KWIC].WindID,1);
   FOR i := BotY TO 0 BY -1 DO
     PosOnLine[i+1] := PosOnLine[i];
   END;
   InitialDisplayItem(PosOnLine[0]);
   IF BotY >= DisplayData[KWIC].WindInfo.YSize-1 THEN
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
   ScrollUp(DisplayData[KWIC].WindID,1);
   DiscardDisplayItem(WorkingList,PosOnLine[0]);
   FOR i := 1 TO BotY DO
     PosOnLine[i-1] := PosOnLine[i];
   END;
   InitialDisplayItem(PosOnLine[BotY]);
END ScrollDisplayUp;

PROCEDURE TermDisplay;
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
END TermDisplay;

PROCEDURE InitialDisplay;
VAR i:     CARDINAL;
    dummy: BOOLEAN;
BEGIN
   WITH DisplayData[KWIC] DO
      XLength := WindInfo.XSize - 1;
      CitCentre := (XLength DIV 2) + 8;
      LinesBefore := WindInfo.YSize DIV 4;
      LinesAfter := WindInfo.YSize - LinesBefore;
      ScrollSize := WindInfo.YSize DIV 2;
      TWB.SetManualUpdate(WindID);
      TWB.Clear;
      FOR CurrentY := 0 TO 26 DO 
          DiscardDisplayItem(WorkingList,PosOnLine[CurrentY])
      END;

      IF NOT GetLine(Initialize,TopDat,TopLPtr) THEN
         ProgramErrorAndHalt('Error Initializing')
      END;
      FancyScreenDisplay(WindID,0,0,TopLPtr^.Text,KWICDisplayTab,FALSE);
      PosOnLine[0] := TopLPtr^.From;
      DEALLOCATE(TopLPtr,TopLPtr^.Size);
      CurrentY := 0;
      BotY := 0;
      WHILE (CurrentY <= LinesBefore) AND GetLine(Up,TopDat,TopLPtr) DO
         dummy := ScrollDisplayDown();
         INC(CurrentY);
         PosOnLine[0] := TopLPtr^.From;
         FancyScreenDisplay(WindID,0,0,TopLPtr^.Text,KWICDisplayTab,FALSE);
         DEALLOCATE(TopLPtr,TopLPtr^.Size);
      END;
      ChangeColorOnScreen(BoldAttr,0,CurrentY,1);
      TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
      IF CurrentY <= LinesBefore THEN
         DEALLOCATE(TopLPtr,TopLPtr^.Size);
      END ;

      BotY := CurrentY+1;
      MoveLine(Initialize,BottomDat);
      WHILE (BotY < WindInfo.YSize) AND GetLine(Down,BottomDat,BottomLPtr) DO
         FancyScreenDisplay(WindID,0,BotY,BottomLPtr^.Text,KWICDisplayTab,
                  BotY = WindInfo.YSize-1 (* display update on last line only *));
         PosOnLine[BotY] := BottomLPtr^.From;
         DEALLOCATE(BottomLPtr,BottomLPtr^.Size);
         INC(BotY);
      END;
      IF BotY < WindInfo.YSize THEN
         DEALLOCATE(BottomLPtr,BottomLPtr^.Size);
      END ;
      DEC(BotY);

      TWB.SetAutoUpdate(WindID);
   END;
END InitialDisplay;

PROCEDURE ResetSelectedListPos ;
   BEGIN
	IF ((PosListStatus = PosMade) AND (DisplayData[KWIC].KWICDispOrg = DispPosition))
	   OR (DisplayData[KWIC].KWICDispOrg = DispType)
	   OR (DisplayData[KWIC].KWICDispOrg = DispTypeOnly) THEN
	   DiscardDisplayItem(SelectedList,SelectedListPos);
	   IF NOT FindDisplayItem(WorkingList,CurPos, SelectedList, SelectedListPos) THEN
		ProgramErrorAndHalt('Could not find corresponding item')
	   END
	END;
   END ResetSelectedListPos;

PROCEDURE ResetCurrPositions;
BEGIN
   DiscardDisplayItem(WorkingList,CurPos);
   CopyDisplayItem(WorkingList,PosOnLine[CurrentY],CurPos);
   ResetSelectedListPos ;
END ResetCurrPositions;

PROCEDURE DoCursorDown(): BOOLEAN;
BEGIN
   WITH DisplayData[KWIC] DO
      ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
      TWB.InitTextOnScreen(' ',0,CurrentY,1);
      INC(CurrentY);
      IF (CurrentY > LinesAfter) OR (CurrentY > BotY) THEN
        IF GetLine(Down,BottomDat,BottomLPtr) THEN
          ScrollDisplayUp;
          DEC(CurrentY);
          FancyScreenDisplay(WindID,0,BotY,BottomLPtr^.Text,KWICDisplayTab,FALSE);
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
      ChangeColorOnScreen(BoldAttr, 0,CurrentY,1);
      TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
      ResetCurrPositions;
   END;
   RETURN TRUE
END DoCursorDown;

PROCEDURE DoCursorUp(): BOOLEAN;
BEGIN
   WITH DisplayData[KWIC] DO
      IF CurrentY = 0 THEN RETURN FALSE END;
      ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
      TWB.InitTextOnScreen(' ',0,CurrentY,1);
      DEC(CurrentY);
      IF (CurrentY < LinesBefore) THEN
        IF GetLine(Up,TopDat,TopLPtr) THEN
          IF ScrollDisplayDown() THEN MoveLine(Up,BottomDat) END;
          INC(CurrentY);
          FancyScreenDisplay(WindID,0,0,TopLPtr^.Text,KWICDisplayTab,FALSE);
          PosOnLine[0] := TopLPtr^.From;
          DEALLOCATE(TopLPtr,TopLPtr^.Size);
        END;
      END;
      ChangeColorOnScreen(BoldAttr, 0,CurrentY,1);
      TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
      ResetCurrPositions;
   END;
   RETURN TRUE
END DoCursorUp;

PROCEDURE DisplayEmptyMessage;
VAR rc:    CARDINAL;
    temp:  StrAny;
BEGIN
   WITH DisplayData[KWIC] DO
      TWB.Clear;
      (*RES OLD MSG 172
      You have no currently selected Display Screen.
      *)
      GetResMessage( (*RES REM INS*) 172 , temp);
      WriteScreenField(WindID,0,0,0,temp,RegularAttr,TRUE);
   END;
END DisplayEmptyMessage;
   
PROCEDURE InitialLists;
BEGIN
   IF (DisplayData[KWIC].KWICDispOrg = DispType) OR
      (DisplayData[KWIC].KWICDispOrg = DispTypeOnly) THEN
      IF NOT ListByTypeMade THEN
         MakeWordList(SelectedList, ListByType);
         ListByTypeMade := TRUE
      END;
      WorkingList := ListByType;
      CurPos := TypeListPos;
   ELSIF (DisplayData[KWIC].KWICDispOrg = DispPosition) AND
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
   IF NOT FindDisplayItem(SelectedList, SelectedListPos,WorkingList, CurPos) THEN
	ProgramErrorAndHalt('Could not synchonize Selected & Working list') END;
END InitialLists;

(*Empty>*)

BEGIN
(*<Empty*)
   TWB.Use(DisplayData[KWIC].WindID);
   IF SelectedListEmpty THEN
      IF KeyInstruction = InitKey THEN DisplayEmptyMessage
      ELSIF KeyInstruction <> TermKey THEN Beep END ;
      RETURN
   END;
   IF InitLineProcs THEN
      InitLineProcs := FALSE;
      LaunchKWICDisplayLineGenerator(TopDat);
      LaunchKWICDisplayLineGenerator(BottomDat);
   END;
   (*<Debug
   GetPosData(CurPos,DummyThisType,DummyTokenVA,DummyTypeVA,DummyCatVA);
   Debug>*)
   CASE KeyInstruction OF
     InitKey:
        InitialLists;
        InitialDisplay;
   | TermKey:
	TermDisplay;
	RETURN ;
   | CloseDownKey:
       TermDisplay;
       InitLineProcs := TRUE;
       CloseDownKWICDisplayLineGenerator(TopDat);
       CloseDownKWICDisplayLineGenerator(BottomDat);
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
   | PgUpKey:
       TWB.SetManualUpdate(DisplayData[KWIC].WindID) ;
       ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
       TWB.InitTextOnScreen(' ',0,CurrentY,1);
       CurrentY := 2 ;
       FOR I := 1 TO DisplayData[KWIC].WindInfo.YSize - 1 DO
          IF NOT DoCursorUp() THEN Beep ;
             ChangeColorOnScreen(BoldAttr, 0,CurrentY,1);
             TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
             TWB.SetAutoUpdate(DisplayData[KWIC].WindID) ;
             RETURN END;
       END ;
       TWB.SetAutoUpdate(DisplayData[KWIC].WindID) ;
   | PgDnKey:
       TWB.SetManualUpdate(DisplayData[KWIC].WindID) ;
       ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
       TWB.InitTextOnScreen(' ',0,CurrentY,1);
       CurrentY := BotY ;
       FOR I := 1 TO DisplayData[KWIC].WindInfo.YSize - 1 DO
          IF NOT DoCursorDown() THEN  Beep ;
            ChangeColorOnScreen(BoldAttr, 0,CurrentY,1);
            TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
            TWB.SetAutoUpdate(DisplayData[KWIC].WindID) ;
            RETURN END;
       END ;
       TWB.SetAutoUpdate(DisplayData[KWIC].WindID) ;
   | AltPgUpKey:
(*     IF NOT PrevMainItem(WorkingList, CurPos) THEN  Beep ; RETURN  END; *)
       IF NOT PrevMainItem(WorkingList, CurPos) THEN  Beep  END;
       InitialDisplay;
       ResetSelectedListPos;
   | AltPgDnKey:
(*     IF NOT NextMainItem(WorkingList, CurPos) THEN  Beep ; RETURN  END; *)
       IF NOT NextMainItem(WorkingList, CurPos) THEN  Beep  END;
       InitialDisplay;
       ResetSelectedListPos;
   | EndKey:
       DiscardDisplayItem(WorkingList, CurPos);
       IF NOT LastDisplayItem(WorkingList, CurPos) THEN
          ProgramErrorAndHalt('Problem finding last item in list')
       END;
       InitialDisplay;
       ResetSelectedListPos;
   ELSE
      Beep ; RETURN ;
   END;

   IF (DisplayData[KWIC].KWICDispOrg = DispType) OR
      (DisplayData[KWIC].KWICDispOrg = DispTypeOnly) THEN
   	 TypeListPos := CurPos
   ELSIF (DisplayData[KWIC].KWICDispOrg = DispPosition) AND (PosListStatus <> PosOnly) THEN
   	 PositionListPos := CurPos
   ELSE
	 SelectedListPos := CurPos
   END;
(*Empty>*)
END HandleKWICDisplay;

PROCEDURE OutputKWICDisplay(VAR file: XFileType; CheckAbort: AbortProc);
(*<Empty*)
VAR
   LineInfo:   LineInfoPntr;
   status:     BOOLEAN;
   NoLines:    CARDINAL;
   result:     CARDINAL;
(*Empty>*)
BEGIN
(*<Empty*)
   IF SelectedListEmpty THEN
      (*RES OLD MSG 249
      There is no KWIC Display for Printing or Ouput to Disk.
      *)
      PutResError( (*RES REM INS*) 249 );
      RETURN
   END;

   LaunchKWICDisplayLineGenerator(PrintDat);
   status := GetLine(Top,PrintDat,LineInfo);
   NoLines := 1 ;
   REPEAT
      status := WriteWithTabs(file, LineInfo^.Text,KWICDisplayTab);
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
   CloseDownKWICDisplayLineGenerator(PrintDat);
(*Empty>*)
END OutputKWICDisplay;

PROCEDURE InitializeKWICDisplay;
BEGIN
(*<Empty*)
   InitLineProcs := TRUE;
   QueueOfGenInfos := NIL;
   WITH KWICDisplayTab[0] DO
      Pos := 30;
      Type := Left;
      FilPat := '';
   END;
   FOR CurrentY := 0 TO 26 DO InitialDisplayItem(PosOnLine[CurrentY]) END;
   (*<Debug  InitialDisplayItem( CurPos ) ;  Debug>*)

(*Empty>*)
END InitializeKWICDisplay;

END KWICDisplay.
