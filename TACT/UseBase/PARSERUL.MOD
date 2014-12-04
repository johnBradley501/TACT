IMPLEMENTATION MODULE ParseRuleSource;

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
IMPORT TWB, Str;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM GlobalDefs IMPORT StrAny;
FROM ScannerSource IMPORT
  (* type *) ItemDataType;
FROM ParserSource IMPORT
  (* procs *) Parser;
FROM HyperBase IMPORT HRecPntr;
FROM Windows IMPORT RegularAttr;
FROM RuleWindow IMPORT RuleWindowData, SubstituteInCriteria, CriteriaTooBig ;
FROM RegularExpr IMPORT
  (* proc *) ParseRegExp;
FROM WhenWork IMPORT
  (* type *) WhenItem,
  (* proc *) DisposeWhenItem, BuildWhenByParsing, DoWhen;
IMPORT RULES;
FROM StackWindows IMPORT WindowType, WindowInfo;
FROM TACTListModule IMPORT
   (* Types *) TACTList, TACTListType, TACTListItem,
   (* Procs *) NewListItem, GetFirstItem, FindFromString, GetItemData,
               ReleaseItemHold, DiscardList, DisposeListItem ;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, InsertListItem;
FROM TypeListModule IMPORT MakeTACTTypeList;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) FreeTypeHandle, FindType;
FROM ListData IMPORT DataItemPntr, ItemType, MarkAsUsed ;
FROM ErrorBase IMPORT ProgramErrorAndHalt ;
FROM SelectWindow IMPORT DoSelectWindow ;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;
FROM ResMessages IMPORT
   (*proc*)  MsgString, PutResError, PutResWarning;
FROM TACTDataServices IMPORT
  (* procs *) AllocTypeData, VirtToTACTList;
FROM DataLinkModule IMPORT
  (* types *) DataLink, DataLinkType, DataLinkPROC, DisposeDataProcType,
  (* procs *) InitLink, InitAndDefineAsList, DisposeLink,
              BuildProcessData, DummyDisposeDataProc, LaunchProcesses,
              DisposeProcessData, SetDataLinkEmpty;
FROM SearchUtils IMPORT
  (* types *) SearchResultType, SimilDataPntr, PhraseBaseArray,
              PhraseDataPntr, PhraseData, BinaryDataPntr,
  (* vars  *) SearchResult, CurrPosOnSelListArray, NumberInSelListArray,
              SelectedListArray,
  (* procs *) MergeDataLinks, DoSpanCollocation, DoPos,
              BuildSimilByParsing, DoSimil, DisposeSimilDataPntr,
              NewPhraseDataPntr, PhraseSearch, DisposePhraseData,
              DisposeBinaryDataPntr, WithInRange, NotWithInRange,
              ListNegateProc;
FROM MainLists IMPORT
  (* Const *) PoolNoForSearchWorkingSpace,
  (* Vars  *) SelectedListEmpty, SelectedList ;
FROM RegularExpr IMPORT
  (* type *) RegExpOpTypePntr, RegExpOpTypeRecord,
  (* proc *) RegExpProc, DisposeRegExpOpTypePntr;
FROM FreqBase IMPORT
  (* types *) FreqItem,
  (* procs *) DisposeFreqItems, BuildFreqByParsing, DoFreq;
FROM Categories IMPORT
   (* const *) NoPDBRes,
   (* Procs *) IsCatNamePresent,
   (* Procs *) DoCatContents, DoCatNameSelectWindow ;
FROM WordBase IMPORT
  (* Procs *) IntToSortWord, FullToSortWord, SortToIntWord;
FROM DBData IMPORT PDBOpen, MainCatList;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMRelease;

(*<Dbg
FROM Trace IMPORT
(*vars *) DoTrace,
(*procs*) TWriteLn,TWriteChar,TWriteString,TWriteInt,TWriteCard,TWriteAddr,
          TWriteStrHex,CloseTFile;
Dbg>*)

VAR
   EditSelectWind:      WindowInfo;

PROCEDURE GetCatNameFromSelect( ItemData : ItemDataType ) : BOOLEAN ;
VAR
   CatDataVA	: VirtAddr;
   CatName	: StrAny ;
