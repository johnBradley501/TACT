IMPLEMENTATION MODULE ResText;
(* copyright (c) 1989-96 John Bradley, Lidio Presutti, University of Toronto *)

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


FROM Utils IMPORT ALLOCATE, DEALLOCATE,
                  ConstStr;
FROM StringIO IMPORT SWriteString;
FROM GlobalDefs IMPORT StrAny;
FROM Translations IMPORT XWrNXlate, XWrLn, OutFile;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResBase IMPORT FilePos;
FROM ResCollection IMPORT
   (* type *) ResCollectionType, ResCollectionData,
   (* proc *) GetCollection, NextColItem, PrevColItem, ReleaseCollection;
FROM ResArray IMPORT
   (*type*) ResDataType,ResArrayError,
   (*proc*) FindResource;

TYPE
   TextItemData = RECORD
      NumbBlkLines:    CHAR; (* as 1 character CARDINAL *)
      NumbOfBlanks:    CHAR; (* as 1 character CARDINAL *)
      Data:            StrAny;
   END;
   TextItemPntr = POINTER TO TextItemData;

   TextColData = RECORD
      ResCol:      ResCollectionType;
      Count:       CARDINAL;
      ColData:     TextItemData;
(*    HLine:       TextData; *)
   END;
   TextColPntr = POINTER TO TextColData;

PROCEDURE ResError;
BEGIN
   ProgramErrorAndHalt('Resource Error within ResText')
END ResError;

PROCEDURE StartTextCol(TextID:   CARDINAL;
                   VAR TextCol:  TextColPntr);
VAR
   Loc:    FilePos;
   size:   CARDINAL;
   Error:  ResArrayError;
   RefData: ARRAY[0..255] OF BYTE; (* stored in Help Res's, but not used here *)
BEGIN
   ALLOCATE(TextCol,SIZE(TextColData));
   IF NOT FindResource(HelpResource,TextID,Loc,Error) THEN ResError END;
   WITH TextCol^ DO
      IF NOT GetCollection(ResCol,Loc) THEN ResError END;
      Count := 1;
      ColData.NumbBlkLines := 0C; (* to force data fetch first time *)
      IF NOT NextColItem(ResCol,RefData,size) THEN ResError END;
   END;
END StartTextCol;

PROCEDURE DiscardTextCol(VAR OldCol:  TextColPntr);
BEGIN
   DEALLOCATE(OldCol^.ResCol,SIZE(ResCollectionData));
   DEALLOCATE(OldCol,SIZE(TextColData));
   OldCol := NIL;
END DiscardTextCol;

PROCEDURE MakeTextLine(VAR Line: TextItemData;
                       VAR Result: ARRAY OF CHAR);
VAR
   lpos:     CARDINAL;
BEGIN
   WITH Line DO
      lpos := ORD(NumbOfBlanks);
      IF lpos > 0 THEN ConstStr(' ',ORD(NumbOfBlanks),Result) END;
      SWriteString(Result,lpos,Data,0);
   END;
END MakeTextLine;

PROCEDURE NextTextColItem(VAR Item:      TextColData;
                          VAR Result:    ARRAY OF CHAR): BOOLEAN;
VAR size:  CARDINAL;
BEGIN
   WITH Item DO
      IF Count > ORD(ColData.NumbBlkLines) THEN
         IF NOT NextColItem(ResCol,ColData,size) THEN RETURN FALSE END;
         Count := 0;
      END;
      IF Count = ORD(ColData.NumbBlkLines) THEN MakeTextLine(ColData,Result)
                                         ELSE Result[0] := 0C END;
      INC(Count);
   END;
   RETURN TRUE;
END NextTextColItem;

PROCEDURE OutputTextItem(ID: CARDINAL);
VAR
   TextCol:    TextColPntr;
   txt:        StrAny;
   IOresult:   CARDINAL;
BEGIN
   StartTextCol(ID, TextCol);
   WHILE (NextTextColItem(TextCol^, txt)) DO
      IF (txt[0] <> 0C) THEN XWrNXlate(OutFile, txt, IOresult) END;
      XWrLn(OutFile, IOresult);
   END;
   DiscardTextCol(TextCol);
END OutputTextItem;

END ResText.
