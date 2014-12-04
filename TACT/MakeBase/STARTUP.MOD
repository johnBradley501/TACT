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

FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM HyperDataModel IMPORT MaxDBTitleLength;
FROM GlobalDefs IMPORT FileNameType, SystemVersion, SystemVersionDate ;
IMPORT TWB, Str ;
IMPORT ASCII ;
IMPORT PCKey ;
FROM SYSTEM    IMPORT ADDRESS ;
FROM SetupFile IMPORT
  (* vars   *) SetupWriteNeeded, SetupMessageNeeded,
  (* Procs  *) ReadSetupFile, WriteSetupFile, VerifySetupFile ;
FROM AlphaPanel IMPORT AlphaInfo, NoAlphaLines, NoRetDiLines, NoNonDiLines;
FROM Utils     IMPORT
  (* procs  *) RemoveExtension, Exist, StandardizeFileName, GetXlationType,
		TimeDelay, TrimBlanks, GetEnv ;
FROM GetParams IMPORT
  (* types *) GetParametersStatus, ParameterResult, ParameterData,
  (* procs *) LegalParameter, GetParameters, InitialParams;
FROM Lists IMPORT
  (* type   *) ListPointer,
  (* procs  *) AddBelow, MoveDown, SetToTop ;
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
FROM ScrollingMenu IMPORT
  (* proc   *) DoScrollingMenu;
FROM Windows  IMPORT
  (* Const  *) RegularAttr,
  (* Vars   *) DialogAttrib, InActiveAttrib,
  (* Procs  *) GetRidOfWindow ;
FROM ErrorBase IMPORT
  (* Procs  *) ProgramErrorAndHalt;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo, WindowInfoPtr,
  (* procs *) PushNewWindow, DummyInit;
FROM KeyTranslation IMPORT
  (* Procs *) WriteScreenField, FILEText;
FROM ResMenus IMPORT
  (* type   *) MenuID,
  (* proc   *) StartMenu, CharFieldProc, CharField, MakeMenu, DestroyMenu,
               GetFieldInfo, ShowFixedText, ShowMenu, DoMenu;
FROM ResMessages IMPORT
  (* proc *)  MsgString, MsgCard, MsgInt, MsgLongInt, GetResMessage,
              PutResError, PutResWarning, PutResMessage,
              ResAskUser;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) ReleaseCollection;

FROM GlobalDefs IMPORT
  (* Type  *)  StrAny,
  (* Const *)  TXTExtension, TDBExtension;

FROM AlphaPanel IMPORT  GetAlphaPanel , DiscardAlphaMenu;
FROM Translations IMPORT
  (* Types *)  XFileType, CurrentModeType, XlateStrAny,
  (* vars  *)  Scr2Int,
  (* Procs *)  XOpenInput, XClose, XlateLine ;
FROM XlatUserInput IMPORT
  (* Types *)  ReshowMenuType,
  (* Procs *)  InitXlateLists, FreeXlateLists, BuildAlphabetXlate,
               BuildSpecialCharXlate, BuildStructInfoXlate, VerifyRefTemplate;
FROM DiskDirectory IMPORT
  (* Procs *)  CurrentDrive, SelectDrive, CurrentDirectory, ChangeDirectory,
               ChangeTDADirectory ;
(*
FROM FIO IMPORT
   (* Types *) FileAttr, DirEntry, PathStr, directory,
   (* Procs *) ReadFirstEntry ;
*)
FROM Utils IMPORT
   (* Procs *) UpcaseStr, TrimBlanks ;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, PopHelpItem, ShowCredit;
FROM ProcTextSource IMPORT DisplayText;
FROM PrintModule IMPORT InitialPrintModule, TerminatePrintModule;

CONST
   CopyWYPos    = 16;
   CopyWXPos    = 0;

   SpecialCharsHelpRes = 28;
   StructInfoHelpRes = 29;
   CreditID = 68 ; (* m.s. - apr 94 *)
TYPE
   FrontActions = (Front, Alpha, SpecChar, Struct, WriteSetup, WriteDefault,
                   Verify, Run);
   FileDataPntr = POINTER TO FileDataType;

