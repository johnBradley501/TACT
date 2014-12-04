IMPLEMENTATION MODULE RUNSource ;

(* copyright (c) 1989-96 Ian Lancashire, Lidio Presutti, University of Toronto *)

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

(*<Debug IMPORT IO ; Debug>*)

IMPORT FIO, Lib, Str, TWB, (* m.s. *) BitOps ;
FROM ResMessages IMPORT
   (* proc *)  MsgString, MsgCard, PutResError, PutResWarning, ResAskUser, GetResMessage;
FROM ResMenus IMPORT
  (* type *)  MenuID,
  (* proc *)  StartMenu, CardField, CharField, MakeMenu, DestroyMenu, GetFieldInfo,
		ClearMenuArea, ShowFixedText, ShowMenu;
FROM Str IMPORT Length, Compare, Copy, Append ;
FROM SYSTEM IMPORT TSIZE, SIZE ;
FROM StringIO IMPORT SWriteString, SWriteChar, SWriteCard;
FROM Storage IMPORT  ALLOCATE, DEALLOCATE ;
FROM HyperDataModel IMPORT HyperData, HyperLength, HNoTokens, HTypePntr, TDBTypePntr,
                 HTypeData ;
FROM ErrorBase IMPORT
  (* Proc *) ProgramErrorAndHalt;
FROM GlobalDefs IMPORT FileNameType, StrAny ;
FROM WordBase IMPORT IntToSortWord, SortToIntWord, SortNoBitsPerChar ;
FROM KeyTranslation IMPORT
  (* Const *) IntEnhOn, IntEnhOff, IntTab,
  (* Type  *) TabInfo, TabType,
  (* Procs *) WriteScreenField ;
FROM Windows  IMPORT
  (* Const *) RegularAttr ;
FROM Translations IMPORT
 (* type *) XFileType,
 (* proc *) XWriteLine, XClose ;
FROM Utils IMPORT BDelete ;
FROM UtilsTwo IMPORT IOErrorMessage;
FROM DiskDirectory IMPORT
 (* procs *) DiskFree, CurrentDrive ;
FROM PrintModule IMPORT PrintMaster, PrintProcType, PrintActionType,
		AbortProc, AbortForFileIO, WriteWithTabs;

FROM StartUp IMPORT
  (* Type *) AnagramTypeType,
  (* Vars *) FileData, OutFileID, RuleFileID, AnagramModePresent, BaseWPtr;
FROM TDBInit IMPORT
  (* Vars *) BeginType, EndTypeRec, EndTypeIdx, NoTypes, TDBFileID ;
FROM LongSort IMPORT
  (* Procs *) LTurboSort, LSortRelease, LSortReturn, LSortEOS, LSortReset, LSortGetPos ;

CONST
   YPosForStatusMenu = 21;

(*RES OLD MNU 32
                  Status: %0__________________________________
    Percentage Completed: %1_ % [estimated]

*)

   StatusMenuResID = (*RES REM INS*) 32 ;

   FileHeaderResource = 113 ;	(* >> MSG defined in MAKBAS: SetupFil.MOD << *)
   MAXCARDINAL = MAX(CARDINAL) ;

TYPE
   HRecPntr = RECORD
		Rec: CARDINAL;
		Idx: CARDINAL;
	      END;
   WordStrType  = ARRAY[0..19] OF CHAR;
   DataTypePntr = POINTER TO DataType ;
   DataType = RECORD
		AnagramForm	: WordStrType ;
		HeadWord	: WordStrType ;
   	      END ;
   StatusType   = RECORD  (* m.s. *)
                Percent            : CARDINAL ;	
                MsgText            : ARRAY [0..80] OF CHAR ;
              END ;
CONST
   MaxCARDINAL = MAX(INTEGER) DIV TSIZE(HRecPntr) - 100 ;  (* any large number will do *)

VAR
   Status       : StatusType; (* m.s. *)
   DataRecSize	: CARDINAL ;
   DataRec	: DataType ;
   RecNo	: CARDINAL ;
   RecIdx	: CARDINAL ;
   HRecord	: POINTER TO HyperData ;
   TypeRec	: HTypePntr ;

   Percentage	: CARDINAL ;
   LastPercentage : CARDINAL ;
   Count	: LONGCARD ;
   AnagramCount	: LONGCARD ;
   NoSortRecs	: LONGCARD ;
   NoCompares	: LONGCARD ;
   BytesRead	: CARDINAL ;

   StatsWind	: TWB.WinType ;
   LenStatus	: CARDINAL ;
   PosXStatus	: CARDINAL ;
   PosYStatus	: CARDINAL ;
   PosXPerCent	: CARDINAL ;
   PosYPerCent	: CARDINAL ;
   MsgTxt	: StrAny;
   AnagramDispTab: ARRAY[0..0] OF TabInfo;
   AnagramFile	: FIO.File ;
   AnagramFileName : ARRAY[0..64] OF CHAR ;

   ch:       CHAR;
   FunctKey: BOOLEAN;
   DoRead:   BOOLEAN;