BEGIN
   IF DoCatNameSelectWindow( CatDataVA, CatName ) THEN
      IF NOT SubstituteInCriteria(RuleWindowData.Criteria,
      ItemData.WhichLine, ItemData.WhichPos, Str.Length(ItemData.IntStr),
      CatName ) THEN
         PutResError( CriteriaTooBig );
         RETURN FALSE
      ELSE RETURN TRUE END;
   ELSE
      RETURN FALSE
   END ;
END GetCatNameFromSelect ;

PROCEDURE ParseRuleCriteria(VAR ResultLink: DataLink;
                            VAR NeedSelect: BOOLEAN): ParseResult;

CONST
   MaxBarNest = 20 ;
TYPE
   PhraseTypeType = (NoSelector, SelFound, PosFound, SelectorPos, PosSelector);
   SetOfPhraseType = SET OF PhraseTypeType;

   RuleLevelPntr = POINTER TO RuleLevelData;
   RuleLevelData = RECORD
      Next:         RuleLevelPntr;
      LevelList:    TACTList;
      ListInit:     BOOLEAN;
      (* info to handle phrases *)
      PhrStart:     CARDINAL;
      BarCount:     CARDINAL;
      PhrOffset:    INTEGER;
      PhraseType:   PhraseTypeType;
      PhraseHold:   PhraseBaseArray;
      PhrItemCntr:  CARDINAL;
      (* end info to handle phrases *)
      tPat:         ARRAY[0..80] OF CHAR;
      tPatPh1:      ARRAY[0..80] OF CHAR;
      tPatCol:      ARRAY[0..80] OF CHAR;
      typeonly:     BOOLEAN;
      typeonlyPh1:  BOOLEAN;
      typeonlyCol:  BOOLEAN;
      tLinkOut:     DataLink;
(* DataLinkType = (DontCare, DirectLink, ListLink); *)
      tLinkOutPh1:  DataLink;
      tLinkOutCol:  DataLink;
      tLType:       DataLinkType;
      tLTypePh1:    DataLinkType;
      tLTypeCol:    DataLinkType;

      NoDataLs:     CARDINAL;
      DataLinks:    ARRAY[0..40] OF DataLink;
      TypeForPhrase:ARRAY[0..40] OF DataLinkType;
   END;

VAR
   Level:       RuleLevelPntr;
   RuleNo:      CARDINAL;
   ItemData:    ItemDataType;
   OK, OK2:     BOOLEAN;
   tWhenItem:   WhenItem;
   sPntr:       SimilDataPntr;
   FItem:       FreqItem;
   RepeatParse: BOOLEAN;
   RegExpDataPntr: RegExpOpTypePntr;
   tempLink:    DataLink;
   tempLType:   DataLinkType;

PROCEDURE SelectWordListWind( VAR SelectedWordList : TACTList ) : BOOLEAN ;
   VAR
	ch:		CHAR;
	TList:		TACTList;
	DummyList:	TACTList;
	SelectItem:	TACTListItem;
	SelectItem2:	TACTListItem;
	FunctKey:	BOOLEAN;
	BDummy:		BOOLEAN;
	Select:		BOOLEAN;
	SomeThingSelected: BOOLEAN;
   BEGIN
	TList := MakeTACTTypeList();
	NewListItem( TList, SelectItem );
	IF NOT GetFirstItem( TList, SelectItem) THEN
	   ProgramErrorAndHalt( 'Error in ParseRule for SelectWordList.' );
	END ;

	DummyList := NewMemoryList(PoolNoForSearchWorkingSpace);
	REPEAT
	   IF NOT DoSelectWindow( EditSelectWind,
			 TList, DummyList, SelectedWordList, PoolNoForSearchWorkingSpace (* m.s. was 0, PoolNo not used *),
			 SelectItem, ch, FunctKey, BDummy, FALSE) THEN
		DisposeListItem( TList, SelectItem);
		DiscardList( TList ) ;
		DiscardList( DummyList ) ;
		RETURN FALSE
	   END;
	   NewListItem(SelectedWordList,SelectItem2);
	   SomeThingSelected := GetFirstItem(SelectedWordList, SelectItem2 ) ;
	   DisposeListItem( SelectedWordList, SelectItem2 ) ;
	   IF NOT SomeThingSelected THEN
	      (*RES OLD MSG 265
	      You selected nothing. Please use the INSert key to choose
	      one or more words.
	      *)
	      PutResError( (*RES REM INS *) 265 ) ;
	   END ;
	UNTIL SomeThingSelected ;

	(* SelectItem points at item selected. *)
	IF GetPanelControlKey(FunctKey, ch) <> PanelCancel THEN
	   Select := TRUE ;
	ELSE
	   Select := FALSE ;
	END;

	DisposeListItem( TList, SelectItem );
	DiscardList( TList );
	DiscardList( DummyList );
	RETURN Select ;
   END SelectWordListWind ;

