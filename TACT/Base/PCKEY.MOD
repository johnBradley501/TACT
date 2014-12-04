IMPLEMENTATION MODULE PCKey ;

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

(*----------------------------------------------------------------------*)
(* DESCRIPTION:                                                         *)
(*    - The following is a complete list of keys (with the second scan  *)
(*      code) for the IBM PC keyboard.                                  *)
(*                                                                      *)
(* DATE: May 15, 1987                                                   *)
(* Last Update:                                                         *)
(*   - Aug. 19, 1988, L.Presutti                                        *)
(*     Added extra keys obtained from modified interupt vectors 09 & 16H*)
(*                                                                      *)
(* BY: Lidio Presutti                                                   *)
(*     University of Toronto Computing Services                         *)
(*     Humanities Application Support Programmer                        *)
(*----------------------------------------------------------------------*)

(*
EXPORT QUALIFIED
	ExtendedCharCode, Nul, Tab,
	AltA, AltB, AltC, AltD, AltE, AltF, AltG, AltH, AltI, AltJ, AltK, AltL,
	      AltM, AltN, AltO, AltP, AltQ, AltR, AltS, AltT, AltU, AltV, AltW,
	      AltX, AltY, AltZ,
	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10,
	ShiftF1, ShiftF2, ShiftF3, ShiftF4, ShiftF5, ShiftF6, ShiftF7, ShiftF8,
	         ShiftF9, ShiftF10,
	CtrlF1, CtrlF2, CtrlF3, CtrlF4, CtrlF5, CtrlF6, CtrlF7, CtrlF8, CtrlF9, CtrlF10,
	AltF1, AltF2, AltF3, AltF4, AltF5, AltF6, AltF7, AltF8, AltF9, AltF10,
	Alt1, Alt2, Alt3, Alt4, Alt5, Alt6, Alt7, Alt8, Alt9, Alt0,
	AltBackQuote, AltMinus, AltEqual, AltBackSlash, CntlTab,
	ShiftTab, AltTab, AltBackspace, AltEsc, AltLeftBracket, AltRightBracket,
	AltSemicolon, AltQuote, AltEnter, AltComma, AltPeriod, AltSlash,
	CntlCursorLeft, CntlCursorRight, CntlEnd, CntlPgDn, CntlHome,
	CntlPgUp, CntlCursorUp, CntlKeyPadMinus, CntlKeyPad5, CntlKeyPadPlus,
	CntlCursorDn, CntlIns, CntlDel,
	AltKeyPadAstirisk, AltKeyPadMinus, AltKeyPadPlus, AltHome,
	AltCursorUp, AltPgDn, AltCursorLeft, AltKeyPad5, AltCursorRight,
	AltEnd, AltCursorDn, AltIns, AltDel,
	Home, CursorUp, PgDn, CursorLeft, KeyPad5, CursorRight, End, CursorDn,
	Ins, Del ;
*)

BEGIN
   (* see Definition file for values of constants *)
END PCKey .
