IMPLEMENTATION MODULE ResTranslations ;

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

IMPORT Str, FIO;
FROM SYSTEM     IMPORT ADR;
FROM Storage    IMPORT ALLOCATE, DEALLOCATE, Available;
(*<Dbg
FROM Trace      IMPORT TWriteString, TWriteCard, TWriteLn;
Dbg>*)
FROM Utils IMPORT
  (* Vars  *) StandardSearchList,
  (* Procs *) FindFileInList;
FROM StringIO   IMPORT SWriteString,SWriteCard,SWriteInt, SWriteChar;
FROM GlobalDefs IMPORT
  (* Type  *)  StrAny, SequenceType ;
FROM ResGetSequences IMPORT
     InitialResGetSequences, XlateFieldData, Line2Sequences,ExtToSeq;

CONST
    XlateEntryLength = 19; (* wouldn't be necessary is Fitted Software
                              Compiler supported TSIZE *)
    IntEnhOn = 374C; (* from STANDARD.CDF file *)
    IntEnhOff = 375C; (* from STANDARD.CDF file *)
    MODEText = 'MODE';
    FileXdt = 'FILE.XDT';
    XlattablDat = 'XLATTABL.DAT';

PROCEDURE MakeNew(VAR p:  XlateEntryPointer;
                      ch: CHAR);
(*                    seq:ARRAY OF CHAR); *)
BEGIN
(*ALLOCATE(p,13 + Str.Length(seq)); *)
  NEW(p);
  WITH p^ DO
    Type := StrResult;
    InChar := ch;
(*  Str.Copy(OutSeq,seq); *)
    OutSeq[0] := 0C;
    OutMode := ' ';
    OutLen := 0;
    Next := NIL;
    Failure := NIL;
  END;
END MakeNew;

PROCEDURE FindMode(VAR XP:      XlateTablePointer;
                       Mode:    CHAR): XlateTablePntr;
VAR XP2:     XlateTablePntr;
    ch:      CHAR;
BEGIN
    IF XP = NIL THEN
       NEW(XP);
       FOR ch := '0' TO '9' DO XP^.XlateMode[ch] := NIL END;
    END;
    IF XP^.XlateMode[Mode] = NIL THEN
       WITH XP^ DO
          NEW(XlateMode[Mode]);
          WITH XP^.XlateMode[Mode]^ DO
            Seq := '';
            NEW(Table);
            XP2 := Table;
            WITH XP^.XlateMode[Mode]^.Table^ DO
              FOR ch := 1C TO 377C DO XlateTableDat[ch] := NIL END;
            END;
            RETURN Table;
          END;
       END;
    ELSE
       XP2 := XP^.XlateMode[Mode]^.Table
    END;
    RETURN XP2
END FindMode;

PROCEDURE InsertEntry(VAR GivenSeq:  ARRAY OF CHAR;
                          XP:        XlateTablePntr): XlateEntryPointer;
VAR
   ch:   CHAR;
   p:    XlateEntryPointer;
   i:    CARDINAL;
BEGIN
   ch := GivenSeq[0];
   IF XP^.XlateTableDat[ch] = NIL THEN
      MakeNew(p, ch);
      XP^.XlateTableDat[ch] := p;
   ELSE
      p := XP^.XlateTableDat[ch]
   END;
   i := 1;
   WHILE (i <= HIGH(GivenSeq)) AND (GivenSeq[i] <> 0C) DO
      ch := GivenSeq[i];
      IF p^.Next = NIL THEN
         MakeNew(p^.Next, ch);
         p := p^.Next;
      ELSE
         p := p^.Next
      END;
      WHILE (p^.Failure <> NIL) AND (p^.InChar <> ch) DO
         p := p^.Failure
      END;
      IF p^.InChar <> ch THEN
         MakeNew(p^.Failure, ch);
         p := p^.Failure;
      END;
      INC(i);
   END;
   RETURN p
END InsertEntry;

PROCEDURE InsertXlateMode(VAR XP:                XlateTablePointer;
                          ModeIn,ModeOut:        CHAR;
                          ModeSeq:               ARRAY OF CHAR;
                          DupWhat:               HandleDuplicateType;
                      VAR ErrorMsg:              ARRAY OF CHAR): BOOLEAN;
VAR
   ch:   CHAR;
   p:    XlateEntryPointer;
   XP2:  XlateTablePntr;
