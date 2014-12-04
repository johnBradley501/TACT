IMPLEMENTATION MODULE Char512;

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
(* IMPORT IO; *)
IMPORT FIO;
FROM SYSTEM IMPORT Registers,ADDRESS;
FROM Lib IMPORT Intr; (* m.s. - used to import UserBreak too, can't be used w/ extender *)
FROM Utils IMPORT ALLOCATE,DEALLOCATE;

TYPE
   VMode = (Colour,Monochrome);
   EGASize = (KB64,KB128,KB192,KB256);
   AddressParts = RECORD
      Offset:    CARDINAL;
      Segment:   CARDINAL;
   END;

PROCEDURE FindEGA(VAR VideoMode:  VMode;
                  VAR EGARAM:     EGASize): BOOLEAN;
VAR r: Registers;
BEGIN
   r.BL := 10H;
   r.AH := 12H;
   Intr(r,10H);
   IF r.BL = 10H THEN RETURN FALSE END;

   VideoMode := VMode(r.BH);
   EGARAM := EGASize(r.BL);
   RETURN TRUE;
END FindEGA;

PROCEDURE FindPS2(VAR Active,Inactive: PSType):BOOLEAN;
VAR r: Registers;
BEGIN
   r.AX := 1A00H;
   Intr(r,10H);
   IF r.AL <> 1AH THEN RETURN FALSE END;

   IF r.BL > 0CH THEN Active := Unknown
   ELSE Active := PSType(r.BL) END;
   IF r.BH > 0CH THEN Inactive := Unknown
   ELSE Inactive := PSType(r.BH) END;
   RETURN TRUE;
END FindPS2;

PROCEDURE LoadROMFont(RAMTableNo: SHORTCARD);
VAR r: Registers;
BEGIN
   r.AH := 11H;
   r.AL := 11H;
   r.BL := RAMTableNo;
   Intr(r,10H);
END LoadROMFont;

PROCEDURE Load8x14CharDef(RAMTableNo: SHORTCARD;
                          NoChars:    CARDINAL;
                          FirstChar:  CHAR;
                          TableAddress:ADDRESS);
VAR r: Registers;
    t: AddressParts;
BEGIN
   r.AH := 11H;
   r.AL := 10H;
   r.BH := 14;
   r.BL := RAMTableNo;
   r.CX := NoChars;
   r.DX := ORD(FirstChar);
   t := AddressParts(TableAddress);
   r.ES := t.Segment;
   r.BP := t.Offset;
   Intr(r,10H);
END Load8x14CharDef;

PROCEDURE ReadIn8x14CharDef(RAMTableNo: SHORTCARD;
                            NoChars:    CARDINAL;
                            FirstChar:  CHAR;
                            FIN:        FIO.File);
VAR
   FileText:  POINTER TO ARRAY[0..65000] OF CHAR;
   ReadSize:  CARDINAL;
   dummy:     CARDINAL;
BEGIN
   IF NoChars = 0 THEN
      ReadSize := CARDINAL(FIO.Size(FIN));
      NoChars := ReadSize DIV 14;
   ELSE
      ReadSize := NoChars * 14;
   END;
   ALLOCATE(FileText,ReadSize);
   dummy := FIO.RdBin(FIN,FileText^,ReadSize);
   Load8x14CharDef(RAMTableNo,NoChars,FirstChar,FileText);
   DEALLOCATE(FileText,ReadSize);
END ReadIn8x14CharDef;

PROCEDURE SetBaseCharSet(RAMTable1,RAMTable2: SHORTCARD);
VAR
   r:  Registers;
   t:  SHORTCARD;
   tt: SHORTCARD;
BEGIN
   t:= 0;
   IF RAMTable1 > 3 THEN
      t := 16;
      t := t - 4;
   END;
   IF RAMTable2 > 3 THEN
      t := 32;
      t := t - 4;
   END;
   INC(t,RAMTable1);
   INC(t,RAMTable2*4);

   r.AX := 1103H;
   r.BL := t;
   Intr(r,10H);
END SetBaseCharSet;

PROCEDURE Set512CharSet(RAMTable1,RAMTable2: SHORTCARD);
VAR
   r:  Registers;
BEGIN
   SetBaseCharSet(RAMTable1,RAMTable2);
(* also, set Colour Plane Enable register to mask out bit 3 as colour choice *)

   r.AX := 1000H;
   r.BX := 0712H;
   Intr(r,10H);
END Set512CharSet;

PROCEDURE Set256CharSet(RAMTable: SHORTCARD);
VAR
   r:  Registers;
BEGIN
   SetBaseCharSet(RAMTable,RAMTable);

(* also, ensure setting of Colour Plane Enable register to
   use bit 3 as colour choice *)

   r.AX := 1000H;
   r.BX := 0F12H;
   Intr(r,10H);
END Set256CharSet;

PROCEDURE ExtendedAvailable(VAR ScreenType: PSType;
                            VAR NoFonts: CARDINAL): BOOLEAN;
VAR
   Active,Inactive: PSType;
   VideoMode:       VMode;
   EGARAM:          EGASize;

PROCEDURE HandleEGA(): BOOLEAN;
BEGIN
   IF FindEGA(VideoMode,EGARAM) THEN
      CASE VideoMode OF
        Colour:     ScreenType := EGAColour;
      | Monochrome: ScreenType := EGAMonochrome;
      ELSE (* m.s. - cant be used w/ extender UserBreak *) HALT
      END;
      CASE EGARAM OF
        KB64:  NoFonts := 1;
      | KB128: NoFonts := 2;
      | KB192: NoFonts := 3;
      | KB256: NoFonts := 4;
      ELSE (* m.s. cant be used w/ extender UserBreak *) HALT ;
      END;
      RETURN TRUE;
   ELSE RETURN FALSE END;
END HandleEGA;

BEGIN
   IF FindPS2(Active,Inactive) THEN
      ScreenType := Active;
      CASE Active OF
        None:          RETURN FALSE;
      | MDA:           RETURN FALSE;
      | CGAColour:     RETURN FALSE;
      | Reserved:      RETURN FALSE;
      | EGAColour, EGAMonochrome:
         IF NOT HandleEGA() THEN (* m.s. cant be used w/ extender UserBreak *) HALT END;
      | PGC:           RETURN FALSE;
      | VGAAMono:      NoFonts := 8;
      | VGAAColour:    NoFonts := 8;
      | Reserved2:     RETURN FALSE;
      | MCGAColour:    NoFonts := 8;
      | MCGAAMono:     NoFonts := 8;
      | MCGAAColour:   NoFonts := 8;
      | Unknown:       RETURN FALSE;
      ELSE             (* m.s. - cant be used w/ extender UserBreak *) HALT ;
      END;
      RETURN TRUE;
   END;
   RETURN HandleEGA();
END ExtendedAvailable;

END Char512.
