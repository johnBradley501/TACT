IMPLEMENTATION MODULE KeyUtils;

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
(*V2=Trace *)
(*V3=Picture *)

IMPORT ASCII, Str, TWB, PCKey, FIO ;
FROM GlobalDefs IMPORT StrAny, FileNameType;
FROM Utils IMPORT
  (* type *) BFile, RWType, PrintHex,
  (* proc *) BOpen, BClose, BCreate, WriteLine, UpcaseStr, GetEnv, ReadLine,
		Beep, TimeDelay, Status, Terminate, InstallTermProc,
                StandardizeFileName, TrimBlanks, ConstStr;
FROM UtilsTwo IMPORT IOErrorMessage, OK ;
FROM ErrorBase IMPORT PutError, ProgramErrorAndHalt;
FROM SYSTEM IMPORT ADR;
FROM StringIO IMPORT SWriteString, SWriteChar, SWriteCard;
FROM KeyBase  IMPORT ReadKey, FlushKeyBoard, GetKeyStroke, KeyPressed ;
FROM Windows IMPORT RegularAttr, BoldAttr, SpecialAttr, InActiveAttrib,
	ErrorText, WarningText, InfoText, PromptText, PressText,
	ErrorWindow, EndWindows, ChangeColorOnScreen, TerminationProc,
        ResizeMoveKeyRead;
FROM KeyTranslation IMPORT
  (* Type  *) TabInfo,TabType,
  (* vars  *) FieldEditingAttr, FieldNotEditingAttr,
  (* Procs *) GetScreenField, FancyScreenDisplay;
FROM ResActionBar IMPORT
  (* Vars *) ABWindow;
FROM DBData IMPORT
    (* vars  *) TDBFileName, TDBTitle, PDBFileName, PDBOpen;

FROM Translations IMPORT XlateLine, XlateTablePointer, CurrentModeType,
	Int2Scr, Scr2Int, XlateStrAny, InitialXlateData, Int2File, File2Int;
FROM ResMessages IMPORT
   (* proc *) ResAskUser, MsgString, MsgCard, PutResError, GetResMessage;
FROM MemoryManagement (* was Storage *) IMPORT ALLOCATE, DEALLOCATE;
FROM HelpBase IMPORT
  (* procs *) ShowHelpItem, PushHelpItem, PopHelpItem;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, MoveCurrentWindow,
              ResizeCurrentWindow, DummyInit, GetCurrentPointer;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CharField, CardField, CharFieldProc,
                 Switches, SwitchValue, GetFieldInfo, CardFieldProc,
                 MakeMenu, DestroyMenu, ShowFixedText, ShowMenu, DoMenu;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys, ListControlKeys,
  (* procs *) GetPanelControlKey, GetListControlKey;
FROM TACTInit IMPORT
 (* vars  *) ExitList,TermList;
FROM FileNameBase IMPORT
          HandleFileNameField;
(*<Trace FROM Trace IMPORT TWriteString, DoTrace ;  Trace>*)

(*<Picture*)
TYPE
   ScreenData = ARRAY[0..24] OF ARRAY [0..79] OF WORD;
VAR
   GData[0B800H:0H]: ScreenData;
(*Picture>*)


CONST
   SpecialFunctionChar = "!" ;
   DefaultOutputKeysName = "KEYTRACE.DMP";

(*RES OLD MSG 337
The error "%0" occurred opening Script File "%1".
*)
   ErrorOpeningRes = (*RES REM INS*) 337 ;

(*RES OLD MNU 35
                   Playing a Script File
  FileName: %0______________________________________________
           Press ESC to interrupt during playing.
*)
   PlayScriptFileMenuID = (*RES REM INS*) 35 ;

(*RES OLD MNU 37
                   Creating a Script File
  FileName: %0______________________________________________
         Type Alt-F10 to finish the Script File.
    Type Alt-F8 to use special scripting functions.
*)
   LogScriptFileMenuID = (*RES REM INS*) 37 ;

TYPE
   ScriptFileInfo = RECORD
	FileID:    BFile;
	FileName:  ARRAY[0..80] OF CHAR;
	Line:      ARRAY[0..100] OF CHAR;
	LPos:      CARDINAL;
   END;
   ScriptFilePntr = POINTER TO ScriptFileInfo;

   DisplayTextPntr = POINTER TO DisplayText;
   DisplayText = RECORD
      Next:      DisplayTextPntr;
      Prev:      DisplayTextPntr;
      Line:      ARRAY[0..100] OF CHAR;
   END;

VAR
   InFile:    ScriptFilePntr;
   OutFile:   ScriptFilePntr;

   SaveKeyStrokes	: BOOLEAN ;
   ReadKeyTraceFile	: BOOLEAN ;

   SingleStep	: BOOLEAN ;
   delay	: BOOLEAN ;
   DelayTime    : CARDINAL;
   PauseWindowMade : BOOLEAN ;
   PauseWindow	: TWB.WinType ;

   ScrDialogWindow:  WindowInfo;
   SpecScripWindow:  WindowInfo;
   SpecDisplayWindow:WindowInfo;
   SpecialScripOpts: ARRAY[0..2] OF CHAR;
   SpecWT:           TWB.WinType;
   SpecText:         DisplayTextPntr;
   PauseMsg:         ARRAY[0..100] OF CHAR;
   AllowResize:      BOOLEAN;
   LoggedMessage:    ARRAY[0..10] OF CHAR;

(*<Picture*)
   AllowScreenCapture: BOOLEAN;
(*Picture>*)

