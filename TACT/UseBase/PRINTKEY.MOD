MODULE PrintKeys ;

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

IMPORT IO, Str;
FROM FIO IMPORT EOF, File, Open, Create, Close, IOresult, RdStr, WrStr, WrLn ;
FROM Lib IMPORT ParamCount, ParamStr ;
FROM StringIO IMPORT SWriteString, SWriteChar, SWriteCard;

VAR
   MPos		: CARDINAL;
   Message	: ARRAY[0..132] OF CHAR;
   KeyLine	: ARRAY[0..132] OF CHAR;
   KeyPos	: CARDINAL ;
   KeyFileName	: ARRAY[0..64] OF CHAR;
   KeyFile	: File;
   ListFileName	: ARRAY[0..64] OF CHAR;
   ListFile	: File;
   ListLine	: ARRAY[0..132] OF CHAR;
   ListPos	: CARDINAL ;
   LineRead	: CARDINAL ;
   ReadKeyTraceFile : BOOLEAN ;
   Ext		: BOOLEAN ;
   Ch		: CHAR ;
   KeyName	: ARRAY[0C..377C] OF ARRAY[0..20] OF CHAR ;
   TempStr		: ARRAY[0..12] OF CHAR ;

PROCEDURE SetPCKeyNames ;
   VAR  I : CHAR ;
   BEGIN
        FOR I := 0C TO 377C DO	(* set default names *)
	   MPos := 0 ;
	   SWriteString( KeyName[I], MPos, 'Alt-',0);
	   SWriteCard( KeyName[I], MPos, ORD(I), 0 ) ;
        END ;

	KeyName[ 3C ] := 'Nul'; 	
	KeyName[ 17C ] := 'Tab'; 	 (* really Shift-Tab *)

	KeyName[ 036C ] := 'AltA'; 	 (* 00H 1EH *)
	KeyName[ 060C ] := 'AltB'; 	 (* 00H 30H *)
	KeyName[ 056C ] := 'AltC'; 	 (* 00H 2EH *)
	KeyName[ 040C ] := 'AltD'; 	 (* 00H 20H *)
	KeyName[ 022C ] := 'AltE'; 	 (* 00H 12H *)
	KeyName[ 041C ] := 'AltF'; 	 (* 00H 21H *)
	KeyName[ 042C ] := 'AltG'; 	 (* 00H 22H *)
	KeyName[ 043C ] := 'AltH'; 	 (* 00H 23H *)
	KeyName[ 027C ] := 'AltI'; 	 (* 00H 17H *)
	KeyName[ 044C ] := 'AltJ'; 	 (* 00H 24H *)
	KeyName[ 045C ] := 'AltK'; 	 (* 00H 25H *)
	KeyName[ 046C ] := 'AltL'; 	 (* 00H 26H *)
	KeyName[ 062C ] := 'AltM'; 	 (* 00H 32H *)
	KeyName[ 061C ] := 'AltN'; 	 (* 00H 31H *)
	KeyName[ 030C ] := 'AltO'; 	 (* 00H 18H *)
	KeyName[ 031C ] := 'AltP'; 	 (* 00H 19H *)
	KeyName[ 020C ] := 'AltQ'; 	 (* 00H 10H *)
	KeyName[ 023C ] := 'AltR'; 	 (* 00H 13H *)
	KeyName[ 037C ] := 'AltS'; 	 (* 00H 1FH *)
	KeyName[ 024C ] := 'AltT'; 	 (* 00H 14H *)
	KeyName[ 026C ] := 'AltU'; 	 (* 00H 16H *)
	KeyName[ 057C ] := 'AltV'; 	 (* 00H 2FH *)
	KeyName[ 021C ] := 'AltW'; 	 (* 00H 11H *)
	KeyName[ 055C ] := 'AltX'; 	 (* 00H 2DH *)
	KeyName[ 025C ] := 'AltY'; 	 (* 00H 15H *)
	KeyName[ 054C ] := 'AltZ'; 	 (* 00H 2CH *)

	KeyName[ 073C ] := 'F1'; 	 (* 00H 3BH *)
	KeyName[ 074C ] := 'F2'; 	 (* 00H 3CH *)
	KeyName[ 075C ] := 'F3'; 	 (* 00H 3DH *)
	KeyName[ 076C ] := 'F4'; 	 (* 00H 3EH *)
	KeyName[ 077C ] := 'F5'; 	 (* 00H 3FH *)
	KeyName[ 100C ] := 'F6'; 	 (* 00H 40H *)
	KeyName[ 101C ] := 'F7'; 	 (* 00H 41H *)
	KeyName[ 102C ] := 'F8'; 	 (* 00H 42H *)
	KeyName[ 103C ] := 'F9'; 	 (* 00H 43H *)
	KeyName[ 104C ] := 'F10'; 	 (* 00H 44H *)
	
	KeyName[ 124C ] := 'ShiftF1'; 	 (* 00H 54H *)
	KeyName[ 125C ] := 'ShiftF2'; 	 (* 00H 55H *)
	KeyName[ 126C ] := 'ShiftF3'; 	 (* 00H 56H *)
	KeyName[ 127C ] := 'ShiftF4'; 	 (* 00H 57H *)
	KeyName[ 130C ] := 'ShiftF5'; 	 (* 00H 58H *)
	KeyName[ 131C ] := 'ShiftF6'; 	 (* 00H 59H *)
	KeyName[ 132C ] := 'ShiftF7'; 	 (* 00H 5AH *)
	KeyName[ 133C ] := 'ShiftF8'; 	 (* 00H 5BH *)
	KeyName[ 134C ] := 'ShiftF9'; 	 (* 00H 5CH *)
	KeyName[ 135C ] := 'ShiftF10'; 	 (* 00H 5DH *)

	KeyName[ 150C ] := 'AltF1'; 	 (* 00H 68H *)
	KeyName[ 151C ] := 'AltF2'; 	 (* 00H 69H *)
	KeyName[ 152C ] := 'AltF3'; 	 (* 00H 6AH *)
	KeyName[ 153C ] := 'AltF4'; 	 (* 00H 6BH *)
	KeyName[ 154C ] := 'AltF5'; 	 (* 00H 6CH *)
	KeyName[ 155C ] := 'AltF6'; 	 (* 00H 6DH *)
	KeyName[ 156C ] := 'AltF7'; 	 (* 00H 6EH *)
	KeyName[ 157C ] := 'AltF8'; 	 (* 00H 6FH *)
	KeyName[ 160C ] := 'AltF9'; 	 (* 00H 70H *)
	KeyName[ 161C ] := 'AltF10'; 	 (* 00H 71H *)

	KeyName[ 136C ] := 'CtrlF1'; 	 (* 00H 5EH *)
	KeyName[ 137C ] := 'CtrlF2'; 	 (* 00H 5FH *)
	KeyName[ 140C ] := 'CtrlF3'; 	 (* 00H 60H *)
	KeyName[ 141C ] := 'CtrlF4'; 	 (* 00H 61H *)
	KeyName[ 142C ] := 'CtrlF5'; 	 (* 00H 62H *)
	KeyName[ 143C ] := 'CtrlF6'; 	 (* 00H 63H *)
	KeyName[ 144C ] := 'CtrlF7'; 	 (* 00H 64H *)
	KeyName[ 145C ] := 'CtrlF8'; 	 (* 00H 65H *)
	KeyName[ 146C ] := 'CtrlF9'; 	 (* 00H 66H *)
	KeyName[ 147C ] := 'CtrlF10'; 	 (* 00H 67H *)

	KeyName[ 170C ] := 'Alt1'; 	 (* 00H 78H *)
	KeyName[ 171C ] := 'Alt2'; 	 (* 00H 79H *)
	KeyName[ 172C ] := 'Alt3'; 	 (* 00H 7AH *)
	KeyName[ 173C ] := 'Alt4'; 	 (* 00H 7BH *)
	KeyName[ 174C ] := 'Alt5'; 	 (* 00H 7CH *)
	KeyName[ 175C ] := 'Alt6'; 	 (* 00H 7DH *)
	KeyName[ 176C ] := 'Alt7'; 	 (* 00H 7EH *)
	KeyName[ 177C ] := 'Alt8'; 	 (* 00H 7FH *)
	KeyName[ 200C ] := 'Alt9'; 	 (* 00H 80H *)
	KeyName[ 201C ] := 'Alt0'; 	 (* 00H 81H *)

	KeyName[ 051C ] := 'AltBackQuote'; 	(* 00H 29H *)
	KeyName[ 202C ] := 'AltMinus';	 	(* 00H 82H *)
	KeyName[ 203C ] := 'AltEqual';	 	(* 00H 83H *)
	KeyName[ 053C ] := 'AltBackSlash'; 	(* 00H 2BH *)
	KeyName[ 224C ] := 'CtrlTab';	 	(* 00H 94H *)
	KeyName[ 017C ] := 'ShiftTab';	 	(* 00H 0FH *)
	KeyName[ 245C ] := 'AltTab';	 	(* 00H A5H *)
	KeyName[ 016C ] := 'AltBackspace'; 	(* 00H 0EH *)
	KeyName[ 001C ] := 'AltEsc'; 	 	(* 00H 01H *)
	KeyName[ 032C ] := 'AltLeftBracket'; 	(* 00H 1AH *)
	KeyName[ 033C ] := 'AltRightBracket'; 	(* 00H 1BH *)
	KeyName[ 047C ] := 'AltSemicolon'; 	(* 00H 27H *)
	KeyName[ 050C ] := 'AltQuote'; 	 (* 00H 28H *)
	KeyName[ 034C ] := 'AltEnter'; 	 (* 00H 1CH *)
	KeyName[ 063C ] := 'AltComma'; 	 (* 00H 33H *)
	KeyName[ 064C ] := 'AltPeriod';  (* 00H 34H *)
	KeyName[ 065C ] := 'AltSlash'; 	 (* 00H 35H *)

	KeyName[ 163C ] := 'CtrlCursorLeft';	(* 00H 73H *)
	KeyName[ 164C ] := 'CtrlCursorRight';	(* 00H 74H *)
	KeyName[ 165C ] := 'CtrlEnd'; 	 (* 00H 75H *)
	KeyName[ 166C ] := 'CtrlPgDn'; 	 (* 00H 76H *)
	KeyName[ 167C ] := 'CtrlHome'; 	 (* 00H 77H *)
	KeyName[ 204C ] := 'CtrlPgUp'; 	 (* 00H 84H *)
	KeyName[ 215C ] := 'CtrlCursorUp'; 	 (* 00H 8DH *)
	KeyName[ 216C ] := 'CtrlKeyPadMinus'; 	 (* 00H 8EH *)
	KeyName[ 217C ] := 'CtrlKeyPad5'; 	 (* 00H 8FH *)
	KeyName[ 220C ] := 'CtrlKeyPadPlus'; 	 (* 00H 90H *)
	KeyName[ 221C ] := 'CtrlCursorDn'; 	 (* 00H 91H *)
	KeyName[ 222C ] := 'CtrlIns'; 	 (* 00H 92H *)
	KeyName[ 223C ] := 'CtrlDel'; 	 (* 00H 93H *)

	KeyName[ 067C ] := 'AltKeyPadAstirisk';	(* 00H 37H *)
	KeyName[ 112C ] := 'AltKeyPadMinus'; 	(* 00H 4AH *)
	KeyName[ 116C ] := 'AltKeyPadPlus'; 	(* 00H 4EH *)
	KeyName[ 227C ] := 'AltHome'; 	 	(* 00H 97H *)
	KeyName[ 230C ] := 'AltCursorUp'; 	(* 00H 98H *)
	KeyName[ 231C ] := 'AltPgUp'; 	 	(* 00H 99H *)
	KeyName[ 233C ] := 'AltCursorLeft'; 	(* 00H 9BH *)
	KeyName[ 234C ] := 'AltKeyPad5'; 	(* 00H 9CH *)
	KeyName[ 235C ] := 'AltCursorRight'; 	(* 00H 9DH *)
	KeyName[ 237C ] := 'AltEnd'; 	 	(* 00H 9FH *)
	KeyName[ 240C ] := 'AltCursorDn'; 	(* 00H A0H *)
	KeyName[ 241C ] := 'AltPgDn'; 	 (* 00H A1H *)
	KeyName[ 242C ] := 'AltIns'; 	 (* 00H A2H *)
	KeyName[ 243C ] := 'AltDel'; 	 (* 00H A3H *)

	KeyName[ 107C ] := 'Home'; 	 (* 00H 47H *)
	KeyName[ 110C ] := 'CursorUp'; 	 (* 00H 48H *)
	KeyName[ 111C ] := 'PgUp'; 	 (* 00H 49H *)
	KeyName[ 113C ] := 'CursorLeft'; (* 00H 4BH *)
	KeyName[ 114C ] := 'KeyPad5'; 	 (* 00H 4CH *)
	KeyName[ 115C ] := 'CursorRight';(* 00H 4DH *)
	KeyName[ 117C ] := 'End'; 	 (* 00H 4FH *)
	KeyName[ 120C ] := 'CursorDn'; 	 (* 00H 50H *)
	KeyName[ 121C ] := 'PgDn'; 	 (* 00H 51H *)
	KeyName[ 122C ] := 'Ins'; 	 (* 00H 52H *)
	KeyName[ 123C ] := 'Del'; 	 (* 00H 53H *)
   END SetPCKeyNames ;

