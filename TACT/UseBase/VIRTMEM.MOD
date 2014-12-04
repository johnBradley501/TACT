IMPLEMENTATION MODULE VirtMem;

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

(*V1=JPI1 *)
(*V2=JPI3 *)
(*V3=Trace *)
(*V4=Check *)

(*<Trace IMPORT Trace ; Trace>*)

IMPORT FIO, Lib, Str;
(*<Check*)
FROM DBData IMPORT TDBFileName;
(*Check>*)
FROM SYSTEM IMPORT BYTE, ADDRESS;
FROM GlobalDefs IMPORT StrAny, FileNameType ;
FROM MemoryManagement IMPORT
  (* const *) ParagraphSize, EMSPageSize, MaxNoEMSPages, MinMemAvail,
  (* types *) HyperPageManagementRecord, HyperPageManagementPntr,
              KiloInfo, RealStorageRecord, RealStoragePntr, HRecordPntr,
              HRecordArrayPntr, EMSInfoPagePntr, RecordLocationType,
              LocationRecord,
  (* vars  *) EMSAvailable, EMSInfo,
  (* procs *) SetupMemoryManagement, RealReference, LocateEMSPage,
              SegmentToReal, GetRealHyperPage, GetNewEMSPage, EMSToReal,
              RealToEMS, ReleaseRealPage, ReleaseEMSPage, SetShowBusyWindow,
              GetManagementDataPtr, SetManagementDataPtr, ALLOCATE, DEALLOCATE,
              ShowBusy, MarkRealAsNotInUse;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM HyperDataModel IMPORT HyperData, HyperLength, HNoPDBWords,
     PDBIDModel, IDType, ThisPDBVersion;
FROM UtilsTwo IMPORT IOErrorMessage;
FROM Utils IMPORT
  (* proc *) UpcaseStr, GetEnv, Exist, InstallTermProc, TrimBlanks ;
FROM DiskDirectory IMPORT
  (* Procs *)  CurrentDrive, SelectDrive, CurrentDirectory, ChangeDirectory ;
FROM ResMessages IMPORT
   (*proc*)  MsgString, PutResWarning, PutResError, GetResMessage, ResAskUser;

(* from .def file
TYPE
   VirtAddr = RECORD
      PageNo:    CARDINAL;
      Offset:    CARDINAL;
   END;
*)
(*<Check*)
  TYPE
    PDBHeader = RECORD
       TYear      : CARDINAL ;
       TMonth     : CARDINAL ;
       TDay       : CARDINAL ;
       CListLoc   : VirtAddr ;
       PoolData   : VirtAddr ;
       OtherItems : VirtAddr ;
       TFileName  : ARRAY [0..99] OF CHAR;
    END;
(*Check>*)

CONST
   (*RES OLD MSG 351
   This is not a "Type 2" .GIX file.
   *)
   NotPDBRes = (*RES REM INS*) 351 ;

TYPE
   AddrType = RECORD
      OFFSET:     CARDINAL;
      SEGMENT:    CARDINAL;
   END;

   VirtLocDataType = RECORD
      DiskPos:     CARDINAL;
      PoolNo:      CARDINAL;
      SpaceFree:   CARDINAL;
      Loc:         LocationRecord;
   END;

   IdxLocDataType = RECORD
      DiskPos:      CARDINAL;
      Loc:          LocationRecord;
   END;

CONST
   MaxVirtIndexSize = 300;
   (* FirstTempPool = MAX(CARDINAL) DIV 2 + 1;    <-- now in .DEF *)
   FirstTempPage = FirstTempPool ;
   NoLocsPerHyper = SIZE(HyperData) DIV SIZE(VirtLocDataType);
   PDBSignature = CARDINAL(032C);
   EndOfSpaceMarker = MAX(CARDINAL) - 1 ;
   FreedSpaceMarker = MAX(CARDINAL) - 2 ;
   MaxCurPages = 11 ;

TYPE
   VirtLocDataTypes = (Wheres, HRecords, VirtLocsR);

   VirtLocData = RECORD
      CASE : VirtLocDataTypes OF
        Wheres:
            Where:   ARRAY[0..NoLocsPerHyper-1] OF VirtLocDataType;
      | VirtLocsR: (* this is the first record, always! *)
            PhFF:       CARDINAL ; (* not used -- here to match PDB version 1 *)
            PDBId:      IDType; (* this is a PDB signature: PDBIDModel *)
            PDBVersion: CARDINAL ; (* last item that matches PDB version 1 layout *)
            WSSize:     CARDINAL;
            DiskP:      ARRAY[0..MaxVirtIndexSize-1] OF CARDINAL;
      | HRecords:
            HRecord: HyperData;
      END;
   END;
   CurrentPageRec = RECORD
			Pool : CARDINAL ;
			Page : CARDINAL ;
		    END ;
   VirtLocDataPntr = POINTER TO VirtLocData;

   VirtMemFileData = RECORD
      FileID:       FIO.File;
      FName:        ARRAY[0..40] OF CHAR;
      CurrentPages: ARRAY[0..MaxCurPages] OF CurrentPageRec ;
      WorkSpaceSize:CARDINAL;
      IdxMPMR:      HyperPageManagementPntr;
      DtaMPMR:      HyperPageManagementPntr;
      VirtLocs:     ARRAY[0..MaxVirtIndexSize-1] OF IdxLocDataType;
      tempfile:     BOOLEAN;
   END;
   VirtMemFile = POINTER TO VirtMemFileData;

VAR
   TempFile:     VirtMemFile;
   TempFileName : FileNameType;
(*<Check*)
   CurRecNo:     CARDINAL;
(*Check>*)


PROCEDURE VirtFileSize(File: VirtMemFile): CARDINAL;
VAR
      size: LONGCARD;
BEGIN
    size := FIO.Size(File^.FileID);
    IF FIO.IOresult() <> 0 THEN
      ProgramErrorAndHalt('Error In VirtFileSize after FIO.Size');
    END;
    RETURN VAL(CARDINAL, size DIV HyperLength);
END VirtFileSize;

PROCEDURE SeekVirtFile(File: VirtMemFile; RecNo:  CARDINAL);
BEGIN
   FIO.Seek(File^.FileID, VAL(LONGCARD,RecNo) * HyperLength);
   IF FIO.IOresult() <> 0 THEN
      ProgramErrorAndHalt('Error In SeekVirtFile after FIO.Seek');
   END;
(*<Check*)
   CurRecNo := RecNo;
(*Check>*)
END SeekVirtFile;

PROCEDURE WriteToVirtFile(VAR File:    VirtMemFile;
                          VAR HRec:   HyperData);
VAR res:   CARDINAL;
(*<Check*)
   PDBHeaderPtr:  POINTER TO PDBHeader;
(*Check>*)

PROCEDURE WrtErrAndStop;
VAR   IOErrMsg	: ARRAY[0..50] OF CHAR;
      ErrMsg	: StrAny;
BEGIN
   IOErrorMessage( res ,IOErrMsg);
   (*RES OLD MSG 352
   An error occurred while trying to write to %0: %1.
   *)
   MsgString(File^.FName,0);
   MsgString(IOErrMsg,0);
   GetResMessage( (*RES REM INS*) 352 , ErrMsg );
   ProgramErrorAndHalt( ErrMsg ) ;
END WrtErrAndStop;

BEGIN
(*<Check*)
   IF (File <> TempFile) AND (CurRecNo = 1) THEN
      PDBHeaderPtr := ADR(HRec.TextData[2]);
      IF Str.Compare(TDBFileName, PDBHeaderPtr^.TFileName) <> 0 THEN
         res := 0; (* a place to trap execution *)
         ProgramErrorAndHalt('Bad writing of record 1')
      END;
   END;
   INC(CurRecNo);
(*Check>*)
   FIO.WrBin(File^.FileID, HRec, HyperLength);
   res := FIO.IOresult();
   IF res <> 0 THEN WrtErrAndStop END;
END WriteToVirtFile;

PROCEDURE ReadFromVirtFile(VAR File:    VirtMemFile;
                           VAR HRec:    HyperData);
