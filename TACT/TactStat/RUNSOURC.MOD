IMPLEMENTATION MODULE RUNSource ;

(* copyright (c) 1989,96 Ian Lancashire, Lidio Presutti, University of Toronto *)

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

IMPORT TFormIO ;

IMPORT BitOps, WordBase ;
IMPORT FIO, Lib, Str, TWB, MATHLIB ;
IMPORT Utils ;
FROM ResMessages IMPORT
   (* proc *)  MsgString, PutResError, ResAskUser, GetResMessage;
FROM ResMenus IMPORT
  (* type *)  MenuID,
  (* proc *)  StartMenu, CardField, CharField, MakeMenu, DestroyMenu, GetFieldInfo,
		ClearMenuArea, ShowFixedText, ShowMenu;
FROM SYSTEM   IMPORT SIZE ;
FROM StringIO IMPORT SWriteString ;
FROM Storage  IMPORT ALLOCATE, DEALLOCATE ;
FROM HyperDataModel IMPORT HyperData, HyperLength, HNoTokens, HTypePntr,TDBTypePntr;
FROM ErrorBase IMPORT
  (* Proc *) ProgramErrorAndHalt;
FROM GlobalDefs IMPORT StrAny ;
FROM WordBase IMPORT ExtraCodeSep, SortToIntWord, SortToFullWord ;
FROM KeyTranslation IMPORT
  (* Const *) IntEnhOn, IntEnhOff, IntTab,
  (* Type  *) TabInfo, TabType,
  (* Procs *) WriteScreenField ;
FROM Windows  IMPORT
  (* Const *) RegularAttr ;
FROM Translations IMPORT
 (* var  *) Int2Alp, Alp2Int, LenD,
 (* type *) XlateStrAny, CurrentModeType,
 (* proc *) XlateLine;
FROM Translations IMPORT
 (* type *) XFileType,
 (* proc *) XWriteLine, XClose ;
FROM Utils IMPORT BDelete ;
FROM UtilsTwo IMPORT IOErrorMessage;
FROM PrintModule IMPORT PrintMaster, PrintProcType, PrintActionType,
		AbortProc, AbortForFileIO, WriteWithTabs;

FROM StartUp IMPORT
  (* Type *) StatOutputType,
  (* Vars *) FileData, OutFileID, StatModePresent, BaseWPtr, BaseWPtr;
IMPORT TDBInit ;
FROM TDBInit IMPORT
  (* Vars *) BeginType, EndTypeRec, EndTypeIdx, TDBFileID, FirstAlphChar, LastAlphChar ;

CONST
   YPosForStatusMenu = 20;

(*RES OLD MNU 32
                  Status: %0__________________________________
    Percentage Completed: %1_ % [estimated]

*)

   StatusMenuResID = (*RES REM INS*) 32 ;

   FileHeaderResource = 113 ;	(* >> MSG defined in MAKBAS: SetupFil.MOD << *)

TYPE
   HyperDataPntr = POINTER TO HyperData ;
   WordAny	 = ARRAY[0..64] OF CHAR ;

VAR
   RecNo	: CARDINAL ;
   RecIdx	: CARDINAL ;
   HRecord	: HyperDataPntr ;
   TDBTypeRec	: TDBTypePntr;
   TypeRec	: HTypePntr ;
   SortWord	: StrAny ;
   WordPtr	: POINTER TO BitOps.PackedStrType ;

   Percentage	: CARDINAL ;
   LastPercentage : CARDINAL ;
   Count	: LONGCARD ;
   BytesRead	: CARDINAL ;

   StatsWind	: TWB.WinType ;
   LenStatus	: CARDINAL ;
   PosXStatus	: CARDINAL ;
   PosYStatus	: CARDINAL ;
   PosXPerCent	: CARDINAL ;
   PosYPerCent	: CARDINAL ;
   MsgTxt	: StrAny;
   StatDispTab  : ARRAY[0..0] OF TabInfo;

   ch:       CHAR;
   FunctKey: BOOLEAN;
   DoRead:   BOOLEAN;

   MostFreqWord : RECORD
		     FreqCount	: CARDINAL ;
		     Word	: WordAny ;
		  END ;

PROCEDURE PutRunStatus( ResID : CARDINAL );
   BEGIN
	GetResMessage(ResID,MsgTxt);
	WriteScreenField( StatsWind, LenStatus, PosXStatus,
			PosYStatus, MsgTxt, RegularAttr, TRUE ) ;
   END PutRunStatus;

PROCEDURE PutPercentage( N : CARDINAL ) ;
   VAR
	LongStr	: ARRAY[0..4] OF CHAR ;
   BEGIN
	TFormIO.WrF1( "%3u", N, LongStr ) ;
	TWB.Use(StatsWind);
	TWB.GotoXY( PosXPerCent, PosYPerCent );
	TWB.WrStr(LongStr);
   END PutPercentage;