PROCEDURE PutRunStatus( ResID : CARDINAL );
   BEGIN
	GetResMessage(ResID,MsgTxt);
	WriteScreenField( StatsWind, LenStatus, PosXStatus,
			PosYStatus, MsgTxt, RegularAttr, TRUE ) ;
   END PutRunStatus;

PROCEDURE PutPercentage( N : CARDINAL ) ;
   VAR
	rc	: CARDINAL ;
	LongStr	: ARRAY[0..4] OF CHAR ;
   BEGIN
	rc := 0;
	LongStr[0] := 0C;
	SWriteCard(LongStr,rc,N,3);
	TWB.Use(StatsWind);
	TWB.GotoXY( PosXPerCent, PosYPerCent );
	TWB.WrStr(LongStr);
   END PutPercentage;

PROCEDURE GetTypeInfo( VAR Data : HTypePntr ) : BOOLEAN ;
   VAR
       TDBData : TDBTypePntr ;
       WordPtr : POINTER TO BitOps.PackedStrType ;
       OK      : BOOLEAN ;
   BEGIN
      OK := TRUE ;
      WHILE OK DO
        OK := FALSE ;
	IF (RecNo > EndTypeRec) OR ( (RecNo = EndTypeRec) AND (RecIdx > EndTypeIdx)) THEN
	   RETURN FALSE ;
	END ;
	IF (RecIdx > HRecord^.NoDataPtrsUsed) AND (RecNo < EndTypeRec) THEN
	   INC( RecNo ) ;
	   RecIdx := 1 ;
	   BytesRead := FIO.RdBin( TDBFileID, HRecord^, HyperLength ) ;
	   IF BytesRead <> HyperLength THEN
	      ProgramErrorAndHalt( 'RunSource(GetTypeInfo): short record read from .TDB file.' )
	   END ;
	   IF HRecord^.NoDataPtrsUsed = 0 THEN (* m.s. - no words in this record, skip *)
	      OK := TRUE ;
	   END ;
	END ;
      END ;	
      (* m.s. - Data -> TDBData, must unpack word *)
      TDBData := ADR( HRecord^.TextData[ HRecord^.DataPntr[ RecIdx ] ] ) ;
	
      (* m.s. new stuff *)
      BitOps.UnPack( TDBData^.PackedWord, Data^.Word, SortNoBitsPerChar ) ;
      Data^.NoOccur := TDBData^.NoOccur ;

      INC( RecIdx ) ;
      RETURN TRUE ;
   END GetTypeInfo ;

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
	RETURN log2
   END Log2 ;


(*$F*)
PROCEDURE AnagramLess( i, j : CARDINAL ) : BOOLEAN ;
   BEGIN
	RETURN DataRec.AnagramForm[i-1] < DataRec.AnagramForm[j-1] ;
   END AnagramLess ;

PROCEDURE AnagramSwap( i, j : CARDINAL ) ;
   VAR  ch : CHAR ;
   BEGIN
	ch := DataRec.AnagramForm[i-1] ;
	DataRec.AnagramForm[i-1] := DataRec.AnagramForm[j-1];
	DataRec.AnagramForm[j-1] := ch ;
   END AnagramSwap ;

PROCEDURE GetInput ;
   VAR
	I, Len : CARDINAL ;
   BEGIN
	RecNo := BeginType ;
	RecIdx := 2 ;
	FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, BeginType )  ) ;
	BytesRead := FIO.RdBin( TDBFileID, HRecord^, HyperLength ) ;
	IF BytesRead <> HyperLength THEN
	   ProgramErrorAndHalt( 'RunSource(GetTypeInfo): short record read from .TDB file.' )
	END ;

	Count := 0 ;
	LastPercentage := 0 ;
	NoSortRecs := 0 ;
	(*RES OLD MSG 503
	Reading the TDB file.
	*)
	PutRunStatus( (*RES REM INS*) 503 );
        ALLOCATE( TypeRec, TSIZE( HTypeData ) );
	WHILE GetTypeInfo( TypeRec ) DO
	   INC(Count);
	   Percentage := VAL(CARDINAL,Count * 100 DIV LONGCARD(NoTypes)) ;
	   IF Percentage >= LastPercentage THEN
		PutPercentage( Percentage ) ;
		INC(LastPercentage, 4) ;
	   END;
	   Str.Copy( DataRec.HeadWord, TypeRec^.Word ) ;
	   Str.Copy( DataRec.AnagramForm, TypeRec^.Word ) ;

	   (* next ignore accents etc. *)
	   I := Str.Pos( DataRec.AnagramForm, 02C ) ;
	   IF I < MAX(CARDINAL) THEN  DataRec.AnagramForm[I] := 0C  END ;
	   Len := Str.Length( DataRec.AnagramForm ) ;
	   Lib.QSort( Len, AnagramLess, AnagramSwap ) ;
	   LSortRelease( DataRec ) ;
	   INC( NoSortRecs ) ;
	END ;
	Lib.Fill( ADR(DataRec), DataRecSize, 255 ) ;	(* dummy sentinal record *)
	LSortRelease( DataRec ) ;

	DEALLOCATE( HRecord, HyperLength ) ;
        DEALLOCATE( TypeRec, TSIZE( HTypeData ) ) ;
	(* set status value for next phase -- calculated above !! *)
	
	(* Note: QuickSort is order O( N log2(N) ) comparisons, it appears *)
	(*	 to be N log2(N) + 4 N					   *)
	NoCompares := NoSortRecs * VAL(LONGCARD, Log2(NoSortRecs) + 4) ;
	Count := 0 ;
	LastPercentage := 0 ;
	(*RES OLD MSG
	Sort phase.
	*)
	PutRunStatus( (*RES REM INS*) 308 );
   END GetInput ;

