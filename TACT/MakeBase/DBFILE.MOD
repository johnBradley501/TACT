IMPLEMENTATION MODULE DBFile ;

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
(* Date:  Feb. 1, 1988                                                      *)
(* Purpose: deal with writing of most info to Textual Database              *)
(*                                                                          *)
(* History:                                                                 *)
(*  15 Feb 88, Lidio Presutti                                               *)
(*     - added BeginLog and EndLog database file markers                    *)
(*                                                                          *)
(*  16 Aug 88, John Bradley                                                 *)
(*     - changed to support newer compressed form of TDB database           *)
(*--------------------------------------------------------------------------*)

(*V1=Production *)
(*V2=Trace *)

IMPORT Utils, Str, FIO, Lib ;
IMPORT UtilsTwo ;

FROM SYSTEM IMPORT ADR, TSIZE, BYTE ;
FROM STANDARD IMPORT
  (* Vars  *) UpperCharList, LowerCharList ;
FROM HyperDataModel IMPORT
  (* Const *) HyperLength, HyperLengthM1, PastHeader, HNoOccurs, HNoTokens, HNoDataPtrs,
              HNoPDBWords, BaseHTypeLen, ThisTDBVersion, OccurRecSize,
              MaxSpaceForOccursInRec, TypeMaxDataPos,
  (* Types *) HyperData, HOccurData, HyperRType, HCompTokenData, TDBTypeData,
  (* Vars  *) TDBIDModel;
FROM StructuralInfo IMPORT
  (* Const *) StructInfoType, NameFieldLen ;
