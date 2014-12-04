IMPLEMENTATION MODULE Windows ;

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
(*V2=Debug *)

(*
  By: Lidio Presutti
  Date: 08/04/1988
  Last Modified:
	29 July 1988, L.Presutti
		- fixed DoMove & DoResize to allow move/resize to col 80, row 25
        8 Feb 1990, L.Presutti
                - replaced TWB.DoubleFrame with TWB.SingleFrame
*)

FROM SYSTEM IMPORT Registers;
IMPORT Lib, Str, FIO;
IMPORT TWB;
IMPORT ASCII;
FROM Utils IMPORT Beep, StandardSearchList, FindFileInList, GetEnv,
                  UpcaseStr, Status, Terminate, InstallTermProc;
FROM KeyBase IMPORT GetKeyStroke ;
FROM GlobalDefs IMPORT StrAny ;
FROM PCKey    IMPORT CursorUp, CursorDn, CursorLeft, CursorRight,
              CtrlCursorLeft, CtrlCursorRight, ExtendedCharCode ;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) NextColItem,ReleaseCollection;
FROM Char512 IMPORT PSType, LoadROMFont, ReadIn8x14CharDef,
   Set512CharSet,Set256CharSet, ExtendedAvailable;

(* May not be needed if Terminate invokes TermProcs for Trace  .. j.b.
(*<Debug
FROM Trace IMPORT
  (* Vars  *) DoTrace,
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard, 
		TWriteAddr, CloseTFile ;
Debug>*)
*)

CONST
    (* Video modes *) (* as defined for the IBM BIOS interrupt 10H *)
    BW40            = 0;
    CO40            = 1;
    BW80            = 2;
    CO80            = 3;
    ColorGraphic320 = 4;
    BWGraphic320    = 5;
    BWGraphic640    = 6;
    Monochrome      = 7;
    LCD             = 99; (* special mode for TACT only *)

    ErrorWStartX = 1;
    ErrorWStartY = 1;
    ErrorWSizeX = 78;
    ErrorWSizeY = 7;

    Font2Offset = 3;
    MonoULine = TWB.PaletteColorDef(TWB.Color(1),TWB.Color(0));
    MonoBoldULine = TWB.PaletteColorDef(TWB.Color(9),TWB.Color(0));
    MonoWhiteOnBlack = TWB.PaletteColorDef(TWB.Color(7),TWB.Color(0));
    MonoBlackOnWhite = TWB.PaletteColorDef(TWB.Color(0),TWB.Color(7));
    MonoBoldOnBlack = TWB.PaletteColorDef(TWB.Color(0FH),TWB.Color(0));
    MonoBlackOnBold = TWB.PaletteColorDef(TWB.Color(0),TWB.Color(0FH));

VAR
   ch:         CHAR;
   OldAttr:    CHAR;
   ProgramTerminatedMessage: ARRAY[0..30] OF CHAR;
   NotEnoughMemoryMessage:  ARRAY[0..60] OF CHAR;
   FriendlyMessage:  ARRAY[0..60] OF CHAR;
   ResetFonts:       BOOLEAN;
   FontLoaded:       ARRAY[0..1] OF BOOLEAN;

PROCEDURE NonWMMessage(Text: ARRAY OF CHAR);
VAR i, j, k, len : CARDINAL ;
    CurLine : ARRAY[0..80] OF CHAR ;
BEGIN
   len := Str.Length( Text );
   j := 0;
   i := 0;
   WHILE (i <= len ) DO
     IF i + 79 < len THEN
        i := i + 79;
        k := 79;
        WHILE (Text[i] <> ' ') DO
          DEC (i);
          DEC (k);
        END ;
        INC (i);
     ELSE
        i := len + 1;
     END ;
     Str.Slice( CurLine, Text, j, k);
     j := i;
     FIO.WrStr(FIO.StandardOutput,CurLine);
     FIO.WrLn(FIO.StandardOutput);
   END ;
END NonWMMessage;

PROCEDURE NoCanDo( Text : ARRAY OF CHAR ) ;

   BEGIN
      NonWMMessage(Text);

      Terminate( Warning ) ;  (* halt without MEMORY.DMP file *)
   END NoCanDo ;