PROCEDURE LessCompare( X, Y : DataTypePntr ) : BOOLEAN ;
   VAR
	rc	: INTEGER ;
	RetVal	: BOOLEAN ;
   BEGIN
	INC(Count);
	Percentage := VAL(CARDINAL,Count * 100 DIV NoCompares) ;
	IF Percentage >= LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage ) ;
		INC(LastPercentage) ;
	END ;
	rc := Str.Compare( X^.AnagramForm, Y^.AnagramForm ) ;
	IF rc < 0 THEN  RetVal := TRUE
	ELSIF rc = 0 THEN
	   rc := Str.Compare( X^.HeadWord, Y^.HeadWord ) ;
	   IF rc < 0 THEN  RetVal := TRUE
	   ELSE RetVal := FALSE
	   END ;
	ELSE
	   RetVal := FALSE
	END ;
	RETURN RetVal ;
   END LessCompare ;

(*$N*)

PROCEDURE CompareNE( X, Y : DataType ) : BOOLEAN ;
   BEGIN
	RETURN Str.Compare( X.AnagramForm, Y.AnagramForm ) <> 0 ;
   END CompareNE ;

PROCEDURE CompareEQ( X, Y : DataType ) : BOOLEAN ;
   BEGIN
	RETURN Str.Compare( X.AnagramForm, Y.AnagramForm ) = 0 ;
   END CompareEQ ;

(*$F*)
PROCEDURE WriteAnagramData ;
   VAR
	NextDataRec, DataRec : DataType ;
	DupCount : CARDINAL ;
	IOResult : CARDINAL;
	ErrorMsg : StrAny ;
	AnagramsFound : BOOLEAN ;
   BEGIN
	(* set status value for next phase *)
	Count := 0 ;
	LastPercentage := 0 ;
	AnagramCount   := 0 ;

	PutRunStatus( (*RES REM INS*) 521 ); (* 521 defined in tactfreq runsourc.mod *)
	
	Str.Concat( AnagramFileName, FileData.TempDiskArea, "$ANAGRM$.DAT" ) ;
	AnagramFile := FIO.Create( AnagramFileName ) ;
	IF FIO.IOresult() <> 0 THEN
	    (*RES OLD MSG 504
	    Can not create a temp file (%0).
	    *)
	    MsgString( FileData.TempDiskArea, 0);
	    PutResWarning( (*RES REM INS *) 504 );
	    RETURN ;
	END ;

	AnagramsFound := FALSE ;
	LSortReturn( DataRec ) ;
	WHILE NOT LSortEOS() DO
	   DupCount := 0 ;
	   LSortReturn( NextDataRec ) ;
	   WHILE NOT LSortEOS() AND CompareEQ( DataRec, NextDataRec ) DO
		INC(Count);
		Percentage := VAL(CARDINAL,Count * 100 DIV NoSortRecs) ;
		IF Percentage >= LastPercentage THEN
		   PutPercentage( Percentage ) ;
		   INC(LastPercentage) ;
		END ;

		IF DupCount = 0 THEN
		   Str.Copy( DataRec.AnagramForm, DataRec.HeadWord ) ;
		   FIO.WrBin( AnagramFile, DataRec, DataRecSize ) ;
		   INC( AnagramCount ) ;
		END ;
		Str.Copy( NextDataRec.AnagramForm, DataRec.HeadWord ) ;
		FIO.WrBin( AnagramFile, NextDataRec, DataRecSize ) ;
		INC( AnagramCount ) ;

		LSortReturn( NextDataRec ) ;
		INC( DupCount ) ;
	   END ;
	   IF DupCount > 1 THEN
		AnagramsFound := TRUE ;
	   END ;
	   DataRec := NextDataRec ;
	END ;
	FIO.Close( AnagramFile ) ;
	IF NOT AnagramsFound THEN
	    (*RES OLD MSG 505
	    No anagrams found in the database %0.
	    *)
	    MsgString( FileData.DBName, 0);
	    PutResWarning( (*RES REM INS *) 505 );
	    IF FileData.GenAnagrams THEN	(* clean up *)
		XClose( OutFileID ) ;
		BDelete( FileData.OutFileName, IOResult );
	    END ;
	    IF FileData.GenRuleFile THEN
		XClose( RuleFileID ) ;
		BDelete( FileData.RuleFileName, IOResult );
	    END ;
	    FIO.Erase( AnagramFileName ) ;
	    RETURN
	END ;
   END WriteAnagramData;

