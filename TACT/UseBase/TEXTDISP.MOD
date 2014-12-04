IMPLEMENTATION MODULE TextDisplay;

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

IMPORT TWB, Str, ASCII ;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM Utils IMPORT Beep ;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList;
FROM MainLists IMPORT
  (* type *) PosListStatusType,
  (* vars *) SelectedList, ListByPosition,
             PosListStatus, SelectedListPos, PositionListPos,
             SelectedListEmpty;
FROM KeyTranslation IMPORT
  (* Const *) IntTab, IntEnhOn, IntEnhOff,
  (* Type  *) TabInfo, TabType,
  (* Procs *) FancyScreenDisplay, GetScreenField;
FROM HyperDataModel IMPORT HTokenData, HyperLength;
FROM ListData IMPORT
  (* types *) ItemType,DataItemPntr;
FROM LineBase IMPORT
  (* type *) LineDataType,
  (* procs*) GetLine, GetNextLine, GetPrevLine;
IMPORT TACTProcesses;
FROM channels IMPORT
  (* type *) channel,
  (* proc *) open, close, attachsender, attachreceiver, send, receive,
             datawaiting;
FROM GlobalDefs IMPORT StrAny;
FROM Windows IMPORT
  (* Const *) RegularAttr, BoldAttr,
  (* Procs *) ScrollUp, ScrollDown, ChangeColorOnScreen;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM StackWindows IMPORT WindowInfo;
FROM DisplayDialog IMPORT
  (* type *) DisplayType, DisplayDataType,
  (* vars *) DisplayData, CurrentDisplay;
FROM ScrollMessages IMPORT
   (* type *) ScrollInstruction, ReturnInstruction,
              ScrollInstructionPacket, ScrollKey;
   (* Note that a **local** definition of LineInformation structures is
      used here -- rather than that exported from ScrollMessages  j.b.  *)
FROM HyperBase IMPORT HRecPntr;
FROM DBData IMPORT
    (* vars  *) BeginText;
FROM ListUtils IMPORT MakePosList, MakeWordList;
FROM PositionManagement IMPORT
  (* types *) PositionItem,
  (* procs *) GetPosData, FirstDisplayItem,
              LastDisplayItem, CopyDisplayItem, NextDisplayItem,
              PrevDisplayItem, FindDisplayItem, DiscardDisplayItem,
              InitialDisplayItem;
FROM RefValBase IMPORT
  (* Procs *) CreateRef ;
FROM Translations IMPORT XFileType, XWrNXlate;
FROM PrintModule IMPORT AbortProc, WriteWithTabs, PrintDest, LinesPerPage,
		PrintActionType ;
FROM TACTDataServices IMPORT GetTDBTokenData;
FROM VirtMem IMPORT VirtAddr, VMAccess, VMMarkChanged, VMRelease;

(*<Empty*)

CONST
    WSSize = 4000;
    MarkerSymbol = 020C;
    BaseLineInfoSize = 13;

TYPE
   GenInfoPntr = POINTER TO GenInfo;
   GenInfo = RECORD
      Next:              GenInfoPntr;
      ToTextDispGen:     channel;
      FromTextDispGen:   channel;
   END;

(* Note: following is a different, local definition LineInfoPntr and
   LineInformation   j.b.  *)

   LineInfoPntr = POINTER TO LineInformation;
   LineInformation = RECORD
       Size:       CARDINAL;
       ListItem:   PositionItem;
(*     LineId:     DataItemPntr; *)
       LineGot:    BOOLEAN;
       LineInList: BOOLEAN;
       CASE : BOOLEAN OF
         TRUE:
            Text:       StrAny
       | FALSE:
            Text1:      ARRAY[0..1] OF CHAR;
            Text2:      StrAny
       END;
   END;

VAR
   QueueOfGenInfos:      GenInfoPntr;
   RefDisplayTab,
   TextDisplayTab:       ARRAY[0..0] OF TabInfo;
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
   PosOnLine:    ARRAY[0..26] OF RECORD
                   ListItem:   PositionItem;
(*                 LineId:     DataItemPntr; *)
                   LineInList: BOOLEAN;
                 END;
   WorkingList:  TACTList;
   CurPos:       PositionItem;
   RefText	: StrAny ;
   DefaultRef	: ARRAY[0..4] OF CHAR ;

PROCEDURE TextDisplayLineGenerator;

TYPE
   HighLightIndicator = (None, MainChoice, InList);
   MoveItemProc = PROCEDURE(TACTList,VAR PositionItem): BOOLEAN;

  VAR
    HighLightArray: ARRAY[0..255] OF HighLightIndicator;
    NextPos	:   PositionItem;
    StartingPoint:  HRecPntr;
    MarchingOrders: ScrollInstructionPacket;
    TLine	: StrAny;
    TLineLen	: CARDINAL;
    TOffset	: CARDINAL;
    i		: CARDINAL;
    DataPtr	: LineDataType;
    LinePntr	: LineInfoPntr;
    LineResult	: BOOLEAN;
    ThisGenInfo	: GenInfoPntr;
    len		: CARDINAL;
    LineInList	: BOOLEAN;

