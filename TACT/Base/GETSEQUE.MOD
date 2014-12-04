IMPLEMENTATION MODULE GetSequences ;

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

IMPORT Str;
FROM GlobalDefs IMPORT SequenceType, StrAny, MaxCharsInSeq;
FROM STANDARD   IMPORT CharNameType, CharNameLength, NumberChars,
                       SortedCharNames;
FROM Utils      IMPORT StandardizeCharName,PrintCode,PrintHex1,PrintHex2,
                       UpcaseStr;
FROM ExtendedAsciiKeys
                IMPORT CharacterEntry, KeyName, KeyBASICTable, KeyALTTable,
                       KeySHIFTTable, KeyCTRLTable;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage;

FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) ReleaseCollection;

FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;

    TYPE 
      CompletionCondition = (OK, EndOfData, ErrorOccurred);
      InputStringType = ARRAY [0..80] OF CHAR;

    VAR 
      InputRecordNumber:      CARDINAL; 
      InputPosition:          CARDINAL;
      InputString:            InputStringType;
      FirstCall:              BOOLEAN;
      INTERNALText:           ARRAY[0..9] OF CHAR;
      SHIFTText:              ARRAY[0..9] OF CHAR;
      ALTText:                ARRAY[0..9] OF CHAR;
      CTRLText:               ARRAY[0..9] OF CHAR;

    PROCEDURE GetItem(VAR ActualLength:  CARDINAL;
                      VAR LengthGiven:   BOOLEAN;
                      VAR Result:        ARRAY OF CHAR;
                      VAR DirectionChar: CHAR;
                      VAR GivenMode:     CHAR;
                      VAR ErrorMsg:      ARRAY OF CHAR): CompletionCondition;
      VAR 
        StartItem:      CARDINAL;
        ItemLength:     CARDINAL;
        Delim:          CHAR; 
        TempItem:       StrAny;
        Code:           CARDINAL;
        EPos:           CARDINAL;
        ProcInit:       BOOLEAN;
        GotMode:        BOOLEAN;
        GotDir:         BOOLEAN;

    BEGIN
      GivenMode := ' ';
      Result[0] := 0C;
      DirectionChar := ' ';
      ErrorMsg[0] := 0C;
      ProcInit := TRUE;
      GotMode := FALSE;
      GotDir := FALSE;
      WHILE ProcInit DO
         WHILE (InputString[InputPosition] = ' ') DO INC(InputPosition) END;
         IF (InputString[InputPosition] = 0C) OR
         (InputString[InputPosition] = CommentChar) THEN
            ActualLength := 0;
            LengthGiven := FALSE;
            RETURN EndOfData;
         ELSIF (InputString[InputPosition] = '*') OR
         ((InputString[InputPosition] >= '0') AND
         (InputString[InputPosition] <= '9')) THEN
            IF GotMode THEN
(*RES OLD MSG 224
A Second MODE Character "%0" was Given.
*)
               MsgString(InputString[InputPosition],0);
               GetResMessage( (*RES REM INS*) 224 , ErrorMsg);
               RETURN ErrorOccurred
            END;
            GivenMode := InputString[InputPosition];
            INC(InputPosition);
            GotMode := TRUE;
         ELSIF (InputString[InputPosition] = '<') OR
         (InputString[InputPosition] = '>') THEN
            IF GotDir THEN
(*RES OLD MSG 210
You Gave the Second Direction Character: "%0".
*)
               MsgString(InputString[InputPosition],0);
               GetResMessage( (*RES REM INS*) 210 , ErrorMsg);
               RETURN ErrorOccurred
            END;
            DirectionChar := InputString[InputPosition];
            INC(InputPosition);
            GotDir := TRUE;
         ELSIF (InputString[InputPosition] = '~') THEN
            DirectionChar := '~';
            INC(InputPosition);
            ActualLength := 0;
            LengthGiven := FALSE;
            RETURN OK;
         ELSE ProcInit := FALSE;
         END;
      END;

      Delim := InputString[InputPosition]; 
      StartItem := InputPosition+1; 
      INC(InputPosition);
      ItemLength := 0;
      WHILE (InputString[InputPosition] <> 0C)
      AND (InputString[InputPosition] <> Delim) DO
         TempItem[ItemLength] := InputString[InputPosition];
         INC(InputPosition);
         INC(ItemLength);
      END;
      TempItem[ItemLength] := 0C;
(*RES OLD MSG 27
Delimiter "%0" is Missing.
*)
      IF InputString[InputPosition] = 0C THEN
          MsgString(Delim,0);
          GetResMessage( (*RES REM INS*) 27, ErrorMsg);
          RETURN ErrorOccurred; 
      END;
