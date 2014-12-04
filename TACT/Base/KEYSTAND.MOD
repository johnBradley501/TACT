IMPLEMENTATION MODULE KeyStandards;

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

   FROM SYSTEM IMPORT ADR;
   IMPORT PCKey, ASCII ;
   IMPORT Lib ;

CONST
   PanelTableSize = 14;
   ListTableSize = 19; (* m.s. - was 17, added AltPgUp and AltPgDn *)
   ActBarTableSize = 10;

VAR
   PA: ARRAY[0..PanelTableSize-1] OF CHAR;
   PE: ARRAY[0..PanelTableSize-1] OF CHAR;
   PR: ARRAY[0..PanelTableSize-1] OF PanelControlKeys;

   LA: ARRAY[0..ListTableSize-1] OF CHAR;
   LE: ARRAY[0..ListTableSize-1] OF CHAR;
   LR: ARRAY[0..ListTableSize-1] OF ListControlKeys;

   AA: ARRAY[0..ActBarTableSize-1] OF CHAR;
   AE: ARRAY[0..ActBarTableSize-1] OF CHAR;
   AR: ARRAY[0..ActBarTableSize-1] OF ActionBarControlKeys;

  PROCEDURE GetPanelControlKey(Ext:    BOOLEAN;
                               ch:     CHAR): PanelControlKeys;
VAR i:   CARDINAL;
BEGIN
   IF Ext THEN i := Lib.ScanR(ADR(PE),PanelTableSize,BYTE(ch))
          ELSE i := Lib.ScanR(ADR(PA),PanelTableSize,BYTE(ch)) END;
   IF i < PanelTableSize THEN RETURN PR[i]
                         ELSE RETURN NotPanelControlKey END;
END GetPanelControlKey;

  PROCEDURE GetListControlKey(Ext:    BOOLEAN;
                              ch:     CHAR): ListControlKeys;
VAR i:   CARDINAL;
BEGIN
   IF Ext THEN i := Lib.ScanR(ADR(LE),ListTableSize,BYTE(ch))
          ELSE i := Lib.ScanR(ADR(LA),ListTableSize,BYTE(ch)) END;
   IF i < ListTableSize THEN RETURN LR[i]
                        ELSE RETURN NotListControlKey END;
END GetListControlKey;

  PROCEDURE GetActBarControlKey(Ext:    BOOLEAN;
                                ch:     CHAR): ActionBarControlKeys;
VAR i:   CARDINAL;
BEGIN
   IF Ext THEN i := Lib.ScanR(ADR(AE),ActBarTableSize,BYTE(ch))
          ELSE i := Lib.ScanR(ADR(AA),ActBarTableSize,BYTE(ch)) END;
   IF i < ActBarTableSize THEN RETURN AR[i]
                        ELSE RETURN NotActionBarControlKey END;
END GetActBarControlKey;
BEGIN
(* within field ops *)
PA[0] := 0C;         PE[0] := PCKey.CursorRight;     PR[0] := CursorRight;
PA[1] := 0C;         PE[1] := PCKey.CursorLeft;      PR[1] := CursorLeft;
PA[2] := 0C;         PE[2] := PCKey.CtrlCursorRight; PR[2] := EndOfField;
PA[3] := 0C;         PE[3] := PCKey.CtrlCursorLeft;  PR[3] := BeginningOfField;
PA[4] := 0C;         PE[4] := PCKey.CtrlEnd;         PR[4] := EraseToEOF;
PA[5] := 0C;         PE[5] := PCKey.Del;             PR[5] := DeleteChar;
PA[6] := ASCII.bs;   PE[6] := 0C;                    PR[6] := BackspaceDelete;
(* field motion ops *)
PA[7] := ASCII.ht;   PE[7] := PCKey.CursorDn;        PR[7] := NextField;
PA[8] := 0C;         PE[8] := PCKey.CursorUp;        PR[8] := PrevField;
PA[9] := 0C;         PE[9] := PCKey.Home;            PR[9] := FirstField;
PA[10] := 0C;        PE[10] := PCKey.End;            PR[10] := LastField;
PA[11] := ASCII.rs;  PE[11] := 0C;                   PR[11] := PanelEnd;
PA[12] := ASCII.esc; PE[12] := 0C;                   PR[12] := PanelCancel;
PA[13] := 0C;        PE[13] := PCKey.Tab;  (* nb *)  PR[13] := PrevField;

FieldMotionExt[0] := PCKey.CursorDn;
FieldMotionExt[1] := PCKey.CursorUp;
FieldMotionExt[2] := PCKey.Home;
FieldMotionExt[3] := PCKey.End;
FieldMotionExt[4] := PCKey.Tab;

FieldMotionASC[0] := ASCII.ht;
FieldMotionASC[1] := ASCII.rs;
FieldMotionASC[2] := ASCII.esc;

