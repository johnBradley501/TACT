IMPLEMENTATION MODULE MemoryManagement;

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

(*V1=Production *)
(*V2=Debug  *)
(*V3=Assert *)
(*V4=Trace  *)

(*
This code relies on the fact that the current release of ALLOCATE in the JPI
library seems to:

(1) always return memory allocated that is aligned on a paragraph boundary.
(2) always returns address with OFFSET of zero.

This assumption is verified in this module -- to see code that
does this look up string "(* !!! *)" and study the code in that area.

My recollection is that the earlier release of JPI did >>not<< allocate
memory this way -- but I haven't verified this for sure.

                                    .... jb
*)

IMPORT Str, Lib, LIM, Storage, Utils, SYSTEM ;
(* FROM SYSTEM IMPORT ADDRESS, HeapBase ; *)
FROM HyperDataModel IMPORT  HyperData;
FROM ResMessages IMPORT
   (*proc*)  MsgString, PutResWarning;
FROM ErrorBase IMPORT ProgramErrorAndHalt ;
FROM TWB IMPORT
  (* Types *) WinType,
  (* Procs *) Used, Use, DirectWrite ;
FROM ResActionBar IMPORT ABWindow;

(*<Trace*)
FROM Trace IMPORT
  (* Vars  *) DoTrace,
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard, TWriteAddr;
(*Trace>*)

CONST
   MinNumberEMSPages = 3;	(* 2 for EMSInfo and at least 1 for data *)
   Amounttoleavefree = 64 * 1024 DIV ParagraphSize;	(* 4 K *)
   MinMemInBytes = 16 * MinMemAvail;
   ThreshHold = 100 ;
   FirstLPgFree = 2 ;  (* logical pages 0 and 1 are used for EMSInfo *)

TYPE
   AddrType = RECORD
      OFFSET:     CARDINAL;
      SEGMENT:    CARDINAL;
   END;

VAR
   AllocCallNo: 	CARDINAL;
   RealPageList:        CARDINAL;
   EMSInfoHandle:       CARDINAL;
   EMSDataHandle:       CARDINAL;
   CurEMSLPage:         CARDINAL;
   CurPPage:		CARDINAL;  (* Physical page frame in use *)
   EMSPPageNo:          ARRAY[FirstLPgFree..3] OF CARDINAL;
   EMSPPageLocked:	ARRAY[FirstLPgFree..3] OF BOOLEAN; (* Physical page frame avail for use *)
   NoOfCalls :          CARDINAL ;
   Indicator :          BOOLEAN ;
   ActBarWin :          WinType ;
(*<Debug
   LookForAddr : SYSTEM.ADDRESS ;
Debug>*)

PROCEDURE FinishEMS;
BEGIN
   LIM.DeAllocatePages(EMSInfoHandle);
   LIM.DeAllocatePages(EMSDataHandle);
END FinishEMS;

PROCEDURE SetupMemoryManagement;

CONST
   (*RES OLD MSG 350
   EMS Memory is not available on your computer and will not be
   used during this UseBase session.
   *)
   NoEMSOnMachineRes = (*RES REM INS*) 350;

VAR
   Rslt:          ARRAY[0..10] OF CHAR;
   OK:            BOOLEAN;
   dummy, FreePages: CARDINAL;
