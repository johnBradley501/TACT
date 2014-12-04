IMPLEMENTATION MODULE TypeBase;
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


IMPORT Lib, BitOps, WordBase ;
FROM SYSTEM IMPORT ADR;
FROM HyperDataModel IMPORT
  (* Types *) HRecPntr, HyperData, HTypePntr, TDBTypePntr, TDBTypeData,
  (* Procs *) TDBTypeCompare ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM HyperBase IMPORT
  (* PROC *)  GetBaseHyper, ReleaseBaseHyper;
FROM MemoryManagement IMPORT ALLOCATE, DEALLOCATE, RealStoragePntr;
FROM DBData IMPORT
    (* vars  *) TDBFile,
    (* vars  *) BeginType, EndTypeRec, EndTypeIdx, LastAlphChar;


TYPE
   HTypePointer = RECORD
                 DataPntr: TDBTypePntr;
                 InRec:    RealStoragePntr
                 END;
   HTypePointerPointer = POINTER TO HTypePointer;

  PROCEDURE GetType(Type : HRecPntr; VAR Handle : HTypeHandle);
    VAR
      HP:       RealStoragePntr;
      T:        HTypePointerPointer;
  BEGIN
    GetBaseHyper(Type.Rec,HP,TDBFile);
    IF Type.Idx > HP^.HRecord.NoDataPtrsUsed THEN
         ProgramErrorAndHalt('Index too high in GetType')
    END;
    NEW(T);
    T^.InRec := HP;
    T^.DataPntr :=  ADR(HP^.HRecord.TextData[HP^.HRecord.DataPntr[Type.Idx]]);
    Handle := HTypeHandle(T);
  END GetType;

  PROCEDURE FreeTypeHandle(VAR Handle: HTypeHandle);
  VAR
      T:        HTypePointerPointer;
  BEGIN
     T := HTypePointerPointer(Handle);
     ReleaseBaseHyper(TDBFile,T^.InRec);
     DISPOSE(T);
     Handle := NIL;
  END FreeTypeHandle;

  PROCEDURE GetNextType(Old : HRecPntr; VAR New : HRecPntr): BOOLEAN;
    VAR
      HP:       RealStoragePntr;
  BEGIN
    GetBaseHyper(Old.Rec,HP,TDBFile);
    New.Rec := Old.Rec;
    New.Idx := Old.Idx+1;
    IF New.Idx > HP^.HRecord.NoDataPtrsUsed THEN
       IF HP^.HRecord.NextHRec = 0 THEN  RETURN FALSE  END ;
       New.Rec := BeginType + HP^.HRecord.NextHRec ;
       New.Idx := 1;
    END;
    ReleaseBaseHyper(TDBFile,HP);
    RETURN (New.Rec < EndTypeRec) OR
          ((New.Rec = EndTypeRec) AND (New.Idx < EndTypeIdx));
  END GetNextType;

  PROCEDURE GetPrevType(Old : HRecPntr; VAR New : HRecPntr): BOOLEAN;
    VAR
      HP:       RealStoragePntr;
  BEGIN
    IF (Old.Rec = BeginType) AND (Old.Idx <= 2) THEN RETURN FALSE END;

    IF Old.Idx = 1 THEN
       GetBaseHyper(Old.Rec,HP,TDBFile);
       New.Rec := BeginType + HP^.HRecord.PrevHRec ;
       ReleaseBaseHyper(TDBFile,HP);
       (* now find out the number of pointers used on prev HRec *)
       GetBaseHyper(New.Rec,HP,TDBFile);
       New.Idx := HP^.HRecord.NoDataPtrsUsed ;
       ReleaseBaseHyper(TDBFile,HP);
    ELSE
       New.Rec := Old.Rec;
       New.Idx := Old.Idx - 1
    END;
    RETURN TRUE;
  END GetPrevType;

  PROCEDURE FindType(Word:    ARRAY OF CHAR;
                 VAR Type:    HRecPntr;
                 VAR Handle:  HTypeHandle): BOOLEAN;
    VAR
      HP:             RealStoragePntr;
      TRec:           CARDINAL;
      LPtr:           TDBTypePntr;
      HPtr:           TDBTypePntr;
      IPtr:           TDBTypePntr;
      LIdx:           CARDINAL;
      UIdx:           CARDINAL;
      IIdx:           CARDINAL;
      FindTypeResult: BOOLEAN;
      Done:           BOOLEAN;
      ICmp:           INTEGER;
      T:              HTypePointerPointer;
      FindWord:	      TDBTypeData;
      FindWordPtr:    TDBTypePntr;

  BEGIN
    IF ORD(Word[0]) > 2 THEN
	TRec := CARDINAL( ( ( LONGCARD(ORD(Word[0])-2) * LONGCARD(EndTypeRec-BeginType) * 10) DIV
	          LONGCARD(ORD(LastAlphChar)-2) + 5) DIV 10) + BeginType;
    ELSE
	(* Handle pathalogical case of markup codes not made of alpha chars!!*)
	TRec := BeginType ;
    END ;
