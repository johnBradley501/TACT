IMPLEMENTATION MODULE WResArray;

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

IMPORT Str;
IMPORT IO;
FROM SYSTEM IMPORT BYTE,ADDRESS,SIZE,ADR;
FROM FileIO IMPORT File,FilePos;
FROM Storage IMPORT ALLOCATE,DEALLOCATE;

FROM ResBase IMPORT
   (*var*)  ResourceOpen, ResourceFile, NullPos,
   (*proc*) OpenResourceFile, CloseResourceFile,
            ReadResourceBase, ReadResRecord, ReadResString;

FROM ResArray IMPORT
   (*type*) ResDataType,ResourceArray,ResourceArrayPntr,
            ResArrayError,ScanActionProcedure,
   (*var*)  ResourcePntrs,ResourceName,
   (*proc*) FindFirst,FindResource,ScanResources;

FROM WResBase IMPORT
  (* proc *)   UOpenResourceFile,NewResourceArrayItem,
               UpdateResourceBase,AppendResourceBase,
               AppendResRecord,AppendResString;

TYPE
    ResourceDataType = RECORD
       CurrentPos:      FilePos;
       NextPos:         FilePos;
       RP:              ResourceArrayPntr;
       BSize:           CARDINAL;
       NewItemNo:       CARDINAL;
       ARecSize:        CARDINAL;
       CurrentFree:     CARDINAL;
       Changed:         BOOLEAN;
    END;

VAR
    ResourceData:     ARRAY[MIN(ResDataType)..MAX(ResDataType)] OF
                           ResourceDataType;
    AllocSize:        ARRAY[MIN(ResDataType)..MAX(ResDataType)] OF CARDINAL;

PROCEDURE OutputErrorMessage(TypeText: ARRAY OF CHAR);
BEGIN
    IO.WrStr('**ERROR** ');
    IO.WrStr(TypeText);
    IO.WrStr(' ');
    IO.WrStr('In WRESARRAY');
    IO.WrLn;
END OutputErrorMessage;

PROCEDURE InitialResArrayData;
VAR i:    ResDataType;
BEGIN
    FOR i := MIN(ResDataType) TO MAX(ResDataType) DO
         ResourceData[i].NextPos := ResourcePntrs[i];
         ResourceData[i].NewItemNo := 1;
         ResourceData[i].Changed := FALSE;
         ResourceData[i].RP := NIL;
         ResourceData[i].CurrentFree := 0;
         ResourceData[i].ARecSize := 0;
    END;
END InitialResArrayData;

PROCEDURE FindFreeResource(RType:     ResDataType;
                      VAR  FreeID:    CARDINAL): BOOLEAN;
VAR
       TRP:              ResourceArrayPntr;
       TBSize:           CARDINAL;
       done:             BOOLEAN;
BEGIN
    WITH ResourceData[RType] DO
       done := FALSE;
       REPEAT
          IF NewItemNo >= ARecSize THEN
             TRP := NIL;
             IF (NextPos.high = NullPos.high) AND
             (NextPos.low = NullPos.low) THEN
                IF NOT NewResourceArrayItem(AllocSize[RType],
                TRP,TBSize,NextPos) THEN
                      OutputErrorMessage('In UpdateResourceBase');
                      RETURN FALSE;
                END;
(*              ARecSize := AllocSize[RType];  *)
                IF RP <> NIL THEN
                   RP^.NextArray := NextPos;
                   IF NOT UpdateResourceBase(BSize,CurrentPos,RP) THEN
                      OutputErrorMessage('In UpdateResourceBase');
                      RETURN FALSE;
                   END;
                   Changed := FALSE
                ELSE
                   ResourcePntrs[RType] := NextPos;
                   IF NOT UpdateResourceBase
                   (SIZE(ResourcePntrs),NullPos,ADR(ResourcePntrs)) THEN
                      OutputErrorMessage('In UpdateResourceBase');
                      RETURN FALSE;
                   END;
                END
             ELSE
                IF NOT ReadResourceBase(0,NextPos,TRP,TBSize) THEN
                    OutputErrorMessage('In ReadResourceBase');
                    RETURN FALSE
                END
             END;
             IF Changed THEN
                IF NOT UpdateResourceBase(BSize,CurrentPos,RP) THEN
                    OutputErrorMessage('In UpdateResourceBase');
                    RETURN FALSE
                END;
             END;
             IF RP <> NIL THEN DEALLOCATE(RP,BSize) END;
             BSize := TBSize;
             CurrentPos := NextPos;
             RP := TRP;
             NextPos := RP^.NextArray;
             NewItemNo := 0;
             Changed := FALSE;
             ARecSize := RP^.ArraySize + 1
          END;
          IF (RP^.Locations[NewItemNo].high = NullPos.high) AND
          (RP^.Locations[NewItemNo].low = NullPos.low) THEN
             done := TRUE
          ELSE
             INC(NewItemNo);
             INC(CurrentFree);
          END
       UNTIL done;
       FreeID := CurrentFree;
    END;
    RETURN TRUE
