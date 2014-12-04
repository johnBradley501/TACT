IMPLEMENTATION MODULE SpecialCharacters ;

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

(* This is code for the SpecialCharacters Menu for MAKEBASE *)

IMPORT PCKey;
FROM TWB        IMPORT WinType;
FROM SYSTEM     IMPORT ADDRESS;
FROM GlobalDefs IMPORT StrAny;
FROM Str	IMPORT Pos, Concat;
FROM Storage    IMPORT ALLOCATE, DEALLOCATE;
FROM StringIO   IMPORT SWriteString, SWriteCard, SWriteChar;
FROM Lists   IMPORT
  (* Procs *) NewList, SetToTop, MoveDown, GetData, DeleteListItem, FreeListPointer ;
FROM Windows IMPORT
  (* Consts *) RegularAttr, BoldAttr, SpecialAttr;
FROM ErrorBase IMPORT
  (* Proc   *) ProgramErrorAndHalt;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CharField, IntField, LongIntField, CardField,
                 Switches, SwitchValue, MakeMenu, DestroyMenu, GetFieldInfo,
                 ClearMenuArea, ShowFixedText, ShowMenu, DoMenu;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage,
            ResAskUser;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* vars  *) FieldMotionExt, FieldMotionASC,
  (* procs *) GetPanelControlKey;

(*RES OLD MNU 0
       Type:  Empty: %|0  Ignore: %|1  COCOA: %|2  Word Sep. Seq.: %|3




*)

VAR
   HDID:  MenuID;
   BDID:  MenuID;
   WSID:  MenuID;
   TPID:  MenuID;
   TempMenuID: MenuID ;
   Data:  SpecialCharDataType;

PROCEDURE BuildSpecialCharHeaderMenu;
BEGIN
   StartMenu(Data);
   WITH Data DO
      Switches(TypeOfSpecialChar);
         SwitchValue(EmptySCType);
         SwitchValue(IgnoreSCType);
         SwitchValue(ReferenceSCType);
         SwitchValue(WordSepSCType);
   END;
   MakeMenu((*RES REM INS*) 0 , HDID);
END BuildSpecialCharHeaderMenu;

PROCEDURE ShowHeaderOnly( WindowRec:  WinType;
                          OffX,OffY:  CARDINAL;
                          Data:       SpecialCharDataType ) ;
BEGIN

   ClearMenuArea(WindowRec, OffX,OffY, HDID);
   ShowFixedText(WindowRec,HDID,OffX,OffY);

   ShowMenu(WindowRec,HDID,OffX,OffY,Data);
END ShowHeaderOnly ;

(*RES OLD MNU 1
        Opening Bracket: %0____          Closing Bracket: %1____
                Suppress Text?       Yes: %|2  No: %|3
                Word Separator?      Yes: %|4  No: %|5
*)

PROCEDURE BuildBrackets ;
BEGIN
   StartMenu(Data);
   WITH Data DO
      CharField(OpenBracket);
      CharField(CloseBracket);
      Switches(SuppressText);
         SwitchValue(TRUE);
         SwitchValue(FALSE);
      Switches(WordSep);
         SwitchValue(TRUE);
         SwitchValue(FALSE);
   END;
   MakeMenu((*RES REM INS*) 1 , BDID);
END BuildBrackets ;

PROCEDURE ShowBrackets( WindowID:   WinType;
                        OffX,OffY:  CARDINAL ) ;
BEGIN
   ClearMenuArea(WindowID,OffX,OffY,BDID);
   ShowFixedText(WindowID,BDID,OffX,OffY);
END ShowBrackets ;

(*RES OLD MNU 2
                Word Separator Sequence: %0_____
 
 
*)

PROCEDURE BuildWordSep ;
BEGIN
   StartMenu(Data);
   WITH Data DO
      CharField(WordSepSeq);
   END;
   MakeMenu((*RES REM INS*) 2 , WSID);
END BuildWordSep ;

PROCEDURE ShowWordSep( WindowID:   WinType;
                       OffX,OffY:  CARDINAL ) ;
VAR   i:    CARDINAL;
BEGIN
   ClearMenuArea(WindowID,OffX,OffY,WSID);
   ShowFixedText(WindowID,WSID,OffX,OffY);

END ShowWordSep ;

(*RES OLD MNU 3
                      Reserved Characters Menu

             To move between items, press PgUp or PgDn.
             To return to the main menu, press "Enter / Return".
             To stop MakeBase, press F10.
*)
PROCEDURE BuildTopPanel;
BEGIN
   StartMenu(Data);
   MakeMenu((*RES REM INS*) 3 , TPID);
