IMPLEMENTATION MODULE HyperBase;
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


IMPORT Str, Lib, FIO ;
FROM SYSTEM IMPORT ADR;
FROM GlobalDefs IMPORT StrAny;
FROM Storage IMPORT MainHeap, HeapTotalAvail;
FROM HyperDataModel IMPORT
  (* Const *) HyperLength, HNoPDBWords,
  (* Types *) HyperData;
FROM ResMessages IMPORT
   (*proc*)  MsgString, GetResMessage;
FROM Utils IMPORT
             Exist;
FROM UtilsTwo IMPORT IOErrorMessage;
FROM ErrorBase IMPORT
   (* proc *)  ProgramErrorAndHalt;
FROM MemoryManagement IMPORT
  (* types *) HyperPageManagementRecord, HyperPageManagementPntr,
              KiloInfo, RealStoragePntr,
              EMSInfoPagePntr, RecordLocationType, LocationRecord,
  (* vars  *) EMSAvailable, EMSInfo,
  (* procs *) RealReference, SegmentToReal, GetRealHyperPage, GetNewEMSPage, EMSToReal,
              RealToEMS, ReleaseRealPage, ReleaseEMSPage,
              GetManagementDataPtr, SetManagementDataPtr, ALLOCATE, DEALLOCATE;
(*<Dbg
FROM Trace IMPORT
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard,
              TWriteAddr, TWriteStrHex, CloseTFile;
Dbg>*)

(*RES OLD MSG 135
UseBase has run out of usable memory.
*)
   CONST
	UsableMemoryMsg = (*RES REM INS*) 135;
	MaxFileNumbInMem = 30 ; (* no more than 30 Hyper recs per file allocated *)

   TYPE
    RecInfoType = RECORD
      RecNo:     CARDINAL;
      RecData:   LocationRecord;
    END;

    HyperFile = POINTER TO HyperFileData;
    HyperFileData = RECORD
       ID:             FIO.File;
       ManagementData: HyperPageManagementPntr;
       TruncOK:        BOOLEAN;
       NumbInMem:      CARDINAL;
       NumbInUse:      CARDINAL;
       NumbRecs:       CARDINAL;
       Name:           StrAny;
       RecInfo:        ARRAY [0..MaxFileNumbInMem-1] OF RecInfoType;
    END;


