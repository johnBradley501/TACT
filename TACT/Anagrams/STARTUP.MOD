IMPLEMENTATION MODULE StartUp ;

(* copyright (c) 1989-96 Ian Lancashire, Lidio Presutti, University of Toronto *)

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
  (* proc *)  MsgString, MsgCard, ResAskUser, PutResError, PutResWarning;
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
               ChangeTDADirectory (* m.s. *) ;

FROM TDBInit IMPORT CheckTDBHeader, InitializeTDB;

(*RES OLD MNU 49

                 General Anagram Generator for the TACT System

                      Anagrams Version %10___ %11____________________


   Input .TDB Filename: %0_______________________________________________
   Temporary File Area: %1_______________________________________________

   Type:       Proper Anagrams: %|2   Partial Anagram Matches: %|3

   Generate Anagrams:      Yes: %|4  No: %|5
   Output Filename:     %6_______________________________________________

   Generate Query File:    Yes: %|7  No: %|8
   Query Filename:      %9_______________________________________________




______________________________________________________________________________
   F1:    Help                        F9:   RUN, generate all anagrams
   F6:    Credits                    F10:  QUIT without generating anagrams
*)
CONST
   MainMenuRes = (*RES REM INS*) 49 ;

   FileHeaderResource = (*RES REM INS*) 113 ;	(* >>> From MAKBAS: SetupFil.MOD <<< *)

   CopyWYPos    = 19;
   CopyWXPos    = 0;

   RuleExtension     = '.QUE';
   AnagramExtension  = '.ANA';

