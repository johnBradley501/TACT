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

(*V1=Production *)
(*V2=SpaceCheck *)

(*<SpaceCheck
FROM CheckMemory IMPORT
  (* Procs *) MemSnapShot ;
SpaceCheck>*)

(* temporary, for debugging

FROM Windows IMPORT
  (* Procs *) PutMessage ;
*)
IMPORT Lib;
FROM DBFile IMPORT
  (* Procs *) StartDBFile, FinishDBFile ;
FROM WordProcessing IMPORT
  (* Procs *) WritePntrData ;
FROM ProcTextSource IMPORT
  (* Procs *) ProcessText ;
FROM RunPan IMPORT
  (* Procs *) SetupRunWindows, CleanupRunWindows, PutRunStatus ;
(* -- only needed when debugging ---  **LP**
FROM DumpLists IMPORT
  (* Procs *) DumpStructLists ;
*)
FROM VirtualMemory IMPORT
  (* Procs *) InitVirtualMemory, EndVirtualMemory ;
FROM  VirtHash IMPORT InitVirtHash;
FROM GlobalDefs IMPORT StrAny ;

VAR
   Message   : StrAny ;
   MsgPos    : CARDINAL ;
   ErrorMsg  : StrAny ;

PROCEDURE Run ;
  BEGIN
(*
     DumpStructLists ;  (* just temporary here while debugging!! *)
     PutMessage( 'Dump Structured lists completed.' ) ;
*)
     (*<SpaceCheck MemSnapShot( 'Run - Start ' ) ; SpaceCheck>*)
    
     SetupRunWindows ;
    
     (*<SpaceCheck MemSnapShot( 'Run - after "SetupRunWindows" ' ) ; SpaceCheck>*)
     (*RES OLD MSG 99
     Now initializing .TDB file.
     *)
     PutRunStatus( (*RES REM INS*) 99 ) ;
     StartDBFile ;

     (*<SpaceCheck MemSnapShot( 'Run - after "StartDBFile" ' ) ; SpaceCheck>*)
     InitVirtualMemory ;
     InitVirtHash;
     (*<SpaceCheck MemSnapShot( 'Run - after "InitVirtualMemory" ' ) ; SpaceCheck>*)
     (*RES OLD MSG 100
     Now reading source text.
     *)
     PutRunStatus( (*RES REM INS*) 100 ) ;
     IF ProcessText() THEN
        WritePntrData ;
	Lib.SetReturnCode( 0 ) ;	(* if got this far then OK *)
     END ;
     (*<SpaceCheck MemSnapShot( 'Run - after "ProcessText" ' ) ; SpaceCheck>*)

     FinishDBFile ;
     (*<SpaceCheck MemSnapShot( 'Run - after "FinishDBFile" ' ) ; SpaceCheck>*)

     CleanupRunWindows ;
     (*<SpaceCheck MemSnapShot( 'Run - after "CleanupRunWindows" ' ) ; SpaceCheck>*)

     EndVirtualMemory ;
     (*<SpaceCheck MemSnapShot( 'Run - after "EndVirtualMemory" ' ) ; SpaceCheck>*)
  END Run ;

BEGIN
END RUNSource .

