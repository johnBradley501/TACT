IMPLEMENTATION MODULE TDBBase;

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

IMPORT Lib, FIO;
FROM HyperDataModel IMPORT
  (* Const *) HyperLength, HyperLengthM1, HNoOccurs, HNoDataPtrs,
              BaseHTypeLen, OccurRecSize, MaxSpaceForOccursInRec, TypeMaxDataPos,
  (* Types *) HyperData, HOccurData, TDBTypeData ;
FROM UtilsTwo IMPORT
   IOErrorMessage;
FROM Windows  IMPORT
  (* Vars  *) TerminationProc;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResMessages IMPORT MsgString, PutResError, ResAskUser;
FROM KeyBase IMPORT
  (* Procs *) Read, KeyPressed ;

VAR
   TPtrLen  : CARDINAL;
   TDataPos : INTEGER ;  (* was CARDINAL, but need allowances to be neg. *)
   PrevHRec : CARDINAL ;
   NextHRec : CARDINAL ;


PROCEDURE DoStop;
BEGIN
   FIO.Close(OutFile);
   FIO.Erase(OutFileName);
   TerminationProc;
   HALT;
END DoStop;

PROCEDURE CheckIO;
VAR i:   CARDINAL;
    m:   ARRAY [0..40] OF CHAR;
BEGIN
   i := FIO.IOresult();
   IF i = 0 THEN RETURN END;

   IOErrorMessage(i, m);
   (*RES OLD MSG 268
   An IO error occurred while writing Textual Database: %0.
   *)
   MsgString(m,0);
   PutResError( (*RES REM INS*) 268 );
   DoStop
END CheckIO;

PROCEDURE WriteDBRec;

PROCEDURE HandleKeyStroke;
VAR ch:  CHAR;
BEGIN
   WHILE KeyPressed() DO Read(ch) END;
   (*RES OLD CHE 17
   Ending Options -- choose between C)ontinue and Q)uit:
   = C Q
   *)
   ResAskUser( (*RES REM INS*) 17 , 'CQ', ch);
   IF ch = 'Q' THEN DoStop END;
END HandleKeyStroke;

BEGIN
   IF KeyPressed() THEN HandleKeyStroke END;

   FIO.IOcheck := FALSE;
   FIO.WrBin(OutFile, OutFileRec, HyperLength);
   CheckIO;
   FIO.IOcheck := TRUE;
   INC(OutPos.Rec);
   OutPos.Idx := 0;
   Lib.WordFill(ADR(OutFileRec), HyperLength DIV 2, 0);
END WriteDBRec;

PROCEDURE InSeek(No:    CARDINAL;
                 RecTo: CARDINAL);
BEGIN
   WITH InFile[No] DO
      IF (Pos + 1) = RecTo THEN RETURN END;
      FIO.Seek(FileID, HyperLength * LONGCARD(RecTo));
      IF RecTo <> 0 THEN Pos := RecTo - 1 END;
   END;
END InSeek;

PROCEDURE GetRec(No:    CARDINAL);
VAR l:    CARDINAL;
BEGIN
   WITH InFile[No] DO
      Idx := 0;
      INC(Pos);
      l := FIO.RdBin(FileID, Rec, HyperLength);
      IF l <> HyperLength THEN
         ProgramErrorAndHalt('Unexpected short record in GetRec');
      END;
   END;
END GetRec;

PROCEDURE InitAddPtrDataToDB() ;
BEGIN
   IF OutPos.Idx <> 0 THEN WriteDBRec END; (* ensure on a new HyperRec boundary!   *)
   TPtrLen  := 4 ; (* will increment to proper value later >>> was 6 in TP <<<*)
   TDataPos :=  HyperLength;
   OutFileRec.DataPntr[0] := HyperLength ;
   OutPos.Idx  := 1 ; (* next position to use *)
END InitAddPtrDataToDB ;