END BuildTopPanel ;

PROCEDURE BuildDetailMenu;
BEGIN
   BuildBrackets ;
   BuildWordSep ;
   BuildTopPanel;
END BuildDetailMenu;

PROCEDURE ShowDetailMenu( WindowRec:  WinType;
                          OffX,OfsY:  CARDINAL;
                          Data:       SpecialCharDataType ) ;
VAR     OffY:    CARDINAL;
        i:       CARDINAL;
BEGIN
   OffY := OfsY + 2;

   CASE Data.TypeOfSpecialChar OF
      WordSepSCType:
         ShowWordSep( WindowRec, OffX, OffY ) ;
         TempMenuID := WSID ;
      ELSE
         ShowBrackets( WindowRec, OffX, OffY ) ;
         TempMenuID := BDID ;
   END ;
   ShowMenu(WindowRec,TempMenuID,OffX,OffY,Data);
END ShowDetailMenu ;

PROCEDURE GetDetailData( WindowRec:     WinType;
                          OffX,OffY:     CARDINAL;
                          Term:          ARRAY OF CHAR;
                          FunctTerm:     ARRAY OF CHAR;
                      VAR Data:          SpecialCharDataType;
                      VAR ItemNumb:      CARDINAL;
                      VAR TC:            CHAR;
                      VAR FunctKey:      BOOLEAN );
BEGIN
   OffY := OffY + 2;
   CASE Data.TypeOfSpecialChar OF
      WordSepSCType:
         TempMenuID := WSID ;
      ELSE
         TempMenuID := BDID ;
   END ;
   DoMenu(WindowRec,TempMenuID,OffX,OffY,Term,FunctTerm,
                 Data,ItemNumb,TC,FunctKey);
END GetDetailData;

PROCEDURE MakeSCMenus;
BEGIN
   BuildSpecialCharHeaderMenu;
   BuildDetailMenu;
END MakeSCMenus;

PROCEDURE DestroySCMenus;
BEGIN
   DestroyMenu(HDID);
   DestroyMenu(BDID);
   DestroyMenu(WSID);
   DestroyMenu(TPID);
END DestroySCMenus;

PROCEDURE ShowSCMenu(WindowRec:   WinType;
                     OffX,OffY:   CARDINAL;
                     Dta:         ADDRESS);
VAR Data:    SpecialCharDataPntr;
BEGIN
   Data := Dta;
   ShowHeaderOnly( WindowRec,OffX,OffY,Data^);
   IF Data^.TypeOfSpecialChar <> EmptySCType THEN
      ShowDetailMenu( WindowRec,OffX,OffY,Data^)
   END
END ShowSCMenu;

PROCEDURE GetSCMenu(WindowRec:  WinType;
                          OffX,OfY:       CARDINAL;
                          Term:          ARRAY OF CHAR;
                          FunctTerm:     ARRAY OF CHAR;
                      VAR Dta:           ADDRESS;
                      VAR ItemNumb:      CARDINAL;
                      VAR TC:            CHAR;
                      VAR FunctKey:      BOOLEAN );
VAR  trm,ftrm: ARRAY[0..40] OF CHAR;
     Data:     SpecialCharDataPntr;
     OffY:     CARDINAL;
     hd:       SpecialCharType;
     done:     BOOLEAN;
     i:        CARDINAL;
     itemn1:   CARDINAL;
     MovedDown:BOOLEAN;
     MovedUp:  BOOLEAN;
     TermPushed:BOOLEAN;
     MovedOutSide: BOOLEAN;

PROCEDURE SetMotionVars;
BEGIN
   TermPushed := ( (NOT FunctKey) AND (Pos(Term,TC) <=      HIGH(Term))) OR
                 ( FunctKey       AND (Pos(FunctTerm,TC) <= HIGH(FunctTerm)));

   MovedDown := FALSE;
   MovedUp := FALSE;
   CASE GetPanelControlKey(FunctKey, TC) OF
      NextField:  MovedDown := TRUE;
    | PrevField:  MovedUp := TRUE;
   ELSE (* do nothing *)
   END;
END SetMotionVars;

PROCEDURE BracketsMissing(VAR NumbItem: CARDINAL): BOOLEAN;
BEGIN
   CASE Data^.TypeOfSpecialChar OF
      EmptySCType :
         RETURN FALSE |
      WordSepSCType:
         IF Data^.WordSepSeq[0] = 0C THEN
