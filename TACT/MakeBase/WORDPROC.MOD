IMPLEMENTATION MODULE WordProcessing ;

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

(*--------------------------------------------------------------------------*)
(* By:    Lidio Presutti                                                    *)
(* Date:  Feb. 16, 1988                                                     *)
(* Purpose:                                                                 *)
(*                                                                          *)
(* History:                                                                 *)
(*  16 Feb 88, Lidio Presutti                                               *)
(*     - made changes to various array references to be zero based.         *)
(*  1 June 88, Lidio Presutti                                               *)
(*     - removed "Word" from Typedata definition since same as balance key. *)
(*  7 June 88, Lidio Presutti                                               *)
(*     - reflect changes to TokenData.DEF.                                  *)
(*  10 Aug 88, John Bradley                                                 *)
(*     - removed use of REAL arithmetic                                     *)
(*                                                                          *)
(*--------------------------------------------------------------------------*)

(*V1=Production *)
(*V2=Debug WordBase translations *)
(*V3=Trace *)

FROM SYSTEM IMPORT TSIZE, ADDRESS, ADR ;
FROM Str    IMPORT Length, Copy ;
(* m.s. FROM VirtualMemory IMPORT
  (* Procs *) AllocateSpace, MakeReal, ReleasePage, MarkDirty,
              MarkInUse, GetDumpVirtPage, IsEqual, InitSpaceType,
  (* Vars  *) VirtNil,
  (* Type  *) VirtualAddrType, VirtPageStorePtr ;
*)
FROM VirtualMemory IMPORT
  (* Procs *) AllocateSpace, MakeReal, IsEqual, InitSpaceType,
  (* Vars  *) VirtNil,
  (* Type  *) VirtualAddrType, VirtPageStorePtr ;
FROM BalancedTrees IMPORT
  (* type *)  BalTreeItemProcess, BTDataPtr,
  (* proc *)  InitialBT, FindBTItem, AddBTItem, ProcessBT, MakeListItem, AddListItem ;
FROM VirtHash IMPORT
  (* Procs *) InsertHash, SearchHashTable, FreeHashMemory ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt ;
FROM TokenDataSource IMPORT
  (* Const *) NumbTokensInList, NumbOccursInList, BaseTypeDataLen,
  (* Types *) TypeData, TypeDataPointer, TokenData, TokenListData, TokenListPointer,
              OccurrenceData, OccurrenceListPointer, OccurrenceListData,
  (* Vars  *) RecordNumber, TokenNumber, TypeNumber, HeadWordHeader,
              TokenListStart, CurrTokenArray, CurrTokenPos, BeginToken,
              VTokenListStart, VCurrTokenArray, NoTypes,
              BeginOccur, BeginType, BeginText, BeginIndex,
              EndTextRec, EndTextIdx, EndTypeRec, EndTypeIdx,
              EndTokenRec, EndTokenIdx, BeginStr, EndStr,
              BeginStrRec, NoStrRecs,
  (* Vars  *) InputFileID ;
FROM LogFile IMPORT
  (* Types *) LogListPtr,
  (* Vars  *) VWordLogEntry,
  (* Procs *) AddNoToLogList, AddStrToLogList ;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny ;
FROM RunPan IMPORT
  (* Procs *) PutTokenCount, PutTypeCount, WriteTextWindow, PutRunStatus,
		PutPercentage ;
FROM DBFile IMPORT
  (* Vars  *) HRecord, HRecNo, HRecPos,
  (* Procs *) WriteDBRec, AddTextToDB, AddOccurToDB, AddTokenToDB,
              AddTypeDataToDB, InitTypeDataToDB, FinishTypeDataToDB ;
FROM XlatUserInput IMPORT
  (* Const *) WordSepCode, MaxNumbResets,
  (* Types *) CounterPtr,
  (* Vars  *) WordCounterPtr, LineCounterPtr;
FROM WordBase IMPORT
  (* Const *) ExtraCodeSep,
  (* Types *) AlphaCharType,
  (* Vars  *) TypeOfChar, SortNoBitsPerChar,
  (* Procs *) (*<Debug SortToFullWord, SortToIntWord, Debug>*) FullToSortWord ;
FROM HyperDataModel IMPORT
  (* Const *) HyperLength, PastHeader, HNoOccurs, HNoTokens, HNoDataPtrs,
              HNoPDBWords, BaseHTypeLen, MaxSpaceForOccursInRec,
              OccurRecSize, TypeMaxDataPos,
  (* Type  *) HTypeData;
