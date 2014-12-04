(*-- m.s. # optimize( stk_frame => off

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
              regass => off ) *)
(*#    data( volatile => on )
*)
IMPLEMENTATION MODULE ResMenus;
(*V5=Dbg Debugging code *)

(* Modified -- removing use of 2nd parameter for NEW and DISPOSE functions
   since they are not supported by the JPI compiler: also changed to local
   extraction of SEGMENT and OFFSET values for ADDRESSes (also not supported
   by JPI compiler).  Finally, changed to support calculation of offsets
   between pointers with different SEGMENT values (common in JPI compiler)
   .. j.bradley (August 1988) *)

(*<Dbg
FROM Trace      IMPORT
      TWriteLn,TWriteChar,TWriteString,TWriteInt,TWriteCard,TWriteAddr,
      CloseTFile;
Dbg>*)
IMPORT TWB, Str, Lib ;
IMPORT ASCII;
FROM SYSTEM IMPORT
  (* type    *)  ADDRESS, BYTE,
  (* proc    *)  SIZE,ADR;
FROM ResBase IMPORT FilePos;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) GetCollection, NextColItem, ReleaseCollection;
FROM ResArray IMPORT
   (*type*) ResDataType,ResArrayError,
   (*proc*) FindResource;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage,
            ResAskUser;
FROM Windows IMPORT
  (* vars   *) TerminationProc,
  (* Consts *) RegularAttr, BoldAttr, SpecialAttr;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM Utils IMPORT
  (* type    *)  Status,
  (* proc    *)  Terminate, Beep,
                 ALLOCATE,DEALLOCATE;
FROM KeyTranslation IMPORT
  (* proc    *)  WriteScreenField,GetScreenField;
FROM GlobalDefs IMPORT
  (* type    *)  StrAny;
FROM StringIO IMPORT
  (* proc    *)  SWriteString, SWriteCard, SWriteInt, SWriteChar;
FROM KeyBase IMPORT
  (* proc    *)  GetKeyStroke;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys, ListControlKeys,
  (* vars  *) FieldMotionExt, FieldMotionASC,
  (* procs *) GetPanelControlKey, GetListControlKey;

CONST
   MaxPgmItems = 40;

