IMPLEMENTATION MODULE WWWBase;
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

IMPORT Str, Utils, FIO;
FROM GlobalDefs IMPORT StrAny, TACTWebVersion;
FROM StringIO IMPORT SWriteString, SWriteCard;
FROM HyperDataModel IMPORT HRecPntr, HLogDataType;
FROM TACTInit IMPORT GifDir, DefDisplay, DoBackingLink, TactPage,
     GetUnitName, GetUnitID, GetBefore, GetAfter;
FROM DBData IMPORT BeginType, TDBFileName, PDBOpen, PDBFileName, 
   NoTypes, NoTokensInDB, TDBTitle;
FROM DisplayDialog IMPORT InitializeData, DisplayData, DispOrg, DisplayType,
     DistDataType, DistType;
FROM PositionManagement IMPORT InitialDisplayItem;
FROM MainLists IMPORT
  (* const *) PoolNoForSelectLists, PoolNoForOldSelect, PoolNoForListFromRule,
          PoolNoForTempList,
  (* type *) PosListStatusType, DiscardMainListType,
  (* vars *) ListFromRule, ListFromRulePos, SelectedList, ListByPosition,
          PosListStatus, SelectedListPos, PositionListPos,
          SelectedListEmpty, ListByType, TypeListPos, ListByTypeMade;
FROM VariDisplay IMPORT OutputVariableDisplay;
FROM KWICDisplay IMPORT OutputKWICDisplay;
FROM DistDisplay IMPORT OutputDistDisplay;
FROM WordDisplay IMPORT OutputWordDisplay;
FROM MemTACTList IMPORT NewMemoryList, InsertListItem;
FROM Translations IMPORT XlateLine, File2Int, LenD, CurrentModeType, OutFile,
                         XWrStr,XWrLn, XClose, XStdOut, FILEText, XFileType,
                         OutFileName, XWrNXlate;
FROM RuleWindow IMPORT ProcessRule;
FROM WWWUtils IMPORT ParseData, pd, DestroyParseData,
               GetItem, FindItem, FindItem, FindItemCard, ParseQueryString,
               StartPre, EndPre, MakeQueryLink,RequestMethodType,
               MakeBasicQuery, CreateParseData, ParseDataDefined;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM RefValBase IMPORT
  (* Vars  *) LastRefPat, LastEncodedRefPat, LastRefPatLen,
  (* procs *) EncodeRefPat, GetLogDataForToken, GetLogDataIntStr;
FROM WordBase IMPORT
  (* Procs *) SortToIntWord, IntToSortWord;
FROM RefsBase IMPORT
   (* procs *) GetIDFromName, GetNameFromID;
FROM ListData IMPORT
  (* types *) DataItemPntr, ItemType,
              MarkAsUsed, MarkAsFreed, MakeTokenDataItem;
FROM LineBase IMPORT DisplayContextLines, HandleTokenType;
FROM ResText IMPORT OutputTextItem;
FROM VirtMem IMPORT VirtAddr, VMRelease;
FROM DBData  IMPORT TDBTitle;
FROM TypeBase IMPORT GetType, FreeTypeHandle, HTypeHandle;
FROM TACTDataServices IMPORT AllocTypeData;
FROM OccurListModule IMPORT InitializeOccurList;

CONST
   NextPageLinkType = 'Z';

PROCEDURE GetVarDisParms;
VAR i,al,ns:  CARDINAL;
    w:     ARRAY[0..40] OF CHAR;
    cm:    CurrentModeType;
    ed:    BOOLEAN; (* used as placeholder only *)
    npd:   ParseData;
BEGIN
    WITH DisplayData[Variable] DO
       ed := FindItemCard(pd, npd, 'dcontext_before',DispBefore);
       ed := FindItemCard(pd, npd, 'dcontext_after', DispAfter);
       IF FindItem(pd, npd, 'dcontext_unit', w) THEN
          cm.ModeIn := '0'; cm.ModeOut := '0';
          XlateLine(File2Int,'?',w,cm,al,LenD,ns,ed,UnitName);
          UnitID := GetIDFromName(UnitName);
          IF UnitID = MAX(INTEGER) THEN
             ProgramErrorAndHalt('Improper Display Context Unit');
          END;
       ELSE
          UnitID := 1;
          UnitName := 'LINES'
       END;
       IF FindItem(pd, npd, 'dorder', w) THEN
          IF Str.Compare(w,'NATURAL') = 0 THEN VariableDispOrg := DispNatural
          ELSIF Str.Compare(w,'WORD') = 0 THEN VariableDispOrg := DispType
          ELSIF Str.Compare(w,'POSITION') = 0 THEN VariableDispOrg := DispPosition
          ELSE ProgramErrorAndHalt('Improper Display Order') END;
       END;
   END;
