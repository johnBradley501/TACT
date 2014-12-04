(* copyright (c) 1987-96 Jensen & Partners, International, Lidio Presutti, University of Toronto *)

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

(* >>>>  Special version to debug memory usage <<<< *LP*  *)

(*   $V-,S-,R-,I-*)
IMPLEMENTATION MODULE Storage;

(*V1=Production *)
(*V2=Trace *)

FROM SYSTEM IMPORT Seg,Ofs,Registers,HeapBase,EI,DI,GetFlags,SetFlags;
IMPORT Lib;
(*<Trace*)
FROM Trace IMPORT
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard, TWriteAddr;

VAR DoTrace : BOOLEAN ;  (* don't trigger other modules with Trace.DoTrace var! *)
(*Trace>*)

CONST
  EndMarker = 0FFFFH;
  ErrorMsg1 = 'Storage, Fatal error : Heap overflow';
  ErrorMsg2 = 'Storage, Fatal error : Corrupt heap';
  ErrorMsg3 = 'Storage, Fatal error : Invalid dispose';
  ErrorMsg4 = 'Storage, CheckHeap : Corrupt heap';
  ErrorMsg5 = 'Storage, ALLOC/DEALLOC : Low memory';
  ErrorMsg6 = 'Storage, Fatal error : Invalid pointer allocated';

VAR
  StartAddr : LONGCARD ;
  MaxHeapSpace : CARDINAL ;


PROCEDURE MakeHeap( Source : CARDINAL;     (* base segment of heap *)
                    Size   : CARDINAL      (* size in paragraphs *)
                    ) : HeapRecPtr;
VAR
  storage,first,last : HeapRecPtr;
  ie : CARDINAL;
BEGIN
  ie := GetFlags(); DI;
  storage := [Source:0];
  first   := [Source+1:0];
  last    := [Source+Size-1:0];
  storage^.next := first;
  storage^.size := 0;
  first^.next := last;
  last^.next  := storage;
  first^.size := Size-2;
  last^.size  := EndMarker;
  SetFlags(ie);
  RETURN storage;
END MakeHeap;

(*
 * Check if the heap is consistent (Debug)           *LP*
 * JPI Modula-2 specific
 *)
PROCEDURE CheckHeap() :BOOLEAN;
VAR
  p : HeapRecPtr;
  c : CARDINAL;
  CurHeapSpace : CARDINAL ;
BEGIN
  CurHeapSpace := HeapTotalAvail( MainHeap ) ;
  IF CurHeapSpace > MaxHeapSpace THEN
     Lib.FatalError(ErrorMsg4);
  END ;
  p := MainHeap^.next;
  FOR c := 1 TO 1000 DO				(* should be big enough!! *)
    IF p = NIL THEN RETURN FALSE END;		(* should be endless ring *)
    IF p = MainHeap THEN RETURN FALSE END;	(* no endmarker *)
    IF p^.size = 0FFFFH THEN RETURN TRUE END;	(* Found endmarker *)
    p := p^.next;
  END;
  RETURN FALSE;  (* endless junk *)
END CheckHeap;

PROCEDURE CheckAddr( a : ADDRESS ) : BOOLEAN ;	(* *LP* *)
   VAR  NormalizedAddr : LONGCARD ;
   BEGIN
	NormalizedAddr := LONGCARD( Seg( a^ ) ) * 16 + LONGCARD( Ofs( a^ ) ) ;
	RETURN (655360 > NormalizedAddr) AND (NormalizedAddr > StartAddr) ;
   END CheckAddr ;

PROCEDURE HeapAllocate(Source : HeapRecPtr; (* source heap                *)
                       VAR A  : ADDRESS;    (* result                     *)
                       Size   : CARDINAL);  (* request size in paragraphs *)

VAR
  res,prev,split : HeapRecPtr;
  ie : CARDINAL;
BEGIN
  ie := GetFlags(); DI;
  IF Size=0 THEN INC(Size) END ;
  prev := Source;
  WHILE prev^.next^.size < Size DO
    prev := prev^.next;
  END;
  res := prev^.next;
  IF res^.size = EndMarker THEN (* heap run out of space *)
    EI ;
    Lib.FatalError(ErrorMsg1);
  END;
  IF res^.size = Size THEN (* block correct size *)
    prev^.next := res^.next;
  ELSE (* split block, bottom half returned, top half linked to free chain *)
    split := [Seg(res^)+Size:0];
    prev^.next := split;
    split^.next := res^.next;
    split^.size := res^.size - Size;
  END;
  SetFlags( ie );
  A := ADR(res^);
END HeapAllocate;


PROCEDURE HeapAvail(Source: HeapRecPtr) : CARDINAL;
(* returns the largest block size available for allocation in paragraphs *)
VAR
  size : CARDINAL;
  p    : HeapRecPtr;
  ie   : CARDINAL;
BEGIN
  ie := GetFlags(); DI;
  p  := Source^.next;
  size := 0;
  WHILE p^.size <> EndMarker DO
    IF p^.size>size THEN size := p^.size END;
    p := p^.next;
  END;
  SetFlags(ie);
  RETURN size;
END HeapAvail;


PROCEDURE HeapTotalAvail(Source: HeapRecPtr) : CARDINAL;
(* returns the total block size available for allocation in paragraphs *)
VAR
  size : CARDINAL;
  p    : HeapRecPtr;
  ie   : CARDINAL;
BEGIN
  ie := GetFlags(); DI;
  p  := Source^.next;
  size := 0;
  WHILE p^.size <> EndMarker DO
    INC(size,p^.size);
    p := p^.next;
  END;
  SetFlags(ie);
  RETURN size;
END HeapTotalAvail;


PROCEDURE HeapDeallocate(Source : HeapRecPtr;  (* source heap         *)
                         VAR A  : ADDRESS;     (* block to deallocate *)
                         Size   : CARDINAL );  (* size of block
                                                  in paragraphs       *)
VAR
  target,prev,split : HeapRecPtr;
  tseg : CARDINAL;
  ie   : CARDINAL;
BEGIN
  IF (Seg(A^)=0)OR(Ofs(A^)<>0) THEN Lib.FatalError(ErrorMsg3) END;
  ie := GetFlags(); DI;
  IF Size=0 THEN INC(Size) END ;
  target := A;
  prev   := Source;
  tseg   := Seg(target^);
  WHILE Seg(prev^.next^) < tseg DO
    prev := prev^.next;
  END;
  IF Seg(prev^)+prev^.size = tseg THEN (* amalgamate with prev *)
    prev^.size := prev^.size + Size;
    target := prev;
  ELSIF Seg(prev^)+prev^.size > tseg THEN (* Heap corrupt *)
    EI ;
    Lib.FatalError(ErrorMsg2);
  ELSE
    (* link after prev *)
    target^.next := prev^.next;
    prev^.next := target;
    target^.size := Size;
  END;
  IF (target^.next^.size <> EndMarker)
     AND (Seg(target^.next^) = Seg(target^)+target^.size) THEN
    (* amalgamate with next block *)
    target^.size := target^.size+target^.next^.size;
    target^.next := target^.next^.next;
  END;
  A := NIL;
  SetFlags(ie);
END HeapDeallocate;


PROCEDURE HeapChangeAlloc(Source  : HeapRecPtr;  (* source heap       *)
                          A       : ADDRESS;     (* block to change   *)
                          OldSize,               (* old size of block *)
                          NewSize : CARDINAL)    (* new size of block *)
                                                 (* in paragraphs     *)
                          : BOOLEAN;             (* if sucessful      *)

(* This procedure attempts to change the size of an allocated block
   It returns TRUE if succeeded (only expansion can fail)
*)

VAR
  target,prev,
  split      : HeapRecPtr;
  tseg       : CARDINAL;
  result     : BOOLEAN;
  extendsize : CARDINAL;
  ie         : CARDINAL;
BEGIN
  IF (Seg(A^)=0)OR(Ofs(A^)<>0) THEN Lib.FatalError(ErrorMsg3) END;
  IF OldSize = NewSize THEN RETURN TRUE END;
  IF OldSize > NewSize THEN
    target := [Seg(A^)+NewSize:0];
    HeapDeallocate(Source,target,OldSize-NewSize);
    RETURN TRUE;
  END;
  extendsize := NewSize-OldSize;
  ie := GetFlags(); DI;
  target := A;
  prev := Source;
  tseg := Seg(target^);
  WHILE Seg(prev^.next^) < tseg DO
    prev := prev^.next;
  END;
  IF (prev^.next^.size <> EndMarker) AND
     (Seg(prev^.next^) = Seg(target^)+OldSize) AND
     (extendsize <= prev^.next^.size) THEN
    IF (extendsize = prev^.next^.size) THEN
      prev^.next := prev^.next^.next
    ELSE
      split := [Seg(target^)+NewSize:0];
      split^.next := prev^.next^.next;
      split^.size := prev^.next^.size - extendsize;
      prev^.next  := split;
    END;
    result := TRUE;
  ELSE
    result := FALSE;
  END;
  SetFlags(ie);
  RETURN result;
END HeapChangeAlloc;



PROCEDURE HeapChangeSize(Source  : HeapRecPtr;   (* source heap       *)
                         VAR A   : ADDRESS;      (* block to change   *)
                         OldSize,                (* old size of block *)
                         NewSize : CARDINAL );   (* new size of block
                                                       in paragraphs  *)

(*
   This procedure will change the size of an allocated block
   avoiding any copy of data if possible
   calls HeapChangeAlloc
*)

VAR
  na : ADDRESS;
BEGIN
  IF NOT HeapChangeAlloc ( Source, A, OldSize, NewSize ) THEN
    HeapAllocate(Source,na,NewSize);
    Lib.WordMove(A,na,OldSize*8);
    HeapDeallocate(Source,A,OldSize);
    A := na;
  END;
END HeapChangeSize;

PROCEDURE ALLOCATE(VAR a: ADDRESS; size: CARDINAL);
VAR ps : CARDINAL;
BEGIN
  IF size>0FFF0H THEN ps := 1000H
  ELSE                ps := (size+15) DIV 16;
  END ;
  IF NOT CheckHeap() THEN    (* *LP* *)
     Lib.FatalError(ErrorMsg4);
  END ;

  HeapAllocate(MainHeap,a,ps);

    (*<Trace
    IF DoTrace THEN
	TWriteLn ;	(* flush out previous line if needed *)
	(* INC( AllocCallNo ) ; *)
	TWriteAddr( a ) ;
	TWriteCard( size, 5 ) ;
	TWriteString( ' A' ) ;
	(* TWriteCard( AllocCallNo, 6 ) ; *)
	TWriteLn ;
    END ;
    Trace>*)

  IF NOT CheckAddr( a ) THEN		(* *LP* *)
     Lib.FatalError(ErrorMsg5);
  END ;
  IF (Seg(a^)=0)OR(Ofs(a^)<>0) THEN Lib.FatalError(ErrorMsg6) END;
  IF ClearOnAllocate THEN Lib.WordFill( a,ps*8,0); END;
END ALLOCATE;


PROCEDURE DEALLOCATE(VAR a: ADDRESS; size: CARDINAL);
VAR
  ps : CARDINAL ;
BEGIN
  IF size>0FFF0H THEN ps := 1000H
  ELSE                ps := (size+15) DIV 16;
  END ;

  IF NOT CheckHeap() THEN		(* *LP* *)
     Lib.FatalError(ErrorMsg4);
  END ;
  IF NOT CheckAddr( a ) THEN		(* *LP* *)
     Lib.FatalError(ErrorMsg5);
  END ;
    (*<Trace
    IF DoTrace THEN
	TWriteLn ;	(* flush out previous line if needed *)
	(* INC( DeallocCallNo ) ; *)
	TWriteAddr( a ) ;
	TWriteCard( size, 5 ) ;
	TWriteString( ' D' ) ;
	(* TWriteCard( DeallocCallNo, 6 ) ; *)
	TWriteLn ;
    END ;
    Trace>*)

  IF ClearOnAllocate THEN Lib.WordFill(a,ps*8,0); END;  (* *LP* *)
  HeapDeallocate(MainHeap,a,ps);
END DEALLOCATE;


PROCEDURE Available(size: CARDINAL) : BOOLEAN;
VAR
  ps : CARDINAL ;
BEGIN
  IF size=0 THEN          ps := 1
  ELSIF size>0FFF0H THEN  ps := 1000H
  ELSE                    ps := (size+15) DIV 16;
  END ;
  RETURN ps <= Storage.HeapAvail(Storage.MainHeap);
END Available;


PROCEDURE HEAPINIT();
VAR
  sseg   : CARDINAL;
BEGIN
  ClearOnAllocate := TRUE  (* was: FALSE *) ;
  (*  StartAddr := [HeapBase:0] ;  (* for test to see if alloc/release mem below legal addr *) *)
  StartAddr := LONGCARD(HeapBase) * 16 ;
  MainHeap := MakeHeap(HeapBase,CARDINAL([Lib.PSP:2]^)-HeapBase);
  MaxHeapSpace := HeapTotalAvail( MainHeap ) ;
END HEAPINIT;


BEGIN
  HEAPINIT;
  (*<Trace  DoTrace := TRUE ;  Trace>*)
END Storage.