PROCEDURE KWriteLn;
BEGIN
   WrStr( ListFile, ListLine );
   WrLn( ListFile ) ;
   IF IOresult() <> 0 THEN
        MPos := 0;
        SWriteString(Message,MPos,'PrintKeys: Error writing to KEYTRACE.LST: ',0);
        IO.WrStr( Message );
        Close( ListFile ) ;
        HALT ;
   END;
   ListPos := 0;
   SWriteString(ListLine,ListPos,'    | ',6);
END KWriteLn;

PROCEDURE WriteKeysToFile( Ext : BOOLEAN; Ch : CHAR ) ;
    BEGIN	
	IF Ext THEN
	   SWriteString(ListLine,ListPos,' ',0);
	   SWriteString(ListLine,ListPos,KeyName[Ch],0);
	   SWriteString(ListLine,ListPos,' ',0);
	ELSIF Ch = ' ' THEN
	   SWriteString(ListLine,ListPos,' SP ',0);
	ELSIF Ch = CHR(30) THEN
	   SWriteString(ListLine,ListPos,' ENTER ',0);
	ELSIF Ch = CHR(8) THEN
	   SWriteString(ListLine,ListPos,' BS ',0);
	ELSIF Ch = CHR(9) THEN
	   SWriteString(ListLine,ListPos,' TAB ',0);
	ELSIF Ch = CHR(27) THEN
	   SWriteString(ListLine,ListPos,' ESC ',0);
	ELSE
	   SWriteString(ListLine,ListPos,Ch,0);
	END ;
	IF ListPos >= 72 THEN
	   KWriteLn ;
	END ;
    END WriteKeysToFile ;