END GetVarDisParms;

PROCEDURE GetKWICDisParms;
VAR i,al,ns:  CARDINAL;
    w:     ARRAY[0..40] OF CHAR;
    npd:   ParseData;
    dummy: BOOLEAN;
BEGIN
    WITH DisplayData[KWIC] DO
       IF FindItem(pd, npd, 'dorder', w) THEN
          IF Str.Compare(w,'NATURAL') = 0 THEN KWICDispOrg := DispNatural
          ELSIF Str.Compare(w,'WORD') = 0 THEN KWICDispOrg := DispType
          ELSIF Str.Compare(w,'POSITION') = 0 THEN KWICDispOrg := DispPosition
          ELSE ProgramErrorAndHalt('Improper Display Order') END;
       END;
(*     DisplayBar := FALSE; *)
       IF FindItem(pd, npd, 'dbar', w) THEN
          Utils.UpcaseStr(w,w);
          IF Str.Compare(w,'YES') = 0 THEN DisplayBar := TRUE
          ELSIF Str.Compare(w,'NO') = 0 THEN DisplayBar := FALSE
          ELSE ProgramErrorAndHalt('Improper dbar value') END;
       END;
       dummy :=FindItemCard(pd, npd, 'kwiclen', LineLength);
       dummy :=FindItemCard(pd, npd, 'kwiccentre', CitCentre);
   END;
END GetKWICDisParms;

PROCEDURE GetDistDisParms;
VAR i,al,ns:  CARDINAL;
    w:     ARRAY[0..40] OF CHAR;
    cm:    CurrentModeType;
    npd:   ParseData;
    dummy,ed: BOOLEAN;
BEGIN
    WITH DisplayData[Distribution] DO
       IF FindItem(pd, npd, 'disttype', w) THEN
          IF Str.Compare(w,'POSITION') = 0 THEN DistData.Type := DistByPos;
          ELSIF Str.Compare(w,'REFERENCE') = 0 THEN DistData.Type := DistByRef;
          ELSIF Str.Compare(w,'TYPE') = 0 THEN DistData.Type := DistByType;
          ELSIF Str.Compare(w,'NORMALIZED') = 0 THEN DistData.Type := NormalizedDist;
          ELSE ProgramErrorAndHalt('Improper disttype value') END;
       END;
       IF DistData.Type = DistByPos THEN
          dummy :=FindItemCard(pd, npd, 'distposstart', DistData.Start);
          dummy :=FindItemCard(pd, npd, 'distposend', DistData.End);
          dummy :=FindItemCard(pd, npd, 'distposby', DistData.ByValue);
       ELSIF (DistData.Type = DistByRef) OR (DistData.Type = NormalizedDist) THEN
          IF NOT FindItem(pd, npd, 'distref', w) THEN
             ProgramErrorAndHalt('Missing distref value');
          END;
          cm.ModeIn := '0'; cm.ModeOut := '0';
          XlateLine(File2Int,'?',w,cm,al,LenD,ns,ed,DistData.DistRefName);
          DistData.DistRefID := GetIDFromName(DistData.DistRefName);
          IF DistData.DistRefID = MAX(INTEGER) THEN
             ProgramErrorAndHalt('Improper Unit name in distref');
          END;
          IF FindItem(pd, npd, 'distreforder', w) THEN
             IF Str.Compare(w,'TEXT') = 0 THEN DistData.RefOrder := TRUE;
             ELSIF Str.Compare(w,'ALPHA') = 0 THEN DistData.RefOrder := FALSE;
             ELSE ProgramErrorAndHalt('Bad distreforder value') END;
          END;
       END;
    END;
END GetDistDisParms;

PROCEDURE GetNDistDisParms;
VAR i,al,ns:  CARDINAL;
    w:     ARRAY[0..40] OF CHAR;
    cm:    CurrentModeType;
    npd:   ParseData;
    dummy,ed: BOOLEAN;