(* this code is no longer needed   ... jb

PROCEDURE WriteText( Label: ARRAY OF CHAR; VAR Text : ARRAY OF CHAR;
                VAR EndX, EndY:  CARDINAL ) ;
CONST
   MaxLineLen = 75 ;
   UnKnownChar = 4C;
VAR
   TextLen  :  CARDINAL ;
   TextPos  :  CARDINAL ;
   TextEnd  :  CARDINAL ;
   ScrnLine :  CARDINAL ;
   PMax     :  CARDINAL;
   LenD     :  XlateStrAny ;
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
   TextPos  := 0 ;  (* next character to print *)
   ScrnLine := 1 ;

   WHILE TextPos < TextLen DO
      INC( ScrnLine ) ;
      IF (TextLen-TextPos) >= MaxLineLen THEN
         (* simple line fold -- will do for screen monitor *)
         TextEnd := TextPos + MaxLineLen -1;
         WHILE (TextEnd > TextPos) AND (TempStr[TextEnd] <> ' ') DO
            DEC( TextEnd ) ;
         END ;
      ELSE
         TextEnd := TextLen
      END ;
      TWB.DirectWrite(1, ScrnLine, ADR(TempStr[TextPos]),TextEnd-TextPos);
      EndX := TextEnd-TextPos+1;
      TextPos := TextEnd + 1 ;
   END ;  (* while *)

   TWB.CursorOn;
   TWB.SetPaletteColor(BoldAttr);
   TWB.PutOnTop(ErrorWindow);
   EndY := ScrnLine;
END WriteText ;

PROCEDURE AskUser( VAR Prompt : ARRAY OF CHAR;
                       Term   : ARRAY OF CHAR;  (* set of terminating characters *)
                   VAR Reply  : CHAR ) ;
VAR
   Ch  :  CHAR ;
   Extended: BOOLEAN;
   OK  :  BOOLEAN;
   EndX, EndY: CARDINAL;
BEGIN
   WriteText(PromptText, Prompt, EndX, EndY);

   REPEAT
      ReadKey( Reply, Extended ) ;
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
END  AskUser ;

end of code is no longer needed   ... jb  *)

PROCEDURE HandleLoggedMessage( ON:  BOOLEAN );
VAR
   i:     CARDINAL;
   ow:    TWB.WinType;
   temp:  ARRAY[0..10] OF CHAR;

PROCEDURE GetMessage;
VAR
     cm:           CurrentModeType;
     TextLen  :    CARDINAL ;
     PMax     :    CARDINAL;
     LenD     :    XlateStrAny ;
     EnoughData :  BOOLEAN;
BEGIN
   (*RES OLD MSG 349
   REC
   *)
   GetResMessage( (*RES REM INS*) 349 , temp );
   cm.ModeIn := '0';
   cm.ModeOut := '0';
   XlateLine( Int2Scr, '?', temp, cm, TextLen, LenD, PMax,
              EnoughData, LoggedMessage);
END GetMessage;

BEGIN
   IF LoggedMessage[0] = 0C THEN GetMessage END;
   ow := TWB.Used();
   TWB.Use(ABWindow);
   i := 69 - Str.Length(LoggedMessage);
   TWB.GotoXY(i,1);
   IF ON THEN
      TWB.SetPaletteColor(BoldAttr);
      TWB.WrStr( LoggedMessage );
      TWB.SetPaletteColor(RegularAttr);
   ELSE
      TWB.SetPaletteColor(RegularAttr);
      ConstStr(' ',Str.Length(LoggedMessage),temp);
      TWB.WrStr( temp );
   END;
   TWB.Use(ow);
END HandleLoggedMessage;

PROCEDURE DisplaySpecialWindowText;
VAR
   TPtr:   DisplayTextPntr;
   i:      CARDINAL;
   Tabs:   ARRAY[0..0] OF TabInfo;
BEGIN
   Tabs[0].Pos := 8;
   Tabs[0].Type := Left;
   TPtr := SpecText;
   i := 0;
   WHILE TPtr <> NIL DO
      FancyScreenDisplay( SpecWT, 0,i,TPtr^.Line, Tabs,FALSE);
      INC(i);
      TPtr := TPtr^.Next;
   END;
END DisplaySpecialWindowText;

PROCEDURE KWriteLn;
VAR
    Mess2:    ARRAY[0..40] OF CHAR;
    IOResult: CARDINAL;
BEGIN
   WITH OutFile^ DO
     WriteLine(FileID,Line,IOResult);
     IF IOResult <> OK THEN
        IOErrorMessage(IOResult,Mess2);
	(*RES OLD MSG 339
	The error "%0" occurred while writing Script File "%1".
	*)
	MsgString(Mess2,0);
	MsgString(FileName,0);
	PutResError( (*RES REM INS*) 339 );
        BClose(FileID,IOResult);
        SaveKeyStrokes := FALSE ;
        DISPOSE(OutFile);
        OutFile := NIL;
        RETURN
     END;
     LPos := 0;
  END;
END KWriteLn;

PROCEDURE OpenOutputKeysFile(KFileName:     ARRAY OF CHAR;
                             AutoOverwrite: BOOLEAN;
                             ShowLoggedMsg: BOOLEAN) ;
VAR
    Mess2:    ARRAY[0..40] OF CHAR;
    IOResult: CARDINAL;
    ch:       CHAR;
    Append:   BOOLEAN;
    BEGIN
        IF OutFile <> NIL THEN
           (*RES OLD MSG 338
           Script File "%0" cannot be opened. File "%1" is already being written.
           *)
           MsgString(KFileName, 0);
           MsgString(InFile^.FileName, 0);
           PutResError ( (*RES REM INS*) 338 ) ;
           RETURN;
        END;
        Append := FALSE;
        IF (NOT AutoOverwrite) AND FIO.Exists(KFileName) THEN
