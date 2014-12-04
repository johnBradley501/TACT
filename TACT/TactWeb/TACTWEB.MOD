MODULE TACTWeb;
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


(*V1=Production *)
(*V2=Debug *)

IMPORT ASCII, Str ;
IMPORT FIO;
FROM TACTProcesses IMPORT BeginTACTProcesses;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny, FileNameType,
  (* Proc  *) CheckResVersion;
FROM Translations IMPORT InitialTranslationData, (* XAppend, XClose, *)
     XWriteLine, OutFile, OutFileName, FILEText, XStdOut, XWrLn, XWrNXlate ;
FROM VirtMem IMPORT InitVirtMem ;
FROM Utils IMPORT
  (* Vars  *) StandardSearchList,
  (* Procs *) GetEnv, FindFileInList, Terminate, Status,
              InstallTermProc, Beep, ParseFilename, MakeFilename ;
FROM ResBase IMPORT
  (* Procs *) OpenResourceFile, CloseResourceFile ;
FROM ResMessages IMPORT
   (* proc *) MsgString, PutResError, GetResMessage;
FROM TACTInit IMPORT
  (* proc *) GetParamData, InitializeDBs;
FROM VirtMem IMPORT
    (* vars *) PDBFile, CloseVirtFile;
FROM DBData IMPORT PDBOpen, MainCatList;
FROM HyperBase IMPORT
  (* TYPE *)  HyperFile,
  (* PROC *)  CloseHyperFile;
FROM WWWBase IMPORT
   (* procs *) DoWWWWork;
FROM ErrorBase IMPORT OutputErrorProc;
IMPORT SYSTEM,Storage (*,VidIf*);

VAR
(* DataBaseName    : StrAny; *)
   DataBaseName    : FileNameType ;
   TemplateFileName: FileNameType;
(*   OutOpen         : BOOLEAN; *)
   dummy           : CARDINAL;

(*
PROCEDURE CloseOutFile();
BEGIN
   IF OutOpen THEN XClose(OutFile) END;
   OutOpen := FALSE;
END CloseOutFile;

PROCEDURE OpenOutFile(OutFileName: ARRAY OF CHAR);
VAR
   EMsg:   StrAny;
BEGIN
   IF NOT(XAppend( OutFileName, '', FILEText, OutFile, EMsg)) THEN HALT END;
   OutOpen := TRUE;
   InstallTermProc(CloseOutFile);
END OpenOutFile;
*)

PROCEDURE ErrorToErrOut(t: ARRAY OF CHAR);
BEGIN
   FIO.WrStr(FIO.ErrorOutput, t);
   FIO.WrLn(FIO.ErrorOutput);
END ErrorToErrOut;

PROCEDURE ErrorToOutfile(t: ARRAY OF CHAR);
VAR
   dummy2: BOOLEAN;
   dummy:  CARDINAL;
BEGIN
   dummy2 := XWriteLine(OutFile, '?', t, dummy);
END ErrorToOutfile;

PROCEDURE CreateTACTEnvironment();
VAR
   DirName        : FileNameType ;
   FullResName    : FileNameType ;
   OpenResult     : CARDINAL ;

BEGIN
(* VidIf.SetUserTrapProc(StoreTraceTrap) ; (* Connect VID User breakpoint *) *)

   (*<Debug
   Storage.ClearOnAllocate := TRUE ;  (* does both ALLOCATE & DEALLOCATE *)
   Debug>*)

   FIO.IOcheck := FALSE ;	(* we will handle all IO error messages *)

   GetEnv( 'TACTPATH', StandardSearchList );
   IF StandardSearchList[0] = 0C THEN GetEnv( 'PATH', StandardSearchList ) END;

   IF NOT FindFileInList( StandardSearchList, 'TACTJB.RES', DirName ) THEN
      Beep;
      Terminate( Normal ) ;
   END ;
   Str.Concat( FullResName, DirName, 'TACTJB.RES' ) ;
   IF NOT OpenResourceFile( FullResName, OpenResult ) THEN
      Beep;
      Terminate( Normal ) ;
   END ;

   CheckResVersion;
   IF NOT InitialTranslationData() THEN HALT END;
   BeginTACTProcesses;
   InitVirtMem() ;  (* also does a  SetupMemoryManagement() *)
END CreateTACTEnvironment;

BEGIN
(* OutOpen := FALSE; *)
   OutputErrorProc := ErrorToErrOut;

   CreateTACTEnvironment;
   XStdOut(FILEText, OutFile);
   OutputErrorProc := ErrorToOutfile;
   XWrNXlate(OutFile, 'Content-type: text/html', dummy);
   XWrLn(OutFile, dummy);
   XWrLn(OutFile, dummy);

(* GetParamData(DataBaseName, OutFileName, TemplateFileName); *)
   GetParamData(DataBaseName, TemplateFileName);

   InitializeDBs(DataBaseName);
   DoWWWWork(TemplateFileName);
(*  CloseOutFile; *)
END TACTWeb .
