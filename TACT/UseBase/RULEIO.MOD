IMPLEMENTATION MODULE RuleIO;

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

IMPORT TWB, Str, TACTProcesses ;
FROM TACTDataServices IMPORT DisposeDataItem, TACTListToVirt;
FROM RuleWindow IMPORT
  (* const*)  NumbCriteria,
  (* type *)  CriteriaType,
  (* vars *)  RuleWindowData,
  (* proc *)  DoRuleWindMenu, FoldToFitCriteria;
FROM SYSTEM IMPORT ADDRESS;
FROM DBData IMPORT TDBFileName;
FROM Utils IMPORT RemoveExtension, StandardizeFileName;
FROM ListData IMPORT DataItemPntr, StringPntr, ItemType, MarkAsUsed,
           MakeCatDataItem;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;
IMPORT ASCII;
FROM GlobalDefs IMPORT StrAny;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CharField, CardField, CharFieldProc,
                 Switches, SwitchValue, GetFieldInfo, DestroyMenu,
                 MakeMenu, DestroyMenu, ShowFixedText, ShowMenu, DoMenu;
FROM ResMessages IMPORT
   (*proc*) MsgString, PutResError, PutResWarning, PutResMessage,
            ResAskUser, GetResMessage;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM Windows IMPORT ActiveAttrib;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM TACTInit IMPORT
 (* vars  *) ExitList,TermList;
FROM SelectWindow IMPORT
  (* proc *) DoSelectWindow;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, GetFirstItem,
              GetNextItem, DiscardList, GetItemData, GetListType,
              FindFromString, ReleaseItemHold;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, PopHelpItem;
FROM RuleListModule IMPORT
  (* const *) RuleFileExtension,
  (* types *) RuleFileInfoType,
  (* vars  *) RuleFileInfo,
  (* procs *) StartUpRuleFile, CloseDownRuleFile, InitializeRuleList,
              AddNewRuleToFile, GetSortRuleName;
FROM WordBase IMPORT IntToSortWord, WordSepCode;
FROM FileNameBase IMPORT
          HandleFileNameField;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMModify, VMRelease, FreePool,
          WriteAllVirts, VirtToPool;
FROM Categories IMPORT CatWindowDataType, CatWindowData, NoPDBRes;
FROM MainLists IMPORT PoolNoForTempList, PoolNoForSearchWorkingSpace;
FROM ParseRuleSource IMPORT ParseResult, ParseRuleCriteria;
FROM SearchUtils IMPORT
  (* Vars *) NumberInSelListArray, SelectedListArray,
             SearchResultType, SearchResult;
FROM DataLinkModule IMPORT
  (* types *) DataLink,
  (* procs *) GetTACTList, LaunchProcesses, DisposeProcessData;
FROM RegularExpr IMPORT FirstREMsg;
FROM DBData IMPORT PDBOpen, MainCatList, GetNewPoolNumber, ReleasePoolNo;
FROM MemTACTList IMPORT NewMemoryList, InsertListItem;

(*RES OLD MNU 25
    Export Query Name: %0_______________
    Query File:        %1________________________________________
*)
CONST
   ExportMenuID = (*RES REM INS*) 25 ;

(*RES OLD MNU 26
    Import Query Name: %0_______________
    Query File:        %1________________________________________
*)
   ImportMenuID = (*RES REM INS*) 26 ;


(*RES OLD MNU 53
                   Multiple Query Imports
    Query File: %0________________________________________
    Duplicate Handling: Skip: %|1 Update: %|2 Ask: %|3
    Query Failures:  Notify: %|4 Ignore: %|5

    %6___________________________

    %7___________________________________________________
    %8___________________________________________________
    %9___________________________________________________
    %10___________________________________________________
*)
   RuleToCatMenuID = (*RES REM INS*) 53 ;


   ImportHelpID = 23;
   ExportHelpID = 24;
   RuleSelectHelpID = 25;
   GroupImportHelpID = 53;
   GroupImportSelectID = 54;

   RefNameSepChar = "#" ;

   (*RES OLD MSG 237
   "%0" does not exist.
   *)
   NoRuleFileMsg = (*RES REM INS*) 237 ;

