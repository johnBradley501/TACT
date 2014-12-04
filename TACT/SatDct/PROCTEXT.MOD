IMPLEMENTATION MODULE ProcTextSource ;

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

(*V1=Debug*)
(*V2=Production*)

(*
Last Modified:
  8 September 1989 - L.Presutti
  - Fixed the handling of the "continuation" character when its the only
    part of a word at the end of a line.  Just ignore it.
  - Changed code to split a line based on command line parm "-f".
  18 October 1989 - L.Presutti
  - in ProcessRefBYU call, we will use the IntName instead of the BYURefCode
    in order to maintain case sensitivity on markers [ie. |p is different
    than |P ].  Note corresponding change to XlatUser.MOD -- BYUType: no
    longer performs a translation and thus use the "internal" form with
    proper case.
*)

FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR ;
IMPORT Lib, Str ;
FROM Storage IMPORT ALLOCATE ;
FROM KeyTranslation IMPORT FILEText;
FROM StringIO IMPORT SWriteString, SWriteCard ;
FROM Str IMPORT StrToCard, Compare, Length, Copy, Slice, Append,
     Prepend, Pos, CardToStr, IntToStr ;
FROM Lib IMPORT Move ;
(* FROM StringsData IMPORT
  (* Types *) StringRec, StringRecPtr,
  (* Procs *) InitStrings, LocateStr, WriteStringsToDB ;
FROM WordProcessing IMPORT
  (* Procs *) InitWordColl, ProcessCollectedWord ;
*)
FROM VirtualMemory IMPORT
  (* Procs *) (* ReleasePage, *) IsEqual, MakeReal, (* MarkDirty, *)
  (* Vars  *) VirtNil,
  (* Type  *) VirtualAddrType, VirtPageStorePtr ;
FROM SatHash IMPORT
  (* Procs *) InsertHash, FreeHashMemory ;

FROM LongSort IMPORT LSortRelease ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt ;
FROM TokenDataSource IMPORT
  (* Vars  *) RecordNumber, TokenNumber, TypeNumber,
              TokenListStart, CurrTokenArray, CurrTokenPos, BeginToken,
              VCurrTokenArray, BeginStr, EndStr,
              BeginOccur, BeginType, BeginText, BeginIndex,
              EndTextRec, EndTextIdx, EndTypeRec, EndTypeIdx,
              EndTokenRec, EndTokenIdx, NoTypes, BeginStrRec, NoStrRecs,
  (* Vars  *) InputFileID ;
(*
FROM HyperDataModel IMPORT
  (* Const *) HyperLength, PastHeader, HNoTokens,
              HNoPDBWords, BaseHTypeLen,
  (* Types *) HyperData;
FROM LogFile IMPORT
  (* Vars  *) VLastLogEntry, VWordLogEntry, StringsStartIndex,
  (* Procs *) InitLogList, AddNoToLogList, AddStrToLogList, WriteLogListToDB ;
*)
IMPORT Utils ; (* for ReadLine *)
FROM Utils IMPORT
  (* Types  *) WrStr, WrLn, BOpen, BFile, BCreate, BClose,
               month, day, year,
  (* Procs  *) Beep, GetXlationType, RemoveExtension, BDelete, LowcaseStr ;
FROM UtilsTwo IMPORT IOErrorMessage, OK, InsufficientData;
FROM Translations IMPORT
  (* Type  *) XFileType, XlateStrAny, CurrentModeType,
  (* Vars  *) Int2FAlp, LenD,
  (* Procs *) XClose, XOpenInput, XReadLine, XlateLine, XWrStr, XWrLn,
              XOpenOutput, XWriteLine ;
FROM GlobalDefs IMPORT
  (* Const *) MaxStringLen, TXTExtension, ERRExtension,
  (* Type  *) StrAny, FileNameType, SequenceType ;
FROM StartUp IMPORT FileData, WantFolding, WordAny, IncludeType;
FROM KeyBase IMPORT
  (* Procs *) Read, KeyPressed, GetKeyStroke ;
FROM RunPan IMPORT
  (* Procs *) WriteTextWindow, PutRecordNumber, PutTokenCount, PutTypeCount,
		PutErrorCount, PutPercentage, ClearAndWriteTextWindow, PutRunStatus ;
(* FROM DBFile IMPORT
  (* Vars  *) HRecord, HRecNo, HRecPos ,
  (* Procs *) WriteDBRec, AddTextToDB, FinishAddPtrDataToDB, InitAddPtrDataToDB ;
*)
FROM WordBase IMPORT
  (* Types *) AlphaCharType,
  (* Vars  *) TypeOfChar,
  (* Procs *) FullToSortWord, SortToIntWord, IntToSortWord ;
FROM XlatUserInput IMPORT
  (* Const *) EolSymbol, WordSepCode, MaxNumbResets,
  (* Types *) IgnoreRefPtr, CounterPtr, CounterCharPtr, LabelPtr,
              RefBYUPtr,
  (* Vars  *) IgnoreBrkList, RefBrkList, CounterCharList, LabelList,
              RefList, BYUList, LineCounterPtr;
FROM ResMessages IMPORT
  (* Procs *) GetResMessage, ResAskUser, PutResError, MsgString, MsgCard ;
FROM PCKey IMPORT
  (* Const *) F2 ;
IMPORT FIO;

(*<Debug
FROM Trace IMPORT DoTrace ;
Debug>*)


TYPE
  TypeOfCollection = (WordLook, InWord, ContSkipBlanks, IgnoreText, ReferenceText,
                      LabelText, BYUText, CounterText ) ;
  RefStates  = ( RefIdLook, RefId, RefFieldLook, RefField ) ;
  LabStates  = ( LabFieldLook, LabField ) ;
  BYUStates  = ( BYURef, BYUField ) ;
  RefBYUType = ( RefType, BYUType ) ;
  MsgType = ( Error, Warning ) ;
(*  StrItemProcess = PROCEDURE( VAR VirtualAddrType, VAR VirtualAddrType, CARDINAL, VAR ARRAY OF CHAR ) ; *)
  WordPtr  = POINTER TO WordAny ;
  TYPE
     ProcessWordType = PROCEDURE( ARRAY OF CHAR ) ;

CONST
  Space = ' ' ;
  SplitLineChar = 370C ;	(* 248 in STANDARD.CDF *)

VAR
(*  DoItem        : StrItemProcess ;
  LastStr	  : StringRecPtr ; *)
  FinalWord       : WordPtr ;
  NoConts         : LONGCARD ;
  ProcessWord : ProcessWordType ;
  TAG, PS : ARRAY[0..63] OF CHAR ;


PROCEDURE ProcessCollectedWord( W : ARRAY OF CHAR ) ;
  BEGIN
     FullToSortWord( W, W ) ;
     SortToIntWord( W, W ) ;
     LowcaseStr( W , W ) ;
(*     LSortRelease( Word ) ; *)
(*     InsertHash( Word , TRUE ) ; *)
     InsertHash( W, PS, TAG ) ;
     INC( TokenNumber ) ;
     TAG[0] := 0C ;
     PS[0] := 0C ;
  END ProcessCollectedWord ;

PROCEDURE ProcessCollectedLemma( W : ARRAY OF CHAR ) ;
  BEGIN
     FullToSortWord( W, W ) ;
     SortToIntWord( W, W ) ;
     LowcaseStr( W , W ) ;
(*     LSortRelease( Word ) ; *)
(*     InsertHash( Word , TRUE ) ; *)
     InsertHash( TAG, PS, W ) ;
     INC( TokenNumber ) ;
     TAG[0] := 0C ;
     PS[0] := 0C ;
  END ProcessCollectedLemma ;


