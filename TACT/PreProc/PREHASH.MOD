IMPLEMENTATION MODULE  PreHash ;

(* copyright (c) 1991-96 Ian Lancashire, Mike Stairs, University of Toronto *)

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
Title:    Virtual Hashing - to improve Word find
Author:   Lidio Presutti
*)

(* Revised for Dictionary access for Ian Lancashire's research project
Author : Mike Stairs *)

FROM VirtualMemory IMPORT
  (* Type  *) VirtualAddrType,
  (* Const *) VirtualPageSize, VirtNil,
  (* Procs *) IsEqual, AllocateSpace, MakeReal, (* m.s. ReleasePage, MarkDirty, *)
		InitSpaceType (* m.s. HasRealMem *) ;

FROM Str       IMPORT Length, Compare, Copy ;

FROM TokenDataSource IMPORT TypeNumber ;

(* FROM BalancedTrees IMPORT BTDataPtr ; (* for debugging only *) *)

(* FROM ErrorBase IMPORT ProgramErrorAndHalt ; *)

FROM SYSTEM IMPORT ADDRESS ;

IMPORT IO ;

FROM Utils IMPORT BCreate, BClose, WrStr, WrLn, BFile;


VAR
  I : CARDINAL ;
  VHashSpaceType : VirtualAddrType ;
  LongSegSize	 : LONGINT ;  (* = constant of LongInt form of SegmentSize *)

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
     Current, Previous	: WordPtr ; (* for scanning down old chain *)
     LastOfNew		: WordPtr ; (* points to last element in new chain *)
     VLastOfNew, VPrevious,
     VCurrent		: VirtualAddrType ;
  BEGIN
     WITH T DO
	(* reached maximum size of address space ? *)
	IF VAL(LONGINT, MaxP + p) < VAL(LONGINT, DirectorySize) * VAL(LONGINT, SegmentSize) THEN
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
	      MakeReal( VNewSegment, NewSegment ) ;
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
(* m.s.                 IF LastOfNew <> NIL THEN
                    ReleasePage( VLastOfNew, LastOfNew ) ;
                 END ;
*)
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
	   ReleasePage( VNewSegment, NewSegment ) ;
	   ReleasePage( VOldSegment, OldSegment ) ;
*)
	ELSE
	   IO.WrStr( 'VirtHash: Hash table full.' ) ;
	   IO.WrLn ;
        END ;
     END ;
  END ExpandTable ;

(*
PROCEDURE OldInsertHash( HashId : LONGINT ;
		      CurrentWord : ARRAY OF CHAR ;
		      Type : BOOLEAN ) ;
  VAR
     Word    :   WordPtr ;
     SegIndex	: CARDINAL ;
     CurrentSeg : SegmentPtr ;
     VCurrentSeg, VWord : VirtualAddrType ;

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
     AllocateSpace( VWord,  Word, VWordUnusedSpace, WordTypeSize ) ;
     Copy( Word^.Key, CurrentWord ) ;
     Word^.Type := Type ;
     Word^.Next := CurrentSeg^[ SegIndex ] ;
     CurrentSeg^[ SegIndex ] := VWord ;
     MarkDirty( VCurrentSeg ) ;
     ReleasePage( VCurrentSeg, CurrentSeg ) ;
     ReleasePage( VWord, Word ) ;
     WITH T DO
        INC( KeyCount ) ;
        IF KeyCount * 2  > CurrentSize  * 3 (* MaxLoadFactor=1.5 *) THEN
	   (*    IF KeyCount  > CurrentSize * MaxLoadFactor THEN *)
           (* expand when KeyCount / CurrentSize > MaxLoadFactor *)
           ExpandTable( T ) ;
        END ;
     END ;
  END OldInsertHash ;
*)

PROCEDURE InsertHash( CurrentWord : ARRAY OF CHAR ;
		      Type : BOOLEAN ) ;
  VAR
     Word    :   WordPtr ;
     SegIndex	: CARDINAL ;
     CurrentSeg : SegmentPtr ;
     VCurrentSeg, VTempPtr, VWord : VirtualAddrType ;
     HashId      : LONGINT ;
  BEGIN
     HashId	 := Hash( CurrentWord, T ) ;
     IF T.CurrentSize = 0 THEN (* get first set of "buckets" *)
        AllocateSpace(T.Directory[0], CurrentSeg, VHashSpaceType, VirtualPageSize ) ;
        FOR I := 0 TO SegmentSize - 1 DO
	    CurrentSeg^[I] := VirtNil ;
        END ;
        INC( T.CurrentSize ) ;
     END ;

     VCurrentSeg := T.Directory[ VAL( CARDINAL, HashId DIV LongSegSize ) ] ;
     SegIndex	 := VAL(CARDINAL, HashId MOD LongSegSize ) ;
     MakeReal( VCurrentSeg, CurrentSeg ) ;
     VWord := CurrentSeg^[ SegIndex ] ;
     WHILE NOT IsEqual( VWord, VirtNil ) DO
        MakeReal( VWord, Word ) ;
        IF (Compare( CurrentWord, Word^.Key ) = 0) THEN
(* m.s.	   ReleasePage( VWord, Word ) ;
	   ReleasePage( VCurrentSeg, CurrentSeg ) ;
*)
           RETURN ;
        END ;
        VTempPtr := Word^.Next ;
