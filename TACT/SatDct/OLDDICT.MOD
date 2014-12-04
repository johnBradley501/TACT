MODULE SatDict ;

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

IMPORT Storage ;

FROM Utils IMPORT BOpen, BCreate, BClose, BDelete, ReadLine, WrStr,
            TrimBlanks, BResultType, RWType, BFile ,  WrLn,
            month, day, year, LowcaseStr ;

FROM FIO IMPORT Open, Create, Create, Close, AssignBuffer,
                Exists, GetPos, Seek, WrChar, Size, Rename, Erase,
                RdChar, RdStr, EOF, File ;

FROM Str IMPORT
        Slice, Concat, Item , Pos , Match, Delete, Length, Copy, CardToStr,
        Compare, Insert, Append, IntToStr, ItemS, CardToStr;

IMPORT IO;

IMPORT Window ;

FROM LSort IMPORT QSort ;

FROM Storage IMPORT ALLOCATE, DEALLOCATE ;

FROM SYSTEM IMPORT TSIZE, ADDRESS, ADR ;

FROM Lib IMPORT ParamStr, ParamCount ;

FROM VirtualMemory IMPORT
  (* Procs *) AllocateSpace, MakeReal, ReleasePage, MarkDirty, InitVirtualMemory,
              MarkInUse, GetDumpVirtPage, IsEqual, InitSpaceType, EndVirtualMemory,
  (* Vars  *) VirtNil,
  (* Type  *) VirtualAddrType, VirtPageStorePtr ;

FROM SatHash IMPORT
  (* Procs *) InsertHash, SearchHashTable, FreeHashMemory, InitVirtHash, LineType,
              DictPtr, DictList, DictListSize, TestHash , DirectorySize, SegmentSize,
              VDataUnusedSpace, VPosUnusedSpace, SegmentPtr, T ;
(*
FROM BalancedTrees IMPORT
  (* Procs *) MakeListItem, InitialBT, AddListItem, ProcessBT, FindBTItem, AddBTItem,
              BTDataPtr ;
*)

TYPE StrAny = ARRAY [0..150] OF CHAR ;
     CharSet = ARRAY [0..1] OF CHAR ;

     WordInfo = RECORD
        POS : ARRAY [0..50] OF CHAR ;
        RAW : ARRAY [0..25] OF CHAR ;
     END ;


CONST
   Seps = CharSet( 11C ) ;

VAR
  Message     : StrAny ;
  LineNumber, MsgPos      : CARDINAL ;

  TRecNo   : CARDINAL ;
  TRecPos, TotalWords, TotalDifferentWords  : CARDINAL ;
(*  TPtrLen  : INTEGER  ;   (* pos in HyperRec from start *)
  TDataPos : INTEGER  ;   (* pos in HyperRec from end   *)
  NoDataPntrUsed : CARDINAL ;
   Dummy    : ADDRESS ; *)

  NumberOccurs	  : LONGINT ;
  Count		  : LONGINT;
  TotCount	  : LONGINT;
  LastPercentage,
  Percentage, WordPos	  : CARDINAL ;

   ErrorOut, BackupDictIn, MainDictIn, MainDictOut, FileIn, FileOut, DictOut : ARRAY [0..63] OF CHAR ;
   InsertStr, LineIn, ContLine, ContSlice : LineType ;
   TempStr, StrFileSize, StrLineNo : ARRAY[0..20] OF CHAR ;
   Result, DataResult : BResultType ;
   VarRWType : RWType ;
   ErrOut, MainIn, MainOut, FIn, FOut, DOut, TOut : BFile ;
   DummyRead, Result2: BOOLEAN;
   TempLong : LONGINT ;
   CompareResult, TempNum : INTEGER ;
   Word, RawWord : ARRAY[0..25] OF CHAR ;
   NotFoundStr : ARRAY [0..4] OF CHAR ;
   MainLinePos, WordNo, WordStart, WordStartI, POSStart, RAWStart : CARDINAL ;
   EditMain, Choice, CurChar, CurLang : CHAR ;
   LineNo : LONGCARD ;
   InputFileSize, NumberOfWords, NumberOfTags, NumberOfCont : LONGCARD ;
   Dummy, Main, InBracket, ParseFlag, ContOK, ContInLine : BOOLEAN ;
   CurrentWord : WordInfo ;
   TypeLinkedList, HeadWordHeader : VirtualAddrType ;
   xcoord, ycoord : Window.RelCoord ;

