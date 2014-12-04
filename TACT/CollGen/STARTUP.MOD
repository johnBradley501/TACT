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
  (* vars   *) month, day, year, StandardSearchList,
  (* procs  *) RemoveExtension, StandardizeFileName, GetXlationType, GetEnv,
	       UpcaseStr, TrimBlanks, Exist, BOpen, RWType, BClose, FindFileInList ;
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
  (* Procs *)  XOpenOutput, XClose, XAppend, XlateLine, XWriteLine, XWrLn,
	       XOpenInput, XReadLine ;
FROM ResMenus IMPORT
  (* type   *) MenuID,
  (* proc   *) StartMenu, CharFieldProc, MakeMenu, DestroyMenu, GetFieldInfo,
		ShowFixedText, ShowMenu, DoMenu, CharField, CardField,
		Switches, SwitchValue, LongIntField ;
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
  (* Procs *)  CurrentDrive, SelectDrive, CurrentDirectory, ChangeDirectory ;

FROM TDBInit IMPORT CheckHeader, InitializeFromDB, MergeRefList ;

(*RES OLD MNU 31
            General Collocation Generator for the TACT System
              COLLGEN Version %22____ %23________________________

   Input .TDB Filename:     %0______________________________________________
   Temporary File Area:     %1______________________________________________
   Span Context: %2_ to %3_ Words
   Number of Repetitions to Keep: %4_ to %5___
   Boundaries:  %6__________________________________________________________
   Output Formatted With:   Tabs: %|7   or   Spaces: %|8

   Generate Fixed Phrases:  Yes: %|9  No: %|10
   Fixed Phrase Filename:   %11_____________________________________________
   Fixed Phrase Format:     Maximal: %|12  or  Permuted: %|13

   Generate Node Collocate Pairs:    Yes: %|14  No: %|15
   Count Overlapping Collocates:     Yes: %|16  No: %|17
   Node-Collocate Filename: %18_____________________________________________

   Generate Fixed Phrases Query File:     Yes: %|19  No: %|20
   Query Filename:          %21_____________________________________________
______________________________________________________________________________
F1: Help       F9: RUN, Generate Collocations      F10: QUIT, No Collocations
F6: Credits          (c) 1995 TACT Group, University of Toronto
*)
(*RES OLD MSG 456
Please rename your file. "%0" is already used by another Output File.
*)

CONST
   MainMenuRes = (*RES REM INS*) 31 ;

   DuplicateOutputFile = (*RES REM INS*) 456   ;  (* for VerifyFileName procedures to avoid duplicate filenames *)

   CopyWYPos    = 22;
   CopyWXPos    = 20;

   PermutedRuleExtension = '.QUE';
   MaximalRuleExtension  = '.QUE';
   PermutedColExtension  = '.COL';
   MaximalColExtension = '.COL';

   NodeCollExtension = '.NOD' ; (* m.s. *)
   FunctionExtension = '.XCL' ; (* m.s. *)
   IncludeExtension = '.INC' ; (* m.s. *)
   DefaultFunctionFileName = 'COLLGEN' ; (* m.s. *)
   FrequencyExtension  = '.FRQ' ; (* m.s. *)
