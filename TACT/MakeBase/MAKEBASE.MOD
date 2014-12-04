(*# data(const_in_code=>on) *)

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
MODULE MakeBase ;

(*V1=Production *)
(*V2=SpaceCheck *)
(*V3=VirtCheck  *)
(*V4=Overlay    *)

IMPORT PCKey ;
IMPORT ASCII;
IMPORT TWB, FIO, Lib, IO ;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny, FileNameType,
  (* Proc  *) CheckResVersion, CheckParam;
FROM KeyTranslation IMPORT InitialTranslationData ;
FROM Str     IMPORT
  (* Procs *) Concat, Compare ;
FROM StartUp IMPORT
  (* proc *) DoStartUp;
FROM RUNSource IMPORT Run ;
FROM Utils IMPORT
  (* Vars  *) StandardSearchList,
  (* Procs *) FindFileInList, GetEnv, Terminate, Status, InstallTermProc ;
FROM Windows  IMPORT
  (* Vars  *) TerminationProc, ResizeMoveKeyRead,
  (* Procs *) InitWindows, NonWMMessage, EndWindows ;
FROM ResBase IMPORT
  (* Procs *) OpenResourceFile, CloseResourceFile ;
FROM UsenhKBD IMPORT
  (* Procs *) RestoreKbdVectors, SetKbdVectors, UserRequestedStdKBD;

(*<SpaceCheck
FROM CheckMemory IMPORT
  (* Procs *) OpenLogFile, MemSnapShot, CloseLogFile ;
SpaceCheck>*)

FROM ResMessages IMPORT
   (* proc *) PutResMessage, ResAskUser ;
FROM KeyBase IMPORT ReadKey, GetKeyStrokeType, GetKeyStroke;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, ShowHelpItem;

(*<VirtCheck
FROM VirtualMemory IMPORT
  (* Procs *) GetNoOfPageFualts, GetNoOfPageReferences, GetAmtOfPageFrag,
	      GetNoOfSwapPages, DumpVirtualQueue, GetHexPageTableEntry,
	      GetDumpVirtPage ;
FROM RealInOut IMPORT WriteReal ;
FROM InOut     IMPORT WriteString, WriteLn, WriteCard ;
VirtCheck>*)

(*<Overlay
IMPORT Overlay ;
Overlay>*)
FROM ScrollingMenu IMPORT InitCodeScrollMenu ;
FROM AlphaPanel IMPORT InitCodeAlphaPanel ;
FROM SetupFile IMPORT InitCodeSetupFile ;
FROM LogFile IMPORT LogFileInitCode ;

VAR
   rc          : CARDINAL ;
(* Percentage  : REAL ; *)
   DirName     : FileNameType ;
   FullResName : FileNameType ;
   OpenResult  : CARDINAL ;
   Message     : StrAny ;
   DoingRun    : BOOLEAN;
   EnhancedKbd : BOOLEAN;
   TermList    : ARRAY[0..1] OF CHAR;
   ExitList    : ARRAY[0..3] OF CHAR;

PROCEDURE TerminateAll;
   VAR
	ch   : CHAR ;
	oldw : TWB.WinType;
   BEGIN
	(*RES OLD CHE 16
	=Y N
	Do you wish to stop MakeBase immediately? Y)es or N)o:
	*)
	oldw := TWB.Used();
	ResAskUser( (*RES REM INS*) 16, 'YN', ch);
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
	 ReadKey( ch, Ext) ;
      END ;
      IF Ext THEN
         IF (NOT DoingRun) AND (ch = PCKey.F1) THEN
            oldw := TWB.Used() ;
            DoRead := ShowHelpItem(TermList,ExitList,ch,Ext);
            TWB.PutOnTop( oldw ) ;
            Done := FALSE
         ELSIF ch = PCKey.F10 THEN
            IF DoingRun THEN
                ch := 33C; (* equivalent to ESC key! *)
                Ext := FALSE;
            ELSE  TerminateAll ; Done := FALSE  END;
         END;
      ELSE
         Ext := FALSE;
      END;
   UNTIL Done;
END ReadTheKeyStrokes;