PROCEDURE EndWindows();
VAR r:  Registers;
BEGIN
   TWB.PutOnTop( TWB.FullScreen ) ;
   TWB.Use( TWB.FullScreen ) ;
   IF ResetFonts THEN
      IF FontLoaded[0] THEN LoadROMFont(0) END;
      IF FontLoaded[1] THEN LoadROMFont(1) END;
      Set256CharSet(0);
   END;
   TWB.CursorOn;
(* following code _MAY_ not be needed if Terminate is used ... j.b.
   (*<Debug
   IF DoTrace THEN
   	 CloseTFile ;
   END ;
   Debug>*)
   HALT ;     (* Stop and produce a MEMORY.DMP file for PMD *)

   r.AX := 0600H;  (* clear screen *)
   r.BH := SHORTCARD(OldAttr);
   r.CX := 0000H;
   r.DH := 24;
   r.DL := 79;
   Lib.Intr(r,10H);
*)
END EndWindows;

PROCEDURE InitWindows();
   VAR
     Mode:          CARDINAL;
     WD:            TWB.WinDef;
     ScreenType:    PSType;
     NoScreenFonts: CARDINAL;
     Font1Loaded:   BOOLEAN;

(*RES OLD DTA 1
    'Error'
    'Warning'
    'Information'
    'Prompt'
    ' Press any Key to Continue '
    'Program has Terminated.'
    'Not enough Memory Available to Create New Window.'
    'Program Initialising, Please Wait ... '
*)

PROCEDURE GetWindowMessages;
VAR
   ResC:    ResCollectionType;
   dummy:   BOOLEAN;

BEGIN
   GetDataArray( (* RES REM INS*) 1, ResC);

   dummy := GetNextDataArrayStringItem(ResC,ErrorText);
   dummy := GetNextDataArrayStringItem(ResC,WarningText);
   dummy := GetNextDataArrayStringItem(ResC,InfoText);
   dummy := GetNextDataArrayStringItem(ResC,PromptText);
   dummy := GetNextDataArrayStringItem(ResC,PressText);
   dummy := GetNextDataArrayStringItem(ResC,ProgramTerminatedMessage);
   dummy := GetNextDataArrayStringItem(ResC,NotEnoughMemoryMessage);
   dummy := GetNextDataArrayStringItem(ResC,FriendlyMessage);

   ReleaseCollection(ResC);
END GetWindowMessages;

PROCEDURE GetScreenMode(): CARDINAL;
VAR r:  Registers;
    tStr: ARRAY[0..20] OF CHAR;

PROCEDURE ParseTSCREnv(EnvVal: ARRAY OF CHAR): CARDINAL;
VAR
   ResC:    ResCollectionType;
   tStr:    ARRAY[0..10] OF CHAR;
   dummy:   BOOLEAN;

(*RES OLD DTA 23
    BW80 CO80 MONOCHROME LCD
*)

PROCEDURE DoNextType(): BOOLEAN;
BEGIN
   dummy := GetNextDataArrayStringItem(ResC,tStr);
   IF Str.Compare(tStr,EnvVal) = 0 THEN
      ReleaseCollection(ResC);
      RETURN TRUE;
   END;
   RETURN FALSE;
END DoNextType;

BEGIN
   UpcaseStr(EnvVal, EnvVal);
   GetDataArray( (*RES REM INS*) 23 , ResC);

   IF DoNextType() THEN RETURN BW80 END;
   IF DoNextType() THEN RETURN CO80 END;
   IF DoNextType() THEN RETURN Monochrome END;
   IF DoNextType() THEN RETURN LCD END;
   ReleaseCollection(ResC);
   RETURN CO80;
END ParseTSCREnv;

BEGIN
   r.AX := 0800H; (* read Attributes/char at cursor position *)
   Lib.Intr(r,10H);
   OldAttr := CHR(r.AH);

   GetEnv('TACTSCR',tStr);
   IF tStr[0] <> 0C THEN
      RETURN ParseTSCREnv(tStr)
   ELSE
      r.AX := 0F00H;
      Lib.Intr(r,10H);
      RETURN CARDINAL(r.AL);
   END;
END GetScreenMode;

