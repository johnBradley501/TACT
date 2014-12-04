IMPLEMENTATION MODULE VariDisplay;
(* copyright (c) 1989-96 John Bradley, Geoffrey Rockwell, Lidio Presutti, University of Toronto *)

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
(*V2=Empty *)


IMPORT Str, ASCII, Lib;
FROM SYSTEM IMPORT BYTE ;
FROM GlobalDefs IMPORT StrAny;
FROM WWWUtils IMPORT DoStartPre, DoEndPre;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM Translations IMPORT
  (* Const *) IntTab,IntEnhOn, IntEnhOff,
  (* Type  *) TabInfo, TabType;
FROM MainLists IMPORT
  (* type *) PosListStatusType,
  (* vars *) SelectedList, ListByPosition,
             PosListStatus, SelectedListPos, PositionListPos,
             SelectedListEmpty, ListByType, TypeListPos, ListByTypeMade;
FROM ListData IMPORT
  (* types *) ItemType,DataItemPntr;
FROM TACTListModule IMPORT
  (* types *) TACTList;
FROM PositionManagement IMPORT
  (* types *) PositionItem,
  (* procs *) GetPosData, FirstDisplayItem,
              LastDisplayItem, CopyDisplayItem, NextDisplayItem,
              PrevDisplayItem, FindDisplayItem, DiscardDisplayItem,
              InitialDisplayItem, PrepareDisplayForItem;
FROM ListUtils IMPORT MakePosList, MakeWordList;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM DisplayDialog IMPORT
  (* type *) DisplayType, DisplayDataType, DispOrg,
  (* vars *) DisplayData, CurrentDisplay;
FROM HyperBase IMPORT HRecPntr, CompareHRecs ;
FROM ResMessages IMPORT
   (*proc*)  GetResMessage, PutResError;
FROM RefValBase IMPORT
  (* Procs *) CreateRef ;
FROM LineBase IMPORT DisplayContextLines, HandleTokenType;
FROM Translations IMPORT XFileType,WriteWithTabs;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMAccess, VMMarkChanged, VMRelease;

(*<Empty*)

CONST
   WSSize = 4000;
   MarkerSymbol = 020C;

PROCEDURE OutputVariableDisplay(VAR file: XFileType);
VAR
   status:       BOOLEAN;
   NoLines:      CARDINAL;
   result:       CARDINAL;

   VarDispTab:   ARRAY[0..0] OF TabInfo;
   WorkingList:  TACTList;
(* CurPos:       PositionItem; *)

PROCEDURE DoTheDisplay;

VAR
   ThisType:     ItemType;
   TokenVA:      VirtAddr;
   TypeVA:       VirtAddr;
   CatVA:        VirtAddr;
   ListPos:      PositionItem;
   StillMore:    BOOLEAN; (* ScrollInstruction; *)

PROCEDURE WriteLine(text: ARRAY OF CHAR);
VAR dummy:  BOOLEAN;
BEGIN
   INC(NoLines);
   dummy := WriteWithTabs(file, text, VarDispTab);
END WriteLine;

PROCEDURE GenContextLine( VAR DispText : ARRAY OF CHAR; Len : CARDINAL );
   (* note: use "pass by ref" -- no modification of DispText *)
   VAR
	LPlen   : CARDINAL ;
	K	: CARDINAL ;
        text    : StrAny;
   BEGIN
        K := 0;
        SWriteString(text,K,'  ',0);
        SWriteString(text,K,DispText,0);
        WriteLine(text);
   END GenContextLine ;

PROCEDURE DoContext() ;
VAR
   StartTPntr, EndTPntr: HRecPntr;
BEGIN
   WITH DisplayData[Variable] DO
      DisplayContextLines(TokenVA, UnitID, DispBefore, DispAfter,
                          DisplayStart, StartTPntr, EndTPntr);
   END;
   END DoContext ;

PROCEDURE DoRef( FlushType : TabType;Bold:  BOOLEAN );
   VAR
	RefText:	StrAny;
	Line:		StrAny;
	LP:		CARDINAL;
	RefLen:		CARDINAL;
   BEGIN
	LP := 0;
(*      IF Bold THEN SWriteString(Line,LP,'ú<Bú>',0); END; *)

	CreateRef( DisplayData[Variable].EncodedRefInfo,
		DisplayData[Variable].EncodedRefLen, TokenVA, RefText, RefLen ) ;
	Line[LP] := IntEnhOn ;
	INC( LP ) ;
	
	IF (FlushType = Right) AND (78 >= RefLen) THEN
	   WITH VarDispTab[0] DO
		Pos := 78 ;
		FilPat := '-';(* 304C ; should use IntRuleChar - not exported ... yet JB?? *)
		Type := Right ;
	   END ;	
	   Line[LP] := IntTab ;
	   INC( LP ) ;
	   Line[LP] := ' ' ; (* a blank after rule line *)
	   INC( LP ) ;
	ELSE  (* Left or does not fit in window size -- make it flush Left *)
	   WITH VarDispTab[0] DO
		Pos := 0 ;
		FilPat := '' ;
		Type := Left ;
	   END ;
	END ;
	SWriteString(Line, LP, RefText, 0);
