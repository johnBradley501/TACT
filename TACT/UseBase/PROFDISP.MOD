IMPLEMENTATION MODULE ProfDisplay;

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

FROM TWB IMPORT
  (* Type  *) WinType,
  (* Const *) RightLowerTitle,
  (* Procs *) WrStr, Use, GotoXY, WrLn, SetTitle, Used ;
IMPORT ASCII, Str, TWB;
IMPORT PCKey;
FROM KeyBase IMPORT GetKeyStroke;
FROM KeyStandards IMPORT
  (* types *) ListControlKeys,
  (* procs *) GetListControlKey;
FROM Utils IMPORT ConstStr, Beep;
FROM StringIO IMPORT SWriteString;
FROM GlobalDefs IMPORT StrAny;
FROM ResMessages IMPORT GetResMessage;
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
FROM VirtMem IMPORT VirtAddr;
FROM ListData IMPORT DataItemPntr, FirstMKSLine ;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) VMAccess, VMRelease;
FROM ResCollection IMPORT ResCollectionType, ReleaseCollection ;
FROM ResDataArray IMPORT
  (* procs *) GetDataArray, GetNextDataArrayStringItem;


VAR
   AlreadyInProf: BOOLEAN;
   StackPntr:     CARDINAL;
   ProfWind:      WindowInfo;
   ProfileWinPtr : WinType ; (* m.s. *)

   DisplayTab:    ARRAY[0..0] OF TabInfo;

   i:             CARDINAL;
   CurProfItem:   CARDINAL;
   ScrollSize:    CARDINAL;
   DoRead:        BOOLEAN;
   Done:          BOOLEAN;

   DisplayText:   StrAny;
   TopList, BotList, Prev, Next: VirtAddr ;


(* m.s. - this procedure returns the line on text stored in VALine, and
          updates next and prev *)
PROCEDURE MakeProfLine(VALine: VirtAddr ; VAR Result: ARRAY OF CHAR ) ;
VAR
   Line : DataItemPntr ;

BEGIN
   Line := VMAccess( VALine ) ;
   Next := Line^.Next ;
   Str.Copy( Result , Line^.LineInfo ) ;
   VMRelease( VALine ) ;
END MakeProfLine ;


PROCEDURE PrevProfItem( VAR Result:    ARRAY OF CHAR): BOOLEAN;
VAR

   NextLine, Line : DataItemPntr ;
   PrevPrev, NextNext: VirtAddr ;
BEGIN
  IF Prev = TopList THEN
         Result[0] := 0C ;
         RETURN FALSE
  END;
  NextLine := VMAccess( Prev ) ;
  PrevPrev := Prev ;
  Prev := NextLine^.Prev ;
  VMRelease( PrevPrev ) ;
  Line := VMAccess( Prev ) ;
  Str.Copy( Result, Line^.LineInfo ) ;
  VMRelease( Prev ) ;
  IF Next = NILVirt THEN
     Next := BotList ;
  ELSE
     Line := VMAccess( Next ) ;
     NextNext := Next ;
     Next := Line^.Prev ;
     VMRelease( NextNext ) ;
  END ;
  RETURN TRUE;
END PrevProfItem;

PROCEDURE NextProfItem( VAR Result:    ARRAY OF CHAR): BOOLEAN;
VAR
   Line : DataItemPntr ;
   NextNext, PrevPrev : VirtAddr ;

BEGIN
  IF Next = NILVirt  THEN
         Result[0] := 0C ;
         RETURN FALSE
  END;

  Line := VMAccess( Next ) ;
  Str.Copy( Result, Line^.LineInfo ) ;
  IF Line^.Next = NILVirt THEN
     BotList := Next ;
  END ;
  NextNext := Next ;
  Next := Line^.Next ;
  VMRelease( NextNext ) ;
  Line := VMAccess( Prev ) ;
  PrevPrev := Prev ;
  Prev := Line^.Next ;
  VMRelease( PrevPrev ) ;
  RETURN TRUE;
END NextProfItem;

