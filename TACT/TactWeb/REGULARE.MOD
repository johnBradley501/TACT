IMPLEMENTATION MODULE RegularExpr ;
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
(*V5=JPI JPI unique code *)

IMPORT RULES, Str;
IMPORT BitOps, WordBase ;
FROM MemoryManagement IMPORT DEALLOCATE;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResMessages IMPORT
   (*proc*)  MsgString, PutResError, PutResWarning;
FROM StringIO IMPORT
   SWriteString, SWriteChar;
FROM WordBase IMPORT
  (* Const *) NonRetDiacCode, ExtraCodeSep,
  (* Types *) AlphaCharType,
  (* Vars  *) SimpAlphTable, TypeOfChar,
  (* procs *) SortToIntWord, SortToFullWord;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames;
FROM HyperBase IMPORT HRecPntr;
FROM TACTListModule IMPORT
  (* types *) TACTListType, TACTList, TACTListItem,
  (* procs *) NewListItem, GetListType, DisposeListItem, ReleaseItemHold,
              GetItemData, GetFirstItem, GetNextItem, FindFromString,
              DiscardList;
FROM MemTACTList IMPORT
  (* procs *)  InsertListItem;
FROM GlobalDefs IMPORT StrAny;
FROM DBData IMPORT BeginType;
FROM HyperDataModel IMPORT
  (* Types *) HyperData, HTypePntr, HyperRType, HTypeData, HOccurData,
              HTokenData, HLogDataType;
FROM ListData IMPORT
  (* types *) ItemType, StringPntr, StringData, DataItem, DataItemPntr;
FROM TypeBase IMPORT
  (* types *) HTypeHandle,
  (* procs *) GetType, FreeTypeHandle;
FROM ParserSource IMPORT Parser;
FROM TACTDataServices IMPORT GetTDBTokenData;
FROM DataLinkModule IMPORT
  (* types *) DataLink, DataLinkType, DataLinkArrayPntr,
  (* procs *) OpenForSending, OpenForReceiving, SendData, ReceiveData,
              CloseForSending, CloseForReceiving, GetTACTList;
FROM SearchUtils IMPORT
   (* types *) SearchResultType,
   (* vars  *) SearchResult,
   (* procs *) UserSuspendsSearch;
FROM RuleWindow IMPORT
  (* type *)  RuleWindowDataType,
  (* vars *)  RuleWindowData;
FROM MainLists IMPORT PoolNoForSearchWorkingSpace;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMRelease, VMMarkChanged, VMAccess;

(*<Dbg
FROM Trace IMPORT
(*vars *) DoTrace,
(*procs*) TWriteLn,TWriteChar,TWriteString,TWriteInt,TWriteCard,TWriteAddr,
          TWriteStrHex,CloseTFile;
Dbg>*)

CONST
    ClosureAlp = 374C;
    EOLAlp = 373C;
    ANYAlp = 372C;
    CCLAlp = 371C;
    CCLDAlp = 370C;
    NCCLAlp = 367C;
    NCCLDAlp = 366C;
    LitCharAlp = 365C;
    LitDCharAlp = 364C;
    FindCharAlp = 363C;
    StrSize = 100;

TYPE
    RegExpBuildType = (StartRegExp,AddCharSeq,AddAnyChar,StartCCL,
            AddCCLString,DoCCLRange,AppendCCL,AppendNCCL,AddClosure,
            FinishReg);
    LStrAny = ARRAY[0..StrSize-1] OF CHAR;

VAR
   LP:      CARDINAL;
   BLChar:  CARDINAL;
   CCL:     ARRAY[0..80] OF CHAR;
   CCLL:    CARDINAL;

PROCEDURE ParseRegExp(VAR RuleNo:      CARDINAL;
                      VAR ItemData:    ItemDataType;
                      VAR Pat:         ARRAY OF CHAR;
                      VAR TypeOnly:    BOOLEAN): BOOLEAN;
VAR
   OK:              BOOLEAN;
   CouldbeWord:     BOOLEAN;
   FirstLetSeq:     BOOLEAN;

PROCEDURE BuildRegExp(GivenString: ARRAY OF CHAR;
                      BuildAction: RegExpBuildType): BOOLEAN;
VAR
   C1,C2:   CHAR;
   i:       CARDINAL;
   tmp:     ARRAY[0..1] OF CHAR;
   DiacIn:  BOOLEAN;
   Char1,Char2: ARRAY[0..8] OF CHAR;
