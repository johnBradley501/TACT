IMPLEMENTATION MODULE DataLinkModule;
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


IMPORT TACTProcesses;
FROM SYSTEM IMPORT ADR;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM ListData IMPORT
  (* types *) DataItemPntr,
  (* procs *) MarkAsUsed;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, GetFirstItem, GetItemData, ReleaseItemHold,
              GetNextItem, GetListType, DisposeListItem, DiscardList;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, ListPoolNo, CopyList, InsertListItem;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM TACTDataServices IMPORT DisposeDataItem;
FROM MainLists IMPORT PoolNoForSearchWorkingSpace;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMModify, VMRelease;

CONST
(*  NumbInDirectLink = 10; *)
    NumbInDirectLink = 20;
    WSSize = 4000;
    ProcessDataBaseSize = 24; (* 5 * ADDRESS + 2 * CARDINAL *)

TYPE
(* kludge change to allow new JPI compiler to work!!   j.b.
   DataLink = POINTER TO DataLinkRecord;  *)

   DataLink = POINTER TO DataLinkRecord;
   DataLinkRecord = RECORD
       Full:    TACTProcesses.SIGNAL;
       Empty:   TACTProcesses.SIGNAL;
       EOF:     BOOLEAN;
       CASE Type :DataLinkType OF
          DontCare:
        | DirectLink:
             DataVA:      ARRAY[0..NumbInDirectLink-1] OF VirtAddr; (* to DataItem *)
             Used:        CARDINAL;
             Sent:        CARDINAL;
             RecShutDown: BOOLEAN;
        | ListLink:
             List:    TACTList;
             OutItem: TACTListItem;
             OutData: VirtAddr; (* to DataItem *)
             OldData: VirtAddr; (* to DataItem *)
             DispList:BOOLEAN;
       END;
   END;

   ProcessDataPntr = POINTER TO ProcessData;
   ProcessData = RECORD
      Size:        CARDINAL;
      Next:        ProcessDataPntr;
      DisposeData: DisposeDataProcType;
      Data:        ADDRESS;
      Proc:        DataLinkPROC;
      OutLink:     DataLink;
      NumbInLinks: CARDINAL;
      InLinks:     ARRAY[0..400] OF DataLink;
   END;

VAR
   ProcessDataQueue:   ProcessDataPntr;
   EndOfQueue :        ProcessDataPntr;

PROCEDURE SetDataLinkEmpty( VAR Link:  DataLink ) ;	(* *LP* *)
   BEGIN
	Link := NIL ;		(* Link better have not been allocated!! *)
   END SetDataLinkEmpty ;

PROCEDURE InitializeListByType(Link:  DataLink;
                               IType: DataLinkType;
                               Pool:  CARDINAL);

PROCEDURE InitLinkAsDirect(Link: DataLink);
BEGIN
   WITH Link^ DO
      Used := 0;
      Sent := 0;
      EOF := FALSE;
      RecShutDown := FALSE;
   END;
END InitLinkAsDirect;

PROCEDURE InitLinkAsList(Link: DataLink; Pool: CARDINAL);
BEGIN
   WITH Link^ DO
      DispList := TRUE;
      OutData := NILVirt;
      OldData := NILVirt;
      List := NewMemoryList(Pool);
      NewListItem(List,OutItem);
   END;
END InitLinkAsList;
BEGIN
   CASE IType OF
       DontCare:
     | DirectLink:
           InitLinkAsDirect(Link);
     | ListLink:
           InitLinkAsList(Link, Pool);
      END;
END InitializeListByType;

PROCEDURE InitLink(VAR Link:   DataLink;
                       IType:  DataLinkType);
BEGIN
   NEW(Link);
   WITH Link^ DO
      Type := IType;
      TACTProcesses.Init(Full);
      TACTProcesses.Init(Empty);
   END;
   InitializeListByType(Link,IType,PoolNoForSearchWorkingSpace);
END InitLink;

PROCEDURE InitAndDefineAsList(VAR Link:                DataLink;
                                  GList:               TACTList;
                                  DisposeListWhenDone: BOOLEAN);
BEGIN
   NEW(Link);
   WITH Link^ DO
      Type := ListLink;
      TACTProcesses.Init(Full);
      TACTProcesses.Init(Empty);
      List := GList;
      NewListItem(List,OutItem);
      OutData := NILVirt;
      OldData := NILVirt;
      DispList := DisposeListWhenDone;
      TACTProcesses.SEND(Full);
   END;
END InitAndDefineAsList;

PROCEDURE SelectType(MustAssign: BOOLEAN;
                     FromProc:   DataLinkType;
                 VAR FromLink:   DataLinkType): DataLinkType;
