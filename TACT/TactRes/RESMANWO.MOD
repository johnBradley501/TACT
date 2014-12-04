IMPLEMENTATION MODULE ResManWork;

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

FROM SYSTEM IMPORT ADR, TSIZE;
IMPORT ASCII;
IMPORT Str;
IMPORT Lib;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteChar;
FROM Storage IMPORT ALLOCATE,DEALLOCATE;
FROM FileIO IMPORT FilePos;
FROM ResComments IMPORT FindNextThing;
FROM WResCollection IMPORT
   (* proc *) AppendNewItem, WriteResCollection;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) InitializeCollection, GetCollection,
              NextColItem, PrevColItem, ReleaseCollection;
FROM ResManUtils IMPORT
  (* proc *) InputErrorMessage, ResErrorMessage, ReportError,
             NextResLine,
             FindResType;
FROM ResTranslations IMPORT CurrentModeType, XlateLine, File2Int;
FROM ResHelp IMPORT
  (* const *) MaxHelpRefs,
  (* types *) HelpData, HelpRef, HelpRefColl;

FROM WResBase IMPORT
  (* proc *)   AppendResourceBase,AppendResRecord,AppendResString;

CONST
   MaxNumberArraySize = 8096; (* words *)


PROCEDURE HandleNewMessage(VAR DataArea: FilePos);
VAR
    Data:    POINTER TO ARRAY[0..2048] OF CHAR;
    Len:     CARDINAL;
    TLen:    CARDINAL;
    Input:   ARRAY[0..255] OF CHAR;
    Temp:    ARRAY[0..255] OF CHAR;
    IStrt:   CARDINAL;
    cm:      CurrentModeType;
BEGIN
    cm.ModeIn := '0'; cm.ModeOut := '0';
    ALLOCATE(Data,2048);
    Len := 0;
    WHILE NextResLine(Input) DO
       XlateLine(File2Int, '?', Input, cm, Temp);
       IStrt := 0;
       WHILE (Temp[IStrt] = ' ') DO INC(IStrt) END;
       TLen := Str.Length(Temp) - IStrt;
       IF TLen > 0 THEN
          IF Len <> 0 THEN
             Data^[Len] := ' ';
             INC(Len)
          END;
          Lib.Move(ADR(Temp[IStrt]),ADR(Data^[Len]),TLen);
          Len := Len + TLen
       END;
    END;
    Data^[Len] := 0C;
    IF Len = 0 THEN
       ReportError('No Text for Message Found')
    ELSE
       IF NOT AppendResString(Data^,DataArea) THEN
           ResErrorMessage('In HandleNewMessage')
       END
    END;
    DEALLOCATE(Data,2048)
END HandleNewMessage;

PROCEDURE HandlePanelDef(VAR Pos: FilePos);
  CONST
    NoScreenLines = 25;
    NoCharPositions = 80;
    FieldChar = '_';
    MarkerChar = '%';
    NoBlanksSep = 4;


  TYPE
