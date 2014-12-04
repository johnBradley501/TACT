MODULE TACTSort;

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
FROM SYSTEM IMPORT TSIZE ;
FROM Str IMPORT Copy, Compare  ;
FROM GetParams IMPORT
  (* types *) GetParametersStatus, ParameterResult, ParameterData,
  (* procs *) LegalParameter, GetParameters, InitialParams;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM GlobalDefs IMPORT StrAny, TDBExtension, CheckResVersion,
     SystemVersion, SystemVersionDate, CheckParam;
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
   Numeric = TRUE ;
   Text    = FALSE ;
   Ascending = TRUE ;
   Descending = FALSE ;

(*RES OLD MNU 63
 Status: %0_________________________________________________________________
 *)

   StatusMenuResID = (*RES REM INS*) 63 ;

   FileHeaderResource = 113 ;	(* >> MSG defined in MAKBAS: SetupFil.MOD << *)

TYPE
   FileData = RECORD
      InputName:  ARRAY[0..64] OF CHAR;
      OutputName:  ARRAY[0..64] OF CHAR;
      FieldNum: CARDINAL ;
      SortOrder : BOOLEAN ;
      Format : BOOLEAN ;
      MKSfileName: ARRAY[0..64] OF CHAR ;
      TempDiskArea : ARRAY[0..64] OF CHAR ;
   END;

   DataRecType = RECORD
      Key : ARRAY[0..31] OF CHAR ;
      Line: ARRAY[0..95] OF CHAR ;
   END;
   DataRecPtr = POINTER TO DataRecType ;

   NumRecType = RECORD
      Key : LONGREAL ;
      Line: ARRAY[0..95] OF CHAR ;
   END;
   NumRecPtr = POINTER TO NumRecType ;

   ConvertProc = PROCEDURE( ADDRESS ) ;

   CompareProc = PROCEDURE( ADDRESS, ADDRESS): BOOLEAN ;

VAR
   Convert : ConvertProc ;
   TCompare : CompareProc ;

 CONST
   DataRecSize = TSIZE( DataRecType ) ;
   NumRecSize = TSIZE( NumRecType ) ;


VAR
   DataRec : DataRecPtr ;
   NumRec : NumRecPtr ;
   InputFileName, OutFileName : StrAny ;
   InputID:      BFile;
   OutputID:      BFile;
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


PROCEDURE VerifyOutputFileName( VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
VAR
   Ch : CHAR ;
BEGIN
   ReDisplay := TRUE;
   TrimBlanks(Base.OutputName,Base.OutputName);
   Str.Caps( Base.OutputName ) ;
   IF Base.OutputName[0] = 0C THEN
         ReEdit := TRUE;
         MenuItem := 2 ;
         RETURN;
   END ;
   IF ( NOT StandardizeFileName(Base.OutputName, 'SRT')) THEN
         (*RES OLD MSG 295
         "%0" cannot be used as the name of a file.
         *)
         MsgString( Base.OutputName, 0 );
         PutResError( (*RES REM INS*) 295 ) ;
         ReEdit := TRUE;
         MenuItem := 2;
         RETURN ;
   END;
   IF FIO.Exists(Base.OutputName) AND NOT OverWriteOut THEN
	 (*RES OLD CHE 32
	 The output filename "%0" already exists. Please choose
	 between N)ew name and O)verwrite file:
	 = N O
	 *)
	 MsgString(Base.OutputName, 0 );
	 ResAskUser( (*RES REM INS *) 32 , 'NO', Ch ) ;
	 IF Ch = 'O' THEN
	    OverWriteOut := TRUE ;
	 ELSE
	    OverWriteOut := FALSE ;
	    MenuItem  := 2 ;
	    ReEdit := TRUE ;
	 END ;
      END;
END VerifyOutputFileName;


