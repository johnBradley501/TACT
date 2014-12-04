MODULE BuildBat;

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

IMPORT FIO, Str, Utils, TWB, PCKey, ASCII, IO ;
FROM GetParams IMPORT
  (* types *) GetParametersStatus, ParameterResult, ParameterData,
  (* procs *) LegalParameter, GetParameters, InitialParams;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM GlobalDefs IMPORT StrAny, TDBExtension, CheckResVersion, CheckParam,
     SystemVersion, SystemVersionDate;
FROM HyperDataModel IMPORT
   IDType, TDBIDModel, PDBIDModel;
FROM Utils IMPORT GetEnv, StandardSearchList, FindFileInList, StandardizeFileName,
     ParseFilename, MakeFilename, Terminate, Status, TrimBlanks, RemoveExtension;
FROM ResBase IMPORT
  (* Procs *) OpenResourceFile, CloseResourceFile ;
FROM KeyBase IMPORT Read, KeyPressed, GetKeyStrokeType, GetKeyStroke;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM Windows  IMPORT
  (* const *) RegularAttr,
  (* Vars  *) TerminationProc,
  (* Procs *) InitWindows, NonWMMessage, EndWindows ;
FROM KeyTranslation IMPORT InitialTranslationData, WriteScreenField;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo, WindowInfoPtr,
  (* procs *) PushNewWindow, DummyInit;
FROM ResMenus IMPORT
  (* type   *) MenuID,
  (* proc   *) StartMenu, CharField, MakeMenu, DestroyMenu, GetFieldInfo, DoMenu,
               ShowFixedText, ShowMenu, Switches, SwitchValue, CharFieldProc;
FROM ResMessages IMPORT
  (* proc *)  MsgString, MsgCard, PutResError, PutResMessage, PutResWarning,
              GetResMessage, ResAskUser;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) NextColItem,ReleaseCollection;
FROM Translations IMPORT
 (* type *) XFileType,
 (* var  *) Int2Scr, Scr2Int,
 (* proc *) XOpenInput, XAppend, XOpenOutput, XClose, XReadLine,
            XWriteLine, XWrStr, XWrLn;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, ShowHelpItem, ShowCredit;

CONST
   MaxNumbToMerge = 4;
   TmpStr = 'TMP';

   CopyWYPos    = 17;
   CopyWXPos    = 12;  (* was 20 *)
   (*RES OLD MSG 427
   .MKS file name "%0" does not exist.
   *)
   FileProblemMessage = (*RES REM INS*) 427 ;

TYPE
   FilePntr = POINTER TO FileData;
   FileData = RECORD
      FileName:  ARRAY[0..64] OF CHAR;
      TDBFile:   BOOLEAN;
      Next:      FilePntr;
   END;

   BasePntr = POINTER TO BaseDataRecord ;
   BaseDataRecord = RECORD
     LSTFileName:     ARRAY [0..100] OF CHAR;
     TDBFileName:     ARRAY [0..255] OF CHAR;
     BatchFileName:   ARRAY[0..100] OF CHAR;
     MKSfileName:     ARRAY[0..64] OF CHAR;
     TempDir:         ARRAY[0..40] OF CHAR;
     TDBTitle:        ARRAY [0..50] OF CHAR;
     TDBRef:          ARRAY [0..40] OF CHAR;
     MAKBAS:          BOOLEAN;
     Batch:           BOOLEAN;
   END;

VAR
   InFile:      XFileType;
   OutFile:     XFileType;
   Base:        BaseDataRecord;
   Top:         FilePntr;
   tempfno:     CARDINAL;
   NumbFiles:   CARDINAL;
   FoldLine:	BOOLEAN ;
   dummy:       BOOLEAN;
   BaseWPtr:    TWB.WinType;
   IOresult:    CARDINAL;

   KeyTerm:   ARRAY[0..0] OF CHAR; (* m.s. *)
   FunctTerm: ARRAY[0..0] OF CHAR; (* m.s. *)
   TermList    : ARRAY[0..1] OF CHAR;
   ExitList    : ARRAY[0..0] OF CHAR;
   FunctKey, ReDisplay, ReEdit, DoMenuNow, Done : BOOLEAN ;
   TC : CHAR ;
   MenuItem : CARDINAL ;
   ErrorMsg : StrAny ;
   FilePath : StrAny ;
   ProcessParameters : BOOLEAN ;
   OverWriteOut : BOOLEAN;

   MakeBasString:    ARRAY[0..20] OF CHAR;
   HSMS2TDBString:   ARRAY[0..30] OF CHAR;
   MergeBasString:   ARRAY[0..30] OF CHAR;
   EraseString:      ARRAY[0..15] OF CHAR;
   ErrorLevelString: ARRAY[0..40] OF CHAR;
   SCREENString:     ARRAY[0..12] OF CHAR;

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
   DPtr = POINTER TO BaseDataRecord;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
   Ch : CHAR ;
