IMPLEMENTATION MODULE TypeListModule;

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

FROM SYSTEM IMPORT ADR;
FROM TACTDataServices IMPORT
  (* procs *) AllocTypeData, DisposeDataItem;
FROM ListData IMPORT
  (* types *) ItemType,DataItemPntr,
  (* procs *) MarkAsUsed, DuplicateDataItem;
FROM MainLists IMPORT PoolNoForTDBTACTLists;
FROM HyperBase IMPORT HRecPntr;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM DBData IMPORT
    (* vars  *) BeginType, EndTypeRec, EndTypeIdx;
FROM MemoryManagement IMPORT ALLOCATE;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) GetType, FreeTypeHandle, GetNextType, GetPrevType,
              FindType;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;
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
    IF A^.DataType <> TypeType THEN
       ProgramErrorAndHalt('NonTypeType Found')
    END;
END CheckForGoodPointer;

PROCEDURE GetPrevTypeItem(List: ADDRESS; (* ignored *)
                      VAR Item: TACTListItem): BOOLEAN;
VAR
    H:       HTypeHandle;
    Ptr:     DataItemPntr;
    NewPos:  HRecPntr;
    hV:      VirtAddr;
BEGIN
   Ptr := VMAccess(Item.DataVA);
   hV := Item.DataVA;
   CheckForGoodPointer(Ptr);
   IF NOT GetPrevType(Ptr^.FilePos,NewPos) THEN
      VMRelease(hV);
      RETURN FALSE
   END;
   GetType(NewPos,H);
   AllocTypeData(H, NewPos, PoolNoForTDBTACTLists, Item.DataVA, Ptr);
   MarkAsUsed(Ptr);
   VMRelease(Item.DataVA);
   FreeTypeHandle(H);
   VMRelease(hV);
   DisposeDataItem(hV);
   RETURN TRUE;
END GetPrevTypeItem;

PROCEDURE GetNextTypeItem(List: ADDRESS; (* ignored *)
                      VAR Item: TACTListItem): BOOLEAN;
VAR
    H:       HTypeHandle;
    Ptr:     DataItemPntr;
    NewPos:  HRecPntr;
    hV:      VirtAddr;
BEGIN
   Ptr := VMAccess(Item.DataVA);
   hV := Item.DataVA;
   CheckForGoodPointer(Ptr);
   IF NOT GetNextType(Ptr^.FilePos,NewPos) THEN
      VMRelease(hV);
      RETURN FALSE
   END;
   GetType(NewPos,H);
   AllocTypeData(H, NewPos, PoolNoForTDBTACTLists, Item.DataVA, Ptr);
   MarkAsUsed(Ptr);
   VMRelease(Item.DataVA);
   FreeTypeHandle(H);
   VMRelease(hV);
   DisposeDataItem(hV);
   RETURN TRUE;
END GetNextTypeItem;

PROCEDURE FindGivenType(Pos:  HRecPntr;
                    VAR A:    VirtAddr);   (* DataItemPntr *)
VAR  H:  HTypeHandle;
     DPntr: DataItemPntr;
BEGIN
    IF A <> NILVirt THEN DisposeDataItem(A) END;
    GetType(Pos,H);
    AllocTypeData(H, Pos, PoolNoForTDBTACTLists, A, DPntr);
    MarkAsUsed(DPntr);
    FreeTypeHandle(H);
    VMRelease(A);
END FindGivenType;

PROCEDURE GetFirstType(List:    ADDRESS; (* ignored here *)
                   VAR Item: TACTListItem): BOOLEAN;
VAR
    NewPos:  HRecPntr;
BEGIN
    NewPos.Rec := BeginType;
    NewPos.Idx := 2;
    FindGivenType(NewPos, Item.DataVA);
    RETURN TRUE;
END GetFirstType;

PROCEDURE GetLastType(List:    ADDRESS; (* ignored here *)
                  VAR Item: TACTListItem): BOOLEAN;
VAR
    NewPos:  HRecPntr;
BEGIN
    NewPos.Rec := EndTypeRec;
    NewPos.Idx := EndTypeIdx;
    FindGivenType(NewPos, Item.DataVA);
    IF NOT GetPrevTypeItem(List, Item) THEN
        ProgramErrorAndHalt('Unexpected failure in GetLastType');
    END;
    RETURN TRUE;
END GetLastType;

PROCEDURE FindTypeFromString(Text:   ARRAY OF CHAR;
                             Type:   ItemType;
                             List:   ADDRESS; (* ignored *)
                         VAR Item:   TACTListItem): BOOLEAN;
VAR
    H:       HTypeHandle;
    NewPos:  HRecPntr;
    TempPos: HRecPntr;
    Found:   BOOLEAN;
    dummy:   BOOLEAN;
    DPntr:   DataItemPntr;
BEGIN
    IF Type <> TypeType THEN RETURN FALSE END;

    IF FindType(Text,NewPos,H) THEN
         Found := TRUE
    ELSE
         Found := FALSE;
         FreeTypeHandle(H);
         (* If GetNextType failed -- we are at the end of the type list;
            hence, we should ignore the failure j.b. *)
         IF GetNextType(NewPos,TempPos) THEN NewPos := TempPos END;
         GetType(NewPos,H);
    END;
    DisposeDataItem(Item.DataVA);
    AllocTypeData(H, NewPos, PoolNoForTDBTACTLists, Item.DataVA, DPntr);
    MarkAsUsed(DPntr);
    VMRelease(Item.DataVA);
    FreeTypeHandle(H);
    RETURN Found
END FindTypeFromString;

PROCEDURE FindTypeItem(List:    ADDRESS; (* ignored here *)
                       Data:    VirtAddr; (* as DataItemVA *)
                   VAR Item:    TACTListItem): BOOLEAN;
VAR Pntr:  DataItemPntr;
BEGIN
   Pntr := VMAccess(Data);
   IF Pntr^.DataType <> TypeType THEN
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
END FindTypeItem;

PROCEDURE TypeItemDataPresent(List:   TACTList;
                              Type:   ItemType;
                              Pos:    HRecPntr;
                          VAR Item:   TACTListItem): BOOLEAN;
BEGIN
   IF Type <> TypeType THEN RETURN FALSE END;
   FindGivenType(Pos,Item.DataVA);
   RETURN TRUE;
END TypeItemDataPresent;

PROCEDURE MakeTACTTypeList(): TACTList;
VAR TList:   TACTList;
BEGIN
   NEW(TList);
   WITH TList^ DO
      LDataSize := SIZE(TACTListData);
      BaseData := ADR(OfficialTypeListData);
      Type := TypeList;
   END;
   RETURN TList;
END MakeTACTTypeList;

BEGIN
   WITH OfficialTypeListData DO
      NewItemProc :=      GenericNewListItem;
      CopyListItemProc := GenericCopyListItem;
      DispListItemProc := GenericDisposeListItem;
      DisposeListProc :=  GenericDisposeList;
      GetItemDataProc :=  GenericGetItemData;
      ReleaseItemProc :=  GenericReleaseItemHold;
      GetFirstItemProc := GetFirstType;
      GetLastItemProc  := GetLastType;
      GetNextItemProc :=  GetNextTypeItem;
      GetPrevItemProc :=  GetPrevTypeItem;
      FindItemProc :=     FindTypeItem;
      ItemDataPresProc := TypeItemDataPresent;
      FindFromStrProc :=  FindTypeFromString;
   END;
END TypeListModule.
