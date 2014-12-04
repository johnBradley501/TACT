IMPLEMENTATION MODULE PrintModule ;

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

IMPORT ASCII;
IMPORT TWB, Str;
FROM KeyBase IMPORT KeyPressed, FlushKeyBoard;
FROM Lib IMPORT Intr ;
FROM SYSTEM IMPORT ADR, Registers ;
(* FROM DisplayDialog IMPORT DisplayType ; *)
FROM Translations IMPORT XlateLine, FindXlateTable, XFileType, Int2Scr,
           XlateTablePointer, XlateStrAny, XlateDirectionType,Scr2Int,
           CurrentModeType, XOpenOutput, XAppend, XClose, XWrNXlate, XWrLn ;
FROM KeyTranslation IMPORT TabInfo, IntTab, FILEText, PRINTERText,TabType,
   WriteScreenField;
FROM Utils IMPORT BFile, WrStr, WrLn, month, day, year,
         Exist,StandardizeFileName, RemoveExtension, TrimBlanks,
         ConstStr, UpcaseStr;
FROM ResMessages IMPORT ResAskUser, MsgString, PutResError, GetResMessage;
FROM GlobalDefs IMPORT
  (* Type  *) SequenceType, StrAny ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM UtilsTwo IMPORT IOErrorMessage, MakePrintableDate, OK;
FROM HelpBase IMPORT
  (* procs *) PushHelpItem, PopHelpItem;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CharField, CardField, CharFieldProc,
                 Switches, SwitchValue, GetFieldInfo,
                 MakeMenu, DestroyMenu, ShowFixedText, ShowMenu, DoMenu;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo,
  (* procs *) PushNewWindow, PopWindow, DummyInit;
FROM KeyStandards IMPORT
  (* types *) PanelControlKeys,
  (* procs *) GetPanelControlKey;
FROM Windows IMPORT BoldAttr;

(*RES OLD MSG 241
   IO Error %0 occurred.
*)
CONST
   IOErrorResNo = (*RES REM INS*) 241 ;

(*RES OLD MNU 27
                           Writing To Disk:

       FileName:    %0______________________________________
       Translation: %1______________
       Append to End of File: %|2  Overwrite File: %|3

Label:
  %4_______________________________________________________________
  %5_______________________________________________________________
  %6_______________________________________________________________
----------------------------------------------------------------------------
  %7_______________________________________________________________
  %8_______________________________________________________________
*)
   DiskMenuRes = (*RES REM INS*) 27 ;

(*RES OLD MNU 28
                               Printing

                  Printer:     %0_______
                  Translation: %1______________
                  Number of Lines per Page: %2_

Label:
  %3_______________________________________________________________
  %4_______________________________________________________________
  %5_______________________________________________________________
----------------------------------------------------------------------------
  %6_______________________________________________________________
  %7_______________________________________________________________
*)
   PrintMenuRes = (*RES REM INS*) 28 ;

(*RES OLD MSG 242
   %0
*)
  GenericMessage = (*RES REM INS*) 242 ;

   ListFileExtension = '.LST';
   MaxPrinterL = 4;
   PrintHelpRes = 21;
   FileHelpRes = 22;

TYPE
   IOInformationType = RECORD
       FileName:       ARRAY[0..80] OF CHAR;
       FileXN:         ARRAY[0..10] OF CHAR;
       PrinterID:      ARRAY[0..10] OF CHAR;
       PrintXN:        ARRAY[0..10] OF CHAR;
       LabelText:      ARRAY[0..2] OF ARRAY[0..79] OF CHAR;
       LinesPerPage:   CARDINAL;
       AppendToFile:   BOOLEAN ;
   END;
   StrAnyPntr = POINTER TO StrAny;

VAR
   PExitList:  StrAnyPntr;
   PFunctList:  StrAnyPntr;

   OldFileName:ARRAY [0..80] OF CHAR;
   DefFileName:ARRAY [0..80] OF CHAR;
   IOInfo:     IOInformationType;
   IOSpecsWind: WindowInfo;
   SetupIOInfo:BOOLEAN;
   MenuIDs:    ARRAY[ToDisk..ToPrinter] OF MenuID;
   HelpIDs:    ARRAY[ToDisk..ToPrinter] OF CARDINAL;
   MsgL1X:     ARRAY[ToDisk..ToPrinter] OF CARDINAL;
   MsgL1Y:     ARRAY[ToDisk..ToPrinter] OF CARDINAL;
   MsgL1L:     ARRAY[ToDisk..ToPrinter] OF CARDINAL;
   MsgL2X:     ARRAY[ToDisk..ToPrinter] OF CARDINAL;
   MsgL2Y:     ARRAY[ToDisk..ToPrinter] OF CARDINAL;
   MsgL2L:     ARRAY[ToDisk..ToPrinter] OF CARDINAL;
   PrinterL:   ARRAY[0..MaxPrinterL] OF ARRAY[0..4] OF CHAR;
   PortNo:     CARDINAL;
   FileNameVer:FileNameVerifyType;

