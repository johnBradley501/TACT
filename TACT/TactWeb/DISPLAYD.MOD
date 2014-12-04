IMPLEMENTATION MODULE DisplayDialog (* Window *) ;
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


FROM SYSTEM IMPORT ADDRESS,ADR;
IMPORT Str, Lib ;
IMPORT ASCII;
FROM GlobalDefs IMPORT StrAny;
FROM Utils IMPORT Beep,TrimBlanks;
FROM WordBase IMPORT
  (* Procs *) SortToIntWord;
FROM ErrorBase IMPORT
  (* procs  *) ProgramErrorAndHalt;
FROM ResMessages IMPORT
  (* proc *) MsgString, MsgCard, PutResError, PutResWarning, PutResMessage;
FROM RefsBase IMPORT
   (* types *) RefsNameList, RefsNameData,
   (* vars  *) RefsNameListPntr, NumbOfRefNames,
   (* procs *) LookupRefName, GetNameFromID;
FROM TACTDataServices IMPORT
   (* const *) NotRefNameRes;
FROM channels IMPORT
  (* type *) channel,
  (* proc *) open, attachsender, attachreceiver, send, receive,
             datawaiting;
FROM ScrollMessages IMPORT
   (* const*) SizeOfLineInfoHeader,
   (* type *) ScrollInstruction, ReturnInstruction, LineInformation,
              LineInfoPntr, ScrollInstructionPacket, ScrollKey;

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

VAR
   td:                    DisplayDataType;
   LastPosDist:           DistDataType;
   LastRefDist:           DistDataType;
   LastTypeDist:          DistDataType;
   NumbDisplayScreens:    CARDINAL;
   j:                     DisplayType;
   Dummy:		  BOOLEAN ;
   OptionLabel:           ARRAY[0..25] OF CHAR;

PROCEDURE InitializeData;
VAR T		: StrAny;
    dummy	: CARDINAL;
    I, K	: CARDINAL ;
    DefaultRef	: StrAny ;
    ResC:   ResCollectionType;
    bd:     BOOLEAN;

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

BEGIN
   CurrentDisplay := None;

   WITH DisplayData[Variable] DO
       DispBefore := 2;
       DispAfter  := 2;
       UnitID     := 1; (* default is always lines *)
       ByPos := FALSE; (* temp line during transition *)
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
      (* MaxDistIDSize := 10; *)
      END;
   END;

   WITH DisplayData[KWIC] DO
      KWICDispOrg := DispNatural;
      ShowText := TRUE;
      DisplayBar := TRUE ;   (* m.s. *)
      HeadHiLite := TRUE ;   (* m.s. *)
      LineLength := 78;
      CitCentre := (LineLength DIV 2) + 8;
   END;

   LastPosDist := DisplayData[Distribution].DistData;
   WITH LastRefDist DO
      DistRefName := '';
      DistRefID := 0;
      Type := DistByRef;
      RefOrder := TRUE ; (* m.s - default order of references *)
   END;
   LastTypeDist := LastRefDist;
   LastTypeDist.Type := DistByType;

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

END InitializeData;

END DisplayDialog.
