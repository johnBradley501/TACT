IMPLEMENTATION MODULE MemTACTList;

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
(*V2=Assert *)
(*V3=Trace *)

(*
  Ver 1.1
  - Sept. 1, 1989, L.Presutti
    Replaced token number calculations in FindMemItemFromString with GetTokenHRec
    which calculates correctly.
*)
(*<Assert
IMPORT Lib, SYSTEM ;
FROM SYSTEM IMPORT Seg,Ofs,HeapBase;
Assert>*)

IMPORT Str;
FROM SYSTEM IMPORT ADR, ADDRESS;
FROM GlobalDefs IMPORT StrAny;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM HyperDataModel IMPORT HTypeData ;
FROM TokenBase IMPORT GetTokenHRec ;
FROM HyperBase IMPORT
  (* TYPEs *) HRecPntr,
  (* Procs *) CompareHRecs ;
FROM ListData IMPORT
  (* types *) ItemType, DataItem, DataItemPntr, StringData, StringPntr,
  (* procs *) CompareDataItems, MarkAsUsed, DuplicateDataItem;
FROM TACTDataServices IMPORT
  (* procs *) DisposeDataItem;
FROM WordBase IMPORT IntToSortWord;
FROM TACTListModule IMPORT
   TACTListType, TACTList, TACTListData, TACTListItem, TACTListBaseData,
   TACTListBasePntr, GetFirstItem, GetItemData, ReleaseItemHold,
   GetNextItem, GenericNewListItem, DisposeListItem ;
FROM MainLists IMPORT PoolNoForFileNameLists;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) CopyFromVirtMem, CopyToVirtMem, VMAccess, VMModify, VMDefined,
              VMRelease, GetSpace, FreeSpace, RealToPool, VirtToPool,
              EqualVirts, FreePool, VMMarkChanged;
(*<Trace
IMPORT Trace ;
FROM Utils IMPORT ConstStr ;
Trace>*)

TYPE
   BranchType = ( LeftBranch, NoParent, RightBranch ) ;

   MemListItemPntr = POINTER TO MemListItem;
   MemListItem = RECORD
      LLink:     VirtAddr;    (* Left   *)
      RLink:     VirtAddr;    (* Right  *)
      PLink:     VirtAddr;    (* Parent *)
      Data:      VirtAddr;    (* DataItem VA *)
      Branch:    BranchType;  (* relative to parent *)
      B:         INTEGER;     (* balanced info. : in header it is usage cnt*)
   END;

   MemList = RECORD (* first three items must match TACTList.TACTListData j.b.*)
       LDataSize:       CARDINAL;
       BaseData:        TACTListBasePntr;
       Type:            TACTListType;
       (* Unique Data items begins here  j.b. *)
       Header:          VirtAddr;
   END;
   MemListPntr = POINTER TO MemList;

(*<Assert
  VAR
     PgmStartAddr,
     PgmEndAddr		: LONGCARD ;

PROCEDURE CheckAddr( MList : MemListPntr ) ;
   VAR
	NormalizedAddr	: LONGCARD ;
	a		: ADDRESS ;
   BEGIN
	IF MList = NIL THEN
	   ProgramErrorAndHalt( "MemTactList: NIL list." );
	END ;
	IF MList^.LDataSize <> 11 THEN
	   ProgramErrorAndHalt( "MemTactList: wrong size list." );
	END ;
	a := ADR( MList^.BaseData^ ) ;
	NormalizedAddr := LONGCARD( Seg( a^ ) ) * 16 + LONGCARD( Ofs( a^ ) ) ;
	IF (NormalizedAddr > PgmEndAddr) OR (NormalizedAddr < PgmStartAddr) THEN
	   (* this address is outside the program code in memory *)
	   ProgramErrorAndHalt( "MemTactList: invalid addr reference." );
	END ;
   END CheckAddr ;
Assert>*)

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

PROCEDURE DumpTree( VA : VirtAddr ) ;
   TYPE
	TheBranchType = ARRAY BranchType OF ARRAY [0..8] OF CHAR;
