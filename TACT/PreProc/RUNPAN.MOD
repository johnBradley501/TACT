IMPLEMENTATION MODULE RunPan ;

(* copyright (c) 1991-96 Ian Lancashire, Mike Stairs, Lidio Presutti, University of Toronto *)

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

(*--------------------------------------------------------------------------*)
(* By:    Lidio Presutti                                                    *)
(* Date:  Feb. 16, 1988                                                     *)
(* Purpose:                                                                 *)
(*                                                                          *)
(* History:                                                                 *)
(*   16 Feb 88, Lidio Presutti                                              *)
(*      - added DragOff(TextScrId) to prevent text from being dragged by    *)
(*        long line in the text window.                                     *)
(*                                                                          *)
(*   22 Jun 88, Lidio Presutti                                              *)
(*      - added UpdateOn/Off to PutRecordNumber and turned off in           *)
(*        WriteTextWindow.                                                  *)
(*                                                                          *)
(*--------------------------------------------------------------------------*)

IMPORT ASCII, Str ;
FROM KeyTranslation IMPORT
  (* Procs *) WriteScreenField ;
FROM Windows  IMPORT
  (* Const *) RegularAttr, BoldAttr,
  (* Vars  *) ActiveAttrib,
  (* Procs *) CreateNewWindow, GetRidOfWindow ;
FROM GlobalDefs IMPORT
  (* Const *) MaxStringLen, FileNameType,
  (* Types *) StrAny;
FROM HyperDataModel IMPORT
  (* Const *) MaxDBTitleLength ;
FROM StartUp IMPORT FileData;
FROM TokenDataSource IMPORT
  (* Vars  *) RecordNumber, TokenNumber, TypeNumber ;
FROM ResMessages IMPORT
  (* Procs *) PutResMessage, GetResMessage ;
FROM ResMenus IMPORT
  (* Type *) MenuID,
  (* proc *) StartMenu, CharField, LongIntField, MakeMenu, DestroyMenu,
             GetFieldInfo, ClearMenuArea, ShowFixedText, ShowMenu ;
FROM StringIO IMPORT
   SWriteCard, SWriteLongCard;

IMPORT TWB ;

(* This is code for displaying statistics on the run panel display in MAKBAS  *)
(*RES OLD MNU 55
                              PREPROC RUN PHASE

 For: Database:  %0___________________________________________
     Setup File: %1___________________________________________

 Input Record:   %2___________                    Word-token Count: %3_______
 Status: %5______________________________________ Word-type Count:  %4_______
 Percentage Completed: %6_%                 No. of Errors/Warnings: %7_______

To interrupt execution, press ESC key. To toggle ON/OFF text display press F2.
*)


CONST
   DBNameVal   = 0 ;
   DBTitleVal  = 1 ;
   InRecVal    = 2 ;
   TokCountVal = 3 ;
   TokTypeVal  = 4 ;
   RunStatVal  = 5 ;
   PerCentVal  = 6 ;
   ErrCountVal = 7 ;
   MaxFields   = 7 ;  (* zero based, ie. 0..7 *)

   RunPanRes = (*RES REM INS*) 55 ;

VAR
   rc        : CARDINAL ;
   StatsWind : TWB.WinType ;
   TextWind  : TWB.WinType ;
   OK        : BOOLEAN ;
   LongStr   : ARRAY[0..10] OF CHAR ;
   PosX      : ARRAY[0..MaxFields] OF CARDINAL ;
   PosY      : ARRAY[0..MaxFields] OF CARDINAL ;
   FLen      : ARRAY[0..MaxFields] OF CARDINAL ;
   RunMenu   : MenuID ;

