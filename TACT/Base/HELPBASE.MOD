IMPLEMENTATION MODULE HelpBase;

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

IMPORT TWB;
IMPORT ASCII, Str;
IMPORT PCKey;
FROM KeyBase IMPORT GetKeyStroke;
FROM KeyStandards IMPORT
  (* types *) ListControlKeys,
  (* procs *) GetListControlKey;
FROM Utils IMPORT ConstStr, Beep;
FROM StringIO IMPORT SWriteString;
FROM GlobalDefs IMPORT StrAny;
FROM ResMessages IMPORT GetResMessage;
FROM ResHelp IMPORT
  (* const *) MaxHelpRefs,
  (* types *) HelpPntr, HelpData, HelpRef, HelpRefColl,
  (* procs *) StartHelpItem, NextHelpLine, PrevHelpLine,
              CopyHelpItem, DiscardHelpItem, ReleaseHelpItem;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM Windows IMPORT
  (* Const *) RegularAttr,
  (* Procs *) ScrollUp, ScrollDown;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM KeyTranslation IMPORT
  (* Const *) IntTab,
  (* Type  *) TabInfo, TabType,
  (* Procs *) FancyScreenDisplay, GetScreenField;
FROM PrintModule IMPORT PrintActionType, PrintMaster, AbortProc,
     WriteWithTabs, PrintDest, LinesPerPage ;
FROM Translations IMPORT
 (* var  *) Int2Alp, Int2Scr,
 (* type *) XlateStrAny, CurrentModeType, XFileType,
 (* proc *) XlateLine, XWrNXlate ;

CONST
   HelpStackSize = 20;

TYPE
   HelpLine = RECORD
      Count:    CARDINAL;
      HData:    HelpPntr;
      HLine:    HelpData;
   END;

VAR
   HelpStack:     ARRAY[1..HelpStackSize] OF CARDINAL;
   AlreadyInHelp: BOOLEAN;
   StackPntr:     CARDINAL;
   HelpWind:      WindowInfo;
   DisplayTab:    ARRAY[0..0] OF TabInfo;

   LWindow:       TWB.WinType;
   i:             CARDINAL;
   TopHelp:       HelpLine;
   BotHelp:       HelpLine;
   PntrData:      HelpRefColl;
   CurHelpItem:   CARDINAL;
   ScrollSize:    CARDINAL;
   DoRead:        BOOLEAN;
   Done:          BOOLEAN;

   DisplayText:   StrAny;

PROCEDURE PushHelpItem(ItemID:   CARDINAL);
BEGIN
   IF StackPntr >= HelpStackSize THEN
       ProgramErrorAndHalt('Help Stack Overflow')
   END;
   INC(StackPntr);
   HelpStack[StackPntr] := ItemID;
END PushHelpItem;

PROCEDURE ReplaceHelpItem(ItemID:   CARDINAL);
BEGIN
   IF StackPntr <= 0 THEN
       ProgramErrorAndHalt('Help Stack Underflow')
   END;
   HelpStack[StackPntr] := ItemID;
END ReplaceHelpItem;

PROCEDURE PopHelpItem;
BEGIN
   IF StackPntr <= 0 THEN
       ProgramErrorAndHalt('Help Stack Underflow')
   END;
   DEC(StackPntr);
END PopHelpItem;

PROCEDURE MakeHelpLine(VAR Line: HelpData;
                       VAR Result: ARRAY OF CHAR);
VAR
   lpos:     CARDINAL;
BEGIN
   WITH Line DO
      lpos := ORD(NumbOfBlanks);
      IF lpos > 0 THEN ConstStr(' ',ORD(NumbOfBlanks),Result) END;
      SWriteString(Result,lpos,Data,0);
   END;
END MakeHelpLine;

PROCEDURE PrevHelpItem(VAR Item:      HelpLine;
                     VAR Result:    ARRAY OF CHAR): BOOLEAN;
BEGIN
   WITH Item DO
      DEC(Count);
      IF Count = 0 THEN
         IF NOT PrevHelpLine(HData,HLine) THEN 
            Count := 1;
            RETURN FALSE
         END;
         Count := 1 + ORD(HLine.NumbBlkLines);
         MakeHelpLine(HLine,Result);
      ELSE
         Result[0] := 0C;
      END;
   END;
   RETURN TRUE;
END PrevHelpItem;

PROCEDURE NextHelpItem(VAR Item:      HelpLine;
                     VAR Result:    ARRAY OF CHAR): BOOLEAN;
BEGIN
   WITH Item DO
      IF Count > ORD(HLine.NumbBlkLines) THEN
         IF NOT NextHelpLine(HData,HLine) THEN RETURN FALSE END;
         Count := 0;
      END;
      IF Count = ORD(HLine.NumbBlkLines) THEN MakeHelpLine(HLine,Result)
                                         ELSE Result[0] := 0C END;
      INC(Count);
   END;
   RETURN TRUE;