BEGIN
   RealPageList := 0;
   EMSAvailable := FALSE;

   IF LIM.LIMPresent THEN  EMSAvailable := LIM.GetStatus() = 0;  END;
   Utils.GetEnv('TACTEMS',Rslt);
   IF Rslt[0] = 0C THEN
      IF NOT EMSAvailable THEN RETURN END;
      NoEMSPagesAvailable := LIM.FreePages();
   ELSE
      NoEMSPagesAvailable := VAL(CARDINAL,Str.StrToCard(Rslt, 10,OK)) DIV 16;
      IF NOT OK THEN
         (*RES OLD MSG 141	(* <--- fix when have new TACT.RES *LP* *)
         Current value %0 for Environment Variable TACTEMS should be a number
         (size in K) and will be ignored.
         *)
         MsgString(Rslt, 0);
         PutResWarning( (*RES REM INS*) 141 );
         NoEMSPagesAvailable := 0;
      END;
      IF (NOT EMSAvailable) AND (NoEMSPagesAvailable <> 0) THEN
         MsgString(Rslt, 0);
         PutResWarning( NoEMSOnMachineRes );
         RETURN
      ELSIF (NOT EMSAvailable) THEN RETURN
      END;
      FreePages := LIM.FreePages();
      IF FreePages = 0 THEN
         (*RES OLD MSG 393
         EMS Memory is not available on your computer and will not be used
         during this UseBase session.
         *)
         MsgString(Rslt, 0);
         PutResWarning( (*RES REM INS*) 393 );
	 EMSAvailable := FALSE;
         RETURN
      END ;
      IF FreePages < NoEMSPagesAvailable THEN  NoEMSPagesAvailable := FreePages  END ;
   END;
   EMSAvailable := NoEMSPagesAvailable >= MinNumberEMSPages;
   IF NOT EMSAvailable THEN RETURN END;

   (* Note: physical page frames 0 and 1 are always available -- must never *)
   (*	    page them out with LIM.MapPage !!				    *)
   EMSInfoHandle := LIM.AllocatePages(2);
   EMSInfo := [LIM.GetPageFrame() : LIM.MapPage(0, 0, EMSInfoHandle)];
   dummy := LIM.MapPage(1, 1, EMSInfoHandle) ;
   EMSInfo^.NoEMSInUse := 0;

   DEC(NoEMSPagesAvailable,2);
   IF NoEMSPagesAvailable > MaxNoEMSPages THEN NoEMSPagesAvailable := MaxNoEMSPages END;
   EMSInfo^.NoEMSAvail := NoEMSPagesAvailable * 16 ;  (* keep track of 1K chunks *)
   IF EMSInfo^.NoEMSAvail >= MaxNoEMSPages THEN
	EMSInfo^.NoEMSAvail := MaxNoEMSPages - 1 ;  (* allow to limit of EMSInfo  array *)
   END ;
   EMSInfo^.EMSPageList := MAX(CARDINAL);

   EMSDataHandle := LIM.AllocatePages(NoEMSPagesAvailable);

   Utils.InstallTermProc(FinishEMS);
   Utils.ALLOCATE := ALLOCATE;
   Utils.DEALLOCATE := DEALLOCATE;
END SetupMemoryManagement;

(*<Assert
  VAR
     PgmStartAddr,
     PgmEndAddr		: LONGCARD ;

PROCEDURE CheckManAddr( ManData : CARDINAL ) ;
   VAR
	NormalizedAddr	: LONGCARD ;
	b		: HyperPageManagementPntr ;
	a		: SYSTEM.ADDRESS ;
   BEGIN
	b := [ManData:0] ;
	a := SYSTEM.ADDRESS( b^ ) ;
	NormalizedAddr := LONGCARD(SYSTEM.Seg(a^))*16 + LONGCARD(SYSTEM.Ofs(a^)) ;
	IF (NormalizedAddr > PgmEndAddr) OR (NormalizedAddr < PgmStartAddr) THEN
	   (* this address is outside the program code in memory *)
	   ProgramErrorAndHalt( "MemoryMan: invalid ManagementData addr." );
	END ;
   END CheckManAddr ;
Assert>*)

(* Note: use of VAR is to pass by Ref and not by value, Data not modified in next proc *)
PROCEDURE GetManagementDataPtr( VAR Data : KiloInfo ) : HyperPageManagementPntr;
   BEGIN
	IF Data.ManagementData = 0 THEN RETURN NIL
	ELSE
	   (*<Assert  CheckManAddr( Data.ManagementData ) ;  Assert>*)
	   RETURN [Data.ManagementData : 0 ]
	END;
   END GetManagementDataPtr;

