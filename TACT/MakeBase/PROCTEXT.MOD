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

IMPORT Str, Lib;
FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR ;
FROM KeyTranslation IMPORT FILEText;
FROM StringIO IMPORT SWriteString, SWriteCard ;
FROM StringsData IMPORT
  (* Types *) StringRec, StringRecPtr,
  (* Procs *) InitStrings, LocateStr, WriteStringsToDB ;
FROM WordProcessing IMPORT
  (* Procs *) InitWordColl, ProcessCollectedWord ;
FROM VirtualMemory IMPORT
  (* Procs *) (* m.s. ReleasePage , *) IsEqual, MakeReal, (* m.s. MarkDirty, *)
  (* Vars  *) VirtNil,
  (* Type  *) VirtualAddrType, VirtPageStorePtr ;
FROM VirtHash IMPORT
  (* Procs *) FreeHashMemory ;
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
FROM HyperDataModel IMPORT
  (* Const *) HyperLength, PastHeader, HNoTokens,
              HNoPDBWords, BaseHTypeLen,
  (* Types *) HyperData;
FROM LogFile IMPORT
  (* Vars  *) VLastLogEntry, VWordLogEntry, StringsStartIndex,
  (* Procs *) InitLogList, AddNoToLogList, AddStrToLogList, WriteLogListToDB ;
IMPORT Utils ; (* for ReadLine *)
FROM Utils IMPORT
  (* Procs  *) Beep, GetXlationType, RemoveExtension, BDelete ;
FROM UtilsTwo IMPORT IOErrorMessage, InsufficientData, OK;
FROM Translations IMPORT
  (* Type  *) XFileType, XlateStrAny, CurrentModeType,
  (* Vars  *) Int2FAlp, LenD,
  (* Procs *) XClose, XOpenInput, XReadLine, XlateLine,
              XOpenOutput, XWriteLine ;
FROM GlobalDefs IMPORT
  (* Const *) MaxStringLen, TXTExtension, ERRExtension,
  (* Type  *) StrAny, FileNameType, SequenceType ;
FROM StartUp IMPORT FileData, WantFolding ;
FROM KeyBase IMPORT
  (* Procs *) Read, KeyPressed, GetKeyStroke ;
FROM RunPan IMPORT
  (* Procs *) WriteTextWindow, PutRecordNumber, PutTokenCount, PutTypeCount,
		PutErrorCount, PutPercentage, ClearAndWriteTextWindow;
FROM DBFile IMPORT
  (* Vars  *) HRecord, HRecNo, HRecPos ,
  (* Procs *) WriteDBRec, AddTextToDB, FinishAddPtrDataToDB, InitAddPtrDataToDB ;
FROM WordBase IMPORT
  (* Types *) AlphaCharType,
  (* Vars  *) TypeOfChar,
  (* Procs *) FullToSortWord ;
FROM XlatUserInput IMPORT
  (* Const *) EolSymbol, WordSepCode, MaxNumbResets,
  (* Types *) IgnoreRefPtr, CounterPtr, CounterCharPtr, LabelPtr,
              RefBYUPtr, RefPosPtr, RefPosRecType,
  (* Vars  *) IgnoreBrkList, RefBrkList, CounterCharList, LabelList,
              RefList, BYUList, LineCounterPtr, PosRefList;
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
  StrItemProcess = PROCEDURE( VAR VirtualAddrType, VAR VirtualAddrType, CARDINAL, VAR ARRAY OF CHAR ) ;

CONST
  Space = ' ' ;
  SplitLineChar = 370C ;	(* 248 in STANDARD.CDF *)
  MaxLine       = 75 ; (* m.s. - max input line length *)
VAR
  DoItem        : StrItemProcess ;
  LastStr	: StringRecPtr ;

