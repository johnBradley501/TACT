IMPLEMENTATION MODULE TokenDataSource ;

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

(* FROM VirtualMemory IMPORT
  (* Var = Const *) VirtNil ;
*)
BEGIN
   RecordNumber := VAL( LONGCARD, 0 ) ;
   TokenNumber  := VAL( LONGCARD, 0 ) ;
(* Following line changed (j.b.)
   TypeNumber   := VAL( LONGINT, -1 ) ; (* First one (to Header) doesn't count *)
*)
   TypeNumber   := VAL( LONGCARD, 0 ) ;
(*m.s.   HeadWordHeader := VirtNil ; *)
   TokenListStart := NIL ;
   CurrTokenArray := NIL ;
(*m.s.   VTokenListStart := VirtNil ;
   VCurrTokenArray := VirtNil ;
*)
   CurrTokenPos   := 0 ;

   BeginToken := 0 ;
   BeginOccur := 0 ;
   BeginType  := 0 ;
   BeginText  := 0 ;
   BeginIndex := 0 ;
   EndTextRec := 0 ;
   EndTextIdx := 0 ;
   EndTypeRec := 0 ;
   EndTypeIdx := 0 ;
   EndTokenRec := 0 ;
   EndTokenIdx := 0 ;
   NoTypes     := 0 ;
   BeginStrRec := 0 ;
   NoStrRecs   := 0 ;
   BeginStr := 0 ;
   EndStr   := 0 ;
   BeginLog := 0 ;
   EndLog   := 0 ;
END TokenDataSource .