(*    ItemLength := InputPosition-StartItem; *)
      (* Now, collect actual length, if given *) 
      IF (InputString[InputPosition] <> 0C) AND
      (InputString[InputPosition+1] >= '0') AND
      (InputString[InputPosition+1] <= '9') THEN 
         LengthGiven := TRUE; 
         StartItem := InputPosition+1;
         ActualLength := 0;
         INC(InputPosition,1);
         REPEAT
             ActualLength := ActualLength*10 +
                   (ORD(InputString[InputPosition]) - ORD('0'));
             INC(InputPosition,1)
         UNTIL (InputString[InputPosition] < '0') OR
         (InputString[InputPosition] > '9'); 
         InputPosition := InputPosition - 1;

(*RES OLD MSG 28
Length of %0 is Too Large.
*)
         IF ActualLength > MaxCharsInSeq THEN 
             MsgCard(ActualLength,0);
             GetResMessage((*RES REM INS*) 28, ErrorMsg);
             ActualLength := 0; 
             LengthGiven := FALSE; 
             RETURN ErrorOccurred;
         END;
         LengthGiven := TRUE
      ELSE 
         ActualLength := 0; 
         LengthGiven := FALSE; 
      END;
      INC(InputPosition, 1); 
      Str.Copy(Result, TempItem);
(*    if trace then writeln(trcfle,' Trace GetItem (end):',TempItem); *) 
      RETURN OK;
      END GetItem;

  PROCEDURE LookupExtendedName(Table:     ARRAY OF CharacterEntry;
                               TmpName:   ARRAY OF CHAR;
                           VAR ExtOn:     BOOLEAN;
                           VAR Code:      CHAR): BOOLEAN;

    VAR 
      l:    INTEGER;
      u:    INTEGER;
      i:    INTEGER;
      compr:INTEGER;

  BEGIN 
    l := 0; 
    u := HIGH(Table); 
    REPEAT
      IF u < l THEN 
          ExtOn := FALSE;
          Code := 0C;
          RETURN FALSE;
          END;
      i := (l+u) DIV 2; 
      compr := Str.Compare(TmpName, Table[i].Name);
      IF compr < 0 THEN u := i-1
      ELSIF compr > 0 THEN l := i+1
      END;
    UNTIL compr = 0;
(*  if trace then
        WriteLn(TrcFle,'    LookupExtendedName: ',SortedCharNames[i].CodePoint); *) 
    ExtOn := Table[i].Ext;
    Code := Table[i].Cde;
    RETURN TRUE
  END  LookupExtendedName;

  PROCEDURE LookupIntName(TmpName: ARRAY OF CHAR;
                          VAR OK: BOOLEAN): CHAR; 

    VAR 
      l:    CARDINAL;
      u:    CARDINAL;
      i:    CARDINAL;
      compr:INTEGER;

  BEGIN 
    OK := TRUE; 
    l := 1; 
    u := NumberChars; 
    REPEAT
      IF u < l THEN 
          OK := FALSE; 
          RETURN 0C;
          END;
      i := (l+u) DIV 2; 
      compr := Str.Compare(TmpName, SortedCharNames[i].CanonicName);
      IF compr < 0 THEN u := i-1
      ELSIF compr > 0 THEN l := i+1
      END;
    UNTIL compr = 0;
(*  if trace then
        WriteLn(TrcFle,'    LookupIntName: ',SortedCharNames[i].CodePoint); *) 
    RETURN SortedCharNames[i].CodePoint
  END LookupIntName;  

PROCEDURE GetName(WorkItem:   ARRAY OF CHAR;
                  DeviceId:   ARRAY OF CHAR;
                  VAR ItemPos:    CARDINAL;
                  VAR Result:  ARRAY OF CHAR;
                  VAR ErrorMsg: ARRAY OF CHAR): CompletionCondition;
VAR
   MaxLen:        CARDINAL;
   i:             CARDINAL;
   EPos:          CARDINAL;
BEGIN
   Result[0] := 0C;
   ErrorMsg[0] := 0C;
   MaxLen := HIGH(Result);

   WHILE(WorkItem[ItemPos] <> 0C) AND (WorkItem[ItemPos] = ' ') DO;
        INC(ItemPos,1);  END;
   IF WorkItem[ItemPos] = 0C THEN
        RETURN EndOfData
   END;
   
   i := 0;
   WHILE (WorkItem[ItemPos] <> ' ') AND (WorkItem[ItemPos] <> 0C) AND
   (i <= MaxLen) DO 
      Result[i] := WorkItem[ItemPos];
      INC(i);
      INC(ItemPos);
   END;
   IF i <= MaxLen THEN 
      Result[i] := 0C;
   ELSE
