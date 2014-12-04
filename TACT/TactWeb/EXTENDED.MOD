IMPLEMENTATION MODULE ExtendedAsciiKeys ;
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



FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) ReleaseCollection,NextColItem;
(*
EXPORT QUALIFIED
   MaxKeyNameLen, KeyName, CharacterEntry,
   MaxBASICEntries, KeyBASICTable,
   MaxALTEntries, KeyALTTable,
   MaxSHIFTEntries, KeySHIFTTable,
   MaxCTRLEntries, KeyCTRLTable,
   InitializeExt;

CONST
   MaxKeyNameLen = 5;
   MaxBASICEntries = 52;
   MaxALTEntries = 48;
   MaxSHIFTEntries = 11;
   MaxCTRLEntries = 48;

TYPE
   KeyName = ARRAY[0..MaxKeyNameLen] OF CHAR;
   CharacterEntry = RECORD
                       Ext:      BOOLEAN;
                       Cde:      CHAR;
                       Name:     KeyName;
                    END;
   KeyBASICType = RECORD
               Data:  ARRAY[0..MaxBASICEntries-1] OF CharacterEntry;
               END;
   KeyALTType = RECORD
               Data:  ARRAY[0..MaxALTEntries-1] OF CharacterEntry;
               END;
   KeySHIFTType = RECORD
               Data:  ARRAY[0..MaxSHIFTEntries-1] OF CharacterEntry;
               END;
   KeyCTRLType = RECORD
               Data:  ARRAY[0..MaxCTRLEntries-1] OF CharacterEntry;
               END;

VAR
   KeyBASICTable:  KeyBASICType;
   KeyALTTable:  KeyALTType;
   KeySHIFTTable:  KeySHIFTType;
   KeyCTRLTable:  KeyCTRLType;
*)

PROCEDURE InitializeExt;
VAR
   ResC:    ResCollectionType;
   dummy:   BOOLEAN;
   i:       CARDINAL;
   dummycard:CARDINAL;
BEGIN
   GetDataArray( 5, ResC);

   FOR i := 0 TO MaxBASICEntries-1 DO
      dummy := NextColItem(ResC,KeyBASICTable.Data[i],dummycard)
   END;

   FOR i := 0 TO MaxALTEntries-1 DO
      dummy := NextColItem(ResC,KeyALTTable.Data[i],dummycard)
   END;

   FOR i := 0 TO MaxSHIFTEntries-1 DO
      dummy := NextColItem(ResC,KeySHIFTTable.Data[i],dummycard)
   END;

   FOR i := 0 TO MaxCTRLEntries-1 DO
      dummy := NextColItem(ResC,KeyCTRLTable.Data[i],dummycard)
   END;

   ReleaseCollection(ResC);
END InitializeExt;

END ExtendedAsciiKeys .