PROCEDURE SetManagementDataPtr( VAR Data : KiloInfo; MDPtr : HyperPageManagementPntr) ;
   VAR	temp	: AddrType;
   BEGIN
	IF MDPtr = NIL THEN
	   Data.ManagementData := 0 ;
	ELSE
	   temp := AddrType( MDPtr );
	   Data.ManagementData := temp.SEGMENT;
	   (*<Assert  CheckManAddr( Data.ManagementData ) ;  Assert>*)
	END ;
   END SetManagementDataPtr;

PROCEDURE CopyKiloInfo(In: KiloInfo; VAR Out: KiloInfo);
VAR n,p:  CARDINAL;
BEGIN
   n := Out.Next;
   p := Out.Prev;
   Out := In;
   Out.Next := n;
   Out.Prev := p;
END CopyKiloInfo;

(*<Assert
PROCEDURE CheckDataAddr( ptr : SYSTEM.ADDRESS ) ;		(* *LP* *)
   VAR
	AP	: CARDINAL;
	temp	: AddrType;
   BEGIN
	temp := AddrType(ptr);
	AP := temp.SEGMENT;
	IF (AP < SYSTEM.HeapBase) OR (AP > 0A000H (* 640K!! *) ) THEN	(* this pointer refers to code area ?? *)
	   ProgramErrorAndHalt( "MemoryMan: Bad data memory addr." );
	END ;
   END CheckDataAddr ;
Assert>*)

PROCEDURE RealInsertInRing(P:    RealStoragePntr);
VAR b,f:  RealStoragePntr;
    fprev: CARDINAL;
    AP:    CARDINAL;
    temp:  AddrType;
BEGIN
   temp := AddrType(P);
   AP := temp.SEGMENT;
   (*<Assert  CheckDataAddr( P ) ;   Assert>*)
   IF RealPageList = 0 THEN
      P^.Data.Next := AP;
      P^.Data.Prev := AP;
   ELSE
      f := [RealPageList:0];
      fprev := f^.Data.Prev;
      b := [fprev:0];
      (*<Assert  CheckDataAddr( f ) ;   Assert>*)
      (*<Assert  CheckDataAddr( b ) ;   Assert>*)
      P^.Data.Next := RealPageList;
      f^.Data.Prev := AP;
      P^.Data.Prev := fprev;
      b^.Data.Next := AP
   END;
   RealPageList := AP;
END RealInsertInRing;

PROCEDURE RealRemoveFromRing(P:   RealStoragePntr);
VAR b,f:  RealStoragePntr;
BEGIN
   (*<Assert   CheckDataAddr( P ) ;  Assert>*)
   b := [P^.Data.Prev: 0];
   f := [P^.Data.Next: 0];
   (*<Assert   CheckDataAddr( f ) ;    Assert>*)
   (*<Assert   CheckDataAddr( b ) ;    Assert>*)
   b^.Data.Next := P^.Data.Next;
   f^.Data.Prev := P^.Data.Prev;
END RealRemoveFromRing;

PROCEDURE FindRealPageToRelease(VAR CS:     CARDINAL;
                                VAR C:      RealStoragePntr): BOOLEAN;
VAR ManagementDataPtr : HyperPageManagementPntr;
BEGIN
   C := NIL;
   CS := RealPageList;
   IF CS = 0 THEN RETURN FALSE END;

   C := [CS : 0];
   REPEAT
      (*<Assert   CheckDataAddr( C ) ;    Assert>*)
      CS := C^.Data.Prev;
      C := [CS : 0];
   UNTIL (CS = RealPageList) OR (C^.Data.UseCount = 0);

   IF C^.Data.UseCount <> 0 THEN RETURN FALSE END;
   IF C^.Data.ManagementData <> 0 THEN
      ManagementDataPtr := GetManagementDataPtr( C^.Data ) ;
      ManagementDataPtr^.RemoveFromReal(C);
      SetManagementDataPtr( C^.Data, NIL ) ;
   END;

   IF CS = RealPageList THEN RealPageList := C^.Data.Next END;
   IF CS (*still*) = RealPageList THEN RealPageList := 0
   ELSE RealRemoveFromRing(C) END;
   RETURN TRUE
