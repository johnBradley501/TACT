IMPLEMENTATION MODULE Translations ;
(* copyright (c) 1989-96 John Bradley, Geoffrey Rockwell, Lidio Presutti, University of Toronto *)

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

(*V1=Mod3 Modula-2 version 3 *)
(*V2=Modf Modula-2 FTL version *)
(*V3=Modl Modula-2 Logitech version *)
(*V4=Dbg Debugging code *)

(*--------------------------------------------------------------------------*)
(* By:    Lidio Presutti                                                    *)
(* Date:  Apr. 27, 1988                                                     *)
(* Purpose:                                                                 *)
(*                                                                          *)
(* History:                                                                 *)
(*  27 Apr 88, Lidio Presutti                                               *)
(*     - added VAR to FN parameter in procs: XOpenInput, XOpenOutput,       *)
(*       DoGenericXOpen.                                                    *)
(*     - deleted some old-old-old comments.                                 *)
(*  15 Sep 88, Lidio Presutti                                               *)
(*     - patched a bug in InsertXlateData -- added HIGH(GivenSeq) check     *)
(*--------------------------------------------------------------------------*)

IMPORT Str;
FROM SYSTEM     IMPORT ADR;
FROM Storage    IMPORT Available;
(*<Dbg
FROM Trace      IMPORT TWriteString, TWriteCard, TWriteLn;
Dbg>*)
FROM Utils      IMPORT ConstStr,PrintCode,PrintHex1,PrintHex2,UpcaseStr,
                       StandardizeFileName,ReadLine,WriteLine,
                       BOpen,BClose,BCreate,BFile, WrStr, WrBin, WrLn, CrLf,
                       RWType, StandardSearchList,
                       ALLOCATE, DEALLOCATE;
FROM UtilsTwo   IMPORT IOErrorMessage,FindAndOpen, TranslationError,
                       InsufficientData, OK ;
FROM StringIO   IMPORT SWriteString,SWriteCard,SWriteInt, SWriteChar;
FROM STANDARD   IMPORT UpperCharList, LowerCharList,HighLowSize,
                       Initialize;
FROM ErrorBase  IMPORT ProgramErrorAndHalt;
FROM ExtendedAsciiKeys IMPORT InitializeExt;
FROM GlobalDefs IMPORT
  (* Type  *)  StrAny, SequenceType ;
FROM GetSequences IMPORT
     XlateFieldData, Line2Sequences,ExtToSeq;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage, PutResError ;
FROM ResCollection IMPORT
  (* type *) ResCollectionType,
  (* proc *) ReleaseCollection;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
CONST
    XlateEntryLength = 19; (* wouldn't be necessary is Fitted Software
                              Compiler supported TSIZE *)
(*RES OLD MSG 40
Character  Specifications Conflict.
*)
    ConflictMsgResource = (*RES REM INS*) 40 ;

(*RES OLD MSG 241
   IO Error %0 occurred.
*)
CONST
   IOErrorResNo = (*RES REM INS*) 241 ;

TYPE
    XlateListPointer = POINTER TO XlateListEntry;
    XlateListEntry = RECORD
                       Name:       ARRAY[0..7] OF CHAR;
                       ToXlate:    XlateTablePointer;
                       FromXlate:  XlateTablePointer;
                       Next:       XlateListPointer;
                     END;


VAR
    XlateList:           XlateListPointer;

PROCEDURE InitialXlateData(VAR XP:    XlateTablePointer);
BEGIN
   XP := NIL;
END InitialXlateData;

PROCEDURE MakeNew(VAR p:  XlateEntryPointer;
                      ch: CHAR);
(*                    seq:ARRAY OF CHAR); *)
BEGIN
(*ALLOCATE(p,13 + Str.Length(seq)); *)
  ALLOCATE(p,SIZE(XlateEntryDataType));
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
(*     NEW(XP); *)
       ALLOCATE(XP,SIZE(XlateModeList));
       FOR ch := '0' TO '9' DO XP^.XlateMode[ch] := NIL END;
    END;
    IF XP^.XlateMode[Mode] = NIL THEN
       WITH XP^ DO
(*        NEW(XlateMode[Mode]); *)
          ALLOCATE(XlateMode[Mode],SIZE(XlateModeData));
          WITH XP^.XlateMode[Mode]^ DO
            Seq := '';
(*          NEW(Table); *)
            ALLOCATE(Table,SIZE(XlateTableRec));
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
(* IF GivenSeq[0] = 0C THEN ProgramErrorAndHalt('InsertXlateData: 0') END; *)

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
   EPos: CARDINAL;
BEGIN
    EPos := 0;
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
          GetResMessage(ConflictMsgResource, ErrorMsg);

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
         GetResMessage(ConflictMsgResource, ErrorMsg);
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
BEGIN
    IF NOT InsertXlateMode(Out2Int,'0',Mode,GivenSeq,DupWhat,ErrorMsg) THEN
       RETURN FALSE
    END;

    XP2 := FindMode(Int2Out,Mode);
    WITH Int2Out^.XlateMode[Mode]^ DO
       IF (DupWhat = GiveError) AND (Seq[0] <> 0C) THEN
          (*RES OLD MSG 222
          There is a Definition Conflict for MODE "%0".
          *)
          MsgString(Mode,0);
          GetResMessage( (*RES REM INS*) 222 , ErrorMsg);
          RETURN FALSE
       ELSIF (DupWhat = DiscardEntry) AND (Seq[0] <> 0C) THEN RETURN TRUE
       ELSE   Str.Copy(Seq,GivenSeq);
       END;
    END;
    RETURN TRUE;