BEGIN
   ReDisplay := TRUE;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(Base.TDBFileName,Base.TDBFileName);
      IF Base.TDBFileName[0] = 0C THEN
         (*RES OLD MSG 482
         Please give a Output .TDB File Name.
         *)
         PutResError( (*RES REM INS*) 482 ) ;
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(Base.TDBFileName, TDBExtension)) THEN
         MsgString( Base.TDBFileName, 0 );
         Str.Copy( TempStr, ' Output TDB Database ' ) ;
         MsgString( TempStr , 1) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN
      END;
      IF FIO.Exists(Base.TDBFileName) AND (NOT OverWriteOut) THEN
	 (*RES OLD CHE 47
	 The .TDB database "%0" already exists. Please choose
	 between N)ew name and O)verwrite file:
	 = N O
	 *)
	 MsgString( Base.TDBFileName, 0 );
	 ResAskUser( (*RES REM INS *) 47 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	 ELSE
	    OverWriteOut := FALSE ;
            ReEdit := TRUE;
            MenuItem := 2 ;
	    RETURN ;
	 END ;
      END;
   END;
   ReDisplay := FALSE;
END VerifyOutFileName;

PROCEDURE VerifyBatchFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO BaseDataRecord;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReDisplay := TRUE;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(Base.BatchFileName,Base.BatchFileName);
      IF Base.BatchFileName[0] = 0C THEN
         (*RES OLD MSG 483
         Please give a Batch File Name.
         *)
         PutResError( (*RES REM INS*) 483 ) ;
         ReEdit := TRUE;
         MenuItem := 3 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(Base.BatchFileName, 'BAT')) THEN
         MsgString( Base.BatchFileName, 0 );
         Str.Copy( TempStr , ' Output Batch File ') ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         MenuItem := 3 ;
         ReEdit := TRUE;
         RETURN
      END;
   END;
   ReDisplay := FALSE;
END VerifyBatchFileName;

PROCEDURE VerifyMKSFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO BaseDataRecord;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReDisplay := TRUE;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(Base.MKSfileName,Base.MKSfileName);
      IF Base.MKSfileName[0] = 0C THEN
         (*RES OLD MSG 484
         Please give a .MKS File Name.
         *)
         PutResError( (*RES REM INS*) 484 ) ;
         ReEdit := TRUE;
         MenuItem := 4 ;
         RETURN
      ELSIF ( NOT StandardizeFileName(Base.MKSfileName, 'MKS')) THEN
         MsgString( Base.MKSfileName, 0 );
         Str.Copy( TempStr, ' MKS ' ) ;
         MsgString( TempStr, 1 ) ;
         PutResError( 480 ) ;
         ReEdit := TRUE;
         MenuItem := 4 ;
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
   ReDisplay := FALSE;
END VerifyMKSFileName;


