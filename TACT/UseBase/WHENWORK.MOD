IMPLEMENTATION MODULE WhenWork;

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
(*V4=Dbg Debugging code *)
(*V5=NoDbg No Debugging code *)

(*  NOTE:
	IF StructID >= 0 THEN numeric field
	ELSE string field END;
*)
IMPORT Str ;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo;
FROM HyperDataModel IMPORT HLogDataType;
FROM HyperBase IMPORT HRecPntr ;
FROM ListData IMPORT
  (* Types *) DataItemPntr, ItemType, StringPntr,
  (* Procs *) MakeRefStringItem, MarkAsUsed ;
FROM WordBase IMPORT
  (* Procs *) IntToSortWord, FullToSortWord ;
IMPORT RULES ;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM GlobalDefs IMPORT StrAny;
FROM ScannerSource IMPORT
  (* type *) ItemDataType;
FROM ParserSource IMPORT
  (* procs *) Parser;
FROM ErrorBase IMPORT  ProgramErrorAndHalt;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames, NumbOfRefUnits,
   (* procs *) DisplayRefNameList, LookupRefName, GetNameFromID;
FROM RefValBase IMPORT
  (* procs *) GetLogDataForToken, GetLogDataIntStr, GetLogDataSortStr;
FROM ResMessages IMPORT
   (*proc*)  MsgString, MsgCard, PutResError, ResAskUser, PutResWarning;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, GetListType, DisposeListItem, GetItemData,
              GetFirstItem, GetNextItem, GetPrevItem, FindFromString,
              ItemDataPresent, DiscardList, ReleaseItemHold;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, InsertListItem, ListPoolNo;
FROM TACTDataServices IMPORT DisposeDataItem, VirtToTACTList, DoRefSelectionWindow ;
FROM OccurListModule IMPORT InitializeOccurList;
FROM DataLinkModule IMPORT
  (* types *) DataLink, DataLinkType, DataLinkArrayPntr,
  (* procs *) OpenForSending, OpenForReceiving, SendData, ReceiveData,
              CloseForSending, CloseForReceiving;
FROM SearchUtils IMPORT
   (* types *) SearchResultType,
   (* vars  *) SearchResult, CurrPosOnSelListArray, NumberInSelListArray,
               SelectedListArray,
   (* procs *) UserSuspendsSearch;
FROM KeyBase IMPORT
  (* procs *) KeyPressed;
FROM RuleWindow IMPORT
  (* cons *)  CriteriaTooBig,
  (* type *)  RuleWindowDataType,
  (* vars *)  RuleWindowData,
  (* Procs *) SubstituteInCriteria;
FROM DBData IMPORT
  (* Consts *) BeginStr, EndStr, BeginStrRec, NoStrRecs, FolioID ;
FROM RefStrListModule IMPORT
  (* procs *) SelectRefStrWind, InitialRefStrList;
FROM RefStrInit IMPORT GetRefStrRecInfo ;
FROM RegularExpr IMPORT
  (* proc *) ParseRegExp, DoRegExp ;
FROM SelectWindow IMPORT
  (* proc *) DoSelectWindow;
FROM MainLists IMPORT PoolNoForSearchWorkingSpace;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMRelease, VMMarkChanged, VMAccess;

(*<Dbg
FROM Trace IMPORT
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard,
              TWriteAddr, TWriteStrHex, CloseTFile;
FROM Utils IMPORT ConstStr;
Dbg>*)

TYPE
   RefType = (Undefined, String, Number);
   WhenOp = (WhenAnd, WhenOr, WhenNot, WhenLeafString,
             WhenEQ, WhenGT, WhenGE, WhenLT, WhenLE, WhenRange);
   WhenItem = POINTER TO WhenRecord;
   WhenRecord = RECORD
      CASE Type: WhenOp OF
         WhenAnd, WhenOr:
            Left:       WhenItem;
            Right:      WhenItem;
       | WhenNot:
            Item:       WhenItem;
       | WhenLeafString:
            RefID:      INTEGER;
            ListNo:     CARDINAL;
       | WhenEQ:
            ERefID:     INTEGER;
            EVal:       CARDINAL;
       | WhenGT, WhenGE, WhenLT, WhenLE:
            NRefID:     INTEGER;
            Val:        CARDINAL;
       | WhenRange:
            RRefID:     INTEGER;
            Low:        CARDINAL;
            High:       CARDINAL;
      END;
      Others : WhenItem; (* has no meaning with type: WhenOr, WhenAnd *)
   END;

VAR
(*<Dbg
    BlankStr:            ARRAY[0..80] OF CHAR;
Dbg>*)
    RefStrSelectWind:    WindowInfo;

