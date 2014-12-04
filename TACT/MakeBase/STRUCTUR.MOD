IMPLEMENTATION MODULE StructuralInfo ;

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

(* This is code for the StructuralInfo Menu for MAKBAS *)

IMPORT PCKey;
FROM SYSTEM     IMPORT ADDRESS;
FROM GlobalDefs IMPORT StrAny;
FROM Str	IMPORT Pos, Concat;
FROM Storage    IMPORT ALLOCATE, DEALLOCATE;
FROM StringIO   IMPORT SWriteString, SWriteCard, SWriteChar;
FROM KeyTranslation IMPORT GetScreenField, WriteScreenField ;
FROM Lists    IMPORT
  (* Procs *) SetToTop, MoveDown, GetData, DeleteListItem, FreeListPointer,
              NewList, AddBelow ;
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
            PutResError, PutResWarning, PutResMessage;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* vars  *) FieldMotionExt, FieldMotionASC,
  (* procs *) GetPanelControlKey;

(* Main Menu Header layout:                                *)

VAR
   HDID:  MenuID;  (* Header Data -- ie. title menu *)
   WordCntID,
   LineCntID,
   ReferenceID,
   LabelID,
   CounterID,
   TopPanelID,
   BYUID,
   PosID:  MenuID;
   Data:  StructInfoDataType;
   MaxPos:  CARDINAL;


PROCEDURE MakeStructMenus;

   BEGIN
(* Menu Title Header layout:                                *)

(*RES OLD MNU 4
                      Reference Tags Menu

             To move between items, press PgUp or PgDn.
             To return to the main menu, press "Enter / Return".
             To stop MakeBase, press F10.
*)
      StartMenu(Data);
      MakeMenu((*RES REM INS*) 4 , TopPanelID);



(*RES OLD MNU 5
 Type: Empty: %|0  COCOA: %|1  Label: %|2  Counter: %|3  WCS: %|4  Pos: %|5




*)
      StartMenu(Data);
      WITH Data DO
         Switches(TypeOfStructInfo);
            SwitchValue(EmptyType);
            SwitchValue(ReferenceType);
            SwitchValue(LabelType);
            SwitchValue(CounterType);
            SwitchValue(BYUType);
            SwitchValue(PosType);
      END;
      MakeMenu((*RES REM INS*) 5 , HDID);

(*RES OLD MNU 6

      TACT ID: %0_____________________________________________________
      Text ID: %1_____________       Numeric?  Yes: %|2 No: %|3
      Number of characters to keep: %4__
*)

      StartMenu(Data);

      WITH Data DO
         CharField(Names);
         CharField(RefRefID);
         Switches(RefNumeric);
            SwitchValue(TRUE);
            SwitchValue(FALSE);
         CardField(RefNoCharsKeep);
      END ;
      MakeMenu((*RES REM INS*) 6 , ReferenceID);

(*RES OLD MNU 7
      TACT ID: %0____________________________________________________
      Opening Bracket: %1____             Closing Bracket:  %2____
      Suppress Text? Yes: %|3 No: %|4     Word Separator?  Yes: %|5 No: %|6
      Numeric?  Yes: %|7 No: %|8          No. of chars. to keep:  %9____
*)

      StartMenu(Data);
      WITH Data DO
         CharField(Names);
         CharField(LabelOpenBracket);
         CharField(LabelCloseBracket);
         Switches(LabelSuppressText);
            SwitchValue(TRUE);
            SwitchValue(FALSE);
         Switches(LabelWordSep);
            SwitchValue(TRUE);
            SwitchValue(FALSE);
         Switches(LabelNumeric);
            SwitchValue(TRUE);
            SwitchValue(FALSE);
         CardField(LabelNoCharsKeep);
      END ;
      MakeMenu((*RES REM INS*) 7 , LabelID);


(*RES OLD MNU 8
      TACT ID:    %0_____________________________________________________
      Counter ID: %1_____________________________________________________
      Reset: %2_______________________________
      Init:  %3______       Suppress Text? Yes: %|4 No: %|5
*)
      StartMenu(Data);
      WITH Data DO
         CharField(Names);
         CharField(CounterRefID);
         CharField(CounterReset);
         CardField(CounterInit);
         Switches(CounterSuppressText);
            SwitchValue(TRUE);
            SwitchValue(FALSE);
      END ;
      MakeMenu((*RES REM INS*) 8 , CounterID);

