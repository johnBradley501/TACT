IMPLEMENTATION MODULE KeyTranslation ;

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
(*V5=Dbg Debugging code *)

(*<Dbg
FROM Trace      IMPORT
      TWriteLn,TWriteChar,TWriteString,TWriteInt,TWriteCard,TWriteAddr,
      CloseTFile,TWriteStrHex;
Dbg>*)
IMPORT ASCII;
IMPORT TWB, Str, Lib ;
FROM GlobalDefs IMPORT
  (* Type  *) SequenceType, StrAny ;
FROM   SYSTEM  IMPORT WORD,TSIZE,ADR;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;
FROM   Utils   IMPORT Beep,ConstStr, PrintCode, PrintHex1, PrintHex2, CrLf,
                      WriteLine,ReadLine,BFile,BClose,
                      StandardSearchList, StandardizeFileName;
FROM   UtilsTwo IMPORT FindAndOpen, IOErrorMessage, InsufficientData;
FROM   StringIO IMPORT SWriteString,SWriteChar,SWriteCard;
FROM   GetSequences IMPORT XlateFieldData, Line2Sequences, ExtendedFlagChar;
FROM   Translations IMPORT XlateLine, InsertXlateData, FindXlateTable,
           XlateTablePointer,Int2Scr,Scr2Int, AddIfAbsent, Int2File, File2Int,
           LengthDataType,HandleDuplicateType,AddNewXlateListEntry,
           InitialXlateData, XlateStrAny, OutProc, MODEText, Int2Prt, LenD,
           LineIsMode, InsertXModeData, XlateDirectionType, CurrentModeType ;
FROM   KeyBase  IMPORT GetKeyStroke;
FROM   Storage  IMPORT ALLOCATE;
FROM   Windows  IMPORT DialogAttrib, TerminationProc, ChangeColorOnScreen,
                RegularAttr, BoldAttr, SpecialAttr;
FROM   ErrorBase IMPORT ProgramErrorAndHalt ;
FROM   STANDARD IMPORT Initialize;
FROM   ExtendedAsciiKeys IMPORT InitializeExt;
FROM   Char512 IMPORT ExtendedAvailable,PSType;

FROM ResCollection IMPORT
  (* type *) ResCollectionType,
  (* proc *) ReleaseCollection;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResMessages IMPORT
  (* proc *) MsgString, GetResMessage, PutResWarning ;

CONST
    UnKnownChar = 4C;
    ScrEsc = 377C;
    ScrTab = 100C;
    ScrEnhOn = 101C;
    ScrEnhOff = 102C;
    ScrChar1 = 01C;
    ScrChar2 = 02C;

TYPE
    KeyQueuePointer = POINTER TO KeySeqQueueDataType;
    KeySeqDataTypeType = (StrResult, ModeChange);
    KeySeqQueueDataType = RECORD
                            InChar: CHAR;
                            Next: KeyQueuePointer;
                            Failure: KeyQueuePointer;
                            CASE Type: KeySeqDataTypeType OF
                               StrResult:
                                 ScrLen:  CARDINAL;
                                 ScrMode: CHAR;
                                 IntSeq:  SequenceType;
                                 ScrSeq:  SequenceType;
                               | ModeChange:
                                 NewMode:CHAR;
                            END;
                          END;
    KeyXlateArray = RECORD
       Data: ARRAY[1C..377C] OF KeyQueuePointer
    END;
    KeyXlateArrayPntr = POINTER TO KeyXlateArray;
    StrAnyPntr = POINTER TO StrAny;
VAR
    KeyXlateData: ARRAY ['0'..'9'] OF KeyXlateArrayPntr;
    TempInt2Scr:  XlateTablePointer;
    CurMode:      CHAR;
    CurrentInputQueue: KeyQueuePointer;
    HoldSize:      CARDINAL;
    ReReadStart:   CARDINAL;
    HeldChar :     CHAR ;
    LastLength:    CARDINAL;

PROCEDURE DoScreenWrite(CurrentStr:       StrAnyPntr;
                        Attr:             SHORTCARD;
                    VAR CurrentCharSet:   SHORTCARD;
                    VAR Tabs:             ARRAY OF TabInfo);
VAR
   Trial:            CARDINAL;
   NxtEvent:         CARDINAL;
   EventChar:        CHAR;
   CurPos:           CARDINAL;
   TempEndPos:	     CARDINAL;
   TabPos:           CARDINAL;
   MaxTabNo:         CARDINAL;
   TabNo:            CARDINAL;
   TabBase:          CARDINAL;
   DoTabNext:        BOOLEAN;
   CurrentAttr:      SHORTCARD;

PROCEDURE DoTabNow(VAR CurPos:    CARDINAL;
                       EndPos:    CARDINAL;
                       Pat:       ARRAY OF CHAR);
VAR
   len:      CARDINAL;
   temp:     StrAny;
   i,j,k:    CARDINAL;
   PatChar:  CHAR ;
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
   TWB.SetPaletteColor(RegularAttr + CurrentCharSet);
   TWB.WrStr(temp);
   TWB.SetPaletteColor(CurrentAttr + CurrentCharSet);
   CurPos := EndPos + 1;
END DoTabNow;

BEGIN
(*  TWB.SetPaletteColor(Attr); *)
    TWB.SetPaletteColor(Attr + CurrentCharSet);
    CurrentAttr := Attr;
(*  CurrentCharSet := 0; *)
    CurPos := TWB.WhereX();
    TabPos := 0;
    MaxTabNo := HIGH(Tabs);
    TabNo := 0;
    TabBase := 0;
    DoTabNext := FALSE;

    LOOP
       Trial := Str.Pos(CurrentStr^, ScrEsc);
       IF Trial = MAX(CARDINAL) THEN
          NxtEvent := Str.Length(CurrentStr^);
          EventChar := 0C;
       ELSE
          NxtEvent := Trial;
          EventChar := CurrentStr^[Trial+1];
          CurrentStr^[NxtEvent] := 0C;
       END;

       IF NxtEvent <> 0 THEN
          IF DoTabNext THEN
             DoTabNext := FALSE;
             WITH Tabs[TabNo-1] DO
                CASE Type OF
                  Right:  TempEndPos := NxtEvent
                | Centre: TempEndPos := NxtEvent DIV 2
                ELSE ProgramErrorAndHalt('Tab Logic Failure')
                END;
                IF TabPos > TempEndPos THEN TempEndPos := TabPos - TempEndPos
                ELSE TempEndPos := CurPos + 2 END;
                DoTabNow( CurPos, TempEndPos, FilPat );
(* above code replaces following  j.b.
                CASE Type OF
                  Right:
		     IF TabPos > NxtEvent THEN
			TempEndPos := TabPos - NxtEvent
		     ELSE
			TempEndPos := CurPos + 2
		     END ;
                     DoTabNow( CurPos, TempEndPos, FilPat );
                | Centre:
		     IF TabPos > (NxtEvent DIV 2) THEN
			TempEndPos := TabPos - (NxtEvent DIV 2)
		     ELSE
			TempEndPos := CurPos + 2
		     END ;
                     DoTabNow( CurPos, TempEndPos, FilPat );
                ELSE ProgramErrorAndHalt('Tab Logic Failure')
                END
end of replaced code *)
             END;
          END;
          INC(CurPos,NxtEvent);
          TWB.WrStr(CurrentStr^);
       END;

       CASE EventChar OF
         0C:
          TWB.SetPaletteColor(RegularAttr + CurrentCharSet);
          RETURN
       | ScrTab:
          REPEAT
             IF TabNo > MaxTabNo THEN
                INC(TabBase,Tabs[MaxTabNo].Pos);
                INC(TabBase); (* one more for good luck j.b. *)
                TabNo := 0;
             END;
             TabPos := TabBase + Tabs[TabNo].Pos;
             INC(TabNo);
          UNTIL CurPos < TabPos;
          CASE Tabs[TabNo-1].Type OF
            Left:
	       IF TabPos > 0 THEN
		  TempEndPos := TabPos - 1
	       ELSE
		  TempEndPos := CurPos + 2
	       END ;
               DoTabNow(CurPos,TempEndPos,Tabs[TabNo-1].FilPat);
          | Right, Centre:
               DoTabNext := TRUE;
          ELSE ProgramErrorAndHalt('This Tab Type not yet implemented')
          END;
