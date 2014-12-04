MODULE ResMan;

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

(* New version created for JPI compiler .... j.b. *)

FROM SYSTEM IMPORT BYTE,ADDRESS,SIZE,ADR;
FROM FileIO IMPORT FilePos;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteChar;
IMPORT Lib;
IMPORT Str;
IMPORT FIO;
FROM Utils IMPORT
  (* Vars  *) StandardSearchList,
  (* Procs *) GetEnv, FindFileInList;

FROM ResManUtils IMPORT
  (* type *) ResOpType,
  (* var *)  InCmdFileName, InResFileName, TmpResFileName,
             TmpCmdFileName, InCmdFile, OutCmdFile,
             ResOptNames, ErrorFound,
  (* proc *) CopyFile, DisposeOfFiles, UpdateFiles,
             ResErrorMessage, ReportError,
             ReadCmdLine, NextResLine,
             FindResType;

FROM ResManWork IMPORT
   (*proc*) HandleNewMessage, HandlePanelDef, HandleNewChoice,
            HandleNewDataArray, HandleNewNumberArray,
            HandleNewHelpItem;

FROM ResBase IMPORT
   (*var*)  ResourceOpen, ResourceFile, NullPos,
   (*proc*) OpenResourceFile, CloseResourceFile,
            ReadResourceBase, ReadResRecord, ReadResString;

FROM ResArray IMPORT
   (*type*) ResDataType,ResourceArray,ResourceArrayPntr,
            ResArrayError,ScanActionProcedure,
   (*var*)  ResourcePntrs,ResourceName,
   (*proc*) FindResource,ScanResources;

FROM WResBase IMPORT
  (* proc *)   UOpenResourceFile;

FROM WResArray IMPORT
   InitialResArrayData,FindFreeResource,UseCurrentFree,UpdateResource,
   DeleteResource,WindUpResources,GetResType;

FROM ResComments IMPORT
   FindOpenComment, FindCloseComment, FindNextThing;

FROM ResTranslations IMPORT SetupTranslations;

IMPORT IO;

FROM Utils IMPORT
 (* proc *) StandardizeFileName,RemoveExtension;

CONST
   IllegalItemNumber = 64000;
   Version = '4.0';

VAR
    InCmdBuf:          ARRAY[0..2047] OF CHAR;
    NewCmdBuf:         ARRAY[0..2047] OF CHAR;
    InCmdFileName2:    ARRAY[0..80] OF CHAR;
    Line:              ARRAY[0..255] OF CHAR;
    CurrentItemNumber: CARDINAL;
    SomethingWasDone:  BOOLEAN;
    CurParm:           CARDINAL;

PROCEDURE ReportDoing(ResOp:    ResOpType;
                      ResType:  ResDataType;
                      ResNumb:  CARDINAL);
BEGIN
    IO.WrStr('Processing ');
    IO.WrStr(ResOptNames[ResOp]);
    IO.WrStr(': ');
    IO.WrStr(ResourceName[ResType]);
    IF ResNumb <> MAX(CARDINAL) THEN
       IO.WrStr(' ');
       IO.WrCard(ResNumb, 0);
    END;
    IO.WrLn;
END ReportDoing;

PROCEDURE HandleResCommand(BeforeFirst:   ARRAY OF CHAR;
                           FirstPart:     ARRAY OF CHAR);
VAR
   WLine:     ARRAY[0..255] OF CHAR;
   Word:      ARRAY[0..255] OF CHAR;
   BfWLine:   ARRAY[0..255] OF CHAR;
   NewWLine:  ARRAY[0..255] OF CHAR;
   OPos:      CARDINAL;
   OLine:     ARRAY[0..255] OF CHAR;
   Dummy:     BOOLEAN;
   ResOp:     ResOpType;

PROCEDURE CopyResCommand;
BEGIN
   SWriteString(OLine,OPos,Word,0);
   SWriteString(OLine,OPos,NewWLine,0);
   FIO.WrStr(OutCmdFile,OLine); FIO.WrLn(OutCmdFile);
   IF FindCloseComment(NewWLine,BfWLine,OLine) THEN RETURN END;
   WHILE NextResLine(OLine) DO END;
END CopyResCommand;

PROCEDURE HandleResType(CType: ARRAY OF CHAR;
                    VAR ResType: ResDataType): BOOLEAN;
