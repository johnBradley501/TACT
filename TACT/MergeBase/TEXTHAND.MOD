IMPLEMENTATION MODULE TextHandling;

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

IMPORT Lib;
FROM HyperDataModel IMPORT HyperLength, HyperData;
FROM TDBBase IMPORT
             HRecPntr, OutFileRec, OutPos, WriteDBRec, NoInFiles, OutHeader,
             NoInFiles, InFile, InSeek, GetRec;

PROCEDURE HandleText;
VAR
  No:   CARDINAL;

PROCEDURE WriteRec(VAR In:  HyperData;
                       Len: CARDINAL);
VAR L1:    CARDINAL;
BEGIN
   IF (OutPos.Idx = 0) AND (Len = HyperLength) THEN
       Lib.Move(ADR(In),ADR(OutFileRec),HyperLength);
       WriteDBRec;
   ELSIF OutPos.Idx + Len >= HyperLength THEN
       L1 := HyperLength - OutPos.Idx;
       Lib.Move(ADR(In),ADR(OutFileRec.TextData[OutPos.Idx]),L1);
       WriteDBRec;
       IF Len-L1 > 0 THEN
          Lib.Move(ADR(In.TextData[L1]), ADR(OutFileRec),Len-L1) ;
          OutPos.Idx := Len - L1 ;
       END;
   ELSE
      Lib.Move(ADR(In),ADR(OutFileRec.TextData[OutPos.Idx]),Len);
      INC(OutPos.Idx,Len);
   END;
END WriteRec;

BEGIN
   OutHeader.BeginText := OutPos.Rec;
   FOR No := 0 TO NoInFiles DO
      WITH InFile[No] DO
         StartTextPos[No] := LONGCARD(OutPos.Rec) * HyperLength +
                             LONGCARD(OutPos.Idx);
         InSeek(No, Header.BeginText);
         GetRec(No);
         WHILE Pos <= Header.EndTextRec DO
            IF Pos = Header.EndTextRec THEN WriteRec(Rec, Header.EndTextIdx)
            ELSE WriteRec(Rec, HyperLength) END;
            GetRec(No);
         END;
      END;
   END;
   IF OutPos.Idx <> 0 THEN
      OutHeader.EndTextRec := OutPos.Rec;
      OutHeader.EndTextIdx := OutPos.Idx-1;
      WriteDBRec;
   ELSE
      OutHeader.EndTextRec := OutPos.Rec-1;
      OutHeader.EndTextIdx := HyperLength;
   END;
END HandleText;

END TextHandling.
