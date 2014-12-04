IMPLEMENTATION MODULE PositionManagement;

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

(*
Ver 1.11
 - Sept. 5, 1989  L.Presutti
   Added GetParentMainItem procedure.
*)

FROM MemoryManagement IMPORT ALLOCATE,DEALLOCATE;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ListData IMPORT
  (* types *) ItemType, DataItemPntr, StringPntr,
  (* procs *) CompareDataItems, MarkAsUsed, MakeStringData;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, DiscardList, GetItemData,
              CopyListItem, GetFirstItem, GetLastItem, GetNextItem,
              GetPrevItem, ReleaseItemHold, GetListType, FindItem;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteChar;
FROM KeyTranslation IMPORT
  (* Const *) IntEnhOn, IntEnhOff;
FROM RefValBase IMPORT
  (* Procs *) CreateRef,
  (* Var *)   LastDisplayWordCountWord ;
FROM WordBase IMPORT
  (* Proc  *) SortToIntWord;
FROM TACTDataServices IMPORT
  (* procs *) GetTokensForType, DisposeDataItem, VirtToTACTList, TACTListToVirt ;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) CopyFromVirtMem, CopyToVirtMem, VMAccess, VMRelease,
              VMMarkChanged,VirtToPool;
FROM OccurListModule IMPORT
     InitializeOccurList;

CONST
(* When Number of tokens in type is more than MaxTokensToLoad they are >not<
   automatically loaded into VirtMem -- instead, an OccurrenceList
   is created to read them directly -- one by one -- from the TDB *)
     MaxTokensToLoad = 30;
TYPE
   PositionItem = POINTER TO DisplayPointer;
   DisplayPointer = RECORD
      ThisList:     TACTList;
      ThisItem:     TACTListItem;
      ThisData:     VirtAddr; (* VA to DataItem *)
      ThisType:     ItemType;
      SubPntr:      PositionItem;
   END;
   FindPosProcType = PROCEDURE(TACTList, VAR TACTListItem): BOOLEAN;


PROCEDURE IllegalListData;
BEGIN
   ProgramErrorAndHalt('Illegal DataType in List')
END IllegalListData;

PROCEDURE GetPntrData(VAR Pointer: PositionItem;
                          TList:   TACTList;
                          PosProc: FindPosProcType): BOOLEAN;
VAR
   TPntr:    TACTListItem;
   TData:    DataItemPntr;
   Temp:     PositionItem;
BEGIN
   Temp := Pointer;
   NewListItem(TList,TPntr);
   IF NOT PosProc(TList,TPntr) THEN
      DisposeListItem(TList,TPntr);
      IF Pointer <> NIL THEN  DiscardList(TList);  END;
      RETURN FALSE
   END;
   NEW(Pointer);
   WITH Pointer^ DO
      GetItemData(TList,TPntr, ThisData, TData);
      ThisList := TList;
      ThisItem := TPntr;
      ThisType := TData^.DataType;
      SubPntr := Temp;
      ReleaseItemHold(ThisList, ThisItem);
   END;
   RETURN TRUE;
END GetPntrData;

PROCEDURE CreateSubPntr(VAR Pointer:   PositionItem;
                            PosProc:   FindPosProcType): BOOLEAN;
VAR
   TList:    TACTList;
   TData:    DataItemPntr;
BEGIN
   TData := VMAccess(Pointer^.ThisData);
   VirtToTACTList(TData^.Contents, TList);
   VMRelease(Pointer^.ThisData);
   RETURN GetPntrData(Pointer, TList, PosProc);
END CreateSubPntr;

PROCEDURE PopSubPntr(VAR Pntr: PositionItem);
VAR tPntr:  PositionItem;
BEGIN
   tPntr := Pntr^.SubPntr;
   DisposeListItem(Pntr^.ThisList,Pntr^.ThisItem);
   (* IF (tPntr <> NIL) AND (GetListType(Pntr^.ThisList) = MemoryList) THEN *)
   IF (tPntr <> NIL) THEN
      DiscardList(Pntr^.ThisList);
   END;
   DISPOSE(Pntr);
   Pntr := tPntr;
END PopSubPntr;

