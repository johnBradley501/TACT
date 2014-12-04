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

  ---------------------------------------------------------------------------*)

CONST
   MaxPagesPerTable = 256 ;     (*  2**8 bits *)
   MaxSegmentsPerTable = 256 ;  (*  2**8 bits *)
(* VirtualPageSize = 4096 ;     (*  2**12 = 4 K *) <--- now in .DEF file *)
   MinSpaceRequired = VirtualPageSize + 4096 ; (* leave 8K for M2 ??? *)
   MaxINTEGER = MAX(INTEGER) ;

TYPE
   AddressParts = RECORD
       OFFSET:     CARDINAL;
       SEGMENT:    CARDINAL;
   END;
   PageTableEntryPtr = POINTER TO PageTableEntry ;
   PageTableEntry = RECORD
                       CASE : BOOLEAN OF
                          TRUE : RealAddr : ADDRESS ; |  (* = NIL when paged out  *)
                          FALSE: RealPage : VirtPageStorePtr ; (* for easier viewing in RTD *)
                       END ;
                    END ;
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


VAR
   SegmentTable              : SegmentTableType ;
   CurrentReadPos            : CARDINAL ;
   CurrentNoSegments         : CARDINAL ;
   CurrentNoPageTableEntries : CARDINAL ;
   Message                   : StrAny ;
   NoOfPageReferences        : LONGINT ;
   TotalPageFragmentation    : LONGINT ;  (* unusable space in pages *)


PROCEDURE MakeReal(     VirtualAddr : VirtualAddrType;
                    VAR RealAddress : ADDRESS ) ;
   VAR
      RAParts	: AddressParts;
      SegmentIndex, PageTableIndex : CARDINAL ;
      VirtualPage: PageTableEntryPtr ;
   BEGIN
      SegmentIndex   := ORD( VirtualAddr.SEGMENTINDEX ) ;
      PageTableIndex := ORD( VirtualAddr.PAGETABLEINDEX ) ;
      IF (SegmentIndex > CurrentNoSegments) OR (PageTableIndex >= MaxPagesPerTable) THEN
         ProgramErrorAndHalt( 'Attempting to MakeReal an invalid Virtual Page.');
      END ;
      WITH SegmentTable^[SegmentIndex]  DO
         VirtualPage := PageTableEntryPtr( ADR(PageTableAddr^[PageTableIndex]) ) ;
      END ;
      WITH VirtualPage^ DO
         IF RealAddr = NIL THEN
             (* error now, all entries should have real addresses *)
             ProgramErrorAndHalt(' Attempting to MakeReal a null pointer.') ;
         END ; (* if *)
         RAParts := AddressParts(RealAddr);
         INC( RAParts.OFFSET, VirtualAddr.OFFSET );
         RealAddress := ADDRESS(RAParts);
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
      END ;
      (* initialize new page table *)
      FOR I := 0 TO MaxPagesPerTable - 1 DO
          WITH PageTableAddr^[ I ] DO
             RealAddr      := NIL ;
          END ;
      END ;
      CurrentNoPageTableEntries := 0 ;
   END CreateNewPageTable ;

PROCEDURE AllocatePage( VAR VirtualAddr : VirtualAddrType;
                        VAR RealAddress : ADDRESS ) ;
   VAR
      VirtualPage       : PageTableEntryPtr ;
   BEGIN
      (* check if we have room in "book" keeping tables *)
      IF CurrentNoPageTableEntries >= MaxPagesPerTable THEN
         INC( CurrentNoSegments ) ;
         IF CurrentNoSegments >= MaxSegmentsPerTable THEN
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
         END ;
         RealAddress := RealAddr ;
         Lib.Fill( RealAddress, VirtualPageSize, 0377C );
         INC( NoOfPageReferences ) ;
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
         SpaceType := VirtAddr ;
      ELSE
         VirtAddr := SpaceType ;
         MakeReal( VirtAddr, RealAddress ) ;
      END ;
      INC( SpaceType.OFFSET, Size ) ; (* next avail. offset *)
   END AllocateSpace ;


PROCEDURE IsEqual( FirstVirtAddr, SecondVirtAddr : VirtualAddrType ) : BOOLEAN ;
   BEGIN
      RETURN (FirstVirtAddr.VAddr = SecondVirtAddr.VAddr) ;
   END IsEqual ;


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
   END EndVirtualMemory ;

PROCEDURE GetAmtOfPageFrag() : LONGINT  ;
   BEGIN
      RETURN TotalPageFragmentation ;
   END GetAmtOfPageFrag ;


PROCEDURE InitVirtualMemory ;
   VAR
      I : CARDINAL ;
   BEGIN
      CurrentReadPos := 0 ;
      CurrentNoSegments := 0 ;
      CurrentNoPageTableEntries := 0 ;
      SegmentTable := NIL ;
      NoOfPageReferences := VAL(LONGINT, 0) ;
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
   END InitVirtualMemory ;

BEGIN  (* VirtualMemory *)
   (* DoTrace := TRUE ;  <<<< just this once for stats <<< *)
END VirtualMemory .