PROCEDURE NewWhenAndOr(T:     WhenOp;
                       L,R:   WhenItem): WhenItem;
VAR
   P:    WhenItem;
BEGIN
   NEW(P);
   WITH P^ DO
      Type := T;
      Left := L;
      Right := R;
      Others := NIL ;
   END;
   RETURN P;
END NewWhenAndOr;

PROCEDURE NewWhenNot(I: WhenItem): WhenItem;
VAR
   P:    WhenItem;
BEGIN
   NEW(P);
   WITH P^ DO
      Type := WhenNot;
      Item := I;
      Others := NIL ;
   END;
   RETURN P;
END NewWhenNot;

PROCEDURE NewWhenLeafString(ID : INTEGER): WhenItem;
VAR
   P:    WhenItem;
BEGIN
   NEW(P);
   WITH P^ DO
      Type := WhenLeafString;
      RefID := ID;
      INC( CurrPosOnSelListArray ) ;
      IF CurrPosOnSelListArray > NumberInSelListArray THEN
	 INC( NumberInSelListArray ) ;
	 SelectedListArray[NumberInSelListArray] := NewMemoryList(PoolNoForSearchWorkingSpace);
      END ;
      ListNo := CurrPosOnSelListArray ;
      Others := NIL ;
   END;
   RETURN P;
END NewWhenLeafString;

PROCEDURE NewWhenEQ(ID:   CARDINAL;
                    V:    CARDINAL): WhenItem;
VAR
   P:    WhenItem;
BEGIN
   NEW(P);
   WITH P^ DO
      Type := WhenEQ;
      ERefID := ID;
      EVal := V;
      Others := NIL;
   END;
   RETURN P;
END NewWhenEQ;

PROCEDURE NewWhenNumbComp(T:     WhenOp;
                          ID:    CARDINAL;
                          V:     CARDINAL): WhenItem;
VAR
   P:    WhenItem;
BEGIN
   NEW(P);
   WITH P^ DO
      Type := T;
      NRefID := ID;
      Val := V;
      Others := NIL ;
   END;
   RETURN P;
END NewWhenNumbComp;

PROCEDURE NewWhenRangeItem(ID:       CARDINAL;
                           L,H:      CARDINAL): WhenItem;
VAR
   P:    WhenItem;
BEGIN
   NEW(P);
   WITH P^ DO
      Type := WhenRange;
      Others := NIL;
      RRefID := ID;
      Low := L;
      High := H;
   END;
   RETURN P;
END NewWhenRangeItem;

PROCEDURE DisposeWhenItem(VAR gItem: ADDRESS);
VAR Item: WhenItem;
BEGIN
   Item := WhenItem(gItem);
   IF Item = NIL THEN  RETURN  END ;
   CASE Item^.Type OF
     WhenAnd, WhenOr:
        DisposeWhenItem(Item^.Left);
        DisposeWhenItem(Item^.Right);
   | WhenNot:
        DisposeWhenItem(Item^.Item);
   ELSE (* do nothing here *)
   END;
   IF Item^.Others <> NIL THEN DisposeWhenItem(Item^.Others) END;
   DISPOSE(Item);
   gItem := NIL;
END DisposeWhenItem;

PROCEDURE BuildWhenByParsing(VAR RuleNo:      CARDINAL;
                             VAR ItemData:    ItemDataType;
                             VAR Result:      WhenItem;
                             VAR RepeatParse: BOOLEAN): BOOLEAN;
CONST
   NumbInItemStack = 30;
TYPE
   LogPackType = RECORD
		CASE : CARDINAL OF
		0 : Count : CARDINAL ; |
		1 : SPos  : CHAR ;
		    SRec  : CHAR ;
		END ;
	    END ;
   EqTypeType = (EqStr, EqReg, EqSelW);
VAR
   StackPos:    INTEGER ;  (* changed to point to TOP element of Stack *LP* *)
   Stack:       ARRAY [0..NumbInItemStack-1] OF WhenItem;
   Numb1:       CARDINAL;
   Numb2:       CARDINAL;
   RefID:       INTEGER;
   dummy:       BOOLEAN;
   EqualityType:EqTypeType;
   DoingEquality: BOOLEAN;
   HoldOp:      WhenOp;
   RefName:     ARRAY[0..20] OF CHAR;
   LastItem:    WhenItem;
   TempItem:    WhenItem;
   StrItem:	WhenItem;
   StrVA:       VirtAddr;
   StrData:	DataItemPntr;
   TList:	TACTList;
   NumbFound:	CARDINAL;
   TempStr:	StrAny;
   tPat:        ARRAY[0..80] OF CHAR;
   typeonly:    BOOLEAN;
   LogPtr:	LogPackType ;
   ch:		CHAR ;
   Pos:		HRecPntr;
   TempPos:	HRecPntr;
   RefIDDefined:BOOLEAN;
   StartedAllStrs : BOOLEAN ;
   ShouldBeFolio: BOOLEAN;
   IsFolio:     BOOLEAN;
   NumbStr:     ARRAY [0..12] OF CHAR;