FROM ResMessages IMPORT GetResMessage;
(*<Trace IMPORT Trace ; Trace>*)

VAR
  CurrentWord : StrAny ;
  Message     : StrAny ;
  MsgPos      : CARDINAL ;
  VTempNext   : VirtualAddrType ;
  TypeLinkedList : VirtualAddrType ;

  VTypeUnusedSpace  : VirtualAddrType ;
  VTokenUnusedSpace : VirtualAddrType ;
  VOccurUnusedSpace : VirtualAddrType ;

  TRecNo   : CARDINAL ;
  TRecPos  : CARDINAL ;
  TPtrLen  : INTEGER  ;   (* pos in HyperRec from start *)
  TDataPos : INTEGER  ;   (* pos in HyperRec from end   *)
  Dummy    : ADDRESS ;

  TokenRecCounter : CARDINAL ;
  TokenPosCounter : CARDINAL ;

  NumberOccurs	  : LONGCARD ;
  Count		  : LONGCARD;
  TotCount	  : LONGCARD;
  LastPercentage,
  Percentage	  : CARDINAL ;

PROCEDURE MakeOccurList( VAR NP     : VirtualAddrType ;
                         VAR NPReal : OccurrenceListPointer ) ;
   VAR
      I : CARDINAL ;
   BEGIN
      AllocateSpace( NP, NPReal, VOccurUnusedSpace, TSIZE( OccurrenceListData ) ) ;
      INC( NumberOccurs ) ;
      WITH NPReal^ DO
         Next := VirtNil ;
         FOR I := 1 TO NumbOccursInList DO
            WITH OccurA[I] DO
               TokenRecNo  := MAX(CARDINAL) ;  (* not initialised value *)
               TokenRecPos := MAX(CARDINAL) ;
            END
         END ;
      END ;
   END MakeOccurList ;

PROCEDURE MakeTokenEntry( VAR NP     : VirtualAddrType ;
                          VAR NPReal : TokenListPointer ) ;
   VAR
      I : CARDINAL ;
   BEGIN
      AllocateSpace( NP, NPReal, VTokenUnusedSpace, TSIZE(TokenListData) ) ;
      WITH NPReal^ DO
         Next := VirtNil ;
         FOR I := 1 TO NumbTokensInList DO
            WITH TokenA[I] DO
               VWordType := VirtNil ;
               VLogPtr   := VirtNil ;
               TRecNo   := 0 ;
               TRecPos  := 0 ;
            END
         END ;
      END ;
      (* ReleasePage( NP, Dummy ) ;  ??? *)
   END MakeTokenEntry ;

PROCEDURE MakeTypeData( VAR NP     : VirtualAddrType ;
                        VAR NPReal : TypeDataPointer ) ;
VAR Dummyt:   OccurrenceListPointer;
   BEGIN
      AllocateSpace(NP, NPReal, VTypeUnusedSpace, BaseTypeDataLen ) ;
      WITH NPReal^ DO
         KRecPos  := 0 ;
         KRecNo   := 0 ;
         NoOccurs := 0 ;
         MakeOccurList( VOccurList, Dummyt ) ;
(*         ReleasePage( VOccurList, Dummy ) ; (* only need virtual addr. *) *)
         VOccurListEnd := VOccurList ;
      END ;
      INC( TypeNumber ) ;
      (* PutTypeCount( TypeNumber ) ; moved to ProcessT.MOD : ReadLine *)
    END MakeTypeData ;

PROCEDURE LocateHWType(     CurrentWord : ARRAY OF CHAR ;
                        VAR VThisType   : VirtualAddrType ;
                        VAR ThisType    : TypeDataPointer ) ;
  VAR
     p, s, t: VirtualAddrType ;
     Dummy  : BOOLEAN ;
     HashId : LONGINT ;
  BEGIN
     IF SearchHashTable( CurrentWord, VThisType, HashId) THEN
        MakeReal( VThisType, ThisType )
     ELSE
        MakeTypeData( VThisType, ThisType ) ;
        MakeListItem( TypeLinkedList, CurrentWord, VThisType, VTypeUnusedSpace, p ) ;
	InsertHash( HashId, p (* = last BalTree node created *) ) ;
     END ;
  END LocateHWType ;