LA[0] := 0C;         LE[0] := PCKey.CursorUp;          LR[0] := PrevItem;
LA[1] := ASCII.ht;   LE[1] := PCKey.CursorDn;          LR[1] := NextItem;
LA[2] := 0C;         LE[2] := PCKey.PgUp;              LR[2] := PrevScreen;
LA[3] := 0C;         LE[3] := PCKey.PgDn;              LR[3] := NextScreen;
LA[4] := 0C;         LE[4] := PCKey.Home;              LR[4] := FirstItem;
LA[5] := 0C;         LE[5] := PCKey.End;               LR[5] := LastItem;
LA[6] := 0C;         LE[6] := PCKey.Ins;               LR[6] := SelectToggle;
LA[7] := 0C;         LE[7] := PCKey.AltIns;            LR[7] := SelectAll;
LA[8] := 0C;         LE[8] := PCKey.AltDel;            LR[8] := DeSelectAll;
LA[9] := ASCII.rs;   LE[9] := 0C;                      LR[9] := ListEnd;
LA[10] := ASCII.esc; LE[10] := 0C;                     LR[10] := ListCancel;
LA[11] := 0C;        LE[11] := PCKey.AltTab;           LR[11] := MoveToItem;
LA[12] := 0C;        LE[12] := PCKey.Tab;  (* nb *)    LR[12] := PrevItem;
LA[13] := 0C;        LE[13] := PCKey.CursorRight;      LR[13] := ListRight;
LA[14] := 0C;        LE[14] := PCKey.CursorLeft;       LR[14] := ListLeft;
LA[15] := 0C;        LE[15] := PCKey.CtrlCursorRight;  LR[15] := JumpToEnd;
LA[16] := 0C;        LE[16] := PCKey.CtrlCursorLeft;   LR[16] := JumpToBeginning;
LA[17] := 0C;        LE[17] := PCKey.AltPgUp;          LR[17] := PrevGroup ; (* m.s. *)
LA[18] := 0C;        LE[18] := PCKey.AltPgDn;          LR[18] := NextGroup ; (* m.s. *)

(* m.s. - not sure of LR[17] and LR[18] *)

ListCharsExt[0] := PCKey.CursorUp;
ListCharsExt[1] := PCKey.CursorDn;
ListCharsExt[2] := PCKey.PgUp;
ListCharsExt[3] := PCKey.PgDn;
ListCharsExt[4] := PCKey.Home;
ListCharsExt[5] := PCKey.End;
ListCharsExt[6] := PCKey.Ins;
ListCharsExt[7] := PCKey.AltIns;
ListCharsExt[8] := PCKey.AltDel;
ListCharsExt[9] := PCKey.AltTab;
ListCharsExt[10] := PCKey.Tab;
ListCharsExt[11] := PCKey.CursorRight;
ListCharsExt[12] := PCKey.CursorLeft;
ListCharsExt[13] := PCKey.CtrlCursorRight;
ListCharsExt[14] := PCKey.CtrlCursorLeft;
ListCharsExt[15] := PCKey.AltPgUp;  (* m.s - replaces the function of old PgUp *)
ListCharsExt[16] := PCKey.AltPgDn;

ListCharsASC[0] := ASCII.ht;
ListCharsASC[1] := ASCII.rs;
ListCharsASC[2] := ASCII.esc;

ScrollingExt[0] := PCKey.PgUp;
ScrollingExt[1] := PCKey.PgDn;
ScrollingExt[2] := PCKey.Home;
ScrollingExt[3] := PCKey.End;

ScrollingASC[0] := ASCII.rs;
ScrollingASC[1] := ASCII.esc;

AA[0] := 0C;          AE[0] := PCKey.CursorLeft;       AR[0] := MoveLeft;
AA[1] := ' ';         AE[1] := PCKey.CursorRight;      AR[1] := MoveRight;
AA[2] := 0C;          AE[2] := PCKey.CursorUp;         AR[2] := MoveUp;
AA[3] := 0C;          AE[3] := PCKey.CursorDn;         AR[3] := MoveDown;
AA[4] := ASCII.ht;    AE[4] := 0C;                     AR[4] := MoveToNext;
AA[5] := 0C;          AE[5] := PCKey.Tab;              AR[5] := MoveToPrev;
AA[6] := 0C;          AE[6] := PCKey.Home;             AR[6] := MoveToFirst;
AA[7] := 0C;          AE[7] := PCKey.End;              AR[7] := MoveToLast;
AA[8] := ASCII.rs;    AE[8] := 0C;                     AR[8] := ChooseThis;
AA[9] := ASCII.esc;   AE[9] := 0C;                     AR[9] := ABCancel;

END KeyStandards.