PROCEDURE GetNextTypeInfo( VAR TDBTypeRec : TDBTypePntr) : BOOLEAN ;
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
	TDBTypeRec := ADR( HRecord^.TextData[ HRecord^.DataPntr[ RecIdx ] ] ) ;

	WordPtr := ADR( TDBTypeRec^.PackedWord ) ;	(* get past the NoOccur value *)
	BitOps.UnPack( WordPtr^, SortWord, WordBase.SortNoBitsPerChar ) ;
	RETURN TRUE ;
   END GetNextTypeInfo ;

(*-----------------------------------------------------------------------------
   Formulas for Type/Token ratios:

   f(r) - observed frequency of r occurrences, r = 1, 2, 3, ... R, where
          R is the most frequent word in the text.

        R
       ---
   n = >   f(r)  - number of types (ie. distinct words)
       ---
       r=1

        R
       ---
   N = >   r * f(r)  - number of tokens (ie. text length)
       ---
       r=1

   hapax legomena = f(1)
   dislegomena    = f(2)
   _
   r = N / n     - average number of occurances

             R
    2       ---       _  2
   S =  1/n >   ( r - r )  * f(r)  - variance
            ---
            r=1

               2
   S = SqRt( S  )       - standard deviation

                 R
                ---       _  3             3
   Skew = 1/n { >   ( r - r )  * f(r) } / S   - coefficient of skewness
                ---
                r=1

                 R
                ---       _  4             4
   Kurt = 1/n { >   ( r - r )  * f(r) } / S  - 3   - coefficient of kurtosis
                ---
                r=1
                                    _
   Herdan's characteristic =  S / ( r * SqRt( n ) )

                 R
            4   ---   2               2
   Yule = 10  { >    r  * f(r) } / ( N  - 1 / N )
                ---
                r=1
----------------------------------------------------------------------------*)

