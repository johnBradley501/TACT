IMPLEMENTATION MODULE RuleWindow;

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
(*V4=Dbg Debugging code *)

IMPORT ASCII, Str, TACTProcesses ;
FROM TWB IMPORT WinType;
FROM Utils IMPORT TrimBlanks;
FROM SYSTEM IMPORT ADDRESS, ADR;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;

(* Shrink *)
FROM ParseRuleSource IMPORT ParseResult, ParseRuleCriteria, InitParseRule;
FROM ScannerSource IMPORT InitScanner;
FROM SearchUtils IMPORT
  (* Vars *) NumberInSelListArray, SelectedListArray,
             SearchResultType, SearchResult;
FROM ParserSource IMPORT
  (* procs *) InitializeParserTables;
FROM DataLinkModule IMPORT
  (* types *) DataLink,
  (* procs *) GetTACTList, LaunchProcesses, DisposeProcessData, InitDataLinks;
FROM RegularExpr IMPORT FirstREMsg;
FROM WhenWork IMPORT InitWhenWork;
FROM RuleIO IMPORT InitRuleIO;
FROM TACTDataServices IMPORT GeneralUnitNameVerify;
(* Shrink *)

FROM GlobalDefs IMPORT StrAny;
FROM StringIO IMPORT
   SWriteString, SWriteChar;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CharField, CardField, CharFieldProc,
                 Switches, SwitchValue, GetFieldInfo,
                 MakeMenu, DestroyMenu, ShowFixedText, ShowMenu, DoMenu;
FROM MainLists IMPORT
  (* const*) PoolNoForOldRuleList, PoolNoForOldSelect, PoolNoForSelectLists,
             PoolNoForListFromRule, PoolNoForSearchWorkingSpace,
  (* type *) PosListStatusType, DiscardMainListType,
  (* vars *) ListFromRule, ListFromRulePos, SelectedList,
             SelectedListPos, SelectedListEmpty,
  (* proc *) DiscardMainLists;
FROM ResMessages IMPORT
   (*proc*) MsgString, PutResError, PutResWarning, PutResMessage,
            ResAskUser, GetResMessage;
FROM DisplayDialog IMPORT
  (* proc *) InitializeAllActiveDisplays, TerminateAllActiveDisplays;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM Windows IMPORT
  (* Const  *) BoldAttr;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames,
   (* procs *) LookupRefName, GetNameFromID;
FROM WordBase IMPORT
  (* Procs *) SortToIntWord;
FROM TACTInit IMPORT
 (* vars  *) ExitList,TermList;
FROM ListData IMPORT DataItemPntr;
FROM VirtMem IMPORT VirtAddr, FreePool, ChangePoolNo;
FROM SelectWindow IMPORT
  (* proc *) DoSelectWindow;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, GetFirstItem, ReleaseItemHold,
              GetNextItem, DiscardList, GetItemData, GetListType;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, CopyList;
FROM TypeListModule IMPORT MakeTACTTypeList;

FROM PositionManagement IMPORT
  (* procs *) FirstDisplayItem, DiscardDisplayItem, InitialDisplayItem;
FROM KeyTranslation IMPORT WriteScreenField, FirstKeyIsText;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, PopHelpItem;
(*<Dbg
FROM Trace IMPORT
(*vars *) DoTrace,
(*procs*) TWriteString, TWriteLn;
Dbg>*)

(*RES OLD MNU 17
                       Query Dialog Box
  Query:
  %2___________________________________________________
  %3___________________________________________________
  %4___________________________________________________
  %5___________________________________________________

  Span Context:        Unit: %8________________
                     Before: %6______  After: %7_______

  For a list of Reference Names for "Unit", type "?" in the
                       Unit field.

  Ignore Errors? Yes: %|9No: %|10
  Manual Select? Yes: %|0No: %|1  %11__________________
*)
CONST
    RuleWindResource = (*RES REM INS*) 17 ;
    SearchField = 11;

    RuleWindHelpItem = 8;
    MainSelectHelpItem = 11;

VAR
    RuleWindInfo:        WindowInfo;
    SelLstSelectWind:    WindowInfo;
    WorkingRuleWindData: RuleWindowDataType;

(*<Dbg
    debug : BOOLEAN ;
    TempRuleList : TACTList ;
Dbg>*)

PROCEDURE VerifyUnitName(Data:      ADDRESS;
                     VAR ReDisplay: BOOLEAN;
                     VAR ReEdit:    BOOLEAN);

TYPE RWDP = POINTER TO RuleWindowDataType;

VAR RWD:RWDP;

