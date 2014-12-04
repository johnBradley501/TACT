IMPLEMENTATION MODULE ProcTrace;

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
IMPORT SYSTEM, Lib, FIO, Str;

VAR
  Int60[0:180H], Old60,
  Int61[0:184H], Old61	: ADDRESS;
  Base, cs, ip	: CARDINAL;
  Term		: PROC;
  ProfFile	: FIO.File ;

PROCEDURE GetTime() : LONGCARD ;
  (* GetTime in milliseconds *)
  VAR
    r : SYSTEM.Registers ;
  BEGIN
    r.AH := 2CH ;
    Lib.Dos( r ) ;
    (* get time -> CX:DX     *)
    (* CH = hour 0..23       *)
    (* CL = min  0..59       *)
    (* DH = sec  0..59       *)
    (* DL = sec/100  0..99   *)
    RETURN LONGCARD(r.CH) * 360000 + LONGCARD(r.CL) * 6000 +
	   LONGCARD(r.DH) * 100 + LONGCARD(r.DL)
  END GetTime ;

PROCEDURE GetBase( l : CARDINAL );
BEGIN
  Base := [SYSTEM.Seg( l ):SYSTEM.Ofs( l )+4]^;
END GetBase;

PROCEDURE GetCsIp(): ADDRESS;
BEGIN
  RETURN [cs:ip];
END GetCsIp;

(*$J+,C FF*)
PROCEDURE EntryTrap( dummy : CARDINAL );
VAR a,t : CARDINAL;
    Adr: LONGCARD;
BEGIN
  SYSTEM.EI;
  a := SYSTEM.Ofs( dummy )-4;
  t := [SYSTEM.Seg( dummy ) : a+2]^;
  cs := t-Base;
  ip := [SYSTEM.Seg( dummy ) : a]^;
  Adr := LONGCARD(cs) << 4 + LONGCARD(ip);
  FIO.WrLngCard( ProfFile, Adr, 8 ) ;
  FIO.WrStr( ProfFile, " E " ) ;
  FIO.WrLngCard( ProfFile, GetTime(), 8 ) ;
  FIO.WrLn( ProfFile ) ;
END EntryTrap;

PROCEDURE ExitTrap( dummy : CARDINAL );
VAR a,t : CARDINAL;
    Adr: LONGCARD;
BEGIN
  SYSTEM.EI;
  a := SYSTEM.Ofs( dummy )-4;
  t := [SYSTEM.Seg( dummy ) : a+2]^;
  cs :=t-Base;
  ip :=[SYSTEM.Seg( dummy ) : a]^;
  Adr := LONGCARD(cs) << 4 + LONGCARD(ip);
  FIO.WrLngCard( ProfFile, Adr, 8 ) ;
  FIO.WrStr( ProfFile, " X " ) ;
  FIO.WrLngCard( ProfFile, GetTime(), 8 ) ;
  FIO.WrLn( ProfFile ) ;
END ExitTrap;
(*$J-,C F0*)


PROCEDURE Finish;
BEGIN
  Int60 := Old60;
  Int61 := Old61;
  FIO.Close( ProfFile ) ;
  Term;
END Finish;

PROCEDURE Install;
BEGIN
  Old60 := Int60;
  Int60 := ADR( EntryTrap );
  Old61 := Int61;
  Int61 := ADR( ExitTrap );
  ProfFile := FIO.Create( "D:PROFILE.DAT" ) ;
  Lib.Terminate( Finish, Term);
END Install;

BEGIN
  GetBase(0);
END ProcTrace.
