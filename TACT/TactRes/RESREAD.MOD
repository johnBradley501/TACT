MODULE ResRead;

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

FROM SYSTEM IMPORT BYTE,ADDRESS,SIZE,ADR;
IMPORT Lib, Str, FIO, IO;
FROM FileIO IMPORT File,FilePos;
FROM Storage IMPORT ALLOCATE,DEALLOCATE;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteChar;

FROM ResTranslations IMPORT CurrentModeType, XlateLine, Int2File;
FROM ResBase IMPORT
   (*var*)  ResourceOpen, ResourceFile, NullPos,
   (*proc*) OpenResourceFile, CloseResourceFile,
            ReadResourceBase, ReadResRecord, ReadResString;

FROM ResArray IMPORT
   (*type*) ResDataType,ResourceArray,ResourceArrayPntr,
            ResArrayError,ScanActionProcedure,
   (*var*)  ResourcePntrs,ResourceName,
   (*proc*) FindResource,ScanResources;

FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) GetCollection, NextColItem, PrevColItem, ReleaseCollection;

FROM ResHelp IMPORT
  (* const *) MaxHelpRefs,
  (* types *) HelpPntr, HelpData, HelpRef, HelpRefColl;

FROM Utils IMPORT
 (* type *) BResultType,
 (* vars *) StandardSearchList,
 (* proc *) UpcaseStr,ConstStr,StandardizeFileName,GetEnv;

(* FROM ResManUtils IMPORT IOErrorMessage; *)
FROM ResTranslations IMPORT SetupTranslations;

CONST
   Version = '3.0';
   MaxNumberArraySize = 8096; (* words *)
   BufSize = 2048;

TYPE
    CharStringPntr = POINTER TO ARRAY[0..2048] OF CHAR;

VAR
    InputFileName:    ARRAY[0..80] OF CHAR;
    OutputFileName:   ARRAY[0..80] OF CHAR;
    OutputFile:       FIO.File;
    OutputBuffer:     ARRAY[0..BufSize-1] OF BYTE;
    Result:           BResultType;
    enough:           BOOLEAN;
    i:                ResDataType;
    lo,hi:            CARDINAL;
    er:               ResArrayError;
    HexChars:         ARRAY[0..15] OF CHAR;
    GivenResourceName:ARRAY[0..15] OF CHAR;
    CurParm:          CARDINAL;

(*
PROCEDURE OutputErrorMessage(TypeText:    ARRAY OF CHAR;
                            Result:      BResultType);
VAR     ResultText:   ARRAY[0..50] OF CHAR;
BEGIN
    FIO.WrStr(FIO.ErrorOutput,'**ERROR** ');
    FIO.WrStr(FIO.ErrorOutput,TypeText);
    FIO.WrStr(FIO.ErrorOutput,' ');
    FIO.WrStr(FIO.ErrorOutput,OutputFileName);
    FIO.WrStr(FIO.ErrorOutput,': ');
    IOErrorMessage(Result,ResultText);
    FIO.WrStr(FIO.ErrorOutput,ResultText);
    FIO.WrLn(FIO.ErrorOutput);
    CloseResourceFile;
    HALT;
END OutputErrorMessage;
*)

PROCEDURE ResErrorMessage(TypeText: ARRAY OF CHAR);
BEGIN
    FIO.WrStr(FIO.ErrorOutput,'**ERROR** ');
    FIO.WrStr(FIO.ErrorOutput,TypeText);
    FIO.WrStr(FIO.ErrorOutput,' ');
    FIO.WrStr(FIO.ErrorOutput,InputFileName);
    CloseResourceFile;
    HALT;
END ResErrorMessage;

PROCEDURE WriteLine(Text: ARRAY OF CHAR);
BEGIN
   FIO.WrStr(OutputFile, Text);
   FIO.WrLn(OutputFile);
END WriteLine;

PROCEDURE MessageFolder(ResData: CharStringPntr; i: CARDINAL);
VAR
    ExtText:   ARRAY[0..255] OF CHAR;
    String:    CharStringPntr;
    j:         CARDINAL;
    cm:        CurrentModeType;