(*<Dbg
   T:       ARRAY[0..255] OF CHAR;
Dbg>*)
BEGIN
   (*<Dbg
   IF DoTrace THEN TWriteString('BuildRegExp: Type:') END;
   Dbg>*)
   CASE BuildAction OF
     StartRegExp:
        (*<Dbg
        IF DoTrace THEN TWriteString('StartRegExp ') END;
        Dbg>*)
        LP := 0;
        Pat[0] := 0C
   | AddCharSeq:
        (*<Dbg
        IF DoTrace THEN TWriteString('AddCharSeq ') END;
        Dbg>*)
        i := 0;
        WHILE GivenString[i] <> 0C DO
           BLChar := LP;
           IF TypeOfChar[GivenString[i]] = Letter THEN tmp[0] := LitCharAlp
           ELSE tmp[0] := LitDCharAlp END;
           tmp[1] := GivenString[i];
           SWriteString(Pat,LP,tmp,0);
           INC(i);
        END;
   | AddAnyChar:
        (*<Dbg
        IF DoTrace THEN TWriteString('AddAnyChar ') END;
        Dbg>*)
        BLChar := LP;
        SWriteChar(Pat,LP,ANYAlp,0);
   | StartCCL:
        (*<Dbg
        IF DoTrace THEN TWriteString('StartCCL ') END;
        Dbg>*)
        CCL[0] := 0C;
        CCLL := 0;
   | AddCCLString:
        (*<Dbg
        IF DoTrace THEN TWriteString('AddCCLString ') END;
        Dbg>*)
        SWriteString(CCL,CCLL,GivenString,0);
   | DoCCLRange:
        (*<Dbg
        IF DoTrace THEN TWriteString('DoCCLRange ') END;
        Dbg>*)
        C1 := CCL[CCLL-1];
        CCL[CCLL] := 0C;
        DEC(CCLL);
        C2 := GivenString[0];
        Str.Delete(GivenString,0,1);
        IF C1 >= C2 THEN
           (*RES OLD MSG 163
           Please change the Specified Range %0 to %1.
           *)
(*         MsgString(C1,0);
           MsgString(C2,0);  *)
           SortToIntWord(C1, Char1) ;
           SortToIntWord(C2, Char2) ;
           MsgString(Char1,0);
           MsgString(Char2,0);
           PutResError( (*RES REM INS*) 163 );
           RETURN FALSE
        END;
        WHILE C1 <= C2 DO
           SWriteChar(CCL,CCLL,C1,0);
           INC(C1);
        END;
        SWriteString(CCL,CCLL,GivenString,0);
   | AppendCCL, AppendNCCL:
        (*<Dbg
        IF DoTrace THEN TWriteString('Append[N]CCL ') END;
        Dbg>*)
        BLChar := LP;
        DiacIn := FALSE;
        i := 0;
        WHILE (NOT DiacIn) AND (tmp[i] <> 0C) DO
            DiacIn := TypeOfChar[tmp[i]] = RetDiac;
            INC(i);
        END;
        IF DiacIn THEN
           IF BuildAction = AppendCCL THEN tmp[0] := CCLDAlp
                                      ELSE tmp[0] := NCCLDAlp END
        ELSE
           IF BuildAction = AppendCCL THEN tmp[0] := CCLAlp
                                      ELSE tmp[0] := NCCLAlp END
        END;
        tmp[1] := CHR(CCLL);
        SWriteString(Pat,LP,tmp,0);
        SWriteString(Pat,LP,CCL,0);
   | AddClosure:
        (*<Dbg
        IF DoTrace THEN TWriteString('AddClosure ') END;
        Dbg>*)
        Str.Insert(Pat,ClosureAlp,BLChar);
        INC(LP);
   | FinishReg:
        (*<Dbg
        IF DoTrace THEN TWriteString('FinishReg ') END;
        Dbg>*)
        IF (LP >= 2) AND (Pat[LP-2] = ClosureAlp) AND (Pat[LP-1] = ANYAlp) THEN
           Pat[LP-2] := 0C
        ELSE
           Pat[LP] := EOLAlp;
           Pat[LP+1] := 0C;
        END;
        IF (Pat[0] = ClosureAlp) AND (Pat[1] = ANYAlp) AND
        (Pat[2] = LitCharAlp) THEN
            Pat[0] := FindCharAlp;
            Str.Delete(Pat,1,2);
        END;
