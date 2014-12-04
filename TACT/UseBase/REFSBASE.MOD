IMPLEMENTATION MODULE RefsBase;

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

IMPORT Str ;
FROM Translations IMPORT OutProc;
FROM WordBase IMPORT
  (* Procs *) SortToIntWord;
FROM GlobalDefs IMPORT StrAny;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteLongInt, SWriteChar;

PROCEDURE DisplayRefNameList(Output: OutProc);
VAR   i:   CARDINAL;
      MP:  CARDINAL;
      M:   StrAny;
      T:   StrAny;
BEGIN
     IF NOT Output('DisplayRefNameList Begins:') THEN RETURN END;

     MP := 0;
     SWriteString(M,MP,'NumbOfRefNames: ',0);
     SWriteCard(M,MP,NumbOfRefNames,0);
     IF NOT Output(M) THEN RETURN END;

     FOR i := 1 TO NumbOfRefNames DO
        MP := 0;
        SWriteCard(M,MP,i,5);
        SWriteString(M,MP,',ID:',0);
        SWriteInt(M,MP,RefsNameListPntr^[i]^.ID,4);
        SWriteString(M,MP,',Pref:',0);
        SWriteCard(M,MP,ORD(RefsNameListPntr^[i]^.Pref),0);
        SWriteString(M,MP,',Name:',0);
        SortToIntWord(RefsNameListPntr^[i]^.Name,T);
        SWriteString(M,MP,T,0);
        IF NOT Output(M) THEN RETURN END;
     END;
END DisplayRefNameList;

PROCEDURE LookupRefName(Name: ARRAY OF CHAR (*sortable form*);
                    VAR Location:   CARDINAL):   BOOLEAN;
VAR
   UIdx, LIdx, IIdx:  CARDINAL;
   Done:   BOOLEAN;
   ICmp:   INTEGER;
BEGIN
   UIdx := NumbOfRefNames;
   LIdx := 1;
   Done := FALSE;
   REPEAT
      IF UIdx < LIdx THEN 
          Location := UIdx;
          RETURN FALSE;
      ELSE
         IIdx := (LIdx+UIdx) DIV 2;
         ICmp := Str.Compare(Name,RefsNameListPntr^[IIdx]^.Name);
         IF ICmp < 0 THEN
            UIdx := IIdx-1
         ELSIF ICmp > 0 THEN
            LIdx := IIdx+1
         ELSE
            Done := TRUE; 
         END;
      END
   UNTIL Done;
   Location := IIdx;
   RETURN TRUE;
END LookupRefName;

PROCEDURE GetNameFromID(ID:   INTEGER;
                    VAR Name: ARRAY OF CHAR (*sortable form*);
                    VAR Idx:  CARDINAL): BOOLEAN;
VAR Done: BOOLEAN;
    i:    CARDINAL;
BEGIN
   FOR i := 1 TO NumbOfRefNames DO
      IF (ABS(RefsNameListPntr^[i]^.ID) = ABS(ID)) AND
         (RefsNameListPntr^[i]^.Pref = 0C) THEN
         Str.Copy( Name, RefsNameListPntr^[i]^.Name );
         Idx := i;
         RETURN TRUE
      END;
   END;
   RETURN FALSE;
END GetNameFromID;

END RefsBase.
