IMPLEMENTATION MODULE TACTInit;
(* copyright (c) 1996 John Bradley, Geoffrey Rockwell, Lidio Presutti, University of Toronto *)

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


(* This is code to start off WWW -- verifies databases, and reads in *)
(* initial data from them.                                            *)

FROM SYSTEM IMPORT SIZE, ADR;
IMPORT Str, ASCII, FIO ;
FROM Storage IMPORT
  (* Vars  *) MainHeap,
  (* Procs *) HeapTotalAvail ;
FROM MemoryManagement IMPORT NoEMSPagesAvailable ;
FROM FIO IMPORT (* Type *) FileAttr, directory ;
FROM VirtMem IMPORT PDBFile, VirtMemFile, CloseVirtFile;
FROM HyperBase IMPORT HyperFile;
FROM GetParams IMPORT
  (* types *) GetParametersStatus, ParameterResult, ParameterData,
  (* procs *) LegalParameter, GetParameters, InitialParams;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteChar;
FROM GlobalDefs IMPORT StrAny, PDBExtension, TDBExtension,
     SystemVersion, SystemVersionDate;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage;
FROM DBData IMPORT
    (* vars  *) TDBFileName, TDBTitle, NoTypes, NoTokensInDB,
                PDBFileName, PDBOpen;
FROM TDBInit IMPORT
    (* procs *) VerifyTDBFile, InitializeFromTDB;
FROM PDBInit IMPORT OpenExistingPDB;
FROM Utils IMPORT BeepMode,
  (* proc *) UpcaseStr,ParseFilename, MakeFilename, AllowWildCards,
     StandardizeFileName,Exist, TrimBlanks, DEALLOCATE, GetEnv;
FROM HyperDataModel IMPORT
    IDType, TDBIDModel, PDBIDModel;
FROM TACTListModule IMPORT TACTListType, TACTList, DiscardList;
FROM WWWUtils IMPORT InitialParseData, RequestMethodType, CheckRequestMethod,
                     pd, FindItem, ParseData, ParseDataDefined,
                     File2ParseData;

TYPE
    DataBaseInfoRecord = RECORD
       FileName:    ARRAY[0..50] OF CHAR;
       Create:      BOOLEAN;
    END;

TYPE
   FileType = (NonExistant, NotTACT, TDBType, PDBType);

PROCEDURE GetFileType(FileName: ARRAY OF CHAR): FileType;
VAR  F:   FIO.File;
     R:   FileType;
     Str: IDType;
     s:   CARDINAL;
BEGIN
   IF NOT Exist(FileName) THEN RETURN NonExistant END;
   F := FIO.OpenRead(FileName);
   s := FIO.RdBin(F,Str,SIZE(IDType));
   IF Str = TDBIDModel THEN
      R := TDBType
   ELSE
      FIO.Seek(F,2); (* PDB ID starts in file position 2 *)
      s := FIO.RdBin(F,Str,SIZE(IDType));
      IF Str = PDBIDModel THEN R := PDBType
      ELSE R := NotTACT END;
   END;
   FIO.Close(F);
   RETURN R;
END GetFileType;

PROCEDURE OpenExistingFile(tFileName: ARRAY OF CHAR): BOOLEAN;
   (*RES OLD MSG 215
   "%0" is not a TACT Database File.
   *)
CONST
   NotTACTDBRes = (*RES REM INS*) 215 ;
VAR
    ft:         FileType;
    tFile:      HyperFile;
    Yr, Mn, Dy: CARDINAL;
    tFileName2: StrAny;
BEGIN
    ft := GetFileType(tFileName);
    CASE ft OF
      NonExistant, NotTACT:
         Str.Copy(tFileName2,tFileName);
         IF ( NOT StandardizeFileName(tFileName2, TDBExtension)) THEN
             ProgramErrorAndHalt('Standardization should work here!')
         END;
         CASE GetFileType(tFileName2) OF
           NonExistant:
              IF ft = NonExistant THEN
                 (*RES OLD MSG 293
                 File "%0" does not exist.
                 *)
                 MsgString(tFileName,0);
                 PutResError( (*RES REM INS*) 293 );
              ELSE
                 MsgString(tFileName,0);
                 PutResError( NotTACTDBRes );
              END;
              RETURN FALSE;
         | NotTACT:
             MsgString(tFileName,0);
             PutResError( NotTACTDBRes );
             RETURN FALSE;
         | TDBType:
             IF NOT VerifyTDBFile(tFileName2,TDBExtension,tFile,Yr,Mn,Dy) THEN
                 RETURN FALSE
             END;
             Str.Copy(TDBFileName,tFileName2);
             InitializeFromTDB(tFile);
         | PDBType:
             Str.Copy(PDBFileName,tFileName2);
             IF NOT OpenExistingPDB(PDBFileName) THEN RETURN FALSE END;
         END;
    | TDBType:
        IF NOT VerifyTDBFile(tFileName,TDBExtension,tFile,Yr,Mn,Dy) THEN
            RETURN FALSE
        END;
        Str.Copy(TDBFileName,tFileName);
        InitializeFromTDB(tFile);
    | PDBType:
        Str.Copy(PDBFileName,tFileName);
        IF NOT OpenExistingPDB(PDBFileName) THEN RETURN FALSE END
    END;
    RETURN TRUE;
