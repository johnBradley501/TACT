IMPLEMENTATION MODULE  VirtHash ;

(* copyright (c) 1987-96 Lidio Presutti, Mike Stairs, University of Toronto *)

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
  (* Procs *) IsEqual, AllocateSpace, MakeReal, (* ms ReleasePage, MarkDirty, *)
		InitSpaceType(* ms , HasRealMem *) ;

FROM Str       IMPORT Length, Compare, Copy, ItemS, Pos, Concat, Append ;

FROM StartUp   IMPORT FileData, Spaces, RuleFileID ;

FROM SYSTEM IMPORT ADDRESS ;

FROM RUNSource IMPORT NoMaximalPhrases, NoRules ;

(* FROM Storage IMPORT ALLOCATE, Available, DEALLOCATE ; *)

(*<Trace IMPORT Trace ; Trace>*)

FROM Storage IMPORT  Available, ALLOCATE, DEALLOCATE (* m.s. , MainHeap, HeapAvail, HeapTotalAvail *) ;

FROM ErrorBase IMPORT ProgramErrorAndHalt;

FROM Translations IMPORT XFileType, XWrStr, XWrLn, XWriteLine ;

IMPORT FIO ;

FROM WordBase IMPORT SortToIntWord ;

FROM Utils IMPORT BCreate, BClose, WrStr, WrLn, BFile;

FROM StringIO IMPORT SWriteString, SWriteChar, SWriteCard, SWriteLongInt ;

FROM ResMessages IMPORT
   (* proc *)  MsgString, MsgCard, PutResError, PutResWarning, ResAskUser, GetResMessage;

FROM UtilsTwo IMPORT IOErrorMessage;

CONST
  SegmentSize = 1024 ;     (* VirtualPageSize div TSIZE(VirtualAddrType) *)
  DirectorySize = 64 ;
  FileHeaderResource = 113 ;	(* >> MSG defined in MAKBAS: SetupFil.MOD << *)

TYPE
  Segment = ARRAY[0..SegmentSize-1] OF VirtualAddrType (* DictDataPtr *) ;
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
  RuleID : CARDINAL ;

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
     FOR I := 0 TO (Length( K ) - 1) DO
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
     OldSegmentIndex , 	DirEntry : CARDINAL ;
     VOldSegment,
     VNewSegment	: VirtualAddrType ;
     OldSegment,
     NewSegment		: SegmentPtr ;
     Current, Previous	: SequencePtr ; (* for scanning down old chain *)
     LastOfNew		: SequencePtr ; (* points to last element in new chain *)
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
           DirEntry := NewAddress DIV SegmentSize ;
	   IF NewAddress MOD SegmentSize = 0 THEN
	      AllocateSpace( Directory[ DirEntry ], NewSegment, VHashSpaceType, VirtualPageSize ) ;
	      VNewSegment := Directory[ DirEntry ];
	      FOR I := 0 TO SegmentSize - 1 DO
		 NewSegment^[I] := VirtNil ;
	      END ;
	   ELSE
	      VNewSegment := Directory[ DirEntry ] ;
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
	
	   VCurrent := OldSegment^[OldSegmentIndex] ;
	   VPrevious := VirtNil ;
	   WHILE NOT IsEqual(VCurrent, VirtNil) DO
	      MakeReal( VCurrent, Current ) ;
	      IF Hash( Current^.Key, T ) = VAL(LONGINT,NewAddress) THEN
	         (* attach it to end of the new chain *)
	         IF LastOfNew = NIL THEN
		    NewSegment^[NewSegmentIndex] := VCurrent ;
(*		    MarkDirty( VNewSegment ) ; *)
		 ELSE
		    LastOfNew^.Next := VCurrent ;
(*                    MarkDirty( VLastOfNew ) ; *)
		 END ;
		 IF Previous = NIL THEN
		    OldSegment^[OldSegmentIndex] := Current^.Next ;
(*		    MarkDirty( VOldSegment ) ; *)
		 ELSE
		    Previous^.Next := Current^.Next ;
(*                    MarkDirty( VPrevious ) ; *)
		 END ;
(*                 IF LastOfNew <> NIL THEN
                    ReleasePage( VLastOfNew, LastOfNew ) ;
                 END ;
*)		 LastOfNew  := Current ;
		 VLastOfNew := VCurrent ;
		 VCurrent   := Current^.Next ;
		 LastOfNew^.Next := VirtNil ;