(* m.s. - March 94 - commenting this out allows users to select all words
        IF Pat[0] = 0C THEN
            (*RES OLD MSG 164
            UseBase does not support Regular Expressions that select everything.
            *)
            PutResError( (*RES REM INS*) 164 );
            RETURN FALSE
        END;
*)
   ELSE
      ProgramErrorAndHalt('Bad BuildAction in BuildRegExp');
   END;
   (*<Dbg
   IF DoTrace THEN
      TWriteString(',LP:');
      TWriteCard( LP,0);
      TWriteString(',BLChar:');
      TWriteCard( BLChar,0);
      TWriteString(',Pat:');
      TWriteStrHex(Pat);
      TWriteLn;
   END;
   Dbg>*)
   RETURN TRUE;
END BuildRegExp;

BEGIN
   OK := BuildRegExp(ItemData.AlpStr,StartRegExp);
   CouldbeWord := TRUE;
   FirstLetSeq := FALSE;
   WHILE OK AND (RuleNo <> RULES.FinishRegExpression) AND (RuleNo < 9999) DO
      RuleNo := Parser(FALSE,ItemData);
(*<Dbg
      TWriteString('ParseRegExp:Rule:');
      TWriteCard(RuleNo,7);
      TWriteString(',Item:');
      TWriteString(ItemData.IntStr);
      TWriteLn;
Dbg>*)
      CASE RuleNo OF
       | RULES.DoAddAnyChar:
           CouldbeWord := FALSE;
           OK := BuildRegExp(ItemData.AlpStr,AddAnyChar);
       | RULES.DoAppendCCL:
           CouldbeWord := FALSE;
           OK := BuildRegExp(ItemData.AlpStr,AppendCCL);
       | RULES.DoAppendNCCL:
           CouldbeWord := FALSE;
           OK := BuildRegExp(ItemData.AlpStr,AppendNCCL);
       | RULES.DoStartCCL:
           OK := BuildRegExp(ItemData.AlpStr,StartCCL);
       | RULES.DoAddCCLString:
           OK := BuildRegExp(ItemData.AlpStr,AddCCLString);
       | RULES.DoDoCCLRange:
           OK := BuildRegExp(ItemData.AlpStr,DoCCLRange);
       | RULES.DoAddCharSeq:
	   IF FirstLetSeq THEN
	      (*RES OLD MSG 217
	      There is a syntax error at "%0". You have perhaps omitted a Connector
	      like ",".
	      *)
	      MsgString( ItemData.IntStr, 0 );
	      PutResError( (*RES REM INS*) 217 );
	      OK := FALSE ;
	   ELSE
	      FirstLetSeq := TRUE ;
              OK := BuildRegExp(ItemData.AlpStr,AddCharSeq);
	   END ;
       | RULES.DoRegExpEscCode:
           CouldbeWord := FALSE;
           FirstLetSeq := TRUE ;
           OK := BuildRegExp(ItemData.AlpStr,AddCharSeq);
       | RULES.DoResetFirstLetSeq:
	   FirstLetSeq := FALSE;  (* just parsed a "." or "[" so OK *)
(*	| RULES.DoCheckLetSeqSet: *)
       | RULES.DoAddClosure:
           CouldbeWord := FALSE;
           FirstLetSeq := FALSE ;
           OK := BuildRegExp(ItemData.AlpStr,AddClosure);
       | RULES.FinishRegExpression:
           IF CouldbeWord THEN
              Str.Copy(Pat,ItemData.AlpStr);
              TypeOnly := TRUE;
           ELSE
              TypeOnly := FALSE;
              OK := BuildRegExp(ItemData.AlpStr,FinishReg);
           END;
      ELSE
         (* ignore parsing rule *)
      END;
   END;
   RETURN OK AND (RuleNo < 9999) ;
END ParseRegExp;

PROCEDURE PerformRegExp(VAR REData: RegExpOpTypeRecord);
VAR
    CurrentPos:   TACTListItem;
    CurrentDat:   DataItemPntr;
    CurrentVA:    VirtAddr;
    HeadDat:      DataItemPntr;
    CheckEnd:     BOOLEAN;
    done:         BOOLEAN;
    IniStr:       LStrAny;
    IniLen:       CARDINAL;
    Word:         LStrAny;
    Word2:        LStrAny;
    tPos:         HRecPntr;
    tHandle:      HTypeHandle;
    SPtr:	  StringPntr;