BEGIN
    ErrorMsg[0] := 0C;

    XP2 := FindMode(XP,ModeIn);

    (*<Dbg
    TWriteString('Trace InsertXlateMode Begins: ModeSeq:');
    TWriteString(ModeSeq);
    TWriteString(',ModeResult:');
    TWriteChar(Mode);
    TWriteLn;
    Dbg>*)
    p := InsertEntry(ModeSeq,XP2);

    WITH p^ DO
       IF (OutSeq[0] = 0C) OR (DupWhat = UpdateEntry) THEN
          Type := ModeChange;
          NewMode := ModeOut;
       ELSIF ((Type = ModeChange) OR (OutSeq[0] <> 0C))
       AND (DupWhat = GiveError) THEN
          Str.Copy(ErrorMsg, 'Conflicting Character Specs');
          (*<Dbg
          TWriteString('Trace InsertXlateMode Error: Inchar:');
          TWriteString(InChar);
          TWriteString(',OutSeq,GivenOutSeq:"');
          TWriteString(OutSeq);
          TWriteString('","');
          TWriteString(GivenOutSeq);
          TWriteString('"');
          TWriteLn;
          Dbg>*)
          RETURN FALSE;
       END;
    END;
    RETURN TRUE
END InsertXlateMode;

PROCEDURE InsertXlateData(VAR XP:                XlateTablePointer;
                          ModeIn,ModeOut:        CHAR;
                          GivenSeq, GivenOutSeq: ARRAY OF CHAR;
                          GivenOutLen:           CARDINAL;
                          DupWhat:               HandleDuplicateType;
                      VAR ErrorMsg:              ARRAY OF CHAR): BOOLEAN;
VAR
   mode:     CHAR;

PROCEDURE InsertForMode(mode: CHAR): BOOLEAN;
VAR
   p:        XlateEntryPointer;
   XP2:      XlateTablePntr;
BEGIN
   XP2 := FindMode(XP,mode);
   (*<Dbg
   TWriteString('trace InsertXlateTable Begins: GivenSeq:');
   TWriteString(GivenSeq);
   TWriteString(',GivenOutSeq:');
   TWriteString(GivenOutSeq);
   TWriteString(',GivenOutLen:');
   TWriteCard(GivenOutLen,0);
   TWriteLn;
   Dbg>*)
   p := InsertEntry(GivenSeq,XP2);

   WITH p^ DO
      IF (OutSeq[0] = 0C) OR (DupWhat = UpdateEntry) THEN
         Type := StrResult;
         Str.Copy(OutSeq,GivenOutSeq);
         OutMode := ModeOut;
         OutLen := GivenOutLen;
      ELSIF (Str.Compare(OutSeq,GivenOutSeq) <> 0) AND (DupWhat = GiveError) THEN
         Str.Copy(ErrorMsg, 'Conflicting Character Specs');
         (*<Dbg
         TWriteString('Trace InsertXlateData Error: Inchar:');
         TWriteString(InChar);
         TWriteString(',OutSeq,GivenOutSeq:"');
         TWriteString(OutSeq);
         TWriteString('","');
         TWriteString(GivenOutSeq);
         TWriteString('"');
         TWriteLn;
         Dbg>*)
         RETURN FALSE;
      END;
   END;
   RETURN TRUE
END InsertForMode;

BEGIN
   ErrorMsg[0] := 0C;

   IF ModeIn = '*' THEN
      IF XP = NIL THEN RETURN InsertForMode('0')
      ELSE
         FOR mode := '0' TO '9' DO
            IF XP^.XlateMode[mode] <> NIL THEN
               IF NOT InsertForMode(mode) THEN RETURN FALSE END;
            END;
         END;
      END;
   ELSE
      RETURN InsertForMode(ModeIn);
   END;
   RETURN TRUE
END InsertXlateData;

PROCEDURE InsertXModeData(VAR Int2Out:       XlateTablePointer;
                          VAR Out2Int:       XlateTablePointer;
                              Mode:          CHAR;
                              GivenSeq:      ARRAY OF CHAR;
                              DupWhat:       HandleDuplicateType;
                          VAR ErrorMsg:      ARRAY OF CHAR): BOOLEAN;
VAR
      XP2:      XlateTablePntr;
      p:        XlateEntryPointer;
      EPos:     CARDINAL;
