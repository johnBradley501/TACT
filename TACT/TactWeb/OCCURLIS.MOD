IMPLEMENTATION MODULE OccurListModule;
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


IMPORT ASCII;
IMPORT Str, Lib ;
FROM SYSTEM IMPORT ADR;
FROM HyperDataModel IMPORT HyperData, HyperLength, HTokenData, HNoOccurs, TypeMaxDataPos,
   HOccurData, HRecPntr, HTypeData, OccurRecSize, MaxSpaceForOccursInRec ;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE, RealStoragePntr;
FROM HyperBase IMPORT NilHRecPntr,
   GetBaseHyper, ReleaseBaseHyper, CompareHRecs;
FROM MainLists IMPORT
   PoolNoForTDBTACTLists;
FROM TACTDataServices IMPORT
  (* procs *) DisposeDataItem;
FROM ListData IMPORT
  (* types *) DataItemPntr, ItemType,
              MarkAsUsed, MarkAsFreed, MakeTokenDataItem;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM TACTListModule IMPORT
   TACTListType, TACTList, TACTListData, TACTListItem, TACTListBaseData,
   TACTListBasePntr,
   GenericDisposeListItem, GenericDisposeList, GenericGetItemData;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) VMAccess, VMModify, VMRelease, VMMarkChanged, RealToPool;
FROM DBData IMPORT TDBFile, BeginToken;

TYPE
   OccurTypeTACTListData = RECORD
	(* first three items much match TACTList.TACTListData j.b.*)
        LDataSize: CARDINAL;
        BaseData:  TACTListBasePntr;
        Type:      TACTListType;
	(*  Unique Data items begins here  j.b. *)
        HeadVA:    VirtAddr;
        OccurStart:HRecPntr;
        NumbOccurs:CARDINAL;
        MaxOccurs :CARDINAL;	(* in the TypeRec, excluding pointer info *)
   END;
   OccurTypeTACTList = POINTER TO OccurTypeTACTListData;

   OccurListItemData = RECORD
      CurPos:     CARDINAL;
      ToDVA:      VirtAddr;
   END;
   OccurListItemPntr = POINTER TO OccurListItemData;

PROCEDURE GetTokenHRecPntr(List		: OccurTypeTACTList;
                           OccurPos	: CARDINAL; (* zero based *)
                       VAR HRec		: HRecPntr);
VAR hp:     RealStoragePntr;
    OPntr:  POINTER TO HOccurData;
    TDBRec: CARDINAL;
    TDBIdx: CARDINAL;
BEGIN
   WITH List^ DO
      IF OccurPos <= MaxOccurs THEN
	 (* its on the same record as the Type info *)
	 TDBRec := OccurStart.Rec ;
	 TDBIdx := OccurStart.Idx - OccurPos * OccurRecSize ;
      ELSE
	 TDBRec := OccurStart.Rec + ((OccurPos - 1 - MaxOccurs) DIV HNoOccurs) + 1 ;
         TDBIdx := TypeMaxDataPos - OccurRecSize -
                   ((OccurPos - 1 - MaxOccurs) MOD HNoOccurs) * OccurRecSize ;
      END ;
   END;
   GetBaseHyper(TDBRec,hp,TDBFile);
   OPntr := ADR(hp^.HRecord.TextData[ TDBIdx ]);
   HRec.Rec := OPntr^.TRecNo + BeginToken;
   HRec.Idx := ORD(OPntr^.TRecPos);
   ReleaseBaseHyper(TDBFile,hp);
END GetTokenHRecPntr;

PROCEDURE ChangeOverData(VAR VA:    VirtAddr (* DataItem VA *);
                            Pos:    HRecPntr;
                            HVA:    VirtAddr);
VAR
    A:       DataItemPntr;

PROCEDURE MakeNewTDI;
VAR
   HPntr:  DataItemPntr;
BEGIN
   MakeTokenDataItem(VA, PoolNoForTDBTACTLists, A);
   MarkAsUsed(A);
   A^.HeadWord := HVA;
   HPntr := VMModify(HVA);
   MarkAsUsed(HPntr);
   VMRelease(HVA);