END NextHelpItem;

PROCEDURE ShowCurrentLine(YPos:      CARDINAL;
                      VAR Item:      HelpLine);
BEGIN
   IF Item.Count > ORD(Item.HLine.NumbBlkLines) THEN
         MakeHelpLine(Item.HLine,DisplayText);
         FancyScreenDisplay(LWindow,0,YPos,DisplayText,DisplayTab,FALSE);
   END;
END ShowCurrentLine;

PROCEDURE InitialDisplay;
VAR i:   CARDINAL;
BEGIN
    DiscardHelpItem(BotHelp.HData);

    ScrollSize := HelpWind.YSize DIV 2;

    TWB.SetManualUpdate(LWindow);
    TWB.Clear;

    ShowCurrentLine(0,TopHelp);

    BotHelp := TopHelp;
    CopyHelpItem(TopHelp.HData, BotHelp.HData);
    i := 1;
    WHILE (i < HelpWind.YSize) AND NextHelpItem(BotHelp,DisplayText) DO 
       FancyScreenDisplay(LWindow,0,i,DisplayText,DisplayTab,FALSE);
       INC(i);
    END;
    TWB.SetAutoUpdate(LWindow);
END InitialDisplay;

PROCEDURE DoScrollDown(): BOOLEAN;
VAR dummy: BOOLEAN;
BEGIN
   IF NOT NextHelpItem(BotHelp,DisplayText) THEN RETURN FALSE END;
   ScrollUp(LWindow,1);
   FancyScreenDisplay(LWindow,0,HelpWind.YSize-1,DisplayText,DisplayTab,TRUE);
   dummy := NextHelpItem(TopHelp,DisplayText);
   RETURN TRUE;
END DoScrollDown;

PROCEDURE DoScrollUp(): BOOLEAN;
VAR dummy: BOOLEAN;
BEGIN
   IF NOT PrevHelpItem(TopHelp,DisplayText) THEN RETURN FALSE END;
   ScrollDown(LWindow,1);
   FancyScreenDisplay(LWindow,0,0,DisplayText,DisplayTab,TRUE);
   dummy := PrevHelpItem(BotHelp,DisplayText);
   RETURN TRUE;
END DoScrollUp;

PROCEDURE InitialTopHelp(CurHelpItem: CARDINAL;
                     VAR TopHelp:     HelpLine);
BEGIN
   WITH TopHelp DO
      StartHelpItem(CurHelpItem,HData,PntrData);
      Count := 1;
      HLine.NumbBlkLines := 0C;
      IF NOT NextHelpLine(HData, HLine) THEN
          ProgramErrorAndHalt('No Lines found in Help Item');
      END;
   END;
END InitialTopHelp;

PROCEDURE InJumpList(ch:       CHAR;
                 VAR HelpItem: CARDINAL): BOOLEAN;
VAR i:   CARDINAL;
BEGIN
   ch := CAP(ch);
   WITH PntrData DO
      IF Size = 0 THEN RETURN FALSE END;
      FOR i := 0 TO Size-1 DO
         IF ch = Data[i].TypedChar THEN
            HelpItem := Data[i].NextID;
            RETURN TRUE
         END;
      END;
   END;
   RETURN FALSE
END InJumpList;

(* m.s. - no longer needed
PROCEDURE OutputHelpItem(VAR file:     XFileType;
                             AskAbort: AbortProc);
VAR
   PrintHelp:    HelpLine;
   DisplayText:  StrAny;
   NoLines:      CARDINAL;
   result:       CARDINAL;
BEGIN
   InitialTopHelp(CurHelpItem,PrintHelp);
   MakeHelpLine(PrintHelp.HLine,DisplayText);
   NoLines := 1 ;
   REPEAT
      INC( NoLines ) ;
      IF (PrintDest = ToPrinter) AND (NoLines > LinesPerPage) THEN
         XWrNXlate( file, ASCII.ff, result);
         NoLines := 1 ;
      END ;
   UNTIL NOT (WriteWithTabs(file,DisplayText,DisplayTab) AND
         NextHelpItem(PrintHelp,DisplayText)) OR AskAbort();

   DiscardHelpItem(PrintHelp.HData);
END OutputHelpItem;
*)

PROCEDURE ShowHelpItem(TermList:    ARRAY OF CHAR;
                       ExtTermList: ARRAY OF CHAR;
                   VAR TermCh:      CHAR;
                   VAR TermFunct:   BOOLEAN): BOOLEAN;
VAR dummy: BOOLEAN;
    d1:    CARDINAL;
    txt:   ARRAY[0..30] OF CHAR;

