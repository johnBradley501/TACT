IMPLEMENTATION MODULE RUNSource ;

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
(*V2=Debug *)

(*<Debug IMPORT IO ; Debug>*)

IMPORT BitOps, WordBase ;
IMPORT FIO, Lib, Str, TWB ;
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
FROM HyperDataModel IMPORT HyperData, HyperLength, HNoTokens, HTypePntr,TDBTypePntr;
FROM ErrorBase IMPORT
  (* Proc *) ProgramErrorAndHalt;
FROM GlobalDefs IMPORT FileNameType, StrAny ;
FROM WordBase IMPORT IntToSortWord, SortToIntWord ;
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
  (* Type *) FreqOutputType, FreqTypeType,
  (* Vars *) FileData, OutFileID, FreqModePresent, BaseWPtr;
FROM TDBInit IMPORT
  (* Vars *) BeginType, EndTypeRec, EndTypeIdx, NoTypes, TDBFileID ;
FROM LongSort IMPORT
  (* Types *) CompareProc, SortIOProc,
  (* Procs *) LTurboSort, LSortRelease, LSortReturn, LSortEOS, LSortReset, LSortGetPos ;

CONST
   YPosForStatusMenu = 21;

(*RES OLD MNU 32
   Status:  %0________________________________________________________
   Percentage Completed: %1_ % [estimated]
*)

   StatusMenuResID = (*RES REM INS*) 32 ;

   FileHeaderResource = 113 ;	(* >> MSG defined in MAKBAS: SetupFil.MOD << *)
   MAXCARDINAL = MAX(CARDINAL) ;
   MaxWordLen = 19 ;

TYPE
   HRecPntr = RECORD
		Rec: CARDINAL;
		Idx: CARDINAL;
	      END;
   HyperDataPntr = POINTER TO HyperData ;
   WordStrType  = ARRAY[0..MaxWordLen] OF CHAR;
   ReverseAlphaTypePntr = POINTER TO ReverseAlphaType ;
   ReverseAlphaType = RECORD
		HeadWord : WordStrType ;
		HRecPtr	 : HRecPntr ;
   	      END ;
   FrequencyTypePntr = POINTER TO FrequencyType ;
   FrequencyType = RECORD
		Freq	: CARDINAL ;
		HRecPtr	: HRecPntr ;
   	      END ;

VAR
   DataRecSize	: CARDINAL ;
   RecNo	: CARDINAL ;
   RecIdx	: CARDINAL ;
   HRecord	: HyperDataPntr ;
   TDBTypeRec	: TDBTypePntr;
   TypeRec	: HTypePntr ;

   Percentage	: CARDINAL ;
   LastPercentage : CARDINAL ;
   Count	: LONGCARD ;
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
   RevFreqDispTab,
   FreqDispTab  : ARRAY[0..0] OF TabInfo;
   FreqFile	: FIO.File ;
   FreqFileName : ARRAY[0..64] OF CHAR ;

   ch:       CHAR;
   FunctKey: BOOLEAN;
   DoRead:   BOOLEAN;

CONST
   MaxCARDINAL = MAX(INTEGER) DIV TSIZE(HRecPntr) - 100 ;  (* any large number will do *)

TYPE
   TypeTableType = ARRAY[0..MaxCARDINAL ] OF HyperDataPntr;
   WordAny	 = ARRAY[0..64] OF CHAR ;
VAR
   TypeTable	: POINTER TO TypeTableType ;
   NoInTable	: CARDINAL ;
   CurType	: HRecPntr ;
   CurRecNo	: CARDINAL ;
   CurHRecord	: HyperDataPntr ;
   DummyHRecord	: HyperDataPntr ;
   PivotRecNo	: CARDINAL ;
   PivotHRecord	: HyperDataPntr ;
   ThisType	: HRecPntr ;
   ThisWord	: WordAny ;
   HeadWord	: WordAny ;
   SortWord	: StrAny ;
   WordPtr	: POINTER TO BitOps.PackedStrType ;

   pos		: CARDINAL ;
   ContextPos	: CARDINAL ;
   ContextStr	: StrAny ;
   TempStr	: StrAny ;
   IOResult	: CARDINAL;
   ErrorMsg	: StrAny ;
   status	: BOOLEAN ;

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