END OpenExistingFile;

PROCEDURE GetParamData(VAR DataBaseName: ARRAY OF CHAR;
                       VAR TemplateFileName: ARRAY OF CHAR);
CONST
(*RES OLD MSG 606
TACTweb does not take parameter "%0".
*)

   NotAcceptableRes = (*RES REM INS*) 606 ;
VAR tStr:           StrAny;
    plst,temp:      ParameterResult;
    i:              CARDINAL;
    fiof:           FIO.File;
    TDBdir:         StrAny;
    InFileName:     StrAny;
    UseContLength:  BOOLEAN;

PROCEDURE IsTWCFile(VAR gfn: ARRAY OF CHAR): BOOLEAN;
VAR
   drive:   ARRAY[0..3] OF CHAR;
   path:    ARRAY[0..50] OF CHAR;
   name:    ARRAY[0..9] OF CHAR;
   ext:     ARRAY[0..4] OF CHAR;
   i:       CARDINAL;
BEGIN
   i := 0;
   WHILE(gfn[i] <> 0C) DO
      IF gfn[i] = '/' THEN gfn[i] := '\'; END;
      INC(i);
   END;
   IF NOT ParseFilename(gfn,drive,path,name,ext) THEN RETURN FALSE END;
   UpcaseStr(ext,ext);
   RETURN 0 = Str.Compare(ext,'TWC');
END IsTWCFile;

PROCEDURE CreateFileName(dir:           ARRAY OF CHAR;
                     VAR DataBaseName:  ARRAY OF CHAR);
VAR
   drive:   ARRAY[0..3] OF CHAR;
   path:    ARRAY[0..50] OF CHAR;
   name:    ARRAY[0..9] OF CHAR;
   ext:     ARRAY[0..4] OF CHAR;
   npd:     ParseData;
   gfn:     StrAny;
BEGIN
   gfn[0] := 0C;
   IF ParseDataDefined(pd) THEN
      IF (NOT FindItem(pd, npd, 'tdb_file', gfn)) OR (gfn[0] = 0C) THEN
         ProgramErrorAndHalt('No "tdb_file" value given');
      END;
   ELSE
      GetEnv('PATH_INFO',gfn);
      IF(gfn[0] = 0C) THEN
         ProgramErrorAndHalt('No "tdb_file" value given');
      END;
      IF gfn[0] = '/' THEN gfn[0] := '\' END;
   END;
   IF (NOT ParseFilename(gfn,drive,path,name,ext)) THEN
      ProgramErrorAndHalt('Bad value for "tdb_file" was given')
   END;
   MakeFilename(0C,dir,name,ext,DataBaseName);
   MakeFilename(0C, 0C,name,ext,PathTDBName);
END CreateFileName;

PROCEDURE ProcessTWCFile(fname: ARRAY OF CHAR);

VAR
   twcfile: FIO.File;
   type, value: ARRAY[0..255] OF CHAR;

PROCEDURE GetTWCLine(VAR type: ARRAY OF CHAR; VAR value: ARRAY OF CHAR): BOOLEAN;
VAR
   tmp:   ARRAY [0..255] OF CHAR;
   i:     CARDINAL;
BEGIN
   LOOP
      FIO.RdStr(twcfile, tmp);
      IF FIO.EOF THEN RETURN FALSE END;
      i := Str.Pos(tmp,'#');
      IF (i < 255) THEN tmp[i] := 0C END;
      Str.Item(type, tmp, Str.CHARSET{ASCII.ht, ' '}, 0);
      UpcaseStr(type,type);
      Str.Item(value, tmp, Str.CHARSET{ASCII.ht, ' '}, 1);
      IF (type[0] <> 0C) THEN RETURN TRUE END;
   END;
END GetTWCLine;