PROCEDURE ItemInLine(LineData:   LineDataType;
                     PosData:    PositionItem;
                 VAR Offset:     CARDINAL):  INTEGER;
VAR
   PTy:       ItemType;
   VAToken:   VirtAddr;
   VAType:    VirtAddr;
   VACat:     VirtAddr;
   PToken:    DataItemPntr;
BEGIN
   GetPosData(PosData, PTy, VAToken, VAType, VACat);
   Offset := 0;
   PToken := VMAccess(VAToken);
   IF NOT PToken^.TokenDataLoaded THEN
      VMMarkChanged(VAToken);
      GetTDBTokenData(PToken)
   END;
   WITH PToken^.TokenFileData DO
      IF TRecNo < LineData.Start.Rec THEN VMRelease(VAToken); RETURN -1
      ELSIF (TRecNo = LineData.Start.Rec) AND
      (TRecPos < LineData.Start.Idx) THEN VMRelease(VAToken); RETURN -1
      END;

      IF TRecNo > LineData.End.Rec THEN VMRelease(VAToken); RETURN 1
      ELSIF (TRecNo = LineData.End.Rec) AND
      (TRecPos > LineData.End.Idx) THEN VMRelease(VAToken); RETURN 1
      END;
      IF TRecNo = LineData.Start.Rec THEN
          Offset := TRecPos - LineData.Start.Idx
      ELSE
          Offset := HyperLength - LineData.Start.Idx + TRecPos
      END;
   END;
   VMRelease(VAToken);
   RETURN 0;
END ItemInLine;

PROCEDURE MoveOutOfLine(LinePtr:        LineDataType;
                        MoveProc:       MoveItemProc;
                    VAR NewPos:         PositionItem;
                    VAR LastItem:       PositionItem;
                    VAR HighLightArray: ARRAY OF HighLightIndicator);
VAR
   Done:      BOOLEAN;
   Offset:    CARDINAL;
BEGIN
   InitialDisplayItem(LastItem);
   CopyDisplayItem(WorkingList, NewPos, LastItem);
   Done := FALSE;
   REPEAT
      IF NOT MoveProc(WorkingList,NewPos) THEN RETURN END;
      IF 0 = ItemInLine(LinePtr,NewPos,Offset) THEN
         HighLightArray[Offset] := InList;
         DiscardDisplayItem(WorkingList,LastItem);
         CopyDisplayItem(WorkingList,NewPos,LastItem)
      ELSE
         Done := TRUE
      END;
   UNTIL Done;
END MoveOutOfLine;

PROCEDURE CreateDisplayLine(TLine:           ARRAY OF CHAR;
                            HighLightArray:  ARRAY OF HighLightIndicator;
                            CurPos:          PositionItem;
                            LineIn:          BOOLEAN);
TYPE
   HighLightState = (NoLight, InBold, InSpecial);
VAR
   RLine:        StrAny;
   i,j:          CARDINAL;
   State:        HighLightState;
BEGIN
    i := 0;
    j := 0;
    State := NoLight;
    WHILE TLine[i] <> 0C DO
      CASE State OF
        NoLight:
           CASE HighLightArray[i] OF
             None:
           | MainChoice:
                RLine[j] := IntEnhOn;
                INC(j);
                State := InSpecial;
           | InList:
                RLine[j] := IntEnhOn;
                INC(j);
                State := InBold;
           END;
      | InBold:
           IF TLine[i] = ' ' THEN
                RLine[j] := IntEnhOff;
                INC(j);
                State := NoLight
           ELSIF HighLightArray[i] = MainChoice THEN
                (* when alt highlight available, put code in here j.b. *)
                State := InSpecial
           END;
      | InSpecial:
           IF TLine[i] = ' ' THEN
                RLine[j] := IntEnhOff;
                INC(j);
                State := NoLight
           ELSIF HighLightArray[i] = InList THEN
                (* when alt highlight available, put code in here j.b. *)
                State := InSpecial
           END;
      END;
      RLine[j] := TLine[i];
      INC(j);
      INC(i);
    END;
    RLine[j] := 0C;

    len := j + BaseLineInfoSize + 2;
    ALLOCATE(LinePntr,len);
    WITH LinePntr^ DO
       Size := len;
