IMPLEMENTATION MODULE ListData;
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


IMPORT Str, Lib, BitOps, WordBase ;
FROM SYSTEM IMPORT ADDRESS, TSIZE, ADR;
FROM GlobalDefs IMPORT StrAny;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM VirtMem IMPORT
  (* types *) VirtAddr,
  (* vars  *) NILVirt,
  (* procs *) CopyFromVirtMem, CopyToVirtMem, VMAccess, VMModify,
              VMRelease, GetSpace, FreeSpace, RealToPool, VirtToPool,
              EqualVirts, VMMarkChanged;
FROM HyperBase IMPORT
  (* TYPE *)  HRecPntr,
  (* VAR  *)  NilHRecPntr ;
FROM HyperDataModel IMPORT
  (* Types *) HyperData, HTypePntr, HyperRType, HTypeData, TDBTypeData, HOccurData,
              HTokenData, HLogDataType;
FROM MemoryManagement IMPORT ALLOCATE,DEALLOCATE;

CONST
   PrefixSize = 19; (* Size of ItemSize,FilePos,DataType, UsageCount,
                       NoContents, Contents and Annotation in Bytes *)
VAR
   HTypeDataBase:         CARDINAL;
   TypeTypeBaseSize:      CARDINAL;
   TokenTypeBaseSize:     CARDINAL;
   RefNameTypeBaseSize:   CARDINAL;
   RefStringTypeBaseSize: CARDINAL;
   CatTypeBaseSize:       CARDINAL;
   RuleTypeSize:          CARDINAL;
   FileNameTypeBaseSize:  CARDINAL;
   MKSTypeBaseSize:	  CARDINAL;(* m.s. *)
   ColTypeBaseSize:	  CARDINAL;
   DistTypeBaseSize:	  CARDINAL;
   LastMKSLine :          VirtAddr; (* m.s. *)

PROCEDURE MarkAsUsed(Pntr:    DataItemPntr);
BEGIN
   INC(Pntr^.UsageCount);
END MarkAsUsed;

PROCEDURE MarkAsFreed(Pntr:    DataItemPntr);
BEGIN
   DEC(Pntr^.UsageCount);
END MarkAsFreed;

PROCEDURE AllocateDataItem(Size:     CARDINAL;
                           Pool:     CARDINAL;
                       VAR VA:       VirtAddr;
                       VAR Pntr:     DataItemPntr);
BEGIN
   Pntr := GetSpace(Size, Pool, VA);
   WITH Pntr^ DO
      ItemSize := Size;
      UsageCount := 0;
      NoContents := 0;
      Contents := NILVirt;
      Annotation := NILVirt;
   END;
END AllocateDataItem;

PROCEDURE MakeStringData(Data:     ARRAY OF CHAR;
                         Pool:     CARDINAL;
                     VAR VA:       VirtAddr);
VAR l:   CARDINAL;
    Pntr: StringPntr;
BEGIN
   l := Str.Length(Data) + 3;
   Pntr := GetSpace(l, Pool, VA);
   Pntr^.ItemSize := l;
   Str.Copy(Pntr^.String,Data);
   VMRelease(VA);
END MakeStringData;

PROCEDURE MakeRealStringData(Data:  ARRAY OF CHAR;
                         VAR Pntr:  StringPntr);
VAR l:   CARDINAL;
BEGIN
   l := Str.Length(Data) + 3;
   ALLOCATE(Pntr, l);
   Pntr^.ItemSize := l;
   Str.Copy(Pntr^.String,Data);
END MakeRealStringData;


PROCEDURE ReleaseStringData(VAR VA:  VirtAddr);
VAR Pntr:    StringPntr;
BEGIN
   Pntr := VMAccess(VA);
   FreeSpace(VA,Pntr^.ItemSize);
   VA := NILVirt;
END ReleaseStringData;

PROCEDURE ReleaseRealStringData(VAR Pntr: StringPntr);
BEGIN
   DEALLOCATE(Pntr, Pntr^.ItemSize);
   Pntr := NIL;
END ReleaseRealStringData;

PROCEDURE MakeTDBTypeDataItem(Data:    TDBTypeData;
                           Pool:    CARDINAL;
                       VAR VA:      VirtAddr;
                       VAR Pntr:    DataItemPntr);
VAR
   WordNameLen	: CARDINAL;
   HTempStr	: StrAny ;
BEGIN
   BitOps.UnPack( Data.PackedWord, HTempStr, WordBase.SortNoBitsPerChar ) ;
   WordNameLen := Str.Length( HTempStr ) + 1;
   AllocateDataItem(WordNameLen+TypeTypeBaseSize,Pool, VA, Pntr);
   WITH Pntr^.TypeFileData DO
	Str.Copy( Word, HTempStr ) ;
	NoOccur  := Data.NoOccur ;
   END ;
   Pntr^.DataType := TypeType;
