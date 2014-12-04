IMPLEMENTATION MODULE SearchUtils;
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

(*V4=Dbg Debugging code *)
(*V5=NoDbg No Debugging code *)

IMPORT RULES, Str;
IMPORT BitOps, WordBase ;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE;
FROM GlobalDefs IMPORT StrAny;

FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, DiscardList, GetItemData, FindItem,
              GetFirstItem, GetNextItem, ItemDataPresent, ReleaseItemHold;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, InsertListItem;
FROM DataLinkModule IMPORT
  (* types *) DataLink, DataLinkType, DataLinkPROC, DisposeDataProcType,
              DataLinkArrayPntr,
  (* procs *) InitLink, InitAndDefineAsList, DisposeLink,
              OpenForSending, OpenForReceiving, SendData, ReceiveData,
              CloseForSending, CloseForReceiving, GetTACTList, PutTACTList,
              BuildProcessData, DummyDisposeDataProc, LaunchProcesses,
              DisposeProcessData;
FROM ListData IMPORT
  (* types *) ItemType, DataItemPntr,
  (* procs *) MakeTypeDataItem, MarkAsUsed, CompareDataItems, MakeTokenDataItem;
FROM ResMessages IMPORT
  (* procs *) MsgString, PutResError, PutResWarning;
FROM DBData IMPORT NoTokensInDB, BeginType ;
FROM ScannerSource IMPORT
  (* type *) ItemDataType;
FROM ParserSource IMPORT
  (* procs *) Parser;
FROM ErrorBase IMPORT  ProgramErrorAndHalt;
FROM HyperBase IMPORT HRecPntr, NilHRecPntr;
FROM HyperDataModel IMPORT
  (* Types *) HyperData, HTypePntr, HyperRType, HTypeData, HOccurData,
              HTokenData, HLogDataType;
FROM TACTDataServices IMPORT GetTDBTokenData, VirtToTACTList;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) GetType, FreeTypeHandle;
FROM TokenBase IMPORT
   (* Procs *) GetTokenNo, GetTokenHRec ;
FROM UnitBase IMPORT
   (* Procs *) GetUnitContext ;
FROM RuleWindow IMPORT
  (* type *)  RuleWindowDataType,
  (* vars *)  RuleWindowData ;
FROM ListUtils IMPORT
  (* types*) PosOrderData,
  (* Proc *) StartPosOrder, NextPosOrder, FinishPosOrder;
FROM UnitBase IMPORT
  (* Proc *) GetUnitLogPosContext ;
FROM VirtMem IMPORT VirtAddr, NILVirt ,VMAccess, VMRelease, VMMarkChanged;
FROM MainLists IMPORT PoolNoForSearchWorkingSpace;
FROM OccurListModule IMPORT InitializeOccurList;

(*<Dbg
FROM Trace IMPORT
(*procs*) TWriteLn,TWriteChar,TWriteString,TWriteInt,TWriteCard,TWriteAddr,
          TWriteStrHex,CloseTFile;
Dbg>*)

CONST
   MaxNumbLinksToMerge = 31;


PROCEDURE UserSuspendsSearch(): BOOLEAN;
VAR Ch:   CHAR;
BEGIN
   RETURN FALSE;
END UserSuspendsSearch;

PROCEDURE GetTokenListForType(TypeVA:   VirtAddr; (* To DataItem, type=typetype*)
                          VAR List:     TACTList);
VAR TypeData:    DataItemPntr;
BEGIN
   TypeData := VMAccess(TypeVA);
   IF TypeData^.Contents = NILVirt THEN List := InitializeOccurList(TypeVA)
   ELSE VirtToTACTList(TypeData^.Contents, List) END;
   VMRelease(TypeVA);
END GetTokenListForType;

PROCEDURE MergeDataLinks(InLinks: DataLinkArrayPntr;
                         NoIn:    CARDINAL;
                         OutLink: DataLink;
                         Data:    ADDRESS);
TYPE
    updatetype = SET OF [0..MaxNumbLinksToMerge-1];
VAR
    rslt:    INTEGER;
    i:       CARDINAL;
    idip:    DataItemPntr;
    data:    ARRAY[0..MaxNumbLinksToMerge-1] OF VirtAddr (* to DataItem *) ;
    update:  updatetype;
    hcur:    CARDINAL;
    hcurdip: DataItemPntr;
    cur :    CARDINAL;
    done:    BOOLEAN;

BEGIN
   FOR i := 0 TO NoIn-1 DO
      OpenForReceiving(InLinks^[i],DontCare);
      IF NOT ReceiveData(InLinks^[i], data[i]) THEN
         data[i] := NILVirt;
         CloseForReceiving(InLinks^[i])
      END;
   END;

   OpenForSending(OutLink,DontCare);

   done := FALSE;
   REPEAT
     hcur := 0;
     update := updatetype{};
     WHILE (hcur < NoIn) AND (data[hcur] = NILVirt) DO INC(hcur) END;
     IF hcur = NoIn THEN
        done := TRUE;
     ELSE
	update := updatetype{hcur};
        hcurdip := VMAccess(data[hcur]);
        FOR i := hcur + 1 TO NoIn-1 DO
           IF (data[i] <> NILVirt) THEN
              idip := VMAccess(data[i]);
              rslt := CompareDataItems(hcurdip,idip);
              IF (rslt = 1) THEN
                 VMRelease(data[hcur]);
                 hcur := i;
                 hcurdip := idip;
                 update := updatetype{i};
              ELSIF (rslt = 0) THEN
                 INCL(update,i);
              ELSE
                 VMRelease(data[i]);
              END;
           END;
        END;

        VMRelease(data[hcur]);
        IF NOT SendData(OutLink,data[hcur]) THEN done := TRUE END;

        FOR i := hcur TO NoIn-1 DO
           IF i IN update THEN
              IF NOT ReceiveData(InLinks^[i], data[i]) THEN
                 data[i] := NILVirt;
                 CloseForReceiving(InLinks^[i])
              END;
           END;
        END;
     END;	(* IF hcur = NoIn THEN *)
   UNTIL done OR (SearchResult > SearchWarned);

   FOR i := 0 TO NoIn-1 DO
      IF data[i] <> NILVirt THEN CloseForReceiving(InLinks^[i]) END;
   END;
   CloseForSending(OutLink);