PROCEDURE VerifyFN(Data: ADDRESS;
               VAR ReDisplay: BOOLEAN;
               VAR ReEdit: BOOLEAN);
TYPE
   DataPtrType =  POINTER TO IOInformationType;
VAR
   DP:   DataPtrType;
BEGIN
   DP := DataPtrType(Data);
   FileNameVer(DP^.FileName,'LST',ReDisplay,ReEdit);
END VerifyFN;

PROCEDURE AbortForFileIO(): BOOLEAN;
VAR ch:    CHAR;
BEGIN
   IF NOT KeyPressed() THEN RETURN FALSE END;
   FlushKeyBoard ;
   (*RES OLD CHE 12
   =S C
   To stop writing to the file named "%0", type "S"; and to continue, type "C":
   *)
   MsgString(IOInfo.FileName,0);
   ResAskUser( (*RES REM INS*) 12 ,'SC',ch);
   RETURN ch = 'S';
END AbortForFileIO;

PROCEDURE AbortForPrinter(): BOOLEAN;
VAR ch:    CHAR;
BEGIN
   IF NOT KeyPressed() THEN RETURN FALSE END;
   FlushKeyBoard ;
   (*RES OLD CHE 13
   =S C
   To stop printing on printer %0, type "S"; to continue, type "C":
   *)
   MsgString(IOInfo.PrinterID,0);
   ResAskUser( (*RES REM INS*) 13 ,'SC',ch);
   RETURN ch = 'S';
END AbortForPrinter;

PROCEDURE WriteWithTabs(VAR file:   XFileType;
                            text:   ARRAY OF CHAR;
                            Tabs:   ARRAY OF TabInfo): BOOLEAN;
VAR
   ts:         StrAny;
   al:         CARDINAL;
   ld:         XlateStrAny ;
   ns:         CARDINAL;
   ed:         BOOLEAN;
   result:     CARDINAL;
   Trial:      CARDINAL;
   NxtEvent:   CARDINAL;
   TabNo:      CARDINAL;
   TabBase:    CARDINAL;
   DoTabNext:  BOOLEAN;
   CurPos:     CARDINAL;
   ActCurPos:  CARDINAL;
   TempEndPos: CARDINAL;
   TabPos:     CARDINAL;
   MaxTabNo:   CARDINAL;
   CurrentStr: StrAnyPntr;
   EventChar:  CHAR;
   temp2:      StrAny;
   cm:         CurrentModeType;

PROCEDURE DoTabNow(VAR CurPos:    CARDINAL;
                       EndPos:    CARDINAL;
                       Pat:       ARRAY OF CHAR);
VAR
   len:      CARDINAL;
   temp:     StrAny;
   i,j,k:    CARDINAL;
   PatChar:  CHAR ;
   temp2:    StrAny;
   al:       CARDINAL;
BEGIN
   len := Str.Length(Pat);
   IF EndPos < CurPos THEN EndPos := CurPos + 5 END;

   IF len = 0 THEN
      PatChar := ' '
   ELSIF len = 1 THEN
      PatChar := Pat[0]
   END ;

   IF len <= 1 THEN
      ConstStr( PatChar, EndPos-CurPos, temp);
   ELSE (* pattern more than one character *)
      j := 0;
      i := CurPos MOD len;
      FOR k := CurPos TO EndPos DO
        temp[j] := Pat[i];
        INC(j); INC(i);
        IF (i >= len) THEN i := 0 END;
      END;
      temp[j] := 0C;
   END;
   XlateLine(file.XP,' ',temp,file.ModeData,al,ld,ns,ed,temp2) ;
   INC(ActCurPos,al);
   WrStr(file.ID,temp2,result);
(*
   INC(ActCurPos,j);
   WrStr(file.ID,temp,result);
*)
   IF result <> OK THEN
      IOErrorMessage(result,temp);
      MsgString(temp,0);
      PutResError( IOErrorResNo );
   END;
END DoTabNow;

