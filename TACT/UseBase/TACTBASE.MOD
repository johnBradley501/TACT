IMPLEMENTATION MODULE TACTBase;

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
(*
Ver 1.11
 - Sept. 5, 1989  L.Presutti
   Added a check for DoWordListSetup (ie. F4) such that a prompt is produced
   before deleting a previous selected vocabulary (ie. F3) list.
   Changed menu item "List ... F3" to "Selected List ... F3".
*)
(* m.s.  Feb 4, 1993 moved everything around... *)

FROM SYSTEM IMPORT ADR, BYTE;
IMPORT Str, Lib, ASCII, PCKey;
FROM VirtMem IMPORT VirtAddr, ChangePoolNo, FreePool, NILVirt, VMModify, VMRelease ;
FROM TACTDataServices IMPORT InsertDataItemContentsInList;
FROM WordBase IMPORT
  (* Procs *) SortToIntWord, IntToSortWord;
FROM TWB IMPORT
  (* Type  *) WinType,
  (* Const *) RightLowerTitle,
  (* Procs *) WrStr, Use, GotoXY, WrLn, SetTitle, Used ;
FROM TACTInit IMPORT TermList, ExitList,
     OpenNewDB;

FROM MemoryManagement IMPORT SetShowBusyWindow ;
FROM KeyStandards IMPORT
  (* types *) ListControlKeys,
  (* procs *) GetListControlKey;
FROM Windows IMPORT
  (* Vars *)  TerminationProc, GetRidOfWindow, BoldAttr, RegularAttr,
  (* proc *)  ChangeColorOnScreen ;
FROM ErrorBase IMPORT
   (* Procs *) ProgramErrorAndHalt;
(* (* temp only*) PutMessage; *)
FROM StackWindows IMPORT WindowType, WindowInfo, ZoomCurrentWindow,
   LayoutWindowsAsPanels, PushNewWindow, DummyInit, PopWindow;
FROM Utils IMPORT Beep;
FROM ListData IMPORT
  (* types *) DataItemPntr,ItemType;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, GetFirstItem,
           GetNextItem, DiscardList, GetListType, GetItemData,
           ReleaseItemHold;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, CopyList;
FROM TypeListModule IMPORT MakeTACTTypeList;
FROM MainLists IMPORT
  (* const *) PoolNoForSelectLists, PoolNoForOldSelect, PoolNoForListFromRule,
          PoolNoForTempList,
  (* type *) PosListStatusType, DiscardMainListType,
  (* vars *) ListFromRule, ListFromRulePos, SelectedList, ListByPosition,
          PosListStatus, SelectedListPos, PositionListPos,
          SelectedListEmpty, ListByType, TypeListPos, ListByTypeMade,
          DiscardMainLists;
FROM SelectWindow IMPORT
  (* proc *) DoSelectWindow;
FROM GlobalDefs IMPORT StrAny;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;
FROM DBData IMPORT BeginType, TDBFileName, PDBOpen, PDBFileName, MainCatList,
   NoTypes, NoTokensInDB, TDBTitle;
FROM HyperBase IMPORT HRecPntr;
FROM KeyBase IMPORT GetKeyStroke;
FROM RuleWindow IMPORT
  (* vars *)  RuleWindowData,
  (* proc *)  InitRuleWindMenu, DoRuleWindMenu;
FROM Categories IMPORT
  (* Const *) NoPDBRes,
  (* types *) CatWindowDataType,
  (* vars  *) CatWindowData,
  (* Procs *) DoCatNameDelete, DoCatNameDisplay, DoCatListDisplay,
          DoCatNameCreate, DoCatNameModify ;
FROM DisplayDialog IMPORT
  (* type *) DisplayType, DisplayDataType,
  (* vars *) PrintProc, CurrentDisplay, DisplayData,
  (* proc *) CreateNewWindow, ChangeCurrentWindow,
          CloseCurrentWindow, ModifyCurrentWindow,
          SendInstructionToCurrent, InitializeAllActiveDisplays,
          MoveToNextDisplayWindow, InitializeData,
          TerminateAllActiveDisplays;
FROM PrintModule IMPORT PrintMaster, PrintProcType, PrintActionType,
          InitialPrintModule;
FROM ScrollMessages IMPORT
   (* const*) SizeOfLineInfoHeader,
   (* type *) ScrollInstruction, ReturnInstruction, LineInformation,
           LineInfoPntr, ScrollInstructionPacket, ScrollKey;
FROM PositionManagement IMPORT
  (* types *) PositionItem,
  (* procs *) FirstDisplayItem, DiscardDisplayItem, InitialDisplayItem;
FROM ResActionBar IMPORT
  (* type *) BarID,
  (* Vars *) ABWindow,
  (* proc *) BuildActionBar, ShowActionBar, DoActionBar;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, PopHelpItem, ShowHelpItem;
FROM ResMessages IMPORT
  (* procs *) PutResWarning, PutResError, ResAskUser, GetResMessage ;
FROM ResCollection IMPORT ResCollectionType, ReleaseCollection ;
FROM ResDataArray IMPORT
  (* procs *) GetDataArray, GetNextDataArrayStringItem;
FROM Storage IMPORT
  (* Vars  *) MainHeap,
  (* Procs *) HeapTotalAvail ;