(*RES OLD CHE 22
The script file named "%0" already exists.  Type "C" to cancel, "O" to
overwrite, or "A" to append to it:
=COA
*)
           MsgString(KFileName, 0);
	   ResAskUser( (*RES REM INS*) 22, 'COA', ch);
           CASE ch OF
	     "C": RETURN
           | "O": (* do nothing *)
	   | "A": Append := TRUE;
           END;
        END;
	NEW(OutFile);
	WITH OutFile^ DO;
           Str.Copy(FileName, KFileName);
           IF Append THEN BOpen(FileID,KFileName,AppendType, IOResult)
           ELSE BCreate(FileID,KFileName,TRUE,IOResult) END;
	   IF IOResult <> OK THEN
	      IOErrorMessage(IOResult,Mess2);
	      MsgString(Mess2,0);
	      MsgString(KFileName, 0);
	      PutResError ( ErrorOpeningRes ) ;
	      DISPOSE(OutFile);
              RETURN ;
           END;
           SaveKeyStrokes := TRUE ;
	   LPos := 0;
	   Line[0] := 0C;
	   SWriteString(Line,LPos,'!! ',0);
           IF PDBOpen THEN
	      SWriteString(Line,LPos,'GIX: ',0);
	      SWriteString(Line,LPos,PDBFileName,0);
	      SWriteString(Line,LPos,', ',0);
           END;
	   SWriteString(Line,LPos,'TDB: ',0);
	   SWriteString(Line,LPos,TDBFileName,0);
           KWriteLn;
        END;
        IF ShowLoggedMsg THEN HandleLoggedMessage( (* ON := *) TRUE ) END;
    END OpenOutputKeysFile ;

PROCEDURE CloseOutputKeysFile;
VAR
    IOResult: CARDINAL;
BEGIN
   IF OutFile = NIL THEN RETURN END;
   WITH OutFile^ DO
      IF LPos <> 0 THEN KWriteLn END;
      BClose(FileID,IOResult);
   END;
   SaveKeyStrokes := FALSE ;
   DISPOSE(OutFile);
   OutFile := NIL;
   HandleLoggedMessage( (* ON := *) FALSE );
END CloseOutputKeysFile;

PROCEDURE OpenInputKeysFile(KFileName: ARRAY OF CHAR);
VAR
    Mess2:    ARRAY[0..40] OF CHAR;
    IOResult: CARDINAL;
BEGIN
   IF InFile <> NIL THEN
      (*RES OLD MSG 340
      Script File "%0" cannot be opened. File "%1" is already being read.
      *)
      MsgString(KFileName, 0);
      MsgString(InFile^.FileName, 0);
      PutResError ( (*RES REM INS*) 340 ) ;
      ReadKeyTraceFile := FALSE;
      RETURN;
   END;
   NEW(InFile);
   WITH InFile^ DO
      Str.Copy(FileName, KFileName);
      BOpen( FileID, KFileName, ReadType, IOResult ) ;
      IF IOResult <> OK THEN
         IOErrorMessage(IOResult,Mess2);
         MsgString(Mess2,0);
         MsgString(KFileName, 0);
         PutResError ( ErrorOpeningRes ) ;
	 DISPOSE(InFile);
         ReadKeyTraceFile := FALSE;
      ELSE
         ReadKeyTraceFile := TRUE ;
         Line[0] := 0C ;
         LPos := 0 ;
         ReadKeyTraceFile := TRUE;
      END;
   END;
END OpenInputKeysFile;

PROCEDURE CloseInputKeysFile;
VAR
    IOResult: CARDINAL;
BEGIN
   IF InFile = NIL THEN RETURN END;
   BClose(InFile^.FileID,IOResult);
   ReadKeyTraceFile := FALSE ;
   DISPOSE(InFile);
   InFile := NIL;
END CloseInputKeysFile;

PROCEDURE SetupDefaultKeyUtilSettings ;
    VAR
	St : StrAny ;
    BEGIN
	GetEnv( 'SAVEKEYS', St) ;
	UpcaseStr( St, St ) ;
	SaveKeyStrokes := Str.Compare( St, 'YES' ) = 0 ;
	IF SaveKeyStrokes THEN
	   OpenOutputKeysFile(DefaultOutputKeysName, 
                              (*AutoOverwrite = *) TRUE,
                              (*ShowLoggedMsg = *) FALSE);
	END ;
	GetEnv( 'KEYTRACE', St) ;
	IF St[0] <> 0C THEN
	   UpcaseStr( St, St ) ;
           OpenInputKeysFile(St);
	END ;
        (*RES OLD MSG 348
	Press F10 to Exit UseBase, ESC to stop the Script, or any other key to continue.
        *)
        GetResMessage( (*RES REM INS*) 348 , PauseMsg );
        
(*<Picture*)
	GetEnv( 'SCRCAP', St) ;
	UpcaseStr( St, St );
        AllowScreenCapture := Str.Compare (St, 'YES' ) = 0 ;
(*Picture>*)
    END SetupDefaultKeyUtilSettings ;

PROCEDURE WriteKeysToFile( Ext : BOOLEAN; Ch : CHAR ) ;
    VAR
	Str	: ARRAY[0..4] OF CHAR;
    BEGIN
	WITH OutFile^ DO
	   IF Ext THEN  SWriteString(Line,LPos,'00',0)  END ;
	   PrintHex(Ch,Str);
	   (*<Trace
	   IF DoTrace THEN
	      IF Ext THEN  TWriteString( '00' )  END ;
	      TWriteString( Str ) ;
	   END ;
	   Trace>*)
	   SWriteString(Line,LPos,Str,0);
(*	   IF LPos MOD 20 = 0 THEN
	      SWriteChar( Line, LPos, ' ', 0 )
	   END ; *)
	   IF LPos >= 72 THEN
	      KWriteLn ;
	   END ;
	END;
    END WriteKeysToFile ;