END FindRealPageToRelease;

PROCEDURE SegmentToReal(Segment: CARDINAL): RealStoragePntr;
VAR p:  RealStoragePntr;
BEGIN
   p := [Segment : 0];
   (*<Assert   CheckDataAddr( p ) ;    Assert>*)
   RETURN p;
END SegmentToReal;

PROCEDURE RealReference(Segment: CARDINAL): RealStoragePntr;
VAR
   p, f, b : RealStoragePntr;
   fprev   : CARDINAL ;
BEGIN
   p := [Segment : 0];
   IF Segment <> RealPageList THEN
      (* combine RealRemoveFromRing and RealInsertInRing for performance reasons *)
      IF RealPageList = 0 THEN
	 p^.Data.Next := Segment ;
	 p^.Data.Prev := Segment ;
      ELSE
	 (* RealRemoveFromRing(p); *)
	 b := [p^.Data.Prev: 0];
	 f := [p^.Data.Next: 0];
	 (*<Assert   CheckDataAddr( f ) ;    Assert>*)
	 (*<Assert   CheckDataAddr( b ) ;    Assert>*)
	 b^.Data.Next := p^.Data.Next;
	 f^.Data.Prev := p^.Data.Prev;
	
	 (* RealInsertInRing(p); *)
	 f := [RealPageList:0];
	 (*<Assert  CheckDataAddr( f ) ;   Assert>*)
	 fprev := f^.Data.Prev;
	 f^.Data.Prev := Segment;
	 p^.Data.Next := RealPageList;
	 p^.Data.Prev := fprev;
	 b := [fprev:0];
	 (*<Assert  CheckDataAddr( b ) ;   Assert>*)
	 b^.Data.Next := Segment;
      END ;
      RealPageList := Segment ;
   END;
   RETURN p;
END RealReference;

PROCEDURE GetRealHyperPage(VAR Ptr: RealStoragePntr): CARDINAL; (* segment address *)
VAR
   AddrParts: AddrType;
   segno:     CARDINAL;
BEGIN
   IF (Storage.HeapTotalAvail(Storage.MainHeap) > Amounttoleavefree)
	OR (RealPageList = 0) THEN (* !!! *)
      Storage.ALLOCATE(Ptr,SIZE(RealStorageRecord));
      AddrParts := AddrType(Ptr);
      IF AddrParts.OFFSET <> 0 THEN
         ProgramErrorAndHalt('Nonzero OFFSET in GetNewHyperPage')
      END;
   ELSE
      IF NOT FindRealPageToRelease(segno,Ptr) THEN
         ProgramErrorAndHalt('Unable to find a "real" memory page to free in GetRealHyperPage');
      END;
   END;

   WITH Ptr^.Data DO
      RecordID := 0;
      Changed := FALSE;
      UseCount := 0;
   END;
   SetManagementDataPtr( Ptr^.Data, NIL ) ;
   AddrParts := AddrType(Ptr);
   RealInsertInRing(Ptr);
   RETURN AddrParts.SEGMENT;
END GetRealHyperPage;

(*<Assert
PROCEDURE CheckEMSRing ;
    VAR
	Count, b, f : CARDINAL;
    BEGIN
	WITH EMSInfo^ DO
	   IF EMSPageList = MAX(CARDINAL) THEN  RETURN  END ;
	   Count := 1 ;
	   b := EMSPageInfo[EMSPageList].Prev ;
	   WHILE b <> EMSPageList DO
		IF b = MAX(CARDINAL) THEN ProgramErrorAndHalt('(1a) EMS Ring corrupted.') END ;
		b := EMSPageInfo[b].Prev ;
		INC( Count ) ;
	   END ;
	   IF Count <> NoEMSInUse-1 (* incremented count before insert *) THEN
		ProgramErrorAndHalt('(1b) EMS Ring corrupted.');
	   END ;
	   Count := 1 ;
	   f := EMSPageInfo[EMSPageList].Next ;
	   WHILE f <> EMSPageList DO
		IF f = MAX(CARDINAL) THEN ProgramErrorAndHalt('(2a) EMS Ring corrupted.') END ;
		f := EMSPageInfo[f].Next ;
		INC( Count ) ;
	   END ;
	   IF Count <> NoEMSInUse-1 THEN
		ProgramErrorAndHalt('(2b) EMS Ring corrupted.');
	   END ;
	END ;
    END CheckEMSRing ;
  Assert>*)