BEGIN
    IF NOT InsertXlateMode(Out2Int,'0',Mode,GivenSeq,DupWhat,ErrorMsg) THEN
       RETURN FALSE
    END;

    XP2 := FindMode(Int2Out,Mode);
    WITH Int2Out^.XlateMode[Mode]^ DO
       IF (DupWhat = GiveError) AND (Seq[0] <> 0C) THEN
          EPos := 0;
          SWriteString(ErrorMsg, EPos, 'Mode definition conflict for mode "',0);
          SWriteString(ErrorMsg, EPos, Mode, 0);
          SWriteString(ErrorMsg, EPos, '"', 0);
          RETURN FALSE
       ELSIF (DupWhat = DiscardEntry) AND (Seq[0] <> 0C) THEN RETURN TRUE
       ELSE   Str.Copy(Seq,GivenSeq);
       END;
    END;
    RETURN TRUE;
END InsertXModeData;

PROCEDURE XlateLine(TransTable:      XlateTablePointer;
                    BadChar:         CHAR;
                    GivenLine:       ARRAY OF CHAR;
                VAR CurrentMode:     CurrentModeType;
                VAR OutputLine:      ARRAY OF CHAR);
    VAR
      TransType:           XlateTablePntr;
      LenD:                ARRAY [0..255] OF LengthDataType;
      HoldPos:             CARDINAL;
      ch:                  CHAR;
      CurrentXlateQueue:   XlateEntryPointer;
      ThisOne:             XlateEntryPointer;
      loop:                BOOLEAN;
      CurPos:              CARDINAL;
      OP,P,Len,MLen:       CARDINAL;
      CurInSeqLen:         CARDINAL;
      ActInSeqLen:         CARDINAL;
      hi,ho,hp:            CARDINAL;
      h:                   CARDINAL;

PROCEDURE AppendText;
BEGIN
   Len := 0;
   MLen := 0;
   WITH ThisOne^ DO
      h := HIGH(OutSeq);
      IF (OutMode <> '*') AND (OutMode <> CurrentMode.ModeOut) THEN
(*        IF (OutSeq[0] <> ' ') OR (OutSeq[1] <> 0C) THEN *)
          IF (OutSeq[0] <> 0C) THEN
            WITH TransTable^.XlateMode[OutMode]^ DO
               WHILE (OP <=ho) AND (Seq[MLen] <> 0C) DO
                  OutputLine[OP] := Seq[MLen];
                  INC(MLen); INC(OP);
               END;
               CurrentMode.ModeOut := OutMode;
            END;
         END;
      END;
      WHILE (Len <= h) AND (OP <=ho) AND (OutSeq[Len] <> 0C) DO
         OutputLine[OP] := OutSeq[Len];
         INC(Len); INC(OP);
      END;
      LenD[P].Int := ActInSeqLen;
      LenD[P].Out := MLen + Len;
      LenD[P].ApprOut := OutLen;
   END;