(*     LineId := NIL; (* until we figure out what it should be! j.b. *) *)
       LineGot := TRUE;
       LineInList := LineIn;
       IF LineInList THEN CopyDisplayItem(WorkingList, CurPos, ListItem)
       ELSE InitialDisplayItem(ListItem) END;
       LinePntr^.Text1 := '  ';
       Str.Copy(LinePntr^.Text2,RLine)
    END;
    send(ThisGenInfo^.FromTextDispGen,LinePntr);
END CreateDisplayLine;

PROCEDURE DoInitialize;
VAR
   PTy:                ItemType;
   PToken:             DataItemPntr;
   VAToken:            VirtAddr;
   VAType:             VirtAddr;
   VACat:              VirtAddr;
   PrevExists:         BOOLEAN;
   PrevPos:            PositionItem;
   dummy:              PositionItem;
BEGIN
   IF SelectedListEmpty THEN
      LineInList := FALSE;
      StartingPoint.Rec := BeginText;
      StartingPoint.Idx := 0
   ELSE
      LineInList := TRUE;
      GetPosData(CurPos, PTy, VAToken, VAType, VACat);
      PToken := VMAccess(VAToken);
      IF NOT PToken^.TokenDataLoaded THEN
         VMMarkChanged(VAToken);
         GetTDBTokenData(PToken)
      END;
      WITH PToken^.TokenFileData DO
         StartingPoint.Rec := TRecNo;
         StartingPoint.Idx := TRecPos;
      END;
      VMRelease(VAToken);
   END;
   GetLine(StartingPoint,TLine,TLineLen,TOffset,DataPtr);
   FOR i := 0 TO TLineLen DO HighLightArray[i] := None END;

   IF NOT SelectedListEmpty THEN
      HighLightArray[TOffset] := MainChoice;
      InitialDisplayItem(PrevPos);
      DiscardDisplayItem(WorkingList, NextPos);
      CopyDisplayItem(WorkingList, CurPos, PrevPos);
      CopyDisplayItem(WorkingList, CurPos, NextPos);
      MoveOutOfLine(DataPtr, PrevDisplayItem, PrevPos, dummy, HighLightArray);
      DiscardDisplayItem(WorkingList, dummy);
      MoveOutOfLine(DataPtr, NextDisplayItem, NextPos, dummy, HighLightArray);
      DiscardDisplayItem(WorkingList, dummy);
      DiscardDisplayItem(WorkingList, PrevPos)
   END;
   IF MarchingOrders.Return = ReturnLine THEN
      CreateDisplayLine(TLine, HighLightArray,CurPos,LineInList)
   END;
END DoInitialize;

PROCEDURE SendNoLine;
BEGIN
    IF MarchingOrders.Return = ReturnLine THEN
        ALLOCATE(LinePntr,BaseLineInfoSize);
        WITH LinePntr^ DO
           Size := BaseLineInfoSize;
(*         LineId := NIL; (* until we figure out what it should be! j.b. *) *)
           LineGot := FALSE;
           LineInList := FALSE;
           InitialDisplayItem(ListItem);
           Text[0] := 0C;
        END;
        send(ThisGenInfo^.FromTextDispGen,LinePntr);
    END
END SendNoLine;

PROCEDURE DoUp;
VAR
   i:       CARDINAL;
   rslt:    INTEGER;
   Offset:  CARDINAL;
   Done:    BOOLEAN;
   InLine:  BOOLEAN;
   LastItem:PositionItem;
BEGIN
   InitialDisplayItem(LastItem);
   IF NOT GetPrevLine(DataPtr,TLine,TLineLen) THEN
      SendNoLine
   ELSE
      FOR i := 0 TO TLineLen DO HighLightArray[i] := None END;
      Done := FALSE;
      IF SelectedListEmpty THEN
         InLine := FALSE
      ELSE
         REPEAT
            rslt := ItemInLine(DataPtr, NextPos, Offset);
            IF rslt <= 0 THEN Done := TRUE
            ELSE Done := NOT PrevDisplayItem(WorkingList, NextPos) END;
         UNTIL Done;
         IF rslt = 0 THEN
            HighLightArray[Offset] := InList;
            MoveOutOfLine(DataPtr, PrevDisplayItem, NextPos, LastItem, HighLightArray);
            InLine := TRUE;
            i := 0;
            WHILE HighLightArray[i] = None DO INC(i) END;
            HighLightArray[i] := MainChoice;
         ELSE
            InLine := FALSE;
         END
      END;
      IF MarchingOrders.Return = ReturnLine THEN
         CreateDisplayLine(TLine, HighLightArray, LastItem, InLine)
      END;
      DiscardDisplayItem(WorkingList, LastItem);
   END;
END DoUp;

PROCEDURE DoDown;
VAR
   i:       CARDINAL;
   rslt:    INTEGER;
   Offset:  CARDINAL;
   Done:    BOOLEAN;
   InLine:  BOOLEAN;
   dummy:   PositionItem;
   TItem:   PositionItem;