(* The following constants specify the size in bytes of various varients
   of the FieldData record for the IBM PC's Logitech and JPI compilers *)

   SizeBase = 13;

   SizeCharType = SizeBase + 8;
   SizeIntType = SizeBase + 6;
   SizeLongIntType = SizeBase + 6;
   SizeCardType = SizeBase + 6;
   SizeLongCardType = SizeBase + 6;
   SizeSwitchType = SizeBase + 11;
   SizeSwitchValueType = SizeBase + 5;

TYPE

   WorkingStr =    ARRAY[0..80] OF CHAR;

(* AddressParts gets at the component parts of the IBM-PC Pointer,
   as implemented for both the Logitech and JPI compilers  j.b. *)

   AddressParts = RECORD
      OFFSET:     CARDINAL;
      SEGMENT:    CARDINAL;
   END;

   TextEntryType = RECORD
      XPos: CHAR;   (* used as 1 byte binary number *)
      YPos: CHAR;   (* used as 1 byte binary number *)
      Text: StrAny
   END;

   TextEntryPointer = POINTER TO TextEntryListType;
   TextEntryListType = RECORD
      Next:    TextEntryPointer;
      Data:    TextEntryType
   END;

   ResFieldDataPointer = POINTER TO ResFieldData;
   ResFieldData = RECORD
      ID: CHAR;    (* used as 1 byte binary number *)
      XPos: CHAR;  (* used as 1 byte binary number *)
      YPos: CHAR;  (* used as 1 byte binary number *)
      Len:  CHAR;  (* used as 1 byte binary number *)
      Next: ResFieldDataPointer;
    END;

  FieldTypeType= (CharType, IntType, LongIntType, CardType,
                  SwitchType, SwitchValueType, LongCardType);

  FieldEntryPntr= POINTER TO FieldData;
  FieldData=     RECORD

      (* These two pointers traverse items in the order in which they
         appear on the screen *)

       NextField:    FieldEntryPntr;
       LastField:    FieldEntryPntr;
       ResData:      ResFieldDataPointer;
       CASE FieldType:    FieldTypeType OF
          CharType:
             ResOff:       CARDINAL;
             ResLen:       CARDINAL;
             SVProc:       DispVProc
        | IntType:
             NResOff:      CARDINAL;
             IVProc:       DispVProc
        | LongIntType:
             LResOff:      CARDINAL;
             LVProc:       DispVProc
        | CardType:
             CResOff:      CARDINAL;
             CVProc:       DispVProc
        | SwitchType:
             SResOff:      CARDINAL;
             NoneVal:      BYTE;
             FirstSwitchVal: FieldEntryPntr;
             LastSwitchVal:  FieldEntryPntr
        | SwitchValueType:
             SwitchHead:   FieldEntryPntr;
             ResVal:       BYTE;
        | LongCardType:
             LCResOff:     CARDINAL;
             LCVProc:      DispVProc
       END
  END;
  MenuInfo = RECORD
     MenuText:   TextEntryPointer;
     MenuFields: FieldEntryPntr;
     ResInfo:    ResFieldDataPointer;
     MenuSize:   CARDINAL;
  END;

  MenuID = POINTER TO MenuInfo;

VAR
   DataStructHolder:     AddressParts;
   MenuIDHolder :        FieldEntryPntr;
   ListEndHolder:        FieldEntryPntr;
   ItemNo:               CARDINAL;
   PgmItems:             ARRAY[0..MaxPgmItems] OF FieldEntryPntr;
   SwitchMaster:         FieldEntryPntr;

(* m.s. no longer applicable with extender
PROCEDURE CalcOffset(L,H: AddressParts): CARDINAL;
BEGIN
   RETURN (H.SEGMENT - L.SEGMENT) * 16 + H.OFFSET - L.OFFSET;
END CalcOffset;
*)

PROCEDURE NoWindow(C: CHAR): BOOLEAN;
BEGIN
  RETURN FALSE
END NoWindow;

PROCEDURE ResError;
BEGIN
   ProgramErrorAndHalt('Resource Error within Menu processor')
END ResError;

PROCEDURE StartMenu(VAR Struct:   ARRAY OF BYTE);
VAR i: CARDINAL;
    temp: ADDRESS;
BEGIN
   MenuIDHolder :=    NIL;
   ListEndHolder:=    NIL;
   temp := ADR(Struct); (* temp variable needed for Logitech implementation restriction j.b. *)
   DataStructHolder := AddressParts(temp);
   ItemNo := 0;
   FOR i := 0 TO MaxPgmItems DO PgmItems[i] := NIL END;
END StartMenu;

PROCEDURE GetNewField(VAR T:    FieldEntryPntr;
                          Type: FieldTypeType);
BEGIN
   WITH T^ DO
      FieldType := Type;
      NextField := NIL;
      LastField := NIL;
      IF Type = SwitchType THEN
         FirstSwitchVal := NIL;
         LastSwitchVal := NIL;
      END;
   END;
END GetNewField;

PROCEDURE CharFieldProc(VAR Result:  ARRAY OF CHAR;VerifyProc: DispVProc);
VAR   T:     FieldEntryPntr;
      Adr:   AddressParts;
BEGIN
   ALLOCATE(T,SizeCharType);
   GetNewField(T,CharType);
   T^.SVProc := VerifyProc;
   PgmItems[ItemNo] := T;
   INC(ItemNo);
   T^.ResLen := HIGH(Result) + 1;
   Adr := AddressParts(ADR(Result));
   IF Adr.SEGMENT <> DataStructHolder.SEGMENT THEN
(* m.s.      Terminate(Halt); *)
       ProgramErrorAndHalt( 'Error in ResMenus, memory offset problem ');
   END;
   T^.ResOff := Adr.OFFSET - DataStructHolder.OFFSET;
(* m.s.   T^.ResOff := CalcOffset(DataStructHolder, Adr); *)
(*<Dbg
   TWriteString('TRACE CharField, T^.ResOff: ');
   TWriteCard(T^.ResOff,0);
   TWriteString(',T^.ResLen: ');
   TWriteCard(T^.ResLen,0);
   TWriteLn;
Dbg>*)
END CharFieldProc;

PROCEDURE CharField(VAR Result:  ARRAY OF CHAR);
VAR
   Dummy:    DispVProc;
BEGIN
   Dummy := DispVProc(NoWindow); (* "magic value" -- indicates no verify *)
   CharFieldProc(Result,Dummy);
END CharField;

PROCEDURE IntFieldProc(VAR Result:  INTEGER;VerifyProc: DispVProc);
VAR   T:     FieldEntryPntr;
      Adr:   AddressParts;
BEGIN
   ALLOCATE(T,SizeIntType);
   GetNewField(T,IntType);
   T^.IVProc := VerifyProc;
   PgmItems[ItemNo] := T;
   INC(ItemNo);
   Adr := AddressParts(ADR(Result));
   IF Adr.SEGMENT <> DataStructHolder.SEGMENT THEN
      ProgramErrorAndHalt( 'Error in ResMenus, memory offset problem ');
(*      Terminate(Halt); *)
   END;
   T^.ResOff := Adr.OFFSET - DataStructHolder.OFFSET;
(*   T^.ResOff := CalcOffset(DataStructHolder, Adr); *)
END IntFieldProc;

PROCEDURE IntField(VAR Result:  INTEGER);
VAR
   Dummy:    DispVProc;
BEGIN
   Dummy := DispVProc(NoWindow); (* "magic value" -- indicates no verify *)
   IntFieldProc(Result,Dummy);
END IntField;

PROCEDURE LongIntFieldProc(VAR Result: LONGINT;VerifyProc: DispVProc);
VAR   T:     FieldEntryPntr;
      Adr:   AddressParts;
BEGIN
   ALLOCATE(T,SizeLongIntType);
   GetNewField(T,LongIntType);
   T^.LVProc := VerifyProc;
   PgmItems[ItemNo] := T;
   INC(ItemNo);
   Adr := AddressParts(ADR(Result));
   IF Adr.SEGMENT <> DataStructHolder.SEGMENT THEN
      ProgramErrorAndHalt( 'Error in ResMenus, memory offset problem ');
(*      Terminate(Halt); *)
   END;
   T^.ResOff := Adr.OFFSET - DataStructHolder.OFFSET;
(* m.s.   T^.ResOff := CalcOffset(DataStructHolder, Adr);    *)
END LongIntFieldProc;

PROCEDURE LongIntField(VAR Result:  LONGINT);
VAR
   Dummy:    DispVProc;
BEGIN
   Dummy := DispVProc(NoWindow); (* "magic value" -- indicates no verify *)
   LongIntFieldProc(Result,Dummy);
END LongIntField;

PROCEDURE CardFieldProc(VAR Result:  CARDINAL;VerifyProc: DispVProc);
VAR   T:     FieldEntryPntr;
      Adr:   AddressParts;
BEGIN
   ALLOCATE(T,SizeCardType);
   GetNewField(T,CardType);
   T^.CVProc := VerifyProc;
   PgmItems[ItemNo] := T;
   INC(ItemNo);
   Adr := AddressParts(ADR(Result));
   IF Adr.SEGMENT <> DataStructHolder.SEGMENT THEN
      ProgramErrorAndHalt( 'Error in ResMenus, memory offset problem ');
(*      Terminate(Halt); *)
   END;
   T^.ResOff := Adr.OFFSET - DataStructHolder.OFFSET;
(* m.s.   T^.ResOff := CalcOffset(DataStructHolder, Adr); *)
END CardFieldProc;


PROCEDURE LongCardField(VAR Result:  LONGCARD);
VAR
   Dummy:    DispVProc;
BEGIN
   Dummy := DispVProc(NoWindow); (* "magic value" -- indicates no verify *)
   LongCardFieldProc(Result,Dummy);
END LongCardField;

PROCEDURE CardField(VAR Result:  CARDINAL);
VAR
   Dummy:    DispVProc;
BEGIN
   Dummy := DispVProc(NoWindow); (* "magic value" -- indicates no verify *)
   CardFieldProc(Result,Dummy);
END CardField;

PROCEDURE LongCardFieldProc(VAR Result: LONGCARD;VerifyProc: DispVProc);
VAR   T:     FieldEntryPntr;
      Adr:   AddressParts;
BEGIN
   ALLOCATE(T,SizeLongCardType);
   GetNewField(T,LongCardType);
   T^.LVProc := VerifyProc;
   PgmItems[ItemNo] := T;
   INC(ItemNo);
   Adr := AddressParts(ADR(Result));
   IF Adr.SEGMENT <> DataStructHolder.SEGMENT THEN
      ProgramErrorAndHalt( 'Error in ResMenus, memory offset problem ');
(*      Terminate(Halt); *)
   END;
   T^.ResOff := Adr.OFFSET - DataStructHolder.OFFSET;
(* m.s.   T^.ResOff := CalcOffset(DataStructHolder, Adr);    *)
END LongCardFieldProc;

PROCEDURE Switches(VAR Result:  BYTE);
VAR   T:     FieldEntryPntr;
      Adr:   AddressParts;
BEGIN
   ALLOCATE(T,SizeSwitchType);
   GetNewField(T,SwitchType);
   Adr := AddressParts(ADR(Result));
   IF Adr.SEGMENT <> DataStructHolder.SEGMENT THEN
      ProgramErrorAndHalt( 'Error in ResMenus, memory offset problem ');
(*      Terminate(Halt); *)
   END;
   T^.SResOff := Adr.OFFSET - DataStructHolder.OFFSET;
(* m.s.   T^.SResOff := CalcOffset(DataStructHolder, Adr); *)
   T^.FirstSwitchVal := NIL;
   T^.LastSwitchVal := NIL;
   SwitchMaster := T;
END Switches;

PROCEDURE SwitchValue(ResultVal: BYTE);
VAR   T:      FieldEntryPntr;
BEGIN
   ALLOCATE(T,SizeSwitchValueType);
   GetNewField(T,SwitchValueType);
   PgmItems[ItemNo] := T;
   INC(ItemNo);
   T^.SwitchHead := SwitchMaster;
(* U := ListEndHolder^.LastSwitchVal;
   IF U <> NIL THEN U^.NextField := T
      ELSE ListEndHolder^.FirstSwitchVal := T END;
   T^.LastField := U;
   T^.NextField := NIL;
   ListEndHolder^.LastSwitchVal := T;  *)
   T^.ResVal := ResultVal;
END SwitchValue;

PROCEDURE SkipField;
BEGIN
   INC(ItemNo);
END SkipField;

PROCEDURE MakeMenu(ResID:   CARDINAL;
              VAR  ID:     MenuID);

VAR size:   CARDINAL;
    ItemRef:CARDINAL;
    Error:  ResArrayError;
    Loc:    FilePos;
    ResC:   ResCollectionType;
    WTE:    TextEntryType;
    STEL:   TextEntryPointer;
    ETEL:   TextEntryPointer;
    NTEL:   TextEntryPointer;
    EFEL:   ResFieldDataPointer;
    NFEL:   ResFieldDataPointer;

PROCEDURE LinkInField(P:  FieldEntryPntr);
BEGIN
   IF ID^.MenuFields = NIL THEN ID^.MenuFields := P
                           ELSE ListEndHolder^.NextField := P END;
   P^.LastField := ListEndHolder;
   P^.NextField := NIL;
   ListEndHolder := P;
END LinkInField;

PROCEDURE LinkInSwitchValue(P:  FieldEntryPntr);
BEGIN
   IF P^.SwitchHead^.FirstSwitchVal = NIL THEN
      LinkInField(P^.SwitchHead)
   END;

   WITH P^.SwitchHead^ DO
      IF FirstSwitchVal = NIL THEN FirstSwitchVal := P
                              ELSE LastSwitchVal^.NextField := P END;
      P^.LastField := LastSwitchVal;
      P^.NextField := NIL;
      LastSwitchVal := P;
   END;
END LinkInSwitchValue;

BEGIN
(* First, get menu information from resource file *)

(* NEW(ID); *)
   ALLOCATE(ID,SIZE(MenuInfo));

   IF NOT FindResource(MenuResource,ResID,Loc,Error) THEN ResError END;
   IF NOT GetCollection(ResC,Loc) THEN ResError END;
   IF NOT NextColItem(ResC,ID^.MenuSize,size) THEN ResError END;

   IF NOT NextColItem(ResC,WTE,size) THEN ResError END;
   ID^.MenuText := NIL;
   WHILE WTE.Text[0] <> 0C DO
      ALLOCATE(NTEL,4+size);
      NTEL^.Next := NIL;
      Lib.Move(ADR(WTE), ADR(NTEL^.Data), size);
      IF ID^.MenuText = NIL THEN ID^.MenuText := NTEL
                    ELSE ETEL^.Next := NTEL
      END;
      ETEL := NTEL;
      IF NOT NextColItem(ResC,WTE,size) THEN ResError END;
   END;

   ID^.MenuFields := NIL;
   ID^.ResInfo := NIL;
(* NEW(NFEL); *)
   ALLOCATE(NFEL,SIZE(ResFieldData));
   WHILE NextColItem(ResC,NFEL^,size) DO
      NFEL^.Next := NIL;
      IF ID^.ResInfo = NIL THEN ID^.ResInfo := NFEL
                    ELSE EFEL^.Next := NFEL END;
      EFEL := NFEL;

      ItemRef := ORD(NFEL^.ID);
      IF PgmItems[ItemRef] <> NIL THEN
         PgmItems[ItemRef]^.ResData := NFEL;
         IF PgmItems[ItemRef]^.FieldType = SwitchValueType THEN
            LinkInSwitchValue(PgmItems[ItemRef])
         ELSE
            LinkInField(PgmItems[ItemRef])
         END
      END;
(*    NEW(NFEL); *)
      ALLOCATE(NFEL,SIZE(ResFieldData));
   END;

(* DISPOSE(NFEL); *)
   DEALLOCATE(NFEL,SIZE(ResFieldData));

   ReleaseCollection(ResC);

END MakeMenu;

PROCEDURE DestroyMenu(VAR ID:   MenuID);
VAR
   T1,T1A:      TextEntryPointer;
   T2,T2A:      FieldEntryPntr;
   T3,T3A:      ResFieldDataPointer;
   T4,T4A:      FieldEntryPntr;  (* for switch value data *)
BEGIN
   IF ID = NIL THEN RETURN END;
   T1 := ID^.MenuText;
   WHILE T1 <> NIL DO
      T1A := T1^.Next;
      DEALLOCATE(T1,7+Str.Length(T1^.Data.Text)); (* was 6+... account of 0C of Text *LP* *)
      T1 := T1A
   END;

   T2 := ID^.MenuFields;
   WHILE T2 <> NIL DO
      T2A := T2^.NextField;
      CASE T2^.FieldType OF
          CharType:    DEALLOCATE(T2,SizeCharType) |
          IntType:     DEALLOCATE(T2,SizeIntType)  |
          LongIntType: DEALLOCATE(T2,SizeLongIntType)  |
          CardType:    DEALLOCATE(T2,SizeCardType) |
          LongCardType:DEALLOCATE(T2,SizeLongCardType)  |
          SwitchType:
             T4 := T2^.FirstSwitchVal;
             WHILE T4 <> NIL DO
                T4A := T4^.NextField;
                IF T4^.FieldType <> SwitchValueType THEN
                   ProgramErrorAndHalt('Invalid type for Switch Value')
                ELSE
                   DEALLOCATE(T4,SizeSwitchValueType)
                END;
                T4 := T4A
             END;
             DEALLOCATE(T2,SizeSwitchType)
          ELSE ProgramErrorAndHalt('CASE error in ShowSwitch')
      END;
      T2 := T2A
   END;

   T3 := ID^.ResInfo;
   WHILE T3 <> NIL DO
      T3A := T3^.Next;
(*    DISPOSE(T3); *)
      DEALLOCATE(T3,SIZE(ResFieldData));
      T3 := T3A
   END;

(* DISPOSE(ID); *)
   DEALLOCATE(ID,SIZE(MenuInfo));
   ID := NIL
END DestroyMenu;

PROCEDURE GetFieldInfo(Menu:       MenuID;
                       ItemID:     CARDINAL;
                   VAR X,Y,Len:    CARDINAL);
VAR RP:    ResFieldDataPointer;
BEGIN
   RP := Menu^.ResInfo;
   WHILE (RP <> NIL) AND (ORD(RP^.ID) <> ItemID) DO RP := RP^.Next END;
   IF RP = NIL THEN
          X := 0; Y := 0; Len := 0
   ELSE
          X := ORD(RP^.XPos);
          Y := ORD(RP^.YPos);
          Len := ORD(RP^.Len);
   END
END GetFieldInfo;

PROCEDURE ClearMenuArea(WindowID:   TWB.WinType;
                        OffX:       CARDINAL;
                        OffY:       CARDINAL;
                        ID:         MenuID);
VAR   i :  CARDINAL ;
BEGIN
   TWB.Use(WindowID);
   TWB.SetPaletteColor(RegularAttr);
   FOR i := 0 TO ID^.MenuSize-1 DO
        TWB.ChangeColorOnScreen(RegularAttr,OffX,OffY+i,999);
        TWB.InitTextOnScreen(' ',OffX,OffY+i,999);
   END;
END ClearMenuArea;

PROCEDURE ShowFixedText(WindowID: TWB.WinType;
                        ID:  MenuID;
                        OffX,OffY:   CARDINAL);
VAR   P:     TextEntryPointer;
      TempStr : StrAny ;
BEGIN
   P := ID^.MenuText;
   WHILE P <> NIL DO
      Str.Copy( TempStr, P^.Data.Text ) ; (* m.s. - so can pass fixed length char array *)
      WriteScreenField( WindowID, 0,
                        OffX + ORD(P^.Data.XPos), OffY + ORD(P^.Data.YPos),
                        TempStr,RegularAttr,P^.Next = NIL);
(* m.s.      WriteScreenField( WindowID, 0,
                        OffX + ORD(P^.Data.XPos), OffY + ORD(P^.Data.YPos),
                        P^.Data.Text,RegularAttr,P^.Next = NIL);
*)
      P := P^.Next
   END;
END ShowFixedText;

PROCEDURE ShowString(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL);
VAR     str:         StrAny;
        i,j:         CARDINAL;
BEGIN
   WITH ID^ DO
      IF ResLen <= HIGH(str) THEN
         str[ResLen] := 0C ;
         i := ResLen ;
      ELSE
         i := HIGH(str) - 1;
         str[i] := 0C ;
      END;
      Lib.Move( ADR(Data[ResOff]), ADR(str), i);
(* m.s.      Lib.Move( ADR(Data[ResOff]), ADR(str), ResLen); *)
(*<Dbg
      TWriteString('TRACE ShowString, ResOff:');
      TWriteCard(ResOff,0);
      TWriteString(',ResLen:');
      TWriteCard(ResLen,0);
      TWriteString(',str:');
      TWriteString(str);
      TWriteLn;
Dbg>*)
      WriteScreenField(WindowID, ORD(ResData^.Len),
             OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos), str,
             BoldAttr,FALSE);
   END