FROM RuleIO IMPORT ImportRule, ExportRule, RulesToCats;
FROM FileNameBase IMPORT HandleFileNameField;
FROM RefValBase IMPORT
  (* Vars  *) LastRefPat, LastEncodedRefPat, LastRefPatLen,
  (* procs *) EncodeRefPat;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr,
   (* procs *) GetNameFromID, LookupRefName;
FROM KeyUtils IMPORT OpenInputScriptFile, OpenOutputScriptFile;
FROM RuleListModule IMPORT RuleFileInfo ;
FROM ProfDisplay IMPORT DoTextBaseProfile ;
CONST
    ActionBarHelpItem = 1;
    MainSelectHelpItem = 11;
    CategorySelectHelpItem = 20;
    CreditHelpItem = 67 ; (* m.s. - new item *)
CONST
   (*RES OLD DTA 8
   "  _File    "
   "   _Select   "
   "   _Displays   "
   "   _Group   "
   "   _Help (F1) "
   *)
   ActBarRes = (*RES REM INS*) 8;

TYPE
(*   ActBarActions = (ABNone,ABHelp,ABExit,ABSelect,ABCurrent,ABNew,ABCategory,ABFile); *)
   ActBarActions = (ABNone,ABFile,ABSelect,ABDisplays,ABGroup,ABHelp);

CONST
   (*RES OLD DTA 9
   "_Complete word-list ... F3"
   "_Selected word-list ... F4"
   "_Groups ............... F5"
   "_Query ................ F2"
   *)
   SelectionListRes = (*RES REM INS*) 9;

TYPE
   SelectActions = (SLNone,SLWordList, SLList, SLGroups, SLQuery);

CONST

(*RES OLD DTA 10
"_KWIC ........... Shift-F3"
"_Variable context Shift-F4"
"_Text ........... Shift-F5"
"_Distribution ... Shift-F6"
"_Collocates ..... Shift-F7"
"_Modify .........       F6"
"c_Ycle displays .       F7"
"_Window display . Shift-F8"
"_Synchronize ....       F8"
"_Zoom ...........  Ctrl-F8"
"c_Lose display ..  Ctrl-F9"
*)
   CurrentListRes = (*RES REM INS*) 10;

TYPE
   CurrentActions = (CRNone, CRKWIC, CRVariable, CRText, CRDist,
              CRCollocate, CRModify, CRCycle, CRWindow, CRSynch,
              CRZoom, CRClose );

CONST
(*RES OLD DTA 12
"_Make ......... Ctrl-F3"
"_Delete ....... Ctrl-F4"
"_Replace ...... Ctrl-F5"
"_Group list ... Ctrl-F6"
"_Selected group Ctrl-F7"
*)
   CatListRes = (*RES REM INS*) 12;

TYPE
   CatActions = (CTNone, CTMake, CTDelete, CTReplace, CTList, CTGroup);

CONST
(*RES OLD DTA 13
"_Open database ..   Alt-F4"
"_Textbase profile Shift-F1"
"_Import ......... Shift-F2"
"_Multiple import.   Alt-F2"
"_Export .........  Ctrl-F2"
"_Disk ...........       F9"
"_Print .......... Shift-F9"
"_Record ........ Shift-F10"
"play _Back ...... Ctrl-F10"
"e_Xit ...........      F10"
*)
   FileRes = (*RES REM INS*) 13;

TYPE
   FileActions = (FLNone, FLOpen, FLProfile, FLImport, FLMultImport,
            FLExport, FLDisk, FLPrint, FLRecord, FLPlay, FLExit );

CONST
(*RES OLD DTA 31
"_Help...........     F1"
"help _Template.. Alt-F1"
"_Credits........Ctrl-F1"
*)
HelpRes = (*RES REM INS*) 31 ;

TYPE
  HelpActions = (HLPNone, HLPHelp, HLPTemplate, HLPCredit ) ;

VAR
   EditSelectWind:      WindowInfo;
   PopUpRes :           ARRAY[ABFile..ABHelp] OF CARDINAL;
   ABar :               BarID;
   IgnoreRuleErrors:    BOOLEAN;

PROCEDURE ShowMemFree(BaseWindow : WinType) ;
   VAR
     MemFree         : CARDINAL ;
     MemFreeStr      : ARRAY [0..6] OF CHAR ;
     i               : CARDINAL;
   BEGIN