(* CompareHRecs compares two HRecPntr's:  HRec1 < HRec2 returns -1
					  HRec1 = HRec2    "     0
					  HRec1 > HRec2    "    +1  *)
PROCEDURE CompareHRecs( HRec1, HRec2 : HRecPntr ) : INTEGER ;
   BEGIN
	IF HRec1.Rec < HRec2.Rec THEN
	   RETURN -1
	ELSIF HRec1.Rec > HRec2.Rec THEN
	   RETURN 1
	ELSIF HRec1.Idx < HRec2.Idx THEN
	   RETURN -1
	ELSIF HRec1.Idx > HRec2.Idx THEN
	   RETURN 1
	ELSE 
	   RETURN 0
	END ;
   END CompareHRecs ;

PROCEDURE HyperFileSize(HFile:   HyperFile): CARDINAL;
VAR
      size: LONGCARD;
BEGIN
    size := FIO.Size(HFile^.ID);
    IF FIO.IOresult() <> 0 THEN
      ProgramErrorAndHalt('Error In HyperFileSize after FIO.Size');
    END;
    RETURN VAL(CARDINAL, (size + 1023) DIV 1024) + 1;
END HyperFileSize;


PROCEDURE SeekHyperRecord(FIOFile:  FIO.File;
                          RecNo:  CARDINAL): CARDINAL; (* returns IOresult() *)
BEGIN
   FIO.Seek(FIOFile, VAL(LONGCARD,RecNo) * HyperLength);
   RETURN FIO.IOresult();
END SeekHyperRecord;

PROCEDURE WriteChangedRecord(HFile:   HyperFile;
                         VAR C:       RealStoragePntr);
VAR
      res:  CARDINAL;
BEGIN
   C^.Data.Changed := FALSE;
   res := SeekHyperRecord(HFile^.ID, C^.Data.RecordID);
   IF res <> 0 THEN
      ProgramErrorAndHalt('Error (1) Positioning HyperFile');
   END;

   FIO.WrBin(HFile^.ID, C^.HRecord, HyperLength);
   IF FIO.IOresult() <> 0 THEN
      ProgramErrorAndHalt('Error Writing To HyperFile');
   END;
END WriteChangedRecord;

PROCEDURE LocateRecData(HFile: HyperFile;
                        No:    CARDINAL;
                    VAR Pos:   CARDINAL): BOOLEAN;
BEGIN
   Pos := 0;
   WITH HFile^ DO
      WHILE Pos < NumbInMem DO
        IF No = RecInfo[Pos].RecNo THEN RETURN TRUE END;
        INC(Pos);
      END;
      RETURN FALSE;
   END;
END LocateRecData;

PROCEDURE RemoveFromRealHyper(Ptr:  RealStoragePntr);
VAR
   HFile:  HyperFile;
   Pos:    CARDINAL;
   temp:   CARDINAL;
   ManagementDataPtr : HyperPageManagementPntr;
BEGIN
   ManagementDataPtr := GetManagementDataPtr( Ptr^.Data ) ;
   HFile := HyperFile(ManagementDataPtr^.DataArea);
   IF NOT LocateRecData(HFile,Ptr^.Data.RecordID,Pos) THEN
      ProgramErrorAndHalt('Error In RemoveFromRealHyper')
   END;

   IF Ptr^.Data.Changed THEN WriteChangedRecord(HFile,Ptr) END;

   WITH HFile^ DO
      IF EMSAvailable THEN
         RecInfo[Pos].RecData.Position := RealToEMS(RecInfo[Pos].RecData.Position);
         RecInfo[Pos].RecData.Location := InEMS;
      ELSE
         DEC(NumbInMem);
         IF Pos < NumbInMem THEN
            Lib.Move(ADR(RecInfo[Pos+1]),ADR(RecInfo[Pos]),(NumbInMem-Pos) * SIZE(RecInfoType));
         END;
      END;
   END;
END RemoveFromRealHyper;

PROCEDURE RemoveFromEMSHyper(PageNo: CARDINAL);
VAR
   HFile:  HyperFile;
   Pos:    CARDINAL;
   ManagementDataPtr : HyperPageManagementPntr;
BEGIN
   WITH EMSInfo^ DO
      ManagementDataPtr := GetManagementDataPtr(EMSPageInfo[PageNo]) ;
      HFile := HyperFile(ManagementDataPtr^.DataArea);
      IF NOT LocateRecData(HFile,EMSPageInfo[PageNo].RecordID,Pos) THEN
         ProgramErrorAndHalt('Error In RemoveFromEMSHyper')
      END;
      SetManagementDataPtr(EMSPageInfo[PageNo], NIL);
   END;
   WITH HFile^ DO
      DEC(NumbInMem);
      IF Pos < NumbInMem THEN
         Lib.Move(ADR(RecInfo[Pos+1]),ADR(RecInfo[Pos]),
                (NumbInMem-Pos) * SIZE(RecInfoType));
      END;
   END;
END RemoveFromEMSHyper;

PROCEDURE OpenHyperFile(VAR HFile:    HyperFile;
                            FileName: ARRAY OF CHAR;
                            Mode:     IOModeType;
                        VAR ErrMsg:   ARRAY OF CHAR):BOOLEAN;
VAR
   res:        CARDINAL;
BEGIN
   NEW(HFile);

   IF (Mode = readmode) THEN  HFile^.ID := FIO.OpenRead(FileName)
   ELSIF (Exist(FileName)) THEN  HFile^.ID := FIO.Open(FileName)
   ELSE HFile^.ID := FIO.Create(FileName) END;

   res := FIO.IOresult();
   IF res <> 0 THEN
      IOErrorMessage( res ,ErrMsg);
      DISPOSE(HFile);
      HFile := NIL;
      RETURN FALSE;
   END;


   WITH HFile^ DO
      NEW(ManagementData);
      NumbInMem := 0;
      NumbInUse := 0;
      Str.Copy(Name,FileName);
      NumbRecs := HyperFileSize(HFile);
      TruncOK := FALSE;
   END;

   WITH HFile^.ManagementData^ DO
      RemoveFromReal :=    RemoveFromRealHyper;
      RemoveFromEMS :=     RemoveFromEMSHyper;
      DataArea := HFile;
   END;
(*<Dbg
    TWriteString('OpenHyperFile ends file:');
    TWriteString(HFile^.Name);
    TWriteString(',NumbRecs:');
    TWriteCard(HFile^.NumbRecs,0);
    TWriteLn;
Dbg>*)
   RETURN TRUE;
END OpenHyperFile;

PROCEDURE SetTruncOK(HFile: HyperFile);
BEGIN
   HFile^.TruncOK := TRUE;
END SetTruncOK;

PROCEDURE GetNumbRecs(HFile: HyperFile): CARDINAL;
BEGIN
   RETURN HFile^.NumbRecs;
END GetNumbRecs;

PROCEDURE FIOFile(HFile: HyperFile;
              VAR Rslt:  FIO.File);
BEGIN
   Rslt := HFile^.ID;
END FIOFile;


PROCEDURE CloseHyperFile(VAR HFile:   HyperFile;
                         VAR ErrMsg:  ARRAY OF CHAR): BOOLEAN;
VAR
   res:        CARDINAL;
   MsgStr:     ARRAY [0..40] OF CHAR;
   Pos:        CARDINAL;
BEGIN
   WITH HFile^ DO
      IF NumbInMem > 0 THEN
	FOR Pos := NumbInMem - 1 TO 0 BY -1 DO	(* changed to descending order of loop *LP* *)
          IF RecInfo[Pos].RecData.Location = InEMS THEN
              ReleaseEMSPage(RecInfo[Pos].RecData.Position);
          ELSIF RecInfo[Pos].RecData.Location = InReal THEN
              ReleaseRealPage(RecInfo[Pos].RecData.Position);
          ELSIF RecInfo[Pos].RecData.Location = OnDisk THEN
	      (* be safe and just ignore this one *LP* *)
          ELSE
              ProgramErrorAndHalt('Unexpected Location during HFile Close')
          END;
	END ;	(* FOR Pos := NumbInMem - 1 TO 0 BY -1 DO *)
      END;
      DISPOSE(ManagementData);
   END;

   FIO.Close(HFile^.ID);
   res := FIO.IOresult();
   IF res <> 0 THEN
      IOErrorMessage( res ,MsgStr);
      (*RES OLD MSG 137
      UseBase could not close File "%0": %1.
      *)
      MsgString(HFile^.Name,0);
      MsgString(MsgStr,0);
      GetResMessage( (*RES REM INS*) 137 , ErrMsg);
      RETURN FALSE;
   END;
   DISPOSE(HFile);
   RETURN TRUE;
END CloseHyperFile;

PROCEDURE WriteAll(VAR HFile:  HyperFile);
VAR
      Pos:  CARDINAL;
      p:    RealStoragePntr;
BEGIN
   WITH HFile^ DO
      IF NumbInMem > 0 THEN
	FOR Pos := 0 TO NumbInMem - 1 DO
         IF RecInfo[Pos].RecData.Location = InReal THEN
            p := SegmentToReal(RecInfo[Pos].RecData.Position);
            IF p^.Data.Changed THEN WriteChangedRecord(HFile,p) END;
            p^.Data.Changed := FALSE;
         END;
	END ;
      END;
   END;
END WriteAll;

PROCEDURE MoveRefNoToFront(HFile: HyperFile;
                           Pos:   CARDINAL);
VAR temp: RecInfoType;
BEGIN
   IF Pos = 0 THEN RETURN END;
   temp := HFile^.RecInfo[Pos];
   Lib.Move(ADR(HFile^.RecInfo[0]),ADR(HFile^.RecInfo[1]),
            Pos * SIZE(RecInfoType));
   HFile^.RecInfo[0] := temp;
END MoveRefNoToFront;

PROCEDURE GetNewSlotForRecord(HFile:  HyperFile;
                          VAR CX:     RealStoragePntr);
VAR Pos: CARDINAL;
    seg: CARDINAL;
BEGIN
   WITH HFile^ DO
      IF NumbInMem = MaxFileNumbInMem THEN
         Pos := MaxFileNumbInMem;
         REPEAT DEC(Pos) UNTIL (Pos = 0) OR (RecInfo[Pos].RecData.Location = InEMS);
         IF (RecInfo[Pos].RecData.Location = InReal) THEN
            Pos := MaxFileNumbInMem;
            REPEAT
               DEC(Pos);
               CX := SegmentToReal(RecInfo[Pos].RecData.Position);
            UNTIL (Pos = 0) OR (CX^.Data.UseCount = 0);
            IF CX^.Data.UseCount <> 0 THEN
               ProgramErrorAndHalt('Cannot find record to free In GetNewSlot...')
            END;
            IF CX^.Data.Changed THEN WriteChangedRecord(HFile,CX) END;
            seg := RecInfo[Pos].RecData.Position;
            CX := RealReference(seg);
         ELSE
            ReleaseEMSPage(RecInfo[Pos].RecData.Position);
	    INC(NumbInMem);
            seg := GetRealHyperPage(CX);
         END;
      ELSE
         Pos := NumbInMem;
         INC(NumbInMem);
         seg := GetRealHyperPage(CX);
      END;

      MoveRefNoToFront(HFile,Pos);
      RecInfo[0].RecData.Position := seg;
      RecInfo[0].RecData.Location := InReal;
   END;
END GetNewSlotForRecord;

PROCEDURE GetBaseHyper(RecNo:     CARDINAL;
                   VAR CX:        RealStoragePntr;
                   VAR HFile:     HyperFile);
VAR
   Pos:   CARDINAL;
   res:   CARDINAL;
   count: CARDINAL;
BEGIN
   WITH HFile^ DO
      IF LocateRecData(HFile, RecNo, Pos) THEN
         IF RecInfo[Pos].RecData.Location = InReal THEN
            CX := RealReference(RecInfo[Pos].RecData.Position);
         ELSIF RecInfo[Pos].RecData.Location = InEMS THEN
            RecInfo[Pos].RecData.Location := InReal;
            RecInfo[Pos].RecData.Position :=
               EMSToReal(RecInfo[Pos].RecData.Position);
            CX := RealReference(RecInfo[Pos].RecData.Position);
         ELSE
             ProgramErrorAndHalt('Unexpected Location during GetBaseHyper')
         END;
         MoveRefNoToFront(HFile,Pos);
      ELSE
         GetNewSlotForRecord(HFile, CX);

         RecInfo[0].RecNo := RecNo;
         WITH CX^.Data DO
            SetManagementDataPtr(CX^.Data, HFile^.ManagementData );
            RecordID := RecNo;
            Changed := FALSE;
            UseCount := 0;
         END;
         res := SeekHyperRecord(ID, RecNo);
         IF res <> 0 THEN
             ProgramErrorAndHalt('Error (2) Positioning HyperFile');
         END;

         count := FIO.RdBin(ID, CX^.HRecord, HyperLength);
         res := FIO.IOresult();
         IF (TruncOK) AND (count < HyperLength) AND (res = 0) THEN
             CX^.HRecord.TextData[count] := 032C (* ^Z j.b. *)
         ELSIF (count < HyperLength) OR (res <> 0) THEN
             ProgramErrorAndHalt('Error (3) Reading from HyperFile');
         END;
      END;

      INC(CX^.Data.UseCount);
      INC(NumbInUse);
   END;
END GetBaseHyper;

PROCEDURE MakeNewBaseHyper(VAR RecNo:     CARDINAL;
                           VAR CX:        RealStoragePntr;
                           VAR HFile:     HyperFile;
                           VAR ErrMsg:    ARRAY OF CHAR): BOOLEAN;
VAR
      res:  CARDINAL;

PROCEDURE GetIOError;
VAR
      MsgStr:    StrAny;
BEGIN
   IOErrorMessage( res ,MsgStr);
   (*RES OLD MSG 138
   An error occurred adding to File "%0": %1.
   *)
   MsgString(HFile^.Name,0);
   MsgString(MsgStr,0);
   GetResMessage( (*RES REM INS*) 138 , ErrMsg);
END GetIOError;

BEGIN
(*<Dbg
    TWriteString('MakeNewBaseHyper begins file:');
    TWriteString(HFile^.Name);
    TWriteString(',NumbRecs:');
    TWriteCard(HFile^.NumbRecs,0);
    TWriteLn;
Dbg>*)
   RecNo := HyperFileSize(HFile);
   GetNewSlotForRecord(HFile, CX);

   HFile^.RecInfo[0].RecNo := RecNo;
   WITH CX^.Data DO
      SetManagementDataPtr(CX^.Data, HFile^.ManagementData );
      RecordID := RecNo;
      Changed := TRUE;
      UseCount := 1;
   END;
   Lib.Fill(ADR(CX^.HRecord), HyperLength, 0C);

   WITH CX^.HRecord DO
      FirstFree := 1;
      PDBCardinal[1] := HNoPDBWords;
      PDBCardinal[2] := 0;
   END;

   FIO.Seek(HFile^.ID,FIO.Size(HFile^.ID));
   res := FIO.IOresult();
   IF res <> 0 THEN
      GetIOError;
      RETURN FALSE;
   END;

   FIO.WrBin(HFile^.ID, CX^.HRecord, HyperLength);
   res := FIO.IOresult();
   IF res <> 0 THEN
      GetIOError;
      RETURN FALSE;
   END;

(*  The file is closed and reopened to ensure that DOS remembers that
    a new block has been added to the end of the file *)

   FIO.Close(HFile^.ID);
   res := FIO.IOresult();
   IF res <> 0 THEN
      GetIOError;
      RETURN FALSE;
   END;

   HFile^.ID := FIO.Open(HFile^.Name);
   res := FIO.IOresult();
   IF res <> 0 THEN
      GetIOError;
      RETURN FALSE;
   END;

   INC(HFile^.NumbRecs);

   INC(HFile^.NumbInUse);
   INC(HFile^.NumbInMem);
(*<Dbg
    TWriteString('MakeNewBaseHyper ends file:');
    TWriteString(HFile^.Name);
    TWriteString(',NumbRecs:');
    TWriteCard(HFile^.NumbRecs,0);
    TWriteLn;
Dbg>*)
    RETURN TRUE;
END MakeNewBaseHyper;

PROCEDURE ReleaseBaseHyper(VAR HFile: HyperFile;
                           VAR CX:    RealStoragePntr);
BEGIN
    DEC(CX^.Data.UseCount);
    DEC(HFile^.NumbInUse);
    CX := NIL;
END ReleaseBaseHyper;

BEGIN
    WITH NilHRecPntr DO
	Rec := 0 ;
	Idx := 0 ;
    END ;
END HyperBase.