(*
PROCEDURE LoopAllStrs( DoItem : StrItemProcess ) ;
  VAR
     TempPtr : LabelPtr ;

  PROCEDURE DoLists( HeadList : RefBYUPtr ) ;
    VAR
       TempList : RefBYUPtr ;
    BEGIN
       TempList := HeadList ;
       WHILE TempList <> NIL DO
          IF NOT TempList^.Numeric THEN
             WITH TempList^ DO
               DoItem( StrHeader, VLastStr, StructID, StrRecInfo ) ;
             END ;
          END ;
          TempList := TempList^.Next ;
       END ;
    END DoLists ;

  BEGIN
     TempPtr := LabelList ;
     WHILE TempPtr <> NIL DO
        IF NOT TempPtr^.Numeric THEN
           WITH TempPtr^ DO
              DoItem( StrHeader, VLastStr, StructID, StrRecInfo ) ;
           END ;
        END ;
        TempPtr := TempPtr^.Next ;
     END ;
     DoLists( RefList ) ;
     DoLists( BYUList ) ;
  END LoopAllStrs ;

PROCEDURE InitStr( VAR StrHeader, VLastStr  : VirtualAddrType ;
                       StructID   : CARDINAL ;
                   VAR StrRecInfo : ARRAY OF CHAR ) ;
  BEGIN
     InitStrings( StrHeader ) ;
     LocateStr( 0C, "???", 3, StrHeader, VLastStr ) ; (* dummy first string *)
  END InitStr ;

PROCEDURE InitAllStrings() ;
  BEGIN
     DoItem := InitStr ;
     LoopAllStrs( DoItem ) ;
  END InitAllStrings ;

PROCEDURE WriteStr( VAR StrHeader, VLastStr  : VirtualAddrType ;
                        StructID   : CARDINAL ;
                    VAR StrRecInfo : ARRAY OF CHAR ) ;
  BEGIN
     (* set the final tally *)
     MakeReal( VLastStr, LastStr ) ;
     WITH LastStr^ DO
	INC( TotWords, TokenNumber - CurWordNo ) ;
     END ;
     MarkDirty( VLastStr ) ;
     ReleasePage( VLastStr, LastStr ) ;
     WriteStringsToDB( StrHeader, StrRecInfo ) ;
     StringsStartIndex[ StructID ] := StrRecInfo[1] ;  (* start index = 1 *)
  END WriteStr ;

PROCEDURE WriteStrRec( VAR StrHeader, VLastStr  : VirtualAddrType ;
                           StructID   : CARDINAL ;
                       VAR StrRecInfo : ARRAY OF CHAR ) ;
  VAR
     Str : ARRAY[0..5] OF CHAR ;
     ID  : INTEGER ;
  BEGIN
     INC( NoStrRecs ) ;
     ID := - INTEGER( StructID ) ;
     Move( ADR(ID), ADR(Str[0]), 2);
     Move( ADR(StrRecInfo), ADR(Str[2]), 4);
     AddTextToDB( Str, 6 ) ;
  END WriteStrRec ;
*)


PROCEDURE ProcessText() : BOOLEAN ;

  VAR
     Continue : BOOLEAN ;
     Mode     : ARRAY[0..7] OF CHAR ;
     Extended : BOOLEAN;
     Dummy	: ADDRESS ;
  ColStatus   : TypeOfCollection ;
  RefStatus   : RefStates ;
  LabStatus   : LabStates ;
  BYUStatus   : BYUStates ;
  InputLine   : StrAny ;
  StrippedLine : StrAny ;
  ErrorMsg    : StrAny ;
  MsgPos      : CARDINAL ;
  ActRecNo    : CARDINAL ;
  WordStore   : WordAny ;
  WSP         : CARDINAL ;
  SWdRec, SWdPos: CARDINAL ;
  SWdRecNo    : LONGCARD ;
  IOResult    : CARDINAL ;
  IdP         : CARDINAL ;
  KeyIdP      : CARDINAL ;
  NotSupText  : BOOLEAN ;
  WordSep     : BOOLEAN ;
  EndChar     : CHAR ;
  RefIdName   : (* StrAny *) ARRAY[0..30] OF CHAR ;
  RefStr      : StrAny ;
  LabStr      : StrAny ;
  KeyStr      : StrAny ;
  BYURefCode  : CHAR ;
  BYUFieldStr : StrAny ;
  IntName     : StrAny ;
  IntP        : CARDINAL ;
  LabPtr      : LabelPtr ;
  IgnTextInWord : BOOLEAN ;
  RefTextInWord : BOOLEAN ;
  ErrorFile     : XFileType ;
  ErrorFileName : FileNameType ;
  NoMoreMsg     : BOOLEAN ;
  NoOfErrors    : CARDINAL ;
  NoOfWarnings  : CARDINAL ;
  InputLineNo   : CARDINAL ;
  StrLineNo    : StrAny ;
  SPos          : CARDINAL ;
  Ch            : CHAR ;
  Percentage	: CARDINAL ;
  InFileLen	: LONGCARD ;
  ShowTextCount : CARDINAL ;
  FirstWarning  : BOOLEAN ;
  symbol        : SequenceType ;

  ReadFlag	: BOOLEAN ;
  FoldFromInput	: BOOLEAN ;
  LineLen	: CARDINAL ;
  StartPos	: CARDINAL ;
  RefFile       : BFile ;
  TagFile       : BFile ;
  TempTagFile   : BFile ;
  TempLong      : LONGCARD ;
  TempStr       : WordAny ;
  Result        : BOOLEAN ;
  StrippedFileID : XFileType ;
  ContInLine     : BOOLEAN ;
  StrippedWordBeginPos : CARDINAL ;
  FAStart       : CARDINAL ; (* m.s. *)
  InFileLine   : StrAny ; (* m.s. - moved from GetTextLine *)

(*RES OLD MSG 101
File: %0 - %1
*)

CONST
  FileErrorRes = (*RES REM INS *) 101 ;

(*RES OLD MSG 125
"%0" cannot be converted to a number.
*)
  NumbConvErrorRes = (*RES REM INS*) 125 ;

(*RES OLD MSG 126
Null field value for Reference.
*)
  NullRefFieldRes = (*RES REM INS*) 126 ;


PROCEDURE PutLineMsg(     MsgID: CARDINAL;
                          Type : MsgType ;
                      VAR Ch   : CHAR ) ;
   VAR
      SPos : CARDINAL ;
      Str  : StrAny ;
      OutLine : StrAny;
      ActLen  : CARDINAL;
      LenD    : XlateStrAny ;
      ns      : CARDINAL;
      EnoughData : BOOLEAN;

PROCEDURE WriteToErrorFile;
BEGIN
   IF NOT XWriteLine(ErrorFile, '?', Str, IOResult) THEN
      IOErrorMessage(IOResult, Str);
      MsgString(ErrorFileName,0);
      MsgString(Str,0);
      PutResError( FileErrorRes );
   END;
END WriteToErrorFile;

   BEGIN
      GetResMessage( MsgID, Str ) ;
      IF (Type = Error) AND NOT NoMoreMsg THEN
         (*RES OLD CHE 0
         %0 Error Options: C)ontinue, S)ilent continue, A)bort, F)inish-Now:
         = C S A F
         *)
         MsgString(Str, 0);
         ResAskUser( (*RES REM INS *) 0, 'CSAF', Ch ) ;
         IF Ch = 'S' THEN
            NoMoreMsg := TRUE ;
            Ch := 'C' ;
         END ;
         INC( NoOfErrors ) ;
      ELSE
         INC( NoOfWarnings )
      END ;
      PutErrorCount( NoOfErrors + NoOfWarnings ) ;
      WriteToErrorFile;
      (*RES OLD MSG 127
      Line: %0: "%1"
      *)
      MsgCard(InputLineNo,0);
      MsgString(InputLine,0);
      GetResMessage( (*RES REM INS*) 127, Str);
      WriteToErrorFile;
      Str[0] := 0C;
      WriteToErrorFile;
   END PutLineMsg ;

(*
PROCEDURE ResetCounter( Counter : CounterPtr ) ;
   VAR
      I : CARDINAL ;
   BEGIN
      WITH Counter^ DO
         CurrentValue := Init ;
         AddNoToLogList( StructID, CurrentValue ) ;
         I := 1 ;
         WHILE (I <= MaxNumbResets) AND (ResetsCounters[I] <> NIL) DO
            ResetCounter( ResetsCounters[I] ) ;
            INC( I ) ;
         END ;
      END ;
   END ResetCounter ;

PROCEDURE IncCounter( Counter : CounterPtr ) ;
   VAR
      I       : CARDINAL ;
   BEGIN
      WITH Counter^ DO
         INC( CurrentValue ) ;
         AddNoToLogList( StructID, CurrentValue ) ;
         I := 1 ;
         WHILE (I <= MaxNumbResets) AND (ResetsCounters[I] <> NIL) DO
            ResetCounter( ResetsCounters[I] ) ;
            INC( I ) ;
         END ;
      END ;
   END IncCounter ;

PROCEDURE ProcessCounter( Counter : CounterPtr ) ;
   VAR
      I       : CARDINAL ;
   BEGIN
      WITH Counter^ DO
         INC( CurrentValue ) ;
         AddNoToLogList( StructID, CurrentValue ) ;
         I := 1 ;
         WHILE (I <= MaxNumbResets) AND (ResetsCounters[I] <> NIL) DO
            ResetCounter( ResetsCounters[I] ) ;
            INC( I ) ;
         END ;
      END ;
   END ProcessCounter ;
*)