(*  FieldName = ARRAY [0..MaxFieldNameLen-1] OF CHAR;   *)
    StringType = ARRAY [0..255] OF CHAR;
    TextStringType = ARRAY [0..NoCharPositions-1] OF CHAR;
    TextEntryPointer = POINTER TO TextEntryType;
    TextEntryType = RECORD
                      XPos: CHAR;   (* used as 1 byte binary number *)
                      YPos: CHAR;   (* used as 1 byte binary number *)
                      Text: TextStringType;
                      Next: TextEntryPointer;
                    END;

    FieldEntryPointer = POINTER TO FieldEntryType;
    FieldEntryType = RECORD
                       ID: CHAR;    (* used as 1 byte binary number *)
                       XPos: CHAR;  (* used as 1 byte binary number *)
                       YPos: CHAR;  (* used as 1 byte binary number *)
                       Len:  CHAR;  (* used as 1 byte binary number *)
                       Next: FieldEntryPointer;
                     END;
    ProcState = (Base, ReadText, TextBlanks, ReadField);

    VAR
      InputString:    StringType;
      InputLength:    CARDINAL;
      Line:           CARDINAL;
      Position:       CARDINAL;
      StartField:     CARDINAL;
      EndField:       CARDINAL;
      StartText:      CARDINAL;
      EndText:        CARDINAL;
      NoBlanks:       CARDINAL;
      State:          ProcState;
      Loop:           BOOLEAN;
      PanelLines:     CARDINAL;
      TextEntry:      TextEntryPointer;
      FieldEntry:     FieldEntryPointer;
      TextEntryList:  TextEntryPointer;
      FieldEntryList: FieldEntryPointer;

    PROCEDURE AllocTextData(Start, Fin: CARDINAL);
    VAR
        ExtText: ARRAY[0..255] OF CHAR;
        cm:      CurrentModeType;
        Len: CARDINAL;
        TextPos: CARDINAL;
        NewTextEntry: TextEntryPointer;

    BEGIN
      Len := Fin-Start+1;
      IF Len > NoCharPositions THEN
         ReportError(' Text Length is too long')
      ELSIF (Start <= NoCharPositions) AND (Fin <= NoCharPositions) AND 
        ((Line = 99) OR (Line <= NoScreenLines)) THEN
        NEW(NewTextEntry);
        WITH NewTextEntry^ DO
          Str.Slice(ExtText,InputString, Start, Len);
          cm.ModeIn := '0'; cm.ModeOut := '0';
          XlateLine(File2Int, '?', ExtText, cm, Text);
          XPos := CHR(Start);
          YPos := CHR(Line);
          Next := NIL;
        END;
        TextEntry^.Next := NewTextEntry;
        TextEntry := NewTextEntry;
      ELSE
        ReportError('Text Ignored, Out of Bounds')
      END;
    END AllocTextData;


    PROCEDURE AllocFieldData(Start, Fin: CARDINAL);
      VAR
        Lngth:         CARDINAL;
        P:             CARDINAL;
        PosEnd:        CARDINAL;
        NewFieldEntry: FieldEntryPointer;
        ColID:         CARDINAL;
        i,j:           CARDINAL;
        EPos:          CARDINAL;
        EMsg:          ARRAY[0..80] OF CHAR;

    BEGIN
      Lngth := Fin-Start+1;

      ColID := 0;
      PosEnd := 0;
      FOR i := Start+1 TO Fin DO
         IF (InputString[i] >= '0') AND (InputString[i] <= '9') THEN
            ColID := ColID*10 + ORD(InputString[i]) - ORD('0')
         ELSIF InputString[i] = '|' THEN
            IF PosEnd = 0 THEN PosEnd := i
            ELSE
               EPos := 0;
               SWriteString(EMsg,EPos,'Second "|" Found, position: ',0);
               SWriteCard(EMsg,EPos,i,0);
               ReportError(EMsg);
            END
         END;
      END;

      IF PosEnd <> 0 THEN Lngth := Fin-PosEnd END;

      NEW(NewFieldEntry);
      WITH NewFieldEntry^ DO
          ID := CHR(ColID);
          XPos := CHR(Start);
          YPos := CHR(Line);
          Len := CHR(Lngth);
          Next := NIL;
      END;
      FieldEntry^.Next := NewFieldEntry;
      FieldEntry := NewFieldEntry;
    END AllocFieldData;

PROCEDURE PrepareResCollection;
VAR
    tempt:      TextEntryPointer;
    tempt2:     TextEntryPointer;
    tempf:      FieldEntryPointer;
    ResC:       ResCollectionType;
    tlen:       CARDINAL;