VAR
   OldList:   POINTER TO FileDataType;
   rc      :  CARDINAL;
   FrontMenu: MenuID;
   FrontAct:  FrontActions;
   FunctTerm: ARRAY[0..6] OF CHAR;
   KeyTerm:   ARRAY[0..0] OF CHAR;
   HelpName:  ARRAY[0..4] OF CHAR;
   ScreenMenuDefined: BOOLEAN;
   BaseWind:  WindowInfo;
   BaseWPtr:  TWB.WinType;
   OverWriteOut : BOOLEAN ; (* m.s. *)

PROCEDURE DummyHandleFNField(VAR Field:     ARRAY OF CHAR;
				 Exten:     ARRAY OF CHAR;
			     VAR ReDisplay: BOOLEAN;
			     VAR ReEdit:    BOOLEAN);
   BEGIN
   END DummyHandleFNField ;

PROCEDURE VerifyDataBase(VAR FileName: ARRAY OF CHAR): BOOLEAN;
   VAR
      Mode : ARRAY[0..12] OF CHAR ;
      Ch : CHAR ;
   BEGIN
      GetXlationType( FileName, Mode ) ;
      IF Mode[0] <> 0C THEN
         (*RES OLD MSG 107
         The translation specification "%0" is not permitted for the database file
         and will be ignored.
         *)
         MsgString( Mode, 0 );
         PutResWarning( (*RES REM INS*) 107 ) ;
      END ;
      IF ( NOT StandardizeFileName(FileName, TDBExtension)) THEN
         (*RES OLD MSG 108
         You cannot use "%0" as the name of a .TDB file.
         *)
         MsgString( FileName, 0 );
         PutResError( (*RES REM INS*) 108 ) ;
         RETURN FALSE
      END;
      IF Exist( FileName) AND NOT OverWriteOut THEN (* m.s. - provide user with choice now *)
	 (*RES OLD CHE 47
	 The .TDB database "%0" already exists. Please choose
	 between N)ew name and O)verwrite file:
	 = N O
	 *)
	 MsgString( FileName, 0 );
	 ResAskUser( (*RES REM INS *) 47 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	 ELSE
	    OverWriteOut := FALSE ;
	    RETURN FALSE
	 END ;
      END ;	
      RETURN TRUE
   END VerifyDataBase;

PROCEDURE MakeDefaultFileNames(VAR FileData: FileDataType): CARDINAL;
   VAR
      Dummy: BOOLEAN;
   BEGIN
      WITH FileData DO
         IF SetupFileName[0] = 0C THEN
            RemoveExtension( InputFileName, SetupFileName );
            Dummy := VerifySetupFile( SetupFileName );
         END;
         IF DataBaseName[0] = 0C THEN
            RemoveExtension( InputFileName, DataBaseName );
            IF NOT VerifyDataBase( DataBaseName ) THEN RETURN 3 END;
         END;
      END;
      RETURN 1;
   END MakeDefaultFileNames;

PROCEDURE VerifyInputFile(VAR FileName: ARRAY OF CHAR): BOOLEAN;
   VAR
      Mode     : ARRAY[0..12] OF CHAR ;
      ErrorMsg : StrAny ;
      FileID   : XFileType ;
      NoMode   : BOOLEAN ;
   BEGIN
      GetXlationType( FileName, Mode ) ;
      IF ( NOT StandardizeFileName(FileName, TXTExtension)) THEN
         (*RES OLD MSG 104
         You cannot use "%0" as the name of a file.
         *)
         MsgString(FileName,0);
         PutResError( (*RES REM INS*) 104 );
      ELSE
         IF Exist(FileName) THEN
            (* next insure that "translation mode/table" exist *)
            NoMode := FALSE ;
            IF Mode[0] = 0C THEN
               NoMode := TRUE ;
               Str.Copy(Mode,FILEText);
            END ;
            IF NOT XOpenInput( FileName, TXTExtension, Mode, FileID, ErrorMsg ) THEN
               (*RES OLD MSG 105
               File name %0: %1.
               *)
               MsgString(FileName, 0);
               MsgString(ErrorMsg, 0);
               PutResError( (*RES REM INS*) 105 );
               XClose( FileID ) ;
            ELSE
               XClose( FileID ) ;
               IF NOT NoMode THEN
                  Str.Append( FileName, '@');
                  Str.Append( FileName, Mode);
               END ;
               RETURN TRUE ;
            END
         ELSE
            (*RES OLD MSG 106
            File %0 does not exist.
            *)
            MsgString(FileName, 0);
            PutResError( (*RES REM INS*) 106 );
         END;
      END;
      IF Mode[0] <> 0C THEN
         Str.Append( FileName, '@' );
         Str.Append( FileName, Mode );
      END ;
      RETURN FALSE
   END VerifyInputFile;

PROCEDURE VerifyTDA( VAR TempDiskArea : ARRAY OF CHAR): BOOLEAN;
   VAR
      TDADone	: BOOLEAN ;
      Done	: BOOLEAN ;
      drive	: CHAR ;
      dir	: StrAny ;
      TDALen	: CARDINAL ;
      I		: CARDINAL ;
      (* Ent   : DirEntry ; *)
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
      (* note: "CurrentDirectory" doesnot return leading "\", need it for CHDIR *)
      IF dir[0] <> '\' THEN
	 FOR I := Str.Length(dir) TO 1 BY -1 DO
		dir[I] := dir[I-1] ;
	 END ;
	 dir[0] := '\' ;
     END ;

      (* see if drive/path exists *)
      ChangeDirectory( TempDiskArea, TDADone ) ;

      IF TDADone THEN (* m.s. - change extender swap drive *)
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
         (*RES OLD MSG 175
         The drive/path specification for Temporary File Area "%0" is invalid.
         *)
         MsgString( TempDiskArea, 0 );
         PutResWarning( (*RES REM INS*) 175 ) ;
         RETURN FALSE
      END;
   END VerifyTDA ;

PROCEDURE CheckInputFile(Pntr:  ADDRESS;
                         VAR ReDisplay: BOOLEAN;
                         VAR ReEdit: BOOLEAN);
VAR
   Data:  FileDataPntr;
BEGIN
   Data := Pntr;
   ReDisplay := FALSE;
   ReEdit := FALSE;
   IF Str.Compare(OldList^.InputFileName,Data^.InputFileName) = 0 THEN RETURN END;
   IF MakeDefaultFileNames(Data^) <> 1 THEN ReEdit := TRUE END;
   OldList^ := Data^;
   ReDisplay := TRUE;
   IF NOT VerifyInputFile(Data^.InputFileName) THEN ReEdit := TRUE END;
END CheckInputFile;

PROCEDURE CheckSetupFile(Pntr:  ADDRESS;
                         VAR ReDisplay: BOOLEAN;
                         VAR ReEdit: BOOLEAN);
VAR
   Data:  FileDataPntr;
BEGIN
   Data := Pntr;
   ReDisplay := FALSE;
   ReEdit := FALSE;
   IF Str.Compare(OldList^.SetupFileName,Data^.SetupFileName) = 0 THEN RETURN END;
   OldList^.SetupFileName := Data^.SetupFileName;
   ReDisplay := TRUE;
   IF NOT VerifySetupFile(Data^.SetupFileName) THEN ReEdit := TRUE END;
END CheckSetupFile;

PROCEDURE CheckDataBase(Pntr:  ADDRESS;
                    VAR ReDisplay: BOOLEAN;
                    VAR ReEdit: BOOLEAN);
VAR
   Data:  FileDataPntr;
BEGIN
   Data := Pntr;
   ReDisplay := FALSE;
   ReEdit := FALSE;
   IF Str.Compare(OldList^.DataBaseName,Data^.DataBaseName) = 0 THEN RETURN END;
   OldList^.DataBaseName := Data^.DataBaseName;
   IF NOT VerifyDataBase(Data^.DataBaseName) THEN
       ReDisplay := TRUE;
       ReEdit := TRUE;
   END;
END CheckDataBase;

PROCEDURE CheckTDA(Pntr:  ADDRESS;
               VAR ReDisplay: BOOLEAN;
               VAR ReEdit: BOOLEAN);
VAR
   Data:  FileDataPntr;
BEGIN
   Data := Pntr;
   ReDisplay := FALSE;
   ReEdit := FALSE;
   IF Str.Compare(OldList^.TempDiskArea,Data^.TempDiskArea) = 0 THEN RETURN END;
   OldList^.TempDiskArea := Data^.TempDiskArea;
   ReDisplay := TRUE;
   IF NOT VerifyTDA(Data^.TempDiskArea) THEN ReEdit := TRUE END;
END CheckTDA;

PROCEDURE MarkTitleChange(Pntr:  ADDRESS;
                      VAR ReDisplay: BOOLEAN;
                      VAR ReEdit: BOOLEAN);
VAR
   Data:  FileDataPntr;
BEGIN
   Data := Pntr;
   ReDisplay := FALSE;
   ReEdit := FALSE;
   IF Str.Compare(OldList^.DataBaseTitle, Data^.DataBaseTitle) <> 0 THEN
      SetupWriteNeeded := TRUE
   END;
END MarkTitleChange;

PROCEDURE MarkRefChange(Pntr:  ADDRESS;
                    VAR ReDisplay: BOOLEAN;
                    VAR ReEdit: BOOLEAN);
VAR
   Data:  FileDataPntr;
BEGIN
   Data := Pntr;
   ReDisplay := FALSE;
   ReEdit := FALSE;
   IF Str.Compare(OldList^.StartingRef, Data^.StartingRef) <> 0 THEN
      SetupWriteNeeded := TRUE
   END;
END MarkRefChange;

PROCEDURE ShowFrontScreen(WindowRec: TWB.WinType);

(*RES OLD MNU 12


                     MakeBase Version %6_____  %7________________________


      Input Text Filename:    %0_____________________________________
      .MKS Filename:          %1_____________________________________
      .TDB Filename:          %2_____________________________________
      .TDB Title:             %3_____________________________________
      Starting Ref. Template: %4_____________________________________

      Temporary File Area:    %5_____________________________________






______________________________________________________________________________
F1:   Help                                F5:   Save markup (^Default)
F2:   Alphabetic Characters               F6:   Credits
F3:   Reserved Characters                 F9:   RUN, creating a database
F4:   Reference Tags                      F10:  QUIT without processing
*)

VAR
      i:             CARDINAL;
      VerLen,DatLen,
      VerX,DatX,
      VerY,DatY:     CARDINAL;
BEGIN
   IF NOT ScreenMenuDefined THEN
      ScreenMenuDefined := TRUE;
      StartMenu(FileData);
      WITH FileData DO
          CharFieldProc(InputFileName, CheckInputFile);
          CharFieldProc(SetupFileName, CheckSetupFile);
          CharFieldProc(DataBaseName,  CheckDataBase);
          CharFieldProc(DataBaseTitle, MarkTitleChange);
          CharFieldProc(StartingRef,   MarkRefChange);
          CharFieldProc(TempDiskArea,  CheckTDA);
      END;
      MakeMenu( (*RES REM INS*) 12 , FrontMenu);
      GetFieldInfo(FrontMenu,6,VerX,VerY,VerLen);
      GetFieldInfo(FrontMenu,7,DatX,DatY,DatLen)
   END;

   TWB.Use(WindowRec);
   TWB.Clear;

   ShowFixedText(WindowRec,FrontMenu,0,0);
   TWB.GotoXY(CopyWXPos,CopyWYPos);
   TWB.ClrEol;
   TWB.WrStr('             Copyright (c) 1995 TACT Group, University of Toronto ' ) ;
(* TWB.WrStr('(c) John Bradley, Lidio Presutti 1989');  *)
(*   TWB.WrStr('Copyright (c) 1992 by John Bradley, Lidio Presutti'); *)

(* m.s.   TWB.WrStr('   Copyright (c) 1994 by John Bradley, Lidio Presutti, Michael Stairs and');
   TWB.WrLn ;
   TWB.WrStr('                     Centre for Computing in the Humanities ');
   TWB.WrLn ;
   TWB.WrStr('                           University of Toronto') ;
*)

   WriteScreenField( WindowRec, VerLen, VerX, VerY,
                           SystemVersion, RegularAttr, TRUE );
   WriteScreenField( WindowRec, DatLen, DatX, DatY,
                           SystemVersionDate, RegularAttr, TRUE );

END ShowFrontScreen;

PROCEDURE DisposeFrontScreenInfo;
BEGIN
   IF ScreenMenuDefined THEN DestroyMenu(FrontMenu) END;
   ScreenMenuDefined := FALSE;
END DisposeFrontScreenInfo;

PROCEDURE DoStartUp();
   VAR
      Selection         : CARDINAL;
      SubPos            : CARDINAL;
      Quit              : BOOLEAN;
      Success           : BOOLEAN;

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

   PROCEDURE ReadParams( ): CARDINAL;
      (*RES OLD MSG 112
      MakeBase cannot accept the parameter "%0".
      *)
      CONST
          NotAcceptableRes = (*RES REM INS*) 112 ;
      VAR
         i               : CARDINAL ;
         FileNo          : CARDINAL ;
         tStrRead        : BOOLEAN;
         tStr            : ARRAY[0..255] OF CHAR;
         plst,temp       : ParameterResult;
         CM              : CurrentModeType;
         ED              : BOOLEAN;
         LD              : XlateStrAny;
      BEGIN
        InitialParams;
        LegalParameter('b',FALSE);
        LegalParameter('t',TRUE);
        LegalParameter('w',TRUE);
        LegalParameter('r',TRUE);
        LegalParameter('f',FALSE);

	GetEnv( 'TACTWRK', FileData.TempDiskArea);
	IF NOT VerifyTDA(FileData.TempDiskArea) THEN  FileData.TempDiskArea[0] := 0C  END ;

        FileNo := 0;
        tStrRead := FALSE;
        IF GetParameters(plst,tStr) <> GPSOk THEN
           MsgString(tStr,0);
           PutResError( NotAcceptableRes );
           RETURN 0
        END;
        WHILE plst <> NIL DO
           WITH plst^ DO
              CASE Code OF
                 ' ':
                   INC(FileNo);
                   CASE FileNo OF
                     1:
                        Str.Copy(FileData.InputFileName, Strg);
                        IF NOT VerifyInputFile(FileData.InputFileName) THEN
                           FrontAct := Front;
                           RETURN 1
                        END;
                   | 2:
                        Str.Copy(FileData.DataBaseName, Strg);
                        IF NOT VerifyDataBase(FileData.DataBaseName) THEN
                           FrontAct := Front;
                           RETURN 3
                        END;
                   | 3:
                        Str.Copy(FileData.SetupFileName, Strg);
                        IF NOT VerifySetupFile(FileData.SetupFileName) THEN
                           FrontAct := Front;
                           RETURN 2
                        END;
                   ELSE
                      FrontAct := Front;
                      MsgString(Strg,0);
                      PutResError( NotAcceptableRes );
                      RETURN 0
                   END;
              | 'B':
                  SetupMessageNeeded := FALSE;
                  FrontAct := Verify;
                  DisplayText := FALSE;
              | 'F':
		  WantFolding := FALSE ; (* m.s. new default was TRUE before - only resetable from command line *)
              | 'T':
                  CM.ModeIn := '0'; CM.ModeOut := '0';
                  XlateLine(Scr2Int,'?',Strg,CM,i,LD,i,ED,tStr);
                  SetupWriteNeeded := TRUE;
                  tStrRead := TRUE;
              | 'R':
                  CM.ModeIn := '0'; CM.ModeOut := '0';
                  XlateLine(Scr2Int,'?',Strg,CM,i,LD,i,ED,FileData.StartingRef);
                  SetupWriteNeeded := TRUE;
              | 'W':
                  Str.Copy(FileData.TempDiskArea, Strg );
                  IF NOT VerifyTDA(FileData.TempDiskArea) THEN
                     FrontAct := Front;
                     RETURN 4
                  END;
              ELSE
                 ProgramErrorAndHalt('Unexpected ParameterData Code found');
              END;
           END;
           temp := plst^.Next;
           DEALLOCATE(plst,plst^.Size);
           plst := temp;
        END;

        IF FileNo = 0 THEN RETURN 0 END;
        FileNo := MakeDefaultFileNames(FileData);
        IF tStrRead THEN Str.Copy(FileData.DataBaseTitle, tStr) END;
        IF FileNo <> 1 THEN FrontAct := Front END;
        RETURN FileNo;
      END ReadParams;

PROCEDURE DoFileMenu(VAR MenuItem:  CARDINAL): FrontActions;
VAR
   TC:       CHAR;
   FunctKey: BOOLEAN;
BEGIN
   NEW(OldList);
   OldList^ := FileData;
   REPEAT
      DoMenu(BaseWPtr,FrontMenu,0,0,KeyTerm,FunctTerm,
                   FileData,MenuItem,TC,FunctKey);
      IF NOT FunctKey THEN
         IF (TC = ASCII.rs) THEN
            (*RES OLD CHE 5
            Proceed to RUN phase now? Y)es or N)o:
            =YN
            *)
            ResAskUser( (*RES REM INS*) 5, 'YN', TC);
            IF TC = 'Y' THEN RETURN Verify
            ELSE INC(MenuItem); TC := ASCII.rs END;
         ELSIF (TC = ASCII.esc) THEN
            (*RES OLD CHE 9
            Do you wish to stop MakeBase immediately? Y)es or N)o:
            =YN
            *)
            ResAskUser( (*RES REM INS*) 9 , 'YN', TC);
            IF TC = 'Y' THEN HALT
            ELSE TC := ASCII.rs END;
         END ;
      END;
   UNTIL (TC <> ASCII.rs) OR (FunctKey);
   DISPOSE(OldList);

   MenuItem := 0;
   IF FunctKey THEN
      CASE TC OF
        PCKey.F2:  RETURN Alpha;
      | PCKey.F3:  RETURN SpecChar;
      | PCKey.F4:  RETURN Struct;
      | PCKey.F5:  RETURN WriteSetup;
      | PCKey.F6:  ShowCredit( CreditID, KeyTerm, FunctTerm, TC, FunctKey ); (* m.s.*)
                   RETURN Front;
      | PCKey.CtrlF5: RETURN WriteDefault;
      | PCKey.F9:  RETURN Verify;
      ELSE
         ProgramErrorAndHalt('Unexpected return from DoMenu');
      END;
   ELSE
      ProgramErrorAndHalt('Unexpected return from DoMenu');
   END;
