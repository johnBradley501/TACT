IMPLEMENTATION MODULE RUNSource ;

(* copyright (c) 1991-96 Ian Lancashire, Mike Stairs, University of Toronto *)

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
  (* Procs *) SetupRunWindows, CleanupRunWindows, PutRunStatus, PutPercentage ;
(* -- only needed when debugging ---  **LP**
FROM DumpLists IMPORT
  (* Procs *) DumpStructLists ;
*)
FROM VirtualMemory IMPORT
  (* Procs *) InitVirtualMemory, EndVirtualMemory, InitSpaceType ;
FROM  PreHash IMPORT InitVirtHash, DumpHash, VWordUnusedSpace ;
FROM GlobalDefs IMPORT StrAny ;
FROM StartUp IMPORT WordAny, FileData ;
FROM Str IMPORT Compare, Copy ;
FROM Utils IMPORT BFile, BCreate, WrStr, WrLn, BClose, BOpen, ReadLine,
     GetXlationType, RWType ;
FROM LongSort IMPORT
  (* Procs *) LTurboSort, LSortRelease, LSortReturn, LSortEOS, LSortReset,
              (* LSortFreeUp, *) LSortGetPos ;
FROM PrintModule IMPORT AbortForFileIO;
FROM Translations IMPORT
  (* Type  *) XFileType, XlateStrAny, CurrentModeType,
  (* Vars  *) Int2FAlp, LenD,
  (* Procs *) XClose, XOpenInput, XReadLine, XlateLine, XWrStr, XWrLn, XAppend,
              XOpenOutput, XWriteLine ;

TYPE WordPtr = POINTER TO WordAny ;

VAR
   Message   : StrAny ;
   MsgPos, Percentage    : CARDINAL ;
   ErrorMsg  : StrAny ;
   Word      : WordPtr ;
   LastPercentage, SortResult : CARDINAL ;
   Count, NoCompares           : LONGCARD ;
   OutFile  : BFile ;
   InputFileName, OutputFileName : StrAny ;
   Action : RWType ;


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

       BEGIN
	INC(Count);
	Percentage := VAL(CARDINAL,(Count * 100) DIV NoCompares) ;
	IF Percentage >= LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage, TRUE ) ;
		LastPercentage := Percentage ;
	END ;

        IF  ( Compare(X^ , Y^ ) < 0 ) THEN
              RETURN TRUE
	END ;
	RETURN FALSE ;
 END PreProcCompare ;



PROCEDURE GetOutput ;  (* m.s. - output words to *.lst or *.tag file *)

VAR
    Result, len : CARDINAL ;
    Word, PrevWord   : WordPtr ;
    OutFile : XFileType ;
    Mode: ARRAY [0..7] OF CHAR ;
    ErrorMsg : StrAny ;
    dummy : BOOLEAN ;
    BadChar : CHAR ;
BEGIN
     ALLOCATE( Word,TSIZE(WordAny)   ) ;
     ALLOCATE( PrevWord,TSIZE(WordAny)   ) ;

     LSortReturn( Word^ ) ;
     PrevWord^[0] := 0C ;
     GetXlationType( FileData.InputFileName, Mode ) ;
     IF Mode[0] = 0C THEN Copy(Mode,FILEText) END;

(*     BOpen( OutFile , OutputFileName , Action, Result ) ; *)
     IF Action = WriteType THEN
        dummy := XOpenOutput( OutputFileName, 0C, Mode , OutFile, ErrorMsg ) ;
     ELSE
        dummy := XAppend( OutputFileName, 0C, Mode , OutFile, ErrorMsg ) ;
     END ;
     (* set status value for next phase *)
     Count := 0 ;

     LastPercentage := 0 ;
     (*RES OLD MSG 492
     Output of sorted items... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 492 );

     WHILE NOT LSortEOS() AND NOT AbortForFileIO() DO
        INC(Count);
        Percentage := VAL(CARDINAL, ( Count * 100 ) DIV NoWords) ;
        IF Percentage >= LastPercentage THEN
 	  IF Percentage >= 100 THEN
	    Percentage := 99	(* fake a reasonable value *)
	  END ;
          PutPercentage( Percentage, TRUE ) ;
          LastPercentage := Percentage ;
        END ;
        SortToIntWord( Word^, Word^ ) ;
        IF Compare( Word^, PrevWord^ ) <> 0 THEN
	  Result := XWrStr( OutFile, Word^, Result ) ;
          XWrLn( OutFile, Result ) ;
	END ;
        Copy( PrevWord^, Word^ ) ;
        LSortReturn( Word^ ) ;
     END ;
     XClose( OutFile ) ;
