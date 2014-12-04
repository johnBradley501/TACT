IMPLEMENTATION MODULE  VirtHash ;

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

(*
Title:    Virtual Hashing - to improve Word find with Balanced Tree
LastEdit: June 1, 1988
Author:   Lidio Presutti

-- requires overflow to be turned off within the Hash function  j.b.
*)

(*V1=Production *)
(*V2=Debug *)
(*V3=JPI *)

FROM VirtualMemory IMPORT
  (* Type  *) VirtualAddrType,
  (* Const *) VirtualPageSize, VirtNil,
  (* Procs *) IsEqual, AllocateSpace, MakeReal, (* m.s. ReleasePage, MarkDirty, *)
		InitSpaceType (* m.s. HasRealMem *) ;

FROM BalancedTrees IMPORT
  (* Types *) BTDataPtr ;

FROM Str       IMPORT Length, Compare ;
FROM ErrorBase IMPORT ProgramErrorAndHalt ;
FROM SYSTEM IMPORT ADDRESS ;

(*<Debug
FROM GlobalDefs IMPORT
  (* Types *) StrAny ;
FROM Utils IMPORT
  (* Procs *) PrintHex ;
FROM WordBase IMPORT 
  (* Procs *) SortToIntWord ;
FROM Trace IMPORT
  (* Vars  *) DoTrace,
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard, TWriteAddr;
Debug>*)

CONST
  SegmentSize = 1024 ;     (* VirtualPageSize div TSIZE(VirtualAddrType) *)
  DirectorySize = 64 ;

TYPE
  Segment = ARRAY[0..SegmentSize-1] OF VirtualAddrType (* BTDataPtr *) ;
  SegmentPtr = POINTER TO Segment ;
  HashTable = RECORD
		p 		: CARDINAL ;	(* next bucket to split *)
		MaxP 		: CARDINAL ;	(* Upper bound on p during this expansion *)
		KeyCount 	: CARDINAL ;	(* number of records in table *)
		CurrentSize 	: CARDINAL ;	(* current number of buckets  *)
		MaxLoadFactor 	: CARDINAL ;	(* upper bound on load factor *)
		Directory	: ARRAY[0..DirectorySize-1] OF VirtualAddrType ;
	    END ;

VAR
  T : HashTable ;
  I : CARDINAL ;
  VHashSpaceType : VirtualAddrType ;
  LongSegSize	 : LONGINT ;  (* = constant of LongInt form of SegmentSize *)

      (*<Debug
      MaxSearch		: CARDINAL ;
      SearchCount	: CARDINAL ;
      FreqSearch	: CARDINAL ;
      TempMsg           : StrAny ;
      Debug>*)

PROCEDURE Hash( K : ARRAY OF CHAR ;
		T : HashTable ) : LONGINT ;
  CONST
     Prime = 1048583 ;
  VAR
     h, addr	: LONGINT ;
     I		: CARDINAL ;
     ConvertedKey : LONGINT ;
  BEGIN
     ConvertedKey := VAL( LONGINT, 0 ) ;
(*<JPI *)  (*$O-*) (*JPI>*)
     FOR I := 0 TO Length( K ) DO
        ConvertedKey := VAL(LONGINT,7) * ConvertedKey + VAL(LONGINT, ORD(K[I]) ) ;
     END ;
(*<JPI *) (*$O=*) (*JPI>*)
     h := ABS( ConvertedKey ) MOD Prime ;
     addr := h MOD VAL(LONGINT,T.MaxP) ;
     IF addr < VAL(LONGINT,T.p) THEN
     	addr := h MOD VAL(LONGINT,2 * T.MaxP) ;
     END ;
     RETURN addr ;
  END Hash ;
 
