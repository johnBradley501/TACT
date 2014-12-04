IMPLEMENTATION MODULE ResArray;

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

FROM ResBase IMPORT
   (*type*) FilePos,
   (*var*)  ResourceOpen, ResourceFile, NullPos,
   (*proc*) OpenResourceFile, CloseResourceFile,
            ReadResourceBase, ReadResRecord, ReadResString;
FROM Utils IMPORT ALLOCATE,DEALLOCATE;

PROCEDURE FindFirst(ResType:      ResDataType;
                    ItemNo:       CARDINAL;
                VAR Error:        ResArrayError;
                VAR LocPntr:      ResourceArrayPntr;
                VAR pos:          CARDINAL;
                VAR fpos:         FilePos;
                VAR size:         CARDINAL): BOOLEAN;
VAR
   found:    BOOLEAN;
BEGIN
   Error := RANotOpen;
   IF NOT ResourceOpen THEN RETURN FALSE END;
   Error := RAOK;
   pos := ItemNo;
   found := FALSE;
   fpos := ResourcePntrs[ResType];
   REPEAT
      IF (fpos.high = NullPos.high) AND (fpos.low = NullPos.low) THEN
         Error := RATooHigh;
         RETURN FALSE
      END;
      LocPntr := NIL;
      IF NOT ReadResourceBase(0,fpos,LocPntr,size) THEN RETURN FALSE END;
      IF LocPntr^.ArraySize >= pos THEN
          found := TRUE
      ELSE
          pos := pos - (LocPntr^.ArraySize + 1);
          fpos := LocPntr^.NextArray;
          DEALLOCATE(LocPntr,size);
      END;
   UNTIL found;
   RETURN TRUE
END FindFirst;

PROCEDURE FindResource(ResType:    ResDataType;
                       ItemNo:     CARDINAL;
                   VAR Location:   FilePos;
                   VAR Error:      ResArrayError): BOOLEAN;
VAR
   LocPntr: ResourceArrayPntr;
   size:    CARDINAL;
   pos:     CARDINAL;
   fpos:    FilePos;
BEGIN
   IF NOT FindFirst(ResType,ItemNo,Error,LocPntr,pos,fpos,size) THEN
       RETURN FALSE
   END;
   Location := LocPntr^.Locations[pos];
   DEALLOCATE(LocPntr,size);
   IF (Location.high <> NullPos.high) OR (Location.low <> NullPos.low) THEN
      RETURN TRUE
   ELSE
      Error := RANotUsed;
      RETURN FALSE
   END
END FindResource;

PROCEDURE ScanResources(ResType:     ResDataType;
                        First, Last: CARDINAL;
                        Action:      ScanActionProcedure;
                    VAR Error:       ResArrayError): BOOLEAN;
VAR
   LocPntr: ResourceArrayPntr;
   size:    CARDINAL;
   pos:     CARDINAL;
   fpos:    FilePos;
   j:       CARDINAL;
   loc:     FilePos;
BEGIN
   IF NOT FindFirst(ResType,First,Error,LocPntr,pos,fpos,size) THEN
       RETURN FALSE
   END;
   Error := RAOK;
   FOR j := First TO Last DO
      loc := LocPntr^.Locations[pos];
      IF (loc.high <> NullPos.high) OR (loc.low <> NullPos.low) THEN
         Action(ResType,j,loc,Error);
         IF Error <> RAOK THEN RETURN FALSE END;
      END;
      INC(pos);
      IF pos > LocPntr^.ArraySize THEN
         fpos := LocPntr^.NextArray;
         DEALLOCATE(LocPntr,size);
         pos := 0;
         IF (fpos.high = NullPos.high) AND (fpos.low = NullPos.low) THEN
            RETURN TRUE
         END;
         LocPntr := NIL;
         IF NOT ReadResourceBase(0,fpos,LocPntr,size) THEN RETURN FALSE END;
      END;
   END;
   DEALLOCATE(LocPntr,size);
   RETURN TRUE
END ScanResources;

BEGIN
    ResourceName[MessageResource] := 'MSG';
    ResourceName[DataArrayResource] := 'DTA';
    ResourceName[MenuResource] := 'MNU';
    ResourceName[HelpResource] := 'HLP';
    ResourceName[ChoiceResource] := 'CHE';
    ResourceName[NumberArrayResource] := 'NAR';
END ResArray.
