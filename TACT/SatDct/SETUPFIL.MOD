IMPLEMENTATION MODULE SetupFile ;

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

FROM KeyTranslation IMPORT FILEText;
FROM AlphaPanel IMPORT
  (* const *) NoAlphaLines, NoRetDiLines, NoNonDiLines,
  (* vars  *) AlphaInfo;
FROM Lists    IMPORT GetData, MoveDown, CopyListPointer, SetToTop, AddBelow,
              SetToLast, ListPointer, FreeListPointer ;
FROM SpecialCharacters IMPORT
  (* vars  *) SCList,
  (* Procs *) IsSCDataEmpty, NewSCData, InitSCList, DeleteSCList,
              SpecialCharType, SpecialCharDataPntr;
FROM StructuralInfo IMPORT
  (* vars  *) StructList,
  (* type  *) StructInfoType, StructInfoDataType, StructInfoDataPntr,
  (* proc  *) NewStructData, IsStructDataEmpty, InitStructList, DeleteStructList ;
FROM StringIO IMPORT SWriteString, SWriteCard ;
FROM SYSTEM   IMPORT ADDRESS ;
FROM Str      IMPORT Copy, Compare, Slice, Length, Append, StrToCard, Delete;
FROM Utils    IMPORT
  (* Procs  *) Exist, StandardizeFileName, GetXlationType, TrimBlanks,
               FindFileInList,
  (* Vars   *) StandardSearchList ;
FROM UtilsTwo IMPORT IOErrorMessage, InsufficientData ;
FROM GlobalDefs IMPORT StrAny, MKSExtension ;
FROM StartUp IMPORT FileData;
FROM ErrorBase  IMPORT ProgramErrorAndHalt ;
FROM ResMessages IMPORT
  (* proc *) MsgString, MsgCard, MsgInt, MsgLongInt, GetResMessage,
             PutResError, PutResWarning, PutResMessage,
             ResAskUser;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) ReleaseCollection;
FROM Translations IMPORT XClose, XOpenInput, XFileType, XReadLine,
              XOpenOutput, XWriteLine ;


   (* The following Resource is used more than once, hence it's number
      is stored in a CONST for use in various places below *)

         (*RES OLD MSG 113
         File %0: %1.
         *)

   CONST
        FileHeaderResource = (*RES REM INS*) 113 ;
        (* m.s. - moved to .def DefaultMKSFileName = 'DEFAULT.MKS' ; *)
   TYPE
      RecordType = (AlphaRecType, RetDiRecType, NonDiRecType, TitleRecType,
                    ContRecType, WordSepRecType, IgnBrkRecType, RefBrkRecType,
                    WordCntRecType, LineCntRecType, RefRecType, LabelRecType,
                    CounterRecType, BYURecType, RefTemplateType, RefPosType, 
                    BadType );

VAR
   SCmdName            : ARRAY[MIN(RecordType)..MAX(RecordType)] OF ARRAY[0..25] OF CHAR;
   SpCharToRecType     : ARRAY[MIN(SpecialCharType)..MAX(SpecialCharType)] OF RecordType ;
   StructInfoToRecType : ARRAY[MIN(StructInfoType)..MAX(StructInfoType)] OF RecordType ;
   GotSCmdNames : BOOLEAN;
   SupText      : ARRAY [0..15] OF CHAR;
   NoSupText    : ARRAY [0..15] OF CHAR;
   WordSep      : ARRAY [0..15] OF CHAR;
   NoWordSep    : ARRAY [0..15] OF CHAR;
   Numeric      : ARRAY [0..15] OF CHAR;
   NonNumeric   : ARRAY [0..15] OF CHAR;
   DefaultMode  : ARRAY [0..8] OF CHAR;
   TempList     : ListPointer ;
   DataPtr      : ADDRESS ;
   SCData       : SpecialCharDataPntr ;
   StructData   : StructInfoDataPntr ;
   Mode         : StrAny ; (* used for in XOpen/XClose translation selection *)
   InitialSetupDone : BOOLEAN;


PROCEDURE GetSCmdNames;

VAR
   ResC:    ResCollectionType;
   dummy:   BOOLEAN;
   i:       RecordType;