PROCEDURE VerifyMKSFileName(Data:      ADDRESS;
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



PROCEDURE VerifyInputFileName( VAR ReDisplay: BOOLEAN;
                        VAR ReEdit: BOOLEAN);
TYPE
   DPtr = POINTER TO FileData;
VAR
   DataP:    DPtr;
   r:        CARDINAL;
   m, TempStr:        ARRAY[0..30] OF CHAR;
BEGIN
   ReDisplay := TRUE ;
      TrimBlanks(Base.InputName,Base.InputName);
      Str.Caps( Base.InputName ) ;
      TrimBlanks(Base.OutputName,Base.OutputName);
      Str.Caps( Base.OutputName ) ;
      IF Base.InputName[0] = 0C THEN
         ReEdit := TRUE;
         MenuItem := 1 ;
         RETURN
      END;
      IF Base.OutputName[0] = 0C THEN
        RemoveExtension( Base.InputName, Base.OutputName ) ;
        MakeFilename(drive,path,Base.OutputName,'SRT', Base.OutputName );
      END ;
      IF Base.MKSfileName[0] = 0C THEN
           RemoveExtension( Base.InputName, Base.MKSfileName ) ;
           VerifyMKSFileName( ADR(Base), ReDisplay, ReEdit ) ;
      END ;

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

      IF TDADone THEN  (* m.s. - change extender swap drive *)
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
	IF Str.Compare(OldTempDiskArea,Base.TempDiskArea) = 0 THEN RETURN END;
	Str.Copy( OldTempDiskArea, Base.TempDiskArea) ;
	ReDisplay := TRUE;
	MenuItem  := 9 ;
	IF NOT VerifyTDA(Base.TempDiskArea) THEN ReEdit := TRUE END;
   END CheckTDA;


PROCEDURE ProcessParams;

VAR plst,temp:  ParameterResult;
   str:         ARRAY[0..255] OF CHAR;
   i:           CARDINAL;
   m:           ARRAY [0..40] OF CHAR;
BEGIN
   InitialParams;
   LegalParameter('b',FALSE);
   LegalParameter('s',TRUE);
   LegalParameter('n',TRUE);
   LegalParameter('a',FALSE);
   LegalParameter('d',FALSE);
   LegalParameter('w',TRUE);
   LegalParameter('?',FALSE); (* m.s. *)
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
          | 'A':
               Base.Format := Numeric ;
          | 'D':
               Base.SortOrder := Descending;
          | 'N' :
               Base.FieldNum := CARDINAL( Str.StrToCard( Strg, 10, dummy )) ;
          | 'S' :
               Str.Copy(Base.MKSfileName, Strg);
               VerifyMKSFileName( ADR(Base), ReDisplay, ReEdit ) ;
 	       IF ReEdit THEN RETURN END;
          | 'W':	(* Temp Disk Area:  -w <TDA>		*)
		Str.Copy( Base.TempDiskArea, Strg );
		CheckTDA( ADR(Base), ReDisplay, ReEdit );
		IF ReEdit THEN RETURN END;
          | ' ':
               CASE i OF
                 0: Str.Copy(Base.InputName, Strg);
               | 1: Str.Copy(Base.OutputName,Strg);
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
   VerifyInputFileName( ReDisplay, ReEdit ) ;
   IF NOT ReEdit THEN
      VerifyOutputFileName( ReDisplay, ReEdit );
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
	(*RES OLD CHE 53
	=Y N
	Do you wish to stop TACTSort immediately? Y)es or N)o.
	*)
	oldw := TWB.Used();
	ResAskUser( (*RES REM INS*) 53 , 'YN', ch);
	TWB.Use(oldw);
	IF ch <> 'Y' THEN  RETURN  END ;
        Terminate(Normal)
   END TerminateAll;

