IMPLEMENTATION MODULE LineBase;

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

IMPORT Lib ;
FROM SYSTEM IMPORT ADR;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM DBData IMPORT
    (* vars  *) TDBFile, BeginText, EndTextRec, EndTextIdx;
FROM HyperDataModel IMPORT
  (* Const *) HyperLength,
  (* Types *) HyperData;
FROM HyperBase IMPORT
  (* TYPE *)  HRecPntr,
  (* PROC *)  GetBaseHyper, ReleaseBaseHyper;
FROM MemoryManagement IMPORT RealStoragePntr;

(* EolSymbol was copied from XlateUserInput rather than imported from
   it (to import it would have dragged in all sorts of VARs that are
   also defined there, but not needed in TACT   j.b. *)
CONST
  EolSymbol      = 15C ;  (* = ASCII CR *)

PROCEDURE FindFrontOfLine(GivenPos:  HRecPntr;
                      VAR ResultPos: HRecPntr;
                      VAR Offset:    CARDINAL);
VAR
   LineStrtRec:    CARDINAL;
   LineStrtIdx:    CARDINAL;
   HP:             RealStoragePntr;
BEGIN
   LineStrtRec := GivenPos.Rec;
   LineStrtIdx := GivenPos.Idx;

   Offset := 0;
   GetBaseHyper(LineStrtRec,HP,TDBFile);
   WHILE (LineStrtRec >= BeginText) AND
	 (HP^.HRecord.TextData[LineStrtIdx] <> EolSymbol) DO
       INC(Offset);
       IF LineStrtIdx = 0 THEN
          ReleaseBaseHyper(TDBFile,HP);
          DEC(LineStrtRec);
          GetBaseHyper(LineStrtRec,HP,TDBFile);
          LineStrtIdx := HyperLength-1;
       ELSE
          DEC(LineStrtIdx)
       END;
   END;
   INC(LineStrtIdx);
   IF LineStrtIdx >= HyperLength THEN
      LineStrtIdx := 0;
      INC(LineStrtRec);
   END;
   ReleaseBaseHyper(TDBFile,HP);

   ResultPos.Rec := LineStrtRec;
   ResultPos.Idx := LineStrtIdx;
END FindFrontOfLine;

PROCEDURE FindEndOfLine(GivenPos:  HRecPntr;
                    VAR ResultPos: HRecPntr);
VAR
   LineEndRec:    CARDINAL;
   LineEndIdx:    CARDINAL;
   HP:            RealStoragePntr;
BEGIN
   LineEndRec := GivenPos.Rec;
   LineEndIdx := GivenPos.Idx;

   GetBaseHyper(LineEndRec,HP,TDBFile);
   WHILE ((LineEndRec < EndTextRec) OR (LineEndIdx <= EndTextIdx))
	   AND (HP^.HRecord.TextData[LineEndIdx] <> EolSymbol) DO
       INC(LineEndIdx);
       IF LineEndIdx >= HyperLength THEN
          ReleaseBaseHyper(TDBFile,HP);
          INC(LineEndRec);
          GetBaseHyper(LineEndRec,HP,TDBFile);
          LineEndIdx := 0;
       END;
   END;
   IF LineEndIdx <> 0 THEN
      DEC(LineEndIdx);
   ELSE
      LineEndIdx := HyperLength-1;
      DEC(LineEndRec);
   END;
   ReleaseBaseHyper(TDBFile,HP);

   ResultPos.Rec := LineEndRec;
   ResultPos.Idx := LineEndIdx;
END FindEndOfLine;

PROCEDURE ExtractLine(StartPos:   HRecPntr;
                      EndPos:     HRecPntr;
                  VAR Text:       ARRAY OF CHAR;
                  VAR TextLen:    CARDINAL);
VAR
   TextPos :      CARDINAL;
   TextHigh:      CARDINAL;
   TextToMove:    CARDINAL;
   HP:            RealStoragePntr;
BEGIN
   TextLen := 0;
   TextPos := 0;
   TextHigh := HIGH(Text);
   WHILE (StartPos.Rec <= EndPos.Rec) AND (TextPos <= TextHigh) DO
       IF StartPos.Rec = EndPos.Rec THEN
          TextToMove := EndPos.Idx + 1 - StartPos.Idx
       ELSE
          TextToMove := HyperLength - StartPos.Idx;
       END;
       IF TextToMove + TextPos > TextHigh + 1 THEN
           TextToMove := TextHigh + 1 - TextPos
       END;

       IF TextToMove <> 0 THEN
          GetBaseHyper(StartPos.Rec,HP,TDBFile);
          Lib.Move(ADR(HP^.HRecord.TextData[StartPos.Idx]),ADR(Text[TextPos]),TextToMove);
          ReleaseBaseHyper(TDBFile,HP)
       END;

       INC(TextPos,TextToMove);
       INC(StartPos.Rec);
       StartPos.Idx := 0;
   END;
   IF TextPos <= TextHigh THEN Text[TextPos] := 0C END;
   TextLen := TextPos;
END ExtractLine;

PROCEDURE GetLine(LinePtr:    HRecPntr;
              VAR Text:       ARRAY OF CHAR;
              VAR Len:        CARDINAL;
              VAR Offset:     CARDINAL;
              VAR DataPtr:    LineDataType);
BEGIN
   FindFrontOfLine(LinePtr,DataPtr.Start,Offset);
   IF Offset > 0 THEN DEC(Offset) END;
   FindEndOfLine(LinePtr,DataPtr.End);
   ExtractLine(DataPtr.Start, DataPtr.End,Text,Len);
END GetLine;

PROCEDURE GetNextLine(VAR DataPtr:    LineDataType;
                      VAR Text:       ARRAY OF CHAR;
                      VAR Len:        CARDINAL): BOOLEAN;
VAR
   TempPtr:      HRecPntr;
BEGIN
(* Text[0] := 0C;	(* >> moved after test of failure *LP* << *)
   Len := 0;	*)
   TempPtr := DataPtr.End;
   TempPtr.Idx := TempPtr.Idx + 2;
   IF TempPtr.Idx >= HyperLength THEN;
      INC(TempPtr.Rec);
      TempPtr.Idx := TempPtr.Idx - HyperLength
   END;
   IF (TempPtr.Rec > EndTextRec) OR
	((TempPtr.Rec = EndTextRec) AND (TempPtr.Idx > EndTextIdx)) THEN
      RETURN FALSE
   END;
   Text[0] := 0C;
   Len := 0;
   DataPtr.Start := TempPtr;
   FindEndOfLine(TempPtr,DataPtr.End);
   ExtractLine(DataPtr.Start, DataPtr.End,Text,Len);
   RETURN TRUE;
END GetNextLine;

PROCEDURE GetPrevLine(VAR DataPtr:    LineDataType;
                      VAR Text:       ARRAY OF CHAR;
                      VAR Len:        CARDINAL): BOOLEAN;
VAR
   TempPtr:      HRecPntr;
   dummy:        CARDINAL;
BEGIN
(* Text[0] := 0C;	(* >> moved after test of failure *LP* << *)
   Len := 0;	*)
   TempPtr := DataPtr.Start;
   IF TempPtr.Idx >= 2 THEN
      TempPtr.Idx := TempPtr.Idx - 2
   ELSE
      DEC(TempPtr.Rec);
      TempPtr.Idx := HyperLength + TempPtr.Idx - 2
   END;
   IF (TempPtr.Rec < BeginText) THEN RETURN FALSE END;
   Text[0] := 0C;
   Len := 0;
   DataPtr.End := TempPtr;
   FindFrontOfLine(TempPtr,DataPtr.Start,dummy);
   ExtractLine(DataPtr.Start, DataPtr.End,Text,Len);
   RETURN TRUE;
END GetPrevLine;

END LineBase.
