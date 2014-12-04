IMPLEMENTATION MODULE STANDARD ;

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
(*V1=Mod2 Modula-2 version 2 *)
(*V2=Mod3 Modula-2 version 3 *)
(*V3=Modf Modula-2 FTL version *)
(*V4=Modl Modula-2 Logitech version *)

FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) ReleaseCollection,NextColItem;

PROCEDURE Initialize;
VAR
   ResC:    ResCollectionType;
   dummy:   BOOLEAN;
   i:       CARDINAL;
   dummycard:CARDINAL;

BEGIN
   GetDataArray( 4, ResC);

   FOR i := 1 TO NumberChars DO
      dummy := NextColItem(ResC,SortedCharNames[i],dummycard)
   END;

   FOR i := 0 TO HighCharacterCode DO
      dummy := GetNextDataArrayStringItem(ResC,CharacterNameSet[i])
   END;

   dummy := GetNextDataArrayStringItem(ResC,UpperCharList);
   dummy := GetNextDataArrayStringItem(ResC,LowerCharList);

   ReleaseCollection(ResC);
END Initialize;
END STANDARD .
