MODULE DumpDBS ;

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

IMPORT Str, Lib, IO, FIO ;
FROM SYSTEM IMPORT ADR, TSIZE, BYTE, ADDRESS;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
IMPORT BitOps ;
FROM WordBase IMPORT
  (* Types *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar, SortNoBitsPerChar,
  (* Procs *) SortToIntWord ;

FROM GlobalDefs IMPORT
  (* Type  *) SequenceType, StrAny, FileNameType,
  (* Const *) MaxCharsInSeq, NumbXlateSeq, MaxStringLen, MaxFileNameLength ;

FROM HyperDataModel IMPORT
  (* Const *) HyperLength, PastHeader, HNoOccurs, HNoTokens, HNoDataPtrs,
              BaseHTypeLen, HyperLengthM1, OccurRecSize,
	      MaxSpaceForOccursInRec, TypeMaxDataPos,
  (* Types *) HyperData, HTypePntr, HyperRType, HTypeData, HOccurData,
              HTokenData, HLogDataType, HCompTokenData, TDBTypeData, TDBStrPntr;

FROM StringIO IMPORT SWriteString, SWriteCard, SWriteInt, SWriteChar, SWriteLongInt ;

FROM Utils IMPORT
 (* var  *) month, day, year,
 (* proc *) StandardizeFileName ;

FROM Translations IMPORT
 (* type *) XlateTablePointer, XlateEntryPointer, XlateEntryDataType,
            XlateTable, XlateTablePntr, XlateTableRec, XlateEntryDataTypeType,
 (* var  *) Int2Alp, Alp2Int ;

(*
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames, NumbOfRefUnits;
*)

TYPE
    RefsNameList = ARRAY[0..1000] OF POINTER TO RefsNameData;
    RefsNameData = RECORD
        ID:    INTEGER;
        Pref:  CHAR;  (* used as 1 byte # *)
        Name:  StrAny;
    END;
VAR
    RefsNameListPntr	: POINTER TO RefsNameList;
    NumbOfRefNames	: CARDINAL;  (* total number of reference names *)
    NumbOfRefUnits	: CARDINAL;  (* total number of different refernces *)

TYPE
   HexType = ARRAY[0..15] OF CHAR ;
   StrRecStructType = RECORD
           ID         : INTEGER ;
           Start      : CHAR ; (* offset to start string record *)
           StartIndex : CHAR ; (* array index of 1 st string *)
           End        : CHAR ;
           EndIndex   : CHAR ;
       END ;

TYPE NoBitsMask = ARRAY[4..8] OF CARDINAL ;  (* could prob. do without 4 !? *)
CONST NoBits = NoBitsMask ( 000FH, 001FH, 003FH, 007FH, 00FFH ) ;

CONST
   Ruler = "     0----+---10----+---20----+---30----+---40----+---50----+---60----+---70----+---80----+---90----+----" ;
   HexChars = HexType ( '0123456789ABCDEF' );

VAR
   InputFileName  : FileNameType ;
   DBFile         : FIO.File ;
   OutputFileName : FileNameType ;
   DumpFile       : FIO.File ;
   SortName	  : StrAny ;
   HexStr	  : StrAny ;
   Message        : StrAny ;
   MsgPos         : CARDINAL ;
   I, J, K        : CARDINAL ;
   Len		: CARDINAL ;
   StrRecStruct : StrRecStructType ;
   InRec, EndRec, StartRec : INTEGER ;
   NoGo         : BOOLEAN ;
   Ch	        : CHAR ;
   HRecord      : HyperData ;
   HRecNo,
   HRecPos      : CARDINAL ;
   HTempStr     : StrAny ;
   NoTokensInDB : LONGINT ;
   StartAt	: CARDINAL ;

(* from DBData.DEF *)
VAR
    BeginStr   : CARDINAL ;
    EndStr     : CARDINAL ;
    BeginStrRec: CARDINAL ;
    NoStrRecs  : CARDINAL ;
    BeginLog   : CARDINAL ;
    EndLog     : CARDINAL ;
    BeginType  : CARDINAL ;
    BeginTokenHRec : CARDINAL ;
    BeginText  : CARDINAL ;
    EndTextRec : CARDINAL ;
    EndTextIdx : CARDINAL ;
    EndTypeHRec : CARDINAL ;
    EndTypeIdx : CARDINAL ;
    EndTokenHRec : CARDINAL ;
    EndTokenIdx : CARDINAL ;
    NoTypes     : CARDINAL ;
    LastAlphChar : CHAR;


PROCEDURE MakePrintableDate(day, month, year: CARDINAL; VAR String: ARRAY OF CHAR);
   TYPE  MonthNms  = ARRAY [1..12] OF ARRAY [0..15] OF CHAR;
   CONST MonthName = MonthNms ("January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December" ) ;
   BEGIN
	MsgPos := 0 ;
	SWriteString(String, MsgPos, MonthName[month], 0);
	SWriteString(String, MsgPos, " ", 0);
	SWriteCard( String, MsgPos, day, 0);
	SWriteString(String, MsgPos, ", ", 0);
	SWriteCard( String, MsgPos, year, 0);
   END MakePrintableDate;

PROCEDURE NewPrintCode(     SeqIn: ARRAY OF CHAR; NoChars: CARDINAL;
			VAR SeqOut: ARRAY OF CHAR);
  VAR  NP: CARDINAL;
  BEGIN
    NP := 0;
    WHILE (NP <= HIGH(SeqIn)) AND (NP <= NoChars) AND (NP <= HIGH(SeqOut)) DO
      IF (SeqIn[NP] < ' ') OR (SeqIn[NP] > '~') THEN  (* *LP* was: SeqOut *)
           SeqOut[NP] := ':'
      ELSE
           SeqOut[NP] := SeqIn[NP]
      END;
      INC(NP)
    END;
    IF NP <= HIGH(SeqOut) THEN SeqOut[NP] := 0C END;
  END NewPrintCode;

PROCEDURE NewPrintHex1(     SeqIn: ARRAY OF CHAR;  NoChars: CARDINAL;
			VAR SeqOut: ARRAY OF CHAR);
  VAR  NP: CARDINAL;
  BEGIN
    NP := 0;
    WHILE (NP <= HIGH(SeqIn)) AND (NP <= NoChars) AND (NP <= HIGH(SeqOut)) DO
      SeqOut[NP] := HexChars[ORD(SeqIn[NP]) DIV 16];
      INC(NP)
    END;
    IF NP <= HIGH(SeqOut) THEN SeqOut[NP] := 0C END;
  END NewPrintHex1;

PROCEDURE NewPrintHex2(SeqIn: ARRAY OF CHAR; NoChars: CARDINAL;
                  VAR SeqOut: ARRAY OF CHAR);
  VAR  NP: CARDINAL;
  BEGIN
    NP := 0;
    WHILE (NP <= HIGH(SeqIn)) AND (NP <= NoChars) AND (NP <= HIGH(SeqOut)) DO
      SeqOut[NP] := HexChars[INTEGER(ORD(SeqIn[NP])) MOD 16];
      INC(NP)
    END;
    IF NP <= HIGH(SeqOut) THEN SeqOut[NP] := 0C END;
  END NewPrintHex2;

PROCEDURE PrintHex( SeqIn : ARRAY OF CHAR; VAR SeqOut : ARRAY OF CHAR );
  VAR NP, NP2 : CARDINAL;
  BEGIN
    NP := 0;
    NP2 := 0;
    WHILE (NP <= HIGH(SeqIn)) AND (SeqIn[NP] <> 0C) AND (NP2 <= HIGH(SeqOut)-1) DO
      SeqOut[NP2] := HexChars[ORD(SeqIn[NP]) DIV 16];
      SeqOut[NP2 + 1] := HexChars[ORD(SeqIn[NP]) MOD 16];
      INC(NP);
      INC(NP2,2)
    END;
    IF NP2 <= HIGH(SeqOut) THEN SeqOut[NP2] := 0C END;
  END PrintHex;

PROCEDURE WriteScrLn( Text : ARRAY OF CHAR ) ;
    BEGIN
        IO.WrStr( Text ) ;
        IO.WrLn ;
    END WriteScrLn ;

PROCEDURE WrFileLine( Text : ARRAY OF CHAR ) ;
    BEGIN
	FIO.WrStr( DumpFile, Text ) ;
	FIO.WrLn( DumpFile ) ;
    END WrFileLine ;

PROCEDURE BadFileName( Name : ARRAY OF CHAR ) ;
  BEGIN
     MsgPos := 0 ;
     SWriteString( Message, MsgPos, 'Invalid file name: ', 0 ) ;
     SWriteString( Message, MsgPos, Name, 0 ) ;
     WriteScrLn( Message ) ;
     HALT ;
  END BadFileName ;

PROCEDURE IOCheck ;
   BEGIN
     IF FIO.IOresult() <> 0 THEN
        MsgPos := 0 ;
        SWriteString( Message, MsgPos, 'Input file - ', 0 ) ;
        SWriteString( Message, MsgPos, InputFileName, 0 ) ;
        SWriteString( Message, MsgPos, ': ', 0 ) ;
        WriteScrLn( Message ) ;
        FIO.Close( DumpFile ) ;  (* time to stop: clean up first *)
        FIO.Close( DBFile ) ;
        HALT ;
     END ;
   END IOCheck ;

PROCEDURE InitFiles() : BOOLEAN ;
  PROCEDURE DoOpens ;
     BEGIN
          IF NOT StandardizeFileName( OutputFileName, '.DMP' ) THEN
             BadFileName( OutputFileName ) ;
          END ;
          DumpFile := FIO.Create( OutputFileName ) ;
          IF NOT StandardizeFileName( InputFileName, '.TDB' ) THEN
             BadFileName( InputFileName ) ;
          END ;
          DBFile := FIO.Open( InputFileName ) ;
          IOCheck ;
     END DoOpens ;
  BEGIN
     CASE Lib.ParamCount() OF
       0 :
          WriteScrLn( 'Command Syntax:  DUMPDBS <infile> <outfile>' ) ;
          RETURN FALSE ; |
       1 :
          Lib.ParamStr( InputFileName, 1 ) ;
          OutputFileName := "DUMP.DMP" ;
          DoOpens ;
          RETURN TRUE ; |
       2 :
          Lib.ParamStr( InputFileName, 1 ) ;
          Lib.ParamStr( OutputFileName, 2 ) ;
          DoOpens ;
          RETURN TRUE ;
      ELSE
          WriteScrLn( 'Invalid number of arguments given.' ) ;
          WriteScrLn( '' ) ;
          WriteScrLn( 'Command Syntax:  DUMPDBS <infile> <outfile>' ) ;
          RETURN FALSE ;
     END ;
  END InitFiles ;

PROCEDURE ReadDBRec( RecNo : INTEGER ) ;
  VAR
     BytesRead : CARDINAL ;
  BEGIN
     FIO.Seek( DBFile, LONGCARD( RecNo ) * HyperLength ) ;
     IOCheck ;
     Lib.Fill( ADR(HRecord), HyperLength, 0C ) ;
     BytesRead := FIO.RdBin( DBFile, HRecord, HyperLength ) ;
     IOCheck ;
     HRecPos := 0 ;
  END ReadDBRec ;

PROCEDURE GetInRecNumber( VAR InRec : INTEGER ) ;
    VAR
        InStr : StrAny ;
        NumStr: StrAny ;
        Done  : BOOLEAN ;
    BEGIN
        REPEAT
            IO.WrStr( 'Enter hyper record number: ' ) ;
            IO.RdStr( InStr ) ;  IO.WrLn ;
            I := Str.Pos( InStr, ":" ) ;
            IF I = MAX(CARDINAL) THEN
		InRec := VAL( INTEGER, Str.StrToInt( InStr, 10, Done ) );
		StartRec := InRec ;
		EndRec   := InRec ;
            ELSE
		Str.Slice( NumStr, InStr, 0, I ) ;
		InRec := VAL( INTEGER, Str.StrToInt( NumStr, 10, Done ) );
		StartRec := InRec ;
		Str.Slice( NumStr, InStr, I+1, 255 ) ;
		EndRec := VAL( INTEGER, Str.StrToInt( NumStr, 10, Done ) );
            END ;
            IF NOT Done THEN
                WriteScrLn( ' invalid (integer) number entered.' ) ;
            END ;
        UNTIL Done ;
    END GetInRecNumber ;

PROCEDURE DoStrWrFile(  Label, string : ARRAY OF CHAR ) ;
  BEGIN
      MsgPos := 0 ;
      SWriteString( Message, MsgPos, Label, 0 ) ;
      SWriteString( Message, MsgPos, string, 0 ) ;
      WrFileLine( Message ) ;
  END DoStrWrFile ;

PROCEDURE DoCardWrFile( string : ARRAY OF CHAR ; Card : CARDINAL ) ;
  BEGIN
      MsgPos := 0 ;
      SWriteString( Message, MsgPos, string, 0 ) ;
      SWriteCard( Message, MsgPos, Card, 5 ) ;
      WrFileLine( Message ) ;
  END DoCardWrFile ;

PROCEDURE Do2CardWrFile( string : ARRAY OF CHAR ; Card1, Card2 : CARDINAL ) ;
  BEGIN
      MsgPos := 0 ;
      SWriteString( Message, MsgPos, string, 0 ) ;
      SWriteCard( Message, MsgPos, Card1, 5 ) ;
      SWriteCard( Message, MsgPos, Card2, 5 ) ;
      WrFileLine( Message ) ;
  END Do2CardWrFile ;

PROCEDURE DoIntWrFile(  string : ARRAY OF CHAR ; Int : INTEGER ) ;
  BEGIN
      MsgPos := 0 ;
      SWriteString( Message, MsgPos, string, 0 ) ;
      SWriteInt( Message, MsgPos, Int, 5 ) ;
      WrFileLine( Message ) ;
  END DoIntWrFile ;

PROCEDURE DoRecWrite( string : ARRAY OF CHAR ; Int : INTEGER ) ;
    BEGIN
        WrFileLine( '' ) ;
        DoIntWrFile( string, Int ) ;
        MsgPos := 0 ;
        SWriteString( Message, MsgPos, string, 0 ) ;
        SWriteCard( Message, MsgPos, Int, 0 ) ;
        WriteScrLn( Message ) ;
        WrFileLine( Ruler ) ;
        J := 100 ;
        FOR I := 0 TO (HyperLength DIV 100) DO
	    IF I = 10 THEN J := HyperLength MOD 100  END ;  (* last chunk *)
            Lib.Move( ADR(HRecord.TextData[I*100]), ADR(HTempStr), J ) ;
            HTempStr[J] := 0C ;
            MsgPos := 0 ;
            SWriteCard( Message, MsgPos, I*100, 4 ) ;
            SWriteString( Message, MsgPos, ' ', 0 ) ;
            NewPrintCode( HTempStr, J-1, HexStr ) ;
            DoStrWrFile( Message, HexStr ) ;
            IF Str.Length( HexStr ) = 0 THEN
               RETURN    (* no more to display for this record *)
            END ;
            MsgPos := 0 ;
            SWriteString( Message, MsgPos, ' ', 5 ) ;
            NewPrintHex1( HTempStr, J-1, HexStr ) ;
            DoStrWrFile( Message, HexStr ) ;
            MsgPos := 0 ;
            SWriteString( Message, MsgPos, ' ', 5 ) ;
            NewPrintHex2( HTempStr, J-1, HexStr ) ;
            DoStrWrFile( Message, HexStr ) ;
        END ;
    END DoRecWrite ;

PROCEDURE DoLogWrite( string : ARRAY OF CHAR ; Int : INTEGER ) ;
    VAR CurTokenNo : LONGINT ;
    BEGIN
        WrFileLine( '' ) ;
        MsgPos := 0 ;
        SWriteString( Message, MsgPos, string, 0 ) ;
        SWriteCard( Message, MsgPos, Int, 0 ) ;
        WriteScrLn( Message ) ;
        SWriteString( Message, MsgPos, '    Base Log:', 0 ) ;
        SWriteCard( Message, MsgPos, CARDINAL(Int) - BeginLog, 5 ) ;
        SWriteString( Message, MsgPos, '  BaseTokenNo: ', 0 ) ;
        SWriteLongInt( Message, MsgPos, HRecord.BaseTokenNo, 8 ) ;
        WrFileLine( Message ) ;
        CurTokenNo := HRecord.BaseTokenNo ;
        FOR Ch := 0C TO 376C DO
	    IF (CARDINAL(Int) = EndLog) AND (Ch <> 0C) AND
	       (HRecord.LogData[Ch].TokenNoOffset = 0) AND
	       (HRecord.LogData[Ch].StructID = 0) THEN  RETURN  END ;
	    INC( CurTokenNo, LONGINT(HRecord.LogData[Ch].TokenNoOffset) ) ;
            MsgPos := 0 ;
            SWriteCard( Message, MsgPos, ORD(Ch), 4 ) ;
            SWriteString( Message, MsgPos, ' ', 0 ) ;
            SWriteString( Message, MsgPos, 'ID: ', 0 ) ;
            SWriteInt( Message, MsgPos, INTEGER(HRecord.LogData[Ch].StructID), 4 ) ;
            IF INTEGER(HRecord.LogData[Ch].StructID) > 0 THEN
		SWriteString( Message, MsgPos, ' ', 27 ) ;
		SWriteString( Message, MsgPos, ' Count: ', 0 ) ;
		SWriteCard( Message, MsgPos, HRecord.LogData[Ch].Count, 5 ) ;
            ELSE
		SWriteString( Message, MsgPos, ' SRecNo: ', 0 ) ;
		SWriteCard( Message, MsgPos, ORD(HRecord.LogData[Ch].SRecNo), 4 ) ;
		SWriteString( Message, MsgPos, ' SRecPos: ', 0 ) ;
		SWriteCard( Message, MsgPos, ORD(HRecord.LogData[Ch].SRecPos), 4 ) ;
		SWriteString( Message, MsgPos, ' ', 13 ) ;
            END ;
            SWriteString( Message, MsgPos, ' Tok offset: ', 0 ) ;
            SWriteCard( Message, MsgPos, CARDINAL(HRecord.LogData[Ch].TokenNoOffset), 3 ) ;
	    SWriteLongInt( Message, MsgPos, CurTokenNo, 8 ) ;
            WrFileLine( Message ) ;

            IF CurTokenNo > NoTokensInDB THEN
		MsgPos := 0 ;
		SWriteString( Message, MsgPos, '** Bad Token pointer for Log: (Max val =', 0 ) ;
		SWriteLongInt( Message, MsgPos, NoTokensInDB, 8 ) ;
		SWriteString( Message, MsgPos, ')', 0 ) ;
		WrFileLine( Message ) ;
		MsgPos := 0 ;
		SWriteString( Message, MsgPos, ' ', 5 ) ;
		WriteScrLn( '** Bad Token pointer for Log. **' ) ;
            END ;
        END ;
    END DoLogWrite ;

PROCEDURE DoTokenWrite( string : ARRAY OF CHAR ; Int : INTEGER ) ;
    VAR  temp, LRecNo, LRecIdx, TRecNo, TRecIdx : CARDINAL ;
    BEGIN
        WrFileLine( '' ) ;
        MsgPos := 0 ;
        SWriteString( Message, MsgPos, string, 0 ) ;
        SWriteCard( Message, MsgPos, Int, 0 ) ;
        WriteScrLn( Message ) ;
        SWriteString( Message, MsgPos, '  BaseToken: ', 0 ) ;
        SWriteCard( Message, MsgPos, CARDINAL(Int) - BeginTokenHRec, 0 ) ;
        SWriteString( Message, MsgPos, '  BaseTextRec: ', 0 ) ;
        SWriteCard( Message, MsgPos, HRecord.BaseTextRec, 0 ) ;
        SWriteString( Message, MsgPos, '  BaseLogRec: ', 0 ) ;
        SWriteCard( Message, MsgPos, HRecord.BaseLogRec, 0 ) ;
        SWriteString( Message, MsgPos, '  (H - Headword, T - Text, L - Log)', 0 ) ;
        WrFileLine( Message ) ;
        FOR I := 0 TO HNoTokens-1 DO
	    IF (CARDINAL(Int) >= EndTokenHRec) AND (I > EndTokenIdx) THEN  RETURN  END ;
            MsgPos := 0 ;
            SWriteCard( Message, MsgPos, I, 4 ) ;
            SWriteString( Message, MsgPos, ' HRec:', 0 ) ;
            SWriteCard( Message, MsgPos, HRecord.TokenData[I].HRecNo, 5 ) ;
            SWriteString( Message, MsgPos, ' HIdx:', 0 ) ;
            SWriteCard( Message, MsgPos, ORD(HRecord.TokenData[I].HRecPos), 4 ) ;

	    temp := HRecord.BaseTextPos + HRecord.TokenData[I].TOffset;
	    TRecNo  := temp DIV HyperLength + HRecord.BaseTextRec;
            SWriteString( Message, MsgPos, '  TRec:', 0 ) ;
            SWriteCard( Message, MsgPos, TRecNo, 5 ) ;

            SWriteString( Message, MsgPos, ' TIdx:', 0 ) ;
            TRecIdx := temp MOD HyperLength ;
            SWriteCard( Message, MsgPos, TRecIdx, 4 ) ;

	    temp := HRecord.BaseLogPos + ORD(HRecord.TokenData[I].LOffset);
	    LRecNo  := temp DIV 256 + HRecord.BaseLogRec;
            SWriteString( Message, MsgPos, '  LRec:', 0 ) ;
            SWriteCard( Message, MsgPos, LRecNo, 5 ) ;

            SWriteString( Message, MsgPos, ' LIdx:', 0 ) ;
            LRecIdx := temp MOD 256 ;
            SWriteCard( Message, MsgPos, LRecIdx, 4 ) ;
            WrFileLine( Message ) ;

            IF (ORD(HRecord.TokenData[I].HRecPos) = 0) OR
	       (HRecord.TokenData[I].HRecNo > EndTypeHRec) OR
	       (LRecNo > EndLog) OR (TRecNo > EndTextRec) THEN
		MsgPos := 0 ;
		SWriteString( Message, MsgPos, '** Bad Type pointer for token at Position: ', 0 ) ;
		SWriteInt( Message, MsgPos, I, 0 ) ;
		SWriteString( Message, MsgPos, ' Record: ', 0 ) ;
		SWriteInt( Message, MsgPos, Int, 0 ) ;
		WrFileLine( Message ) ;
		MsgPos := 0 ;
		SWriteString( Message, MsgPos, ' ', 5 ) ;
		WriteScrLn( '** Bad Type pointer for token. **' ) ;
            END ;
	END ;
    END DoTokenWrite ;

PROCEDURE DoStrRecWrFile( string1 : ARRAY OF CHAR ; Card1, Card2 : CARDINAL ;
			  string2 : ARRAY OF CHAR ; Card3 : CARDINAL ) ;
  BEGIN
      MsgPos := 0 ;
      SWriteString( Message, MsgPos, string1, 0 ) ;
      SWriteCard( Message, MsgPos, Card1, 5 ) ;
      SWriteCard( Message, MsgPos, Card2, 5 ) ;
      SWriteString( Message, MsgPos, string2, 0 ) ;
      SWriteCard( Message, MsgPos, Card3, 5 ) ;
      WrFileLine( Message ) ;
  END DoStrRecWrFile ;

PROCEDURE DoScrWrite( string : ARRAY OF CHAR ; Int : INTEGER ) ;
    BEGIN
        MsgPos := 0 ;
        SWriteString( Message, MsgPos, string, 0 ) ;
        SWriteCard( Message, MsgPos, Int, 0 ) ;
        WriteScrLn( Message ) ;
    END DoScrWrite ;

PROCEDURE CheckWordCounts( StartAt, StartIndex, EndRec, EndIndex : CARDINAL );
    VAR
	BytesRead : CARDINAL ;
	StrHRec	: HyperData ;
	StartIdx, EndIdx,
	I, J	: CARDINAL ;
	RefTotalWords, TotWords	: LONGINT ;
    BEGIN
	RefTotalWords := 0 ;
	FOR I := StartAt TO EndRec DO
	    FIO.Seek( DBFile, LONGCARD( I ) * HyperLength ) ;
	    IOCheck ;
	    Lib.Fill( ADR(StrHRec), HyperLength, 0C ) ;
	    BytesRead := FIO.RdBin( DBFile, StrHRec, HyperLength ) ;
	    IOCheck ;
	    IF I = StartAt THEN  StartIdx := StartIndex
	    ELSE StartIdx := 1
	    END ;
	    IF I = EndRec THEN  EndIdx := EndIndex
	    ELSE EndIdx := StrHRec.NoDataPtrsUsed
	    END ;
	    WITH StrHRec DO
		FOR J := StartIdx TO EndIdx DO
		   Lib.Move( ADR( TextData[DataPntr[ J ] ] ), ADR(TotWords), 4 ) ;
		   INC( RefTotalWords, TotWords ) ;
		END ;
	    END ;
	END ;
	IF RefTotalWords <> NoTokensInDB THEN
		MsgPos := 0 ;
		SWriteString( Message, MsgPos, "** Reference total words (", 0 ) ;
		SWriteLongInt( Message, MsgPos, RefTotalWords, 0 ) ;
		SWriteString( Message, MsgPos, ") does not match number words in TDB. **", 0 ) ;
		WrFileLine( Message ) ;
                WriteScrLn( Message ) ;
	END ;
    END CheckWordCounts ;

PROCEDURE DumpStrings ;
    VAR TempStr,TempStr2 : StrAny ;
	TotWords : LONGINT;
	StrPtr	: TDBStrPntr ;
    BEGIN
        WITH HRecord DO
            DoCardWrFile( 'No of pointers used: ', NoDataPtrsUsed ) ;
            FOR I := 1 TO NoDataPtrsUsed DO
		StrPtr := ADR( TextData[ DataPntr[I] ] ) ;
		Len := DataPntr[I-1] - DataPntr[I] - CARDINAL(StrPtr^.TDBStr.PackedLen)
			- 1 (* account for KeyLen byte *) - TSIZE(LONGINT);
		Lib.Move( ADR(StrPtr^.TDBStr.PackedStr[CARDINAL(StrPtr^.TDBStr.PackedLen)]),
			  ADR(TempStr2), Len ) ;
		TempStr2[Len] := 0C;
		BitOps.UnPack( StrPtr^.TDBStr, HTempStr, SortNoBitsPerChar ) ;
                MsgPos := 0 ;
                SWriteCard( Message, MsgPos, I, 4 ) ;
                SWriteCard( Message, MsgPos, DataPntr[I], 5 ) ;
                SWriteCard( Message, MsgPos, (* Len= *) DataPntr[I-1] - DataPntr[I], 4 ) ;
                SWriteLongInt( Message, MsgPos, StrPtr^.TotalWords, 6 ) ;
                SWriteChar( Message, MsgPos, " ", 0 ) ;
                SWriteString( Message, MsgPos, TempStr2, 0 ) ;
                SWriteChar( Message, MsgPos, " ", 2 ) ;
		SortToIntWord( HTempStr, SortName ) ;
                SWriteString( Message, MsgPos, SortName, 0 ) ;
                (* try aligning at column 45 if possible *)
		IF MsgPos > 45 THEN  K := 2
		ELSE K := 46 - MsgPos
		END;
                SWriteChar( Message, MsgPos, " ", K ) ;
                PrintHex( HTempStr, HexStr ) ;
                DoStrWrFile( Message, HexStr) ;
            END ;
            DoIntWrFile( 'Unused space: ',INTEGER(DataPntr[NoDataPtrsUsed])-(INTEGER(NoDataPtrsUsed)+1) * 2 ) ;
        END ;
    END DumpStrings ;

PROCEDURE DumpDataPntr ;
    BEGIN
        WITH HRecord DO
            DoCardWrFile( 'No of pointers used: ', NoDataPtrsUsed ) ;
            FOR I := 1 TO NoDataPtrsUsed DO
                Len := DataPntr[I-1] - DataPntr[I] ;
                Lib.Move( ADR(TextData[DataPntr[I]]), ADR(HTempStr), Len ) ;
                HTempStr[Len] := 0C ;
                MsgPos := 0 ;
                SWriteCard( Message, MsgPos, I, 4 ) ;
                SWriteCard( Message, MsgPos, Len, 5 ) ;
                SWriteString( Message, MsgPos, ' ', 0 ) ;
                NewPrintCode( HTempStr, Len, HexStr ) ;
                DoStrWrFile( Message, HexStr ) ;
                MsgPos := 0 ;
                SWriteString( Message, MsgPos, ' ', 10 ) ;
                NewPrintHex1( HTempStr, Len, HexStr ) ;
                DoStrWrFile( Message, HexStr ) ;
                MsgPos := 0 ;
                SWriteString( Message, MsgPos, ' ', 10 ) ;
                NewPrintHex2( HTempStr, Len, HexStr ) ;
                DoStrWrFile( Message, HexStr ) ;
            END ;
            DoIntWrFile( 'Unused space: ',INTEGER(DataPntr[NoDataPtrsUsed])-(INTEGER(NoDataPtrsUsed)+1) * 2 ) ;
        END ;
    END DumpDataPntr ;

PROCEDURE DumpTypeData ;
    VAR
        Data	: TDBTypeData ;
	PtrLen	: CARDINAL ;
	OldOccur: HOccurData;

    PROCEDURE DumpOccurs ;
	VAR
	   DataPos	: INTEGER ;
	   InRecNo	: INTEGER ;
	   OccurPtr	: POINTER TO HOccurData ;
	BEGIN
	   WITH HRecord DO
	     DataPos := INTEGER( DataPntr[ I ] ) ;
	     SWriteString( Message, MsgPos, ' ', 5 ) ;
	     J := 0 ;
	     InRecNo := InRec ;
	     LOOP
		INC( J ) ;
		IF J > Data.NoOccur THEN  EXIT  END ;
		DEC( DataPos, OccurRecSize ) ;
		IF DataPos < INTEGER( PtrLen ) THEN
		   DataPos := TypeMaxDataPos - OccurRecSize ;
		   INC( InRecNo ) ;
		   IF CARDINAL(InRecNo) <= EndTypeHRec THEN
			SWriteString( Message, MsgPos, " * ", 0 ) ;
			ReadDBRec( InRecNo ) ;
		   ELSE	(* no more recs ??? *)
			WriteScrLn( '** Insuficient Occur items found. **' ) ;
			EXIT ;
		   END ;
		   IF NoDataPtrsUsed > 0 THEN
			PtrLen := 4 + 2 * NoDataPtrsUsed
		   ELSE
			PtrLen := 2
		   END ;
		END ;
		OccurPtr := ADR( TextData[DataPos] ) ;
		SWriteCard( Message, MsgPos, OccurPtr^.TRecNo, 0 ) ;
		SWriteChar( Message, MsgPos, ":", 0 ) ;
		SWriteCard( Message, MsgPos, ORD(OccurPtr^.TRecPos), 0 ) ;
		SWriteChar( Message, MsgPos, " ", 0 ) ;
		IF MsgPos > 132 THEN
		   WrFileLine( Message ) ;
		   MsgPos := 0 ;
		   SWriteString( Message, MsgPos, ' ', 5 ) ;
		END ;
		(* check validity of occur pointers *)
		IF ( (OldOccur.TRecNo < OccurPtr^.TRecNo) OR
		     ((OldOccur.TRecNo = OccurPtr^.TRecNo) AND (OldOccur.TRecPos < OccurPtr^.TRecPos))) AND
		   ( OccurPtr^.TRecNo <= (EndTokenHRec - BeginTokenHRec) ) AND
		   ( ORD( OccurPtr^.TRecPos ) < HNoTokens ) THEN
		   (* OK *)
		ELSE
		   IF MsgPos > 5 THEN  WrFileLine( Message )  END ;
		   MsgPos := 0 ;
		   SWriteString( Message, MsgPos, '** Possible Bad Occur pointer at Position: ', 0 ) ;
		   SWriteInt( Message, MsgPos, DataPos, 0 ) ;
		   SWriteString( Message, MsgPos, ' Record: ', 0 ) ;
		   SWriteInt( Message, MsgPos, InRecNo, 0 ) ;
		   WrFileLine( Message ) ;
		   MsgPos := 0 ;
		   SWriteString( Message, MsgPos, ' ', 5 ) ;
		   WriteScrLn( '** Possible Bad Occur pointers. **' ) ;
		END ;
		OldOccur := OccurPtr^ ;
	     END ;
	     IF MsgPos > 5 THEN  WrFileLine( Message )  END ;
	   END ;
	END DumpOccurs ;

    BEGIN
	WrFileLine( "" ) ;
	MsgPos := 0 ;
        SWriteString( Message, MsgPos, 'Base Type Rec:', 0 ) ;
        SWriteCard( Message, MsgPos, CARDINAL(InRec) - BeginType, 5 ) ;
	SWriteString( Message, MsgPos, '  No of pointers used: ', 0) ;
	SWriteCard( Message, MsgPos, HRecord.NoDataPtrsUsed, 4 ) ;
	IF HRecord.NoDataPtrsUsed > 0 THEN
		SWriteString( Message, MsgPos, ' Prev:', 0) ;
                SWriteCard( Message, MsgPos, HRecord.PrevHRec+BeginType, 5 ) ;
		SWriteString( Message, MsgPos, ' Next:', 0) ;
                SWriteCard( Message, MsgPos, HRecord.NextHRec+BeginType, 5 ) ;
                SWriteString( Message, MsgPos, ' ', 0 ) ;
	END ;
	WrFileLine( Message ) ;
        WITH HRecord DO
	    IF NoDataPtrsUsed > 0 THEN
		PtrLen := 4 + 2 * NoDataPtrsUsed
	    ELSE
		PtrLen := 2
	    END ;
            FOR I := 1 TO NoDataPtrsUsed DO
                Lib.Move( ADR(TextData[DataPntr[I]]), ADR(Data), 255 ) ;
                BitOps.UnPack( Data.PackedWord, HTempStr, SortNoBitsPerChar ) ;
                MsgPos := 0 ;
                SWriteCard( Message, MsgPos, I, 4 ) ;
                SWriteCard( Message, MsgPos, DataPntr[I], 5 ) ;
                SWriteCard( Message, MsgPos, Data.NoOccur, 6 ) ;
                SWriteChar( Message, MsgPos, " ", 0 ) ;
		SortToIntWord( HTempStr, SortName ) ;
                SWriteString( Message, MsgPos, SortName, 0 ) ;
		IF Str.Length(SortName) > 25 THEN  K := 2
		ELSE K := 25 - Str.Length(SortName) + 1
		END;
                SWriteChar( Message, MsgPos, " ", K ) ;
                PrintHex( HTempStr (* was: Data.Word *), HexStr ) ;
                SWriteString( Message, MsgPos, HexStr, 0 ) ;
                OldOccur.TRecNo := 0 ;
                OldOccur.TRecPos := 0C ;
                DumpOccurs ;
            END ;
        END ;
    END DumpTypeData ;

PROCEDURE ShowScrHeader ;
    BEGIN
        WriteScrLn( '' ) ;
        DoScrWrite( '  BeginText: ', BeginText ) ;
        DoScrWrite( ' EndTextRec: ', EndTextRec ) ;
        DoScrWrite( '   BeginStr: ', BeginStr ) ;
        DoScrWrite( '     EndStr: ', EndStr ) ;
        DoScrWrite( 'BeginStrRec: ', BeginStrRec ) ;
        DoScrWrite( '   BeginLog: ', BeginLog ) ;
        DoScrWrite( '     EndLog: ', EndLog ) ;
        DoScrWrite( ' BeginToken: ', BeginTokenHRec ) ;
        DoScrWrite( 'EndTokenRec: ', EndTokenHRec ) ;
        DoScrWrite( '  BeginType: ', BeginType ) ;
        DoScrWrite( ' EndTypeRec: ', EndTypeHRec ) ;
        DoScrWrite( '    NoTypes: ', NoTypes ) ;
	WriteScrLn( 'Enter number < 0 to exit, 0 for header record info, n1:n2 for range.' ) ;
    END ShowScrHeader ;


PROCEDURE BuildDBXlate(): XlateTablePointer;
TYPE
   XRecStringType = RECORD
        CASE : BOOLEAN OF
        TRUE: Level:      CHAR;
              InChr:      CHAR;
              OutLenC:    CHAR;
              OutSeqC:    SequenceType |
        FALSE:
              Str:       ARRAY[0..MaxCharsInSeq+3] OF CHAR
        END
   END;

  VAR
    Ch:        CHAR;
    FirstOne:  XlateEntryPointer;
    DLvl:      CARDINAL;
    XlTbl:     XlateTablePntr;
    result:    XlateTablePointer;

PROCEDURE GetEntry(VAR P: XlateEntryPointer): CARDINAL;
  VAR
    Start:   CARDINAL;
    ActLen:  CARDINAL;
    lvl:     CARDINAL;
    XRec:    POINTER TO XRecStringType;
    found:   BOOLEAN;

BEGIN
   found := FALSE;
   REPEAT
      IF HRecPos >= HyperLength THEN
         INC( HRecNo ) ;
         ReadDBRec( HRecNo );
         HRecPos := 0;
      END;
      IF HRecord.TextData[HRecPos] <> 0C THEN found := TRUE
      ELSE INC(HRecPos) END;
   UNTIL found;
   IF HRecord.TextData[HRecPos] = 376C THEN
      INC(HRecPos,2);
      P := NIL;
      RETURN 0;
   END;
   Start := HRecPos;
   XRec := ADR(HRecord.TextData[HRecPos]);
   INC(HRecPos, Str.Length(XRec^.Str));
   WHILE HRecord.TextData[HRecPos] <> 0C DO INC(HRecPos) END;

   lvl := ORD(XRec^.Level);
   NEW(P);
   WITH P^ DO
      InChar := XRec^.InChr;
      OutLen := ORD(XRec^.OutLenC)-1;
      ActLen := HRecPos-Start-3;
      OutSeq := XRec^.OutSeqC;
      Type := StrResult;
      OutMode := '0';
      Next := NIL;
      Failure := NIL;
   END;
   RETURN lvl;
END GetEntry; (* GetEntry *)

PROCEDURE DoLevel(P, P1: XlateEntryPointer; VAR Q: XlateEntryPointer; GLvl: CARDINAL): CARDINAL;
VAR
    R, S: XlateEntryPointer;
    RLvl: CARDINAL;
BEGIN
  IF GLvl = 1 THEN
    XlTbl^.XlateTableDat[Q^.InChar] := Q
  ELSE
    P^.Next := Q;
    IF P1 <> NIL THEN
      P1^.Next := Q
    END;
  END;
  RLvl := GetEntry(R);
  WHILE (RLvl = 255) OR (RLvl >= GLvl) DO
    IF RLvl = GLvl THEN
      IF GLvl <> 1 THEN
        Q^.Failure := R
      ELSE
        XlTbl^.XlateTableDat[R^.InChar] := R
      END;
      S := NIL;
      Q := R;
      RLvl := GetEntry(R);
    ELSIF RLvl = 255 THEN
      IF GLvl <> 1 THEN
        Q^.Failure := R
      ELSE
        XlTbl^.XlateTableDat[R^.InChar] := R
      END;
      S := Q;
      Q := R;
      RLvl := GetEntry(R);
    ELSE
      RLvl := DoLevel(Q, S, R, RLvl)
    END;
  END;
  Q := R;
  RETURN RLvl
END DoLevel; (* DoLevel *)

BEGIN
  NEW(XlTbl);
  WITH XlTbl^ DO
    FOR Ch := 1C TO 377C DO
      XlateTableDat[Ch] := NIL
    END;
  END;
  DLvl := GetEntry(FirstOne);
  DLvl := DoLevel(NIL, NIL, FirstOne, DLvl);
  NEW(result);
  WITH result^ DO
     FOR Ch := '1' TO '9' DO XlateMode[Ch] := NIL END;
     NEW(XlateMode['0']);
     XlateMode['0']^.Seq[0] := 0C;
     XlateMode['0']^.Table := XlTbl;
  END;
  RETURN result
END BuildDBXlate;

PROCEDURE GetByte(): BYTE;
VAR b:  BYTE;
BEGIN
   IF HRecPos >= HyperLength THEN
      INC( HRecNo ) ;
      ReadDBRec(HRecNo);
      HRecPos := 0;
   END;
   b := BYTE(HRecord.TextData[HRecPos]);
   INC(HRecPos);
   RETURN b;
END GetByte;

PROCEDURE Get2Bytes(VAR Result:ARRAY OF BYTE);
BEGIN
   Result[0] := GetByte();
   Result[1] := GetByte();
END Get2Bytes;

PROCEDURE GetString(VAR StrResult: ARRAY OF CHAR);
VAR i,h: CARDINAL;
    c:   CHAR;
BEGIN
   h := HIGH(StrResult);
   i := 0;
   REPEAT
      c := GetByte();
      IF i <= h THEN StrResult[i] := c END;
      INC(i);
   UNTIL c = 0C;
END GetString;

PROCEDURE GetRefNames;
VAR
   AmtToAlloc:   CARDINAL;
   i:            CARDINAL;
   TRName:       RefsNameData;

PROCEDURE GetRefEntry(VAR Result: ARRAY OF BYTE; VAR NumbGot: CARDINAL);
VAR b: BYTE;
BEGIN
   NumbGot := 0;
   REPEAT
      b := GetByte();
      Result[NumbGot] := b;
      INC(NumbGot);
   UNTIL (NumbGot > 3 (* size of ID + size of Pref*) ) AND (b = BYTE(0C));
END GetRefEntry;

BEGIN
   Get2Bytes(NumbOfRefNames);

   AmtToAlloc := TSIZE(ADDRESS) * (2 + NumbOfRefNames);
   ALLOCATE(RefsNameListPntr,AmtToAlloc);

   NumbOfRefUnits := 0 ;
   ALLOCATE(RefsNameListPntr^[0],3);
   RefsNameListPntr^[0]^.ID := 0;
   RefsNameListPntr^[0]^.Name := '';
   FOR i := 1 TO NumbOfRefNames DO
      GetRefEntry(TRName,AmtToAlloc);
      ALLOCATE(RefsNameListPntr^[i],AmtToAlloc);
      Lib.Move( ADR(TRName), RefsNameListPntr^[i], AmtToAlloc);
      IF RefsNameListPntr^[i]^.Pref = 0C THEN
	 INC( NumbOfRefUnits )
      END ;
   END;
   ALLOCATE(RefsNameListPntr^[NumbOfRefNames+1],4);
   RefsNameListPntr^[NumbOfRefNames+1]^.ID := INTEGER(0);
   RefsNameListPntr^[NumbOfRefNames+1]^.Name[0] := 377C;
   RefsNameListPntr^[NumbOfRefNames+1]^.Name[1] := 0C;
END GetRefNames;

PROCEDURE PrintRefNames ;
    VAR
        TempStr : StrAny ;
    BEGIN
        WrFileLine( '' ) ;
        WrFileLine( 'Reference Names:' ) ;
        WrFileLine( '      ID Pref Name' ) ;
        FOR I := 1 TO NumbOfRefNames DO
            MsgPos := 0 ;
            SWriteCard( Message, MsgPos, I, 4 ) ;
            SWriteInt( Message, MsgPos, RefsNameListPntr^[I]^.ID, 4 ) ;
            SWriteCard( Message, MsgPos, ORD(RefsNameListPntr^[I]^.Pref), 5 ) ;
            SWriteString( Message, MsgPos, ' ', 0 ) ;
            J := 0 ;
            SortToIntWord( RefsNameListPntr^[I]^.Name, SortName ) ;
            SWriteString( TempStr, J, SortName, 25 ) ;
            SWriteChar( TempStr, J, " ", 2 ) ;
            PrintHex( RefsNameListPntr^[I]^.Name, HexStr ) ;
            SWriteString( TempStr, J, HexStr, 0 ) ;
            DoStrWrFile( Message, TempStr ) ;
        END ;
        WrFileLine( '' ) ;
    END PrintRefNames ;

PROCEDURE PrintTypeOfChar ;
   VAR  J : CHAR ;

   PROCEDURE WriteTypeOfChar( Code : AlphaCharType ) ;
      BEGIN
         CASE Code OF
            NullChar :
               SWriteString( Message, MsgPos, ' NullChar', 12 ) |
            Letter :
               SWriteString( Message, MsgPos, ' Letter', 12 ) |
            RetDiac :
               SWriteString( Message, MsgPos, ' RetDiac', 12 ) |
            NonRetDiac :
               SWriteString( Message, MsgPos, ' NonRetDiac', 12 ) |
            IgnBrkStart :
               SWriteString( Message, MsgPos, ' IgnBrkStart', 12 ) |
            IgnBrkEnd :
               SWriteString( Message, MsgPos, ' IgnBrkEnd', 12 ) |
            IgnBrkStEnd :
               SWriteString( Message, MsgPos, ' IgnBrkStEnd', 12 ) |
            RefBrkStart :
               SWriteString( Message, MsgPos, ' RefBrkStart', 12 ) |
            RefBrkEnd :
               SWriteString( Message, MsgPos, ' RefBrkEnd', 12 ) |
            RefBrkStEnd :
               SWriteString( Message, MsgPos, ' RefBrkStEnd', 12 ) |
            ContinuationChar :
               SWriteString( Message, MsgPos, ' ContChar', 12 ) |
            LabelStart :
               SWriteString( Message, MsgPos, ' LabelStart', 12 ) |
            LabelEnd :
               SWriteString( Message, MsgPos, ' LabelEnd', 12 ) |
            LabelStEnd :
               SWriteString( Message, MsgPos, ' LabelStEnd', 12 ) |
            BYUStart :
               SWriteString( Message, MsgPos, ' BYUStart', 12 ) |
            HighKeyChar :
               SWriteString( Message, MsgPos, ' HighKeyChar', 12 ) |
            Counter :
               SWriteString( Message, MsgPos, ' Counter', 12 )
         END ; (* CASE Code OF *)
      END WriteTypeOfChar ;

   BEGIN
      WrFileLine( '[TypeOfChar]' ) ;
      MsgPos := 0 ;
      FOR J := 1C TO 377C DO
	 IF (J < 3C) OR ( TypeOfChar[ J ] <> NullChar ) THEN
	    SWriteCard( Message, MsgPos, ORD(J), 4 ) ;
	    SWriteChar( Message, MsgPos, " ", 0 ) ;
	    PrintHex( J, HexStr ) ;
	    SWriteString( Message, MsgPos, HexStr, 0 ) ;
	    WriteTypeOfChar( TypeOfChar[ J ] ) ;
	    IF MsgPos > 80 THEN
		WrFileLine( Message ) ;
		MsgPos := 0 ;
	    END ;
         END ;
      END ;
      IF MsgPos > 0 THEN      (* last line *)
         WrFileLine( Message ) ;
         MsgPos := 0 ;
      END ;
      WrFileLine( '' ) ;
   END PrintTypeOfChar ;

BEGIN
  IF NOT InitFiles() THEN   HALT   END ;

  DoStrWrFile( ' Input file name: ', InputFileName ) ;
  DoStrWrFile( 'Output file name: ', OutputFileName ) ;
  MakePrintableDate( day, month, year, Message ) ;
  DoStrWrFile( '            Date: ', Message ) ;

  HRecNo := 0 ;
  HRecPos := 0 ;
  HTempStr[0] := 0C ;

  ReadDBRec( HRecNo ) ;  (* first record -- header info *)

   (* now save the header info values *)
   BeginType   := HRecord.TDBHeader.BeginType ;
   BeginLog    := HRecord.TDBHeader.BeginLog ;
   EndLog      := HRecord.TDBHeader.EndLog ;
   BeginTokenHRec:= HRecord.TDBHeader.BeginToken ;
   EndTokenHRec:= HRecord.TDBHeader.EndTokenRec ;
   EndTokenIdx := HRecord.TDBHeader.EndTokenIdx ;
   EndTypeHRec := HRecord.TDBHeader.EndTypeRec ;
   EndTypeIdx  := HRecord.TDBHeader.EndTypeIdx ;
   BeginText   := HRecord.TDBHeader.BeginText ;
   EndTextRec  := HRecord.TDBHeader.EndTextRec ;
   EndTextIdx  := HRecord.TDBHeader.EndTextIdx ;
   NoTypes     := HRecord.TDBHeader.NoTypes ;
   BeginStr    := HRecord.TDBHeader.BeginStr ;
   EndStr      := HRecord.TDBHeader.EndStr ;
   BeginStrRec := HRecord.TDBHeader.BeginStrRec ;
   NoStrRecs   := HRecord.TDBHeader.NoStrRecs ;

   NoTokensInDB := VAL(LONGINT, EndTokenHRec - BeginTokenHRec) * VAL(LONGINT, HNoTokens) +
		      VAL(LONGINT, EndTokenIdx + 1) ;

  (* print the header *)
  WITH HRecord.TDBHeader DO
      MsgPos := 0 ;
      SWriteString( Message, MsgPos, 'Title: "', 0 ) ;
      SWriteString( Message, MsgPos, Title, 0 ) ;
      SWriteString( Message, MsgPos, '"', 0 ) ;
      WrFileLine( Message ) ;
      MsgPos := 0 ;
      SWriteString( Message, MsgPos, 'DB Version: "', 0 ) ;
      SWriteCard( Message, MsgPos, TDBVersion, 0 ) ;
      SWriteString( Message, MsgPos, '"', 0 ) ;
      WrFileLine( Message ) ;
      DoCardWrFile( 'Year:  ', Year ) ;
      DoCardWrFile( 'Month: ', Month ) ;
      DoCardWrFile( 'Day:   ', Day ) ;
      WrFileLine( '' ) ;
      Do2CardWrFile('  BeginText: ', BeginText, EndTextRec - BeginText + 1 ) ;
      DoCardWrFile( ' EndTextRec: ', EndTextRec ) ;
      DoCardWrFile( ' EndTextIdx: ', EndTextIdx ) ;
      WrFileLine( '' ) ;
      Do2CardWrFile('   BeginStr: ', BeginStr, EndStr - BeginStr + 1 ) ;
      DoCardWrFile( '     EndStr: ', EndStr ) ;
      WrFileLine( '' ) ;
      Do2CardWrFile('BeginStrRec: ', BeginStrRec, BeginLog - BeginStrRec ) ;
      DoCardWrFile( '   NoStrRec: ', NoStrRecs ) ;
      WrFileLine( '' ) ;
      Do2CardWrFile('   BeginLog: ', BeginLog, EndLog - BeginLog + 1 ) ;
      DoCardWrFile( '     EndLog: ', EndLog ) ;
      WrFileLine( '' ) ;
      Do2CardWrFile(' BeginToken: ', BeginTokenHRec, EndTokenHRec - BeginTokenHRec + 1 ) ;
      DoCardWrFile( 'EndTokenRec: ', EndTokenHRec ) ;
      DoCardWrFile( 'EndTokenIdx: ', EndTokenIdx ) ;
      WrFileLine( '' ) ;
      Do2CardWrFile('  BeginType: ', BeginType, EndTypeHRec - BeginType + 1 ) ;
      DoCardWrFile( ' EndTypeRec: ', EndTypeHRec ) ;
      DoCardWrFile( ' EndTypeIdx: ', EndTypeIdx ) ;
      DoCardWrFile( '    NoTypes: ', NoTypes ) ;
      MsgPos := 0 ;
      SWriteString( Message, MsgPos, '   NoTokens: ', 0 ) ;
      SWriteLongInt( Message, MsgPos, NoTokensInDB, 0 ) ;
      WrFileLine( Message ) ;
      WrFileLine( '' ) ;
   END ;

   ShowScrHeader ;

      HRecPos :=     PastHeader; (* TSIZE(HyperData,HHeader); *)
      Lib.Move( ADR(HRecord.TextData[HRecPos]), ADR(SimpAlphTable), 256);
      INC(HRecPos,256);
      Lib.Move( ADR(HRecord.TextData[HRecPos]), ADR(TypeOfChar), 255);
      INC(HRecPos,255) ;
 
      Ch := 377C ;
      WHILE (TypeOfChar[Ch] <> Letter) AND (TypeOfChar[Ch] <> RetDiac) DO  DEC( Ch )  END ;
      SortNoBitsPerChar := 4 ;
      WHILE ORD(Ch) >= NoBits[ SortNoBitsPerChar ] DO  INC( SortNoBitsPerChar )  END ;
 
      PrintTypeOfChar ;

    (* now do validity checks on header info. *)
    NoGo := FALSE ;
    IF (BeginText > 0) AND (BeginText <= EndTextRec) THEN
       (* ok *)
    ELSE
       WrFileLine( 'Text record pointers bad' ) ;
       NoGo := TRUE ;
    END ;
    IF (BeginStr > 0) AND (EndTextRec < BeginStr) AND (BeginStr <= EndStr) THEN
       (* ok *)
    ELSE
       WrFileLine( 'String record pointers bad' ) ;
       NoGo := TRUE ;
    END ;
    IF (BeginStrRec > 0) AND (EndStr < BeginStrRec) THEN
       (* ok *)
    ELSE
       WrFileLine( 'String record structure  pointer bad' ) ;
       NoGo := TRUE ;
    END ;
    IF (BeginLog > 0) AND (BeginStrRec < BeginLog) AND (BeginLog <= EndLog) THEN
       (* ok *)
    ELSE
       WrFileLine( 'Log record pointers bad' ) ;
       NoGo := TRUE ;
    END ;
    IF (BeginTokenHRec > 0) AND (EndLog < BeginTokenHRec) AND (BeginTokenHRec <= EndTokenHRec) THEN
       (* ok *)
    ELSE
       WrFileLine( 'Token record pointers bad' ) ;
       NoGo := TRUE ;
    END ;
    IF NoGo THEN
	FIO.Close( DumpFile ) ;
	FIO.Close( DBFile ) ;
	HALT ;
    END ;

    Int2Alp := BuildDBXlate();
    Alp2Int := BuildDBXlate();

    GetRefNames;
    PrintRefNames ;

      WrFileLine( 'List of strings:' ) ;
      ReadDBRec( BeginStrRec ) ;  (* find out the location of each string list *)
      StartAt := BeginStr - 1 ;
      FOR I := 1 TO NoStrRecs DO
          Lib.Move( ADR(HRecord.TextData[(I-1)*TSIZE(StrRecStructType)]), ADR(StrRecStruct),  TSIZE(StrRecStructType) );
          INC( HRecPos, TSIZE(StrRecStructType) );
          WITH StrRecStruct DO
	      IF ORD( StartIndex ) = 1 THEN  INC( StartAt )  END ;
              DoIntWrFile(   'String      ID: ', ID ) ;
              DoStrRecWrFile( '  record start: ', StartAt, ORD(Start),
			      '  start index: ', ORD( StartIndex )  ) ;
              DoStrRecWrFile( '  record   end: ', StartAt + ORD( End ), ORD(End),
			      '  end   index: ', ORD( EndIndex )  ) ;
	      CheckWordCounts( StartAt, ORD(StartIndex), StartAt+ORD(End), ORD(EndIndex) );			
              INC( StartAt, ORD(End) ) ;
          END ;
          WrFileLine( '' ) ;
      END ;

   (* loop for selected DB records *)
   GetInRecNumber( InRec ) ;
   WHILE InRec >= 0 DO
        IF (BeginText <= CARDINAL( InRec )) AND (CARDINAL( InRec ) <= EndTextRec) THEN
            ReadDBRec( InRec ) ;
            DoRecWrite( 'Text Record: ', InRec ) ;
        ELSIF (BeginStr <= CARDINAL( InRec )) AND (CARDINAL( InRec ) <= EndStr) THEN
            ReadDBRec( InRec ) ;
            DoRecWrite( 'String Record: ', InRec ) ;
            DumpStrings ;
        ELSIF (BeginStrRec <= CARDINAL( InRec )) AND (CARDINAL( InRec ) <= BeginLog-1) THEN
            ReadDBRec( InRec ) ;
            DoRecWrite( 'String Record Structure: ', InRec ) ;
        ELSIF (BeginLog <= CARDINAL( InRec )) AND (CARDINAL( InRec ) <= EndLog) THEN
            ReadDBRec( InRec ) ;
            DoLogWrite( 'Log Record: ', InRec ) ;
        ELSIF (BeginTokenHRec <= CARDINAL( InRec )) AND (CARDINAL( InRec ) <= EndTokenHRec) THEN
            ReadDBRec( InRec ) ;
            DoTokenWrite( 'Token Record: ', InRec ) ;
        ELSIF (BeginType <= CARDINAL( InRec )) AND (CARDINAL( InRec ) <= EndTypeHRec) THEN
            ReadDBRec( InRec ) ;
            DoRecWrite( 'Type Record: ', InRec ) ;
            DumpTypeData ;
        ELSIF InRec = 0 THEN
            ShowScrHeader ;
        ELSE
            IF InRec > 0 THEN
                DoIntWrFile( 'Bad record number selected - ', InRec ) ;
                WriteScrLn(  'Bad record number selected.' ) ;
            END ;
        END ;
        INC( InRec ) ;
        IF InRec > EndRec THEN  GetInRecNumber( InRec )  END ;
    END ;
	FIO.Close( DumpFile ) ;
	FIO.Close( DBFile ) ;
END DumpDBS .