TYPE
   GetRuleReturn = ( RuleFound, RuleNotFound, RuleCancel ) ;
   HandleCatDuplicateType = (SkipDup, UpdateDup, AskDup);
   RuleToCatDataType = RECORD
       FileName:   ARRAY[0..40] OF CHAR;
       HowDup:     HandleCatDuplicateType;
       IgnoreFailedQueries : BOOLEAN ; (* m.s. - flag to allow ignored multiple query errors *)
       RuleName:   ARRAY[0..30] OF CHAR;
       Criteria:   CriteriaType;
   END;

VAR
   ExportMenuMade:   BOOLEAN;
   ExportMenu:       MenuID;
   ImportMenuMade:   BOOLEAN;
   ImportMenu:       MenuID;
   ExpImpRuleWind:   WindowInfo;
   RuleSelectWind:   WindowInfo;
   RuleToCatWind:    WindowInfo;
   RuleIgnoreErrs:   BOOLEAN;

PROCEDURE DoRuleSelectionWindow(VAR RetName:   ARRAY OF CHAR): BOOLEAN;
VAR
   ch:         CHAR;
   RUList:     TACTList;
   DummyList:  TACTList;
   DummyList2: TACTList;
   SelectItem: TACTListItem;
   DPtr:       DataItemPntr;
   DVA:        VirtAddr;
   FunctKey:   BOOLEAN;
   BDummy:     BOOLEAN;
BEGIN
   RUList := InitializeRuleList();
   NewListItem(RUList,SelectItem);
   IF NOT GetFirstItem(RUList,SelectItem) THEN
       ProgramErrorAndHalt('Error in DoRuleSelectionWindow')
   END;

   PushHelpItem(RuleSelectHelpID);
   IF NOT DoSelectWindow(RuleSelectWind,
                        RUList, DummyList, DummyList2, 0 (* PoolNo not used *),
                        SelectItem, ch, FunctKey,BDummy,TRUE) THEN
	DisposeListItem( RUList, SelectItem );
	DiscardList(RUList);
	PopHelpItem;
	RETURN FALSE
   END;
   PopHelpItem;

   (* SelectItem points at item selected. *)

   IF GetPanelControlKey(FunctKey, ch) <> PanelCancel THEN
      GetItemData(RUList,SelectItem,DVA, DPtr);
      Str.Copy(RetName,DPtr^.RuleName^.String);
      ReleaseItemHold(RUList, SelectItem);
   END;

   DisposeListItem(RUList,SelectItem);
   DiscardList(RUList);
   RETURN TRUE;
END DoRuleSelectionWindow;

PROCEDURE FileNameVerify(Data: ADDRESS;
                     VAR ReDisplay: BOOLEAN;
                     VAR ReEdit:    BOOLEAN);
TYPE
  RealDataPntr = POINTER TO RuleFileInfoType;
VAR
  Dtx: RealDataPntr;
BEGIN
  Dtx := RealDataPntr(Data);
  HandleFileNameField(Dtx^.FileName,RuleFileExtension,ReDisplay,ReEdit);
END FileNameVerify;


PROCEDURE MakeExpImpMenu(ResNo:     CARDINAL;
                     VAR Menu:      MenuID);
BEGIN
    StartMenu(RuleFileInfo);
    WITH RuleFileInfo DO
       IF FileName[0] = 0C THEN
          RemoveExtension(TDBFileName,FileName);
          IF NOT StandardizeFileName(FileName,RuleFileExtension) THEN
             ProgramErrorAndHalt('Rule File name should be legal!')
          END;
       END;
       CharField(RuleName);
       CharFieldProc(FileName, FileNameVerify);
    END;
    MakeMenu( ResNo,Menu );
