MODULE FCompare;

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

IMPORT FIO, Str, Utils, TWB, PCKey, ASCII, IO ;
FROM SYSTEM IMPORT TSIZE ;
FROM Str IMPORT Copy, Compare  ;
FROM GetParams IMPORT
  (* types *) GetParametersStatus, ParameterResult, ParameterData,
  (* procs *) LegalParameter, GetParameters, InitialParams;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM GlobalDefs IMPORT StrAny, TDBExtension, CheckResVersion, CheckParam,
     SystemVersion, SystemVersionDate;
FROM HyperDataModel IMPORT
   IDType, TDBIDModel, PDBIDModel;
FROM Utils IMPORT GetEnv, StandardSearchList, FindFileInList, StandardizeFileName,
     ParseFilename, MakeFilename, Terminate, Status, TrimBlanks, RemoveExtension,
     WriteLine, BFile, BOpen, BClose, ReadLine, WriteLine, RWType, UpcaseStr ;
FROM DiskDirectory IMPORT
  (* Procs *)  CurrentDrive, SelectDrive, CurrentDirectory, ChangeDirectory,
               ChangeTDADirectory ;
FROM UtilsTwo IMPORT IOErrorMessage ;
FROM ResBase IMPORT
  (* Procs *) OpenResourceFile, CloseResourceFile ;
FROM KeyBase IMPORT Read, KeyPressed, GetKeyStrokeType, GetKeyStroke;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM Windows  IMPORT
  (* const *) RegularAttr,
  (* Vars  *) TerminationProc,
  (* Procs *) InitWindows, NonWMMessage, EndWindows ;
FROM KeyTranslation IMPORT InitialTranslationData, WriteScreenField, FILEText;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo, WindowInfoPtr,
  (* procs *) PushNewWindow, DummyInit;
FROM ResMenus IMPORT
  (* type   *) MenuID,
  (* proc   *) StartMenu, CharField, MakeMenu, DestroyMenu, GetFieldInfo, DoMenu, CardField,
               ShowFixedText, ShowMenu, Switches, SwitchValue, CharFieldProc, ClearMenuArea;
FROM ResMessages IMPORT
  (* proc *)  MsgString, MsgCard, PutResError, PutResMessage, PutResWarning,
              GetResMessage, ResAskUser;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) NextColItem,ReleaseCollection;
FROM Translations IMPORT
 (* type *) XFileType, CurrentModeType,
 (* var  *) Int2Scr, Scr2Int, File2Int, LenD,
 (* proc *) XOpenInput, XAppend, XOpenOutput, XClose, XReadLine,
            XWriteLine, XWrStr, XWrLn, XlateLine;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, ShowHelpItem, ShowCredit;
FROM AlphaPanel IMPORT AlphaInfo, NoAlphaLines, NoRetDiLines, NoNonDiLines;
FROM SpecialCharacters IMPORT
  (* vars   *) SCList,
  (* procs  *) MakeSCMenus, DestroySCMenus, InitSCList,
               ShowSCMenu, GetSCMenu, ShowSCTitleMenu,
               NewSCData, DeleteSCData, DeleteSCList, IsSCDataEmpty;
FROM StructuralInfo IMPORT
  (* vars   *) StructList,
  (* type   *) StructInfoType, StructInfoDataType, StructInfoDataPntr,
  (* procs  *) MakeStructMenus, DestroyStructMenus, DeleteStructList,
               ShowStructMenu, GetStructMenu, ShowStructTitleMenu, InitStructList,
               NewStructData, DeleteStructData, IsStructDataEmpty;
FROM XlatUserInput IMPORT BuildAlphabetXlate, InitXlateLists ;
FROM SetupFile IMPORT VerifySetupFile ;
FROM WordBase IMPORT SortToIntWord, IntToSortWord, FullToSortWord ;
FROM SortLine IMPORT IntToSimpleSortLine, IntToSortLine, IntToSimpleWord ;
FROM LongSort IMPORT
  (* Procs *) LTurboSort, LSortRelease, LSortReturn, LSortEOS, LSortReset,
              LSortGetPos, SpaceReserved ;
FROM PrintModule IMPORT PrintMaster, PrintProcType, PrintActionType,
		AbortProc, AbortForFileIO, WriteWithTabs;


CONST
   CopyWYPos    = 17;
   CopyWXPos    = 12;  (* was 20 *)
   (*RES OLD MSG 562
   File name "%0" does not exist.
   *)
   FileProblemMessage = (*RES REM INS*) 562  ;
   YPosForStatusMenu = 22;  (* m.s. - was 19 *)
