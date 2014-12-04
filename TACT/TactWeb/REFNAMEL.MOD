IMPLEMENTATION MODULE RefNameListModule;
(* copyright (c) 1989-96 John Bradley, Lidio Presutti, University of Toronto *)

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
Date: ????, 1988
By: J.Bradley

Updated:
   Aug. 9, 1988 - L.Presutti
	Replaced "UNTIL (i >= NumbOfRefNames)" with "UNTIL (i > NumbOfRefNames)"
	in MoveDnRefNme.  It generated one too many names for names list.
*)
FROM SYSTEM IMPORT ADR;
FROM MemoryManagement IMPORT ALLOCATE;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames,
   (* procs *) LookupRefName;
FROM TACTDataServices IMPORT
  (* procs *) DisposeDataItem;
FROM MainLists IMPORT PoolNoForTDBTACTLists;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM HyperBase IMPORT HRecPntr;
FROM ListData IMPORT
  (* types *) DataItemPntr, ItemType,
  (* procs *) MakeRefNameItem, MarkAsUsed, DuplicateDataItem;
FROM TACTListModule IMPORT
   TACTListType, TACTList, TACTListData, TACTListItem, TACTListBaseData,
   GenericDisposeListItem, GenericDisposeList, GenericGetItemData,
   GenericReleaseItemHold, GenericNewListItem, GenericCopyListItem;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) VMAccess, VMModify, VMRelease, VMMarkChanged, RealToPool;

PROCEDURE CheckForGoodPointer(A:   DataItemPntr);
BEGIN
    IF A = NIL THEN
       ProgramErrorAndHalt('Illegal NIL Found')
    END;
    IF A^.DataType <> RefNameType THEN
       ProgramErrorAndHalt('NonRefNameType Found')
    END;
END CheckForGoodPointer;

PROCEDURE ReassignRefNameItem(Val:  CARDINAL;
                              Ptr:  DataItemPntr;
                          VAR Item: TACTListItem);
BEGIN
    IF Ptr^.UsageCount = 1 THEN
       VMMarkChanged(Item.DataVA);
       Ptr^.FilePos.Idx := Val;
       VMRelease(Item.DataVA);
    ELSE
       VMRelease(Item.DataVA);
       MakeRefNameItem(Val, PoolNoForTDBTACTLists, Item.DataVA, Ptr);
       MarkAsUsed(Ptr);
       VMRelease(Item.DataVA);
    END;
END ReassignRefNameItem;

PROCEDURE GetNextRefNameItem(List: ADDRESS; (* ignored *)
                         VAR Item: TACTListItem): BOOLEAN;
VAR
    i:       CARDINAL;
    Ptr:     DataItemPntr;
BEGIN
    Ptr := VMAccess(Item.DataVA);
    CheckForGoodPointer(Ptr);
    i := Ptr^.FilePos.Idx;
    REPEAT
       INC (i)
    UNTIL (i > NumbOfRefNames) OR (RefsNameListPntr^[i]^.Pref = 0C);
    IF i > NumbOfRefNames THEN 
       VMRelease(Item.DataVA);
       RETURN FALSE
    END;
    ReassignRefNameItem(i, Ptr, Item);
    RETURN TRUE;
END GetNextRefNameItem;

PROCEDURE GetPrevRefNameItem(List: ADDRESS; (* ignored *)
                         VAR Item: TACTListItem): BOOLEAN;
VAR
    i:       CARDINAL;
    Ptr:     DataItemPntr;
BEGIN
    Ptr := VMAccess(Item.DataVA);
    CheckForGoodPointer(Ptr);
    i := Ptr^.FilePos.Idx;
    REPEAT
       DEC (i)
    UNTIL (i <= 0) OR (RefsNameListPntr^[i]^.Pref = 0C);
    IF i <= 0 THEN
       VMRelease(Item.DataVA);
       RETURN FALSE
    END;
    ReassignRefNameItem(i, Ptr, Item);
    RETURN TRUE;
END GetPrevRefNameItem;

PROCEDURE UpdateRef(VAR Item:  TACTListItem;
                        Val:   CARDINAL);
VAR
    Ptr:  DataItemPntr;
BEGIN
    IF Item.DataVA = NILVirt THEN 
       MakeRefNameItem(Val, PoolNoForTDBTACTLists, Item.DataVA, Ptr);
       MarkAsUsed(Ptr);
       VMRelease(Item.DataVA);
    ELSE
       Ptr := VMAccess(Item.DataVA);
       ReassignRefNameItem(Val, Ptr, Item);
    END;
END UpdateRef;

PROCEDURE GetFirstRefName(List: ADDRESS; (* ignored *)
                      VAR Item: TACTListItem): BOOLEAN;
VAR
    i:    CARDINAL;
BEGIN
    i := 1;
    WHILE (i <= NumbOfRefNames) AND (RefsNameListPntr^[i]^.Pref <> 0C) DO
       INC (i)
    END;
    IF i > NumbOfRefNames THEN
       ProgramErrorAndHalt('No RefName Found by GetFirstRefNme')
    END;
    UpdateRef(Item, i);
    RETURN TRUE
END GetFirstRefName;

PROCEDURE GetLastRefName(List: ADDRESS; (* ignored *)
                     VAR Item: TACTListItem): BOOLEAN;
VAR
    i:    CARDINAL;