PROCEDURE SetupRunWindows ;

  (*RES OLD MSG 121
  Program terminating.
  *)
  CONST
     TermResMsg = (*RES REM INS*) 121 ;
  VAR
     I : CARDINAL ;
  BEGIN
     CreateNewWindow( StatsWind, 1, 1, 10, 80, 80, ActiveAttrib, TRUE );

     StartMenu( I ) ; (* variable doesn't matter j.b. *)
     MakeMenu( RunPanRes, RunMenu ) ;

     FOR I := 0 TO MaxFields DO
        GetFieldInfo( RunMenu, I, PosX[I], PosY[I], FLen[I] ) ;
     END ;

     CreateNewWindow( TextWind, 1, 13, 10, 80, 255, ActiveAttrib, TRUE );
     ShowRunScreen ;
  END SetupRunWindows ;

PROCEDURE ShowRunScreen;
   BEGIN
      TWB.Use(StatsWind);
      TWB.Clear;
      TWB.SetPaletteColor( RegularAttr);

      ShowFixedText( StatsWind, RunMenu, 0, 0 ) ;

      PutRecordNumber( RecordNumber ) ;
      PutTokenCount( TokenNumber ) ;
      PutTypeCount( TypeNumber ) ;

      WriteScreenField( StatsWind, FLen[DBNameVal], PosX[DBNameVal],
                              PosY[DBNameVal], FileData.InputFileName,
                              BoldAttr, FALSE ) ;
      WriteScreenField( StatsWind, FLen[DBTitleVal], PosX[DBTitleVal],
                              PosY[DBTitleVal], FileData.SetupFileName,
                              BoldAttr, TRUE );
   END ShowRunScreen ;

PROCEDURE PutRunStatus(ResID:    CARDINAL);
VAR
   MsgTxt:   StrAny;
BEGIN
     GetResMessage(ResID,MsgTxt);
     WriteScreenField( StatsWind, FLen[RunStatVal], PosX[RunStatVal],
                             PosY[RunStatVal], MsgTxt, RegularAttr, TRUE ) ;
END PutRunStatus;

PROCEDURE PutErrorCount( N : CARDINAL ) ;
  BEGIN
(*   CardToString( N, LongStr, 5 );  *)
     rc := 0;
     LongStr[0] := 0C;
     SWriteCard(LongStr,rc,N,8);
     TWB.Use(StatsWind);
     TWB.GotoXY(PosX[ErrCountVal], PosY[ErrCountVal]);
     TWB.WrStr(LongStr);
  END PutErrorCount;

PROCEDURE PutRecordNumber( N : LONGCARD ) ;
  BEGIN
     rc := 0;
     LongStr[0] := 0C;
     SWriteLongCard(LongStr,rc,N,8);
     TWB.Use(StatsWind);
     TWB.GotoXY(PosX[InRecVal], PosY[InRecVal]);
     TWB.WrStr(LongStr);
  END PutRecordNumber ;

PROCEDURE PutTokenCount( N : LONGCARD ) ;
  BEGIN
     rc := 0;
     LongStr[0] := 0C;
     SWriteLongCard(LongStr,rc,N,8);
     TWB.Use(StatsWind);
     TWB.GotoXY(PosX[TokCountVal], PosY[TokCountVal]);
     TWB.WrStr(LongStr);
  END PutTokenCount ;

PROCEDURE PutTypeCount( N : LONGCARD ) ;
  BEGIN
     rc := 0;
     LongStr[0] := 0C;
     SWriteLongCard(LongStr,rc,N,8);
     TWB.Use(StatsWind);
     TWB.GotoXY(PosX[TokTypeVal], PosY[TokTypeVal]);
     TWB.WrStr(LongStr);
  END PutTypeCount ;

PROCEDURE PutPercentage( N : CARDINAL; update : BOOLEAN ) ;
  BEGIN
     IF N > 100 THEN N := 100 END;
     rc := 0;
     LongStr[0] := 0C;
     SWriteCard(LongStr,rc,N,3);
     TWB.Use(StatsWind);
     TWB.GotoXY(PosX[PerCentVal], PosY[PerCentVal]);
     TWB.WrStr(LongStr);
  END PutPercentage;

PROCEDURE WriteTextWindow( TextLine : ARRAY OF CHAR ) ;
  BEGIN

(* Constants in the following line:
     0 for length means "do not check length"
     2000 for X means "write where window cursor is, and move to a
                       new line after writing"
     1000 for Y means "write on current line"
*)
     WriteScreenField( TextWind, 0, 2000,1000,TextLine, RegularAttr, TRUE) ;
  END WriteTextWindow ;

PROCEDURE ClearAndWriteTextWindow(TextLine: ARRAY OF CHAR);
BEGIN
   TWB.Use(TextWind);
   TWB.Clear;
   WriteScreenField( TextWind, 0, 2000,1000,TextLine, RegularAttr, TRUE) ;
END ClearAndWriteTextWindow;

(* This is code for display input text on the run panel display in MAKBAS  *)

PROCEDURE CleanupRunWindows ;
  BEGIN
     GetRidOfWindow( StatsWind );
     GetRidOfWindow( TextWind );
     DestroyMenu( RunMenu ) ;
  END CleanupRunWindows ;

END RunPan .


