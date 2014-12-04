IMPLEMENTATION MODULE RUNSource ;

(* copyright (c) 1987-96 John Bradley, Lidio Presutti, Mike Stairs, University of Toronto *)

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
(*V2=Debug *)
(*V3=Trace *)

(*<Trace IMPORT Trace ; Trace>*)
(*<Debug IMPORT IO ; Debug>*)

IMPORT BitOps, WordBase ;
IMPORT FIO, Lib, TWB, MATHLIB, Str ;
FROM ResMessages IMPORT
   (* proc *)  MsgString, MsgCard, PutResError, PutResWarning, ResAskUser, GetResMessage;
FROM ResMenus IMPORT
  (* type *)  MenuID,
  (* proc *)  StartMenu, CardField, CharField, MakeMenu, DestroyMenu, GetFieldInfo,
		ClearMenuArea, ShowFixedText, ShowMenu;
FROM Str IMPORT Length, Copy, Pos, ItemS, Slice, Compare, StrToCard, CardToStr ;
FROM SYSTEM IMPORT TSIZE, SIZE ;
FROM StringIO IMPORT SWriteString, SWriteChar, SWriteCard, SWriteLongInt ;
FROM Storage IMPORT  Available, ALLOCATE       , DEALLOCATE, MainHeap, HeapAvail, HeapTotalAvail ;
FROM HyperDataModel IMPORT HRecPntr, HyperData, HyperLength, HNoTokens,
                           MaxNoLogData, TDBTypePntr;
FROM ErrorBase IMPORT
  (* Proc *) ProgramErrorAndHalt;
FROM GlobalDefs IMPORT FileNameType, StrAny ;
FROM WordBase IMPORT SortToIntWord, IntToSortWord, FullToSortWord ;
FROM KeyTranslation IMPORT
  (* Const *) IntEnhOn, IntEnhOff, IntTab,
  (* Type  *) TabInfo, TabType,
  (* Procs *) WriteScreenField ;
FROM Windows  IMPORT
  (* Const *) RegularAttr ;
FROM Translations IMPORT
 (* type *) XFileType, CurrentModeType, LengthDataType,
 (* proc *) XWriteLine, XClose, XWrStr, XWrNXlate, XWrLn, XReadLine, XOpenInput,
            XOpenOutput, XlateLine,
 (* vars *) Int2Alp, LenD ;
FROM Utils IMPORT BDelete, BOpen, BCreate, RWType, ReadLine,
           BFile, WrStr, WrLn, BClose, TrimBlanks;
FROM UtilsTwo IMPORT IOErrorMessage;
FROM DiskDirectory IMPORT
 (* procs *) DiskFree, CurrentDrive ;
FROM PrintModule IMPORT PrintMaster, PrintProcType, PrintActionType,
		AbortProc, AbortForFileIO, WriteWithTabs;

FROM StartUp IMPORT
  (* Vars *) FileData, OutFileID, RuleFileID, CollModePresent, Boundaries,
             FunctionFileID, NodeCollocateOnly (* m.s. *) ,
             FunctionType (* m.s. *), NodeCollFileID, Tabs, Spaces,
             FrequencyFileID, CollMode, FunctionWords, RuleMode ;

FROM TDBInit IMPORT
    (* vars  *) TDBFileID, CORFileID, UsingCorpusFile, HROffset,
		BeginCorpusType, EndCorpusTypeRec, MaxRefID (* m.s. *),
                BeginType, BeginToken, EndTypeRec, EndTypeIdx,
                EndTokenRec, EndTokenIdx, NoTypes, LastAlphChar,
		NumbFiles, TDBDir, TDBFileNames, BeginLog, EndLog, RefArray,
    (* procs *) OpenTDB ;
FROM LongSort IMPORT
  (* Procs *) LTurboSort, LSortRelease, LSortReturn, LSortEOS, LSortReset,
              LSortGetPos, SpaceReserved ;

FROM VirtHash IMPORT
  (* Types *) SequenceType , SequencePtr,
  (* Vars  *) VSequenceUnusedSpace,
  (* Const *) SequenceSize,
  (* Procs *) InsertHash, SearchHashTable, FreeHashMemory, InitVirtHash,
              DumpHash ;

FROM VirtualMemory IMPORT InitSpaceType, InitVirtualMemory, EndVirtualMemory ;

FROM SortLine IMPORT IntToSimpleSortLine, IntToSortLine, IntToSimpleWord ;

CONST
   YPosForStatusMenu = 21;  (* m.s. - was 19 *)

(*RES OLD MNU 32
 Status: %0_________________________________________________________________
 Percentage Completed: %1_ % [Estimated]
 *)

   StatusMenuResID = (*RES REM INS*) 32 ;

   FileHeaderResource = 113 ;	(* >> MSG defined in MAKBAS: SetupFil.MOD << *)

CONST
   MaxCARDINAL = MAX(INTEGER) DIV TSIZE(HRecPntr) - 100 ;  (* any large number will do *)

TYPE
   StrAnyPtr = POINTER TO StrAny ;
   DataTypePtr = POINTER TO DataType ;
   DataType = RECORD
		CASE : BOOLEAN OF
		  | TRUE :
			KeyWord	: HRecPntr ;
			position: CARDINAL ;
			Context	: ARRAY[1..MaxCARDINAL] OF HRecPntr ;
		  | FALSE :
			ptr	: ARRAY[1..MaxCARDINAL] OF CARDINAL;
		END ;
   	      END ;
         TypeRecPntr = POINTER TO TypeRecType ;
   TypeRecType = RECORD
		    RecNo	: CARDINAL ;
		    HRecord	: HyperData ;
		    Next	: TypeRecPntr ;
		END ;

   TypeBitIdx = SET OF [0..255] ;  (* allow room for later -- compressions; really need <= 102 *)
   TypeBitIdxPntr = POINTER TO TypeBitIdx ;
   TypeBitRecType = RECORD
			Set	: TypeBitIdxPntr ;
			SetLen	: SHORTCARD ;
		END ;
   TypeBitRec = ARRAY[0..MaxCARDINAL] OF TypeBitRecType ;

   PresentBitSetType = SET OF [0..255];   (* for corpus *)

   (* establish types for HRecPntr map translations *)
   XRecInfoData = ARRAY[0..255] OF HRecPntr ;
   XRecInfo = RECORD
      Size:    CARDINAL;
      NewLoc:  XRecInfoData;
   END;
   XRecInfoPntr = POINTER TO XRecInfo;
   ToRecDataType = RECORD
      Size:    CARDINAL;
      RecData: ARRAY[0..2000] OF XRecInfoPntr;
   END;
   ToRecPntrType = POINTER TO ToRecDataType;

   ShortSequencePtr = POINTER TO ShortSequenceType ; (* m.s. *)
   ShortSequenceType = RECORD
      Text  : StrAny ;
      SortText : StrAny ;
      NoOccurs : CARDINAL ;
   END ;
   NodCollPairPtr = POINTER TO NodCollPairType ;
   NodCollPairType = ARRAY[0..1] OF LONGCARD ; (* m.s.*)


VAR
   DataRecSize	: CARDINAL ;
   RecNo	: CARDINAL ;
   RecIdx	: CARDINAL ;
   HRecord	: POINTER TO HyperData ;
   HRecordLog   : POINTER TO HyperData ;   (* m.s. - to hold Log info simultaneously with token info *)
   HRecLogPos   : CARDINAL ;  (* m.s. *)
   HRecLogNo    : CARDINAL ;  (* m.s. *)
   CurTokenPos        : LONGCARD ;   (* m.s. *)
   CurTokenLogPos        : LONGCARD ;   (* m.s. *)
   CheckColl : BOOLEAN ;

   NoNodCollPairs : LONGCARD ;
   MaxCardsInContext : CARDINAL ;

   PrevNodCollPair : NodCollPairPtr ;
   NodCollOccurs : LONGCARD ; (* m.s. *)
   NodCollOutFile  : BFile ;
   PrevCol         : LONGCARD ;

   HeadTRec	: TypeRecPntr ;
   Percentage	: CARDINAL ;
   LastPercentage : CARDINAL ;
   Count	: LONGCARD ;
   NoSortRecs	: LONGCARD ;
   NoCompares   : LONGCARD ;
   NoTokens, TotalNoTokens	: LONGCARD ;
   NoOutputRecs : LONGCARD ;
   TheFileID : FIO.File ; (* m.s. - moved from GetOutput *)

   StatsWind	: TWB.WinType ;
   LenStatus	: CARDINAL ;
   PosXStatus	: CARDINAL ;
   PosYStatus	: CARDINAL ;
   PosXPerCent	: CARDINAL ;
   PosYPerCent	: CARDINAL ;
   MsgTxt	: StrAny;
   CollDisplayTab: ARRAY[0..0] OF TabInfo;

   TypeTable, FunctionTable	: POINTER TO TypeBitRec ;

(* m.s.
   (* for corpus *)
   NumbOfEntries : CARDINAL ;
   Present	: POINTER TO PresentBitSetType ;
   WordPtr	: POINTER TO BitOps.PackedStrType ;
   NoOccurs	: POINTER TO ARRAY[0..255] OF CARDINAL;
   TypePos	: POINTER TO ARRAY[0..255] OF HRecPntr ;
   EncodedEntry : POINTER TO ARRAY[0..1023] OF CHAR;
   Entry	: ARRAY[0..1023] OF CHAR;
   Offset	: CARDINAL ;
   MaxNoTypeRecs: CARDINAL ;
   TypeMap	: ToRecPntrType ;
*)
   dummy	: BOOLEAN ;	(* <<<<---- just for now!! --->>> *)
   dumint       : LONGINT ;

CONST
    ShortSequenceSize  = TSIZE( ShortSequenceType ) ; (* m.s *)
    NodCollPairSize       = TSIZE( NodCollPairType ) ;
PROCEDURE PutRunStatus( ResID : CARDINAL );
   BEGIN
	GetResMessage(ResID,MsgTxt);
	WriteScreenField( StatsWind, LenStatus, PosXStatus,
			PosYStatus, MsgTxt, RegularAttr, TRUE ) ; (* m.s. - subbed 60 for LenStatus *)
   END PutRunStatus;


PROCEDURE PutHeapAvailable (From : ARRAY OF CHAR ) ;
  VAR
    x : CARDINAL ;
    (*<Trace
    BEGIN
      IF Trace.DoTrace THEN
	Trace.TWriteLn ;	(* flush out previous line if needed *)
        Trace.TWriteString( ' Total Heap memory available : ') ;
	Trace.TWriteCard( ((HeapTotalAvail( MainHeap) * 16) DIV 1024) , 0 ) ;
	Trace.TWriteString( 'K called from : ' ) ;
	Trace.TWriteString( From ) ;
	Trace.TWriteLn ;
    END ;
    Trace>*)
END PutHeapAvailable ;

PROCEDURE PutPercentage( N : CARDINAL ) ;
   VAR
	rc	: CARDINAL ;
	TempStr	: ARRAY[0..4] OF CHAR ;
   BEGIN
	rc := 0;
	TempStr[0] := 0C;
	SWriteCard(TempStr,rc,N,3);
	TWB.Use(StatsWind);
	TWB.GotoXY( PosXPerCent, PosYPerCent );
	TWB.WrStr(TempStr);
   END PutPercentage;

PROCEDURE Log2( Num : LONGCARD ) : CARDINAL ;
   VAR
	log2	: CARDINAL ;
	I	: CARDINAL ;
	Temp	: LONGCARD ;
   BEGIN (* calc the number bits in Num *)
	Temp := Num ;
	log2 := 0 ;	
	WHILE Temp <> 0 DO
	   INC( log2 ) ;
	   Temp := Temp DIV 2 ;
	END ;
	(*<Debug
	IO.WrStr( 'Number:' ) ;
	IO.WrLngCard( Num, 10 ) ;
	IO.WrStr( ' log2:' ) ;
	IO.WrCard( log2, 5 ) ;
	IO.WrLn ;
	Debug>*)
(*
	(* now take an upper bound if 2 ** log2  + 2 ** (log2 - 2) < Num *)
	(* ie. if Num is bigger than a quarter of log2 range		 *)
	Temp := 1 ;
	FOR I := 1 TO log2 DO
	   INC( Temp, Temp ) ;
	END ;
	IF Temp + (Temp DIV 4) < Num THEN
	   INC( log2 )
	END ;
*)
	RETURN log2
   END Log2 ;

(* m.s.
PROCEDURE GetNumbOfEntries( VAR NumbOfEntries : CARDINAL ) ;
    VAR	   I	: CARDINAL ;
    BEGIN
	NumbOfEntries := 0 ;
	FOR I := 0 TO NumbFiles - 1 DO
	   IF I IN Present^ THEN  INC( NumbOfEntries ) 	END ;
	END ;
    END GetNumbOfEntries;
*)

(* m.s. modified to handle node-collocate pairs *)

