IMPLEMENTATION MODULE BalancedTrees;

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

(*V1=Production*)
(*V2=Debug*)

FROM SYSTEM  IMPORT TSIZE, ADDRESS ;
FROM Str     IMPORT
  (* Procs *)  Copy, Length, Compare;
FROM VirtualMemory IMPORT
  (* Type  *)  VirtualAddrType,
  (* Var   *)  VirtNil,
  (* Procs *)  AllocateSpace, MakeReal, (* m.s. ReleasePage, MarkDirty, *)
               IsEqual;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny ;

(*<Debug
FROM Utils IMPORT
  (* Procs *) PrintHex ;
FROM Trace IMPORT
  (* Vars  *) DoTrace,
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard, TWriteAddr;
Debug>*)


CONST
    (* BTDataSize = TSIZE(VirtualAddrType) * 4 + TSIZE(INTEGER) ;  *)
    BTDataSize = 18 ;

PROCEDURE MakeBTData(    KeyValue: ARRAY OF CHAR;
                         DataPntr: VirtualAddrType;
                     VAR SpaceType: VirtualAddrType;
                     VAR q: VirtualAddrType);
  VAR
      q1:     BTDataPtr;
  BEGIN (* MakeBTData *)
    AllocateSpace( q, q1, SpaceType, BTDataSize+Length(KeyValue)+1 ) ;
    WITH q1^ DO
         LLink := VirtNil;
         RLink := VirtNil;
         Copy( Key, KeyValue ) ;
         Data := DataPntr;
         B := 0;
         Next := VirtNil;  (* Hash chain *)
    END;
(* m.s.    ReleasePage(q,q1); *)
  END MakeBTData;

PROCEDURE InitialBT( VAR Header : BalTree; VAR SpaceType : VirtualAddrType );
    BEGIN
       MakeBTData( 0C, VirtNil, SpaceType, Header);
    END InitialBT;

PROCEDURE FindBTItem(  Header:      BalTree;
                       KeyValue:    ARRAY OF CHAR;
                   VAR DataPntr:    VirtualAddrType;
                   VAR p, s, t:     VirtualAddrType): BOOLEAN;
  VAR
      FoundIt: BOOLEAN;
      q:       VirtualAddrType;
      q1, p1:  BTDataPtr;
      CR:      INTEGER;

  BEGIN (* FindBTItem *)
    p := Header;
    t := p;
    MakeReal(p,p1);
    q := p1^.RLink;
    s := q;

    IF IsEqual(s,VirtNil) THEN
(* m.s.        ReleasePage(p,p1); *)
        RETURN FALSE
    ELSE
        MakeReal(q,q1);
(* m.s.        ReleasePage(p,p1); *)
        p := q;
        p1 := q1;
        FoundIt := FALSE;
        REPEAT
           CR := Compare(KeyValue,p1^.Key);
           IF CR = 0 THEN
              FoundIt := TRUE;
           ELSIF CR < 0 THEN
              q := p1^.LLink;
              IF NOT IsEqual(q,VirtNil) THEN
                  MakeReal(q,q1);
                  IF q1^.B <> 0 THEN
                     t := p;
                     s := q;
                  END;
(* m.s.                  ReleasePage(p,p1); *)
                  p := q;
                  p1 := q1;
              ELSE
(* m.s.                 ReleasePage(p,p1); *)
                 RETURN FALSE
              END;
           ELSE
              q := p1^.RLink;
              IF NOT IsEqual(q,VirtNil) THEN
                 MakeReal(q,q1);
                 IF q1^.B <> 0 THEN
                    t := p;
                    s := q;
                 END;
(* m.s.                 ReleasePage(p,p1); *)
                 p := q;
                 p1 := q1;
              ELSE
(* m.s.                 ReleasePage(p,p1); *)
                 RETURN FALSE;
              END;
           END;
       UNTIL FoundIt;
       DataPntr := p1^.Data;
(* m.s.       ReleasePage(p,p1); *)
       RETURN TRUE;
    END;
  END FindBTItem; (* FindBTItem *)

  (* This routine is the 'single rotation' discussed by Knuth     *)
  (* in his book 'The Art of Computer Programming' vol 3, pg      *)
  (* 457 and 454.                                                 *)