PROCEDURE ReadTheKeyStrokes(VAR ch: CHAR; VAR Ext: BOOLEAN);
VAR Done:   BOOLEAN;
    DoRead: BOOLEAN;
    oldw: TWB.WinType;
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
            ShowCredit( 79, TermList,ExitList,ch,Ext);
            Done := FALSE ;
         ELSIF ch = PCKey.F10 THEN TerminateAll END;
      ELSE
         Ext := FALSE;
      END;
   UNTIL Done;
END ReadTheKeyStrokes;



PROCEDURE ConvertLine( DataRec : DataRecPtr ) ;

VAR
   LI, LO : ARRAY [0..127] OF CHAR ;
   al, ns : CARDINAL ;

BEGIN
      Str.ItemS( LI, DataRec^.Line, 11C, Base.FieldNum ) ;
      XlateLine( File2Int, 1C, LI, cm, al, LenD, ns, dummy, LO ) ;
      IntToSortLine( LO, LO ) ;
      IF LO[0] = 0C THEN (* if not part of alphabet i.e. punctuation etc.*)
         Copy( LO, LI ) ;
      END ;
      Copy( DataRec^.Key, LO ) ;
END ConvertLine ;

PROCEDURE ConvertNumLine( DataRec : NumRecPtr ) ;

VAR
   LI: ARRAY [0..127] OF CHAR ;
   OK: BOOLEAN ;
   ch : CHAR ;
BEGIN
      Str.ItemS( LI, DataRec^.Line, 11C, Base.FieldNum ) ;
      IF LI[0] = ' ' THEN
        WHILE LI[0] = ' ' DO
          Str.Delete( LI, 0, 1);
        END ;
      END ;
      DataRec^.Key := Str.StrToReal( LI, OK ) ;
      IF OK = FALSE THEN
	(*RES OLD CHE 54
	=S C
	Could not process field %0 of line "%1" as a number. Do you wish to stop immediately,
	or substitute 0 and continue? S)top or C)ontinue.
	*)
        MsgCard(Base.FieldNum,0);
        MsgString(DataRec^.Line,1);
	ResAskUser( (*RES REM INS*) 54 , 'SC', ch);
	IF ch <> 'S' THEN
	   DataRec^.Key := 0.0;
	ELSE
           Terminate(Normal) ;
        END ;
      END ;
END ConvertNumLine ;


PROCEDURE SortLine( DataRec : DataRecPtr ) ;

VAR
    al, ns : CARDINAL ;
BEGIN
      XlateLine( File2Int, 1C, DataRec^.Line, cm, al, LenD, ns, dummy, DataRec^.Key ) ;
      IntToSortLine( DataRec^.Key, DataRec^.Key ) ;
END SortLine ;

PROCEDURE LessDescendingCompare( X, Y : DataRecPtr ) : BOOLEAN ;
   BEGIN
(*	INC(Count);
	Percentage := VAL(CARDINAL, (Count * 100) DIV NoRules) ;
	IF Percentage >= LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage ) ;
		LastPercentage := Percentage ;
	END ;
*)
        IF  Compare(X^.Key , Y^.Key ) > 0  THEN
              RETURN TRUE
	END ;
	RETURN FALSE ;
END LessDescendingCompare ;

PROCEDURE LessAscendingCompare( X, Y : DataRecPtr ) : BOOLEAN ;
   BEGIN
(*	INC(Count);
	Percentage := VAL(CARDINAL, (Count * 100) DIV NoRules) ;
	IF Percentage >= LastPercentage THEN
		IF Percentage >= 100 THEN
		   Percentage := 99	(* fake a reasonable value *)
		END ;
		PutPercentage( Percentage ) ;
		LastPercentage := Percentage ;
	END ;
*)
        IF  Compare(X^.Key , Y^.Key ) < 0  THEN
              RETURN TRUE
	END ;
	RETURN FALSE ;
   END LessAscendingCompare ;

PROCEDURE NumAscendingCompare( X, Y : NumRecPtr ) : BOOLEAN ;
  BEGIN
    RETURN (X^.Key > Y^.Key ) ;
END NumAscendingCompare ;