END ShowString;

PROCEDURE ShowCard(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL);
VAR     num:         CARDINAL;
        str:         WorkingStr;
        dummy:       BOOLEAN;
BEGIN
   WITH ID^ DO
      Lib.Move( ADR(Data[ResOff]), ADR(num), 2);
(*    CardToString(num,str,0); *)
      Str.CardToStr(LONGCARD(num),str,10,dummy);
(*<Dbg
      TWriteString('TRACE ShowCard, ResOff:');
      TWriteCard(ResOff,0);
      TWriteString(',num:');
      TWriteCard(num,0);
      TWriteString(',str:');
      TWriteString(str);
      TWriteLn;
Dbg>*)
      WriteScreenField(WindowID, ORD(ResData^.Len),
             OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos), str,
             BoldAttr,FALSE);
   END
END ShowCard;

PROCEDURE ShowLongCard(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL);
VAR     num:         LONGCARD;
        str:         WorkingStr;
        dummy:       BOOLEAN;
BEGIN
   WITH ID^ DO
      Lib.Move( ADR(Data[ResOff]), ADR(num), 4);
      Str.CardToStr(num,str,10,dummy);
(*<Dbg
      TWriteString('TRACE ShowCard, ResOff:');
      TWriteCard(ResOff,0);
      TWriteString(',num:');
      TWriteCard(num,0);
      TWriteString(',str:');
      TWriteString(str);
      TWriteLn;
Dbg>*)
      WriteScreenField(WindowID, ORD(ResData^.Len),
             OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos), str,
             BoldAttr,FALSE);
   END