(*   FirstTempName = 'TEMP1.FCO';
   SecondTempName = 'TEMP2.FCO';
*)
(*RES OLD MNU 63
 Status: %0_________________________________________________________________
 *)

   StatusMenuResID = (*RES REM INS*) 63 ;

   FileHeaderResource = 113 ;	(* >> MSG defined in MAKBAS: SetupFil.MOD << *)

TYPE
   FileData = RECORD
      FirstInputName:  ARRAY[0..64] OF CHAR;
      SecondInputName:  ARRAY[0..64] OF CHAR;
      MergeName:  ARRAY[0..64] OF CHAR;
      FirstOutputName:  ARRAY[0..64] OF CHAR;
      SecondOutputName:  ARRAY[0..64] OF CHAR;
      FieldNum: CARDINAL ;
      MKSfileName: ARRAY[0..64] OF CHAR ;
   END;

   ConvertProc = PROCEDURE( ARRAY OF CHAR , VAR ARRAY OF CHAR ) ;

VAR
   Convert : ConvertProc ;
   InputFileName, OutFileName : StrAny ;
   FirstID:      BFile;
   SecondID:      BFile;
   MergeID:      BFile;
   FirstOutID:      BFile;
   SecondOutID:      BFile;
   Base:        FileData;
   BatchMode, dummy:       BOOLEAN;
   BaseWPtr:    TWB.WinType;
   StatsWind: TWB.WinType ;
   LenStatus, IOResult, IOresult:    CARDINAL;
   OldTempDiskArea : ARRAY [0..64] OF CHAR ;
   Count : CARDINAL ;
   KeyTerm:   ARRAY[0..0] OF CHAR; (* m.s. *)
   FunctTerm: ARRAY[0..0] OF CHAR; (* m.s. *)
   TermList    : ARRAY[0..1] OF CHAR;
   ExitList    : ARRAY[0..0] OF CHAR;
   Result, FunctKey, ReDisplay, ReEdit, DoMenuNow, Done : BOOLEAN ;
   TC : CHAR ;
   MenuItem, PosXStatus, PosYStatus : CARDINAL ;
   ErrorMsg, MsgTxt : StrAny ;
   FilePath, drive, path : StrAny ;
   OverWriteOut : BOOLEAN ;
   Result1, Result2 : CARDINAL ;
   cm : CurrentModeType ;


PROCEDURE PutRunStatus( ResID : CARDINAL );
   BEGIN
	GetResMessage(ResID,MsgTxt);
	WriteScreenField( StatsWind, LenStatus, PosXStatus,
			PosYStatus, MsgTxt, RegularAttr, TRUE ) ;
   END PutRunStatus;

PROCEDURE StandardizeFileNames(VAR Fname:  ARRAY OF CHAR;
                                  pext:   ARRAY OF CHAR;
                                  Reppext:BOOLEAN);
VAR
   drive:       ARRAY[0..5] OF CHAR;
   path:        ARRAY[0..100] OF CHAR;
   name:        ARRAY[0..8] OF CHAR;
   ext:         ARRAY[0..3] OF CHAR;

BEGIN
   Str.Caps(Fname);
   IF NOT ParseFilename(Fname,drive,path,name,ext) THEN
        (*RES OLD MSG 501
        Parameter "%0" is not a legal file name.
        *)
        MsgString( name, 0 );
        PutResError((*RES REM INS*) 501 ) ;
        HALT;
   END;
   IF Reppext OR (ext[0] = 0C) THEN Str.Copy(ext,pext) END;
   MakeFilename(drive,path,name,ext,Fname);
END StandardizeFileNames;