BEGIN
   InitialDisplayItem(TItem);
   IF NOT GetNextLine(DataPtr,TLine,TLineLen) THEN
      SendNoLine
   ELSE
      FOR i := 0 TO TLineLen DO HighLightArray[i] := None END;
      Done := FALSE;
      IF SelectedListEmpty THEN
         InLine := FALSE
      ELSE
         REPEAT
            rslt := ItemInLine(DataPtr, NextPos, Offset);
            IF rslt >= 0 THEN Done := TRUE
            ELSE Done := NOT NextDisplayItem(WorkingList, NextPos) END;
         UNTIL Done;
         IF rslt = 0 THEN
            HighLightArray[Offset] := MainChoice;
            CopyDisplayItem(WorkingList, NextPos, TItem);
            MoveOutOfLine(DataPtr, NextDisplayItem, NextPos, dummy, HighLightArray);
            DiscardDisplayItem(WorkingList, dummy);
            InLine := TRUE;
         ELSE
            InLine := FALSE;
         END
      END;
      IF MarchingOrders.Return = ReturnLine THEN
         CreateDisplayLine(TLine, HighLightArray, TItem, InLine)
      END;
      DiscardDisplayItem(WorkingList, TItem);
   END;
END DoDown;

PROCEDURE DoTerminate;
BEGIN
   DiscardDisplayItem(WorkingList,NextPos);
   SendNoLine  (* to sychonize the various processes  j.b. *)
END DoTerminate;

BEGIN
   ThisGenInfo := QueueOfGenInfos;
   IF ThisGenInfo = NIL THEN
      ProgramErrorAndHalt('No GenInfos Available')
   END;
   QueueOfGenInfos := QueueOfGenInfos^.Next;

   attachreceiver (ThisGenInfo^.ToTextDispGen);
   attachsender (ThisGenInfo^.FromTextDispGen);
   InitialDisplayItem(NextPos);
   LOOP
       receive(ThisGenInfo^.ToTextDispGen,MarchingOrders);
       CASE MarchingOrders.Scroll OF
         Up:           DoUp;
       | Down:         DoDown;
       | Initialize:   DoInitialize;
       | Terminate:    DoTerminate;
       | CloseDown:    TACTProcesses.Terminate;
       END;
   END;
END TextDisplayLineGenerator;

PROCEDURE LaunchTextDisplayLineGenerator(VAR Info: GenInfoPntr);
BEGIN
   NEW(Info);
   Info^.Next := QueueOfGenInfos;
   QueueOfGenInfos := Info;
   WITH Info^ DO
      open (ToTextDispGen);
      open (FromTextDispGen);
      TACTProcesses.StartProcess (TextDisplayLineGenerator, WSSize);
      attachsender(ToTextDispGen);
      attachreceiver(FromTextDispGen);
   END;
END LaunchTextDisplayLineGenerator;

PROCEDURE InitialPosOnLineItems;
BEGIN
   FOR CurrentY := 0 TO 26 DO
      InitialDisplayItem(PosOnLine[CurrentY].ListItem);
(*    PosOnLine[CurrentY].LineId := NIL; *)
      PosOnLine[CurrentY].LineInList := FALSE;
   END;
END InitialPosOnLineItems;

PROCEDURE GetDLine(Type:   ScrollInstruction;
                   TB:     GenInfoPntr;
               VAR Ptr:    LineInfoPntr):BOOLEAN;
VAR
   MarchingOrders:     ScrollInstructionPacket;
BEGIN
   MarchingOrders.Scroll := Type;
   MarchingOrders.Return := ReturnLine;
   send(TB^.ToTextDispGen,MarchingOrders);
   receive(TB^.FromTextDispGen,Ptr);
   RETURN Ptr^.LineGot;
END GetDLine;

PROCEDURE MoveLine(Type:   ScrollInstruction;
                   TB:     GenInfoPntr);
VAR
   MarchingOrders:     ScrollInstructionPacket;
BEGIN
   MarchingOrders.Scroll := Type;
   MarchingOrders.Return := NoReturnLine;
   send(TB^.ToTextDispGen,MarchingOrders);
END MoveLine;

PROCEDURE CloseDownTextDisplayLineGenerator(VAR Info: GenInfoPntr);
BEGIN
   MoveLine(CloseDown,Info);  (* this terminates remote processes *)
   TACTProcesses.YIELD;
   WITH Info^ DO
      close (ToTextDispGen);
      close (FromTextDispGen);
   END;
   DISPOSE(Info);
   Info := NIL;
END CloseDownTextDisplayLineGenerator;

(*Empty>*)

