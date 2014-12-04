IMPLEMENTATION MODULE Categories ;

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

IMPORT TWB, Str ;
FROM SYSTEM IMPORT ADDRESS;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;
FROM GlobalDefs IMPORT StrAny;
FROM ResMessages IMPORT
  (* proc *) MsgString, PutResError, PutResWarning;
FROM SelectWindow IMPORT
  (* proc *) DoSelectWindow;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CharField, CharFieldProc,
                 MakeMenu, DestroyMenu, ShowFixedText, ShowMenu, DoMenu;
FROM MainLists IMPORT
  (* vars *) SelectedListEmpty;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM WordBase IMPORT
  (* Procs *) IntToSortWord, SortToIntWord, IntToSingleSortWord;
FROM TACTInit IMPORT
 (* vars  *) ExitList,TermList;
FROM ListData IMPORT ItemType, DataItemPntr, MarkAsUsed, MakeCatDataItem ;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, GetFirstItem, FindFromString,
              DiscardList, GetItemData, GetListType, ReleaseItemHold;
FROM MemTACTList IMPORT NewMemoryList, CopyList, InsertListItem,
              DeleteListItem;
FROM TACTDataServices IMPORT
              VirtToTACTList, TACTListToVirt, InsertDataItemContentsInList;
FROM ScannerSource IMPORT
  (* Type  *) ItemDataType ;
FROM DBData IMPORT PDBOpen, MainCatList, GetNewPoolNumber, ReleasePoolNo;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) VMAccess, VMModify, VMRelease, VirtToPool, FreePool, WriteAllVirts;
FROM MainLists IMPORT SelectedList;

(*<Dbg
FROM Trace IMPORT
(*vars *) DoTrace,
(*procs*) TWriteString, TWriteLn;
Dbg>*)

(*RES OLD MNU 23
                Name of Group to Make

  Name: %0___________________________________________
*)
CONST
    CreateCatNameRes = (*RES REM INS*) 23 ;

VAR
   CatWindInfo,
   CatNameSelectWind	: WindowInfo;


PROCEDURE DoCatNameSelectWindow( VAR CatDataVA   : VirtAddr (* to DataItem *);
				 VAR CatName	 : ARRAY OF CHAR ) : BOOLEAN;
VAR
   ch:		CHAR;
   DummyList:	TACTList;
   DummyList2:	TACTList;
   SelectItem:	TACTListItem;
   DataItem:	DataItemPntr;
   FunctKey:	BOOLEAN;
   BDummy:	BOOLEAN;
   Select:	BOOLEAN;
BEGIN
   CatDataVA := NILVirt;
   CatName[0]  := 0C ;

   NewListItem(MainCatList, SelectItem);
   IF NOT GetFirstItem(MainCatList, SelectItem) THEN
	(*RES OLD MSG 191
	You have defined no Groups.
	*)
	PutResWarning( (*RES REM INS*) 191 ) ;
	DisposeListItem(MainCatList, SelectItem);
	RETURN FALSE
   END ;

   IF NOT DoSelectWindow(CatNameSelectWind,
	 MainCatList, DummyList, DummyList2, 0 (* PoolNo not used *), SelectItem,
	 ch, FunctKey,BDummy,(* OneSelect = *) TRUE) THEN
	DisposeListItem(MainCatList, SelectItem);
	RETURN FALSE
   END;

   (* SelectItem points at item selected. *)

   IF GetPanelControlKey(FunctKey, ch) <> PanelCancel THEN
      GetItemData(MainCatList, SelectItem, CatDataVA, DataItem);
      SortToIntWord(DataItem^.CatName, CatName);
      MarkAsUsed( DataItem ) ;
      Select := TRUE ;
      ReleaseItemHold(MainCatList, SelectItem);
   ELSE
	Select	    := FALSE ;
   END;
   DisposeListItem(MainCatList, SelectItem);
   RETURN Select ;
END DoCatNameSelectWindow;

PROCEDURE VerifyCatName(    Data:      ADDRESS;
			VAR ReDisplay: BOOLEAN;
			VAR ReEdit:    BOOLEAN ) ;
    TYPE
	RWDP = POINTER TO CatWindowDataType ;
    VAR
	RWD	: RWDP ;
	T	: ARRAY[0..39] OF CHAR;
	i	: CARDINAL;
	ch	: CHAR;
	Empty	: BOOLEAN;
	CatDataVA: VirtAddr;
	Item	: TACTListItem;
    BEGIN
	RWD := RWDP(Data);
	ReDisplay := FALSE;
	ReEdit := FALSE;
	WITH RWD^ DO
	   Empty := TRUE;
	   i := 0;
	   WHILE (Empty) AND (i <= HIGH(CatName)) AND (CatName[i] <> 0C) DO
	      Empty := CatName[i] = ' ';
	      INC(i);
	   END;
	   IF NOT Empty THEN  DEC(i)  END ;

	   IF Empty OR (Str.Pos(CatName,'?') <= HIGH(CatName)) THEN
	      ReDisplay := DoCatNameSelectWindow( CatDataVA, CatName );
	      ReEdit := TRUE;
	      RETURN
	   END;
	   IF (CatName[i] >='0') AND (CatName[i] <= '9') THEN
	      (*RES OLD MSG 334
	      Please start your Group Name "%0" with a letter, not a digit.
	      *)
	      MsgString( CatName, 0 ) ;
	      PutResWarning( (*RES REM INS*) 334 ) ;
	      ReDisplay := TRUE ;
	      ReEdit := TRUE;
	      RETURN
	   END ;
	   IF NOT IntToSingleSortWord(CatName,T,ch) THEN
	      (*RES OLD MSG 369
	      Please use Alphabetic Characters only in creating Group Names.
	      Your Group Name "%0" has the non-Alphabetic Character "%1".
	      *)
	      MsgString( CatName, 0 ) ;
	      MsgString( ch, 0 ) ;
	      PutResError( (*RES REM INS*) 369) ;
	      ReDisplay := TRUE ;
	      ReEdit := TRUE;
	      RETURN
	   END;
