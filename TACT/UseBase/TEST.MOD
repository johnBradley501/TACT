MODULE Test;

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

IMPORT Graph, IO ;

VAR
  V : Graph.VideoConfig ;
  dummy : BOOLEAN ;
  x : CARDINAL ;
BEGIN
  Graph.InitGraph ;
  Graph.GetVideoConfig( V ) ;
  dummy := Graph.SetVideoMode(Graph._MRESNOCOLOR) ;
  x := Graph.SelectPalette(0);
(*  Graph.Arc(0,0,100,100,80,20,80,60,2) ; *)
  Graph.Line(10,10,70,10,2);
  Graph.Line(40,10,40,70,2);
  Graph.Line(115,10,90,70,2);
  Graph.Line(115,10,140,70,2);
  Graph.Line(102,40,128,40,2);
  Graph.Line(150,10,200,10,2);
  Graph.Line(150,10,150,70,2);
  Graph.Line(150,70,200,70,2);
  Graph.Line(220,10,280,10,2);
  Graph.Line(250,10,250,70,2);
  x := IO.RdCard() ;
END Test.