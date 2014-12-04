IMPLEMENTATION MODULE TACTInit;

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

(* This is code to start off TACT -- verifies databases, and reads in *)
(* initial data from them.                                            *)

(*
Dec 4, 1989 -- L.Presutti
- added 0C termination to "ExitList" and "TermList".  Also modified .DEF definitions
  caused some DoMenus to prematurely terminate on some junk chars.
*)

FROM SYSTEM IMPORT SIZE, ADR;
IMPORT TWB, Str, ASCII, PCKey, FIO ;
FROM Storage IMPORT
  (* Vars  *) MainHeap,
  (* Procs *) HeapTotalAvail ;
FROM MemoryManagement IMPORT NoEMSPagesAvailable ;
FROM FIO IMPORT (* Type *) FileAttr, directory ;
FROM VirtMem IMPORT PDBFile, VirtMemFile, CloseVirtFile;
FROM HyperBase IMPORT HyperFile;
FROM GetParams IMPORT
  (* types *) GetParametersStatus, ParameterResult, ParameterData,
  (* procs *) LegalParameter, GetParameters, InitialParams;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteChar;
FROM GlobalDefs IMPORT StrAny, PDBExtension, TDBExtension,
     SystemVersion, SystemVersionDate;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CharField, CharFieldProc, LongIntField, CardField,
                 Switches, SwitchValue, MakeMenu, DestroyMenu, GetFieldInfo,
                 ClearMenuArea, ShowFixedText, ShowMenu, DoMenu;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage,
            ResAskUser;
FROM Windows IMPORT
  (* const *) RegularAttr,
  (* Var   *) TerminationProc;
FROM KeyTranslation IMPORT
  (* Procs *) WriteScreenField;
FROM KeyUtils IMPORT OpenInputKeysFile, ScriptFileExtension,
   ScriptBadFileNameRes;
FROM DBData IMPORT
    (* vars  *) TDBFileName, TDBTitle, NoTypes, NoTokensInDB,
                PDBFileName, PDBOpen;
FROM TDBInit IMPORT
    (* procs *) VerifyTDBFile, InitializeFromTDB;
FROM PDBInit IMPORT
  (* proc *) OpenExistingPDB, InitializeNewPDB;
FROM Utils IMPORT
  (* vars *) BeepMode,
  (* proc *) UpcaseStr,ParseFilename, MakeFilename, AllowWildCards,
     StandardizeFileName,Exist, TrimBlanks, DEALLOCATE;
FROM HyperDataModel IMPORT
    IDType, TDBIDModel, PDBIDModel;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;
FROM FileNameBase IMPORT BuildFileNameList, ChooseFromList;
FROM TACTListModule IMPORT TACTListType, TACTList, DiscardList;
FROM MemTACTList IMPORT InitializeFileNameList;
FROM HelpBase IMPORT PushHelpItem, PopHelpItem;
(*
(*RES OLD MNU 16




                   TACT Version %4_____ %5______________________

            Text: %1_________________________________________________
            PDB : %0________________________________________
            Number of Types: %2_________  Tokens: %3______________
            Startup  memory: %6_ K   EMS: %7___ K

               For help, push the F1 key. To exit, push F10.
            To choose action from Action Bar, push the SPACEBAR



 ____________________________________________________________________________
 Short Cuts:   Action Bar action: SPACEBAR
 F1: Help                      F5: Groups               F9: Output to Disk
 F2: Query                     F6: Modify Window       F10: QUIT
 F3: Complete WordList         F7: Cycle Displays
 F4: Selected WordList         F8: Synchronize Displays
*)
*)
(*RES OLD MNU 16










                    UseBase Version %2_____ %3______________________

            Text:  %1_________________________________________________
            .GIX:  %0_________________________________________________







               To choose option from Menu Bar, press the SPACEBAR
*)
CONST
    FirstTactDisplay = (*RES REM INS*) 16 ;
    CopyWYPos    = 15;
    CopyWXPos    = 12;  (* was 20 *)
    HIGHPDBFileName = 27;

TYPE
    DataBaseInfoRecord = RECORD
       FileName:    ARRAY[0..50] OF CHAR;
       GIXFileName:    ARRAY[0..50] OF CHAR;
       Create:      BOOLEAN;
    END;

    ScreenDataType = RECORD
        PDBFileName:    ARRAY[0..HIGHPDBFileName] OF CHAR;
        TextInfo:       ARRAY[0..50] OF CHAR;
        NumberTypes:    CARDINAL;
        NumberTokens:   LONGINT;
    END;