PROCEDURE GetInitPoint(VAR Pat:    ARRAY OF CHAR; (* read only *)
                       VAR IniStr: ARRAY OF CHAR;
                       VAR IniLen: CARDINAL;
                       VAR Item:   TACTListItem): BOOLEAN;
VAR
  Work:     LStrAny;
  L1, L2:   CARDINAL;
  dummy:    BOOLEAN;
  CheckEnd: BOOLEAN;
BEGIN
   L2 := 0;
   WHILE Pat[L2] = LitDCharAlp DO INC(L2,2) END;
   IF Pat[L2] <> LitCharAlp THEN
       IF NOT GetFirstItem(REData.InList,CurrentPos) THEN
          ProgramErrorAndHalt('Error(1) in GetInitPoint/DoRegExp')
       END;
       CheckEnd := FALSE;
   ELSE
       L1 := 0;
       WHILE (L2 < Str.Length(Pat)) AND (Pat[L2] = LitCharAlp) DO
          Work[L1] := SimpAlphTable[Pat[L2+1]];
          INC(L1);
          INC(L2,2);
       END;
       Work[L1] := 0C;
       dummy := FindFromString(Work,TypeType,REData.InList,Item);
       Str.Copy(IniStr,Work);
       IniLen := L1;
       CheckEnd := TRUE;
   END;
(*<Dbg
   IF DoTrace THEN
       TWriteString('GetInitPoint:, Pat:');
       TWriteStrHex(Pat);
       TWriteString(',Work:');
       TWriteStrHex(Work);
       TWriteString(',IniStr:');
       TWriteStrHex(IniStr);
       TWriteLn;
   END;
Dbg>*)
   RETURN CheckEnd;
   END GetInitPoint;

   PROCEDURE InitMatches(No:        CARDINAL;
                         Test:      ARRAY OF CHAR;
                     VAR InitConst: ARRAY OF CHAR): BOOLEAN;
   VAR
      J:   CARDINAL;
   BEGIN
      J := 0;
      REPEAT INC(J)
      UNTIL (J > No) OR (Test[J] = 0C) OR (Test[J] = ExtraCodeSep);

      Test[No] := 0C;
      RETURN 0 = Str.Compare(Test,InitConst);
   END InitMatches;

   (* The following code was adapted from "Matching Regular Expressions"
       in PC TechJournal May 1986.

      Code was subsequently modifed (in match_closure and amatch) to
       correct what I perceive to be a bug in the original code j.b. *)

   (*
      Search for the character C in the character class at pat[offset]
   *)

(*<JPI*)
   PROCEDURE amatch(VAR lin:    ARRAY OF CHAR;
                        offset: CARDINAL;
                    VAR pat:    ARRAY OF CHAR;
                        p:      CARDINAL): BOOLEAN; FORWARD;