(* in Version 1 of JPI HeapTotalAvail returned size in paragraphs, now
   we are told (but do not believe it) it's in bytes!   j.b. *)
     MemFree := HeapTotalAvail( MainHeap ) DIV 64 ;  (* in K's *)
(*      MemFree := HeapTotalAvail( MainHeap ) DIV 1024 ;(* in K's *) *)
     i := 0;
     MemFreeStr := 0C;
     SWriteCard(MemFreeStr,i,MemFree,4);
     MemFreeStr[4] := ' ' ;
     MemFreeStr[5] := 'K' ;
     MemFreeStr[6] := 0C ;
     (* TWB. *) Use( BaseWindow ) ;
     (* TWB. *) GotoXY( 71, 1 ) ;
     (* TWB. *) WrStr( MemFreeStr ) ;
   END ShowMemFree ;

PROCEDURE DoTACTWork(BaseWindow: WinType);
VAR Done:     BOOLEAN;
    ch:       CHAR;
    FunctKey: BOOLEAN;
    DoRead:   BOOLEAN;
    dummy:    DataItemPntr;
    ignore:   BOOLEAN;
    tlist:    TACTList;

(*
PROCEDURE NotDefined;
VAR   t:  ARRAY[0..40] OF CHAR;
BEGIN
    t := 'Sorry, currently not defined';
    PutMessage(t); (* new PutMessage must be variable -- to save stack j.b.*)
END NotDefined;
*)

PROCEDURE DoMainSelect;
BEGIN
   PushHelpItem(MainSelectHelpItem);
   IF DoSelectWindow(EditSelectWind,
           ListFromRule, SelectedList, tlist, PoolNoForTempList,
           ListFromRulePos, ch, FunctKey,DoRead,FALSE)  THEN
      TerminateAllActiveDisplays;
      DiscardMainLists(DiscardAll);
      SelectedList := tlist;
      ChangePoolNo( PoolNoForTempList, PoolNoForSelectLists ) ;

      SelectedListEmpty := NOT FirstDisplayItem(SelectedList, SelectedListPos);
      ignore := InitializeAllActiveDisplays(TRUE);
   ELSE
      DiscardList(tlist);
   END;
   PopHelpItem;
END DoMainSelect;

PROCEDURE DoCategoryList;
VAR
   CatNameList: TACTList;
   SelectItem:  TACTListItem;
   CatItem:     TACTListItem;
   TListIn:    TACTList;

PROCEDURE DoListInsert;
VAR Numb:  CARDINAL;
    DataItem:   DataItemPntr;
    DataVA:  VirtAddr;

BEGIN
   REPEAT
      GetItemData(tlist, CatItem, DataVA, DataItem);
      ReleaseItemHold(tlist, CatItem);
      InsertDataItemContentsInList(DataVA, ListFromRule);
      DataItem := VMModify( DataVA ) ;
      DataItem^.Contents := NILVirt ;
      VMRelease( DataVA ) ;
   UNTIL NOT GetNextItem(tlist,CatItem);
   IF NOT GetFirstItem(ListFromRule, ListFromRulePos) THEN
      ProgramErrorAndHalt('Unexpected problem in DoCategoryList');
   END;
   SelectedList := NewMemoryList(PoolNoForSelectLists);
   CopyList(ListFromRule, SelectedList);
END DoListInsert;

BEGIN
   IF NOT PDBOpen THEN
      PutResWarning(NoPDBRes);
      RETURN
   END;
   NewListItem(MainCatList, SelectItem);
   IF NOT GetFirstItem(MainCatList, SelectItem) THEN
     PutResWarning( (*RES REM INS*) 191 ) ;
     DisposeListItem(MainCatList, SelectItem);
     RETURN
   END;
   PushHelpItem(CategorySelectHelpItem);
   TListIn := NewMemoryList(PoolNoForSelectLists);
   IF DoSelectWindow(EditSelectWind,
           MainCatList, TListIn, tlist, PoolNoForTempList,
           SelectItem, ch, FunctKey,DoRead,FALSE) THEN
      NewListItem(tlist, CatItem);
      DiscardList(TListIn);
      IF NOT GetFirstItem(tlist, CatItem) THEN
      (*RES OLD MSG 240
      You have selected no Groups.
      *)
      PutResWarning( (*RES REM INS*) 240 ) ;
      ELSE
      TerminateAllActiveDisplays;
      DiscardMainLists(DiscardAll);

      DisposeListItem(ListFromRule, ListFromRulePos);
      FreePool( PoolNoForListFromRule );
      DiscardList( ListFromRule ) ;  (* added *LP* *)
      ListFromRule := NewMemoryList(PoolNoForListFromRule);
      ChangePoolNo( PoolNoForTempList, PoolNoForListFromRule ) ;

      DoListInsert;
      SelectedListEmpty := NOT FirstDisplayItem(SelectedList, SelectedListPos);
      ignore := InitializeAllActiveDisplays(TRUE);
      END;
      DisposeListItem(tlist, CatItem);
      DiscardList(tlist);
   ELSE
      DiscardList(TListIn);
   END;
   DisposeListItem(MainCatList, SelectItem);
   PopHelpItem;
END DoCategoryList;

PROCEDURE DiscardAndInitAllLists;
BEGIN
   TerminateAllActiveDisplays;

   DisposeListItem(ListFromRule, ListFromRulePos);
   FreePool( PoolNoForListFromRule );
   DiscardList( ListFromRule ) ;        (* added *LP* *)

   DiscardMainLists(DiscardAll) ;

   SelectedListEmpty := TRUE;
   SelectedList := NewMemoryList(PoolNoForSelectLists);
   InitialDisplayItem(SelectedListPos);
   ignore := InitializeAllActiveDisplays(TRUE);

   ListFromRule := MakeTACTTypeList( );

   NewListItem(ListFromRule,ListFromRulePos);
   IF NOT GetFirstItem(ListFromRule,ListFromRulePos) THEN
       ProgramErrorAndHalt('Error in TACTBase')
   END;
END DiscardAndInitAllLists;

PROCEDURE DoWordListSetup() : BOOLEAN ;
   VAR  ch : CHAR ;
BEGIN

   IF NOT SelectedListEmpty AND (GetListType(ListFromRule) = TypeList) THEN
(*RES OLD CHE 18
Do you wish to discard the current selected word-list?  Type "Y" for
yes, or "N" for no:
=YN
*)
     ResAskUser( (*RES REM INS *) 18 , 'YN', ch ) ;
     IF ch <> 'Y' THEN  RETURN FALSE  END ;
   END;

   DiscardAndInitAllLists;
   RETURN TRUE
END DoWordListSetup;

PROCEDURE DoPrintWrite(type: PrintActionType);
BEGIN
   IF CurrentDisplay = None THEN
      (*RES OLD MSG 251
      UseBase only Prints, or Writes to Disk, if a Display is active.
      *)
      PutResError( (*RES REM INS*) 251 );
      RETURN
   END;
   PrintMaster(type,PrintProc[CurrentDisplay],DoRead,ch,FunctKey);
END DoPrintWrite;

PROCEDURE DoFileOpen;

PROCEDURE InitialRefs;
VAR
   T:     StrAny ;
   Dummy: BOOLEAN;
   K:     CARDINAL;
   D:     DisplayType;

PROCEDURE GetRefName(UnitID:   INTEGER;
           VAR UnitName: ARRAY OF CHAR);
VAR dummy:  CARDINAL;
BEGIN
   IF NOT GetNameFromID(UnitID,T,dummy (*not used here j.b.*) ) THEN
      ProgramErrorAndHalt('GetNameFromID could not get given ID')
   END;
   SortToIntWord(T,UnitName);
END GetRefName;

BEGIN
   WITH DisplayData[Variable] DO
      IntToSortWord(UnitName,T);
      IF LookupRefName(T, K) THEN
      UnitID := RefsNameListPntr^[K]^.ID;
      ELSE
      UnitID := 1;
      GetRefName(UnitID, UnitName);
      DispBefore := 2;
      DispAfter := 2;
      END;

      IF LastRefPatLen = 0 THEN
      (* values for other constants are assigned via initialization  j.b. *)
      LastRefPat := '($' ;
      IF UnitID = 1 THEN
         Str.Append(LastRefPat,UnitName);
      ELSE
         GetRefName(1,T);
         Str.Append(LastRefPat,T);
      END;
      Str.Append(LastRefPat,')');
      END;

      Dummy := EncodeRefPat( LastRefPat, LastEncodedRefPat, LastRefPatLen);
    END;

    FOR D := Variable TO Distribution DO
       WITH DisplayData[D] DO
      Str.Copy(RefInfo, LastRefPat );
      EncodedRefLen := LastRefPatLen;
      Lib.Move(ADR(LastEncodedRefPat),ADR(EncodedRefInfo),
              EncodedRefLen+1);
       END;
    END;

    WITH DisplayData[Collocate].ColData DO
       IntToSortWord(ColUnitName,T);
       IF LookupRefName(T, K) THEN
       ColUnitID := RefsNameListPntr^[K]^.ID;
       ELSE
       ColUnitID := 0;
       GetRefName(ColUnitID, ColUnitName);
       ColBefore := 5;
       ColAfter := 5;
       END;
    END;

    WITH RuleWindowData DO
       IntToSortWord(UnitName,T);
       IF LookupRefName(T, K) THEN
       UnitID := RefsNameListPntr^[K]^.ID;
       ELSE
       UnitID := 0;
       GetRefName(UnitID, UnitName);
       ConfBefore := 5;
       ConfAfter := 5;
       END;
    END;
END InitialRefs;

BEGIN
   IF NOT OpenNewDB(BaseWindow) THEN RETURN END;
   RuleFileInfo.FileName[0] := 0C;  (* m.s. *)
   DiscardAndInitAllLists;
   InitialRefs;
   IF PDBOpen THEN
      InitialPrintModule(PDBFileName,ExitList,TermList,HandleFileNameField);
   ELSE
      InitialPrintModule(TDBFileName,ExitList,TermList,HandleFileNameField);
(*    PopUpRes[ABCategory] := 0 *)
   END;
END DoFileOpen;

PROCEDURE DoPanelling;
BEGIN
   IF SelectedListEmpty THEN (* m.s. - apr 94 - check that at least one display open *)
      PutResError( 168 ) ; (* m.s. - msg defined in displayd.mod *)
   ELSE
      LayoutWindowsAsPanels;
      IF NOT InitializeAllActiveDisplays(TRUE) THEN
        ProgramErrorAndHalt('Init of windows in CRPanel failed')
      END ;
   END ;
END DoPanelling;


(* m.s. - moved to profdisp.mod
PROCEDURE DoTextBaseProfile;  (* m.s. *)

  VAR Profile : WindowInfo ;
      ResC: ResCollectionType ;
      dummy: BOOLEAN ;
      Text: ARRAY[0..3] OF ARRAY[0..50] OF CHAR ;
      Ch : CHAR ;
      ProfileWinPtr : WinType ;
      TempStr: StrAny ;

  CONST
   (*RES OLD DTA 30
   ' Title and FileName of TextBase: ' ' FileName of PDB: '
   ' Total Number of Words: ' ' Total Number of Different Words: '
   *)
BEGIN
   GetDataArray((*RES REM INS*) 30  , ResC ) ;
   dummy := GetNextDataArrayStringItem( ResC, Text[0] );
   dummy := GetNextDataArrayStringItem( ResC, Text[1] );
   dummy := GetNextDataArrayStringItem( ResC, Text[2] );
   dummy := GetNextDataArrayStringItem( ResC, Text[3] );
   ReleaseCollection(ResC) ;
   WITH Profile DO
      XPos := 2 ;
      YPos := 4 ;
      XSize := 76 ;
      YSize := 14 ;
      MxYSize := 14 ;
      Type := Active ;
      AllowMove := FALSE ;
      AllowResize := FALSE ;
      IsTop := TRUE ;
    END ;
   PushNewWindow( Profile, ProfileWinPtr, DummyInit ) ;
   (*RES OLD MSG 457
   TextBase Profile
   *)
   GetResMessage((*RES REM INS*) 457 , TempStr ) ;

   SetTitle( ProfileWinPtr, TempStr , RightLowerTitle ) ;
   WrLn ;
   WrLn ;
   WrStr( Text[0] ) ;
   WrStr( '( ' );
   WrStr( TDBTitle ) ;
   WrStr( ' ) ' ) ;
   IF Str.Length( TDBTitle )  + Str.Length( TDBFileName ) > 40 THEN
      WrLn ;
      WrStr('        ') ;
   END ;
   WrStr( TDBFileName ) ;
   WrLn ;
   WrStr( Text[1] ) ;
   WrStr( PDBFileName );
   WrLn ;
   WrStr( Text[2] ) ;
   Str.CardToStr( LONGCARD(NoTokensInDB), TempStr, 10, dummy ) ;
   WrStr( TempStr ) ;
   WrLn ;
   WrStr( Text[3] ) ;
   Str.CardToStr( LONGCARD(NoTypes), TempStr, 10, dummy ) ;
   WrStr( TempStr );
   GetKeyStroke( Ch, dummy ) ;
   PopWindow ;
END DoTextBaseProfile ;
*)

PROCEDURE DoTemplate;  (* m.s. *)

  VAR Template : WindowInfo ;
      ResC: ResCollectionType ;
      dummy: BOOLEAN ;
      Text: ARRAY[0..44] OF ARRAY[0..74] OF CHAR ;
      Ch : CHAR ;
      TemplateWinPtr : WinType ;
      TempStr: StrAny ;

(*RES OLD DTA 32
    '  Help                 ''  Query                 '
    '  Credit               ''  Query Export          '
    '  TEXTBASE PROFILE     ''  QUERY IMPORT          '
    '__Template_____________''__Multiple_Import_______'
    '  Complete Word-list   ''  Selected Word-list    '
    '  Make Group           ''  Delete Group          '
    '  KWIC                 ''  VARIABLE CONTEXT      ''     Legend:'
    '__unassigned___________''__Open_DataBase_________'
    '  Groups               ''  Modify                ''   Function Key Alone'
    '  Replace Group        ''  View Group-list       ''   Ctrl+Function Key'
    '  TEXT                 ''  DISTRIBUTION          ''     SHIFT+FUNCTION KEY'
    '__Resize_Window________''__Move_Window___________''   __Alt+Function Key__'
    '  Cycle Displays       ''  Synchronize Displays  '
    '  View Selected-group  ''  Zoom                  '
    '  COLLOCATES           ''  WINDOW_DISPLAYS       '
    '__unassigned___________''__Script_Dialog_Box_____'
    '  Output to Disk       ''  Exit                  '
    '  Close Display        ''  Script Playback       '
    '  OUTPUT TO PRINTER    ''  SCRIPT RECORD         '
    '__unassigned___________''__End_Script_Record_____'
*)
BEGIN
   GetDataArray((*RES REM INS*) 32  , ResC ) ;
   dummy := GetNextDataArrayStringItem( ResC, Text[0] );
   dummy := GetNextDataArrayStringItem( ResC, Text[1] );
   dummy := GetNextDataArrayStringItem( ResC, Text[2] );
   dummy := GetNextDataArrayStringItem( ResC, Text[3] );
   dummy := GetNextDataArrayStringItem( ResC, Text[4] );
   dummy := GetNextDataArrayStringItem( ResC, Text[5] );
   dummy := GetNextDataArrayStringItem( ResC, Text[6] );
   dummy := GetNextDataArrayStringItem( ResC, Text[7] );
   dummy := GetNextDataArrayStringItem( ResC, Text[8] );
   dummy := GetNextDataArrayStringItem( ResC, Text[9] );
   dummy := GetNextDataArrayStringItem( ResC, Text[10] );
   dummy := GetNextDataArrayStringItem( ResC, Text[11] );
   dummy := GetNextDataArrayStringItem( ResC, Text[12] );
   dummy := GetNextDataArrayStringItem( ResC, Text[13] );
   dummy := GetNextDataArrayStringItem( ResC, Text[14] );
   dummy := GetNextDataArrayStringItem( ResC, Text[15] );
   dummy := GetNextDataArrayStringItem( ResC, Text[16] );
   dummy := GetNextDataArrayStringItem( ResC, Text[17] );
   dummy := GetNextDataArrayStringItem( ResC, Text[18] );
   dummy := GetNextDataArrayStringItem( ResC, Text[19] );
   dummy := GetNextDataArrayStringItem( ResC, Text[20] );
   dummy := GetNextDataArrayStringItem( ResC, Text[21] );
   dummy := GetNextDataArrayStringItem( ResC, Text[22] );
   dummy := GetNextDataArrayStringItem( ResC, Text[23] );
   dummy := GetNextDataArrayStringItem( ResC, Text[24] );
   dummy := GetNextDataArrayStringItem( ResC, Text[25] );
   dummy := GetNextDataArrayStringItem( ResC, Text[26] );
   dummy := GetNextDataArrayStringItem( ResC, Text[27] );
   dummy := GetNextDataArrayStringItem( ResC, Text[28] );
   dummy := GetNextDataArrayStringItem( ResC, Text[29] );
   dummy := GetNextDataArrayStringItem( ResC, Text[30] );
   dummy := GetNextDataArrayStringItem( ResC, Text[31] );
   dummy := GetNextDataArrayStringItem( ResC, Text[32] );
   dummy := GetNextDataArrayStringItem( ResC, Text[33] );
   dummy := GetNextDataArrayStringItem( ResC, Text[34] );
   dummy := GetNextDataArrayStringItem( ResC, Text[35] );
   dummy := GetNextDataArrayStringItem( ResC, Text[36] );
   dummy := GetNextDataArrayStringItem( ResC, Text[37] );
   dummy := GetNextDataArrayStringItem( ResC, Text[38] );
   dummy := GetNextDataArrayStringItem( ResC, Text[39] );
   dummy := GetNextDataArrayStringItem( ResC, Text[40] );
   dummy := GetNextDataArrayStringItem( ResC, Text[41] );
   dummy := GetNextDataArrayStringItem( ResC, Text[42] );
   dummy := GetNextDataArrayStringItem( ResC, Text[43] );
   dummy := GetNextDataArrayStringItem( ResC, Text[44] );
   ReleaseCollection(ResC) ;
  WITH Template DO
      XPos := 2 ;
      YPos := 1 ;
      XSize := 76 ;
      YSize := 22 ;
      MxYSize := 22 ;
      Type := Active ;
      AllowMove := FALSE ;
      AllowResize := FALSE ;
      IsTop := TRUE ;
    END ;
   PushNewWindow( Template, TemplateWinPtr, DummyInit ) ;
   (*RES OLD MSG 496
   Function Keys Template
   *)
   GetResMessage((*RES REM INS*) 496 , TempStr ) ;

   SetTitle( TemplateWinPtr, TempStr , RightLowerTitle ) ;
   (*   ผ ป ว ถ ฯ ส ห ฬ ั
   ศ ษ ฬ ห น ส ฮ  *)

   WrLn ;
   WrStr( '  ษอออออออออออออออออออออออหออออออออออออออออออออออออป ' );
   WrLn ;
   WrStr( 'F1บ' ) ;
   WrStr( Text[0] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[1] ) ;
   WrStr( 'บF2' ) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[2] ) ;
   WrStr( 'บ' ) ;
(*   ChangeColorOnScreen( BoldAttr, 28, 5, 20) ; *)
   WrStr( Text[3] ) ;
   WrStr( 'บ' ) ;
   WrLn ;
   ChangeColorOnScreen( BoldAttr, 3, 3, 23) ;
   ChangeColorOnScreen( BoldAttr, 27, 3, 24) ;
   WrStr( '  บ' ) ;
   WrStr( Text[4] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[5]) ;
   WrStr( 'บ' ) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[6] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[7] ) ;
   WrStr( 'บ' ) ;
   WrLn ;
   WrStr( 'F3บ' ) ;
   WrStr( Text[8] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[9] ) ;
   WrStr( 'บF4' ) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[10] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[11] ) ;
   WrStr( 'บ' ) ;
   ChangeColorOnScreen( BoldAttr, 3, 7, 23) ;
   ChangeColorOnScreen( BoldAttr, 27, 7, 24) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[12] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[13]) ;
   WrStr( 'บ' ) ;
   WrStr( Text[14] );
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[15] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[16] ) ;
   WrStr( 'บ' ) ;
   WrLn ;
   WrStr( 'F5บ' ) ;
   WrStr( Text[17] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[18] ) ;
   WrStr( 'บF6' ) ;
   WrStr( Text[19] ) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[20] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[21] ) ;
   WrStr( 'บ  ' ) ;
   WrStr( Text[22] ) ;
   ChangeColorOnScreen( BoldAttr, 3, 11, 23) ;
   ChangeColorOnScreen( BoldAttr, 27, 11, 24) ;
   ChangeColorOnScreen( BoldAttr, 55, 11, 22) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[23] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[24]) ;
   WrStr( 'บ' ) ;
   WrStr( Text[25] ) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[26] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[27]) ;
   WrStr( 'บ' ) ;
   WrStr( Text[28] ) ;
   WrLn ;
   WrStr( 'F7บ' ) ;
   WrStr( Text[29] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[30] ) ;
   WrStr( 'บF8' ) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[31] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[32] ) ;
   WrStr( 'บ  ' ) ;
   ChangeColorOnScreen( BoldAttr, 3, 15, 23) ;
   ChangeColorOnScreen( BoldAttr, 27, 15, 24) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[33] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[34]) ;
   WrStr( 'บ' ) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[35] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[36] ) ;
   WrStr( 'บ' ) ;
   WrLn ;
   WrStr( 'F9บ' ) ;
   WrStr( Text[37] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[38] ) ;
   WrStr( 'บF10' ) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[39] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[40] ) ;
   WrStr( 'บ' ) ;
   ChangeColorOnScreen( BoldAttr, 3, 19, 23) ;
   ChangeColorOnScreen( BoldAttr, 27, 19, 24) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[41] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[42]) ;
   WrStr( 'บ' ) ;
   WrLn ;
   WrStr( '  บ' ) ;
   WrStr( Text[43] ) ;
   WrStr( 'บ' ) ;
   WrStr( Text[44] ) ;
   WrStr( 'บ' ) ;
   WrLn ;
   WrStr( '  ศอออออออออออออออออออออออสออออออออออออออออออออออออผ ') ;


   GetKeyStroke( Ch, dummy ) ;
   PopWindow ;
