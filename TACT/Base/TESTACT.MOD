MODULE TestAct ;

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

IMPORT BitOps, Handles ;
IMPORT HyperDataModel;
IMPORT WordBase ;
IMPORT ResNumberArray;
IMPORT KeyTranslation ;
IMPORT GetSequences ;
IMPORT GetParams ;
IMPORT DiskDirectory ;

FROM ResActionBar IMPORT
  (* type *) BarID,
  (* proc *) BuildActionBar, DiscardActionBar, ShowActionBar, DoActionBar;
IMPORT ASCII, Str ;
IMPORT TWB;
IMPORT PCKey ;
FROM ResBase IMPORT
  (* Procs *) OpenResourceFile, CloseResourceFile ;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny, FileNameType, SystemVersionDate, CheckResVersion ;
FROM Windows IMPORT
  (* Vars  *) TerminationProc,
   (* Vars *)  DialogAttrib, ErrorAttrib, InActiveAttrib, ActiveAttrib,
   (* Const *) RegularAttr, BoldAttr, SpecialAttr,
   (* Procs *) InitWindows, CreateNewWindow, GetRidOfWindow, NonWMMessage,
               ReSizeWindow, MoveWindow, ScrollUp, ScrollDown;

FROM ResMessages IMPORT
   (*proc*)  MsgString, PutResError;
FROM StringIO IMPORT SWriteString,SWriteChar,SWriteCard;
FROM KeyTranslation IMPORT InitialTranslationData, WriteScreenField,
       GetScreenField, DumpKeyData;
FROM Utils    IMPORT Beep,WriteLine,PrintCode,PrintHex1,PrintHex2,
  (* Types *) BResultType,
  (* Vars  *) StandardSearchList,
  (* Procs *) GetEnv, FindFileInList, Terminate, Status, InstallTermProc  ;
FROM UsenhKBD IMPORT
  (* Procs *) RestoreKbdVectors, SetKbdVectors, UserRequestedStdKBD;
FROM KeyBase IMPORT ReadKey, KeyPressed, GetKeyStrokeType, GetKeyStroke;
FROM ResMenus IMPORT
  (* type   *) MenuID,
  (* proc   *) StartMenu, CharField, MakeMenu, DestroyMenu, GetFieldInfo,
               ShowFixedText, ShowMenu, DoMenu;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo, WindowInfoPtr,
  (* procs *) PushNewWindow, DummyInit,ResizeCurrentWindow,
              MoveCurrentWindow;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, ReplaceHelpItem, PopHelpItem, ShowHelpItem;

VAR
   DirName        : FileNameType ;
   FullResName    : FileNameType ;
   OpenResult     : BResultType ;
   BaseWindow     : TWB.WinType;
   BaseWindowInfo : WindowInfo;
   EnhancedKbd	   : BOOLEAN ;
   RtdStr	        : StrAny ;
   MainBar        : BarID;
   PopupIDList    : ARRAY[0..6] OF CARDINAL;
   ch,ch1,ch2: CHAR; 
   fk: BOOLEAN;

PROCEDURE StartingTerminateAll;
   BEGIN
      IF EnhancedKbd THEN
	 RestoreKbdVectors ;
      END ;
      Terminate(Normal)
   END StartingTerminateAll;

PROCEDURE ReadTheKeyStrokes(VAR ch: CHAR; VAR Ext: BOOLEAN);
VAR Done:   BOOLEAN;
    DoRead: BOOLEAN;
BEGIN
   Done := FALSE;
   DoRead := TRUE;
   REPEAT
      IF DoRead THEN
	 ReadKey( ch, Ext ) ;
(*
         Read(ch);
         IF (ch = 0C) AND KeyPressed() THEN
            Ext := TRUE;
            Read(ch)
         ELSE Ext := FALSE END;
*)
      END;
      IF Ext THEN
         CASE ch OF
           PCKey.F10: TerminationProc
         | PCKey.F1:  DoRead := ShowHelpItem(ASCII.rs,0C,ch,Ext)
         | PCKey.F5:  DoRead := NOT ResizeCurrentWindow(Ext,ch)
         | PCKey.CtrlF5: DoRead := NOT MoveCurrentWindow(Ext,ch)
         ELSE Done := TRUE END;
      ELSE
         Ext := FALSE;
         Done := TRUE;
      END;
   UNTIL Done;
END ReadTheKeyStrokes;

(*
PROCEDURE TerminateAll;
VAR ErrMsg:   StrAny;
   BEGIN
      WriteAll(PDBFile);
      IF NOT CloseHyperFile(PDBFile, ErrMsg) THEN
         (*RES OLD MSG 136
         Problem closing Personal Database: %0
         *)
         MsgString(ErrMsg, 0);
         PutResError( (*RES REM INS*) 136 );
      END;
      rc := WM.TerminateWM();
      IF EnhancedKbd THEN
	 RestoreKbdVectors ;
      END ;
      Terminate(Normal)
   END TerminateAll;
*)

BEGIN
   TerminationProc := StartingTerminateAll;  (* must be first thing done! *)

   EnhancedKbd := NOT UserRequestedStdKBD();
   IF EnhancedKbd THEN
      SetKbdVectors ;  (* use enhanced Keyboard BIOS patch *)
   END ;

   
   GetKeyStroke := ReadTheKeyStrokes;

   GetEnv( 'PATH', StandardSearchList ) ;

   IF NOT FindFileInList( StandardSearchList, 'TACT.RES', DirName ) THEN
      NonWMMessage( 'File "TACT.RES" could not be found.' ) ;
   END ;
   Str.Concat(  FullResName, DirName, 'TACT.RES' ) ;
   IF NOT OpenResourceFile( FullResName, OpenResult ) THEN
      NonWMMessage( 'Unable to open file "TACT.RES".' ) ;
   END ;

   CheckResVersion;
(* BeginTACTProcesses; *)

   InitWindows() ;
   IF NOT InitialTranslationData() THEN
      HALT
   END;

   WITH BaseWindowInfo DO
      XPos := 1;
      YPos := 2;
      XSize := 80;
      YSize := 22;
      MxYSize := 25;
      Type := Active;
      AllowMove := FALSE;
      AllowResize := FALSE;
   END;

PutResError( 67 ) ;

   PushHelpItem(0);
   PushNewWindow(BaseWindowInfo, BaseWindow, DummyInit);

(*
   InitializeDBs(BaseWindow) ;
   TerminationProc := TerminateAll;  (* reset to reflect need to close
                                        Personal Database now *)

   DoTACTWork(BaseWindow);
*)
   PopupIDList[0] := 0;
   PopupIDList[1] := 0;
   PopupIDList[2] := 9;
   PopupIDList[3] := 10;
   PopupIDList[4] := 11;
   PopupIDList[5] := 12;
   PopupIDList[6] := 13;
   BuildActionBar(MainBar, (*RES REM INS*) 8, PopupIDList);
   ShowActionBar(MainBar);

   LOOP
      ReadTheKeyStrokes(ch, fk);
      IF (NOT fk) AND (ch = ASCII.rs) THEN
         fk := DoActionBar(MainBar, 0C, 0C,ch,fk,ch1,ch2);
      ELSE
         Beep
      END;
   END;
   StartingTerminateAll;
END TestAct .