PROCEDURE NumDescendingCompare( X, Y : NumRecPtr ) : BOOLEAN ;
  BEGIN
    RETURN (X^.Key < Y^.Key ) ;
END NumDescendingCompare ;

PROCEDURE DoSetup;
(*RES OLD MNU 64

                      TACTSort Version %9____ %10________________________


   Input Text Filename: %0________________________________________________
   Output Filename:     %1________________________________________________

   Field Number to Compare:        %2_
   Numeric Field to be Compared:   Yes: %|3  No: %|4
   Sort Order: Descending/Alphabetical: %|5 Ascending/Reverse Order: %|6

   .MKS Filename:       %7________________________________________________
   Temporary File Area: %8________________________________________________



_____________________________________________________________________________
   F1: Help                                F9: RUN, creating sorted file
   F6: Credits                            F10: QUIT without doing anything
*)


CONST
   MainMenuRes = (*RES REM INS*) 64 ;
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

   StartMenu(Base);
   WITH Base DO
     CharField(InputName);
     CharField(OutputName);
     CardField(FieldNum) ;
     Switches(Format) ;(* m.s. *)
        SwitchValue(Numeric) ;
        SwitchValue(Text) ;
     Switches(SortOrder) ;(* m.s. *)
        SwitchValue(Ascending) ;
        SwitchValue(Descending) ;

     CharFieldProc(MKSfileName, VerifyMKSFileName);
     CharFieldProc(TempDiskArea, CheckTDA ) ;
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
   TWB.WrStr('             Copyright (c) 1995 TACT Group, University of Toronto');
   TWB.WrLn ;

   DoMenuNow := TRUE ;
   KeyTerm[0] := ASCII.rs ;
   FunctTerm[0] := PCKey.F9 ;
   Base.SortOrder := Ascending ;
   Base.Format := Text ;
   ReEdit := FALSE ;
   BatchMode := FALSE ;
   MenuItem := 1;

   ProcessParams;

   IF ReEdit OR NOT BatchMode THEN
   REPEAT
      ReEdit := FALSE ;
      ShowMenu(BaseWPtr,FrontMenu,0,0,Base);
      DoMenu(BaseWPtr,FrontMenu,0,0,KeyTerm, FunctTerm,
                      Base,MenuItem,TC,FunctKey);
      VerifyInputFileName( ReDisplay, ReEdit ) ;
      IF NOT ReEdit THEN
         VerifyOutputFileName( ReDisplay, ReEdit ) ;
      END ;
      IF NOT ReEdit THEN
         VerifyMKSFileName( ADR(Base), ReDisplay, ReEdit ) ;
      END ;
      IF NOT ReEdit THEN
         CheckTDA( ADR(Base) , ReDisplay, ReEdit ) ;
      END ;
      IF ( Base.Format = Numeric ) AND ( Base.FieldNum = 0 ) THEN
         (*RES OLD MSG 568
         If you select a numeric comparison you must specify a field to
         compare (nonzero).
         *)
         PutResError( (*RES REM INS*) 568) ;
         ReEdit := TRUE;
         MenuItem := 6 ;
      END ;
  UNTIL ReEdit = FALSE ;
  END ;
  DestroyMenu(FrontMenu);

  BOpen( InputID, Base.InputName, ReadType, IOResult) ;
  IF IOResult <> 0  THEN
      IOErrorMessage( IOResult, ErrorMsg ) ;
      MsgString(Base.InputName, 0);
      MsgString(ErrorMsg, 0);
      PutResError( FileProblemMessage );
      HALT;
   END;
   Convert := SortLine ;
   IF Base.FieldNum > 0 THEN
           DEC(Base.FieldNum) ; (* ItemS in 0 based *)
           dummy := ReadLine( InputID, TempStr, EnoughData, IOResult ) ;
           Str.ItemS( TempStr, TempStr, 11C, Base.FieldNum ) ;
           IF TempStr[0] <> 0C THEN (* field exists, use ConvertLine *)
              Convert := ConvertLine ;
           END ;
   END ;
  IF Base.Format = Numeric THEN
     Convert := ConvertNumLine ;
     IF Base.SortOrder = Descending THEN
        TCompare := NumDescendingCompare ;
     ELSE
        TCompare := NumAscendingCompare ;
     END ;
  ELSE (* Base.Format = Text *)
     IF Base.SortOrder = Descending THEN
        TCompare := LessDescendingCompare;
     ELSE
        TCompare := LessAscendingCompare ;
     END ;
  END ;

  BClose( InputID, IOResult ) ;
  BOpen( InputID, Base.InputName, ReadType, IOResult) ;

  BOpen( OutputID, Base.OutputName, WriteType, IOResult) ;
  IF IOResult <> 0  THEN
      IOErrorMessage( IOResult, ErrorMsg ) ;
      MsgString(Base.OutputName, 0);
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

   (*RES OLD MSG 580
   tactsort -a -b -d -n <field number> -s <.MKS filename> -w <path> <input
   text filename> <output .SRT filename>
   *)

   CheckParam( (*RES REM INS*) 580) ;

   InitWindows() ;
   IF NOT InitialTranslationData() THEN HALT END;
   PushHelpItem(66); (* Help Res 66 is TACTSort's single help item *)
   TermList[0] := ASCII.rs;
   TermList[1] := ASCII.esc;
   ExitList := 0C;

END BeginEverything;


PROCEDURE GetInput ;  (* m.s. - read words in *)

VAR
    Result : CARDINAL ;
    EnoughData : BOOLEAN ;
    BadChar : CHAR ;
     AL,NS: CARDINAL;
     ED:    BOOLEAN;
BEGIN
     Count := 0 ;
(*     LastPercentage := 0 ; *)
     (*RES OLD MSG 565
     Reading file for sorting... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 565 );
     dummy := ReadLine( InputID, DataRec^.Line, EnoughData, Result ) ;
     WHILE Result = 0 DO
           INC(Count);
(*         Percentage := VAL (CARDINAL , (Count * 100) DIV NoRules) ;
           IF Percentage >= LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage ) ;
              LastPercentage := Percentage ;
           END ;
*)
(*           XlateLine( File2Int, BadChar, DataRec^.Key, cm, AL, LenD, NS, EnoughData, DataRec^.Key ) ;
           IntToSimpleSortLine( DataRec^.Key, TRUE, DataRec^.Key ) ;
*)
           Convert( DataRec ) ;
           LSortRelease( DataRec ) ;
           dummy := ReadLine( InputID, DataRec^.Line, EnoughData, Result ) ;
     END ;
     IF Base.SortOrder = Ascending THEN
        DataRec^.Key[0] := 255C ;	(* dummy sentinal record *)
        DataRec^.Line[0] := 255C ;
     ELSE
        DataRec^.Key[0] := 0C ;	(* dummy sentinal record *)
        DataRec^.Line[0] := 0C ;
     END ;
     LSortRelease( DataRec ) ;

     BClose( InputID, Result ) ;

     Count := 0 ;
