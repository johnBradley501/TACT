IMPLEMENTATION MODULE RuleWindow;
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

IMPORT ASCII, Str, TACTProcesses ;
FROM Utils IMPORT TrimBlanks;
FROM SYSTEM IMPORT ADDRESS, ADR;

(* Shrink *)
FROM ParseRuleSource IMPORT ParseResult, ParseRuleCriteria(* , InitParseRule *);
FROM ScannerSource IMPORT InitScanner;
FROM SearchUtils IMPORT
  (* Vars *) NumberInSelListArray, SelectedListArray,
             SearchResultType, SearchResult;
FROM ParserSource IMPORT
  (* procs *) InitializeParserTables;
FROM DataLinkModule IMPORT
  (* types *) DataLink,
  (* procs *) GetTACTList, LaunchProcesses, DisposeProcessData, InitDataLinks;
FROM RegularExpr IMPORT FirstREMsg;
(* FROM WhenWork IMPORT InitWhenWork; *)
(* FROM RuleIO IMPORT InitRuleIO; *)
(* Shrink *)
FROM WWWUtils IMPORT ParseData, StartPre, EndPre,
                      GetItem, FindItem, FindItemCard;
FROM ResText IMPORT OutputTextItem;
FROM Translations IMPORT XlateLine, File2Int, LenD, CurrentModeType,
          OutFile, XWrStr, XWrLn, XWrNXlate;
FROM GlobalDefs IMPORT StrAny;
FROM StringIO IMPORT
   SWriteString, SWriteChar, SWriteCard;
FROM MainLists IMPORT
  (* const*) PoolNoForOldRuleList, PoolNoForOldSelect, PoolNoForSelectLists,
             PoolNoForListFromRule, PoolNoForSearchWorkingSpace,
  (* type *) PosListStatusType, DiscardMainListType,
  (* vars *) ListFromRule, ListFromRulePos, SelectedList,
             SelectedListPos, SelectedListEmpty,
  (* proc *) DiscardMainLists;
FROM ResMessages IMPORT
   (*proc*) MsgString, PutResError, PutResWarning, PutResMessage,
            GetResMessage;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM RefsBase IMPORT GetIDFromName, GetNameFromID;
FROM WordBase IMPORT
  (* Procs *) SortToIntWord;
FROM ListData IMPORT DataItemPntr;
FROM VirtMem IMPORT VirtAddr, FreePool, ChangePoolNo;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, DisposeListItem, GetFirstItem, ReleaseItemHold,
              GetNextItem, DiscardList, GetItemData, GetListType;
FROM MemTACTList IMPORT
  (* procs *)  NewMemoryList, CopyList;
FROM TypeListModule IMPORT MakeTACTTypeList;

FROM PositionManagement IMPORT
  (* procs *) FirstDisplayItem, DiscardDisplayItem, InitialDisplayItem;
(*<Dbg
FROM Trace IMPORT
(*vars *) DoTrace,
(*procs*) TWriteString, TWriteLn;
Dbg>*)

(*<Dbg
VAR
    debug : BOOLEAN ;
    TempRuleList : TACTList ;
Dbg>*)


PROCEDURE InitRuleWindMenu(pd: ParseData);
VAR T:  StrAny;
    dummy: CARDINAL;
    npd:   ParseData;
    i:     CARDINAL;

PROCEDURE GetAndFixCriteria;
VAR i,al,ns:  CARDINAL;
    w:     ARRAY[0..MaxQueryLen] OF CHAR;
    cm:    CurrentModeType;
    ed:    BOOLEAN; (* placeholder use only *)

PROCEDURE ConcatQueryParts();
VAR
   wk:     ARRAY[0..255] OF CHAR;
   qn:     ARRAY[0..10] OF CHAR;
   i,j:    CARDINAL;