END MakeExpImpMenu;


PROCEDURE GetTheRule(VAR InData:  RuleFileInfoType;
                     VAR OutData: DataItemPntr;
                     VAR OutVA:   VirtAddr;
                     VAR Done:    BOOLEAN) : GetRuleReturn ;
VAR
    T:  ARRAY[0..39] OF CHAR;
    RList:	TACTList;
    TItem:	TACTListItem;
    i:		CARDINAL;
    ch:		CHAR;
    Empty:	BOOLEAN;
    return:     GetRuleReturn;
BEGIN
   OutVA := NILVirt;
   WITH InData DO
      Empty := TRUE;
      i := 0;
      WHILE (Empty) AND (i <= HIGH(RuleName)) AND (RuleName[i] <> 0C) DO
         Empty := RuleName[i] = ' ';
         INC(i);
      END;
      IF Empty OR (Str.Pos(RuleName,'?') <= HIGH(RuleName)) THEN
         IF NOT DoRuleSelectionWindow(RuleName) THEN
            Done := TRUE;
            RETURN RuleCancel
         END;
      END;
   END;
   GetSortRuleName( InData.RuleName, T ) ;

   RList := InitializeRuleList();
   NewListItem(RList,TItem);
   OutData := NIL;
   IF FindFromString(T, RuleType, RList, TItem) THEN
      Done := TRUE;
      return := RuleFound;
      GetItemData(RList, TItem, OutVA, OutData);
      ReleaseItemHold(RList, TItem);
      OutData := VMModify(OutVA);
      MarkAsUsed(OutData);
   ELSE
      Done := FALSE;
      return := RuleNotFound
   END;
   DisposeListItem(RList,TItem);
   DiscardList(RList);
   RETURN return;
END GetTheRule;

PROCEDURE ImportRule(VAR DoRead:   BOOLEAN;
                     VAR ch:       CHAR;
                     VAR FunctKey: BOOLEAN);
VAR
   L:                    CARDINAL;
   w:                    TWB.WinType;
   A:                    DataItemPntr;
   VA:                   VirtAddr;
   Done:                 BOOLEAN;
   FileExists:           BOOLEAN;

BEGIN
   IF NOT ImportMenuMade THEN
      MakeExpImpMenu(ImportMenuID, ImportMenu);
      ImportMenuMade := TRUE
   END;

   L := 0;
   RuleFileInfo.RuleName := 0C;
   PushHelpItem(ImportHelpID);
   PushNewWindow(ExpImpRuleWind,w, DummyInit);
   ShowFixedText(w, ImportMenu, 0,0);
   IF RuleFileInfo.FileName[0] = 0C THEN  (* m.s. - bug fix to handle second DB opened *)
      RemoveExtension(TDBFileName,RuleFileInfo.FileName);
      IF NOT StandardizeFileName(RuleFileInfo.FileName,RuleFileExtension) THEN
            ProgramErrorAndHalt('Rule File name should be legal!')
      END;
   END;
   ShowMenu(w,ImportMenu,0,0,RuleFileInfo);
   REPEAT
      Done := TRUE;
      DoMenu(w,ImportMenu,0,0,TermList,ExitList,
                      RuleFileInfo,L,ch,FunctKey);
      IF GetPanelControlKey(FunctKey, ch) <> PanelCancel THEN
         IF NOT StartUpRuleFile(FileExists) THEN
            IF NOT FileExists THEN
               MsgString(RuleFileInfo.FileName,0);
               PutResError( NoRuleFileMsg );
            END;
            Done := FALSE;
         ELSE
            CASE GetTheRule(RuleFileInfo,A,VA,Done) OF
		RuleCancel: |
		RuleNotFound:
		   (*RES OLD MSG 238
		   "%0" is not in Query File "%1".
		   *)
		   MsgString(RuleFileInfo.RuleName,0);
		   MsgString(RuleFileInfo.FileName,0);
		   PutResError( (*RES REM INS*) 238 ); |
		RuleFound:
                   Str.Copy(CatWindowData.CatName, A^.RuleName^.String );
		   WITH RuleWindowData DO
			IF NOT FoldToFitCriteria(A^.RuleLine^.String,Criteria) THEN
			   (*RES OLD MSG 253
			   The selected item was too large to be inserted in you Autoselection Query.
			   *)
			   PutResError( (*RES REM INS*) 253 );
			ELSE
			   DoRuleWindMenu(ch,FunctKey,RuleIgnoreErrs);
			   DoRead := NOT FunctKey;
			END;
		   END;
		   VMRelease(VA);
		   DisposeDataItem(VA);
            END;
            CloseDownRuleFile;
         END;
      END;
   UNTIL Done;
   PopHelpItem;
   PopWindow;
