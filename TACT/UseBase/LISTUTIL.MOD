IMPLEMENTATION MODULE ListUtils;

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
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM HyperDataModel IMPORT HTokenData, HTypeData;
FROM HyperBase IMPORT HRecPntr;
FROM ListData IMPORT
  (* types *) ItemType, DataItemPntr,
  (* procs *) MakeTypeDataItem, MakeTDBTypeDataItem, MarkAsUsed, CompareDataItems,
              MakeTokenDataItem;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, GetFirstItem, GetNextItem,
              ItemDataPresent, CopyListItem, GetItemData,
              DiscardList, ReleaseItemHold;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, InsertListItem, ListPoolNo;
FROM Categories IMPORT
   (* Procs *) DoCatContents;
FROM TACTDataServices IMPORT
  (* procs *) GetTokensForType, GetTDBTokenData,
              DisposeDataItem, VirtToTACTList,TACTListToVirt;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) GetType, FreeTypeHandle, GetNextType, GetPrevType,
              FindType;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM DBData IMPORT
    (* vars  *) BeginType, NoTokensInDB;
FROM OccurListModule IMPORT InitializeOccurList;
FROM TokenBase IMPORT
  (* procs *) GetTokenNo, GetTokenHRec;
FROM VirtMem IMPORT VirtAddr, NILVirt,
   VMMarkChanged, VMAccess, VMModify, VMRelease;

TYPE
   PosOrderDataType = (MainListType, WordEntryType);
   PosOrderData = POINTER TO PosOrderRec;
   PosOrderRec = RECORD
      Next:        PosOrderData;
      Type:        PosOrderDataType;
      List:        TACTList;
      CurListPos:  TACTListItem;
      DeleteWhenDone: BOOLEAN;
   END;


PROCEDURE IllegalListData;
BEGIN
   ProgramErrorAndHalt('Illegal DataType in ListUtil')
END IllegalListData;

(*
PROCEDURE LoadCatList(cData:   DataItemPntr);
VAR temp:   CARDINAL;
    cList:  TACTList;
BEGIN
   IF cData^.Contents <> NIL THEN RETURN END;
   cList := InitializeMemoryList();
   DoCatContents(cList,temp,cData^.CatFileData.Name);
   cData^.Contents := ADDRESS(cList);
END LoadCatList;
*)

PROCEDURE MakePosList(ListIn:  TACTList;
                  VAR ListOut: TACTList);

PROCEDURE InsertFromContentsList(List:   TACTList);
VAR
   tItem:        TACTListItem;
   tList:        TACTList;
   tData:        DataItemPntr;
   DVA:          VirtAddr;
   tType:        ItemType;
   dummy:        BOOLEAN;
BEGIN
   NewListItem(List, tItem);
   IF NOT GetFirstItem(List, tItem) THEN
      DisposeListItem(List, tItem);
      RETURN
   END;
   REPEAT
      GetItemData(List, tItem, DVA, tData);
      tType := tData^.DataType;
      CASE tType OF
        CatType:
           VirtToTACTList(tData^.Contents, tList);
           InsertFromContentsList(tList);
           DiscardList(tList);
      | TypeType:
           GetTokensForType(DVA);
           VirtToTACTList(tData^.Contents, tList);
           InsertFromContentsList(tList);
           DiscardList(tList);
      | TokenType:
           dummy := InsertListItem(DVA, ListOut);
      ELSE
         IllegalListData
      END;
      ReleaseItemHold(List, tItem);
   UNTIL NOT GetNextItem(List, tItem);
   DisposeListItem(List, tItem);
END InsertFromContentsList;

BEGIN
   InsertFromContentsList(ListIn);
END MakePosList;

PROCEDURE MakeWordList(ListIn:  TACTList;
                   VAR ListOut: TACTList);
VAR dummy:    BOOLEAN;
    pNo:      CARDINAL;

PROCEDURE InsertFromList(List:   TACTList);
VAR
   tItem:        TACTListItem;
   oItem:        TACTListItem;
   tData:        DataItemPntr;
   tDVA:         VirtAddr;
   tList:        TACTList;

PROCEDURE HandleTokenType;
VAR
   tHandle:      HTypeHandle;
   tPos:         HRecPntr;
   oData:        DataItemPntr;
   HWord:        DataItemPntr;
   cList:        TACTList;
   DVA:          VirtAddr; (* of DataItem VA *)