PROCEDURE LoopAllStrs( DoItem : StrItemProcess ) ;
  VAR
     TempPtr  : LabelPtr ;
     TempPPtr : RefPosPtr ;

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

     TempPPtr := PosRefList ;
     WHILE TempPPtr <> NIL DO
        IF (NOT TempPPtr^.Numeric) AND (TempPPtr^.StructID <> 0) THEN
           WITH TempPPtr^ DO
              DoItem( StrHeader, VLastStr, StructID, StrRecInfo ) ;
           END ;
        END ;
        TempPPtr := TempPPtr^.Next ;
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
(* m.s.     MarkDirty( VLastStr ) ;
     ReleasePage( VLastStr, LastStr ) ;
*)
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
     Lib.Move( ADR(ID), ADR(Str[0]), 2);
     Lib.Move( ADR(StrRecInfo), ADR(Str[2]), 4);
     AddTextToDB( Str, 6 ) ;
  END WriteStrRec ;

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
  ErrorMsg    : StrAny ;
  MsgPos      : CARDINAL ;
  ActRecNo    : CARDINAL ;
  WordStore   : StrAny ;
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
  FAStart       : CARDINAL ; (* m.s. *)
  InFileLine   : StrAny ; (* m.s. - moved from GetTextLine *)
  XFlag        : BOOLEAN ; (* m.s. *)

(*RES OLD MSG 101
File: %0 - %1.
*)

CONST
  FileErrorRes = (*RES REM INS *) 101 ;

(*RES OLD MSG 125
"%0" cannot be converted to a number.
*)
  NumbConvErrorRes = (*RES REM INS*) 125 ;

(*RES OLD MSG 126
A reference has a null field value.
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
(*    LenD    : XlateStrAny ; *)
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
         %0 Error options -- choose among C)ontinue, S)ilent continue, E)nd abruptly, F)inish Now:
         = C S E F
         *)
         MsgString(Str, 0);
         ResAskUser( (*RES REM INS *) 0, 'CSEF', Ch ) ; (* m.s. - res updated in messages directory *)
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
      Line: %0: "%1".
      *)
      MsgCard(InputLineNo,0);
      MsgString(InputLine,0);
      GetResMessage( (*RES REM INS*) 127, Str);
      WriteToErrorFile;
      Str[0] := 0C;
      WriteToErrorFile;
   END PutLineMsg ;

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

PROCEDURE ReadLine( VAR InputLine : StrAny ) : BOOLEAN ;
  VAR
     EnoughData : BOOLEAN ;
     al		: CARDINAL ;

  PROCEDURE GetTextLine( VAR InputLine : ARRAY OF CHAR ;
			 VAR IOResult	 : CARDINAL;
			 VAR al		 : CARDINAL ) ;
	VAR
	   I, J, K	: CARDINAL ;
	   ld, FAld    	: XlateStrAny ;
	   ns, FAal		: CARDINAL;
	   FoldedLine, FAFileLine	: StrAny ;
	   Folded	: BOOLEAN ;
	   ch		: CHAR ;
	   EndPos       : CARDINAL ;
	   OK           : BOOLEAN ;
           cm         : CurrentModeType;

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
(* m.s.             MarkDirty( cur^.VLastStr ) ;
             ReleasePage( cur^.VLastStr, LastStr ) ;
*)
          END ;
          LocateStr( alps, ints, Str.Length(ints), cur^.StrHeader, cur^.VLastStr ) ;
          MakeReal( cur^.VLastStr, LastStr ) ;
          LastStr^.CurWordNo := TokenNumber ;