PROCEDURE CleanupRefID ;
   BEGIN
	(* release TList & StrVA if needed here ??? *)
	IF RefIDDefined THEN
	   IF StrVA <> NILVirt THEN DisposeDataItem( StrVA ) END;
	   DiscardList( TList ) ;
	   RefIDDefined := FALSE ;
	END;
   END CleanupRefID ;

PROCEDURE CleanupStack;
BEGIN
   WHILE (StackPos >= 0) DO
      DisposeWhenItem(Stack[StackPos]);
      DEC(StackPos);
   END;
   CleanupRefID ;
END CleanupStack;

PROCEDURE PutMustBeNumeric;
BEGIN
   (*RES OLD MSG 179
   "%0" cannot be used in a numeric WHEN selection.
   *)
   MsgString(RefName,0);
   PutResError( (*RES REM INS*) 179 );
   CleanupStack;
END PutMustBeNumeric;

PROCEDURE PutMustBeString;
BEGIN
   (*RES OLD MSG 214
   Please do not use "%0" in a WHEN Query.
   *)
   MsgString(RefName,0);
   PutResError( (*RES REM INS*) 214 );
   CleanupStack;
END PutMustBeString;

PROCEDURE CheckString( VAR string : ARRAY OF CHAR ) : BOOLEAN ;
   VAR
	dummy	: BOOLEAN ;
	Item	: TACTListItem ;
	ch	: CHAR ;
	StrDataIntStrPtr : StringPntr ;
   BEGIN
	IntToSortWord( string, TempStr ) ;
	NewListItem( TList, Item ) ;
	IF FindFromString( TempStr, RefStringType, TList, Item ) THEN
	   GetItemData(TList, Item, StrVA, StrData);
           ReleaseItemHold(TList, Item);
	   StrData := VMAccess(StrVA);

	ELSE
(*RES OLD CHE 7
The reference string "%0" is not found in the text database. Choose
between S)elect, or E)dit:
=SE
*)
	   MsgString( string, 0 ) ;
	   ResAskUser( (*RES REM INS *) 7 , 'SE', ch ) ;
	   IF ch = 'S' THEN
		IF SelectRefStrWind( RefID, StrVA ) THEN
		   (* insert selected ref string into display lines *)
		   StrData := VMAccess(StrVA);
		   StrDataIntStrPtr := VMAccess( StrData^.IntStrVA ) ;
                   IF NOT SubstituteInCriteria(RuleWindowData.Criteria,
			ItemData.WhichLine,ItemData.WhichPos, Str.Length(string),
			StrDataIntStrPtr^.String) THEN
                      PutResError( CriteriaTooBig );
                      CleanupStack;
		      VMRelease(StrVA);
                      RETURN FALSE;
                   END;
                   VMRelease( StrData^.IntStrVA ) ;
		ELSE
		   CleanupStack ;
		   RETURN FALSE ;
		END ;
	   ELSE
		RepeatParse := FALSE ;
		CleanupStack ;
		RETURN FALSE ;
	   END ;
	END ;
	VMMarkChanged(StrVA);
	MarkAsUsed( StrData ) ;  (* keep StrData around *)
	DisposeListItem( TList, Item ) ;
        EqualityType := EqStr;
	VMRelease(StrVA);
	RETURN TRUE ;
   END CheckString ;

PROCEDURE DoStrEqProcessing():BOOLEAN;
VAR
   ch:         CHAR;
   templist:   TACTList;
   SelectItem: TACTListItem;
   SelectItem2:TACTListItem;
   dummy:      DataItemPntr;
   FunctKey:   BOOLEAN;
   BDummy:     BOOLEAN;
   selected:	BOOLEAN;
