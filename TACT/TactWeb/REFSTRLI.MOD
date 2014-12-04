IMPLEMENTATION MODULE RefStrListModule;
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


IMPORT Lib, WordBase, BitOps ;
FROM SYSTEM IMPORT ADR, TSIZE ;
FROM DBData IMPORT
   (* Vars *) TDBFile, BeginStr, NoStrRecs, LastAlphChar ;
FROM ErrorBase IMPORT ProgramErrorAndHalt ;
FROM TACTListModule IMPORT
   (* Types *) TACTList, TACTListType, TACTListItem, TACTListBaseData,
               TACTListBasePntr,
   (* Procs *) NewListItem, GetFirstItem, DiscardList, DisposeListItem,
               GetItemData, GenericDisposeListItem, GenericGetItemData,
               GenericReleaseItemHold, GenericNewListItem, GenericCopyListItem;
FROM TACTDataServices IMPORT
  (* procs *) DisposeDataItem;
FROM RefStrInit IMPORT
  (* Vars *) RefStrRecListPntr,
  (* Proc *) GetRefStrRecInfo ;
FROM HyperBase IMPORT
  (* Types *) HRecPntr,
  (* Procs *) GetBaseHyper, ReleaseBaseHyper ;
FROM ListData IMPORT
  (* Types *) DataItemPntr, DataItem, ItemType,
  (* Procs *) MakeRefStringItem, MakeStringData, MarkAsUsed,
              DuplicateDataItem ;
FROM HyperDataModel IMPORT
  (* Types *) HyperData, TDBStrPntr, HLogDataType, TDBStringFormat,
  (* Procs *) TDBStrCompare ;
FROM GlobalDefs IMPORT StrAny ;
FROM ResMessages IMPORT
  (* Procs *) MsgString, PutResWarning ;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE, RealStoragePntr ;
FROM MainLists IMPORT
   PoolNoForTDBTACTLists;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) VMAccess, VMModify, VMRelease, VMMarkChanged, RealToPool;

TYPE
   RefTypeTACTListData = RECORD
     (* first three items much match TACTList.TACTListData j.b.*)
        LDataSize: CARDINAL;
        BaseData:  TACTListBasePntr;
        Type:      TACTListType;
    (*  Unique Data items begins here  j.b. *)
        RefID:     INTEGER ;
        StartRec:  CARDINAL ;
        StartIdx:  CARDINAL ;
        EndRec:    CARDINAL ;
        EndIdx:    CARDINAL ;
   END;
   RefTypeTACTList = POINTER TO RefTypeTACTListData;

PROCEDURE GetNextRefStrPos( List : RefTypeTACTList;
                            Old  : HRecPntr;
                        VAR New  : HRecPntr ) : BOOLEAN ;
VAR
   HP: RealStoragePntr;
BEGIN
   GetBaseHyper( Old.Rec, HP, TDBFile);
   New.Rec := Old.Rec;
   New.Idx := Old.Idx+1;
   IF New.Idx > HP^.HRecord.NoDataPtrsUsed THEN
      INC( New.Rec ) ;
      New.Idx := 1;
   END;
   ReleaseBaseHyper( TDBFile, HP );
   RETURN   (New.Rec < List^.EndRec) OR
      ((New.Rec = List^.EndRec) AND (New.Idx < List^.EndIdx));
END GetNextRefStrPos;

PROCEDURE GetPrevRefStrPos( List : RefTypeTACTList;
                            Old  : HRecPntr;
                        VAR New  : HRecPntr ) : BOOLEAN ;
VAR
   HP: RealStoragePntr;
BEGIN
   IF (Old.Rec = List^.StartRec) AND (Old.Idx <= List^.StartIdx+1 ) THEN
      RETURN FALSE
   END;

   IF Old.Idx = 1 THEN
      New.Rec := Old.Rec - 1;
      IF New.Rec < List^.StartRec THEN RETURN FALSE END;
      GetBaseHyper( New.Rec, HP, TDBFile);
      New.Idx := HP^.HRecord.NoDataPtrsUsed;
      ReleaseBaseHyper(TDBFile,HP);
      IF New.Idx = List^.StartIdx THEN  RETURN FALSE  END ;
   ELSE
      New.Rec := Old.Rec;
      New.Idx := Old.Idx - 1
   END;
   RETURN TRUE;
END GetPrevRefStrPos;

PROCEDURE UpdateItem(VAR Item   : TACTListItem;
                         List   : RefTypeTACTList;
                         Pos    : HRecPntr);
