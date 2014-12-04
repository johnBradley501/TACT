IMPLEMENTATION MODULE  SatHash ;

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
Title:    Virtual Hashing - to improve Word find
Author:   Lidio Presutti
*)

(* Revised for Dictionary access for Ian Lancashire's research project
Author : Mike Stairs *)

FROM VirtualMemory IMPORT
  (* Type  *) VirtualAddrType,
  (* Const *) VirtualPageSize, VirtNil,
  (* Procs *) IsEqual, AllocateSpace, MakeReal, (* ReleasePage, MarkDirty, *)
		InitSpaceType (* , HasRealMem *) ;

FROM Str       IMPORT Length, Compare, Copy, Append, Concat, CardToStr, Pos ;

(* FROM BalancedTrees IMPORT BTDataPtr ; (* for debugging only *) *)

(* FROM ErrorBase IMPORT ProgramErrorAndHalt ; *)

FROM SYSTEM IMPORT ADDRESS ;

IMPORT IO ;

FROM Utils IMPORT BCreate, BClose, WrStr, WrLn, BFile;

FROM StartUp IMPORT FileData ;

FROM ProcTextSource IMPORT NoWords ;

FROM RunPan IMPORT
  (* Procs *) PutRunStatus, PutPercentage ;



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
     Current, Previous	: DictPtr ; (* for scanning down old chain *)
     LastOfNew		: DictPtr ; (* points to last element in new chain *)
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
	      IF Hash( Current^.KEY, T ) = VAL(LONGINT,NewAddress) THEN
	         (* attach it to end of the new chain *)
	         IF LastOfNew = NIL THEN
		    NewSegment^[NewSegmentIndex] := VCurrent ;
(*		    MarkDirty( VNewSegment ) ; *)
		 ELSE
		    LastOfNew^.Next := VCurrent ;
(*                     MarkDirty( VLastOfNew ) ; *)
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
*)
		 LastOfNew  := Current ;
		 VLastOfNew := VCurrent ;
		 VCurrent   := Current^.Next ;
		 LastOfNew^.Next := VirtNil ;
(*                 MarkDirty( VLastOfNew ) ; *)
	      ELSE
		 (* leave it on the old chain *)
(*                 IF Previous <> NIL THEN
                    ReleasePage( VPrevious, Previous ) ;
                 END ;
*)
		 VPrevious := VCurrent ;
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
	   IO.WrStr( 'VirtHash: Hash table full.' ) ;
	   IO.WrLn ;
        END ;
     END ;
  END ExpandTable ;


PROCEDURE InsertHash( Key: ARRAY OF CHAR ;
                      POS: ARRAY OF CHAR ;
                      TAG: ARRAY OF CHAR ) ;
  VAR
     VDictNode : VirtualAddrType;
     HashId     : LONGINT ;
     SegIndex	: CARDINAL ;
     CurrentSeg : SegmentPtr ;
     DictNode : DictPtr  ;
     VCurrentSeg : VirtualAddrType ;
     VTempPtr	: VirtualAddrType ;
(*     ThisWordPosEntry : WordPosPtr ;
     VWordPos, VLastWordPos 	: VirtualAddrType ; *)

  BEGIN
     HashId	 := Hash( Key, T ) ;
     VCurrentSeg := T.Directory[ VAL(CARDINAL, HashId DIV LongSegSize) ] ;
     SegIndex	 := VAL(CARDINAL, HashId MOD LongSegSize) ;
     MakeReal( VCurrentSeg, CurrentSeg ) ;
     VDictNode := CurrentSeg^[ SegIndex ] ;
     WHILE NOT IsEqual( VDictNode, VirtNil ) DO
        MakeReal( VDictNode, DictNode ) ;
        IF (Compare( Key, DictNode^.KEY ) = 0) AND
           (Compare( POS, DictNode^.POS) = 0 )  AND
           (Compare( TAG, DictNode^.TAG) = 0) THEN
           INC( DictNode^.NoOccurs ) ;
(*           MarkDirty( VDictNode );
	   ReleasePage( VDictNode, DictNode ) ;
	   ReleasePage( VCurrentSeg, CurrentSeg ) ;
*)
           RETURN ;
        END ;
        VDictNode := DictNode^.Next ;
(*        ReleasePage( VDictNode, DictNode ) ;
        VDictNode := VTempPtr  ;
*)
     END ;
     (* not found *)
     INC( NoWords ) ;
     AllocateSpace( VDictNode , DictNode, VDataUnusedSpace, DictListSize ) ;
     DictNode^.Next := CurrentSeg^[ SegIndex ] ;
     Copy( DictNode^.KEY, Key ) ;
     Copy( DictNode^.TAG, TAG ) ;
     Copy( DictNode^.POS, POS ) ;
     DictNode^.NoOccurs := 1 ;
     CurrentSeg^[ SegIndex ] := VDictNode ;