PROCEDURE SetTypeBitTable ;
   VAR
	Rec,I,J,K : CARDINAL ;
	BytesRead : CARDINAL ;
	TheSize : CARDINAL ;
	Limit	: CARDINAL ;
	Total	: LONGCARD ;
	Data	: TDBTypePntr ;
	WordPtr	  : POINTER TO BitOps.PackedStrType ;(* m.s.*)
	SortWord, CurrWord  : StrAny ;  (* m.s. *)
	MaxRecIdx: POINTER TO ARRAY[0..MaxCARDINAL] OF CARDINAL ;  (* m.s. - was MAX(CARDINAL) *)
	ToRecs	: POINTER TO ARRAY[0..MaxCARDINAL] OF HRecPntr ;   (* m.s. - was MAX(CARDINAL) *)
        NextFunctionWord : StrAny ;
        NoMoreFunctionWords : BOOLEAN ;
        TempCompare, FunctionTypeNum : INTEGER ;

   PROCEDURE ReadFile( TheFileID : FIO.File ) ;	
	BEGIN
	    BytesRead := FIO.RdBin( TheFileID, HRecord^, HyperLength ) ;
	    IF BytesRead <> HyperLength THEN
		 ProgramErrorAndHalt( 'RunSource(SetTypeBitTable): short record read from .TDB file.' )
	    END ;
	END ReadFile ;

PROCEDURE GetNextFunctionWord ;

VAR
   Result : CARDINAL ;
   enoughdata, dummy: BOOLEAN ;
   BadChar : CHAR ;

BEGIN
   NextFunctionWord[0] := 0C ;
   WHILE (NextFunctionWord[0] = 0C) AND (NOT NoMoreFunctionWords) DO
      dummy := XReadLine( FunctionFileID, BadChar, NextFunctionWord, enoughdata, Result ) ;
      TrimBlanks( NextFunctionWord, NextFunctionWord ) ;
      IntToSortWord( NextFunctionWord, NextFunctionWord ) ;
      IF Result <> 0 THEN
         NoMoreFunctionWords := TRUE ;
      END ;
  END ;
  IF Result <> 0 THEN
     NextFunctionWord := MAX(CHR) + MAX(CHR) + MAX(CHR);
  END ;
END GetNextFunctionWord ;
	
   BEGIN
        IF FunctionWords  THEN
           NoMoreFunctionWords := FALSE ;
           GetNextFunctionWord ;  (* now set regardless *)
        ELSE
           NextFunctionWord := MAX(CHR) + MAX(CHR) + MAX(CHR);
        END ;
	Limit := EndTypeRec - BeginType ;	(* note BeginType set for both COR & TDB *)
	ALLOCATE( TypeTable, (Limit + 1) * TSIZE(TypeBitRecType) );
	IF CheckColl THEN
	   ALLOCATE( FunctionTable, (Limit + 1) * TSIZE(TypeBitRecType) ) ;
	END ;
	NoTokens := 0 ;
(*	IF UsingCorpusFile THEN
	   (* first find max Type recs needed by reading the last corpus type rec *)
	   FIO.Seek( CORFileID, HyperLength * VAL(LONGCARD, EndCorpusTypeRec) ) ;
	   ReadFile( CORFileID ) ;
	   (* last entry has values for all TDB files !! *)
	   WITH HRecord^ DO
		Offset  := DataPntr[NoDataPtrsUsed] ;
		WordPtr := ADR( TextData[ Offset ] ) ;
		INC( Offset, CARDINAL(WordPtr^.PackedLen) + 1 + HROffset );
		EncodedEntry := ADR( TextData[ Offset ] ) ;
		BitOps.Decode( EncodedEntry^, Entry, NumbFiles * (SIZE(CARDINAL)+SIZE(HRecPntr)) );
		Offset   := NumbFiles * SIZE(CARDINAL) ;
		TypePos  := ADR( Entry[ Offset ] ) ;
		MaxNoTypeRecs := 0 ;
		FOR I := 0 TO NumbFiles - 1 DO
		    IF TypePos^[ I ].Rec > MaxNoTypeRecs THEN
			MaxNoTypeRecs := TypePos^[ I ].Rec ;
		    END ;
		END ;
		INC( MaxNoTypeRecs ) ;	(* account for the zero-th record *)
	   END ;
	   TheSize := MaxNoTypeRecs*SIZE(CARDINAL);
	   ALLOCATE( MaxRecIdx, TheSize ) ;
	   Lib.Fill( MaxRecIdx, TheSize, 0 ) ;
	   TheSize := MaxNoTypeRecs*SIZE(XRecInfoPntr) + SIZE(CARDINAL);
	   ALLOCATE( TypeMap, TheSize ) ;
	   Lib.Fill( TypeMap, TheSize, 0 ) ;
	   TypeMap^.Size := MaxNoTypeRecs ;
	   TheSize := NumbFiles * SIZE(HRecPntr) ;
	   ALLOCATE( ToRecs, TheSize ) ;
	   Lib.Fill( ToRecs, TheSize, 0 ) ;

	   LastPercentage := 0 ;
	   FIO.Seek( CORFileID, HyperLength * VAL(LONGCARD, BeginCorpusType) ) ;
	   FOR Rec := 0 TO Limit DO
	      Percentage := (Rec * 100) DIV Limit ;
	      IF Percentage >= LastPercentage THEN
		PutPercentage( Percentage ) ;
		INC(LastPercentage, 2) ;
	      END ;
	      ReadFile( CORFileID ) ;
	      WITH HRecord^ DO
	       TypeTable^[Rec].SetLen := VAL(SHORTCARD, (NoDataPtrsUsed+7) DIV 8 );
	       ALLOCATE( TypeTable^[Rec].Set, VAL(CARDINAL, TypeTable^[Rec].SetLen) ) ;
	       FOR I := 1 TO NoDataPtrsUsed DO
		 Offset  := DataPntr[I] ;
		 WordPtr := ADR( TextData[ Offset ] ) ;
		 INC( Offset, CARDINAL(WordPtr^.PackedLen) + 1 );
		 Present := ADR( TextData[ Offset ] ) ;
		 GetNumbOfEntries( NumbOfEntries ) ;
		 INC( Offset, HROffset) ;

		 EncodedEntry := ADR( TextData[ Offset ] ) ;
		 BitOps.Decode( EncodedEntry^, Entry, NumbOfEntries * (SIZE(CARDINAL)+SIZE(HRecPntr)) );
		 NoOccurs := ADR( Entry ) ;
		 Total := 0 ;
		 IF NumbOfEntries > 0 THEN
		    FOR K := 0 TO NumbOfEntries-1 DO INC(Total,LONGCARD(NoOccurs^[K])) END ;
		 END ;
		 IF Total >= LONGCARD(FileData.RepeatMin) THEN
		   INCL( TypeTable^[Rec].Set^, I ) ;
		   INC( NoTokens, Total ) ;
		 ELSE
		   EXCL( TypeTable^[Rec].Set^, I )
		 END ;

		 Offset   := NumbOfEntries * SIZE(CARDINAL) ;
		 TypePos  := ADR( Entry[ Offset ] ) ;
		 J := 0 ;
		 FOR K := 0 TO NumbFiles-1 DO
		    IF K IN Present^ THEN
			IF TypePos^[J].Rec <> ToRecs^[K].Rec THEN
			   IF ToRecs^[K].Idx > MaxRecIdx^[ ToRecs^[K].Rec ] THEN
				MaxRecIdx^[ ToRecs^[K].Rec ] := ToRecs^[K].Idx
			   END ;
			   ToRecs^[K].Rec := TypePos^[J].Rec ;
			END ;
			ToRecs^[K].Idx := TypePos^[J].Idx ;
			INC( J ) ;
		    END ;
		 END ;	(* FOR K := 0 TO NumbFiles-1 DO *)
	       END ;
	      END ;	(* WITH HRecord^ DO *)
	   END ;
	   FOR K := 0 TO NumbFiles-1 DO	(* update last counts *)
		   IF ToRecs^[K].Idx > MaxRecIdx^[ ToRecs^[K].Rec ] THEN
			MaxRecIdx^[ ToRecs^[K].Rec ] := ToRecs^[K].Idx
		   END ;
	   END ;

	   (* now allocate the max memory needed for TypeMap structure *)
	   FOR K := 0 TO TypeMap^.Size-1 DO
		TheSize := MaxRecIdx^[K]*SIZE(HRecPntr) + SIZE(CARDINAL);
		ALLOCATE( TypeMap^.RecData[K], TheSize ) ;
		Lib.Fill( TypeMap^.RecData[K], TheSize, 0 ) ;
		TypeMap^.RecData[K]^.Size := MaxRecIdx^[K];
	   END ;
	   DEALLOCATE( ToRecs, NumbFiles * SIZE(HRecPntr)) ;
	   DEALLOCATE( MaxRecIdx, MaxNoTypeRecs*SIZE(CARDINAL)) ;
	ELSE
*)
	   FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, BeginType) ) ;
	   IF FunctionType = TRUE THEN
	     FunctionTypeNum := -1 ;
	   ELSE
	     FunctionTypeNum := 0 ;
	   END ;
	   FOR Rec := 0 TO Limit DO
	      ReadFile( TDBFileID ) ;
	      TypeTable^[Rec].SetLen := VAL(SHORTCARD, (HRecord^.NoDataPtrsUsed DIV 8) + 1 );
	      ALLOCATE( TypeTable^[Rec].Set, VAL(CARDINAL, TypeTable^[Rec].SetLen) ) ;
	      Lib.Fill( TypeTable^[Rec].Set, VAL(CARDINAL, TypeTable^[Rec].SetLen), 0 ) ;
	      FOR I := 1 TO HRecord^.NoDataPtrsUsed DO
		 Data := ADR( HRecord^.TextData[ HRecord^.DataPntr[ I ] ] ) ;
		 IF Data^.NoOccur >= FileData.RepeatMin THEN
		   INCL( TypeTable^[Rec].Set^, I ) ;
		   INC( NoTokens, VAL(LONGCARD, Data^.NoOccur) ) ;
		 ELSE
		   EXCL( TypeTable^[Rec].Set^, I )
		 END ;
	      END ;
	      IF CheckColl THEN
        	      FunctionTable^[Rec].SetLen := VAL(SHORTCARD, (HRecord^.NoDataPtrsUsed DIV 8) + 1 );
        	      ALLOCATE( FunctionTable^[Rec].Set, VAL(CARDINAL, FunctionTable^[Rec].SetLen) ) ;
        	      Lib.Fill( FunctionTable^[Rec].Set, VAL(CARDINAL, FunctionTable^[Rec].SetLen), 0 ) ;
        	      FOR I := 1 TO HRecord^.NoDataPtrsUsed DO
        		Data := ADR( HRecord^.TextData[ HRecord^.DataPntr[ I ] ] ) ;
                        WordPtr := ADR( Data^.PackedWord ) ; (* get past the NoOccur value *)
                     	BitOps.UnPack( WordPtr^, CurrWord, WordBase.SortNoBitsPerChar ) ;
(* m.s. Apr 94 compare sort forms      SortToIntWord( SortWord, CurrWord ) ; *)
        		TempCompare := Compare( CurrWord , NextFunctionWord ) ;
                        WHILE TempCompare > 0 DO
                          GetNextFunctionWord ;
             		  TempCompare := Compare( CurrWord , NextFunctionWord ) ;
                        END ;
        		IF TempCompare = FunctionTypeNum THEN  (* FunctionTypeNum = -1 if .INC file exists else =0 *)
        		   EXCL( FunctionTable^[Rec].Set^, I ) ;
        		   (* m.s.?? INC( NoTokens, VAL(LONGCARD, Data^.NoOccur) ) ;*)
        		 ELSE
        		   INCL( FunctionTable^[Rec].Set^, I )
        		 END ;
        	      END ;
              END ;
	   END ;
(*m.s.	-if corpus END ; *)
   END SetTypeBitTable ;


(*$F*)
PROCEDURE GetInput ;
   TYPE
        CollocationPtr = POINTER TO ARRAY[1..255] OF LONGCARD ;
   VAR
        CollArray : CollocationPtr ;
	DataRec : DataTypePtr ;
	I, J, K, L, M, N : CARDINAL ;
	TokenDataArray : POINTER TO ARRAY[1..MaxCARDINAL] OF HRecPntr ;
	TokDataArraySize : CARDINAL ;
	CollocateArraySize : CARDINAL ; (* m.s. *)
	NodeCollArray : CollocationPtr ;
	FileNo	: CARDINAL ;
	NotDone	: BOOLEAN ;
	Include : BOOLEAN ;
	TempBoundaries : BOOLEAN ;
	TempVal   : LONGINT ;
	LogOffset  : CARDINAL ;
	CurLogNo, SpanMax   : LONGCARD ;
	TempNodeCollFile : BFile ;
	Result : CARDINAL ;
	NodeInclude : BOOLEAN ;
	temp : INTEGER ;
	
   PROCEDURE CheckInclude( DataRec : HRecPntr ) : BOOLEAN ;
	BEGIN
	   RETURN  DataRec.Idx IN TypeTable^[DataRec.Rec].Set^  ;
	END CheckInclude ;

   PROCEDURE CheckFunctionInclude( DataRec : HRecPntr ) : BOOLEAN ;
	BEGIN
	   RETURN DataRec.Idx IN FunctionTable^[DataRec.Rec].Set^  ;
   END CheckFunctionInclude ;


