IMPLEMENTATION MODULE SortLine;

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

IMPORT Str, Lib;
FROM SYSTEM IMPORT ADR;
FROM GlobalDefs IMPORT StrAny;
FROM Translations IMPORT
 (* var  *) Int2Alp, Alp2Int, LenD,
 (* type *) XlateStrAny, CurrentModeType, LengthDataType,
 (* proc *) XlateLine;

FROM WordBase IMPORT SimpAlphTable, TypeOfChar, AlphaCharType  ;
(*----------------------------------------------------------------------*)
(* A note about code conventions within a string:                       *)
(*                                                                      *)
(*   0C - end of string code                                            *)
(*   1C - word separator in a string                                    *)
(*   2C - extra code separator                                          *)
(*                                                                      *)
(*----------------------------------------------------------------------*)

CONST
   WordSepCode = 1C ;
   ExtraCodeSep = 2C ;

PROCEDURE IntToSimpleSortLine( InputLine : ARRAY OF CHAR ;
                               Simple: BOOLEAN ;
                               VAR SortLine : ARRAY OF CHAR ) ;

  VAR
     InputPos, InputLength, SortPos : CARDINAL ;
     Char : CHAR ;
  BEGIN
     InputPos := 0 ;
     SortPos := 0 ;
     InputLength := HIGH( InputLine ) ;
     Char := InputLine[ InputPos ] ;
     WHILE (InputPos <= InputLength) AND (Char <> 0C) DO
        SortLine[SortPos] := SimpAlphTable[ Char ] ;
        IF (NOT Simple) AND (SimpAlphTable[ Char ] <> Char) THEN
           (* have an accented (or grouped) character, or WordSep *)
           SortLine[ SortPos] := Char ;
        END ;
        INC( SortPos ) ;
        INC( InputPos ) ;
        Char := InputLine[ InputPos ] ;
     END ;
     SortLine[ SortPos ] := 0C ;
END IntToSimpleSortLine ;



PROCEDURE FullToSortWord(     FullWord : ARRAY OF CHAR ;
                          VAR SortWord : ARRAY OF CHAR ) ;
  VAR
     I            : CARDINAL ;
     NoRetDiacs   : CARDINAL ;
     SortPos      : CARDINAL ;
     SortWordHigh : CARDINAL ;
     FullPos      : CARDINAL ;
     FullWordHigh : CARDINAL ;
     ExtraCodePos : CARDINAL ;
     ExtraCode    : StrAny ;
     LastChar,
     Char         : CHAR ;

  BEGIN
     (* Build simplified word (for sorting) *)
     SortPos      := 0 ;
     SortWordHigh := HIGH( SortWord ) ;
     FullPos      := 0 ;
     FullWordHigh := HIGH( FullWord ) ;
     ExtraCodePos := 0 ;
     NoRetDiacs   := 0 ;
     LastChar     := WordSepCode ;
     WHILE (FullPos <= FullWordHigh) AND (FullWord[FullPos] <> 0C) DO
        Char := FullWord[ FullPos ] ;
        CASE TypeOfChar[ Char ] OF
           Letter, HighKeyChar :
              SortWord[ SortPos ] := SimpAlphTable[ Char ] ;
              INC( SortPos ) ;
              IF SortPos > SortWordHigh THEN
                 (* do a silent truncation by returning to call proc *)
                 RETURN ;
              END ;
              IF SimpAlphTable[ Char ] <> Char THEN
                 (* have an accented (or grouped) character *)
                 ExtraCode[ ExtraCodePos ] := CHR( FullPos - NoRetDiacs + 2 ) ;
                 INC( ExtraCodePos ) ;
                 ExtraCode[ ExtraCodePos ] := Char ;
                 INC( ExtraCodePos ) ;
              END ;     |
           RetDiac :
              (* note: will need to insert after FullPos-1 position *)
              ExtraCode[ ExtraCodePos ] := CHR( FullPos - NoRetDiacs + 2 ) ;
              INC( ExtraCodePos ) ;
              INC( NoRetDiacs ) ;
              ExtraCode[ ExtraCodePos ] := Char ;
              INC( ExtraCodePos ) ;
           ELSE
              IF (Char = WordSepCode) AND (LastChar <> WordSepCode) THEN
                 (* its a word separator character, ignore multiple ones *)
                 ExtraCode[ ExtraCodePos ] := CHR( FullPos + 2 ) ;
                 INC( ExtraCodePos ) ;
                 ExtraCode[ ExtraCodePos ] := Char ;
                 INC( ExtraCodePos ) ;
              END ;
              (* else ignore character *)
        END ;    (* CASE TypeOfChar[ Char ] OF *)
        LastChar := Char ;
        INC( FullPos ) ;
     END ;    (* WHILE (FullPos <= FullWordHigh) AND (FullWord[FullPos] <> 0C) DO *)

     IF ExtraCodePos > 0 THEN
        (* concatenate the extra code to the end of the simplified word
           after the extra code separator character                     *)
        IF SortPos <= SortWordHigh THEN
           SortWord[ SortPos ] := ExtraCodeSep ;
           INC( SortPos ) ;
        END ;
        I := 0 ;
        WHILE (SortPos <= SortWordHigh) AND (I < ExtraCodePos) DO
           SortWord[ SortPos ] := ExtraCode[ I ] ;
           INC( SortPos ) ;
           INC( I ) ;
        END ;
     END ;
     IF SortPos <= SortWordHigh THEN
        SortWord[ SortPos ] := 0C ;
     END ;
  END FullToSortWord ;