PROCEDURE ReadKeysFromFile( VAR Ext : BOOLEAN; VAR Ch : CHAR ) ;
   VAR
	dummy	: BOOLEAN ;
	Done	: BOOLEAN ;
	Reply	: CHAR ;
        tCh     : CHAR ;
        tExt    : BOOLEAN ;

    PROCEDURE IsHex( ch : CHAR ) : BOOLEAN ;
	BEGIN
	   IF ( ('0' <= ch) AND (ch <= '9') ) OR ( ('A' <= ch) AND (ch <= 'F') ) THEN
		RETURN TRUE
	   ELSE
		RETURN FALSE
	   END ;
	END IsHex ;

    PROCEDURE GetHexChar( VAR ch : CHAR ) : BOOLEAN ;
	VAR
	   ch1	: CHAR;
	   ch2	: CHAR;
	BEGIN
	   WITH InFile^ DO
	      IF IsHex( Line[LPos] ) THEN
                 ch1 := Line[LPos] ;
                 INC( LPos ) ;
                 IF IsHex( Line[LPos] ) THEN
                    ch2 := Line[LPos] ;
                    INC( LPos ) ;	
                    IF ch1 >= 'A' THEN Ch := CHAR( (ORD(ch1) - 55) * 16 )
                    ELSE Ch := CHAR( (ORD(ch1) - 48) * 16 ) END ;
                    IF ch2 >= 'A' THEN Ch := CHAR( ORD(Ch) + ORD(ch2) - 55)
                    ELSE Ch := CHAR( ORD(Ch) + ORD(ch2) - 48) END ;
                    RETURN TRUE
                 END;
	      END ;
	   END ;
	   Ch := '?' ;
	   Ext := FALSE ;
	   RETURN FALSE ;
	END GetHexChar ;

(*RES REM DEL CHE 23 *)
(*
    PROCEDURE DoCheck ;
	VAR OldSKS:    BOOLEAN;
	BEGIN
                (*RES OLD CHE 23
                = S C F
                Script File Running Options: S)ingle step,
                C)ontinue, F)inish using file:
                *)

		OldSKS := SaveKeyStrokes;
		SaveKeyStrokes := FALSE ;
                ReadKeyTraceFile := FALSE;
	        ResAskUser( (*RES REM INS*) 23 , 'SCF', Reply);
                ReadKeyTraceFile := TRUE;
		SaveKeyStrokes := OldSKS ;

		IF Reply = 'F' THEN
		   CloseInputKeysFile;
                   RETURN
		ELSIF Reply = 'S' THEN
		   SingleStep := TRUE ;
		ELSIF Reply = 'C' THEN
		   SingleStep := FALSE;
		(* else ignore it *)
		END ;
	END DoCheck ;
*)

PROCEDURE HandleImproperScript;
BEGIN
   (*RES OLD MSG 341
   Your input Script File "%0" contains an Invalid Character "%1".
   *)
   WITH InFile^ DO
      MsgString(FileName,0);
      MsgString(Line[LPos],0);
   END;
   PutResError( (*RES REM INS*) 341 );
   CloseInputKeysFile;
   ReadKey(Ch, Ext);
   Done := TRUE;
END HandleImproperScript;

PROCEDURE GetNumber(VAR Rslt:  CARDINAL): BOOLEAN;
VAR i: CARDINAL;
BEGIN
   WITH InFile^ DO;
      i := 0;
      WHILE Line[LPos] = ' ' DO INC(LPos) END;
      IF Line[LPos] = 0C THEN RETURN FALSE END;
      WHILE (Line[LPos] <> ' ') AND (Line[LPos] <> 0C) DO
         IF (Line[LPos] <'0') OR (Line[LPos] > '9') THEN RETURN FALSE END;
         i := i * 10 + ORD(Line[LPos]) - ORD('0');
         INC(LPos);
      END;
      WHILE Line[LPos] = ' ' DO INC(LPos) END;
   END;
   Rslt := i;
   RETURN TRUE;
END GetNumber;

PROCEDURE ShowPauseWind ;
    VAR
	WD : TWB.WinDef;
	ow : TWB.WinType;
	Extended : BOOLEAN ;
	Reply	 : CHAR ;
        PauseLen : CARDINAL;
        PauseXPos: CARDINAL;
	pos:       CARDINAL;
    BEGIN
        PauseLen := Str.Length(PauseMsg);
        PauseXPos := (80 - PauseLen) DIV 2;
	ow := TWB.Used();
	IF NOT PauseWindowMade THEN
	   PauseWindowMade := TRUE;
	   WITH WD DO
		X1 := 0;
		Y1 := 24;
		X2 := 80;
		Y2 := 24;
		CursorOn := FALSE;
		WrapOn := FALSE;
		Hidden := FALSE;
		FrameOn := FALSE;
	   END;
	   PauseWindow := TWB.PaletteOpen(WD, InActiveAttrib);
	   (* need to write message once in window *)
	   TWB.Use(PauseWindow);

	   TWB.Clear;
	   TWB.SetPaletteColor( BoldAttr );

	   TWB.GotoXY( PauseXPos, 0 );
	   TWB.WrStr( PauseMsg );
	END;

	TWB.PutOnTop(PauseWindow);
	pos := SpecialAttr;
(*	pos := PauseXPos; *)
	WHILE NOT KeyPressed() DO

	   (* well, I liked this, anyway .... john b
	   TWB.ChangeColorOnScreen(SpecialAttr, pos, 0,5);
	   TimeDelay( 100 ) ;  (* 100 mS *)
	   TWB.ChangeColorOnScreen(BoldAttr, pos, 0,5);
	   INC(pos);
	   IF pos > PauseXPos + PauseLen-6 THEN pos := PauseXPos END;
	   *)

	   TimeDelay( 500 ) ;  (* 500 mS *)
	   ChangeColorOnScreen( pos, PauseXPos,0, PauseLen);
	   IF pos = BoldAttr THEN pos := SpecialAttr
	   ELSE pos := BoldAttr END;
	END;
	ReadKey( Reply, Extended ) ;
	IF Extended AND (Reply = PCKey.F10) THEN
	   TerminationProc ;
        ELSIF (NOT Extended) AND (Reply = ASCII.esc) THEN
           CloseInputKeysFile;
	ELSIF (Extended) AND (Reply=PCKey.CtrlF10) THEN  (* m.s. was Alt *)
	   SingleStep := TRUE ;
	ELSE
	   SingleStep := FALSE;
	END ;

	TWB.Hide(PauseWindow);
	TWB.Use(ow);
	TimeDelay( 100 ) ;  (* 100 mS *)
    END ShowPauseWind;