PROCEDURE ReadLine( VAR InputLine : StrAny ) : BOOLEAN ;
  VAR
     EnoughData : BOOLEAN ;
     al		: CARDINAL ;

  PROCEDURE GetTextLine( VAR InputLine : ARRAY OF CHAR ;
			 VAR IOResult	 : CARDINAL;
			 VAR al		 : CARDINAL ) ;
	VAR
	   I, J, K	: CARDINAL ;
	   ld		: XlateStrAny ;
	   ns		: CARDINAL;
	   FoldedLine, FAFileLine	: StrAny ;
	   Folded	: BOOLEAN ;
	   ch		: CHAR ;
	   EndPos       : CARDINAL ;
	   OK           : BOOLEAN ;
           cm         : CurrentModeType;
(*
     PROCEDURE ProcessFixedPosRefs;
     VAR
        i,j,k,s,e:   CARDINAL;
        ints, alps:  ARRAY[0..40] OF CHAR;
        cm:          CurrentModeType;
        ed:          BOOLEAN;
        uc:          BOOLEAN;
        cur:         RefPosPtr;

     PROCEDURE HandleNumericRef;
     BEGIN
        s := 0;
        WHILE (ints[s] <> 0C) DO
           IF ints[s] = ' ' THEN ints[s] := '0' END;
           INC(s)
        END;
        s := CARDINAL(Str.StrToCard(ints, 10, ed));
        IF ed THEN
           IF s <> cur^.LastValCard THEN
              AddNoToLogList( cur^.StructID, s ) ;
              cur^.LastValCard := s;
              uc := TRUE;
           END;
        ELSE
           MsgString(ints, 0);
           PutLineMsg( NumbConvErrorRes, Error ,Ch);
           RETURN
        END ;
     END HandleNumericRef;

     PROCEDURE HandleStrRef;
     BEGIN
        cm.ModeIn := '0'; cm.ModeOut := '0';
        XlateLine( Int2FAlp, WordSepCode, ints, cm, s, LenD, e, ed, alps);
        IF Str.Compare(cur^.LastValStr, alps) <> 0 THEN
          uc := TRUE;
          Str.Copy(cur^.LastValStr, alps);
          IF NOT IsEqual( cur^.VLastStr, VirtNil ) THEN
             MakeReal( cur^.VLastStr, LastStr ) ;
             WITH LastStr^ DO
               INC( TotWords, TokenNumber - CurWordNo ) ;
             END ;
             MarkDirty( cur^.VLastStr ) ;
             ReleasePage( cur^.VLastStr, LastStr ) ;
          END ;
          LocateStr( alps, ints, Str.Length(ints), cur^.StrHeader, cur^.VLastStr ) ;
          MakeReal( cur^.VLastStr, LastStr ) ;
          LastStr^.CurWordNo := TokenNumber ;
          MarkDirty( cur^.VLastStr ) ;
          ReleasePage( cur^.VLastStr, LastStr ) ;

          AddStrToLogList( cur^.StructID, cur^.VLastStr ) ;
        END;
     END HandleStrRef;

     BEGIN
        cur:= PosRefList;
        i := 0;
        j := 0;
        k := 0;
        WHILE (j <= cur^.EndPos) AND (i < ns) DO
           INC(j, ld[i].Int);
           INC(k, ld[i].Out);
           INC(i);
        END;
        DEC(i);
        WHILE (cur <> NIL) DO
           IF j >= cur^.EndPos THEN
              WHILE (j > cur^.EndPos) DO
                 DEC(j, ld[i].Int);
                 DEC(k, ld[i].Out);
                 DEC(i);
              END;
              e := k;
              IF cur^.StartPos = 0 THEN
                 s := 0;
                 j := 0;
              ELSE
                 WHILE (j > cur^.StartPos) DO
                    DEC(j, ld[i].Int);
                    DEC(k, ld[i].Out);
                    DEC(i);
                 END;
                 s := k;
              END;

              Str.Slice(ints, InputLine, s, e - s + 1);
              Str.Delete(InputLine, s, e - s + 1);
              DEC(al, e - s + 1);
              Utils.TrimBlanks(ints, ints);

              uc := FALSE;
              IF (ints[0] = 0C) OR (cur^.StructID = 0) THEN (* do nothing *)
              ELSIF cur^.Numeric THEN HandleNumericRef
              ELSE HandleStrRef END;

              IF uc THEN
                 s := 1 ;
                 WHILE (s <= MaxNumbResets) AND (cur^.IncremCounters[s] <> NIL) DO
                    IncCounter( cur^.IncremCounters[s] ) ;
                    INC( s ) ;
                 END ;
              END ;
           END;

           cur := cur^.Next;
        END;
        Utils.TrimBlanks(InputLine, InputLine);
     END ProcessFixedPosRefs;
  *)
	BEGIN
	   IF ReadFlag THEN
		ReadFlag := FALSE ;
		StartPos := 0 ;
		IF NOT Utils.ReadLine( InputFileID.ID, InFileLine, EnoughData, IOResult ) THEN
		   RETURN
		END ;
		INC( InputLineNo ) ;  (* corresponds to file line number *)
		Utils.TrimBlanks( InFileLine, InFileLine ) ;

		LineLen := Str.Length( InFileLine ) ;
		PutRecordNumber( RecordNumber ) ;
		PutTypeCount( TypeNumber ) ;
		PutTokenCount( TokenNumber ) ;
		FAStart := 0 ;  (* m.s. *)
		IF (LineLen <> 0) AND NOT FoldFromInput THEN
		   INC( RecordNumber ) ;
(*		   ProcessCounter( LineCounterPtr ) ; *)
		END ;
	   END ;
	   IF WantFolding THEN
	      IF (LineLen - StartPos) > 75 THEN
                cm.ModeIn := '0'; cm.ModeOut := '0';
       		EndPos := StartPos + 75 ;
         	XlateLine(InputFileID.XP, '?', InFileLine, InputFileID.ModeData,
			al, ld, ns, EnoughData, FAFileLine ) ; (* m.s. *)
         	XlateLine(Int2FAlp, WordSepCode, FAFileLine, cm,
			al, ld, ns, EnoughData, FAFileLine ) ; (* m.s. *)
		OK := TRUE ;	
                J := StartPos ;
                K := FAStart ;
                I := J ;
                WHILE (J <= EndPos) DO
                   CASE TypeOfChar[ FAFileLine[K] ] OF (* m.s. *)
                      RefBrkEnd, LabelEnd :   (* m.s. - removed IgnBrkEnd *)
                         OK := TRUE ;
                    | LabelStart, RefBrkStart : (* m.s. - removed IgnBrkStart *)
                         OK := FALSE ;
                    | NullChar :
                         IF OK = TRUE THEN
                            I := J ; (* m.s. - found space outside ref, ign or label *)
                            FAStart := K + 1 ;
                         END ;
                   END ;
                   INC( J, ld[K].Int ) ;
                   INC( K ) ;
		END ;
		IF I = StartPos THEN
		   (* unable to split line at 75 char boundary -- long word *)
		   I := StartPos + 75 ;
                   K := FAStart ;
		   WHILE (I <= LineLen) DO
                       CASE TypeOfChar[ FAFileLine[K] ] OF (* m.s. *)
                          RefBrkEnd, LabelEnd :   (* m.s. - removed IgnBrkEnd *)
                             OK := TRUE ;
                     |    LabelStart, RefBrkStart : (* m.s. - removed IgnBrkStart *)
                             OK := FALSE ;
                     |    NullChar :
                             IF OK = TRUE THEN
                                FAStart := K + 1 ;
                                (* m.s. - found space outside ref, ign or label *)
                                I := LineLen + 1 ;
                             END ;
                       END ;
                       INC( I, ld[K].Int ) ;
                       INC( K ) ;
		   END ;
         		   IF I >= LineLen THEN
			ReadFlag := TRUE ;
		   END ;
		   (*RES OLD MSG 266
		   Warning: Line cannot be Split because it Contains a Word Longer
		   than 75 Characters.
		   *)
		   PutLineMsg( (*RES REM INS *) 266 , Warning, ch ) ;		
		END ;
		J := 0 ;
		FOR K := StartPos TO I DO
		   FoldedLine[J] := InFileLine[K] ;
		   INC( J ) ;
		END ;
		FoldedLine[J] := 0C ;
		StartPos := I + 1 ;
		IF I >= LineLen THEN
		   Folded   := FALSE ;
		ELSE
		   Folded   := TRUE ;
		END ;
	      ELSE
		J := 0 ;
		FOR K := StartPos TO LineLen DO
		   FoldedLine[J] := InFileLine[K] ;
		   INC( J ) ;
		END ;
		FoldedLine[J] := 0C ;
		ReadFlag := TRUE ;
		Folded   := FALSE ;
	      END ;
	   ELSE	
		ReadFlag := TRUE ;
		Str.Copy( FoldedLine, InFileLine ) ;
	   END ;
	   XlateLine(InputFileID.XP, '?', FoldedLine, InputFileID.ModeData,
			al, ld, ns, EnoughData, InputLine ) ;
