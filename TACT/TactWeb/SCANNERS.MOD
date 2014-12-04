IMPLEMENTATION MODULE ScannerSource;
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
  (* type *)  RuleWindowDataType, CriteriaType,
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
   QueryPos:          CARDINAL;
   ScannerOCList:     ARRAY[0..20] OF CHAR;
   ParenCount:	      INTEGER;
   RightParenPos:     CARDINAL;
   Query:             POINTER TO CriteriaType;
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
       Query^[QueryPos] := 0C;
       ScnRslt := 0
   ELSE
      INC(QueryPos,I);
      ScnRslt := LetterSeqScanVal
   END
END CollectAlphaChars;

BEGIN
   IF Start THEN
      State := SkipBlanks;	(* maintain compatability with prev versions of scannner *)
      IF NOT GotEndText THEN GetInitialData END;
      ThisIsDQuote := FALSE;
      QueryPos := 0;
      ParenCount := 0;
      Query := ADR(RuleWindowData.Criteria);
   END;
   ItemData.IntStr := '';
   ItemData.AlpStr := '';
   LastWasDQuote := ThisIsDQuote;
   ThisIsDQuote := FALSE;
(*
   IF Query^[QueryPos] = 0C THEN
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
*)
   IF State = Quoted THEN
	State := GetAlphaStr ;	(* previous state was a double quote! *)
   ELSE
	State := SkipBlanks;	(* maintain compatability with prev versions of scannner *)
   END ;
   done := FALSE;
   REPEAT
      IF Query^[QueryPos] = 0C THEN
         IF State = GetString THEN
            (*RES OLD MSG 160
            The string "%0" is missing a closing delimiter.
            *)
            MsgString(StrDelim,0);
            PutResError( (*RES REM INS*) 160 );
            ItemData.IntStr := '';
            RETURN 0
         ELSIF ParenCount > 0 THEN
	    DEC( ParenCount ) ;
	    ItemData.IntStr[0] := ')' ;
	    ItemData.IntStr[1] := 0C;
	    RETURN RightParenPos ;
	 ELSE
	    Str.Copy(ItemData.IntStr,EndOfCriteriaText);
	    RETURN EndOfCommandScanVal
	 END ;
      END;
      Ch := Query^[QueryPos];
      CASE State OF
         SkipBlanks:
           IF (Ch = ' ') THEN
              INC(QueryPos)
           ELSE
	      IF Ch = '(' THEN
		 INC( ParenCount )
	      ELSIF Ch = ')' THEN
		 DEC( ParenCount )
	      END ;	      	
              I := Str.Pos(ScannerOCList, Ch );
              IF I <= HIGH(ScannerOCList) THEN
                 IF (Ch = '(') AND (Query^[QueryPos+1] = '*') THEN
		    DEC( ParenCount );
                    INC(QueryPos,2);
                    State := ProcessComment;
                 ELSE
                    ItemData.IntStr[0] := Ch;
                    ItemData.IntStr[1] := 0C;
                    ItemData.WhichPos := QueryPos;
                    INC(QueryPos);
                    (* ignore spaces between " and first character  *LP* *)
		    WHILE (Query^[QueryPos] = ' ') DO INC(QueryPos)  END ;
                    done := TRUE;
                    ScnRslt := I + 1;
                    ThisIsDQuote := Ch = '"';
		    IF ThisIsDQuote THEN  State := Quoted  END ;
                 END;
              ELSIF Ch = "'" THEN
                   State := GetString;
                   IP := 0;
                   StrDelim := Ch;
                   INC(QueryPos);   (* note: point past the "'" *)
                   ItemData.WhichPos := QueryPos;
              ELSIF (Ch >= '0') AND (Ch <= '9') THEN
                   State := GetNumb;
                   IP := 0;
                   ItemData.WhichPos := QueryPos;
              ELSIF (Ch = "\") THEN
                   IF Query^[QueryPos+1] = 0C THEN
                      (*RES OLD MSG 254
                      Do not put the Escape Character "\" at the end of a line.
                      *)
                      PutResError( (*RES REM INS*) 254 );
                      ItemData.IntStr := '';
                      RETURN 0
                   END;
                   INC(QueryPos);
                   StrPtr := ADR(Query^[QueryPos]);
                   CollectAlphaChars;
                   IF ScnRslt <> 0 THEN
			done := TRUE ;
			ScnRslt := RegExpEscapeCode
		   END;
              ELSE
                   ItemData.WhichPos := QueryPos;
                   State := GetAlphaStr
              END;
           END;
       | GetNumb:
           IF (Ch >= '0') AND (Ch <= '9') THEN
              ItemData.IntStr[IP] := Ch;
              INC(IP);
              INC(QueryPos)
           ELSIF (CAP(Ch) = 'V') OR (CAP(Ch) = 'R') THEN
              ItemData.IntStr[IP] := Ch;
              INC(IP);
              INC(QueryPos);
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

           StrPtr := ADR(Query^[QueryPos]);
           IF LastWasDQuote THEN
              CollectAlphaChars
           ELSIF CompareKeyWords(StrPtr,WhenHeaderWord,ItemData.IntStr,I) THEN
              INC(QueryPos,I);
              ScnRslt := WhenHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,PosHeaderWord,ItemData.IntStr,I) THEN
              INC(QueryPos,I);
              ScnRslt := PosHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,FreqHeaderWord,ItemData.IntStr,I) THEN
              INC(QueryPos,I);
              ScnRslt := FreqHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,RegExpHeaderWord,ItemData.IntStr,I) THEN
              INC(QueryPos,I);
              ScnRslt := RegExpHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,SimilHeaderWord,ItemData.IntStr,I) THEN
              INC(QueryPos,I);
              ScnRslt := SimilHeaderScanVal;
           ELSIF CompareKeyWords(StrPtr,SpanHeaderWord,ItemData.IntStr,I) THEN
              INC(QueryPos,I);
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
           INC(QueryPos)
       | ProcessComment:
           IF (Ch = '*') AND (Query^[QueryPos+1] = ')') THEN
              INC(QueryPos,2);
              State := SkipBlanks;
           ELSE
              INC(QueryPos)
           END;
      ELSE
           ProgramErrorAndHalt('Bad State in Scanner')
      END; (* CASE *)
   UNTIL done;

   ItemData.WhichLine := 0;
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