VAR ct,res:   CARDINAL;

PROCEDURE WriteErrorAndStop;
VAR   IOErrMsg	: ARRAY[0..50] OF CHAR;
      ErrMsg	: StrAny;
BEGIN
   IOErrorMessage( res ,IOErrMsg);
   (*RES OLD MSG 353
   An error occurred while trying to read from %0: %1.
   *)
   MsgString(File^.FName,0);
   MsgString(IOErrMsg,0);
   GetResMessage( (*RES REM INS*) 353 , ErrMsg );
   ProgramErrorAndHalt( ErrMsg ) ;
END WriteErrorAndStop;

BEGIN
   ct := FIO.RdBin(File^.FileID, HRec, HyperLength);
   res := FIO.IOresult();
   IF (res = 0) AND (ct <> HyperLength) THEN res := 20 END;
   IF (res <> 0) THEN WriteErrorAndStop END;
END ReadFromVirtFile;

PROCEDURE WriteHRecToDisk(TheFile:   VirtMemFile;
                      VAR Pos:       CARDINAL;
                      VAR HRecord:   HyperData);
BEGIN
   IF Pos = MAX(CARDINAL) THEN
      Pos := VirtFileSize(TheFile);
   END;
   SeekVirtFile(TheFile, Pos);
   WriteToVirtFile(TheFile, HRecord);
END WriteHRecToDisk;

PROCEDURE WriteRealPageToDisk(TheFile:   VirtMemFile;
                              TPtr:      VirtLocDataPntr;
                              LocOffset: CARDINAL;
   (* to avoid copying *) VAR HRecord:   HyperData);
BEGIN
   WriteHRecToDisk(TheFile, TPtr^.Where[LocOffset].DiskPos,HRecord);
END WriteRealPageToDisk;

PROCEDURE RemoveFromRealPageWork(Ptr:    RealStoragePntr;
                                 UseEMS: BOOLEAN);
VAR  idx, EMSPos: CARDINAL;
     hr		: VirtLocData;
     hrp	: VirtLocDataPntr;
     LocItem,
     LocOffset	: CARDINAL;
     DoLater	: BOOLEAN;
     tPtr	: RealStoragePntr;
     TheFile	: VirtMemFile;
     ManagementDataPtr : HyperPageManagementPntr;
BEGIN
   idx := Ptr^.Data.RecordID;
   IF idx >= FirstTempPage THEN  DEC(idx, FirstTempPage)  END;

   ManagementDataPtr := GetManagementDataPtr( Ptr^.Data ) ;
   TheFile	:= VirtMemFile(ManagementDataPtr^.DataArea);
   LocItem	:= idx DIV NoLocsPerHyper;
   LocOffset	:= idx MOD NoLocsPerHyper;
   IF UseEMS AND (TheFile^.VirtLocs[LocItem].Loc.Location = InEMS) THEN
	hrp := VirtLocDataPntr( LocateEMSPage(TheFile^.VirtLocs[LocItem].Loc.Position));
	EMSPos := RealToEMS(hrp^.Where[LocOffset].Loc.Position);
	(* hrp may now be unreliable, recalculate it later *)
	DoLater := TRUE;
   ELSE
	DoLater := FALSE
   END ;

   WITH TheFile^ DO
      CASE VirtLocs[LocItem].Loc.Location OF
        UndefinedLocation:
           ProgramErrorAndHalt('Bad VirtLocs in RemoveFromRealPage');
      | OnDisk:
           SeekVirtFile(TheFile,VirtLocs[LocItem].DiskPos);
           ReadFromVirtFile(TheFile, hr.HRecord);
           hrp := ADR(hr);
      | InReal:
           tPtr := SegmentToReal(VirtLocs[LocItem].Loc.Position);
           tPtr^.Data.Changed := TRUE;
           hrp := ADR(tPtr^.HRecord);
      | InEMS:
           hrp := VirtLocDataPntr(LocateEMSPage(VirtLocs[LocItem].Loc.Position));
           EMSInfo^.EMSPageInfo[VirtLocs[LocItem].Loc.Position].Changed := TRUE;
      END;

      IF UseEMS THEN
	 IF DoLater THEN
	    hrp^.Where[LocOffset].Loc.Position := EMSPos ;
	 ELSE  (* never done if ...Location = InEMS, so its safe! *)
	    hrp^.Where[LocOffset].Loc.Position := RealToEMS(hrp^.Where[LocOffset].Loc.Position);
	 END ;
         hrp^.Where[LocOffset].Loc.Location := InEMS;
      ELSE
         IF Ptr^.Data.Changed THEN
            WriteRealPageToDisk(TheFile, hrp, LocOffset, Ptr^.HRecord);
            Ptr^.Data.ManagementData := 0 ;
            Ptr^.Data.Changed := FALSE ;	(* *LP2* *)
         END;
         hrp^.Where[LocOffset].Loc.Location := OnDisk;
      END;
      IF VirtLocs[LocItem].Loc.Location = OnDisk THEN
         SeekVirtFile(TheFile,VirtLocs[LocItem].DiskPos);
         WriteToVirtFile(TheFile,hr.HRecord);
      END;
   END;
END RemoveFromRealPageWork;

PROCEDURE RemoveFromRealPage(Ptr:    RealStoragePntr);
BEGIN
   RemoveFromRealPageWork(Ptr, EMSAvailable);
END RemoveFromRealPage;

PROCEDURE RemoveFromEMSPage(PageNo: CARDINAL);
VAR  idx,ct: CARDINAL;
     hr:     VirtLocData;
     vldp:   VirtLocDataPntr;
     tPtr:   RealStoragePntr;
     LocItem,
     LocOffset: CARDINAL;
     hrp:     HRecordPntr;
     TheFile: VirtMemFile;
     ManagementDataPtr : HyperPageManagementPntr;
BEGIN
   WITH EMSInfo^ DO
      idx := EMSPageInfo[PageNo].RecordID;
      IF EMSPageInfo[PageNo].RecordID >= FirstTempPage THEN DEC(idx, FirstTempPage) END;
      ManagementDataPtr := GetManagementDataPtr(EMSPageInfo[PageNo]) ;
      TheFile := VirtMemFile(ManagementDataPtr^.DataArea);
   END;

   LocItem := idx DIV NoLocsPerHyper;
   LocOffset := idx MOD NoLocsPerHyper;

   WITH TheFile^ DO
      CASE VirtLocs[LocItem].Loc.Location OF
        UndefinedLocation:
           ProgramErrorAndHalt('Bad VirtLocs in RemoveFromEMSPage');
      | OnDisk:
           SeekVirtFile(TheFile,VirtLocs[LocItem].DiskPos);
           ReadFromVirtFile(TheFile, hr.HRecord);
           vldp := ADR(hr);
      | InReal:
           tPtr := SegmentToReal(VirtLocs[LocItem].Loc.Position);
           tPtr^.Data.Changed := TRUE;
           vldp := ADR(tPtr^.HRecord);
      | InEMS:
           vldp := VirtLocDataPntr(LocateEMSPage(VirtLocs[LocItem].Loc.Position));
           EMSInfo^.EMSPageInfo[VirtLocs[LocItem].Loc.Position].Changed := TRUE;
      END;
      vldp^.Where[LocOffset].Loc.Location := OnDisk;
      WITH EMSInfo^ DO
         EMSPageInfo[PageNo].ManagementData := 0 ;
         IF EMSPageInfo[PageNo].Changed THEN
	    hrp := LocateEMSPage(PageNo);
            WriteHRecToDisk(TheFile,vldp^.Where[LocOffset].DiskPos,hrp^);
         END;
      END;
      IF VirtLocs[LocItem].Loc.Location = OnDisk THEN
         SeekVirtFile(TheFile,VirtLocs[LocItem].DiskPos);
         WriteToVirtFile(TheFile,hr.HRecord);
      END;
   END;
END RemoveFromEMSPage;

PROCEDURE RemoveFromRealIdxWork(Ptr:    RealStoragePntr;
                                UseEMS: BOOLEAN);