PROCEDURE LoadFont(No:  CARDINAL): BOOLEAN;
VAR fontName:   ARRAY[0..8] OF CHAR;
    DirName:    ARRAY[0..79] OF CHAR;
    f:          FIO.File;
BEGIN
   IF No > NoScreenFonts THEN RETURN FALSE END;
   fontName := 'TACT .EGA';
   fontName[4] := CHR(ORD('0') + No);
   IF NOT FindFileInList(StandardSearchList,fontName,DirName) THEN
      RETURN FALSE
   END;
   Str.Append( DirName, fontName );
   f := FIO.Open(DirName);
   ReadIn8x14CharDef(SHORTCARD(No),0,0C,f);
   FIO.Close(f);
   FontLoaded[No] := TRUE;
   RETURN TRUE;
END LoadFont;

PROCEDURE DoAttrSet(Mode:   CARDINAL; TwoFonts: BOOLEAN);

PROCEDURE GetAttribs(ResNo:  CARDINAL);
VAR
   ResC:    ResCollectionType;
   dummy:   BOOLEAN;
   szdummy: CARDINAL;
BEGIN
   GetDataArray( ResNo, ResC);

   dummy := NextColItem(ResC,DialogAttrib,szdummy);
   dummy := NextColItem(ResC,ErrorAttrib,szdummy);
   dummy := NextColItem(ResC,InActiveAttrib,szdummy);
   dummy := NextColItem(ResC,ActiveAttrib,szdummy);
   dummy := NextColItem(ResC,ActionBarAttrib,szdummy);

   ReleaseCollection(ResC);
END GetAttribs;

BEGIN
   IF TwoFonts THEN
     CASE Mode OF
        BW80 :        GetAttribs( 20 );
      | CO80 :        GetAttribs( 19 );
      | Monochrome :  GetAttribs( 21 );
      | LCD :         GetAttribs( 22 );
     END;
   ELSE
     CASE Mode OF
        BW80 :        GetAttribs( 17 );
      | CO80 :        GetAttribs( 16 );
      | Monochrome :  GetAttribs( 18 );
      | LCD :         GetAttribs( 22 );
     END;
   END;
END DoAttrSet;