VAR   WPos:    CARDINAL;
BEGIN
   IF NOT FindNextThing(WLine,Word,BfWLine,NewWLine) THEN
      WPos := 0;
      SWriteString(WLine,WPos,'Missing RES Type in ',0);
      SWriteString(WLine,WPos,CType,0);
      SWriteString(WLine,WPos,' Command',0);
      ReportError(WLine);
      RETURN FALSE
   END;
   IF NOT GetResType(Word,ResType) THEN
      WPos := 0;
      SWriteString(WLine,WPos,'Unrecognized type "',0);
      SWriteString(WLine,WPos,Word,0);
      SWriteString(WLine,WPos,'" in ',0);
      SWriteString(WLine,WPos,CType,0);
      SWriteString(WLine,WPos,' Command',0);
      ReportError(WLine);
      RETURN FALSE
   END;
   SWriteString(OLine,OPos,BfWLine,0);
   SWriteString(OLine,OPos,Word,0);
   Str.Copy(WLine, NewWLine);
   RETURN TRUE
END HandleResType;

PROCEDURE StoreResName(Name:  ARRAY OF CHAR;  Val:   CARDINAL);
BEGIN
   IO.WrStr('StoreResName: ');
   IO.WrStr(Name);
   IO.WrStr(': ');
   IO.WrCard(Val,0);
   IO.WrLn;
END StoreResName;

PROCEDURE HandleResNewCommand;
VAR
      ResType:    ResDataType;
      FreeID:     CARDINAL;
      DataArea:   FilePos;
BEGIN
(* Change type of RES command to OLD on output *)
   SWriteString(OLine,OPos,'OLD',0);

(* Get RES Type -- next parameter *)
   IF NOT HandleResType('NEW',ResType) THEN RETURN END;

(* Now, get a new ID for the type of resource *)

   IF NOT FindFreeResource(ResType,FreeID) THEN
       ResErrorMessage('Trouble getting freeID');
       RETURN
   END;
   CurrentItemNumber := FreeID;

(* and add it to the OLD Resource message *)

   SWriteChar(OLine,OPos,' ',0);
   SWriteCard(OLine,OPos,FreeID,0);

(* If Resource has a name, get it here *)

   IF FindNextThing(WLine,Word,BfWLine,NewWLine) THEN
      StoreResName(Word,FreeID);
   END;
   SWriteString(OLine,OPos,WLine,0);
(* Write out modified line *)
   FIO.WrStr(OutCmdFile,OLine);
   FIO.WrLn(OutCmdFile);

   ReportDoing(ResNew, ResType, MAX(CARDINAL));
   CASE ResType OF
     MessageResource:     HandleNewMessage(DataArea) |
     MenuResource:        HandlePanelDef(DataArea) |
     HelpResource:        HandleNewHelpItem(DataArea) |
     ChoiceResource:      HandleNewChoice(DataArea) |
     DataArrayResource:   HandleNewDataArray(DataArea) |
     NumberArrayResource: HandleNewNumberArray(DataArea)
   ELSE
     ReportError('This type isnt handled at present')
   END;

   UseCurrentFree(ResType,DataArea);
   SomethingWasDone := TRUE;
END HandleResNewCommand;

PROCEDURE HandleResUpdCommand;
VAR
      ResType:    ResDataType;
      UpdID:      CARDINAL;
      done:       BOOLEAN;
      DataArea:   FilePos;
BEGIN
   SWriteString(OLine,OPos,'OLD',0);

(* Get RES Type -- next parameter *)
   IF NOT HandleResType('UPD',ResType) THEN RETURN END;

   IF NOT FindNextThing(WLine,Word,BfWLine,NewWLine) THEN
      ReportError('Missing RES Number ID in UPD Command');
      RETURN
   END;
   UpdID := CARDINAL(Str.StrToCard(Word,10,done));
   IF NOT done THEN
      ReportError('Bad RES Number ID in UPD Command');
      RETURN
   END;
   CurrentItemNumber := UpdID;
   SWriteString(OLine,OPos,BfWLine,0);
   SWriteString(OLine,OPos,Word,0);
   Str.Copy(WLine, NewWLine);

   IF FindNextThing(WLine,Word,BfWLine,NewWLine) THEN
      StoreResName(Word,UpdID);
   END;
   SWriteString(OLine,OPos,WLine,0);