(*           IF PosRefList <> NIL THEN ProcessFixedPosRefs END; *)
	   IF WantFolding THEN
	      IF Folded THEN
		FoldFromInput := FALSE ;
		InputLine[al] := SplitLineChar ;
		INC(al) ;
	      ELSE
		IF InputLine[al] <> 0C THEN
		   FoldFromInput := InputLine[al] = SplitLineChar ;
		   INC(al) ;
		ELSIF al > 0 THEN
		   FoldFromInput := InputLine[al-1] = SplitLineChar ;
		ELSE
		   FoldFromInput := FALSE ;
		END ;
	      END ;
	   END ;
	   InputLine[al] := 0C ;
	END GetTextLine ;

  BEGIN
     (* Dummy := XReadLine( InputFileID, '?', InputLine, EnoughData, IOResult ) ; *)
     GetTextLine( InputLine, IOResult, al ) ;
     CASE IOResult OF
        OK :
          IF InputLineNo MOD ShowTextCount = 0 THEN
             Percentage :=
             VAL(CARDINAL,FIO.GetPos( InputFileID.ID.FileID ) DIV InFileLen);

(*	     FileIO.GetPos( InputFileID.ID.FileID, CurrentPos, result ) ;
	     Percentage := VAL(CARDINAL, FileIO.ConvertFilePos(CurrentPos) DIV InFileLen) ; *)
	     PutPercentage( Percentage, TRUE ) ;
	  END ;
          IF DisplayText THEN
	     WriteTextWindow( InputLine ) ;
	  END ;
	  (* add end of line marker after displayed the text *)
	  InputLine[al] := EolSymbol ;
	  INC(al) ;
	  InputLine[al] := 0C ;
(*
	  IF FoldFromInput THEN
		PutRecordNumber( RecordNumber ) ;
		PutTypeCount( TypeNumber ) ;
		PutTokenCount( TokenNumber ) ;
		IF InputLine[0] <> 0C THEN
		   INC( RecordNumber ) ;
		   ProcessCounter( LineCounterPtr ) ;
		END ;
	  END ;
*)		
                  |
        InsufficientData :
(*         XClose(InputFileID); *)
           InputLine := '' ;
           RETURN FALSE ;
        ELSE
           IOErrorMessage(IOResult, ErrorMsg) ;
           MsgString( FileData.InputFileName, 0 ) ;
           MsgString( ErrorMsg, 0 ) ;
           PutResError( FileErrorRes ) ;
(*         XClose(InputFileID); *)
           InputLine := '' ;
           RETURN FALSE ;
     END ;  (* CASE IOResult OF *)
     RETURN TRUE
  END ReadLine ;

(*

PROCEDURE ProcessLabel( KeyStr : ARRAY OF CHAR;
                        LabStr : ARRAY OF CHAR;
                        LabLen : CARDINAL;
                        LabPtr : LabelPtr ) ;
   VAR
      Ch       : CHAR;
      I        : CARDINAL ;
      Number   : CARDINAL ;
      Done     : BOOLEAN ;
      VStrPtr  : VirtualAddrType ;
   BEGIN
      WITH LabPtr^ DO
	 IF LabLen > NoCharsKeep THEN
	    IF HIGH( LabStr ) > NoCharsKeep THEN  (* truncate string *)
		LabStr[NoCharsKeep] := 0C ;
	    ELSE
		NoCharsKeep := HIGH( LabStr )
	    END ;
	    LabLen := NoCharsKeep ;
         END ;
         IF Numeric THEN
            (* trim trailing blanks *)
            I := LabLen ;
            WHILE (I >= 0) AND (LabStr[I] = ' ') DO
               DEC( I ) ;
            END ;
            IF I < HIGH(LabStr) THEN
               LabStr[I+1] := 0C ;
            END;
            Number := CARDINAL(StrToCard(LabStr,10,Done));
            IF NOT Done THEN
               MsgString(LabStr, 0);
               PutLineMsg( NumbConvErrorRes, Error ,Ch);
               RETURN
            END ;
            AddNoToLogList( StructID, Number ) ;
         ELSE
	    IF NOT IsEqual( VLastStr, VirtNil ) THEN
	       MakeReal( VLastStr, LastStr ) ;
	       WITH LastStr^ DO
		  INC( TotWords, TokenNumber - CurWordNo ) ;
	       END ;
	       MarkDirty( VLastStr ) ;
	       ReleasePage( VLastStr, LastStr ) ;
	    END ;
            LocateStr( KeyStr, LabStr, LabLen, StrHeader, VStrPtr ) ;
	    (* could save next call by not releasing in LocateStr -- too much bother *)
	    MakeReal( VStrPtr, LastStr ) ;
	    LastStr^.CurWordNo := TokenNumber ;
	    MarkDirty( VStrPtr ) ;
	    ReleasePage( VStrPtr, LastStr ) ;
	
	    VLastStr := VStrPtr ;  (* new current str that words are associated with *)
	
            AddStrToLogList( StructID, VStrPtr ) ;
         END ;
         I := 1 ;
         WHILE (I <= MaxNumbResets) AND (IncremCounters[I] <> NIL) DO
            IncCounter( IncremCounters[I] ) ;
            INC( I ) ;
         END ;
      END ;
   END ProcessLabel ;

PROCEDURE ProcessRefBYU( IdCode   : ARRAY OF CHAR ;
                         IntName  : ARRAY OF CHAR ;
                         KeyStr   : ARRAY OF CHAR ;
                         FieldStr : ARRAY OF CHAR ;
                         StrLen   : CARDINAL ;
                         ListType : RefBYUType;
                     VAR HeadList : RefBYUPtr ) ;
   VAR
      Prev,
      TempList : RefBYUPtr ;
      I        : CARDINAL ;
      Number   : CARDINAL ;
      Done     : BOOLEAN ;
      VStrPtr  : VirtualAddrType ;
   BEGIN
      TempList := HeadList ;
      WHILE TempList <> NIL DO
         IF Compare( IdCode, TempList^.RefID ) = 0 THEN
            (* found it *)
            WITH TempList^ DO
	       IF StrLen > NoCharsKeep THEN
		  IF HIGH( FieldStr ) > NoCharsKeep THEN  (* truncate string *)
			FieldStr[NoCharsKeep] := 0C ;
		  ELSE
			NoCharsKeep := HIGH( FieldStr ) ;
		  END ;
		  StrLen := NoCharsKeep ;
               END ;
               IF Numeric THEN
                  Number := CARDINAL(StrToCard(FieldStr,10,Done));
                  IF NOT Done THEN
                     MsgString(LabStr, 0);
                     PutLineMsg( NumbConvErrorRes, Error ,Ch);
                     RETURN
                  END ;
                  AddNoToLogList( StructID, Number ) ;
               ELSE
		  IF NOT IsEqual( VLastStr, VirtNil ) THEN
		     MakeReal( VLastStr, LastStr ) ;
		     WITH LastStr^ DO
			INC( TotWords, TokenNumber - CurWordNo ) ;
		     END ;
		     MarkDirty( VLastStr ) ;
		     ReleasePage( VLastStr, LastStr ) ;
		  END ;
		
                  LocateStr( KeyStr, FieldStr, StrLen, StrHeader, VStrPtr ) ;
		  (* could save next call by not releasing in LocateStr -- too much bother *)
		  MakeReal( VStrPtr, LastStr ) ;
		  LastStr^.CurWordNo := TokenNumber ;
		  MarkDirty( VStrPtr ) ;
		  ReleasePage( VStrPtr, LastStr ) ;

		  VLastStr := VStrPtr ;  (* new current str that words are associated with *)
	
                  AddStrToLogList( StructID, VStrPtr ) ;
               END ;
               I := 1 ;
               WHILE (I <= MaxNumbResets) AND (IncremCounters[I] <> NIL) DO
                  IncCounter( IncremCounters[I] ) ;
                  INC( I ) ;
               END ;
            END ;
	   IF HeadList <> TempList THEN
		(* Move TempList to front *)
		Prev^.Next := TempList^.Next ;
		TempList^.Next := HeadList ;
		HeadList := TempList ;
	    END ;
            RETURN  (* we are done *)
         ELSE
	    Prev := TempList ;
            TempList := TempList^.Next
         END ;
      END ;
      (* id not found -- warning message *)
      SPos := 0 ;
      MsgString(IntName,0);
      IF ListType = RefType THEN
         (*RES OLD MSG 128
         Reference Id "%0" was not found
         *)
         PutLineMsg( (*RES REM INS*) 128, Warning, Ch);
      ELSE
         (*RES OLD MSG 129
         BYU Id "%0" was not found
         *)
         PutLineMsg( (*RES REM INS*) 129, Warning, Ch);
      END ;
   END ProcessRefBYU ;
*)