BEGIN
   CASE EqualityType OF
     EqStr:
        BDummy := InsertListItem( StrVA, SelectedListArray[StrItem^.ListNo] )
   | EqReg:
        DoRegExp( TList, SelectedListArray[StrItem^.ListNo], NumbFound, tPat ) ;
        IF NumbFound = 0 THEN
           (* no matches of Reg Expr *)
           CleanupStack ;
	   RETURN FALSE ;
        END ;
   | EqSelW:
        NewListItem(TList,SelectItem);
        IF NOT GetFirstItem(TList,SelectItem) THEN
           ProgramErrorAndHalt('Error in DoRefSelectionWindow')
        END;
        REPEAT
	   IF NOT DoSelectWindow(RefStrSelectWind, TList, SelectedListArray[StrItem^.ListNo],
		templist, ListPoolNo(SelectedListArray[StrItem^.ListNo]),
                SelectItem, ch, FunctKey,BDummy,FALSE) THEN
	      DiscardList(templist);
	      DisposeListItem( TList, SelectItem ) ;
	      CleanupStack ;
	      RETURN FALSE
	   END;
	   NewListItem(templist,SelectItem2);
	   selected := GetFirstItem(templist, SelectItem2) ;
	   DisposeListItem( templist, SelectItem2 ) ;
	   IF NOT selected THEN
	      (*RES OLD MSG 263
	      You selected nothing. Please use the INSert key to choose one or more entries.
	      *)
	      PutResError( (*RES REM INS *) 263 ) ;
	   END ;
        UNTIL selected ;
        DiscardList( SelectedListArray[StrItem^.ListNo] );
        SelectedListArray[StrItem^.ListNo] := templist;
	DisposeListItem( TList, SelectItem ) ;
   END;
   RETURN TRUE ;
END DoStrEqProcessing;

PROCEDURE DoWhenCompareBuildNow;
VAR
   Data:   DataItemPntr;
   DVA:    VirtAddr;
   Item:   TACTListItem;
   dummy:  BOOLEAN;
   StartRec, StartIdx, EndRec, EndIdx : CARDINAL ;
BEGIN
   IF RefID < 0 (* string field *) THEN
     NewListItem(TList, Item);

     IF NOT FindFromString(TempStr, RefStringType, TList, Item) THEN

         (* if not there, FindFromString will be pointing one past,
         we want one >before< here! *)

         dummy := GetPrevItem(TList, Item);
	 CASE HoldOp OF
	   WhenGT : HoldOp := WhenGE ; |
	   WhenLT : HoldOp := WhenLE ;
	   ELSE  (* do nothing *)
	 END ;
      END ;
      (* Note: SRec + SPos overlaid with Count for 8088 word format *)
      GetRefStrRecInfo( RefID, StartRec, StartIdx, EndRec, EndIdx ) ;
      GetItemData(TList, Item, DVA, Data);
      LogPtr.SRec := CHR( Data^.FilePos.Rec - StartRec (* BeginStr *) ) ;
      LogPtr.SPos := CHR( Data^.FilePos.Idx ) ;
      Numb1 := LogPtr.Count ;
      DoingEquality := FALSE ;
      ReleaseItemHold(TList, Item);
      DisposeListItem(TList, Item);
   END;
   TempItem := NewWhenNumbComp( HoldOp, RefID, Numb1 );
END DoWhenCompareBuildNow;

PROCEDURE ConvertStrToNumber(VAR Rslt: CARDINAL): BOOLEAN;
VAR  len: CARDINAL;
     ch:  CHAR;
BEGIN
   IF IsFolio AND (NOT ShouldBeFolio) THEN
      (*RES OLD MSG 394
      Please avoid using "%0" as a Folio Number for Reference ID "%1" in a WHEN Query.
      *)
      MsgString(NumbStr,0);
      MsgString(RefName,0);
      PutResError( (*RES REM INS*) 394 );
      CleanupStack;
      RETURN FALSE
   ELSIF (NOT IsFolio) AND (ShouldBeFolio) THEN
      (*RES OLD MSG 395
      Please use "%0" as a Folio Number for Reference ID "%1" in a WHEN Query.
      *)
      MsgString(NumbStr,0);
      MsgString(RefName,0);
      PutResError( (*RES REM INS*) 395 );
      CleanupStack;
      RETURN FALSE
   END;
   IF IsFolio THEN
      len := Str.Length(NumbStr);
      ch := CAP(NumbStr[len-1]);
      NumbStr[len-1] := 0C;
      Rslt := CARDINAL(Str.StrToCard(NumbStr, 10, dummy)) * 2;
      IF ch = 'R' THEN DEC(Rslt) END;
   ELSE
      Rslt := CARDINAL(Str.StrToCard(NumbStr, 10, dummy));
   END;
   RETURN TRUE
END ConvertStrToNumber;

BEGIN	(* BuildWhenByParsing *)
   RepeatParse	:= FALSE;
   StackPos	:= -1 ;
   StrVA := NILVirt;
   RefIDDefined := FALSE;
   WHILE (RuleNo <> RULES.EndOfWhen) AND (RuleNo < 999 (* no SYNTAX error *) ) DO
      CASE RuleNo OF
        RULES.WhenOrRule:
           Stack[StackPos-1] := NewWhenAndOr(WhenOr,
                                             Stack[StackPos-1],
                                             Stack[StackPos]);