PROCEDURE IntToSimpleWord ( Word : ARRAY OF CHAR ;
                            VAR SortWord : ARRAY OF CHAR ) ;
   VAR
     Char         : CHAR ;
     I,J,AL,NS: CARDINAL;
     ED:    BOOLEAN;
     cm:    CurrentModeType;
     FullWord : StrAny ;
   BEGIN
     cm.ModeIn := '0'; cm.ModeOut := '0';
     I := 0 ; J := 0;
     XlateLine( Int2Alp, WordSepCode, Word, cm, AL, LenD, NS, ED, FullWord ) ;
      (* Build simplified word (for sorting) *)
     WHILE (FullWord[I] <> WordSepCode) AND (I <= AL) DO
        Char := FullWord[I] ;
        CASE TypeOfChar[ Char ] OF
           Letter, HighKeyChar:
              SortWord[ J ] := SimpAlphTable[ Char ] ;
              INC(J) ;
        END ;
        INC(I);
      END ;
      SortWord[J] := 0C ;
 END IntToSimpleWord ;

PROCEDURE IntToSortLine(     InputLine : ARRAY OF CHAR ;
                          VAR SortWord : ARRAY OF CHAR ) ;
  VAR
     I            : CARDINAL ;
     NoRetDiacs   : CARDINAL ;
     SortPos      : CARDINAL ;
     SortWordHigh : CARDINAL ;
     FullPos      : CARDINAL ;
     FullWordHigh : CARDINAL ;
     ExtraCodePos : CARDINAL ;
     FullWord, ExtraCode    : StrAny ;
     LastChar,
     Char         : CHAR ;
     AL,NS: CARDINAL;
     ED:    BOOLEAN;
     cm:    CurrentModeType;
   BEGIN
     cm.ModeIn := '0'; cm.ModeOut := '0';
     XlateLine( Int2Alp, WordSepCode, InputLine, cm, AL, LenD, NS, ED, FullWord ) ;
      (* Build simplified word (for sorting) *)