(*RES OLD MSG 29
Character Name "%0" is Too Long in %1 Specification.
*)
      MsgString(WorkItem, 0);
      MsgString(DeviceId,0);
      GetResMessage((*RES REM INS*) 29,ErrorMsg);
      RETURN ErrorOccurred;
   END;
   RETURN OK;
END GetName;

PROCEDURE IntToSeq(InputItem:  ARRAY OF CHAR;
                   VAR Result:     ARRAY OF CHAR;
                   VAR ErrorMsg:   ARRAY OF CHAR): BOOLEAN;

      VAR 
        ItemPos:        CARDINAL;
        WorkName:       InputStringType;
        ResPos:         CARDINAL;
        C:              CHAR; 
        StillOK:        BOOLEAN;
        EPos:           CARDINAL;
        Status:         CompletionCondition;
        TmpCharName:    ARRAY[0..CharNameLength] OF CHAR;

BEGIN
      Result[0] := 0C;
      ErrorMsg[0] := 0C;
      ItemPos := 0;
(*    if trace then
      WriteLn(TrcFle,'  Trace for IntToSeq:',
                     ' WorkItem:',WorkItem,', Length:',ItemLength); *)
      ResPos := 0;

      Status := GetName(InputItem,INTERNALText,ItemPos,WorkName,ErrorMsg);
      WHILE Status = OK DO
         StandardizeCharName(WorkName,TmpCharName);
         IF ResPos > HIGH(Result) THEN 

(*RES OLD MSG 30
There are Too Many Characters.
*)
             GetResMessage( (*RES REM INS*) 30, ErrorMsg);
             RETURN FALSE;
             END;
         C := LookupIntName(TmpCharName, StillOK); 
         IF  NOT StillOK THEN 

(*RES OLD MSG 31
Internal Character Name "%0" is not Recognized.
*)
             MsgString( WorkName, 0);
             GetResMessage( (*RES REM INS*) 31, ErrorMsg);
             RETURN FALSE;
         END;
         Result[ResPos] := C;
         INC(ResPos);
         Status := GetName(InputItem,INTERNALText,ItemPos,WorkName,ErrorMsg);
      END;
      IF ResPos <= HIGH(Result) THEN 
         Result[ResPos] := 0C
      END;
      IF Status = ErrorOccurred THEN RETURN FALSE END;
      RETURN TRUE;
   END IntToSeq;

PROCEDURE PrivExtToSeq(InputItem:  ARRAY OF CHAR;
                       DeviceName: ARRAY OF CHAR;
                   VAR Result:     ARRAY OF CHAR;
                   VAR ErrorMsg:   ARRAY OF CHAR): CompletionCondition;

      VAR 
        ItemPos:        CARDINAL;
        WorkName:       InputStringType;
        ResPos:         CARDINAL;
        C,C1:           CHAR; 
        ExtOn:          BOOLEAN;
        EPos:           CARDINAL;
        Status:         CompletionCondition;
        TmpCharName:    ARRAY[0..CharNameLength] OF CHAR;
        compr:          INTEGER;

PROCEDURE HandleSubOp(Type:  ARRAY OF CHAR;
                      Table: ARRAY OF CharacterEntry): CompletionCondition;
VAR
      Status:         CompletionCondition;
      TmpCharName:    ARRAY[0..CharNameLength] OF CHAR;
BEGIN
      ExtOn := FALSE;
      C := 0C;
      Status := GetName(InputItem,DeviceName,ItemPos,WorkName,ErrorMsg);
      IF Status = EndOfData THEN

(*RES OLD MSG 32
This String Ended Unexpected after "%0" for Device %1.
*)
           MsgString( Type, 0); 
           MsgString( DeviceName, 0);
           GetResMessage( (*RES REM INS*) 32, ErrorMsg);
           RETURN ErrorOccurred;
      END;
      UpcaseStr(WorkName,TmpCharName);
      IF (NOT LookupExtendedName(Table,TmpCharName,ExtOn,C)) THEN

(*RES OLD MSG 33
Character Name "%0" %1 is not Recognized for Device %2.
*)
           MsgString( Type, 0); 
           MsgString( WorkName, 0);
           MsgString( DeviceName, 0);
           GetResMessage( (*RES REM INS*) 33, ErrorMsg);
           RETURN ErrorOccurred;
      END;
   RETURN OK;
END HandleSubOp;

PROCEDURE LookupHexCode(TmpName: ARRAY OF CHAR; 
                    VAR C: CHAR): BOOLEAN; 

  VAR
      i,Rslt,Base:    CARDINAL;

