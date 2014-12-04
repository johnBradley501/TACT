IMPLEMENTATION MODULE SelectWindow;

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

IMPORT ASCII, Str;
IMPORT TWB;
IMPORT PCKey;
IMPORT MagicChars;
FROM TACTInit IMPORT
 (* const *) NumberInTermList, NumberInExitList,
 (* vars  *) TermList, ExitList;
FROM ResMessages IMPORT
  (* procs *) PutResError, MsgString;
FROM Translations IMPORT
 (* var  *) Int2Alp, Int2Scr,
 (* type *) XlateStrAny, CurrentModeType, XFileType,
 (* proc *) XlateLine;
FROM WordBase IMPORT
  (* Procs *) SortToIntWord, FullToSortWord, IntToSortWord, WordSepCode;
FROM Utils IMPORT Beep;
FROM GlobalDefs IMPORT StrAny;
FROM MemoryManagement IMPORT ALLOCATE,DEALLOCATE;
FROM KeyBase IMPORT GetKeyStroke;
FROM HyperBase IMPORT HRecPntr;
FROM KeyStandards IMPORT
  (* const *) ListCharsExtSize,
  (* vars  *) ListCharsExt, ListCharsASC,
  (* types *) ListControlKeys,
  (* procs *) GetListControlKey;
FROM KeyTranslation IMPORT
  (* Const *) IntTab,
  (* Type  *) TabInfo, TabType, KeyCode (* m.s. *),
  (* Procs *) FancyScreenDisplay, GetScreenField, DoKeyTranslation (* m.s. *);
FROM CitationTools IMPORT
  (* procs*) FillOutWithCitation;
FROM ListData IMPORT
  (* types *) DataItemPntr, ItemType, StringPntr ;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, GetListType, CopyListItem,
              DiscardList, GetItemData, GetFirstItem, GetLastItem, GetNextItem,
              GetPrevItem, FindItem, FindFromString, ReleaseItemHold;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, CopyList, InsertListItem, DeleteListItem ;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM Windows IMPORT
  (* Const *) RegularAttr, BoldAttr,
  (* Procs *) ScrollUp, ScrollDown, ChangeColorOnScreen;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames;
FROM GetSequences IMPORT
  (* Const *) ExtendedFlagChar;
FROM RefValBase IMPORT
  (* Vars  *) LastEncodedRefPat, LastRefPatLen, LastDisplayWordCountWord,
  (* procs *) CreateRef;
FROM PrintModule IMPORT PrintActionType, PrintMaster, AbortProc,
     WriteWithTabs;
FROM TACTDataServices IMPORT GetTDBTokenData;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMAccess, VMRelease ;

CONST
   RefNameSepChar = '#' ;	(* >>> should IMPORT from RuleIO ?? <<< *)
TYPE
   SelectWindowDataPntr = POINTER TO SelectWindowData;
   SelectWindowData = RECORD
     NextSWD:      SelectWindowDataPntr;
     CurWind:      WindowInfo;
     ListIn:       TACTList;
     NewListOut:   TACTList;
     StartAtData:  TACTListItem;
     OneSelect:    BOOLEAN;

     LWindow:      TWB.WinType;
     LinesBefore:  CARDINAL;
     LinesAfter:   CARDINAL;
     CitCentre:    CARDINAL;
     XLength:      CARDINAL;
     DisplayLine:  StrAny;
     i:            CARDINAL;
     TopPos:       TACTListItem;
     BottomPos:    TACTListItem;
     CurrentPos:   TACTListItem;
(*   TopDat:       DataItemPntr;
     BottomDat:    DataItemPntr;
     CurrentDat:   DataItemPntr; *)
     CurrentY:     CARDINAL;
     BotY:         CARDINAL;
     ScrollSize:   CARDINAL;
     Done:         BOOLEAN;
     ignore:       BOOLEAN;
     DoChange:     BOOLEAN;
   END;

VAR
   LocalFunctList:  RECORD
      CASE : BOOLEAN OF
        TRUE:
          FunctList: ARRAY [0 ..ListCharsExtSize + NumberInExitList - 1] OF CHAR
      | FALSE:
          LocalList: ARRAY [0..ListCharsExtSize] OF CHAR;
          ExitCopy:  ARRAY [0..NumberInExitList-1] OF CHAR
       END
   END;
   DisplayTab:   ARRAY[0..0] OF TabInfo;
   Current:      SelectWindowDataPntr;
   ch:           CHAR;
   FunctKey:     BOOLEAN;

