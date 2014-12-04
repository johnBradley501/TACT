IMPLEMENTATION MODULE LogFile ;

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
Last Modified:
  27 June 1988 - L.Presutti
  - removed TYPE CurValRec and replaced it with HLogDataType
  5 July 1988 -  L.Presutti
  - WriteLogListToDB was writing ABS(StructID) -- need to preserve sign
*)

FROM SYSTEM IMPORT TSIZE ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
FROM Lib IMPORT Fill ;
FROM DBFile IMPORT
  (* Vars  *) HRecNo, HRecPos ,
  (* Procs *) WriteDBRec, AddTextToDB ;
FROM ErrorBase IMPORT
  (* Procs *) ProgramErrorAndHalt ;
FROM VirtualMemory IMPORT
  (* Types *) VirtualAddrType,
  (* Vars  *) VirtNil,
  (* Procs *) AllocateSpace, MakeReal, (* m.s. MarkDirty, ReleasePage, *) IsEqual,
              InitSpaceType ;
FROM WordBase IMPORT
  (* Procs *) FullToSortWord, SortToFullWord ;
FROM XlatUserInput IMPORT
  (* Types *) CounterPtr, CounterCharPtr, LabelPtr, RefBYUPtr, RefPosPtr,
  (* Const *) MaxNumbResets,
  (* Vars  *) CounterCharList, LabelList, RefList, BYUList, WordCounterPtr,
              LineCounterPtr, StructIDCounter, PosRefList;
FROM StringsData IMPORT
  (* Type  *) StringRecPtr ;
FROM GlobalDefs IMPORT StrAny ;
FROM TokenDataSource IMPORT
  (* Vars  *) BeginLog, EndLog, TokenNumber ;
FROM HyperDataModel IMPORT
  (* Type  *) HLogDataType ;

CONST
   BigCard = 0FFFH ;
   LogEntrySize = TSIZE(HLogDataType) ;
TYPE
   CurValArray = ARRAY[0..BigCard] OF HLogDataType ;

VAR
  CurValues   : POINTER TO CurValArray ;
  VNullStrPtr : VirtualAddrType ;
  StrPtr      : StringRecPtr ;

  VLogUnusedSpace : VirtualAddrType ;

  VTempLogEntry : VirtualAddrType ;
  VLogEntry     : VirtualAddrType ;
  LogEntry      : LogListPtr ;
  (* VLastLogEntry : VirtualAddrType ;  <--- in DEF file *)
  LastLogEntry  : LogListPtr ;
  LogList       : LogListPtr ;
  LogListInitEntryCount : CARDINAL ;

PROCEDURE AddNoToLogList( ID : CARDINAL ; Numb : CARDINAL ) ;
   BEGIN
      AllocateSpace( VLogEntry, LogEntry, VLogUnusedSpace, TSIZE(LogListEntry) ) ;
      LastLogEntry^.Next := VLogEntry ;
(* m.s.      ReleasePage( VLastLogEntry, LastLogEntry ) ; *)
      LogEntry^.StructID := ID ;
      LogEntry^.Number  := Numb ;
      LogEntry^.TokenNo := TokenNumber ;
      VLastLogEntry := VLogEntry ;
      LastLogEntry  := LogEntry ;
   END AddNoToLogList ;

PROCEDURE AddStrToLogList( ID : CARDINAL ; VStr : VirtualAddrType ) ;
   BEGIN
      AllocateSpace( VLogEntry, LogEntry, VLogUnusedSpace, TSIZE(LogListEntry) ) ;
      LastLogEntry^.Next := VLogEntry ;
(* m.s.      ReleasePage( VLastLogEntry, LastLogEntry ) ; *)
      LogEntry^.StructID := - INTEGER( ID ) ;
      LogEntry^.VStrPtr := VStr ;
      LogEntry^.TokenNo := TokenNumber ;
      VLastLogEntry := VLogEntry ;
      LastLogEntry  := LogEntry ;
   END AddStrToLogList ;