BEGIN
   IF MustAssign AND (FromProc = DontCare) THEN FromProc := DirectLink END;
   IF FromProc > FromLink THEN
      FromLink := FromProc;
      RETURN FromLink
   END;
   RETURN DontCare;
END SelectType;

PROCEDURE OpenForSending(VAR Link:  DataLink;
                             SType: DataLinkType);
BEGIN
   WITH Link^ DO
      InitializeListByType(Link,SelectType(FALSE,SType,Type),
                           PoolNoForSearchWorkingSpace);
      TACTProcesses.WAIT(Empty);
   END;
END OpenForSending;

PROCEDURE OpenForReceiving(VAR Link:  DataLink;
                               SType: DataLinkType);
BEGIN
   WITH Link^ DO
      InitializeListByType(Link,SelectType(TRUE,SType,Type),
                           PoolNoForSearchWorkingSpace);
      TACTProcesses.SEND(Empty);
      TACTProcesses.WAIT(Full);
      IF Type = ListLink THEN 
         TACTProcesses.YIELD;
(*       NewListItem(List,OutItem); *)
         EOF := NOT GetFirstItem(List,OutItem);
      END;
   END;
END OpenForReceiving;

PROCEDURE VMarkAsUsed(Data: VirtAddr (* to DataItem *) );
VAR Pntr:  DataItemPntr;
BEGIN
   Pntr := VMModify(Data);
   MarkAsUsed(Pntr);
   VMRelease(Data);
END VMarkAsUsed;

PROCEDURE SendData(VAR Link: DataLink;
                       Data: VirtAddr (* to DataItem *) ): BOOLEAN;
VAR dummy:   BOOLEAN;
BEGIN
   CASE Link^.Type OF
     DontCare: ProgramErrorAndHalt('DontCare in SendData');
   | DirectLink:
        WITH Link^ DO
           IF Sent >= NumbInDirectLink THEN
              TACTProcesses.SEND(Full);
              TACTProcesses.WAIT(Empty);
              IF RecShutDown THEN RETURN FALSE END;
              Sent := 0;
           END;
           DataVA[Sent] := Data;
           VMarkAsUsed(Data);
           INC(Sent);
        END;
   | ListLink:
        dummy := InsertListItem(Data,Link^.List);
   END;
   RETURN TRUE
END SendData;

PROCEDURE DisposeLink(VAR Link: DataLink);
BEGIN
   IF (Link = NIL) OR
      (Link^.Full = NIL) THEN
          RETURN  END ;  (* protect against empty DataLink *LP* *)
       (* m.s. - added check to be sure Link not deleted previously in cross reference *)
   WITH Link^ DO
      IF Type = ListLink THEN
          DisposeDataItem(OldData);
          DisposeListItem(List,OutItem);
          IF DispList THEN DiscardList(List) END;
      END;
      IF TACTProcesses.Awaited(Full) THEN TACTProcesses.SEND(Full) END;
      IF TACTProcesses.Awaited(Empty) THEN TACTProcesses.SEND(Empty) END;
      TACTProcesses.Dispose(Full);
      TACTProcesses.Dispose(Empty);
      DISPOSE(Link);
   END;
   Link := NIL;
END DisposeLink;

PROCEDURE CloseForSending(VAR Link: DataLink);
BEGIN
   WITH Link^ DO
      EOF := TRUE;
      TACTProcesses.SEND(Full);
   END;
END CloseForSending;

PROCEDURE ReceiveData(VAR Link: DataLink;
                      VAR Data: VirtAddr (* to DataItem *) ): BOOLEAN;
VAR i:     CARDINAL;
    Dummy: DataItemPntr;
BEGIN
   CASE Link^.Type OF
     DontCare: ProgramErrorAndHalt('DontCare in ReceiveData');
   | DirectLink:
        WITH Link^ DO
           IF Used >=Sent THEN
              IF Sent > 0 THEN
                 FOR i := 0 TO Sent-1 DO DisposeDataItem(DataVA[i]) END;
              END;
              IF EOF THEN RETURN FALSE END;
              TACTProcesses.SEND(Empty);
              TACTProcesses.WAIT(Full);
              IF EOF THEN TACTProcesses.YIELD END;
              Used := 0;
           END;
           Data := DataVA[Used];
           INC(Used);
        END;
   | ListLink:
        WITH Link^ DO
           IF EOF THEN RETURN FALSE END;
           DisposeDataItem(OldData);
           GetItemData(List, OutItem, OutData, Dummy);
           ReleaseItemHold(List, OutItem);
           VMarkAsUsed(OutData);
           Data := OutData;
           OldData := Data;
           EOF := NOT GetNextItem(List,OutItem);
        END;
   END;
   RETURN TRUE;
END ReceiveData;