BEGIN
    MaxTabNo := HIGH(Tabs);
    FOR TabNo := 0 TO MaxTabNo DO
       IF Tabs[TabNo].FilPat[0] <> 0C THEN
          cm.ModeIn := '0'; cm.ModeOut := '0';
          XlateLine(Scr2Int,' ',Tabs[TabNo].FilPat,cm,al,ld,ns,ed,temp2) ;
          Str.Copy(Tabs[TabNo].FilPat,temp2)
       END
    END;
    ActCurPos := 0;
    TabPos := 0;
    TabNo := 0;
    TabBase := 0;
    DoTabNext := FALSE;
    CurrentStr := ADR(text);
    CurPos := 0 ; (* m.s. *)
    LOOP
       Trial := Str.Pos(CurrentStr^, IntTab);
       IF Trial = MAX(CARDINAL) THEN
          NxtEvent := Str.Length(CurrentStr^);
          EventChar := 0C;
       ELSE
          NxtEvent := Trial;
          EventChar := CurrentStr^[Trial];
          CurrentStr^[NxtEvent] := 0C;
       END;

       IF NxtEvent <> 0 THEN
          XlateLine(file.XP,' ',CurrentStr^,file.ModeData,al,ld,ns,ed,temp2) ;
          IF DoTabNext THEN
             DoTabNext := FALSE;
             WITH Tabs[TabNo-1] DO
                CASE Type OF
                  Right:
		     IF TabPos > al THEN
			TempEndPos := TabPos - al
		     ELSE
			TempEndPos := ActCurPos + 2
		     END ;
		     DoTabNow( ActCurPos, TempEndPos, FilPat );
                     IF result <> OK THEN RETURN FALSE END;
                | Centre:
		     IF TabPos > (al DIV 2) THEN
			TempEndPos := TabPos - (al DIV 2)
		     ELSE
			TempEndPos := ActCurPos + 2
		     END ;
		     DoTabNow( ActCurPos, TempEndPos, FilPat );
                     IF result <> OK THEN RETURN FALSE END;
                ELSE ProgramErrorAndHalt('Tab Logic Failure')
                END
             END;
          END;
          INC(CurPos,NxtEvent);
          INC(ActCurPos,al);
          WrStr(file.ID,temp2,result);
          IF result <> OK THEN
             IOErrorMessage(result,temp2);
             MsgString(temp2,0);
             PutResError( IOErrorResNo );
             RETURN FALSE;
          END;
       END;

       CASE EventChar OF
         0C:
          WrLn(file.ID,result);
          RETURN result = OK;
       | IntTab:
          REPEAT
             IF TabNo > MaxTabNo THEN
                INC(TabBase,Tabs[MaxTabNo].Pos);
                INC(TabBase); (* one more for good luck j.b. *)
                TabNo := 0;
             END;
             TabPos := TabBase + Tabs[TabNo].Pos;
             INC(TabNo);
          UNTIL ActCurPos < TabPos;
          CASE Tabs[TabNo-1].Type OF
            Left:
		IF TabPos > 0 THEN
			TempEndPos := TabPos - 1
		ELSE
			TempEndPos := ActCurPos + 2
		END ;
               DoTabNow( ActCurPos, TempEndPos, Tabs[TabNo-1].FilPat ) ;
               IF result <> OK THEN RETURN FALSE END;
          | Right, Centre:
               DoTabNext := TRUE;
          ELSE ProgramErrorAndHalt('This Tab Type not yet implemented')
          END;
       ELSE ProgramErrorAndHalt('Bad Event Char found in WriteWithTabs')
       END;
       CurrentStr := ADR(CurrentStr^[NxtEvent+1]);
    END;
END WriteWithTabs;

PROCEDURE PrintMaster( Destination : PrintActionType;
                       DoPrint :     PrintProcType;
                   VAR DoRead:       BOOLEAN;
                   VAR ch:           CHAR;
                   VAR FunctKey:     BOOLEAN);
VAR
   w:          TWB.WinType;
   L:          CARDINAL;
   Done:       BOOLEAN;
   file:       XFileType;
   Message:    StrAny;
   OpenResult: BOOLEAN;
   result:     CARDINAL;

PROCEDURE CheckPrinterID(): BOOLEAN;
VAR
   l:     CARDINAL;
