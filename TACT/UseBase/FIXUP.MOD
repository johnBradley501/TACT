MODULE FixUp ;

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

FROM GlobalDefs IMPORT
  (* Type  *) SequenceType, StrAny, FileNameType,
  (* Const *) MaxCharsInSeq, NumbXlateSeq, MaxStringLen, MaxFileNameLength ;

FROM HyperDataModel IMPORT
  (* Const *) HyperLength, PastHeader, HNoOccurs, HNoTokens, HNoDataPtrs,
              BaseHTypeLen, HyperLengthM1, OccurRecSize,
	      MaxSpaceForOccursInRec, TypeMaxDataPos,
  (* Types *) HyperData, HTypePntr, HyperRType, HTypeData, HOccurData,
              HTokenData, HLogDataType, HCompTokenData, TDBTypeData, TDBStrPntr;

FROM Utils IMPORT
 (* proc *) StandardizeFileName ;

VAR
   InputFileName  : FileNameType ;
   DBFile         : FIO.File ;
   NoGo         : BOOLEAN ;
   HRecord      : HyperData ;
   HRecNo,
   OldHRecNo    : CARDINAL ;

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

PROCEDURE WriteScrLn( Text : ARRAY OF CHAR ) ;
    BEGIN
        IO.WrStr( Text ) ;
        IO.WrLn ;
    END WriteScrLn ;

PROCEDURE BadFileName( Name : ARRAY OF CHAR ) ;
  BEGIN
     IO.WrStr('Invalid file name: ' ) ;
     IO.WrStr(Name ) ;
     IO.WrLn;
     HALT ;
  END BadFileName ;

PROCEDURE IOCheck ;
   BEGIN
     IF FIO.IOresult() <> 0 THEN
        IO.WrStr('File error - ') ;
        IO.WrStr( InputFileName ) ;
        IO.WrLn;
        FIO.Close( DBFile ) ;
        HALT ;
     END ;
   END IOCheck ;

PROCEDURE InitFiles() : BOOLEAN ;
  PROCEDURE DoOpens ;
     BEGIN
          IF NOT StandardizeFileName( InputFileName, '.TDB' ) THEN
             BadFileName( InputFileName ) ;
          END ;
          DBFile := FIO.Open( InputFileName ) ;
          IOCheck ;
     END DoOpens ;
  BEGIN
     CASE Lib.ParamCount() OF
       0 :
          WriteScrLn( 'Command Syntax:  Fixup <infile>' ) ;
          RETURN FALSE ; |
       1 :
          Lib.ParamStr( InputFileName, 1 ) ;
          DoOpens ;
          RETURN TRUE ; |
      ELSE
          WriteScrLn( 'Invalid number of arguments given.' ) ;
          WriteScrLn( '' ) ;
          WriteScrLn( 'Command Syntax:  FixUp <infile>' ) ;
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
  END ReadDBRec ;

PROCEDURE WriteDBRec( RecNo : INTEGER ) ;
  VAR
     BytesRead : CARDINAL ;
  BEGIN
     FIO.Seek( DBFile, LONGCARD( RecNo ) * HyperLength ) ;
     IOCheck ;
     FIO.WrBin( DBFile, HRecord, HyperLength ) ;
     IOCheck ;
END WriteDBRec ;

PROCEDURE DoStrWrFile(  Label, string : ARRAY OF CHAR ) ;
  BEGIN
      IO.WrStr(Label) ;
      IO.WrStr(string) ;
      IO.WrLn ;
  END DoStrWrFile ;

PROCEDURE DoCardWrFile( string : ARRAY OF CHAR ; Card : CARDINAL ) ;
  BEGIN
      IO.WrStr(string) ;
      IO.WrCard(Card, 5) ;
      IO.WrLn ;
  END DoCardWrFile ;

PROCEDURE Do2CardWrFile( string : ARRAY OF CHAR ; Card1, Card2 : CARDINAL ) ;
  BEGIN
      IO.WrStr(string) ;
      IO.WrCard(Card1, 5) ;
      IO.WrCard(Card2, 5) ;
      IO.WrLn ;
  END Do2CardWrFile ;

PROCEDURE DoIntWrFile(  string : ARRAY OF CHAR ; Int : INTEGER ) ;
  BEGIN
      IO.WrStr(string) ;
      IO.WrInt(Int, 5) ;
      IO.WrLn ;
  END DoIntWrFile ;

BEGIN
  IF NOT InitFiles() THEN   HALT   END ;

  DoStrWrFile( ' TDB file name: ', InputFileName ) ;

  HRecNo := 0 ;

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

  (* print the header *)
  WITH HRecord.TDBHeader DO
      DoStrWrFile( 'Title: ',Title);
      Do2CardWrFile('  BeginType: ', BeginType, EndTypeHRec - BeginType + 1 ) ;
      DoCardWrFile( ' EndTypeRec: ', EndTypeHRec ) ;
      DoCardWrFile( ' EndTypeIdx: ', EndTypeIdx ) ;
      DoCardWrFile( '    NoTypes: ', NoTypes ) ;
   END ;
   HRecNo := BeginType;
   OldHRecNo := 0;
   WHILE HRecNo <= EndTypeHRec DO
        ReadDBRec( HRecNo );
      	IF HRecord.NoDataPtrsUsed = 0 THEN
           IF HRecNo = BeginType THEN
           ELSE
              ReadDBRec(OldHRecNo);
              INC(HRecord.NextHRec);
              IO.WrStr('Fixing up Type Page; ');
              IO.WrCard(OldHRecNo, 0);
              IO.WrLn;
              WriteDBRec(OldHRecNo);
           END;
        ELSE
           OldHRecNo := HRecNo;
        END;
        HRecNo := HRecord.NextHRec + BeginType;
   END;
   FIO.Close( DBFile ) ;
END FixUp .