BEGIN
   RWD := RWDP(Data);
   WITH RWD^ DO
      GeneralUnitNameVerify(UnitName,UnitID,ReDisplay,ReEdit);
   END;
END VerifyUnitName;

PROCEDURE VerifyCriteria(Data:      ADDRESS;
                     VAR ReDisplay: BOOLEAN;
                     VAR ReEdit:    BOOLEAN);

TYPE RWDP = POINTER TO RuleWindowDataType;

VAR RWD:RWDP;
    i:  CARDINAL;

BEGIN
   RWD := RWDP(Data);
   WITH RWD^ DO
	IF FirstKeyIsText THEN
	   FOR i := 1 TO NumbCriteria-1 DO Criteria[i] := 0C END;
	   ReDisplay	:= TRUE ;
	   ReEdit	:= FALSE ;
	END ;
   END;
END VerifyCriteria;


PROCEDURE InitRuleWindMenu;
(* Shrink *)
VAR T:  StrAny;
    dummy: CARDINAL;

PROCEDURE InitCriteriaLines;
VAR i:   CARDINAL;
BEGIN
  FOR i := 0 TO NumbCriteria-1 DO
     RuleWindowData.Criteria[i] := ''
  END;
END InitCriteriaLines;

(* Shrink *)
BEGIN
(* Shrink *)
    WITH RuleWindInfo DO;
       XPos := 10;
       YPos := 3;
       YSize := 16;
       XSize := 60;
       MxYSize := 14;
       Type := Dialog;
       AllowMove := TRUE;
       AllowResize := FALSE;
    END;

    WITH SelLstSelectWind DO
        XPos :=   2;
        YPos :=   9;
        XSize := 76;
        YSize := 10;
        MxYSize := 10;
        Type := Dialog;
        AllowMove := TRUE;
        AllowResize := TRUE;
    END;

    WITH RuleWindowData DO
       DoSelect := TRUE;
       IgnoreErrs := FALSE;
(*     Criteria[0] := '';  This is done by InitCriteriaLines  j.b. *)
       ConfBefore := 5;
       ConfAfter := 5;
       UnitID := 0;
   END;
   InitCriteriaLines;

(*<Dbg
   debug := FALSE ;
Dbg>*)

    InitScanner;
    InitParseRule;
    InitDataLinks;
    InitWhenWork;
    InitRuleIO;

    WITH RuleWindowData DO
       (* values for other constants are assigned via initialization  j.b. *)
       IF NOT GetNameFromID(UnitID,T,dummy) THEN
          ProgramErrorAndHalt('GetNameFromID could not get given ID')
       END;
       SortToIntWord(T,UnitName);
    END;
    InitializeParserTables;
(* Shrink *)
END InitRuleWindMenu;

PROCEDURE DoRuleWindMenu(VAR ch:               CHAR;
                         VAR FunctKey:         BOOLEAN;
                         VAR IgnoreErrors:     BOOLEAN);

(* Shrink *)
VAR
   RuleWindMenu: MenuID;
   SearchWord:   ARRAY[0..15] OF CHAR;
   SearchX,
   SearchY,
   SearchL:      CARDINAL;
   ch1:          CHAR;
   OldCrit:      CriteriaType;
   w:            WinType;
   rc:           CARDINAL;
   Done:         BOOLEAN;
   L:            CARDINAL;
   TLink:        DataLink;
   NeedSelect:   BOOLEAN;
   FirstTrial:   BOOLEAN;
   PResult:      ParseResult;
   i:	         CARDINAL ;
   dDIP:         DataItemPntr;
   Something:    BOOLEAN;
   OldRuleList:  TACTList;
   OldRuleItem:  TACTListItem;

PROCEDURE UpdateLists;
VAR
    dummy:    DataItemPntr;
    ignore:   BOOLEAN;
    NewSelectedList: TACTList;
BEGIN
   TerminateAllActiveDisplays;
   DisposeListItem(OldRuleList, OldRuleItem);
   FreePool( PoolNoForOldRuleList );
   DiscardList(OldRuleList);
   FreePool(PoolNoForOldSelect);
   DiscardMainLists(DiscardAll);

   SelectedList := NewMemoryList(PoolNoForSelectLists);
   CopyList(ListFromRule, SelectedList);

   WriteScreenField( w,SearchL, SearchX, SearchY, 0C,BoldAttr,TRUE);
   IF RuleWindowData.DoSelect THEN
      PushHelpItem(MainSelectHelpItem);
      IF NOT DoSelectWindow(SelLstSelectWind,
                 ListFromRule, SelectedList, NewSelectedList, 
                 PoolNoForSelectLists, ListFromRulePos, ch, FunctKey,ignore,FALSE) THEN
          DiscardList(NewSelectedList);
      ELSE
          DiscardList(SelectedList);
          SelectedList := NewSelectedList;
      END;
      PopHelpItem;
   END;
   SelectedListEmpty := NOT FirstDisplayItem(SelectedList, SelectedListPos);
   ignore := InitializeAllActiveDisplays(TRUE);
