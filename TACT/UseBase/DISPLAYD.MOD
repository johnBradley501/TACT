IMPLEMENTATION MODULE DisplayDialog (* Window *) ;

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
Ver 1.11

 - Sept. 1, 1989  L.Presutti
   Added "Word Only" to modify panel of KWIC.
Ver 1.2
 - Jan. 8, 1990  L.Presutti
   Added Collocate Generator Display code.
*)

FROM SYSTEM IMPORT ADDRESS,ADR;
IMPORT TWB, Str, Lib ;
IMPORT ASCII;
FROM GlobalDefs IMPORT StrAny;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo, WindowInfoPtr,
  (* procs *) PushNewWindow, PopWindow, RollWindows, DummyInit,
              GetCurrentPointer, MakeHighestPriority;
FROM Utils IMPORT Beep,TrimBlanks;
FROM WordBase IMPORT
  (* Procs *) SortToIntWord;
FROM Windows IMPORT
  (* Const  *) RegularAttr;
FROM ErrorBase IMPORT
  (* procs  *) ProgramErrorAndHalt;
FROM TACTInit IMPORT
 (* const *) NumberInExitList,
 (* vars  *) TermList,ExitList;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CharField, CardField, CharFieldProc, CardFieldProc,
                 Switches, SwitchValue, SkipField, ClearMenuArea,
                 MakeMenu, DestroyMenu, ShowFixedText, ShowMenu, DoMenu;
FROM ResMessages IMPORT
  (* proc *) MsgString, MsgCard, PutResError, PutResWarning, PutResMessage,
            ResAskUser;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames,
   (* procs *) LookupRefName, GetNameFromID;
FROM TACTDataServices IMPORT
   (* const *) NotRefNameRes,
   (* procs *) GeneralUnitNameVerify;
FROM channels IMPORT
  (* type *) channel,
  (* proc *) open, attachsender, attachreceiver, send, receive,
             datawaiting;
FROM ScrollMessages IMPORT
   (* const*) SizeOfLineInfoHeader,
   (* type *) ScrollInstruction, ReturnInstruction, LineInformation,
              LineInfoPntr, ScrollInstructionPacket, ScrollKey;
FROM KeyStandards IMPORT
  (* const *) FieldMotionExtSize,
  (* types *) PanelControlKeys,
  (* vars  *) FieldMotionExt, FieldMotionASC,
  (* procs *) GetPanelControlKey;

FROM HelpBase IMPORT
  (* procs *) PushHelpItem, ReplaceHelpItem, PopHelpItem;

FROM PrintModule IMPORT PrintProcType;

FROM TextDisplay IMPORT
  (* proc *) HandleTextDisplay, OutputTextDisplay, InitializeTextDisplay;
FROM VariDisplay IMPORT
  (* proc *) HandleVariableDisplay, OutputVariableDisplay, InitializeVariableDisplay;
FROM KWICDisplay IMPORT
  (* proc *) HandleKWICDisplay, OutputKWICDisplay, InitializeKWICDisplay;
FROM DistDisplay IMPORT
  (* proc *) HandleDistDisplay, OutputDistDisplay, InitializeDistDisplay;
FROM ColDisplay IMPORT
  (* proc *) HandleCollocateDisplay, OutputCollocateDisplay, InitializeCollocateDisplay;
FROM RefValBase IMPORT
  (* Vars  *) LastRefPat, LastEncodedRefPat, LastRefPatLen,
  (* procs *) EncodeRefPat;
FROM MagicChars IMPORT
  (* Vars/Const *) RefDelimID ;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray,GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* type *) ResCollectionType,
   (* proc *) ReleaseCollection;

CONST

(*RES OLD MNU 20
Variable Context Display Options:

  Refs.: %0_________________________________________________________

       Display Context:  Unit: %3________________
                         Before: %1______  After: %2_______

      For a list of reference names for "Unit", type "?" in
                          the Unit field.

      Order:  Selected Word-list: %|4Position: %|5Word: %|6

      Wordnumber Tag?  String:%|7 Counter: %|8
*)
    VariableOptionsMenuID = (*RES REM INS*) 20 ;

(*RES OLD MNU 24
KWIC Display Options:

  Refs.: %0_________________________________________________________

    Order?  Selected Word-list:%|1 Position:%|2 Word:%|3 Word Only:%|4
    Show Text?  Yes: %|5 No: %|6

    Display "|"?   Yes: %|7 No: %|8
    Indicate headword using:   "Highlight": %|9 ">": %|10

    Wordnumber Tag?  String:%|11 Counter: %|12
*)
    KWICOptionsMenuID = (*RES REM INS*) 24 ;