END MakeTDBTypeDataItem;

PROCEDURE MakeTypeDataItem(Data:    HTypeData;
                           Pool:    CARDINAL;
                       VAR VA:      VirtAddr;
                       VAR Pntr:    DataItemPntr);
VAR
   WordNameLen	: CARDINAL;
BEGIN
   WordNameLen := Str.Length( Data.Word ) + 1;
   AllocateDataItem(WordNameLen+TypeTypeBaseSize,Pool, VA, Pntr);
   WITH Pntr^.TypeFileData DO
	Str.Copy( Word, Data.Word ) ;
	NoOccur  := Data.NoOccur ;
   END ;
   Pntr^.DataType := TypeType;
END MakeTypeDataItem;

PROCEDURE MakeTokenDataItem(VAR VA:    VirtAddr;
                            Pool:      CARDINAL;
                            VAR Pntr:  DataItemPntr);
BEGIN
   AllocateDataItem(TokenTypeBaseSize,Pool, VA, Pntr);
   Pntr^.HeadWord := NILVirt;
   Pntr^.CurrentContextCount := 0 ; (* 0 = current context range not set yet *)
   Pntr^.StartContext := NilHRecPntr ;
   Pntr^.FinishContext := NilHRecPntr ;
   Pntr^.BefOffset := CHR( 0 ) ;
   Pntr^.AftOffset := CHR( 0 ) ;
   Lib.Fill(ADR(Pntr^.TokenFileData),TSIZE(HTokenData),0C);
   Pntr^.DataType := TokenType;
   Pntr^.TokenDataLoaded := FALSE;
END MakeTokenDataItem;

PROCEDURE MakeCatDataItem(Name:    ARRAY OF CHAR;
                          Pool:    CARDINAL;
                      VAR VA:      VirtAddr;
                      VAR Pntr:    DataItemPntr);
VAR
   CatNameLen:   CARDINAL;
BEGIN
   CatNameLen := Str.Length(Name) + 1;
   IF CatNameLen > 40 THEN CatNameLen := 41 END;
   AllocateDataItem(CatNameLen+CatTypeBaseSize,Pool, VA, Pntr);
   Lib.Move(ADR(Name),ADR(Pntr^.CatName),CatNameLen);
   Pntr^.CatName[CatNameLen - 1] := 0C;
   Pntr^.DataType := CatType;
END MakeCatDataItem;

PROCEDURE MakeRefNameItem(Idx:     CARDINAL;
                          Pool:    CARDINAL;
                      VAR VA:      VirtAddr;
                      VAR Pntr:    DataItemPntr);
BEGIN
   AllocateDataItem(RefNameTypeBaseSize,Pool, VA, Pntr);
   Pntr^.FilePos.Rec := 0;
   Pntr^.FilePos.Idx := Idx;
   Pntr^.DataType := RefNameType;
END MakeRefNameItem;

PROCEDURE MakeRefStringItem( 	 RefID : INTEGER ;
                                 Pool  : CARDINAL;
                             VAR VA    : VirtAddr;
			     VAR Pntr  : DataItemPntr ) ;
   BEGIN
	AllocateDataItem( RefStringTypeBaseSize,Pool, VA, Pntr);
	(* FilePos must be set from calling proc, ie. Rec = BeginStr + ORD(SRecNo) ... *)
	Pntr^.FilePos.Rec := 0;
	Pntr^.FilePos.Idx := 0;
	Pntr^.IntStrVA    := NILVirt ;
	Pntr^.SortStrVA   := NILVirt ;
	Pntr^.RefID	  := RefID ;
	Pntr^.DataType	  := RefStringType;
   END MakeRefStringItem ;

PROCEDURE MakeRuleItem( pRuleName: ARRAY OF CHAR;
                    VAR pRuleLine: ARRAY OF CHAR; (* read only *)
                        Pool:      CARDINAL;
                    VAR VA:        VirtAddr;
                    VAR Pntr:      DataItemPntr ) ;
VAR
     tStr:    StringPntr;
BEGIN
     AllocateDataItem( RuleTypeSize, Pool, VA, Pntr);
     (* FilePos must be set from calling proc *)
     Pntr^.DataType := RuleType;
     Pntr^.FilePos.Rec := 0;
     Pntr^.FilePos.Idx := 0;
     IF pRuleName[0] <> 0C THEN MakeRealStringData(pRuleName,Pntr^.RuleName)
     ELSE Pntr^.RuleName := NIL END;
     Pntr^.SortRuleName := NIL;
     IF pRuleLine[0] <> 0C THEN MakeRealStringData(pRuleLine,Pntr^.RuleLine)
     ELSE Pntr^.RuleLine := NIL END;