PROCEDURE GetNextTypeInfo( VAR Data : TDBTypePntr) : BOOLEAN ;
   BEGIN
	IF (RecNo > EndTypeRec) OR ( (RecNo = EndTypeRec) AND (RecIdx >= (EndTypeIdx-1))) THEN
	   RETURN FALSE ;
	END ;
	INC( RecIdx ) ;
	IF (RecIdx > HRecord^.NoDataPtrsUsed) AND (RecNo < EndTypeRec) THEN
	   IF HRecord^.NextHRec = 0 THEN  RETURN FALSE  END ;
	   RecNo := BeginType + HRecord^.NextHRec ;
	   RecIdx := 1 ;
	   FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, RecNo)  ) ;
	   BytesRead := FIO.RdBin( TDBFileID, HRecord^, HyperLength ) ;
	   IF BytesRead <> HyperLength THEN
	      ProgramErrorAndHalt( 'RunSource(GetNextTypeInfo): short record read from .TDB file.' )
	   END ;
	END ;
	Data := ADR( HRecord^.TextData[ HRecord^.DataPntr[ RecIdx ] ] ) ;
	RETURN TRUE ;
   END GetNextTypeInfo ;

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

(* CompareHRecs compares two HRecPntr's:  HRec1 < HRec2 returns -1
					  HRec1 = HRec2    "     0
					  HRec1 > HRec2    "    +1  *)
PROCEDURE CompareHRecs( HRec1, HRec2 : HRecPntr ) : INTEGER ;
   BEGIN
	IF HRec1.Rec < HRec2.Rec THEN
	   RETURN -1
	ELSIF HRec1.Rec > HRec2.Rec THEN
	   RETURN 1
	ELSIF HRec1.Idx < HRec2.Idx THEN
	   RETURN -1
	ELSIF HRec1.Idx > HRec2.Idx THEN
	   RETURN 1
	ELSE
	   RETURN 0
	END ;
   END CompareHRecs ;

PROCEDURE DoAlphaOutput( VAR file: XFileType; CheckAbort: AbortProc);
   VAR
	I	: CARDINAL ;
	pos	: CARDINAL ;
	TempStr	: StrAny ;
	KeyStr	: StrAny ;
	ContextStr : StrAny ;
	IOResult : CARDINAL;
	ErrorMsg : StrAny ;
   BEGIN
	ALLOCATE( HRecord, HyperLength ) ;
	RecNo := BeginType ;
	RecIdx := 1 ;	(* will point to first item by inc later *)
	FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, BeginType )  ) ;
	BytesRead := FIO.RdBin( TDBFileID, HRecord^, HyperLength ) ;
	IF BytesRead <> HyperLength THEN
	   ProgramErrorAndHalt( 'RunSource(GetNextTypeInfo): short record read from .TDB file.' )
	END ;

	Count := 0 ;
	LastPercentage := 0 ;

	(*RES OLD MSG 521    *** m.s. - shared with tactstat  ***
	Output phase.
	*)
	PutRunStatus( (*RES REM INS*) 521 );

	WHILE GetNextTypeInfo( TDBTypeRec ) AND NOT CheckAbort() DO
	   INC(Count);
	   Percentage := VAL(CARDINAL,Count * 100 DIV LONGCARD(NoTypes)) ;
	   IF Percentage >= LastPercentage THEN
		PutPercentage( Percentage ) ;
		INC(LastPercentage, 4) ;
	   END ;

	   WordPtr := ADR( TDBTypeRec^.PackedWord ) ;	(* get past the NoOccur value *)
	   BitOps.UnPack( WordPtr^, SortWord, WordBase.SortNoBitsPerChar ) ;
	   SortToIntWord( SortWord, KeyStr ) ;
	   pos := 0 ;

	   IF FreqModePresent OR (FileData.GenFreqOut = OutToPrinter) THEN	(* we a file translation table *)
		TempStr[0] := IntEnhOn ;
		FOR I := 1 TO Length( KeyStr ) DO
		   TempStr[I] := KeyStr[I-1]
		END ;
		TempStr[I+1] := IntEnhOff;
		TempStr[I+2] := 0C ;
	   ELSE
		Copy( TempStr, KeyStr )
	   END ;

	   SWriteCard( ContextStr, pos, TDBTypeRec^.NoOccur, 5 ) ;
	   SWriteString( ContextStr, pos, '  ', 0 ) ;
	   SWriteString( ContextStr, pos, TempStr, 0 );

	   CASE FileData.GenFreqOut OF
	      OutToDisk:
		IF NOT XWriteLine(OutFileID, '?', ContextStr, IOResult) THEN
		   IOErrorMessage(IOResult, ErrorMsg) ;
		   MsgString( FileData.OutFileName, 0 ) ;
		   MsgString( ErrorMsg, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		END ; |
	      OutToPrinter:
		status := WriteWithTabs(file, ContextStr, FreqDispTab);
	   END ;
	END ;

	DEALLOCATE( HRecord, HyperLength ) ;

	FIO.Close( TDBFileID ) ;
	IF FileData.GenFreqOut = OutToDisk THEN  XClose( OutFileID )  END ;
   END DoAlphaOutput ;

PROCEDURE DoAlphabetical ;
   BEGIN
	IF FileData.GenFreqOut = OutToPrinter THEN	
	   PrintMaster( ToPrinter, DoAlphaOutput, DoRead, ch, FunctKey );
	ELSE
	   DoAlphaOutput( OutFileID, AbortForFileIO )
	END ;
   END DoAlphabetical ;

PROCEDURE SetTypeTable ;
   VAR i : CARDINAL ;
   BEGIN
	(* compute & allocate the amount of HRecs that we can keep in memory *)
(* m.s.	NoInTable := HeapAvail( MainHeap ) DIV 64 - 5 (* in 1Ks *) ;
	IF NoInTable > (EndTypeRec - BeginType ) THEN
		NoInTable := EndTypeRec - BeginType ; (* use max # of HRecs *)
	ELSE
		ALLOCATE( CurHRecord, HyperLength ) ;
		CurRecNo := MAXCARDINAL ;
		ALLOCATE( PivotHRecord, HyperLength ) ;
		PivotRecNo := MAXCARDINAL ;
	END ;
*)
	NoInTable := EndTypeRec - BeginType ; (* use max # of HRecs *)
	ALLOCATE( TypeTable, (NoInTable+1) * TSIZE( HyperDataPntr ) );
	FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, BeginType )  ) ;
	FOR i := 0 TO NoInTable DO
		ALLOCATE( TypeTable^[i], HyperLength ) ;
		BytesRead := FIO.RdBin( TDBFileID, TypeTable^[i]^, HyperLength ) ;
		IF BytesRead <> HyperLength THEN
		   ProgramErrorAndHalt( 'RunSource(PartialAnagrams): short record read from .TDB file.' )
		END ;
	END ;
    END SetTypeTable ;
   	
PROCEDURE FindHRecord( Rec : CARDINAL; VAR HRecord : HyperDataPntr ) ;
   VAR Temp : HyperDataPntr ;
   BEGIN
     IF Rec > (EndTypeRec -BeginType) THEN  Lib.FatalError( "invalid rec no." ) END ;

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
   	
(*$F*)
PROCEDURE GetReverseInput ;
   VAR
	DataRec : ReverseAlphaType ;
	IOResult : CARDINAL;
	RetDiaPos, I	: CARDINAL ;
	J	: INTEGER ;
   BEGIN
	ALLOCATE( HRecord, HyperLength ) ;
	RecNo := BeginType ;
	RecIdx := 1 ;	(* will point to first item by INC later *)
	FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, BeginType )  ) ;
	BytesRead := FIO.RdBin( TDBFileID, HRecord^, HyperLength ) ;
	IF BytesRead <> HyperLength THEN
	   ProgramErrorAndHalt( 'RunSource(GetNextTypeInfo): short record read from .TDB file.' )
	END ;

	Count := 0 ;
	LastPercentage := 0 ;

	(*RES OLD MSG 503
	Reading the TDB file.
	*)
	PutRunStatus( (*RES REM INS*) 503 );

	WHILE GetNextTypeInfo( TDBTypeRec ) DO
	   DataRec.HRecPtr.Rec := RecNo - BeginType  ;
	   DataRec.HRecPtr.Idx := RecIdx ;
	   INC(Count);
	   Percentage := VAL(CARDINAL,Count * 100 DIV LONGCARD(NoTypes)) ;
	   IF Percentage >= LastPercentage THEN
		PutPercentage( Percentage ) ;
		INC(LastPercentage, 4) ;
	   END ;

	   WordPtr := ADR( TDBTypeRec^.PackedWord ) ;	(* get past the NoOccur value *)
	   BitOps.UnPack( WordPtr^, SortWord, WordBase.SortNoBitsPerChar ) ;

	   RetDiaPos := Str.Pos( SortWord, 02C ) ;
	   IF RetDiaPos = MAX(CARDINAL) THEN  RetDiaPos := Str.Length(SortWord)  END;
	   DEC( RetDiaPos ) ;
	   J := RetDiaPos ;
	   IF RetDiaPos > MaxWordLen THEN  RetDiaPos := MaxWordLen  END ;
	   FOR I := 0 TO RetDiaPos DO
		DataRec.HeadWord[I] := SortWord[J] ;
		DEC( J ) ;
	   END ;
	   IF I < MaxWordLen THEN  DataRec.HeadWord[I+1] := 0C  END ;
	   LSortRelease( DataRec ) ;
	END ;
	NoSortRecs := LONGCARD( NoTypes ) ;

	DEALLOCATE( HRecord, HyperLength ) ;

	(* set status value for next phase -- calculated above !! *)
	
	(* Note: QuickSort is order O( N log2(N) ) comparisons, it appears *)
	(*	 to be N log2(N) + 4 N					   *)
	NoCompares := NoSortRecs * VAL(LONGCARD, Log2(NoSortRecs) + 4) ;
	Count := 0 ;
	LastPercentage := 0 ;
	(*RES OLD MSG 308
	Sort phase.
	*)
	PutRunStatus( (*RES REM INS*) 308 );
   END GetReverseInput ;