(*
PROCEDURE NextProfItem( VAR Result:    ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF Next = NILVirt THEN
         Result[0] := 0C ;
         RETURN FALSE;
  END ;
  MakeProfLine(Next,Result) ;
  RETURN TRUE;
END NextProfItem;
*)
PROCEDURE ShowCurrentLine(YPos:      CARDINAL ) ;
BEGIN
    IF NextProfItem(DisplayText) THEN
       FancyScreenDisplay(ProfileWinPtr,0,YPos,DisplayText,DisplayTab,FALSE);
    END ;
END ShowCurrentLine;

PROCEDURE InitialDisplay;
VAR i:   CARDINAL;
BEGIN
(*    DiscardProfItem(BotProf.HData); *)

    ScrollSize := ProfWind.YSize - 2;

    TWB.SetManualUpdate(ProfileWinPtr);
    TWB.Clear;

    Next := TopList ;
    Prev := TopList ;

    ShowCurrentLine(0);

    i := 1;
    WHILE (i < ProfWind.YSize) AND NextProfItem(DisplayText) DO
       FancyScreenDisplay(ProfileWinPtr,0,i,DisplayText,DisplayTab,FALSE);
       INC(i);
    END;
    Prev := TopList ;
    TWB.SetAutoUpdate(ProfileWinPtr);
END InitialDisplay;

PROCEDURE DoScrollDown(): BOOLEAN;
VAR dummy: BOOLEAN;
BEGIN
   IF NOT NextProfItem(DisplayText) THEN RETURN FALSE END;
   ScrollUp(ProfileWinPtr,1);
   FancyScreenDisplay(ProfileWinPtr,0,ProfWind.YSize-1,DisplayText,DisplayTab,TRUE);
(*   dummy := NextProfItem(TopList,DisplayText); *)
   RETURN TRUE;
END DoScrollDown;

PROCEDURE DoScrollUp(): BOOLEAN;
VAR dummy: BOOLEAN;
BEGIN
   IF NOT PrevProfItem(DisplayText) THEN RETURN FALSE END;
   ScrollDown(ProfileWinPtr,1);
   FancyScreenDisplay(ProfileWinPtr,0,0,DisplayText,DisplayTab,TRUE);
(*   dummy := PrevProfItem(BotProf,DisplayText); *)
   RETURN TRUE;
END DoScrollUp;

(* PROCEDURE InitialTopProf(CurProfItem: CARDINAL;
                     VAR TopProf:     ProfLine);
BEGIN
   WITH TopProf DO
      StartProfItem(CurProfItem,HData,PntrData);
      Count := 1;
      HLine.NumbBlkLines := 0C;
      IF NOT NextProfLine(HData, HLine) THEN
          ProgramErrorAndHalt('No Lines found in Prof Item');
      END;
   END;
END InitialTopProf;

PROCEDURE OutputProfItem(VAR file:     XFileType;
                             AskAbort: AbortProc);
VAR
   PrintProf:    ProfLine;
   DisplayText:  StrAny;
   NoLines:      CARDINAL;
   result:       CARDINAL;
BEGIN
(*   InitialTopProf(CurProfItem,PrintProf); *)
   MakeProfLine(PrintProf.HLine,DisplayText);
   NoLines := 1 ;
   REPEAT
      INC( NoLines ) ;
      IF (PrintDest = ToPrinter) AND (NoLines > LinesPerPage) THEN
         XWrNXlate( file, ASCII.ff, result);
         NoLines := 1 ;
      END ;
   UNTIL NOT (WriteWithTabs(file,DisplayText,DisplayTab) (* m.s. AND
         NextProfItem(PrintProf,DisplayText)) *) OR AskAbort();

   DiscardProfItem(PrintProf.HData);
END OutputProfItem;
*)

(* m.s. - main procedure, called once to show display *)

PROCEDURE ShowProfItem(TermList:    ARRAY OF CHAR;
                       ExtTermList: ARRAY OF CHAR;
                   VAR TermCh:      CHAR;
                   VAR TermFunct:   BOOLEAN): BOOLEAN;
VAR dummy: BOOLEAN;
    d1:    CARDINAL;
    txt:   ARRAY[0..30] OF CHAR;
    TempStr : StrAny ;

BEGIN (* ShowProfItem *)
   IF AlreadyInProf THEN
      Beep;
      RETURN TRUE
   END;
   AlreadyInProf := TRUE;

   (*RES OLD MSG 457
   TextBase Profile
   *)
   GetResMessage((*RES REM INS*) 457 , TempStr ) ;

   SetTitle( ProfileWinPtr, TempStr , RightLowerTitle ) ;

   BotList := NILVirt ;
   InitialDisplay;

   DoRead := TRUE;
   Done := FALSE;
   REPEAT
       IF DoRead THEN GetKeyStroke(TermCh,TermFunct) END;
       DoRead := TRUE;
       IF TermFunct AND (TermCh = PCKey.F9) THEN
        (*  PrintMaster(ToPrinter,OutputProfItem, DoRead, TermCh, TermFunct) *)
       ELSIF TermFunct AND (TermCh = PCKey.ShiftF9) THEN
        (*  PrintMaster(ToDisk,OutputProfItem, DoRead, TermCh, TermFunct) *)
       ELSE
          CASE GetListControlKey(TermFunct, TermCh) OF
            PrevItem:
               IF NOT DoScrollUp() THEN Beep END;
          | NextItem:
               IF NOT DoScrollDown() THEN Beep END;
          | PrevScreen:
               TWB.SetManualUpdate(ProfileWinPtr);
               IF NOT DoScrollUp() THEN Beep
               ELSE
                  i := 2;
                  WHILE (i <= ScrollSize) AND  DoScrollUp() DO
                  INC(i) END;
                 (* InitialDisplay ; *)
               END;
               TWB.SetAutoUpdate(ProfileWinPtr);

          | NextScreen:
               TWB.SetManualUpdate(ProfileWinPtr);
               IF NOT DoScrollDown() THEN Beep
               ELSE
                  i := 2;
                  WHILE (i <= ScrollSize) AND  DoScrollDown() DO
                  INC(i)
                  END;
                  (* InitialDisplay *)
               END;
               TWB.SetAutoUpdate(ProfileWinPtr);

          | FirstItem:
               InitialDisplay
          | LastItem:
               TWB.SetManualUpdate(ProfileWinPtr);
               IF NOT DoScrollDown() THEN Beep
               ELSE
                  WHILE DoScrollDown() DO
                  END;
               END;
               TWB.SetAutoUpdate(ProfileWinPtr);
          | ListEnd, ListCancel:
               DoRead := TRUE;
               Done := TRUE;
          ELSE
             IF (TermFunct AND (Str.Pos(ExtTermList,TermCh) <= HIGH(ExtTermList))) OR
             ((NOT TermFunct) AND (Str.Pos(TermList,TermCh) <= HIGH(TermList))) THEN
                DoRead := FALSE;
                Done := TRUE
             ELSE Beep;
             END;
          END;
       END;
   UNTIL Done;

   AlreadyInProf := FALSE;
   RETURN DoRead;
END ShowProfItem;



PROCEDURE DoTextBaseProfile;  (* m.s. *)

  VAR
      Ch : CHAR ;
      TempStr: StrAny ;
      TermList, ExtTermList : StrAny ; (* temporary !! *)
      TermCh : CHAR ;
      TermFunct : BOOLEAN ;
BEGIN
   WITH ProfWind DO
      XPos := 2 ;
      YPos := 4 ;
      XSize := 76 ;
      YSize := 14 ;
      MxYSize := 14 ;
      Type := Active ;
      AllowMove := FALSE ;
      AllowResize := FALSE ;
      IsTop := TRUE ;
    END ;
   PushNewWindow( ProfWind, ProfileWinPtr, DummyInit ) ;
   (*RES OLD MSG 457
   TextBase Profile
   *)
   GetResMessage((*RES REM INS*) 457 , TempStr ) ;

   SetTitle( ProfileWinPtr, TempStr , RightLowerTitle ) ;
   TopList := FirstMKSLine ;
   TermList[0] := 0C ;
   ExtTermList[0] := 0C ;
   IF NOT ShowProfItem( TermList, ExtTermList, TermCh, TermFunct ) THEN
         Beep ; (* for now *)
   END ;
   PopWindow ;
END DoTextBaseProfile ;

BEGIN
   AlreadyInProf := FALSE;
   StackPntr := 0;
   WITH ProfWind DO
        XPos :=   2;
        YPos :=   4;
        XSize := 76;
        YSize := 18;
        MxYSize := 18;
        Type := Active;
        AllowResize := TRUE;
        AllowMove := TRUE;
   END;
   WITH DisplayTab[0] DO
      Pos := 5;
      Type := Left;
      FilPat := ' ';
   END;
END ProfDisplay.
