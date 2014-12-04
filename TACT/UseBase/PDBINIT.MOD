IMPLEMENTATION MODULE PDBInit;

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

IMPORT ASCII, Str, FIO, Lib;
FROM TWB IMPORT WinType;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM SYSTEM IMPORT ADR;
FROM GlobalDefs IMPORT StrAny, TDBExtension;
FROM Utils IMPORT StandardizeFileName, RemoveExtension;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;
FROM HyperDataModel IMPORT
  (* const *) HyperLength, ThisPDBVersion,
  (* Types *) HyperData,
  (* Vars  *) PDBIDModel;
FROM VirtMem IMPORT
  (* types *) VirtAddr, VirtMemFile,
  (* vars  *) NILVirt, PDBFile,
  (* procs *) CopyFromVirtMem, CopyToVirtMem, VMAccess, VMModify, VMMarkChanged,
              VMRelease, GetSpace, FreeSpace, RealToPool, VirtToPool,
              EqualVirts, FreePool, WriteAllVirts, OpenVirtFile;
FROM HyperBase IMPORT  (* access to TDB *)
  (* TYPE *) HyperFile,
  (* PROC *) CloseHyperFile;
FROM MemoryManagement IMPORT RealStoragePntr;
FROM KeyTranslation IMPORT
   WriteScreenField;
FROM Windows IMPORT
  (* Consts *) RegularAttr, BoldAttr, SpecialAttr;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CharFieldProc,
                 MakeMenu, DestroyMenu, GetFieldInfo,
                 ClearMenuArea, ShowFixedText, ShowMenu, DoMenu;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage,
            ResAskUser;
FROM TDBInit IMPORT
    (* procs *) VerifyTDBFile, InitializeFromTDB;
FROM FileNameBase IMPORT
          HandleFileNameField;
FROM HelpBase IMPORT PushHelpItem, PopHelpItem;
FROM MemTACTList IMPORT InitializeCatList;
FROM TACTDataServices IMPORT VirtToTACTList, TACTListToVirt;

FROM DBData IMPORT
     PDBFileName, PDBOpen, MainCatList, SavePoolInfo, InitPool,
     TDBFile, TDBFileName, TDBYear, TDBMonth, TDBDay, TDBDataInitialized;

(*<Dbg
FROM Trace IMPORT
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard,
              TWriteAddr, TWriteStrHex, CloseTFile;
Dbg>*)

(*RES OLD MNU 15
%1______________________________________________________________________
%2______________________________________________________________________
%3______________________________________________________________________

Name of TACT Database: %0_______________________________________________

                         Press F10 to exit from UseBase.
*)

  CONST
      TextDBNameMenu = (*RES REM INS*) 15;

(*RES OLD MSG 147
  Please give the name of a different .TDB file below.
*)
      ToTryMsg = (*RES REM INS*) 147;

(*RES OLD MSG 148
UseBase cannot use "%0" as a .TDB or .COR file.
*)
      CannotUseMsg = (*RES REM INS*) 148;

  TYPE
    PDBHeader = RECORD
       TYear      : CARDINAL ;
       TMonth     : CARDINAL ;
       TDay       : CARDINAL ;
       CListLoc   : VirtAddr ;
       PoolData   : VirtAddr ;
       OtherItems : VirtAddr ;
       TFileName  : ARRAY [0..99] OF CHAR;
    END;

PROCEDURE FileNameVerify(Data: ADDRESS;
                     VAR ReDisplay: BOOLEAN;
                     VAR ReEdit:    BOOLEAN);
TYPE
  RealDataPntr = POINTER TO StrAny;
VAR
  Dtx: RealDataPntr;
BEGIN
  Dtx := RealDataPntr(Data);
  HandleFileNameField(Dtx^,TDBExtension,ReDisplay,ReEdit);
END FileNameVerify;

PROCEDURE ShowTDBScreen( MsgLine1:    ARRAY OF CHAR;
                         MsgLine2:    ARRAY OF CHAR;
                         MsgLine3:    ARRAY OF CHAR;
                     VAR TDBFileName: ARRAY OF CHAR): BOOLEAN;