END InsertXModeData;

  PROCEDURE EquateXlateData(VAR XP: XlateTablePointer);
  VAR
      XP2:          XlateTablePntr;
      Mode:         CHAR;

  PROCEDURE EquateXlateMode(VAR XP: XlateTablePntr);
    VAR
      Letter:       CHAR;
      UpLetter:     CHAR;
      LPos:         CARDINAL;

    PROCEDURE MakeEquatedEntry(Ch: CHAR;
                           VAR P:  XlateEntryPointer): XlateEntryPointer;
      VAR
        NP: XlateEntryPointer;

      BEGIN
        WITH P^ DO
(*        NEW(NP); *)
          ALLOCATE(NP,SIZE(XlateEntryDataType));
          NP^ := P^;
          NP^.InChar := Ch;
        END;
        RETURN NP
      END MakeEquatedEntry;

    PROCEDURE HandleSub(XP: XlateEntryPointer);
      VAR
        P:        XlateEntryPointer;
        CCol:     ARRAY[0C..377C] OF BOOLEAN;
        NP:       XlateEntryPointer;
        OC:       CHAR;
        UPos:     CARDINAL;
        LPos:     CARDINAL;
    BEGIN
      P := XP;
      FOR OC := 0C TO 377C DO CCol[OC] := FALSE END;
      WHILE P <> NIL DO
        WITH P^ DO
          CCol[InChar] := TRUE;
          P := Failure;
        END
      END;
      P := XP;
      WHILE P <> NIL DO
         WITH P^ DO
            UPos := Str.Pos(UpperCharList,InChar);
            LPos := Str.Pos(LowerCharList,InChar);
            IF (UPos <= HIGH(UpperCharList)) OR (LPos <= HIGH(LowerCharList)) THEN
               IF UPos <= HIGH(UpperCharList) THEN
                  OC := LowerCharList[UPos]
               ELSE
                  OC := UpperCharList[LPos]
               END;
               IF NOT CCol[OC] THEN
                  NP := MakeEquatedEntry(OC, P);
                  Failure := NP;
                  P := NP;
                  IF Next <> NIL THEN
                     HandleSub(Next)
                  END;
               END;
            END;
            P := P^.Failure;
         END
      END;
    END HandleSub;

  BEGIN
    WITH XP^ DO
      FOR Letter := 1C TO 377C DO
        IF XlateTableDat[Letter] <> NIL THEN
          HandleSub(XlateTableDat[Letter]^.Next)
        END
      END;
      FOR LPos := 0 TO HighLowSize-1 DO
        Letter := LowerCharList[LPos];
        UpLetter := UpperCharList[LPos];
        IF XlateTableDat[Letter] <> NIL THEN
          IF XlateTableDat[UpLetter] = NIL THEN
            XlateTableDat[UpLetter] := MakeEquatedEntry(UpLetter, XlateTableDat[Letter])
          END
        ELSIF XlateTableDat[UpLetter] <> NIL THEN
          IF XlateTableDat[Letter] = NIL THEN
            XlateTableDat[Letter] := MakeEquatedEntry(Letter, XlateTableDat[UpLetter])
          END;
        END;
      END;
    END;
  END EquateXlateMode;
BEGIN
    WITH XP^ DO
       FOR Mode := '0' TO '9' DO
          IF XP^.XlateMode[Mode] <> NIL THEN
             EquateXlateMode(XP^.XlateMode[Mode]^.Table)
          END;
       END;
    END;
  END EquateXlateData;


PROCEDURE XlateLine(TransTable:      XlateTablePointer;
                    BadChar:         CHAR;
                    GivenLine:       ARRAY OF CHAR;
                VAR CurrentMode:     CurrentModeType;
                VAR ActualLength:    CARDINAL;
                VAR LenD:            ARRAY OF LengthDataType;
                VAR NumbSeq:         CARDINAL;
                VAR EnoughData:      BOOLEAN;
                VAR OutputLine:      ARRAY OF CHAR);
    VAR
      TransType:           XlateTablePntr;
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
      INC(ActualLength, OutLen);
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
     ActualLength := 0;
     P := 0;
     CurInSeqLen := 0;
     ActInSeqLen := 0;
     ch := GivenLine[CurPos];
     HoldPos := 0;
     IF TransTable = NIL THEN (* a straight copy to out variables *)
        WHILE (ch <> 0C) AND (P <= hp) AND (OP <= ho) DO
(*         AddToOutput(OutputLine,OP,Len,ch);  *)
           OutputLine[OP] := ch ;
           INC(OP) ;
           INC(ActualLength);
           LenD[P].Int := 1 ;
           LenD[P].Out := 1 ;
           LenD[P].ApprOut := 1 ;
           INC(P);
           INC(CurPos);
           IF CurPos > hi THEN
              ch := 0C
           ELSE
              ch := GivenLine[CurPos]
           END;
        END ; (* WHILE (ch <> 0C) AND (P <= hp) AND (OP <= ho) DO *)
        IF OP <= ho THEN   OutputLine[OP] := 0C   END ;
        NumbSeq := P;
        EnoughData := ch = 0C;
        RETURN
     END;

     TransType := TransTable^.XlateMode[CurrentMode.ModeIn]^.Table;
     WHILE (ch <> 0C) AND (P <= hp) AND (OP <= ho) DO
        IF CurrentXlateQueue = NIL THEN
           CurrentXlateQueue := TransType^.XlateTableDat[ch] ;
        END;
        loop := CurrentXlateQueue <> NIL;
        WHILE loop DO
           IF CurrentXlateQueue = NIL THEN
              loop := FALSE ;
           ELSIF ch = CurrentXlateQueue^.InChar THEN
              WITH CurrentXlateQueue^ DO
                 loop := FALSE;
                 INC(CurInSeqLen);