(*RES OLD MNU 9

      TACT ID: %0________________________________________________________
      Text ID: %|1         Numeric?  Yes: %|2 No: %|3
      Number of chars. to keep:  %4__
*)

      StartMenu(Data);
      WITH Data DO
         CharField(Names);
         CharField(BYURefID);
         Switches(BYUNumeric);
            SwitchValue(TRUE);
            SwitchValue(FALSE);
         CardField(BYUNoCharsKeep);
      END ;
      MakeMenu((*RES REM INS*) 9 , BYUID);

(*RES OLD MNU 10
                           Word Counter

      TACT ID: %0______________________________________________
      Init:    %1___
*)

      StartMenu(Data);
      WITH Data DO
         CharField(Names);
         CardField(WordCounterInit);
      END ;
      MakeMenu((*RES REM INS*) 10 , WordCntID);

(*RES OLD MNU 11
                           Line Counter

      TACT ID: %0____________________________________________
      Reset:   %1____________________________________________
      Init:    %2___
*)

      StartMenu(Data);
      WITH Data DO
         CharField(Names);
         CharField(LineCounterReset);
         CardField(LineCounterInit);
      END ;
      MakeMenu((*RES REM INS*) 11 , LineCntID);

(*RES OLD MNU 52

      TACT ID: %0_______________________________________________________
      Starting Position: %1_____      Ending Position: %2_____
      Numeric?  Yes: %|3 No: %|4
*)

      StartMenu(Data);
      WITH Data DO
         CharField(Names);
         CardField(PosStart);
         CardField(PosEnd);
         Switches(PosNumeric);
            SwitchValue(TRUE);
            SwitchValue(FALSE);
      END ;
      MakeMenu((*RES REM INS*) 52 , PosID);

   END MakeStructMenus;

PROCEDURE DestroyStructMenus;
   BEGIN
      DestroyMenu(HDID);
      DestroyMenu(TopPanelID);
      DestroyMenu(WordCntID);
      DestroyMenu(LineCntID);
      DestroyMenu(ReferenceID);
      DestroyMenu(LabelID);
      DestroyMenu(CounterID);
      DestroyMenu(BYUID);
      DestroyMenu(PosID);
   END DestroyStructMenus;

PROCEDURE ShowHeaderOnly( WindowRec:  WinType;
                          OffX,OffY:  CARDINAL;
                          Data:       StructInfoDataType ) ;
BEGIN
   ClearMenuArea(WindowRec, OffX,OffY, HDID);
   ShowFixedText(WindowRec,HDID,OffX,OffY);

   ShowMenu(WindowRec,HDID,OffX,OffY,Data);
END ShowHeaderOnly ;

PROCEDURE ShowDetailMenu( WindowRec:     WinType;
                          OffX,OfsY:  CARDINAL;
                          Data:       StructInfoDataType ) ;
   VAR     OffY       : CARDINAL;
           TempMenuId : MenuID ;
   BEGIN
      TempMenuId := HDID ;
      CASE Data.TypeOfStructInfo OF
         NoType :              |
         EmptyType :           |
         WordCounterType :
            OffY := OfsY ;
            TempMenuId := WordCntID   |
         LineCounterType :
            OffY := OfsY ;
            TempMenuId := LineCntID   |
         ReferenceType :
            OffY := OfsY + 1 ;  (* m.s. - was 2, added blank line to res *)
            TempMenuId := ReferenceID |
         LabelType :
            OffY := OfsY + 1 ;
            TempMenuId := LabelID     |
         CounterType :
            OffY := OfsY + 1 ;
            TempMenuId := CounterID   |
         BYUType :
            OffY := OfsY + 1 ; (* m.s. - was 2 *)
            TempMenuId := BYUID       |
         PosType :
            OffY := OfsY + 1 ;  (* m.s. - was 2 *)
            TempMenuId := PosID ;
      END ;
      ClearMenuArea(WindowRec,OffX,OffY,TempMenuId);
      ShowFixedText(WindowRec,TempMenuId,OffX,OffY);
      ShowMenu(WindowRec,TempMenuId,OffX,OffY,Data) ;
   END ShowDetailMenu ;