PROCEDURE ReadAnagramData ;
   VAR
	BytesRead : CARDINAL ;
   BEGIN
	Count := 0 ;
	LastPercentage := 0 ;
	NoSortRecs := 0 ;
	(*RES OLD MSG 506
	Reading the temp Anagram data file.
	*)
	PutRunStatus( (*RES REM INS*) 506 );

	AnagramFile := FIO.OpenRead( AnagramFileName ) ;
	BytesRead := FIO.RdBin( AnagramFile, DataRec, DataRecSize ) ;
	WHILE BytesRead = DataRecSize DO
	   INC(Count);
	   Percentage := VAL(CARDINAL,Count * 100 DIV AnagramCount) ;
	   IF Percentage >= LastPercentage THEN
		PutPercentage( Percentage ) ;
		INC(LastPercentage, 4) ;
	   END ;
	   LSortRelease( DataRec ) ;
	   INC( NoSortRecs ) ;
	   BytesRead := FIO.RdBin( AnagramFile, DataRec, DataRecSize ) ;
	END ;
	Lib.Fill( ADR(DataRec), DataRecSize, 255 ) ;	(* dummy sentinal record *)
	LSortRelease( DataRec ) ;

	(* clean up temp file *)
	FIO.Close( AnagramFile ) ;
	FIO.Erase( AnagramFileName ) ;

	(* set status value for next phase -- calculated above !! *)
	
	(* Note: QuickSort is order O( N log2(N) ) comparisons, it appears *)
	(*	 to be N log2(N) + 4 N					   *)
	NoCompares := NoSortRecs * VAL(LONGCARD, Log2(NoSortRecs) + 4 ) ;
	Count := 0 ;
	LastPercentage := 0 ;
	(*RES OLD MSG 308
	Sort phase.
	*)
	PutRunStatus( (*RES REM INS*) 308 );
   END ReadAnagramData ;