END UpdateLists;

(* Shrink *)
BEGIN
(* Shrink *)
   RuleWindowData.IgnoreErrs := IgnoreErrors;
   StartMenu(RuleWindowData);
   WITH RuleWindowData DO
      Switches(DoSelect);
         SwitchValue(TRUE);
         SwitchValue(FALSE);
      CharFieldProc(Criteria[0], VerifyCriteria);
      FOR L := 1 TO NumbCriteria-1 DO
         CharField(Criteria[L]);
      END;
      CardField(ConfBefore);
      CardField(ConfAfter);
      CharFieldProc(UnitName,VerifyUnitName);
      Switches(IgnoreErrs);
         SwitchValue(TRUE);
         SwitchValue(FALSE);
   END;
   MakeMenu( RuleWindResource, RuleWindMenu);

   (*RES OLD MSG 159
   Searching
   *)
   GetResMessage( (*RES REM INS*) 159, SearchWord);
   GetFieldInfo(RuleWindMenu, SearchField, SearchX, SearchY, SearchL);

   PushHelpItem(RuleWindHelpItem);

   OldCrit := RuleWindowData.Criteria;
   PushNewWindow(RuleWindInfo,w, DummyInit);

   ShowFixedText(w, RuleWindMenu, 0,0);
   WorkingRuleWindData := RuleWindowData;

   ChangePoolNo( PoolNoForListFromRule, PoolNoForOldRuleList );
   OldRuleList := ListFromRule;
   OldRuleItem := ListFromRulePos;
   ListFromRule := NewMemoryList(PoolNoForListFromRule);
   NewListItem(ListFromRule, ListFromRulePos);
   L := 0;
   FirstTrial := TRUE;
   REPEAT
      ShowMenu(w,RuleWindMenu,0,0,WorkingRuleWindData);
      DoMenu(w,RuleWindMenu,0,0,TermList,ExitList,
                   WorkingRuleWindData,L,ch,FunctKey);
      Done := TRUE;
      IF GetPanelControlKey(FunctKey, ch) = PanelCancel THEN
         SearchResult:= SearchStoppedByUser;
      ELSE (* IF GetPanelControlKey(FunctKey, ch) <> PanelCancel *)
         WITH WorkingRuleWindData DO
            RuleWindowData := WorkingRuleWindData;
            IgnoreErrors := RuleWindowData.IgnoreErrs;
	    (*<Dbg
               DoTrace := TRUE;
               TWriteString('RuleWind: Criteria:');
               TWriteString(RuleWindowData.Criteria[0]);
               IF RuleWindowData.Criteria[1][0] <> 0C THEN
                  TWriteString('/');
                  TWriteString(RuleWindowData.Criteria[1])
               END;
               TWriteLn;
	    Dbg>*)

	    WriteScreenField( w,SearchL, SearchX, SearchY,
				SearchWord, BoldAttr, TRUE);

 	    NumberInSelListArray := 0 ;		(* <<-- is this right place ?? *)
            FreePool( PoolNoForSearchWorkingSpace );
	    REPEAT
		PResult := ParseRuleCriteria(TLink,NeedSelect);
		IF PResult = ParseRepeat THEN
                   DisposeProcessData;
		   ShowMenu(w,RuleWindMenu,0,0,RuleWindowData);
		END;
	    UNTIL PResult <> ParseRepeat;
	    Done := PResult = ParseOK;

	    IF Done THEN
                FirstREMsg := TRUE ;
                SearchResult := SearchOK;
                LaunchProcesses;
                DiscardList(ListFromRule);
                GetTACTList(TLink, PoolNoForListFromRule, ListFromRule);
                TACTProcesses.YIELD;
                FreePool( PoolNoForSearchWorkingSpace );

                Something := GetFirstItem(ListFromRule, ListFromRulePos);
                IF (NOT Something) AND (SearchResult < SearchFailed) THEN
                   (*RES OLD MSG 336
                   Your Query did not select anything.
                   *)
                   PutResError( (*RES REM INS*) 336 );
                   Done := FALSE
                ELSE
		   CASE SearchResult OF
		      SearchOK: (* nothing needs be done here *)
	            | SearchWarned:
(*RES OLD CHE 4
Your criteria generated warning messages.  Do you wish to use the
resulting list?  Y)es or N)o:
=YN
*)
                        ResAskUser( (*RES REM INS*) 4 , 'YN', ch1);
                        IF ch1 = 'Y' THEN
                           SearchResult := SearchOK;
                        ELSE
                           Done := FALSE;
                           SearchResult := SearchFailed;
                        END;
                    | SearchFailed, SearchStoppedByUser:
                        Done := FALSE;
		   END; (* CASE SearchResult *)
                 END;
            ELSE
               DisposeProcessData;
	    END; (* IF Done *)
	    FOR i := 1 TO NumberInSelListArray DO
		DiscardList( SelectedListArray[ i ] )
	    END ;
         END; (* WITH WorkingRuleWindData *)
      END; (* IF GetPanelControlKey(FunctKey, ch) <> PanelCancel *)
      WriteScreenField( w,SearchL, SearchX, SearchY, 0C,BoldAttr,TRUE);
   UNTIL Done;

   IF SearchResult = SearchOK THEN
      UpdateLists;
   ELSE
      DisposeListItem(ListFromRule, ListFromRulePos);
      FreePool(PoolNoForListFromRule);
      DiscardList(ListFromRule);
      ChangePoolNo( PoolNoForOldRuleList, PoolNoForListFromRule );
      ListFromRule := OldRuleList;
      ListFromRulePos := OldRuleItem;
   END;
   PopWindow;
   PopHelpItem;
   DestroyMenu(RuleWindMenu);
(* Shrink *)
END DoRuleWindMenu;

PROCEDURE FoldToFitCriteria(VAR input:     ARRAY OF CHAR; (* read-only *)
                            VAR output:    CriteriaType): BOOLEAN; (* True=fit*)
CONST
   MaxLen = CriteriaLen * NumbCriteria;
TYPE
   StrPntr = POINTER TO StrAny;
VAR
   i,j,k,l: CARDINAL;
   p:       StrPntr;
   temp:    CriteriaType;
   ch:      CHAR;

BEGIN
   FOR i := 0 TO NumbCriteria - 1 DO temp[i][0] := 0C END;
   l := Str.Length(input);
   IF l > MaxLen THEN RETURN FALSE END;
   p := ADR(input);
   i := 0;
   WHILE (i <= NumbCriteria -2) AND (l > CriteriaLen-1) DO
      j := CriteriaLen-1;
      WHILE (j > 0) AND (p^[j] <> ' ') AND (p^[j] <> ',') AND (p^[j] <> ';')DO
         DEC(j)
      END;
      IF j = 0 THEN RETURN FALSE END;
      k := j;
      REPEAT INC(j) UNTIL (p^[j] <> ' ');
      WHILE (k > 0) AND (p^[k] = ' ') DO DEC(k) END;
      IF p^[k] <> ' ' THEN
         ch := p^[k+1];
         p^[k+1] := 0C;
         Str.Copy(temp[i],p^);
         p^[k+1] := ch;
      END;
      IF p^[j] = 0C THEN
         output := temp;
         RETURN TRUE
      END;
      p := ADR(p^[j]);
      DEC(l,j);
      INC(i);
   END;
   IF l > CriteriaLen THEN RETURN FALSE END;
   Str.Copy(temp[i],p^);
   output := temp;
   RETURN TRUE;
END FoldToFitCriteria;

PROCEDURE SubstituteInCriteria(VAR criteria:     CriteriaType;
                                   line,pos,len: CARDINAL;
                                   text:         ARRAY OF CHAR): BOOLEAN;
VAR
   hold:   ARRAY[0 .. NumbCriteria*CriteriaLen] OF CHAR;
   i:      CARDINAL;
   hpos:   CARDINAL;
   first:  BOOLEAN;
   temp:   StrAny;
BEGIN
   hold[0] := 0C;
   hpos := 0;
   first := TRUE;
   FOR i := 0 TO NumbCriteria-1 DO
      TrimBlanks(criteria[i],criteria[i]);
      IF criteria[i][0] <> 0C THEN
         IF first THEN first := FALSE
         ELSE SWriteChar(hold,hpos,' ',0) END;
         IF i = line THEN
            Str.Copy(temp,criteria[i]);
            Str.Delete(temp,pos,len);
            Str.Insert(temp,text,pos);
            SWriteString(hold,hpos,temp,0);
         ELSE
            SWriteString(hold,hpos,criteria[i],0);
         END;
      END;
   END;
   RETURN FoldToFitCriteria(hold,criteria);
END SubstituteInCriteria;

END RuleWindow.