(*                 MarkDirty( VLastOfNew ) ; *)
	      ELSE
		 (* leave it on the old chain *)
(*                 IF Previous <> NIL THEN
                    ReleasePage( VPrevious, Previous ) ;
                 END ;
*)		 VPrevious := VCurrent ;
		 Previous  := Current ;
		 VCurrent  := Current^.Next ;
	      END ;
	   END ;
(*           IF LastOfNew <> NIL THEN
              ReleasePage( VLastOfNew, LastOfNew ) ;
           END ;
           IF Previous <> NIL THEN
              ReleasePage( VPrevious, Previous ) ;
           END ;
	   ReleasePage( VNewSegment, NewSegment ) ;
	   ReleasePage( VOldSegment, OldSegment ) ;
*)
	ELSE
	   ProgramErrorAndHalt( 'VirtHash: Hash table full.' ) ;
        END ;
     END ;
  END ExpandTable ;


PROCEDURE InsertHash( HashId : LONGINT ;
                      Sequence   : SequencePtr ) ;
  VAR
     SegIndex	: CARDINAL ;
     CurrentSeg : SegmentPtr ;
     TempSequence : SequencePtr ;
     VCurrentSeg, VSequence : VirtualAddrType ;

  BEGIN
     IF T.CurrentSize = 0 THEN (* get first set of "buckets" *)
        AllocateSpace(T.Directory[0], CurrentSeg, VHashSpaceType, VirtualPageSize ) ;
        FOR I := 0 TO SegmentSize - 1 DO
	    CurrentSeg^[I] := VirtNil ;
        END ;
        INC( T.CurrentSize ) ;
(*        ReleasePage( T.Directory[0], CurrentSeg ) ; *)
     END ;
     VCurrentSeg := T.Directory[ VAL(CARDINAL, HashId DIV LongSegSize) ] ;
     SegIndex	 := VAL(CARDINAL, HashId MOD LongSegSize) ;
     MakeReal( VCurrentSeg, CurrentSeg ) ;
     Sequence^.Next := CurrentSeg^[ SegIndex ] ;
     AllocateSpace( VSequence,  TempSequence, VSequenceUnusedSpace, SequenceSize ) ;
     CurrentSeg^[ SegIndex ] := VSequence ;
(*     MarkDirty( VCurrentSeg ) ; *)
     TempSequence^ := Sequence^ ;