(*     FullToSortWord(FullWord,SortWord); *)

     SortPos      := 0 ;
     SortWordHigh := HIGH( SortWord ) ;
     FullPos      := 0 ;
     FullWordHigh := HIGH( FullWord ) ;
     ExtraCodePos := 0 ;
     NoRetDiacs   := 0 ;
     LastChar     := WordSepCode ;
     WHILE (FullPos <= FullWordHigh) AND (FullWord[FullPos] <> 0C) DO
        Char := FullWord[ FullPos ] ;
        CASE TypeOfChar[ Char ] OF
           Letter, HighKeyChar:
              SortWord[ SortPos ] := SimpAlphTable[ Char ] ;
              INC( SortPos ) ;
              IF SortPos > SortWordHigh THEN
                 (* do a silent truncation by returning to call proc *)
                 RETURN ;
              END ;
              IF SimpAlphTable[ Char ] <> Char THEN
                 (* have an accented (or grouped) character, or WordSep *)
                 SortWord[ SortPos - 1] := Char ;
              END ;
              |
           RetDiac :
              (* note: will need to insert after FullPos-1 position *)
              ExtraCode[ ExtraCodePos ] := CHR( FullPos - NoRetDiacs + 2 ) ;
              INC( ExtraCodePos ) ;
              INC( NoRetDiacs ) ;
              ExtraCode[ ExtraCodePos ] := Char ;
              INC( ExtraCodePos ) ;
           ELSE
              IF (Char = WordSepCode) AND (LastChar <> WordSepCode) THEN
                 (* its a word separator character, ignore multiple ones *)
                 SortWord[ SortPos ] := Char ;
                 INC( SortPos ) ;
                 ExtraCode[ ExtraCodePos ] := CHR( FullPos + 2 ) ;
                 INC( ExtraCodePos ) ;
                 ExtraCode[ ExtraCodePos ] := Char ;
                 INC( ExtraCodePos ) ;
              END ;
              (* else ignore character *)
        END ;    (* CASE TypeOfChar[ Char ] OF *)
        LastChar := Char ;
        INC( FullPos ) ;
     END ;    (* WHILE (FullPos <= FullWordHigh) AND (FullWord[FullPos] <> 0C) DO *)

     IF ExtraCodePos > 0 THEN
        (* concatenate the extra code to the end of the simplified word
           after the extra code separator character                     *)
        IF SortPos <= SortWordHigh THEN
           SortWord[ SortPos ] := ExtraCodeSep ;
           INC( SortPos ) ;
        END ;
        I := 0 ;
        WHILE (SortPos <= SortWordHigh) AND (I < ExtraCodePos) DO
           SortWord[ SortPos ] := ExtraCode[ I ] ;
           INC( SortPos ) ;
           INC( I ) ;
        END ;
     END ;

     IF SortPos <= SortWordHigh THEN
        SortWord[ SortPos ] := 0C ;
     END ;

  END IntToSortLine ;



(*
PROCEDURE SortToIntLine(     SortWord : ARRAY OF CHAR ;
                          VAR FullWord : ARRAY OF CHAR ) ;
  VAR
     SortPos      : INTEGER ;
     FullPos      : CARDINAL ;
     SimpWordLen  : CARDINAL ;
     EndPos       : INTEGER  ;
     SortWordHigh : CARDINAL ;
     FullWordHigh : CARDINAL ;
     ExtraCodePos : CARDINAL ;
     Char         : CHAR ;
     InsertExtraCode : BOOLEAN ;
     done	  : BOOLEAN ;

  BEGIN
        SortWordHigh := HIGH( SortWord ) ;
        SortPos := 0 ;
        FullPos := 0 ;
        FullWordHigh := HIGH( FullWord ) ;
        InsertExtraCode := FALSE ;
        done := FALSE ;
        REPEAT
           IF (ExtraCodePos > SortWordHigh) OR (SortWord[ExtraCodePos] = 0C) THEN
              EndPos := SimpWordLen ;
	      done := TRUE ;
           ELSE
              EndPos := INTEGER(ORD( SortWord[ ExtraCodePos ] )) - 3 ;
              INC( ExtraCodePos ) ;
              Char := SortWord[ ExtraCodePos ] ;
              INC( ExtraCodePos ) ;
              InsertExtraCode := TRUE ;  (* need to insert Char *)
           END ;
           WHILE SortPos <= EndPos DO  (* copy "simple" letters out *)
              IF FullPos > FullWordHigh THEN
                 (* no more room, silent truncation *)
                 RETURN
              END ;
              FullWord[ FullPos ] := SortWord[ SortPos ] ;
              INC( FullPos ) ;
              INC( SortPos ) ;
           END ;
           IF InsertExtraCode THEN
              IF FullPos > FullWordHigh THEN
                 (* no more room, silent truncation *)
                 RETURN
              END ;
              FullWord[ FullPos ] := Char ;
              INC( FullPos ) ;
              IF TypeOfChar[ Char ] = Letter THEN
                 (* skip over un-accented form of letter *)
                 INC( SortPos )
              END ;
              InsertExtraCode := FALSE ;
           END ;
        UNTIL (SortPos > INTEGER(SimpWordLen)) AND done ;

        IF FullPos <= FullWordHigh THEN
           FullWord[ FullPos ] := 0C ;
        END ;
     END ; (* IF ExtraCodePos > SortWordHigh THEN *)

     cm.ModeIn := '0'; cm.ModeOut := '0';
     XlateLine( FAlp2Int, 1C, InputLine, cm, al, ld, ns, EnoughData, FullWord ) ;
      (* Build simplified word (for sorting) *)


  END SortToFullWord ;
  *)

END SortLine.