BEGIN
   Str.Copy(qn, 'query');
   i := 5;
   j := 0;
   w[0] := 0C;
   SWriteCard(qn, i, j, 0);
   WHILE FindItem(pd, npd, qn, wk) DO
     Str.Append(w, wk);
     i := 5;
     INC(j);
     SWriteCard(qn, i, j, 0);
   END;
END ConcatQueryParts;

PROCEDURE DisplayQuery;
VAR
   dummy1,IOresult:  CARDINAL;
BEGIN
   XWrNXlate(OutFile, '<P>Query: <tt>', IOresult);
   XWrNXlate(OutFile, w, IOresult);
   XWrNXlate(OutFile, '</tt><HR>', IOresult);
END DisplayQuery;

BEGIN
    WITH RuleWindowData DO
       DoSelect := TRUE;
       IgnoreErrs := FALSE;
       ed := FindItemCard(pd, npd, 'qcontext_before', ConfBefore);
       ed := FindItemCard(pd, npd, 'qcontext_after',ConfAfter);
       IF FindItem(pd, npd, 'qcontext_unit', w) THEN
          cm.ModeIn := '0'; cm.ModeOut := '0';
          XlateLine(File2Int,'?',w,cm,al,LenD,ns,ed,UnitName);
          UnitID := GetIDFromName(UnitName);
          IF UnitID = MAX(INTEGER) THEN
             ProgramErrorAndHalt('Improper Query Context Unit');
          END;
       ELSE
          UnitID := 0;
          UnitName := 'WORDS';
       END;
   END;

   IF NOT FindItem(pd, npd, 'query', w) THEN
      IF FindItem(pd, npd, 'query0', w) THEN
         ConcatQueryParts();
      ELSE
         ProgramErrorAndHalt('Unable to find Query');
      END;
   END;
   DisplayQuery;
   i := 0;
   WHILE (w[i] <> 0C) DO
      IF w[i] < ' ' THEN w[i] := ' ' END;
      INC(i);
   END;
   w[i] := ' ';
   w[i+1] := 0C;
   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine(File2Int,'?',w,cm,al,LenD,ns,ed,RuleWindowData.Criteria);
END GetAndFixCriteria;

BEGIN
   GetAndFixCriteria;
(*<Dbg
   debug := FALSE ;
Dbg>*)

    InitScanner;
(*  InitParseRule;  *)
    InitDataLinks;
(*  InitWhenWork; *)

    WITH RuleWindowData DO
       (* values for other constants are assigned via initialization  j.b. *)
       IF NOT GetNameFromID(UnitID,T,dummy) THEN
          ProgramErrorAndHalt('GetNameFromID could not get given ID')
       END;
       SortToIntWord(T,UnitName);
    END;
    InitializeParserTables;
(* Shrink *)
END InitRuleWindMenu;

PROCEDURE ProcessRule(pd: ParseData): BOOLEAN;

(* Shrink *)
VAR
   ch1:          CHAR;
   OldCrit:      CriteriaType;
   rc:           CARDINAL;
   Done:         BOOLEAN;
   L:            CARDINAL;
   TLink:        DataLink;
   NeedSelect:   BOOLEAN;
   FirstTrial:   BOOLEAN;
   PResult:      ParseResult;
   i:	         CARDINAL ;
   dDIP:         DataItemPntr;
   Something:    BOOLEAN;