END MakeRuleItem;

PROCEDURE MakeFileNameItem(fName: ARRAY OF CHAR;
                           Pool:  CARDINAL;
                       VAR VA:    VirtAddr;
                       VAR Pntr:  DataItemPntr);
VAR
   fNameLen:   CARDINAL;
BEGIN
   fNameLen := Str.Length(fName) + 1;
   AllocateDataItem(fNameLen+FileNameTypeBaseSize, Pool, VA, Pntr);
   WITH Pntr^ DO
      Str.Copy(FNameInt, fName);
      DataType := FileNameType;
      FilePos.Rec := 0; (* FilePos is not used in this type j.b. *)
      FilePos.Idx := 0; (* FilePos is not used in this type j.b. *)
   END;
END MakeFileNameItem;

PROCEDURE MakeMKSLineItem(Line: ARRAY OF CHAR;
                           Pool:  CARDINAL ) ;
(* m.s. - can be local, not used for now   VAR VA:    VirtAddr;
                       VAR Pntr:  DataItemPntr);
*)
VAR
   LineLen:   CARDINAL;
   PrevItem:  DataItemPntr ;
   VA:    VirtAddr;
   Pntr:  DataItemPntr;
BEGIN
   LineLen := Str.Length(Line) + 1;
   AllocateDataItem(LineLen+MKSTypeBaseSize, Pool, VA, Pntr);
   WITH Pntr^ DO
      Str.Copy(LineInfo, Line);
      DataType := MKSInfoLineType;
      Next := NILVirt ;
      IF FirstMKSLine = NILVirt THEN (* if first item *)
         FirstMKSLine := VA ;
         LastMKSLine := VA ;
         Prev := NILVirt ;
      ELSE
         Prev := LastMKSLine ;
         PrevItem := VMModify( LastMKSLine ) ;
         PrevItem^.Next := VA ;  (* make the previous last line .Next point to new line *)
         VMRelease( LastMKSLine ) ;
         LastMKSLine := VA ;
      END ;
   END;
(*   VMMarkChanged( VA ) ; (* m.s. - needed ? *) *)
   VMRelease( VA ) ; (* m.s. - released here for now *)
END MakeMKSLineItem;


PROCEDURE MakeColDataItem(    Data	: HTypeHandle;
			      Pool	: CARDINAL;
			  VAR VA	: VirtAddr;
			  VAR Pntr	: DataItemPntr);
VAR
   WordNameLen	: CARDINAL;
   HTempStr	: StrAny ;
BEGIN
   BitOps.UnPack( Data^^.PackedWord, HTempStr, WordBase.SortNoBitsPerChar ) ;
   WordNameLen := Str.Length( HTempStr ) + 1 ;	(* +1 for 0C *)
   AllocateDataItem(ColTypeBaseSize+WordNameLen, Pool, VA, Pntr);
   WITH Pntr^ DO
	Str.Copy( HeadWordData.Word, HTempStr ) ;
	HeadWordData.NoOccur := Data^^.NoOccur ;
	DataType   := ColDataItemType;
	Freq	   := 0 ;
	ZScore	   := 0.0 ;
	PrevColVA  := NILVirt;
	NextColVA  := NILVirt;
   END ;
END MakeColDataItem;

PROCEDURE MakeDistDataItem(    Pool	: CARDINAL;
			   VAR VA	: VirtAddr;
			   VAR Pntr	: DataItemPntr);
BEGIN
   AllocateDataItem(DistTypeBaseSize, Pool, VA, Pntr);
   WITH Pntr^ DO
       DataType  := DistDataItemType;
       LineID[0] := 0C ;
       PrevDistVA:= NILVirt;
       NextDistVA:= NILVirt;
       (* LogID  := ?? *)
   END ;
END MakeDistDataItem;

PROCEDURE DuplicateDataItem( DataIn:   VirtAddr; (* as DataItemVA *)
                             PoolOut:  CARDINAL;
                         VAR DataOut:  VirtAddr; (* as DataItemVA *)
                         VAR PntrOut:  DataItemPntr);
VAR item:   DataItem;
    StrPtr: StringPntr;
