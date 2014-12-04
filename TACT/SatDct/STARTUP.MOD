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

FROM Translations IMPORT
 (* type *) XFileType,
 (* proc *) XWriteLine, XClose, XWrStr, XWrNXlate, XWrLn, XReadLine, XOpenInput,
            XOpenOutput ;

IMPORT Str, FIO, PCKey, ASCII ;
FROM ResMenus IMPORT
  (* type   *) MenuID,
  (* proc   *) StartMenu, CharField, MakeMenu, DestroyMenu, GetFieldInfo, DoMenu,
               ShowFixedText, ShowMenu, Switches, SwitchValue, CharFieldProc, CardField;
FROM ResMessages IMPORT
  (* proc *)  MsgString, MsgCard, PutResError, PutResMessage, PutResWarning,
              GetResMessage, ResAskUser;
FROM Utils IMPORT GetEnv, StandardSearchList, FindFileInList, StandardizeFileName,
     ParseFilename, MakeFilename, Terminate, Status, TrimBlanks, RemoveExtension,
     StrAny, UpcaseStr, BOpen, BClose, RWType;
FROM UtilsTwo IMPORT IOErrorMessage ;
FROM ResBase IMPORT
  (* Procs *) OpenResourceFile, CloseResourceFile ;
FROM KeyBase IMPORT Read, KeyPressed, GetKeyStrokeType, GetKeyStroke;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM Windows  IMPORT
  (* const *) RegularAttr,
  (* Vars  *) TerminationProc, ActiveAttrib,
  (* Procs *) InitWindows, NonWMMessage, EndWindows ;
FROM KeyTranslation IMPORT InitialTranslationData, WriteScreenField, FILEText;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo, WindowInfoPtr,
  (* procs *) PushNewWindow, DummyInit;
FROM GetParams IMPORT
  (* types *) GetParametersStatus, ParameterResult, ParameterData,
  (* procs *) LegalParameter, GetParameters, InitialParams;
FROM Storage IMPORT  Available, ALLOCATE       , DEALLOCATE, MainHeap, HeapAvail, HeapTotalAvail ;
FROM GlobalDefs IMPORT FileNameType, SystemVersion, SystemVersionDate ;
FROM DiskDirectory IMPORT
  (* Procs *)  CurrentDrive, SelectDrive, CurrentDirectory, ChangeDirectory,
               ChangeTDADirectory ;
FROM XlatUserInput IMPORT BuildAlphabetXlate, InitXlateLists, BuildSpecialCharXlate,
     BuildStructInfoXlate,
     (* Types *)  ReshowMenuType      ;
FROM SetupFile IMPORT VerifySetupFile ;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) ReleaseCollection;
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


VAR
   MenuItem : CARDINAL ;
   ReDisplay, ReEdit, OverWriteOut : BOOLEAN ;
   OldTempDiskArea : ARRAY [0..100] OF CHAR ;
   Result : CARDINAL ;
   OldInputFileName : StrAny ;
   TagPos: ARRAY[RAW..None] OF CARDINAL ;

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