PROCEDURE SRot(VAR p:     VirtualAddrType;
                   r, s:  VirtualAddrType;
                   a:     INTEGER );

    VAR
      r1, s1: BTDataPtr;

  BEGIN
    p := r;
    MakeReal(r,r1);
(* m.s.    MarkDirty(r); *)
    MakeReal(s,s1);
(* m.s.    MarkDirty(s); *)
    s1^.B := 0;
    r1^.B := 0;
    IF a = 1 THEN
        s1^.RLink := r1^.LLink;
        r1^.LLink := s;
    ELSE
        s1^.LLink := r1^.RLink;
        r1^.RLink := s;
    END;
(* m.s.    ReleasePage(r,r1);
    ReleasePage(s,s1);
*)
  END SRot;


  (* This routine is the 'double rotation' discussed by Knuth    *)
  (* in his book 'The Art of Computer Programming  vol 3, pgs    *)
  (* 457 and 454.                                                *)

  PROCEDURE DRot(VAR p:    VirtualAddrType;
                     r, s: VirtualAddrType;
                     a:    INTEGER);

    VAR

      r1, s1, p1: BTDataPtr;

  BEGIN
    MakeReal(r,r1);
  (* m.s.  MarkDirty(r); *)
    MakeReal(s,s1);
(* m.s.    MarkDirty(s); *)
    IF a = (-1) THEN
       p := r1^.RLink;
       MakeReal(p,p1);
(* m.s.       MarkDirty(p); *)
       r1^.RLink := p1^.LLink;
       p1^.LLink := r; 
       s1^.LLink := p1^.RLink; 
       p1^.RLink := s; 
       s1^.B := 0; 
       r1^.B := 0; 
       IF p1^.B = (-1) THEN 
          s1^.B := 1
       END; 
       IF p1^.B = 1 THEN 
          r1^.B := (-1)
       END; 
       p1^.B := 0; 
    ELSE
       p := r1^.LLink; 
       MakeReal(p,p1);
(* m.s.       MarkDirty(p); *)
       r1^.LLink := p1^.RLink;
       p1^.RLink := r;
       s1^.RLink := p1^.LLink;
       p1^.LLink := s;
       s1^.B := 0;
       r1^.B := 0;
       IF p1^.B = 1 THEN
          s1^.B := (-1)
       END;
       IF p1^.B = (-1) THEN
          r1^.B := 1
       END;
       p1^.B := 0;
    END;
(* m.s.    ReleasePage(p,p1);
    ReleasePage(r,r1);
    ReleasePage(s,s1);
*)
  END DRot;

  PROCEDURE AddBTItem(Header:      BalTree;
                      KeyValue:    ARRAY OF CHAR;
                      DataPntr:    VirtualAddrType;
                  VAR SpaceType:   VirtualAddrType;
                  VAR p:           VirtualAddrType;
                      s, t:        VirtualAddrType);

   VAR
      pt, r, q:             VirtualAddrType;
      t1, r1, s1, p1, q1:   BTDataPtr;
      a:                    INTEGER;
      CR,CRs:               INTEGER;
      (*<Debug
      TempMsg             : StrAny ;
      Debug>*)

  BEGIN
    MakeBTData(KeyValue, DataPntr, SpaceType, q);
    MakeReal(p,p1);
(* m.s.    MarkDirty(p); *)

    (*<Debug
    IF DoTrace THEN
       TWriteString( 'AddBTItem: after MarkDirty: virt = ' ) ;
       TWriteAddr( ADDRESS( p ) ) ;
       TWriteString( '  real = ' ) ;
       TWriteAddr( p1 ) ;
       PrintHex( KeyValue, TempMsg ) ;
       TWriteString( '  KeyValue = ' ) ;
       TWriteString( TempMsg ) ;
       TWriteLn ;
    END ;
    Debug>*)

    IF IsEqual(p,Header) THEN
       p1^.RLink := q;
(* m.s.       ReleasePage(p,p1); *)
    ELSE
       CR := Compare(KeyValue,p1^.Key);
       IF CR < 0 THEN
          p1^.LLink := q
       ELSE
          p1^.RLink := q
       END;
(* m.s.       ReleasePage(p,p1); *)
(* a6:  *)
       MakeReal(s,s1);
       CRs := Compare(KeyValue,s1^.Key);
       IF CRs < 0 THEN
          r := s1^.LLink
       ELSE
          r := s1^.RLink
       END;
       p := r;
       WHILE NOT IsEqual(p,q) DO
          MakeReal(p,p1);
(* m.s.          MarkDirty(p); *)
          CR := Compare(KeyValue,p1^.Key);
          IF CR < 0 THEN
             p1^.B := (-1);
             pt := p1^.LLink;
(* m.s.             ReleasePage(p,p1); *)
             p := pt;
          ELSE
             p1^.B := 1;
             pt := p1^.RLink;
(* m.s.             ReleasePage(p,p1); *)
             p := pt;
          END;
       END;
(* a7:   *)
       IF CRs < 0 THEN
          a := -1
       ELSE
          a := 1
       END;
       IF s1^.B = 0 THEN
(* m.s.          MarkDirty(s); *)
          s1^.B := a
       ELSIF s1^.B = -a THEN
(* m.s.          MarkDirty(s); *)
          s1^.B := 0
       ELSE
          MakeReal(r,r1);
          IF r1^.B = a THEN
             SRot(p, r, s, a)
          ELSE
             DRot(p, r, s, a)
          END;
(* m.s.          ReleasePage(r,r1); *)

(*        MakeReal(s,s1);   No need to make s1 real again. J.B. 8/24/87
          MakeReal(p,p1);   I don't see why this is here! J.B. 8/24/87
          MarkDirty(p);   *)

          MakeReal(t,t1);
(* m.s.          MarkDirty(t); *)
          IF IsEqual(s,t1^.RLink) THEN
             t1^.RLink := p
          ELSE
             t1^.LLink := p
          END;
(* m.s.          ReleasePage(t,t1); *)
       END;
(* m.s.       ReleasePage(s,s1); *)
    END;
    p := q;

    (*<Debug
    IF DoTrace THEN
       TWriteString( 'AddBTItem: before exit : virt = ' ) ;
       TWriteAddr( ADDRESS( p ) ) ;
       PrintHex( KeyValue, TempMsg ) ;
       TWriteString( '  KeyValue = ' ) ;
       TWriteString( TempMsg ) ;
       TWriteLn ;
    END ;
    Debug>*)
  END AddBTItem;

(* MakeListItem -- allocates a binary tree node *)
PROCEDURE MakeListItem( VAR Header	: BalTree;
			    KeyValue	: ARRAY OF CHAR;
			    DataPntr	: VirtualAddrType;
			VAR SpaceType	: VirtualAddrType;
			VAR p		: VirtualAddrType ) ;
   VAR
	p1 : BTDataPtr;
   BEGIN
	AllocateSpace( p, p1, SpaceType, BTDataSize+Length(KeyValue)+1 ) ;
	WITH p1^ DO
	   LLink := Header;	(* form a link list -- reuse pointer later *)
	   RLink := VirtNil;
	   Copy( Key, KeyValue ) ;
	   Data := DataPntr;
	   B := 0;
	   Next := VirtNil;	(* Hash chain *)
	END;
	Header := p ;		(* becomes last item on chain *)
(* m.s.	ReleasePage(p,p1); *)
   END MakeListItem ;

(* AddListItem -- maintains a balanced binary tree for all Type words *)
PROCEDURE AddListItem(  Header	: BalTree; KeyValue : ARRAY OF CHAR ;
			q	: VirtualAddrType ;
		    VAR p	: VirtualAddrType ;
			s, t	: VirtualAddrType ) ;
   VAR
      pt, r:             VirtualAddrType;
      t1, r1, s1, p1:    BTDataPtr;
      a:                 INTEGER;
      CR,CRs:            INTEGER;
      (*<Debug
      TempMsg  : StrAny ;
      Debug>*)
   BEGIN
    MakeReal(p,p1);
(* m.s.    MarkDirty(p); *)

    (*<Debug
    IF DoTrace THEN
       TWriteString( 'AddBTItem: after MarkDirty: virt = ' ) ;
       TWriteAddr( ADDRESS( p ) ) ;
       TWriteString( '  real = ' ) ;
       TWriteAddr( p1 ) ;
       PrintHex( KeyValue, TempMsg ) ;
       TWriteString( '  KeyValue = ' ) ;
       TWriteString( TempMsg ) ;
       TWriteLn ;
    END ;
    Debug>*)

    IF IsEqual(p,Header) THEN
       p1^.RLink := q;
(* m.s.       ReleasePage(p,p1); *)
    ELSE
       CR := Compare(KeyValue,p1^.Key);
       IF CR < 0 THEN
          p1^.LLink := q
       ELSE
          p1^.RLink := q
       END;
(* m.s.       ReleasePage(p,p1); *)
(* a6:  *)
       MakeReal(s,s1);
       CRs := Compare(KeyValue,s1^.Key);
       IF CRs < 0 THEN
          r := s1^.LLink
       ELSE
          r := s1^.RLink
       END;
       p := r;
       WHILE NOT IsEqual(p,q) DO
          MakeReal(p,p1);
(* m.s.          MarkDirty(p); *)
          CR := Compare(KeyValue,p1^.Key);
          IF CR < 0 THEN
             p1^.B := (-1);
             pt := p1^.LLink;
(* m.s.             ReleasePage(p,p1); *)
             p := pt;
          ELSE
             p1^.B := 1;
             pt := p1^.RLink;
(* m.s.             ReleasePage(p,p1); *)
             p := pt;
          END;
       END;
(* a7:   *)
       IF CRs < 0 THEN
          a := -1
       ELSE
          a := 1
       END;
       IF s1^.B = 0 THEN
(* m.s.          MarkDirty(s); *)
          s1^.B := a
       ELSIF s1^.B = -a THEN
(* m.s.          MarkDirty(s); *)
          s1^.B := 0
       ELSE
          MakeReal(r,r1);
          IF r1^.B = a THEN
             SRot(p, r, s, a)
          ELSE
             DRot(p, r, s, a)
          END;
(* m.s.          ReleasePage(r,r1); *)
          MakeReal(t,t1);
(* m.s.          MarkDirty(t); *)
          IF IsEqual(s,t1^.RLink) THEN
             t1^.RLink := p
          ELSE
             t1^.LLink := p
          END;
(* m.s.          ReleasePage(t,t1); *)
       END;
(* m.s.       ReleasePage(s,s1); *)
    END;

    (*<Debug
    IF DoTrace THEN
       TWriteString( 'AddBTItem: before exit : virt = ' ) ;
       TWriteAddr( ADDRESS( p ) ) ;
       PrintHex( KeyValue, TempMsg ) ;
       TWriteString( '  KeyValue = ' ) ;
       TWriteString( TempMsg ) ;
       TWriteLn ;
    END ;
    Debug>*)
   END AddListItem ;

  PROCEDURE ProcessBT(Header:   BalTree;
                      DoItem:   BalTreeItemProcess);

  VAR p1:         BTDataPtr;

  PROCEDURE DoThisOne(p:      VirtualAddrType);
  VAR p1:         BTDataPtr;
      k1:         POINTER TO ARRAY[0..255] OF CHAR;
  BEGIN
    MakeReal(p,p1);
    WITH p1^ DO
        IF NOT IsEqual(LLink,VirtNil) THEN
             DoThisOne(LLink);
        END;
        DoItem(Key,Data);
        IF NOT IsEqual(RLink,VirtNil) THEN
             DoThisOne(RLink);
        END;
    END;
(* m.s.    ReleasePage(p,p1); *)
  END DoThisOne;
  BEGIN
     MakeReal(Header,p1);
     IF NOT IsEqual(p1^.RLink,VirtNil) THEN
        DoThisOne(p1^.RLink)
     END;
(* m.s.     ReleasePage(Header,p1); *)
  END ProcessBT;

END BalancedTrees.