(*               IF OutSeq[0] <> 0C *)
                 IF (Type = ModeChange) OR (OutMode <> ' ') THEN
                    ThisOne := CurrentXlateQueue;
                    HoldPos := CurPos;
                    ActInSeqLen := CurInSeqLen;
                 END;
              END
           ELSE
              CurrentXlateQueue := CurrentXlateQueue^.Failure ;
           END;
        END;  (* WHILE loop DO *)
        IF CurrentXlateQueue <> NIL THEN
           CurrentXlateQueue := CurrentXlateQueue^.Next ;
        END;
        IF CurrentXlateQueue = NIL THEN
           IF ThisOne = NIL THEN
              OutputLine[OP] := BadChar;
              INC(OP);
              INC(ActualLength);
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
           ch := GivenLine[CurPos] ;
        END;
     END;  (* WHILE (ch <> 0C) AND (P <= hp) AND (OP <= ho) DO *)
     IF ThisOne <> NIL THEN
        IF ThisOne^.OutSeq[0] <> 0C THEN AppendText END;
        INC(P);
     END;

     IF OP <= ho THEN   OutputLine[OP] := 0C   END ;
     NumbSeq := P;
     EnoughData := ch = 0C;
  END XlateLine ;

  PROCEDURE DeleteXlateTable( VAR XP : XlateTablePointer );
  VAR
    ch:        CHAR;
    md:        CHAR;

  PROCEDURE ReleaseString(VAR P: XlateEntryPointer);
  BEGIN
     IF P = NIL THEN RETURN END;
     WITH P^ DO
         IF Failure <> NIL THEN ReleaseString(Failure) END;
         IF Next <> NIL THEN ReleaseString(Next) END;
     END;
(*   DISPOSE(P); *)
     DEALLOCATE(P,SIZE(XlateEntryDataType));
     P := NIL;
  END ReleaseString;

  BEGIN
     IF XP = NIL THEN RETURN END;
     FOR md := '0' TO '9' DO
        IF XP^.XlateMode[md] <> NIL THEN
           WITH XP^.XlateMode[md]^.Table^ DO
              FOR ch := 1C TO 377C DO
                IF XlateTableDat[ch] <> NIL THEN
                   ReleaseString(XlateTableDat[ch])
                END
              END
           END;
(*         DISPOSE(XP^.XlateMode[md]^.Table); *)
           DEALLOCATE(XP^.XlateMode[md]^.Table,SIZE(XlateTableRec));
(*         DISPOSE(XP^.XlateMode[md]); *)
           DEALLOCATE(XP^.XlateMode[md],SIZE(XlateModeData));
        END
     END;
(*   DISPOSE(XP); *)
     DEALLOCATE(XP,SIZE(XlateModeList));
     XP := NIL
  END DeleteXlateTable ;

  PROCEDURE DumpXlateTable(XP: XlateTablePointer;
                           InDev, OutDev: ARRAY OF CHAR;
                           Output:       OutProc);
VAR
  Mode:     CHAR;
  MP:       CARDINAL;
  Msg:      ARRAY[0..80] OF CHAR;

  PROCEDURE WriteOut;
  BEGIN
      IF NOT Output(Msg) THEN
         HALT;
      END;
      MP := 0;
  END WriteOut;

  PROCEDURE DumpXlateMode(XP:   XlateTablePntr;
                          Mode: CHAR);
    VAR
      CurrentChar: CHAR;

    PROCEDURE PrintQueueItem(ThisItem: XlateEntryPointer;
                             Depth: INTEGER);
      VAR
        Blanks:   ARRAY [0..80] OF CHAR;
        TempStr:  ARRAY[0..40] OF CHAR;
    BEGIN
      MP := 0;
      WITH ThisItem^ DO
        SWriteString(Msg,MP, '===============================================', 0);
        WriteOut;

        ConstStr(' ',Depth*5,Blanks);
        SWriteString(Msg,MP, Blanks, 0);
        SWriteChar(Msg,MP, InChar, 0);
        IF Type = StrResult THEN
           SWriteString(Msg,MP, ': Str: OutSeq: ', 0);
           PrintCode(OutSeq,TempStr);
           SWriteString(Msg,MP, TempStr, 0);
           SWriteString(Msg,MP, ',Len:', 0);
           SWriteCard(Msg,MP, OutLen, 0);
           SWriteString(Msg,MP, ',OutMode:', 0);
           SWriteChar(Msg,MP, OutMode, 0);
        ELSE
           SWriteString(Msg,MP, ': NewMode: ', 0);
           SWriteChar(Msg,MP, NewMode, 0);
        END;
        WriteOut;

        SWriteString(Msg,MP, Blanks, 0);
        SWriteString(Msg,MP, '           ', 0);
        PrintHex1(OutSeq,TempStr);
        SWriteString(Msg,MP, TempStr, 0);
        WriteOut;

        SWriteString(Msg,MP, Blanks, 0);
        SWriteString(Msg,MP, '           ', 0);
        PrintHex2(OutSeq,TempStr);
        SWriteString(Msg,MP, TempStr, 0);
        WriteOut;
      END;
    END PrintQueueItem;

    PROCEDURE ProcessNext(Pointer: XlateEntryPointer;
                          Depth: CARDINAL);
      VAR
        CurrentItem: XlateEntryPointer;
    BEGIN
      CurrentItem := Pointer;
      WHILE CurrentItem <> NIL DO
        PrintQueueItem(CurrentItem, Depth);
        ProcessNext(CurrentItem^.Next, Depth+1);
        CurrentItem := CurrentItem^.Failure;
      END;
    END ProcessNext;


  BEGIN
    Msg := 0C;
    WriteOut;
    SWriteString(Msg,MP, '****** Beginning Mode: ', 0);
    SWriteChar(Msg,MP, Mode, 0);
    WriteOut;
    FOR CurrentChar := 1C TO 377C DO
      IF XP^.XlateTableDat[CurrentChar] <> NIL THEN
        PrintQueueItem(XP^.XlateTableDat[CurrentChar], 0);
        IF XP^.XlateTableDat[CurrentChar]^.Next <> NIL THEN
          ProcessNext(XP^.XlateTableDat[CurrentChar]^.Next, 1)
        END;
      END;
    END;
  END DumpXlateMode;