PROCEDURE VerifyOutputFileNames( VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
VAR
   Ch : CHAR ;
BEGIN
   ReDisplay := TRUE;
   TrimBlanks(Base.MergeName,Base.MergeName);
   Str.Caps( Base.MergeName ) ;
   TrimBlanks(Base.FirstOutputName,Base.FirstOutputName);
   Str.Caps( Base.FirstOutputName ) ;
   TrimBlanks(Base.SecondOutputName,Base.SecondOutputName);
   Str.Caps( Base.SecondOutputName ) ;
   IF Base.MergeName[0] = 0C THEN
         (*RES OLD MSG 557
         Please provide Output File Names.
         *)
         PutResError( (*RES REM INS*) 557 ) ;
         ReEdit := TRUE;
         MenuItem := 3 ;
   ELSIF Base.FirstOutputName[0] = 0C THEN
         PutResError( (*RES REM INS*) 557 ) ;
         ReEdit := TRUE;
         MenuItem := 4 ;
   ELSIF Base.SecondOutputName[0] = 0C THEN
         PutResError( (*RES REM INS*) 557 ) ;
         ReEdit := TRUE;
         MenuItem := 5 ;
   ELSIF FIO.Exists(Base.MergeName) OR FIO.Exists(Base.FirstOutputName) OR
         FIO.Exists(Base.SecondOutputName) AND NOT OverWriteOut THEN
	 (*RES OLD CHE 51
	 At least one output filename is already in use. Please choose
	 between N)ew names and O)verwrite files:
	 = N O
	 *)
	 ResAskUser( (*RES REM INS *) 51 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	 ELSE
	    OverWriteOut := FALSE ;
	    MenuItem  := 3 ;
	    ReEdit := TRUE ;
	 END ;
      END;
END VerifyOutputFileNames;

PROCEDURE VerifyFirstOutputFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO FileData;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
   Ch : CHAR ;
BEGIN
   ReDisplay := TRUE;
   DataP := DPtr(Data);
   ReEdit := FALSE ;
   WITH DataP^ DO
      TrimBlanks(Base.FirstOutputName,Base.FirstOutputName);
      IF Base.FirstOutputName[0] = 0C THEN
         PutResError( 557 ) ;
         ReEdit := TRUE;
         MenuItem := 4 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(Base.FirstOutputName, 'FCP')) THEN
         MsgString( Base.FirstOutputName, 0 );
         Str.Copy( TempStr, ' FCP ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 4 ;
         RETURN
     ELSIF FIO.Exists(Base.FirstOutputName) THEN
	 (*RES OLD CHE 51
	 At least one output filename is already in use. Please choose
	 between N)ew names and O)verwrite files:
	 = N O
	 *)
	 ResAskUser( (*RES REM INS *) 51 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	 ELSE
	    OverWriteOut := FALSE ;
	    MenuItem  := 4 ;
	    ReEdit := TRUE ;
	 END ;
      END;
   END ;
END VerifyFirstOutputFileName;

PROCEDURE VerifySecondOutputFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO FileData;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
   Ch : CHAR ;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE ;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(Base.SecondOutputName,Base.SecondOutputName);
      IF Base.SecondOutputName[0] = 0C THEN
         PutResError( 557 ) ;
         ReEdit := TRUE;
         MenuItem := 4 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(Base.SecondOutputName, 'FCP')) THEN
         MsgString( Base.SecondOutputName, 0 );
         Str.Copy( TempStr, ' FCP ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 4 ;
         RETURN
     ELSIF FIO.Exists(Base.SecondOutputName) THEN
	 (*RES OLD CHE 51
	 At least one output filename is already in use. Please choose
	 between N)ew names and O)verwrite files:
	 = N O
	 *)
	 ResAskUser( (*RES REM INS *) 51 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	 ELSE
	    OverWriteOut := FALSE ;
	    MenuItem  := 4 ;
	    ReEdit := TRUE ;
	 END ;
      END;
    END ;
END VerifySecondOutputFileName;

PROCEDURE VerifyMergeFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO FileData;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
   Ch : CHAR ;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE ;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(Base.MergeName,Base.MergeName);
      IF Base.MergeName[0] = 0C THEN
        MakeFilename(drive,path,'FSHARED','FCP', Base.MergeName );
        ReEdit := TRUE ;
      END ;
      IF ( NOT StandardizeFileName(Base.MergeName, 'FCP')) THEN
         MsgString( Base.MergeName, 0 );
         Str.Copy( TempStr, ' FCP ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 4 ;
         RETURN
     ELSIF FIO.Exists(Base.MergeName) THEN
	 (*RES OLD CHE 55
	 File "%0" already exists. Please choose
	 between N)ew name and O)verwrite file:
	 = N O
	 *)
	 MsgString( Base.MergeName, 0 ) ;
	 ResAskUser( (*RES REM INS *) 55 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	 ELSE
	    OverWriteOut := FALSE ;
	    MenuItem  := 4 ;
	    ReEdit := TRUE ;
	 END ;
      END;
   END ;
END VerifyMergeFileName;


PROCEDURE VerifyMKSFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO FileData;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
   Ch : CHAR ;
BEGIN
   ReDisplay := TRUE;
   DataP := DPtr(Data);
   ReEdit := FALSE ;
   WITH DataP^ DO
      TrimBlanks(Base.MKSfileName,Base.MKSfileName);
      IF Base.MKSfileName[0] = 0C THEN
         (*RES OLD MSG 484
         Please give a .MKS File Name.
         *)
         PutResError( (*RES REM INS*) 484 ) ;
         ReEdit := TRUE;
         MenuItem := 7 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(Base.MKSfileName, 'MKS')) THEN
         MsgString( Base.MKSfileName, 0 );
         Str.Copy( TempStr, ' MKS ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 7 ;
         RETURN
      END;
      IF (NOT FIO.Exists(Base.MKSfileName)) AND
         (Str.Compare( Base.MKSfileName, 'DEFAULT.MKS') <> 0) THEN
         (*RES OLD MSG 485
         "%0" not found. Will use DEFAULT.MKS instead.
         *)
         MsgString( Base.MKSfileName, 0 ) ;
         PutResWarning( (*RES REM INS*) 485 ) ;
         Str.Copy( Base.MKSfileName, 'DEFAULT.MKS' ) ;
      END;
   END;
END VerifyMKSFileName;

PROCEDURE VerifyFirstInputFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO FileData;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReDisplay := TRUE;
   DataP := DPtr(Data);
   ReEdit := FALSE ;
   WITH DataP^ DO
      TrimBlanks(Base.FirstInputName,Base.FirstInputName);
      IF Base.FirstInputName[0] = 0C THEN
         PutResError( 558 ) ;
         ReEdit := TRUE;
         MenuItem := 1 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(Base.FirstInputName, 'TXT')) THEN
         MsgString( Base.FirstInputName, 0 );
         Str.Copy( TempStr, ' TXT ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 1 ;
         RETURN
      END;
      IF (NOT FIO.Exists(Base.FirstInputName)) THEN
         (*RES OLD MSG 569
         Input File "%0" not found.
         *)
         MsgString( Base.FirstInputName, 0 ) ;
         PutResError( (*RES REM INS*) 569 ) ;
         ReEdit := TRUE ;
         MenuItem := 1 ;
         RETURN ;
      END;
      IF Base.FirstOutputName[0] = 0C THEN
        RemoveExtension( Base.FirstInputName, Base.FirstOutputName ) ;
        MakeFilename(drive,path,Base.FirstOutputName,'FCP', Base.FirstOutputName );
      END ;
   END;
END VerifyFirstInputFileName;

PROCEDURE VerifySecondInputFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO FileData;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReEdit := FALSE ;
   ReDisplay := TRUE;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(Base.SecondInputName,Base.SecondInputName);
      IF Base.SecondInputName[0] = 0C THEN
         PutResError( 558 ) ;
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(Base.SecondInputName, 'TXT')) THEN
         MsgString( Base.SecondInputName, 0 );
         Str.Copy( TempStr, ' TXT ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN
      END;
      IF (NOT FIO.Exists(Base.SecondInputName)) THEN
         (*RES OLD MSG 570
         Input File "%0" not found.
         *)
         MsgString( Base.SecondInputName, 0 ) ;
         PutResError( (*RES REM INS*) 570 ) ;
         ReEdit := TRUE ;
         MenuItem := 2 ;
         RETURN ;
      END;
      IF Base.SecondOutputName[0] = 0C THEN
        RemoveExtension( Base.SecondInputName, Base.SecondOutputName ) ;
        MakeFilename(drive,path,Base.SecondOutputName,'FCP', Base.SecondOutputName );
      END ;
   END;
END VerifySecondInputFileName;



PROCEDURE VerifyInputFileNames( VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO FileData;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReDisplay := TRUE ;
      TrimBlanks(Base.FirstInputName,Base.FirstInputName);
      Str.Caps( Base.FirstInputName ) ;
      TrimBlanks(Base.SecondInputName,Base.SecondInputName);
      Str.Caps( Base.SecondInputName ) ;
      TrimBlanks(Base.MergeName,Base.MergeName);
      Str.Caps( Base.MergeName ) ;
      TrimBlanks(Base.SecondOutputName,Base.SecondOutputName);
      Str.Caps( Base.SecondOutputName ) ;
      TrimBlanks(Base.FirstOutputName,Base.FirstOutputName);
      Str.Caps( Base.FirstOutputName ) ;
      IF Base.FirstInputName[0] = 0C THEN
         (*RES OLD MSG 558
         Please provide Input File Names.
         *)
         PutResError( (*RES REM INS*) 558 ) ;
         ReEdit := TRUE;
         MenuItem := 1 ;
         RETURN ;
      ELSIF Base.SecondInputName[0] = 0C THEN
         PutResError( (*RES REM INS*) 558 ) ;
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN ;
      END;
      IF Base.MergeName[0] = 0C THEN
        MakeFilename(drive,path,'FSHARED','FCP', Base.MergeName );
        ReEdit := TRUE ;
      END ;
      IF Base.FirstOutputName[0] = 0C THEN
        RemoveExtension( Base.FirstInputName, Base.FirstOutputName ) ;
        MakeFilename(drive,path,Base.FirstOutputName,'FCP', Base.FirstOutputName );
        ReEdit := TRUE ;
      END ;
      IF Base.SecondOutputName[0] = 0C THEN
        RemoveExtension( Base.SecondInputName, Base.SecondOutputName ) ;
        MakeFilename(drive,path,Base.SecondOutputName,'FCP', Base.SecondOutputName );
        ReEdit := TRUE ;
      END ;
      IF Base.MKSfileName[0] = 0C THEN
           RemoveExtension( Base.FirstInputName, Base.MKSfileName ) ;
           VerifyMKSFileName( ADR(Base), ReDisplay, ReEdit ) ;
      END ;

END VerifyInputFileNames;


PROCEDURE ProcessParams;

VAR plst,temp:  ParameterResult;
   str:         ARRAY[0..255] OF CHAR;
   i:           CARDINAL;
   m:           ARRAY [0..40] OF CHAR;
BEGIN
   InitialParams;
   LegalParameter('b',FALSE);
   LegalParameter('n',TRUE);
   LegalParameter('s',TRUE);
   i := 0;
   CASE GetParameters(plst,str) OF
      GPSOk: (* do nothing right now *)
   | GPSBadParameter:
        (*RES OLD MSG 559
        You cannot specify parameter "%0" for FCompare.
        *)
        MsgString(str,0);
        PutResError( (*RES REM INS*) 559 );
        HALT;
   | GPSMissingValue:
        (*RES OLD MSG
        Parameter "%0" requires a parameter for FCompare.
        *)
        MsgString(str,0);
        PutResError( (*RES REM INS*) 559 );
        HALT;
   END;
   WHILE plst <> NIL DO
      WITH plst^ DO
         CASE Code OF
          | 'B':
               BatchMode := TRUE ;
          | 'N' :
               Base.FieldNum := CARDINAL( Str.StrToCard( Strg, 10, dummy )) ;
          | 'S' :
               Str.Copy(Base.MKSfileName, Strg);
               VerifyMKSFileName( ADR(Base), ReDisplay, ReEdit ) ;
               IF ReEdit THEN
                 RETURN ;
               END ;
          | ' ':
               CASE i OF
                 0: Str.Copy(Base.FirstInputName, Strg);
               | 1: Str.Copy(Base.SecondInputName,Strg);
               | 2: Str.Copy(Base.MergeName,Strg);
               | 3: Str.Copy(Base.FirstOutputName,Strg);
               | 4: Str.Copy(Base.SecondOutputName,Strg);
               END;
               INC(i);
         ELSE
            ProgramErrorAndHalt('Unexpected ParameterData Code found');
         END;
      END;
      temp := plst^.Next;
      DEALLOCATE(plst,plst^.Size);
      plst := temp;
   END;
   IF Base.FirstInputName[0] <> 0C THEN
      VerifyInputFileNames( ReDisplay, ReEdit ) ;
   END ;
END ProcessParams;

PROCEDURE InitTables;
      VAR
         ResC       : ResCollectionType;
         i          : CARDINAL;
         dummy      : BOOLEAN;

(*RES OLD DTA 6
   'a b c d e f g h i j k l m n o p q r s t u v w x y z'
   '0 1 2 3 4 5 6 7 8 9' !00 !00
   -!20!\Acute\!20!\Grave\!20!\Circumflex\!20!\Cedilla\!20!\Umlaut\!20!\Tilde\!20!"'"
   !00
   !00 !00
   !00
*)
      BEGIN
         GetDataArray( (*RES REM INS*) 6, ResC);

         WITH AlphaInfo DO
            FOR i := 1 TO NoAlphaLines DO
                dummy := GetNextDataArrayStringItem(ResC,AlphaString[i])
            END;
            FOR i := 1 TO NoRetDiLines DO
                dummy := GetNextDataArrayStringItem(ResC,RetDiacStr[i])
            END;
            FOR i := 1 TO NoNonDiLines DO
                dummy := GetNextDataArrayStringItem(ResC,NonDiacStr[i])
            END;
            dummy := GetNextDataArrayStringItem(ResC,ContinuationSeq);
         END;
         ReleaseCollection(ResC);

         InitSCList() ;
         InitStructList() ;

      END InitTables;

PROCEDURE TerminateAll;
  VAR
	ch   : CHAR ;
	oldw : TWB.WinType;

   BEGIN
	(*RES OLD CHE 52
	=Y N
	Do you wish to stop FCompare immediately? Y)es or N)o.
	*)
	oldw := TWB.Used();
	ResAskUser( (*RES REM INS*) 52 , 'YN', ch);
	TWB.Use(oldw);
	IF ch <> 'Y' THEN  RETURN  END ;
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
         ELSIF ch = PCKey.F6 THEN
            ShowCredit( 78, TermList, ExitList, ch, Ext ) ;
            Done := FALSE ;
         ELSIF ch = PCKey.F10 THEN TerminateAll END;
      ELSE
         Ext := FALSE;
      END;
   UNTIL Done;