PROCEDURE GetTokenInfo( VAR Data : HRecPntr ; I : CARDINAL ) : BOOLEAN ;
   VAR
	BytesRead : CARDINAL ;
   BEGIN
        INC( CurTokenPos ) ;   (* m.s. *)
	IF (RecNo > EndTokenRec) OR ( (RecNo = EndTokenRec) AND (RecIdx > EndTokenIdx)) THEN
	   Data.Rec := 0 ;
	   Data.Idx := 0 ;
	   IF (TokenDataArray^[FileData.SpanMin].Rec = 0) AND  (* m.s. *)
	      (TokenDataArray^[FileData.SpanMin].Idx = 0) THEN
	     RETURN FALSE ;
	   ELSE
	     IF CheckColl THEN
	       CollArray^[I] := 0 ;
	     END ;
	     RETURN TRUE ;
	   END ;
	END ;
	IF RecIdx >= HNoTokens THEN
	   RecIdx := 0 ;
	   INC( RecNo ) ;
	   BytesRead := FIO.RdBin( TDBFileID, HRecord^, HyperLength ) ;
	   IF BytesRead <> HyperLength THEN
	      ProgramErrorAndHalt( 'RunSource(GetTokenInfo): short record read from .TDB file.' )
	   END ;
	END ;
	Data.Rec := HRecord^.TokenData[RecIdx].HRecNo ;
	Data.Idx := VAL(CARDINAL, HRecord^.TokenData[RecIdx].HRecPos) ;
        IF CheckColl THEN
           IF CheckFunctionInclude( Data ) AND CheckInclude( Data ) THEN
                (* if current word is not a function word, and occurs more than minimum required compare tto neighbours *)
(* m.s.              CollArray^[I] := (LONGCARD(Data.Rec) * 1000) + LONGCARD(Data.Idx) ; *)
                     CollArray^[I] := (LONGCARD(Data.Rec) * MAX(CARDINAL)) + LONGCARD(Data.Idx) ;
           ELSE
              CollArray^[I] := 0 ;
           END ;
        END ;
(* m.s.	IF UsingCorpusFile THEN
	   (* ReMapTypeData *)
	   Data := TypeMap^.RecData[ Data.Rec ]^.NewLoc[ Data.Idx - 1 ] ;
	END ;
*)	
	INC( RecIdx ) ;
	RETURN TRUE ;
   END GetTokenInfo ;



PROCEDURE ReadDBLogRec( LogRecNo : CARDINAL ) ;
  VAR
     BytesRead : CARDINAL ;
     TmpPos  : LONGCARD ;
  BEGIN
     TmpPos := FIO.GetPos( TDBFileID ) ;
     FIO.Seek( TDBFileID, LONGCARD( LogRecNo ) * HyperLength ) ;
     IF FIO.IOresult() <> 0 THEN
        ProgramErrorAndHalt( 'Problem reading log records in TDB file.' )
     END ;
     BytesRead := FIO.RdBin( TDBFileID, HRecordLog^, HyperLength ) ;
     IF FIO.IOresult() <> 0 THEN
        ProgramErrorAndHalt( 'Problem reading log records in TDB file.' )
     END ;
     FIO.Seek(TDBFileID, TmpPos ) ;  (* reset pointer *)
     HRecLogPos := MaxRefID + 1;  (* skip to first entry after header info *)
  END ReadDBLogRec ;


PROCEDURE FindNextBoundary( VAR CurTokenLogPos : LONGCARD ) : BOOLEAN ;
  VAR
      Ch : CHAR ;
  BEGIN
     M := L ;
     N := FileData.SpanMax ;
     WHILE (HRecLogNo <= EndLog ) DO
        IF HRecLogPos >= CARDINAL( MaxNoLogData ) THEN (* if at end of record read next *)
           INC(HRecLogNo) ;
           ReadDBLogRec( HRecLogNo ) ;   (* read next record *)
           CurTokenLogPos := HRecordLog^.BaseTokenNo ; (* want to point to token after boundary, was + 1 *)
        END ;
        FOR Ch := CHR(HRecLogPos) TO MaxNoLogData DO  (* run through current log record
                                                 until log token counter greater
                                                 than token position counter and
                                                 come across ref id listed as a
                                                 boundary *)
	    INC( CurTokenLogPos, LONGCARD(HRecordLog^.LogData[Ch].TokenNoOffset) ) ;
            IF (CurTokenLogPos + SpanMax > CurTokenPos ) AND  (* + SpanMax new *)
               (RefArray[CARDINAL(ABS(HRecordLog^.LogData[Ch].StructID))] = TRUE)
             THEN  (* found next boundary *)
                HRecLogPos := CARDINAL( Ch ) + 1 ;
                RETURN TRUE ;
            END ;
        END ;
        HRecLogPos := MAX(CARDINAL) ;
        INC(HRecLogNo) ;
     END ;
     RETURN FALSE ;  (* if no boundary found return false *)
END FindNextBoundary ;


(* output list of pairs of collocates represented by pairs of LONGCARDS *)
PROCEDURE AddCollocate( N : CARDINAL ) ;

   VAR
      J : CARDINAL ;
      Result : CARDINAL ;
      Temp1, Temp2 : LONGCARD ;
   BEGIN
       IF (NOT FunctionType) AND (CollArray^[1] > 0)  THEN
          IF PrevCol > 0 THEN
            IF CollArray^[1] = PrevCol THEN
               PrevCol := 0 ;
            ELSE
               RETURN
            END ;
          END ;
          IF FileData.SpanMin <= N THEN
            FOR J := FileData.SpanMin TO N DO   (* consider collocates from FileData.SpanMin to boundary or SpanMax whichever is smaller *)
               IF (CollArray^[J] > 0) THEN
                 IF  (NOT FileData.OverlapCollocates) AND (CollArray^[1] = CollArray^[J]) THEN
                   PrevCol := CollArray^[J] ;
                 END ;
                 FIO.WrLngCard( TempNodeCollFile.FileID , CollArray^[1], 15 ) ;
                 FIO.WrLngCard( TempNodeCollFile.FileID , CollArray^[J], 15 ) ;
                 WrLn( TempNodeCollFile, Result ) ;
                 INC( NoNodCollPairs ) ;
                 FIO.WrLngCard( TempNodeCollFile.FileID , CollArray^[J], 15 ) ;
                 FIO.WrLngCard( TempNodeCollFile.FileID , CollArray^[1], 15 ) ;
                 WrLn( TempNodeCollFile, Result ) ;
                 INC( NoNodCollPairs ) ;
                 IF PrevCol > 0 THEN  RETURN END ;
             END ;
         END ;
       END ;
    ELSIF FunctionType THEN (* TRUE if .INC *)
        IF FileData.SpanMin <= N THEN
           IF CheckInclude( TokenDataArray^[1] ) THEN (* in list *)
              Temp1 := (LONGCARD( TokenDataArray^[1].Rec) * MAX(CARDINAL))
                                  + LONGCARD( TokenDataArray^[1].Idx ) ;
              FOR J := FileData.SpanMin TO N DO   (* consider collocates from FileData.SpanMin to boundary or SpanMax whichever is smaller *)
               IF (CollArray^[J] > 0) THEN
                 Temp2 := CollArray^[J] ;
               ELSE
                 IF CheckInclude( TokenDataArray^[J] ) THEN (* in list *)
                    Temp2 := (LONGCARD( TokenDataArray^[J].Rec) * MAX(CARDINAL))
                                  + LONGCARD( TokenDataArray^[J].Idx ) ;
                 ELSE
                    Temp2 := 0 ;
                 END ;
               END ;
               IF  (NOT FileData.OverlapCollocates) AND (Temp1 = Temp2) AND
                   (Temp1 > 0) THEN
                   PrevCol := CollArray^[J] ;
               END ;
               IF (CollArray^[1] > 0) AND (Temp2 > 0) THEN
                 (* considering word to be included *)
                 FIO.WrLngCard( TempNodeCollFile.FileID , Temp1, 15 ) ;
                 FIO.WrLngCard( TempNodeCollFile.FileID , Temp2, 15 ) ;
                 WrLn( TempNodeCollFile, Result ) ;
                 INC( NoNodCollPairs ) ;
                 IF CollArray^[J] > 0 THEN (* both words to be included *)
                    FIO.WrLngCard( TempNodeCollFile.FileID , CollArray^[J], 15 ) ;
                    FIO.WrLngCard( TempNodeCollFile.FileID , CollArray^[1], 15 ) ;
                    WrLn( TempNodeCollFile, Result ) ;
                    INC( NoNodCollPairs ) ;
                 END ;
                 IF PrevCol > 0 THEN  RETURN END ;
               ELSIF (CollArray^[J] > 0) AND (Temp1 > 0) THEN
                 (* considering word within span preceding word to be included *)
                 FIO.WrLngCard( TempNodeCollFile.FileID , Temp2, 15 ) ;
                 FIO.WrLngCard( TempNodeCollFile.FileID , Temp1, 15 ) ;
                 WrLn( TempNodeCollFile, Result ) ;
                 INC( NoNodCollPairs ) ;
                 IF PrevCol > 0 THEN  RETURN END ;
               END ; (* end if *)
          END ;  (* end for *)
        END ;
       END ;
    END ; (* end main if *)
END AddCollocate ;


   BEGIN
	MaxCardsInContext := FileData.SpanMax * 2 + 1 ;

        IF FileData.NodeCollocate THEN
            BCreate(TempNodeCollFile , "NODECOLL.TMP" , TRUE, Result ) ;
            NoNodCollPairs := 0 ;
            PrevCol := 0 ;
        END ;
	TokDataArraySize := FileData.SpanMax * TSIZE(HRecPntr) ;
	ALLOCATE( TokenDataArray, TokDataArraySize ) ;
	Lib.Fill( TokenDataArray, TokDataArraySize, 0 ) ;

        CollocateArraySize := TokDataArraySize ;
	ALLOCATE( CollArray, CollocateArraySize ) ;
	Lib.Fill( CollArray, CollocateArraySize, 0 ) ;


	ALLOCATE( DataRec, DataRecSize ) ;
	Lib.Fill( DataRec, DataRecSize, 0 ) ;

       	ALLOCATE( HRecordLog, HyperLength ) ;   (* m.s. *)
       	Lib.Fill( HRecordLog, HyperLength, 0C ) ; (* m.s. *)
	
        SpanMax := LONGCARD( FileData.SpanMax ) ; (* m.s. *)

	NoSortRecs := 0 ;
        IF NOT FileData.MaximalPhrase THEN  (* m.s. - if PermutePhrase then will generate
                                  sequence for all KeyWords else only for
                                  first word in sequence *)
            L := FileData.SpanMax ;
        ELSE
            L := 1 ;
        END ;

        LogOffset  :=  2 ; (* FileData.SpanMax - FileData.SpanMin  ???  *)
        TempBoundaries := Boundaries ; (* m.s. - so can reset for each tdb *)


	FOR FileNo := 1 TO NumbFiles DO	