PROCEDURE ProcessCollectedWord( CompleteWord   : ARRAY OF CHAR ;
                                SWdRec, SWdPos : CARDINAL ;
                                SWdRecNo       : LONGCARD ) ;
  VAR
     ThisType   : TypeDataPointer ;
     VThisType  : VirtualAddrType ;
     NTP        : TokenListPointer ;
     VNTP       : VirtualAddrType ;
     OLP        : OccurrenceListPointer ;
     VOLP       : VirtualAddrType ;
     OLP2       : OccurrenceListPointer ;
     VOLP2      : VirtualAddrType ;
     SortWord   : StrAny ;
     (*<Debug
     IntWord,
     FullWord   : StrAny ;   Debug>*)
     WrkPos	: CARDINAL ;
  BEGIN
     FullToSortWord( CompleteWord, SortWord ) ;
     IF (SortWord[0] = WordSepCode) OR
        (SortWord[0] = ExtraCodeSep) THEN
        RETURN  (* only contained retained diacritics, ignore it *)
     END ;

     (* >>> the following is for debugging WordBase translations <<< *)
     (*<Debug
     SortToIntWord( SortWord, IntWord ) ;
     WriteTextWindow( IntWord ) ;
     SortToFullWord( SortWord, FullWord ) ;
     SortToIntWord( FullWord, IntWord ) ;
     WriteTextWindow( IntWord ) ;
     Debug>*)
     LocateHWType( SortWord, VThisType, ThisType ) ;
     INC( ThisType^.NoOccurs ) ;
(* m.s.    MarkDirty( VThisType ) ; *)
     INC( CurrTokenPos ) ;
     IF CurrTokenPos > NumbTokensInList THEN
        MakeTokenEntry( VNTP, NTP ) ;
        CurrTokenArray^.Next := VNTP ;
(* m.s.        ReleasePage( VCurrTokenArray, CurrTokenArray ) ; *)
        VCurrTokenArray := VNTP ;
        CurrTokenArray  := NTP ;
        CurrTokenPos := 1 ;
     END ;
     WITH CurrTokenArray^.TokenA[CurrTokenPos] DO
        VWordType := VThisType ;
        VLogPtr   := VWordLogEntry ;
        TRecNo    := SWdRec ;
        TRecPos   := SWdPos ;
     END ;
     VOLP := ThisType^.VOccurListEnd ;
     MakeReal( VOLP, OLP ) ;
     WITH OLP^ DO
        WrkPos := 1 ;
        WHILE (WrkPos < NumbOccursInList) AND (OccurA[WrkPos].TokenRecNo <> MAX(CARDINAL) ) DO
           INC( WrkPos )
        END ;
        IF OccurA[WrkPos].TokenRecNo <> MAX(CARDINAL) THEN
           MakeOccurList( VOLP2, OLP2 ) ;
           ThisType^.VOccurListEnd := VOLP2 ;
(* m.s.           MarkDirty( VThisType ) ; *)
           OLP^.Next := VOLP2 ;
(* m.s.           MarkDirty( VOLP ) ;
           ReleasePage( VOLP, OLP ) ; *)
           VOLP := VOLP2 ;
           OLP := OLP2 ;
           WrkPos := 1 ;
        END ;
     END ;
     WITH OLP^.OccurA[WrkPos] DO
        TokenRecNo  := TokenRecCounter ;
        TokenRecPos := TokenPosCounter ;
        INC( TokenPosCounter ) ;
        IF TokenPosCounter >= HNoTokens THEN
           INC( TokenRecCounter ) ;
           TokenPosCounter := 0 ;
        END ;
     END ;
(* m.s.     MarkDirty( VOLP ) ;
     ReleasePage( VOLP, OLP ) ;
     ReleasePage( VThisType, ThisType ) ;
*)
     INC( TokenNumber ) ;
     (* PutTokenCount( TokenNumber ) ;  moved to ProcessT.MOD : ReadLine *)
  END ProcessCollectedWord ;


PROCEDURE InitWordColl() ;
  BEGIN
     InitSpaceType( VTypeUnusedSpace ) ;  (* was in MODULE BEGIN area *)
     InitSpaceType( VTokenUnusedSpace ) ;
     InitSpaceType( VOccurUnusedSpace ) ;

     TypeLinkedList := VirtNil ;
     MakeTokenEntry( VTokenListStart, TokenListStart ) ;
     VCurrTokenArray := VTokenListStart ;
     CurrTokenArray  := TokenListStart ;
  END InitWordColl ;


(* Global Procedures that are used as parameters  *)