PROCEDURE VerifyInputFileName(Data:      ADDRESS;
                        VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO BaseDataRecord;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReDisplay := TRUE;
   ReEdit := FALSE ;
   DataP := DPtr(Data);
   WITH DataP^ DO
      TrimBlanks(Base.LSTFileName,Base.LSTFileName);
      IF Base.LSTFileName[0] = 0C THEN
        (*RES OLD MSG 479
        Input List File Name is required.
        *)
        PutResError((*RES REM INS*) 479 ) ;
        ReEdit := TRUE;
        MenuItem := 1 ;
        RETURN
      ELSIF ( NOT StandardizeFileName(Base.LSTFileName, 'LST')) THEN
         (*RES OLD MSG 480
         "%0" cannot be used as the name of an %1 file.
         *)
         MsgString( Base.LSTFileName, 0 );
         Str.Copy( TempStr, ' Input Str ') ;
         MsgString( TempStr , 1 ) ;
         PutResError( (*RES REM INS*) 480 ) ;
         ReEdit := TRUE;
         MenuItem := 1 ;
         RETURN
      END;
      IF NOT FIO.Exists(Base.LSTFileName) THEN
         (*RES OLD MSG 481
         Input List file "%0" was not found.
         *)
         MsgString( Base.LSTFileName, 0 );
         PutResError( (*RES REM INS*) 481 ) ;
         ReEdit := TRUE;
         MenuItem := 1 ;
        RETURN
      END;
      IF NOT ProcessParameters THEN
         IF Base.TDBFileName[0] = 0C THEN
           RemoveExtension( Base.LSTFileName, Base.TDBFileName ) ;
           VerifyOutFileName( Data, ReDisplay, ReEdit ) ;
         END ;
         IF Base.MKSfileName[0] = 0C THEN
           RemoveExtension( Base.LSTFileName, Base.MKSfileName ) ;
           VerifyMKSFileName( Data, ReDisplay, ReEdit ) ;
         END ;
         IF Base.BatchFileName[0] = 0C THEN
           RemoveExtension( Base.LSTFileName, Base.BatchFileName ) ;
           VerifyBatchFileName( Data, ReDisplay, ReEdit ) ;
         END ;
      END ;
   END;
   ReDisplay := FALSE;
END VerifyInputFileName;

PROCEDURE ProcessParams;

VAR plst,temp:  ParameterResult;
   str:         ARRAY[0..255] OF CHAR;
   i:           CARDINAL;
   m:           ARRAY [0..40] OF CHAR;
BEGIN
   Base.TDBTitle := 0C;
   Base.MKSfileName := 0C ;
   Base.MAKBAS := TRUE;
   Base.TDBRef := 0C;
   FoldLine := FALSE ;
   Base.Batch := FALSE ;
   InitialParams;
   LegalParameter('b',FALSE);
   LegalParameter('f',FALSE);
   LegalParameter('h',FALSE);
   LegalParameter('t',TRUE);
   LegalParameter('w',TRUE);
   LegalParameter('r',TRUE);
   LegalParameter('s',TRUE);
   i := 0;
   ProcessParameters := TRUE ;
   CASE GetParameters(plst,str) OF
      GPSOk: (* do nothing right now *)
   | GPSBadParameter:
        (*RES OLD MSG 428
        You cannot specify parameter "%0" for BuildBat.
        *)
        MsgString(str,0);
        PutResError( (*RES REM INS*) 428 );
        HALT;
   | GPSMissingValue:
        (*RES OLD MSG 429
        Parameter "%0" requires a parameter for BuildBat.
        *)
        MsgString(str,0);
        PutResError( (*RES REM INS*) 429 );
        HALT;
   END;
   WHILE plst <> NIL DO
      WITH plst^ DO
         CASE Code OF
          | 'B':
               Base.Batch := TRUE ;
          | 'F':
		FoldLine := FALSE ;
          | 'H':
                Base.MAKBAS := FALSE;
          | 'T':
               Str.Copy(Base.TDBTitle,Strg);
          | 'R':
               Str.Copy(Base.TDBRef,Strg);
          | 'W':
               Str.Copy(Base.TempDir,Strg);
               Str.Caps(Base.TempDir);
               IF Base.TempDir[Str.Length(Base.TempDir)-1] <> '\' THEN
                  Str.Append(Base.TempDir,'\');
               END;
          | 'S':
               Str.Copy(Base.MKSfileName,Strg);
               VerifyMKSFileName( ADR( Base ), ReDisplay, ReEdit ) ;
          | ' ':
               CASE i OF
                 0: Str.Copy(Base.LSTFileName, Strg);
                    VerifyInputFileName( ADR ( Base ) , ReDisplay, ReEdit ) ;
               | 1: Str.Copy(Base.TDBFileName,Strg);
                    VerifyOutFileName(ADR (Base) , ReDisplay, ReEdit ) ;
               | 2: Str.Copy(Base.BatchFileName,Strg);
                    VerifyBatchFileName( ADR( Base ) , ReDisplay, ReEdit ) ;
               ELSE
                 (*RES OLD MSG 431
                 BuildBat permits only three file names.
                 *)
                 PutResError( (*RES REM INS*) 431 );
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
   ProcessParameters := FALSE;
   IF (MenuItem = 0) AND (NOT ReEdit) AND (i > 0) THEN
      VerifyInputFileName( ADR ( Base ) , ReDisplay, ReEdit ) ;
   END ;
END ProcessParams;

PROCEDURE ProcessInputFile(VAR List:   FilePntr;
                           VAR Count:  CARDINAL);
VAR
   Filename:    ARRAY[0..100] OF CHAR;
   SFilename:   ARRAY[0..100] OF CHAR;
   Mode:	ARRAY[0..14] OF CHAR;
   F:           FIO.File;
   FID:         IDType;
   l:           CARDINAL;
   End,temp:    FilePntr;
   ErrorOccurred: BOOLEAN;
   ed:          BOOLEAN;
BEGIN
   ErrorOccurred := FALSE;
   List := NIL;
   Count := 0;
   End := NIL;
   WHILE XReadLine(InFile, '?', Filename, ed, IOresult) DO
      Utils.TrimBlanks( Filename, Filename ) ;
      IF Filename[0] <> 0C THEN		(* non blank line *)
        Str.Prepend( Filename, FilePath ) ;
	Utils.GetXlationType( Filename, Mode ) ;
	Str.Copy(SFilename,Filename);
	StandardizeFileNames(SFilename,'TDB',FALSE);
	IF NOT FIO.Exists(SFilename) THEN
	   Str.Copy(SFilename,Filename);
	   StandardizeFileNames(SFilename,'TXT',FALSE);
	   IF NOT FIO.Exists(SFilename) THEN
                (*RES OLD MSG 432
		File "%0" in your Input List was not found.
                *)
                MsgString(Filename, 0);
                PutResError( (*RES REM INS*) 432 );
		ErrorOccurred := TRUE;
	   END;
	END;
	F := FIO.OpenRead(SFilename);
	INC(Count);
	NEW(temp);
	Str.Copy(temp^.FileName ,SFilename);
	temp^.Next := NIL;
	FID[3] := 0C;
	l := FIO.RdBin(F,FID,SIZE(FID));
	FIO.Close(F);
	temp^.TDBFile := FID = TDBIDModel;
	IF Mode[0] <> 0C THEN
	   IF temp^.TDBFile THEN
                (*RES OLD MSG 433
		You misused @ mode for .TDB file "%0".
                *)
                MsgString(Filename, 0);
                PutResError( (*RES REM INS*) 433 );
		ErrorOccurred := TRUE;
	   ELSE
		Str.Append( temp^.FileName, "@" ) ;
		Str.Append( temp^.FileName, Mode ) ;
	   END ;
	END ;
	IF End = NIL THEN List := temp
	ELSE End^.Next := temp END;
	End := temp;
      END ;
   END;
   XClose(InFile);
   IF ErrorOccurred THEN HALT END;
END ProcessInputFile;

PROCEDURE ProcessGroup(Number:    CARDINAL;
                   VAR TDBResult: ARRAY OF CHAR;
                   VAR KeepTDB:   BOOLEAN);
VAR i,j,k:  CARDINAL;
    Names:  ARRAY[0..MaxNumbToMerge-1] OF ARRAY[0..40] OF CHAR;
    Keep:   ARRAY[0..MaxNumbToMerge-1] OF BOOLEAN;
    temp:   ARRAY[0..15] OF CHAR;
    text:   ARRAY[0..255] OF CHAR;
    dummy:  CARDINAL;

PROCEDURE GetInputName(VAR Name:  ARRAY OF CHAR;
                       VAR TDB:   BOOLEAN);
BEGIN
   Str.Copy(Name, Top^.FileName);
   TDB := Top^.TDBFile;
   Top := Top^.Next;
END GetInputName;

PROCEDURE CreateTempFileName(VAR str: ARRAY OF CHAR);
VAR tmp2: ARRAY[0..4] OF CHAR;
    ok:   BOOLEAN;
BEGIN
   Str.Copy(str,Base.TempDir);
   Str.Append(str,TmpStr);
   Str.CardToStr(LONGCARD(tempfno),tmp2,10,ok);
   INC(tempfno);
   Str.Append(str,tmp2);
   Str.Append(str,'.TDB');
END CreateTempFileName;

PROCEDURE DoInputGroup(start,stop: CARDINAL);
BEGIN
   FOR i := start TO stop DO
      GetInputName(Names[i-1],Keep[i-1]);
      IF (NOT Keep[i-1]) THEN
         IF Base.MAKBAS THEN Str.Copy(text, MakeBasString)
         ELSE Str.Copy(text, HSMS2TDBString) END;

	 IF FoldLine THEN
            Str.Append(text, '-f ');
	 END ;
         Str.Append(text, Names[i-1]);
         CreateTempFileName(Names[i-1]);
         Str.Append(text, ' ');
         Str.Append(text, Names[i-1]);
         IF Base.MKSfileName[0] <> 0C THEN
            Str.Append(text, ' ');
            Str.Append(text, Base.MKSfileName ) ;
         END ;
         dummy := XWrStr(OutFile,text, IOresult);
         XWrLn(OutFile, IOresult);
         dummy := XWrStr(OutFile,ErrorLevelString, IOresult);
         XWrLn(OutFile, IOresult);
      END;
   END;
END DoInputGroup;

BEGIN
   FOR i := 0 TO MaxNumbToMerge-1 DO
     Names[i] := 0C;
     Keep[i] := TRUE;
   END;
   IF Number <= MaxNumbToMerge THEN
      DoInputGroup(1,Number);
      IF Number = 1 THEN
         KeepTDB := Keep[0];
         Str.Copy(TDBResult,Names[0]);
         RETURN;
      END;
   ELSIF Number < 2 * MaxNumbToMerge THEN
      j := Number - MaxNumbToMerge + 1;
      ProcessGroup(j, Names[0],Keep[0]);
      DoInputGroup(2,MaxNumbToMerge);
   ELSE
      j := 0;
      FOR i := 1 TO MaxNumbToMerge DO
         Keep[i-1] := FALSE;
         k := ((i* Number) + MaxNumbToMerge-1) DIV MaxNumbToMerge;
         ProcessGroup(k - j,Names[i-1],Keep[i-1]);
         j := k;
      END;
   END;

   IF TDBResult[0] = 0C THEN
      CreateTempFileName(TDBResult)
   END;
   Str.Copy(text, MergeBasString);
   Str.Append(text, TDBResult);
   FOR i := 0 TO MaxNumbToMerge-1 DO
      IF (Names[i][0] <> 0C) THEN
      Str.Append(text, ' ');
      Str.Append(text, Names[i]);
      END;
   END;
   dummy := XWrStr(OutFile,text, IOresult);
   XWrLn(OutFile, IOresult);
   dummy := XWrStr(OutFile, ErrorLevelString, IOresult);
   XWrLn(OutFile, IOresult);
   FOR i := 0 TO MaxNumbToMerge-1 DO
      IF (NOT Keep[i]) THEN
         dummy := XWrStr(OutFile, EraseString, IOresult);
         dummy := XWrStr(OutFile, Names[i], IOresult);
         XWrLn(OutFile,IOresult);
      END;
   END;
   KeepTDB := FALSE;
END ProcessGroup;
PROCEDURE TerminateAll;
  VAR
	ch   : CHAR ;
	oldw : TWB.WinType;

   BEGIN
	(*RES OLD CHE 34
	=Y N
	Do you wish to stop BuildBat immediately? Y)es or N)o.
	*)
	oldw := TWB.Used();
	ResAskUser( (*RES REM INS*) 34, 'YN', ch);
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
         ELSIF (ch = PCKey.F6) THEN (* m.s. - apr 94 *)
            ShowCredit( 73, TermList, ExitList, ch, Ext ) ;
            Done := FALSE ;
         ELSIF ch = PCKey.F10 THEN TerminateAll END;
      ELSE
         Ext := FALSE;
      END;
   UNTIL Done;