VAR
      FieldNo:                   CARDINAL;
      TC:                        CHAR;
      FunctKey:                  BOOLEAN;
      WindowRec :                WinType;
      MsgL1X, MsgL1Y, MsgL1L:    CARDINAL;
      MsgL2X, MsgL2Y, MsgL2L:    CARDINAL;
      MsgL3X, MsgL3Y, MsgL3L:    CARDINAL;
      TDBScrMenu:                MenuID;
      NewTDBWindow:              WindowInfo;
      EscTabRs:                  ARRAY[0..2] OF CHAR;

   BEGIN
      EscTabRs[0] := ASCII.rs; EscTabRs[1] := ASCII.ht; EscTabRs[2] := ASCII.esc;
      PushHelpItem(42);
      WITH NewTDBWindow DO;
        XPos := 4;
        YPos := 4;
        XSize := 72;
        YSize := 7;
        MxYSize := 7;
        Type := Dialog;
        AllowMove := FALSE;
        AllowResize := FALSE;
      END;
      PushNewWindow(NewTDBWindow,WindowRec,DummyInit);
      StartMenu(TDBFileName);
          CharFieldProc(TDBFileName,FileNameVerify);
      MakeMenu( TextDBNameMenu , TDBScrMenu);
      GetFieldInfo(TDBScrMenu,1,MsgL1X,MsgL1Y,MsgL1L);
      GetFieldInfo(TDBScrMenu,2,MsgL2X,MsgL2Y,MsgL2L);
      GetFieldInfo(TDBScrMenu,3,MsgL3X,MsgL3Y,MsgL3L);
      ClearMenuArea(WindowRec, 0,0, TDBScrMenu);
      ShowFixedText(WindowRec,TDBScrMenu,0,0);

      WriteScreenField( WindowRec, MsgL1L, MsgL1X, MsgL1Y, MsgLine1,
                              RegularAttr, FALSE );
      WriteScreenField( WindowRec, MsgL2L, MsgL2X, MsgL2Y, MsgLine2,
                              RegularAttr, FALSE );
      WriteScreenField( WindowRec, MsgL3L, MsgL3X, MsgL3Y, MsgLine3,
                              RegularAttr, FALSE );
      ShowMenu(WindowRec, TDBScrMenu, 0,0,TDBFileName);

      FieldNo := 0;
      DoMenu(WindowRec, TDBScrMenu, 0,0,EscTabRs,0C,TDBFileName,FieldNo,
                   TC,FunctKey);
      PopWindow;
      PopHelpItem;
      DestroyMenu(TDBScrMenu);
      RETURN GetPanelControlKey(FunctKey, TC) <> PanelCancel;
   END ShowTDBScreen;

PROCEDURE OpenBase(FileName: ARRAY OF CHAR): BOOLEAN;
VAR ErrMsg:  ARRAY[0..100] OF CHAR;
BEGIN
  IF NOT OpenVirtFile(FileName, PDBFile, ErrMsg, (*tmpfile=*) FALSE) THEN
     (*RES OLD MSG 151
     UseBase cannot open .GIX file %0: %1.
     *)
     MsgString(FileName,0);
     MsgString(ErrMsg,1);
     PutResError( (*RES REM INS*) 151 );
     RETURN FALSE
  END;
  Str.Copy(PDBFileName,FileName);
  RETURN TRUE
END OpenBase;

PROCEDURE OpenExistingPDB(VAR FileName: ARRAY OF CHAR): BOOLEAN;
  VAR
    MsgLine1,
    MsgLine2,
    MsgLine3:     StrAny;
    PDBPntr:      RealStoragePntr;
    loop:         BOOLEAN;
    NameChanged:  BOOLEAN;
    dummy:        BOOLEAN;
    ErrMsg:       StrAny;
    Yr, Mn, Dy:   CARDINAL;
    HeaderLoc:    VirtAddr;
    HeaderPtr:    POINTER TO PDBHeader;
    tFile:        HyperFile; (* for TDB *)
BEGIN
  IF NOT OpenBase(FileName) THEN RETURN FALSE END;

  HeaderLoc.PageNo := 0; HeaderLoc.Offset := 2;
  HeaderPtr := VMAccess(HeaderLoc);

  SavePoolInfo(HeaderPtr^.PoolData);

  loop := TRUE;
  NameChanged := FALSE;
  WHILE loop DO
    IF NOT VerifyTDBFile(HeaderPtr^.TFileName,TDBExtension,
       tFile, Yr, Mn, Dy) THEN
       MsgString( HeaderPtr^.TFileName, 0);
       GetResMessage( CannotUseMsg , MsgLine1);
       GetResMessage(ToTryMsg, MsgLine2);
       MsgLine3[0] := 0C;
       IF NOT ShowTDBScreen( MsgLine1, MsgLine2, MsgLine3, HeaderPtr^.TFileName) THEN
          RETURN FALSE;
       END;
       NameChanged := TRUE;
    ELSIF (Yr <> HeaderPtr^.TYear) OR
    (Mn <> HeaderPtr^.TMonth) OR
    (Dy <> HeaderPtr^.TDay) THEN
       (*RES OLD MSG 154
       Your .TDB file ("%0") does not match your .GIX file.
       *)
       MsgString( HeaderPtr^.TFileName, 0);
       GetResMessage( (*RES REM INS*) 154, MsgLine1);
       GetResMessage(ToTryMsg, MsgLine2);
       MsgLine3[0] := 0C;
       dummy := CloseHyperFile(tFile,ErrMsg);
       IF NOT ShowTDBScreen( MsgLine1, MsgLine2, MsgLine3, HeaderPtr^.TFileName) THEN
          RETURN FALSE;
       END;
       NameChanged := TRUE;
    ELSE
       Str.Copy(TDBFileName,HeaderPtr^.TFileName);
       InitializeFromTDB(tFile);
       loop := FALSE
    END;
  END;
  IF NameChanged THEN
    VMMarkChanged(HeaderLoc);
    WriteAllVirts();
  END;
  VirtToTACTList(HeaderPtr^.CListLoc, MainCatList);
  VMRelease(HeaderLoc);
  PDBOpen := TRUE;
  RETURN TRUE;