FROM WordBase IMPORT
  (* Types *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar, SortNoBitsPerChar,
  (* Procs *) FullToSortWord, SortToFullWord ;
FROM XlatUserInput IMPORT
  (* Types *) IgnoreRefPtr, CounterPtr, CounterCharPtr, LabelPtr,
              RefBYUPtr, NamesTypePtr, NamesType, RefPosPtr,
  (* Vars  *) IgnoreBrkList, RefBrkList, CounterCharList, LabelList,
              RefList, BYUList, WordCounterPtr, LineCounterPtr, NamesList,
              NumberNamesInList;
FROM StringIO IMPORT SWriteString, SWriteCard ;
FROM SYSTEM   IMPORT ADDRESS ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM KeyTranslation IMPORT FILEText ; (* m.s. - needed now *)
FROM GlobalDefs IMPORT
  (* Type  *) StrAny, StrAnyPntr, SequenceType,
  (* Const *) MaxCharsInSeq, MKSExtension ;
FROM StartUp IMPORT
  (* vars *) FileData;
FROM SetupFile IMPORT
  (* vars *) DefaultMKSUsed, DefaultMKSFileName ;
FROM Translations IMPORT
  (* Type  *) XlateEntryPointer, XlateTablePointer, XFileType,
  (* Vars  *) Int2Alp, Alp2Int,
  (* Procs *) XClose, XOpenInput, XReadLine ;
FROM TokenDataSource IMPORT
  (* Vars  *) RecordNumber, TokenNumber, TypeNumber, HeadWordHeader,
              TokenListStart, CurrTokenArray, CurrTokenPos, BeginToken,
              VTokenListStart, VCurrTokenArray,
              BeginOccur, BeginType, BeginText, BeginIndex,
              EndTextRec, EndTextIdx, EndTypeRec, EndTypeIdx,
              EndTokenRec, EndTokenIdx, NoTypes, BeginStr, EndStr,
              BeginLog, EndLog, BeginStrRec, NoStrRecs,
  (* Vars  *) InputFileID ;
FROM ResMessages IMPORT
  (* Procs *) MsgString, PutResError ;
FROM BitOps IMPORT Pack ;
(*<Trace IMPORT Trace ; Trace>*)

VAR
   DBfile   : FIO.File ;
   ErrorMsg : StrAny ;
   TDataPos : INTEGER ;  (* was CARDINAL, but need allowances to be neg. *)
   TPtrLen  : CARDINAL ;
   PrevHRec : CARDINAL ;
   NextHRec : CARDINAL ;

   CompressMap : ARRAY [0C..377C] OF CHAR ;
   LastCode    : CHAR ;
   MaxNoBitsUsed : CARDINAL ;
   CompressBuffer : ARRAY[0..(HyperLength*8 DIV 7)] OF CHAR ; (* best compaction to 7 bits *)

TYPE   BitCounts = ARRAY[5..8] OF CARDINAL ;
CONST  NoBits = BitCounts (31, 63, 127, 255 ) ;

(*RES OLD MSG 98
File: %0 - %1.
*)

CONST
   FileErrorRes = (*RES REM INS *) 98 ;
   FileHeaderResource = (*RES REM INS*) 113 ;


PROCEDURE IOCheck ;
VAR trslt:   CARDINAL;
    Msg:     ARRAY[0..60] OF CHAR;
   BEGIN
     trslt := FIO.IOresult();
     IF trslt = 0 THEN RETURN END;

     UtilsTwo.IOErrorMessage( trslt, Msg ) ;
     MsgString( FileData.DataBaseName, 0 ) ;
     MsgString( Msg, 0 ) ;
     PutResError( FileErrorRes ) ;
     XClose( InputFileID ) ;  (* time to stop: clean up first *)
     FIO.Close( DBfile ) ;
     HALT;
   END IOCheck ;

PROCEDURE AddTextToDB( VAR IntLine : ARRAY OF BYTE ; Len : CARDINAL ) ;
   VAR
      L1         : CARDINAL ;
      IntLinePtr : StrAnyPntr ;
   BEGIN
      IF HRecPos+Len >= HyperLength THEN
         L1 := HyperLength - HRecPos ;
         Lib.Move( ADR(IntLine), ADR(HRecord.TextData[HRecPos]), L1) ;
         WriteDBRec ;
         IF Len-L1 > 0 THEN
            IntLinePtr := ADR( IntLine ) ; (* get around strict range check of M2 *)
            Lib.Move( ADR(IntLinePtr^[L1]), ADR(HRecord.TextData), Len-L1) ;
            HRecPos := Len - L1 ;
         END ;
      ELSE
         Lib.Move( ADR(IntLine), ADR(HRecord.TextData[HRecPos]), Len) ;
         INC(HRecPos, Len)
      END;
   END AddTextToDB ;

PROCEDURE WriteDBRec ;
  BEGIN
     IF HRecPos > 0 THEN
        FIO.WrBin( DBfile, HRecord, HyperLength);
        IOCheck ;
        Lib.Fill( ADR(HRecord), HyperLength, 0C ) ;
        INC( HRecNo ) ;
        HRecPos := 0 ;
     END ;
  END WriteDBRec ;

(*----------------------------------------------------------------------------
  Convention for storage of "string/text" type of data:
  - array of cardinal
       +------------------------------------------------------------------+
       |  |  |  |  |                                                   |  |
       +------------------------------------------------------------------+
        ^  ^  ^
        |  |  value is start of first, second, third, ... , 510 th entry.
        |  last position in array.
        number of pointer used.

    overlayed with a text string starting from end of record, inserted to fit
    without overlapping the index positions.

    Length of string[i] = DataPntr[i-1] - DataPntr[i]

    Note: HRecPos -- is used as current text/string index position and not as
          position in HyperRecord.

  --------------------------------------------------------------------------*)

PROCEDURE InitAddPtrDataToDB() ;
  BEGIN
     WriteDBRec ;    (* ensure on a new HyperRec boundary!   *)
     TPtrLen  := 4 ; (* will increment to proper value later >>> was 6 in TP <<<*)
     TDataPos := INTEGER( HyperLength );
     HRecord.DataPntr[0] := HyperLength ;
     HRecPos  := 1 ; (* next position to use *)
  END InitAddPtrDataToDB ;

PROCEDURE AddPtrDataToDB( Data : ARRAY OF BYTE ; (* << changed j.b. (was CHAR) *)
                          Len  : CARDINAL ) ;
   BEGIN
      INC(TPtrLen, 2) ;
      DEC(TDataPos, Len) ;
      IF TDataPos < INTEGER( TPtrLen ) THEN
         (* this data will not fit on current HyperRec *)
         HRecord.NoDataPtrsUsed := HRecPos (* added j.b. >> *) - 1;
         WriteDBRec ;
         HRecord.DataPntr[0] := HyperLength ;
         TPtrLen := 6 ;  (* >>> was 8 in the TP version <<< *)
         TDataPos := HyperLength-Len ;
         (* added j.b. >> *) HRecPos := 1;
      END ;
      HRecord.DataPntr[HRecPos] := CARDINAL( TDataPos ) ;
      Lib.Move( ADR(Data), ADR(HRecord.TextData[CARDINAL(TDataPos)]), Len) ;
      INC(HRecPos) ;
   END AddPtrDataToDB ;

PROCEDURE FinishAddPtrDataToDB() ;
  BEGIN
     HRecord.NoDataPtrsUsed := HRecPos - 1 ;
     WriteDBRec ;
  END FinishAddPtrDataToDB ;

PROCEDURE AddTokenToDB( HHRecNo : CARDINAL ; HHRecPos : CHAR ;
                        TRecNo  : CARDINAL ; TRecPos : CARDINAL ;
                        LRecNo  : CARDINAL ; LRecPos : CHAR ) ;

   BEGIN
      IF HRecPos >= HNoTokens THEN
         WriteDBRec ;
         HRecord.BaseTextRec := TRecNo;
         HRecord.BaseTextPos := TRecPos;
         HRecord.BaseLogRec := LRecNo;
         HRecord.BaseLogPos := ORD(LRecPos);
      END ;
      HRecord.TokenData[HRecPos].HRecNo  := HHRecNo ;
      HRecord.TokenData[HRecPos].HRecPos := HHRecPos ;

      HRecord.TokenData[HRecPos].TOffset :=
                    (TRecNo - HRecord.BaseTextRec) * HyperLength +
                     TRecPos - HRecord.BaseTextPos;
      HRecord.TokenData[HRecPos].LOffset := CHR(
                    (LRecNo - HRecord.BaseLogRec) * 256 (* # Log Records *) +
                     ORD(LRecPos) - HRecord.BaseLogPos) ; (* used as 1 byte number *)
      INC(HRecPos) ;
   END AddTokenToDB ;

PROCEDURE AddOccurToDB( CRecNo, CRecPos : CARDINAL ) ;
   VAR OccurPntr: POINTER TO HOccurData;
   BEGIN
      DEC(TDataPos, OccurRecSize);
      IF (TDataPos < INTEGER( TPtrLen )) AND ((HRecPos > 1) OR (TDataPos < 1)) THEN
         HRecord.NoDataPtrsUsed := HRecPos - 1 ;
         IF HRecPos > 1 THEN  (* pointer values on this record *)
	    HRecord.PrevHRec := PrevHRec ;
	    HRecord.NextHRec := NextHRec ; (* NextHRec is always calculated to proper val *)
	    PrevHRec := HRecNo - BeginType ;
	 END ;
         WriteDBRec ;
	 HRecord.DataPntr[0] := TypeMaxDataPos;
	 HRecPos  := 1 ; (* next position to use *)
         TPtrLen  := 4 ; (* add 2 later in AddTypeDataToDB for correct offset *)
	 TDataPos := INTEGER( TypeMaxDataPos ) - OccurRecSize ;
      END ;
      OccurPntr := ADR(HRecord.TextData[TDataPos]);
      OccurPntr^.TRecNo  := CRecNo ;
      OccurPntr^.TRecPos := CHR(CRecPos) ;
   END AddOccurToDB ;

PROCEDURE InitTypeDataToDB ;
  BEGIN
     WriteDBRec ;    (* ensure on a new HyperRec boundary!   *)
     HRecord.DataPntr[0] := TypeMaxDataPos;
     TPtrLen  := 4 ; (* will increment to proper value later *)
     TDataPos := INTEGER( TypeMaxDataPos );
     HRecPos  := 1 ; (* next position to use *)
     PrevHRec := 0 ;
     NextHRec := 0 ;
  END InitTypeDataToDB ;

PROCEDURE AddTypeDataToDB( Data : HTypeData ) ;
   VAR
	SpaceLeft, SpaceNeed : LONGINT ;
	Len	: CARDINAL ;
	TDBData	: TDBTypeData ;
	FixUpNextHRec : BOOLEAN ;
	BytesRead : CARDINAL ;
   BEGIN
      TDBData.NoOccur := Data.NoOccur ;
      Pack( Data.Word, TDBData.PackedWord, SortNoBitsPerChar ) ;
      Len := CARDINAL( TDBData.PackedWord.PackedLen ) + BaseHTypeLen ;
      INC(TPtrLen, 2) ;
      DEC(TDataPos, Len) ;
      IF TDataPos < INTEGER( TPtrLen ) THEN
         (* this data will not fit on current HyperRec *)
         HRecord.NoDataPtrsUsed := HRecPos - 1 ;
         IF HRecPos > 1 THEN  (* pointer values on this record *)
	    HRecord.PrevHRec := PrevHRec ;
	    HRecord.NextHRec := NextHRec ;
	    PrevHRec := HRecNo - BeginType ;
	    FixUpNextHRec := FALSE ;
	 ELSE
	    FixUpNextHRec := TRUE ;
	 END ;
         WriteDBRec ;
         IF FixUpNextHRec THEN
	    FIO.Seek(  DBfile, HyperLength * LONGCARD(BeginType+PrevHRec));
	    IOCheck ;
	    BytesRead := FIO.RdBin( DBfile, HRecord, HyperLength ) ;
	    IOCheck ;
	    INC( HRecord.NextHRec ) ;
	    FIO.Seek(  DBfile, HyperLength * LONGCARD(BeginType+PrevHRec));
	    IOCheck ;
	    FIO.WrBin( DBfile, HRecord, HyperLength);
	    IOCheck ;
	    (* now reposition to end of file for next record *)
	    FIO.Seek(  DBfile, HyperLength * LONGCARD(HRecNo));
	    IOCheck ;
	    Lib.Fill( ADR(HRecord), HyperLength, 0C ) ;
         END ;
	 HRecord.DataPntr[0] := TypeMaxDataPos ;
         TPtrLen := 6 ;
         TDataPos := TypeMaxDataPos -Len ;
         HRecPos := 1;
      END ;
	(*<Trace
	Trace.TWriteCard(HRecNo-BeginType,5);
	Trace.TWriteCard(HRecPos,5);
	Trace.TWriteCard(TPtrLen,5);
	Trace.TWriteCard(TDataPos,5);
	Trace.TWriteCard(Len,3);
	Trace.TWriteLn ;
	Trace>*)
      SpaceLeft := ((LONGINT(TDataPos) - LONGINT(TPtrLen)) DIV OccurRecSize) * OccurRecSize ;
      SpaceNeed := LONGINT(Data.NoOccur) * OccurRecSize ;
      NextHRec := HRecNo - BeginType + 1 ;
      IF SpaceLeft < SpaceNeed THEN
	 INC(NextHRec, CARDINAL((SpaceNeed - SpaceLeft - 1 (* m.s. - remove 1 to
	                                                 make sure division
	                                                 doesn't fall
	                                                 exactly on boundary *)
	      ) DIV MaxSpaceForOccursInRec) ) ;
      END ;
      HRecord.DataPntr[HRecPos] := CARDINAL( TDataPos ) ;
      Lib.Move( ADR(TDBData), ADR(HRecord.TextData[CARDINAL(TDataPos)]), Len) ;
      INC(HRecPos) ;
   END AddTypeDataToDB ;

PROCEDURE FinishTypeDataToDB() ;
  BEGIN
     HRecord.NoDataPtrsUsed := HRecPos - 1 ;
     IF HRecPos > 1 THEN
	HRecord.PrevHRec := PrevHRec ;
	HRecord.NextHRec := HRecNo - BeginType + 1 ;	(* was 0, non-zero useful in checks *)
     END ;
     WriteDBRec ;
  END FinishTypeDataToDB ;

PROCEDURE WriteXTable( Table : XlateTablePointer ) ;
  TYPE
     RecStringType = RECORD
          CASE : BOOLEAN OF
             TRUE: Level   : CHAR ;
                   InChr   : CHAR ;
                   OutLenC : CHAR ;
                   OutSeqC : SequenceType |
             FALSE:
                   Str     : ARRAY[0..MaxCharsInSeq+3] OF CHAR
          END
     END ;
  VAR
     Ch  : CHAR ;
     Lvl : CARDINAL ;
     i   : CARDINAL ;
     HighCharList : CARDINAL ;

  PROCEDURE PutStr( S : ARRAY OF CHAR ) ;
     VAR
        L   : CARDINAL ;
     BEGIN
        L := Str.Length( S ) ;
        IF HRecPos + L >= HyperLength THEN
           WriteDBRec ;
        END ;
        Lib.Move( ADR(S), ADR(HRecord.TextData[HRecPos]), L ) ;
        INC( HRecPos, L );
        INC( HRecPos )  (* mark str with 0C by moving index *)
     END PutStr ;

  PROCEDURE EqI( Ptr1, Ptr2 : XlateEntryPointer ) : BOOLEAN ;
     BEGIN
	IF (Ptr1 = NIL) OR (Ptr2 = NIL) THEN
	   RETURN FALSE
        ELSE
	    RETURN ( Str.Compare(Ptr1^.OutSeq, Ptr2^.OutSeq) = 0 ) AND
		   ( Ptr1^.Next = Ptr2^.Next ) ;
	END ;
     END EqI ;

  PROCEDURE DoItem( Ptr : XlateEntryPointer ) ;
     VAR
        temp : RecStringType ;
     BEGIN
        WITH Ptr^ DO
           temp.Level := CHR( Lvl ) ;
           temp.InChr := InChar ;
           temp.OutLenC := CHR( OutLen + 1 ) ; (* to avoid 0C, 1 added *)
           temp.OutSeqC := OutSeq ;
           PutStr( temp.Str )
        END ;
     END DoItem ;

  PROCEDURE DoDup( Ptr : XlateEntryPointer ) ;
     VAR
        temp : RecStringType ;
     BEGIN
        WITH Ptr^ DO
           temp.Level := 377C ;
           temp.InChr := InChar ;
           temp.OutLenC := CHR( OutLen + 1 ) ;
           temp.OutSeqC := OutSeq ;
           PutStr( temp.Str )
        END ;
     END DoDup ;

  PROCEDURE DoNext( Ptr : XlateEntryPointer ) ;
     BEGIN
        INC( Lvl ) ;
        WHILE Ptr <> NIL DO
           DoItem( Ptr ) ;
           IF (Ptr^.Failure <> NIL) AND EqI( Ptr, Ptr^.Failure ) THEN
              DoDup( Ptr^.Failure ) ;
              Ptr := Ptr^.Failure ;
           END ;
           IF Ptr^.Next <> NIL THEN
              DoNext( Ptr^.Next )
           END ;
           Ptr := Ptr^.Failure ;
        END ;
        DEC( Lvl )
     END DoNext ;

  BEGIN (* WriteXTable *)
     Lvl := 1 ;
     HighCharList := HIGH(LowerCharList) ;
     WITH Table^.XlateMode['0']^.Table^ DO
        FOR Ch := 1C TO 377C DO
           IF XlateTableDat[Ch] <> NIL THEN
              i := Str.Pos( LowerCharList, Ch ) ;
              IF i <= HighCharList THEN
                 IF NOT EqI( XlateTableDat[Ch], XlateTableDat[UpperCharList[i]] ) THEN
                    DoItem( XlateTableDat[Ch] ) ;
                    IF XlateTableDat[Ch]^.Next <> NIL THEN
                       DoNext( XlateTableDat[Ch]^.Next )
                    END ;
                 END ;
              ELSE
                 DoItem( XlateTableDat[Ch] ) ;
                 i := Str.Pos( UpperCharList, Ch ) ;
                 IF i <= HighCharList THEN
                    IF EqI( XlateTableDat[Ch], XlateTableDat[LowerCharList[i]] ) THEN
                       DoDup( XlateTableDat[LowerCharList[i]] )
                    END
                 END ;
                 IF XlateTableDat[Ch]^.Next <> NIL THEN
                    DoNext( XlateTableDat[Ch]^.Next )
                 END ;
              END ;
           END    (* IF XlateTableDat[Ch] <> NIL THEN *)
        END ;    (* FOR Ch := 1C TO 377C DO *)
     END ;      (* WITH Table^.XlateMode['0']^.Table^ DO ... *)
     PutStr( 376C ) ;
  END WriteXTable ;

PROCEDURE WriteNames ;
  (*-----------------------------------------------------------------------*)
  (* Structure of names in DB file:                                        *)
  (*                                                                       *)
  (*   - at next record position:                                          *)
  (*     Number of Names in the list (CARDINAL)                            *)
  (*   - repeat for each name:                                             *)
  (*     - Name Id (INTEGER)                                               *)
  (*     - Name string (terminated with a 0C)                              *)
  (*                                                                       *)
  (*-----------------------------------------------------------------------*)
  TYPE
     NamesStrType = RECORD
              CASE : BOOLEAN OF
                 TRUE :
                    ID   : INTEGER ; (* < 0 means str, > 0 means numeric *)
                    Pref : CHAR ; (* used as 1 byte cardinal # -- j.b. *)
                    Name : NamesType  |
                 FALSE :
                    Str  : ARRAY[0..NameFieldLen+4] OF CHAR ;
              END ;
           END ;
  VAR
     TempNameList : NamesTypePtr ;
     Temp         : NamesStrType ;
     TempLabelPtr : LabelPtr ;
     TempRefBYUPtr: RefBYUPtr ;
     TempPosPtr   : RefPosPtr ;
     Len          : CARDINAL ;
  BEGIN
     Temp.ID := NumberNamesInList ;
     AddTextToDB( Temp.Str, 2 (* TSIZE(CARDINAL) *) ) ;
     TempNameList := NamesList ;
     WHILE TempNameList <> NIL DO
        WITH TempNameList^ DO
           Temp.Name := Name ;
           Temp.Pref := CHR(Preference) ;
           Len := Str.Length( Name ) ;
           CASE AddrType OF
              CounterType, LineCounterType, WordCounterType:
                 Temp.ID := NameID |
              LabelType:
                 TempLabelPtr := CounterAddr ;
                 IF TempLabelPtr^.Numeric THEN
                    Temp.ID := NameID
                 ELSE
                    Temp.ID := - INTEGER( NameID )
                 END ; |
              ReferenceType, BYUType :
                 TempRefBYUPtr := CounterAddr ;
                 IF TempRefBYUPtr^.Numeric THEN
                    Temp.ID := NameID
                 ELSE
                    Temp.ID := - INTEGER( NameID )
                 END |
              PosType :
                 TempPosPtr := CounterAddr ;
                 IF TempPosPtr^.Numeric THEN
                    Temp.ID := NameID
                 ELSE
                    Temp.ID := - INTEGER( NameID )
                 END |
           ELSE
              ProgramErrorAndHalt('Illegal value in WriteNames');
           END ;
        END ;
        AddTextToDB( Temp.Str, Len+4 (* INTEGER + CHAR + Name + 0C *) ) ;
        TempNameList := TempNameList^.Next ;
     END ;
  END WriteNames ;

PROCEDURE WriteMKSInfo ;  (* m.s. - March 93 - this procedure dumps mks info to
                           header record of tdb for retrieval in USEBASE *)
  VAR
    MKSFileName, InputLine : StrAny ;
    EndCode: ARRAY[0..1] OF CHAR ;
    FileID : XFileType ;
    ErrorMsg, Mode: StrAny ;
    Enough : BOOLEAN ;
    IOResult : CARDINAL ;
  BEGIN
   IF DefaultMKSUsed THEN
      Str.Copy( MKSFileName, DefaultMKSFileName ) ;
   ELSE
      Str.Copy( MKSFileName, FileData.SetupFileName ) ;
   END ;
   Utils.GetXlationType( MKSFileName, Mode ) ;
   IF Mode[0] = 0C THEN
      Str.Copy( Mode, FILEText ) ;
   END ;
   IF NOT XOpenInput( MKSFileName, MKSExtension, Mode, FileID, ErrorMsg ) THEN
      MsgString( MKSFileName, 0 ) ;
      MsgString( ErrorMsg, 0 ) ;
      PutResError( FileHeaderResource ) ;

      XClose( FileID ) ;
      RETURN ;
   END ;
   WHILE XReadLine(FileID,'!',InputLine,Enough,IOResult) DO
      EndCode[0] := 'M';
      EndCode[1] := 'K';
      AddTextToDB( EndCode, 2 );
      AddTextToDB( InputLine, 1 + Str.Length(InputLine));
   END ;
(*   EndCode[0] := 'E' ;   (* m.s. - mark end of mks info in tdb. Needed? *)
   EndCode[1] := 'M' ;
   AddtextToDB( EndCode, 2) ;
*)
   IF IOResult <> UtilsTwo.InsufficientData THEN
     UtilsTwo.IOErrorMessage(IOResult, ErrorMsg) ;
     MsgString( MKSFileName, 0 ) ;
     MsgString( ErrorMsg, 0 ) ;
     PutResError( FileHeaderResource ) ;
   END ;
   XClose(FileID);
END WriteMKSInfo ;

PROCEDURE StartDBFile ;
  VAR
     Ch     : CHAR ;
     EndCode : ARRAY[0..1] OF CHAR ;
  BEGIN
     DBfile := FIO.Create( FileData.DataBaseName );
     IOCheck ;
     Lib.Fill( ADR(HRecord), HyperLength, 0C ) ;
     HRecNo  := 0 ;
     HRecPos := 0 ;
     HRecord.TDBHeader.Year  := Utils.year;
     HRecord.TDBHeader.Month := Utils.month;
     HRecord.TDBHeader.Day   := Utils.day;
     Str.Copy( HRecord.TDBHeader.Title, FileData.DataBaseTitle );
     HRecord.TDBHeader.TDBVersion := ThisTDBVersion;
     HRecPos := PastHeader;
     FOR Ch := 0C TO 377C DO
        HRecord.TextData[HRecPos] := SimpAlphTable[Ch];
        INC( HRecPos );
     END;
     FOR Ch := 1C TO 377C DO
        HRecord.TextData[HRecPos] := CHAR( TypeOfChar[Ch] ) ;
        INC( HRecPos );
     END;
     WriteXTable( Int2Alp ) ;
     WriteXTable( Alp2Int ) ;
     WriteNames ;

     IF FileData.StartingRef[0] <> 0C THEN
        EndCode[0] := 'R';
        EndCode[1] := 'F';
        AddTextToDB( EndCode, 2 );
        AddTextToDB( FileData.StartingRef, 1 + Str.Length(FileData.StartingRef));
     END;

     WriteMKSInfo ;             (* m.s. - write mks info to tdb for access in usebase *)
     EndCode[0] := 'E' ;
     EndCode[1] := 'N' ;
     AddTextToDB( EndCode, 2 ) ;
     WriteDBRec ;
  END StartDBFile ;

PROCEDURE FinishDBFile ;
  VAR
     BytesRead : CARDINAL ;
  BEGIN
     IF HRecPos > 0 THEN
        WriteDBRec
     END ;

     FIO.Seek( DBfile, 0);
     IOCheck ;
     BytesRead := FIO.RdBin(DBfile, HRecord, HyperLength);
     IOCheck ;
     WITH HRecord DO
        TDBHeader.BeginType   := BeginType ;
        TDBHeader.BeginLog    := BeginLog ;
        TDBHeader.EndLog      := EndLog ;
        TDBHeader.BeginToken  := BeginToken ;
        TDBHeader.EndTokenRec := EndTokenRec ;
        TDBHeader.EndTokenIdx := EndTokenIdx ;
        TDBHeader.EndTypeRec  := EndTypeRec ;
        TDBHeader.EndTypeIdx  := EndTypeIdx ;
        TDBHeader.BeginText   := BeginText ;
        TDBHeader.EndTextRec  := EndTextRec ;
        TDBHeader.EndTextIdx  := EndTextIdx ;
        TDBHeader.NoTypes     := NoTypes ;
        TDBHeader.BeginStr    := BeginStr ;
        TDBHeader.EndStr      := EndStr ;
        TDBHeader.BeginStrRec := BeginStrRec ;
        TDBHeader.NoStrRecs   := NoStrRecs ;
        TDBHeader.TDBID       := TDBIDModel;
     END ;
     HRecPos := HyperLength ; (* force a write of record *)

     FIO.Seek( DBfile, 0);
     IOCheck ;
     WriteDBRec ;
     FIO.Close( DBfile ) ;
     IOCheck ;
  END FinishDBFile ;

BEGIN
   Lib.Fill( ADR(HRecord), HyperLength, 0C ) ;
   HRecNo  := 0 ;
   HRecPos := 0 ;

   Lib.Fill( ADR(CompressMap), SIZE(CompressMap), 0C ) ;
   LastCode := 0C ;
   MaxNoBitsUsed := 5 ;		(* assume best compaction to 5 bits *)
END DBFile .