END DoTemplate ;


PROCEDURE DoActionBarWork;
VAR
   ActionBarItem:    ActBarActions;
   PopUpItem:        BYTE;
   reply:      CHAR ;
   oldw:            WinType;
BEGIN
   PushHelpItem(ActionBarHelpItem);
   DoRead := DoActionBar(ABar, 0C, ExitList,
                  ch, FunctKey, ActionBarItem, PopUpItem);
   PopHelpItem;
   CASE ActionBarItem OF
      ABNone: RETURN
    | ABHelp:
       CASE HelpActions(PopUpItem) OF
           HLPHelp: DoRead := ShowHelpItem(TermList, ExitList,ch,FunctKey); |
           HLPTemplate: DoTemplate ; |
           HLPCredit:
              PushHelpItem(CreditHelpItem) ;  (* m.s. - apr 94 *)
              DoRead := ShowHelpItem( TermList, ExitList,ch,FunctKey) ;
               (* call up credit screen *)
              PopHelpItem ;
       END ;
    | ABSelect:
     CatWindowData.CatName := '';
     CASE SelectActions(PopUpItem) OF
       SLWordList: IF DoWordListSetup() THEN  DoMainSelect  END ;
     | SLList: DoMainSelect;
     | SLGroups:     DoCategoryList;
     | SLQuery:     DoRuleWindMenu(ch,FunctKey,IgnoreRuleErrors)
     END;
    | ABDisplays:
     CASE CurrentActions(PopUpItem) OF
       CRModify:    ModifyCurrentWindow(ch,FunctKey,DoRead)
     | CRKWIC:      CreateNewWindow(KWIC)
     | CRText:      CreateNewWindow(Text)
     | CRVariable:     CreateNewWindow(Variable)
     | CRDist:      CreateNewWindow(Distribution)
     | CRCollocate: CreateNewWindow(Collocate)
     | CRCycle:      MoveToNextDisplayWindow
     | CRSynch:
          IF NOT InitializeAllActiveDisplays(FALSE) THEN Beep END
     | CRClose:     CloseCurrentWindow
     | CRWindow:     DoPanelling
     | CRZoom:      ZoomCurrentWindow
     END;
    | ABGroup:
     IF PDBOpen THEN
        CASE CatActions(PopUpItem) OF
          CTDelete:  DoCatNameDelete
        | CTMake:  DoCatNameCreate
        | CTReplace:  DoCatNameModify
        | CTList:    DoCatNameDisplay
        | CTGroup:     DoCatListDisplay
        END;
     ELSE
        PutResWarning(NoPDBRes);
     END;
    | ABFile:
     CASE FileActions(PopUpItem) OF
       FLOpen:   DoFileOpen;
     | FLPrint:  DoPrintWrite(ToPrinter);
     | FLDisk:   DoPrintWrite(ToDisk);
     | FLImport: ImportRule(DoRead,ch,FunctKey);
     | FLMultImport:RulesToCats(DoRead,ch,FunctKey);
     | FLExport: ExportRule(DoRead,ch,FunctKey);
     | FLRecord:    OpenOutputScriptFile;
     | FLPlay:   OpenInputScriptFile;
     | FLProfile : DoTextBaseProfile ; (* m.s. *)
     | FLExit:
                (*RES OLD CHE 15   (* ALSO DEFINED IN KEYUTILS.MOD *)
                Do you wish to stop UseBase immediately? Y)es or N)o:
                =YN
                *)
                oldw := Used();
          ResAskUser( (*RES REM INS*) 15, 'YN', reply);
                Use(oldw);
          IF reply = 'Y' THEN  TerminationProc  END ;
     END;
   END;
   DoRead := NOT FunctKey;
