IMPLEMENTATION MODULE LineBase;
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


IMPORT Lib, Str ;
FROM SYSTEM IMPORT ADR;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM TACTInit IMPORT DoBackingLink;
FROM HyperDataModel IMPORT
  (* Types *) HTokenData, HNoTokens ;
FROM ListData IMPORT
  (* types *) ItemType,DataItemPntr;
FROM GlobalDefs IMPORT StrAny;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;
FROM DBData IMPORT
    (* vars  *) TDBFile, BeginText, EndTextRec, EndTextIdx,
                BeginToken, NoTokensInDB;
FROM HyperDataModel IMPORT
  (* Const *) HyperLength,
  (* Types *) HyperData;
FROM HyperBase IMPORT
  (* TYPE *)  HRecPntr,
  (* PROC *)  GetBaseHyper, ReleaseBaseHyper, CompareHRecs;
FROM MemoryManagement IMPORT RealStoragePntr;
FROM VirtMem IMPORT VirtAddr,VMAccess, VMMarkChanged, VMRelease;
FROM TACTDataServices IMPORT GetTDBTokenData;
FROM Translations IMPORT XFileType,XWriteLine, OutFile;
FROM WWWUtils IMPORT MakeQueryLink, MakeQueryDest;
FROM TokenBase IMPORT
  (* Types *) HTokenHandle,
  (* procs *) GetTokenNo, GetPrevToken, GetToken, DecompressTokenInfo,
              FreeTokenHandle, GetNextToken ;
FROM UnitBase IMPORT
  (* Procs *) GetUnitContext ;

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

(* HandleTokenType = (DisplayStart, DisplayEnd, NoDisplay); *)

PROCEDURE DisplayContextLines(TokenVA:     VirtAddr;
                              UnitID:      INTEGER;
                              Before:      CARDINAL;
                              After:       CARDINAL;
                              HandleToken: HandleTokenType;
                          VAR StartTPntr:  HRecPntr;
                          VAR EndTPntr:    HRecPntr);
   VAR
	TokenDataP	: DataItemPntr;
	loop		: BOOLEAN ;
	K		: CARDINAL ;
	Len		: CARDINAL ;
	TempLen		: CARDINAL ;
	Offset		: CARDINAL ;
	LText		: StrAny ;
	TempLText	: StrAny ;
	LineDisplayed	: CARDINAL ;
	Limit		: CARDINAL ;
	HighLite	: CARDINAL ;
	DataPtr		: LineDataType ;
	TempDataPtr	: LineDataType ;
	VariableLineStart	: HRecPntr ;
	BeforeLineStart	: HRecPntr ;
	AfterLineStart	: HRecPntr ;
	HLinePtr	: HRecPntr ;
	TempHLinePtr	: HRecPntr ;
        TokPos          : HRecPntr ;
	BefOffset	: CARDINAL ;
	AftOffset	: CARDINAL ;
	NotFirstTokenInFile : BOOLEAN ;


PROCEDURE HighLiteVariable() ;
VAR
   tptr:      POINTER TO StrAny;
   i:         CARDINAL ;
   LinkText : StrAny;
BEGIN
   IF HandleToken = NoDisplay THEN RETURN END;
   tptr := ADR(LText[Offset]);
   i := Str.Pos(tptr^, ' ');
   IF (i = MAX(CARDINAL)) THEN
      IF (HandleToken = DisplayStart) AND (DoBackingLink) THEN
         MakeQueryLink(TokPos, 'P', tptr^, LinkText)
      ELSIF (HandleToken = DisplayStart) THEN
         Str.Copy(LinkText, 'ú<Bú>');
         Str.Append(LinkText, tptr^);
         Str.Append(LinkText,'ú</Bú>');
      ELSE
         MakeQueryDest(tptr^, LinkText);
      END;
      LText[Offset] := 0C;
      Str.Append(LText, LinkText);
   ELSE
      tptr^[i] := 0C;
      IF HandleToken = DisplayStart THEN 
         MakeQueryLink(TokPos, 'P', tptr^, LinkText)
      ELSE
         MakeQueryDest(tptr^, LinkText);
      END;
      tptr^[i] := ' ';
      tptr := ADR(tptr^[i]);
      LText[Offset] := 0C;
      Str.Append(LinkText, tptr^);
      Str.Append(LText, LinkText);
   END;