END DoFileMenu;

PROCEDURE VerifyData(VAR FrontAct: FrontActions;
                     VAR Selection: CARDINAL);
BEGIN
   IF FileData.InputFileName[0] = 0C THEN
      (*RES OLD MSG 109
      To Run, MakeBase needs an Input ASCII/DOS Filename.
      *)
      PutResError( (*RES REM INS*) 109 );
      Selection :=  1;
      FrontAct := Front;
      RETURN
   ELSIF NOT VerifyInputFile(FileData.InputFileName) THEN
      Selection :=  1;
      FrontAct := Front;
      RETURN
   END;

   IF FileData.DataBaseName[0] = 0C THEN
      (*RES OLD MSG 110
      To Run, MakeBase needs a .TDB Filename.
      *)
      PutResError( (*RES REM INS*) 110 );
      Selection :=  3;
      FrontAct := Front;
      RETURN
   ELSIF NOT VerifyDataBase(FileData.DataBaseName) THEN
      Selection :=  3;
      FrontAct := Front;
      RETURN
   END;

   FreeXlateLists() ; (* if any where set *)
   Selection := BuildAlphabetXlate();
   IF Selection <> 0 THEN
      FrontAct := Alpha;
      RETURN
   END;

   Selection := BuildSpecialCharXlate();
   IF Selection <> 0 THEN
      FrontAct := SpecChar;
      RETURN
   END;

   CASE BuildStructInfoXlate() OF
     XUAllOK:      FrontAct := Run
   | XUSpecChars:  FrontAct := SpecChar
   | XUStructList: FrontAct := Struct
   END;

   TrimBlanks( FileData.StartingRef, FileData.StartingRef ) ;
   IF FileData.StartingRef[0] = 0C THEN  RETURN  END ;
   IF NOT VerifyRefTemplate(FileData.StartingRef) THEN
      Selection :=  5;
      FrontAct := Front;
   END;