PROCEDURE ProcessLine(VAR IntLine: StrAny ) ;
VAR
     TextLen    : CARDINAL ;
     AlphaText  : StrAny ;
     CurPos     : CARDINAL ;
     NumbSeq    : CARDINAL ;
     IntLenD    : XlateStrAny ;
     EnoughData : BOOLEAN ;
     IntLinePos : CARDINAL ;
     CharCounter : CounterCharPtr ;
     cm         : CurrentModeType;
     BadChar    : CHAR ;
     IOResult   : CARDINAL ;
     TagInLine  : BOOLEAN ;
     I          : CARDINAL ;
     IgnText : StrAny ;
     TempWord : StrAny ;

PROCEDURE AddTextToOutput( IntLine : ARRAY OF CHAR ; IntLinePos, Len : CARDINAL ) ;
   VAR
      TempSlice : StrAny ;
   BEGIN
      Slice( TempSlice, IntLine, IntLinePos, Len ) ;
      Append( StrippedLine, TempSlice ) ;
   END AddTextToOutput ;


  PROCEDURE AdvancePointers() ;
     BEGIN
        IF NotSupText THEN
(*           AddTextToDB( IntLine[IntLinePos], IntLenD[CurPos].Int ) ; *)
           AddTextToOutput( IntLine, IntLinePos, IntLenD[CurPos].Int ) ;
        END ;
        INC( IntLinePos, IntLenD[CurPos].Int ) ;
        INC( CurPos ) ;
     END AdvancePointers ;

  PROCEDURE GetLabelInfo(     InCode      : CHAR ;
                          VAR NotSupText  : BOOLEAN ;
                          VAR IsWordSep   : BOOLEAN ;
                          VAR EndChar     : CHAR ;
                          VAR PtrAddr     : ADDRESS ) ;
     VAR
	Prev,
        TempPtr : LabelPtr ;
     BEGIN
        TempPtr := LabelList ;
        WHILE TempPtr <> NIL DO
           IF TempPtr^.OpenCode = InCode THEN
              WITH TempPtr^ DO
                 NotSupText := NOT SuppressText ;
                 EndChar    := ClosingCode ;
                 IsWordSep  := WordSep ;
              END ;
              PtrAddr := TempPtr ;
	      IF LabelList <> TempPtr THEN
		 (* Move TempPtr to front *)
		 Prev^.Next := TempPtr^.Next ;
		 TempPtr^.Next := LabelList ;
		 LabelList := TempPtr ;
	      END ;
              RETURN  (* get out of here! *)
           ELSE
	      Prev := TempPtr ;
              TempPtr := TempPtr^.Next
           END ;
        END ;
        (* should NOT get here if lists are NOT corrupted *)
        ProgramErrorAndHalt( 'GetLabelInfo: Label Character code not found in list' ) ;
     END GetLabelInfo ;

  PROCEDURE GetCounterInfo(     InCode     : CHAR ;
                            VAR NotSupText : BOOLEAN ;
                            VAR PtrAddr    : ADDRESS ) ;
     VAR
	Prev,
        TempPtr : CounterCharPtr ;
     BEGIN
        TempPtr := CounterCharList ;
        WHILE TempPtr <> NIL DO
           IF TempPtr^.Code = InCode THEN
              NotSupText := NOT TempPtr^.ToCounterData^.SuppressText ;
              PtrAddr := TempPtr ;
	      IF CounterCharList <> TempPtr THEN
		 (* Move TempPtr to front *)
		 Prev^.Next := TempPtr^.Next ;
		 TempPtr^.Next := CounterCharList ;
		 CounterCharList := TempPtr ;
	      END ;
              RETURN  (* get out of here! *)
           ELSE
	      Prev := TempPtr ;
              TempPtr := TempPtr^.Next
           END ;
        END ;
        (* should NOT get here if lists are NOT corrupted *)
        ProgramErrorAndHalt( 'GetCounterInfo: Counter Character code not found in list' ) ;
     END GetCounterInfo ;

  PROCEDURE GetSCInfo(     InCode     : CHAR;
                       VAR NotSupText : BOOLEAN ;
                       VAR IsWordSep  : BOOLEAN ;
                       VAR EndChar    : CHAR ;
                       VAR ListHead   : IgnoreRefPtr ) ;
     VAR
	Prev,
        TempPtr : IgnoreRefPtr ;
     BEGIN
	TempPtr := ListHead ;
        WHILE TempPtr <> NIL DO
           IF TempPtr^.OpenCode = InCode THEN
              WITH TempPtr^ DO
                 NotSupText := NOT SuppressText ;
                 EndChar    := ClosingCode ;
                 IsWordSep  := WordSep ;
              END ;
	      IF ListHead <> TempPtr THEN
		 (* Move TempPtr to front *)
		 Prev^.Next := TempPtr^.Next ;
		 TempPtr^.Next := ListHead ;
		 ListHead := TempPtr ;
	      END ;
              RETURN  (* get out of here! *)
           ELSE
	      Prev    := TempPtr ;
              TempPtr := TempPtr^.Next
           END ;
        END ;
        (* should NOT get here if lists are NOT corrupted *)
        ProgramErrorAndHalt( 'GetSCInfo: Special Character code not found in list' ) ;
     END GetSCInfo ;

  BEGIN (* ProcessLine *)

     cm.ModeIn := '0'; cm.ModeOut := '0';
     XlateLine( Int2FAlp, WordSepCode, IntLine, cm, TextLen, IntLenD, NumbSeq,
                EnoughData, AlphaText );
     CurPos := 0 ;
     IntLinePos := 0 ;
     IF NOT ContInLine THEN
        StrippedLine[0] := 0C;
     END ;
     ContInLine := FALSE ;
     IF FileData.WordForm = RAW THEN
        ProcessWord := ProcessCollectedWord ;
     ELSE
        ProcessWord := ProcessCollectedLemma ;
     END ;
     WHILE (CurPos < TextLen) DO  (* was "<=" since now strings are zero based *)
        CASE ColStatus OF
           WordLook:
              CASE TypeOfChar[ AlphaText[CurPos] ] OF
                 Letter, RetDiac:
                    WSP := 0 ;
                    (* VWordLogEntry := VLastLogEntry ; *)
                    ColStatus := InWord ;
                    StrippedWordBeginPos := Length( StrippedLine ) ;

                       |
                 NullChar, NonRetDiac:
                    (* the following is a duplicate of AdvancePointers() to
                       improve performance *)
		    INC( IntLinePos, IntLenD[CurPos].Int ) ;
		    INC( CurPos ) ;|
                 IgnBrkEnd, RefBrkEnd, LabelEnd:
                    (*RES OLD MSG 133
                    Ending symbol "%0" was found unexpectedly.
                    *)
                    Slice( symbol, IntLine, IntLinePos, IntLenD[CurPos].Int ) ;
                    MsgString( symbol, 0 ) ;
                    PutLineMsg( (*RES REM INS*) 133, Warning, Ch ) ;
                    TagInLine := TRUE ;
                    AdvancePointers() |
                 IgnBrkStart, IgnBrkStEnd:
                    GetSCInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, IgnoreBrkList ) ;
                    TagInLine := TRUE ;
                    ColStatus := IgnoreText ;
                    IF TypeOfChar[ AlphaText[CurPos] ] = IgnBrkStart THEN
                       NotSupText := FALSE ;
                    END ;
                    AdvancePointers() |
                 RefBrkStart, RefBrkStEnd:
                    GetSCInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, RefBrkList ) ;
                    TagInLine := TRUE ;
                    ColStatus := ReferenceText ;
                    RefStatus := RefIdLook ;
                    FirstWarning := TRUE ;
                    IF TypeOfChar[ AlphaText[CurPos] ] = RefBrkStart THEN
                       NotSupText := FALSE ;
                    END ;
                    AdvancePointers() |
                 LabelStart, LabelStEnd:
                    GetLabelInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, LabPtr ) ;
                    ColStatus := LabelText ;
                    TagInLine := TRUE ;
                    LabStatus := LabFieldLook ;
                    FirstWarning := TRUE ;
                    IF TypeOfChar[ AlphaText[CurPos] ] = LabelStart THEN
                       NotSupText := FALSE ;
                    END ;
                    AdvancePointers() |
                 Counter:
(*                    GetCounterInfo( AlphaText[CurPos], NotSupText, CharCounter ) ;
*)
                    ColStatus := CounterText ;
                    AdvancePointers() |
                 BYUStart:
                    TagInLine := TRUE ;
                    ColStatus := BYUText ;
                    BYUStatus := BYURef ;
                    IF TypeOfChar[ AlphaText[CurPos] ] = BYUStart THEN
                       NotSupText := FALSE ;
                    END ;
                    AdvancePointers() ;
                 ELSE (* ignore character [only thing left are Continuation & HighKey *)
                    AdvancePointers() ;
              END ;  (* CASE TypeOfChar[ AlphaText[CurPos] ] OF *)
              |
           InWord:
              CASE TypeOfChar[ AlphaText[CurPos] ] OF
                 Letter, RetDiac:
                    WordStore[WSP] := AlphaText[CurPos] ;
                    INC( WSP ) ;
                    (* the following is a duplicate of AdvancePointers() to
                       improve performance *)
		    INC( IntLinePos, IntLenD[CurPos].Int ) ;
		    INC( CurPos ) ;|
                 NonRetDiac:
		    INC( IntLinePos, IntLenD[CurPos].Int ) ;
		    INC( CurPos ) ;|
                 ContinuationChar:
                    ColStatus := ContSkipBlanks ;
                    AdvancePointers()  |
                 IgnBrkStart, IgnBrkStEnd:
                    GetSCInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, IgnoreBrkList ) ;
                    IF WordSep THEN
                       WordStore[WSP] := 0C ;
                       ProcessWord(WordStore) ;
                       ColStatus := WordLook ; (* which determines next action *)
                    ELSE  (* new state to ignore text ... within word *)
                       ColStatus := IgnoreText ;
                       IgnTextInWord := TRUE ;
                       AdvancePointers() ;
                    END;
                    IF TypeOfChar[ AlphaText[CurPos] ] = IgnBrkStart THEN
                       NotSupText := FALSE ;
                    END ; |
                 RefBrkStart, RefBrkStEnd:
                    GetSCInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, RefBrkList ) ;
                    IF WordSep THEN
                       WordStore[WSP] := 0C ;
                       ProcessWord(WordStore) ;
                       ColStatus := WordLook ; (* which determines next action *)
                    ELSE
                       ColStatus := ReferenceText ;
                       RefStatus := RefIdLook ;
                       RefTextInWord := TRUE ;
                       AdvancePointers() ;
                    END;
                    IF TypeOfChar[ AlphaText[CurPos] ] = RefBrkStart THEN
                       NotSupText := FALSE ;
                    END ;
                 ELSE  (* its a word separator! *)
                    WordStore[WSP] := 0C ;
                    ProcessWord(WordStore) ;
                    ColStatus := WordLook ; (* which determines next action *)
              END ;
              |
           ContSkipBlanks:
              IF TypeOfChar[ AlphaText[CurPos] ] = NullChar THEN
                 AdvancePointers() ;
              ELSE
                 ColStatus := InWord  (* go back to collecting word *)
              END ;
              |
           IgnoreText:
              IF AlphaText[CurPos] = EndChar THEN
                 AdvancePointers() ;
                 NotSupText := TRUE ;
                 IF IgnTextInWord THEN
                    IgnTextInWord := FALSE ;
                    ColStatus := InWord  (* go back to InWord *)
                 ELSE
                    ColStatus := WordLook
                 END ;
              ELSE
                 AdvancePointers()
              END ;
              |
           ReferenceText:
              CASE RefStatus OF
                 RefIdLook:
                    IF AlphaText[CurPos] = EndChar THEN
                       (*RES OLD MSG 134
                       A Reference ID seems to be missing from the text.
                       *)
                       PutLineMsg( (*RES REM INS*) 134, Error, Ch ) ;
                       IF RefTextInWord THEN
                          RefTextInWord := FALSE ;
                          ColStatus := InWord ;
                       ELSE
                          ColStatus := WordLook ;
                       END ;
                       AdvancePointers() ;
                       NotSupText := TRUE ;
                    ELSE
                       CASE TypeOfChar[ AlphaText[CurPos] ] OF
                          Letter, RetDiac:
                             IdP := 0 ;
                             IntP := 0 ;
                             RefStatus := RefId
                          ELSE  (* ignore them *)
                             AdvancePointers()
                       END ;
                    END |
                 RefId:
                    IF AlphaText[CurPos] = EndChar THEN
                       PutLineMsg( NullRefFieldRes , Warning, Ch ) ;
                       IF RefTextInWord THEN
                          RefTextInWord := FALSE ;
                          ColStatus := InWord ;
                       ELSE
                          ColStatus := WordLook ;
                       END ;
                       (* process as null reference *)
                       RefIdName[IdP] := 0C ;
                       IntName[IntP]  := 0C ;
                       RefStr[0] := 0C ;
                       KeyStr[0] := 0C ;
                       AdvancePointers() ;
                       NotSupText := TRUE ;
                    ELSE
                       CASE TypeOfChar[ AlphaText[CurPos] ] OF
                          Letter, RetDiac:
                             Move( ADR(IntLine[IntLinePos]), ADR(IntName[IdP]),
                                 IntLenD[CurPos].Int ) ;
                             INC( IntP, IntLenD[CurPos].Int ) ;
                             RefIdName[IdP] := AlphaText[CurPos] ;
                             INC( IdP ) ;
                             AdvancePointers()  |
                          NonRetDiac, ContinuationChar:
                             AdvancePointers()
                          ELSE  (* its a word separator! *)
                             RefIdName[IdP] := 0C ;
                             IntName[IntP]  := 0C ;
                             RefStatus := RefFieldLook ;
                       END ;
                    END |
                 RefFieldLook:
                    IF AlphaText[CurPos] = EndChar THEN
                       PutLineMsg( NullRefFieldRes , Warning, Ch ) ;
                       IF RefTextInWord THEN
                          RefTextInWord := FALSE ;
                          ColStatus := InWord ;
                       ELSE
                          ColStatus := WordLook ;
                       END ;
                       AdvancePointers() ;
                       NotSupText := TRUE ;
                       (* process as null reference *)
                       RefIdName[IdP] := 0C ;
                       IntName[IntP]  := 0C ;
                       RefStr[0] := 0C ;
                       KeyStr[0] := 0C ;
                    ELSIF IntLine[IntLinePos] <> Space THEN
                       IdP := 0 ;
                       Move( ADR(IntLine[IntLinePos]), ADR(RefStr[IdP]),
                                 IntLenD[CurPos].Int ) ;
                       INC( IdP, IntLenD[CurPos].Int ) ;
                       KeyIdP := 0 ;
                       KeyStr[KeyIdP] := AlphaText[CurPos] ;
                       INC( KeyIdP ) ;
                       AdvancePointers() ;
                       RefStatus := RefField
                    ELSE  (* ignore them *)
                       AdvancePointers()
                    END |
                 RefField:
                    IF AlphaText[CurPos] = EndChar THEN