BEGIN 
    IF Str.Length(TmpName) <> 2 THEN
      C := 0C;
      RETURN FALSE
    END;
    Rslt := 0;
    FOR i := 0 TO 1 DO
       IF (TmpName[i] >= '0') AND (TmpName[i] <= '9') THEN
          Base := ORD('0')
       ELSIF (TmpName[i] >= 'A') AND (TmpName[i] <= 'F') THEN
          Base := ORD('A') - 10
       ELSE
          C := 0C;
          RETURN FALSE
       END;
       Rslt := Rslt*16 + (ORD(TmpName[i]) - Base)
    END;
    C := CHR(Rslt);
    RETURN TRUE
END LookupHexCode;


BEGIN
      Result[0] := 0C;
      ErrorMsg[0] := 0C;
      ItemPos := 0;
(*    if trace then
      WriteLn(TrcFle,'  Trace for PrivExtToSeq:',
                     ' WorkItem:',WorkItem,', Length:',ItemLength); *)
      ResPos := 0;

      Status := GetName(InputItem,DeviceName,ItemPos,WorkName,ErrorMsg);
      WHILE Status = OK DO
         IF WorkName[1] = 0C THEN
            ExtOn := FALSE;
            C := WorkName[0];
         ELSE
            UpcaseStr(WorkName,TmpCharName);
            IF Str.Compare(TmpCharName,SHIFTText) = 0 THEN
                 IF HandleSubOp(WorkName,KeySHIFTTable.Data) <> OK THEN
                     RETURN ErrorOccurred
                 END
            ELSIF Str.Compare(TmpCharName,ALTText) = 0 THEN
                 IF HandleSubOp(WorkName,KeyALTTable.Data) <> OK THEN
                     RETURN ErrorOccurred
                 END
            ELSIF Str.Compare(TmpCharName,CTRLText) = 0 THEN
                 IF HandleSubOp(WorkName,KeyCTRLTable.Data) <> OK THEN
                     RETURN ErrorOccurred
                 END
            ELSIF LookupExtendedName(KeyBASICTable.Data,TmpCharName,ExtOn,C) THEN
            ELSIF LookupHexCode(TmpCharName,C) THEN
                  ExtOn := FALSE;
                  IF C = 0C THEN

(*RES OLD MSG 34
Code 00 is not Allowed: %0.
*)
                     MsgString(DeviceName, 0);
                     GetResMessage( (*RES REM INS*) 34, ErrorMsg);
                     RETURN ErrorOccurred
                  END
            ELSE
(*RES OLD MSG 35
Character Name "%0" is not Recognized for Device %1.
*)
               MsgString( TmpCharName, 0); 
               MsgString( DeviceName, 0);
               GetResMessage( (*RES REM INS*) 35, ErrorMsg);
               RETURN ErrorOccurred;
            END
         END;
         REPEAT
            IF ExtOn THEN
                C1 := ExtendedFlagChar;
                ExtOn := FALSE
            ELSE
                C1 := C;
                C := 0C;
            END;
            IF ResPos > HIGH(Result) THEN 
                EPos := 0;
(*RES OLD MSG 36
Sequence is Too Long for Device %0.
*)
                MsgString( DeviceName, 0);
                GetResMessage( (*RES REM INS*) 36, ErrorMsg);
                RETURN ErrorOccurred;
                END;
            Result[ResPos] := C1;
            INC(ResPos);
         UNTIL C = 0C;
         Status := GetName(InputItem,DeviceName,ItemPos,WorkName,ErrorMsg);
      END;
      IF ResPos <= HIGH(Result) THEN
         Result[ResPos] := 0C
      END;
      IF Status = ErrorOccurred THEN RETURN ErrorOccurred END;
      RETURN OK;
   END PrivExtToSeq;

PROCEDURE GetSequencesInit;
VAR
   ResC:    ResCollectionType;
   dummy:   BOOLEAN;
BEGIN
(*RES OLD DTA 2
INTERNAL SHIFT ALT CTRL
*)
   GetDataArray( (*RES REM INS*) 2, ResC);

   dummy := GetNextDataArrayStringItem(ResC,INTERNALText);
   dummy := GetNextDataArrayStringItem(ResC,SHIFTText);
   dummy := GetNextDataArrayStringItem(ResC,ALTText);
   dummy := GetNextDataArrayStringItem(ResC,CTRLText);

   ReleaseCollection(ResC);
END GetSequencesInit;

PROCEDURE ExtToSeq(InputItem:      ARRAY OF CHAR;
                   DeviceName:     ARRAY OF CHAR;
                   VAR Result:     ARRAY OF CHAR;
                   VAR ErrorMsg:   ARRAY OF CHAR): BOOLEAN;
