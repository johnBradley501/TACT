IMPLEMENTATION MODULE LogHandling;

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

FROM SYSTEM IMPORT ADR;
IMPORT Lib, Str;
FROM TDBBase IMPORT MaxNoMergeFiles, HRecPntr, InSeek, GetRec, RefsNamePntr,
                    FileNID,InFile,NoInFiles, InFileDataType,
                    RefsNameData, RefsNames, OutFileRec, OutPos, OutHeader,
                    WriteDBRec, NoRefIDs, RefsNamePntr;
FROM StringHandling IMPORT WheresTitle, TitleNoWords, StringFirstItem;
FROM HRecPntrTranslation IMPORT
   XRecInfo, XRecInfoPntr, ToRecDataType, ToRecPntrType,
   SetupToRecPntr, DisposeToRecPnts;

FROM HyperDataModel IMPORT HLogDataType, HyperData, MaxNoLogData;
FROM GlobalDefs IMPORT StrAny;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM ErrorBase IMPORT ProgramErrorAndHalt;

CONST
   MaxCurVal = 100;
   MaxNoLogs = ORD( MaxNoLogData ) + 1 ;	(* since 0 based *)
   MaxLogDataIndex = ORD( MaxNoLogData ) ;	(* was 255 now 254 *)

(* the following is the structure of the log data as defined in HYPERDAT.DEF:
TYPE
    HLogDataType = RECORD
                     StructID : SHORTINT ;
                     TokenNoOffset : SHORTCARD ; (* successive relative offset *)
                     CASE : CARDINAL OF
                       1 : SRecPos : CHAR ;  (* Pos * 4 to real start of data *)
                           SRecNo  : CHAR |  (* base index to Strings data    *)
                       2 : Count   : CARDINAL ; (* note use of CARDINAL overlay *)
                     END ;
                   END ;

    HyperData = RECORD
                   CASE : HyperRType OF
                           ...
                      HLogList :
			 BaseTokenNo : LONGCARD ;
                         LogData : ARRAY[0C..376C] OF HLogDataType  |
                   END  (* CASE HyperRType OF *)
                END ;
*)

VAR
    LogBegin	: ARRAY[0..MaxNoMergeFiles-1] OF LONGCARD;
    MapValue	: LONGCARD;

PROCEDURE MakeRealOffset(data:   HRecPntr;
                         srec:   CARDINAL;
                         norefs: CARDINAL): LONGCARD;
BEGIN
   RETURN LONGCARD(data.Rec - srec) * LONGCARD(MaxNoLogs-norefs) +
          LONGCARD(data.Idx - norefs)
END MakeRealOffset;

PROCEDURE HandleLog;
VAR DBNo:       CARDINAL;
    CurVal:     ARRAY[1..MaxCurVal] OF HLogDataType;
    ToRec:      ARRAY[1..MaxCurVal] OF ToRecPntrType;
    CurLogItem: HRecPntr;
    FirstItem:  BOOLEAN;
    tlog:       HLogDataType;
    CurrTokenNo  : LONGCARD;
    DBCurrTokenNo: LONGCARD;

PROCEDURE GetToRecs;
VAR i:   INTEGER;
    c:   CARDINAL;
    r:   ToRecPntrType;
BEGIN
   FOR c := 1 TO MaxCurVal DO ToRec[c] := NIL END;
   WHILE SetupToRecPntr(DBNo,i,r) DO ToRec[ABS(i)] := r END;
END GetToRecs;

PROCEDURE DiscardToRecs;
VAR c:   CARDINAL;
BEGIN
   FOR c := 1 TO MaxCurVal DO
      IF ToRec[c] <> NIL THEN DisposeToRecPnts(ToRec[c]) END;
   END;
END DiscardToRecs;

PROCEDURE XlateLogEntry(Old:  HLogDataType;
                    VAR New:  HLogDataType);
