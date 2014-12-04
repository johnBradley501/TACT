MODULE ResComp;

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

IMPORT DebugPMD;
FROM SYSTEM IMPORT BYTE,ADDRESS,SIZE,ADR, DOSCALL;
FROM Storage IMPORT ALLOCATE;
FROM FileIO IMPORT
    File, FileName, FilePos, IOModeType, Delete, Rename,
    Open, Create, Close, SetPos, ReadNBytes, WriteNBytes;
IMPORT FileIO;

FROM ResManUtils IMPORT
  (* proc *) IOErrorMessage;

FROM ResBase IMPORT
   (*var*)  ResourceOpen, ResourceFile, NullPos,
   (*proc*) OpenResourceFile, CloseResourceFile,
            ReadResourceBase, ReadResRecord, ReadResString;

FROM ResArray IMPORT
   (*type*) ResDataType,ResourceArray,ResourceArrayPntr,
            ResArrayError,ScanActionProcedure,
   (*var*)  ResourcePntrs,ResourceName,
   (*proc*) FindResource,ScanResources;

(*
FROM WResArray IMPORT
   InitialResArrayData,FindFreeResource,UseCurrentFree,UpdateResource,
   DeleteResource,WindUpResources,GetResType;
*)

FROM InOut IMPORT WriteString, WriteCard, WriteLn, ReadString;

FROM Utils IMPORT
 (* type *) BResultType, RWType,
 (* proc *) Exist,StandardizeFileName,RemoveExtension;

CONST
   MaxArrayTableSize = 300;
TYPE
   NewResourceArray = RECORD
      NextArray:       FilePos;
      ArraySize:       CARDINAL;
      Locations:       ARRAY[0..MaxArrayTableSize-1] OF FilePos
   END;
VAR
    OutputResourceFile:  File;
    Result:              BResultType;
    Message:             ARRAY[0..255] OF CHAR;
    OutputResourcePntrs: ARRAY [MessageResource..NumberArrayResource]
                         OF FilePos;
    InResFileName:       ARRAY[0..80] OF CHAR;
    TmpResFileName:      ARRAY[0..80] OF CHAR;

   nr:       CARDINAL;
   walow:    CARDINAL;
   wahi:     CARDINAL;
   wa:       NewResourceArray;
   pos:      CARDINAL;
   last:     FilePos;
   er:       ResArrayError;
   AnyDone:  BOOLEAN;

(*
PROCEDURE DisposeOfFiles;
VAR
    FRs:              FileIO.IOResultType;
BEGIN
    CloseResourceFile;
    Delete(TmpResFileName,FRs);
END DisposeOfFiles;
*)

PROCEDURE UpdateFiles;
VAR  BAKName:    ARRAY[0..80] OF CHAR;
    FRs:              FileIO.IOResultType;
BEGIN
    RemoveExtension(InResFileName,BAKName);
    IF NOT StandardizeFileName(BAKName,'.RBK') THEN
        WriteString('Bad File Name: ');
        WriteString(BAKName);
        WriteLn
    END;
    IF Exist(BAKName) THEN Delete(BAKName,FRs) END;

    CloseResourceFile;
    Rename(InResFileName,BAKName,FRs);
    Close(OutputResourceFile,FRs);
    Rename(TmpResFileName,InResFileName,FRs);
END UpdateFiles;

PROCEDURE OpenNewResourceFile(FName:    ARRAY OF CHAR): BOOLEAN;
VAR
   Result:         FileIO.IOResultType;
   i:              CARDINAL;
   t:              ResDataType;
   sz:             CARDINAL;
BEGIN
   Create(OutputResourceFile,FName,TRUE,Result);
   IF Result <> FileIO.OK THEN RETURN FALSE END;
   FOR t := MIN(ResDataType) TO MAX(ResDataType) DO
       OutputResourcePntrs[t] := NullPos
   END;
   sz := SIZE(OutputResourcePntrs);
   WriteNBytes(OutputResourceFile,ADR(sz),SIZE(sz),Result);
   IF Result <> FileIO.OK THEN RETURN FALSE END;
   WriteNBytes(OutputResourceFile,ADR(OutputResourcePntrs),sz,Result);
   RETURN Result = FileIO.OK
END OpenNewResourceFile;