PROCEDURE TrimAllBlanks(     InStr  : ARRAY OF CHAR;
                      VAR OutStr : ARRAY OF CHAR);
   VAR  I, J : CARDINAL;
   BEGIN
      Copy( OutStr, InStr ) ;
      WHILE  (OutStr[0] = ' ') OR (OutStr[0] = 11C) DO
         Delete( OutStr , 0, 1) ;
      END ;
      I := Length( OutStr ) ;
      WHILE (I > 0) AND (OutStr[I-1] = ' ') DO
         DEC( I )
      END ;
      IF I <= HIGH(OutStr) THEN OutStr[I] := 0C END ;
   END TrimAllBlanks ;

PROCEDURE GetString( InStr: ARRAY OF CHAR ; Loc : CARDINAL; Len : CARDINAL;
                    VAR Str : ARRAY OF CHAR ) ;
  BEGIN
    Slice( Str, InStr, Loc, Len ) ;
    TrimAllBlanks( Str, Str ) ;
  END GetString ;


PROCEDURE ProcessWord(   VAR Word : ARRAY OF CHAR ) ;

  VAR
     CWord, Key       : StrAny ;
     p		: VirtualAddrType ;
     HashId : LONGINT ;
     Dict   : DictPtr ;
  BEGIN
     INC( WordPos ) ;
     INC( TotalWords ) ;
     ItemS( CWord, Word, Seps, 0 ) ;
     IF NOT SearchHashTable( CurrentWord.RAW, HashId, CurrentWord.POS,
                             CWord, WordPos ) THEN
        AllocateSpace(p , Dict, VDataUnusedSpace, DictListSize ) ;
        Concat( Key, CurrentWord.RAW, CurrentWord.POS ) ;
(*        MakeListItem( TypeLinkedList, Key, p, VBTUnusedSpace, q ) ; *)
        InsertHash( HashId, p, CurrentWord.RAW , CurrentWord.POS,
                    CWord, WordPos, Dict ) ;
        ReleasePage( p, Dict) ;
        INC(TotalDifferentWords) ;
     END ;
     Word[0] := 0C ;
  END ProcessWord ;

PROCEDURE GetInfo ( LI : ARRAY OF CHAR ; VAR I, J : CARDINAL ) ;

TYPE
   CharSet = ARRAY [ 0..8 ] OF CHAR ;
CONST
   Seps = CharSet( 11C,',','.',';','?','!',':',')','(' ) ;

VAR x, k, NoBrackets : CARDINAL ;
    TempSlice : ARRAY [ 0..50 ] OF CHAR ;

    BEGIN
      INC( I , 5 ) ;
      INC( J , 5 ) ;
      k := 0 ;
      NoBrackets := 0 ;
      WHILE ((LI[I] <> '>') OR (NoBrackets > 0)) AND (LI[I] <> 0C) DO
         IF LI[I] = '<' THEN
           INC(NoBrackets) ;
         ELSIF LI[I] = '>' THEN
           DEC(NoBrackets) ;
         ELSIF ( Pos( '[]+{}', LI[I] ) = MAX(CARDINAL) )
                AND ( NoBrackets = 0 ) THEN
           CurrentWord.RAW[k] := LI[I] ;
           INC( k ) ;
         END ;
         INC( I ) ;
         INC( J ) ;
      END ;
      CurrentWord.RAW[k] := 0C ;
      INC( I ) ;
      INC( J ) ;
      LowcaseStr( CurrentWord.RAW, CurrentWord.RAW ) ;
    WHILE (LI[I] <> '<') AND (LI[I] <> 0C) DO
         INC( I ) ;
         INC( J ) ;
      END ;
      INC( I ) ;
      INC( J ) ;
      Slice( TempSlice, LI, I, 3 ) ;
      IF Compare( TempSlice, 'POS' ) = 0 THEN (* all ok *)
        INC( I , 4 ) ;
        INC( J , 4 ) ;
        k := 0 ;
        WHILE (LI[I] <> '>') AND (LI[I] <> 0C) DO
           CurrentWord.POS[k] := LI[I] ;
           INC( k ) ;
           INC( I ) ;
           INC( J ) ;
        END ;
        CurrentWord.POS[k] := 0C ;
