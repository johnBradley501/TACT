MODULE TestSort ;

(* copyright (c) 1989-96 Ian Lancashire, Lidio Presutti, University of Toronto *)

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

IMPORT IO, Lib;
FROM Lib IMPORT RANDOM ;
FROM Str IMPORT Length, Compare ;
FROM SYSTEM IMPORT TSIZE, SIZE ;
FROM LongSort IMPORT
   (* Procs *) LTurboSort, LSortRelease, LSortReturn, LSortEOS,
		LSortReset, SortAvail ;

FROM FIO IMPORT EOF, File, Open, Create, Close, IOresult, RdStr, WrStr, WrLn,
		WrLngCard, WrCard ;
FROM Lib IMPORT ParamCount, ParamStr, Fill ;
FROM StringIO IMPORT SWriteString, SWriteChar, SWriteCard;
FROM Storage IMPORT ALLOCATE, DEALLOCATE, Available ;

TYPE
   DataTypePtr = POINTER TO DataType ;
   DataType = RECORD
   		key	: LONGCARD ;
   		filler	: ARRAY[0..38] OF CHAR ;
   	      END ;

CONST
   Limit = 100000 ;

VAR
   I		: LONGCARD;
   SortResult	: CARDINAL ;
   ch		: CHAR ;

   ListFileName	: ARRAY[0..64] OF CHAR;
   ListFile	: File;
   TempStr	: ARRAY[0..12] OF CHAR ;
   x, y         : LONGINT ;
   Hrs, Secs, Mins, HSecs : CARDINAL ;
(*$F*)
PROCEDURE GetInput ;
   VAR
	DataRec : DataType ;
   BEGIN
(*	IO.WrStr( 'Memory available before sort (before input): ' ) ;
(*	IO.WrCard( HeapAvail(MainHeap) DIV 64, 4 ) ; *)
        x := SortAvail() ;
        y := 1024 ;
        x := x DIV y ;
        IO.WrLngInt( x, 4 ) ;
	IO.WrStr( 'K' ) ;
	IO.WrLn ;
*)	
	Fill( ADR(DataRec.filler), SIZE(DataRec.filler), 0) ;
	FOR I := 1 TO Limit DO
	   (* create random data records to be sorted *)
	   DataRec.key := VAL(LONGCARD, RANDOM( MAX( CARDINAL )) ) ;
	   LSortRelease( DataRec ) ;
	END ;
(*	IO.WrStr( 'Memory available before sort (after input): ' ) ;
(*	IO.WrCard( HeapAvail(MainHeap) DIV 64, 4 ) ; *)
        x := SortAvail() ;
        y := 1024 ;
        x := x DIV y ;
        IO.WrLngInt( x, 4 ) ;
	IO.WrStr( 'K' ) ;
	IO.WrLn ;
*)	
	IO.WrStr( 'Reading complete.  Sorting ' ) ;
	IO.WrLngCard( Limit, 10 ) ;
	IO.WrStr( ' records; Sort Begins ... ') ;
	IO.WrLn ;
   END GetInput ;

PROCEDURE LessCompare( X, Y : DataTypePtr ) : BOOLEAN ;
(*   VAR  result : BOOLEAN ; *)
   BEGIN
(*	result := X^.key < Y^.key ;
	RETURN result ; *)
	RETURN  X^.key < Y^.key ;
   END LessCompare ;

PROCEDURE GetOutput ;
   VAR
	DataRec : DataType ;
	Prev	: LONGCARD ;
	x, y : LONGINT ;
   BEGIN
	IO.WrStr( 'Sorting complete.  Outputting records ... ' ) ;
        IO.WrLn ;
	IO.WrStr( 'Memory available after sort (before output): ' ) ;
(*	IO.WrCard( HeapAvail(MainHeap) DIV 64, 4 ) ; *)
        x := SortAvail() ;
        y := 1024 ;
        x := x DIV y ;
        IO.WrLngInt( x, 4 ) ;
	IO.WrStr( 'K' ) ;
	IO.WrLn ;
	Prev := 0 ;
	REPEAT
	   LSortReturn( DataRec ) ;
	   IF Prev > DataRec.key THEN
	        IO.WrStr( 'TestSort: Error in sorting -- wrong order.');
	        IO.WrLn ;
	   END ;
	   Prev := DataRec.key ;
	   WrLngCard( ListFile, DataRec.key, 7);
	   WrLn( ListFile ) ;
	   IF IOresult() <> 0 THEN
	        IO.WrStr( 'TestSort: Error writing to SORT.LST: ');
	        Close( ListFile ) ;
	        HALT ;
	   END;
	UNTIL LSortEOS() ;
	Close( ListFile ) ;
   END GetOutput ;

(*$N*)

   BEGIN
	ListFileName := 'SORT.LST';
	ParamStr( TempStr, 1 ) ;
	IF (TempStr[0] = '?') OR (Compare( TempStr, '-h') = 0) OR (Compare( TempStr, '-H') = 0) THEN
	   IO.WrStr( 'Syntax:   TESTSORT [ListFileName]' ) ; IO.WrLn ;
	   IO.WrLn ;
	   IO.WrStr( 'Defaults: ListFileName = SORT.LST' ) ; IO.WrLn ;
	   HALT ;
	END ;
	IF ParamCount() > 0 THEN
	   ParamStr( ListFileName, 1 ) ;
	END ;
	ListFile := Create( ListFileName ) ;
	IF IOresult() <> 0 THEN
	   IO.WrStr( 'Unable to find/open file "' ) ;
	   IO.WrStr( ListFileName ) ;
	   IO.WrStr( '"' ) ;
	   HALT ;
	END ;
	IO.WrStr( 'Output listing file: ' ) ;
	IO.WrStr( ListFileName ) ;
	IO.WrLn ;
	
	IO.WrStr( 'Memory available before sort: ' ) ;
(*	IO.WrCard( HeapAvail(MainHeap) DIV 64, 4 ) ; *)
        x := SortAvail() ;
        y := 1024 ;
        x := x DIV y ;
        IO.WrLngInt( x, 4 ) ;
	IO.WrStr( 'K' ) ;
	IO.WrLn ;
        Lib.GetTime( Hrs, Mins, Secs, HSecs ) ;
        IO.WrStr( ' Start time : ' ) ;
        IO.WrCard( Mins,0 ) ; IO.WrStr( ':') ;
        IO.WrCard( Secs,0 ) ; IO.WrStr( ':') ;
        IO.WrCard( HSecs,0 ) ; IO.WrLn ;
	SortResult := LTurboSort( TSIZE(DataType), GetInput, LessCompare, GetOutput, '\' ) ;
	IO.WrStr( 'Sort result is: ') ;
	IO.WrCard( SortResult, 3 ) ;
	IO.WrLn ;
	IO.WrStr( 'Memory available at end of sort: ' ) ;
(*	IO.WrCard( HeapAvail(MainHeap) DIV 64, 4 ) ; *)
        x := SortAvail() ;
        y := 1024 ;
        x := x DIV y ;
        IO.WrLngInt( x, 4 ) ;
	IO.WrStr( 'K' ) ;
	IO.WrLn ;
        Lib.GetTime( Hrs, Mins, Secs, HSecs ) ;
        IO.WrStr( ' Finish time : ' ) ;
        IO.WrCard( Mins,0 ) ; IO.WrStr( ':') ;
        IO.WrCard( Secs,0 ) ; IO.WrStr( ':') ;
        IO.WrCard( HSecs,0 ) ; IO.WrLn ;
	
   END TestSort .
