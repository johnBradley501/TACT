IMPLEMENTATION MODULE UsenhKBD ;

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

(* JPI version   j.b. *)
(*v1=Dbg *)
IMPORT Str;
FROM SYSTEM IMPORT ADDRESS, Registers;
FROM ENHKBD IMPORT
  (* Vars  *) HASENHANCEDKBD, ENABLEENHANCED,
  (* Procs *) INITVECTORS, ENHANCEDKBD (*, RESTOREVECTORS *) ;

FROM Utils IMPORT UpcaseStr, GetEnv;

(*<Dbg
FROM IO IMPORT WrLn, WrStr ;
Dbg>*)

VAR
  Restored  : BOOLEAN ;
  Int09 [0:09H*4],
  Int16 [0:16H*4],
  OldInt09, OldInt16	: ADDRESS ;

PROCEDURE RestoreKbdVectors;
  (* Restores original vectors for INT's $09 and $16. *)
VAR r:  Registers;
  BEGIN
    IF Restored THEN
       RETURN
    END ;
    Restored := TRUE;

(*    RESTOREVECTORS; *)

    Int09 := OldInt09 ;
    Int16 := OldInt16 ;

  END RestoreKbdVectors ;

PROCEDURE SetKbdVectors ;
   BEGIN
	(* Don't test for enhanced keyboard until requested *)
	HASENHANCEDKBD := ENHANCEDKBD() ;
	ENABLEENHANCED := TRUE;

(*<Dbg
        WrLn ;
        IF HASENHANCEDKBD THEN
           WrStr( 'HASENHANCEDKBD is TRUE' )
        ELSE
           WrStr( 'HASENHANCEDKBD is FALSE')
        END ;
        WrLn ;
        IF ENABLEENHANCED THEN
           WrStr( 'ENABLEENHANCED is TRUE' )
        ELSE
           WrStr( 'ENABLEENHANCED is FALSE')
        END ;
        WrLn ;

        WrStr('Starting INITVECTORS ...');
Dbg>*)

	OldInt09 := Int09 ;	(* save old interupt vector addresses *)
	OldInt16 := Int16 ;
	
	INITVECTORS;
        Restored := FALSE;

(*<Dbg
        WrStr(' Done');
        WrLn;
Dbg>*)


   END SetKbdVectors ;

PROCEDURE UserRequestedStdKBD(): BOOLEAN;
   VAR
        st:  ARRAY[0..40] OF CHAR;
   BEGIN
        GetEnv( 'ENHKBD', st);
        UpcaseStr(st,st);
        RETURN (Str.Compare(st, 'NO') = 0)
   END UserRequestedStdKBD;

BEGIN
	Restored := TRUE ;
END UsenhKBD .
