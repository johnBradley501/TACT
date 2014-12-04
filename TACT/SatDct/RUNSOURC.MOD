IMPLEMENTATION MODULE RUNSource ;

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

(*V1=Production *)
(*V2=SpaceCheck *)

FROM SYSTEM IMPORT TSIZE, SIZE ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
IMPORT FIO ;
FROM KeyTranslation IMPORT FILEText;

(*<SpaceCheck
FROM CheckMemory IMPORT
  (* Procs *) MemSnapShot ;
SpaceCheck>*)

(* temporary, for debugging

FROM Windows IMPORT
  (* Procs *) PutMessage ;
*)
IMPORT Lib;
(* FROM DBFile IMPORT
  (* Procs *) StartDBFile, FinishDBFile ;
FROM WordProcessing IMPORT
  (* Procs *) WritePntrData ;
*)
FROM ProcTextSource IMPORT
  (* Procs *) ProcessText,
  (* Vars  *) NoWords, NoTags ;
FROM WordBase IMPORT SortToIntWord, IntToSortWord ;
FROM TokenDataSource IMPORT TypeNumber, InputFileID ;
FROM RunPan IMPORT
  (* Procs *) SetupRunWindows, CleanupRunWindows, PutRunStatus, PutPercentage,
              WriteTextWindow ;
(* -- only needed when debugging ---  **LP**
FROM DumpLists IMPORT
  (* Procs *) DumpStructLists ;
*)
FROM VirtualMemory IMPORT
  (* Procs *) InitVirtualMemory, EndVirtualMemory, InitSpaceType ;
FROM  SatHash IMPORT InitVirtHash, DumpHash, VDataUnusedSpace, SearchHash,
  FreeHashMemory ;
FROM GlobalDefs IMPORT StrAny ;
FROM StartUp IMPORT WordAny, FileData ;
FROM Str IMPORT Compare, Copy, ItemS, Pos, Insert, Append ;
FROM Utils IMPORT BFile, BCreate, WrStr, WrLn, BClose, BOpen, ReadLine,
     GetXlationType, RWType, WriteLine ;
FROM LongSort IMPORT
  (* Procs *) LTurboSort, LSortRelease, LSortReturn, LSortEOS, LSortReset,
              (* LSortFreeUp, *) LSortGetPos ;
FROM PrintModule IMPORT AbortForFileIO;
FROM Translations IMPORT
  (* Type  *) XFileType, XlateStrAny, CurrentModeType,
  (* Vars  *) Int2FAlp, LenD, File2Int, Int2Alp, Alp2Int, Int2File,
  (* Procs *) XClose, XOpenInput, XReadLine, XlateLine, XWrStr, XWrLn, XAppend,
              XOpenOutput, XWriteLine ;

TYPE WordPtr = POINTER TO WordType ;
     WordType = RECORD
         Line : ARRAY [0..127] OF CHAR ;
         Key : WordAny ;
         POS : ARRAY [0..30] OF CHAR ;
     END ;
     DictPtr = POINTER TO DictType ;
     DictType = RECORD
         Line : StrAny ;
         Key : WordAny ;
         POS : WordAny ;
     END ;

VAR
   Message   : StrAny ;
   MsgPos, Percentage    : CARDINAL ;
   ErrorMsg  : StrAny ;
   Word      : WordPtr ;
   LastPercentage, SortResult : CARDINAL ;
   Count, NoCompares           : LONGCARD ;
   OutFile, DictFile, DictOut  : BFile ;
   InputFileName, OutputFileName : StrAny ;
   Action : RWType ;
   DictWord : WordAny ;
   DictLine: StrAny ;
   DictPOS: WordAny ;

PROCEDURE Log2( Num : LONGCARD ) : CARDINAL ;
   VAR
	log2	: CARDINAL ;
	I	: CARDINAL ;
	Temp	: LONGCARD ;
   BEGIN (* calc the number bits in Num *)
	Temp := Num ;
	log2 := 0 ;	
	WHILE Temp <> 0 DO
	   INC( log2 ) ;
	   Temp := Temp DIV 2 ;
	END ;
	(*<Debug
	IO.WrStr( 'Number:' ) ;
	IO.WrLngCard( Num, 10 ) ;
	IO.WrStr( ' log2:' ) ;
	IO.WrCard( log2, 5 ) ;
	IO.WrLn ;
	Debug>*)
(*
	(* now take an upper bound if 2 ** log2  + 2 ** (log2 - 2) < Num *)
	(* ie. if Num is bigger than a quarter of log2 range		 *)
	Temp := 1 ;
	FOR I := 1 TO log2 DO
	   INC( Temp, Temp ) ;
	END ;
	IF Temp + (Temp DIV 4) < Num THEN
	   INC( log2 )
	END ;
*)
	RETURN log2
   END Log2 ;


