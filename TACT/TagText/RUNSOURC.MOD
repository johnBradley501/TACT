IMPLEMENTATION MODULE RunSource ;

(* copyright (c) 1991-96 Ian Lancashire, Lidio Presutti, University of Toronto *)

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

(*V1=Production *)
(*V2=SpaceCheck *)

FROM SYSTEM IMPORT TSIZE, SIZE ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
IMPORT FIO, IO, TWB ;
FROM KeyTranslation IMPORT FILEText, WriteScreenField;

(*<SpaceCheck
FROM CheckMemory IMPORT
  (* Procs *) MemSnapShot ;
SpaceCheck>*)

(* temporary, for debugging

FROM Windows IMPORT
  (* Procs *) PutMessage ;
*)
IMPORT Lib;
(* FROM DBFile IMPORT
  (* Procs *) StartDBFile, FinishDBFile ;
FROM WordProcessing IMPORT
  (* Procs *) WritePntrData ;
*)
FROM ProcTextSource IMPORT
  (* Procs *) ProcessText,
  (* Vars  *) NoWords, NoTags ;
FROM WordBase IMPORT SortToIntWord, IntToSortWord ;
FROM TokenDataSource IMPORT TypeNumber, InputFileID ;
FROM RunPan IMPORT
(* Procs *) SetupRunWindows, CleanupRunWindows, PutRunStatus, PutPercentage ;
(* -- only needed when debugging ---  **LP**
FROM DumpLists IMPORT
  (* Procs *) DumpStructLists ;
*)
FROM VirtualMemory IMPORT
  (* Type  *) VirtualAddrType,
  (* Const *) VirtualPageSize, VirtNil,
  (* Procs *) (* ProgramErrorAndHalt, *) IsEqual, AllocateSpace, MakeReal, (* m.s.ReleasePage, MarkDirty, *)
		InitSpaceType, (* HasRealMem, *) InitVirtualMemory, EndVirtualMemory ;

(* FROM  VirtHash IMPORT InitVirtHash, VWordUnusedSpace ; *)
FROM ResMessages IMPORT
   (* proc *)  MsgString, MsgCard, PutResError, PutResWarning, ResAskUser, GetResMessage;
FROM VirtHash IMPORT
  (* Procs *) InsertHash, SearchHashTable, FreeHashMemory, InitVirtHash, LineType,
              DictPtr, DictList, DictEntryPtr, DictEntry, DictListSize, TestHash ;

FROM GlobalDefs IMPORT StrAny ;
FROM StartUp IMPORT FileData, OutFile, IncludeType,
     Tag1Field, Tag2Field, WordField ;
FROM Str IMPORT Compare, Copy, Delete, Slice, Length, ItemS, Insert, Append ;
FROM Utils IMPORT BFile, BCreate, WrStr, WrLn, BClose, BOpen, ReadLine,
     GetXlationType, RWType ;
(* FROM LongSort IMPORT
  (* Procs *) LTurboSort, LSortRelease, LSortReturn, LSortEOS, LSortReset,
              LSortFreeUp, LSortGetPos,
  (* Vars  *) SortOK ;
*)
FROM PrintModule IMPORT AbortForFileIO;
FROM Translations IMPORT
  (* Type  *) XFileType, XlateStrAny, CurrentModeType,
  (* Vars  *) Int2FAlp, LenD,
  (* Procs *) XClose, XOpenInput, XReadLine, XlateLine, XWrStr, XWrLn, XAppend,
              XOpenOutput, XWriteLine ;
FROM Windows  IMPORT
  (* Const *) RegularAttr ;
FROM ResMenus IMPORT
  (* type *)  MenuID,
  (* proc *)  StartMenu, CardField, CharField, MakeMenu, DestroyMenu, GetFieldInfo,
		ClearMenuArea, ShowFixedText, ShowMenu;
FROM StringIO IMPORT SWriteString, SWriteChar, SWriteCard, SWriteLongInt ;

TYPE
   WordAny = ARRAY[0..25] OF CHAR ;
   WordPtr = POINTER TO WordAny ;
   CharSet = ARRAY [0..2] OF CHAR ;

CONST
   Seps = CharSet( 255C, 11C, ' ');
   YPosForStatusMenu = 21;  (* m.s. - was 19 *)