(*RES OLD MNU 21
Display Options:

  Refs.: %0_________________________________________________________

  Wordnumber Tag?  String:%|1 Counter: %|2

*)
    OtherOptionsMenuID = (*RES REM INS*) 21 ;
(*RES OLD MNU 65
Display Options:

  Refs.: %0_________________________________________________________



*)
    DistByTypeMenuID = (*RES REM INS*) 65 ;

(*RES OLD MNU 18
Distribution Display Options:    Block Char.:   %|3
     Type:  Text Position: %|0    Reference: %|1    Word:  %|2
     Wordnumber Tag?  String:%|4  Counter: %|5
___________________________________________________________________





*)

    DistHeaderMenuID = (*RES REM INS*) 18 ;
    HeaderSize = 5; (* # of lines in header - m.s. - was 4, mar 95 *)

(*RES OLD MNU 19
  Refs.:  %0_________________________________________________________

  Start: %1_%  End: %2_%  By:  %3_%
*)

   DistByPosMenuID = (*RES REM INS*) 19 ;

(*RES OLD MNU 22
  Refs.: %0_________________________________________________________

  Selection Ref. ID : %1____________________________________________

  Order Ref. IDs by:     Text Position: %|2      Alphabetical: %|3
*)

   DistByRefMenuID = (*RES REM INS*) 22 ;

(*RES OLD MNU 34
Collocates Generator Display Options:

  Refs.: %0_________________________________________________________

  Collocates Display Context:  Unit: %3________________
                             Before: %1______  After: %2_______

  Count Overlaps?   Yes: %|4 No: %|5
  Show Intermediate Results?   Yes: %|6 No: %|7

  Wordnumber Tag?  String:%|8  Counter: %|9

  For list of Reference Names for Unit, type "?" in the Unit Field.
*)
    ColGenOptionsMenuID = (*RES REM INS*) 34 ;

VAR
   td:                    DisplayDataType;
   LastPosDist:           DistDataType;
   LastRefDist:           DistDataType;
   LastTypeDist:          DistDataType;
   DisplayProc:           ARRAY[Variable..Distribution] OF PROCEDURE(ScrollKey);
   ModificationMenus:     ARRAY[Variable..Distribution] OF MenuID;
   ModMenuLength:         ARRAY[Variable..Distribution] OF CARDINAL;
   ScreenLabel:           ARRAY[Variable..Distribution] OF ARRAY[0..25] OF CHAR;
   DisplayHelp:           ARRAY[Variable..Distribution] OF CARDINAL;
   OptionsHelp:           ARRAY[Variable..Distribution] OF CARDINAL;
   DistHeaderMenu:        MenuID;
   DistByPosMenu:         MenuID;
   DistByRefMenu:         MenuID;
   DistByTypeMenu:        MenuID;
   NumbDisplayScreens:    CARDINAL;
   j:                     DisplayType;
   DisplayWindInfo:       WindowInfo;
   Dummy:		  BOOLEAN ;
   LocalFunctTerm:        ARRAY[0..NumberInExitList+FieldMotionExtSize-1]
                          OF CHAR;
   LocalTermsNotMade:     BOOLEAN ;
   OptionLabel:           ARRAY[0..25] OF CHAR;

PROCEDURE VerifyUnitName(Data:      ADDRESS;
                     VAR ReDisplay: BOOLEAN;
                     VAR ReEdit:    BOOLEAN);
TYPE DDPT = POINTER TO DisplayDataType;

VAR DDP:DDPT;

BEGIN
   DDP := DDPT(Data);
   WITH DDP^ DO
      GeneralUnitNameVerify(UnitName,UnitID,ReDisplay,ReEdit);
   END;
END VerifyUnitName;

PROCEDURE VerifyColUnitName(Data:      ADDRESS;
                     VAR ReDisplay: BOOLEAN;
                     VAR ReEdit:    BOOLEAN);
   TYPE
	DDPT = POINTER TO DisplayDataType;
   VAR
	DDP : DDPT;
   BEGIN
	DDP := DDPT(Data);
	WITH DDP^.ColData DO
	   GeneralUnitNameVerify( ColUnitName, ColUnitID, ReDisplay, ReEdit);
	END;
   END VerifyColUnitName;

PROCEDURE VerifyDistUnitName(Data:      ADDRESS;
                         VAR ReDisplay: BOOLEAN;
                         VAR ReEdit:    BOOLEAN);
TYPE DDPT = POINTER TO DisplayDataType;
VAR DDP:DDPT;
BEGIN
   DDP := DDPT(Data);
   WITH DDP^.DistData DO
      GeneralUnitNameVerify(DistRefName,DistRefID,ReDisplay,ReEdit);
   END;
END VerifyDistUnitName;

PROCEDURE VerifyStart(Data:     ADDRESS;
                  VAR ReDisplay: BOOLEAN;
                  VAR ReEdit:    BOOLEAN);

TYPE DDPT = POINTER TO DisplayDataType;

VAR DDP:DDPT;

BEGIN
   DDP := DDPT(Data);
   ReDisplay := FALSE;
   ReEdit := FALSE;
   WITH DDP^.DistData DO
      IF Start > 100 THEN
          (*RES OLD MSG 181
          The "Start" value is given in terms of a percentage of the text.
          Please give a value between 0 and 99.
          *)
          PutResError( (*RES REM INS*) 181 );
          ReDisplay := TRUE;
          ReEdit := TRUE;
      END;
   END;
END VerifyStart;

PROCEDURE VerifyEnd(Data:     ADDRESS;
                VAR ReDisplay: BOOLEAN;
                VAR ReEdit:    BOOLEAN);

TYPE DDPT = POINTER TO DisplayDataType;

VAR DDP:DDPT;

BEGIN
   DDP := DDPT(Data);
   ReDisplay := FALSE;
   ReEdit := FALSE;
   WITH DDP^.DistData DO
      IF End > 100 THEN
          (*RES OLD MSG 182
          The "End" value is given in terms of a percentage of the text.  Please
          give a value between 0 and 99.
          *)
          PutResError( (*RES REM INS*) 182 );
          ReDisplay := TRUE;
          ReEdit := TRUE;
      END;
   END;
END VerifyEnd;

PROCEDURE VerifyByValue(Data:     ADDRESS;
                    VAR ReDisplay: BOOLEAN;
                    VAR ReEdit:    BOOLEAN);

TYPE DDPT = POINTER TO DisplayDataType;

VAR DDP:DDPT;

BEGIN
   DDP := DDPT(Data);
   ReDisplay := FALSE;
   ReEdit := FALSE;
   WITH DDP^.DistData DO
      IF (ByValue > 100) OR (ByValue < 1) THEN
          (*RES OLD MSG 183
          The "ByValue" is given in terms of a percentage of the text.  Please
          give a value between 1 and 99.
          *)
          PutResError( (*RES REM INS*) 183 );
          ReDisplay := TRUE;
          ReEdit := TRUE;
      ELSIF ByValue > 50 THEN
          (*RES OLD MSG 184
          A "ByValue" of %0 will yield a Histogram with only 1 column.
          Usually values of 20 percent or less are given.
          *)
          MsgCard( ByValue, 0 ) ;
          PutResWarning( (*RES REM INS*) 184 );
      END;
   END;
END VerifyByValue;

PROCEDURE InitializeNewDisplay(VAR Type: DisplayType);
BEGIN
      DisplayProc[Type](InitKey);
END InitializeNewDisplay;

PROCEDURE InitCurrentWindow;
BEGIN
      DisplayProc[CurrentDisplay](InitKey);
END InitCurrentWindow;

PROCEDURE CopyLastRef(VAR Data: DisplayDataType);
BEGIN
   IF LastRefPatLen = 0 THEN
      ProgramErrorAndHalt('Cannot copy yet -- none defined')
   END;

   WITH Data DO
      Str.Copy(RefInfo, LastRefPat);
      EncodedRefLen := LastRefPatLen;
      Lib.Move( ADR(LastEncodedRefPat), ADR(EncodedRefInfo), EncodedRefLen+1);
   END;
END CopyLastRef;

PROCEDURE CreateNewWindow(DType:     DisplayType);
BEGIN
   ReplaceHelpItem(DisplayHelp[DType]);
   IF DisplayData[DType].OnScreen THEN
      MakeHighestPriority(ADR(DisplayData[DType].WindInfo));
      CurrentDisplay := DType;
      InitCurrentWindow;
      RETURN
   END;
   WITH DisplayData[DType] DO
      IF NOT WindInfoSet THEN
         WindInfoSet := TRUE;
         WITH WindInfo DO
           XPos :=   1;
           YPos :=   2;
           XSize := 78;
           YSize := 22;
           MxYSize := 25;
           Type := Active;
           AllowMove := TRUE;
           AllowResize := TRUE;
         END;
         CopyLastRef(DisplayData[DType]);
      END;
      PushNewWindow(WindInfo,WindID, InitCurrentWindow);
      TWB.SetTitle(WindID, ScreenLabel[DType], TWB.RightLowerTitle);
      OnScreen := TRUE;
   END;
   CurrentDisplay := DType;
   InitializeNewDisplay(DType);
   INC(NumbDisplayScreens);
END CreateNewWindow;

PROCEDURE ChangeCurrentWindow(DType:  DisplayType);
BEGIN
   ReplaceHelpItem(DisplayHelp[DType]);
   IF CurrentDisplay = None THEN
      CreateNewWindow(DType);
      RETURN
   END;
   IF DType = CurrentDisplay THEN
      InitCurrentWindow;
      RETURN
   END;
   IF DisplayData[DType].OnScreen THEN
      MakeHighestPriority(ADR(DisplayData[DType].WindInfo));
      CurrentDisplay := DType;
   ELSE
      SendInstructionToCurrent( TermKey ) ;
      WITH DisplayData[DType] DO
         WindID := DisplayData[CurrentDisplay].WindID;
         WindInfo := DisplayData[CurrentDisplay].WindInfo;
         OnScreen := TRUE;
         WindInfoSet := TRUE;
         PopWindow;
         PushNewWindow(WindInfo,WindID,InitCurrentWindow);
         TWB.SetTitle(WindID, ScreenLabel[DType], TWB.RightLowerTitle);
      END;
      DisplayData[CurrentDisplay].OnScreen := FALSE;
      CurrentDisplay := DType;
      InitializeNewDisplay(DType);
   END;
END ChangeCurrentWindow;

PROCEDURE CloseCurrentWindow;
VAR
   j:               DisplayType;
   done:            BOOLEAN;
   CurWind:         WindowInfoPtr;
BEGIN
   IF CurrentDisplay = None THEN
	(*RES OLD MSG 197
	You have no current Display to Close.
	*)
	PutResError( (*RES REM INS *) 197 ) ;
	RETURN ;
   END ;
(* SendInstructionToCurrent( TermKey ) ; *)
   SendInstructionToCurrent( CloseDownKey ) ;
   PopWindow;
   DisplayData[CurrentDisplay].OnScreen := FALSE;
   DEC(NumbDisplayScreens);
   IF NumbDisplayScreens = 0 THEN
      ReplaceHelpItem(0); (* Basic Help *)
      CurrentDisplay := None;
      RETURN
   END;
   GetCurrentPointer(CurWind);
   j := None;
   done := FALSE;
   REPEAT
      INC(j);
      done := DisplayData[j].OnScreen AND DisplayData[j].WindInfo.IsTop;
   UNTIL (j = Distribution) OR done;
   IF NOT done THEN j := None END;
   CurrentDisplay := j;
   ReplaceHelpItem(DisplayHelp[CurrentDisplay]);
   InitCurrentWindow;
END CloseCurrentWindow;

PROCEDURE ProcessRef(Data:     ADDRESS;
                 VAR ReDisplay: BOOLEAN;
                 VAR ReEdit:    BOOLEAN);

TYPE DDPT = POINTER TO DisplayDataType;

VAR DDP:DDPT;

BEGIN
   DDP := DDPT(Data);
   WITH DDP^ DO
      TrimBlanks(RefInfo, RefInfo);
      IF RefInfo[0] = 0C THEN
          IF LastRefPatLen = 0 THEN
             Beep;
             ReDisplay := TRUE;
             ReEdit := TRUE;
          ELSE
             CopyLastRef(DDP^);
             ReDisplay := TRUE;
             ReEdit := FALSE;
          END;
      ELSE
         ReEdit := NOT EncodeRefPat( RefInfo, EncodedRefInfo, EncodedRefLen);
         ReDisplay := ReEdit;
      END;
   END;
END ProcessRef;

PROCEDURE ModifyCurrentWindow(VAR TC:       CHAR;
                              VAR FunctKey: BOOLEAN;
                              VAR DoRead:   BOOLEAN);
VAR
   w:      TWB.WinType;
   in:     CARDINAL;
   KeyType:PanelControlKeys;
   tStr:   ARRAY[0..50] OF CHAR;

PROCEDURE DoDistributionDisplay;
VAR  hd:         DistType;
     ItemNumb:   CARDINAL;
     temp:       MenuID;
     DetailDone: BOOLEAN;

PROCEDURE ShowDetailMenu;
BEGIN
   CASE td.DistData.Type OF
     DistByPos:   temp := DistByPosMenu
   | DistByType:  temp := DistByTypeMenu
     ELSE         temp := DistByRefMenu
   END;
   ClearMenuArea(w,0,HeaderSize,temp);
   ShowFixedText(w,temp,0,HeaderSize);
   ShowMenu(w,temp,0,HeaderSize,td);

END ShowDetailMenu;

PROCEDURE VerifyValues(): BOOLEAN;
VAR DtPntr:   ADDRESS;
    ReD,ReE:  BOOLEAN;
    OK:       BOOLEAN;
BEGIN
   OK := TRUE;
   DtPntr := ADR(td);
   CASE td.DistData.Type OF
   DistByPos:
      ItemNumb := 1;
      VerifyStart(DtPntr,ReD,ReE);
      OK := NOT ReE;
      IF OK THEN
         ItemNumb := 2;
         VerifyEnd(DtPntr,ReD,ReE);
         OK := NOT ReE;
      END;
      IF OK THEN
         ItemNumb := 3;
         VerifyByValue(DtPntr,ReD,ReE);
      END;
      IF OK THEN
         WITH td.DistData DO
            IF Start > End THEN
               (*RES OLD MSG 185
               The "Start" value must be less than the "End" value.
               *)
               PutResError( (*RES REM INS*) 185 );
               ItemNumb := 1;
               OK := FALSE;
            ELSIF ByValue > End - Start THEN
               (*RES OLD MSG 186
               The "By" value must be smaller than the range from "Start"
               and "End".
               *)
               PutResError( (*RES REM INS*) 186 );
               ItemNumb := 3;
               OK := FALSE;
            ELSE OK := TRUE;
            END;
         END; (* IF Start > End THEN ... ELSE ... *)
      END;
   | DistByType:
   ELSE
      ItemNumb := 1;
      VerifyDistUnitName(DtPntr,ReD,ReE);
      OK := NOT ReE;
   END;  (* CASE td.DistData.Type OF *)
   IF OK THEN
      WITH td.DistData DO
         CASE Type OF
           DistByPos:  LastPosDist := td.DistData
         | DistByRef:  LastRefDist := td.DistData ;

         | DistByType: LastTypeDist := td.DistData
         END;
      END;
   ELSE
      ShowDetailMenu;
   END;
   RETURN OK;
END VerifyValues;

BEGIN
   ClearMenuArea(w,0,0,DistHeaderMenu);
   ShowFixedText(w,DistHeaderMenu,0,0);

   ShowMenu(w,DistHeaderMenu,0,0,td);
   ShowDetailMenu;

   LOOP
      hd := td.DistData.Type;
      ItemNumb := 0;
      DoMenu(w,DistHeaderMenu,0,0,FieldMotionASC,LocalFunctTerm,
             td,ItemNumb,TC,FunctKey);

      KeyType := GetPanelControlKey(FunctKey,TC);
      IF KeyType = PanelCancel THEN RETURN END;

      WITH td.DistData DO
         IF hd <> Type THEN
            CASE Type OF
              DistByPos:  td.DistData := LastPosDist
            | DistByRef:  td.DistData := LastRefDist
            | DistByType: td.DistData := LastTypeDist
            END;
            ShowDetailMenu;
         END;
      END;

      CASE KeyType OF
        NotPanelControlKey:
          IF KeyType = NotPanelControlKey THEN
             IF (FunctKey) AND (Str.Pos(ExitList,TC) <= HIGH(ExitList))
             AND VerifyValues() THEN RETURN END;
          END;
      | NextField: ItemNumb := 0;
      | PrevField: Beep;
      | FirstField: (* do nothing right now *)
      | LastField: ItemNumb := 99;
      | PanelEnd:  IF VerifyValues() THEN RETURN END;
      END;

      DetailDone := TRUE;
      REPEAT
         DoMenu(w,temp,0,HeaderSize,FieldMotionASC,LocalFunctTerm,
                td,ItemNumb,TC,FunctKey);
         KeyType := GetPanelControlKey(FunctKey,TC);

         CASE KeyType OF
           NotPanelControlKey:
              IF (FunctKey) AND (Str.Pos(ExitList,TC) <= HIGH(ExitList)) THEN
                 IF VerifyValues() THEN RETURN
                                   ELSE DetailDone := FALSE END;
              END
         | NextField, PrevField, FirstField, LastField:
              (* do nothing right now *)
         | PanelEnd:  IF VerifyValues() THEN RETURN
                                        ELSE DetailDone := FALSE END;
         | PanelCancel: RETURN
         END
      UNTIL DetailDone;
   END (* LOOP *)
END DoDistributionDisplay;

BEGIN
   IF CurrentDisplay = None THEN
      (*RES OLD MSG 168
      You have no currently selected Display Screen.
      *)
      PutResError( (*RES REM INS*) 168 );
      RETURN
   END;
   PushHelpItem(OptionsHelp[CurrentDisplay]);
   td := DisplayData[CurrentDisplay];
   DisplayWindInfo.YSize := ModMenuLength[CurrentDisplay];
   PushNewWindow(DisplayWindInfo, w, DummyInit);
   Str.Concat( tStr, OptionLabel,ScreenLabel[CurrentDisplay]);
   TWB.SetTitle(w, tStr, TWB.RightLowerTitle);

   IF CurrentDisplay = Distribution THEN
      DoDistributionDisplay
   ELSE
      ShowFixedText(w,ModificationMenus[CurrentDisplay],0,0);
      ShowMenu(w,ModificationMenus[CurrentDisplay],0,0,td);
      in := 0;
      DoMenu(w,ModificationMenus[CurrentDisplay],0,0,TermList,ExitList,
            td,in,TC,FunctKey);
      KeyType := GetPanelControlKey(FunctKey,TC);
   END;

   CASE KeyType OF
     NotPanelControlKey:
        DisplayData[CurrentDisplay] := td;
	IF CurrentDisplay = Variable THEN
	   INC( DisplayData[Variable].ContextCount )
	END ;
        InitCurrentWindow;
        DoRead := FALSE
   | PanelCancel:
        DoRead := TRUE
   | PanelEnd:
        DisplayData[CurrentDisplay] := td;
	IF CurrentDisplay = Variable THEN (* can do better check than just invoked panel !? *)
	   INC( DisplayData[Variable].ContextCount )
	END ;
        InitCurrentWindow;
        DoRead := TRUE;
   END;

   PopWindow;
   PopHelpItem;

END ModifyCurrentWindow;

PROCEDURE MoveToNextDisplayWindow;
VAR
   NewTop:     WindowInfoPtr;
   i:          DisplayType;
BEGIN
   IF NumbDisplayScreens <= 1 THEN
      Beep;
      RETURN
   END;
   RollWindows(NewTop);
   i := None;
   REPEAT INC(i) UNTIL (i = MAX(DisplayType)) OR
	(DisplayData[i].OnScreen AND DisplayData[i].WindInfo.IsTop);
   IF (NOT DisplayData[i].OnScreen) OR (NOT DisplayData[i].WindInfo.IsTop) THEN
       ProgramErrorAndHalt('Could not find new top screen')
   END;
   CurrentDisplay := i;
   ReplaceHelpItem(DisplayHelp[CurrentDisplay]);
   DisplayProc[CurrentDisplay](InitKey);
END MoveToNextDisplayWindow;

PROCEDURE SendInstructionToCurrent(Inst: ScrollKey);
BEGIN
   IF CurrentDisplay = None THEN Beep
   ELSE DisplayProc[CurrentDisplay](Inst) END;
END SendInstructionToCurrent;

PROCEDURE InitializeAllActiveDisplays(IncludeTop: BOOLEAN): BOOLEAN;
VAR
   AnyChanged: BOOLEAN;
   i:          DisplayType;
BEGIN
   AnyChanged := FALSE;
   FOR i := Variable TO MAX(DisplayType) DO
     IF (DisplayData[i].OnScreen) AND
     (IncludeTop OR NOT DisplayData[i].WindInfo.IsTop) THEN
         DisplayProc[i](InitKey);
         AnyChanged := TRUE;
     END;
   END;
   RETURN AnyChanged;
END InitializeAllActiveDisplays;

PROCEDURE TerminateAllActiveDisplays;
VAR
   i:          DisplayType;
BEGIN
   FOR i := Variable TO MAX(DisplayType) DO
     IF (DisplayData[i].OnScreen) THEN DisplayProc[i](TermKey) END;
   END;
END TerminateAllActiveDisplays;

PROCEDURE InitializeData;
VAR T		: StrAny;
    dummy	: CARDINAL;
    I, K	: CARDINAL ;
    DefaultRef	: StrAny ;
    OtherOptionsMenu:      MenuID;
    ResC:   ResCollectionType;
    bd:     BOOLEAN;

BEGIN
   NumbDisplayScreens := 0;
   CurrentDisplay := None;
   WITH DisplayWindInfo DO
       XPos :=   5;
       YPos :=   4;
       XSize := 70;
       YSize := 14;
       MxYSize := 14;
       Type := Dialog;
       AllowMove := TRUE;
       AllowResize := FALSE;
       IsTop := FALSE;
   END;

   DisplayProc[Variable] := HandleVariableDisplay;
   DisplayProc[Text] := HandleTextDisplay;
   DisplayProc[KWIC] := HandleKWICDisplay;
   DisplayProc[Collocate] := HandleCollocateDisplay;
   DisplayProc[Distribution] := HandleDistDisplay;

   PrintProc[Variable] := OutputVariableDisplay;
   PrintProc[Text] := OutputTextDisplay;
   PrintProc[KWIC] := OutputKWICDisplay;
   PrintProc[Collocate] := OutputCollocateDisplay;
   PrintProc[Distribution] := OutputDistDisplay;

   ModMenuLength[Variable] := 16;   (* m.s. - Mar 95 - added 2 to each *)
   ModMenuLength[Text] := 7;
   ModMenuLength[KWIC] := 12;  (* m.s. - was 7 *)
   ModMenuLength[Collocate] := 13;
   ModMenuLength[Distribution] := 11;

   DisplayHelp[Variable] := 16;
   OptionsHelp[Variable] := 17;
   DisplayHelp[Text] := 18;
   OptionsHelp[Text] := 19;
   DisplayHelp[KWIC] := 14;
   OptionsHelp[KWIC] := 15;
   DisplayHelp[Collocate] := 39;		(* >>> need new NUMBER here <<< *)
   OptionsHelp[Collocate] := 40;		(* >>> need new NUMBER here <<< *)
   DisplayHelp[Distribution] := 12;
   OptionsHelp[Distribution] := 13;

   FOR j := Variable TO Distribution DO
      DisplayData[j].OnScreen := FALSE;
      DisplayData[j].WindInfoSet := FALSE;
      DisplayData[j].DisplayWordCountWord := TRUE ; (* m.s. - default is to display word rather than word count if $word selected *)
   END;
   WITH DisplayData[Variable] DO
       DispBefore := 2;
       DispAfter  := 2;
       UnitID     := 1; (* default is always lines *)
       ByPos := FALSE; (* temp line during transition *)
       WindInfo.IsTop := FALSE;
       ContextCount := 1 ; (* 0 = token context in DataItem not set *)
       VariableDispOrg := DispNatural;
   END;
   WITH DisplayData[Collocate].ColData DO
       ColBefore := 5;
       ColAfter  := 5;
       ColUnitID := 0; (* default is always words *)
       ColOverLaps := FALSE ;
       ColShowIntRslt := FALSE ;
   END;
   WITH DisplayData[Distribution] DO
      BlockChar := ' ';
      WITH DistData DO
         Type := DistByPos;
         Start := 0; End := 100; ByValue := 10;
      END;
   END;

   WITH DisplayData[KWIC] DO
      KWICDispOrg := DispNatural;
      ShowText := TRUE;
      DisplayBar := TRUE ;   (* m.s. *)
      HeadHiLite := TRUE ;   (* m.s. *)
   END;

   LastPosDist := DisplayData[Distribution].DistData;
   WITH LastRefDist DO
      DistRefName := '';
      DistRefID := 0;
      Type := DistByRef;
      RefOrder := FALSE ; (* m.s - default order of references *)
   END;
   LastTypeDist := LastRefDist;
   LastTypeDist.Type := DistByType;

   LocalTermsNotMade := TRUE;

   InitializeTextDisplay;
   InitializeVariableDisplay;
   InitializeCollocateDisplay;
   InitializeKWICDisplay;
   InitializeDistDisplay;

   WITH DisplayData[Variable] DO
	(* values for other constants are assigned via initialization  j.b. *)
	IF NOT GetNameFromID(UnitID,T,dummy) THEN
	   ProgramErrorAndHalt('GetNameFromID could not get given ID')
	END;
	SortToIntWord(T,UnitName);
   END ;
   IF LastRefPatLen = 0 THEN
      WITH DisplayData[Variable] DO
	   (* values for other constants are assigned via initialization  j.b. *)
	   DefaultRef[0] := '(' ;
	   DefaultRef[1] := '$' ;
	   I := 0 ; K := 2 ;
	   WHILE (I <= Str.Length(UnitName)) AND (UnitName[I] <> 0C ) DO
	      DefaultRef[ K ] := UnitName[ I ] ;
	      INC( K ) ; INC( I ) ;
	   END ;
	   DefaultRef[K] := ')' ;
	   DefaultRef[K+1] := 0C ;
       END;

       Str.Copy( LastRefPat, DefaultRef);
       Dummy := EncodeRefPat( LastRefPat, LastEncodedRefPat, LastRefPatLen);
   END;

   FOR j := Variable TO Distribution DO CopyLastRef(DisplayData[j]) END;

   StartMenu(DisplayData[Variable]);
   WITH DisplayData[Variable] DO
       CharFieldProc(RefInfo, ProcessRef);
       CardField(DispBefore);
       CardField(DispAfter);
       CharFieldProc(UnitName,VerifyUnitName);
       Switches(VariableDispOrg);
          SwitchValue(DispNatural);
          SwitchValue(DispPosition);
          SwitchValue(DispType);
       Switches(DisplayWordCountWord); (* m.s. - Mar 95 *)
          SwitchValue(TRUE);
          SwitchValue(FALSE);
   END;
   MakeMenu( VariableOptionsMenuID, ModificationMenus[Variable]);

   StartMenu(DisplayData[KWIC]);  (* m.s. was Variable, I don't know why ??? *)
   WITH DisplayData[KWIC] DO      (* m.s. was Variable *)
       CharFieldProc(RefInfo, ProcessRef);
       Switches(KWICDispOrg);
          SwitchValue(DispNatural);
          SwitchValue(DispPosition);
          SwitchValue(DispType);
          SwitchValue(DispTypeOnly);
       Switches(ShowText);
          SwitchValue(TRUE);
          SwitchValue(FALSE);
       Switches(DisplayBar); (* m.s. *)
          SwitchValue(TRUE);
          SwitchValue(FALSE);
       Switches(HeadHiLite); (* m.s. *)
          SwitchValue(TRUE);
          SwitchValue(FALSE);
       Switches(DisplayWordCountWord); (* m.s. - Mar 95 *)
          SwitchValue(TRUE);
          SwitchValue(FALSE);
   END;
   MakeMenu( KWICOptionsMenuID, ModificationMenus[KWIC]);

   StartMenu(DisplayData[Variable]);
   WITH DisplayData[Variable] DO
       CharFieldProc(RefInfo, ProcessRef);
       Switches(DisplayWordCountWord); (* m.s. - Mar 95 *)
          SwitchValue(TRUE);
          SwitchValue(FALSE);
   END;
   MakeMenu( OtherOptionsMenuID, ModificationMenus[Text]);

   StartMenu(DisplayData[Variable]);
   WITH DisplayData[Variable] DO
       Switches(DistData.Type);
          SwitchValue(DistByPos);
          SwitchValue(DistByRef);
          SwitchValue(DistByType);
       CharField(BlockChar);
       Switches(DisplayWordCountWord); (* m.s. - Mar 95 *)
          SwitchValue(TRUE);
          SwitchValue(FALSE);
   END;
   MakeMenu( DistHeaderMenuID, DistHeaderMenu);

   StartMenu(DisplayData[Variable]);
   WITH DisplayData[Variable] DO
          CharFieldProc(RefInfo, ProcessRef);
          CardFieldProc(DistData.Start,VerifyStart);
          CardFieldProc(DistData.End,VerifyEnd);
          CardFieldProc(DistData.ByValue,VerifyByValue);
   END;
   MakeMenu( DistByPosMenuID, DistByPosMenu);

   StartMenu(DisplayData[Variable]);
   WITH DisplayData[Variable] DO
          CharFieldProc(RefInfo, ProcessRef);
          CharFieldProc(DistData.DistRefName,VerifyDistUnitName);
          Switches( DistData.RefOrder );
            SwitchValue(TRUE) ;
            SwitchValue(FALSE) ;
   END;
   MakeMenu( DistByRefMenuID, DistByRefMenu);

   StartMenu(DisplayData[Variable]);
   WITH DisplayData[Variable] DO
       CharFieldProc(RefInfo, ProcessRef);
   END;
   MakeMenu( DistByTypeMenuID, DistByTypeMenu);

   StartMenu(DisplayData[Variable]);
   WITH DisplayData[Variable] DO
       CharFieldProc(RefInfo, ProcessRef);
       CardField(ColData.ColBefore);
       CardField(ColData.ColAfter);
       CharFieldProc(ColData.ColUnitName,VerifyColUnitName);
       Switches(ColData.ColOverLaps);
          SwitchValue(TRUE);
          SwitchValue(FALSE);
       Switches(ColData.ColShowIntRslt);
          SwitchValue(TRUE);
          SwitchValue(FALSE);
       Switches(DisplayWordCountWord); (* m.s. - Mar 95 *)
          SwitchValue(TRUE);
          SwitchValue(FALSE);
   END;
   WITH DisplayData[Collocate].ColData DO
	IF NOT GetNameFromID( ColUnitID, T, dummy ) THEN
	   ProgramErrorAndHalt('GetNameFromID could not get given ID')
	END;
	SortToIntWord(T, ColUnitName);
   END ;
   MakeMenu( ColGenOptionsMenuID, ModificationMenus[Collocate]);

   ModificationMenus[Distribution] := ModificationMenus[Text];

   IF LocalTermsNotMade THEN
       LocalTermsNotMade := FALSE;
       Str.Concat( LocalFunctTerm, FieldMotionExt,ExitList);
   END;

   (*RES OLD DTA 15
   'Variable Context Display'
   'Text Display'
   'KWIC Display'
   'Collocates Display'
   'Distribution Display'
   'Options for '
   *)
   GetDataArray( (*RES REM INS*) 15 , ResC);
   FOR j := Variable TO Distribution DO
      bd := GetNextDataArrayStringItem(ResC,ScreenLabel[j]);
   END;
   bd := GetNextDataArrayStringItem(ResC,OptionLabel);
   ReleaseCollection(ResC);
END InitializeData;

END DisplayDialog.
