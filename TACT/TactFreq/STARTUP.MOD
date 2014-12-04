IMPLEMENTATION MODULE StartUp ;

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

IMPORT (*FIO,*) TWB, ASCII, PCKey, Str, Lib;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM HyperDataModel IMPORT MaxDBTitleLength, IDType, TDBIDModel, HyperLength,
     ThisTDBVersion, HyperData;
FROM GlobalDefs IMPORT FileNameType, SystemVersion, SystemVersionDate ;
FROM SYSTEM IMPORT ADR;
FROM GetParams IMPORT
  (* types *) GetParametersStatus, ParameterResult, ParameterData,
  (* procs *) LegalParameter, GetParameters, InitialParams;
FROM Utils IMPORT
  (* vars   *) month, day, year,
  (* procs  *) RemoveExtension, StandardizeFileName, GetXlationType,
	       UpcaseStr, TrimBlanks, Exist ;
FROM UtilsTwo IMPORT IOErrorMessage;
FROM Windows  IMPORT
  (* Const  *) RegularAttr,
  (* Vars   *) DialogAttrib, InActiveAttrib, ActiveAttrib,
  (* Procs  *) GetRidOfWindow ;
FROM ErrorBase IMPORT
  (* Procs  *) ProgramErrorAndHalt;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo, WindowInfoPtr,
  (* procs *) PushNewWindow, DummyInit;
FROM KeyTranslation IMPORT
  (* Procs *) WriteScreenField, FILEText;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;
FROM Translations IMPORT
  (* Types *)  XFileType, CurrentModeType, XlateStrAny,
  (* vars  *)  Scr2Int, Int2Alp,
  (* Procs *)  XOpenOutput, XClose, XAppend, XlateLine, XWriteLine, XWrLn ;
FROM ResMenus IMPORT
  (* type   *) MenuID,
  (* proc   *) StartMenu, CharFieldProc, MakeMenu, DestroyMenu, GetFieldInfo,
		ShowFixedText, ShowMenu, DoMenu, CharField, CardField,
		Switches, SwitchValue;
FROM ResMessages IMPORT
  (* proc *)  MsgString, MsgCard, ResAskUser, PutResError, PutResWarning, PutResMessage;
FROM GlobalDefs IMPORT
  (* Type  *)  StrAny,
  (* Const *)  TDBExtension;