(* Shrink *)
BEGIN
(* Shrink *)
   InitRuleWindMenu(pd);
   RuleWindowData.IgnoreErrs := FALSE (*IgnoreErrors*);

   ListFromRule := NewMemoryList(PoolNoForListFromRule);
   NewListItem(ListFromRule, ListFromRulePos);
   WITH RuleWindowData DO

     NumberInSelListArray := 0 ;		(* <<-- is this right place ?? *)
     FreePool( PoolNoForSearchWorkingSpace );
     IF ParseOK <> ParseRuleCriteria(TLink,NeedSelect) THEN
        ProgramErrorAndHalt('Parse of Query was not OK');
     END;
     FirstREMsg := TRUE ;
     SearchResult := SearchOK;
     LaunchProcesses;
     GetTACTList(TLink, PoolNoForSelectLists, SelectedList);
     TACTProcesses.YIELD;
     FreePool( PoolNoForSearchWorkingSpace );

     Something := GetFirstItem(SelectedList, ListFromRulePos);
     IF (NOT Something) AND (SearchResult < SearchFailed) THEN
        (*RES OLD MSG 336
        Your Query did not select anything.
        *)
        PutResError( (*RES REM INS*) 336 );
        HALT;
     ELSIF (SearchResult = SearchFailed) THEN HALT;
     END;
     FOR i := 1 TO NumberInSelListArray DO
       DiscardList( SelectedListArray[ i ] )
     END ;
   END; (* WITH WorkingRuleWindData *)
   SelectedListEmpty := FALSE;
   RETURN TRUE;
END ProcessRule;

(*
PROCEDURE FoldToFitCriteria(VAR input:     ARRAY OF CHAR; (* read-only *)
                            VAR output:    CriteriaType): BOOLEAN; (* True=fit*)
CONST
   MaxLen = CriteriaLen * NumbCriteria;
TYPE
   StrPntr = POINTER TO StrAny;
VAR
   i,j,k,l: CARDINAL;
   p:       StrPntr;
   temp:    CriteriaType;
   ch:      CHAR;

BEGIN
   FOR i := 0 TO NumbCriteria - 1 DO temp[i][0] := 0C END;
   l := Str.Length(input);
   IF l > MaxLen THEN RETURN FALSE END;
   p := ADR(input);
   i := 0;
   WHILE (i <= NumbCriteria -2) AND (l > CriteriaLen-1) DO
      j := CriteriaLen-1;
      WHILE (j > 0) AND (p^[j] <> ' ') AND (p^[j] <> ',') AND (p^[j] <> ';')DO
         DEC(j)
      END;
      IF j = 0 THEN RETURN FALSE END;
      k := j;
      REPEAT INC(j) UNTIL (p^[j] <> ' ');
      WHILE (k > 0) AND (p^[k] = ' ') DO DEC(k) END;
      IF p^[k] <> ' ' THEN
         ch := p^[k+1];
         p^[k+1] := 0C;
         Str.Copy(temp[i],p^);
         p^[k+1] := ch;
      END;
      IF p^[j] = 0C THEN
         output := temp;
         RETURN TRUE
      END;
      p := ADR(p^[j]);
      DEC(l,j);
      INC(i);
   END;
   IF l > CriteriaLen THEN RETURN FALSE END;
   Str.Copy(temp[i],p^);
   output := temp;
   RETURN TRUE;
END FoldToFitCriteria;

PROCEDURE SubstituteInCriteria(VAR criteria:     CriteriaType;
                                   line,pos,len: CARDINAL;
                                   text:         ARRAY OF CHAR): BOOLEAN;
VAR
   hold:   ARRAY[0 .. NumbCriteria*CriteriaLen] OF CHAR;
   i:      CARDINAL;
   hpos:   CARDINAL;
   first:  BOOLEAN;
   temp:   StrAny;
BEGIN
   hold[0] := 0C;
   hpos := 0;
   first := TRUE;
   FOR i := 0 TO NumbCriteria-1 DO
      TrimBlanks(criteria[i],criteria[i]);
      IF criteria[i][0] <> 0C THEN
         IF first THEN first := FALSE
         ELSE SWriteChar(hold,hpos,' ',0) END;
         IF i = line THEN
            Str.Copy(temp,criteria[i]);
            Str.Delete(temp,pos,len);
            Str.Insert(temp,text,pos);
            SWriteString(hold,hpos,temp,0);
         ELSE
            SWriteString(hold,hpos,criteria[i],0);
         END;
      END;
   END;
   RETURN FoldToFitCriteria(hold,criteria);
END SubstituteInCriteria;
*)
END RuleWindow.