(*   CONST TheBranch = TheBranchType( "Left", "NoParent", "Right" ) ; *)
   CONST TheBranch = TheBranchType( "L", "NoP", "R" ) ;
   VAR  Depth : INTEGER ;
	StrDepth : StrAny ;

   PROCEDURE PrintNode( Node : MemListItem ) ;
      BEGIN
	WITH Node DO
	   Trace.TWriteString( " " ) ;		(* " Depth: " *)
	   Trace.TWriteInt( Depth, 0 ) ;
	   Trace.TWriteString( " L: " ) ;
	   PrintAddr( LLink ) ;
	   Trace.TWriteString( " R: " ) ;
	   PrintAddr( RLink ) ;
	   Trace.TWriteString( " P: " ) ;
	   PrintAddr( PLink ) ;
	   Trace.TWriteString( " D: " ) ;
	   PrintAddr( Data ) ;
	   Trace.TWriteString( " " ) ;		(* " Br: " *)
	   Trace.TWriteString( TheBranch[Branch] ) ;
	   Trace.TWriteString( " " ) ;		(* " B: " *)
	   Trace.TWriteInt( B, 0 ) ;
	   Trace.TWriteLn ;
	END ;
      END PrintNode ;

   PROCEDURE DumpNode( VA : VirtAddr; TheParent : VirtAddr; FromBranch : BranchType ): CARDINAL ;
      VAR Node : MemListItem ;
          ra, la: CARDINAL;
      BEGIN
	IF VA = NILVirt THEN  RETURN 0 END ;
	INC( Depth ) ;
	CopyFromVirtMem( VA, SIZE(MemListItem), Node ) ;

	ConstStr( " ", CARDINAL(Depth)*2, StrDepth ) ;
	Trace.TWriteString( StrDepth ) ;

	PrintAddr( VA ) ;
	PrintNode( Node ) ;

	IF Depth > 2 THEN
	   IF FromBranch <> Node.Branch THEN
		Trace.TWriteString( "** Branch label mismatch at this node.") ;
		Trace.TWriteLn ;
	   END ;
	   IF TheParent <> Node.PLink THEN
		Trace.TWriteString( "** Parent link mismatch at this node.") ;
		Trace.TWriteLn ;
	   END ;
	END ;

	la := DumpNode( Node.LLink, VA, LeftBranch ) ;
	ra := DumpNode( Node.RLink, VA, RightBranch ) ;
        IF (Node.B = -1) AND (la = ra + 1) THEN (* do nothing *)
        ELSIF (Node.B = 0) AND (la = ra) THEN (* do nothing *)
        ELSIF (Node.B = 1) AND (la + 1 = ra) THEN (* do nothing *)
        ELSIF Depth > 1 THEN (* ignore dummy header which is always unbalanced *)
	   Trace.TWriteString( "** Unbalanced tree at node: ") ;
	   PrintAddr( VA ) ;
	   PrintNode( Node ) ;
	   Trace.TWriteLn ;
	END;
	DEC( Depth ) ;
        IF la > ra THEN RETURN 1 + la
        ELSE RETURN 1 + ra END;
      END DumpNode ;

   BEGIN
	Depth := 0 ;
	Trace.TWriteLn ;
	Depth := DumpNode( VA, NILVirt, NoParent ) ;
   END DumpTree ;
Trace>*)

PROCEDURE RealFindMemItem(List:        ADDRESS;
                          Data:        DataItemPntr;
                      VAR Item:        TACTListItem): BOOLEAN;
VAR
   p:        VirtAddr;
   p1:       MemListItem;
   MList:    MemListPntr;

PROCEDURE CompToGiven(VA:  VirtAddr (* DataItem VA *)): INTEGER;
VAR a:  INTEGER;
    d2: DataItemPntr;
BEGIN
   d2 := VMAccess(VA);
   a := CompareDataItems(Data,d2);
   VMRelease(VA);
   RETURN a
END CompToGiven;

BEGIN
   (* WriteLn(trcFle,'Trace FindCatego Begins:',Alp2IntWord(CategoName));  *)
   IF List = NIL THEN RETURN FALSE END;
   MList := MemListPntr(List);
   (*<Assert CheckAddr( MList ) ; Assert>*)
   p  := MList^.Header ; (* always start from root of tree *)
   CopyFromVirtMem(p,SIZE(MemListItem),p1);
   p := p1.RLink;
   IF p = NILVirt THEN RETURN FALSE END;

   LOOP
      CopyFromVirtMem(p,SIZE(MemListItem),p1);
      CASE CompToGiven(p1.Data) OF
         0 :
           Item.DataVA := p;
           RETURN TRUE;
      | -1 : (* Given Item < p *)
           p := p1.LLink;
           IF p = NILVirt THEN RETURN FALSE END;
      ELSE (* Given item > p *)
           p := p1.RLink;
           IF p = NILVirt THEN RETURN FALSE END;
      END;
   END; (* Loop *)
END RealFindMemItem;

PROCEDURE FindMemItem(List:        ADDRESS;
                      Data:        VirtAddr; (* as DataItem VA *)
                  VAR Item:        TACTListItem): BOOLEAN;
VAR Pntr:   DataItemPntr;
    rslt:   BOOLEAN;
BEGIN
   Pntr := VMAccess(Data);
   rslt := RealFindMemItem(List, Pntr, Item);
   VMRelease(Data);
   RETURN rslt;
END FindMemItem;

PROCEDURE GetMemItemData(Adr:  ADDRESS;
                         Item: TACTListItem;
                     VAR DVA:  VirtAddr; (*VAddress of Data *)
                     VAR Data: DataItemPntr);
VAR temp:    MemListItem;
BEGIN
   CopyFromVirtMem(Item.DataVA,SIZE(MemListItem),temp);
   DVA := temp.Data;
   Data := VMAccess(temp.Data);
END GetMemItemData;

PROCEDURE ReleaseMemItemHold(List: TACTList; Item: TACTListItem);
VAR temp:    MemListItem;
BEGIN
   CopyFromVirtMem(Item.DataVA,SIZE(MemListItem),temp);
   VMRelease(temp.Data);
END ReleaseMemItemHold;

PROCEDURE GetFirstMemItem(List: ADDRESS; VAR Item: TACTListItem): BOOLEAN;
VAR
     q, p:     VirtAddr;
     q1, p1:   MemListItem;
     MList:    MemListPntr;
BEGIN
     IF List = NIL THEN RETURN FALSE END;
     MList := MemListPntr(List);
     (*<Assert CheckAddr( MList ) ; Assert>*)
     p  := MList^.Header ; (* always start from root of tree *)
     CopyFromVirtMem(p,SIZE(MemListItem),p1);
     q  := p1.RLink ;
     IF q = NILVirt THEN
       Item.DataVA := NILVirt ;
       RETURN FALSE
     END;

     CopyFromVirtMem(q,SIZE(MemListItem),q1);
     p1 := q1 ;
     p  := q ;
     WHILE  p1.LLink <> NILVirt DO
        q := p1.LLink ;
        CopyFromVirtMem(q,SIZE(MemListItem),q1);
        p1 := q1 ;
        p  := q ;
     END ;

   (* p is record of first category name *)
   Item.DataVA := p;
   RETURN TRUE;
