IMPLEMENTATION MODULE TACTDataServices;

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

IMPORT Lib, Str;
FROM SYSTEM IMPORT TSIZE, ADR;
FROM ErrorBase IMPORT
  (* procs *) ProgramErrorAndHalt;
FROM HyperBase IMPORT
(*  (* TYPE *)  HRecPntr,	<------------ ??????   *)
  (* PROC *)  GetBaseHyper, ReleaseBaseHyper;
FROM DBData IMPORT TDBFile, BeginToken, EndTypeRec;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo;
FROM HyperDataModel IMPORT
  (* Const *) HNoOccurs, OccurRecSize, TypeMaxDataPos,
  (* Types *) HRecPntr, HOccurData, TDBTypeData, TDBTypePntr ;
FROM ListData IMPORT
  (* types *) ItemType, DataItemPntr,
  (* procs *) ReleaseStringData, MakeTDBTypeDataItem, MakeTokenDataItem,
              MarkAsUsed, ReleaseRealStringData ;
FROM TypeBase IMPORT
  (* types *) HTypeHandle;
FROM TypeListModule IMPORT
   OfficialTypeListData;
FROM RuleListModule IMPORT
     OfficialRuleListData;
FROM RefNameListModule IMPORT
   OfficialRefNameListData;
FROM RefStrListModule IMPORT
   OfficialRefStrListData;
FROM OccurListModule IMPORT
   OfficialOccurListData, IncOccurListUsage;
FROM TokenBase IMPORT
  (* types *) HTokenHandle,
  (* procs *) GetToken, FreeTokenHandle, DecompressTokenInfo;
FROM MemoryManagement IMPORT
  ALLOCATE, RealStoragePntr;
FROM GlobalDefs IMPORT StrAny;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem, TACTListBaseData,
  (* procs *) NewListItem, GetFirstItem, DiscardList, DisposeListItem,
              GetItemData, ReleaseItemHold ;
FROM SelectWindow IMPORT
  (* proc *) DoSelectWindow;
FROM MemTACTList IMPORT
  (* vars  *)  OfficialMemTACTListBaseData,
  (* procs *)  NewMemoryList, CopyList, InsertListItem, IncrementListUsage;
FROM WordBase IMPORT SortToIntWord;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) VMModify, VMRelease, VMMarkChanged, GetSpace, FreeSpace, RealToPool,
              VMAccess, VirtToPool,CopyFromVirtMem;
FROM WordBase IMPORT
  (* Procs *) IntToSortWord, SortToIntWord;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames,
   (* procs *) LookupRefName;
FROM RefNameListModule IMPORT MakeTACTRefNameList;
FROM ResMessages IMPORT
   (*proc*) MsgString, ResAskUser;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;

VAR
    RefNmeSelectWind:    WindowInfo;

PROCEDURE GetTokensForType(TypeRecVA:   VirtAddr);
    VAR
	DataPos, PtrLen	: INTEGER ;
	OccurPtr: POINTER TO HOccurData ;
	J	: CARDINAL;
	orec	: CARDINAL;
	temp	: DataItemPntr;
	tList	: TACTList;

	TypeRec	: DataItemPntr;
	hp	: RealStoragePntr;
	PoolNo	: CARDINAL;
	TokVA	: VirtAddr; (* VA for Token type DataItemPntr *)

    BEGIN
	TypeRec := VMModify(TypeRecVA);
	IF TypeRec^.DataType <> TypeType THEN
	   ProgramErrorAndHalt('GetTokensForType called without TypeType');
	END;
	IF TypeRec^.Contents <> NILVirt THEN
	   VMRelease(TypeRecVA);
	   RETURN
	END;

	PoolNo := RealToPool(TypeRec);
	tList := NewMemoryList(PoolNo);

	orec := TypeRec^.FilePos.Rec ; (* occurences are on same rec as type *)
	GetBaseHyper(orec, hp, TDBFile);
	WITH TypeRec^.TypeFileData DO
	     TypeRec^.NoContents := NoOccur;
	     DataPos := INTEGER( hp^.HRecord.DataPntr[TypeRec^.FilePos.Idx] ) ;
	     PtrLen  := 4 + 2 * hp^.HRecord.NoDataPtrsUsed ;
	     J := 0 ;
	     LOOP
		INC( J ) ;
		IF J > NoOccur THEN  EXIT  END ;
		DEC( DataPos, OccurRecSize ) ;
		IF DataPos < INTEGER( PtrLen ) THEN
		   DataPos := TypeMaxDataPos - OccurRecSize ;
		   INC( orec ) ;
		   IF orec <= EndTypeRec THEN
			ReleaseBaseHyper(TDBFile,hp);
			GetBaseHyper(orec,hp,TDBFile);
		   ELSE	(* not done yet and no more recs ??? *)
			ProgramErrorAndHalt( 'TactData: Insuficient Occur items found.' ) ;
		   END ;
		   IF hp^.HRecord.NoDataPtrsUsed > 0 THEN
			PtrLen := 4 + 2 * hp^.HRecord.NoDataPtrsUsed
		   ELSE	(* occupies full record!! *)
			PtrLen := 2
		   END ;
		END ;
		(* from occurrence record, get position of token record *)
		OccurPtr := ADR( hp^.HRecord.TextData[DataPos] ) ;
		MakeTokenDataItem(TokVA, PoolNo, temp);
		temp^.FilePos.Rec := OccurPtr^.TRecNo + BeginToken;
		temp^.FilePos.Idx := ORD(OccurPtr^.TRecPos);
		temp^.HeadWord := TypeRecVA;
		VMRelease( TokVA ) ;
		IF NOT InsertListItem(TokVA,tList) THEN
		   ProgramErrorAndHalt('Could not insert in occur list')
		END;
		MarkAsUsed(TypeRec);
	     END ;
	     ReleaseBaseHyper(TDBFile,hp);
	END;

	TACTListToVirt(tList,PoolNo,TypeRec^.Contents);
	DiscardList(tList);
	VMRelease(TypeRecVA);

    END GetTokensForType;