END MakeNewTDI;

BEGIN
    IF VA = NILVirt THEN
       MakeNewTDI;
    ELSE
       A := VMModify(VA);
       IF A^.UsageCount = 1 THEN
          WITH A^ DO
             HeadWord := HVA;
             CurrentContextCount := 0 ; (* 0 = current context range not set yet *)
             StartContext := NilHRecPntr ;
             FinishContext := NilHRecPntr ;
             BefOffset := CHR( 0 ) ;
             AftOffset := CHR( 0 ) ;
             TokenDataLoaded := FALSE;
          END;
       ELSE
          MarkAsFreed( A ) ;
          VMRelease(VA);
          MakeNewTDI;
       END;
    END;
    A^.FilePos := Pos;
    VMRelease(VA);
END ChangeOverData;

PROCEDURE CopyOccurListItem(List: TACTList;
                            Item1: TACTListItem;
                        VAR Item2: TACTListItem);
VAR LI1, LI2:   OccurListItemPntr;
(*  A1, A2, A3: DataItemPntr; *)
    A:          DataItemPntr;
BEGIN
   NEW(LI2);
   LI1 := Item1.DataRA;
   LI2^ := LI1^; (* copy OK here -- full space allocated j.b. *)
   IF LI2^.ToDVA <> NILVirt THEN
      A := VMModify(LI1^.ToDVA);
      MarkAsUsed(A);
(* this is old ... j.b.
      MakeTokenDataItem(LI2^.ToDVA, PoolNoForTDBTACTLists, A2);
      Lib.Move(A1, A2, A1^.ItemSize);
      A2^.UsageCount := 1;
      A3 := VMModify( A2^.HeadWord ) ;   (* now keep the Head word around *)
      INC( A3^.UsageCount ) ;
      VMRelease( A2^.HeadWord ) ;
      VMRelease(LI2^.ToDVA);
this was old   ...j.b. *)
      VMRelease(LI1^.ToDVA);
   END;
   Item2.DataRA := LI2;
END CopyOccurListItem;

PROCEDURE NewOccurListItem(List:  ADDRESS; (* ignored here *)
                       VAR Item:  TACTListItem);
VAR
   LI:   OccurListItemPntr;
BEGIN
   NEW(LI);
   WITH LI^ DO
      CurPos := 0;
      ToDVA := NILVirt;
   END;
   Item.DataRA := LI;
END NewOccurListItem;

PROCEDURE DisposeOccurListItem(List:  TACTList; VAR Item: TACTListItem);
VAR
   LI:   OccurListItemPntr;
BEGIN
   LI := Item.DataRA;
   IF LI = NIL THEN RETURN END;
   DisposeDataItem(LI^.ToDVA);
   DISPOSE(LI);
   Item.DataRA := NIL;
END DisposeOccurListItem;

PROCEDURE GetOccurItemData(List: TACTList;
                           Item: TACTListItem;
                       VAR DVA:  VirtAddr; (* VAddress of Data *)
                       VAR Data: DataItemPntr);
VAR
   LI:   OccurListItemPntr;
BEGIN
   LI := Item.DataRA;
   DVA := LI^.ToDVA;
   Data := VMAccess(DVA);
END GetOccurItemData;

PROCEDURE ReleaseOccurItemHold(List: TACTList;
                               Item: TACTListItem);
VAR
   LI:   OccurListItemPntr;
BEGIN
   LI := Item.DataRA;
   VMRelease(LI^.ToDVA);
END ReleaseOccurItemHold;

PROCEDURE GetPrevOccur(List:  ADDRESS;
                  VAR Item:   TACTListItem): BOOLEAN;
VAR
   LI:   OccurListItemPntr;
   L:    OccurTypeTACTList;
   LIH:  HRecPntr;
BEGIN
   LI := Item.DataRA;
   IF LI^.CurPos = 0 THEN RETURN FALSE END;
   DEC(LI^.CurPos);
   L := OccurTypeTACTList(List);
   GetTokenHRecPntr(L, LI^.CurPos, LIH);
   ChangeOverData(LI^.ToDVA, LIH, L^.HeadVA);
   RETURN TRUE;