BEGIN
    MP := 0;
    SWriteString(Msg,MP, 'Dump of "', 0);
    SWriteString(Msg,MP, InDev, 0);
    SWriteString(Msg,MP, '" to "', 0);
    SWriteString(Msg,MP, OutDev, 0);
    SWriteChar(Msg,MP, '"', 0);
    WriteOut;
    FOR Mode := '0' TO '9' DO
        IF XP^.XlateMode[Mode] <> NIL THEN
           DumpXlateMode(XP^.XlateMode[Mode]^.Table,Mode);
        END;
    END;
  END DumpXlateTable;

PROCEDURE NewXlateListEntry(N:    ARRAY OF CHAR;
                            T:    XlateTablePointer;
                            F:    XlateTablePointer): XlateListPointer;
VAR
    p:          XlateListPointer;
BEGIN
   IF Str.Length(N) > 8 THEN
      N[8] := 0C;
   END;
   IF Available(XlateEntryLength) THEN
(*    NEW(p); *)
      ALLOCATE(p,SIZE(XlateListEntry));
      WITH p^ DO
         Str.Copy(Name,N);
         ToXlate :=   T;
         FromXlate := F;
         Next :=      XlateList;
      END;
      XlateList := p;

      (*<Dbg
      TWriteString('TRACE NewXlateListEntry: New Entry:');
      TWriteString(N);
      TWriteLn;
      Dbg>*)
      RETURN p
   ELSE
      RETURN NIL
   END
END NewXlateListEntry;

PROCEDURE AddNewXlateListEntry(N:    ARRAY OF CHAR;
                               T:    XlateTablePointer;
                               F:    XlateTablePointer): BOOLEAN;

(* This Exportable form of NewXlateListEntry is used in KEYTRANS
   and allows new Xlate tables to be added to the XlateList without
   returning the pointer to where the item is -- info not needed by
   KEYTRANS.  Other applications should use GETNEWXLATETABLE or
   XOpenInput or XOpenOutput.   *)

VAR
    p:          XlateListPointer;

BEGIN
    p := NewXlateListEntry(N,T,F);
    RETURN p <> NIL;
END AddNewXlateListEntry;

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

PROCEDURE LineIsMode(InputLine: ARRAY OF CHAR;
                     DevName:   ARRAY OF CHAR;
                 VAR Success:   BOOLEAN;
                 VAR Mode:      CHAR;
                 VAR Seq:       ARRAY OF CHAR;
                 VAR TErrorMsg: ARRAY OF CHAR): BOOLEAN;
                                (* TRUE means LineIsMode handled it *)
(*RES OLD MSG 221
TACT has found an Incorrectly-Formed MODE Command.
*)
CONST
   MalFormedRes = (*RES REM INS*) 221 ;

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
      GetResMessage( MalFormedRes , TErrorMsg);
      RETURN TRUE
   END;
   Mode := InputLine[i];
   INC(i);

   WHILE InputLine[i] = ' ' DO INC(i) END;
   IF InputLine[i] = 0C THEN
      GetResMessage( MalFormedRes , TErrorMsg);
      RETURN TRUE
   END;


   p := ADR(InputLine[i]);
   Success := ExtToSeq(p^,DevName,Seq,TErrorMsg);
   RETURN TRUE
END LineIsMode;

PROCEDURE GetNewXlateTable(N:        ARRAY OF CHAR;
                       VAR ErrorMsg: ARRAY OF CHAR): XlateListPointer;

CONST
   ChCR = 012C; (* = 10 *)
   ChLF = 015C; (* = 13 *)

VAR
   C,C2:        CHAR;
   CA:          ARRAY[0..0] OF CHAR;
   EPos:        CARDINAL;
   XFileName:   StrAny;
   FileID:      BFile;
   ExtData:     ARRAY[0..0] OF XlateFieldData;
   InputLine:   ARRAY[0..80] OF CHAR;
   IntSeq:      SequenceType;
   IOResult:    CARDINAL;
   Enough:      BOOLEAN;
   BlankLine:   BOOLEAN;
   LineNo:      CARDINAL;
   TErrorMsg:   StrAny;
   ToPtr:       XlateTablePointer; (* For Ext2Int pointer *)
   FromPtr:     XlateTablePointer; (* For Int2Ext pointer *)
   TP:          XlateListPointer;
   ModeIsOK:    BOOLEAN;
   NumbModes:   CARDINAL;
   x:           XlateTablePntr;

PROCEDURE PrepareError(ErIn: ARRAY OF CHAR);
BEGIN
   (*RES OLD MSG 41
   File %0 (%1) %2
   *)
   MsgString(XFileName,0);
   MsgCard(LineNo,0);
   MsgString(ErIn,0);
   GetResMessage( (*RES REM INS*) 41,ErrorMsg);

   BClose(FileID,IOResult);
END PrepareError;