BEGIN
   TrimBlanks(IOInfo.PrinterID,IOInfo.PrinterID);
   UpcaseStr(IOInfo.PrinterID,IOInfo.PrinterID);
   IF IOInfo.PrinterID[0] = 0C THEN
      IOInfo.PrinterID := 'LPT1';
      RETURN TRUE
   END;
   l := Str.Length(IOInfo.PrinterID);
   IF IOInfo.PrinterID[l-1] = ':' THEN IOInfo.PrinterID[l-1] := 0C END;
   FOR l := 0 TO MaxPrinterL DO
      IF Str.Compare(IOInfo.PrinterID,PrinterL[l]) = 0 THEN
	 PortNo := l ;
	 RETURN TRUE
      END;
   END;
   (*RES OLD MSG 247
   "%0" is not Supported as a Printer Type in TACT.
   *)
   MsgString(IOInfo.PrinterID,0);
   PutResError( (*RES REM INS*) 247 );
   RETURN FALSE;
END CheckPrinterID;

(*
Int 17H, AH=02H (* Get printer status *)
DX = port (0-3)
AH = status bits
     0 = time out
     1 = unused
     2 = unused
     3 = I/O error
     4 = selected
     5 = out of paper
     6 = acknowledge
     7 = not busy
*)

PROCEDURE CheckPrinterStatus( port : CARDINAL; VAR MsgId : CARDINAL ) : BOOLEAN ;
   VAR
	PrtStatus : BITSET ;
	Regs	  : Registers ;
   BEGIN
	IF port >= 3 THEN  RETURN TRUE (* using COM1: or COM2: *) END ;
	Regs.AH := 02H ;
	Regs.DX := port ;
        Intr( Regs, 17H ) ;
        PrtStatus := BITSET(VAL(CARDINAL, Regs.AH ) );
	IF BITSET{4,7} = PrtStatus THEN
	   (* printer is on and OK *)
	   RETURN TRUE
	ELSE
	   IF BITSET{4,5,7} = PrtStatus THEN
		(*RES OLD MSG 258
		There is a Printer Error for "%0". The Device is not Connected.
		*)
		MsgId := (*RES REM INS *) 258 ;
	   ELSIF (BITSET{3,4,6,7} = PrtStatus) OR (BITSET{3,4,5,6,7} = PrtStatus) THEN
		(* -- bit 5 (out of paper) is sometimes on and othertimes off! -- *)
		(*RES OLD MSG 259
		There is a Printer Error for "%0". The Device is Switched OFF.
		*)
		MsgId := (*RES REM INS *) 259 ;
	   ELSIF BITSET{3,4,5} = PrtStatus THEN
		(*RES OLD MSG 260
		There is a Printer Error for "%0". The Device is Out of Paper.
		*)
		MsgId := (*RES REM INS *) 260 ;
	   ELSIF BITSET{3,4} = PrtStatus THEN
		(*RES OLD MSG 261
		There is a Printer Error for "%0". The Device is Offline.
		*)
		MsgId := (*RES REM INS *) 261 ;
	   ELSE
		(*RES OLD MSG 262
		There is a Printer Error for "%0". The Device is Out-of-order.
		*)
		MsgId := (*RES REM INS *) 262 ;
	   END ;
	   RETURN FALSE
	END ;
   END CheckPrinterStatus ;

PROCEDURE DoLabelPrinting(): BOOLEAN;
VAR L:  CARDINAL;
    P:  BOOLEAN;
    T:  ARRAY[0..0] OF TabInfo;
BEGIN
   WITH T[0] DO Pos := 5; Type := Left; FilPat := 0C; END;

   P := FALSE;
   FOR L := 0 TO 2 DO
      TrimBlanks(IOInfo.LabelText[L], IOInfo.LabelText[L]);
      IF IOInfo.LabelText[L,0] <> 0C THEN
         P := TRUE;
         IF NOT WriteWithTabs(file, IOInfo.LabelText[L],T) THEN RETURN FALSE END;
      END;
   END;
   IF P THEN
      ConstStr(CHR(31) (* internal character: rule *) , 65, Message);
      IF NOT WriteWithTabs(file, Message ,T) THEN RETURN FALSE END;
   END;
   RETURN TRUE;
END DoLabelPrinting;

PROCEDURE OpenAndDoPrint;
   VAR
	ch	   : CHAR ;
	FileExists : BOOLEAN ;
	MsgId	   : CARDINAL ;
	FinalStr   : ARRAY[0..3] OF CHAR ;
	AbortType  : AbortProc;
