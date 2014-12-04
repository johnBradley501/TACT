IMPLEMENTATION MODULE ResDataArray;
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


FROM ResBase IMPORT FilePos;
FROM Lib IMPORT FatalError;
FROM ResArray IMPORT
   (*type*) ResDataType,ResourceArray,ResourceArrayPntr,
            ResArrayError,ScanActionProcedure,
   (*var*)  ResourcePntrs,ResourceName,
   (*proc*) FindFirst,FindResource,ScanResources;

FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) GetCollection, NextColItem, PrevColItem;

PROCEDURE GetDataArray(ID:  CARDINAL;
                   VAR ResC:    ResCollectionType);
VAR
   Error:   ResArrayError;
   ColPos:  FilePos;
BEGIN
   IF NOT FindResource(DataArrayResource,ID,ColPos,Error) THEN
       FatalError('Fatal Resource Error (1) in GetDataArray')
   END;
   IF NOT GetCollection(ResC,ColPos) THEN
       FatalError('Fatal Resource Error (2) in GetDataArray')
   END;
END GetDataArray;

PROCEDURE GetNextDataArrayStringItem(VAR ResC:   ResCollectionType;
                                     VAR Text:   ARRAY OF CHAR): BOOLEAN;
VAR size:  CARDINAL;
BEGIN
   IF NOT NextColItem(ResC,Text,size) THEN RETURN FALSE END;
   IF size < HIGH(Text)+1 THEN Text[size] := 0C END;
   RETURN TRUE;
END GetNextDataArrayStringItem;

PROCEDURE GetPrevDataArrayStringItem(VAR ResC:   ResCollectionType;
                                     VAR Text:   ARRAY OF CHAR): BOOLEAN;
VAR size:  CARDINAL;
BEGIN
   IF NOT PrevColItem(ResC,Text,size) THEN RETURN FALSE END;
   IF size < HIGH(Text)+1 THEN Text[size] := 0C END;
   RETURN TRUE;
END GetPrevDataArrayStringItem;

END ResDataArray.