PROCEDURE DoOutput( VAR file: XFileType; CheckAbort: AbortProc);
   VAR
	NextDataRec, DataRec : DataType ;
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
	AnagramsFound : BOOLEAN ;

   PROCEDURE CollectAnagrams ;
	BEGIN
	   IF DupCount = 0 THEN
		SortToIntWord( DataRec.HeadWord, KeyStr ) ;
		IF FileData.GenRuleFile THEN
		   RulePos := 0 ;
		   SWriteString( RuleStr, RulePos, KeyStr, 0 );
		   SWriteString( RuleStr, RulePos, ' ', 0 );
		END ;
		IF FileData.GenAnagrams THEN  pos := 0  END ;
	   ELSE
		SortToIntWord( NextDataRec.HeadWord, KeyStr ) ;
	   END ;

	   IF FileData.GenRuleFile THEN
		IF DupCount > 0 THEN  SWriteString( RuleStr, RulePos, ', ', 0 ); END;
		SWriteString( RuleStr, RulePos, '"', 0 );
		SWriteString( RuleStr, RulePos, KeyStr, 0 );
	   END ;
	
	   IF AnagramModePresent  THEN	(* we a file translation table *)
		TempStr[0] := IntEnhOn ;
		FOR I := 1 TO Length( KeyStr ) DO
		   TempStr[I] := KeyStr[I-1]
		END ;
		TempStr[I+1] := IntEnhOff;
		TempStr[I+2] := 0C ;
	   ELSE
		Copy( TempStr, KeyStr )
	   END ;

	   IF FileData.GenAnagrams THEN
		SWriteString( ContextStr, pos, ' ', 0 ) ;
		SWriteString( ContextStr, pos, TempStr, 0 );
	   END ;
	END CollectAnagrams ;

   PROCEDURE PrintRec ;
	VAR status : BOOLEAN ;
	BEGIN
	   IF FileData.GenAnagrams THEN
		IF NOT XWriteLine(OutFileID, '?', ContextStr, IOResult) THEN
		   IOErrorMessage(IOResult, ErrorMsg) ;
		   MsgString( FileData.OutFileName, 0 ) ;
		   MsgString( ErrorMsg, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		END ;
	   END ;
	   IF FileData.GenRuleFile THEN
		IF NOT XWriteLine(RuleFileID, '?', RuleStr, IOResult) THEN
		   IOErrorMessage(IOResult, ErrorMsg) ;
		   MsgString( FileData.RuleFileName, 0 ) ;
		   MsgString( ErrorMsg, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		END ;
	   END ;
	END PrintRec ;

   BEGIN
	(*<Debug
	IO.WrStr( 'Number of compares:' ) ;
	IO.WrLngCard( Count, 10 ) ;
	IO.WrStr( ' estimate:' ) ;
	IO.WrLngCard( NoCompares, 10 ) ;
	Debug>*)

	(* set status value for next phase *)
	Count := 0 ;
	LastPercentage := 0 ;

	PutRunStatus( (*RES REM INS*) 521 ); (* 521 defined in tactstat runsourc.mod *)

	AnagramsFound := FALSE ;
	LSortReturn( DataRec ) ;
	WHILE NOT LSortEOS() AND NOT CheckAbort() DO
	   DupCount := 0 ;
	   REPEAT
		INC(Count);
		Percentage := VAL(CARDINAL,Count * 100 DIV NoSortRecs) ;
		IF Percentage >= LastPercentage THEN
		   PutPercentage( Percentage ) ;
		   INC(LastPercentage) ;
		END ;
		CollectAnagrams ;
		LSortReturn( NextDataRec ) ;
		INC( DupCount ) ;
	   UNTIL LSortEOS() OR CompareNE( DataRec, NextDataRec ) ;
	   IF DupCount > 1 THEN
		AnagramsFound := TRUE ;
		PrintRec ;
	   END ;
	   DataRec := NextDataRec ;
	END ;
	FIO.Close( TDBFileID ) ;
	IF NOT AnagramsFound THEN
	    (* L.P.
	    MsgString( FileData.DBName, 0);
	    PutResWarning( (*RES REM INS *) ???? );
	    IF FileData.GenAnagrams THEN	(* clean up *)
		XClose( OutFileID ) ;
		BDelete( FileData.OutFileName, IOResult );
	    END ;
	    IF FileData.GenRuleFile THEN
		XClose( RuleFileID ) ;
		BDelete( FileData.RuleFileName, IOResult );
	    END ;
	    *)
	    RETURN
	END ;

	IF FileData.GenAnagrams THEN
	   XClose( OutFileID )
	END ;
	IF FileData.GenRuleFile THEN
	   XClose( RuleFileID ) ;
	END ;
   END DoOutput ;

PROCEDURE DoAnagramOutput ;
   BEGIN
	   DoOutput( OutFileID, AbortForFileIO )
   END DoAnagramOutput;


PROCEDURE DoPartialAnagramMatch( VAR file : XFileType; CheckAbort : AbortProc ) ;
   	TYPE
   	   HyperDataPntr = POINTER TO HyperData ;
   	   TypeTableType = ARRAY[0..MaxCARDINAL] OF HyperDataPntr;
   	   WordAny	 = ARRAY[0..64] OF CHAR ;
   	   SetOfChar	 = SET OF CHAR ;
   	VAR
   	   TypeTable	: POINTER TO TypeTableType ;
   	   NoInTable	: CARDINAL ;
   	   CurType	: HRecPntr ;
   	   CurRecNo	: CARDINAL ;
   	   CurHRecord	: HyperDataPntr ;
   	   DummyHRecord	: HyperDataPntr ;
   	   PivotRecNo	: CARDINAL ;
   	   PivotHRecord	: HyperDataPntr ;
   	   i, j		: CARDINAL ;
   	   ThisType	: HRecPntr ;
   	   ThisWord	: WordAny ;
   	   HeadWord	: WordAny ;
   	   AnagramCharSet : SetOfChar ;
	   pos		: CARDINAL ;
	   RulePos	: CARDINAL ;
	   RuleStr	: StrAny ;
	   ContextPos	: CARDINAL ;
	   ContextStr	: StrAny ;
	   TempStr	: StrAny ;
	   IOResult	: CARDINAL;
	   ErrorMsg	: StrAny ;
	   FirstRule	: BOOLEAN ;
   	
	PROCEDURE FindHRecord( Rec : CARDINAL; VAR HRecord : HyperDataPntr ) ;
	   VAR Temp : HyperDataPntr ;
	   BEGIN
	     IF Rec <= NoInTable THEN
		HRecord := TypeTable^[Rec] (* HRecord *)
	     ELSE
		IF Rec = CurRecNo THEN
		   HRecord := CurHRecord
		ELSIF Rec = PivotRecNo THEN
		   HRecord := PivotHRecord
		ELSE
		   (* read it in *)
		   IF HRecord = CurHRecord THEN
		 	(* swap storage addresses *)
			Temp := PivotHRecord ;
			PivotHRecord := CurHRecord ;
			CurHRecord   := Temp ;
		   END ;
		   FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, Rec + BeginType )  ) ;
		   BytesRead := FIO.RdBin( TDBFileID, PivotHRecord^, HyperLength ) ;
		   IF BytesRead <> HyperLength THEN
		      ProgramErrorAndHalt( 'RunSource(FindHRec): short record read from .TDB file.' )
		   END ;
		   PivotRecNo := Rec ;
		   HRecord := PivotHRecord
		END ;
	     END ;
	   END FindHRecord ;
   	
	PROCEDURE GetFirstType( VAR ThisType : HRecPntr; VAR ThisWord : ARRAY OF CHAR );
	   VAR
	      Data	: TDBTypePntr ; (* m.s. - was HTypePntr *)
	      HRecord	: HyperDataPntr ;
	   BEGIN
	      ThisType.Rec := 0 ;
	      ThisType.Idx := 2 ;
	      FindHRecord( ThisType.Rec, HRecord ) ;
	      Data := ADR( HRecord^.TextData[ HRecord^.DataPntr[ ThisType.Idx ] ] ) ;
              (* m.s. - unpack word *)
              BitOps.UnPack( Data^.PackedWord, ThisWord, SortNoBitsPerChar ) ;