PROCEDURE CompLessReverse(X, Y : ReverseAlphaTypePntr) : BOOLEAN ;
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
	rc := Str.Compare( X^.HeadWord, Y^.HeadWord ) ;
	IF rc < 0 THEN  RetVal := TRUE
	ELSIF rc = 0 THEN
	   rc := CompareHRecs( X^.HRecPtr, Y^.HRecPtr ) ;
	   IF rc < 0 THEN  RetVal := TRUE
	   ELSE RetVal := FALSE
	   END ;
	ELSE
	   RetVal := FALSE
	END ;
	RETURN RetVal ;
   END CompLessReverse ;

PROCEDURE DoReverseOutput( VAR file: XFileType; CheckAbort: AbortProc);
   VAR
	DataRec : ReverseAlphaType ;
	IOResult : CARDINAL;
	len	: CARDINAL ;
   BEGIN
	(* set status value for next phase *)
	Count := 0 ;
	LastPercentage := 0 ;

	PutRunStatus( (*RES REM INS*) 521 );
	
	SetTypeTable ;

	WHILE NOT LSortEOS() AND NOT CheckAbort() DO
	   LSortReturn( DataRec ) ;
	   INC(Count);
	   Percentage := VAL(CARDINAL,Count * 100 DIV NoSortRecs) ;
	   IF Percentage >= LastPercentage THEN
		PutPercentage( Percentage ) ;
		INC(LastPercentage) ;
	   END ;

	   FindHRecord( DataRec.HRecPtr.Rec, HRecord ) ;
	   TDBTypeRec := ADR( HRecord^.TextData[ HRecord^.DataPntr[ DataRec.HRecPtr.Idx ] ] ) ;

	   WordPtr := ADR( TDBTypeRec^.PackedWord ) ;	(* get past the NoOccur value *)
	   BitOps.UnPack( WordPtr^, SortWord, WordBase.SortNoBitsPerChar ) ;
	   SortToIntWord( SortWord, TempStr ) ;
	   len := Str.Length( TempStr ) ;
	   pos := 0 ;
	   SWriteString( ContextStr, pos, IntTab, 0 ) ;
	   SWriteString( ContextStr, pos, TempStr, 0 );
	   SWriteCard( ContextStr, pos, TDBTypeRec^.NoOccur, 5 ) ;

	   CASE FileData.GenFreqOut OF
	      OutToDisk:
		IF NOT WriteWithTabs(OutFileID, ContextStr, RevFreqDispTab) THEN
		   IOErrorMessage(IOResult, ErrorMsg) ;
		   MsgString( FileData.OutFileName, 0 ) ;
		   MsgString( ErrorMsg, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		END ; |
	      OutToPrinter:
		status := WriteWithTabs(file, ContextStr, FreqDispTab);
	   END ;
	END ;

	IF FileData.GenFreqOut = OutToDisk THEN  XClose( OutFileID )  END ;
   END DoReverseOutput ;

PROCEDURE WriteReverseOutput ;
   BEGIN
	IF FileData.GenFreqOut = OutToPrinter THEN	
	   PrintMaster( ToPrinter, DoReverseOutput, DoRead, ch, FunctKey );
	ELSE
	   DoReverseOutput( OutFileID, AbortForFileIO )
	END ;
   END WriteReverseOutput ;


PROCEDURE GetFrequencyInput ;
   VAR
	DataRec : FrequencyType ;
	IOResult : CARDINAL;
   BEGIN
	ALLOCATE( HRecord, HyperLength ) ;
	RecNo := BeginType ;
	RecIdx := 1 ;	(* will point to first item by INC later *)
	FIO.Seek( TDBFileID, HyperLength * VAL(LONGCARD, BeginType )  ) ;
	BytesRead := FIO.RdBin( TDBFileID, HRecord^, HyperLength ) ;
	IF BytesRead <> HyperLength THEN
	   ProgramErrorAndHalt( 'RunSource(GetNextTypeInfo): short record read from .TDB file.' )
	END ;

	Count := 0 ;
	LastPercentage := 0 ;

	(*RES OLD MSG 503
	Reading the TDB file.
	*)
	PutRunStatus( (*RES REM INS*) 503 );

	WHILE GetNextTypeInfo( TDBTypeRec ) DO
	   INC(Count);
	   Percentage := VAL(CARDINAL,Count * 100 DIV LONGCARD(NoTypes)) ;
	   IF Percentage >= LastPercentage THEN
		PutPercentage( Percentage ) ;
		INC(LastPercentage, 4) ;
	   END ;

	   DataRec.HRecPtr.Rec := RecNo - BeginType ;
	   DataRec.HRecPtr.Idx := RecIdx ;
	   DataRec.Freq := TDBTypeRec^.NoOccur ;
	   LSortRelease( DataRec ) ;
	END ;
	NoSortRecs := LONGCARD( NoTypes ) ;

	DEALLOCATE( HRecord, HyperLength ) ;

	(* set status value for next phase -- calculated above !! *)
	
	(* Note: QuickSort is order O( N log2(N) ) comparisons, it appears *)
	(*	 to be N log2(N) + 4 N					   *)
	NoCompares := NoSortRecs * VAL(LONGCARD, Log2(NoSortRecs) + 4) ;
	Count := 0 ;
	LastPercentage := 0 ;
	(*RES OLD MSG 308
	Sort phase.
	*)
	PutRunStatus( (*RES REM INS*) 308 );
   END GetFrequencyInput ;

PROCEDURE CompLessFrequency(X, Y : FrequencyTypePntr) : BOOLEAN ;
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
	(* use ">" to obtain a descending sort order for freqs *)
	IF X^.Freq > Y^.Freq THEN  RetVal := TRUE
	ELSIF X^.Freq = Y^.Freq THEN
	   rc := CompareHRecs( X^.HRecPtr, Y^.HRecPtr ) ;
	   IF rc < 0 THEN  RetVal := TRUE
	   ELSE RetVal := FALSE
	   END ;
	ELSE
	   RetVal := FALSE
	END ;
	RETURN RetVal ;
   END CompLessFrequency ;

PROCEDURE DoFreqOutput( VAR file: XFileType; CheckAbort: AbortProc);
   VAR
	DataRec  : FrequencyType ;
	IOResult : CARDINAL;
   BEGIN
	(* set status value for next phase *)
	Count := 0 ;
	LastPercentage := 0 ;

	PutRunStatus( (*RES REM INS*) 521 );
	
	SetTypeTable ;

	WHILE NOT LSortEOS() AND NOT CheckAbort() DO
	   LSortReturn( DataRec ) ;
	   INC(Count);
	   Percentage := VAL(CARDINAL,Count * 100 DIV NoSortRecs) ;
	   IF Percentage >= LastPercentage THEN
		PutPercentage( Percentage ) ;
		INC(LastPercentage) ;
	   END ;

	   FindHRecord( DataRec.HRecPtr.Rec, HRecord ) ;
	   TDBTypeRec := ADR( HRecord^.TextData[ HRecord^.DataPntr[ DataRec.HRecPtr.Idx ] ] ) ;
	   WordPtr := ADR( TDBTypeRec^.PackedWord ) ;	(* get past the NoOccur value *)
	   BitOps.UnPack( WordPtr^, SortWord, WordBase.SortNoBitsPerChar ) ;
	   SortToIntWord( SortWord, TempStr ) ;

	   pos := 0 ;
	   SWriteCard( ContextStr, pos, TDBTypeRec^.NoOccur, 5 ) ;
	   SWriteString( ContextStr, pos, '  ', 0 ) ;
	   SWriteString( ContextStr, pos, TempStr, 0 );

	   CASE FileData.GenFreqOut OF
	      OutToDisk:
		IF NOT XWriteLine(OutFileID, '?', ContextStr, IOResult) THEN
		   IOErrorMessage(IOResult, ErrorMsg) ;
		   MsgString( FileData.OutFileName, 0 ) ;
		   MsgString( ErrorMsg, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		END ; |
	      OutToPrinter:
		status := WriteWithTabs(file, ContextStr, FreqDispTab);
	   END ;
	END ;

	IF FileData.GenFreqOut = OutToDisk THEN  XClose( OutFileID )  END ;
   END DoFreqOutput ;

PROCEDURE WriteFrequencyOutput ;
   BEGIN
	IF FileData.GenFreqOut = OutToPrinter THEN	
	   PrintMaster( ToPrinter, DoFreqOutput, DoRead, ch, FunctKey );
	ELSE
	   DoFreqOutput( OutFileID, AbortForFileIO )
	END ;
   END WriteFrequencyOutput ;

(*$N*)

PROCEDURE DoSort( DataRecSize : CARDINAL;
		  GetInput    : SortIOProc;
		  CompareLess : CompareProc;
		  WriteOutput : SortIOProc ) ;
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

     BEGIN	(* DoSort *)
	FIO.IOcheck := FALSE ;
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
	
	SortResult := LTurboSort( DataRecSize, GetInput, CompareLess,
			WriteOutput, FileData.TempDiskArea ) ;
	IF SortResult <> 0 THEN  SortErrorMsg  END ;
	FIO.Close( TDBFileID ) ;
     END DoSort ;

PROCEDURE Run(VAR MsgStr : ARRAY OF CHAR );
   TYPE
      StatusType   = RECORD  (* m.s. *)
                Percent            : CARDINAL ;	
                MsgText            : ARRAY [0..80] OF CHAR ;
              END ;
   VAR
	len		: CARDINAL;
	StatusMenu	: MenuID;
        Status          : StatusType ; (* m.s. *)
   BEGIN
	MsgTxt[0] := 0C ;
(* m.s.	StartMenu(Percentage);
	CharField( MsgTxt );
	CardField(Percentage);
*)
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

	WITH FreqDispTab[0] DO
	     Pos := 5;
	     Type := Left;
	     FilPat := '';
	END;

	WITH RevFreqDispTab[0] DO
	     Pos := 25;
	     Type := Right;
	     FilPat := ' ';
	END;

	FIO.IOcheck := FALSE ;
	CASE FileData.FreqType OF
	   Alphabetical:  DoAlphabetical |
	   ReverseAlpha:
		DoSort( SIZE(ReverseAlphaType), GetReverseInput, CompLessReverse,
			WriteReverseOutput ) ; |
	   Frequency:
		DoSort( SIZE(FrequencyType), GetFrequencyInput, CompLessFrequency,
			WriteFrequencyOutput ) ;
	END ;	
        Copy( MsgStr, 'TACTFREQ finished successfully.');
	
   END Run;

END RUNSource .