PROCEDURE CloseForReceiving(VAR Link: DataLink);
VAR i:  CARDINAL;
BEGIN
   WITH Link^ DO
      CASE Type OF
        DontCare:   ProgramErrorAndHalt('Bad Type in CloseForReceiving');
      | DirectLink:
          RecShutDown := TRUE;
          TACTProcesses.SEND(Empty);
          IF Used < Sent THEN
             FOR i := Used TO Sent-1 DO DisposeDataItem(DataVA[i]) END;
          END;
      | ListLink:
      END;
   END;
   DisposeLink(Link);
END CloseForReceiving;

PROCEDURE GetTACTList(VAR Link:  DataLink; (* this disposes of it *)
                          Pool:  CARDINAL; (* suggested Pool # for List  j.b. *)
                      VAR OList: TACTList); (* list is already initialized *)
BEGIN
   WITH Link^ DO
      InitializeListByType(Link,SelectType(FALSE,ListLink,Type), Pool);
      TACTProcesses.SEND(Empty);
      TACTProcesses.WAIT(Full);
      TACTProcesses.YIELD;
      IF DispList AND ((GetListType(List) <> MemoryList) OR (Pool = ListPoolNo(List)) ) THEN
	 OList := List;
	 DispList := FALSE;	(* move here *LP* *)
      ELSE
         OList := NewMemoryList(Pool);
         CopyList(List, OList);
      END;
   END;
   DisposeLink(Link);
END GetTACTList;

PROCEDURE PutTACTList(VAR Link:  DataLink; (* this disposes of it *)
                          OList: TACTList);
BEGIN
   WITH Link^ DO
      Type := ListLink;
      List := OList;
      NewListItem(List,OutItem);
      TACTProcesses.SEND(Full);
   END;
END PutTACTList;

 (* ============================================================= *)

PROCEDURE DoProcess;
VAR ThisProcessData :    ProcessDataPntr;
    InLinkPntr :         DataLinkArrayPntr;
BEGIN
   ThisProcessData := ProcessDataQueue;
   ProcessDataQueue := ThisProcessData^.Next;
   WITH ThisProcessData^ DO
      InLinkPntr := ADR(InLinks);
      Proc(InLinkPntr, NumbInLinks, OutLink, Data);
      DisposeData(Data);
   END;
   DEALLOCATE(ThisProcessData,ThisProcessData^.Size);
   TACTProcesses.Terminate;
END DoProcess;

PROCEDURE BuildProcessData(DataIn:          ARRAY OF DataLink;
                           NumbDataIns:     CARDINAL;
                           DataOut:         DataLink;
                           Pgm:             DataLinkPROC;
                           DisposeDataProc: DisposeDataProcType;
                           PgmData:         ADDRESS);
VAR temp:   ProcessDataPntr;
    size:   CARDINAL;
    i:      CARDINAL;
BEGIN
   size := NumbDataIns * SIZE(ADDRESS) + ProcessDataBaseSize;
   ALLOCATE(temp,size);
   WITH temp^ DO
      Size := size;
      Next := NIL;
      NumbInLinks := NumbDataIns;
      FOR i := 1 TO NumbInLinks DO InLinks[i-1] := DataIn[i-1] END;
      Proc := Pgm;
      OutLink := DataOut;
      Data := PgmData;
      DisposeData := DisposeDataProc;
   END;
   IF EndOfQueue = NIL THEN ProcessDataQueue := temp
   ELSE EndOfQueue^.Next := temp END;
   EndOfQueue := temp;
END BuildProcessData;

PROCEDURE DummyDisposeDataProc(VAR dummy: ADDRESS);
BEGIN
END DummyDisposeDataProc;


PROCEDURE LaunchProcesses;
VAR temp:   ProcessDataPntr;
BEGIN
   temp := ProcessDataQueue;
   WHILE temp <> NIL DO
      TACTProcesses.StartProcess (DoProcess,WSSize);
      temp := temp^.Next;
   END;
   EndOfQueue := NIL;
END LaunchProcesses;

PROCEDURE DisposeProcessData;
VAR temp:   ProcessDataPntr;
    next:   ProcessDataPntr;
    i:      CARDINAL;
BEGIN
   temp := ProcessDataQueue;
   WHILE temp <> NIL DO
      next := temp^.Next;
      WITH temp^ DO
         DisposeData(Data);
         DisposeLink(OutLink);
         FOR i := 1 TO NumbInLinks DO DisposeLink(InLinks[i-1]) END;
      END;
      DEALLOCATE(temp,temp^.Size);
      temp := next;
   END;
   ProcessDataQueue := NIL;
   EndOfQueue := NIL;
END DisposeProcessData;

PROCEDURE InitDataLinks;
BEGIN
   ProcessDataQueue := NIL;
   EndOfQueue := NIL;
END InitDataLinks;
END DataLinkModule.