BEGIN
    WITH DisplayData[Distribution] DO
       DistData.Type := NormalizedDist;
       IF NOT FindItem(pd, npd, 'distref', w) THEN
          ProgramErrorAndHalt('Missing distref value');
       END;
       cm.ModeIn := '0'; cm.ModeOut := '0';
       XlateLine(File2Int,'?',w,cm,al,LenD,ns,ed,DistData.DistRefName);
       DistData.DistRefID := GetIDFromName(DistData.DistRefName);
       IF DistData.DistRefID = MAX(INTEGER) THEN
          ProgramErrorAndHalt('Improper Unit name in distref');
       END;
    END;
END GetNDistDisParms;

PROCEDURE OutputData();
VAR
   StdOutFile:   XFileType;
   w:            StrAny;
   wptr:         POINTER TO StrAny;
   RealDir:      StrAny;
   URLDir:       StrAny;
   drive:        ARRAY[0..3] OF CHAR;
   path:         ARRAY[0..40] OF CHAR;
   name:         ARRAY[0..9] OF CHAR;
   ext:          ARRAY[0..4] OF CHAR;
   i:            CARDINAL;
   dummy:        BOOLEAN;
BEGIN
   XStdOut(FILEText, StdOutFile);
   RealDir := 'C:\HTTPD\HTDOCS\TACTWEB\GIFS';
   URLDir := '/tactweb/gifs';