VAR
   AbsOldID : CARDINAL;
   xrec:      XRecInfoPntr;
BEGIN
   AbsOldID := ABS( INTEGER(Old.StructID) );
   WITH InFile[DBNo] DO
      New.StructID := SHORTINT( RefIDL^[AbsOldID]^.ID );
      New.TokenNoOffset := Old.TokenNoOffset;	(* >> will this work across files ??? << *)
      IF Old.StructID >= 0 THEN
          New.Count := Old.Count
      ELSE
          xrec := ToRec[AbsOldID]^.RecData[ORD(Old.SRecNo)];
          WITH xrec^.NewLoc[ORD(Old.SRecPos)-xrec^.IOffset-1] DO
             New.SRecPos := CHR(Idx);
             New.SRecNo := CHR(Rec);
          END;
      END;
   END;
END XlateLogEntry;


PROCEDURE InitialCurVals;
VAR i,j:   CARDINAL;
    tlog:  HLogDataType;
BEGIN
   FOR i := 1 TO NoRefIDs-1 DO
     IF StringFirstItem[i] <> 0 THEN
        CurVal[i].StructID := -SHORTINT(i);
        CurVal[i].SRecNo := 0C;
        CurVal[i].SRecPos := CHR(StringFirstItem[i]);
     ELSE
        CurVal[i].StructID := SHORTINT(i);
        CurVal[i].Count := 0
     END;
     CurVal[i].TokenNoOffset := 0 ;
   END;
   WITH InFile[DBNo] DO
      FOR i := 1 TO RefIDN DO
          XlateLogEntry(Rec.LogData[CHR(i)],tlog);
          j := ABS( INTEGER(tlog.StructID) );
          CurVal[j] := tlog;
      END;
   END;

   j := ABS(FileNID);
   IF (WheresTitle[DBNo].Rec <> 0) OR (WheresTitle[DBNo].Idx <> 0) THEN
      CurVal[j].SRecPos := CHR(WheresTitle[DBNo].Idx);
      CurVal[j].SRecNo := CHR(WheresTitle[DBNo].Rec);
      CurVal[j].TokenNoOffset := 0 ;
   END;
END InitialCurVals;

PROCEDURE WriteAllInitials;
VAR i,j:   CARDINAL;
BEGIN
   OutFileRec.BaseTokenNo := CurrTokenNo ;
   OutFileRec.LogData[0C].StructID := 0;
   OutFileRec.LogData[0C].Count := 0;
   OutFileRec.LogData[0C].TokenNoOffset := 0;
   FOR i := 1 TO NoRefIDs-1 DO (* RefIDs are 0 based: 0 is word count *)
      OutFileRec.LogData[CHR(i)] := CurVal[i] ;
      OutFileRec.LogData[CHR(i)].TokenNoOffset := 0 ;	(* reset offset to proper vals *)
   END;
   OutPos.Idx := NoRefIDs;
END WriteAllInitials;

PROCEDURE PutLogItem(data: HLogDataType);
BEGIN
   IF OutPos.Idx > MaxLogDataIndex THEN
      WriteDBRec;
      WriteAllInitials;
   END;
   OutFileRec.LogData[CHR(OutPos.Idx)] := data;
   CurVal[ABS( INTEGER(data.StructID) )] := data;
   INC( CurrTokenNo, LONGCARD(data.TokenNoOffset) ) ;
   INC(OutPos.Idx);
END PutLogItem;

PROCEDURE UpdateCurValsAndWrite;
VAR i,j:   CARDINAL;
    tlog:  HLogDataType;
    TotalWords: LONGCARD;