PROCEDURE AddPtrDataToDB( Data : ARRAY OF BYTE ; (* << changed j.b. (was CHAR) *)
                          Len  : CARDINAL;
                      VAR RPos : HRecPntr);
   BEGIN
      INC(TPtrLen, 2) ;
      IF CARDINAL(TDataPos) < TPtrLen + Len THEN
         (* this data will not fit on current HyperRec *)
         OutFileRec.NoDataPtrsUsed := OutPos.Idx - 1;
         WriteDBRec ;
         OutFileRec.DataPntr[0] := HyperLength ;
         TPtrLen := 6 ;  (* >>> was 8 in the TP version <<< *)
         TDataPos := HyperLength ;
         OutPos.Idx := 1;
      END ;
      DEC(TDataPos, Len) ;
      RPos := OutPos;
(*    DEC(RPos.Rec, OutHeader.BeginStr); *)
      OutFileRec.DataPntr[OutPos.Idx] := TDataPos ;
      Lib.Move(ADR(Data), ADR(OutFileRec.TextData[TDataPos]), Len) ;
      INC(OutPos.Idx) ;
   END AddPtrDataToDB ;

PROCEDURE FinishAddPtrDataToDB() ;
  BEGIN
     OutFileRec.NoDataPtrsUsed := OutPos.Idx - 1;
     WriteDBRec ;
  END FinishAddPtrDataToDB ;


(* the following procs are "modified" versions from MAKBAS *)

PROCEDURE AddOccurToDB( Data : HOccurData ) ;
   VAR OccurPntr: POINTER TO HOccurData;
   BEGIN
      DEC(TDataPos, OccurRecSize);
      IF (TDataPos < INTEGER( TPtrLen )) AND ((OutPos.Idx > 1) OR (TDataPos < 1)) THEN
         OutFileRec.NoDataPtrsUsed := OutPos.Idx - 1 ;
         IF OutPos.Idx > 1 THEN  (* pointer values on this record *)
	    OutFileRec.PrevHRec := PrevHRec ;
	    OutFileRec.NextHRec := NextHRec ; (* NextHRec is always calculated to proper val *)
	    PrevHRec := OutPos.Rec - OutHeader.BeginType ;
	 END ;
         WriteDBRec ;
(*	 OutFileRec.DataPntr[0] := HyperLength ; *)
	 OutFileRec.DataPntr[0] := TypeMaxDataPos;
	 OutPos.Idx := 1 ; (* next position to use *)
         TPtrLen  := 4 ; (* add 2 later in AddTypeDataToDB for correct offset *)
	 TDataPos := INTEGER( TypeMaxDataPos ) - OccurRecSize ;
      END ;
      OccurPntr := ADR(OutFileRec.TextData[TDataPos]);
      OccurPntr^ := Data ;
   END AddOccurToDB ;

PROCEDURE InitAddTypeDataToDB() ;
  BEGIN
     IF OutPos.Idx <> 0 THEN WriteDBRec END; (* ensure on a new HyperRec boundary!   *)
(*   OutFileRec.DataPntr[0] := HyperLength ; *)
     OutFileRec.DataPntr[0] := TypeMaxDataPos;
     TPtrLen  := 4 ; (* will increment to proper value later *)
     TDataPos := INTEGER( TypeMaxDataPos );
     OutPos.Idx := 1 ; (* next position to use *)
     PrevHRec := 0 ;
     NextHRec := 0 ;
  END InitAddTypeDataToDB;