END GetFirstMemItem;

PROCEDURE GetLastMemItem(List:    ADDRESS;
                     VAR Item: TACTListItem): BOOLEAN;
VAR
   q, p:   VirtAddr;
   q1, p1: MemListItem;
   MList:  MemListPntr;
BEGIN
   IF List = NIL THEN RETURN FALSE END;
   MList := MemListPntr(List);
   (*<Assert CheckAddr( MList ) ; Assert>*)
   p  := MList^.Header ; (* always start from root of tree *)
   CopyFromVirtMem(p,SIZE(MemListItem),p1);
   q  := p1.RLink ;
   IF q = NILVirt THEN
      Item.DataVA := NILVirt ;
      RETURN FALSE
   END;

   CopyFromVirtMem(q,SIZE(MemListItem),q1);
   p1 := q1 ;
   p  := q ;
   WHILE  p1.RLink <> NILVirt DO
      q := p1.RLink ;
      CopyFromVirtMem(q,SIZE(MemListItem),q1);
      p1 := q1 ;
      p  := q ;
   END ;

   (* p is record of last category name *)
   Item.DataVA := p;
   RETURN TRUE;
END GetLastMemItem ;

PROCEDURE GetNextMemItem(List:    ADDRESS;
                     VAR Item: TACTListItem): BOOLEAN;
VAR
	q, p	:   VirtAddr;
	q1, p1	: MemListItem;
BEGIN
   IF Item.DataVA = NILVirt THEN  RETURN FALSE  END ;
   p := Item.DataVA;
   CopyFromVirtMem(p,SIZE(MemListItem),p1);
   IF p1.RLink = NILVirt THEN
      WHILE (p1.PLink <> NILVirt) AND (p1.Branch = RightBranch) DO
         q := p1.PLink ;
         p := q ;
         CopyFromVirtMem(p,SIZE(MemListItem),p1);
      END ;
      IF (p1.Branch = NoParent) OR (p1.PLink = NILVirt) THEN RETURN FALSE
      ELSE Item.DataVA := p1.PLink END ;
   ELSE
      q := p1.RLink ;
      p := q ;
      CopyFromVirtMem(p,SIZE(MemListItem),p1);
      WHILE p1.LLink <> NILVirt DO
         q := p1.LLink ;
         p := q ;
         CopyFromVirtMem(p,SIZE(MemListItem),p1);
      END ;
      Item.DataVA := p;
   END;
   RETURN TRUE ;
END GetNextMemItem;

PROCEDURE GetPrevMemItem(List:    ADDRESS; (* ignored here *)
                     VAR Item: TACTListItem): BOOLEAN;
VAR
	q, p:   VirtAddr;
	q1, p1: MemListItem;
BEGIN
   IF Item.DataVA = NILVirt THEN  RETURN FALSE  END ;
   p := Item.DataVA;
   CopyFromVirtMem(p,SIZE(MemListItem),p1);
   IF p1.LLink = NILVirt THEN
      WHILE (p1.PLink <> NILVirt) AND (p1.Branch = LeftBranch) DO
         q := p1.PLink ;
         p := q ;
         CopyFromVirtMem(p,SIZE(MemListItem),p1);
      END ;
      IF (p1.Branch = NoParent) OR (p1.PLink = NILVirt) THEN RETURN FALSE
      ELSE Item.DataVA := p1.PLink END;
   ELSE
      q := p1.LLink ;
      p := q ;
      CopyFromVirtMem(p,SIZE(MemListItem),p1);
      WHILE p1.RLink <> NILVirt DO
         q := p1.RLink ;
         p := q ;
         CopyFromVirtMem(p,SIZE(MemListItem),p1);
      END ;
      Item.DataVA := p;
   END;
   RETURN TRUE ;
END GetPrevMemItem;

(* This routine is the 'single rotation' discussed by Knuth     *)
(* in his book 'The Art of Computer Programming' vol 3, pg      *)
(* 457 and 454.                                                 *)

PROCEDURE SRot(VAR p, r, s : VirtAddr;
                   a:        INTEGER);
VAR
   r1, s1, q1:    MemListItem;

PROCEDURE SRotUpdParent( q : VirtAddr; NewBranch : BranchType ) ;
BEGIN
   IF q <> NILVirt THEN
      CopyFromVirtMem(q,SIZE(MemListItem),q1);
      q1.PLink := s ;
      q1.Branch := NewBranch ;
      CopyToVirtMem(q, SIZE(MemListItem), q1);
   END ;
   s1.PLink := r ;
END SRotUpdParent ;

BEGIN
   p := r;
   CopyFromVirtMem(r,SIZE(MemListItem),r1);
   CopyFromVirtMem(s,SIZE(MemListItem),s1);
   s1.B := 0;
   r1.B := 0;
   IF a = 1 THEN
      s1.RLink := r1.LLink;
      r1.LLink := s;
      r1.Branch := s1.Branch ;
      s1.Branch := LeftBranch ;
      SRotUpdParent( s1.RLink, RightBranch ) ;
   ELSE
      s1.LLink := r1.RLink;
      r1.RLink := s;
      r1.Branch := s1.Branch ;
      s1.Branch := RightBranch ;
      SRotUpdParent( s1.LLink, LeftBranch ) ;
   END;
   CopyToVirtMem(r, SIZE(MemListItem), r1);
   CopyToVirtMem(s, SIZE(MemListItem), s1);
