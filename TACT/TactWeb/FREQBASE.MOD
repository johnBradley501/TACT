IMPLEMENTATION MODULE FreqBase;
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
(*V5=NoDbg No Debugging code *)

IMPORT RULES, Str;
FROM DBData IMPORT BeginType;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM ScannerSource IMPORT
  (* type *) ItemDataType;
FROM ParserSource IMPORT
  (* procs *) Parser;
FROM ErrorBase IMPORT  ProgramErrorAndHalt;
FROM GlobalDefs IMPORT StrAny;
FROM ResMessages IMPORT
   (*proc*)  PutResError, PutResWarning;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, GetFirstItem, GetNextItem,
              DiscardList, ItemDataPresent, GetItemData, ReleaseItemHold;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, InsertListItem, DeleteListItem;
FROM ListUtils IMPORT MakeWordList;
FROM DataLinkModule IMPORT
  (* types *) DataLink, DataLinkType, DataLinkArrayPntr,
  (* procs *) OpenForSending, OpenForReceiving, SendData, ReceiveData,
              CloseForSending, CloseForReceiving;
FROM SearchUtils IMPORT
   (* types *) SearchResultType,
   (* vars  *) SearchResult,
   (* procs *) UserSuspendsSearch, KeyPressed;
FROM ListData IMPORT
  (* Types *) DataItemPntr, ItemType,
  (* procs *) MakeTypeDataItem, MarkAsUsed;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) GetType, FreeTypeHandle, GetNextType, GetPrevType,
              FindType;
FROM TACTDataServices IMPORT GetTDBTokenData, VirtToTACTList;
FROM RuleWindow IMPORT RuleWindowData;
FROM HyperBase IMPORT HRecPntr;
FROM MainLists IMPORT PoolNoForSearchWorkingSpace;
FROM VirtMem IMPORT VirtAddr, VMRelease, VMAccess;
(*<Dbg
FROM Trace IMPORT
(*procs*) TWriteLn,TWriteChar,TWriteString,TWriteInt,TWriteCard,TWriteAddr,
          TWriteStrHex,CloseTFile;
Dbg>*)

CONST
    (*RES OLD MSG 257
    Your FREQ Query was incorrectly specified. Check the online Help.
    *)
    ImproperRes = (*RES REM INS*) 257 ;

TYPE
  FreqItem = POINTER TO FreqItemData;
  FreqItemData = RECORD
      Low,High:  CARDINAL;
      Next:      FreqItem;
  END;

PROCEDURE DisposeFreqItems(VAR gItem: ADDRESS);
VAR t:    FreqItem;
    Item: FreqItem;
BEGIN
   Item :=FreqItem(gItem);
   WHILE Item <> NIL DO
      t := Item^.Next;
      DISPOSE(Item);
      Item := t;
   END;
   gItem := NIL;
END DisposeFreqItems;

PROCEDURE BuildFreqByParsing(VAR RuleNo:      CARDINAL;
                             VAR Result:      FreqItem): BOOLEAN;
VAR
    tCard:       CARDINAL;
    ItemData:    ItemDataType;
    LastItem:    FreqItem;
    tItem:       FreqItem;

PROCEDURE GetNumberFromItem(): CARDINAL;
VAR OK:   BOOLEAN;
    Numb: CARDINAL;
BEGIN
   Numb := CARDINAL(Str.StrToCard(ItemData.IntStr,10,OK));
   IF NOT OK THEN ProgramErrorAndHalt('Bad number conversion occurred') END;
   RETURN Numb;
END GetNumberFromItem;

PROCEDURE AllocateFreq(Start,End:  CARDINAL;
                   VAR newf:       FreqItem): BOOLEAN;
VAR t:  FreqItem;
BEGIN
   IF (End = 0) OR (Start > End) THEN
      PutResError(ImproperRes);
      DisposeFreqItems( Result);
      RETURN FALSE;
   END;
   NEW(newf);
   WITH newf^ DO
      Low := Start;
      High := End;
      Next := NIL;
   END;
   RETURN TRUE