BEGIN
   FIO.IOcheck := FALSE ;
   (* force our order of module initialization -- JPI doesn't help!? *)
   LogFileInitCode ;

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
   DoingRun := FALSE;

   GetEnv( 'TACTPATH', StandardSearchList );
   IF StandardSearchList[0] = 0C THEN GetEnv( 'PATH', StandardSearchList ) END;

   IF NOT FindFileInList( StandardSearchList, 'TACT.RES', DirName) THEN
      NonWMMessage( 'File "TACT.RES" could not be found.' ) ;
      Terminate( Normal ) ;  (* no dumps *)
   END ;
   Concat( FullResName, DirName, 'TACT.RES' ) ;
   IF NOT OpenResourceFile( FullResName, OpenResult ) THEN
      NonWMMessage( 'Unable to open file "TACT.RES".' ) ;
      Terminate( Normal ) ;  (* no dumps *)
   END ;

   (*<Overlay
   IF NOT FindFileInList( StandardSearchList, 'MAKEBASE.OV1', DirName) THEN
      NonWMMessage( 'File "MAKEBASE.OV1" could not be found.');
      Terminate( Normal ) ;  (* no dumps *)
   END ;
   Concat( Overlay.Path, DirName, 'MAKEBASE' ) ;
   Overlay.Load( 1 ) ;
   Overlay>*)
   InitCodeScrollMenu ;  (* this is for OVERLAY mechanism *LP* *)
   InitCodeAlphaPanel ;
   InitCodeSetupFile ;

   CheckResVersion;

   (*RES OLD MSG 575
   makebase -b -f -r "<template>" -t "<title>" -w <path> <input text filename>
   @<special .XDT filename> <output .TDB filename> <.MKS filename>
   *)

   CheckParam ((*RES REM INS*) 575 ) ;

   (*<SpaceCheck
   OpenLogFile() ;
   MemSnapShot( 'MakeBase - Start ' ) ;
   SpaceCheck>*)

   InitWindows() ;

   (*<SpaceCheck MemSnapShot( 'MakeBase - After "InitWindows" ' ) ; SpaceCheck>*)

   IF NOT InitialTranslationData() THEN HALT END;

   (*<SpaceCheck MemSnapShot( 'MakeBase - after "InitialTranslationData" ' ) ; SpaceCheck>*)

   PushHelpItem(26); (* Help Res 26 is MAKEBASE's basic help *)
   DoStartUp;

   (*<Overlay   Overlay.UnLoad( 1 ) ;   Overlay>*)

   (*<SpaceCheck MemSnapShot( 'MakeBase - after "DoStartUp" ' ) ; SpaceCheck>*)
   DoingRun := TRUE;
   Run() ;

   (* Lib.SetReturnCode( 0 ) ;	set in Run() -- if got this far then OK *)

   (*<SpaceCheck
   MemSnapShot( 'MakeBase - after "Run" ' ) ;
   CloseLogFile() ;
   SpaceCheck>*)

   CloseResourceFile ;

   EndWindows ; (* m.s. *)

   IO.WrStr( 'MAKEBASE finished.' ) ; (* m.s. *)
   IO.WrLn ;
   (*<VirtCheck
      WriteLn ;
      WriteString( 'Total Amount of page memory not used = ' ) ;
      WriteCard( GetAmtOfPageFrag(), 10 ) ;
      WriteLn ;
      WriteString( 'Number of Swap Pages = ' ) ;
      WriteCard( GetNoOfSwapPages(), 10 ) ;
      WriteLn ;
      WriteString( 'Number of Page Fualts = ' ) ;
      WriteCard( GetNoOfPageFualts(), 10 ) ;
      WriteLn ;
      WriteString( 'Number of Page References = ' ) ;
      WriteCard( GetNoOfPageReferences(), 10 ) ;
      WriteLn ;
      WriteString( 'Percentage of Page Fualts = ' ) ;
      Percentage := FLOAT(GetNoOfPageFualts()) / FLOAT(GetNoOfPageReferences()) * 100.0 ;
      WriteReal( Percentage, 10 ) ;
      WriteLn ;
      VirtCheck>*)
END MakeBase .