PROCEDURE GotoEOF(f:   File;
              VAR l:   FilePos;
              VAR er:  FileIO.IOResultType);
    VAR error: CARDINAL;

(* This code really belongs in Module FileIO!  -- J.Bradley *)

  BEGIN
    DOSCALL(42H, f, 2,0,0, l.high, l.low, error);
    er := VAL(FileIO.IOResultType,error);
  END GotoEOF;

PROCEDURE AppendResourceBase(NumberToWrite:    CARDINAL;
                         VAR Location:         FilePos;
                             Data:             ADDRESS): BOOLEAN;
VAR
   Result:         FileIO.IOResultType;
   size,ngot:      CARDINAL;
   i:              CARDINAL;
BEGIN
   GotoEOF(OutputResourceFile,Location,Result);
   IF Result <> FileIO.OK THEN RETURN FALSE END;
   WriteNBytes(OutputResourceFile,ADR(NumberToWrite),SIZE(NumberToWrite),Result);
   IF Result <> FileIO.OK THEN RETURN FALSE END;
   WriteNBytes(OutputResourceFile,Data,NumberToWrite,Result);
   RETURN Result = FileIO.OK
END AppendResourceBase;

PROCEDURE ReadFromNewResource(NumberExpected:   CARDINAL;
                           Location:         FilePos;
                       VAR Data:             ADDRESS;
                       VAR NumberGot:        CARDINAL): BOOLEAN;
VAR
   Result:         FileIO.IOResultType;
   size:           CARDINAL;
   ngot:           CARDINAL;
BEGIN
   SetPos(OutputResourceFile,Location,Result);
   IF Result <> FileIO.OK THEN RETURN FALSE END;
   ReadNBytes(OutputResourceFile,ADR(size),SIZE(size),ngot,Result);
   IF Result <> FileIO.OK THEN RETURN FALSE END;
   IF NumberExpected <> 0 THEN
      IF size <> NumberExpected THEN RETURN FALSE END;
   END;
   IF Data = NIL THEN ALLOCATE(Data,size) END;
   ReadNBytes(OutputResourceFile,Data,size,NumberGot,Result);
   RETURN Result = FileIO.OK
END ReadFromNewResource;

PROCEDURE UpdateNewResourceBase(NumberToWrite:   CARDINAL;
                             Location:         FilePos;
                             Data:             ADDRESS): BOOLEAN;
VAR
   Result:         FileIO.IOResultType;
   size,ngot:      CARDINAL;
   i:              CARDINAL;
BEGIN
   SetPos(OutputResourceFile,Location,Result);
   IF Result <> FileIO.OK THEN RETURN FALSE END;
   ReadNBytes(OutputResourceFile,ADR(size),SIZE(size),ngot,Result);
   IF size <> NumberToWrite THEN RETURN FALSE END;
   WriteNBytes(OutputResourceFile,Data,size,Result);
   RETURN Result = FileIO.OK
END UpdateNewResourceBase;

PROCEDURE Initwa;
VAR i:  CARDINAL;
BEGIN
   wa.NextArray := NullPos;
   wa.ArraySize := 0;
   FOR i := 0 TO MaxArrayTableSize-1 DO wa.Locations[i] := NullPos END;
END Initwa;

PROCEDURE SetupArrayReference(ResType: ResDataType; Loc:   FilePos);
VAR   pntr:   ADDRESS;
      dummy:  CARDINAL;
BEGIN
   IF (last.high = NullPos.high) AND (last.low = NullPos.low) THEN
      OutputResourcePntrs[ResType] := Loc
   ELSE
      pntr := ADR(wa);
      IF NOT ReadFromNewResource(SIZE(wa),last,pntr,dummy) THEN
         WriteString('Error (1) in SetupArrayReference');
         HALT;
      END;
      wa.NextArray := Loc;
      IF NOT UpdateNewResourceBase(SIZE(wa),last,ADR(wa)) THEN
         WriteString('Error (2) in SetupArrayReference');
         HALT;
      END;
   END;
   last := Loc;
END SetupArrayReference;

PROCEDURE HandleResource(ResType: ResDataType;
                         ItemNo:  CARDINAL;
                         Loc:     FilePos;
                     VAR er:      ResArrayError);
