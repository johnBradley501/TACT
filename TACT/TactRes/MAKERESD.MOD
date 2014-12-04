MODULE MakeResDat;

(* copyright (c) 1987-96 John Bradley, University of Toronto *)

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

FROM FileIO IMPORT FilePos;
FROM Utils IMPORT
  (* Types *) BResultType,
  (* Vars  *) StandardSearchList,
  (* Procs *) GetEnv, FindFileInList;
FROM ResArray IMPORT
   (*type*) ResDataType,ResourceArray,ResourceArrayPntr,
            ResArrayError,ScanActionProcedure,
   (*proc*) FindResource;
FROM ResBase IMPORT OpenResourceFile, ReadResourceBase;
IMPORT FIO, Str;

VAR
   rc             : CARDINAL ;
   DirName        : ARRAY [0..50] OF CHAR;
   FullResName    : ARRAY [0..50] OF CHAR ;
   OpenResult     : BResultType ;
   FID            : FIO.File;

PROCEDURE DoResource(No:  CARDINAL);
TYPE
   DataPtr = POINTER TO ARRAY[0..64000] OF BYTE;
VAR
   ColPos         : FilePos;
   Error          : ResArrayError;
   Data           : DataPtr;
   Size           : CARDINAL;
BEGIN
   IF NOT FindResource(DataArrayResource,No,ColPos,Error) THEN
       FIO.WrStr(FIO.ErrorOutput,'Fatal Resource Error (1)')
   END;

   Data := NIL;
   Size := 0;
   IF NOT ReadResourceBase(0,ColPos,Data,Size) THEN
      FIO.WrStr(FIO.ErrorOutput,'Fatal Resource Error (2)')
   END;
   FIO.WrBin(FID,Size,SIZE(Size));
   FIO.WrBin(FID,Data^,Size);
END DoResource;

BEGIN
   GetEnv( 'TACTPATH', StandardSearchList );
   IF StandardSearchList[0] = 0C THEN GetEnv( 'PATH', StandardSearchList ) END;

   IF NOT FindFileInList( StandardSearchList, 'TACT.RES', DirName ) THEN
      FIO.WrStr(FIO.ErrorOutput, 'File "TACT.RES" could not be found.' ) ;
      HALT;
   END ;
   Str.Concat( FullResName, DirName, 'TACT.RES' ) ;
   IF NOT OpenResourceFile( FullResName, OpenResult ) THEN
      FIO.WrStr(FIO.ErrorOutput, 'Unable to open file "TACT.RES".' ) ;
      HALT;
   END ;

   FID := FIO.Create('RES.DAT');

   DoResource(4);
   DoResource(5);

   FIO.Close(FID);
END MakeResDat.