BEGIN
    cm.ModeIn := '0'; cm.ModeOut := '0';
    String := ResData;
    WHILE (i > 80) DO
        j := 80;
        WHILE (j > 0) AND (String^[j] <> ' ') DO DEC(j) END;
        String^[j] := 0C;
        XlateLine(Int2File, '?', String^, cm, ExtText);
        WriteLine(ExtText);
(*      IF Result <> OK THEN
             OutputErrorMessage('Writing',Result)
        END;
*)
        String := ADR(String^[j+1]);
        i := Str.Length(ResData^);
    END;
    XlateLine(Int2File, '?', String^, cm, ExtText);
    WriteLine(ExtText);
(*  IF Result <> OK THEN
         OutputErrorMessage('Writing',Result)
    END;
*)
END MessageFolder;

PROCEDURE HandleMessage(Loc:   FilePos);
VAR
    ResData:   CharStringPntr;
    size,i:    CARDINAL;

BEGIN
    ResData := NIL;
    IF NOT ReadResourceBase(0,Loc,ResData,size) THEN
         ResErrorMessage('In HandleMessage')
    END;
    i := Str.Length(ResData^);
    MessageFolder(ResData,i);
    DEALLOCATE(ResData,size);
END HandleMessage;

PROCEDURE HandleChoice(Loc:   FilePos);
VAR
    ResData:   CharStringPntr;
    String:    CharStringPntr;
    size,i:    CARDINAL;
    ChoiceList: ARRAY[0..255] OF CHAR;

BEGIN
    ResData := NIL;
    IF NOT ReadResourceBase(0,Loc,ResData,size) THEN
         ResErrorMessage('In HandleChoice')
    END;
    i := Str.Length(ResData^);
    MessageFolder(ResData,i);

    String := ADR(ResData^[i]);
    String^[0] := '=';
    WriteLine(String^);
(*  IF Result <> OK THEN
         OutputErrorMessage('Writing',Result)
    END;
*)
    DEALLOCATE(ResData,size);
END HandleChoice;

PROCEDURE HandlePanel(Loc:   FilePos);
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
VAR
   ResC:   ResCollectionType;
   PanelSize:   CARDINAL;
   size:  CARDINAL;
   PanelText: ARRAY[0..NoScreenLines-1] OF ARRAY[0..NoCharPositions-1] OF CHAR;
   LineSize: ARRAY[0..NoScreenLines-1] OF CARDINAL;
   line,col:  CARDINAL;
   len:       CARDINAL;
   TextEntry:   TextEntryType;
   FieldEntry:  FieldEntryType;
   TxtOut:  ARRAY[0..NoCharPositions-1] OF CHAR;
   cm:       CurrentModeType;

PROCEDURE MakeFieldDisplay(ID: CARDINAL;
                       VAR len: CARDINAL;
                       VAR line: ARRAY OF CHAR);
VAR  lpos:  CARDINAL;
     xpos:  CARDINAL;
BEGIN
   lpos := 1;
   line[0] := MarkerChar;
   SWriteCard(line,lpos,ID,0);
   IF lpos > len THEN
      Str.Insert(line,'|',len);
      INC(lpos)
   ELSE
      xpos := lpos;
      FOR lpos := xpos TO len-1 DO line[lpos] := FieldChar END;
      lpos := len;
      line[len] := 0C;
   END;
   len := lpos;
END MakeFieldDisplay;

