IMPLEMENTATION MODULE StartUp ;

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
  (* Procs *)  CurrentDrive, SelectDrive, CurrentDirectory, ChangeDirectory ;

FROM TDBInit IMPORT CheckTDBHeader, InitializeTDB;

(*RES OLD MNU 57

                  TACTStat Version %4____ %5_____________________

                Statistical Generator for the TACT system
                   [Word/Letter Type/Token Statistics]



   Input .TDB Filename:  %0_______________________________________________

   Direct Results:       To Disk: %|1  To Printer: %|2

   Output Filename:      %3_______________________________________________



______________________________________________________________________________
   F1:    Help                      F9:   RUN, generate statistical results
   F6:    Credits                  F10:  QUIT, without generating statistics
*)
CONST
   MainMenuRes = (*RES REM INS*) 57 ;

   FileHeaderResource = (*RES REM INS*) 113 ;	(* >>> From MAKBAS: SetupFil.MOD <<< *)

   CopyWYPos    = 16;
   CopyWXPos    = 0;

   StatExtension = '.STA';

VAR
   OldDBName	  : FileNameType ;
   OldOutFileName : FileNameType ;
   MenuItem	  : CARDINAL ;
   CreateOutFile  : BOOLEAN ;	(* when FALSE its an FIO.Append *)
   OverWriteOut   : BOOLEAN ;
   StatMode	  : ARRAY[0..12] OF CHAR ;
   ExitList	  : ARRAY[0..1] OF CHAR;
   TermList	  : ARRAY[0..1] OF CHAR;
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
	Ch	 : CHAR ;
	Mode	 : ARRAY[0..12] OF CHAR ;
	ErrorMsg : StrAny ;
	FileID	 : XFileType ;
   BEGIN
      GetXlationType( FileName, StatMode ) ;
      IF StatMode[0] = 0C THEN
	 StatModePresent := FALSE
      ELSE
	 StatModePresent := TRUE ;
      END ;
      IF ( NOT StandardizeFileName(FileName, Extension)) THEN
         (*RES OLD MSG 295
         "%0" cannot be used as the name of a file.
         *)
         MsgString( FileName, 0 );
         PutResError( (*RES REM INS*) 295 ) ;
         RETURN FALSE
      END;
      IF (FileData.GenStatOut = OutToDisk) AND Exist(FileName) AND NOT OverWriteOut THEN
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
	 IF NOT StatModePresent THEN
		Str.Copy(StatMode,FILEText);
	 END ;
	 IF NOT XOpenOutput( FileName, Extension, StatMode, FileID, ErrorMsg ) THEN
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
      IF StatModePresent THEN
	   Str.Append( FileName, '@');
	   Str.Append( FileName, StatMode);
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
         (*RES OLD MSG 107	>>> From MAKBAS <<<
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
      IF (Str.Compare( OldDBName, DBName) <> 0) AND
         (NOT CheckTDBHeader( DBName )) THEN
         ReEdit := TRUE;
         RETURN
      END;
      Str.Copy(OldDBName,DBName);
      IF (NOT ProcessParameters)  AND (OutFileName[0] = 0C) THEN
         RemoveExtension( DBName, OutFileName ) ;
         IF NOT VerifyOutName( OutFileName, StatExtension ) THEN
	    ReEdit := TRUE;
	    MenuItem := 3 ;
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
	MenuItem := 3 ;
	OldOutFileName := Data^.OutFileName;
	ReDisplay := TRUE;
	IF NOT VerifyOutName(Data^.OutFileName, StatExtension ) THEN ReEdit := TRUE END;
   END VerifyOutFile;

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
	(* Syntax:  TACTSTAT [-b] [-c D|P] <TDB file name> <output fn >*)
	InitialParams;
	LegalParameter('b',FALSE);	(* batch switch			*)
	LegalParameter('c',TRUE);	(* generate TACTSTAT to D=disk, P=printer *)
	i := 0;
	TryBatch := FALSE;
	ProcessParameters := TRUE ;
	CASE GetParameters(plst,str) OF
	   GPSOk: (* do nothing right now *)
	   | GPSBadParameter:
		(*RES OLD MSG 517
		Parameter "%0" cannot be specified for TACTStat.
		*)
		MsgString(str,0);
		PutResError( (*RES REM INS*) 517 );
		DoMenuNow := TRUE;
		RETURN
	   | GPSMissingValue:
		(*RES OLD MSG 518
		Parameter "%0" requires a parameter for TACTStat.
		*)
		MsgString(str,0);
		PutResError( (*RES REM INS*) 518 );
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
                            IF NOT VerifyOutName(FileData.OutFileName, StatExtension ) THEN
                               MenuItem := 7;
                               ReEdit := TRUE ;
                               RETURN
                            END ;
			ELSE
			   (*RES OLD MSG 519
			   Too many input files were given as parameters to TACTStat.
			   *)
			   PutResError( (*RES REM INS*) 519 );
			   HALT;
			END; 	
                        INC(i);
		   | 'B':
			TryBatch := TRUE;
		   | 'C':	(* output type: -c D|P		*)
			CASE CAP(Strg[0]) OF
			  'D' :  FileData.GenStatOut := OutToDisk |
			  'P' :  FileData.GenStatOut := OutToPrinter
			  ELSE
			      RETURN
			END ;
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

BEGIN	(* DoStartUp *)
   ExitList[0] := ASCII.rs;
   ExitList[1] := 0C ;
   TermList[0] := PCKey.F9;
   TermList[1] := 0C ;
   HelpName := 'HELP';
   BaseWPtr := NIL ; (* m.s. *)
   InitialPrintModule(HelpName, TermList, ExitList, DummyHandleFNField);
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
     Switches(GenStatOut);
         SwitchValue(OutToDisk);
         SwitchValue(OutToPrinter);
     CharFieldProc(OutFileName,VerifyOutFile);
(*   CharField(Alphabet[0]) ;
     CharField(Alphabet[1]) ; *)
   END;
   MakeMenu( MainMenuRes, FrontMenu);
   GetFieldInfo(FrontMenu, 4,VerX,VerY,VerLen);
   GetFieldInfo(FrontMenu, 5,DatX,DatY,DatLen);

   PushNewWindow(BaseWind, BaseWPtr, DummyInit);
   ShowFixedText(BaseWPtr,FrontMenu,0,0);

   TWB.GotoXY(0, 21);
   TWB.ClrEol;
   TWB.WrStr('               Copyright (c) 1995 TACT Group, University of Toronto ') ;
   TWB.WrLn ;

   WriteScreenField( BaseWPtr, VerLen, VerX, VerY,
                           SystemVersion, RegularAttr, TRUE );

   WriteScreenField( BaseWPtr, DatLen, DatX, DatY,
                           SystemVersionDate, RegularAttr, TRUE );

   WITH FileData DO
      DBName	   := 0C;
      OutFileName  := 0C;
      GenStatOut   := OutToDisk ;
      Alphabet[0]  := 0C;
      Alphabet[1]  := 0C;
   END;
   StatMode := 0C ;

   MenuItem := 0;
   DoMenuNow := TRUE;
   CreateOutFile := TRUE ;
   OverWriteOut  := FALSE ;
   StatModePresent := FALSE ;
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
      IF (FileData.OutFileName[0] = 0C) AND (FileData.GenStatOut = OutToDisk) THEN
         DoMenuNow := TRUE;
	 MenuItem := 3 ;
	 (*RES OLD MSG 520
	 The file name must be given.
	 *)
	 PutResError( (*RES REM INS*) 520 ) ;
      END ;
   UNTIL NOT DoMenuNow ;

   IF FileData.GenStatOut <> OutToDisk THEN FileData.OutFileName[0] := 0C  END ;

   ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);

   IF NOT InitializeTDB( FileData.DBName ) THEN
	RETURN FALSE;
   END ;

   IF FileData.GenStatOut = OutToDisk THEN
	IF NOT StatModePresent THEN
	   Str.Copy(StatMode,FILEText);
	END ;
	IF CreateOutFile THEN
	   IF NOT XOpenOutput( FileData.OutFileName, StatExtension, StatMode, OutFileID, ErrorMsg ) THEN
	      (* something wrong ... *)
	      MsgString( FileData.OutFileName, 0 ) ;
	      MsgString( ErrorMsg, 0 ) ;
	      PutResError( FileHeaderResource ) ;
	      XClose( OutFileID ) ;
	      RETURN FALSE ;
	   END ;
	ELSE
	   IF NOT XAppend( FileData.OutFileName, StatExtension, StatMode, OutFileID, ErrorMsg ) THEN
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
