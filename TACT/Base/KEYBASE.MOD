(*--------------------------------------------------------------------------*)

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
(*                                                                          *)
(* History: was "Keyboard" module from Logitech version 3.0                 *)
(*          modified for use in JPI Modula 2  j.b.                          *)
(*          Added mouse support.   *LP*                                     *)
(*                                                                          *)
(*--------------------------------------------------------------------------*)

IMPLEMENTATION MODULE KeyBase ;

(*V1=NoMouse*)
(*V2=Mouse Support code*)

IMPORT IO;
IMPORT Lib;
IMPORT ASCII;
FROM SYSTEM IMPORT Registers ;

CONST
    CtrlC =  3C;
    KBDCR = 15C;
    BREAK = 1BH;
    H = 40;
    V = 13;


PROCEDURE IsMouseInstalled() : BOOLEAN;
    VAR
	Reg : Registers;
    BEGIN
	Reg.AX := 0;
	Lib.Intr(Reg, 33H);
	RETURN  Reg.AX <> 0;
    END IsMouseInstalled ;

PROCEDURE ShowMouseCursor;
    VAR
	Reg : Registers;
    BEGIN
	Reg.AX := 1;
	Lib.Intr(Reg, 33H);
    END ShowMouseCursor ;

PROCEDURE HideMouseCursor;
    VAR
	Reg : Registers;
    BEGIN
	Reg.AX := 2;
	Lib.Intr(Reg, 33H);
    END HideMouseCursor ;

PROCEDURE GetMouseAction(VAR Button : ButtonType; VAR Column, Row : CARDINAL);
    VAR
	Reg : Registers;
    BEGIN
	WITH Reg DO
	   AX := 3;
	   Lib.Intr(Reg, 33H);
	   Column  := CX DIV 8;
	   Row     := DX DIV 8;
	   CASE BX MOD 4 OF
	      0:   Button := NoButtons;   |
	      1:   Button := LeftButton;  |
	      2:   Button := RightButton; |
	      3:   Button := BothButtons
	   END ;
	END;
    END GetMouseAction ;

PROCEDURE MoveMouse(Column, Row : CARDINAL);
    VAR
	Reg : Registers;
    BEGIN
	Reg.AX := 4;
	Reg.CX := Column * 8 - 1;
	Reg.DX := Row * 8 - 1;
	Lib.Intr(Reg, 33H);
    END MoveMouse ;

PROCEDURE ConfineMouseHoriz(MinCol, MaxCol : CARDINAL);
    VAR
	Reg : Registers;
    BEGIN
	Reg.AX := 7;
	Reg.CX := MinCol * 8 - 1 ;
	Reg.DX := MaxCol * 8 - 1 ;
	Lib.Intr(Reg, 33H);
    END ConfineMouseHoriz ;

PROCEDURE ConfineMouseVert(TopRow, BotRow : CARDINAL);
    VAR
	Reg : Registers;
    BEGIN
	Reg.AX := 8;
	Reg.CX := TopRow * 8 - 1 ;
	Reg.DX := BotRow * 8 - 1 ;
	Lib.Intr(Reg, 33H);
    END ConfineMouseVert ;

PROCEDURE SetMouseCursorStyle(OrdChar : CARDINAL);
    VAR
	Reg : Registers;
    BEGIN
	Reg.AX := 10;
	Reg.BX := 0;        (* software text cursor *)
	Reg.CX := 7700H ;   (* Screen mask *)
	Reg.DX := OrdChar MOD 77H ; (* Cursor mask --> was: 77H AND OrdChar *)
	Lib.Intr(Reg, 33H);
    END SetMouseCursorStyle;


PROCEDURE KeyPressed(): BOOLEAN;
   (* Returns TRUE, if a character has been entered, FALSE otherwise.   *)
   BEGIN
	RETURN IO.KeyPressed();
   END KeyPressed;

PROCEDURE Read(VAR ch: CHAR);
    (* Waits until a character has been entered and returns it.
       If Ctrl-C is entered, the program is stopped.
       CR is transformed into ASCII.EOL.    *)
  BEGIN
    ch := IO.RdKey();
    IF ch = CtrlC THEN
(* m.s. - only works with DOS      Lib.UserBreak; *)
    END;
    IF ch = KBDCR THEN ch := ASCII.rs;
      (* ASCII-cr is transformed in Modula-2 EOL character *)
    END;
  END Read;

PROCEDURE ReadKey( VAR Ch : CHAR; VAR Ext : BOOLEAN ) ;
    (* waits for keypress or mouse activity *)
    VAR
	Action,
	Done		: BOOLEAN;
	Hor, Vert	: CARDINAL;
	Button		: ButtonType;
    BEGIN
	Ext := FALSE;
(*<Mouse	
	Done := FALSE;
	Action := FALSE;
	Button := NoButtons;
	IF MouseInstalled THEN MoveMouse(H, V) END ;	(* logically put mouse in middle of screen *)
	REPEAT		(* keep checking Mouse for activity UNTIL keypressed *)
	   IF MouseInstalled THEN
	      Done := TRUE;  (* assume true, unless there was no real mouse activity *)
	      GetMouseAction(Button, Hor, Vert);
	      CASE Button OF
		 LeftButton :
			Ch := MouseEnter |
		 RightButton :
			Ch := MouseEsc |
		 ELSE	(* ignore it, see if there was motion *) ;
		    IF (INTEGER(Vert) - V) > 1 THEN
			Ch := MouseDown;
			Ext := TRUE ;
		    ELSIF (V - INTEGER(Vert)) > 1 THEN
			Ch := MouseUp;
			Ext := TRUE ;
		    ELSIF (INTEGER(Hor) - H) > HorizSensitivity THEN
			Ch := MouseRight;
			Ext := TRUE ;
		    ELSIF (H - INTEGER(Hor)) > HorizSensitivity THEN
			Ch := MouseLeft;
			Ext := TRUE ;
		    ELSE
			Done := FALSE ;
		    END;
	      END (* CASE Button OF *) ;
	   END;
	   IF KeyPressed() OR Done THEN  Action := TRUE  END ;
	UNTIL Action;
	IF NOT Done THEN
Mouse>*)
	   Read( Ch );
	   IF Ch = 0C THEN
		Ext := TRUE ;
		Read( Ch );
	   END;
(*<Mouse
	END;

	IF Done AND ((Ch = MouseEnter) OR (Ch = MouseEsc)) THEN
	   (*  Delay(150);  *)
	   GetMouseAction(Button, Hor, Vert);  (* absorb any mouse activity *)
	END;
Mouse>*)	
    END ReadKey ;

PROCEDURE FlushKeyBoard;
    VAR
	Ch : CHAR ;
    BEGIN
	WHILE KeyPressed() DO  Read( Ch )  END ;
    END FlushKeyBoard ;


    BEGIN
(*Mouse
	MouseInstalled := IsMouseInstalled();
	IF MouseInstalled THEN  HorizSensitivity := 1  END ;
Mouse>*)
    END KeyBase.