END AppendText;

  BEGIN
     hi := HIGH(GivenLine);
     ho := HIGH(OutputLine);
     hp := HIGH(LenD);

     CurrentXlateQueue := NIL;
     ThisOne := NIL;
     OP := 0;
     CurPos := 0;
     P := 0;
     CurInSeqLen := 0;
     ActInSeqLen := 0;
     ch := GivenLine[CurPos];
     HoldPos := 0;
     IF TransTable = NIL THEN (* a straight copy to out variables *)
        Str.Copy(OutputLine,GivenLine);
        RETURN
     END;

     TransType := TransTable^.XlateMode[CurrentMode.ModeIn]^.Table;
     WHILE (ch <> 0C) AND (P <= hp) AND (OP <= ho) DO
        IF CurrentXlateQueue = NIL THEN
           CurrentXlateQueue := TransType^.XlateTableDat[ch]
        END;
        loop := CurrentXlateQueue <> NIL;
        WHILE loop DO
           IF CurrentXlateQueue = NIL THEN
              loop := FALSE
           ELSIF ch = CurrentXlateQueue^.InChar THEN
              WITH CurrentXlateQueue^ DO
                 loop := FALSE;
                 INC(CurInSeqLen);
                 IF (Type = ModeChange) OR (OutMode <> ' ') THEN
                    ThisOne := CurrentXlateQueue;
                    HoldPos := CurPos;
                    ActInSeqLen := CurInSeqLen;
                 END;
              END
           ELSE
              CurrentXlateQueue := CurrentXlateQueue^.Failure
           END;
        END;  (* WHILE loop DO *)
        IF CurrentXlateQueue <> NIL THEN
           CurrentXlateQueue := CurrentXlateQueue^.Next
        END;
        IF CurrentXlateQueue = NIL THEN
           IF ThisOne = NIL THEN
              OutputLine[OP] := BadChar;
              INC(OP);
              LenD[P].Int := 1;
              LenD[P].Out := 1;
              LenD[P].ApprOut := 1;
              ActInSeqLen := 0;
              CurInSeqLen := 0;
              INC(P);
           ELSE
              WITH ThisOne^ DO
                 IF Type = ModeChange THEN
                    CurrentMode.ModeIn := NewMode;
                    TransType := TransTable^.XlateMode[NewMode]^.Table;
                 ELSE
                    IF OutSeq[0] <> 0C THEN AppendText END;
                    ActInSeqLen := 0;
                    CurInSeqLen := 0;
                    INC(P);
                 END;
              END;
              ThisOne := NIL;
           END;
           CurPos := HoldPos;
           INC(HoldPos);
        END;
        INC(CurPos);
        IF CurPos > hi THEN
           ch := 0C
        ELSE
           ch := GivenLine[CurPos]
        END;
     END;  (* WHILE (ch <> 0C) AND (P <= hp) AND (OP <= ho) DO *)
     IF ThisOne <> NIL THEN
        IF ThisOne^.OutSeq[0] <> 0C THEN AppendText END;
        INC(P);
     END;

     IF OP <= ho THEN   OutputLine[OP] := 0C   END ;
  END XlateLine ;

PROCEDURE AddIfAbsent(XP:      XlateTablePointer;
                      C:       CHAR;
                      R:       ARRAY OF CHAR);
VAR
   p:     XlateEntryPointer;
   ch:    CHAR;
   XP2:   XlateTablePntr;
BEGIN
   XP2 := FindMode(XP,'0');

   IF XP2^.XlateTableDat[C] = NIL THEN
      MakeNew(p,C);
      XP2^.XlateTableDat[C] := p
   END;
   WITH XP2^.XlateTableDat[C]^ DO
      IF OutSeq[0] <> 0C THEN
         RETURN
      ELSE
         Str.Copy(OutSeq,R);
         OutLen := Str.Length(R);
         OutMode := '0';
      END
   END;
END AddIfAbsent;

PROCEDURE IsNotDefined(XP:      XlateTablePointer;
                       C:       CHAR): BOOLEAN;
VAR
   p:     XlateEntryPointer;
   XP2:   XlateTablePntr;
BEGIN
   XP2 := FindMode(XP,'0');
   RETURN XP2^.XlateTableDat[C] = NIL;
END IsNotDefined;

PROCEDURE LineIsMode(InputLine: ARRAY OF CHAR;
                     DevName:   ARRAY OF CHAR;
                 VAR Success:   BOOLEAN;
                 VAR Mode:      CHAR;
                 VAR Seq:       ARRAY OF CHAR;
                 VAR TErrorMsg: ARRAY OF CHAR): BOOLEAN;
                                (* TRUE means LineIsMode handled it *)
TYPE
   TextPntr = POINTER TO StrAny;

VAR i,j:    CARDINAL;
    t:      ARRAY[0..11] OF CHAR;
    p:      TextPntr;
BEGIN
   Success := FALSE;
   i := 0;
   WHILE InputLine[i] = ' ' DO INC(i) END;
   IF InputLine[i] = 0C THEN RETURN FALSE END;

   j := 0;
   WHILE (j <= HIGH(t)) AND (CAP(InputLine[i]) >= 'A') AND
   (CAP(InputLine[i]) <= 'Z') DO
      t[j] := CAP(InputLine[i]);
      INC(j); INC(i);
   END;
   IF j <= HIGH(t) THEN t[j] := 0C END;

   IF Str.Compare(t,MODEText) <> 0 THEN RETURN FALSE END;

   WHILE InputLine[i] = ' ' DO INC(i) END;

   IF (InputLine[i] < '0') OR (InputLine[i] > '9') THEN
      Str.Copy(TErrorMsg,'Incorrectly formed "MODE" command found');
      RETURN TRUE
   END;
   Mode := InputLine[i];
   INC(i);

   WHILE InputLine[i] = ' ' DO INC(i) END;
   IF InputLine[i] = 0C THEN
      Str.Copy(TErrorMsg,'Incorrectly formed "MODE" command found');
      RETURN TRUE
   END;


   p := ADR(InputLine[i]);
   Success := ExtToSeq(p^,DevName,Seq,TErrorMsg);
   RETURN TRUE