PROCEDURE ProcessTranslationLine(): BOOLEAN;
BEGIN
   IF (ExtData[0].Dir = '~') THEN
      (*RES OLD MSG 213
      Please do not Use the "no-translation" Character "~" here.
      *)
      GetResMessage( (*RES REM INS*) 213 , TErrorMsg);
      PrepareError(TErrorMsg);
      RETURN FALSE
   END;
   IF (ExtData[0].Dir = ' ') OR (ExtData[0].Dir = '>') THEN
      IF NOT InsertXlateData(ToPtr,'0',ExtData[0].Mode,IntSeq,ExtData[0].Sqn,
         ExtData[0].ActLen,UpdateEntry,TErrorMsg) THEN
         PrepareError(TErrorMsg);
         RETURN FALSE
      END
   END;
   IF (ExtData[0].Dir = ' ') OR (ExtData[0].Dir = '<') THEN
      IF NOT InsertXlateData(FromPtr,ExtData[0].Mode,'0',ExtData[0].Sqn,IntSeq,
         Str.Length(IntSeq),GiveError,TErrorMsg) THEN
         PrepareError(TErrorMsg);
         RETURN FALSE
      END
   END;
   RETURN TRUE;
END ProcessTranslationLine;

BEGIN
   NumbModes := 0;
   ToPtr := NIL;
   FromPtr := NIL;
   EPos := 0;
   Str.Copy(XFileName,N);
   IF NOT StandardizeFileName(XFileName,'.XDT') THEN
      (*RES OLD MSG 42
      "%0" cannot be a Translation Table Name.
      *)
      MsgString(N,0);
      GetResMessage( (*RES REM INS*) 42, ErrorMsg);
      RETURN NIL
   END;
   IF NOT FindAndOpen(StandardSearchList,XFileName,FileID,ErrorMsg) THEN
      RETURN NIL
   END;
   Str.Copy(ExtData[0].DevName,N);
   ExtData[0].LenOK := TRUE;
   LineNo := 0;
   WHILE ReadLine(FileID,InputLine,Enough,IOResult) DO
      (*<Dbg
      TWriteString('ReadLine:');
      TWriteString(InputLine);
      TWriteLn;
      Dbg>*)

      INC(LineNo);
      IF LineIsMode(InputLine,N,ModeIsOK,C,IntSeq,TErrorMsg) THEN
         IF NOT ModeIsOK THEN
            PrepareError(TErrorMsg);
            RETURN NIL
         END;
         IF (FromPtr = NIL) OR (FromPtr^.XlateMode[C] = NIL) THEN
            x := FindMode(FromPtr,C);
         END;
         x := FindMode(ToPtr,C);
         IF ToPtr^.XlateMode[C]^.Seq[0] <> 0C THEN
(*RES OLD MSG 223
A Second Definition for MODE "%0" was given.
*)
            MsgString(C,0);
            GetResMessage( (*RES REM INS*) 223 , TErrorMsg);
            PrepareError(TErrorMsg);
            RETURN NIL
         END;
         Str.Copy(ToPtr^.XlateMode[C]^.Seq,IntSeq);
         INC(NumbModes);
      ELSIF Line2Sequences(InputLine,BlankLine,IntSeq,ExtData,TErrorMsg) THEN
         IF NOT BlankLine THEN
            IF NOT ProcessTranslationLine() THEN RETURN NIL END;
         END;
      ELSE
         PrepareError(TErrorMsg);
         (*<Dbg
         TWriteString('Error fro L2Seq:');
         TWriteString(ErrorMsg);
         TWriteLn;
         Dbg>*)
         RETURN NIL
      END;
   END;

   IF IOResult = InsufficientData THEN
      (*<Dbg
      TWriteString('End due to Insufficient Data');
      TWriteLn;
      Dbg>*)

      BClose(FileID,IOResult);
      FOR C := ' ' TO '~' DO
        CA[0] := C;
        AddIfAbsent(ToPtr,C,CA);
        AddIfAbsent(FromPtr,C,CA);
      END;

      CA := ChLF;
      AddIfAbsent(ToPtr, ChLF, CA);
      AddIfAbsent(FromPtr, ChLF, CA); (* ext LF xlates to&from int NewLine *)

      CA[0] := 0C;
      AddIfAbsent(ToPtr, ChCR, CA); (* Ext CR translates to nothing *)
      AddIfAbsent(ToPtr,IntEnhOn,CA);
      AddIfAbsent(ToPtr,IntEnhOff,CA);

      IF NumbModes >= 1 THEN
         FOR C := '0' TO '9' DO
            IF FromPtr^.XlateMode[C] <> NIL THEN
               IF (ToPtr^.XlateMode[C] = NIL) OR (ToPtr^.XlateMode[C]^.Seq[0] = 0C) THEN
                  (*RES OLD MSG 226
                  No Translation Sequence was Given for MODE "%0".
                  *)
                  MsgString(C,0);
                  GetResMessage( (*RES REM INS*) 226 , TErrorMsg);
                  PrepareError(TErrorMsg);
                  RETURN NIL
               END;
               FOR C2 := '0' TO '9' DO
                  IF ToPtr^.XlateMode[C2] <> NIL THEN
                     IF NOT InsertXlateMode(FromPtr,C,C2,
                     ToPtr^.XlateMode[C2]^.Seq,GiveError,TErrorMsg) THEN
                        PrepareError(TErrorMsg);
                        RETURN NIL
                     END;
                  END;
               END;
            END;
         END;
      END;

      TP := NewXlateListEntry(N,ToPtr,FromPtr);
      IF TP = NIL THEN

         (*RES OLD MSG 43
         Insufficient Memory to Handle Xlate Table.
         *)
         GetResMessage( (*RES REM INS*) 43, ErrorMsg);
      END;
      RETURN TP
   END;
   IOErrorMessage(IOResult,TErrorMsg);
   BClose(FileID,IOResult);
   (*RES OLD MSG 44
   File %0: %1
   *)
   MsgString(XFileName,0);
   MsgString(TErrorMsg,0);
   GetResMessage( (*RES REM INS*) 44, ErrorMsg );

   (*<Dbg
   TWriteString('TRACE GetNewXlateTable Error Reported:');
   TWriteString(ErrorMsg);
   TWriteLn;
   Dbg>*)
   RETURN NIL