BEGIN
   IF Destination = ToPrinter THEN
      IF NOT CheckPrinterID() THEN
         Done := FALSE
      ELSIF NOT CheckPrinterStatus( PortNo, MsgId ) THEN
         MsgString(IOInfo.PrinterID, 0);
         PutResError( MsgId );
         Done := FALSE;
      ELSIF NOT XOpenOutput(IOInfo.PrinterID,'',IOInfo.PrintXN,file,Message) THEN
         MsgString(Message,0);
         PutResError( GenericMessage );
         Done := FALSE;
      END;
   ELSE
      TrimBlanks(IOInfo.FileName,IOInfo.FileName);
      IF IOInfo.FileName[0] = 0C THEN Str.Copy(IOInfo.FileName, DefFileName) END;
      IF ( NOT StandardizeFileName(IOInfo.FileName, ListFileExtension)) THEN
         (*RES OLD MSG 243
         "%0" is not a Legal File Name.
         *)
         MsgString(IOInfo.FileName,0);
         PutResError( (*RES REM INS*) 243 );
         Done := FALSE;
      ELSE
	 FileExists := Exist(IOInfo.FileName) ;
	 IF (Str.Compare(OldFileName, IOInfo.FileName) <> 0) AND FileExists
         AND (NOT IOInfo.AppendToFile) THEN
	    (*RES OLD CHE 14
	    = P C
	    The file named "%0" already exists. Type "P" to proceed,
	    or "C" to cancel:
	    *)
	    MsgString( IOInfo.FileName, 0 ) ;
	    ResAskUser( (*RES REM INS *) 14 , 'PC', ch ) ;
	    Done := ch = 'P' ;
	 END ;
	 IF Done THEN
	    IF IOInfo.AppendToFile AND FileExists THEN
		OpenResult := XAppend(IOInfo.FileName,ListFileExtension,IOInfo.FileXN,file,Message)
	    ELSE
		OpenResult := XOpenOutput(IOInfo.FileName,ListFileExtension,IOInfo.FileXN,file,Message)
	    END;
	    IF NOT OpenResult THEN
		MsgString(Message,0);
		PutResError( GenericMessage );
		Done := FALSE;
	    END;
	 END ;
      END;
   END;

   (* the following bit of code is a kludge to make PRINTMOD
   begin output (or printing) by explicitly setting the printer
   file mode >>only<< if printing uses a different xlatlation table
   from the screen  .. j.b. *)

   IF ADDRESS(file.XP) <> ADDRESS(Int2Scr) THEN file.ModeData.ModeOut := ' ' END;

   ShowMenu(w,MenuIDs[Destination],0,0,IOInfo);

   IF NOT Done THEN  RETURN  END ;

   IF Destination = ToPrinter THEN
      (*RES OLD MSG 244
      Now Printingon Device %0.
      *)
      MsgString(IOInfo.PrinterID,0);
      GetResMessage( (*RES REM INS*) 244, Message);
   ELSE
      (*RES OLD MSG 245
      Now Writing to File %0.
      *)
      MsgString(IOInfo.FileName,0);
      GetResMessage( (*RES REM INS*) 245, Message);
   END;
   WriteScreenField( w, MsgL1L[Destination],
        MsgL1X[Destination], MsgL1Y[Destination], Message,
        BoldAttr, FALSE );

   (*RES OLD MSG 246
   To Interrupt, Type any Key.
   *)
   GetResMessage( (*RES REM INS*) 246, Message);
   WriteScreenField( w, MsgL2L[Destination],
        MsgL2X[Destination], MsgL2Y[Destination], Message,
        BoldAttr, FALSE );

   IF Destination = ToPrinter THEN
      PrintDest := Destination ; (* exported value *)
      LinesPerPage := IOInfo.LinesPerPage ;
      AbortType := AbortForPrinter;
   ELSE
      AbortType := AbortForFileIO;
   END;
   IF DoLabelPrinting() THEN DoPrint(file, AbortType) END;

   FinalStr[0] := ASCII.ff ;
   FinalStr[1] := ASCII.cr ;
   FinalStr[2] := ASCII.lf ;
   FinalStr[3] := 0C ;
   XWrNXlate(file,FinalStr,result);
   IF result <> OK THEN
      IOErrorMessage(result,Message);
      MsgString(Message,0);
      PutResError( IOErrorResNo );
      RETURN
   END;
   XClose(file);
END OpenAndDoPrint;