BEGIN
   IF FirstCall THEN
      FirstCall := FALSE;
      GetSequencesInit
   END;
   RETURN OK = PrivExtToSeq(InputItem,DeviceName,Result,ErrorMsg);
END ExtToSeq;

PROCEDURE Line2Sequences(InputLine:         ARRAY OF CHAR;
                     VAR BlankLine:         BOOLEAN;
                     VAR IntSeq:            ARRAY OF CHAR;
                     VAR ExtSeqs:           ARRAY OF XlateFieldData;
                     VAR ErrorMsg:          ARRAY OF CHAR):BOOLEAN;
VAR
      TActLen:   CARDINAL;
      LenGiv:    BOOLEAN;
      Status:    CompletionCondition;
      EPos:      CARDINAL;
      TString:   StrAny;
      NSeq:      CARDINAL;
      HActLen:   CARDINAL;
      HSqn:      SequenceType;
      TDir:      CHAR;
      TMode:     CHAR;

BEGIN
   IF FirstCall THEN
      FirstCall := FALSE;
      GetSequencesInit
   END;

   BlankLine := FALSE;
   Str.Copy(InputString, InputLine);
   InputPosition := 0;
   Status := GetItem(TActLen, LenGiv, TString, TDir, TMode, ErrorMsg);
   IF (Status <> OK) THEN
      IF (Status = EndOfData) THEN
         BlankLine := TRUE;
         RETURN TRUE
      END;
      RETURN FALSE
   END;
   IF TMode <> ' ' THEN
(*RES OLD MSG 225
Please don not Use the Mode Character "%0" in front of Internal String.
*)
      MsgString(TMode,0);
      GetResMessage( (*RES REM INS*) 225 , ErrorMsg);
      RETURN FALSE
   ELSIF TDir = '~' THEN
(*RES OLD MSG 211
The Unspecified Character Indicator "~" cannot be Used for an Internal String.
*)
      GetResMessage( (*RES REM INS*) 211 , ErrorMsg);
      RETURN FALSE
   ELSIF TDir <> ' ' THEN
(*RES OLD MSG 212
The Direction Character "%0" cannot Appear in front of Internal String.
*)
      MsgString(TDir,0);
      GetResMessage( (*RES REM INS*) 212 , ErrorMsg);
      RETURN FALSE
   ELSIF LenGiv THEN

(*RES OLD MSG 37
This Length Field is not Permitted with this Internal String.
*)
      GetResMessage( (*RES REM INS*) 37, ErrorMsg);
      RETURN FALSE
   ELSIF NOT IntToSeq(TString, IntSeq, ErrorMsg) THEN
      RETURN FALSE
   END;

   FOR NSeq := 0 TO HIGH(ExtSeqs) DO
      IF Status = OK THEN
         Status := GetItem(TActLen, LenGiv, TString, TDir, TMode, ErrorMsg);
         IF (NOT ExtSeqs[NSeq].LenOK) AND LenGiv THEN
             EPos := 0;
(*RES OLD MSG 38
This Field Length is not Permitted for %0.
*)
             MsgString( ExtSeqs[NSeq].DevName, 0);
             GetResMessage( (*RES REM INS*) 38, ErrorMsg);
             RETURN FALSE
         END;
         IF (Status = OK) OR (NSeq = 0) THEN
            Status := PrivExtToSeq(TString,ExtSeqs[NSeq].DevName,HSqn,ErrorMsg);
            IF LenGiv THEN
                HActLen := TActLen;
            ELSE 
                HActLen := Str.Length(HSqn);
            END;
         END;
      END;
      IF (Status = ErrorOccurred) THEN
         RETURN FALSE
      END;
      IF TMode = ' ' THEN TMode := '0' END;
      WITH ExtSeqs[NSeq] DO
         Str.Copy(Sqn, HSqn);
         ActLen := HActLen;
         Dir := TDir;
         Mode := TMode;
      END;
   END;
   WHILE (InputString[InputPosition] = ' ') DO
     INC(InputPosition, 1)
   END;
   IF (InputString[InputPosition] <> 0C) AND
   (InputString[InputPosition] <> CommentChar) THEN
(*RES OLD MSG 39
Extra Text has been Found on Xlation File Line.
*)
      GetResMessage( (*RES REM INS*) 39, ErrorMsg);
      RETURN FALSE
   END;
   ErrorMsg[0] := 0C;
   RETURN TRUE;
END Line2Sequences;

BEGIN
   FirstCall := TRUE;
END GetSequences .
