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
FROM HyperDataModel IMPORT MaxDBTitleLength, IDType, TDBIDModel, HyperLength,
     ThisTDBVersion, DBaseTitleType, TDBHeaderType ;
FROM GlobalDefs IMPORT FileNameType, SystemVersion, SystemVersionDate ;
FROM SYSTEM IMPORT ADR;
IMPORT FIO;
IMPORT TWB ;
IMPORT ASCII ;
IMPORT PCKey ;
IMPORT Str;
IMPORT Lib;
FROM GetParams IMPORT
  (* types *) GetParametersStatus, ParameterResult, ParameterData,
  (* procs *) LegalParameter, GetParameters, InitialParams;
FROM Utils     IMPORT
  (* vars   *) month, day, year,
  (* procs  *) RemoveExtension, StandardizeFileName, GetXlationType,
               UpcaseStr, TrimBlanks, Exist ;
FROM UtilsTwo IMPORT
   IOErrorMessage;
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
  (* Procs *) WriteScreenField;
FROM Translations IMPORT
  (* Types *)  CurrentModeType, XlateStrAny,
  (* vars  *)  Scr2Int, Int2Alp,
  (* Procs *)  XlateLine;
FROM ResMenus IMPORT
  (* type   *) MenuID,
  (* proc   *) StartMenu, CharFieldProc, MakeMenu, DestroyMenu, GetFieldInfo,
               ShowFixedText, ShowMenu, DoMenu, CharField;
FROM ResMessages IMPORT
  (* proc *)  MsgString, MsgCard, PutResError, ResAskUser;
FROM GlobalDefs IMPORT
  (* Type  *)  StrAny,
  (* Const *)  TDBExtension;
FROM TDBBase IMPORT
 (* const *) MaxNoMergeFiles,
 (* type  *) InFileDataType, RefsNamePntr,
 (* vars  *) InFile, NoInFiles, OutFile, OutFileName, OutHeader, OutPos,
             OutStartRef;
FROM TDBStart IMPORT
    GetDBTranslate, CompareDBTranslate, GetRefsNameList,
    LocateFileNameID, LocateRefName, HandleHeaderTrailer;
FROM WordBase IMPORT
  (* Type  *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar,
  (* Procs *) IntToSortWord, FullToSortWord;
FROM PrintModule IMPORT InitialPrintModule, TerminatePrintModule;


(*RES OLD MNU 29
                      MergeBas Version %12_____ %13___________________

    Output .TDB Filename:   %0_____________________________________________
    .TDB Title:             %10____________________________________________
    Starting Ref. Template: %11____________________________________________
______________________________________________________________________________

    Save .TDB Titles as COCOA Tag:%1_______________________________________

    Input .TDB Filenames:
      1)  %2_______________________________________________________________
                    .TDB Title: %3_________________________________________
      2)  %4_______________________________________________________________
                    .TDB Title: %5_________________________________________
      3)  %6_______________________________________________________________
                    .TDB Title: %7_________________________________________
      4)  %8_______________________________________________________________
                    .TDB Title: %9_________________________________________
______________________________________________________________________________
F1:    Help                                    F9:   RUN, merging databases
F6:    Credits                                F10:  QUIT without merging

         Copyright (c) 1995 by TACT Group, University of Toronto
*)
CONST
   MainMenuRes = (*RES REM INS*) 29 ;
   CopyWYPos    = 22;
   CopyWXPos    = 0;

TYPE
   FileDataType = RECORD
     FName:      ARRAY[0..MaxNoMergeFiles-1] OF FileNameType;
     OldFName:   ARRAY[0..MaxNoMergeFiles-1] OF FileNameType;
     DTitles:    ARRAY[0..MaxNoMergeFiles-1] OF DBaseTitleType;
     OName:      FileNameType;
     OTitle:     DBaseTitleType;
     FileRef:    ARRAY[0..15] OF CHAR;
     StartRef:   ARRAY[0..40] OF CHAR;
   END;