PROCEDURE PreProcCompare( X, Y : WordPtr ) : BOOLEAN ;
       VAR
           z : INTEGER ;
       BEGIN
	INC(Count);
	Percentage := VAL(CARDINAL,(Count * 100) DIV NoCompares) ;
	IF Percentage > LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage, TRUE ) ;
		LastPercentage := Percentage ;
	END ;
        z := Compare( X^.Key, Y^.Key ) ;
        IF  ( z < 0 ) OR
            (( z = 0 ) AND (Compare( X^.POS, Y^.POS ) < 0 )) THEN
              RETURN TRUE
	END ;
	RETURN FALSE ;
END PreProcCompare ;


PROCEDURE UpdateDCT ;

VAR
    Result, x : CARDINAL ;
(*    Word: WordPtr ;  *)
    al, ns : CARDINAL ;
    cm: CurrentModeType ;
    dummy, EnoughData : BOOLEAN ;
    NewPOS : WordAny ;
    Dict: DictPtr ;
    BadChar : CHAR ;
TYPE
   CharSet = CHAR ;
CONST
   Seps = CharSet( 11C ) ;
BEGIN
    BOpen( DictFile, FileData.DCTFileName, ReadType, Result ) ;
    BOpen( DictOut, FileData.TempDCTFileName, WriteType, Result ) ;
    DictWord[0] := 0C ;
    (* set status value for next phase *)
     Count := 0 ;
     LastPercentage := 0 ;
     (*RES OLD MSG 555
     Updating Input Dictionary... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 555 );
     ALLOCATE( Dict,TSIZE(DictType)   ) ;
     cm.ModeIn := '0' ; cm.ModeOut := '0';
     LastPercentage := 0 ;
     dummy := ReadLine( DictFile, Dict^.Line, EnoughData, Result ) ;
     WHILE Result = 0 DO
           INC(Count);
           Percentage := VAL (CARDINAL , (Count * 100) DIV NoWords) ;
           IF Percentage > LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99  ;	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage, TRUE ) ;
              LastPercentage := Percentage ;
           END ;
           ItemS( Dict^.Key, Dict^.Line, 11C, 0) ;
           XlateLine( File2Int, 1C, Dict^.Key, cm, al, LenD, ns, EnoughData, Dict^.Key ) ;

           ItemS( Dict^.POS, Dict^.Line, 11C, 1) ;
           IF SearchHash( Dict^.Key, Dict^.POS, NewPOS ) THEN (* POS updated *)
                x := Pos( Dict^.Line, Dict^.POS ) ;
                Insert( Dict^.Line, NewPOS, x ) ;
           END ;
           WriteLine( DictOut, Dict^.Line, Result ) ;
           dummy := ReadLine( DictFile, Dict^.Line, EnoughData, Result ) ;
     END ;
     BClose( DictFile, Result ) ;
     BClose( DictOut, Result ) ;
     FIO.Erase( FileData.DCTFileName ) ;
     FIO.Rename( FileData.TempDCTFileName, FileData.DCTFileName ) ;
     DEALLOCATE( Dict, TSIZE( DictType ) ) ;

END UpdateDCT ;



PROCEDURE GetOutput ;  (* m.s. - output words to *.ttt file *)

VAR
    Result, len : CARDINAL ;
    Word   : WordPtr ;
    OutFile : XFileType ;
    ErrorMsg: StrAny ;
    BadChar : CHAR ;
    dummy : BOOLEAN ;
BEGIN
     ALLOCATE( Word,TSIZE(WordType)   ) ;
     LSortReturn( Word^ ) ;
(*     BOpen( OutFile , FileData.SATFileName , WriteType, Result ) ; *)
     dummy := XOpenOutput( FileData.SATFileName, 0C, FILEText, OutFile, ErrorMsg ) ;
     (* set status value for next phase *)
     Count := 0 ;

     LastPercentage := 0 ;
     (*RES OLD MSG 492
     Output of sorted items... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 492 );

     WHILE NOT LSortEOS() AND NOT AbortForFileIO() DO
        INC(Count);
        Percentage := VAL(CARDINAL, ( Count * 100) DIV NoWords) ;
        IF Percentage > LastPercentage THEN
 	  IF Percentage >= 100 THEN
	    Percentage := 99	(* fake a reasonable value *)
	  END ;
          PutPercentage( Percentage, TRUE ) ;
          LastPercentage := Percentage ;
        END ;
(*        WrStr( OutFile, Word^.Line, Result ) ;
        WrLn( OutFile, Result ) ;
*)
        WriteTextWindow( Word^.Line ) ;
        dummy := XWriteLine( OutFile, BadChar, Word^.Line, Result ) ;
        LSortReturn( Word^ ) ;
     END ;