PROCEDURE EMSInsertInRing(P:    CARDINAL);
VAR b,f:  CARDINAL;
BEGIN
   (*<Assert    CheckEMSRing ;   Assert>*)
   WITH EMSInfo^ DO
      IF EMSPageList = MAX(CARDINAL) THEN
         EMSPageInfo[P].Prev := P;
         EMSPageInfo[P].Next := P;
      ELSE
         f := EMSPageList;
         b := EMSPageInfo[f].Prev;
         EMSPageInfo[P].Next := f;
         EMSPageInfo[f].Prev := P;
         EMSPageInfo[P].Prev := b;
         EMSPageInfo[b].Next := P
      END;
      EMSPageList := P;
   END;
END EMSInsertInRing;

PROCEDURE EMSRemoveFromRing(P:   CARDINAL);
VAR b,f:  CARDINAL;
BEGIN
   WITH EMSInfo^ DO
      b := EMSPageInfo[P].Prev;
      f := EMSPageInfo[P].Next;
      EMSPageInfo[b].Next := f;
      EMSPageInfo[f].Prev := b;
   END;
   (*<Assert    CheckEMSRing ;   Assert>*)
END EMSRemoveFromRing;

PROCEDURE GetNewEMSPage(): CARDINAL; (* EMS Page Number *)
VAR
   EMSPage:   CARDINAL;

PROCEDURE FreeUpEMSPage(VAR C:    CARDINAL);
VAR ManagementDataPtr : HyperPageManagementPntr;
BEGIN
   WITH EMSInfo^ DO
      C := EMSPageList;
      IF C <> MAX(CARDINAL) THEN
         REPEAT
            C := EMSPageInfo[C].Prev;
         UNTIL (C = EMSPageList) OR (EMSPageInfo[C].UseCount = 0);

         IF (EMSPageInfo[C].UseCount = 0) THEN
            IF EMSPageInfo[C].ManagementData <> 0 THEN
	       ManagementDataPtr := GetManagementDataPtr( EMSPageInfo[C] ) ;
               ManagementDataPtr^.RemoveFromEMS(C);
               SetManagementDataPtr(EMSPageInfo[C], NIL );
            END;
            IF C = EMSPageList THEN EMSPageList := EMSPageInfo[C].Next END;
            IF C (*still*) = EMSPageList THEN EMSPageList := MAX(CARDINAL);
            ELSE EMSRemoveFromRing(C) END;
            RETURN
         END;
      END;
   END;
   ProgramErrorAndHalt('Error in EMS FreeUpHyperPage');
END FreeUpEMSPage;

BEGIN	(* GetNewEMSPage *)
   IF NOT EMSAvailable THEN
      ProgramErrorAndHalt('GetNewEMSPage called when EMS not available');
   END;
   WITH EMSInfo^ DO
      IF NoEMSInUse < NoEMSAvail THEN
         EMSPage := NoEMSInUse;
         INC(NoEMSInUse);
      ELSE
         FreeUpEMSPage(EMSPage);
      END;
      SetManagementDataPtr(EMSPageInfo[EMSPage], NIL );
      EMSPageInfo[EMSPage].RecordID := 0;
      EMSPageInfo[EMSPage].Changed := FALSE;
      EMSPageInfo[EMSPage].UseCount := 0;
      EMSInsertInRing(EMSPage);
   END;

   RETURN EMSPage;