END ShowLongCard;

PROCEDURE ShowInt(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL);
VAR     num:         INTEGER;
        str:         WorkingStr;
        dummy:       BOOLEAN;
BEGIN
   WITH ID^ DO
      Lib.Move( ADR(Data[ResOff]), ADR(num), 2);
(*    IntToString(num,str,0);  *)
      Str.IntToStr(LONGINT(num),str,10,dummy);
      WriteScreenField(WindowID, ORD(ResData^.Len),
             OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos), str,
             BoldAttr,FALSE);
   END
END ShowInt;

PROCEDURE ShowLongInt(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL);
VAR     num:         LONGINT;
        str:         WorkingStr;
        dummy:       BOOLEAN;
BEGIN
   WITH ID^ DO
      Lib.Move( ADR(Data[ResOff]), ADR(num), 4);
(*    LongIntToString(num,str,0);  *)
      Str.IntToStr(num,str,10,dummy);
      WriteScreenField(WindowID, ORD(ResData^.Len),
             OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos), str,
             BoldAttr,FALSE);
   END
END ShowLongInt;

PROCEDURE ShowSwitch(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL);
VAR     d:       BYTE;
        p:       FieldEntryPntr;
        char:    CHAR;
BEGIN
   WITH ID^ DO
      d := Data[SResOff];
      p := FirstSwitchVal;
      WHILE p <> NIL DO
         WITH p^ DO
            IF d = ResVal THEN char := 'X'
                          ELSE char := '_' END;
            WriteScreenField(WindowID, 0,
                OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos),
                char, BoldAttr,FALSE);
         END;
         p := p^.NextField;
      END
   END;
