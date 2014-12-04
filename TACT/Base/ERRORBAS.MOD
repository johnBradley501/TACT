IMPLEMENTATION MODULE ErrorBase;

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
(*$V-*)

(*V1=Production *)
(*V2=Debug *)

FROM SYSTEM IMPORT ADR;
IMPORT Str, TWB ;
FROM StringIO IMPORT SWriteString, SWriteChar, SWriteCard;
FROM GlobalDefs IMPORT StrAny ;
FROM KeyBase  IMPORT FlushKeyBoard, GetKeyStroke ;
FROM Windows IMPORT RegularAttr, BoldAttr, SpecialAttr,
                    ErrorText, WarningText, InfoText, PromptText, PressText,
                    ErrorWindow,
                    EndWindows;
FROM Translations IMPORT XlateLine, XlateTablePointer, CurrentModeType,
              Int2Scr, Scr2Int, XlateStrAny, InitialXlateData, LenD;
FROM Utils IMPORT Beep, TimeDelay, Status, Terminate, MsDosDate, Exist;
FROM KeyTranslation IMPORT TabType, WriteScreenField;
(*<Debug*)  IMPORT FIO, Lib, SYSTEM ;  (*Debug>*)

(* PutError, PutWarning, PutMessage and AskUser all use the ErrorWindow *)

PROCEDURE WriteText(Label: ARRAY OF CHAR; VAR Text : ARRAY OF CHAR;
                VAR EndX, EndY:  CARDINAL ) ;
CONST
   MaxLineLen = 75 ;
   UnKnownChar = 4C;
(* m.s. TYPE
   TxtPtrType =  POINTER TO StrAny;
*)
VAR
   TextLen  :  CARDINAL ;
   TextPos  :  CARDINAL ;
   TextEnd  :  CARDINAL ;
   ScrnLine :  CARDINAL ;
   IntPos   :  CARDINAL ;
(*m.s.   TxtPtr   :  TxtPtrType; *)
   Txt      : StrAny ; (* m.s. - used instead of pointer *)
   PMax     :  CARDINAL;
   P,AL,IL  :  CARDINAL;
   TempStr  :  StrAny ;
   EnoughData :  BOOLEAN;
   cm:         CurrentModeType;
BEGIN
   TWB.Use(ErrorWindow);
   TWB.Clear;

(* First, write out top corner message "error", "warning" , etc. *)

   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine( Int2Scr, UnKnownChar, Label, cm, TextLen, LenD, PMax,
              EnoughData, TempStr) ;
   TWB.SetPaletteColor(BoldAttr);
   TWB.GotoXY(0,0);
   TWB.WrStr(TempStr);
   TWB.SetPaletteColor(RegularAttr);

  (* Now, write out text of message *)

   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine( Int2Scr, UnKnownChar, Text, cm, TextLen, LenD, PMax,
              EnoughData, TempStr) ;
   P := 0;
   IntPos := 0;
   TextPos := 0 ;
   ScrnLine := 2 ;
(* m.s.   TxtPtr := ADR(Text[IntPos]); *)
   Str.Copy( Txt, Text ) ;
   EndX := TextLen + 1;

   WHILE TextLen > MaxLineLen DO
      (* find apparent position at or Past MaxLineLen *)
      AL := 0;
      IL := 0;
      WHILE AL < MaxLineLen DO
         INC(AL, LenD[P].ApprOut);
         INC(IL, LenD[P].Int);
         INC(P);
      END;
      (* back up to space *)
      WHILE (AL > 40) AND (Text[IL] <> ' ') DO
         DEC(AL, LenD[P].ApprOut);
         DEC(IL, LenD[P].Int);
         DEC(P);
      END;
(* m.s. - instead of using pointer to array potentially different length than 256
      Text[IL] := 0C;
      WriteScreenField( ErrorWindow, 0,1, ScrnLine, TxtPtr^, RegularAttr, FALSE);
      TxtPtr := ADR(Text[IL+1]);
*)
      Txt[IL] := 0C ;
      WriteScreenField( ErrorWindow, 0,1, ScrnLine, Txt, RegularAttr, FALSE);
      Str.Slice( Txt, Text, IL+1, MAX(CARDINAL) );
      DEC(TextLen,AL);
      EndX := TextLen;
      INC(AL, LenD[P].ApprOut);
      INC(IL, LenD[P].Int);
      INC(P);
      INC( ScrnLine ) ;
   END ;  (* while *)
(* m.s.   WriteScreenField( ErrorWindow, 0,1, ScrnLine, TxtPtr^, RegularAttr, FALSE); *)
   WriteScreenField( ErrorWindow, 0,1, ScrnLine, Txt, RegularAttr, FALSE);
   TWB.CursorOn;
   TWB.SetPaletteColor(BoldAttr);
   TWB.PutOnTop(ErrorWindow);
   EndY := ScrnLine;
END WriteText ;

PROCEDURE WaitForAKey;
VAR Ch		: CHAR;
    dummy	: BOOLEAN;
BEGIN
   TWB.SetTitle( ErrorWindow, PressText, TWB.CenterLowerTitle );
   GetKeyStroke(Ch, dummy);                 (* wait for a key        *)
   FlushKeyBoard ;
   TWB.SetTitle( ErrorWindow, '', TWB.CenterLowerTitle );
   TWB.Hide(ErrorWindow);