(*        k := 0 ;
        WHILE (LI[I] <= 'a') AND (LI[I] >= 'z') DO
          CurrentWord.Lemma[k] := LI[I] ;
          INC( k) ;
          INC(J) ;
          INC(I);
       END ;
       CurrentWord.Lemma[k] := 0C ;
       INC(I ) ;
       INC(J) : *)
     END;
END GetInfo ;



PROCEDURE Parse(  VAR LI : ARRAY OF CHAR );

VAR
   I, IMAX, J, JMAX : CARDINAL ;
   TempLI, TempSlice : LineType ;
   Tag : ARRAY[ 0..20] OF CHAR ;

BEGIN
   I := 0 ;
   J := 0 ;
   IF ContInLine THEN
      Concat( LI, RawWord, LI ) ;
      I := Length( RawWord ) ;
      ContInLine := FALSE ;
      J := I ;
      WordStartI := 0 ;
      WordStart := 0 ;
   END ;
   IMAX := Length( LI ) ;
   Copy( TempLI, LI ) ;
   WHILE I < IMAX DO
      CASE LI[I] OF
        '<','['         :
               Slice( TempSlice, LI, I + 1, 3 ) ;
               IF Compare( TempSlice, 'RAW' ) = 0 THEN
                  GetInfo( LI , I , J ) ;
               ELSE
                 InBracket := TRUE ;
                 IF LI[I + 1] = 'L' THEN
                   IF LI[I + 3] = 'E' THEN
                     ParseFlag := TRUE ;
                     CurLang := 'E' ;
                   ELSE
                     ParseFlag := FALSE ;
                     CurLang := 'x' ;
                   END ;
                 ELSIF (LI[I + 1] = 'T') AND (LI[I + 2] ='T') THEN
                   Slice( TempSlice, LI, I + 4 , 4 ) ;
                   IF ( Compare( TempSlice , 'main' ) = 0 ) AND
                      ( CurLang = 'E' ) THEN
                      ParseFlag := TRUE ;
                   ELSE
                      ParseFlag := FALSE ;
                   END ;
                   INC( I , 2 ) ;
                   INC( J , 2 ) ;
                 ELSIF (LI[I + 1] = '<') OR (LI[I + 1] = '[') THEN
                   INC(I) ;
                   INC(J) ;
                 END ;
               END ;
                |
        '>',']'      :
               InBracket := FALSE ;
               IF (LI[I+1] = '>') OR (LI[I+1] = ']') THEN
                  INC(I) ;
                  INC(J) ;
               END ;
                |
        '*','+','{','}' :
             (*   |  '0','1','2','3','4','5','6','7','8','9' : (* do nothing *)*)
                |
        11C,',','.',';','?','!',':',')','(' : (* puncuation *)
              IF ( Word[0] <> 0C ) THEN
                 ProcessWord( Word ) ;
              END ;
        ELSE
           IF (( LI[I] = '-') AND ( LI[I+1] = '|')) AND
               (ParseFlag AND NOT InBracket )           THEN
                 ContInLine := TRUE ;
                 Slice( RawWord, LI, WordStartI, I - WordStartI ) ;
                 I := IMAX ;
                 Slice( TempLI, TempLI, 0, WordStart ) ;
           ELSIF ParseFlag AND NOT InBracket THEN
                 IF ( LI[I] <> ' ' ) AND (Word[0] = 0C) THEN
                     WordStart := J ;
                     WordStartI := I ;
                     Append( Word, LI[ I ] ) ;
                 ELSIF  ( LI[ I ] = ' ' ) AND ( Word[0] <> 0C ) THEN
                     ProcessWord( Word ) ;
                 ELSIF Word[0] <> 0C THEN
                     Append( Word , LI[ I ] ) ;
                 END ;
           END ;
        END ; (* CASE *)
        INC(I) ;
        INC(J) ;
    END ;     (* WHILE *)
    IF (Word[0] <> 0C) AND NOT ContInLine THEN
       ProcessWord( Word ) ;
    END ;
    IF (TempLI[0] <> 0C) THEN