VAR
   OldDBName      : FileNameType ;
   OldTempDiskArea: FileNameType ;
   OldOutFileName : FileNameType ;
   OldRuleFileName: FileNameType ;
   OldNodeCollFileName: FileNameType ;
   MenuItem       : CARDINAL ;
   CreateOutFile  : BOOLEAN ;   (* when FALSE its an FIO.Append *)
   OverWriteOut   : BOOLEAN ;
   OverWriteRule  : BOOLEAN ;
   OverWriteNodeColl  : BOOLEAN ; (* m.s. *)
   NodeCollMode   : ARRAY[0..12] OF CHAR ;  (* m.s. *)
   FunctionMode   : ARRAY[0..12] OF CHAR ;  (* m.s. *)
   ExitList       : ARRAY[0..1] OF CHAR;
   TermList       : ARRAY[0..1] OF CHAR;

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
      GetXlationType( FileName, CollMode ) ;
      IF CollMode[0] = 0C THEN
	 CollModePresent := FALSE
      ELSE
	 CollModePresent := TRUE ;
      END ;
      IF ( NOT StandardizeFileName(FileName, Extension)) THEN
	 (*RES OLD MSG 295
	 "%0" cannot be used as the name of a file.
	 *)
	 MsgString( FileName, 0 );
	 PutResError( (*RES REM INS*) 295 ) ;
	 RETURN FALSE
      END;
      IF (FileData.GenCollOut) AND Exist(FileName)  THEN
	IF ( Str.Compare( FileName, FileData.NodeCollFileName) = 0 ) OR
	   (Str.Compare( FileName, FileData.RuleFileName)  = 0) THEN
	   MsgString( FileName, 0 ) ;
	   PutResError( DuplicateOutputFile ) ;
	   RETURN FALSE ;
	ELSIF NOT OverWriteOut THEN
	 (*RES OLD CHE 32
	 The output filename "%0" already exists. Please choose
	 between N)ew name and O)verwrite file:
	 = N O
	 *)
	 MsgString( FileName, 0 );
	 ResAskUser( (*RES REM INS *) 32 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	    CreateOutFile := TRUE
	 ELSE
	    OverWriteOut := FALSE ;
	    CreateOutFile := TRUE ;
	    RETURN FALSE
	 END ;

	 (* next insure that "translation mode/table" exist *)
	 IF NOT CollModePresent THEN
		Str.Copy(CollMode,FILEText);
	 END ;
	 IF NOT XOpenOutput( FileName, Extension, CollMode, FileID, ErrorMsg ) THEN
		(*RES  OLD MSG 105       >>> From MAKBAS <<<
		File Name %0: %1.
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
      END ;
      IF CollModePresent THEN
	   Str.Append( FileName, '@');
	   Str.Append( FileName, CollMode);
      END ;
      RETURN TRUE
   END VerifyOutName;

PROCEDURE VerifyRuleName(VAR FileName : ARRAY OF CHAR; Extension : ARRAY OF CHAR): BOOLEAN;
   VAR
	Ch              : CHAR ;
	RuleModePresent : BOOLEAN ;
	ErrorMsg        : StrAny ;
	FileID          : XFileType ;
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
      IF FileData.GenRuleFile AND Exist(FileName) THEN

	IF (Str.Compare( FileName, FileData.NodeCollFileName ) = 0) OR
	   (Str.Compare( FileName, FileData.OutFileName)  = 0) THEN
	   MsgString( FileName, 0 ) ;
	   PutResError( DuplicateOutputFile ) ;
	   RETURN FALSE ;
	ELSIF NOT OverWriteRule THEN
            (*RES OLD CHE 20
            The query filename "%0" already exists.  Please choose between N)ew name and O)verwrite file:
            =NO
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
		(*RES  OLD MSG 105       >>> From MAKBAS <<<
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
      END ;
      IF RuleModePresent THEN
	   Str.Append( FileName, '@');
	   Str.Append( FileName, RuleMode);
      END ;
      RETURN TRUE
   END VerifyRuleName;

(* m.s.  - copy of VerifyRuleName *)
PROCEDURE VerifyNodeCollName(VAR FileName : ARRAY OF CHAR; Extension : ARRAY OF CHAR): BOOLEAN;
   VAR
	Ch              : CHAR ;
	NodeCollModePresent : BOOLEAN ;
	ErrorMsg        : StrAny ;
	FileID          : XFileType ;
   BEGIN
      GetXlationType( FileName, NodeCollMode ) ;
      IF NodeCollMode[0] = 0C THEN
	 Str.Copy(NodeCollMode,FILEText);
	 NodeCollModePresent := FALSE
      ELSE
	 NodeCollModePresent := TRUE ;
      END ;
      IF ( NOT StandardizeFileName(FileName, Extension)) THEN
	 (*RES OLD MSG 295
	 "%0" cannot be used as the name of a file.
	 *)
	 MsgString( FileName, 0 );
	 PutResError( (*RES REM INS*) 295 ) ;
	 RETURN FALSE
      END;
      IF FileData.NodeCollocate AND Exist(FileName) THEN
	IF (Str.Compare( FileName, FileData.RuleFileName ) = 0) OR
	   (Str.Compare( FileName, FileData.OutFileName ) = 0 ) THEN
	   MsgString( FileName, 0 ) ;
	   PutResError( DuplicateOutputFile ) ;
	   RETURN FALSE ;
	ELSIF NOT OverWriteNodeColl THEN
            (*RES OLD CHE 30
            A node-collocate file named "%0" already exists.  Please choose between N)ew name, or O)verwrite file:
            =NO
            *)
	 MsgString( FileName, 0 );
	 ResAskUser( (*RES REM INS *) 30 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteNodeColl :=TRUE ;
	 ELSE
	    RETURN FALSE
	 END ;
	
	 (* next insure that "translation mode/table" exist *)
	 IF NOT XOpenOutput( FileName, Extension, NodeCollMode, FileID, ErrorMsg ) THEN
		(*RES  OLD MSG 105       >>> From MAKBAS <<<
		File Name %0: %1
		*)
		MsgString(FileName, 0);
		MsgString(ErrorMsg, 0);
		PutResError( (*RES REM INS*) 105 );
		XClose( FileID ) ;
		RETURN FALSE ;
	 ELSE
		XClose( FileID ) ;
	 END ;

       END;
      END ;
      IF NodeCollModePresent THEN
	   Str.Append( FileName, '@');
	   Str.Append( FileName, NodeCollMode);
      END ;

      RETURN TRUE
   END VerifyNodeCollName;

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
	 (*RES  OLD MSG 107      >>> From MAKBAS <<<
	 A translation specification "%0" is not permitted for database file.
	 It will be ignored.
	 *)
	 MsgString( Mode, 0 );
	 PutResWarning( (*RES REM INS*) 107 ) ;
      END ;
      IF DBName[0] = 0C THEN
	 GenRuleFile := TRUE ;
	 OutFileName[0] := 0C ;
	 RuleFileName[0] := 0C ;
	 NodeCollFileName[0] := 0C ;
	 FrequencyFileName[0] := 0C ;
         GenCollOut := TRUE ;
         NodeCollocate := TRUE ;
         MaximalPhrase := TRUE ;
	 OverWriteOut := FALSE ;
	 OverWriteRule := FALSE ;
	 OutputFormat := TRUE ;
	 OverlapCollocates := FALSE ;
	 RETURN
      ELSIF Str.Compare(OldDBName,DBName) = 0 THEN
	 ReDisplay := FALSE;
	 RETURN
      ELSIF ( NOT StandardizeFileName(DBName, TDBExtension)) THEN
	 (*RES  OLD MSG 272  >> from MERGEBAS <<
	 Textual DataBase Name %0 is improper
	 *)
	 MsgString(DBName,0);
	 PutResError( (*RES REM INS*) 272 );
	 ReEdit := TRUE;
	 RETURN
      END;
      IF NOT Exist(DBName) THEN
	 (*RES  OLD MSG 273  >> from MERGEBAS <<
	 Textual DataBase file named %0 does not exist.
	 *)
	 MsgString(DBName,0);
	 PutResError( (*RES REM INS*) 273 );
	 ReEdit := TRUE;
	 RETURN
      END;
      IF NOT CheckHeader( DBName ) THEN
	 ReEdit := TRUE;
	 RETURN
      END;
      Str.Copy(OldDBName,DBName);
      IF OutFileName[0] = 0C THEN
	 RemoveExtension( DBName, OutFileName ) ;
	 IF NOT VerifyOutName( OutFileName, MaximalColExtension ) THEN
	    ReEdit := TRUE;
	    MenuItem := 11 ;
	    RETURN ;
	 END ;
      END ;
      IF (RuleFileName[0] = 0C) AND GenRuleFile THEN
	 RemoveExtension( DBName, RuleFileName ) ;
	 IF NOT VerifyRuleName( RuleFileName, MaximalRuleExtension ) THEN
	    ReEdit := TRUE;
	    MenuItem := 16;
	    RETURN ;
	 END ;
      END ;
      IF (NodeCollFileName[0] = 0C) THEN
	 RemoveExtension( DBName, NodeCollFileName ) ;
	 IF NOT VerifyNodeCollName( NodeCollFileName, NodeCollExtension ) THEN
	    ReEdit := TRUE;
	    MenuItem := 14;
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
	TrimBlanks( Data^.OutFileName, Data^.OutFileName ) ;
	IF Str.Compare(OldOutFileName,Data^.OutFileName) = 0 THEN RETURN END;
	MenuItem := 11 ;
	Str.Copy( OldOutFileName , Data^.OutFileName );
	ReDisplay := TRUE;
        IF Data^.MaximalPhrase THEN
  	   IF NOT VerifyOutName(Data^.OutFileName,MaximalColExtension ) THEN ReEdit := TRUE END;
  	ELSIF NOT VerifyOutName(Data^.OutFileName, PermutedColExtension ) THEN ReEdit := TRUE
 	END;
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
	TrimBlanks( Data^.RuleFileName, Data^.RuleFileName ) ;
	IF Str.Compare(OldRuleFileName,Data^.RuleFileName) = 0 THEN RETURN END;
	IF NOT Data^.GenRuleFile AND (Data^.RuleFileName[0] <> 0C) THEN
	   Data^.RuleFileName := 0C ;
	   ReDisplay := TRUE ;
	   RETURN
	END ;
	MenuItem := 17 ;
	Str.Copy( OldRuleFileName , Data^.RuleFileName ) ;
	ReDisplay := TRUE;
	IF Data^.MaximalPhrase THEN
 	   IF NOT VerifyRuleName(Data^.RuleFileName, MaximalRuleExtension ) THEN ReEdit := TRUE ; END ;
        ELSIF NOT VerifyRuleName(Data^.RuleFileName, PermutedRuleExtension ) THEN ReEdit := TRUE ;
        END ;
   END VerifyRuleFile;


(* m.s. - copy of VerifyRuleFile *)
PROCEDURE VerifyNodeCollFile(Pntr:  ADDRESS;
	       VAR ReDisplay: BOOLEAN;
	       VAR ReEdit: BOOLEAN);
   VAR
	Data : POINTER TO FileDataType ;
   BEGIN
	Data := Pntr;
	ReDisplay := FALSE;
	ReEdit := FALSE;
	TrimBlanks( Data^.NodeCollFileName , Data^.NodeCollFileName ) ;
	IF Str.Compare(OldNodeCollFileName,Data^.NodeCollFileName) = 0 THEN RETURN END;
	IF NOT FileData.NodeCollocate AND (Data^.NodeCollFileName[0] <> 0C) THEN
	   Data^.NodeCollFileName := 0C ;
	   ReDisplay := TRUE ;
	   RETURN
	END ;
	MenuItem := 15 ;
	Str.Copy( OldNodeCollFileName , Data^.NodeCollFileName);
	ReDisplay := TRUE;
	IF NOT VerifyNodeCollName(Data^.NodeCollFileName, NodeCollExtension ) THEN ReEdit := TRUE END;
   END VerifyNodeCollFile;



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
	 (*RES  OLD MSG 175  >> from MAKBAS <<
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
	MenuItem  := 2 ;
	IF NOT VerifyTDA(Data^.TempDiskArea) THEN ReEdit := TRUE END;
   END CheckTDA;

(* m.s. *)
PROCEDURE CheckRefs( VAR RefList: ARRAY OF CHAR ) ;

    BEGIN
	 TrimBlanks( RefList, RefList ) ;
	 IF RefList[0] <> 0C THEN Boundaries := TRUE  END;
    END CheckRefs ;


PROCEDURE DoStartUp(VAR BaseWPtr:  TWB.WinType ): BOOLEAN;
VAR
   FrontMenu: MenuID;
   BaseWind:  WindowInfo;
   i,j:       CARDINAL;
   TC:        CHAR;
   FunctKey:  BOOLEAN;
   Done:      BOOLEAN;
   VerX,VerY,VerLen,DatX,DatY,DatLen: CARDINAL;
(*   m:         ARRAY[0..40] OF CHAR; *)
   DoMenuNow: BOOLEAN;
   HelpName:  ARRAY[0..4] OF CHAR;
   MaxSet:    BOOLEAN;
   IOresult:  CARDINAL ;
   ErrorMsg : StrAny ;
   RefListOK: BOOLEAN ; (* m.s. *)
   TDBInit:   BOOLEAN ; (* m.s. *)
   DefaultFunFileName : StrAny ;
   result  : CARDINAL ;
   DirName : StrAny ;

PROCEDURE HandleParameters;
   VAR
	plst,temp:  ParameterResult;
	str:         StrAny;
	ReDisplay:   BOOLEAN;
	ReEdit:      BOOLEAN;
	i,j:         CARDINAL;
	TryBatch:    BOOLEAN;
   BEGIN
	(* Syntax:  COLLGEN [-b] [-c D|P|N] [ [-n] | [-q <rule FN>] ] [-k <n>]
			[-m <min>] [-x max] [-w <TDA>] [-o <out FN>] <TDB file name> *)
	InitialParams;
	LegalParameter('b',FALSE);      (* batch switch                 *)
	LegalParameter('c',FALSE);       (* generate collocates to true Default *)
	LegalParameter('k',TRUE);       (* min no. of repeats to keep       *)
	LegalParameter('l',TRUE);       (* max no. of repeats to keep       *)
	LegalParameter('m',TRUE);       (* min no. of span words        *)
	LegalParameter('n',FALSE);      (* no rule file; default gen rule *)
	LegalParameter('p',TRUE);       (* out collate file name        *)
	LegalParameter('q',TRUE);       (* rule file name               *)
	LegalParameter('w',TRUE);       (* Temp Disk Area               *)
	LegalParameter('x',TRUE);       (* max no. of span words        *)
	LegalParameter('a',TRUE) ;      (* node collocate file name    m.s.  *)
	LegalParameter('f',FALSE);       (* report format default maximal phrase     m.s.   *)
	LegalParameter('s',TRUE);       (* boundaries m.s. *)
	LegalParameter('t',FALSE);       (* tabs m.s. *)
	LegalParameter('e',FALSE);       (* node collocate file;  m.s. *)
        LegalParameter('o',FALSE);       (* count overlapping collocates *)	

	GetEnv( 'TACTWRK', FileData.TempDiskArea);
	IF NOT VerifyTDA(FileData.TempDiskArea) THEN  FileData.TempDiskArea[0] := 0C  END ;

	i := 0;
	MaxSet := FALSE;
	TryBatch := FALSE;
	CASE GetParameters(plst,str) OF
	   GPSOk: (* do nothing right now *)
	   | GPSBadParameter:
		(*RES OLD MSG 297
		Collgen does not take parameter "%0".
		*)
		MsgString(str,0);
		PutResError( (*RES REM INS*) 297 );
		DoMenuNow := TRUE;
		RETURN
	   | GPSMissingValue:
		(*RES OLD MSG 298
		COLLGEN requires parameter "%0".
		*)
		MsgString(str,0);
		PutResError( (*RES REM INS*) 298 );
		DoMenuNow := TRUE;
		RETURN
	END;
	WHILE plst <> NIL DO
	   WITH plst^ DO
		CASE Code OF
		   ' ':
			IF i >= 1 THEN
			   (*RES OLD MSG 299
			   You gave too many input files as parameters to Collgen.
			   *)
			   PutResError( (*RES REM INS*) 299 );
			   RETURN;
			END;
			Str.Copy( FileData.DBName, Strg );
                        VerifyInFile( ADR(FileData), ReDisplay, ReEdit );
			IF ReEdit THEN
			   MenuItem := 1 ;
			   RETURN
			END;
			INC(i);
		   | 'B':
			TryBatch := TRUE;
		   | 'C':       (* output type: -c = no output        *)
                        FileData.GenCollOut := FALSE ;
		   | 'K':       (* min repeats to keep: -k <n>          *)
			FileData.RepeatMin := VAL(CARDINAL, Str.StrToCard(Strg,10,ReEdit));
			IF NOT ReEdit THEN RETURN END;
		   | 'L':       (* max repeats to keep: -k <n>          *)
			FileData.RepeatMax := VAL(CARDINAL, Str.StrToCard(Strg,10,ReEdit));
			FileData.TempMax := LONGINT( FileData.RepeatMax ) ;
			IF NOT ReEdit THEN RETURN END;
		   | 'M':       (* min span context: -m <n>             *)
			FileData.SpanMin := VAL(CARDINAL, Str.StrToCard(Strg,10,ReEdit));
			IF NOT ReEdit THEN RETURN END;
		   | 'X':       (* max span context: -m <n>             *)
			FileData.SpanMax := VAL(CARDINAL, Str.StrToCard(Strg,10,ReEdit));
			MaxSet := TRUE ;
			IF NOT ReEdit THEN RETURN END;
		   | 'N':       (* do NOT generate rule file *)
			FileData.GenRuleFile := FALSE ;
		   | 'P':       (* out collate file name:  -o <rule FN> *)
			Str.Copy( FileData.OutFileName, Strg );
			IF NOT VerifyOutName( FileData.OutFileName, MaximalColExtension ) THEN  RETURN  END ;
		   | 'Q':       (* rule file name:  -f <rule FN>        *)
			Str.Copy( FileData.RuleFileName, Strg );
			IF NOT VerifyRuleName( FileData.RuleFileName, MaximalRuleExtension ) THEN  RETURN  END ;
		   | 'W':       (* Temp Disk Area:  -w <TDA>            *)
			Str.Copy( FileData.TempDiskArea, Strg );
			CheckTDA( ADR(FileData), ReDisplay, ReEdit );
			IF ReEdit THEN RETURN END;
		   | 'E':       (* generate node collocate file *)
			FileData.NodeCollocate := FALSE ;
		   | 'A':       (* m.s - node collocate file name:  -a <node collocate FN>      *)
			Str.Copy( FileData.NodeCollFileName, Strg );
			IF NOT VerifyNodeCollName( FileData.NodeCollFileName, NodeCollExtension ) THEN  RETURN  END ;
		   |  'F':      (* Maximal phrases only = false        m.s.   *)
			FileData.MaximalPhrase := FALSE ;
                   | 'O' :  (* m.s. - allow overlapping collocates *)
                        FileData.OverlapCollocates := TRUE ;
                   | 'T' : (* output format *)
                        FileData.OutputFormat := Spaces ;
		   | 'S' :
			Str.Copy( FileData.RefsNamesList, Strg );
			CheckRefs( FileData.RefsNamesList ) ; (* strips blanks and sets boundaries variable *)
			RefListOK := MergeRefList() ;
			IF NOT RefListOK THEN RETURN END ;
		   ELSE
			ProgramErrorAndHalt('Unexpected ParameterData Code found');
		END;
	   END;
	   temp := plst^.Next;
	   DEALLOCATE(plst,plst^.Size);
	   plst := temp;
	END;
	DoMenuNow := (NOT TryBatch) OR (FileData.DBName[0] = 0C);
   END HandleParameters;

BEGIN   (* DoStartUp *)
   ExitList[0] := ASCII.rs;
   ExitList[1] := 0C ;
   TermList[0] := PCKey.F9;
   TermList[1] := 0C ;
   FileData.RefsNamesList[0] := 0C ; (* m.s. *)
   HelpName := 'HELP';
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
     CharFieldProc(TempDiskArea, CheckTDA ) ;
     CardField(SpanMin);
     CardField(SpanMax);
     CardField(RepeatMin);
     LongIntField(TempMax) ;
     CharField( RefsNamesList ); (* m.s. *)
     Switches(OutputFormat) ;(* m.s. *)
        SwitchValue(Tabs) ;
        SwitchValue(Spaces) ;
     Switches(GenCollOut);
	 SwitchValue(TRUE);
	 SwitchValue(FALSE);
     CharFieldProc(OutFileName,VerifyOutFile);
     Switches(MaximalPhrase);     (* m.s. *)
	 SwitchValue(TRUE);
	 SwitchValue(FALSE);
     Switches(NodeCollocate);
	 SwitchValue(TRUE);
	 SwitchValue(FALSE);
     Switches(OverlapCollocates);
	 SwitchValue(TRUE);
	 SwitchValue(FALSE);
     CharFieldProc(NodeCollFileName,VerifyNodeCollFile);
     Switches(GenRuleFile);
	 SwitchValue(TRUE);
	 SwitchValue(FALSE);
     CharFieldProc(RuleFileName,VerifyRuleFile);
   END;
   MakeMenu( MainMenuRes, FrontMenu);
   GetFieldInfo(FrontMenu,22,VerX,VerY,VerLen);
   GetFieldInfo(FrontMenu,23,DatX,DatY,DatLen);

   PushNewWindow(BaseWind, BaseWPtr, DummyInit);
   ShowFixedText(BaseWPtr,FrontMenu,0,0);
(*   TWB.GotoXY((CopyWXPos - 17),CopyWYPos); (* was -12 *)
   TWB.ClrEol;
(* TWB.WrStr('(c) John Bradley, Lidio Presutti 1989'); *)
(*   TWB.WrStr('Copyright (c) 1992 by John Bradley, Lidio Presutti and Michael Stairs'); *)
   TWB.WrStr('Copyright (c) 1994 by TACT Group, University of Toronto') ;
*)
   WriteScreenField( BaseWPtr, VerLen, VerX, VerY,
			   SystemVersion, RegularAttr, TRUE );
   WriteScreenField( BaseWPtr, DatLen, DatX, DatY,
			   SystemVersionDate, RegularAttr, TRUE );

   WITH FileData DO
      DBName[0]    := 0C;
      OutFileName[0]  := 0C;
      NodeCollFileName[0] := 0C ;
      TempDiskArea[0] := 0C;
      SpanMin      := 2 ;
      SpanMax      := 2 ;
      RepeatMin  := 2 ;
      RepeatMax  := MAX(CARDINAL) ;
      GenCollOut   := TRUE ;
      GenRuleFile  := TRUE ;
      RuleFileName[0] := 0C ;
      FrequencyFileName[0] := 0C ;
      NodeCollocate := TRUE ; (* m.s. *)
      MaximalPhrase := TRUE ; (* m.s.*)
      OutputFormat := Tabs ; (* m.s. - Apr 94 *)

      OverlapCollocates := FALSE ; (* m.s. *)
      TempMax := MAX(CARDINAL) ;
   END;
   CollMode[0] := 0C ;
   RuleMode[0] := 0C ;
   Boundaries := FALSE ; (* m.s. *)

   OldOutFileName[0] := 0C ;
   OldRuleFileName[0] := 0C ;
   OldNodeCollFileName[0] := 0C ;
   MenuItem := 0;
   DoMenuNow := TRUE;
   CreateOutFile := TRUE ;
   OverWriteOut  := FALSE ;
   OverWriteRule := FALSE ;
   OverWriteNodeColl := FALSE ;
   CollModePresent := FALSE ;
   RefListOK       := FALSE ; (* m.s. *)
   TDBInit         := FALSE ; (* m.s. *)

   HandleParameters;
   IF NOT MaxSet THEN  FileData.SpanMax := FileData.SpanMin  END ;
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
	 MenuItem := 1 ;
	 (*RES OLD MSG 296
	 Please give the Input Database file name.
	 *)
	 PutResError( (*RES REM INS*) 296 ) ;
      END ;
      IF NOT TDBInit THEN
	  IF NOT InitializeFromDB( FileData.DBName ) THEN
	       RETURN FALSE;
	  ELSE
	       TDBInit := TRUE ;
	  END ;
      END ;
      IF (FileData.OutFileName[0] = 0C) AND (FileData.GenCollOut = TRUE) THEN
	 DoMenuNow := TRUE;
	 MenuItem := 10 ;
	 (*RES OLD MSG 302
	 The Fixed Phrase File Name must be given.
	 *)
	 PutResError( (*RES REM INS*) 302 ) ;
      END ;
      IF (FileData.SpanMin < 2) OR (FileData.SpanMax < 2) THEN
	 DoMenuNow := TRUE;
	 IF FileData.SpanMin < 2 THEN
	    MenuItem := 3 ;
	 ELSE
	    MenuItem := 4 ;
	 END ;
	 (*RES OLD MSG 303
	 Span Context must have a value of 2 or greater.
	 *)
	 PutResError( (*RES REM INS*) 303 ) ;
      END ;
      IF (FileData.RepeatMin = 0) OR (FileData.TempMax = 0) THEN
	 DoMenuNow := TRUE;
         IF FileData.TempMax = 0 THEN
   	   MenuItem := 6 ;
   	 ELSE
   	   MenuItem:= 5 ;
   	 END ;
	 (*RES OLD MSG 306
	 "Number of repetitions to keep" has a minimum value of 1.
	 *)
	 PutResError( (*RES REM INS*) 306 ) ;
      END ;
      IF NOT RefListOK AND TDBInit THEN
	 CheckRefs( FileData.RefsNamesList ) ; (* strips blanks and sets boundaries variable *)
	 RefListOK := MergeRefList() ;
	 IF NOT RefListOK THEN
	    DoMenuNow := TRUE ;
	    MenuItem  := 7 ;
	 END ;
      END ;
      IF FileData.NodeCollocate AND (FileData.NodeCollFileName[0] = 0C) THEN
	 DoMenuNow := TRUE;
	 MenuItem := 15 ;
	 (*RES OLD MSG 458
	 Please give the Node-Collocate File Name.
	 *)
	 PutResError( (*RES REM INS*) 458 ) ;
      END ;
      IF FileData.GenRuleFile AND (FileData.RuleFileName[0] = 0C) THEN
	 DoMenuNow := TRUE;
	 MenuItem := 17 ;
	 (*RES OLD MSG 304
	 Please give the Query File Name.
	 *)
	 PutResError( (*RES REM INS*) 304 ) ;
      END ;
      IF ( NOT FileData.GenRuleFile) AND (NOT FileData.GenCollOut) AND
	 ( NOT FileData.NodeCollocate (* m.s. *) ) THEN
	 DoMenuNow := TRUE;
	 MenuItem := 9 ;
	 (*RES OLD MSG 459
	 Please request at least one type of output (Queries, Fixed Phrases, or
	 Node-Collocate Pairs).
	 *)
	 PutResError( (*RES REM INS*) 459 ) ;
      END ;
      IF FileData.TempMax > MAX(CARDINAL) THEN
        FileData.RepeatMax := MAX(CARDINAL) ;
        FileData.TempMax := MAX(CARDINAL) ;
      ELSE
        FileData.RepeatMax := CARDINAL(FileData.TempMax) ;
      END ;
      IF FileData.SpanMin > FileData.SpanMax THEN    (* switch order ?? *)
	 i := FileData.SpanMin ;
	 FileData.SpanMin := FileData.SpanMax ;
	 FileData.SpanMax := i ;
      END ;
      IF FileData.RepeatMax < FileData.RepeatMin THEN  (* switch order ?? *)
         i := FileData.RepeatMin ;
         FileData.RepeatMin := FileData.RepeatMax ;
         FileData.RepeatMax := i ;
         FileData.TempMax := LONGINT(i) ;
      END ;

   UNTIL NOT DoMenuNow ;

   IF NOT FileData.GenRuleFile THEN  FileData.RuleFileName[0] := 0C  END ;
   IF NOT FileData.NodeCollocate THEN  FileData.NodeCollFileName[0] := 0C  END ;
   IF NOT FileData.GenCollOut AND (NOT FileData.GenRuleFile)
       THEN FileData.OutFileName[0] := 0C  END ;

   ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);

   IF FileData.GenCollOut OR (FileData.MaximalPhrase AND FileData.GenRuleFile) THEN
	IF NOT CollModePresent THEN
	   Str.Copy(CollMode,FILEText);
	END ;
        IF (FileData.MaximalPhrase AND NOT XOpenOutput( FileData.OutFileName, MaximalColExtension, CollMode, OutFileID, ErrorMsg ))
	     OR ((NOT FileData.MaximalPhrase) AND NOT XOpenOutput( FileData.OutFileName, PermutedColExtension, CollMode, OutFileID, ErrorMsg ))
	   THEN
	      (* something wrong ... *)
	      MsgString( FileData.OutFileName, 0 ) ;
	      MsgString( ErrorMsg, 0 ) ;
	      PutResError( FileHeaderResource ) ;
	      XClose( OutFileID ) ;
	      RETURN FALSE ;
	END ;
   END ;
   IF FileData.GenRuleFile THEN
	IF (FileData.MaximalPhrase AND NOT XOpenOutput( FileData.RuleFileName, MaximalRuleExtension, RuleMode, RuleFileID, ErrorMsg ))
	  OR ((NOT FileData.MaximalPhrase) AND NOT XOpenOutput( FileData.RuleFileName, PermutedRuleExtension, RuleMode, RuleFileID, ErrorMsg )) THEN
	   (* something wrong ... *)
	   MsgString( FileData.RuleFileName, 0 ) ;
	   MsgString( ErrorMsg, 0 ) ;
	   PutResError( FileHeaderResource ) ;
	   XClose( RuleFileID ) ;
	   RETURN FALSE ;
	END ;
   END ;
   IF FileData.NodeCollocate THEN
	IF NOT XOpenOutput( FileData.NodeCollFileName, NodeCollExtension, NodeCollMode, NodeCollFileID, ErrorMsg ) THEN
	   (* something wrong ... *)
	   MsgString( FileData.NodeCollFileName, 0 ) ;
	   MsgString( ErrorMsg, 0 ) ;
	   PutResError( FileHeaderResource ) ;
	   XClose( NodeCollFileID ) ;
	   RETURN FALSE ;
	END ;
   END ;	
   FunctionWords := TRUE ;
   FunctionType := Include ;
   RemoveExtension( FileData.DBName, FileData.FunctionFileName ) ;
   Str.Append( FileData.FunctionFileName, IncludeExtension ) ;
   IF NOT XOpenInput( FileData.FunctionFileName, IncludeExtension, NodeCollMode, FunctionFileID, ErrorMsg ) THEN
      (* include file doesn't exist use exclude file *)
      FunctionType := Exclude ;
      RemoveExtension( FileData.DBName, FileData.FunctionFileName ) ;
      IF NOT XOpenInput( FileData.FunctionFileName, FunctionExtension, NodeCollMode, FunctionFileID, ErrorMsg ) THEN
        (* file not found try to use default *)
        FunctionWords := FALSE ;
        Str.Concat( DefaultFunFileName, DefaultFunctionFileName, IncludeExtension ) ;
        IF FindFileInList( StandardSearchList, DefaultFunFileName, DirName ) THEN
           Str.Prepend( DefaultFunFileName, DirName ) ;
           FunctionType := Include ;
           IF XOpenInput( DefaultFunFileName, IncludeExtension, NodeCollMode, FunctionFileID, ErrorMsg ) THEN
              FunctionWords := TRUE ;
           END ;
        ELSE
           Str.Concat( DefaultFunFileName, DefaultFunctionFileName, FunctionExtension ) ;
           IF FindFileInList( StandardSearchList, DefaultFunFileName, DirName ) THEN
             Str.Prepend( DefaultFunFileName, DirName ) ;
             FunctionType := Exclude ;
             IF XOpenInput( DefaultFunFileName, FunctionExtension, NodeCollMode, FunctionFileID, ErrorMsg ) THEN
                FunctionWords := TRUE ;
             END ;
           END ;
        END ;
      END ;
   END ;
   IF (NOT FileData.GenCollOut) AND (NOT FileData.GenRuleFile) THEN
      (* only generate node collocate file *)
      NodeCollocateOnly := TRUE ;
   END ;
   IF FileData.MaximalPhrase THEN
        IF FileData.GenCollOut THEN
   	   RemoveExtension( FileData.OutFileName, FileData.FrequencyFileName ) ;
   	ELSIF FileData.GenRuleFile THEN
   	   RemoveExtension( FileData.RuleFileName, FileData.FrequencyFileName ) ;
   	ELSE
   	   RemoveExtension( FileData.NodeCollFileName, FileData.FrequencyFileName ) ;
   	END;
	Str.Append( FileData.FrequencyFileName, FrequencyExtension ) ;
   END ;
   TWB.SetPalette(BaseWPtr, ActiveAttrib);
   DestroyMenu(FrontMenu);
   TerminatePrintModule;
   RETURN TRUE;

END DoStartUp;

BEGIN
  NodeCollocateOnly := FALSE ;
END StartUp .
