IMPLEMENTATION MODULE TDBStart;

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

FROM SYSTEM IMPORT ADR, ADDRESS, TSIZE;
FROM GlobalDefs IMPORT StrAnyPntr, MaxCharsInSeq, SequenceType;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM STANDARD IMPORT
  (* Vars  *) UpperCharList, LowerCharList ;
IMPORT Lib;
IMPORT Str;
IMPORT FIO;
FROM HyperDataModel IMPORT PastHeader, HyperData, HyperLength;
FROM TDBBase IMPORT
 (* type  *) RefsNamePntr, RefsNameList,
             RefsNameData, InFileDataType,
 (* vars  *) InFile, RefsNames, NoRefIDs, FileNID, OutPos, OutFileRec,
             OutStartRef,
 (* procs *) WriteDBRec;
FROM WordBase IMPORT
  (* Types *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar,
  (* Procs *) SetSortNoBitsPerChar ;
FROM Translations IMPORT
 (* type *) XlateTablePointer, XlateEntryPointer, XlateEntryDataType,
            XlateTable, XlateTablePntr, XlateTableRec, XlateEntryDataTypeType,
 (* var  *) Int2Alp, Alp2Int,
 (* proc *) DeleteXlateTable;
FROM ErrorBase IMPORT ProgramErrorAndHalt;

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
   IsFolioType = SET OF [1..127];

   MKSInfoPtr  = POINTER TO MKSInfoType ; (* m.s.*)
   MKSInfoType = RECORD
        Text : ARRAY [0..79] OF CHAR ;
        Next : MKSInfoPtr ;
      END ;

VAR
   NumberNamesInOutputList:   CARDINAL;
   AddFolio	: BOOLEAN ;
   FolioID	: IsFolioType ;
   FirstMKSItem, LastMKSItem : MKSInfoPtr ;

PROCEDURE ReadTDBRecord(No:  CARDINAL);
VAR r:   CARDINAL;
BEGIN
   FIO.IOcheck := FALSE;
   WITH InFile[No] DO
      r := FIO.RdBin(FileID,Rec,HyperLength);
      IF r <> HyperLength THEN
         ProgramErrorAndHalt('Problem reading file in ReadTDBRecord')
      END;
      r := FIO.IOresult();
      IF r <> 0 THEN
         ProgramErrorAndHalt('Problem reading file in ReadTDBRecord')
      END;
      INC(Pos);
      Idx := 0;
   END;
END ReadTDBRecord;

PROCEDURE GetEntry(No:    CARDINAL;
               VAR P: XlateEntryDataType): CARDINAL;
  VAR
    Start:   CARDINAL;
    ActLen:  CARDINAL;
    lvl:     CARDINAL;
    XRec:    POINTER TO XRecStringType;
    found:   BOOLEAN;
    HRecPos: CARDINAL;

BEGIN
   WITH InFile[No] DO
      HRecPos := Idx;
      found := FALSE;
      REPEAT
         IF HRecPos >= HyperLength THEN
            HRecPos := 0;
            ReadTDBRecord(No)
         END;
         IF Rec.TextData[HRecPos] <> 0C THEN found := TRUE
                                        ELSE INC(HRecPos) END;
      UNTIL found;
      IF Rec.TextData[HRecPos] = 376C THEN
         INC(HRecPos,2);
         Idx := HRecPos;
         RETURN 0;
      END;
      Start := HRecPos;
      XRec := ADR(Rec.TextData[HRecPos]);
      INC(HRecPos, Str.Length(XRec^.Str));
      WHILE Rec.TextData[HRecPos] <> 0C DO INC(HRecPos) END;

      lvl := ORD(XRec^.Level);
      WITH P DO
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
      Idx := HRecPos;
      RETURN lvl;
   END;
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

PROCEDURE GetDBTranslate;

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
  R := NIL ;
  IF GLvl = 1 THEN
     XlTbl^.XlateTableDat[Q^.InChar] := Q
  ELSE
     P^.Next := Q;
     IF P1 <> NIL THEN P1^.Next := Q END;
  END;
  RLvl := BuildEntry(R);
  S := NIL ;
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

BEGIN
   WITH InFile[0] DO
      Idx :=     PastHeader; (* TSIZE(HyperData,HHeader); *)

      Lib.Move(ADR(Rec.TextData[Idx]),ADR(SimpAlphTable),256);
      INC(Idx,256);
      Lib.Move(ADR(Rec.TextData[Idx]),ADR(TypeOfChar),255);
      INC(Idx,255);

      Int2Alp := BuildDBXlate();
      Alp2Int := BuildDBXlate();

      (* net to set SortNoBitsPerChar for bit packing/unpacking -- WordBase *)
      SetSortNoBitsPerChar ;
   END;
END GetDBTranslate;

PROCEDURE CompareDBTranslate(No:  CARDINAL): BOOLEAN;
VAR
   l:    CARDINAL;

PROCEDURE CompareDBXlate(No: CARDINAL;
                     VAR XP: XlateTablePointer): BOOLEAN;
  VAR
    FirstOne:  XlateEntryDataType;
    DLvl:      CARDINAL;
    XlTbl:     XlateTablePntr;
    Status:    BOOLEAN;

PROCEDURE CheckLevel(P, P1: XlateEntryPointer;
                 VAR Q1:    XlateEntryDataType;
                     GLvl:  CARDINAL;
                 VAR Status:BOOLEAN): CARDINAL;
VAR
    Q, R, S: XlateEntryPointer;
    RLvl: CARDINAL;

PROCEDURE CompareEntries(A: XlateEntryPointer;
                     VAR B: XlateEntryDataType (* read only *) ): BOOLEAN;
BEGIN
   IF A = NIL THEN RETURN FALSE END;
   RETURN 0 = Str.Compare(A^.OutSeq,B.OutSeq)
END CompareEntries;

BEGIN
  Status := FALSE;
  IF GLvl = 1 THEN
     Q := XlTbl^.XlateTableDat[Q1.InChar]
  ELSE
     Q := P^.Next;
     IF P1 <> NIL THEN
        IF NOT CompareEntries(P1^.Next,Q1) THEN
	   RETURN 0
	END;
     END;
  END;
  IF NOT CompareEntries(Q,Q1) THEN
	RETURN 0
  END;
  RLvl := GetEntry(No,Q1);
  S := NIL;			(* *LP* *)
  WHILE (RLvl = 255) OR (RLvl >= GLvl) DO
     IF RLvl = GLvl THEN
        IF GLvl <> 1 THEN R := Q^.Failure;
                     ELSE R := XlTbl^.XlateTableDat[Q1.InChar] END;
        IF NOT CompareEntries(R,Q1) THEN
	   RETURN 0
	END;
        S := NIL;
        Q := R;
        RLvl := GetEntry(No,Q1);
     ELSIF RLvl = 255 THEN
        IF GLvl <> 1 THEN R := Q^.Failure;
                     ELSE R := XlTbl^.XlateTableDat[Q1.InChar] END;
        IF NOT CompareEntries(R,Q1) THEN
	   RETURN 0
	END;
        S := Q;
        Q := R;
        RLvl := GetEntry(No,Q1);
     ELSE
        RLvl := CheckLevel(Q, S, Q1, RLvl,Status);
        IF NOT Status THEN
	   RETURN 0
        END;
     END;
  END;
  Status := TRUE;
  RETURN RLvl;
END CheckLevel;

BEGIN
   XlTbl := XP^.XlateMode['0']^.Table;
   DLvl := GetEntry(No,FirstOne);
   DLvl := CheckLevel(NIL, NIL, FirstOne, DLvl, Status);
   RETURN Status;
END CompareDBXlate;

BEGIN
   WITH InFile[No] DO
      Idx :=     PastHeader; (* TSIZE(HyperData,HHeader); *)
      l := Lib.Compare(ADR(Rec.TextData[Idx]),ADR(SimpAlphTable),256);
      IF l <> 256 THEN
         DeleteXlateTable(Int2Alp);
         DeleteXlateTable(Alp2Int);
         RETURN FALSE
      END;
      INC(Idx,256);
      l := Lib.Compare(ADR(Rec.TextData[Idx]),ADR(TypeOfChar),255);
      IF l <> 255 THEN
         DeleteXlateTable(Int2Alp);
         DeleteXlateTable(Alp2Int);
         RETURN FALSE
      END;
      INC(Idx,255);
   END;

   IF CompareDBXlate(No,Int2Alp) THEN
      IF CompareDBXlate(No,Alp2Int) THEN RETURN TRUE END
   END;
   DeleteXlateTable(Int2Alp);
   DeleteXlateTable(Alp2Int);
   RETURN FALSE
END CompareDBTranslate;

PROCEDURE LocateRefName(VAR RName:     ARRAY OF CHAR; (* read only *)
                        VAR Pntr:      RefsNamePntr): BOOLEAN;
VAR i:   INTEGER;
    c,p: RefsNamePntr;
BEGIN
   IF RefsNames = NIL THEN
      Pntr := NIL;
      RETURN FALSE;
   END;
   c := RefsNames;
   p := NIL;
   i := Str.Compare(RName,c^.Name);
   WHILE (c <> NIL) AND (i > 0) DO
      p := c;
      c := c^.Next;
      IF c <> NIL THEN i := Str.Compare(RName,c^.Name) END;
   END;
   IF i = 0 THEN
      Pntr := c;
      RETURN TRUE;
   ELSE
      Pntr := p;
      RETURN FALSE
   END;
END LocateRefName;

PROCEDURE BuildNewRefName(VAR NameData:   RefsNameData;
                              AmtToAlloc: CARDINAL;
                          VAR Pntr:       RefsNamePntr);
VAR  t:   RefsNamePntr;
BEGIN
   ALLOCATE(t,AmtToAlloc);
   INC(NumberNamesInOutputList);
   Lib.Move( ADR(NameData),t, AmtToAlloc);
   IF Pntr = NIL THEN
      t^.Next := RefsNames;
      RefsNames := t
   ELSE
      t^.Next := Pntr^.Next;
      Pntr^.Next := t;
   END;
   Pntr := t;
END BuildNewRefName;

PROCEDURE GetRefsNameList(No:    CARDINAL): BOOLEAN;
CONST
   MaxNoRefIDs = 256;
VAR
   NumbOfRefNames: CARDINAL;
   NumbOfRefUnits: CARDINAL;
   AmtToAlloc:     CARDINAL;
   i:              CARDINAL;
   TRName:         RefsNameData;
   HRecPos:        CARDINAL;
   TRefNL:         ARRAY[0..MaxNoRefIDs-1] OF RefsNamePntr;
   p:              RefsNamePntr;

PROCEDURE GetByte(): BYTE;
VAR b:  BYTE;
BEGIN
   IF HRecPos >= HyperLength THEN
      HRecPos := 0;
      ReadTDBRecord(No);
   END;
   b := BYTE(InFile[No].Rec.TextData[HRecPos]);
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

PROCEDURE HandleRefEntry(): BOOLEAN;
BEGIN
   IF LocateRefName(TRName.Name, p) THEN
      IF (TRName.ID = 0) OR (TRName.ID = 1) THEN
          IF (p^.ID <> TRName.ID) THEN RETURN FALSE END;
      ELSE
          IF (p^.ID < 0) AND (TRName.ID > 0) OR
             (p^.ID > 0) AND (TRName.ID < 0) THEN RETURN FALSE END;
      END;
      IF TRefNL[CARDINAL(ABS(TRName.ID))] = NIL THEN
         TRefNL[CARDINAL(ABS(TRName.ID))] := p;
         INC(NumbOfRefUnits);
      END;
   ELSE
      BuildNewRefName(TRName, AmtToAlloc, p);
      IF TRefNL[CARDINAL(ABS(TRName.ID))] = NIL THEN
         TRefNL[CARDINAL(ABS(TRName.ID))] := p;
         INC(NumbOfRefUnits);
         WITH p^ DO
            IF (TRName.ID = 0) OR (TRName.ID = 1) THEN ID := TRName.ID
            ELSE
               IF TRName.ID < 0 THEN ID := -INTEGER(NoRefIDs)
               ELSE ID := INTEGER(NoRefIDs) END;
               INC(NoRefIDs)
            END;
         END;
      ELSE
         p^.ID := TRefNL[CARDINAL(ABS(TRName.ID))]^.ID;

      END; (* IF TRefNL[CARDINAL(ABS(TRName.ID))] = NIL THEN ... *)
   END; (* IF NOT LocateRefName(TRName, P) THEN ... *)
   RETURN TRUE;
END HandleRefEntry;

BEGIN
   HRecPos := InFile[No].Idx;
   Get2Bytes(NumbOfRefNames);

   NumbOfRefUnits := 0 ;
   FOR i := 0 TO MaxNoRefIDs-1 DO TRefNL[i] := NIL END;

   FOR i := 1 TO NumbOfRefNames DO
      GetRefEntry(TRName,AmtToAlloc);
      IF NOT HandleRefEntry() THEN RETURN FALSE END;
   END;

   WITH InFile[No] DO
      Idx:= HRecPos;
      i := SIZE(ADDRESS) * NumbOfRefUnits;
      ALLOCATE(RefIDL,i);
      Lib.Move( ADR(TRefNL),RefIDL, i);
      RefIDN := NumbOfRefUnits - 1;
   END;
   RETURN TRUE;
END GetRefsNameList;

PROCEDURE LocateFileNameID(N:   ARRAY OF CHAR): BOOLEAN; (* N in sort format *)
VAR
   TRName:       RefsNameData;
   p:            RefsNamePntr;
BEGIN
   IF LocateRefName(N, p) THEN
      IF (p^.ID > 0) THEN RETURN FALSE END;
   ELSE
      WITH TRName DO
         Str.Copy(Name,N);
         ID := -INTEGER(NoRefIDs);
         INC(NoRefIDs);
         Pref := 0C;
      END;
      BuildNewRefName(TRName, 8 + Str.Length(N),p);
   END;
   FileNID := p^.ID;
   RETURN TRUE;
END LocateFileNameID;

PROCEDURE HandleHeaderTrailer(No:    CARDINAL;
                          VAR RString: ARRAY OF CHAR);

VAR
    hd:   ARRAY[0..1] OF CHAR;
    FolioCounter : CARDINAL;
    done: BOOLEAN;

PROCEDURE GetByteHH(): BYTE;
VAR b:    BYTE;
BEGIN
   WITH InFile[No] DO
      IF Idx >= HyperLength THEN
         Idx := 0;
         ReadTDBRecord(No);
      END;
      b := BYTE(Rec.TextData[Idx]);
      INC(Idx);
      RETURN b;
   END;
END GetByteHH;

PROCEDURE Get2BytesHH(VAR Result:ARRAY OF BYTE);
BEGIN
   Result[0] := GetByteHH();
   Result[1] := GetByteHH();
END Get2BytesHH;

PROCEDURE GetString(VAR StrResult: ARRAY OF CHAR);
VAR i,h: CARDINAL;
    c:   CHAR;
BEGIN
   h := HIGH(StrResult);
   i := 0;
   REPEAT
      c := GetByteHH();
      IF i <= h THEN StrResult[i] := c END;
      INC(i);
   UNTIL c = 0C;
END GetString;

PROCEDURE HandleMKSInfo ;

VAR
   TempStr : ARRAY [0..79] OF CHAR ;
   NewPtr :  MKSInfoPtr ;
BEGIN
   IF No = 0 THEN (* process first .tdb mks file only *)
      ALLOCATE( NewPtr, TSIZE( MKSInfoType ) );
      GetString( NewPtr^.Text) ;
      NewPtr^.Next := NIL ;
      IF FirstMKSItem = NIL THEN  (* first item *)
         FirstMKSItem := NewPtr ;
      ELSE
         LastMKSItem^.Next := NewPtr ;
      END ;
      LastMKSItem := NewPtr ;
   ELSE
      GetString( TempStr ) ; (* else ignored *)
   END ;
END HandleMKSInfo ;


BEGIN
   RString[0] := 0C;
   done := FALSE;
   WHILE NOT done DO
      Get2BytesHH(hd);
      IF Str.Compare(hd,'EN') = 0 THEN done := TRUE
      ELSIF Str.Compare(hd,'RF') = 0 THEN GetString(RString)
      (* ---------> handle folios here ??? <----------- *)
      ELSIF Str.Compare(hd,'MK') = 0 THEN HandleMKSInfo ; (* m.s. *)
      ELSIF Str.Compare(hd,'FO') = 0 THEN
	Get2BytesHH(FolioCounter);
	AddFolio := TRUE ;
	INCL( FolioID, FolioCounter ) ;
      ELSE ProgramErrorAndHalt('Error in HandleHeaderTrailer');
      END;
   END;
END HandleHeaderTrailer;

PROCEDURE WriteHeaderMaterial;

VAR
   HTCode: ARRAY[0..1] OF CHAR;
   I	: CARDINAL ;

PROCEDURE WriteXTables;

PROCEDURE WriteXTable( Table : XlateTablePointer ) ;
  VAR
     Ch  : CHAR ;
     Lvl : CARDINAL ;
     i   : CARDINAL ;
     HighCharList : CARDINAL ;

  PROCEDURE PutStr( S : ARRAY OF CHAR ) ;
     VAR
        L   : CARDINAL ;
     BEGIN
        L := Str.Length( S ) ;
        IF OutPos.Idx + L >= HyperLength THEN
           WriteDBRec ;
        END ;
        Lib.Move( ADR(S), ADR(OutFileRec.TextData[OutPos.Idx]), L ) ;
        INC( OutPos.Idx, L );
        INC( OutPos.Idx )  (* mark str with 0C by moving index *)
     END PutStr ;

  PROCEDURE EqI( Ptr1, Ptr2 : XlateEntryPointer ) : BOOLEAN ;
     BEGIN
	IF (Ptr1 = NIL) OR (Ptr2 = NIL) THEN
	   RETURN FALSE
        ELSE
	    RETURN ( Str.Compare(Ptr1^.OutSeq, Ptr2^.OutSeq) = 0 ) AND
		   ( Ptr1^.Next = Ptr2^.Next ) ;
	END ;
     END EqI ;

  PROCEDURE DoItem( Ptr : XlateEntryPointer ) ;
     VAR
        temp : XRecStringType ;
     BEGIN
        WITH Ptr^ DO
           temp.Level := CHR( Lvl ) ;
           temp.InChr := InChar ;
           temp.OutLenC := CHR( OutLen + 1 ) ; (* to avoid 0C, 1 added *)
           temp.OutSeqC := OutSeq ;
           PutStr( temp.Str )
        END ;
     END DoItem ;

  PROCEDURE DoDup( Ptr : XlateEntryPointer ) ;
     VAR
        temp : XRecStringType ;
     BEGIN
        WITH Ptr^ DO
           temp.Level := 377C ;
           temp.InChr := InChar ;
           temp.OutLenC := CHR( OutLen + 1 ) ;
           temp.OutSeqC := OutSeq ;
           PutStr( temp.Str )
        END ;
     END DoDup ;

  PROCEDURE DoNext( Ptr : XlateEntryPointer ) ;
     BEGIN
        INC( Lvl ) ;
        WHILE Ptr <> NIL DO
           DoItem( Ptr ) ;
           IF (Ptr^.Failure <> NIL) AND EqI( Ptr, Ptr^.Failure ) THEN
              DoDup( Ptr^.Failure ) ;
              Ptr := Ptr^.Failure ;
           END ;
           IF Ptr^.Next <> NIL THEN
              DoNext( Ptr^.Next )
           END ;
           Ptr := Ptr^.Failure ;
        END ;
        DEC( Lvl )
     END DoNext ;

  BEGIN (* WriteXTable *)
     Lvl := 1 ;
     HighCharList := HIGH(LowerCharList) ;
     WITH Table^.XlateMode['0']^.Table^ DO
        FOR Ch := 1C TO 377C DO
           IF XlateTableDat[Ch] <> NIL THEN
              i := Str.Pos( LowerCharList, Ch ) ;
              IF i <= HighCharList THEN
                 IF NOT EqI( XlateTableDat[Ch], XlateTableDat[UpperCharList[i]] ) THEN
                    DoItem( XlateTableDat[Ch] ) ;
                    IF XlateTableDat[Ch]^.Next <> NIL THEN
                       DoNext( XlateTableDat[Ch]^.Next )
                    END ;
                 END ;
              ELSE
                 DoItem( XlateTableDat[Ch] ) ;
                 i := Str.Pos( UpperCharList, Ch ) ;
                 IF i <= HighCharList THEN
                    IF EqI( XlateTableDat[Ch], XlateTableDat[LowerCharList[i]] ) THEN
                       DoDup( XlateTableDat[LowerCharList[i]] )
                    END
                 END ;
                 IF XlateTableDat[Ch]^.Next <> NIL THEN
                    DoNext( XlateTableDat[Ch]^.Next )
                 END ;
              END ;
           END    (* IF XlateTableDat[Ch] <> NIL THEN *)
        END ;    (* FOR Ch := 1C TO 377C DO *)
     END ;      (* WITH Table^.XlateMode['0']^.Table^ DO ... *)
     PutStr( 376C ) ;
  END WriteXTable ;

BEGIN
   Lib.WordFill(ADR(OutFileRec), HyperLength DIV 2, 0);
   OutPos.Rec := 0;
   OutPos.Idx := PastHeader;
   Lib.Move(ADR(SimpAlphTable),ADR(OutFileRec.TextData[OutPos.Idx]),256);
   INC(OutPos.Idx,256);
   Lib.Move(ADR(TypeOfChar),ADR(OutFileRec.TextData[OutPos.Idx]),255);
   INC(OutPos.Idx,255);

    WriteXTable( Int2Alp ) ;
    WriteXTable( Alp2Int ) ;
END WriteXTables;

PROCEDURE AddTextToDB( Data    : ADDRESS;
                       Len     : CARDINAL ) ;
VAR
   L1         : CARDINAL ;
   IntLinePtr : StrAnyPntr ;
BEGIN
   IntLinePtr := StrAnyPntr(Data);
   IF OutPos.Idx+Len >= HyperLength THEN
      L1 := HyperLength - OutPos.Idx ;
      Lib.Move( IntLinePtr,ADR(OutFileRec.TextData[OutPos.Idx]),  L1) ;
      WriteDBRec ;
      IF Len-L1 > 0 THEN
         Lib.Move(ADR(IntLinePtr^[L1]), ADR(OutFileRec),Len-L1) ;
         OutPos.Idx := Len - L1 ;
      END ;
   ELSE
      Lib.Move( IntLinePtr,ADR(OutFileRec.TextData[OutPos.Idx]),  Len) ;
      INC(OutPos.Idx, Len)
   END;
END AddTextToDB ;

PROCEDURE WriteNames ;
  VAR
     Temp:          RefsNamePntr;
     Len          : CARDINAL ;
  BEGIN
     AddTextToDB( ADR(NumberNamesInOutputList) , 2 (* TSIZE(CARDINAL) *) ) ;

     Temp := RefsNames;
     WHILE Temp <> NIL DO
        AddTextToDB( ADR(Temp^.ID), Str.Length(Temp^.Name)+4 (* INTEGER + CHAR + Name + 0C *) ) ;
        Temp := Temp^.Next ;
     END ;
  END WriteNames ;

BEGIN
   WriteXTables;
   WriteNames;

   IF OutStartRef[0] <> 0C THEN
      HTCode := 'RF';
      AddTextToDB( ADR(HTCode), 2);
      AddTextToDB( ADR(OutStartRef), 1 + Str.Length(OutStartRef));
   END;
   IF AddFolio THEN
      FOR I := 1 TO 127 (* MAX(IsFolioType) *) DO
	 IF I IN FolioID THEN
	    HTCode := 'FO';
	    AddTextToDB( ADR(HTCode), 2);
	    AddTextToDB( ADR(I), 2);
	 END ;
      END ;
   END ;

   IF FirstMKSItem <> NIL THEN (* m.s. - mks info found in input tdb, write out now *)
      WHILE FirstMKSItem <> NIL DO
         HTCode := 'MK' ;
         AddTextToDB( ADR(HTCode) , 2) ;
         AddTextToDB( ADR(FirstMKSItem^.Text), Str.Length(FirstMKSItem^.Text) ) ;
         HTCode := 0C ;
         AddTextToDB( ADR(HTCode) ,1 ) ;
         FirstMKSItem := FirstMKSItem^.Next ;
      END ;
   END ;
   HTCode := 'EN';
   AddTextToDB( ADR(HTCode), 2);
   WriteDBRec ;
END WriteHeaderMaterial;


BEGIN
   NumberNamesInOutputList := 0;
   FirstMKSItem := NIL ;
   LastMKSItem := NIL ;
   FolioID  := IsFolioType{};
   AddFolio := FALSE ;
END TDBStart.