(*     | ScrEnhOn:
          CurrentAttr := BoldAttr;
          TWB.SetPaletteColor(BoldAttr + CurrentCharSet)
       | ScrEnhOff:
          CurrentAttr := RegularAttr;
          TWB.SetPaletteColor(RegularAttr + CurrentCharSet) *)
       | ScrChar1:
          CurrentCharSet := 0;
          TWB.SetPaletteColor(CurrentAttr)
       | ScrChar2:
          CurrentCharSet := 3;
          TWB.SetPaletteColor(CurrentAttr + 3)
       ELSE ProgramErrorAndHalt('Bad Event Char found in FancyScreenDisplay')
       END; (* CASE EventChar ... *)
       CurrentStr := ADR(CurrentStr^[NxtEvent+2]);
    END; (* LOOP *)
END DoScreenWrite;

PROCEDURE WriteScreenField( WindowRec:   WinType ;
                            L, X, Y:     CARDINAL;
                            Text:        ARRAY OF CHAR;
                            Attr:        CARDINAL;
                            Update:      BOOLEAN); (* at the moment, unused *)
   VAR
      ActualLength:     CARDINAL;
      PMax:             CARDINAL;
      rc:               CARDINAL;
      ED:               BOOLEAN;
      TempStr:          StrAny;
      I, J            : CARDINAL ;
      dTab :            ARRAY[0..0] OF TabInfo;
      cm:               CurrentModeType;
      CurrentCharSet:   SHORTCARD;

BEGIN
(*<Dbg
    TWriteString('TRACE WriteScreenField Begins,L:'); TWriteCard(L,0);
    TWriteString(',X:'); TWriteCard(X,0);
    TWriteString(',Y:'); TWriteCard(Y,0);
    TWriteString(',Text:'); TWriteString(Text);
    TWriteString(',Attr:'); TWriteCard(Attr,0);
    TWriteLn;
Dbg>*)
    cm.ModeIn := '0'; cm.ModeOut := '0';
    XlateLine(Int2Scr, UnKnownChar, Text, cm,
              ActualLength, LenD, PMax, ED, TempStr);
(*<Dbg
    TWriteString('TRACE WriteScreenField (after XlateLine), TempStr:');
    TWriteString(TempStr);
    TWriteLn;
Dbg>*)

    TWB.Use(WindowRec);
    IF (L <> 0) THEN
       IF (ActualLength > L) THEN
          (* truncate display string to fit field  *)
          I := 0 ;
          J := 0 ;
          WHILE J < L DO
             INC( I ) ;
             INC( J, LenD[I].Out ) ;
          END ;
          DEC( J, LenD[I].Out ) ;  (* compensate for going over *)
          TempStr[J+1] := 0C ;
       END;
       TWB.InitTextOnScreen(' ',X,Y,L);
    END;

(*<Dbg
    TWriteString('TRACE WriteScreenField (after trunc), TempStr:');
    TWriteString(TempStr);
    TWriteLn;
Dbg>*)
    IF (X < 1000) AND (Y < 1000) THEN  TWB.GotoXY(X,Y) END;
    IF L > 0 THEN ChangeColorOnScreen(Attr,X,Y,L) END;

    CurrentCharSet := 0;
    DoScreenWrite(ADR(TempStr),SHORTCARD(Attr),CurrentCharSet,dTab);
    IF X > 1999 THEN TWB.WrLn END;
END WriteScreenField;

PROCEDURE FancyScreenDisplay( WindowRec:   WinType;
                              X, Y:        CARDINAL;
                              Text:        ARRAY OF CHAR;
                              Tabs:        ARRAY OF TabInfo;
                              Update:      BOOLEAN);

   VAR
      ActualLength:     CARDINAL;
      PMax:             CARDINAL;
      rc:               CARDINAL;
      ED:               BOOLEAN;
      TempStr:          StrAny;
      cm:               CurrentModeType;
      NxtEvent:         CARDINAL;
      EventChar:        CHAR;
      CurCode:          CHAR;
      Trial:            CARDINAL;
      CurrentStr:       StrAnyPntr;
      CurrentCharSet:   SHORTCARD;
BEGIN
    TWB.Use(WindowRec);
    IF (X < 1000) AND (Y < 1000) THEN  TWB.GotoXY(X,Y) END;
    cm.ModeIn := '0'; cm.ModeOut := '0';
    CurrentStr := ADR(Text);
    CurCode := IntEnhOff;
    CurrentCharSet := 0;
    NxtEvent := 0;
    REPEAT
       CurrentStr := ADR(CurrentStr^[NxtEvent]);
       NxtEvent := Str.Pos(CurrentStr^,IntEnhOn);
       Trial := Str.Pos(CurrentStr^,IntEnhOff);
       IF Trial < NxtEvent THEN NxtEvent := Trial END;
       IF NxtEvent = MAX(CARDINAL) THEN
          NxtEvent := Str.Length(CurrentStr^);
          EventChar := 0C;
       ELSE
          EventChar := CurrentStr^[NxtEvent];
          CurrentStr^[NxtEvent] := 0C;
       END;
       IF NxtEvent <> 0 THEN
          XlateLine(Int2Scr, UnKnownChar, CurrentStr^, cm,
                 ActualLength, LenD, PMax, ED, TempStr);
          CASE CurCode OF
            IntEnhOn:  DoScreenWrite(ADR(TempStr),BoldAttr,CurrentCharSet,Tabs);
          | IntEnhOff: DoScreenWrite(ADR(TempStr),RegularAttr,CurrentCharSet,Tabs);
          ELSE
             ProgramErrorAndHalt('Unexpected CurCode in FancyScreenDisplay');
          END;
       END;
       INC(NxtEvent);
       CurCode := EventChar
    UNTIL CurCode = 0C;

    IF X > 1999 THEN TWB.WrLn END;
END FancyScreenDisplay;

PROCEDURE DoKeyTranslation( VAR Numb : CARDINAL ;
                            VAR Result : ARRAY OF CHAR ;
                            Term       : ARRAY OF CHAR ;
                            VAR TC     : CHAR ;
                            VAR FunctKey:      BOOLEAN);

VAR
      ScrLine:       StrAny;
      ReReadPos :    CARDINAL ;
(*      SavedChars:    StrAny; *)
      ch:            CHAR;
      GetChar,ED:    BOOLEAN;
(* m.s.     CurrentKeyQueue: KeyQueuePointer; *)
      LH:            CARDINAL;
      loop:          BOOLEAN;
      P, PMax, I:    CARDINAL;
      CurX, EndX:    CARDINAL;
      ActualLength:  CARDINAL;
      ScrStrPos:     CARDINAL;
      ResultStrPos:  CARDINAL;
      LenScr,
      LenResult:     CARDINAL;
(*    LenD:          XlateStrAny;  This change from earlier version
       breaks this procedure -- changed back by J.Bradley 3/3/88 *)
      LenD:          ARRAY[1..256] OF LengthDataType;
      TempStr:       StrAny;
      TempResult:    StrAny;
      rc:            CARDINAL;
      OldPriority:   CARDINAL;
