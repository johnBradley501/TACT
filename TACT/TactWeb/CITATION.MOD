IMPLEMENTATION MODULE CitationTools;
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


IMPORT Str ;
FROM HyperBase IMPORT HRecPntr;
FROM Translations IMPORT XlateTablePointer, LengthDataType, XlateLine,
     LenD, CurrentModeType, IntEnhOn, IntEnhOff;
FROM TACTInit IMPORT DoBackingLink;
FROM LineBase IMPORT
  (* type *) LineDataType,
  (* procs*) GetLine, GetNextLine, GetPrevLine;
FROM Utils IMPORT ConstStr;
FROM GlobalDefs IMPORT StrAny ;
FROM DisplayDialog IMPORT
  (* type *) DisplayType,
  (* vars *) DisplayData(*, CurrentDisplay*);
FROM WWWUtils IMPORT MakeQueryLink;

TYPE
   TextPtr = POINTER TO ARRAY[0..1000] OF CHAR;

VAR
   Save:           StrAny;
   TEXT:           StrAny;
   XLine:          StrAny;

PROCEDURE GetOneLineCitation(LinePtr:    HRecPntr;
                             PosPtr:     HRecPntr;
                             Xlate:      XlateTablePointer;
                             NumbBefore: CARDINAL;
                             NumbAfter:  CARDINAL;
                         VAR Answer:     ARRAY OF CHAR);
VAR
   Result:         StrAny;
   back,forward:   LineDataType;
   ED:             BOOLEAN;
   Len,Offset:     CARDINAL;
   ALen:           CARDINAL;
   NumbSeq:        CARDINAL;
   OffsetChar:     CHAR;
   TotalLen:       CARDINAL;
   i,j,k:          CARDINAL;
   cm:             CurrentModeType;
   rest:           TextPtr;
   LinkText:       StrAny;

PROCEDURE RemoveFrontBlanks(VAR Line: ARRAY OF CHAR);
VAR i:   CARDINAL;
BEGIN
   i := 0;
   WHILE (Line[i] = ' ') DO INC(i) END;
   IF i <> 0 THEN Str.Delete(Line, 0,i) END;
END RemoveFrontBlanks;

PROCEDURE RemoveBlanks(VAR Line:  ARRAY OF CHAR);
VAR i:   CARDINAL;
BEGIN
   RemoveFrontBlanks(Line);
   i := Str.Length(Line);
   IF i = 0 THEN (* blank line *) RETURN END ;
   REPEAT DEC(i) UNTIL (i = 0) OR (Line[i] <> ' ');
   IF i < HIGH(Line) THEN Line[i+1] := 0C END;
END RemoveBlanks;

BEGIN
(* first, we get the line that contains LinePtr *)

   GetLine(LinePtr,Result,ALen,Offset,back);
   forward := back;

(* next, we take that portion of the line that appears before LinePtr *)

   IF Offset <> 0 THEN
      Str.Slice(Save,Result,Offset,999);
      Result[Offset] := 0C;
(*    by calling XlateLine we find out how many positions in the final
      translated format (say, for the screen) it will take up *)

      RemoveFrontBlanks(Result);
      cm.ModeIn := '0'; cm.ModeOut := '0';
      XlateLine(Xlate,'?',Result,cm, ALen, LenD,NumbSeq,ED,XLine);
      TotalLen := ALen;
   ELSE
      Str.Copy( Save, Result);
      Result[0] := 0C;
      TotalLen := 0;
   END;

   i := 0;