(*JPI>*)

   PROCEDURE locate(c:      CHAR;
                VAR pat:    ARRAY OF CHAR;   (* read only *)
                    offset: CARDINAL): BOOLEAN;
     VAR
       i:     CARDINAL;
   BEGIN
   (* size of class is at pat[offset], characters follow *)
     i := offset+ORD(pat[offset]);     (*last position in class*)
     WHILE i > offset DO
        IF c = pat[i] THEN
           RETURN TRUE
        ELSE
           DEC(i, 1)
        END
     END;
     RETURN FALSE;
   END locate;

   (*
      Matches character pattern pat[p] against input line characters
      starting at lin[l].  Lin_ADVANCE=-1 means no match.
   *)
   PROCEDURE linAdvance(VAR lin: ARRAY OF CHAR; (* read only *)
                            l:   CARDINAL;
                        VAR pat: ARRAY OF CHAR; (* read only *)
                            p:   CARDINAL;
                        VAR amt: CARDINAL): BOOLEAN;
   VAR Result:   BOOLEAN;
       slush:    CARDINAL;
   BEGIN
     Result := FALSE;
     slush := 0;
     CASE pat[p] OF
       EOLAlp, ANYAlp, CCLAlp, NCCLAlp, LitCharAlp:
          WHILE (lin[l] <> 0C) AND (TypeOfChar[lin[l]] = RetDiac) DO
             INC(l);
             INC(slush)
          END;
     ELSE (* do nothing *)
     END;
     amt := 0;
     CASE pat[p] OF
         LitDCharAlp,
         LitCharAlp:
         IF lin[l] = pat[p+1] THEN
           amt := 1 + slush;
           Result := TRUE
         END
       | ANYAlp:
         IF lin[l] <> 0C THEN
           amt := 1 + slush;
           Result := TRUE
         END
       | EOLAlp:
         IF lin[l] = 0C THEN
           amt := 0 + slush;
           Result := TRUE
         END
       | CCLAlp, CCLDAlp:
         IF locate(lin[l], pat, p+1) THEN
           amt := 1 + slush;
           Result := TRUE
         END
       | NCCLAlp, NCCLDAlp:
         IF (lin[l] <> 0C) AND ( NOT (locate(lin[l], pat, p+1))) THEN
           amt := 1 + slush;
           Result := TRUE
         END
       ELSE
          ProgramErrorAndHalt("in lin_advance: can't happen")
     END; (*case*)
   (*<Dbg
   IF DoTrace THEN
      IF Result THEN TWriteString('linAdvance returns TRUE,')
                ELSE TWriteString('linAdvance returns FALSE,') END;
      TWriteCard(amt,0);
      TWriteLn;
   END;
   Dbg>*)
   RETURN Result
   END linAdvance;

   (*
      Returns offset of next pattern within PAT string.  Current pattern
      starts at PAT[P].  ex.  if pat="@c@a@t" and p=1 then pat_advance=3;
   *)
   PROCEDURE patAdvance(VAR pat: ARRAY OF CHAR; (* read only *)
                            p: CARDINAL): CARDINAL;
   BEGIN
     CASE pat[p] OF
         LitDCharAlp,
         LitCharAlp:      RETURN p+2
       | EOLAlp, ANYAlp:  RETURN p+1
       | CCLDAlp, NCCLDAlp,
         CCLAlp, NCCLAlp: RETURN p+ORD(pat[p+1])+2
       | ClosureAlp:      RETURN p+1
       ELSE
         ProgramErrorAndHalt("in pat_advance: can't happen");
     END; (*case*)
   END patAdvance;

   (*
      Match as many characters as possible with closure.
      Does rest of pattern match remaining characters on line?
      If not, shorted closure match by one and try again.
      If closure shorted to 0, no match is possible (match_close=-1)
   *)
   PROCEDURE matchClosure(VAR lin:      ARRAY OF CHAR; (* read only *)
                              offset:   CARDINAL;
                          VAR pat:      ARRAY OF CHAR; (* read only *)
                              p:        CARDINAL): BOOLEAN;
     VAR
       n, backtrack, increment: CARDINAL;
       linAResult:    BOOLEAN;
   BEGIN
     (*<Dbg
     IF DoTrace THEN
        TWriteString('match_closure offset:');
        TWriteCard(offset,0);
        TWriteString(',p:');
        TWriteCard(p,0);
        TWriteLn
     END;
     Dbg>*)
     n := offset;
     REPEAT
       linAResult := linAdvance(lin, n, pat, p, increment);
       IF linAResult THEN
         INC(n, increment)
       END;
     UNTIL (NOT linAResult) OR (lin[n] = 0C);

     (*<Dbg
     IF DoTrace THEN
        TWriteString('match_closure n:');
        TWriteCard(n,0);
        TWriteLn
     END;
     Dbg>*)
     FOR backtrack := n TO offset BY -1 DO
        IF amatch(lin, backtrack, pat, patAdvance(pat, p)) THEN
           (*<Dbg
           IF DoTrace THEN
              TWriteString('match_closure normal end:');
              TWriteCard(backtrack,0);
              TWriteLn
           END;
           Dbg>*)
           RETURN TRUE;
        END;
     END;
     (*<Dbg
     IF DoTrace THEN
        TWriteString('match_closure failed');
        TWriteLn
     END;
     Dbg>*)
     RETURN FALSE;
   END matchClosure;

   PROCEDURE DoFind(lin:   ARRAY OF CHAR;
                    l:     CARDINAL;
                VAR pat:   ARRAY OF CHAR; (* read only *)
                    p:     CARDINAL): BOOLEAN;
   BEGIN
     LOOP
       Str.Delete(lin,0,l);
       l := Str.Pos(lin, pat[p+1]);
       IF l >= HIGH(lin) THEN RETURN FALSE END;
       INC(l, 1);
       IF amatch(lin, l, pat, p+2) THEN RETURN TRUE END;
     END;
   END DoFind;

   PROCEDURE amatch(VAR lin:    ARRAY OF CHAR; (* read only *)
                        offset: CARDINAL;
                    VAR pat:    ARRAY OF CHAR; (* read only *)
                        p:      CARDINAL): BOOLEAN;
   (*
      Anchored match:  Does pattern PAT match input line starting at
      LIN[offset]?  Loop through PAT distinguishing the two cases;
      if PAT[P] is a closure, find appropriate closure size to match.
      Otherwise, just compare characters and update PAT and LIN indexes.
   *)
     VAR
       l, increment, closureEnd: CARDINAL;
       loop: BOOLEAN;
   BEGIN
     (*<Dbg
     IF DoTrace THEN
        TWriteString('amatch begins p:');
        TWriteCard(p,0);
        TWriteString(',offset:');
        TWriteCard(offset,0);
        TWriteLn
     END;
     Dbg>*)
     l := offset;
     WHILE (pat[p] <> 0C) DO
       IF pat[p] = ClosureAlp THEN
          (* match rest using match_closure *)
          RETURN matchClosure(lin, l, pat, patAdvance(pat, p))
       END;
       IF (lin[l] = 0C) AND (pat[p] <> EOLAlp) THEN
          (*<Dbg
          IF DoTrace THEN
             TWriteString('amatch returns FALSE(1)');
             TWriteLn
          END;
          Dbg>*)
          RETURN FALSE
       END;
       IF pat[p] = FindCharAlp THEN RETURN DoFind(lin,l,pat,p) END;