(* ????       WrStr( FOut, TempLI, Result ) ;
       WrLn( FOut, Result ) ;
*)
       IO.WrCard( LineNumber , -1 ) ;
       Window.GotoXY( xcoord, ycoord ) ;
    END ;
END Parse ;


PROCEDURE ProcessText ;


   BEGIN
      EOF := FALSE ;
      DummyRead := ReadLine( FIn, LineIn, Result2, DataResult ) ;
      xcoord := Window.WhereX() ;
      ycoord := Window.WhereY() ;
      WHILE EOF <> TRUE DO
      INC( LineNumber ) ;
       TrimAllBlanks( LineIn, LineIn ) ;
       IF LineIn[0] <> 0C THEN
           Parse( LineIn ) ;
        ELSE
           IO.WrCard( LineNumber, -1 ) ;
           Window.GotoXY( xcoord , ycoord ) ;
        END ;
        DummyRead := ReadLine( FIn, LineIn, Result2, DataResult ) ;
      END ;
END ProcessText ;

PROCEDURE OutputWord ;
VAR
   P   : DictPtr ;
   OutLine, TempStr, TempWord : ARRAY [0..128] OF CHAR ;
   OK : BOOLEAN ;
   I, J, L, M               : CARDINAL ;
   K		      : INTEGER ;
   Result             : BResultType;
   VCurSeg, VTempPtr, VTempNextPtr : VirtualAddrType ;
   CurSeg : SegmentPtr ;

BEGIN
   BCreate( TOut, 'dictlist.tag', TRUE, Result ) ;
   FOR I := 0 TO DirectorySize -1 DO
       VCurSeg := T.Directory[I] ;
       IF NOT IsEqual( VCurSeg, VirtNil) THEN
         MakeReal( VCurSeg, CurSeg ) ;
         FOR J := 0 TO SegmentSize -1 DO
            VTempPtr := CurSeg^[J] ;
            WHILE NOT IsEqual( VTempPtr , VirtNil) DO
              MakeReal( VTempPtr, P ) ;
              INC( WordNo ) ;
              M := Length(P^.Word) - 1 ;
              L := 0 ;
              TempWord[0] := 0C ;
              WHILE L <= M DO
                CASE P^.Word[L] OF
                  '{','}','+' : ;
                  ELSE
                    Append(TempWord, P^.Word[L]) ;
                END ;
                INC( L ) ;
              END ;
              Concat( OutLine, '"', TempWord ) ;
              Append( OutLine, '","') ;
              Append( OutLine, P^.POS ) ;
              Append( OutLine, '","') ;
              Append( OutLine, P^.Lemma );
              Append( OutLine, '",') ;
              CardToStr( LONGCARD(P^.NoOccurs), TempStr, 10 , OK) ;
              Append( OutLine, TempStr ) ;
              WrStr( TOut, OutLine, Result ) ;
              WrLn( TOut, Result ) ;
              VTempNextPtr := P^.Next ;
              ReleasePage( VTempPtr, P ) ;
              VTempPtr := VTempNextPtr ;
           END ;
        END ;
        ReleasePage( VCurSeg, CurSeg ) ;
      END ;
   END ;
   BClose( TOut, Result ) ;
END OutputWord ;

PROCEDURE UpdateMain ;

VAR
  K : INTEGER ;
  MainLine, MainWord, MainPos, SatWord, SatPos, SatLine : ARRAY [0..80] OF CHAR ;
  MainResult, SatResult : BResultType ;

CONST
  Seps2 = CharSet( CHR(42C) ) ;