(* m.s.          MarkDirty( cur^.VLastStr ) ;
          ReleasePage( cur^.VLastStr, LastStr ) ;
*)
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

	BEGIN
	   IF ReadFlag THEN
		ReadFlag := FALSE ;
		StartPos := 0 ;
		IF NOT Utils.ReadLine( InputFileID.ID, InFileLine, EnoughData, IOResult ) THEN
		   RETURN
		END ;
		INC( InputLineNo ) ;  (* corresponds to file line number *)
		Utils.TrimBlanks( InFileLine, InFileLine ) ;
         	XlateLine(InputFileID.XP, '?', InFileLine, InputFileID.ModeData,
			al, ld, ns, EnoughData, InFileLine ) ; (* m.s. *)
		LineLen := Str.Length( InFileLine )  ;
		PutRecordNumber( RecordNumber ) ;
		PutTypeCount( TypeNumber ) ;
		PutTokenCount( TokenNumber ) ;
		FAStart := 0 ;  (* m.s. *)
		IF (LineLen <> 0) AND NOT FoldFromInput THEN
		   INC( RecordNumber ) ;
		   ProcessCounter( LineCounterPtr ) ;
		ELSE
		   InputLine[0] := 0C ; (* m.s. - exit now *)
		   al := 0 ;
		   ReadFlag := TRUE ;
		   RETURN ;
		END ;
   	        Str.Append( InFileLine, EolSymbol ) ;
	        INC( LineLen ) ;
	   END ;
	   IF WantFolding THEN
	      IF (LineLen - StartPos) > MaxLine  THEN
                cm.ModeIn := '0'; cm.ModeOut := '0';
         	XlateLine(Int2FAlp, WordSepCode, InFileLine, cm,
			FAal, FAld, ns, EnoughData, FAFileLine ) ; (* m.s. *)
       		EndPos := StartPos + MaxLine ;
		OK := TRUE ;	
		XFlag := FALSE ;
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
                   INC( J, FAld[K].Int ) ; (* was ld *)
                   INC( K ) ;
		END ;
		IF (InFileLine[MaxLine+StartPos] = EolSymbol) OR
		   (InFileLine[MaxLine+1+StartPos] = EolSymbol) THEN (* unusual case where MaxLine char is a null char *)
		   I := LineLen;
		ELSIF I = StartPos THEN
		   (* unable to split line at MaxLine char boundary -- long word *)
                   I :=  LineLen ; (* m.s. - since line can't be split, don't try *)
		   (*RES OLD MSG 266
		   Warning: line cannot be split because it contains a word longer
		   than 75 characters.
		   *)
		   PutLineMsg( (*RES REM INS *) 266 , Warning, ch ) ;		
		END ;
		J := 0 ;
		FOR K := StartPos TO I DO
		   InputLine[J] := InFileLine[K] ;
		   INC( J ) ;
		END ;
		InputLine[J] := 0C ;
		StartPos := I + 1;
		IF I >= LineLen THEN
		   Folded   := FALSE ;
		   ReadFlag := TRUE ;
		   DEC( J, 2 ) ;
		   InputLine[J] := 0C ; (* m.s. - get rid of eol char *)
		ELSE
		   Folded   := TRUE ;
		END ;
	      ELSE
		J := 0 ;
		FOR K := StartPos TO (LineLen - 2) DO (* exclude eol char *)
		   InputLine[J] := InFileLine[K] ;
		   INC( J ) ;
		END ;
		InputLine[J] := 0C ;
		ReadFlag := TRUE ;
		Folded   := FALSE ;
