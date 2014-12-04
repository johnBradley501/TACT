IMPLEMENTATION MODULE TypeHandling;

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
IMPORT Lib, BitOps, WordBase ;
FROM HyperDataModel IMPORT
  (* Types *) HyperData, TDBTypePntr, TDBTypeData, BaseHTypeLen, HOccurData,
  (* Consts*) HyperLength, HNoTokens, OccurRecSize, TypeMaxDataPos,
  (* Procs *) TDBTypeCompare ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM TDBBase IMPORT MaxNoMergeFiles, HRecPntr, InSeek, GetRec, RefsNamePntr,
                    InFile,NoInFiles, InFileDataType,
                    OutFileRec, OutPos, OutHeader, AddOccurToDB,
		    InitAddTypeDataToDB, AddTypeDataToDB, FinishAddTypeDataToDB ;
FROM HRecPntrTranslation IMPORT
       BeginXlateGroup, AddTranslationItem, AddTransWithNewRecord,
       SetupToRecPntr, DisposeToRecPnts, EndAllXlateGroups, ToRecPntrType;

VAR
   TypeRslt:  ToRecPntrType;
   MasterPos: HRecPntr;

PROCEDURE HandleTypes;

VAR
   CurTPosRec: ARRAY[0..MaxNoMergeFiles-1] OF CARDINAL;	(* used for translation *)
   TPos:     ARRAY[0..MaxNoMergeFiles-1] OF HRecPntr;
   TORec:    ARRAY[0..MaxNoMergeFiles-1] OF CARDINAL;
   TData:    ARRAY[0..MaxNoMergeFiles-1] OF TDBTypePntr;
   TComps:   ARRAY[0..MaxNoMergeFiles-1] OF INTEGER;
   TokenOffset: ARRAY[0..MaxNoMergeFiles-1] OF LONGCARD;
   Master:   TDBTypeData;
   MasterPtr:TDBTypePntr;
   DBNo,i:   CARDINAL;
   Done:     BOOLEAN;
   DummyType:ARRAY[0..1] OF CHAR;
   DummyLastWordChar : CHAR ;

PROCEDURE GetFirstType(DBNo:   CARDINAL;
                   VAR RPos:   HRecPntr;
                   VAR Data:   TDBTypePntr);
BEGIN
   WITH InFile[DBNo] DO
      RPos.Rec := Header.BeginType;
      RPos.Idx := 2;
      InSeek(DBNo, RPos.Rec);
      GetRec(DBNo);
      Data :=  ADR(Rec.TextData[Rec.DataPntr[RPos.Idx]]);
   END;
END GetFirstType;

PROCEDURE GetNextType(DBNo:    CARDINAL;
                  VAR RPos:    HRecPntr;
                  VAR Data:    TDBTypePntr);
VAR OldRec:   CARDINAL;
BEGIN
   OldRec := RPos.Rec;
   WITH InFile[DBNo] DO
      INC(RPos.Idx);
      IF RPos.Idx > Rec.NoDataPtrsUsed THEN
