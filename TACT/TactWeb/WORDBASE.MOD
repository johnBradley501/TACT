IMPLEMENTATION MODULE WordBase;
(* copyright (c) 1989-96 John Bradley, Lidio Presutti, University of Toronto *)

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
 (* type *) XlateStrAny, CurrentModeType,
 (* proc *) XlateLine;
(*----------------------------------------------------------------------*)
(* A note about code conventions within a string:                       *)
(*                                                                      *)
(*   0C - end of string code                                            *)
(*   1C - word separator in a string                                    *)
(*   2C - extra code separator                                          *)
(*                                                                      *)
(*----------------------------------------------------------------------*)

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

PROCEDURE SortToFullWord(     SortWord : ARRAY OF CHAR ;
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
     ExtraCodePos := Str.Pos( SortWord, ExtraCodeSep ) ;
     SortWordHigh := HIGH( SortWord ) ;
     IF (ExtraCodePos > SortWordHigh) OR (ExtraCodePos = 0 (*m.s*)) THEN
        Str.Copy( FullWord, SortWord )
     ELSE
        SortPos := 0 ;
        FullPos := 0 ;
        SimpWordLen := ExtraCodePos - 1 ;  (* pos of last letter in word/string *)
        INC( ExtraCodePos ) ;
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
  END SortToFullWord ;

PROCEDURE IntToSingleSortWord(IntWord  : ARRAY OF CHAR ;
                          VAR SortWord : ARRAY OF CHAR;
                          VAR BadChar:   CHAR ): BOOLEAN ;
VAR T:     StrAny;
    AL,NS: CARDINAL;
    ED:    BOOLEAN;
    cm:    CurrentModeType;

PROCEDURE CheckForSingleWord(): BOOLEAN;
VAR
   NS,i,j:     CARDINAL;
BEGIN
   BadChar := 0C;
   NS := Str.Pos(T, WordSepCode);
   IF NS > HIGH(T) THEN RETURN TRUE END;
   i := 0; j := 0;
   WHILE j < NS DO
      INC(j,LenD[i].Int);
      INC(i);
   END;
   BadChar := IntWord[j];
   RETURN FALSE;
END CheckForSingleWord;

BEGIN
   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine(Int2Alp,WordSepCode (* was 377C *),IntWord,cm,AL,LenD,NS,ED,T);
   FullToSortWord(T,SortWord);
   RETURN CheckForSingleWord();
END IntToSingleSortWord;

PROCEDURE IntToSortWord(     IntWord : ARRAY OF CHAR ;
                          VAR SortWord : ARRAY OF CHAR ) ;
VAR T:     StrAny;
    AL,NS: CARDINAL;
    ED:    BOOLEAN;
    cm:    CurrentModeType;

BEGIN
   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine(Int2Alp,WordSepCode (* was 377C *),IntWord,cm,AL,LenD,NS,ED,T);
   FullToSortWord(T,SortWord);
END IntToSortWord;

PROCEDURE SortToIntWord(     SortWord : ARRAY OF CHAR ;
                          VAR IntWord : ARRAY OF CHAR ) ;
VAR T:     StrAny;
    AL,NS: CARDINAL;
    ED:    BOOLEAN;
    cm:    CurrentModeType;

BEGIN
   cm.ModeIn := '0'; cm.ModeOut := '0';
   SortToFullWord(SortWord,T);
   XlateLine(Alp2Int,'?',T,cm,AL,LenD,NS,ED,IntWord);
END SortToIntWord;

PROCEDURE Int2FirstAlphWord(IntStr:    ARRAY OF CHAR ;
                        VAR EndOfWord: CARDINAL ;
                        VAR IntRslt:   ARRAY OF CHAR ;
                        VAR AlphRslt:  ARRAY OF CHAR);
VAR T:       StrAny;
    AL,NS,i: CARDINAL;
    ED:      BOOLEAN;
    cm:      CurrentModeType;
BEGIN
   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine(Int2Alp,377C,IntStr,cm,AL,LenD,NS,ED,T);
   NS := Str.Pos(T, 377C);
   IF NS <= HIGH(T) THEN T[NS] := 0C
                    ELSE NS := Str.Length(T) END;
   IF NS = 0 THEN
      EndOfWord := 0;
      IntRslt[0] := 0C;
      AlphRslt[0] := 0C;
      RETURN
   END;
   AL := 0;
   FOR i := 0 TO NS-1 DO INC(AL,LenD[i].Int) END;
   EndOfWord := AL;
   Str.Slice(IntRslt,IntStr,0,AL);
   Str.Copy(AlphRslt,T);
END Int2FirstAlphWord;

PROCEDURE SetSortNoBitsPerChar ;
   TYPE  NoBitsMask = ARRAY[4..8] OF CARDINAL ;  (* could prob. do without 4 !? *)
   CONST NoBits = NoBitsMask ( 000FH, 001FH, 003FH, 007FH, 00FFH ) ;
   VAR	Ch : CHAR ;
   BEGIN
	(* now find out how many bits are used for "sort word" encoding *)
	Ch := 377C ;
	WHILE (TypeOfChar[Ch] <> Letter) AND (TypeOfChar[Ch] <> RetDiac) DO
	   DEC( Ch )
	END ;
	SortNoBitsPerChar := 4 ;
	WHILE ORD(Ch) >= NoBits[ SortNoBitsPerChar ] DO
	   INC( SortNoBitsPerChar )
	END ;
   END SetSortNoBitsPerChar ;

BEGIN
   Lib.Fill( ADR(SimpAlphTable), 256, 0C );
END WordBase.