END VerifyData;


BEGIN
      HelpName := 'HELP';
      InitialPrintModule(HelpName,KeyTerm,FunctTerm,DummyHandleFNField);
      BaseWPtr := NIL ; (* m.s. *)
      PushNewWindow(BaseWind, BaseWPtr, DummyInit);
      SetupWriteNeeded := FALSE;
      MakeStructMenus;
      MakeSCMenus;
      InitXlateLists() ;
      InitTables;
      ShowFrontScreen(BaseWPtr);
      SubPos :=  0;
      FrontAct := Front;
      Selection := ReadParams();
      ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);
      IF FrontAct <> Front THEN TimeDelay(500) END;

      REPEAT
         CASE FrontAct OF
           Front:
              FrontAct := DoFileMenu(Selection)
         | Alpha:
              GetAlphaPanel(Selection);
              FrontAct := Front
         | SpecChar:
              PushHelpItem(SpecialCharsHelpRes);
              FrontAct := Front;
              SetupWriteNeeded := TRUE;
              (*RES OLD MSG 207
              Reserved Characters
              *)
              DoScrollingMenu( SCList,ShowSCMenu,GetSCMenu,ShowSCTitleMenu,
                               NewSCData,DeleteSCData,IsSCDataEmpty,
                               (*RES REM INS*) 207 );
              PopHelpItem;
         | WriteSetup:
              WriteSetupFile( (*DoAsDefault := *) FALSE, (* Confirm := *) TRUE );
              FrontAct := Front;
              SetupWriteNeeded := FALSE;
         | WriteDefault:
              WriteSetupFile( (*DoAsDefault := *) TRUE, (* Confirm := *) TRUE );
              FrontAct := Front;
         | Struct:
              PushHelpItem(StructInfoHelpRes);
              FrontAct := Front;
              SetupWriteNeeded := TRUE;
              (*RES OLD MSG 208
              Reference Tags Information
              *)
              DoScrollingMenu( StructList,ShowStructMenu,GetStructMenu,ShowStructTitleMenu,
                             NewStructData,DeleteStructData,IsStructDataEmpty,
                             (*RES REM INS*) 208 );
              PopHelpItem;
         | Verify:
              VerifyData(FrontAct,Selection)
         END;
      UNTIL (FrontAct = Run);

      IF SetupWriteNeeded THEN
         WriteSetupFile((*DoAsDefault :=*) FALSE, (*Confirm :=*) FALSE)
      END;

      DestroyStructMenus;
      DestroySCMenus;
      DeleteStructList;
      DeleteSCList ;
      DisposeFrontScreenInfo;
      DiscardAlphaMenu;

(* instead of PopWindow which doesn't like losing the bottom window: *)
      GetRidOfWindow(BaseWPtr);
      TerminatePrintModule;

END DoStartUp ;

BEGIN
    ScreenMenuDefined := FALSE;
    OverWriteOut := FALSE ;
    WantFolding := TRUE ;	(* m.s. - now default. Resetable from command line: "-f" *)
    WITH FileData DO
       InputFileName[0] := 0C;
       SetupFileName[0] := 0C;
       DataBaseName[0]  := 0C;
       DataBaseTitle[0] := 0C;
       StartingRef[0]   := 0C;
       TempDiskArea[0]  := 0C;
    END;

   KeyTerm[0] := ASCII.rs;
   FunctTerm[0] := PCKey.F2;
   FunctTerm[1] := PCKey.F3;
   FunctTerm[2] := PCKey.F4;
   FunctTerm[3] := PCKey.F9;
   FunctTerm[4] := PCKey.F5;
   FunctTerm[5] := PCKey.CtrlF5;
   FunctTerm[6] := PCKey.F6;

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
END StartUp .