BEGIN
   IF Main AND Exists( MainDictIn ) THEN
      BOpen( MainIn , MainDictIn, ReadType , MainResult ) ;
      IF MainResult = OK THEN
        Main := TRUE ;
        MainPos[0] := 0C ;
        MainWord[0] := 0C ;
        Dummy := ReadLine( MainIn , MainLine, Result2, MainResult ) ;
        IF MainResult <> OK THEN
          Main := FALSE ;
        ELSE
          ItemS( MainWord, MainLine, Seps, 0 ) ;
          ItemS( MainPos, MainLine, Seps, 1 ) ;
          MainLinePos := Pos( MainLine, MainPos) ;
        END ;
      END ;
   ELSIF Main THEN
        IO.WrStr( 'Main Dictionary (main.dct) not found, will not be updated.');
        IO.WrLn ;
        Main := FALSE ;
   END ;
   IF Main THEN
     BOpen( DOut, DictOut , ReadType, Result ) ;
     Dummy := ReadLine( DOut , SatLine, Result2, SatResult ) ;
     ItemS( SatWord, SatLine, Seps2, 0 ) ;
     ItemS( SatPos, SatLine, Seps2, 2 ) ;
     IF SatResult = OK THEN
       WHILE MainResult = OK DO
          ItemS( SatWord, SatLine, Seps2, 0 ) ;
          ItemS( SatPos, SatLine, Seps2, 2 ) ;
          K := Compare( SatWord , MainWord ) ;
          MainLinePos := Pos( MainLine, MainPos ) ;
          IF K = 0 THEN
                   IF ( Pos( MainPos, SatPos ) = MAX(CARDINAL)) THEN
                     Append( SatPos, ',' ) ;
                     Insert( MainLine, SatPos, MainLinePos ) ;
                   END ;
                   Dummy := ReadLine( DOut , SatLine, Result2, SatResult ) ;
                   ItemS( SatWord, SatLine, Seps2, 0 ) ;
                   ItemS( SatPos, SatLine, Seps2, 2 ) ;
          ELSIF ( K > 0 ) OR ( SatResult <> OK ) THEN
                    WrStr( MainOut , MainLine , Result ) ;
                    WrLn( MainOut , Result ) ;
                    Dummy := ReadLine( MainIn , MainLine, Result2, MainResult ) ;
                    IF MainResult <> OK THEN
                       Main := FALSE ;
                    ELSE
                       ItemS( MainWord, MainLine, Seps, 0 ) ;
                       ItemS( MainPos, MainLine, Seps, 1 ) ;
                       MainLinePos := Pos( MainLine, MainPos) ;
                    END ;
          ELSE (* K < 0 *)
                    IF (SatWord[0] < CHR(48)) OR (SatWord[0] > CHR(57) ) THEN  (* numerals 0..9 *)
                      IO.WrStr('Warning. word not found in main dictionary. Cant update : ');
                      IO.WrStr( SatWord ) ;
                      IO.WrLn ;
                      WrStr( ErrOut, SatWord, Result ) ;
                      WrLn( ErrOut, Result ) ;
                    END ;
                    Dummy := ReadLine( DOut , SatLine, Result2, SatResult ) ;
                    ItemS( SatWord, SatLine, Seps2, 0 ) ;
                    ItemS( SatPos, SatLine, Seps2, 2 ) ;
          END ;
       END ;
     END ;
  END ;
END UpdateMain ;

BEGIN
   Storage.ClearOnAllocate := TRUE ;
   IO.WrStr(' *******************************************************************************');
   IO.WrLn ;
   IO.WrStr(' SatDict is a program written for Prof. I. Lancashire according to his ') ;
   IO.WrLn ;
   IO.WrStr(' specifications. This program creates a satellite dictionary using a tagged ') ;
   IO.WrLn ;
   IO.WrStr(' file marked up with the TagText program and optionally edited. ') ;
   IO.WrLn;
   IO.WrStr(' This program was designed and written by Michael Stairs (1991). It ') ;
   IO.WrLn ;
   IO.WrStr(' uses virtual memory, and virtual hashing modules designed and written by ');
   IO.WrLn ;
   IO.WrStr(' Lidio Presutti and John Bradley, and modified by Michael Stairs. ') ;
   IO.WrLn ;
   IO.WrStr(' ******************************************************************************');
   IO.WrLn ;
   IO.WrLn ;
   IO.WrStr(' Syntax:  satdict filename ');
   IO.WrLn;
   IO.WrLn ;
   IO.WrStr('Where filename is name of text to be processed. The output ') ;
   IO.WrLn;
   IO.WrStr('from SatDict is a file with suffix ".sat" which includes POS information') ;
   IO.WrLn ;
   IO.WrStr('and the word as it occurred in the original text in tagged form <RAW> as well') ;
   IO.WrLn ;
   IO.WrStr('as either the lemmatized or conceptual form. Also included in the total number') ;
   IO.WrLn ;
   IO.WrStr('of occurrences of the word in the text and a pointer to a list of word ') ;
   IO.WrLn;
   IO.WrStr('positions of these occurrences. ') ;
   IO.WrLn ;
   IO.WrLn ;

   IO.WrLn ;

