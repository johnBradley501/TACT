IMPLEMENTATION MODULE WResBase;

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

FROM SYSTEM IMPORT ADR, SIZE, ADDRESS, BYTE;
IMPORT Str;
IMPORT FIO;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM FileIO IMPORT
    File, FileName, FilePos, IOModeType, IOResultType, SetEOF,
    Open, Create, Close, SetPos, ReadNBytes, WriteNBytes;
FROM ResBase IMPORT
   (*var*)  ResourceOpen, ResourceFile, NullPos,
   (*proc*) OpenResourceFile, CloseResourceFile,
            ReadResourceBase, ReadResRecord, ReadResString;
FROM ResArray IMPORT
   (*type*) ResDataType,ResourceArray,ResourceArrayPntr,
   (*var*)  ResourcePntrs;

PROCEDURE UOpenResourceFile(FName:    ARRAY OF CHAR): BOOLEAN;
VAR
   Result:         IOResultType;
   i:              CARDINAL;
   t:              ResDataType;
   sz:             CARDINAL;
   Place:          ADDRESS;
BEGIN
   IF FIO.Exists(FName) THEN
      Open(ResourceFile,FName,readwritemode,Result);
      IF Result <> OK THEN RETURN FALSE END;
   ELSE
      Create(ResourceFile,FName,FALSE,Result);
      IF Result <> OK THEN RETURN FALSE END;
      FOR t := MIN(ResDataType) TO MAX(ResDataType) DO
          ResourcePntrs[t] := NullPos
      END;
      sz := SIZE(ResourcePntrs);
      WriteNBytes(ResourceFile,ADR(sz),SIZE(sz),Result);
      IF Result <> OK THEN RETURN FALSE END;
      WriteNBytes(ResourceFile,ADR(ResourcePntrs),sz,Result);
      IF Result <> OK THEN RETURN FALSE END;
   END;
   ResourceOpen := TRUE;
   Place := ADR(ResourcePntrs);
   RETURN ReadResourceBase(SIZE(ResourcePntrs),NullPos,Place,i);
END UOpenResourceFile;

PROCEDURE NewResourceArrayItem(ASize:  CARDINAL;
                           VAR RP:     ResourceArrayPntr;
                           VAR BSize:  CARDINAL;
                           VAR Loc:    FilePos): BOOLEAN;
VAR  i:    CARDINAL;
BEGIN
    BSize := 6 + 4*ASize;
    ALLOCATE(RP,BSize);
    WITH RP^ DO
      ArraySize := ASize-1;
      NextArray := NullPos;
      FOR i := 0 TO ASize-1 DO
          Locations[i] := NullPos;
      END;
    END;
    RETURN AppendResourceBase(BSize,Loc,RP)
END NewResourceArrayItem;

PROCEDURE UpdateResourceBase(NumberToWrite:   CARDINAL;
                             Location:         FilePos;
                             Data:             ADDRESS): BOOLEAN;
VAR
   Result:         IOResultType;
   size,ngot:      CARDINAL;
   i:              CARDINAL;
BEGIN
   IF NOT ResourceOpen THEN RETURN FALSE END;
   SetPos(ResourceFile,Location,Result);
   IF Result <> OK THEN RETURN FALSE END;
   ReadNBytes(ResourceFile,ADR(size),SIZE(size),ngot,Result);
   IF size <> NumberToWrite THEN RETURN FALSE END;
   WriteNBytes(ResourceFile,Data,size,Result);
   RETURN Result = OK
END UpdateResourceBase;

PROCEDURE AppendResourceBase(NumberToWrite:    CARDINAL;
                         VAR Location:         FilePos;
                             Data:             ADDRESS): BOOLEAN;
VAR
   Result:         IOResultType;
   size,ngot:      CARDINAL;
   i:              CARDINAL;
BEGIN
   IF NOT ResourceOpen THEN RETURN FALSE END;
   SetEOF(ResourceFile,Location,Result);
   IF Result <> OK THEN RETURN FALSE END;
   WriteNBytes(ResourceFile,ADR(NumberToWrite),SIZE(NumberToWrite),Result);
   IF Result <> OK THEN RETURN FALSE END;
   WriteNBytes(ResourceFile,Data,NumberToWrite,Result);
   RETURN Result = OK
END AppendResourceBase;

PROCEDURE AppendResRecord(Data:     ARRAY OF BYTE;
                      VAR Location: FilePos): BOOLEAN;
BEGIN
   RETURN AppendResourceBase(HIGH(Data), Location, ADR(Data));
END AppendResRecord;

PROCEDURE AppendResString(Data:     ARRAY OF CHAR;
                      VAR Location: FilePos): BOOLEAN;
BEGIN
   RETURN AppendResourceBase(Str.Length(Data)+1, Location, ADR(Data));
END AppendResString;


END WResBase.