BEGIN
   IF tData^.HeadWord = NILVirt THEN
      IF NOT tData^.TokenDataLoaded THEN GetTDBTokenData(tData) END;
      VMMarkChanged(tDVA);
      tPos.Rec := tData^.TokenFileData.HRecNo + BeginType;
      tPos.Idx := ORD(tData^.TokenFileData.HRecPos);
   ELSE
      oData := VMAccess(tData^.HeadWord);
      tPos := oData^.FilePos;
      VMRelease(tData^.HeadWord);
   END;
   IF ItemDataPresent(ListOut,TypeType,tPos,oItem) THEN
      GetItemData(ListOut, oItem, DVA, oData);
      VirtToTACTList(oData^.Contents, cList);
   ELSE
      WITH tData^ DO
         IF HeadWord = NILVirt THEN
            GetType(tPos,tHandle);
            MakeTDBTypeDataItem(tHandle^^,pNo, tData^.HeadWord, oData);
            FreeTypeHandle(tHandle);
         ELSE
            HWord := VMAccess(tData^.HeadWord);
            MakeTypeDataItem(HWord^.TypeFileData,pNo, tData^.HeadWord, oData);
            VMRelease(tData^.HeadWord);
         END;
         DVA := tData^.HeadWord;
         oData^.FilePos := tPos;
         cList := NewMemoryList(pNo);
         TACTListToVirt(cList, pNo, oData^.Contents);
      END;
      dummy := InsertListItem(DVA, ListOut);
   END;
   IF oData^.TypeFileData.NoOccur <> oData^.NoContents THEN
       IF InsertListItem(tDVA, cList) THEN
          INC(oData^.NoContents);
          MarkAsUsed(oData);
       END;
   END;
   DiscardList(cList);
   VMRelease(DVA);
END HandleTokenType;

BEGIN	(* InsertFromList *)
   tData := NIL;
   NewListItem(List, tItem);
   NewListItem(ListOut, oItem);
   IF NOT GetFirstItem(List, tItem) THEN
      DisposeListItem(ListOut, oItem);
      DisposeListItem(List, tItem);
      RETURN
   END;
   REPEAT
      GetItemData(List, tItem, tDVA, tData);
      CASE tData^.DataType OF
        CatType:
           VirtToTACTList(tData^.Contents, tList);
           InsertFromList(tList);
           DiscardList(tList);
      | TypeType:
           dummy := InsertListItem(tDVA, ListOut);
      | TokenType:
           HandleTokenType;
      ELSE
         IllegalListData
      END;
      ReleaseItemHold(List, tItem);
   UNTIL NOT GetNextItem(List, tItem);
   DisposeListItem(List, tItem);
   DisposeListItem(ListOut, oItem);
END InsertFromList;

BEGIN (* MakeWordList *)
   pNo := ListPoolNo(ListOut);
   InsertFromList(ListIn);
END MakeWordList;

PROCEDURE DisposePosOrderItem(VAR ThisOne:  PosOrderData);
VAR  temp: PosOrderData;
BEGIN
   temp := ThisOne;
   ThisOne := temp^.Next;
   WITH temp^ DO
      DisposeListItem(List, CurListPos);
      IF DeleteWhenDone THEN  DiscardList(List);  END ;
   END;
   DISPOSE(temp);
END DisposePosOrderItem;

PROCEDURE StartPosOrder(ListIn:   TACTList;
                    VAR PosOrder: PosOrderData);

PROCEDURE DoRealPosOrder(ListIn:  TACTList);
VAR   tItem:    TACTListItem;
      tData:    DataItemPntr;
      tPos:     PosOrderData;
      tToDI:    VirtAddr; (* VAddress of DataItem *)
      tList:    TACTList;

PROCEDURE BuildPosForList(l:  TACTList; DoDelete : BOOLEAN);
BEGIN
   NEW(tPos);
   WITH tPos^ DO
      Next := PosOrder;
      PosOrder := tPos;
      NewListItem(l,CurListPos);
      List := l;
      DeleteWhenDone := DoDelete;
   END;
END BuildPosForList;

