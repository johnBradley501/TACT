IMPLEMENTATION MODULE XlatUserInput ;

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

(* Changed by J.Bradley:
  (1) Changed FillChar to BlockClear (see below)
  (2) Changed ID counter usage for LineCounter and Word Counter types
  (3) Added "Preference field" to indicate order of names for references

Changed by J.Bradley June 3, 1992
I didn't see the need for the NameIdCounter and NameID to be separate
from StructID and StructIDCounter.  So I have eliminated NameIDCounter
by commenting out lines.  The old lines are labelled "*NIC*"  .. jb
*)

IMPORT Str;
FROM SYSTEM   IMPORT ADR,ADDRESS ;
FROM Storage  IMPORT ALLOCATE, DEALLOCATE ;
(* FROM StartUp  IMPORT WantFolding; *)
FROM Lib      IMPORT Fill;
FROM StringIO IMPORT SWriteString, SWriteCard ;
FROM VirtualMemory IMPORT VirtNil ;
FROM WordBase IMPORT
  (* Const *) NonRetDiacCode, ExtraCodeSep,
  (* Type  *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar, SortNoBitsPerChar,
  (* Procs *) FullToSortWord, SortToFullWord;
FROM Translations IMPORT
  (* Type   *) XlateTablePointer, HandleDuplicateType, XlateStrAny, CurrentModeType,
  (* Vars   *) Int2Alp, Alp2Int, Int2FAlp,
  (* Procs  *) InitialXlateData, InsertXlateData, EquateXlateData,
               XlateLine, DeleteXlateTable, DumpXlateTable ;
FROM AlphaPanel IMPORT
  (* const *) NoAlphaLines, NoRetDiLines, NoNonDiLines,
  (* vars  *) AlphaInfo;
FROM Utils IMPORT StandardizeCharName ;
FROM GetSequences IMPORT LookupIntName ;
FROM Lists IMPORT
  (* type   *)   ListPointer,
  (* proc   *)   GetData, MoveDown, SetToTop ;
FROM StructuralInfo IMPORT
  (* vars   *)   StructList,
  (* type   *)   StructInfoType, StructInfoDataType, StructInfoDataPntr,
  (* const  *)   NameFieldLen,
  (* procs  *)   IsStructDataEmpty;
FROM GlobalDefs IMPORT StrAny, SequenceType, MaxCharsInSeq ;
FROM STANDARD IMPORT
  (* Type  *) CharNameType,
  (* Const *) CharNameLength ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt ;
FROM SpecialCharacters IMPORT
  (* vars  *) SCList,
  (* Type  *) SpecialCharType, SpecialCharDataPntr,
  (* Procs *) IsSCDataEmpty ;
FROM ResMessages IMPORT
  (* proc *) MsgString, MsgCard, PutResError, PutResMessage, PutResWarning ;

(* ---- debugging ----- *LP*
FROM FileIO   IMPORT IOResultType,IOModeType;
FROM Utils    IMPORT Beep, BFile, BOpen, BCreate, BClose ;

VAR
    cm:         CurrentModeType;
    OutFile:    BFile;
    IOResult:   IOResultType;
 ---- debugging ----- *LP* *)
CONST
  RefDelimID = '$' ;
TYPE
   AlphaSelectType = (JustFullAlpha, BothAlpha) ;
VAR
   MsgPos     : CARDINAL;
   Message    : StrAny ;
   CodePoint  : CHAR ;
   DataPtr    : ADDRESS ;
   SCData     : SpecialCharDataPntr ;
   StructData : StructInfoDataPntr ;
(* NameIdCounter   : CARDINAL ; *NIC* *)
    WantFolding: BOOLEAN ;
   HeadCounterList : CounterPtr ; (* starting thread thru counters *)

CONST
	(*RES OLD MSG 84
	A duplicate or infinite loop has been Reset for "%0".
	*)
	ResInfiniteLoop = (*RES REM INS *) 84 ;
	(*RES OLD MSG 85
	There are more Counter Resets for "%0" than the limit of "%1".
	*)
	ResTooManyResets = (*RES REM INS *) 85  ;
	(*RES OLD MSG 90
	The Counter to which "%0" refers is incremented twice.
	*)
	ResIncTwice = (*RES REM INS *) 90 ;


PROCEDURE LookupName(VAR SortName: ARRAY OF CHAR (*read only*);
                     VAR NameRec : NamesTypePtr ) : BOOLEAN ;
VAR
   TempList  : NamesTypePtr ;
BEGIN
        TempList := NamesList ;
        WHILE (TempList <> NIL) AND (Str.Compare(TempList^.Name, SortName) < 0) DO
           TempList := TempList^.Next ;
        END ;
        IF (TempList <> NIL) AND (Str.Compare(TempList^.Name, SortName) = 0) THEN
           NameRec := TempList ;
           RETURN TRUE
        ELSE
           NameRec := NIL ;
           RETURN FALSE ;
        END ;
END LookupName;

PROCEDURE InsertToXlate( Sequence      : ARRAY OF CHAR ;
                         IntSeq        : ARRAY OF CHAR ;
                         AlphaSelector : AlphaSelectType ) : BOOLEAN ;
	(*RES OLD MSG 66
	The symbol "%0" appears twice.
	*)
   CONST
      ResDupMsg = (*RES REM INS *) 66 ;
   BEGIN
      IF AlphaSelector = BothAlpha THEN
         IF NOT InsertXlateData(Int2Alp, '0','0',
         Sequence, IntSeq, 1, GiveError, Message) THEN
            MsgString( Sequence, 0 ) ;
            PutResError(ResDupMsg) ;
            RETURN FALSE ;
         END ;
      END ;
      IF NOT InsertXlateData(Int2FAlp, '0','0',
	     Sequence, IntSeq, 1, GiveError, Message) THEN
         MsgString( Sequence, 0 ) ;
         PutResError( ResDupMsg ) ;
         RETURN FALSE ;
      END ;
      RETURN TRUE ;
   END InsertToXlate ;

PROCEDURE DeleteTables ;
   BEGIN
      DeleteXlateTable( Int2Alp ) ;
      DeleteXlateTable( Int2FAlp ) ;
   END DeleteTables ;

PROCEDURE BuildAlphabetXlate() : CARDINAL ;
   VAR
      I          : CARDINAL ;
      InBracket  : BOOLEAN ;
      ResetSCode : BOOLEAN ;
      SCodePoint : CHAR ;
      CharSeq    : SequenceType ;

   TYPE
      SymbolType = ( LetterSym, RetDiacSym, NonRetDiacSym, ContCharSym ) ;

   PROCEDURE InsertCode( Sequence   : SequenceType ;
                         SymbolKind : SymbolType ) : BOOLEAN ;
      VAR
         AlphaSeq : SequenceType ;
      BEGIN
         CASE SymbolKind OF
            LetterSym :
               INC( CodePoint ) ;
               Str.Copy( AlphaSeq, CodePoint ) ;
               TypeOfChar[CodePoint] := Letter ;
               IF ResetSCode THEN
                  SCodePoint := CodePoint
               END ;
               IF InBracket AND ResetSCode THEN
                  ResetSCode := FALSE
               END ;
               SimpAlphTable[CodePoint] := SCodePoint  |
            RetDiacSym :
               INC( CodePoint ) ;
               Str.Copy( AlphaSeq, CodePoint ) ;
               TypeOfChar[CodePoint] := RetDiac ;
               SimpAlphTable[CodePoint] := 1C |     (* <---- ???? *)
            NonRetDiacSym :
               TypeOfChar[NonRetDiacCode] := NonRetDiac;
               AlphaSeq[0] := NonRetDiacCode ;
               AlphaSeq[1] := 0C  |
            ContCharSym :
               INC( CodePoint ) ;
               TypeOfChar[CodePoint] := ContinuationChar ;
               Str.Copy( AlphaSeq, CodePoint ) ;
               Str.Append( Sequence, EolSymbol );
         END ; (* CASE SymbolKind OF *)
         IF NOT InsertToXlate( Sequence, AlphaSeq, BothAlpha ) THEN
            RETURN FALSE ;
         END ;
         IF (SymbolKind <> NonRetDiacSym) AND (SymbolKind <> ContCharSym) THEN
            IF NOT InsertXlateData(Alp2Int, '0','0',
            AlphaSeq, Sequence, Str.Length(Sequence), GiveError, Message) THEN
		(*RES OLD MSG 68
		There is an unexpected double occurrence of AlphaSeq!!  sequence: "%0".
		*)
	       MsgString( Sequence, 0 ) ;	(* *LP2* *)
               PutResError( (*RES REM INS *) 68 ) ;
               RETURN FALSE ;
            END
         END ;
         RETURN TRUE ;
      END InsertCode ;

   PROCEDURE ProcessAlphaLine( InputLine  : ARRAY OF CHAR ;
                               SymbolKind : SymbolType ) : BOOLEAN ;
      TYPE
         StateValues = (CharLook, RestChar, DoString, IntNameLook, IntNameGet) ;
      VAR
         LinePos       : CARDINAL ;
         State     : StateValues ;
         EndStr    : CHAR ;
         CharSeq   : SequenceType ;
         IntName   : CharNameType ;
         StIntName : CharNameType ;
         TempLine  : StrAny ;
         C         : CHAR ;
         OK        : BOOLEAN ;
      BEGIN
         Str.Concat( TempLine, InputLine, ' ' ) ;
         State := CharLook ;
         FOR LinePos := 0 TO Str.Length(TempLine) DO
            CASE State OF
               CharLook :
                  IF TempLine[LinePos] <> ' ' THEN
                     IF (TempLine[LinePos] = "'") OR (TempLine[LinePos] = '"') THEN
                        State := DoString ;
                        EndStr := TempLine[LinePos] ;
                        CharSeq := '' ;
                     ELSIF TempLine[LinePos] = '(' THEN
                        IF InBracket THEN
				(*RES OLD MSG 69
				Please remove nested brackets in the Alphabet.
				*)
                           PutResError( (*RES REM INS *) 69 ) ;
                           RETURN FALSE ;
                        ELSE
                           InBracket := TRUE
                        END ;
                     ELSIF (TempLine[LinePos] = ')') AND InBracket THEN
                        ResetSCode := TRUE ;
                        InBracket := FALSE ;
                     ELSIF (TempLine[LinePos] = '\') THEN
                        State := IntNameLook ;
                        CharSeq := '' ;
                     ELSE
                        Str.Copy( CharSeq, TempLine[LinePos] ) ;
                        State := RestChar ;
                     END ;
                  END   |
               RestChar :
                  IF ((TempLine[LinePos] = ')') AND InBracket) OR (TempLine[LinePos] = ' ') THEN
                     IF NOT InsertCode(CharSeq, SymbolKind) THEN
                        RETURN FALSE ;
                     END ;
                     IF TempLine[LinePos] <> ' ' THEN
                        InBracket := FALSE ;
                        ResetSCode := TRUE ;
                     END ;
                     State := CharLook ;
                  ELSE
                     IF Str.Length(CharSeq) = MaxCharsInSeq THEN
			(*RES OLD MSG 70
			There are too many characters in the symbol.
			*)
                        PutResError( (*RES REM INS *) 70 ) ;
                        RETURN FALSE ;
                     ELSE
                        Str.Append( CharSeq, TempLine[LinePos] );
                     END ;
                  END    |
               DoString :
                  IF TempLine[LinePos] = EndStr THEN
                     IF NOT InsertCode(CharSeq, SymbolKind) THEN
                        RETURN FALSE ;
                     END ;
                     State := CharLook ;
                  ELSE
                     IF Str.Length(CharSeq) = MaxCharsInSeq THEN
			(*RES OLD MSG 71
			There are too many characters in the quoted symbol.
			*)
                        PutResError( (*RES REM INS *) 71 ) ;
                        RETURN FALSE ;
                     ELSE
                        Str.Append ( CharSeq, TempLine[LinePos] );
                     END ;
                  END    |
               IntNameLook :
                  IF TempLine[LinePos] = '\' THEN
                     IF CharSeq[0] = 0C THEN
			(*RES OLD MSG 72
			MakeBase has found a null Internal Name sequence.
			*)
                        PutResError( (*RES REM INS *) 72 ) ;
                        RETURN FALSE ;
                     END ;
                     IF NOT InsertCode(CharSeq, SymbolKind) THEN
                        RETURN FALSE ;
                     END ;
                     State := CharLook ;
                  ELSIF TempLine[LinePos] <> ' ' THEN
                     State := IntNameGet ;
                     Str.Copy( IntName, TempLine[LinePos]);
                  END    |
               IntNameGet :
                  IF (TempLine[LinePos] = ' ') OR (TempLine[LinePos] = '\') THEN
                     StandardizeCharName(IntName, StIntName) ;
                     C := LookupIntName(StIntName, OK) ;
                     State := IntNameLook ;
                     IF NOT OK THEN
			(*RES OLD MSG 73
			MakeBase has found an invalid Internal Name "%0".
			*)
                        MsgString( IntName, 0 ) ;
                        PutResError( (*RES REM INS *) 73 ) ;
                        RETURN FALSE ;
                     ELSE
                        IF Str.Length(CharSeq) = MaxCharsInSeq THEN
				(*RES OLD MSG 74
				There are too many characters in an Internal Symbol string.
				*)
                           PutResError( (*RES REM INS *) 74 ) ;
                           RETURN FALSE ;
                        ELSE
                           Str.Append( CharSeq, C);
                        END ;
                     END ;
                  ELSIF TempLine[LinePos] <> ' ' THEN
                     IF Str.Length(IntName) = CharNameLength THEN
			(*RES OLD MSG 75
			There are too many characters in an Internal Name.
			*)
                        PutResError( (*RES REM INS *) 75 ) ;
                        RETURN FALSE ;
                     ELSE
                        Str.Append( IntName, TempLine[LinePos]);
                     END ;
                  END ;
                  IF TempLine[LinePos] = '\' THEN
                     IF Str.Length(CharSeq) = 0 THEN
			(*RES OLD MSG 76
			MakeBase has found a null Internal Name sequence.
			*)
                        PutResError( (*RES REM INS *) 76 ) ;
                        RETURN FALSE ;
                     END ;
                  IF NOT InsertCode(CharSeq, SymbolKind) THEN
                     RETURN FALSE ;
                  END ;
                  State := CharLook ;
               END ;
               ELSE
            END  (* CASE State OF *)
         END ;  (* FOR LinePos := 1 TO Str.Length(TempLine) DO *)
         IF State = DoString THEN
		(*RES OLD MSG 77
		The closing quote is missing: %0.
		*)
            MsgString( EndStr, 0 ) ;
            PutResError( (*RES REM INS *) 77 ) ;
            RETURN FALSE
         ELSIF (State = IntNameLook) OR (State = IntNameGet) THEN
		(*RES OLD MSG 78
		The "\" that closes an Internal String definition is missing.
		*)
            MsgString( EndStr, 0 ) ;
            PutResError( (*RES REM INS *) 78 ) ;
            RETURN FALSE
         END ;
         RETURN TRUE ;
      END ProcessAlphaLine ;

   BEGIN
      CodePoint := 2C ;  (* first real value is 3C *)
      ResetSCode := TRUE ;
      InBracket := FALSE ;
      InitialXlateData( Int2FAlp ) ;

      I := 0 ;
      InBracket := FALSE ;
      WHILE (I < NoAlphaLines) DO
         INC( I ) ;
         IF NOT ProcessAlphaLine(AlphaInfo.AlphaString[I], LetterSym) THEN
            DeleteTables ;
            RETURN I ;
         END
      END ;
      IF InBracket THEN
	(*RES OLD MSG 79
	The Alphabet is missing a closing bracket.
	*)
         PutResError( (*RES REM INS *) 79 ) ;
         DeleteTables ;
         RETURN 1 ;
      END ;
      I := 0 ;
      WHILE (I < NoRetDiLines) DO
         INC( I ) ;
         IF NOT ProcessAlphaLine(AlphaInfo.RetDiacStr[I], RetDiacSym) THEN
            DeleteTables ;
            RETURN NoAlphaLines + I ;
         END
      END ;
      I := 0 ;
      WHILE (I < NoNonDiLines) DO
         INC( I ) ;
         IF NOT ProcessAlphaLine(AlphaInfo.NonDiacStr[I], NonRetDiacSym) THEN
            DeleteTables ;
            RETURN NoAlphaLines + NoRetDiLines + I ;
         END
      END ;
      IF NOT ProcessAlphaLine( AlphaInfo.ContinuationSeq, ContCharSym) THEN
         DeleteTables ;
         RETURN NoAlphaLines + NoRetDiLines + NoNonDiLines + 1 ;
      END ;

      (* force the use of a high character for delimeter in sorting *)
      TypeOfChar[HighKeyCode] := HighKeyChar ;
      CharSeq[0] := HighKeyCode ;
      CharSeq[1] := 0C ;
      IF NOT InsertToXlate( CharSeq, CharSeq, BothAlpha ) THEN
         RETURN 0 ;
      END ;
  
      EquateXlateData(Int2Alp) ;
      EquateXlateData(Int2FAlp) ;

  (* --- *LP* Debug -----

   (* lets first dump the Xlate table info.  *)
   BCreate(OutFile,'$$XLATE.DMP',TRUE,IOResult);
   IF IOResult <> OK THEN   Beep;   RETURN 0  END;
   BOpen(OutFile,'XLATE.DMP',writemode,IOResult);
   IF IOResult <> OK THEN   Beep;   RETURN 0  END;
   DumpXlateTable( Int2FAlp,'Int', 'FAlp', OutFile ) ;
   BClose( OutFile, IOResult ) ;
   IF IOResult <> OK THEN   Beep;   RETURN 0  END;
   ----- *LP* -------- *)

      RETURN 0
  END BuildAlphabetXlate ;

PROCEDURE InitXlateLists( ) ;
  VAR
     I : CHAR ;
  BEGIN
     FOR I := 1C TO 377C DO
         TypeOfChar[I] := NullChar ;
     END ;
     IgnoreBrkList   := NIL ;
     RefBrkList      := NIL ;
     CounterCharList := NIL ;
     LabelList       := NIL ;
     RefList         := NIL ;
     BYUList         := NIL ;
     WordCounterPtr  := NIL ;
     LineCounterPtr  := NIL ;
     NamesList       := NIL ;
     PosRefList      := NIL ;
     NumberNamesInList := 0 ;
(*   NameIdCounter   := 2 ;   (* NameId 0 is for words, 1 for lines *) *NIC* *)
     StructIDCounter := 0 ;
     HeadCounterList := NIL ;

  END InitXlateLists ;


PROCEDURE FreeXlateLists( ) ;
  VAR
     I    : CHAR ;
     J    : CARDINAL ;
     Temp : ADDRESS ;

  PROCEDURE DisposeCounters( VAR Ptr : CounterPtr ) ;
     BEGIN
        IF Ptr = NIL THEN
           RETURN
        END ;
        J := 1 ;
        WHILE (J <= MaxNumbResets) AND (Ptr^.ResetsCounters[J] <> NIL) DO
           DisposeCounters( Ptr^.ResetsCounters[J] ) ;
           INC( J ) ;
        END ;
        DISPOSE( Ptr ) ;
        Ptr := NIL ;
     END DisposeCounters ;

  PROCEDURE DisposeRefBYUPtr( VAR Ptr : RefBYUPtr ) ;
     BEGIN
        WHILE Ptr <> NIL DO
           J := 1 ;
           WHILE (J <= MaxNumbResets) AND (Ptr^.IncremCounters[J] <> NIL) DO
              DisposeCounters( Ptr^.IncremCounters[J] ) ;
              INC( J ) ;
           END ;
           Temp := Ptr^.Next ;
           DISPOSE( Ptr ) ;
           Ptr := Temp ;
        END ;
     END DisposeRefBYUPtr ;

  PROCEDURE DisposeRefPosPtr( VAR Ptr : RefPosPtr );
     BEGIN
        WHILE Ptr <> NIL DO
           J := 1 ;
           WHILE (J <= MaxNumbResets) AND (Ptr^.IncremCounters[J] <> NIL) DO
              DisposeCounters( Ptr^.IncremCounters[J] ) ;
              INC( J ) ;
           END ;
           Temp := Ptr^.Next ;
           DISPOSE( Ptr ) ;
           Ptr := Temp ;
         END;
     END DisposeRefPosPtr ;

  BEGIN
     FOR I := 1C TO 377C DO
         TypeOfChar[I] := NullChar ;
     END ;

     WHILE IgnoreBrkList <> NIL DO
        Temp := IgnoreBrkList^.Next ;
        DISPOSE( IgnoreBrkList ) ;
        IgnoreBrkList := Temp ;
     END ;

     WHILE RefBrkList <> NIL DO
        Temp := RefBrkList^.Next ;
        DISPOSE( RefBrkList ) ;
        RefBrkList := Temp ;
     END ;

     WHILE NamesList <> NIL DO
        Temp := NamesList^.Next ;
        DISPOSE( NamesList ) ;
        NamesList := Temp ;
     END ;
     IF WordCounterPtr <> NIL THEN
        DISPOSE( WordCounterPtr ) ; (* WordCounter does NOT have reset counters *)
        WordCounterPtr := NIL ;
     END ;

     DisposeCounters( LineCounterPtr ) ;

     WHILE CounterCharList <> NIL DO
        DisposeCounters( CounterCharList^.ToCounterData ) ;
        Temp := CounterCharList^.Next ;
        DISPOSE( CounterCharList ) ;
        CounterCharList := Temp ;
     END ;

     WHILE LabelList <> NIL DO
        J := 1 ;
        WHILE (J <= MaxNumbResets) AND (LabelList^.IncremCounters[J] <> NIL) DO
           DisposeCounters( LabelList^.IncremCounters[J] ) ;
           INC( J ) ;
        END ;
        Temp := LabelList^.Next ;
        DISPOSE( LabelList ) ;
        LabelList := Temp ;
     END ;

     DisposeRefBYUPtr( RefList ) ;

     DisposeRefBYUPtr( BYUList ) ;

     DisposeRefPosPtr( PosRefList );

  END FreeXlateLists ;

PROCEDURE BuildSpecialCharXlate( ) : CARDINAL ;
  TYPE NoBitsMask = ARRAY[4..8] OF CARDINAL ;  (* could prob. do without 4 !? *)
  CONST NoBits = NoBitsMask ( 000FH, 001FH, 003FH, 007FH, 00FFH ) ;
  VAR
     HeadIgn, HeadRef : IgnoreRefPtr ;
     NoErrors	: BOOLEAN ;
     I		: CHAR ;
  BEGIN
     HeadIgn := NIL ;
     HeadRef := NIL ;

     SetToTop( SCList ) ;
     NoErrors := TRUE ;
     WHILE NoErrors AND MoveDown( SCList ) DO
        GetData( SCList, DataPtr ) ;
        SCData := DataPtr ;
        INC( CodePoint ) ;
        WITH SCData^ DO
           CASE TypeOfSpecialChar OF
              WordSepSCType :
                 TypeOfChar[CodePoint] := NullChar ;
                 NoErrors := InsertToXlate( WordSepSeq, CodePoint, JustFullAlpha ) |
              IgnoreSCType :
                 NEW( IgnoreBrkList ) ;  (* create a reversed order list this way *)
                 IgnoreBrkList^.Next := HeadIgn ;
                 HeadIgn := IgnoreBrkList ;
                 IgnoreBrkList^.SuppressText := SuppressText ;
                 IgnoreBrkList^.WordSep      := WordSep ;
                 IF Str.Compare( OpenBracket, CloseBracket ) = 0 THEN
                    TypeOfChar[CodePoint] := IgnBrkStEnd ;
                    IgnoreBrkList^.OpenCode    := CodePoint ;
                    IgnoreBrkList^.ClosingCode := CodePoint ;
                    NoErrors := InsertToXlate( OpenBracket, CodePoint, JustFullAlpha ) ;
                 ELSE
                    TypeOfChar[CodePoint] := IgnBrkStart ;
                    IgnoreBrkList^.OpenCode := CodePoint ;
                    NoErrors := InsertToXlate( OpenBracket, CodePoint, JustFullAlpha ) ;
                    IF NoErrors THEN
                       INC( CodePoint ) ;
                       TypeOfChar[CodePoint] := IgnBrkEnd ;
                       IgnoreBrkList^.ClosingCode := CodePoint ;
                       NoErrors := InsertToXlate( CloseBracket, CodePoint, JustFullAlpha ) ;
                    END ;
                 END ;    |
              ReferenceSCType :
                 NEW( RefBrkList ) ;
                 RefBrkList^.Next := HeadRef ;
                 HeadRef := RefBrkList ;
                 RefBrkList^.SuppressText := SuppressText ;
                 RefBrkList^.WordSep      := WordSep ;
                 IF Str.Compare( OpenBracket, CloseBracket ) = 0 THEN
                    TypeOfChar[CodePoint] := RefBrkStEnd ;
                    RefBrkList^.OpenCode := CodePoint ;
                    RefBrkList^.ClosingCode := CodePoint ;
                    NoErrors := InsertToXlate( OpenBracket, CodePoint, JustFullAlpha ) ;
                 ELSE
                    TypeOfChar[CodePoint] := RefBrkStart ;
                    RefBrkList^.OpenCode := CodePoint ;
                    NoErrors := InsertToXlate( OpenBracket, CodePoint, JustFullAlpha ) ;
                    IF NoErrors THEN
                       INC( CodePoint ) ;
                       TypeOfChar[CodePoint] := RefBrkEnd ;
                       RefBrkList^.ClosingCode := CodePoint ;
                       NoErrors := InsertToXlate( CloseBracket, CodePoint, JustFullAlpha ) ;
                    END ;
                 END ;
              ELSE
                 (*RES OLD MSG 80
                 BuildSpecialCharXlate: invalid Special Character.
                 *)
                 PutResError( (*RES REM INS *) 80 ) ;
           END ; (* CASE TypeOfSpecialChar OF *)
        END ;  (* WITH SCData^ DO *)
     END;    (* WHILE NoErrors AND MoveDown( SCList ) DO *)

     I := 377C ;
     WHILE (TypeOfChar[I] <> Letter) AND (TypeOfChar[I] <> RetDiac) DO  DEC( I )  END ;
     SortNoBitsPerChar := 4 ;
     WHILE ORD(I) >= NoBits[ SortNoBitsPerChar ] DO  INC( SortNoBitsPerChar )  END ;

     IF NoErrors THEN
        RETURN 0
     ELSE
        DeleteTables ;
        RETURN 5  (* any non zero value will do *)
     END ;
  END BuildSpecialCharXlate ;

PROCEDURE BuildStructInfoXlate():   ReshowMenuType;
  CONST
     BadChar = 1C ;
  VAR
     I, J     : CARDINAL ;
     HeadLab  : LabelPtr ;
     HeadRef  : RefBYUPtr ;
     HeadBYU  : RefBYUPtr ;
     Dummy    : BOOLEAN ;
     NoErrors : BOOLEAN ;
     NamesPos : CARDINAL ;
     NewName  : StrAny ;
     ToCounterPtr : CounterPtr ;
     HeadCharList : CounterCharPtr ;
     DerefNameRec : NamesTypePtr ;
     NameRec      : NamesTypePtr ;
     NotAddedBYUMarker : BOOLEAN ;

     NumbSeq    : CARDINAL ;
     ActualLen  : CARDINAL ;
     LenD       : XlateStrAny;
     EnoughData : BOOLEAN ;
     cm         : CurrentModeType;

     PrevPosRef,
     NextPosRef,
     NewPosRef  : RefPosPtr;
     DoSIDInc   : BOOLEAN;

  PROCEDURE XlateToken(     NewName  : ARRAY OF CHAR ;
                        VAR SortName : ARRAY OF CHAR ) : BOOLEAN ;
     VAR
        XlateName  : StrAny ;
        cm         : CurrentModeType;
     BEGIN
        cm.ModeIn := '0'; cm.ModeOut := '0';
        XlateLine( Int2Alp, BadChar, NewName, cm, ActualLen, LenD, NumbSeq,
        	EnoughData, XlateName );
        I := 1 ;
        J := 0 ;
        WHILE (I <= NumbSeq) AND (XlateName[J] <> BadChar) DO
           INC( J, LenD[I].Out ) ;
           INC( I ) ;
        END ;
        IF I <= NumbSeq THEN
	(*RES OLD MSG 81
	The invalid character "%0" occurs in the name "%1".
	*)
           MsgString( NewName[I-1], 0 ) ;
           MsgString( NewName, 0 ) ;
           PutResError( (*RES REM INS *) 81 ) ;
           RETURN FALSE ;
        END ;
        FullToSortWord( XlateName, SortName ) ;
        RETURN TRUE
     END XlateToken ;

  PROCEDURE AddInNameList( NewName      : ARRAY OF CHAR ;
                           NameIdCounter: CARDINAL ; (* added, j.b. *)
                           PrefVal      : CARDINAL ; (* added, j.b. *)
                           CntrAddress  : ADDRESS ;
                           TypeOfStruct : StructInfoType ) : BOOLEAN ;
     VAR
        Previous, TempList  : NamesTypePtr ;
        SortName     : StrAny ;
        NewNameEntry : NamesTypePtr ;
     BEGIN
        IF NewName[0] = 0C THEN  (* no name provided! *)
           ProgramErrorAndHalt('In XLATUSER.MOD, procedure AddInNameList: "NewName" is null');
        END ;
        IF NOT XlateToken( NewName, SortName ) THEN
           RETURN FALSE
        END ;
        Previous := NIL ;
        TempList := NamesList ;
        WHILE (TempList <> NIL) AND (Str.Compare(TempList^.Name, SortName) < 0) DO
           Previous := TempList ;
           TempList := TempList^.Next ;
        END ;
        IF (TempList <> NIL) AND (Str.Compare(TempList^.Name, SortName) = 0) THEN
		(*RES OLD MSG 82
		There is a duplicate name "%0".
		*)
           MsgString( NewName, 0 ) ;
           PutResError( (*RES REM INS *) 82 ) ;
           RETURN FALSE  (* SortName already in names list *)
        ELSE  (* insert name in list *)
           NEW( NewNameEntry ) ;
           INC( NumberNamesInList ) ;
           WITH NewNameEntry^ DO
              NameID := NameIdCounter ;
              Str.Copy( Name, SortName ) ;
              AddrType := TypeOfStruct ;
              CounterAddr := CntrAddress ;
              Preference := PrefVal;
           END ;
           IF Previous = NIL THEN
              (* add to front of list *)
              NewNameEntry^.Next := NamesList ;
              NamesList := NewNameEntry ;
           ELSE
              NewNameEntry^.Next := TempList ;
              Previous^.Next     := NewNameEntry ;
           END ;
        END ;
        RETURN TRUE ;
     END AddInNameList ;

  PROCEDURE GetNameRec(     NewName     : ARRAY OF CHAR ;
                        VAR NameRec : NamesTypePtr ) : BOOLEAN ;
     VAR
        SortName  : StrAny ;
        TempList  : NamesTypePtr ;
     BEGIN
        IF NewName[0] = 0C THEN  (* no name provided! *)
           NameRec := NIL ;
           RETURN FALSE ;
        END ;
        IF NOT XlateToken( NewName, SortName ) THEN
           RETURN FALSE
        END ;
        RETURN LookupName(SortName, NameRec);
     END GetNameRec ;

  PROCEDURE GetName(     NamesStr : ARRAY OF CHAR ;
                     VAR NamePos  : CARDINAL ;
                     VAR Name     : ARRAY OF CHAR ) : BOOLEAN ;
     TYPE
        StateValues = ( CharLook, DoString, RestOfName ) ;
     VAR
        State   : StateValues ;
        Char    : CHAR ;
        EndStr  : CHAR ;
        TempStr : StrAny ;
     BEGIN
        Str.Concat( TempStr, NamesStr, ' ' ) ;
        Name[0] := 0C ;		(* *LP3* *)
        State := CharLook ;
        WHILE NamePos <= Str.Length( TempStr ) DO
           Char := TempStr[NamePos] ;
           CASE State OF
              CharLook :
                 IF Char <> ' ' THEN
                    IF (Char = '"') OR (Char = "'") THEN
                       State := DoString ;
                       EndStr := Char ;
                    ELSE
                       Str.Copy( Name, Char ) ;
                       State := RestOfName ;
                    END ;
                 END ;    |
              RestOfName :
                 IF Char = ' ' THEN
                    RETURN TRUE
                 ELSE
                    Str.Append( Name, Char ) ;
                 END ;    |
              DoString :
                 IF Char = EndStr THEN
		    IF Str.Length( Name ) = 0 THEN	(* *LP3* *)
			(*RES OLD MSG 392
			A double occurence of %0 should not be in line "%1".
			*)
			MsgString( EndStr, 0 ) ;
			MsgString( NamesStr, 0 ) ;
			PutResError( (*RES REM INS *) 392 ) ;
			NoErrors := TRUE ;	(* force exit of parsing! *)
			RETURN FALSE ;
		    END ;
		    INC( NamePos ) ;
		    RETURN TRUE
                 ELSE
                    Str.Append( Name, Char );
                 END ;
           END ;  (* CASE State OF *)
           INC( NamePos ) ;
        END ; (* WHILE NamePos <= Str.Length( TempStr ) DO *)
        IF State = DoString THEN
		(*RES OLD MSG 83
		A closing quote is missing from %0.
		*)
           MsgString( NamesStr, 0 ) ;
           PutResError( (*RES REM INS *) 83 ) ;
	   NoErrors := TRUE ;	(* force exit of parsing! *LP3* *)
           RETURN FALSE ;
        END ;
        RETURN FALSE
     END GetName ;

  PROCEDURE CheckLoop( Ptr : CounterPtr ) : BOOLEAN ;
     (* HeadCounterList needs to be set to NIL each non-recursive call to CheckLoop *)
     VAR
        TempCounterPtr : CounterPtr ;
        I              : CARDINAL ;
     BEGIN
        TempCounterPtr := HeadCounterList ;
        WHILE TempCounterPtr <> NIL DO
           IF TempCounterPtr = Ptr THEN
              RETURN FALSE
           END ;
           TempCounterPtr := TempCounterPtr^.Next ;
        END ;
        Ptr^.Next := HeadCounterList ;
        HeadCounterList := Ptr ;
        I := 1 ;
        WHILE (I <= MaxNumbResets) AND (Ptr^.ResetsCounters[I] <> NIL) DO
           IF NOT CheckLoop( Ptr^.ResetsCounters[I] ) THEN
              RETURN FALSE
           END ;
           INC( I ) ;
        END ;
        RETURN TRUE ;
     END CheckLoop ;

  PROCEDURE SetResetsCounters( ResetStr        : ARRAY OF CHAR ;
                               StartCounterPtr : CounterPtr ) ;
     BEGIN
        NamesPos := 0 ;
	HeadCounterList := NIL ;  (* needed by CheckLoop proc *)
        WHILE NoErrors AND GetName(ResetStr,NamesPos,NewName) DO
           IF GetNameRec( NewName, NameRec ) THEN
              WITH StartCounterPtr^ DO
                 IF (NameRec^.AddrType = CounterType) OR
                    (NameRec^.AddrType = WordCounterType) OR
                    (NameRec^.AddrType = LineCounterType) THEN
                    I := 1 ;
                    WHILE (I <= MaxNumbResets) AND (ResetsCounters[I] <> NIL) DO
                       INC( I ) ;
                    END ;
                    IF I <= MaxNumbResets THEN
                       ResetsCounters[I] := NameRec^.CounterAddr ;
                       NoErrors := CheckLoop( StartCounterPtr ) ;
                       IF NOT NoErrors THEN
                          MsgString( NewName, 0 ) ;
                          PutResError( ResInfiniteLoop ) ;
                       END ;
                    ELSE
                       MsgString( NewName, 0 ) ;
                       MsgCard( MaxNumbResets, 0 ) ;
                       PutResError( ResTooManyResets ) ;
                       NoErrors := FALSE ;
                    END ;
                 ELSE
			(*RES OLD MSG 86
			The structure to which "%0" refers does not have a Counter to Reset.
			*)
                    MsgString( NewName, 0 ) ;
                    PutResError( (*RES REM INS *) 86 ) ;
                    NoErrors := FALSE ;
                 END ;  (* IF AddrType = CounterType THEN *)
              END ; (* WITH NameRec^ DO *)
           ELSE
		(*RES OLD MSG 87
		The structure to which "%0" refers does not exist.
		*)
              MsgString( NewName, 0 ) ;
              PutResError( (*RES REM INS *) 87 ) ;
              NoErrors := FALSE ;
           END ;
        END ;  (* WHILE NoErrors AND GetName(ResetStr,NamesPos,NewName) DO *)
     END SetResetsCounters ;

  PROCEDURE AddCounterToIncrem( DerefNameRec : NamesTypePtr ;
                                ToCounterPtr : CounterPtr ) ;
     VAR
        TempLabelPtr  : LabelPtr ;
        TempRefBYUPtr : RefBYUPtr ;
     BEGIN
       IF NOT CheckLoop(ToCounterPtr) THEN
          MsgString( DerefNameRec^.Name, 0 ) ;
          PutResError( ResInfiniteLoop ) ;
          NoErrors := FALSE ;
          RETURN
        END ;
        CASE DerefNameRec^.AddrType OF
           WordCounterType,
           LineCounterType,
           CounterType :
		(*RES OLD MSG 89
		The structure to which "%0" refers cannot be used to increment another Counter.
		*)
              MsgString( NewName, 0 ) ;
              PutResError( (*RES REM INS *) 89 ) ;
              NoErrors := FALSE ;    |
           LabelType :
              TempLabelPtr := DerefNameRec^.CounterAddr ;
              WITH TempLabelPtr^ DO
                 I := 1 ;
                 WHILE (I <= MaxNumbResets) AND (IncremCounters[I] <> NIL) DO
                    IF IncremCounters[I] = ToCounterPtr THEN
			(*RES OLD MSG 90
			The Counter to which "%0" refers is incremented twice.
			*)
                       MsgString( NewName, 0 ) ;
                       PutResError( ResIncTwice ) ;
                       NoErrors := FALSE ;
                       RETURN
                    END ;
		    HeadCounterList := NIL ;  (* needed by CheckLoop proc *)
                    IF NOT CheckLoop(IncremCounters[I]) THEN
                       MsgString( DerefNameRec^.Name, 0 ) ;
                       PutResError( ResInfiniteLoop ) ;
                       NoErrors := FALSE ;
                       RETURN
                    END ;
                    INC( I )
                 END ;
                 IF I > MaxNumbResets THEN
                    MsgString( NewName, 0 ) ;
                    MsgCard( MaxNumbResets, 0 ) ;
                    PutResError( ResTooManyResets ) ;
                    NoErrors := FALSE ;
                 ELSE
                    IncremCounters[I] := ToCounterPtr
                 END ;
              END ;         |
           ReferenceType,
           BYUType :
              TempRefBYUPtr := DerefNameRec^.CounterAddr ;
              WITH TempRefBYUPtr^ DO
                 I := 1 ;
                 WHILE (I <= MaxNumbResets) AND (IncremCounters[I] <> NIL) DO
                    IF IncremCounters[I] = ToCounterPtr THEN
                       MsgString( DerefNameRec^.Name, 0 ) ;
                       PutResError( ResIncTwice ) ;
                       NoErrors := FALSE ;
                       RETURN
                    END ;
		    HeadCounterList := NIL ;  (* needed by CheckLoop proc *)
                    IF NOT CheckLoop(IncremCounters[I]) THEN
                       MsgString( NewName, 0 ) ;
                       PutResError( ResInfiniteLoop ) ;
                       NoErrors := FALSE ;
                       RETURN
                    END ;
                    INC( I )
                 END ;
                 IF I > MaxNumbResets THEN
                    MsgString( NewName, 0 ) ;
                    MsgCard( MaxNumbResets, 0 ) ;
                    PutResError( ResTooManyResets ) ;
                    NoErrors := FALSE ;
                 ELSE
                    IncremCounters[I] := ToCounterPtr
                 END ;
              END ;
           ELSE
        END ;  (* CASE DerefNameRec^.AddrType OF *)
     END AddCounterToIncrem ;

  PROCEDURE HandlePosType;
  BEGIN
     NEW( NewPosRef );
     NewPosRef^.StructID     := StructIDCounter ;
     NewPosRef^.StartPos     := StructData^.PosStart - 1;
     NewPosRef^.EndPos       := StructData^.PosEnd - 1;
     NewPosRef^.Numeric      := StructData^.PosNumeric;
     NewPosRef^.VLastStr     := VirtNil ;
     NewPosRef^.StrHeader    := VirtNil ;
     Fill( ADR(NewPosRef^.StrRecInfo), 4, 0C );
     IF NewPosRef^.Numeric THEN NewPosRef^.LastValCard := 0
     ELSE NewPosRef^.LastValStr := 0C END;

     PrevPosRef := NIL;
     NextPosRef := PosRefList;
     WHILE (NextPosRef <> NIL)
     AND (NextPosRef^.StartPos > NewPosRef^.StartPos) DO
        PrevPosRef := NextPosRef;
        NextPosRef := NextPosRef^.Next;
     END;
     IF WantFolding THEN
        WantFolding := FALSE;
        (*RES OLD MSG 438
        The "-f" (Folding) switch cannot be used with Position References.
        Automatic Line Folding has been turned off.
        *)
        PutResWarning( (*RES REM INS *) 438 ) ;
     END;
     IF (PrevPosRef <> NIL) AND
     (PrevPosRef^.StartPos <= NewPosRef^.EndPos) THEN
        (*RES OLD MSG 439
        One Position Reference overlaps another Position Reference.
        *)
        PutResError( (*RES REM INS *) 439 ) ; (* notice ref again below j.b. *)
        NoErrors := FALSE ;
        DISPOSE(NewPosRef);
        RETURN
     ELSIF NextPosRef = NIL THEN
        NewPosRef^.Next := NIL;
     ELSIF (NextPosRef^.EndPos >= NewPosRef^.StartPos) THEN
        PutResError( (*RES REM INS *) 439 ) ;
        NoErrors := FALSE ;
        DISPOSE(NewPosRef);
        RETURN
     ELSE
        NewPosRef^.Next := NextPosRef;
     END;
     IF PrevPosRef = NIL THEN PosRefList := NewPosRef
     ELSE PrevPosRef^.Next := NewPosRef END;
     IF (StructData^.Names[0] = '-') AND (StructData^.Names[1] = 0C) THEN
        DoSIDInc := FALSE;
        NewPosRef^.StructID     := 0;
     ELSE
        I := 0;
        WHILE NoErrors AND GetName( StructData^.Names, NamesPos, NewName ) DO
(* *NIC*   NoErrors := AddInNameList( NewName, NameIdCounter,I,
                        NewPosRef, StructData^.TypeOfStructInfo ); (* chng jb *) *)
           NoErrors := AddInNameList( NewName, StructIDCounter,I,
                        NewPosRef, StructData^.TypeOfStructInfo ); (* chng jb *)
           INC(I);
        END ;
(* *NIC*INC(NameIdCounter); *)
        FOR I := 1 TO MaxNumbResets DO
           NewPosRef^.IncremCounters[ I ] := NIL
        END ;
     END;
  END HandlePosType;

  BEGIN
     HeadLab := NIL ;
     HeadRef := NIL ;
     HeadBYU := NIL ;
     NoErrors := TRUE ;
     HeadCharList := NIL ;
     NotAddedBYUMarker := TRUE ;
     SetToTop( StructList ) ;
     WHILE NoErrors AND MoveDown( StructList ) DO
        DoSIDInc := TRUE;
        NamesPos := 0 ;
        GetData( StructList, DataPtr ) ;
        StructData := DataPtr ;
        WITH StructData^ DO
           CASE TypeOfStructInfo OF
              WordCounterType :
                 NEW( WordCounterPtr ) ;
                 WordCounterPtr^.Next := NIL ;
                 WordCounterPtr^.Init := WordCounterInit ;

                 (* >>> Note: WordCounterPtr^.CurrentValue is NOT used/referred <<< *LP* *)
                 WordCounterPtr^.CurrentValue := WordCounterInit ;
                 WordCounterPtr^.StructID     := StructIDCounter ;
                 I := 0;
                 WHILE NoErrors AND GetName( Names, NamesPos, NewName ) DO
                    NoErrors := AddInNameList(NewName,0,I,WordCounterPtr,
                                              TypeOfStructInfo);(*"0" added jb*)
                    INC(I);
                 END ;
                 FOR I := 1 TO MaxNumbResets DO
                    WordCounterPtr^.ResetsCounters[ I ] := NIL
                 END ;
                     |
              LineCounterType :
                 NEW( LineCounterPtr ) ;
                 LineCounterPtr^.Next := NIL ;
                 LineCounterPtr^.Init := LineCounterInit ;
                 LineCounterPtr^.CurrentValue := LineCounterInit ;
                 LineCounterPtr^.StructID     := StructIDCounter ;
                 I := 0;
                 WHILE NoErrors AND GetName( Names, NamesPos, NewName ) DO
                    NoErrors := AddInNameList(NewName,1,I,LineCounterPtr,
                                              TypeOfStructInfo);(*"1" added jb*)
                    INC(I);
                 END ;
                 FOR I := 1 TO MaxNumbResets DO
                    LineCounterPtr^.ResetsCounters[ I ] := NIL
                 END ;
                     |
              ReferenceType :
                 IF RefBrkList = NIL THEN
			(*RES OLD MSG 96
			A Reference Structure requires that a "Reference Bracket" be defined in
			the Reserved Characters menu.
			*)
                    PutResError( (*RES REM INS *) 96 ) ;
                    NoErrors := FALSE ;
                    SetToTop( SCList ) ;
                    Dummy := MoveDown( SCList ) ;
                    RETURN XUSpecChars
                 ELSE
                    NEW( RefList ) ;
                    RefList^.Next := HeadRef ;
                    HeadRef := RefList ;
                    RefList^.StructID     := StructIDCounter ;
                    RefList^.NoCharsKeep  := RefNoCharsKeep ;
                    RefList^.Numeric      := RefNumeric ;
                    RefList^.VLastStr     := VirtNil ;
                    RefList^.StrHeader    := VirtNil ;

                    Fill( ADR(RefList^.StrRecInfo), 4, 0C );
		    cm.ModeIn := '0'; cm.ModeOut := '0';
        	    XlateLine( Int2Alp, BadChar, RefRefID, cm, ActualLen, LenD,
        	    	NumbSeq, EnoughData, RefList^.RefID );
                    I := 0;
                    WHILE NoErrors AND GetName( Names, NamesPos, NewName ) DO
(* *NIC*               NoErrors := AddInNameList( NewName, NameIdCounter, I,
                                   RefList, TypeOfStructInfo );(*changed jb*) *)
                       NoErrors := AddInNameList( NewName, StructIDCounter, I,
                                   RefList, TypeOfStructInfo );(*changed jb*)
                       INC(I);
                    END ;
(* *NIC*            INC(NameIdCounter); *)
                    FOR I := 1 TO MaxNumbResets DO
                        RefList^.IncremCounters[ I ] := NIL
                    END ;
                 END ;
                     |
              LabelType :
                 NEW( LabelList ) ;  (* create a reversed order list this way *)
                 LabelList^.Next := HeadLab ;
                 HeadLab := LabelList ;
                 LabelList^.StructID     := StructIDCounter ;
                 LabelList^.SuppressText := LabelSuppressText ;
                 LabelList^.WordSep      := LabelWordSep ;
                 LabelList^.NoCharsKeep  := LabelNoCharsKeep ;
                 LabelList^.Numeric      := LabelNumeric ;
                 LabelList^.VLastStr     := VirtNil ;
                 LabelList^.StrHeader    := VirtNil ;
                 Fill( ADR(LabelList^.StrRecInfo), 4, 0C );
                 INC( CodePoint ) ;
                 IF Str.Compare( LabelOpenBracket, LabelCloseBracket ) = 0 THEN
                    TypeOfChar[CodePoint]  := LabelStEnd ;
                    LabelList^.OpenCode    := CodePoint ;
                    LabelList^.ClosingCode := CodePoint ;
                    NoErrors := InsertToXlate( LabelOpenBracket, CodePoint, JustFullAlpha ) ;
                 ELSE
                    TypeOfChar[CodePoint] := LabelStart ;
                    LabelList^.OpenCode := CodePoint ;
                    NoErrors := InsertToXlate( LabelOpenBracket, CodePoint, JustFullAlpha ) ;
                    IF NoErrors THEN
                       INC( CodePoint ) ;
                       TypeOfChar[CodePoint] := LabelEnd ;
                       LabelList^.ClosingCode := CodePoint ;
                       NoErrors := InsertToXlate( LabelCloseBracket, CodePoint, JustFullAlpha ) ;
                    END ;
                 END ;
                 I := 0;
                 WHILE NoErrors AND GetName( Names, NamesPos, NewName ) DO
(* *NIC*            NoErrors := AddInNameList(NewName,NameIdCounter,I,
                                        LabelList,TypeOfStructInfo); (* chngd jb *) *)
                    NoErrors := AddInNameList(NewName,StructIDCounter,I,
                                        LabelList,TypeOfStructInfo); (* chngd jb *)
                    INC(I);
                 END ;
(* *NIC*         INC(NameIdCounter); *)
                 FOR I := 1 TO MaxNumbResets DO
                    LabelList^.IncremCounters[ I ] := NIL
                 END ;
                     |
              CounterType :
                 NEW( ToCounterPtr ) ;
                 WITH ToCounterPtr^ DO
                    StructID     := StructIDCounter ;
                    Init         := CounterInit ;
                    CurrentValue := CounterInit ;
                    SuppressText := CounterSuppressText ;
                    Next         := NIL ;
                    FOR I := 1 TO MaxNumbResets DO
                       ResetsCounters[ I ] := NIL
                    END ;
                 END ;
                 I := 0;
                 WHILE NoErrors AND GetName( Names, NamesPos, NewName ) DO
(* *NIC*            NoErrors := AddInNameList(NewName,NameIdCounter,I,
                                    ToCounterPtr,TypeOfStructInfo);(*chng jb*) *)
                    NoErrors := AddInNameList(NewName,StructIDCounter,I,
                                    ToCounterPtr,TypeOfStructInfo);(*chng jb*)
                    INC(I);
                 END ;
(* *NIC*         INC(NameIdCounter); *)
                     |
              BYUType :
                 NEW( BYUList ) ;
                 BYUList^.Next := HeadBYU ;
                 HeadBYU := BYUList ;
                 BYUList^.StructID     := StructIDCounter ;
                 BYUList^.NoCharsKeep  := BYUNoCharsKeep ;
                 BYUList^.Numeric      := BYUNumeric ;
                 BYUList^.VLastStr     := VirtNil ;
                 BYUList^.StrHeader    := VirtNil ;
		 Str.Copy( BYUList^.RefID, BYURefID ) ;  (* added *LP* *)
                 IF NotAddedBYUMarker THEN
                    INC( CodePoint ) ;
		    TypeOfChar[CodePoint] := BYUStart ;
                    NoErrors := InsertToXlate( '|', CodePoint, JustFullAlpha ) ;
                    NotAddedBYUMarker := FALSE ;
                 END ;
                 I := 0;
                 WHILE NoErrors AND GetName( Names, NamesPos, NewName ) DO
(* *NIC*            NoErrors := AddInNameList( NewName, NameIdCounter,I,
                                 BYUList, TypeOfStructInfo ); (* chng jb *) *)
                    NoErrors := AddInNameList( NewName, StructIDCounter,I,
                                 BYUList, TypeOfStructInfo ); (* chng jb *)
                    INC(I);
                 END ;
(* *NIC*         INC(NameIdCounter); *)
                 FOR I := 1 TO MaxNumbResets DO
                    BYUList^.IncremCounters[ I ] := NIL
                 END ;
                 |
              PosType:
                 HandlePosType;
              ELSE
                 ProgramErrorAndHalt( 'error in BuildStructInfoXlate' ) ;
           END ;
        END ;  (* WITH StructData^ DO *)
        IF DoSIDInc THEN INC( StructIDCounter ) END;
     END ; (* WHILE NoErrors AND MoveDown( StructList ) DO *)

     (* Now handle the other fields such as reset etc. *)
     IF NoErrors THEN
        SetToTop( StructList ) ;
     END ;
     WHILE NoErrors AND MoveDown( StructList ) DO
        GetData( StructList, DataPtr ) ;
        StructData := DataPtr ;
        HeadCounterList := NIL ;  (* needed by CheckLoop proc *)
        WITH StructData^ DO
           CASE TypeOfStructInfo OF
              WordCounterType,
              ReferenceType,
              LabelType,
              PosType,
              BYUType :  (* no more action for these structures *) |
              LineCounterType :
                 SetResetsCounters( LineCounterReset, LineCounterPtr ) ;
                     |
              CounterType :
                 NamesPos := 0 ;
                 Dummy := GetName( Names, NamesPos, NewName ) ;
                 IF GetNameRec( NewName, NameRec ) THEN
                    ToCounterPtr := NameRec^.CounterAddr ;
                    IF NameRec^.AddrType = CounterType THEN
                       NamesPos := 0 ;
                       WHILE NoErrors AND GetName( CounterRefID, NamesPos, NewName ) DO
                          IF NewName[0] = "@" THEN
                            Str.Delete( NewName, 0, 1 ) ;
                            IF GetNameRec( NewName, DerefNameRec ) THEN
                               AddCounterToIncrem( DerefNameRec, ToCounterPtr )
                            ELSE
                               (*RES OLD MSG 97
                               The structure to which "%0" refers does not exist.
                               *)
                               MsgString( NewName, 0 ) ;
                               PutResError( (*RES REM INS *) 97 ) ;
                               NoErrors := FALSE ;
                            END ;
                          ELSE (* its a unique code sequence marker to recognise *)
                            NEW( CounterCharList ) ;
                            CounterCharList^.Next := HeadCharList ;
                            CounterCharList^.ToCounterData := ToCounterPtr ;
                            HeadCharList := CounterCharList ;
                            INC( CodePoint ) ;
                            TypeOfChar[CodePoint] := Counter ;
                            CounterCharList^.Code := CodePoint ;
                            NoErrors := InsertToXlate( NewName, CodePoint, JustFullAlpha ) ;
                          END ;  (* IF NewName[0] = "@" THEN *)
                       END ; (* WHILE ... DO *)
                       IF NoErrors THEN
                          SetResetsCounters( CounterReset, ToCounterPtr )
                       END ;
                    ELSE
                       ProgramErrorAndHalt( 'error in BuildStructInfoXlate' ) ;
                    END ;
                 END ;  (* IF GetNameRec( NewName, NameRec ) THEN *)
              |
              ELSE  (* for case statement *)
                 ProgramErrorAndHalt( 'error in BuildStructInfoXlate' ) ;
           END ; (* CASE TypeOfStructInfo OF *)
        END ;  (* WITH StructData^ DO *)
     END ; (* WHILE NoErrors AND MoveDown( StructList ) DO *)

     IF NoErrors THEN
        RETURN XUAllOK
     ELSE
        DeleteTables ;
        RETURN XUStructList
     END ;
  END BuildStructInfoXlate ;

PROCEDURE VerifyRefTemplate(InTemplate: ARRAY OF CHAR):   BOOLEAN;
(* modelled after EncodeRefPat from TACT's RefValBase module    j.b. *)
CONST
   NoUnitsRes =    264; (* from RefValBase model *)

TYPE
   StateTypes = ( ColRefPat, LookForRefName, ColRefName, LookForStartPos,
		LookUpName, GetStartPos, GetNoChars );
VAR
   Ch:            CHAR;
   State:         StateTypes ;
   TemplateIndex: CARDINAL ;
   cm:            CurrentModeType ;
   AlpTemplate:   StrAny ;
   CurPos:        CARDINAL ;
   NumbSeq:       CARDINAL ;
   IntLenD:       XlateStrAny ;
   EnoughData	: BOOLEAN ;
   NameStartInt	: CARDINAL ;
   NameStartAlp	: CARDINAL ;
   LastCharRet  : BOOLEAN ;
   LastCharLen  : CARDINAL ;
   RefNameAlp   : ARRAY[0..30] OF CHAR;
   RefNameInt   : ARRAY[0..30] OF CHAR;
   TextLen      : CARDINAL;

PROCEDURE VerifyGivenRefName(): BOOLEAN;
VAR
   SortName:   ARRAY[0..30] OF CHAR;
   l:          CARDINAL;
   dummy:      NamesTypePtr;
BEGIN
   l := CurPos - NameStartAlp;
   FullToSortWord( RefNameAlp, SortName ) ;
   IF LookupName(SortName, dummy) THEN RETURN TRUE END;
   IF LastCharRet THEN
      (* To quote Lidio in RefValba:  (j.b.) *)
         (* this is a "bit" of a Kludge, but gets results! *)
         (* remove last retained diacritic from name and try again *)
      RefNameAlp[l-1] := 0C;
      FullToSortWord( RefNameAlp, SortName ) ;
      l := TemplateIndex - NameStartInt - LastCharLen;
      Str.Slice(RefNameInt, InTemplate, NameStartInt,
                TemplateIndex - NameStartInt);
      IF LookupName(SortName, dummy) THEN RETURN TRUE END;
   END;
   (*RES OLD MSG 289
   Your Reference Template contains an ill-formed Reference Name:"%0".
   *)
   MsgString( RefNameInt, 0);
   PutResError( (*RES REM INS*) 289 );
   RETURN FALSE;
END VerifyGivenRefName;

BEGIN
   IF Str.Pos(InTemplate, RefDelimID ) = MAX(CARDINAL) THEN
      Ch := RefDelimID;
      MsgString( InTemplate, 0 ) ;
      MsgString( Ch, 0 ) ;
      PutResError( NoUnitsRes );
      RETURN FALSE ;
   END ;
   State := ColRefPat ;
   TemplateIndex := 0 ;
   Str.Append(InTemplate, ' ');

   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine( Int2Alp, 377C, InTemplate, cm,TextLen, IntLenD, NumbSeq,
		EnoughData, AlpTemplate );

   CurPos := 0 ;
   WHILE (CurPos < TextLen) DO
      Ch := InTemplate[ TemplateIndex ] ;
      CASE State OF
        ColRefPat :
          IF Ch = RefDelimID THEN
	     NameStartInt := TemplateIndex + IntLenD[CurPos].Int ;
	     NameStartAlp := CurPos + 1;
	     State := LookForRefName ;
             LastCharRet := FALSE
          END ;
          INC( TemplateIndex, IntLenD[CurPos].Int ) ;
          INC( CurPos ) ;
      | LookForRefName :
          IF Ch = '?' THEN
             (*RES OLD MSG 290
             You cannot use "$?" in MakeBase.
             *)
             PutResMessage( (*RES REM INS*) 290 );
             RETURN FALSE ;
          END;
          IF (TypeOfChar[AlpTemplate[CurPos]] = Letter) OR
	     (TypeOfChar[AlpTemplate[CurPos]] = RetDiac) THEN
             IF TypeOfChar[AlpTemplate[CurPos]] = RetDiac THEN
                LastCharLen := IntLenD[CurPos].Int ;
                LastCharRet := TRUE ;
             ELSE
                LastCharRet := FALSE
             END ;
            INC( TemplateIndex, IntLenD[CurPos].Int ) ;
            INC( CurPos ) ;
          ELSE
             State := ColRefName;
          END;
      | ColRefName :
          IF CurPos = NameStartAlp THEN
             State := ColRefPat
          ELSE
             Str.Slice(RefNameAlp, AlpTemplate, NameStartAlp,
                       CurPos - NameStartAlp);
             Str.Slice(RefNameInt, InTemplate, NameStartInt,
                       TemplateIndex - NameStartInt);
             IF NOT VerifyGivenRefName() THEN
                RETURN FALSE
             END;
             IF Ch = '/' THEN
                State := LookForStartPos ;
                INC( TemplateIndex, IntLenD[CurPos].Int ) ;
                INC( CurPos ) ;
             ELSE
                State := ColRefPat ;
             END ;
          END;
      | LookForStartPos :
          IF (Ch < '0') OR (Ch > '9') THEN
             State := ColRefPat
          ELSE
             State := GetStartPos ;
             INC( TemplateIndex, IntLenD[CurPos].Int ) ;
             INC( CurPos ) ;
          END;
      | GetStartPos :
          IF (Ch >= '0') AND (Ch <= '9') THEN
             INC( TemplateIndex, IntLenD[CurPos].Int ) ;
             INC( CurPos ) ;
          ELSIF Ch = ',' THEN
             State := GetNoChars
          ELSE
             State := ColRefPat ;
          END;
      | GetNoChars:
          IF (Ch >= '0') AND (Ch <= '9') THEN
             INC( TemplateIndex, IntLenD[CurPos].Int ) ;
             INC( CurPos ) ;
          ELSE
             State := ColRefPat ;
          END;
      ELSE ProgramErrorAndHalt('Invalid State in VerifyRefTemplate');
      END;
   END;
   RETURN TRUE;
END VerifyRefTemplate;
BEGIN
   WantFolding := TRUE ;
END XlatUserInput .
