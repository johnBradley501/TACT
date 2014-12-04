MODULE TACTStatistics ;

(* copyright (c) 1989,96 Ian Lancashire, Lidio Presutti, University of Toronto *)

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

IMPORT PCKey ;
IMPORT IO, ASCII, TWB;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny, FileNameType,
  (* Proc  *) CheckResVersion, CheckParam;
FROM KeyTranslation IMPORT InitialTranslationData ;
FROM Str IMPORT Compare, Concat ;
FROM Utils IMPORT
  (* Vars  *) StandardSearchList,
  (* Procs *) FindFileInList, GetEnv, Terminate, Status, InstallTermProc ;
FROM Windows  IMPORT
  (* Vars  *) TerminationProc,
  (* Procs *) InitWindows, NonWMMessage, EndWindows ;
FROM ResBase IMPORT
  (* Procs *) OpenResourceFile, CloseResourceFile ;
FROM UsenhKBD IMPORT
  (* Procs *) RestoreKbdVectors, SetKbdVectors, UserRequestedStdKBD;
FROM ResMessages IMPORT
   (* proc *) GetResMessage, PutResMessage, ResAskUser ;
FROM KeyBase IMPORT Read, KeyPressed, GetKeyStrokeType, GetKeyStroke;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, ShowHelpItem, ShowCredit;

(* local modules [ie. in current directory] *)
FROM StartUp IMPORT
  (* proc *) DoStartUp;
FROM RUNSource IMPORT Run ;

(*<Debug*) IMPORT Storage ; (*Debug>*)

VAR
   EnhancedKbd : BOOLEAN;
   TermList    : ARRAY[0..1] OF CHAR;
   ExitList    : ARRAY[0..0] OF CHAR;
   MsgStr      : StrAny ;

PROCEDURE TerminateAll;
   VAR
     	ch   : CHAR ;
	oldw : TWB.WinType;
   BEGIN
        (*RES OLD CHE 43
        Do you wish to stop TACTStat immediately?  Y)es or N)o.
        =YN
        *)
	oldw := TWB.Used();
	ResAskUser( (*RES REM INS*) 43  , 'YN', ch);
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
    oldw:     TWB.WinType;
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
            ShowCredit( 72, TermList, ExitList, ch, Ext) ;
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
   TermList[0] := ASCII.rs;
   TermList[1] := ASCII.esc;
   ExitList := 0C;

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
      NonWMMessage( 'Unable to open file "TACT.RES".' ) ;
      Terminate( Normal ) ;  (* no dumps *)
   END ;

   CheckResVersion;

   (*RES OLD MSG 573
   tactstat -b [-c d | p] <input .TDB filename> <output .STA filename>
   *)
   CheckParam( (*RES REM INS*) 573 ) ;
   InitWindows() ;
   IF NOT InitialTranslationData() THEN HALT END;

   PushHelpItem( 58 ); (* Help Res 58 is TACTStatistics's single help item *)
END InitializeThings;


BEGIN
   TerminationProc := TerminateAll;  (* must be first thing done! *)
   (*<Debug
   Storage.ClearOnAllocate := TRUE ;  (* does both ALLOCATE & DEALLOCATE *)
   Debug>*)

   MsgStr[0] := 0C ;

   InitializeThings;

   IF DoStartUp() THEN Run(MsgStr) END;

   CloseResourceFile ;

   EndWindows ;

   IF MsgStr[0] <> 0C THEN
      IO.WrStr( MsgStr ) ;
      IO.WrLn ;
   END ;

END TACTStatistics .

