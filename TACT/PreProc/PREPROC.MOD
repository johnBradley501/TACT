MODULE PreProc ;

(* copyright (c) 1991-96 Ian Lancashire, Mike Stairs, University of Toronto *)

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
IMPORT Storage ;
IMPORT PCKey ;
IMPORT ASCII, FIO, TWB, Lib, IO;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny, FileNameType,
  (* Proc  *) CheckResVersion, CheckParam;
FROM KeyTranslation IMPORT InitialTranslationData ;
FROM Str IMPORT Compare, Concat ;
FROM Utils IMPORT
  (* Vars  *) StandardSearchList,
  (* Procs *) FindFileInList, GetEnv, Terminate, Status, InstallTermProc ;
FROM UtilsTwo IMPORT InsufficientData ;
FROM Windows  IMPORT
  (* Vars  *) TerminationProc,  ResizeMoveKeyRead,
  (* Procs *) InitWindows, NonWMMessage, EndWindows ;
FROM ResBase IMPORT
  (* Procs *) OpenResourceFile, CloseResourceFile ;
FROM UsenhKBD IMPORT
  (* Procs *) RestoreKbdVectors, SetKbdVectors, UserRequestedStdKBD;
FROM ResMessages IMPORT
   (* proc *) GetResMessage, PutResMessage, ResAskUser ;
FROM KeyBase IMPORT Read, KeyPressed, GetKeyStrokeType, GetKeyStroke, ReadKey;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, ShowHelpItem, ShowCredit;

(* local modules [ie. in current directory] *)
FROM StartUp IMPORT
  (* proc *) DoStartUp, WordAny ;
FROM ScrollingMenu IMPORT InitCodeScrollMenu ;
FROM AlphaPanel IMPORT InitCodeAlphaPanel ;
FROM SetupFile IMPORT InitCodeSetupFile ;

FROM RUNSource IMPORT Run ;

(* FROM PreMain IMPORT Run ; *)

(*<Debug*) IMPORT Storage ; (*Debug>*)

VAR
   EnhancedKbd : BOOLEAN;
   TermList    : ARRAY[0..1] OF CHAR;
   ExitList    : ARRAY[0..3] OF CHAR;
   BaseWind    : TWB.WinType;
   DirName     : FileNameType ;
   FullResName : FileNameType ;
   OpenResult  : CARDINAL ;
   Message     : StrAny ;
   DoingRun    : BOOLEAN ;

PROCEDURE TerminateAll;
VAR
	ch   : CHAR ;
	oldw : TWB.WinType;
   BEGIN
      (*RES REM DEL MSG 486
      At your Request, PREPROC has Stopped.
      *)
(*      PutResMessage( (*RES REM INS*) 486 ); *)
      (*RES OLD CHE 37
      =Y N
      Do you wish to stop PreProc immediately? Y)es or N)o:
      *)
      oldw := TWB.Used();
      ResAskUser( (*RES REM INS*) 37, 'YN', ch);
      TWB.Use(oldw);
      IF ch <> 'Y' THEN  RETURN  END ;

      IF EnhancedKbd THEN
	 RestoreKbdVectors ;
      END ;
      Terminate(Normal)
   END TerminateAll;

PROCEDURE ReadTheKeyStrokes(VAR ch: CHAR; VAR Ext: BOOLEAN);
VAR Done:   BOOLEAN;
    DoRead: BOOLEAN;
    oldw:   TWB.WinType;
BEGIN
   DoRead := TRUE;
   REPEAT
      Done := TRUE;
      IF DoRead THEN
         Read(ch);
         IF (ch = 0C) AND KeyPressed() THEN
            Ext := TRUE;
            Read(ch)
         ELSE Ext := FALSE END;
      END;
      IF Ext THEN
         IF (ch = PCKey.F1) THEN
            oldw := TWB.Used() ;
            DoRead := ShowHelpItem(TermList,ExitList,ch,Ext);
            TWB.PutOnTop( oldw ) ;
            Done := FALSE
         ELSIF (ch = PCKey.F6) THEN
            ShowCredit( 74, TermList, ExitList, ch, Ext) ;
            Done := FALSE ;
         ELSIF ch = PCKey.F10 THEN TerminateAll END;
      ELSE
         Ext := FALSE;
      END;
   UNTIL Done;
END ReadTheKeyStrokes;

PROCEDURE InitializeThings;
VAR
   rc          : CARDINAL ;
   DirName     : FileNameType ;
   FullResName : FileNameType ;
   OpenResult  : CARDINAL ;
   Message     : StrAny ;

BEGIN
   FIO.IOcheck := FALSE ;
   (* force our order of module initialization -- JPI doesn't help!? *)
   Lib.SetReturnCode( 99 ) ;	(* assume we are going to fail *)

   TerminationProc := TerminateAll;  (* must be first thing done! *)
   ResizeMoveKeyRead := ReadKey ;

   TermList[0] := ASCII.rs;
   TermList[1] := ASCII.esc;
   ExitList[0] := PCKey.F2;
   ExitList[1] := PCKey.F3;
   ExitList[2] := PCKey.F4;
   ExitList[3] := PCKey.F9;

   EnhancedKbd := NOT UserRequestedStdKBD();
   IF EnhancedKbd THEN
      InstallTermProc(RestoreKbdVectors);
      SetKbdVectors ;  (* use enhanced Keyboard BIOS patch *)
   END ;

   GetKeyStroke := ReadTheKeyStrokes;

   GetEnv( 'TACTPATH', StandardSearchList );
   IF StandardSearchList[0] = 0C THEN GetEnv( 'PATH', StandardSearchList ) END;

   IF NOT FindFileInList( StandardSearchList, 'TACT.RES', DirName ) THEN
      NonWMMessage( 'File "TACT.RES" could not be found.' ) ;
      Terminate( Normal ) ;  (* no dumps *)
   END ;
   Concat( FullResName , DirName, 'TACT.RES' ) ;
   IF NOT OpenResourceFile( FullResName, OpenResult ) THEN
      NonWMMessage( 'Unable to open file "DCTPROGS.RES".' ) ;
      Terminate( Normal ) ;  (* no dumps *)
   END ;

   InitCodeScrollMenu ;  (* this is for OVERLAY mechanism *LP* *)
   InitCodeAlphaPanel ;
   InitCodeSetupFile ;


   CheckResVersion;

   (*RES OLD MSG 578
   preproc -b -f <output reference filename> -r <output stripped filename>
   -s <.MKS filename> -t <output tags filename> -w <path> <input text
   filename> <output .LST filename>
   *)

   CheckParam( (*RES REM INS*) 578 ) ;
   InitWindows() ;
   IF NOT InitialTranslationData() THEN HALT END;

   PushHelpItem(56); (* Help Res 56 is PREPROC's single help item *)
END InitializeThings;


BEGIN

   InitializeThings;

   DoingRun := FALSE;

   DoStartUp ;

   DoingRun := TRUE ;

   Run( Message ) ;

   CloseResourceFile ;

   EndWindows ;

   IF Message[0] <> 0C THEN
      IO.WrStr( Message ) ;
      IO.WrLn ;
   END ;
END PreProc .