(*	   DisposeWhenItem( Stack[StackPos] ) ; *)
	   Stack[StackPos] := NIL ;
           DEC(StackPos);
      | RULES.WhenAndRule:
           Stack[StackPos-1] := NewWhenAndOr(WhenAnd,
                                             Stack[StackPos-1],
                                             Stack[StackPos]);
(*	   DisposeWhenItem( Stack[StackPos] ) ; *)
	   Stack[StackPos] := NIL ;
           DEC(StackPos);
      | RULES.WhenNumberIsDigSeq:
           IsFolio := FALSE;
           Str.Copy(NumbStr, ItemData.IntStr)
      | RULES.WhenNumberIsFolSeq:
           IsFolio := TRUE;
           Str.Copy(NumbStr, ItemData.IntStr)
      | RULES.WhenNotRule:
           Stack[StackPos] := NewWhenNot(Stack[StackPos]);
      | RULES.DoRefNameDone:
	   IF RefID < 0 THEN
		DiscardList( TList ) ;
		DisposeDataItem( StrVA ) ;
	   END ;
           RefIDDefined := FALSE;
      | RULES.DoRefNameSelectForWhen:
           CleanupStack;
	   IF NOT DoRefSelectionWindow( RefID, RefName ) THEN
              RETURN FALSE
           END;
           (* replace the "?" *)
           IF NOT SubstituteInCriteria( RuleWindowData.Criteria,
           ItemData.WhichLine,ItemData.WhichPos, 1, RefName) THEN
              PutResError( CriteriaTooBig );
              RETURN FALSE;
           END;
           RepeatParse := TRUE;
           RETURN TRUE
      | RULES.GetWhenRefName:
           FullToSortWord(ItemData.AlpStr,RefName);
           IF NOT LookupRefName(RefName,Numb1) THEN
	      CleanupStack;
