IMPLEMENTATION MODULE Lists ;

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

FROM SYSTEM  IMPORT ADDRESS;
FROM ErrorBase IMPORT ProgramErrorAndHalt ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;

TYPE
    ListItemDataPntr = POINTER TO ListItemData;
    ListItemData = RECORD
        ItemData:        ADDRESS;
        Prev, Next:      ListItemDataPntr;
    END;

    MasterListData = RECORD
        Top, Bottom:     ListItemDataPntr;
        Usage:           CARDINAL;
    END;

    ListPointer = POINTER TO RECORD
        MasterList:     POINTER TO MasterListData;
        Item:           ListItemDataPntr;
    END;

PROCEDURE NewList(VAR Ptr:     ListPointer);
BEGIN
   NEW(Ptr);
   Ptr^.Item := NIL;
   NEW(Ptr^.MasterList);
   WITH Ptr^.MasterList^ DO
      Top := NIL;
      Bottom := NIL;
      Usage := 1
   END
END NewList;

PROCEDURE CopyListPointer(Old:   ListPointer;
                      VAR New:   ListPointer);
BEGIN
   IF Old = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in CopyListPointer' );
       RETURN
   END;
   NEW(New);
   New^.Item := Old^.Item;
   New^.MasterList := Old^.MasterList;
   INC(New^.MasterList^.Usage);
END CopyListPointer;

PROCEDURE FreeListPointer(VAR Ptr:   ListPointer);
VAR   p,p1:      ListItemDataPntr;
BEGIN
   IF Ptr = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in FreeListPointer' );
       RETURN
   END;
   DEC(Ptr^.MasterList^.Usage);
   IF Ptr^.MasterList^.Usage = 0 THEN
      p := Ptr^.MasterList^.Top;
      WHILE p <> NIL DO
        p1 := p^.Next;
        DISPOSE(p);
        p := p1;
      END;
      DISPOSE(Ptr^.MasterList);
   END;
   DISPOSE(Ptr);
   Ptr := NIL;
END FreeListPointer;

PROCEDURE AddBelow(Ptr:   ListPointer;
                   Data:  ADDRESS);
VAR   p,p1:     ListItemDataPntr;
BEGIN
   IF Ptr = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in AddBelow' );
       RETURN
   END;
   NEW(p);
   p^.ItemData := Data;
   IF Ptr^.Item = NIL THEN
       p^.Prev := NIL;
       p^.Next := Ptr^.MasterList^.Top
   ELSE
       p^.Prev := Ptr^.Item;
       p^.Next := Ptr^.Item^.Next;
   END;
   IF p^.Prev <> NIL THEN
       p^.Prev^.Next := p
   ELSE
       Ptr^.MasterList^.Top := p;
   END;
   IF p^.Next <> NIL THEN
       p^.Next^.Prev := p
   ELSE
       Ptr^.MasterList^.Bottom := p;
   END;
END AddBelow;

PROCEDURE DeleteListItem(VAR Ptr:     ListPointer);
VAR   p:     ListItemDataPntr;
BEGIN
   IF Ptr = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in DeleteListItem' );
       RETURN
   END;
   IF Ptr^.Item = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in DeleteListItem(2)' );
       RETURN
   END;
   p := Ptr^.Item;
   IF p^.Next = NIL THEN
      Ptr^.Item := p^.Prev
   ELSE
      Ptr^.Item := p^.Next
   END;
   WITH p^ DO
      IF p^.Next <> NIL THEN
         p^.Next^.Prev := p^.Prev
      ELSE
         Ptr^.MasterList^.Bottom := p^.Prev
      END;
      IF p^.Prev <> NIL THEN
         p^.Prev^.Next := p^.Next
      ELSE
         Ptr^.MasterList^.Top := p^.Next
      END
   END;
   DISPOSE(p);
END DeleteListItem;

PROCEDURE GetData(Ptr:        ListPointer;
              VAR Data:       ADDRESS);
BEGIN
   IF Ptr = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in GetData' );
       RETURN
   END;
   IF Ptr^.Item = NIL THEN
       Data := NIL;
(*     ProgramErrorAndHalt('Invalid Pointer in GetData(2)');   *)
       RETURN
   END;
   Data := Ptr^.Item^.ItemData;
END GetData;

PROCEDURE MoveUp(VAR Ptr:     ListPointer): BOOLEAN;
BEGIN
   IF Ptr = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in MoveUp' );
       RETURN FALSE
   END;
   IF Ptr^.Item = NIL THEN
       RETURN FALSE
   END;
   Ptr^.Item := Ptr^.Item^.Prev;
   RETURN TRUE
END MoveUp;

PROCEDURE MoveDown(VAR Ptr:     ListPointer): BOOLEAN;
BEGIN
   IF Ptr = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in MoveDown' );
       RETURN FALSE
   END;
   IF Ptr^.Item = NIL THEN
       Ptr^.Item := Ptr^.MasterList^.Top;
       RETURN Ptr^.Item <> NIL
   ELSE
      IF Ptr^.Item^.Next = NIL THEN RETURN FALSE END;
      Ptr^.Item := Ptr^.Item^.Next; 
      RETURN TRUE
   END;
END MoveDown;

PROCEDURE SetToTop(VAR Ptr:     ListPointer);
BEGIN
   IF Ptr = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in SetToTop' );
       RETURN
   END;
   Ptr^.Item := NIL;
END SetToTop;

PROCEDURE SetToLast(VAR Ptr:     ListPointer);
BEGIN
   Ptr^.Item := Ptr^.MasterList^.Bottom
END SetToLast;

PROCEDURE AtTop(Ptr:   ListPointer): BOOLEAN;
BEGIN
   IF Ptr = NIL THEN
       ProgramErrorAndHalt( 'Invalid Pointer in AtTop' );
       RETURN FALSE
   END;
   RETURN Ptr^.Item = NIL
END AtTop;

END  Lists .