PROCEDURE VerifySATFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   FPtr = POINTER TO FileDataType;
VAR
   FileP:    FPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
   Ch : CHAR ;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE ;
   FileP := FPtr(Data);
   WITH FileP^ DO
      TrimBlanks(SATFileName,SATFileName);
      IF SATFileName[0] = 0C THEN
         (*RES OLD MSG 536
         Please give a Output File Name.
         *)
         PutResError( (*RES REM INS*) 536 ) ;
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(SATFileName, SATExtension)) THEN
         MsgString( SATFileName, 0 );
         Str.Copy( TempStr, ' Output File ' ) ;
         MsgString( TempStr , 1) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN
      END;
      IF FIO.Exists(SATFileName) AND (NOT OverWriteOut) THEN
	 (*RES OLD CHE 49
	 The output filename "%0" already exists. Please choose
	 between N)ew name and O)verwrite file:
	 = N O
	 *)
	 MsgString( SATFileName, 0 );
	 ResAskUser( (*RES REM INS *) 49 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
         ELSE
            ReEdit := TRUE;
            MenuItem := 2 ;
	 END ;
         RETURN
      END;
   END;
END VerifySATFileName;


PROCEDURE VerifyMKSFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   FPtr = POINTER TO FileDataType;
VAR
   FileP:    FPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE ;
   FileP := FPtr(Data);
   WITH FileP^ DO
      TrimBlanks(MKSfileName,MKSfileName);
      IF MKSfileName[0] = 0C THEN
         (*RES OLD MSG 484
         Please give a .MKS File Name.
         *)
         PutResError( (*RES REM INS*) 484 ) ;
         ReEdit := TRUE;
         MenuItem := 3 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(MKSfileName, 'MKS')) THEN
         MsgString( MKSfileName, 0 );
         Str.Copy( TempStr, ' MKS ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 3 ;
         RETURN
      END;
      IF (NOT FIO.Exists(MKSfileName)) AND
         (Str.Compare( MKSfileName, 'DEFAULT.MKS') <> 0) THEN
         (*RES OLD MSG 485
         "%0" not found. Will use DEFAULT.MKS instead.
         *)
         MsgString( MKSfileName, 0 ) ;
         PutResWarning( (*RES REM INS*) 485 ) ;
         Str.Copy( MKSfileName, 'DEFAULT.MKS' ) ;
         MenuItem := 3 ;
      END;
   END;
END VerifyMKSFileName;

PROCEDURE VerifyDCTFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   FPtr = POINTER TO FileDataType;
VAR
   FileP:    FPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE ;
   FileP := FPtr(Data);
   WITH FileP^ DO
      TrimBlanks(DCTFileName,DCTFileName);
      IF DCTFileName[0] = 0C THEN
         (*RES OLD MSG 537
         Please give a Input Dictionary (.DCT) File Name.
         *)
         PutResError( (*RES REM INS*) 537 ) ;
         ReEdit := TRUE;
         MenuItem := 10 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(DCTFileName, 'DCT')) THEN
         MsgString( DCTFileName, 0 );
         Str.Copy( TempStr, ' DCT ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 10 ;
         RETURN
      END;
      IF UpdateDict AND (NOT FIO.Exists(DCTFileName)) THEN
         (*RES OLD MSG 538
         The dictionary "%0" not found.
         *)
         MsgString( DCTFileName, 0 ) ;
         PutResWarning( (*RES REM INS*) 538 ) ;
         ReEdit := TRUE ;
         MenuItem := 10 ;
         RETURN
      END;
      Str.Concat( TempDCTFileName, TempDiskArea, '$$dct.tmp' ) ;
   END;
END VerifyDCTFileName;



PROCEDURE VerifyInputFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   FPtr = POINTER TO FileDataType;
VAR
   FileP:    FPtr;
   r:        CARDINAL;
   dummy : BOOLEAN ;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE ;
   FileP := FPtr(Data);
   WITH FileP^ DO
      TrimBlanks(InputFileName,InputFileName);
      IF InputFileName[0] = 0C THEN
        (*RES OLD MSG 539
        Input File Name is required.
        *)
        PutResError((*RES REM INS*) 539 ) ;
        ReEdit := TRUE;
        MenuItem := 1 ;
        RETURN
      ELSIF ( NOT StandardizeFileName(InputFileName, 'TTT')) THEN
         (*RES OLD MSG 480
         "%0" cannot be used as the name of an %1 file.
         *)
         MsgString( InputFileName, 0 );
         Str.Copy( TempStr, ' Input File ') ;
         MsgString( TempStr , 1 ) ;
         PutResError( (*RES REM INS*) 480 ) ;
         ReEdit := TRUE;
         MenuItem := 1 ;
         RETURN
      END;
      IF NOT FIO.Exists(InputFileName) THEN
         (*RES OLD MSG 540
         Input file "%0" was not found.
         *)
         MsgString( InputFileName, 0 );
         PutResError( (*RES REM INS*) 540 ) ;
         ReEdit := TRUE;
         MenuItem := 1 ;
        RETURN
      END;
      IF Str.Compare(OldInputFileName, InputFileName) <> 0 THEN
        RemoveExtension( InputFileName, SATFileName ) ;
        VerifySATFileName( Data, ReDisplay, ReEdit ) ;
        IF NOT ReEdit THEN
          RemoveExtension( InputFileName, MKSfileName ) ;
          VerifyMKSFileName( Data, ReDisplay, ReEdit ) ;
          IF NOT ReEdit THEN
            RemoveExtension( InputFileName, DCTFileName ) ;
            VerifyDCTFileName( Data, ReDisplay, ReEdit ) ;
          END ;
        END ;
        Str.Copy( OldInputFileName, InputFileName ) ;
      END ;
   END;
END VerifyInputFileName;


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
   BEGIN
	ReDisplay := FALSE;
	ReEdit := FALSE;
	IF Str.Compare(OldTempDiskArea,FileData.TempDiskArea) = 0 THEN RETURN END;
	Str.Copy( OldTempDiskArea, FileData.TempDiskArea) ;
	ReDisplay := TRUE;
	MenuItem  := 4 ;
	IF NOT VerifyTDA(FileData.TempDiskArea) THEN ReEdit := TRUE END;
   END CheckTDA;


PROCEDURE ProcessParams;

VAR plst,temp:  ParameterResult;
   str:         ARRAY[0..255] OF CHAR;
   i:           CARDINAL;
   m:           ARRAY [0..40] OF CHAR;
BEGIN
   FileData.InputFileName := 0C ;
   FileData.OutFileName := 0C ;
   FileData.DCTFileName := 0C ;
   FileData.MKSfileName := 0C ;
   FileData.SATFileName := 0C ;
   BatchMode := FALSE ;
   InitialParams;
   LegalParameter('b',FALSE);
   LegalParameter('u',FALSE);
   LegalParameter('w',TRUE);
   LegalParameter('s',TRUE);
   LegalParameter('d',TRUE);
   LegalParameter('t',TRUE);
   LegalParameter('1',TRUE);
   LegalParameter('2',TRUE);
   LegalParameter('3',TRUE);
   i := 0;
   CASE GetParameters(plst,str) OF
      GPSOk: (* do nothing right now *)
   | GPSBadParameter:
        (*RES OLD MSG 541
        You cannot specify parameter "%0" for TagText.
        *)
        MsgString(str,0);
        PutResError( (*RES REM INS*) 541 );
        HALT;
   | GPSMissingValue:
        (*RES OLD MSG 542
        Parameter "%0" requires a parameter for TagText.
        *)
        MsgString(str,0);
        PutResError( (*RES REM INS*) 542 );
        HALT;
   END;
   WHILE plst <> NIL DO
      WITH plst^ DO
         CASE Code OF
          | 'B':
               BatchMode := TRUE ;
          | 'W':       (* Temp Disk Area:  -w <TDA>            *)
			Str.Copy( FileData.TempDiskArea, Strg );
			CheckTDA( ADR(FileData), ReDisplay, ReEdit );
                        IF ReEdit THEN
                          MenuItem := 5;
                          RETURN ;
                        END ;
          | 'S':
               Str.Copy(FileData.MKSfileName,Strg);
               VerifyMKSFileName( ADR( FileData ), ReDisplay, ReEdit ) ;
               IF ReEdit THEN
                       MenuItem := 4;
                       RETURN ;
               END ;
          | 'D':
               Str.Copy(FileData.DCTFileName,Strg);
               VerifyDCTFileName( ADR( FileData ), ReDisplay, ReEdit ) ;
               IF ReEdit THEN
                       MenuItem := 3;
                       RETURN ;
               END ;
          | 'U':
              FileData.UpdateDict := TRUE;
          | 'T':
              CASE CAP(Strg[i]) OF
                 'O': FileData.WordForm := RAW;
               | 'P': FileData.WordForm := POS;
               | 'L': FileData.WordForm := Lemma;
               | 'M': FileData.WordForm := Modern;
               | 'C': FileData.WordForm := Concept;
              ELSE
                 ReEdit := TRUE;
                 MenuItem := 5;
                 RETURN;
              END ;
          | '1':
              CASE CAP(Strg[i]) OF
                 'O': FileData.OutputOrder.RAW := 1;
               | 'P': FileData.OutputOrder.POS := 1;
               | 'L': FileData.OutputOrder.LEMMA := 1;
              ELSE
                 ReEdit := TRUE;
                 MenuItem := 6;
                 RETURN;
              END ;
          | '2':
              CASE CAP(Strg[i]) OF
                 'O': FileData.OutputOrder.RAW := 2;
               | 'P': FileData.OutputOrder.POS := 2;
               | 'L': FileData.OutputOrder.LEMMA := 2;
              ELSE
                 ReEdit := TRUE;
                 MenuItem := 7;
                 RETURN;
              END ;
          | '3':
              CASE CAP(Strg[i]) OF
                 'O': FileData.OutputOrder.RAW := 3;
               | 'P': FileData.OutputOrder.POS := 3;
               | 'L': FileData.OutputOrder.LEMMA := 3;
              ELSE
                 ReEdit := TRUE;
                 MenuItem := 8;
                 RETURN;
              END ;
          | ' ':
               CASE i OF
                 0: Str.Copy(FileData.InputFileName, Strg);
                    VerifyInputFileName( ADR ( FileData ) , ReDisplay, ReEdit ) ;
                    IF ReEdit THEN
                       MenuItem := 1;
                       RETURN ;
                    END ;
               | 1: Str.Copy(FileData.OutFileName,Strg);
                    VerifySATFileName(ADR ( FileData ) , ReDisplay, ReEdit ) ;
                    IF ReEdit THEN
                       MenuItem := 2;
                       RETURN ;
                    END ;
               ELSE
                 (*RES OLD MSG 544
                 TagText permits only two file names.
                 *)
                 PutResError( (*RES REM INS*) 544 );
                 HALT;
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
END ProcessParams;



PROCEDURE DoStartUp ( VAR BaseWPtr : TWB.WinType ) : BOOLEAN ;

(*RES OLD MNU 61

                   SatDCT Version %15____ %16________________________


   Input Text Filename:  %0________________________________________________
   Output .SAT Filename: %1________________________________________________

   .MKS Filename:        %2________________________________________________
   Temporary File Area:  %3________________________________________________

   Text Form:   Original Sp.:%|4 POS:%|5 Lemma:%|6 Modern Sp.:%|7 Concept:%|8

   Output Order (0-3): Original Sp.:%9  POS:%10  Lemma/Modern Sp./Concept:%11

   Update Input Dictionary?     Yes: %|12   No: %|13
   Input .DCT Filename: %14_______________________________________________


_____________________________________________________________________________
   F1: Help                           F9: RUN, creating Satellite Dictionary
   F6: Credits                       F10: QUIT without doing anything
*)

CONST
   MainMenuRes = (*RES REM INS*) 61  ;
VAR
   FrontMenu: MenuID;
   Work:      ARRAY[0..255] OF CHAR;
   drive, path, name, ext : ARRAY[0..25] OF CHAR ;
   BaseWind:  WindowInfo;
   i,j:       CARDINAL;
   TC:        CHAR;
   FunctKey:  BOOLEAN;
   Done:      BOOLEAN;
   VerX,VerY,VerLen,DatX,DatY,DatLen: CARDINAL;
   DoMenuNow: BOOLEAN;
   HelpName:  ARRAY[0..4] OF CHAR;
   IOresult:  CARDINAL ;
   ErrorMsg : StrAny ;
   result  : CARDINAL ;
   FunctTerm, KeyTerm :ARRAY [0..0] OF CHAR ;
   FilePath : StrAny ;
   InFile, DCTFile: BFile ;

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

   InitXlateLists() ;
   InitTables;

   StartMenu(FileData);
   WITH FileData DO
     CharFieldProc(InputFileName, VerifyInputFileName);
     CharFieldProc(SATFileName, VerifySATFileName);
     CharFieldProc(MKSfileName, VerifyMKSFileName);
     CharFieldProc(FileData.TempDiskArea, CheckTDA);
     Switches(WordForm);
        SwitchValue(RAW) ;
        SwitchValue(POS) ;
        SwitchValue(Lemma);
        SwitchValue(Modern);
        SwitchValue(Concept);
(*     Switches(TagForm);
        SwitchValue(RAW) ;
        SwitchValue(POS) ;
        SwitchValue(Lemma);
        SwitchValue(Modern);
        SwitchValue(Concept);
*)
(*     CardField(TagPos[RAW]);
     CardField(TagPos[POS]);
     CardField(TagPos[Lemma]);
     CardField(TagPos[Modern]);
     CardField(TagPos[Concept]);
*)
     CardField(OutputOrder.RAW);
     CardField(OutputOrder.POS);
     CardField(OutputOrder.LEMMA);
     Switches(UpdateDict);
        SwitchValue(TRUE);
        SwitchValue(FALSE);
     CharFieldProc(DCTFileName, VerifyDCTFileName);
   END;

   MakeMenu( MainMenuRes , FrontMenu);
   GetFieldInfo(FrontMenu,15,VerX,VerY,VerLen);
   GetFieldInfo(FrontMenu,16,DatX,DatY,DatLen);

   PushNewWindow(BaseWind, BaseWPtr, DummyInit);
   ShowFixedText(BaseWPtr,FrontMenu,0,0);
   WriteScreenField( BaseWPtr, VerLen, VerX, VerY,
                          SystemVersion, RegularAttr, TRUE );
   WriteScreenField( BaseWPtr, DatLen, DatX, DatY,
                          SystemVersionDate, RegularAttr, TRUE );
   TWB.GotoXY(0, 21);
   TWB.ClrEol;
   TWB.WrStr('           Copyright (c) 1995 TACT Group, University of Toronto' ) ;
   TWB.WrLn;

   BatchMode := FALSE ;
   DoMenuNow := TRUE ;
   KeyTerm[0] := ASCII.rs ;
   MenuItem :=  1 ;
   FunctTerm[0] := PCKey.F9 ;
   ProcessParams;
   IF NOT BatchMode OR ReEdit OR ((FileData.OutputOrder.RAW = FileData.OutputOrder.POS) OR
                                   (FileData.OutputOrder.RAW = FileData.OutputOrder.LEMMA) OR
                                   (FileData.OutputOrder.POS = FileData.OutputOrder.LEMMA))
                                   THEN
       REPEAT
         WITH FileData DO
          ReEdit := FALSE ;
          ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);
          DoMenu(BaseWPtr,FrontMenu,0,0,KeyTerm, FunctTerm,
                          FileData,MenuItem,TC,FunctKey);
