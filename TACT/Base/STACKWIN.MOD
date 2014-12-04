IMPLEMENTATION MODULE StackWindows;

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

IMPORT TWB;
FROM Utils IMPORT Beep, ALLOCATE, DEALLOCATE;
FROM SYSTEM IMPORT ADR;
FROM Windows IMPORT
  (* Vars *)  DialogAttrib, ErrorAttrib, InActiveAttrib, ActiveAttrib,
              ActionBarAttrib, TerminationProc,
  (* Const *) RegularAttr, BoldAttr, SpecialAttr,
  (* Procs *) InitWindows, CreateNewWindow, GetRidOfWindow,
              ReSizeWindow, MoveWindow;
FROM ErrorBase IMPORT ProgramErrorAndHalt;

TYPE
   StackWindPntr = POINTER TO StackWindData;
   StackWindData = RECORD
      Info:     WindowInfoPtr;
      InitP:    PROC;
      WPtr:     TWB.WinType;
      Next:     StackWindPntr;
   END;

VAR
   WindPriority:   CARDINAL;
   WindStack:      StackWindPntr;

PROCEDURE DummyInit;
BEGIN
END DummyInit;

PROCEDURE PushNewWindow(VAR Info: WindowInfo;
                        VAR Ptr:  TWB.WinType;
                            Init: PROC);
VAR
   temp:    StackWindPntr;
   tAttr:   TWB.PaletteDef;
BEGIN
   ALLOCATE(temp,SIZE(StackWindData));
   INC(WindPriority);
   temp^.Next := WindStack;
   temp^.Info := ADR(Info);
   IF WindStack <> NIL THEN
      WindStack^.Info^.IsTop := FALSE;
      IF Info.Type <> Message THEN
         TWB.SetPalette(WindStack^.WPtr, InActiveAttrib)
      END;
   END;

   CASE Info.Type OF
     Dialog:  tAttr := DialogAttrib;
   | Active:  tAttr := ActiveAttrib;
   | ActBar:  tAttr := ActionBarAttrib;
   | Message: tAttr := ErrorAttrib;
   END;
   WITH Info DO
      CreateNewWindow(Ptr,XPos,YPos,YSize,XSize,MxYSize,tAttr,TRUE);
   END;
   TWB.PutOnTop(Ptr);
   TWB.Use(Ptr);
   temp^.WPtr := Ptr;
   temp^.InitP := Init;
   temp^.Info^.IsTop := TRUE;
   WindStack := temp;
END PushNewWindow;

PROCEDURE PopWindow;
VAR
   temp:    StackWindPntr;
   oldtype: WindowType;
BEGIN
   GetRidOfWindow(WindStack^.WPtr);
   temp := WindStack;
   temp^.Info^.IsTop := FALSE;
   oldtype := temp^.Info^.Type;
   WindStack := temp^.Next;
   WindStack^.Info^.IsTop := TRUE;
   TWB.PutOnTop(WindStack^.WPtr);
   TWB.Use(WindStack^.WPtr);
   DEALLOCATE(temp,SIZE(StackWindData));
   DEC(WindPriority);
   IF oldtype <> Message THEN
      WITH WindStack^ DO
         CASE Info^.Type OF
           Dialog: TWB.SetPalette(WPtr, DialogAttrib)
         | Active: TWB.SetPalette(WPtr, ActiveAttrib)
         | ActBar: TWB.SetPalette(WPtr, ActionBarAttrib)
         | Message:TWB.SetPalette(WPtr, ErrorAttrib);
         END;
      END;
   END;
END PopWindow;

PROCEDURE MoveCurrentWindow(VAR Extended:  BOOLEAN;
                            VAR ch:        CHAR): BOOLEAN;
VAR
  WD:    TWB.WinDef;
BEGIN
   WITH WindStack^.Info^ DO
      IF NOT AllowMove THEN
         Beep;
         RETURN FALSE
      END;
      MoveWindow(WindStack^.WPtr,Extended,ch);
      TWB.Info(WindStack^.WPtr,WD);
      XPos := WD.X1 + 1;
      YPos := WD.Y1 + 1;
   END;
   RETURN TRUE
END MoveCurrentWindow;

PROCEDURE ResizeCurrentWindow(VAR Extended: BOOLEAN;
                              VAR ch:       CHAR): BOOLEAN;
VAR
  WD:    TWB.WinDef;
BEGIN
   WITH WindStack^.Info^ DO
      IF NOT AllowResize THEN
         Beep;
         RETURN FALSE
      END;
      ReSizeWindow(WindStack^.WPtr,Extended,ch);
      TWB.Info(WindStack^.WPtr,WD);
      YSize := WD.Y2-WD.Y1 - 1;
      XSize := WD.X2-WD.X1 - 1;
      WindStack^.InitP;
   END;
   RETURN TRUE;