BEGIN
   IF NOT GetCollection(ResC,Loc) THEN
       ResErrorMessage('Reading ResCollection')
   END;
   size := SIZE(PanelSize);
   IF NOT NextColItem(ResC,PanelSize,size) THEN
       ResErrorMessage('Unexpected empty collection')
   END;
   FOR line := 0 TO NoScreenLines-1 DO
      LineSize[line] := 0;
      FOR col := 0 TO NoCharPositions-1 DO PanelText[line][col] := ' ' END
   END;

   IF NOT NextColItem(ResC,TextEntry,size) THEN
       ResErrorMessage('Unexpected End -- before first text')
   END;
   WHILE TextEntry.Text[0] <> 0C DO
      WITH TextEntry DO
         line := ORD(YPos);
         col := ORD(XPos);
         cm.ModeIn := '0'; cm.ModeOut := '0';
         XlateLine(Int2File, '?', Text, cm, TxtOut);
         len := Str.Length(TxtOut);
         Lib.Move(ADR(TxtOut),ADR(PanelText[line][col]),len);
         IF len+col > LineSize[line] THEN LineSize[line] := len+col END;
      END;
      IF NOT NextColItem(ResC,TextEntry,size) THEN
          ResErrorMessage('Unexpected End -- during text')
      END;
   END;

   WHILE NextColItem(ResC,FieldEntry,size) DO
         WITH FieldEntry DO
         line := ORD(YPos);
         col := ORD(XPos);
         len := ORD(Len);
         MakeFieldDisplay(ORD(ID),len,TxtOut);
         Lib.Move(ADR(TxtOut),ADR(PanelText[line][col]),len);
         IF len+col > LineSize[line] THEN LineSize[line] := len+col END;
      END;
   END;

   FOR line := 0 TO PanelSize-1 DO
      PanelText[line][LineSize[line]] := 0C;
      WriteLine(PanelText[line]);
(*    IF Result <> OK THEN
         OutputErrorMessage('Writing',Result)
      END;
*)
   END;
   ReleaseCollection(ResC);
END HandlePanel;

PROCEDURE HandleDataArray(Loc:   FilePos);
VAR
   ResC:   ResCollectionType;
   UnCd:   ARRAY[0..255] OF CHAR;
   Cd:     ARRAY[0..255] OF CHAR;
   Line:   ARRAY[0..255] OF CHAR;
   ELine:  ARRAY[0..255] OF CHAR;
   lpos:   CARDINAL;
   sizein: CARDINAL;
   sizeout:CARDINAL;
   cm:     CurrentModeType;

PROCEDURE EncodeItem(UnCd: ARRAY OF CHAR;
                     szin: CARDINAL;
                 VAR Cd: ARRAY OF CHAR;
                 VAR szout: CARDINAL);

VAR i,j:   CARDINAL;
    InHex: BOOLEAN;
BEGIN
   i := 0; j := 0;
   InHex := FALSE;
   FOR i := 0 TO szin-1 DO

       (* Note range: Space must be encoded in HEX, and "!" is
          a meta-character here, also must be in HEX *)

       IF (UnCd[i] <= '!') OR (UnCd[i] > '~') THEN
          IF NOT InHex THEN
             InHex := TRUE;
             Cd[j] := '!';
             INC(j);
          END;
          Cd[j] := HexChars[ORD(UnCd[i]) DIV 16];
          Cd[j + 1] := HexChars[ORD(UnCd[i]) MOD 16];
          j := j + 2;
       ELSE
          IF InHex THEN
             InHex := FALSE;
             Cd[j] := '!';
             INC(j);
          END;
          Cd[j] := UnCd[i];
          INC(j)
       END
   END;
   Cd[j] := 0C;
   szout := j
END EncodeItem;

PROCEDURE QuotableItem(UnCd: ARRAY OF CHAR;
                       szin: CARDINAL;
                   VAR Cd: ARRAY OF CHAR;
                   VAR szout: CARDINAL): BOOLEAN;
VAR
   i:              CARDINAL;
   FndBlnk:        BOOLEAN;
   FndSingleQuote: BOOLEAN;
   FndDoubleQuote: BOOLEAN;
   QuoteMark:      CHAR;
BEGIN
   FndBlnk := FALSE;
   FndSingleQuote := FALSE;
   FndDoubleQuote := FALSE;

   FOR i := 1 TO szin-1 DO
      IF (UnCd[i] < ' ') OR (UnCd[i] > '~') THEN RETURN FALSE
      ELSIF (UnCd[i] = ' ') THEN FndBlnk := TRUE
      ELSIF (UnCd[i] = '"') THEN FndDoubleQuote := TRUE
      ELSIF (UnCd[i] = "'") THEN FndSingleQuote := TRUE END
   END;

   IF FndDoubleQuote AND FndSingleQuote THEN RETURN FALSE END;
   IF FndSingleQuote THEN QuoteMark := '"'
                     ELSE QuoteMark := "'" END;

   IF FndBlnk THEN
      szout := 0;
      SWriteString(Cd,szout,QuoteMark,0);
      IF szin < HIGH(UnCd) THEN UnCd[szin] := 0C END;
      SWriteString(Cd,szout,UnCd,0);
      SWriteString(Cd,szout,QuoteMark,0);
   END;
   RETURN FndBlnk;