(*          IF (TagPos[RAW] = 0) AND (WordForm <> RAW) THEN
            (*RES OLD MSG 547   ** shared message with tagtext **
            The RAW (Original Sp.) word form must be chosen as either the Text Form
            or as a tag (assigned a non-zero value in the Tags Order).
            *)
            ReEdit := TRUE;
            MenuItem := 6 ;
          ELSIF (TagPos[RAW] > 2) OR (TagPos[POS] > 2) OR (TagPos[Lemma] > 2) OR
                (TagPos[Modern] > 2) OR (TagPos[Concept] > 2) OR
                ((TagPos[RAW] = 0) AND (TagPos[POS] = 0) AND (TagPos[Lemma] = 0) AND
                 (TagPos[Modern] = 0) AND (TagPos[Concept] = 0)) THEN
            (*RES OLD MSG 548
            Each tag must be assigned a number between 0 and 2. To
            process a given tag in the to-be-processed tagged text, assign it the
            number 1 or 2. The 1 or 2 specify the order in which the tags are
            placed in the text preceding Text Form. You must select at least one tag
            to be included in the text.
            *)
            PutResError((*RES REM INS*) 548 ) ;
            ReEdit := TRUE;
            MenuItem := 6 ;
*)
           IF ((OutputOrder.LEMMA = OutputOrder.POS) AND (OutputOrder.LEMMA > 0)) OR
               ((OutputOrder.LEMMA = OutputOrder.RAW) AND (OutputOrder.LEMMA > 0)) OR
               ((OutputOrder.RAW = OutputOrder.POS) AND (OutputOrder.RAW > 0))  OR
               (OutputOrder.RAW > 3) OR (OutputOrder.POS > 3) OR (OutputOrder.LEMMA > 3)
           THEN
             (*RES OLD MSG 551
             Each item must be assigned a mutually exclusive output order
             position of 1 through 3, or 0 if you do not want it included in the
             .SAT output.
             *)
            PutResError((*RES REM INS*) 551 ) ;
            ReEdit := TRUE;
            MenuItem := 6 ;
         ELSIF (OutputOrder.POS > 0) AND (OutputOrder.RAW = 0) AND
               (OutputOrder.LEMMA = 0) THEN
             (*RES OLD MSG 550
             Either (or both) the Original Sp. or Lemma/Modern Sp./Concept form of
             the word must be selected (non-zero value) in Output Order.
             *)
             PutResError((*RES REM INS*) 550 ) ;
             ReEdit := TRUE ;
             MenuItem := 6 ;
         ELSIF UpdateDict AND (FileData.DCTFileName[0] = 0C) THEN
             (*RES OLD MSG 552
             If you choose to update the Input Dictionary, you must supply a
             Input Dictionary File Name.
             *)
            PutResError((*RES REM INS*) 552 ) ;
            ReEdit := TRUE;
            MenuItem := 10 ;
         ELSIF UpdateDict AND (OutputOrder.POS = 0) THEN
             (*RES OLD MSG 549
             If you choose to update the Input Dictionary, POS must be
             assigned a non-zero value in the Output Order.
             *)
            PutResError((*RES REM INS*) 549 ) ;
            ReEdit := TRUE;
            MenuItem := 9 ;
         END ;
        END ;
       UNTIL ReEdit = FALSE ;
  END ;
  TWB.SetPalette(BaseWPtr, ActiveAttrib);
  DestroyMenu(FrontMenu);

   BOpen(InFile, FileData.InputFileName, ReadType, Result);
   IF Result <> 0 THEN
   (*RES  OLD MSG 105       >>> From MAKBAS <<<
   File Name %0: %1.
   *)
   IOErrorMessage( Result, ErrorMsg ) ;
   MsgString(FileData.InputFileName, 0);
   MsgString(ErrorMsg, 0);
   PutResError( (*RES REM INS*) 105 );
   BClose( InFile , Result) ;
   RETURN FALSE ;
 ELSE
   BClose( InFile , Result) ;
 END ;

 IF FileData.UpdateDict THEN
   BOpen(DCTFile, FileData.DCTFileName, ReadType, Result);
   IF Result <> 0 THEN
   (*RES  OLD MSG 105       >>> From MAKBAS <<<
   File Name %0: %1.
   *)
    IOErrorMessage( Result, ErrorMsg ) ;
    MsgString(FileData.DCTFileName, 0);
    MsgString(ErrorMsg, 0);
    PutResError( (*RES REM INS*) 105 );
    BClose( DCTFile , Result) ;
    RETURN FALSE ;
   ELSE
    BClose( DCTFile , Result) ;
   END ;
 END ;
 IF NOT VerifySetupFile( FileData.MKSfileName ) THEN
    ProgramErrorAndHalt('Fatal error while processing .MKS file' ) ;
 ELSE
    Result:= BuildAlphabetXlate();
    IF Result <> 0 THEN
      ProgramErrorAndHalt(' Fatal error while building Alphabet Translation.');
    END ;
    Result := BuildSpecialCharXlate();
    IF Result <> 0 THEN
      ProgramErrorAndHalt(' Fatal error while building Special Character Translation.');
    END ;
   CASE BuildStructInfoXlate() OF
     XUAllOK:     (*  FrontAct := Run *)
   | XUSpecChars, XUStructList:
       ProgramErrorAndHalt(' Fatal error while building Structural Information Translation.');

   END;

  END ;

  RETURN TRUE ;
END DoStartUp;


BEGIN
  FileData.MKSfileName[0] := 0C ;
  FileData.OutFileName[0] := 0C ;
  FileData.SATFileName[0] := 0C ;
  FileData.InputFileName[0] := 0C ;
  FileData.DCTFileName[0] := 0C ;
  FileData.TempDiskArea[0] := 0C ;
  OldTempDiskArea[0] := 0C ;
  OverWriteOut := FALSE ;
  FileData.WordForm := Lemma ;
  FileData.TagForm := RAW ;
  OldInputFileName[0] := 0C ;
  FileData.OutputOrder.RAW := 1 ;
  FileData.OutputOrder.POS := 2 ;
  FileData.OutputOrder.LEMMA := 3 ;
  TagPos[RAW] := 1 ;
  TagPos[POS] := 2 ;
END  StartUp .
