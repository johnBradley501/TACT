(*$N,A-,V-*)

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
IMPLEMENTATION MODULE Overlay;
(* Copyright (C) 1987 Jensen & Partners International *)


IMPORT Str,FIO,Storage,SYSTEM,Lib;

PROCEDURE (*$S+ stack check for safety*) Load( n:CARDINAL );

TYPE bp=POINTER TO SHORTCARD;
     LONG = ARRAY [0.. MAX(CARDINAL)-1] OF BYTE;

VAR
  f:CARDINAL;        (* file handle *)
  s:CARDINAL;        (* segment for overlay *)
  segsize:CARDINAL;  (* in paras *)

  header:RECORD
    Alloc: LONGCARD; (* total size *)
    Init:  LONGCARD; (* size of initialised part *)
    nifix: CARDINAL; (* number of patchs in loaded overlay *)
    nefix: CARDINAL; (* number of patchs in other overlays *)
    resvd: ARRAY[0..3] OF CHAR; (* Can be used for validity check *)
  END;

  Locseg:CARDINAL;
  Target:CARDINAL;

  tmp:CARDINAL;
  atmp:ADDRESS;
  count:LONGCARD;
  base:CARDINAL;
  chunk:CARDINAL;
  dummy:CARDINAL;

  fixbufseg:CARDINAL;
  fixbufoff:CARDINAL;
  fixbufcount:CARDINAL;
  fixbuf:ARRAY [1..5*200H] OF SHORTCARD;

  Filename:ARRAY[1..50] OF CHAR;
  Ext:ARRAY[0..3] OF CHAR;

  PROCEDURE chkread( buf:ADDRESS; count:CARDINAL );
  VAR tmp:POINTER TO LONG;
  BEGIN
    tmp := buf;
    IF FIO.RdBin(f, tmp^, count ) <> count THEN HALT END;
  END chkread;

BEGIN
  IF (Size[n]<>0)OR(n=0) THEN RETURN END ; (* Already loaded *)
  Ext := '.ov ';
  Ext[3] := CHAR( ORD('0') + n );
  Str.Concat( Filename, Path, Ext );
  f := FIO.Open(Filename);
  chkread(ADR(header),SIZE(header));

  segsize := CARDINAL( ( header.Alloc + 15 ) DIV 16 );

  Storage.HeapAllocate( Storage.MainHeap, atmp, segsize );
  s := SYSTEM.Seg(atmp^);

  Seg[n] := s;
  Size[n] := segsize;

  tmp := s;
  count := header.Init;

  IF count > 0FFF0H THEN
    chkread( [tmp:0], 0FFF0H );
    DEC(count,0FFF0H);
    INC(tmp, 0FFFH );
  END;

  WHILE count > 0F000H DO
    chkread( [tmp:0], 0F000H );
    DEC(count,0F000H);
    INC(tmp, 0F00H );
  END;

  chkread( [tmp:0], CARDINAL(count) );

  WHILE ( header.nifix <> 0 ) OR ( header.nefix <> 0 ) DO
    fixbufcount := FIO.RdBin( f, fixbuf, SIZE(fixbuf) );
    fixbufseg := SYSTEM.Seg(fixbuf);
    fixbufoff := SYSTEM.Ofs(fixbuf);
    REPEAT
      tmp := VAL(CARDINAL,[fixbufseg:fixbufoff bp]^);
      INC(fixbufoff);
      Locseg := [fixbufseg:fixbufoff]^;
      INC(fixbufoff,2);
      Target := [fixbufseg:fixbufoff]^;
      INC(fixbufoff,2);

      base := Seg[ tmp DIV 16 ];
      tmp := tmp MOD 16;
      IF header.nefix <> 0 THEN
        DEC(header.nefix);
        IF base <> CARDINAL(-1) THEN
          [ Locseg+base : tmp ]^ := Target + s;
        END;
      ELSE
        DEC(header.nifix);
        IF base <> CARDINAL(-1) THEN
          [ Locseg + s : tmp ]^ := Target + base;
        END;
      END;
      DEC(fixbufcount,5);
    UNTIL fixbufcount = 0;
  END;

  FIO.Close(f);

END Load;

PROCEDURE UnLoad( n:CARDINAL );
VAR a:ADDRESS;
BEGIN
  IF Size[n]<>0 THEN
    a := [Seg[n]:0];
    Storage.HeapDeallocate( Storage.MainHeap, a, Size[n] );
    Size[n] := 0;
  END ;
END UnLoad;

PROCEDURE (*$S-*) Init;
VAR i:CARDINAL;
BEGIN
  FOR i := 0 TO 9 DO
    Size[i] := 0;
  END;
  Seg[0] := Lib.PSP+10H;
  Size[0] := 0;
END Init;

BEGIN
  Path := 'OVLNAME' ; (* Base mame of overlay files *)
  Init;
END Overlay.