END OpenExistingPDB;

PROCEDURE InitializeNewPDB(VAR FileName: ARRAY OF CHAR): BOOLEAN;
  VAR
    MsgLine1,
    MsgLine2,
    MsgLine3:     StrAny;
    TFileName:    StrAny;
    HeaderLoc:    VirtAddr;
    HeaderPtr:    POINTER TO PDBHeader;
    loop:         BOOLEAN;
    tFile:        HyperFile;
    Yr, Mn, Dy:   CARDINAL;
    DoTDBOpen:    BOOLEAN;

PROCEDURE FinishInit() : BOOLEAN ;
BEGIN
   IF NOT OpenBase(FileName) THEN  RETURN FALSE  END ;
(*<Dbg
   TWriteString('InitializeNewPDB: after OpenBase');
   TWriteLn;
Dbg>*)
   HeaderPtr := GetSpace(SIZE(PDBHeader), 0, HeaderLoc);
   IF (HeaderLoc.PageNo <> 0) OR (HeaderLoc.Offset <> 2) THEN
      ProgramErrorAndHalt('Unexpected problem with HeaderLoc')
   END;

   WITH HeaderPtr^ DO
      InitPool(PoolData);
      SavePoolInfo(PoolData);
   END;

   Str.Copy(HeaderPtr^.TFileName,TFileName);
   MainCatList := InitializeCatList();
   WITH HeaderPtr^ DO
      TYear := TDBYear;
      TMonth := TDBMonth;
      TDay := TDBDay;
      TACTListToVirt(MainCatList, 0, CListLoc);
      OtherItems := NILVirt;
   END;
   VMRelease(HeaderLoc);

(*
   CP := MakeCategoData('', HP, CHeader);
   HeaderPtr^.CHeaderIdx := CHeader.Idx;
   ReleaseBaseHyper(PDBFile, HP);
   WriteAll(PDBFile);
*)
   WriteAllVirts();
   loop := FALSE;
   PDBOpen := TRUE;
   RETURN TRUE;
END FinishInit;

BEGIN

(* First, create a pattern TDB Filename from the PDB Filename as a guess *)

(*<Dbg
  TWriteString('InitializeNewPDB begins:');
  TWriteString(FileName);
  TWriteLn;
Dbg>*)
  IF NOT TDBDataInitialized AND (TDBFileName[0] = 0C) THEN (* m.s. added TDBFileName check *)
     RemoveExtension(FileName,TFileName);
     loop := StandardizeFileName(TFileName,TDBExtension);
  ELSE
     Str.Copy(TFileName, TDBFileName);
     loop := TRUE;
  END;

  (*RES OLD MSG 155
  .GIX file "%0" does not exist.
  *)
  MsgString( FileName, 0);
  GetResMessage( (*RES REM INS*) 155, MsgLine1);

  (*RES OLD MSG 156
  Please name a .TDB file now in order to create the .GIX file:
  *)

  GetResMessage( (*RES REM INS*) 156 , MsgLine2);
  MsgLine3[0] := 0C;

  IF (TDBFileName[0] = 0C) THEN
    IF NOT ShowTDBScreen( MsgLine1, MsgLine2, MsgLine3, TFileName) THEN
       RETURN FALSE;
    END;
  END ;
  DoTDBOpen := (NOT TDBDataInitialized) OR
               (0 <> Str.Compare(TFileName, TDBFileName));
  WHILE loop DO
(*<Dbg
    TWriteString('InitializeNewPDB: ready to call VerifyTDBFile:');
    TWriteString(TFileName);
    TWriteLn;
Dbg>*)
    IF NOT DoTDBOpen THEN RETURN FinishInit();
    ELSIF (NOT VerifyTDBFile(TFileName,TDBExtension,tFile,Yr,Mn,Dy)) THEN
        MsgString( TFileName, 0);
        GetResMessage( CannotUseMsg , MsgLine1);
        GetResMessage(ToTryMsg, MsgLine2);
        MsgLine3[0] := 0C;
        IF NOT ShowTDBScreen( MsgLine1, MsgLine2, MsgLine3, TFileName) THEN
           RETURN FALSE;
        END;
    ELSE
(*<Dbg
        TWriteString('InitializeNewPDB: ready to call OpenBase:');
        TWriteString(FileName);
        TWriteLn;
Dbg>*)
        Str.Copy(TDBFileName,TFileName);
        InitializeFromTDB(tFile);

        RETURN FinishInit();
    END;
  END;
END InitializeNewPDB;

END PDBInit.
