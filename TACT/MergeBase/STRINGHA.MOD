IMPLEMENTATION MODULE StringHandling;

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
IMPORT Lib, Str, BitOps;
FROM HyperDataModel IMPORT HyperLength, HyperData, TDBStringFormat,
		HNoTokens, TDBStrCompare ;
FROM TDBBase IMPORT MaxNoMergeFiles, HRecPntr, InSeek, GetRec, RefsNamePntr,
                    FileNID,InFile,NoInFiles, InFileDataType,
                    RefsNameData, RefsNames, OutFileRec, OutPos, OutHeader,
                    WriteDBRec, InitAddPtrDataToDB, AddPtrDataToDB,
                    FinishAddPtrDataToDB;
FROM GlobalDefs IMPORT StrAny;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM WordBase IMPORT IntToSortWord, SortNoBitsPerChar;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM HRecPntrTranslation IMPORT
       BeginXlateGroup, AddTranslationItem, AddTransWithNewRecord,
       EndAllXlateGroups;

(* Note - Strings are stored in the following structure:
    +----------+-----+------------------+--------+----+
    | TotWords | Len | BitPackedSortStr | IntStr | 0C |
    +----------+-----+------------------+--------+----+
   where Len is a 1 byte offset to start of IntStr - 1 (ie. # bytes in
   BitPackedSortStr); and is part of BitPackedSortStr; TotWord is LONGCARD.
*)

TYPE
    DBRefStringData = RECORD
      ID     : INTEGER;
      SRec   : CHAR;		(* Start position *)
      SPos   : CHAR;
      ERec   : CHAR;		(* End position *)
      EPos   : CHAR;
    END;
    RefStringData = RECORD (* from RefStrInit.MOD *)
	ID	: INTEGER;
        SRec	: CARDINAL;	(* Start position *)
        SPos	: CHAR;
        ERec	: CHAR;		(* End position *)
        EPos	: CHAR;
    END;
    RefStrRecList = ARRAY[1..170] OF RefStringData;
    RefStrRecListPntr = POINTER TO RefStrRecList;

    MergeType = (BeginEnd, FileNames, FromDB);
    MergeStrPntr = POINTER TO MergeStrData;
    MergeStrData = RECORD
       Next:     MergeStrPntr;
       Len:      CARDINAL;
       Str:      TDBStringFormat;
    END;
    MergeSource = POINTER TO MergeSourceType;
    MergeProcedure = PROCEDURE(VAR MergeSource): BOOLEAN;
    MergeSourceType = RECORD
       Next:         MergeSource;
       Lowest:       BOOLEAN;
       MergeProc:    MergeProcedure;
       Current:      MergeStrPntr;
       CASE MType: MergeType OF
         BeginEnd:
           Done:        BOOLEAN;
       | FileNames:
           NextData:    MergeStrPntr;
       | FromDB:
           DBNo:        CARDINAL;
           CurPos:      HRecPntr;
           EndPos:      HRecPntr;
       END;
    END;

PROCEDURE NewMergeStrPntr(VAR Data:  ARRAY OF BYTE; (*read only*)
                              Len:   CARDINAL): MergeStrPntr;
VAR t:  MergeStrPntr;
BEGIN
    ALLOCATE(t, 6 + Len);
    Lib.Move(ADR(Data), ADR(t^.Str),Len);
    t^.Len := Len;
    t^.Next := NIL;
    RETURN t
END NewMergeStrPntr;

PROCEDURE DisposeMergeStrPntr(VAR Data: MergeStrPntr);
BEGIN
   IF Data = NIL THEN RETURN END;
   DEALLOCATE(Data,Data^.Len + 6);
   Data := NIL;
END DisposeMergeStrPntr;

PROCEDURE GetRefStrData(No:     CARDINAL;
                        CurPos: HRecPntr): MergeStrPntr;
TYPE
   DataType =  POINTER TO ARRAY[0..256] OF CHAR;
VAR
   DataLen     : CARDINAL ;
   Data:         DataType;
BEGIN
   WITH InFile[No] DO
      IF Pos = CurPos.Rec THEN (* Do nothing *)
      ELSIF Pos+1 = CurPos.Rec THEN GetRec(No)
      ELSE
          InSeek(No,CurPos.Rec);
          GetRec(No);
      END;
      WITH Rec DO
        IF (CurPos.Idx > NoDataPtrsUsed) OR (CurPos.Idx = 0) THEN
            ProgramErrorAndHalt( 'RefStrBase (GetRefStr): Invalid String record access.' )
        END ;
        DataLen := DataPntr[CurPos.Idx-1] - DataPntr[CurPos.Idx];
        Data := ADR(TextData[ DataPntr[CurPos.Idx] ] ) ;
        RETURN NewMergeStrPntr(Data^, DataLen);
        END ;
   END;