PROCEDURE DisplayProc(OutList:   TACTList;
                      Item:      TACTListItem;
                      OneSelect: BOOLEAN;
                  VAR B:         ARRAY OF CHAR;
                  VAR Tab:       TabInfo);
VAR
   TP:      CARDINAL;
   RefLen:  CARDINAL;
   T1:      ARRAY[0..79] OF CHAR;
   Item2:   TACTListItem;
   TokenNo: LONGINT;
   FP:      HRecPntr;
   A:       DataItemPntr;
   CurDA:   VirtAddr;
   SPtr:    StringPntr;
BEGIN
   GetItemData(Current^.ListIn, Item, CurDA, A);
   TP := 2;
   B[0] := ' ';
   IF (NOT OneSelect) THEN
      NewListItem(OutList,Item2);
      IF FindItem(OutList,CurDA,Item2) THEN B[0] := '>' END;
      DisposeListItem(OutList,Item2);
   END;
   B[1] := ' ';
   CASE A^.DataType OF
    TypeType:
       SortToIntWord(A^.TypeFileData.Word,T1);
       SWriteString(B,TP,T1,0);
       WITH Tab DO
          Pos := 30;
          Type := Right;
          FilPat := '. ';
       END;
       SWriteChar(B,TP,IntTab,1);
       SWriteCard(B,TP,A^.TypeFileData.NoOccur,0)
   | TokenType:
       CreateRef( LastEncodedRefPat,LastRefPatLen, CurDA, T1, RefLen,
                  LastDisplayWordCountWord);
       SWriteString(B,TP,T1,0);

       IF NOT A^.TokenDataLoaded THEN GetTDBTokenData(A) END;
       IF TP <= Current^.CitCentre - 2 THEN
          FP.Rec := A^.TokenFileData.TRecNo;
          FP.Idx := A^.TokenFileData.TRecPos;
          FillOutWithCitation(FP,Int2Scr,Current^.XLength,Current^.CitCentre,TRUE, B);
       END;

   | RefNameType:
       SortToIntWord(RefsNameListPntr^[A^.FilePos.Idx]^.Name,T1);
       SWriteString(B,TP,T1,0);
   | CatType:
       SortToIntWord(A^.CatName,T1);
       SWriteString(B,TP,T1,0);
    | RefStringType:
       IF A^.IntStrVA <> NILVirt THEN
	  SPtr := VMAccess( A^.IntStrVA );
	  SWriteString(B,TP,SPtr^.String,0);
	  VMRelease( A^.IntStrVA );
       ELSE ProgramErrorAndHalt('RefStr Type has no value')
       END
    | RuleType:
       SWriteString(B,TP,A^.RuleName^.String,0);
       SWriteString(B,TP,':   ',0);
       IF A^.RuleLine <> NIL THEN SWriteString(B,TP,A^.RuleLine^.String,0) END;
    | FileNameType:
       SWriteString(B,TP,A^.FNameInt,0);
   ELSE
       ProgramErrorAndHalt('Data Type not yet supported here!')
   END;
   ReleaseItemHold(Current^.ListIn, Item);
(* DisposeListItem(OutList,Item) ; *)
END DisplayProc;

PROCEDURE OutputCurrentDisplay(VAR file:     XFileType;
                                   AskAbort: AbortProc);
VAR ListPos:      TACTListItem;
    DisplayLine:  StrAny;
    DisplayTab:   ARRAY[0..0] OF TabInfo;
BEGIN
   WITH Current^ DO
      NewListItem(ListIn, ListPos) ;
      IF NOT GetFirstItem(ListIn,ListPos) THEN
          ProgramErrorAndHalt('Unexpected problem in OutputCurrentDisplay')
      END;
      REPEAT
         DisplayProc(NewListOut,ListPos, OneSelect, DisplayLine,DisplayTab[0]);
      UNTIL NOT (WriteWithTabs(file,DisplayLine,DisplayTab) AND
      GetNextItem(ListIn,ListPos)) OR AskAbort();
      DisposeListItem(ListIn,ListPos);
   END;
END OutputCurrentDisplay;