PROCEDURE ExpandTable( VAR T : HashTable ) ;
  VAR
     NewAddress,
     NewSegmentIndex,
     OldSegmentIndex 	: CARDINAL ;
     VOldSegment,
     VNewSegment	: VirtualAddrType ;
     OldSegment,
     NewSegment		: SegmentPtr ;
     Current, Previous	: BTDataPtr ; (* for scanning down old chain *)
     LastOfNew		: BTDataPtr ; (* points to last element in new chain *)
     VLastOfNew, VPrevious,
     VCurrent		: VirtualAddrType ;
  BEGIN
     WITH T DO
	(* reached maximum size of address space ? *)
	IF VAL(LONGINT, MaxP + p) < VAL(LONGINT, DirectorySize) * VAL(LONGINT, SegmentSize) THEN

	(*<Debug 
	IF DoTrace THEN
	   TWriteString( 'ExpandTable (begins):' ) ;
	   TWriteLn ;
	END ;
	Debug>*)

	   (* locate bucket to be split *)
	   VOldSegment := Directory[ p DIV SegmentSize ] ;
	   MakeReal( VOldSegment, OldSegment ) ;
	   OldSegmentIndex := p MOD SegmentSize ;

	   (* expand address space, if necessary create a new segment *)
	   NewAddress := MaxP + p ;
	   IF NewAddress MOD SegmentSize = 0 THEN
	      AllocateSpace( Directory[NewAddress DIV SegmentSize], NewSegment, VHashSpaceType, VirtualPageSize ) ;
	      VNewSegment := Directory[ NewAddress DIV SegmentSize ] ;
	      FOR I := 0 TO SegmentSize - 1 DO
		 NewSegment^[I] := VirtNil ;
	      END ;
	   ELSE
	      VNewSegment := Directory[ NewAddress DIV SegmentSize ] ;
	      MakeReal( VNewSegment, NewSegment )
	   END ;
	   NewSegmentIndex := NewAddress MOD SegmentSize ;

	   (* Adjust the state variables *)
	   INC( p ) ;
	   IF p = MaxP THEN
	      MaxP := 2 * MaxP ;
	      p := 0 ;
	   END ;
	   INC( CurrentSize ) ;

	   (* Relocate records to the new bucket *)
	   Previous  := NIL ;
	   VLastOfNew := VirtNil ;
	   LastOfNew  := NIL ;
	   
	   (*<Debug
	   IF DoTrace THEN
		VCurrent := OldSegment^[OldSegmentIndex] ;
		VPrevious := VirtNil ;
		TWriteString( 'ExpandTable: before split: MaxP = ' ) ;
		TWriteCard( T.MaxP, 4 ) ;
 		TWriteString( ' p = ' ) ;
		TWriteCard( T.p, 4 ) ;
 		TWriteString( ' KeyCount = ' ) ;
		TWriteCard( T.KeyCount, 4 ) ;
 		TWriteString( ' CurrentSize = ' ) ;
		TWriteCard( T.CurrentSize, 4 ) ;
		TWriteLn ;
 		TWriteString( 'Old bucket:' ) ;
		TWriteCard( OldSegmentIndex, 4 ) ;
 		TWriteString( ';  MaxSearch = ' ) ;
		TWriteCard( MaxSearch, 2 ) ;
 		TWriteString( ' FreqSearch = ' ) ;
		TWriteCard( FreqSearch, 2 ) ;
		TWriteLn ;
		WHILE NOT IsEqual( VCurrent, VirtNil ) DO
			MakeReal( VCurrent, Current ) ;
			TWriteString( '  Current = ' ) ;
			TWriteAddr( ADDRESS(VCurrent) ) ;
			TWriteString( ' Next = ' ) ;
			TWriteAddr( ADDRESS(Current^.Next) ) ;
			TWriteString( '  Key = "' ) ;
			SortToIntWord( Current^.Key, TempMsg ) ;
			(* PrintHex( Current^.Key, TempMsg ) ; *)
			TWriteString( TempMsg ) ;
			TWriteString( '"' ) ;
			TWriteLn ;
			VPrevious := Current^.Next ;
			ReleasePage( VCurrent, Current ) ;
			VCurrent := VPrevious ;
		END ;
	   END ;
	   Debug>*)
	   
	   VCurrent := OldSegment^[OldSegmentIndex] ;
	   VPrevious := VirtNil ;
	   WHILE NOT IsEqual(VCurrent, VirtNil) DO
	      MakeReal( VCurrent, Current ) ;
	      IF Hash( Current^.Key, T ) = VAL(LONGINT,NewAddress) THEN
	         (* attach it to end of the new chain *)
	         IF LastOfNew = NIL THEN
		    NewSegment^[NewSegmentIndex] := VCurrent ;