END SRot;

(* This routine is the 'double rotation' discussed by Knuth    *)
(* in his book 'The Art of Computer Programming  vol 3, pgs    *)
(* 457 and 454.						    *)


PROCEDURE DRot( VAR p, r, s : VirtAddr;
                    a:        INTEGER);
VAR
   r1,  s1, p1:       MemListItem;

PROCEDURE DRotUpdParent( q, Q : VirtAddr;
                         NewBranch1, NewBranch2 : BranchType ) ;
VAR
   q1  : MemListItem;
BEGIN
   IF q <> NILVirt THEN
      CopyFromVirtMem(q,SIZE(MemListItem),q1);
      q1.PLink  := r ;
      q1.Branch := NewBranch1 ;
      CopyToVirtMem(q, SIZE(MemListItem), q1);
   END ;
   r1.PLink := p ;

   IF Q <> NILVirt THEN
      CopyFromVirtMem(Q,SIZE(MemListItem),q1);
      q1.PLink  := s ;
      q1.Branch := NewBranch2 ;
      CopyToVirtMem(Q, SIZE(MemListItem), q1);
   END ;
   s1.PLink := p ;
END DRotUpdParent ;

BEGIN
   CopyFromVirtMem(r,SIZE(MemListItem),r1);
   CopyFromVirtMem(s,SIZE(MemListItem),s1);
   IF a = -1 THEN
      p := r1.RLink;
      CopyFromVirtMem(p,SIZE(MemListItem),p1);
      p1.Branch := s1.Branch ;
      s1.Branch := RightBranch ;
      r1.RLink := p1.LLink;
      p1.LLink := r;
      s1.LLink := p1.RLink;
      p1.RLink := s;
      DRotUpdParent( r1.RLink, s1.LLink, RightBranch, LeftBranch ) ;
      s1.B := 0;
      r1.B := 0;
      IF p1.B = -1 THEN s1.B := 1 END;
      IF p1.B = 1 THEN r1.B := -1 END;
      p1.B := 0;
   ELSE
      p := r1.LLink;
      CopyFromVirtMem(p,SIZE(MemListItem),p1);
      p1.Branch := s1.Branch ;
      s1.Branch := LeftBranch ;
      r1.LLink := p1.RLink;
      p1.RLink := r;
      s1.RLink := p1.LLink;
      p1.LLink := s;
      DRotUpdParent( r1.LLink, s1.RLink, LeftBranch, RightBranch ) ;
      s1.B := 0;
      r1.B := 0;
      IF p1.B = 1 THEN s1.B := -1 END;
      IF p1.B = -1 THEN r1.B := 1 END;
      p1.B := 0;
   END;
   CopyToVirtMem(r, SIZE(MemListItem), r1);
   CopyToVirtMem(s, SIZE(MemListItem), s1);
   CopyToVirtMem(p, SIZE(MemListItem), p1);
END DRot;

PROCEDURE InsertListItem(DataItm: VirtAddr; (* DataItem VA *)
                     VAR List:    TACTList): BOOLEAN;
VAR
   a:      INTEGER;
   loop:   BOOLEAN ;
   Data:   DataItemPntr ;
   MList:  MemListPntr;
   DItem:  DataItem;
   PoolIn: CARDINAL;
   PoolNo: CARDINAL;

   p, s, t, r, q, ptemp:    VirtAddr;
   t1,  r1,  s1,  p1,  q1:  MemListItemPntr;

PROCEDURE AddNewNode(Parent : VirtAddr;
                     branch : BranchType ;
                 VAR SonOf  : VirtAddr);
VAR qp:    MemListItemPntr;
    DPntr: DataItemPntr;
BEGIN
   q1 := GetSpace(SIZE(MemListItem), PoolNo, q);
   (*<Trace
   Trace.TWriteString( "New Node: " ) ;
   PrintAddr( q ) ;
   Trace.TWriteLn ;
   Trace>*)
   WITH q1^ DO
      PLink := Parent ;
      Branch := branch ;
      IF PoolIn = PoolNo THEN
         Data := DataItm;
         DPntr := VMModify(DataItm)
      ELSE
         DuplicateDataItem(DataItm, PoolNo, Data, DPntr)
      END;
      INC(DPntr^.UsageCount);
      VMRelease(Data);
      LLink := NILVirt;
      RLink := NILVirt;
      B := 0;
   END ;
   SonOf := q ;
   VMRelease(q);
END AddNewNode ;

PROCEDURE CompareToGiven(VA:  VirtAddr (* DataItem VA *)): INTEGER;
VAR a:  INTEGER;
    d2: DataItemPntr;
BEGIN
   d2 := VMAccess(VA);
   a := CompareDataItems(Data,d2);
   VMRelease(VA);
   RETURN a
END CompareToGiven;

BEGIN
   IF List = NIL THEN RETURN FALSE END;
   MList := MemListPntr(List);
   (*<Assert CheckAddr( MList ) ; Assert>*)

   (*<Trace
   Trace.TWriteString( "Insert Data Node: " ) ;
   PrintAddr( DataItm ) ;
   Trace.TWriteLn ;
   Trace.DoTrace := TRUE ;
   Trace>*)

   PoolNo := VirtToPool(MList^.Header);

   IF (List^.Type <> MemoryList) AND (List^.Type <> FileNameList) AND
	(List^.Type <> CatList) THEN
        ProgramErrorAndHalt('Cannot insert in this type of list')
   END;

   PoolIn := VirtToPool(DataItm);
   CopyFromVirtMem(DataItm,SIZE(DataItem),DItem);
   Data := ADR(DItem);

   p := MList^.Header;
   t := p ;
   p1 := VMModify(p);
   s := p1^.RLink;

   IF s = NILVirt THEN
      AddNewNode( p (* was = NILVirt *), NoParent, p1^.RLink ) ;
      VMRelease(p);
      RETURN TRUE
   END;

   s1 := VMAccess(s);
   VMRelease(p);
   p := s;
   p1 := s1;
   loop := TRUE ;
   WHILE loop DO
      CASE CompareToGiven(p1^.Data) OF
         0 : (* already present *)
            VMRelease(p);
            RETURN FALSE
      | -1 : (* New Item < p1.Data *)
            q := p1^.LLink;
            IF q <> NILVirt THEN
               q1 := VMAccess(q);
               IF q1^.B <> 0 THEN
		  t := p ;
                  s := q ;
               END;
               VMRelease(p);
               p := q;
               p1 := q1;
            ELSE
               VMMarkChanged(p);
               AddNewNode( p, LeftBranch, p1^.LLink ) ;
               loop := FALSE
            END;
      |  1 : (* New Item > p1.Data *)
            q := p1^.RLink;
            IF q <> NILVirt THEN
               q1 := VMAccess(q);
               IF q1^.B <> 0 THEN
		  t := p ;
		  s := q ;
               END;
               VMRelease(p);
               p := q;
               p1 := q1;
            ELSE
               VMMarkChanged(p);
               AddNewNode( p, RightBranch, p1^.RLink ) ;
               loop := FALSE
            END;
      END; (* CASE a := CompareDataItems(Data,Data2) *)
   END; (* WHILE loop DO *)

   VMRelease(p);

(* a6:  *)

   s1 := VMModify(s);
   IF CompareToGiven(s1^.Data) = -1 THEN r := s1^.LLink
   ELSE r := s1^.RLink END;

   p := r;
   WHILE p <> q DO
      p1 := VMModify(p);
      IF CompareToGiven(p1^.Data) = -1 THEN
         p1^.B := -1;
         ptemp := p1^.LLink;
      ELSE
         p1^.B := 1;
         ptemp := p1^.RLink;
      END;
      VMRelease(p);
      p := ptemp ;
   END;

(* a7:   *)

   IF CompareToGiven(s1^.Data) = -1 THEN a := -1
   ELSE a := 1 END;

   IF s1^.B = 0 THEN s1^.B := a
   ELSIF s1^.B = (-a) THEN s1^.B := 0
   ELSE
      r1 := VMAccess(r);
      IF r1^.B = a THEN SRot(p, r, s, a)
      ELSE DRot(p, r, s, a) END;
      VMRelease(r);
      t1 := VMModify(t);
      p1 := VMModify(p);
      IF s = t1^.RLink THEN t1^.RLink := p
      ELSE t1^.LLink := p END;
      p1^.PLink := t ;
      VMRelease(p);
      VMRelease(t);
   END;
   VMRelease(s);
   (*<Trace
   Trace.DoTrace := FALSE ;
   Trace.TWriteString( "After Insertion: " ) ;
   Trace.TWriteLn ;
   Trace>*)
   RETURN TRUE ;
END InsertListItem;

PROCEDURE DeleteListItem(DataItm: VirtAddr; (* DataItem VA *)
                     VAR List:    TACTList);
VAR
   t, r, s, p, q,tva:  VirtAddr;
   t1, r1, s1, p1, q1: MemListItemPntr;
   rLeft	    :  VirtAddr;
   rL1		    :  MemListItemPntr;
   ak, a, dak:         INTEGER;
   done:               BOOLEAN;
   RepeatAdjustment:   BOOLEAN;
   Data:               DataItemPntr ;
   MList:              MemListPntr;
   DItem:              DataItem;
   tempItem:           TACTListItem;

PROCEDURE UpdParent( p, parent : VirtAddr ) ;
VAR
   p1:   MemListItemPntr;
BEGIN
   IF p = NILVirt THEN RETURN END;
   p1 := VMModify(p);
   p1^.PLink := parent ;
   VMRelease(p);
END UpdParent ;

    (* algorithm from knuth vol 3 page 465 and 429;		*)
    (* q points at node to be deleted, q1 is real address;	*)

BEGIN
   IF List = NIL THEN RETURN END;
   MList := MemListPntr(List);
   (*<Assert CheckAddr( MList ) ; Assert>*)

   IF (List^.Type <> MemoryList) AND (List^.Type <> FileNameList) AND
	(List^.Type <> CatList) THEN
        ProgramErrorAndHalt('Cannot delete in this type of list')
   END;

   IF NOT FindMemItem(List, DataItm, tempItem) THEN RETURN END;
   q := tempItem.DataVA; (* item to be removed pointed to by q *)

   (*<Trace
   DumpTree( MList^.Header ) ;
   Trace.TWriteLn ;
   Trace.TWriteString( "Delete Node: " ) ;
   PrintAddr( q ) ;
   Trace.TWriteLn ;
   Trace.DoTrace := TRUE ;
   Trace>*)

(* algorithm label: d1 *)
   q1 := VMModify(q);
   t := q;
   t1 := q1;
   IF t1^.RLink = NILVirt THEN
      q := t1^.LLink;
      r  := t1^.PLink ;
      ak := INTEGER( ORD( t1^.Branch ) ) - 1 ;  (*  ** warning: order of enumerated type *)
      (* WriteLn(trcfle,' label d1 taken');  *)
   ELSE
      (* algorithm label: d2 *)
      r  := t1^.RLink;
      r1 := VMModify(r);
      IF r1^.LLink = NILVirt THEN
         r1^.LLink := t1^.LLink;
         UpdParent( t1^.LLink, r ) ;
         q := r;
         q1 := r1;
         ak := 1;
	 VMRelease(r);		(* this "r" no longer needed *)
         (*  WriteLn(trcfle,' label d2 taken');  *)
      ELSE
         (* algorithm label: d3 *)
         s := r1^.LLink;
	 VMRelease(r);		(* this "r" no longer needed *)
         s1 := VMAccess(s);
         WHILE s1^.LLink <> NILVirt DO
            r := s;
            s := s1^.LLink;
            VMRelease( r );
            s1 := VMAccess(s);
         END;
         VMMarkChanged(s);
         r1 := VMModify(r);	(* r here is the parent of s *)
         s1^.LLink := t1^.LLink;
         UpdParent( s1^.LLink, s ) ;
         r1^.LLink := s1^.RLink;
         UpdParent( r1^.LLink, r ) ;
	 VMRelease(r);

         rLeft := r1^.LLink ;		(* need to update new left branch *LP* *)
         IF rLeft <> NILVirt THEN
	    rL1 := VMModify( rLeft ) ;
	    rL1^.Branch := LeftBranch ;	(* same as s1^.Branch!! *)
	    VMRelease( rLeft ) ;
         END ;
         s1^.RLink := t1^.RLink;
         UpdParent( s1^.RLink, s ) ;
         VMRelease(s);
         q := s;
         q1 := s1;
         ak := -1;
    (*   WriteLn(trcfle,' label d3 taken');  *)
      END;
      q1^.B := t1^.B;   (* <--- ??? *)
   END;
   IF q <> NILVirt THEN (* d4 *)
      q1 := VMModify(q);
      q1^.PLink := t1^.PLink ;
      q1^.Branch := t1^.Branch ;
      VMRelease(q);
   END;

(* p -> father of node to be removed *)
   p  := t1^.PLink ;
   p1 := VMModify(p);
   IF t1^.Branch = LeftBranch THEN p1^.LLink := q
   ELSE p1^.RLink := q END;
   VMRelease(p);

   DisposeDataItem(t1^.Data);
   FreeSpace(t, SIZE(MemListItem));
   p := r;
   p1 := VMModify(p);
   done := FALSE;
   RepeatAdjustment := TRUE ;
   (* Assert: a) k = 0 and P(k) = Header, done
	      b) if B( P(k) ) = 0 then terminate deletion algorithm *)
   WHILE RepeatAdjustment AND (p1^.B <> 0) AND (p <> MList^.Header) DO
      IF p1^.B = ak THEN
	 p1^.B := 0 ;  (* (i) page 466 top*)
	 (* Assert: decrease k and repeat adjustment with P(k-1) *)
	 RepeatAdjustment := TRUE ;
      ELSE
	 (* Assert: B( P(k) ) = - a(k) *)
         a := -ak ;
         s := p;
         s1 := p1;
         IF a = 1 THEN r := s1^.RLink
         ELSE r := s1^.LLink END;
         r1 := VMAccess(r);
         t := p1^.PLink ;
         VMRelease(p);
         IF r1^.B = 0 THEN
            (* case 3 *)
            done := TRUE;
            VMRelease(r);
            SRot(p, r, s, a);
            r1 := VMModify(r);
            r1^.B := (-a);
            s1 := VMModify(s);
            s1^.B := a;
            VMRelease(s);
	    (* Assert: single rotation which leaves bal(A) and bal(B) non-zero
	       without changing the overall heigth; make LINK( a(k-1), P(k-1))
	       point to node B.  Terminate the algorithm.			*)
	    (* Note: A is node P(k), and B is node LINK( -a(k), P(k) )		*)
	    RepeatAdjustment := FALSE ;
         ELSIF r1^.B = a THEN
	    SRot(p, r, s, a) ;
	    (* Assert: decrease k and repeat adjustment with P(k-1) *)
	    RepeatAdjustment := TRUE ;
         ELSE
	    DRot(p, r, s, a) ;
	    (* Assert: decrease k and repeat adjustment with P(k-1) *)
	    RepeatAdjustment := TRUE ;
	 END;
         VMRelease(r);
         t1 := VMModify(t);
         p1 := VMModify(p);
         p1^.PLink := t ;
         IF (s = t1^.RLink) THEN t1^.RLink := p
         ELSE t1^.LLink := p END;
         VMRelease(t);
      END;
      IF RepeatAdjustment THEN
	 (* perform the decrease k and prepare repeat adjustment with P(k-1) *)
         ak := INTEGER( ORD( p1^.Branch ) ) - 1 ;
         tva := p;
         p  := p1^.PLink ;
         VMRelease(tva);
         p1 := VMModify(p);
      END;
   END;		(* WHILE RepeatAdjustment AND (p1^.B <> 0) AND (p <> MList^.Header) *)
   IF (p1^.B = 0) AND ( NOT done) THEN
      VMMarkChanged(p);
      (* case ii) pg 466 top *)
       p1^.B := -ak ;
   END;
   VMRelease(p);
   VMRelease(tempItem.DataVA);	(* was "t" but wiped out in line 684 above *LP2* *)

   (*<Trace
   Trace.DoTrace := FALSE ;
   Trace.TWriteString( "After Deletion: " ) ;
   Trace.TWriteLn ;
   DumpTree( MList^.Header ) ;
   Trace>*)