IF ParamCount() = 0 THEN
     (* exit *)
ELSE
   ParamStr( FileIn , 1 ) ;
   TempNum := Pos( FileIn , '.' ) ;
   Slice( DictOut , FileIn , 0 , TempNum ) ;
   Append ( DictOut, '.sat') ;
   BOpen( FIn, FileIn, ReadType, Result ) ;
   IF Result <> OK THEN
      IO.WrStr( FileIn ) ;
      IO.WrStr( ' : text file does not exist. Check name and try again. ') ;
      IO.WrLn ;
      RETURN ;
   END ;
   IO.WrLn ;
   IO.WrStr('Update main dictionary (***last step***)? : (y/n) ');
   IO.RdStr( EditMain );
   IO.WrLn ;
   Copy( MainDictIn, 'main.dct' ) ;
   Copy( BackupDictIn, 'maindct.old' ) ;
   Copy( MainDictOut, 'maindct.tmp' ) ;
   Copy( ErrorOut, 'maindct.err' ) ;
   Main := FALSE ;
   IF Compare( EditMain , 'y') = 0 THEN
     Main := TRUE ;
     BCreate( MainOut, MainDictOut, TRUE, Result ) ;
   END ;

   InitVirtualMemory ;
   InitVirtHash ;
   InitSpaceType( VDataUnusedSpace ) ;
   InitSpaceType( VPosUnusedSpace ) ;
   TypeLinkedList := VirtNil ;
   HeadWordHeader := VirtNil ;
   InBracket := FALSE ;
   ParseFlag := TRUE ;
   ContInLine := FALSE ;
   ContLine[0] := 0C ;
   ContOK := FALSE ;
   LineNumber := 0 ;
   WordPos := 0 ;
   WordNo := 0 ;
   TotalWords  := 0 ;
   TotalDifferentWords := 0 ;
   IO.WrStr( 'Reading text, please be patient. ') ;
   IO.WrLn ;
   IO.WrStr('Processing Line number: ') ;
   Word[0] := 0C ;
   Window.CursorOff ;
   ProcessText ;
   IO.WrLn ;
   IO.WrStr('Writing dictionary entries to file.') ;
   IO.WrLn ;
   OutputWord ;
   FreeHashMemory ;
   EndVirtualMemory ;
   IO.WrStr('Sorting list of dictionary entries into alphabetical order.  ' ) ;
   IO.WrLn ;
   IO.WrStr('Please be patient, this could take a few minutes...');
   IO.WrLn ;
   QSort( 'dictlist.tag', DictOut ) ;
   IO.WrStr( 'Dictionary output directed to file : ') ;
   IO.WrStr( DictOut ) ;
   IO.WrLn ;
   BClose( FIn, Result ) ;
   IO.WrStr('Total number of words processed: ') ;
   IO.WrCard( TotalWords , 0 ) ;
   IO.WrLn ;
   IO.WrStr('Total number of distinct words processed: ') ;
   IO.WrCard( TotalDifferentWords, 0 ) ;
   IO.WrLn ;
   IF Compare( EditMain , 'y') = 0 THEN
     IO.WrStr('Updating main.dct') ;
     IO.WrLn ;
     BCreate( ErrOut, ErrorOut, TRUE, Result ) ;
     UpdateMain ;
     BClose( MainOut, Result ) ;
     BClose( ErrOut, Result ) ;
     IF Exists( BackupDictIn ) THEN
       Erase( BackupDictIn ) ;
     END ;
     Rename( MainDictIn, BackupDictIn ) ;
     IF Exists( MainDictIn ) THEN
       Erase( MainDictIn ) ;
     END ;
     Rename( MainDictOut, MainDictIn ) ;
     IO.WrStr('Update completed.');
     IO.WrLn ;
   END ;

END ; (* IF *)

Window.CursorOn ;

END SatDict .