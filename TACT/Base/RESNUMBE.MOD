IMPLEMENTATION MODULE ResNumberArray;

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

FROM Utils IMPORT DEALLOCATE;
FROM SYSTEM IMPORT ADDRESS;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResArray IMPORT
   (*type*) ResDataType,ResArrayError,
   (*proc*) FindResource;
FROM ResBase IMPORT
   (*type*) FilePos,
   (*proc*) ReadResourceBase;

PROCEDURE GetNumberArray(ID:   CARDINAL;
                     VAR Data: ADDRESS; (* POINTER TO ARRAY OF CARDINAL *)
                     VAR Size: CARDINAL); (* # of CARDINAL numbers *)
VAR
   Error:    ResArrayError;
   ArryPos:  FilePos;
   NBytes:   CARDINAL;
BEGIN
   IF NOT FindResource(NumberArrayResource,ID,ArryPos,Error) THEN
       ProgramErrorAndHalt('Fatal Resource Error (1) in GetNumberArray');
       HALT
   END;
   Data := NIL;
   IF NOT ReadResourceBase(0,ArryPos,Data,NBytes) THEN
       ProgramErrorAndHalt('Fatal Resource Error (2) in GetNumberArray');
       HALT
   END;
   Size := NBytes DIV 2;
END GetNumberArray;

PROCEDURE DisposeNumberArray(VAR Data: ADDRESS;
                             VAR Size: CARDINAL);
BEGIN
   DEALLOCATE(Data,Size*2);
   Data := NIL;
END DisposeNumberArray;

END ResNumberArray.
