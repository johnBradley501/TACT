IMPLEMENTATION MODULE ErrorBase;
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

(*$V-*)

(*V1=Production *)
(*V2=Debug *)

FROM SYSTEM IMPORT ADR;
IMPORT Str;
FROM StringIO IMPORT SWriteString, SWriteChar, SWriteCard;
FROM GlobalDefs IMPORT StrAny ;
FROM Translations IMPORT XlateLine, XlateTablePointer, CurrentModeType,
              Int2File, File2Int, XlateStrAny, InitialXlateData, LenD,
              XClose, XWrStr, XWrLn, XWrNXlate, OutFile;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) NextColItem,ReleaseCollection;

VAR
   ErrorText:  ARRAY[0..10] OF CHAR;
   WarningText: ARRAY [0..10] OF CHAR;
   InfoText :  ARRAY [0..10] OF CHAR;
   LabelsDef:  BOOLEAN;

PROCEDURE WriteText(Label: ARRAY OF CHAR; VAR Text : ARRAY OF CHAR) ;
VAR
   MPos: CARDINAL;
   Msg: StrAny;
   dummy:  BOOLEAN;
   ResC:   ResCollectionType;
BEGIN
   IF NOT LabelsDef THEN
      GetDataArray( (* RES REM INS*) 1, ResC);
      dummy := GetNextDataArrayStringItem(ResC,ErrorText);
      dummy := GetNextDataArrayStringItem(ResC,WarningText);
      dummy := GetNextDataArrayStringItem(ResC,InfoText);
      ReleaseCollection(ResC);
      LabelsDef := TRUE;
   END;
   MPos := 0;
   SWriteString( Msg, MPos, Label, 0);
   SWriteString( Msg, MPos, ': ', 0);
   SWriteString( Msg, MPos, Text, 0);
   OutputErrorProc(Msg);
END WriteText ;

PROCEDURE PutError(VAR Text : ARRAY OF CHAR ) ;
BEGIN
   WriteText(ErrorText, Text);
END PutError;

PROCEDURE PutWarning(VAR Text : ARRAY OF CHAR ) ;
BEGIN
   WriteText(WarningText, Text);
END PutWarning ;

PROCEDURE PutMessage(VAR Text : ARRAY OF CHAR ) ;
BEGIN
   WriteText(InfoText, Text);
END PutMessage ;

PROCEDURE ProgramErrorAndHalt( Text : ARRAY OF CHAR ) ;
VAR
   ErrPos:     CARDINAL;
   ErrorMsg:   StrAny;
BEGIN
   ErrPos := 0;
   SWriteString( ErrorMsg, ErrPos, Text, 0 );
   SWriteString( ErrorMsg, ErrPos, '  Process terminating.', 0 );
   WriteText('Program Error:',ErrorMsg) ;
   HALT ;
END ProgramErrorAndHalt ;

BEGIN
   LabelsDef := FALSE;
END ErrorBase.