END LineIsMode;

PROCEDURE GetXlateTables(XFileName: ARRAY OF CHAR;
                           ExtFieldNo:CARDINAL;
                       VAR ErrorMsg:  ARRAY OF CHAR): BOOLEAN;
VAR
   C,C2:        CHAR;
   CA:          ARRAY[0..0] OF CHAR;
   EPos:        CARDINAL;
   FileID:      FIO.File;
   FileBuff:    ARRAY[0..2047] OF BYTE;
   ExtData:     ARRAY[0..1] OF XlateFieldData;
   InputLine:   ARRAY[0..80] OF CHAR;
   IntSeq:      SequenceType;
   Enough:      BOOLEAN;
   BlankLine:   BOOLEAN;
   LineNo:      CARDINAL;
   TErrorMsg:   StrAny;
   ModeIsOK:    BOOLEAN;
   NumbModes:   CARDINAL;
   x:           XlateTablePntr;

PROCEDURE PrepareError(ErIn: ARRAY OF CHAR);
VAR
   Pos:    CARDINAL;
BEGIN
   Pos := 0;
   SWriteString(ErrorMsg, Pos, 'File ',0);
   SWriteString(ErrorMsg, Pos, XFileName, 0);
   SWriteString(ErrorMsg, Pos, ' (',0);
   SWriteCard(ErrorMsg, Pos, LineNo, 0);
   SWriteString(ErrorMsg, Pos, '): ',0);
   SWriteString(ErrorMsg, Pos, ErIn, 0);

   FIO.Close(FileID);
END PrepareError;

PROCEDURE ProcessTranslationLine(): BOOLEAN;
BEGIN
   IF (ExtData[ExtFieldNo].Dir = '~') THEN
      PrepareError('The "no-translation" character "~" is not permitted here');
      RETURN FALSE
   END;
   IF (ExtData[ExtFieldNo].Dir = ' ') OR (ExtData[ExtFieldNo].Dir = '>') THEN
      IF NOT InsertXlateData(Int2File,'0',ExtData[ExtFieldNo].Mode,IntSeq,ExtData[ExtFieldNo].Sqn,
         ExtData[ExtFieldNo].ActLen,UpdateEntry,TErrorMsg) THEN
         PrepareError(TErrorMsg);
         RETURN FALSE
      END
   END;
   IF (ExtData[ExtFieldNo].Dir = ' ') OR (ExtData[ExtFieldNo].Dir = '<') THEN
      IF NOT InsertXlateData(File2Int,ExtData[ExtFieldNo].Mode,'0',ExtData[ExtFieldNo].Sqn,IntSeq,
         Str.Length(IntSeq),GiveError,TErrorMsg) THEN
         PrepareError(TErrorMsg);
         RETURN FALSE
      END
   END;
   RETURN TRUE;
END ProcessTranslationLine;

PROCEDURE ReadLine(VAR text: ARRAY OF CHAR): BOOLEAN;
BEGIN
   FIO.RdStr(FileID, text);
   RETURN NOT FIO.EOF;
END ReadLine;

