IMPLEMENTATION MODULE WordDisplay;
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


IMPORT Str, ASCII ;
IMPORT TACTProcesses;
FROM GlobalDefs IMPORT StrAny;
FROM WWWUtils IMPORT DoStartPre, DoEndPre;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM Utils IMPORT Beep ;
FROM Translations IMPORT Int2File, XFileType, XWrNXlate, WriteWithTabs,
  (* Const *) IntTab,
  (* Type  *) TabInfo, TabType;
FROM MainLists IMPORT
  (* type *) PosListStatusType,
  (* vars *) SelectedList, ListByPosition,
             PosListStatus, SelectedListPos, PositionListPos,
             SelectedListEmpty, ListByType, TypeListPos, ListByTypeMade;
FROM ListData IMPORT
  (* types *) ItemType,DataItemPntr,
  (* procs *) MakeStringData;
FROM TACTListModule IMPORT
  (* types *) TACTList;
FROM PositionManagement IMPORT
  (* types *) PositionItem,
  (* procs *) GetPosData, FirstDisplayItem,
              LastDisplayItem, CopyDisplayItem, NextDisplayItem,
              PrevDisplayItem, GetParentMainItem, NextMainItem, PrevMainItem,
              FindDisplayItem, DiscardDisplayItem,
              InitialDisplayItem, PrepareTypeItemForDisplay;
FROM ListUtils IMPORT MakePosList, MakeWordList;
FROM WordBase IMPORT
              SortToIntWord;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM DisplayDialog IMPORT
  (* type *) DisplayType, DisplayDataType, DispOrg,
  (* vars *) DisplayData, CurrentDisplay;
FROM HyperBase IMPORT HRecPntr;
FROM HyperDataModel IMPORT
  (* Types *) HTypeData;
FROM DBData IMPORT
    (* vars  *) BeginText;
FROM ResMessages IMPORT
   (*proc*)  GetResMessage, PutResError;
FROM TokenBase IMPORT
  (* procs *) GetTokenNo;
FROM RefValBase IMPORT
  (* Procs *) CreateRef ;
FROM CitationTools IMPORT
  (* procs*) FillOutWithCitation;
FROM TACTDataServices IMPORT GetTDBTokenData;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMAccess, VMMarkChanged, VMRelease;

PROCEDURE OutputWordDisplay(VAR file: XFileType);
VAR
   KWICDisplayTab: ARRAY[0..0] OF TabInfo;
   WorkingList:    TACTList;
   CurPos:         PositionItem;
   NoLines:        CARDINAL;

PROCEDURE CreateDisplay(VAR file: XFileType);
VAR
   ThisType:     ItemType;
   TokenVA:      VirtAddr;
   TypeVA:       VirtAddr;
   CatVA:        VirtAddr;
   ListPos:      PositionItem;
   MoreData:     BOOLEAN;

PROCEDURE WriteLine(text: ARRAY OF CHAR);
VAR dummy:  BOOLEAN;
BEGIN
   INC(NoLines);
   dummy := WriteWithTabs(file, text, KWICDisplayTab);
END WriteLine;

PROCEDURE ReturnTypeHeader(TypeVA:     VirtAddr);
VAR
   TString:       StrAny;
BEGIN
   PrepareTypeItemForDisplay( ListPos, TString );
   WriteLine(TString);
END ReturnTypeHeader;

PROCEDURE GetNewPosInfo(): BOOLEAN;
VAR
   NextExists:   BOOLEAN;
BEGIN
   NextExists := NextMainItem(WorkingList, ListPos);
   IF NextExists THEN
      GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);
   END;
   RETURN NextExists;
END GetNewPosInfo;

PROCEDURE HandleType(): BOOLEAN;
VAR
   CurrentType:     VirtAddr;
BEGIN
   CurrentType := TypeVA;
   WHILE TypeVA = CurrentType DO
      GetParentMainItem( WorkingList, ListPos ) ;
      GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);
      ReturnTypeHeader(TypeVA);
      IF (NOT GetNewPosInfo()) THEN RETURN FALSE END;
   END;
   RETURN TRUE;
END HandleType;

BEGIN
      NoLines := 1 ;
      InitialDisplayItem(ListPos);
      IF NOT FirstDisplayItem(WorkingList, ListPos) THEN
         ProgramErrorAndHalt('unexpected problem in DoNewItem')
      END;
      GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);

      REPEAT
         CASE ThisType OF
           CatType:    ProgramErrorAndHalt('CatType not yet supported here!')
         | TypeType:   MoreData := HandleType();
         ELSE
              ProgramErrorAndHalt('Illegal DataType in List')
         END;
      UNTIL NOT MoreData;
      DiscardDisplayItem(WorkingList,ListPos);
END CreateDisplay;

PROCEDURE InitialLists;
BEGIN
   IF NOT ListByTypeMade THEN
      MakeWordList(SelectedList, ListByType);
      ListByTypeMade := TRUE
   END;
   WorkingList := ListByType;
   CurPos := TypeListPos;
   DiscardDisplayItem( WorkingList, CurPos );
END InitialLists;

BEGIN
   DoStartPre();
   IF SelectedListEmpty THEN
      (*RES UPD MSG 249
      Your query selected nothing to display.
      *)
      PutResError( (*RES REM INS*) 249 );
      DoEndPre();
      RETURN
   END;
   WITH KWICDisplayTab[0] DO
      Pos := 30;
      Type := Left;
      FilPat := '';
   END;

   InitialLists;
   CreateDisplay(file);
   DoEndPre();
END OutputWordDisplay;

END WordDisplay.