(*m.s.	   IF UsingCorpusFile THEN
		SetTypeHRecPntrMap( FileNo - 1 ) ;
		dummy := OpenTDB( TDBFileNames^[ FileNo ]^ ) ; (* <<<--- ??? *)
	   END ;
*)
	   RecNo  := BeginToken - 1 ; (* compensate later	*)
	   RecIdx := HNoTokens + 1 ;  (* force a read from DB	*)
	   FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, BeginToken )  ) ;

           HRecLogNo := BeginLog - 1 ;  (* m.s. - will increment before reading *)
           HRecLogPos := MAX(CARDINAL) ;        (* m.s. - will force a read *)
           CurTokenPos := 0 ;            (* m.s. *)
           CurTokenLogPos := 0 ;         (* m.s. - was 1  *)
           N :=   FileData.SpanMax ;     (* m.s. *)
           M := L ;                      (* m.s. *)

	   Count := 0 ;
	   LastPercentage := 0 ;
	   TotalNoTokens := 1 ;
	   (*RES OLD MSG 307
	   Reading TDB File %0.
	   *)
	   MsgString( FileData.DBName, 0 );
	   PutRunStatus( (*RES REM INS*) 307 );
           PutPercentage( 0 ) ;
	   FOR I := 1 TO FileData.SpanMax DO
		NotDone := GetTokenInfo( TokenDataArray^[I], I ) ;
	   END ;

	   WHILE NotDone DO
	      INC(TotalNoTokens);
	      Percentage := VAL(CARDINAL,(TotalNoTokens * 100) DIV NoTokens) ;
	      IF Percentage >= LastPercentage THEN
                 IF Percentage >= 100 THEN
                	 Percentage := 99	(* fake a reasonable value *)
                 END ;
                 LastPercentage := Percentage ;
		 PutPercentage( Percentage ) ;
	      END ;

	      IF Boundaries THEN  (* m.s. - if checking for boundaries *)
	        IF ((CurTokenLogPos + SpanMax) (* if current position in token record
	                                                      is beyond position of current boundary
	                                                      then get next boundary *)
	               <= CurTokenPos ) AND
	              ( FindNextBoundary( CurTokenLogPos ) = FALSE ) THEN
	              (* no more boundaries *)
	            Boundaries := FALSE ;
                ELSIF (CurTokenPos > CurTokenLogPos)  THEN  (* within boundary *)
                    N := FileData.SpanMax - CARDINAL(CurTokenPos - CurTokenLogPos ) ;
                    IF (N < FileData.SpanMin) THEN  (* if boundary between first and second token skip completely , was 2 *)
                      M := 0 ;
                    ELSE
                      FOR I := FileData.SpanMin TO FileData.SpanMax DO  (* make sure context beyond boundary is empty *)
                         DataRec^.Context[I].Rec := 0 ;
                         DataRec^.Context[I].Idx := 0 ;
                      END ;
                      IF NOT FileData.MaximalPhrase THEN
                        M := N ;  (* else it is = 1 *)
                      END ;
                    END ;
	        END ;
	      END ;
	      FOR I := 1 TO M DO (* m.s. - was FileData.SpanMax, M depends on MaximalPhrase
	                                   and whether thereis a boundary within span *)
		 DataRec^.KeyWord  := TokenDataArray^[ I ] ;
		 DataRec^.position := I ;
		 K := 1 ;
		 FOR J := 1 TO N DO (* n = spanmax or boundary token position *)
		   IF I <> J THEN
			DataRec^.Context[K] := TokenDataArray^[ J ] ;
			INC( K ) ;
		   END ;
		 END ;

		 K := 1 ;
		 IF CheckColl THEN
		   Include := CheckInclude(DataRec^.KeyWord);
		   NodeInclude := NOT(CollArray^[I] = 0) ;
		   WHILE Include AND (K < FileData.SpanMin ) DO
		     IF NOT CheckInclude( DataRec^.Context[K] ) THEN
			Include := FALSE
		     ELSE
		        NodeInclude := NodeInclude OR NOT(CollArray^[K] = 0) ;	
		     END ;
		     INC( K ) ;
		   END ;
                   Include := NodeInclude ;
                   IF NOT Include THEN  (* check to be sure there is at least one word in span that isn't excluded *)
                     FOR J := FileData.SpanMin TO N DO
                        Include := Include OR NOT(CollArray^[J] = 0) ;
                     END ;
                   END ;
		 ELSE
    		   Include := CheckInclude( DataRec^.KeyWord ) ;
    		   WHILE Include AND (K < FileData.SpanMin ) DO
    		     IF NOT CheckInclude( DataRec^.Context[K] ) THEN
    			Include := FALSE
    	  	     END ;
    		     INC( K ) ;
    		   END ;
                 END ;
		 IF Include THEN
		   IF FileData.NodeCollocate AND (I = 1) THEN
		      AddCollocate( N ) ;  (* m.s. - N is boundary value =< FileData.SpanMax *)
                   END ;
                   IF NOT NodeCollocateOnly THEN (* m.s. - only release strings if necessary *)
  		     LSortRelease( DataRec ) ;
		     INC( NoSortRecs ) ;
		    END ;
		 END ;
	      END ;
	      (* shift by one token and add next token to the end of array *)
	      Lib.Move( ADR(TokenDataArray^[2]), ADR(TokenDataArray^[1]), TokDataArraySize ) ;
              IF CheckColl THEN
   	         Lib.Move( ADR(CollArray^[2]), ADR(CollArray^[1]), CollocateArraySize ) ;
   	      END ;
	      NotDone := GetTokenInfo( TokenDataArray^[FileData.SpanMax] , FileData.SpanMax ) ;
	   END ;	(* WHILE NotDone DO *)
(* m.s.	   IF UsingCorpusFile THEN
		(* free up TypeMap table *)
		FIO.Close( TDBFileID ) ;
	   END ;
*)
           Boundaries := TempBoundaries ; (* m.s. - reset for next tdb *)
	END ;

	Lib.Fill( DataRec, DataRecSize, 255 ) ;	(* dummy sentinal record *)
	LSortRelease( DataRec ) ;

(*m.s.	IF UsingCorpusFile THEN
	   (* free up TypeMap table *)
	END ;
*)
	DEALLOCATE( DataRec, DataRecSize ) ;
	DEALLOCATE( TokenDataArray, TokDataArraySize ) ;
	DEALLOCATE( HRecord, HyperLength ) ;
       	DEALLOCATE( HRecordLog, HyperLength ) ;   (* m.s. *)
	DEALLOCATE( CollArray, CollocateArraySize ) ;

	FOR I := 0 TO EndTypeRec - BeginType DO
	   DEALLOCATE( TypeTable^[I].Set, VAL(CARDINAL, TypeTable^[I].SetLen) ) ;
	END ;
	DEALLOCATE( TypeTable, (EndTypeRec - BeginType + 1) * TSIZE(TypeBitRecType) );
        IF CheckColl THEN
        	FOR I := 0 TO EndTypeRec - BeginType DO
        	   DEALLOCATE( FunctionTable^[I].Set, VAL(CARDINAL, FunctionTable^[I].SetLen) ) ;
        	END ;
        	DEALLOCATE( FunctionTable, (EndTypeRec - BeginType + 1) * TSIZE(TypeBitRecType) );
	END ;
	(* set status value for next phase -- calculated above !!	  *)
	(* Note: QuickSort is order O( N log2(N) ) comparisons, it appears *)
	(*	 to be N log2(N) + 4 N					   *)
	NoCompares := NoSortRecs * VAL(LONGCARD, Log2(NoSortRecs) + 4 ) ;
	Count := 0 ;
	LastPercentage := 0 ;
	IF FileData.NodeCollocate THEN
	   BClose( TempNodeCollFile , Result ) ;
	END ;
	(*RES OLD MSG 308
	Sort Phase.
	*)
	(*RES OLD MSG 445
	First sort phase (of three)... Please wait.
	*)
	IF FileData.MaximalPhrase THEN
	  PutRunStatus((*RES REM INS*) 445 ) ;
	ELSE
	  PutRunStatus( (*RES REM INS*) 308 );
	END ;
	PutPercentage( 0 ) ;
   END GetInput ;


PROCEDURE LessCompare( X, Y : DataTypePtr ) : BOOLEAN ;
   VAR
	I	: CARDINAL ;
   BEGIN
	INC(Count);
	Percentage := VAL(CARDINAL,(Count * 100) DIV NoCompares) ;
	IF Percentage > LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage ) ;
		LastPercentage := Percentage ;
	END ;
	FOR I := 1 TO MaxCardsInContext DO
	    IF X^.ptr[I] < Y^.ptr[I] THEN
		RETURN TRUE
	    ELSIF X^.ptr[I] > Y^.ptr[I] THEN
		RETURN FALSE
	    END ;
	END ;
	RETURN FALSE ;
   END LessCompare ;


PROCEDURE LookUp( TypeRec : HRecPntr; VAR HeadWord : ARRAY OF CHAR ;
                  VAR NoOccur : CARDINAL ) ;
   VAR
	Prev, ptr : TypeRecPntr ;
	BytesRead : CARDINAL ;
	NotFound  : BOOLEAN ;
	NeedToReadIn : BOOLEAN ;
	WordPtr	  : POINTER TO BitOps.PackedStrType ;
	Data	  : TDBTypePntr ;
	SortWord  : StrAny ;
   BEGIN
	ptr := HeadTRec ;
	Prev := NIL ;
	NotFound := TRUE ;
	NeedToReadIn := FALSE ;
	WHILE NotFound DO
	   IF (ptr = NIL) OR NeedToReadIn THEN
		IF Available( TSIZE(TypeRecType) ) THEN
		   Prev := ptr ;
		   ALLOCATE( ptr, TSIZE(TypeRecType) ) ;
		   ptr^.Next := NIL ;
		   IF HeadTRec = NIL THEN  HeadTRec := ptr
		   ELSIF Prev <> NIL THEN  Prev^.Next := ptr
		   END ;
		ELSIF ptr = NIL THEN
		   ProgramErrorAndHalt( 'RUNSOURCE LookUp; No memory available' ) ;
		(* else replace the last TypeRec on linked list *)		
		END ;
		ptr^.RecNo := TypeRec.Rec ;
		FIO.Seek( TheFileID, HyperLength * VAL(LONGCARD, BeginType+TypeRec.Rec) );
		BytesRead := FIO.RdBin( TheFileID, ptr^.HRecord, HyperLength ) ;
		IF BytesRead <> HyperLength THEN
		   ProgramErrorAndHalt( 'RunSource(LookUpType): short record read from .TDB file.' )
		END ;
	   END ;
	   IF ptr^.RecNo = TypeRec.Rec THEN
		IF ptr <> HeadTRec THEN		(* move node to front of linked list *)
		   Prev^.Next := ptr^.Next ;
		   ptr^.Next  := HeadTRec ;
		   HeadTRec   := ptr ;
		END ;
		NotFound := FALSE ;	(* exit loop *)
	   ELSE
		IF ptr^.Next <> NIL THEN
		   Prev := ptr ;
		   ptr := ptr^.Next
		ELSE
		   NeedToReadIn := TRUE
		END ;
	   END ;
	END ;
	WITH HeadTRec^.HRecord DO
	   IF UsingCorpusFile THEN
		WordPtr := ADR( TextData[ DataPntr[ TypeRec.Idx ] ] ) ;
	   ELSE
		Data := ADR( TextData[ DataPntr[ TypeRec.Idx ] ] ) ;
		WordPtr := ADR( Data^.PackedWord ) ;	(* get past the NoOccur value *)
	   END ;
	END ;
	BitOps.UnPack( WordPtr^, SortWord, WordBase.SortNoBitsPerChar ) ;
	SortToIntWord( SortWord, HeadWord ) ;
	NoOccur := Data^.NoOccur ;
   END LookUp ;