END ImportRule;

PROCEDURE ExportRule(VAR DoRead:   BOOLEAN;
                     VAR ch:       CHAR;
                     VAR FunctKey: BOOLEAN);
VAR
   L:                    CARDINAL;
   w:                    TWB.WinType;
   A:                    DataItemPntr;
   VA:                   VirtAddr;
   Done:                 BOOLEAN;
   FileExists:           BOOLEAN;
   ch1:                  CHAR;
   DoInsert:             BOOLEAN;
   tStr:                 StrAny;
   i:                    CARDINAL;

PROCEDURE CriteriaEmpty(): BOOLEAN;
BEGIN
   FOR i := 0 TO NumbCriteria-1 DO
     IF (RuleWindowData.Criteria[i][0] <> 0C) THEN RETURN FALSE END;
   END;
   RETURN TRUE;
END CriteriaEmpty;

BEGIN
   IF CriteriaEmpty() THEN
      (*RES OLD MSG 239
      You should first define a Query in the Autoselection Window before trying
      to Export.
      *)
      PutResError( (*RES REM INS*) 239 );
      RETURN
   END;
   IF NOT ExportMenuMade THEN
      MakeExpImpMenu(ExportMenuID, ExportMenu);
      ExportMenuMade := TRUE
   END;
   L := 0;
   RuleFileInfo.RuleName := 0C;
   PushHelpItem(ExportHelpID);
   PushNewWindow(ExpImpRuleWind,w, DummyInit);
   ShowFixedText(w, ExportMenu, 0,0);
   IF RuleFileInfo.FileName[0] = 0C THEN  (* m.s. - bug fix to handle second DB opened *)
      RemoveExtension(TDBFileName,RuleFileInfo.FileName);
      IF NOT StandardizeFileName(RuleFileInfo.FileName,RuleFileExtension) THEN
            ProgramErrorAndHalt('Rule File name should be legal!')
      END;
   END;
   ShowMenu(w,ExportMenu,0,0,RuleFileInfo);
   DoInsert := FALSE;
   REPEAT
      Done := TRUE;
      DoMenu(w,ExportMenu,0,0,TermList,ExitList,
                      RuleFileInfo,L,ch,FunctKey);
      IF GetPanelControlKey(FunctKey, ch) <> PanelCancel THEN
         IF NOT StartUpRuleFile(FileExists) THEN
            IF NOT FileExists THEN
(*RES OLD CHE 10
File "%0" does not exist. Do you wish to create it? Y)es or N)o:
=YN
*)
               MsgString(RuleFileInfo.FileName,0);
               ResAskUser( (*RES REM INS*) 10 , 'YN', ch1);
               IF ch1 = 'Y' THEN DoInsert := TRUE END;
            ELSE
               Done := FALSE;
            END;
         ELSE
            CASE GetTheRule(RuleFileInfo,A,VA,Done) OF
		RuleCancel:
		   DoInsert := FALSE;
		   Done := TRUE;  |
		RuleNotFound:		
		   DoInsert := TRUE;
		   Done := TRUE;  |
		RuleFound:
(*RES OLD CHE 11
Query "%0" is already in file "%1".  Do you wish to replace the old entry?
Y)es or N)o:
=YN
*)
		   Str.Copy(RuleFileInfo.RuleName, A^.RuleName^.String);
		   MsgString(RuleFileInfo.RuleName,0);
		   MsgString(RuleFileInfo.FileName,0);
		   ResAskUser( (*RES REM INS*) 11 , 'YN', ch1);
		   IF ch1 = 'Y' THEN DoInsert := TRUE END;
		   VMRelease(VA);
		   DisposeDataItem(VA);
            END;
            CloseDownRuleFile;
         END;
      END;
   UNTIL Done;
   IF DoInsert THEN
      WITH RuleWindowData DO
         tStr[0] := 0C;
         FOR i := 0 TO NumbCriteria-1 DO
            IF Criteria[i][0] <> 0C THEN
               IF tStr[0] <> 0C THEN Str.Append(tStr,' ') END;
               Str.Append(tStr,Criteria[i]);
            END;
         END;
         AddNewRuleToFile(RuleFileInfo.RuleName,tStr);
      END;
   END;
   PopHelpItem;
   PopWindow;
END ExportRule;

PROCEDURE RToCFileNameVerify(Data: ADDRESS;
                         VAR ReDisplay: BOOLEAN;
                         VAR ReEdit:    BOOLEAN);
TYPE
  RealDataPntr = POINTER TO RuleToCatDataType;
VAR
  Dtx: RealDataPntr;
BEGIN
  Dtx := RealDataPntr(Data);
  HandleFileNameField(Dtx^.FileName,RuleFileExtension,ReDisplay,ReEdit);
END RToCFileNameVerify;

PROCEDURE RulesToCats(VAR DoRead:   BOOLEAN;
                      VAR ch:       CHAR;
                      VAR FunctKey: BOOLEAN);
VAR
   FileExists:      BOOLEAN;
   RulesToDo:       TACTList;
   SelectItem:      TACTListItem;
   RuleVA:          VirtAddr;
   RuleData:        DataItemPntr;
   ch1:             CHAR;
   StopImmediately: BOOLEAN;
   RuleToCatData:   RuleToCatDataType;
   w:               TWB.WinType;
   m:               MenuID;
   i:               CARDINAL;

PROCEDURE DoRuleSelection(VAR RulesToDo:   TACTList): BOOLEAN;
VAR
   ch:         CHAR;
   RUList:     TACTList;
   DummyList:  TACTList;
   SelectItem: TACTListItem;
   DPtr:       DataItemPntr;
   DVA:        VirtAddr;
   FunctKey:   BOOLEAN;
   BDummy:     BOOLEAN;
   Cancel:     BOOLEAN;
BEGIN
   DummyList := NewMemoryList( PoolNoForTempList );
   RUList := InitializeRuleList();
   NewListItem(RUList,SelectItem);
   IF NOT GetFirstItem(RUList,SelectItem) THEN
       ProgramErrorAndHalt('Error in DoRuleSelectionWindow')
   END;

   PushHelpItem(GroupImportSelectID);
   Cancel := NOT DoSelectWindow(RuleSelectWind,
                        RUList, DummyList, RulesToDo, PoolNoForTempList,
                        SelectItem, ch, FunctKey,BDummy,FALSE);
   IF Cancel THEN
        FreePool( PoolNoForTempList );
        DiscardList( RulesToDo );
   END;
   DiscardList( DummyList );
   DisposeListItem( RUList, SelectItem );
   DiscardList(RUList);
   PopHelpItem;
   RETURN NOT Cancel;
END DoRuleSelection;

PROCEDURE HandleGettingRuleList(): BOOLEAN;
VAR
   r:            BOOLEAN;

PROCEDURE CloseUp;
BEGIN
   DestroyMenu(m);
END CloseUp;