PROCEDURE DoStatOutput( VAR file: XFileType; CheckAbort: AbortProc);
   TYPE
	GraphEnumType = (ChFirst, ChLast, ChAll);
	ChTableType   = ARRAY [0C..377C] OF LONGCARD;
	TypeTokenRec  = RECORD
			  Freq	: CARDINAL;
			  Occur	: CARDINAL;
		       END;
   CONST
	MaxR = 500;
	MaxWordLen = 50 ; (* m.s. - was 30, IL caused overflow *)
   VAR
	pos	: CARDINAL ;
	Ch      : CHAR ;
	MsgStr	: StrAny ;
	TempStr	: StrAny ;
	KeyStr	: StrAny ;
	IOResult : CARDINAL;
	ErrorMsg : StrAny ;
	SortLen	 : CARDINAL ;

      Temp1, Temp2: LONGREAL;
      MaxCh: CHAR;
      MaxCount	: LONGCARD ;
      ScaleFactor,
      NoOfAsterisks,
      I, J	: CARDINAL;

	WordLenTable	: ARRAY[1..MaxWordLen] OF LONGCARD;
	FirstChTable	: ChTableType;
	LastChTable	: ChTableType;
	AllChTable	: ChTableType;
	FreqTable	: ARRAY[0..MaxR] OF TypeTokenRec;
	r		: CARDINAL;
	MaxFreqIndex	: CARDINAL;
	NoTypes		: LONGCARD; (* n *)
	NoTokens	: LONGCARD; (* N *)

	TotTypes	: LONGCARD; (* cummilative n *)
	TotTokens	: LONGCARD; (* cummilative N *)

	LRNoTypes,	(* temp vars for correct (LONGREAL) types *)
	LRNoTokens,
	LRHapax,
	LROccur,
	LRFreq		: LONGREAL;

	AveNoOccur	: LONGREAL; (* N / n *)
	VarSq,
	StandDev,
	Skew,
	Kurt,
	Herdan,
	Yule		: LONGREAL;

	TempReal, TotTypeRatio, TotTokenRatio, FreqOccurRatio : LONGREAL ;
	FreqOccur : LONGCARD ;
	InternalCh,
	SortAlphabet  : StrAny ;
	
   PROCEDURE Write( VAR MsgStr : ARRAY OF CHAR ) ;
	VAR status	: BOOLEAN ;
	BEGIN
	   CASE FileData.GenStatOut OF
	     OutToDisk:
		IF NOT XWriteLine(OutFileID, '?', MsgStr, IOResult) THEN
		   IOErrorMessage(IOResult, ErrorMsg) ;
		   MsgString( FileData.OutFileName, 0 ) ;
		   MsgString( ErrorMsg, 0 ) ;
		   PutResError( FileHeaderResource ) ;
		END ;	|
	     OutToPrinter:
		status := WriteWithTabs(file, MsgStr, StatDispTab);
	   END ;
	   pos := 0 ;  (* reset to MsgStr position for next line *)
	   MsgStr[0] := 0C ;
	END Write ;


    PROCEDURE DoLetterFreq( ChTable : ChTableType; GraphType : GraphEnumType);
      VAR
        I, FLen: CARDINAL;
        Header2: StrAny ;
        Letters: ARRAY [0C..377C] OF CHAR;
        TempReal2, TempReal3 : LONGREAL ;

      (* sorts variable ChTable *)

      PROCEDURE Quicksort(start, finish: CHAR);
        VAR
          pivot: LONGCARD;
          left, right: CHAR;
          Temp: LONGCARD;
      BEGIN
        (* set pivot point *)
        left := start;
        right := finish;
        pivot := ChTable[CHR( (ORD(start)+ORD(finish)) DIV 2 )]; (* partition *)
        REPEAT
          WHILE ChTable[left] > pivot DO
            INC(left)
          END;
          WHILE pivot > ChTable[right] DO
            DEC(right)
          END;
          IF left <= right THEN
            (* Swap( ChTable[left], ChTable[right] ) *)
            Temp := ChTable[left];
            ChTable[left] := ChTable[right];
            ChTable[right] := Temp; (* also for letters pointers *)
            Ch := Letters[left];
            Letters[left] := Letters[right];
            Letters[right] := Ch;
            INC(left);
            DEC(right);
          END;
        UNTIL (right <= left) ; (* sort right and left halves *)
        IF start < right THEN
          Quicksort(start, right)
        END;
        IF left < finish THEN
          Quicksort(left, finish)
        END;
      END Quicksort; (* QuickSort *)


	BEGIN
	   FOR Ch := 0C TO 377C DO
	      Letters[Ch] := Ch
	   END;
	   MaxCount := 0;
	   NoTypes := 0;
	   NoTokens := 0;
	   FOR I := 0 TO Str.Length(SortAlphabet)-1 DO
	      Ch := SortAlphabet[I];
	      IF ChTable[Ch] > MaxCount THEN
		 MaxCh := Ch;
		 MaxCount := ChTable[Ch];
	      END;
	      INC(NoTypes);
	      INC(NoTokens, LONGCARD(ChTable[Ch]));
	   END;
	   LRNoTokens := VAL(LONGREAL, NoTokens ) ;
	   LRNoTypes  := VAL(LONGREAL, NoTypes ) ;
	   AveNoOccur := LRNoTokens / LRNoTypes;
	   VarSq := 0.0 ;
	   Write( MsgStr ) ;	
	   CASE GraphType OF
	      ChFirst, ChLast:
		IF NoTokens DIV LONGCARD(MaxCount) >= 2 THEN  (* ie. largest item is less than 50 % *)
		   ScaleFactor := 2
		ELSE
		   ScaleFactor := 1
		END;
		SWriteString( MsgStr, pos, 'Letter Freq.    %                        Percentage', 0);
		Write( MsgStr ) ;	
		SWriteString( MsgStr, pos, ' ', 19);
		IF ScaleFactor = 1 THEN
		   SWriteString( MsgStr, pos, '    10   20   30   40   50   60   70   80   90  100', 0);
		ELSE
		   SWriteString( MsgStr, pos, '         10        20        30        40        50', 0);
		END;
		Write( MsgStr ) ;	
		SWriteString( MsgStr, pos, ' ', 19);
		SWriteString( MsgStr, pos, '+----+----+----+----+----+----+----+----+----+----+', 0);
		Write( MsgStr ) ;	
		FOR I := 0 TO Str.Length(SortAlphabet)-1 DO
		   Ch := SortAlphabet[I];
 	         IF Str.Compare(Ch , CHR(ExtraCodeSep)) <> 0 THEN (* m.s. *)
		   SortToIntWord(Ch, InternalCh) ;
		   TempReal := VAL(LONGREAL, ChTable[Ch]) / LRNoTokens * 100.0 ;
		   NoOfAsterisks := VAL(CARDINAL,
			VAL(LONGREAL,ChTable[Ch]) * VAL(LONGREAL,ScaleFactor) * 50.0 / LRNoTokens  + 0.5) ;
		   Utils.ConstStr( '*', NoOfAsterisks, TempStr ) ;
		   TFormIO.WrF4( "%4c %6u%7.2r |%s", InternalCh, ChTable[Ch], TempReal, TempStr, MsgStr) ;
		   Write( MsgStr ) ;	
		   Temp1 := VAL(LONGREAL, ChTable[Ch]) - AveNoOccur;
		   Temp2 := Temp1 * Temp1 ;
		   VarSq := VarSq + Temp2;
                 END ;
		END;
        | ChAll:
		SWriteString( MsgStr, pos, 'Letter  Freq.  % in all  Initial  % in all  Final  % in all', 0);
		Write( MsgStr ) ;	
		FOR I := 0 TO Str.Length(SortAlphabet)-1 DO
		 Ch := SortAlphabet[I];
 	         IF Str.Compare(Ch , CHR(ExtraCodeSep)) <> 0 THEN (* m.s. *)
		   SortToIntWord(Ch, InternalCh) ;
		   TempReal := VAL(LONGREAL, ChTable[Ch]) / LRNoTokens * 100.0 ;
		   IF ChTable[Ch] > 0 THEN
			TempReal2:= VAL(LONGREAL, FirstChTable[Ch]) /
				VAL(LONGREAL, ChTable[Ch]) * 100.0 ;
			TempReal3:= VAL(LONGREAL, LastChTable[Ch]) /
				VAL(LONGREAL, ChTable[Ch]) * 100.0 ;
		   ELSE
			TempReal2:= VAL(LONGREAL, FirstChTable[Ch]) ;
			TempReal3:= VAL(LONGREAL, LastChTable[Ch]) ;
		   END ;
		   TFormIO.WrF7( "%6c %6u%9.2r  %6u%10.2r  %6u%10.2r", InternalCh, ChTable[Ch], TempReal,
			FirstChTable[Ch], TempReal2, LastChTable[Ch], TempReal3, MsgStr) ;
		   Write( MsgStr ) ;	
		   Temp1 := VAL(LONGREAL, ChTable[Ch]) - AveNoOccur;
		   Temp2 := Temp1 * Temp1 ;
		   VarSq := VarSq + Temp2;
		END;
	      END ; (* m.s. *)
	   END;

	   Quicksort(3C, 377C);

	   Write( MsgStr ) ;	
	   SWriteString( MsgStr, pos, 'Sorted by frequency', 0);
	   Write( MsgStr ) ;	
	   Write( MsgStr ) ;	
	   SWriteString( MsgStr, pos, 'Letter Freq.    %                       Percentage', 0);
	   Write( MsgStr ) ;	
	   SWriteString( MsgStr, pos, ' ', 19);
	   IF ScaleFactor = 1 THEN
		SWriteString( MsgStr, pos, '    10   20   30   40   50   60   70   80   90  100', 0);
	   ELSE
		SWriteString( MsgStr, pos, '         10        20        30        40        50', 0);
	   END;
	   Write( MsgStr ) ;	
	   SWriteString( MsgStr, pos, ' ', 19);
	   SWriteString( MsgStr, pos, '+----+----+----+----+----+----+----+----+----+----+', 0);
	   Write( MsgStr ) ;	