PROCEDURE InitialDisplay;
VAR i:   CARDINAL;
BEGIN
    WITH Current^ DO
       XLength := CurWind.XSize - 2;
       CitCentre := (XLength DIV 2) + 8;
       LinesBefore := CurWind.YSize DIV 4;
       LinesAfter := CurWind.YSize - LinesBefore;
       ScrollSize := CurWind.YSize DIV 2;
       TWB.SetManualUpdate ( LWindow);
       TWB.Clear;
       DisplayProc(NewListOut,CurrentPos, OneSelect, DisplayLine,DisplayTab[0]);
       FancyScreenDisplay(LWindow,0,0,DisplayLine,DisplayTab,FALSE);
       DisposeListItem( ListIn, TopPos ) ;
       CopyListItem(ListIn,CurrentPos,TopPos);
       CurrentY := 0;
       i := 1;
       WHILE (i < LinesBefore) AND GetPrevItem(ListIn,TopPos) DO
          ScrollDown(LWindow,1);
          INC(i);
          INC(CurrentY);
          DisplayProc(NewListOut,TopPos, OneSelect, DisplayLine,DisplayTab[0]);
          FancyScreenDisplay(LWindow,0,0,DisplayLine,DisplayTab,FALSE);
       END;
       ChangeColorOnScreen(BoldAttr,0,CurrentY, 999);

       BotY := CurrentY+1;
       DisposeListItem( ListIn, BottomPos ) ;
       CopyListItem(ListIn,CurrentPos,BottomPos);
       WHILE (BotY < CurWind.YSize) AND GetNextItem(ListIn,BottomPos) DO
          DisplayProc(NewListOut,BottomPos, OneSelect, DisplayLine,DisplayTab[0]);
          FancyScreenDisplay(LWindow,0,BotY,DisplayLine,DisplayTab,FALSE );
          INC(BotY);
       END;
       DEC(BotY);

       TWB.SetAutoUpdate(LWindow);
   END;
END InitialDisplay;

PROCEDURE DoSelectWindow(VAR SelWind:      WindowInfo;
                         VAR GListIn:      TACTList;
                         VAR GOldListOut:  TACTList;
                         VAR GNewListOut:  TACTList;
			     PoolNo:	   CARDINAL; (* used when OneSelect = false *)
                         VAR GStartAtData: TACTListItem;
                         VAR TermCh:       CHAR;
                         VAR TermFunct:    BOOLEAN;
                         VAR DoRead:       BOOLEAN;
                             GOneSelect:   BOOLEAN ): BOOLEAN; (* do update *)
VAR
   TSWD:         SelectWindowDataPntr;
   ReturnResult: BOOLEAN;
   (* m.s. - for testing DoKeyTranslation *)
   Numb,x : CARDINAL ;
   Result, SearchString : StrAny ;
   Term : StrAny ;
   Codes : ARRAY[0..128] OF KeyCode ;
   FunctKey : BOOLEAN ;
   OK:   BOOLEAN ; (* m.s. - March 94*)
PROCEDURE DoCursorDown(): BOOLEAN;
BEGIN
   WITH Current^ DO
      IF NOT GetNextItem(ListIn,CurrentPos) THEN RETURN FALSE END;
      ChangeColorOnScreen(RegularAttr,0,CurrentY, 999);
      INC(CurrentY);
      IF (CurrentY > LinesAfter) AND GetNextItem(ListIn,BottomPos) THEN
         ScrollUp(LWindow,1);
         DEC(CurrentY);
         DisplayProc(NewListOut,BottomPos, OneSelect, DisplayLine,DisplayTab[0]);
         FancyScreenDisplay(LWindow,0,BotY,DisplayLine,DisplayTab,FALSE);
         IF NOT GetNextItem(ListIn,TopPos) THEN
            ProgramErrorAndHalt('Error in DoCursorDown, moving TopPos')
         END;
      END;
      ChangeColorOnScreen(BoldAttr,0,CurrentY, 999);
      RETURN TRUE;
   END;
END DoCursorDown;

PROCEDURE DoCursorUp(): BOOLEAN;
BEGIN
   WITH Current^ DO
      IF NOT GetPrevItem(ListIn,CurrentPos) THEN RETURN FALSE END;
      ChangeColorOnScreen(RegularAttr,0,CurrentY, 999);
      DEC(CurrentY);
      IF (CurrentY < LinesBefore) AND GetPrevItem(ListIn,TopPos) THEN
         ScrollDown(LWindow,1);
         INC(CurrentY);
         DisplayProc(NewListOut,TopPos, OneSelect, DisplayLine,DisplayTab[0]);
         FancyScreenDisplay(LWindow,0,0,DisplayLine,DisplayTab,FALSE);
         INC(BotY);
         IF (BotY >= CurWind.YSize) THEN
            DEC(BotY);
            IF NOT GetPrevItem(ListIn,BottomPos) THEN
               ProgramErrorAndHalt('Error in DoCursorUp, moving BottomPos')
            END
         END;
      END;
      ChangeColorOnScreen(BoldAttr,0,CurrentY, 999);
      RETURN TRUE;
   END;
