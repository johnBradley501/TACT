MODULE MtasFreq;

(* copyright (c) 1989,96 Ian Lancashire, Lidio Presutti, University of Toronto *)

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


  CONST
    MaxWordLen = 20;

  TYPE
    WordString = ARRAY [0..MaxWordLen-1] OF CHAR;
    WordRec = RECORD
                SortWord: WordString;
                WordStr: WordString;
                FreqCount: CARDINAL;
              END;

  VAR
    InTextFile: File;
    OutTextFile: File;
    WordsFile: File;
    TextFileName: FileString;
    OutFileName: FileString;

    NoOfTokens: LONGCARD; (* number of words/tokens read *)
    WordEntry: WordRec;
    Blanks: WordString;
    Answer: ARRAY [0..1-1] OF CHAR;


  TYPE
    TypeTokenRec = RECORD
                     Freq: CARDINAL;
                     Occur: CARDINAL;
                   END;
    ChTableType = ARRAY [0C..377C] OF CARDINAL;

  CONST
    MaxR = 100;

  VAR
    WordLenTable: ARRAY [1..MaxWordLen] OF CARDINAL;
    FirstChTable: ChTableType;
    LastChTable:  ChTableType;
    AllChTable:   ChTableType;
    FreqTable: ARRAY [1..MaxR] OF TypeTokenRec;
    r: CARDINAL; 
    MaxFreq: CARDINAL; 
    NoTypes: CARDINAL; (* n *)

    NoTokens: LONGCARD; (* N *)

    AveNoOccur: REAL; (* N / n *)

    VarSq, StandDev, Skew, Kurt, Herdan, Yule: REAL;


  PROCEDURE OutStatPass1;
    VAR
      Current, Next: WordRec;
      TempWordStr: WordString;
      I: CARDINAL;
  BEGIN
  (* create a temp file to store all the words with freqs *)
    AssignFile(WordsFile, '$MTASTMP.$$$', fileOfRecord);
    Rewrite(WordsFile, TSIZE(WordRec));
    FillChar(WordLenTable, SIZE(WordLenTable), 0);
    FillChar(FirstChTable, SIZE(FirstChTable), 0);
    FillChar(LastChTable, SIZE(LastChTable), 0);
    FillChar(AllChTable, SIZE(AllChTable), 0);
    LSortReturn(Current);
    REPEAT
      Current.FreqCount := 0;
      REPEAT
        LSortReturn(Next);
        INC(WordLenTable[Length(Current.SortWord)]);
        TempWordStr := Translate(Current.WordStr, SortTrans1, Alphabet);
        FOR I := 1 TO Length(TempWordStr) DO
          IF TempWordStr[I] IN AlphaSet THEN
            INC(AllChTable[TempWordStr[I]])
          END
        END;
        INC(FirstChTable[TempWordStr[1]]);
        INC(LastChTable[TempWordStr[Length(TempWordStr)]]);
        INC(Current.FreqCount);
      UNTIL ((Current.SortWord <> Next.SortWord) OR (Current.WordStr <> Next.WordStr)) OR
	    LSortEOS();
      Write(WordsFile, Current);
      Current := Next;
    UNTIL LSortEOS(); (* use the "sentinel" trick for counting latter *)
    FillChar(Current.WordStr, MaxWordLen, '?');
    FillChar(Current.SortWord, MaxWordLen, 377C);
    Current.FreqCount := 0FFFFH; 
    Write(WordsFile, Current);
    Close(WordsFile);
  END OutStatPass1; (* OutStatPass1 *)



  PROCEDURE LessStat(Current, Next: WordRec): BOOLEAN; 
    VAR LessStatResult: BOOLEAN; 
  BEGIN 
    LessStatResult := (Current.FreqCount < Next.FreqCount) OR ((Current.FreqCount = Next.FreqCount) AND ((Current.SortWord >
    Next.SortWord) OR ((Current.SortWord = Next.SortWord) AND (Current.WordStr > Next.WordStr))));
    RETURN LessStatResult
  END LessStat; (* LessStat *)


  (*-----------------------------------------------------------------------------
   Formulas for Type/Token ratios:
   f(r) - observed frequency of r occurrences, r = 1, 2, 3, ... R, where
          R is the most frequent word in the text.
        R
       ---
   n = >   f(r)  - number of types (ie. distinct words)
       ---
       r=1
        R
       ---
   N = >   r * f(r)  - number of tokens (ie. text length)
       ---
       r=1
   hapax legomena = f(1)
   dislegomena    = f(2)
   _
   r = N / n     - average number of occurances
             R
    2       ---       _  2
   S =  1/n >   ( r - r )  * f(r)  - variance
            ---
            r=1
               2
   S = SqRt( S  )       - standard deviation
                 R
                ---       _  3             3
   Skew = 1/n { >   ( r - r )  * f(r) } / S   - coefficient of skewness
                ---
                r=1
                 R
                ---       _  4             4
   Kurt = 1/n { >   ( r - r )  * f(r) } / S  - 3   - coefficient of kurtosis
                ---
                r=1
                                    _
   Herdan's characteristic =  S / ( r * SqRt( n ) )
                 R
            4   ---   2               2
   Yule = 10  { >    r  * f(r) } / ( N  - 1 / N )
                ---
                r=1
   ----------------------------------------------------------------------------*) 



  PROCEDURE OutStat; 

    TYPE 

      GraphEnumType = (ChFirst, ChLast, ChAll); 

    VAR 

      MostFreqWord, Current, Next: WordRec; 
      Temp1, Temp2: REAL; 
      TotVocab, TotTokens: LONGCARD;
      Total: LONGCARD;
      MaxCh: CHAR; 
      MaxCount, ScaleFactor, I, J: CARDINAL;


    PROCEDURE DoLetterFreq(ChTable: ChTableType; 
                           GraphType: GraphEnumType);

      VAR 

        I, FLen: CARDINAL; 
        Header2: BigString;
        Letters: ARRAY [0C..377C] OF CHAR; 

      (* sorts variable ChTable *)

      PROCEDURE Quicksort(start, finish: CHAR);
        VAR
          pivot: CARDINAL;
          left, right: CHAR;
          Temp: CARDINAL;
      BEGIN
        (* set pivot point *)
        left := start;
        right := finish;
        pivot := ChTable[CHR((INTEGER((ORD(start)+ORD(finish))) DIV 2))]; (* partition *)
        REPEAT

          WHILE ChTable[left] > pivot DO
            INC(left)
          END;
          WHILE pivot > ChTable[right] DO
            DEC(right)
          END;
          IF left <= right THEN

            (* Swap( ChTable[left], ChTable[right] ) *)
            Temp := ChTable[left];
            ChTable[left] := ChTable[right];
            ChTable[right] := Temp; (* also for letters pointers *)
            Ch := Letters[left];
            Letters[left] := Letters[right];
            Letters[right] := Ch;
            INC(left);
            DEC(right);
          END;
        UNTIL right <= left; (* sort right and left halves *)
        IF start < right THEN
          Quicksort(start, right)
        END;
        IF left < finish THEN
          Quicksort(left, finish)
        END;
      END Quicksort; (* QuickSort *)


    BEGIN
      WrLn(OutTextFile);
      FOR Ch := 0C TO 377C DO
        Letters[Ch] := Ch
      END;
      Total := 0;
      MaxCount := 0;
      TotVocab := 0;
      TotTokens := 0;
      FOR I := 1 TO Length(Alphabet) DO

        Ch := Alphabet[I];
        IF ChTable[Ch] > MaxCount THEN

          MaxCh := Ch;
          MaxCount := ChTable[Ch];
        END; 
        INC(TotVocab);
        INC(TotTokens, ChTable[Ch]);
      END; 
      Total := TotTokens; 
      AveNoOccur := TotTokens/TotVocab;
      VarSq := Float(0);
      CASE GraphType OF 
          ChFirst, ChLast: 

          IF Total DIV MaxCount >= 2 THEN
            (* ie. largest item is less than 50 % *) 
            ScaleFactor := 2
          ELSE 
            ScaleFactor := 1
          END; 
          WrStr(OutTextFile, 'Letter Freq.    %                        Percentage', 0);
          WrLn(OutTextFile);
          WriteChar(OutTextFile, ' ', 19);
          IF ScaleFactor = 1 THEN 
            WrStr(OutTextFile, '    10   20   30   40   50   60   70   80   90  100', 0);
            WrLn(OutTextFile)
          ELSE 
            WrStr(OutTextFile, '         10        20        30        40        50', 0);
            WrLn(OutTextFile)
          END;
          WriteChar(OutTextFile, ' ', 19);
          WrStr(OutTextFile, '+----+----+----+----+----+----+----+----+----+----+', 0);
          WrLn(OutTextFile);
          FOR I := 1 TO Length(Alphabet) DO 
            Ch := Alphabet[I];
            Write(OutTextFile, Ch);
            WriteChar(OutTextFile, ' ', 4);
            WrStr(OutTextFile, ChTable[Ch], 6);
            WriteReal(OutTextFile, ChTable[Ch]/Total*100.0, 7, 2);
            WrStr(OutTextFile, ' |', 0);
            Write(OutTextFile, ?1Replicate(Round(ChTable[Ch]*ScaleFactor*50.0/Total), '*'));
            WrLn(OutTextFile);
            Temp1 := ChTable[Ch]-AveNoOccur;
            Temp2 := (Temp1*Temp1);
            (* * 1*) VarSq := VarSq+Temp2;
          END;
        | ChAll:
          WrStr(OutTextFile, 'Letter  Freq.  % in all  Initial  % in all  Final  % in all', 0);
          WrLn(OutTextFile);
          FOR I := 1 TO Length(Alphabet) DO
            Ch := Alphabet[I];
            IF ChTable[Ch] > 0 THEN
              Write(OutTextFile, Ch);
              WriteChar(OutTextFile, ' ', 6); 
              WrStr(OutTextFile, ChTable[Ch], 5);
              WriteReal(OutTextFile, ChTable[Ch]/Total*100.0, 10, 2);
              WriteChar(OutTextFile, ' ', 2); 
              WrStr(OutTextFile, FirstChTable[Ch], 6);
              WriteReal(OutTextFile, FirstChTable[Ch]/ChTable[Ch]*100.0, 10, 2);
              WriteChar(OutTextFile, ' ', 2); 
              WrStr(OutTextFile, LastChTable[Ch], 6);
              WriteReal(OutTextFile, LastChTable[Ch]/ChTable[Ch]*100.0, 10, 2);
              WrLn(OutTextFile)(* do NOT divide by zero! *) 
            ELSE 
              Write(OutTextFile, Ch);
              WriteChar(OutTextFile, ' ', 6); 
              WrStr(OutTextFile, ChTable[Ch], 5);
              WriteReal(OutTextFile, ChTable[Ch]*1.0, 10, 2);
              WriteChar(OutTextFile, ' ', 2); 
              WrStr(OutTextFile, FirstChTable[Ch], 6);
              WriteReal(OutTextFile, FirstChTable[Ch]*1.0, 10, 2);
              WriteChar(OutTextFile, ' ', 2);
              WrStr(OutTextFile, LastChTable[Ch], 6);
              WriteReal(OutTextFile, LastChTable[Ch]*1.0, 10, 2);
              WrLn(OutTextFile)
            END; 
            Temp1 := ChTable[Ch]-AveNoOccur;
            Temp2 := (Temp1*Temp1); 
            (* * 1*) VarSq := VarSq+Temp2; 
          END; 
         
        ELSE 
      END; 
      Quicksort(0C, 377C); 
      WrLn(OutTextFile); 
      WrStr(OutTextFile, 'Sorted by frequency', 0); 
      WrLn(OutTextFile); 
      WrLn(OutTextFile);
      WrStr(OutTextFile, 'Letter Freq.    %                       Percentage', 0); 
      WrLn(OutTextFile); 
      WriteChar(OutTextFile, ' ', 19); 
      IF ScaleFactor = 1 THEN 
        WrStr(OutTextFile, '    10   20   30   40   50   60   70   80   90  100', 0); 
        WrLn(OutTextFile)
      ELSE
        WrStr(OutTextFile, '         10        20        30        40        50', 0); 
        WrLn(OutTextFile)
      END; 
      WriteChar(OutTextFile, ' ', 19); 
      WrStr(OutTextFile, '+----+----+----+----+----+----+----+----+----+----+', 0); 
      WrLn(OutTextFile); 
      FOR I := 0 TO INTEGER(Length(Alphabet))-1 DO 
        Ch := CHR(I);
        IF ChTable[Ch] > 0 THEN
          WriteChar(OutTextFile, Letters[CHR(I)], 0);
          WriteChar(OutTextFile, ' ', 4);
          WrStr(OutTextFile, ChTable[Ch], 6);
          WriteReal(OutTextFile, ChTable[Ch]/Total*100.0, 7, 2);
          WrStr(OutTextFile, ' |', 0);
          Write(OutTextFile, ?1Replicate(Round(ChTable[Ch]*ScaleFactor*50.0/Total), '*'));
          WrLn(OutTextFile)
        END;
      END;
      VarSq := VarSq/VAL(?1UNDEF, ORD(TotVocab)-1); (* n - 1 instead of n *)
      StandDev := sqrt(VarSq);
      Herdan := StandDev/(AveNoOccur*sqrt(TotVocab));
      WrLn(OutTextFile);
      CASE GraphType OF
          ChFirst:

          WrStr(OutTextFile, 'Total initial letters (Tokens)   = ', 0);
          Header2 := 'initial';
          FLen := 9;
        | ChLast:

          WrStr(OutTextFile, 'Total final letters (Tokens)     = ', 0);
          Header2 := 'final';
          FLen := 11;
        | ChAll:

          WrStr(OutTextFile, 'Total all letters (Tokens)       = ', 0);
          Header2 := 'all';
          FLen := 13;

        ELSE
      END;
      Write(OutTextFile, TotTokens)