(* now we add previous lines to the front until we have more than
   enough characters for the length we need to provide (NumbBefore *)

   WHILE TotalLen < NumbBefore DO
(*    IF ( CurrentDisplay <> KWIC ) OR DisplayData[KWIC].DisplayBar THEN (* m.s. *) *)
      IF DisplayData[KWIC].DisplayBar THEN (* m.s. *)
         Str.Insert( Result, ' | ', 0);
         INC(TotalLen,3);
      ELSE
         Str.Insert( Result, ' ', 0 ) ; (* m.s. *)
         INC(TotalLen) ;  (* m.s. *)
      END ;
      IF TotalLen < NumbBefore THEN
         IF GetPrevLine(back, TEXT, ALen) THEN
            RemoveBlanks(TEXT);
         ELSE
            ALen := NumbBefore - TotalLen;
            ConstStr(' ',NumbBefore - TotalLen,TEXT);
         END;
         Str.Insert( Result, TEXT, 0);
         cm.ModeIn := '0'; cm.ModeOut := '0';
         XlateLine(Xlate,'?',TEXT,cm, ALen, LenD,NumbSeq,ED,XLine);
         INC(TotalLen,ALen)
      END;
   END;

(* Now we edge forward until TotalLen is exactly (if possible) NumbBefore *)

   i := 0;
   j := 0;
   WHILE (TotalLen > NumbBefore) DO
      DEC(TotalLen,LenD[j].ApprOut);
      INC(i,LenD[j].Int);
      INC(j)
   END;

(* now we find out how far forward we must go for the first blank
   following this position (the text we pass over must be blanked out
   in the resulting output string *)

   k := i;
   WHILE (j< NumbSeq) AND ((LenD[j].Int <> 1) OR (Result[i] <> ' ')) DO
      DEC(TotalLen,LenD[j].ApprOut);
      INC(i,LenD[j].Int);
      INC(j)
   END;

   Str.Delete(Result,0,i);
   ConstStr(' ',NumbBefore - TotalLen,TEXT);
   Str.Insert( Result, TEXT, 0);

   RemoveBlanks(Save);
   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine(Xlate,'?',Save,cm, ALen, LenD,NumbSeq,ED,XLine);
   TotalLen := ALen;
(* IF ( CurrentDisplay <> KWIC ) OR DisplayData[KWIC].DisplayBar THEN (* m.s. *) *)
   IF DisplayData[KWIC].DisplayBar THEN (* m.s. *)
      DEC(NumbAfter); (* to allow insertion of ">" below .. j.b. *)
   END ;
   WHILE TotalLen < NumbAfter DO
      IF GetNextLine(forward, TEXT, ALen) THEN
         RemoveBlanks(TEXT);
      ELSE
         ALen := NumbAfter - TotalLen;	(* *LP* *)
         ConstStr(' ', ALen, TEXT);	(* *LP* *)
      END;
(*    IF ( CurrentDisplay <> KWIC ) OR DisplayData[KWIC].DisplayBar THEN (* m.s. *) *)
      IF DisplayData[KWIC].DisplayBar THEN (* m.s. *)
         Str.Concat( TEXT,' | ',TEXT);
      ELSE
         Str.Concat( TEXT, ' ', TEXT ) ; (* m.s. *)
      END ;
      Str.Append( TEXT,' ' );
      Str.Append(Save,TEXT);
      cm.ModeIn := '0'; cm.ModeOut := '0';
      XlateLine(Xlate,'?',TEXT,cm, ALen, LenD,NumbSeq,ED,XLine);
      INC(TotalLen,ALen)
   END;

   i := Str.Length(Save);
   j := NumbSeq-1;
   WHILE (TotalLen > NumbAfter) AND (j > 0) DO
      DEC(TotalLen,LenD[j].ApprOut);
      DEC(i,LenD[j].Int);
      DEC(j)
   END;

   k := i;
   WHILE (j<> 0) AND ((LenD[j].Int <> 1) OR (Save[i] <> ' ')) DO
      DEC(i,LenD[j].Int);
      DEC(j)
   END;
   Save[i] := 0C;

   i := Str.Pos(Save, ' ');
   Save[i] := 0C;
   IF DoBackingLink THEN MakeQueryLink(PosPtr, 'P', Save, LinkText);
   ELSE
      Str.Copy(LinkText, 'ú<Bú>');
      Str.Append(LinkText, Save);
      Str.Append(LinkText,'ú</Bú>');
   END;
   Str.Append(Result, LinkText);
   Save[i] := ' ';
   rest := ADR(Save[i]);
   Str.Concat( Answer, Result, rest^ );
END GetOneLineCitation;

PROCEDURE FillOutWithCitation(LinePtr:    HRecPntr;
                              PosPtr:     HRecPntr;
                              Xlate:      XlateTablePointer;
                              ScrLen:     CARDINAL;
                              TextPos:    CARDINAL;
                          VAR string:     ARRAY OF CHAR);
VAR
   Temp:    StrAny;
   ALen:    CARDINAL;
   NumbSeq: CARDINAL;
   ED:      BOOLEAN;
   NumbB:   CARDINAL;
   NumbA:   CARDINAL;
   cm:      CurrentModeType;
BEGIN
   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine(Xlate,'?',string,cm, ALen, LenD,NumbSeq,ED,Temp);
   INC(ALen,2); (* for two blanks to separate ref from citation *)

   IF ALen > TextPos THEN
      NumbB := 0;
   ELSE
      NumbB := TextPos - ALen;
   END;
   NumbA := ScrLen - ALen - NumbB;
   GetOneLineCitation(LinePtr,PosPtr,Xlate,NumbB,NumbA,Temp);

   Str.Append(string,'  ');
   Str.Append(string,Temp);
END FillOutWithCitation;

END CitationTools.