END DeleteListItem;

PROCEDURE MemItemDataPresent(Adr:    ADDRESS;
                             Type:   ItemType;
                             Pos:    HRecPntr;
                         VAR Item:   TACTListItem): BOOLEAN;
VAR dummy:  BOOLEAN;
    Pntr:   DataItemPntr;
    temp:   MemListItemPntr;
    rslt:   BOOLEAN;
BEGIN
   IF Type = CatType THEN
      (* Categories cannot be found purely from Type and Pos j.b *)
      ProgramErrorAndHalt('Unsupported type given')
   END;
   NEW(Pntr);
   Pntr^.FilePos := Pos;
   Pntr^.DataType := Type;
   rslt := RealFindMemItem(Adr, Pntr, Item);
   DISPOSE(Pntr);
   RETURN rslt;
END MemItemDataPresent;

PROCEDURE FindMemItemFromString(Text:  ARRAY OF CHAR;  (* in sort form *)
                                Type:  ItemType;
                                Adr:   ADDRESS;
                            VAR Item:  TACTListItem): BOOLEAN;
VAR
   p:        VirtAddr;
   p1:       MemListItem;
   MList:    MemListPntr;
   tp:       HRecPntr;
   dummy:    BOOLEAN;

PROCEDURE StrToThisData(Adr:  VirtAddr): INTEGER;
VAR
   Pntr:   DataItemPntr;
   rslt:   INTEGER;
   tStr:   ARRAY[0..50] OF CHAR;
   SPtr:   StringPntr;
