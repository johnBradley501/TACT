IMPLEMENTATION MODULE ResActionBar;

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

FROM SYSTEM IMPORT ADR, BYTE;
IMPORT TWB,Str,Lib;
FROM Utils IMPORT Beep, ALLOCATE, DEALLOCATE;
FROM KeyBase IMPORT GetKeyStroke;
FROM KeyStandards IMPORT
  (* types *) ActionBarControlKeys,
  (* procs *) GetActBarControlKey;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM Windows IMPORT CreateNewWindow, GetRidOfWindow, MoveRange,
                    RegularAttr, BoldAttr, SpecialAttr, DialogAttrib,
                    ActionBarAttrib, InActiveAttrib,
                    ChangeColorOnScreen;
FROM GlobalDefs IMPORT StrAny;
FROM Translations IMPORT
 (* var  *) Int2Scr,
 (* type *) XlateStrAny, CurrentModeType,
 (* proc *) XlateLine;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) ReleaseCollection;

CONST
    BarItemDataBaseSize = 33;
    PopupItemDataBaseSize = 16;

TYPE

    PopupItemPntr = POINTER TO PopupItemData;
    PopupItemData = RECORD
       Size:      CARDINAL;
       Next:      PopupItemPntr;
       Prev:      PopupItemPntr;
       Line:      CARDINAL;
       XHi:       CARDINAL;
       Letter:    CHAR;
       Text:      StrAny;
    END;

    PopupBase = RECORD
       XPos:      CARDINAL;
       XWidth:    CARDINAL;
       Len:       CARDINAL;
       First:     PopupItemPntr;
       Last:      PopupItemPntr;
    END;

    BarItemPntr = POINTER TO BarItemData;
    BarItemData = RECORD
       Size:      CARDINAL;
       Next:      BarItemPntr;
       Prev:      BarItemPntr;
       Popup:     PopupBase;
       XPos:      CARDINAL;
       Len:       CARDINAL;
       XHi:       CARDINAL;
       Letter:    CHAR;
       ItemNo:    BYTE;
       Text:      StrAny;
    END;

    BarBaseData = RECORD
       HIGHItems:       CARDINAL;
       FirstItem:       BarItemPntr;
       LastItem:        BarItemPntr;
    END;

    BarID = POINTER TO BarBaseData;

VAR
    ABWindowMade: BOOLEAN;

PROCEDURE BuildActionBar(VAR ID:       BarID;
                         ResID:        CARDINAL;
                         PopupIDs:     ARRAY OF CARDINAL);
VAR
   tBIPntr:     BarItemPntr;
   tPUPntr:     PopupItemPntr;
   ResC:        ResCollectionType;
   ItemT:       StrAny;
   dummy:       BOOLEAN;
   HighPop:     CARDINAL;
   len:         CARDINAL;
   BarItem:     BarItemData;
   PopupItem:   PopupItemData;

PROCEDURE ParseText(In:    ARRAY OF CHAR;
                VAR Out:   ARRAY OF CHAR;
                VAR Len:   CARDINAL;
                VAR Offset:CARDINAL;
                VAR Letter:CHAR);
VAR i:     CARDINAL;
    D:     XlateStrAny;
    NS:    CARDINAL;
    ED:    BOOLEAN;
    cm:    CurrentModeType;
BEGIN
   i := Str.Pos(In,'_');
   IF i <= HIGH(In) THEN
      Offset := i;
      Str.Delete(In,i,1)
   ELSE
      Offset := 0
   END;
   Letter := CAP(In[Offset]);
   cm.ModeIn := '0';
   cm.ModeOut := '0';
   XlateLine(Int2Scr,'?',In,cm,Len,D,NS,ED,Out);
END ParseText;

