MODULE ResNew;

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
FROM SYSTEM IMPORT ADR;
IMPORT FIO;
IMPORT Str;

CONST
   ResStr = '(*RES';
   ResOldStr = '(*RES OLD';
   ResRemStr = '(*RES REM INS*)';
   ResNewStr = '(*RES NEW';
   ResInsStr = '(*RES INS*)';

TYPE
   TxtPtrType= POINTER TO ARRAY[0..255] OF CHAR;

VAR
   TxtP:  TxtPtrType;
   Txt:   ARRAY[0..255] OF CHAR;
   Val:   ARRAY[0..30] OF CHAR;
   i,j:   CARDINAL;
   InsF:  BOOLEAN;

PROCEDURE HandleResOld;
VAR j,k:   CARDINAL;
BEGIN
   j := Str.Length(ResOldStr);
   Str.Delete(TxtP^,0,j);
   Str.Insert(TxtP^,ResNewStr,0);

   (* skip past "MSG"... *)

   WHILE TxtP^[j] = ' ' DO INC(j) END;
   WHILE TxtP^[j] <> ' ' DO INC(j) END;
   k := j;

   (* skip past number *)
   WHILE TxtP^[j] = ' ' DO INC(j) END;
   WHILE (TxtP^[j] >= '0') AND (TxtP^[j] <= '9' ) DO INC(j) END;
   Str.Delete(TxtP^,k,j - k);
END HandleResOld;

PROCEDURE HandleResRem;
VAR j,k:   CARDINAL;
BEGIN
   j := Str.Length(ResRemStr);
   Str.Delete(TxtP^,0,j);
   Str.Insert(TxtP^,ResInsStr,0);

   j := Str.Length(ResInsStr);
   k := j;
   (* skip past number *)

   WHILE TxtP^[j] = ' ' DO INC(j) END;
   WHILE (TxtP^[j] >= '0') AND (TxtP^[j] <= '9' ) DO INC(j) END;

   Str.Delete(TxtP^,k,j - k);
END HandleResRem;

BEGIN
   FIO.RdStr(FIO.StandardInput,Txt);
   WHILE NOT FIO.EOF DO
      InsF := FALSE;
      i := 0;
      TxtP := ADR(Txt[i]);
      i := Str.Pos(TxtP^,ResStr);
      WHILE i < MAX(CARDINAL) DO
         TxtP := ADR(Txt[i]);
         IF Str.Pos(TxtP^,ResOldStr) = 0 THEN     HandleResOld
         ELSIF Str.Pos(TxtP^,ResRemStr) = 0 THEN  HandleResRem
         ELSE
            FIO.WrStr(FIO.ErrorOutput,'Could not handle: ');
            FIO.WrStr(FIO.ErrorOutput,TxtP^);
            FIO.WrLn(FIO.ErrorOutput);
         END;
         INC(i);
         TxtP := ADR(Txt[i]);
         i := Str.Pos(TxtP^,ResStr);
      END;
      FIO.WrStr(FIO.StandardOutput,Txt);
      FIO.RdStr(FIO.StandardInput,Txt);
      FIO.WrLn(FIO.StandardOutput);
   END;
END ResNew.