BEGIN
   Pntr := VMAccess(Adr);
   WITH Pntr^ DO
      IF Type <> DataType THEN
         IF Type < DataType THEN rslt := -1
         ELSE rslt := 1 END;
      ELSE
         CASE DataType OF
           TypeType:
             rslt := Str.Compare(Text,TypeFileData.Word);
         | TokenType:
             rslt := CompareHRecs( tp, FilePos );
         | FileNameType:
             IntToSortWord(FNameInt, tStr);
             rslt := Str.Compare(Text,tStr);
         | CatType:
             rslt := Str.Compare(Text,CatName);
         | RefStringType:
	     SPtr := VMAccess( SortStrVA ) ;	(* assume its not empty?? *)
             rslt := Str.Compare(Text, SPtr^.String);
             VMRelease( SortStrVA ) ;
         ELSE ProgramErrorAndHalt('Bad Type in StrToThisData');
         END;
      END;
   END;
   VMRelease(Adr);
   RETURN rslt;
END StrToThisData;

PROCEDURE HandleTokenString(): BOOLEAN;
VAR WordNo:  LONGINT;
    OK:      BOOLEAN;
BEGIN
   (* convert "Text" to a HRecPntr *)
   WordNo := Str.StrToInt(Text,10,OK);
   IF NOT OK THEN (* invalid number *) RETURN FALSE END ;
   GetTokenHRec( WordNo, tp ) ;
   RETURN TRUE;