END DoActionBarWork;

PROCEDURE DoFunctionKeyWork;
BEGIN
   CASE ch OF
     PCKey.ShiftF1:
       DoTextBaseProfile ; (* m.s. *)
   | PCKey.CtrlF1:
       PushHelpItem(CreditHelpItem) ; (* m.s. - apr 94 *)
       DoRead := ShowHelpItem( TermList, ExitList,ch,FunctKey) ;
       (* call up credit screen *)
       PopHelpItem ;
   | PCKey.AltF1:
       DoTemplate ;
   | PCKey.AltF4:
       DoFileOpen ;
   | PCKey.F2:
       CatWindowData.CatName := '';
       DoRuleWindMenu(ch,FunctKey,IgnoreRuleErrors);
       DoRead := NOT FunctKey;
   | PCKey.ShiftF2:
       ImportRule(DoRead,ch,FunctKey);
   | PCKey.CtrlF2:
       ExportRule(DoRead,ch,FunctKey);
   | PCKey.AltF2:
       RulesToCats(DoRead,ch,FunctKey);
   | PCKey.F3:
       CatWindowData.CatName := '';
       IF DoWordListSetup() THEN  DoMainSelect  END ;
   | PCKey.CtrlF3:
       DoCatNameCreate ;
   | PCKey.ShiftF3:
(* m.s. - may 94 - why is this test here?      IF PDBOpen THEN *)
         CreateNewWindow(KWIC) ;
(*       END ; *)
   | PCKey.F4:
       CatWindowData.CatName := '';
       DoMainSelect;
   | PCKey.ShiftF4:
       CreateNewWindow(Variable) ;
   | PCKey.CtrlF4:
       IF PDBOpen THEN
         DoCatNameDelete ;
       END ;
   | PCKey.F5:
       DoCategoryList ;
   | PCKey.ShiftF5:
       CreateNewWindow(Text) ;
   | PCKey.CtrlF5:
       IF PDBOpen THEN
         DoCatNameModify ;
       END ;
   | PCKey.F6: (* Modify Current Display *)
       ModifyCurrentWindow(ch,FunctKey,DoRead);
   | PCKey.ShiftF6:
       CreateNewWindow(Distribution) ;
   | PCKey.CtrlF6:
       IF PDBOpen THEN
         DoCatNameDisplay ;
       END ;
   | PCKey.F7:
       MoveToNextDisplayWindow;
   | PCKey.ShiftF7:
       CreateNewWindow(Collocate) ;
   | PCKey.CtrlF7:
       IF PDBOpen THEN
         DoCatListDisplay ;
       END ;
   | PCKey.F8:
       IF NOT InitializeAllActiveDisplays(FALSE) THEN Beep END;
   | PCKey.ShiftF8:
       DoPanelling;
   | PCKey.CtrlF8:
       ZoomCurrentWindow;
   | PCKey.F9:
       DoPrintWrite(ToDisk);
   | PCKey.ShiftF9:
       DoPrintWrite(ToPrinter);
   | PCKey.CtrlF9: (* Close Current Display *)
       CloseCurrentWindow;
   | PCKey.ShiftF10: (* m.s. - start script record *)
       OpenOutputScriptFile;
   | PCKey.CtrlF10: (* m.s. - playback script *)
       OpenInputScriptFile;