VAR
   Message   : StrAny ;
   MsgPos, Percentage    : CARDINAL ;
   ErrorMsg  : StrAny ;
   Word      : WordPtr ;
   LastPercentage, SortResult : CARDINAL ;
   Count, NoCompares           : LONGCARD ;
   InputFileName, OutputFileName : StrAny ;
   Action : RWType ;
   VDataUnusedSpace, VDictUnusedSpace  : VirtualAddrType ;
   EnoughData, dummy: BOOLEAN ;
   BadChar: CHAR ;
   IOResult: CARDINAL ;
   InsertStr: StrAny ;
   StatsWind	: TWB.WinType ;
   LenStatus	: CARDINAL ;
   PosXStatus	: CARDINAL ;
   PosYStatus	: CARDINAL ;
   PosXPerCent	: CARDINAL ;
   PosYPerCent	: CARDINAL ;
   MsgTxt	: StrAny;


PROCEDURE Log2( Num : LONGCARD ) : CARDINAL ;
   VAR
	log2	: CARDINAL ;
	I	: CARDINAL ;
	Temp	: LONGCARD ;
   BEGIN (* calc the number bits in Num *)
	Temp := Num ;
	log2 := 0 ;	
	WHILE Temp <> 0 DO
	   INC( log2 ) ;
	   Temp := Temp DIV 2 ;
	END ;
	(*<Debug
	IO.WrStr( 'Number:' ) ;
	IO.WrLngCard( Num, 10 ) ;
	IO.WrStr( ' log2:' ) ;
	IO.WrCard( log2, 5 ) ;
	IO.WrLn ;
	Debug>*)
(*
	(* now take an upper bound if 2 ** log2  + 2 ** (log2 - 2) < Num *)
	(* ie. if Num is bigger than a quarter of log2 range		 *)
	Temp := 1 ;
	FOR I := 1 TO log2 DO
	   INC( Temp, Temp ) ;
	END ;
	IF Temp + (Temp DIV 4) < Num THEN
	   INC( log2 )
	END ;
*)
	RETURN log2
   END Log2 ;

PROCEDURE TrimAllBlanks(     InStr  : ARRAY OF CHAR;
                      VAR OutStr : ARRAY OF CHAR);
   VAR  I, J : CARDINAL;
   BEGIN
      Copy( OutStr, InStr ) ;
      WHILE  (OutStr[0] = ' ') OR (OutStr[0] = 11C) DO
         Delete( OutStr , 0, 1) ;
      END ;
      I := Length( OutStr ) ;
      WHILE (I > 0) AND (OutStr[I-1] = ' ') DO
         DEC( I )
      END ;
      IF I <= HIGH(OutStr) THEN OutStr[I] := 0C END ;
   END TrimAllBlanks ;

PROCEDURE GetString( InStr: ARRAY OF CHAR ; Loc : CARDINAL; Len : CARDINAL;
                    VAR Str : ARRAY OF CHAR ) ;
  BEGIN
    Slice( Str, InStr, Loc, Len ) ;
    TrimAllBlanks( Str, Str ) ;
  END GetString ;


PROCEDURE InsertInDict(  Line            : ARRAY OF CHAR ) ;
  VAR
     CurrentWord       : StrAny ;
     p, s, t: VirtualAddrType ;
     Dummy  : BOOLEAN ;
     HashId : LONGINT ;
     Dict   : DictPtr ;
     ThisDictEntry, Test          : DictEntryPtr ;
     VTest, VDictEntry  : VirtualAddrType ;
  BEGIN
     ItemS( CurrentWord, Line, Seps, 0 ) ;
     IF SearchHashTable( CurrentWord, VDictEntry, HashId) THEN
       (* MakeReal( VDictEntry, ThisDictEntry ) ; *)
        IO.WrStr(' Duplicate word in dictionary ' ) ;
        IO.WrStr( CurrentWord ) ;
        IO.WrLn ;
     ELSE
        AllocateSpace(VDictEntry, ThisDictEntry, VDataUnusedSpace, TSIZE( DictEntry )) ;
        AllocateSpace(p , Dict, VDictUnusedSpace, DictListSize ) ;
        ItemS( ThisDictEntry^.Word, Line, Seps, WordField ) ;
        ItemS( ThisDictEntry^.Tag1, Line, Seps, Tag1Field );
        ItemS( ThisDictEntry^.Tag2, Line, Seps, Tag2Field ) ;

(*        ItemS( ThisDictEntry^.POS, Line, Seps, 1 ) ;
        IF (WordForm = Lemma) OR (TagForm = Lemma) THEN
           ItemS( ThisDictEntry^.Lemma, Line, Seps, 2 ) ;
        ELSIF (WordForm = Concept) OR (TagForm = Concept) THEN
           ItemS( ThisDictEntry^.Lemma, Line, Seps, 3 ) ;
        END ;
*)
        InsertHash( HashId, p, VDictEntry, CurrentWord ) ;
(*        ReleasePage( p, Dict) ;
        ReleasePage( VDictEntry, ThisDictEntry ) ;
*)
     END ;
     (* for testing *)
