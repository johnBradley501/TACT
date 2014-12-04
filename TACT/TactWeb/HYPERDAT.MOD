IMPLEMENTATION MODULE HyperDataModel ;
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


IMPORT Lib ;

(* Note from HyperDat.DEF:

    TDBStringFormat = RECORD
		TotalWords : LONGCARD ;
		TDBStr	   : BitOps.PackedStrType ;
		(* where TDBStr is formed as follows:
		   +-------------------------+---------------------------+
		   |   BitPackedSortStr      |       IntStr              |  Not 0C terminated!
		   +-------------------------+---------------------------+
		   0                          TDBStr.PackedLen

		   Notice difference from BitOps.PackedStrType type [we concatenate
		   the internal string to it!
		*)	
	END ;
*)	

PROCEDURE TDBStrCompare( TDBStrPtr1, TDBStrPtr2 : TDBStrPntr ) : INTEGER;
   VAR
	L1, L2, L, Index : CARDINAL;
   BEGIN
	L1 := CARDINAL( TDBStrPtr1^.TDBStr.PackedLen ) ;
	L2 := CARDINAL( TDBStrPtr2^.TDBStr.PackedLen );
	IF L1 < L2 THEN L := L1
	ELSE L := L2 END;
	Index := Lib.Compare( ADR(TDBStrPtr1^.TDBStr.PackedStr),
			      ADR(TDBStrPtr2^.TDBStr.PackedStr), L);
	IF (Index < L) THEN
	   IF TDBStrPtr1^.TDBStr.PackedStr[Index] < TDBStrPtr2^.TDBStr.PackedStr[Index] THEN
	      RETURN -1
	   ELSE
	      RETURN 1;
	   END;
	ELSIF (L1 = L2) THEN
	   RETURN 0
	ELSIF (L1 < L2) THEN
	   RETURN -1
	ELSE
	   RETURN 1;
	END;
   END TDBStrCompare;

PROCEDURE TDBTypeCompare( TDBTypePtr1, TDBTypePtr2 : TDBTypePntr ) : INTEGER;
    VAR
	L1, L2, L, Index : CARDINAL;
    BEGIN
	L1 := CARDINAL( TDBTypePtr1^.PackedWord.PackedLen ) ;
	L2 := CARDINAL( TDBTypePtr2^.PackedWord.PackedLen );
	IF L1 < L2 THEN L := L1
	ELSE L := L2 END;
	Index := Lib.Compare( ADR(TDBTypePtr1^.PackedWord.PackedStr),
			      ADR(TDBTypePtr2^.PackedWord.PackedStr), L);
	IF (Index < L) THEN
	   IF TDBTypePtr1^.PackedWord.PackedStr[Index] < TDBTypePtr2^.PackedWord.PackedStr[Index] THEN
	      RETURN -1
	   ELSE
	      RETURN 1;
	   END;
	ELSIF (L1 = L2) THEN
	   RETURN 0
	ELSIF (L1 < L2) THEN
	   RETURN -1
	ELSE
	   RETURN 1;
	END;
    END TDBTypeCompare;

BEGIN
   TDBIDModel := 'TDB';
   TDBIDModel[3] := 032C; (* ^Z--to prevent typing of file from showing more *)
   PDBIDModel := 'PDB';
   PDBIDModel[3] := 032C; (* ^Z--to prevent typing of file from showing more *)
   CORIDModel := 'COR';
   CORIDModel[3] := 032C; (* ^Z--to prevent typing of file from showing more *)
END HyperDataModel .