END GetRefStrData;

PROCEDURE NextBeginEnd(VAR Pntr: MergeSource): BOOLEAN;
BEGIN
   IF Pntr^.Done THEN
      RETURN FALSE
   END;
   Pntr^.Current^.Str.TDBStr.PackedStr[0] := 377C;
   Pntr^.Done := TRUE;
   RETURN TRUE;
END NextBeginEnd;

PROCEDURE NextFileNames(VAR Pntr: MergeSource): BOOLEAN;
BEGIN
   WITH Pntr^ DO
      DisposeMergeStrPntr(Current);
      IF NextData = NIL THEN RETURN FALSE END;
      Current := NextData;
      NextData := NextData^.Next;
   END;
   RETURN TRUE;
END NextFileNames;

PROCEDURE NextFromDB(VAR Pntr: MergeSource): BOOLEAN;
BEGIN
   WITH Pntr^ DO
      DisposeMergeStrPntr(Current);
      INC(CurPos.Idx);
      IF (CurPos.Rec = EndPos.Rec) AND (CurPos.Idx > EndPos.Idx) THEN
         RETURN FALSE
      END;
      IF CurPos.Idx > InFile[DBNo].Rec.NoDataPtrsUsed THEN
         GetRec(DBNo);
         INC(CurPos.Rec);
         CurPos.Idx := 1;
      END;
      Current := GetRefStrData(DBNo, CurPos);
   END;
   RETURN TRUE;
END NextFromDB;


PROCEDURE HandleStrings;
VAR
   RefStrRecListData: ARRAY[0..MaxNoMergeFiles-1] OF RefStrRecListPntr;
   OldRecID:          ARRAY[0..MaxNoMergeFiles-1] OF CARDINAL;
   i:                 CARDINAL;
   OutRefStrRecList:  RefStrRecList;
   NoRefStrings:      CARDINAL;
   tRefNamePntr:      RefsNamePntr;
   tRefNamePntr2:     RefsNamePntr;
   DoingID:           INTEGER;
   OldID:             INTEGER;
   cr:                INTEGER;
   MergeList:         MergeSource;
   tMerge:            MergeSource;
   cMerge:            MergeSource;
   pMerge:            MergeSource;
   FirstLowest:       BOOLEAN;
   FPos:              HRecPntr;
   tPos:              HRecPntr;
   tPos2:             HRecPntr;
   FirstForThisID:    BOOLEAN;
   TotWords:	      LONGCARD;

PROCEDURE GetRefStringList(No: CARDINAL) ;
VAR
   AmtToAlloc    : CARDINAL;
   StartAt       : CARDINAL;
   I             : CARDINAL;
   CurrRefStrRec : POINTER TO ARRAY[1..170] OF DBRefStringData;

BEGIN
   WITH InFile[No].Header DO
      InSeek(No, BeginStrRec) ;
      GetRec(No);

      AmtToAlloc := SIZE(RefStringData) * (1 + NoStrRecs) ;
      ALLOCATE( RefStrRecListData[No], AmtToAlloc ) ;

      StartAt := BeginStr - 1 ;
      CurrRefStrRec := ADR(InFile[No].Rec);
      FOR I := 1 TO NoStrRecs+1 DO
         WITH RefStrRecListData[No]^[I] DO
            ID   := CurrRefStrRec^[I].ID ;
            IF ORD(CurrRefStrRec^[I].SPos) = 1 THEN  INC( StartAt ) END ;
            SRec := StartAt (* + ORD(CurrRefStrRec.SRec) *) ;
            SPos := CurrRefStrRec^[I].SPos ;
            ERec := CurrRefStrRec^[I].ERec ;
            EPos := CurrRefStrRec^[I].EPos ;
         END ;
         INC( StartAt, ORD(CurrRefStrRec^[I].ERec) ) ;
      END ;
   END;
END GetRefStringList ;

PROCEDURE PutRefStringList;
VAR
   AmtToAlloc    : CARDINAL;
   StartAt       : CARDINAL;
   I             : CARDINAL;
   CurrRefStrRec : POINTER TO ARRAY[1..170] OF DBRefStringData;
