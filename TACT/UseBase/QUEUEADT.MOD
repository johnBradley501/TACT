IMPLEMENTATION MODULE queueadt;

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

(* Modelled after version in "Software Development with Modula-2,
Gary A.Ford & Richard S. Wiener, Wiley Press 1986, pp. 249-50 *)

(* This module defines the implementation of the queue abstract
data type.  It assumes the type of data to be stored in the queue
are ADDRESS's.  Note that queue is an opaque type.  *)

(*
  Modifications:
  15 Aug 88 - L.Presutti
	- replaced call to "empty" in both "insert" and "remove" procs with
	inline check.
*)
	
FROM SYSTEM IMPORT ADDRESS;

(* FROM Storage IMPORT *)
FROM MemoryManagement IMPORT
 (* proc *) ALLOCATE, DEALLOCATE;

TYPE
  queueptr = POINTER TO queuenode;
  queuenode = RECORD
               contents : ADDRESS;
               next     : queueptr
              END;
  queue = POINTER TO RECORD
            front      : queueptr;
            rear       : queueptr
          END;

PROCEDURE queueerror;
BEGIN
  (* error handling procedure: recovery, message, abort, etc *)
END queueerror;

PROCEDURE makeempty(VAR q   : queue  (* in/out *) );
BEGIN
  destroy(q);
  NEW(q);
  q^.front := NIL;
  q^.rear := NIL
END makeempty;

PROCEDURE empty(q: queue (* in *) ): BOOLEAN;
BEGIN
  RETURN q^.front = NIL
END empty;

PROCEDURE insert(VAR q   : queue   (* in/out *);
                     item: ADDRESS (* in     *));
VAR newnode : queueptr;
BEGIN
   NEW (newnode );
   newnode^.contents := item;
   newnode^.next := NIL;
   IF q^.front = NIL THEN
      q^.front := newnode
   ELSE
      q^.rear^.next := newnode
   END;
   q^.rear := newnode
END insert;

PROCEDURE remove(VAR q   : queue   (* in/out *);
                 VAR item: ADDRESS (* out    *));
VAR oldnode : queueptr;
BEGIN
   IF q^.front <> NIL (* NOT empty(q) *) THEN
      oldnode := q^.front;
      item := q^.front^.contents;
      q^.front := q^.front^.next;
      IF q^.front = NIL THEN q^.rear := NIL END;
      DISPOSE(oldnode)
   ELSE
      queueerror
   END
END remove;

PROCEDURE define(VAR q   : queue   (* out    *));
BEGIN
   q := NIL
END define;

PROCEDURE destroy(VAR q  : queue   (* in/out *));
VAR node : queueptr;
BEGIN
   IF q <> NIL THEN
      node := q^.front;
      WHILE node <> NIL DO
         q^.front := node^.next;
         DISPOSE(node);
         node := q^.front
      END;
      DISPOSE(q);
      q := NIL
   END
END destroy;

END queueadt.