END AllocateFreq;

BEGIN (* BuildFreqByParsing *)
   Result := NIL;
   REPEAT
      RuleNo := Parser(FALSE,ItemData);
(*<Dbg
      TWriteString('BuildFreqByParsing:Rule:');
      TWriteCard(RuleNo,7);
      TWriteString(',Item:');
      TWriteString(ItemData.IntStr);
      TWriteLn;
Dbg>*)
      CASE RuleNo OF
        RULES.StartFreqList, RULES.StartFreqList2:
           Result := tItem;
           LastItem := tItem;
      | RULES.AppendFreqList:
           LastItem^.Next := tItem;
           LastItem := tItem;
      | RULES.FreqGT:
           IF NOT AllocateFreq(1 + GetNumberFromItem(),MAX(CARDINAL),tItem)
           THEN RETURN FALSE END;
      | RULES.FreqLT:
           tCard := GetNumberFromItem();
           IF tCard = 0 THEN
              PutResError(ImproperRes);
              DisposeFreqItems( Result);
              RETURN FALSE
           END;
           IF NOT AllocateFreq(0,tCard-1,tItem)
           THEN RETURN FALSE END;
      | RULES.FreqGE:
           IF NOT AllocateFreq(GetNumberFromItem(),MAX(CARDINAL),tItem)
           THEN RETURN FALSE END;
      | RULES.FreqLE:
           IF NOT AllocateFreq(0,GetNumberFromItem(),tItem)
           THEN RETURN FALSE END;
      | RULES.FreqEQ:
           tCard := GetNumberFromItem();
           IF NOT AllocateFreq(tCard,tCard,tItem)
           THEN RETURN FALSE END;
      | RULES.FreqRange: (* do nothing *)
      | RULES.SaveLowNumberFromRange:
           tCard := GetNumberFromItem();
      | RULES.LastWhenRule:
           IF NOT AllocateFreq(tCard,GetNumberFromItem(),tItem)
           THEN RETURN FALSE END;
      ELSE (* ignore it *)
      END;
   UNTIL (RuleNo = RULES.FreqDone) OR (RuleNo >= 1000 (* no SYNTAX error *) );
   IF RuleNo >= 1000 THEN
       DisposeFreqItems( Result );
   END;
   RETURN RuleNo = RULES.FreqDone;
END BuildFreqByParsing;

PROCEDURE DoFreq(InData:  DataLinkArrayPntr; (* always 1 only *)
                 Numb:    CARDINAL;          (* always 1 only *)
                 OutData: DataLink;
                 Info:    ADDRESS); (* FreqItem *)
VAR
    CurrentDat:   DataItemPntr;
    CurrentVA:    VirtAddr;
    NumbFound:    CARDINAL;
    TList:        TACTList;
    WList:        TACTList;
    WListPos:     TACTListItem;
    AnyPos:       BOOLEAN;
    done:         BOOLEAN;
    Specs:        FreqItem;

PROCEDURE HandleType(Data: DataItemPntr;
                     VA:   VirtAddr);
VAR t:     FreqItem;
    count: CARDINAL;
BEGIN
   t := Specs;
   count := Data^.TypeFileData.NoOccur;
   WHILE t <> NIL DO
      IF (t^.Low <= count) AND (count <= t^.High) THEN
         done := NOT SendData(OutData, VA);
         INC(NumbFound);
         RETURN
      END;
      t := t^.Next;
   END;
END HandleType;

PROCEDURE HandleToken(VA:   VirtAddr);
VAR dummy:  BOOLEAN;
BEGIN
   dummy := InsertListItem(VA, TList);
   AnyPos := TRUE;
END HandleToken;

PROCEDURE CheckCollectedPos;
VAR t:     FreqItem;
    count: CARDINAL;
    dummy: BOOLEAN;
    VA:    VirtAddr;
    Data:  DataItemPntr;

PROCEDURE InsertWholeList(VList:    VirtAddr);
VAR
   List:     TACTList;
   item:     TACTListItem;
   va:       VirtAddr;
   data:     DataItemPntr;