BEGIN
   IF OutPos.Idx <> 0 THEN WriteDBRec END; (* ensure on a new HyperRec boundary! *LP* *)
   OutHeader.BeginStrRec := OutPos.Rec;

   CurrRefStrRec := ADR(OutFileRec);
   StartAt := OutHeader.BeginStr;
   FOR I := 1 TO NoRefStrings DO
      WITH CurrRefStrRec^[I] DO
         ID := OutRefStrRecList[I].ID ;
         SRec := CHR(OutRefStrRecList[I].SRec - StartAt);
         StartAt := OutRefStrRecList[I].SRec;
         SPos := OutRefStrRecList[I].SPos ;
         ERec := OutRefStrRecList[I].ERec ;
         EPos := OutRefStrRecList[I].EPos ;
      END;
   END;

(* m.s. - now write a dummy record *)

   WriteDBRec;
END PutRefStringList;

PROCEDURE GetOldIDFor(No:    CARDINAL;
                      NewID: INTEGER): INTEGER;
VAR i:   CARDINAL;
BEGIN
   WITH InFile[No] DO
      FOR i := 0 TO RefIDN DO
        IF RefIDL^[i]^.ID = NewID THEN
           RETURN (- INTEGER(i))
        END;
      END;
   END;
   RETURN 0
END GetOldIDFor;

PROCEDURE GetRefStrRecInfo(No:       CARDINAL;
                           RefID :   INTEGER ;
                       VAR StartPos: HRecPntr;
                       VAR EndPos:   HRecPntr);
VAR
   I : CARDINAL ;
BEGIN
   I := 1 ;
   WHILE (I <= InFile[No].Header.NoStrRecs)
   AND (RefID <> RefStrRecListData[No]^[I].ID) DO
      INC( I )
   END ;
   IF I > InFile[No].Header.NoStrRecs THEN
      ProgramErrorAndHalt( 'RefStrInit: RefID not found.' )
   END ;
   WITH RefStrRecListData[No]^[I] DO
(*    StartPos.Rec := InFile[No].Header.BeginStr + ORD( SRec ) ; *)
      StartPos.Rec := SRec ;
      StartPos.Idx := ORD( SPos ) ;
(*    EndPos.Rec   := InFile[No].Header.BeginStr + ORD( ERec ) ; *)
      EndPos.Rec   := StartPos.Rec + ORD( ERec ) ;
      EndPos.Idx   := ORD( EPos ) ;
   END ;
END GetRefStrRecInfo ;

PROCEDURE StartBeginEnd(VAR Pntr: MergeSource); (* from StringsData *)
(* VAR TempStr:   ARRAY[0..5] OF CHAR; *)
VAR TempStr : TDBStringFormat ;
BEGIN
(* TempStr[0] := 1C;   ---old code ---
   TempStr[1] := 0C;
   TempStr[2] := '?';
   TempStr[3] := '?';
   TempStr[4] := '?';
   TempStr[5] := 0C;  *)

   WITH TempStr DO
	TotalWords := 0 ;
	WITH TDBStr DO
	   PackedLen := 1 ;
	   PackedStr[0] := 0C ;
	   PackedStr[1] := "?" ;
	   PackedStr[2] := "?" ;
	   PackedStr[3] := "?" ;
	   PackedStr[4] := 0C ;
	END ;
   END ;

   NEW(Pntr);
   WITH Pntr^ DO
      Next := NIL;
      MergeProc := NextBeginEnd;
      MType := BeginEnd;
      Current := NewMergeStrPntr(TempStr, 10);	(* was: 6 *)
      Done := FALSE;
   END;
END StartBeginEnd;

PROCEDURE StartFromDB(No:    CARDINAL;
                      ID:    INTEGER;
                  VAR Pntr: MergeSource);
BEGIN
   NEW(Pntr);
   WITH Pntr^ DO
      Next := NIL;
      MergeProc := NextFromDB;
      MType := FromDB;
      DBNo := No;
      GetRefStrRecInfo(No,ID,CurPos, EndPos);
      Current := GetRefStrData(No, CurPos);
   END;
END StartFromDB;

PROCEDURE StartFileNames(ID:    INTEGER;
                     VAR Pntr:  MergeSource): BOOLEAN;

VAR i:      CARDINAL;
    di:     INTEGER;
    tStr:   TDBStringFormat;
    sortStr:StrAny;
    l1,l2:  CARDINAL;
    np,c,p: MergeStrPntr;