(*		IF J = 0 THEN (* m.s. - empty line somehow, don't process *)
		  RETURN
		END ;
*)	      END ;
	      al := J - 1;
	   ELSE	
		ReadFlag := TRUE ;
		Str.Copy( InputLine, InFileLine ) ;
	   END ;
           IF PosRefList <> NIL THEN ProcessFixedPosRefs END;
	   IF WantFolding THEN
	      IF Folded THEN
		FoldFromInput := FALSE ;
		INC(al) ;
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
            Number := CARDINAL(Str.StrToCard(LabStr,10,Done));
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
(* m.s.	       MarkDirty( VLastStr ) ;
	       ReleasePage( VLastStr, LastStr ) ;
*)
	    END ;
            LocateStr( KeyStr, LabStr, LabLen, StrHeader, VStrPtr ) ;
	    (* could save next call by not releasing in LocateStr -- too much bother *)
	    MakeReal( VStrPtr, LastStr ) ;
	    LastStr^.CurWordNo := TokenNumber ;
(* m.s.	    MarkDirty( VStrPtr ) ;
	    ReleasePage( VStrPtr, LastStr ) ;
*)	
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
         IF Str.Compare( IdCode, TempList^.RefID ) = 0 THEN
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
                  Number := CARDINAL(Str.StrToCard(FieldStr,10,Done));
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
(* m.s.		     MarkDirty( VLastStr ) ;
		     ReleasePage( VLastStr, LastStr ) ;
*)
		  END ;
		
                  LocateStr( KeyStr, FieldStr, StrLen, StrHeader, VStrPtr ) ;
		  (* could save next call by not releasing in LocateStr -- too much bother *)
		  MakeReal( VStrPtr, LastStr ) ;
		  LastStr^.CurWordNo := TokenNumber ;
(* m.s.		  MarkDirty( VStrPtr ) ;
		  ReleasePage( VStrPtr, LastStr ) ;
*)
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
         Reference ID "%0" was not found.
         *)
         PutLineMsg( (*RES REM INS*) 128, Warning, Ch);
      ELSE
         (*RES OLD MSG 129
         BYU ID "%0" was not found.
         *)
         PutLineMsg( (*RES REM INS*) 129, Warning, Ch);
      END ;
   END ProcessRefBYU ;

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

  PROCEDURE AdvancePointers() ;
     BEGIN
        IF NotSupText THEN
           AddTextToDB( IntLine[IntLinePos], IntLenD[CurPos].Int ) ;
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
     WHILE (CurPos < TextLen) DO  (* was "<=" since now strings are zero based *)
        CASE ColStatus OF
           WordLook:
              CASE TypeOfChar[ AlphaText[CurPos] ] OF
                 Letter, RetDiac:
                    WSP := 0 ;
                    VWordLogEntry := VLastLogEntry ;
                    ColStatus := InWord ;
                    SWdRec    := HRecNo ;
                    SWdPos    := HRecPos ;
                    SWdRecNo  := RecordNumber ;  |
                 NullChar, NonRetDiac:
                    (* the following is a duplicate of AdvancePointers() to
                       improve performance *)
		    IF NotSupText THEN
			AddTextToDB( IntLine[IntLinePos], IntLenD[CurPos].Int ) ;
		    END ;
		    INC( IntLinePos, IntLenD[CurPos].Int ) ;
		    INC( CurPos ) ;|
                 IgnBrkEnd, RefBrkEnd, LabelEnd:
                    (*RES OLD MSG 133
                    An unexpected ending symbol "%0" was found.
                    *)
                    Str.Slice( symbol, IntLine, IntLinePos, IntLenD[CurPos].Int ) ;
                    MsgString( symbol, 0 ) ;
                    PutLineMsg( (*RES REM INS*) 133, Warning, Ch ) ;
                    AdvancePointers() |
                 IgnBrkStart, IgnBrkStEnd:
                    GetSCInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, IgnoreBrkList ) ;
                    ColStatus := IgnoreText ;
                    AdvancePointers() |
                 RefBrkStart, RefBrkStEnd:
                    GetSCInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, RefBrkList ) ;
                    ColStatus := ReferenceText ;
                    RefStatus := RefIdLook ;
                    FirstWarning := TRUE ;
                    AdvancePointers() |
                 LabelStart, LabelStEnd:
                    GetLabelInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, LabPtr ) ;
                    ColStatus := LabelText ;
                    LabStatus := LabFieldLook ;
                    FirstWarning := TRUE ;
                    AdvancePointers() |
                 Counter:
                    GetCounterInfo( AlphaText[CurPos], NotSupText, CharCounter ) ;
                    ColStatus := CounterText ;
                    AdvancePointers() |
                 BYUStart:
                    ColStatus := BYUText ;
                    BYUStatus := BYURef ;
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
		    IF NotSupText THEN
			AddTextToDB( IntLine[IntLinePos], IntLenD[CurPos].Int ) ;
		    END ;
		    INC( IntLinePos, IntLenD[CurPos].Int ) ;
		    INC( CurPos ) ;|
                 NonRetDiac:
                    AdvancePointers()  |
                 ContinuationChar:
                    ColStatus := ContSkipBlanks ;
                    AdvancePointers()  |
                 IgnBrkStart, IgnBrkStEnd:
                    GetSCInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, IgnoreBrkList ) ;
                    IF WordSep THEN
                       WordStore[WSP] := 0C ;
                       ProcessCollectedWord(WordStore, SWdRec, SWdPos, SWdRecNo) ;
                       ColStatus := WordLook ; (* which determines next action *)
                    ELSE  (* new state to ignore text ... within word *)
                       ColStatus := IgnoreText ;
                       IgnTextInWord := TRUE ;
                       AdvancePointers() ;
                    END   |
                 RefBrkStart, RefBrkStEnd:
                    GetSCInfo( AlphaText[CurPos], NotSupText, WordSep, EndChar, RefBrkList ) ;
                    IF WordSep THEN
                       WordStore[WSP] := 0C ;
                       ProcessCollectedWord(WordStore, SWdRec, SWdPos, SWdRecNo) ;
                       ColStatus := WordLook ; (* which determines next action *)
                    ELSE
                       ColStatus := ReferenceText ;
                       RefStatus := RefIdLook ;
                       RefTextInWord := TRUE ;
                       AdvancePointers() ;
                    END
                 ELSE  (* its a word separator! *)
                    WordStore[WSP] := 0C ;
                    ProcessCollectedWord(WordStore, SWdRec, SWdPos, SWdRecNo) ;
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
                 END
              ELSE
                 AdvancePointers()
              END ;
              |
           ReferenceText:
              CASE RefStatus OF
                 RefIdLook:
                    IF AlphaText[CurPos] = EndChar THEN
                       (*RES OLD MSG 134
                       A Reference ID seems to be missing.
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
                       ProcessRefBYU( RefIdName, IntName, KeyStr, RefStr, 0, RefType, RefList ) ;
                       AdvancePointers() ;
                       NotSupText := TRUE ;
                    ELSE
                       CASE TypeOfChar[ AlphaText[CurPos] ] OF
                          Letter, RetDiac:
                             Lib.Move( ADR(IntLine[IntLinePos]), ADR(IntName[IdP]),
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
                       ProcessRefBYU( RefIdName, IntName, KeyStr, RefStr, 0, RefType, RefList ) ;
                    ELSIF IntLine[IntLinePos] <> Space THEN
                       IdP := 0 ;
                       Lib.Move( ADR(IntLine[IntLinePos]), ADR(RefStr[IdP]),
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
(*                     IF KeyStr[KeyIdP-1] = WordSepCode THEN
                          DEC( KeyIdP ) (* remove trailing word separator *)
                       END; *)
                       KeyStr[KeyIdP] := 0C ;
                       RefStr[IdP] := 0C ;
                       AdvancePointers() ;
                       NotSupText := TRUE ;
                       ProcessRefBYU( RefIdName, IntName, KeyStr, RefStr, IdP, RefType, RefList ) ;
                       IF RefTextInWord THEN
                          RefTextInWord := FALSE ;
                          ColStatus := InWord ;
                       ELSE
                          ColStatus := WordLook ;
                       END ;
                    ELSE
(*                     (* suppress multiple spaces to one code *)
                       IF (AlphaText[CurPos] <> WordSepCode) OR (KeyStr[KeyIdP-1] <> WordSepCode) THEN
                          KeyStr[KeyIdP] := AlphaText[CurPos] ;
                          INC( KeyIdP ) ;
                       END ; *)

                       IF (IdP+IntLenD[CurPos].Int < MaxStringLen) AND (KeyIdP < MaxStringLen) THEN
                          KeyStr[KeyIdP] := AlphaText[CurPos] ;
                          INC( KeyIdP ) ;
                          Lib.Move( ADR(IntLine[IntLinePos]), ADR(RefStr[IdP]),
				IntLenD[CurPos].Int ) ;
                          INC( IdP, IntLenD[CurPos].Int ) ;
                       ELSIF FirstWarning THEN
                          (*RES OLD MSG 205
                          The Reference field for "%0" is too long.
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
                 This Label does not specify any value.
                 *)
                 PutLineMsg( (*RES REM INS*) 130 , Warning, Ch ) ;
                 ColStatus := WordLook ;
                 AdvancePointers() ;
                 NotSupText := TRUE ;
                 LabStr[0] := 0C ;
                 KeyStr[0] := 0C ;
                 ProcessLabel( KeyStr, LabStr, 0, LabPtr ) ;
              ELSIF (IntLine[IntLinePos] <> Space) OR (IntLenD[CurPos].Int <> 1) THEN
                 (* this symbol is not a blank -- start collecting *)
                 IdP := 0 ;
                 Lib.Move( ADR(IntLine[IntLinePos]), ADR(LabStr[IdP]),
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
                 ProcessLabel( KeyStr, LabStr, IdP, LabPtr ) ;
                 ColStatus := WordLook
              ELSE
                 (* suppress multiple spaces to one code *)
                 IF (KeyIdP < MaxStringLen) AND (IdP+IntLenD[CurPos].Int < MaxStringLen) THEN
                    KeyStr[KeyIdP] := AlphaText[CurPos] ;
                    INC( KeyIdP ) ;
                    Lib.Move( ADR(IntLine[IntLinePos]), ADR(LabStr[IdP]),
			  IntLenD[CurPos].Int ) ;
                    INC( IdP, IntLenD[CurPos].Int ) ;
                 ELSIF FirstWarning THEN
                    (*RES OLD MSG 204
                    The Label field "%0" is too long.
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
                 Lib.Move( ADR(IntLine[IntLinePos]), ADR(IntName[0]),
			   IntLenD[CurPos].Int ) ;
		 IntName[ IntLenD[CurPos].Int ] := 0C ; (* since only single char names *)
                 BYUStatus := BYUField ;
                 IdP := 0 ;
                 KeyIdP := 0 ;
                 AdvancePointers()
              ELSE
                 (*RES OLD MSG 131
                 An unexpected WCS marker was found.
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
                 Lib.Move( ADR(IntLine[IntLinePos]), ADR(BYUFieldStr[IdP]),
			   IntLenD[CurPos].Int ) ;
                 INC( IdP, IntLenD[CurPos].Int ) ;
                 AdvancePointers()
              ELSE
                 KeyStr[KeyIdP]   := 0C ;
                 BYUFieldStr[IdP] := 0C ;
                 IF BYUFieldStr[0] = 0C THEN
                    (*RES OLD MSG 132
                    An empty WCS Reference was Found.
                    *)
                    PutLineMsg( (*RES REM INS*) 132 , Error, Ch ) ;
                 END ;
                 (* Note: use the "untranslated" form of BYU reference name to maintain *)
                 (* case sensitivity.  *LP*						*)
                 ProcessRefBYU( IntName (* was BYURefCode *), IntName, KeyStr, BYUFieldStr, IdP, BYUType, BYUList ) ;
                 ColStatus := WordLook
              END
        END ;  (* CASE BYUStatus OF *)
		|
           CounterText:
              ProcessCounter( CharCounter^.ToCounterData ) ;
	      ColStatus := WordLook ;
	      NotSupText := TRUE ;
        END ;  (* CASE ColStatus OF *)
     END ; (* WHILE (CurPos <= TextLen) DO *)

     CASE ColStatus OF
        ReferenceText:
           (*RES OLD MSG 92
           A Reference that seems to be split between two lines has been ignored.
           *)
           PutLineMsg( (*RES REM INS*) 92 , Warning, Ch);
           ColStatus := WordLook ;
      | LabelText:
           (*RES OLD MSG 93
           A Label that seems to be split between two lines has been ignored.
           *)
           PutLineMsg( (*RES REM INS*) 93 , Warning, Ch);
           ColStatus := WordLook ;
        ELSE (* do nothing *)
     END;
  END ProcessLine ;

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

PROCEDURE WriteF2Message;
VAR Str: ARRAY[0..80] OF CHAR;
BEGIN
   (*RES OLD MSG 173
   ------------------
   *)
   GetResMessage( (*RES REM INS *) 173, Str ) ;
   ClearAndWriteTextWindow( Str );
   (*RES OLD MSG 174
   Display of text is disabled.  To restart Display, press F2.
   *)
   GetResMessage( (*RES REM INS *) 174, Str ) ;
   WriteTextWindow( Str ) ;
END WriteF2Message;

  BEGIN (* ProcessText *)
     FirstWarning := TRUE ;
     ReadFlag := TRUE ;
     FoldFromInput := FALSE ;

     GetXlationType( FileData.InputFileName, Mode ) ;
     IF Mode[0] = 0C THEN Str.Copy(Mode,FILEText) END;
     IF NOT XOpenInput( FileData.InputFileName, TXTExtension , Mode, InputFileID, ErrorMsg ) THEN
        MsgString( FileData.InputFileName, 0 ) ;
        MsgString( ErrorMsg, 0 ) ;
        PutResError( FileErrorRes ) ;
(*      XClose( InputFileID ) ; *)
        RETURN FALSE ;
     END ;
     InFileLen := FIO.Size(InputFileID.ID.FileID) DIV VAL(LONGCARD, 100) ;
     IF InFileLen = 0 THEN  (* m.s. - allow for very small files *)
       InFileLen := 1 ;
     END ;
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

     InitWordColl() ;

     InitAllStrings();

     InitLogList() ;

     BeginText := HRecNo ;

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

     IF NOT DisplayText THEN WriteF2Message END ;

     WHILE Continue AND ReadLine( InputLine ) DO
        IF KeyPressed() THEN
           GetKeyStroke(Ch,Extended);
           IF (Ch = 33C) AND (NOT Extended) THEN  (* ESC character *)
	      (*<Production*)
              (*RES OLD CHE 1
              Ending Options -- choose among C)ontinue, E)nd abruptly, F)inish Now:
              = C E F
              *)
              ResAskUser( (*RES REM INS *) 1, 'CEF', Ch ) ;
	      (*Production>*)

	      (*<Debug
              (*RES OLD CHE 6
              Ending Options -- choose one: C)ontinue, E)nd abruptly, F)inish Now:
              = C E F T
              *)
              ResAskUser( (*RES REM INS *) 6, 'CEFT', Ch ) ;
	      IF Ch = 'T' THEN
	         DoTrace := NOT DoTrace ;
		 Ch := 'C' ; (* to continue *)
	      END ;
	      Debug>*)
	
              IF Ch = 'E' THEN