(*
PROCEDURE DoAttrSetFor1Font;
BEGIN
     CASE Mode OF
        BW80 :                           (* Fore        Back *)
           DialogAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.Black);
           DialogAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.White, TWB.Black);
           DialogAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Black, TWB.LightGray);

           ErrorAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.DarkGray, TWB.LightGray);
           ErrorAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Black, TWB.LightGray);
           ErrorAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.White, TWB.Black);

           ActiveAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.Black);
           ActiveAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.White, TWB.Black);
           ActiveAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.White, TWB.Black);

           InActiveAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.DarkGray, TWB.LightGray);
           InActiveAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Black, TWB.LightGray);
           InActiveAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.White, TWB.Black);

           ActionBarAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.Black);
           ActionBarAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.White, TWB.Black);
           ActionBarAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Black, TWB.LightGray);

      | CO80 :
           DialogAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.White, TWB.Black);
           DialogAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Yellow, TWB.Black);
           DialogAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Yellow, TWB.LightGray);

           ErrorAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.White, TWB.Red);
           ErrorAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Yellow, TWB.Red);
           ErrorAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.LightGreen, TWB.Red);

           ActiveAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.White, TWB.Blue);
           ActiveAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Yellow, TWB.Blue);
           ActiveAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.LightGreen, TWB.Blue);

           InActiveAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.White, TWB.LightGray);
           InActiveAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Yellow, TWB.LightGray);
           InActiveAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.LightGreen, TWB.LightGray);

           ActionBarAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.LightCyan, TWB.Green);
           ActionBarAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Yellow, TWB.Green);
           ActionBarAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Yellow, TWB.Blue);

      | Monochrome :
           DialogAttrib[RegularAttr] := MonoWhiteOnBlack;
           DialogAttrib[BoldAttr] :=    MonoBoldOnBlack;
           DialogAttrib[SpecialAttr] := MonoBoldULine;

           ErrorAttrib[RegularAttr] :=  MonoBlackOnWhite;
           ErrorAttrib[BoldAttr] :=     MonoBoldOnBlack;
           ErrorAttrib[SpecialAttr] :=  MonoWhiteOnBlack;

           ActiveAttrib[RegularAttr] := MonoWhiteOnBlack;
           ActiveAttrib[BoldAttr] :=    MonoBoldOnBlack;
           ActiveAttrib[SpecialAttr] := MonoBoldOnBlack;

           InActiveAttrib[RegularAttr] := MonoBlackOnWhite;
           InActiveAttrib[BoldAttr] :=    MonoWhiteOnBlack;
           InActiveAttrib[SpecialAttr] := MonoWhiteOnBlack;

           ActionBarAttrib[RegularAttr] := MonoBoldOnBlack;
           ActionBarAttrib[BoldAttr] :=    MonoBoldULine;
           ActionBarAttrib[SpecialAttr] := MonoBlackOnBold;
        ELSE
           (* BW40, CO40, ColorGraphic320, BWGraphic320, BWGraphics640 *)

           (* should we attempt to reset the video here?  *)
                  (* I don't think so .. John *)
        END ;  (* Case Mode *)
END DoAttrSetFor1Font;

PROCEDURE DoAttrSetFor2Fonts;

PROCEDURE Add2ndFont(VAR Palette: PaletteDef);
VAR i: TWB.PaletteRange;
BEGIN
   FOR i := 0 TO 2 DO;
      Palette[i+3] := Palette[i];
      INC(Palette[i+3].Fore,8)
   END;
END Add2ndFont;

BEGIN
   CASE Mode OF
      BW80 :                                                   (* Fore        Back *)
         DialogAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.Black);
         DialogAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Black, TWB.LightGray);
         DialogAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Black, TWB.White);

         ErrorAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.Black, TWB.White);
         ErrorAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.White);
         ErrorAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.White);

         ActiveAttrib := DialogAttrib;

         InActiveAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.Black, TWB.LightGray);
         InActiveAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Black, TWB.LightGray);
         InActiveAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Black, TWB.LightGray);

         ActionBarAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.White);
         ActionBarAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Black, TWB.White);
         ActionBarAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.Black);

    | CO80 :
         DialogAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.Black);
         DialogAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Cyan, TWB.Black);
         DialogAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Black, TWB.Cyan);

         ErrorAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.Black, TWB.Red);
         ErrorAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.Red);
         ErrorAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Green, TWB.Red);

         ActiveAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.Brown, TWB.Black);
         ActiveAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Red, TWB.Black);
         ActiveAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.LightGray, TWB.Black);

         InActiveAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.Black, TWB.LightGray);
         InActiveAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Red, TWB.LightGray);
         InActiveAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Green, TWB.LightGray);

         ActionBarAttrib[RegularAttr] := TWB.PaletteColorDef(TWB.Black, TWB.Green);
         ActionBarAttrib[BoldAttr] := TWB.PaletteColorDef(TWB.Brown, TWB.Green);
         ActionBarAttrib[SpecialAttr] := TWB.PaletteColorDef(TWB.Green, TWB.Black);

    | Monochrome :
         DialogAttrib[RegularAttr] := MonoWhiteOnBlack;
         DialogAttrib[BoldAttr] :=    MonoULine;
         DialogAttrib[SpecialAttr] := MonoBlackOnWhite;


         ErrorAttrib[RegularAttr] := MonoBlackOnBold;
         ErrorAttrib[BoldAttr] :=    MonoWhiteOnBlack;
         ErrorAttrib[SpecialAttr] := MonoWhiteOnBlack;

         ActiveAttrib[RegularAttr] := MonoWhiteOnBlack;
         ActiveAttrib[BoldAttr] :=    MonoBlackOnWhite;
         ActiveAttrib[SpecialAttr] := MonoULine;

         InActiveAttrib[RegularAttr] := MonoBlackOnWhite;
         InActiveAttrib[BoldAttr] :=    MonoBlackOnWhite;
         InActiveAttrib[SpecialAttr] := MonoBlackOnWhite;

         ActionBarAttrib[RegularAttr] := MonoWhiteOnBlack;
         ActionBarAttrib[BoldAttr] :=    MonoULine;
         ActionBarAttrib[SpecialAttr] := MonoBlackOnWhite;
      ELSE
         (* BW40, CO40, ColorGraphic320, BWGraphic320, BWGraphics640 *)

         (* should we attempt to reset the video here?  *)
                (* I don't think so .. John *)
      END ;  (* Case Mode *)
      Add2ndFont(DialogAttrib);
      Add2ndFont(ErrorAttrib);
      Add2ndFont(ActiveAttrib);
      Add2ndFont(InActiveAttrib);
      Add2ndFont(ActionBarAttrib);
END DoAttrSetFor2Fonts;
*)

   BEGIN
     TWB.CursorOff;

     GetWindowMessages;
     (* write a friendly message on the screen while doing other initialisations *)

     NonWMMessage(FriendlyMessage);

     IF ExtendedAvailable(ScreenType,NoScreenFonts) THEN
        Font1Loaded := LoadFont(0);
        IF Font1Loaded THEN ResetFonts := TRUE END;
        IF LoadFont(1) THEN
           ResetFonts := TRUE;
           NoScreenFonts := 2;
           Set512CharSet(0,1);
        ELSE
           NoScreenFonts := 1
        END;
     ELSE NoScreenFonts := 1;
     END;

     DoAttrSet(GetScreenMode(),NoScreenFonts <> 1);

     WITH WD DO
        X1 := ErrorWStartX;
        Y1 := ErrorWStartY;
        X2 := ErrorWStartX + ErrorWSizeX - 1;
        Y2 := ErrorWStartY + ErrorWSizeY - 1;
        CursorOn := FALSE;
        WrapOn := FALSE;
        Hidden := TRUE; (* << note j.b. *)
        FrameOn := TRUE;
        FrameDef := TWB.SingleFrame;
     END;
     ErrorWindow := TWB.PaletteOpen(WD,ErrorAttrib);
     InstallTermProc(EndWindows);
   END InitWindows ;