(* L.P.                    IF KeyStr[KeyIdP-1] = WordSepCode THEN
                          DEC( KeyIdP ) (* remove trailing word separator *)
                       END; *)
                       KeyStr[KeyIdP] := 0C ;
                       RefStr[IdP] := 0C ;
                       Append( IntName, ' ' );
                       Prepend( IntName, ' ') ;
                       IF Compare( ' POS ', IntName ) = 0 THEN (* clean up later *)
                          Copy( PS, RefStr ) ;
                       ELSIF Pos( ' LEMMA RAW CONCEPT MODERN', IntName ) < 20 THEN
                          Copy( TAG, RefStr ) ;
                       END ;
                       AdvancePointers() ;
                       NotSupText := TRUE ;
                       IF RefTextInWord THEN
                          RefTextInWord := FALSE ;
                          ColStatus := InWord ;
                       ELSE
                          ColStatus := WordLook ;
                       END ;
                    ELSE
                       IF (IdP+IntLenD[CurPos].Int < MaxStringLen) AND (KeyIdP < MaxStringLen) THEN
                          KeyStr[KeyIdP] := AlphaText[CurPos] ;
                          INC( KeyIdP ) ;
                          Move( ADR(IntLine[IntLinePos]), ADR(RefStr[IdP]),
				IntLenD[CurPos].Int ) ;
                          INC( IdP, IntLenD[CurPos].Int ) ;
                       ELSIF FirstWarning THEN
                          (*RES OLD MSG 205
                          Reference field for "%0" is too long.
                          *)
                          MsgString( IntName, 0 ) ;
                          PutLineMsg( (*RES REM INS *) 205, Warning, Ch ) ;
                          FirstWarning := FALSE ;
                       END ;
                       AdvancePointers() ;
                    END ;
              END ;  (* CASE RefStatus OF *)
              |
           LabelText:
        CASE LabStatus OF
           LabFieldLook:
              IF AlphaText[CurPos] = EndChar THEN
                 (*RES OLD MSG 130
                 No value specified within Label.
                 *)
                 PutLineMsg( (*RES REM INS*) 130 , Warning, Ch ) ;
                 ColStatus := WordLook ;
                 AdvancePointers() ;
                 NotSupText := TRUE ;
                 LabStr[0] := 0C ;
                 KeyStr[0] := 0C ;
              ELSIF (IntLine[IntLinePos] <> Space) OR (IntLenD[CurPos].Int <> 1) THEN
                 (* this symbol is not a blank -- start collecting *)
                 IdP := 0 ;
                 Move( ADR(IntLine[IntLinePos]), ADR(LabStr[IdP]),
			   IntLenD[CurPos].Int ) ;
                 INC( IdP, IntLenD[CurPos].Int ) ;
                 KeyIdP := 0 ;
                 KeyStr[KeyIdP] := AlphaText[CurPos] ;
                 INC( KeyIdP ) ;
                 AdvancePointers() ;
                 LabStatus := LabField
              ELSE  (* ignore them *)
                 AdvancePointers() ;
              END ;  |
           LabField:
              IF AlphaText[CurPos] = EndChar THEN
                 KeyStr[KeyIdP] := 0C ;
                 LabStr[IdP] := 0C ;
                 AdvancePointers() ;
                 NotSupText := TRUE ;
                 ColStatus := WordLook
              ELSE
                 (* suppress multiple spaces to one code *)
                 IF (KeyIdP < MaxStringLen) AND (IdP+IntLenD[CurPos].Int < MaxStringLen) THEN
                    KeyStr[KeyIdP] := AlphaText[CurPos] ;
                    INC( KeyIdP ) ;
                    Move( ADR(IntLine[IntLinePos]), ADR(LabStr[IdP]),
			  IntLenD[CurPos].Int ) ;
                    INC( IdP, IntLenD[CurPos].Int ) ;
                 ELSIF FirstWarning THEN
                    (*RES OLD MSG 204
                    Label field "%0" is too long.
                    *)
                    LabStr[MaxStringLen] := 0C ;
                    MsgString( LabStr, 0 ) ;
                    PutLineMsg( (*RES REM INS *) 204, Warning, Ch ) ;
                    FirstWarning := FALSE ;
                 END ;
                 AdvancePointers()
              END ;
        END ;  (* CASE LabStatus OF *)
		|
           BYUText:
        CASE BYUStatus OF
           BYURef:
              IF IntLine[IntLinePos] <> Space THEN
                 BYURefCode := AlphaText[CurPos] ;
                 Move( ADR(IntLine[IntLinePos]), ADR(IntName[0]),
			   IntLenD[CurPos].Int ) ;
		 IntName[ IntLenD[CurPos].Int ] := 0C ; (* since only single char names *)
                 BYUStatus := BYUField ;
                 IdP := 0 ;
                 KeyIdP := 0 ;
                 AdvancePointers()
              ELSE
                 (*RES OLD MSG 131
                 An unexpected BYU Marker was found.
                 *)
                 PutLineMsg( (*RES REM INS*) 131 , Error, Ch ) ;
                 ColStatus := WordLook
              END  |
           BYUField:
              IF (IntLine[IntLinePos] <> Space) AND (IntLine[IntLinePos] <> 15C) AND
		 (TypeOfChar[AlphaText[CurPos]] <> BYUStart) THEN
		 (* stop collecting when reach a space or end of line or another BYU marker *)
                 KeyStr[KeyIdP] := AlphaText[CurPos] ;
                 INC( KeyIdP ) ;
                 Move( ADR(IntLine[IntLinePos]), ADR(BYUFieldStr[IdP]),
			   IntLenD[CurPos].Int ) ;
                 INC( IdP, IntLenD[CurPos].Int ) ;
                 AdvancePointers()
              ELSE
                 KeyStr[KeyIdP]   := 0C ;
                 BYUFieldStr[IdP] := 0C ;
                 IF BYUFieldStr[0] = 0C THEN
                    (*RES OLD MSG 132
                    An empty BYU reference was found.
                    *)
                    PutLineMsg( (*RES REM INS*) 132 , Error, Ch ) ;
                 END ;
                 (* Note: use the "untranslated" form of BYU reference name to maintain *)
                 (* case sensitivity.  *LP*						*)
                 ColStatus := WordLook
              END
        END ;  (* CASE BYUStatus OF *)
		|
           CounterText:
	      ColStatus := WordLook ;
	      NotSupText := TRUE ;
        END ;  (* CASE ColStatus OF *)
     END ; (* WHILE (CurPos <= TextLen) DO *)

     CASE ColStatus OF
        ReferenceText:
           (*RES OLD MSG 92
           A Reference seems to be split over more than one line.
           It was ignored.
           *)
           PutLineMsg( (*RES REM INS*) 92 , Warning, Ch);
           ColStatus := WordLook ;
      | LabelText:
           (*RES OLD MSG 93
           A Label seems to be split over more than one line. It was ignored.
           *)
           PutLineMsg( (*RES REM INS*) 93 , Warning, Ch);
           ColStatus := WordLook ;
        ELSE (* do nothing *)
     END;

   END ProcessLine ;


(*
PROCEDURE WriteAllStringsToDB() ;
  VAR
     DummyStr : ARRAY [0..3] OF CHAR ;
     EndPos   : CARDINAL ;
     VStrPtr  : VirtualAddrType ;
  BEGIN
     InitAddPtrDataToDB() ;
     BeginStr := HRecNo ;

     (* -- loop for each balanced tree string -- *)
     DoItem := WriteStr ;
     LoopAllStrs( DoItem ) ;
     EndStr := HRecNo ;
     EndPos := HRecPos ;
     FinishAddPtrDataToDB() ;

     (* now write the record information about the strings *)
     DoItem := WriteStrRec ;
     NoStrRecs := 0 ;
     BeginStrRec := HRecNo ;
     LoopAllStrs( DoItem ) ;
     DummyStr[0] := CHR( EndStr - BeginStr ) ;
     DummyStr[1] := CHR( EndPos ) ;
     DummyStr[2] := DummyStr[0] ;
     DummyStr[3] := DummyStr[1] ;
     VStrPtr  := VirtNil ;
     WriteStrRec( VStrPtr, VStrPtr (* dummy args *), 0, DummyStr ) ;
     DEC( NoStrRecs ) ; (* compensate for dummy header string record *)
  END WriteAllStringsToDB ;
*)

PROCEDURE WriteF2Message;
VAR Str: ARRAY[0..80] OF CHAR;
BEGIN
   (*RES OLD MSG 173
   ------------------
   *)
   GetResMessage( (*RES REM INS *) 173, Str ) ;
   ClearAndWriteTextWindow( Str );
   (*RES OLD MSG 174
   Display input text disabled.  Press F2 to restart display text again.
   *)
   GetResMessage( (*RES REM INS *) 174, Str ) ;
   WriteTextWindow( Str ) ;
END WriteF2Message;

  BEGIN (* ProcessText *)

     FirstWarning := TRUE ;
     ReadFlag := TRUE ;
     FoldFromInput := FALSE ;
     ContInLine    := FALSE ;

     GetXlationType( FileData.InputFileName, Mode ) ;
     IF Mode[0] = 0C THEN Copy(Mode,FILEText) END;
     IF NOT XOpenInput( FileData.InputFileName, TXTExtension , Mode, InputFileID, ErrorMsg ) THEN
        MsgString( FileData.InputFileName, 0 ) ;
        MsgString( ErrorMsg, 0 ) ;
        PutResError( FileErrorRes ) ;
(* L.P.      XClose( InputFileID ) ; *)
        RETURN FALSE ;
     END ;
     InFileLen := FIO.Size(InputFileID.ID.FileID) DIV VAL(LONGCARD, 100) ;
     IF FIO.IOresult() <> 0 THEN
        ProgramErrorAndHalt('Fatal error in ProcText: getting file length');
     END;
     (* set ShowTextLine to display percentage at every % of file ratio
	   assume average line length of 70 chars			   *)
     ShowTextCount := VAL(CARDINAL, InFileLen DIV VAL(LONGCARD, 70) ) ;
     IF ShowTextCount = 0 THEN
        ShowTextCount := 1      (* for small files *)
     END;
     RemoveExtension( FileData.InputFileName, ErrorFileName ) ;
     IF NOT XOpenOutput(ErrorFileName, ERRExtension, FILEText, ErrorFile, ErrorMsg) THEN
        MsgString( ErrorFileName, 0 ) ;
        MsgString( ErrorMsg, 0 ) ;
        PutResError( FileErrorRes ) ;
(*      XClose( InputFileID ) ; *)
        RETURN FALSE ;
     END ;