BEGIN
    InitializeCollection(ResC);
    AppendNewItem(ResC,PanelLines,0);
    tempt2 := TextEntryList;
    TextEntryList := TextEntryList^.Next;
    WHILE TextEntryList <> NIL DO
       tlen := Str.Length(TextEntryList^.Text);
       IF tlen = NoCharPositions THEN tlen := tlen + 2
                                 ELSE tlen := tlen + 3 END;
       AppendNewItem(ResC,TextEntryList^,tlen);
       tempt := TextEntryList;
       TextEntryList := TextEntryList^.Next;
       DISPOSE(tempt);
    END;
    tempt2^.Text := 0C;
    AppendNewItem(ResC,tempt2^,3);
    DISPOSE(tempt2);

    tempf := FieldEntryList;
    FieldEntryList := FieldEntryList^.Next;
    DISPOSE(tempf);
    WHILE FieldEntryList <> NIL DO
       AppendNewItem(ResC,FieldEntryList^,4);
       tempf := FieldEntryList;
       FieldEntryList := FieldEntryList^.Next;
       DISPOSE(tempf);
    END;
    IF NOT WriteResCollection(ResC,Pos) THEN
       ResErrorMessage('Doing WriteResCollection')
    END;
END PrepareResCollection;

PROCEDURE BeginningField(VAR Str:    ARRAY OF CHAR;
                         Ptr:        CARDINAL): BOOLEAN;
BEGIN
   RETURN (Str[Ptr] = MarkerChar) AND (((Str[Ptr+1] >= '0') AND
          (Str[Ptr+1] <= '9')) OR (Str[Ptr+1] = '|'));
END BeginningField;

  BEGIN
    NEW(TextEntryList);
    TextEntry := TextEntryList;
    TextEntry^.Next := NIL;
    NEW(FieldEntryList);
    FieldEntry := FieldEntryList;
    FieldEntry^.Next := NIL;
    Line := 0;
    Loop := TRUE;
    WHILE NextResLine(InputString) DO
        IF Line = NoScreenLines-1 THEN
          ReportError('Too Many lines in Panel Def')
        END;
        InputLength := Str.Length(InputString);
        IF InputLength > NoCharPositions THEN
          ReportError('Line Too Long for String')
        END;
        State := Base;
        InputString[InputLength] := ' ';
        InputString[InputLength+1] := 0C;
        INC(InputLength);

        FOR Position := 0 TO InputLength-1 DO
          CASE State OF
              Base:
              IF BeginningField(InputString,Position) THEN
                StartField := Position;
                State := ReadField;
              ELSIF InputString[Position] <> ' ' THEN
                StartText := Position;
                State := ReadText;
              END
            | ReadText:
              IF InputString[Position] = ' ' THEN
                EndText := Position-1;
                NoBlanks := 1;
                State := TextBlanks;
              ELSIF BeginningField(InputString,Position) THEN
                EndText := Position-1;
                AllocTextData(StartText, EndText);
                StartField := Position;
                State := ReadField;
              END
            | TextBlanks:
              IF InputString[Position] = ' ' THEN
                NoBlanks := NoBlanks+1;
                IF NoBlanks > NoBlanksSep THEN
                  AllocTextData(StartText, EndText);
                  State := Base;
                END;
              ELSIF BeginningField(InputString,Position) THEN
                AllocTextData(StartText, EndText);
                StartField := Position;
                State := ReadField;
              ELSE
                State := ReadText
              END;
            | ReadField:
              IF ((InputString[Position] < '0') OR
              (InputString[Position] > '9')) AND
              (InputString[Position] <> FieldChar) AND
              (InputString[Position] <> '|')
              THEN
                AllocFieldData(StartField, Position-1);
                IF InputString[Position] = ' ' THEN State := Base
                ELSIF BeginningField(InputString,Position) THEN
                    StartField := Position;
                ELSE
                    StartText := Position;
                    State := ReadText;
                END
              END;
            ELSE
          END;
        END;
        IF State = TextBlanks THEN
          AllocTextData(StartText, EndText)
        END;
        INC(Line)
    END;
    PanelLines := Line - 1;
    PrepareResCollection;
  END HandlePanelDef;

PROCEDURE HandleNewChoice(VAR DataArea: FilePos);
VAR
    Data:     POINTER TO ARRAY[0..2048] OF CHAR;
    Len:      CARDINAL;
    TLen:     CARDINAL;
    Temp:     ARRAY[0..255] OF CHAR;
    AnswC:    ARRAY[0..255] OF CHAR;
    i:        CARDINAL;
    FoundAns: BOOLEAN;
    FoundTxt: BOOLEAN;
    ALen:     CARDINAL;
    IStrt:    CARDINAL;
    cm:       CurrentModeType;
    Input:    ARRAY[0..255] OF CHAR;
