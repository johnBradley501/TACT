IMPLEMENTATION MODULE ScannerSource;

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

(*
Ver 1.02,
   - Aug. 23, 1989, L.Presutti
     fix the scanning of regexp escape character ("\") -- was missing "done:=TRUE"
     to return value.
Ver 1.11,
   - Aug. 29, 1989, L.Presutti
     Added "SPAN" refinement for collocation generator.
*)

IMPORT Str ;
FROM SYSTEM IMPORT ADR;
FROM GlobalDefs IMPORT StrAny, StrAnyPntr ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM RuleWindow IMPORT
  (* const*)  NumbCriteria,
  (* type *)  RuleWindowDataType,
  (* vars *)  RuleWindowData;
FROM ResMessages IMPORT
  (* procs *) MsgString, PutResError;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) ReleaseCollection;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM WordBase IMPORT Int2FirstAlphWord;

CONST
   (*RES OLD DTA 14
   '<Criteria End>'
   'WHEN' 'REGEXP' 'POS' 'FREQ' 'SIMIL' 'SPAN'
   *)
   StringsResource = (*RES REM INS*) 14 ;

   DigitSeqScanVal = 22;
   LetterSeqScanVal = 23;
   RegExpEscapeCode = 24;
   RegExpHeaderScanVal = 25;
   CharStringScanVal = 26;
   WhenHeaderScanVal = 27;
   PosHeaderScanVal = 28;
   FreqHeaderScanVal = 29;
   SimilHeaderScanVal = 30;
   SpanHeaderScanVal = 31;
   FoliationScanVal = 32;
   EndOfCommandScanVal = 33;

TYPE
  StateType = (SkipBlanks, GetAlphaStr, GetString, GetNumb, ProcessComment, Quoted);
VAR
   ScCmdLne:          CARDINAL;
   ScCmdPos:          CARDINAL;
   ScannerOCList:     ARRAY[0..20] OF CHAR;
   ParenCount:	      INTEGER;
   RightParenPos:     CARDINAL;
   GivenLine:         StrAny;
   EndOfCriteriaText: ARRAY[0..20] OF CHAR;
   WhenHeaderWord:    ARRAY[0..10] OF CHAR;
   RegExpHeaderWord:  ARRAY[0..10] OF CHAR;
   PosHeaderWord:	ARRAY[0..10] OF CHAR;
   FreqHeaderWord:	ARRAY[0..10] OF CHAR;
   SimilHeaderWord:	ARRAY[0..10] OF CHAR;
   SpanHeaderWord:	ARRAY[0..10] OF CHAR;
   GotEndText:        BOOLEAN;
   ThisIsDQuote:      BOOLEAN;
   State:    StateType;

PROCEDURE Scanner(Start:     BOOLEAN;
              VAR ItemData:  ItemDataType): CARDINAL;
VAR
  StrPtr:   StrAnyPntr;
  IP:       CARDINAL;
  done:     BOOLEAN;
  Ch:       CHAR;
  I:        CARDINAL;
  Word:     StrAny;
  StrDelim: CHAR;
  ScnRslt:  CARDINAL;
  LastWasDQuote:     BOOLEAN;

PROCEDURE GetInitialData;
VAR
   ResC:    ResCollectionType;
   dummy:   BOOLEAN;
BEGIN
   GetDataArray( StringsResource, ResC);
   dummy := GetNextDataArrayStringItem(ResC, EndOfCriteriaText);
   dummy := GetNextDataArrayStringItem(ResC, WhenHeaderWord);
   dummy := GetNextDataArrayStringItem(ResC, RegExpHeaderWord);
   dummy := GetNextDataArrayStringItem(ResC, PosHeaderWord);
   dummy := GetNextDataArrayStringItem(ResC, FreqHeaderWord);
   dummy := GetNextDataArrayStringItem(ResC, SimilHeaderWord);
   dummy := GetNextDataArrayStringItem(ResC, SpanHeaderWord);
   ReleaseCollection(ResC);
   GotEndText := TRUE;
END GetInitialData;

PROCEDURE CompareKeyWords(A:   StrAnyPntr;
                          B:   ARRAY OF CHAR;
                      VAR C:   ARRAY OF CHAR;
                      VAR I:   CARDINAL): BOOLEAN;
BEGIN
   I := 0;
   WHILE (B[I] <> 0C) AND (CAP(A^[I]) = CAP(B[I])) DO
      IF I <= HIGH(C) THEN C[I] := A^[I] END;
      INC(I)
   END;
   IF (B[I] = 0C) AND (CAP(A^[I]) >= 'A') AND (CAP(A^[I]) <= 'Z') THEN
      RETURN FALSE
   END;
   IF I <= HIGH(C) THEN C[I] := 0C END;
   RETURN (B[I] = 0C);