END QuotableItem;

BEGIN
   cm.ModeIn := '0'; cm.ModeOut := '0';
   IF NOT GetCollection(ResC,Loc) THEN
       ResErrorMessage('Reading ResCollection')
   END;
   lpos := 0;
   WHILE NextColItem(ResC,UnCd,sizein) DO
      IF NOT QuotableItem(UnCd,sizein,Cd,sizeout) THEN
         EncodeItem(UnCd,sizein,Cd,sizeout)
      END;

      IF (lpos > 0) AND (lpos + sizeout + 1 > 80) THEN
         XlateLine(Int2File, '?', Line, cm, ELine);
         WriteLine(Line);
         lpos := 0;
      ELSE
         SWriteChar(Line,lpos,' ',0);
      END;
      SWriteString(Line,lpos,Cd,0)
   END;
   XlateLine(Int2File, '?', Line, cm, ELine);
   WriteLine(Line);
   ReleaseCollection(ResC);
END HandleDataArray;

PROCEDURE  HandleNumberArray(Loc:   FilePos);
VAR
   Data:      POINTER TO ARRAY[0..MaxNumberArraySize-1] OF CARDINAL;
   size,i:    CARDINAL;
   NData:     CARDINAL;
   Line:      ARRAY[0..255] OF CHAR;
   lpos:      CARDINAL;
BEGIN
   Data := NIL;
   IF NOT ReadResourceBase(0,Loc,Data,size) THEN
        ResErrorMessage('In HandleMessage')
   END;
   NData := size DIV 2;
   lpos := 0;
   FOR i := 0 TO NData-1 DO
      IF (lpos > 0) AND (lpos > 72) THEN
         WriteLine(Line);
         lpos := 0;
      ELSE
         SWriteChar(Line,lpos,' ',0);
      END;
      SWriteCard(Line,lpos,Data^[i],0)
   END;
   WriteLine(Line);
   DEALLOCATE(Data,size);
END HandleNumberArray;

PROCEDURE  HandleHelpItem(Loc:   FilePos);
VAR
   Refs:    HelpRefColl;
   HData:   HelpData;
   ResC:    ResCollectionType;
   i:       CARDINAL;
   Line:    ARRAY[0..255] OF CHAR;
   ELine:   ARRAY[0..255] OF CHAR;
   lpos:    CARDINAL;
   cm:      CurrentModeType;
BEGIN
   cm.ModeIn := '0'; cm.ModeOut := '0';
   IF NOT GetCollection(ResC,Loc) THEN
       ResErrorMessage('Getting ResCollection')
   END;
   IF NOT NextColItem(ResC,Refs,i) THEN 
       ResErrorMessage('Reading header info in Help Item')
   END;
   Line[0] := '='; Line[1] := ' '; Line[2] := 0C;
   FOR i := 1 TO Refs.Size DO
      lpos := 2;
      WITH Refs.Data[i-1] DO
         SWriteChar(Line,lpos,TypedChar,0);
         SWriteChar(Line,lpos,' ',0);
         SWriteCard(Line,lpos,NextID,0);
         WriteLine(Line);
      END;
   END;
   WHILE NextColItem(ResC,HData,i) DO
      WITH HData DO
        FOR i := 1 TO ORD(NumbBlkLines) DO FIO.WrLn(OutputFile) END;
        lpos := ORD(NumbOfBlanks);
        IF lpos > 0 THEN ConstStr(' ',ORD(NumbOfBlanks),Line) END;
        SWriteString(Line,lpos,Data,0);
        XlateLine(Int2File, '?', Line, cm, ELine);
        WriteLine(ELine);
      END;
   END;
   ReleaseCollection(ResC);
END HandleHelpItem;

PROCEDURE HandleProc(ResType: ResDataType;
                     ItemNo:  CARDINAL;
                     Loc:     FilePos;
                 VAR er:      ResArrayError);
VAR    MPos:      CARDINAL;
       Msg:       ARRAY[0..80] OF CHAR;