VAR
   CX:         RealStoragePntr;
   TIntStr:    StrAny;
   TSortStr:   TDBStrPntr ;
   Len:	       CARDINAL ;
   TempStr:    StrAny ;
   Data:       DataItemPntr;
BEGIN
   IF Item.DataVA <> NILVirt THEN DisposeDataItem( Item.DataVA ) END;
   GetBaseHyper( Pos.Rec, CX, TDBFile );
   WITH CX^.HRecord DO
     IF (Pos.Idx > NoDataPtrsUsed) OR (Pos.Idx = 0) OR
        ( (Pos.Rec = List^.EndRec) AND (Pos.Idx > List^.EndIdx) ) THEN
        ProgramErrorAndHalt( 'RefStrBase (GetRefStr): Invalid String record access.' )
     END ;
     TSortStr := ADR( TextData[ DataPntr[Pos.Idx] ]);
     Len := DataPntr[Pos.Idx-1] - DataPntr[Pos.Idx] - CARDINAL(TSortStr^.TDBStr.PackedLen)
			- 1 (* account for KeyLen byte *) - TSIZE(LONGINT);
     Lib.Move(  ADR(TSortStr^.TDBStr.PackedStr[CARDINAL(TSortStr^.TDBStr.PackedLen)] ),
		ADR(TIntStr), Len ) ;
     TIntStr[Len] := 0C ;	(* guarantee 0C terminated! Not always so in DB *LP* *)
   END ;
   MakeRefStringItem( List^.RefID, PoolNoForTDBTACTLists, Item.DataVA, Data ) ;
   WITH Data^ DO
      FilePos := Pos ;
(*    MakeRealStringData( TIntStr, IntStr ) ; *)
      MakeStringData( TIntStr, PoolNoForTDBTACTLists, IntStrVA ) ;
      BitOps.UnPack( TSortStr^.TDBStr, TempStr, WordBase.SortNoBitsPerChar ) ;
(*    MakeRealStringData( TempStr, SortStr ) ; *)
      MakeStringData( TempStr, PoolNoForTDBTACTLists, SortStrVA ) ;
   END ;
   ReleaseBaseHyper( TDBFile, CX ) ;
   MarkAsUsed(Data);
   VMRelease(Item.DataVA);
END UpdateItem;

PROCEDURE GetPrevRefStr(Adr:  ADDRESS;
                    VAR Item: TACTListItem): BOOLEAN;
VAR
   List    : RefTypeTACTList;
   NewPos  : HRecPntr;
   Pntr    : DataItemPntr;
BEGIN
   List := RefTypeTACTList(Adr);
   Pntr := VMAccess(Item.DataVA);
   IF NOT GetPrevRefStrPos( List, Pntr^.FilePos, NewPos ) THEN
      VMRelease(Item.DataVA);
      RETURN FALSE
   END;
   VMRelease(Item.DataVA);
   UpdateItem(Item, List, NewPos);
   RETURN TRUE;
END GetPrevRefStr;


PROCEDURE GetNextRefStr(Adr:  ADDRESS;
                    VAR Item: TACTListItem): BOOLEAN;
VAR
   List    : RefTypeTACTList;
   NewPos  : HRecPntr;
   Pntr    : DataItemPntr;
BEGIN
   List := RefTypeTACTList(Adr);
   Pntr := VMAccess(Item.DataVA);
   IF NOT GetNextRefStrPos( List, Pntr^.FilePos, NewPos ) THEN
      VMRelease(Item.DataVA);
      RETURN FALSE
   END;
   VMRelease(Item.DataVA);
   UpdateItem(Item, List, NewPos);
   RETURN TRUE;
END GetNextRefStr;

PROCEDURE GetFirstRefStr(Adr:  ADDRESS;
                     VAR Item: TACTListItem): BOOLEAN;
VAR
   List    : RefTypeTACTList;
   NewPos  : HRecPntr;
   dummy   : BOOLEAN ;
BEGIN
   List := RefTypeTACTList(Adr);
   NewPos.Rec := List^.StartRec ;
   NewPos.Idx := List^.StartIdx ;	(* need to +1 to skip "" string ??? *)
   dummy := GetNextRefStrPos( List, NewPos, NewPos ) ;
   UpdateItem(Item, List, NewPos);
   RETURN TRUE;
END GetFirstRefStr;

PROCEDURE GetLastRefStr(Adr:  ADDRESS;
                   VAR Item: TACTListItem): BOOLEAN;
