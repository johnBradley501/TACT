IMPLEMENTATION MODULE VirtualMemory ;

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

(*V1=Debug*)
(*V2=Production*)
(*V3=Assert*)

IMPORT FIO, Str, Lib ;
IMPORT Utils, UtilsTwo ;
FROM Storage IMPORT ALLOCATE, Available, DEALLOCATE ;
FROM SYSTEM  IMPORT TSIZE, ADR, ADDRESS ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResMessages IMPORT MsgString, PutResWarning;
FROM GlobalDefs IMPORT StrAny, FileNameType ;
FROM StartUp IMPORT FileData;
FROM StringIO IMPORT SWriteString, SWriteCard, SWriteInt ;
(*<Assert IMPORT SYSTEM ; Assert>*)

(*<Debug
FROM Trace IMPORT
  (* Vars  *) DoTrace,
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard, TWriteAddr;
Debug>*)

(*---------------------------------------------------------------------------
  Background Info:

  Virtual Address: is two "cardinal" numbers interpreted as follows
     +-----------------+--------------+  +--------+-------+----------------+
     | Page Table Index| Segment Index|  | Unused |        Offset          |
     +-----------------+--------------+  +--------+-------+----------------+
             8 bits         8 bits         4 bits      4  +   8 = 12 bits

      SegmentTable
     +------------+                       PageTable
   0 |____________| -------\           +------------+           VirtualPage
     |            |          \---->  0 |____________| ---\      +---------+
     |            |                    |            |     \---> |         |
     |     :      |                    |     :      |           |         |
     |     :      |                    |     :      |           |         |
     |            |                    |____________|           +---------+
     |____________|                255 |            | ---\           :
 255 |            |                    +------------+     \     +---------+
     +------------+                                        \--> |         |
                                                                |         |
                                                                |         |
                                                                +---------+

  Addressing Ranges:
     Offset             2**12 = 4096 = 4 K  [ Virtual Page Size ]
     Segement Index     2**8  =  256
     Page Table Index   2**8  =  256

  Addressing Space:  (No_tables / Segment) * (No_pages / Table) * (No_KBytes / Pages)
                     =  ( 2**8 ) * ( 2**8 ) * ( 4 K )
                     =  2 ** 18 K
                     =  262,144 K  ( = 256 Mb ) per segment

  Over head:  ( (Space_required / Page_size) / (Max_#_Page_Tables) * (Page_Table_Size)
                + Segment_Table_Size

      eg.  550K  ==> 1400 lines of text (approx. 20 pages)
          8800K <==>  320 pages [ie. novel size]

      For 1 K Virtual Page Size:
          OverHead = RoundUp( (8800 K / 1 K) / 256 ) * 4 K + 1 K = 141 K

      For 2 K Virtual Page Size:
          OverHead = RoundUp( (8800 K / 2 K) / 256 ) * 4 K + 1 K = 73 K

      For 4 K Virtual Page Size:
          OverHead = RoundUp( (8800 K / 4 K) / 256 ) * 4 K + 1 K = 37 K

  ----------------
  ** W A R N I N G ** These routines are DEPENDENT on IBM PC storage structure.

  On the IBM PC the ADDRESS structure is two cardinals/words as follows:
     ADDRESS  =  RECORD
                    SEGMENT : CARDINAL ;
                    OFFSET  : CARDINAL ;
                 END ;

  We will be taking the "most significant" byte (High byte) for the Virtual
  Address "Segment Index" and the "least significant" byte (Low byte) as the
  "Page Table Index".
  ie. :     SegmentIndex = VirtualAddr.SEGMENT DIV 256    [  8 bits ]
            PageTableIndex = VirtualAddr.SEGMENT MOD 256  [  8 bits ]
  and
      VirtualAddressOffset = VirtualAddr.OFFSET MOD 4096  [ 12 bits ]

  However, for our use, since we have a "byte" boundary, the SEGMENT will
  be define as type:  SEGEMENT = RECORD
                                    SEGMENTINDEX   : BYTE ;
                                    PAGETABLEINDEX : BYTE ;
                                 END ;
  for faster processing on the IBM PC (which is byte addressable).

  Page Table Entry Conventions:
     RealAddr = NIL          - not in memory
     ReadPos  = MaxINTEGER   - no copy on virtual IO file
     ReadPos  < 0	     - EMS logical page = -(ReadPos+1)
     ABS(UsageCounter) > 0   - page still in use (and can not be paged out)
     UsageCounter < 0        - page is dirty

  Also note with EMS:
     VirtPage.ReadPos <  0   - copy in EMS and EMSPageInfo[-(ReadPos+1)].ReadPos
				is either MaxINTEGER or disk position (>= 0)
  ---------------------------------------------------------------------------*)

CONST
   MaxPagesPerTable = 256 ;     (*  2**8 bits *)
   MaxSegmentsPerTable = 256 ;  (*  2**8 bits *)
(* VirtualPageSize = 4096 ;     (*  2**12 = 4 K *) <--- now in .DEF file *)
   MinSpaceRequired = VirtualPageSize + 4096 ; (* leave 8K for M2 ??? *)
   MaxINTEGER = MAX(INTEGER) ;
(*   VIOFileName = '$$VIRTIO.TMP' ; *)

TYPE
   AddressParts = RECORD
       OFFSET:     CARDINAL;
       SEGMENT:    CARDINAL;
   END;
   PageTableEntryPtr = POINTER TO PageTableEntry ;
   PageTableEntry = RECORD
(* m.s.                       QueueForward  : PageTableEntryPtr ; (* Page Replacement queue *)
                       QueueBackward : PageTableEntryPtr ;
                       UsageCounter  : INTEGER ; (* "Dirty" bit is neg. value *)
                       ReadPos       : INTEGER ; (* = MaxINT when no file copy exists *)
*)
                       CASE : BOOLEAN OF
                          TRUE : RealAddr : ADDRESS ; |  (* = NIL when paged out  *)
                          FALSE: RealPage : VirtPageStorePtr ; (* for easier viewing in RTD *)
                       END ;
                    END ;
(*   QueueType = RECORD
                  Front : PageTableEntryPtr ;
                  Rear  : PageTableEntryPtr ;
               END ;
*)
   PageTableRange = [0..MaxPagesPerTable-1] ;
   PageTable = ARRAY PageTableRange OF PageTableEntry ; (* = 4K Storage *)
   PageTablePtr = POINTER TO PageTable ;
   SegmentTableRange = [0..MaxSegmentsPerTable-1] ;
   SegmentTableEntry = RECORD
                          PageTableAddr : PageTablePtr ;
                       END ;
   SegmentTableType = POINTER TO ARRAY SegmentTableRange OF SegmentTableEntry ; (* = 1K Storage *)

   (* the VirtualPageSize - OFFSET will mark amount of free space in virt. page

   SpaceRecord = RECORD
                    VirtAddr   : VirtualAddrType ;
                 END ;  *)

(* m.s. (* ------------- EMS stuff here ---------------- *)
CONST
   MinNumberEMSPages = 2;
   EMSPageSize = 16 * 1024; (* 16 K page frames *)

TYPE
   KiloInfo = RECORD  (* this info kept in EMS physical page frame 0 *)
      LastUsed		: CARDINAL;
      ReadPos		: CARDINAL; (* has VIO file pos of ever written to disk *)
      VirtPage		: PageTableEntryPtr ;
   END;

CONST
   (* Max no = 16K/8=2048-1 possible 16K EMS pages (just less than 32 MB max) *)
   MaxNoEMSPages = (EMSPageSize-4 (* 2 CARDINALS *) ) DIV SIZE(KiloInfo);
   NoPagesPerFrame = EMSPageSize DIV VirtualPageSize ; (* 16K / 4K = 4 *)

TYPE
   EMSVirtPageArrayPtr = POINTER TO ARRAY[0..NoPagesPerFrame-1] OF VirtPageStorage;

   EMSInfoPagePntr = POINTER TO RECORD
      NoEMSPagesInUse	: CARDINAL;
      NoEMSPagesAvail	: CARDINAL;
      EMSPageInfo	: ARRAY[0..MaxNoEMSPages - 1] OF KiloInfo;
   END;

VAR
   EMSInfo              : EMSInfoPagePntr;
   EMSAvailable		: BOOLEAN;
   EMSInfoHandle	: CARDINAL;
   EMSDataHandle	: CARDINAL;
   LRUCount		: CARDINAL;
(* ------------- End of EMS stuff ---------------- *)
*)

VAR
   SegmentTable              : SegmentTableType ;
   CurrentReadPos            : CARDINAL ;
   CurrentNoSegments         : CARDINAL ;
   CurrentNoPageTableEntries : CARDINAL ;
(*   Queue                     : QueueType ; *)
   Message                   : StrAny ;
(*   BIOResult                 : CARDINAL ;
   VirtualIOFile             : FIO.File ;
   NoPageIn                  : LONGINT ;
   NoPageOut                 : LONGINT ;
*)
   NoOfPageReferences        : LONGINT ;
   TotalPageFragmentation    : LONGINT ;  (* unusable space in pages *)
(*   HexRep                    : ARRAY[0..4] OF CHAR ;
   TempAddr                  : ADDRESS ;   (* for pointer type conversion *)
   MesPos                    : CARDINAL ;
   VirtualIOFileName	     : FileNameType ;
*)
(*<Debug
PROCEDURE WriteVirt( VirtualPage : PageTableEntryPtr ) ;
   BEGIN
      TWriteString( ' VPg = ' ) ;
      TWriteAddr( ADDRESS( VirtualPage ) ) ;
      TWriteString( ' Use =' ) ;
      TWriteInt( VirtualPage^.UsageCounter, 3 ) ;
      TWriteString( ' File = ' ) ;
      IF VirtualPage^.ReadPos = MaxINTEGER THEN
         TWriteString( 'NONE' )
      ELSE
         TWriteCard( VirtualPage^.ReadPos, 4 ) ;
      END ;
      TWriteString( ' ' ) ;
      IF VirtualPage^.RealAddr = NIL THEN
         TWriteString( '      NIL' ) ;
      ELSE
         TWriteAddr( ADDRESS(VirtualPage^.RealAddr) ) ;
      END ;
      TWriteLn ;
   END WriteVirt ;

PROCEDURE DumpVirtualQueue ;
   VAR
      QueueNode  : PageTableEntryPtr ;
      NodeCount  : CARDINAL ;
   BEGIN
      NodeCount := 0 ;
      QueueNode := Queue.Front ;
      TWriteString( '------' ) ;
      TWriteLn ;
      WHILE QueueNode <> NIL DO
         INC( NodeCount ) ;
         TWriteCard( NodeCount, 3 ) ;
         TWriteString( ' P: ' ) ;
         TWriteAddr( ADDRESS( QueueNode^.QueueForward ) ) ;
         TWriteString( ' N: ' ) ;
         TWriteAddr( ADDRESS( QueueNode^.QueueBackward ) );
         WriteVirt( QueueNode ) ;
         QueueNode := QueueNode^.QueueBackward ;
      END ;
      TWriteString( 'Rear of queue.' ) ;
      TWriteLn ;
   END DumpVirtualQueue ;
Debug>*)

(* m.s.
PROCEDURE UpdateLRU( VAR NewLRU : CARDINAL ) ;
   VAR  p : CARDINAL ;
   BEGIN
	(* Update quasi-time *)
	INC( LRUCount ) ;
	IF LRUCount = MAX(CARDINAL) THEN
	   WITH EMSInfo^ DO	(* reset all LRU at wrap-around time *)
	      (* halve all entries to maintain relative time references *)
	      FOR p := 0 TO NoEMSPagesInUse-1 DO
		 EMSPageInfo[p].LastUsed := EMSPageInfo[p].LastUsed DIV 2 ;
	      END ;
	   END ;
	   LRUCount := LRUCount DIV 2 ;
	END ;
	NewLRU := LRUCount ;
   END UpdateLRU ;

PROCEDURE FindEMSVictom( VAR EMSPageRef : CARDINAL ) ;
   VAR
	MinLRU, p	: CARDINAL ;
	Found		: BOOLEAN ;
   BEGIN
	MinLRU := MAX(CARDINAL) ;
	WITH EMSInfo^ DO
	  p := 0 ;
	  Found := FALSE ;	
	  WHILE NOT Found AND (p < NoEMSPagesInUse) DO
	     IF EMSPageInfo[ p ].VirtPage = NIL THEN
		EMSPageRef := p ;
		Found := TRUE ;
	     ELSE
		WITH EMSPageInfo[ p ] DO
		IF (VirtPage^.UsageCounter = 0) OR (VirtPage^.UsageCounter = -1) THEN
		   IF LastUsed < MinLRU THEN
			MinLRU := LastUsed;
			EMSPageRef := p ;
		   END ;
		END ;
		INC( p ) ;
		END ;
	     END ;
	  END ;
	  IF NOT Found AND (MinLRU = MAX(CARDINAL)) THEN
	     ProgramErrorAndHalt( 'Unable to get a free EMS Virtual Page frame.' );
	  END ;
	END ;
   END FindEMSVictom ;

PROCEDURE LocateEMSAddr( pg : CARDINAL; VAR EMSAddr : VirtPageStorePtr ) ;
   VAR
	Page, Offset	: CARDINAL ;
	TempAddr	: EMSVirtPageArrayPtr ;
   BEGIN
	Page   := pg DIV NoPagesPerFrame ;
	Offset := pg MOD NoPagesPerFrame ;
	TempAddr := [LIM.GetPageFrame() : LIM.MapPage(1,Page,EMSDataHandle) ] ;
	EMSAddr  := VirtPageStorePtr( ADR( TempAddr^[ Offset ] ) ) ;
   END LocateEMSAddr ;

PROCEDURE PageOut( VirtualPage : PageTableEntryPtr ) ; FORWARD ;
PROCEDURE Dirty( VirtualPage : PageTableEntryPtr ) : BOOLEAN ; FORWARD ;

PROCEDURE PageEMSToDisk( pg : CARDINAL ) ;
   VAR
	CleanUp : BOOLEAN ;
   BEGIN
	WITH EMSInfo^.EMSPageInfo[ pg ] DO
	   IF VirtPage = NIL THEN  RETURN  END ; (* a copy of image exists on disk or real mem! *)	
	   VirtPage^.ReadPos := ReadPos ; (* EMSPageInfo[pg].ReadPos is disk loc or MaxINT *)
	   VirtPage^.UsageCounter := -1 ; (* force a write to disk by PageOut *)
	   IF VirtPage^.RealAddr <> NIL THEN
	      ProgramErrorAndHalt( 'Inconsistancy in PageEMSToDisk.');
	   END ;
	   LocateEMSAddr( pg, VirtPage^.RealPage (* == RealAddr *) ) ;
	   PageOut( VirtPage ) ;(* to Disk *)
	   VirtPage^.RealPage := NIL ;	(* no longer have a real addr!! *)
	   VirtPage := NIL ;	(* EMS page slot now available for re-use *)
	END ;
   END PageEMSToDisk ;

PROCEDURE PageEMSToReal( VirtualPage : PageTableEntryPtr; pg : CARDINAL ) ;
   VAR
	EMSAddr : VirtPageStorePtr ;
   BEGIN
	LocateEMSAddr( pg, EMSAddr ) ;
	WITH EMSInfo^.EMSPageInfo[ pg ] DO
	   VirtualPage^.ReadPos := ReadPos ;(* true disk loc. status *)
	   VirtualPage^.UsageCounter := 0 ; (* clean copy exists on EMS *)
	   VirtualPage^.RealPage^ := EMSAddr^ ;  (* or BlockMove ?? *)
	   VirtPage := NIL ;	(* EMS page slot now available for re-use *)
	END ;
   END PageEMSToReal ;

PROCEDURE PageRealToEMS( VirtualPage : PageTableEntryPtr; pg : CARDINAL ) ;
   VAR
	EMSAddr : VirtPageStorePtr ;
   BEGIN
	LocateEMSAddr( pg, EMSAddr ) ;
	EMSAddr^ := VirtualPage^.RealPage^ ;  (* or BlockMove ?? *)
	WITH EMSInfo^.EMSPageInfo[ pg ] DO
	   ReadPos  := VirtualPage^.ReadPos ;
	   VirtPage := VirtualPage ;
	   UpdateLRU( LastUsed ) ; (* we don't select this EMS page as victom *)
	END ;
	VirtualPage^.ReadPos := - ( INTEGER(pg + 1) );
	VirtualPage^.UsageCounter := 0 ;
   END PageRealToEMS ;

PROCEDURE PageOutToEMS( VirtualPage : PageTableEntryPtr ) ;
   VAR	pg : CARDINAL ;
   BEGIN
	IF Dirty( VirtualPage ) THEN
	   WITH VirtualPage^ DO
	      IF ReadPos < 0 THEN
		 (* a slot already reserved in EMS info *)
		 pg := CARDINAL( - ReadPos - 1 ) ;
	      ELSE (* ELSIF ReadPos = MaxINTEGER THEN *)
		 (* never been to EMS *)
		 IF EMSInfo^.NoEMSPagesInUse < EMSInfo^.NoEMSPagesAvail THEN
		    pg := EMSInfo^.NoEMSPagesInUse ;
		    INC( EMSInfo^.NoEMSPagesInUse ) ;
	         ELSE (* no more slots available *)
		    FindEMSVictom( pg ) ;
		    PageEMSToDisk( pg ) ;
	         END ;
(*	      ELSE
		 ProgramErrorAndHalt( 'Inconsistancy in PageOutToEMS.'); *)
	      END ;
	   END ;
	   PageRealToEMS( VirtualPage, pg ) ;
	END ;
   END PageOutToEMS ;


PROCEDURE CheckIOResult() ;
VAR rslt:   CARDINAL;
    Msg:    ARRAY[0..50] OF CHAR;
   BEGIN
      rslt := FIO.IOresult();
      IF rslt = 0 THEN RETURN END;

      UtilsTwo.IOErrorMessage(rslt, Msg) ;
      FIO.Close( VirtualIOFile ) ;
      FIO.Erase( VIOFileName );
      ProgramErrorAndHalt( Msg );
   END CheckIOResult ;

PROCEDURE AddToRearOfQueue( Node : PageTableEntryPtr ) ;
   (*<Assert VAR NormalizedAddr : LONGCARD ; Assert>*)
   BEGIN
      IF Node = NIL THEN
         ProgramErrorAndHalt( 'Program error: adding invalid node to rear of queue.');
      END ;
      (*<Assert
	NormalizedAddr := LONGCARD(SYSTEM.Seg(Node^.RealAddr^))*16 + LONGCARD(SYSTEM.Ofs(Node^.RealAddr^)) ;
	IF (NormalizedAddr > 640*1024) THEN
	   (* this address is outside the program code in memory *)
	   ProgramErrorAndHalt( "Invalid node in AddToRearOfQueue" );
	END ;
      Assert>*)
      IF Queue.Rear = NIL THEN  (* empty queue *)
         Queue.Front := Node ;
         Queue.Rear  := Node ;
         Node^.QueueForward  := NIL ;
         Node^.QueueBackward := NIL ;
      ELSE  (* at least one node in queue *)
         Queue.Rear^.QueueBackward := Node ; (* change previous node ptr *)
         Node^.QueueForward  := Queue.Rear ;
         Queue.Rear          := Node ;
         Node^.QueueBackward := NIL ;
      END ;
   END  AddToRearOfQueue ;

PROCEDURE RemoveNode( Node : PageTableEntryPtr ) ;
   VAR
      PreviousNode, NextNode : PageTableEntryPtr ;
   BEGIN
      IF (Node = NIL) OR (Queue.Front = NIL) THEN
         ProgramErrorAndHalt( 'invalid node to remove from Page Replacement Queue.');
      END ;
      IF (Node^.QueueForward = NIL) AND (Node^.QueueBackward = NIL) THEN
         RETURN   (* ignore this node - it has no real address attached to page *)
      END ;
      IF Node = Queue.Front THEN
         (* case: node is at front of queue *)
         Queue.Front := Node^.QueueBackward ;
         IF Queue.Front = NIL THEN
            Queue.Rear := NIL ;  (* queue is now empty *)
         ELSE
            PreviousNode := Node^.QueueBackward ;
            PreviousNode^.QueueForward := NIL ;
         END ;
      ELSE
         (* case: there is at least one following node *)
         NextNode := Node^.QueueForward ;
         NextNode^.QueueBackward := Node^.QueueBackward ;
         IF Node = Queue.Rear THEN
            Queue.Rear := NextNode ;
         ELSE
            PreviousNode := Node^.QueueBackward ;
            PreviousNode^.QueueForward := NextNode ;
         END ;
      END ;
      Node^.QueueForward  := NIL ; (* for completeness sake *)
      Node^.QueueBackward := NIL ;
   END  RemoveNode ;

PROCEDURE Dirty( VirtualPage : PageTableEntryPtr ) : BOOLEAN ;
   BEGIN
      RETURN (VirtualPage^.UsageCounter < 0) ;
   END  Dirty ;

PROCEDURE PageIn( VirtualPage : PageTableEntryPtr ) ;
   VAR
      Count  :  CARDINAL ;
   BEGIN
      IF VirtualPage^.RealAddr = NIL THEN
         ProgramErrorAndHalt( 'Attempting to page into an invalid pageframe.');
      END ;

      IF (VirtualPage^.ReadPos = MaxINTEGER) OR (VirtualPage^.ReadPos < 0) THEN
         (* this virtual page was never written out *)
         ProgramErrorAndHalt( 'No copy of virtual page on Virtual IO file exists.');
      END ;

      (*<Debug
      IF DoTrace THEN
         TWriteString( 'PageIn:  ' ) ;
         WriteVirt( VirtualPage ) ;
      END ;
      Debug>*)

      FIO.Seek( VirtualIOFile, VAL(LONGCARD,VirtualPage^.ReadPos) *
                               VAL(LONGCARD, VirtualPageSize));
      CheckIOResult ;
      INC( NoPageIn ) ;
      Count := FIO.RdBin( VirtualIOFile, VirtualPage^.RealAddr^, VirtualPageSize );
      CheckIOResult ;
      IF Count <> VirtualPageSize THEN
         FIO.Close( VirtualIOFile ) ;
         FIO.Erase( VIOFileName ) ;
         ProgramErrorAndHalt( 'PageIn:  wrong "Count" (number of characters) read in.') ;
      END ;
      (* mark page as clean *)
      VirtualPage^.UsageCounter := 0 ;
   END PageIn ;

(*<Debug VAR DiskPgSet : ARRAY[0..VirtPageSize-1] OF BOOLEAN ; Debug>*)

PROCEDURE PageOut( VirtualPage : PageTableEntryPtr ) ;
   BEGIN
      IF NOT ((VirtualPage^.UsageCounter = 0) OR (VirtualPage^.UsageCounter = -1)) THEN
         ProgramErrorAndHalt( 'Attempting to page out a VirtualPage still in use.');
      END ;

      (*<Debug
      IF DoTrace THEN
         TWriteString( 'PageOut:  ' ) ;
         WriteVirt( VirtualPage ) ;
      END ;
      Debug>*)

      (* only need to page out "dirty" pages or no file copy exists *)
      IF Dirty( VirtualPage ) OR (VirtualPage^.ReadPos = MaxINTEGER) THEN
         IF VirtualPage^.ReadPos = MaxINTEGER THEN
            (* this virtual page was never written out *)
            IF CurrentReadPos = CARDINAL(MaxINTEGER) THEN
               FIO.Close( VirtualIOFile ) ;
               FIO.Erase( VIOFileName ) ;
               ProgramErrorAndHalt( 'Exceeding program limit for number of virtual pages.  Program Terminating');
            END ;
            FIO.Seek( VirtualIOFile, VAL(LONGCARD,CurrentReadPos) *
                               VAL(LONGCARD, VirtualPageSize));
            VirtualPage^.ReadPos := CurrentReadPos ;
            INC( CurrentReadPos ) ;
         ELSIF VirtualPage^.ReadPos < 0 THEN
	    ProgramErrorAndHalt( 'Attempting to PageOut an EMS page.');
	 ELSE
            FIO.Seek( VirtualIOFile, VAL(LONGCARD,VirtualPage^.ReadPos) *
                               VAL(LONGCARD, VirtualPageSize));
         END ;
         CheckIOResult ;
         INC( NoPageOut ) ;
         FIO.WrBin( VirtualIOFile, VirtualPage^.RealAddr^, VirtualPageSize);
         CheckIOResult ;
         (* mark page as clean *)
         VirtualPage^.UsageCounter := 0 ; (* should really use IbmPCHighBit here *)
      END ;
      (*<Debug
      FOR I := 0 TO CurrentNoSegments DO
	 FOR J := 0 TO VirtualPageSize-1 DO
	    VirtPg := PageTableEntryPtr( ADR(SegmentTable^[I].PageTableAddr^[J]) ) ;
	 END ;
      END ;
      Debug>*)
   END PageOut ;

(*<Debug VAR NoOfRealPages, OldNoPages : CARDINAL ; Debug>*)

PROCEDURE FindREALVictom( VAR VirtualPage : PageTableEntryPtr ) ;
   (* searches the replacement queue for a VirtualPage to page out  *)
   (* and reuse the page "frame" (ie. real memory occupied by page) *)
   (* Use a "second" chance strategy as oppose to page in front of  *)
   (* queue.                                                        *)
   VAR
      QueueNode  :  PageTableEntryPtr ;
      Found      :  BOOLEAN ;
   (*<Assert VAR NormalizedAddr : LONGCARD ; Assert>*)
   BEGIN
      (*<Debug
      QueueNode := Queue.Front ;
      OldNoPages := NoOfRealPages ;
      NoOfRealPages := 0 ;
      WHILE QueueNode <> NIL DO
	(*<Assert
	NormalizedAddr := LONGCARD(SYSTEM.Seg(QueueNode^.RealAddr^))*16 + LONGCARD(SYSTEM.Ofs(QueueNode^.RealAddr^)) ;
	IF (NormalizedAddr > 640*1024) THEN
	   (* this address is outside the program code in memory *)
	   ProgramErrorAndHalt( "Invalid node in AddToRearOfQueue/FindRealVictom" );
	END ;
	Assert>*)
	INC( NoOfRealPages ) ;
	QueueNode := QueueNode^.QueueBackward ;
      END ;
      IF OldNoPages <> NoOfRealPages THEN  DumpVirtualQueue  END ;
      Debug>*)

      Found := FALSE ;
      QueueNode := Queue.Front ;

      (* look for a VirtualPage which has a clean copy on the VirtualIOFile *)
      (* and is not dirty.                                                  *)
      WHILE NOT Found AND (QueueNode <> NIL) DO
(*	 IF (QueueNode^.UsageCounter = 0) AND (QueueNode^.ReadPos <> MaxINTEGER) AND (QueueNode^.RealAddr <> NIL) THEN *)
         IF (QueueNode^.UsageCounter = 0) AND (QueueNode^.ReadPos <> MaxINTEGER) THEN
            Found := TRUE ;
         ELSE
            QueueNode := QueueNode^.QueueBackward ;
         END ;
      END ;
      IF NOT Found THEN
         (* no easy victom -- use anyone existing page frame from front queue *)
         QueueNode := Queue.Front ;
(*	 WHILE (QueueNode <> NIL) AND
               ( ((QueueNode^.UsageCounter <> 0) AND (QueueNode^.UsageCounter <> -1)) OR
               (QueueNode^.RealAddr = NIL)) DO	*)
         WHILE (QueueNode <> NIL) AND (QueueNode^.UsageCounter <> 0) AND (QueueNode^.UsageCounter <> -1) DO
            QueueNode := QueueNode^.QueueBackward ;
         END ;
         IF (QueueNode = NIL) OR (QueueNode^.RealAddr = NIL) THEN
            ProgramErrorAndHalt( 'Unable to get a free Virtual Page frame.' );
         END ;
      END ;

      (*<Debug
      IF DoTrace THEN
         TWriteString( 'FindVict: ' ) ;
         WriteVirt( QueueNode ) ;
      END ;
      Debug>*)

      RemoveNode( QueueNode ) ;  (* it no longer has a real mem frame *)
      VirtualPage := QueueNode ;
   END FindREALVictom ;
*)

PROCEDURE MakeReal(     VirtualAddr : VirtualAddrType;
                    VAR RealAddress : ADDRESS ) ;
   VAR
      RAParts	: AddressParts;
      SegmentIndex, PageTableIndex : CARDINAL ;
      VirtualPage: PageTableEntryPtr ;
(*            VictomVirtualPage      : PageTableEntryPtr ;
      PreviousNode, NextNode : PageTableEntryPtr ;
      pg	: CARDINAL ;
*)
   (*<Assert VAR NormalizedAddr : LONGCARD ; Assert>*)
   BEGIN
      SegmentIndex   := ORD( VirtualAddr.SEGMENTINDEX ) ;
      PageTableIndex := ORD( VirtualAddr.PAGETABLEINDEX ) ;
      IF (SegmentIndex > CurrentNoSegments) OR (PageTableIndex >= MaxPagesPerTable) THEN
         ProgramErrorAndHalt( 'Attempting to MakeReal an invalid Virtual Page.');
      END ;
      WITH SegmentTable^[SegmentIndex]  DO
         VirtualPage := PageTableEntryPtr( ADR(PageTableAddr^[PageTableIndex]) ) ;
      END ;

      (*<Debug
      IF DoTrace THEN
         TWriteString( 'MakeReal: VAddr = ' ) ;
         TWriteAddr( ADDRESS( VirtualAddr ) ) ;
         WriteVirt( VirtualPage ) ;
      END ;
      Debug>*)

      WITH VirtualPage^ DO
         IF RealAddr = NIL THEN
             (* error now, all entries should have real addresses *)
             ProgramErrorAndHalt(' Attempting to MakeReal a null pointer.') ;


(*  m.s.          (* get the Virtual Page back from the file or EMS *)
            IF ReadPos = MaxINTEGER THEN
               ProgramErrorAndHalt( 'Accessing invalid VirtualPage.');
            END ;

	    FindREALVictom( VictomVirtualPage ) ;	(* real mem frame addr *)
	    (* MarkDirty( VictomVirtualPage ) ;		(* force write out *) *)
	    WITH VictomVirtualPage^ DO
		IF UsageCounter >= 0 THEN  UsageCounter := - UsageCounter - 1  END ;
	    END ;
	    IF EMSAvailable THEN
		PageOutToEMS( VictomVirtualPage ) ;
	    ELSE
		PageOut( VictomVirtualPage ) ;
	    END ;
	    RealAddr := VictomVirtualPage^.RealAddr ;
	    VictomVirtualPage^.RealAddr := NIL ;
	    IF (ReadPos < 0) THEN
		pg := CARDINAL( - ReadPos - 1 ) ;
		PageEMSToReal( VirtualPage, pg ) ;
		UpdateLRU( EMSInfo^.EMSPageInfo[pg].LastUsed ) ;
	    ELSE  (* resides on disk *)
		(*<Debug  IF DoTrace THEN  DumpVirtualQueue  END ;  Debug>*)
		PageIn( VirtualPage ) ;
            END ;
*)
         END ; (* if *)
(*	 RemoveNode( VirtualPage ) ;
	 AddToRearOfQueue( VirtualPage ) ;
*)	
(* m.s.	 (* move this virtual page to the back of the replacement queue *)
	 (* >>> Duplicated code from RemoveNode & AddToRearOfQueue <<< *)

	 (* RemoveNode( VirtualPage : PageTableEntryPtr ) ; *)
	 IF (Queue.Front = NIL) OR (VirtualPage = NIL) THEN
		ProgramErrorAndHalt( 'invalid node to remove from Page Replacement Queue.');
	 END ;
	 IF VirtualPage = Queue.Front THEN
		(* case: node is at front of queue *)
		Queue.Front := VirtualPage^.QueueBackward ;
		IF Queue.Front = NIL THEN
		   Queue.Rear := NIL ;  (* queue is now empty *)
		ELSE
		   PreviousNode := VirtualPage^.QueueBackward ;
		   PreviousNode^.QueueForward := NIL ;
		END ;
	 ELSIF VirtualPage^.QueueForward <> NIL (* not a new entry *) THEN
		(* case: there is at least one following node *)
		NextNode := VirtualPage^.QueueForward ;
		NextNode^.QueueBackward := VirtualPage^.QueueBackward ;
		IF VirtualPage = Queue.Rear THEN
		   Queue.Rear := NextNode ;
		ELSE
		   PreviousNode := VirtualPage^.QueueBackward ;
		   PreviousNode^.QueueForward := NextNode ;
		END ;
	 END ;

      (*<Assert
	NormalizedAddr := LONGCARD(SYSTEM.Seg(RealAddr^))*16 + LONGCARD(SYSTEM.Ofs(RealAddr^)) ;
	IF (NormalizedAddr > 640*1024) THEN
	   (* this address is outside the program code in memory *)
	   ProgramErrorAndHalt( "Invalid node in AddToRearOfQueue/MakeReal" );
	END ;
      Assert>*)

	 (* AddToRearOfQueue( VirtualPage : PageTableEntryPtr )  *)
	 IF Queue.Rear = NIL THEN  (* empty queue *)
		Queue.Front := VirtualPage ;
		Queue.Rear  := VirtualPage ;
		VirtualPage^.QueueForward  := NIL ;
		VirtualPage^.QueueBackward := NIL ;
	 ELSE  (* at least one node in queue *)
		Queue.Rear^.QueueBackward := VirtualPage ; (* change previous node ptr *)
		VirtualPage^.QueueForward := Queue.Rear ;
		Queue.Rear := VirtualPage ;
		VirtualPage^.QueueBackward := NIL ;
	 END ;
*)
         RAParts := AddressParts(RealAddr);
         INC( RAParts.OFFSET, VirtualAddr.OFFSET );
         RealAddress := ADDRESS(RAParts);
(* m.s.
         (* mark the page as being used *)
         IF UsageCounter >= 0 THEN
            INC( UsageCounter )
         ELSE (* page is dirty, maintain "high" bit status *)
            DEC( UsageCounter )
         END ;
*)
      END ;

      INC( NoOfPageReferences ) ;

   END MakeReal ;


PROCEDURE CreateNewPageTable( VAR PageTableAddr : PageTablePtr ) ;
   VAR
      I           : CARDINAL ;
      VirtualPage : PageTableEntryPtr ;
   BEGIN
      IF Available( MinSpaceRequired ) THEN
         ALLOCATE( PageTableAddr, TSIZE(PageTable) ) ;
      ELSE  (* make room by paging some VirtualPage out *)
         ProgramErrorAndHalt( 'Out of memory while attempting to CreateNewPageTable.') ;
(* m.s.	 FindREALVictom( VirtualPage ) ;
	 (*	MarkDirty( VictomVirtualPage ) ;	(* force write out *) *)
	 WITH VirtualPage^ DO
		IF UsageCounter >= 0 THEN  UsageCounter := - UsageCounter - 1  END ;
	 END ;
	 IF EMSAvailable THEN
	   PageOutToEMS( VirtualPage ) ;
	 ELSE
	   PageOut( VirtualPage ) ;
	 END ;

         (*<Debug
         IF DoTrace THEN
            TWriteString( 'CreateNewPageTable: Victom page - ' ) ;
            WriteVirt( VirtualPage ) ;
            DumpVirtualQueue ;
         END ;
         Debug>*)

         PageTableAddr := PageTablePtr( VirtualPage^.RealAddr ) ;  (* type tranfer *)
         VirtualPage^.RealAddr := NIL ;
         (* remove it from "replacement queue" to prevent it from being paged out *)
	 (* RemoveNode( VirtualPage ) ; *)
*)	
      END ;
      (* initialize new page table *)
      FOR I := 0 TO MaxPagesPerTable - 1 DO
          WITH PageTableAddr^[ I ] DO
             RealAddr      := NIL ;         (* no "page frame" for virtual page *)
(* m.s.             QueueForward  := NIL ;
             QueueBackward := NIL ;
             UsageCounter  := 0 ;           (* clean and not in use *)
             ReadPos       := MaxINTEGER ; (* not written out yet *)
*)
          END ;
      END ;
      CurrentNoPageTableEntries := 0 ;
   END CreateNewPageTable ;

PROCEDURE AllocatePage( VAR VirtualAddr : VirtualAddrType;
                        VAR RealAddress : ADDRESS ) ;
   VAR
      VirtualPage       : PageTableEntryPtr ;
(*      VictomVirtualPage : PageTableEntryPtr ;
      pg	: CARDINAL ;
*)
   BEGIN
      (* check if we have room in "book" keeping tables *)
      IF CurrentNoPageTableEntries >= MaxPagesPerTable THEN
         INC( CurrentNoSegments ) ;
         IF CurrentNoSegments >= MaxSegmentsPerTable THEN
(* m.s.          FIO.Close( VirtualIOFile ) ;
            FIO.Erase( VIOFileName );
*)
            ProgramErrorAndHalt( 'Insufficient memory.  Segment Table overflow in AllocatePage.  Program terminating');
         END ;
         CreateNewPageTable( SegmentTable^[CurrentNoSegments].PageTableAddr ) ;
      END ;

      WITH SegmentTable^[CurrentNoSegments] DO
         VirtualPage := PageTableEntryPtr( ADR(PageTableAddr^[CurrentNoPageTableEntries]) ) ;
      END ;
      WITH VirtualPage^ DO
         IF Available( MinSpaceRequired ) THEN
            ALLOCATE( RealAddr, VirtualPageSize ) ;
         ELSE
            (* out of memory *)
            ProgramErrorAndHalt( ' Insufficient memory for AllocatePage. Program terminating.' );

(* m.s.            FindREALVictom( VictomVirtualPage ) ; (* real mem frame addr *)
	    (*	    MarkDirty( VictomVirtualPage ) ;	(* force write out *) *)
	    WITH VictomVirtualPage^ DO
		IF UsageCounter >= 0 THEN  UsageCounter := - UsageCounter - 1  END ;
	    END ;
	    IF EMSAvailable THEN
		PageOutToEMS( VictomVirtualPage ) ;
	    ELSE
		PageOut( VictomVirtualPage ) ;
	    END ;

            (*<Debug
            IF DoTrace THEN
               TWriteString( 'AllocatePage: Victom page - ' ) ;
               WriteVirt( VirtualPage ) ;
               DumpVirtualQueue ;
            END ;
            Debug>*)

            RealAddr := VictomVirtualPage^.RealAddr ;
            VictomVirtualPage^.RealAddr := NIL ;
*)
         END ;
(* m.s.	 ReadPos := MaxINTEGER ; (* ie. not written out yet *) *)
         RealAddress := RealAddr ;

         Lib.Fill( RealAddress, VirtualPageSize, 0377C );

         INC( NoOfPageReferences ) ;
(* m.s.         UsageCounter := 0 ;  (* and not "dirty" *)
         AddToRearOfQueue( VirtualPage ) ;
*)
         (* now form the virtual address *)
         VirtualAddr.OFFSET  := 0 ; (* Virtual offset starts always at 0 *)
         VirtualAddr.SEGMENTINDEX   := CHR( CurrentNoSegments );
         VirtualAddr.PAGETABLEINDEX := CHR( CurrentNoPageTableEntries );
      END ;
      INC( CurrentNoPageTableEntries ) ;
   END AllocatePage ;

PROCEDURE AllocateSpace( VAR VirtAddr    : VirtualAddrType ;
                         VAR RealAddress : ADDRESS ;
                         VAR SpaceType   : VirtualAddrType ;
                             Size        : CARDINAL ) ;
   (* AllocateSpace will keep "data" of the same type on the same virtual page
      frame to prevent excessive pagination on access of the data.
      SpaceType keeps track of unused space in a page frame of a particular
      type such as Tokens, Strings, Occurances, etc..
      Note: must initialize the SpaceType.OFFSET to greater than PageSize *)
   BEGIN
      IF Size > VirtualPageSize THEN
         ProgramErrorAndHalt( 'AllocateSpace: variable size greater than page size.' );
      END ;
      IF Size + SpaceType.OFFSET > VirtualPageSize THEN
         IF VirtualPageSize >  SpaceType.OFFSET THEN  (* ignore start value *)
            TotalPageFragmentation := TotalPageFragmentation +
                 VAL(LONGINT, VirtualPageSize - SpaceType.OFFSET) ;
         END ;
         AllocatePage( VirtAddr, RealAddress ) ;
(* m.s.         MarkInUse( VirtAddr ) ; *)
         SpaceType := VirtAddr ;
      ELSE
         VirtAddr := SpaceType ;
         MakeReal( VirtAddr, RealAddress ) ;
      END ;
(* m.s.     MarkDirty( VirtAddr ) ; (* because going to use/write to space after alloc *) *)
      INC( SpaceType.OFFSET, Size ) ; (* next avail. offset *)
   END AllocateSpace ;

(* m.s.
PROCEDURE MarkInUse( VirtualAddr : VirtualAddrType ) ;
   VAR
      SegmentIndex, PageTableIndex : CARDINAL ;
      VirtualPage                  : PageTableEntryPtr ;
   BEGIN
      INC( NoOfPageReferences ) ;
      SegmentIndex   := ORD( VirtualAddr.SEGMENTINDEX ) ;
      PageTableIndex := ORD( VirtualAddr.PAGETABLEINDEX ) ;
      IF (SegmentIndex > CurrentNoSegments) OR (PageTableIndex >= MaxPagesPerTable) THEN
         ProgramErrorAndHalt( 'Attempting to MarkInUse an invalid Virtual Page.');
      END ;
      WITH SegmentTable^[SegmentIndex]  DO
         VirtualPage := PageTableEntryPtr( ADR(PageTableAddr^[PageTableIndex]) ) ;
      END ;
      WITH VirtualPage^ DO
         (* mark the page as being used *)
         IF UsageCounter >= 0 THEN
            INC( UsageCounter )
         ELSE (* page is dirty, maintain "high" bit status *)
            DEC( UsageCounter )
         END ;
      END ;
      (* move this virtual page to the back of the replacement queue *)
      RemoveNode( VirtualPage ) ;
      AddToRearOfQueue( VirtualPage ) ;
   END  MarkInUse ;

PROCEDURE ReleasePage(     VirtualAddr : VirtualAddrType;
                       VAR RealAddress : ADDRESS ) ;
   VAR
      SegmentIndex, PageTableIndex : CARDINAL ;
      VirtualPage                  : PageTableEntryPtr ;
   BEGIN
      RealAddress := NIL ;
      (* was IsEqual( VirtNil, VirtualAddr ) -- now faster!! *)
      IF VirtNil.VAddr = VirtualAddr.VAddr THEN
         RETURN
      END ;
      SegmentIndex   := ORD( VirtualAddr.SEGMENTINDEX ) ;
      PageTableIndex := ORD( VirtualAddr.PAGETABLEINDEX ) ;
      IF (SegmentIndex > CurrentNoSegments) OR (PageTableIndex >= MaxPagesPerTable) THEN
         ProgramErrorAndHalt( 'Attempting to Release an invalid Virtual Page.');
      END ;
      WITH SegmentTable^[SegmentIndex]  DO
         VirtualPage := PageTableEntryPtr( ADR(PageTableAddr^[PageTableIndex]) ) ;
      END ;
      WITH VirtualPage^ DO
         (* mark the page as being used *)
         IF UsageCounter > 0 THEN
            DEC( UsageCounter )
         ELSIF UsageCounter < 0 THEN
            (* page is dirty, maintain "high" bit status *)
            INC( UsageCounter )
         ELSE
            ProgramErrorAndHalt( 'one too many ReleasePage calls.' ) ;
         END ;
      END ;
   END ReleasePage ;

PROCEDURE MarkDirty( VirtualAddr : VirtualAddrType ) ;
   VAR
      SegmentIndex, PageTableIndex : CARDINAL ;
      VirtualPage                  : PageTableEntryPtr ;
   BEGIN
      (* Convention:  UsageCounter = 0   -- clean and NOT in use
                      UsageCounter = -1  -- dirty and NOT in use
                      UsageCounter > 0   -- clean and in use
                      UsageCounter < -1  -- dirty and in use  *)

      SegmentIndex   := ORD( VirtualAddr.SEGMENTINDEX ) ;
      PageTableIndex := ORD( VirtualAddr.PAGETABLEINDEX ) ;
      WITH SegmentTable^[SegmentIndex]  DO
         VirtualPage := PageTableEntryPtr( ADR(PageTableAddr^[PageTableIndex]) ) ;
      END ;
      WITH VirtualPage^ DO
         IF UsageCounter >= 0 THEN
            UsageCounter := - UsageCounter - 1 ;
         END ;
      END ;

      (*<Debug
      IF DoTrace THEN
         TWriteString( 'MarkDirty VAddr = ' ) ;
         TWriteAddr( ADDRESS( VirtualAddr ) ) ;
         WriteVirt( VirtualPage ) ;
      END ;
      Debug>*)
   END MarkDirty ;

*)


PROCEDURE IsEqual( FirstVirtAddr, SecondVirtAddr : VirtualAddrType ) : BOOLEAN ;
   BEGIN
      RETURN (FirstVirtAddr.VAddr = SecondVirtAddr.VAddr) ;
   END IsEqual ;

(* m.s.
PROCEDURE HasRealMem( VirtualAddr : VirtualAddrType ) : BOOLEAN ;
   VAR
      SegmentIndex, PageTableIndex : CARDINAL ;
      VirtualPage                  : PageTableEntryPtr ;
   BEGIN
      SegmentIndex   := ORD( VirtualAddr.SEGMENTINDEX ) ;
      PageTableIndex := ORD( VirtualAddr.PAGETABLEINDEX ) ;
      WITH SegmentTable^[SegmentIndex]  DO
         VirtualPage := PageTableEntryPtr( ADR(PageTableAddr^[PageTableIndex]) ) ;
      END ;
      RETURN VirtualPage^.RealAddr <> NIL
   END HasRealMem ;
*)

PROCEDURE InitSpaceType( VAR SpaceType : VirtualAddrType ) ;
   BEGIN
      SpaceType.OFFSET := VirtualPageSize + 1 ;
   END InitSpaceType ;


PROCEDURE EndVirtualMemory ;
   VAR
      I, J  :  CARDINAL ;
     QueueNode  : PageTableEntryPtr ;
      UnReleasedPages : CARDINAL ;
   BEGIN
      (* Check for any unreleased virtual page *)
(* m.s.      QueueNode := Queue.Front ;
      UnReleasedPages := 0 ;
      WHILE QueueNode <> NIL DO
         IF (QueueNode^.UsageCounter <> 0) AND (QueueNode^.UsageCounter <> -1) THEN
            INC( UnReleasedPages )
         END ;
         QueueNode := QueueNode^.QueueBackward ;
      END ;
      IF UnReleasedPages > 0 THEN
         MesPos := 0 ;
         SWriteString( Message, MesPos, 'VirtualMemory: there are ', 0 ) ;
         SWriteCard( Message, MesPos, UnReleasedPages, 0 ) ;
         SWriteString( Message, MesPos, ' un-released virtual pages.', 0 ) ;
         ProgramErrorAndHalt( Message ) ;
      END ;

      (* get rid of temporary virtual memory file *)
      FIO.Close( VirtualIOFile ) ;
      CheckIOResult ;
      FIO.Erase( VirtualIOFileName ) ;
      CheckIOResult ;

(* ------- not really needed since end of program !!!
      (* Now release memory *)
      IF CurrentNoSegments > 0 THEN
         FOR I := 0 TO CurrentNoSegments-1 DO
            FOR J := 0 TO MaxPagesPerTable-1 DO
               WITH SegmentTable^[I].PageTableAddr^[J] DO
                  IF RealAddr <> NIL THEN
                     DEALLOCATE( RealAddr, VirtualPageSize ) ;
                  END ;
               END ;
            END ;
            (* now the page table itself *)
            DEALLOCATE( SegmentTable^[I].PageTableAddr, TSIZE(PageTable) ) ;
         END ;
      END ; (* IF CurrentNoSegments > 0 THEN *)
      (* now last Page table -- maybe partially filled *)
      FOR J := 0 TO CurrentNoPageTableEntries DO
          WITH SegmentTable^[CurrentNoSegments].PageTableAddr^[J] DO
             IF RealAddr <> NIL THEN
                DEALLOCATE( RealAddr, VirtualPageSize ) ;
             END ;
          END ;
      END ;
      (* now the page table itself and the segment table *)
      DEALLOCATE( SegmentTable^[CurrentNoSegments].PageTableAddr, TSIZE(PageTable) ) ;
      DEALLOCATE( SegmentTable, TSIZE(SegmentTableType) ) ;
-------------- *)
*)
   END EndVirtualMemory ;

(* m.s.
(* The following are for thrashing count/performance check *)
PROCEDURE GetNoOfPageFualts() : LONGINT  ;
   BEGIN
      RETURN NoPageOut ;
   END GetNoOfPageFualts ;

PROCEDURE GetNoOfPageReferences() : LONGINT  ;
   BEGIN
      RETURN NoOfPageReferences ;
   END GetNoOfPageReferences ;


PROCEDURE GetNoOfSwapPages() : LONGINT  ;
   BEGIN
      RETURN VAL( LONGINT, CurrentReadPos ) ;
   END GetNoOfSwapPages ;

*)
PROCEDURE GetAmtOfPageFrag() : LONGINT  ;
   BEGIN
      RETURN TotalPageFragmentation ;
   END GetAmtOfPageFrag ;

(* m.s.
PROCEDURE GetHexPageTableEntry(     VirtualAddr : VirtualAddrType;
                                VAR PageTableEntryHexRep : ARRAY OF CHAR ) ;
   VAR
      SegmentIndex, PageTableIndex : CARDINAL ;
      VirtualPage                  : PageTableEntryPtr ;
      Pos                          : CARDINAL ;
      TempParts                    : AddressParts;
      OK                           : BOOLEAN;
   BEGIN
      SegmentIndex   := ORD( VirtualAddr.SEGMENTINDEX ) ;
      PageTableIndex := ORD( VirtualAddr.PAGETABLEINDEX ) ;
      WITH SegmentTable^[SegmentIndex]  DO
         VirtualPage := PageTableEntryPtr( ADR(PageTableAddr^[PageTableIndex]) ) ;
      END ;
      TempParts := AddressParts(VirtualPage) ;
      Pos := 0 ;
      Str.CardToStr(LONGCARD(TempParts.SEGMENT), HexRep,16,OK);
      SWriteString( PageTableEntryHexRep, Pos, HexRep, 5 ) ;
      Str.CardToStr(LONGCARD(TempParts.OFFSET), HexRep,16,OK);
      SWriteString( PageTableEntryHexRep, Pos, HexRep, 5 ) ;
   END GetHexPageTableEntry ;

PROCEDURE GetDumpVirtPage(     VirtualAddr   : VirtualAddrType;
                           VAR VirtPage : VirtPageStorePtr ) ;
   BEGIN
      VirtualAddr.OFFSET := 0 ; (* always return from start of virtual page *)
      MakeReal( VirtualAddr, VirtPage ) ;
   END GetDumpVirtPage ;

PROCEDURE FinishEMS;
   BEGIN
	LIM.DeAllocatePages(EMSInfoHandle);
	LIM.DeAllocatePages(EMSDataHandle);
   END FinishEMS;

PROCEDURE SetupEMS ;
   VAR
	Rslt	: ARRAY[0..10] OF CHAR;
	OK	: BOOLEAN;
	NoAvailPages : CARDINAL;
   BEGIN
	EMSAvailable := FALSE;

	IF NOT LIM.LIMPresent THEN EMSAvailable := FALSE
	ELSE EMSAvailable := LIM.GetStatus() = 0;
	END;
	Utils.GetEnv('TACTEMS',Rslt);
	IF Rslt[0] = 0C THEN
	   IF NOT EMSAvailable THEN RETURN END;
	   NoAvailPages := LIM.FreePages();
	ELSE
	   NoAvailPages := VAL(CARDINAL,Str.StrToCard(Rslt, 10,OK)) DIV 16;
	   IF NOT OK THEN
		(*RES OLD MSG 141
		Current value %0 for Environment Variable TACTEMS should be a number
		(size in K). No EMS memory will be used.
		*)
		MsgString(Rslt, 0);
		PutResWarning( (*RES REM INS*) 141 );
		NoAvailPages := 0;
	   END;
	   IF (NOT EMSAvailable) AND (NoAvailPages <> 0) THEN
		(*RES OLD MSG 350
		EMS memory is not available on your computer and will not be used
		during this TACT session.
		*)
		MsgString(Rslt, 0);
		PutResWarning( (*RES REM INS*) 350 );
		RETURN
	   END;
	END;
	EMSAvailable := NoAvailPages > MinNumberEMSPages;
	IF NOT EMSAvailable THEN  RETURN  END;

	EMSInfoHandle := LIM.AllocatePages(1);
	EMSInfo := [LIM.GetPageFrame() : LIM.MapPage(0, 0, EMSInfoHandle)];
	Lib.Fill( EMSInfo, MAX(CARDINAL), 377C ) ; 	(* <--- just for debugging *)
	EMSInfo^.NoEMSPagesInUse := 0;

	DEC(NoAvailPages);
	IF NoAvailPages > MaxNoEMSPages THEN NoAvailPages := MaxNoEMSPages END;
	EMSInfo^.NoEMSPagesAvail := NoAvailPages * NoPagesPerFrame ;

	EMSDataHandle := LIM.AllocatePages(NoAvailPages);
	LRUCount := 0 ;

	Utils.InstallTermProc(FinishEMS);
    END SetupEMS;
*)

PROCEDURE InitVirtualMemory ;
   VAR
      I : CARDINAL ;
   BEGIN
      CurrentReadPos := 0 ;
      CurrentNoSegments := 0 ;
      CurrentNoPageTableEntries := 0 ;
      SegmentTable := NIL ;
(* m.s.      Queue.Front  := NIL ;
      Queue.Rear   := NIL ;
      NoPageIn     := VAL(LONGINT, 0) ;
      NoPageOut    := VAL(LONGINT, 0) ;
*)      NoOfPageReferences := VAL(LONGINT, 0) ;
      TotalPageFragmentation := VAL(LONGINT, 0) ;
      I := MaxSegmentsPerTable * TSIZE(SegmentTableType) ; (* <--- debug *)
      IF Available( MaxSegmentsPerTable * TSIZE(SegmentTableType) ) THEN
         ALLOCATE( SegmentTable, MaxSegmentsPerTable * TSIZE(SegmentTableType) ) ;
         FOR I := 0 TO MaxSegmentsPerTable-1 DO
             SegmentTable^[I].PageTableAddr := NIL ;
         END ;
      ELSE
         ProgramErrorAndHalt( 'Insufficient memory for SegmentTable at InitVirtualMemory.' ) ;
      END ;
      IF Available( MinSpaceRequired ) THEN
         CreateNewPageTable( SegmentTable^[CurrentNoSegments].PageTableAddr ) ;
      ELSE
         ProgramErrorAndHalt( 'Insufficient memory for PageTable at InitVirtualMemory.' ) ;
      END ;
(* m.s.      (* get rid of temporary Virtual IO File, if any *)
      Str.Concat( VirtualIOFileName, FileData.TempDiskArea, VIOFileName ) ;
      VirtualIOFile := FIO.Create( VirtualIOFileName) ;
      CheckIOResult ;
      SetupEMS ;
*)
   END InitVirtualMemory ;

BEGIN  (* VirtualMemory *)
   (* DoTrace := TRUE ;  <<<< just this once for stats <<< *)
END VirtualMemory .