VAR
   OpenDBWind:   WindowInfo;
   ScreenData:   ScreenDataType;
   LastFileName: StrAny;

(*<JPI*)
PROCEDURE DoDBOpen(BaseWindow:   TWB.WinType;
               VAR DataBaseInfo: DataBaseInfoRecord): BOOLEAN; FORWARD;
(*JPI>*)

PROCEDURE CheckIfDirectory( Pat : ARRAY OF CHAR ) : BOOLEAN ;
   VAR
	DirEntryRec : FIO.DirEntry;
	OldIOcheck  : BOOLEAN ;
	rc	    : BOOLEAN ;
   BEGIN
	OldIOcheck := FIO.IOcheck ;
	FIO.IOcheck := FALSE ;
(*	IF (Pat[Str.Length(Pat)-1] = ':') (* OR (Pat[Str.Length(Pat)-1] = '\') *) THEN
	   rc := TRUE *)
	IF (Str.Pos(Pat,'*') < MAX(CARDINAL)) OR (Str.Pos(Pat,'?') < MAX(CARDINAL)) THEN
	   rc := FALSE	(* if have wild chars -- assume not a directory; ReadFirst may return TRUE! *)
	ELSIF FIO.ReadFirstEntry(Pat, FileAttr{directory},DirEntryRec) AND
	      ( directory IN DirEntryRec.attr) THEN
	   rc := TRUE
	ELSE
	   rc := FALSE
	END;
	FIO.IOcheck := OldIOcheck ;
	RETURN rc
   END CheckIfDirectory ;

PROCEDURE PrepareScreenDataPDBName;
VAR len:   CARDINAL;
    TP:    CARDINAL;
BEGIN
    len := Str.Length(PDBFileName);
    IF len <= 1+HIGHPDBFileName THEN
        Str.Copy(ScreenData.PDBFileName,PDBFileName)
    ELSE
        Str.Slice(ScreenData.PDBFileName,PDBFileName,
                   len+2-HIGHPDBFileName,HIGHPDBFileName+1);
        Str.Insert(ScreenData.PDBFileName,'..',0);
    END;

    TP := 0;
    SWriteString(ScreenData.TextInfo,TP,TDBTitle,0);
    SWriteString(ScreenData.TextInfo,TP,' (',0);
    SWriteString(ScreenData.TextInfo,TP,TDBFileName,0);
    SWriteChar(ScreenData.TextInfo,TP,')',0);
    ScreenData.NumberTypes := NoTypes;
    ScreenData.NumberTokens := NoTokensInDB;
END PrepareScreenDataPDBName;


PROCEDURE DoOpenMenu(BaseWindow: TWB.WinType;
                 VAR DBI:        DataBaseInfoRecord): BOOLEAN;

(*RES OLD MNU 33
                 Open TACT Database

   Database: %0_______________________________________

       Create New .GIX? Yes: %|1 No: %|2
*)
CONST
   OpenMenuID = (*RES REM INS*) 33 ;
VAR
   MenuData:     MenuID;
   w:            TWB.WinType;
   ch:           CHAR;
   FunctKey:     BOOLEAN;
   Rslt:         BOOLEAN;
   L:            CARDINAL;

PROCEDURE CheckDBFileName(): BOOLEAN;
VAR
     Drv:    ARRAY[0..4] OF CHAR;
     Pth:    ARRAY[0..100] OF CHAR;
     Name:   ARRAY[0..8] OF CHAR;
     Ext:    ARRAY[0..3] OF CHAR;
     Pat:    ARRAY[0..100] OF CHAR;
     Pat2:   ARRAY[0..100] OF CHAR;
     Dummy:  ARRAY[0..2] OF CHAR;
     Rslt:   ARRAY[0..15] OF CHAR;
     Empty:  BOOLEAN;
     DoMenu: BOOLEAN;
     i:      CARDINAL;
     tList:  TACTList;
     PatLen: CARDINAL;

BEGIN
   TrimBlanks( DBI.FileName, Pat);
   UpcaseStr(Pat,Pat);

   Empty := Pat[0] = 0C;
   DoMenu := FALSE;

   IF DBI.Create THEN
      IF Empty THEN
         (*RES OLD MSG 443
         You must give a new .GIX file name when creating a .GIX
         *)
         PutResError( (*RES REM INS*) 443 );
         RETURN FALSE;
      END;
      IF ( NOT StandardizeFileName(DBI.FileName, PDBExtension)) THEN
         (*RES OLD MSG 444
         Do not use "%0" as a file name for a .GIX.
         *)
         MsgString(DBI.FileName,0);
         PutResError( (*RES REM INS*) 444 );
         RETURN FALSE;
      END;
      RETURN TRUE;
   END;

   IF Empty THEN
      Drv[0] := 0C;
      Pth[0] := 0C;
      Ext[0] := 0C;
      DoMenu := TRUE;
   ELSE
      AllowWildCards := TRUE;
      IF CheckIfDirectory( Pat ) THEN  Str.Append( Pat, '\*' )  END ;
      PatLen := Str.Length(Pat)-1 ;
      IF (Pat[ PatLen ] = '\') OR (Pat[ PatLen ] = ':') THEN  Str.Append( Pat, '*' )  END ;
      IF NOT StandardizeFileName(Pat,0C) THEN
          (*RES OLD MSG 318
          "%0" cannot be used as a File Name or Pattern.
          *)
          AllowWildCards := FALSE;
          MsgString(DBI.FileName,0);
          PutResError( (*RES REM INS*) 318 );
          RETURN FALSE
      END;
      AllowWildCards := FALSE;
      IF NOT ParseFilename(Pat,Drv,Pth,Name,Ext) THEN
         ProgramErrorAndHalt('Unexpected error from ParseFilename');
      END;
      IF (Str.Pos(Name,'*') < MAX(CARDINAL)) OR (Str.Pos(Name,'?') < MAX(CARDINAL))
         OR (Str.Pos(Ext,'*') < MAX(CARDINAL)) OR (Str.Pos(Ext,'?') < MAX(CARDINAL))
         OR (Ext[0] = 0C)
      THEN  DoMenu := TRUE  END;
   END;
   Str.Copy(LastFileName, DBI.FileName);
   IF DoMenu THEN
      tList := InitializeFileNameList();
      IF Ext[0] = 0C THEN
         IF (Pat[0] = 0C) THEN Pat2 := '*'
         ELSE Str.Copy(Pat2,Pat) END;
         Str.Append(Pat2,TDBExtension);
         Empty := NOT BuildFileNameList(Pat2, tList);

         IF (Pat[0] = 0C) THEN Pat2 := '*' 
         ELSE Str.Copy(Pat2,Pat) END;
         Str.Append(Pat2,PDBExtension);
         IF NOT BuildFileNameList(Pat2, tList) THEN
            IF Empty THEN
               (*RES OLD MSG 321
               No .TDB or .GIX Files match "%0".
               *)
	       MsgString(Pat,0);
               PutResError( (*RES REM INS*) 321 );
               DiscardList(tList);
               RETURN FALSE;
            END;
         END;
      ELSIF NOT BuildFileNameList(Pat, tList) THEN
         (*RES OLD MSG 319
         Your file pattern "%0" selected nothing.
         *)
         MsgString(Pat,0);
         PutResError( (*RES REM INS*) 319 );
         DiscardList(tList);
         RETURN FALSE;
      END;
      IF NOT ChooseFromList(tList,Rslt) THEN
         DiscardList(tList);
         RETURN FALSE;
      END;
      DiscardList(tList);
      IF NOT ParseFilename(Rslt,Dummy,Dummy,Name,Ext) THEN
         ProgramErrorAndHalt('Unexpected error (2) from ParseFilename');
      END;
      MakeFilename(Drv,Pth,Name,Ext,DBI.FileName);
   END;
   RETURN TRUE;
END CheckDBFileName;

BEGIN
   StartMenu(DBI);
   WITH DBI DO
      CharField(FileName);
      Switches(Create);
         SwitchValue(TRUE);
         SwitchValue(FALSE);
   END;
   MakeMenu( OpenMenuID,MenuData );

   PushHelpItem(41);
   PushNewWindow(OpenDBWind,w, DummyInit);
   ShowFixedText(w, MenuData, 0,0);
   LOOP
      ShowMenu(w,MenuData,0,0,DBI);
      L := 0;
      DoMenu(w,MenuData,0,0,TermList,ExitList,DBI,L,ch,FunctKey);
      IF GetPanelControlKey(FunctKey, ch) = PanelCancel THEN
         DestroyMenu(MenuData);
         PopHelpItem;
         PopWindow;
         RETURN FALSE;
      END;
      IF NOT CheckDBFileName() THEN (* do nothing here *)
      ELSIF DoDBOpen(BaseWindow,DBI) THEN
         ShowMenu(w,MenuData,0,0,DBI);
         DestroyMenu(MenuData);
         PopHelpItem;
         PopWindow;
         RETURN TRUE;
      END;
   END;
END DoOpenMenu;

PROCEDURE DoDBOpen(BaseWindow:   TWB.WinType;
               VAR DataBaseInfo: DataBaseInfoRecord): BOOLEAN;
VAR
     Parm1:        ARRAY[0..50] OF CHAR;
     tFileName:    ARRAY[0..50] OF CHAR;
     tFileName2:   ARRAY[0..50] OF CHAR;
     temp:         BOOLEAN;

TYPE
   FileType = (NonExistant, NotTACT, TDBType, PDBType);

PROCEDURE GetFileType(FileName: ARRAY OF CHAR): FileType;
VAR  F:   FIO.File;
     R:   FileType;
     Str: IDType;
     s:   CARDINAL;
BEGIN
   IF NOT Exist(FileName) THEN RETURN NonExistant END;
   F := FIO.OpenRead(FileName);
   s := FIO.RdBin(F,Str,SIZE(IDType));
   IF Str = TDBIDModel THEN
      R := TDBType
   ELSE
      FIO.Seek(F,2); (* PDB ID starts in file position 2 *)
      s := FIO.RdBin(F,Str,SIZE(IDType));
      IF Str = PDBIDModel THEN R := PDBType
      ELSE R := NotTACT END;
   END;
   FIO.Close(F);
   RETURN R;
END GetFileType;

VAR
      DoCreate:      BOOLEAN;

PROCEDURE OpenExistingFile(): BOOLEAN;
   (*RES OLD MSG 215
   "%0" is not a TACT Database File.
   *)
CONST
   NotTACTDBRes = (*RES REM INS*) 215 ;
VAR
    ft:         FileType;
    tFile:      HyperFile;
    Yr, Mn, Dy: CARDINAL;
BEGIN
    ft := GetFileType(tFileName);
    CASE ft OF
      NonExistant, NotTACT:
         Str.Copy(tFileName2,DataBaseInfo.FileName);
         IF ( NOT StandardizeFileName(tFileName2, TDBExtension)) THEN
             ProgramErrorAndHalt('Standardization should work here!')
         END;
         CASE GetFileType(tFileName2) OF
           NonExistant:
              IF ft = NonExistant THEN
                 (*RES OLD MSG 293
                 File "%0" does not exist.
                 *)
                 MsgString(DataBaseInfo.FileName,0);
                 PutResError( (*RES REM INS*) 293 );
              ELSE
                 MsgString(DataBaseInfo.FileName,0);
                 PutResError( NotTACTDBRes );
              END;
              RETURN FALSE;
         | NotTACT:
             MsgString(DataBaseInfo.FileName,0);
             PutResError( NotTACTDBRes );
             RETURN FALSE;
         | TDBType:
             IF NOT VerifyTDBFile(tFileName2,TDBExtension,tFile,Yr,Mn,Dy) THEN
                 RETURN FALSE
             END;
             Str.Copy(TDBFileName,tFileName2);
             InitializeFromTDB(tFile);
         | PDBType:
             Str.Copy(PDBFileName,tFileName2);
             IF NOT OpenExistingPDB(PDBFileName) THEN RETURN FALSE END;
         END;
    | TDBType:
        IF NOT VerifyTDBFile(tFileName,TDBExtension,tFile,Yr,Mn,Dy) THEN
            RETURN FALSE
        END;
        Str.Copy(TDBFileName,tFileName);
        InitializeFromTDB(tFile);
    | PDBType:
        Str.Copy(PDBFileName,tFileName);
        IF NOT OpenExistingPDB(PDBFileName) THEN RETURN FALSE END
    END;
    RETURN TRUE;
END OpenExistingFile;

PROCEDURE CreateNewFile(): BOOLEAN;
BEGIN
   IF GetFileType(tFileName) = NonExistant THEN
      IF NOT InitializeNewPDB(tFileName) THEN RETURN FALSE END
   ELSE
      (*RES OLD MSG 294
      UseBase cannot create .GIX file "%0" because that file already exists.
      *)
      MsgString(tFileName,0);
      PutResError( (*RES REM INS*) 294 );
      RETURN FALSE;
   END;
   RETURN TRUE;
END CreateNewFile;

BEGIN
    IF DataBaseInfo.GIXFileName[0] <> 0C THEN
       Str.Copy(TDBFileName, DataBaseInfo.FileName );
       temp := StandardizeFileName( TDBFileName, TDBExtension);
       Str.Copy(tFileName, DataBaseInfo.GIXFileName);
    ELSE
       Str.Copy(tFileName,DataBaseInfo.FileName);
    END ;
    IF ( NOT StandardizeFileName(tFileName, PDBExtension)) THEN
       AllowWildCards := TRUE;
       Str.Copy(tFileName, DataBaseInfo.FileName);
       temp := StandardizeFileName(tFileName, PDBExtension);
       AllowWildCards := FALSE;
       IF temp THEN
          RETURN DoOpenMenu(BaseWindow, DataBaseInfo)
       ELSE
          (*RES OLD MSG 150
          Please use a different .TDB file name than "%0".
          *)
          MsgString(DataBaseInfo.FileName,0);
          PutResError( (*RES REM INS*) 150 );
          RETURN FALSE;
       END;
    END;

    IF DataBaseInfo.Create THEN
       IF NOT CreateNewFile() THEN RETURN FALSE END;
    ELSIF CheckIfDirectory( DataBaseInfo.FileName ) THEN
          RETURN DoOpenMenu(BaseWindow, DataBaseInfo)
    ELSE
       IF NOT OpenExistingFile() THEN RETURN FALSE END;
    END;

    RETURN TRUE;
END DoDBOpen;

PROCEDURE BuildFirstScreenMenu(VAR FirstScreen:    MenuID);
BEGIN
    StartMenu(ScreenData);
    WITH ScreenData DO
      CharField(PDBFileName);
      CharField(TextInfo);
(*      CardField(NumberTypes);
      NumberTypes := 0;
      LongIntField(NumberTokens);
      NumberTokens := 0;
*)
    END;
    MakeMenu( FirstTactDisplay, FirstScreen);
END BuildFirstScreenMenu;

PROCEDURE InitializeDBs(BaseWindow:  TWB.WinType);

(*RES OLD MSG 292
UseBase does not take parameter "%0".
*)

CONST
   NotAcceptableRes = (*RES REM INS*) 292 ;

(*RES OLD MSG 157
Please give no more than one Database Name.
*)

   OneDatabaseRes = (*RES REM INS*) 157 ;

VAR DataBaseInfo:   DataBaseInfoRecord;
    tStr:           StrAny;
    FirstScreen:    MenuID;
    plst,temp:      ParameterResult;
    MemFree:	    ARRAY[0..3] OF CHAR;
    EMSFree:	    ARRAY[0..6] OF CHAR;
    AmountOfEMS:    CARDINAL;
    OK:		    BOOLEAN;
    i:		    CARDINAL;
    VerLen,DatLen,MemLen,EMSLen,
    MemX,MemY,EMSX,EMSY,
    VerX,DatX,
    VerY,DatY:      CARDINAL;
BEGIN
    InitialParams;
    LegalParameter('c',FALSE);
    LegalParameter('q',FALSE);
    LegalParameter('s',TRUE);
    LegalParameter('g',TRUE);

    IF GetParameters(plst,tStr) <> GPSOk THEN
        MsgString(tStr,0);
        PutResError( NotAcceptableRes );
        TerminationProc;
    END;

    DataBaseInfo.FileName[0] := 0C;
    DataBaseInfo.GIXFileName[0] := 0C;
    DataBaseInfo.Create := FALSE;
    TDBFileName[0] := 0C ;
    PDBFileName[0] := 0C;
    WHILE plst <> NIL DO
       WITH plst^ DO
          CASE Code OF
            ' ':
               IF DataBaseInfo.FileName[0] <> 0C THEN
                  PutResError( OneDatabaseRes );
                  TerminationProc;
               END;
               Str.Copy(DataBaseInfo.FileName, Strg);
          | 'C':
               DataBaseInfo.Create := TRUE;
          | 'G':
               DataBaseInfo.Create := TRUE;
               Str.Copy(DataBaseInfo.GIXFileName, Strg);
          | 'Q':
               (* Utils. *) BeepMode := TRUE;  (* m.s. - now default is turn off beep *)
	  | 'S':
		Str.Copy( tStr, Strg);
		IF StandardizeFileName(tStr,ScriptFileExtension) THEN
		   OpenInputKeysFile(tStr);
                ELSE
		   MsgString(tStr,0);
		   PutResError( ScriptBadFileNameRes );
		END;
          ELSE
             ProgramErrorAndHalt('Unexpected ParameterData Code found');
          END;
       END;
       temp := plst^.Next;
       DEALLOCATE(plst,plst^.Size);
       plst := temp;
    END;

    Str.Copy(LastFileName, DataBaseInfo.FileName);
    BuildFirstScreenMenu(FirstScreen);


    TWB.GotoXY(0,1) ;
(*    TWB.WrStr(' Â      Â   ÚÄÄÄÄÄÄÄ¿ ÚÄÄÄÄÄÄÄ¿  ÚÄÄÄÄÄÄÄÄ¿   ÚÄÄÄÄÄÄÄ¿  ÚÄÄÄÄÄÄÄ¿ ÚÄÄÄÄÄÄÄ¿ ');
    TWB.WrLn ;
    TWB.WrStr(' ³      ³   ³         ³          ³        ³   ³       ³  ³         ³        ');
    TWB.WrLn ;
    TWB.WrStr(' ³      ³   ³         ³          ³        ³   ³       ³  ³         ³        ');
    TWB.WrLn ;
    TWB.WrStr(' ³      ³   ÀÄÄÄÄÄÄ¿  ÃÄÄÄÄÄÄÄ´  ³ÄÄÄÄÄÄÄ<    ÃÄÄÄÄÄÄÄ´  ÀÄÄÄÄÄÄ¿  ÃÄÄÄÄÄÄÄ´ ');
    TWB.WrLn ;
    TWB.WrStr(' ³      ³          ³  ³          ³        ³   ³       ³         ³  ³        ');
    TWB.WrLn ;
    TWB.WrStr(' ³      ³          ³  ³          ³        ³   ³       ³         ³  ³        ');
    TWB.WrLn ;
    TWB.WrStr(' ÀÄÄÄÄÄÄÙ   ÀÄÄÄÄÄÄÙ  ÀÄÄÄÄÄÄÄÙ  ÀÄÄÄÄÄÄÄÄÙ   Á       Á  ÀÄÄÄÄÄÄÙ  ÀÄÄÄÄÄÄÄÙ ');
    TWB.WrLn ;
*)
    TWB.WrStr(' Ò      Â   ÖÄÄÄÄÄÄ¿  ÖÄÄÄÄÄÄÄ¿  ÖÄÄÄÄÄÄÄÄ¿   ÖÄÄÄÄÄÄÄ¿  ÖÄÄÄÄÄÄ¿  ÖÄÄÄÄÄÄÄ¿ ');
    TWB.WrLn ;
    TWB.WrStr(' º      ³   º         º          º        ³   º       ³  º         º        ');
    TWB.WrLn ;
    TWB.WrStr(' º      ³   º         º          º        ³   º       ³  º         º        ');
    TWB.WrLn ;
    TWB.WrStr(' º      ³   ÓÄÄÄÄÄÄ¿  ÇÄÄÄÄÄÄÄ   ÇÄÄÄÄÄÄÄ<    ÇÄÄÄÄÄÄÄ´  ÓÄÄÄÄÄÄ¿  ÇÄÄÄÄÄÄÄ ');
    TWB.WrLn ;
    TWB.WrStr(' º      ³          ³  º          º        ³   º       ³         ³  º        ');
    TWB.WrLn ;
    TWB.WrStr(' º      ³          ³  º          º        ³   º       ³         ³  º        ');
    TWB.WrLn ;
    TWB.WrStr(' ÓÄÄÄÄÄÄÙ   ÓÄÄÄÄÄÄÙ  ÓÄÄÄÄÄÄÄÙ  ÓÄÄÄÄÄÄÄÄÙ   Ð       Á  ÓÄÄÄÄÄÄÙ  ÓÄÄÄÄÄÄÄÙ ');
    TWB.WrLn ;



  GetFieldInfo(FirstScreen,2,VerX,VerY,VerLen);
    GetFieldInfo(FirstScreen,3,DatX,DatY,DatLen);
    ShowFixedText(BaseWindow, FirstScreen, 0,0);
    WriteScreenField( BaseWindow, VerLen, VerX, VerY,
                           SystemVersion, RegularAttr, TRUE );
    WriteScreenField( BaseWindow, DatLen, DatX, DatY,
                           SystemVersionDate, RegularAttr, TRUE );
(*    GetFieldInfo(FirstScreen,6,MemX,MemY,MemLen);
    Str.CardToStr(LONGCARD(HeapTotalAvail(MainHeap) DIV 64),MemFree,10,OK) ;	(* in K's *)
    WriteScreenField( BaseWindow, MemLen,MemX,MemY, MemFree, RegularAttr,TRUE );
    i := 0;
    EMSFree := 0C;
    (* compensate the amount of EMS by info two pages *)
    IF NoEMSPagesAvailable > 0 THEN  AmountOfEMS := NoEMSPagesAvailable + 2
    ELSE AmountOfEMS := 0  END ;
    SWriteCard(EMSFree, i, AmountOfEMS * 16, 5);
    GetFieldInfo(FirstScreen,7,EMSX,EMSY,EMSLen);
    WriteScreenField( BaseWindow, EMSLen,EMSX,EMSY, EMSFree, RegularAttr,TRUE );
*)
    TWB.Use(BaseWindow);
    TWB.GotoXY(0, CopyWYPos + 2);
    TWB.ClrEol;
    TWB.WrStr('              Copyright (c) 1995 TACT Group, University of Toronto');
    TWB.WrLn ;

    IF DataBaseInfo.FileName[0] = 0C THEN
       IF NOT DoOpenMenu(BaseWindow, DataBaseInfo) THEN TerminationProc END;
    ELSIF NOT DoDBOpen(BaseWindow, DataBaseInfo) THEN
       IF NOT DoOpenMenu(BaseWindow, DataBaseInfo) THEN TerminationProc END;
    END;

    PrepareScreenDataPDBName;
    ShowMenu(BaseWindow, FirstScreen, 0,0, ScreenData);

    DestroyMenu(FirstScreen);

END InitializeDBs;

PROCEDURE OpenNewDB(BaseWindow: WinType): BOOLEAN;
VAR
   DataBaseInfo:    DataBaseInfoRecord;
   FirstScreen:     MenuID;
   HoldPDBOpen:     BOOLEAN;
   HoldPDBFile:     VirtMemFile;
   HoldPDBFileName: StrAny;
   dummy:           BOOLEAN;
BEGIN
   Str.Copy(DataBaseInfo.FileName, LastFileName);
   DataBaseInfo.Create := FALSE;
   HoldPDBOpen := PDBOpen;
   PDBOpen := FALSE;
   Str.Copy(HoldPDBFileName, PDBFileName);
   PDBFileName := '-----';
   HoldPDBFile := PDBFile;

   IF DoOpenMenu(BaseWindow, DataBaseInfo) THEN
      IF HoldPDBOpen THEN
         CloseVirtFile(HoldPDBFile);
      END;

      BuildFirstScreenMenu(FirstScreen);
      PrepareScreenDataPDBName;
      ShowMenu(BaseWindow, FirstScreen, 0,0, ScreenData);
      DestroyMenu(FirstScreen);
      RETURN TRUE;
   END;

   PDBOpen := HoldPDBOpen;
   Str.Copy(PDBFileName, HoldPDBFileName);
   PDBFile := HoldPDBFile;

   RETURN FALSE;
END OpenNewDB;

BEGIN
   TermList[0] := ASCII.rs; TermList[1] := ASCII.esc; (*TermList[2] := ASCII.ht; *)
   TermList[2] := 0C ;
   ExitList[0] := PCKey.F2; ExitList[1] := PCKey.F4; ExitList[2] := PCKey.F6;
   ExitList[3] := PCKey.CtrlF9; ExitList[4] := PCKey.ShiftF9;
   ExitList[5] := PCKey.F9; ExitList[6] := PCKey.F7;
   ExitList[7] := PCKey.CtrlF3; ExitList[8] := PCKey.F4;
   ExitList[9] := PCKey.CtrlF2; ExitList[10] := 0C ;
   LastFileName:= '';

   WITH OpenDBWind DO
       XPos := 9;
       YPos := 4;
       YSize := 5;
       XSize := 62;
       MxYSize := 14;
       Type := Dialog;
       AllowMove := TRUE;
       AllowResize := FALSE;
   END;
   BeepMode :=FALSE ; (* m.s. - default in now quiet mode *)
END TACTInit.
