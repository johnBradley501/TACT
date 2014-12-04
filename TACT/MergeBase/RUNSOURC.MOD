IMPLEMENTATION MODULE RUNSource ;

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

IMPORT FIO, TWB;
FROM HRecPntrTranslation IMPORT CleanUpXFiles;
FROM TDBBase IMPORT OutFile, OutFileRec, OutHeader ;
FROM TDBStart IMPORT
  (* procs *) WriteHeaderMaterial;
FROM TextHandling IMPORT HandleText;
FROM StringHandling IMPORT HandleStrings;
FROM LogHandling IMPORT HandleLog;
FROM TypeHandling IMPORT HandleTypes;
(* FROM OccurHandling IMPORT HandleOccurs, TempFileName; *)
FROM TokenHandling IMPORT HandleTokens;
FROM ResMenus IMPORT
  (* type    *)  MenuID,
  (* proc    *)  StartMenu, CardField, MakeMenu, DestroyMenu,
                 ClearMenuArea, ShowFixedText, ShowMenu;

CONST
   YPosForStatusMenu = 19;

(*RES OLD MNU 30
           Status of .TDB Merging: Current Phase: %0___ of 7 phases
                        To interrupt press any key.

*)
    StatusMenuResID = (*RES REM INS*) 30 ;

PROCEDURE Run(VAR BaseWind: TWB.WinType);

VAR
    CurrentPhase:   CARDINAL;
    StatusMenu:     MenuID;

PROCEDURE WriteHeader;
BEGIN
   FIO.Seek(OutFile,0);
   FIO.WrBin(OutFile, OutHeader, SIZE(OutHeader));
   FIO.Close(OutFile);
END WriteHeader;

PROCEDURE CleanUpTemps;
BEGIN
(* IF FIO.Exists(TempFileName) THEN FIO.Erase(TempFileName) END; *)
   CleanUpXFiles;
END CleanUpTemps;

BEGIN

   StartMenu(CurrentPhase);
   CardField(CurrentPhase);
   MakeMenu( StatusMenuResID, StatusMenu);
   ClearMenuArea(BaseWind, 0, YPosForStatusMenu, StatusMenu);
   ShowFixedText(BaseWind, StatusMenu, 0, YPosForStatusMenu);

   CurrentPhase := 1;
   ShowMenu(BaseWind, StatusMenu, 0, YPosForStatusMenu,CurrentPhase);
   WriteHeaderMaterial;

   CurrentPhase := 2;
   ShowMenu(BaseWind, StatusMenu, 0, YPosForStatusMenu,CurrentPhase);
   HandleText;
   CurrentPhase := 3;
   ShowMenu(BaseWind, StatusMenu, 0, YPosForStatusMenu,CurrentPhase);
   HandleStrings;
   CurrentPhase := 4;
   ShowMenu(BaseWind, StatusMenu, 0, YPosForStatusMenu,CurrentPhase);
   HandleLog;

   CurrentPhase := 5;
   ShowMenu(BaseWind, StatusMenu, 0, YPosForStatusMenu,CurrentPhase);
   HandleTypes;
(*
   CurrentPhase := 6;
   ShowMenu(BaseWind, StatusMenu, 0, YPosForStatusMenu,CurrentPhase);
   HandleOccurs;
*)
   CurrentPhase := 7;
   ShowMenu(BaseWind, StatusMenu, 0, YPosForStatusMenu,CurrentPhase);
   HandleTokens;

   WriteHeader;
   CleanUpTemps;

END Run;

END RUNSource .