(*      IF Bold THEN SWriteString(Line,LP,'ú</Bú>',0); END; *)
	Line[LP] := IntEnhOff ;
	INC( LP ) ;
	Line[LP] := 0C ;

        WriteLine(Line);
    END DoRef ;

PROCEDURE DoBar() ;
   VAR
        Text:           ARRAY[0..5] OF CHAR;
   BEGIN
	VarDispTab[0].Pos := 77 ;
(*	VarDispTab[0].FilPat := 304C ;*) (* should use IntRuleChar - not exported ... yet JB?? *)  
	VarDispTab[0].FilPat := '-' ;
	VarDispTab[0].Type := Right ;

	Text[0] := ' ' ;
	Text[1] := ' ' ;
	Text[2] := IntTab ;
	Text[3] := ' ' ; (* a blank after rule Line *) 
	Text[4] := 0C ;
	WriteLine(Text);
    END DoBar ;

PROCEDURE GetNewPosInfo(): BOOLEAN;
VAR
   NextExists:   BOOLEAN;
BEGIN
   IF NextDisplayItem(WorkingList, ListPos) THEN
      GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);
      RETURN TRUE
   ELSE
      RETURN FALSE
   END;
END GetNewPosInfo;

PROCEDURE DoTypeItem();
BEGIN
   DoContext();
   DoRef( (* Flush *) Right, FALSE ) ;
END DoTypeItem;

PROCEDURE DoTypeHeader();
VAR
   TString:       StrAny;
   Text:          StrAny;
   LP:            CARDINAL;
BEGIN
   LP := 0;
   PrepareDisplayForItem(ListPos,99,'',0,TString);
   SWriteString(Text,LP,'ú<Bú>',0);
   SWriteString(Text,LP,TString,0);
   SWriteString(Text,LP,'ú</Bú>',0);
   WriteLine(Text);
END DoTypeHeader;

PROCEDURE HandleType(): BOOLEAN;
VAR
   CurrentType:     VirtAddr;
   More:            BOOLEAN;
BEGIN
   CurrentType := TypeVA;
   More := TRUE;
   REPEAT
      IF TokenVA = NILVirt THEN DoTypeHeader()
      ELSE DoTypeItem() END;
      More := GetNewPosInfo();
   UNTIL (NOT More) OR (TypeVA <> CurrentType);
   RETURN More;
END HandleType;

PROCEDURE HandleToken(): BOOLEAN;
BEGIN
   DoRef( (* Flush *) Left, TRUE ) ;
   DoContext() ;
   DoBar() ;
   RETURN GetNewPosInfo();
END HandleToken;

BEGIN  (* DoTheDisplay *)
   InitialDisplayItem(ListPos);
   IF NOT FirstDisplayItem(WorkingList, ListPos) THEN
      ProgramErrorAndHalt('unexpected problem in FirstDisplayItem')
   END;
   GetPosData(ListPos,ThisType,TokenVA,TypeVA,CatVA);

   REPEAT
      CASE ThisType OF
        CatType:    ProgramErrorAndHalt('CatType not yet supported here!')
      | TypeType:
           StillMore := HandleType();
      | TokenType:
           StillMore := HandleToken();
      ELSE
           ProgramErrorAndHalt('Illegal DataType in List')
      END;
   UNTIL (NOT StillMore);
   DiscardDisplayItem(WorkingList,ListPos);
END DoTheDisplay;

PROCEDURE InitialLists;
BEGIN
   IF (DisplayData[Variable].VariableDispOrg = DispType) THEN
      IF NOT ListByTypeMade THEN
         MakeWordList(SelectedList, ListByType);
         ListByTypeMade := TRUE
      END;
      WorkingList := ListByType;
(*    CurPos := TypeListPos; *)
   ELSIF (DisplayData[Variable].VariableDispOrg = DispPosition) AND
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
(* DiscardDisplayItem( WorkingList, CurPos );
   IF NOT FindDisplayItem(SelectedList, SelectedListPos,
			  WorkingList, CurPos) THEN
          ProgramErrorAndHalt('Could not synchonize Selected & Working list')
   END; *)
END InitialLists;

BEGIN
(*
   IF SelectedListEmpty THEN
      (*RES OLD MSG 250
      There is no Variable Context Display for printing or writing to a file.
      *)
      PutResError( (*RES REM INS*) 250 );
      RETURN
   END;
*)
   WITH VarDispTab[0] DO
      Pos := 3 ;
      Type := Left;
      FilPat := '';
   END;

   InitialLists;
   DoStartPre();
   DoTheDisplay;
   DoEndPre();
END OutputVariableDisplay;

END VariDisplay.