PROCEDURE AllocTypeData(DataPos:  HTypeHandle;
                        FilePos:  HRecPntr;
                        Pool:     CARDINAL;
                    VAR VA:       VirtAddr;
                    VAR Pntr:     DataItemPntr);
BEGIN
    MakeTDBTypeDataItem(DataPos^^,Pool, VA,Pntr);
    Pntr^.FilePos := FilePos;
(*    VMRelease(VA); *)
END AllocTypeData;

PROCEDURE GetTDBTokenData(Pntr:     DataItemPntr);
VAR
   Handle:    HTokenHandle;
BEGIN
   GetToken(Pntr^.FilePos,Handle);
   DecompressTokenInfo(Handle,Pntr^.TokenFileData);
   Pntr^.TokenDataLoaded := TRUE;
   FreeTokenHandle(Handle);
END GetTDBTokenData;

PROCEDURE GetTypeIntName(DVA:   VirtAddr; (* to Type DataItem *)
                     VAR TypeStr : ARRAY OF CHAR );
VAR
   DPntr:     DataItemPntr;
BEGIN
   DPntr := VMAccess(DVA);
   WITH DPntr^ DO
      IF DataType <> TypeType THEN ProgramErrorAndHalt('Error in GetTypeIntName') END;
      SortToIntWord(DPntr^.TypeFileData.Word, TypeStr );
   END;
   VMRelease(DVA);
END GetTypeIntName;

PROCEDURE InsertDataItemContentsInList(VA:  VirtAddr (* to DataItem *);
                                       Li:  TACTList (* List to receive *) );
VAR
   DP:      DataItemPntr;
   TList:   TACTList;
BEGIN
   DP := VMAccess(VA);
   IF DP^.Contents = NILVirt THEN
      ProgramErrorAndHalt('InsertDataItemContentsInList Failed');
   END;
   VirtToTACTList(DP^.Contents, TList);
   VMRelease(VA);
   CopyList(TList, Li);
   DiscardList(TList);
END InsertDataItemContentsInList;
(* ==================================== *)

PROCEDURE LocalVirtToTACTList(VA : VirtAddr; VAR TList: TACTList; Increment : BOOLEAN);
VAR Pntr:   TACTList;
BEGIN
   IF VA = NILVirt THEN
      ProgramErrorAndHalt('NILVirt given to VirtToTACTList');
   END;
   Pntr := VMAccess( VA ) ;
   ALLOCATE( TList, Pntr^.LDataSize );
   Lib.Move(Pntr, TList, Pntr^.LDataSize);
   IF Increment THEN
	IF (TList^.Type = MemoryList) OR (TList^.Type = CatList) THEN IncrementListUsage(TList)
	ELSIF (TList^.Type = OccurrenceList) THEN IncOccurListUsage(TList) END;
   END ;
   VMRelease( VA ) ;
   WITH TList^ DO
      CASE Type OF
        MemoryList,
        FileNameList,
        CatList:        BaseData := ADR(OfficialMemTACTListBaseData);
      | TypeList:       BaseData := ADR(OfficialTypeListData);
      | OccurrenceList: BaseData := ADR(OfficialOccurListData);
      | RuleList:       BaseData := ADR(OfficialRuleListData);
      | RefNameList:    BaseData := ADR(OfficialRefNameListData);
      | RefStrList:     BaseData := ADR(OfficialRefStrListData);
        ELSE
           ProgramErrorAndHalt('VirtToTACTList: bad Type');
      END;
   END;