(*     LastPercentage := 0 ; *)
     (*RES OLD MSG 566
     Sorting file... Please Wait.
     *)
     PutRunStatus( (*RES REM INS*) 566 ) ;
(*     NoCompares := Count * VAL(LONGCARD, Log2(Count) + 4 ) ; *)
(*     PutPercentage( 0 ) ; *)
END GetInput ;

PROCEDURE GetNumInput ;  (* m.s. - read words in *)

VAR
    Result : CARDINAL ;
    EnoughData : BOOLEAN ;
    BadChar : CHAR ;
     AL,NS: CARDINAL;
     ED:    BOOLEAN;
BEGIN
     Count := 0 ;
(*     LastPercentage := 0 ; *)
     (*RES OLD MSG 565
     Reading file for sorting... Please wait.
     *)
     PutRunStatus( (*RES REM INS*) 565 );
     dummy := ReadLine( InputID, NumRec^.Line, EnoughData, Result ) ;
     WHILE Result = 0 DO
           INC(Count);
(*         Percentage := VAL (CARDINAL , (Count * 100) DIV NoRules) ;
           IF Percentage >= LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage ) ;
              LastPercentage := Percentage ;
           END ;
*)
           Convert( NumRec ) ;
           LSortRelease( NumRec ) ;
           dummy := ReadLine( InputID, NumRec^.Line, EnoughData, Result ) ;
     END ;
     IF Base.SortOrder = Descending THEN
        NumRec^.Key := MAX(REAL) ;
        NumRec^.Line[0] := 255C ;
     ELSE
        NumRec^.Key := MIN(REAL) ;
        NumRec^.Line[0] := 255C ;
     END ;
     LSortRelease( NumRec ) ;

     BClose( InputID, Result ) ;

     Count := 0 ;