(* m.s.		    MarkDirty( VNewSegment ) ; *)
		 ELSE
		    LastOfNew^.Next := VCurrent ;
(* m.s.                    MarkDirty( VLastOfNew ) ; *)
		 END ;
		 IF Previous = NIL THEN
		    OldSegment^[OldSegmentIndex] := Current^.Next ;
(* m.s.		    MarkDirty( VOldSegment ) ; *)
		 ELSE
		    Previous^.Next := Current^.Next ;
(* m.s.                    MarkDirty( VPrevious ) ; *)
		 END ;
                 IF LastOfNew <> NIL THEN
(* m.s.                    ReleasePage( VLastOfNew, LastOfNew ) ; *)
                 END ;
		 LastOfNew  := Current ;
		 VLastOfNew := VCurrent ;
		 VCurrent   := Current^.Next ;
		 LastOfNew^.Next := VirtNil ;
(* m.s.                 MarkDirty( VLastOfNew ) ; *)
	      ELSE
		 (* leave it on the old chain *)
(* m.s.                 IF Previous <> NIL THEN
                    ReleasePage( VPrevious, Previous ) ;
                 END ;
*)
		 VPrevious := VCurrent ;
		 Previous  := Current ;
		 VCurrent  := Current^.Next ;
	      END ;
	   END ;
(* m.s.           IF LastOfNew <> NIL THEN
              ReleasePage( VLastOfNew, LastOfNew ) ;
           END ;
           IF Previous <> NIL THEN
              ReleasePage( VPrevious, Previous ) ;
           END ;
*)
	   (*<Debug
	   IF DoTrace THEN
		VCurrent := OldSegment^[OldSegmentIndex] ;
		VPrevious := VirtNil ;
		TWriteString( '' ) ;
		TWriteLn ;
 		TWriteString( 'Old bucket after split:' ) ;
		TWriteCard( OldSegmentIndex, 4 ) ;
		TWriteLn ;
		WHILE NOT IsEqual( VCurrent, VirtNil ) DO
			MakeReal( VCurrent, Current ) ;
			TWriteString( '  Current = ' ) ;
			TWriteAddr( ADDRESS(VCurrent) ) ;
			TWriteString( ' Next = ' ) ;
			TWriteAddr( ADDRESS(Current^.Next) ) ;
			TWriteString( '  Key = "' ) ;
			SortToIntWord( Current^.Key, TempMsg ) ;
			(* PrintHex( Current^.Key, TempMsg ) ; *)
			TWriteString( TempMsg ) ;
			TWriteString( '"' ) ;
			TWriteLn ;
			VPrevious := Current^.Next ;
			ReleasePage( VCurrent, Current ) ;
			VCurrent := VPrevious ;
		END ;
		VCurrent := NewSegment^[NewSegmentIndex] ;
		VPrevious := VirtNil ;
 		TWriteString( 'New bucket:' ) ;
		TWriteCard( NewSegmentIndex, 4 ) ;
		TWriteLn ;
		WHILE NOT IsEqual( VCurrent, VirtNil ) DO
			MakeReal( VCurrent, Current ) ;
			TWriteString( '  Current = ' ) ;
			TWriteAddr( ADDRESS(VCurrent) ) ;
			TWriteString( ' Next = ' ) ;
			TWriteAddr( ADDRESS(Current^.Next) ) ;
			TWriteString( '  Key = "' ) ;
			SortToIntWord( Current^.Key, TempMsg ) ;
			(* PrintHex( Current^.Key, TempMsg ) ; *)
			TWriteString( TempMsg ) ;
			TWriteString( '"' ) ;
			TWriteLn ;
			VPrevious := Current^.Next ;
			ReleasePage( VCurrent, Current ) ;
			VCurrent := VPrevious ;
		END ;
	   END ;
	   Debug>*)

	(*<Debug 
	IF DoTrace THEN
	   TWriteString( 'ExpandTable (ends):' ) ;
	   TWriteLn ;
	END ;
	Debug>*)

(* m.s.	   ReleasePage( VNewSegment, NewSegment ) ;
	   ReleasePage( VOldSegment, OldSegment ) ;
*)
	ELSE
	   ProgramErrorAndHalt( 'VirtHash: Hash table full.' ) ;
        END ;
     END ;
  END ExpandTable ;   
           
