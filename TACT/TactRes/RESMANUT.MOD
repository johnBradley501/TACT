IMPLEMENTATION MODULE ResManUtils;

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

(* JPI Version ... j.b. *)

FROM SYSTEM IMPORT BYTE,ADDRESS,SIZE,ADR;
IMPORT ASCII;
FROM Storage IMPORT ALLOCATE,DEALLOCATE;
IMPORT Str;
IMPORT Lib;
IMPORT FIO;
IMPORT IO;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteChar;

FROM ResComments IMPORT
   FindOpenComment, FindCloseComment, FindNextThing;

FROM ResBase IMPORT
   (*var*)  NullPos,
   (*proc*) CloseResourceFile;

FROM Utils IMPORT
 (* type *) BResultType,
 (* proc *) StandardizeFileName,RemoveExtension;

VAR
    CmdLine:          CARDINAL;
    CommNest:         CARDINAL;

PROCEDURE CopyFile(InFileName:  ARRAY OF CHAR;
                   OutFileName: ARRAY OF CHAR):BOOLEAN;
VAR     Data:    POINTER TO ARRAY[0..4095] OF BYTE;
        In,Out:  FIO.File;
        num:     CARDINAL;
        IOrslt:  CARDINAL;
BEGIN
     IF NOT FIO.Exists(InFileName) THEN RETURN TRUE END;

     FIO.IOcheck := FALSE;

     In := FIO.Open(InFileName);
     IF FIO.IOresult() <> 0 THEN RETURN FALSE END;

     Out := FIO.Create(OutFileName);
     IF FIO.IOresult() <> 0 THEN RETURN FALSE END;

     ALLOCATE(Data,4096);
     num := FIO.RdBin(In,Data^,4096);
     IOrslt := FIO.IOresult();
     WHILE (NOT FIO.EOF) AND (IOrslt = 0) AND (num <> 0) DO
          FIO.WrBin(Out,Data^,num);
          IOrslt := FIO.IOresult();
          IF IOrslt = 0 THEN
             num := FIO.RdBin(In,Data^,4096);
             IOrslt := FIO.IOresult();
          END;
     END;

     IF IOrslt <> 0 THEN RETURN FALSE END;

     DEALLOCATE(Data,4096);

     FIO.Close(In);
     FIO.Close(Out);
     IF FIO.IOresult() <> 0 THEN RETURN FALSE END;
     FIO.IOcheck := TRUE;
     RETURN TRUE;
END CopyFile;

PROCEDURE DisposeOfFiles;
BEGIN
    FIO.Close(OutCmdFile);
    CloseResourceFile;
    FIO.Erase(TmpResFileName);
    FIO.Erase(TmpCmdFileName);
END DisposeOfFiles;

PROCEDURE UpdateFiles;
VAR  BAKName:    ARRAY[0..80] OF CHAR;
BEGIN
    RemoveExtension(InCmdFileName,BAKName);
    IF NOT StandardizeFileName(BAKName,'.BAK') THEN
        IO.WrStr('Bad File Name: ');
        IO.WrStr(BAKName);
        IO.WrLn
    END;
    IF FIO.Exists(BAKName) THEN FIO.Erase(BAKName) END;

    FIO.Close(InCmdFile);
    FIO.Rename(InCmdFileName,BAKName);
    FIO.Close(OutCmdFile);
    FIO.Rename(TmpCmdFileName,InCmdFileName);

    RemoveExtension(InResFileName,BAKName);
    IF NOT StandardizeFileName(BAKName,'.RBK') THEN
        IO.WrStr('Bad File Name: ');
        IO.WrStr(BAKName);
        IO.WrLn
    END;
    IF FIO.Exists(BAKName) THEN FIO.Erase(BAKName) END;

    IF FIO.Exists(InResFileName) THEN FIO.Rename(InResFileName,BAKName) END;
    CloseResourceFile;
    FIO.Rename(TmpResFileName,InResFileName);
END UpdateFiles;

PROCEDURE InputErrorMessage(TypeText:    ARRAY OF CHAR;
                            Result:      BResultType);
VAR     ResultText:   ARRAY[0..50] OF CHAR;
BEGIN
    IO.WrStr('**ERROR** ');
    IO.WrStr(TypeText);
    IO.WrStr(' ');
    IO.WrStr(InCmdFileName);
    IO.WrStr(': ');
    IOErrorMessage(Result,ResultText);
    IO.WrStr(ResultText);
    IO.WrLn;
    DisposeOfFiles;
    HALT;
END InputErrorMessage;

PROCEDURE ResErrorMessage(TypeText:    ARRAY OF CHAR);
BEGIN
    IO.WrStr('**ERROR** Doing RES Command In ');
    IO.WrStr(InCmdFileName);
    IO.WrStr(': ');
    IO.WrStr(TypeText);
    IO.WrLn;
    DisposeOfFiles;
    HALT;
END ResErrorMessage;

PROCEDURE ReportError(TypeText: ARRAY OF CHAR);
BEGIN
    IO.WrStr('**ERROR** (');
    IO.WrCard(CmdLine,0);
    IO.WrStr('/');
    IO.WrStr(InCmdFileName);
    IO.WrStr(') ');
    IO.WrStr(TypeText);
    IO.WrLn;
    ErrorFound := TRUE;