END GetOutput ;

(*
PROCEDURE ProcText ;
   BEGIN
      IF NOT ProcessText() THEN
         SortOK := FALSE ;
      END ;
END ProcText ;
*)

PROCEDURE GetInput ;

VAR
    Result : CARDINAL ;
    InputFile  : BFile ;
    Word   : WordPtr ;
    dummy, EnoughData : BOOLEAN ;
BEGIN
     BOpen( InputFile , InputFileName, ReadType, Result ) ;
     ALLOCATE( Word,TSIZE(WordAny)   ) ;
     (* set status value for next phase *)
     Count := 0 ;
     Word^[0] := 0C ;
     LastPercentage := 0 ;
     dummy := ReadLine( InputFile, Word^, EnoughData, Result ) ;
     WHILE Result = 0 DO
           INC(Count);
           Percentage := VAL (CARDINAL , (Count * 100) DIV NoWords) ;
           IF Percentage >= LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99  ;	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage, TRUE ) ;
              LastPercentage := Percentage ;
           END ;
           IntToSortWord( Word^, Word^ ) ;
           LSortRelease( Word^ ) ;
           dummy := ReadLine( InputFile, Word^, EnoughData, Result ) ;
     END ;
     Lib.Fill( Word, TSIZE(WordAny) , 255 ) ;	(* dummy sentinal record *)
     LSortRelease( Word^ ) ;

     BClose( InputFile , Result ) ;
     DEALLOCATE( Word, TSIZE( WordAny ) ) ;
     Count := 0 ;
     LastPercentage := 0 ;
     NoCompares := NoWords * VAL( LONGCARD , Log2( NoWords ) + 4 ) ;
    (*RES OLD MSG 493
     PREPROC is now sorting words ... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 493 );
     PutPercentage( 0 , TRUE ) ;

END GetInput ;


PROCEDURE Run( VAR MsgStr: ARRAY OF CHAR ) ;

  VAR
    IOResult : CARDINAL ;

  BEGIN
     SetupRunWindows ;

     InitVirtualMemory ;
     InitVirtHash;
     InitSpaceType( VWordUnusedSpace ) ;

     (*<SpaceCheck MemSnapShot( 'Run - after "InitVirtualMemory" ' ) ; SpaceCheck>*)

   (*RES OLD MSG 100
     Reading Source Text
     *)
     BCreate(OutFile , FileData.ListFileName , TRUE, IOResult ) ;
     Count := 0 ;
     PutRunStatus( (*RES REM INS*) 100 ) ;

     IF ProcessText() THEN
        DumpHash( OutFile ) ;
        BClose( OutFile , IOResult ) ;
        Action := WriteType ;
        Copy( InputFileName , FileData.ListFileName ) ;
        Copy( OutputFileName, FileData.ListFileName ) ;
        NoWords := TypeNumber ;
     (*RES OLD MSG 494
     Distinct words will now be sorted.
     *)
     PutRunStatus( (*RES REM INS*) 494 ) ;
     SortResult := LTurboSort( TSIZE(WordAny), GetInput, PreProcCompare, GetOutput,
        				  FileData.TempDiskArea ) ;
  IF SortResult = 0 THEN
   (*RES OLD MSG 495
     Distinct tags will now be sorted.
     *)
(*     BOpen(OutFile , FileData.TagFileName , AppendType, IOResult ) ; *)
     Copy( InputFileName, FileData.TempTagFileName ) ;
     Copy( OutputFileName, FileData.TagFileName ) ;
     Action := AppendType ;
     NoWords := NoTags ;
     Count := 0 ;
     PutRunStatus( (*RES REM INS*) 495 ) ;

     SortResult := LTurboSort( TSIZE(WordAny), GetInput, PreProcCompare, GetOutput,
        				  FileData.TempDiskArea ) ;
     FIO.Erase( FileData.TempTagFileName ) ;
   END ;
   END ;
   CleanupRunWindows ;
     (*<SpaceCheck MemSnapShot( 'Run - after "CleanupRunWindows" ' ) ; SpaceCheck>*)
   IF SortResult = 0 THEN
      Copy( MsgStr, 'PREPROC finished successfully.' ) ;
   ELSE
      Copy( MsgStr, 'PREPROC finished unexpectedly, resulting output files may not be reliable.' ) ;
   END ;
  END Run ;

BEGIN
    Count := 0 ;
    LastPercentage := 0 ;
END RUNSource .


