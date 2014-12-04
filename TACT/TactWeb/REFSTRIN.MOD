IMPLEMENTATION MODULE RefStrInit ;
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


FROM ErrorBase IMPORT ProgramErrorAndHalt ;
FROM DBData IMPORT BeginStr, NoStrRecs ;

(* maybe RefStrRecListPntr should be sorted and index by ABS(RefID) ?? *)

PROCEDURE GetRefStrRecInfo( 	RefID : INTEGER ;
			    VAR StartRec, StartIdx, EndRec, EndIdx : CARDINAL ) ;
   VAR
	I : CARDINAL ;
   BEGIN
	I := 1 ;
	WHILE (I <= NoStrRecs) AND (RefID <> RefStrRecListPntr^[I].ID) DO
	   INC( I )
	END ;
	IF I > NoStrRecs THEN
	   ProgramErrorAndHalt( 'RefStrInit: RefID not found.' )
	END ;
	WITH RefStrRecListPntr^[I] DO
	   StartRec := SRec ;
	   StartIdx := ORD( SPos ) ;
	   EndRec   := StartRec + ORD( ERec ) ;
	   EndIdx   := ORD( EPos ) ;
	END ;
   END GetRefStrRecInfo ;
   			
BEGIN
    RefStrRecListPntr	:= NIL ;
END RefStrInit .