END ReadTheKeyStrokes;

PROCEDURE ConvertLine( LI : ARRAY OF CHAR ; VAR LO: ARRAY OF CHAR ) ;

VAR
    al, ns : CARDINAL ;
BEGIN
      Str.ItemS( LI, LI, 11C, Base.FieldNum ) ;
      XlateLine( File2Int, 1C, LI, cm, al, LenD, ns, dummy, LO ) ;
      IntToSortLine( LO, LO ) ;
      IF LO[0] = 0C THEN (* if not part of alphabet i.e. punctuation etc.*)
         Copy( LO, LI ) ;
      END ;
END ConvertLine ;

PROCEDURE SortLine( LI : ARRAY OF CHAR ; VAR LO: ARRAY OF CHAR ) ;

VAR
    al, ns : CARDINAL ;
BEGIN
      XlateLine( File2Int, 1C, LI, cm, al, LenD, ns, dummy, LI ) ;
      IntToSortLine( LI, LO ) ;
END SortLine ;


PROCEDURE DoSetup;
(*RES OLD MNU 62

                  FCompare Version %7____ %8________________________


     First Input Filename: %0___________________________________________
     Second Input Filename: %1__________________________________________

     Intersection Output Filename:     %2_______________________________
     First Exclusive Output Filename:  %3_______________________________
     Second Exclusive Output Filename: %4_______________________________

     Field Number to Compare: %5_
     .MKS Filename: %6__________________________________________________




_____________________________________________________________________________
     F1: Help                             F9: RUN, creating output files
     F6: Credits                         F10: QUIT without doing anything
*)