*** ERROR **************************
      ) expected
      :  found
      ;
      WrLn(OutTextFile)
*** ERROR ***
    END expected
    )  found


*** TRANSLATION STOPPED ... ***
       WrLn( OutTextFile, 'Total different letters (Types)  = ', TotVocab:8 ) ;
       WrLn( OutTextFile, 'Type/Token ratio                 = ', TotVocab / TotTokens:13:4 ) ;
       WrLn( OutTextFile, 'Arithmetric Mean                 = ', AveNoOccur:13:4 ) ;
{      WrLn( OutTextFile, 'Variance ( S.D. squared )        = ', VarSq:13:4 ) ; }
    ;
       WrLn( OutTextFile, 'Standard Deviation (S.D.)        = ', StandDev:13:4 ) ;
       WrLn( OutTextFile, 'Herdan''s characteristic          = ', Herdan:13:4 ) ;
       WrLn( OutTextFile, 'Repeat rate for ',Header2,' letter "',MaxCh,
                '" = ', TotTokens/MaxCount:FLen:2 ) ;
       WrLn( OutTextFile ) ;
     End

*** ... TRANSLATION RESUMED ***
    END DoLetterFreq; (* DoLetterFreq *)


  BEGIN
    TempMsg('Second Sort completed, calculating statistics now ...');
    (* calculate various statistics *)
    LSortReturn(Current);
    r := 0;
    NoTypes := 0;
    NoTokens := 0;
    REPEAT
      INC(r);
      IF r > MaxR THEN
        MsgDialog('Program limit for number of TYPES exceeded.  Maximum limit is '+
	        ?1IntToStr(MaxR), TRUE);
        DEC(r); (* continue, but ignore all but last type *)
      END;
      FreqTable[r].Freq := Current.FreqCount;
      FreqTable[r].Occur := 0;
      REPEAT
        LSortReturn(Next);
        INC(FreqTable[r].Occur);
      UNTIL (Current.FreqCount <> Next.FreqCount) OR LSortEOS();
      INC(NoTypes, FreqTable[r].Occur);
      INC(NoTokens, FreqTable[r].Occur*FreqTable[r].Freq);
      MostFreqWord := Current;
      Current := Next;
    UNTIL LSortEOS();
    MaxFreq := r;
    AveNoOccur := NoTokens/NoTypes;
    VarSq := 0.0;
    Skew := 0.0;
    Kurt := 0.0;
    Yule := 0.0;
    FOR r := 1 TO MaxFreq DO
      Temp1 := FreqTable[r].Freq-AveNoOccur;
      Temp2 := (Temp1*Temp1);
      VarSq := VarSq+Temp2*FreqTable[r].Occur;
      Skew := Skew+Temp2*Temp1*FreqTable[r].Occur;
      Kurt := Kurt+(Temp2*Temp2)*FreqTable[r].Occur;
      Yule := Yule+(FreqTable[r].Freq*FreqTable[r].Freq)*FreqTable[r].Occur;
    END;
    VarSq := VarSq/VAL(REAL, NoTypes - 1); (* use n - 1 instead of n *)
    StandDev := sqrt(VarSq);
    Skew := (Skew/VAL(REAL, NoTypes - 1 )/((StandDev*StandDev)*StandDev);
    Kurt := (Kurt/VAL(REAL, NoTypes - 1 )/((StandDev*StandDev)*(StandDev*StandDev))-Float(3);
    Herdan := StandDev/(AveNoOccur*sqrt(NoTypes));
    Yule := Yule*10.0E4/(NoTokens*NoTokens-1.0/NoTokens);
    (* produce an OCP style table *)
    TotVocab := 0;
    TotTokens := 0;
    WrStr(OutTextFile, 'Frequency', 0);
    WriteChar(OutTextFile, ' ', 2);
    WrStr(OutTextFile, 'Observed Freq.', 0);
    WriteChar(OutTextFile, ' ', 2);
    WrStr(OutTextFile, 'Words in', 0);
    WriteChar(OutTextFile, ' ', 3);
    WrStr(OutTextFile, 'Tokens', 0);
    WriteChar(OutTextFile, ' ', 3);
    WrStr(OutTextFile, 'Word', 0);
    WriteChar(OutTextFile, ' ', 4);
    WrStr(OutTextFile, '% of', 0);
    WriteChar(OutTextFile, ' ', 5);
    WrStr(OutTextFile, '% of', 0);
    WriteChar(OutTextFile, ' ', 3);
    WrStr(OutTextFile, '% of word', 0);
    WrLn(OutTextFile);
    WrStr(OutTextFile, '  Rank', 0);
    WriteChar(OutTextFile, ' ', 9);
    WrStr(OutTextFile, 'of Rank', 0);
    WriteChar(OutTextFile, ' ', 4);
    WrStr(OutTextFile, 'Frequency', 0);
    WriteChar(OutTextFile, ' ', 4);
    WrStr(OutTextFile, 'Total', 0);
    WriteChar(OutTextFile, ' ', 3);
    WrStr(OutTextFile, 'Total', 0);
    WriteChar(OutTextFile, ' ', 2);
    WrStr(OutTextFile, 'Tokens', 0);
    WriteChar(OutTextFile, ' ', 4);
    WrStr(OutTextFile, 'Words', 0);
    WriteChar(OutTextFile, ' ', 3);
    WrStr(OutTextFile, 'in freq.', 0);
    WrLn(OutTextFile);
    FOR r := 1 TO MaxFreq DO
      WITH FreqTable[r] DO
        INC(TotVocab, Occur);
        INC(TotTokens, Occur*Freq);
(*
                     WrLn( OutTextFile, Freq:6, ' ':6, Occur:8, ' ':2,
                              Freq * Occur:10, ' ':3,
                              TotVocab:8,
                              TotTokens:8, ' ':1,
                              TotVocab/NoTypes*100.0:8:2, ' ':1,
                              TotTokens/NoTokens*100.0:8:2, ' ':1,
                              Freq * Occur / NoTokens*100.0:8:2 ) ; *)

        Write(OutTextFile, Freq);
        WriteChar(OutTextFile, ' ', 0);
        Write(OutTextFile, Occur);
        WriteChar(OutTextFile, ' ', 0);
        Write(OutTextFile, Freq*Occur);
        WriteChar(OutTextFile, ' ', 0);
        Write(OutTextFile, TotVocab);
        Write(OutTextFile, TotTokens);
        WriteChar(OutTextFile, ' ', 0);
        WriteReal(OutTextFile, TotVocab/NoTypes*100.0, 18, -10);
        WriteChar(OutTextFile, ' ', 0);
        WriteReal(OutTextFile, TotTokens/NoTokens*100.0, 18, -10);
        WriteChar(OutTextFile, ' ', 0);
        WriteReal(OutTextFile, Freq*Occur/NoTokens*100.0, 18, -10);
        WrLn(OutTextFile);
      END
    END;
    WrLn(OutTextFile);
    WrLn(OutTextFile);
(*
         WrLn( OutTextFile, 'Number of Types   = ', NoTypes:8 ) ;
         WrLn( OutTextFile, 'Number of Tokens  = ', NoTokens:8 ) ;
         WrLn( OutTextFile, 'Type/Token ratio  = ', NoTypes / NoTokens:12:3 ) ;
         WrLn( OutTextFile, 'Token/Type ratio  = ', AveNoOccur:12:3 ) ;
         WrLn( OutTextFile, 'Hapax Legomena    = ', FreqTable[1].Occur:8 ) ;
         WrLn( OutTextFile, 'Hapax Dislegomena = ', FreqTable[2].Occur:8 ) ;
         WrLn( OutTextFile, 'Hapax Legomena/Dislegomena ratio   = ',
                  FreqTable[1].Occur/FreqTable[2].Occur:10:4 ) ;
         WrLn( OutTextFile, 'Hapax Legomena/Number of Types     = ',
                  FreqTable[1].Occur/NoTypes:10:4 ) ;
         WrLn( OutTextFile, 'Hapax Legomena/Number of Tokens    = ',
                  FreqTable[1].Occur/NoTokens:10:4 ) ;
         WrLn( OutTextFile, 'Hapax Legomena cubed/Types squared = ',
                  (Sqr(FreqTable[1].Occur)*FreqTable[1].Occur) /
                  Sqr(NoTypes):10:4 ) ;
         WrLn( OutTextFile, 'Variance ( S.D. squared )          = ', VarSq:10:4 ) ;
         WrLn( OutTextFile, 'Standard Deviation (S.D.)          = ', StandDev:10:4 ) ;
         WrLn( OutTextFile, 'Coefficient of skewness            = ', Skew:10:4 ) ;
         WrLn( OutTextFile, 'Coefficient of kurtosis            = ', Kurt:10:4 ) ;
         WrLn( OutTextFile, 'Herdan''s characteristic            = ', Herdan:10:4 ) ;
         WrLn( OutTextFile, 'Yule''s characteristic              = ', Yule:10:4 ) ;
         WrLn( OutTextFile, 'Carroll TTR (Types / Sqrt of 2 X Tokens) = ',
                  NoTypes / Sqrt(2.0*NoTokens) :10:4 ) ;
         WrLn( OutTextFile, 'Most Frequent word "',
                  Translate(MostFreqWord.WordStr,SortTrans1,Alphabet),'" occurred ',
                  MostFreqWord.FreqCount, ' times') ;
         WrLn( OutTextFile, 'repeat rate (Tokens / frequency most frequent word) = ',
                  NoTokens / MostFreqWord.FreqCount :10:4 ) ;
*)

    WrStr(OutTextFile, 'Number of Types   = ', 0);
    Write(OutTextFile, NoTypes);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Number of Tokens  = ', 0);
    Write(OutTextFile, NoTokens);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Type/Token ratio  = ', 0);
    Write(OutTextFile, NoTypes/NoTokens);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Token/Type ratio  = ', 0);
    WriteReal(OutTextFile, AveNoOccur, 18, -10);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Hapax Legomena    = ', 0);
    Write(OutTextFile, FreqTable[1].Occur);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Hapax Dislegomena = ', 0);
    Write(OutTextFile, FreqTable[2].Occur);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Hapax Legomena/Dislegomena ratio   = ', 0);
    Write(OutTextFile, FreqTable[1].Occur/FreqTable[2].Occur);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Hapax Legomena/Number of Types     = ', 0);
    Write(OutTextFile, FreqTable[1].Occur/NoTypes);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Hapax Legomena/Number of Tokens    = ', 0);
    Write(OutTextFile, FreqTable[1].Occur/NoTokens);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Hapax Legomena cubed/Types squared = ', 0);
    WriteInt(OutTextFile, ((FreqTable[1].Occur*FreqTable[1].Occur)*FreqTable[1].Occur)/(NoTypes*NoTypes), 0);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Variance ( S.D. squared )          = ', 0);
    WriteReal(OutTextFile, VarSq, 18, -10);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Standard Deviation (S.D.)          = ', 0);
    WriteReal(OutTextFile, StandDev, 18, -10);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Coefficient of skewness            = ', 0);
    WriteReal(OutTextFile, Skew, 18, -10);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Coefficient of kurtosis            = ', 0);
    WriteReal(OutTextFile, Kurt, 18, -10);
    WrLn(OutTextFile); 
    WrStr(OutTextFile, "Herdan's characteristic            = ", 0); 
    WriteReal(OutTextFile, Herdan, 18, -10); 
    WrLn(OutTextFile);
    WrStr(OutTextFile, "Yule's characteristic              = ", 0); 
    WriteReal(OutTextFile, Yule, 18, -10); 
    WrLn(OutTextFile); 
    WrStr(OutTextFile, 'Carroll TTR (Types / Sqrt of 2 X Tokens) = ', 0); 
    WriteReal(OutTextFile, NoTypes/sqrt(2.0*NoTokens), 18, -10); 
    WrLn(OutTextFile); 
    WrStr(OutTextFile, 'Most Frequent word "', 0); 
    WrStr(OutTextFile, Translate(MostFreqWord.WordStr, SortTrans1, Alphabet), 0); 
    WrStr(OutTextFile, '" occurred ', 0); 
    Write(OutTextFile, MostFreqWord.FreqCount); 
    WrStr(OutTextFile, ' times', 0); 
    WrLn(OutTextFile); 
    WrStr(OutTextFile, 'repeat rate (Tokens / frequency most frequent word) = ', 0); 
    Write(OutTextFile, NoTokens/MostFreqWord.FreqCount); 
    WrLn(OutTextFile); 
    WrLn(OutTextFile);
    WrLn(OutTextFile); 
    WrStr(OutTextFile, 'Word Length Statistics', 0); 
    WrLn(OutTextFile);
    WrStr(OutTextFile, '----------------------', 0); 
    WrLn(OutTextFile); 
    WrLn(OutTextFile); 
    Total := 0;
    TotVocab := 0; 
    TotTokens := 0; 
    MaxCount := 0; 
    FOR I := 1 TO MaxWordLen DO 
      IF WordLenTable[I] > MaxCount THEN
        MaxCount := WordLenTable[I]
      END;
      INC(TotVocab, WordLenTable[I]);
      INC(TotTokens, WordLenTable[I]*I);
    END;
    Total := TotVocab;
    IF Total DIV MaxCount >= 2 THEN
      (* ie. largest item is less than 50 % *)
      ScaleFactor := 2
    ELSE
      ScaleFactor := 1
    END;
    WrStr(OutTextFile, 'Word', 0);
    WriteChar(OutTextFile, ' ', 2); 
    WrStr(OutTextFile, 'Freq.', 0); 
    WriteChar(OutTextFile, ' ', 4); 
    WriteChar(OutTextFile, '%', 0);
    WriteChar(OutTextFile, ' ', 24); 
    WrStr(OutTextFile, 'Percentage', 0); 
    WrLn(OutTextFile); 
    WriteChar(OutTextFile, ' ', 0); 
    WrStr(OutTextFile, 'Len', 0); 
    WriteChar(OutTextFile, ' ', 15);
    IF ScaleFactor = 1 THEN 
      WrStr(OutTextFile, '    10   20   30   40   50   60   70   80   90  100', 0); 
      WrLn(OutTextFile)
    ELSE 
      WrStr(OutTextFile, '         10        20        30        40        50', 0); 
      WrLn(OutTextFile)
    END; 
    WriteChar(OutTextFile, ' ', 19); 
    WrStr(OutTextFile, '+----+----+----+----+----+----+----+----+----+----+', 0); 
    WrLn(OutTextFile); (* recycle some variables *)
    AveNoOccur := TotTokens/TotVocab; 
    VarSq := Float(0); (* find last non empty word length *) 
    J := MaxWordLen; 
    WHILE WordLenTable[J] = 0 DO 
      DEC(J)
    END; 
    FOR I := 1 TO J DO
      (*
                 WrLn( OutTextFile, I:4, ' ', WordLenTable[I]:6, WordLenTable[I] / Total * 100.0 :7:2, ' |',
                          Replicate( Round(WordLenTable[I] * ScaleFactor * 50.0 / Total), '*' ) ) ;
      *)
      Write(OutTextFile, I);
      WriteChar(OutTextFile, ' ', 0);
      Write(OutTextFile, WordLenTable[I]);
      WriteReal(OutTextFile, WordLenTable[I]/Total*100.0, 18, -10);
      WrStr(OutTextFile, ' |', 0);
      Write(OutTextFile, ?1Replicate(Round(WordLenTable[I]*ScaleFactor*50.0/Total), '*'));
      WrLn(OutTextFile);
      Temp1 := I-AveNoOccur;
      Temp2 := (Temp1*Temp1);
      VarSq := VarSq+Temp2*WordLenTable[I];
    END;
    VarSq := VarSq/VAL(REAL, TotVocab - 1); (* use n - 1 instead of n *)
    StandDev := sqrt(VarSq);
    Herdan := StandDev/(AveNoOccur*sqrt(TotVocab));
    WrLn(OutTextFile);
(*
         WrLn( OutTextFile, 'Total letters (Tokens)   = ', TotTokens:8 ) ;
         WrLn( OutTextFile, 'Total Words (Types)      = ', TotVocab:8 ) ;
         WrLn( OutTextFile, 'Type/Token ratio         = ', TotVocab / TotTokens:13:4 ) ;
         WrLn( OutTextFile, 'Mean word length         = ', AveNoOccur:13:4 ) ;
         WrLn( OutTextFile, 'Variance (S.D. squared)  = ', VarSq:13:4 ) ;
         WrLn( OutTextFile, 'Standard Deviation (S.D.)= ', StandDev:13:4 ) ;
         WrLn( OutTextFile, 'Herdan''s characteristic  = ', Herdan:13:4 ) ;
    *)
    WrStr(OutTextFile, 'Total letters (Tokens)   = ', 0);
    Write(OutTextFile, TotTokens);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Total Words (Types)      = ', 0);
    Write(OutTextFile, TotVocab);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Type/Token ratio         = ', 0);
    Write(OutTextFile, TotVocab/TotTokens);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Mean word length         = ', 0);
    WriteReal(OutTextFile, AveNoOccur, 18, -10);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Variance (S.D. squared)  = ', 0);
    WriteReal(OutTextFile, VarSq, 18, -10);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Standard Deviation (S.D.)= ', 0);
    WriteReal(OutTextFile, StandDev, 18, -10);
    WrLn(OutTextFile);
    WrStr(OutTextFile, "Herdan's characteristic  = ", 0);
    WriteReal(OutTextFile, Herdan, 18, -10);
    WrLn(OutTextFile);
    WrLn(OutTextFile);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'First letter in words statistics', 0);
    WrLn(OutTextFile);
    WrStr(OutTextFile, '--------------------------------', 0);
    WrLn(OutTextFile);
    DoLetterFreq(FirstChTable, ChFirst);
    WrLn(OutTextFile);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'Final letter in words statistics', 0);
    WrLn(OutTextFile);
    WrStr(OutTextFile, '--------------------------------', 0);
    WrLn(OutTextFile);
    DoLetterFreq(LastChTable, ChLast);
    WrLn(OutTextFile);
    WrLn(OutTextFile);
    WrStr(OutTextFile, 'All letters in words statistics', 0);
    WrLn(OutTextFile);
    WrStr(OutTextFile, '-------------------------------', 0);
    WrLn(OutTextFile);
    DoLetterFreq(AllChTable, ChAll);

  END OutStat; (* OutStat *)