BEGIN
(* This code assumes (by means of return if TokenType found) that
   all records in the inputlist after the first tokentype are
   "not of interest": This is true with the current ordering of
   values for type ItemType in ListData, but would be incorrect
   if the ordering was changed -- remember this!!  j.b. *)

   NewListItem(ListIn,tItem);
   IF NOT GetFirstItem(ListIn, tItem) THEN
      DisposeListItem(ListIn,tItem);
      RETURN
   END;
   REPEAT
      GetItemData(ListIn, tItem, tToDI, tData);
      CASE tData^.DataType OF
        CatType:
           VirtToTACTList(tData^.Contents, tList);
           DoRealPosOrder(tList);
      | TokenType:
          BuildPosForList(ListIn, (* DoDelete *) FALSE);
          WITH PosOrder^ DO
             CopyListItem(ListIn, tItem, CurListPos);
(*           GetItemData(ListIn, CurListPos, CurrentData); *)
             Type := MainListType;
          END;
          ReleaseItemHold(ListIn,tItem);
          DisposeListItem(ListIn,tItem);
          RETURN (* see warning note above about this *)
      | TypeType:
          IF tData^.Contents <> NILVirt THEN VirtToTACTList(tData^.Contents, tList)
          ELSE tList := InitializeOccurList(tToDI) END;
          BuildPosForList(tList, (* DoDelete *) TRUE);
          WITH PosOrder^ DO
             IF NOT GetFirstItem(List, CurListPos) THEN
                ProgramErrorAndHalt('Failure of GetFirstItem in StartPosOrder')
             END;
             Type := WordEntryType;
          END;
      ELSE
          IllegalListData
      END;
      ReleaseItemHold(ListIn, tItem);
   UNTIL NOT GetNextItem(ListIn, tItem);
   DisposeListItem(ListIn,tItem);
END DoRealPosOrder;

BEGIN
   PosOrder := NIL;
   DoRealPosOrder(ListIn);
END StartPosOrder;

PROCEDURE NextPosOrder(VAR PosOrder: PosOrderData;
                       VAR DataVA:   VirtAddr (* DataItem VA *)): BOOLEAN;
VAR
   cur, prev, hcur:  PosOrderData;
   curdata,hcurdata: DataItemPntr;
   curDVA, hcurDVA:  VirtAddr;
   remove:           BOOLEAN;
BEGIN
   IF DataVA <> NILVirt THEN DisposeDataItem(DataVA) END;
   IF PosOrder = NIL THEN RETURN FALSE END;
   hcur := PosOrder;
   cur := hcur^.Next;
   GetItemData(hcur^.List,hcur^.CurListPos,hcurDVA,hcurdata);
   WHILE cur <> NIL DO
      GetItemData(cur^.List,cur^.CurListPos,curDVA,curdata);
      IF CompareDataItems(hcurdata,curdata) = 1 THEN
          hcurdata := curdata;
          hcurDVA := curDVA;
          ReleaseItemHold(hcur^.List,hcur^.CurListPos);
          hcur := cur
      ELSE
          ReleaseItemHold(cur^.List,cur^.CurListPos);
      END;
      cur := cur^.Next;
   END;

(* hcur points to the item to return *)

   DataVA := hcurDVA;
   ReleaseItemHold(hcur^.List,hcur^.CurListPos);

   hcurdata := VMModify(DataVA);
   MarkAsUsed(hcurdata);

   prev := NIL;
   cur := PosOrder;
   WHILE cur <> NIL DO
      WITH cur^ DO
         GetItemData(List,CurListPos,curDVA,curdata);
         IF CompareDataItems(hcurdata,curdata) = 0 THEN
            ReleaseItemHold(List,CurListPos);
            remove := NOT GetNextItem(List, CurListPos)
         ELSE
            remove := (Type = MainListType) AND (curdata^.DataType <> TokenType);
            ReleaseItemHold(List,CurListPos);
         END;
      END;
      IF remove THEN
          IF prev = NIL THEN
             DisposePosOrderItem(PosOrder);
             cur := PosOrder;
          ELSE
             DisposePosOrderItem(prev^.Next);
             cur := prev^.Next;
          END;
      ELSE
         prev := cur;
         cur := cur^.Next;
      END;
   END;
   VMRelease(DataVA);
   RETURN TRUE
END NextPosOrder;

PROCEDURE FinishPosOrder(VAR PosOrder: PosOrderData);
BEGIN
   WHILE PosOrder <> NIL DO DisposePosOrderItem(PosOrder) END;
END FinishPosOrder;

END ListUtils.
