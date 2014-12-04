(* ***************************************************************)
(*		       DATABASE	TOOLBOX	4.0			*)
(*     Copyright (c) 1984, 87 by Borland International,	Inc.	*)
(*								*)
(*		    TURBO LONG SORT UNIT			*)
(*								*)
(*  Purpose: Toolbox of	routines to implement a	general		*)
(*	     purpose QuickSort for over	2 billion items.	*)
(*								*)
(*  Modified: By Lidio Presutti	 (March	1988)			*)
(*    -	improve	basic QuickSort	algorithm by using Insertion	*)
(*	sort for small partitions.				*)
(*    -	allow multiple passes thru sorted results.		*)
(*    -	use INC	& DEC as they are optimised by compiler	in loops*)
(*								*)
(*    - Adapted for JPI Modula-2 (Oct. 1989)			*)
(*								*)
(****************************************************************)

IMPLEMENTATION MODULE LongSort ;


IMPORT FIO, Str, IO ;
FROM SYSTEM IMPORT BYTE, ADDRESS, ADR, SIZE, Ofs, Seg ;
FROM Lib IMPORT Move ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE, Available, HeapAvail, MainHeap ;
IMPORT SYSTEM,TSXLIB,Lib;

CONST
   maxint = MAX(INTEGER)  (* 32767 *) ;
   MaxIntBy2 = MAX(CARDINAL) (* maxint * 2 = 65536 *) ;
   TempSortFileName = 'SORTWORK.$$$' ;
   MaxPage = 5000 ;
   segsize = 16*1024; (* 16K segments *)
   SecSize = 512; (* m.s. was 128 *)
TYPE
   SortPointer = POINTER TO ARRAY[0..(MaxIntBy2 - 1)] OF BYTE; (* was MaxIntBy2 *)
   PageFrameRange = [0..5000] ; (* m.s. - was 10 *)

VAR
   LSortFree: BOOLEAN; (* *LP* *)
   SortRecord: RECORD (* Global	variables used by all routines *)
		      (* variables concerning paging *)
		      N: LONGINT;      (* no of records to be sorted	*)
		      B: LONGINT;      (* no of records pr page	*)
		      Pages: PageFrameRange;   (* No of pages in memory - m.s. was 10 	*)
(*		      SecPrPage : LONGINT;	(* no of sectors per page	*) *)
		      NDivB, NModB: CARDINAL;	(* = N Div B, N Mod B respectively *)

		      Buf: ARRAY PageFrameRange OF SortPointer; (* Addresses of buffers - was 10 *)
(* m.s. not needed		      Page: ARRAY PageFrameRange OF CARDINAL;    (* Nos of pages in workarea - was 10 *)
		      W: ARRAY PageFrameRange OF BOOLEAN;       (* dirty-bits : is page changed ?- was 10 *)
*)
		      Udix: LONGINT;     (* Udix points to the next record to be returned *)

(*		      F: FIO.File;   (* File used for external sorting	 *)

		      FileCreated: BOOLEAN;     (* Is external file used *)
		      FileName: ARRAY[0..64] OF CHAR;
*)
		      Error: CARDINAL;     (* Has an i/o error occurred	*)

		      ItemLength: CARDINAL;     (* Length of record	*)
	    END;

	SaveZ, SwopPost: SortPointer;
	SafetyP, WorkArea: LONGCARD ; (* No of bytes internal memory	   *)

	I	 : CARDINAL;
	PageSize : CARDINAL; (* No of bytes pr page *)


  GR : TSXLIB.GlobalRecPtr;
TYPE SegArray = ARRAY[0..1023] OF CARDINAL;