BEGIN
    cm.ModeIn := '0'; cm.ModeOut := '0';
    ALLOCATE(Data,2048);
    Len := 0;
    FoundAns := FALSE;
    FoundTxt := FALSE;
    ALen := 0;
    WHILE NextResLine(Input) DO
       XlateLine(File2Int, '?', Input, cm, Temp);
       IStrt := 0;
       WHILE (Temp[IStrt] = ' ') DO INC(IStrt) END;
       IF Temp[IStrt] = 0C THEN
          (* No nothing but get the next line *)
       ELSIF Temp[IStrt] = '=' THEN
          i := IStrt+1;
          WHILE Temp[i] <> 0C DO
             IF Temp[i] <> ' ' THEN
                AnswC[ALen] := Temp[i];
                INC(ALen)
             END;
             INC(i)
          END;
          FoundAns := TRUE;
       ELSE
          FoundTxt := TRUE;
          TLen := Str.Length(Temp) - IStrt;
          IF TLen > 0 THEN
             IF Len <> 0 THEN
                Data^[Len] := ' ';
                INC(Len)
             END;
             Lib.Move(ADR(Temp[IStrt]),ADR(Data^[Len]),TLen);
             Len := Len + TLen
          END;
       END;
    END;
    AnswC[ALen] := 0C;
    Data^[Len] := 0C;
    IF NOT FoundAns THEN
       ReportError('No Answer Character List Found')
    ELSIF NOT FoundTxt THEN
       ReportError('No Text for Choice Message Found')
    ELSE
       INC(Len);
       Lib.Move(ADR(AnswC),ADR(Data^[Len]),ALen+1);
       Len := Len + ALen+1;
       IF NOT AppendResourceBase(Len,DataArea,Data) THEN
           ResErrorMessage('In HandleNewChoice')
       END;
    END;
    DEALLOCATE(Data,2048)
END HandleNewChoice;

PROCEDURE HandleNewDataArray(VAR Pos: FilePos);
VAR
    ResC:       ResCollectionType;
    Input:      ARRAY[0..255] OF CHAR;
    Line:       ARRAY[0..255] OF CHAR;
    RestLine:   ARRAY[0..255] OF CHAR;
    Word:       ARRAY[0..255] OF CHAR;
    CodedText:  ARRAY[0..255] OF CHAR;
    BfWord:     ARRAY[0..20] OF CHAR;
    len:        CARDINAL;
    cm:         CurrentModeType;

PROCEDURE CodeItem(UnCd:  ARRAY OF CHAR;
               VAR Cd:    ARRAY OF CHAR;
               VAR len:   CARDINAL);
TYPE
   CodingState = (TextChar,Hex1,Hex2);
VAR
   i,j:   CARDINAL;
   CState: CodingState;
   hex1:  CARDINAL;
BEGIN
   CState := TextChar;
   i := 0; j := 0;
   WHILE UnCd[i] <> 0C DO
      CASE CState OF
        TextChar:
            IF UnCd[i] = '!' THEN
               CState := Hex1
            ELSE
               Cd[j] := UnCd[i];
               INC(j)
            END
      | Hex1:
            IF UnCd[i] = '!' THEN
               CState := TextChar
            ELSE
               CState := Hex2;
               UnCd[i] := CAP(UnCd[i]);
               IF (UnCd[i] >= '0') AND (UnCd[i] <= '9') THEN
                   hex1 := ORD(UnCd[i]) - ORD('0')
               ELSIF (UnCd[i] >= 'A') AND (UnCd[i] <= 'F') THEN
                   hex1 := ORD(UnCd[i]) - ORD('A') + 10
               ELSE
                   ReportError('Illegal HEX character found')
               END
            END
      | Hex2:
            UnCd[i] := CAP(UnCd[i]);
            IF (UnCd[i] >= '0') AND (UnCd[i] <= '9') THEN
                Cd[j] := CHR(hex1*16 + ORD(UnCd[i]) - ORD('0'))
            ELSIF (UnCd[i] >= 'A') AND (UnCd[i] <= 'F') THEN
                Cd[j] := CHR(hex1*16 + ORD(UnCd[i]) - ORD('A') + 10)
            ELSE
                ReportError('Illegal HEX character found')
            END;
            INC(j);
            CState := Hex1
      END;
      INC(i);
   END;
   len := j