(* Write out modified line *)
   FIO.WrStr(OutCmdFile,OLine);
   FIO.WrLn(OutCmdFile);

   ReportDoing(ResUpdate, ResType, UpdID);
   CASE ResType OF
     MessageResource:     HandleNewMessage(DataArea) |
     MenuResource:        HandlePanelDef(DataArea) |
     HelpResource:        HandleNewHelpItem(DataArea) |
     ChoiceResource:      HandleNewChoice(DataArea) |
     DataArrayResource:   HandleNewDataArray(DataArea) |
     NumberArrayResource: HandleNewNumberArray(DataArea)
   ELSE
     ReportError('This type isnt handled at present')
   END;

   IF NOT UpdateResource(ResType,UpdID,DataArea) THEN
     ResErrorMessage('Trouble in UpdateResource')
   END;
   SomethingWasDone := TRUE;
END HandleResUpdCommand;

PROCEDURE HandleResDelCommand;
VAR
      ResType:    ResDataType;
      UpdID:      CARDINAL;
      done:       BOOLEAN;
BEGIN
   SWriteString(OLine,OPos,'REM ',0);
   SWriteString(OLine,OPos,Word,0);

(* Get RES Type -- next parameter *)
   IF NOT HandleResType('DEL',ResType) THEN RETURN END;


   IF NOT FindNextThing(WLine,Word,BfWLine,NewWLine) THEN
      ReportError('Missing RES Number ID in DEL Command');
      RETURN
   END;
   UpdID := CARDINAL(Str.StrToCard(Word,10,done));
   IF NOT done THEN
      ReportError('Bad RES Number ID in DEL Command');
      RETURN
   END;
   SWriteString(OLine,OPos,WLine,0);
(* Write out modified line *)
   FIO.WrStr(OutCmdFile,OLine);
   FIO.WrLn(OutCmdFile);

   ReportDoing(ResDelete, ResType, UpdID);
   IF NOT DeleteResource(ResType,UpdID) THEN
      ResErrorMessage('DeleteResource Failed')
   END;

   CurrentItemNumber := IllegalItemNumber;
   SomethingWasDone := TRUE;
END HandleResDelCommand;

PROCEDURE HandleResInsCommand;
BEGIN
   IF CurrentItemNumber = IllegalItemNumber THEN
      ReportError('Item Number is currently not set');
      RETURN
   END;

   SWriteString(OLine,OPos,'REM ',0);
   SWriteString(OLine,OPos,Word,0);

   IF NOT FindCloseComment(WLine,BfWLine,NewWLine) THEN
      ReportError('Missing Closing Comment mark in RES INS Command');
      RETURN
   END;
   IO.WrStr('Processing INS: Number = ');
   IO.WrCard(CurrentItemNumber,0);
   IO.WrLn;

   SWriteString(OLine,OPos,BfWLine,0);
   SWriteString(OLine,OPos,'*) ',0);
   SWriteCard(OLine,OPos,CurrentItemNumber,0);
   SWriteString(OLine,OPos,NewWLine,0);

   FIO.WrStr(OutCmdFile,OLine);
   FIO.WrLn(OutCmdFile);
   SomethingWasDone := TRUE;
END HandleResInsCommand;

BEGIN
   Str.Copy(WLine, FirstPart);
   Str.Copy(OLine, BeforeFirst);

   OPos := Str.Length(BeforeFirst);
   SWriteString(OLine,OPos,'(*',0);
   Dummy := FindNextThing(WLine,Word,BfWLine,NewWLine);
   SWriteString(OLine,OPos,BfWLine,0);
   SWriteString(OLine,OPos,Word,0);
   Str.Copy(WLine, NewWLine);

   IF NOT FindNextThing(WLine,Word,BfWLine,NewWLine) THEN
      ReportError('Missing RES Command Type');
      RETURN
   END;
   SWriteString(OLine,OPos,BfWLine,0);
   Str.Copy(WLine, NewWLine);

   IF NOT FindResType(Word,ResOp) THEN
       ReportError('Unrecognized RES Command Type');
       CopyResCommand
   ELSIF ResOp = ResInsertNumber THEN HandleResInsCommand
   ELSE
      CASE ResOp OF
         ResComment:      CopyResCommand |
         ResOld:          CopyResCommand |
         ResNew:          HandleResNewCommand |
         ResUpdate:       HandleResUpdCommand |
         ResDelete:       HandleResDelCommand
      ELSE
         ReportError('Program error: in HandleResCommand')
      END
   END;
END HandleResCommand;

PROCEDURE HandleLines;
VAR
   LineBefore:   ARRAY[0..255] OF CHAR;
   LineAfter:    ARRAY[0..255] OF CHAR;

