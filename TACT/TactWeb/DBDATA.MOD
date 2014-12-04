IMPLEMENTATION MODULE DBData;
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


IMPORT Lib;
FROM Utils IMPORT InstallTermProc ;
FROM VirtMem IMPORT CloseVirtFile, VirtAddr, GetSpace, VMModify, VMRelease,
                  PDBFile;
FROM ErrorBase IMPORT ProgramErrorAndHalt;

CONST
   NumbOfPools = 2048;
   NumbOfPoolWords = NumbOfPools DIV 16;
   MaxReservedPool = 0;

TYPE
    PoolDataType = RECORD
      CASE : BOOLEAN OF
         TRUE:
             Bits:   ARRAY[0..NumbOfPoolWords - 1] OF BITSET;
       | FALSE:
             Words:  ARRAY[0..NumbOfPoolWords - 1] OF WORD;
      END;
    END;
    PoolPntr = POINTER TO PoolDataType;

VAR
   PoolInfoVA:                VirtAddr;

PROCEDURE SavePoolInfo(ValToSet: VirtAddr);
BEGIN
    PoolInfoVA := ValToSet;
END SavePoolInfo;

PROCEDURE InitPool(VAR PoolInfoAdr: VirtAddr);
VAR
   PP:    PoolPntr;
   i,j,k: CARDINAL;
BEGIN
   PP := GetSpace(SIZE(PoolDataType), 0, PoolInfoAdr);
   Lib.WordFill(PP, NumbOfPoolWords, 0);
   FOR i := 0 TO MaxReservedPool DO
      j := i DIV 16;
      k := i MOD 16;
      INCL(PP^.Bits[j],k);
   END;
   VMRelease(PoolInfoAdr);
END InitPool;

PROCEDURE GetNewPoolNumber(): CARDINAL;
VAR
  PP:   PoolPntr;
  i,j,k:CARDINAL;
BEGIN
  PP := VMModify(PoolInfoVA);
  i := Lib.ScanNeR(PP,NumbOfPoolWords * 2, 0377C) DIV 2;
  IF i >= NumbOfPoolWords THEN
     ProgramErrorAndHalt('GetNewPoolNumber fails');
  END;
  FOR j := 0 TO 15 DO
     IF NOT (j IN PP^.Bits[i]) THEN
        INCL(PP^.Bits[i],j);
        VMRelease(PoolInfoVA);
        RETURN i * 16 + j;
     END;
  END;
  ProgramErrorAndHalt('GetNewPoolNumber fails 2');
END GetNewPoolNumber;

PROCEDURE ReleasePoolNo(No: CARDINAL);
VAR
  PP:   PoolPntr;
  i,j:  CARDINAL;
BEGIN
  PP := VMModify(PoolInfoVA);
  i := No DIV 16;
  j := No MOD 16;
  EXCL(PP^.Bits[i],j);
  VMRelease(PoolInfoVA);
END ReleasePoolNo;

(* =================================================== *)

PROCEDURE ClosePDBOnHalt ;
   BEGIN
	IF PDBOpen THEN
	   PDBOpen := FALSE ;	(* ensure that its called only once! *)
	   CloseVirtFile( PDBFile ) ;
	END ;
   END ClosePDBOnHalt ;

BEGIN
   PDBOpen := FALSE;
   PDBFileName := '-----';
   InstallTermProc( ClosePDBOnHalt ) ;
   TDBDataInitialized := FALSE;
END DBData.