(* m.s.		 ReleasePage( VCurrTokenArray, CurrTokenArray ) ;
		 ReleasePage( VLastLogEntry, Dummy ) ;
*)		 FreeHashMemory() ;
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
           ActRecNo := HRecNo ;
           ProcessLine( InputLine ) ;
           IF Ch = 'E' THEN  (* abort from error in text coding etc. *)
(* m.s.	      ReleasePage( VCurrTokenArray, CurrTokenArray ) ;
	      ReleasePage( VLastLogEntry, Dummy ) ;
*)	      FreeHashMemory() ;
              RETURN FALSE
           END ;
           Continue := (Ch = 'C') OR ((Ch = F2) AND Extended) ;
        END ;
     END ;
     (* display final percentage read *)
     Percentage :=
             VAL(CARDINAL,FIO.GetPos( InputFileID.ID.FileID ) DIV InFileLen);
     PutRecordNumber( RecordNumber ) ;
     PutTypeCount( TypeNumber ) ;
     PutTokenCount( TokenNumber ) ;
     PutPercentage( Percentage, TRUE ) ;
(* m.s.     ReleasePage( VCurrTokenArray, CurrTokenArray ) ; *)
     XClose(ErrorFile);
     XClose(InputFileID);
     IF (NoOfErrors = 0) AND (NoOfWarnings = 0) THEN
        (* erase error file *)
        BDelete( ErrorFileName, IOResult ) ;
     END ;
     EndTextRec := HRecNo ;
     EndTextIdx := HRecPos ;
     WriteDBRec ;

     WriteAllStringsToDB() ;

     WriteLogListToDB() ;

     RETURN TRUE
  END ProcessText ;

BEGIN
	DisplayText  := TRUE ;
END ProcTextSource .