(* m.s.        ReleasePage( VWord, Word ) ; *)
        VWord := VTempPtr  ;
     END ;
     (* not found *)
     AllocateSpace( VWord,  Word, VWordUnusedSpace, WordTypeSize ) ;
     Copy( Word^.Key, CurrentWord ) ;
     Word^.Type := Type ;
     Word^.Next := CurrentSeg^[ SegIndex ] ;
     INC( TypeNumber ) ;
     CurrentSeg^[ SegIndex ] := VWord ;
(* m.s.     MarkDirty( VCurrentSeg ) ;
     ReleasePage( VCurrentSeg, CurrentSeg ) ;
     ReleasePage( VWord, Word ) ;
*)
     WITH T DO
        INC( KeyCount ) ;
        IF KeyCount * 2  > CurrentSize  * 3 (* MaxLoadFactor=1.5 *) THEN
	   (*    IF KeyCount  > CurrentSize * MaxLoadFactor THEN *)
           (* expand when KeyCount / CurrentSize > MaxLoadFactor *)
           ExpandTable( T ) ;
        END ;
     END ;
  END InsertHash ;

PROCEDURE SearchHashTable(     Key : ARRAY OF CHAR ;
			   VAR HashId : LONGINT ) : BOOLEAN ;
  VAR
     SegIndex	: CARDINAL ;
     CurrentSeg : SegmentPtr ;
     VCurrentSeg : VirtualAddrType ;
     Word	: WordPtr ;
     VWord      : VirtualAddrType ;
     VTempPtr	: VirtualAddrType ;

  BEGIN
     HashId	 := Hash( Key, T ) ;
     IF T.CurrentSize = 0 THEN
	RETURN FALSE
     END ;
     VCurrentSeg := T.Directory[ VAL( CARDINAL, HashId DIV LongSegSize ) ] ;
     SegIndex	 := VAL(CARDINAL, HashId MOD LongSegSize ) ;
     MakeReal( VCurrentSeg, CurrentSeg ) ;
     VWord := CurrentSeg^[ SegIndex ] ;
     WHILE NOT IsEqual( VWord, VirtNil ) DO
        MakeReal( VWord, Word ) ;
        IF (Compare( Key, Word^.Key ) = 0) THEN
(* m.s.	   ReleasePage( VWord, Word ) ;
	   ReleasePage( VCurrentSeg, CurrentSeg ) ;
*)
           RETURN TRUE ;
        END ;
        VTempPtr := Word^.Next ;
(* m.s.        ReleasePage( VWord, Word ) ; *)
        VWord := VTempPtr  ;
     END ;
     (* not found *)
(* m.s.     ReleasePage( VCurrentSeg, CurrentSeg ) ; *)
     RETURN FALSE ;
  END SearchHashTable ;

PROCEDURE FreeHashMemory ;
  VAR
     I		: CARDINAL ;
     DummyReal	: ADDRESS ;
  BEGIN
(*     WITH T DO
	FOR I := 0 TO DirectorySize - 1 DO
	    IF NOT IsEqual( Directory[I], VirtNil ) AND HasRealMem(Directory[I]) THEN
		ReleasePage( Directory[I], DummyReal )
	    END ;
	END ;
     END ;
*)
  END FreeHashMemory ;

PROCEDURE InitVirtHash;

VAR
     NewSegment		: SegmentPtr ;
     I, J               : CARDINAL ;

BEGIN
  InitSpaceType( VHashSpaceType ) ;
  LongSegSize := VAL( LONGINT, SegmentSize ) ;
  WITH T DO
	MaxP := SegmentSize ; (*  N * 2**L, L = 0  -- # of times table has doubled *)
        p := 0 ;
	KeyCount := 0 ;
	CurrentSize := 0 ;
	MaxLoadFactor := 2 ; (* average chain length *)
        FOR I := 0 TO DirectorySize -1 DO
           Directory[I] := VirtNil ;
        END ;
(*
             AllocateSpace( Directory[I], NewSegment, VHashSpaceType, VirtualPageSize ) ;
	     FOR J := 0 TO SegmentSize - 1 DO
	       NewSegment^[J] := VirtNil ;
             END ;
       END ;
*)
  END ;
END InitVirtHash;


PROCEDURE DumpHash( OutFile : BFile ) ;

VAR
     I, J               : CARDINAL ;
     Result             : CARDINAL;
     BugOut             : BFile ;
     VCurSeg, VTempPtr, VTempNextPtr : VirtualAddrType ;
     CurSeg : SegmentPtr ;
     Word : WordPtr ;
BEGIN

   FOR I := 0 TO DirectorySize -1 DO
       VCurSeg := T.Directory[I] ;
       IF NOT IsEqual( VCurSeg, VirtNil) THEN
         MakeReal( VCurSeg, CurSeg ) ;
         FOR J := 0 TO SegmentSize -1 DO
            VTempPtr := CurSeg^[J] ;
            WHILE NOT IsEqual( VTempPtr , VirtNil) DO
              MakeReal( VTempPtr, Word ) ;
              WrStr( OutFile, Word^.Key, Result ) ;
              WrLn( OutFile, Result ) ;
              VTempNextPtr := Word^.Next ;
(* m.s.              ReleasePage( VTempPtr, Word ) ; *)
            (*  DISPOSE( Sequence ) ;  (* reclaim memory from records as they are dumped to file *) *)
              VTempPtr := VTempNextPtr ;
           END ;
        END ;
(* m.s.        ReleasePage( VCurSeg, CurSeg ) ; *)
      END ; (* if *)
   END ;    (* for *)

 END DumpHash ;


END PreHash .