BEGIN
   twcfile := FIO.Open(fname);
   IF (FIO.IOresult() <> 0) THEN
      ProgramErrorAndHalt('TWC File would not open.');
   END;
   WHILE GetTWCLine(type, value) DO
      IF Str.Compare(type,'DB') = 0 THEN
         Str.Copy(DataBaseName, value);
      ELSIF Str.Compare(type,'DIR') = 0 THEN
         Str.Copy(TDBdir, value);
      ELSIF Str.Compare(type,'WRAP') = 0 THEN
         Str.Copy(TemplateFileName, value);
      ELSIF Str.Compare(type,'INPUT') = 0 THEN
         Str.Copy(InFileName, value);
      ELSIF Str.Compare(type,'USELEN') = 0 THEN
         UseContLength := 'Y' = CAP(value[0]);
      ELSIF Str.Compare(type,'GIFDIR') = 0 THEN
         Str.Copy(GifDir, value);
      ELSIF Str.Compare(type,'DISPLAY') = 0 THEN
         Str.Copy(DefDisplay, value);
      ELSIF Str.Compare(type,'PAGE') = 0 THEN
         Str.Copy(TactPage, value);
      ELSE
         ProgramErrorAndHalt('Format Error in TWC File');
      END;
   END;
   FIO.Close(twcfile);
END ProcessTWCFile;

BEGIN
    TemplateFileName[0] := 0C;
    GetEnv('GIF_DIR', GifDir);
    GetEnv('DISPLAY_TYPE', DefDisplay);
    GetEnv( 'TACTPAGE', TactPage);
    InitialParams;
    LegalParameter('d',TRUE);  (* directory which contains TDBs *)
    LegalParameter('w',TRUE);  (* name of HTML wrapper file *)
    LegalParameter('i',TRUE);  (* name of input file "-" is legal *)
    LegalParameter('f',FALSE); (* ignore (read "full") CONTENT_LENGTH *)

    IF GetParameters(plst,tStr) <> GPSOk THEN
        MsgString(tStr,0);
        PutResError( NotAcceptableRes );
        HALT;
    END;
    i := 0;
    DataBaseName[0] := 0C;
    TDBdir[0] := 0C;
    UseContLength := TRUE;
    InFileName[0] := 0C;
    WHILE plst <> NIL DO
       WITH plst^ DO
          CASE Code OF
            ' ':
               CASE i OF
                 0: IF IsTWCFile(Strg) THEN ProcessTWCFile(Strg);
                    ELSE Str.Copy(DataBaseName, Strg); END;
               ELSE
                   ProgramErrorAndHalt('Too many file parameters');
               END;
               INC(i);
          | 'D':
               i := 1;
               Str.Copy(TDBdir, Strg);
          | 'W': (* "W" for "Wrapper file" j.b. *)
               Str.Copy(TemplateFileName, Strg);
          | 'I': (* "I" for parse data "input" *)
               Str.Copy(InFileName, Strg);
          | 'F': UseContLength := FALSE;
          ELSE
             ProgramErrorAndHalt('Unexpected ParameterData Code found');
          END;
       END;
       temp := plst^.Next;
       DEALLOCATE(plst,plst^.Size);
       plst := temp;
    END;
    IF (i <> 1) THEN
       ProgramErrorAndHalt('No File Parameters Given');
    END;
    IF (InFileName[0] = '-') AND (InFileName[1] = 0C) THEN
       File2ParseData(pd, FIO.StandardInput, UseContLength);
    ELSIF InFileName[0] <> 0C THEN
       fiof := FIO.OpenRead(InFileName);
       File2ParseData(pd, fiof, UseContLength);
       FIO.Close(fiof);
    ELSIF (CheckRequestMethod() = POSTMethod) THEN InitialParseData(pd) END;

    IF (TDBdir[0] <> 0C) THEN CreateFileName(TDBdir, DataBaseName); END;
END GetParamData;

PROCEDURE InitializeDBs(DataBaseName: ARRAY OF CHAR);
BEGIN
    IF (DataBaseName[0] = 0C) THEN
       ProgramErrorAndHalt('Missing TDB File Name');
    ELSIF NOT OpenExistingFile(DataBaseName) THEN
       ProgramErrorAndHalt('DoDBOpen Failed');
    END;
END InitializeDBs;

BEGIN
   BeepMode :=FALSE ; (* m.s. - default in now quiet mode *)
   PathTDBName[0] := 0C;
   GifDir[0] := 0C;
   DefDisplay[0] := 0C;
   TactPage[0] := 0C;
   DoBackingLink := TRUE;
   GetUnitName := 'lines';
   GetUnitID := 1;
   GetBefore := 40;
   GetAfter := 40;
END TACTInit.