END CodeItem;

PROCEDURE GetString(Line:      ARRAY OF CHAR;
                VAR CodedText: ARRAY OF CHAR;
                VAR RestLine:  ARRAY OF CHAR;
                VAR len:       CARDINAL);

VAR i,j:        CARDINAL;
    CloseQuote: CHAR;
BEGIN
   i := 0;
   WHILE (Line[i] = ' ') OR (Line[i] = ASCII.ht) DO INC(i) END;
   CloseQuote := Line[i];
   INC(i);

   j := 0;
   WHILE (i <= HIGH(Line)) AND (j <= HIGH(CodedText)) AND
   (Line[i] <> 0C) AND (Line[i] <> CloseQuote) DO
      CodedText[j] := Line[i];
      INC(i);
      INC(j);
   END;
   IF j <= HIGH(CodedText) THEN CodedText[j] := 0C END;
   len := j;
   IF Line[i] = CloseQuote THEN INC(i) END;

   j := 0;
   WHILE (i <= HIGH(Line)) AND (j <= HIGH(RestLine)) AND
   (Line[i] <> 0C) DO
      RestLine[j] := Line[i];
      INC(i);
      INC(j);
   END;
   IF j <= HIGH(RestLine) THEN RestLine[j] := 0C END;
END GetString;

BEGIN
    InitializeCollection(ResC);
    cm.ModeIn := '0'; cm.ModeOut := '0';
    WHILE NextResLine(Input) DO
       XlateLine(File2Int, '?', Input, cm, Line);
       WHILE FindNextThing(Line,Word,BfWord,RestLine) DO
           IF (Word[0] = "'") OR (Word[0] = '"') THEN
               GetString(Line,CodedText,RestLine,len)
           ELSE
               CodeItem(Word,CodedText,len)
           END;
           AppendNewItem(ResC,CodedText,len);
           Str.Copy(Line,RestLine)
       END;
    END;
    IF NOT WriteResCollection(ResC,Pos) THEN
       ResErrorMessage('Doing WriteResCollection')
    END;
END HandleNewDataArray;

PROCEDURE HandleNewNumberArray(VAR DataArea: FilePos);
VAR
   NumberStore: POINTER TO ARRAY[0..MaxNumberArraySize-1] OF CARDINAL;
   CurNum:      CARDINAL;
   Line:        ARRAY[0..255] OF CHAR;
   RestLine:    ARRAY[0..255] OF CHAR;
   Word:        ARRAY[0..255] OF CHAR;
   BfWord:      ARRAY[0..20] OF CHAR;
   done:        BOOLEAN;
BEGIN
   NEW(NumberStore);
   CurNum := 0;
   WHILE NextResLine(Line) DO
      WHILE FindNextThing(Line,Word,BfWord,RestLine) DO
         IF CurNum >= MaxNumberArraySize THEN
            ReportError('Too many numbers in Number Array');
            RETURN
         END;
         NumberStore^[CurNum] := CARDINAL(Str.StrToCard(Word,10,done));
         IF NOT done THEN
            ReportError('Something that is not a CARDINAL number found');
            RETURN
         END;
         INC(CurNum);
         Str.Copy(Line,RestLine)
      END;
   END;
   IF CurNum = 0 THEN
      ReportError('No Numbers found in Number Array');
      RETURN
   END;
   IF NOT AppendResourceBase(CurNum*2,DataArea,NumberStore) THEN
      ResErrorMessage('In HandleNewNumberArray')
   END;
   DISPOSE(NumberStore);