BEGIN
   Str.Copy(RuleToCatData.FileName, RuleFileInfo.FileName);
   RuleToCatData.HowDup := SkipDup;
(*   RuleToCatData.IgnoreFailedQueries := FALSE ; *)

   StartMenu(RuleToCatData);
   WITH RuleToCatData DO
      IF FileName[0] = 0C THEN
         RemoveExtension(TDBFileName,FileName);
         IF NOT StandardizeFileName(FileName,RuleFileExtension) THEN
            ProgramErrorAndHalt('File name should be legal!')
         END;
      END;
      CharFieldProc(FileName, RToCFileNameVerify);
      Switches(HowDup);
        SwitchValue(SkipDup);
        SwitchValue(UpdateDup);
        SwitchValue(AskDup);
      Switches(IgnoreFailedQueries);
        SwitchValue(FALSE);
        SwitchValue(TRUE);
   END;
   MakeMenu( RuleToCatMenuID,m );
   ShowFixedText(w, m, 0,0);
   ShowMenu(w,m,0,0,RuleToCatData);
   i := 0;
   DoMenu(w,m,0,0,TermList,ExitList,
                  RuleToCatData,i,ch,FunctKey);
   IF GetPanelControlKey(FunctKey, ch) = PanelCancel THEN
      CloseUp;
      RETURN FALSE;
   END;
   r := StandardizeFileName(RuleToCatData.FileName,RuleFileExtension);
   ShowMenu(w,m,0,0,RuleToCatData);
   Str.Copy(RuleFileInfo.FileName, RuleToCatData.FileName);
   IF NOT StartUpRuleFile(FileExists) THEN
      IF NOT FileExists THEN
         MsgString(RuleFileInfo.FileName,0);
         PutResError( NoRuleFileMsg );
      END;
      CloseUp;
      RETURN FALSE
   END;
   r := DoRuleSelection(RulesToDo);
   CloseDownRuleFile;
   CloseUp;
   RETURN r;
END HandleGettingRuleList;

PROCEDURE HandleRule(RuleData: DataItemPntr): BOOLEAN;
VAR
   NeedSelect:      BOOLEAN;
   PResult:         ParseResult;
   TLink:           DataLink;
   OldPoolNo,
   NewPoolNo:       CARDINAL;
   TList:           TACTList;
   TItem:           TACTListItem;
   TStr:            ARRAY [0..80] OF CHAR;
   Something:       BOOLEAN;
   CatDVA:          VirtAddr;
   CatItemPntr:     DataItemPntr;
   dummy:           BOOLEAN;
   wDup:            HandleCatDuplicateType;
   DoInsert:        BOOLEAN;
BEGIN
   Str.Copy(RuleToCatData.RuleName, RuleData^.RuleName^.String);
   IntToSortWord( RuleToCatData.RuleName, TStr ) ;
   NewListItem(MainCatList, TItem);
   wDup := RuleToCatData.HowDup;
   DoInsert := TRUE;
   IF FindFromString(TStr, CatType, MainCatList, TItem) THEN
      dummy := TRUE;
      IF wDup = AskDup THEN
(*RES OLD CHE 29
The group named "%0" is already in the .GIX file.  Do you wish to skip it and
C)ontinue, R)eplace the contents, or S)top immediately?
=SRC
*)
         MsgString(RuleData^.RuleName^.String, 0);
         ResAskUser( (*RES REM INS*) 29 , 'SRC', ch1);
         IF ch1 = 'S' THEN wDup := SkipDup; dummy := FALSE
         ELSIF ch1 = 'C' THEN wDup := SkipDup
         ELSE wDup := UpdateDup END;
      END;
      IF wDup = SkipDup THEN
         DisposeListItem(MainCatList, TItem);
         RETURN dummy
      ELSE
         DoInsert := FALSE;
         GetItemData(MainCatList, TItem, CatDVA, CatItemPntr);
         ReleaseItemHold(MainCatList, TItem);
      END;
   END;
   DisposeListItem(MainCatList, TItem);

   IF NOT FoldToFitCriteria(RuleData^.RuleLine^.String,RuleWindowData.Criteria) THEN
      ShowMenu(w,m,0,0,RuleToCatData);
      FOR i := 1 TO NumbCriteria-1 DO RuleToCatData.Criteria[i] := '' END;
      ShowMenu(w,m,0,0,RuleToCatData);