(*     IF pat[p] = ClosureAlp THEN
          (* match rest using match_closure *)
          RETURN matchClosure(lin, l, pat, patAdvance(pat, p))
       END; *)
       IF NOT linAdvance(lin, l, pat, p, increment) THEN
          (*<Dbg
          IF DoTrace THEN
             TWriteString('amatch returns FALSE(2)');
             TWriteLn
          END;
          Dbg>*)
          RETURN FALSE
       END;
       INC(l, increment);
       p := patAdvance(pat, p);
(*   WriteLn(trcfle,'AMatch continues: p: ',p,',l:',l);  *)
       (*<Dbg
       IF DoTrace THEN
          TWriteString('amatch continues p:');
          TWriteCard(p,0);
          TWriteString(',l:');
          TWriteCard(l,0);
          TWriteLn
       END;
       Dbg>*)
     END; (*while*)

     (*<Dbg
     IF DoTrace THEN
         TWriteString('amatch returns TRUE');
         TWriteLn
     END;
     Dbg>*)
     RETURN TRUE;
   END amatch;

   (* End of code adapted from "Matching Regular Expressions"
      in PC TechJournal May 1986 *)

BEGIN
   IF REData.InputType = ByTACTList THEN
      NewListItem(REData.InList,CurrentPos);
      CurrentDat := NIL;
      done := FALSE;
      IF GetListType(REData.InList) = TypeList THEN
         CheckEnd := GetInitPoint(REData.Pat,IniStr,IniLen,CurrentPos);
      ELSE
         CheckEnd := FALSE;
         done := NOT GetFirstItem(REData.InList,CurrentPos);
      END;
      IF NOT done THEN 
         GetItemData(REData.InList, CurrentPos, CurrentVA, CurrentDat)
      END;
  ELSE
      done := NOT ReceiveData(REData.InLink, CurrentVA);
      CurrentDat := VMAccess(CurrentVA);
   END;
   REData.NumbFound := 0;
   WHILE NOT done DO
      CASE CurrentDat^.DataType OF
        TypeType:
           Str.Copy(Word,CurrentDat^.TypeFileData.Word);
     | TokenType:
           IF CurrentDat^.HeadWord = NILVirt THEN
              IF NOT CurrentDat^.TokenDataLoaded THEN
                 VMMarkChanged(CurrentVA);
                 GetTDBTokenData(CurrentDat)
              END;
              tPos.Rec := CurrentDat^.TokenFileData.HRecNo + BeginType;
              tPos.Idx := ORD(CurrentDat^.TokenFileData.HRecPos);
              GetType(tPos,tHandle);
	      BitOps.UnPack( tHandle^^.PackedWord, Word (*SortTempStr*), WordBase.SortNoBitsPerChar ) ;