BEGIN
    er := RAOK;
    MPos := 0;
    SWriteString(Msg,MPos,'(*RES OLD ',0);
    SWriteString(Msg,MPos,ResourceName[ResType],0);
    SWriteChar(Msg,MPos,' ',0);
    SWriteCard(Msg,MPos,ItemNo,0);
    WriteLine(Msg);
(*  IF Result <> OK THEN
         OutputErrorMessage('Writing',Result)
    END;
*)

    CASE ResType OF
      MessageResource:     HandleMessage(Loc) |
      MenuResource:        HandlePanel(Loc) |
      HelpResource:        HandleHelpItem(Loc) |
      ChoiceResource:      HandleChoice(Loc) |
      DataArrayResource:   HandleDataArray(Loc) |
      NumberArrayResource: HandleNumberArray(Loc)
    ELSE
      ResErrorMessage('This Type cannot be handled at present')
    END;

    WriteLine('*)');
(*
    IF Result <> OK THEN
         OutputErrorMessage('Writing',Result)
    END;
*)
END HandleProc;

PROCEDURE DoScan(i:     ResDataType;
                 lo,hi: CARDINAL);
BEGIN
   IF NOT ScanResources(i,lo,hi,HandleProc,er) THEN
       CASE er OF
         RANotOpen:     FIO.WrStr(FIO.ErrorOutput,': Resource File Not Open') |
         RATooHigh:     FIO.WrStr(FIO.ErrorOutput,': No Resources of this type Given') |
         RANotUsed:     FIO.WrStr(FIO.ErrorOutput,': Not Used Error Occurred') |
         RAActionError: FIO.WrStr(FIO.ErrorOutput,': Action Error Occurred')
       ELSE
           FIO.WrStr(FIO.ErrorOutput,': Unknown Error type returned')
       END
   END;
END DoScan;

PROCEDURE FindResType(Parm: ARRAY OF CHAR;
                  VAR Res:  ResDataType): BOOLEAN;
VAR   i:     ResDataType;
BEGIN
    FOR i := MIN(ResDataType) TO MAX(ResDataType) DO
        IF (Str.Compare(Parm,ResourceName[i]) = 0) THEN
            Res := i;
            RETURN TRUE
        END
    END;
    RETURN FALSE
END FindResType;

PROCEDURE GetParam(VAR Parm: ARRAY OF CHAR);
BEGIN
    INC(CurParm);
    IF CurParm <= Lib.ParamCount() THEN
       Lib.ParamStr(Parm,CurParm);
       FIO.WrStr(FIO.StandardOutput,Parm);
       FIO.WrLn(FIO.StandardOutput);
    ELSE IO.RdStr(Parm) END;
END GetParam;

PROCEDURE GetRange(VAR lo,hi: CARDINAL);
VAR
    NumbStr:        ARRAY[0..20] OF CHAR;
    NumbCard:       CARDINAL;
    done:           BOOLEAN;
BEGIN
    done := TRUE;
    REPEAT
       FIO.WrStr(FIO.StandardOutput,'  Starting Number: ');
       GetParam(NumbStr);
       UpcaseStr(NumbStr,NumbStr);
       IF (NumbStr[0] = 0C) OR ((NumbStr[0] = '.') AND (NumbStr[1] = 0C)) THEN
           FIO.WrStr(FIO.StandardOutput,'  *** Reading ALL');
           FIO.WrLn(FIO.StandardOutput);
           lo := 0;
           hi := 63000
       ELSIF (Str.Compare('ALL',NumbStr) = 0) THEN
           FIO.WrStr(FIO.StandardOutput,'  *** Reading ALL');
           FIO.WrLn(FIO.StandardOutput);
           lo := 0;
           hi := 63000
       ELSE
           NumbCard := CARDINAL(Str.StrToCard(NumbStr, 10, done));
           IF NOT done THEN
              FIO.WrStr(FIO.ErrorOutput,'Illegal Number given');
              FIO.WrLn(FIO.ErrorOutput);
           ELSE
              lo := NumbCard;
              FIO.WrStr(FIO.StandardOutput,'  Ending Number: ');
              GetParam(NumbStr);
              IF (NumbStr[0] = 0C) OR ((NumbStr[0] = '.') AND (NumbStr[1] = 0C)) THEN
                 FIO.WrStr(FIO.StandardOutput,'  *** reading TO END');
                 FIO.WrLn(FIO.StandardOutput);
                 hi := 63000
              ELSE
                 NumbCard := CARDINAL(Str.StrToCard(NumbStr, 10, done));
                 IF NOT done THEN
                    FIO.WrStr(FIO.ErrorOutput,'Illegal Number given');
                    FIO.WrLn(FIO.ErrorOutput);
                 ELSE
                    hi := NumbCard
                 END
              END
           END
       END;
    UNTIL done;
