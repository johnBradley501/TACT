IMPLEMENTATION MODULE TDBInit;

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


FROM SYSTEM IMPORT ADR, ADDRESS;
FROM GlobalDefs IMPORT StrAny, MaxCharsInSeq, SequenceType;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM STANDARD IMPORT
  (* Vars  *) UpperCharList, LowerCharList ;
IMPORT Lib;
IMPORT Str;
IMPORT FIO;
FROM HyperDataModel IMPORT MaxDBTitleLength, IDType, TDBIDModel, HyperLength,
     ThisTDBVersion, PastHeader, HyperData, HNoTokens;
FROM WordBase IMPORT
  (* Types *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar,
  (* Procs *) SetSortNoBitsPerChar;
FROM Translations IMPORT
 (* type *) XlateTablePointer, XlateEntryPointer, XlateEntryDataType,
            XlateTable, XlateTablePntr, XlateTableRec, XlateEntryDataTypeType,
 (* var  *) Int2Alp, Alp2Int,
 (* proc *) DeleteXlateTable;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM Utils     IMPORT
  (* vars   *) month, day, year,
  (* procs  *) RemoveExtension, StandardizeFileName, GetXlationType,
               UpcaseStr, TrimBlanks ;
FROM UtilsTwo IMPORT IOErrorMessage;
FROM ResMessages IMPORT
  (* proc *)  MsgString, MsgCard, PutResError, PutResWarning;


PROCEDURE CheckTDBHeader( Name: ARRAY OF CHAR ) : BOOLEAN ;
(*RES OLD MSG 269  >> from MERGEBAS <<
File %0 is not a textual database file.
*)
CONST
   NotTDBRes = (*RES REM INS*) 269;

   VAR
	r : CARDINAL;
	m : ARRAY[0..40] OF CHAR;
	HRecord : HyperData ;
   BEGIN
	FIO.IOcheck := FALSE;
	TDBFileID := FIO.Open(Name);
	r := FIO.IOresult();
	IF r <> 0 THEN
	   IOErrorMessage(r, m);
	   (*RES OLD MSG 270   >> from MERGEBAS <<
	   IO Error reading file "%0": %1
	   *)
	   MsgString(Name,0);
	   MsgString(m,0);
	   PutResError( (*RES REM INS*) 270 );
	   FIO.IOcheck := TRUE;
	   RETURN FALSE
	END;

	r := FIO.RdBin( TDBFileID, HRecord, HyperLength);
	IF r <> HyperLength THEN
	   MsgString(Name,0);
	   PutResError( NotTDBRes );
	   FIO.IOcheck := TRUE;
	   FIO.Close(TDBFileID);
	   RETURN FALSE
	END;

	WITH HRecord.TDBHeader DO
	   IF Str.Compare(TDBID,TDBIDModel) <> 0 THEN
		MsgString(Name,0);
		PutResError( NotTDBRes );
		FIO.IOcheck := TRUE;
		FIO.Close( TDBFileID );
		RETURN FALSE
	   END;
	   IF (Month > 12) OR (Day > 31) THEN
		MsgString(Name,0);
		PutResError( NotTDBRes );
		FIO.IOcheck := TRUE;
		FIO.Close(TDBFileID);
		RETURN FALSE
	   END;
	   IF TDBVersion <> ThisTDBVersion THEN
		(*RES OLD MSG 271  >> from MERGEBAS <<
		%0 is not a TACT Textual Database of the correct version.
		*)
		MsgString(Name,0);
		PutResError( (*RES REM INS*) 271 );
		FIO.IOcheck := TRUE;
		FIO.Close(TDBFileID);
		RETURN FALSE;
	   END;
	END;

	FIO.IOcheck := TRUE;
	FIO.Close(TDBFileID);
	RETURN TRUE;
   END CheckTDBHeader ;


PROCEDURE InitializeTDB( FileName : ARRAY OF CHAR ) : BOOLEAN;
   VAR
	r	: CARDINAL;
	HRecNo	: CARDINAL;
	HRecPos : CARDINAL;
	HRecord : POINTER TO HyperData ;
	msg	: ARRAY[0..40] OF CHAR;

   TYPE
	XRecStringType = RECORD
			   CASE : BOOLEAN OF
			      TRUE: Level	: CHAR;
				    InChr	: CHAR;
				    OutLenC	: CHAR;
				    OutSeqC	: SequenceType |
			      FALSE:
				    Str		: ARRAY[0..MaxCharsInSeq+3] OF CHAR
			   END
			 END;

PROCEDURE ReadTDBRecord();
   VAR
	r : CARDINAL;
   BEGIN
	r := FIO.RdBin( TDBFileID, HRecord^, HyperLength);
	IF r <> HyperLength THEN
	   ProgramErrorAndHalt('TDBInit: Problem reading file in ReadTDBRecord')
	END;
	r := FIO.IOresult();
	IF r <> 0 THEN
	   ProgramErrorAndHalt('TDBInit: Problem reading file in ReadTDBRecord')
	END;
	INC( HRecNo );
	HRecPos := 0;
   END ReadTDBRecord;

PROCEDURE GetEntry(No:    CARDINAL;
               VAR P: XlateEntryDataType): CARDINAL;
   VAR
	Start:   CARDINAL;
	ActLen:  CARDINAL;
	lvl:     CARDINAL;
	XRec:    POINTER TO XRecStringType;
	found:   BOOLEAN;
    BEGIN
	found := FALSE;
	REPEAT
	   IF HRecPos >= HyperLength THEN
		ReadTDBRecord()
	   END;
	   IF HRecord^.TextData[HRecPos] <> 0C THEN found := TRUE
	   ELSE INC(HRecPos) END;
	UNTIL found;
	IF HRecord^.TextData[HRecPos] = 376C THEN
	   INC(HRecPos,2);
	   RETURN 0;
	END;
	Start := HRecPos;
	XRec := ADR(HRecord^.TextData[HRecPos]);
	INC(HRecPos, Str.Length(XRec^.Str));
	WHILE HRecord^.TextData[HRecPos] <> 0C DO INC(HRecPos) END;

	lvl := ORD(XRec^.Level);
	WITH P DO
	   InChar := XRec^.InChr;
	   OutLen := ORD(XRec^.OutLenC)-1;
	   ActLen := HRecPos-Start-3;
	   OutSeq := XRec^.OutSeqC;
	   Type := StrResult;
	   OutMode := '0';
	   Next := NIL;
	   Failure := NIL;
	END;
	RETURN lvl;
   END GetEntry;

PROCEDURE BuildEntry(VAR P: XlateEntryPointer): CARDINAL;
   VAR result:   CARDINAL;
   BEGIN
	NEW(P);
	result := GetEntry(0,P^);
	IF result = 0 THEN
	   DISPOSE(P);
	   P := NIL;
	END;
	RETURN result;
   END BuildEntry;


PROCEDURE BuildDBXlate(): XlateTablePointer;
  VAR
    Ch:        CHAR;
    FirstOne:  XlateEntryPointer;
    DLvl:      CARDINAL;
    XlTbl:     XlateTablePntr;
    result:    XlateTablePointer;

PROCEDURE DoLevel(P, P1: XlateEntryPointer;
              VAR Q:     XlateEntryPointer;
                  GLvl:  CARDINAL): CARDINAL;
VAR
    R, S: XlateEntryPointer;
    RLvl: CARDINAL;
BEGIN
  IF GLvl = 1 THEN
     XlTbl^.XlateTableDat[Q^.InChar] := Q
  ELSE
     P^.Next := Q;
     IF P1 <> NIL THEN P1^.Next := Q END;
  END;
  R := NIL ; (* m.s. *)
  RLvl := BuildEntry(R);
  S := NIL ;  (* m.s. *)
  WHILE (RLvl = 255) OR (RLvl >= GLvl) DO
    IF RLvl = GLvl THEN
      IF GLvl <> 1 THEN
        Q^.Failure := R
      ELSE
        XlTbl^.XlateTableDat[R^.InChar] := R
      END;
      S := NIL;
      Q := R;
      RLvl := BuildEntry(R);
    ELSIF RLvl = 255 THEN
      IF GLvl <> 1 THEN
        Q^.Failure := R
      ELSE
        XlTbl^.XlateTableDat[R^.InChar] := R
      END;
      S := Q;
      Q := R;
      RLvl := BuildEntry(R);
    ELSE
      RLvl := DoLevel(Q, S, R, RLvl)
    END;
  END;
  Q := R;
  RETURN RLvl
END DoLevel;

BEGIN
  NEW(XlTbl);
  WITH XlTbl^ DO
    FOR Ch := 1C TO 377C DO
      XlateTableDat[Ch] := NIL
    END;
  END;
  DLvl := BuildEntry(FirstOne);
  DLvl := DoLevel(NIL, NIL, FirstOne, DLvl);
  NEW(result);
  WITH result^ DO
     FOR Ch := '1' TO '9' DO XlateMode[Ch] := NIL END;
     NEW(XlateMode['0']);
     XlateMode['0']^.Seq[0] := 0C;
     XlateMode['0']^.Table := XlTbl;
  END;
  RETURN result
END BuildDBXlate;

   BEGIN	(* InitializeTDB *)
	HRecNo := 0 ;
	ALLOCATE( HRecord, HyperLength ) ;
	FIO.IOcheck := FALSE;
	TDBFileID := FIO.Open(FileName);
	r := FIO.IOresult();
	IF r <> 0 THEN
	   IOErrorMessage(r, msg);
	   (*RES OLD MSG 270   >> from MERGEBAS <<
	   IO Error reading file "%0": %1
	   *)
	   MsgString(FileName,0);
	   MsgString(msg,0);
	   PutResError( (*RES REM INS*) 270 );
	   FIO.IOcheck := TRUE;
	   DEALLOCATE( HRecord, HyperLength ) ;
	   RETURN FALSE
	END ;

	ReadTDBRecord();

	TDBYear  := HRecord^.TDBHeader.Year;
	TDBMonth := HRecord^.TDBHeader.Month;
	TDBDay   := HRecord^.TDBHeader.Day;

	Str.Copy(TDBTitle,HRecord^.TDBHeader.Title);

	BeginStr   :=  HRecord^.TDBHeader.BeginStr;
	EndStr     :=  HRecord^.TDBHeader.EndStr;
	BeginStrRec:=  HRecord^.TDBHeader.BeginStrRec;
	NoStrRecs  :=  HRecord^.TDBHeader.NoStrRecs;
	BeginLog   :=  HRecord^.TDBHeader.BeginLog;
	EndLog     :=  HRecord^.TDBHeader.EndLog;
	BeginToken :=  HRecord^.TDBHeader.BeginToken;
	BeginType :=   HRecord^.TDBHeader.BeginType;
	BeginText :=   HRecord^.TDBHeader.BeginText;
	EndTextRec :=  HRecord^.TDBHeader.EndTextRec;
	EndTextIdx :=  HRecord^.TDBHeader.EndTextIdx;
	EndTypeRec :=  HRecord^.TDBHeader.EndTypeRec;
	EndTypeIdx :=  HRecord^.TDBHeader.EndTypeIdx;
	EndTokenRec := HRecord^.TDBHeader.EndTokenRec;
	EndTokenIdx := HRecord^.TDBHeader.EndTokenIdx;
	NoTypes :=     HRecord^.TDBHeader.NoTypes;

	HRecPos :=     PastHeader; (* TSIZE(HyperData,HHeader); *)

	NoTokensInDB := VAL(LONGCARD, EndTokenRec - BeginToken) * VAL(LONGCARD, HNoTokens) +
			VAL(LONGCARD, EndTokenIdx + 1) ;

	Lib.Move(ADR(HRecord^.TextData[HRecPos]),ADR(SimpAlphTable),256);
	INC(HRecPos,256);
	Lib.Move(ADR(HRecord^.TextData[HRecPos]),ADR(TypeOfChar),255);
	INC(HRecPos,255);

	Int2Alp := BuildDBXlate();
	Alp2Int := BuildDBXlate();

	LastAlphChar := 377C;
	WHILE TypeOfChar[LastAlphChar] <> Letter DO DEC(LastAlphChar) END;
	SetSortNoBitsPerChar ;
	DEALLOCATE( HRecord, HyperLength ) ;
	RETURN TRUE;
   END InitializeTDB;

END TDBInit.