END ShowSwitch;

PROCEDURE ShowMenu(WindowID:    TWB.WinType;
                   ID:          MenuID;
                   OffX,OffY:   CARDINAL;
               VAR Data:        ARRAY OF BYTE);

VAR     p:     FieldEntryPntr;
(*<Dbg
        ptemp: POINTER TO ARRAY[0..7] OF CHAR;
Dbg>*)
BEGIN
   p := ID^.MenuFields;
(*<Dbg
   ptemp := ADR(Data[0]);
   TWriteString('TRACE ShowMenu, Data: ');
   TWriteString(ptemp^);
   TWriteLn;
Dbg>*)
   WHILE p <> NIL DO
      CASE p^.FieldType OF
          CharType:
            ShowString(Data,WindowID,p,OffX,OffY)    |
          IntType:
            ShowInt(Data,WindowID,p,OffX,OffY)    |
          LongIntType:
            ShowLongInt(Data,WindowID,p,OffX,OffY)    |
          CardType:
            ShowCard(Data,WindowID,p,OffX,OffY)    |
          LongCardType:
            ShowLongCard(Data,WindowID,p,OffX,OffY)    |
          SwitchType:
            ShowSwitch(Data,WindowID,p,OffX,OffY)
          ELSE ProgramErrorAndHalt('CASE error in ShowSwitch')
      END;
      p := p^.NextField
   END;