PROCEDURE HandleTextDisplay(KeyInstruction: ScrollKey);
(*<Empty*)
VAR
    rc		: CARDINAL;
    dummy	: BOOLEAN;
    ThisType	: ItemType;
    TokenVA	: VirtAddr;
    TypeVA	: VirtAddr;
    CatVA	: VirtAddr;
    I           : CARDINAL ; (* m.s. *)
    OK          : BOOLEAN ;

PROCEDURE ScrollDisplayDown(): BOOLEAN;
VAR i:    CARDINAL;
BEGIN
   ScrollDown(DisplayData[Text].WindID,1);
   FOR i := BotY TO 0 BY -1 DO
     PosOnLine[i+1] := PosOnLine[i];
   END;
   WITH PosOnLine[0] DO
      InitialDisplayItem(ListItem);
(*    LineId := NIL; *)
      LineInList := FALSE;
   END;
   IF BotY >= DisplayData[Text].WindInfo.YSize-2 THEN
      WITH PosOnLine[BotY+1] DO
         DiscardDisplayItem(SelectedList,ListItem);
         LineInList := FALSE;
         RETURN TRUE;
      END;
   ELSE
      INC(BotY);
      RETURN FALSE;
   END;
END ScrollDisplayDown;

(* m.s. - to handle PgDn *)
PROCEDURE ScrollDisplayPgDn(): BOOLEAN;
VAR i:    CARDINAL;
BEGIN
   ScrollDown(DisplayData[Text].WindID,1);
   FOR i := BotY TO 0 BY -1 DO
     PosOnLine[i+1] := PosOnLine[i];
   END;
   WITH PosOnLine[0] DO
      InitialDisplayItem(ListItem);
(*    LineId := NIL; *)
      LineInList := FALSE;
   END;
   IF BotY >= DisplayData[Text].WindInfo.YSize-2 THEN
      WITH PosOnLine[BotY+1] DO
         DiscardDisplayItem(SelectedList,ListItem);
         LineInList := FALSE;
         RETURN TRUE;
      END;
   ELSE
      INC(BotY);
      RETURN FALSE;
   END;
END ScrollDisplayPgDn;

PROCEDURE ScrollDisplayUp;
VAR i:    CARDINAL;
BEGIN
   ScrollUp(DisplayData[Text].WindID,1);
   WITH PosOnLine[0] DO
      DiscardDisplayItem(SelectedList,ListItem);
      LineInList := FALSE;
   END;
   FOR i := 1 TO BotY DO
     PosOnLine[i-1] := PosOnLine[i];
   END;
   WITH PosOnLine[BotY] DO
      InitialDisplayItem(ListItem);
(*    LineId := NIL; *)
      LineInList := FALSE;
   END;
END ScrollDisplayUp;

PROCEDURE InitialDisplay;
VAR
    dummy	: BOOLEAN;
    RefLen	: CARDINAL ;
    i		: CARDINAL;
BEGIN
   WITH DisplayData[Text] DO
      LinesBefore := WindInfo.YSize DIV 4;
      LinesAfter := WindInfo.YSize - LinesBefore;
      TWB.SetManualUpdate(WindID);
      TWB.Clear;
      FOR CurrentY := 0 TO 26 DO
          DiscardDisplayItem(SelectedList,PosOnLine[CurrentY].ListItem) ;
	  PosOnLine[CurrentY].LineInList := FALSE;
      END;
(*	InitialPosOnLineItems; *)

      IF NOT GetDLine(Initialize,TopDat,TopLPtr) THEN
         ProgramErrorAndHalt('Error Initializing')
      END;
      FancyScreenDisplay(WindID,0,0,TopLPtr^.Text,TextDisplayTab,FALSE);
      WITH TopLPtr^ DO
        PosOnLine[0].ListItem := ListItem;
(*      PosOnLine[0].LineId := LineId; *)
        PosOnLine[0].LineInList := LineInList;
      END;
      DEALLOCATE(TopLPtr,TopLPtr^.Size);

      CurrentY := 0;
      BotY := 0;
      WHILE (CurrentY <= LinesBefore) AND GetDLine(Up,TopDat,TopLPtr) DO
         dummy := ScrollDisplayDown();
         INC(CurrentY);
         WITH TopLPtr^ DO
            PosOnLine[0].ListItem := ListItem;
(*          PosOnLine[0].LineId := LineId; *)
            PosOnLine[0].LineInList := LineInList;
         END;
         FancyScreenDisplay(WindID,0,0,TopLPtr^.Text,TextDisplayTab,FALSE);
         DEALLOCATE(TopLPtr,TopLPtr^.Size);
      END;
      ChangeColorOnScreen(BoldAttr,0,CurrentY,1);
      TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
      IF CurrentY <= LinesBefore THEN
         DEALLOCATE(TopLPtr,TopLPtr^.Size);
      END ;

      BotY := CurrentY+1;
      MoveLine(Initialize,BottomDat);
      WHILE (BotY < WindInfo.YSize-1) AND GetDLine(Down,BottomDat,BottomLPtr) DO
         FancyScreenDisplay(WindID,0,BotY,BottomLPtr^.Text,TextDisplayTab,FALSE) ;
         WITH BottomLPtr^ DO
            PosOnLine[BotY].ListItem := ListItem;