BEGIN
   CopyFromVirtMem(DataIn, SIZE(DataItem), item);
   PntrOut := GetSpace(item.ItemSize, PoolOut, DataOut);
   Lib.Move(ADR(item),PntrOut, item.ItemSize);
   WITH PntrOut^ DO
      UsageCount := 0;
      NoContents := 0;
      IF DataType <> CatType  THEN  Contents := NILVirt  END ;
      IF DataType = TokenType THEN  HeadWord := NILVirt
      ELSIF DataType = RefStringType THEN
	 IF IntStrVA  <> NILVirt THEN
	    StrPtr := VMAccess( item.IntStrVA ) ;
	    MakeStringData( StrPtr^.String, PoolOut, IntStrVA);
	    VMRelease( item.IntStrVA ) ;
	 END;
	 IF SortStrVA <> NILVirt THEN
	    StrPtr := VMAccess( item.SortStrVA ) ;
	    MakeStringData(StrPtr^.String, PoolOut, SortStrVA) ;
	    VMRelease( item.SortStrVA ) ;
	 END;
      ELSIF DataType = RuleType THEN
         IF item.RuleName <> NIL THEN MakeRealStringData(item.RuleName^.String, RuleName) END;
         IF item.SortRuleName <> NIL THEN MakeRealStringData(item.SortRuleName^.String, SortRuleName) END;
         IF item.RuleLine <> NIL THEN MakeRealStringData(item.RuleLine^.String, RuleLine) END;
      END ;
   END;
END DuplicateDataItem;

PROCEDURE CompareDataItems(Data1,Data2: DataItemPntr): INTEGER;
BEGIN
   IF Data1^.DataType < Data2^.DataType THEN RETURN -1
   ELSIF Data1^.DataType > Data2^.DataType THEN RETURN 1
   ELSE
      IF Data1^.DataType = CatType THEN
         RETURN Str.Compare(Data1^.CatName,Data2^.CatName)
      END;
      IF Data1^.DataType = FileNameType THEN
         RETURN Str.Compare(Data1^.FNameInt,Data2^.FNameInt)
      END;
      IF Data1^.DataType = ZScoreType THEN
	 (* do a compare for descending order *)
	 IF Data1^.ZScore < Data2^.ZScore THEN RETURN 1
	 ELSIF Data1^.ZScore > Data2^.ZScore THEN RETURN -1
	 (* else use FilePos when equal *)
	 END ;
      END;
      IF Data1^.FilePos.Rec < Data2^.FilePos.Rec THEN RETURN -1
      ELSIF Data1^.FilePos.Rec > Data2^.FilePos.Rec THEN RETURN 1
      ELSE
         IF Data1^.FilePos.Idx < Data2^.FilePos.Idx THEN RETURN -1
         ELSIF Data1^.FilePos.Idx > Data2^.FilePos.Idx THEN RETURN 1
         ELSE RETURN 0
         END;
      END;
   END;
END CompareDataItems;

PROCEDURE CompareVADataItems( Data1, Data2 : VirtAddr ) : INTEGER;
VAR
   Pntr1, Pntr2: DataItemPntr;
   rslt:  INTEGER;
BEGIN
   Pntr1 := VMAccess(Data1);
   Pntr2 := VMAccess(Data2);
   rslt := CompareDataItems(Pntr1, Pntr2);
   VMRelease(Data1);
   VMRelease(Data2);
   RETURN rslt;
END CompareVADataItems;

BEGIN
   HTypeDataBase := TSIZE(HTypeData) - TSIZE(StrAny) + 1 (* for 0C *);
   TypeTypeBaseSize := PrefixSize + HTypeDataBase;
   TokenTypeBaseSize := PrefixSize + TSIZE(HTokenData) + TSIZE(ADDRESS) +
			TSIZE(VirtAddr) + TSIZE(CARDINAL) +
			2*TSIZE(HRecPntr) + 3 (* 2CHARs 1BOOL*) ;
   CatTypeBaseSize := PrefixSize;
   RefNameTypeBaseSize := PrefixSize;
   RefStringTypeBaseSize := PrefixSize + TSIZE(INTEGER) + 2*TSIZE(ADDRESS) ;
   RuleTypeSize := PrefixSize + 3 * TSIZE(ADDRESS);
   FileNameTypeBaseSize := PrefixSize;
   MKSTypeBaseSize := PrefixSize + 2*TSIZE(ADDRESS) + TSIZE(CHAR)*79 ;  (* m.s. - is this ok? should be *)
   ColTypeBaseSize := PrefixSize + HTypeDataBase + TSIZE(REAL) + 2*TSIZE(VirtAddr) + TSIZE(CARDINAL);
   DistTypeBaseSize := PrefixSize + 2*TSIZE(VirtAddr) + TSIZE(HLogDataType) + MaxDistID ;
END ListData.