(*RES OLD CHE 25
The Query "%0" is too large to fit.  Do you wish to skip it and C)ontinue,
or S)top immediately?
=SC
*)
      MsgString(RuleData^.RuleName^.String, 0);
      ResAskUser( (*RES REM INS*) 25 , 'SC', ch1);
      RETURN ch1 = 'C';
   END;
   NumberInSelListArray := 0 ;		(* <<-- is this right place ?? *)
   FreePool( PoolNoForSearchWorkingSpace );
   REPEAT
      RuleToCatData.Criteria := RuleWindowData.Criteria;
      ShowMenu(w,m,0,0,RuleToCatData);
      PResult := ParseRuleCriteria(TLink,NeedSelect);
      IF PResult = ParseRepeat THEN
         DisposeProcessData
      END;
   UNTIL PResult <> ParseRepeat;
   IF PResult <> ParseOK THEN
      DisposeProcessData;
      FOR i := 1 TO NumberInSelListArray DO
	 DiscardList( SelectedListArray[ i ] )
      END ;
      IF RuleToCatData.IgnoreFailedQueries THEN (* m.s. - added option for multiple import to ignore failures *)
        RETURN TRUE;
      ELSE
        (*RES OLD CHE 26
        The Query "%0" did not parse correctly.  Do you wish to skip it and C)ontinue,
        or S)top immediately?
        =SC
        *)
        MsgString(RuleData^.RuleName^.String, 0);
        ResAskUser( (*RES REM INS*) 26 , 'SC', ch1);
        RETURN ch1 = 'C';
      END ;
   END;
   FirstREMsg := TRUE ;
   SearchResult := SearchOK;
   RuleWindowData.IgnoreErrs := TRUE;
   LaunchProcesses;
   NewPoolNo := GetNewPoolNumber();
   GetTACTList(TLink, NewPoolNo, TList);
   TACTProcesses.YIELD;
   FreePool( PoolNoForSearchWorkingSpace );

   NewListItem(TList, TItem);
   Something := GetFirstItem(TList, TItem);
   DisposeListItem(TList, TItem);
   IF (NOT Something) AND (SearchResult < SearchFailed) THEN
      IF (RuleToCatData.IgnoreFailedQueries) (* m.s. *) THEN
        RETURN TRUE;
      ELSE
        (*RES OLD CHE 27
        The Query "%0" did not select anything.  Do you wish to skip it and C)ontinue,
        or S)top immediately?
        =SC
        *)
        MsgString(RuleData^.RuleName^.String, 0);
        ResAskUser( (*RES REM INS*) 27 , 'SC', ch1);
        RETURN ch1 = 'C';
      END ;
   ELSIF (SearchResult = SearchWarned) THEN
      IF (RuleToCatData.IgnoreFailedQueries) THEN (*m.s.*)
         SearchResult := SearchFailed;
      ELSE
         (*RES OLD CHE 28
         The Query "%0" generated warning messages.  Do you wish to U)se the resulting
         list, C)ontinue to the next, or S)top immediately?
         =UCS
         *)
         MsgString(RuleData^.RuleName^.String, 0);
         ResAskUser( (*RES REM INS*) 28 , 'UCS', ch1);
         IF ch1 = 'U' THEN SearchResult := SearchOK
         ELSIF ch1 = 'C' THEN SearchResult := SearchFailed
         ELSE
           ReleasePoolNo(NewPoolNo);
           FreePool(NewPoolNo);
           RETURN FALSE
         END;
      END ;
   END;
   FOR i := 1 TO NumberInSelListArray DO DiscardList( SelectedListArray[i]) END;

   IF SearchResult = SearchOK THEN
      IF DoInsert THEN
         MakeCatDataItem(TStr, 0, CatDVA, CatItemPntr);
         dummy := InsertListItem(CatDVA, MainCatList);
      ELSE
         CatItemPntr := VMModify(CatDVA);
         OldPoolNo := VirtToPool(CatItemPntr^.Contents);
         ReleasePoolNo(OldPoolNo);
         FreePool(OldPoolNo);
      END;
      TACTListToVirt(TList, NewPoolNo, CatItemPntr^.Contents);
      VMRelease(CatDVA);
      WriteAllVirts();
   ELSE
      ReleasePoolNo(NewPoolNo);
      FreePool(NewPoolNo);
   END;
   DiscardList(TList);
   RETURN TRUE;