END LocalVirtToTACTList;

PROCEDURE VirtToTACTList(VA : VirtAddr; VAR TList : TACTList);
    BEGIN
	LocalVirtToTACTList(VA, TList, TRUE );
    END VirtToTACTList;

PROCEDURE TACTListToVirt(TList: TACTList;
                         Pool:  CARDINAL;
                     VAR VA:    VirtAddr);
VAR
   vList:    TACTList;
BEGIN
   vList := GetSpace(TList^.LDataSize, Pool, VA);
   Lib.Move(TList,vList,TList^.LDataSize);
   IF (TList^.Type = MemoryList) OR (TList^.Type = CatList) THEN IncrementListUsage(TList) END;
   VMRelease(VA);
END TACTListToVirt;

PROCEDURE RemoveVirtTACTList(VAR VA:  VirtAddr);
VAR
   TList:     TACTList;
   LDataSize: CARDINAL;
BEGIN
   LocalVirtToTACTList(VA, TList, FALSE);  (* don't increment usage count of temp TACTList *)
   LDataSize := TList^.LDataSize;
   DiscardList(TList);
   FreeSpace(VA, LDataSize);
   VA := NILVirt;
END RemoveVirtTACTList;

(* ==================================== *)

PROCEDURE DisposeDataItem(VAR VA:    VirtAddr);
VAR
   Pntr:   DataItemPntr;

PROCEDURE DisposeTypeData(Pntr: DataItemPntr);
VAR tList:  TACTList;
BEGIN
   WITH Pntr^ DO
      IF UsageCount = NoContents+1 THEN
         IF Contents <> NILVirt THEN
            RemoveVirtTACTList(Contents);
            NoContents := 0;
         END;
      END;
      DEC(UsageCount);
   END;
END DisposeTypeData;

PROCEDURE DisposeTokenData(VAR Pntr:  DataItemPntr);
VAR
   head:    VirtAddr;
BEGIN
   DEC(Pntr^.UsageCount);
   IF Pntr^.UsageCount = 0 THEN
      IF Pntr^.Contents <> NILVirt THEN
         RemoveVirtTACTList(Pntr^.Contents);
         Pntr^.NoContents := 0;
      END;
      IF Pntr^.HeadWord <> NILVirt THEN
         head := Pntr^.HeadWord;
         Pntr^.HeadWord := NILVirt; (* to avoid deletion loops *)
         DisposeDataItem(head);
      END;
   END;
END DisposeTokenData;

PROCEDURE DisposeRefStrData( VAR Data : DataItemPntr);
BEGIN
   WITH Data^ DO
      DEC(UsageCount);
      IF UsageCount = 0 THEN
         IF Contents <> NILVirt THEN
            RemoveVirtTACTList(Contents);
            NoContents := 0;
         END;
	 IF IntStrVA  <> NILVirt THEN ReleaseStringData( IntStrVA ) END ;
         IF SortStrVA <> NILVirt THEN ReleaseStringData( SortStrVA ) END ;
      END ;
   END;
END DisposeRefStrData ;

PROCEDURE DisposeRuleData(VAR Pntr: DataItemPntr);
BEGIN
   WITH Pntr^ DO
      DEC(UsageCount);
      IF UsageCount = 0 THEN
         IF Contents <> NILVirt THEN
            RemoveVirtTACTList(Contents);
            NoContents := 0;
         END;
         IF RuleName <> NIL THEN ReleaseRealStringData( RuleName ) END ;
         IF SortRuleName <> NIL THEN ReleaseRealStringData( SortRuleName ) END ;
         IF RuleLine <> NIL THEN ReleaseRealStringData( RuleLine ) END ;
      END;
   END;
END DisposeRuleData;

PROCEDURE DisposeGenericData(VAR Pntr:  DataItemPntr);
BEGIN
   WITH Pntr^ DO
      DEC(UsageCount);
      IF UsageCount = 0 THEN
        IF Contents <> NILVirt THEN
           RemoveVirtTACTList(Contents);
           NoContents := 0;
        END;
     END;
   END;
END DisposeGenericData;

BEGIN
     IF VA = NILVirt THEN RETURN END;
     Pntr := VMModify(VA);
     CASE Pntr^.DataType OF
       TypeType:      DisposeTypeData(Pntr)
     | TokenType:     DisposeTokenData(Pntr)
     | RefStringType: DisposeRefStrData(Pntr)
     | RuleType:      DisposeRuleData(Pntr)
     | RefNameType,
       FileNameType,
       DistDataItemType,
       ColDataItemType,
       CatType:	      DisposeGenericData(Pntr)
     ELSE ProgramErrorAndHalt('Data Type Not Supported for deletion!') END;

     IF Pntr^.UsageCount = 0 THEN
        Pntr^.DataType := AnyType; (* any other pointer to same will now fail j.b. *)
        FreeSpace(VA, Pntr^.ItemSize);
     END;
     VMRelease(VA);
     VA := NILVirt;
END DisposeDataItem;

(* ======================= *)

PROCEDURE DoRefSelectionWindow(VAR RetID:     INTEGER;
                               VAR RetName:   ARRAY OF CHAR): BOOLEAN;
VAR
   ch:         CHAR;
   RNList:     TACTList;
   DummyList:  TACTList;
   DummyList2: TACTList;
   SelectItem: TACTListItem;
   DPtr:       DataItemPntr;
   DVA:        VirtAddr;
   FunctKey:   BOOLEAN;
   BDummy:     BOOLEAN;
BEGIN
   RNList := MakeTACTRefNameList();
   NewListItem(RNList,SelectItem);
   IF NOT GetFirstItem(RNList,SelectItem) THEN
       ProgramErrorAndHalt('Error in DoRefSelectionWindow')
   END;

   IF NOT DoSelectWindow(RefNmeSelectWind,
                        RNList, DummyList, DummyList2, 0 (* PoolNo not used *),
                        SelectItem, ch, FunctKey,BDummy,TRUE) THEN
	DisposeListItem( RNList, SelectItem );
	DiscardList( RNList );
	RETURN FALSE
   END;

(* SelectItem points at item selected. *)

   IF GetPanelControlKey(FunctKey, ch) <> PanelCancel THEN
      GetItemData(RNList,SelectItem, DVA, DPtr);
      WITH RefsNameListPntr^[DPtr^.FilePos.Idx]^ DO
         RetID := ID;
         SortToIntWord(Name,RetName);
      END;
      ReleaseItemHold(RNList, SelectItem);
   END;

   DisposeListItem(RNList,SelectItem);
   DiscardList(RNList);
   RETURN TRUE;
END DoRefSelectionWindow;


PROCEDURE GeneralUnitNameVerify(VAR UnitName: ARRAY OF CHAR;
                                VAR UnitID:   INTEGER;
                                VAR ReDisplay:BOOLEAN;
                                VAR ReEdit:   BOOLEAN);
VAR T:  ARRAY[0..39] OF CHAR;
    i:  CARDINAL;
    ch: CHAR;
    Empty: BOOLEAN;
BEGIN
   ReDisplay := FALSE;
   ReEdit := FALSE;

   Empty := TRUE;
   i := 0;
   WHILE (Empty) AND (i <= HIGH(UnitName)) AND (UnitName[i] <> 0C) DO
      Empty := UnitName[i] = ' ';
      INC(i);
   END;

   IF Empty OR (Str.Pos(UnitName,'?') <= HIGH(UnitName)) THEN
      ReDisplay := DoRefSelectionWindow(UnitID,UnitName);
      ReEdit := TRUE;
      RETURN
   END;
   
   IntToSortWord(UnitName,T);
   IF LookupRefName(T,i) THEN UnitID := RefsNameListPntr^[i]^.ID;
   ELSE
      MsgString(UnitName,0);
      ResAskUser( NotRefNameRes, 'SC', ch);
      IF ch = 'C' THEN
         ReDisplay := FALSE;
         ReEdit := TRUE
      ELSE
         ReDisplay := DoRefSelectionWindow(UnitID,UnitName);
         ReEdit := TRUE;
      END;
   END;
END GeneralUnitNameVerify;

BEGIN
    WITH RefNmeSelectWind DO
        XPos :=   45;
        YPos :=   4;
        XSize := 25;
        YSize := 9;
        MxYSize := 9;
        Type := Dialog;
        AllowMove := TRUE;
        AllowResize := TRUE;
    END;
END TACTDataServices.