BEGIN (* ShowHelpItem *)
   IF AlreadyInHelp THEN
      Beep;
      RETURN TRUE
   END;
   AlreadyInHelp := TRUE;
   IF (StackPntr <= 0) OR (StackPntr > HelpStackSize) THEN
       ProgramErrorAndHalt('Bad StackPntr')
   END;
   CurHelpItem := HelpStack[StackPntr];
   InitialTopHelp(CurHelpItem,TopHelp);
   BotHelp := TopHelp;
   CopyHelpItem(TopHelp.HData, BotHelp.HData);

   (*RES OLD MSG 209
   Help Window
   *)
   GetResMessage( (*RES REM INS*) 209 , txt);
   PushNewWindow(HelpWind,LWindow, InitialDisplay);
   TWB.SetTitle(LWindow, txt, TWB.RightLowerTitle);

   InitialDisplay;

   DoRead := TRUE;
   Done := FALSE;
   REPEAT
       IF DoRead THEN GetKeyStroke(TermCh,TermFunct) END;
       DoRead := TRUE;
       IF TermFunct AND (TermCh = PCKey.F9) THEN
            Beep ; (* m.s. - disabled printing from within help menus *)
(*          PrintMaster(ToPrinter,OutputHelpItem, DoRead, TermCh, TermFunct) *)
       ELSIF TermFunct AND (TermCh = PCKey.ShiftF9) THEN
            Beep ; (* m.s. - disabled printing from within help menus *)
(*          PrintMaster(ToDisk,OutputHelpItem, DoRead, TermCh, TermFunct) *)
       ELSE
          CASE GetListControlKey(TermFunct, TermCh) OF
            PrevItem:
               IF NOT DoScrollUp() THEN Beep END;
          | NextItem:
               IF NOT DoScrollDown() THEN Beep END;
          | PrevScreen:
               IF NOT PrevHelpItem(TopHelp,DisplayText) THEN Beep
               ELSE
                  i := 2;
                  WHILE (i <= ScrollSize) AND
                  PrevHelpItem(TopHelp,DisplayText) DO INC(i) END;
                  InitialDisplay
               END;
          | NextScreen:
               IF NOT NextHelpItem(BotHelp,DisplayText) THEN Beep
               ELSE
                  dummy := NextHelpItem(TopHelp,DisplayText);
                  i := 2;
                  WHILE (i <= ScrollSize) AND
                  NextHelpItem(BotHelp,DisplayText) DO
                     dummy := NextHelpItem(TopHelp,DisplayText);
                     INC(i)
                  END;
                  InitialDisplay
               END;
          | FirstItem:
               IF NOT PrevHelpItem(TopHelp,DisplayText) THEN Beep
               ELSE
                  WHILE PrevHelpItem(TopHelp,DisplayText) DO END;
                  InitialDisplay
               END;
          | LastItem:
               IF NOT NextHelpItem(BotHelp,DisplayText) THEN Beep
               ELSE
                  dummy := NextHelpItem(TopHelp,DisplayText);
                  WHILE NextHelpItem(BotHelp,DisplayText) DO
                     dummy := NextHelpItem(TopHelp,DisplayText);
                  END;
                  InitialDisplay
               END;
          | ListEnd, ListCancel:
               DoRead := TRUE;
               Done := TRUE;
          ELSE
             IF (TermFunct AND (Str.Pos(ExtTermList,TermCh) <= HIGH(ExtTermList))) OR
             ((NOT TermFunct) AND (Str.Pos(TermList,TermCh) <= HIGH(TermList))) THEN
                DoRead := FALSE;
                Done := TRUE
             ELSIF (NOT TermFunct) AND InJumpList(TermCh, CurHelpItem) THEN
                InitialTopHelp(CurHelpItem,TopHelp);
                InitialDisplay
             ELSE Beep;
             END;
          END;
       END;
   UNTIL Done;

   PopWindow;
   DiscardHelpItem(BotHelp.HData);
   ReleaseHelpItem(TopHelp.HData);
   AlreadyInHelp := FALSE;
   RETURN DoRead;
END ShowHelpItem;


(* m.s. - apr 94 - used to display credit screen *)
PROCEDURE ShowCredit( ItemID: CARDINAL;
                      TermList:    ARRAY OF CHAR;
                      ExtTermList: ARRAY OF CHAR;
                   VAR TermCh:      CHAR;
                   VAR TermFunct:   BOOLEAN ) ;
VAR
   ch : CHAR ;
   DoRead : BOOLEAN ;
BEGIN
   PushHelpItem( ItemID ) ;
   DoRead := ShowHelpItem( TermList, ExtTermList, TermCh, TermFunct ) ;
   PopHelpItem ;
END ShowCredit ;


BEGIN
   AlreadyInHelp := FALSE;
   StackPntr := 0;
   WITH HelpWind DO
        XPos :=   2;
        YPos :=   4;
        XSize := 76;
        YSize := 14;
        MxYSize := 14;
        Type := Active;
        AllowResize := TRUE;
        AllowMove := TRUE;
   END;
   WITH DisplayTab[0] DO
      Pos := 5;
      Type := Left;
      FilPat := ' ';
   END;
END HelpBase.