CONST
   MainMenuRes = (*RES REM INS*) 62 ;
VAR
   FrontMenu: MenuID;
   BaseWind:  WindowInfo;
   VerLen,DatLen,
   VerX,DatX,
   VerY,DatY: CARDINAL;
   Work:      ARRAY[0..255] OF CHAR;
   drive, path, name, ext : ARRAY[0..25] OF CHAR ;
   TempStr : StrAny ;
   EnoughData: BOOLEAN ;

BEGIN

   WITH BaseWind DO
      XPos := 1;
      YPos := 1;
      XSize := 80;
      YSize := 25;
      MxYSize := 25;
      Type :=       Active;
      AllowMove :=  FALSE;
      AllowResize :=FALSE;
      IsTop :=      FALSE
   END;

   Base.FieldNum := 1 ;
   InitXlateLists() ;
   InitTables;
   Str.Copy( Base.MergeName, 'FSHARE.FCP') ;
   Str.Copy( Base.MKSfileName, 'DEFAULT.MKS')  ;
   Base.FirstInputName[0] := 0C ;
   Base.SecondInputName[0] := 0C ;
   Base.FirstOutputName[0] := 0C ;
   Base.SecondOutputName[0] := 0C ;
   StartMenu(Base);
   WITH Base DO
     CharFieldProc(FirstInputName, VerifyFirstInputFileName);
     CharFieldProc(SecondInputName, VerifySecondInputFileName);
     CharFieldProc(MergeName, VerifyMergeFileName);
     CharFieldProc(FirstOutputName, VerifyFirstOutputFileName);
     CharFieldProc(SecondOutputName, VerifyFirstOutputFileName);
     CardField(FieldNum) ;
     CharFieldProc(MKSfileName, VerifyMKSFileName);
   END;

   MakeMenu( MainMenuRes , FrontMenu);
   GetFieldInfo(FrontMenu,7,VerX,VerY,VerLen);
   GetFieldInfo(FrontMenu,8,DatX,DatY,DatLen);

   PushNewWindow(BaseWind, BaseWPtr, DummyInit);
   ShowFixedText(BaseWPtr,FrontMenu,0,0);
   WriteScreenField( BaseWPtr, VerLen, VerX, VerY,
                          SystemVersion, RegularAttr, TRUE );
   WriteScreenField( BaseWPtr, DatLen, DatX, DatY,
                          SystemVersionDate, RegularAttr, TRUE );
   TWB.GotoXY(0, 21);
   TWB.ClrEol;
   TWB.WrStr('              Copyright (c) 1995 TACT Group, University of Toronto');
   TWB.WrLn ;

   DoMenuNow := TRUE ;
   KeyTerm[0] := ASCII.rs ;
   FunctTerm[0] := PCKey.F9 ;
   BatchMode := FALSE ;
   ProcessParams;
   IF ReEdit OR NOT BatchMode THEN
    REPEAT
      ReEdit := FALSE ;
      ShowMenu(BaseWPtr,FrontMenu,0,0,Base);
      DoMenu(BaseWPtr,FrontMenu,0,0,KeyTerm, FunctTerm,
                      Base,MenuItem,TC,FunctKey);
    UNTIL ReEdit = FALSE ;
  END ;
  DestroyMenu(FrontMenu);

  BOpen( FirstID, Base.FirstInputName, ReadType, IOResult) ;
  IF IOResult <> 0  THEN
      IOErrorMessage( IOResult, ErrorMsg ) ;
      MsgString(Base.FirstInputName, 0);
      MsgString(ErrorMsg, 0);
      PutResError( FileProblemMessage );
      HALT;
   END;
   Convert := SortLine ;
   IF Base.FieldNum > 0 THEN
           DEC(Base.FieldNum) ; (* ItemS in 0 based *)
           dummy := ReadLine( FirstID, TempStr, EnoughData, IOResult ) ;
           Str.ItemS( TempStr, TempStr, 11C, Base.FieldNum ) ;
           IF TempStr[0] <> 0C THEN (* field exists, use ConvertLine *)
              Convert := ConvertLine ;
           END ;
   END ;
  BClose( FirstID, IOResult ) ;
  BOpen( FirstID, Base.FirstInputName, ReadType, IOResult) ;

  BOpen( SecondID, Base.SecondInputName, ReadType, IOResult) ;
  IF IOResult <> 0  THEN
      IOErrorMessage( IOResult, ErrorMsg ) ;
      MsgString(Base.SecondInputName, 0);
      MsgString(ErrorMsg, 0);
      PutResError( FileProblemMessage );
      HALT;
   END;
  BOpen( FirstOutID, Base.FirstOutputName, WriteType, IOResult) ;
  IF IOResult <> 0  THEN
      IOErrorMessage( IOResult, ErrorMsg ) ;
      MsgString(Base.FirstOutputName, 0);
      MsgString(ErrorMsg, 0);
      PutResError( FileProblemMessage );
      HALT;
   END;

  BOpen( SecondOutID, Base.SecondOutputName, WriteType, IOResult) ;
  IF IOResult <> 0  THEN
      IOErrorMessage( IOResult, ErrorMsg ) ;
      MsgString(Base.SecondOutputName, 0);
      MsgString(ErrorMsg, 0);
      PutResError( FileProblemMessage );
      HALT;
   END;
  BOpen( MergeID, Base.MergeName, WriteType, IOResult) ;
  IF IOResult <> 0  THEN
      IOErrorMessage( IOResult, ErrorMsg ) ;
      MsgString(Base.MergeName, 0);
      MsgString(ErrorMsg, 0);
      PutResError( FileProblemMessage );
      HALT;
   END;
   IF NOT VerifySetupFile( Base.MKSfileName ) THEN
    ProgramErrorAndHalt('Fatal error while processing .MKS file' ) ;
   ELSE
    IOResult:= BuildAlphabetXlate();
    IF IOResult <> 0 THEN
      ProgramErrorAndHalt(' Fatal error while building Alphabet translation.');
    END ;
   END ;