END GetPrevOccur;


PROCEDURE GetNextOccur(List:  ADDRESS;
                  VAR Item:   TACTListItem): BOOLEAN;
VAR
   LI:   OccurListItemPntr;
   L:    OccurTypeTACTList;
   LIH:  HRecPntr;
BEGIN
   L := OccurTypeTACTList(List);
   LI := Item.DataRA;
   IF LI^.CurPos = L^.NumbOccurs-1 THEN RETURN FALSE END;
   INC(LI^.CurPos);
   GetTokenHRecPntr(L, LI^.CurPos, LIH);
   ChangeOverData(LI^.ToDVA, LIH, L^.HeadVA);
   RETURN TRUE;
END GetNextOccur;

PROCEDURE GetFirstOccur(List:    ADDRESS;
                   VAR Item: TACTListItem): BOOLEAN;
VAR
   LI:   OccurListItemPntr;
   L:    OccurTypeTACTList;
   LIH:  HRecPntr;
BEGIN
   L := OccurTypeTACTList(List);
   LI := Item.DataRA;
   LI^.CurPos := 0;
   GetTokenHRecPntr(L, LI^.CurPos, LIH);
   ChangeOverData(LI^.ToDVA, LIH, L^.HeadVA);
   RETURN TRUE;
END GetFirstOccur;

PROCEDURE GetLastOccur(List:    ADDRESS;
                  VAR Item: TACTListItem): BOOLEAN;
VAR
   LI:   OccurListItemPntr;
   L:    OccurTypeTACTList;
   LIH:  HRecPntr;
BEGIN
   L := OccurTypeTACTList(List);
   LI := Item.DataRA;
   LI^.CurPos := L^.NumbOccurs - 1;
   GetTokenHRecPntr(L, LI^.CurPos, LIH);
   ChangeOverData(LI^.ToDVA, LIH, L^.HeadVA);
   RETURN TRUE;
END GetLastOccur;

PROCEDURE FindNearestFromPos(List: OccurTypeTACTList;
                             Pos:  HRecPntr;
                         VAR Item: TACTListItem): BOOLEAN;
VAR
   LI:     OccurListItemPntr;
   I,U,L:  CARDINAL;
   LIH:  HRecPntr;
BEGIN
   LI := Item.DataRA;
   L := 1;
   U := List^.NumbOccurs;
   LOOP
      IF U < L THEN
         IF U = 0 THEN LI^.CurPos := 1;
         ELSE LI^.CurPos := U - 1 END;
         GetTokenHRecPntr(List, LI^.CurPos, LIH);
         ChangeOverData(LI^.ToDVA, LIH, List^.HeadVA);
         RETURN FALSE;
      ELSE
         I := (L + U) DIV 2;
         GetTokenHRecPntr(List, I-1, LIH);
         CASE CompareHRecs(Pos, LIH) OF
          -1:   U := I - 1;
         | 1:   L := I + 1;
         | 0:
            LI^.CurPos := I - 1;
            ChangeOverData(LI^.ToDVA, LIH, List^.HeadVA);
            RETURN TRUE;
         END;
      END;
   END;
END FindNearestFromPos;

PROCEDURE FindOccurItem(List:    ADDRESS; (* ignored here *)
                       Data:    VirtAddr; (* as DataItem VA *)
                   VAR Item: TACTListItem): BOOLEAN;
VAR
   Pntr: DataItemPntr;
   rslt: BOOLEAN;
   L:    OccurTypeTACTList;
BEGIN
   L := OccurTypeTACTList(List);
   Pntr := VMAccess(Data);
   IF Pntr^.DataType <> TokenType THEN rslt := FALSE
   ELSE rslt := FindNearestFromPos(L, Pntr^.FilePos, Item) END;
   VMRelease(Data);
   RETURN rslt;
END FindOccurItem;

PROCEDURE OccurItemDataPresent(List:   ADDRESS; (* not used *)
                              Type:   ItemType;
                              Pos:    HRecPntr;
                          VAR Item:   TACTListItem): BOOLEAN;
