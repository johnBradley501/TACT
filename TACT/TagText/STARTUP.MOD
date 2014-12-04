IMPLEMENTATION MODULE StartUp ;

(* copyright (c) 1991-96 Ian Lancashire, Lidio Presutti, University of Toronto *)

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
FROM Str IMPORT Append;
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


PROCEDURE VerifyOutFileName(Data:      ADDRESS;
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
      TrimBlanks(OutFileName,OutFileName);
      IF OutFileName[0] = 0C THEN
         (*RES OLD MSG 536
         Please give a Output File Name.
         *)
         PutResError( (*RES REM INS*) 536 ) ;
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(OutFileName, TAGExtension)) THEN
         MsgString( OutFileName, 0 );
         Str.Copy( TempStr, ' Output File ' ) ;
         MsgString( TempStr , 1) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN
      END;
      IF FIO.Exists(OutFileName) AND (NOT OverWriteOut) THEN
	 (*RES OLD CHE 49
	 The output filename "%0" already exists. Please choose
	 between N)ew name and O)verwrite file:
	 = N O
	 *)
	 MsgString( OutFileName, 0 );
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
END VerifyOutFileName;


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
         MenuItem := 4 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(MKSfileName, 'MKS')) THEN
         MsgString( MKSfileName, 0 );
         Str.Copy( TempStr, ' MKS ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 4 ;
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
         MenuItem := 4 ;
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
         MenuItem := 3 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(DCTFileName, 'DCT')) THEN
         MsgString( DCTFileName, 0 );
         Str.Copy( TempStr, ' DCT ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 3 ;
         RETURN
      END;
      IF (NOT FIO.Exists(DCTFileName)) THEN
         (*RES OLD MSG 538
         The dictionary "%0" not found.
         *)
         MsgString( DCTFileName, 0 ) ;
         PutResWarning( (*RES REM INS*) 538 ) ;
         ReEdit := TRUE ;
         MenuItem := 3 ;
         RETURN
      END;
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
      ELSIF ( NOT StandardizeFileName(InputFileName, 'TXT')) THEN
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
        IF OutFileName[0] = 0C THEN
           RemoveExtension( InputFileName, OutFileName ) ;
        END ;
        IF MKSfileName[0] = 0C THEN
             RemoveExtension( InputFileName, MKSfileName ) ;
        END ;
        IF DCTFileName[0] = 0C THEN
             RemoveExtension( InputFileName, DCTFileName ) ;
        END ;
        VerifyOutFileName( Data, ReDisplay, ReEdit ) ;
        VerifyMKSFileName( Data, ReDisplay, ReEdit ) ;
        VerifyDCTFileName( Data, ReDisplay, ReEdit ) ;
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

      IF TDADone THEN (* m.s. change extender swap drive *)
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
	MenuItem  := 5 ;
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
   BatchMode := FALSE ;
   InitialParams;
   LegalParameter('b',FALSE);
   LegalParameter('w',TRUE);
   LegalParameter('s',TRUE);
   LegalParameter('d',TRUE);
   LegalParameter('t',TRUE);
   LegalParameter('1',TRUE);
   LegalParameter('2',TRUE);
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
			END;
          | 'S':
               Str.Copy(FileData.MKSfileName,Strg);
          | 'D':
               Str.Copy(FileData.DCTFileName,Strg);
          | 'T':
              CASE CAP(Strg[i]) OF
                 'O': FileData.WordForm := RAW;
               | 'P': FileData.WordForm := POS;
               | 'L': FileData.WordForm := Lemma;
               | 'M': FileData.WordForm := Modern;
               | 'C': FileData.WordForm := Concept;
              ELSE
                 ReEdit := TRUE;
                 MenuItem := 6;
              END ;
          | '1':
              FileData.TagPos[RAW] := 0 ;
              CASE CAP(Strg[i]) OF
                 'O': FileData.TagPos[RAW] := 1;
               | 'P': FileData.TagPos[POS] := 1;
               | 'L': FileData.TagPos[Lemma] := 1;
               | 'M': FileData.TagPos[Modern] := 1;
               | 'C': FileData.TagPos[Concept] := 1;
              ELSE
                 ReEdit := TRUE;
                 FileData.TagPos[RAW] := 1 ;
                 MenuItem := 5;
              END ;
          | '2':
              FileData.TagPos[POS] := 0 ;
              CASE CAP(Strg[i]) OF
                 'O': FileData.TagPos[RAW] := 2;
               | 'P': FileData.TagPos[POS] := 2;
               | 'L': FileData.TagPos[Lemma] := 2;
               | 'M': FileData.TagPos[Modern] := 2;
               | 'C': FileData.TagPos[Concept] := 2;
              ELSE
                 ReEdit := TRUE;
                 FileData.TagPos[POS] := 2 ;
                 MenuItem := 5;
              END ;
          | ' ':
               CASE i OF
                 0: Str.Copy(FileData.InputFileName, Strg);
               | 1: Str.Copy(FileData.OutFileName,Strg);
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
   VerifyInputFileName( ADR ( FileData ) , ReDisplay, ReEdit ) ;
END ProcessParams;



PROCEDURE DoStartUp ( VAR BaseWPtr : TWB.WinType ) : BOOLEAN ;

(*RES OLD MNU 59
                   TagText Version %15__ %16________________________


  Input Text Filename:  %0_______________________________________________
  Output .TTT Filename: %1_______________________________________________

  Input .DCT Filename:  %2_______________________________________________
  .MKS Filename:        %3_______________________________________________
  Temporary File Area:  %4_______________________________________________

  Text Form:      Original Sp.:%|5POS:%|6Lemma:%|7Modern Sp.:%|8Concept:%|9

  Tag Order(0-2): Original Sp.:%|10POS:%|11Lemma:%|12Modern Sp.:%|13Concept:%|14




_____________________________________________________________________________
  F1: Help                                 F9: RUN, creating tagged file
  F6: Credits                             F10: QUIT without doing anything
*)

CONST
   MainMenuRes = (*RES REM INS*) 59  ;
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
   FunctTerm, KeyTerm : ARRAY [0..0] OF CHAR ;
   FilePath : StrAny ;
   InFile, DCTFile: BFile ;
   NoTags: CARDINAL ;
   I, J: IncludeType ;

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
     CharFieldProc(OutFileName, VerifyOutFileName);
     CharFieldProc(DCTFileName, VerifyDCTFileName);
     CharFieldProc(MKSfileName, VerifyMKSFileName);
     CharFieldProc(FileData.TempDiskArea, CheckTDA);
     Switches(WordForm);
        SwitchValue(RAW);
        SwitchValue(POS);
        SwitchValue(Lemma);
        SwitchValue(Modern);
        SwitchValue(Concept);
     CardField(TagPos[RAW]);
     CardField(TagPos[POS]);
     CardField(TagPos[Lemma]);
     CardField(TagPos[Modern]);
     CardField(TagPos[Concept]);
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
   TWB.WrStr('          Copyright (c) 1995 by TACT Group, University of Toronto' ) ;
   TWB.WrLn;

   BatchMode := FALSE ;
   DoMenuNow := TRUE ;
   KeyTerm[0] := ASCII.rs ;
   FunctTerm[0] := PCKey.F9 ;
   ProcessParams;
   MenuItem :=  0 ;
   IF NOT BatchMode OR ReEdit THEN
     WITH FileData DO
       REPEAT
          ReEdit := FALSE ;
          ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);
          DoMenu(BaseWPtr,FrontMenu,0,0,KeyTerm, FunctTerm,
                          FileData,MenuItem,TC,FunctKey);
          IF (TagPos[RAW] = 0) AND (WordForm <> RAW) THEN
            (*RES OLD MSG 547
            The RAW (Original Sp.) word form must be chosen as either the Text Form
            or as a tag (assigned a non-zero value in the Tags Order).
            *)
            PutResError((*RES REM INS*) 547 ) ;
            ReEdit := TRUE;
            MenuItem := 6 ;
          ELSIF (TagPos[RAW] > 2) OR (TagPos[POS] > 2) OR (TagPos[Lemma] > 2) OR
                (TagPos[Modern] > 2) OR (TagPos[Concept] > 2) OR
                ((TagPos[RAW] = 0) AND (TagPos[POS] = 0) AND (TagPos[Lemma] = 0) AND
                 (TagPos[Modern] = 0) AND (TagPos[Concept] = 0)) THEN
            (*RES OLD MSG 546
            Each tag must be assigned a number between 0 and 2. To
            include a given tag in the to-be-produced tagged text, assign it the
            number 1 or 2. The 1 or 2 specify the order in which the tags will be
            placed in the text preceding Text Form. You must select at least one tag
            to be included in the text.
            *)
            PutResError((*RES REM INS*) 546 ) ;
            ReEdit := TRUE;
            MenuItem := 6 ;
          ELSE
            NoTags := 0 ;
            Tag1Form := None ;
            Tag2Form := None ;
            FOR I := RAW TO Concept DO
              IF TagPos[I] > 0 THEN
                 FOR J := RAW TO Concept DO
                   IF I <> J THEN
                     IF TagPos[I] = TagPos[J] THEN (* two items have same order #*)
                       (*RES OLD MSG 556
                       Two tags have been assigned the same Order number. Please
                       make them distinct.
                       *)
                       PutResError((*RES REM INS*) 556 ) ;
                       ReEdit := TRUE;
                       MenuItem := 7 ;
                       I := None ; J := None ;
                     END ;
                   END ;
                 END ;
                 IF NOT ReEdit THEN (* distinct *)
                    INC( NoTags ) ;
                    IF TagPos[I] = 1 THEN
                       Tag1Form := I ;
                    ELSE
                       Tag2Form := I ;
                    END ;
                 END ;
              END ;
            END ;
          END ;
       UNTIL ReEdit = FALSE ;
   END ;
  END ;
  TWB.SetPalette(BaseWPtr, ActiveAttrib);
  DestroyMenu(FrontMenu);

  InsertStr[0] := 0C ;

  IF (NoTags = 1) AND (Tag1Form = None) THEN
    Tag1Form := Tag2Form ;
    Tag2Form := None ;
  END ;
     CASE Tag1Form OF
        RAW :
          Append( InsertStr, '<RAW >' ) ;
          Tag1Start := 5 ;
          Tag1Field := 0 ;   |
        POS :
          Append( InsertStr, '<POS >' ) ;
          Tag1Start := 5 ;
          Tag1Field := 1 ;    |
        Lemma:
          Append( InsertStr, '<LEMMA >' ) ;
          Tag1Start := 7 ;
          Tag1Field := 2 ;     |
        Modern:
          Append( InsertStr, '<MODERN >' ) ;
          Tag1Start := 8 ;
          Tag1Field := 3 ;      |
        Concept:
          Append( InsertStr, '<CONCEPT >' ) ;
          Tag1Start := 9 ;
          Tag1Field := 4 ;
     END ;
     CASE Tag2Form OF
        RAW :
          Append( InsertStr, '<RAW >' ) ;
          Tag2Start := 6 + Tag1Start ;
          Tag2Field := 0 ;       |
        POS :
          Append( InsertStr, '<POS >' ) ;
          Tag2Start := 6 + Tag1Start ;
          Tag2Field := 1 ;        |
        Lemma:
          Append( InsertStr, '<LEMMA >' ) ;
          Tag2Start := 8 + Tag1Start ;
          Tag2Field := 2 ;         |
        Modern:
          Append( InsertStr, '<MODERN >' ) ;
          Tag2Start := 9 + Tag1Start ;
          Tag2Field := 3 ;          |
        Concept:
          Append( InsertStr, '<CONCEPT >' ) ;
          Tag2Start := 10 + Tag1Start ;
          Tag2Field := 4 ;
     END ;
     CASE FileData.WordForm OF
        RAW :
          WordField := 0 ;           |
        POS :
          WordField := 1 ;            |
        Lemma :
          WordField := 2 ;             |
        Modern :
          WordField := 3 ;              |
        Concept :
          WordField := 4 ;
     END ;


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
  FileData.InputFileName[0] := 0C ;
  FileData.DCTFileName[0] := 0C ;
  FileData.TempDiskArea[0] := 0C ;
  OldTempDiskArea[0] := 0C ;
  OverWriteOut := FALSE ;
  FileData.WordForm := Lemma ;
  Tag1Form := RAW ;
  Tag2Form := POS ;
  Tag1Start := 0 ;
  Tag2Start := 0 ;
  OldInputFileName[0] := 0C ;
  FileData.TagPos[RAW] := 1 ;
  FileData.TagPos[POS] := 2 ;
  FileData.TagPos[Lemma] := 0 ;
  FileData.TagPos[Concept] := 0 ;
  FileData.TagPos[Modern] := 0 ;
END  StartUp .
