IMPLEMENTATION MODULE KWICDisplay;
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
              InitialDisplayItem, PrepareDisplayForItem;
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

CONST
VAR
   XLength:    CARDINAL;
   CitCentre:  CARDINAL;

PROCEDURE OutputKWICDisplay(VAR file:       XFileType;
                                IncludePre: BOOLEAN);
VAR
   KWICDisplayTab: ARRAY[0..0] OF TabInfo;
   WorkingList:    TACTList;
(* CurPos:         PositionItem;*)
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

PROCEDURE ReturnTokenLine(TokenVA:   VirtAddr);
VAR
   TokenPntr:      DataItemPntr;
   TokenNo:        LONGINT;
   RefText:	   StrAny;
   Line:           StrAny;
   LP:             CARDINAL;
   RefLen:	   CARDINAL;
   len:            CARDINAL;
   FP:             HRecPntr;
BEGIN
   LP := 0;
(* SWriteString(Line, LP, '  ', 0); *)
   CreateRef( DisplayData[KWIC].EncodedRefInfo,
		DisplayData[KWIC].EncodedRefLen, TokenVA, RefText, RefLen ) ;
   SWriteString(Line, LP, RefText, 0);

   IF DisplayData[KWIC].ShowText THEN
      IF LP > CitCentre - 2 THEN (* added j.b. Feb 28/91 *)
         LP := CitCentre - 2;
         Line[LP] := 0C;
         Line[LP-1] := '.';
         Line[LP-2] := '.';
         Line[LP-3] := '.';
      END;
      TokenPntr := VMAccess(TokenVA);
      IF NOT TokenPntr^.TokenDataLoaded THEN
         VMMarkChanged(TokenVA);
         GetTDBTokenData(TokenPntr)
      END;
      FP.Rec := TokenPntr^.TokenFileData.TRecNo;
      FP.Idx := TokenPntr^.TokenFileData.TRecPos;
      FillOutWithCitation(FP,TokenPntr^.FilePos,Int2File,XLength,CitCentre,Line);
      VMRelease(TokenVA);
   END;
   WriteLine(Line);
END ReturnTokenLine;

PROCEDURE ReturnTypeHeader(TypeVA:     VirtAddr);
VAR
   len:           CARDINAL;
   TString:       StrAny;
   Text:          StrAny;
   LP:            CARDINAL;
BEGIN
   PrepareDisplayForItem( ListPos, 99, DisplayData[KWIC].EncodedRefInfo,
	   DisplayData[KWIC].EncodedRefLen, TString );
   LP := 0;
   SWriteString(Text,LP,TString,0);
   WriteLine(Text);
END ReturnTypeHeader;

PROCEDURE GetNewPosInfo(): BOOLEAN;
VAR
   NextExists:   BOOLEAN;
BEGIN
   IF DisplayData[KWIC].KWICDispOrg = DispTypeOnly THEN
      NextExists := NextMainItem(WorkingList, ListPos)
   ELSE
      NextExists := NextDisplayItem(WorkingList, ListPos)
   END ;

   IF NextExists THEN
      GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);
   END;
   RETURN NextExists;
END GetNewPosInfo;

PROCEDURE HandleToken(): BOOLEAN;
BEGIN
   ReturnTokenLine(TokenVA);
   RETURN GetNewPosInfo();
END HandleToken;

PROCEDURE HandleType(): BOOLEAN;
VAR
   CurrentType:     VirtAddr;
BEGIN
   CurrentType := TypeVA;
   WHILE TypeVA = CurrentType DO
      IF (TokenVA = NILVirt) OR (DisplayData[KWIC].KWICDispOrg = DispTypeOnly) THEN
	 IF (DisplayData[KWIC].KWICDispOrg = DispTypeOnly) THEN
	    GetParentMainItem( WorkingList, ListPos ) ;
	    GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);
	 END ;
	 ReturnTypeHeader(TypeVA)
      ELSE
	 ReturnTokenLine(TokenVA)
      END;
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
         | TokenType:  MoreData := HandleToken();
         ELSE
              ProgramErrorAndHalt('Illegal DataType in List')
         END;
      UNTIL NOT MoreData;
      DiscardDisplayItem(WorkingList,ListPos);
END CreateDisplay;

PROCEDURE InitialLists;
BEGIN
   IF (DisplayData[KWIC].KWICDispOrg = DispType) OR
      (DisplayData[KWIC].KWICDispOrg = DispTypeOnly) THEN
      IF NOT ListByTypeMade THEN
         MakeWordList(SelectedList, ListByType);
         ListByTypeMade := TRUE
      END;
      WorkingList := ListByType;
(*    CurPos := TypeListPos; *)
   ELSIF (DisplayData[KWIC].KWICDispOrg = DispPosition) AND
	 (PosListStatus <> PosOnly) THEN
      IF PosListStatus = NoPos THEN
         PosListStatus := PosMade;
         MakePosList(SelectedList, ListByPosition);
      END;
      WorkingList := ListByPosition;
(*    CurPos := PositionListPos; *)
   ELSE
      WorkingList := SelectedList;
(*    CurPos := SelectedListPos; *)
      RETURN
   END;
(* DiscardDisplayItem( WorkingList, CurPos ); *)
END InitialLists;

BEGIN
   IF IncludePre THEN DoStartPre(); END;
(* IF SelectedListEmpty THEN
      (*RES UPD MSG 249
      Your query selected nothing to display.
      *)
      PutResError( (*RES REM INS*) 249 );
      RETURN
   END;
*)
   WITH KWICDisplayTab[0] DO
      Pos := 30;
      Type := Left;
      FilPat := '';
   END;

   InitialLists;

   XLength := DisplayData[KWIC].LineLength;
   CitCentre := DisplayData[KWIC].CitCentre;

   CreateDisplay(file);
   IF IncludePre THEN DoEndPre(); END;
END OutputKWICDisplay;

END KWICDisplay.