BEGIN
    WHILE ReadCmdLine(Line) DO
        IF FindOpenComment(Line,LineBefore,LineAfter) THEN
           IF (LineAfter[0] = 'R') AND (LineAfter[1] = 'E') AND
           (LineAfter[2] = 'S') THEN
                HandleResCommand(LineBefore,LineAfter);
           ELSE
                FIO.WrStr(OutCmdFile,Line);
                FIO.WrLn(OutCmdFile);
           END
        ELSE
           FIO.WrStr(OutCmdFile,Line);
           FIO.WrLn(OutCmdFile);
        END;
    END;
END HandleLines;


PROCEDURE GetParam(VAR Parm: ARRAY OF CHAR);
BEGIN
    INC(CurParm);
    IF CurParm <= Lib.ParamCount() THEN
       Lib.ParamStr(Parm,CurParm);
       IO.WrStr(Parm);
       IO.WrLn;
    ELSE IO.RdStr(Parm) END;
END GetParam;

BEGIN
    CurParm := 0;
    SomethingWasDone := FALSE;
    CurrentItemNumber := IllegalItemNumber;

    IO.WrStr('RESMAN Version ');
    IO.WrStr(Version);
    IO.WrLn;

    GetEnv( 'TACTPATH', StandardSearchList );
    IF StandardSearchList[0] = 0C THEN GetEnv( 'PATH', StandardSearchList ) END;
    SetupTranslations();

    IO.WrStr('Input Command File Name: ');
    GetParam(InCmdFileName);
    Str.Copy(InCmdFileName2, InCmdFileName);

    IF NOT StandardizeFileName(InCmdFileName,'.MOD') THEN
        IO.WrStr('Non-Standard File Name: ');
        IO.WrStr(InCmdFileName);
        IO.WrLn;
        HALT;
    END;
    IF FIO.Exists(InCmdFileName) THEN
        InCmdFile := FIO.Open(InCmdFileName);
    ELSE
       Str.Copy(InCmdFileName, InCmdFileName2);
       IF NOT StandardizeFileName(InCmdFileName,'.RSI') THEN
           IO.WrStr('Non-Standard File Name: ');
           IO.WrStr(InCmdFileName);
           IO.WrLn;
           HALT;
       END;
       IF NOT FIO.Exists(InCmdFileName) THEN
           IO.WrStr('Could not find File: ');
           IO.WrStr(InCmdFileName);
           IO.WrLn;
           HALT;
       END;
       InCmdFile := FIO.Open(InCmdFileName);
    END;
    FIO.AssignBuffer(InCmdFile, InCmdBuf);

    IO.WrStr('Resource File To Change: ');
    GetParam(InResFileName);
    IF NOT StandardizeFileName(InResFileName,'.RES') THEN
        IO.WrStr('Non-Standard File Name: ');
        IO.WrStr(InResFileName);
        IO.WrLn
    END;

    RemoveExtension(InCmdFileName,TmpCmdFileName);
    IF NOT StandardizeFileName(TmpCmdFileName,'.$RI') THEN
        IO.WrStr('Bad FileName: ');
        IO.WrStr(TmpCmdFileName);
        IO.WrLn;
        HALT
    END;
    OutCmdFile := FIO.Create(TmpCmdFileName);
    FIO.AssignBuffer(OutCmdFile, NewCmdBuf);

    RemoveExtension(InResFileName,TmpResFileName);
    IF NOT StandardizeFileName(TmpResFileName,'.$RE') THEN
       IO.WrStr('Bad FileName: ');
       IO.WrStr(TmpResFileName);
       IO.WrLn;
       HALT
    END;

    IF NOT CopyFile(InResFileName,TmpResFileName) THEN
       IO.WrStr('Making Working copy of "');
       IO.WrStr(InResFileName);
       IO.WrStr('" failed.  Execution is aborted');
       IO.WrLn;
       HALT
    END;

    IF NOT UOpenResourceFile(TmpResFileName) THEN
        ResErrorMessage('Opening')
    END;
    InitialResArrayData;

    HandleLines;

    IF ErrorFound THEN
       DisposeOfFiles;
       IO.WrStr('ResMan found errors: No changes in files produced');
    ELSIF SomethingWasDone THEN
       WindUpResources;
       UpdateFiles;
       IO.WrStr('ResMan completed normally');
    ELSE
       DisposeOfFiles;
       IO.WrStr('ResMan did nothing: No changes in files produced');
    END;
END ResMan.