END HighLiteVariable ;
	
   PROCEDURE GetGivenTokenInfo(PosData  : HRecPntr;
                           VAR Offset	: CARDINAL) ;
   VAR
      Handle:    HTokenHandle;
      Data:      HTokenData;
   BEGIN
      GetToken(PosData, Handle);
      DecompressTokenInfo(Handle, Data);
      FreeTokenHandle(Handle);
      WITH Data DO
	HLinePtr.Rec := TRecNo ;
	HLinePtr.Idx := TRecPos ;
      END ;
      GetLine( HLinePtr, TempLText, TempLen, Offset, TempDataPtr );
   END GetGivenTokenInfo;

   PROCEDURE FindRangeForTokens;
   VAR
	VariableTokenNo:    LONGINT;
	BeforeTokenNo:  LONGINT;
	AfterTokenNo:	LONGINT;
   BEGIN
      GetTokenNo( TokenDataP^.FilePos, VariableTokenNo ) ;
      BeforeTokenNo := VariableTokenNo - VAL(LONGINT,Before+1) ;
      IF BeforeTokenNo < VAL(LONGINT, 0) THEN
	 BeforeTokenNo := VAL(LONGINT, 0)
      END ;
      WITH StartTPntr DO
	Rec := VAL( CARDINAL, BeforeTokenNo DIV VAL(LONGINT,HNoTokens)) + BeginToken ;
	Idx := VAL( CARDINAL, BeforeTokenNo MOD VAL(LONGINT,HNoTokens)) ;
      END ;
      GetGivenTokenInfo(StartTPntr, BefOffset);
      BeforeLineStart := TempDataPtr.Start ;

      AfterTokenNo := VariableTokenNo + VAL(LONGINT, After) ;
      DEC( AfterTokenNo ) ;  (* use Kludgy form -- Logitech bug in VAL(...) *)
      IF AfterTokenNo > NoTokensInDB THEN
	 AfterTokenNo := NoTokensInDB
      END ;
      WITH StartTPntr DO
	Rec := VAL(CARDINAL, AfterTokenNo DIV VAL(LONGINT,HNoTokens)) + BeginToken ;
	Idx := VAL(CARDINAL, AfterTokenNo MOD VAL(LONGINT,HNoTokens)) ;
      END ;
      GetGivenTokenInfo(StartTPntr, AftOffset);
      AfterLineStart := TempDataPtr.Start ;
      NotFirstTokenInFile := TRUE;
   END FindRangeForTokens;

   PROCEDURE FindRangeForOthers;
   BEGIN
      GetUnitContext( TokenVA, UnitID, Before, After, StartTPntr, EndTPntr );

      (* >>> backup to previous token before range here <<< *)
      IF GetPrevToken( StartTPntr, HLinePtr ) THEN
        StartTPntr := HLinePtr;
        GetGivenTokenInfo(HLinePtr, BefOffset);
	NotFirstTokenInFile := TRUE ;
      ELSE (* no previous token available *)
	HLinePtr.Rec := 0 ;
	HLinePtr.Idx := 0;
        StartTPntr.Rec := 0; StartTPntr.Idx := 0; (* no previous! *)
	NotFirstTokenInFile := FALSE ;
        GetLine( HLinePtr, TempLText, TempLen, BefOffset, TempDataPtr );
      END ;
      BeforeLineStart := TempDataPtr.Start ;

      GetGivenTokenInfo(EndTPntr, AftOffset);
      AfterLineStart := TempDataPtr.Start ;
      IF GetNextToken(EndTPntr, HLinePtr) THEN EndTPntr := HLinePtr;
      ELSE EndTPntr.Rec := 0; EndTPntr.Idx := 0 END;
   END FindRangeForOthers;