BEGIN
   VirtToTACTList(VList, List);
   NewListItem(List, item);
   IF NOT GetFirstItem(List,item) THEN
      ProgramErrorAndHalt('unexpected end in InsertList')
   END;
   REPEAT
      GetItemData(List, item, va, data);
      ReleaseItemHold(List, item);
      done := NOT SendData(OutData, va);
      INC(NumbFound);
   UNTIL done OR (NOT GetNextItem(List,item));
   DisposeListItem(List, item);
   DiscardList(List);
END InsertWholeList;

BEGIN (* CheckCollectedPos *)
   GetItemData(WList, WListPos, VA, Data);
   t := Specs;
   count := Data^.NoContents;
   WHILE t <> NIL DO
      IF (t^.Low <= count) AND (count <= t^.High) THEN
         InsertWholeList(Data^.Contents);
         RETURN
      END;
      t := t^.Next;
   END;
   ReleaseItemHold(WList, WListPos);
END CheckCollectedPos;

BEGIN (* DoFreq *)
   Specs := FreqItem(Info);
   AnyPos := FALSE;
   NumbFound := 0;
   OpenForReceiving(InData^[0], DontCare);
   OpenForSending(OutData, DontCare);
   done := NOT ReceiveData(InData^[0], CurrentVA);
   IF done THEN
      CloseForReceiving(InData^[0]);
      CloseForSending(OutData);
      RETURN
   END;

   TList := NewMemoryList( PoolNoForSearchWorkingSpace );
   WList := NewMemoryList( PoolNoForSearchWorkingSpace );
   NewListItem(WList, WListPos);
   REPEAT
      CurrentDat := VMAccess(CurrentVA);
      CASE CurrentDat^.DataType OF
        CatType:  ProgramErrorAndHalt('Cat Type not yet supported in DoFreq')
      | TypeType: HandleType(CurrentDat, CurrentVA);
      | TokenType:HandleToken(CurrentVA);
      END;
      VMRelease(CurrentVA);
      IF KeyPressed() THEN done := UserSuspendsSearch() END;
      done := done OR (SearchResult > SearchWarned);
      done := done OR (NOT ReceiveData(InData^[0], CurrentVA));
   UNTIL done;
   CloseForReceiving(InData^[0]);

   done := (SearchResult > SearchWarned);
   IF (NOT done) AND AnyPos THEN
      DiscardList(WList);	(* *LP* *)
      WList := NewMemoryList( PoolNoForSearchWorkingSpace );
      MakeWordList(TList, WList);
      IF NOT GetFirstItem(WList,WListPos) THEN
         ProgramErrorAndHalt('expected WList items in DoFreq')
      END;
      REPEAT CheckCollectedPos UNTIL done OR (NOT GetNextItem(WList,WListPos));
      DiscardList(WList);
   END;
   DiscardList(TList);
   DiscardList(WList);	(* *LP* *)

   IF (NOT RuleWindowData.IgnoreErrs) AND (NumbFound = 0) AND (SearchResult <= SearchWarned) THEN
      (*RES OLD MSG 256
      Your FREQ Query selected nothing.
      *)
      PutResWarning( (*RES REM INS*) 256 );
      SearchResult := SearchWarned;
   END;
   CloseForSending(OutData);
END DoFreq;

PROCEDURE DumpFreqSpec(ident:  CARDINAL; Spec:   FreqItem);
(*<Dbg
VAR t:  FreqItem;
    BlankStr:            ARRAY[0..80] OF CHAR;

PROCEDURE TWriteIndent;
BEGIN
   ConstStr(' ',indent,BlankStr);
   TWriteString(BlankStr);
END TWriteIndent;
Dbg>*)

BEGIN
(*<Dbg
   t := Spec;
   WHILE t <> NIL DO
      TWriteIndent;
      TWriteCard(t^.Low,0);
      TWriteString(':');
      TWriteCard(t^.High,0);
      TWriteLn;
      t := t^.Next;
   END;
Dbg>*)
END DumpFreqSpec;
END FreqBase.
