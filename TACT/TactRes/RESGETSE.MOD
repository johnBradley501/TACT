IMPLEMENTATION MODULE ResGetSequences ;

(* copyright (c) 1987-96 John Bradley, University of Toronto *)

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

IMPORT Str, FIO, Lib;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM GlobalDefs IMPORT SequenceType, StrAny, MaxCharsInSeq;
FROM STANDARD   IMPORT 
    NumberChars, CharNameLength, HighCharacterCode, HighLowSize,
    BaseCharData, HighLowSizeType, CharNameType, SortedCharNames,
    CharacterNameSet, UpperCharList, LowerCharList, Initialize;
FROM Utils      IMPORT StandardizeCharName, UpcaseStr;
FROM Utils IMPORT
  (* Vars  *) StandardSearchList,
  (* Procs *) FindFileInList, StandardizeCharName, UpcaseStr;
FROM ExtendedAsciiKeys IMPORT
   MaxKeyNameLen, KeyName, CharacterEntry,
   MaxBASICEntries, KeyBASICTable,
   MaxALTEntries, KeyALTTable,
   MaxSHIFTEntries, KeySHIFTTable,
   MaxCTRLEntries, KeyCTRLTable;
FROM StringIO IMPORT SWriteString, SWriteCard;

    CONST
      INTERNALText = 'INTERNAL';
      SHIFTText = 'SHIFT';
      ALTText = 'ALT';
      CTRLText = 'CTRL';
      ResdataFile = 'RES.DAT';

    TYPE 
      CompletionCondition = (OK, EndOfData, ErrorOccurred);
      InputStringType = ARRAY [0..80] OF CHAR;

    VAR 
      InputRecordNumber:      CARDINAL; 
      InputPosition:          CARDINAL;
      InputString:            InputStringType;

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
               EPos := 0;
               SWriteString(ErrorMsg, EPos, 'A second mode character "',0);
               SWriteString(ErrorMsg, EPos, InputString[InputPosition],0);
               SWriteString(ErrorMsg, EPos, '" was given', 0);
               RETURN ErrorOccurred
            END;
            GivenMode := InputString[InputPosition];
            INC(InputPosition);
            GotMode := TRUE;
         ELSIF (InputString[InputPosition] = '<') OR
         (InputString[InputPosition] = '>') THEN
            IF GotDir THEN
               EPos := 0;
               SWriteString(ErrorMsg, EPos, 'A second direction character "',0);
               SWriteString(ErrorMsg, EPos, InputString[InputPosition],0);
               SWriteString(ErrorMsg, EPos, '" was given', 0);
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
      IF InputString[InputPosition] = 0C THEN
          EPos := 0;
          SWriteString(ErrorMsg, EPos, 'Missing Delimiter "',0);
          SWriteString(ErrorMsg, EPos, Delim, 0);
          SWriteString(ErrorMsg, EPos, '"', 0);
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

         IF ActualLength > MaxCharsInSeq THEN 
             EPos := 0;
             SWriteString(ErrorMsg, EPos, 'Actual Length of ',0);
             SWriteCard(ErrorMsg, EPos, ActualLength, 0);
             SWriteString(ErrorMsg, EPos, ' is too large.',0);
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
      EPos := 0;
      SWriteString(ErrorMsg, EPos, 'Character Name "' ,0);
      SWriteString(ErrorMsg, EPos, WorkItem, 0);
      SWriteString(ErrorMsg, EPos, '" is illegal -- too long in ', 0);
      SWriteString(ErrorMsg, EPos, DeviceId,0);
      SWriteString(ErrorMsg, EPos, ' Spec', 0);
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
             Str.Copy(ErrorMsg, 'Too Many Characters for Internal');
             RETURN FALSE;
             END;
         C := LookupIntName(TmpCharName, StillOK); 
         IF  NOT StillOK THEN 
             EPos := 0;
             SWriteString(ErrorMsg, EPos, 'Internal Character Name "',0);
             SWriteString(ErrorMsg, EPos, WorkName, 0);
             SWriteString(ErrorMsg, EPos, '" is not recognized.',0);
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
           EPos := 0;
           SWriteString(ErrorMsg, EPos, 'Unexpected end of string after "',0);
           SWriteString(ErrorMsg, EPos, Type, 0); 
           SWriteString(ErrorMsg, EPos, '" for Device ',0);
           SWriteString(ErrorMsg, EPos, DeviceName, 0);
           RETURN ErrorOccurred;
      END;
      UpcaseStr(WorkName,TmpCharName);
      IF (NOT LookupExtendedName(Table,TmpCharName,ExtOn,C)) THEN
           EPos := 0;
           SWriteString(ErrorMsg, EPos, 'Character Name "',0);
           SWriteString(ErrorMsg, EPos, Type, 0); 
           SWriteString(ErrorMsg, EPos, '" ', 0);
           SWriteString(ErrorMsg, EPos, WorkName, 0);
           SWriteString(ErrorMsg, EPos, ' is not recognized for Device ',0);
           SWriteString(ErrorMsg, EPos, DeviceName, 0);
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
                     EPos := 0;
                     SWriteString(ErrorMsg, EPos, 'Code 00 is not allowed: ',0);
                     SWriteString(ErrorMsg, EPos, DeviceName, 0);
                     RETURN ErrorOccurred
                  END
            ELSE
               EPos := 0;
               SWriteString(ErrorMsg, EPos, 'Character Name "',0);
               SWriteString(ErrorMsg, EPos, TmpCharName, 0); 
               SWriteString(ErrorMsg, EPos, '" is not recognized for Device ',0);
               SWriteString(ErrorMsg, EPos, DeviceName, 0);
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
                SWriteString(ErrorMsg, EPos, 'Sequence too long for Device ',0);
                SWriteString(ErrorMsg, EPos, DeviceName, 0);
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

