IMPLEMENTATION MODULE TACTProcesses;
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


(* Modelled after version in "Software Development with Modula-2,
Gary A.Ford & Richard S. Wiener, Wiley Press 1986, pp.295-96

We didn't use the Processes Module provided with Logitech's
Modula-2 because there is no TERMINATE process in it.  *)

(* This module provides a process synchronization abstraction
based on general (non-binary) semaphores.  It also provdes
additional capabilities to support various process communication
abstractions.   *)

FROM SYSTEM IMPORT
  (* type    *)  ADDRESS, PROCESS,
  (* proc    *)  TSIZE, NEWPROCESS, TRANSFER;

IMPORT Utils ; (*was System/RTSMain in Logitech 2.0*)

(* FROM KeyBase IMPORT KeyPressed ; *)
(* FROM IO IMPORT KeyPressed; *)

(* FROM Storage IMPORT *)
FROM MemoryManagement IMPORT
  (* proc    *)  ALLOCATE, DEALLOCATE;

FROM queueadt IMPORT
  (* type    *)  queue,
  (* proc    *)  makeempty, empty, insert, remove, define, destroy;


TYPE
(*DoRead           : SIGNAL;  *)

(* kludge change to allow new JPI compiler to work!!   j.b. *)
(*SIGNAL    = POINTER TO semaphore; *)
  semaphore = RECORD
                 value:    CARDINAL;
                 procs:    queue
              END;
  processid = POINTER TO TACTProcessInfo;

  TACTProcessInfo = RECORD
      WSSize:    CARDINAL;
      WS:        ADDRESS;
      M2Proc:    PROCESS;
  END;

  WSrecord = RECORD
     AllocSize:     CARDINAL;
     M2ProcessWS:   BYTE; (* actually, will be of arbitrary size j.b. *)
  END;

VAR
   readyqueue       : queue;
   activeprocesses  : CARDINAL;
   terminatedprocess: processid;

PROCEDURE deadlockhandler;
VAR
   HoldMsg:    ARRAY[0..40] OF CHAR;
BEGIN
   HoldMsg := 'Deadlock has occurred';
   Utils.Terminate(Utils.Halt);
END deadlockhandler;

PROCEDURE DisposeOfTerminatedProcess;
BEGIN
   DEALLOCATE(terminatedprocess^.WS, terminatedprocess^.WSSize);
   DISPOSE(terminatedprocess);
   terminatedprocess := NIL;
END DisposeOfTerminatedProcess;

PROCEDURE Init(VAR s: SIGNAL (* out *) );
BEGIN
   NEW(s);
   s^.value := 0;
   define(s^.procs);
   makeempty(s^.procs)
END Init;

PROCEDURE Dispose(VAR s: SIGNAL (* out *) );
BEGIN
   destroy(s^.procs);
   DISPOSE(s);
END Dispose;

PROCEDURE SEND(VAR s: SIGNAL (* in/out *));
VAR
   prevprocess : processid;


BEGIN
   IF NOT empty(s^.procs) (* a process is waiting *) THEN
      insert(readyqueue, currentprocess);
      prevprocess := currentprocess;
      remove(s^.procs, currentprocess);
      TRANSFER(prevprocess^.M2Proc, currentprocess^.M2Proc);
   ELSE
      INC(s^.value);
      IF NOT empty(readyqueue) THEN
         insert(readyqueue, currentprocess);
         prevprocess := currentprocess;
         remove(readyqueue, currentprocess);
         TRANSFER(prevprocess^.M2Proc, currentprocess^.M2Proc);
      END
   END;
   IF terminatedprocess <> NIL THEN DisposeOfTerminatedProcess END;
END SEND;

PROCEDURE YIELD;
VAR
   prevprocess : processid;
BEGIN
   IF NOT empty(readyqueue) THEN
      insert(readyqueue, currentprocess);
      prevprocess := currentprocess;
      remove(readyqueue, currentprocess);
      TRANSFER(prevprocess^.M2Proc, currentprocess^.M2Proc);
   END;
   IF terminatedprocess <> NIL THEN DisposeOfTerminatedProcess END;
END YIELD;

PROCEDURE WAIT(VAR s: SIGNAL (* in/out *));
VAR
   prevprocess : processid;

BEGIN
(* IF KeyPressed() THEN
      SEND(DoRead)
   END; *)
   IF s^.value > 0 THEN
      DEC (s^.value)
   ELSE
      IF empty(readyqueue) THEN
          IF NOT empty(DoRead^.procs) THEN
             SEND(DoRead)
          ELSE
             deadlockhandler
          END
      END;
      insert(s^.procs, currentprocess );
      prevprocess := currentprocess;
      remove (readyqueue, currentprocess );
      TRANSFER(prevprocess^.M2Proc, currentprocess^.M2Proc)
   END;
   IF terminatedprocess <> NIL THEN DisposeOfTerminatedProcess END;
END WAIT;

PROCEDURE Awaited(s: SIGNAL  (* in *)): BOOLEAN;
BEGIN
   RETURN NOT empty(s^.procs )
END Awaited;

PROCEDURE StartProcess(p:      PROC;    (* in *)
                       wssize: CARDINAL (* in *));
VAR
   workspace   :   ADDRESS;
   prevprocess :   processid;
BEGIN
   ALLOCATE(workspace, wssize);
   INC(activeprocesses);
   insert(readyqueue, currentprocess );
   prevprocess := currentprocess;
   NEW(currentprocess);
   WITH currentprocess^ DO
      WS := workspace;
      WSSize := wssize;
      NEWPROCESS( p, workspace,wssize, M2Proc );
      TRANSFER(prevprocess^.M2Proc, M2Proc);
   END;
END StartProcess;

PROCEDURE Terminate;
VAR
   prevprocess : processid;
BEGIN
   IF terminatedprocess <> NIL THEN DisposeOfTerminatedProcess END;
   terminatedprocess := currentprocess;
   DEC(activeprocesses);
   IF (activeprocesses = 0) AND NOT empty(DoRead^.procs ) THEN
      remove(DoRead^.procs, prevprocess);
      insert(readyqueue, prevprocess)
   END;
   IF NOT empty(readyqueue) THEN
      prevprocess := currentprocess;
      remove(readyqueue, currentprocess);
      TRANSFER(prevprocess^.M2Proc, currentprocess^.M2Proc)
   ELSE
      deadlockhandler
   END
END Terminate;

PROCEDURE equal(p1:  processid   (* in *);
                p2:  processid   (* in *)): BOOLEAN;
BEGIN
   RETURN p1 = p2
END equal;

PROCEDURE BeginTACTProcesses;
BEGIN
   Init (DoRead );
   define (readyqueue);
   makeempty ( readyqueue );
   nullprocess := NIL;
   terminatedprocess := NIL;
   NEW( currentprocess );
   activeprocesses := 0;
END BeginTACTProcesses;

END TACTProcesses.
