MODULE TestPack ;

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

FROM BitOps IMPORT PackedStrType, Pack, UnPack ;
IMPORT IO, Lib, Str ;

VAR result : PackedStrType ;
    t1, t2 : ARRAY[0..80] OF CHAR;
    rc     : INTEGER ;
    loop   : CARDINAL ;
    NCompares : CARDINAL ;

PROCEDURE BuildStr( VAR str : ARRAY OF CHAR ) ;
   VAR
	i, Limit : CARDINAL ;
   BEGIN
      Limit := Lib.RANDOM( 80 ) + 1 ;
      FOR i := 0 TO Limit DO
	str[ i ] := CHR( Lib.RANDOM( 63 ) + 1) ;
      END ;
      str[Limit] := 0C ;
   END BuildStr ;

BEGIN
	NCompares := 5000 ;
	IO.WrStr( "Performing " ) ;
	IO.WrCard( NCompares, 5 ) ;
	IO.WrStr( " compares:" ) ;
	IO.WrLn ;
	FOR loop := 1 TO NCompares DO
	   BuildStr( t1 ) ;
	   Pack( t1, result, 6 ) ;
	   UnPack( result, t2, 6 ) ;
	   rc := Str.Compare( t1, t2 ) ;
	   IF rc <> 0 THEN
	      IO.WrStr( "Mismatch: t1=" ) ;
	      IO.WrStr( t1 ) ;
	      IO.WrStr( "  t2=" ) ;
	      IO.WrStr( t2 ) ;
	      IO.WrLn ;
	   END ;
	END ;
	IO.WrStr( "Comparisons completed." ) ;
	IO.WrLn ;
END TestPack .