PROCEDURE HandleDelayCode;
VAR temp:  CARDINAL;
BEGIN
  INC(InFile^.LPos);
  IF NOT GetNumber(temp) THEN
     HandleImproperScript;
     RETURN
  END;
  IF temp <> 0 THEN
      delay := TRUE;
      DelayTime := temp;
  ELSE delay := FALSE
  END;
END HandleDelayCode;

PROCEDURE ReadNewInputLine(): BOOLEAN;
VAR
   ED      : BOOLEAN ;
   IOResult: CARDINAL;
BEGIN
   WITH InFile^ DO
      IF NOT ReadLine(FileID, Line, ED, IOResult ) THEN
         (* IF IOResult <> OK THEN *)
         CloseInputKeysFile;
         delay := FALSE;
         RETURN FALSE
      END ;
      LPos := 0 ;
      RETURN TRUE;
   END;
END ReadNewInputLine;

PROCEDURE HandleWindowCode;
VAR
     Finished:     BOOLEAN;
     cm:           CurrentModeType;
     TextLen  :    CARDINAL ;
     PMax     :    CARDINAL;
     LenD     :    XlateStrAny ;
     EnoughData :  BOOLEAN;
     i:            CARDINAL;
     WorkLine:     ARRAY[0..80] OF CHAR;
     Tabs:         ARRAY[0..0] OF TabInfo;
     ch:           CHAR;
     Ext:          BOOLEAN;
     OldWind:      TWB.WinType;
BEGIN
   INC(InFile^.LPos);
   WITH SpecDisplayWindow DO
      IF NOT GetNumber(XPos) THEN HandleImproperScript;  RETURN END;
      IF NOT GetNumber(YPos) THEN HandleImproperScript;  RETURN END;
      IF NOT GetNumber(XSize) THEN HandleImproperScript;  RETURN END;
      IF NOT GetNumber(YSize) THEN HandleImproperScript;  RETURN END;
   END;
   cm.ModeIn := '0';
   cm.ModeOut := '0';
   Tabs[0].Pos := 8;
   Tabs[0].Type := Left;
   OldWind := TWB.Used();
   PushNewWindow(SpecDisplayWindow, SpecWT, DisplaySpecialWindowText);
   i := 0;
   REPEAT
      IF ReadNewInputLine() THEN
         SpecText := NIL;
         WITH InFile^ DO
            Finished := Line[0] <> '|';
            IF NOT Finished THEN
               Str.Delete(Line,0,1);
               XlateLine( File2Int, '?', Line, cm, TextLen, LenD, PMax,
                 EnoughData, WorkLine) ;
               FancyScreenDisplay( SpecWT, 0,i,WorkLine, Tabs,FALSE);
            END;
         END;
      ELSE
         ProgramErrorAndHalt('Error in HandleWindowCode');
      END;
      INC(i);
   UNTIL Finished;

   INC(InFile^.LPos);
   ShowPauseWind ;
   PopWindow;
   TWB.Use(OldWind);
END HandleWindowCode;

    BEGIN (* ReadKeysFromFile *)
      IF KeyPressed() THEN
         ReadKey(tCh, tExt);
         IF (NOT tExt) AND (tCh = ASCII.esc) THEN ShowPauseWind
         ELSE FlushKeyBoard END;
      END;
      IF SingleStep THEN  ShowPauseWind  END ;
      IF delay THEN  TimeDelay( DelayTime )  END ;
      Done := FALSE ;
      IF InFile = NIL THEN (* j.b. added 3/29/91 *)
         ReadKey(Ch, Ext);
         RETURN
      END;
      WITH InFile^ DO
	REPEAT
	   IF NOT ReadKeyTraceFile THEN
              ReadKey(Ch, Ext);
              RETURN
	   ELSIF Line[LPos] = 0C THEN
                IF NOT ReadNewInputLine() THEN 
                   ReadKey(Ch, Ext);
                   RETURN
                END;
	   ELSIF Line[LPos] = ' ' THEN  (* ignore blanks *)
		INC( LPos ) ;
	   ELSIF GetHexChar( Ch ) THEN
		IF Ch = 0C THEN
		   dummy := GetHexChar( Ch ) ;
		   Ext := TRUE;
		ELSE
		   Ext := FALSE
		END ;
		Done := TRUE ;
	   ELSIF Line[LPos] = SpecialFunctionChar THEN
		INC( LPos ) ;
                CASE Line[LPos] OF
                  'P':
                     ShowPauseWind;
                     INC(LPos);
                | 'D':
                     HandleDelayCode;
                | 'W':
                     HandleWindowCode;
                | '!':
                     Line[LPos] := 0C (* to ignore rest of line *)
                ELSE HandleImproperScript;
                END;
	   ELSIF Line[LPos] = '?' THEN
		INC( LPos ) ;
		ShowPauseWind ;
	   ELSIF Line[LPos] = '#' THEN
		INC( LPos ) ;
		delay := NOT delay ;
		DelayTime := 2000;
	   ELSE
                HandleImproperScript;
	   END ;
	UNTIL Done ;
      END;
    END ReadKeysFromFile ;

PROCEDURE CloseKeysFile ;
    BEGIN
        CloseOutputKeysFile;
	CloseInputKeysFile;
    END CloseKeysFile ;

PROCEDURE ScriptFileNameVerify(Data: ADDRESS;
                           VAR ReDisplay: BOOLEAN;
                           VAR ReEdit:    BOOLEAN);