(*     ReleasePage( VDictNode, DictNode ) ;
     MarkDirty( VCurrentSeg ) ;
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

PROCEDURE SearchHash( Key: ARRAY OF CHAR ;  POS: ARRAY OF CHAR ;
                      VAR NewPOS: ARRAY OF CHAR ):  BOOLEAN ;
  VAR
     VDictNode : VirtualAddrType;
     HashId     : LONGINT ;
     SegIndex	: CARDINAL ;
     CurrentSeg : SegmentPtr ;
     DictNode : DictPtr  ;
     VCurrentSeg : VirtualAddrType ;
     VTempPtr	: VirtualAddrType ;
     Result : BOOLEAN ;
  BEGIN
     HashId	 := Hash( Key, T ) ;
     Result := FALSE ;
     NewPOS[0] := 0C ;
     VCurrentSeg := T.Directory[ VAL(CARDINAL, HashId DIV LongSegSize) ] ;
     SegIndex	 := VAL(CARDINAL, HashId MOD LongSegSize) ;
     MakeReal( VCurrentSeg, CurrentSeg ) ;
     VDictNode := CurrentSeg^[ SegIndex ] ;
     WHILE NOT IsEqual( VDictNode, VirtNil ) DO
        MakeReal( VDictNode, DictNode ) ;
        IF (Compare( Key, DictNode^.KEY ) = 0) THEN
           IF Pos( POS, DictNode^.POS ) = MAX(CARDINAL ) THEN (* not found *)
              Append( NewPOS, DictNode^.POS ) ; (* add to list of POS *)
              Result := TRUE ;
           END ;
        END ;
        VTempPtr := DictNode^.Next ;
(*        ReleasePage( VDictNode, DictNode ) ; *)
        VDictNode := VTempPtr  ;
     END ;
     IF Result THEN Append( NewPOS, ',' ) ; END ;
(*     ReleasePage( VCurrentSeg, CurrentSeg ) ; *)
     RETURN Result ;
END SearchHash ;


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
        AllocateSpace( Directory[0], NewSegment, VHashSpaceType, VirtualPageSize ) ;
        FOR J := 0 TO SegmentSize - 1 DO
	       NewSegment^[J] := VirtNil ;
        END ;
        INC( T.CurrentSize ) ;
  END ;
END InitVirtHash;

PROCEDURE DumpHash ;
VAR
   P   : DictPtr ;
   OutLine, TempStr, TempWord : ARRAY [0..128] OF CHAR ;
   OK : BOOLEAN ;
   I, J, L, M               : CARDINAL ;
   K		      : INTEGER ;
   Result             : CARDINAL;
   VCurSeg, VTempPtr, VTempNextPtr : VirtualAddrType ;
   CurSeg : SegmentPtr ;
   OutFile: BFile ;
   LastPercentage, Percentage : CARDINAL ;
   Count : LONGCARD ;
BEGIN
   BCreate( OutFile, FileData.SATFileName, TRUE, Result ) ;
   LastPercentage := 0 ;
   Count := 0 ;
   FOR I := 0 TO DirectorySize -1 DO
       VCurSeg := T.Directory[I] ;
       IF NOT IsEqual( VCurSeg, VirtNil) THEN
         MakeReal( VCurSeg, CurSeg ) ;
         FOR J := 0 TO SegmentSize -1 DO
            VTempPtr := CurSeg^[J] ;
            WHILE NOT IsEqual( VTempPtr , VirtNil) DO
              MakeReal( VTempPtr, P ) ;
              INC(Count);
              Percentage := VAL (CARDINAL , (Count * 100) DIV NoWords) ;
              IF Percentage >= LastPercentage THEN
                IF Percentage >= 100 THEN
        	  Percentage := 99  ;	(* fake a reasonable value *)
                END ;
                PutPercentage( Percentage, TRUE ) ;
                LastPercentage := Percentage ;
              END ;
              INC( NoWords ) ;
              Copy( OutLine, '"' ) ;
              FOR L := 1 TO 3 DO
                IF FileData.OutputOrder.RAW = L THEN
                  Append( OutLine, P^.KEY ) ;
                  Append( OutLine, '","') ;
                ELSIF FileData.OutputOrder.POS = L THEN
                  Append( OutLine, P^.POS ) ;
                  Append( OutLine, '","') ;
                ELSIF FileData.OutputOrder.LEMMA = L THEN
                  Append( OutLine, P^.TAG );
                  Append( OutLine, '","') ;
                END ;
              END ;
              L := Length( OutLine) ;
              OutLine[ L -1 ] := 0C ;
              CardToStr( LONGCARD(P^.NoOccurs), TempStr, 10 , OK) ;
              Append( OutLine, TempStr ) ;
              WrStr( OutFile, OutLine, Result ) ;
              WrLn( OutFile, Result ) ;
              VTempNextPtr := P^.Next ;
(*              ReleasePage( VTempPtr, P ) ; *)
              VTempPtr := VTempNextPtr ;
           END ;
        END ;
(*        ReleasePage( VCurSeg, CurSeg ) ; *)
      END ;
   END ;
   BClose( OutFile, Result ) ;
END DumpHash ;


END SatHash .
