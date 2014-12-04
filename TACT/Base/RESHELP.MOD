IMPLEMENTATION MODULE ResHelp;

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

FROM Utils IMPORT ALLOCATE, DEALLOCATE;
FROM GlobalDefs IMPORT StrAny;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResBase IMPORT FilePos;
FROM ResCollection IMPORT
   (* type *) ResCollectionType, ResCollectionData,
   (* proc *) GetCollection, NextColItem, PrevColItem, ReleaseCollection;
FROM ResArray IMPORT
   (*type*) ResDataType,ResArrayError,
   (*proc*) FindResource;

TYPE
   HelpPntrData= RECORD
      ResCol:      ResCollectionType;
      LineCount:   CARDINAL;
   END;
   HelpPntr = POINTER TO HelpPntrData;

PROCEDURE ResError;
BEGIN
   ProgramErrorAndHalt('Resource Error within ResHelp')
END ResError;

PROCEDURE StartHelpItem(HelpID:   CARDINAL;
                    VAR HelpCol:  HelpPntr;
                    VAR PntrData: HelpRefColl);
VAR
   Loc:    FilePos;
   size:   CARDINAL;
   Error:  ResArrayError;
BEGIN
   ALLOCATE(HelpCol,SIZE(HelpPntrData));
   IF NOT FindResource(HelpResource,HelpID,Loc,Error) THEN ResError END;
   WITH HelpCol^ DO
      IF NOT GetCollection(ResCol,Loc) THEN ResError END;
      LineCount := 0;
      IF NOT NextColItem(ResCol,PntrData,size) THEN ResError END;
   END;
END StartHelpItem;

PROCEDURE NextHelpLine(VAR HelpCol: HelpPntr;
                       VAR LineData: HelpData): BOOLEAN;
VAR  size:   CARDINAL;
BEGIN
   WITH HelpCol^ DO
      IF NOT NextColItem(ResCol,LineData,size) THEN RETURN FALSE END;
      INC(LineCount);
   END;
   RETURN TRUE;
END NextHelpLine;

PROCEDURE PrevHelpLine(VAR HelpCol: HelpPntr;
                       VAR LineData: HelpData): BOOLEAN;
VAR  size:   CARDINAL;
BEGIN
   WITH HelpCol^ DO
      IF LineCount <= 1 THEN RETURN FALSE END;
      IF NOT PrevColItem(ResCol,LineData,size) THEN ResError END;
      DEC(LineCount);
   END;
   RETURN TRUE;
END PrevHelpLine;

PROCEDURE CopyHelpItem(OldCol:    HelpPntr;
                    VAR NewCol:  HelpPntr);
BEGIN
   ALLOCATE(NewCol,SIZE(HelpPntrData));
   NewCol^ := OldCol^;
   ALLOCATE(NewCol^.ResCol,SIZE(ResCollectionData));
   NewCol^.ResCol^ := OldCol^.ResCol^;
END CopyHelpItem;

PROCEDURE DiscardHelpItem(VAR OldCol:  HelpPntr);
BEGIN
   DEALLOCATE(OldCol^.ResCol,SIZE(ResCollectionData));
   DEALLOCATE(OldCol,SIZE(HelpPntrData));
   OldCol := NIL;
END DiscardHelpItem;

PROCEDURE ReleaseHelpItem(VAR HelpCol: HelpPntr);
BEGIN
   ReleaseCollection(HelpCol^.ResCol);
   DEALLOCATE(HelpCol,SIZE(HelpPntrData));
   HelpCol := NIL;
END ReleaseHelpItem;

END ResHelp.