(*----------------------------------------------------------------------*)
(* Structure of TypeData on Hyper record:                               *)
(*                                                                      *)
(* - a count for a number of elements in (the following) array of pos.  *)
(* - an array of position of which there are actually "count" valid     *)
(*   entries.  The position indicate where the start of TypeData        *)
(*      :                                                               *)
(* - from end of Hyper record, TypeData are added to fill up to last    *)
(*   valid array entry.                                                 *)
(*                                                                      *)
(*----------------------------------------------------------------------*)
PROCEDURE CalcTypeDataSpace( Key       : ARRAY OF CHAR ;
                             VWordType : VirtualAddrType ) ;
   VAR
      P			: TypeDataPointer ;
      TypeLen		: CARDINAL;
      SpaceForOccurs	: LONGINT ;
      NBits, NBytes	: CARDINAL ;
   BEGIN
      INC(Count);
      Percentage := VAL(CARDINAL,Count * VAL(LONGCARD,100) DIV TotCount) ;
      IF Percentage >= LastPercentage THEN
	 PutPercentage( Percentage, TRUE ) ;
	 INC(LastPercentage, 4) ;
      END ;
      MakeReal( VWordType, P ) ;
      WITH P^ DO
	 NBits := Length( Key ) * SortNoBitsPerChar ;
	 NBytes := (NBits+7) DIV 8 ;
         TypeLen := BaseHTypeLen + NBytes ;  (* <<< compress Key later >>> *)
         INC(TPtrLen, 2) ;
         DEC(TDataPos, TypeLen ) ;
         IF TDataPos < TPtrLen THEN
            INC(TRecNo) ;
            TRecPos := 1 ;
	    TPtrLen := 6 ;  (* = NoDataPntrUsed + 0th ptr + 1st ptr = 2 + 2 + 2 *)
	    TDataPos := TypeMaxDataPos - TypeLen ;
         END ;
	 (*<Trace
	 Trace.TWriteCard(TRecNo,5);
	 Trace.TWriteCard(TRecPos,5);
	 Trace.TWriteCard(TPtrLen,5);
	 Trace.TWriteCard(TDataPos,5);
	 Trace.TWriteCard(TypeLen,3);
	 Trace.TWriteLn ;
	 Trace>*)
         KRecNo := TRecNo ;
         KRecPos := TRecPos ;
         INC(TRecPos) ;
	 SpaceForOccurs := LONGINT(NoOccurs) * OccurRecSize ;
	 IF LONGINT(TDataPos - TPtrLen) < SpaceForOccurs THEN
	    (* will not completely fit on current record *)
	    DEC( SpaceForOccurs, LONGINT((TDataPos - TPtrLen) DIV OccurRecSize) * OccurRecSize ) ;
	    (* place rest on subsequent records *)
	    INC( TRecNo ) ;
	    WHILE SpaceForOccurs >= MaxSpaceForOccursInRec DO
		(* fill up whole of next record *)
		INC( TRecNo ) ;
		DEC( SpaceForOccurs, MaxSpaceForOccursInRec ) ;
	    END ;
            TRecPos  := 1 ;
	    TDataPos := TypeMaxDataPos ;
	    TPtrLen  := 4 ; (* was 8; add 2 later for correct offset! *LP* *)
	 END ;
	 DEC( TDataPos, CARDINAL(SpaceForOccurs) ) ;
      END ;
(*  m.s.    MarkDirty( VWordType ) ;
      ReleasePage( VWordType, P ) ;
*)
   END CalcTypeDataSpace ;

PROCEDURE AssignTypePos() ;
   BEGIN
      TRecNo  := 0 ;
      TRecPos := 2 (* was: 1, account for 1st dummy type *LP* *) ;
      TDataPos := TypeMaxDataPos - BaseHTypeLen - 1; (* account for 1st rec *)
      TPtrLen := 6 ;  (* = NoDataPntrUsed + 0th ptr + 1st ptr = 2 + 2 + 2 *)
      Count := VAL(LONGCARD,0);
      TotCount := VAL(LONGCARD,TypeNumber);
      LastPercentage := 0 ;
      (*<Trace
      Trace.TWriteString("AssignTypePos:");
      Trace.TWriteLn ;
      Trace>*)
      ProcessBT( HeadWordHeader, CalcTypeDataSpace ) ;
   END AssignTypePos ;

