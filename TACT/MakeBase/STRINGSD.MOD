IMPLEMENTATION MODULE StringsData ;

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
Last Modifications:
- modified String structure in DB.  Now it contains an "offset" to
  the IntStr (ie. length of KeyStr + 1 )
  28 June 1988 - Lidio Presutti
- Dec 1, 1990 - L.P.
  bit packing of "sortstr";  count of total words associated with a string.
*)

IMPORT BitOps ;
FROM SYSTEM  IMPORT ADR ;
FROM Lib     IMPORT Move, Fill ;
FROM Str     IMPORT Copy, Length ;
FROM HyperDataModel IMPORT TDBStringFormat ;
FROM VirtualMemory IMPORT
  (* Procs *) AllocateSpace, MakeReal, (* m.s. MarkDirty, ReleasePage, *) InitSpaceType,
  (* Type  *) VirtualAddrType ;
FROM BalancedTrees IMPORT
  (* type *)  BalTreeItemProcess,
  (* proc *)  InitialBT, FindBTItem, AddBTItem, ProcessBT ;
FROM DBFile IMPORT
  (* Vars  *) HRecNo, HRecPos;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny ;
FROM DBFile IMPORT
  (* Procs *) WriteDBRec, AddTextToDB, AddPtrDataToDB ;
FROM WordBase IMPORT
  (* Vars  *) SortNoBitsPerChar,
  (* Procs *) FullToSortWord ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt ;

CONST
  StrRecBaseSize = 11 ; (* 0C + 2 CHAR + 2 LONGCARD = 1 + 2 + 2*4 = 11 *)


VAR
  TPtrLen  : CARDINAL ;
  TDataPos : CARDINAL ;
  FirstStr : BOOLEAN ;
  StartRecForStr  : CARDINAL ;
  StartPosForStr  : CARDINAL ;
  VStrUnusedSpace : VirtualAddrType ;

PROCEDURE InitStrings( VAR StrHeader : VirtualAddrType ) ;
  BEGIN
     InitialBT( StrHeader, VStrUnusedSpace );
  END InitStrings ;


PROCEDURE LocateStr(     KeyStr  : ARRAY OF CHAR ;
                         Str     : ARRAY OF CHAR ;
                         StrLen  : CARDINAL ;
                         StrHeader : VirtualAddrType ;
                     VAR VStrPtr : VirtualAddrType ) ;
  VAR
     p, s, t : VirtualAddrType ;
     StrPtr  : StringRecPtr ;
     SortStr : StrAny ;
  BEGIN
     FullToSortWord( KeyStr, SortStr ) ;
     IF NOT FindBTItem(StrHeader, SortStr, VStrPtr, p, s, t) THEN
        AllocateSpace( VStrPtr, StrPtr, VStrUnusedSpace, StrLen+StrRecBaseSize ) ;
        Copy( StrPtr^.IntStr, Str ) ;
        StrPtr^.TotWords  := 0 ;
        StrPtr^.CurWordNo := 0 ;
        AddBTItem( StrHeader, SortStr, VStrPtr, VStrUnusedSpace, p, s, t ) ;
(* m.s.        ReleasePage( VStrPtr, StrPtr ) *)
     END ;
  END LocateStr ;


PROCEDURE DoStrToDB( Key  : ARRAY OF CHAR ;
                     VStr : VirtualAddrType ) ;
   VAR
      StrPtr : StringRecPtr ;
      KeyLen  : CARDINAL ;
      StrLen  : CARDINAL ;
      StrData : TDBStringFormat ;
   BEGIN
      MakeReal( VStr, StrPtr ) ;
      WITH StrPtr^ DO
	 KeyLen := Length( Key ) ;
	 BitOps.Pack( Key, StrData.TDBStr, SortNoBitsPerChar ) ;
	 IF (KeyLen > 0) AND (KeyLen < CARDINAL(StrData.TDBStr.PackedLen)) THEN
	    (* Assert:  Packed bits will be <= length of key *)
	    ProgramErrorAndHalt( "StringsData: DoStrToDB -- something wrong with bit packing." );	
	 END ;
         KeyLen := CARDINAL(StrData.TDBStr.PackedLen) ;
         StrLen := Length(IntStr) + 1 ;
         Move( ADR(IntStr), ADR(StrData.TDBStr.PackedStr[KeyLen]), StrLen ) ;
         StrData.TotalWords := TotWords ;
         AddPtrDataToDB( StrData, 4+KeyLen+StrLen ) ;

         IF FirstStr THEN	(* do it only once *)
	    FirstStr := FALSE ;
	    StartRecForStr := HRecNo ;
	    StartPosForStr := HRecPos - 1 ;
         END ;

         SRecNo  := CHR( HRecNo - StartRecForStr ) ;
         SRecPos := CHR( HRecPos - 1 ) ;  (* compensate for AddPtrDataToDB INC *)
      END ;
(* m.s.      MarkDirty( VStr ) ;
      ReleasePage( VStr, StrPtr ) ;
*)
   END DoStrToDB ;

PROCEDURE WriteStringsToDB(     StrHeader : VirtualAddrType;
                            VAR RecInfo : ARRAY OF CHAR ) ;
  VAR
     TempStr : ARRAY[0..9] OF CHAR;
  BEGIN
     (* Note - Strings are stored in the following structure:
          +----------+-----+------------------+--------+----+
          | TotWords | Len | BitPackedSortStr | IntStr | 0C |
          +----------+-----+------------------+--------+----+
         where Len is a 1 byte offset to start of IntStr - 1 (ie. # bytes in
         BitPackedSortStr); and is part of BitPackedSortStr; TotWord is LONGCARD.
	 RecInfo - containt the ABSOLUTE offset for the string type; proper
		DB location is calculated by summing the EndRecNo with BeginStr.
     *)
(*
     Fill( ADR(TempStr), 10, 0C ) ;
     (* TempStr[0:3] = TotWords = 0 *)
     TempStr[4] := 1C;
     (* TempStr[5] := 0C; *)
     TempStr[6] := '?';
     TempStr[7] := '?';
     TempStr[8] := '?';
     (* TempStr[9] := 0C; *)
     AddPtrDataToDB(TempStr,10);
*)
     FirstStr := TRUE ;
     ProcessBT( StrHeader, DoStrToDB ) ;

     RecInfo[0] := CHR( 0 ) ;		(* always starts at zero !! *)
     RecInfo[1] := CHR( StartPosForStr ) ;

     Fill( ADR(TempStr), 10, 0C ) ;
     (* TempStr[0:3] = TotWords = 0 *)
     TempStr[4] := 1C;
     TempStr[5] := 377C;
     TempStr[6] := '?';
     TempStr[7] := '?';
     TempStr[8] := '?';
     (* TempStr[9] := 0C; *)
     AddPtrDataToDB(TempStr,10);

     RecInfo[2] := CHR( HRecNo - StartRecForStr ) ;
     RecInfo[3] := CHR( HRecPos - 1 ) ;   (* HRecPos points to next pos. *)
  END WriteStringsToDB ;

BEGIN
  InitSpaceType( VStrUnusedSpace ) ;
END StringsData .