(*RES OLD MSG 54
Please give a Word Separator sequence.
*)
            PutResError( (*RES REM INS*) 54 );
            NumbItem := 2;
            RETURN TRUE
         END ;
         RETURN FALSE
      ELSE
         IF Data^.OpenBracket[0] = 0C THEN
(*RES OLD MSG 55
Please give an Opening Bracket.
*)
            PutResError( (*RES REM INS*) 55 );
            NumbItem := 2;
            RETURN TRUE
         ELSIF Data^.CloseBracket[0] = 0C THEN
(*RES OLD MSG 56
Please give a Closing Bracket.
*)
            PutResError( (*RES REM INS*) 56 );
            NumbItem := 3;
            RETURN TRUE
         ELSE
            RETURN FALSE
         END
   END ;
END BracketsMissing;

BEGIN
   Concat( trm, FieldMotionASC, Term );
   Concat( ftrm, FieldMotionExt, FunctTerm );
   Data := Dta;
   REPEAT
      hd := Data^.TypeOfSpecialChar;
      IF (ItemNumb <= 1) OR (hd = EmptySCType) THEN
         DoMenu(WindowRec,HDID,OffX,OfY,trm,ftrm,
                   Data^,ItemNumb,TC,FunctKey);
      ELSE
         TC := 0C;
         FunctKey := FALSE
      END;

      IF hd <> Data^.TypeOfSpecialChar THEN
         OffY := OfY + 2;
         IF Data^.TypeOfSpecialChar = EmptySCType THEN
             WITH Data^ DO  (* this will also work for the WordSepSeq since overlay data *)
                OpenBracket := 0C;
                CloseBracket := 0C;
                SuppressText := TRUE;
                WordSep := FALSE;
             END;
             ClearMenuArea(WindowRec,OffX,OffY,BDID);
             RETURN
         ELSE
            ShowDetailMenu(WindowRec,OffX,OfY,Data^);
         END;
      END;

      (* Cursor is now outside of header field area *)
      SetMotionVars;
      MovedOutSide := (ItemNumb <> 9999) AND (
                       (Data^.TypeOfSpecialChar = EmptySCType) OR
                       MovedUp OR TermPushed);

      IF NOT MovedOutSide THEN
         (* Cursor has been moved into subfield area *)
         itemn1 := ItemNumb - 1;
         GetDetailData(WindowRec,OffX,OfY,trm,ftrm,
                             Data^,itemn1,TC,FunctKey);
         ItemNumb := itemn1 + 1;
         SetMotionVars;
         MovedOutSide := TermPushed OR MovedDown;
      END;
   IF MovedOutSide THEN
      (* Cursor has been moved outside of submenu, check to see if brackets
         were given before allowing exit.     *)
      MovedOutSide := NOT BracketsMissing(ItemNumb);
   END
   UNTIL MovedOutSide;
END GetSCMenu;

PROCEDURE ShowSCTitleMenu(WindowRec:  WinType;
                          OffX,OffY:  CARDINAL);
BEGIN
   ClearMenuArea(WindowRec, OffX,OffY, TPID);
   ShowFixedText(WindowRec,TPID,OffX,OffY);

END ShowSCTitleMenu ;

PROCEDURE NewSCData(VAR Dta:  ADDRESS);
VAR   Data: SpecialCharDataPntr;
BEGIN
   NEW(Data);
   Dta := Data;
   WITH Data^ DO
      TypeOfSpecialChar := EmptySCType;
      OpenBracket := 0C;
      CloseBracket := 0C;
      SuppressText := TRUE;
      WordSep := FALSE;
   END;
END NewSCData;

PROCEDURE DeleteSCData(VAR Dta: ADDRESS);
VAR   Data: SpecialCharDataPntr;
BEGIN
   Data := Dta;
   Dta := NIL;
   DISPOSE(Data);
END DeleteSCData;

PROCEDURE IsSCDataEmpty(Dta: ADDRESS): BOOLEAN;
VAR   Data: SpecialCharDataPntr;
BEGIN
   Data := Dta;
   RETURN Data^.TypeOfSpecialChar = EmptySCType
END IsSCDataEmpty;

PROCEDURE InitSCList() ;
   BEGIN
      NewList( SCList ) ;
   END InitSCList ;

PROCEDURE DeleteSCList() ;
   VAR
      DataPtr : ADDRESS ;
   BEGIN
      SetToTop( SCList ) ;
      WHILE MoveDown( SCList ) DO
         GetData( SCList, DataPtr ) ;
         DeleteSCData( DataPtr ) ;
         DeleteListItem( SCList ) ;
      END ;
      FreeListPointer( SCList ) ;
   END DeleteSCList ;

END  SpecialCharacters .

