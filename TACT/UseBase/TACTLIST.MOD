IMPLEMENTATION MODULE TACTListModule;

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

(*V1=Production *)
(*V2=Assert *)

FROM MemoryManagement IMPORT DEALLOCATE, ShowBusy ;
FROM HyperBase IMPORT HRecPntr;
FROM ListData IMPORT  MarkAsUsed;
FROM TACTDataServices IMPORT DisposeDataItem;
FROM VirtMem IMPORT VMAccess, VMModify, VMRelease, NILVirt;

(*<Assert
IMPORT Lib, SYSTEM ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM SYSTEM IMPORT Seg,Ofs,HeapBase;
  VAR
     PgmStartAddr,
     PgmEndAddr		: LONGCARD ;

PROCEDURE CheckAddr( List : TACTList ) ;
   VAR
	NormalizedAddr	: LONGCARD ;
	a		: ADDRESS ;
   BEGIN
	IF List = NIL THEN
	   ProgramErrorAndHalt( "TACTList: NIL list." );
	END ;
	a := ADR( List^.BaseData^ ) ;
	NormalizedAddr := LONGCARD( Seg( a^ ) ) * 16 + LONGCARD( Ofs( a^ ) ) ;
	IF (NormalizedAddr > PgmEndAddr) OR (NormalizedAddr < PgmStartAddr) THEN
	   (* this address is outside the program code in memory *)
	   ProgramErrorAndHalt( "TACTList: invalid addr reference." );
	END ;
   END CheckAddr ;
Assert>*)

PROCEDURE NewListItem(List:  TACTList; VAR Item: TACTListItem);
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   List^.BaseData^.NewItemProc(List, Item);
END NewListItem;

PROCEDURE DisposeListItem(List:  TACTList; VAR Item: TACTListItem);
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
    List^.BaseData^.DispListItemProc(List, Item)
END DisposeListItem;

PROCEDURE GetListType(List:  TACTList): TACTListType;
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   RETURN List^.Type;
END GetListType;

PROCEDURE CopyListItem(List:    TACTList;
                       Item1:   TACTListItem;
                   VAR Item2:   TACTListItem);
   BEGIN
	(*<Assert CheckAddr( List ) ; Assert>*)
	List^.BaseData^.CopyListItemProc( List, Item1, Item2 );
   END CopyListItem;

PROCEDURE DiscardList(VAR List:   TACTList);
BEGIN
  IF List = NIL THEN  RETURN  END;
  (*<Assert CheckAddr( List ) ; Assert>*)
  List^.BaseData^.DisposeListProc(List);
END DiscardList;

PROCEDURE GetItemData(List: TACTList;
                      Item: TACTListItem;
                  VAR DVA:  VirtAddr; (* VAddress of Data *)
                  VAR Data: DataItemPntr);
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   List^.BaseData^.GetItemDataProc(List, Item, DVA, Data);
END GetItemData;

PROCEDURE ReleaseItemHold(List: TACTList;
                          Item: TACTListItem);
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   List^.BaseData^.ReleaseItemProc(List, Item);
END ReleaseItemHold;

PROCEDURE GetFirstItem(List:    TACTList;
                   VAR Item: TACTListItem): BOOLEAN;
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   RETURN List^.BaseData^.GetFirstItemProc(List, Item);
END GetFirstItem;

PROCEDURE GetLastItem(List:     TACTList;
                  VAR Item: TACTListItem): BOOLEAN;
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   RETURN List^.BaseData^.GetLastItemProc(List, Item);
END GetLastItem;

PROCEDURE GetNextItem(List : TACTList; VAR Item : TACTListItem): BOOLEAN;
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   ShowBusy ;
   RETURN List^.BaseData^.GetNextItemProc(List, Item);
END GetNextItem;

PROCEDURE GetPrevItem(List : TACTList; VAR Item : TACTListItem): BOOLEAN;
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   ShowBusy ;
   RETURN List^.BaseData^.GetPrevItemProc(List, Item);
END GetPrevItem;

PROCEDURE FindItem(List:        TACTList;
                   Data:        VirtAddr; (* as DataItem VA *)
               VAR Item:        TACTListItem): BOOLEAN;
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   RETURN List^.BaseData^.FindItemProc(List, Data, Item);
END FindItem;

PROCEDURE ItemDataPresent(List:   TACTList;
                          Type:   ItemType;
                          Pos:    HRecPntr;
                      VAR Item:   TACTListItem): BOOLEAN;
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   RETURN List^.BaseData^.ItemDataPresProc(List, Type, Pos, Item);
END ItemDataPresent;

PROCEDURE FindFromString(Text:   ARRAY OF CHAR;
                         Type:   ItemType;
                         List:   TACTList;
                     VAR Item:   TACTListItem): BOOLEAN;
BEGIN
   (*<Assert CheckAddr( List ) ; Assert>*)
   RETURN List^.BaseData^.FindFromStrProc(Text, Type, List, Item);
END FindFromString;

(* the following procedures are meant to be used only by list definers --
   not users -- they provide common definitions of simple LIST functions.

   NB: Not all list types >can< use them!!    jb *)

PROCEDURE GenericNewListItem(List:  TACTList; VAR Item: TACTListItem);
BEGIN
   (* This code assumes all TACTListItems are simply Virt ADDRESSES *)
   Item.DataVA := NILVirt;
END GenericNewListItem;

PROCEDURE GenericDisposeListItem(List:  TACTList; VAR Item: TACTListItem);
BEGIN
   IF Item.DataVA = NILVirt THEN RETURN END;
   DisposeDataItem(Item.DataVA);
END GenericDisposeListItem;

PROCEDURE GenericDisposeList(VAR List :ADDRESS);
VAR TList:   TACTList;
BEGIN
   TList := TACTList(List);
   DISPOSE(TList);
   List := NIL;
END GenericDisposeList;

PROCEDURE GenericGetItemData(List: TACTList;
                         Item: TACTListItem;
                     VAR DVA:  VirtAddr; (* VAddress of Data *)
                     VAR Data: DataItemPntr);
BEGIN
   Data := VMAccess(Item.DataVA);
   DVA := Item.DataVA;
END GenericGetItemData;

PROCEDURE GenericReleaseItemHold(List: TACTList;
                                 Item: TACTListItem);
BEGIN
   VMRelease(Item.DataVA);
END GenericReleaseItemHold;

PROCEDURE GenericCopyListItem(      List : TACTList; Item1 : TACTListItem;
				VAR Item2 : TACTListItem ) ;
    VAR Pntr:   DataItemPntr;
    BEGIN
	Item2 := Item1;
	Pntr := VMModify(Item2.DataVA);
	MarkAsUsed(Pntr);
	VMRelease(Item2.DataVA);
    END GenericCopyListItem ;

BEGIN
	(*<Assert
	PgmStartAddr := LONGCARD( Lib.PSP ) * 16 ;
	PgmEndAddr := LONGCARD(SYSTEM.HeapBase) * 16 ;
	Assert>*)
END TACTListModule.