(*	      Str.Copy( ThisWord, Data^.Word ) ; *)
	   END GetFirstType ;
   	
	PROCEDURE GetNextType(  VAR ThisType : HRecPntr;
				VAR ThisWord : ARRAY OF CHAR;
				VAR HRecord  : HyperDataPntr ) ;
	   VAR
	      Data	: TDBTypePntr ; (* m.s. - was HTypePntr *)
	
	   BEGIN
	      IF   (ThisType.Rec > EndTypeRec) OR
		 ( (ThisType.Rec = EndTypeRec) AND (ThisType.Idx > EndTypeIdx)) THEN
	         ThisWord[0] := 0C ;
		 RETURN ;
	      END ;
	      INC( ThisType.Idx ) ;
	      FindHRecord( ThisType.Rec, HRecord ) ;
	      WHILE ((ThisType.Idx > HRecord^.NoDataPtrsUsed) AND (ThisType.Rec < EndTypeRec))
	             OR (HRecord^.NoDataPtrsUsed = 0) DO
		 INC( ThisType.Rec ) ;
		 ThisType.Idx := 1 ;
		 FindHRecord( ThisType.Rec, HRecord ) ;
	      END ;
	      Data := ADR( HRecord^.TextData[ HRecord^.DataPntr[ ThisType.Idx ] ] ) ;
              (* m.s. - unpack word *)
              BitOps.UnPack( Data^.PackedWord, ThisWord, SortNoBitsPerChar ) ;
(*	      Str.Copy( ThisWord, Data^.Word ) ; *)
	   END GetNextType ;

	PROCEDURE MakeAnagramCharSet( SortWord : ARRAY OF CHAR; VAR AnagramCharSet : SetOfChar ) ;
	   VAR
	      RetDiaPos, I	: CARDINAL ;
	   BEGIN
	      RetDiaPos := Str.Pos( SortWord, 02C ) ;
	      IF RetDiaPos < MAX(CARDINAL) THEN  SortWord[RetDiaPos] := 0C  END;
	      AnagramCharSet := SetOfChar{} ;  (* start with empty set *)
	      FOR I := 0 TO Str.Length( SortWord ) - 1 DO
		 INCL( AnagramCharSet, SortWord[I] ) ;  (* add each char in SortWord *)
	      END ;
	   END MakeAnagramCharSet ;

	PROCEDURE PartialAnagram( ThisWord : ARRAY OF CHAR; AnagramCharSet : SetOfChar) : BOOLEAN;
	   VAR
	      RetDiaPos, I	: CARDINAL ;
	   BEGIN
	      RetDiaPos := Str.Pos( ThisWord, 02C ) ;
	      IF RetDiaPos < MAX(CARDINAL) THEN  ThisWord[RetDiaPos] := 0C  END;
	      FOR I := 0 TO Str.Length( ThisWord ) - 1 DO
		 IF NOT (ThisWord[I] IN AnagramCharSet) THEN  RETURN FALSE  END ;
	      END ;
	      RETURN TRUE ;
	   END PartialAnagram ;

	PROCEDURE WriteContextRec ;
	   VAR status : BOOLEAN ;
	   BEGIN
		IF FileData.GenAnagrams THEN
		     IF NOT XWriteLine(OutFileID, '?', ContextStr, IOResult) THEN
			IOErrorMessage(IOResult, ErrorMsg) ;
			MsgString( FileData.OutFileName, 0 ) ;
			MsgString( ErrorMsg, 0 ) ;
			PutResError( FileHeaderResource ) ;
		     END ;
		END ;
	   END WriteContextRec ;

	PROCEDURE WriteRuleRec ;
	   BEGIN
		IF FileData.GenRuleFile THEN
		   IF NOT XWriteLine(RuleFileID, '?', RuleStr, IOResult) THEN
		      IOErrorMessage(IOResult, ErrorMsg) ;
		      MsgString( FileData.RuleFileName, 0 ) ;
		      MsgString( ErrorMsg, 0 ) ;
		      PutResError( FileHeaderResource ) ;
		   END ;
		END ;
	   END WriteRuleRec ;

	PROCEDURE PrintHeadWord( HeadWord : ARRAY OF CHAR ) ;
	   VAR	WordStr	: WordAny ;
		I	: CARDINAL ;
	   BEGIN
		SortToIntWord( HeadWord, WordStr ) ;
		IF FileData.GenRuleFile THEN
		   RulePos := 0 ;
		   SWriteString( RuleStr, RulePos, WordStr, 0 );
		   SWriteString( RuleStr, RulePos, ' ', 0 );
		   FirstRule := TRUE ;
		END ;
		IF AnagramModePresent  THEN	
		   (* we have a file translation table *)
		   TempStr[0] := IntEnhOn ;
		   FOR I := 1 TO Length( WordStr ) DO
			TempStr[I] := WordStr[I-1]
		   END ;
		   TempStr[I+1] := IntEnhOff;
		   TempStr[I+2] := 0C ;
		ELSE
		   Copy( TempStr, WordStr )
		END ;

		IF FileData.GenAnagrams THEN
		   ContextPos := 0  ;
		   SWriteString( ContextStr, ContextPos, TempStr, 0 );
		   SWriteString( ContextStr, ContextPos, ': ', 0 ) ;
		END ;
	   END PrintHeadWord ;

	PROCEDURE PrintWord( HeadWord : ARRAY OF CHAR ) ;
	   VAR WordStr	: WordAny ;
	   BEGIN
		SortToIntWord( HeadWord, WordStr ) ;
		IF FileData.GenAnagrams THEN
		   IF ContextPos > 72 THEN
			WriteContextRec ;
			ContextPos := 0 ;
			SWriteString( ContextStr, ContextPos, ' ', 3 );
		   END;
		   SWriteString( ContextStr, ContextPos, ' ', 0 ) ;
		   SWriteString( ContextStr, ContextPos, WordStr, 0 );
		END ;
		IF FileData.GenRuleFile THEN
		   IF FirstRule THEN
			FirstRule := FALSE ;
		   ELSE
			SWriteString( RuleStr, RulePos, ',', 0 );
		   END ;
		   IF RulePos > 72 THEN
			WriteRuleRec ;
			RulePos := 0 ;
			SWriteString( RuleStr, RulePos, '  ', 0 );
		   END;
		   SWriteString( RuleStr, RulePos, '"', 0 );
		   SWriteString( RuleStr, RulePos, WordStr, 0 );
		END ;
	   END PrintWord ;
	
	BEGIN	(* DoPartialAnagramMatch *)
	   (* compute & allocate the amount of HRecs that we can keep in memory *)
