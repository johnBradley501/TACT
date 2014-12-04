IMPLEMENTATION MODULE ResCollection;
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


FROM SYSTEM IMPORT BYTE,ADR,ADDRESS;
IMPORT Lib ;
FROM Utils IMPORT ALLOCATE,DEALLOCATE;
FROM ResBase IMPORT
   (*type*) FilePos,
   (*var*)  ResourceOpen, ResourceFile, NullPos,
   (*proc*) OpenResourceFile, CloseResourceFile,
            ReadResourceBase, ReadResRecord, ReadResString;


PROCEDURE InitializeCollection(VAR ResC: ResCollectionType);
BEGIN
   ALLOCATE(ResC,SIZE(ResCollectionData));
   ResC^.CurPos := 0;
   ResC^.MaxSize := MaxCollectionSize;
   ALLOCATE(ResC^.Data,MaxCollectionSize);
END InitializeCollection;

PROCEDURE GetCollection(VAR ResC: ResCollectionType;
                            Loc:  FilePos): BOOLEAN;
VAR  size:    CARDINAL;
BEGIN
    ALLOCATE(ResC,SIZE(ResCollectionData));
    ResC^.MaxSize := 0;
    ResC^.Data := NIL;
    IF NOT ReadResourceBase(0,Loc,ResC^.Data,ResC^.MaxSize) THEN
       RETURN FALSE
    END;
    ResC^.CurPos := 0;
    RETURN TRUE
END GetCollection;

PROCEDURE NextColItem(VAR ResC: ResCollectionType;
                      VAR ItemData: ARRAY OF BYTE;
                      VAR Size: CARDINAL): BOOLEAN;
VAR   givenlen:    CARDINAL;
      sentlen:     CARDINAL;
      datap:       POINTER TO ARRAY[0..10] OF BYTE;
BEGIN
    WITH ResC^ DO
       IF CurPos >= MaxSize THEN RETURN FALSE END;
       givenlen := ORD(Data^[CurPos]);
       datap := ADR(Data^[CurPos+1]);
       IF givenlen > HIGH(ItemData) THEN sentlen := HIGH(ItemData)+1
                                    ELSE sentlen := givenlen END;
       Lib.Move( datap, ADR(ItemData), sentlen);
       CurPos := CurPos + givenlen + 2
    END;
    Size := sentlen;
    RETURN TRUE
END NextColItem;

PROCEDURE PrevColItem(VAR ResC: ResCollectionType;
                      VAR ItemData: ARRAY OF BYTE;
                      VAR Size: CARDINAL): BOOLEAN;
VAR   givenlen:    CARDINAL;
      sentlen:     CARDINAL;
      front:       CARDINAL;
BEGIN
    WITH ResC^ DO
       IF CurPos = 0 THEN RETURN FALSE END;

(* Note: CurPos points at beginning of **next** item: first move it to front of
       current item   j.b. *)

       DEC(CurPos);
       givenlen := ORD(Data^[CurPos]);
       IF CurPos <= givenlen + 1 THEN RETURN FALSE END;
       CurPos := CurPos - givenlen - 1;

(* Note: CurPos now points at front of **current** item    j.b. *)

       front := CurPos - 1;
       givenlen := ORD(Data^[front]);
       IF givenlen > HIGH(ItemData) THEN sentlen := HIGH(ItemData)+1
                                    ELSE sentlen := givenlen END;
       front := front - givenlen;

(* Note: front now points to front of **previous** item   j.b. *)

       Lib.Move( ADR(Data^[front]), ADR(ItemData), sentlen);
    END;
    Size := sentlen;
    RETURN TRUE
END PrevColItem;

PROCEDURE ReleaseCollection(VAR ResC: ResCollectionType);
BEGIN
   DEALLOCATE(ResC^.Data,ResC^.MaxSize);
   DEALLOCATE(ResC,SIZE(ResCollectionData));
   ResC := NIL
END ReleaseCollection;

END ResCollection.