PROCEDURE ProcessCatName() : BOOLEAN ;
VAR tList:   TACTList;
    Numb:    CARDINAL;
    SortCatName: StrAny;
    Item:    TACTListItem;
    CVA:     VirtAddr;
    CPntr:   DataItemPntr;
BEGIN
   IntToSortWord( ItemData.IntStr, SortCatName );
   NewListItem(MainCatList, Item);
   IF FindFromString( SortCatName, CatType, MainCatList, Item) THEN
      GetItemData(MainCatList, Item, CVA, CPntr);
      VirtToTACTList(CPntr^.Contents, tList);
      ReleaseItemHold(MainCatList, Item);
      IF NOT (RuleWindowData.IgnoreErrs OR GetFirstItem(tList, Item)) THEN
         (*RES OLD MSG 200
         Group "%0" contains nothing.
         *)
         MsgString( ItemData.IntStr, 0 ) ;
         PutResWarning( (*RES REM INS*) 200 );
         IF SearchResult = SearchOK THEN SearchResult := SearchWarned END;
      END;
      DisposeListItem( tList, Item);
      InitAndDefineAsList(Level^.tLinkOut, tList, TRUE);
      Level^.tLType := ListLink;
      Level^.typeonly := FALSE;
   ELSE
      (*RES OLD MSG 202
      You have not defined Group "%0".  Please select one from the list.
      *)
      MsgString( ItemData.IntStr, 0 ) ;
      PutResWarning( (*RES REM INS *) 202 ) ;
      IF GetCatNameFromSelect( ItemData ) THEN RETURN FALSE  (* force a ParseRepeat *)
      ELSE OK := FALSE END ;
   END ;
   RETURN TRUE ;
END ProcessCatName;

PROCEDURE DoMakeNewLevel;
VAR tLevel:   RuleLevelPntr;
BEGIN
   NEW(tLevel);
   WITH tLevel^ DO
       Next := Level;
       PhrStart := MAX(CARDINAL);
       ListInit := FALSE;
       NoDataLs := 0;
       typeonly := FALSE;
       SetDataLinkEmpty( tLinkOut ) ;	(* *LP* *)
   END;
   Level := tLevel
END DoMakeNewLevel;

PROCEDURE AddItemToLevelList(item:  VirtAddr (* to DataItem *));
VAR dummy: BOOLEAN;
BEGIN
   WITH Level^ DO
      IF NOT ListInit THEN
         ListInit := TRUE;
         LevelList := NewMemoryList( PoolNoForSearchWorkingSpace );
      END;
      dummy := InsertListItem(item,LevelList);
   END;
END AddItemToLevelList;

PROCEDURE BuildFilter(ProcessEntryPoint: DataLinkPROC;
                      DisposeDataProc:   DisposeDataProcType;
                      DataPntr:          ADDRESS);
BEGIN
   WITH Level^ DO
      InitLink(tLinkOut,DontCare);
      BuildProcessData(DataLinks, 1, tLinkOut, ProcessEntryPoint,
                 DisposeDataProc, DataPntr);
      DataLinks[0] := tLinkOut;