; (* F1, AF5, AF6, F10, AF8, AF9, AF10 are handled differently jb, m.s.*)
   ELSE
      CASE GetListControlKey(FunctKey,ch) OF
      PrevItem:
         SendInstructionToCurrent(UpKey);
       | NextItem:
         SendInstructionToCurrent(DownKey);
       | PrevScreen:   (* m.s. wuz here *)
         SendInstructionToCurrent(PgUpKey);
       | NextScreen:
         SendInstructionToCurrent(PgDnKey);
       | PrevGroup:
         SendInstructionToCurrent(AltPgUpKey); (* m.s. wuz here *)
       | NextGroup:
         SendInstructionToCurrent(AltPgDnKey);
       | FirstItem:
         SendInstructionToCurrent(HomeKey);
       | LastItem:
         SendInstructionToCurrent(EndKey);
       | ListRight:
         SendInstructionToCurrent(RightKey);
       | ListLeft:
         SendInstructionToCurrent(LeftKey);
       | JumpToEnd:
         SendInstructionToCurrent(REndKey);
       | JumpToBeginning:
         SendInstructionToCurrent(LEndKey);
       | ListEnd:
       | ListCancel:
      ELSE Beep
      END;
   END;
END DoFunctionKeyWork;

BEGIN
   IF PDBOpen THEN
      InitialPrintModule(PDBFileName,ExitList,TermList,HandleFileNameField);
   ELSE
      InitialPrintModule(TDBFileName,ExitList,TermList,HandleFileNameField);