BEGIN
   WITH InFile[DBNo] DO
      FOR i := 1 TO RefIDN DO
          XlateLogEntry(Rec.LogData[CHR(i)],tlog);
          j := ABS( INTEGER(tlog.StructID) );
          IF CurVal[j].Count <> tlog.Count THEN
             PutLogItem(tlog);
          END;
      END;
   END;

   j := ABS(FileNID);
   IF (WheresTitle[DBNo].Rec <> 0) OR (WheresTitle[DBNo].Idx <> 0) THEN
      CurVal[j].SRecPos := CHR(WheresTitle[DBNo].Idx);
      CurVal[j].SRecNo := CHR(WheresTitle[DBNo].Rec);
      TotalWords := 0 ;
      FOR i := 0 TO DBNo - 1 DO  INC(TotalWords, TitleNoWords[i])  END ;
      CurVal[j].TokenNoOffset := SHORTCARD(TotalWords - CurrTokenNo);
      PutLogItem(CurVal[j]);
   END;
END UpdateCurValsAndWrite;

BEGIN	(* HandleLog *)
   CurrTokenNo := 0 ;
   OutHeader.BeginLog := OutPos.Rec;
   FOR DBNo := 0 TO NoInFiles DO
      GetToRecs;
      DBCurrTokenNo := 0 ;	(* for each DB know the cummalitive Tok no *)
      WITH InFile[DBNo] DO
         CurLogItem.Rec := Header.BeginLog;
         CurLogItem.Idx := RefIDN + 1;
         InSeek(DBNo, Header.BeginLog);
         GetRec(DBNo);
         IF DBNo = 0 THEN
            InitialCurVals;
            WriteAllInitials;
         ELSE
            UpdateCurValsAndWrite;
         END;
         FirstItem := TRUE;
         WHILE (CurLogItem.Rec < Header.EndLog) OR 	(* a dummy log entry *)
	       (( CurLogItem.Rec = Header.EndLog ) AND
	       ((Rec.LogData[CHR(CurLogItem.Idx)].StructID <> 0) OR
		(Rec.LogData[CHR(CurLogItem.Idx)].TokenNoOffset = 255)) ) DO
             XlateLogEntry(Rec.LogData[CHR(CurLogItem.Idx)],tlog);
             PutLogItem(tlog);
	     INC( DBCurrTokenNo, LONGCARD(tlog.TokenNoOffset) ) ;
             IF FirstItem THEN
                LogBegin[DBNo] := MakeRealOffset(OutPos,OutHeader.BeginLog,
                                                 NoRefIDs) - 1;
                FirstItem := FALSE;
             END;
             INC(CurLogItem.Idx);
             IF CurLogItem.Idx > MaxLogDataIndex THEN
                GetRec(DBNo);
                CurLogItem.Rec := Pos;
                CurLogItem.Idx := RefIDN + 1;
                IF CurLogItem.Rec <= Header.EndLog THEN (* m.s. *)
                   (* compensate TokenNoOffset at start of new log rec *)
		   Rec.LogData[CHR(CurLogItem.Idx)].TokenNoOffset :=
  			SHORTCARD( Rec.BaseTokenNo - DBCurrTokenNo );
  		END ;	
             END;
         END;
      END;
      DiscardToRecs;
   END;

   OutHeader.EndLog := OutPos.Rec;
   IF OutPos.Idx <> 0 THEN WriteDBRec END;
   MapValue := LONGCARD(MaxNoLogs - NoRefIDs);
END HandleLog;

PROCEDURE NewLogsForOld(DBNo:   CARDINAL;
                        Old:    HRecPntr;
                    VAR New:    HRecPntr);
VAR
   OldLogPos:   LONGCARD;
   NewLogPos:   LONGCARD;
BEGIN
   WITH InFile[DBNo] DO
      OldLogPos := MakeRealOffset(Old,Header.BeginLog,InFile[DBNo].RefIDN+1);
      NewLogPos := OldLogPos + LogBegin[DBNo];
      New.Rec := OutHeader.BeginLog + CARDINAL(NewLogPos DIV MapValue);
      New.Idx := NoRefIDs + CARDINAL(NewLogPos MOD MapValue);
   END;
END NewLogsForOld;

END LogHandling.