END ShowMenu;

PROCEDURE  GetString(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         MID:      MenuID;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL;
                     VAR Term:          ARRAY OF CHAR; (* VAR to save stack *)
                     VAR FunctTerm:     ARRAY OF CHAR; (* VAR to save stack *)
                     VAR TC:            CHAR;
                     VAR FunctKey:      BOOLEAN);
VAR     str: StrAny;
        redisplay,reedit: BOOLEAN;
        i : CARDINAL ;
BEGIN
   WITH ID^ DO
      redisplay := FALSE;
      reedit := FALSE;
      REPEAT
	 IF ResLen <= HIGH(str) THEN
	    str[ResLen] := 0C ;	(* ensure end of string marked *)
	    i := ResLen ;
         ELSE
            i := HIGH(str) - 1;
            str[i] := 0C ;
	 END ;
	 Lib.Move( ADR(Data[ResOff]), ADR(str), i);
(* m.s.	 Lib.Move( ADR(Data[ResOff]), ADR(str), ResLen);
	 IF ResLen <= HIGH(str) THEN
	    str[ResLen] := 0C ;	(* ensure end of string marked *)
	 END ;
*)         GetScreenField(WindowID, ORD(ResData^.Len),
                OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos),
                Term, FunctTerm, str, TC, FunctKey);

         IF GetPanelControlKey(FunctKey,TC) = PanelCancel THEN RETURN END;

         Lib.Move( ADR(str), ADR(Data[ResOff]), ResLen);
         IF SVProc <> DispVProc(NoWindow) THEN
            SVProc(ADR(Data),redisplay,reedit);
            IF redisplay THEN ShowMenu(WindowID,MID,OffX,OffY,Data) END;
         END;
      UNTIL NOT reedit;
   END
END GetString;

PROCEDURE  GetCard(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         MID:      MenuID;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL;
                     VAR Term:          ARRAY OF CHAR; (* VAR To save stack *)
                     VAR FunctTerm:     ARRAY OF CHAR; (* VAR to save stack *)
                     VAR TC:            CHAR;
                     VAR FunctKey:      BOOLEAN);
TYPE    CardPtr = POINTER TO CARDINAL;
VAR     str:  WorkingStr;
        num:  CardPtr;
        done: BOOLEAN;
        redisplay,reedit: BOOLEAN;
BEGIN
   WITH ID^ DO
      redisplay := FALSE;
      reedit := FALSE;
      REPEAT
	 num := ADR(Data[ResOff]);
(*	 CardToString(num^,str,0); *)
         Str.CardToStr(LONGCARD(num^),str,10,done);
         GetScreenField(WindowID, ORD(ResData^.Len),
                OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos),
                Term, FunctTerm, str, TC, FunctKey);

         IF GetPanelControlKey(FunctKey,TC) = PanelCancel THEN RETURN END;

(*       StringToCard(str,num^,done); *)
         num^ := CARDINAL(Str.StrToCard(str,10,done));
         IF done THEN
            IF CVProc <> DispVProc(NoWindow) THEN
               CVProc(ADR(Data),redisplay,reedit)
            END;
            IF redisplay THEN ShowMenu(WindowID,MID,OffX,OffY,Data) END;
         ELSE
            ShowCard(Data, WindowID, ID, OffX,OffY);
(*RES OLD MSG 51
"%0" must be a Zero or Positive Number Less than 65535.
*)
            MsgString(str,0);
            PutResWarning( (*RES REM INS*) 51 );
         END;
      UNTIL NOT reedit;
   END
END GetCard;

PROCEDURE  GetInt(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         MID:      MenuID;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL;
                     VAR Term:          ARRAY OF CHAR; (* VAR To save Stack *)
                     VAR FunctTerm:     ARRAY OF CHAR; (* VAR to save Stack *)
                     VAR TC:            CHAR;
                     VAR FunctKey:      BOOLEAN);
TYPE    IntPtr = POINTER TO INTEGER;
VAR     str:  WorkingStr;
        num:  IntPtr;
        wr:   CARDINAL;
        done: BOOLEAN;
        redisplay,reedit: BOOLEAN;
BEGIN
   WITH ID^ DO
      redisplay := FALSE;
      reedit := FALSE;
      REPEAT
	 num := ADR(Data[ResOff]);
(*	 IntToString(num^,str,0); *)
         Str.IntToStr(LONGINT(num^),str,10,done);
         GetScreenField(WindowID, ORD(ResData^.Len),
                OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos),
                Term, FunctTerm, str, TC, FunctKey);

         IF GetPanelControlKey(FunctKey,TC) = PanelCancel THEN RETURN END;

(*       StringToInt(str,num^,done); *)
         num^ := INTEGER(Str.StrToInt(str,10,done));
         IF done THEN
            IF IVProc <> DispVProc(NoWindow) THEN
               IVProc(ADR(Data),redisplay,reedit)
            END;
            IF redisplay THEN ShowMenu(WindowID,MID,OffX,OffY,Data) END;
         ELSE
            ShowInt(Data, WindowID, ID, OffX,OffY);