(*RES OLD DTA 7
'[Alpha]' '[DiacRet]' '[DiacNon]' '[Title]' '[Continuation]' '[WordSepSeq]'
'[IgnoreBracket]' '[ReferenceBracket]' '[WordCounter]' '[LineCounter]'
'[Reference]' '[Label]' '[Counter]' '[BYU]' '[RefTemplate]' '[RefPosType]'
'!Illegal!' 'SupText' 'NoSupText' 'WordSep' 'NoWordSep'
'Numeric' 'NonNumeric'
*)
BEGIN
   GetDataArray( (*RES REM INS*) 7, ResC);
   FOR i := MIN(RecordType) TO MAX(RecordType) DO
      dummy := GetNextDataArrayStringItem(ResC,SCmdName[i]);
   END;

   dummy := GetNextDataArrayStringItem(ResC,SupText);
   dummy := GetNextDataArrayStringItem(ResC,NoSupText);
   dummy := GetNextDataArrayStringItem(ResC,WordSep);
   dummy := GetNextDataArrayStringItem(ResC,NoWordSep);
   dummy := GetNextDataArrayStringItem(ResC,Numeric);
   dummy := GetNextDataArrayStringItem(ResC,NonNumeric);
   Copy( DefaultMode, FILEText );

   ReleaseCollection(ResC);

   SpCharToRecType[NoSCType]        := BadType ;
   SpCharToRecType[EmptySCType]     := BadType ;
   SpCharToRecType[IgnoreSCType]    := IgnBrkRecType ;
   SpCharToRecType[ReferenceSCType] := RefBrkRecType ;
   SpCharToRecType[WordSepSCType]   := WordSepRecType ;

   StructInfoToRecType[NoType]          := BadType ;
   StructInfoToRecType[EmptyType]       := BadType ;
   StructInfoToRecType[WordCounterType] := WordCntRecType ;
   StructInfoToRecType[LineCounterType] := LineCntRecType ;
   StructInfoToRecType[ReferenceType]   := RefRecType ;
   StructInfoToRecType[LabelType]       := LabelRecType ;
   StructInfoToRecType[CounterType]     := CounterRecType ;
   StructInfoToRecType[BYUType]         := BYURecType ;
   StructInfoToRecType[PosType]         := RefPosType ;

   GotSCmdNames := TRUE;
END GetSCmdNames;

PROCEDURE FindCmdType(Given: ARRAY OF CHAR; VAR Result: RecordType);
VAR  i:  RecordType;
BEGIN
   FOR i := MIN(RecordType) TO RefPosType DO
     IF Compare(Given, SCmdName[i] ) = 0 THEN
        Result := i;
       RETURN
     END
   END;
   Result := BadType;
END FindCmdType;