END WaitForAKey;

PROCEDURE PutError(VAR Text : ARRAY OF CHAR ) ;
VAR dX, dY:   CARDINAL;
    oldw:     TWB.WinType;
BEGIN
   oldw := TWB.Used();
   WriteText(ErrorText, Text, dX, dY);
   WaitForAKey;
   TWB.Use(oldw);
END PutError ;

PROCEDURE PutWarning(VAR Text : ARRAY OF CHAR ) ;
VAR dX, dY:   CARDINAL;
    oldw:     TWB.WinType;
BEGIN
   oldw := TWB.Used();
   WriteText(WarningText, Text, dX, dY);
   WaitForAKey;
   TWB.Use(oldw);
END PutWarning ;

PROCEDURE PutMessage(VAR Text : ARRAY OF CHAR ) ;
VAR dX, dY:   CARDINAL;
    oldw:     TWB.WinType;
BEGIN
   oldw := TWB.Used();
   WriteText(InfoText, Text, dX, dY);
   WaitForAKey;
   TWB.Use(oldw);
END PutMessage ;

PROCEDURE ProgramErrorAndHalt( Text : ARRAY OF CHAR ) ;
VAR
   ErrPos:     CARDINAL;
   ErrorMsg:   StrAny;
   dX, dY:     CARDINAL;
   (*<Debug*)
   ErrorFile:  FIO.File;
   Hrs, Mins, Secs : CARDINAL ;
   month, day, year   : INTEGER;

PROCEDURE GetTime ( VAR Hrs,Mins,Secs : CARDINAL ) ;
VAR
  R : SYSTEM.Registers ;
BEGIN
  WITH R DO
    AH := 2CH ;
    Lib.Dos(R) ;
    Hrs   := CARDINAL(CH) ;
    Mins  := CARDINAL(CL) ;
    Secs  := CARDINAL(DH) ;
  END ;
END GetTime ;
   (*Debug>*)
BEGIN
   ErrPos := 0;
   SWriteString( ErrorMsg, ErrPos, Text, 0 );
   SWriteString( ErrorMsg, ErrPos, '  Program terminating.', 0 );
   WriteText( 'Program Error:',ErrorMsg, dX, dY ) ;
   WaitForAKey;

   (*<Debug*)
   IF Exist( "$$TACT$$.ERR" ) THEN
      ErrorFile := FIO.Append( "$$TACT$$.ERR" ) ;
   ELSE
      ErrorFile := FIO.Create( "$$TACT$$.ERR" ) ;
   END ;
   FIO.WrLn( ErrorFile ) ;
   MsDosDate( month, day, year );
   FIO.WrInt( ErrorFile, day, 0 ) ;
   FIO.WrStr( ErrorFile, "/" ) ;
   FIO.WrInt( ErrorFile, month, 0 ) ;
   FIO.WrStr( ErrorFile, "/" ) ;
   FIO.WrInt( ErrorFile, year, 0 ) ;
   FIO.WrStr( ErrorFile, "  " ) ;

   GetTime( Hrs, Mins, Secs ) ;
   FIO.WrCard( ErrorFile, Hrs, 0 ) ;
   FIO.WrStr( ErrorFile, ":" ) ;
   FIO.WrCard( ErrorFile, Mins, 0 ) ;
   FIO.WrStr( ErrorFile, ":" ) ;
   FIO.WrCard( ErrorFile, Secs, 0 ) ;
   FIO.WrStr( ErrorFile, "  " ) ;

   FIO.WrStr( ErrorFile, ErrorMsg ) ;
   FIO.WrLn( ErrorFile ) ;
   FIO.Close( ErrorFile ) ;
   (*Debug>*)

   (* EndWindows;   <--- this is called by HALT via Terminate(p,c) in RTSMain *)
   HALT ;
END ProgramErrorAndHalt ;

PROCEDURE AskUser( VAR Prompt : ARRAY OF CHAR;
                       Term   : ARRAY OF CHAR;  (* set of terminating characters *)
                   VAR Reply  : CHAR ) ;
VAR
   Ch  :  CHAR ;
   Extended: BOOLEAN;
   OK  :  BOOLEAN;
   EndX, EndY: CARDINAL;
   oldw:     TWB.WinType;
BEGIN
   oldw := TWB.Used();
   WriteText(PromptText, Prompt, EndX, EndY);

   REPEAT
      TWB.GotoXY(EndX,EndY);
      GetKeyStroke(Reply, Extended);
      IF Extended THEN OK := FALSE (* can never be a extended key *)
      ELSE
         Reply := CAP( Reply ) ;
         OK := Str.Pos(Term, Reply) <= HIGH(Term) ;
      END;
      IF NOT OK THEN Beep END ;
   UNTIL OK;
   FlushKeyBoard ;

   TWB.DirectWrite(EndX, EndY, ADR(Reply), 1);
   TimeDelay( 500 ) ;  (* 500 mS *)
   TWB.Hide(ErrorWindow);
   TWB.Use(oldw);
END  AskUser ;

END ErrorBase.