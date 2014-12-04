IMPLEMENTATION MODULE Categories ;
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


(*V4=Dbg Debugging code *)

IMPORT Str ;
FROM SYSTEM IMPORT ADDRESS;
FROM GlobalDefs IMPORT StrAny;
FROM ResMessages IMPORT
  (* proc *) MsgString, PutResError, PutResWarning;
FROM MainLists IMPORT
  (* vars *) SelectedListEmpty;
FROM WordBase IMPORT
  (* Procs *) IntToSortWord, SortToIntWord, IntToSingleSortWord;
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

END Categories .