(*          PosOnLine[BotY].LineId := LineId; *)
            PosOnLine[BotY].LineInList := LineInList;
         END;
         DEALLOCATE(BottomLPtr,BottomLPtr^.Size);
         INC(BotY);
      END;
      IF BotY < WindInfo.YSize-1 THEN
         DEALLOCATE(BottomLPtr,BottomLPtr^.Size);
      END ;
      DEC(BotY);

      IF PosOnLine[CurrentY].LineInList THEN
	 GetPosData( PosOnLine[CurrentY].ListItem, ThisType, TokenVA, TypeVA, CatVA ) ;
	 CreateRef( EncodedRefInfo, EncodedRefLen, TokenVA, RefText, RefLen,
	            DisplayWordCountWord ) ;
	 Str.Concat( RefText, IntTab, RefText ) ;
	 Str.Concat( RefText, IntEnhOn, RefText ) ;
      ELSE
	 RefLen := 3 ;
	 Str.Copy( RefText, DefaultRef ) ;
      END ;
      WITH RefDisplayTab[0] DO
	   IF (* DisplayData[Text].*) WindInfo.XSize >= RefLen-2 THEN
		Pos  := WindInfo.XSize - 2 ;
		Type := Right ;
	   ELSE  (* very small window!!! *)
(*		Pos  := WindInfo.XSize - 2 ; (* was 0 *) *)
		Pos  := 2 ; (* was 0 *)
		Type := Left ;
	   END ;
      END ;
      FancyScreenDisplay(WindID,0,WindInfo.YSize-1,RefText,RefDisplayTab, TRUE );

      TWB.GotoXY(0,0);
      TWB.SetAutoUpdate(WindID);
   END;
END InitialDisplay;

PROCEDURE TerminateDisplay;
VAR
   dummy:   BOOLEAN;
   temp:    LineInfoPntr;
BEGIN
   (* in this proc GetDLine was used rather than MoveLine to ensure
      that the processing on Top and BottomDat are completely finished
      before execution proceeds    j.b.    *)

      dummy := GetDLine(Terminate,TopDat,temp);
      DEALLOCATE(temp,temp^.Size);
      dummy := GetDLine(Terminate,BottomDat,temp);
      DEALLOCATE(temp,temp^.Size);
      FOR CurrentY := 0 TO 26 DO
          DiscardDisplayItem(SelectedList,PosOnLine[CurrentY].ListItem)
      END;
END TerminateDisplay;

PROCEDURE ResetCurrent;
VAR RefLen : CARDINAL ;
BEGIN
   DiscardDisplayItem(WorkingList,CurPos);
   CopyDisplayItem(WorkingList,PosOnLine[CurrentY].ListItem,CurPos);
   IF PosListStatus <> PosOnly THEN
      DiscardDisplayItem( SelectedList, SelectedListPos ) ;
      IF NOT FindDisplayItem(WorkingList, CurPos,
                             SelectedList,SelectedListPos) THEN
         ProgramErrorAndHalt('Could not find corresponding item')
      END ;
      GetPosData( PosOnLine[CurrentY].ListItem, ThisType, TokenVA, TypeVA, CatVA ) ;
      WITH DisplayData[Text] DO
         CreateRef( EncodedRefInfo, EncodedRefLen, TokenVA, RefText, RefLen,
                    DisplayWordCountWord ) ;
	 Str.Concat( RefText, IntTab, RefText ) ;
	 Str.Concat( RefText, IntEnhOn, RefText ) ;
	 FancyScreenDisplay(WindID,0,WindInfo.YSize-1,RefText,RefDisplayTab, FALSE );
      END ;
   END;
END ResetCurrent;

PROCEDURE DoCursorDown(): BOOLEAN;
BEGIN
   WITH DisplayData[Text] DO
      ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
      TWB.InitTextOnScreen(' ',0,CurrentY,1);
      INC(CurrentY);
      IF (CurrentY > LinesAfter) OR (CurrentY > BotY) THEN
        IF GetDLine(Down,BottomDat,BottomLPtr) THEN
          TWB.GotoXY(0,DisplayData[Text].WindInfo.YSize-1);
          TWB.ClrEol; (* clear the Ref line *)
          ScrollDisplayUp;
          DEC(CurrentY);
          FancyScreenDisplay(WindID,0,BotY,BottomLPtr^.Text,TextDisplayTab,FALSE);
          WITH BottomLPtr^ DO
             PosOnLine[BotY].ListItem := ListItem;