BEGIN
    i := NumbOfRefNames;
    WHILE (i > 0) AND (RefsNameListPntr^[i]^.Pref <> 0C) DO
       DEC(i)
    END;
    IF i <= 0 THEN
       ProgramErrorAndHalt('No RefName Found by GetLastRefNme')
    END;
    UpdateRef(Item, i);
    RETURN TRUE
END GetLastRefName;

PROCEDURE FindRefNameItem(List:    ADDRESS; (* ignored here *)
                          Data:    VirtAddr; (* as DataItemVA *)
                      VAR Item:    TACTListItem): BOOLEAN;
VAR Pntr:  DataItemPntr;
BEGIN
   Pntr := VMAccess(Data);
   IF Pntr^.DataType <> RefNameType THEN
      VMRelease(Data);
      RETURN FALSE
   END;
   IF Item.DataVA <> NILVirt THEN DisposeDataItem(Item.DataVA) END;
   IF RealToPool(Pntr) = PoolNoForTDBTACTLists THEN
      Item.DataVA := Data;
   ELSE
      VMRelease(Data);
      DuplicateDataItem(Data, PoolNoForTDBTACTLists, Item.DataVA, Pntr);
   END;
   MarkAsUsed(Pntr);
   VMRelease(Item.DataVA);
   VMMarkChanged(Item.DataVA);
   RETURN TRUE;
END FindRefNameItem;

PROCEDURE RefNameItemDataPresent(List:   TACTList;
                                 Type:   ItemType;
                                 Pos:    HRecPntr;
                             VAR Item:   TACTListItem): BOOLEAN;
VAR
    i:    CARDINAL;
    j:    INTEGER;
BEGIN
   IF Type <> RefNameType THEN RETURN FALSE END;
   IF Pos.Rec <> 0 THEN
      ProgramErrorAndHalt('Invalid HRecPntr for RefNme Reference (1)')
   ELSIF (Pos.Idx > NumbOfRefNames - 1) OR (Pos.Idx = 0) THEN
      ProgramErrorAndHalt('Invalid HRecPntr for RefNme Reference (2)')
   END;
   i := Pos.Idx;
   IF RefsNameListPntr^[i]^.Pref <> 0C THEN
      j := RefsNameListPntr^[i]^.ID;
      i := 1;

      WHILE (i < NumbOfRefNames) AND (RefsNameListPntr^[i]^.ID <> j) AND
      (RefsNameListPntr^[i]^.Pref <> 0C) DO
         INC (i);
      END;
      IF i >= NumbOfRefNames THEN
         ProgramErrorAndHalt('No RefName Found by RefNameItemDataPresent');
      END;
   END;
   UpdateRef(Item, i);
   RETURN TRUE
END RefNameItemDataPresent;

PROCEDURE FindRefNameFromString(Text:   ARRAY OF CHAR; (* Sort Format *)
                                Type:   ItemType;
                                List:   ADDRESS; (* ignored *)
                            VAR Item:   TACTListItem): BOOLEAN;
VAR
     Found:	BOOLEAN;
     ID:	HRecPntr;
     OldIDIdx:	CARDINAL;
     I:		CARDINAL ;
     dummy:     BOOLEAN;
BEGIN
   IF Type <> RefNameType THEN RETURN FALSE END;
   ID.Rec := 0;
   Found := LookupRefName(Text,ID.Idx);
   Found := (RefsNameListPntr^[ID.Idx]^.Pref = 0C) ;
   OldIDIdx := ID.Idx ;
   I := OldIDIdx ;
   WHILE ((I < NumbOfRefNames) AND (RefsNameListPntr^[I]^.Pref <> 0C)) OR (I = 0) DO
      INC( I ) ;
   END ;
   IF I >= NumbOfRefNames THEN
      I := OldIDIdx ;
      WHILE (I > 0) AND (RefsNameListPntr^[I]^.Pref <> 0C) DO
         DEC( I ) ;
      END ;
      IF I = 0 THEN
         ProgramErrorAndHalt('Invalid RefsNameListPntr in FindRefNmeFromString')
      END ;
   END ;
   ID.Idx := I ;
   dummy := RefNameItemDataPresent(List, Type, ID, Item);
   RETURN Found ;
END FindRefNameFromString;

PROCEDURE MakeTACTRefNameList(): TACTList;
VAR TList:   TACTList;
BEGIN
   NEW(TList);
   WITH TList^ DO
      LDataSize := SIZE(TACTListData);
      BaseData := ADR(OfficialRefNameListData);
      Type := RefNameList;
   END;
   RETURN TList;
END MakeTACTRefNameList;

BEGIN
   WITH OfficialRefNameListData DO
      NewItemProc :=      GenericNewListItem;
      CopyListItemProc := GenericCopyListItem;
      DispListItemProc := GenericDisposeListItem;
      DisposeListProc :=  GenericDisposeList;
      GetItemDataProc :=  GenericGetItemData;
      ReleaseItemProc :=  GenericReleaseItemHold;
      GetFirstItemProc := GetFirstRefName;
      GetLastItemProc  := GetLastRefName;
      GetNextItemProc :=  GetNextRefNameItem;
      GetPrevItemProc :=  GetPrevRefNameItem;
      FindItemProc :=     FindRefNameItem;
      ItemDataPresProc := RefNameItemDataPresent;
      FindFromStrProc :=  FindRefNameFromString;
   END;
END RefNameListModule.