PROCEDURE ReadSetupFile(FileName: ARRAY OF CHAR): BOOLEAN;

   VAR
      Message        : StrAny ;
      MsgPos         : CARDINAL ;
      IOResult       : CARDINAL ;
      FileID         : XFileType ;
      Enough         : BOOLEAN ;
      ErrorMsg       : StrAny ;
      InputLine      : StrAny ;
      MaxRecords     : CARDINAL;
      NoFound        : CARDINAL;
      NumbSeq        : CARDINAL;
      ActualLength   : CARDINAL;
      EnoughData     : BOOLEAN ;
      MustBeHeader   : BOOLEAN;
      OK             : BOOLEAN;
      Dummy          : BOOLEAN ;
      DataType       : RecordType;

   PROCEDURE CheckSuppressText( Loc : CARDINAL ) : BOOLEAN ;
      VAR  TempStr  :  ARRAY[0..9] OF CHAR ;
      BEGIN
         Slice( TempStr, InputLine, Loc, 10 ) ;
         TrimBlanks( TempStr, TempStr ) ;
         IF Compare( TempStr, SupText ) = 0 THEN
            RETURN TRUE
         ELSIF Compare( TempStr, NoSupText ) = 0 THEN
            RETURN FALSE
         ELSE

            (*RES OLD MSG 114
            The option "%0" for SuppressText in  Markup File is invalid.
            *)

            MsgString( TempStr, 0 ) ;
            PutResError( (*RES REM INS*) 114 ) ;
            RETURN TRUE ;
         END ;
      END CheckSuppressText ;

   PROCEDURE CheckWordSep( Loc : CARDINAL ) : BOOLEAN ;
      VAR  TempStr  :  ARRAY[0..9] OF CHAR ;
      BEGIN
         Slice( TempStr, InputLine, Loc, 10 ) ;
         TrimBlanks( TempStr, TempStr ) ;
         IF Compare( TempStr, WordSep ) = 0 THEN
            RETURN TRUE
         ELSIF Compare( TempStr, NoWordSep ) = 0 THEN
            RETURN FALSE
         ELSE
            (*RES OLD MSG 115
            The option "%0" for WordSeparator in Markup file is invalid.
            *)

            MsgString( TempStr, 0 ) ;
            PutResError( (*RES REM INS*) 115 ) ;
            RETURN TRUE ;
         END ;
      END CheckWordSep ;

   PROCEDURE CheckNumeric( Loc : CARDINAL ) : BOOLEAN ;
      VAR  TempStr  :  ARRAY[0..9] OF CHAR ;
      BEGIN
         Slice( TempStr, InputLine, Loc, 10 ) ;
         TrimBlanks( TempStr, TempStr ) ;
         IF Compare( TempStr, Numeric ) = 0 THEN
            RETURN TRUE
         ELSIF Compare( TempStr, NonNumeric ) = 0 THEN
            RETURN FALSE
         ELSE
            (*RES OLD MSG 116
            The option "%0" for Numeric in Markup file is invalid.
            *)

            MsgString( TempStr, 0 ) ;
            PutResError( (*RES REM INS*) 116 ) ;
            RETURN TRUE ;
         END ;
      END CheckNumeric ;

   PROCEDURE GetString(     Loc : CARDINAL ;
                            Len : CARDINAL ;
                        VAR Str : ARRAY OF CHAR ) ;
      BEGIN
         Slice( Str, InputLine, Loc, Len ) ;
         TrimBlanks( Str, Str ) ;
      END GetString ;

   PROCEDURE GetCard( Loc : CARDINAL ) : CARDINAL ;
      VAR
         TempStr  :  ARRAY[0..9] OF CHAR ;
         Number   :  CARDINAL ;
         Done     :  BOOLEAN ;
      BEGIN
         Slice( TempStr, InputLine, Loc, 5 ) ;
         Number := 0;
         WHILE TempStr[Number] = ' ' DO INC(Number) END;
         IF Number <> 0 THEN Delete(TempStr,0,Number) END;
         Number := CARDINAL(StrToCard( TempStr, 10, Done )) ;
         IF NOT Done THEN
            (*RES OLD MSG 117
            The number "%0" in Markup file is invalid.
            *)

            MsgString( TempStr, 0 ) ;
            PutResError( (*RES REM INS*) 117 ) ;
            RETURN 0
         ELSE
            RETURN Number ;
         END ;
      END GetCard ;

   PROCEDURE GetBracket(     Loc     : CARDINAL;
                         VAR Bracket : ARRAY OF CHAR ) ;
      BEGIN
         Slice( Bracket, InputLine, Loc, 8 ) ;
         TrimBlanks( Bracket, Bracket ) ;
      END GetBracket ;

   PROCEDURE ParseSCBrackets ;
      BEGIN
         WITH SCData^ DO
            GetBracket( 0, OpenBracket ) ;
            GetBracket( 8, CloseBracket ) ;
            SuppressText := CheckSuppressText( 16 ) ;
            WordSep      := CheckWordSep( 26 ) ;
         END ;
      END ParseSCBrackets ;

   PROCEDURE AddStructEntry ;
      BEGIN
         NewStructData( DataPtr ) ;
         AddBelow( StructList, DataPtr ) ;
         Dummy := MoveDown( StructList ) ;
         StructData := DataPtr ;
      END AddStructEntry ;

   PROCEDURE FindStructRec( TypeToFind : StructInfoType ) ;
      BEGIN
         SetToTop( StructList ) ;
         WHILE MoveDown( StructList ) DO
            GetData( StructList, DataPtr ) ;
            StructData := DataPtr ;
            IF StructData^.TypeOfStructInfo = TypeToFind THEN
               SetToLast( StructList ) ;  (* for next record if any *)
               RETURN ; (* found it! *)
            END ;
         END ;
         ProgramErrorAndHalt( 'unable to find WordCounter or LineCounter structure record.');
      END FindStructRec ;

   BEGIN
      IF NOT GotSCmdNames THEN GetSCmdNames END;
      GetXlationType( FileName, Mode ) ;
      IF Mode[0] = 0C THEN
         Copy( Mode, DefaultMode  ) ;
      END ;
      IF NOT XOpenInput( FileName, MKSExtension, Mode, FileID, ErrorMsg ) THEN
         MsgString( FileName, 0 ) ;
         MsgString( ErrorMsg, 0 ) ;
         PutResError( FileHeaderResource ) ;

         XClose( FileID ) ;
         RETURN FALSE ;
      END ;
      DeleteSCList() ;      (* get rid of anything previously set *)
      InitSCList() ;
      DeleteStructList() ;  (* get rid of anything previously set *)
      InitStructList() ;
      MustBeHeader := TRUE;
      OK := TRUE;
      WHILE XReadLine(FileID,'!',InputLine,Enough,IOResult) AND OK DO
         IF InputLine[0] = 0C THEN
            (* Do nothing here - ignore it *)
         ELSIF InputLine[0] <> ' ' THEN
            FindCmdType(InputLine,DataType);
            CASE DataType OF
            AlphaRecType :
               MaxRecords := NoAlphaLines ;
               FOR NoFound := 1 TO NoAlphaLines DO
                   AlphaInfo.AlphaString[NoFound] := ''
               END;
          | RetDiRecType :
               MaxRecords := NoRetDiLines ;
               FOR NoFound := 1 TO NoRetDiLines DO
                   AlphaInfo.RetDiacStr[NoFound] := ''
               END;
          | NonDiRecType :
               MaxRecords := NoNonDiLines ;
               FOR NoFound := 1 TO NoNonDiLines DO
                   AlphaInfo.NonDiacStr[NoFound] := ''
               END;
          | TitleRecType :
               MaxRecords := 1 ;
          | ContRecType :
               MaxRecords := 1 ;
          | WordSepRecType :
               MaxRecords := 1 ;
               NewSCData( DataPtr ) ;
               AddBelow( SCList, DataPtr ) ;
               Dummy := MoveDown( SCList ) ;
               SCData := DataPtr ;
               SCData^.TypeOfSpecialChar := WordSepSCType ;
          | IgnBrkRecType :
               MaxRecords := 1 ;
               NewSCData( DataPtr ) ;
               AddBelow( SCList, DataPtr ) ;
               Dummy := MoveDown( SCList ) ;
               SCData := DataPtr ;
               SCData^.TypeOfSpecialChar := IgnoreSCType ;
          | RefBrkRecType :
               MaxRecords := 1 ;
               NewSCData( DataPtr ) ;
               AddBelow( SCList, DataPtr ) ;
               Dummy := MoveDown( SCList ) ;
               SCData := DataPtr ;
               SCData^.TypeOfSpecialChar := ReferenceSCType ;
          | WordCntRecType :
               MaxRecords := 2 ;
               FindStructRec( WordCounterType ) ;
          | LineCntRecType :
               MaxRecords := 2 ;
               FindStructRec( LineCounterType ) ;
          | RefRecType :
               MaxRecords := 2 ;
               AddStructEntry ;
               StructData^.TypeOfStructInfo := ReferenceType ;
          | LabelRecType :
               MaxRecords := 2 ;
               AddStructEntry ;
               StructData^.TypeOfStructInfo := LabelType ;
          | CounterRecType :
               MaxRecords := 3 ;
               AddStructEntry ;
               StructData^.TypeOfStructInfo := CounterType ;
          | BYURecType :
               MaxRecords := 2 ;
               AddStructEntry ;
               StructData^.TypeOfStructInfo := BYUType ;
          | RefTemplateType :
               MaxRecords := 1 ;
          | RefPosType :
               MaxRecords := 2 ;
               AddStructEntry ;
               StructData^.TypeOfStructInfo := PosType ;
            ELSE
               (*RES OLD MSG 118
               The option "%0" in Markup file "%1" is invalid.
               *)
               MsgString( InputLine, 0 ) ;
               MsgString( FileName, 0 ) ;
               PutResError( (*RES REM INS*) 118 ) ;
               OK := FALSE;
            END;
            NoFound := 0 ;
            MustBeHeader := FALSE;
         ELSE
            IF MustBeHeader THEN
               (* Note second use of same Message Resource!! *)
               MsgString( FileName, 0 ) ;
               PutResError( (*RES REM INS*) 118 ) ;
               OK := FALSE;
            ELSE
               IF Length(InputLine) > 2 THEN
                  Delete(InputLine, 0, 2) ;  (* get rid of leading 2 spaces *)
                  INC( NoFound ) ;
                  CASE DataType OF
                     AlphaRecType:   AlphaInfo.AlphaString[NoFound] := InputLine     |
                     RetDiRecType:   AlphaInfo.RetDiacStr[NoFound]  := InputLine     |
                     NonDiRecType:   AlphaInfo.NonDiacStr[NoFound]  := InputLine     |
                     TitleRecType:  (* Copy( FileData.DataBaseTitle, InputLine) *)    |
                     RefTemplateType: (* Copy( FileData.StartingRef, InputLine ) *)     |
                     ContRecType:    Copy( AlphaInfo.ContinuationSeq, InputLine)  |
                     WordSepRecType: Copy( SCData^.WordSepSeq, InputLine ) |
                     IgnBrkRecType:  ParseSCBrackets                       |
                     RefBrkRecType:  ParseSCBrackets                       |
                     WordCntRecType..BYURecType, RefPosType:
                        IF NoFound = 1 THEN
                           Copy( StructData^.Names, InputLine ) ;
                        ELSE (* its the second or third record *)
                           WITH StructData^ DO
                              CASE DataType OF
                                 WordCntRecType:
                                    WordCounterInit := GetCard( 0 ) ; |
                                 LineCntRecType:
                                    LineCounterInit := GetCard( 0 ) ;
                                    GetString( 6, 20, LineCounterReset )  |
                                 RefRecType:
                                    GetString( 0, 20, RefRefID ) ;
                                    RefNumeric := CheckNumeric( 21 ) ;
                                    RefNoCharsKeep := GetCard( 32 )   |
                                 LabelRecType:
                                    GetBracket( 0, LabelOpenBracket ) ;
                                    GetBracket( 8, LabelCloseBracket ) ;
                                    LabelSuppressText := CheckSuppressText(16);
                                    LabelWordSep := CheckWordSep( 26 ) ;
                                    LabelNumeric := CheckNumeric( 36 ) ;
                                    LabelNoCharsKeep := GetCard( 46 )   |
                                 CounterRecType:
                                    IF NoFound = 2 THEN
                                       CounterInit := GetCard( 0 ) ;
                                       CounterSuppressText := CheckSuppressText(6);
                                       GetString( 16, 80, CounterRefID ) ;
                                    ELSE (* only one with 3 records! *)
                                       GetString( 0, 80, CounterReset ) ;
                                    END   |
                                 BYURecType:
                                    GetString( 0, 1, BYURefID ) ;
                                    BYUNumeric := CheckNumeric( 2 ) ;
                                    BYUNoCharsKeep := GetCard( 12 ) |
                                 RefPosType:
                                    PosStart := GetCard( 0 ) ;
                                    PosEnd := GetCard( 5 ) ;
                                    PosNumeric := CheckNumeric(10);
                              END ; (* CASE DataType OF *)
                           END ; (* WITH StructData^ DO *)
                        END ; (* IF NoFound = 1 THEN *)
                  END; (* CASE DataType OF *)
                  IF NoFound = MaxRecords THEN
                     MustBeHeader := TRUE
                  END;
               END;  (* IF Length(InputLine) > 2 THEN *)
            END;  (* IF MustBeHeader THEN ... *)
         END;  (* IF InputLine[0] <> ' ' THEN ... *)
      END;   (* WHILE ( NOT Eof(FileId)) AND OK DO *)
      SetToTop( SCList ) ;
      SetToTop( StructList ) ;

      IF IOResult <> InsufficientData THEN
         IOErrorMessage(IOResult, ErrorMsg) ;
         MsgString( FileName, 0 ) ;
         MsgString( ErrorMsg, 0 ) ;
         PutResError( FileHeaderResource ) ;
      END ;
      XClose(FileID);
      InitialSetupDone := TRUE;
      RETURN OK ;
   END ReadSetupFile ;