VAR
  i:           CARDINAL;
  InFilePres:  ARRAY[0..MaxNoMergeFiles-1] OF BOOLEAN;
  OverWriteOut : BOOLEAN ;

PROCEDURE DummyHandleFNField(VAR Field:     ARRAY OF CHAR;
				 Exten:     ARRAY OF CHAR;
			     VAR ReDisplay: BOOLEAN;
			     VAR ReEdit:    BOOLEAN);
   BEGIN
   END DummyHandleFNField ;

PROCEDURE OpenAndReadHeader(Name:   ARRAY OF CHAR;
                            No:     CARDINAL): BOOLEAN;
(*RES OLD MSG 269
File %0 is not a .TDB file.
*)
CONST
   NotTDBRes = (*RES REM INS*) 269;

VAR r:  CARDINAL;
    m:  ARRAY[0..40] OF CHAR;
BEGIN
   FIO.IOcheck := FALSE;
   WITH InFile[No] DO
      FileID := FIO.Open(Name);
      r := FIO.IOresult();
      IF r <> 0 THEN
         IOErrorMessage(r, m);
         (*RES OLD MSG 270
         An IO error occurred reading file "%0": %1.
         *)
         MsgString(Name,0);
         MsgString(m,0);
         PutResError( (*RES REM INS*) 270 );
         FIO.IOcheck := TRUE;
         RETURN FALSE
      END;

      r := FIO.RdBin(FileID,Rec,HyperLength);
      IF r <> HyperLength THEN
         MsgString(Name,0);
         PutResError( NotTDBRes );
         FIO.IOcheck := TRUE;
         FIO.Close(FileID);
         RETURN FALSE
      END;
      Pos := 0;

      Lib.Move(ADR(Rec),ADR(Header),SIZE(TDBHeaderType));
      WITH Header DO
         IF Str.Compare(TDBID,TDBIDModel) <> 0 THEN
            MsgString(Name,0);
            PutResError( NotTDBRes );
            FIO.IOcheck := TRUE;
            FIO.Close(InFile[No].FileID);
            RETURN FALSE
         END;
         IF (Month > 12) OR (Day > 31) THEN
            MsgString(Name,0);
            PutResError( NotTDBRes );
            FIO.IOcheck := TRUE;
            FIO.Close(FileID);
            RETURN FALSE
         END;
         IF TDBVersion <> ThisTDBVersion THEN
            (*RES OLD MSG 271
            %0 is not a Textual Database created by the version of TACT now running.
            *)
            MsgString(Name,0);
            PutResError( (*RES REM INS*) 271 );
            FIO.IOcheck := TRUE;
            FIO.Close(FileID);
            RETURN FALSE;
         END;
      END;
   END;

   FIO.IOcheck := TRUE;
   RETURN TRUE;
END OpenAndReadHeader;

PROCEDURE VerifyInFile(No:        CARDINAL;
                       Data:      ADDRESS;
                   VAR ReDisplay: BOOLEAN;
                   VAR ReEdit:    BOOLEAN);
TYPE
   DPtr = POINTER TO FileDataType;
VAR
   DataP:    DPtr;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(FName[No],FName[No]);
      IF FName[No][0] = 0C THEN
         IF InFilePres[No] THEN FIO.Close(InFile[No].FileID) END;
         InFilePres[No] := FALSE;
         DTitles[No] := 0C;
         RETURN
      ELSIF Str.Compare(OldFName[No],FName[No]) = 0 THEN
         ReDisplay := FALSE;
         RETURN
      ELSIF ( NOT StandardizeFileName(FName[No], TDBExtension)) THEN
         (*RES OLD MSG 272
         The Textual DataBase name %0 is improper.
         *)
         MsgString(FName[No],0);
         PutResError( (*RES REM INS*) 272 );
         ReEdit := TRUE;
         RETURN
      END;
      IF NOT FIO.Exists(FName[No]) THEN
         (*RES OLD MSG 273
         The .TDB File named %0 does not exist.
         *)
         MsgString(FName[No],0);
         PutResError( (*RES REM INS*) 273 );
         ReEdit := TRUE;
         RETURN
      END;
      IF NOT OpenAndReadHeader(FName[No],No) THEN
         ReEdit := TRUE;
         RETURN
      END;
      Str.Copy(DTitles[No],InFile[No].Header.Title);
      Str.Copy(OldFName[No],FName[No]);
   END;
   InFilePres[No] := TRUE;
