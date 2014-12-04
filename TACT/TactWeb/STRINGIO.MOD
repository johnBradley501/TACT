IMPLEMENTATION MODULE StringIO ;
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


IMPORT Str;
VAR
   Blanks: ARRAY[0..19] OF CHAR;

PROCEDURE Pad(VAR str:  ARRAY OF CHAR;
                  clen: CARDINAL;
                  dlen: CARDINAL);
BEGIN
    Blanks[dlen - clen] := 0C;
    Str.Insert(str,Blanks,0);
    Blanks[dlen - clen] := ' ';
END Pad;

PROCEDURE SWriteString(VAR St:       ARRAY OF CHAR;
                       VAR Pos:      CARDINAL;
                       Data:     ARRAY OF CHAR;
                       Len:      CARDINAL);
VAR
    LSt:     CARDINAL;
    I:       CARDINAL;
BEGIN
   LSt :=  HIGH(St);
   I := 0;
   WHILE (Pos < LSt) AND (I <= HIGH(Data)) AND (Data[I] <> 0C) DO
      St[Pos] := Data[I];
      INC(I); INC(Pos);
   END;
   WHILE (Pos < LSt) AND (I < Len) DO
      St[Pos] := ' ';
      INC(Pos); INC(I);
   END;
   St[Pos] := 0C;
   END SWriteString;

PROCEDURE SWriteCard(VAR St:       ARRAY OF CHAR;
                       VAR Pos:      CARDINAL;
                       Data:     CARDINAL;
                       Len:      CARDINAL);
VAR
    TempData:        ARRAY[0..20] OF CHAR;
    I:               CARDINAL;

PROCEDURE CardToString(num: CARDINAL;
                   VAR str: ARRAY OF CHAR;
                       width: CARDINAL);
VAR  OK:   BOOLEAN;
     len:  CARDINAL;
BEGIN
   Str.CardToStr(LONGCARD(num),str,10,OK);
   IF (NOT OK) OR (width = 0) THEN RETURN END;
   len := Str.Length(str);
   IF len < width THEN Pad(str,len,width) END;
END CardToString;

BEGIN
   CardToString(Data,TempData,Len);
   I := 0;
   WHILE (Pos < HIGH(St)) AND (TempData[I] <> 0C) DO
      St[Pos] := TempData[I];
      INC(I); INC(Pos);
   END;
   St[Pos] := 0C;
END SWriteCard;

PROCEDURE SWriteInt(VAR St:       ARRAY OF CHAR;
                       VAR Pos:      CARDINAL;
                       Data:     INTEGER;
                       Len:      CARDINAL);
VAR
    TempData:        ARRAY[0..20] OF CHAR;
    I:               CARDINAL;

PROCEDURE IntToString(num: INTEGER;
                  VAR str: ARRAY OF CHAR;
                      width: CARDINAL);
VAR   OK:   BOOLEAN;
      len:  CARDINAL;
      temp: LONGINT;
BEGIN
   Str.IntToStr(LONGINT(num),str,10,OK);
   IF (NOT OK) OR (width = 0) THEN RETURN END;
   len := Str.Length(str);
   IF len < width THEN Pad(str,len,width) END;
END IntToString;

BEGIN
   IntToString(Data,TempData,Len);
   I := 0;
   WHILE (Pos < HIGH(St)) AND (TempData[I] <> 0C) DO
      St[Pos] := TempData[I];
      INC(I); INC(Pos);
   END;
   St[Pos] := 0C;
END SWriteInt;

PROCEDURE SWriteLongInt(VAR St:      ARRAY OF CHAR;
                       VAR Pos:      CARDINAL;
                       Data:         LONGINT;
                       Len:          CARDINAL);
VAR
    TempData:        ARRAY[0..20] OF CHAR;
    I:               CARDINAL;

PROCEDURE LongIntToString(num: LONGINT;
                      VAR str: ARRAY OF CHAR;
                          width: CARDINAL);
VAR
       OK:   BOOLEAN;
       len:  CARDINAL;
BEGIN
   Str.IntToStr(num,str,10,OK);
   IF (NOT OK) OR (width = 0) THEN RETURN END;
   len := Str.Length(str);
   IF len < width THEN Pad(str,len,width) END;
END LongIntToString;

BEGIN
   LongIntToString(Data,TempData,Len);
   I := 0;
   WHILE (Pos < HIGH(St)) AND (TempData[I] <> 0C) DO
      St[Pos] := TempData[I];
      INC(I); INC(Pos);
   END;
   St[Pos] := 0C;
END SWriteLongInt;


PROCEDURE SWriteLongCard(VAR St:     ARRAY OF CHAR;
                       VAR Pos:      CARDINAL;
                       Data:         LONGCARD;
                       Len:          CARDINAL);
VAR
    TempData:        ARRAY[0..20] OF CHAR;
    I:               CARDINAL;

PROCEDURE LongCardToString(num: LONGCARD;
                      VAR str: ARRAY OF CHAR;
                          width: CARDINAL);
VAR
       OK:   BOOLEAN;
       len:  CARDINAL;
BEGIN
   Str.CardToStr(num,str,10,OK);
   IF (NOT OK) OR (width = 0) THEN RETURN END;
   len := Str.Length(str);
   IF len < width THEN Pad(str,len,width) END;
END LongCardToString;

BEGIN
   LongCardToString(Data,TempData,Len);
   I := 0;
   WHILE (Pos < HIGH(St)) AND (TempData[I] <> 0C) DO
      St[Pos] := TempData[I];
      INC(I); INC(Pos);
   END;
   St[Pos] := 0C;
END SWriteLongCard;


PROCEDURE SWriteChar(VAR St:       ARRAY OF CHAR;
                     VAR Pos:      CARDINAL;
                     Data:     CHAR;
                     Len:      CARDINAL);
VAR
    LSt,  LData:     CARDINAL;
    I:               CARDINAL;
BEGIN
   IF Data = 0C THEN RETURN; END;
   LSt :=  HIGH(St);
   IF (Pos < LSt) THEN
      St[Pos] := Data;
      INC(Pos);
   END;
   I := 1;
   WHILE (Pos < LSt) AND (I < Len) DO
      St[Pos] := ' ';
      INC(Pos); INC(I);
   END;
   St[Pos] := 0C;
   END SWriteChar;

BEGIN
   Blanks := '                    ';
END StringIO .