PROCEDURE GetPosData(Pointer:   PositionItem;
                 VAR Type:      ItemType;
                 VAR TokenVA:   VirtAddr; (* VA for DataItem *)
                 VAR TypeVA:    VirtAddr; (* VA for DataItem *)
                 VAR CatVA:     VirtAddr  (* VA for DataItem *) );
BEGIN
   TokenVA := NILVirt;
   TypeVA := NILVirt;
   CatVA := NILVirt;
   WHILE Pointer <> NIL DO
      Type := Pointer^.ThisType;
      WITH Pointer^ DO
         CASE Type OF
           CatType:   CatVA := ThisData
         | TypeType:  TypeVA := ThisData
         | TokenType: TokenVA := ThisData
         ELSE
            IllegalListData
         END;
      END;
      Pointer := Pointer^.SubPntr;
   END;
END GetPosData;

PROCEDURE GetTokenDataList(VAR VA:    VirtAddr; (* VA of DataItem *)
                           VAR TList: TACTList);
VAR  tData:  DataItemPntr;
BEGIN
   tData := VMAccess(VA);
   WITH tData^ DO
      IF Contents <> NILVirt THEN VirtToTACTList(Contents, TList)
      ELSIF TypeFileData.NoOccur > MaxTokensToLoad THEN
         TList := InitializeOccurList(VA);
         TACTListToVirt(TList, VirtToPool(VA), Contents);
         VMMarkChanged(VA);
      ELSE
         GetTokensForType(VA);
         VirtToTACTList(tData^.Contents, TList);
         VMMarkChanged(VA);
      END;
   END;
   VMRelease(VA);
END GetTokenDataList;

PROCEDURE SetupContents(Pointer: PositionItem);
VAR
   TList:       TACTList;
   ThisPntr:    DataItemPntr;
BEGIN
   ThisPntr := VMAccess(Pointer^.ThisData);
   WITH ThisPntr^ DO
      Pointer^.ThisType := DataType;
      IF Contents <> NILVirt THEN (* do nothing *)
      ELSIF DataType <> TypeType THEN IllegalListData (* can do nothing *)
      ELSE
         GetTokenDataList(Pointer^.ThisData, TList);
         IF GetListType(TList) = MemoryList THEN DiscardList(TList);  END;
      END;
   END;
   VMRelease(Pointer^.ThisData);
END SetupContents;

PROCEDURE NewListItemBackward(VAR Pointer: PositionItem): BOOLEAN;
VAR ThisPntr:    DataItemPntr;
BEGIN
   WHILE Pointer^.ThisType <> TokenType DO
      SetupContents(Pointer);
      IF NOT CreateSubPntr(Pointer,GetLastItem) THEN RETURN FALSE END;
   END;
   RETURN TRUE;
END NewListItemBackward;

PROCEDURE FirstDisplayItem(List:    TACTList;
                       VAR Pointer: PositionItem): BOOLEAN;
BEGIN
   IF Pointer <> NIL THEN ProgramErrorAndHalt('NonNil Position Pntr') END;
   RETURN GetPntrData(Pointer, List, GetFirstItem);
END FirstDisplayItem;

PROCEDURE LastDisplayItem(List:    TACTList;
                      VAR Pointer: PositionItem): BOOLEAN;
BEGIN
   IF Pointer <> NIL THEN ProgramErrorAndHalt('NonNil Position Pntr') END;
   RETURN GetPntrData(Pointer, List, GetLastItem);
END LastDisplayItem;

PROCEDURE CopyDisplayItem(List:     TACTList;
                         PntrIn:    PositionItem;
                     VAR PntrOut:   PositionItem);
VAR tPntr:   PositionItem;
    tPntr2:  PositionItem;
    tPntr3:  PositionItem;
    tData:   DataItemPntr;
BEGIN
   PntrOut := NIL;
   tPntr := PntrIn;
   tPntr2 := NIL;
   WHILE tPntr <> NIL DO
      NEW(tPntr3);
      tPntr3^ := tPntr^; (* copy OK here -- full size allocated *)
      WITH tPntr3^ DO;