(*RES OLD CHE 8
In this "When" statement, "%0" is not the name of a reference. Choose between
S)elect, or E)dit:
=SE
*)
              MsgString(ItemData.IntStr,0);
	      ResAskUser( (*RES REM INS *) 8 , 'SE', ch ) ;
	      IF ch = 'S' THEN
		 RepeatParse := TRUE;
		 IF NOT DoRefSelectionWindow( RefID, RefName ) THEN
		    RETURN FALSE
		 END;
		 IF NOT SubstituteInCriteria(RuleWindowData.Criteria,
			ItemData.WhichLine, ItemData.WhichPos, Str.Length(ItemData.IntStr),
			RefName) THEN
		    PutResError( CriteriaTooBig );
		    RETURN FALSE
		 END;
		 RETURN TRUE
	      ELSE
		 RepeatParse := FALSE;
		 RETURN FALSE
	      END ;
           END;
           Str.Copy( RefName, ItemData.IntStr);
           RefID := RefsNameListPntr^[Numb1]^.ID;
           IF RefID < 0 THEN
	      TList := InitialRefStrList( RefID ) ;
	      RefIDDefined := TRUE;
           ELSIF RefID = 0 THEN ShouldBeFolio := FALSE
           ELSE ShouldBeFolio := (VAL(CARDINAL,RefID) IN FolioID);
           END ;
      | RULES.DoFirstWhenList:
	   IF (RefID < 0) AND DoingEquality THEN
	      TempItem := NewWhenLeafString( RefID ) ;
	      StrItem  := TempItem ;
	      StartedAllStrs := TRUE ;
              IF NOT DoStrEqProcessing() THEN  RETURN FALSE  END;
           ELSE
	      StartedAllStrs := FALSE ;
	   END ;
           INC(StackPos);
           Stack[StackPos] := TempItem;
           LastItem := TempItem;
      | RULES.DoSubsequentWhenList:
	   IF (RefID < 0) AND DoingEquality THEN
	      IF NOT StartedAllStrs THEN
		 StrItem := NewWhenLeafString( RefID ) ;
		 LastItem^.Others := StrItem ;
		 LastItem := StrItem;
		 StartedAllStrs := TRUE ;
	      END ;
              IF NOT DoStrEqProcessing() THEN  RETURN FALSE  END;
	   ELSE
	      LastItem^.Others := TempItem ;
	      LastItem := TempItem;
           END ;
      | RULES.DoWhenEqual1, RULES.DoWhenEqual2 :
	   DoingEquality := TRUE ;
      | RULES.DoWhenCompare:
           DoWhenCompareBuildNow;
      | RULES.DoWhenGT:
           HoldOp := WhenGT;
      | RULES.DoWhenGE:
           HoldOp := WhenGE;
      | RULES.DoWhenLT:
           HoldOp := WhenLT;
      | RULES.DoWhenLE:
           HoldOp := WhenLE;
      | RULES.DoLogicalOperStr1, RULES.DoLogicalOperStr2:
	   IntToSortWord( ItemData.IntStr, TempStr ) ;
      | RULES.DoLGNumbConvert:
           IF NOT ConvertStrToNumber(Numb1) THEN RETURN FALSE END;
      | RULES.DoRegExpStr:
	   (* this is triggered after DoStartRegExp *)
	   IF typeonly THEN
	      IF NOT CheckString( ItemData.IntStr ) THEN
		 RETURN FALSE
	      END ;
	   ELSE
              EqualityType := EqReg;
	   END ;
      | RULES.DoStartRegExp:
           IF RefID >= 0 THEN		(* catch verse = 15.*  etc. *)
              PutMustBeString ;
              CleanupStack ;
              RETURN FALSE ;
           END ;
	   IF NOT ParseRegExp( RuleNo, ItemData, tPat, typeonly ) THEN
		CleanupStack ;
		RETURN FALSE;
	   END ;
      | RULES.DoEqualNumb:
           IF RefID < 0 (* string field *) THEN
	      IF NOT CheckString( ItemData.IntStr ) THEN
		 RETURN FALSE
	      END ;
	   ELSE
              IF NOT ConvertStrToNumber(Numb1) THEN RETURN FALSE END;
	      TempItem := NewWhenEQ(RefID, Numb1);
	   END ;
      | RULES.DoEqualStr:
           IF RefID >= 0 THEN
              PutMustBeString ;
              CleanupStack ;
              RETURN FALSE ;
           END ;
	   IF NOT CheckString( ItemData.IntStr ) THEN
		 RETURN FALSE
	   END ;
      | RULES.DoRefSelectWindow:
           IF RefID >= 0 THEN
              PutMustBeString ;
              CleanupStack ;
              RETURN FALSE ;
           END ;
           EqualityType := EqSelW;
      | RULES.SaveLowNumberFromRange:
           IF RefID < 0 (* string field *) THEN
              PutMustBeNumeric;
              CleanupStack;
              RETURN FALSE
           END;
           IF NOT ConvertStrToNumber(Numb1) THEN RETURN FALSE END;
      | RULES.LastWhenRule:
           IF NOT ConvertStrToNumber(Numb2) THEN RETURN FALSE END;
           IF Numb2 < Numb1 THEN
              (*RES OLD MSG 194
              You cannot use the range "%0:%1" in a WHEN Selection.
              *)
              MsgCard(Numb1,0);
              MsgCard(Numb2,0);
              PutResError( (*RES REM INS*) 194 );
              CleanupStack;
              RETURN FALSE
           END;
           TempItem := NewWhenRangeItem(RefID, Numb1, Numb2);
      END;
      RuleNo := Parser(FALSE,ItemData);
(*<Dbg
      TWriteString('BuildWhenByParsing:Rule:');
      TWriteCard(RuleNo,7);
      TWriteString(',Item:');
      TWriteString(ItemData.IntStr);
      TWriteLn;
Dbg>*)
   END;
   IF RuleNo >= 999 THEN
	CleanupStack;
	RETURN FALSE
   ELSE
	IF StackPos <> 0 THEN  ProgramErrorAndHalt('BuildWhenByParsing: stack corrupted.') END;
	Result := Stack[StackPos];
	CleanupRefID ;
	RETURN TRUE;
   END ;
END BuildWhenByParsing;

PROCEDURE DoWhen(InData:  DataLinkArrayPntr; (* always 1 only *)
                 Numb:    CARDINAL;          (* always 1 only *)
                 OutData: DataLink;
                 Info:    ADDRESS); (* When item *)
VAR
    Tree:         WhenItem;
    NumbFound:    CARDINAL;
    CurrentDat:   DataItemPntr;
    CurrentVA:    VirtAddr;
    CurrentType:  ItemType;
    done:         BOOLEAN;

PROCEDURE HandleToken(VA:  VirtAddr);

    PROCEDURE RefValue(RefID:  INTEGER): CARDINAL;
	VAR
	   LogData: HLogDataType;
	BEGIN
	   GetLogDataForToken(VA,RefID,LogData);
	   RETURN LogData.Count;
	END RefValue;

    PROCEDURE RefStrValue( Tree : WhenItem ) : BOOLEAN ;
	VAR
	   LogData	: HLogDataType;
	   Pos		: HRecPntr ;
	   Item		: TACTListItem ;
	   Result	: BOOLEAN ;
	   StartRec, StartIdx, EndRec, EndIdx : CARDINAL ;
	BEGIN
	   GetLogDataForToken( VA, Tree^.RefID, LogData );