END DoCursorUp;

PROCEDURE DoFind( VAR T : StrAny ) ;
CONST
    BadCharIndicator = 377C;
VAR
(* m.s.  T:              StrAny; (* internal form *) *)
   T2:             StrAny; (* sort form *)
   D:              XlateStrAny;
   AL,NS:          CARDINAL;
   ED:             BOOLEAN;
   LookingForType: ItemType;
   RemoveFirst:    BOOLEAN;
   ListOp:         ListControlKeys;
   WordNo:         LONGINT ;
   OK:             BOOLEAN ;
   cm:             CurrentModeType;
   TempName:       StrAny ;
   i,j,k:          CARDINAL ;
   len:            CARDINAL ;
   NeedPadding:    BOOLEAN ;
   PadStr:         ARRAY[0..5] OF CHAR ;

BEGIN

   WITH Current^ DO
      IF T[0] = 0C THEN
        TWB.GotoXY(0,CurrentY);
        TWB.ClrEol;
        GetScreenField(LWindow,CurWind.XSize-4,2,CurrentY,ListCharsASC,
                        LocalFunctList.FunctList,T,ch,FunctKey);
      ELSE
        ch := T[0] ;
      END ;
      DoRead := TRUE;
      IF T[0] = 0C THEN RETURN END;
      ListOp := GetListControlKey(FunctKey,ch);
      IF ListOp = ListCancel THEN RETURN END;
      DoRead := (ListOp = ListEnd);

      (* First -- try to figure out what type of data user is looking for *)
      RemoveFirst := FALSE;
      IF T[0] = MagicChars.CatID THEN
         LookingForType := CatType;
         RemoveFirst := TRUE
      ELSIF T[0] = MagicChars.WordID THEN
         LookingForType := TypeType;
         RemoveFirst := TRUE