(*	   FOR I := 0 TO Str.Length(SortAlphabet) - 1 DO *)
(*	      Ch := SortAlphabet[I]; *)
(*	      Ch := CHR(I); *)
	   FOR Ch := 0C TO 377C DO
	      IF ChTable[Ch] > 0 THEN
		 SortToIntWord(Letters[Ch], InternalCh) ;
		 TempReal := VAL(LONGREAL, ChTable[Ch]) / LRNoTokens * 100.0 ;
		 NoOfAsterisks := VAL(CARDINAL,
			VAL(LONGREAL,ChTable[Ch]) * VAL(LONGREAL,ScaleFactor) * 50.0 / LRNoTokens + 0.5) ;
		 Utils.ConstStr( '*', NoOfAsterisks, TempStr ) ;
		 TFormIO.WrF4( "%4c %6u%7.2r |%s", InternalCh, ChTable[Ch], TempReal, TempStr, MsgStr) ;
		 Write( MsgStr ) ;	
	      END;
	   END;
	   VarSq := VarSq/VAL(LONGREAL, NoTypes-1); (* n - 1 instead of n *)
	   StandDev := MATHLIB.Sqrt(VarSq);
	   Herdan := StandDev / (AveNoOccur * MATHLIB.Sqrt(LRNoTypes));
	   Write( MsgStr ) ;	
	   CASE GraphType OF
	      ChFirst:
		 SWriteString( MsgStr, pos, 'Total initial letters (Tokens)   = %8u', 0);
		 Header2 := 'initial';
		 FLen := 9;
	    | ChLast:
		 SWriteString( MsgStr, pos, 'Total final letters (Tokens)     = %8u', 0);
		 Header2 := 'final';
		 FLen := 11;
	    | ChAll:
		 SWriteString( MsgStr, pos, 'Total all letters (Tokens)       = %8u', 0);
		 Header2 := 'all';
		 FLen := 13;
	   END;
	   TFormIO.WrF1( MsgStr, NoTokens, MsgStr) ;
	   Write( MsgStr ) ;	

	   TFormIO.WrF1( 'Total different letters (Types)  = %8u', NoTypes, MsgStr ) ;
	   Write( MsgStr ) ;
	   TempReal := LRNoTypes / LRNoTokens ;
	   TFormIO.WrF1( 'Type/Token ratio                 = %13.4r', TempReal, MsgStr ) ;
	   Write( MsgStr ) ;	
	   TFormIO.WrF1( 'Arithmetric Mean                 = %13.4r', AveNoOccur, MsgStr ) ;
	   Write( MsgStr ) ;	
	   TFormIO.WrF1( 'Standard Deviation (S.D.)        = %13.4r', StandDev, MsgStr ) ;
	   Write( MsgStr ) ;	
	   TFormIO.WrF1( "Herdan's characteristic          = %13.4r", Herdan, MsgStr ) ;
	   Write( MsgStr ) ;	
	   TempReal :=  LRNoTokens / VAL(LONGREAL, MaxCount) ;
	   SortToIntWord(MaxCh, TempStr ) ;
	   TFormIO.WrF3( 'Repeat rate for %s letter "%c" = %13.2r', Header2, TempStr, TempReal, MsgStr ) ;
	   Write( MsgStr ) ;	
   END DoLetterFreq;