PROCEDURE WriteRestOfLineToFile ;
    VAR
	RestOfLine : ARRAY[0..255] OF CHAR ;
	LineLen : CARDINAL ;
    BEGIN
	LineLen := Str.Length( KeyLine ) ;
	Str.Slice( RestOfLine, KeyLine, KeyPos, LineLen );
	KeyPos := LineLen ; (* point at the 0C character to for a read line *)
	SWriteString(ListLine,ListPos,RestOfLine,0);
	IF ListPos >= 72 THEN
	   KWriteLn ;
	END ;
    END WriteRestOfLineToFile ;

PROCEDURE ReadKeysFromFile( VAR Ext : BOOLEAN; VAR Ch : CHAR ) ;
   VAR
	dummy	: BOOLEAN ;
	Done	: BOOLEAN ;
	NextCh	: CHAR ;
	
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
	   IF IsHex( KeyLine[KeyPos] ) THEN
	      ch1 := KeyLine[KeyPos] ;
	      INC( KeyPos ) ;
	      IF IsHex( KeyLine[KeyPos] ) THEN
		 ch2 := KeyLine[KeyPos] ;
		 INC( KeyPos ) ;	
		 IF ch1 >= 'A' THEN	(* its one of "A"-"F" *)
		    Ch := CHAR( (ORD(ch1) - 55) * 16 ) (* "7" = 55 *)
		 ELSE
		    Ch := CHAR( (ORD(ch1) - 48) * 16 ) (* "0" = 48 *)
		 END ;
		 IF ch2 >= 'A' THEN
		    Ch := CHAR( ORD(Ch) + ORD(ch2) - 55)
		 ELSE
		    Ch := CHAR( ORD(Ch) + ORD(ch2) - 48)
		 END ;
		 RETURN TRUE
	      END ;
	   END ;
	   Ch := '?' ;
	   Ext := FALSE ;
	   RETURN FALSE ;
	END GetHexChar ;
	    	
    BEGIN	
        Done := FALSE ;
	REPEAT
	   IF KeyLine[KeyPos] = 0C THEN
		RdStr(KeyFile, KeyLine) ;
		INC( LineRead ) ;
		IF ListPos > 6 THEN  KWriteLn  END ; (* flush out previous line *)
		ListPos := 0 ;  (* so we can add the input line number *)
		SWriteCard(ListLine,ListPos,LineRead,4);
		SWriteString(ListLine,ListPos,'| ',0);
		IF EOF OR ( IOresult() <> 0 ) THEN
		   Close( KeyFile );
		   ReadKeyTraceFile := FALSE ;
		   Ch := '?' ;
		   Ext := FALSE ;
		   RETURN
		END ;
		KeyPos := 0 ;
	   END ;
	   IF KeyLine[KeyPos] = ' ' THEN  (* ignore blanks *)
		INC( KeyPos ) ;
	   ELSIF GetHexChar( Ch ) THEN
		IF Ch = 0C THEN
		   dummy := GetHexChar( Ch ) ;
		   Ext := TRUE;
		ELSE
		   Ext := FALSE
		END ;
		Done := TRUE ;
	   ELSIF KeyLine[KeyPos] = '?' THEN
		INC( KeyPos ) ;
	   ELSIF KeyLine[KeyPos] = '#' THEN
		Ch := '#' ;	(* pass thru the pause character *)
		Done := TRUE ;
		Ext := FALSE ;
		INC( KeyPos ) ;
	   ELSIF (KeyPos = 0) AND (KeyLine[KeyPos] = '.') THEN
		Ch := '.' ;	(* pass thru end of window structure *)
		Done := TRUE ;
		Ext := FALSE ;
		INC( KeyPos ) ;
	   ELSIF (KeyLine[KeyPos] = '!') OR (KeyLine[KeyPos] = '|') THEN
		Ch := KeyLine[KeyPos] ;
		NextCh := KeyLine[KeyPos+1] ;
		IF (Ch = "!") AND (NextCh = "P") THEN
		   (* pass thru the pause escape codes *)
		   SWriteString(ListLine,ListPos," !P ",0);
		   INC( KeyPos, 2 ) ;
		ELSIF (Ch = "!") AND (NextCh = "D") THEN
		   (* pass thru the delay escape codes *)
		   SWriteString(ListLine,ListPos," !D ",0);
		   INC( KeyPos, 3 ) ;
		   WHILE KeyLine[KeyPos] IN Str.CHARSET{"0".."9"} DO
			WriteKeysToFile( FALSE, KeyLine[KeyPos] ) ;
			INC( KeyPos ) ;
		   END ;
		   SWriteString(ListLine,ListPos," ",0);
		ELSE
		   (* pass thru to end of line *)
		   WriteRestOfLineToFile ;
		END ;
	   ELSE
		(* ignore invalid char ??? *)
		INC( KeyPos ) ;
		MPos := 0;
		SWriteString(Message,MPos,'invalid HEX code in KEYTRACE file, code = ',0);
		SWriteChar( Message, MPos, KeyLine[KeyPos], 0 ) ;
		SWriteString(Message,MPos,', Line # ',0);
		SWriteCard(Message,MPos,LineRead,0);
		IO.WrStr( Message );
	   END ;	
	UNTIL Done ;
    END ReadKeysFromFile ;

