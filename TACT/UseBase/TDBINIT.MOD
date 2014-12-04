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

(*
Created by: J.Bradley
Last Modified:
   Sept. 2, 1988 - L.Presutti
	- added calculation for NumbOfRefUnits in GetRefNames.
   Feb. 27, 1990 - L.Presutti
	- correct count for "StartAt" in GetRefStringList
*)

IMPORT Lib;
FROM Str IMPORT Length, Copy, Compare, Append, CardToStr;
FROM SYSTEM IMPORT ADR, TSIZE, BYTE, ADDRESS;
FROM GlobalDefs IMPORT StrAny, MaxCharsInSeq, SequenceType;
FROM ListData IMPORT MakeMKSLineItem, FirstMKSLine ; (* m.s. *)
FROM MainLists IMPORT PoolNoForMKSInfoList ; (* m.s. *)
FROM WordBase IMPORT
  (* Types *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar,
  (* Procs *) SetSortNoBitsPerChar;
FROM HyperDataModel IMPORT
  (* Const *) HyperLength, PastHeader, HNoOccurs, HNoTokens, HNoDataPtrs,
              HNoPDBWords, BaseHTypeLen, ThisTDBVersion,
  (* Types *) HyperData, HTypePntr, HyperRType;

FROM DBData IMPORT
    (* types *) IsFolioType,
    (* vars  *) TDBFile, TDBFileName, TDBTitle, TDBYear, TDBMonth, TDBDay,
                BeginStr, EndStr, BeginStrRec, NoStrRecs, BeginLog,
                EndLog, BeginType, BeginToken, BeginText,
                EndTextRec, EndTextIdx, EndTypeRec, EndTypeIdx,
                EndTokenRec, EndTokenIdx, NoTypes, LastAlphChar,
                NoTokensInDB, TDBDataInitialized, FolioID, PDBFileName;

FROM HyperBase IMPORT
  (* TYPE *)  HyperFile, IOModeType,
  (* PROC *)  OpenHyperFile, CloseHyperFile, GetBaseHyper,
              ReleaseBaseHyper;
(* FROM Storage IMPORT ALLOCATE, DEALLOCATE; *)
FROM MemoryManagement IMPORT
  (* types *) RealStoragePntr,
  (* procs *) ALLOCATE, DEALLOCATE;

FROM Translations IMPORT
 (* type *) XlateTablePointer, XlateEntryPointer, XlateEntryDataType,
            XlateTable, XlateTablePntr, XlateTableRec, XlateEntryDataTypeType,
 (* var  *) Int2Alp, Alp2Int,
 (* proc *) DeleteXlateTable;
FROM ResMessages IMPORT
   (*proc*)  MsgString, PutResError, PutResMessage;
FROM ErrorBase IMPORT
             ProgramErrorAndHalt, PutWarning;
FROM Utils IMPORT
 (* proc *) StandardizeFileName;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames, NumbOfRefUnits ;
FROM RefStrInit IMPORT
  (* Types *) RefStrRecList, RefStringData,
  (* Vars  *) RefStrRecListPntr ;
FROM RefValBase IMPORT
  (* Vars  *) LastRefPat, LastEncodedRefPat, LastRefPatLen,
  (* procs *) EncodeRefPat;
FROM TACTBase IMPORT MKSInfoPtr, MKSInfo, MKSInfoType ; (* m.s. *)
FROM VirtMem IMPORT NILVirt ; (* m.s. *)
FROM ResCollection IMPORT ResCollectionType, ReleaseCollection ;
FROM ResDataArray IMPORT
  (* procs *) GetDataArray, GetNextDataArrayStringItem;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;

CONST
(*RES OLD MSG 145
%0 is not a UseBase Textual Database.
*)
    NotTDBResNo = (*RES REM INS*) 145;

(*RES OLD MSG 144
%0 is not a UseBase Textual Database of the correct level.
*)

   NotTDBVersion = (*RES REM INS*) 144;

PROCEDURE VerifyTDBFile(VAR FileName: ARRAY OF CHAR;
                            Extension:ARRAY OF CHAR;
                        VAR TDBFile:  HyperFile;
                        VAR TDBYear:  CARDINAL;
                        VAR TDBMonth: CARDINAL;
                        VAR TDBDay:   CARDINAL): BOOLEAN;
VAR
   CX:      RealStoragePntr;
   ErrMsg:  StrAny;
BEGIN
   IF ( NOT StandardizeFileName(FileName, Extension)) THEN
      (*RES OLD MSG 142
      Please change the .TDB name %0.
      *)
      MsgString(FileName,0);
      PutResError( (*RES REM INS*) 142 );
      RETURN FALSE
   END;

   IF NOT OpenHyperFile(TDBFile, FileName, readmode,ErrMsg) THEN
      (*RES OLD MSG 143
      UseBase cannot open .TDB name %0: %1.
      *)
      MsgString(FileName,0);
      MsgString(ErrMsg,0);
      PutResError( (*RES REM INS*) 143 );
      RETURN FALSE
   END;

   GetBaseHyper(0,CX,TDBFile);

   WITH CX^ DO
      IF (HRecord.TDBHeader.Month > 12) OR (HRecord.TDBHeader.Day > 31) THEN
         MsgString(FileName, 0);
         PutResError( NotTDBResNo );
         IF NOT CloseHyperFile(TDBFile,ErrMsg) THEN
            ProgramErrorAndHalt(ErrMsg);
         END;
         RETURN FALSE;
      END;

      IF HRecord.TDBHeader.TDBVersion <> ThisTDBVersion THEN
         MsgString(FileName, 0);
         PutResError( NotTDBVersion );
         IF NOT CloseHyperFile(TDBFile,ErrMsg) THEN
            ProgramErrorAndHalt(ErrMsg);
         END;
         RETURN FALSE;
      END;

      WITH HRecord.TDBHeader DO
	TDBYear :=  Year;
	TDBMonth := Month;
	TDBDay :=   Day;
      END ;
   END;
   ReleaseBaseHyper(TDBFile,CX);
   RETURN TRUE;
END VerifyTDBFile;

PROCEDURE InitializeFromTDB(tFile:  HyperFile);
VAR
   HRec:    CARDINAL;
   HRecPos: CARDINAL;
   CX:      RealStoragePntr;
   Ch:	    CHAR ;
   ErrMsg:  StrAny;

PROCEDURE ReadTDBRecord(VAR CX: RealStoragePntr);
BEGIN
   IF HRec <> 0 THEN ReleaseBaseHyper(TDBFile,CX) END;

   GetBaseHyper(HRec,CX,TDBFile);
   INC(HRec);
END ReadTDBRecord;

PROCEDURE BuildDBXlate(): XlateTablePointer;

TYPE
   XRecStringType = RECORD
        CASE : BOOLEAN OF
        TRUE: Level:      CHAR;
              InChr:      CHAR;
              OutLenC:    CHAR;
              OutSeqC:    SequenceType |
        FALSE:
              Str:       ARRAY[0..MaxCharsInSeq+3] OF CHAR
        END
   END;

  VAR
    Ch:        CHAR;
    FirstOne:  XlateEntryPointer;
    DLvl:      CARDINAL;
    XlTbl:     XlateTablePntr;
    result:    XlateTablePointer;

PROCEDURE GetEntry(VAR P: XlateEntryPointer): CARDINAL;
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
         ReadTDBRecord(CX);
         HRecPos := 0;
      END;
      IF CX^.HRecord.TextData[HRecPos] <> 0C THEN found := TRUE
                                             ELSE INC(HRecPos) END;
   UNTIL found;
   IF CX^.HRecord.TextData[HRecPos] = 376C THEN
      INC(HRecPos,2);
      P := NIL;
      RETURN 0;
   END;
   Start := HRecPos;
   XRec := ADR(CX^.HRecord.TextData[HRecPos]);
   INC(HRecPos, Length(XRec^.Str));
   WHILE CX^.HRecord.TextData[HRecPos] <> 0C DO INC(HRecPos) END;

   lvl := ORD(XRec^.Level);
   NEW(P);
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
END GetEntry; (* GetEntry *)

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
  R := NIL ; (* m.s. *)
  RLvl := GetEntry(R);
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
      RLvl := GetEntry(R);
    ELSIF RLvl = 255 THEN
      IF GLvl <> 1 THEN
        Q^.Failure := R
      ELSE
        XlTbl^.XlateTableDat[R^.InChar] := R
      END;
      S := Q;
      Q := R;
      RLvl := GetEntry(R);
    ELSE
      RLvl := DoLevel(Q, S, R, RLvl)
    END;
  END;
  Q := R;
  RETURN RLvl
END DoLevel; (* DoLevel *)

BEGIN
  NEW(XlTbl);
  WITH XlTbl^ DO
    FOR Ch := 1C TO 377C DO
      XlateTableDat[Ch] := NIL
    END;
  END;
  DLvl := GetEntry(FirstOne);
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

PROCEDURE GetByte(): BYTE;
VAR b:  BYTE;
BEGIN
   IF HRecPos >= HyperLength THEN
      ReadTDBRecord(CX);
      HRecPos := 0;
   END;
   b := BYTE(CX^.HRecord.TextData[HRecPos]);
   INC(HRecPos);
   RETURN b;
END GetByte;

PROCEDURE Get2Bytes(VAR Result:ARRAY OF BYTE);
BEGIN
   Result[0] := GetByte();
   Result[1] := GetByte();
END Get2Bytes;

PROCEDURE GetString(VAR StrResult: ARRAY OF CHAR);
VAR i,h: CARDINAL;
    c:   CHAR;
BEGIN
   h := HIGH(StrResult);
   i := 0;
   REPEAT
      c := GetByte();
      IF i <= h THEN StrResult[i] := c END;
      INC(i);
   UNTIL c = 0C;
END GetString;

PROCEDURE GetRefNames;
VAR
   AmtToAlloc:   CARDINAL;
   i:            CARDINAL;
   TRName:       RefsNameData;

PROCEDURE GetRefEntry(VAR Result: ARRAY OF BYTE;
                      VAR NumbGot: CARDINAL);
VAR b: BYTE;
BEGIN
   NumbGot := 0;
   REPEAT
      b := GetByte();
      Result[NumbGot] := b;
      INC(NumbGot);
   UNTIL (NumbGot > 3 (* size of ID + size of Pref*) ) AND (b = BYTE(0C));
END GetRefEntry;

BEGIN
   Get2Bytes(NumbOfRefNames);

   AmtToAlloc := TSIZE(ADDRESS) * (2 + NumbOfRefNames);
   ALLOCATE(RefsNameListPntr,AmtToAlloc);

   NumbOfRefUnits := 0 ;
(* m.s.   ALLOCATE(RefsNameListPntr^[0],3); *)
   NEW( RefsNameListPntr^[0] ) ;
   RefsNameListPntr^[0]^.ID := 0;
   RefsNameListPntr^[0]^.Name[0] := 0C;
   FOR i := 1 TO NumbOfRefNames DO
      GetRefEntry(TRName,AmtToAlloc);
(* m.s.      ALLOCATE(RefsNameListPntr^[i],AmtToAlloc); *)
      NEW ( RefsNameListPntr^[i] ) ;
(*    BlockMoveForward( RefsNameListPntr^[i], ADR(TRName), AmtToAlloc); *)
      Lib.Move( ADR(TRName), RefsNameListPntr^[i], AmtToAlloc);
      IF RefsNameListPntr^[i]^.Pref = 0C THEN
	 INC( NumbOfRefUnits )
      END ;
   END;
(* m.s.   ALLOCATE(RefsNameListPntr^[NumbOfRefNames+1],4); *)
   NEW( RefsNameListPntr^[NumbOfRefNames + 1]) ;
   RefsNameListPntr^[NumbOfRefNames+1]^.ID := INTEGER(0);
   RefsNameListPntr^[NumbOfRefNames+1]^.Name[0] := 377C;
   RefsNameListPntr^[NumbOfRefNames+1]^.Name[1] := 0C;

END GetRefNames;

PROCEDURE DisposeRefNames;
VAR
   i:         CARDINAL;
   AmtToFree: CARDINAL;
BEGIN
   FOR i := 0 TO NumbOfRefNames + 1 DO
      DISPOSE(RefsNameListPntr^[i]);
   END;
   AmtToFree := TSIZE(ADDRESS) * (2 + NumbOfRefNames);
   DEALLOCATE(RefsNameListPntr,AmtToFree);
END DisposeRefNames;

PROCEDURE GetRefStringList ;
    TYPE
	DBRefStringData = RECORD
		ID	: INTEGER;
		SRec	: CHAR;		(* Start position *)
		SPos	: CHAR;
		ERec	: CHAR;		(* End position *)
		EPos	: CHAR;
	END;
   VAR
	AmtToAlloc	: CARDINAL;
	StartAt		: CARDINAL;
	I		: CARDINAL;
	CurrRefStrRec	: DBRefStringData;
   BEGIN
        IF NoStrRecs = 0 THEN
	   IF CX <> NIL THEN ReleaseBaseHyper(TDBFile,CX) END;
	   RETURN
	END;
	HRec := BeginStrRec ;
	ReadTDBRecord(CX);

	AmtToAlloc := TSIZE(RefStringData) * (1 + NoStrRecs) ;
	ALLOCATE( RefStrRecListPntr, AmtToAlloc ) ;

	StartAt := BeginStr - 1 ;
	FOR I := 1 TO NoStrRecs+1 DO
	    Lib.Move(ADR(CX^.HRecord.TextData[(I-1)*TSIZE(DBRefStringData)]),
		ADR(CurrRefStrRec), TSIZE(DBRefStringData) ) ;
	    WITH RefStrRecListPntr^[I] DO
		 ID   := CurrRefStrRec.ID ;
		 IF ORD( CurrRefStrRec.SPos ) = 1 THEN  INC( StartAt )  END ;
		 SRec := StartAt (* + ORD(CurrRefStrRec.SRec) *) ;
		 SPos := CurrRefStrRec.SPos ;
		 ERec := CurrRefStrRec.ERec ;
		 EPos := CurrRefStrRec.EPos ;
	    END ;
	    INC( StartAt, ORD(CurrRefStrRec.ERec) ) ;
	END ;

	ReleaseBaseHyper(TDBFile,CX);
   END GetRefStringList ;

PROCEDURE DisposeRefStringList ;
VAR
   i:         CARDINAL;
   AmtToFree: CARDINAL;
BEGIN
   IF NoStrRecs = 0 THEN RETURN END;
   AmtToFree := TSIZE(RefStringData) * (1 + NoStrRecs) ;
   DEALLOCATE( RefStrRecListPntr, AmtToFree ) ;
END DisposeRefStringList ;

PROCEDURE HandleHeaderEnd;
VAR
   hd:    ARRAY[0..1] OF CHAR;
   done:  BOOLEAN;
   FolioCounter : CARDINAL;
   MKSString : StrAny ;
   MKSLast : MKSInfoPtr ;

PROCEDURE GetRefString;
BEGIN
   GetString(LastRefPat);
   IF NOT EncodeRefPat(LastRefPat, LastEncodedRefPat, LastRefPatLen) THEN
      ProgramErrorAndHalt('Error encoding ref in GetRefString');
   END;
END GetRefString;

PROCEDURE GetMKSString ;
 VAR
   Text : ARRAY[0..127] OF CHAR ;

 BEGIN
   GetString( Text );
   MakeMKSLineItem( Text, PoolNoForMKSInfoList ) ;
END GetMKSString ;

BEGIN
   done := FALSE;
   WHILE NOT done DO
     Get2Bytes(hd);
     IF Compare(hd,'EN') = 0 THEN done := TRUE
     ELSIF Compare(hd,'RF') = 0 THEN GetRefString
     ELSIF Compare( hd,'MK') = 0 THEN GetMKSString; (* m.s. - add mks info to list for future use in tactbase *)
     ELSIF Compare(hd,'FO') = 0 THEN
	Get2Bytes(FolioCounter);
	INCL( FolioID, FolioCounter ) ;
     ELSE
        ErrMsg :='Error in HandleHeaderEnd';
        PutWarning(ErrMsg);
        done := TRUE;
     END;
   END;

END HandleHeaderEnd;

PROCEDURE DisposeHeaderEnd;
BEGIN
   LastRefPatLen := 0;
END DisposeHeaderEnd;

(* prepare general profile information, excluding mks info *)
PROCEDURE HandleProfileInfo ;
  VAR
      ResC: ResCollectionType ;
      dummy: BOOLEAN ;
      Text: ARRAY[0..4] OF ARRAY[0..50] OF CHAR ;
      Ch : CHAR ;
      TempStr, TempNum: ARRAY [0..79] OF CHAR ;
  CONST
   (*RES OLD DTA 30
   'Title and FileName of TextBase: ' 'FileName of .GIX: '
   'Total Number of Words: ' 'Total Number of Different Words: '
   '.MKS Information: '
   *)
BEGIN
   GetDataArray((*RES REM INS*) 30  , ResC ) ;
   dummy := GetNextDataArrayStringItem( ResC, Text[0] );
   dummy := GetNextDataArrayStringItem( ResC, Text[1] );
   dummy := GetNextDataArrayStringItem( ResC, Text[2] );
   dummy := GetNextDataArrayStringItem( ResC, Text[3] );
   dummy := GetNextDataArrayStringItem( ResC, Text[4] );
   ReleaseCollection(ResC) ;

   Copy( TempStr, Text[0] ) ;
   Append( TempStr , '( ' );
   Append( TempStr, TDBTitle ) ;
   Append( TempStr, ' ) ' ) ;
   IF Length( TDBTitle )  + Length( TDBFileName ) > 40 THEN
      MakeMKSLineItem( TempStr, PoolNoForMKSInfoList ) ;
      Copy(TempStr, '        ') ;
   END ;
   Append( TempStr, TDBFileName ) ;
   MakeMKSLineItem( TempStr, PoolNoForMKSInfoList ) ;
   Copy( TempStr, Text[1] ) ;
   Append( TempStr, PDBFileName );
   MakeMKSLineItem( TempStr, PoolNoForMKSInfoList ) ;
   Copy( TempStr, Text[2] ) ;
   CardToStr( LONGCARD(NoTokensInDB), TempNum, 10, dummy ) ;
   Append( TempStr, TempNum );
   MakeMKSLineItem( TempStr, PoolNoForMKSInfoList ) ;
   Copy( TempStr, Text[3] ) ;
   CardToStr( LONGCARD(NoTypes), TempNum, 10, dummy ) ;
   Append( TempStr, TempNum ) ;
   MakeMKSLineItem( TempStr, PoolNoForMKSInfoList ) ;
   TempStr[0] := 0C ;
   MakeMKSLineItem( TempStr, PoolNoForMKSInfoList ) ;
   TempStr[0] := 0C ;
   MakeMKSLineItem( TempStr, PoolNoForMKSInfoList ) ;
   Copy( TempStr, Text[4] ) ;
   MakeMKSLineItem( TempStr, PoolNoForMKSInfoList ) ;
   TempStr[0] := 0C ;
   MakeMKSLineItem( TempStr, PoolNoForMKSInfoList ) ;
END HandleProfileInfo ;




BEGIN (* InitializeFromTDB *)
   IF TDBDataInitialized THEN
      IF NOT CloseHyperFile(TDBFile,ErrMsg) THEN
            ProgramErrorAndHalt(ErrMsg);
      END;

      DeleteXlateTable(Int2Alp);
      DeleteXlateTable(Alp2Int);
      DisposeRefNames;
      DisposeHeaderEnd;
      DisposeRefStringList ;
   END;

   TDBFile := tFile;
   HRec := 0;
   ReadTDBRecord(CX);

   WITH CX^ DO
      TDBYear :=     HRecord.TDBHeader.Year;
      TDBMonth :=    HRecord.TDBHeader.Month;
      TDBDay :=      HRecord.TDBHeader.Day;

      Copy(TDBTitle,HRecord.TDBHeader.Title);

      BeginStr   :=  HRecord.TDBHeader.BeginStr;
      EndStr     :=  HRecord.TDBHeader.EndStr;
      BeginStrRec:=  HRecord.TDBHeader.BeginStrRec;
      NoStrRecs  :=  HRecord.TDBHeader.NoStrRecs;
      BeginLog   :=  HRecord.TDBHeader.BeginLog;
      EndLog     :=  HRecord.TDBHeader.EndLog;
      BeginToken :=  HRecord.TDBHeader.BeginToken;
      BeginType :=   HRecord.TDBHeader.BeginType;
      BeginText :=   HRecord.TDBHeader.BeginText;
      EndTextRec :=  HRecord.TDBHeader.EndTextRec;
      EndTextIdx :=  HRecord.TDBHeader.EndTextIdx;
      EndTypeRec :=  HRecord.TDBHeader.EndTypeRec;
      EndTypeIdx :=  HRecord.TDBHeader.EndTypeIdx;
      EndTokenRec := HRecord.TDBHeader.EndTokenRec;
      EndTokenIdx := HRecord.TDBHeader.EndTokenIdx;
      NoTypes :=     HRecord.TDBHeader.NoTypes;

      HRecPos :=     PastHeader; (* TSIZE(HyperData,HHeader); *)

      NoTokensInDB := VAL(LONGINT, EndTokenRec - BeginToken) * VAL(LONGINT, HNoTokens) +
		      VAL(LONGINT, EndTokenIdx + 1) ;

      Lib.Move(ADR(HRecord.TextData[HRecPos]),ADR(SimpAlphTable),256);
      INC(HRecPos,256);
      Lib.Move(ADR(HRecord.TextData[HRecPos]),ADR(TypeOfChar),255);
      INC(HRecPos,255)
   END;
   Int2Alp := BuildDBXlate();
   Alp2Int := BuildDBXlate();

   FirstMKSLine := NILVirt ; (* m.s. *)

   HandleProfileInfo ;

   GetRefNames;

   FolioID := IsFolioType{};
   HandleHeaderEnd;

   GetRefStringList ;

   LastAlphChar := 377C;
   WHILE TypeOfChar[LastAlphChar] <> Letter DO DEC(LastAlphChar) END;

   SetSortNoBitsPerChar ;

   TDBDataInitialized := TRUE;
END InitializeFromTDB;

END TDBInit.

