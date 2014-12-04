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


IMPORT Lib, Str, FIO, BitOps ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
FROM SYSTEM IMPORT ADR, ADDRESS, TSIZE;
FROM GlobalDefs IMPORT StrAny, MaxCharsInSeq, SequenceType, FileNameType;
FROM STANDARD IMPORT
  (* Vars  *) UpperCharList, LowerCharList ;
FROM HyperDataModel IMPORT MaxDBTitleLength, IDType, TDBIDModel, CORIDModel, HyperLength,
     ThisTDBVersion, ThisCORVersion, PastHeader, HCorHeader, HyperData, HNoTokens,
     HCorFileListRecord;
FROM WordBase IMPORT
  (* Types *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar, SortNoBitsPerChar ,
  (* Procs *) SortToFullWord, IntToSortWord, Int2FirstAlphWord, FullToSortWord, SortToIntWord ;
FROM Translations IMPORT
 (* type *) XlateTablePointer, XlateEntryPointer, XlateEntryDataType,
            XlateTable, XlateTablePntr, XlateTableRec, XlateEntryDataTypeType,
 (* var  *) Int2Alp, Alp2Int,
 (* proc *) DeleteXlateTable;
FROM GetSequences IMPORT IntToSeq ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM Utils     IMPORT
  (* vars   *) month, day, year,
  (* procs  *) RemoveExtension, StandardizeFileName, GetXlationType,
               UpcaseStr, TrimBlanks ;
FROM UtilsTwo IMPORT IOErrorMessage;
FROM ResMessages IMPORT
  (* proc *)  MsgString, MsgCard, PutResError, PutResWarning;
FROM StartUp IMPORT
  (* vars *) Boundaries, FileData ;  (* m.s. *)


TYPE
   RefsNamePntr = POINTER TO RefsNameData;
(*   RefsNameList = ARRAY[0..1000] OF RefsNamePntr; *)
   RefsNameData = RECORD
       Next:  RefsNamePntr;
       ID:    INTEGER;
       Pref:  CHAR;  (* used as 1 byte # *)
       Name:  StrAny;
   END;

VAR

  RefsNames:   RefsNamePntr;  (* m.s. *)



PROCEDURE DoOpen( FileName : ARRAY OF CHAR; VAR FileID : File ) : BOOLEAN ;
   VAR
	r   : CARDINAL;
	msg : ARRAY[0..40] OF CHAR;
   BEGIN
	FileID := FIO.Open(FileName);
	r := FIO.IOresult();
	IF r <> 0 THEN
	   IOErrorMessage(r, msg);
	   (* RES OLD MSG 270   >> from MERGEBAS <<
	   IO Error reading file "%0": %1
	   *)
	   MsgString(FileName,0);
	   MsgString(msg,0);
	   PutResError( (*RES REM INS*) 270 );
	   RETURN FALSE
	ELSE
	   RETURN TRUE
	END ;
   END DoOpen ;

PROCEDURE CheckHeader( Name: ARRAY OF CHAR ) : BOOLEAN ;
   CONST
	(* RES OLD MSG 269  >> from MERGEBAS <<
	File %0 is not a textual database file.
	*)
	NotTDBRes = (*RES REM INS*) 269;
   VAR
	r	: CARDINAL;
	HRecord : HyperData ;
	FileID  : FIO.File ;

    PROCEDURE CloseUpWithErrMsg( Resource : CARDINAL ) ;
	BEGIN
	   MsgString(Name,0);
	   PutResError( Resource );
	   FIO.Close(FileID);
	END CloseUpWithErrMsg;

   BEGIN
	IF NOT DoOpen(Name, FileID) THEN  RETURN FALSE  END;

	r := FIO.RdBin( FileID, HRecord, HyperLength);
	IF r <> HyperLength THEN
	   CloseUpWithErrMsg( NotTDBRes ) ;
	   RETURN FALSE
	END;

	WITH HRecord DO
	   UsingCorpusFile := Str.Compare( CHeaderData.CORID, CORIDModel ) = 0 ;
	   IF UsingCorpusFile THEN
		IF CHeaderData.CORVersion <> ThisCORVersion THEN
		   (*RES OLD MSG 421
		   %0 is not a TACT Corpus Database of the correct version.
		   *)
		   CloseUpWithErrMsg( (*RES REM INS *) 421 ) ;
		   RETURN FALSE
		END ;
	   ELSIF Str.Compare(TDBHeader.TDBID,TDBIDModel) = 0 THEN
		IF TDBHeader.TDBVersion <> ThisTDBVersion THEN
		   (*RES OLD MSG 271  >> from MERGEBAS <<
		   %0 is not a TACT Textual Database of the Correct Version.
		   *)
		   CloseUpWithErrMsg( (*RES REM INS *) 271 ) ;
		   RETURN FALSE;
		END ;
	   ELSE
		(*RES OLD MSG 422
		File %0 is not a Textual or Corpus Database File.
		*)
		CloseUpWithErrMsg( (*RES REM INS *) 422 ) ;
		RETURN FALSE
	   END;
	   IF (TDBHeader.Month > 12) OR (TDBHeader.Day > 31) THEN
		CloseUpWithErrMsg( NotTDBRes ) ;
		RETURN FALSE
	   END;
	END;

	FIO.Close(FileID);
	RETURN TRUE;
   END CheckHeader ;



PROCEDURE MergeRefList( ) : BOOLEAN ; (* m.s. - called from startup  until true *)

   VAR
     TempPos : CARDINAL ;
     TempPtr : RefsNamePntr ;
     TempName, SortName, TempNamesList, IntResult, AlphResult : StrAny ;
     Found, Temp : BOOLEAN ;

   CONST
     Delims  = ' ' ;

   BEGIN
      FOR TempPos := 0 TO 255 DO   (* initialize *)
        RefArray[ TempPos ] := FALSE ;
      END ;
      IF Boundaries THEN
         TempPos := 0 ;
         Boundaries := FALSE ;
         Str.ItemS( TempName, FileData.RefsNamesList, Delims, TempPos ) ;
         WHILE TempName[0] <> 0C DO
            Found := FALSE ;
            IntToSortWord( TempName, SortName );
            TempPtr := RefsNames ; (* set pointer to head of list of refs in tdb *)
            WHILE TempPtr <> NIL DO
              IF (Str.Compare( TempPtr^.Name, SortName ) = 0) THEN
                  RefArray[ABS(TempPtr^.ID)] := TRUE ; (* found *)
                  Found := TRUE ;
                  Boundaries := TRUE ;
              END ;
              TempPtr := TempPtr^.Next ;
            END ;
            IF NOT Found THEN
               (*RES OLD MSG 478
               The Reference Name (Boundary) "%0" was not found in the .TDB file.
               *)
               MsgString( TempName , 0 ) ;
               PutResError( (*RES REM INS*) 478 ) ;
               RETURN FALSE ;
            END ;
            INC( TempPos ) ;
            Str.ItemS( TempName, FileData.RefsNamesList, Delims, TempPos ) ;
          END ;
      END ;
      (* if ok dispose of pointers *)
      TempPtr := RefsNames ;
      WHILE TempPtr <> NIL DO
         TempPtr := RefsNames^.Next ;
         DEALLOCATE( RefsNames , TSIZE( RefsNameData ) );
         RefsNames := TempPtr ;
      END ;
      RETURN TRUE ;  (* returns TRUE if all ref names ok *)
END MergeRefList ;


PROCEDURE InitializeFromDB( FileName : ARRAY OF CHAR ) : BOOLEAN;
   VAR
	HRecNo	: CARDINAL;
	HRecPos : CARDINAL;
	HRecord : POINTER TO HyperData ;
	Ch	: CHAR;
	FileID  : FIO.File ;
	FileNo	: CARDINAL ;
	BeginFile  : CARDINAL ;
	EndFileRec : CARDINAL ;
	TitleStart : CARDINAL ;
	Entry	: POINTER TO HCorFileListRecord;
	Name	: FileNameType ;
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
  TYPE  NoBitsMask = ARRAY[4..8] OF CARDINAL ;  (* could prob. do without 4 !? *)
  CONST NoBits = NoBitsMask ( 000FH, 001FH, 003FH, 007FH, 00FFH ) ;

PROCEDURE ReadDBRecord();
   VAR
	r : CARDINAL;
   BEGIN
	r := FIO.RdBin( FileID, HRecord^, HyperLength);
	IF r <> HyperLength THEN
	   ProgramErrorAndHalt('TDBInit: Problem reading file in ReadDBRecord')
	END;
	r := FIO.IOresult();
	IF r <> 0 THEN
	   ProgramErrorAndHalt('TDBInit: Problem reading file in ReadDBRecord')
	END;
	INC( HRecNo );
	HRecPos := 0;
   END ReadDBRecord;


PROCEDURE BuildDBXlate(): XlateTablePointer;
  VAR
    Ch:        CHAR;
    FirstOne:  XlateEntryPointer;
    DLvl:      CARDINAL;
    XlTbl:     XlateTablePntr;
    result:    XlateTablePointer;

PROCEDURE BuildEntry(VAR P: XlateEntryPointer): CARDINAL;
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
         ReadDBRecord();
      END;
      IF HRecord^.TextData[HRecPos] <> 0C THEN found := TRUE
                                             ELSE INC(HRecPos) END;
   UNTIL found;
   IF HRecord^.TextData[HRecPos] = 376C THEN
      INC(HRecPos,2);
      P := NIL;
      RETURN 0;
   END;
   Start := HRecPos;
   XRec := ADR(HRecord^.TextData[HRecPos]);
   INC(HRecPos, Str.Length(XRec^.Str));
   WHILE HRecord^.TextData[HRecPos] <> 0C DO INC(HRecPos) END;

   lvl := ORD(XRec^.Level);
   ALLOCATE(P, TSIZE(XlateEntryDataType));
   WITH P^ DO
      InChar := XRec^.InChr;
      OutLen := ORD(XRec^.OutLenC)-1;
      ActLen := HRecPos-Start-3;
      OutSeq := XRec^.OutSeqC;
      Type := StrResult;
      IF OutSeq[0] <> 0C THEN OutMode := '0'
      ELSE OutMode := ' ' END;
      Next := NIL;
      Failure := NIL;
   END;
   RETURN lvl;
END BuildEntry; (* GetEntry *)



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
     IF P1 <> NIL THEN
       P1^.Next := Q
     END;
  END;
  R := NIL ; (* m.s. - initialize before being passed as parameter *)
  RLvl := BuildEntry(R);
  S := NIL ; (* m.s. - unitialized o.w. *)
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
  ALLOCATE(XlTbl, TSIZE(XlateTable));
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


(* m.s. - moved from tdbstart - mergebas *)


PROCEDURE GetRefsNameList ;  (* m.s. *)
CONST
   MaxNoRefIDs = 256;
VAR
   NumbOfRefNames: CARDINAL;
   NumbOfRefUnits: CARDINAL;
   AmtToAlloc:     CARDINAL;
   i:              CARDINAL;
   TRName:         RefsNameData;
(*   HRecPos:        CARDINAL; *)
   NewRef:              RefsNamePntr;
   RefsSize:       CARDINAL ;


PROCEDURE GetByte(): BYTE;
VAR b:  BYTE;
BEGIN
   IF HRecPos >= HyperLength THEN
(*      INC( HRecNo ) ; *)
      ReadDBRecord();
   END;
   b := BYTE(HRecord^.TextData[HRecPos]);
   INC(HRecPos);
   RETURN b;
END GetByte;

PROCEDURE GetRefEntry(VAR Result: ARRAY OF BYTE;
                      VAR NumbGot: CARDINAL);
VAR b: BYTE;
BEGIN
   NumbGot := 4; (* start after "Next" pntr *)
   REPEAT
      b := GetByte();
      Result[NumbGot] := b;
      INC(NumbGot);
   UNTIL (NumbGot > 7 (* size Next + ID + Pref*) ) AND (b = BYTE(0C));
END GetRefEntry;

PROCEDURE Get2Bytes(VAR Result:ARRAY OF BYTE);
BEGIN
   Result[0] := GetByte();
   Result[1] := GetByte();
END Get2Bytes;


BEGIN
   Get2Bytes(NumbOfRefNames);
   RefsNames := NIL ;
   RefsSize := TSIZE( RefsNameData ) ;
   FOR i := 1 TO NumbOfRefNames DO
      GetRefEntry( TRName,AmtToAlloc);
      ALLOCATE( NewRef, RefsSize ) ;
      NewRef^ := TRName ;
      NewRef^.Next := RefsNames ;
      RefsNames := NewRef ;
   END ;

END GetRefsNameList;

(* m.s. - end of stuff moved, modified *)


   BEGIN	(* InitializeFromDB *)
	IF NOT DoOpen( FileName, FileID ) THEN  RETURN FALSE  END ;

	HRecNo := 0 ;
	ALLOCATE( HRecord, HyperLength ) ;
	ReadDBRecord();
	WITH HRecord^ DO	(* common to both TDB and COR files *)
		BeginType   := TDBHeader.BeginType;
		EndTypeRec  := TDBHeader.EndTypeRec;
		EndTypeIdx  := TDBHeader.EndTypeIdx;
		NoTypes     := TDBHeader.NoTypes;
                BeginLog    := TDBHeader.BeginLog ; (* m.s. *)
                EndLog      := TDBHeader.EndLog ;   (* m.s. *)
	END ;

	IF UsingCorpusFile THEN
	   HRecPos := SIZE( HCorHeader ) ;
	   CORFileID := FileID ;
	   WITH HRecord^ DO
		BeginFile   := CHeaderData.BeginFile;
		EndFileRec  := CHeaderData.EndFileRec;
		NumbFiles   := CHeaderData.NumbFiles;
		TDBDir	    := CHeaderData.TDBDir ;
		BeginCorpusType  := CHeaderData.BeginType;
		EndCorpusTypeRec := CHeaderData.EndTypeRec;
	   END ;
	   HROffset := ((NumbFiles-1) DIV 8) + 1;
	   BitOps.InitHuffDecodeTable ;
	ELSE
	   HRecPos := PastHeader; (* TSIZE(HyperData,HHeader); *)
	   TDBDir[0] := 0C ;
	   NumbFiles := 1 ;
	END ;

	Lib.Move(ADR(HRecord^.TextData[HRecPos]),ADR(SimpAlphTable),256);
	INC(HRecPos,256);
	Lib.Move(ADR(HRecord^.TextData[HRecPos]),ADR(TypeOfChar),255);
	INC(HRecPos,255);

	Int2Alp := BuildDBXlate();
	Alp2Int := BuildDBXlate();

	LastAlphChar := 377C;
	WHILE TypeOfChar[LastAlphChar] <> Letter DO DEC(LastAlphChar) END;

	(* now find out how many bits are used for "sort word" encoding *)
	Ch := 377C ;
	WHILE (TypeOfChar[Ch] <> Letter) AND (TypeOfChar[Ch] <> RetDiac) DO  DEC( Ch )  END ;
	SortNoBitsPerChar := 4 ;
	WHILE ORD(Ch) >= NoBits[ SortNoBitsPerChar ] DO  INC( SortNoBitsPerChar )  END ;

 	ALLOCATE( TDBFileNames, NumbFiles * SIZE(FileNamePntr) ) ;
	IF UsingCorpusFile THEN
	   FIO.Seek( FileID, LONGCARD(BeginFile) * HyperLength ) ;
	   ReadDBRecord();
	   HRecPos := 2 ;	(* first real file name *)
	   FOR FileNo := 1 TO NumbFiles DO
		IF HRecPos > HRecord^.NoDataPtrsUsed THEN
		   ReadDBRecord();
		   HRecPos := 1 ;
		END ;
                Entry := ADR(HRecord^.TextData[HRecord^.DataPntr[HRecPos]]) ;
		INC( HRecPos ) ;
		TitleStart := Str.Pos( Entry^.Names, 377C ) ;
		IF TitleStart > 255 (* really MAX CARD *) THEN
		   ProgramErrorAndHalt('TDBInit: Problem reading file names in Corpus file.')
		END ;
		Str.Slice( Name, Entry^.Names, 0, TitleStart ) ;
		Str.Insert( Name, TDBDir, 0 ) ;
		ALLOCATE( TDBFileNames^[FileNo], Str.Length(Name)+1 ) ;
		Str.Copy( TDBFileNames^[FileNo]^, Name) ;
	   END ;
	ELSE
(*	   ALLOCATE( TDBFileNames^[1], Str.Length(FileName)+1 ) ; *)
	   ALLOCATE( TDBFileNames^[1], SIZE(FileNameType) ) ;
	   Str.Copy( TDBFileNames^[1]^, FileName ) ;
           GetRefsNameList() ; (* m.s. - get list of refs from tdb for comparison to Boundaries  field *)
	   FIO.Close( FileID ) ;	(* do an open later in RunSource *)
	END ;
	DEALLOCATE( HRecord, HyperLength ) ;
	RETURN TRUE;
   END InitializeFromDB;

PROCEDURE OpenTDB( FileName : ARRAY OF CHAR ) : BOOLEAN;
   VAR
	r	: CARDINAL;
	HRecord : POINTER TO HyperData ;
   BEGIN
	IF NOT DoOpen( FileName, TDBFileID ) THEN  RETURN FALSE  END ;

	ALLOCATE( HRecord, HyperLength ) ;
	r := FIO.RdBin( TDBFileID, HRecord^, HyperLength);
	IF r <> HyperLength THEN
	   ProgramErrorAndHalt('TDBInit: Problem reading file in ReadDBRecord')
	END;
	r := FIO.IOresult();
	IF r <> 0 THEN
	   ProgramErrorAndHalt('TDBInit: Problem reading file in ReadDBRecord')
	END;
	WITH HRecord^ DO
		NoTypes     := TDBHeader.NoTypes;
		BeginToken  := TDBHeader.BeginToken;
		EndTokenRec := TDBHeader.EndTokenRec;
		EndTokenIdx := TDBHeader.EndTokenIdx;
		BeginLog    := TDBHeader.BeginLog ;  (* m.s. *)
		EndLog      := TDBHeader.EndLog ;    (* m.s. *)
	END ;
	DEALLOCATE( HRecord, HyperLength ) ;
	RETURN TRUE;

   END OpenTDB;

BEGIN
   NoRefIDs := 2 ;  (* m.s. - 0 & 1 have fixed values *)
   MaxRefID := 1 ;  (* m.s. - 0 & 1 have fixed values, so are always present *)
   RefsNames := NIL ;
END TDBInit.
