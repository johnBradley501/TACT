IMPLEMENTATION MODULE ResMessages;

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
(*-- m.s $V-*)
IMPORT Str, Lib ;
FROM SYSTEM IMPORT ADR,ADDRESS;
FROM Utils IMPORT ALLOCATE, DEALLOCATE;
FROM ErrorBase IMPORT PutError, PutWarning, PutMessage, AskUser,
                      ProgramErrorAndHalt;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;
FROM ResArray IMPORT
   (*type*) ResDataType,ResArrayError,
   (*proc*) FindResource;
FROM ResBase IMPORT FilePos, ReadResourceBase;
FROM GlobalDefs IMPORT
  (* type    *)  StrAny;

CONST
    SWorkSize = 256;

TYPE
    TxtPntr =      POINTER TO ARRAY[0..2047] OF CHAR;
    ShortTxtPntr = POINTER TO ARRAY[0..SWorkSize-1] OF CHAR;
    DataTypeType = (String, Cardinal, Integer, LongInt);

    MsgItemDataType = RECORD
       GivenSz:      CARDINAL ;
       CASE DataType: DataTypeType OF
          String:    DataPntr:   ADDRESS;
                     DataLen:    CARDINAL
        | Cardinal:  CardVal:    CARDINAL
        | Integer:   IntVal:     INTEGER
        | LongInt:   LongIntVal: LONGINT
       END
    END;

VAR
   MsgItemData:    ARRAY[0..MaxMsgItems-1] OF MsgItemDataType;
   CurrentItem:    CARDINAL;
   MarkerChar:     CHAR;
   TMsg:           ARRAY[0..SWorkSize-1] OF CHAR;

PROCEDURE MsgString(VAR Text:  ARRAY OF CHAR; sz:   CARDINAL);
BEGIN
    WITH MsgItemData[CurrentItem] DO
       DataPntr := ADR(Text);
       DataType := String;
       DataLen := HIGH(Text)+1;
       IF DataLen > SWorkSize THEN DataLen := SWorkSize END;
       GivenSz := sz;
    END;
    INC(CurrentItem)
END MsgString;

PROCEDURE MsgCard(Numb:  CARDINAL; sz:   CARDINAL);
BEGIN
    WITH MsgItemData[CurrentItem] DO
       DataType := Cardinal;
       CardVal := Numb;
       GivenSz := sz;
    END;
    INC(CurrentItem)
END MsgCard;

PROCEDURE MsgInt(Numb:  INTEGER; sz:   CARDINAL);
BEGIN
    WITH MsgItemData[CurrentItem] DO
       DataType := Integer;
       IntVal := Numb;
       GivenSz := sz;
    END;
    INC(CurrentItem)
END MsgInt;

PROCEDURE MsgLongInt(Numb:  LONGINT; sz:   CARDINAL);
BEGIN
    WITH MsgItemData[CurrentItem] DO
       DataType := LongInt;
       LongIntVal := Numb;
       GivenSz := sz;
    END;
    INC(CurrentItem)
END MsgLongInt;

PROCEDURE ProcessResMessage(BMsgTxt:   TxtPntr;
                            sz:        CARDINAL;
                        VAR MsgTxt:    ARRAY OF CHAR);
VAR
    Error:     ResArrayError;
    i,j,k:       CARDINAL;
    ItemsMax:  CARDINAL;
    mkpos:     CARDINAL;
    mk2pos:    CARDINAL;
    mk3pos:    CARDINAL;

PROCEDURE DoParmSub;
VAR
   ParmNo:   CARDINAL;
   CardPtr:  POINTER TO CARDINAL;
   IntPtr:   POINTER TO CARDINAL;
   SWork:    ShortTxtPntr;
   TempStr:  StrAny ;
BEGIN
   ParmNo := 0;
   WHILE (i < sz) AND (BMsgTxt^[i] >= '0') AND (BMsgTxt^[i] <= '9') DO
        ParmNo := ParmNo*10 + ORD(BMsgTxt^[i]) - ORD('0');
        INC(i)
   END;
   IF ParmNo > ItemsMax THEN
      ProgramErrorAndHalt('Resource error (3) in GetResMessage');
      RETURN
   END;
   WITH MsgItemData[ParmNo] DO
      CASE DataType OF
        String:
(* m.s.         ALLOCATE(SWork,DataLen + 1); *)
          ALLOCATE( SWork, SWorkSize ) ;
          IF (DataLen < SWorkSize) THEN
             SWork^[DataLen] := 0C ;
             k := DataLen ;
          ELSE
             k := SWorkSize - 1 ;
             SWork^[k] := 0C ;
          END;
          Lib.Move( DataPntr, SWork, k);
(* m.s.          Lib.Move( DataPntr, SWork, DataLen);
          IF (DataLen < SWorkSize) THEN SWork^[DataLen] := 0C END;
*)          SWriteString(MsgTxt,j,SWork^,GivenSz);
          DEALLOCATE(SWork,SWorkSize); (* m.s. was DataLen  + 1 *)
      | Cardinal:
          SWriteCard(MsgTxt,j,CardVal,GivenSz)
      | Integer:
          SWriteInt(MsgTxt,j,IntVal,GivenSz)
      | LongInt:
          SWriteLongInt(MsgTxt,j,LongIntVal,GivenSz)
      END
   END;