(*	 IF (SubPntr <> NIL) AND (GetListType( tPntr^.ThisList ) = MemoryList) THEN *)
	 IF (SubPntr <> NIL) THEN
	    tData := VMAccess( SubPntr^.ThisData ) ;
	    VirtToTACTList( tData^.Contents, ThisList ) ;
	    VMRelease( SubPntr^.ThisData ) ;
	 END ;
         CopyListItem(ThisList,tPntr^.ThisItem,ThisItem);
         SubPntr := NIL;
      END;
      IF tPntr2 <> NIL THEN tPntr2^.SubPntr := tPntr3
      ELSE PntrOut := tPntr3 END;
      tPntr2 := tPntr3;
      tPntr := tPntr^.SubPntr;
   END;
END CopyDisplayItem;

PROCEDURE DiscardDisplayItem(List:  TACTList; VAR Pntr:  PositionItem);
BEGIN
   WHILE Pntr <> NIL DO
      PopSubPntr( Pntr ) ;
   END;
END DiscardDisplayItem;

PROCEDURE InitialDisplayItem(VAR Pntr:  PositionItem);
BEGIN
   Pntr := NIL;
END InitialDisplayItem;

PROCEDURE NextDisplayItem(List:    TACTList;
                       VAR Pointer: PositionItem): BOOLEAN;
VAR
   finished:      BOOLEAN;
   finished2:     BOOLEAN;
   tPntr:         PositionItem;
   TData:         DataItemPntr;
   tType:         ItemType;
BEGIN
   IF Pointer = NIL THEN RETURN FALSE END;
   finished := TRUE;
   tType := Pointer^.ThisType;
   REPEAT
     IF tType = TokenType THEN
        REPEAT
           WITH Pointer^ DO
              IF GetNextItem(ThisList,ThisItem) THEN
                 GetItemData(ThisList,ThisItem, ThisData, TData);
                 ThisType := TData^.DataType;
                 ReleaseItemHold(ThisList, ThisItem);
                 finished2 := TRUE;
              ELSIF SubPntr = NIL THEN
                 finished2 := NewListItemBackward(Pointer);
                 RETURN FALSE
              ELSE
                 PopSubPntr(Pointer);
                 finished2 := FALSE;
              END;
           END;
        UNTIL finished2;
     ELSE
        SetupContents(Pointer);
        finished := CreateSubPntr(Pointer,GetFirstItem);
     END;
   UNTIL finished;
   RETURN TRUE;
END NextDisplayItem;

PROCEDURE PrevDisplayItem(List:    TACTList;
                       VAR Pointer: PositionItem): BOOLEAN;
VAR
   finished:      BOOLEAN;
   TData:         DataItemPntr;
BEGIN
   IF Pointer = NIL THEN RETURN FALSE END;
   REPEAT
      WITH Pointer^ DO
        IF GetPrevItem(ThisList,ThisItem) THEN
           GetItemData(ThisList, ThisItem, ThisData, TData);
           ThisType := TData^.DataType;
           ReleaseItemHold(ThisList, ThisItem);
        ELSE
           IF SubPntr <> NIL THEN
              PopSubPntr(Pointer);
              RETURN TRUE
           END;
           RETURN FALSE
        END;
      END;
      finished := NewListItemBackward(Pointer);
   UNTIL finished;
   RETURN TRUE;
END PrevDisplayItem;

PROCEDURE GenMainItem( List : TACTList; VAR Pointer : PositionItem;
                       PosProc: FindPosProcType): BOOLEAN ;
VAR
   TData:         DataItemPntr;
BEGIN
   IF Pointer = NIL THEN RETURN FALSE END;
   WITH Pointer^ DO
      IF (SubPntr <> NIL) AND (ThisType = TokenType) THEN
	 PopSubPntr(Pointer);
      END;
   END ;
   WITH Pointer^ DO
      IF NOT PosProc(ThisList,ThisItem) THEN RETURN FALSE END;
      GetItemData(ThisList, ThisItem, ThisData, TData);
      ThisType := TData^.DataType;
      ReleaseItemHold(ThisList, ThisItem);
   END;
   RETURN TRUE;
END GenMainItem;

PROCEDURE GetParentMainItem( List : TACTList; VAR Pointer : PositionItem) ;
BEGIN