END GetNewXlateTable;

PROCEDURE FindXlateTable(N:          ARRAY OF CHAR;
                         Direction:  XlateDirectionType;
                     VAR Pointer:    XlateTablePointer;
                     VAR ErrorMsg:   ARRAY OF CHAR): BOOLEAN;
VAR
   P:          XlateListPointer;
BEGIN
   IF Str.Length(N) > 8 THEN
      N[8] := 0C;
   END;
   UpcaseStr(N,N);

   (*<Dbg
   TWriteString('TRACE FindXlateTable: Looking For:');
   TWriteString(N);
   TWriteLn;
   Dbg>*)
   P := XlateList;
   WHILE (P <> NIL) AND (Str.Compare(P^.Name,N) <> 0) DO
      (*<Dbg
      TWriteString('TRACE FindXlateTable: Rejected:');
      TWriteString(P^.Name);
      TWriteLn;
      Dbg>*)
      P := P^.Next
   END;
   IF P = NIL THEN
      P := GetNewXlateTable(N,ErrorMsg);
      IF P = NIL THEN
         (*<Dbg
         TWriteString('TRACE FindXlateTable: GetNewX Reported:');
         TWriteString(ErrorMsg);
         TWriteLn;
         Dbg>*)
         RETURN FALSE
         END
   END;
   CASE Direction OF
     StdOut,
     To,Append:     Pointer := P^.ToXlate
   | From:          Pointer := P^.FromXlate
   END;
   ErrorMsg[0] := 0C;
   RETURN TRUE
END FindXlateTable;

PROCEDURE DoGenericXOpen(VAR FN:       ARRAY OF CHAR;
                             DE:       ARRAY OF CHAR;
                             DD:       ARRAY OF CHAR;
                             DR:       XlateDirectionType;
                         VAR FL:       XFileType;
                         VAR ErrorMsg: ARRAY OF CHAR): BOOLEAN;
VAR
    p,i,j:    CARDINAL;
    dv:       StrAny;
    EPos:     CARDINAL;
    IOResult: CARDINAL;
BEGIN
    FL.ModeData.ModeIn := '0';
    FL.ModeData.ModeOut := '0';
    EPos := 0;
    p := Str.Pos(FN,'@');
    IF p > HIGH(FN) THEN Str.Copy(dv,DD)
    ELSE
      i := p+1; j := 0;
      WHILE(FN[i] <> 0C) AND (i <= HIGH(FN)) DO
           dv[j] := FN[i];
           INC(j); INC(i);
      END;
      FN[p] := 0C;
    END;
    IF (DR <> StdOut) THEN
       IF NOT StandardizeFileName(FN,DE) THEN
          (*RES OLD MSG 45
          "%0" cannot be a File Name.
          *)
          MsgString(FN,0);
          GetResMessage( (*RES REM INS*) 45, ErrorMsg );
          RETURN FALSE;
       END;
    END;
    IF DR = StdOut THEN
       BOpen(FL.ID,0C,BStdOut,IOResult);
    ELSIF DR = To THEN
       BCreate(FL.ID,FN,TRUE,IOResult);
    ELSIF DR = Append THEN
       BOpen(FL.ID,FN,AppendType,IOResult);
    ELSE
       BOpen(FL.ID,FN,ReadType,IOResult);
    END;
    IF IOResult <> OK THEN
       IOErrorMessage(IOResult,ErrorMsg);
       RETURN FALSE
    END;
    IF NOT FindXlateTable(dv,DR,FL.XP,ErrorMsg) THEN
       RETURN FALSE
    END;
    FL.Dir := DR;
    RETURN TRUE
END DoGenericXOpen;

PROCEDURE XOpenInput(VAR FN:       ARRAY OF CHAR;  (* Full File Name        *)
                         DE:       ARRAY OF CHAR;  (* Default Extension     *)
                         DD:       ARRAY OF CHAR;  (* Default Xlation Table *)
                     VAR FL:       XFileType;      (* File Pointer and Data *)
                     VAR ErrorMsg: ARRAY OF CHAR): BOOLEAN;
BEGIN
    FL.Dir := Defective;
    RETURN DoGenericXOpen(FN,DE,DD,From,FL,ErrorMsg)
END XOpenInput;

PROCEDURE XOpenOutput(VAR FN:       ARRAY OF CHAR;  (* Full File Name        *)
                          DE:       ARRAY OF CHAR;  (* Default Extension     *)
                          DD:       ARRAY OF CHAR;  (* Default Xlation Table *)
                      VAR FL:       XFileType;      (* File Pointer and Data *)
                      VAR ErrorMsg: ARRAY OF CHAR): BOOLEAN;
BEGIN
    FL.Dir := Defective;
    RETURN DoGenericXOpen(FN,DE,DD,To,FL,ErrorMsg)
END XOpenOutput;

PROCEDURE XAppend(    VAR FN:       ARRAY OF CHAR;  (* Full File Name        *)
                          DE:       ARRAY OF CHAR;  (* Default Extension     *)
                          DD:       ARRAY OF CHAR;  (* Default Xlation Table *)
                      VAR FL:       XFileType;      (* File Pointer and Data *)
                      VAR ErrorMsg: ARRAY OF CHAR): BOOLEAN;
BEGIN
    FL.Dir := Defective ;
    RETURN DoGenericXOpen(FN,DE,DD,Append,FL,ErrorMsg)
END XAppend ;