TYPE
   FileNamePntr = POINTER TO FileNameType;
VAR
  Dtx: FileNamePntr;
BEGIN
  Dtx := FileNamePntr(Data);
  HandleFileNameField(Dtx^,ScriptFileExtension,ReDisplay,ReEdit);
  IF NOT StandardizeFileName(Dtx^,ScriptFileExtension) THEN
      MsgString(Dtx^,0);
      PutResError( ScriptBadFileNameRes );
      ReDisplay := TRUE;
      ReEdit := TRUE;
  END;
END ScriptFileNameVerify;

PROCEDURE HandleScriptMenu(VAR FileName: FileNameType;
                               MID:      CARDINAL): BOOLEAN;
VAR
   Menu:             MenuID;
   L:                CARDINAL;
   w:                TWB.WinType;
   return:           BOOLEAN;
   ch:               CHAR;
   FunctKey:         BOOLEAN;

BEGIN
   FileName[0] := 0C;
   StartMenu(FileName);
   CharFieldProc(FileName, ScriptFileNameVerify);
   MakeMenu( MID,Menu );

   PushNewWindow(ScrDialogWindow,w, DummyInit);
   ShowFixedText(w, Menu, 0,0);
   ShowMenu(w,Menu,0,0,FileName);

   PushHelpItem(44);
   DoMenu(w, Menu,0,0,TermList,ExitList,FileName,L,ch,FunctKey);
   PopHelpItem;

   PopWindow;
   DestroyMenu(Menu);

   RETURN PanelCancel <> GetPanelControlKey(FunctKey, ch);
END HandleScriptMenu;

PROCEDURE OpenInputScriptFile;
VAR KFileName: FileNameType;
BEGIN
   IF InFile <> NIL THEN
      (*RES OLD MSG 342
      UseBase is already reading Script File "%0".
      *)
      MsgString(InFile^.FileName, 0);
      PutResError( (*RES REM INS*) 342 );
      RETURN;
   END;

   IF NOT HandleScriptMenu(KFileName,PlayScriptFileMenuID) THEN RETURN END;
   OpenInputKeysFile(KFileName);
END OpenInputScriptFile;

PROCEDURE OpenOutputScriptFile;
VAR KFileName: FileNameType;
BEGIN
   IF OutFile <> NIL THEN
      (*RES OLD MSG 343
      UseBase is already writing Script File "%0".  Type Alt-F10 to
      finish it first.
      *)
      MsgString(OutFile^.FileName, 0);
      PutResError( (*RES REM INS*) 343 );
      RETURN;
   END;

   IF NOT HandleScriptMenu(KFileName,LogScriptFileMenuID) THEN RETURN END;
   OpenOutputKeysFile(KFileName,
                     (*AutoOverwrite = *) FALSE,
                     (*ShowLoggedMsg = *) TRUE);
END OpenOutputScriptFile;

PROCEDURE VerifyDelayTime(Data: ADDRESS;
                           VAR ReDisplay: BOOLEAN;
                           VAR ReEdit:    BOOLEAN);
TYPE
   CardinalPntr = POINTER TO CARDINAL;
VAR
   Dtx:  CardinalPntr;
BEGIN
   ReDisplay := FALSE;
   ReEdit := FALSE;
   Dtx := CardinalPntr(Data);
   IF Dtx^ > 10000 THEN
      (*RES OLD MSG 345
      Delay Time of %0 Milliseconds is more than 10 Seconds.
      *)
      MsgCard(Dtx^,0);
      PutResError( (*RES REM INS*) 345 );
      Dtx^ := 10000;
      ReDisplay := TRUE;
      ReEdit := TRUE;
   ELSIF (Dtx^ <> 0) AND (Dtx^ < 100) THEN
      (*RES OLD MSG 346
      Delay Time of %0 Milliseconds is less than 0.1 Seconds.
      *)
      MsgCard(Dtx^,0);
      PutResError( (*RES REM INS*) 346 );
      Dtx^ := 100;
      ReDisplay := TRUE;
      ReEdit := TRUE;
   END;
END VerifyDelayTime;

PROCEDURE BaseKeyRead( VAR ch : CHAR; VAR Ext : BOOLEAN ) ;

VAR Done:   BOOLEAN;

(*<Picture*)

PROCEDURE CaptureScreen;
CONST
   FileName = 'TACT.SNP';
VAR
   F:                FIO.File;
BEGIN
   IF FIO.Exists(FileName) THEN F := FIO.Append(FileName)
                           ELSE F := FIO.Create(FileName) END;
   FIO.WrBin(F,GData,SIZE(GData));
   FIO.Close(F);
END CaptureScreen;

(*Picture>*)

PROCEDURE HandleSpecialScriptInstruction;
CONST
(*RES OLD MNU 36
 Script Instruction:

   Pause
   Delay %0____ ms
   Window
*)
   SpecScripMenuID = (*RES REM INS*) 36 ;

VAR
   Menu:             MenuID;
   L:                CARDINAL;
   w:                TWB.WinType;
   ch:               CHAR;
   Ext:              BOOLEAN;
   Done:             BOOLEAN;
   dummy:            BOOLEAN;
   OldWind:          TWB.WinType;

PROCEDURE InsertDelayCode;
BEGIN
   ShowMenu(w,Menu,0,0,DelayTime);
   L := 0;
   DoMenu(w, Menu,0,0,TermList,ExitList,DelayTime,L,ch,Ext);
   IF PanelCancel = GetPanelControlKey(Ext, ch) THEN RETURN END;

   WITH OutFile^ DO
      SWriteChar( Line, LPos, SpecialFunctionChar,0);
      SWriteString( Line, LPos, 'D ',0);
      SWriteCard( Line, LPos, DelayTime, 0);
      SWriteChar( Line, LPos, ' ',0);
   END;
END InsertDelayCode;

