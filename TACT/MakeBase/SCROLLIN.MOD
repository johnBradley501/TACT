IMPLEMENTATION MODULE ScrollingMenu ;

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

FROM GlobalDefs IMPORT StrAny;
FROM ResMessages IMPORT GetResMessage;
FROM Windows IMPORT
   (* Vars *)  DialogAttrib,
   (* Const *) RegularAttr, BoldAttr, SpecialAttr,
   (* Procs *) ScrollUp, ScrollDown;
FROM ErrorBase IMPORT ProgramErrorAndHalt;

FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo, WindowInfoPtr,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM Utils IMPORT Beep;
FROM KeyTranslation IMPORT WriteScreenField ;
FROM Lists IMPORT
  (* type   *)   ListPointer,
  (* proc   *)   NewList, CopyListPointer, FreeListPointer,
                 AddBelow, DeleteListItem, GetData,
                 MoveUp, MoveDown, SetToTop, SetToLast, AtTop;
FROM KeyStandards IMPORT
  (* types *) ListControlKeys,
  (* vars  *) ScrollingExt, ScrollingASC,
  (* procs *) GetListControlKey;
IMPORT ASCII;
IMPORT TWB;

FROM SYSTEM IMPORT ADDRESS;

CONST
    Menu1 =        0;
    Menu2 =        6;
    Menu3 =        12;
    ScreenWidth =  76;

VAR
    TabRs:       ARRAY[0..1] OF CHAR;
    RulerImage:  ARRAY[0..ScreenWidth-3] OF CHAR;
    i:           CARDINAL;
    ScrollWind:  WindowInfo;

PROCEDURE DoScrollingMenu(VAR LP:        ListPointer;
                              ShowMenu:  ShowMenuProc;
                              GetMenu:   GetMenuProc;
                              ShowHeader:ShowHeaderProc;
                              NewData:   NewDataProc;
                              DeleteData:DeleteDataProc;
                              IsEmpty:   IsEmptyProc;
                              ResLabel:  CARDINAL);
VAR     w:       TWB.WinType;
        t,                      (* top "window" pointer *)
        c,                      (* current "window" pointer *)
        b:       ListPointer;   (* bottom "window" pointer *)
        d:       ADDRESS;
        rc:      CARDINAL;
        es:      BOOLEAN;
        LstBlnk: BOOLEAN;
        la:      ListControlKeys;

PROCEDURE DoRuler(Y:  CARDINAL);
VAR rc:     CARDINAL;
BEGIN
  WriteScreenField(w,0,0,Y+5,RulerImage,BoldAttr,FALSE);
  END DoRuler;

PROCEDURE ShowSubMenu(Y:   CARDINAL;  p:   ListPointer);
VAR    a:    ADDRESS;
BEGIN
   IF AtTop(p) THEN
      ShowHeader(w,0,Y);
   ELSE
      GetData(p,a);
      ShowMenu(w,0,Y,a);
   END
END ShowSubMenu;

PROCEDURE InitializeDisplay();
VAR  dmy:      BOOLEAN;
BEGIN