(*     LastPercentage := 0 ; *)
     (*RES OLD MSG 566
     Sorting file... Please Wait.
     *)
     PutRunStatus( (*RES REM INS*) 566 ) ;
(*     NoCompares := Count * VAL(LONGCARD, Log2(Count) + 4 ) ; *)
(*     PutPercentage( 0 ) ; *)
END GetNumInput ;



PROCEDURE GetOutput ;  (* m.s. - output sorted lines to file *)

VAR
    Result : CARDINAL ;
BEGIN
     BOpen( OutputID, Base.OutputName, WriteType, Result ) ;
     IF IOResult <> 0  THEN
        IOErrorMessage( IOResult, ErrorMsg ) ;
        MsgString(OutFileName, 0);
        MsgString(ErrorMsg, 0);
        PutResError( FileProblemMessage );
        HALT;
     END;
     LSortReturn( DataRec ) ;

     (* set status value for next phase *)
     Count := 0 ;
(*     LastPercentage := 0 ; *)
     (*RES OLD MSG 567
     Outputting sorted file... Please Wait.
     *)
     PutRunStatus((*RES REM INS*) 567 );

     WHILE NOT LSortEOS() AND NOT AbortForFileIO() DO
(*        Percentage := VAL(CARDINAL, ( LONGCARD(RuleID) * 100 ) DIV NoRules) ;
        IF Percentage >= LastPercentage THEN
 	  IF Percentage >= 100 THEN
	    Percentage := 99	(* fake a reasonable value *)
	  END ;
          PutPercentage( Percentage ) ;
          LastPercentage := Percentage ;
        END ;
*)
        WriteLine( OutputID, DataRec^.Line, Result ) ;
        LSortReturn( DataRec ) ;
     END ;
     BClose( OutputID, Result ) ;
END GetOutput ;

PROCEDURE GetNumOutput ;  (* m.s. - output sorted lines to file *)

VAR
    Result : CARDINAL ;
BEGIN
     BOpen( OutputID, Base.OutputName, WriteType, Result ) ;
     IF IOResult <> 0  THEN
        IOErrorMessage( IOResult, ErrorMsg ) ;
        MsgString(OutFileName, 0);
        MsgString(ErrorMsg, 0);
        PutResError( FileProblemMessage );
        HALT;
     END;
     LSortReturn( NumRec ) ;

     (* set status value for next phase *)
     Count := 0 ;
(*     LastPercentage := 0 ; *)
     (*RES OLD MSG 567
     Outputting sorted file... Please Wait.
     *)
     PutRunStatus((*RES REM INS*) 567 );

     WHILE NOT LSortEOS() AND NOT AbortForFileIO() DO