PROCEDURE InsertFreq( NoOccur : CARDINAL ) ;
   VAR
	U, L, M	: CARDINAL ;
   BEGIN
	IF FreqTable[MaxFreqIndex].Freq < NoOccur THEN
	   IF MaxFreqIndex < MaxR THEN
	      INC( MaxFreqIndex ) ;
	      FreqTable[MaxFreqIndex].Freq := NoOccur ;
	      FreqTable[MaxFreqIndex].Occur := 1 ;
	   ELSE
	      ProgramErrorAndHalt( 'Frequency table limit exceeded.') ;
	   END ;
	ELSE
	   U := MaxFreqIndex ;
	   L := 1 ;
	   M := (U + L) DIV 2 ;
	   WHILE L <= M DO
		IF FreqTable[M].Freq < NoOccur THEN
		   L := M + 1
		ELSIF FreqTable[M].Freq > NoOccur THEN
		   U := M - 1
		ELSE
		   INC( FreqTable[M].Occur ) ;
		   RETURN ;
		END ;
		M := (U + L) DIV 2 ;
	   END ;
	   IF MaxFreqIndex < MaxR THEN
	      INC( MaxFreqIndex ) ;
	      Lib.WordMove( ADR(FreqTable[L]), ADR(FreqTable[L+1]),
		     SIZE(TypeTokenRec) * (MaxFreqIndex - M) DIV 2 ) ;
	      FreqTable[L].Freq := NoOccur ;
	      FreqTable[L].Occur := 1 ;
	   ELSE
	      ProgramErrorAndHalt( 'Frequency table limit exceeded.') ;
	   END ;
	END ;
   END InsertFreq ;

   PROCEDURE MySortToIntWord( SortWord : ARRAY OF CHAR ;
                          VAR IntWord : ARRAY OF CHAR ) ;
   VAR
	T:     StrAny;
	AL,NS: CARDINAL;
	ED:    BOOLEAN;
	cm:    CurrentModeType;
   BEGIN
	cm.ModeIn := '0'; cm.ModeOut := '0';
	SortToFullWord(SortWord,T);

	(* do some local computations here *)
	   SortLen := Str.Pos( SortWord, ExtraCodeSep ) ;
	   IF SortLen = MAX(CARDINAL) THEN  SortLen := Str.Length(SortWord)  END;
           INC( WordLenTable[ SortLen ], LONGCARD(TDBTypeRec^.NoOccur));

           FOR I := 0 TO SortLen - 1 DO
              INC( AllChTable[ KeyStr[I] ], LONGCARD(TDBTypeRec^.NoOccur))
	   END;
	   INC( FirstChTable[ KeyStr[0] ], LONGCARD(TDBTypeRec^.NoOccur));
	   INC( LastChTable[ KeyStr[SortLen-1] ], LONGCARD(TDBTypeRec^.NoOccur));

	XlateLine(Alp2Int,'?',T,cm,AL,LenD,NS,ED,IntWord);
   END MySortToIntWord;

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

	(* quickly initialize to zero *)
        Lib.WordFill( ADR(WordLenTable), SIZE(WordLenTable) DIV 2, 0);
        Lib.WordFill( ADR(FirstChTable), SIZE(FirstChTable) DIV 2, 0);
        Lib.WordFill( ADR(LastChTable),  SIZE(LastChTable) DIV 2, 0);
        Lib.WordFill( ADR(AllChTable),   SIZE(AllChTable) DIV 2, 0);
        Lib.WordFill( ADR(FreqTable),    SIZE(FreqTable) DIV 2, 0);

	(* initialize alphabet *)
	I := 0 ;
	FOR Ch := FirstAlphChar TO LastAlphChar DO
	   SortAlphabet[I] := Ch ;
	   INC( I ) ;
	END ;
	SortAlphabet[I] := 0C ;

	(*RES OLD MSG  <<< defined in TACTFreq Runsourc >>>
	Reading the TDB file.
	*)
	PutRunStatus( (*RES REM INS*) 503 );

	MaxFreqIndex := 0;
	WHILE GetNextTypeInfo( TDBTypeRec ) AND NOT CheckAbort() DO
	   INC(Count);
	   Percentage := VAL(CARDINAL,Count * 100 DIV LONGCARD(TDBInit.NoTypes)) ;
	   IF Percentage >= LastPercentage THEN
		PutPercentage( Percentage ) ;
		INC(LastPercentage, 4) ;
	   END ;