VAR
   List    : RefTypeTACTList;
   NewPos  : HRecPntr;
   dummy   : BOOLEAN ;
BEGIN
   List := RefTypeTACTList(Adr);
   NewPos.Rec := List^.EndRec ;
   NewPos.Idx := List^.EndIdx ;	(* need to -1 to skip last string ??? *)
   dummy := GetPrevRefStrPos( List, NewPos, NewPos ) ;
   UpdateItem(Item, List, NewPos);
   RETURN TRUE;
END GetLastRefStr;

PROCEDURE FindRefStrFromString(Text:   ARRAY OF CHAR;
                               Type:   ItemType;
                               Adr:    ADDRESS; (* TACTList *)
                           VAR Item:   TACTListItem): BOOLEAN;
VAR
   Data    : DataItemPntr;
   List    : RefTypeTACTList;
   NewPos  : HRecPntr;
   TempPos : HRecPntr;
   Found   : BOOLEAN;
   FindStr : TDBStringFormat ;
   FindStrPtr : TDBStrPntr;

PROCEDURE FindRefStr(VAR RefStr: HRecPntr ) : BOOLEAN ;
VAR
   HP:    RealStoragePntr;
   TRec:  CARDINAL;
   LPtr:  TDBStrPntr;
   HPtr:  TDBStrPntr;
   IPtr:  TDBStrPntr;
   LIdx:  CARDINAL;
   UIdx:  CARDINAL;
   IIdx:  CARDINAL;
   Found: BOOLEAN;
   Done:  BOOLEAN;
   ICmp:  INTEGER;
BEGIN
   (* estimate the starting Record for this string *)
   WITH List^ DO
      IF ORD(Text[0]) > 2 THEN
	 TRec := ( ( ( (ORD(Text[0])-2) * (EndRec-StartRec) * 10) DIV
	          (ORD(LastAlphChar)-2) + 5) DIV 10) + StartRec;
      ELSE
         (* Handle pathalogical case of markup codes not made of alpha chars!!*)
         TRec := StartRec
      END ;
      IF TRec < StartRec THEN TRec := StartRec
      ELSIF TRec > EndRec THEN TRec := EndRec END;
   END ;

   GetBaseHyper( TRec, HP, TDBFile);

   (* now position to Hyper record containing the string *)
   WITH HP^.HRecord DO
      IF TRec = List^.StartRec THEN
         LPtr := ADR( TextData[ DataPntr[List^.StartIdx] ] )
      ELSE
         LPtr := ADR( TextData[ DataPntr[1] ] )
      END ;
      IF TRec = List^.EndRec THEN
         HPtr := ADR( TextData[ DataPntr[List^.EndIdx] ] )
      ELSE
         HPtr := ADR( TextData[ DataPntr[NoDataPtrsUsed] ] )
      END ;
   END;

   (* NEED TO CONVERT WORD TO PACKED FORMAT AND USE PackedStr for comparison *)
   FindStrPtr := ADR( FindStr ) ;
   BitOps.Pack( Text, FindStrPtr^.TDBStr, WordBase.SortNoBitsPerChar ) ;

   IF TDBStrCompare( FindStrPtr, LPtr ) < 0 THEN
      REPEAT
         ReleaseBaseHyper(TDBFile,HP);
         DEC(TRec);
         GetBaseHyper( TRec, HP, TDBFile);
         WITH HP^.HRecord DO
             IF TRec = List^.StartRec THEN
                LPtr := ADR( TextData[ DataPntr[List^.StartIdx] ] )
             ELSE
                LPtr := ADR( TextData[ DataPntr[1] ] )
             END ;
             IF TRec = List^.EndRec THEN
                HPtr := ADR( TextData[ DataPntr[List^.EndIdx] ] )
             ELSE
                HPtr := ADR( TextData[ DataPntr[NoDataPtrsUsed] ] )
             END ;
          END;
      UNTIL TDBStrCompare( FindStrPtr, LPtr ) >= 0
   ELSE
      WHILE TDBStrCompare( FindStrPtr, HPtr ) > 0 DO
         ReleaseBaseHyper(TDBFile,HP);
         INC(TRec);
         GetBaseHyper( TRec, HP, TDBFile);
         WITH HP^.HRecord DO
            IF TRec = List^.StartRec THEN
               LPtr := ADR( TextData[ DataPntr[List^.StartIdx] ] )
            ELSE
               LPtr := ADR( TextData[ DataPntr[1] ] )
            END ;
            IF TRec = List^.EndRec THEN
               HPtr := ADR( TextData[ DataPntr[List^.EndIdx] ] )
            ELSE
               HPtr := ADR( TextData[ DataPntr[NoDataPtrsUsed] ] )
            END ;
         END;
      END;
   END;

   RefStr.Rec := TRec;

   WITH HP^.HRecord DO
      IF TRec = List^.StartRec THEN LIdx := List^.StartIdx
      ELSE LIdx := 1 END ;

      IF TRec = List^.EndRec THEN UIdx := List^.EndIdx
      ELSE UIdx := NoDataPtrsUsed END ;

      Done := FALSE;
      REPEAT
         IF UIdx < LIdx THEN
            Done := TRUE;
            RefStr.Idx := UIdx;
            Found := FALSE
         ELSE
            IIdx := (LIdx + UIdx) DIV 2;
            IPtr := ADR( TextData[ DataPntr[IIdx] ] );
            ICmp := TDBStrCompare( FindStrPtr, IPtr );

            IF ICmp < 0 THEN UIdx := IIdx - 1
            ELSIF ICmp > 0 THEN LIdx := IIdx + 1
            ELSE
               Done := TRUE;
               Found := TRUE;
               RefStr.Idx := IIdx;
            END;
         END
      UNTIL Done;
   END;
   ReleaseBaseHyper( TDBFile, HP ) ;
   RETURN Found