BEGIN
   NumbModes := 0;
   EPos := 0;
   FileID := FIO.Open(XFileName);
   FIO.AssignBuffer(FileID, FileBuff);
   ExtData[0].DevName := 'KEYBOARD';
   ExtData[0].LenOK := FALSE;
   ExtData[ExtFieldNo].DevName := 'FILE';
   ExtData[ExtFieldNo].LenOK := TRUE;
   LineNo := 0;
   WHILE ReadLine(InputLine) DO
      INC(LineNo);
      IF LineIsMode(InputLine,'FILE',ModeIsOK,C,IntSeq,TErrorMsg) THEN
         IF NOT ModeIsOK THEN
            PrepareError(TErrorMsg);
            RETURN FALSE
         END;
         IF (File2Int = NIL) OR (File2Int^.XlateMode[C] = NIL) THEN
            x := FindMode(File2Int,C);
         END;
         x := FindMode(Int2File,C);
         IF Int2File^.XlateMode[C]^.Seq[ExtFieldNo] <> 0C THEN
            SWriteString(TErrorMsg, EPos, 'Second mode definition for mode "',0);
            SWriteString(TErrorMsg, EPos, C,0);
            SWriteString(TErrorMsg, EPos, '"',0);
            PrepareError(TErrorMsg);
            RETURN FALSE
         END;
         Str.Copy(Int2File^.XlateMode[C]^.Seq,IntSeq);
         INC(NumbModes);
      ELSIF Line2Sequences(InputLine,BlankLine,IntSeq,ExtData,TErrorMsg) THEN
         IF NOT BlankLine THEN
            IF NOT ProcessTranslationLine() THEN RETURN FALSE END;
         END;
      ELSE
         PrepareError(TErrorMsg);
         RETURN FALSE
      END;
   END;

   FIO.Close(FileID);
   FOR C := ' ' TO '~' DO
     CA[0] := C;
     AddIfAbsent(Int2File,C,CA);
     AddIfAbsent(File2Int,C,CA);
   END;

   IF IsNotDefined(Int2File, IntEnhOn) THEN
      AddIfAbsent(Int2File,IntEnhOn,'{B}');
      CA[0] := IntEnhOn;
      IF NOT InsertXlateData(File2Int,'0','0','{B}', CA, 0,DiscardEntry, TErrorMsg) THEN
         RETURN FALSE
      END;
   END;

   IF IsNotDefined(Int2File, IntEnhOff) THEN
      AddIfAbsent(Int2File,IntEnhOff,'{N}');
      CA[0] := IntEnhOff;
      IF NOT InsertXlateData(File2Int,'0','0','{N}', CA, 0,DiscardEntry, TErrorMsg) THEN
         RETURN FALSE
      END;
   END;

   CA[0] := 0C;
   IF NumbModes >= 1 THEN
      FOR C := '0' TO '9' DO
         IF File2Int^.XlateMode[C] <> NIL THEN
            IF (Int2File^.XlateMode[C] = NIL) OR (Int2File^.XlateMode[C]^.Seq[0] = 0C) THEN
               SWriteString(TErrorMsg, EPos,
                         'No transition sequence was given for mode "',0);
               SWriteString(TErrorMsg, EPos, C, 0);
               SWriteString(TErrorMsg, EPos, '"', 0);
               RETURN FALSE
            END;
            FOR C2 := '0' TO '9' DO
               IF Int2File^.XlateMode[C2] <> NIL THEN
                  IF NOT InsertXlateMode(File2Int,C,C2,
                  Int2File^.XlateMode[C2]^.Seq,GiveError,TErrorMsg) THEN
                     PrepareError(TErrorMsg);
                     RETURN FALSE
                  END;
               END;
            END;
         END;
      END;
   END;

   RETURN TRUE;
END GetXlateTables;

PROCEDURE SetupTranslations();
VAR
   XFileName:   ARRAY[0..55] OF CHAR;
   DirName:     ARRAY[0..40] OF CHAR;
   ErrorMsg:    StrAny;
BEGIN
    InitialResGetSequences;

    IF FindFileInList(StandardSearchList,FileXdt, DirName) THEN
       Str.Concat(XFileName, DirName, FileXdt);
       IF NOT GetXlateTables(XFileName, 0, ErrorMsg) THEN
          FIO.WrStr(FIO.ErrorOutput,ErrorMsg);
          FIO.WrLn(FIO.ErrorOutput);
          HALT;
       END;
    ELSIF FindFileInList(StandardSearchList,XlattablDat, DirName) THEN
       Str.Concat(XFileName, DirName, XlattablDat);
       IF NOT GetXlateTables(XFileName, 1, ErrorMsg) THEN
          FIO.WrStr(FIO.ErrorOutput,ErrorMsg);
          FIO.WrLn(FIO.ErrorOutput);
          HALT;
       END;
    ELSE
       FIO.WrStr(FIO.ErrorOutput,'Could not find FILE.XDT or XLATTABL.DAT');
       FIO.WrLn(FIO.ErrorOutput);
       HALT;
    END;
END SetupTranslations;

BEGIN
  File2Int := NIL;
  Int2File := NIL;
END ResTranslations .