PROCEDURE ExtToSeq(InputItem:      ARRAY OF CHAR;
                   DeviceName:     ARRAY OF CHAR;
                   VAR Result:     ARRAY OF CHAR;
                   VAR ErrorMsg:   ARRAY OF CHAR): BOOLEAN;
BEGIN
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
      EPos := 0;
      SWriteString(ErrorMsg, EPos, 'Mode Character "',0);
      SWriteString(ErrorMsg, EPos, TMode,0);
      SWriteString(ErrorMsg, EPos, 
           '" is not allowed in front of INTERNAL string',0);
      RETURN FALSE
   ELSIF TDir = '~' THEN
      Str.Copy(ErrorMsg,'Indicator "~" is not allowed instead of an INTERNAL string');
      RETURN FALSE
   ELSIF TDir <> ' ' THEN
      EPos := 0;
      SWriteString(ErrorMsg, EPos, 'Direction Character "',0);
      SWriteString(ErrorMsg, EPos, TDir,0);
      SWriteString(ErrorMsg, EPos, '" is not allowed in front of INTERNAL string',0);
      RETURN FALSE
   ELSIF LenGiv THEN
      Str.Copy(ErrorMsg,'Actual Length Field not permitted with INTERNAL String');
      RETURN FALSE
   ELSIF NOT IntToSeq(TString, IntSeq, ErrorMsg) THEN
      RETURN FALSE
   END;

   FOR NSeq := 0 TO HIGH(ExtSeqs) DO
      IF Status = OK THEN
         Status := GetItem(TActLen, LenGiv, TString, TDir, TMode, ErrorMsg);
         IF (NOT ExtSeqs[NSeq].LenOK) AND LenGiv THEN
             EPos := 0;
             SWriteString(ErrorMsg, EPos,
               'Actual Length Field not permitted for ',0);
             SWriteString(ErrorMsg, EPos, ExtSeqs[NSeq].DevName, 0);
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
      Str.Copy(ErrorMsg, 'Extra Text found on xlation file line');
      RETURN FALSE
   END;
   ErrorMsg[0] := 0C;
   RETURN TRUE;
END Line2Sequences;

PROCEDURE InitialResGetSequences;
VAR
   FName:       ARRAY[0..55] OF CHAR;
   DirName:     ARRAY[0..40] OF CHAR;
   ErrorMsg:    StrAny;