(*     ReleasePage( VSequence, TempSequence ) ;
     ReleasePage( VCurrentSeg, CurrentSeg ) ;
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


PROCEDURE SearchHashTable(     Sequence : SequencePtr ;
			   VAR HashId : LONGINT ) ;
(* this procedure now checks for subsequences already present in the hash table
   that should be removed since they occur the same number of times as the
   longer sequence, if they are found they are removed. InsertHash is called
   regardless. *)
  VAR
     SegIndex	: CARDINAL ;
     CurrentSeg : SegmentPtr ;
     VCurrentSeg : VirtualAddrType ;
     CurSequence, PrevSequence    : SequencePtr ;
     VCurSequence	: VirtualAddrType ;
     VTempPtr	: VirtualAddrType ;
     VPrevSequence   : VirtualAddrType ;
     TempStr, Key   : StrAny ;
     I, J, K      : CARDINAL ;

  BEGIN
     Copy ( TempStr, Sequence^.Text ) ;
     K := 0 ;
     IF T.CurrentSize <> 0 THEN
         FOR I := 1 TO  (Sequence^.NoWords - FileData.SpanMin) DO (* skip first word *)
           ItemS( Key , Sequence^.Text, ' ', I ) ;
           HashId	 := Hash( Key, T ) ;
           VCurrentSeg := T.Directory[ VAL( CARDINAL, HashId DIV LongSegSize ) ] ;
           SegIndex	 := VAL(CARDINAL, HashId MOD LongSegSize ) ;
           MakeReal( VCurrentSeg, CurrentSeg ) ;
           VCurSequence := CurrentSeg^[ SegIndex ] ;
           VPrevSequence  := VirtNil ;
           WHILE NOT IsEqual( VCurSequence, VirtNil ) DO
              MakeReal( VCurSequence, CurSequence ) ;
              IF Pos( Sequence^.Text, CurSequence^.Text ) < MAX(CARDINAL) THEN (* found  substring, remove substring from table *)
        	   IF VPrevSequence <> VirtNil THEN
      	              MakeReal( VPrevSequence, PrevSequence ) ;
      	              PrevSequence^.Next := CurSequence^.Next ;
(*                      MarkDirty( VPrevSequence ) ;
      	              ReleasePage( VPrevSequence, PrevSequence ) ;
 *)
      	           ELSE
      	              CurrentSeg^[ SegIndex ] := CurSequence^.Next ;
      	           END ;
 (*                  MarkDirty( VCurrentSeg ) ; *)
              ELSE
                   VPrevSequence  := VCurSequence ;
              END ;
              VTempPtr := CurSequence^.Next ;
(*              ReleasePage( VCurSequence, CurSequence ) ; *)
              VCurSequence := VTempPtr  ;
           END ;
(*           ReleasePage( VCurrentSeg, CurrentSeg ) ; *)
       END ; (* for *)
    END ; (* if *)
    HashId := Hash( Sequence^.Key , T ) ; (* set HashId for InsertHash *)
  END SearchHashTable ;


PROCEDURE FreeHashMemory ;
  VAR
     I		: CARDINAL ;
     DummyReal	: ADDRESS ;
  BEGIN
(*     WITH T DO
	FOR I := 0 TO DirectorySize - 1 DO
	    IF NOT IsEqual( Directory[I], VirtNil ) AND HasRealMem(Directory[I]) THEN
            	ReleasePage( Directory[I], DummyReal )  ;
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
  END ;
END InitVirtHash;




PROCEDURE DumpHash( OutFile : XFileType ) ;

VAR
     I, J, Len               : CARDINAL ;
     Result             : CARDINAL ;
     BugOut             : BFile ;
     VCurSeg, VTempPtr, VTempNextPtr : VirtualAddrType ;
     CurSeg : SegmentPtr ;
     Sequence : SequencePtr ;
     OK : BOOLEAN ;
     KeyWord : StrAny ;
BEGIN

   FOR I := 0 TO DirectorySize -1 DO
       VCurSeg := T.Directory[I] ;
       IF NOT IsEqual( VCurSeg, VirtNil) THEN
         MakeReal( VCurSeg, CurSeg ) ;
         FOR J := 0 TO SegmentSize -1 DO
            VTempPtr := CurSeg^[J] ;
            WHILE NOT IsEqual( VTempPtr , VirtNil) DO
              MakeReal( VTempPtr, Sequence ) ;
              FIO.WrCard( OutFile.ID.FileID , Sequence^.NoOccurs, 3 ) ;
              WrStr( OutFile.ID, '  ', Result ) ;
              IF FileData.GenRuleFile THEN
                 FOR I := 1 TO Sequence^.NoWords DO
                   FIO.WrCard( RuleFileID.ID.FileID, Sequence^.NoOccurs, -8 ) ;
                   FIO.WrCard( RuleFileID.ID.FileID, Sequence^.NoWords, -8 ) ;
                   FIO.WrCard( RuleFileID.ID.FileID, I, 0 ) ;
                   ItemS( KeyWord, Sequence^.Text, ' ', I - 1) ;
                   Concat( KeyWord, ' ', KeyWord ) ;
                   Append( KeyWord, ' ' ) ;
                   Append( KeyWord, Sequence^.Text ) ;
                   Len := XWrStr( RuleFileID, KeyWord , Result ) ;
                   XWrLn( RuleFileID, Result ) ;
                   INC( NoRules ) ;
                 END ;
              END ;
              Len := XWrStr( OutFile, Sequence^.Text, Result ) ;
              XWrLn( OutFile, Result ) ;
              INC( NoMaximalPhrases ) ;
              VTempNextPtr := Sequence^.Next ;
(*              ReleasePage( VTempPtr, Sequence ) ; *)
            (*  DISPOSE( Sequence ) ;  (* reclaim memory from records as they are dumped to file *) *)
              VTempPtr := VTempNextPtr ;
           END ;
        END ;
(*        ReleasePage( VCurSeg, CurSeg ) ; *)
      END ; (* if *)
   END ;    (* for *)

 END DumpHash ;

BEGIN
  RuleID := 0 ;
END VirtHash .