FROM WordBase IMPORT
  (* Type  *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar,
  (* Procs *) IntToSortWord, FullToSortWord;
FROM PrintModule IMPORT InitialPrintModule, TerminatePrintModule;
FROM DiskDirectory IMPORT
  (* Procs *)  CurrentDrive, SelectDrive, CurrentDirectory, ChangeDirectory,
               ChangeTDADirectory ;

FROM TDBInit IMPORT CheckTDBHeader, InitializeTDB;

(*RES UPD MNU 50

                         TACTFreq Version %8____ %9_____________________

                  General Frequency Generator for the TACT System



   Input .TDB Filename:    %0_____________________________________________
   Temporary File Area:    %1_____________________________________________

   Order Type:  Alphabetical: %|2  Reverse Alphabetical: %|3  Frequency: %|4

   Direct Results:         To Disk: %|5  To Printer: %|6
   Output Filename:        %7_____________________________________________



______________________________________________________________________________
   F1:    Help                      F9:  RUN, generate frequency results
   F6:    Credits                  F10:  QUIT, without generating frequency
*)
TYPE
   ExtensionTypes = ARRAY FreqTypeType OF ARRAY[0..3] OF CHAR;
CONST
   MainMenuRes = (*RES REM INS*) 50 ;

   FileHeaderResource = (*RES REM INS*) 113 ;   (* >>> From MAKBAS: SetupFil.MOD <<< *)

   CopyWYPos    = 16;
   CopyWXPos    = 0;

   FreqExtensions       = ExtensionTypes( ".ALP", ".REV", ".FRE" ) ;

VAR
   OldDBName      : FileNameType ;
   OldTempDiskArea: FileNameType ;
   OldOutFileName : FileNameType ;
   MenuItem       : CARDINAL ;
   CreateOutFile  : BOOLEAN ;   (* when FALSE its an FIO.Append *)
   OverWriteOut   : BOOLEAN ;
   FreqMode       : ARRAY[0..12] OF CHAR ;
   ExitList       : ARRAY[0..1] OF CHAR;
   TermList       : ARRAY[0..1] OF CHAR;
   ProcessParameters : BOOLEAN ;

PROCEDURE DummyHandleFNField(VAR Field:     ARRAY OF CHAR;
				 Exten:     ARRAY OF CHAR;
			     VAR ReDisplay: BOOLEAN;
			     VAR ReEdit:    BOOLEAN);
   BEGIN
	ReEdit := FALSE ;
	ReDisplay := FALSE ;
   END DummyHandleFNField ;


PROCEDURE VerifyOutName(VAR FileName : ARRAY OF CHAR; Extension : ARRAY OF CHAR): BOOLEAN;
   VAR
	Ch       : CHAR ;
	Mode     : ARRAY[0..12] OF CHAR ;
	ErrorMsg : StrAny ;
	FileID   : XFileType ;
   BEGIN
      GetXlationType( FileName, FreqMode ) ;
      IF FreqMode[0] = 0C THEN
	 FreqModePresent := FALSE
      ELSE
	 FreqModePresent := TRUE ;
      END ;
      IF ( NOT StandardizeFileName(FileName, Extension)) THEN
	 (*RES OLD MSG 295
	 "%0" cannot be used as the name of a file.
	 *)
	 MsgString( FileName, 0 );
	 PutResError( (*RES REM INS*) 295 ) ;
	 RETURN FALSE
      END;
      IF (FileData.GenFreqOut = OutToDisk) AND Exist(FileName) AND NOT OverWriteOut THEN
	 (*RES OLD CHE 19
	 Output File Name "%0" already exists, please choose
	 from Options: N)ew name, A)ppend to file, O)ver write file:
	 = N A O
	 *)
	 MsgString( FileName, 0 );
	 ResAskUser( (*RES REM INS *) 19 , 'NAO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	    CreateOutFile := TRUE
	 ELSIF Ch = 'A' THEN
	    CreateOutFile := FALSE
	 ELSE
	    OverWriteOut := FALSE ;
	    CreateOutFile := TRUE ;
	    RETURN FALSE
	 END ;

	 (* next insure that "translation mode/table" exist *)
	 IF NOT FreqModePresent THEN
		Str.Copy(FreqMode,FILEText);
	 END ;
	 IF NOT XOpenOutput( FileName, Extension, FreqMode, FileID, ErrorMsg ) THEN
		(*RES OLD MSG 105       >>> From MAKBAS <<<
		File Name %0: %1
		*)
		MsgString(FileName, 0);
		MsgString(ErrorMsg, 0);
		PutResError( (*RES REM INS*) 105 );
		XClose( FileID ) ;
		RETURN FALSE ;
	 ELSE
		XClose( FileID ) ;
	 END
      END;
      IF FreqModePresent THEN
	   Str.Append( FileName, '@');
	   Str.Append( FileName, FreqMode);
      END ;
      RETURN TRUE
   END VerifyOutName;

PROCEDURE VerifyInFile(Data:      ADDRESS;
		   VAR ReDisplay: BOOLEAN;
		   VAR ReEdit:    BOOLEAN);
TYPE
   DPtr = POINTER TO FileDataType;
VAR
   DataP: DPtr;
   Mode : ARRAY[0..12] OF CHAR ;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(DBName,DBName);
      GetXlationType( DBName, Mode ) ;
      IF Mode[0] <> 0C THEN
	 (*RES OLD MSG 107      >>> From MAKBAS <<<
	 A translation specification "%0" is not permitted for database file.
	 It will be ignored.
	 *)
	 MsgString( Mode, 0 );
	 PutResWarning( (*RES REM INS*) 107 ) ;
      END ;
      IF DBName[0] = 0C THEN
	 OutFileName := 0C ;
	 OverWriteOut := FALSE ;
	 RETURN
(*      ELSIF Str.Compare(OldDBName,DBName) = 0 THEN
	 ReDisplay := FALSE;
	 RETURN
*)
      ELSIF ( NOT StandardizeFileName(DBName, TDBExtension)) THEN
	 (*RES OLD MSG 272  >> from MERGEBAS <<
	 Textual DataBase Name %0 is improper
	 *)
	 MsgString(DBName,0);
	 PutResError( (*RES REM INS*) 272 );
	 ReEdit := TRUE;
	 RETURN
      END;
      IF NOT Exist(DBName) THEN
	 (*RES OLD MSG 273  >> from MERGEBAS <<
	 Textual DataBase file named %0 does not exist.
	 *)
	 MsgString(DBName,0);
	 PutResError( (*RES REM INS*) 273 );
	 ReEdit := TRUE;
	 RETURN
      END;
      IF (Str.Compare(OldDBName,DBName) <> 0) AND
         (NOT CheckTDBHeader( DBName )) THEN
	 ReEdit := TRUE;
	 RETURN
      END;
      Str.Copy(OldDBName,DBName);

      IF (NOT ProcessParameters) AND (OutFileName[0] = 0C) THEN
	 RemoveExtension( DBName, OutFileName ) ;
	 IF NOT VerifyOutName( OutFileName, FreqExtensions[FileData.FreqType] ) THEN
	    ReEdit := TRUE;
	    MenuItem := 7 ;
	    RETURN ;
	 END ;
      END ;
   END;
END VerifyInFile;


PROCEDURE VerifyOutFile(Pntr:  ADDRESS;
	       VAR ReDisplay: BOOLEAN;
	       VAR ReEdit: BOOLEAN);
   VAR
	Data : POINTER TO FileDataType ;
   BEGIN
	Data := Pntr;
	ReDisplay := FALSE;
	ReEdit := FALSE;
	IF Str.Compare(OldOutFileName,Data^.OutFileName) = 0 THEN RETURN END;
	MenuItem := 7 ;
	OldOutFileName := Data^.OutFileName;
	ReDisplay := TRUE;
	IF NOT VerifyOutName(Data^.OutFileName, FreqExtensions[FileData.FreqType] ) THEN ReEdit := TRUE END;
   END VerifyOutFile;

PROCEDURE VerifyTDA( VAR TempDiskArea : ARRAY OF CHAR): BOOLEAN;
   VAR
      TDADone   : BOOLEAN ;
      Done      : BOOLEAN ;
      drive     : CHAR ;
      dir       : StrAny ;
      TDALen    : CARDINAL ;
      I         : CARDINAL ;
   BEGIN
      TrimBlanks( TempDiskArea, TempDiskArea ) ;
      IF TempDiskArea[0] = 0C THEN
         ChangeTDADirectory ;
	 RETURN TRUE
      END ;
      UpcaseStr( TempDiskArea, TempDiskArea ) ;
      TDALen := Str.Length( TempDiskArea ) ;
      IF TempDiskArea[TDALen-1] = '\' THEN
	 DEC( TDALen ) ;
	 TempDiskArea[TDALen] := 0C ;
      END ;
      IF (TempDiskArea[1] = ':') AND (TempDiskArea[2] <> '\')THEN
	 (* make room to insert a "\" after ":" *)
	 FOR I := TDALen TO 3 BY -1 DO
              TempDiskArea[I] := TempDiskArea[I-1] ;
	 END ;
	 TempDiskArea[2] := '\' ;
	 INC( TDALen ) ;
	 TempDiskArea[TDALen] := 0C ;
      END ;

      CurrentDrive( drive ) ;
      CurrentDirectory( drive, dir ) ;
      (* note: "CurrentDirectory" does not return leading "\", need it for CHDIR *)
      IF dir[0] <> '\' THEN
	 FOR I := Str.Length(dir) TO 1 BY -1 DO
		dir[I] := dir[I-1] ;
	 END ;
	 dir[0] := '\' ;
      END ;

      (* see if drive/path exists *)
      ChangeDirectory( TempDiskArea, TDADone ) ;

      IF TDADone THEN (* m.s. *)
         ChangeTDADirectory ;
      END ;
      (* restore drive/path *)
      SelectDrive( drive ) ;
      ChangeDirectory( dir, Done ) ;

      IF TDADone THEN
	 IF TempDiskArea[TDALen-1] <> '\' THEN
	    TempDiskArea[TDALen] := '\' ;
	    TempDiskArea[TDALen+1] := 0C ;
	 END ;
	 RETURN TRUE
      ELSE
	 (*RES OLD MSG 175  >> from MAKBAS <<
	 Invalid Drive/Path specification for temporary disk space "%0".
	 *)
	 MsgString( TempDiskArea, 0 );
	 PutResWarning( (*RES REM INS*) 175 ) ;
	 RETURN FALSE
      END;
   END VerifyTDA ;

PROCEDURE CheckTDA(Pntr:  ADDRESS;
	       VAR ReDisplay: BOOLEAN;
	       VAR ReEdit: BOOLEAN);
   VAR
	Data : POINTER TO FileDataType ;
   BEGIN
	Data := Pntr;
	ReDisplay := FALSE;
	ReEdit := FALSE;
	IF Str.Compare(OldTempDiskArea,Data^.TempDiskArea) = 0 THEN RETURN END;
	OldTempDiskArea := Data^.TempDiskArea;
	ReDisplay := TRUE;
	MenuItem  := 1 ;
	IF NOT VerifyTDA(Data^.TempDiskArea) THEN ReEdit := TRUE END;
   END CheckTDA;

PROCEDURE DoStartUp(): BOOLEAN;
VAR
   FrontMenu: MenuID;
(*   BaseWind:  WindowInfo; *)
   i,j:       CARDINAL;
   TC:        CHAR;
   FunctKey:  BOOLEAN;
   Done:      BOOLEAN;
   VerX,VerY,VerLen: CARDINAL;
   DatX,DatY,DatLen: CARDINAL;
   m:         ARRAY[0..40] OF CHAR;
   DoMenuNow: BOOLEAN;
   HelpName:  ARRAY[0..4] OF CHAR;
   IOresult:  CARDINAL ;
   ErrorMsg : StrAny ;

PROCEDURE HandleParameters;
   VAR
	plst,temp:  ParameterResult;
	str:         ARRAY[0..255] OF CHAR;
	ReDisplay:   BOOLEAN;
	ReEdit:      BOOLEAN;
	i,j:         CARDINAL;
	TryBatch:    BOOLEAN;
   BEGIN
	(* format
	TACTFREQ [-b] [-c D|P] [-a | -f | -r ]
			[-w <TDA>] [-o <out FN>] <TDB file name>
	*)
	InitialParams;
	LegalParameter('?',FALSE);      (* options  *)
	LegalParameter('a',FALSE);      (* order: Alphabetical          *)
	LegalParameter('b',FALSE);      (* batch switch                 *)
	LegalParameter('c',TRUE);       (* generate anagrams to D=disk, P=printer *)
	LegalParameter('f',FALSE);      (* order: Frequency             *)
	LegalParameter('r',FALSE);      (* order: ReverseAlpha          *)
	LegalParameter('w',TRUE);       (* Temp Disk Area               *)
	i := 0;
	TryBatch := FALSE;
	ProcessParameters := TRUE ;
	CASE GetParameters(plst,str) OF
	   GPSOk: (* do nothing right now *)
	   | GPSBadParameter:
		(*RES OLD MSG 508
		Parameter "%0" cannot be specified for TACTFREQ.
		*)
		MsgString(str,0);
		PutResError( (*RES REM INS*) 508 );
		DoMenuNow := TRUE;
		RETURN
	   | GPSMissingValue:
		(*RES OLD MSG 514
		Parameter "%0" requires a parameter for TACTFREQ.
		*)
		MsgString(str,0);
		PutResError( (*RES REM INS*) 514 );
		DoMenuNow := TRUE;
		RETURN
	END;
	WHILE plst <> NIL DO
	   WITH plst^ DO
		CASE Code OF
		   ' ':	
                      CASE i OF
                         0: Str.Copy(FileData.DBName, Strg);
                            VerifyInFile( ADR ( FileData ) , ReDisplay, ReEdit ) ;
                       | 1: Str.Copy(FileData.OutFileName,Strg);
                            IF NOT VerifyOutName(FileData.OutFileName, FreqExtensions[FileData.FreqType] ) THEN
                               MenuItem := 7;
                               ReEdit := TRUE ;
                               RETURN
                            END ;
			ELSE
			   (*RES OLD MSG 515
			   Too many input files were given as parameters to TACTFREQ
			   *)
			   PutResError( (*RES REM INS*) 515 );
			   HALT;
			END; 	
                        INC(i);
		   | 'A':
			FileData.FreqType := Alphabetical ;
		   | 'B':
			TryBatch := TRUE;
		   | 'C':       (* output type: -c D|P          *)
			CASE CAP(Strg[0]) OF
			  'D' :  FileData.GenFreqOut := OutToDisk |
			  'P' :  FileData.GenFreqOut := OutToPrinter
			  ELSE
			      RETURN
			END ;
		   | 'F':
			FileData.FreqType := Frequency ;
		   | 'R':
			FileData.FreqType := ReverseAlpha ;
		   | 'W':       (* Temp Disk Area:  -w <TDA>            *)
			Str.Copy( FileData.TempDiskArea, Strg );
			CheckTDA( ADR(FileData), ReDisplay, ReEdit );
			IF ReEdit THEN RETURN END;
		   ELSE
			ProgramErrorAndHalt('Unexpected ParameterData Code found');
		END;
	   END;
	   temp := plst^.Next;
	   DEALLOCATE(plst,plst^.Size);
	   plst := temp;
	END;
	DoMenuNow := (NOT TryBatch) OR (FileData.DBName[0] = 0C) OR (MenuItem > 0) OR ReEdit;
        ProcessParameters := FALSE;
        IF (MenuItem = 0) AND (NOT ReEdit) AND (i > 0) THEN
           VerifyInFile( ADR ( FileData ) , ReDisplay, ReEdit ) ;
        END ;
   END HandleParameters;

BEGIN   (* DoStartUp *)
   ExitList[0] := ASCII.rs;
   ExitList[1] := 0C ;
   TermList[0] := PCKey.F9;
   TermList[1] := 0C ;
   HelpName := 'HELP';
   InitialPrintModule(HelpName, TermList, ExitList, DummyHandleFNField);
   BaseWPtr := NIL ;
   WITH BaseWind DO
      XPos := 1;
      YPos := 1;
      XSize := 80;
      YSize := 25;
      MxYSize := 25;
      Type :=       Dialog;
      AllowMove :=  FALSE;
      AllowResize :=FALSE;
      IsTop :=      FALSE
   END;

   StartMenu(FileData);
   WITH FileData DO
     CharFieldProc(DBName,VerifyInFile);
     CharFieldProc(TempDiskArea,CheckTDA);
     Switches(FreqType);
	 SwitchValue(Alphabetical);
	 SwitchValue(ReverseAlpha);
	 SwitchValue(Frequency);
     Switches(GenFreqOut);
	 SwitchValue(OutToDisk);
	 SwitchValue(OutToPrinter);
     CharFieldProc(OutFileName,VerifyOutFile);
   END;
   MakeMenu( MainMenuRes, FrontMenu);
   GetFieldInfo(FrontMenu, 8,VerX,VerY,VerLen);
   GetFieldInfo(FrontMenu, 9,DatX,DatY,DatLen);

   PushNewWindow(BaseWind, BaseWPtr, DummyInit);
   ShowFixedText(BaseWPtr,FrontMenu,0,0);

   TWB.GotoXY(0,21);
   TWB.ClrEol;
   TWB.WrStr('              Copyright (c) 1995 TACT Group, University of Toronto ') ;
   TWB.WrLn ;

   WriteScreenField( BaseWPtr, VerLen, VerX, VerY,
			   SystemVersion, RegularAttr, TRUE );

   WriteScreenField( BaseWPtr, DatLen, DatX, DatY,
			   SystemVersionDate, RegularAttr, TRUE );

   WITH FileData DO
      DBName       := 0C;
      OutFileName  := 0C;
      TempDiskArea := 0C;
      FreqType     := Alphabetical ;
      GenFreqOut := OutToDisk ;
   END;
   FreqMode := 0C ;

   MenuItem := 0;
   DoMenuNow := TRUE;
   CreateOutFile := TRUE ;
   OverWriteOut  := FALSE ;
   FreqModePresent := FALSE ;
   HandleParameters;
   REPEAT
      ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);
      IF DoMenuNow THEN
	 DoMenu(BaseWPtr,FrontMenu,0,0, ExitList, TermList, FileData,MenuItem,TC,FunctKey);
	 IF GetPanelControlKey(FunctKey, TC) = PanelCancel THEN
	    RETURN FALSE
	 END ;
	 DoMenuNow := FALSE ;
      END;
      IF FileData.DBName[0] = 0C THEN
	 DoMenuNow := TRUE;
	 MenuItem := 0 ;
	 (*RES OLD MSG 296
	 The TDB file name must be given.
	 *)
	 PutResError( (*RES REM INS*) 296 ) ;
      END ;
      IF (FileData.OutFileName[0] = 0C) AND (FileData.GenFreqOut = OutToDisk) THEN
	 DoMenuNow := TRUE;
	 MenuItem := 7 ;
	 (*RES OLD MSG 516
	 The output frequency file name must be given.
	 *)
	 PutResError( (*RES REM INS*) 516 ) ;
      END ;
   UNTIL NOT DoMenuNow ;

   IF FileData.GenFreqOut <> OutToDisk THEN FileData.OutFileName[0] := 0C  END ;

   ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);

   IF NOT InitializeTDB( FileData.DBName ) THEN
	RETURN FALSE;
   END ;

   IF FileData.GenFreqOut = OutToDisk THEN
	IF NOT FreqModePresent THEN
	   Str.Copy(FreqMode,FILEText);
	END ;
	IF CreateOutFile THEN
	   IF NOT XOpenOutput( FileData.OutFileName, FreqExtensions[FileData.FreqType], FreqMode, OutFileID, ErrorMsg ) THEN
	      (* something wrong ... *)
	      MsgString( FileData.OutFileName, 0 ) ;
	      MsgString( ErrorMsg, 0 ) ;
	      PutResError( FileHeaderResource ) ;
	      XClose( OutFileID ) ;
	      RETURN FALSE ;
	   END ;
	ELSE
	   IF NOT XAppend( FileData.OutFileName, FreqExtensions[FileData.FreqType], FreqMode, OutFileID, ErrorMsg ) THEN
	      (* something wrong ... *)
	      MsgString( FileData.OutFileName, 0 ) ;
	      MsgString( ErrorMsg, 0 ) ;
	      PutResError( FileHeaderResource ) ;
	      XClose( OutFileID ) ;
	      RETURN FALSE ;
	   END ;
	END ;
	IF NOT CreateOutFile THEN  (* separate from previous listing *)
	   XWrLn( OutFileID, IOresult );
	   XWrLn( OutFileID, IOresult );
	END ;
   END ;
   TWB.SetPalette(BaseWPtr, ActiveAttrib);
   DestroyMenu(FrontMenu);
   TerminatePrintModule;
   RETURN TRUE;
END DoStartUp;

END StartUp .