END FindFreeResource;

PROCEDURE UseCurrentFree(RType:     ResDataType;
                         Data:    FilePos);
BEGIN
    WITH ResourceData[RType] DO
         IF (RP^.Locations[NewItemNo].high <> NullPos.high) OR
         (RP^.Locations[NewItemNo].high <> NullPos.high) THEN
              OutputErrorMessage('In UseCurrentFree');
              RETURN
         END;
         RP^.Locations[NewItemNo] := Data;
         Changed := TRUE
    END;
END UseCurrentFree;

PROCEDURE UpdateResource(RType:     ResDataType;
                         RNum:      CARDINAL;
                         NewPos:    FilePos): BOOLEAN;
VAR
    Error:        ResArrayError;
    LocPntr:      ResourceArrayPntr;
    pos:          CARDINAL;
    fpos:         FilePos;
    size:         CARDINAL;

BEGIN
    WITH ResourceData[RType] DO
       IF Changed THEN
          IF NOT UpdateResourceBase(BSize,CurrentPos,RP) THEN
              OutputErrorMessage('In UpdateResourceBase');
              RETURN FALSE
          END;
          Changed := FALSE
       END
    END;
    IF NOT FindFirst(RType,RNum,Error,LocPntr,pos,fpos,size) THEN
       OutputErrorMessage('Item to delete not present');
       RETURN FALSE;
    END;
    LocPntr^.Locations[pos] := NewPos;
    IF NOT UpdateResourceBase(size,fpos,LocPntr) THEN
        OutputErrorMessage('In UpdateResourceBase');
        RETURN FALSE
    END;
    DEALLOCATE(LocPntr,size);

    WITH ResourceData[RType] DO
       IF ((CurrentPos.high <> NullPos.high) OR 
       (CurrentPos.low <> NullPos.low)) AND (RP <> NIL) THEN
          IF NOT ReadResourceBase(BSize,CurrentPos,RP,BSize) THEN
             OutputErrorMessage('In ReadResourceBase');
             RETURN FALSE
          END
       END
    END;
    RETURN TRUE
END UpdateResource;

PROCEDURE DeleteResource(RType:     ResDataType;
                         RNum:      CARDINAL): BOOLEAN;
BEGIN
   RETURN UpdateResource(RType,RNum,NullPos);
END DeleteResource;

PROCEDURE WindUpResources;
VAR
    i:                ResDataType;
BEGIN
    FOR i := MIN(ResDataType) TO MAX(ResDataType) DO
       WITH ResourceData[i] DO
          IF Changed THEN
             IF NOT UpdateResourceBase(BSize,CurrentPos,RP) THEN
                 OutputErrorMessage('In UpdateResourceBase');
                 RETURN
             END
          END
       END
    END;
END WindUpResources;

PROCEDURE GetResType(Word:      ARRAY OF CHAR;
                 VAR ResType:   ResDataType): BOOLEAN;
VAR
    i:                ResDataType;
BEGIN
    FOR i := MIN(ResDataType) TO MAX(ResDataType) DO
       IF Str.Compare(Word,ResourceName[i]) = 0 THEN
          ResType := i;
          RETURN TRUE
       END
    END;
RETURN FALSE
END GetResType;

BEGIN
    AllocSize[MessageResource] := 20;
    AllocSize[DataArrayResource] := 5;
    AllocSize[MenuResource] := 5;
    AllocSize[HelpResource] := 20;
    AllocSize[ChoiceResource] := 10;
    AllocSize[NumberArrayResource] := 2;
END WResArray.