PROCEDURE InitLogList ;
   VAR
      TempBYUList   : RefBYUPtr ;
      TempRefList   : RefBYUPtr ;
      TempPosList   : RefPosPtr ;
      TempCharList  : CounterCharPtr ;
      TempLabelList : LabelPtr ;
      TempToCounter : CounterPtr ;
      I		    : CARDINAL ;
   BEGIN
      AllocateSpace( VLogEntry, LogEntry, VLogUnusedSpace, TSIZE(LogListEntry) ) ;
      VHeadLogList  := VLogEntry ;   (* start of Log List *)
      VLastLogEntry := VLogEntry ;
      LastLogEntry  := LogEntry ;
      LogEntry^.StructID := WordCounterPtr^.StructID ;
      LogEntry^.Number   := WordCounterPtr^.Init ;
      LogListInitEntryCount := 1 ;

      AddNoToLogList( LineCounterPtr^.StructID, LineCounterPtr^.Init ) ;
      INC( LogListInitEntryCount ) ;

      TempCharList := CounterCharList ;
      WHILE TempCharList <> NIL DO
         WITH TempCharList^.ToCounterData^ DO AddNoToLogList( StructID, Init ) END ;
	 INC( LogListInitEntryCount ) ;

	 (* now handle any counter indirections *)
	 TempToCounter := TempCharList^.ToCounterData^.Next ;
	 WHILE TempToCounter <> NIL DO
	    WITH TempToCounter^ DO  AddNoToLogList( StructID, Init )  END ;
	    INC( LogListInitEntryCount ) ;
	    TempToCounter := TempToCounter^.Next ;
	 END ;

         TempCharList  := TempCharList^.Next ;
      END ;

      TempLabelList := LabelList ;
      WHILE TempLabelList <> NIL DO
	 WITH TempLabelList^ DO
	    IF Numeric THEN ;
		AddNoToLogList( TempLabelList^.StructID, 0 )
	    ELSE
		AddStrToLogList( TempLabelList^.StructID, VirtNil ) ;
	    END ;
	    INC( LogListInitEntryCount ) ;
	    I := 1 ;
	    WHILE (IncremCounters[I] <> NIL) AND (I <= MaxNumbResets) DO
		WITH IncremCounters[I]^ DO AddNoToLogList( StructID, Init ) END ;
		INC( LogListInitEntryCount ) ;
		INC( I ) ;
	    END ;
	 END ;
         TempLabelList := TempLabelList^.Next ;
      END ;

      TempRefList := RefList ;
      WHILE TempRefList <> NIL DO
	 WITH TempRefList^ DO
	    IF Numeric THEN ;
		AddNoToLogList( TempRefList^.StructID, 0 )
	    ELSE
		AddStrToLogList( TempRefList^.StructID, VirtNil )
	    END ;
	    INC( LogListInitEntryCount ) ;
	    I := 1 ;
	    WHILE (IncremCounters[I] <> NIL) AND (I <= MaxNumbResets) DO
		WITH IncremCounters[I]^ DO AddNoToLogList( StructID, Init ) END ;
		INC( LogListInitEntryCount ) ;
		INC( I ) ;
	    END ;
	 END ;
         TempRefList   := TempRefList^.Next ;
      END ;

      TempBYUList := BYUList ;
      WHILE TempBYUList <> NIL DO
	 WITH TempBYUList^ DO
	    IF Numeric THEN ;
		AddNoToLogList( TempBYUList^.StructID, 0 )
	    ELSE
		AddStrToLogList( TempBYUList^.StructID, VirtNil )
	    END ;
	    INC( LogListInitEntryCount ) ;
	    I := 1 ;
	    WHILE (IncremCounters[I] <> NIL) AND (I <= MaxNumbResets) DO
		WITH IncremCounters[I]^ DO AddNoToLogList( StructID, Init ) END ;
		INC( LogListInitEntryCount ) ;
		INC( I ) ;
	    END ;
	 END ;
         TempBYUList   := TempBYUList^.Next ;
      END ;

      TempPosList := PosRefList ;
      WHILE TempPosList <> NIL DO
	 WITH TempPosList^ DO
            IF StructID <> 0 THEN
	       IF Numeric THEN
	          AddNoToLogList( TempPosList^.StructID, 0 )
	       ELSE
		  AddStrToLogList( TempPosList^.StructID, VirtNil )
	       END ;
	       INC( LogListInitEntryCount ) ;
	       I := 1 ;
	       WHILE (IncremCounters[I] <> NIL) AND (I <= MaxNumbResets) DO
		   WITH IncremCounters[I]^ DO AddNoToLogList( StructID, Init ) END ;
		   INC( LogListInitEntryCount ) ;
		   INC( I ) ;
               END;
	    END ;
	 END ;
         TempPosList   := TempPosList^.Next ;
      END ;

      LastLogEntry^.Next := VirtNil ;
   END InitLogList ;

PROCEDURE WriteLogListToDB ;
   VAR
	I : CARDINAL ;
	Offset : CARDINAL ;
	CurBaseTokenNo : LONGCARD ;
	DummyLog : HLogDataType ;
(* -- CONST is not acceptable parameter to AddTextToDB -- use var.
   CONST
	DummyLog = HLogDataType ( 0, 255, (* case : *) 2, 0 ) ;
*)	
   BEGIN
      WriteDBRec ;  (* ensure start log on a new record boundary *)
      BeginLog := HRecNo ;