PROCEDURE DoOutput( VAR file: XFileType; CheckAbort: AbortProc);
   VAR
	NextDataRec, DataRec, TempRec : DataTypePtr ;
	PrevKey : HRecPntr ;
	DupCount: CARDINAL ;
	I, K	: CARDINAL ;
	pos	: CARDINAL ;
	RulePos	: CARDINAL ;
	RuleID	: CARDINAL ;
	TempStr	: StrAny ;
	KeyStr	: StrAny ;
	RuleStr	: StrAny ;
	ContextStr : StrAny ;
	IOResult : CARDINAL;
	ErrorMsg : StrAny ;
	StartSpanSortItem,
	EndSpanSortItem : LONGINT ;
	CollatesFound : BOOLEAN ;
	TempTypeRec : TypeRecPntr ;
	OutKeyStr : StrAny ; (* m.s. - either '--' or KeyStr de[ending on MaximalPhrase *)
	PrevContextStr : StrAny ; (* m.s. - stores previous ContextStr for possible comparison *)
	status : BOOLEAN ; (* m.s. - moved here from PrintRec *)

PROCEDURE CompareNE( X, Y : DataTypePtr; SpanContext : CARDINAL ) : BOOLEAN ;
   VAR
	I	: CARDINAL ;
   BEGIN
	MaxCardsInContext := SpanContext * 2 + 1 ;
	FOR I := 1 TO MaxCardsInContext DO
	    IF X^.ptr[I] <> Y^.ptr[I] THEN
		RETURN TRUE
	    END ;
	END ;
	RETURN FALSE ;
   END CompareNE ;

   PROCEDURE PrintRecMax( Span : CARDINAL ) ;
        VAR
           NoOccur : CARDINAL ;
	BEGIN

	   IF (DataRec^.KeyWord.Rec <> PrevKey.Rec) OR
	      (DataRec^.KeyWord.Idx <> PrevKey.Idx) THEN
		PrevKey := DataRec^.KeyWord ;
		LookUp( DataRec^.KeyWord, KeyStr , NoOccur) ;
		IF CollModePresent THEN	(* we a file translation table *)
		   TempStr[0] := IntEnhOn ;
		   FOR I := 1 TO Length( KeyStr ) DO
			TempStr[I] := KeyStr[I-1]
		   END ;
		   TempStr[I+1] := IntEnhOff;
		   TempStr[I+2] := 0C ;
		ELSE
		   Copy( TempStr, KeyStr )
		END ;
 	        Copy( OutKeyStr , KeyStr ) ; (* m.s. - if simple report use keyword instead of '--' *)
	   END ;
	   pos := 0 ;
	   SWriteCard( ContextStr, pos, DupCount, 6 ) ;
	   SWriteString( ContextStr, pos, '  ', 0 ) ;
	   K := 1 ;
	   FOR I := 1 TO Span DO
		IF I = DataRec^.position THEN
		      SWriteString( ContextStr, pos, OutKeyStr , 0 ) ;  (* m.s. - was '--' *)
		ELSE
		   LookUp( DataRec^.Context[K], TempStr , NoOccur) ;
		   IF TempStr[0] = 0C THEN  (* m.s. - jump out if boundary crossed in context *)
		     RETURN ;
		   END ;
		   INC( K ) ;
		   SWriteString( ContextStr, pos, TempStr, 0 );
		END ;
		SWriteString( ContextStr, pos, ' ', 0 ) ;
	   END ;
	   IF (PrevContextStr[0] <> 0C) AND
	      ( Pos( ContextStr, PrevContextStr ) = MAX(CARDINAL)  ) THEN  (* m.s. - cope with maximal phrases *)
        		IF NOT XWriteLine(OutFileID, '?', PrevContextStr, IOResult) THEN
        		   IOErrorMessage(IOResult, ErrorMsg) ;
        		   MsgString( FileData.OutFileName, 0 ) ;
        		   MsgString( ErrorMsg, 0 ) ;
        		   PutResError( FileHeaderResource ) ;
        		END ;
           END ;	
	   INC( NoOutputRecs) ;
           Copy( PrevContextStr, ContextStr ) ; (* m.s. *)
	END PrintRecMax ;


   PROCEDURE PrintRec( Span : CARDINAL ) ;
        VAR
           NoOccur : CARDINAL ;
	BEGIN

	   IF (DataRec^.KeyWord.Rec <> PrevKey.Rec) OR
	      (DataRec^.KeyWord.Idx <> PrevKey.Idx) THEN
		PrevKey := DataRec^.KeyWord ;
		LookUp( DataRec^.KeyWord, KeyStr , NoOccur ) ;
		IF CollModePresent THEN	(* we a file translation table *)
		   TempStr[0] := IntEnhOn ;
		   FOR I := 1 TO Length( KeyStr ) DO
			TempStr[I] := KeyStr[I-1]
		   END ;
		   TempStr[I+1] := IntEnhOff;
		   TempStr[I+2] := 0C ;
		ELSE
		   Copy( TempStr, KeyStr )
		END ;
        	IF FileData.GenCollOut THEN
        		IF NOT XWriteLine(OutFileID, '?', TempStr, IOResult) THEN
        		  IOErrorMessage(IOResult, ErrorMsg) ;
        	          MsgString( FileData.OutFileName, 0 ) ;
        		  MsgString( ErrorMsg, 0 ) ;
        		  PutResError( FileHeaderResource ) ;
        	        END ;
     		END ;
		RuleID := 0 ;
	   END ;
	   IF FileData.GenRuleFile THEN
		RulePos := 0 ;
		SWriteString( RuleStr, RulePos, KeyStr, 0 );
		INC( RuleID ) ;
		SWriteString( RuleStr, RulePos, '#', 0 );
		SWriteCard( RuleStr, RulePos, RuleID, 0 );
		SWriteString( RuleStr, RulePos, ' (* ', 0 );
		SWriteCard( RuleStr, RulePos, DupCount, 0 );
		SWriteString( RuleStr, RulePos, ' *)  ', 0 );
	   END ;
	   IF FileData.GenCollOut THEN
		pos := 0 ;
		SWriteCard( ContextStr, pos, DupCount, 6 ) ;
        	SWriteString( ContextStr, pos, '  ', 0 ) ;
	   END ;
	   K := 1 ;
	   FOR I := 1 TO Span DO
		IF I = DataRec^.position THEN
		   IF FileData.GenCollOut THEN
  		      SWriteString( ContextStr, pos, OutKeyStr , 0 ) ;  (* m.s. - was '--' *)
  		   END ;
		   IF FileData.GenRuleFile THEN
		      SWriteString( RuleStr, RulePos, '> "', 0 );
		      SWriteString( RuleStr, RulePos, KeyStr, 0 );
		   END ;
		ELSE
		   LookUp( DataRec^.Context[K], TempStr , NoOccur) ;
		   IF TempStr[0] = 0C THEN  (* m.s. - jump out if boundary crossed in context *)
                     IF FileData.GenRuleFile THEN  (* m.s. - correct rule numbering *)
                       DEC( RuleID ) ;
                     END ;
		     RETURN ;
		   END ;
		   INC( K ) ;
		   IF FileData.GenCollOut THEN
                      SWriteString( ContextStr, pos, TempStr, 0 );
                   END ;
		   IF FileData.GenRuleFile THEN
		      SWriteString( RuleStr, RulePos, '"', 0 );
		      SWriteString( RuleStr, RulePos, TempStr, 0 );
		   END ;
		END ;
		IF FileData.GenCollOut THEN
                   SWriteString( ContextStr, pos, ' ', 0 ) ;
                END ;
		IF FileData.GenRuleFile AND (I <> Span) THEN
		   SWriteString( RuleStr, RulePos, ' | ', 0 );
		END ;
	   END ;
	   IF FileData.GenCollOut THEN
 	       IF NOT XWriteLine(OutFileID, '?', ContextStr, IOResult) THEN
              	   IOErrorMessage(IOResult, ErrorMsg) ;
    		   MsgString( FileData.OutFileName, 0 ) ;
    		   MsgString( ErrorMsg, 0 ) ;
    		   PutResError( FileHeaderResource ) ;
    	       END ;
    	   END ;
	   IF FileData.GenRuleFile THEN
		RuleFileID.ModeData.ModeIn := '0' ;	(* *JB* *)
		RuleFileID.ModeData.ModeOut := '0' ;
		IF NOT XWriteLine(RuleFileID, '?', RuleStr, IOResult) THEN
		   IOErrorMessage(IOResult, ErrorMsg) ;
		   MsgString( FileData.RuleFileName, 0 ) ;
		   MsgString( ErrorMsg, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		END ;
	   END ;
	END PrintRec ;

   PROCEDURE CheckForSubRange( SpanContext : CARDINAL; StartSpan, EndSpan : LONGINT ) ;
   	VAR
   	   SortItem	: LONGINT ;
   	   NewStartSpan	: LONGINT ;
	BEGIN
	   SortItem := StartSpan ;
	   REPEAT
		NewStartSpan := SortItem ; (* save current position of sort *)
		DupCount := 0 ;
		REPEAT
		   LSortReturn( NextDataRec ) ;
		   INC( SortItem ) ;
		   INC( DupCount ) ;
		UNTIL (SortItem >= EndSpan) OR CompareNE( DataRec, NextDataRec, SpanContext) ;
		IF (DupCount >= FileData.RepeatMin) AND
		   (DupCount <= FileData.RepeatMax) THEN
		   IF DataRec^.position <= SpanContext THEN
                        IF FileData.MaximalPhrase THEN
			   PrintRecMax( SpanContext ) ;
			ELSE
			   PrintRec( SpanContext ) ;
			END ;
		   END ;
		   IF SpanContext+1 <= FileData.SpanMax THEN
			LSortReset( NewStartSpan ) ;
			CheckForSubRange( SpanContext+1, NewStartSpan, SortItem ) ;
		   ELSE
			TempRec := DataRec ;	(* exchange ptr addresses, since going to overwrite NextDataRec *)
			DataRec := NextDataRec ;
			NextDataRec := TempRec ;
		   END ;
		ELSE
		   TempRec := DataRec ;	(* exchange ptr addresses, since going to overwrite NextDataRec *)
		   DataRec := NextDataRec ;
		   NextDataRec := TempRec ;
		END ;
	   UNTIL SortItem >= EndSpan ;
	END CheckForSubRange ;

   BEGIN
	HeadTRec := NIL ;
	IF UsingCorpusFile THEN
	   TheFileID := CORFileID
	ELSE
	   TheFileID := TDBFileID
	END ;

	ALLOCATE( DataRec, DataRecSize ) ;
	ALLOCATE( NextDataRec, DataRecSize ) ;

	(* set status value for next phase *)
	Count := 0 ;
	LastPercentage := 0 ;
	NoOutputRecs := 0 ;
	(*RES OLD MSG 309
	This is the Fixed Phrase output phase... Please wait.
	*)
	(*RES OLD MSG 446
	First Fixed Phrase output phase (of 3)... Please wait.
	*)
	IF FileData.MaximalPhrase THEN
	   PutRunStatus((*RES REM INS*) 446 ) ;
	ELSE
	   PutRunStatus( (*RES REM INS*) 309 );
        END ;
        PutPercentage( 0 ) ;
        Copy ( OutKeyStr , '--' ) ;  (* m.s. *)
	CollatesFound := FALSE ;
	LSortReturn( DataRec ) ;

	PrevKey.Rec := 0 ;
	PrevKey.Idx := 0 ;
	PrevContextStr[0] := 0C ;

        IF NOT NodeCollocateOnly THEN  (* if only interested in node collocates no string output *)
  	 WHILE NOT LSortEOS() AND NOT CheckAbort() DO
	   LSortGetPos( StartSpanSortItem ) ; (* save current position of sort *)
	   DupCount := 0 ;
	   REPEAT
		INC(Count);
		Percentage := VAL(CARDINAL,(Count * 100) DIV NoSortRecs) ;
		IF Percentage > LastPercentage THEN
                    IF Percentage >= 100 THEN
                	 Percentage := 99	(* fake a reasonable value *)
                    END ;
                    LastPercentage := Percentage ;
 		    PutPercentage( Percentage ) ;
		END ;
		LSortReturn( NextDataRec ) ;
		INC( DupCount ) ;
	   UNTIL LSortEOS() OR CompareNE( DataRec, NextDataRec, FileData.SpanMin) ;
	   IF (DupCount >= FileData.RepeatMin) AND
	      (DupCount <= FileData.RepeatMax) THEN
		CollatesFound := TRUE ;
		IF DataRec^.position <= FileData.SpanMin THEN
		   IF FileData.MaximalPhrase THEN
		      PrintRecMax( FileData.SpanMin ) ;
		   ELSE
		      PrintRec( FileData.SpanMin ) ;
		   END ;
		END ;
		IF FileData.SpanMin+1 <= FileData.SpanMax THEN
		   LSortGetPos( EndSpanSortItem ) ;
		   LSortReset( StartSpanSortItem ) ;
		   CheckForSubRange( FileData.SpanMin+1, StartSpanSortItem, EndSpanSortItem ) ;
		ELSE
		   TempRec := DataRec ;	(* exchange ptr addresses, since going to overwrite NextDataRec *)
		   DataRec := NextDataRec ;
		   NextDataRec := TempRec ;
		END ;
	   ELSE
		TempRec := DataRec ;	(* exchange ptr addresses, since going to overwrite NextDataRec *)
		DataRec := NextDataRec ;
		NextDataRec := TempRec ;
	   END ;
	 END ; (* while *)
	END ; (* if *)
	IF NOT FileData.NodeCollocate THEN  (* m.s. - added if, leave open if needed later *)
	   FIO.Close( TheFileID ) ;
	END ;
	IF NOT CollatesFound AND NOT NodeCollocateOnly THEN
	    (*RES OLD MSG 300
	    No collations were found in the %0-to-%1 Word-Span that repeated
	    %2 to %3 times in the database "%4".
	    *)
	    MsgCard( FileData.SpanMin, 0);
	    MsgCard( FileData.SpanMax, 0);
	    MsgCard( FileData.RepeatMin, 0);
	    MsgCard( FileData.RepeatMax, 0);
	    MsgString( FileData.DBName, 0);
	    PutResWarning( (*RES REM INS *) 300 );
	    IF FileData.GenCollOut THEN	(* clean up *)
		XClose( OutFileID ) ;
		BDelete( FileData.OutFileName, IOResult );
	    END ;
	    IF FileData.GenRuleFile THEN
		XClose( RuleFileID ) ;
		BDelete( FileData.RuleFileName, IOResult );
	    END ;
  	    IF FileData.NodeCollocate THEN  (* m.s. - added if, leave open if needed later *)
	       FIO.Close( TheFileID ) ;
	    END ;
	    HALT ;   (* nothing more to do *)
        ELSIF FileData.MaximalPhrase AND (NOT NodeCollocateOnly ) AND
	      (PrevContextStr[0] <> 0C) THEN  (* m.s. - cope with last context for maximal phrases *)
        		IF NOT XWriteLine(OutFileID, '?', PrevContextStr, IOResult) THEN
        		   IOErrorMessage(IOResult, ErrorMsg) ;
        		   MsgString( FileData.OutFileName, 0 ) ;
        		   MsgString( ErrorMsg, 0 ) ;
        		   PutResError( FileHeaderResource ) ;
        		END ;
        END ;

(*	IF (NOT NodeCollocateOnly) THEN *)
	   XClose( OutFileID ) ;
(*	END ; *)
	IF FileData.GenRuleFile AND NOT FileData.MaximalPhrase THEN
	   XClose( RuleFileID ) ;
	END ;
	DEALLOCATE( NextDataRec, DataRecSize ) ;
	DEALLOCATE( DataRec, DataRecSize ) ;
	WHILE HeadTRec <> NIL DO
	    TempTypeRec := HeadTRec^.Next ;
	    DEALLOCATE( HeadTRec , TSIZE( TypeRecType )) ;
	    HeadTRec := TempTypeRec ;
	END ;
   END DoOutput ;

PROCEDURE GetOutput ;
   BEGIN
	   DoOutput( OutFileID, AbortForFileIO )
   END GetOutput ;



PROCEDURE GetMaximalInput ;  (* m.s. - read words from .col file to sort again *)

TYPE
    SmArr  = ARRAY[ 0..1] OF CHAR ;
VAR
    Result : CARDINAL ;
    EnoughData : BOOLEAN ;
    GenFile : XFileType ;
    Sequence : SequencePtr ;
    InputLine, TempStr, ErrorMsg : StrAny ;
    SequenceP : SequencePtr ;
    temp : LONGREAL ;
    Exponent : INTEGER ;
    BadChar : CHAR ;

CONST delims = SmArr ( ' ', 11C ) ;


PROCEDURE AddWords ( Line : ARRAY OF CHAR ) : CARDINAL ;

VAR
  Count : CARDINAL ;
  Word  : StrAny   ;

BEGIN
  Count := FileData.SpanMin ;
  ItemS( Word , Line, delims , Count ) ;
  WHILE Word[0] <> 0C DO
    INC( Count ) ;
    ItemS( Word , Line, delims , Count ) ;
  END ;
  RETURN Count ;
END AddWords ;

BEGIN
     ALLOCATE( Sequence, SequenceSize ) ;
     EnoughData := XOpenInput( FileData.OutFileName, 0C, CollMode, GenFile, ErrorMsg ) ;
     NoSortRecs := 0 ;
     Count := 0 ;
     LastPercentage := 0 ;
     (*RES OLD MSG 447
     Input for Maximal Phrase sequences (2nd phase of 3).
     *)
     PutRunStatus( (*RES REM INS*) 447 );
     PutPercentage( 0 ) ;

(*     dummy := ReadLine( GenFile, InputLine, EnoughData, Result ) ; *)
     dummy := XReadLine( GenFile, BadChar, InputLine, EnoughData, Result ) ;
     WHILE Result = 0 DO
           INC(Count);
           Percentage := VAL(CARDINAL,(Count * 100) DIV NoOutputRecs) ;
           IF Percentage > LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99	(* fake a reasonable value *)
              END ;
              LastPercentage := Percentage ;
              PutPercentage( Percentage ) ;
           END ;
           ItemS( TempStr, InputLine, delims , 0 ) ;
           Sequence^.NoOccurs := CARDINAL(StrToCard( TempStr, 10, EnoughData )) ;
           Slice( Sequence^.Text, InputLine, 8, MAX(CARDINAL)) ;
           ItemS( Sequence^.Key , Sequence^.Text, delims, 0 ) ; (*use first word as key for hash *)
           Sequence^.NoWords := AddWords( Sequence^.Text ) ;
(*           IntToSortWord( Sequence^.Text, Sequence^.Text ) ; *)
           LSortRelease( Sequence ) ;
           INC( NoSortRecs ) ;
(*           dummy := ReadLine( GenFile, InputLine, EnoughData, Result ) ; *)
           dummy := XReadLine( GenFile, BadChar, InputLine, EnoughData, Result ) ;
     END ;

     Sequence^.NoOccurs := 0 ;	(* dummy sentinal record *)
     Copy( Sequence^.Text , '***dummy***' ) ;
     Sequence^.NoWords := 0  ;
     LSortRelease( Sequence ) ;
     DEALLOCATE( Sequence, SequenceSize ) ;
     XClose( GenFile ) ;

     NoCompares := NoSortRecs * VAL(LONGCARD, Log2(NoSortRecs) + 4 ) ;
     Count := 0 ;
     LastPercentage := 0 ;
     (*RES OLD MSG 448
     Second Sort phase (of three)... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 448 );
     PutPercentage( 0 ) ;

     temp := MATHLIB.Rexp( Exponent, LONGREAL(NoSortRecs) ) ;
     SpaceReserved := VAL(LONGINT, (NoSortRecs * VAL( LONGCARD, TSIZE( SequenceSize ))) +
                        VAL( LONGCARD , Exponent  * 1024 (* SegmentSize*))  + 4096) ;
END GetMaximalInput ;

PROCEDURE GetFinalInput ;  (* m.s. - read words from .col file to sort final time after maximal eliminations *)

TYPE
    SmArr  = ARRAY[ 0..1] OF CHAR ;
    TabArr = CHAR ;
VAR
    Result : CARDINAL ;
    EnoughData : BOOLEAN ;
    GenFile : BFile ;
    Sequence : ShortSequencePtr ;
    InputLine, TempStr : StrAny ;
    BadChar : CHAR ;

CONST delims = SmArr ( ' ', 11C ) ;
      tab    = CHAR( 11C ) ;

BEGIN
(*     BOpen( GenFile , FileData.FrequencyFileName, ReadType, Result ) ; *)
    IF NOT XOpenInput( FileData.FrequencyFileName, 0C, CollMode, FrequencyFileID, TempStr) THEN
         	   (* something wrong ... *)
		   MsgString( FileData.FrequencyFileName, 0 ) ;
		   MsgString( TempStr, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		   XClose( FrequencyFileID ) ;
		   RETURN ;
     END ;	

     NoSortRecs := 0 ;
     Count := 0 ;
     LastPercentage := 0 ;
     (*RES OLD MSG 449
     Input for final alphabetical sort of Fixed Phrases.
     *)
     PutRunStatus( (*RES REM INS*) 449 );
     PutPercentage( 0 ) ;

     ALLOCATE( Sequence, ShortSequenceSize ) ;
(*     dummy := ReadLine( GenFile, InputLine, EnoughData, Result ) ; *)
     dummy := XReadLine( FrequencyFileID, BadChar, InputLine, EnoughData, Result ) ;
     WHILE Result = 0 DO
           INC(Count);
           Percentage := VAL (CARDINAL , (Count * 100) DIV NoMaximalPhrases) ;
           IF Percentage > LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage ) ;
              LastPercentage := Percentage ;
           END ;
           ItemS( TempStr, InputLine, delims , 0 ) ;
           Sequence^.NoOccurs := CARDINAL(StrToCard( TempStr, 10, EnoughData )) ;
(*           IF FileData.OutputFormat = Spaces THEN *)
              Slice( Sequence^.Text, InputLine, 5, MAX(CARDINAL)) ;
(*           ELSE
              ItemS( Sequence^.Text, InputLine, tab, 1 );
           END ;
*)           IntToSortLine( Sequence^.Text, Sequence^.SortText ) ;
           LSortRelease( Sequence ) ;
(*           dummy := ReadLine( GenFile, InputLine, EnoughData, Result ) ; *)
           dummy := XReadLine( FrequencyFileID, BadChar, InputLine, EnoughData, Result ) ;

     END ;
     Lib.Fill( Sequence, ShortSequenceSize, 255 ) ;	(* dummy sentinal record *)
     LSortRelease( Sequence ) ;

(*     BClose( GenFile , Result ) ; *)
     XClose( FrequencyFileID ) ;
     DEALLOCATE( Sequence, ShortSequenceSize ) ;

     Count := 0 ;
     LastPercentage := 0 ;
     (*RES OLD MSG 450
     Final Sort phase... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 450 );
     NoCompares := NoMaximalPhrases * VAL(LONGCARD, Log2(NoMaximalPhrases) + 4 ) ;
     PutPercentage( 0 ) ;
END GetFinalInput ;


PROCEDURE GetRuleInput ;  (* m.s. - read words from .rul file to sort final time after maximal permutations *)

VAR
    Result : CARDINAL ;
    EnoughData : BOOLEAN ;
(*    RuleFile : BFile ; *)
    Rule : RulePtr ;
    BadChar : CHAR ;
     AL,NS: CARDINAL;
     ED:    BOOLEAN;
     cm:    CurrentModeType;
BEGIN
(*     BOpen( RuleFile , FileData.RuleFileName, ReadType, Result ) ; *)
     ALLOCATE( Rule, TSIZE(RuleType) ) ;
     IF NOT XOpenInput( FileData.RuleFileName, 0C, RuleMode, RuleFileID, Rule^.RuleStr) THEN
         	   (* something wrong ... *)
		   MsgString( FileData.RuleFileName, 0 ) ;
		   MsgString( Rule^.RuleStr, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		   XClose( RuleFileID ) ;
		   RETURN ;
     END ;	

     NoSortRecs := 0 ;
     Count := 0 ;
     LastPercentage := 0 ;
     cm.ModeIn := '0' ;
     cm.ModeOut := '0' ;
     (*RES OLD MSG 475
     Input for sort of Maximal Phrase Queries... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 475  );
     PutPercentage( 0 ) ;

(*     dummy := ReadLine( GenFile, InputLine, EnoughData, Result ) ; *)
     Rule^.NoOccurs := FIO.RdCard( RuleFileID.ID.FileID ) ;
     Rule^.NoWords  := FIO.RdCard( RuleFileID.ID.FileID ) ;
     Rule^.WordPos  := FIO.RdCard( RuleFileID.ID.FileID ) ;
     cm.ModeIn := '0'; cm.ModeOut := '0';
     dummy := XReadLine( RuleFileID, BadChar, Rule^.RuleStr, EnoughData, Result ) ;
     WHILE Result = 0 DO
           INC(Count);
           Percentage := VAL (CARDINAL , (Count * 100) DIV NoRules) ;
           IF Percentage > LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage ) ;
              LastPercentage := Percentage ;
           END ;
           IntToSortLine( Rule^.RuleStr, Rule^.SortStr ) ;
           LSortRelease( Rule ) ;
           Rule^.NoOccurs := FIO.RdCard( RuleFileID.ID.FileID ) ;
           Rule^.NoWords  := FIO.RdCard( RuleFileID.ID.FileID ) ;
           Rule^.WordPos  := FIO.RdCard( RuleFileID.ID.FileID ) ;
           dummy := XReadLine( RuleFileID, BadChar, Rule^.RuleStr, EnoughData, Result ) ;

     END ;
     Rule^.RuleStr[0] := 255C ;	(* dummy sentinal record *)
     Rule^.SortStr[0] := 255C ;
     LSortRelease( Rule ) ;
     DEALLOCATE( Rule , TSIZE( RuleType )) ;
     XClose( RuleFileID ) ;

     Count := 0 ;
     LastPercentage := 0 ;
     (*RES OLD MSG 476
     Maximal Phrase Queries sort phase... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 476 ) ;
     NoCompares := NoRules * VAL(LONGCARD, Log2(NoRules) + 4 ) ;
     PutPercentage( 0 ) ;
END GetRuleInput ;


PROCEDURE RuleCompare( X, Y : RulePtr ) : BOOLEAN ;
   VAR
	I	: CARDINAL ;
   BEGIN
	INC(Count);
	Percentage := VAL(CARDINAL, (Count * 100) DIV NoRules) ;
	IF Percentage > LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage ) ;
		LastPercentage := Percentage ;
	END ;
        IF  Compare(X^.SortStr , Y^.SortStr ) < 0  THEN
              RETURN TRUE
	END ;
	RETURN FALSE ;
   END RuleCompare ;


PROCEDURE GetRuleOutput ;  (* m.s. - output sorted maximal rules to .rul file *)

VAR
    Result, I, J, RulePos, RuleID : CARDINAL ;
    pos, PrevNoOccurs, Len      : CARDINAL ;
    RuleFileID  : XFileType ;
    Word, SortWord, ErrorMsg, RuleStr, PrevWord  : StrAny ;
    Rule  : RulePtr ;

BEGIN
(*     BCreate(OutFile , FileData.RuleFileName , TRUE, Result ) ; *)
     IF NOT XOpenOutput( FileData.RuleFileName, 0C, RuleMode, RuleFileID, ErrorMsg) THEN
         	   (* something wrong ... *)
		   MsgString( FileData.RuleFileName, 0 ) ;
		   MsgString( ErrorMsg, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		   XClose( RuleFileID ) ;
		   RETURN ;
     END ;	
     ALLOCATE( Rule, TSIZE( RuleType ) );
     LSortReturn( Rule ) ;

     (* set status value for next phase *)
     Count := 0 ;
     RuleID := 0 ;
     LastPercentage := 0 ;
     PrevWord[0] := 0C ;
     (*RES OLD MSG 477
     Output of sorted Maximal Phrase Queries... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 477 );
     PutPercentage( 0 ) ;

     RuleFileID.ModeData.ModeIn := '0' ;	(* *JB* *)
     RuleFileID.ModeData.ModeOut := '0' ;

     WHILE NOT LSortEOS() AND NOT AbortForFileIO() DO
        Percentage := VAL(CARDINAL, ( LONGCARD(RuleID) * 100 ) DIV NoRules) ;
        IF Percentage > LastPercentage THEN
 	  IF Percentage >= 100 THEN
	    Percentage := 99	(* fake a reasonable value *)
	  END ;
          PutPercentage( Percentage ) ;
          LastPercentage := Percentage ;
        END ;
         ItemS( Word, Rule^.RuleStr, ' ',  0 ) ;
         IntToSimpleWord( Word, SortWord ) ;
         IF Compare( SortWord, PrevWord ) <> 0 THEN
           RuleID := 0 ;
         END ;
         Copy( PrevWord, SortWord ) ;
         INC(RuleID);
         RulePos := 0 ;
         SWriteString( RuleStr, RulePos, Word, 0 );
         SWriteString( RuleStr, RulePos, '#', 0 );
         SWriteCard( RuleStr, RulePos, RuleID, 0 );
         SWriteString( RuleStr, RulePos, ' (* ', 0 );
         SWriteCard( RuleStr, RulePos, Rule^.NoOccurs, 0 );
         SWriteString( RuleStr, RulePos, ' *)  ', 0 );
         FOR J := 1 TO Rule^.NoWords   DO
           ItemS( Word, Rule^.RuleStr, ' ',  J ) ;
           IF Rule^.WordPos = J THEN (* keyword *)
              SWriteString( RuleStr, RulePos, '> ' , 0) ;
           END ;
           SWriteString( RuleStr, RulePos, '"', 0 );
           SWriteString( RuleStr, RulePos, Word, 0 );
           SWriteString( RuleStr, RulePos, ' | ' , 0) ;
         END ;
         RuleStr[RulePos - 3] := 0C ;
         IF NOT XWriteLine(RuleFileID, '?', RuleStr, Result) THEN
             IOErrorMessage(Result, ErrorMsg) ;
             MsgString( FileData.RuleFileName, 0 ) ;
             MsgString( ErrorMsg, 0 ) ;
             PutResError( FileHeaderResource ) ;
         END ;
        LSortReturn( Rule ) ;
     END ;
     XClose( RuleFileID ) ;
     DEALLOCATE( Rule, TSIZE( RuleType));
END GetRuleOutput ;


PROCEDURE GetNodCollInput ;  (* m.s. - read words from .col file to sort final time after maximal eliminations *)

TYPE
    SmArr  = ARRAY[ 0..1] OF CHAR ;

VAR
    Result : CARDINAL ;
    EnoughData : BOOLEAN ;
    GenFile : BFile ;
    NodCollPair : NodCollPairPtr ;
    InputLine, TempStr : StrAny ;

CONST delims = SmArr ( ' ', 11C ) ;

BEGIN
     BOpen( GenFile , 'NODECOLL.TMP', ReadType, Result ) ;
     NoSortRecs := 0 ;
     Count := 0 ;
     Percentage := 0 ;
     LastPercentage := 0 ;
     ALLOCATE( NodCollPair, NodCollPairSize ) ;
     (*RES OLD MSG 451
     Input for the Node-Collocate sort... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 451 );
     PutPercentage( 0 ) ;

     FIO.EOF := FALSE ;
     NodCollPair^[0] := FIO.RdLngCard( GenFile.FileID ) ;
     NodCollPair^[1] := FIO.RdLngCard( GenFile.FileID ) ;
     WHILE FIO.EOF <> TRUE DO
           INC(Count);
           Percentage := VAL (CARDINAL , (Count * 100) DIV NoNodCollPairs) ;
           IF Percentage > LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage ) ;
              LastPercentage := Percentage ;
           END ;
           LSortRelease( NodCollPair ) ;
           INC( NoSortRecs ) ;
           NodCollPair^[0] := FIO.RdLngCard( GenFile.FileID ) ;
           NodCollPair^[1] := FIO.RdLngCard( GenFile.FileID ) ;
     END ;
     NodCollPair^[0] := MAX(LONGCARD) ;
     NodCollPair^[1] := MAX(LONGCARD);
     LSortRelease( NodCollPair) ;  (* dummy record *)
     NoCompares := NoNodCollPairs * VAL(LONGCARD, Log2(NoNodCollPairs) + 4 ) ;

     DEALLOCATE( NodCollPair, NodCollPairSize ) ;

     BClose( GenFile , Result ) ;
     BDelete( 'NODECOLL.TMP', Result );

     Count := 0 ;
     LastPercentage := 0 ;
     Percentage := 0 ;
     (*RES OLD MSG 452
     Node-Collocate sort phase... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 452 );
     PutPercentage( 0 ) ;
END GetNodCollInput ;


PROCEDURE MaximalCompare( X, Y : SequencePtr ) : BOOLEAN ;
   VAR
	I	: CARDINAL ;
   BEGIN
	INC(Count);
	Percentage := VAL(CARDINAL,(Count * 100) DIV NoCompares) ;
	IF Percentage > LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage ) ;
		LastPercentage := Percentage ;
	END ;
	
        IF ( X^.NoOccurs > Y^.NoOccurs ) OR
           ( (X^.NoOccurs = Y^.NoOccurs ) AND
               ((X^.NoWords  < Y^.NoWords) OR
           ( (X^.NoWords  <= Y^.NoWords)
              AND ( Compare(X^.Text , Y^.Text ) < 0 )    )  )) THEN
              RETURN TRUE

	END ;
	RETURN FALSE ;
   END MaximalCompare ;