PROCEDURE ProcessThisOL( VP : VirtualAddrType ) ;
   VAR
       VPNext   : VirtualAddrType ;
       P : OccurrenceListPointer ;
       L : [1..NumbOccursInList] ;
   BEGIN
       WHILE NOT IsEqual(VP, VirtNil) DO
          INC(Count);
          Percentage := VAL(CARDINAL,Count * VAL(LONGCARD,100) DIV TotCount) ;

	  IF Percentage >= LastPercentage THEN
	     PutPercentage( Percentage, TRUE ) ;
	     INC( LastPercentage, 2 ) ;
	  END ;
          MakeReal( VP, P ) ;
          FOR L := 1 TO NumbOccursInList DO
             WITH P^.OccurA[L] DO
                IF TokenRecNo <> MAX(CARDINAL) THEN
                   AddOccurToDB( TokenRecNo, TokenRecPos ) ;
                END
             END  (* WITH P^.OccurA[L] DO *)
          END ;
          VPNext := P^.Next ;
(* m.s.         ReleasePage( VP, P ) ; *)
          VP := VPNext ;
       END ;
   END ProcessThisOL ;

PROCEDURE DoTypes( Key : ARRAY OF CHAR ;
                   VP  : VirtualAddrType ) ;
   VAR
      P         : TypeDataPointer ;
      HTypeRec  : HTypeData;
   BEGIN
      MakeReal( VP, P ) ;
      WITH P^ DO
         Copy( HTypeRec.Word, Key ) ;
         HTypeRec.NoOccur := NoOccurs ;
         AddTypeDataToDB( HTypeRec ) ;
         INC(NoTypes) ;
         ProcessThisOL( VOccurList ) ;
      END ;
(* m.s.      ReleasePage( VP, P ) ; *)
   END DoTypes ;

PROCEDURE WritePntrData() ;
  VAR
     SizeLeft : CARDINAL ;

  PROCEDURE WriteTokenData ;
     VAR
        LogPtr   : LogListPtr ;
        WordType : TypeDataPointer ;
        I        : CARDINAL ;
     BEGIN
	(* ensure first call to AddTokenToDB will start with a new record j.b. *)
        IF HRecPos =  0 THEN (* m.s. - start of a new record already *)
           BeginToken := HRecNo ; (* m.s. if - then else and this line new*)
        ELSE
           BeginToken := HRecNo + 1;
        END ;
	HRecPos := HNoTokens + 1 ;
        VCurrTokenArray := VTokenListStart ;
        Count := VAL(LONGCARD,0);
        TotCount := VAL(LONGCARD,TokenNumber);

        LastPercentage := 0 ;
        WHILE NOT IsEqual(VCurrTokenArray, VirtNil) DO
           Percentage := VAL(CARDINAL,Count * VAL(LONGCARD,100) DIV TotCount) ;
	   IF Percentage >= LastPercentage THEN
	      PutPercentage( Percentage, TRUE ) ;
	      INC( LastPercentage, 4 ) ;
	   END ;
           MakeReal( VCurrTokenArray, CurrTokenArray ) ;
           WITH CurrTokenArray^ DO
              FOR I := 1 TO NumbTokensInList DO
                 WITH TokenA[I] DO
                    IF NOT IsEqual( VWordType, VirtNil) THEN
                       MakeReal( VLogPtr, LogPtr ) ;
                       MakeReal( VWordType, WordType ) ;
                       INC(Count);
                       AddTokenToDB( WordType^.KRecNo,  (* HRecNo *)
                                     CHR(WordType^.KRecPos), (* HRecPos *)
                                     TRecNo, TRecPos,
                                     LogPtr^.LRecNo, LogPtr^.LRecPos ) ;
(* m.s.                       ReleasePage( VWordType, WordType ) ;
                       ReleasePage( VLogPtr, LogPtr ) ;
*)
                    END ;
                 END (* WITH TokenA[I] DO *)
              END ;
              VTempNext := Next ;
           END (* WITH CurrTokenArray^ DO *) ;