(*	   IntToSortWord(CatName,T);  above replaces this j.b. *)
           NewListItem(MainCatList, Item);
	   IF FindFromString( T, CatType, MainCatList, Item ) THEN
	      (*RES OLD MSG 192
	      You have already defined Group "%0". Please enter a new Group Name.
	      *)
	      MsgString( CatName, 0 ) ;
	      PutResWarning( (*RES REM INS*) 192 ) ;
	      ReDisplay := TRUE ;
	      ReEdit := TRUE;
	   END ;
	DisposeListItem(MainCatList, Item);
	END;
    END VerifyCatName;

PROCEDURE DoCatWindMenu( VAR ch		: CHAR ;
                         VAR FunctKey	: BOOLEAN ) ;
    VAR
	w	: TWB.WinType;
	L	: CARDINAL;
	CatWindMenu : MenuID;
    BEGIN
	PushNewWindow( CatWindInfo, w, DummyInit);

(*	CatWindowData.CatName := ''; *)

	StartMenu(CatWindowData);
	WITH CatWindowData DO
	   CharFieldProc( CatName, VerifyCatName ) ;
	END;
	MakeMenu( CreateCatNameRes, CatWindMenu);
	ShowFixedText(w, CatWindMenu, 0,0);

	L := 0;
	ShowMenu(w, CatWindMenu, 0,0, CatWindowData);
	DoMenu( w, CatWindMenu, 0,0, TermList, ExitList,
			 CatWindowData, L, ch, FunctKey );

	DestroyMenu(CatWindMenu);
	PopWindow;
    END DoCatWindMenu;

PROCEDURE DoCatNameCreate ;
VAR
   ch		: CHAR ;
   FunctKey	: BOOLEAN ;
   dummy	: BOOLEAN ;

PROCEDURE DoRealAdd;
VAR
   NewPoolNo:    CARDINAL;
   TList:        TACTList;
   TStr:         ARRAY [0..80] OF CHAR;
   CatDVA:       VirtAddr;
   CatItemPntr:  DataItemPntr;
   dummy:        BOOLEAN;
BEGIN
   NewPoolNo := GetNewPoolNumber();
   TList := NewMemoryList(NewPoolNo);
   CopyList(SelectedList, TList);
   IntToSortWord( CatWindowData.CatName, TStr ) ;
   MakeCatDataItem(TStr, 0, CatDVA, CatItemPntr);
   dummy := InsertListItem(CatDVA, MainCatList);
   TACTListToVirt(TList, NewPoolNo, CatItemPntr^.Contents);
   DiscardList(TList);
   VMRelease(CatDVA);
   WriteAllVirts();
END DoRealAdd;

BEGIN
   IF NOT PDBOpen THEN
      PutResWarning(NoPDBRes);
      RETURN
   END;
   IF SelectedListEmpty THEN
      (*RES OLD MSG 198
      You must select a Word-list before Creating a Group.
      *)
      PutResError( (*RES REM INS *) 198 ) ;
      RETURN ;
   END ;
   DoCatWindMenu( ch, FunctKey ) ;
   IF GetPanelControlKey(FunctKey, ch) <> PanelCancel THEN DoRealAdd END;
END DoCatNameCreate ;

PROCEDURE DoCatNameDelete ;
VAR
   CatDataVA	: VirtAddr; (* TO DataItem *)
   CatName	: StrAny ;
   CatDataPntr	: DataItemPntr;
   OldPoolNo	: CARDINAL;
BEGIN
   IF DoCatNameSelectWindow( CatDataVA, CatName ) THEN
      CatDataPntr := VMModify(CatDataVA);
      OldPoolNo := VirtToPool(CatDataPntr^.Contents);
      FreePool(OldPoolNo);
      ReleasePoolNo(OldPoolNo);
      CatDataPntr^.Contents := NILVirt;
      VMRelease(CatDataVA);
      DeleteListItem(CatDataVA, MainCatList);
      WriteAllVirts() ;
   END ;
END DoCatNameDelete ;

PROCEDURE DoCatNameModify ;