BEGIN
   Pntr := NIL;
   IF FileNID <> ID THEN RETURN FALSE END;
   NEW(Pntr);
   WITH Pntr^ DO
      Next := NIL;
      MergeProc := NextFileNames;
      MType := FileNames;
      NextData := NIL
   END;
   FOR i := 0 TO NoInFiles DO
      di := GetOldIDFor(i,ID);
      IF di = 0 THEN (* ID currently not present, should be added *)
         WITH InFile[i].Header DO
            l2 := Str.Length(Title) + 1;
            IntToSortWord(Title, sortStr);
	    BitOps.Pack( sortStr, tStr.TDBStr, SortNoBitsPerChar ) ;
            l1 := CARDINAL(tStr.TDBStr.PackedLen) ;
            Lib.Move( ADR(Title), ADR(tStr.TDBStr.PackedStr[l1]), l2) ;
            tStr.TotalWords := VAL(LONGCARD,EndTokenRec-BeginToken) * VAL(LONGCARD,HNoTokens) +
		      VAL(LONGCARD, EndTokenIdx + 1) ;
	    TitleNoWords[i] := tStr.TotalWords ;
            np := NewMergeStrPntr(tStr,l1 + l2 + 6);
            (* was l1+l2+ 3; account for 0c, PackedLen, TotalWords [1+1+4=6] *LP* *)
         END;
         p := NIL;
         c := Pntr^.NextData;
         WHILE (c <> NIL) AND (TDBStrCompare( ADR(np^.Str), ADR(c^.Str)) >= 0) DO
            p := c;
            c := c^.Next;
         END;
         IF p = NIL THEN
            np^.Next := Pntr^.NextData;
            Pntr^.NextData := np;
         ELSIF TDBStrCompare( ADR(np^.Str), ADR(p^.Str)) <> 0 THEN
            np^.Next := p^.Next;
            p^.Next := np;
         ELSE
            DisposeMergeStrPntr(np);
         END;
      ELSE
         WITH InFile[i].Header DO
            TitleNoWords[i] := VAL(LONGCARD,EndTokenRec-BeginToken) * VAL(LONGCARD,HNoTokens) +
		      VAL(LONGCARD, EndTokenIdx + 1) ;
	 END ;
      END;
   END;
   IF Pntr^.NextData = NIL THEN
      DISPOSE(Pntr);
      RETURN FALSE
   END;
   Pntr^.Current := Pntr^.NextData;
   Pntr^.NextData := Pntr^.NextData^.Next;
   RETURN TRUE;
END StartFileNames;

PROCEDURE LogCurrentRefStr(MergeData: MergeSource;
                           FPos:      HRecPntr);
VAR i:   CARDINAL;
    sortStr: StrAny;
    tStr: TDBStringFormat;
BEGIN
   WITH MergeData^ DO
      CASE MType OF
        BeginEnd:   (* do nothing *)
      | FileNames:
           FOR i := 0 TO NoInFiles DO
             IntToSortWord(InFile[i].Header.Title,sortStr);
	     BitOps.Pack( sortStr, tStr.TDBStr, SortNoBitsPerChar ) ;
             IF TDBStrCompare( ADR(tStr), ADR(Current^.Str)) = 0 THEN
                WheresTitle[i] := FPos;
             END;
           END;
          (* not in place yet *)
      | FromDB:
          IF CurPos.Rec <> OldRecID[DBNo] THEN
             OldRecID[DBNo] := CurPos.Rec;
             AddTransWithNewRecord(DBNo,FPos)
          ELSE
             AddTranslationItem(DBNo,FPos)
          END;
      END;
   END;
END LogCurrentRefStr;

PROCEDURE WriteOutCurrentRefStr(tMerge:   MergeSource;
                            VAR FPos:     HRecPntr);
BEGIN
   WITH tMerge^ DO
      AddPtrDataToDB(Current^.Str, Current^.Len,FPos);
   END;
   IF FirstForThisID THEN
      WITH OutRefStrRecList[NoRefStrings] DO
         SRec := OutPos.Rec;
         SPos := CHR(OutPos.Idx-1);
      END;
   END;
   DEC(FPos.Rec,OutRefStrRecList[NoRefStrings].SRec);
END WriteOutCurrentRefStr;


BEGIN
   InitAddPtrDataToDB() ;
   OutHeader.BeginStr := OutPos.Rec;

   FOR i := 0 TO NoInFiles DO
      GetRefStringList(i);
      OldRecID[i] := 0;
      WheresTitle[i].Rec := 0;
      WheresTitle[i].Idx := 0;
   END;
   FOR i := 0 TO 170 DO StringFirstItem[i] := 0 END;
   NoRefStrings := 0;
   tRefNamePntr := RefsNames;
   LOOP
      IF NoRefStrings > 0 THEN
         WITH OutRefStrRecList[NoRefStrings] DO
            ERec := CHR(FPos.Rec); (* still OK ?? j.b. *)
            EPos := CHR(FPos.Idx);
         END;
      END;
      DoingID := 0;
      WHILE (tRefNamePntr <> NIL) AND (DoingID = 0) DO
         IF (tRefNamePntr^.ID < 0) AND (DoingID = 0) THEN
            DoingID := tRefNamePntr^.ID
         ELSE
            tRefNamePntr := tRefNamePntr^.Next
         END;
      END;
      IF DoingID = 0 THEN EXIT END;	(* no more strings *)
      INC(NoRefStrings);

      OutRefStrRecList[NoRefStrings].ID := DoingID;