(* I assume that ItemDataPresent can be used here j.b.
	   MakeRefStringItem( Tree^.RefID, Data ) ;
	   MarkAsUsed( Data ) ;
	   GetRefStrRecInfo( Tree^.RefID, StartRec, StartIdx, EndRec, EndIdx ) ;
	   Data^.FilePos.Rec := ORD( LogData.SRecNo ) + StartRec (* BeginStr *) ;
	   Data^.FilePos.Idx := ORD( LogData.SRecPos ) ;
	   NewListItem( SelectedListArray[Tree^.ListNo], Item ) ;
	   Result := FindItem( SelectedListArray[Tree^.ListNo], Data, Item ) ;
	   (* release space for Data & Item here  *)
	   DisposeListItem( SelectedListArray[Tree^.ListNo], Item ) ;
	   DisposeRefStrData( Data ) ;
*)
	   GetRefStrRecInfo( Tree^.RefID, StartRec, StartIdx, EndRec, EndIdx ) ;
	   Pos.Rec := ORD( LogData.SRecNo ) + StartRec (* BeginStr *) ;
	   Pos.Idx := ORD( LogData.SRecPos ) ;
	   NewListItem( SelectedListArray[Tree^.ListNo], Item ) ;
           Result := ItemDataPresent( SelectedListArray[Tree^.ListNo],
		RefStringType, Pos, Item ) ;
	   DisposeListItem( SelectedListArray[Tree^.ListNo], Item ) ;
	   RETURN Result ;
	END RefStrValue ;

    PROCEDURE DoEvals( VAR Tree : WhenItem ): BOOLEAN;
	VAR
	    n    : CARDINAL;
	    loop : BOOLEAN ;
	BEGIN
	   n := RefValue( Tree^.NRefID ) ;  (* Note: RefIDs are overlaid on same mem area *)
	   loop := TRUE ;
	   WHILE loop AND (Tree <> NIL) DO
		CASE Tree^.Type OF
		   WhenEQ:
			IF n = Tree^.EVal THEN RETURN TRUE END;
		   | WhenRange:
			IF (n >= Tree^.Low) AND (n <= Tree^.High) THEN RETURN TRUE END;
		   | WhenGT:
			IF n > Tree^.Val THEN  RETURN TRUE  END ;
		   | WhenGE:
			IF n >= Tree^.Val THEN  RETURN TRUE  END ;
		   | WhenLT:
			IF n < Tree^.Val THEN  RETURN TRUE  END ;
		   | WhenLE:
			IF n <= Tree^.Val THEN  RETURN TRUE  END ;
		   ELSE
		END ;
		Tree := Tree^.Others ;
		IF Tree <> NIL THEN
		   CASE Tree^.Type OF
		     WhenEQ..WhenRange:
			(* do nothing here *)
		     ELSE
			loop := FALSE
		   END ;
		END ;
	   END ;
	   RETURN FALSE;
	END DoEvals;

PROCEDURE InWhen( Tree : WhenItem ) : BOOLEAN;
   VAR
	Temp : WhenItem ;
   BEGIN
	Temp := Tree ;
	WHILE Temp <> NIL DO
	   CASE Temp^.Type OF
	      WhenAnd:
		 IF NOT InWhen(Temp^.Left) THEN RETURN FALSE END;
		 RETURN InWhen(Temp^.Right)
	     | WhenOr:
		 IF InWhen(Temp^.Left) THEN RETURN TRUE END;
		 RETURN InWhen(Temp^.Right)
	     | WhenNot:
		 RETURN NOT InWhen(Temp^.Item)
	     | WhenLeafString:
		 IF RefStrValue( Temp ) THEN  RETURN TRUE  END ;
		 Temp := Temp^.Others ;
	     ELSE
		 IF DoEvals( Temp ) THEN  RETURN TRUE  END;
	   END;
	END ;
	RETURN FALSE ;
   END InWhen;

BEGIN
   IF InWhen(Tree) THEN
      done := NOT SendData(OutData, VA);
      INC(NumbFound);
   END;
END HandleToken;

PROCEDURE HandleType(TypeVA: VirtAddr (* To DataItem *) );
VAR
   TypeData	: DataItemPntr;
   List		: TACTList;
   PosList	: TACTList;
   PosItem	: TACTListItem;
   TokenVA	: VirtAddr (* to DataItem *);
   TokenDat	: DataItemPntr;