VAR
   CatDataVA	: VirtAddr; (* To Cat-type DataItem *)
   CatName	: StrAny ;

PROCEDURE DoRealModify;
VAR
   CatPoolNo:    CARDINAL;
   TList:        TACTList;
   TStr:         ARRAY [0..80] OF CHAR;
   CatItemPntr:  DataItemPntr;
BEGIN
   CatItemPntr := VMModify(CatDataVA);
   CatPoolNo := VirtToPool(CatItemPntr^.Contents);
   FreePool(CatPoolNo);
   TList := NewMemoryList(CatPoolNo);
   CopyList(SelectedList, TList);
   TACTListToVirt(TList, CatPoolNo, CatItemPntr^.Contents);
   DiscardList(TList);
   VMRelease(CatDataVA);
   WriteAllVirts() ;
END DoRealModify;

BEGIN
   IF SelectedListEmpty THEN
      (*RES OLD MSG 199
      You must select a Word-list before Modifying a Group.
      *)
      PutResError( (*RES REM INS *) 199 ) ;
      RETURN ;
   END ;
   IF DoCatNameSelectWindow( CatDataVA, CatName ) THEN DoRealModify END;
END DoCatNameModify ;

PROCEDURE DoCatNameDisplay ;
VAR
   CatDataVA	: VirtAddr;
   CatName	: StrAny ;
   dummy	: BOOLEAN;
BEGIN
   dummy := DoCatNameSelectWindow( CatDataVA, CatName );
END DoCatNameDisplay ;

PROCEDURE IsCatNamePresent(CatName :     ARRAY OF CHAR;
                       VAR SortCatName : ARRAY OF CHAR) : BOOLEAN ;
VAR
   CatDataItem	: TACTListItem;
   rslt		: BOOLEAN;
BEGIN
   IntToSortWord( CatName, SortCatName ) ;
   NewListItem(MainCatList, CatDataItem);
   rslt := FindFromString(SortCatName, CatType, MainCatList, CatDataItem);
   DisposeListItem(MainCatList, CatDataItem);
   RETURN rslt;
END IsCatNamePresent ;

PROCEDURE DoCatListDisplay ;
VAR
   CatDataVA	: VirtAddr; (* to DataItem *)
   CatName	: StrAny ;
   TList	: TACTList;

PROCEDURE DoCatListSelectWindow( CatDataVA : VirtAddr );
VAR
   ch:		CHAR;
   DummyList:	TACTList;
   DummyList2:	TACTList;
   SelectItem:	TACTListItem;
   FunctKey:	BOOLEAN;
   BDummy:	BOOLEAN;
   DummyNumb:	CARDINAL ;
   CatDataPntr: DataItemPntr;
BEGIN
   CatDataPntr := VMAccess(CatDataVA);
   VirtToTACTList(CatDataPntr^.Contents, TList);
   VMRelease(CatDataVA);
   NewListItem(TList, SelectItem);

   IF NOT GetFirstItem(TList, SelectItem) THEN
	(*RES OLD MSG 355
	Group %0 is empty.
	*)
	MsgString(CatName, 0);
	PutResWarning( (*RES REM INS*) 355 ) ;
   ELSE
	BDummy := DoSelectWindow( CatNameSelectWind, TList, DummyList, DummyList2,
   		0 (* PoolNo not used *), SelectItem, ch, FunctKey,BDummy,TRUE) ;
   END ;

   DisposeListItem( TList, SelectItem);
   DiscardList( TList);
END DoCatListSelectWindow;

BEGIN
   IF DoCatNameSelectWindow( CatDataVA, CatName ) THEN
      DoCatListSelectWindow( CatDataVA ) ;
   END ;
END DoCatListDisplay ;

PROCEDURE DoCatContents( VAR CurrentList : TACTList; VAR Numb : CARDINAL ;
			     CatName : ARRAY OF CHAR (* Sort Form *) ) ;
VAR
   CatDataItem:	TACTListItem;
   DVA:         VirtAddr;
   CatDataPntr: DataItemPntr;
   TList:       TACTList;
BEGIN
   NewListItem(MainCatList, CatDataItem);
   IF NOT FindFromString(CatName, CatType, MainCatList, CatDataItem) THEN RETURN END ;
   GetItemData(MainCatList, CatDataItem, DVA, CatDataPntr);
   ReleaseItemHold(MainCatList, CatDataItem);
   DisposeListItem(MainCatList, CatDataItem);
   InsertDataItemContentsInList(DVA, CurrentList);
END DoCatContents ;


BEGIN
    CatWindowData.CatName := '';
    WITH CatNameSelectWind DO
	XPos :=  24;
	YPos :=   4;
	XSize := 55;
	YSize := 10;
	MxYSize := 10;
	Type := Dialog;
	AllowMove := TRUE;
	AllowResize := TRUE;
    END;

    WITH CatWindInfo DO
	XPos :=  13;
	YPos :=   4;
	XSize := 55;
	YSize :=  5;
	MxYSize := 10;
	Type := Dialog;
	AllowMove := TRUE;
	AllowResize := TRUE;
    END;

END Categories .