END GetRange;

BEGIN
    CurParm := 0;
    HexChars := '0123456789ABCDEF';
    IO.Prompt := FALSE;

    FIO.WrStr(FIO.StandardOutput,'RESREAD Version ');
    FIO.WrStr(FIO.StandardOutput,Version);
    FIO.WrLn(FIO.StandardOutput);

    GetEnv( 'TACTPATH', StandardSearchList );
    IF StandardSearchList[0] = 0C THEN GetEnv( 'PATH', StandardSearchList ) END;
    SetupTranslations();

    FIO.WrStr(FIO.StandardOutput,'Input Resource File Name: ');
    GetParam(InputFileName);
(*  FIO.WrLn(FIO.StandardOutput); *)
    IF NOT StandardizeFileName(InputFileName,'.RES') THEN
        FIO.WrStr(FIO.ErrorOutput,'Non-Standard File Name: ');
        FIO.WrStr(FIO.ErrorOutput,InputFileName);
        FIO.WrLn(FIO.ErrorOutput)
    END;
    IF NOT OpenResourceFile(InputFileName,Result) THEN
        ResErrorMessage('Opening')
    END;

    FIO.WrStr(FIO.StandardOutput,'Output Resource Listing File: ');
    GetParam(OutputFileName);
(*  FIO.WrLn(FIO.StandardOutput); *)
    IF NOT StandardizeFileName(OutputFileName,'.RSI') THEN
        FIO.WrStr(FIO.ErrorOutput,'Non-Standard File Name: ');
        FIO.WrStr(FIO.ErrorOutput,OutputFileName);
        FIO.WrLn(FIO.ErrorOutput)
    END;
    OutputFile := FIO.Create(OutputFileName);
    FIO.AssignBuffer(OutputFile, OutputBuffer);
(*  IF Result <> OK THEN OutputErrorMessage('Opening',Result) END; *)

    FIO.WrStr(FIO.StandardOutput,'Resource Type: ');
    GetParam(GivenResourceName);
(*  FIO.WrLn(FIO.StandardOutput); *)
    UpcaseStr(GivenResourceName,GivenResourceName);

    IF Str.Compare('ALL',GivenResourceName) = 0 THEN
       FOR i := MIN(ResDataType) TO MAX(ResDataType) DO
          FIO.WrStr(FIO.StandardOutput,'Doing Resource Type: ');
          FIO.WrStr(FIO.StandardOutput,ResourceName[i]);
          DoScan(i,0,9999);
          FIO.WrLn(FIO.StandardOutput);
       END
    ELSE
       WHILE (Str.Length(GivenResourceName) <> 1) OR
       (GivenResourceName[0] <> '.') DO

          IF NOT FindResType(GivenResourceName,i) THEN
             FIO.WrStr(FIO.ErrorOutput,'Resource Type: ');
             FIO.WrStr(FIO.ErrorOutput,GivenResourceName);
             FIO.WrStr(FIO.ErrorOutput,' not recognized.');
             FIO.WrLn(FIO.StandardOutput);
          ELSE
             GetRange(lo,hi);
             DoScan(i,lo,hi);
          END;
(*        FIO.WrLn(FIO.StandardOutput); *)
          FIO.WrStr(FIO.StandardOutput,'Resource Type: ');
          GetParam(GivenResourceName);
(*        FIO.WrLn(FIO.StandardOutput); *)
          UpcaseStr(GivenResourceName,GivenResourceName);
       END;
    END;

    FIO.Close(OutputFile);
    CloseResourceFile;
END ResRead.