(*	 since reading Types + Occurs sequentially can't safely use NextHRec!! *)
(*	 RPos.Rec := Header.BeginType + Rec.NextHRec ; *)
	 INC( RPos.Rec ) ;
         RPos.Idx := 1;
      END;
      IF ((RPos.Rec > Header.EndTypeRec) OR
	 ((RPos.Rec = Header.EndTypeRec) AND (RPos.Idx > Header.EndTypeIdx))) THEN
          ProgramErrorAndHalt('Attempt to read past End of Types');
      END;
      IF OldRec <> RPos.Rec THEN GetRec(DBNo) END;
      Data :=  ADR(Rec.TextData[Rec.DataPntr[RPos.Idx]]);
   END;
END GetNextType;

PROCEDURE SetupTokenTranslation;
VAR
   i:   CARDINAL;
BEGIN
   TokenOffset[0] := 0;
   FOR i := 1 TO NoInFiles DO
     WITH InFile[i-1].Header DO
        TokenOffset[i] := TokenOffset[i-1] +
                       LONGCARD(EndTokenRec - BeginToken) * HNoTokens +
                       LONGCARD(EndTokenIdx + 1);
     END;
   END;
END SetupTokenTranslation;

PROCEDURE NewTokenForOld(DBNo: CARDINAL;
                         Old:  HOccurData;
                     VAR New:  HOccurData);
VAR t:   LONGCARD;
BEGIN
   t := TokenOffset[DBNo] + LONGCARD(Old.TRecNo) * HNoTokens +
                       LONGCARD(ORD(Old.TRecPos));
   New.TRecNo := CARDINAL(t DIV HNoTokens);
   New.TRecPos := CHR(CARDINAL(t MOD HNoTokens));
END NewTokenForOld;

PROCEDURE CopyOccurs(DBNo, NoOccurs: CARDINAL);
TYPE
    OccurPntrType = POINTER TO HOccurData;
VAR i:     CARDINAL;
    ip:    INTEGER ;
    MaxOccurPos: CARDINAL;	(* anything less than this is pointer info! *)
    in:    OccurPntrType;
    out:   HOccurData;
BEGIN
   WITH InFile[DBNo] DO
      ip := Rec.DataPntr[ TPos[DBNo].Idx ] - OccurRecSize ;
      IF ip < INTEGER(4 + 2 * Rec.NoDataPtrsUsed) THEN
	 (* Occur data starts on next record *)
	 GetRec(DBNo);
	 TPos[DBNo].Rec := Pos ;	(* update our position location *)
	 TPos[DBNo].Idx := 0 ;		(* will update correctly in GetNextType *)
	 ip := INTEGER( TypeMaxDataPos ) - OccurRecSize ;
	 IF Rec.NoDataPtrsUsed = 0 THEN
		MaxOccurPos := 2 ;
	 ELSE
		MaxOccurPos := 4 + 2 * Rec.NoDataPtrsUsed ;
	 END ;	
      ELSE
	 MaxOccurPos := 4 + 2 * Rec.NoDataPtrsUsed ;
      END ;	

      FOR i := 1 TO NoOccurs DO
         IF ip < INTEGER(MaxOccurPos) THEN
            GetRec(DBNo);
	    TPos[DBNo].Rec := Pos ;	(* update our position location *)
	    TPos[DBNo].Idx := 0 ;	(* will update correctly in GetNextType *)
	    IF Rec.NoDataPtrsUsed = 0 THEN
		MaxOccurPos := 2 ;
	    ELSE
		MaxOccurPos := 4 + 2 * Rec.NoDataPtrsUsed ;
	    END ;	
	    ip := INTEGER( TypeMaxDataPos ) - OccurRecSize ;
         END;
         in := ADR(Rec.TextData[ip]);
         NewTokenForOld(DBNo, in^, out);
         AddOccurToDB( out ) ;
         DEC(ip, OccurRecSize);
      END;
   END;
END CopyOccurs;


BEGIN	(* HandleTypes *)
   OutHeader.NoTypes := 0;
   InitAddTypeDataToDB();
   SetupTokenTranslation;
   OutHeader.BeginType := OutPos.Rec;

   WITH Master DO
      NoOccur := 0;
      DummyType[0] := 0C ;
      DummyType[1] := 0C ;
      BitOps.Pack( DummyType, PackedWord, WordBase.SortNoBitsPerChar ) ;
   END;
   MasterPtr := ADR( Master ) ;
   AddTypeDataToDB( Master, (* InitialDummyTypeRecLength,*) MasterPos);
   DEC(MasterPos.Rec,OutHeader.BeginType);

   (* since we don't know how many bits are used to pack the HighChar we
      compute it							*)
   WITH Master DO
      DummyType[0] := 377C ;
      BitOps.Pack( DummyType, PackedWord, WordBase.SortNoBitsPerChar ) ;
      DummyLastWordChar := PackedWord.PackedStr[0] ;
   END;

   FOR DBNo := 0 TO NoInFiles DO
      GetFirstType(DBNo,TPos[DBNo],TData[DBNo]);
      BeginXlateGroup(DBNo,0,0);
      AddTranslationItem(DBNo, MasterPos);
      TORec[DBNo] := TPos[DBNo].Rec;
   END;
   Done := FALSE;

   REPEAT
      Master := TData[0]^;
      TComps[0] := 0;
      FOR DBNo := 1 TO NoInFiles DO
         TComps[DBNo] := TDBTypeCompare(MasterPtr, TData[DBNo]);
         IF TComps[DBNo] > 0 THEN
            FOR i := 0 TO DBNo-1 DO TComps[i] := -1 END;
            TComps[DBNo] := 0;
            Master := TData[DBNo]^;
         END;
      END;
      Done := Master.PackedWord.PackedStr[0] = DummyLastWordChar ;
      IF NOT Done THEN
         (* process TData's with TComp = 0 *)
         WITH Master DO
            NoOccur := 0;
            FOR DBNo := 0 TO NoInFiles DO
               IF TComps[DBNo] = 0 THEN  INC(NoOccur,TData[DBNo]^.NoOccur)  END;
            END;
	    AddTypeDataToDB( Master, MasterPos ) ;
	    DEC(MasterPos.Rec,OutHeader.BeginType);
	    INC(OutHeader.NoTypes) ;
	    (* handle all occur data for current Type *)
	    FOR DBNo := 0 TO NoInFiles DO
		IF TComps[DBNo] = 0 THEN
		   CurTPosRec[DBNo] := TPos[DBNo].Rec ; (* save value in as CopyOccurs changes them *)
		   CopyOccurs(DBNo, TData[DBNo]^.NoOccur)
		END;
	    END;
         END;

         FOR DBNo := 0 TO NoInFiles DO
            IF TComps[DBNo] = 0 THEN
               IF TORec[DBNo] = CurTPosRec[DBNo] THEN
                  AddTranslationItem(DBNo, MasterPos);
               ELSE
                  FOR i := TORec[DBNo]+1 TO CurTPosRec[DBNo] DO
			(* add as many rec structs as hyper recs changed *)
			AddTransWithNewRecord(DBNo, MasterPos);
                  END ;
                  TORec[DBNo] := CurTPosRec[DBNo] ;
               END;
               GetNextType(DBNo,TPos[DBNo],TData[DBNo])
            END;
         END;
      END;
   UNTIL Done;

   WITH Master DO
      NoOccur := 0;
      DummyType[0] := 377C ;
      BitOps.Pack( DummyType, PackedWord, WordBase.SortNoBitsPerChar ) ;
   END;
   AddTypeDataToDB( Master, (* FinalDummyTypeRecLength,*) MasterPos);
   DEC(MasterPos.Rec,OutHeader.BeginType);

   OutHeader.EndTypeRec := OutPos.Rec;
   OutHeader.EndTypeIdx := OutPos.Idx -1;

   FinishAddTypeDataToDB() ;
   FOR DBNo := 0 TO NoInFiles DO
      EndAllXlateGroups(DBNo)
   END;
END HandleTypes;

PROCEDURE SetupTypeTranslation(DBNo: CARDINAL);
VAR dummy: INTEGER;
BEGIN
   IF TypeRslt <> NIL THEN
      ProgramErrorAndHalt('2nd call to SetupTypeTranslation')
   END;
   IF NOT SetupToRecPntr(DBNo, dummy, TypeRslt) THEN
      ProgramErrorAndHalt('Error reported by SetupToRecPntr');
   END;
END SetupTypeTranslation;

PROCEDURE NewTypeForOld(Old:    HRecPntr;
                    VAR New:    HRecPntr);
BEGIN
   New := TypeRslt^.RecData[Old.Rec]^.NewLoc[Old.Idx-1];
   IF (New.Rec > MasterPos.Rec) OR (New.Idx > 145) OR
	((New.Rec = 0) AND (New.Idx = 0)) THEN (* 3 lines for debugging only*)
      ProgramErrorAndHalt('TypeHandling: Invalid Type mapping.');
   END;
END NewTypeForOld;

PROCEDURE FinishTypeTranslation;
BEGIN
   DisposeToRecPnts(TypeRslt);
END FinishTypeTranslation;

BEGIN
   TypeRslt :=    NIL;
END TypeHandling.