END HandleTokenString;

BEGIN
   IF Adr = NIL THEN RETURN FALSE END;
   MList := MemListPntr(Adr);
   (*<Assert CheckAddr( MList ) ; Assert>*)
   p  := MList^.Header ; (* always start from root of tree *)
   CopyFromVirtMem(p,SIZE(MemListItem),p1);
   p := p1.RLink;
   IF p = NILVirt THEN RETURN FALSE END;

   IF Type = TokenType THEN
      IF NOT HandleTokenString() THEN RETURN FALSE END
   END;

   LOOP
      CopyFromVirtMem(p,SIZE(MemListItem),p1);
      CASE StrToThisData(p1.Data) OF
         0 :
           Item.DataVA := p;
           RETURN TRUE;
      | -1 : (* Given Item < p *)
           IF p1.LLink = NILVirt THEN
		Item.DataVA := p;
		RETURN FALSE ;
	   END;
           p := p1.LLink;
      ELSE (* Given item > p *)
           IF p1.RLink = NILVirt THEN
		Item.DataVA := p;
		(* move to the next item if any there *LP2* *)
		dummy := GetNextMemItem( MList, Item ) ;
		RETURN FALSE ;
           END;
           p := p1.RLink;
      END;
   END; (* Loop *)
END FindMemItemFromString;

PROCEDURE DeleteWholeMemList(VAR Adr:   ADDRESS);
VAR
   MList:    MemListPntr;

PROCEDURE CheckForRealDelete(Header: VirtAddr): BOOLEAN; (*TRUE = return now*)
VAR
   Pntr:   MemListItemPntr;
   rslt:   BOOLEAN;
BEGIN
   IF NOT VMDefined(Header) THEN RETURN FALSE END;
   Pntr := VMAccess(Header);
   DEC(Pntr^.B);
   rslt := Pntr^.B = 0;
   VMRelease(Header);
   RETURN rslt;
END CheckForRealDelete;

PROCEDURE LocalDeleteListItem(Adr:  VirtAddr);
VAR
   Pntr:   MemListItemPntr;
   LLink, RLink, Data : VirtAddr ;
