MODULE UseBase ;

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

(*V1=Production *)
(*V2=Debug *)

(*--------------------------------------------------------------------------
History:

  Ver 1.2 --  4 Jan 90, Lidio Presutti
  - turned off FIO.IOcheck for all modules.
--------------------------------------------------------------------------*)

IMPORT TWB, ASCII, Str ;
IMPORT PCKey ;
IMPORT FIO;
FROM TACTProcesses IMPORT BeginTACTProcesses;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny, FileNameType,
  (* Proc  *) CheckResVersion, CheckParam;
FROM KeyTranslation IMPORT InitialTranslationData ;
FROM VirtMem IMPORT InitVirtMem ;
FROM Utils IMPORT
  (* Vars  *) StandardSearchList,
  (* Procs *) GetEnv, FindFileInList, Terminate, Status,
              InstallTermProc(*, Beep*) ;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM Windows  IMPORT
  (* Vars *)  TerminationProc,
  (* Procs *) InitWindows, NonWMMessage;
FROM ResBase IMPORT
  (* Procs *) OpenResourceFile, CloseResourceFile ;
FROM ResMessages IMPORT
   (* proc *) MsgString, PutResError, GetResMessage;
FROM TACTInit IMPORT
  (* proc *) InitializeDBs,TermList,ExitList;
FROM VirtMem IMPORT
    (* vars *) PDBFile, CloseVirtFile;
FROM DBData IMPORT PDBOpen, MainCatList;
FROM HyperBase IMPORT
  (* TYPE *)  HyperFile,
  (* PROC *)  CloseHyperFile;
FROM TACTBase IMPORT
   (* procs *) DoTACTWork;
FROM UsenhKBD IMPORT
  (* Procs *) RestoreKbdVectors, SetKbdVectors, UserRequestedStdKBD;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem;
FROM KeyUtils IMPORT
  (* Procs *) SetupDefaultKeyUtilSettings;
(* FROM PrintModule IMPORT InitialPrintModule; *)
FROM TACTListModule IMPORT DiscardList;
IMPORT SYSTEM,Storage (*,VidIf*);

PROCEDURE CheckStorage( heap : Storage.HeapRecPtr ) : BOOLEAN ;
(*
   This routine checks that the storage free space chain is consistant
   ie that no obvious corruption has occured (ie memory ovewritten
   or incorrectly deallocated)
   Returns TRUE if storage is OK
*)
VAR
   pp,hp : Storage.HeapRecPtr ;
BEGIN
   hp := heap ; IF hp^.size<>0 THEN RETURN FALSE END ;
   LOOP
      pp := hp ; hp := hp^.next ;
      IF (hp=NIL)OR(SYSTEM.Seg(pp^)>=SYSTEM.Seg(hp^)) THEN RETURN FALSE END ;
      IF hp^.size = MAX(CARDINAL) THEN EXIT END ;
      IF (SYSTEM.Seg(pp^)+pp^.size>=SYSTEM.Seg(hp^))
          OR(hp^.size=0)OR(hp^.size>=0A000H) THEN
         RETURN FALSE
      END ;
   END ;
   RETURN (hp^.next=heap) ; (* ok if can join hands *)
END CheckStorage ;

(*
PROCEDURE StoreTraceTrap ( modname : ARRAY OF CHAR;
                           lineno  : CARDINAL ) : BOOLEAN ;
VAR
   ok    : BOOLEAN ;
   ha    : CARDINAL ;
   hta   : CARDINAL ;
   fr    : CARDINAL ;
BEGIN
   ok := CheckStorage(Storage.MainHeap) ;
   IF ok THEN
      ha  := Storage.HeapAvail(Storage.MainHeap) ;
      hta := Storage.HeapTotalAvail(Storage.MainHeap) ;
   ELSE
      ha := 0 ; hta := 1 ;
   END ;
   fr := CARDINAL((LONGCARD(ha)*100)DIV LONGCARD(hta));
   VidIf.Trace('%10s(%u): Tot = %-5u Avail = %-5u \n',
               modname, lineno, hta, ha);
   IF NOT ok THEN
      VidIf.Trace(' Storage corrupt\n',0,0,0,0);
      RETURN TRUE ;                (* Stop if storage corrupt *)
   END;
   IF (ha<8192 DIV 16) THEN       (* or less than 8K left *)
      VidIf.Trace(' Storage exausted\n',0,0,0,0);
      RETURN TRUE ;
   END ;
   RETURN TRUE ; (* FALSE ;  Continue *)
END StoreTraceTrap;
*)

