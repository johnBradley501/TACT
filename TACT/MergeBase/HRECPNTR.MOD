IMPLEMENTATION MODULE HRecPntrTranslation;

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

FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM TDBBase IMPORT HRecPntr, MaxNoMergeFiles, 
             OutFile, OutFileName;
IMPORT FIO;
FROM UtilsTwo IMPORT
   IOErrorMessage;
FROM Windows  IMPORT
  (* Vars  *) TerminationProc;
FROM ResMessages IMPORT MsgString, MsgCard, PutResError;

(*RES OLD MSG 283
An IO error occurred while writing working file %0: %1.
*)
CONST
    IOErrorRes = (*RES REM INS*) 283 ;

TYPE
   TFileInfo = RECORD
      Open:    BOOLEAN;
      FID:     FIO.File;
      gbegin:  LONGCARD;
      cid:     INTEGER;
      xref:    XRecInfoPntr;
      noxrefs: CARDINAL;
   END;
   IDHeader = RECORD;
      idno:   INTEGER;
      idsz:   CARDINAL;
   END;

VAR
   TFile:  ARRAY[0..MaxNoMergeFiles-1] OF TFileInfo;
   i:      CARDINAL;

PROCEDURE CheckIOError(No:  CARDINAL);
VAR l:   CARDINAL;
    m:   ARRAY[0..40] OF CHAR;
BEGIN
   l := FIO.IOresult();
   IF l <> 0 THEN
      IOErrorMessage(l, m);
      MsgCard(No,0);
      MsgString(m,0);
      PutResError( IOErrorRes );
      FIO.Close(OutFile);
      FIO.Erase(OutFileName);
      TerminationProc;
      HALT;
   END;
END CheckIOError;

PROCEDURE WriteXRefInfo(No: CARDINAL);
VAR l : CARDINAL;
BEGIN
   WITH TFile[No] DO
(*    ** we want to write zero size structures for type data  ** *LP*
      IF xref^.Size = 0 THEN
         xref^.IOffset := 0;
         RETURN
      END;
*)
      l := SIZE(CARDINAL)*2 + SIZE(HRecPntr) * xref^.Size;
      FIO.IOcheck := FALSE;
      FIO.WrBin(FID, xref^, l);
      CheckIOError(No);
      xref^.Size := 0;
      xref^.IOffset := 0;
      INC(noxrefs);
   END;
END WriteXRefInfo;

PROCEDURE FinishGroup(No: CARDINAL);
VAR t:   IDHeader;
BEGIN
   WITH TFile[No] DO
      WriteXRefInfo(No);
      FIO.Seek(FID, gbegin);
      CheckIOError(No);
      t.idno := cid;
      t.idsz := noxrefs;
      FIO.WrBin(FID, t, SIZE(IDHeader));
      gbegin := FIO.Size(FID);
      FIO.Seek(FID, gbegin);
      CheckIOError(No);
   END;
END FinishGroup;

PROCEDURE BeginXlateGroup(No:  CARDINAL;
                          ID:  INTEGER;
                          IOff:CARDINAL);
VAR  m:   ARRAY[0..39] OF CHAR;
     t:   IDHeader;
BEGIN
   WITH TFile[No] DO
      IF Open THEN
         FinishGroup(No);
      ELSE
         m := 'TEMP0.$$$';
         m[4] := CHR(ORD('0') + No);
         Open := TRUE;
         FIO.IOcheck := FALSE;
         FID := FIO.Create(m);
         CheckIOError(No);
         gbegin := 0;
      END;  (* IF Open THEN ... ELSE ... *)
      t.idno := ID;
      FIO.WrBin(FID, t, SIZE(IDHeader)); (* to set aside space for later use *)
      CheckIOError(No);

      cid := ID;
      noxrefs := 0;
      IF xref = NIL THEN NEW(xref) END;
      xref^.Size := 0;
      xref^.IOffset := IOff;
   END;
END BeginXlateGroup;

PROCEDURE AddTranslationItem(No:   CARDINAL; New: HRecPntr);
BEGIN
   WITH TFile[No].xref^ DO
      NewLoc[Size] := New;
      INC(Size);
   END;
END AddTranslationItem;

PROCEDURE AddTransWithNewRecord(No:  CARDINAL; New: HRecPntr);
BEGIN
   WriteXRefInfo(No);
   AddTranslationItem(No, New);
END AddTransWithNewRecord;

PROCEDURE EndAllXlateGroups(No: CARDINAL);
BEGIN
   IF NOT TFile[No].Open THEN RETURN END;
   FinishGroup(No);
   WITH TFile[No] DO
      FIO.Seek(FID,0);
      CheckIOError(No);
      DISPOSE(xref)
   END;
END EndAllXlateGroups;

PROCEDURE SetupToRecPntr(No:     CARDINAL;
                     VAR ID:     INTEGER;
                     VAR Rslt:   ToRecPntrType): BOOLEAN;
VAR
   t :   IDHeader;
   l,i : CARDINAL;
   sz:   CARDINAL;
BEGIN
   WITH TFile[No] DO
      IF NOT Open THEN RETURN FALSE END;
      l := FIO.RdBin(FID, t,SIZE(IDHeader));
      IF FIO.EOF THEN
         FIO.Close(FID);
         Open := FALSE;
         RETURN FALSE
      END;
      CheckIOError(No);
      ID := t.idno;
      ALLOCATE(Rslt, SIZE(CARDINAL) + SIZE(XRecInfoPntr) * t.idsz);
      Rslt^.Size := t.idsz;
      FOR i := 0 TO t.idsz-1 DO
         l := FIO.RdBin(FID, sz,SIZE(CARDINAL));
         CheckIOError(No);
         l := SIZE(HRecPntr) * sz + SIZE(CARDINAL);
         ALLOCATE(Rslt^.RecData[i],SIZE(CARDINAL) + l);
         WITH Rslt^.RecData[i]^ DO
            Size := sz;
            l := FIO.RdBin(FID, IOffset,l);
            CheckIOError(No);
         END;
      END;
   END;
   RETURN TRUE
END SetupToRecPntr;

PROCEDURE DisposeToRecPnts(VAR Data: ToRecPntrType);
VAR l : CARDINAL;
    sz: CARDINAL;
BEGIN
    WITH Data^ DO
       FOR l := 0 TO Size - 1 DO
           DEALLOCATE(RecData[l],
                      SIZE(CARDINAL)*2 + SIZE(HRecPntr) * RecData[l]^.Size);
       END;
    END;
    DEALLOCATE(Data, SIZE(CARDINAL) + SIZE(XRecInfoPntr) * Data^.Size);
    Data := NIL;
END DisposeToRecPnts;

PROCEDURE CleanUpXFiles;
VAR i:   CARDINAL;
    m:   ARRAY[0..39] OF CHAR;
BEGIN
   FOR i := 0 TO MaxNoMergeFiles-1 DO
     m := 'TEMP0.$$$';
     m[4] := CHR(ORD('0') + i);
     IF FIO.Exists(m) THEN
        IF TFile[i].Open THEN FIO.Close(TFile[i].FID) END;
        FIO.Erase(m);
     END;
   END;
END CleanUpXFiles;

BEGIN
   FOR i := 0 TO MaxNoMergeFiles-1 DO
      TFile[i].Open := FALSE;
      TFile[i].xref := NIL;
   END;
END HRecPntrTranslation.