END GetNewEMSPage;

PROCEDURE FindEMSPage(EMSRPageNo: CARDINAL): HRecordArrayPntr;
VAR i:  CARDINAL;
BEGIN
   FOR CurPPage := FirstLPgFree TO 3 DO
      IF EMSPPageNo[CurPPage] = EMSRPageNo THEN
         RETURN [LIM.GetPageFrame() : CurPPage * EMSPageSize];
      END;
   END;
   (* next try to find first unlocked page frame that is not being used *)
   FOR CurPPage := FirstLPgFree TO 3 DO
      IF NOT EMSPPageLocked[CurPPage] AND (EMSPPageNo[CurPPage] = MAX(CARDINAL)) THEN
	 EMSPPageNo[CurPPage] := EMSRPageNo;
	 RETURN [LIM.GetPageFrame() : LIM.MapPage(CurPPage, EMSRPageNo, EMSDataHandle)];
      END ;
   END ;
   (* last resort find first unlocked page frame *)
   FOR CurPPage := FirstLPgFree TO 3 DO
      IF NOT EMSPPageLocked[CurPPage] THEN
	 EMSPPageNo[CurPPage] := EMSRPageNo;
	 RETURN [LIM.GetPageFrame() : LIM.MapPage(CurPPage, EMSRPageNo, EMSDataHandle)];
      END ;
   END ;
   ProgramErrorAndHalt( "No Physical Page Frames avail in EMS." );
END FindEMSPage;

PROCEDURE LocateEMSPage(EMSPageNo: CARDINAL): HRecordPntr;
VAR
   EMSRPageNo, EMSPageOffset: CARDINAL;
   EMSDataPntr:  HRecordArrayPntr;
BEGIN
   IF NOT EMSAvailable THEN ProgramErrorAndHalt('No EMS in LocateEMSPage') END;
   IF EMSPageNo <> EMSInfo^.EMSPageList THEN
      EMSRemoveFromRing(EMSPageNo);
      EMSInsertInRing(EMSPageNo);
   END;
   EMSRPageNo := EMSPageNo DIV 16;
   EMSPageOffset := EMSPageNo MOD 16;
   EMSDataPntr := FindEMSPage(EMSRPageNo);
   RETURN ADR(EMSDataPntr^[EMSPageOffset]);
END LocateEMSPage;

PROCEDURE EMSToReal(EMSPageNo: CARDINAL): CARDINAL; (*segment address *)
VAR
   EMSDataPage: HRecordPntr;
   EMSRPageNo, EMSPageOffset: CARDINAL;
   Segment:     CARDINAL;
   i:		CARDINAL;
   rp:          RealStoragePntr;