PROCEDURE XStdOut (DD:   ARRAY OF CHAR; (* Default Xlation Table *)
               VAR FL:   XFileType);    (* File Pointer and Data *)
VAR
   dummy:    BOOLEAN;
   dummystr: ARRAY[0..10] OF CHAR;
   ErrorMsg: ARRAY[0..40] OF CHAR;
BEGIN
   dummy := DoGenericXOpen(dummystr, 0C, DD, StdOut, FL, ErrorMsg);
END XStdOut;

PROCEDURE XClose(VAR FL:     XFileType);
VAR
   Dummy:    CARDINAL;
BEGIN
   FL.Dir := Defective;
   BClose(FL.ID,Dummy);
END XClose;

PROCEDURE XReadLine(VAR file:        XFileType;
                        badchar:     CHAR;
                    VAR data:        ARRAY OF CHAR;
                    VAR enoughdata:  BOOLEAN;
                    VAR IOResult:    CARDINAL): BOOLEAN;
VAR
   ts:         StrAny;
   al:         CARDINAL;
   ns:         CARDINAL;
BEGIN
   enoughdata := TRUE;
   data[0] := 0C;
   IF file.Dir <> From THEN
      IOResult := TranslationError;
      RETURN FALSE
   END;
   IF NOT ReadLine(file.ID,ts,enoughdata,IOResult) THEN
      RETURN FALSE
   END;
   XlateLine(file.XP,badchar,ts,file.ModeData,al,LenD,ns,enoughdata,data) ;
   RETURN TRUE
END XReadLine;

PROCEDURE XWrStr(VAR file:     XFileType;
                     data:     ARRAY OF CHAR;
                 VAR IOresult: CARDINAL): CARDINAL; (* actual length *)
VAR
   ts:         StrAny;
   al:         CARDINAL;
   ns:         CARDINAL;
   ed:         BOOLEAN;
BEGIN
   XlateLine(file.XP,'?',data,file.ModeData,al,LenD,ns,ed,ts) ;
   WrStr(file.ID,ts,IOresult);
   RETURN al;
END XWrStr;

PROCEDURE XWrLn(VAR file:     XFileType;
                VAR IOresult: CARDINAL);
BEGIN
   WrStr(file.ID,CrLf,IOresult);
END XWrLn;

PROCEDURE XWrNXlate(VAR file:        XFileType;
                        data:        ARRAY OF CHAR;
                    VAR IOResult:    CARDINAL);
BEGIN
   WrStr(file.ID,data,IOResult);
END XWrNXlate;

PROCEDURE XWrBin(VAR file:      XFileType;
                     data:      ARRAY OF BYTE;
                     size:      CARDINAL;
                 VAR IOResult:  CARDINAL);
BEGIN
  WrBin(file.ID, data, size, IOResult);
END XWrBin;

PROCEDURE XWriteLine(VAR file:        XFileType;
                         badchar:     CHAR;
                         data:        ARRAY OF CHAR;
                     VAR IOResult:    CARDINAL): BOOLEAN;
VAR
   ts:         StrAny;
   al:         CARDINAL;
   ns:         CARDINAL;
   ed:         BOOLEAN;
BEGIN
   IF (file.Dir <> To) AND (file.Dir <> Append) AND (file.Dir <> StdOut) THEN
      IOResult := TranslationError;
      RETURN FALSE
   END;

   XlateLine(file.XP,badchar,data,file.ModeData,al,LenD,ns,ed,ts) ;
   WriteLine(file.ID,ts,IOResult);
   RETURN IOResult = OK;
END XWriteLine;

PROCEDURE WriteWithTabs(VAR file:   XFileType;
                            text:   ARRAY OF CHAR;
                            Tabs:   ARRAY OF TabInfo): BOOLEAN;
VAR
   ts:         StrAny;
   al:         CARDINAL;
   ld:         XlateStrAny ;
   ns:         CARDINAL;
   ed:         BOOLEAN;
   result:     CARDINAL;
   Trial:      CARDINAL;
   NxtEvent:   CARDINAL;
   TabNo:      CARDINAL;
   TabBase:    CARDINAL;
   DoTabNext:  BOOLEAN;
   CurPos:     CARDINAL;
   ActCurPos:  CARDINAL;
   TempEndPos: CARDINAL;
   TabPos:     CARDINAL;
   MaxTabNo:   CARDINAL;
   CurrentStr: POINTER TO StrAny;
   EventChar:  CHAR;
   temp2:      StrAny;
   cm:         CurrentModeType;

PROCEDURE DoTabNow(VAR CurPos:    CARDINAL;
                       EndPos:    CARDINAL;
                       Pat:       ARRAY OF CHAR);
VAR
   len:      CARDINAL;
   temp:     StrAny;
   i,j,k:    CARDINAL;
   PatChar:  CHAR ;
   temp2:    StrAny;
   al:       CARDINAL;
BEGIN
   len := Str.Length(Pat);
   IF EndPos < CurPos THEN EndPos := CurPos + 5 END;

   IF len = 0 THEN
      PatChar := ' '
   ELSIF len = 1 THEN
      PatChar := Pat[0]
   END ;

   IF len <= 1 THEN
      ConstStr( PatChar, EndPos-CurPos, temp);
   ELSE (* pattern more than one character *)
      j := 0;
      i := CurPos MOD len;
      FOR k := CurPos TO EndPos DO
        temp[j] := Pat[i];
        INC(j); INC(i);
        IF (i >= len) THEN i := 0 END;
      END;
      temp[j] := 0C;
   END;
   XlateLine(file.XP,' ',temp,file.ModeData,al,ld,ns,ed,temp2) ;
   INC(ActCurPos,al);
   WrStr(file.ID,temp2,result);