PROCEDURE FinalCompare( X, Y : ShortSequencePtr ) : BOOLEAN ;
   VAR
	I	: CARDINAL ;
   BEGIN
	INC(Count);
	Percentage := VAL(CARDINAL, (Count * 100) DIV NoCompares) ;
	IF Percentage > LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage ) ;
		LastPercentage := Percentage ;
	END ;
        IF  Compare(X^.SortText , Y^.SortText ) < 0  THEN
              RETURN TRUE
	END ;
	RETURN FALSE ;
   END FinalCompare ;


PROCEDURE NodCollCompare( X, Y : NodCollPairPtr ) : BOOLEAN ;
   VAR
	I	: CARDINAL ;
	
   BEGIN
	INC(Count);
	Percentage := VAL(CARDINAL, (Count * 100) DIV NoCompares) ;
	IF Percentage > LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage ) ;
		LastPercentage := Percentage ;
	END ;
	IF (X^[0] < Y^[0]) OR
	   ((X^[0] = Y^[0]) AND  (X^[1] < Y^[1]))  THEN
                 RETURN TRUE ;
        END ;
        RETURN FALSE ;
   END NodCollCompare ;

PROCEDURE OutputNodeCollPair( NodCollPair : NodCollPairPtr ) ;

VAR
   NodCollWord : HRecPntr ;
   Word        : StrAny ;
   Result      : CARDINAL ;
   CollNoOccur, CurPos, NodeNoOccur, TempCard     : CARDINAL ;
   P, E        : REAL ;
   SD, Z       : LONGREAL ;
   OK          : BOOLEAN ;
   TempStr     : ARRAY[0..10] OF CHAR ;
   OutString   : ARRAY[0..128] OF CHAR ;
   BadChar     : CHAR ;