(*           PosOnLine[BotY].LineId := LineId; *)
             PosOnLine[BotY].LineInList := LineInList;
          END;
          DEALLOCATE(BottomLPtr,BottomLPtr^.Size);
          MoveLine(Down,TopDat) ;
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
      IF PosOnLine[CurrentY].LineInList THEN
	 ResetCurrent ;
      ELSE
	 FancyScreenDisplay(WindID,0,WindInfo.YSize-1,DefaultRef,RefDisplayTab, FALSE );
      END ;
   END;
   RETURN TRUE
END DoCursorDown;

PROCEDURE DoCursorUp(): BOOLEAN;
BEGIN
   WITH DisplayData[Text] DO
      IF CurrentY = 0 THEN RETURN FALSE END;
      ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
      TWB.InitTextOnScreen(' ',0,CurrentY,1);
      DEC(CurrentY);
      IF (CurrentY < LinesBefore) THEN
        IF GetDLine(Up,TopDat,TopLPtr) THEN
          TWB.GotoXY(0,DisplayData[Text].WindInfo.YSize-2);
          TWB.ClrEol; (* clear the Ref line *)

          IF ScrollDisplayDown() THEN MoveLine(Up,BottomDat) END;
          INC(CurrentY);
          FancyScreenDisplay(WindID,0,0,TopLPtr^.Text,TextDisplayTab,FALSE);
          WITH TopLPtr^ DO
            PosOnLine[0].ListItem := ListItem;
(*          PosOnLine[0].LineId := LineId; *)
            PosOnLine[0].LineInList := LineInList;
          END;
          DEALLOCATE(TopLPtr,TopLPtr^.Size);
        END;
      END;
      ChangeColorOnScreen(BoldAttr, 0,CurrentY,1);
      TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
      IF PosOnLine[CurrentY].LineInList THEN
	 ResetCurrent ;
      ELSE
	 FancyScreenDisplay(WindID,0,WindInfo.YSize-1,DefaultRef,RefDisplayTab, FALSE );
      END;
   END;
   RETURN TRUE
END DoCursorUp;
(*Empty>*)

BEGIN
(*<Empty*)
   TWB.Use(DisplayData[Text].WindID);
   IF InitLineProcs THEN
      InitLineProcs := FALSE;
      LaunchTextDisplayLineGenerator(TopDat);
      LaunchTextDisplayLineGenerator(BottomDat);
   END;
   CASE KeyInstruction OF
     InitKey:
       IF NOT SelectedListEmpty THEN
          IF PosListStatus = NoPos THEN
             PosListStatus := PosMade;
             MakePosList(SelectedList, ListByPosition);
          END;
          IF PosListStatus = PosOnly THEN
             WorkingList := SelectedList;
             CurPos := SelectedListPos;
          ELSE
             WorkingList := ListByPosition;
	     DiscardDisplayItem( ListByPosition, PositionListPos ) ; (* line was prev commented out *LP* *)
             IF NOT FindDisplayItem(SelectedList, SelectedListPos,
                                    ListByPosition, PositionListPos) THEN
                  ProgramErrorAndHalt('Could not synchonize Selected a Pos list')
             END;
             CurPos := PositionListPos;
          END
       END;
       InitialDisplay;
   | TermKey:
       TerminateDisplay;
       RETURN ;
   | CloseDownKey:
       TerminateDisplay;
       InitLineProcs := TRUE;
       CloseDownTextDisplayLineGenerator(TopDat);
       CloseDownTextDisplayLineGenerator(BottomDat);
       RETURN;
   | UpKey:
       IF NOT DoCursorUp() THEN  Beep ; RETURN  END;
   | DownKey:
       IF NOT DoCursorDown() THEN  Beep ; RETURN  END;
   | PgUpKey:
       TWB.SetManualUpdate(DisplayData[Text].WindID);
       ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
       TWB.InitTextOnScreen(' ',0,CurrentY,1);
       CurrentY := 2 ;
       LinesBefore := 2 ;
       FOR I := 1 TO DisplayData[Text].WindInfo.YSize - 2 DO
          IF NOT DoCursorUp() THEN Beep ;
              ChangeColorOnScreen(BoldAttr, 0,CurrentY,1);
              TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
              TWB.SetAutoUpdate(DisplayData[Text].WindID) ;
              RETURN END;
       END ;
       TWB.SetAutoUpdate(DisplayData[Text].WindID) ;
   | PgDnKey:
       TWB.SetManualUpdate(DisplayData[Text].WindID);
       ChangeColorOnScreen(RegularAttr,0,CurrentY,1);
       TWB.InitTextOnScreen(' ',0,CurrentY,1);
       BotY := DisplayData[Text].WindInfo.YSize - 2;
       CurrentY := BotY - 2;
       FOR I := 1 TO DisplayData[Text].WindInfo.YSize - 2 DO
          IF NOT DoCursorDown() THEN Beep ;
             ChangeColorOnScreen(BoldAttr, 0,CurrentY,1);
             TWB.InitTextOnScreen(MarkerSymbol,0,CurrentY,1);
             TWB.SetAutoUpdate(DisplayData[Text].WindID) ;
             RETURN END;
       END ;
       TWB.SetAutoUpdate(DisplayData[Text].WindID) ;
   | HomeKey,EndKey,AltPgUpKey,AltPgDnKey:
      IF NOT SelectedListEmpty THEN
         CASE KeyInstruction OF
           HomeKey:
              DiscardDisplayItem(WorkingList,CurPos);
              dummy := FirstDisplayItem(WorkingList, CurPos);
         | EndKey:
              DiscardDisplayItem(WorkingList,CurPos);
              dummy := LastDisplayItem(WorkingList, CurPos);
         | AltPgUpKey:
              IF NOT PrevDisplayItem(WorkingList, CurPos) THEN
                 Beep;
                 RETURN
              END;
         | AltPgDnKey:
              IF NOT NextDisplayItem(WorkingList, CurPos) THEN
                 Beep;
                 RETURN
              END;
         END;
         IF PosListStatus <> PosOnly THEN
	    DiscardDisplayItem( SelectedList, SelectedListPos ) ;
            IF NOT FindDisplayItem(WorkingList, CurPos,
                                   SelectedList,SelectedListPos) THEN
               ProgramErrorAndHalt('Could not find corresponding item')
            END;
         END
      END;
      InitialDisplay;
   ELSE
      Beep
   END;
   IF NOT SelectedListEmpty THEN
      IF PosListStatus = PosOnly THEN SelectedListPos := CurPos
      ELSE PositionListPos := CurPos END
   END;