(* Add to bottom the empty item (to permit adding of new items *)

   CopyListPointer(LP,b);
   SetToLast(b);
   GetData(b,d);
   IF d <> NIL THEN
      IF NOT IsEmpty(d) THEN
         NewData(d);
         AddBelow(b,d);
         dmy := MoveDown(b);
      END
   ELSE
      NewData(d);
      AddBelow(b,d);
      dmy := MoveDown(b);
   END;
   FreeListPointer(b);

(* Pointer c points to the current (editable) item: middle submenu *)

   CopyListPointer(LP,c);
   IF AtTop(c) THEN
      dmy := MoveDown(c)
   END ;
   ShowSubMenu(Menu2,c);
   DoRuler(Menu2);

(* Pointer t points to the item being displayed on the top submenu *)

   CopyListPointer(c,t);
   dmy := MoveUp(t);
   ShowSubMenu(Menu1,t); (* this will always show the menu header *)
   DoRuler(Menu1);

(* Next, reset b to point to bottom item: in bottom submenu *)

   CopyListPointer(c,b);
   IF MoveDown(b) THEN
      LstBlnk := FALSE;
      ShowSubMenu(Menu3,b)
   ELSE
      LstBlnk := TRUE
   END;
END InitializeDisplay;

PROCEDURE ClearMenu3;
VAR i:   CARDINAL;
BEGIN
   TWB.Use(w);
   FOR i := Menu3 TO ScrollWind.YSize-1 DO
      TWB.GotoXY(0,i);
      TWB.ClrEol;
   END;
END ClearMenu3;

PROCEDURE GoToTopOfList;
VAR dmy:     BOOLEAN;
BEGIN
   SetToTop(t);
   ShowSubMenu(Menu1,t);
   SetToTop(c);
   dmy := MoveDown(c);
   ShowSubMenu(Menu2,c);
   SetToTop(b);
   dmy := MoveDown(b);
   IF MoveDown(b) THEN
       ShowSubMenu(Menu3,b);
       LstBlnk := FALSE
   ELSE
       LstBlnk := TRUE;
       ClearMenu3;
   END
END GoToTopOfList;

PROCEDURE GoToBottomOfList;
VAR dmy:     BOOLEAN;
BEGIN
   SetToLast(t);
   dmy := MoveUp(t);
   ShowSubMenu(Menu1,t);
   SetToLast(c);
   ShowSubMenu(Menu2,c);
   LstBlnk := TRUE;
   SetToLast(b);
   ClearMenu3;
END GoToBottomOfList;

PROCEDURE TowardsFirst(): BOOLEAN;
VAR dmy:     BOOLEAN;
BEGIN
    IF MoveUp(t) THEN
       ScrollDown(w,6);
       ShowSubMenu(Menu1,t);
       DoRuler(Menu1);
       dmy := MoveUp(c);
       IF NOT LstBlnk THEN
          dmy := MoveUp(b)
       ELSE
          LstBlnk := FALSE
       END;
       RETURN TRUE
    ELSE
       Beep;
       RETURN FALSE
    END
END TowardsFirst;

PROCEDURE TowardsLast(): BOOLEAN;
VAR dmy:     BOOLEAN;
BEGIN
    IF MoveDown(c) THEN
       ScrollUp(w,6);
       DoRuler(Menu2);
       dmy := MoveDown(t);
       IF MoveDown(b) THEN
           ShowSubMenu(Menu3,b);
           LstBlnk := FALSE
       ELSE
           LstBlnk := TRUE
       END;
       RETURN TRUE
    ELSE
       Beep;
       RETURN FALSE
    END
END TowardsLast;

PROCEDURE DoInteraction;
VAR   TC:            CHAR;
      ItemN:         CARDINAL;
      FunctKey:      BOOLEAN;
      d:             ADDRESS;
      cUsed:         BOOLEAN;
      rc:            CARDINAL;
      cUse:          BOOLEAN;
      AllowDown:     BOOLEAN;
      dmy:           BOOLEAN;

BEGIN
   ItemN := 1;
   REPEAT
     GetData(c,d);
     cUsed := NOT IsEmpty(d);
     GetMenu(w,0,Menu2,ScrollingASC,ScrollingExt,d,ItemN,TC,FunctKey);
     cUse := NOT IsEmpty(d);
     AllowDown := TRUE;
     IF cUsed AND (NOT cUse) THEN
        (* Record has been newly made empty, Get rid of it *)
        AllowDown := FALSE;
        GetData(c,d);
        DeleteData(d);
        DeleteListItem(c);
        ShowSubMenu(Menu2,c);
        IF MoveDown(b) THEN
            ShowSubMenu(Menu3,b);
            LstBlnk := FALSE
        ELSE
            ClearMenu3;
            LstBlnk := TRUE;
        END;
     ELSIF (NOT cUsed) AND cUse THEN

        (* Record has been newly filled, create new empty below *)
        NewData(d);
        AddBelow(c,d);
        IF LstBlnk THEN
           dmy := MoveDown(b)
        ELSE
           dmy := MoveUp(b);
           ClearMenu3
        END;
        ShowSubMenu(Menu3,b);
        LstBlnk := FALSE;
     END;

     la := GetListControlKey(FunctKey, TC);
     CASE la OF
       PrevItem, PrevGroup, PrevScreen:
         IF (TowardsFirst() AND (la = PrevItem)) THEN ItemN := 9999
                                                      ELSE ItemN := 1 END;
     | NextItem, NextGroup, NextScreen:
         IF AllowDown THEN
            IF TowardsLast() THEN ItemN := 1
                             ELSE ItemN := 9999 END;
         END;
     | FirstItem:
         GoToTopOfList;
         ItemN := 1;
     | LastItem:
         GoToBottomOfList;
         ItemN := 1;
     | ListEnd: (* do nothing here *)
     ELSE Beep
     END;
   UNTIL (la = ListEnd);

END DoInteraction;

PROCEDURE DoFinish;
VAR   d:     ADDRESS;
BEGIN

(* First, throw away last, empty item (added earlier) *)

   SetToLast(b);
   GetData(b,d);
   IF IsEmpty(d) THEN 
      DeleteListItem(b);
      DeleteData(d)
   END;
   FreeListPointer(t);
   FreeListPointer(c);
   FreeListPointer(b);
END DoFinish;

PROCEDURE AddLabel;
VAR
   a:    StrAny;
BEGIN
   GetResMessage(ResLabel,a);
   TWB.SetTitle(w, a, TWB.RightLowerTitle);
END AddLabel;

BEGIN
   PushNewWindow(ScrollWind, w, DummyInit);
   AddLabel;

   InitializeDisplay();

   DoInteraction;

   DoFinish;

   PopWindow;
END DoScrollingMenu;

PROCEDURE InitCodeScrollMenu ;  (* this is for OVERLAY mechanism *LP* *)
BEGIN
    FOR i := 0 TO ScreenWidth-3 DO
      RulerImage[i] := 37C; (* internal character set ruler character *)
    END;
    WITH ScrollWind DO
      XPos := 2;
      YPos := 4;
      XSize := ScreenWidth;
      YSize := 17;
      MxYSize := 17;
      Type :=       Dialog;
      AllowMove :=  FALSE;
      AllowResize :=FALSE;
      IsTop :=      FALSE
   END;
END InitCodeScrollMenu ;

END  ScrollingMenu .