(*      HeldChar:      CHAR; *)
      TMode:         CHAR;
      SMode:         CHAR;
      cm:            CurrentModeType;

BEGIN  (* for textual chars *)
    TMode := ' ';
    SMode := '0';
    FirstKeyIsText := FALSE ;  (* EXPORTED and used a VerifyXXXProc *)
    HeldChar := 0C;
(* m.s.    HoldSize := 0;
    SavedChars[0] := 0C;
    ReReadPos := 0; *)
(*    ReReadStart := Numb; *)
    ReReadPos := Numb ;
(*    HoldSize := Numb ; *)
(*    Str.Copy ( SavedChars, Result ) ; *)
    Str.Copy(TempResult, Result) ; (* m.s. - was Result *)
    IF ReReadPos = 0 THEN
      HoldSize := 0 ;
      ReReadStart := 0 ;
      LastLength := 0 ;
      HeldChar := 0C ;
      Result[0] := 0C ;
(*      SavedChars[0] := 0C ; *)
    END ;

    LOOP (* forever -- see RETURN below j.b. *)
      LOOP (* for textual character *)
         IF ReReadPos < Numb THEN  (* m.s. was holdSize *)

            (* if execution gets here we are reprocessing characters
            entered earlier *)

(*            ch := SavedChars[ReReadPos]; *)
            ch := Result[ReReadPos];
            INC(ReReadPos);
            EXIT
         END;
         IF HeldChar <> 0C THEN

            (* if execution gets here last keystroke was a textual
            extended char -- now we must not read a new keystroke but
            process the scan code associated with the keystroke *)

            ch := HeldChar;
            HeldChar := 0C;
            EXIT (* LOOP for textual character *)
         END;

         GetKeyStroke(ch, FunctKey);

         (* First, check to see if it is in the termination lists *)

(*         IF ( (NOT FunctKey) AND (Str.Pos(Term,ch) <= HIGH(Term)) )
             OR ( FunctKey (* m.s. not needed AND   (Str.Pos(FunctTerm,ch) <= HIGH(FunctTerm)) *) ) *)
         IF FunctKey   (* m.s. - rest not needed, I think *)
         THEN
             TC := ch;
             Str.Copy( Result,TempResult);
             (* m.s. - if Terminating sequence or function key return without doing anything *)
             RETURN ;
         END;

         (* character is not a termination char -- try something else *)

         CASE GetPanelControlKey(FunctKey, ch) OF
           (* m.s. - only panel key of interest is backspace, which will decrease string counter *)
           CursorRight, CursorLeft, EndOfField, BeginningOfField, EraseToEOF,
           DeleteChar:
              TC := ch ;
              RETURN ;
         | BackspaceDelete:
              IF Numb <= 0 THEN Beep (* m.s. - was P *)
              END;
              IF Numb > 0 THEN
                DEC( Numb ) ; (* m.s. - ?? delete counter by screen length ?? *)
                DEC( ReReadPos ) ;
              END ;
              Result[Numb] := 0C ;
              IF Numb = 0 THEN
                 (* special case where we want to return to top of list in calling proc *)
                 Result[0] := CHR(255) ;
              END ;
              LastLength := 0;
              CurrentInputQueue := NIL;
              RETURN ;
         ELSE
           (* character is not magic -- process it as text *)
            IF FunctKey THEN
               HeldChar := ch;
               ch := ExtendedFlagChar
            ELSE
               HeldChar := 0C;
            END;
            EXIT (* LOOP for textual character *)
         END;
     END; (* LOOP for textual character *)


