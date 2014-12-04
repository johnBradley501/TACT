IMPLEMENTATION MODULE Handles;

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
(*
Description: Allows Modula-2 programmers to use more than the 20
             files provided by DOS.  Requires DOS 3.0 or higher,
             TopSpeed or others Modula-2. No procedures exported,
             installs automatically.

Author:      Marc Scheuner
             Alisys
             CH-3400 Burgdorf, Switzerland
             modified by John Bradley to perform check of DOS
             version.

Date:        June 3, 1989
*)

FROM Lib IMPORT Fill, Move, Dos;
FROM SYSTEM IMPORT Registers, ADR;

TYPE   PSPRec = RECORD
           Unused       : ARRAY [1..24] OF CHAR;
           HandTable    : ARRAY [1..20] OF SHORTCARD;
           (* the DOS file handle table *)
           Unused2      : ARRAY [1..6] OF CHAR;
           TableSize    : CARDINAL ; (* size of the table *)
           TablePtr     : ADDRESS ;  (* pointer to the table *)
       END;

VAR NewHTable : ARRAY [1..MaxNrOfFiles] OF SHORTCARD;
   (* This is the new table of file handles that replaces the
      standard DOS file handle table which is in the PSP, limited
      to 20 entries at most. *)

PROCEDURE Setup;
VAR
   R:    Registers;
   P: RECORD
        CASE : BOOLEAN OF
           | TRUE   : Ptr : POINTER TO PSPRec;
           | FALSE  : Ofs, Seg: CARDINAL;
        END;
      END;

BEGIN
   R.AH := 30H;
   R.AL := 0;
   Dos (R);  (* Get the DOS version number *)
   IF R.AL < 3 THEN
      NrOfFilesAvailable := 20;
      RETURN
   END;
   NrOfFilesAvailable := MaxNrOfFiles;

   R.AH := 62H;
   R.AL := 0;
   Dos (R); (* Get the segment address of the PSP of the program *)
   P.Seg := R.BX;
   P.Ofs := 0; (* set P to point to the PSP of the program *)

   (* initialize the new file handle table to zero values *)
   Fill ( ADR (NewHTable), SIZE(NewHTable), 0FFH);

   (* move the contents of the original DOS file handle table into
   the new table *)
   Move ( ADR (P.Ptr^.HandTable), ADR(NewHTable), 20);

   (* instruct the PSP to accept the new maximum number of files *)
   P.Ptr^.TableSize := MaxNrOfFiles;

   (* set the pointer to the file handle table in the PSP to our
   own new file handle table *)
   P.Ptr^.TablePtr := ADR (NewHTable);
END Setup;

BEGIN
   Setup;
END Handles.