END ReportError;

PROCEDURE FindResType(Parm: ARRAY OF CHAR;
                  VAR Res:  ResOpType): BOOLEAN;
VAR   i:     ResOpType;
BEGIN
    FOR i := MIN(ResOpType) TO MAX(ResOpType) DO
        IF (Str.Compare(Parm,ResOptNames[i]) = 0) THEN
            Res := i;
            RETURN TRUE
        END
    END;
    RETURN FALSE
END FindResType;

PROCEDURE ReadCmdLine(VAR RLine: ARRAY OF CHAR): BOOLEAN;
VAR
   enough:       BOOLEAN;
BEGIN
   INC(CmdLine);
   FIO.RdStr(InCmdFile,RLine);
   IF FIO.EOF THEN RETURN FALSE END;
   RETURN TRUE
END ReadCmdLine;

PROCEDURE NextResLine(VAR Line: ARRAY OF CHAR): BOOLEAN;
VAR   RLine:      ARRAY[0..255] OF CHAR;
      loop:       BOOLEAN;
      LineBefore: ARRAY[0..255] OF CHAR;
      LineAfter:  ARRAY[0..255] OF CHAR;
      lpos:       CARDINAL;
BEGIN
   IF CommNest = 0 THEN
      INC(CommNest);
      RETURN FALSE
   END;

   IF NOT ReadCmdLine(RLine) THEN
       ReportError('Unexpected EOF in a RES Command');
       RETURN FALSE;
   END;
   FIO.WrStr(OutCmdFile,RLine);
   FIO.WrLn(OutCmdFile);
   Line[0] := 0C;
   lpos := 0;
   loop := TRUE;
   WHILE loop DO
      IF FindOpenComment(RLine,LineBefore,LineAfter) THEN
         INC(CommNest);
         SWriteString(Line,lpos,LineBefore,0);
         SWriteString(Line,lpos,'(*',0);
         Str.Copy(RLine,LineAfter)
      ELSIF FindCloseComment(RLine,LineBefore,LineAfter) THEN
         DEC(CommNest);
         SWriteString(Line,lpos,LineBefore,0);
         IF CommNest <> 0 THEN
            SWriteString(Line,lpos,'*)',0)
         ELSE
            loop := FALSE
         END;
         Str.Copy(RLine,LineAfter);
      ELSE
         loop := FALSE;
         SWriteString(Line,lpos,RLine,0)
      END
   END;
   lpos := 0;
   WHILE Line[lpos] <> 0C DO
     IF Line[lpos] = ASCII.ht THEN Line[lpos] := ' ' END;
     INC(lpos)
   END;
   RETURN TRUE;
END NextResLine;

PROCEDURE IOErrorMessage(Code:     BResultType;
                     VAR Message:  ARRAY OF CHAR);
VAR
    temp:      ARRAY[0..35] OF CHAR;
BEGIN
   CASE Code OF
    OK :
       temp := 0C |
(*<Modl*)
    InternalError :
       temp := 'M2 FileIO Internal Error' |
    FileNotFound:
       temp := 'File not found' |
    FileAlreadyExists:
       temp := 'File Already Exists' |
    PathNotFound:
       temp := 'Path Not Found' |
    TooManyFiles:
       temp := 'Too Many Files' |
    DeviceFull:
       temp := 'Device Full' |
    DirectoryFull:
       temp := 'Directory Full' |
    FileAccessDenied:
       temp := 'File Access Denied' |
    DeviceAccessDenied:
       temp := 'Device Access Denied' |
    InvalidFileHandle:
       temp := 'Invalid File Handle' |
    InsufficientMemory:
       temp := 'Insufficient Memory for IO' |
    NoSuchDevice:
       temp := 'No Such Device' |
    DeviceNotReady:
       temp := 'Device Not Ready' |
    EndOfMedium:
       temp := 'End of Medium' |
    DataError:
       temp := 'Data Error' |
    DeviceFailure:
       temp := 'Device Failure' |
(*Modl>*)
(*<Modf
    OpenFailed:     temp := 'Failure during File Opening' |
    CreateFailed:   temp := 'Failure during File Create' |
    WriteFailed:    temp := 'Failure during writing to file' |
    CloseFailed:    temp := 'Failure during File Closing' |
    ReadFailed:     temp := 'Failure during reading from file' |
Modf>*)
    InsufficientData:
       temp := 'Insufficient Data' |
    TranslationError:
       temp := 'Error in Translation'
   ELSE
       temp := 'Unknown IO Error'
   END;
   Str.Copy(Message,temp);
END IOErrorMessage;

BEGIN
    ResOptNames[ResComment] := 'REM';
    ResOptNames[ResOld] := 'OLD';
    ResOptNames[ResNew] := 'NEW';
    ResOptNames[ResUpdate] := 'UPD';
    ResOptNames[ResDelete] := 'DEL';
    ResOptNames[ResInsertNumber] := 'INS';
    ErrorFound := FALSE;
    CmdLine := 0;
    CommNest := 1;
END ResManUtils.
