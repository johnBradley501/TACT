IMPLEMENTATION MODULE TokenHandling;

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

IMPORT FIO;
FROM TDBBase IMPORT MaxNoMergeFiles, HRecPntr, InSeek, GetRec,
                    InFile,NoInFiles, InFileDataType,
                    OutFileRec, OutPos, OutHeader, WriteDBRec,
                    OutFile, OutFileName;
FROM HyperDataModel IMPORT
     HNoOccurs, HOccurData, HNoTokens, HyperData, HyperLength, HTokenData,
     HCompTokenData;
FROM TypeHandling IMPORT
     SetupTypeTranslation, NewTypeForOld, FinishTypeTranslation;
FROM LogHandling IMPORT NewLogsForOld;
FROM TextHandling IMPORT StartTextPos;
FROM ResMessages IMPORT MsgCard, PutResError;
FROM Windows  IMPORT
  (* Vars  *) TerminationProc;
FROM HRecPntrTranslation IMPORT CleanUpXFiles;

PROCEDURE HandleTokens;
VAR
   DBNo:     CARDINAL;
   InHRec:   HRecPntr;
   OutHRec:  HRecPntr;
   wtoken:   HTokenData;

PROCEDURE NewTextForOld(DBNo:  CARDINAL;
                    VAR PRec:  CARDINAL;
                    VAR PIdx:  CARDINAL);
VAR t:  LONGCARD;
BEGIN
    t := StartTextPos[DBNo] +
         LONGCARD(PRec - InFile[DBNo].Header.BeginText) * HyperLength +
         LONGCARD(PIdx);
    PRec := CARDINAL(t DIV HyperLength);
    PIdx := CARDINAL(t MOD HyperLength);
END NewTextForOld;

PROCEDURE DecompressTokenInfo(DBNo:       CARDINAL;
                              TokenRecNo: CARDINAL;
                          VAR Result:   HTokenData);
VAR
    temp:     CARDINAL;
    wtoken:   HTokenData;
BEGIN
   WITH InFile[DBNo].Rec DO
      Result.HRecNo  := TokenData[TokenRecNo].HRecNo;
      Result.HRecPos := TokenData[TokenRecNo].HRecPos;

      temp := BaseTextPos + TokenData[TokenRecNo].TOffset;
      Result.TRecNo  := temp DIV HyperLength + BaseTextRec;
      Result.TRecPos := temp MOD HyperLength;

      temp := BaseLogPos + ORD(TokenData[TokenRecNo].LOffset);
      Result.LRecNo  := temp DIV 256 + BaseLogRec;
      Result.LRecPos := CHR(temp MOD 256);
   END;
END DecompressTokenInfo;

PROCEDURE AddTokenToDB( In:     HTokenData);
BEGIN
   WITH OutFileRec DO
      IF OutPos.Idx >= HNoTokens THEN
         WriteDBRec ;
         BaseTextRec := In.TRecNo;
         BaseTextPos := In.TRecPos;
         BaseLogRec := In.LRecNo;
         BaseLogPos := ORD(In.LRecPos);
      END ;
      TokenData[OutPos.Idx].HRecNo  := In.HRecNo ;
      TokenData[OutPos.Idx].HRecPos := In.HRecPos ;

      TokenData[OutPos.Idx].TOffset :=
                    (In.TRecNo - BaseTextRec) * HyperLength +
                     In.TRecPos - BaseTextPos;
      TokenData[OutPos.Idx].LOffset := CHR(
                    (In.LRecNo - BaseLogRec) * 256 (* # Log Records *) +
                     ORD(In.LRecPos) - BaseLogPos) ; (* used as 1 byte number *)
      INC(OutPos.Idx) ;
   END;
END AddTokenToDB ;

BEGIN
   (* this code assumes that the previous output record has *not* been
      written out yet  j.b. *)

   OutHeader.BeginToken := OutPos.Rec + 1;
   OutPos.Idx := MAX(CARDINAL);
   FOR DBNo := 0 TO NoInFiles DO
      SetupTypeTranslation(DBNo);
      WITH InFile[DBNo] DO
         InSeek(DBNo, Header.BeginToken);
         GetRec(DBNo);
         WHILE (Pos < Header.EndTokenRec) OR
         ((Pos = Header.EndTokenRec) AND (Idx <= Header.EndTokenIdx)) DO
            IF Idx >= HNoTokens THEN
               GetRec(DBNo);
            END;
            DecompressTokenInfo(DBNo,Idx,wtoken);

            IF (wtoken.HRecNo = 0) AND (wtoken.HRecPos = 0C) THEN
               (*RES OLD MSG 284
               Input database number %0 was created by an earlier version of MakeBase and so
               cannot be used by MergeBas. Please recreate with the current version of MakeBase.
               *)
               MsgCard(DBNo + 1,0);
               PutResError( (*RES REM INS*) 284 );
               FIO.Close(OutFile);
               FIO.Erase(OutFileName);
               CleanUpXFiles;
               TerminationProc;
               HALT;
            END;
            InHRec.Rec := wtoken.HRecNo;
            InHRec.Idx := ORD(wtoken.HRecPos);
            NewTypeForOld(InHRec,OutHRec);
            wtoken.HRecNo := OutHRec.Rec;
            wtoken.HRecPos := CHR(OutHRec.Idx);

            InHRec.Rec := wtoken.LRecNo;
            InHRec.Idx := ORD(wtoken.LRecPos);
            NewLogsForOld(DBNo, InHRec, OutHRec);
            wtoken.LRecNo := OutHRec.Rec;
            wtoken.LRecPos := CHR(OutHRec.Idx);

            NewTextForOld(DBNo,wtoken.TRecNo, wtoken.TRecPos);

            AddTokenToDB(wtoken);
            INC(Idx);
         END;
      END;
      FinishTypeTranslation;
   END;
   OutHeader.EndTokenRec := OutPos.Rec ;
   OutHeader.EndTokenIdx := OutPos.Idx - 1 ;  (* *LP* *)
   WriteDBRec;
END HandleTokens;

END TokenHandling.