BEGIN
   IF SetupIOInfo THEN
      Str.Copy(IOInfo.FileXN, FILEText);
      Str.Copy(IOInfo.PrintXN, PRINTERText);
      IOInfo.PrinterID := 'LPT1';
      StartMenu(IOInfo);
      WITH IOInfo DO
         CharField(PrinterID);
         CharField(PrintXN);
         CardField(LinesPerPage);
         FOR L := 0 TO 2 DO CharField(LabelText[L]) END;
      END;
      MakeMenu(PrintMenuRes,MenuIDs[ToPrinter]);
      GetFieldInfo(MenuIDs[ToPrinter],6,
           MsgL1X[ToPrinter],MsgL1Y[ToPrinter],MsgL1L[ToPrinter]);
      GetFieldInfo(MenuIDs[ToPrinter],7,
           MsgL2X[ToPrinter],MsgL2Y[ToPrinter],MsgL2L[ToPrinter]);
      StartMenu(IOInfo);
      WITH IOInfo DO
         CharFieldProc(FileName,VerifyFN);
         CharField(FileXN);
         Switches(AppendToFile);
	    SwitchValue(TRUE);
	    SwitchValue(FALSE);
         FOR L := 0 TO 2 DO CharField(LabelText[L]) END;
      END;
      MakeMenu(DiskMenuRes,MenuIDs[ToDisk]);
      GetFieldInfo(MenuIDs[ToDisk],7,
           MsgL1X[ToDisk],MsgL1Y[ToDisk],MsgL1L[ToDisk]);
      GetFieldInfo(MenuIDs[ToDisk],8,
           MsgL2X[ToDisk],MsgL2Y[ToDisk],MsgL2L[ToDisk]);
      SetupIOInfo := FALSE;
   END;
   IOInfo.AppendToFile := TRUE ;
   PushHelpItem(HelpIDs[Destination]);
   PushNewWindow(IOSpecsWind,w, DummyInit);
   ShowFixedText(w, MenuIDs[Destination], 0,0);
   ShowMenu(w,MenuIDs[Destination],0,0,IOInfo);
   L := 0;
   DoRead := FALSE;
   LOOP
      Done := TRUE;
      DoMenu(w,MenuIDs[Destination],0,0,PFunctList^,PExitList^,IOInfo,L,ch,FunctKey);
      CASE GetPanelControlKey(FunctKey, ch) OF
        PanelCancel:
          DoRead := TRUE;
          PopWindow;
          PopHelpItem;
          RETURN
      | PanelEnd:
          OpenAndDoPrint;
          IF Done THEN
	     Str.Copy( OldFileName, IOInfo.FileName ) ;
             DoRead := TRUE;
             PopWindow;
             PopHelpItem;
             RETURN
          END;
      ELSE
          DoRead := FALSE;
          PopWindow;
          PopHelpItem;
          RETURN
      END;
   END;
END PrintMaster;

PROCEDURE TerminatePrintModule;
BEGIN
   IF NOT SetupIOInfo THEN
      DestroyMenu(MenuIDs[ToDisk]);
      DestroyMenu(MenuIDs[ToPrinter])
   END;
END TerminatePrintModule;

PROCEDURE InitialPrintModule(VAR FileNameModel: ARRAY OF CHAR;
                             VAR ExitList:      ARRAY OF CHAR;
                             VAR FuncList:      ARRAY OF CHAR;
                                 VerifyProc:    FileNameVerifyType);
VAR L:  CARDINAL;
BEGIN
   PExitList := ADR(ExitList);
   PFunctList := ADR(FuncList);
   OldFileName := '' ;
   RemoveExtension(FileNameModel,DefFileName);
   IF ( NOT StandardizeFileName(DefFileName, ListFileExtension)) THEN
      ProgramErrorAndHalt('Unexpected problem creating LST file Name');
   END;
   Str.Copy(IOInfo.FileName, DefFileName);
   IOInfo.LinesPerPage := 60 ;

   FileNameVer := VerifyProc;
   SetupIOInfo := TRUE;
   WITH IOSpecsWind DO
       XPos := 5;
       YPos := 4;
       YSize := 13;
       XSize := 68;
       MxYSize := 8;
       Type := Dialog;
       AllowMove := TRUE;
       AllowResize := FALSE;
   END;
   PrinterL[0] := 'LPT1';
   PrinterL[1] := 'LPT2';
   PrinterL[2] := 'LPT3';
   PrinterL[3] := 'COM1';
   PrinterL[4] := 'COM2';
   HelpIDs[ToDisk] := FileHelpRes;
   HelpIDs[ToPrinter] := PrintHelpRes;

   FOR L := 0 TO 2 DO IOInfo.LabelText[L] := '' END;
   MakePrintableDate(day, month, year, IOInfo.LabelText[2]);
END InitialPrintModule;

END PrintModule .