BEGIN
   MoveRange.YTop := 1;

   ALLOCATE(ID, SIZE(BarBaseData));
   WITH ID^ DO
      HIGHItems := HIGH(PopupIDs);
      FirstItem := NIL;
      LastItem  := NIL;
   END;
   HighPop := 0;
   BarItem.XPos := 0;
   GetDataArray( ResID, ResC);

   WHILE GetNextDataArrayStringItem(ResC,ItemT) DO
      ParseText(ItemT,BarItem.Text,BarItem.Len,BarItem.XHi,BarItem.Letter);
      INC(BarItem.XHi, BarItem.XPos);
      BarItem.Size := BarItemDataBaseSize + Str.Length(BarItem.Text);
      ALLOCATE(tBIPntr, BarItem.Size);
      Lib.Move(ADR(BarItem),tBIPntr,BarItem.Size);
      WITH tBIPntr^ DO
          ItemNo := VAL(BYTE,HighPop + 1);
          Next := NIL;
          Prev := ID^.LastItem;
          IF Prev = NIL THEN ID^.FirstItem := tBIPntr
                        ELSE ID^.LastItem^.Next := tBIPntr END;
      END;
      ID^.LastItem := tBIPntr;
      INC(BarItem.XPos,BarItem.Len + 2);
      INC(HighPop);
   END;

   DEC(HighPop);
   ReleaseCollection(ResC);

   IF HighPop <> HIGH(PopupIDs) THEN
      ProgramErrorAndHalt('Wrong number of PopupIDs');
   END;

   tBIPntr := ID^.FirstItem;
   HighPop := 0;
   WHILE tBIPntr <> NIL DO
      WITH tBIPntr^.Popup DO
         First := NIL;
         Last := NIL;
         Len := 0;
         XWidth := 0;
         XPos := 0;
         PopupItem.Line := 0;
         IF PopupIDs[HighPop] <> 0 THEN
            GetDataArray( PopupIDs[HighPop], ResC);
            WHILE GetNextDataArrayStringItem(ResC,ItemT) DO
               ParseText(ItemT,PopupItem.Text,len,PopupItem.XHi,PopupItem.Letter);
               IF len > XWidth THEN XWidth := len END;
               PopupItem.Size := PopupItemDataBaseSize + Str.Length(PopupItem.Text);
               ALLOCATE(tPUPntr, PopupItem.Size);
               Lib.Move(ADR(PopupItem),tPUPntr,PopupItem.Size);
               WITH tPUPntr^ DO
                  Next := NIL;
                  Prev := Last;
                  IF Prev = NIL THEN First := tPUPntr
                                ELSE Last^.Next := tPUPntr END;
               END;
               Last := tPUPntr;
               INC(PopupItem.Line);
               INC(Len);
            END;
            XPos := tBIPntr^.XPos;
            IF XPos > 0 THEN DEC(XPos) END;
            IF XWidth + XPos + 2 > 78 THEN XPos := 76- XWidth END;
            ReleaseCollection(ResC);
         END;
      END;
      tBIPntr := tBIPntr^.Next;
      INC(HighPop);
   END;
END BuildActionBar;

PROCEDURE DiscardActionBar(VAR ID:       BarID);
VAR
   t1PU,t2PU:   PopupItemPntr;
   t1BI,t2BI:   BarItemPntr;
BEGIN
   t1BI := ID^.FirstItem;
   WHILE t1BI <> NIL DO
      t2BI := t1BI^.Next;
      WITH t1BI^.Popup DO
        t1PU := First;
        WHILE t1PU <> NIL DO
           t2PU := t1PU^.Next;
           DEALLOCATE(t1PU,t1PU^.Size);
           t1PU := t2PU;
        END
      END;
      DEALLOCATE(t1BI,t1BI^.Size);
      t1BI := t2BI;
   END;
   DEALLOCATE(ID, SIZE(BarBaseData));
   ID := NIL;
END DiscardActionBar;

PROCEDURE ShowActionBar(ID:     BarID);

VAR
   WD:      TWB.WinDef;
   tBIPntr: BarItemPntr;
   BarLine: ARRAY[0..76] OF CHAR;
   ow:      TWB.WinType;

BEGIN
   ow := TWB.Used();
   IF NOT ABWindowMade THEN
      ABWindowMade := TRUE;
      WITH WD DO
        X1 := 0;
        Y1 := 0;
        X2 := 80;
        Y2 := 0;
        CursorOn := FALSE;
        WrapOn := FALSE;
        Hidden := FALSE;
        FrameOn := FALSE;
      END;
      ABWindow := TWB.PaletteOpen(WD, InActiveAttrib);
   END;
   TWB.Use(ABWindow);
   tBIPntr := ID^.FirstItem;

   TWB.Clear;
   TWB.SetPaletteColor(RegularAttr);

   WHILE tBIPntr <> NIL DO
     WITH tBIPntr^ DO
        TWB.GotoXY(XPos,0);
        TWB.WrStr(Text);
        ChangeColorOnScreen(BoldAttr,XHi,0,1);
     END;
     tBIPntr := tBIPntr^.Next;
   END;
   TWB.Use(ow);
END ShowActionBar;