(* m.s.          ReleasePage( VCurrTokenArray, CurrTokenArray ) ; *)
           VCurrTokenArray := VTempNext ;
        END ;
	PutPercentage( Percentage, TRUE ) ;  (* last value *)
        EndTokenRec := HRecNo ;
        EndTokenIdx := HRecPos - 1 ;  (* *LP* *)
        WriteDBRec ;
     END WriteTokenData ;

  PROCEDURE SortTypeData ;
     VAR
	Node, NextNode  : VirtualAddrType ;
	Node1		: BTDataPtr ;
	p, s, t,
	VThisType	: VirtualAddrType ;
	dummy		: BOOLEAN ;
	(*<Debug
	IntWord		: StrAny ;
	Debug>*)
     BEGIN
	VThisType := VirtNil ;	  (* not really used here *)
	Node := TypeLinkedList ;  (* link list thread *)
	InitialBT( HeadWordHeader, VTypeUnusedSpace );  (* start the balanced tree *)
        Count := VAL(LONGCARD,0);
        TotCount := VAL(LONGCARD,TypeNumber);
        LastPercentage := 0 ;
	WHILE NOT IsEqual(Node, VirtNil) DO
           Percentage := VAL(CARDINAL,Count * VAL(LONGCARD,100) DIV TotCount) ;
	   IF Percentage >= LastPercentage THEN
	      PutPercentage( Percentage, TRUE ) ;
	      INC( LastPercentage, 2 ) ;
	   END ;
	   INC( Count ) ;
	   MakeReal( Node, Node1 ) ;
	   (*<Debug
	   SortToIntWord( Node1^.Key, IntWord ) ;
	   WriteTextWindow( IntWord ) ;
	   Debug>*)
	   NextNode := Node1^.LLink ;  (* link list thread thru all type records *)
	   Node1^.LLink := VirtNil ;
(* m.s.	   MarkDirty( Node ) ; *)
	   dummy := FindBTItem( HeadWordHeader, Node1^.Key, VThisType, p, s, t ) ;
	   AddListItem( HeadWordHeader, Node1^.Key, Node, p, s, t ) ;
(* m.s.	   ReleasePage( Node, Node1 ) ; *)
	   Node := NextNode ;
	END ;
	PutPercentage( Percentage, TRUE ) ;
     END SortTypeData ;

  PROCEDURE WriteTypeData ;
     VAR
      HTypeRec  : HTypeData;
     BEGIN
	(*<Trace
	Trace.TWriteString(" "); (* blank line *)
	Trace.TWriteLn ;
	Trace.TWriteString("WriteTypeData:");
	Trace.TWriteLn ;
	Trace>*)
        NoTypes := 0 ;
        InitTypeDataToDB() ;
        BeginType := HRecNo ;

	(* J.B.: First add dummy header record *)
        WITH HTypeRec DO
           NoOccur := 0;
           Word := 0C;
        END;
        AddTypeDataToDB( HTypeRec ) ;

	(*  Now, Write out real data *)
        Count := VAL(LONGCARD,0);
        TotCount := VAL(LONGCARD,NumberOccurs);
        LastPercentage := 0 ;

        ProcessBT( HeadWordHeader, DoTypes ) ;
	PutPercentage( Percentage, TRUE ) ;

	(*  Now, Write out trailing data *)
        WITH HTypeRec DO
           Word[0] := 377C;
           Word[1] := 0C;
        END;
        AddTypeDataToDB( HTypeRec ) ;

        EndTypeRec := HRecNo ;
        EndTypeIdx := HRecPos - 1;
        FinishTypeDataToDB() ;
     END WriteTypeData ;

  BEGIN (* WritePntrData *)
     WriteTextWindow( '' ) ;
     WriteTextWindow( '-------------------' ) ;

     FreeHashMemory ;

     (*RES OLD MSG 102
     *** Input of text has ended. ***
     *)
     GetResMessage( (*RES REM INS*) 102, Message);
     WriteTextWindow( Message ) ;

     (*RES OLD MSG 310
     Now sorting Word-type data.
     *)
     PutRunStatus( (*RES REM INS*) 310 );
     SortTypeData ;

     (*RES OLD MSG 103
     Now preparing index pointers.
     *)
     PutRunStatus( (*RES REM INS*) 103 );
     AssignTypePos ;

     (*RES OLD MSG 122
     Writing Word-token data to TDB.
     *)
     PutRunStatus( (*RES REM INS*) 122 );
     WriteTokenData ;

     (*RES REM DEL MSG 123
     Writing Occurrence Data to DB.
     *)
(*
     PutRunStatus( (*RES REM INS*) 123 );
     WriteOccurData ;
*)

     (*RES OLD MSG 124
     Writing Type and Occurrence data to TDB.
     *)
     PutRunStatus( (*RES REM INS*) 124 );
     WriteTypeData ;
  END WritePntrData ;

BEGIN
(*
  InitSpaceType( VTypeUnusedSpace ) ;   >>> moved to InitWordColl <<<
  InitSpaceType( VTokenUnusedSpace ) ;
  InitSpaceType( VOccurUnusedSpace ) ;  *)

  TokenRecCounter := 0 ;
  TokenPosCounter := 0 ;
  NumberOccurs	  := VAL( LONGCARD, 0 ) ;
END WordProcessing .

