IMPLEMENTATION MODULE GlobalDefs;
(* copyright (c) 1989-96 John Bradley, Lidio Presutti, University of Toronto *)

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

IMPORT Str, Lib, FIO;
FROM ResMessages IMPORT
   (* proc *) GetResMessage;
FROM Utils IMPORT Terminate, Status;

CONST
   (*RES OLD MSG 203
   2.1.3/(April 1994 - Gamma)
   *)
   (*RES OLD MSG 203
   2.1.3
   *)
   SystemVerRes = (*RES REM INS*) 203;
   SystemVersionModel = '2.1.3'; (* this constant value should match Res value j.b. *)


PROCEDURE CheckResVersion;
VAR
   tStr:     ARRAY[0..40] OF CHAR;
   i:        CARDINAL;
   Year, Month, Day : CARDINAL ;
(* DayOfWeek: Lib.DayType ; *)
BEGIN
   SystemVersion := SystemVersionModel;
   GetResMessage( SystemVerRes, tStr);
   SystemVersionDate[0] := 0C ;
   i := 0;
   WHILE (tStr[i] <> '/') AND (tStr[i] <> 0C) DO INC(i) END;
   tStr[i] := 0C;
   IF Str.Compare(tStr, SystemVersion) <> 0 THEN
      FIO.WrStr(FIO.ErrorOutput, 'Incorrect RES Version');
      Terminate( Normal ) ;
   END;
   tStr[i] := '/';
   Str.Slice(SystemVersionDate,tStr,i+1,99) ;
(*   m.s. time bomb removed
   Lib.GetDate( Year, Month, Day, DayOfWeek ) ;
   IF (Year <> 1993) OR (Month < 5) THEN  (* test for beta version !! *)
      NonWMMessage( 'Incorrect version of file "TACT.RES".' ) ;
      Terminate( Normal ) ;
   END ;
*)
END CheckResVersion;

(*
PROCEDURE CheckParam( ID : CARDINAL ) ; (* m.s. - check to see if program started
                                                  with -?, ?, /?, if so dump ID
                                                  message and quit *)
VAR
   P : ARRAY [0..255] OF CHAR ;
BEGIN
   IF Lib.ParamCount() > 0 THEN
     Lib.ParamStr( P, 1) ;
     IF (P[0] = '?') OR ( P[1] = '?' ) THEN
       GetResMessage( ID, P ) ;
       FIO.WrStr(FIO.StandardOutput, P);
       Terminate( Normal ) ;  (* no dumps *)
     END ;
   END ;
END CheckParam ;
*)

END GlobalDefs.