END ResizeCurrentWindow;

PROCEDURE GetCurrentPointer(VAR Ptr:  WindowInfoPtr);
BEGIN
   Ptr := WindStack^.Info;
END GetCurrentPointer;

PROCEDURE RollWindows(VAR Ptr:  WindowInfoPtr);
VAR i:        CARDINAL;
    p,q:      StackWindPntr;
BEGIN
   i := WindPriority;
   IF i <= 2 THEN RETURN END; (* no roll if only 1 or 2 windows on screen jb *)
   p := WindStack;
   q := WindStack;

(* first, reassign all windows except top to 1 higher priority  jb *)
   WHILE i > 2 DO (* all but bottom window are scrolled  j.b. *)
      q := q^.Next;
      DEC(i);
   END;
   TWB.PutBeneath(p^.WPtr,q^.WPtr);
   WindStack := WindStack^.Next;
   TWB.PutOnTop(WindStack^.WPtr);
   TWB.Use(WindStack^.WPtr);
   WindStack^.Info^.IsTop := TRUE;
   WITH WindStack^ DO
      CASE Info^.Type OF
        Dialog: TWB.SetPalette(WPtr, DialogAttrib)
      | Active: TWB.SetPalette(WPtr, ActiveAttrib)
      | ActBar: TWB.SetPalette(WPtr, ActionBarAttrib)
      | Message:TWB.SetPalette(WPtr, ErrorAttrib);
      END
   END;
   Ptr := WindStack^.Info;

(* Now, put what was the top window on the bottom (above base window) jb *)

   p^.Info^.IsTop := FALSE;
   TWB.SetPalette(p^.WPtr, InActiveAttrib);
   p^.Next := q^.Next;
   q^.Next := p;
END RollWindows;

PROCEDURE MakeHighestPriority(Ptr:   WindowInfoPtr);
VAR i:        CARDINAL;
    p,q:      StackWindPntr;
BEGIN
   i := WindPriority - 1;
   p := WindStack;
   q := NIL;
   WHILE (i >= 1) AND (p <> NIL) AND (p^.Info <> Ptr) DO
      q := p;
      p := p^.Next;
      DEC(i);
   END;
   IF (i = 0) OR (p = NIL) THEN
     ProgramErrorAndHalt('Given Window not in stack')
   END;
   IF q = NIL THEN RETURN END; (* top window already highest priority *)
   TWB.SetPalette(WindStack^.WPtr, InActiveAttrib);
   WindStack^.Info^.IsTop := FALSE;
   q^.Next := p^.Next;
   p^.Next := WindStack;
   WindStack := p;
   WindStack^.Info^.IsTop := TRUE;
   TWB.PutOnTop(WindStack^.WPtr);
   TWB.Use(WindStack^.WPtr);
   WITH WindStack^ DO
      CASE Info^.Type OF
        Dialog: TWB.SetPalette(WPtr, DialogAttrib)
      | Active: TWB.SetPalette(WPtr, ActiveAttrib)
      | ActBar: TWB.SetPalette(WPtr, ActionBarAttrib)
      | Message:TWB.SetPalette(WPtr, ErrorAttrib);
      END
   END;
END MakeHighestPriority;

PROCEDURE LayoutWindowsAsPanels;
VAR
   i:   CARDINAL;
   j:   CARDINAL;
   t,b: CARDINAL;
   cw:  StackWindPntr;
BEGIN
   IF WindPriority <= 2 THEN RETURN END; (* no panelization if 1 or 2 windows *)
   i := WindPriority - 1 ; (* # of "panelable" windows *)

   cw := WindStack;
   t := 1;
   FOR j := 1 TO i DO
      b := j * 24 DIV i;
      TWB.Change(cw^.WPtr, 0,t,TWB.ScreenWidth-1, b);
      WITH cw^.Info^ DO
        XPos := 1;
        YPos := t + 1;
        XSize := 78;
        YSize := b - t - 1;
      END;
      t := b;
      cw := cw^.Next;
   END;
END LayoutWindowsAsPanels;

PROCEDURE ZoomCurrentWindow;
VAR
   TWBPtr:       TWB.WinType;
   InfoPtr:      WindowInfoPtr;
BEGIN
   TWBPtr := WindStack^.WPtr;
   InfoPtr := WindStack^.Info;
   IF (NOT InfoPtr^.AllowResize) OR (WindPriority <= 1) THEN
      Beep;
      RETURN;
   END;
   WITH InfoPtr^ DO
      XPos :=   1;
      YPos :=   2;
      XSize := 78;
      YSize := 22;
   END;
   TWB.Change(TWBPtr, 0,1,TWB.ScreenWidth-1, TWB.ScreenDepth -1);
   WindStack^.InitP;
END ZoomCurrentWindow;

BEGIN
   WindPriority := 0;
   WindStack    := NIL;
END StackWindows.
