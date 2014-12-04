IMPLEMENTATION MODULE AlphaPanel ;

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

FROM SYSTEM  IMPORT ADR,SIZE;
IMPORT TWB;
IMPORT ASCII;
FROM Windows IMPORT
  (* Consts *) RegularAttr, BoldAttr, SpecialAttr,
  (* Vars   *) InActiveAttrib, DialogAttrib;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo, WindowInfoPtr,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM SetupFile IMPORT SetupWriteNeeded;
FROM ResMenus IMPORT
  (* type   *) MenuID,
  (* proc   *) StartMenu, CharField, MakeMenu, DestroyMenu, GetFieldInfo,
               ShowFixedText, ShowMenu, DoMenu;
FROM ResMessages IMPORT GetResMessage;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, PopHelpItem;
FROM GlobalDefs IMPORT
  (* Type   *) SequenceType, StrAny;

(* This is code for the front panel display and selection processing  *)
(* for MAKEBASE                                                         *)

(*RES OLD MNU 13

                 ALPHABET, DIACRITICS, AND CONTINUATION SEQUENCE

Alphabet
 %0_________________________________________________________________________
 %1_________________________________________________________________________
 %2_________________________________________________________________________
 %3_________________________________________________________________________
Diacritics Retained
 %4_________________________________________________________________________
 %5_________________________________________________________________________
Diacritics NonRetained
 %6_________________________________________________________________________
 %7_________________________________________________________________________
Continuation Sequence:  %8_____

 To edit or add material, move to line using Up or Down arrow Keys and type.
        When finished, press "Enter / Return".

*)

VAR
   AlphaMenuDefined  : BOOLEAN;
   rc                : CARDINAL ;
   AlphaWindowRec    : TWB.WinType ;
   AlphaMenu         : MenuID;
   AlphaWind         : WindowInfo;

PROCEDURE GetAlphaPanel(StartPos  : CARDINAL ) ;
   VAR
      L        : CARDINAL ;
      FunctKey : BOOLEAN ;
      TC       : CHAR ;   (* terminating character from DoMenu operation *)

PROCEDURE InitialAlphaMenu;
VAR i: CARDINAL;
BEGIN
   StartMenu(AlphaInfo);
   WITH AlphaInfo DO
     FOR i := 1 TO NoAlphaLines DO CharField(AlphaString[i]) END;
     FOR i := 1 TO NoRetDiLines DO CharField(RetDiacStr[i]) END;
     FOR i := 1 TO NoNonDiLines DO CharField(NonDiacStr[i]) END;
     CharField(ContinuationSeq);
   END;
   MakeMenu( (*RES REM INS*) 13 , AlphaMenu);
END InitialAlphaMenu;

PROCEDURE DisplayLabel;
VAR a:  ARRAY[0..40] OF CHAR;
BEGIN
   (*RES OLD MSG 206
   Letters and Word Symbols
   *)
   GetResMessage( (*RES REM INS*) 206 ,a);
   TWB.SetTitle(AlphaWindowRec, a, TWB.RightLowerTitle);
END DisplayLabel;

   BEGIN
      IF NOT AlphaMenuDefined THEN InitialAlphaMenu END;
      AlphaMenuDefined := TRUE;
      PushHelpItem(27);
      PushNewWindow(AlphaWind,AlphaWindowRec, DummyInit);
      DisplayLabel;

      ShowFixedText(AlphaWindowRec, AlphaMenu,0,0);

      SetupWriteNeeded := TRUE ;

      ShowMenu(AlphaWindowRec,AlphaMenu,0,0,AlphaInfo);
      L := StartPos;
      DoMenu(AlphaWindowRec,AlphaMenu,0,0,ASCII.rs,0C,AlphaInfo,L,TC,FunctKey);

      PopHelpItem;
      PopWindow;
   END  GetAlphaPanel ;

PROCEDURE DiscardAlphaMenu;
BEGIN
   IF AlphaMenuDefined THEN DestroyMenu(AlphaMenu) END;
   AlphaMenuDefined := FALSE;
END DiscardAlphaMenu;

PROCEDURE InitCodeAlphaPanel ;  (* this is for OVERLAY mechanism *LP* *)
BEGIN
   AlphaMenuDefined := FALSE;
   WITH AlphaWind DO
      XPos := 2;
      YPos := 4;
      XSize := 78;
      YSize := 19;
      MxYSize := 19;
      Type :=       Dialog;
      AllowMove :=  FALSE;
      AllowResize :=FALSE;
      IsTop :=      FALSE
   END;
END InitCodeAlphaPanel ;

END AlphaPanel .