VAR
    size:        CARDINAL;
    ResData:     ADDRESS;
    NewLoc:      FilePos;
    NewArrayLoc: FilePos;
    pos:         CARDINAL;
BEGIN
    nr := ItemNo;
    AnyDone := TRUE;
    ResData := NIL;
    IF NOT ReadResourceBase(0,Loc,ResData,size) THEN
         WriteString('Error In In HandleResource');
         HALT;
    END;
    IF NOT AppendResourceBase(size,NewLoc,ResData) THEN
         WriteString('Error Appending New Resource');
         HALT;
    END;
    IF ItemNo < walow THEN
        WriteString('Programming error 1 in HandleResource');
        HALT
    END;
    WHILE ItemNo > wahi DO
        wa.ArraySize := MaxArrayTableSize - 1;
        IF NOT AppendResourceBase(SIZE(wa),NewArrayLoc,ADR(wa)) THEN
           WriteString('Error Appending New Resource Array Table');
           HALT;
        END;
        SetupArrayReference(ResType,NewArrayLoc);
        walow := walow + MaxArrayTableSize;
        wahi := wahi + MaxArrayTableSize;
        Initwa;
    END;
    pos := ItemNo - walow;
    IF pos < wa.ArraySize THEN
        WriteString('Programming error 2 in HandleResource');
        HALT
    END;
    wa.Locations[pos] := NewLoc;
    wa.ArraySize := pos;
END HandleResource;

PROCEDURE CompressType(type:  ResDataType);
VAR
   NewArrayLoc: FilePos;

BEGIN
   nr := 0;
   AnyDone := FALSE;
   last := NullPos;
   walow := 0;
   wahi := MaxArrayTableSize - 1;
   Initwa;
   IF NOT ScanResources(type,0,63000,HandleResource,er) THEN
       IF er <> RATooHigh THEN
          CASE er OF
            RANotOpen:     WriteString(': Resource File Not Open') |
            RANotUsed:     WriteString(': Not Used Error Occurred') |
            RAActionError: WriteString(': Action Error Occurred')
          ELSE
              WriteString(': Unknown Error type returned')
          END;
          HALT;
       END;
   END;
   IF AnyDone THEN
      IF NOT AppendResourceBase(6 + 4*(wa.ArraySize+1),NewArrayLoc,ADR(wa)) THEN
         WriteString('Error (2) Appending New Resource Array Table');
         HALT;
      END;
      SetupArrayReference(type,NewArrayLoc)
   END;

   WriteString(' (');
   WriteCard(nr,0);
   WriteString(')');
END CompressType;

PROCEDURE DoTheCompress;
VAR
    i:                ResDataType;
BEGIN
   FOR i := MIN(ResDataType) TO MAX(ResDataType) DO
      WriteString('Doing Resource Type: ');
      WriteString(ResourceName[i]);
      OutputResourcePntrs[i] := NullPos;
      CompressType(i);
      WriteLn;
   END;
   
   IF NOT UpdateNewResourceBase(SIZE(OutputResourcePntrs),NullPos,
   ADR(OutputResourcePntrs)) THEN
      WriteString('Error writing final Resource Pntr table');
      HALT
   END;
END DoTheCompress;

BEGIN

    WriteString('Resource File To Compress: ');
    ReadString(InResFileName);
    WriteLn;
    IF NOT StandardizeFileName(InResFileName,'.RES') THEN
        WriteString('Non-Standard File Name: ');
        WriteString(InResFileName);
        WriteLn
    END;
    IF NOT OpenResourceFile(InResFileName,Result) THEN
        WriteString('Input Resource File ');
        WriteString(InResFileName);
        WriteString(' would not open: ');
        IOErrorMessage(Result,Message);
        WriteString(Message);
        WriteLn;
        HALT;
    END;

    RemoveExtension(InResFileName,TmpResFileName);
    IF NOT StandardizeFileName(TmpResFileName,'.$RE') THEN
       WriteString('Bad FileName: ');
       WriteString(TmpResFileName);
       WriteLn;
       HALT
    END;

    IF NOT OpenNewResourceFile(TmpResFileName) THEN
        WriteString(' Error Opening New Resfile as ');
        WriteString(TmpResFileName);
        HALT;
    END;

    DoTheCompress;

    UpdateFiles;
    WriteString('ResCompress completed normally');
END ResComp.