PROCEDURE GenContextLine( VAR DispText : ARRAY OF CHAR; Len : CARDINAL );
   (* note: use "pass by ref" -- no modification of DispText *)
   VAR
	LPlen   : CARDINAL ;
	K	: CARDINAL ;
        text    : StrAny;
        dummy   : BOOLEAN;
   BEGIN
        K := 0;
        SWriteString(text,K,'  ',0);
        SWriteString(text,K,DispText,0);
        dummy := XWriteLine(OutFile, '?', text, K);
   END GenContextLine ;

   BEGIN  (* DoContext *)
	TokenDataP := VMAccess(TokenVA);
        IF NOT TokenDataP^.TokenDataLoaded THEN
	   VMMarkChanged(TokenVA);
	   GetTDBTokenData(TokenDataP)
	END;
	WITH TokenDataP^.TokenFileData DO
	   HLinePtr.Rec := TRecNo ;
	   HLinePtr.Idx := TRecPos ;
	END ;
        TokPos := TokenDataP^.FilePos;
	GetLine( HLinePtr, LText, Len, Offset, DataPtr ) ;

	IF UnitID = 1 (* lines *) THEN
	   VMRelease(TokenVA);
	   HighLite := Before + 1 ;
	   Limit := HighLite + After ;
	   LineDisplayed := HighLite ;
	   loop := TRUE ;
	   WHILE loop AND (LineDisplayed > 1) DO
		IF LineBase.GetPrevLine( DataPtr, LText, Len ) THEN
		   DEC( LineDisplayed ) ;
		ELSE
		   loop := FALSE ;
		END ;
	   END ;
	
	   LOOP
		IF LineDisplayed = HighLite THEN
		   HighLiteVariable() ;
	        END ;

		GenContextLine( LText, Len ) ;
		INC( LineDisplayed ) ;
		IF LineDisplayed > Limit THEN RETURN  END ;
		IF NOT GetNextLine( DataPtr, LText, Len ) THEN
		   RETURN
		END ;
	   END ; (* LOOP *)

	ELSE (* handle all other units *)

	   VariableLineStart := DataPtr.Start ; (* start of line with Variable *)
	   IF UnitID = 0 (* lines *) THEN FindRangeForTokens
	   ELSE FindRangeForOthers END;

	   VMMarkChanged(TokenVA);
	   TokenDataP^.CurrentContextCount := 0 ; (* !! *)
	   TokenDataP^.StartContext := BeforeLineStart ;
	   TokenDataP^.FinishContext := AfterLineStart ;
	   TokenDataP^.BefOffset := CHR(BefOffset) ;
	   TokenDataP^.AftOffset := CHR(AftOffset) ;
	   VMRelease(TokenVA);
	   loop := TRUE ;
	   WHILE loop AND ( CompareHRecs(DataPtr.Start, BeforeLineStart) > 0 ) DO
	      loop := GetPrevLine( DataPtr, LText, Len ) 
	   END ;
	
	   LOOP
		IF (CompareHRecs( DataPtr.Start, BeforeLineStart ) = 0) AND NotFirstTokenInFile THEN
		   IF BefOffset > 0 THEN Lib.Fill(ADR(LText),BefOffset,' ') END;
		   IF UnitID <> 0 (* words *) THEN
		      K := BefOffset ;
		      WHILE (K <= Len) AND (LText[K] <> ' ') DO
			LText[K] := ' ' ;
			INC( K ) ;
		      END ;   
		      IF (K > Len) THEN
		         IF NOT GetNextLine( DataPtr, LText, Len ) THEN
			      RETURN  
			 END ; 
		      END ;
		   END ; 
		END ;
		IF CompareHRecs( DataPtr.Start, AfterLineStart ) = 0 THEN
		   (* blank out from after the last Token to end of line *)
		   K := AftOffset ;
		   WHILE (K <= Len) AND (LText[K] <> ' ') DO
			INC( K ) ;
		   END ;
		   IF (K < Len) THEN
		      LText[K] := 0C;
		      Len := K;
		      END;
(*		   Lib.Fill(ADR(LText[K],Len - K + 1, ' '); *)
		END ;
		IF CompareHRecs( DataPtr.Start, VariableLineStart ) = 0 THEN
		   HighLiteVariable()
		END ;
		GenContextLine( LText, Len ) ;	
		IF CompareHRecs(DataPtr.Start, AfterLineStart) >= 0 THEN RETURN  END ;
		IF NOT GetNextLine( DataPtr, LText, Len ) THEN
		   RETURN  
		END ;
	   END ;
	END ;
END DisplayContextLines;

END LineBase.