(*	   MySortToIntWord( SortWord, KeyStr ) ; *)

	   SortLen := Str.Pos( SortWord, ExtraCodeSep ) ;
	   IF SortLen = MAX(CARDINAL) THEN  SortLen := Str.Length(SortWord)  END;
           INC( WordLenTable[ SortLen ], LONGCARD(TDBTypeRec^.NoOccur));
           FOR I := 0 TO SortLen - 1 DO
              INC( AllChTable[ SortWord[I] ], LONGCARD(TDBTypeRec^.NoOccur))
	   END;
	   INC( FirstChTable[ SortWord[0] ], LONGCARD(TDBTypeRec^.NoOccur));
	   INC( LastChTable[ SortWord[SortLen-1] ], LONGCARD(TDBTypeRec^.NoOccur));
(*
           FOR I := 0 TO SortLen DO
              INC( AllChTable[ SortWord[I] ])
	   END;
	   INC( FirstChTable[ SortWord[0] ]);
	   INC( LastChTable[ SortWord[SortLen-1] ]);
*)	
	   InsertFreq( TDBTypeRec^.NoOccur ) ;
	   IF MostFreqWord.FreqCount < TDBTypeRec^.NoOccur THEN
		MostFreqWord.FreqCount := TDBTypeRec^.NoOccur ;
		Str.Copy( MostFreqWord.Word, SortWord ) ;
	   END ;

	END ;

	DEALLOCATE( HRecord, HyperLength ) ;

	FIO.Close( TDBFileID ) ;

	(*RES OLD MSG 521
	Output phase.
	*)
	PutRunStatus( (*RES REM INS*) 521 );
	PutPercentage( 0 ) ;

	(* calculate various statistics *)
	
	(* DON'T really need to do this loop -- already have these values in TDB *)
	NoTypes := 0;
	NoTokens := 0;
	FOR r := 1 TO MaxFreqIndex DO
	    INC(NoTypes, LONGCARD(FreqTable[r].Occur));
	    INC(NoTokens, VAL(LONGCARD,FreqTable[r].Occur*FreqTable[r].Freq));
	END ;

	LRNoTokens := VAL(LONGREAL, NoTokens ) ;
	LRNoTypes  := VAL(LONGREAL, NoTypes ) ;
	AveNoOccur := LRNoTokens / LRNoTypes;
	VarSq := 0.0;
	Skew  := 0.0;
	Kurt  := 0.0;
	Yule  := 0.0;
	FOR r := 1 TO MaxFreqIndex DO
	   LRFreq := VAL(LONGREAL, FreqTable[r].Freq ) ;
	   LROccur:= VAL(LONGREAL, FreqTable[r].Occur) ;
	   Temp1 := LRFreq - AveNoOccur;
	   Temp2 := Temp1 * Temp1 ;
	   VarSq := VarSq + Temp2 * LROccur;
	   Skew  := Skew  + Temp2 * Temp1 * LROccur;
	   Kurt  := Kurt  + Temp2 * Temp2 * LROccur;
	   Yule  := Yule  + LRFreq * LRFreq * LROccur;
	END;
	IF Temp1 = 0.0 THEN (* m.s. - special case *)
	    VarSq := 0.0 ;
	    StandDev := 0.0 ;
	    Skew := 0.0 ;
	    Kurt := 0.0 ;
	    Herdan := 0.0 ;
	ELSE
	    VarSq := VarSq/(LRNoTypes - 1.0); (* use n - 1 instead of n *)
	    StandDev := MATHLIB.Sqrt(VarSq);
	    Skew := (Skew/(LRNoTypes - 1.0)) / (StandDev * StandDev * StandDev);
	    Kurt := (Kurt/(LRNoTypes - 1.0)) / (StandDev * StandDev * StandDev * StandDev)- 3.0;
	    Herdan := StandDev / (AveNoOccur * MATHLIB.Sqrt(LRNoTypes));
	END ;
	Yule := Yule * 10.0E4 / (LRNoTokens * LRNoTokens - 1.0 / LRNoTokens);

	(* produce an OCP style table *)

	pos := 0 ;
	SWriteString( MsgStr, pos,
		'Frequency  Observed Freq.  Words in    Types  Tokens   % of     % of   % of word', 0 ) ;
	Write( MsgStr ) ;	
	SWriteString( MsgStr, pos,
		'  Rank         of Rank    Frequency    Total   Total   Types   Tokens   in freq.', 0 ) ;
	Write( MsgStr ) ;	
	Write( MsgStr ) ;	
	TotTypes := 0 ;
	TotTokens := 0 ;

	FOR r := 1 TO MaxFreqIndex DO
	    WITH FreqTable[r] DO
	      FreqOccur := LONGCARD(Freq) * LONGCARD(Occur) ;
	      INC(TotTypes, LONGCARD(Occur));
	      INC(TotTokens, FreqOccur);
	      TotTypeRatio := VAL(LONGREAL, TotTypes) / LRNoTypes*100.0 ;
	      TotTokenRatio := VAL(LONGREAL, TotTokens) / LRNoTokens*100.0 ;
	      FreqOccurRatio := VAL(LONGREAL, FreqOccur) / LRNoTokens*100.0 ;
	      TFormIO.WrF8( "%6u      %8u  %10u   %8u%8u %8.2r %8.2r %8.2r",
			    Freq,  Occur,FreqOccur,TotTypes, TotTokens,
			    TotTypeRatio, TotTokenRatio, FreqOccurRatio,
			    MsgStr);
	    END ;
	    Write( MsgStr ) ;	
	END;
	Write( MsgStr ) ;	
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Number of Types   = %8u', NoTypes, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Number of Tokens  = %8u', NoTokens, MsgStr ) ;
	Write( MsgStr ) ;	
	TempReal := LRNoTypes / LRNoTokens ;
	TFormIO.WrF1( 'Type/Token ratio  = %12.3r', TempReal, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Token/Type ratio  = %12.3r', AveNoOccur, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Hapax Legomena    = %8u', FreqTable[1].Occur, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Hapax Dislegomena = %8u', FreqTable[2].Occur, MsgStr ) ;
	Write( MsgStr ) ;	
	LRHapax := VAL(LONGREAL, FreqTable[1].Occur ) ;
	IF FreqTable[2].Occur > 0 THEN   (* m.s. - check that all words don't occur the same number of times *)
  	  TempReal := LRHapax / VAL(LONGREAL,FreqTable[2].Occur) ;
  	ELSE
  	  TempReal := 0.0 ;
  	END ;
	TFormIO.WrF1( 'Hapax Legomena/Dislegomena ratio   = %10.4r', TempReal, MsgStr ) ;
	Write( MsgStr ) ;	
	TempReal := LRHapax / LRNoTypes ;
	TFormIO.WrF1( 'Hapax Legomena/Number of Types     = %10.4r', TempReal, MsgStr ) ;
	Write( MsgStr ) ;	
	TempReal := LRHapax / LRNoTokens ;
	TFormIO.WrF1( 'Hapax Legomena/Number of Tokens    = %10.4r', TempReal, MsgStr ) ;
	Write( MsgStr ) ;
	TempReal := (LRHapax * LRHapax * LRHapax) / (LRNoTypes * LRNoTypes);
	TFormIO.WrF1( 'Hapax Legomena cubed/Types squared = %10.4r', TempReal, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Variance ( S.D. squared )          = %10.4r', VarSq, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Standard Deviation (S.D.)          = %10.4r', StandDev, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Coefficient of skewness            = %10.4r', Skew, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Coefficient of kurtosis            = %10.4r', Kurt, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( "Herdan's characteristic            = %10.4r", Herdan, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( "Yule's characteristic              = %10.4r", Yule, MsgStr ) ;
	Write( MsgStr ) ;	
	TempReal := LRNoTypes / MATHLIB.Sqrt( 2.0 * LRNoTokens) ;
	TFormIO.WrF1( 'Carroll TTR (Types / Sqrt of 2 X Tokens) = %10.4r', TempReal, MsgStr ) ;
	Write( MsgStr ) ;	
	SortToIntWord(MostFreqWord.Word, TempStr ) ;
(*	TFormIO.WrF2( 'Most Frequent word "%s" occurred %u times', MostFreqWord.Word, MostFreqWord.FreqCount, MsgStr ) ;*)
	TFormIO.WrF2( 'Most Frequent word "%s" occurred %u times', TempStr, MostFreqWord.FreqCount, MsgStr ) ;
	Write( MsgStr ) ;
	TempReal := LRNoTokens / VAL(LONGREAL, MostFreqWord.FreqCount) ;
	TFormIO.WrF1( 'repeat rate (Tokens / frequency most frequent word) = %10.4r', TempReal, MsgStr ) ;

	PutPercentage( 25 ) ;
	Write( MsgStr ) ;	
	Write( MsgStr ) ;	
	Write( MsgStr ) ;	
	SWriteString( MsgStr, pos, 'Word Length Statistics', 0 ) ;
	Write( MsgStr ) ;	
	SWriteString( MsgStr, pos, '----------------------', 0 ) ;
	Write( MsgStr ) ;	
	Write( MsgStr ) ;	

	NoTypes  := 0;
	NoTokens := 0;
	MaxCount  := 0;
	FOR I := 1 TO MaxWordLen DO
	   IF WordLenTable[I] > MaxCount THEN  MaxCount := WordLenTable[I]  END;
	   INC(NoTypes, WordLenTable[I]);
	   INC(NoTokens, VAL(LONGCARD, WordLenTable[I] * LONGCARD(I)) );
	END;
	IF NoTypes DIV MaxCount >= 2 THEN
	   (* ie. largest item is less than 50 % *)
	   ScaleFactor := 2
	ELSE
	   ScaleFactor := 1
	END;
	SWriteString( MsgStr, pos, 'Word  Freq.    %                        Percentage', 0 ) ;
	Write( MsgStr ) ;	
	SWriteString( MsgStr, pos, ' Len               ', 0 ) ;

	IF ScaleFactor = 1 THEN
	   SWriteString( MsgStr, pos, '    10   20   30   40   50   60   70   80   90  100', 0);
	ELSE
	   SWriteString( MsgStr, pos, '         10        20        30        40        50', 0);
	END;
	Write( MsgStr ) ;	
	SWriteString( MsgStr, pos, ' ', 19);
	SWriteString( MsgStr, pos, '+----+----+----+----+----+----+----+----+----+----+', 0);
	Write( MsgStr ) ;	

	(* recycle some variables *)
	LRNoTokens := VAL(LONGREAL, NoTokens ) ;
	LRNoTypes  := VAL(LONGREAL, NoTypes  ) ;
	AveNoOccur := LRNoTokens / LRNoTypes;	(* TotTokens/TotVocab *)
	VarSq := 0.0; (* find last non empty word length *)
	J := MaxWordLen;
	WHILE WordLenTable[J] = 0 DO  DEC(J)  END;
	FOR I := 1 TO J DO
	   TempReal := VAL(LONGREAL, WordLenTable[I]) / LRNoTypes * 100.0 ;
	   NoOfAsterisks := VAL(CARDINAL,
		VAL(LONGREAL,WordLenTable[I]) * VAL(LONGREAL,ScaleFactor) * 50.0 / LRNoTypes + 0.5) ;
	   Utils.ConstStr( '*', NoOfAsterisks, TempStr ) ;
	   TFormIO.WrF4( "%4u %6u%7.2r |%s", I, WordLenTable[I], TempReal, TempStr, MsgStr) ;
	   Write( MsgStr ) ;	
	   Temp1 := VAL(LONGREAL, I) - AveNoOccur;
	   Temp2 := Temp1 * Temp1 ;
	   VarSq := VarSq + Temp2 * VAL(LONGREAL, WordLenTable[I]);
	END;
	VarSq := VarSq/VAL(LONGREAL, NoTypes - 1); (* use n - 1 instead of n *)
	StandDev := MATHLIB.Sqrt(VarSq);
	Herdan := StandDev / (AveNoOccur * MATHLIB.Sqrt( VAL(LONGREAL, NoTypes) ) );

	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Total letters (Tokens)   = %8u', NoTokens, MsgStr );
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Total Words (Types)      = %8u', NoTypes, MsgStr );
	Write( MsgStr ) ;	
	TempReal := LRNoTypes / LRNoTokens ;
	TFormIO.WrF1( 'Type/Token ratio         = %13.4r', TempReal, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Mean word length         = %13.4r', AveNoOccur, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Variance (S.D. squared)  = %13.4r', VarSq, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( 'Standard Deviation (S.D.)= %13.4r', StandDev, MsgStr ) ;
	Write( MsgStr ) ;	
	TFormIO.WrF1( "Herdan's characteristic  = %13.4r", Herdan, MsgStr ) ;
	Write( MsgStr ) ;	
	Write( MsgStr ) ;	
	Write( MsgStr ) ;	

	PutPercentage( 50 ) ;
	SWriteString( MsgStr, pos, 'First letter in words statistics', 0);
	Write( MsgStr ) ;	
	SWriteString( MsgStr, pos, '--------------------------------', 0);
	Write( MsgStr ) ;	
	DoLetterFreq(FirstChTable, ChFirst);
	Write( MsgStr ) ;	
	Write( MsgStr ) ;	
	SWriteString( MsgStr, pos, 'Final letter in words statistics', 0);
	Write( MsgStr ) ;	
	SWriteString( MsgStr, pos, '--------------------------------', 0);
	Write( MsgStr ) ;	
	DoLetterFreq(LastChTable, ChLast);
	Write( MsgStr ) ;	
	Write( MsgStr ) ;	
	PutPercentage( 75 ) ;
	SWriteString( MsgStr, pos, 'All letters in words statistics', 0);
	Write( MsgStr ) ;	
	SWriteString( MsgStr, pos, '-------------------------------', 0);
	Write( MsgStr ) ;	
	DoLetterFreq(AllChTable, ChAll);
	Write( MsgStr ) ;	
	PutPercentage( 100 ) ;

	IF FileData.GenStatOut = OutToDisk THEN  XClose( OutFileID )  END ;
   END DoStatOutput ;

PROCEDURE Run(VAR MsgStr : ARRAY OF CHAR );
  TYPE
        StatusType   = RECORD  (* m.s. *)
                Percent            : CARDINAL ;	
                MsgText            : ARRAY [0..80] OF CHAR ;
              END ;
   VAR
	len		: CARDINAL;
	StatusMenu	: MenuID;
	Status          : StatusType;
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

	WITH StatDispTab[0] DO
	     Pos := 5;
	     Type := Left;
	     FilPat := '';
	END;

	FIO.IOcheck := FALSE ;
	IF FileData.GenStatOut = OutToPrinter THEN	
	   PrintMaster( ToPrinter, DoStatOutput, DoRead, ch, FunctKey );
	ELSE
	   DoStatOutput( OutFileID, AbortForFileIO )
	END ;
        Str.Copy( MsgStr, 'TACTSTAT finished successfully.');
   END Run;

END RUNSource .