VAR
   L:    OccurTypeTACTList;
BEGIN
   IF Type <> TokenType THEN RETURN FALSE END;
   L := OccurTypeTACTList(List);
   RETURN FindNearestFromPos(L, Pos, Item);
END OccurItemDataPresent;

PROCEDURE FindOccurFromString(Name:   ARRAY OF CHAR; (* Sort Format *)
                             Type:   ItemType;
                             List:   ADDRESS; (* ignored *)
                         VAR Item:   TACTListItem): BOOLEAN;
BEGIN
   ProgramErrorAndHalt('FindOccurFromString was called');
   RETURN FALSE;
END FindOccurFromString;

PROCEDURE DisposeOccurList(VAR List: ADDRESS);
VAR
   L:    OccurTypeTACTList;
BEGIN
   L := OccurTypeTACTList(List);
   DisposeDataItem(L^.HeadVA);
   DISPOSE(L);
   List := NIL;
END DisposeOccurList;

PROCEDURE InitializeOccurList(HWord: VirtAddr (* DataItem VA*)): TACTList;
VAR TList:   OccurTypeTACTList;
    Data:    DataItemPntr;
    hp:      RealStoragePntr;
BEGIN
   Data := VMModify(HWord);
   IF Data^.DataType <> TypeType THEN
      ProgramErrorAndHalt('Improper DataItem passed to InitOccurList')
   END;
   MarkAsUsed(Data); (* cleared by DisposeDataItem in DisposeOccurList *)
   NEW(TList);
   WITH TList^ DO
      LDataSize := SIZE(OccurTypeTACTListData);
      BaseData := ADR(OfficialOccurListData);
      Type := OccurrenceList;
      HeadVA := HWord;
      NumbOccurs := Data^.TypeFileData.NoOccur;
      OccurStart.Rec := Data^.FilePos.Rec ;	(* Occur data now proceeds TypeRec info *)
      GetBaseHyper( OccurStart.Rec, hp, TDBFile);	(* get the data *)
      OccurStart.Idx := hp^.HRecord.DataPntr[ Data^.FilePos.Idx ] - OccurRecSize ;
      IF OccurStart.Idx < (4 + 2 * hp^.HRecord.NoDataPtrsUsed) THEN
	 (* Occur data starts on next record *)
	 INC( OccurStart.Rec ) ;
	 OccurStart.Idx := TypeMaxDataPos - OccurRecSize ;
	 MaxOccurs := MaxSpaceForOccursInRec ;
      ELSE
	 MaxOccurs := (OccurStart.Idx - (4 + 2 * hp^.HRecord.NoDataPtrsUsed)) DIV OccurRecSize ;
      END ;	
      IF MaxOccurs > NumbOccurs THEN  MaxOccurs := NumbOccurs  END ;
      ReleaseBaseHyper( TDBFile, hp );
   END;
   VMRelease(HWord);
   RETURN TACTList(TList);
END InitializeOccurList;

PROCEDURE IncOccurListUsage(List: TACTList);
VAR
   L:    OccurTypeTACTList;
   Pntr: DataItemPntr;
BEGIN
   L := OccurTypeTACTList(List);
   Pntr := VMModify(L^.HeadVA);
   MarkAsUsed(Pntr);
   VMRelease(L^.HeadVA);
END IncOccurListUsage;

BEGIN
   WITH OfficialOccurListData DO
      NewItemProc :=      NewOccurListItem;
      DispListItemProc := DisposeOccurListItem;
      DisposeListProc :=  DisposeOccurList;
      GetItemDataProc :=  GetOccurItemData;
      ReleaseItemProc:=   ReleaseOccurItemHold;
      GetFirstItemProc := GetFirstOccur;
      GetLastItemProc  := GetLastOccur;
      GetNextItemProc :=  GetNextOccur;
      GetPrevItemProc :=  GetPrevOccur;
      FindItemProc :=     FindOccurItem;
      ItemDataPresProc := OccurItemDataPresent;
      FindFromStrProc :=  FindOccurFromString;
      CopyListItemProc := CopyOccurListItem;
   END;
END OccurListModule.