END VerifyInFile;

PROCEDURE VerifyInFile0(Data:      ADDRESS;
                    VAR ReDisplay: BOOLEAN;
                    VAR ReEdit: BOOLEAN);
BEGIN
   VerifyInFile(0,Data,ReDisplay,ReEdit);
END VerifyInFile0;

PROCEDURE VerifyInFile1(Data:      ADDRESS;
                    VAR ReDisplay: BOOLEAN;
                    VAR ReEdit: BOOLEAN);
BEGIN
   VerifyInFile(1,Data,ReDisplay,ReEdit);
END VerifyInFile1;

PROCEDURE VerifyInFile2(Data:      ADDRESS;
                    VAR ReDisplay: BOOLEAN;
                    VAR ReEdit: BOOLEAN);
BEGIN
   VerifyInFile(2,Data,ReDisplay,ReEdit);
END VerifyInFile2;

PROCEDURE VerifyInFile3(Data:      ADDRESS;
                    VAR ReDisplay: BOOLEAN;
                    VAR ReEdit: BOOLEAN);
BEGIN
   VerifyInFile(3,Data,ReDisplay,ReEdit);
END VerifyInFile3;

PROCEDURE VerifyOutFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO FileDataType;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m:        ARRAY[0..30] OF CHAR;
   Ch : CHAR ;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(OName,OName);
      IF OName[0] = 0C THEN
         (*RES OLD MSG 274
         Please give an Output Database file name.
         *)
         PutResError( (*RES REM INS*) 274 ) ;
         ReEdit := TRUE;
         RETURN
      ELSIF ( NOT StandardizeFileName(OName, TDBExtension)) THEN
         (*RES OLD MSG 275
         "%0" cannot be used as the name of an Output Database file.
         *)
         MsgString( OName, 0 );
         PutResError( (*RES REM INS*) 275 ) ;
         ReEdit := TRUE;
         RETURN
      END;
      IF Exist( OName) AND NOT OverWriteOut THEN (* m.s. - provide user with choice now *)
	 (*RES OLD CHE 47  *** defined in MakeBase startup.mod ****
	 The .TDB database "%0" already exists. Please choose
	 between N)ew name and O)verwrite file:
	 = N O
	 *)
	 MsgString( OName, 0 );
	 ResAskUser( (*RES REM INS *) 47 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	 ELSE
	    OverWriteOut := FALSE ;
	    ReEdit := TRUE ;
	    RETURN
	 END ;
      END ;	
(* m.s. - now give the option to replace above
      IF FIO.Exists(OName) THEN
         (*RES OLD MSG 276
         Output Database file name "%0" is already in use. Please choose another name.
         *)
         MsgString( OName, 0 );
         PutResError( (*RES REM INS*) 276 ) ;
         ReEdit := TRUE;
         RETURN
      END;
*)
   END;
END VerifyOutFileName;

PROCEDURE DoStartUp(VAR BaseWPtr:  TWB.WinType): BOOLEAN;
VAR
   FrontMenu: MenuID;
   BaseWind:  WindowInfo;
   i,j:       CARDINAL;
   FileData:  FileDataType;
   TC:        CHAR;
   FunctKey:  BOOLEAN;
   MenuItem:  CARDINAL;
   Done:      BOOLEAN;
   VerX,VerY,VerLen,DatX,DatY,DatLen: CARDINAL;
   m:         ARRAY[0..40] OF CHAR;
   DoMenuNow: BOOLEAN;
   HelpName:  ARRAY[0..4] OF CHAR;
   KeyTerm:   ARRAY[0..0] OF CHAR;
   FunctTerm: ARRAY[0..0] OF CHAR;

PROCEDURE HandleParameters;
VAR plst,temp:  ParameterResult;
   str:         ARRAY[0..255] OF CHAR;
   ReDisplay:   BOOLEAN;
   ReEdit:      BOOLEAN;
   i,j:         CARDINAL;
   TryBatch:    BOOLEAN;
   CM:          CurrentModeType;
   ED:          BOOLEAN;
   LD:          XlateStrAny;
BEGIN
    InitialParams;
    LegalParameter('o',TRUE);
    LegalParameter('b',FALSE);
    LegalParameter('t',TRUE);
    LegalParameter('r',TRUE);
    LegalParameter('f',TRUE);
    i := 0;
    TryBatch := FALSE;
    CASE GetParameters(plst,str) OF
      GPSOk: (* do nothing right now *)
    | GPSBadParameter:
         (*RES OLD MSG 285
         MergeBas does not accept parameter "%0".
         *)
         MsgString(str,0);
         PutResError( (*RES REM INS*) 285 );
         DoMenuNow := TRUE;
         RETURN
    | GPSMissingValue:
         (*RES OLD MSG 286
         MergeBas requires parameter "%0".
         *)
         MsgString(str,0);
         PutResError( (*RES REM INS*) 286 );
         DoMenuNow := TRUE;
         RETURN
    END;
    WHILE plst <> NIL DO
       WITH plst^ DO
          CASE Code OF
             ' ':
             IF i >= MaxNoMergeFiles THEN
                (*RES OLD MSG 287
                Too many Input Databases were given as parameters to MergeBas.
                *)
                PutResError( (*RES REM INS*) 287 );
                RETURN;
             END;
                Str.Copy(FileData.FName[i],Strg);
                VerifyInFile(i,ADR(FileData),ReDisplay,ReEdit);
                IF ReEdit THEN
                   MenuItem := (i+2)*2;
                   RETURN
                END;
             INC(i);
           | 'O':
             Str.Copy(FileData.OName,Strg);
             VerifyOutFileName(ADR(FileData),ReDisplay, ReEdit);
             IF ReEdit THEN RETURN END;
           | 'B':
             TryBatch := TRUE;
           | 'T':
             CM.ModeIn := '0'; CM.ModeOut := '0';
             XlateLine(Scr2Int,'?',Strg,CM,j,LD,j,ED,FileData.OTitle)
           | 'R':
             CM.ModeIn := '0'; CM.ModeOut := '0';
             XlateLine(Scr2Int,'?',Strg,CM,j,LD,j,ED,FileData.StartRef)
           | 'F':
             CM.ModeIn := '0'; CM.ModeOut := '0';
             XlateLine(Scr2Int,'?',Strg,CM,j,LD,j,ED,FileData.FileRef)
          ELSE
             ProgramErrorAndHalt('Unexpected ParameterData Code found');
          END;
       END;
       temp := plst^.Next;
       DEALLOCATE(plst,plst^.Size);
       plst := temp;
    END;
    DoMenuNow := (NOT TryBatch) OR (FileData.OName[0] = 0C);
END HandleParameters;

PROCEDURE VerifyRefTemplate(InTemplate: ARRAY OF CHAR):   BOOLEAN;
(* modelled after EncodeRefPat from TACT's RefValBase module    j.b. *)
CONST
   NoUnitsRes =    264; (* from RefValBase model *)
   BadRefNameRes = 289; (* taken from XLATUser in MAKBAS *)
   RefDelimID =    '$' ;

TYPE
   StateTypes = ( ColRefPat, LookForRefName, ColRefName, LookForStartPos,
		LookUpName, GetStartPos, GetNoChars );
VAR
   Ch:            CHAR;
   State:         StateTypes ;
   TemplateIndex: CARDINAL ;
   cm:            CurrentModeType ;
   AlpTemplate:   StrAny ;
   CurPos:        CARDINAL ;
   NumbSeq:       CARDINAL ;
   IntLenD:       XlateStrAny ;
   EnoughData	: BOOLEAN ;
   NameStartInt	: CARDINAL ;
   NameStartAlp	: CARDINAL ;
   LastCharRet  : BOOLEAN ;
   LastCharLen  : CARDINAL ;
   RefNameAlp   : ARRAY[0..30] OF CHAR;
   RefNameInt   : ARRAY[0..30] OF CHAR;
   TextLen      : CARDINAL;

PROCEDURE VerifyGivenRefName(): BOOLEAN;
VAR
   SortName:   ARRAY[0..30] OF CHAR;
   l:          CARDINAL;
   dummy:      RefsNamePntr;
BEGIN
   l := CurPos - NameStartAlp;
   FullToSortWord( RefNameAlp, SortName ) ;
   IF LocateRefName(SortName, dummy) THEN RETURN TRUE END;
   IF LastCharRet THEN
      (* To quote Lidio in RefValba:  (j.b.) *)
         (* this is a "bit" of a Kludge, but gets results! *)
         (* remove last retained diacritic from name and try again *)
      RefNameAlp[l-1] := 0C;
      FullToSortWord( RefNameAlp, SortName ) ;
      l := TemplateIndex - NameStartInt - LastCharLen;
      Str.Slice(RefNameInt, InTemplate, NameStartInt,
                TemplateIndex - NameStartInt);
      IF LocateRefName(SortName, dummy) THEN RETURN TRUE END;
   END;
   MsgString( RefNameInt, 0);
   PutResError( BadRefNameRes );
   RETURN FALSE;
END VerifyGivenRefName;

BEGIN
   TrimBlanks(InTemplate, InTemplate);
   IF InTemplate[0] = 0C THEN RETURN TRUE END;

   IF Str.Pos(InTemplate, RefDelimID ) = MAX(CARDINAL) THEN
      Ch := RefDelimID;
      MsgString( InTemplate, 0 ) ;
      MsgString( Ch, 0 ) ;
      PutResError( NoUnitsRes );
      RETURN FALSE ;
   END ;
   State := ColRefPat ;
   TemplateIndex := 0 ;
   Str.Append(InTemplate, ' ');

   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine( Int2Alp, 377C, InTemplate, cm,TextLen, IntLenD, NumbSeq,
		EnoughData, AlpTemplate );

   CurPos := 0 ;
   WHILE (CurPos < TextLen) DO
      Ch := InTemplate[ TemplateIndex ] ;
      CASE State OF
        ColRefPat :
          IF Ch = RefDelimID THEN
	     NameStartInt := TemplateIndex + IntLenD[CurPos].Int ;
	     NameStartAlp := CurPos + 1;
	     State := LookForRefName ;
             LastCharRet := FALSE
          END ;
          INC( TemplateIndex, IntLenD[CurPos].Int ) ;
          INC( CurPos ) ;
      | LookForRefName :
          IF Ch = '?' THEN
             (*RES OLD MSG 291
             You cannot use "$?" in MergeBas.
             *)
             PutResError( (*RES REM INS*) 291 );
             RETURN FALSE ;
          END;
          IF (TypeOfChar[AlpTemplate[CurPos]] = Letter) OR
	     (TypeOfChar[AlpTemplate[CurPos]] = RetDiac) THEN
             IF TypeOfChar[AlpTemplate[CurPos]] = RetDiac THEN
                LastCharLen := IntLenD[CurPos].Int ;
                LastCharRet := TRUE ;
             ELSE
                LastCharRet := FALSE
             END ;
            INC( TemplateIndex, IntLenD[CurPos].Int ) ;
            INC( CurPos ) ;
          ELSE
             State := ColRefName;
          END;
      | ColRefName :
          IF CurPos = NameStartAlp THEN
             State := ColRefPat
          ELSE
             Str.Slice(RefNameAlp, AlpTemplate, NameStartAlp,
                       CurPos - NameStartAlp);
             Str.Slice(RefNameInt, InTemplate, NameStartInt,
                       TemplateIndex - NameStartInt);
             IF NOT VerifyGivenRefName() THEN
                RETURN FALSE
             END;
             IF Ch = '/' THEN
                State := LookForStartPos ;
                INC( TemplateIndex, IntLenD[CurPos].Int ) ;
                INC( CurPos ) ;
             ELSE
                State := ColRefPat ;
             END ;
          END;
      | LookForStartPos :
          IF (Ch < '0') OR (Ch > '9') THEN
             State := ColRefPat
          ELSE
             State := GetStartPos ;
             INC( TemplateIndex, IntLenD[CurPos].Int ) ;
             INC( CurPos ) ;
          END;
      | GetStartPos :
          IF (Ch >= '0') AND (Ch <= '9') THEN
             INC( TemplateIndex, IntLenD[CurPos].Int ) ;
             INC( CurPos ) ;
          ELSIF Ch = ',' THEN
             State := GetNoChars
          ELSE
             State := ColRefPat ;
          END;
      | GetNoChars:
          IF (Ch >= '0') AND (Ch <= '9') THEN
             INC( TemplateIndex, IntLenD[CurPos].Int ) ;
             INC( CurPos ) ;
          ELSE
             State := ColRefPat ;
          END;
      ELSE ProgramErrorAndHalt('Invalid State in VerifyRefTemplate');
      END;
   END;
   RETURN TRUE;
END VerifyRefTemplate;

BEGIN
   KeyTerm[0] := ASCII.rs;
   FunctTerm[0] := PCKey.F9;
   HelpName := 'HELP';
   InitialPrintModule(HelpName,KeyTerm,FunctTerm, DummyHandleFNField);
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
     CharFieldProc(OName,VerifyOutFileName);  (* field 0 *)
     CharField(FileRef);                      (* field 1 *)
     CharFieldProc(FName[0],VerifyInFile0);   (* field 2 *)
     CharField(DTitles[0]);                   (* field 3 *)
     CharFieldProc(FName[1],VerifyInFile1);   (* field 4 *)
     CharField(DTitles[1]);                   (* field 5 *)
     CharFieldProc(FName[2],VerifyInFile2);   (* field 6 *)
     CharField(DTitles[2]);                   (* field 7 *)
     CharFieldProc(FName[3],VerifyInFile3);   (* field 8 *)
     CharField(DTitles[3]);                   (* field 9 *)
     CharField(OTitle);                       (* field 10 *)
     CharField(StartRef);                     (* field 11 *)
   END;
   MakeMenu( MainMenuRes , FrontMenu);
   GetFieldInfo(FrontMenu,12,VerX,VerY,VerLen);
   GetFieldInfo(FrontMenu,13,DatX,DatY,DatLen);

   PushNewWindow(BaseWind, BaseWPtr, DummyInit);
   ShowFixedText(BaseWPtr,FrontMenu,0,0);

   WriteScreenField( BaseWPtr, VerLen, VerX, VerY,
                           SystemVersion, RegularAttr, TRUE );
   WriteScreenField( BaseWPtr, DatLen, DatX, DatY,
                           SystemVersionDate, RegularAttr, TRUE );

   WITH FileData DO
      FOR i := 0 TO MaxNoMergeFiles-1 DO
         FName[i] := 0C;
         DTitles[i] := 0C;
         OldFName[i] := 0C;
      END;
      OName := 0C;
      OTitle := 0C;
      FileRef := 0C;
      StartRef := 0C;
   END;

   MenuItem := 0;
   DoMenuNow := TRUE;
   HandleParameters;
   REPEAT
      Done := TRUE;
      ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);
      IF NOT DoMenuNow THEN
         DoMenuNow := TRUE;
      ELSE
         DoMenu(BaseWPtr,FrontMenu,0,0,KeyTerm, FunctTerm,
                      FileData,MenuItem,TC,FunctKey);
      END;
      j := 0;
      FOR i := 0 TO MaxNoMergeFiles-1 DO
         IF InFilePres[i] THEN
            IF j <> i THEN
               InFile[j] := InFile[i];
               FileData.FName[j] := FileData.FName[i];
               FileData.DTitles[j] := FileData.DTitles[i];
            END;
            INC(j);
         END;
      END;
      IF j >= 2 THEN
         NoInFiles := j - 1
      ELSIF j = 0 THEN
         (*RES OLD MSG 277
         Please give a collection of Input Database file names.
         *)
         PutResError( (*RES REM INS*) 277 );
         Done := FALSE;
         MenuItem := 4;
      ELSE
         (*RES OLD MSG 278
         Please give more than one Input Database file name.
         *)
         PutResError( (*RES REM INS*) 278 );
         Done := FALSE;
         MenuItem := 6;
      END;
   UNTIL Done;

   ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);

   GetDBTranslate;
   FOR i := 1 TO NoInFiles DO
      IF NOT CompareDBTranslate(i) THEN
         (*RES OLD MSG 279
         The alphabet for file "%0" does not match the alphabet for the first file.
         *)
         MsgCard(i+1,0);
         PutResError( (*RES REM INS*) 279 );
         RETURN FALSE;
      END;
   END;

   FOR i := 0 TO NoInFiles DO
      IF NOT GetRefsNameList(i) THEN
         (*RES OLD MSG 280
         Reference names for file "%0" do not match the ones from earlier files.
         *)
         MsgCard(i+1,0);
         PutResError( (*RES REM INS*) 280 );
         RETURN FALSE;
      END;
      InFile[i].Header.Title := FileData.DTitles[i];
      IF FileData.StartRef[0] = 0C THEN
         HandleHeaderTrailer(i,FileData.StartRef);
         IF FileData.StartRef[0] <> 0C THEN
            ShowMenu(BaseWPtr,FrontMenu,0,0,FileData);
         END;
      END;
   END;

   TrimBlanks(FileData.FileRef,FileData.FileRef);
   IF FileData.FileRef[0] <> 0C THEN
      IntToSortWord(FileData.FileRef,m);
      IF NOT LocateFileNameID(m) THEN
         (*RES OLD MSG 281
         The Reference name "%0" does not appear in the Input Databases.
         *)
         MsgString(FileData.FileRef,0);
         PutResError( (*RES REM INS*) 281 );
         RETURN FALSE;
      END;
   END;

   Str.Copy(OutStartRef, FileData.StartRef);
   IF NOT VerifyRefTemplate(OutStartRef) THEN RETURN FALSE END;

   OutFileName := FileData.OName;
   WITH OutHeader DO
      Title := FileData.OTitle;
      TDBID := TDBIDModel;
      TDBVersion := ThisTDBVersion;
      Year := year;
      Month := month;
      Day := day;
   END;

   FIO.IOcheck := FALSE;
   OutFile := FIO.Create(OutFileName);
   i := FIO.IOresult();
   IF i <> 0 THEN
      IOErrorMessage(i, m);
      (*RES OLD MSG 282
      An IO error occurred while creating the new .TDB file "%0": %1.
      *)
      MsgString(OutFileName,0);
      MsgString(m,0);
      PutResError( (*RES REM INS*) 282 );
      RETURN FALSE;
   END;
   OutPos.Rec := 0;
   FIO.IOcheck := TRUE;
   TWB.SetPalette(BaseWPtr, ActiveAttrib);
   DestroyMenu(FrontMenu);
   TerminatePrintModule;
   RETURN TRUE;
END DoStartUp;

BEGIN
  FOR i := 0 TO MaxNoMergeFiles-1 DO
      InFilePres[i] := FALSE;
  END;
  OverWriteOut := FALSE ;
END StartUp .