PROCEDURE InsertHash( HashId : LONGINT ;
		      VBTnode : VirtualAddrType ) ;
  VAR
     SegIndex	: CARDINAL ;
     CurrentSeg : SegmentPtr ;
     VCurrentSeg : VirtualAddrType ;
     BTnode	: BTDataPtr ;
     (*<Debug
     VPrevious,
     VCurrent	: VirtualAddrType ;
     Current	: BTDataPtr ;
     Debug>*)
  BEGIN
     IF T.CurrentSize = 0 THEN (* get first set of "buckets" *)
        AllocateSpace(T.Directory[0], CurrentSeg, VHashSpaceType, VirtualPageSize ) ;
        FOR I := 0 TO SegmentSize - 1 DO
	    CurrentSeg^[I] := VirtNil ;
        END ;
        INC( T.CurrentSize ) ;
     END ;
     VCurrentSeg := T.Directory[ VAL(CARDINAL, HashId DIV LongSegSize) ] ;
     SegIndex	 := VAL(CARDINAL, HashId MOD LongSegSize) ;
     MakeReal( VCurrentSeg, CurrentSeg ) ;
     MakeReal( VBTnode, BTnode ) ;
     BTnode^.Next := CurrentSeg^[ SegIndex ] ;

     (*<Debug
     IF DoTrace THEN
	TWriteString( 'InsertHash: Key = "' ) ;
	SortToIntWord( BTnode^.Key, TempMsg ) ;
	TWriteString( TempMsg ) ;
	TWriteString( '" SegIndex = ' ) ;
	TWriteCard( SegIndex, 4 ) ;
	TWriteString( ' BTnode = ' ) ;
	TWriteAddr( ADDRESS(VBTnode) ) ;
	TWriteLn ;
     END ;
     Debug>*)
     
     CurrentSeg^[ SegIndex ] := VBTnode ;
(* m.s.     MarkDirty( VBTnode ) ;
     MarkDirty( VCurrentSeg ) ;
     ReleasePage( VBTnode, BTnode ) ;
     ReleasePage( VCurrentSeg, CurrentSeg ) ;
*)
	(*<Debug
	IF DoTrace THEN
		VCurrent := VBTnode ;
		VPrevious := VirtNil ;
		WHILE NOT IsEqual( VCurrent, VirtNil ) DO
			MakeReal( VCurrent, Current ) ;
			TWriteString( '  Current = ' ) ;
			TWriteAddr( ADDRESS(VCurrent) ) ;
			TWriteString( ' Next = ' ) ;
			TWriteAddr( ADDRESS(Current^.Next) ) ;
			TWriteString( '  Key = "' ) ;
			SortToIntWord( Current^.Key, TempMsg ) ;
			(* PrintHex( Current^.Key, TempMsg ) ; *)
			TWriteString( TempMsg ) ;
			TWriteString( '"') ;
			TWriteLn ;
			VPrevious := Current^.Next ;
			ReleasePage( VCurrent, Current ) ;
			VCurrent := VPrevious ;
		END ;
	   END ;
	Debug>*)

     WITH T DO
        INC( KeyCount ) ;
        IF KeyCount * 2  > CurrentSize * 3 (* MaxLoadFactor=1.5 *) THEN
	   (*    IF KeyCount  > CurrentSize * MaxLoadFactor THEN *)
           (* expand when KeyCount / CurrentSize > MaxLoadFactor *)
           ExpandTable( T ) ;
        END ;
     END ;
  END InsertHash ;

