IMPLEMENTATION MODULE RefValBase;
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


(*
  By: Lidio Presutti
  Date: 28 June 1988
  Last Modified:

  Ver 1.02
  - Aug. 23, 1989, L.Presutti
    Fix GetLogDataIntStr, was setting DispLen to length+1.
    Fix EncodeRefPat, after collecting start and number of chars the LookForName
    state did not have NameIndex reset to zero.
  - Aug. 29, 1989, L.Presutti
    Fix EncodeRefPat from "eating-up" comma in "$name/n1,ABC".  Also added check
    for field length for numbers to be <= 20 [since no number will be more than
    nine significant digits (ie. LONGINT)].
*)

IMPORT Str, Lib, WordBase, BitOps ;
FROM DBData IMPORT
  (* Vars  *) TDBFile, BeginStr, FolioID, BeginType ;
FROM HyperBase IMPORT
  (* Procs *) GetBaseHyper, ReleaseBaseHyper, HRecPntr ;
FROM MemoryManagement IMPORT RealStoragePntr;
FROM RefsBase IMPORT
  (* Vars  *) RefsNameListPntr, NumbOfRefNames,
  (* Procs *) LookupRefName ;
FROM RefStrInit IMPORT
  (* Proc  *) GetRefStrRecInfo ;
FROM WordBase IMPORT
  (* Types *) AlphaCharType,
  (* Vars  *) TypeOfChar,
  (* Procs *) IntToSortWord, SortToIntWord ;
FROM TokenBase IMPORT
  (* Procs *) GetTokenNo ;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) GetType, FreeTypeHandle;
FROM ListData IMPORT
  (* Types *) DataItemPntr, DataItem ;
FROM HyperDataModel IMPORT
  (* Types *) HyperData, HTokenData, HLogDataType, TDBStrPntr ;
FROM GlobalDefs IMPORT StrAny, SequenceType ;
FROM SYSTEM IMPORT ADR, TSIZE ;
FROM StringIO IMPORT
              SWriteCard, SWriteLongInt, SWriteString ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt ;
FROM MagicChars IMPORT
  (* Vars/Const *) RefDelimID ;
FROM Translations IMPORT
  (* Type  *) XlateStrAny, CurrentModeType,
  (* Vars  *) Int2Alp,
  (* Procs *) XlateLine ;
FROM ResMessages IMPORT
  (* Procs *) MsgString, PutResMessage ;
FROM TACTDataServices IMPORT
  (* Const *) NotRefNameRes,
  (* Procs *) GetTDBTokenData;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMAccess, VMRelease, VMMarkChanged;

CONST
   RefOnlyCode  = 1C ;
   RefStartCode = 2C ;
   RefAllCode   = 3C ;

   RefLimit = 80 ;  (* max size of a reference display ?? *)

