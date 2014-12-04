IMPLEMENTATION MODULE TokenBase;
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


(*
   Date: ??/??/88
   By:   J.Bradley
   Last Modified:
   09/09/88 L.Presutti
	- GetPrevToken did not set New.Rec properly.
*)

FROM SYSTEM IMPORT ADR;
FROM HyperDataModel IMPORT
  (* Const *) HNoTokens, HyperLength,
  (* Types *) HyperData, HTokenData, HCompTokenData;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM HyperBase IMPORT
  (* TYPE *)  HRecPntr,
  (* PROC *)  GetBaseHyper, ReleaseBaseHyper;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE,
  (* types *) RealStoragePntr;
FROM DBData IMPORT
    (* vars  *) TDBFile,
    (* vars  *) BeginToken, EndTokenRec, EndTokenIdx, LastAlphChar;


TYPE
   HCompTokenPntr = POINTER TO HCompTokenData;
   HTokenPointer = RECORD
                   DataPntr: HCompTokenPntr;
                   InRec:    RealStoragePntr
                END;
   HTokenPointerPointer = POINTER TO HTokenPointer;

  PROCEDURE GetToken(Token:    HRecPntr;
                 VAR Handle:   HTokenHandle);
    VAR
      HP:       RealStoragePntr;
      T:        HTokenPointerPointer;
  BEGIN
    GetBaseHyper(Token.Rec,HP,TDBFile);
    IF Token.Idx >= HNoTokens THEN
         ProgramErrorAndHalt('Index too high in GetToken')
    END;
    NEW(T);
    T^.InRec := HP;
    T^.DataPntr :=  ADR(HP^.HRecord.TokenData[Token.Idx]);
    Handle := HTokenHandle(T);
  END GetToken;

  PROCEDURE FreeTokenHandle(VAR Handle: HTokenHandle);
  VAR
      T:        HTokenPointerPointer;
  BEGIN
     T := HTokenPointerPointer(Handle);
     ReleaseBaseHyper(TDBFile,T^.InRec);
     DISPOSE(T);
     Handle := NIL;
  END FreeTokenHandle;

  PROCEDURE GetNextToken(Old:  HRecPntr;
                    VAR New:  HRecPntr): BOOLEAN;
  BEGIN
    New.Rec := Old.Rec;
    New.Idx := Old.Idx+1;
    IF New.Idx >= HNoTokens THEN
       INC(New.Rec);
       New.Idx := 0;
    END;
    RETURN (New.Rec < EndTokenRec) OR
          ((New.Rec = EndTokenRec) AND (New.Idx <= EndTokenIdx));
  END GetNextToken;

  PROCEDURE GetPrevToken(Old:  HRecPntr;
                    VAR New:  HRecPntr): BOOLEAN;
  BEGIN
    IF Old.Idx = 0 THEN
       New.Rec := Old.Rec - 1;
       IF Old.Rec < BeginToken THEN RETURN FALSE END;
       New.Idx := HNoTokens-1;
    ELSE
       New.Rec := Old.Rec ;
       New.Idx := Old.Idx - 1
    END;
    RETURN (New.Rec >= BeginToken);
  END GetPrevToken;

PROCEDURE GetTokenNo(Token : HRecPntr; VAR Result : LONGINT); (* number is 1-origin *)
  BEGIN
     Result := VAL(LONGINT,Token.Rec - BeginToken) * VAL(LONGINT,HNoTokens) +
                   VAL(LONGINT,1 + Token.Idx);
  END GetTokenNo;

PROCEDURE GetTokenHRec( TokenNo : LONGINT; VAR Result : HRecPntr ) ;
  BEGIN
	DEC( TokenNo ) ; (* make zero base again *)
	Result.Idx := VAL(CARDINAL, TokenNo MOD HNoTokens) ;
	Result.Rec := VAL(CARDINAL, TokenNo DIV HNoTokens) + BeginToken ;
  END GetTokenHRec ;

PROCEDURE DecompressTokenInfo(Handle:   HTokenHandle;
                            VAR Result:   HTokenData);
  VAR
      T:        HTokenPointerPointer;
      temp:     CARDINAL;
  BEGIN
     T := HTokenPointerPointer(Handle);
     WITH T^.DataPntr^ DO
        Result.HRecNo  := HRecNo;
        Result.HRecPos := HRecPos;

        temp := T^.InRec^.HRecord.BaseTextPos + TOffset;
        Result.TRecNo  := temp DIV HyperLength + T^.InRec^.HRecord.BaseTextRec;
        Result.TRecPos := temp MOD HyperLength;

        temp := T^.InRec^.HRecord.BaseLogPos + ORD(LOffset);
        Result.LRecNo  := temp DIV 256 + T^.InRec^.HRecord.BaseLogRec;
        Result.LRecPos := CHR(temp MOD 256);
     END;
  END DecompressTokenInfo;
END TokenBase.