VAR
   rc             : CARDINAL ;
   DirName        : FileNameType ;
   FullResName    : FileNameType ;
   OpenResult     : CARDINAL ;
   BaseWindow     : TWB.WinType;
   BaseWindowInfo : WindowInfo;
   EnhancedKbd	   : BOOLEAN ;
   RtdStr   	   : StrAny ;

PROCEDURE StartingTerminateAll;
   BEGIN
      IF EnhancedKbd THEN
	 RestoreKbdVectors ;
      END ;
      TWB.CursorOn;
      Terminate(Normal)
   END StartingTerminateAll;

PROCEDURE TerminateAll;
VAR ErrMsg:   StrAny;
   BEGIN
      IF PDBOpen THEN
	 DiscardList(MainCatList);
	 PDBOpen := FALSE;
         CloseVirtFile(PDBFile);
         (*RES REM DEL MSG 136*)
(*       IF NOT CloseHyperFile(PDBFile, ErrMsg) THEN
            (*RES OLD MSG 136
            UseBase could not close .GIX File %0.
            *)
            MsgString(ErrMsg, 0);
            PutResError( (*RES REM INS*) 136 );
         END; *)
      END;
      IF EnhancedKbd THEN
	 RestoreKbdVectors ;
      END ;
      Terminate(Normal)
   END TerminateAll;

BEGIN
(* VidIf.SetUserTrapProc(StoreTraceTrap) ; (* Connect VID User breakpoint *) *)

   (*<Debug
   Storage.ClearOnAllocate := TRUE ;  (* does both ALLOCATE & DEALLOCATE *)
   Debug>*)

   TerminationProc := StartingTerminateAll;  (* must be first thing done! *)

   FIO.IOcheck := FALSE ;	(* we will handle all IO error messages *)

   EnhancedKbd := NOT UserRequestedStdKBD();
   IF EnhancedKbd THEN
      InstallTermProc(RestoreKbdVectors);
      SetKbdVectors ;  (* use enhanced Keyboard BIOS patch *)
   END ;

   GetEnv( 'TACTPATH', StandardSearchList );
   IF StandardSearchList[0] = 0C THEN GetEnv( 'PATH', StandardSearchList ) END;

   IF NOT FindFileInList( StandardSearchList, 'TACT.RES', DirName ) THEN
      NonWMMessage( 'File "TACT.RES" could not be found.' ) ;
      Terminate( Normal ) ;
   END ;
   Str.Concat( FullResName, DirName, 'TACT.RES' ) ;
   IF NOT OpenResourceFile( FullResName, OpenResult ) THEN
      NonWMMessage( 'Unable to open file "TACT.RES".' ) ;
      Terminate( Normal ) ;
   END ;

   CheckResVersion;

   (*RES OLD MSG 582
   USEBASE -c -g <.GIX filename> -s <script filename> <input .TDB filename>
   *)
   CheckParam((*RES REM INS*) 582) ;
   BeginTACTProcesses;

   InitWindows() ;
   IF NOT InitialTranslationData() THEN HALT END;

   InitVirtMem ;  (* also does a  SetupMemoryManagement() *)

   WITH BaseWindowInfo DO
      XPos := 1;
      YPos := 2;
      XSize := 80;
      YSize := 23;
      MxYSize := 25;
      Type := Active;
      AllowMove := FALSE;
      AllowResize := FALSE;
   END;

   (* SetupDefaultKeyUtilSettings ;  makes ref to TDB/PDB Name before set *LP* *)

   PushHelpItem(0); (* base help item *)
   PushNewWindow(BaseWindowInfo, BaseWindow, DummyInit);
   InitializeDBs(BaseWindow) ;
   TerminationProc := TerminateAll;  (* reset to reflect need to close
                                        Personal Database now *)

   SetupDefaultKeyUtilSettings ;  (* move here  *LP* *)

   DoTACTWork(BaseWindow);

   TerminateAll;
END UseBase .