END MergeDataLinks;

PROCEDURE DoSpanCollocation(InData:  DataLinkArrayPntr; (* always 1 only *)
                            Numb:    CARDINAL;          (* always 1 only *)
                            OutData: DataLink;
                            Info:    ADDRESS); (* should always be NIL *)
VAR
   CurrentVA	: VirtAddr (* to DataItem *) ;
   CurrentDat	: DataItemPntr;
   CurrentType	: ItemType;
   done         : BOOLEAN;

PROCEDURE HandleToken(Dat:  VirtAddr (* to DataItem *));
VAR
   NodePos	: LONGINT ;
   StartRange,
   EndRange	: LONGINT ;
   TokenNo	: LONGINT ;
   TokFilePos	: HRecPntr ;
   CollTokVA	: VirtAddr (* to DataItem *) ;
   CollTokDat	: DataItemPntr;
   StartToken	: HRecPntr;
   EndToken	: HRecPntr;
   Pntr		: DataItemPntr (* for Dat -- will be freed *) ;
BEGIN
   Pntr := VMAccess(Dat);
   GetTokenNo( Pntr^.FilePos, NodePos) ;
   VMRelease(Dat);

   WITH RuleWindowData DO
	IF UnitID = 0 (* word context *) THEN
	   StartRange := NodePos - LONGINT( ConfBefore ) ;
	   EndRange   := NodePos + LONGINT( ConfAfter ) ;
	ELSE
	   GetUnitContext( Dat, UnitID, ConfBefore, ConfAfter,
				StartToken, EndToken ) ;
	   GetTokenNo( StartToken, StartRange ) ;
	   GetTokenNo( EndToken, EndRange ) ;
	END ;
   END ;
   IF StartRange < 1 THEN  StartRange := 1  END ;
   IF EndRange > NoTokensInDB THEN  EndRange := NoTokensInDB  END ;
   FOR TokenNo := StartRange TO EndRange DO
	IF TokenNo <> NodePos THEN  (* don't include the Node token itself *)
	   GetTokenHRec( TokenNo, TokFilePos ) ;
           MakeTokenDataItem(CollTokVA, PoolNoForSearchWorkingSpace ,CollTokDat);
           CollTokDat^.FilePos := TokFilePos;
	   VMRelease(CollTokVA);
	   done := NOT SendData(OutData, CollTokVA);
	   IF done THEN RETURN END;
	END ;
   END;
END HandleToken;

PROCEDURE HandleType( Dat : VirtAddr (* to DataItem *) ) ;
VAR
   PosList	: TACTList;
   PosItem	: TACTListItem;
   TokenVA	: VirtAddr (* to DataItem *);
   TokenDat	: DataItemPntr;
BEGIN
   GetTokenListForType( Dat, PosList);
   NewListItem(PosList, PosItem);
   IF NOT GetFirstItem(PosList, PosItem) THEN RETURN END;
   REPEAT
      GetItemData(PosList, PosItem, TokenVA, TokenDat);
      ReleaseItemHold(PosList, PosItem);
      HandleToken(TokenVA);
   UNTIL done OR (NOT GetNextItem(PosList, PosItem));
   DisposeListItem(PosList, PosItem);  (* *LP* *)
   DiscardList(PosList);
END HandleType;

BEGIN
   OpenForReceiving(InData^[0], DontCare);
   OpenForSending(OutData, DontCare);
   done := NOT ReceiveData(InData^[0], CurrentVA);

   WHILE NOT done DO
      CurrentDat := VMAccess(CurrentVA);
      CurrentType := CurrentDat^.DataType;
      VMRelease(CurrentVA);

      CASE CurrentType OF
	CatType  : ProgramErrorAndHalt('Cat Type not yet supported in SPAN') |
	TypeType : HandleType(CurrentVA); |
	TokenType: HandleToken(CurrentVA);
      END;

(*    IF KeyPressed() THEN done := UserSuspendsSearch() END; *)
      done := done OR (SearchResult > SearchWarned);
      done := done OR (NOT ReceiveData(InData^[0], CurrentVA));
   END;
   CloseForReceiving(InData^[0]);
   CloseForSending(OutData);
END DoSpanCollocation ;

PROCEDURE DoPos(InData:  DataLinkArrayPntr; (* always 1 only *)
                Numb:    CARDINAL;          (* always 1 only *)
                OutData: DataLink;
                Info:    ADDRESS); (* should always be NIL *)
VAR
   done		: BOOLEAN;
   CurrentVA	: VirtAddr (* to DataItem *) ;
   CurrentDat	: DataItemPntr;
   CurrentType	: ItemType;

PROCEDURE HandleType2( Dat : VirtAddr (* to DataItem *) ) ;
VAR
   PosList	: TACTList;
   PosItem	: TACTListItem;
   TokenVA	: VirtAddr (* to DataItem *);
   TokenDat	: DataItemPntr;
BEGIN
   GetTokenListForType( Dat, PosList);
   NewListItem(PosList, PosItem);
   IF NOT GetFirstItem(PosList, PosItem) THEN RETURN END;
   REPEAT
      GetItemData(PosList, PosItem, TokenVA, TokenDat);
      ReleaseItemHold(PosList, PosItem);
      done := NOT SendData(OutData, TokenVA);
(*    IF KeyPressed() THEN done := UserSuspendsSearch() END; *)
      done := done OR (SearchResult > SearchWarned);
   UNTIL done OR (NOT GetNextItem(PosList, PosItem));
   DisposeListItem(PosList, PosItem);  (* *LP* *)
   DiscardList(PosList);
END HandleType2;

BEGIN
   OpenForReceiving(InData^[0], DontCare);
   OpenForSending(OutData, DontCare);
   done := NOT ReceiveData(InData^[0], CurrentVA);

   WHILE NOT done DO
      CurrentDat := VMAccess(CurrentVA);
      CurrentType := CurrentDat^.DataType;
      VMRelease(CurrentVA);

      CASE CurrentType OF
	CatType  : ProgramErrorAndHalt('Cat Type not yet supported in DoPos') |
	TypeType : HandleType2(CurrentVA); |
	TokenType: done := NOT SendData(OutData, CurrentVA);
      END;
(*    IF KeyPressed() THEN done := UserSuspendsSearch() END; *)
      done := (SearchResult > SearchWarned);
      done := done OR (NOT ReceiveData(InData^[0], CurrentVA));
   END;
   CloseForReceiving(InData^[0]);
   CloseForSending(OutData);
END DoPos;

PROCEDURE BuildSimilByParsing(  VAR RuleNo	: CARDINAL;
                                VAR SPntr       : SimilDataPntr): BOOLEAN;
    VAR
	ItemData:   ItemDataType;
        Pattern:    StrAny;
        Percentage: CARDINAL;
        size:       CARDINAL;

PROCEDURE GetNumberFromItem(): CARDINAL;
    VAR
	OK	: BOOLEAN;
	Numb	: CARDINAL;
    BEGIN
	Numb := CARDINAL(Str.StrToCard(ItemData.IntStr,10,OK));
	IF NOT OK THEN ProgramErrorAndHalt('In SIMIL: Bad number conversion occurred') END;
	RETURN Numb;
    END GetNumberFromItem;

BEGIN (* BuildSimilByParsing *)
   SPntr := NIL;
   Percentage := 100 ;	(* assume some defaults *)
   Pattern[0] := 0C ;
   REPEAT
      RuleNo := Parser(FALSE,ItemData);
(*<Dbg
      TWriteString('BuildSimilByParsing:Rule:');
      TWriteCard(RuleNo,7);
      TWriteString(',Item:');
      TWriteString(ItemData.IntStr);
      TWriteLn;
Dbg>*)
      CASE RuleNo OF
        RULES.SimilWord1, RULES.SimilWord2:
	   Str.Copy(Pattern, ItemData.AlpStr ) ;
      | RULES.SimilNumber:
           Percentage := GetNumberFromItem();
           IF (Percentage > 100) OR (Percentage < 1) THEN
	      (*RES OLD MSG 267
	      Please use a percentage value between 1 and 100 in your SIMILarity
	      Specification.
	      *)
    	      PutResError( (*RES REM INS*) 267 );
              RETURN FALSE
           END ;
      ELSE (* ignore it *)
      END;
   UNTIL (RuleNo = RULES.SimilDone) OR (RuleNo >= 1000 (* SYNTAX error *) );
   IF RuleNo < 1000 THEN
      size := 4 (* 2 * CARDINAL *) + Str.Length(Pattern) + 1;
      ALLOCATE(SPntr, size);
      SPntr^.Size := size;
      SPntr^.Percentage := Percentage;
      Str.Copy(SPntr^.Pattern, Pattern);
   END;
   RETURN RuleNo = RULES.SimilDone;
END BuildSimilByParsing;


(* Ratcliff/Obershelp Pattern Matching -- Dr. Dobb's Journal Nov. 1988  *)
(* 	letter to the Editor, pages 12 and 118.  Complete article in	*)
(* 	Dr. Dobb's Journal July 1988, pages 48-51.			*)

PROCEDURE Similarity( Str1, Str2 : ARRAY OF CHAR ) : CARDINAL ;
    VAR
	Len1, Len2	: INTEGER ;

    (* Recursive Greatest Common sub-string *)
    PROCEDURE GCsubstr( Start1, End1, Start2, End2 : INTEGER ) : INTEGER ;
	VAR
	   a1, a2,
	   b1, b2,
	   s1, s2	: INTEGER;
	   I		: INTEGER ;
	   Max		: INTEGER;
	BEGIN
	   IF (End1 <= Start1) OR (End2 <= Start2) THEN  (* Str1 OR Str2 empty string *)
		RETURN 0
	   END ;
	   IF (End1 = Start1 + 1) AND (End2 = Start2 + 1) THEN  (* Str1 AND Str2 have 1 char.  They cannot be equal*)
		RETURN 0
	   END ;
	   Max := 0 ;
	   b1  := End1 ;
	   b2  := End2 ;
	   a1  := Start1 ;
	   WHILE a1 < b1 DO
		a2 := Start2 ;
		WHILE a2 < b2 DO
		   IF Str1[ a1 ] = Str2[ a2 ] THEN
			(* How long is the common substring ? *)
			I := 1 ;
			(* Note: BOOLEAN( str[...] ) assumes that string is 0C terminated *)
			WHILE (a1+I < Len1) AND (Str1[a1+I] = Str2[a2+I]) DO
			   INC( I );
			END ;
			IF I > Max THEN
			   Max := I ;
			   s1  := a1 ;
			   s2  := a2 ;
			   b1  := End1 - Max ;
			   b2  := End2 - Max ;
			END ;
		   END ;
		   INC( a2 ) ;
		END ;
		INC( a1 ) ;
	   END ;
	   IF Max = 0 THEN  RETURN 0  END ;
	   INC( Max, GCsubstr( s1 + Max, End1, s2 + Max, End2 ) ) ;  (* RHS *)
	   INC( Max, GCsubstr( Start1, s1, Start2, s2 ) ) ;	     (* LHS *)
	   RETURN Max ;
	END GCsubstr ;
	
    BEGIN
	Len1 := Str.Length( Str1 ) ;
	Len2 := Str.Length( Str2 ) ;
	IF (Len1 = 0) OR (Len2 = 0) THEN (* check for null string case *)
	   RETURN 0
	ELSIF (Len1 = 1) AND (Len2 = 1) AND (Str1[0] = Str2[0]) THEN (* check for easiest case *)
	   RETURN 100
	END ;
	RETURN (200 * GCsubstr( 0, Len1, 0, Len2 )) DIV (Len1 + Len2)
    END Similarity ;

PROCEDURE DoSimil(InData:  DataLinkArrayPntr; (* always 1 only *)
                  Numb:    CARDINAL;          (* always 1 only *)
                  OutData: DataLink;
                  Info:    ADDRESS); (* SimilDataItemPntr *)
VAR
   CurrentVA	: VirtAddr (* to DataItem *) ;
   CurrentDat	: DataItemPntr;
   HWordDat	: DataItemPntr;
   Word		: StrAny;
   tPos		: HRecPntr;
   tHandle		: HTypeHandle;
   NumbFound	: CARDINAL;
   SPntr		: SimilDataPntr;
   done		: BOOLEAN;
BEGIN
   SPntr := SimilDataPntr(Info);
   NumbFound := 0;
   OpenForReceiving(InData^[0], DontCare);
   OpenForSending(OutData, DontCare);
   CurrentDat := NIL;
   done := NOT ReceiveData(InData^[0], CurrentVA);
   IF done THEN
      CloseForReceiving(InData^[0]);
      CloseForSending(OutData);
      RETURN
   END;

   REPEAT
      CurrentDat := VMAccess(CurrentVA);
      CASE CurrentDat^.DataType OF
        TypeType:
	   Str.Copy(Word,CurrentDat^.TypeFileData.Word);
      | TokenType:
	   IF CurrentDat^.HeadWord = NILVirt THEN
              IF NOT CurrentDat^.TokenDataLoaded THEN
                 GetTDBTokenData(CurrentDat);
                 VMMarkChanged(CurrentVA);
              END;
	      tPos.Rec := CurrentDat^.TokenFileData.HRecNo + BeginType;
	      tPos.Idx := ORD(CurrentDat^.TokenFileData.HRecPos);
	      GetType(tPos,tHandle);
	      BitOps.UnPack( tHandle^^.PackedWord, Word (* SortTempStr*), WordBase.SortNoBitsPerChar ) ;
(*	      Str.Copy(Word, tHandle^^.PackedWord); *)
	      FreeTypeHandle(tHandle);
	   ELSE
              HWordDat := VMAccess(CurrentDat^.HeadWord);
	      Str.Copy(Word,HWordDat^.TypeFileData.Word);
              VMRelease(CurrentDat^.HeadWord);
	   END;
(*
      | RefNameType:
	   Str.Copy(Word,RefsNameListPntr^[CurrentDat^.FilePos.Idx]^.Name);
      | RefStringType:
	   Str.Copy(Word, CurrentDat^.SortStr^.String ) ;
*)
      ELSE
	ProgramErrorAndHalt('SIMIL: CurrentData type currently not supported')
      END;

      IF Similarity( SPntr^.Pattern, Word ) >= SPntr^.Percentage THEN
	 done := NOT SendData(OutData, CurrentVA);
	 INC(NumbFound);
      END;
      VMRelease(CurrentVA);
      done := (SearchResult > SearchWarned);
      done := done OR (NOT ReceiveData(InData^[0], CurrentVA));
   UNTIL done;

   IF (NOT RuleWindowData.IgnoreErrs) AND (NumbFound = 0) AND (SearchResult <= SearchWarned) THEN
      (*RES OLD MSG 111
      A SIMILarity Specification selected nothing.
      *)
      PutResWarning( (*RES REM INS*) 111 );
      SearchResult := SearchWarned;
   END;
   CloseForReceiving(InData^[0]);
   CloseForSending(OutData);
END DoSimil;

PROCEDURE DisposeSimilDataPntr(VAR Item: ADDRESS); (* SimilDataItemPntr *)
VAR
	SPntr		: SimilDataPntr;
BEGIN
   SPntr := SimilDataPntr(Item);
   DEALLOCATE(SPntr, SPntr^.Size);
   Item := NIL;
END DisposeSimilDataPntr;

(* ==================================================== *)

CONST
   DataOrListItemSize = 17; (* Data=4 DPos=4 + Type=1 + PosOrderData=4 + TACTList=4 *)

TYPE
   DataOrListType = (DLinkType, TListType);
   DataOrListBase = RECORD
      Data:     VirtAddr (* to DataItem *);
      DPos:     HRecPntr (* FilePos from DataItem *) ;
      CASE Type :DataOrListType OF
        DLinkType:    DLink:   DataLink;
      | TListType:    POrder:  PosOrderData;
                      TList:   TACTList;
      END;
   END;
   DataOrListArray = POINTER TO ARRAY[0..2047] OF DataOrListBase;

PROCEDURE InitDorLArrayItem(AccessInfo:  DataOrListArray;
                            i:           CARDINAL;
                            AccessType:  DataLinkType;
                            DaLink:      DataLink);
BEGIN
   WITH AccessInfo^[i] DO
      Data := NILVirt;
      IF AccessType = ListLink THEN
         GetTACTList(DaLink, PoolNoForSearchWorkingSpace, TList);
         StartPosOrder(TList, POrder);
         Type := TListType;
      ELSE
         DLink := DaLink;
         Type := DLinkType;
         OpenForReceiving(DLink, DontCare);
      END;
   END;
END InitDorLArrayItem;

PROCEDURE FinishDorLArray(VAR AccessInfo:  DataOrListArray;
                              Numb:        CARDINAL);
VAR i:   CARDINAL;
BEGIN
    FOR i := 0 TO Numb - 1 DO
      WITH AccessInfo^[i] DO
         IF Type = DLinkType THEN
            CloseForReceiving(DLink);
         ELSE
            FinishPosOrder(POrder);
            DiscardList(TList);
         END;
      END;
    END;
    DEALLOCATE(AccessInfo, DataOrListItemSize * Numb);
END FinishDorLArray;

PROCEDURE GetNextDItemP(DorLArray: DataOrListArray;
                        Item:      CARDINAL): BOOLEAN;
VAR Pntr:  DataItemPntr;
    rslt:  BOOLEAN;
BEGIN
   WITH DorLArray^[Item] DO
      IF Type = DLinkType THEN rslt := ReceiveData(DLink, Data)
      ELSE rslt := NextPosOrder(POrder, Data) END;

      IF NOT rslt THEN
         DPos := NilHRecPntr;
         RETURN FALSE
      END;
      Pntr := VMAccess(Data);
      DPos := Pntr^.FilePos;
      VMRelease(Data);
   END;
   RETURN TRUE;
END GetNextDItemP;

(* ==================================================== *)

PROCEDURE PhraseSearch(InData:  DataLinkArrayPntr;
                       Numb:    CARDINAL;
                       OutData: DataLink;
                       Info:    ADDRESS); (* PhraseDataPntr *)
VAR AccessInfo:    DataOrListArray;
    i:             CARDINAL;
    PData:         PhraseDataPntr;
    continue:      BOOLEAN;
    matches:       BOOLEAN;
    rslt:          LONGINT;
    rsltpos:       CARDINAL;
    tData:         DataItemPntr;
    tVA:           VirtAddr; (* to DataItem *)
    NumbOut:       CARDINAL;
    LOffset:       LONGINT;
    PosOfZero:     LONGINT;

PROCEDURE CorrectDistance( ItemNo: CARDINAL; Distance : CARDINAL ) : LONGINT ;
VAR
    IthPos:     LONGINT;
    IthData:    DataItemPntr;
BEGIN
   GetTokenNo( AccessInfo^[ItemNo].DPos, IthPos);
   RETURN IthPos - VAL(LONGINT,Distance) - PosOfZero;
END CorrectDistance ;

BEGIN
    PData := PhraseDataPntr(Info);
    LOffset := VAL(LONGINT,PData^.OutOffset);
    ALLOCATE(AccessInfo, DataOrListItemSize * Numb);

    IF PData^.OutOffset = 0 THEN rsltpos := 0
    ELSE rsltpos := MAX(CARDINAL) END;

    FOR i := 0 TO Numb - 1 DO
       IF INTEGER(PData^.InLinkData[i].Offset) = PData^.OutOffset THEN
          rsltpos := i
       END;
       InitDorLArrayItem(AccessInfo, i, PData^.InLinkData[i].Access, InData^[i])
    END;

    OpenForSending(OutData, DontCare);

    continue := TRUE;
    i := 0;
    WHILE continue AND (i < Numb) DO
       continue := GetNextDItemP(AccessInfo,i);
       INC(i);
    END;

    IF NOT continue THEN NumbOut := MAX(CARDINAL) (* to skip error message at end *)
    ELSE NumbOut := 0 END;

    GetTokenNo( AccessInfo^[0].DPos, PosOfZero);
    WHILE continue DO
       i := 1;
       matches := TRUE;
       WHILE continue AND matches AND (i < Numb) DO
          rslt := -1;
          WHILE continue AND (rslt < 0) DO
             rslt := CorrectDistance(i, PData^.InLinkData[i].Offset);
             IF rslt < 0 THEN continue := GetNextDItemP(AccessInfo,i) END;
             continue := (SearchResult <= SearchWarned) AND continue;
          END;
          matches := rslt = 0;
          INC(i);
       END;
       IF continue AND matches THEN
           INC(NumbOut);
           IF rsltpos <> MAX(CARDINAL) THEN
              continue := SendData(OutData,AccessInfo^[rsltpos].Data)
           ELSE
              rslt := PosOfZero + LOffset;
              IF (rslt > 0) AND (rslt <= NoTokensInDB) THEN
                 MakeTokenDataItem(tVA, PoolNoForSearchWorkingSpace, tData);
                 GetTokenHRec(rslt, tData^.FilePos);
                 continue := SendData(OutData,tVA);
              END;
           END;
       END;
       IF continue THEN
          continue := GetNextDItemP(AccessInfo,0);
          IF continue THEN GetTokenNo( AccessInfo^[0].DPos, PosOfZero) END;
       END;
    END;

    FinishDorLArray(AccessInfo,Numb);

    CloseForSending(OutData);
    IF (NOT RuleWindowData.IgnoreErrs) AND (NumbOut = 0) AND (SearchResult <= SearchWarned) THEN
       (*RES OLD MSG 218
       Your Phrase Query (using "|") selected nothing.
       *)
       PutResWarning( (*RES REM INS*) 218 );
       SearchResult := SearchWarned;
    END;
END PhraseSearch;

PROCEDURE DisposePhraseData(VAR Item: ADDRESS); (* PhraseDataPntr *)
VAR temp:    PhraseDataPntr;
BEGIN
   temp := PhraseDataPntr(Item);
   DEALLOCATE(temp,temp^.Size);
   Item := NIL;
END DisposePhraseData;

PROCEDURE NewPhraseDataPntr(Numb:    CARDINAL;
                        VAR InData:  ARRAY OF PhraseBase (* read only *)):
                            PhraseDataPntr;
VAR temp:    PhraseDataPntr;
    size:    CARDINAL;
BEGIN
   size := 4 (* 2*CARDINAL *) + Numb * 3 (* CARDINAL + DataLinkType *);
   ALLOCATE(temp,size);
   WITH temp^ DO
      Size := size;
      FOR size := 0 TO Numb - 1 DO InLinkData[size] := InData[size] END;
      OutOffset := 0;
   END;
   RETURN temp;
END NewPhraseDataPntr;

PROCEDURE InWordContext( Left, Right : HRecPntr;
                     VAR LeftPos, RightPos: LONGINT) : BOOLEAN ;
BEGIN
   WITH RuleWindowData DO
	(* word context *)
	GetTokenNo( Left, LeftPos ) ;
        IF Right = NilHRecPntr THEN
           RightPos := MAX(LONGINT);
           RETURN FALSE;
        END;
	GetTokenNo( Right, RightPos ) ;
	IF RightPos = LeftPos THEN	(* *LP* *)
	   RETURN FALSE	
	ELSIF RightPos < LeftPos THEN
	   RETURN VAL(CARDINAL, LeftPos - RightPos) <= ConfBefore
	ELSE
	   RETURN VAL(CARDINAL, RightPos - LeftPos) <= ConfAfter
	END ;
   END ;
END InWordContext ;

PROCEDURE DisposeBinaryDataPntr(VAR Item: ADDRESS); (* PhraseDataPntr *)
VAR temp:  BinaryDataPntr;
BEGIN
   temp := BinaryDataPntr(Item);
   DISPOSE(temp);
   Item := NIL;
END DisposeBinaryDataPntr;

PROCEDURE GetLogPos(Token: VirtAddr (* to DataItem *) ): LONGINT;
VAR  Pntr:   DataItemPntr;
     rslt:   LONGINT;
BEGIN
   Pntr := VMAccess(Token);
   IF NOT Pntr^.TokenDataLoaded THEN 
      VMMarkChanged(Token);
      GetTDBTokenData(Pntr)
   END;
   WITH Pntr^.TokenFileData DO
      rslt := LONGINT( LRecNo ) * LONGINT( 256 ) + LONGINT( LRecPos )
   END ;
   VMRelease(Token);
   RETURN rslt;
END GetLogPos;

PROCEDURE WithInRange (InData:  DataLinkArrayPntr;
                       Numb:    CARDINAL;
                       OutData: DataLink;
                       Info:    ADDRESS); (* PhraseDataPntr *)
VAR
   PBArray      : BinaryDataPntr;
   AccessInfo   : DataOrListArray;
   Loop		: BOOLEAN ;
   NumbOut      : CARDINAL;
   LeftPos, RightPos: LONGINT;
   StartRange:	LONGINT ;
   EndRange:	LONGINT ;

PROCEDURE WithInRangeForWords;
BEGIN
   LOOP
      IF InWordContext( AccessInfo^[LeftSide].DPos,
	   AccessInfo^[RightSide].DPos, LeftPos, RightPos ) THEN
         IF NOT SendData(OutData,AccessInfo^[LeftSide].Data) THEN RETURN END;
         INC( NumbOut );
         IF NOT GetNextDItemP(AccessInfo,LeftSide) THEN RETURN END;
      ELSIF LeftPos < RightPos THEN
         IF NOT GetNextDItemP(AccessInfo,LeftSide) THEN RETURN END;
      ELSE
         IF NOT GetNextDItemP(AccessInfo,RightSide) THEN RETURN END;
      END ;
      IF (SearchResult > SearchWarned) THEN RETURN END;
   END
END WithInRangeForWords;

PROCEDURE WithInRangeForOther;
VAR LeftTokNo, RightTokNo : LONGINT ;
BEGIN
   WITH RuleWindowData DO
      GetUnitLogPosContext( AccessInfo^[LeftSide].Data, UnitID, ConfBefore, ConfAfter,
		       StartRange, EndRange ) ;

(*    GetUnitLogPosContext will have loaded TokenData, if needed j.b.
      IF NOT AccessInfo^[RightSide].Data^.TokenDataLoaded THEN
         GetTDBTokenData(AccessInfo^[RightSide].Data)
      END; *)

      RightPos := GetLogPos(AccessInfo^[RightSide].Data);
      GetTokenNo( AccessInfo^[RightSide].DPos, RightTokNo );	(* *LP* *)
      GetTokenNo( AccessInfo^[LeftSide].DPos, LeftTokNo );
      LOOP
         IF (StartRange <= RightPos) AND (RightPos <= EndRange) AND (RightTokNo <> LeftTokNo) THEN
            IF NOT SendData(OutData,AccessInfo^[LeftSide].Data) THEN RETURN END;
            INC( NumbOut );
            IF NOT GetNextDItemP(AccessInfo,LeftSide) THEN RETURN END;
            GetUnitLogPosContext( AccessInfo^[LeftSide].Data, UnitID, ConfBefore, ConfAfter,
                                  StartRange, EndRange ) ;
	    GetTokenNo( AccessInfo^[LeftSide].DPos, LeftTokNo );	(* *LP *)
         ELSIF EndRange < RightPos THEN
            IF NOT GetNextDItemP(AccessInfo,LeftSide) THEN RETURN END;
            GetUnitLogPosContext( AccessInfo^[LeftSide].Data, UnitID, ConfBefore, ConfAfter,
                   StartRange, EndRange ) ;
	    GetTokenNo( AccessInfo^[LeftSide].DPos, LeftTokNo );	(* *LP *)
         ELSE
            IF NOT GetNextDItemP(AccessInfo,RightSide) THEN RETURN END;
            RightPos := GetLogPos(AccessInfo^[RightSide].Data);
	    GetTokenNo( AccessInfo^[RightSide].DPos, RightTokNo );	(* *LP* *)
         END ;
         IF (SearchResult > SearchWarned) THEN RETURN END;
      END ; (* LOOP *)
   END ;  (* WITH RuleWindowData DO *)
END WithInRangeForOther;

BEGIN
   PBArray := BinaryDataPntr(Info);
   ALLOCATE(AccessInfo, DataOrListItemSize * 2);
   FOR NumbOut := 0 TO 1 DO
       InitDorLArrayItem(AccessInfo,NumbOut, PBArray^[NumbOut], InData^[NumbOut])
   END;

   OpenForSending(OutData, DontCare);

   Loop := GetNextDItemP(AccessInfo,LeftSide);
   IF Loop THEN Loop := GetNextDItemP(AccessInfo,RightSide) END;

   IF Loop THEN 
      NumbOut := 0;
      IF RuleWindowData.UnitID = 0 (* word context *) THEN WithInRangeForWords
      ELSE  (* all other UnitID context *) WithInRangeForOther END ;

      IF (NOT RuleWindowData.IgnoreErrs) AND (NumbOut = 0) AND (SearchResult <= SearchWarned) THEN
         (*RES OLD MSG 219
         Your Proximity Query (using "&") selected nothing.
         *)
         PutResError( (*RES REM INS*) 219 );
         SearchResult := SearchWarned;
      END;
   END;

   FinishDorLArray(AccessInfo,2);
   CloseForSending(OutData);
END WithInRange;

PROCEDURE NotWithInRange (InData:  DataLinkArrayPntr;
                          Numb:    CARDINAL;
                          OutData: DataLink;
                          Info:    ADDRESS); (* PhraseDataPntr *)
VAR
   PBArray      : BinaryDataPntr;
   AccessInfo   : DataOrListArray;
   NumbOut      : CARDINAL;
   Loop         : BOOLEAN;
   LeftPos, RightPos: LONGINT;
   StartRange:	LONGINT ;
   EndRange:	LONGINT ;

PROCEDURE NotWithInRangeForWords(): BOOLEAN;
BEGIN
   IF NOT GetNextDItemP(AccessInfo,RightSide) THEN RETURN TRUE END;
   LOOP
     IF InWordContext( AccessInfo^[LeftSide].DPos,
	  AccessInfo^[RightSide].DPos, LeftPos, RightPos ) THEN
        IF NOT GetNextDItemP(AccessInfo,LeftSide) THEN RETURN FALSE END;
     ELSIF LeftPos < RightPos THEN
        INC( NumbOut );
        IF NOT SendData(OutData,AccessInfo^[LeftSide].Data) THEN RETURN FALSE END;
        IF NOT GetNextDItemP(AccessInfo,LeftSide) THEN RETURN FALSE END;
     ELSE
        IF NOT GetNextDItemP(AccessInfo,RightSide) THEN RETURN TRUE END;
     END ;
     IF (SearchResult > SearchWarned) THEN RETURN FALSE END;
   END ;
END NotWithInRangeForWords;

PROCEDURE NotWithInRangeForOther(): BOOLEAN;
VAR LeftTokNo, RightTokNo : LONGINT ;
BEGIN
   IF NOT GetNextDItemP(AccessInfo,RightSide) THEN RETURN TRUE END;
   WITH RuleWindowData DO
      GetUnitLogPosContext( AccessInfo^[LeftSide].Data, UnitID, ConfBefore, ConfAfter,
	 StartRange, EndRange ) ;

(*    GetUnitLogPosContext will have loaded TokenData, if needed j.b.
      IF NOT AccessInfo^[RightSide].Data^.TokenDataLoaded THEN
         GetTDBTokenData(AccessInfo^[RightSide].Data)
      END; *)
      RightPos := GetLogPos(AccessInfo^[RightSide].Data);
      GetTokenNo( AccessInfo^[RightSide].DPos, RightTokNo );	(* *LP* *)
      GetTokenNo( AccessInfo^[LeftSide].DPos, LeftTokNo );
      LOOP
	IF (StartRange <= RightPos) AND (RightPos <= EndRange) AND (RightPos <> LeftPos) THEN
           IF NOT GetNextDItemP(AccessInfo,LeftSide) THEN RETURN FALSE END;
           GetUnitLogPosContext( AccessInfo^[LeftSide].Data, UnitID, ConfBefore, ConfAfter,
					 StartRange, EndRange ) ;
	   GetTokenNo( AccessInfo^[LeftSide].DPos, LeftTokNo );
        ELSIF EndRange < RightPos THEN
           INC( NumbOut );
           IF NOT SendData(OutData,AccessInfo^[LeftSide].Data) THEN RETURN FALSE END;
           IF NOT GetNextDItemP(AccessInfo,LeftSide) THEN RETURN FALSE END;
           GetUnitLogPosContext( AccessInfo^[LeftSide].Data, UnitID, ConfBefore, ConfAfter,
		 StartRange, EndRange ) ;
	   GetTokenNo( AccessInfo^[LeftSide].DPos, LeftTokNo );
	ELSE
           IF NOT GetNextDItemP(AccessInfo,RightSide) THEN RETURN TRUE END;
           RightPos := GetLogPos(AccessInfo^[RightSide].Data);
	   GetTokenNo( AccessInfo^[RightSide].DPos, RightTokNo );	(* *LP* *)
	END ; (* IF (StartRange <= RightPos) ... *)
        IF (SearchResult > SearchWarned) THEN RETURN FALSE END;
      END ; (* LOOP *)
   END ; (* WITH RuleWindowData DO *)
END NotWithInRangeForOther;

PROCEDURE HandleNotWithinRange;
BEGIN
   IF RuleWindowData.UnitID = 0 (* word context *) THEN 
      IF NOT NotWithInRangeForWords() THEN RETURN END;
   ELSE  (* all other UnitID context *) 
      IF NOT NotWithInRangeForOther() THEN RETURN END;
   END;

   LOOP
      INC( NumbOut );
      IF NOT SendData(OutData,AccessInfo^[LeftSide].Data) THEN RETURN END;
      IF NOT GetNextDItemP(AccessInfo,LeftSide) THEN RETURN END;
      IF (SearchResult > SearchWarned) THEN RETURN END;
   END;
END HandleNotWithinRange;

BEGIN
   PBArray := BinaryDataPntr(Info);
   ALLOCATE(AccessInfo, DataOrListItemSize * 2);
   FOR NumbOut := 0 TO 1 DO
       InitDorLArrayItem(AccessInfo,NumbOut, PBArray^[NumbOut], InData^[NumbOut])
   END;

   OpenForSending(OutData, DontCare);

   IF GetNextDItemP(AccessInfo,LeftSide) THEN
      NumbOut := 0;
      HandleNotWithinRange;
      IF (NOT RuleWindowData.IgnoreErrs) AND (NumbOut = 0) AND (SearchResult <= SearchWarned) THEN
         (*RES OLD MSG 220
         Your not-in-Proximity Query (using "~") selected nothing.
         *)
         PutResError( (*RES REM INS*) 220 );
         SearchResult := SearchWarned;
      END;
   END;

   FinishDorLArray(AccessInfo,2);
   CloseForSending(OutData);
END NotWithInRange;

PROCEDURE ListNegateProc (InData:  DataLinkArrayPntr;
                          Numb:    CARDINAL;
                          OutData: DataLink;
                          Info:    ADDRESS); (* NIL *)
VAR
   LeftDLink:     DataLink;
   RightList:	  TACTList ;
   RightItem:	  TACTListItem ;
   RightLoop:     BOOLEAN;
   TokensPresent: BOOLEAN;
   RecID:         HRecPntr;
   TList:         TACTList;
   TListItem:     TACTListItem;
   TokenData:     DataItemPntr;
   AllTokensIn:   BOOLEAN;
   dummy:         BOOLEAN;
   NumbIn, NumbOut: CARDINAL;
   LeftData,
   RightData:     DataItemPntr;
   TVA,
   LeftVA,
   RightVA:       VirtAddr;

PROCEDURE DoProcessingNow;

PROCEDURE HandleListOfTokens;
VAR OList:     TACTList;
    OLItem:    TACTListItem;
    DVA:       VirtAddr;
    TokenData: DataItemPntr;
BEGIN
   IF LeftData^.Contents = NILVirt THEN OList := InitializeOccurList(LeftVA)
   ELSE VirtToTACTList(LeftData^.Contents, OList) END;
   NewListItem(OList, OLItem);

   AllTokensIn := TRUE;
   IF NOT GetFirstItem(OList, OLItem) THEN RETURN END;
   REPEAT
      GetItemData(OList, OLItem, DVA, TokenData);
      ReleaseItemHold(OList, OLItem);
      IF FindItem(RightList,DVA, RightItem) THEN AllTokensIn := FALSE
      ELSE dummy := InsertListItem(DVA,TList) END;
   UNTIL NOT GetNextItem(OList, OLItem);
   DisposeListItem(OList, OLItem);
   DiscardList(OList);
END HandleListOfTokens;

BEGIN
   LOOP
      IF (SearchResult > SearchWarned) THEN RETURN END;

      IF NOT ReceiveData(LeftDLink, LeftVA) THEN RETURN END;
      INC(NumbIn);
      IF FindItem(RightList,LeftVA, RightItem) THEN
         (* ignore the item from the left *)
      ELSE
         LeftData := VMAccess(LeftVA);
         CASE LeftData^.DataType OF
           TypeType:
             IF NOT TokensPresent THEN
                IF NOT SendData(OutData,LeftVA) THEN RETURN END;
                INC(NumbOut)
             ELSE
                TList := NewMemoryList(PoolNoForSearchWorkingSpace);
                HandleListOfTokens;
                IF AllTokensIn THEN
                   IF NOT SendData(OutData,LeftVA) THEN RETURN END;
                   INC(NumbOut)
                ELSE
                   NewListItem( TList, TListItem ) ;
                   AllTokensIn := GetFirstItem( TList, TListItem ) ;
                   WHILE AllTokensIn DO
                      GetItemData(TList, TListItem, TVA, TokenData);
                      ReleaseItemHold(TList, TListItem);
                      IF NOT SendData(OutData,TVA) THEN 
                         DisposeListItem( TList, TListItem ) ;
                         DiscardList(TList);
                         RETURN
                      END;
                      INC(NumbOut);
                      AllTokensIn := GetNextItem( TList, TListItem ) ;
                   END;
                   DisposeListItem( TList, TListItem ) ;
                END;
                DiscardList(TList);
             END;
         | TokenType:
             RecID.Rec := LeftData^.TokenFileData.HRecNo + BeginType;
             RecID.Idx := ORD(LeftData^.TokenFileData.HRecPos);
             IF NOT ItemDataPresent(RightList,TypeType,RecID,RightItem) THEN
                IF NOT SendData(OutData,LeftVA) THEN RETURN END;
                INC(NumbOut)
             END;
         ELSE ProgramErrorAndHalt('Unexpected type in ListNegateProc')
         END;
         VMRelease(LeftVA);
      END;
   END;
END DoProcessingNow;

BEGIN
   NumbOut := 0;
   NumbIn := 0;
   LeftDLink := InData^[0]; (* used as synonym j.b. *)
   OpenForReceiving(LeftDLink,DontCare);
   GetTACTList(InData^[1], PoolNoForSearchWorkingSpace, RightList);

   NewListItem( RightList, RightItem ) ;

   TokensPresent := FALSE;
   RightLoop := GetFirstItem( RightList, RightItem ) ;
   WHILE (RightLoop) AND (NOT TokensPresent) DO
      GetItemData(RightList, RightItem, RightVA, RightData);
      TokensPresent := RightData^.DataType = TokenType;
      ReleaseItemHold(RightList, RightItem);
      RightLoop := GetNextItem( RightList, RightItem ) ;
   END;

   OpenForSending(OutData, DontCare);

   DoProcessingNow;

   DisposeListItem( RightList, RightItem ) ;
   DiscardList( RightList );
   CloseForReceiving(LeftDLink);
   IF (NOT RuleWindowData.IgnoreErrs) AND
   (NumbIn > 0) AND (NumbOut = 0) AND (SearchResult <= SearchWarned) THEN
      (*RES OLD MSG 255
      Your Query (using "-") selected nothing.
      *)
      PutResError( (*RES REM INS*) 255 );
      SearchResult := SearchWarned;
   END;
   CloseForSending(OutData);
END ListNegateProc;

PROCEDURE KeyPressed(): BOOLEAN;
BEGIN
   RETURN FALSE;
END KeyPressed;

END SearchUtils.