(*        Percentage := VAL(CARDINAL, ( LONGCARD(RuleID) * 100 ) DIV NoRules) ;
        IF Percentage >= LastPercentage THEN
 	  IF Percentage >= 100 THEN
	    Percentage := 99	(* fake a reasonable value *)
	  END ;
          PutPercentage( Percentage ) ;
          LastPercentage := Percentage ;
        END ;
*)
        WriteLine( OutputID, NumRec^.Line, Result ) ;
        LSortReturn( NumRec ) ;
     END ;
     BClose( OutputID, Result ) ;
END GetNumOutput ;

PROCEDURE DumpSortError( SortResult : CARDINAL ) ;

VAR     MsgId : CARDINAL ;

BEGIN
   CASE SortResult OF
 	   0 : (* Sorted OK *)	|
 	   3 :
 		(*RES OLD MSG 311
 		Insufficient available Lower Memory caused sorting to fail.)
 		*)
 		MsgId := (*RES REM INS *) 311 ; |
 	   8 :
 		(*RES OLD MSG 312
 		Sorting failed when a too-long word was encountered.
 		*)
 		MsgId := (*RES REM INS *) 312 ; |
 	   9 :
 		(*RES OLD MSG 313
 		Sorting failed when more than 2,147,483,647 words encountered in the .TDB.
 		*)
 		MsgId := (*RES REM INS *) 313 ; |
 	   10 :
 		(*RES OLD MSG 314
 		Sorting failed because the disk is full.
 		*)
 		MsgId := (*RES REM INS *) 314 ; |
 	   11 :
 		(*RES OLD MSG 315
 		Sorting failed because of a read-error.
 		*)
 		MsgId := (*RES REM INS *) 315 ; |
 	   12 :
 		(*RES OLD MSG 316
 		Sorting Failed Because there are too many Files in the Directory
 		Where the Temporary Sort File was to Go.
 		*)
 		MsgId := (*RES REM INS *) 316 ; |
 	   ELSE
 		(*RES OLD MSG 317
 		Sorting failed because of an unknown return code (%0).
 		*)
 		MsgId := (*RES REM INS *) 317 ;
 	   END ;
 	   CASE SortResult OF
 	     3, 8, 9, 10, 11, 12: ; (* do nothing *)
 	     ELSE
 		MsgCard( SortResult, 0);
 	     END ;
 	   PutResError( MsgId );

END DumpSortError ;


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
        (* sort input files *)
        IF Base.Format = Text THEN
           ALLOCATE( DataRec, DataRecSize ) ;
           IF (Base.SortOrder = Descending) THEN
      	      SortResult := LTurboSort( DataRecSize, GetInput, LessDescendingCompare, GetOutput,
				  Base.TempDiskArea ) ;
           ELSE
      	      SortResult := LTurboSort( DataRecSize, GetInput, LessAscendingCompare, GetOutput,
				  Base.TempDiskArea ) ;
	   END;			
        ELSE
           ALLOCATE( NumRec, NumRecSize ) ;
           IF (Base.SortOrder = Descending ) THEN
   	      SortResult := LTurboSort( NumRecSize, GetNumInput, NumDescendingCompare, GetNumOutput,
				  Base.TempDiskArea ) ;
           ELSE
   	      SortResult := LTurboSort( NumRecSize, GetNumInput, NumAscendingCompare, GetNumOutput,
				  Base.TempDiskArea ) ;
            END ;
	END ;			
	IF SortResult <> 0 THEN
           DumpSortError( SortResult ) ;
           HALT ;
	END ;
END Run ;
BEGIN

   GetKeyStroke := ReadTheKeyStrokes;

   BeginEverything  ;

   cm.ModeIn := '0' ;
   cm.ModeOut := '0' ;
   OldTempDiskArea[0] := 0C ;

   DoSetup;

   Run;

   EndWindows ;
   (*RES OLD MSG 564
   TACTSort completed successfully.
   *)
   GetResMessage( (*RES REM INS*) 564 , MsgTxt ) ;
   IO.WrStr( MsgTxt ) ;
   IO.WrLn ;
END TACTSort.