VAR Swapped : BOOLEAN;
(*#save, call(reg_saved=>(bx,cx,dx,di,si,es,ds,st1,st2),reg_return=>(ax)) *)
PROCEDURE TestSwap():BOOLEAN;
(* routine to monitor when virtual memory accessed *)
BEGIN
  Swapped := TRUE;
  RETURN TRUE; (* allow to swap *)
END TestSwap;
(*#restore*)

PROCEDURE SortAvail () : LONGINT ;
VAR
  segs : SegArray;
  nsegs,nrsegs,s : CARDINAL;
  sa   : ADDRESS;
  r    : SYSTEM.Registers;
  ps   : ARRAY[0..4] OF CHAR;
  i    : CARDINAL;
BEGIN

  GR := TSXLIB.GETGLOBALPTR();
  (* the following is an installation check for the TopSpeed Extender *)
  (* can be called from real/protected libraries *)
  r.AH := 2BH;
  r.CX := 05354H; (* 'TS' *)
  r.DX := 05844H; (* 'DX' *)
  Lib.Dos(r);     (* int 21H *)
  IF r.AX = 0 THEN (* TopSpeed Extender installed *)
  END;
(*
  IO.WrStr('TopSpeed Extender Version '); WrVer(r.CX);IO.WrLn;
  IO.WrStr('様様様様様様様様様様様様様様様');IO.WrLn;
*)
  sa := GR^.SwapCheckProc;
  GR^.SwapCheckProc := ADR(TestSwap);
  nsegs := 0;
  nrsegs := 0;
  Swapped := FALSE;
  LOOP
    s := TSXLIB.ALLOCSEG(segsize);
    IF (s=MAX(CARDINAL)) THEN EXIT END;
    segs[nsegs] := s;
    IF Swapped THEN EXIT END;
    INC(nsegs);
(*    IF TSXLIB.GETSEGBASE(s)<100000H THEN INC(nrsegs) END; *)
    IF nsegs>HIGH(segs) THEN EXIT END;
  END;
  GR^.SwapCheckProc := sa;
(*  IO.WrStr('Extended memory available:   ');IO.WrCard(16*(nsegs-nrsegs),8);IO.WrChar('K');IO.WrLn;
  IO.WrStr('Low memory available:        ');IO.WrCard(16*nrsegs,8);IO.WrChar('K');IO.WrLn;
  IO.WrStr('Total memory available:      ');IO.WrCard(16*nsegs,8);IO.WrChar('K');IO.WrLn;

  IF Lib.ParamCount()>0 THEN
    Lib.ParamStr(ps,1);
    IF CAP(ps[0])='T' THEN
      TestSegs(segs,nsegs);
    END;
  END;
  *)
  FOR s := 1 TO nsegs DO TSXLIB.FREESEG(segs[s-1]); END;
  RETURN LONGINT(nsegs) * LONGINT(segsize) ;
END SortAvail;

(*   m.s. not needed

(* Write page PageNo on file, address of page in memory is Addr *)
PROCEDURE SortPut( Addr : SortPointer; PageNo : CARDINAL);
   BEGIN
(*	IOCheck(off); *)
	IF SortRecord.Error = 0	THEN
		(* No i/o error *)
		FIO.Seek(SortRecord.F, VAL(LONGCARD,PageNo) * VAL(LONGCARD,PageSize));
		FIO.WrBin(SortRecord.F, Addr^, PageSize );
		IF FIO.IOresult() <> 0 THEN
		    SortRecord.Error :=	10 (* write error *)
		END
	END
   END SortPut;
*)

(* Find address in memory for record no Ix. It is assumed that record Ix is in memory *)
PROCEDURE SortFetchAddr( Ix : LONGINT; VAR Adr : SortPointer );
   VAR
	IxPage, IxOfs : CARDINAL;
(*	I: PageFrameRange; (* was 10 *) *)
   BEGIN
	IxPage := VAL(CARDINAL, Ix DIV SortRecord.B);
	IxOfs  := VAL(CARDINAL, Ix MOD SortRecord.B);
(*	I := 0;
	WHILE SortRecord.Page[I] <> IxPage DO  INC(I)  END;
(*	Adr := Ptr(Seg(ADR(SortRecord.Buf[I]^)), Ofs(ADR(SortRecord.Buf[I]^)) +
		(Ix MOD SortRecord.B)*SortRecord.ItemLength); *)
	Adr := ADR( SortRecord.Buf[I]^[ IxOfs * SortRecord.ItemLength ] );
*)	
	Adr := ADR( SortRecord.Buf[IxPage]^[ IxOfs * SortRecord.ItemLength ] );
   END SortFetchAddr;

(* m.s. -old version
(* Find address in memory for record no Ix. It is assumed that record Ix is in memory *)
PROCEDURE SortFetchAddr( Ix : LONGINT; VAR Adr : SortPointer );
   VAR
	IxPage, IxOfs : CARDINAL;
	I: PageFrameRange; (* was 10 *)
   BEGIN
	IxPage := VAL(CARDINAL, Ix DIV SortRecord.B);
	IxOfs  := VAL(CARDINAL, Ix MOD SortRecord.B);
	I := 0;
	WHILE SortRecord.Page[I] <> IxPage DO  INC(I)  END;
(*	Adr := Ptr(Seg(ADR(SortRecord.Buf[I]^)), Ofs(ADR(SortRecord.Buf[I]^)) +
		(Ix MOD SortRecord.B)*SortRecord.ItemLength); *)
	Adr := ADR( SortRecord.Buf[I]^[ IxOfs * SortRecord.ItemLength ] );
   END SortFetchAddr;
*)
(* m.s. - not needed anymore
(* After call of SortFetchPage the record Ix is in memory.
   If records U1 and U2 are in memory before call, then
   they are not overwritten since we soon will need them   *)
PROCEDURE SortFetchPage(Ix, U1, U2: LONGINT);
   VAR
	U1Page, U2Page, IxPage: CARDINAL;
	Victim: PageFrameRange; (* The chosen page to be written to file - was 10 *)


	(* Read	page PageNo into memory	at address Addr	*)

	PROCEDURE SOget( Addr : SortPointer; Pageno : CARDINAL);
	   VAR
		BytesRead : CARDINAL ;
	   BEGIN
		IF SortRecord.Error = 0 THEN
		    FIO.Seek(SortRecord.F, VAL(LONGCARD,Pageno) * VAL(LONGCARD,PageSize) );
		    BytesRead := FIO.RdBin(SortRecord.F, Addr^, PageSize );
		    IF FIO.IOresult() <> 0 THEN
		      SortRecord.Error := 11 (* read error *)
		    END
		END;
	   END SOget;

	(* InMem returns true if record	ix is in memory	*)
	PROCEDURE InMem(Ix: LONGINT): BOOLEAN;
	   VAR
		I, IxPage: CARDINAL;
	   BEGIN
		IxPage := VAL( CARDINAL, Ix DIV SortRecord.B ) ;
		FOR I := 0 TO SortRecord.Pages-1 DO
		    IF IxPage =	SortRecord.Page[I] THEN
		       RETURN TRUE
		    END
		END;
		RETURN FALSE
	   END InMem;

   BEGIN (* SortFetchPage *)
	IF ( NOT InMem(Ix)) THEN
	   (* Record Ix not in memory *)
	   IxPage := VAL( CARDINAL, Ix DIV SortRecord.B ) ;
	   Victim := 0;
	   U1Page := VAL( CARDINAL, U1 DIV SortRecord.B ) ;
	   U2Page := VAL( CARDINAL, U2 DIV SortRecord.B ) ;
	   WHILE ((SortRecord.Page[Victim] = U1Page) OR (SortRecord.Page[Victim] = U2Page)) DO
		INC(Victim)
	   END; (* SortRecord.Page[Victim] not in U *)
	   IF SortRecord.W[Victim] THEN (* Dirty bit set *)
		SortPut(SortRecord.Buf[Victim], SortRecord.Page[Victim])
	   END;
	   SOget(SortRecord.Buf[Victim], IxPage);
	   SortRecord.Page[Victim] := IxPage;
	   SortRecord.W[Victim] := FALSE;
	END
   END SortFetchPage;
*)

(* Function TurboSort returns an integer specifying the result of the sort
		   LTurboSort=0	 : Sorted
		   LTurboSort=3	 : Workarea too	small
		   LTurboSort=8	 : Illegal itemlength
		   LTurboSort=9	 : More	than MaxLongInt	records
		   LTurboSort=10 : Write error during sorting (	disk full )
		   LTurboSort=11 : Read	error during sorting
		   LTurboSort=12 : Impossible to create	new file ( directory full )
		   LTurboSort=13 : ARRAY FULL
*)



(* InpProc, LessProc,  and OutProc are procedure pointers which hold the
   address of the user input procedure, less function, and output procedure,
   respectively.  ItemLength is the size of the item to be sorted (in bytes).
   Use SizeOf(MyRec) to calculate this value. *)

PROCEDURE LTurboSort(ItemLength: CARDINAL;
		     InpProc	: SortIOProc ;
		     Less	: CompareProc ;
		     OutProc	: SortIOProc ;
		     TempDiskArea : ARRAY OF CHAR ) : CARDINAL;
   CONST
(*	UserStack = 8192 ; (* Minimum  memory for user *) *)
   VAR
	TempPageSize : LONGINT ;
	UserStack : LONGINT ;

	(* Redefine MaxAvail to	return real result *)


	(* Non-recursive version of quicksort algorithm	as given
	   in Nicklaus Wirth : Algorithms + Data Structures = Programs *)


	PROCEDURE QuickSort ;

	   (* Change records I and J *)
	   PROCEDURE Exchange( I, J : LONGINT);
		VAR
		    P, Q, R, S: CARDINAL;
		    K, L: PageFrameRange; (* was 10 *)
		    IAddr, JAddr: SortPointer;
		BEGIN
		    P := VAL(CARDINAL, I DIV SortRecord.B );
(*		    K := 0;
		    WHILE SortRecord.Page[K] <>	P DO  INC(K)  END;
*)		
		    Q := VAL(CARDINAL, J DIV SortRecord.B);
(*		    L := 0;
		    WHILE SortRecord.Page[L] <>	P DO  INC(L)  END;
*)
		    R := VAL(CARDINAL, I MOD SortRecord.B );
		    S := VAL(CARDINAL, J MOD SortRecord.B );
		    IAddr := ADR(SortRecord.Buf[P]^[ R * ItemLength] );
		    JAddr := ADR(SortRecord.Buf[Q]^[ S * ItemLength] );
		    Move(IAddr, SwopPost, ItemLength);
		    Move(JAddr, IAddr, ItemLength);
		    Move(SwopPost, JAddr, ItemLength);
		END Exchange;



	CONST
	    MaxStack = 32; (* Log2(N) =	MaxStack, i. e.	for MaxStack = 32
			      it is possible to sort over 2 billion records *)

	    CutOff = 20; (* cutoff for Insertion Sort, best when 8 < CutOff < 30 *)


	VAR
	    (* The stacks *)
		LStack: ARRAY [1..MaxStack] OF LONGINT; (* Stack of left index *)
		RStack: ARRAY [1..MaxStack] OF LONGINT; (* Stack of right index *)

		Sp	: CARDINAL; (* Stack SortPointer *)
		M, L, R, I, J	: LONGINT ;
		XAddr, YAddr, ZAddr: SortPointer;

		II, JJ: LONGINT ; (* **LP** *)

		JJAddr, Jm1Addr: SortPointer;
	LABEL DoneInnerLoop ;
	BEGIN
		(* The quicksort algorithm *)
		IF SortRecord.N > 0 THEN
		    LStack[1] := 0;
		    RStack[1] := SortRecord.N-1;
		    Sp := 1
		ELSE
		    Sp := 0
		END;
		WHILE Sp > 0 DO
		    (* Pop(L,R)	*)
		    L := LStack[Sp];
		    R := RStack[Sp];
		    DEC(Sp);
		    REPEAT
		      IF (R-L) < CutOff	THEN (*	*LP* *)
			(* Sort	small partitions via Insertion Sort *)
			FOR II := L+1 TO R DO
			  JJ :=	II;
(* m.s. - not needed	  SortFetchPage(JJ, JJ-1, II); (* get JJ, hold II and JJ-1 *) *)
			  (* record JJ in memory*)
			  SortFetchAddr(JJ, JJAddr);
			  Move(JJAddr, SwopPost, ItemLength);	(* Copy	to temp	location *)
(* m.s.			  SortFetchPage(JJ-1, JJ, II); (* get JJ-1, hold II and	JJ *) *)
			  SortFetchAddr(JJ-1, Jm1Addr);
			  WHILE	( Less(SwopPost, Jm1Addr)) DO
			    (* move JJ-1 content over to proper	place *)
			    Move(Jm1Addr, JJAddr, ItemLength);
			    JJAddr := Jm1Addr;
			    DEC(JJ);
			    IF JJ <= L THEN
			       GOTO DoneInnerLoop
			    END; (* get	JJ-1, hold II and JJ in	memory *)
(* m.s.			    SortFetchPage(JJ-1,	JJ, II); *)
			    SortFetchAddr(JJ-1,	Jm1Addr);
			  END;
			DoneInnerLoop :
			  Move(SwopPost, JJAddr, ItemLength);
			END; (*	For II := L+1 To R *)
			L := R;
		      ELSE
			I := L;
			J := R;
			M := (I+J) DIV 2 ; (* was SHR 1 *)
(* m.s.			SortFetchPage(M, I, J);	(* get M, hold I and J *) *)
			(* record M in memory*)
			IF SortRecord.Error <> 0 THEN
			  RETURN
			END; (*	End program *)
			SortFetchAddr(M, ZAddr);
			Move(ZAddr, SaveZ, ItemLength);
			REPEAT
(* m.s. 			  SortFetchPage(I, J, M); (* get I, hold J and M *) *)
			  (* I and M in	memory *)
			  IF SortRecord.Error <> 0 THEN
			    RETURN
			  END; (* End program *)
			  SortFetchAddr(I, XAddr);
			  WHILE	Less(XAddr, SaveZ) DO
			    INC(I);
(* m.s.			    SortFetchPage(I, J,	M); *)
			    SortFetchAddr(I, XAddr);
			    IF SortRecord.Error	<> 0 THEN
			      RETURN
			    END; (* End	program	*)
			  END; (* I and	M in memory *)
(* m.s.			  SortFetchPage(J, I, M); (* Get J, hold I and M *) *)
			  (* I,	J and M	in memory *)
			  IF SortRecord.Error <> 0 THEN
			    RETURN
			  END; (* End program *)
			  SortFetchAddr(J, YAddr);
			  WHILE	Less(SaveZ, YAddr) DO
			    DEC(J);
(* m.s.			    SortFetchPage(J, I,	M); *)
			    SortFetchAddr(J, YAddr);
			    IF SortRecord.Error	<> 0 THEN
			      RETURN
			    END; (* End	program	*)
			  END; (* I, J and M in	memory *)
			  IF I <= J THEN
			    IF I <> J THEN
			      Exchange(I, J)
			    END;
			    INC(I);
			    DEC(J);
			  END;
			UNTIL I	> J; (*	Push longest interval on stack *)
			IF J-L < R-I THEN
			  IF I < R THEN
			    (* Push(I,R) *)
			    INC(Sp);
			    LStack[Sp] := I;
			    RStack[Sp] := R;
			  END;
			  R := J
			ELSE
			  IF L < J THEN
			    (* Push(L,J) *)
			    INC(Sp);
			    LStack[Sp] := L;
			    RStack[Sp] := J;
			  END;
			  L := I
			END;
		      END; (* If R-L < CutOff Then ... Else ...*)
		    UNTIL L >= R ;
		  END;
	END  QuickSort;



	BEGIN (* TurboSort *)
		IF ItemLength >	1 THEN
		  IF SpaceReserved > 0 THEN
                     UserStack := SpaceReserved ;
                  ELSE
                     UserStack := 4096 ;
                  END ;
		  SortRecord.ItemLength	:= ItemLength;
(*		  WorkArea := SortAvail() - VAL(LONGINT,ItemLength) - VAL(LONGINT,ItemLength)
		              - UserStack ;

		  (* No	of pages to be kept in memory -- at most 10 with 640K *)
		  SortRecord.Pages := VAL(CARDINAL, WorkArea DIV MaxIntBy2) + 1 ;
		  IF SortRecord.Pages <	3 THEN (* Must be at least 3 *)
		    SortRecord.Pages :=	3
		  END;		
		  (* Note: 512 <= SecPrPage <= 1707 *)
		  SortRecord.SecPrPage := VAL(LONGINT, (WorkArea DIV SecSize) DIV VAL(LONGCARD,SortRecord.Pages)) ;
		  IF SortRecord.SecPrPage > 20 THEN
		    SortRecord.SecPrPage := 4*(SortRecord.SecPrPage DIV	4)
		  END;

		  TempPageSize := SortRecord.SecPrPage*SecSize; (* ??? May be negative or 0 *)
		  IF TempPageSize > MaxIntBy2 THEN
			PageSize := MaxIntBy2  (* 64K = max segment on 8088 *)
		  ELSE
			PageSize := VAL(CARDINAL, TempPageSize)
		  END ;
*)	
                  SortRecord.Pages := MaxPage ; (* max # of pages *)
                  PageSize := (MaxIntBy2 DIV SecSize) * SecSize ;
(*                  SortRecord.SecPrPage := PageSize DIV SecSize ; *)
		  IF (PageSize = MaxIntBy2) THEN
		    SafetyP := MaxIntBy2 ;
		  ELSE
		    SafetyP := VAL(LONGINT, PageSize )
		  END;
		  SortRecord.B := VAL(LONGINT, SafetyP DIV VAL(LONGCARD,ItemLength) ) ;
		  IF SortRecord.B > 0 THEN
		    (* Enough memory *)
		    ALLOCATE(SwopPost, ItemLength);
		    ALLOCATE(SaveZ, ItemLength);
(*		    FOR	I := 0 TO SortRecord.Pages-1 DO
		      ALLOCATE(SortRecord.Buf[I], PageSize)
		    END;
*)
                    ALLOCATE( SortRecord.Buf[0] , PageSize ) ;
		    SortRecord.Error :=	0;
(*		    SortRecord.FileCreated := FALSE; *)
		    SortRecord.N := 0;
		    SortRecord.NModB :=	0;
		    SortRecord.NDivB :=	0;
(*		    FOR	I := 0 TO SortRecord.Pages-1 DO
		      SortRecord.Page[I] := I
		    END;
*)		
(*		    Str.Concat( SortRecord.FileName, TempDiskArea, TempSortFileName ) ; *)
		    InpProc ;    	(* call	user defined input procedure *)
		    (* all records are read *)

		    IF SortRecord.Error	= 0 THEN
		      (* No errors while reading records *)
		      (* Initialize virtual system *)
(*		      FOR I := 0 TO SortRecord.Pages-1 DO
			 SortRecord.W[I] := TRUE
		      END;
                      FOR I := SortRecord.Pages TO MaxPage DO  (* was 10 m.s. - make sure *)
                         SortRecord.W[I] := FALSE
                      END ;
*)
		      IF SortRecord.Error = 0 THEN
			 QuickSort;
		      END; (* End sort,	return all records *)
		      SortRecord.Udix := 0;

		      IF SortRecord.Error = 0 THEN
(*			 IF NOT SortRecord.FileCreated THEN
			    (* create user file *)
			    SortRecord.F := FIO.Create( SortRecord.FileName ) ;
			    IF FIO.IOresult() <> 0 THEN
			       SortRecord.Error := 12 ;
			       RETURN SortRecord.Error  (* Note need to clean after this ?? *)
			    ELSE
			       SortRecord.FileCreated := TRUE
			    END;
			 END ;
			 (* force all of memory buffers to disk *)
			 FOR I := 0 TO SortRecord.Pages-1 DO
			    SortPut( SortRecord.Buf[I], SortRecord.Page[I] )
			 END;
			 (* Release all allocated memory except ...Buf[0] *)
			 FOR I := SortRecord.Pages-1 TO 1 BY -1 DO
			    DEALLOCATE(SortRecord.Buf[I], PageSize);
                            SortRecord.Buf[I] := NIL ;
			 END;
*)			
			 DEALLOCATE(SaveZ, SortRecord.ItemLength);
			 DEALLOCATE(SwopPost, SortRecord.ItemLength);

			 OutProc ; (* call user defined output procedure *)

			 FOR I := SortRecord.Pages-1 TO 0 BY -1 DO
			    DEALLOCATE(SortRecord.Buf[I], PageSize);
                            SortRecord.Buf[I] := NIL ;
			 END;
(*			 SortRecord.Buf[0] := NIL ;
			 FIO.Close(SortRecord.F);
			 FIO.Erase(SortRecord.FileName);
			 SortRecord.FileCreated := FALSE ;  (* m.s. - allow multiple uses of LSORT *)
*)			
		      END;
		    END;
 		    (* IF LSortFree THEN
			LSortFreeUp
		    END;  *)
		  ELSE
		    SortRecord.Error :=	3
		  END; (* Too little memory  *)
		ELSE
		  SortRecord.Error := 8
		END; (*	Illegal	itemlength *)
		RETURN  SortRecord.Error;
	END LTurboSort ;


(* Procedures used by user routines *)


PROCEDURE LSortGetPos( VAR Pos : LONGINT ) ;
   (* return current record in the sort file *)
   BEGIN
	Pos := SortRecord.Udix ;
   END LSortGetPos ;

PROCEDURE LSortReset( NewStartPos : LONGINT ) ;
   (* next call to LSortReturn will return record "NewStartPos" *)
   BEGIN
	IF NewStartPos < 0 THEN
	   SortRecord.Udix := 0;
	ELSIF NewStartPos >= SortRecord.N THEN
	   SortRecord.Udix := SortRecord.N ;
	ELSE
	   SortRecord.Udix := NewStartPos ;
	END ;
   END LSortReset;

(*
PROCEDURE LSortFreeUp; (* **LP** *)
   VAR
	I : CARDINAL;
   BEGIN
	IF SortRecord.FileCreated THEN
		FIO.Close(SortRecord.F);
		FIO.Erase(SortRecord.FileName)
	END;
	(* Release allocated memory *)
	FOR I := SortRecord.Pages-1 TO 0 BY -1 DO
	    DEALLOCATE(SortRecord.Buf[I], PageSize)
	END;
	DEALLOCATE(SaveZ, SortRecord.ItemLength);
	DEALLOCATE(SwopPost, SortRecord.ItemLength);
   END LSortFreeUp ;
*)

(* Accept record from user *)
PROCEDURE LSortRelease( VAR ReleaseRecord : ARRAY OF BYTE);
   VAR
	I: CARDINAL;
	BufNo: CARDINAL;
	Point: SortPointer;
   BEGIN
	IF SortRecord.Error = 0	THEN
	   IF SortRecord.N = MAX(LONGINT) THEN
		(* Only possible to sort MaxLongInt records *)
		SortRecord.Error := 9
	   END;
	   IF (SortRecord.NDivB >= SortRecord.Pages) THEN
              (* we have a problem - array full time to increase > 5000 !!! *)
              SortRecord.Error := 13 ;
              RETURN ;
(*	      (* Write out last read page	*)
	      IF SortRecord.NDivB = SortRecord.Pages THEN
		 (* create user file *)
		 SortRecord.F := FIO.Create( SortRecord.FileName ) ;
		 IF FIO.IOresult() <> 0 THEN
		    SortRecord.Error := 12
		 ELSE
		    SortRecord.FileCreated := TRUE
		 END; (* Fill page 0 to Pages-2 *)
		 FOR I := 0 TO SortRecord.Pages-2 DO
			(* was: SortPut(Ptr(Dseg(), 0), I) *)
			SortPut( SortRecord.Buf[I], I )
		 END;
	      END; (* Write user record in last page *)
	      SortPut(SortRecord.Buf[SortRecord.Pages-1], SortRecord.Page[SortRecord.Pages-1]);
	      INC( SortRecord.Page[SortRecord.Pages-1] ) ;
*)	
	   END;
(*	   IF VAL(CARDINAL,SortRecord.NDivB) >= SortRecord.Pages THEN
		BufNo := SortRecord.Pages-1
	   ELSE
		BufNo := SortRecord.NDivB
	   END;
*)	
(*	   Point := Ptr(Seg(ADR(SortRecord.Buf[BufNo]^)), Ofs(ADR(SortRecord.Buf[BufNo]^))+SortRecord.NModB*SortRecord.
		  ItemLength); *)
           BufNo := SortRecord.NDivB ;
	   WITH SortRecord DO  Point := ADR( Buf[BufNo]^[ VAL(CARDINAL,NModB) * ItemLength] );  END ;
	   Move(ADR(ReleaseRecord), Point, SortRecord.ItemLength);
	   INC(SortRecord.N);
	   INC(SortRecord.NModB);
	   IF SortRecord.NModB = VAL(CARDINAL,SortRecord.B) THEN
		SortRecord.NModB := 0;
		INC(SortRecord.NDivB) ;
                ALLOCATE( SortRecord.Buf[SortRecord.NDivB] , PageSize ) ;
	   END;
	END;
    END LSortRelease;


(* Return record to user *)
PROCEDURE LSortReturn( VAR ReturnRecord: ARRAY OF BYTE);
   VAR
	AuxAddr		: SortPointer;
	IxPage, IxOfs	: CARDINAL;
	BytesRead	: CARDINAL;
   BEGIN
	IF SortRecord.Error = 0	THEN
(*		SortFetchPage(SortRecord.Udix, SortRecord.N-1, SortRecord.B );
		SortFetchAddr(SortRecord.Udix, AuxAddr); *)

		(* use one buffer page to access all the sorted data from disk *)
		IxPage := VAL(CARDINAL, SortRecord.Udix DIV SortRecord.B ) ;
		IxOfs  := VAL(CARDINAL, SortRecord.Udix MOD SortRecord.B);
(*		IF IxPage <> SortRecord.Page[0] THEN
		   (* not in memory -- bring page in *)
		   IF SortRecord.Error = 0 THEN
		      FIO.Seek(SortRecord.F, VAL(LONGCARD,IxPage) * VAL(LONGCARD,PageSize) );
		      BytesRead := FIO.RdBin(SortRecord.F, SortRecord.Buf[0]^, PageSize );
		      IF FIO.IOresult() <> 0 THEN
			 SortRecord.Error := 11 ; (* read error *)
			 RETURN ;
		      END ;
		      SortRecord.Page[0] := IxPage;
		   END;
		END ;
*)
		AuxAddr := ADR( SortRecord.Buf[IxPage]^[ IxOfs * SortRecord.ItemLength ] );

		Move(AuxAddr, ADR(ReturnRecord), SortRecord.ItemLength);
		INC(SortRecord.Udix) ;
	END
   END LSortReturn;


(* Returns True if all records are returned *)
PROCEDURE LSortEOS(): BOOLEAN;
   BEGIN
	RETURN (SortRecord.Udix >= SortRecord.N) OR (SortRecord.Error <> 0);
   END LSortEOS;

BEGIN
      LSortFree	:= TRUE; (* *LP* *)
      SpaceReserved := 0 ;
END LongSort.