VAR  idx:     CARDINAL;
     TheFile: VirtMemFile;
     ManagementDataPtr : HyperPageManagementPntr;
BEGIN
   idx := Ptr^.Data.RecordID;
   ManagementDataPtr := GetManagementDataPtr( Ptr^.Data ) ;
   TheFile := VirtMemFile(ManagementDataPtr^.DataArea);

   WITH TheFile^ DO
      IF UseEMS THEN
         VirtLocs[idx].Loc.Position := RealToEMS(VirtLocs[idx].Loc.Position);
         VirtLocs[idx].Loc.Location := InEMS;
      ELSE
         Ptr^.Data.ManagementData := 0;
         IF Ptr^.Data.Changed THEN
            WriteHRecToDisk(TheFile, VirtLocs[idx].DiskPos, Ptr^.HRecord);
	    Ptr^.Data.Changed := FALSE ;	(* *LP2* *)
         END;
         VirtLocs[idx].Loc.Location := OnDisk;
      END;
   END;
END RemoveFromRealIdxWork;

PROCEDURE RemoveFromRealIdx(Ptr:  RealStoragePntr);
BEGIN
   RemoveFromRealIdxWork(Ptr, EMSAvailable);
END RemoveFromRealIdx;

PROCEDURE RemoveFromEMSIdx(PageNo: CARDINAL);
VAR
   HRP:    HRecordPntr;
   TheFile: VirtMemFile;
   idx:    CARDINAL;
   ManagementDataPtr : HyperPageManagementPntr;
BEGIN
   WITH EMSInfo^ DO
      ManagementDataPtr := GetManagementDataPtr(EMSPageInfo[PageNo]) ;
      TheFile := VirtMemFile(ManagementDataPtr^.DataArea);
      idx := EMSPageInfo[PageNo].RecordID;
      TheFile^.VirtLocs[idx].Loc.Location := OnDisk;
      IF EMSPageInfo[PageNo].Changed THEN
         HRP := LocateEMSPage(PageNo);
         WriteHRecToDisk(TheFile, TheFile^.VirtLocs[idx].DiskPos, HRP^);
      END;
      EMSPageInfo[PageNo].ManagementData := 0;
   END;
END RemoveFromEMSIdx;

PROCEDURE OpenVirtFile(Name:   ARRAY OF CHAR;
                   VAR file:   VirtMemFile;
                   VAR ErrMsg: ARRAY OF CHAR;
                       tmpfile:BOOLEAN): BOOLEAN;
VAR res:   CARDINAL;
    tld:   VirtLocData;
    ct,i:  CARDINAL;
    sz:    LONGCARD;
    answ:  CHAR;

PROCEDURE handleIOerror(): BOOLEAN;
BEGIN
   IOErrorMessage( res ,ErrMsg);
   DISPOSE(file);
   file := NIL;
   RETURN FALSE;
END handleIOerror;

PROCEDURE MakeNew;
BEGIN
   WITH file^ DO
      Lib.WordFill(ADR(tld),HyperLength DIV 2, MAX(CARDINAL));
      tld.PDBId := PDBIDModel;
      tld.PDBVersion := ThisPDBVersion;
      tld.WSSize := 0;
      IF NOT tmpfile THEN WriteToVirtFile(file, tld.HRecord) END;
   END;
END MakeNew;

BEGIN
   ErrMsg[0] := 0C;
   NEW(file);
   WITH file^ DO
      IF (NOT tmpfile) AND Exist(Name) THEN
          FileID := FIO.Open(Name);
          res := FIO.IOresult();
          IF res <> 0 THEN RETURN handleIOerror() END;
          sz := FIO.Size(FileID);
          res := FIO.IOresult();
          IF res <> 0 THEN RETURN handleIOerror() END;
          IF (sz = 0) THEN
(*RES OLD CHE 24
The file named "%0" exists but is empty.  To initialize it as
a Group Index, type "Y"; or to avoid using it, type "N":
=YN
*)
             MsgString(Name, 0);
             ResAskUser( (*RES REM INS*) 24 , 'YN', answ);
             IF answ = 'N' THEN
                GetResMessage( NotPDBRes , ErrMsg );
                DISPOSE(file);
                file := NIL;
                RETURN FALSE
             ELSE
                MakeNew;
             END;
          ELSE
             IF sz MOD HyperLength <> 0 THEN
                GetResMessage( NotPDBRes , ErrMsg );
                DISPOSE(file);
                file := NIL;
                RETURN FALSE
             END;
             ReadFromVirtFile(file, tld.HRecord);
             IF (tld.PDBId <> PDBIDModel) OR (tld.PDBVersion <> ThisPDBVersion) THEN
                GetResMessage( NotPDBRes , ErrMsg );
                DISPOSE(file);
                file := NIL;
                RETURN FALSE
             ELSIF (tld.PDBVersion <> ThisPDBVersion) THEN
                (*RES OLD MSG 153
                Your .GIX File belongs to another version of UseBase.
                *)
                GetResMessage( (*RES REM INS*) 153 , ErrMsg );
                DISPOSE(file);
                file := NIL;
                RETURN FALSE
             END;
          END;
      ELSE
         FileID := FIO.Create(Name);
         res := FIO.IOresult();
         IF res <> 0 THEN RETURN handleIOerror() END;
         MakeNew;
      END;
      Str.Copy(FName, Name);
      WorkSpaceSize := tld.WSSize;
      FOR i := 0 TO MaxCurPages DO
	 WITH CurrentPages[i] DO
		Pool := MAX(CARDINAL);
		Page := MAX(CARDINAL);
	 END ;
      END ;
      FOR i := 0 TO MaxVirtIndexSize-1 DO
         WITH VirtLocs[i] DO
            DiskPos := tld.DiskP[i];
            IF DiskPos = MAX(CARDINAL) THEN Loc.Location := UndefinedLocation
            ELSE Loc.Location := OnDisk END;
         END;
      END;
      NEW(IdxMPMR);
      WITH IdxMPMR^ DO
        RemoveFromReal := RemoveFromRealIdx;
        RemoveFromEMS := RemoveFromEMSIdx;
        DataArea := file;
      END;
      NEW(DtaMPMR);
      WITH DtaMPMR^ DO
        RemoveFromReal := RemoveFromRealPage;
        RemoveFromEMS := RemoveFromEMSPage;
        DataArea := file;
      END;
      tempfile := tmpfile;
   END;
   RETURN TRUE;
END OpenVirtFile;

PROCEDURE DisposeTempFile;
BEGIN
   FIO.Close(TempFile^.FileID);
   FIO.Erase(TempFileName);
END DisposeTempFile;

PROCEDURE InitVirtMem;
VAR
    IOErrMsg	: ARRAY[0..40] OF CHAR;
    ErrMsg	: StrAny ;
    TempDiskArea: FileNameType;

