IMPLEMENTATION MODULE UnitBase;

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

FROM DBData IMPORT
  (* Vars  *) TDBFile, BeginToken, EndTokenRec, EndTokenIdx ;
IMPORT DBData; (* for reference to BeginLog and EndLog j.b. *)
FROM HyperBase IMPORT
  (* Types *) HRecPntr,
  (* Procs *) GetBaseHyper, ReleaseBaseHyper ;
FROM MemoryManagement IMPORT RealStoragePntr;
FROM RefsBase IMPORT
  (* Vars  *) NumbOfRefUnits ;
FROM ListData IMPORT
  (* Types *) DataItemPntr, DataItem;
FROM HyperDataModel IMPORT
  (* Const *) HyperLength, MaxNoLogData,
  (* Types *) HyperData, HTokenData, HNoTokens, HLogDataType ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt ;
FROM TACTDataServices IMPORT GetTDBTokenData;
FROM VirtMem IMPORT VMAccess, VMRelease, VMMarkChanged;

VAR
   TokenHyper : RealStoragePntr ;

(* GetLogDataForToken takes a text position (represented as
   a particular Token-type DataItem pointed to by Token, and a particular
   Structure ID (for any ID except the word type (ID 0), and
   returns the corresponding Log entry *)

PROCEDURE GetLogData(   Token	: HRecPntr;
			UnitID  : INTEGER;
		    VAR OutLogData: HLogDataType;
		    VAR LogRecNo  : CARDINAL ;
		    VAR LogRecPos : INTEGER ) ;
   VAR
	CX	: RealStoragePntr ;
	NotDone	: BOOLEAN ;
	Count	: CARDINAL ;
   BEGIN
	LogRecNo  := Token.Rec ;
	LogRecPos := Token.Idx ;
	NotDone := TRUE ;
	WHILE NotDone DO
	   GetBaseHyper( LogRecNo, CX, TDBFile );
	   WITH CX^.HRecord DO
	      WHILE (LogRecPos >= INTEGER(NumbOfRefUnits)) AND
		  (LogData[CHR(LogRecPos)].StructID <> SHORTINT(UnitID)) DO
	         DEC( LogRecPos )
	      END ;
	      ReleaseBaseHyper( TDBFile, CX ) ;
	      IF LogRecPos < INTEGER(NumbOfRefUnits) THEN
		  (* log event not on this log record, try previous record *)
		  DEC( LogRecNo ) ;
		  IF LogRecNo < DBData.BeginLog THEN
		     (* no more log records -- set to default init value *)
		     NotDone := FALSE ;
		     WITH OutLogData DO
		        IF UnitID < 0 THEN
			   SRecNo := 0C ;
			   SRecPos := 1C ;
			ELSE
			   Count := 0
			END ;
			StructID := SHORTINT(UnitID) ;
		     END ;
		  ELSE
		     LogRecPos := INTEGER(MaxNoLogData)
		  END ;
	      ELSE
		 OutLogData := LogData[ CHR(LogRecPos) ] ;
		 NotDone := FALSE ;
	      END ;
	   END ; (* WITH CX^.HRecord DO *)
	END ; (* WHILE NotDone DO *)
   END GetLogData ;

PROCEDURE GetPrevToken( VAR Token	: HRecPntr;
			    LogRecNo	: CARDINAL;
			    LogRecPos	: INTEGER ) : BOOLEAN ;
   VAR
	TokenIndex	: INTEGER ;
	TempLRecNo	: CARDINAL ;
	TempLRecPos	: INTEGER ;
	Temp		: CARDINAL ;
   BEGIN
	TokenIndex := INTEGER( Token.Idx ) ;
	LOOP
	   IF TokenIndex <= 0 THEN
	      DEC( Token.Rec ) ;
	      IF Token.Rec < BeginToken THEN
		 (* point to very first token when none are left *)
		 Token.Rec := BeginToken ;
		 Token.Idx := 0 ;	
		 RETURN FALSE
	      END ;
	      TokenIndex := HNoTokens-1 ;
	      ReleaseBaseHyper( TDBFile, TokenHyper ) ;
	      GetBaseHyper( Token.Rec, TokenHyper, TDBFile );
	   ELSE
	      DEC( TokenIndex )
	   END ;
	   WITH TokenHyper^.HRecord DO
	      REPEAT
		 Temp := ORD(TokenData[TokenIndex].LOffset) + BaseLogPos ;(* decompress Token data *)
		 TempLRecNo  := Temp DIV 256 + BaseLogRec ;
		 TempLRecPos := Temp MOD 256 ;	
		 DEC( TokenIndex ) ;
	      UNTIL (TokenIndex < 0) OR (TempLRecNo < LogRecNo) OR
		    ( (TempLRecNo = LogRecNo) AND (TempLRecPos <= LogRecPos) );
	      IF TokenIndex >= 0 THEN
		 Token.Idx := CARDINAL( TokenIndex ) + 1 ;	
		 RETURN TRUE ;
	      END ;
	   END ;
	END ;
   END GetPrevToken ;

PROCEDURE GetNextToken( VAR Token	: HRecPntr;
			    LogRecNo	: CARDINAL;
			    LogRecPos	: INTEGER ) : BOOLEAN ;
   VAR
	NoToks		: CARDINAL ;
	TempLRecNo	: CARDINAL ;
	TempLRecPos	: INTEGER ;
	Temp		: CARDINAL ;
   BEGIN
	IF Token.Rec < EndTokenRec THEN
	   NoToks := HNoTokens
	ELSE
	   NoToks := EndTokenIdx + 1
	END ;
	LOOP
	   IF Token.Idx >= NoToks-1 THEN
	      INC( Token.Rec ) ;
	      IF Token.Rec < EndTokenRec THEN
		 NoToks := HNoTokens
	      ELSIF Token.Rec = EndTokenRec THEN
		 NoToks := EndTokenIdx + 1   (* <<< ??? *)
	      ELSE
		 (* point to very last token when none are left *)
		 Token.Rec := EndTokenRec ;
		 Token.Idx := EndTokenIdx ;
		 RETURN FALSE
	      END ;
	      Token.Idx := 0 ;
	      ReleaseBaseHyper( TDBFile, TokenHyper ) ;
	      GetBaseHyper( Token.Rec, TokenHyper, TDBFile );
	   ELSE
	      INC( Token.Idx )
	   END ;
	   WITH TokenHyper^.HRecord DO
	      Temp := ORD(TokenData[Token.Idx].LOffset) + BaseLogPos ; (* decompress Token data *)
	      TempLRecNo  := Temp DIV 256 + BaseLogRec ;
	      TempLRecPos := Temp MOD 256 ;	
	      WHILE (Token.Idx < NoToks) AND
		    ( (TempLRecNo < LogRecNo) OR
		      ( (TempLRecNo = LogRecNo) AND (TempLRecPos < LogRecPos) ) ) DO
		 INC( Token.Idx ) ;
		 Temp := ORD(TokenData[Token.Idx].LOffset) + BaseLogPos ;
		 TempLRecNo  := Temp DIV 256 + BaseLogRec ;
		 TempLRecPos := Temp MOD 256 ;	
	      END ;
	      IF Token.Idx < NoToks THEN
		 RETURN TRUE ;
	      END ;
	   END ;
	END ;
   END GetNextToken ;

PROCEDURE GetUnitContext( TokenVA	: VirtAddr ; (* to DataItem *)
			  UnitID	: INTEGER ;
			  Before	: CARDINAL;
			  After		: CARDINAL;
		      VAR FirstTokenPtr	: HRecPntr ;
		      VAR LastTokenPtr	: HRecPntr );
   VAR
	TokenPtr	: DataItemPntr ;
	LogData		: HLogDataType ;
	KwicLogData	: HLogDataType ;
	LogTokPtr	: HRecPntr ;
	NumberCount	: CARDINAL ;
	LastCount	: CARDINAL ;
	LogRecNo	: CARDINAL ;
	LogRecPos	: INTEGER ;
	Temp		: CARDINAL ;
	CurrTokenData	: HTokenData ;
   BEGIN
	IF UnitID = 0 (* word *) THEN
	   RETURN  (* ensure to handle words elsewhere *)
	END ;

	TokenPtr := VMAccess(TokenVA);
        IF NOT TokenPtr^.TokenDataLoaded THEN
	   VMMarkChanged(TokenVA);
	   GetTDBTokenData(TokenPtr)
	END;
	LogTokPtr.Rec := TokenPtr^.TokenFileData.LRecNo ;
	LogTokPtr.Idx := ORD( TokenPtr^.TokenFileData.LRecPos ) ;

	GetLogData( LogTokPtr, UnitID, KwicLogData, LogRecNo, LogRecPos ) ;
	FirstTokenPtr := TokenPtr^.FilePos ;
        GetBaseHyper( FirstTokenPtr.Rec, TokenHyper, TDBFile );
	NumberCount := 0 ;
	LastCount   := KwicLogData.Count ;
	WHILE (NumberCount <= Before) AND GetPrevToken( FirstTokenPtr, LogRecNo, LogRecPos ) DO
	   WITH TokenHyper^.HRecord DO
	      Temp := ORD(TokenData[FirstTokenPtr.Idx].LOffset) + BaseLogPos ; (* decompress Token data *)
	      LogTokPtr.Rec := Temp DIV 256 + BaseLogRec ;
	      LogTokPtr.Idx := Temp MOD 256 ;
	   END ;
	   GetLogData( LogTokPtr, UnitID, LogData, LogRecNo, LogRecPos ) ;
	   IF LogData.Count <> LastCount THEN
	      (* change in Count (also String value, since overlay) means new entry *)
	      LastCount := LogData.Count ;
	      INC( NumberCount )
	   END ;
	END ;

	IF NumberCount > Before THEN
	   (* backup one token to set the very first Token in the range *)
	   WITH FirstTokenPtr DO
	      IF Idx = HNoTokens - 1 THEN
		 Idx := 0 ;
		 ReleaseBaseHyper( TDBFile, TokenHyper ) ;
		 INC( Rec ) ;
		 GetBaseHyper( Rec, TokenHyper, TDBFile );
	      ELSE
		 INC( Idx )
	      END
	   END ;
	(* else already pointing to first token in file (ie. range) *)
	END ;

	(* now reset starting Log & Token position and do "After" count *)
	ReleaseBaseHyper( TDBFile, TokenHyper ) ;

	LogTokPtr.Rec := TokenPtr^.TokenFileData.LRecNo ;
	LogTokPtr.Idx := ORD( TokenPtr^.TokenFileData.LRecPos ) ;
	GetLogData( LogTokPtr, UnitID, KwicLogData, LogRecNo, LogRecPos ) ;
	LastTokenPtr := TokenPtr^.FilePos ;
	GetBaseHyper( LastTokenPtr.Rec, TokenHyper, TDBFile );
	NumberCount := 0 ;
	LastCount   := KwicLogData.Count ;
	WHILE (NumberCount <= After) AND GetNextToken( LastTokenPtr, LogRecNo, LogRecPos ) DO
	   WITH TokenHyper^.HRecord DO
	      Temp := ORD(TokenData[LastTokenPtr.Idx].LOffset) + BaseLogPos ; (* decompress Token data *)
	      LogTokPtr.Rec := Temp DIV 256 + BaseLogRec ;
	      LogTokPtr.Idx := Temp MOD 256 ;
	   END ;
	   GetLogData( LogTokPtr, UnitID, LogData, LogRecNo, LogRecPos ) ;
	   IF LogData.Count <> LastCount THEN
	      (* change in Count (also String value, since overlay) means new entry *)
	      LastCount := LogData.Count ;
	      INC( NumberCount )
	   END ;
	END ;

	IF NumberCount > After THEN	
	   (* backup one token for very last Token in the range, except for last Tok in file *)
	   WITH LastTokenPtr DO
	      IF Idx = 0 THEN
		 Idx := HNoTokens - 1 ;
		 ReleaseBaseHyper( TDBFile, TokenHyper ) ;
		 DEC( Rec ) ;
		 GetBaseHyper( Rec, TokenHyper, TDBFile );
	      ELSE
		 DEC( Idx )
	      END
	   END ;
	END ;

	ReleaseBaseHyper( TDBFile, TokenHyper ) ;
	VMRelease(TokenVA);
   END GetUnitContext ;

PROCEDURE GetUnitLogPosContext( TokenVA 	: VirtAddr ; (* to DataItem *)
				UnitID		: INTEGER ;
				Before		: CARDINAL;
				After		: CARDINAL;
			    VAR StartLog	: LONGINT ;
			    VAR FinishLog	: LONGINT ) ;
   VAR
	TokenPtr	: DataItemPntr ;
	LogRecNo	: CARDINAL ;
	LogRecIdx	: CARDINAL ;
	CX		: RealStoragePntr ;
	Loop		: BOOLEAN ;
	Count		: INTEGER ;
   BEGIN
	IF UnitID = 0 (* word *) THEN
	   RETURN  (* ensure to handle words elsewhere *)
	END ;

	TokenPtr := VMAccess(TokenVA);
        IF NOT TokenPtr^.TokenDataLoaded THEN
	   VMMarkChanged(TokenVA);
	   GetTDBTokenData(TokenPtr)
	END;
	LogRecNo := TokenPtr^.TokenFileData.LRecNo ;
	LogRecIdx := ORD( TokenPtr^.TokenFileData.LRecPos ) ;

	GetBaseHyper( LogRecNo, CX, TDBFile );
	Count := INTEGER( Before ) ;
(* j.b.	IF CX^.HRecord.LogData[CHR(LogRecIdx)].StructID <> SHORTINT( UnitID ) THEN
	   INC( Count ) (* +1 to find it *)
	END ; *)
        Loop := TRUE;
	WHILE Loop DO
	   WITH CX^.HRecord DO
		WHILE   (LogRecIdx >= NumbOfRefUnits) AND
			(LogData[CHR(LogRecIdx)].StructID <> SHORTINT(UnitID)) DO
		    DEC( LogRecIdx )
		END ;
		IF LogRecIdx >= NumbOfRefUnits THEN
		   (* found one *)
		   DEC( Count ) ;
		   IF Count <(*jb=*) 0 THEN Loop := FALSE
		   ELSE DEC( LogRecIdx )  (* look for prev extry *) END ;
		END ;
		IF LogRecIdx < NumbOfRefUnits THEN
		   (* log event not on this log record, try previous record *)
		   DEC( LogRecNo ) ;
		   IF LogRecNo < DBData.BeginLog THEN
			(* no more log records -- set to default init value *)
			Loop := FALSE ;
			LogRecNo := DBData.BeginLog ; (* fake null first entry *)
			LogRecIdx := 0 ;
		   ELSE
			ReleaseBaseHyper( TDBFile, CX ) ;
			GetBaseHyper( LogRecNo, CX, TDBFile );
			LogRecIdx := CARDINAL(MaxNoLogData)
		   END ;
		END ;
	   END ; (* WITH CX^.HRecord DO *)
	END ; (* WHILE Loop DO *)

	StartLog := LONGINT( LogRecNo ) * LONGINT( 256 ) + LONGINT( LogRecIdx );
	
	IF LogRecNo <> TokenPtr^.TokenFileData.LRecNo THEN
	   ReleaseBaseHyper( TDBFile, CX ) ;
	   LogRecNo := TokenPtr^.TokenFileData.LRecNo ;
	   GetBaseHyper( LogRecNo, CX, TDBFile );
	ELSE
	   Loop := TRUE
	END ;
	LogRecIdx := ORD( TokenPtr^.TokenFileData.LRecPos) + 1; (* we start at +1 jb *)
	Count := INTEGER( After ) ;
(*	IF CX^.HRecord.LogData[CHR(LogRecIdx)].StructID = SHORTINT(UnitID) THEN
	   INC( Count ) ; (* +1 to find end of current UnitID *)
	END ; *)

	WHILE Loop DO
	   WITH CX^.HRecord DO
		WHILE   (LogRecIdx <= CARDINAL(MaxNoLogData)) AND
			(LogData[CHR(LogRecIdx)].StructID <> SHORTINT(UnitID) ) DO
		    INC( LogRecIdx )
		END ;
		IF LogRecIdx <= CARDINAL(MaxNoLogData) THEN
		   (* found one *)
		   DEC( Count ) ;
		   IF Count <(*jb=*) 0 THEN Loop := FALSE
		   ELSE INC( LogRecIdx )  (* look for next extry *) END ;
		END ;
		IF LogRecIdx > CARDINAL(MaxNoLogData) THEN
		   (* log event not on this log record, try next record *)
		   INC( LogRecNo ) ;
		   IF LogRecNo > DBData.EndLog THEN
			(* no more log records -- set to default last value *)
			Loop := FALSE ;
			LogRecNo := DBData.EndLog + 1 ; (* fake null Last entry *)
			LogRecIdx := 0 ;
		   ELSE
			ReleaseBaseHyper( TDBFile, CX ) ;
			GetBaseHyper( LogRecNo, CX, TDBFile );
			LogRecIdx := NumbOfRefUnits
		   END ;
		END ;
	   END ; (* WITH CX^.HRecord DO *)
	END ; (* WHILE Loop DO *)

	FinishLog := LONGINT( LogRecNo ) * LONGINT( 256 )
                     + LONGINT( LogRecIdx ) - 1;
	ReleaseBaseHyper( TDBFile, CX ) ;
	VMRelease(TokenVA);
   END GetUnitLogPosContext ;

END UnitBase.