(*
   INC(ActCurPos,j);
   WrStr(file.ID,temp,result);
*)
   IF result <> OK THEN
      IOErrorMessage(result,temp);
      MsgString(temp,0);
      PutResError( IOErrorResNo );
   END;
END DoTabNow;

BEGIN
    MaxTabNo := HIGH(Tabs);
    FOR TabNo := 0 TO MaxTabNo DO
       IF Tabs[TabNo].FilPat[0] <> 0C THEN
          cm.ModeIn := '0'; cm.ModeOut := '0';
          XlateLine(File2Int,' ',Tabs[TabNo].FilPat,cm,al,ld,ns,ed,temp2) ;
          Str.Copy(Tabs[TabNo].FilPat,temp2)
       END
    END;
    ActCurPos := 0;
    TabPos := 0;
    TabNo := 0;
    TabBase := 0;
    DoTabNext := FALSE;
    CurrentStr := ADR(text);
    CurPos := 0 ; (* m.s. *)
    LOOP
       Trial := Str.Pos(CurrentStr^, IntTab);
       IF Trial = MAX(CARDINAL) THEN
          NxtEvent := Str.Length(CurrentStr^);
          EventChar := 0C;
       ELSE
          NxtEvent := Trial;
          EventChar := CurrentStr^[Trial];
          CurrentStr^[NxtEvent] := 0C;
       END;

       IF NxtEvent <> 0 THEN
          XlateLine(file.XP,' ',CurrentStr^,file.ModeData,al,ld,ns,ed,temp2) ;
          IF DoTabNext THEN
             DoTabNext := FALSE;
             WITH Tabs[TabNo-1] DO
                CASE Type OF
                  Right:
		     IF TabPos > al THEN
			TempEndPos := TabPos - al
		     ELSE
			TempEndPos := ActCurPos + 2
		     END ;
		     DoTabNow( ActCurPos, TempEndPos, FilPat );
                     IF result <> OK THEN RETURN FALSE END;
                | Centre:
		     IF TabPos > (al DIV 2) THEN
			TempEndPos := TabPos - (al DIV 2)
		     ELSE
			TempEndPos := ActCurPos + 2
		     END ;
		     DoTabNow( ActCurPos, TempEndPos, FilPat );
                     IF result <> OK THEN RETURN FALSE END;
                ELSE ProgramErrorAndHalt('Tab Logic Failure')
                END
             END;
          END;
          INC(CurPos,NxtEvent);
          INC(ActCurPos,al);
          WrStr(file.ID,temp2,result);
          IF result <> OK THEN
             IOErrorMessage(result,temp2);
             MsgString(temp2,0);
             PutResError( IOErrorResNo );
             RETURN FALSE;
          END;
       END;

       CASE EventChar OF
         0C:
          WrLn(file.ID,result);
          RETURN result = OK;
       | IntTab:
          REPEAT
             IF TabNo > MaxTabNo THEN
                INC(TabBase,Tabs[MaxTabNo].Pos);
                INC(TabBase); (* one more for good luck j.b. *)
                TabNo := 0;
             END;
             TabPos := TabBase + Tabs[TabNo].Pos;
             INC(TabNo);
          UNTIL ActCurPos < TabPos;
          CASE Tabs[TabNo-1].Type OF
            Left:
		IF TabPos > 0 THEN
			TempEndPos := TabPos - 1
		ELSE
			TempEndPos := ActCurPos + 2
		END ;
               DoTabNow( ActCurPos, TempEndPos, Tabs[TabNo-1].FilPat ) ;
               IF result <> OK THEN RETURN FALSE END;
          | Right, Centre:
               DoTabNext := TRUE;
          ELSE ProgramErrorAndHalt('This Tab Type not yet implemented')
          END;
       ELSE ProgramErrorAndHalt('Bad Event Char found in WriteWithTabs')
       END;
       CurrentStr := ADR(CurrentStr^[NxtEvent+1]);
    END;
END WriteWithTabs;

PROCEDURE InitialTranslationData() : BOOLEAN;
VAR
   EMes:   ARRAY[0..90] OF CHAR;
   ResC:   ResCollectionType;
   OK:     BOOLEAN;
BEGIN
(*RES OLD DTA 3
KEYBOARD SCREEN FILE PRINTER INTERNAL MODE
*)
   Initialize;
   InitializeExt;

   GetDataArray( (*RES REM INS*) 3, ResC);

   OK := GetNextDataArrayStringItem(ResC,EMes); (* KEYBOARD, really *)
   OK := GetNextDataArrayStringItem(ResC,EMes); (* SCREEN, really *)
   OK := GetNextDataArrayStringItem(ResC,EMes); (* FILE, really *)
   OK := GetNextDataArrayStringItem(ResC,PRINTERText);
   OK := GetNextDataArrayStringItem(ResC,INTERNALText);
   OK := GetNextDataArrayStringItem(ResC,MODEText);
   FILEText := 'ISOLATIN'; (* in TACTWeb, the translation is ISOLATIN.XDT *)

   ReleaseCollection(ResC);

   IF (NOT FindXlateTable(FILEText, From, File2Int, EMes)) THEN
      ProgramErrorAndHalt(EMes);
   END;
   IF (NOT FindXlateTable(FILEText, To, Int2File, EMes)) THEN
      ProgramErrorAndHalt(EMes);
   END;
   RETURN TRUE;
END InitialTranslationData;

 BEGIN
(*  Int2Scr := NIL;
    Int2Prt := NIL;
    Scr2Int := NIL; *)
    Int2Alp := NIL;
    Alp2Int := NIL;
    Int2File := NIL;
    File2Int := NIL;
    Int2FAlp := NIL; (* m.s. *)
    XlateList := NIL;
    MODEText := 'MODE';
END Translations .