CONST
   MaxCollectionSize = 32000;
   PrefixLen = 4; (* # of Bytes in MaxSize and CurPos in ResCollectionType *)

TYPE
   DataPointer = POINTER TO ARRAY[0..MaxCollectionSize-1] OF CHAR;
   CollectionType = POINTER TO RECORD
                       MaxSize:  CARDINAL;
                       CurPos:   CARDINAL;
                       Data:     DataPointer;
                       END;

PROCEDURE GetXlationNames(FName: ARRAY OF CHAR);
VAR
   FID:       FIO.File;
   i:         CARDINAL;
   ResC:      CollectionType;
   dummycard: CARDINAL;

PROCEDURE ReadBase(VAR Data:             ADDRESS;
                   VAR NumberGot:        CARDINAL);
VAR
   size:           CARDINAL;
   ngot:           CARDINAL;
BEGIN
   ngot := FIO.RdBin(FID, size, SIZE(size));
   IF Data = NIL THEN ALLOCATE(Data,size) END;
   NumberGot := FIO.RdBin(FID,Data^, size);
END ReadBase;

PROCEDURE GetCollection(VAR ResC: CollectionType);
VAR  size:    CARDINAL;
BEGIN
    NEW(ResC);
    ResC^.MaxSize := 0;
    ResC^.Data := NIL;
    ReadBase(ResC^.Data,ResC^.MaxSize);
    ResC^.CurPos := 0;
END GetCollection;

PROCEDURE ReleaseCollection(VAR ResC: CollectionType);
BEGIN
   DEALLOCATE(ResC^.Data,ResC^.MaxSize);
   DISPOSE(ResC);
   ResC := NIL
END ReleaseCollection;

PROCEDURE NextColItem(VAR ResC: CollectionType;
                      VAR ItemData: ARRAY OF BYTE;
                      VAR Size:   CARDINAL);
VAR   givenlen:    CARDINAL;
      sentlen:     CARDINAL;
      datap:       POINTER TO ARRAY[0..10] OF BYTE;
BEGIN
    WITH ResC^ DO
       IF CurPos >= MaxSize THEN 
          FIO.WrStr(FIO.ErrorOutput,'Error in NextColitem');
          HALT;
       END;
       givenlen := ORD(Data^[CurPos]);
       datap := ADR(Data^[CurPos+1]);
       IF givenlen > HIGH(ItemData) THEN sentlen := HIGH(ItemData)+1
                                    ELSE sentlen := givenlen END;
       Lib.Move( datap, ADR(ItemData), sentlen);
       CurPos := CurPos + givenlen + 2
    END;
    Size := sentlen;
END NextColItem;

PROCEDURE GetNextStringItem(VAR ResC:   CollectionType;
                            VAR Text:   ARRAY OF CHAR);
VAR size:  CARDINAL;
BEGIN 
   NextColItem(ResC,Text,size);
   IF size < HIGH(Text)+1 THEN Text[size] := 0C END;
END GetNextStringItem;

BEGIN
   FID := FIO.Open(FName);

   GetCollection(ResC);
   FOR i := 1 TO NumberChars DO
      NextColItem(ResC,SortedCharNames[i],dummycard)
   END;
   FOR i := 0 TO HighCharacterCode DO
      GetNextStringItem(ResC,CharacterNameSet[i])
   END;
   GetNextStringItem(ResC,UpperCharList);
   GetNextStringItem(ResC,LowerCharList);
   ReleaseCollection(ResC);

   GetCollection(ResC);
   FOR i := 0 TO MaxBASICEntries-1 DO
      NextColItem(ResC,KeyBASICTable.Data[i],dummycard)
   END;
   FOR i := 0 TO MaxALTEntries-1 DO
      NextColItem(ResC,KeyALTTable.Data[i],dummycard)
   END;
   FOR i := 0 TO MaxSHIFTEntries-1 DO
      NextColItem(ResC,KeySHIFTTable.Data[i],dummycard)
   END;
   FOR i := 0 TO MaxCTRLEntries-1 DO
      NextColItem(ResC,KeyCTRLTable.Data[i],dummycard)
   END;
   ReleaseCollection(ResC);

   FIO.Close(FID);
END GetXlationNames;

BEGIN
   IF FindFileInList(StandardSearchList,ResdataFile, DirName) THEN
      Str.Concat(FName, DirName, ResdataFile);
      GetXlationNames(FName);
   ELSE
      FIO.WrStr(FIO.ErrorOutput,'Could not find RES.DAT');
      FIO.WrLn(FIO.ErrorOutput);
      HALT;
   END;
END InitialResGetSequences;

END ResGetSequences .