(*     BClose( OutFile, Result ) ; *)

     XClose( OutFile ) ;
END GetOutput ;


PROCEDURE GetInput ;

VAR
    InputFile  : BFile ;
    Word: WordPtr ;
    dummy, EnoughData : BOOLEAN ;
    Result, al, ns : CARDINAL ;
    cm: CurrentModeType ;
    BadChar : CHAR ;
    TempStr : WordAny ;

BEGIN
     cm.ModeIn := '0' ; cm.ModeOut := '0';
(*     dummy := XOpenInput( InputFileName, 0C, FILEText, InputFile, TempStr ) ; *)
     BOpen( InputFile, InputFileName, ReadType, Result ) ;
     (* set status value for next phase *)
     Count := 0 ;
     ALLOCATE( Word,TSIZE(WordType)   ) ;
     LastPercentage := 0 ;
(*     dummy := XReadLine( InputFile, BadChar, Word^.Line, EnoughData, Result ) ; *)
     dummy := ReadLine( InputFile, Word^.Line, EnoughData, Result ) ;
     WHILE Result = 0 DO
           INC(Count);
           Percentage := VAL (CARDINAL , (Count * 100) DIV NoWords) ;
           IF Percentage > LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99  ;	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage, TRUE ) ;
              LastPercentage := Percentage ;
           END ;
           ItemS( Word^.Key, Word^.Line, '"', 0) ;
           ItemS( Word^.POS, Word^.Line, '"',2 ) ;
           XlateLine( File2Int, 1C, Word^.Key, cm, al, LenD, ns, EnoughData, Word^.Key ) ;
           XlateLine( File2Int, 1C, Word^.POS, cm, al, LenD, ns, EnoughData, Word^.POS ) ;
           IntToSortWord( Word^.Key, Word^.Key ) ;
           IntToSortWord( Word^.POS, Word^.POS ) ;

(*           XlateLine( File2Int, 1C, Word^.Line, cm, al, LenD, ns, EnoughData, Word^.Sort ) ; *)
(*           XlateLine( Int2Alp, 1C, Word^.Sort, cm, al, LenD, ns, EnoughData, Word^.Sort ) ; *)
(*           IntToSortWord( Word^.Sort, Word^.Sort ) ; *)
           LSortRelease( Word^ ) ;
           dummy := ReadLine( InputFile, Word^.Line, EnoughData, Result ) ;
     END ;
     Lib.Fill( Word, TSIZE(WordType) , 255 ) ;	(* dummy sentinal record *)
     LSortRelease( Word^ ) ;

     BClose( InputFile, Result ) ;
     DEALLOCATE( Word, TSIZE( WordType ) ) ;
     Count := 0 ;
     LastPercentage := 0 ;
     NoCompares := NoWords * VAL( LONGCARD , Log2( NoWords ) + 4 ) ;
    (*RES OLD MSG 553
     SATDICT is now sorting words ... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 553 );
     PutPercentage( 0 , TRUE ) ;

END GetInput ;


PROCEDURE Run ;

  VAR
    IOResult : CARDINAL ;

BEGIN
  SetupRunWindows ;

  InitVirtualMemory ;
  InitVirtHash;
  InitSpaceType( VDataUnusedSpace ) ;

  (*<SpaceCheck MemSnapShot( 'Run - after "InitVirtualMemory" ' ) ; SpaceCheck>*)

  (*RES OLD MSG 100
  Reading Source Text
  *)
  Count := 0 ;
  PutRunStatus( (*RES REM INS*) 100 ) ;

  IF ProcessText() THEN
     (*RES OLD MSG 554
     Generating a list of distinct words.
     *)
     Count := 0 ;
     PutRunStatus( (*RES REM INS*) 554 ) ;

     DumpHash ;
     IF FileData.UpdateDict THEN
         UpdateDCT ;
     END ;
     FreeHashMemory ;
     EndVirtualMemory ;
     Action := WriteType ;
     Copy( InputFileName , FileData.SATFileName ) ;
     Copy( OutputFileName, FileData.SATFileName ) ;
     (*RES OLD MSG 494
     Distinct words will now be input for sorting.
     *)
     PutRunStatus( (*RES REM INS*) 494 ) ;
     SortResult := LTurboSort( TSIZE(WordType), GetInput, PreProcCompare, GetOutput,
        				  FileData.TempDiskArea ) ;
   END ;
   CleanupRunWindows ;
     (*<SpaceCheck MemSnapShot( 'Run - after "CleanupRunWindows" ' ) ; SpaceCheck>*)

  END Run ;

BEGIN
    Count := 0 ;
    LastPercentage := 0 ;
END RUNSource .