BEGIN
  IF PrevNodCollPair^ = NodCollPair^ THEN
     INC( NodCollOccurs ) ;
  ELSE
     IF (NodCollOccurs >= LONGCARD(FileData.RepeatMin)) AND
        (NodCollOccurs <= LONGCARD(FileData.RepeatMax)) THEN
         NodCollWord.Rec :=  CARDINAL(PrevNodCollPair^[0] DIV MAX(CARDINAL)) ;
         NodCollWord.Idx :=  CARDINAL(PrevNodCollPair^[0] MOD MAX(CARDINAL)) ;
         LookUp( NodCollWord, Word, NodeNoOccur ) ;
         OutString[0] := 0C ;
         CurPos := 0 ;
         IF FileData.OutputFormat = Spaces THEN

             SWriteString( OutString, CurPos, Word, 20 );
             SWriteString( OutString, CurPos, ' ( ', 3 ) ;
             SWriteCard( OutString, CurPos, NodeNoOccur, 3 );
             SWriteString( OutString, CurPos, ' ) ', 3 ) ;
             SWriteString( OutString, CurPos, ' <= ', 4 ) ;
             SWriteCard( OutString, CurPos, CARDINAL(NodCollOccurs), 2 );
             SWriteString( OutString, CurPos, ' => ', 4 ) ;

             NodCollWord.Rec :=  CARDINAL(PrevNodCollPair^[1] DIV MAX(CARDINAL)) ;
             NodCollWord.Idx :=  CARDINAL(PrevNodCollPair^[1] MOD MAX(CARDINAL)) ;
             LookUp( NodCollWord, Word, CollNoOccur ) ;
             SWriteString( OutString, CurPos, Word, 20 );
             SWriteString( OutString, CurPos, ' ( ', 3 ) ;
             SWriteCard( OutString, CurPos, CollNoOccur, 3 );
             SWriteString( OutString, CurPos, ' ) ', 8 ) ;
             TempCard := XWrStr( NodeCollFileID, OutString, Result ) ;
         ELSE  (* OutputFormat = Tabs *)
             TempCard := XWrStr( NodeCollFileID, Word , Result );
             XWrNXlate( NodeCollFileID, 11C, Result ) ;
             CardToStr( LONGCARD( NodeNoOccur ) , OutString, 10, OK ) ;
             TempCard := XWrStr( NodeCollFileID, OutString, Result ) ;
             XWrNXlate( NodeCollFileID, 11C, Result ) ;
             CardToStr( LONGCARD( NodCollOccurs ) , OutString, 10, OK ) ;
             TempCard := XWrStr( NodeCollFileID, OutString, Result ) ;
             XWrNXlate( NodeCollFileID, 11C, Result ) ;
             NodCollWord.Rec :=  CARDINAL(PrevNodCollPair^[1] DIV MAX(CARDINAL)) ;
             NodCollWord.Idx :=  CARDINAL(PrevNodCollPair^[1] MOD MAX(CARDINAL)) ;
             LookUp( NodCollWord, Word, CollNoOccur ) ;
             TempCard := XWrStr( NodeCollFileID, Word, Result ) ;
             XWrNXlate( NodeCollFileID, 11C, Result ) ;
             CardToStr( LONGCARD( CollNoOccur ) , OutString, 10, OK ) ;
             TempCard := XWrStr( NodeCollFileID, OutString, Result ) ;
             XWrNXlate( NodeCollFileID, 11C, Result ) ;
         END ;
         P := (REAL(CollNoOccur) / REAL(TotalNoTokens) ) ;
         E := P * REAL(FileData.SpanMax - 1) * REAL(NodeNoOccur) * 2.0 ;
         SD := MATHLIB.Sqrt(LONGREAL( E * (1.0 - P))) ;
         Z := LONGREAL(REAL(NodCollOccurs) - E) / SD ;
         Str.FixRealToStr( Z, 3, TempStr, OK ) ;
         IF Z >= 0.0 THEN
            Str.Concat( TempStr, ' ', TempStr ) ;
         END ;
         TempCard := XWrStr( NodeCollFileID, TempStr, Result ) ;
         XWrLn( NodeCollFileID, Result ) ;
     END ;
     NodCollOccurs := 1 ;
     PrevNodCollPair^ := NodCollPair^ ;
  END ;
END OutputNodeCollPair ;


PROCEDURE GetNodCollOutput ;  (* m.s. - output words to *.nod file *)

VAR
    Result : CARDINAL ;
    NodCollPair: NodCollPairPtr ;
    pos, PrevNoOccurs      : CARDINAL ;
    HashID    : LONGINT ;
    OutString: StrAny ;
    CurPos, TempCard : CARDINAL ;
    TempTypeRec : TypeRecPntr;

BEGIN
(*     BCreate(NodCollOutFile , FileData.NodeCollFileName , TRUE, Result ) ; *)

     ALLOCATE( NodCollPair, NodCollPairSize );
     ALLOCATE( PrevNodCollPair, NodCollPairSize );
     LSortReturn( NodCollPair ) ;
     HeadTRec := NIL ;

     (* set status value for next phase *)
     Count := 0 ;
     PrevNodCollPair^ := NodCollPair^ ;
     NodCollOccurs := 0 ;
     Percentage := 0 ;
     LastPercentage := 0 ;
     CurPos := 0 ;
     OutString[0] := 0C ;
     (*RES OLD MSG 453
     Output of sorted Node-Collocate pairs... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 453 );
     PutPercentage( 0 ) ;

     SWriteString( OutString, CurPos, 'TDB: ', 0 ) ;
     SWriteString( OutString, CurPos, FileData.DBName, 0 ) ;
     SWriteString( OutString, CurPos,'   Number of Words in Text: ', 0) ;
     SWriteLongInt( OutString, CurPos, LONGINT(TotalNoTokens), 0 ) ;
     SWriteString( OutString, CurPos, '   Span: from ', 0 ) ;
     SWriteCard( OutString, CurPos, FileData.SpanMin , 0 ) ;
     SWriteString( OutString, CurPos, ' to ', 0 ) ;
     SWriteCard( OutString, CurPos, FileData.SpanMax , 0 ) ;
     SWriteString( OutString, CurPos, ' words ', 0 ) ;
     TempCard := XWrStr( NodeCollFileID, OutString, Result ) ;
(*     WrStr( NodCollOutFile, OutString, Result ) ; *)
     XWrLn( NodeCollFileID , Result ) ;

     WHILE NOT LSortEOS() AND NOT AbortForFileIO() DO
        INC(Count);
        Percentage := VAL(CARDINAL, ( Count * 100 ) DIV NoNodCollPairs) ;
        IF Percentage > LastPercentage THEN
 	  IF Percentage >= 100 THEN
	    Percentage := 99	(* fake a reasonable value *)
	  END ;
          PutPercentage( Percentage ) ;
          LastPercentage := Percentage ;
        END ;
        OutputNodeCollPair( NodCollPair ) ;

(*      (* for testing *)
	FIO.WrLngCard( NodCollOutFile.FileID , NodCollPair^[0], 15 ) ;
	FIO.WrLngCard( NodCollOutFile.FileID , NodCollPair^[1], 15 ) ;
	WrLn( NodCollOutFile, Result ) ;
*)	
        LSortReturn( NodCollPair ) ;
     END ;
     NodCollPair^[0] := MAX(CARDINAL) ;
     NodCollPair^[1] := MAX(CARDINAL) ;
     OutputNodeCollPair( NodCollPair ) ; (* output last record *)

     DEALLOCATE( NodCollPair, NodCollPairSize );
     DEALLOCATE( PrevNodCollPair, NodCollPairSize );

     WHILE HeadTRec <> NIL DO
       TempTypeRec := HeadTRec^.Next ;
       DEALLOCATE( HeadTRec , TSIZE( TypeRecType )) ;
       HeadTRec := TempTypeRec ;
     END ;

(*     BClose( NodCollOutFile , Result ) ; *)
     FIO.Close( TheFileID ) ;
END GetNodCollOutput ;


PROCEDURE GetFinalOutput ;  (* m.s. - output words to collgen.tmp file *)

VAR
    Result : CARDINAL ;
    Sequence : ShortSequencePtr ;
    pos, PrevNoOccurs, Len      : CARDINAL ;
    HashID    : LONGINT ;
    OutFileID  : XFileType ;
    OutStr   : StrAny ;