END ReadTheKeyStrokes;

PROCEDURE DoSetup;
(*RES OLD MNU 51

                  BuildBat Version %9__ %10________________________


             Input List Filename: %0_______________________________
            Output .TDB Filename: %1_______________________________

                  Batch Filename: %2_______________________________
                   .MKS Filename: %3_______________________________
                     Working Dir.: %4_______________________________

                       .TDB Title:  %5______________________________
                    .TDB Name Ref:  %6______________________________

                     MAKEBASE: %|7  HSMS2TDB: %|8

_____________________________________________________________________________
F1: Help                                   F9: RUN, creating batch file
                                          F10: QUIT without doing anything
*)

(*RES OLD MNU 56

                  BuildBat Version %9_____ %10________________________


   Input List Filename:    %0___________________________________________
   Output .TDB Filename:   %1___________________________________________

   .BAT Filename:          %2___________________________________________
   .MKS Filename:          %3___________________________________________
   Temporary File Area:    %4___________________________________________

   .TDB Title:             %5___________________________________________
   Starting Ref. Template: %6___________________________________________


                       MakeBase: %|7  HSMS2TDB: %|8

_____________________________________________________________________________
   F1: Help                                 F9: RUN, creating batch file
   F6: Credits                             F10: QUIT without doing anything


*)