PROCEDURE GetDetailData(  WindowRec:     WinType;
                          OffX,OffY:     CARDINAL;
                          Term:          ARRAY OF CHAR;
                          FunctTerm:     ARRAY OF CHAR;
                      VAR Data:          StructInfoDataType;
                      VAR ItemNumb:      CARDINAL;
                      VAR TC:            CHAR;
                      VAR FunctKey:      BOOLEAN );
   VAR
      TempMenuId : MenuID ;
   BEGIN
      TempMenuId := HDID ;
      CASE Data.TypeOfStructInfo OF
         NoType :              |
         EmptyType :           |
         WordCounterType :
            TempMenuId := WordCntID   |
         LineCounterType :
            TempMenuId := LineCntID   |
         ReferenceType :
            OffY := OffY + 1 ; (* m.s. - was 2, added blank line to res *)
            TempMenuId := ReferenceID |
         LabelType :
            OffY := OffY + 1 ;
            TempMenuId := LabelID     |
         CounterType :
            OffY := OffY + 1 ;
            TempMenuId := CounterID   |
         BYUType :
            OffY := OffY + 1 ;  (* m.s. - was 2 *)
            TempMenuId := BYUID       |
         PosType :
            OffY := OffY + 1 ;  (* m.s. - was 2 *)
            TempMenuId := PosID ;
      END ;
      DoMenu(WindowRec,TempMenuId,OffX,OffY,Term,FunctTerm,
                    Data,ItemNumb,TC,FunctKey);
   END GetDetailData;

PROCEDURE ShowStructMenu( WindowRec:   WinType;
                          OffX,OffY:   CARDINAL;
                          Dta:         ADDRESS);
   VAR Data:    StructInfoDataPntr;
   BEGIN
      Data := Dta;
      IF (Data^.TypeOfStructInfo <> WordCounterType) AND
         (Data^.TypeOfStructInfo <> LineCounterType) THEN
         ShowHeaderOnly( WindowRec,OffX,OffY,Data^);
      END ;
      IF Data^.TypeOfStructInfo <> EmptyType THEN
         ShowDetailMenu( WindowRec,OffX,OffY,Data^)
      END
   END ShowStructMenu;

PROCEDURE GetStructMenu(WindowRec:  WinType;
                          OffX,OffY:     CARDINAL;
                          Term:          ARRAY OF CHAR;
                          FunctTerm:     ARRAY OF CHAR;
                      VAR Dta:           ADDRESS;
                      VAR ItemNumb:      CARDINAL;
                      VAR TC:            CHAR;
                      VAR FunctKey:      BOOLEAN );

(*RES OLD MSG 57
The number of characters to keep must be greater than zero.
*)
   CONST NoCharMsg = (*RES REM INS*) 57 ;

   VAR  trm,ftrm     : ARRAY[0..40] OF CHAR;
        Data         : StructInfoDataPntr;
        hd           : StructInfoType;
        done         : BOOLEAN;
        i            : CARDINAL;
        itemn1       : CARDINAL;
        MovedDown    : BOOLEAN;
        MovedUp      : BOOLEAN;
        TermPushed   : BOOLEAN;
        MovedOutSide : BOOLEAN;
        TempMenuId   : MenuID ;

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

PROCEDURE CheckMissing(VAR NumbItem: CARDINAL): BOOLEAN;
   BEGIN
      WITH Data^ DO
         IF (TypeOfStructInfo <> EmptyType) AND ( Names[0] = 0C ) THEN
(*RES OLD MSG 58
Please give a "TACT ID".
*)
            PutResError( (*RES REM INS*) 58 );
            NumbItem := 2;
            RETURN TRUE ;
         END ;
         CASE TypeOfStructInfo OF
            ReferenceType :
               IF RefRefID[0] = 0C THEN
(*RES OLD MSG 59
Please give a Reference Identification.
*)
                  PutResError( (*RES REM INS*) 59 );
                  NumbItem := 3;
                  RETURN TRUE
               ELSIF (RefNoCharsKeep = 0) AND NOT RefNumeric THEN
                  PutResError( NoCharMsg );
                  RETURN TRUE
               END  |
            LabelType :
               IF LabelOpenBracket[0] = 0C THEN
(*RES OLD MSG 60
Please give an Opening bracket.
*)
                  PutResError( (*RES REM INS*) 60 );
                  NumbItem := 3;
                  RETURN TRUE
               ELSIF LabelCloseBracket[0] = 0C THEN