END DoParmSub;

BEGIN
   MsgTxt[0] := 0C;
   ItemsMax := CurrentItem;
   CurrentItem := 0;

   i := 0;
   j := 0;
   WHILE (i <= sz) AND (j <= HIGH(MsgTxt)) DO
      mkpos := Lib.ScanR( ADR(BMsgTxt^[i]), sz-i, BYTE(MarkerChar) );
      IF mkpos > sz THEN mk2pos := sz-i        (* MarkerChar not found *)
                    ELSE mk2pos := mkpos END;
      IF mk2pos > HIGH(MsgTxt) - j +1 THEN mk3pos := HIGH(MsgTxt) - j + 1
                                      ELSE mk3pos := mk2pos END;
      IF mk3pos > 0 THEN
         Lib.Move( ADR(BMsgTxt^[i]), ADR(MsgTxt[j]), mk3pos);
      END;
      i := i + mk2pos + 1;
      j := j + mk2pos;
      IF i < sz THEN
          IF BMsgTxt^[i] = MarkerChar THEN
             MsgTxt[j] := MarkerChar;
             INC(j)
          ELSE
             DoParmSub;
          END
      END
   END;

   IF (j < HIGH(MsgTxt)) THEN MsgTxt[j] := 0C END;
END ProcessResMessage;

PROCEDURE GetResMessage(ID:  CARDINAL;
                   VAR MsgTxt:    ARRAY OF CHAR);
VAR
    Error:     ResArrayError;
    MsgLoc:    FilePos;
    BMsgTxt:   TxtPntr;
    sz:        CARDINAL;
    TmpStr:    StrAny ;
BEGIN
   IF NOT FindResource(MessageResource,ID,MsgLoc,Error) THEN
      ProgramErrorAndHalt('Resource error (1) in GetResMessage');
      RETURN
   END;

   BMsgTxt := NIL;
   IF NOT ReadResourceBase(0,MsgLoc,BMsgTxt,sz) THEN
      ProgramErrorAndHalt('Resource error (2) in GetResMessage');
      RETURN
   END;
   TmpStr[0] := 0C ; (* m.s. *)
   ProcessResMessage(BMsgTxt, sz, TmpStr);
   DEALLOCATE(BMsgTxt,sz);
   Str.Copy( MsgTxt, TmpStr ) ;
END GetResMessage;

PROCEDURE PutResError(ID:  CARDINAL);
BEGIN
   GetResMessage(ID,TMsg);
   PutError(TMsg);
END PutResError;

PROCEDURE PutResWarning(ID:  CARDINAL);
BEGIN
   GetResMessage(ID,TMsg);
   PutWarning(TMsg);
END PutResWarning;

PROCEDURE PutResMessage(ID:  CARDINAL);
BEGIN
   GetResMessage(ID,TMsg);
   PutMessage(TMsg);
END PutResMessage;

PROCEDURE ResAskUser(ID     : CARDINAL;
                     Term   : ARRAY OF CHAR;  (* set of terminating characters *)
                 VAR Reply  : CHAR ) ;
VAR
    Error:     ResArrayError;
    MsgLoc:    FilePos;
    BMsgTxt:   TxtPntr;
    CMsgTxt:   TxtPntr;
    sz:        CARDINAL;
    i:         CARDINAL;
    Msgsz:     CARDINAL;
    MsgTxt:    ShortTxtPntr;
    URep:      CHAR;
BEGIN
   IF NOT FindResource(ChoiceResource,ID,MsgLoc,Error) THEN
      ProgramErrorAndHalt('Resource error (1) in ResAskUser');
      RETURN
   END;

   BMsgTxt := NIL;
   IF NOT ReadResourceBase(0,MsgLoc,BMsgTxt,sz) THEN
      ProgramErrorAndHalt('Resource error (2) in ResAskUser');
      RETURN
   END;
   Msgsz := Str.Length(BMsgTxt^);
   ALLOCATE(MsgTxt,SWorkSize); (* size of ShortTxtPntr *)
   ProcessResMessage(BMsgTxt, Msgsz, MsgTxt^);

 (* Now, get set of characters user can type in
    in response to message ( characters are past end of msg) *)

   CMsgTxt := ADR(BMsgTxt^[Msgsz+1]);
   AskUser(MsgTxt^,CMsgTxt^,URep);
   DEALLOCATE(MsgTxt, SWorkSize);

 (* User has specified character, from set CMsgTxt^, find corresponding
    character in Term, and return that to calling program *)

   i := Str.Pos(CMsgTxt^,URep);
   IF i <= 2047 THEN Reply := Term[i]
                ELSE Reply := 0C END;
   DEALLOCATE(BMsgTxt,sz);
END ResAskUser;

BEGIN
   CurrentItem := 0;
   MarkerChar := '%';
END ResMessages.