(*    TRec := BeginType + (((ORD(Word[0])-2) * (EndTypeRec-BeginType) * 10) DIV
                        (ORD(LastAlphChar)-2) + 5) DIV 10; *)
    IF TRec < BeginType THEN
      TRec := BeginType
    ELSIF TRec > EndTypeRec THEN
      TRec := EndTypeRec
    END;

    GetBaseHyper(TRec,HP,TDBFile);

    (* its not valid to just jump in at any type record -- must have pntr data!*)
    WHILE HP^.HRecord.NoDataPtrsUsed = 0 DO
	ReleaseBaseHyper(TDBFile,HP);
	INC(TRec);
	GetBaseHyper(TRec,HP,TDBFile);
    END ;

    WITH HP^.HRecord DO
       LPtr := ADR(TextData[DataPntr[1]]);
       HPtr := ADR(TextData[DataPntr[ NoDataPtrsUsed ]]);
    END;

    (* NEED TO CONVERT WORD TO PACKED FORMAT AND USE PackedStr for comparison *)
    FindWordPtr := ADR( FindWord ) ;
    BitOps.Pack( Word, FindWordPtr^.PackedWord, WordBase.SortNoBitsPerChar ) ;

    IF TDBTypeCompare( FindWordPtr, LPtr ) < 0 THEN
       REPEAT
          TRec := BeginType + HP^.HRecord.PrevHRec ;
          ReleaseBaseHyper(TDBFile,HP);
          GetBaseHyper(TRec,HP,TDBFile);
          WITH HP^.HRecord DO
              LPtr := ADR(TextData[DataPntr[1]]);
              HPtr := ADR(TextData[DataPntr[NoDataPtrsUsed]]);
          END;
       UNTIL TDBTypeCompare( FindWordPtr, LPtr ) >= 0
    ELSE
       WHILE TDBTypeCompare( FindWordPtr, HPtr ) > 0 DO
          TRec := BeginType + HP^.HRecord.NextHRec ;
          ReleaseBaseHyper(TDBFile,HP);
          GetBaseHyper(TRec,HP,TDBFile);
          WITH HP^.HRecord DO
              LPtr := ADR(TextData[DataPntr[1]]);
              HPtr := ADR(TextData[DataPntr[NoDataPtrsUsed]]);
          END;
       END;
    END;

    Type.Rec := TRec;

    WITH HP^.HRecord DO
       UIdx := NoDataPtrsUsed ;
       LIdx := 1;
       Done := FALSE;
       REPEAT
          IF UIdx < LIdx THEN
              Done := TRUE;
              Type.Idx := UIdx;
              FindTypeResult := FALSE
          ELSE
             IIdx := (LIdx+UIdx) DIV 2;
             IPtr := ADR(TextData[DataPntr[IIdx]]);
             ICmp := TDBTypeCompare( FindWordPtr, IPtr );
             IF ICmp < 0 THEN
                UIdx := IIdx-1
             ELSIF ICmp > 0 THEN
                LIdx := IIdx+1
             ELSE
                Done := TRUE;
                FindTypeResult := TRUE;
                Type.Idx := IIdx;
             END;
          END
       UNTIL Done;
       NEW(T);
       T^.DataPntr := IPtr;
    END;
    T^.InRec := HP;
    Handle := HTypeHandle(T);
    RETURN FindTypeResult
  END FindType;

END TypeBase.