(*RES OLD MSG 52
"%0" must be an Integer Number between -32768 and 32767.
*)
            MsgString(str,0);
            PutResWarning( (*RES REM INS*) 52 );
         END;
      UNTIL NOT reedit;
   END
END GetInt;

PROCEDURE  GetLongInt(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         MID:      MenuID;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL;
                     VAR Term:          ARRAY OF CHAR; (* VAR to save stack *)
                     VAR FunctTerm:     ARRAY OF CHAR; (* VAR to save stack *)
                     VAR TC:            CHAR;
                     VAR FunctKey:      BOOLEAN);
TYPE    LIntPtr = POINTER TO LONGINT;
VAR     str:  WorkingStr;
        num:  LIntPtr;
        done: BOOLEAN;
        redisplay,reedit: BOOLEAN;
BEGIN
   WITH ID^ DO
      redisplay := FALSE;
      reedit := FALSE;
      REPEAT
	 num := ADR(Data[ResOff]);
(*	 LongIntToString(num^,str,0); *)
         Str.IntToStr(num^,str,10,done);
         GetScreenField(WindowID, ORD(ResData^.Len),
                OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos),
                Term, FunctTerm, str, TC, FunctKey);

         IF GetPanelControlKey(FunctKey,TC) = PanelCancel THEN RETURN END;


(*       StringToLongInt(str,num^,done); *)
         num^ := Str.StrToInt(str,10,done);
         IF done THEN
            IF LVProc <> DispVProc(NoWindow) THEN
               LVProc(ADR(Data),redisplay,reedit)
            END;
            IF redisplay THEN ShowMenu(WindowID,MID,OffX,OffY,Data) END;
         ELSE
            ShowLongInt(Data, WindowID, ID, OffX,OffY);
(*RES OLD MSG 53
"%0" must be an Integer Number between -2147483648 and 2147483648.
*)
            MsgString(str,0);
            PutResWarning( (*RES REM INS*) 53 );
         END;
      UNTIL NOT reedit;
   END
END GetLongInt;

PROCEDURE  GetLongCard(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         MID:      MenuID;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL;
                     VAR Term:          ARRAY OF CHAR; (* VAR to save stack *)
                     VAR FunctTerm:     ARRAY OF CHAR; (* VAR to save stack *)
                     VAR TC:            CHAR;
                     VAR FunctKey:      BOOLEAN);
TYPE    LCardPtr = POINTER TO LONGCARD;
VAR     str:  WorkingStr;
        num:  LCardPtr;
        done: BOOLEAN;
        redisplay,reedit: BOOLEAN;
BEGIN
   WITH ID^ DO
      redisplay := FALSE;
      reedit := FALSE;
      REPEAT
	 num := ADR(Data[ResOff]);
         Str.CardToStr(num^,str,10,done);
         GetScreenField(WindowID, ORD(ResData^.Len),
                OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos),
                Term, FunctTerm, str, TC, FunctKey);

         IF GetPanelControlKey(FunctKey,TC) = PanelCancel THEN RETURN END;


         num^ := Str.StrToCard(str,10,done);
         IF done THEN
            IF LVProc <> DispVProc(NoWindow) THEN
               LVProc(ADR(Data),redisplay,reedit)
            END;
            IF redisplay THEN ShowMenu(WindowID,MID,OffX,OffY,Data) END;
         ELSE
            ShowLongCard(Data, WindowID, ID, OffX,OffY);
(*RES OLD MSG 424
"%0" must be an Positive Integer Number between 0 and 4294967295.
*)
            MsgString(str,0);
            PutResWarning( (*RES REM INS*) 424 );
         END;
      UNTIL NOT reedit;
   END
END GetLongCard;

PROCEDURE  GetSwitch(VAR Data:     ARRAY OF BYTE;
                         WindowID: TWB.WinType;
                         ID:       FieldEntryPntr;
                         OffX,OffY:   CARDINAL;
                     VAR Term:          ARRAY OF CHAR; (* VAR to save stack *)
                     VAR FunctTerm:     ARRAY OF CHAR; (* VAR to save stack *)
                     VAR TC:            CHAR;
                     VAR FunctKey:      BOOLEAN);
    VAR
      rc:            CARDINAL;
      p,cur:         FieldEntryPntr;
      OldPriority:   CARDINAL;
      done:          BOOLEAN;
      ch:            CHAR;

PROCEDURE SetSwitchAttrs(at:   CARDINAL;
                     VAR cur:  FieldEntryPntr);
BEGIN
    p := ID^.FirstSwitchVal;
    TWB.Use(WindowID);
    WHILE p <> NIL DO
       WITH p^ DO
         rc := TWB.GetTextFromScreen(ch, OffX + ORD(ResData^.XPos),
                  OffY + ORD(ResData^.YPos), 1);
         IF ch = 'X' THEN cur := p END;

         TWB.ChangeColorOnScreen(TWB.PaletteRange(CHR(at)), 
                  OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos), 1);
         p := NextField;
       END
    END;
END SetSwitchAttrs;

PROCEDURE MoveXAndCursor(new: FieldEntryPntr);
BEGIN
   Data[ID^.SResOff] := new^.ResVal;
   TWB.WrStr('_');
   cur := new;
   WITH cur^ DO
      TWB.GotoXY( OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos));
      TWB.WrStr('X');
      TWB.GotoXY( OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos));
   END;
END MoveXAndCursor;