PROCEDURE AddTypeDataToDB( TDBData : TDBTypeData; VAR RPos : HRecPntr);
   VAR
	SpaceLeft, SpaceNeed : LONGINT ; (* m.s. - was INTEGER *)
	Len,BR:    CARDINAL ;
	FixUpNextHRec : BOOLEAN ;
   BEGIN
      Len := CARDINAL( TDBData.PackedWord.PackedLen ) + BaseHTypeLen ;
      INC(TPtrLen, 2) ;
      DEC(TDataPos, Len) ;
      IF TDataPos < INTEGER( TPtrLen ) THEN
         (* this data will not fit on current HyperRec *)
         OutFileRec.NoDataPtrsUsed := OutPos.Idx - 1 ;
         IF OutPos.Idx > 1 THEN  (* pointer values on this record *)
	    OutFileRec.PrevHRec := PrevHRec ;
	    OutFileRec.NextHRec := NextHRec ;
	    PrevHRec := OutPos.Rec - OutHeader.BeginType ;
	    FixUpNextHRec := FALSE ;
	 ELSE
	    FixUpNextHRec := TRUE ;
	 END ;
         WriteDBRec ;
         IF FixUpNextHRec THEN
            FIO.IOcheck := FALSE;
	    FIO.Seek(  OutFile, HyperLength * LONGCARD(OutHeader.BeginType+PrevHRec));
	    CheckIO ;
	    BR := FIO.RdBin( OutFile, OutFileRec, HyperLength ) ;
	    CheckIO ;
	    INC( OutFileRec.NextHRec ) ;
	    FIO.Seek(  OutFile, HyperLength * LONGCARD(OutHeader.BeginType+PrevHRec));
	    CheckIO ;
	    FIO.WrBin( OutFile, OutFileRec, HyperLength);
	    CheckIO ;
	    (* now reposition to end of file for next record *)
	    FIO.Seek(  OutFile, HyperLength * LONGCARD(OutPos.Rec)) ;
	    CheckIO ;
	    Lib.Fill( ADR(OutFileRec), HyperLength, 0C ) ;
            FIO.IOcheck := TRUE;
         END ;
	 OutFileRec.DataPntr[0] := TypeMaxDataPos;
         TPtrLen := 6 ;
         TDataPos := TypeMaxDataPos -Len ;
         OutPos.Idx := 1;
      END ;
	(*<Trace
	Trace.TWriteCard(HRecNo-OutHeader.BeginType,5);
	Trace.TWriteCard(OutPos.Idx,5);
	Trace.TWriteCard(TPtrLen,5);
	Trace.TWriteCard(TDataPos,5);
	Trace.TWriteCard(Len,3);
	Trace.TWriteLn ;
	Trace>*)
      RPos := OutPos;
(*      SpaceLeft := ((TDataPos - INTEGER(TPtrLen)) DIV OccurRecSize) * OccurRecSize ;
      SpaceNeed := INTEGER(TDBData.NoOccur * OccurRecSize) ;
*)
      (* m.s. - changed to LONGINT because SpaceNeed was being truncated *)
      SpaceLeft := (LONGINT(TDataPos - INTEGER(TPtrLen)) DIV OccurRecSize) * OccurRecSize ;
      SpaceNeed := LONGINT(TDBData.NoOccur) * OccurRecSize ;
      NextHRec  := OutPos.Rec - OutHeader.BeginType + 1 ;
      IF SpaceLeft < SpaceNeed THEN
	 INC(NextHRec, CARDINAL((SpaceNeed - SpaceLeft) DIV MaxSpaceForOccursInRec) ) ;
      END ;
      OutFileRec.DataPntr[OutPos.Idx] := CARDINAL( TDataPos ) ;
      Lib.Move( ADR(TDBData), ADR(OutFileRec.TextData[CARDINAL(TDataPos)]), Len) ;
      INC(OutPos.Idx) ;
   END AddTypeDataToDB ;

PROCEDURE FinishAddTypeDataToDB() ;
  BEGIN
     OutFileRec.NoDataPtrsUsed := OutPos.Idx - 1 ;
     IF OutPos.Idx > 1 THEN
	OutFileRec.PrevHRec := PrevHRec ;
(*	OutFileRec.NextHRec := 0 ; *)
	OutFileRec.NextHRec := OutPos.Rec - OutHeader.BeginType ;	(* was 0, non-zero useful in checks *)
     END ;
(*   WriteDBRec ;	record is written out in HandleToken -- next pass *)
  END FinishAddTypeDataToDB;

BEGIN
  NoInFiles := 0;
  RefsNames := NIL;
  NoRefIDs := 2; (* 0 and 1 have fixed assignments *)
  FileNID := 0;
END TDBBase.