(* m.s.	   NoInTable := HeapAvail( MainHeap ) DIV 64 - 5 (* in 1Ks *) ;
	   IF NoInTable > (EndTypeRec - BeginType ) THEN
		NoInTable := EndTypeRec - BeginType ; (* use max # of HRecs *)
	   ELSE
*)	
	   NoInTable := EndTypeRec - BeginType ; (* use max # of HRecs *)
 	   ALLOCATE( CurHRecord, HyperLength ) ;
	   CurRecNo := MAXCARDINAL ;
	   ALLOCATE( PivotHRecord, HyperLength ) ;
	   PivotRecNo := MAXCARDINAL ;
(*	   END ; *)
	   ALLOCATE( TypeTable, (NoInTable+1) * TSIZE( HyperDataPntr ) );
	   FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, BeginType )  ) ;
	   FOR i := 0 TO NoInTable DO
		ALLOCATE( TypeTable^[i], HyperLength ) ;
		BytesRead := FIO.RdBin( TDBFileID, TypeTable^[i]^, HyperLength ) ;
		IF BytesRead <> HyperLength THEN
		   ProgramErrorAndHalt( 'RunSource(PartialAnagrams): short record read from .TDB file.' )
		END ;
	   END ;
	   (*RES OLD MSG 507
	   Finding ALL partial Anagrams.
	   *)
	   PutRunStatus( (*RES REM INS *) 507 );
	   CurType.Rec := 0 ;
	   CurType.Idx := 1 ; (* will point to first type later *)
	   FOR i := 1 TO NoTypes DO
		INC(Count);
		Percentage := VAL(CARDINAL,Count * 100 DIV LONGCARD(NoTypes)) ;
		IF Percentage >= LastPercentage THEN
		   PutPercentage( Percentage ) ;
		   INC(LastPercentage) ;
		END ;
		IF CheckAbort() THEN  RETURN  END ;
		GetNextType( CurType, HeadWord, CurHRecord ) ;
		CurRecNo := CurType.Rec ;
		MakeAnagramCharSet( HeadWord, AnagramCharSet ) ;
		PrintHeadWord( HeadWord ) ;
		GetFirstType( ThisType, ThisWord ) ;
		FOR j := 1 TO NoTypes DO
		   IF PartialAnagram( ThisWord, AnagramCharSet ) THEN
			PrintWord( ThisWord )
		   END ;
		   GetNextType( ThisType, ThisWord, DummyHRecord );
		END ;
		WriteContextRec ;	(* only if needed *)
		WriteRuleRec ;
	   END ;
	   FIO.Close( TDBFileID ) ;
	   IF FileData.GenAnagrams THEN  XClose( OutFileID )  END ;
	   IF FileData.GenRuleFile THEN  XClose( RuleFileID )  END ;
	END DoPartialAnagramMatch ;