PROCEDURE CreateSpecialWindow;
VAR
   ExtExitCodes: ARRAY[0..4] OF CHAR;
   line:         CARDINAL;
   TPtr:         DisplayTextPntr;
   TPtr2:        DisplayTextPntr;
   ch:           CHAR;
   Ext:          BOOLEAN;
   GetDone:      BOOLEAN;

PROCEDURE WriteOutWindowInfo;
VAR  i,LastLine:   CARDINAL;
     WorkLine:     ARRAY[0..80] OF CHAR;
     cm:           CurrentModeType;
     TextLen  :    CARDINAL ;
     PMax     :    CARDINAL;
     LenD     :    XlateStrAny ;
     EnoughData :  BOOLEAN;
BEGIN
   TPtr := SpecText;
   i := 0;
   REPEAT
      TrimBlanks(TPtr^.Line, TPtr^.Line);
      IF TPtr^.Line[0] <> 0C THEN LastLine := i END;
      INC(i);
      TPtr := TPtr^.Next;
   UNTIL TPtr = NIL;
   WITH OutFile^ DO
      IF LPos <> 0 THEN KWriteLn END;

      SWriteChar( Line, LPos, SpecialFunctionChar,0);
      SWriteString( Line, LPos, 'W ',0);
      SWriteCard( Line, LPos, SpecDisplayWindow.XPos, 0);
      SWriteChar( Line, LPos, ' ',0);
      SWriteCard( Line, LPos, SpecDisplayWindow.YPos, 0);
      SWriteChar( Line, LPos, ' ',0);
      SWriteCard( Line, LPos, SpecDisplayWindow.XSize, 0);
      SWriteChar( Line, LPos, ' ',0);
      SWriteCard( Line, LPos, SpecDisplayWindow.YSize, 0);
      SWriteChar( Line, LPos, ' ',0);
      KWriteLn;
   END;
   TPtr := SpecText;
   cm.ModeIn := '0';
   cm.ModeOut := '0';

   FOR i := 0 TO LastLine DO
      XlateLine( Int2File, '?', TPtr^.Line, cm, TextLen, LenD, PMax,
              EnoughData, WorkLine) ;
      WITH OutFile^ DO
        SWriteChar( Line, LPos, '|',0);
        SWriteString( Line, LPos, WorkLine,0);
        KWriteLn;
      END;
      TPtr := TPtr^.Next;
   END;

  OutFile^.Line[0] := '.';
  OutFile^.Line[1] := 0C;
  INC(OutFile^.LPos);
  TPtr := SpecText;
  WHILE TPtr <> NIL DO
     TPtr2 := TPtr^.Next;
     DISPOSE(TPtr);
     TPtr := TPtr2;
  END;
END WriteOutWindowInfo;

BEGIN
   ExtExitCodes[0] := PCKey.CursorUp;
   ExtExitCodes[1] := PCKey.CursorDn;
   ExtExitCodes[2] := PCKey.Home;
   ExtExitCodes[3] := PCKey.End;
   ExtExitCodes[4] := PCKey.AltF5;
   PushNewWindow(SpecDisplayWindow, SpecWT, DisplaySpecialWindowText);
   line := 0;
   NEW(SpecText);
   WITH SpecText^ DO
      Next := NIL;
      Prev := NIL;
      Line[0] := 0C;
   END;
   TPtr := SpecText;
   AllowResize := FALSE;
   PushHelpItem(46);

   FieldEditingAttr := RegularAttr;
   FieldNotEditingAttr := RegularAttr;

   LOOP
      REPEAT
         GetDone := TRUE;
         GetScreenField( SpecWT, SpecDisplayWindow.XSize-1, 0,line,
                         TermList, ExtExitCodes, TPtr^.Line, ch, Ext);
         IF Ext AND (ch = PCKey.AltF5) THEN
            REPEAT
               IF NOT ResizeCurrentWindow(Ext,ch) THEN
                  Ext := FALSE; ch := ASCII.rs;
               END;
            UNTIL (NOT Ext) OR (ch <> PCKey.AltF5);
            GetDone := FALSE;
         END;
      UNTIL GetDone;

      CASE GetListControlKey(Ext, ch) OF
        PrevItem:
          IF line = 0 THEN Beep
          ELSE
             DEC(line);
             TPtr := TPtr^.Prev;
          END;
      | NextItem:
          IF line >= SpecDisplayWindow.YSize-1 THEN Beep
          ELSE
             INC(line);
             IF TPtr^.Next = NIL THEN
                NEW(TPtr2);
                TPtr^.Next := TPtr2;
                WITH TPtr2^ DO
                   Prev := TPtr;
                   Next := NIL;
                   Line[0] := 0C;
                END;
             END;
             TPtr := TPtr^.Next;
          END;
      | FirstItem:
          line := 0;
          TPtr := SpecText;
      | LastItem:
          WHILE TPtr^.Next <> NIL DO
             INC(line);
             TPtr := TPtr^.Next;
          END;
      | ListEnd:
          WriteOutWindowInfo;
          PopHelpItem;
          PopWindow;
          AllowResize := TRUE;
	  FieldEditingAttr := SpecialAttr;
	  FieldNotEditingAttr := BoldAttr;
          RETURN;
      | ListCancel:
          PopWindow;
          PopHelpItem;
          AllowResize := TRUE;
	  FieldEditingAttr := SpecialAttr;
	  FieldNotEditingAttr := BoldAttr;
          RETURN;
      ELSE Beep
      END;
   END;
END CreateSpecialWindow;