(*    ELSIF (T[0] >= '0') AND (T[0] <= '9') THEN LookingForType := TokenType *LP* *)
      ELSE
        CASE GetListType(ListIn) OF
         MemoryList:   LookingForType := TypeType
       | FileNameList: LookingForType := FileNameType
       | CatList:      LookingForType := CatType
       | TypeList:     LookingForType := TypeType
       | RefNameList:  LookingForType := RefNameType
       | RefStrList:   LookingForType := RefStringType
       | RuleList:     LookingForType := RuleType
        ELSE           ProgramErrorAndHalt('Type not yet supported in DoFind')
        END;
      END;

      IF RemoveFirst THEN
          IF T[1] = 0C THEN
             MsgString(T[0],0);
             IF LookingForType = TypeType THEN
                (*RES OLD MSG 169
                Please give a word after the character "%0".
                *)
                PutResError( (*RES REM INS*) 169 );
             ELSIF LookingForType = CatType THEN
                (*RES OLD MSG 170
                Please give a Group Name after the character "%0".
                *)
                PutResError( (*RES REM INS*) 170 );
             ELSE
                (*RES OLD MSG 171
                Please supply some text after character "%0".
                *)
                PutResError( (*RES REM INS*) 171 );
             END;
             RETURN
          END;
          Str.Delete(T,0,1)
      END;

      CASE LookingForType OF
	TokenType :
		WordNo := Str.StrToInt( T, 10, OK ) ;
		IF NOT OK THEN
		   (*RES OLD MSG 201
		   "%0" contains invalid (non-numeric) characters for a
		   Word-Token Number.
		   *)
		   MsgString(T,0);
		   PutResError( (*RES REM INS*) 201 );
		   RETURN
		END ;
		Str.Copy( T2, T ) |
	RuleType:
		len := Str.Length( T ) ;	(* **LP** *)
		i := len-1 ;
		WHILE (i > 0) AND ( ('0' <= T[i]) AND (T[i] <= '9')) DO
			DEC( i ) ;
		END ;
		IF T[i] = RefNameSepChar THEN
			Str.Slice( TempName, T, 0, i ) ;
			PadStr[0] := WordSepCode ;
			FOR j := 1 TO 6 - (len-i) DO  PadStr[j] := '0'  END ;
			FOR k := i+1 TO len DO  PadStr[j] := T[k]; INC(j)  END ;
			NeedPadding := TRUE ;
		ELSE
			Str.Copy( TempName, T) ;
			NeedPadding := FALSE ;
		END ;
		IntToSortWord(TempName,T2);
		IF NeedPadding THEN  Str.Append( T2, PadStr )  END ;
	ELSE
		cm.ModeIn := '0'; cm.ModeOut := '0';
		XlateLine(Int2Alp,BadCharIndicator,T,cm,AL,D,NS,ED,T2);
		IF Str.Pos(T2,BadCharIndicator) < MAX(CARDINAL) THEN
		   (*RES OLD MSG 158
		   "%0" contains characters that cannot occur within the
		   name of a Word or Group.
		   *)
		   MsgString(T,0);
		   PutResError( (*RES REM INS*) 158 );
		   RETURN
		END;
		FullToSortWord(T2,T2);
      END;
      (* result doesn't matter *)
      ED := FindFromString( T2, LookingForType, ListIn, CurrentPos ) ;
   END; (* WITH Current^ ... *)
END DoFind;

PROCEDURE DoStateChange;

VAR Item:   TACTListItem;
    CurDat: VirtAddr;
    CurPtr: DataItemPntr;
    dummy:  BOOLEAN;
BEGIN
   WITH Current^ DO
      GetItemData(ListIn, CurrentPos, CurDat, CurPtr);
      ReleaseItemHold(ListIn, CurrentPos);
      NewListItem(NewListOut,Item);
      IF FindItem(NewListOut,CurDat,Item) THEN DeleteListItem(CurDat,NewListOut)
      ELSE dummy := InsertListItem(CurDat,NewListOut) END;

      DisplayProc(NewListOut,CurrentPos, OneSelect, DisplayLine, DisplayTab[0]);
      FancyScreenDisplay(LWindow,0,CurrentY,DisplayLine,DisplayTab,FALSE);
      ChangeColorOnScreen(BoldAttr, 0, CurrentY, 999);
      DisposeListItem(NewListOut,Item);
   END; (* WITH Current^ *)
END DoStateChange;

BEGIN  (* DoSelectWindow *)
   IF LocalFunctList.ExitCopy[0] = 0C THEN
      Str.Copy(LocalFunctList.LocalList,ListCharsExt);
      Str.Copy(LocalFunctList.ExitCopy,ExitList);
   END;

   NEW(TSWD);
   TSWD^.NextSWD := Current;
   Current := TSWD;
   WITH Current^ DO
      NextSWD := Current;
      CurWind := SelWind;
      ListIn := GListIn;
      NewListOut := GNewListOut;
      StartAtData := GStartAtData;
      OneSelect := GOneSelect;

      NewListItem( ListIn, TopPos ) ;   (* **LP** *)
      NewListItem( ListIn, BottomPos ) ;

      PushNewWindow(CurWind,LWindow, InitialDisplay);
      TWB.Use(LWindow);

      IF NOT OneSelect THEN
	 NewListOut := NewMemoryList( PoolNo );
	 CopyList(GOldListOut, NewListOut)
      END;
      CurrentPos := StartAtData;

      InitialDisplay;

      DoRead := TRUE;
      Done := FALSE;
      (* m.s. - for testing *)
      Result[0] := 0C ;
      Term[0] := 0C ;
      Numb := 0 ;
      REPEAT
          (* IF DoRead THEN GetKeyStroke(ch,FunctKey) END; *)
          OK := TRUE ;
          WHILE OK DO (* m.s. - march 94 - added loop to check for spaces *)
             DoKeyTranslation( Numb, SearchString , ExitList, ch, FunctKey ) ;
              IF (NOT FunctKey) AND (Numb > 0) AND (* if alphanumeric key *)
                (CARDINAL( SearchString[Numb-1]) = 32) THEN (* if space entered, ignore *)
                  DEC( Numb ) ;
                  SearchString[ Numb ] := 0C ;
                  OK := TRUE
             ELSE
               OK := FALSE ;
             END ;
          END ;
          DoRead := TRUE;
          IF FunctKey AND (ch = PCKey.ShiftF9) THEN
             PrintMaster(ToPrinter,OutputCurrentDisplay, DoRead, ch, FunctKey)
          ELSIF FunctKey AND (ch = PCKey.F9) THEN
             PrintMaster(ToDisk,OutputCurrentDisplay, DoRead, ch, FunctKey)
          ELSIF FunctKey AND (Str.Pos(ExitList,ch) < MAX(CARDINAL)) THEN
             Done := TRUE;
             DoChange := TRUE;
             DoRead := FALSE;
          ELSIF (NOT FunctKey) AND (Numb > 0) THEN
               DoFind( SearchString ) ;
               InitialDisplay;
          ELSIF (NOT FunctKey) AND (SearchString[0] = CHR(255)) THEN  (* m.s. - search for string *)
                  IF NOT GetFirstItem(ListIn,CurrentPos) THEN
                     ProgramErrorAndHalt('Working with NULL List')
                  END;
                  InitialDisplay;
                  SearchString[0] := 0C ;
          ELSE
             Numb := 0 ; (* m.s. - reset searchstring *)
             SearchString[0] := 0C ;
             CASE GetListControlKey(FunctKey, ch) OF
               PrevItem:
                  IF NOT DoCursorUp() THEN Beep  END;
             | NextItem:
                  IF NOT DoCursorDown() THEN Beep END;
             | PrevScreen:  (* m.s. - was PrevGroup *)
                  IF NOT GetPrevItem(ListIn,CurrentPos) THEN Beep
                  ELSE
                     i := 2;
                     WHILE (i <= ScrollSize) AND
                        GetPrevItem(ListIn,CurrentPos) DO INC(i) END;
                     InitialDisplay
                  END;
             | NextScreen:  (* m.s. - was NextGroup *)
                  IF NOT GetNextItem(ListIn,CurrentPos) THEN Beep
                  ELSE
                     i := 2;
                     WHILE (i <= ScrollSize) AND
                       GetNextItem(ListIn,CurrentPos) DO INC(i) END;
                     InitialDisplay
                  END;
             | FirstItem:
                  IF NOT GetFirstItem(ListIn,CurrentPos) THEN
                     ProgramErrorAndHalt('Working with NULL List')
                  END;
                  InitialDisplay;
             | LastItem:
                  IF NOT GetLastItem(ListIn,CurrentPos) THEN
                     ProgramErrorAndHalt('Working with NULL List')
                  END;
                  InitialDisplay;
             | SelectToggle:
                  IF OneSelect THEN
                     Done := TRUE;
                     DoChange := TRUE;
                     DoRead := TRUE ;
                  ELSE
                      DoStateChange ;
                      IF NOT DoCursorDown() THEN InitialDisplay END;
                  END ;
             | SelectAll:
                  IF OneSelect THEN
                     Beep
                  ELSE
                     IF GetListType(ListIn) = TypeList THEN
                        (*RES OLD MSG 176
                        UseBase cannot select all items from this List.
                        *)
                        PutResError( (*RES REM INS*) 176 );
                     ELSE
                        DiscardList(NewListOut);
                        NewListOut := NewMemoryList( PoolNo );
                        CopyList(ListIn, NewListOut);
                        InitialDisplay;
                     END;
                 END;
             | DeSelectAll:
                  IF OneSelect THEN
                     Beep
                  ELSE
                     DiscardList(NewListOut);
                     NewListOut := NewMemoryList( PoolNo );
                     InitialDisplay;
                  END;
             | ListEnd:
                  DoChange := TRUE;
                  Done := TRUE;
                  DoRead := TRUE;
             | ListCancel:
                  DoChange := FALSE;
                  Done := TRUE;
                  DoRead := TRUE;
             | MoveToItem:
                  DoFind( SearchString ) ;
                  InitialDisplay;
             ELSE Beep
             END;
          END;
      UNTIL Done;

      PopWindow;

      GStartAtData := CurrentPos;

      DisposeListItem(ListIn,TopPos) ;
      DisposeListItem(ListIn,BottomPos) ;
      IF NOT DoChange (* ie. cancel *) AND NOT OneSelect (* *LP2* *) THEN
         DiscardList(NewListOut); (* return memory *)
      END ;
      GNewListOut := NewListOut;
      TermCh := ch;
      TermFunct := FunctKey;
      ReturnResult := DoChange;
      SelWind := CurWind;
   END; (* WITH Current^ *)

   Current := Current^.NextSWD;
   DISPOSE(TSWD);
   RETURN ReturnResult;
END DoSelectWindow;

BEGIN
   WITH LocalFunctList DO
      LocalList[0] := 0C;
      ExitCopy[0] := 0C; (* to indicate that ExitList not yet included *)
   END;
   Current := NIL ;
END SelectWindow.