CONST
   MainMenuResWithHMS = (*RES REM INS*) 51 ; (* m.s. - not used right now *)
   MainMenuRes = (*RES REM INS*) 56 ;
VAR
   FrontMenu: MenuID;
   BaseWind:  WindowInfo;
   VerLen,DatLen,
   VerX,DatX,
   VerY,DatY: CARDINAL;
   Work:      ARRAY[0..255] OF CHAR;
   drive, path, name, ext : ARRAY[0..25] OF CHAR ;

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

   Base.LSTFileName[0] := 0C ;
   Base.TDBFileName[0] := 0C ;
   Base.BatchFileName[0] := 0C ;
   Base.MKSfileName[0] := 0C ;
   StartMenu(Base);
   WITH Base DO
     CharFieldProc(LSTFileName, VerifyInputFileName);
     CharFieldProc(TDBFileName, VerifyOutFileName);
     CharFieldProc(BatchFileName, VerifyBatchFileName);
     CharFieldProc(MKSfileName, VerifyMKSFileName);
     CharField(TempDir);
     CharField(TDBTitle);
     CharField(TDBRef);
     Switches(MAKBAS);
        SwitchValue(TRUE);
        SwitchValue(FALSE);
   END;

   MakeMenu( MainMenuRes , FrontMenu);
   GetFieldInfo(FrontMenu,9,VerX,VerY,VerLen);
   GetFieldInfo(FrontMenu,10,DatX,DatY,DatLen);

   PushNewWindow(BaseWind, BaseWPtr, DummyInit);
   ShowFixedText(BaseWPtr,FrontMenu,0,0);
   WriteScreenField( BaseWPtr, VerLen, VerX, VerY,
                          SystemVersion, RegularAttr, TRUE );
   WriteScreenField( BaseWPtr, DatLen, DatX, DatY,
                          SystemVersionDate, RegularAttr, TRUE );

   TWB.GotoXY(0, 21);
   TWB.ClrEol;
   TWB.WrStr('        Copyright (c) 1995 TACT Group, University of Toronto');
   TWB.WrLn ;

   DoMenuNow := TRUE ;
   KeyTerm[0] := ASCII.rs ;
   FunctTerm[0] := PCKey.F9 ;
   ReEdit := FALSE ;
   ReDisplay := TRUE ;
   OverWriteOut := FALSE ;
   MenuItem := 0;
   ProcessParams;
   IF (NOT Base.Batch) OR ReEdit OR ReDisplay THEN
     REPEAT
       ReEdit := FALSE ;
       ShowMenu(BaseWPtr,FrontMenu,0,0,Base);
       DoMenu(BaseWPtr,FrontMenu,0,0,KeyTerm, FunctTerm,
                      Base,MenuItem,TC,FunctKey);
     UNTIL ReEdit = FALSE ;
  END ;
  DestroyMenu(FrontMenu);

   IF NOT XOpenInput(Base.LSTFileName, 'LST',SCREENString,InFile,ErrorMsg) THEN
      MsgString(Base.LSTFileName, 0);
      MsgString(ErrorMsg, 0);
      PutResError( FileProblemMessage );
      HALT;
   END;
   IF NOT XOpenOutput(Base.BatchFileName, 'BAT',SCREENString,OutFile,ErrorMsg) THEN
      MsgString(Base.BatchFileName, 0);
      MsgString(ErrorMsg, 0);
      PutResError( FileProblemMessage );
      HALT;
   END;
   IF ParseFilename( Base.LSTFileName, drive, path, name, ext ) THEN
     (* should always get here *)
     Str.Concat( FilePath, drive, path ) ;
   END ;
   IF Base.TDBTitle[0] <> 0C THEN
      Str.Append(Base.TDBFileName,' -t "');
      Str.Append(Base.TDBFileName,Base.TDBTitle);
      Str.Append(Base.TDBFileName,'"');
   END;
   IF Base.TDBRef[0] <> 0C THEN
      Str.Append(Base.TDBFileName,' -r "');
      Str.Append(Base.TDBFileName,Base.TDBRef);
      Str.Append(Base.TDBFileName,'"');
   END;
   Str.Caps(Base.TempDir);
   IF (Base.TempDir[0] <> 0C) AND (Base.TempDir[Str.Length(Base.TempDir)-1] <> '\')
      THEN
      Str.Append(Base.TempDir,'\');
   END;
END DoSetup;

PROCEDURE WriteOutEndOfFile;
VAR
   ResC:    ResCollectionType;
   Text:    ARRAY [0..100] OF CHAR;
BEGIN
   (*RES OLD DTA 28
     'goto Finish'
     ':Terminate'
     'echo off'
     'echo Batch terminating prematurely, either at your request or'
     'echo a program failed.  Examine partial results (ie. *.ERR files)'
     'echo or .TDB files.  Remember to DELETE TMP*.TDB files before'
     'echo invoking batch again.'
     ':Finish'
   *)
   GetDataArray( (*RES REM INS*) 28 , ResC);

   WHILE GetNextDataArrayStringItem(ResC,Text) DO
      dummy := XWriteLine(OutFile, '?', Text, IOresult);
   END;

   ReleaseCollection(ResC);
END WriteOutEndOfFile;

PROCEDURE GetTextConstants;
VAR
   ResC:    ResCollectionType;
   dummy:   BOOLEAN;
BEGIN
   (*RES OLD DTA 29
      'MAKEBASE -b '
      'HSMS2TDB -b '
      'MERGEBAS -b -o '
      'ERASE '
      'if ERRORLEVEL 1 goto Terminate'
      'SCREEN'
   *)
   GetDataArray( (*RES REM INS*) 29 , ResC);
   dummy := GetNextDataArrayStringItem(ResC,MakeBasString);
   dummy := GetNextDataArrayStringItem(ResC,HSMS2TDBString);
   dummy := GetNextDataArrayStringItem(ResC,MergeBasString);
   dummy := GetNextDataArrayStringItem(ResC,EraseString);
   dummy := GetNextDataArrayStringItem(ResC,ErrorLevelString);
   dummy := GetNextDataArrayStringItem(ResC,SCREENString);
   ReleaseCollection(ResC);
END GetTextConstants;

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

   (*RES OLD MSG 434
         buildbat -b -f -h -r "<template>" -s <.MKS filename> -t "<title>" -w <path>
         <.LST filename> <.TDB filename> <.BAT filename>
   *)
   CheckParam( 434 ) ;

   InitWindows() ;
   IF NOT InitialTranslationData() THEN HALT END;
   PushHelpItem(55); (* Help Res 30 is BuildBat's single help item *)
   TermList[0] := ASCII.rs;
   TermList[1] := ASCII.esc;
   ExitList := 0C;

END BeginEverything;

BEGIN
   Base.TempDir := 0C;

   GetKeyStroke := ReadTheKeyStrokes;

   BeginEverything;

   GetTextConstants;
   DoSetup;


   ProcessInputFile(Top, NumbFiles);

   tempfno := 0;
   ProcessGroup(NumbFiles, Base.TDBFileName, dummy);

   WriteOutEndOfFile;

   XClose(OutFile);
   EndWindows ;
   (*RES OLD MSG 502
   Batch File Created Successfully:
   *)
   GetResMessage( 502, FilePath ) ;
   IO.WrStr( FilePath ) ;
   IO.WrStr( '  ') ;
   IO.WrStr(Base.BatchFileName ) ;
   IO.WrLn ;
END BuildBat.
