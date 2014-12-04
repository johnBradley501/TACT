IMPLEMENTATION MODULE ParserSource;

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
(*V4=Dbg Debugging code *)
(*V5=NoDbg No Debugging code *)

FROM SYSTEM IMPORT ADDRESS;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResNumberArray IMPORT
  (* proc *) GetNumberArray, DisposeNumberArray;
FROM ResMessages IMPORT
   (*proc*)  MsgString, PutResError;
FROM ScannerSource IMPORT 
   (* type *) ItemDataType,
   (* proc *) Scanner;
(*<Dbg
FROM Trace IMPORT
(*vars *) DoTrace,
(*procs*) TWriteLn,TWriteChar,TWriteString,TWriteInt,TWriteCard,TWriteAddr,
          TWriteStrHex,CloseTFile;
Dbg>*)
CONST
    StackSize = 100; (* parser stack size *)
    MaxStateDataSize = 8096; (* words *)
    MaxStatePntrSize = 1096; (* words *)
    MaxNames = 200;
    StatePntrResNo = 0; (* resource type NAR *)
    StateDataResNo = 1; (* resource type NAR *)

VAR
   LhdItemNumb, CurItemNumb:  CARDINAL;
   LhdItem, CurItem:          ItemDataType;
   State, OpNo:               CARDINAL;
   Stack:                     ARRAY [1..StackSize] OF CARDINAL;
   StackPntr:                 CARDINAL;
   StateData:                 POINTER TO ARRAY[1..MaxStateDataSize] OF CARDINAL;
   StatePntr:                 POINTER TO ARRAY[1..MaxStatePntrSize] OF CARDINAL;
   NumbStatePtrs:             CARDINAL;
   NumbStateDatas:            CARDINAL;

PROCEDURE InitializeParserTables;
BEGIN
   GetNumberArray(StatePntrResNo, StatePntr, NumbStatePtrs);
   GetNumberArray(StateDataResNo, StateData, NumbStateDatas);
END InitializeParserTables;

PROCEDURE Parser(start: BOOLEAN;
             VAR item:  ItemDataType): CARDINAL;

VAR
     i:            CARDINAL;
     looping:      BOOLEAN;
(*<Dbg   OldState:     CARDINAL; Dbg>*)

BEGIN
   IF start THEN
      LhdItemNumb := Scanner(TRUE, LhdItem);
      State := 1;
      OpNo := 1;
      StackPntr := 0;
      CurItem.IntStr := '';
      RETURN 0
   END;

(*<Dbg
   OldState := State;
   TWriteString('Parser begins: State:');
   TWriteCard(State,0);
   TWriteLn;
Dbg>*)

   LOOP
(*<Dbg
     IF OldState <> State THEN
        OldState := State;
        TWriteString('Parser State:');
        TWriteCard(State,0);
        TWriteString(',stack(Pos):');
        TWriteCard(Stack[StackPntr],0);
        TWriteChar('(',0);
        TWriteCard(StackPntr,0);
        TWriteString('),OpNo:');
        TWriteCard(OpNo,0);
        TWriteLn;
     END;
Dbg>*)
     CASE StateData^[OpNo] OF
     1: (* push operation *)
        INC(OpNo, 1);
        INC(StackPntr, 1);
        IF StackPntr > StackSize THEN
          (* *program error* parser stack overflow *)
          ProgramErrorAndHalt('Parser Stack Overflow')
        END;
        Stack[StackPntr] := StateData^[OpNo];
        INC(OpNo, 1)
   | 2: (* if item *)
        CurItem := LhdItem;
        CurItemNumb := LhdItemNumb;
        LhdItemNumb := Scanner(FALSE, LhdItem);
(*<Dbg
        TWriteString('Parser CurItemNumb:');
        TWriteCard(CurItemNumb,0);
        TWriteString(',LhdItemNumb:');
        TWriteCard(LhdItemNumb,0);
        TWriteLn;
Dbg>*)
        looping := TRUE;
        WHILE (StateData^[OpNo] = 2) AND looping DO
          IF StateData^[OpNo+1] = CurItemNumb THEN
            State := StateData^[OpNo+2];
            OpNo := StatePntr^[State];
            looping := FALSE;
          ELSE
            INC(OpNo, 3)
          END;
        END;
   | 3: (* output *)
        item := CurItem;
        i := StateData^[OpNo+1];
        INC(OpNo, 2);
(*<Dbg
        TWriteString('Parser Returns:');
        TWriteCard(i,0);
        TWriteLn;
Dbg>*)
        RETURN i
   | 4: (* lookahead *)
        INC(OpNo, 1);
        WHILE (StateData^[OpNo] <> 0) AND (StateData^[OpNo] <> LhdItemNumb) DO
          INC(OpNo, 1)
        END;
        IF StateData^[OpNo] = 0 THEN
          INC(OpNo, 2);
        ELSE
          INC(OpNo, 1);
          WHILE (StateData^[OpNo] <> 0) DO
            INC(OpNo, 1);
          END;
          State := StateData^[OpNo+1];
          OpNo := StatePntr^[State];
        END;
   | 5: (* pop *)
        DEC(StackPntr, StateData^[OpNo+1]);
        INC(OpNo, 2);
   | 6: (* if top *)
        IF Stack[StackPntr] = StateData^[OpNo+1] THEN
          State := StateData^[OpNo+2];
          OpNo := StatePntr^[State];
        ELSE
          INC(OpNo, 3)
        END;
   | 7: (* go to *)
        State := StateData^[OpNo+1];
        OpNo := StatePntr^[State];
   | 0: (* syntax error *)
        IF CurItemNumb = 0 THEN CurItem := LhdItem END;
        (*RES OLD MSG 161
        UseBase cannot understand problem occurring at :"%0"
        *)
        MsgString(CurItem.IntStr,0);
        PutResError( (*RES REM INS*) 161 );

(*      put file(sysprint) skip edit('valid item(s) are:')(a);
               i := StatePntr^(state);
               while(StateData^(i) ^= 0) do begin
                  select(StateData^(i));
                    when(2) begin
                       put file(sysprint) edit(
                       ItemNames(StateData^(i + 1)))(x(2),a);
                       i := i + 3;
                       end;
                    when(4) begin
                       i := i + 1;
                       while(StateData^(i) ^= 0) do begin
                         put file(sysprint) edit(
                         ItemNames(StateData^(i)))(x(2),a);
                         i := i + 1;
                         end;
                       i := i + 2;
                       end;
                    when(6) i := i + 3;
                    otherwise i := i + 2;
                    end;
                  end; *)
        item := CurItem;
        RETURN 10000
     ELSE (* Invalid StateTable Op *)
        ProgramErrorAndHalt('Invalid StateTable Op found in Parser');
     END; (* CASE *)
   END; (* LOOP *)
END Parser;

END ParserSource.