(*Empty>*)
END HandleTextDisplay;

PROCEDURE OutputTextDisplay(VAR file:       XFileType;
                                CheckAbort: AbortProc);
VAR
   text:       StrAny;
   status:     BOOLEAN;
   i:          CARDINAL;
   NoLines:    CARDINAL;
   result:     CARDINAL;
(*<Empty*)

PROCEDURE GetTextLine(Type:   ScrollInstruction;
                  VAR text:   ARRAY OF CHAR): BOOLEAN;
VAR
   LineInfo:   LineInfoPntr;
   result:     BOOLEAN;
BEGIN
   result := GetDLine(Type,PrintDat,LineInfo);
   IF result THEN Str.Copy(text,LineInfo^.Text) END;
   DiscardDisplayItem(WorkingList, LineInfo^.ListItem);
   DEALLOCATE(LineInfo,LineInfo^.Size);
   RETURN result;
END GetTextLine;
(*Empty>*)

BEGIN
(*<Empty*)
   LaunchTextDisplayLineGenerator(PrintDat);
   IF NOT GetTextLine(Initialize,text) THEN
      ProgramErrorAndHalt('Error Initializing')
   END;
   i := 15;
   WHILE (i <> 0) AND (GetTextLine(Up,text)) DO DEC(i) END;
   NoLines := 1 ;
   REPEAT
      status := WriteWithTabs(file, text,TextDisplayTab);
      INC(i);
      INC( NoLines ) ;
      IF (PrintDest = ToPrinter) AND (NoLines > LinesPerPage) THEN
         XWrNXlate( file, ASCII.ff, result);
         NoLines := 1 ;
      END ;
   UNTIL (i > 30) OR (NOT status) OR CheckAbort() OR (NOT GetTextLine(Down,text));
   status := GetTextLine(Terminate,text);
   CloseDownTextDisplayLineGenerator(PrintDat);
(*Empty>*)
END OutputTextDisplay;

PROCEDURE InitializeTextDisplay;
BEGIN
(*<Empty*)
   InitLineProcs := TRUE;
   QueueOfGenInfos := NIL;
   WITH TextDisplayTab[0] DO
      Pos := 5;
      Type := Left;
      FilPat := '';
   END;
   WITH RefDisplayTab[0] DO
      Pos := 60 ;
      Type := Right ;
      FilPat := '';
   END;
   DefaultRef[0] := IntEnhOn ;
   DefaultRef[1] := IntTab ;
   DefaultRef[2] := '-' ;
   DefaultRef[3] := '-' ;
   DefaultRef[4] := 0C ;
   InitialPosOnLineItems;
(*Empty>*)
END InitializeTextDisplay;

END TextDisplay.