PROCEDURE VerifyTDA( VAR TempDiskArea : ARRAY OF CHAR) ;
   VAR
      TDADone	: BOOLEAN ;
      Done	: BOOLEAN ;
      drive	: CHAR ;
      dir	: StrAny ;
      TDALen	: CARDINAL ;
      I		: CARDINAL ;
   BEGIN
      TrimBlanks( TempDiskArea, TempDiskArea ) ;
      IF TempDiskArea[0] = 0C THEN  RETURN  END ;
      UpcaseStr( TempDiskArea, TempDiskArea ) ;
      TDALen := Str.Length( TempDiskArea ) ;
      IF TempDiskArea[TDALen-1] = '\' THEN
	 DEC( TDALen ) ;
	 TempDiskArea[TDALen] := 0C ;
      END ;
      IF (TempDiskArea[1] = ':') AND (TempDiskArea[2] <> '\')THEN
	 (* make room to insert a "\" after ":" *)
	 FOR I := TDALen TO 3 BY -1 DO
	     TempDiskArea[I] := TempDiskArea[I-1] ;
	 END ;
	 TempDiskArea[2] := '\' ;
	 INC( TDALen ) ;
	 TempDiskArea[TDALen] := 0C ;
      END ;

      CurrentDrive( drive ) ;
      CurrentDirectory( drive, dir ) ;
      (* note: "CurrentDirectory" doesnot return leading "\", need it for CHDIR *)
      IF dir[0] <> '\' THEN  Str.Insert( dir, '\', 0 )  END ;

      (* see if drive/path exists *)
      ChangeDirectory( TempDiskArea, TDADone ) ;

      (* restore drive/path *)
      SelectDrive( drive ) ;
      ChangeDirectory( dir, Done ) ;

      IF TDADone THEN
	 IF TempDiskArea[TDALen-1] <> '\' THEN
	    TempDiskArea[TDALen] := '\' ;
	    TempDiskArea[TDALen+1] := 0C ;
	 END ;
      ELSE
         (* >> RES OLD MSG 175  <--- from MAKBAS
         Invalid Drive/Path specification for temporary disk space "%0".
         *)
         MsgString( TempDiskArea, 0 );
         PutResWarning( (*RES REM INS*) 175 ) ;
         TempDiskArea[0] := 0C ;
      END;
   END VerifyTDA ;

BEGIN
   SetupMemoryManagement;

   GetEnv( 'TACTWRK', TempDiskArea);
   VerifyTDA(TempDiskArea) ;
   IF TempDiskArea[0] <> 0C THEN  Str.Insert( TempFileName, TempDiskArea, 0 )  END;

   IF NOT OpenVirtFile(TempFileName, TempFile, IOErrMsg, (* tmpfile = *) TRUE) THEN
      (*RES OLD MSG 354
      UseBase cannot Run because its Temporary Working File TACT.WRK could not be opened.
      *)
      GetResMessage( (*RES REM INS*) 354 , ErrMsg );
      ProgramErrorAndHalt( ErrMsg ) ;
   END;
   InstallTermProc(DisposeTempFile);
END InitVirtMem;

PROCEDURE GetRSP(TheFile: VirtMemFile;
                 Pos:     CARDINAL;
                 TPtr:    RealStoragePntr);
VAR count:   CARDINAL;
BEGIN
   SeekVirtFile(TheFile,Pos);
   ReadFromVirtFile(TheFile, TPtr^.HRecord);
END GetRSP;

PROCEDURE FindVirtPage(PageNo:    CARDINAL;
                   VAR TheFile:   VirtMemFile;
                   VAR LocOffset: CARDINAL;
                   VAR TPtr:      RealStoragePntr): VirtLocDataPntr;
VAR
   LocItem:      CARDINAL;
   tempPageNo:   CARDINAL;
   T2Ptr:        VirtLocDataPntr;

PROCEDURE InitializeTPtr;
VAR i:       CARDINAL;
BEGIN
   T2Ptr := ADR(TPtr^.HRecord);
   WITH T2Ptr^ DO
      FOR i := 0 TO NoLocsPerHyper-1 DO
         Where[i].DiskPos := MAX(CARDINAL);
         Where[i].Loc.Location := UndefinedLocation;
      END;
   END;
END InitializeTPtr;

BEGIN
   IF PageNo < FirstTempPage THEN
      TheFile := PDBFile;
      tempPageNo := PageNo
   ELSE
      TheFile := TempFile;
      tempPageNo := PageNo - FirstTempPage;
   END;
   LocItem := tempPageNo DIV NoLocsPerHyper;
   LocOffset := tempPageNo MOD NoLocsPerHyper;
   WITH TheFile^ DO
      CASE VirtLocs[LocItem].Loc.Location OF
        UndefinedLocation:
           VirtLocs[LocItem].Loc.Position := GetRealHyperPage(TPtr);
           InitializeTPtr;
           WITH TPtr^.Data DO
	      SetManagementDataPtr( TPtr^.Data, IdxMPMR ) ;
              RecordID := LocItem;
              Changed := TRUE;
              UseCount := 1;
           END;
      | OnDisk:
           VirtLocs[LocItem].Loc.Position := GetRealHyperPage(TPtr);
           GetRSP(TheFile, VirtLocs[LocItem].DiskPos,TPtr);
           WITH TPtr^.Data DO
	      SetManagementDataPtr( TPtr^.Data, IdxMPMR ) ;
              RecordID := LocItem;
              Changed := FALSE;
              UseCount := 1;
           END;
           T2Ptr := ADR(TPtr^.HRecord);
      | InReal:
           TPtr := RealReference(VirtLocs[LocItem].Loc.Position);
           INC(TPtr^.Data.UseCount);
           T2Ptr := ADR(TPtr^.HRecord);
      | InEMS:
           VirtLocs[LocItem].Loc.Position := EMSToReal(VirtLocs[LocItem].Loc.Position);
           TPtr := SegmentToReal(VirtLocs[LocItem].Loc.Position);
           INC(TPtr^.Data.UseCount);
           T2Ptr := ADR(TPtr^.HRecord);
      END;
      VirtLocs[LocItem].Loc.Location := InReal;
      RETURN T2Ptr;
   END;
END FindVirtPage;

PROCEDURE LoadVirtPage(TheFile:   VirtMemFile;
                       T2Ptr:     VirtLocDataPntr;
                       TPtr:      RealStoragePntr;
                       LocOffset: CARDINAL;
                       PageNo:    CARDINAL): RealStoragePntr;
VAR
   DPtr:         RealStoragePntr;
BEGIN
   WITH T2Ptr^ DO
      CASE Where[LocOffset].Loc.Location OF
        UndefinedLocation:
           INC(TheFile^.WorkSpaceSize);
           TPtr^.Data.Changed := TRUE;
           Where[LocOffset].Loc.Position := GetRealHyperPage(DPtr);

           Lib.Fill(ADR(DPtr^.HRecord), HyperLength, 0C);
           WITH DPtr^.HRecord DO
              FirstFree := 1;
              PDBCardinal[1] := HNoPDBWords;
              PDBCardinal[2] := 0;
           END;

           WITH DPtr^.Data DO
	      SetManagementDataPtr( DPtr^.Data, TheFile^.DtaMPMR) ;
              RecordID := PageNo;
              Changed := TRUE;
              UseCount := 0;
           END;
      | OnDisk:
           TPtr^.Data.Changed := TRUE;
           Where[LocOffset].Loc.Position := GetRealHyperPage(DPtr);
           GetRSP(TheFile, Where[LocOffset].DiskPos,DPtr);
           WITH DPtr^.Data DO
	      SetManagementDataPtr( DPtr^.Data, TheFile^.DtaMPMR) ;
              RecordID := PageNo;
              Changed := FALSE;
              UseCount := 0;
           END;
      | InReal:
           DPtr := RealReference(Where[LocOffset].Loc.Position);
      | InEMS:
           TPtr^.Data.Changed := TRUE;
           Where[LocOffset].Loc.Position := EMSToReal(Where[LocOffset].Loc.Position);
           DPtr := SegmentToReal(Where[LocOffset].Loc.Position);
      END;
      Where[LocOffset].Loc.Location := InReal;
   END;
   DEC(TPtr^.Data.UseCount);
   RETURN DPtr;
END LoadVirtPage;

PROCEDURE LocateVirtPage(TheFile:   VirtMemFile;
                         T2Ptr:     VirtLocDataPntr;
                         TPtr:      RealStoragePntr;
                         LocOffset: CARDINAL;
                         PageNo:    CARDINAL;
                         SetChanged:BOOLEAN): HRecordPntr;
VAR
   DPtr:         RealStoragePntr;
   HPtr:         HRecordPntr;
BEGIN
   WITH T2Ptr^ DO
      CASE Where[LocOffset].Loc.Location OF
        UndefinedLocation:
           INC(TheFile^.WorkSpaceSize);
           TPtr^.Data.Changed := TRUE;
           Where[LocOffset].Loc.Position := GetRealHyperPage(DPtr);

           Lib.Fill(ADR(DPtr^.HRecord), HyperLength, 0C);
           WITH DPtr^.HRecord DO
              FirstFree := 1;
              PDBCardinal[1] := HNoPDBWords;
              PDBCardinal[2] := 0;
           END;

           WITH DPtr^.Data DO
	      SetManagementDataPtr( DPtr^.Data, TheFile^.DtaMPMR) ;
              RecordID := PageNo;
              Changed := SetChanged;
              UseCount := 0;
           END;
           Where[LocOffset].Loc.Location := InReal;
      | OnDisk:
           TPtr^.Data.Changed := TRUE;
           Where[LocOffset].Loc.Position := GetRealHyperPage(DPtr);
           GetRSP(TheFile, Where[LocOffset].DiskPos,DPtr);
           WITH DPtr^.Data DO
	      SetManagementDataPtr( DPtr^.Data, TheFile^.DtaMPMR) ;
              RecordID := PageNo;
              Changed := SetChanged;
              UseCount := 0;
           END;
           Where[LocOffset].Loc.Location := InReal;
      | InReal:
           DPtr := RealReference(Where[LocOffset].Loc.Position);
           IF SetChanged THEN DPtr^.Data.Changed := TRUE END;
      | InEMS:
           HPtr := LocateEMSPage(Where[LocOffset].Loc.Position);
           IF SetChanged THEN
              EMSInfo^.EMSPageInfo[Where[LocOffset].Loc.Position].Changed := TRUE;
           END;
           DEC(TPtr^.Data.UseCount);
           RETURN HPtr;
      END;
   END;
   DEC(TPtr^.Data.UseCount);
   HPtr := ADR(DPtr^.HRecord);
   RETURN HPtr;
END LocateVirtPage;

PROCEDURE CopyFromVirtMem(VA:    VirtAddr;
                          Sz:    CARDINAL;
                      VAR Dt:    ARRAY OF BYTE);
VAR T2Ptr:     VirtLocDataPntr;
    LocOffset: CARDINAL;
    TPtr:      RealStoragePntr;
    HPtr:      HRecordPntr;
    TheFile:   VirtMemFile;
BEGIN
   IF Sz = 0 THEN Sz := HIGH(Dt) + 1 END;
   IF VA.Offset + Sz > HyperLength THEN Sz := HyperLength - VA.Offset END;

   T2Ptr := FindVirtPage(VA.PageNo, TheFile, LocOffset, TPtr);
   HPtr := LocateVirtPage(TheFile, T2Ptr, TPtr, LocOffset, VA.PageNo, FALSE);
   Lib.Move(ADR(HPtr^.TextData[VA.Offset]),ADR(Dt),Sz);
END CopyFromVirtMem;

PROCEDURE CopyToVirtMem(VA:    VirtAddr;
                        Sz:    CARDINAL;
                        Dt:    ARRAY OF BYTE);
VAR T2Ptr:     VirtLocDataPntr;
    LocOffset: CARDINAL;
    TPtr:      RealStoragePntr;
    HPtr:      HRecordPntr;
    TheFile:   VirtMemFile;
BEGIN
   IF Sz = 0 THEN Sz := HIGH(Dt) + 1 END;
   IF VA.Offset + Sz > HyperLength THEN Sz := HyperLength - VA.Offset END;

   T2Ptr := FindVirtPage(VA.PageNo, TheFile, LocOffset, TPtr);
   HPtr := LocateVirtPage(TheFile, T2Ptr, TPtr, LocOffset, VA.PageNo, TRUE);
   Lib.Move(ADR(Dt),ADR(HPtr^.TextData[VA.Offset]),Sz);
END CopyToVirtMem;

(*<Trace
   PROCEDURE PrintAddr( VA : VirtAddr ) ;
      TYPE
	AddrParts = RECORD
			Seg : CARDINAL ;
			Ofs : CARDINAL ;
	   END ;
      VAR Addr : AddrParts ;
      BEGIN
	   IF VA = NILVirt THEN
		Trace.TWriteString( "Nil" ) ;
	   ELSE
		Addr := AddrParts( VA ) ;
		Trace.TWriteCard( Addr.Seg, 0 ) ;
		Trace.TWriteString( ":" ) ;
		Trace.TWriteCard( Addr.Ofs, 0 ) ;
	   END ;
      END PrintAddr ;
Trace>*)

PROCEDURE VMAccess(VA: VirtAddr): ADDRESS;
VAR T2Ptr:     VirtLocDataPntr;
    LocOffset: CARDINAL;
    TPtr:      RealStoragePntr;
    DPtr:      RealStoragePntr;
    HPtr:      HRecordPntr;
    TheFile:   VirtMemFile;
BEGIN
   IF VA = NILVirt THEN RETURN NIL END;
   T2Ptr := FindVirtPage(VA.PageNo, TheFile, LocOffset, TPtr);
   DPtr := LoadVirtPage(TheFile, T2Ptr, TPtr, LocOffset, VA.PageNo);

   (*<Trace
   IF Trace.DoTrace THEN
	Trace.TWriteString( "A " ) ;
	PrintAddr( VA ) ;
	Trace.TWriteString( " " ) ;
	Trace.TWriteAddr( DPtr ) ;
	Trace.TWriteString( " " ) ;
	Trace.TWriteCard( VAL(CARDINAL,DPtr^.Data.UseCount), 0 ) ;
	Trace.TWriteLn ;
   END ;
   Trace>*)

   INC(DPtr^.Data.UseCount);
   RETURN ADR(DPtr^.HRecord.TextData[VA.Offset])
END VMAccess;

PROCEDURE VMModify(VA: VirtAddr): ADDRESS;
VAR T2Ptr:     VirtLocDataPntr;
    LocOffset: CARDINAL;
    TPtr:      RealStoragePntr;
    DPtr:      RealStoragePntr;
    HPtr:      HRecordPntr;
    TheFile:   VirtMemFile;
BEGIN
   T2Ptr := FindVirtPage(VA.PageNo, TheFile, LocOffset, TPtr);
   DPtr := LoadVirtPage(TheFile, T2Ptr, TPtr, LocOffset, VA.PageNo);

   (*<Trace
   IF Trace.DoTrace THEN
	Trace.TWriteString( "M " ) ;
	PrintAddr( VA ) ;
	Trace.TWriteString( " " ) ;
	Trace.TWriteAddr( DPtr ) ;
	Trace.TWriteString( " " ) ;
	Trace.TWriteCard( VAL(CARDINAL,DPtr^.Data.UseCount), 0 ) ;
	Trace.TWriteLn ;
   END ;
   Trace>*)

   INC(DPtr^.Data.UseCount);
   DPtr^.Data.Changed := TRUE;
   RETURN ADR(DPtr^.HRecord.TextData[VA.Offset])
END VMModify;

PROCEDURE VMMarkChanged(VA: VirtAddr);
VAR T2Ptr:     VirtLocDataPntr;
    LocOffset: CARDINAL;
    TPtr:      RealStoragePntr;
    DPtr:      RealStoragePntr;
    HPtr:      HRecordPntr;
    TheFile:   VirtMemFile;
BEGIN
   T2Ptr := FindVirtPage(VA.PageNo, TheFile, LocOffset, TPtr);
   DPtr := LoadVirtPage(TheFile, T2Ptr, TPtr, LocOffset, VA.PageNo);
   DPtr^.Data.Changed := TRUE;
END VMMarkChanged;

PROCEDURE VMRelease(VA: VirtAddr);
VAR T2Ptr:     VirtLocDataPntr;
    LocOffset: CARDINAL;
    TPtr:      RealStoragePntr;
    DPtr:      RealStoragePntr;
    HPtr:      HRecordPntr;
    TheFile:   VirtMemFile;
BEGIN
   T2Ptr := FindVirtPage(VA.PageNo, TheFile, LocOffset, TPtr);
   (* for optimization: since page must be in real memory.
   DPtr := LoadVirtPage(TheFile, T2Ptr, TPtr, LocOffset, VA.PageNo);
   *)
   DPtr := SegmentToReal(T2Ptr^.Where[LocOffset].Loc.Position);

   (*<Trace
   IF Trace.DoTrace THEN
   Trace.TWriteString( "R " ) ;
	PrintAddr( VA ) ;
	Trace.TWriteString( " " ) ;
	Trace.TWriteAddr( DPtr ) ;
	Trace.TWriteString( " " ) ;
	Trace.TWriteCard( VAL(CARDINAL,DPtr^.Data.UseCount), 0 ) ;
	Trace.TWriteLn ;
   END ;
   Trace>*)

   DEC(TPtr^.Data.UseCount);	(* to compensate for LoadVirtPage  *LP2* *)
   DEC(DPtr^.Data.UseCount);
END VMRelease;

PROCEDURE GetSpace(Size:  CARDINAL;
                   Pool:  CARDINAL;
               VAR VA:    VirtAddr): ADDRESS;

VAR
    ipg:       CARDINAL;
    rslt:      ADDRESS;
    TheFile:   VirtMemFile;
    CurPage:   CARDINAL;
    BasePage:  CARDINAL;

PROCEDURE GtWrds(n:         CARDINAL;
                 HP:        RealStoragePntr;
             VAR ifree:     CARDINAL;
             VAR SpaceFree: CARDINAL (* in bytes *)): CARDINAL;
VAR
    M: CARDINAL;
    IPrev: CARDINAL;
    ICur: CARDINAL;
    INxt: CARDINAL;
    NotFound: BOOLEAN;
BEGIN (* GtWrds *)
  (*  M := ((n+1) DIV 2) ;  (* M  is space needed in 2-byte words *) *)
  M := ((n+1) DIV 2) + 1 ;  (* M  is space needed in 2-byte words *)
  IPrev := 0;
  ICur := ifree;
  NotFound := TRUE;
  WITH HP^.HRecord DO
    WHILE (ICur <> 0) AND NotFound DO
      IF M <= PDBCardinal[ICur] THEN
        IF M+1 < PDBCardinal[ICur] THEN
          INxt := ICur+M;
          PDBCardinal[INxt] := PDBCardinal[ICur]-M;
          PDBCardinal[INxt+1] := PDBCardinal[ICur+1];
        ELSE
          INxt := PDBCardinal[ICur+1];
        END;
        IF IPrev <> 0 THEN PDBCardinal[IPrev+1] := INxt;
        ELSE ifree := INxt END;
        PDBCardinal[ICur + M - 1 ] := EndOfSpaceMarker ;  (* *LP* *)
        NotFound := FALSE;
	DEC(SpaceFree,M * 2);
      ELSE
        IPrev := ICur;
        ICur := PDBCardinal[ICur+1];
      END;
    END;
  END;
  RETURN ICur
END GtWrds;

PROCEDURE TryPage(PageNo: CARDINAL): ADDRESS;
VAR RsltIdx:   CARDINAL;
    T2Ptr:     VirtLocDataPntr;
    LocOffset: CARDINAL;
    TPtr:      RealStoragePntr;
    DPtr:      RealStoragePntr;
    HPtr:      HRecordPntr;
    TempCurPage: CurrentPageRec ;
BEGIN
   T2Ptr := FindVirtPage(PageNo, TheFile, LocOffset, TPtr);

   IF T2Ptr^.Where[LocOffset].Loc.Location = UndefinedLocation THEN
      T2Ptr^.Where[LocOffset].PoolNo := Pool;
      T2Ptr^.Where[LocOffset].SpaceFree := HNoPDBWords * 2;
   ELSIF T2Ptr^.Where[LocOffset].PoolNo = MAX(CARDINAL) THEN
	 T2Ptr^.Where[LocOffset].SpaceFree := HNoPDBWords * 2;
   ELSE
      IF (T2Ptr^.Where[LocOffset].PoolNo <> Pool) OR
	 (T2Ptr^.Where[LocOffset].SpaceFree < Size) THEN
	 DEC(TPtr^.Data.UseCount); (* release count because of FromVirtPage *)
	 RETURN NIL
      END
   END;

   INC(TPtr^.Data.UseCount); (* to ensure it remains in memory *)
   DPtr := LoadVirtPage(TheFile, T2Ptr, TPtr, LocOffset, PageNo);
   IF T2Ptr^.Where[LocOffset].PoolNo = MAX(CARDINAL) THEN
      T2Ptr^.Where[LocOffset].PoolNo := Pool;
      WITH DPtr^.HRecord DO
         FirstFree := 1;
         PDBCardinal[1] := HNoPDBWords;
         PDBCardinal[2] := 0;
      END;
   END;

   RsltIdx := GtWrds(Size, DPtr, DPtr^.HRecord.FirstFree,
                     T2Ptr^.Where[LocOffset].SpaceFree);
   DEC(TPtr^.Data.UseCount); (* we're really done with TPtr and T2Ptr now *)
   IF RsltIdx > 0 THEN
      DPtr^.Data.Changed := TRUE;
      INC(DPtr^.Data.UseCount);
      VA.PageNo := PageNo; VA.Offset := RsltIdx * 2 ;  (* **LP** *)
      WITH TheFile^ DO
	 (* move current page to the front of the list *)
	 IF CurPage = 0 THEN
	    CurrentPages[0].Page := PageNo ;  (* reflect current page (may have filled up!) *)
	 ELSIF CurPage > MaxCurPages THEN
	    (* only the top MaxCurPages will be kept around *)
	    Lib.Move( ADR(CurrentPages[0]), ADR(CurrentPages[1]), (MaxCurPages-1)*SIZE(CurrentPageRec) );
	    CurrentPages[0].Pool := Pool ;
	    CurrentPages[0].Page := PageNo ;
	 ELSE
	    TempCurPage := CurrentPages[CurPage] ;
	    Lib.Move( ADR(CurrentPages[0]), ADR(CurrentPages[1]), CurPage*SIZE(CurrentPageRec) );
	    CurrentPages[0] := TempCurPage ;	
	 END ;
      END ;
(*      RETURN ADR(DPtr^.HRecord.PDBCardinal[RsltIdx]);  same thing, more clear!? *)
      RETURN ADR(DPtr^.HRecord.TextData[VA.Offset]);
   END;
   RETURN NIL
END TryPage;

BEGIN
   IF Pool = MAX(CARDINAL) THEN
      ProgramErrorAndHalt('GetSpace: Invalid pool no.');
   END ;
   IF Pool < FirstTempPool THEN
     TheFile := PDBFile;
     BasePage := 0;
   ELSE
     TheFile := TempFile;
     BasePage := FirstTempPage;
   END;
   ShowBusy ;

   WITH TheFile^ DO
      (*  First, try to find space on "current" page *)
      CurPage := 0 ;
      WHILE (CurPage <= MaxCurPages) AND (CurrentPages[CurPage].Pool <> Pool) DO
	 INC( CurPage )
      END ;
      IF (CurPage <= MaxCurPages) AND (CurrentPages[CurPage].Page <> MAX(CARDINAL)) THEN
         rslt := TryPage( CurrentPages[CurPage].Page );
         IF rslt <> NIL THEN RETURN rslt END;
      END;

(*  Now, try to find space on other pages;  note that the range given
    to the FOR is intentionally one greater than the number of pages
    currently created! (if all pages are full this will cause creation
    of a new page  j.b. *)

      FOR ipg := BasePage TO BasePage + WorkSpaceSize DO
         rslt := TryPage(ipg);
         IF rslt <> NIL THEN RETURN rslt END;
      END;
   END;
   ProgramErrorAndHalt('GetSpace -- should never get here!');
END GetSpace;

PROCEDURE FreeSpace(VA:   VirtAddr;
                    Size: CARDINAL);

VAR
    TheFile:   VirtMemFile;

PROCEDURE FrWrds(ilocx:     CARDINAL;
                 HP:        RealStoragePntr;
                 n:         CARDINAL;
             VAR ifree:     CARDINAL;
             VAR SpaceFree: CARDINAL);

VAR
    iloc, m: CARDINAL;
    icur, inxt: CARDINAL;
    SpaceMarkerIndex : CARDINAL ;
BEGIN
  WITH HP^.HRecord DO
    iloc := ilocx DIV 2 ;
    (* m := ((n+1) DIV 2); (* m is space to free in 2-byte words *) *)
    m := ((n+1) DIV 2) + 1 ; (* m is space to free in 2-byte words *)
    SpaceMarkerIndex := iloc + m - 1 ;
    IF PDBCardinal[ SpaceMarkerIndex ] = FreedSpaceMarker THEN  (* *LP* *)
	ProgramErrorAndHalt( "FreeSpace: freed memory twice.") ;
    END ;
    IF PDBCardinal[ SpaceMarkerIndex ] = EndOfSpaceMarker THEN  (* *LP* *)
        PDBCardinal[ SpaceMarkerIndex ] := FreedSpaceMarker
    ELSE
	ProgramErrorAndHalt( "FreeSpace: corrupted memory.") ;
    END ;
    IF (iloc < ifree) OR (ifree = 0) THEN
(*    IF iloc+m+1 >= ifree THEN    ... old line j.b. *)
      IF (ifree <> 0) AND (iloc+m+1 >= ifree) THEN  (* jb 3/29/91 *)
        PDBCardinal[iloc] := ifree-iloc+PDBCardinal[ifree];
        PDBCardinal[iloc+1] := PDBCardinal[ifree+1];
      ELSE
        PDBCardinal[iloc] := m;
        PDBCardinal[iloc+1] := ifree;
      END;
      ifree := iloc;
    ELSE
      icur := ifree;
      WHILE (icur <> 0) DO
        inxt := PDBCardinal[icur+1];
        IF (inxt > iloc) OR (inxt = 0) THEN
          IF icur+PDBCardinal[icur]+1 >= iloc THEN
            PDBCardinal[icur] := iloc-icur+m;
            iloc := icur;
          ELSE
            PDBCardinal[iloc] := m;
            PDBCardinal[iloc+1] := PDBCardinal[icur+1];
            PDBCardinal[icur+1] := iloc;
          END;
          IF (inxt <> 0) AND (PDBCardinal[iloc]+iloc+1 >= inxt) THEN
            PDBCardinal[iloc] := inxt-iloc+PDBCardinal[inxt];
            PDBCardinal[iloc+1] := PDBCardinal[inxt+1];
          END;
          INC(SpaceFree,m * 2);
          RETURN
        ELSE
          icur := inxt
        END;
      END;
      (* execution at this point indicates a program error*)
      ProgramErrorAndHalt('In FrWrds, should not get here!!');
    END;
  END;
  INC(SpaceFree,m * 2);
END FrWrds;

VAR RsltIdx:   CARDINAL;
    T2Ptr:     VirtLocDataPntr;
    LocOffset: CARDINAL;
    TPtr:      RealStoragePntr;
    DPtr:      RealStoragePntr;
    HPtr:      HRecordPntr;

BEGIN
   T2Ptr := FindVirtPage(VA.PageNo, TheFile, LocOffset, TPtr);
   INC(TPtr^.Data.UseCount); (* to ensure it remains in memory *)
   IF T2Ptr^.Where[LocOffset].PoolNo = MAX(CARDINAL) THEN
      ProgramErrorAndHalt('FreeSpace: Invalid pool no.');
   END ;
   DPtr := LoadVirtPage(TheFile, T2Ptr, TPtr, LocOffset, VA.PageNo);
   ShowBusy ;
   FrWrds(VA.Offset, DPtr, Size, DPtr^.HRecord.FirstFree,
                     T2Ptr^.Where[LocOffset].SpaceFree);
   DPtr^.Data.Changed := TRUE;
   DEC(TPtr^.Data.UseCount); (* we're really done with TPtr and T2Ptr now *)
END FreeSpace;

PROCEDURE RealToPool(Adr: ADDRESS): CARDINAL;
VAR
   Addr:      AddrType;
   Ptr:       RealStoragePntr;
   TheFile:   VirtMemFile;
   LocOffset: CARDINAL;
   TPtr:      RealStoragePntr;
   T2Ptr:     VirtLocDataPntr;
BEGIN
   Addr := AddrType(Adr);
   Ptr := [Addr.SEGMENT : 0]; (* this must be verified by experience!! j.b. *)
   T2Ptr := FindVirtPage(Ptr^.Data.RecordID, TheFile, LocOffset, TPtr);
   DEC(TPtr^.Data.UseCount);
   IF T2Ptr^.Where[LocOffset].PoolNo = MAX(CARDINAL) THEN
      ProgramErrorAndHalt('ReadToPool: Invalid pool no.');
   END ;
   RETURN T2Ptr^.Where[LocOffset].PoolNo
END RealToPool;

PROCEDURE VirtToPool(Adr: VirtAddr): CARDINAL;
VAR
   TheFile:   VirtMemFile;
   LocOffset: CARDINAL;
   TPtr:      RealStoragePntr;
   T2Ptr:     VirtLocDataPntr;
BEGIN
   T2Ptr := FindVirtPage(Adr.PageNo, TheFile, LocOffset, TPtr);
   DEC(TPtr^.Data.UseCount);
   IF T2Ptr^.Where[LocOffset].PoolNo = MAX(CARDINAL) THEN
      ProgramErrorAndHalt('VirtToPool: Invalid pool no.');
   END ;
   RETURN T2Ptr^.Where[LocOffset].PoolNo
END VirtToPool;

PROCEDURE VMDefined(VA: VirtAddr): BOOLEAN;
VAR
   TheFile:   VirtMemFile;
   LocOffset: CARDINAL;
   TPtr:      RealStoragePntr;
   T2Ptr:     VirtLocDataPntr;
BEGIN
   T2Ptr := FindVirtPage(VA.PageNo, TheFile, LocOffset, TPtr);
   DEC(TPtr^.Data.UseCount);
   RETURN T2Ptr^.Where[LocOffset].PoolNo <> MAX(CARDINAL);
END VMDefined;

PROCEDURE EqualVirts(First,Second: VirtAddr): BOOLEAN;
BEGIN
   RETURN (First.PageNo = Second.PageNo) AND (First.Offset = Second.Offset)
END EqualVirts;

PROCEDURE ChangePoolNo(Old, New: CARDINAL);
VAR
   TheFile:   VirtMemFile;
   BasePage:  CARDINAL;
   ipg:       CARDINAL;
   LocOffset: CARDINAL;
   TPtr:      RealStoragePntr;
   T2Ptr:     VirtLocDataPntr;
BEGIN
   IF Old = MAX(CARDINAL) THEN
      ProgramErrorAndHalt('ChangePoolNo: Invalid pool no.');
   END ;
   IF Old < FirstTempPool THEN
      TheFile := PDBFile;
      BasePage := 0;
   ELSE
      TheFile := TempFile;
      BasePage := FirstTempPage
   END;

   IF TheFile^.WorkSpaceSize = 0 THEN	(* protect against arithmatic overflow *)
      ProgramErrorAndHalt('ChangePoolNo: Invalid WorkSpaceSize.');
   END ;

   FOR ipg := BasePage TO BasePage + TheFile^.WorkSpaceSize-1 DO
      T2Ptr := FindVirtPage(ipg, TheFile, LocOffset, TPtr);
      IF T2Ptr^.Where[LocOffset].PoolNo = Old THEN
         T2Ptr^.Where[LocOffset].PoolNo := New;
      END;
(*      IF New = MAX(CARDINAL) THEN DEC(TPtr^.Data.UseCount) END;  *LP2* *)
      DEC(TPtr^.Data.UseCount) ;	(* *LP2* *)
   END;
END ChangePoolNo;

PROCEDURE FreePool(No: CARDINAL);
BEGIN
   IF No = MAX(CARDINAL) THEN
      ProgramErrorAndHalt('FreePool: Invalid pool no.');
   END ;
   ChangePoolNo(No, MAX(CARDINAL));
END FreePool;

PROCEDURE WriteAllVirts();
VAR
   TheFile:   VirtMemFile;
   BasePage:  CARDINAL;
   ipg:       CARDINAL;
   LocOffset: CARDINAL;
   TPtr:      RealStoragePntr;
   T2Ptr:     VirtLocDataPntr;
   DPtr:      RealStoragePntr;
   hrp:       HRecordPntr;
   tld:       VirtLocData;

PROCEDURE WriteOutIndexPages;
VAR ipg:   CARDINAL;
    idata: VirtLocData;

PROCEDURE IndicateOnDisk;
VAR i:  CARDINAL;
BEGIN
   FOR i := 0 TO NoLocsPerHyper-1 DO
      IF idata.Where[i].Loc.Location = UndefinedLocation THEN RETURN END;
      idata.Where[i].Loc.Location := OnDisk;
   END;
END IndicateOnDisk;

BEGIN
   Lib.WordFill(ADR(tld),HyperLength DIV 2, MAX(CARDINAL));

   WITH TheFile^ DO
      FOR ipg := 0 TO MaxVirtIndexSize - 1 DO
          CASE VirtLocs[ipg].Loc.Location OF
              UndefinedLocation:
                RETURN  (* all active ones are done *)
            | OnDisk:
                SeekVirtFile(TheFile,VirtLocs[ipg].DiskPos);
                ReadFromVirtFile(TheFile, idata.HRecord);
                IndicateOnDisk;
                WriteHRecToDisk(TheFile,VirtLocs[ipg].DiskPos,idata.HRecord);
            | InReal:
                DPtr := SegmentToReal(VirtLocs[ipg].Loc.Position);
                IF DPtr^.Data.Changed THEN
                   idata.HRecord := DPtr^.HRecord;
                   IndicateOnDisk;
                   WriteHRecToDisk(TheFile,VirtLocs[ipg].DiskPos,idata.HRecord);
                   DPtr^.Data.Changed := FALSE
                END;
            | InEMS:
                IF EMSInfo^.EMSPageInfo[VirtLocs[ipg].Loc.Position].Changed THEN
                   hrp := LocateEMSPage(VirtLocs[ipg].Loc.Position);
                   idata.HRecord := hrp^;
                   IndicateOnDisk;
                   WriteHRecToDisk(TheFile,VirtLocs[ipg].DiskPos,idata.HRecord);
                   EMSInfo^.EMSPageInfo[VirtLocs[ipg].Loc.Position].Changed := FALSE
                END;
          END;
          tld.DiskP[ipg] := VirtLocs[ipg].DiskPos;
      END;
   END;
END WriteOutIndexPages;

BEGIN
   IF PDBFile^.WorkSpaceSize = 0 THEN
      RETURN (* nothing to do here either *)
   END;

   FOR ipg := 0 TO PDBFile^.WorkSpaceSize-1 DO
      T2Ptr := FindVirtPage(ipg, TheFile, LocOffset, TPtr);
      WITH T2Ptr^ DO
         CASE Where[LocOffset].Loc.Location OF
           UndefinedLocation:
              ProgramErrorAndHalt('unexpected Location in WriteAll')
         | OnDisk: (* do nothing here *)
         | InReal:
              DPtr := SegmentToReal(Where[LocOffset].Loc.Position);
              IF DPtr^.Data.Changed THEN
                 WriteRealPageToDisk(TheFile, T2Ptr, LocOffset, DPtr^.HRecord);
                 DPtr^.Data.Changed := FALSE
              END;
         | InEMS:
              IF EMSInfo^.EMSPageInfo[Where[LocOffset].Loc.Position].Changed THEN
                 hrp := LocateEMSPage(Where[LocOffset].Loc.Position);
                 WriteRealPageToDisk(TheFile, T2Ptr, LocOffset, hrp^);
                 EMSInfo^.EMSPageInfo[Where[LocOffset].Loc.Position].Changed := FALSE ; (* *LP2* *)
              END;
         END;
      END;
      DEC(TPtr^.Data.UseCount);
   END;

   (* now, write out all index pages in memory *)

   WriteOutIndexPages;

   (* finally, write out index of indexes created in WriteOutIndexPages *)

   tld.PDBId := PDBIDModel;
   tld.WSSize := TheFile^.WorkSpaceSize;
   tld.PDBVersion := ThisPDBVersion;
   SeekVirtFile(TheFile,0);
   WriteToVirtFile(TheFile, tld.HRecord);

   (*<JPI1*)
   FIO.Close( TheFile^.FileID ) ;
   TheFile^.FileID := FIO.Open( TheFile^.FName ) ;
   (*JPI1>*)

   (*<JPI3     FIO.Flush( TheFile^.FileID ) ;  JPI3>*)
END WriteAllVirts;

PROCEDURE CloseVirtFile(VAR file: VirtMemFile);
VAR ipg:       CARDINAL;
    T2Ptr:     VirtLocDataPntr;
    LocOffset: CARDINAL;
    TPtr,DPtr: RealStoragePntr;
    HPtr:      HRecordPntr;
    tld:       VirtLocData;
    dummy:     VirtMemFile;

PROCEDURE CloseOutIndexPages;
VAR ipg:   CARDINAL;
BEGIN
   Lib.WordFill(ADR(tld),HyperLength DIV 2, MAX(CARDINAL));

   WITH file^ DO
      FOR ipg := 0 TO MaxVirtIndexSize - 1 DO
          CASE VirtLocs[ipg].Loc.Location OF
              UndefinedLocation:
                RETURN  (* all active ones are done *)
            | OnDisk: (* ignore -- nothing to do here *)
            | InReal:
                DPtr := SegmentToReal(VirtLocs[ipg].Loc.Position);
                RemoveFromRealIdxWork(DPtr, (* UseEMS = *) FALSE);
		MarkRealAsNotInUse(DPtr);
            | InEMS:
                RemoveFromEMSIdx(VirtLocs[ipg].Loc.Position);
          END;
          tld.DiskP[ipg] := VirtLocs[ipg].DiskPos;
      END;
   END;
END CloseOutIndexPages;

BEGIN
   IF file = NIL THEN  RETURN  END ;  (* needed for ClosePDBOnHalt -- opaque type! *)
   WITH file^ DO
      IF tempfile THEN
          ProgramErrorAndHalt('Unexpected CloseVirtFile on tempfile');
      END;

      IF (WorkSpaceSize > 0) THEN

         (* First, write out all changed pages in memory (Real, and EMS) *)

         FOR ipg := 0 TO WorkSpaceSize-1 DO
            T2Ptr := FindVirtPage(ipg, dummy, LocOffset, TPtr);
            CASE T2Ptr^.Where[LocOffset].Loc.Location OF
              UndefinedLocation:
                ProgramErrorAndHalt('Unexpected Where in CloseVirtFile');
            | OnDisk: (* ignore -- nothing to do here *)
            | InReal:
                DPtr := SegmentToReal(T2Ptr^.Where[LocOffset].Loc.Position);
                RemoveFromRealPageWork(DPtr, (* UseEMS = *) FALSE);
                MarkRealAsNotInUse(DPtr);
            | InEMS:
                RemoveFromEMSPage(T2Ptr^.Where[LocOffset].Loc.Position);
            END;
            DEC(TPtr^.Data.UseCount);
         END;

         (* now, write out all index pages in memory *)

         CloseOutIndexPages;

         (* finally, write out index of indexes created in WriteOutIndexPages *)

         tld.PDBId := PDBIDModel;
         tld.WSSize := WorkSpaceSize;
         tld.PDBVersion := ThisPDBVersion;
         SeekVirtFile(file,0);
         WriteToVirtFile(file, tld.HRecord);
      END;
      FIO.Close(FileID);
   END;
   DISPOSE(file);
   file := NIL;
END CloseVirtFile;

BEGIN
   TempFile := NIL;
   TempFileName := 'TACT.WRK';
   PDBFile := NIL;
(*   NILVirt.PageNo := MAX(CARDINAL);    *LP*
     NILVirt.Offset := MAX(CARDINAL);  *)
   NILVirt.PageNo := 0EEEEH ;
   NILVirt.Offset := 0EEEEH ;
(*<Check*)
   CurRecNo := 0;
(*Check>*)
END VirtMem.
