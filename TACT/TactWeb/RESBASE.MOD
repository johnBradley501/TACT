IMPLEMENTATION MODULE ResBase;
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


IMPORT FIO;
(*
FROM FileIO IMPORT
    File, FilePos, IOModeType, Open, Close, SetPos, ReadNBytes;
IMPORT FileIO;
*)
FROM SYSTEM IMPORT ADR, SIZE,ADDRESS,BYTE;
IMPORT Utils;
FROM ResArray IMPORT
   (*var*)  ResourcePntrs;

  PROCEDURE ConvertFilePos( pos : FilePos ) : LONGCARD ;
    (* interchanges order of cardinals since can't use a TYPE transfer and
       FilePos is "hardcoded" in too many RES modules -- L.Presutti, June 88
    *)
    TYPE
	LongCardPos = RECORD
			low, high : CARDINAL ; (* switched order! *)
		     END ;
    VAR
	TempPos : LongCardPos ;
    BEGIN
	TempPos.high := pos.high ;
	TempPos.low  := pos.low ;
	RETURN LONGCARD( TempPos ) ;   (* use TYPE cast *)
    END ConvertFilePos ;

PROCEDURE OpenResourceFile(FName:    ARRAY OF CHAR;
                       VAR BRes:     CARDINAL): BOOLEAN;
VAR
   Result:         CARDINAL;
   i:              CARDINAL;
   Place:          ADDRESS;
BEGIN
   FIO.IOcheck := FALSE;
   ResourceFile := FIO.OpenRead(FName);
   BRes := FIO.IOresult();
(* m.s.  BRes := Utils.BResultType(Result); *)
   IF BRes <> 0 THEN RETURN FALSE END;
   ResourceOpen := TRUE;
   Place := ADR(ResourcePntrs);
   RETURN ReadResourceBase(SIZE(ResourcePntrs),NullPos,Place,i);
END OpenResourceFile;

PROCEDURE CloseResourceFile;
BEGIN
   IF ResourceOpen THEN FIO.Close(ResourceFile) END;
   ResourceOpen := FALSE;
END CloseResourceFile;

PROCEDURE ReadResourceBase(NumberExpected:   CARDINAL;
                           Location:         FilePos;
                       VAR Data:             ADDRESS;
                       VAR NumberGot:        CARDINAL): BOOLEAN;
VAR
   size:           CARDINAL;
   ngot:           CARDINAL;
BEGIN
   IF NOT ResourceOpen THEN RETURN FALSE END;
   FIO.Seek( ResourceFile, ConvertFilePos( Location ));
   IF FIO.IOresult() <> 0 THEN RETURN FALSE END;

   ngot := FIO.RdBin( ResourceFile, size, SIZE(size));
   IF FIO.IOresult() <> 0 THEN RETURN FALSE END;
   IF NumberExpected <> 0 THEN
      IF size <> NumberExpected THEN RETURN FALSE END;
   END;

   IF Data = NIL THEN Utils.ALLOCATE(Data,size) END;
   NumberGot := FIO.RdBin( ResourceFile, Data^, size);
   RETURN FIO.IOresult() = 0;
END ReadResourceBase;

PROCEDURE ReadResRecord(VAR Data:     ARRAY OF BYTE;
                            Location: FilePos): BOOLEAN;
VAR i:    CARDINAL;
    Place:ADDRESS;
BEGIN
   Place := ADR(Data);
   RETURN ReadResourceBase(HIGH(Data),Location,Place,i);
END ReadResRecord;

PROCEDURE ReadResString(VAR Data:     ARRAY OF CHAR;
                            Location: FilePos): BOOLEAN;
VAR
   size:           CARDINAL;
   ngot:           CARDINAL;
BEGIN
   IF NOT ResourceOpen THEN RETURN FALSE END;
   FIO.Seek( ResourceFile, ConvertFilePos( Location ));
   IF FIO.IOresult() <> 0 THEN RETURN FALSE END;

   ngot := FIO.RdBin( ResourceFile, size, SIZE(size));
   IF FIO.IOresult() <> 0 THEN RETURN FALSE END;
(* IF size > HIGH(Data) THEN size := HIGH(Data) END; *)
   IF size > HIGH(Data)+1 THEN size := HIGH(Data)+1 END;

   ngot := FIO.RdBin( ResourceFile, Data, size);
   RETURN FIO.IOresult() = 0;
END ReadResString;

BEGIN
   ResourceOpen := FALSE;
   NullPos.high := 0; NullPos.low := 0;
END ResBase.