BEGIN
   TypeData := VMAccess(TypeVA);
   IF TypeData^.Contents = NILVirt THEN PosList := InitializeOccurList(TypeVA)
   ELSE VirtToTACTList(TypeData^.Contents, PosList) END;
   VMRelease(TypeVA);

   NewListItem(PosList, PosItem);
   IF GetFirstItem(PosList, PosItem) THEN
      REPEAT
         GetItemData(PosList, PosItem, TokenVA, TokenDat);
         ReleaseItemHold(PosList, PosItem);
         HandleToken(TokenVA);
      UNTIL done OR (NOT GetNextItem(PosList, PosItem));
   END;
   DisposeListItem(PosList, PosItem);
   DiscardList(PosList);
END HandleType;

BEGIN
   Tree := WhenItem(Info);
   NumbFound := 0;
   OpenForReceiving(InData^[0], DontCare);
   OpenForSending(OutData, DontCare);
   done := NOT ReceiveData(InData^[0], CurrentVA);
   IF done THEN
      CloseForReceiving(InData^[0]);
      CloseForSending(OutData);
      RETURN
   END;
   WHILE NOT done DO
      CurrentDat := VMAccess(CurrentVA);
      CurrentType := CurrentDat^.DataType;
      VMRelease(CurrentVA);
      CASE CurrentType OF
        CatType:  ProgramErrorAndHalt('Cat Type not yet supported in DoWhen')
      | TypeType: HandleType(CurrentVA);
      | TokenType:HandleToken(CurrentVA);
      END;
      IF KeyPressed() THEN done := UserSuspendsSearch() END;
      done := done OR (SearchResult > SearchWarned);
      done := done OR (NOT ReceiveData(InData^[0], CurrentVA));
   END;
   IF (NOT RuleWindowData.IgnoreErrs) AND (NumbFound = 0) AND (SearchResult <= SearchWarned) THEN
      (*RES OLD MSG 195
      Your WHEN Selection selected nothing.
      *)
      PutResWarning( (*RES REM INS*) 195 );
      SearchResult := SearchWarned;
   END;
   CloseForReceiving(InData^[0]);
   CloseForSending(OutData);
END DoWhen;

PROCEDURE TraceWhenTree(indent:  CARDINAL; Tree:   WhenItem);
(*<Dbg
PROCEDURE TWriteIndent;
BEGIN
   ConstStr(' ',indent,BlankStr);
   TWriteString(BlankStr);
END TWriteIndent;

PROCEDURE WriteComp(OpName: ARRAY OF CHAR);
BEGIN
   TWriteIndent;
   TWriteString(OpName);
   TWriteInt(Tree^.NRefID,0);
   TWriteChar(',',0);
   TWriteCard(Tree^.Val,0);
   TWriteLn;
END WriteComp;
Dbg>*)

BEGIN
(*<Dbg
   CASE Tree^.Type OF
     WhenAnd, WhenOr:
        TraceWhenTree(indent+5,Tree^.Right);
        TWriteIndent;
        IF Tree^.Type = WhenAnd THEN TWriteString('AND')
                                ELSE TWriteString('OR') END;
        TWriteLn;
        TraceWhenTree(indent+5,Tree^.Left);
   | WhenNot:
        TWriteIndent;
        TWriteString('NOT');
        TWriteLn;
        TraceWhenTree(indent+5,Tree^.Item);
   | WhenLeafString:
        TWriteIndent;
        TWriteString('LEAFSTRING');
        TWriteLn;
   | WhenEQ:
        TWriteIndent;
        TWriteString('EQ:');
        TWriteInt(Tree^.ERefID,0);
        TWriteChar(',',0);
        TWriteCard(Tree^.EVal,0);
        TWriteLn;
        IF Tree^.Others <> NIL THEN TraceWhenTree(indent,Tree^.Others) END;
   | WhenGT:
        WriteComp('GT:');
   | WhenGE:
        WriteComp('GE:');
   | WhenLT:
        WriteComp('LT:');
   | WhenLE:
        WriteComp('LE:');
   | WhenRange:
        TWriteIndent;
        TWriteString('RA:');
        TWriteInt(Tree^.ERefID,0);
        TWriteChar(',',0);
        TWriteCard(Tree^.Low,0);
        TWriteChar(':',0);
        TWriteCard(Tree^.High,0);
        TWriteLn;
        IF Tree^.Others <> NIL THEN TraceWhenTree(indent,Tree^.Others) END;
   END;
Dbg>*)
END TraceWhenTree;

PROCEDURE InitWhenWork;
BEGIN
    WITH RefStrSelectWind DO
        XPos :=   45;
        YPos :=   4;
        XSize := 25;
        YSize := 9;
        MxYSize := 9;
        Type := Dialog;
        AllowMove := TRUE;
        AllowResize := TRUE;
    END;
END InitWhenWork;
END WhenWork.
