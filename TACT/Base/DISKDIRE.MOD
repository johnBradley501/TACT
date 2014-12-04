IMPLEMENTATION MODULE DiskDirectory;

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

IMPORT SYSTEM;
IMPORT FIO;
IMPORT Lib;
IMPORT TSXLIB ; (* m.s. - to allow change extender swap drive *)

PROCEDURE CurrentDrive( VAR drive: CHAR);
VAR
   r:   SYSTEM.Registers;
BEGIN
   r.AH := 19H;
   Lib.Dos(r);
   drive := CHR(ORD('A') + CARDINAL(r.AL));
END CurrentDrive;

PROCEDURE SelectDrive( drive: CHAR );
VAR
   r:   SYSTEM.Registers;
BEGIN
   r.AH := 0EH;
   r.DL := SHORTCARD(ORD(CAP(drive)) - ORD('A'));
   Lib.Dos(r);
(* -- Note: Select Disk interupt does NOT set a return code, see DOS Tech Ref
   done := (BITSET{SYSTEM.CarryFlag} * r.Flags) = BITSET{};
*)
END SelectDrive;

PROCEDURE CurrentDirectory(drive: CHAR; VAR dir: ARRAY OF CHAR);
VAR
   DriveNo:   SHORTCARD;
BEGIN
   DriveNo := SHORTCARD(ORD(CAP(drive)) - ORD('A') + 1);
   FIO.GetDir(DriveNo, dir);
END CurrentDirectory;

PROCEDURE ChangeDirectory(dir: ARRAY OF CHAR; VAR done: BOOLEAN);
VAR OldIOcheck : BOOLEAN ;
BEGIN
  OldIOcheck  := FIO.IOcheck ;
  FIO.IOcheck := FALSE;
  FIO.ChDir(dir);
  done := FIO.IOresult() = 0;
  FIO.IOcheck := OldIOcheck ;
END ChangeDirectory;

PROCEDURE ChangeTDADirectory ; (* m.s. - to allow swap drive to be changed to
                                         current directory *)
(* VAR g : TSXLIB.GlobalRecPtr ;
    r:   SYSTEM.Registers;
BEGIN
    g := TSXLIB.GETGLOBALPTR() ;
    r.AH := 19H;
    Lib.Dos(r);
    g^.virtual_drive := SHORTCARD(r.AL) + 1; (* change virtual drive to current drive *)
*)
END ChangeTDADirectory;

PROCEDURE DiskStatus( VAR DriveNo, Tracks, TotalTracks, Bytes, Sectors : CARDINAL ) ;
   VAR
	r : SYSTEM.Registers;
   BEGIN
	r.AX := 3600H ;
	r.DX := DriveNo ;
	Lib.Dos( r );
	Tracks := r.BX ;	(* number of tracks available	*)
	TotalTracks := r.DX ;	(*   "    "  total tracks	*)
	Bytes := r.CX ;		(*   "    "  bytes per sector	*)
	Sectors := r.AX ;	(*   "    "  sector per cluster *)
   END DiskStatus ;


PROCEDURE DiskFree( Drive : CHAR ) : LONGCARD ;
   VAR
	DriveNo : CARDINAL ;
	Tracks	: CARDINAL ;
	Bytes	: CARDINAL ;
	Sectors	: CARDINAL ;
	TotalTracks : CARDINAL ;
	TotalBytesFree : LONGCARD ;
   BEGIN
	DriveNo := ORD( CAP(Drive) ) - ORD( 'A' ) + 1 ;
	DiskStatus( DriveNo, Tracks, TotalTracks, Bytes, Sectors ) ;
	TotalBytesFree := VAL(LONGCARD, Sectors) * VAL(LONGCARD, Bytes) *
			  VAL(LONGCARD, Tracks ) ;
	RETURN TotalBytesFree
   END DiskFree ;

END DiskDirectory.