(*     IF SearchHashTable( CurrentWord, VTest, HashId) THEN
        MakeReal( VTest , Test ) ;
     END ;
*)
  END InsertInDict ;

PROCEDURE BuildDict ;
   VAR
      LineIn : StrAny ;
(*      DCTFile : XFileType ; *)
      DCTFile: BFile;

   BEGIN
      Count := 0 ;
      LastPercentage := 0 ;
      (*RES OLD MSG 178
      Processing Dictionary.
      *)
      PutRunStatus( (*RES REM INS*) 178 ) ;
      BOpen( DCTFile, FileData.DCTFileName, ReadType, IOResult ) ;
      NoWords := FIO.Size( DCTFile.FileID ) DIV 50 ;
      dummy := ReadLine( DCTFile, LineIn, EnoughData, IOResult ) ;
(*      dummy := XOpenInput( FileData.DCTFileName, 0C, FILEText, DCTFile, ErrorMsg ) ;
      NoWords := FIO.Size( DCTFile.ID.FileID ) DIV 50 ;
      dummy := XReadLine( DCTFile, BadChar, LineIn, EnoughData, IOResult ) ;
*)
      WHILE IOResult = 0 DO
           INC(Count);
           Percentage := VAL (CARDINAL , (Count * 100) DIV NoWords) ;
           IF Percentage >= LastPercentage THEN
              IF Percentage >= 100 THEN
        	 Percentage := 99  ;	(* fake a reasonable value *)
              END ;
              PutPercentage( Percentage , TRUE ) ;
              LastPercentage := Percentage ;
           END ;
        InsertInDict( LineIn ) ;
(*        dummy := XReadLine( DCTFile, BadChar, LineIn, EnoughData, IOResult ) ; *)
        dummy := ReadLine( DCTFile, LineIn, EnoughData, IOResult ) ;
      END ;
(*      XClose( DCTFile ) ; *)
      BClose( DCTFile, IOResult ) ;
END  BuildDict ;

(*
PROCEDURE LowcaseStr(InWord: ARRAY OF CHAR;
                 VAR OutWord: ARRAY OF CHAR);
  VAR
      I,IMAX :           CARDINAL;

  BEGIN
     OutWord[0] := 0C ;
     IF InWord[0] <> 0C THEN
        IMAX := Length(InWord) - 1 ;
        FOR I := 0 TO IMAX DO
           Append( OutWord , CharArray[InWord[I]] ) ;
        END ;
      END ;
  END LowcaseStr;
*)

PROCEDURE Run( BaseWind: TWB.WinType )  ;

  VAR
    IOResult : CARDINAL ;
	len : CARDINAL;
	MsgId : CARDINAL ;
	ch    : CHAR ;

  BEGIN
        SetupRunWindows ;
	MsgTxt[0] := 0C ;
(*	StartMenu(Percentage);
	CharField( MsgTxt );
	CardField(Percentage);
	MakeMenu( StatusMenuResID, StatusMenu);
	ClearMenuArea(BaseWind, 0, YPosForStatusMenu, StatusMenu);
	ShowFixedText(BaseWind, StatusMenu, 0, YPosForStatusMenu);
	Percentage := 0;
	ShowMenu(BaseWind, StatusMenu, 0, YPosForStatusMenu, Percentage);

	StatsWind := BaseWind ;

        GetFieldInfo( StatusMenu, 0, PosXStatus, PosYStatus, LenStatus ) ;
        INC( PosYStatus, YPosForStatusMenu ) ;
        GetFieldInfo( StatusMenu, 1, PosXPerCent, PosYPerCent, len ) ;
        INC( PosYPerCent, YPosForStatusMenu ) ;
*)
     InitVirtualMemory ;
     InitVirtHash;
     InitSpaceType( VDataUnusedSpace ) ;
     InitSpaceType( VDictUnusedSpace ) ;

     BuildDict ;

     (*<SpaceCheck MemSnapShot( 'Run - after "InitVirtualMemory" ' ) ; SpaceCheck>*)

   (*RES OLD MSG 100
     Reading Source Text
     *)
(*     BCreate(OutFile , FileData.OutFileName , TRUE, IOResult ) ; *)
     dummy := XOpenOutput( FileData.OutFileName, 0C, FILEText, OutFile, ErrorMsg ) ;
     Count := 0 ;
     PutRunStatus( (*RES REM INS*) 100 ) ;

     IF ProcessText() THEN
     END ;

   CleanupRunWindows ;
     (*<SpaceCheck MemSnapShot( 'Run - after "CleanupRunWindows" ' ) ; SpaceCheck>*)

  END Run ;

BEGIN
    Count := 0 ;
    LastPercentage := 0 ;
END RunSource .