(* Utils.GetEnv('GIF_DIR', w); *)
   Str.Copy(w, GifDir);
   IF w[0] <> 0C THEN
      i := Str.Pos(w,',');
      w[i] := 0C;
      Str.Copy(RealDir, w);
      wptr := ADR(w[i+1]);
      Str.Copy(URLDir, w);
   END;
   dummy := Utils.ParseFilename(OutFileName, drive,path,name,ext);
   Utils.MakeFilename(0C,RealDir, name, 'GIF', w);
   i := XWrStr(StdOutFile, w, i);
   XWrLn(StdOutFile, i);
   Utils.MakeFilename(0C,URLDir, name, 'gif', w);
   i := Str.Pos(w,'\');
   w[i] := '/';
   XWrNXlate(OutFile, '<IMG SRC="', i);
   i := XWrStr(OutFile, w, i);
   XWrNXlate(OutFile, '">', i);
   XWrLn(OutFile, i);

   DisplayData[KWIC].ShowText := FALSE;
   DisplayData[KWIC].KWICDispOrg := DispPosition;
   OutputKWICDisplay(StdOutFile, FALSE);
   XClose(StdOutFile);
END OutputData;

PROCEDURE HandleOutput;
VAR
   npd:  ParseData;
   dtype: ARRAY[0..10] OF CHAR;
BEGIN
   IF NOT FindItem(pd, npd, 'display_type', dtype) THEN
(*    Utils.GetEnv('DISPLAY_TYPE', dtype); *)
      Str.Copy(dtype, DefDisplay);
      IF dtype[0] = 0C THEN dtype := 'KWIC' END;
   END;
   IF Str.Compare(dtype, 'DATA') = 0 THEN
      OutputData();
   ELSIF Str.Compare(dtype, 'KWIC') = 0 THEN 
      GetKWICDisParms;
      OutputKWICDisplay(OutFile, TRUE);
   ELSIF Str.Compare(dtype, 'WORD') = 0 THEN
      OutputWordDisplay(OutFile);
   ELSIF Str.Compare(dtype, 'VAR') = 0 THEN
      GetVarDisParms;
      OutputVariableDisplay(OutFile);
   ELSIF Str.Compare(dtype, 'DIST') = 0 THEN
      GetDistDisParms;
      OutputDistDisplay(OutFile);
   ELSIF Str.Compare(dtype, 'NDIST') = 0 THEN
      GetNDistDisParms;
      OutputDistDisplay(OutFile);
   ELSE ProgramErrorAndHalt('Bad display_type') END;
END HandleOutput;

PROCEDURE LoadRefIfGiven;
VAR
    npd:  ParseData;
    rft:  ARRAY[0..200] OF CHAR;
    al,ns:  CARDINAL;
    cm:    CurrentModeType;
    ed:    BOOLEAN;
BEGIN
   IF NOT FindItem(pd, npd, 'ref_template', rft) THEN RETURN END;
   Utils.TrimBlanks(rft, rft);
   IF rft[0] = 0C THEN RETURN END;

   cm.ModeIn := '0'; cm.ModeOut := '0';
   XlateLine(File2Int,'?',rft,cm,al,LenD,ns,ed,LastRefPat);
   IF NOT EncodeRefPat(LastRefPat, LastEncodedRefPat, LastRefPatLen) THEN
      ProgramErrorAndHalt('Error encoding ref in GetRefString');
   END;

END LoadRefIfGiven;

PROCEDURE SetUpListsEtc();
BEGIN
   ListByPosition := NewMemoryList(PoolNoForSelectLists);
   PosListStatus := NoPos;
   ListByType := NewMemoryList(PoolNoForSelectLists);
   ListByTypeMade := FALSE;
   InitialDisplayItem(SelectedListPos);
   InitialDisplayItem(PositionListPos);
   InitialDisplayItem(TypeListPos);
   SelectedListEmpty := TRUE;
END SetUpListsEtc;

PROCEDURE DisplayCredits();
BEGIN
(*RES UPD HLP 2
<p>The text search engine you are using is TACTweb.
TACTweb is beta-level software developed as a part of a project
by John Bradley and Geoffrey Rockwell</p>
<ul>
<li>Project Management by John Bradley and Geoffrey Rockwell.
<li>TACTweb software by John Bradley.
<li>Instructional Design by Geoffrey Rockwell and John Bradley.
<li>Documentation by John Bradley and Geoffrey Rockwell.
</ul>
<p>Parts of TACTweb reuse code originally in TACT version 2.0.  Thanks
are given to the other copyright holders: Lidio Presutti, and
the University of Toronto.
<p>For more information about TACTweb click
<a href="http://tactweb.humanities.mcmaster.ca">here.</a>
</body>
</html>
*)
      OutputTextItem( (*RES REM INS*) 2 );
END DisplayCredits;

(* ============================================================== *)

PROCEDURE OutputLine(l: ARRAY OF CHAR);
VAR   IOresult:   CARDINAL;
BEGIN
   XWrNXlate(OutFile,l, IOresult);
   XWrLn(OutFile, IOresult);
END OutputLine;

PROCEDURE DefaultFirstPart();
VAR
   IOresult,dmy:   CARDINAL;
BEGIN
   OutputLine('<HTML>');
   OutputLine('<HEAD>');
   XWrNXlate(OutFile,'<title>TACTweb (', IOresult);
   XWrNXlate(OutFile, TACTWebVersion, IOresult);
   XWrNXlate(OutFile,') Results</title>', IOresult);
   XWrLn(OutFile, IOresult);
   OutputLine('</HEAD>');
   OutputLine('<BODY>');

   XWrNXlate(OutFile,'<h3>TACTweb (', IOresult);
   XWrNXlate(OutFile, TACTWebVersion, IOresult);
   XWrNXlate(OutFile,') Results</h3>', IOresult);
   XWrLn(OutFile, IOresult);
END DefaultFirstPart;

VAR
  tfl:  FIO.File;

PROCEDURE ProcessTemplateFirstPart(VAR TemplateFileName: ARRAY OF CHAR);
VAR
   s:   StrAny;
   i:   CARDINAL;
BEGIN
   tfl := FIO.OpenRead(TemplateFileName);
   IF FIO.IOresult() <> 0 THEN
      TemplateFileName[0] := 0C;
      DefaultFirstPart();
      RETURN;
   END;
   LOOP
      FIO.RdStr(tfl, s);
      IF FIO.EOF OR (FIO.IOresult() <> 0) THEN
         FIO.Close(tfl);
         TemplateFileName[0] := 0C;
         RETURN;
      END;
      IF 0 = Str.Compare(s, '$$$$') THEN RETURN END;
      XWrNXlate(OutFile,s, i);
      XWrLn(OutFile, i);
   END;
END ProcessTemplateFirstPart;

PROCEDURE BeginStandardOutput(TemplateFileName: ARRAY OF CHAR);
VAR
   IOresult:   CARDINAL;
   dmy:        CARDINAL;
BEGIN
   IF TemplateFileName[0] = 0C THEN DefaultFirstPart();
   ELSE ProcessTemplateFirstPart(TemplateFileName); END;

   XWrNXlate(OutFile,'<hr><p>Database Title: ', IOresult);
   dmy :=XWrStr(OutFile, TDBTitle, IOresult);
   XWrLn(OutFile, IOresult);
END BeginStandardOutput;

PROCEDURE ProcessTemplateSecondPart();
VAR
   s:   StrAny;
   i:   CARDINAL;
BEGIN
   LOOP
      FIO.RdStr(tfl, s);
      IF FIO.EOF OR (FIO.IOresult() <> 0) THEN
         FIO.Close(tfl);
         RETURN;
      END;
      XWrNXlate(OutFile,s, i);
      XWrLn(OutFile, i);
   END;
END ProcessTemplateSecondPart;

PROCEDURE HandleGETQuery(VAR TemplateFileName: ARRAY OF CHAR);
VAR
   QueryData:  ARRAY[0..255] OF CHAR;
   type:       CHAR;
   hrec:       HRecPntr;
   VA:         VirtAddr;
   A:          DataItemPntr;
   dummy:      BOOLEAN;
(* UnitName:   ARRAY[0..40] OF CHAR;
   UnitID:     INTEGER; *)
   Before,After: CARDINAL;
   w:          StrAny;
   d2:         CARDINAL;
   StartTPntr,
   EndTPntr:   HRecPntr;

PROCEDURE MakeIDValue(VA: VirtAddr (*to TokenDataItem *);
                  VAR s:  ARRAY OF CHAR);
VAR
   LogData:   HLogDataType;
   w:         StrAny;
   l,l1:      CARDINAL;
   nw:        LONGCARD;
BEGIN
   GetLogDataForToken(VA, GetUnitID, LogData);
   l := 0;
   SWriteString(s,l,GetUnitName,0);
   SWriteString(s,l,' ', 0);
   IF GetUnitID < 0 THEN
      GetLogDataIntStr(LogData, w, l1, nw);
      SWriteString(s,l,w,0);
   ELSE
      SWriteCard(s,l,LogData.Count, 0);
   END;
END MakeIDValue;

PROCEDURE MakeButton(s: ARRAY OF CHAR;T: HRecPntr);
VAR
   d2:    CARDINAL;
   s1,s2: StrAny;
BEGIN
   MakeTokenDataItem(VA, PoolNoForSelectLists, A);
   A^.FilePos := T;
   VMRelease(VA);
   d2 := XWrStr(OutFile,'[',d2);
   d2 := 0;
   SWriteString(s2,d2,s,0);
   MakeIDValue(VA,s1);
   SWriteString(s2,d2,s1,0);
   MakeQueryLink(T,NextPageLinkType,s2,s1);
   d2 := XWrStr(OutFile,s1,d2);
   d2 := XWrStr(OutFile,']',d2);
   XWrLn(OutFile,d2);
END MakeButton;

PROCEDURE WriteWordList();
VAR
   h:       HTypeHandle;
   tVA:     VirtAddr;
   tp:      DataItemPntr;
BEGIN
   ParseQueryString(QueryData, hrec, type);
   SetUpListsEtc();

   GetType(hrec, h);
   AllocTypeData(h,hrec,PoolNoForSelectLists,tVA, tp);
   FreeTypeHandle(h);
   VMRelease(tVA);
   SelectedList := InitializeOccurList(tVA);
   SelectedListEmpty := FALSE;
   OutputKWICDisplay(OutFile, TRUE);
END WriteWordList;

PROCEDURE WritePage();
BEGIN
   IF (NOT DoBackingLink) THEN
      ProgramErrorAndHalt('A Backing Display it not permitted.');
   END;
   ParseQueryString(QueryData, hrec, type);
   SetUpListsEtc();

   MakeTokenDataItem(VA, PoolNoForSelectLists, A);
   A^.FilePos := hrec;
   VMRelease(VA);

   MakeIDValue(VA, w);
   XWrNXlate(OutFile,'<P>',d2);
   d2 := XWrStr(OutFile,w,d2); XWrLn(OutFile,d2);
   XWrNXlate(OutFile,'<HR>',d2);

   OutputTextItem( StartPre );
   IF type = 'P' THEN
      DisplayContextLines(VA, GetUnitID, GetBefore, GetAfter, 
      DisplayEnd, StartTPntr, EndTPntr);
   ELSE
      DisplayContextLines(VA, GetUnitID, GetBefore, GetAfter, 
      NoDisplay, StartTPntr, EndTPntr);
   END;
   OutputTextItem( EndPre );
   IF GetUnitID <> 1 THEN
      XWrNXlate(OutFile,'<HR><P>',d2);
      IF (StartTPntr.Rec <> 0) AND (StartTPntr.Idx <> 0) THEN
         MakeButton('Previous ',StartTPntr);
      END;
      IF (EndTPntr.Rec <> 0) AND (EndTPntr.Idx <> 0) THEN
         MakeButton('Next ',EndTPntr);
      END;
   END;
END WritePage;

PROCEDURE DoQueryQuery();

PROCEDURE BuildParseData();
VAR
   i:     CARDINAL;
   str:   ARRAY[0..255] OF CHAR;
   pstr:  POINTER TO ARRAY[0..255] OF CHAR;
BEGIN
   pstr := ADR(QueryData[1]);
   i := 0;
   WHILE (pstr^[i] <> 0C) AND (pstr^[i] <> '&')DO INC(i); END;
   IF (pstr^[i] <> 0C) THEN
      WHILE (pstr^[i] <> 0C) DO
         IF pstr^[i] = ':' THEN pstr^[i] := '='; END;
         INC(i);
      END;
   END;
   Str.Concat(str, 'query=', pstr^);
   CreateParseData(pd, str);
END BuildParseData;

BEGIN
   BuildParseData();
   LoadRefIfGiven;
   InitializeData;
   SetUpListsEtc();

   IF ProcessRule(pd) THEN HandleOutput END;
END DoQueryQuery;

BEGIN
   Utils.GetEnv( 'QUERY_STRING', QueryData);
   IF QueryData[0] = 'C' THEN
      DefaultFirstPart();
      DisplayCredits();
      HALT;
   END;

   BeginStandardOutput(TemplateFileName);
   CASE QueryData[0] OF
     'W': WriteWordList();
   | 'Q': DoQueryQuery();
   | 'P': WritePage();
   | NextPageLinkType: WritePage();
   ELSE
      ProgramErrorAndHalt('Invalid QueryString')
   END;
END HandleGETQuery;

PROCEDURE FinishOutputText();
VAR
   txt:   ARRAY[0..100] OF CHAR;
   i,j:   CARDINAL;
BEGIN
   XWrNXlate(OutFile, '<HR><P>', i);
   MakeBasicQuery('C','','[About TACTweb]',txt);
   j := XWrStr(OutFile, txt, i);
   j := XWrStr(OutFile, ' (Ver. ', i);
   j := XWrStr(OutFile, TACTWebVersion, i);
   j := XWrStr(OutFile, ')', i);
   XWrLn(OutFile, i);
END FinishOutputText;

PROCEDURE ProcessTactPage(t: ARRAY OF CHAR);
VAR
   ptr:    POINTER TO StrAny;
   i:      CARDINAL;
   j:      INTEGER;
   OK:     BOOLEAN;
BEGIN
   IF t[0] = 0C THEN RETURN END;
   IF (t[0] = '-') AND (t[1] = 0C) THEN
      DoBackingLink := FALSE;
      RETURN;
   END;
   i := Str.Pos(t,'/');
   IF i <> MAX(CARDINAL) THEN
     ptr := ADR(t[i+1]);
     t[i] := 0C;
   ELSE ptr := ADR(t[0]) END;
   GetUnitID := GetIDFromName(t);
   IF GetUnitID = MAX(INTEGER) THEN ProgramErrorAndHalt('Bad name given in TACTPAGE') END;
   IF GetUnitID = 0 THEN ProgramErrorAndHalt('TACTPAGE set to "words"') END;
   IF (GetUnitID = 1) AND (i<>MAX(CARDINAL)) THEN
      i := CARDINAL(Str.StrToCard(ptr^,10,OK));
      IF (NOT OK) OR (i < 3) THEN
         ProgramErrorAndHalt('Inproper # for lines in TACTPAGE');
      END;
      DEC(i);
      GetBefore := i DIV 2;
      GetAfter := i - GetBefore;
      ptr := ADR(t[0]);
   ELSIF (GetUnitID <> 1) THEN
      GetBefore := 0;
      GetAfter := 0;
   END;
   Str.Copy(GetUnitName, ptr^);
END ProcessTactPage;

PROCEDURE DoWWWWork(TemplateFileName: ARRAY OF CHAR);
VAR
   IOresult,dmy:   CARDINAL;
BEGIN
   ProcessTactPage(TactPage);
   IF ParseDataDefined(pd) THEN
      BeginStandardOutput(TemplateFileName);
(*    InitialParseData(pd); *)
      LoadRefIfGiven;
      InitializeData;
      SetUpListsEtc();

      IF ProcessRule(pd) THEN HandleOutput END;
   ELSE
      InitializeData;
      HandleGETQuery(TemplateFileName);
   END;
   FinishOutputText();
   IF TemplateFileName[0] = 0C THEN
      OutputLine('</BODY>');
      OutputLine('</HTML>');
   ELSE ProcessTemplateSecondPart(); END;
END DoWWWWork;
END WWWBase.