(* check this with the old version! j.b. *)

   IF Pointer = NIL THEN RETURN END;
   WITH Pointer^ DO
      IF (SubPntr <> NIL) AND (ThisType = TokenType) THEN
	 PopSubPntr(Pointer);
      END;
   END;
END GetParentMainItem;

PROCEDURE PrevMainItem(List:    TACTList;
                   VAR Pointer: PositionItem): BOOLEAN;
BEGIN
   RETURN GenMainItem( List, Pointer, GetPrevItem);
END PrevMainItem;

PROCEDURE NextMainItem(List:    TACTList;
                   VAR Pointer: PositionItem): BOOLEAN;
BEGIN
   RETURN GenMainItem( List, Pointer, GetNextItem);
END NextMainItem;

PROCEDURE FindDisplayItem(ListIn:    TACTList;
                          PointerIn: PositionItem;
                          ListOut:   TACTList;
                      VAR PointerOut:PositionItem): BOOLEAN;
VAR
   LookForVA:   VirtAddr; (* VA for LookFor *)
   dummy:       PositionItem;
   result:      INTEGER;
   bresult:     BOOLEAN;

   (* The following code assumes that the items in the list are
      maintained in the following order:
      (1) All Category entries first
      (2) All Type entries next -- with Position entries in position
          order
      (3) All Position entries last, with all of those in position order
                   .... j.b. *)

PROCEDURE LocateFirstPos(tVA: VirtAddr; (* input DataItem *)
                     VAR RVA: VirtAddr  (* output DataItem *) ): BOOLEAN;
VAR tList:   TACTList;
    tItem:   TACTListItem;
    temp:    DataItemPntr;
    tData:   DataItemPntr;
BEGIN
   tData := VMAccess(tVA);
   RVA := tVA;
   WITH tData^ DO
      IF DataType = TokenType THEN
	 VMMarkChanged(tVA);
	 MarkAsUsed(tData);
	 VMRelease(tVA);
         RETURN TRUE;
      ELSIF (Contents <> NILVirt) THEN
         VirtToTACTList(tData^.Contents, tList);
      ELSIF (DataType = TypeType) THEN
         GetTokenDataList(tVA, tList);
      ELSE
	 ProgramErrorAndHalt('Failure (1) in LocateFirstPos')
      END;
   END;
   NewListItem(tList, tItem);
   IF NOT GetFirstItem(tList, tItem) THEN
	ProgramErrorAndHalt('Failure (2) in LocateFirstPos')
   END;
   VMRelease(tVA);
   GetItemData(tList,tItem, RVA, tData);
   VMMarkChanged(RVA);
   MarkAsUsed(tData);
   ReleaseItemHold(tList, tItem);
   DisposeListItem(tList, tItem);
(*   IF GetListType(tList) = MemoryList THEN  DiscardList(tList);  END; *)
   DiscardList(tList);
   RETURN TRUE
END LocateFirstPos;

PROCEDURE TryList(tList:   TACTList;
              VAR bottom:  PositionItem;
              VAR Result:  PositionItem): BOOLEAN;
VAR
    sList:   TACTList;
    tItem:   TACTListItem;
    tData:   DataItemPntr;
    t2:      PositionItem;
    DVA:     VirtAddr;

PROCEDURE MakePosItem(VAR Result: PositionItem);
VAR TData:   DataItemPntr;
BEGIN
   NEW(Result);
   WITH Result^ DO
      ThisList := tList;
      ThisItem := tItem;
      ThisData := DVA;
      GetItemData(ThisList,ThisItem, ThisData, TData);
      ThisType := TData^.DataType;
      ReleaseItemHold(ThisList, ThisItem);
      SubPntr := NIL;
   END;
END MakePosItem;

BEGIN
   NewListItem(tList,tItem);
   IF NOT GetFirstItem(tList, tItem) THEN
      DisposeListItem(tList,tItem);
      RETURN FALSE
   END;
   REPEAT
      GetItemData(tList, tItem, DVA, tData);
      CASE tData^.DataType OF
        CatType:
           VirtToTACTList(tData^.Contents, sList);
           IF TryList(sList,t2,Result) THEN
              MakePosItem(bottom);
              t2^.SubPntr := bottom;
              ReleaseItemHold(tList, tItem);
              RETURN TRUE;
           END;