PROCEDURE WriteSetupFile(DoAsSetup: BOOLEAN; Confirm: BOOLEAN) ;
   VAR
      Message        : StrAny ;
      MsgPos         : CARDINAL ;
      IOResult       : CARDINAL ;
      FileID         : XFileType ;
      Enough         : BOOLEAN ;
      ErrorMsg       : StrAny ;
      InputLine      : StrAny ;
      TC             : CHAR ;
      I              : CARDINAL ;
      First          : BOOLEAN ;
      Empty          : BOOLEAN ;
      SFileNameUsed  : StrAny ;
      NewSetupFile   : BOOLEAN ;
(*
   PROCEDURE WriteText( Str : ARRAY OF CHAR ) ;
      BEGIN
         IF NOT XWriteLine(FileID, '!', Str, IOResult) THEN
            IOErrorMessage(IOResult, ErrorMsg) ;
            MsgString( FileData.SetupFileName, 0 ) ;
            MsgString( ErrorMsg, 0 ) ;
            PutResError( FileHeaderResource ) ;
         END ;
      END WriteText ;

   PROCEDURE WriteSetupString( Str : ARRAY OF CHAR ) ;
      BEGIN
         MsgPos := 0 ;
         SWriteString( Message, MsgPos, '  ', 0 ) ;
         SWriteString( Message, MsgPos, Str, 0 ) ;
         WriteText( Message ) ;
      END WriteSetupString ;

   PROCEDURE WriteNames( VAR Names : ARRAY OF CHAR ) ;
      BEGIN
         MsgPos := 0 ;
         SWriteString( Message, MsgPos, '  ', 0 ) ;
         SWriteString( Message, MsgPos, Names, 0 ) ;
         WriteText( Message ) ;
         MsgPos := 0 ; (* prepare next line *)
         SWriteString( Message, MsgPos, '  ', 0 ) ;
      END WriteNames ;

   PROCEDURE AddNumeric( NumericFlag : BOOLEAN ) ;
      BEGIN
         IF NumericFlag THEN
            SWriteString( Message, MsgPos, Numeric, 10 )
         ELSE
            SWriteString( Message, MsgPos, NonNumeric, 10 )
         END ;
      END AddNumeric ;

   PROCEDURE AddSuppressText( SuppressText : BOOLEAN ) ;
      BEGIN
         IF SuppressText THEN
            SWriteString( Message, MsgPos, SupText, 10 )
         ELSE
            SWriteString( Message, MsgPos, NoSupText, 10 )
         END ;
      END AddSuppressText ;

   PROCEDURE AddWordSep( WordSepFlag : BOOLEAN ) ;
      BEGIN
         IF WordSepFlag THEN
            SWriteString( Message, MsgPos, WordSep, 10 )
         ELSE
            SWriteString( Message, MsgPos, NoWordSep, 10 )
         END ;
      END AddWordSep ;

   BEGIN
      IF NOT GotSCmdNames THEN GetSCmdNames END;

      WITH FileData DO
         TrimBlanks(SetupFileName, SetupFileName);
         IF SetupFileName[0] = 0C THEN RETURN END;

         IF DoAsSetup THEN
            SFileNameUsed := DefaultMKSFileName;
            DefaultMKSUsed := TRUE ;             (* m.s. - used in DBFILE *)
         ELSE
            Copy(SFileNameUsed, FileData.SetupFileName)
         END;

         GetXlationType( SFileNameUsed, Mode ) ;
         IF Mode[0] = 0C THEN
            Copy( Mode, DefaultMode ) ;
         END ;

         NewSetupFile := TRUE;
         IF (Exist(SFileNameUsed)) AND (SetupMessageNeeded) THEN
            (*RES OLD CHE 2
            Rewrite "%0"? Y)es or N)o:
            = Y N
            *)
            MsgString( SFileNameUsed, 0 ) ;
            ResAskUser( (*RES REM INS*) 2 , 'YN', TC);
            IF TC = 'N' THEN RETURN END;
            NewSetupFile := FALSE;
         END;

         IF NOT XOpenOutput( SFileNameUsed, MKSExtension, Mode, FileID, ErrorMsg ) THEN
            (* something wrong ... *)
            MsgString( SFileNameUsed, 0 ) ;
            MsgString( ErrorMsg, 0 ) ;
            PutResError( FileHeaderResource ) ;
            XClose( FileID ) ;
            RETURN ;
         END ;
      END;

      First := TRUE;
      FOR I := 1 TO NoAlphaLines DO
         IF AlphaInfo.AlphaString[I][0] <> 0C THEN
            IF First THEN
               First := FALSE;
               WriteText( SCmdName[AlphaRecType] ) ;
            END;
            WriteSetupString( AlphaInfo.AlphaString[I] ) ;
         END;
      END;
      First := TRUE;
      FOR I := 1 TO NoRetDiLines DO
         IF AlphaInfo.RetDiacStr[I][0] <> 0C THEN
            IF First THEN
               First := FALSE;
               WriteText( SCmdName[RetDiRecType] ) ;
            END;
            WriteSetupString( AlphaInfo.RetDiacStr[I] ) ;
         END;
      END;
      First := TRUE;
      FOR I := 1 TO NoNonDiLines DO
         IF AlphaInfo.NonDiacStr[I][0] <> 0C THEN
            IF First THEN
               First := FALSE;
               WriteText( SCmdName[NonDiRecType] ) ;
            END;
            WriteSetupString( AlphaInfo.NonDiacStr[I] ) ;
         END;
      END;
      IF NOT DoAsSetup THEN
         IF FileData.DataBaseTitle[0] <> 0C THEN
            WriteText( SCmdName[TitleRecType] ) ;
            WriteSetupString( FileData.DataBaseTitle ) ;
         END;
      END;
      IF FileData.StartingRef[0] <> 0C THEN
         WriteText( SCmdName[RefTemplateType] ) ;
         WriteSetupString( FileData.StartingRef ) ;
      END;
      IF AlphaInfo.ContinuationSeq[0] <> 0C THEN
         WriteText( SCmdName[ContRecType] ) ;
         WriteSetupString( AlphaInfo.ContinuationSeq ) ;
      END;
      CopyListPointer( SCList, TempList ) ;
      SetToTop( TempList ) ;
      WHILE MoveDown( TempList ) DO
         GetData( TempList, DataPtr ) ;
         SCData := DataPtr ;
         WITH SCData^ DO
            CASE TypeOfSpecialChar OF
               IgnoreSCType ,
               ReferenceSCType ,
               WordSepSCType :
                  WriteText( SCmdName[ SpCharToRecType[TypeOfSpecialChar] ] ) ;
               ELSE
                  ProgramErrorAndHalt( 'error in writing special characters to setup file' ) ;
            END ;
            CASE TypeOfSpecialChar OF
               WordSepSCType :
                  WriteSetupString( WordSepSeq ) ;
               ELSE
                  MsgPos := 0 ;
                  SWriteString( Message, MsgPos, '  ', 0 ) ;
                  SWriteString( Message, MsgPos, OpenBracket, 8 ) ;
                  SWriteString( Message, MsgPos, CloseBracket, 8 ) ;
                  AddSuppressText( SuppressText ) ;
                  AddWordSep( WordSep ) ;
                  WriteText( Message ) ;
            END ;
         END ;  (* WITH SCData^ DO *)
      END; (* WHILE MoveDown( TempList ) DO *)
      FreeListPointer( TempList ) ;

      CopyListPointer( StructList, TempList ) ;
      SetToTop( TempList ) ;
      WHILE MoveDown( TempList ) DO
         GetData( TempList, DataPtr ) ;
         StructData := DataPtr ;
         WITH StructData^ DO
            WriteText( SCmdName[ StructInfoToRecType[TypeOfStructInfo] ] ) ;
            CASE TypeOfStructInfo OF
               WordCounterType : (* 2 lines for setup representation *)
                  WriteNames( Names ) ;
                  SWriteCard( Message, MsgPos, WordCounterInit, 5 ) ;
                  WriteText( Message ) ;
                  |
               LineCounterType : (* 2 lines for setup representation *)
                  WriteNames( Names ) ;
                  SWriteCard( Message, MsgPos, LineCounterInit, 5 ) ;
                  SWriteString( Message, MsgPos, ' ', 0 ) ;
                  SWriteString( Message, MsgPos, LineCounterReset, 0 ) ;
                  WriteText( Message ) ;
                  |
               ReferenceType : (* 2 lines for setup representation *)
                  WriteNames( Names ) ;
                  SWriteString( Message, MsgPos, RefRefID, 20 ) ;
                  SWriteString( Message, MsgPos, ' ', 0 ) ;
                  AddNumeric( RefNumeric ) ;
                  SWriteCard( Message, MsgPos, RefNoCharsKeep, 5 ) ;
                  WriteText( Message ) ;
                  |
               LabelType : (* 2 lines for setup representation *)
                  WriteNames( Names ) ;
                  SWriteString( Message, MsgPos, LabelOpenBracket, 8 ) ;
                  SWriteString( Message, MsgPos, LabelCloseBracket, 8 ) ;
                  AddSuppressText( LabelSuppressText ) ;
                  AddWordSep( LabelWordSep ) ;
                  AddNumeric( LabelNumeric ) ;
                  SWriteCard( Message, MsgPos, LabelNoCharsKeep, 5 ) ;
                  WriteText( Message ) ;
                  |
               CounterType : (* 3 lines for setup representation *)
                  WriteNames( Names ) ;
                  SWriteCard( Message, MsgPos, CounterInit, 5 ) ;
                  SWriteString( Message, MsgPos, ' ', 0 ) ;
                  AddSuppressText( CounterSuppressText ) ;
                  SWriteString( Message, MsgPos, CounterRefID, 0 ) ;
                  WriteText( Message ) ;
                  MsgPos := 0 ;
                  SWriteString( Message, MsgPos, '  ', 0 ) ;
                  SWriteString( Message, MsgPos, CounterReset, 80 ) ;
                  WriteText( Message ) ;
                  |
               BYUType : (* 2 lines for setup representation *)
                  WriteNames( Names ) ;
                  SWriteString( Message, MsgPos, BYURefID, 1 ) ;
                  SWriteString( Message, MsgPos, ' ', 0 ) ;
                  AddNumeric( BYUNumeric ) ;
                  SWriteCard( Message, MsgPos, BYUNoCharsKeep, 5 ) ;
                  WriteText( Message ) ;
                  |
               PosType:
                  WriteNames( Names ) ;
                  SWriteCard( Message, MsgPos, PosStart, 5 ) ;
                  SWriteCard( Message, MsgPos, PosEnd, 5 ) ;
                  AddNumeric( PosNumeric ) ;
                  WriteText( Message ) ;
               ELSE
                  ProgramErrorAndHalt( 'error in writing special characters to setup file' ) ;
            END ;
         END ;  (* WITH StructData^ DO *)
      END; (* WHILE MoveDown( TempList ) DO *)
      FreeListPointer( TempList ) ;
      XClose( FileID );

      IF Confirm THEN
         MsgString( SFileNameUsed, 0 ) ;
         IF NewSetupFile THEN
            (*RES OLD MSG 440
            File "%0" has been created.
            *)
            PutResMessage( (*RES REM INS*) 440 )
         ELSE
            (*RES OLD MSG 441
            File "%0" has been updated.
            *)
            PutResMessage( (*RES REM INS*) 441 )
         END;
      END;