(* now process the character we've just got *)

(*<Dbg
     TWriteString('New Char: ');
     TWriteStrHex(ch);
     TWriteString(',OldCKQueue: ');
     TWriteAddr(CurrentInputQueue);
     TWriteString(',HoldSize: ');
     TWriteCard(HoldSize,0);
     TWriteString(',ReReadPos: ');
     TWriteCard(ReReadPos,0);
     TWriteString(',ReReadStart: ');
     TWriteCard(ReReadStart,0);
     TWriteLn;
Dbg>*)
     IF CurrentInputQueue = NIL THEN
        (* we're going to try to start a new chain *)
        IF TMode <> ' ' THEN CurMode := TMode END;
        CurrentInputQueue := KeyXlateData[CurMode]^.Data[ch];
        LastLength := 0;
        ReReadStart := ReReadPos ; (* m.s. ? *)
     ELSE
        (* check to see if new character can be added to current chain *)
        WHILE (CurrentInputQueue <> NIL) AND (ch <> CurrentInputQueue^.InChar) DO
           CurrentInputQueue := CurrentInputQueue^.Failure;
        END;
     END;

(*<Dbg
     TWriteString('      NewCKQueue: ');
     TWriteAddr(CurrentInputQueue);
     TWriteLn;
     TWriteString(',SavedChars: ');
     TWriteStrHex(SavedChars);
Dbg>*)
     IF CurrentInputQueue = NIL THEN

        (* character was not recognized within translate table for
        one of two reasons: (1) no legal continuation of current
        string from this point or (2) no legal string at all *)

        IF LastLength = 0 THEN
           (* if we get here -- given ch cannot be translated *)
           (* m.s. - ignore whole string, start over *)
           HeldChar := 0C; (* ignore all of extended char *)
           HoldSize := 0; (* no need to hold previous characters either *)
           ReReadPos := 0;
           ReReadStart := 0;
           Result[0] := 0C ;
           Numb := 0 ;
           TC := ch ;
           RETURN ;
(*           Beep *)
        ELSE
           (* if we get here -- given ch cannot be added to current
           translation chain -- try again, asking routine to
           try re-read of all characters that haven't lead, so far,
           to a display on the screen (and ending with this char we've
           just read *)

           Result[Numb] := ch; (* save for future re-read *)
           INC(Numb);
           Result[Numb] := 0C;
           ReReadPos := ReReadStart; (* try to reread from end of last successful match *)
        END;
     ELSE

        (* character was recognized within translate table *)

        WITH CurrentInputQueue^ DO
          IF (Type <> ModeChange) AND (ScrLen = 0) THEN
             (* this character may be in legal string -- but there
             is still no assurrence -- if not rereading save it for
             possible future reuse *)
             IF ReReadPos >= Numb THEN
                Result[Numb] := ch;
                INC(Numb);
                Result[Numb] := 0C;
                INC(ReReadPos);
             END
          ELSE
             (* this character marks one legal termination point in a current
             string: hence, no need to hold previous characters for reread *)
             IF ReReadPos < (*= j.b.*) Numb THEN
                ReReadStart := ReReadPos ;
(* m.s.            ELSE
                HoldSize := 0;
                ReReadPos := 0;
                ReReadStart := 0;
                SavedChars[0] := 0C; *)
             END;
             IF Type = StrResult THEN (* m.s. DoTextDisplay *)
                 IF ReReadPos >= Numb THEN
                    Result[Numb] := ch;
                    INC(Numb);
                    Result[Numb] := 0C;
                    INC(ReReadPos);
                 END ;
                 LastLength := ScrLen ;  (* m.s. *)
             ELSE
               TMode := NewMode;
               LastLength := 0;
             END ;
          END;  (* IF ScrLen > 0 ... THEN *)
        END;  (* WITH CurrentInputQueue^ DO *)

        (* now, get ready for possible next char in current chain *)

        CurrentInputQueue := CurrentInputQueue^.Next ;
        EXIT ; (* m.s. *)
     END; (* IF CurrentInputQueue <> NIL -- char was recognized *)
   END; (* LOOP forever (except for legal character above) *)
END DoKeyTranslation ;


PROCEDURE GetScreenField( WindowRec:     WinType;
                          L, X, Y:       CARDINAL;
                          Term:          ARRAY OF CHAR;
                          FunctTerm:     ARRAY OF CHAR;
                      VAR Result:        ARRAY OF CHAR;
                      VAR TC:            CHAR;
                      VAR FunctKey:      BOOLEAN);

    VAR
      ScrLine:       StrAny;
      SavedChars:    StrAny;
      HoldSize:      CARDINAL;
      ReReadPos:     CARDINAL;
      ReReadStart:   CARDINAL;
      ch:            CHAR;
      GetChar,ED:    BOOLEAN;
      LastLength:    CARDINAL;
      CurrentKeyQueue: KeyQueuePointer;
      LH:            CARDINAL;
      loop:          BOOLEAN;
      P, PMax, I:    CARDINAL;
      CurX, EndX:    CARDINAL;
      ActualLength:  CARDINAL;
      ScrStrPos:     CARDINAL;
      ResultStrPos:  CARDINAL;
      LenScr,
      LenResult:     CARDINAL;
(*    LenD:          XlateStrAny;  This change from earlier version
       breaks this procedure -- changed back by J.Bradley 3/3/88 *)
      LenD:          ARRAY[1..256] OF LengthDataType;
      TempStr:       StrAny;
      TempResult:    StrAny;
      rc:            CARDINAL;
      OldPriority:   CARDINAL;
      FirstKeyStroke:BOOLEAN;
      HeldChar:      CHAR;
      TMode:         CHAR;
      SMode:         CHAR;
      cm:            CurrentModeType;

PROCEDURE BeginThis(); (* needed by compiler -- code too big otherwise jb *)
BEGIN
    Str.Copy(TempResult,Result);

    IF L > HIGH(Result)+1 THEN
       ProgramErrorAndHalt
           ( 'In GetScreenField - field length is greater than RESULT' );
       HALT ;
    END ;
    TWB.Use(WindowRec);

    (* Now convert it into it's screen form *)

    cm.ModeIn := '0'; cm.ModeOut := '0';
    XlateLine(Int2Scr, UnKnownChar, Result, cm,
              ActualLength, LenD, PMax, ED, ScrLine);

    (* LenD array elements have 3 values:
       Int:      Length of string in Result as single entity.
       Out:      Length of string in ScrLine as single entity.
       ApprOut:  same as OUT (??), not used.  ** WARNING: values not set! **
    *)

    LenResult := Str.Length(Result);
    LenScr := Str.Length(ScrLine);

    CurX := X;
    EndX := X+ActualLength;
    CurrentKeyQueue := NIL;
    P := 0;
    ScrStrPos := 0;
    ResultStrPos := 0;
    GetChar := TRUE;
    LastLength := 0;

    (* Now, initial screen attributes for field *)
    TWB.SetPaletteColor(FieldEditingAttr);
    ChangeColorOnScreen(CARDINAL(FieldEditingAttr),X,Y,L);

    TWB.PutOnTop(WindowRec);
    TWB.GotoXY(X,Y);
    TWB.CursorOn;

END BeginThis;

PROCEDURE EndThis();
VAR rc:   CARDINAL;
BEGIN
   TWB.SetPaletteColor(RegularAttr);
   ChangeColorOnScreen(CARDINAL(FieldNotEditingAttr),X,Y,L);
   TWB.CursorOff;
END EndThis;

PROCEDURE DoTextDisplay;
BEGIN
   WITH CurrentKeyQueue^ DO
      IF (NOT FirstKeyStroke) AND (LenScr+ScrLen-LastLength > L) THEN
         (* it's matched -- but won't fit! *)
         Beep
      ELSE
         (* something to display, and room to display it*)

         IF FirstKeyStroke THEN
            (* if we got here the first keystroke was a textual character:
            first, we need to clear the field *)
            FirstKeyIsText := TRUE ;  (* EXPORTED and used a VerifyXXXProc *)
            FirstKeyStroke := FALSE;
            TWB.InitTextOnScreen(' ',CurX,Y,L);
            TempResult[0] := 0C;
            ScrLine[0] := 0C;
            LenResult := 0;
            LenScr := 0;
            EndX := CurX;
            PMax := P;
           END;

         IF LastLength = 0 THEN
            (* needn't replace earlier display *)
            INC(P, 1);
            IF P <= PMax THEN
               Lib.Move(ADR(LenD[P]),ADR(LenD[P+1]),(PMax-P+1)*TSIZE(LengthDataType));
            END;
            INC(PMax, 1);
         ELSE
            (* must replace earlier display with this one *)
            WITH LenD[P] DO
               DEC(ResultStrPos, Int);
               DEC(ScrStrPos, Out);
               Str.Delete(TempResult, ResultStrPos, Int);
               Str.Delete(ScrLine, ScrStrPos, Out);
               DEC(LenScr,Out);
               DEC(LenResult,Int);
            END;
            DEC(CurX, LastLength);
            DEC(EndX, LastLength);
         END;

         (* now display new sequence *)

         IF P < PMax THEN
            I := Str.Length(ScrLine) - ScrStrPos;
            TWB.MoveText(CurX,Y,I,INTEGER(ScrLen)-INTEGER(LastLength),
                         ' ',FieldEditingAttr);
         END;
         IF (ScrMode <> '*') AND (ScrMode <> SMode) THEN
            IF ScrMode = '0' THEN TWB.SetPaletteColor(FieldEditingAttr)
            ELSE TWB.SetPaletteColor(FieldEditingAttr + 3)
            END;
            SMode := ScrMode;
         END;
         TWB.GotoXY(CurX,Y);
         TWB.WrStr(ScrSeq);
         LastLength := ScrLen;
         Str.Insert(TempResult, IntSeq, ResultStrPos);
         Str.Insert(ScrLine, ScrSeq, ScrStrPos);
         WITH LenD[P] DO
            Int := Str.Length(IntSeq);
            Out := Str.Length(ScrSeq);
            ApprOut := LastLength;
            INC(LenScr, Out);
            INC(LenResult, Int);
            INC(ResultStrPos, Int);
            INC(ScrStrPos, Out);
         END;
         INC(CurX, LastLength);
         INC(EndX, LastLength);
         TMode := ' ';
      END
   END;
END DoTextDisplay;

PROCEDURE DoModeChange;
BEGIN
   WITH CurrentKeyQueue^ DO
      IF LastLength <> 0 THEN
         IF P <= 0 THEN ProgramErrorAndHalt('Bad P in DoModeChange') END;
         WITH LenD[P] DO
            DEC(ResultStrPos, Int);
            DEC(ScrStrPos, Out);
            Str.Delete(TempResult, ResultStrPos, Int);
            Str.Delete(ScrLine, ScrStrPos, Out);
            DEC(LenScr,Out);
            DEC(LenResult,Int);
            DEC(CurX, LastLength);
            DEC(EndX, LastLength);
         END;
         LH := Str.Length(ScrLine);
         TWB.MoveText(CurX,Y,LH - ScrStrPos,-INTEGER(LastLength),' ',FieldEditingAttr);
         FOR I := P+1 TO PMax DO
            LenD[I] := LenD[I+1];
         END;
         DEC(P, 1);
         DEC(PMax, 1);
      END;
      TMode := NewMode;
      LastLength := 0;
   END;
END DoModeChange;

  BEGIN
    BeginThis();
    TMode := ' ';
    SMode := '0';
    FirstKeyStroke := TRUE;
    FirstKeyIsText := FALSE ;  (* EXPORTED and used a VerifyXXXProc *)
    HeldChar := 0C;
    HoldSize := 0;
    SavedChars[0] := 0C;
    ReReadPos := 0;
    ReReadStart := 0;

    LOOP (* forever -- see RETURN below j.b. *)
      LOOP (* for textual character *)
         IF ReReadPos < HoldSize THEN

            (* if execution gets here we are reprocessing characters
            entered earlier *)

            ch := SavedChars[ReReadPos];
            INC(ReReadPos);
            EXIT
         END;
         IF HeldChar <> 0C THEN

            (* if execution gets here last keystroke was a textual
            extended char -- now we must not read a new keystroke but
            process the scan code associated with the keystroke *)

            ch := HeldChar;
            HeldChar := 0C;
            EXIT (* LOOP for textual character *)
         END;

         TWB.GotoXY(CurX,Y);

         GetKeyStroke(ch, FunctKey);

         (* First, check to see if it is in the termination lists *)

         IF ( (NOT FunctKey) AND (Str.Pos(Term,ch) <= HIGH(Term)) ) OR
         ( FunctKey AND (Str.Pos(FunctTerm,ch) <= HIGH(FunctTerm)) ) THEN
             TC := ch;
             Str.Copy(Result,TempResult);
             EndThis();
             RETURN
         END;

         (* character is not a termination char -- try something else *)

         CASE GetPanelControlKey(FunctKey, ch) OF
           CursorRight:
              IF (P < PMax) THEN
                 INC(P);
                 INC(CurX, LenD[P].ApprOut);
                 INC(ResultStrPos, LenD[P].Int);
                 INC(ScrStrPos, LenD[P].Out);
              ELSE  (* don't permit cursor to get past field end *)
                 Beep
              END
         | CursorLeft:
              IF P > 0 THEN
                 DEC(CurX, LenD[P].ApprOut);
                 DEC(ResultStrPos, LenD[P].Int);
                 DEC(ScrStrPos, LenD[P].Out);
                 DEC(P, 1);
              ELSE
                 Beep
              END
         | EndOfField:
              FOR I := P+1 TO PMax DO
                INC(ResultStrPos, LenD[I].Int);
                INC(ScrStrPos, LenD[I].Out);
              END;
              P := PMax;
              CurX := EndX
         | BeginningOfField:
              P := 0;
              CurX := X;
              ResultStrPos := 0;
              ScrStrPos := 0
         | EraseToEOF:
              IF CurX < EndX THEN
                 TWB.GotoXY(CurX,Y);
                 TWB.InitTextOnScreen(' ',CurX,Y,EndX-CurX);
                 TempResult[ResultStrPos] := 0C;
                 ScrLine[ScrStrPos] := 0C;
                 LenResult := ResultStrPos;
                 LenScr := ScrStrPos;
                 EndX := CurX;
                 PMax := P;
              END
         | DeleteChar:
              FirstKeyStroke := FALSE;
              IF P >= PMax THEN
                 Beep
              ELSE
                 WITH LenD[P+1] DO
                    Str.Delete(TempResult, ResultStrPos, Int);
                    Str.Delete(ScrLine, ScrStrPos,Out);
                    DEC(LenScr,Out);
                    DEC(LenResult,Int);
                    DEC(EndX, ApprOut);
                    I := Str.Length(ScrLine) - ScrStrPos;
                    TWB.MoveText(CurX+ApprOut,Y,I,-INTEGER(ApprOut),' ',FieldEditingAttr);
                 END;
                 FOR I := P+1 TO PMax DO
                     LenD[I] := LenD[I+1];
                 END;
                 DEC(PMax, 1);
              END
         | BackspaceDelete:
              IF P <= 0 THEN Beep
              ELSE
                WITH LenD[P] DO
                   DEC(ResultStrPos, Int);
                   DEC(ScrStrPos, Out);
                   Str.Delete(TempResult, ResultStrPos, Int);
                   Str.Delete(ScrLine, ScrStrPos, Out);
                   DEC(LenScr,Out);
                   DEC(LenResult,Int);
                   I := Str.Length(ScrLine) - ScrStrPos;
                   TWB.MoveText(CurX,Y,I,-INTEGER(ApprOut),' ',FieldEditingAttr);
                   DEC(CurX, ApprOut);
                   DEC(EndX, ApprOut);
                END;
                FOR I := P+1 TO PMax DO
                   LenD[I] := LenD[I+1];
                END;
                DEC(P, 1);
                DEC(PMax, 1);
              END;
              LastLength := 0;
              CurrentKeyQueue := NIL;
         ELSE
            (* character is not magic -- process it as text *)
            IF FunctKey THEN
               HeldChar := ch;
               ch := ExtendedFlagChar
            ELSE
               HeldChar := 0C;
            END;
            EXIT (* LOOP for textual character *)
         END;
         FirstKeyStroke := FALSE;
     END; (* LOOP for textual character *)


(* now process the character we've just got *)

(*<Dbg
     TWriteString('New Char: ');
     TWriteStrHex(ch);
     TWriteString(',OldCKQueue: ');
     TWriteAddr(CurrentKeyQueue);
     TWriteString(',HoldSize: ');
     TWriteCard(HoldSize,0);
     TWriteString(',ReReadPos: ');
     TWriteCard(ReReadPos,0);
     TWriteString(',ReReadStart: ');
     TWriteCard(ReReadStart,0);
     TWriteLn;
Dbg>*)
     IF CurrentKeyQueue = NIL THEN
        (* we're going to try to start a new chain *)
        IF TMode <> ' ' THEN CurMode := TMode END;
        CurrentKeyQueue := KeyXlateData[CurMode]^.Data[ch];
        LastLength := 0;
     ELSE
        (* check to see if new character can be added to current chain *)
        WHILE (CurrentKeyQueue <> NIL) AND (ch <> CurrentKeyQueue^.InChar) DO
           CurrentKeyQueue := CurrentKeyQueue^.Failure;
        END;
     END;

(*<Dbg
     TWriteString('      NewCKQueue: ');
     TWriteAddr(CurrentKeyQueue);
     TWriteLn;
     TWriteString(',SavedChars: ');
     TWriteStrHex(SavedChars);
Dbg>*)
     IF CurrentKeyQueue = NIL THEN

        (* character was not recognized within translate table for
        one of two reasons: (1) no legal continuation of current
        string from this point or (2) no legal string at all *)

        IF LastLength = 0 THEN
           (* if we get here -- given ch cannot be translated *)
           HeldChar := 0C; (* ignore all of extended char *)
           HoldSize := 0; (* no need to hold previous characters either *)
           ReReadPos := 0;
           ReReadStart := 0;
           Beep
        ELSE
           (* if we get here -- given ch cannot be added to current
           translation chain -- try again, asking routine to
           try re-read of all characters that haven't lead, so far,
           to a display on the screen (and ending with this char we've
           just read *)

           SavedChars[HoldSize] := ch; (* save for future re-read *)
           INC(HoldSize);
           SavedChars[HoldSize] := 0C;
           ReReadPos := ReReadStart; (* try to reread from end of last successful match *)
        END;
     ELSE

        (* character was recognized within translate table *)

        WITH CurrentKeyQueue^ DO
          IF (Type <> ModeChange) AND (ScrLen = 0) THEN
             (* this character may be in legal string -- but there
             is still no assurrence -- if not rereading save it for
             possible future reuse *)
             IF ReReadPos >= HoldSize THEN
                SavedChars[HoldSize] := ch;
                INC(HoldSize);
                SavedChars[HoldSize] := 0C;
                INC(ReReadPos);
             END
          ELSE
             (* this character marks one legal termination point in a current
             string: hence, no need to hold previous characters for reread *)
             IF ReReadPos < (*= j.b.*) HoldSize THEN
                ReReadStart := ReReadPos
             ELSE
                HoldSize := 0;
                ReReadPos := 0;
                ReReadStart := 0;
                SavedChars[0] := 0C;
             END;
             IF Type = StrResult THEN DoTextDisplay
             ELSE DoModeChange END;
          END;  (* IF ScrLen > 0 ... THEN *)
        END;  (* WITH CurrentKeyQueue^ DO *)

        (* now, get ready for possible next char in current chain *)

        CurrentKeyQueue := CurrentKeyQueue^.Next

     END; (* IF CurrentKeyQueue <> NIL -- char was recognized *)
   END; (* LOOP forever (except for RETURN above) *)
 END GetScreenField;

PROCEDURE MakeNew( VAR p: KeyQueuePointer; ch: CHAR);
   BEGIN
      NEW(p);
      WITH p^ DO
         InChar := ch;
         IntSeq := '';
         ScrSeq := '';
         ScrLen := 0;
         ScrMode := '0';
         Next := NIL;
         Failure := NIL;
         Type := StrResult;
      END;
   END MakeNew;

PROCEDURE BuildNewPath(VAR GivenSeq:    ARRAY OF CHAR;
                           GivenMode:   CHAR): KeyQueuePointer;
VAR
   ch:       CHAR;
   i:        CARDINAL;
   GivenLen: CARDINAL;
   p:        KeyQueuePointer;
BEGIN
   GivenLen := Str.Length(GivenSeq);
   IF GivenLen = 0 THEN
      ProgramErrorAndHalt('Program Error, in BuildNewPath');
   END;

   IF KeyXlateData[GivenMode] = NIL THEN
      NEW(KeyXlateData[GivenMode]);
      WITH KeyXlateData[GivenMode]^ DO
         FOR ch := 1C TO 377C DO Data[ch] := NIL END
      END;
   END;

   ch := GivenSeq[0];
   WITH KeyXlateData[GivenMode]^ DO
      IF Data[ch] = NIL THEN
          MakeNew(p, ch);
          Data[ch] := p;
      ELSE
          p := Data[ch]
      END
   END;
   FOR i := 1 TO GivenLen-1 DO
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
   END;
   RETURN p;
END BuildNewPath;

PROCEDURE InsertKeyStrg( GivenSeq, GivenIntSeq, GivenScrSeq: ARRAY OF CHAR;
                         GivenScrLen: CARDINAL;
                         GivenScrMode:CHAR;
                         GivenMode:   CHAR;
                     VAR ErrorMsg:    ARRAY OF CHAR): BOOLEAN;
VAR
   p:        KeyQueuePointer;

BEGIN
   ErrorMsg[0] := 0C;
   p := BuildNewPath(GivenSeq,GivenMode);
   WITH p^ DO
      IF Type = ModeChange THEN
         ProgramErrorAndHalt('Same Keyboard Sequences: Mode Change')
      ELSIF IntSeq[0] = 0C THEN
         Str.Copy(IntSeq,GivenIntSeq)
      ELSIF Str.Compare(IntSeq,GivenIntSeq) <> 0 THEN
(*RES OLD MSG 46
Internal Sequences Given.
*)
         GetResMessage( (*RES REM INS*) 46, ErrorMsg);
         RETURN FALSE;
      END;
      IF ScrSeq[0] = 0C THEN
         Str.Copy(ScrSeq,GivenScrSeq);
         ScrLen := GivenScrLen;
         ScrMode := GivenScrMode;
      ELSIF Str.Compare(ScrSeq,GivenScrSeq) <> 0 THEN
(*RES OLD MSG 47
Screen Sequences Conflict.
*)
         GetResMessage( (*RES REM INS*) 47, ErrorMsg);
         RETURN FALSE;
      END;
   END;
   RETURN TRUE;
END InsertKeyStrg;

PROCEDURE InsertKeyMode( ModeOut:     CHAR;
                         GivenMode:   CHAR;
                         GivenSeq:    ARRAY OF CHAR;
                     VAR ErrorMsg:    ARRAY OF CHAR): BOOLEAN;
VAR
   p:        KeyQueuePointer;

BEGIN
   ErrorMsg[0] := 0C;
   p := BuildNewPath(GivenSeq,GivenMode);
   WITH p^ DO
       IF (IntSeq[0] = 0C) THEN
          Type := ModeChange;
          NewMode := ModeOut;
       ELSE
(*RES OLD MSG 227
The Mode Change from "%0" to "%1" Conflicts with Display Sequence.
*)
         MsgString(GivenMode,0);
         MsgString(ModeOut,0);
         GetResMessage( (*RES REM INS*) 227 , ErrorMsg);
         RETURN FALSE;
       END;
   END;
   RETURN TRUE;
END InsertKeyMode;

PROCEDURE DumpKeyData( OutPut:     OutProc);
   VAR
      Mode:     CHAR;
      MP:       CARDINAL;
      Msg:      ARRAY[0..80] OF CHAR;

   PROCEDURE WriteLn;
      BEGIN
         IF NOT OutPut(Msg) THEN HALT END;
         MP := 0;
      END WriteLn;

PROCEDURE DumpXlateMode(Mode: CHAR);
VAR
   CurrentChar: CHAR;

PROCEDURE PrintQueueItem( ThisItem : KeyQueuePointer; Depth : CARDINAL ) ;
   VAR
      Blanks:   ARRAY [0..80] OF CHAR;
      i:        CARDINAL;
      TempStr:  ARRAY[0..40] OF CHAR;
   BEGIN
      MP := 0;
      WITH ThisItem^ DO
         SWriteString(Msg,MP,'===============================================', 0);
         WriteLn;

         ConstStr(' ',Depth*5,Blanks);
         SWriteString(Msg,MP, Blanks, 0);
         SWriteChar(Msg,MP, InChar, 0);
         IF Type = StrResult THEN
            SWriteString(Msg,MP, ': IntSeq: ', 0);
            PrintCode(IntSeq,TempStr);
            SWriteString(Msg,MP, TempStr, 0);
         ELSE
            SWriteString(Msg,MP, ': NewMode: ', 0);
            SWriteChar(Msg,MP, NewMode, 0);
         END;
         WriteLn;

         SWriteString(Msg,MP, Blanks, 0);
         SWriteString(Msg,MP, '           ', 0);
         PrintHex1(IntSeq,TempStr);
         SWriteString(Msg,MP, TempStr, 0);
         WriteLn;

         SWriteString(Msg,MP, Blanks, 0);
         SWriteString(Msg,MP, '           ', 0);
         PrintHex2(IntSeq,TempStr);
         SWriteString(Msg,MP, TempStr, 0);
         WriteLn;

         IF Type = StrResult THEN
            SWriteString(Msg,MP, Blanks, 0);
            SWriteString(Msg,MP, '   ScrSeq: ', 0);
            PrintCode(ScrSeq,TempStr);
            SWriteString(Msg,MP, TempStr, 0);
            SWriteString(Msg,MP, ',Len:', 0);
            SWriteCard(Msg,MP, ScrLen, 0);
            WriteLn;

            SWriteString(Msg,MP, Blanks, 0);
            SWriteString(Msg,MP, '           ', 0);
            PrintHex1(ScrSeq,TempStr);
            SWriteString(Msg,MP, TempStr, 0);
            WriteLn;

            SWriteString(Msg,MP, Blanks, 0);
            SWriteString(Msg,MP, '           ', 0);
            PrintHex2(ScrSeq,TempStr);
            SWriteString(Msg,MP, TempStr, 0);
            WriteLn;
         END;
      END;
   END PrintQueueItem;

PROCEDURE ProcessNext( Pointer : KeyQueuePointer ; Depth : INTEGER) ;
   VAR
      CurrentItem: KeyQueuePointer;
   BEGIN
      CurrentItem := Pointer;
      WHILE CurrentItem <> NIL DO
         PrintQueueItem(CurrentItem, Depth);
         ProcessNext(CurrentItem^.Next, Depth+1);
         CurrentItem := CurrentItem^.Failure;
      END;
   END ProcessNext;

   BEGIN  (* DumpKeyData *)
    Msg := 0C;
    WriteLn;
    SWriteString(Msg,MP, '****** Beginning Mode: ', 0);
    SWriteChar(Msg,MP, Mode, 0);
    WriteLn;
    WITH KeyXlateData[Mode]^ DO
      FOR CurrentChar := 1C TO 377C DO
         IF Data[CurrentChar] <> NIL THEN
            PrintQueueItem(Data[CurrentChar], 0);
            IF Data[CurrentChar]^.Next <> NIL THEN
               ProcessNext(Data[CurrentChar]^.Next, 1)
            END;
         END;
      END;
   END;
END DumpXlateMode;

BEGIN
    MP := 0;
    SWriteString(Msg,MP, 'Dump of KeyXlateData', 0);
    WriteLn;
    FOR Mode := '0' TO '9' DO
        IF KeyXlateData[Mode] <> NIL THEN
           DumpXlateMode(Mode);
        END;
    END;
END DumpKeyData;

PROCEDURE InitialTranslationData() : BOOLEAN;
   VAR
      ErrorMsg:    ARRAY[0..80] OF CHAR;
      EPos:        CARDINAL;
      EndValue:    BOOLEAN;
      C,C2:        CHAR;
      CA:          ARRAY[0..1] OF CHAR;
      FileID:      BFile;
      ExtData:     ARRAY[0..1] OF XlateFieldData;
      InputLine:   ARRAY[0..80] OF CHAR;
      IntSeq:      SequenceType;
      ModSeqs:     ARRAY['0'..'9'] OF SequenceType;
      ModeIsOK:    BOOLEAN;
      IOResult:    CARDINAL;
      Enough:      BOOLEAN;
      BlankLine:   BOOLEAN;
      LineNo:      CARDINAL;
      TErrorMsg:   StrAny;
      NilPntr:     XlateTablePointer;
      OK:          BOOLEAN;
      ResC:        ResCollectionType;
      KEYBOARDText: ARRAY[0..15] OF CHAR;
      SCREENText:   ARRAY[0..15] OF CHAR;
      INTERNALText: ARRAY[0..15] OF CHAR;
      NumbModes:    CARDINAL;
      MaxSMode:     CHAR;
      SType:        PSType;

   PROCEDURE PrepareError(ErIn: ARRAY OF CHAR);
      VAR
         Msg:      ARRAY[0..254] OF CHAR;
         C:        CARDINAL;
      BEGIN

(*RES OLD MSG 48
Translate Tables are now being Built: %0 %1.
*)

         IF LineNo <> 0 THEN
            C := 0;
            SWriteString(Msg,C,' (',0);
            SWriteCard(Msg,C,LineNo,0);
            SWriteString(Msg,C,')',0);
            MsgString(Msg,0);
         ELSE
            Msg[0] := 0C;
            MsgString(Msg,0);
         END;
         MsgString(ErIn,0);
         PutResWarning( (*RES REM INS*) 48 );
      END PrepareError;

PROCEDURE KeyAddIfAbsent( C : CHAR ; R : ARRAY OF CHAR ) ;
VAR
    p:     KeyQueuePointer;
    ch:    CHAR;
BEGIN
   WITH KeyXlateData['0']^ DO
      IF Data[C] = NIL THEN
         MakeNew(p,C);
         Data[C] := p
      END;
      WITH Data[C]^ DO
         IF IntSeq[0] = 0C THEN
            Str.Copy(IntSeq,R);
         END;
         IF ScrSeq[0] = 0C THEN
            Str.Copy(ScrSeq,R);
            ScrLen := Str.Length(R);
         END
      END;
   END;
END KeyAddIfAbsent;

PROCEDURE DoInsertions;
BEGIN
   IF (ExtData[0].Dir = '<') OR (ExtData[0].Dir = '>') THEN
(*RES OLD MSG 228
Do not Use the Keyboard to Specify the Direction Marker "%0".
*)
      MsgString(ExtData[0].Dir,0);
      GetResMessage( (*RES REM INS*) 228 , TErrorMsg);
      PrepareError(TErrorMsg);
      EndValue := FALSE;
      RETURN;
   END;
   IF (ExtData[1].Mode <> '*') AND (ExtData[1].Mode > MaxSMode) THEN
(*RES OLD MSG 229
Your Screen does not Accept the MODE "%0".
*)
      MsgString(ExtData[1].Mode,0);
      GetResMessage( (*RES REM INS*) 229 , TErrorMsg);
      PrepareError(TErrorMsg);
      EndValue := FALSE;
      RETURN;
   END;
   IF (ExtData[0].Dir <> '~') AND
   ((ExtData[1].Dir = ' ') OR (ExtData[1].Dir = '>')) THEN
      IF (NOT InsertKeyStrg(ExtData[0].Sqn, IntSeq, ExtData[1].Sqn,
      ExtData[1].ActLen,ExtData[1].Mode,ExtData[0].Mode,TErrorMsg)) THEN
         EndValue := FALSE;
         PrepareError(TErrorMsg);
         RETURN
      END
   END;
   IF (ExtData[1].Dir = ' ') OR (ExtData[1].Dir = '>') THEN
      IF NOT InsertXlateData(TempInt2Scr,'0',ExtData[1].Mode,
      IntSeq,ExtData[1].Sqn,ExtData[1].ActLen,
      UpdateEntry,TErrorMsg) THEN
         EndValue := FALSE;
         PrepareError(TErrorMsg);
         RETURN
      END;
   END;
   IF (ExtData[1].Dir = ' ') OR (ExtData[1].Dir = '<') THEN
      IF NOT InsertXlateData(Scr2Int,ExtData[1].Mode,'0',
      ExtData[1].Sqn,IntSeq,Str.Length(IntSeq),
      GiveError,TErrorMsg) THEN
         EndValue := FALSE;
         PrepareError(TErrorMsg);
         RETURN
      END;
   END;
END DoInsertions;

PROCEDURE InsertDefaultXType(Name: ARRAY OF CHAR): BOOLEAN;
BEGIN
   Str.Copy(InputLine,Name);
   IF NOT StandardizeFileName(InputLine,'.XDT') THEN
      ProgramErrorAndHalt('Problem with FILEText name')
   END;
   IF FindAndOpen(StandardSearchList,InputLine,FileID,ErrorMsg) THEN
      BClose(FileID,IOResult);
      RETURN FALSE;
   ELSE
      OK := AddNewXlateListEntry(Name,Int2Scr,Scr2Int);
      RETURN TRUE;
   END;
END InsertDefaultXType;

BEGIN  (* InitialTranslationData *)
(*RES OLD DTA 3
KEYBOARD SCREEN FILE PRINTER INTERNAL MODE
*)
   Initialize;
   InitializeExt;

   GetDataArray( (*RES REM INS*) 3, ResC);

   OK := GetNextDataArrayStringItem(ResC,KEYBOARDText);
   OK := GetNextDataArrayStringItem(ResC,SCREENText);
   OK := GetNextDataArrayStringItem(ResC,FILEText);
   OK := GetNextDataArrayStringItem(ResC,PRINTERText);
   OK := GetNextDataArrayStringItem(ResC,INTERNALText);
   OK := GetNextDataArrayStringItem(ResC,MODEText);

   ReleaseCollection(ResC);

   InitialXlateData(TempInt2Scr);

   FOR C := '0' TO '9' DO ModSeqs[C] := '' END;

   EndValue := TRUE;
   LineNo := 0;
   IF NOT FindAndOpen(StandardSearchList,XlatTablDatFileTag,FileID,ErrorMsg) THEN
      PrepareError(ErrorMsg);
      BClose(FileID,IOResult);
      RETURN FALSE
   END;

   MaxSMode := '0';
   IF ExtendedAvailable(SType, NumbModes) THEN
      IF NumbModes > 1 THEN MaxSMode := '1' END;
   END;

   NumbModes := 0;
   Str.Copy(ExtData[0].DevName,KEYBOARDText);
   Str.Copy(ExtData[1].DevName,SCREENText);
   ExtData[0].LenOK := FALSE;
   ExtData[1].LenOK := FALSE;

   WHILE ReadLine(FileID,InputLine,Enough,IOResult) DO
(*    WriteString('Read Line:');
      WriteString(InputLine);
      WriteLn;                        *)

      INC(LineNo);
      IF LineIsMode(InputLine,KEYBOARDText,ModeIsOK,C,IntSeq,TErrorMsg) THEN
         IF NOT ModeIsOK THEN
            PrepareError(TErrorMsg);
            EndValue := FALSE;
         ELSIF ModSeqs[C][0] <> 0C THEN
(*RES OLD MSG 230
A Second Definition for Keyboard MODE "%0" was given.
*)
            MsgString(C,0);
            GetResMessage( (*RES REM INS*) 230 , TErrorMsg);
            PrepareError(TErrorMsg);
            EndValue := FALSE;
         ELSE
            Str.Copy(ModSeqs[C],IntSeq);
            INC(NumbModes);
         END;
      ELSIF NOT Line2Sequences(InputLine,BlankLine,IntSeq,ExtData,TErrorMsg) THEN
         EndValue := FALSE;
         PrepareError(TErrorMsg);
      ELSIF NOT BlankLine THEN
         DoInsertions;
      END;
   END;  (* WHILE ReadLine(FileID,InputLine,Enough,IOResult) DO *)

   LineNo := 0; (* In case error message still required *)
   IF IOResult = InsufficientData THEN
      BClose(FileID,IOResult);
      CA[1] := 0C;
      FOR C := ' ' TO '~' DO
         CA[0] := C;
         KeyAddIfAbsent(C,CA);
         AddIfAbsent(TempInt2Scr,C,CA);
         AddIfAbsent(Scr2Int,C,CA);
      END;

(* Now adding mode transitions for Keyboard *)

      IF NumbModes > 0 THEN
         FOR C := '0' TO '9' DO
            IF KeyXlateData[C] <> NIL THEN
               IF ModSeqs[C][0] = 0C THEN
                  (*RES OLD MSG 231
                  No Translation Sequence was given for Keyboard MODE "%0".
                  *)
                  MsgString(C,0);
                  GetResMessage( (*RES REM INS*) 231 , TErrorMsg);
                  PrepareError(TErrorMsg);
                  EndValue := FALSE;
               ELSE
                  FOR C2 := '0' TO '9' DO
                     IF KeyXlateData[C2] <> NIL THEN
                        IF NOT InsertKeyMode(C2,C,ModSeqs[C2],TErrorMsg) THEN
                           PrepareError(TErrorMsg);
                           EndValue := FALSE;
                         END;
                     END; (* IF KeyXlateData[C2] <> NIL THEN *)
                  END; (* FOR C2 := '0' TO '9' DO *)
               END; (* IF ModSeqs[C][0] = 0C THEN ... ELSE *)
            END; (* IF KeyXlateData[C] <> NIL THEN ... *)
         END; (* FOR C := '0' TO '9' DO ... *)
      END; (* IF NumbModes > 1 THEN ... *)

(* Now adding magic codes for handling of TABs and Enhanced Chars
   for Int2Scr only   j.b. *)

      CA[0] := ScrEsc;
      CA[1] := ScrTab;
      AddIfAbsent(TempInt2Scr,IntTab,CA);

      IF MaxSMode <> '0' THEN
         CA[1] := ScrChar1;
         IF NOT InsertXModeData(TempInt2Scr,Scr2Int,'0',CA,GiveError,TErrorMsg) THEN
            PrepareError(TErrorMsg);
            EndValue := FALSE;
         END;

         CA[1] := ScrChar2;
         IF NOT InsertXModeData(TempInt2Scr,Scr2Int,'1',CA,GiveError,TErrorMsg) THEN
            PrepareError(TErrorMsg);
            EndValue := FALSE;
         END
      END;

      CA[0] := 0C;
      AddIfAbsent(TempInt2Scr,IntEnhOn,CA);
      AddIfAbsent(TempInt2Scr,IntEnhOff,CA);

      Int2Scr := TempInt2Scr ;
      InitialXlateData(NilPntr);
      OK := AddNewXlateListEntry(SCREENText,Int2Scr,Scr2Int);
      IF OK THEN
         OK := AddNewXlateListEntry(INTERNALText,NilPntr,NilPntr);
      END;
      IF OK THEN
         IF InsertDefaultXType(FILEText) THEN
            Int2File := Int2Scr;
            File2Int := Scr2Int;
         ELSE
            IF NOT FindXlateTable(FILEText, To, Int2File, TErrorMsg) THEN
               PrepareError(TErrorMsg);
               EndValue := FALSE
            ELSIF NOT FindXlateTable(FILEText, From, File2Int, TErrorMsg) THEN
               PrepareError(TErrorMsg);
               EndValue := FALSE
            END;
         END;
      END;
      IF OK THEN
         IF InsertDefaultXType(PRINTERText) THEN
            Int2Prt := Int2Scr
         ELSE
            IF NOT FindXlateTable(PRINTERText, To, Int2Prt, TErrorMsg) THEN
               PrepareError(TErrorMsg);
               EndValue := FALSE
            END;
         END;
      END;
      IF NOT OK THEN
(*RES OLD MSG 49
There is Insufficient Memory to Handle Translate Tables.
*)
         GetResMessage( (*RES REM INS*) 49, TErrorMsg);
         PrepareError(TErrorMsg);
         EndValue := FALSE;
      END;
   ELSE
      EndValue := FALSE;
      IOErrorMessage(IOResult,TErrorMsg);
      BClose(FileID,IOResult);
(*RES OLD MSG 50
File %0: %2
*)
      ErrorMsg := XlatTablDatFileTag;
      MsgString(ErrorMsg,0);
      MsgString(TErrorMsg,0);
      GetResMessage( (*RES REM INS*) 50, TErrorMsg);
      PrepareError(TErrorMsg);
   END;

   RETURN EndValue
END InitialTranslationData;

VAR
   C:    CHAR;
BEGIN
   NEW(KeyXlateData['0']);
   WITH KeyXlateData['0']^ DO
      FOR C := 1C TO 377C DO
         Data[C] := NIL;
      END
   END;
   FOR C := '1' TO '9' DO KeyXlateData[C] := NIL END;
   CurMode := '0';
   FieldEditingAttr := SpecialAttr;
   FieldNotEditingAttr := BoldAttr;
   CurrentInputQueue := NIL ;  (* m.s. *)
   HoldSize := 0 ;
   ReReadStart := 0 ;
   LastLength := 0 ;
END KeyTranslation .