BEGIN
    TWB.PutOnTop(WindowID);
    TWB.Use(WindowID);
    TWB.SetPaletteColor(SpecialAttr);
    SetSwitchAttrs(SpecialAttr,cur);

    TWB.CursorOn;
    p := cur;
    WITH p^ DO
      TWB.GotoXY( OffX + ORD(ResData^.XPos), OffY + ORD(ResData^.YPos));
    END;
    done := FALSE;
    REPEAT
       GetKeyStroke(ch,FunctKey);
       CASE GetPanelControlKey(FunctKey, ch) OF
         CursorRight:
            IF p^.NextField = NIL THEN p := ID^.FirstSwitchVal
                                  ELSE p := p^.NextField END;
            MoveXAndCursor(p);
       | CursorLeft:
            IF p^.LastField = NIL THEN p := ID^.LastSwitchVal
                                  ELSE p := p^.LastField END;
            MoveXAndCursor(p);
       | EndOfField:
            p := ID^.LastSwitchVal;
            MoveXAndCursor(p);
       | BeginningOfField:
            p := ID^.FirstSwitchVal;
            MoveXAndCursor(p);
       ELSE
          IF FunctKey THEN
             IF Str.Pos(FunctTerm,ch) < MAX(CARDINAL) THEN done := TRUE
             ELSE Beep END
          ELSE
             IF ch = ' ' THEN
                IF p^.NextField = NIL THEN p := ID^.FirstSwitchVal
                                      ELSE p := p^.NextField END;
                MoveXAndCursor(p);
             ELSIF Str.Pos(Term,ch) < MAX(CARDINAL) THEN done := TRUE
             ELSE Beep;
             END
          END
       END
    UNTIL done;

    TC := ch;

    SetSwitchAttrs(BoldAttr,cur);
    TWB.SetPaletteColor(BoldAttr);
    TWB.CursorOff;
END GetSwitch;

PROCEDURE DoMenu(WindowID:      TWB.WinType;
                 ID:            MenuID;
                 OffX,OffY:     CARDINAL;
                 Term:          ARRAY OF CHAR;
                 FunctTerm:     ARRAY OF CHAR;
             VAR Data:          ARRAY OF BYTE;
             VAR ItemNumb:      CARDINAL;
             VAR TC:            CHAR;
             VAR FunctKey:      BOOLEAN );

VAR
      ftrm:          WorkingStr;
      trm:           WorkingStr;
      rc:            CARDINAL;
      p:             FieldEntryPntr;
      done:          BOOLEAN;
      ch:            CHAR;
      i:             CARDINAL;

PROCEDURE InTerminationLists(FunctKey: BOOLEAN;
                             ch:       CHAR): BOOLEAN;
BEGIN
   RETURN ( (NOT FunctKey) AND (Str.Pos(Term,ch) < MAX(CARDINAL)) ) OR
          ( FunctKey AND (Str.Pos(FunctTerm,ch) < MAX(CARDINAL)) );
END InTerminationLists;

BEGIN
   Str.Concat(ftrm,FunctTerm,FieldMotionExt);
   Str.Concat(trm,Term,FieldMotionASC);
   p := ID^.MenuFields;
   i := 1;
   WHILE (i < ItemNumb) DO
       IF p^.NextField = NIL THEN
           ItemNumb := i
       ELSE
          p := p^.NextField;
          INC(i)
       END
   END;
   ItemNumb := i;
   done := FALSE;
   REPEAT
      CASE p^.FieldType OF
          CharType:
            GetString(Data,WindowID,ID,p,OffX,OffY,trm,ftrm,ch,FunctKey) |
          IntType:
            GetInt(Data,WindowID,ID,p,OffX,OffY,trm,ftrm,ch,FunctKey) |
          LongIntType:
            GetLongInt(Data,WindowID,ID,p,OffX,OffY,trm,ftrm,ch,FunctKey) |
          CardType:
            GetCard(Data,WindowID,ID,p,OffX,OffY,trm,ftrm,ch,FunctKey) |
          LongCardType:
            GetLongCard(Data,WindowID,ID,p,OffX,OffY,trm,ftrm,ch,FunctKey) |
          SwitchType:
            GetSwitch(Data,WindowID,p,OffX,OffY,trm,ftrm,ch,FunctKey)
          ELSE ProgramErrorAndHalt('CASE error in DoMenu')
       END;

       CASE GetPanelControlKey(FunctKey, ch) OF
         PanelCancel: done := TRUE
       | NextField:
            p := p^.NextField;
            INC(ItemNumb);
            IF p = NIL THEN
               IF InTerminationLists(FunctKey,ch) THEN done := TRUE
               ELSE
                  p := ID^.MenuFields;
                  ItemNumb := 1;
               END;
            END;
       | PrevField:
            p := p^.LastField;
            DEC(ItemNumb);
            IF p = NIL THEN
               IF InTerminationLists(FunctKey,ch) THEN done := TRUE
               ELSE
                  i := 1;
                  p := ID^.MenuFields;
                  WHILE (p^.NextField <> NIL) DO
                      p := p^.NextField;
                      INC(i)
                  END;
                  ItemNumb := i
               END
            END;
       | FirstField:
            IF InTerminationLists(FunctKey,ch) THEN done := TRUE
            ELSE
               p := ID^.MenuFields;
               ItemNumb := 1;
            END;
       | LastField:
            IF InTerminationLists(FunctKey,ch) THEN done := TRUE
            ELSE
               i := 1;
               p := ID^.MenuFields;
               WHILE (p^.NextField <> NIL) DO
                   p := p^.NextField;
                   INC(i)
               END;
               ItemNumb := i
            END;
       ELSE
          IF InTerminationLists(FunctKey,ch) THEN done := TRUE
                                             ELSE Beep END;
       END;
   UNTIL done;

   TC := ch;
END DoMenu;

END ResMenus.

