IMPLEMENTATION MODULE channels;
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
Gary A.Ford & Richard S. Wiener, Wiley Press 1986, p. 307 *)

FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM SYSTEM IMPORT
  (* type *) BYTE,
  (* proc *) TSIZE;

FROM MemoryManagement IMPORT
  (* proc *) ALLOCATE, DEALLOCATE;

IMPORT TACTProcesses;

CONST
  channelsize = 16;
  channelmax = channelsize - 1;

TYPE
  channel = POINTER TO buffer;
  buffer  = RECORD
             amtsent  : CARDINAL;
             contents : ARRAY [0..channelmax] OF BYTE;
             sender   : TACTProcesses.processid;
             receiver : TACTProcesses.processid;
             idle     : TACTProcesses.SIGNAL;
             busy     : TACTProcesses.SIGNAL
            END;
  errors = ( senderconflict, receiverconflict,
             senderror, receiveerror, datawaitingerror );

PROCEDURE error(code: errors (* in *) );
BEGIN
   CASE code OF
     senderconflict :   ProgramErrorAndHalt( 'sender already attached' ) |
     receiverconflict:  ProgramErrorAndHalt( 'receiver already attached') |
     senderror:         ProgramErrorAndHalt( 'cannot send to this channel' ) |
     receiveerror:      ProgramErrorAndHalt( 'cannot receive from this channel' ) |
     datawaitingerror:  ProgramErrorAndHalt( 'cannot check data status');
   END;
END error;

PROCEDURE open
 ( VAR chan        : channel                  (* out    *) );
BEGIN
   NEW ( chan );
   chan^.sender := TACTProcesses.nullprocess;
   chan^.receiver := TACTProcesses.nullprocess;
   TACTProcesses.Init( chan^.idle );
   TACTProcesses.Init( chan^.busy );
   TACTProcesses.SEND (chan^.idle );
   chan^.amtsent  := 0;
END open;

PROCEDURE close
 ( VAR chan        : channel                  (* in/out *) );
BEGIN
   WHILE TACTProcesses.Awaited(chan^.idle) DO
      TACTProcesses.SEND(chan^.idle)
   END;
   WHILE TACTProcesses.Awaited(chan^.busy) DO
      TACTProcesses.SEND(chan^.busy)
   END;
   TACTProcesses.Dispose(chan^.idle);
   TACTProcesses.Dispose(chan^.busy);
   DISPOSE ( chan );
   chan := NIL;
END close;

PROCEDURE attachsender
 ( VAR chan        : channel                  (* in/out *) );
BEGIN
   IF TACTProcesses.equal ( chan^.sender, TACTProcesses.nullprocess )
      THEN chan^.sender := TACTProcesses.currentprocess
      ELSE error(senderconflict)
   END
END attachsender;

PROCEDURE attachreceiver
 ( VAR chan        : channel                  (* in/out *) );
BEGIN
   IF TACTProcesses.equal (chan^.receiver, TACTProcesses.nullprocess )
      THEN chan^.receiver := TACTProcesses.currentprocess
      ELSE error(receiverconflict)
   END
END attachreceiver;

PROCEDURE send
 ( VAR chan        : channel                  (* in/out *);
       message     : ARRAY OF BYTE            (* in     *) );
VAR pos:  CARDINAL;
BEGIN
   IF TACTProcesses.equal (chan^.sender, TACTProcesses.currentprocess )
      THEN TACTProcesses.WAIT (chan^.idle );
         FOR pos := 0 TO HIGH ( message ) DO
             chan^.contents[ pos ] := message[ pos ]
         END;
         chan^.amtsent := chan^.amtsent + 1;
         TACTProcesses.SEND ( chan^.busy )
      ELSE error (senderror )
    END
END send;

PROCEDURE receive
 ( VAR chan        : channel                  (* in/out *);
   VAR message     : ARRAY OF BYTE            (* out    *) );
VAR pos:   CARDINAL;
BEGIN
   IF TACTProcesses.equal (chan^.receiver, TACTProcesses.currentprocess )
     THEN TACTProcesses.WAIT (chan^.busy );
        chan^.amtsent := chan^.amtsent - 1;
        FOR pos := 0 TO HIGH (message ) DO
            message[ pos ] := chan^.contents[ pos ]
        END;
        TACTProcesses.SEND (chan^.idle )
     ELSE error ( receiveerror )
   END;
END receive;

PROCEDURE datawaiting
 ( VAR chan        : channel                  (* in *) ): BOOLEAN;
BEGIN
   IF TACTProcesses.equal (chan^.receiver, TACTProcesses.currentprocess ) THEN
       RETURN 0 < chan^.amtsent
   ELSE error (datawaitingerror)
   END
END datawaiting;

END channels.