PROCEDURE DoActionBar(ID:            BarID;
                      Term:          ARRAY OF CHAR;
                      FunctTerm:     ARRAY OF CHAR;
                  VAR TC:            CHAR;
                  VAR FunctKey:      BOOLEAN;
                  VAR ActionBarSele: BYTE;
                  VAR PopupSelect:   BYTE ) : BOOLEAN;
VAR
   ow:       TWB.WinType;
   WX,WY:    CARDINAL;
   WD:       TWB.WinDef;
   dummy:    CARDINAL;
   rc:       CARDINAL;
   tBIPntr:  BarItemPntr;
   tBIPntr2: BarItemPntr;
   done:     BOOLEAN;
   DoRead:   BOOLEAN;
   abck:     ActionBarControlKeys;

PROCEDURE ResetBarItem(bi:  BarItemPntr);
BEGIN
   WITH bi^ DO
     ChangeColorOnScreen(RegularAttr,XPos,0,Len);
     ChangeColorOnScreen(BoldAttr,XHi,0,1);
   END;
END ResetBarItem;

PROCEDURE PresentPopup(Data:     PopupBase;
                   VAR TC:       CHAR;
                   VAR FunctKey: BOOLEAN;
                   VAR abck:     ActionBarControlKeys;
                   VAR Result:   BYTE;
                   VAR DoRead:   BOOLEAN): BOOLEAN;
VAR
   ow:    TWB.WinType;
   w:     TWB.WinType;
   line:  CARDINAL;
   PI:    PopupItemPntr;
   PI2:   PopupItemPntr;
   done:  BOOLEAN;

PROCEDURE ResetItem(bi:  PopupItemPntr);
BEGIN
   WITH bi^ DO
      ChangeColorOnScreen(RegularAttr,0,Line,999);
      ChangeColorOnScreen(BoldAttr,XHi,Line,1);
   END;
END ResetItem;

BEGIN
   WITH Data DO
      IF First = NIL THEN
         Result := BYTE(0C);
         RETURN TRUE;
      END;
      ow := TWB.Used();
      CreateNewWindow(w,XPos+1+WX,2+WY,Len,XWidth,Len,ActionBarAttrib,TRUE);
      PI := First;
   END;
   TWB.PutOnTop(w);
   TWB.Use(w);
   line := 0;
   WHILE PI <> NIL DO
      TWB.GotoXY(0,line);
      TWB.WrStr(PI^.Text);
      ChangeColorOnScreen(BoldAttr,PI^.XHi,line,1);
      PI := PI^.Next;
      INC(line);
   END;
   PI := Data.First;
   done := FALSE;
   LOOP
      ChangeColorOnScreen(SpecialAttr,0,PI^.Line,999);
      Result := VAL(BYTE,PI^.Line + 1);
      GetKeyStroke(TC, FunctKey);
      IF ( (NOT FunctKey) AND (Str.Pos(Term,TC) <= HIGH(Term)) ) OR
       ( FunctKey AND (Str.Pos(FunctTerm,TC) <= HIGH(FunctTerm)) ) THEN
          done := TRUE;
          EXIT;
      END;
      abck := GetActBarControlKey(FunctKey, TC);
      CASE abck OF
         MoveLeft, MoveRight:
           done := FALSE;
           Result := BYTE(0C);
           DoRead := FALSE;
           EXIT
       | MoveUp, MoveToPrev:
           ResetItem(PI);
           PI := PI^.Prev;
           IF PI = NIL THEN PI := Data.First END;
       | MoveDown, MoveToNext:
           ResetItem(PI);
           PI := PI^.Next;
           IF PI = NIL THEN PI := Data.First END;
       | MoveToFirst:
           ResetItem(PI);
           PI := Data.First;
       | MoveToLast:
           ResetItem(PI);
           PI := Data.Last;
       | ChooseThis:
           done := TRUE;
           Result := VAL(BYTE,PI^.Line + 1);
           EXIT
       | ABCancel:
           done := FALSE;
           Result := BYTE(0C);
           DoRead := TRUE;
           EXIT
      ELSE
         IF FunctKey THEN Beep
         ELSE
            PI2 := Data.First;
            WHILE (PI2 <> NIL) AND (PI2^.Letter <> CAP(TC)) DO
               PI2 := PI2^.Next;
            END;
            IF PI2 = NIL THEN Beep;
            ELSE
               done := TRUE;
               Result := VAL(BYTE,PI2^.Line+1);
               EXIT
            END;
         END;
      END;
   END;
   GetRidOfWindow(w);
   TWB.Use(ow);
   RETURN done;
END PresentPopup;

