IMPLEMENTATION MODULE XlatAlphabet ;

(* copyright (c) 1987-96 John Bradley, Lidio Presutti, University of Torontoo *)

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

IMPORT Str;
FROM SYSTEM   IMPORT ADR,ADDRESS ;
FROM Storage  IMPORT ALLOCATE, DEALLOCATE ;
FROM StringIO IMPORT SWriteString, SWriteCard ;
FROM WordBase IMPORT
  (* Const *) NonRetDiacCode, ExtraCodeSep,
  (* Type  *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar,
  (* Procs *) FullToSortWord, SortToFullWord;
FROM Translations IMPORT
  (* Type   *) XlateTablePointer, HandleDuplicateType, XlateStrAny, CurrentModeType,
  (* Vars   *) Int2Alp, Alp2Int, Int2FAlp,
  (* Procs  *) InitialXlateData, InsertXlateData, EquateXlateData,
               XlateLine, DeleteXlateTable, DumpXlateTable ;
FROM Utils IMPORT StandardizeCharName ;
FROM GetSequences IMPORT LookupIntName ;
FROM GlobalDefs IMPORT StrAny, SequenceType, MaxCharsInSeq ;
FROM STANDARD IMPORT
  (* Type  *) CharNameType,
  (* Const *) CharNameLength ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt ;
FROM ResMessages IMPORT
  (* proc *) MsgString, MsgCard, PutResError, PutResMessage ;

TYPE
   AlphaSelectType = (JustFullAlpha, BothAlpha) ;
VAR
   MsgPos     : CARDINAL;
   Message    : StrAny ;
   CodePoint  : CHAR ;

PROCEDURE InsertToXlate( Sequence      : ARRAY OF CHAR ;
                         IntSeq        : ARRAY OF CHAR ;
                         AlphaSelector : AlphaSelectType ) : BOOLEAN ;
	(*RES OLD MSG 66
	Symbol "%0" appears twice.
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
		UnExpected Double Occurrence of AlphaSeq!!  Sequence: "%0"
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
				Nested Brackets in Alphabet
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
			Too Many Characters in Symbol
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
			Too Many Characters in Quoted Symbol
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
			Null Internal Name Sequence Found
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
			Invalid Internal Name "%0" found.
			*)
                        MsgString( IntName, 0 ) ;
                        PutResError( (*RES REM INS *) 73 ) ;
                        RETURN FALSE ;
                     ELSE
                        IF Str.Length(CharSeq) = MaxCharsInSeq THEN
				(*RES OLD MSG 74
				Too Many Characters in Internal Symbol String
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
			Too Many Characters in Internal Name
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
			Null Internal Name Sequence Found
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
		Missing Closing Quote: %0
		*)
            MsgString( EndStr, 0 ) ;
            PutResError( (*RES REM INS *) 77 ) ;
            RETURN FALSE
         ELSIF (State = IntNameLook) OR (State = IntNameGet) THEN
		(*RES OLD MSG 78
		Missing Closing "\" for end of Internal String Def
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
      WHILE (I < 2) DO
         INC( I ) ;
         IF NOT ProcessAlphaLine(AlphaInfo.AlphaString[I], LetterSym) THEN
            DeleteTables ;
            RETURN I ;
         END
      END ;
      IF InBracket THEN
	(*RES OLD MSG 79
	Missing Closing Bracket in Alphabet
	*)
         PutResError( (*RES REM INS *) 79 ) ;
         DeleteTables ;
         RETURN 1 ;
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

      RETURN 0
  END BuildAlphabetXlate ;

PROCEDURE InitXlateLists( ) ;
  VAR
     I : CHAR ;
  BEGIN
     FOR I := 1C TO 377C DO
         TypeOfChar[I] := NullChar ;
     END ;
  END InitXlateLists ;

END XlatAlphabet.