(*    tLType := TypeForPhrase[0]; not needed: a filter doesn't change this *)
   END;
END BuildFilter;

PROCEDURE BuildFromTypeList(ProcessEntryPoint: DataLinkPROC;
                            DisposeDataProc:   DisposeDataProcType;
                            DataPntr:          ADDRESS);
VAR tList:     TACTList;
    tLinkIn:   ARRAY [0..0] OF DataLink;
BEGIN
   tList := MakeTACTTypeList();
   InitAndDefineAsList(tLinkIn[0], tList, TRUE);
   InitLink(Level^.tLinkOut,DontCare);
   BuildProcessData(tLinkIn, 1, Level^.tLinkOut, ProcessEntryPoint,
                 DisposeDataProc, DataPntr);
   Level^.tLType := ListLink;
END BuildFromTypeList;

PROCEDURE GetTypeItem(AlpWord:   ARRAY OF CHAR;
                  VAR Data:      VirtAddr (* to DataItem *)): BOOLEAN;
VAR
    SortWord:    StrAny;
    H:           HTypeHandle;
    NewPos:      HRecPntr;
    Pntr:        DataItemPntr;
BEGIN
   Data := NILVirt;
   FullToSortWord(AlpWord,SortWord);
   IF NOT FindType(SortWord,NewPos,H) THEN
       IF RuleWindowData.IgnoreErrs THEN
          Data := NILVirt;
          RETURN TRUE;
       ELSE
          (*RES OLD MSG 165
          "%0" is not in the Word-list.
          *)
          SortToIntWord(SortWord, AlpWord);
          MsgString(AlpWord,0);
          PutResWarning( (*RES REM INS*) 165 );
          IF SearchResult = SearchOK THEN SearchResult := SearchWarned END;
          RETURN FALSE
       END;
   END;
   AllocTypeData(H,NewPos, PoolNoForSearchWorkingSpace, Data, Pntr);
(* MarkAsUsed(Pntr); *)
   VMRelease(Data);
   FreeTypeHandle(H);
   RETURN TRUE;
END GetTypeItem;

PROCEDURE TypeToLevelList(AlpWord:     ARRAY OF CHAR): BOOLEAN;
VAR
   dummy:       BOOLEAN;
   Data:        VirtAddr (* to DataItem *);
BEGIN
   IF NOT GetTypeItem(AlpWord, Data) THEN RETURN FALSE END;
   IF Data <> NILVirt THEN AddItemToLevelList(Data) END;
(* DisposeTypeData(Data); *)
   RETURN TRUE;
END TypeToLevelList;

PROCEDURE CombineLevel(VAR link: DataLink;VAR LType: DataLinkType);
VAR i:  CARDINAL;
BEGIN
   WITH Level^ DO
      IF NoDataLs = 0 THEN
         IF NOT ListInit THEN
            IF RuleWindowData.IgnoreErrs THEN
               LevelList := NewMemoryList( PoolNoForSearchWorkingSpace )
            ELSE ProgramErrorAndHalt('No List data in Level') END;
         END;
         InitAndDefineAsList(link, LevelList, TRUE);
         LType := ListLink;
         RETURN
        
      ELSE
         IF ListInit THEN
            InitAndDefineAsList(DataLinks[NoDataLs], LevelList, TRUE);
            INC(NoDataLs);
         END;
         IF NoDataLs > 1 THEN
            InitLink(link,DontCare);
            BuildProcessData(DataLinks, NoDataLs, link, MergeDataLinks,
                           DummyDisposeDataProc, NIL);
         ELSE
            link := DataLinks[0];
         END;
      END;
      LType := ListLink;
      FOR i := 0 TO NoDataLs - 1 DO
         IF TypeForPhrase[i] = ListLink THEN RETURN END;
      END;
      LType := DirectLink;
   END;
END CombineLevel;

PROCEDURE LevelToLink(VAR link: DataLink;VAR LType: DataLinkType);
VAR tLevel:  RuleLevelPntr;
BEGIN
   CombineLevel(link,LType);
   tLevel := Level;
   Level := Level^.Next;
   DISPOSE(tLevel);
END LevelToLink;

PROCEDURE CleanUpLevelData;
VAR tLevel:  RuleLevelPntr;
    i:       CARDINAL;
BEGIN
   tLevel := Level;
   WHILE tLevel <> NIL DO
      WITH tLevel^ DO
         IF ListInit THEN DiscardList(LevelList) END;
(*	 DisposeLink( tLinkOut ) ;	(* an empty/NIL link is ok *LP* *) *)
(*	 >>> this should have worked but doesn't!! JB to think thru on how to
	     release the memory pointers for the copied tLinkOut DataLink
	     Test: F2 gold.*; ? ? ENTER CursorDn ENTER
	     causes DEALLOCATE to Lib.FatalError with "invalid pointer"
	     DisposeLink is only needed for F2 rules that fail and
	     there is a cleanup						*)
(*       FOR i := 1 TO NoDataLs DO DisposeLink(DataLinks[i-1]) END; *)
      END;
      tLevel := tLevel^.Next;
      DISPOSE(Level);
      Level := tLevel;
   END;
END CleanUpLevelData;

PROCEDURE SingleTypeToDataLink(AlpWord:   ARRAY OF CHAR;
                           VAR Rslt: DataLink): BOOLEAN;
VAR tList:  TACTList;
    dummy:  BOOLEAN;
    Data:   VirtAddr (* to DataItem *);
BEGIN
   IF NOT GetTypeItem(AlpWord, Data) THEN RETURN FALSE END;
   tList := NewMemoryList( PoolNoForSearchWorkingSpace );
   IF Data <> NILVirt THEN dummy := InsertListItem(Data,tList) END;
(* DisposeTypeData(Data); *)
   InitAndDefineAsList(Rslt, tList,TRUE);
   RETURN TRUE
END SingleTypeToDataLink;

PROCEDURE BuildPhraseSelection;
VAR pntr:   PhraseDataPntr;
    dlptr:  POINTER TO ARRAY[0..40] OF DataLink;
BEGIN
   WITH Level^ DO
     pntr := NewPhraseDataPntr(PhrItemCntr, PhraseHold);
     pntr^.OutOffset := PhrOffset;

     InitLink(tLinkOut,DontCare);
     dlptr := ADR(DataLinks[PhrStart]);
     BuildProcessData(dlptr^, PhrItemCntr, tLinkOut, PhraseSearch,
                      DisposePhraseData, pntr);
     NoDataLs := PhrStart;
     tLType := DirectLink;
     typeonly := FALSE;
   END;
END BuildPhraseSelection;

PROCEDURE BuildBinaryOperation(TheProc: DataLinkPROC): BOOLEAN;
VAR bd:   BinaryDataPntr;
    dl:   ARRAY[0..1] OF DataLink;
BEGIN
   WITH Level^ DO
      IF typeonlyCol THEN
         IF NOT SingleTypeToDataLink(tPatCol, tLinkOutCol) THEN RETURN FALSE END;
      END;
      IF typeonly THEN
         IF NOT SingleTypeToDataLink(tPat, tLinkOut) THEN RETURN FALSE END;
      END;
      NEW(bd);
      bd^[0] := tLTypeCol;
      bd^[1] := tLType;
      dl[0] := tLinkOutCol;
      dl[1] := tLinkOut;
      InitLink(tLinkOut,DontCare);
      BuildProcessData(dl, 2, tLinkOut, TheProc,
                      DisposeBinaryDataPntr, bd);
      typeonlyCol := FALSE;
      typeonly := FALSE;
      tLinkOutCol := tLinkOut;
      tLType := DirectLink;
      tLTypeCol := DirectLink;
      RETURN TRUE;
   END;
END BuildBinaryOperation;

PROCEDURE BuildListNegate(): BOOLEAN;
VAR dl:   ARRAY[0..1] OF DataLink;
BEGIN
   WITH Level^ DO
      IF typeonlyCol THEN
         IF NOT SingleTypeToDataLink(tPatCol, tLinkOutCol) THEN RETURN FALSE END;
      END;
      IF typeonly THEN
         IF NOT SingleTypeToDataLink(tPat, tLinkOut) THEN RETURN FALSE END;
      END;
      dl[0] := tLinkOutCol;
      dl[1] := tLinkOut;
      InitLink(tLinkOut,DontCare);
      BuildProcessData(dl, 2, tLinkOut, ListNegateProc,
                      DummyDisposeDataProc, NIL);
      typeonlyCol := FALSE;
      typeonly := FALSE;
      tLinkOutCol := tLinkOut;
      tLType := ListLink;
      RETURN TRUE
   END;
END BuildListNegate;

BEGIN
   NeedSelect := FALSE;
   Level := NIL;
   DoMakeNewLevel;
   CurrPosOnSelListArray := 0 ;
   RuleNo := Parser(TRUE, ItemData);
   OK := TRUE;

   REPEAT
      RuleNo := Parser(FALSE,ItemData);
(*<Dbg
      TWriteString('ParseRuleCriteria:Rule:');
      TWriteCard(RuleNo,7);
      TWriteString(',Item:');
      TWriteString(ItemData.IntStr);
      TWriteLn;
Dbg>*)
      CASE RuleNo OF
         RULES.FirstSelect, RULES.SubsequentSelect:
           WITH Level^ DO
              IF typeonly THEN
                 OK := TypeToLevelList(tPat);
                 typeonly := FALSE;
              ELSE
                DataLinks[NoDataLs] := tLinkOut;
                TypeForPhrase[NoDataLs] := tLType;
                INC(NoDataLs);
              END;
           END;
       | RULES.FirstTermOfBinary:
           WITH Level^ DO
              typeonlyCol := typeonly;
              tLTypeCol := tLType;
              IF typeonlyCol THEN Str.Copy(tPatCol,tPat)
              ELSE tLinkOutCol := tLinkOut END;
           END;
       | RULES.WithInRange:
           OK := BuildBinaryOperation(WithInRange);
       | RULES.NotWithInRange:
           OK := BuildBinaryOperation(NotWithInRange);
       | RULES.DoListNegate:
           OK := BuildListNegate();
       | RULES.OpenBracket:
           DoMakeNewLevel;
       | RULES.CloseBracket:
           LevelToLink(tempLink,tempLType);
           Level^.tLinkOut := tempLink;
           Level^.tLType := tempLType;
           Level^.typeonly := FALSE;
       | RULES.DoPhraseStart:
           WITH Level^ DO
              PhrItemCntr := 0;
	      BarCount := 0 ;
              PhrOffset := 0;
              PhraseType := NoSelector;
           END;
       | RULES.FinishUpPhrase:
           WITH Level^ DO
              IF PhraseType = PosFound THEN PhrOffset := 0 END;
              IF PhrStart < MAX(CARDINAL) THEN 
                 IF PhrItemCntr = 0 THEN
                    PhrStart := NoDataLs;
                    IF typeonlyPh1 THEN OK := SingleTypeToDataLink(tPatPh1, tLinkOutPh1) END;
                    DataLinks[NoDataLs] := tLinkOutPh1;
                    TypeForPhrase[NoDataLs] := tLTypePh1;
                    INC(NoDataLs);
                    PhrItemCntr := 1;
                 END;
                 BuildPhraseSelection
              END;
              PhrStart := MAX(CARDINAL);
           END;
       | RULES.FirstPhraseWord:
           WITH Level^ DO
              PhraseHold[0].Offset := 0;
              PhraseHold[0].Access := tLType;
              BarCount := 0 ;
              CASE PhraseType OF
                NoSelector:
                  PhraseType := PosFound;
                  PhrOffset := 0;
              | SelFound:
                  PhraseType := SelectorPos
              ELSE (* do nothing *)
              END;

              IF PhrStart = MAX(CARDINAL) THEN
                 typeonlyPh1 := typeonly;
                 tLTypePh1 := tLType;
                 IF typeonlyPh1 THEN Str.Copy(tPatPh1,tPat)
                 ELSE tLinkOutPh1 := tLinkOut END;
              ELSE
                 IF typeonly THEN 
                    OK := SingleTypeToDataLink(tPat, tLinkOut);
                    tLType := ListLink;
                 END;
                 DataLinks[NoDataLs] := tLinkOut;
                 TypeForPhrase[NoDataLs] := tLType;
                 typeonly := FALSE;
                 INC(NoDataLs);
                 PhrItemCntr := 1;
              END;
           END;

       | RULES.ImmediateFollowed, RULES.ImmediateFollowed2:
           WITH Level^ DO
(*            IF PhrStart = MAX(CARDINAL) THEN *)
              IF PhrItemCntr = 0 THEN
                 PhrStart := NoDataLs;
                 IF typeonlyPh1 THEN OK := SingleTypeToDataLink(tPatPh1, tLinkOutPh1) END;
                 DataLinks[NoDataLs] := tLinkOutPh1;
                 TypeForPhrase[NoDataLs] := tLTypePh1;
                 INC(NoDataLs);
                 PhrItemCntr := 1;
              END;

              PhraseHold[PhrItemCntr].Offset := BarCount;
              PhraseHold[PhrItemCntr].Access := tLType;
              INC(PhrItemCntr);
              IF typeonly THEN OK2 := SingleTypeToDataLink(tPat, tLinkOut)
              ELSE  OK2 := TRUE  END;
              DataLinks[NoDataLs] := tLinkOut;
              TypeForPhrase[NoDataLs] := tLType;
              typeonly := FALSE;
              INC(NoDataLs);
           END;
           OK := OK AND OK2 ;

       | RULES.CountBar, RULES.CountBar2:
           WITH Level^ DO
              IF PhrStart = MAX(CARDINAL) THEN PhrStart := NoDataLs END;
              INC( BarCount ) ;
              CASE PhraseType OF
                PosFound:
                   INC(PhrOffset);
              | SelFound:
                   DEC(PhrOffset);
              ELSE (* ignore *)
              END;
           END;
       | RULES.HandleSelector:
           WITH Level^ DO
(*            IF PhrStart = MAX(CARDINAL) THEN
                 PhrStart := NoDataLs;
                 IF typeonlyPh1 THEN OK := SingleTypeToDataLink(tPatPh1, tLinkOutPh1) END;
                 DataLinks[NoDataLs] := tLinkOutPh1;
                 TypeForPhrase[NoDataLs] := tLTypePh1;
                 INC(NoDataLs);
              END;
*)
              CASE PhraseType OF
                NoSelector:  PhraseType := SelFound
              | PosFound:    PhraseType := PosSelector
              ELSE
                (*RES OLD MSG 305
                The Selector Character ">" occurred twice within a single phrase.
                *)
                PutResError( (*RES REM INS*) 305 );
                RETURN ParseFailed
              END;
           END;

       | RULES.StartRefinements:
           WITH Level^ DO
              CombineLevel(tLinkOut,tLType);
              ListInit := FALSE;
              NoDataLs := 1;
              DataLinks[0] := tLinkOut;
              TypeForPhrase[0] := tLType;
           END;

       | RULES.DoUseCurrentSelectList:
           IF SelectedListEmpty THEN
              OK := FALSE;
              (*RES OLD MSG 335
              Your Query (using "@") failed because there is no Group of that name.
              *)
              PutResError( (*RES REM INS*) 335 );
           ELSE
              NeedSelect := TRUE;
              InitAndDefineAsList(Level^.tLinkOut, SelectedList, FALSE);
              Level^.tLType := ListLink;
           END;

       | RULES.DoStartRegExp:
           WITH Level^ DO
              OK := ParseRegExp(RuleNo,ItemData,tPat,typeonly);
              IF NOT typeonly THEN
                 NEW(RegExpDataPntr);
                 WITH RegExpDataPntr^ DO
                   HandleInputAsList := TRUE;
                   Str.Copy(Pat, tPat);
                 END;
              END;
           END;
       | RULES.AddRegExpToAgenda:
           IF NOT Level^.typeonly THEN
              BuildFromTypeList(RegExpProc,DisposeRegExpOpTypePntr, RegExpDataPntr);
           END;
           Level^.tLType := ListLink;
       | RULES.AddRegExpToAgenda2:
           WITH Level^ DO
              IF typeonly THEN
                 typeonly := FALSE;
                 OK := FALSE;
                 (*RES OLD MSG 196
                 Please specify a Regular Expression after "REGEXP".
                 *)
                 PutResWarning( (*RES REM INS*) 196 );
              ELSE
                 RegExpDataPntr^.HandleInputAsList := FALSE;
                 BuildFilter(RegExpProc, DisposeRegExpOpTypePntr, RegExpDataPntr);
              END;
           END;
       | RULES.FirstWhenRule..RULES.LastWhenRule:
           OK := BuildWhenByParsing(RuleNo, ItemData, tWhenItem,RepeatParse);
           IF RepeatParse THEN
              CleanUpLevelData;
              RETURN ParseRepeat
           END;
           IF OK THEN
              BuildFilter(DoWhen, DisposeWhenItem, ADDRESS(tWhenItem));
           END;

       | RULES.MakeIntoPosList:
           BuildFilter(DoPos, DummyDisposeDataProc, NIL);
           Level^.tLType := DirectLink;

       | RULES.FreqStart:
           OK := BuildFreqByParsing(RuleNo, FItem);
       | RULES.DoFreqAsBasicSelection:
           BuildFromTypeList(DoFreq, DisposeFreqItems, ADDRESS(FItem));
       | RULES.DoFreqSelectAsPipe:
           BuildFilter(DoFreq, DisposeFreqItems, ADDRESS(FItem));

       | RULES.SimilStart:
           OK := BuildSimilByParsing(RuleNo, sPntr);
       | RULES.DoSimilAsBasicSelection:
           BuildFromTypeList(DoSimil, DisposeSimilDataPntr, sPntr);
       | RULES.DoSimilSelectAsPipe:
           BuildFilter(DoSimil, DisposeSimilDataPntr, sPntr);

(*     | RULES.SpanStart: *)
       | RULES.DoSpanSelectAsPipe:
           BuildFilter(DoSpanCollocation, DummyDisposeDataProc, NIL);

       | RULES.DoAddType:
           Str.Copy(Level^.tPat, ItemData.AlpStr);
           Level^.typeonly := TRUE;
           Level^.tLType := ListLink;
       | RULES.DoWordListSelectWindow:
	   INC( CurrPosOnSelListArray ) ;
	   IF CurrPosOnSelListArray > NumberInSelListArray THEN
		INC( NumberInSelListArray ) ;
(*		SelectedListArray[NumberInSelListArray] :=
                                 NewMemoryList(PoolNoForSearchWorkingSpace);  *LP* *)
		OK := SelectWordListWind( SelectedListArray[NumberInSelListArray] ) ;
	   END ;
           IF OK THEN
             InitAndDefineAsList(Level^.tLinkOut,
                 SelectedListArray[NumberInSelListArray], FALSE);
	   ELSIF CurrPosOnSelListArray > NumberInSelListArray THEN
		DEC( NumberInSelListArray ) ;
	   END ;
           Level^.tLType := ListLink;

       | RULES.DoAddCatName, RULES.DoAddCatContents:
           IF NOT PDBOpen THEN
                PutResError(NoPDBRes);
                CleanUpLevelData;
                RETURN ParseFailed
           ELSIF NOT ProcessCatName() THEN
                CleanUpLevelData;
		RETURN ParseRepeat
	   END ;
       | RULES.DoGetCatNameFromSelect1, RULES.DoGetCatNameFromSelect2:
           IF NOT PDBOpen THEN
                PutResError(NoPDBRes);
                CleanUpLevelData;
                RETURN ParseFailed
           ELSIF GetCatNameFromSelect( ItemData ) THEN
              CleanUpLevelData;
	      RETURN ParseRepeat
	   ELSE
	      OK := FALSE
	   END ;

      ELSE
         (* ignore Parsing Rule *)
      END;
   UNTIL (NOT OK) OR (RuleNo = 1) OR (RuleNo > 999);
(*<Dbg
(*   IF DoTrace THEN *)
      TWriteString('ParseRuleCriteria: Done Parsing; AgendaListing: ');
      TWriteLn;
      AP := TheAgenda;
      WHILE AP <> NIL DO
         TPrintAgndaOp(AP);
         TWriteLn;
         AP := AP^.Next;
      END;
(*   END; *)
Dbg>*)
   IF OK AND (RuleNo = 1) THEN 
      LevelToLink(ResultLink,tempLType);
      RETURN ParseOK
   ELSE
      CleanUpLevelData;
      RETURN ParseFailed END;
END ParseRuleCriteria;

PROCEDURE InitParseRule;
BEGIN
   (* this should really be in a separate mod and accessed by TACTBase & and this *)
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
END InitParseRule;
END ParseRuleSource.