PROCEDURE DoMoveFirst(VAR abck:     ActionBarControlKeys);
BEGIN
   ResetBarItem(tBIPntr);
   CASE abck OF
     MoveLeft:
        tBIPntr := tBIPntr^.Prev;
        IF tBIPntr = NIL THEN
           tBIPntr := ID^.LastItem;
        END;
   | MoveRight:
        tBIPntr := tBIPntr^.Next;
        IF tBIPntr = NIL THEN
           tBIPntr := ID^.FirstItem;
        END;
   ELSE ProgramErrorAndHalt('In DoMoveFirst')
   END;
   IF tBIPntr^.Popup.First = NIL THEN DoRead := TRUE
   ELSE abck := ChooseThis END;
END DoMoveFirst;

BEGIN
   ow := TWB.Used();
   TWB.SetPalette(ABWindow, ActionBarAttrib);
   TWB.PutOnTop(ABWindow);
   ActionBarSele := BYTE(0C);
   PopupSelect := BYTE(0C);
   TWB.Info(ABWindow,WD);
   WX := WD.X1;
   WY := WD.Y1;

   tBIPntr := ID^.FirstItem;
   DoRead := TRUE;
   done := FALSE;
   TWB.Use(ABWindow);
   REPEAT
      WITH tBIPntr^ DO
         ChangeColorOnScreen(SpecialAttr,XPos,0,Len);
         IF DoRead THEN
            GetKeyStroke(TC, FunctKey);
            IF ( (NOT FunctKey) AND (Str.Pos(Term,TC) <= HIGH(Term)) ) OR
             ( FunctKey AND (Str.Pos(FunctTerm,TC) <= HIGH(FunctTerm)) ) THEN
                ResetBarItem(tBIPntr);
                TWB.SetPalette(ABWindow,InActiveAttrib);
                TWB.Use(ow);
                RETURN FALSE
            END;
            abck := GetActBarControlKey(FunctKey, TC)
         ELSE DoRead := TRUE END;
         CASE abck OF
            MoveLeft, MoveToPrev:
              ResetBarItem(tBIPntr);
              tBIPntr := tBIPntr^.Prev;
              IF tBIPntr = NIL THEN
                 tBIPntr := ID^.LastItem;
              END;
          | MoveRight, MoveToNext:
              ResetBarItem(tBIPntr);
              tBIPntr := tBIPntr^.Next;
              IF tBIPntr = NIL THEN
                 tBIPntr := ID^.FirstItem;
              END;
          | MoveUp:
              Beep;
          | MoveToFirst:
              ResetBarItem(tBIPntr);
              tBIPntr := ID^.FirstItem;
          | MoveToLast:
              ResetBarItem(tBIPntr);
              tBIPntr := ID^.LastItem;
          | ChooseThis, MoveDown:
              ActionBarSele := tBIPntr^.ItemNo;
              done := PresentPopup(tBIPntr^.Popup,
                                   TC,FunctKey,abck,PopupSelect,DoRead);
              IF (abck = MoveLeft) OR (abck = MoveRight) THEN DoMoveFirst(abck) END;
          | ABCancel:
              ActionBarSele := BYTE(0C);
              PopupSelect := BYTE(0C);
              ResetBarItem(tBIPntr);
              TWB.SetPalette(ABWindow, InActiveAttrib);
              TWB.Use(ow);
              RETURN FALSE;
         ELSE
            IF FunctKey THEN Beep
            ELSE
              tBIPntr2 := ID^.FirstItem;
              LOOP
                 IF tBIPntr2 = NIL THEN
                     Beep;
                     EXIT
                 END;
                 IF CAP(TC) = tBIPntr2^.Letter THEN
                    ResetBarItem(tBIPntr);
                    DoRead := FALSE;
                    tBIPntr := tBIPntr2;
                    abck := ChooseThis;
                    EXIT
                 ELSE
                   tBIPntr2 := tBIPntr2^.Next;
                 END; (* IF CAP(TC) = tBIPntr2^.Letter THEN ... ELSE *)
              END; (* LOOP *)
            END; (* IF FunctKey THEN ... ELSE *)
         END; (* CASE abck OF ... ELSE *)
      END; (* WITH tBIPntr^ DO *)
   UNTIL done;
   ResetBarItem(tBIPntr);
   TWB.SetPalette(ABWindow, InActiveAttrib);
   TWB.Use(ow);
   RETURN TRUE;
END DoActionBar;

BEGIN
    ABWindowMade := FALSE;
END ResActionBar.