(*	      Str.Copy(Word,tHandle^^.Word); *)
              FreeTypeHandle(tHandle);
           ELSE
             HeadDat := VMAccess(CurrentDat^.HeadWord);
             Str.Copy(Word,HeadDat^.TypeFileData.Word);
             VMRelease(CurrentDat^.HeadWord);
           END;
     | RefNameType:
           Str.Copy(Word,RefsNameListPntr^[CurrentDat^.FilePos.Idx]^.Name);
     | RefStringType:
	   SPtr := VMAccess( CurrentDat^.SortStrVA ) ;
           Str.Copy( Word, SPtr^.String ) ;
           VMRelease( CurrentDat^.SortStrVA ) ;
      ELSE
         ProgramErrorAndHalt('CurrentDat type currently not supported')
      END;

      IF CheckEnd THEN done := NOT InitMatches(IniLen,Word,IniStr) END;
      IF NOT done THEN
         SortToFullWord(Word,Word2);
         IF amatch(Word2, 0, REData.Pat, 0) THEN
            CASE REData.OutputType OF
              ByDataLink:
               INC(REData.NumbFound);
               IF NOT SendData(REData.OutLink, CurrentVA) THEN RETURN END;
            | ByTACTList:
               IF InsertListItem(CurrentVA,REData.OutList) THEN
                  INC(REData.NumbFound)
               END;
            END;
         END;
         IF REData.InputType = ByTACTList THEN
            ReleaseItemHold(REData.InList, CurrentPos);
            IF GetNextItem(REData.InList, CurrentPos) THEN
               GetItemData(REData.InList, CurrentPos, CurrentVA, CurrentDat)
            ELSE done := TRUE END;
         ELSE
            VMRelease(CurrentVA);
            IF ReceiveData(REData.InLink, CurrentVA) THEN
               CurrentDat := VMAccess(CurrentVA)
            ELSE done := TRUE END;
         END;
      END;
      IF REData.AllowSearchIntrpt THEN
         done := done OR (SearchResult > SearchWarned);
      END;
   END;

   IF REData.InputType = ByTACTList THEN
      DisposeListItem(REData.InList,CurrentPos)
   END;
END PerformRegExp;

PROCEDURE DoRegExp(PInList:    TACTList;
               VAR POutList:   TACTList;
               VAR PNumbFound: CARDINAL;
                   Pat:       ARRAY OF CHAR);
VAR REData:   RegExpOpTypeRecord;
BEGIN
   Str.Copy(REData.Pat,Pat);
   WITH REData DO
      AllowSearchIntrpt := FALSE;
      InputType := ByTACTList;
      InList := PInList;
      OutputType := ByTACTList;
      OutList := POutList;
   END;
   PerformRegExp(REData);
   PNumbFound := REData.NumbFound;
END DoRegExp;

PROCEDURE RegExpProc(InData:   DataLinkArrayPntr; (* always 1 only *)
                     Numb:     CARDINAL;          (* always 1 only *)
                     POutData: DataLink;
                     Info:     ADDRESS);
VAR REData:   RegExpOpTypePntr;
BEGIN
   REData := RegExpOpTypePntr(Info);
   WITH REData^ DO
      AllowSearchIntrpt := TRUE;
      IF HandleInputAsList THEN
         GetTACTList(InData^[0], PoolNoForSearchWorkingSpace, InList);
         InputType := ByTACTList
      ELSE
         InputType := ByDataLink;
         InLink := InData^[0];
         OpenForReceiving(InLink, DontCare);
      END;
      OutputType := ByDataLink;
      OutLink := POutData;
      OpenForSending(OutLink, DontCare);
      PerformRegExp(REData^);
      WITH REData^ DO
         IF (NOT RuleWindowData.IgnoreErrs) AND
         (NumbFound = 0) AND FirstREMsg AND (SearchResult <= SearchWarned) THEN
            (*RES OLD MSG 166
            Your Regular Expression selected nothing.
            *)
            PutResWarning( (*RES REM INS*) 166 );
            SearchResult := SearchWarned;
            FirstREMsg := FALSE ;
         END;
      END;
      CloseForSending(OutLink);
      IF HandleInputAsList THEN DiscardList(InList);
      ELSE CloseForReceiving(InLink) END;
  END;
END RegExpProc;

PROCEDURE DisposeRegExpOpTypePntr(VAR Pntr: ADDRESS);
BEGIN
   DEALLOCATE(Pntr, SIZE(RegExpOpTypeRecord));
END DisposeRegExpOpTypePntr;

END RegularExpr .
 