(* m.s.      ReleasePage( VLastLogEntry, LastLogEntry ) ; *)

      WITH DummyLog DO
	StructID := 0 ;
	TokenNoOffset := 255 ;
	Count := 0 ;
      END ;
      (* initialise current values here -- ie. initial defaults from InitLogList *)
      ALLOCATE( CurValues, TSIZE(HLogDataType) * StructIDCounter ) ;
      FOR I := 0 TO StructIDCounter-1 DO
         CurValues^[I].StructID := 0 ;
	 CurValues^[I].TokenNoOffset := 0 ;
      END ;
      VLogEntry := VHeadLogList ;
      I := 1 ;  (* Note: StructIDCounter is zero based *)
      WHILE NOT IsEqual( VLogEntry, VirtNil ) AND (I <= StructIDCounter) DO
         MakeReal( VLogEntry, LogEntry ) ;
         WITH LogEntry^ DO
            IF StructID >= 0 THEN
               CurValues^[StructID].Count := 0 ;
            ELSE
               CurValues^[ABS(StructID)].SRecNo  := 0C (* always start with 1st Rec *) ;
               CurValues^[ABS(StructID)].SRecPos := StringsStartIndex[ ABS(StructID) ] ;
            END ;
            (* increment the number of counter when see new (different) LogEntry *)
            IF CurValues^[ABS(StructID)].StructID = 0 THEN  INC( I )  END ;
            CurValues^[ABS(StructID)].StructID := SHORTINT( StructID ) ;
            VTempLogEntry := Next ;
         END ;
(* m.s.         ReleasePage( VLogEntry, LogEntry ) ; *)
         VLogEntry := VTempLogEntry ;
      END ;

(*	VLogEntry := VHeadLogList ;	<--- ??? *LP* *)

      CurBaseTokenNo := 0 ;
      (* now start with the first real log entry from text *)
      WHILE NOT IsEqual( VLogEntry, VirtNil ) DO
         MakeReal( VLogEntry, LogEntry ) ;
         WITH LogEntry^ DO
	    IF HRecPos = 0 THEN
		(* write current values at beginning of Hyper record for each Id *)
		CurBaseTokenNo := TokenNo ;
		AddTextToDB( CurBaseTokenNo, LogEntrySize ) ;
		FOR I := 0 TO StructIDCounter-1 DO
		    CurValues^[I].TokenNoOffset := 0 ;	(* assure lookup table is always set to 0 *LP* *)
		    AddTextToDB( CurValues^[I], LogEntrySize ) ;
		END ;
	    END ;
            IF CARDINAL( ABS(StructID) ) >= StructIDCounter THEN
               ProgramErrorAndHalt( 'LogFile module: invalid Structure ID' ) ;
            END ;
            IF StructID >= 0 THEN
               CurValues^[StructID].Count := Number ;
	    ELSE
               MakeReal( VStrPtr, StrPtr ) ;
               CurValues^[-StructID].SRecNo  := StrPtr^.SRecNo ;
               CurValues^[-StructID].SRecPos := StrPtr^.SRecPos ;
(* m.s.               ReleasePage( VStrPtr, StrPtr ) ; *)
            END ;
            Offset := CARDINAL( TokenNo - CurBaseTokenNo ) ;
            IF Offset > 255 THEN
		(* this will only hapen if we allow long line folding       *)
		(* which would permit more than 255 words per line.         *)
		(* Currently: input line is max of 255 chars, thus will have*)
		(* less than 255 words per line per log entry!!		    *)
		FOR I := 1 TO (Offset DIV 256) DO
		    AddTextToDB( DummyLog, LogEntrySize ) ;
		END ;
		CurValues^[ABS(StructID)].TokenNoOffset := SHORTCARD(Offset MOD 256);
	    ELSE
		CurValues^[ABS(StructID)].TokenNoOffset := SHORTCARD( Offset );
	    END ;
	    CurBaseTokenNo := TokenNo ;  (* for next relative offset value *)

            (* save position of Structure Id, note use of overlay area    *)
            (* thus both Number and VStrPtr are lost.  Not needed anymore *)
            LRecNo  := HRecNo ;
            (* the correct offset position is set by taking into account of BaseTokenNo *)
            LRecPos := CHR( (HRecPos-TSIZE(LONGCARD)) DIV LogEntrySize) ;
(*  m.s.           MarkDirty( VLogEntry )  ; *)
            AddTextToDB( CurValues^[ABS(StructID)], LogEntrySize) ;
            VTempLogEntry := Next ;
(* m.s.            ReleasePage( VLogEntry, LogEntry ) ; *)
         END ;
         VLogEntry := VTempLogEntry ;
      END ;
      (* M.S. - added the following if then *)
      IF HRecPos = 0 THEN (* exceptional case where exactly 255 records in last record, prevents creating blank record *)
		(* write current values at beginning of Hyper record for each Id *)
(* m.s. - n/a		CurBaseTokenNo := TokenNo ; *)
		AddTextToDB( CurBaseTokenNo, LogEntrySize ) ;
		FOR I := 0 TO StructIDCounter-1 DO
		    CurValues^[I].TokenNoOffset := 0 ;	(* assure lookup table is always set to 0 *LP* *)
		    AddTextToDB( CurValues^[I], LogEntrySize ) ;
		END ;
      END ;
      EndLog := HRecNo ;
      DEALLOCATE( CurValues, TSIZE(HLogDataType) * StructIDCounter ) ; (*m.s.*)

   END WriteLogListToDB ;

PROCEDURE LogFileInitCode ;
    BEGIN
	VLastLogEntry := VirtNil ;
	InitSpaceType( VLogUnusedSpace ) ;
	Fill( ADR(StringsStartIndex), SIZE(StringsStartIndex), 0C ) ;
    END LogFileInitCode ;
    	
END LogFile .