END HandleNewNumberArray;

PROCEDURE HandleNewHelpItem(VAR DataArea: FilePos);

CONST
    HDataItemBaseSize = 2 + 4 + 2; (*SIZE HDataItem.Size,Next and
                                     HDataItem.Data.NumbBlkLines,NumbOfBlanks*)

TYPE
    HDataPntr = POINTER TO HDataItem;
    HDataItem = RECORD
       Next:     HDataPntr;
       Size:     CARDINAL;
       Data:     HelpData;
    END;
VAR
    done:       BOOLEAN;
    Refs:       HelpRefColl;
    HDataList:  HDataPntr;
    HDataEnd:   HDataPntr;
    Temp:       ARRAY[0..255] OF CHAR;
    Input:      ARRAY[0..255] OF CHAR;
    BlankLines: CARDINAL;
    i,j:        CARDINAL;
    TPntr:      POINTER TO ARRAY[0..255] OF CHAR;
    tempItem:   HDataPntr;
    cm:         CurrentModeType;

PROCEDURE PutHelpRes;
VAR
    ResC:       ResCollectionType;
BEGIN
    IF HDataList = NIL THEN
       ReportError('No lines of text found in Help Item')
    END;

    InitializeCollection(ResC);
    AppendNewItem(ResC,Refs,2 (*TSIZE(CARDINAL)*) + Refs.Size*TSIZE(HelpRef));

    WHILE HDataList <> NIL DO
       AppendNewItem(ResC,HDataList^.Data, HDataList^.Size - 5 (* Size, Next *));
       HDataEnd := HDataList;
       HDataList := HDataList^.Next;
       DEALLOCATE(HDataEnd, HDataEnd^.Size);
    END;

    IF NOT WriteResCollection(ResC,DataArea) THEN
       ResErrorMessage('Doing WriteResCollection')
    END;
END PutHelpRes;

BEGIN
    Refs.Size := 0;
    BlankLines := 0;
    HDataList := NIL;
    HDataEnd := NIL;
    cm.ModeIn := '0'; cm.ModeOut := '0';
    WHILE NextResLine(Input) DO
       XlateLine(File2Int, '?', Input, cm, Temp);
       i := Str.Length(Temp);
       WHILE (i <> 0) AND (Temp[i-1] = ' ') DO DEC(i) END;
       Temp[i] := 0C;
       IF Temp[0] = 0C THEN INC(BlankLines)
       ELSIF Temp[0] = '=' THEN
          INC(Refs.Size);
          IF Refs.Size > MaxHelpRefs THEN
             ReportError('Too many Refs in Help Item');
             RETURN
          ELSE
             j := 1;
             WHILE (Temp[j] = ' ') DO INC(j) END;
             WITH Refs.Data[Refs.Size-1] DO
                TypedChar := Temp[j];
                INC(j);
                WHILE (Temp[j] = ' ') DO INC(j) END;
                IF Temp[j] = 0C THEN
                   ReportError('Number missing in Ref in Help Item');
                ELSE
                   TPntr := ADR(Temp[j]);
                   NextID := CARDINAL(Str.StrToCard(TPntr^,10,done));
                   IF NOT done THEN
                      ReportError('Improper number given in Ref in Help Item');
                   END;
                END;
             END;
          END;
       ELSE
          j := 0;
          WHILE (Temp[j] = ' ') DO INC(j) END;
          TPntr := ADR(Temp[j]);
          ALLOCATE(tempItem, HDataItemBaseSize + i - j);
          WITH tempItem^ DO
             Size := HDataItemBaseSize + i - j;
             Next := NIL;
             Data.NumbBlkLines := CHR(BlankLines);
             Data.NumbOfBlanks := CHR(j);
             Str.Copy(Data.Data,TPntr^);
          END;
          IF HDataList = NIL THEN HDataList := tempItem
                             ELSE HDataEnd^.Next := tempItem END;
          HDataEnd := tempItem;
          BlankLines := 0;
       END;
    END;
    PutHelpRes;
END HandleNewHelpItem;

END ResManWork.