BEGIN
   IF NOT EMSAvailable THEN ProgramErrorAndHalt('No EMS in EMSToReal') END;
   EMSDataPage := LocateEMSPage(EMSPageNo);
   i := CurPPage ;		(* remember which physical page we are using *)
   EMSPPageLocked[i] := TRUE ;  (* to ensure GetRealHyperPage doesn't erase page *)
   Segment := GetRealHyperPage(rp);
   EMSPPageLocked[i] := FALSE;  (* page is now available again *)
   rp^.HRecord := EMSDataPage^ ;
   CopyKiloInfo(EMSInfo^.EMSPageInfo[EMSPageNo], rp^.Data);
   SetManagementDataPtr( EMSInfo^.EMSPageInfo[EMSPageNo], NIL );  (* not avail anymore *)
(*   rp^.Data.Changed := FALSE ;	 *LP* *)
   RETURN Segment;
END EMSToReal;

PROCEDURE RealToEMS(SegAddr: CARDINAL): CARDINAL; (* EMS Page Number *)
VAR
   EMSDataPage:   HRecordArrayPntr;
   EMSPageNo:     CARDINAL;
   EMSRPageNo:    CARDINAL;
   EMSPageOffset: CARDINAL;
   rp:            RealStoragePntr;
BEGIN
   IF NOT EMSAvailable THEN ProgramErrorAndHalt('No EMS in RealToEMS') END;
   rp := [SegAddr : 0];
   (*<Assert   CheckDataAddr( rp ) ;    Assert>*)

   EMSPageNo := GetNewEMSPage();
   EMSRPageNo := EMSPageNo DIV 16;
   EMSPageOffset := EMSPageNo MOD 16;
   EMSDataPage := FindEMSPage(EMSRPageNo);
   CopyKiloInfo(rp^.Data,EMSInfo^.EMSPageInfo[EMSPageNo]);
   EMSDataPage^[EMSPageOffset] := rp^.HRecord;
   RETURN EMSPageNo;
END RealToEMS;

PROCEDURE ReleaseRealPage(No: CARDINAL);
VAR
   rp			: RealStoragePntr;
   ManagementDataPtr	: HyperPageManagementPntr;
BEGIN
   rp := [No : 0];
   (*<Assert   CheckDataAddr( rp ) ;    Assert>*)
   IF rp^.Data.UseCount <> 0 THEN
      ProgramErrorAndHalt('UseCount nonzero in ReleaseRealPage');
   END;
   IF rp^.Data.ManagementData <> 0 THEN
      ManagementDataPtr := GetManagementDataPtr( rp^.Data ) ;
      ManagementDataPtr^.RemoveFromReal(rp)
   END;
   IF No = RealPageList THEN RealPageList := rp^.Data.Next; END;

   IF No (*still*) = RealPageList THEN RealPageList := 0;
   ELSE RealRemoveFromRing(rp) END;
   DISPOSE(rp);
END ReleaseRealPage;

PROCEDURE ReleaseEMSPage(No: CARDINAL);
VAR b,f:  CARDINAL;
    ManagementDataPtr : HyperPageManagementPntr;
BEGIN
   WITH EMSInfo^ DO
      IF (EMSPageInfo[No].UseCount <> 0) THEN
         ProgramErrorAndHalt('UseCount nonzero in ReleaseEMSPage');
      END;

      IF EMSPageInfo[No].ManagementData <> 0 THEN
	 ManagementDataPtr := GetManagementDataPtr( EMSPageInfo[No] );
         ManagementDataPtr^.RemoveFromEMS(No);
	 SetManagementDataPtr(EMSPageInfo[No], NIL );
      END;
      IF No = EMSPageList THEN EMSPageList := EMSPageInfo[No].Next END;
      IF (No (* now *) <> EMSPageList) AND
	 (EMSPageInfo[EMSPageList].Prev <> No) THEN
         EMSRemoveFromRing(No);
         EMSInsertInRing(No);
         EMSPageList := EMSPageInfo[EMSPageList].Next;
      END;
   END;
END ReleaseEMSPage;

PROCEDURE MarkRealAsNotInUse(Ptr: RealStoragePntr);
VAR CS:   AddrType;
BEGIN
   IF (Ptr^.Data.UseCount <> 0) OR (Ptr^.Data.Changed) THEN
      ProgramErrorAndHalt('Record cannot be marked not in use')
   END;
   SetManagementDataPtr( Ptr^.Data, NIL ) ;
   Ptr^.Data.RecordID := 0;

   CS := AddrType(Ptr);
   IF CS.SEGMENT <> RealPageList THEN
      RealRemoveFromRing(Ptr);
      RealInsertInRing(Ptr);
   END;
   RealPageList := Ptr^.Data.Next;
END MarkRealAsNotInUse;

PROCEDURE DisplayBusy;
    VAR
	OldWin	: WinType ;
	Ch	: CHAR ;
    BEGIN
	IF ABWindow = NIL THEN  RETURN  END ;
	OldWin := Used() ;
	Use( ABWindow ) ;
	IF Indicator THEN
	   Ch := 011C ; (* tab char looks like <> *)
	ELSE
	   Ch := 07C ; (* raised period *)
	END ;
	DirectWrite( 78, 0, ADR( Ch ), 1 ) ;
	Use( OldWin ) ;
	NoOfCalls := 0 ;
	Indicator := NOT Indicator ;
    END DisplayBusy ;

PROCEDURE SetShowBusyWindow( ) ;
    BEGIN
	DisplayBusy;
    END SetShowBusyWindow ;

PROCEDURE ShowBusy ;
    BEGIN
	INC( NoOfCalls ) ;
	IF NoOfCalls MOD ThreshHold = 0 THEN
	   DisplayBusy;
	END ;
    END ShowBusy ;

PROCEDURE ALLOCATE(VAR a: SYSTEM.ADDRESS; size: CARDINAL);
VAR
   (*<Debug  avail: CARDINAL ;   Debug>*)
   CX:    RealStoragePntr;
   segno: CARDINAL;
   OK:    BOOLEAN;
BEGIN
    (*<Debug  avail := Storage.HeapAvail( Storage.MainHeap ) ;  Debug>*)
    IF (NOT Storage.Available(size + MinMemInBytes)) THEN
        REPEAT
            OK := FindRealPageToRelease(segno,CX);
            IF OK THEN Storage.DEALLOCATE(CX,SIZE(RealStorageRecord)) END;
        UNTIL (Storage.Available(size)) OR (NOT OK);
	(*<Debug  avail := Storage.HeapAvail( Storage.MainHeap ) ;  Debug>*)
    END;
(*  IF (NOT Storage.Available(size + MinMemInBytes)) THEN *)
    IF (NOT Storage.Available(size)) THEN
	ProgramErrorAndHalt('TACTStorage: insufficient memory for allocation.');
    END ;
    ShowBusy ;
    Storage.ALLOCATE(a,size);
    (*<Trace  *)
    IF DoTrace THEN
	INC( AllocCallNo ) ;
 	TWriteLn ;	(* flush out previous line if needed *)
	TWriteAddr( a ) ;
	TWriteCard( size, 5 ) ;
	TWriteString( ' A' ) ;
	TWriteCard( AllocCallNo, 6 ) ;
	TWriteLn ;
    END ;
(*    Trace>*)
END ALLOCATE;

PROCEDURE DEALLOCATE(VAR a: SYSTEM.ADDRESS; size: CARDINAL);
(*<Debug VAR TempAddr : AddrType ; Debug>*)
BEGIN
    IF a = NIL THEN
	ProgramErrorAndHalt('TACTStorage: attempting to DEALLOCATE nil pointer.');
    END ;
    ShowBusy;
    (*<Debug
    TempAddr := AddrType(a);
    IF a = LookForAddr THEN
	size := size (* so we can break here *)
    END ;
    Debug>*)
    (*<Trace *)
    IF DoTrace THEN
	(* INC( DeallocCallNo ) ; *)
 	TWriteLn ;	(* flush out previous line if needed *)
	TWriteAddr( a ) ;
	TWriteCard( size, 5 ) ;
	TWriteString( ' D' ) ;
	(* TWriteCard( DeallocCallNo, 6 ) ; *)
	TWriteLn ;
    END ;
(*    Trace>*)
    Storage.DEALLOCATE(a,size);
END DEALLOCATE;

BEGIN
   NoOfCalls := 0 ;
   (*<Trace  DoTrace := TRUE ;
               AllocCallNo := 0 ;
    Trace>*)
   Indicator := TRUE ;
   ABWindow := NIL ;
   CurEMSLPage := FirstLPgFree - 1 ;
   FOR CurPPage := FirstLPgFree TO 3 DO
	EMSPPageNo[CurPPage] := MAX(CARDINAL);
	EMSPPageLocked[CurPPage] := FALSE;
   END ;
	(*<Assert
	PgmStartAddr := LONGCARD( Lib.PSP ) * 16 ;
	PgmEndAddr := LONGCARD(SYSTEM.HeapBase) * 16 ;
	Assert>*)
END MemoryManagement.