PROCEDURE SearchHashTable(     Key : ARRAY OF CHAR ;
			   VAR VThisType : VirtualAddrType ;
			   VAR HashId : LONGINT ) : BOOLEAN ;
  VAR
     SegIndex	: CARDINAL ;
     CurrentSeg : SegmentPtr ;
     VCurrentSeg : VirtualAddrType ;
     BTnode	: BTDataPtr ;
     VBTnode	: VirtualAddrType ;
     VTempPtr	: VirtualAddrType ;
     
  BEGIN
     VThisType   := VirtNil ;
     HashId	 := Hash( Key, T ) ;
     IF T.CurrentSize = 0 THEN
	RETURN FALSE
     END ;
     VCurrentSeg := T.Directory[ VAL( CARDINAL, HashId DIV LongSegSize ) ] ;
     SegIndex	 := VAL(CARDINAL, HashId MOD LongSegSize ) ;
     
     (*<Debug 
        SearchCount := 0 ;
	IF DoTrace THEN
	   TWriteString( 'HashSearch (begins):  Key = "' ) ;
	   SortToIntWord( Key, TempMsg ) ;
	   TWriteString( TempMsg ) ;
	   TWriteString( '"  HashId = ' ) ;
	   TWriteCard( VAL(CARDINAL,HashId), 6 ) ;
	   TWriteLn ;
	END ;
     Debug>*)

     MakeReal( VCurrentSeg, CurrentSeg ) ;
     VBTnode := CurrentSeg^[ SegIndex ] ;
     WHILE NOT IsEqual( VBTnode, VirtNil ) DO
        MakeReal( VBTnode, BTnode ) ;
        IF Compare( Key, BTnode^.Key ) = 0 THEN
	   (*<Debug
	   IF SearchCount > MaxSearch THEN
	      MaxSearch := SearchCount ;
	      FreqSearch := 1 ;
	   ELSIF SearchCount = MaxSearch THEN
	      INC( FreqSearch ) 
	   END ;
	   IF DoTrace THEN
	      TWriteString( 'HashSearch (Ends - found):  Key = "' ) ;
	      SortToIntWord( Key, TempMsg ) ;
	      TWriteString( TempMsg ) ;
	      TWriteString( '"' ) ;
	      TWriteLn ;
	   END ;
	   Debug>*)
	   
           VThisType := BTnode^.Data ;
(* m.s.	   ReleasePage( VBTnode, BTnode ) ;
	   ReleasePage( VCurrentSeg, CurrentSeg ) ;
*)
           RETURN TRUE ;
        END ;
        VTempPtr := BTnode^.Next ;
(* m.s.        ReleasePage( VBTnode, BTnode ) ; *)
        VBTnode := VTempPtr  ;
	(*<Debug INC( SearchCount ) ; Debug>*)
     END ;
     (*<Debug
	IF SearchCount > MaxSearch THEN
	   MaxSearch := SearchCount ;
	   FreqSearch := 1 ;
	ELSIF SearchCount = MaxSearch THEN
	   INC( FreqSearch ) 
	END ;

	IF DoTrace THEN
	   TWriteString( 'HashSearch (Ends - Not found):  Key = "' ) ;
	   SortToIntWord( Key, TempMsg ) ;
	   TWriteString( TempMsg ) ;
	   TWriteString( '"' ) ;
	   TWriteLn ;
	END ;
     Debug>*)
     
     (* not found *)
(* m.s.     ReleasePage( VCurrentSeg, CurrentSeg ) ; *)
     RETURN FALSE ;
  END SearchHashTable ;

PROCEDURE FreeHashMemory ;
  VAR
     I		: CARDINAL ;
     DummyReal	: ADDRESS ;
  BEGIN
(* m.s. - replace this if necessary...    WITH T DO
	FOR I := 0 TO DirectorySize - 1 DO
	    IF NOT IsEqual( Directory[I], VirtNil )  AND HasRealMem(Directory[I]) THEN
		ReleasePage( Directory[I], DummyReal )
	    END ;
	END ;
     END ;
*)
  END FreeHashMemory ;

PROCEDURE InitVirtHash;
BEGIN
  (*<Debug
  MaxSearch := 0 ;
  FreqSearch := 0 ;
  Debug>*)
  
  InitSpaceType( VHashSpaceType ) ;
  LongSegSize := VAL( LONGINT, SegmentSize ) ;
  WITH T DO
	p := 0 ;
	MaxP := SegmentSize ; (*  N * 2**L, L = 0  -- # of times table has doubled *)
	KeyCount := 0 ;
	CurrentSize := 0 ;
	MaxLoadFactor := 2 ; (* average chain length *)
	FOR I := 0 TO DirectorySize - 1 DO
		Directory[I] := VirtNil ;
	END ;
  END ;
END InitVirtHash;
END VirtHash .