END DoSetup;


PROCEDURE BeginEverything;
VAR
   DirName:      ARRAY[0..60] OF CHAR;
   FullResName:  ARRAY[0..100] OF CHAR;
   OpenResult  : CARDINAL ;
BEGIN
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

   (*RES OLD MSG 560
   fcompare -b -n <field number> -s <.MKS filename> <first input filename>
   <second input filename> <intersection output filename> <first exclusive
   output filename> <second exclusive output filename>
   *)
   CheckParam( 560 ) ;


   InitWindows() ;
   IF NOT InitialTranslationData() THEN HALT END;
   PushHelpItem(65); (* Help Res 65 is FCompare's single help item *)
   TermList[0] := ASCII.rs;
   TermList[1] := ASCII.esc;
   ExitList := 0C;

END BeginEverything;


PROCEDURE Run ;

TYPE
      StatusType   = RECORD  (* m.s. *)
(*                Percent            : CARDINAL ;	 *)
                MsgText            : ARRAY [0..80] OF CHAR ;
              END ;
   CONST
	MAXCARDINAL = MAX(CARDINAL) ;
   VAR
	len, temp, Result3 : CARDINAL;
	MsgId : CARDINAL ;
	Drive : CHAR ;
	ch, BadChar    : CHAR ;
	AmountNeeded,
	AmountDiskFree : LONGCARD ;
	StatusMenu : MenuID;
	SortResult : CARDINAL ;
	Status : StatusType ;
	Prev1, Prev2, Line1, Line2, XLine1, XLine2, TempStr: StrAny ;
	OK : BOOLEAN ;
	x : INTEGER ;


   BEGIN
	Status.MsgText[0] := 0C ;

(*	Status.Percent := 0; *)
	StartMenu(Status);
	CharField( Status.MsgText );
(*	CardField( Status.Percent); *)
	MakeMenu( StatusMenuResID, StatusMenu);
	ClearMenuArea(BaseWPtr, 0, YPosForStatusMenu, StatusMenu);
	ShowFixedText(BaseWPtr, StatusMenu, 0, YPosForStatusMenu);
	ShowMenu(BaseWPtr, StatusMenu, 0, YPosForStatusMenu, Status);

	StatsWind := BaseWPtr ;

        GetFieldInfo( StatusMenu, 0, PosXStatus, PosYStatus, LenStatus ) ;
        INC( PosYStatus, YPosForStatusMenu ) ;
(*        GetFieldInfo( StatusMenu, 1, PosXPerCent, PosYPerCent, len ) ;
        INC( PosYPerCent, YPosForStatusMenu ) ;
*)
        (*RES OLD MSG 563
        Comparing files... Please Wait.
        *)
        PutRunStatus( (*RES REM INS*) 563) ;
        cm.ModeIn := '0' ; cm.ModeOut := '0' ;
        dummy := ReadLine( FirstID, Line1, OK, Result1 ) ;
        Convert( Line1, XLine1 ) ;
        IF Result1 <> 0 THEN
          ProgramErrorAndHalt('First input file empty.') ;
        END ;
        dummy := ReadLine( SecondID, Line2, OK, Result2 ) ;
        IF Result2 <> 0 THEN
          ProgramErrorAndHalt('Second input file empty.') ;
        END ;
        Convert( Line2, XLine2 ) ;
        Prev1[0] := 0C ;
        Prev2[0] := 0C ;
        WHILE (Result1 = 0) AND (Result2 = 0) DO
          x := Compare( XLine1, XLine2 ) ;
          IF x = 0 THEN
             WriteLine( MergeID, Line1, Result1 ) ;
             IF Compare( Line1, Line2 ) <> 0 THEN (* other fields not same *)
                WriteLine( MergeID,   Line2, Result1 ) ;
             END ;
             Copy( Prev1, Line1 ) ;
             REPEAT
               dummy := ReadLine( FirstID, Line1, OK, Result1 ) ;
             UNTIL (Result1 <> 0) OR (Compare( Line1, Prev1 ) <> 0) ;
             Convert( Line1, XLine1 ) ;
             Copy( Prev2, Line2 ) ;
             REPEAT
               dummy := ReadLine( SecondID, Line2, OK, Result2 ) ;
             UNTIL (Result2 <> 0) OR (Compare( Line2, Prev2 ) <> 0) ;
             Convert( Line2, XLine2 ) ;
          ELSIF x < 1 THEN
             WriteLine( FirstOutID, Line1, Result1 ) ;
             Copy( Prev1, Line1 ) ;
             REPEAT
                dummy := ReadLine( FirstID, Line1, OK, Result1 ) ;
             UNTIL (Result1 <> 0) OR (Compare( Line1, Prev1 ) <> 0) ;
             Convert( Line1, XLine1 ) ;
          ELSE
             WriteLine( SecondOutID, Line2, Result2 ) ;
             Copy( Prev2, Line2 ) ;
             REPEAT
               dummy := ReadLine( SecondID, Line2, OK, Result2 ) ;
             UNTIL (Result2 <> 0) OR (Compare( Line2, Prev2 ) <> 0) ;
             Convert( Line2, XLine2 ) ;
          END ;
       END ;
       IF Result1 = 0 THEN
             REPEAT
               IF Compare( Line1, Prev1) <> 0 THEN
                  WriteLine( FirstOutID, Line1, Result1 ) ;
                  Copy( Prev1, Line1 ) ;
               END ;
               dummy := ReadLine( FirstID, Line1, OK, Result3 ) ;
             UNTIL (Result1 <> 0) OR (Result3 <> 0);
       END ;
       IF (Result2 = 0) THEN
             REPEAT
               IF Compare( Line2, Prev2) <> 0 THEN
                  WriteLine( SecondOutID, Line2, Result2 ) ;
                  Copy( Prev2, Line2 ) ;
               END ;
               dummy := ReadLine( SecondID, Line2, OK, Result3 ) ;
             UNTIL (Result2 <> 0) OR (Result3 <> 0);
       END ;
       BClose( FirstID, Result1 ) ;
       BClose( SecondID, Result1 ) ;
       BClose( MergeID, Result1 ) ;
       BClose( FirstOutID, Result1 );
       BClose( SecondOutID, Result1 ) ;
(*       FIO.Erase( FirstTempName ) ;
       FIO.Erase( SecondTempName ) ;
*)
END Run ;
BEGIN

   GetKeyStroke := ReadTheKeyStrokes;

   BeginEverything  ;

   cm.ModeIn := '0' ;
   cm.ModeOut := '0' ;

   DoSetup;

   Run;

   EndWindows ;
   (*RES OLD MSG 561
   FCompare completed successfully.
   *)
   GetResMessage( 561 , MsgTxt ) ;
   IO.WrStr( MsgTxt ) ;
   IO.WrLn ;
END FCompare.