PROCEDURE CreateNewWindow( VAR WindowRec    : WinType;
                               XPos, YPos   : CARDINAL;  (* position on monitor    *)
                               NRows, NCols : CARDINAL;  (* window size (inside frame) *)
                               ScreenLen    : CARDINAL;  (* max # of columns [upto 255] *)
                               DefaultAttrib : PaletteDef;
                               Border       : BOOLEAN ) ;
VAR
   WD:    TWB.WinDef;
   BEGIN
      WITH WD DO
         X1 := XPos;
         Y1 := YPos;
         IF Border THEN
            IF X1 > 0 THEN DEC(X1) END;
            IF Y1 > 0 THEN DEC(Y1) END;
         END;
         X2 := X1 + NCols-1;
         Y2 := Y1 + NRows-1;
         IF Border THEN
            IF X2 < TWB.ScreenWidth THEN INC(X2,2) END;
            IF Y2 < TWB.ScreenDepth THEN INC(Y2,2) END;
         END;
         CursorOn := FALSE;
         WrapOn := FALSE;
         Hidden := FALSE;
         FrameOn := Border;
         IF Border THEN
            FrameDef := TWB.SingleFrame;
         END;
      END;
      WindowRec := TWB.PaletteOpen(WD, DefaultAttrib);

(*
         (* do some checks on the window cordinates  *)
         (* Note: these only affect the local values *)
         IF XPos > 78 THEN  XPos := 78  END ;
         IF YPos > 23 THEN  YPos := 23  END ;
         IF NRows < 1 THEN  NRows := 1  END ;
         IF NCols < 1 THEN  NCols := 1  END ;
         IF (NRows + YPos) > 24 THEN  NRows := 24 - YPos  END ;
         IF (NCols + XPos) > 79 THEN  NCols := 79 - XPos  END ;
*)
   END CreateNewWindow ;

PROCEDURE GetRidOfWindow( VAR WindowRec  : WinType ) ;
   BEGIN
      TWB.Close(WindowRec); 
   END GetRidOfWindow ;

PROCEDURE ScrollUp(   WindowRec  : WinType;
                      Amount     : CARDINAL ) ;
VAR i:   CARDINAL;
BEGIN
   TWB.Use(WindowRec);
   TWB.GotoXY(0,0);
   FOR i := 1 TO Amount DO TWB.DelLine END;
END ScrollUp ;

PROCEDURE ScrollDown( WindowRec : WinType; Amount : CARDINAL ) ;
VAR i:   CARDINAL;
BEGIN
   TWB.Use(WindowRec);
   TWB.GotoXY(0,0);
   FOR i := 1 TO Amount DO TWB.InsLine END;
END ScrollDown ;

PROCEDURE ReSizeWindow( VAR WindowRec : WinType;
                        VAR FunctKey  : BOOLEAN;
                        VAR TermCh    : CHAR ) ;
VAR
      WD           : TWB.WinDef;
      ch           : CHAR ;
      ExtendedChar : BOOLEAN ;
      done         : BOOLEAN ;
      DX,DY        : INTEGER ;
      oldCursor    : BOOLEAN ;
      oldXCursor   : CARDINAL ;
      oldYCursor   : CARDINAL ;

PROCEDURE DoResize;
BEGIN
      IF INTEGER(WD.X2 - WD.X1 ) + DX < 2 THEN
         Beep;
         RETURN
      END;
      IF INTEGER(WD.X2 - WD.X1 ) + DX > INTEGER(MoveRange.XBot) THEN
         Beep;
         RETURN
      END;
      IF INTEGER(WD.Y2 - WD.Y1 ) + DY < 2 THEN
         Beep;
         RETURN
      END;
      IF INTEGER(WD.Y2 - WD.Y1 ) + DY > INTEGER(MoveRange.YBot) THEN
         Beep;
         RETURN
      END;
      WD.X2 := CARDINAL(INTEGER(WD.X2) + DX);
      WD.Y2 := CARDINAL(INTEGER(WD.Y2) + DY);
      TWB.Change(WindowRec, WD.X1, WD.Y1, WD.X2, WD.Y2);
END DoResize;

BEGIN
   TWB.PutOnTop(WindowRec);
   TWB.Info(WindowRec, WD);
   TWB.Use(WindowRec);
   oldCursor := WD.CursorOn;
   oldXCursor := TWB.WhereX();
   oldYCursor := TWB.WhereY();
   TWB.CursorOn;
   done := FALSE;
   REPEAT
      TWB.GotoXY(WD.X2, WD.Y2);
      ResizeMoveKeyRead( ch, ExtendedChar ) ;
      IF ExtendedChar THEN
         CASE ch OF
            CursorUp :        DX := 0; DY := -1
          | CursorDn :        DX := 0; DY := 1
          | CursorLeft :      DX := -1; DY := 0
          | CtrlCursorLeft :  DX := -4; DY := 0
          | CursorRight :     DX := 1; DY := 0
          | CtrlCursorRight : DX := 4; DY := 0
         ELSE
             done := TRUE
         END ;  (* case *)
         IF NOT done THEN DoResize END;
      ELSE done := TRUE
      END;
   UNTIL done;
   IF NOT oldCursor THEN TWB.CursorOff END;
   TWB.GotoXY(oldXCursor, oldYCursor);
(* IF (NOT ExtendedChar) AND ((ch = ASCII.esc) OR (ch = ASCII.rs)) THEN
      ResizeMoveKeyRead( ch, ExtendedChar ) ;
   END; *)
   FunctKey := ExtendedChar;
   TermCh := ch;
END ReSizeWindow;

PROCEDURE MoveWindow(   VAR WindowRec : WinType;
                        VAR FunctKey  : BOOLEAN;
                        VAR TermCh    : CHAR ) ;
VAR
      WD           : TWB.WinDef;
      ch           : CHAR ;
      ExtendedChar :  BOOLEAN ;
      done         :  BOOLEAN ;
      DX,DY        : INTEGER ;
      FrameTmp     : BOOLEAN;
      oldCursor    : BOOLEAN ;
      oldXCursor   : CARDINAL ;
      oldYCursor   : CARDINAL ;

PROCEDURE DoMove;
BEGIN
      IF INTEGER(WD.X1) + DX < INTEGER(MoveRange.XTop) THEN
         Beep;
         RETURN
      END;
      IF INTEGER(WD.X2) + DX > INTEGER(MoveRange.XBot) THEN
         Beep;
         RETURN
      END;
      IF INTEGER(WD.Y1) + DY < INTEGER(MoveRange.YTop) THEN
         Beep;
         RETURN
      END;
      IF INTEGER(WD.Y2) + DY > INTEGER(MoveRange.YBot) THEN
         Beep;
         RETURN
      END;
      WD.X2 := CARDINAL(INTEGER(WD.X2) + DX);
      WD.Y2 := CARDINAL(INTEGER(WD.Y2) + DY);
      WD.X1 := CARDINAL(INTEGER(WD.X1) + DX);
      WD.Y1 := CARDINAL(INTEGER(WD.Y1) + DY);
      TWB.Change(WindowRec, WD.X1, WD.Y1, WD.X2, WD.Y2);
END DoMove;

BEGIN
(* FrameTmp := WindowRec^.WDef.FrameOn;
   WindowRec^.WDef.FrameOn := FALSE; *)
   TWB.PutOnTop(WindowRec);
   TWB.Info(WindowRec, WD);
   TWB.Change(WindowRec, WD.X1, WD.Y1, WD.X2, WD.Y2);
   TWB.Use(WindowRec);
   oldCursor := WD.CursorOn;
   oldXCursor := TWB.WhereX();
   oldYCursor := TWB.WhereY();
   TWB.CursorOn;
   done := FALSE;
   REPEAT
      TWB.GotoXY(0,0);
      ResizeMoveKeyRead( ch, ExtendedChar ) ;
      IF ExtendedChar THEN
         CASE ch OF
            CursorUp :        DX := 0; DY := -1
          | CursorDn :        DX := 0; DY := 1
          | CursorLeft :      DX := -1; DY := 0
          | CtrlCursorLeft :  DX := -4; DY := 0
          | CursorRight :     DX := 1; DY := 0
          | CtrlCursorRight : DX := 4; DY := 0
         ELSE
             done := TRUE
         END ;  (* case *)
         IF NOT done THEN DoMove END;
      ELSE done := TRUE
      END;
   UNTIL done;
   IF NOT oldCursor THEN TWB.CursorOff END;
   TWB.GotoXY(oldXCursor, oldYCursor);
   IF (NOT ExtendedChar) AND ((ch = ASCII.esc) OR (ch = ASCII.rs)) THEN
      ResizeMoveKeyRead( ch, ExtendedChar ) ;
   END;
   FunctKey := ExtendedChar;
   TermCh := ch;
(* WindowRec^.WDef.FrameOn := FrameTmp; *)
END MoveWindow;

PROCEDURE ChangeColorOnScreen(pc:  CARDINAL;
                              X,Y: CARDINAL;Len: CARDINAL);
TYPE
   ScreenPos = RECORD
     Char:  CHAR;
     Attr:  SHORTCARD;
   END;
   ScreenLine = ARRAY [0..79] OF ScreenPos;
VAR
  W : TWB.WinType;
  RL,i: CARDINAL;
  WK: ScreenLine;
  attr: SHORTCARD;
BEGIN
  W := TWB.Used();
  WITH W^ DO
(*   MX := W^.Width;
     IF WDef.FrameOn AND NOT WDef.WrapOn THEN DEC(MX) END; *)
     RL := Len;
     IF RL + X >= Width THEN RL := Width - X END;
  END;
  attr := SHORTCARD(pc);
  TWB.RdBufferLn ( W,X,Y,ADR(WK),RL);
  FOR i := 0 TO RL - 1 DO
     IF WK[i].Attr >= Font2Offset THEN WK[i].Attr := attr + Font2Offset
     ELSE WK[i].Attr := attr END;
  END;
  TWB.WrBufferLn ( W,X,Y,ADR(WK),RL);
END ChangeColorOnScreen;

BEGIN  (* initialise global variables *)
   ErrorWindow := NIL ;

(* These variables must be predefined (even before defined by
   resource read during initialization of windows, in case of
   an error occuring during that resource read  (j.b.)  *)

   ErrorText := 'Error';
   PressText := ' Press any key to continue ';
   WITH MoveRange DO
      XTop := 0; YTop := 0;
      XBot := TWB.ScreenWidth-1; YBot := TWB.ScreenDepth-1;
   END;
   ResetFonts := FALSE;
   FontLoaded[0] := FALSE;
   FontLoaded[1] := FALSE;
END Windows .