BEGIN
(*     BCreate(OutFile , FileData.OutFileName , TRUE, Result ) ; *)
     IF NOT XOpenOutput( FileData.OutFileName, 0C, CollMode, OutFileID, OutStr) THEN
         	   (* something wrong ... *)
		   MsgString( FileData.OutFileName, 0 ) ;
		   MsgString( OutStr, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		   XClose( FrequencyFileID ) ;
		   RETURN ;
     END ;	

     ALLOCATE( Sequence, ShortSequenceSize ) ;
     LSortReturn( Sequence ) ;

     (* set status value for next phase *)
     Count := 0 ;

     LastPercentage := 0 ;
     (*RES OLD MSG 454
     Output of final sorted Fixed Phrases... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 454 );
     PutPercentage( 0 ) ;

     WHILE NOT LSortEOS() AND NOT AbortForFileIO() DO
        INC(Count);
        Percentage := VAL(CARDINAL, ( Count * 100 ) DIV NoMaximalPhrases) ;
        IF Percentage > LastPercentage THEN
 	  IF Percentage >= 100 THEN
	    Percentage := 99	(* fake a reasonable value *)
	  END ;
          PutPercentage( Percentage ) ;
          LastPercentage := Percentage ;
        END ;

	FIO.WrCard( OutFileID.ID.FileID , Sequence^.NoOccurs, 3 ) ;
        IF FileData.OutputFormat = Tabs THEN
  	   WrStr( OutFileID.ID, 11C, Result ) ;
        ELSE
           WrStr( OutFileID.ID, '  ', Result ) ;
        END ;
	Len := XWrStr( OutFileID, Sequence^.Text, Result ) ;
	XWrLn( OutFileID, Result ) ;
(*	
	WrStr( OutFile, Sequence^.Text, Result ) ;
	WrLn( OutFile, Result ) ;
*)
        LSortReturn( Sequence ) ;
     END ;
     XClose( OutFileID ) ;
END GetFinalOutput ;


PROCEDURE GetMaximalOutput ;  (* m.s. - output words to collgen.tmp file *)

VAR
    Result : CARDINAL ;
    Sequence : SequencePtr ;
    pos, PrevNoOccurs      : CARDINAL ;
    HashID    : LONGINT ;
    OutStr   : StrAny ;
BEGIN
     IF NOT XOpenOutput( FileData.FrequencyFileName, 0C, CollMode, FrequencyFileID, OutStr) THEN
         	   (* something wrong ... *)
		   MsgString( FileData.FrequencyFileName, 0 ) ;
		   MsgString( OutStr, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		   XClose( FrequencyFileID ) ;
		   RETURN ;
     END ;	

(*     BCreate(TempFile , FileData.FrequencyFileName , TRUE, Result ) ; *)
     ALLOCATE( Sequence, SequenceSize ) ;
     LSortReturn( Sequence ) ;
     PrevNoOccurs := Sequence^.NoOccurs ;
     (* set status value for next phase *)
     Count := 0 ;
     Percentage := 0 ;
     LastPercentage := 0 ;
     (*RES OLD MSG 455
     Output of Maximal Phrases... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 455 );
     PutPercentage( 0 ) ;
     (* Trace.DoTrace := TRUE ;

     IF Trace.DoTrace THEN
        Trace.TWriteLn ;
     END ;
     *)
     NoMaximalPhrases := 0 ;
     NoRules := 0 ;
     WHILE NOT LSortEOS() AND NOT AbortForFileIO() DO
        INC(Count);
        Percentage := VAL(CARDINAL,(Count * 100) DIV NoSortRecs) ;
           IF Percentage > LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage ) ;
              LastPercentage := Percentage ;
           END ;

        IF PrevNoOccurs <> Sequence^.NoOccurs THEN
            (* IF Trace.DoTrace THEN
              (* Trace.TWriteString( ' Real Memory (before dump) HeapAvail : ' ) ;
              Trace.TWriteCard( HeapAvail( MainHeap ) ,0);
              Trace.TWriteString( ' Total Available : ' ) ;
              Trace.TWriteCard( HeapTotalAvail ( MainHeap ) , 0 ) ;*)
              Trace.TWriteString( ' Occurence number : ' ) ;
              Trace.TWriteCard( PrevNoOccurs , 0 ) ;
              Trace.TWriteLn ;
           END ;
           *)
           DumpHash( FrequencyFileID ) ;
          (* FreeHashMemory ;  (* reclaim memory after output of each frequency list *)*)
           EndVirtualMemory ;
           (* IF Trace.DoTrace THEN
              Trace.TWriteString( ' Real Memory (after EndVirtualM) HeapAvail : ' ) ;
              Trace.TWriteCard( HeapAvail( MainHeap ) ,0 );
              Trace.TWriteString( ' Total Available : ' ) ;
              Trace.TWriteCard( HeapTotalAvail ( MainHeap ) , 0 ) ;
              Trace.TWriteLn ;
           END ;
           *)
           InitVirtualMemory ;
           InitVirtHash ;
           InitSpaceType( VSequenceUnusedSpace ) ;
           PrevNoOccurs := Sequence^.NoOccurs ;
        END ;

        SearchHashTable( Sequence , HashID ) ;
        InsertHash( HashID , Sequence ) ;

        (*  << testing >>
       	OutStr[0] := 0C ;
	FIO.WrCard( Frequency.FileID , Sequence^.NoOccurs, 6 ) ;
	WrStr( TempFile, '  ', Result ) ;
	WrStr( TempFile, Sequence^.Text, Result ) ;
	WrLn( TempFile, Result ) ;
	<< testing >> *)
	
        LSortReturn( Sequence ) ;
     END ;
     DumpHash( FrequencyFileID ) ;
(*     FreeHashMemory ;  (* reclaim memory after output of each frequency list *)*)
     EndVirtualMemory ;
     DEALLOCATE( Sequence, SequenceSize ) ;
     XClose( FrequencyFileID ) ;
     IF FileData.GenRuleFile THEN
        XClose( RuleFileID ) ;
     END ;
     SpaceReserved := 0 ;
END GetMaximalOutput ;

PROCEDURE DumpSortError( SortResult : CARDINAL ) ;

VAR     MsgId : CARDINAL ;

BEGIN
   CASE SortResult OF
 	   0 : (* Sorted OK *)	|
 	   3 :
 		(*RES OLD MSG 311
 		Insufficient available Lower Memory caused sorting to fail.)
 		*)
 		MsgId := (*RES REM INS *) 311 ; |
 	   8 :
 		(*RES OLD MSG 312
 		Sorting failed when a too-long word was encountered.
 		*)
 		MsgId := (*RES REM INS *) 312 ; |
 	   9 :
 		(*RES OLD MSG 313
 		Sorting failed when more than 2,147,483,647 words encountered in the .TDB.
 		*)
 		MsgId := (*RES REM INS *) 313 ; |
 	   10 :
 		(*RES OLD MSG 314
 		Sorting failed because the disk is full.
 		*)
 		MsgId := (*RES REM INS *) 314 ; |
 	   11 :
 		(*RES OLD MSG 315
 		Sorting failed because of a read-error.
 		*)
 		MsgId := (*RES REM INS *) 315 ; |
 	   12 :
 		(*RES OLD MSG 316
 		Sorting Failed Because there are too many Files in the Directory
 		Where the Temporary Sort File was to Go.
 		*)
 		MsgId := (*RES REM INS *) 316 ; |
 	   ELSE
 		(*RES OLD MSG 317
 		Sorting failed because of an unknown return code (%0).
 		*)
 		MsgId := (*RES REM INS *) 317 ;
 	   END ;
 	   CASE SortResult OF
 	     3, 8, 9, 10, 11, 12: ; (* do nothing *)
 	     ELSE
 		MsgCard( SortResult, 0);
 	     END ;
 	   PutResError( MsgId );

END DumpSortError ;


PROCEDURE Run(VAR BaseWind: TWB.WinType ; VAR MsgStr : ARRAY OF CHAR);
   TYPE
      StatusType   = RECORD  (* m.s. *)
                Percent            : CARDINAL ;	
                MsgText            : StrAny ;
              END ;
   CONST
	MAXCARDINAL = MAX(CARDINAL) ;
   VAR
	len : CARDINAL;
	MsgId : CARDINAL ;
	Drive : CHAR ;
	ch    : CHAR ;
	AmountNeeded,
	AmountDiskFree : LONGCARD ;
	StatusMenu : MenuID;
	SortResult : CARDINAL ;
	Status     : StatusType ;
   BEGIN
	Status.MsgText[0] := 0C ;
	Status.Percent := 0 ;
	StartMenu(Status);
	CharField( Status.MsgText );
	CardField(Status.Percent);
	MakeMenu( StatusMenuResID, StatusMenu);
	ClearMenuArea(BaseWind, 0, YPosForStatusMenu, StatusMenu);
	ShowFixedText(BaseWind, StatusMenu, 0, YPosForStatusMenu);
	Percentage := 0;
	ShowMenu(BaseWind, StatusMenu, 0, YPosForStatusMenu, Status);

	StatsWind := BaseWind ;

        GetFieldInfo( StatusMenu, 0, PosXStatus, PosYStatus, LenStatus ) ;
        INC( PosYStatus, YPosForStatusMenu ) ;
        GetFieldInfo( StatusMenu, 1, PosXPerCent, PosYPerCent, len ) ;
        INC( PosYPerCent, YPosForStatusMenu ) ;
    	
	ALLOCATE( HRecord, HyperLength ) ;

        CheckColl := FileData.NodeCollocate OR FunctionWords ;

	IF NOT UsingCorpusFile THEN
	   dummy := OpenTDB( TDBFileNames^[ NumbFiles ]^ ) ; (* <<<--- ??? *)
	END ;
	SetTypeBitTable ;
	
	DataRecSize := FileData.SpanMax * TSIZE(HRecPntr) + TSIZE(CARDINAL) ;
	IF (Length(FileData.TempDiskArea) >= 2) AND (FileData.TempDiskArea[1] = ':') THEN
	   Drive := FileData.TempDiskArea[0]
	ELSE
	   CurrentDrive( Drive )
	END ;
	AmountDiskFree := DiskFree( Drive ) ;
	(* NoTokens is set by SetTypeBitTable PROC -- an overestimate *)			
	AmountNeeded := ((VAL(LONGCARD,DataRecSize) * NoTokens * VAL(LONGCARD,FileData.SpanMax) DIV
			MAXCARDINAL) + 1) * MAXCARDINAL ; (* nearest full 8088 segment *)
	IF AmountDiskFree < AmountNeeded THEN
            (*RES OLD CHE 23
            Drive %0: has %1K free disk space, but the minimum needed just for sorting
            is estimated to be %2K.  Press "Y" to continue, or "N" to stop:
            =YN
            *)
	    MsgString( Drive, 0);
	    MsgCard( VAL(CARDINAL, AmountDiskFree DIV 1024), 0);
	    MsgCard( VAL(CARDINAL, AmountNeeded DIV 1024), 0);
	    ResAskUser( (*RES REM INS *) 23, "YN", ch );
	    IF ch = "N" THEN  RETURN  END ;
	END ;
	WITH CollDisplayTab[0] DO
	     Pos := 5;
	     Type := Left;
	     FilPat := '';
	END;
    	(* Trace.DoTrace := TRUE ; *)
        PutHeapAvailable( ' Before Node Collocate hash space allocated ' ) ;

        PutHeapAvailable( 'Before GetInput ' ) ;
        SortResult := MAX(CARDINAL) ;

	SortResult := LTurboSort( DataRecSize, GetInput, LessCompare, GetOutput,
				  FileData.TempDiskArea ) ;
        PutHeapAvailable( 'after GetInput ' ) ;
	IF SortResult <> 0 THEN
           DumpSortError( SortResult ) ;
	ELSE
           IF FileData.NodeCollocate THEN
        	SortResult := LTurboSort( NodCollPairSize, GetNodCollInput, NodCollCompare, GetNodCollOutput,
        				  FileData.TempDiskArea ) ;
                PutHeapAvailable( 'after NodColl processing ' ) ;
        	IF SortResult <> 0 THEN
                   DumpSortError( SortResult ) ;
                   RETURN ;
                END ;
           END ;
           IF (NOT NodeCollocateOnly) AND FileData.MaximalPhrase THEN
                (* LSortFreeUp ;
                LSortReset( -1 ) ; *)

                InitVirtualMemory ;

                InitVirtHash ;

                InitSpaceType( VSequenceUnusedSpace ) ;
                PutHeapAvailable( 'after InitVirtualMemory ' ) ;

        	SortResult := LTurboSort( SequenceSize, GetMaximalInput, MaximalCompare, GetMaximalOutput,
        				  FileData.TempDiskArea ) ;
                PutHeapAvailable( 'after output of maximal phrases ' ) ;
        	IF SortResult <> 0 THEN
        	  DumpSortError( SortResult ) ;
        	ELSE
                   IF FileData.GenCollOut THEN
                      SortResult := LTurboSort( ShortSequenceSize, GetFinalInput, FinalCompare, GetFinalOutput,
        				  FileData.TempDiskArea ) ;
        	   END ;			
        	   IF SortResult <> 0 THEN
        	      DumpSortError( SortResult ) ;
        	   ELSIF FileData.GenRuleFile THEN
	       	      SortResult := LTurboSort( TSIZE(RuleType), GetRuleInput,  RuleCompare, GetRuleOutput,
	       	                          FileData.TempDiskArea ) ;
        	   END ;
        	END ;      			
       	     END ;
        END ;	
        IF SortResult = 0 THEN
           Copy( MsgStr, 'COLLGEN finished successfully.');
        ELSE
           Copy(MsgStr, 'COLLGEN finished unexpectedly, resulting output files may not be reliable.' ) ;
        END ;
END Run;

END RUNSource .