VAR
   OldDBName	  : FileNameType ;
   OldTempDiskArea: FileNameType ;
   OldOutFileName : FileNameType ;
   OldRuleFileName: FileNameType ;
   MenuItem	  : CARDINAL ;
   CreateOutFile  : BOOLEAN ;	(* when FALSE its an FIO.Append *)
   OverWriteOut   : BOOLEAN ;
   OverWriteRule  : BOOLEAN ;
   AnagramMode	  : ARRAY[0..12] OF CHAR ;
   RuleMode	  : ARRAY[0..12] OF CHAR ;
   ExitList	  : ARRAY[0..1] OF CHAR;
   TermList	  : ARRAY[0..1] OF CHAR;
   ProcessingParameters : BOOLEAN ;

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
	Ch	 : CHAR ;
	Mode	 : ARRAY[0..12] OF CHAR ;
	ErrorMsg : StrAny ;
	FileID	 : XFileType ;
   BEGIN
      GetXlationType( FileName, AnagramMode ) ;
      IF AnagramMode[0] = 0C THEN
	 AnagramModePresent := FALSE
      ELSE
	 AnagramModePresent := TRUE ;
      END ;
      IF ( NOT StandardizeFileName(FileName, Extension)) THEN
         (*RES OLD MSG 295
         "%0" cannot be used as the name of a file.
         *)
         MsgString( FileName, 0 );
         PutResError( (*RES REM INS*) 295 ) ;
         RETURN FALSE
      END;
      IF (FileData.GenAnagrams) AND Exist(FileName) AND NOT OverWriteOut THEN
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
	 IF NOT AnagramModePresent THEN
		Str.Copy(AnagramMode,FILEText);
	 END ;
	 IF NOT XOpenOutput( FileName, Extension, AnagramMode, FileID, ErrorMsg ) THEN
		(*RES OLD MSG 105	>>> From MAKBAS <<<
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
      IF AnagramModePresent THEN
	   Str.Append( FileName, '@');
	   Str.Append( FileName, AnagramMode);
      END ;
      RETURN TRUE
   END VerifyOutName;

PROCEDURE VerifyRuleName(VAR FileName : ARRAY OF CHAR; Extension : ARRAY OF CHAR): BOOLEAN;
   VAR
	Ch		: CHAR ;
	RuleModePresent : BOOLEAN ;
	ErrorMsg 	: StrAny ;
	FileID	 	: XFileType ;
   BEGIN
      GetXlationType( FileName, RuleMode ) ;
      IF RuleMode[0] = 0C THEN
	 Str.Copy(RuleMode,FILEText);
	 RuleModePresent := FALSE
      ELSE
	 RuleModePresent := TRUE ;
      END ;
      IF ( NOT StandardizeFileName(FileName, Extension)) THEN
         (*RES OLD MSG 295
         "%0" cannot be used as the name of a file.
         *)
         MsgString( FileName, 0 );
         PutResError( (*RES REM INS*) 295 ) ;
         RETURN FALSE
      END;
      IF FileData.GenRuleFile AND Exist(FileName) AND NOT OverWriteRule THEN
	 (*RES OLD CHE 20
         Rule File Name "%0" already exists, please choose
	 from Options: N)ew name, or O)ver write file:
	 = N O
	 *)
         MsgString( FileName, 0 );
	 ResAskUser( (*RES REM INS *) 20 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteRule :=TRUE ;
	 ELSE
	    RETURN FALSE
	 END ;

	 (* next insure that "translation mode/table" exist *)
	 IF NOT XOpenOutput( FileName, Extension, RuleMode, FileID, ErrorMsg ) THEN
		(*RES OLD MSG 105	>>> From MAKBAS <<<
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
      IF RuleModePresent THEN
	   Str.Append( FileName, '@');
	   Str.Append( FileName, RuleMode);
      END ;
      RETURN TRUE
   END VerifyRuleName;

PROCEDURE VerifyInFile(Data:      ADDRESS;
                   VAR ReDisplay: BOOLEAN;
                   VAR ReEdit:    BOOLEAN);
TYPE
   DPtr = POINTER TO FileDataType;
VAR
   DataP:    DPtr;
   Mode : ARRAY[0..12] OF CHAR ;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(DBName,DBName);
      GetXlationType( DBName, Mode ) ;
      IF Mode[0] <> 0C THEN
         (*RES OLD MSG 107	>>> From MAKBAS <<<
         A translation specification "%0" is not permitted for database file.
         It will be ignored.
         *)
         MsgString( Mode, 0 );
         PutResWarning( (*RES REM INS*) 107 ) ;
      END ;
      IF DBName[0] = 0C THEN
         GenRuleFile := TRUE ;
         OutFileName := 0C ;
         RuleFileName := 0C ;
         OverWriteOut := FALSE ;
         OverWriteRule := FALSE ;
         RETURN
      ELSIF Str.Compare(OldDBName,DBName) = 0 THEN
         ReDisplay := FALSE;
         RETURN
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
      IF NOT CheckTDBHeader( DBName ) THEN
         ReEdit := TRUE;
         RETURN
      END;
      Str.Copy(OldDBName,DBName);
      IF NOT ProcessingParameters THEN
        IF OutFileName[0] = 0C THEN
          RemoveExtension( DBName, OutFileName ) ;
          IF NOT VerifyOutName( OutFileName, AnagramExtension ) THEN
	    ReEdit := TRUE;
	    MenuItem := 5 ;
          END ;
        END ;
        IF (RuleFileName[0] = 0C) AND GenRuleFile THEN
          RemoveExtension( DBName, RuleFileName ) ;
          IF NOT VerifyRuleName( RuleFileName, RuleExtension ) THEN
	    ReEdit := TRUE;
	    IF MenuItem = 0 THEN
	       MenuItem := 7;
	    END ;
          END ;
        END ;
     END ;
   END;
END VerifyInFile;

PROCEDURE MakeDefaultFileNames(VAR FileData: FileDataType);
   VAR
      Dummy: BOOLEAN;
   BEGIN
    WITH FileData DO
      IF OutFileName[0] = 0C THEN
         RemoveExtension( DBName, OutFileName ) ;
         IF NOT VerifyOutName( OutFileName, AnagramExtension ) THEN
	    MenuItem := 5 ;
         END ;
      END ;
      IF (RuleFileName[0] = 0C) AND GenRuleFile THEN
         RemoveExtension( DBName, RuleFileName ) ;
         IF NOT VerifyRuleName( RuleFileName, RuleExtension ) THEN
	    IF MenuItem = 0 THEN
  	      MenuItem := 7;
  	    END ;
         END ;
      END ;
      END ;
   END MakeDefaultFileNames;

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
	MenuItem := 6 ;
	OldOutFileName := Data^.OutFileName;
	ReDisplay := TRUE;
	IF NOT VerifyOutName(Data^.OutFileName, AnagramExtension ) THEN ReEdit := TRUE END;
   END VerifyOutFile;

PROCEDURE VerifyRuleFile(Pntr:  ADDRESS;
               VAR ReDisplay: BOOLEAN;
               VAR ReEdit: BOOLEAN);
   VAR
	Data : POINTER TO FileDataType ;
   BEGIN
	Data := Pntr;
	ReDisplay := FALSE;
	ReEdit := FALSE;
	IF Str.Compare(OldRuleFileName,Data^.RuleFileName) = 0 THEN RETURN END;
	IF NOT Data^.GenRuleFile AND (Data^.RuleFileName[0] <> 0C) THEN
	   Data^.RuleFileName := 0C ;
	   ReDisplay := TRUE ;
	   RETURN
	END ;
	MenuItem := 9;
	OldRuleFileName := Data^.RuleFileName;
	ReDisplay := TRUE;
	IF NOT VerifyRuleName(Data^.RuleFileName, RuleExtension ) THEN ReEdit := TRUE END;
   END VerifyRuleFile;

PROCEDURE VerifyTDA( VAR TempDiskArea : ARRAY OF CHAR): BOOLEAN;
   VAR
      TDADone	: BOOLEAN ;
      Done	: BOOLEAN ;
      drive	: CHAR ;
      dir	: StrAny ;
      TDALen	: CARDINAL ;
      I		: CARDINAL ;
   BEGIN
      TrimBlanks( TempDiskArea, TempDiskArea ) ;
      IF TempDiskArea[0] = 0C THEN
         ChangeTDADirectory ; (* change extender swap location *)
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
         ChangeTDADirectory ; (* change extender swap location *)
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
	MenuItem  := 0 ;
	IF NOT VerifyTDA(Data^.TempDiskArea) THEN ReEdit := TRUE END;
   END CheckTDA;

PROCEDURE DoStartUp(): BOOLEAN;
VAR
   FrontMenu: MenuID;
(* m.s. moved to .def   BaseWind:  WindowInfo; *)
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
	(* Syntax:  ANAGRAMS [-b] [-a] [ [-n] | [-q <rule FN>] ]
			[-p] [-w <TDA>] [-o <out FN>] <TDB file name> *)
	InitialParams;
	LegalParameter('b',FALSE);	(* batch switch			*)
	LegalParameter('a',FALSE);	(* no anagrams switch, default yes *)
	LegalParameter('n',FALSE);	(* no rule file; default gen rule *)
	LegalParameter('p',FALSE);	(* partial matches (default proper) *)
	LegalParameter('q',TRUE);	(* rule file name		*)
	LegalParameter('w',TRUE);	(* Temp Disk Area		*)
	i := 0;
	TryBatch := FALSE;
	CASE GetParameters(plst,str) OF
	   GPSOk: (* do nothing right now *)
	   | GPSBadParameter:
		(*RES OLD MSG 509
		Parameter "%0" cannot be specified for Anagrams.
		*)
		MsgString(str,0);
		PutResError( (*RES REM INS*) 509 );
		DoMenuNow := TRUE;
		RETURN
	   | GPSMissingValue:
		(*RES OLD MSG 510
		Parameter "%0" requires a parameter for Anagrams.
		*)
		MsgString(str,0);
		PutResError( (*RES REM INS*) 510 );
		DoMenuNow := TRUE;
		RETURN
	END;
	WHILE plst <> NIL DO
	   WITH plst^ DO
		CASE Code OF
		   ' ':
			IF i >= 2 THEN
			   (*RES OLD MSG 511
			   Too many input files were given as parameters to Anagrams.
			   *)
			   PutResError( (*RES REM INS*) 511 );
			   RETURN;
                        ELSE
                           CASE i OF
                             0:
			     Str.Copy( FileData.DBName, Strg );
			     VerifyInFile( ADR(FileData), ReDisplay, ReEdit );
			     IF ReEdit THEN
			         MenuItem := 1 ;
			         RETURN
			     END;
			     INC(i);
                           | 1:
		             Str.Copy( FileData.OutFileName, Strg );
			     IF NOT VerifyOutName( FileData.OutFileName, AnagramExtension ) THEN
			        MenuItem := 2;
			        RETURN
			     END ;
			     INC(i);
                          END ;
                       END ;
		   | 'B':
			TryBatch := TRUE;
		   | 'A':	(* output type: -A		*)
                        FileData.GenAnagrams := FALSE ;
                   			
		   | 'N':	(* do NOT generate rule file *)
			FileData.GenRuleFile := FALSE ;
		   | 'P':	(* generate partial matches file *)
			FileData.AnagramType := PartialMatchAnagrams;
		   | 'Q':	(* rule file name:  -q <rule FN>	*)
			Str.Copy( FileData.RuleFileName, Strg );
			IF NOT VerifyRuleName( FileData.RuleFileName, RuleExtension ) THEN  RETURN  END ;
		   | 'W':	(* Temp Disk Area:  -w <TDA>		*)
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
	IF i = 0 THEN
	   MenuItem := 1;
	   RETURN ;
	END;
        MakeDefaultFileNames(FileData);
	DoMenuNow := (NOT TryBatch) OR (FileData.DBName[0] = 0C) OR
	             (MenuItem > 1);
   END HandleParameters;

BEGIN	(* DoStartUp *)
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
     Switches(AnagramType);
         SwitchValue(ProperAnagrams);
         SwitchValue(PartialMatchAnagrams);
     Switches(GenAnagrams);
         SwitchValue(TRUE);
         SwitchValue(FALSE);
     CharFieldProc(OutFileName,VerifyOutFile);
     Switches(GenRuleFile);
         SwitchValue(TRUE);
         SwitchValue(FALSE);
     CharFieldProc(RuleFileName,VerifyRuleFile);
   END;
   MakeMenu( MainMenuRes, FrontMenu);
   GetFieldInfo(FrontMenu,10,VerX,VerY,VerLen);
   GetFieldInfo(FrontMenu,11,DatX,DatY,DatLen);

   PushNewWindow(BaseWind, BaseWPtr, DummyInit);
   ShowFixedText(BaseWPtr,FrontMenu,0,0);

   TWB.GotoXY(CopyWXPos,CopyWYPos);
   TWB.ClrEol;
   TWB.WrStr('              Copyright (c) 1995 TACT Group, University of Toronto ') ;
   TWB.WrLn ;
(*
   TWB.WrStr('                 Centre for Computing in the Humanities ' ) ;
   TWB.WrLn ;
   TWB.WrStr('                         University of Toronto');
   TWB.WrLn ;
*)
   WriteScreenField( BaseWPtr, VerLen, VerX, VerY,
                           SystemVersion, RegularAttr, TRUE );

   WriteScreenField( BaseWPtr, DatLen, DatX, DatY,
                           SystemVersionDate, RegularAttr, TRUE );

   WITH FileData DO
      DBName	   := 0C;
      OutFileName  := 0C;
      TempDiskArea := 0C;
      AnagramType  := ProperAnagrams;
      GenAnagrams := TRUE ;
      GenRuleFile  := TRUE ;
      RuleFileName := 0C ;
   END;
   AnagramMode := 0C ;
   RuleMode := 0C ;

   MenuItem := 0;
   DoMenuNow := TRUE;
   CreateOutFile := TRUE ;
   OverWriteOut  := FALSE ;
   OverWriteRule := FALSE ;
   AnagramModePresent := FALSE ;
   ProcessingParameters := TRUE ;
   HandleParameters;
   ProcessingParameters := FALSE ;
   REPEAT
      ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);
      IF DoMenuNow THEN
         DoMenu(BaseWPtr,FrontMenu,0,0, ExitList, TermList, FileData,MenuItem,TC,FunctKey);
	 IF GetPanelControlKey(FunctKey, TC) = PanelCancel THEN
	    RETURN FALSE
	 END ;
         DoMenuNow := FALSE ;
         TrimBlanks(FileData.DBName, FileData.DBName ) ;
         TrimBlanks(FileData.OutFileName, FileData.OutFileName ) ;
         TrimBlanks(FileData.RuleFileName, FileData.RuleFileName ) ;
      END;
      IF FileData.DBName[0] = 0C THEN
         DoMenuNow := TRUE;
	 MenuItem := 0 ;
	 (*RES OLD MSG 296
	 The TDB file name must be given.
	 *)
	 PutResError( (*RES REM INS*) 296 ) ;
      END ;
      IF (FileData.OutFileName[0] = 0C) AND (FileData.GenAnagrams) THEN
         DoMenuNow := TRUE;
	 MenuItem := 5 ;
	 (*RES OLD MSG 512
	 The Anagrams file name must be given.
	 *)
	 PutResError( (*RES REM INS*) 512 ) ;
      END ;
      IF FileData.GenRuleFile AND (FileData.RuleFileName[0] = 0C) THEN
         DoMenuNow := TRUE;
	 MenuItem := 9;
	 (*RES OLD MSG 304
	 The RULE file name must be given.
	 *)
	 PutResError( (*RES REM INS*) 304 ) ;
      END ;
      IF ( NOT FileData.GenRuleFile) AND (NOT FileData.GenAnagrams) THEN
         DoMenuNow := TRUE;
	 MenuItem := 4 ;
	 (*RES OLD MSG 513
	 At least one output type (QUERY or ANAGRAMS) must be requested.
	 *)
	 PutResError( (*RES REM INS*) 513 ) ;
      END ;
   UNTIL NOT DoMenuNow ;

   IF NOT FileData.GenRuleFile THEN  FileData.RuleFileName[0] := 0C  END ;
   IF NOT FileData.GenAnagrams  THEN FileData.OutFileName[0] := 0C  END ;

   ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);

   IF NOT InitializeTDB( FileData.DBName ) THEN
	RETURN FALSE;
   END ;

   IF FileData.GenAnagrams THEN
	IF NOT AnagramModePresent THEN
	   Str.Copy(AnagramMode,FILEText);
	END ;
	IF CreateOutFile THEN
	   IF NOT XOpenOutput( FileData.OutFileName, AnagramExtension, AnagramMode, OutFileID, ErrorMsg ) THEN
	      (* something wrong ... *)
	      MsgString( FileData.OutFileName, 0 ) ;
	      MsgString( ErrorMsg, 0 ) ;
	      PutResError( FileHeaderResource ) ;
	      XClose( OutFileID ) ;
	      RETURN FALSE ;
	   END ;
	ELSE
	   IF NOT XAppend( FileData.OutFileName, AnagramExtension, AnagramMode, OutFileID, ErrorMsg ) THEN
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
   IF FileData.GenRuleFile THEN
	IF NOT XOpenOutput( FileData.RuleFileName, RuleExtension, RuleMode, RuleFileID, ErrorMsg ) THEN
	   (* something wrong ... *)
	   MsgString( FileData.RuleFileName, 0 ) ;
	   MsgString( ErrorMsg, 0 ) ;
	   PutResError( FileHeaderResource ) ;
	   XClose( RuleFileID ) ;
	   RETURN FALSE ;
	END ;
   END ;
   TWB.SetPalette(BaseWPtr, ActiveAttrib);
   DestroyMenu(FrontMenu);
   TerminatePrintModule;
   RETURN TRUE;
END DoStartUp;

END StartUp .