(*RES OLD MSG 61
Please give a Closing bracket.
*)
                  PutResError( (*RES REM INS*) 61 );
                  NumbItem := 4;
                  RETURN TRUE
               ELSIF (LabelNoCharsKeep = 0) AND NOT LabelNumeric THEN
                  PutResError( NoCharMsg );
                  NumbItem := 8;
                  RETURN TRUE ;
               END  |
            CounterType :
               IF CounterRefID[0] = 0C THEN
(*RES OLD MSG 62
Please give a Counter Identification.
*)
                  PutResError( (*RES REM INS*) 62 );
                  NumbItem := 3;
                  RETURN TRUE
               END  |
            BYUType :
               IF BYURefID[0] = 0C THEN
(*RES OLD MSG 63
Please give a BYU Identification.
*)
                  PutResError( (*RES REM INS*) 63 );
                  NumbItem := 3;
                  RETURN TRUE
               ELSIF (BYUNoCharsKeep = 0) AND NOT BYUNumeric THEN
                  PutResError( NoCharMsg );
                  NumbItem := 5;
                  RETURN TRUE ;
               END |
            PosType :
               IF PosStart = 0 THEN
                  (*RES OLD MSG 435
                  Please give a Starting Position.
                  *)
                  PutResError( (*RES REM INS*) 435 );
                  NumbItem := 3;
                  RETURN TRUE
               ELSIF PosEnd = 0 THEN
                  (*RES OLD MSG 436
                  Please give a Ending Position.
                  *)
                  PutResError( (*RES REM INS*) 436 );
                  NumbItem := 4;
                  RETURN TRUE
               ELSIF PosStart > PosEnd THEN
                  (*RES OLD MSG 437
                  Please ensure that the Ending Position is not smaller than
                  the Starting Position.
                  *)
                  PutResError( (*RES REM INS*) 437 );
                  NumbItem := 3;
                  RETURN TRUE
               END;
               IF PosEnd > MaxPos THEN MaxPos := PosEnd END;
            ELSE
               RETURN FALSE
         END ;
      END ;
      RETURN FALSE
   END CheckMissing;

   BEGIN  (* GetStructMenu *)
      Concat( trm, FieldMotionASC, Term );
      Concat( ftrm, FieldMotionExt, FunctTerm );
      Data := Dta;
      REPEAT
         MovedOutSide := TRUE;
         hd := Data^.TypeOfStructInfo;
         CASE hd OF
            WordCounterType :
               (* handle Word counters differently *)
               DoMenu(WindowRec,WordCntID,OffX,OffY,trm,ftrm,
                            Data^,ItemNumb,TC,FunctKey);
               TempMenuId := WordCntID  |
            LineCounterType :
               (* handle Line counters differently *)
               DoMenu(WindowRec,LineCntID,OffX,OffY,trm,ftrm,
                            Data^,ItemNumb,TC,FunctKey);
               TempMenuId := LineCntID
            ELSE
               IF (ItemNumb <= 1) OR (hd = EmptyType) THEN
                  DoMenu(WindowRec,HDID,OffX,OffY,trm,ftrm,
                            Data^,ItemNumb,TC,FunctKey);
               ELSE
                  TC := 0C;
                  FunctKey := FALSE
               END;

               IF hd <> Data^.TypeOfStructInfo THEN
                  (* there is a change in the structure type selected *)
                  WITH Data^ DO
                     Names := 0C ;
                     CASE TypeOfStructInfo OF
                        NoType :        |
                        EmptyType :     |
                        WordCounterType :
                           WordCounterInit  := 0 |
                        LineCounterType :
                           LineCounterReset := 0C ;
                           LineCounterInit  := 0 |
                        ReferenceType :
                           RefRefID := 0C ;
                           RefNumeric := FALSE ;
                           RefNoCharsKeep := 9999  |
                        LabelType :
                           LabelOpenBracket   := 0C ;
                           LabelCloseBracket  := 0C ;
                           LabelSuppressText  := FALSE ;
                           LabelWordSep       := TRUE ;
                           LabelNumeric       := FALSE ;
                           LabelNoCharsKeep   := 9999 |
                        CounterType :
                           CounterRefID := 0C ;
                           CounterReset := 0C ;
                           CounterInit  := 0 ;
                           CounterSuppressText := FALSE |
                        BYUType :
                           BYURefID   := 0C ;
                           BYUNumeric := FALSE ;
                           BYUNoCharsKeep := 9999 |
                        PosType :
                           PosStart := MaxPos + 1;
                           PosEnd := 0;
                           PosNumeric := FALSE;
                     END ;
                  END;  (* WITH Data^ DO *)
                  IF Data^.TypeOfStructInfo = EmptyType THEN
                     ClearMenuArea(WindowRec, OffX,OffY, HDID);
                     RETURN
                  ELSE
                     ShowDetailMenu(WindowRec,OffX,OffY,Data^);
                  END;
               END ; (* IF hd <> Data^.TypeOfStructInfo THEN *)

               (* Cursor is now outside of header field area *)

               SetMotionVars;
               MovedOutSide := (ItemNumb <> 9999) AND (
                       (Data^.TypeOfStructInfo = EmptyType) OR
                       MovedUp OR TermPushed);

               IF NOT MovedOutSide THEN
                  (* Cursor has been moved into subfield area *)
                  itemn1 := ItemNumb - 1;
                  GetDetailData(WindowRec,OffX,OffY,trm,ftrm,
                             Data^,itemn1,TC,FunctKey);
                  ItemNumb := itemn1 + 1;
                  SetMotionVars;
                  MovedOutSide := TermPushed OR MovedDown;
               END;
               IF MovedOutSide THEN
               (* Cursor has been moved outside of submenu, check to see if options
                  were given before allowing exit.     *)
                  MovedOutSide := NOT CheckMissing(ItemNumb);
               END
           END
      UNTIL MovedOutSide;
   END GetStructMenu;