(*	   IF GetListType( sList ) = MemoryList THEN  DiscardList(sList)  END ; *)
	   DiscardList(sList) ;
      | TypeType:
           GetTokenDataList(DVA, sList);
           IF TryList(sList,t2,Result) THEN
              ReleaseItemHold(tList, tItem);
              MakePosItem(bottom);
              t2^.SubPntr := bottom;
              RETURN TRUE;
           END;
(*	   IF GetListType( sList ) = MemoryList THEN  DiscardList(sList)  END ;*)
	   DiscardList(sList) ;
      | TokenType:
	   ReleaseItemHold(tList, tItem);
           bresult := FindItem(tList, LookForVA, tItem);
           IF bresult THEN
              MakePosItem(Result);
              bottom := Result;
              RETURN TRUE
           ELSE
	      DisposeListItem(tList,tItem);
              RETURN FALSE
           END;
      ELSE
           IllegalListData
      END;
      ReleaseItemHold(tList, tItem);
   UNTIL NOT GetNextItem(tList, tItem);
   DisposeListItem(tList,tItem);
   RETURN FALSE;
END TryList;

BEGIN
   IF PointerIn = NIL THEN RETURN FALSE END;
   IF NOT LocateFirstPos(PointerIn^.ThisData,LookForVA) THEN bresult := FALSE
   ELSE bresult := TryList(ListOut,dummy,PointerOut) END;
   DisposeDataItem(LookForVA);
   RETURN bresult;
END FindDisplayItem;

PROCEDURE PrepareDisplayForItem(Pntr:   PositionItem;
                                NoLvls: CARDINAL;
                                RefIn:  ARRAY OF CHAR;
                                RefLn:  CARDINAL;
                            VAR tStr:   ARRAY OF CHAR);
VAR
   SPntr:     StringPntr;
   TString:   ARRAY[0..80] OF CHAR;
   cLvl:      CARDINAL;
   LP:        CARDINAL;
   TempLen:   CARDINAL;
   tPos:      PositionItem;
   tData:     DataItemPntr;
   tVA:       VirtAddr;
BEGIN
   tStr[0] := 0C;
   LP := 0;
   cLvl := 1;
   IF NoLvls < 1 THEN NoLvls := 1 END;
   tPos := Pntr;
   WHILE (cLvl <= NoLvls) AND (tPos <> NIL) DO
      IF cLvl = 1 THEN SWriteString(tStr,LP,IntEnhOn,0)
      ELSE SWriteString(tStr,LP,', ',0) END;

      GetItemData(Pntr^.ThisList,Pntr^.ThisItem, tVA, tData);

      WITH tData^ DO
         CASE DataType OF
           CatType:
	      SortToIntWord(CatName, TString);
              SWriteChar(tStr,LP,'@',0);
              SWriteString(tStr,LP,TString,0);
              IF cLvl = 1 THEN SWriteChar(tStr,LP,IntEnhOff,0) END;
         | TypeType:
              (* GetTypeIntName(tVA, TString); <-- why have this ?? *)
	      SortToIntWord(TypeFileData.Word, TString );
              SWriteString(tStr,LP,TString,0);
              IF cLvl = 1 THEN SWriteChar(tStr,LP,IntEnhOff,0) END;
              SWriteString(tStr,LP,' (',0);
              IF (NoContents <> 0) AND (NoContents <> TypeFileData.NoOccur) THEN
                 SWriteCard(tStr,LP,NoContents,0);
                 SWriteChar(tStr,LP,'/',0);
              END;
              SWriteCard(tStr,LP,TypeFileData.NoOccur,0);
              SWriteChar(tStr,LP,')',0);
         | TokenType:
              CreateRef( RefIn, RefLn, tVA, TString, TempLen, LastDisplayWordCountWord);
              SWriteString(tStr,LP,TString,0);
              IF cLvl = 1 THEN SWriteChar(tStr,LP,IntEnhOff,0) END;
         ELSE
           IllegalListData
         END;
      END;
      tPos := tPos^.SubPntr;
      INC(cLvl);
      ReleaseItemHold(Pntr^.ThisList,Pntr^.ThisItem);
   END;
END PrepareDisplayForItem;

END PositionManagement.
