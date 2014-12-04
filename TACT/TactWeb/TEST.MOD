MODULE Test;
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

IMPORT FIO;
VAR
   sz:  CARDINAL;
   buf: ARRAY[0..400] OF CHAR;
BEGIN
   sz := FIO.RdBin(FIO.StandardInput, buf, 400);
   FIO.WrStr(FIO.StandardOutput,"Number of characters: ");
   FIO.WrCard(FIO.StandardOutput, sz, 0);
END Test.