(*    PopUpRes[ABCategory] := 0 *)
   END;

   BuildActionBar(ABar, ActBarRes, PopUpRes);
   ShowActionBar(ABar);

   SetShowBusyWindow( ) ;

   InitRuleWindMenu;
   InitializeData;

   ListFromRule := MakeTACTTypeList();
   SelectedList := NewMemoryList(PoolNoForSelectLists);
   ListByPosition := NewMemoryList(PoolNoForSelectLists);
   PosListStatus := NoPos;
   ListByType := NewMemoryList(PoolNoForSelectLists);
   ListByTypeMade := FALSE;
   InitialDisplayItem(SelectedListPos);
   InitialDisplayItem(PositionListPos);
   InitialDisplayItem(TypeListPos);
   SelectedListEmpty := TRUE;

   NewListItem(ListFromRule,ListFromRulePos);
   IF NOT GetFirstItem(ListFromRule,ListFromRulePos) THEN
       ProgramErrorAndHalt('Error in TACTBase')
   END;


   Done := FALSE;
   DoRead := TRUE;
   REPEAT
      ShowMemFree( ABWindow ) ;
      IF DoRead THEN GetKeyStroke(ch,FunctKey) END;
      DoRead := TRUE;
      IF FunctKey THEN DoFunctionKeyWork
      ELSE
      CASE ch OF
        ASCII.rs,' ': DoActionBarWork
      | ASCII.ht:
      | ASCII.esc:
      ELSE Beep
      END;
      END;
   UNTIL Done;

END DoTACTWork;

BEGIN
   WITH EditSelectWind DO
     XPos :=   2;
     YPos :=   4;
     XSize := 76;
     YSize := 14;
     MxYSize := 14;
     Type := Dialog;
     AllowResize := TRUE;
     AllowMove := TRUE;
   END;
   PopUpRes[ABHelp] := HelpRes; (* m.s. *)
   PopUpRes[ABSelect] := SelectionListRes ;
   PopUpRes[ABDisplays] := CurrentListRes ;
   PopUpRes[ABGroup] := CatListRes ;
   PopUpRes[ABFile] := FileRes ;
   IgnoreRuleErrors := FALSE;
END TACTBase.
