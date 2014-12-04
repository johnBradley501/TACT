IMPLEMENTATION MODULE Utils ;
(* copyright (c) 1989-96 John Bradley, Geoffrey Rockwell, Lidio Presutti, University of Toronto *)

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

(*V1=Dbg Debugging code *)

(*--------------------------------------------------------------------------*)
(* Purpose:                                                                 *)
(*                                                                          *)
(* History:                                                                 *)
(*  26 Apr 88, Lidio Presutti                                               *)
(*     - fixed PrintCode routine.                                           *)
(*  28 Jun 88, John Bradley                                                 *)
(*     - prepared version for JPI's Modula 2                                *)
(*  19 Sep 91, Lidio Presutti                                               *)
(*     - fixed ConstStr routine						    *)
(*                                                                          *)
(*--------------------------------------------------------------------------*)

IMPORT Str, Lib, FIO, ASCII, Storage, UtilsTwo;
FROM GlobalDefs IMPORT StrAny;
FROM StringIO IMPORT SWriteString, SWriteCard, SWriteChar;

FROM SYSTEM IMPORT ADDRESS,SIZE,WORD, ADR, Registers, Seg, Ofs;

(*<Dbg
FROM Trace
IMPORT TWriteLn, TWriteString, TWriteCard;
Dbg>*)

  CONST
    ArraySize   = 2000;

  TYPE
    CardPTR = POINTER TO CARDINAL;
    StringPTR = POINTER TO ARRAY[0..ArraySize] OF CHAR;

  VAR
    HexChars: ARRAY[0..15] OF CHAR;
    LegalNameChars: ARRAY[0..20] OF CHAR;


(* >> From RTSMain, merged in. << *)
CONST
   NoTermProcs = 10;
VAR
   TermProcList:  ARRAY[0..NoTermProcs-1] OF PROC;
   TermProcPos:   CARDINAL;
   FinalCall:     PROC;

PROCEDURE Terminate(st:  Status);
BEGIN
   HALT;
END Terminate;

PROCEDURE InstallTermProc(p: PROC);
BEGIN
   IF TermProcPos >=NoTermProcs THEN Terminate(TermListFull) END;
   TermProcList[TermProcPos] := p;
   INC(TermProcPos);
END InstallTermProc;

PROCEDURE CallTermProc;
VAR i:   CARDINAL;
BEGIN
   IF TermProcPos > 0 THEN
      FOR i := 0 TO TermProcPos-1 DO TermProcList[i] END;
   END;
END CallTermProc;

PROCEDURE DoTermProcs;
BEGIN
   CallTermProc;
   FinalCall;
END DoTermProcs;
(* >> End RTSMain, merged in. << *)


PROCEDURE MsDosDate(VAR month, day, year: INTEGER);
    VAR
      r:       Registers;
      temp:    CARDINAL;

  BEGIN
    r.AH := 2AH;
    Lib.Dos(r);
    year := r.CX;
    month := r.DX DIV 256;
    day := r.DX MOD 256;
(*
          MOV AX,2A00H
          INT 21H
          MOV @CX,CX
          MOV @DX,DX
*)
  END MsDosDate;


PROCEDURE StandardizeCharName(InputName: ARRAY OF CHAR;
                          VAR OutputName:ARRAY OF CHAR);

  VAR
      NP:           CARDINAL;

  BEGIN
    NP := 0;
    IF InputName[0] <> 0C THEN
       NP := 1; (* This is, intentially, *NOT* zero *)
       OutputName[0] := InputName[0];
       WHILE (InputName[NP] <> 0C) AND
       (NP <= HIGH(OutputName)) AND
       (NP <= HIGH(InputName)) DO
         OutputName[NP] := CAP(InputName[NP]);
         INC(NP)
       END
    END;
    IF NP <= HIGH(OutputName) THEN OutputName[NP] := 0C END;
  END StandardizeCharName; 


PROCEDURE UpcaseStr(InputName: ARRAY OF CHAR;
                VAR OutputName: ARRAY OF CHAR);
  VAR 
      NP:           CARDINAL;

  BEGIN
    NP := 0;
    WHILE (NP <= HIGH(InputName)) AND
    (InputName[NP] <> 0C) AND
    (NP <= HIGH(OutputName)) DO
      OutputName[NP] := CAP(InputName[NP]);
      INC(NP)
    END;
    IF NP <= HIGH(OutputName) THEN OutputName[NP] := 0C END;
  END UpcaseStr;

PROCEDURE LowcaseStr(InputName: ARRAY OF CHAR;
                 VAR OutputName: ARRAY OF CHAR);
  VAR 
      NP:           CARDINAL;

  BEGIN
    NP := 0;
    WHILE (NP <= HIGH(InputName)) AND
    (InputName[NP] <> 0C) AND
    (NP <= HIGH(OutputName)) DO
      IF (InputName[NP] >= 'A') AND
         (InputName[NP] <= 'Z') THEN
           OutputName[NP] := CHR(ORD(InputName[NP])+32)
      ELSE
           OutputName[NP] := InputName[NP]
      END;
      INC(NP)
    END;
    IF NP <= HIGH(OutputName) THEN OutputName[NP] := 0C END;
  END LowcaseStr; 


PROCEDURE PrintCode(SeqIn: ARRAY OF CHAR;
                VAR SeqOut: ARRAY OF CHAR);
  VAR
      NP:           CARDINAL;

  BEGIN
    NP := 0;
    WHILE (NP <= HIGH(SeqIn)) AND (SeqIn[NP] <> 0C) AND (NP <= HIGH(SeqOut)) DO
      IF (SeqIn[NP] < ' ') OR (SeqIn[NP] > '~') THEN  (* *LP* was: SeqOut *)
           SeqOut[NP] := ':'
      ELSE
           SeqOut[NP] := SeqIn[NP]
      END;
      INC(NP)
    END;
    IF NP <= HIGH(SeqOut) THEN SeqOut[NP] := 0C END;
  END PrintCode; 


PROCEDURE PrintHex1(SeqIn: ARRAY OF CHAR;
                VAR SeqOut: ARRAY OF CHAR);
  VAR 
      NP:           CARDINAL;

  BEGIN
    NP := 0;
    WHILE (NP <= HIGH(SeqIn)) AND
    (SeqIn[NP] <> 0C) AND
    (NP <= HIGH(SeqOut)) DO
      SeqOut[NP] := HexChars[ORD(SeqIn[NP]) DIV 16];
      INC(NP)
    END;
    IF NP <= HIGH(SeqOut) THEN SeqOut[NP] := 0C END;
  END PrintHex1; 

PROCEDURE PrintHex2(SeqIn: ARRAY OF CHAR;
                VAR SeqOut: ARRAY OF CHAR);
  VAR
      NP:           CARDINAL;

  BEGIN
    NP := 0;
    WHILE (NP <= HIGH(SeqIn)) AND
    (SeqIn[NP] <> 0C) AND
    (NP <= HIGH(SeqOut)) DO
      SeqOut[NP] := HexChars[INTEGER(ORD(SeqIn[NP])) MOD 16];
      INC(NP)
    END;
    IF NP <= HIGH(SeqOut) THEN SeqOut[NP] := 0C END;
  END PrintHex2;

PROCEDURE MakeHex(in:     BYTE;
                  pos:    CARDINAL;
              VAR SeqOut: ARRAY OF CHAR);
BEGIN
   SeqOut[pos] := HexChars[ORD(in) DIV 16];
   SeqOut[pos + 1] := HexChars[ORD(in) MOD 16];
END MakeHex;

PROCEDURE PrintHex(SeqIn: ARRAY OF CHAR;
               VAR SeqOut: ARRAY OF CHAR);
  VAR 
      NP:           CARDINAL;
      NP2:          CARDINAL;

  BEGIN
    NP := 0;
    NP2 := 0;
    WHILE (NP <= HIGH(SeqIn)) AND
    (SeqIn[NP] <> 0C) AND
    (NP2 <= HIGH(SeqOut)-1) DO
      MakeHex(SeqIn[NP], NP2, SeqOut);
      INC(NP);
      INC(NP2,2)
    END;
    IF NP2 <= HIGH(SeqOut) THEN SeqOut[NP2] := 0C END;
  END PrintHex;

PROCEDURE PrintHexByte(SeqIn: ARRAY OF BYTE;
                   VAR SeqOut: ARRAY OF CHAR);
  VAR 
      NP:           CARDINAL;
      NP2:          CARDINAL;
  BEGIN
    NP := 0;
    NP2 := 0;
    WHILE (NP <= HIGH(SeqIn)) AND
    (NP2 <= HIGH(SeqOut)-1) DO
      MakeHex(SeqIn[NP], NP2, SeqOut);
      INC(NP);
      INC(NP2,2)
    END;
    IF NP2 <= HIGH(SeqOut) THEN SeqOut[NP2] := 0C END;
END PrintHexByte;

PROCEDURE ConstStr(c: CHAR;
                   N: CARDINAL;
               VAR SeqOut: ARRAY OF CHAR);
VAR
    i:      CARDINAL;
  BEGIN
 (*<Dbg
    WriteString('ConstStr: c:');
    WriteString(c);
    WriteString(',N:');
    WriteCard(N,0);
    WriteString(',HIGH(SeqOut):');
    WriteCard(HIGH(SeqOut),0);
    WriteLn;
 Dbg>*)
    IF N <= HIGH(SeqOut) THEN
       SeqOut[N] := 0C ;
    ELSE
       N := HIGH(SeqOut) + 1 ;	(* fix by *LP* *)
    END;
    Lib.Fill( ADR(SeqOut), N, c ) ;

(* --- was:			*LP*
    IF N > 0 THEN
       FOR i := 0 TO N-1 DO
           SeqOut[i] := c
       END
    END
*)
  END ConstStr;


PROCEDURE Beep;
   BEGIN
     IF BeepMode THEN
	Lib.Sound(440);
	Lib.Delay(250);
	Lib.NoSound;
     (* ELSE be quiet !! *)
     END ;
   END Beep;


PROCEDURE Exist(FileName: ARRAY OF CHAR): BOOLEAN;
     VAR
         result     : BOOLEAN ;
         OldIOcheck : BOOLEAN ;
  BEGIN
    OldIOcheck := FIO.IOcheck ;
    FIO.IOcheck := FALSE ;   (* disable JPI error "fatal" handler *)
    result := FIO.Exists(FileName);
    FIO.IOcheck := OldIOcheck ; (* re-enable JPI error "fatal" handler *)
    RETURN result
  END Exist;

(* the following two procedures where directly stolen from JPI (but
   used with permission, since source was licensed, and code borrowing
   is permitted by the license j.b. *)

PROCEDURE ParseFilename(f:ARRAY OF CHAR;
                        VAR drive,path,name,ext:ARRAY OF CHAR):BOOLEAN;

VAR Lnth,pos,NameLnth:CARDINAL;

BEGIN
     drive[0]:=0C; path[0]:=0C; name[0]:=0C; ext[0]:=0C;
     Lnth := Str.Length(f);
     IF Lnth=0 THEN RETURN(FALSE) END;
     pos := Lnth-Lib.ScanL(ADR(f[Lnth-1]),Lnth,':');
     IF pos>0 THEN
         IF pos<>2 THEN RETURN(FALSE) END;
         drive[0] := CAP(f[0]);
         drive[1] := 0C;
         DEC(Lnth,2);
         Lib.Move(ADR(f[2]),ADR(f),Lnth+1)
       ELSE
         drive[0] := 0C;
     END;
     IF Lnth=0 THEN RETURN(FALSE) END;
     pos := Lnth-Lib.ScanL(ADR(f[Lnth-1]),Lnth,'\');
     IF pos>0 THEN
         Lib.Move(ADR(f),ADR(path),pos);
         DEC(Lnth,pos);
         Lib.Move(ADR(f[pos]),ADR(f),Lnth+1);
     END;
     path[pos] := 0C;
     IF Lnth=0 THEN RETURN(FALSE) END;
     pos := Lnth-Lib.ScanL(ADR(f[Lnth-1]),Lnth,'.');
     IF pos>0 THEN
         IF pos=1 THEN RETURN(FALSE) END;
         IF pos-1>8 THEN NameLnth:=8 ELSE NameLnth:=pos-1 END;
         Lib.Move(ADR(f),ADR(name),NameLnth);
         name[NameLnth]:=0C;
         DEC(Lnth,pos);
         Lib.Move(ADR(f[pos]),ADR(f),Lnth+1);
         Lib.Move(ADR(f),ADR(ext),Lnth+1)
       ELSE
         IF Lnth+1>8 THEN NameLnth:=8 ELSE NameLnth:=Lnth+1 END;
         Lib.Move(ADR(f),ADR(name),NameLnth); name[Lnth]:=0C;
         ext[0] := 0C;
     END;
     RETURN(TRUE);
END ParseFilename;

(*.................................................*)

PROCEDURE MakeFilename(drive,path,name,ext:ARRAY OF CHAR;
                       VAR f:ARRAY OF CHAR);

VAR Lnth,LnthDest:CARDINAL;

BEGIN
     f[0] := 0C;
     IF drive[0]<>0C THEN
         f[0]:=drive[0]; f[1]:=':'; f[2]:=0C;
     END;
     Str.Concat(f,f,path);
     IF path[0]<>0C THEN
         Lnth := Str.Length(f);
         IF f[Lnth-1]<>'\' THEN f[Lnth]:='\'; f[Lnth+1]:=0C END;
     END;
     Lnth := Str.Length(name);
     IF Lnth>8 THEN name[8]:=0C END;
     Str.Concat(f,f,name);
     IF ext[0]<>0C THEN
         Lnth := Str.Length(f);
         IF ext[0]<>'.' THEN f[Lnth]:='.'; f[Lnth+1]:=0C END;
         Str.Concat(f,f,ext);
     END;
END MakeFilename;

(*.................................................*)


PROCEDURE StandardizeFileName(VAR FileName: ARRAY OF CHAR;
                                Extension: ARRAY OF CHAR): BOOLEAN;

(* old version / pre Parse.. and MakeFilename  j.b.
    VAR 
      OK: BOOLEAN;
      P, Q: CARDINAL; 

  PROCEDURE GoodFileChar(Ch: CHAR): BOOLEAN;
  BEGIN
     IF (Ch >= 'A') AND (Ch <= 'Z') THEN RETURN TRUE END;
     IF (Ch >= '0') AND (Ch <= '9') THEN RETURN TRUE END;
     IF (Str.Pos(LegalNameChars,Ch) < MAX(CARDINAL)) THEN RETURN TRUE END;
     RETURN FALSE;
  END GoodFileChar;

  BEGIN
    UpcaseStr(FileName,FileName); 
    IF Extension[0] = 0C THEN
      OK := (Str.Pos(FileName,'.') > HIGH(FileName));
    ELSE 
      OK := TRUE; 
      IF Str.Pos(FileName,'.') > HIGH(FileName) THEN 
        Str.Append(FileName,Extension);
      END;
    END; 
    IF NOT OK THEN
       RETURN OK;
    END;
    P := 0; 
    REPEAT
        OK := GoodFileChar(FileName[P]);
        INC(P); 
    UNTIL ( NOT OK) OR (FileName[P] = 0C) OR (FileName[P] = '.'); 
    IF OK AND (FileName[P] <> 0C) THEN 
        INC(P);
        Q := 0;
        WHILE OK AND (FileName[P] <> 0C) DO
          OK := GoodFileChar(FileName[P]); 
          INC(P);
          INC(Q);
        END;
        OK := OK AND (Q <= 3); 
    END; 
    RETURN OK;
end old version / pre Parse.. and MakeFilename  j.b. *)

  VAR
     Drv:    ARRAY[0..4] OF CHAR;
     Pth:    ARRAY[0..100] OF CHAR;
     Name:   ARRAY[0..8] OF CHAR;
     Ext:    ARRAY[0..3] OF CHAR;
     i:      CARDINAL;

  PROCEDURE CheckChars(VAR Strg:        ARRAY OF CHAR;
                           bg:          CARDINAL;
                           AllowPeriod: BOOLEAN): BOOLEAN;
  VAR i :   CARDINAL;
      OK:   BOOLEAN;

  PROCEDURE GoodFileChar(Ch: CHAR): BOOLEAN;
  BEGIN
     IF (AllowPeriod) AND (Ch = '.') THEN
        AllowPeriod := FALSE;
        RETURN TRUE;
     END;
     IF (Ch >= 'A') AND (Ch <= 'Z') THEN RETURN TRUE END;
     IF (Ch >= '0') AND (Ch <= '9') THEN RETURN TRUE END;
     IF (Str.Pos(LegalNameChars,Ch) < MAX(CARDINAL)) THEN RETURN TRUE END;
     RETURN FALSE;
  END GoodFileChar;

  BEGIN
     FOR i := bg TO HIGH(Strg) DO
        IF Strg[i] = 0C THEN RETURN TRUE END;
        IF (NOT GoodFileChar(Strg[i])) THEN RETURN FALSE END;
     END;
  RETURN TRUE;
  END CheckChars;

  BEGIN
    IF AllowWildCards THEN
       LegalNameChars[0] := '*';
       LegalNameChars[1] := '?';
    ELSE
       LegalNameChars[0] := '0';
       LegalNameChars[1] := '1';
    END;

    UpcaseStr(FileName,FileName); 
    IF NOT ParseFilename(FileName,Drv,Pth,Name,Ext) THEN RETURN FALSE END;

    IF NOT CheckChars(Drv,0, (* AllowPeriod = *) FALSE) THEN RETURN FALSE END;
    IF Pth[0] <> 0C THEN
       i := 0;
       IF Pth[i] = '.' THEN INC(i) END;
       IF Pth[i] = '.' THEN INC(i) END;
       IF (i <> 0) AND (Pth[i] <> '\') AND (Pth[i] <> 0C) THEN RETURN FALSE END;
       IF NOT CheckChars(Pth,i, (* AllowPeriod = *) TRUE) THEN RETURN FALSE END;
    END;
    IF NOT CheckChars(Name,0, (* AllowPeriod = *) FALSE) THEN RETURN FALSE END;
    IF NOT CheckChars(Ext,0, (* AllowPeriod = *) FALSE) THEN RETURN FALSE END;
    IF Ext[0] = 0C THEN
       IF Extension[0] = '.' THEN Str.Slice(Ext,Extension,1,3)
       ELSE Str.Copy(Ext, Extension) END;
    END;
    MakeFilename(Drv,Pth,Name,Ext,FileName);
    RETURN TRUE;
  END StandardizeFileName; 


PROCEDURE RemoveExtension(     FileName: ARRAY OF CHAR;
                           VAR Result:   ARRAY OF CHAR ) ;
   VAR
     dummy:    BOOLEAN;
     Drv:    ARRAY[0..4] OF CHAR;
     Pth:    ARRAY[0..100] OF CHAR;
     Name:   ARRAY[0..8] OF CHAR;
     XName:  ARRAY[0..8] OF CHAR;
     Ext:    ARRAY[0..3] OF CHAR;
  BEGIN
    GetXlationType(FileName,XName);
    dummy := ParseFilename(FileName,Drv,Pth,Name,Ext);
    Ext[0] := 0C;
    MakeFilename(Drv,Pth,Name,Ext,Result);
    IF XName[0] <> 0C THEN
       Str.Append(Result,'@');
       Str.Append(Result,XName);
    END;
(* old pre Make... ParseFilename version j.b.
    P := Str.Length(FileName);
    WHILE (P > 0) AND (FileName[P] <> '.') DO
      P := P-1
    END;
    IF P = 0 THEN  (* no extension in file name *)
      Str.Copy(Result,FileName);
    ELSE
      FOR i := 0 TO P-1 DO
           Result[i] := FileName[i]
      END;
      IF P <= HIGH(Result) THEN Result[P] := 0C END;
    END;
old pre Make... ParseFilename version j.b. *)
  END RemoveExtension; 

PROCEDURE GetXlationType(VAR FileName: ARRAY OF CHAR;
                         VAR XlName:   ARRAY OF CHAR);
VAR
    i,j:        CARDINAL;
    lin:        CARDINAL;
    lout:       CARDINAL;
BEGIN
   lin := HIGH(FileName);
   lout := HIGH(XlName);
   i := 0; j := 0;
   XlName[0] := 0C;
   WHILE (i <=lin) AND (FileName[i] <> '@') AND (FileName[i] <> 0C) DO
      INC(i)
   END;
   IF FileName[i] = '@' THEN
      FileName[i] := 0C;
      INC(i)
   ELSE
      RETURN
   END;
   WHILE (i <=lin) AND (j <= lout) AND (FileName[i] <> 0C) DO
      XlName[j] := FileName[i];
      INC(j);
      INC(i)
   END;
   IF j <=lout THEN
      XlName[j] := 0C
   END;
END GetXlationType;

PROCEDURE BOpen( VAR file:   BFile;
                name:   ARRAY OF CHAR;
                mode:   RWType;
                VAR result: CARDINAL);
BEGIN
   IF (mode = AppendType) AND (NOT Exist(name)) THEN mode := WriteType END;
   WITH file DO
      RW := mode;
      CASE mode OF
        ReadType:   FileID := FIO.OpenRead(name);
      | WriteType:  FileID := FIO.Create(name);
      | AppendType: FileID := FIO.Append(name);
      | BStdOut:    FileID := FIO.StandardOutput;
      END;
      result := FIO.IOresult();
(* m.s.      result := BResultType(trslt); *)
      IF result <> 0 THEN RETURN END;
      IF mode <> BStdOut THEN FIO.AssignBuffer(FileID, Buf) END;
(*    FIO.AssignBuffer(FileID, Buf); *)
   END;
END BOpen;

PROCEDURE BCreate(VAR file:   BFile;
                 name:   ARRAY OF CHAR;
                 erase:  BOOLEAN;
                 VAR result: CARDINAL);
BEGIN
   BOpen(file, name, WriteType, result);
END BCreate;

PROCEDURE BClose(file: BFile; VAR result: CARDINAL);
BEGIN
   WITH file DO
      IF RW = BStdOut THEN (* FIO.Flush(FileID) *)
      ELSE FIO.Close(FileID) END;
      result := FIO.IOresult();
   END;
END BClose;

PROCEDURE BDelete( Name : ARRAY OF CHAR ; VAR result : CARDINAL ) ;
  BEGIN
     FIO.Erase( Name );
     result := FIO.IOresult();
  END BDelete ;

PROCEDURE ReadLine(VAR file:       BFile;
                   VAR data:       ARRAY OF CHAR;
                   VAR enoughdata: BOOLEAN;
                   VAR result:     CARDINAL):BOOLEAN;
VAR  trslt:   CARDINAL;
BEGIN
   enoughdata := TRUE;
   FIO.RdStr(file.FileID, data);
   IF FIO.EOF THEN
      result := UtilsTwo.InsufficientData;
      RETURN FALSE
   END;
   result := FIO.IOresult();
(* m.s.   result := BResultType(trslt); *)
   RETURN result = 0;
END ReadLine;

PROCEDURE WrStr(VAR file:       BFile;
                    data:       ARRAY OF CHAR;
                VAR result:     CARDINAL);
BEGIN
   FIO.WrStr(file.FileID, data);
   result := FIO.IOresult();
(*   result := BResultType(trslt); *)
END WrStr;

PROCEDURE WrBin(VAR file:       BFile;
                    data:       ARRAY OF BYTE;
                    size:       CARDINAL;
                VAR result:     CARDINAL);
BEGIN
   FIO.WrBin(file.FileID, data, size);
   result := FIO.IOresult();
END WrBin;

PROCEDURE WrLn(VAR file:   BFile;
               VAR result: CARDINAL);
BEGIN
   FIO.WrLn(file.FileID);
   result := FIO.IOresult();
(* m.s.   result := BResultType(trslt); *)
END WrLn;

PROCEDURE WriteLine(VAR file:       BFile;
                        data:       ARRAY OF CHAR;
                    VAR result:     CARDINAL);
BEGIN
   WrStr(file,data,result);
   IF result = UtilsTwo.OK THEN WrLn(file, result) END;
END WriteLine;

PROCEDURE GetEnv(EnvVar : ARRAY OF CHAR; VAR Strg : ARRAY OF CHAR);
VAR
        i, j, res:    CARDINAL;
        Str1, Str2:   StrAny;
        Value:        StrAny;
        EnvPTR:       Lib.CommandType;
BEGIN
        UpcaseStr(EnvVar,Str1);
(*<Dbg
        WriteString('Str1: ');
        WriteString(Str1);
        WriteString('---');
        WriteLn();
Dbg>*)
        Strg[0] := 0C;
        i := 0;
        LOOP
           EnvPTR := Lib.Environment(i);
           IF EnvPTR^[0] = 0C THEN RETURN END;
           j := 0;
           WHILE (EnvPTR^[j] # '=') AND (EnvPTR^[j] # ASCII.nul) DO
              Str2[j] := EnvPTR^[j];
              INC(j);
           END;
           Str2[j] := ASCII.nul;
(*<Dbg
           WriteString('Str2:');
           WriteString(Str2);
           WriteLn();
Dbg>*)
           IF Str.Compare(Str1, Str2) = 0 THEN
               Str.Slice(Value, EnvPTR^, j+1,255);
               res := Lib.ScanNeR( ADR( Value ), 255, SHORTCARD( ' ' ) ) ;
               IF res > 0 THEN
                  Str.Delete( Value, 0, res ) ;
               END ;
               TrimBlanks( Value, Strg ) ;
               RETURN
           END;
           INC(i)
        END;
END GetEnv;

PROCEDURE FindFileInList(List:        ARRAY OF CHAR;
                         FileName:    ARRAY OF CHAR;
                     VAR DirName:     ARRAY OF CHAR): BOOLEAN;
    VAR
      i,j,ln:   CARDINAL;
      found:    BOOLEAN;
      TempStr:  StrAny;

  BEGIN
  (*<Dbg
    WriteString('FindFileInList Starts: List:');
    WriteString(List);
    WriteString(',FileName:');
    WriteString(FileName);
    WriteLn;
  Dbg>*)
    DirName[0] := 0C;
    IF FIO.Exists(FileName) THEN RETURN TRUE END;

    i := 0;
    ln := HIGH(List);
    REPEAT
       j := 0;
       REPEAT
          DirName[j] := List[i];
          INC(i); INC(j);
       UNTIL (i > ln) OR (List[i] = 0C) OR (List[i] = ';');
       IF (List[i] = ';') THEN INC(i) END;
       IF (DirName[j-1] <> '\') AND (DirName[j-1] <> ':') THEN
          DirName[j] := '\';
          INC(j);
       END;
       DirName[j] := 0C;
       Str.Concat(TempStr, DirName,FileName);
 (*<Dbg
       WriteString('FindFileInList:');
       WriteString(List);
       WriteString(',');
       WriteCard(i,0);
       WriteString(',');
       WriteString(DirName);
       WriteLn;
 Dbg>*)
       found := Exist(TempStr);
    UNTIL found OR (List[i] = 0C);
    RETURN found;
  END FindFileInList;

PROCEDURE TrimBlanks(     InStr  : ARRAY OF CHAR;
                      VAR OutStr : ARRAY OF CHAR);
   VAR  I : CARDINAL;
   BEGIN
      Str.Copy( OutStr, InStr ) ;
      I := Str.Length( OutStr ) ;
      WHILE (I > 0) AND (OutStr[I-1] = ' ') DO
         DEC( I )
      END ;
      IF I <= HIGH(OutStr) THEN OutStr[I] := 0C END ;
   END TrimBlanks ;

PROCEDURE TimeDelay(Time:  CARDINAL);
  BEGIN
     Lib.Delay(Time);
  END TimeDelay;


PROCEDURE GetTempFile(VAR file: FIO.File;
                      VAR name: ARRAY OF CHAR): BOOLEAN;
VAR
   r:   Registers;
   i,j: CARDINAL;
BEGIN
   file := FIO.File(0);
   r.AH := 05AH; (*90; 5Ah *)
   r.CX := 0; (* file attribute (see #0731 at AX=4301h) *)
   r.Flags := BITSET{};
   IF(name[0] = 0C)THEN Str.Copy(name,".\"); END;
   i := Str.Length(name);
   j := 1;
   WHILE (j <= 13) DO name[i] := 0C; INC(i); INC(j); END;
   r.DS := Seg(name); r.DX := Ofs(name);
     (* DS:DX -> ASCIZ path ending with a '\' + 13 zero bytes to receive the
		generated filename *)
   Lib.Dos(r);
(* IF (r.Flags <> BITSET{}) THEN RETURN FALSE END; *)
   file := FIO.File(r.AX);
   RETURN TRUE;
END GetTempFile;

BEGIN
   TermProcPos := 0;
   BeepMode := FALSE ;  (* m.s. - default to quiet May, 1993 *)
   Lib.Terminate(DoTermProcs,FinalCall);

   CrLf[0] := ASCII.cr; CrLf[1] := ASCII.lf; CrLf[2] := 0C;
   HexChars := '0123456789ABCDEF';
   LegalNameChars := "01\$#&@!%()-_{}'`~^:"; (* "01" are placeholders *)
       (* if wildcards are allows, "01" are replaced with "*" and "?" j.b. *)
   AllowWildCards := FALSE;

   MsDosDate( month, day, year ) ;
   GetEnv( 'PATH', StandardSearchList ) ;

   ALLOCATE := Storage.ALLOCATE;
   DEALLOCATE := Storage.DEALLOCATE;
END Utils .

