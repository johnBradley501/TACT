MODULE ResExtr;

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

(* This module reads a file containing a list of source files, and,
for each RES it finds in the source file writes:

(1) the source file name,
(2) the line where RES item found,
(3) the RES material itself.

To an output file  .... j.b. *)

FROM SYSTEM IMPORT BYTE,ADDRESS,SIZE,ADR;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteChar;
IMPORT Lib;
IMPORT Str;
IMPORT FIO;

FROM ResManUtils IMPORT
  (* type *) ResOpType,
  (* var *)  InCmdFileName, InCmdFile, OutCmdFile,
             ResOptNames, ErrorFound,
  (* proc *) ReportError, ReadCmdLine, NextResLine,
             FindResType;

FROM ResComments IMPORT
   FindOpenComment, FindCloseComment, FindNextThing;

IMPORT IO;

FROM Utils IMPORT
 (* proc *) StandardizeFileName,RemoveExtension;

CONST
   IllegalItemNumber = 64000;
   Version = '1.0';

VAR
    Line:              ARRAY[0..255] OF CHAR;
    ListFile:          FIO.File;
    InCmdBuf:          ARRAY[0..2047] OF CHAR;
    OutCmdBuf:         ARRAY[0..2047] OF CHAR;
    ListFileName:      ARRAY[0..255] OF CHAR;
    FirstinFile:       BOOLEAN;
    SomethingWasDone:  BOOLEAN;
    CurParm:           CARDINAL;
    Answ:              CHAR;
    OutputFileName:    ARRAY[0..255] OF CHAR;

PROCEDURE HandleResCommand(BeforeFirst:   ARRAY OF CHAR;
                           FirstPart:     ARRAY OF CHAR;
                           LineCount:     CARDINAL);
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
   SomethingWasDone := TRUE;
END CopyResCommand;

PROCEDURE PutLineNumber(LineCount: CARDINAL);
BEGIN
   IF FirstinFile THEN
      FIO.WrStr(OutCmdFile,'File: ');
      FIO.WrStr(OutCmdFile,InCmdFileName);
      FIO.WrLn(OutCmdFile);
      FirstinFile := FALSE;
   END;

   FIO.WrStr(OutCmdFile,'[');
   FIO.WrCard(OutCmdFile,LineCount,0);
   FIO.WrStr(OutCmdFile,']');
   FIO.WrLn(OutCmdFile);
END PutLineNumber;

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
   END;
   IF (ResOp <> ResInsertNumber) AND (ResOp <> ResComment) THEN
      PutLineNumber(LineCount);
      CopyResCommand
   END;
END HandleResCommand;

PROCEDURE HandleLines;
VAR
   LineBefore:   ARRAY[0..255] OF CHAR;
   LineAfter:    ARRAY[0..255] OF CHAR;
   LineCount:    CARDINAL;

BEGIN
    FirstinFile := TRUE;
    LineCount := 0;
    WHILE ReadCmdLine(Line) DO
        INC(LineCount);
        IF FindOpenComment(Line,LineBefore,LineAfter) THEN
           IF (LineAfter[0] = 'R') AND (LineAfter[1] = 'E') AND
           (LineAfter[2] = 'S') THEN
                HandleResCommand(LineBefore,LineAfter, LineCount);
           END
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

PROCEDURE ProcessListFile;
BEGIN
    FIO.RdStr(ListFile, InCmdFileName);
    REPEAT
       IF InCmdFileName[0] = '#' THEN (* ignore line *)
          Str.Delete(InCmdFileName, 0,1);
          IO.WrStr(InCmdFileName);
          IO.WrLn;
       ELSIF InCmdFileName[0] = '!' THEN
          Str.Delete(InCmdFileName, 0,1);
          FIO.WrStr(OutCmdFile,InCmdFileName);
          FIO.WrLn(OutCmdFile);
       ELSIF NOT StandardizeFileName(InCmdFileName,'.MOD') THEN
          IO.WrStr('Non-Standard File Name: ');
          IO.WrStr(InCmdFileName);
          IO.WrLn;
          HALT;
       ELSIF NOT FIO.Exists(InCmdFileName) THEN
          IO.WrStr('Could not find File: ');
          IO.WrStr(InCmdFileName);
          IO.WrLn;
       ELSE
          InCmdFile := FIO.Open(InCmdFileName);
          FIO.AssignBuffer(InCmdFile, InCmdBuf);
          IO.WrStr('File:');
          IO.WrStr(InCmdFileName);
          IO.WrLn;
          HandleLines;
          FIO.Close(InCmdFile);
       END;
       FIO.RdStr(ListFile, InCmdFileName);
    UNTIL FIO.EOF;
    FIO.Close(ListFile);
END ProcessListFile;

BEGIN
    CurParm := 0;
    SomethingWasDone := FALSE;

    IO.WrStr('RESEXTR Version ');
    IO.WrStr(Version);
    IO.WrLn;

    IO.WrStr('Input File containing Source Files: ');
    GetParam(ListFileName);

    IF NOT StandardizeFileName(ListFileName,'.LST') THEN
        IO.WrStr('Non-Standard File Name: ');
        IO.WrStr(ListFileName);
        IO.WrLn;
        HALT;
    END;
    IF NOT FIO.Exists(ListFileName) THEN
       IO.WrStr('Could not find File: ');
       IO.WrStr(ListFileName);
       IO.WrLn;
       HALT;
    END;
    ListFile := FIO.Open(ListFileName);

    IO.WrStr('Output Listing File: ');
    GetParam(OutputFileName);
    IF NOT StandardizeFileName(OutputFileName,'.RSI') THEN
        IO.WrStr('Non-Standard File Name: ');
        IO.WrStr(OutputFileName);
        IO.WrLn
    END;

    IF FIO.Exists(OutputFileName) THEN
       Answ := ' ';
       IO.WrStr('File ');
       IO.WrStr(OutputFileName);
       IO.WrStr('Exists, Choose "O" to Overwrite, "A" to Append, "Q" to Quit: ');
       WHILE Answ = ' ' DO
          IO.RdStr(Answ);
          Answ := CAP(Answ);
          CASE Answ OF
            'O': OutCmdFile := FIO.Create(OutputFileName)
          | 'A': OutCmdFile := FIO.Append(OutputFileName)
          | 'Q': HALT
          ELSE Answ := ' '
          END;
       END;
    ELSE
       OutCmdFile := FIO.Create(OutputFileName);
    END;
    FIO.AssignBuffer(OutCmdFile, OutCmdBuf);

    ProcessListFile;

    IF ErrorFound THEN IO.WrStr('ResExtr found errors')
    ELSIF SomethingWasDone THEN IO.WrStr('ResExtr completed normally')
    ELSE IO.WrStr('ResExtr found nothing') END;

    FIO.Close(OutCmdFile);
END ResExtr.