(*    Build Merge List *)

      FirstForThisID := TRUE;
      StartBeginEnd(MergeList);
      (* get first occurance of string from each DB *)
      FOR i := 0 TO NoInFiles DO
         OldID := GetOldIDFor(i,DoingID);
         IF OldID <> 0 THEN
            GetRefStrRecInfo(i,OldID,tPos,tPos2);
            BeginXlateGroup(i,OldID,tPos.Idx-1);
            OldRecID[i] := tPos.Rec;
            StartFromDB(i,OldID,tMerge);
            tMerge^.Next := MergeList;
            MergeList := tMerge;
         END;
      END;
      IF StartFileNames(DoingID,tMerge) THEN
         tMerge^.Next := MergeList;
         MergeList := tMerge;
      END;

(*    Creating Strings, extracting from Merge List *)
      WHILE MergeList <> NIL DO
         cMerge := MergeList;
         cMerge^.Lowest := TRUE;
	 TotWords := cMerge^.Current^.Str.TotalWords ;
         tMerge := MergeList^.Next;
         WHILE tMerge <> NIL DO
            cr := TDBStrCompare( ADR(cMerge^.Current^.Str), ADR(tMerge^.Current^.Str));
            tMerge^.Lowest := FALSE;
            IF cr = 0 THEN
		tMerge^.Lowest := TRUE ;
		INC( TotWords, tMerge^.Current^.Str.TotalWords ) ;
            ELSIF cr > 0 THEN
                cMerge := MergeList;
                WHILE cMerge <> tMerge DO
                  cMerge^.Lowest := FALSE;
                  cMerge := cMerge^.Next
                END;
                cMerge^.Lowest := TRUE;
		TotWords := cMerge^.Current^.Str.TotalWords ;
            END;
            tMerge := tMerge^.Next;
         END;
         tMerge := MergeList;
         pMerge := NIL;
         FirstLowest := TRUE;
         WHILE tMerge <> NIL DO
            WITH tMerge^ DO
               IF Lowest THEN
                  IF FirstLowest THEN
		     tMerge^.Current^.Str.TotalWords := TotWords ; (* include new totals *)
                     WriteOutCurrentRefStr(tMerge,FPos);
                     FirstLowest := FALSE;
                     IF FirstForThisID THEN
                        FirstForThisID := FALSE;
                        StringFirstItem[ABS(DoingID)] := FPos.Idx;
                     END;
                  END;
                  LogCurrentRefStr(tMerge,FPos);
                  IF NOT MergeProc(tMerge) THEN
                     cMerge := tMerge^.Next;
                     IF pMerge = NIL THEN MergeList := tMerge^.Next;
                     ELSE pMerge^.Next := tMerge^.Next END;
                     DisposeMergeStrPntr(tMerge^.Current);
                     DISPOSE(tMerge);
                     tMerge := cMerge;
                  ELSE
                     pMerge := tMerge;
                     tMerge := tMerge^.Next;
                  END;
               ELSE
                  pMerge := tMerge;
                  tMerge := tMerge^.Next;
               END;
            END;
         END;
      END;

      tRefNamePntr2 := tRefNamePntr^.Next;
      WHILE (tRefNamePntr2 <> NIL) DO
         IF DoingID = tRefNamePntr2^.ID THEN tRefNamePntr2^.ID := 0 END;
         tRefNamePntr2 := tRefNamePntr2^.Next;
      END;
      tRefNamePntr := tRefNamePntr^.Next;
   END;
   FOR i := 0 TO NoInFiles DO EndAllXlateGroups(i) END;

   OutHeader.EndStr := OutPos.Rec;
   OutHeader.NoStrRecs := NoRefStrings;
   (*   OutHeader.BeginStrRec := OutPos.Rec ;   (* m.s. - needed in case NoRefStrings = 0 *) *)

   FinishAddPtrDataToDB();	(* moved here since WriteDBRec increments OutPos.Rec !! *LP* *)

  (* m.s. IF NoRefStrings <> 0 THEN  *)
     PutRefStringList  (* END; *)
END HandleStrings;

END StringHandling.