*)
   END WriteSetupFile ;

PROCEDURE VerifySetupFile(VAR FileName: ARRAY OF CHAR): BOOLEAN;
VAR
   Temp:     ARRAY[0..55] OF CHAR;

PROCEDURE LoadDefaultSetup(): BOOLEAN;
BEGIN
   IF InitialSetupDone THEN RETURN TRUE
   ELSIF FindFileInList(StandardSearchList,DefaultMKSFileName,Temp) THEN
      Append(Temp, DefaultMKSFileName );
      RETURN ReadSetupFile( Temp )
   ELSE
      (*RES OLD MSG 190
      The default Markup file "%0" could not be found. Please check
      your Markup options again.
      *)
      Copy( Temp, DefaultMKSFileName );
      MsgString( Temp, 0 );
      PutResWarning( (*RES REM INS*) 190 );
      RETURN TRUE
   END;
END LoadDefaultSetup;

   BEGIN
      TrimBlanks(FileName, FileName);
      IF FileName[0] = 0C THEN RETURN LoadDefaultSetup() END;

      GetXlationType( FileName, Mode ) ;
      IF (NOT StandardizeFileName(FileName, MKSExtension)) THEN
         (*RES OLD MSG 119
         Please change the file name %0.
         *)
         MsgString( FileName, 0 );
         PutResError( (*RES REM INS*) 119 );
         IF Mode[0] <> 0C THEN    (* reconstruct full name *)
            Append( FileName, '@' ) ;
            Append( FileName, Mode ) ;
         END ;
         RETURN FALSE
      END;

      IF (NOT Exist(FileName)) THEN
         IF SetupMessageNeeded THEN
            (*RES OLD MSG 120
            The Markup file "%0" does not exist and may be created.
            *)
            MsgString( FileName, 0 );
            PutResWarning( (*RES REM INS*) 120 );
         END;
         IF Mode[0] <> 0C THEN  (* reconstruct full name *)
            Append( FileName, '@' ) ;
            Append( FileName, Mode ) ;
         END ;
         RETURN LoadDefaultSetup();
      ELSE
         IF Mode[0] <> 0C THEN  (* reconstruct full name *)
            Append( FileName, '@' ) ;
            Append( FileName, Mode ) ;
         END ;
         RETURN ReadSetupFile( FileName )
      END;
   END VerifySetupFile ;

PROCEDURE InitCodeSetupFile ;  (* this is for OVERLAY mechanism *LP* *)
   BEGIN
     GotSCmdNames := FALSE;
     InitialSetupDone := FALSE;
     SetupMessageNeeded := TRUE;
   END InitCodeSetupFile ;

END SetupFile .