BEGIN
   KeyFileName  := 'KEYTRACE.DMP';
   ListFileName := 'KEYTRACE.LST';
   ParamStr( TempStr, 1 ) ;
   IF (TempStr[0] = '?') OR (Str.Compare( TempStr, '-h') = 0) OR
	(Str.Compare( TempStr, '-H') = 0) THEN
	IO.WrStr( 'Syntax:   PrintKeys [InKeyTraceFileName [OutListFileName] ]' ) ; IO.WrLn ;
	IO.WrLn ;
	IO.WrStr( 'Defaults: InKeyTraceFileName = KEYTRACE.DMP' ) ; IO.WrLn ;
	IO.WrStr( '          OutListFileName    = KEYTRACE.LST' ) ; IO.WrLn ;
	HALT ;
   END ;
   IF ParamCount() > 0 THEN
	ParamStr( KeyFileName, 1 ) ;
	IF ParamCount() >= 2 THEN
	   ParamStr( ListFileName, 2 ) ;
	END ;
   END ;
   LineRead  := 0 ;
   MPos := 0;
   KeyFile := Open( KeyFileName ) ;
   IF IOresult() <> 0 THEN
	IO.WrStr( 'Unable to find/open file "' ) ;
	IO.WrStr( KeyFileName ) ;
	IO.WrStr( '"' ) ;
	HALT ;
   END ;
   ListFile := Create( ListFileName ) ;
   IF IOresult() <> 0 THEN
	IO.WrStr( 'Unable to find/open file "' ) ;
	IO.WrStr( ListFileName ) ;
	IO.WrStr( '"' ) ;
	HALT ;
   END ;
   IO.WrStr( 'Input keytrace file: ' ) ;
   IO.WrStr( KeyFileName ) ;
   IO.WrLn ;
   IO.WrStr( 'Output listing file: ' ) ;
   IO.WrStr( ListFileName ) ;
   IO.WrLn ;
   SetPCKeyNames ;
   ReadKeyTraceFile := TRUE ;
   ListPos := 0 ;
   KeyPos  := 0 ;
   KeyLine[0] := 0C ;
   ListLine[0] := 0C ;
   ReadKeysFromFile( Ext, Ch ) ;
   WHILE ReadKeyTraceFile DO
	WriteKeysToFile( Ext, Ch ) ;
	ReadKeysFromFile( Ext, Ch ) ;
   END ;
   IF ListPos > 6 THEN  KWriteLn  END ; (* flush out last line *)
   Close( ListFile ) ;
END PrintKeys.