PROCEDURE ShowStructTitleMenu(WindowRec:  WinType;
                          OffX,OffY:  CARDINAL);
   BEGIN
   ClearMenuArea(WindowRec, OffX,OffY, TopPanelID);
   ShowFixedText(WindowRec,TopPanelID,OffX,OffY);
   END ShowStructTitleMenu ;

PROCEDURE NewStructData(VAR Dta:  ADDRESS);
   VAR   Data: StructInfoDataPntr;
   BEGIN
      NEW(Data);
      Dta := Data;
      WITH Data^ DO
           TypeOfStructInfo := EmptyType;
           Names := 0C ;
      END;
   END NewStructData;

PROCEDURE DeleteStructData(VAR Dta: ADDRESS);
   VAR   Data: StructInfoDataPntr;
   BEGIN
      Data := Dta;
      Dta := NIL;
      DISPOSE(Data);
   END DeleteStructData;

PROCEDURE IsStructDataEmpty(Dta: ADDRESS): BOOLEAN;
   VAR   Data: StructInfoDataPntr;
   BEGIN
      Data := Dta;
      RETURN Data^.TypeOfStructInfo = EmptyType
   END IsStructDataEmpty;

PROCEDURE InitStructList() ;
   VAR
      Dummy      : BOOLEAN ;
      DataPtr    : ADDRESS ;
      StructData : StructInfoDataPntr ;
   BEGIN
      NewList(StructList);
      NewStructData( DataPtr ) ;
      AddBelow( StructList, DataPtr ) ;
      Dummy := MoveDown( StructList ) ;
      StructData := DataPtr ;
      WITH StructData^ DO
(*RES OLD MSG 64
WORDNO WORDNOS
*)
         GetResMessage( (*RES REM INS*) 64, Names);
         TypeOfStructInfo := WordCounterType ;
         WordCounterInit  := 0 ;
      END ;
      NewStructData( DataPtr ) ;
      AddBelow( StructList, DataPtr ) ;
      Dummy := MoveDown( StructList ) ;
      StructData := DataPtr ;
      WITH StructData^ DO
(*RES OLD MSG 65
LINENO LINENOS
*)
         GetResMessage( (*RES REM INS*) 65, Names);
         TypeOfStructInfo := LineCounterType ;
         LineCounterInit  := 0 ;
         LineCounterReset := 0C ;
      END ;
      SetToTop( StructList ) ;
      Dummy := MoveDown( StructList ) ;
   END InitStructList ;

PROCEDURE DeleteStructList() ;
   VAR
      DataPtr : ADDRESS ;
   BEGIN
      SetToTop( StructList ) ;
      WHILE MoveDown( StructList ) DO
         GetData( StructList, DataPtr ) ;
         DeleteStructData( DataPtr ) ;
         DeleteListItem( StructList ) ;
      END ;
      FreeListPointer( StructList ) ;
   END DeleteStructList ;

BEGIN
   MaxPos := 0;
END  StructuralInfo .