PROCEDURE Run( VAR MsgStr : ARRAY OF CHAR );
   VAR
	len		: CARDINAL;
	StatusMenu	: MenuID;

   PROCEDURE DoProperAnagrams ;
      VAR
	Drive : CHAR ;
	ch    : CHAR ;
	AmountNeeded,
	AmountDiskFree : LONGCARD ;
	SortResult : CARDINAL ;

   PROCEDURE SortErrorMsg ;
      VAR MsgId : CARDINAL ;
      BEGIN
	IF SortResult <> 0 THEN
	   CASE SortResult OF
	   0 : (* Sorted OK *)	|
	   3 :
		(*RES OLD MSG 311
		Sort routine failure: Workarea too small (insufficient memory available.)
		*)
		MsgId := (*RES REM INS *) 311 ; |
	   8 :
		(*RES OLD MSG 312
		Sort routine failure: Illegal itemlength.
		*)
		MsgId := (*RES REM INS *) 312 ; |
	   9 :
		(*RES OLD MSG 313
		Sort routine: More than 2,147,483,647 records (words in TDB file).
		*)
		MsgId := (*RES REM INS *) 313 ; |
	   10 :
		(*RES OLD MSG 314
		Sort routine: Write error during sorting (disk full).
		*)
		MsgId := (*RES REM INS *) 314 ; |
	   11 :
		(*RES OLD MSG 315
		Sort routine: Read error during sorting.
		*)
		MsgId := (*RES REM INS *) 315 ; |
	   12 :
		(*RES OLD MSG 316
		Sort routine: Impossible to create (sort temporary) file -- directory full.
		*)
		MsgId := (*RES REM INS *) 316 ; |
	   ELSE
		(*RES OLD MSG 317
		Sort routine failure: Unknown return code (%0) from sort.
		*)
		MsgId := (*RES REM INS *) 317 ;
	   END ;
	   CASE SortResult OF
	     3, 8, 9, 10, 11, 12: ; (* do nothing *)
	     ELSE
		MsgCard( SortResult, 0);
	   END ;
	   PutResError( MsgId );
	END ;
     END SortErrorMsg ;

     BEGIN	(* DoProperAnagrams *)
	ALLOCATE( HRecord, HyperLength ) ;

	FIO.IOcheck := FALSE ;
	DataRecSize := SIZE( DataRec ) ;
	IF (Length(FileData.TempDiskArea) >= 2) AND (FileData.TempDiskArea[1] = ':') THEN
	   Drive := FileData.TempDiskArea[0]
	ELSE
	   CurrentDrive( Drive )
	END ;
	AmountDiskFree := DiskFree( Drive ) ;
	AmountNeeded := ( ( LONGCARD(DataRecSize) * LONGCARD(NoTypes) DIV
			MAXCARDINAL) + 1) * MAXCARDINAL ; (* nearest full 8088 segment *)
	IF AmountDiskFree < AmountNeeded THEN
	    (*RES OLD CHE 23
	    Possibly insufficient amount of disk storage on drive %0, amount free: %1 K, maximum
	    needed: %2 K (estimated) just for sorting.  Press "Y" to continue or "N" to stop?
	    = Y N
	    *)
	    MsgString( Drive, 0);
	    MsgCard( VAL(CARDINAL, AmountDiskFree DIV 1024), 0);
	    MsgCard( VAL(CARDINAL, AmountNeeded DIV 1024), 0);
	    ResAskUser( (*RES REM INS *) 23, "YN", ch );
	    IF ch = "N" THEN  RETURN  END ;
	END ;
	
	SortResult := LTurboSort( DataRecSize, GetInput, LessCompare,
			WriteAnagramData, FileData.TempDiskArea ) ;
	IF SortResult <> 0 THEN  SortErrorMsg
	ELSE
	   SortResult := LTurboSort( DataRecSize, ReadAnagramData, LessCompare,
			   DoAnagramOutput, FileData.TempDiskArea ) ;
	   IF SortResult <> 0 THEN  SortErrorMsg  END ;
	END ;
     END DoProperAnagrams ;

   BEGIN
        Copy(MsgStr, 'COLLGEN finished unexpectedly, resulting output files may not be reliable.' ) ;
	MsgTxt[0] := 0C ;
(* m.s.	StartMenu(Percentage); *)
	StartMenu(Status);
	CharField( Status.MsgText );
	CardField( Status.Percent);
	MakeMenu( StatusMenuResID, StatusMenu);
	ClearMenuArea(BaseWPtr, 0, YPosForStatusMenu, StatusMenu);
	ShowFixedText(BaseWPtr, StatusMenu, 0, YPosForStatusMenu);
	Percentage := 0;
(* m.s.	ShowMenu(BaseWPtr, StatusMenu, 0, YPosForStatusMenu, Percentage); *)
	ShowMenu(BaseWPtr, StatusMenu, 0, YPosForStatusMenu, Status);

	StatsWind := BaseWPtr ;

        GetFieldInfo( StatusMenu, 0, PosXStatus, PosYStatus, LenStatus ) ;
        INC( PosYStatus, YPosForStatusMenu ) ;
        GetFieldInfo( StatusMenu, 1, PosXPerCent, PosYPerCent, len ) ;
        INC( PosYPerCent, YPosForStatusMenu ) ;

	WITH AnagramDispTab[0] DO
	     Pos := 5;
	     Type := Left;
	     FilPat := '';
	END;
	
	IF FileData.AnagramType = PartialMatchAnagrams THEN
	      DoPartialAnagramMatch( OutFileID, AbortForFileIO )
	ELSE
	   DoProperAnagrams
	END ;
        Copy( MsgStr, 'ANAGRAMS finished successfully.');
   END Run;

END RUNSource .