(*     IF NOT XOpenOutput(FileData.StrippedFileName, StrippedExtension, FILEText, StrippedFileID, ErrorMsg ) THEN
        MsgString( FileData.StrippedFileName, 0 ) ;
        MsgString( ErrorMsg, 0 ) ;
        PutResError( FileErrorRes ) ;
(*      XClose( InputFileID ) ; *)
        RETURN FALSE ;
     END ;
     BCreate( TagFile, FileData.TagFileName, TRUE, IOResult ) ;
     IF IOResult <> OK THEN
        MsgString( FileData.TagFileName, 0 ) ;
        MsgString( ErrorMsg, 0 ) ;
        PutResError( FileErrorRes ) ;
(*      XClose( InputFileID ) ; *)
        RETURN FALSE ;
     END ;
     BCreate( TempTagFile, FileData.TempTagFileName, TRUE, IOResult ) ;
     IF IOResult <> OK THEN
        MsgString( FileData.TempTagFileName, 0 ) ;
        MsgString( ErrorMsg, 0 ) ;
        PutResError( FileErrorRes ) ;
(*      XClose( InputFileID ) ; *)
        RETURN FALSE ;
     END ;
     BCreate( RefFile, FileData.RefFileName, TRUE, IOResult ) ;
     IF IOResult <> OK THEN
        MsgString( FileData.RefFileName, 0 ) ;
        MsgString( ErrorMsg, 0 ) ;
        PutResError( FileErrorRes ) ;
(*      XClose( InputFileID ) ; *)
        RETURN FALSE ;
     END ;
   WrStr( RefFile, 'Input file : ', IOResult ) ;
   WrStr( RefFile, FileData.InputFileName, IOResult) ;
   WrLn( RefFile, IOResult ) ;
   TempLong := VAL( LONGINT, month ) ;
   IntToStr( TempLong, TempStr, 10, Result) ;
   WrStr( RefFile, TempStr , IOResult ) ;
   WrStr( RefFile, '/' , IOResult ) ;
   TempLong := VAL( LONGINT, day ) ;
   IntToStr( TempLong, TempStr, 10, Result) ;
   WrStr( RefFile, TempStr , IOResult ) ;
   WrStr( RefFile, '/' , IOResult ) ;
   TempLong := VAL( LONGINT, year ) ;
   IntToStr( TempLong, TempStr, 10, Result) ;
   WrStr( RefFile, TempStr , IOResult ) ;
   WrLn( RefFile, IOResult ) ;
   WrStr( RefFile, 'File Size : ', IOResult ) ;
   TempLong := FIO.Size( InputFileID.ID.FileID ) ;

   CardToStr( TempLong, TempStr, 10, Result) ;
   WrStr( RefFile, TempStr , IOResult ) ;
   WrLn( RefFile, IOResult ) ;

*)
(*     InitWordColl() ;

     InitAllStrings();

     InitLogList() ;

     BeginText := HRecNo ;
*)
     Continue := TRUE ;
     NoMoreMsg    := FALSE ;
     NoOfErrors   := 0 ;
     PutErrorCount( NoOfErrors ) ;
     NoOfWarnings := 0 ;
     InputLineNo  := 0 ;
     NotSupText   := TRUE ;
     IgnTextInWord := FALSE ;
     RefTextInWord := FALSE ;
     CurrTokenPos := 0 ;
     ColStatus := WordLook ;
     Ch := 'C' ;
     WSP := 0 ;

     IF NOT DisplayText THEN WriteF2Message END ;

     WHILE Continue AND ReadLine( InputLine ) DO
        IF KeyPressed() THEN
           GetKeyStroke(Ch,Extended);
           IF (Ch = 33C) AND (NOT Extended) THEN  (* ESC character *)
	      (*<Production*)
              (*RES OLD CHE 1
              Ending Options: C)ontinue, A)bort, F)inish-Now:
              = C A F
              *)
              ResAskUser( (*RES REM INS *) 1, 'CAF', Ch ) ;
	      (*Production>*)

	      (*<Debug
              (*RES OLD CHE 6
              Ending Options: C)ontinue, A)bort, F)inish-Now:
              = C A F T
              *)
              ResAskUser( (*RES REM INS *) 6, 'CAFT', Ch ) ;
	      IF Ch = 'T' THEN
	         DoTrace := NOT DoTrace ;
		 Ch := 'C' ; (* to continue *)
	      END ;
	      Debug>*)
	
              IF Ch = 'A' THEN
	(*	 ReleasePage( VCurrTokenArray, CurrTokenArray ) ;
		 ReleasePage( VLastLogEntry, Dummy ) ;
        *) 	
	         FreeHashMemory() ;
		
                 RETURN FALSE
              END ;
              Continue := (Ch = 'C') ;
           ELSIF Extended AND (Ch = F2) THEN
	      DisplayText := NOT DisplayText ;
	      IF NOT DisplayText THEN WriteF2Message END ;
           ELSE
              Ch := 'C' ; (* still want to continue *)
              Beep
           END ;
           IF NOT (Extended AND (Ch = F2)) THEN
              WHILE KeyPressed() DO Read( Ch )  END ;  (* flush keybord buffer *)
           END ;
        END ;
        IF Continue THEN
(*           ActRecNo := HRecNo ; *)
           ProcessLine( InputLine ) ;
           IF Ch = 'A' THEN  (* abort from error in text coding etc. *)
(*	      ReleasePage( VCurrTokenArray, CurrTokenArray ) ;
	      ReleasePage( VLastLogEntry, Dummy ) ;
*)	
	      FreeHashMemory() ;

              RETURN FALSE
           END ;
           Continue := (Ch = 'C') OR ((Ch = F2) AND Extended) ;
        END ;
     END ;
     BClose( RefFile, IOResult ) ;
     (* display final percentage read *)
     Percentage :=
             VAL(CARDINAL,FIO.GetPos( InputFileID.ID.FileID ) DIV InFileLen);
     PutRecordNumber( RecordNumber ) ;
     PutTypeCount( TypeNumber ) ;
     PutTokenCount( TokenNumber ) ;
     PutPercentage( Percentage, TRUE ) ;
     (*RES OLD MSG 491
     This is the Word Sort Phase... Please Wait.
     *)
     PutRunStatus( (*RES REM INS*) 491 );
(*     ALLOCATE( FinalWord , TSIZE( WordPtr ) ) ;
     Lib.Fill( FinalWord, TSIZE( WordPtr ) , 255 ) ;
     LSortRelease( FinalWord^ ) ; *)

  (*   ReleasePage( VCurrTokenArray, CurrTokenArray ) ;
  *)
     XClose(ErrorFile);
(*     XClose(StrippedFileID); *)
     XClose(InputFileID);
(*     WrLn( TagFile, IOResult ) ;
     WrLn( TagFile, IOResult ) ;
     WrLn( TagFile, IOResult ) ;
     WrStr( TagFile, 'Number of Words : ' , IOResult ) ;
     CardToStr( TokenNumber , TempStr , 10 , Result ) ;
     WrStr( TagFile, TempStr , IOResult ) ;
     WrLn( TagFile, IOResult ) ;
     WrStr( TagFile, 'Number of Tags : ' , IOResult ) ;
     CardToStr( NoTags , TempStr , 10 , Result ) ;
     WrStr( TagFile, TempStr , IOResult ) ;
     WrLn( TagFile, IOResult ) ;
     WrStr( TagFile, 'Number of Continuation Characters : ' , IOResult ) ;
     CardToStr( NoConts , TempStr , 10 , Result ) ;
     WrStr( TagFile, TempStr , IOResult ) ;
     WrLn( TagFile, IOResult ) ;
     WrStr( TagFile, 'Number of Lines : ' , IOResult ) ;
     CardToStr( LONGCARD(InputLineNo) , TempStr , 10 , Result ) ;
     WrStr( TagFile, TempStr , IOResult ) ;
     WrLn( TagFile, IOResult ) ;
     WrLn( TagFile, IOResult ) ;
     WrLn( TagFile, IOResult ) ;
     WrStr( TagFile , 'Alphabetical list of tags : ' , IOResult ) ;
     WrLn( TagFile , IOResult ) ;
     WrLn( TagFile , IOResult ) ;

     BClose( TagFile, IOResult ) ;
     BClose( TempTagFile, IOResult ) ;
*)
     IF (NoOfErrors = 0) AND (NoOfWarnings = 0) THEN
        (* erase error file *)
        BDelete( ErrorFileName, IOResult ) ;
     END ;
(*     EndTextRec := HRecNo ;
     EndTextIdx := HRecPos ;
     WriteDBRec ;

     WriteAllStringsToDB() ;

     WriteLogListToDB() ;
*)
     RETURN TRUE
  END ProcessText ;


BEGIN
	DisplayText  := TRUE ;
	NoWords      := 0 ;
	NoConts      := 0 ;
	NoTags       := 0 ;
END ProcTextSource .