BEGIN
   IF SpecialScripOpts[0] = 0C THEN
      (*RES OLD MSG 347
      PDW
      *)
      GetResMessage( (*RES REM INS*) 347 , SpecialScripOpts );
   END;
   StartMenu(DelayTime);
   CardFieldProc(DelayTime, VerifyDelayTime);
   MakeMenu( SpecScripMenuID,Menu );

   OldWind := TWB.Used();
   PushNewWindow(SpecScripWindow,w, DummyInit);
   ShowFixedText(w, Menu, 0,0);
   SaveKeyStrokes := FALSE; (* temporarily *)
   REPEAT
      PushHelpItem(45);
      ReadKey(ch, Ext);
      ch := CAP(ch);
      Done := TRUE;
      IF Ext THEN
         IF ch = PCKey.F10 THEN TerminationProc
         ELSIF ch = PCKey.F1 THEN
             dummy := ShowHelpItem(TermList,0C,ch,Ext);
         ELSE Beep
         END;
         Done := FALSE;
      ELSE
   	 IF ch = ASCII.esc THEN (* do nothing *)
         ELSIF ch = SpecialScripOpts[0] THEN (* do pause insert *)
	    WITH OutFile^ DO
	       SWriteChar( Line, LPos, SpecialFunctionChar,0);
	       SWriteChar( Line, LPos, 'P',0);
	    END;
         ELSIF ch = SpecialScripOpts[1] THEN (* do delay set *)
	    InsertDelayCode;
         ELSIF ch = SpecialScripOpts[2] THEN (* do window create *)
            PopWindow;
            PopHelpItem;
            DestroyMenu(Menu);
	    CreateSpecialWindow;
            SaveKeyStrokes := TRUE;
            TWB.Use(OldWind);
            RETURN
         ELSE
            Beep;
            Done := FALSE;
         END;
      END;
   UNTIL Done;

   PopWindow;
   PopHelpItem;
   TWB.Use(OldWind);
   DestroyMenu(Menu);
   SaveKeyStrokes := TRUE;
END HandleSpecialScriptInstruction;


   BEGIN
     REPEAT
        Done := TRUE;
	IF ReadKeyTraceFile THEN
	    ReadKeysFromFile( Ext, ch )
	ELSE
	    ReadKey(ch, Ext);
	END ;
	IF SaveKeyStrokes THEN
           IF (Ext) AND (ch = PCKey.AltF10) THEN
              CloseOutputKeysFile;
              Done := FALSE;
           ELSIF (Ext) AND (ch = PCKey.AltF8) THEN
              IF ReadKeyTraceFile THEN Beep
	      ELSE HandleSpecialScriptInstruction END;
              Done := FALSE;
	   ELSE WriteKeysToFile( Ext, ch ) END;
	END ;
(*<Picture*)
        IF (AllowScreenCapture) AND (Ext) AND (ch = PCKey.AltF9) THEN
	   CaptureScreen;
           Done := FALSE;
	END;
(*Picture>*)
     UNTIL Done;
   END BaseKeyRead ;

PROCEDURE ReadTheKeyStrokes(VAR ch: CHAR; VAR Ext: BOOLEAN);
VAR Done:   BOOLEAN;
    DoRead: BOOLEAN;
    reply:  CHAR ;
    oldw:    TWB.WinType;

BEGIN
   Done := FALSE;
   DoRead := TRUE;
   REPEAT
      IF DoRead THEN
	 BaseKeyRead( ch, Ext ) ;
      END ;
      IF Ext THEN
         CASE ch OF
           PCKey.F10:
(*RES OLD CHE 15
Do you wish to stop UseBase immediately? Y)es or N)o:
=YN
*)
                oldw := TWB.Used();
		ResAskUser( (*RES REM INS*) 15, 'YN', reply);
                TWB.Use(oldw);
		IF reply = 'Y' THEN  TerminationProc  END ;
         | PCKey.F1:
                oldw := TWB.Used() ;
                DoRead := ShowHelpItem(TermList,ExitList,ch,Ext);
                TWB.PutOnTop( oldw ) ;
         | PCKey.AltF5:
                IF AllowResize THEN (* false only within this module j.b. *)
                   IF ResizeCurrentWindow(Ext,ch) THEN
                      DoRead := (NOT Ext) AND
                                ((ch = ASCII.esc) OR (ch = ASCII.rs));
                   ELSE
                      DoRead := TRUE;
                   END
                ELSE
                   Done := TRUE;
                END;
         | PCKey.AltF6:
		DoRead := NOT MoveCurrentWindow(Ext,ch) ;
         ELSE  Done := TRUE  END;
      ELSE
         Done := TRUE
      END;
   UNTIL Done;
END ReadTheKeyStrokes;

BEGIN
   ReadKeyTraceFile := FALSE;
   SingleStep := FALSE ;
   delay := FALSE ;
   SaveKeyStrokes := FALSE ;
   PauseWindowMade := FALSE ;
   InstallTermProc(CloseKeysFile);
   InFile := NIL;
   OutFile := NIL;
   ResizeMoveKeyRead := BaseKeyRead ;
   GetKeyStroke := ReadTheKeyStrokes;

   WITH SpecScripWindow DO
       XPos := 30;
       YPos := 4;
       YSize := 6;
       XSize := 21;
       MxYSize := 3;
       Type := Dialog;
       AllowMove := TRUE;
       AllowResize := FALSE;
   END;
   WITH ScrDialogWindow DO
       XPos := 11;
       YPos := 4;
       YSize := 4;
       XSize := 62;
       MxYSize := 3;
       Type := Dialog;
       AllowMove := TRUE;
       AllowResize := FALSE;
   END;
   WITH SpecDisplayWindow DO
       XPos := 30;
       YPos := 4;
       XSize := 20;
       YSize := 5;
       MxYSize := 22;
       Type := Message;
       AllowMove := TRUE;
       AllowResize := TRUE;
   END;
   DelayTime := 0;
   SpecialScripOpts[0] := 0C;
   PauseMsg[0] := 0C;
   AllowResize := TRUE;
   LoggedMessage := 0C;
   (*<Picture*)  AllowScreenCapture := FALSE; (*Picture>*)
END KeyUtils.