END FindRefStr;

BEGIN
   IF Type <> RefStringType THEN RETURN FALSE END;
   List := RefTypeTACTList(Adr);

   IF FindRefStr( NewPos ) THEN
      Found := TRUE
   ELSE
      Found := FALSE;
   (* If GetNextRefStrPos failed -- are at the end of the RefStr list;
         hence, we should ignore the failure j.b. *)
      IF GetNextRefStrPos( List, NewPos, TempPos ) THEN NewPos := TempPos END;
   END;
   UpdateItem(Item, List, NewPos);
   RETURN Found
END FindRefStrFromString;

PROCEDURE DeleteRefStrTACTList( VAR TList:  TACTList);
VAR  RList:   RefTypeTACTList;
BEGIN
   IF TList = NIL THEN RETURN END;
   RList := RefTypeTACTList(TList);
   DISPOSE( RList );
   TList := NIL ;
END DeleteRefStrTACTList;

PROCEDURE FindRefStrItem(List:    ADDRESS; (* ignored here *)
                         Data:    VirtAddr;
                     VAR Item: TACTListItem): BOOLEAN;
BEGIN
   ProgramErrorAndHalt('No FindItem for RefStrList');
   RETURN FALSE;
END FindRefStrItem;

PROCEDURE RefStrItemDataPresent(List:   TACTList;
                                Type:   ItemType;
                                Pos:    HRecPntr;
                            VAR Item:   TACTListItem): BOOLEAN;
BEGIN
   ProgramErrorAndHalt('No ItemDataPresent for RefStrList');
   RETURN FALSE;
END RefStrItemDataPresent;

PROCEDURE InitialRefStrList( InRefID : INTEGER ): TACTList ;
VAR  RefListP:    RefTypeTACTList;
BEGIN
   NEW(RefListP);
   WITH RefListP^ DO
      LDataSize := SIZE(RefTypeTACTListData);
      BaseData := ADR(OfficialRefStrListData);
      Type := RefStrList ;
      RefID := InRefID ;
      GetRefStrRecInfo( InRefID, StartRec, StartIdx, EndRec, EndIdx ) ;
   END;
   RETURN TACTList(RefListP);
END InitialRefStrList;

BEGIN
    WITH OfficialRefStrListData DO
      NewItemProc :=      GenericNewListItem;
      CopyListItemProc := GenericCopyListItem;
      DispListItemProc := GenericDisposeListItem;
      DisposeListProc :=  DeleteRefStrTACTList;
      GetItemDataProc :=  GenericGetItemData;
      ReleaseItemProc:=   GenericReleaseItemHold;
      GetFirstItemProc := GetFirstRefStr;
      GetLastItemProc  := GetLastRefStr;
      GetNextItemProc :=  GetNextRefStr;
      GetPrevItemProc :=  GetPrevRefStr;
      FindItemProc :=     FindRefStrItem;
      ItemDataPresProc := RefStrItemDataPresent;
      FindFromStrProc :=  FindRefStrFromString;
    END;
END RefStrListModule.
