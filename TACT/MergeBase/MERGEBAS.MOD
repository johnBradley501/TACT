MODULE MergeBas ;

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

IMPORT PCKey ;
IMPORT ASCII, TWB, Lib, Str, IO ;
FROM GlobalDefs IMPORT
  (* Type  *) StrAny, FileNameType,
  (* Procs *) CheckResVersion, CheckParam ;
FROM KeyTranslation IMPORT InitialTranslationData ;
FROM StartUp IMPORT
  (* proc *) DoStartUp;
FROM RUNSource IMPORT Run ;
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

VAR
   EnhancedKbd : BOOLEAN;
   TermList    : ARRAY[0..1] OF CHAR;
   ExitList    : ARRAY[0..0] OF CHAR;
   BaseWind    : TWB.WinType;

PROCEDURE TerminateAll;
  VAR
	ch   : CHAR ;
	oldw : TWB.WinType;

   BEGIN
      (*RES REM DEL MSG 94
      MergeBas has stopped, due to your request.
      *)
(* m.s. provide choice below     PutResMessage( (*RES REM INS*) 94 ); *)
	(*RES OLD CHE 33
	=Y N
	Do you wish to stop {B}MergeBas{N} immediately? Y)es or N)o.
	*)
	oldw := TWB.Used();
	ResAskUser( (*RES REM INS*) 33, 'YN', ch);
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
    oldw:   TWB.WinType ;
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
            ShowCredit( 69, TermList, ExitList, ch, Ext ) ;
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
   Str.Concat( FullResName, DirName, 'TACT.RES' ) ;
   IF NOT OpenResourceFile( FullResName, OpenResult ) THEN
      NonWMMessage( 'Unable to open file "TACT.RES".' ) ;
      Terminate( Normal ) ;  (* no dumps *)
   END ;

   CheckResVersion ;

   (*RES OLD MSG 576
   mergebas -b -f <TACTID> -o <output .TDB filename> -r "<template>"
   -t "<title>" <input .TDB filename> <input .TDB filename>
   <input .TDB filename> <input .TDB filename>
   *)
   CheckParam( (*RES REM INS*) 576 ) ;

   InitWindows() ;
   IF NOT InitialTranslationData() THEN HALT END;

   PushHelpItem(30); (* Help Res 30 is MERGEBAS's single help item *)
END InitializeThings;

BEGIN
   Lib.SetReturnCode( 99 ) ;	(* assume we are going to fail *)
   TerminationProc := TerminateAll;  (* must be first thing done! *)

   InitializeThings;
   IF DoStartUp(BaseWind) THEN
	Run(BaseWind) ;
	Lib.SetReturnCode( 0 ) ;	(* if got this far, then OK *)
   END;

   CloseResourceFile ;

   EndWindows ;

   IO.WrStr('MergeBas completed successfully.') ;
   IO.WrLn ;

END MergeBas .