(* Note from HyperDat.DEF:

    TDBStringFormat = RECORD
		TotalWords : LONGINT ;	(* should be LONGCARD -- another Logitech carry thru! *)
		TDBStr	   : BitOps.PackedStrType ;
		(* where TDBStr is formed as follows:
		   +-------------------------+---------------------------+--+
		   |   BitPackedSortStr      |       IntStr              |0C|
		   +-------------------------+---------------------------+--+
		   0                          TDBStr.PackedLen

		   Notice difference from BitOps.PackedStrType type [we concatenate
		   the internal string to it!
		*)	
	END ;
*)	

(* GetLogDataForToken takes a text position (represented as
   a particular Token-type DataItem pointed to by Token, and a particular
   Structure ID (for any ID "except" the word types (ID 0 and MAX(INTEGER), and
   returns the corresponding Log entry *)

PROCEDURE GetLogDataForToken(   TokenVA:  VirtAddr; (* to DataItem *)
				StructID: INTEGER;
			    VAR OutLogData:  HLogDataType);
   VAR
	Token	: DataItemPntr;
	LRecNo	: CARDINAL ;
	LRecPos	: INTEGER ;
	CX	: RealStoragePntr ;
   BEGIN
	IF (StructID = 0) OR (StructID = MAX(INTEGER)) (* word *) THEN
	   (* return -- will handle GetTokenNo in CreateRef proc. *)
	   RETURN
	END ;
	IF TokenVA = NILVirt THEN
	   ProgramErrorAndHalt('Token = NILVirt in GetLogDataForToken')
	END;

        Token := VMAccess(TokenVA);
        IF NOT Token^.TokenDataLoaded THEN
	   VMMarkChanged(TokenVA);
	   GetTDBTokenData(Token)
	END;
	LRecNo  := Token^.TokenFileData.LRecNo ;
	LRecPos := ORD( Token^.TokenFileData.LRecPos ) (* * 4 *) ;
	VMRelease(TokenVA);
	GetBaseHyper( LRecNo, CX, TDBFile );
	WITH CX^.HRecord DO
	   WHILE (LRecPos >= 0) AND (LogData[CHR(LRecPos)].StructID <> SHORTINT(StructID)) DO
	      DEC( LRecPos )
	   END ;
	   IF LRecPos < 0 THEN
		ProgramErrorAndHalt( 'RefValBase: StructID not found.' );
	   END ;
	   OutLogData := LogData[CHR(LRecPos)] ;
        END ;
        ReleaseBaseHyper( TDBFile, CX ) ;
   END GetLogDataForToken ;


(* GetLogDataIntStr is used for Ref data which is of the
   string type: It takes a particular log entry (which contains a
   structural ID and a string pointer), and extracts the particular
   string value -- in the internal character set *)

PROCEDURE GetLogDataIntStr(   LogData:  HLogDataType;
                          VAR Display:  ARRAY OF CHAR;
                          VAR DispLen:  CARDINAL;
                          VAR NoWords:  LONGCARD );
   VAR
	RecPos	: CARDINAL ;
	KeyLen	: CARDINAL ;
	Len	: CARDINAL ;
	CX	: RealStoragePntr ;
	StrPtr	: TDBStrPntr ;
	StartRec, StartIdx, EndRec, EndIdx : CARDINAL ;
   BEGIN
	GetRefStrRecInfo( INTEGER(LogData.StructID), StartRec, StartIdx, EndRec, EndIdx ) ;

	GetBaseHyper(ORD(LogData.SRecNo) + StartRec (* BeginStr *), CX, TDBFile);
	RecPos := ORD( LogData.SRecPos ) ;
	WITH CX^.HRecord DO
	   IF (RecPos > NoDataPtrsUsed) OR (RecPos = 0) THEN
  	      ProgramErrorAndHalt( 'RefValBase: Invalid String record access.' )
           END ;
           StrPtr := ADR( TextData[ DataPntr[RecPos] ] ) ;
(* KeyLen := ORD( TextData[DataPntr[RecPos] + TSIZE(LONGINT)] ) + TSIZE(LONGINT); *)
           Len := DataPntr[RecPos-1] - DataPntr[RecPos] - CARDINAL(StrPtr^.TDBStr.PackedLen)
			- 1 (* account for KeyLen byte *) - TSIZE(LONGINT);
           IF Len > HIGH( Display ) THEN
	      Len := HIGH( Display ) + 1 (* silent truncation ?! *)
           END ;
(*         Lib.Move( ADR(TextData[ DataPntr[RecPos]+KeyLen+1 ]), ADR(Display), Len ) ;*)
           Lib.Move( ADR(StrPtr^.TDBStr.PackedStr[CARDINAL(StrPtr^.TDBStr.PackedLen)] ), ADR(Display), Len ) ;
           IF Len <= HIGH( Display ) THEN  Display[Len] := 0C  END ;
           NoWords := StrPtr^.TotalWords;
           DispLen := Len ;
        END;
        ReleaseBaseHyper( TDBFile, CX ) ;
   END GetLogDataIntStr ;


(* GetLogDataSortStr is used for Ref data which is of the
   string type: It takes a particular log entry (which contains a
   structural ID and a string pointer), and extracts the particular
   string value -- in the sortable encoding *)

PROCEDURE GetLogDataSortStr(	    LogData:  HLogDataType;
				VAR Display:  ARRAY OF CHAR;
				VAR DispLen:  CARDINAL );
   VAR
	RecPos	: CARDINAL ;
	KeyLen	: CARDINAL ;
	CX	: RealStoragePntr ;
	StrPtr	: TDBStrPntr ;
	StartRec, StartIdx, EndRec, EndIdx : CARDINAL ;
	TempStr : StrAny ;
   BEGIN
	GetRefStrRecInfo( INTEGER(LogData.StructID), StartRec, StartIdx, EndRec, EndIdx ) ;
	GetBaseHyper(ORD(LogData.SRecNo) + BeginStr, CX, TDBFile );
        RecPos := ORD( LogData.SRecPos ) ;
        WITH CX^.HRecord DO
           IF (RecPos > NoDataPtrsUsed) OR (RecPos = 0) THEN
  	      ProgramErrorAndHalt( 'RefValBase: Invalid String record access.' )
	   END ;
           StrPtr := ADR( TextData[ DataPntr[RecPos] ] ) ;
(*
	   KeyLen := ORD( TextData[DataPntr[RecPos] + TSIZE(LONGINT)] ) + TSIZE(LONGINT);
	   IF KeyLen > HIGH( Display ) THEN
	      KeyLen := HIGH( Display ) + 1 (* silent truncation ?! *)
	   END ;
	   Lib.Move( ADR( TextData[ DataPntr[RecPos]+1 ]), ADR(TempStr), KeyLen ) ;
*)
	   BitOps.UnPack( StrPtr^.TDBStr, Display, WordBase.SortNoBitsPerChar ) ;
	   DispLen := Str.Length( Display ) ;
	END ;
	ReleaseBaseHyper( TDBFile, CX ) ;
   END GetLogDataSortStr ;


(* EncodeRefPat takes a Reference pattern and tranlates it into
   an encoded format that can be used efficiently by CreateRef *)

PROCEDURE EncodeRefPat(	VAR InTemplate	: ARRAY OF CHAR;
			VAR RefPat	: ARRAY OF CHAR;
			VAR RefLen	: CARDINAL ) : BOOLEAN ;
   TYPE
	StateTypes = ( ColRefPat, LookForRefName, ColRefName, LookForStartPos,
			LookUpName, GetStartPos, GetNoChars );
   (*RES OLD MSG 264
   Reference pattern "%0" does not refer to any Unit. "%1" precedes all Unit Names.
   Please type "%2?" to list existing Unit Names.
   *)
   CONST
	NoRefNames = (*RES REM INS *) 264 ;
   VAR
	cm	        : CurrentModeType ;
	State		: StateTypes ;
	Ch		: CHAR ;
	NameIndex	: CARDINAL ;
	NameStart	: CARDINAL ;
	TemplateIndex	: CARDINAL ;
	TempName	: StrAny ;
	StartNo		: CARDINAL ;
	NoChars		: CARDINAL ;
	I		: CARDINAL ;

	TextLen		: CARDINAL ;
	AlpTemplate	: StrAny ;
	CurPos		: CARDINAL ;
	NumbSeq		: CARDINAL ;
	IntLenD		: XlateStrAny ;
	EnoughData	: BOOLEAN ;
	IntLinePos	: CARDINAL ;
	LastCharRet	: BOOLEAN ;
	LastCharLen	: CARDINAL ;
	LastNameChar	: SequenceType ;
	RefNamesPresent : BOOLEAN ;

   PROCEDURE AddRefName( RefCode : CHAR ) : BOOLEAN ;
	VAR
	   RefLoc	: CARDINAL ;
	   StructID	: INTEGER ;
	   TryNameAgain	: StrAny ;
	   TempSortName : StrAny ;
	   ch		: CHAR ;
	
	PROCEDURE DoAdd ;
	   BEGIN
	      RefPat[RefLen] := RefCode ;
	      INC( RefLen ) ;
(* following code added to support position #s in ref string j.b. *)
              IF RefLoc = MAX(CARDINAL) THEN StructID := MAX(INTEGER)
              ELSE StructID := RefsNameListPntr^[RefLoc]^.ID END;
(* end of changed code for position #s *)
              
	      Lib.Move( ADR(StructID), ADR(RefPat[RefLen]), TSIZE(INTEGER) );
	      INC( RefLen, TSIZE(INTEGER) ) ;
	      IF (StartNo > 0) AND (StructID < 0) THEN
	         DEC( StartNo )     (* remember strings are zero-based *)
	      END ;
	      CASE RefCode OF
		RefStartCode :
		  Lib.Move( ADR(StartNo), ADR(RefPat[RefLen]), TSIZE(INTEGER) ) ;
		  INC( RefLen, TSIZE(INTEGER) ) ; |
		RefAllCode :
		  Lib.Move( ADR(StartNo), ADR(RefPat[RefLen]), TSIZE(INTEGER) ) ;
		  INC( RefLen, TSIZE(INTEGER) ) ;
		  Lib.Move( ADR(NoChars), ADR(RefPat[RefLen]), TSIZE(INTEGER) ) ;
		  INC( RefLen, TSIZE(INTEGER) ) ;
		ELSE
	      END ;
	      RefNamesPresent := TRUE ; (* at least one ref name present *)
	   END DoAdd ;
	
	BEGIN
	   TempName[NameIndex] := 0C ;
(* following code added to support position #s in ref string j.b. *)
           IF (TempName[0] = '#') AND (TempName[1] = 0C) THEN
              RefLoc := MAX(CARDINAL);
              DoAdd;
              RETURN TRUE;
           END;
(* end of changed code for position #s *)
	   IntToSortWord( TempName, TempSortName ) ;
	   IF LookupRefName( TempSortName, RefLoc ) THEN
	      DoAdd ;
	      RETURN TRUE
	   ELSE
	      (* error / warning -- TempName not found *)
	      IF TempName[0] = '?' THEN
	         ProgramErrorAndHalt('"?" Not permitted in Template');
(*		 IF DoRefSelectionWindow( StructID, TempName ) THEN
		    (* insert "new" TempName in InTemplate *)
		    Str.Delete( InTemplate, NameStart, 1 (* was NameIndex *) ) ;
		    Str.Insert( InTemplate, TempName, NameStart ) ;
                 END; *)
	      ELSIF LastCharRet THEN
	         (* this is a "bit" of a Kludge, but gets results! *)
	         (* remove last retained diacritic from name and try again *)
	         Str.Copy( TryNameAgain, TempName ) ;
	         TryNameAgain[ NameIndex-LastCharLen ] := 0C ;
		 IntToSortWord( TryNameAgain, TempSortName ) ;
		 IF LookupRefName( TempSortName, RefLoc ) THEN
		    DoAdd ;
		    (* now insert the "ret diac" in RefPat *)
		    Lib.Move( ADR(LastNameChar), ADR(RefPat[RefLen]), LastCharLen ) ;
		    INC( RefLen, LastCharLen ) ;
		    RETURN TRUE ;
		 ELSE
		    ProgramErrorAndHalt('Bad Reference name in Template');
(*		    MsgString( TempName, 0 ) ;
		    ResAskUser( NotRefNameRes, 'SC', ch ) ;
		    IF ch = 'S' THEN
			IF DoRefSelectionWindow( StructID, TempName ) THEN
			   Str.Delete( InTemplate, NameStart, NameIndex ) ;
			   Str.Insert( InTemplate, TempName, NameStart ) ;
			END;
		    END ; *)
	         END ;
	      ELSE
	         ProgramErrorAndHalt('Bad Reference name in Template');
(*		 MsgString( TempName, 0 ) ;
		 ResAskUser( NotRefNameRes, 'SC', ch ) ;
		 IF ch = 'S' THEN
		    IF DoRefSelectionWindow( StructID, TempName ) THEN
		       Str.Delete( InTemplate, NameStart, NameIndex ) ;
		       Str.Insert( InTemplate, TempName, NameStart ) ;
		    END;
		 END ; *)
	      END ;
	      RETURN FALSE
	   END ;
	END AddRefName ;

   PROCEDURE NextCh() : CHAR ;
	BEGIN
	   RETURN InTemplate[ TemplateIndex+1 ]
	END NextCh ;	

   BEGIN
	RefLen := 0 ;
	IF Str.Pos( InTemplate, RefDelimID ) > HIGH( InTemplate ) THEN
	   MsgString( InTemplate, 0 ) ;
	   MsgString( RefDelimID, 0 ) ;
	   MsgString( RefDelimID, 0 ) ;
	   PutResMessage( NoRefNames ) ;
	   RETURN FALSE ;
	END ;
	State := ColRefPat ;
	TemplateIndex := 0 ;
	RefNamesPresent := FALSE ; (* assume no ref name present *)
	Str.Concat( InTemplate, InTemplate, ' ' ) ; (* dummy sentinel *)
	cm.ModeIn := '0'; cm.ModeOut := '0';
	XlateLine( Int2Alp, 377C, InTemplate, cm,TextLen, IntLenD, NumbSeq,
			EnoughData, AlpTemplate );
	CurPos := 0 ;
	IntLinePos := 0 ;
	WHILE (CurPos < TextLen) DO
	   Ch := InTemplate[ TemplateIndex ] ;
	   CASE State OF
	     ColRefPat :
		IF Ch = RefDelimID THEN
		   NameIndex := 0 ;
		   State := LookForRefName ;
		ELSE
		   RefPat[ RefLen ] := Ch ;
		   INC( RefLen )
		END ;  |
	     LookForRefName :
		IF (Ch = '?') THEN
                   ProgramErrorAndHalt('"?" not permitted in Template');
                ELSIF (Ch = '#') THEN
		   TempName[0] := Ch ;
		   TempName[1] := 0C ;
		   NameIndex := 1 ;
		   NameStart := TemplateIndex ;
		   LastCharRet := FALSE ;
                   IF NOT AddRefName( RefOnlyCode ) THEN RETURN FALSE END;
		   State := ColRefPat ;
		ELSIF (TypeOfChar[AlpTemplate[CurPos]] = Letter) OR 
		   (TypeOfChar[AlpTemplate[CurPos]] = RetDiac) THEN
		   Lib.Move(ADR(InTemplate[TemplateIndex]), ADR(TempName[NameIndex]),IntLenD[CurPos].Int );
		   INC( NameIndex, IntLenD[CurPos].Int ) ;
		   IF TypeOfChar[AlpTemplate[CurPos]] = RetDiac THEN
		      Lib.Move(ADR(InTemplate[TemplateIndex]),ADR(LastNameChar),IntLenD[CurPos].Int );
		      LastCharLen := IntLenD[CurPos].Int ;
		      LastCharRet := TRUE ;
		   ELSE
		      LastCharRet := FALSE
		   END ;
		   NameStart := TemplateIndex ;
		   State := ColRefName
		ELSE
		   RefPat[ RefLen ] := Ch ;
		   INC( RefLen ) ;
		   State := ColRefPat ;
		END ; |
	     LookUpName :
		IF Ch = '/' THEN
		   StartNo := 0 ;
		   State := LookForStartPos ;
		ELSE
		   IF NOT AddRefName( RefOnlyCode ) THEN
		      RETURN FALSE
		   END ;
		   State := ColRefPat ;
		END ; |
	     ColRefName :
		IF Ch = '/' THEN
		   TempName[NameIndex] := 0C ;
		   StartNo := 0 ;
		   State := LookForStartPos ;
		ELSIF (TypeOfChar[AlpTemplate[CurPos]] <> Letter) AND
		      (TypeOfChar[AlpTemplate[CurPos]] <> RetDiac) THEN
		   IF NOT AddRefName( RefOnlyCode ) THEN
		      RETURN FALSE
		   END ;
		   IF Ch = RefDelimID THEN
		      NameIndex := 0 ;
		      State := LookForRefName ;
		   ELSE
		      RefPat[RefLen] := Ch ;
		      INC( RefLen ) ;
		      State := ColRefPat
		   END ;
		ELSE
		   Lib.Move(ADR(InTemplate[TemplateIndex]),ADR(TempName[NameIndex]),IntLenD[CurPos].Int );
		   INC( NameIndex, IntLenD[CurPos].Int ) ;	
		   IF TypeOfChar[AlpTemplate[CurPos]] = RetDiac THEN
		      Lib.Move(ADR(InTemplate[TemplateIndex]),ADR(LastNameChar),IntLenD[CurPos].Int );
		      LastCharLen := IntLenD[CurPos].Int ;
		      LastCharRet := TRUE ;
		   ELSE
		      LastCharRet := FALSE
		   END ;
		END ; |
	     LookForStartPos :
		IF (Ch < '0') OR (Ch > '9') THEN
		   IF NOT AddRefName( RefOnlyCode ) THEN
		      RETURN FALSE
		   END ;
		   IF Ch = RefDelimID THEN
		      NameIndex := 0 ;
		      State := LookForRefName ;
		   ELSE
		      RefPat[RefLen] := Ch ;
		      INC( RefLen ) ;
		      State := ColRefPat
		   END ;
		ELSE
		   StartNo := ORD( Ch ) - ORD( '0' ) ;
		   State := GetStartPos ;
		END ; |
	     GetStartPos :
		IF (Ch >= '0') AND (Ch <= '9') THEN
		   StartNo := StartNo * 10 + ORD( Ch ) - ORD( '0' )
		ELSIF (Ch = ',') AND ((NextCh() >= '0') AND (NextCh() <= '9') ) THEN
		   IF StartNo > RefLimit THEN
		      (* error /warning *)
		   ELSE
		      NoChars := 0 ;
		      State := GetNoChars
		   END ;
		ELSE
		   IF StartNo > RefLimit THEN
		      (* error / warning *)
		   ELSE
		      IF NOT AddRefName( RefStartCode ) THEN
		         RETURN FALSE
		      END ;
		   END ;
		   IF Ch = RefDelimID THEN
		      NameIndex := 0 ;
		      State := LookForRefName ;
		   ELSE
		      State := ColRefPat ;
		      RefPat[ RefLen ] := Ch ;
		      INC( RefLen )
		   END ;
		END ; |
	     GetNoChars:
		IF (Ch >= '0') AND (Ch <= '9') THEN
		   NoChars := NoChars * 10 + ORD( Ch ) - ORD( '0' )
		ELSE
		   IF StartNo + NoChars > RefLimit THEN
		      (* error / warning ? *)
		   ELSE
		      IF NOT AddRefName( RefAllCode ) THEN
			 RETURN FALSE
		      END ;
		      NameIndex := 0 ;
		   END ;
		   IF Ch = RefDelimID THEN
		      NameIndex := 0 ;
		      State := LookForRefName ;
		   ELSE
		      State := ColRefPat ;
		      RefPat[ RefLen ] := Ch ;
		      INC( RefLen )
		   END ;
		END ;
	   END ;
	   INC( TemplateIndex, IntLenD[CurPos].Int ) ;
	   INC( CurPos ) ;
	END ;
	IF NOT RefNamesPresent THEN
	   MsgString( InTemplate, 0 ) ;
	   MsgString( RefDelimID, 0 ) ;
	   MsgString( RefDelimID, 0 ) ;
	   PutResMessage( NoRefNames ) ;
	   RETURN FALSE
	END ;
	DEC( RefLen, 2 ) ; (* true length *)

	(* save these as the last set RefPat's *)
	Str.Copy( LastRefPat, InTemplate ) ;
	FOR I := 0 TO RefLen DO
	   (* do local assign, since RefPat may contain 0C's as part of pattern *)
	   LastEncodedRefPat[I] := RefPat[I]
	END ;
	LastRefPatLen	:= RefLen ;
	RETURN TRUE ;
   END EncodeRefPat ;


(* CreateRef takes an encoded reference pattern (created
   by EncodeRefPattern) and a particular position (represented by a
   Token-Type DataItem), and creates the reference text for it *)

PROCEDURE CreateRef(	 EncodedPat: ARRAY OF CHAR;
			 EncodedLen: CARDINAL;
			 TokenVA:    VirtAddr; (* to DataItem *)
		     VAR Pat:	     ARRAY OF CHAR;
		     VAR RefLen:     CARDINAL );
   VAR
	Token	 : DataItemPntr;
	EncodedIndex : CARDINAL ;
	StructID : INTEGER ;
	StartPos : CARDINAL ;
	NoChars  : CARDINAL ;
		
   PROCEDURE AddToPat( StartPos : CARDINAL; NoChars : CARDINAL ) ;
	VAR
	   I, J		: CARDINAL ;
	   StrLen	: CARDINAL ;
	   EndPos	: CARDINAL ;
           nw           : LONGCARD ;
	   IntStr, string, Word: StrAny ;
	   LogData	: HLogDataType ;
	   TokenNo	: LONGINT ;
           dummy        : BOOLEAN;
           tPos:         HRecPntr;
           tHandle:      HTypeHandle;


	PROCEDURE HandleLogNumber;
        VAR Pos:    CARDINAL;
            Side:   CHAR;
	BEGIN
	   IF NOT (VAL(CARDINAL,StructID) IN FolioID) THEN
              SWriteCard(string, I,LogData.Count,J)
           ELSIF LogData.Count = 0 THEN
              SWriteString(string, I, '???', J);
           ELSE
              Pos := 0;
              SWriteCard(IntStr, Pos, (LogData.Count+1) DIV 2, 0);
              IF (LogData.Count MOD 2) = 1 THEN Side := 'r'
              ELSE Side := 'v' END;
	      SWriteString(IntStr, Pos, Side, 0);
	      SWriteString(string, I, IntStr, J);
           END;
	END HandleLogNumber;

	BEGIN
	   GetLogDataForToken( TokenVA, StructID, LogData ) ;
	   IF StructID >= 0 THEN
	      (* numeric field -- ignore the StartPos for numbers *)
	      IF StartPos > 0 THEN J := StartPos   (* use first number if provided *)
	      ELSE J := NoChars END ;
	      IF J > 20 THEN  J := 20  END ;
              I := 0;
              string[0] := 0C;
              IF StructID = MAX(INTEGER) THEN
		 Token := VMAccess(TokenVA);
		 GetTokenNo( Token^.FilePos, TokenNo ) ;
                 SWriteLongInt(string,I,TokenNo,J);
		 VMRelease(TokenVA);
	      ELSIF StructID > 0 THEN HandleLogNumber
	      ELSE  (* want headword *)
		 Token := VMAccess(TokenVA);
                 GetTDBTokenData(Token) ;
                 tPos.Rec := Token^.TokenFileData.HRecNo + BeginType;
                 tPos.Idx := ORD(Token^.TokenFileData.HRecPos);
                 GetType(tPos,tHandle);
        	 BitOps.UnPack( tHandle^^.PackedWord, Word (*SortTempStr*), WordBase.SortNoBitsPerChar ) ;
                 FreeTypeHandle(tHandle);
                 SortToIntWord( Word, Word ) ;
                 SWriteString( string, I, Word, J);
		 VMRelease(TokenVA);
	      END ;
	   ELSE
	      (* string field *)
	      GetLogDataIntStr( LogData, IntStr, StrLen, nw ) ;
	      IF StartPos > StrLen THEN
	         IF NoChars > 0 THEN  (* pad with blanks as necessary *)
		    FOR I := 0 TO NoChars DO string[I] := ' ' END ;
		 END ;
		 string[NoChars] := 0C ;
	      ELSE
		 IF NoChars = 0 THEN
		    EndPos := StrLen
		 ELSE
		    EndPos := NoChars
		 END ;
		 I := StartPos ;
		 J := 0 ;
		 WHILE (I <= StrLen) AND (J < EndPos) AND (IntStr[I] <> 0C) DO
		   string[J] := IntStr[I] ;
		   INC( I ) ;
		   INC( J ) ;
		 END ;
		 WHILE J < NoChars DO
		    string[J] := ' ' ;
		    INC( J ) ;
		 END ;
		 IF J < (HIGH( Pat ) - RefLen) THEN
		    string[J] := 0C ;
		 ELSE
		    (* truncate string -- will not fit in "Pat" *)
		    string[ HIGH(Pat) - RefLen ] := 0C
		 END ;
	      END ;
	   END ;
	   StrLen := Str.Length( string ) ;
	   Lib.Move( ADR(string), ADR(Pat[RefLen]), StrLen ) ;
	   INC( RefLen, StrLen ) ;
	END AddToPat ;
	
   BEGIN
	EncodedIndex := 0 ;
	RefLen := 0 ;
 (*	WHILE (EncodedIndex <= EncodedLen ) DO  ... changed by jb *)
	WHILE (EncodedIndex <= EncodedLen ) AND (RefLen <= HIGH(Pat)) DO
	   CASE EncodedPat[EncodedIndex] OF
	      RefOnlyCode :
	         INC( EncodedIndex ) ;
	         Lib.Move( ADR(EncodedPat[EncodedIndex]), ADR(StructID), TSIZE(INTEGER) );
	         INC( EncodedIndex, TSIZE(INTEGER) ) ;
	         AddToPat( 0, 0 ) ;|
	      RefStartCode :
	         INC( EncodedIndex ) ;
	         Lib.Move( ADR(EncodedPat[EncodedIndex]), ADR(StructID), TSIZE(INTEGER) );
	         INC( EncodedIndex, TSIZE(INTEGER) ) ;
	         Lib.Move( ADR(EncodedPat[EncodedIndex]), ADR(StartPos), TSIZE(INTEGER) );
	         INC( EncodedIndex, TSIZE(INTEGER) ) ;
	         AddToPat( StartPos, 0 ) ;|
	      RefAllCode :
	         INC( EncodedIndex ) ;
	         Lib.Move( ADR(EncodedPat[EncodedIndex]), ADR(StructID), TSIZE(INTEGER) );
	         INC( EncodedIndex, TSIZE(INTEGER) ) ;
	         Lib.Move( ADR(EncodedPat[EncodedIndex]), ADR(StartPos), TSIZE(INTEGER) );
	         INC( EncodedIndex, TSIZE(INTEGER) ) ;
	         Lib.Move( ADR(EncodedPat[EncodedIndex]), ADR(NoChars), TSIZE(INTEGER) );
	         INC( EncodedIndex, TSIZE(INTEGER) ) ;
	         AddToPat( StartPos, NoChars)
	       ELSE
	         Pat[RefLen] := EncodedPat[EncodedIndex] ;
	         INC( RefLen ) ;
	         INC( EncodedIndex ) ;
	   END ;
	END ;
	IF RefLen <= HIGH(Pat) THEN Pat[RefLen] := 0C END;
   END CreateRef ;

BEGIN
	LastRefPat[0] := 0C ;
	LastEncodedRefPat[0] := 0C ; 
	LastRefPatLen	:= 0 ;
END RefValBase.