END CompareKeyWords;

PROCEDURE CollectAlphaChars;
BEGIN
   Int2FirstAlphWord(StrPtr^, I, ItemData.IntStr, ItemData.AlpStr);
   IF I = 0 THEN
       (*RES OLD MSG 162
       Your specification has the unrecognized character "%0".
       *)
       MsgString(Ch,0);
       PutResError( (*RES REM INS*) 162 );
       ItemData.IntStr[0] := Ch;
       ItemData.IntStr[1] := 0C;
       GivenLine[ScCmdPos] := 0C;
       ScnRslt := 0
   ELSE
      INC(ScCmdPos,I);
      ScnRslt := LetterSeqScanVal
   END
END CollectAlphaChars;

BEGIN
   IF Start THEN
      State := SkipBlanks;	(* maintain compatability with prev versions of scannner *)
      IF NOT GotEndText THEN GetInitialData END;
      ThisIsDQuote := FALSE;
      ScCmdLne := 0;
      ScCmdPos := 0;
      ParenCount := 0;
      WITH RuleWindowData DO
	 Str.Insert( Criteria[NumbCriteria-1], ' ', Str.Length(Criteria[NumbCriteria-1]) ) ;
	 Str.Copy( GivenLine, Criteria[0] );
      END ;
   END;
   ItemData.IntStr := '';
   ItemData.AlpStr := '';
   LastWasDQuote := ThisIsDQuote;
   ThisIsDQuote := FALSE;
   IF ScCmdLne >= NumbCriteria THEN
      IF ParenCount > 0 THEN
	 DEC( ParenCount ) ;
	 ItemData.IntStr[0] := ')' ;
	 ItemData.IntStr[1] := 0C;
	 RETURN RightParenPos ;
      ELSE
	 Str.Copy(ItemData.IntStr,EndOfCriteriaText);
	 RETURN EndOfCommandScanVal;
      END ;
   END;
   IF State = Quoted THEN
	State := GetAlphaStr ;	(* previous state was a double quote! *)
   ELSE
	State := SkipBlanks;	(* maintain compatability with prev versions of scannner *)
   END ;
   done := FALSE;
   REPEAT
      WHILE GivenLine[ScCmdPos] = 0C DO
         ScCmdPos := 0;
         INC(ScCmdLne);
         IF ScCmdLne >= NumbCriteria THEN
            IF State = GetString THEN
               (*RES OLD MSG 160
               The string "%0" is missing a closing delimiter.
               *)
               MsgString(StrDelim,0);
               PutResError( (*RES REM INS*) 160 );
               ItemData.IntStr := '';
               RETURN 0
            ELSE
	       IF ParenCount > 0 THEN
		  DEC( ParenCount ) ;
		  ItemData.IntStr[0] := ')' ;
		  ItemData.IntStr[1] := 0C;
		  RETURN RightParenPos ;
	       ELSE
		  Str.Copy(ItemData.IntStr,EndOfCriteriaText);
		  RETURN EndOfCommandScanVal
	       END ;
            END;
         END;
         Str.Copy(GivenLine,RuleWindowData.Criteria[ScCmdLne]);
      END;
      Ch := GivenLine[ScCmdPos];
      CASE State OF
         SkipBlanks:
           IF (Ch = ' ') THEN
              INC(ScCmdPos)
           ELSE
	      IF Ch = '(' THEN
		 INC( ParenCount )
	      ELSIF Ch = ')' THEN
		 DEC( ParenCount )
	      END ;	      	
              I := Str.Pos(ScannerOCList, Ch );
              IF I <= HIGH(ScannerOCList) THEN
                 IF (Ch = '(') AND (GivenLine[ScCmdPos+1] = '*') THEN
		    DEC( ParenCount );
                    INC(ScCmdPos,2);
                    State := ProcessComment;
                 ELSE
                    ItemData.IntStr[0] := Ch;
                    ItemData.IntStr[1] := 0C;
                    ItemData.WhichPos := ScCmdPos;
                    INC(ScCmdPos);
                    (* ignore spaces between " and first character  *LP* *)
		    WHILE (GivenLine[ScCmdPos] = ' ') DO INC(ScCmdPos)  END ;
                    done := TRUE;
                    ScnRslt := I + 1;
                    ThisIsDQuote := Ch = '"';
		    IF ThisIsDQuote THEN  State := Quoted  END ;
                 END;
              ELSIF Ch = "'" THEN
                   State := GetString;
                   IP := 0;
                   StrDelim := Ch;
                   INC(ScCmdPos);   (* note: point past the "'" *)
                   ItemData.WhichPos := ScCmdPos;
              ELSIF (Ch >= '0') AND (Ch <= '9') THEN
                   State := GetNumb;
                   IP := 0;
                   ItemData.WhichPos := ScCmdPos;
              ELSIF (Ch = "\") THEN
                   IF GivenLine[ScCmdPos+1] = 0C THEN
                      (*RES OLD MSG 254
                      Do not put the Escape Character "\" at the end of a line.
                      *)
                      PutResError( (*RES REM INS*) 254 );
                      ItemData.IntStr := '';
                      RETURN 0
                   END;
                   INC(ScCmdPos);
                   StrPtr := ADR(GivenLine[ScCmdPos]);
                   CollectAlphaChars;
                   IF ScnRslt <> 0 THEN
			done := TRUE ;
			ScnRslt := RegExpEscapeCode
		   END;
              ELSE
                   ItemData.WhichPos := ScCmdPos;
                   State := GetAlphaStr
              END;
           END;
       | GetNumb:
           IF (Ch >= '0') AND (Ch <= '9') THEN
              ItemData.IntStr[IP] := Ch;
              INC(IP);
              INC(ScCmdPos)
           ELSIF (CAP(Ch) = 'V') OR (CAP(Ch) = 'R') THEN
              ItemData.IntStr[IP] := Ch;
              INC(IP);
              INC(ScCmdPos);
              ItemData.IntStr[IP] := 0C;
              done := TRUE;
              ScnRslt := FoliationScanVal;
           ELSE
              ItemData.IntStr[IP] := 0C;
              done := TRUE;
              ScnRslt := DigitSeqScanVal;
           END;
       | GetAlphaStr:
           done := TRUE;
           ItemData.AlpStr[0] := 0C;

           StrPtr := ADR(GivenLine[ScCmdPos]);
           IF LastWasDQuote THEN
              IF (Ch = '?') THEN  (* m.s. - Nov 95 - added to handle "? *)
                    ItemData.IntStr[0] := Ch;
                    ItemData.IntStr[1] := 0C;
                    ItemData.WhichPos := ScCmdPos;
                    INC(ScCmdPos);
                    done := TRUE;
                    ScnRslt := Str.Pos(ScannerOCList, Ch) + 1;
              ELSE
                   CollectAlphaChars
              END ;
           ELSIF CompareKeyWords(StrPtr,WhenHeaderWord,ItemData.IntStr,I) THEN
              INC(ScCmdPos,I);
              ScnRslt := WhenHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,PosHeaderWord,ItemData.IntStr,I) THEN
              INC(ScCmdPos,I);
              ScnRslt := PosHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,FreqHeaderWord,ItemData.IntStr,I) THEN
              INC(ScCmdPos,I);
              ScnRslt := FreqHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,RegExpHeaderWord,ItemData.IntStr,I) THEN
              INC(ScCmdPos,I);
              ScnRslt := RegExpHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,SimilHeaderWord,ItemData.IntStr,I) THEN
              INC(ScCmdPos,I);
              ScnRslt := SimilHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,SpanHeaderWord,ItemData.IntStr,I) THEN
              INC(ScCmdPos,I);
              ScnRslt := SpanHeaderScanVal;
           ELSE
              CollectAlphaChars
           END;
       | GetString:
           IF Ch <> StrDelim THEN
              ItemData.IntStr[IP] := Ch;
              INC(IP);
           ELSE
              ItemData.IntStr[IP] := 0C;
              done := TRUE;
              ScnRslt := CharStringScanVal;
           END;
           INC(ScCmdPos)
       | ProcessComment:
           IF (Ch = '*') AND (GivenLine[ScCmdPos+1] = ')') THEN
              INC(ScCmdPos,2);
              State := SkipBlanks;
           ELSE
              INC(ScCmdPos)
           END;
      ELSE
           ProgramErrorAndHalt('Bad State in Scanner')
      END; (* CASE *)
   UNTIL done;

   ItemData.WhichLine := ScCmdLne;
   RETURN ScnRslt;
END Scanner;

PROCEDURE InitScanner;
BEGIN
   GotEndText := FALSE;
   ThisIsDQuote := FALSE;
   ScannerOCList := '"&()*,./:;<=>?@[]|~-%';
   RightParenPos := Str.Pos( ScannerOCList, ')' ) + 1 ;
   State := SkipBlanks;
END InitScanner;
END ScannerSource.
