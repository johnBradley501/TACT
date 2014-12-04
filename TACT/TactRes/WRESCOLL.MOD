IMPLEMENTATION MODULE WResCollection;

(* copyright (c) 1987-96 John Bradley, University of Toronto *)

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

FROM SYSTEM IMPORT BYTE,ADR,ADDRESS;
FROM FileIO IMPORT FilePos;
IMPORT Lib;
FROM WResBase IMPORT
  (* proc *)   AppendResourceBase;
FROM ResCollection IMPORT ResDataPointer, ResCollectionType, ReleaseCollection;

PROCEDURE AppendNewItem(VAR ResC: ResCollectionType;
                    VAR ItemData:  ARRAY OF BYTE;
                        Size:      CARDINAL);
VAR
   l:     CARDINAL;
BEGIN
   IF Size = 0 THEN l := HIGH(ItemData) + 1
               ELSE l := Size END;
   WITH ResC^ DO
      Data^[CurPos] := CHR(l);
      INC(CurPos);
      Lib.Move(ADR(ItemData),ADR(Data^[CurPos]),l);
      CurPos := CurPos + l;
      Data^[CurPos] := CHR(l);
      INC(CurPos);
   END
END AppendNewItem;

PROCEDURE WriteResCollection(VAR ResC: ResCollectionType;
                             VAR Pos: FilePos): BOOLEAN;
VAR
    WriteResult:    BOOLEAN;
BEGIN
   IF ResC^.CurPos = 0 THEN
      WriteResult := FALSE
   ELSE
      WriteResult := AppendResourceBase(ResC^.CurPos,Pos,ResC^.Data)
   END;

   ReleaseCollection(ResC);
   RETURN WriteResult;
END WriteResCollection;

END WResCollection.