END HandleRule;

BEGIN
   DoRead := TRUE;
   IF NOT PDBOpen THEN
      PutResWarning(NoPDBRes);
      RETURN
   END;
   RuleToCatData.IgnoreFailedQueries := FALSE ;
   PushHelpItem(GroupImportHelpID);
   PushNewWindow(RuleToCatWind,w, DummyInit);
   IF NOT HandleGettingRuleList() THEN
      PopWindow;
      RETURN
   END;
   NewListItem(RulesToDo, SelectItem);
   IF NOT GetFirstItem(RulesToDo, SelectItem) THEN
      (*RES OLD MSG 442
      You selected no Queries to be converted into Groups.
      *)
      PutResError( (*RES REM INS*) 442 );
      PopWindow;
      RETURN
   END;
   TWB.SetPalette(w, ActiveAttrib);
   StartMenu(RuleToCatData);
   WITH RuleToCatData DO
      CharField(FileName);
      Switches(HowDup);
        SwitchValue(SkipDup);
        SwitchValue(UpdateDup);
        SwitchValue(AskDup);
      Switches(IgnoreFailedQueries);
        SwitchValue(FALSE);
        SwitchValue(TRUE);
      CharField(RuleName);
      FOR i := 0 TO NumbCriteria-1 DO CharField(Criteria[i]) END;
   END;
   MakeMenu( RuleToCatMenuID,m );
   REPEAT
      GetItemData(RulesToDo, SelectItem, RuleVA, RuleData);
      StopImmediately := NOT HandleRule(RuleData);
      ReleaseItemHold(RulesToDo, SelectItem);
   UNTIL (StopImmediately) OR (NOT GetNextItem(RulesToDo, SelectItem));
   DisposeListItem(RulesToDo, SelectItem);
   FreePool( PoolNoForTempList );
   DiscardList( RulesToDo );
   PopWindow;
   DestroyMenu(m);
   PopHelpItem;
END RulesToCats;

PROCEDURE InitRuleIO;
BEGIN
   ExportMenuMade := FALSE;
   ImportMenuMade := FALSE;
   WITH ExpImpRuleWind DO
       XPos := 9;
       YPos := 4;
       YSize := 2;
       XSize := 62;
       MxYSize := 14;
       Type := Dialog;
       AllowMove := TRUE;
       AllowResize := FALSE;
   END;
   WITH RuleSelectWind DO
        XPos :=   9;
        YPos :=   7;
        XSize := 62;
        YSize := 9;
        MxYSize := 9;
        Type := Dialog;
        AllowMove := TRUE;
        AllowResize := TRUE;
   END;
   WITH RuleToCatWind DO
       XPos := 9;
       YPos := 4;
       YSize := 11;
       XSize := 62;
       MxYSize := 14;
       Type := Dialog;
       AllowMove := TRUE;
       AllowResize := FALSE;
   END;
   RuleIgnoreErrs := TRUE;
(*   IgnoreFailedQueries := FALSE ; *)
END InitRuleIO;
END RuleIO.