BEGIN
(* -- old form -- *LP3*
   Pntr := VMAccess(Adr);
   WITH Pntr^ DO
      IF LLink <> NILVirt THEN LocalDeleteListItem(LLink) END;
      IF RLink <> NILVirt THEN LocalDeleteListItem(RLink) END;
      IF Data <> NILVirt THEN DisposeDataItem(Data) END;
   END;
   VMRelease(Adr);
------ *)
   Pntr  := VMAccess(Adr);	(* don't tie down any real page that need not be!! *)
   LLink := Pntr^.LLink ;
   RLink := Pntr^.RLink ;
   Data  := Pntr^.Data  ;
   VMRelease(Adr);
   IF LLink <> NILVirt THEN LocalDeleteListItem(LLink) END;
   IF RLink <> NILVirt THEN LocalDeleteListItem(RLink) END;
   (* at this point don't really care about modification to Pntr^.Data since do a FreeSpace!! *)
   IF Data  <> NILVirt THEN DisposeDataItem(Data) END;
   FreeSpace(Adr, SIZE(MemListItem));
END LocalDeleteListItem;

BEGIN
   IF Adr = NIL THEN RETURN END;
   MList := MemListPntr(Adr);
   (*<Assert CheckAddr( MList ) ; Assert>*)
   WITH MList^ DO
      IF CheckForRealDelete(Header) THEN
         LocalDeleteListItem(Header);
      END;
   END;
   DISPOSE(MList);
   Adr := NIL;
END DeleteWholeMemList;

PROCEDURE CopyList(List1:  TACTList;
               VAR List2:  TACTList);
VAR
   Item:  TACTListItem;
   DVA:   VirtAddr;
   Data:  DataItemPntr;
   dummy: BOOLEAN;
BEGIN
   IF (List2^.Type <> MemoryList) AND (List2^.Type <> FileNameList) AND
	(List2^.Type <> CatList) THEN
      ProgramErrorAndHalt('Non MemoryList Copy is not supported')
   END;

   GenericNewListItem(List1, Item);
   IF NOT GetFirstItem(List1, Item) THEN RETURN END;
   REPEAT
      GetItemData(List1, Item, DVA, Data);
      dummy := InsertListItem(DVA, List2);
      ReleaseItemHold(List1, Item);
   UNTIL NOT GetNextItem(List1,Item);
   DisposeListItem(List1, Item);
END CopyList;

PROCEDURE ListPoolNo(List:  TACTList): CARDINAL;
VAR MList: MemListPntr;
BEGIN
   MList := MemListPntr(List);
   (*<Assert CheckAddr( MList ) ; Assert>*)
   IF (MList^.Type <> MemoryList) AND (MList^.Type <> FileNameList) AND (MList^.Type <> CatList) THEN
	RETURN MAX(CARDINAL)	(* return a fake PoolNo for non memory type lists *)
   ELSE
	RETURN VirtToPool(MList^.Header);
   END ;
END ListPoolNo;

PROCEDURE IncrementListUsage(List: TACTList);
VAR MList:  MemListPntr;
    Hdr:    MemListItemPntr;
BEGIN
   MList := MemListPntr(List);
   (*<Assert CheckAddr( MList ) ; Assert>*)
   Hdr := VMAccess(MList^.Header);
   INC(Hdr^.B);
   VMRelease(MList^.Header);
END IncrementListUsage;

PROCEDURE RealInitializeList(Pool:       CARDINAL;
                             TypeOfList: TACTListType):  TACTList;
VAR  MemListP:    MemListPntr;
     HPntr:       MemListItemPntr;
BEGIN
   NEW(MemListP);
   WITH MemListP^ DO
      LDataSize := SIZE(MemList);
      BaseData := ADR(OfficialMemTACTListBaseData);
      Type := TypeOfList;
      HPntr := GetSpace(SIZE(MemListItem), Pool, Header);
   END;
   WITH HPntr^ DO
      LLink := NILVirt;
      RLink := NILVirt;
      PLink := NILVirt;
      Data := NILVirt;
      Branch := NoParent;
      B := 1;
   END;
   VMRelease(MemListP^.Header);
   RETURN TACTList(MemListP);
END RealInitializeList;

PROCEDURE NewMemoryList(PoolNo: CARDINAL): TACTList;
BEGIN
   RETURN RealInitializeList(PoolNo, MemoryList);
END NewMemoryList;

PROCEDURE InitializeFileNameList(): TACTList;
BEGIN
   RETURN RealInitializeList(PoolNoForFileNameLists, FileNameList);
END InitializeFileNameList;

PROCEDURE InitializeCatList(): TACTList;
BEGIN
   RETURN RealInitializeList(0, CatList);
END InitializeCatList;

PROCEDURE DisposeMemListItem(List:  TACTList; VAR Item: TACTListItem);
BEGIN
   Item.DataVA := NILVirt;
END DisposeMemListItem;

PROCEDURE CopyListItem(     List : TACTList; Item1 : TACTListItem;
			VAR Item2 : TACTListItem ) ;
    BEGIN
	Item2 := Item1;
    END CopyListItem ;

BEGIN
  WITH OfficialMemTACTListBaseData DO
      NewItemProc :=      GenericNewListItem;
      CopyListItemProc := CopyListItem;
      DispListItemProc := DisposeMemListItem;
      DisposeListProc :=  DeleteWholeMemList;
      GetItemDataProc :=  GetMemItemData;
      ReleaseItemProc :=  ReleaseMemItemHold;
      GetFirstItemProc := GetFirstMemItem;
      GetLastItemProc  := GetLastMemItem;
      GetNextItemProc :=  GetNextMemItem;
      GetPrevItemProc :=  GetPrevMemItem;
      FindItemProc :=     FindMemItem;
      ItemDataPresProc := MemItemDataPresent;
      FindFromStrProc :=  FindMemItemFromString;
  END;

	(*<Assert
	PgmStartAddr := LONGCARD( Lib.PSP ) * 16 ;
	PgmEndAddr := LONGCARD(SYSTEM.HeapBase) * 16 ;
	Assert>*)

END MemTACTList.
