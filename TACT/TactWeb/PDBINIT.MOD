IMPLEMENTATION MODULE PDBInit;
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


IMPORT ASCII, Str, FIO, Lib;
FROM SYSTEM IMPORT ADR;
FROM GlobalDefs IMPORT StrAny, TDBExtension;
FROM Utils IMPORT StandardizeFileName, RemoveExtension;
FROM HyperDataModel IMPORT
  (* const *) HyperLength, ThisPDBVersion,
  (* Types *) HyperData,
  (* Vars  *) PDBIDModel;
FROM VirtMem IMPORT
  (* types *) VirtAddr, VirtMemFile,
  (* vars  *) NILVirt, PDBFile,
  (* procs *) CopyFromVirtMem, CopyToVirtMem, VMAccess, VMModify, VMMarkChanged,
              VMRelease, GetSpace, FreeSpace, RealToPool, VirtToPool,
              EqualVirts, FreePool, WriteAllVirts, OpenVirtFile;
FROM HyperBase IMPORT  (* access to TDB *)
  (* TYPE *) HyperFile,
  (* PROC *) CloseHyperFile;
FROM MemoryManagement IMPORT RealStoragePntr;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage;
FROM TDBInit IMPORT
    (* procs *) VerifyTDBFile, InitializeFromTDB;
FROM MemTACTList IMPORT InitializeCatList;
FROM TACTDataServices IMPORT VirtToTACTList, TACTListToVirt;

FROM DBData IMPORT
     PDBFileName, PDBOpen, MainCatList, SavePoolInfo, InitPool,
     TDBFile, TDBFileName, TDBYear, TDBMonth, TDBDay, TDBDataInitialized;

(*<Dbg
FROM Trace IMPORT
  (* Procs *) TWriteLn, TWriteChar, TWriteString, TWriteInt, TWriteCard,
              TWriteAddr, TWriteStrHex, CloseTFile;
Dbg>*)

  CONST
(*RES OLD MSG 147
  Please give the name of a different .TDB file below.
*)
      ToTryMsg = (*RES REM INS*) 147;

(*RES OLD MSG 148
UseBase cannot use "%0" as a .TDB or .COR file.
*)
      CannotUseMsg = (*RES REM INS*) 148;

  TYPE
    PDBHeader = RECORD
       TYear      : CARDINAL ;
       TMonth     : CARDINAL ;
       TDay       : CARDINAL ;
       CListLoc   : VirtAddr ;
       PoolData   : VirtAddr ;
       OtherItems : VirtAddr ;
       TFileName  : ARRAY [0..99] OF CHAR;
    END;

PROCEDURE OpenBase(FileName: ARRAY OF CHAR): BOOLEAN;
VAR ErrMsg:  ARRAY[0..100] OF CHAR;
BEGIN
  IF NOT OpenVirtFile(FileName, PDBFile, ErrMsg, (*tmpfile=*) FALSE) THEN
     (*RES OLD MSG 151
     UseBase cannot open .GIX file %0: %1.
     *)
     MsgString(FileName,0);
     MsgString(ErrMsg,1);
     PutResError( (*RES REM INS*) 151 );
     RETURN FALSE
  END;
  Str.Copy(PDBFileName,FileName);
  RETURN TRUE
END OpenBase;

PROCEDURE OpenExistingPDB(VAR FileName: ARRAY OF CHAR): BOOLEAN;
  VAR
    MsgLine1,
    MsgLine2,
    MsgLine3:     StrAny;
    PDBPntr:      RealStoragePntr;
    loop:         BOOLEAN;
    NameChanged:  BOOLEAN;
    dummy:        BOOLEAN;
    ErrMsg:       StrAny;
    Yr, Mn, Dy:   CARDINAL;
    HeaderLoc:    VirtAddr;
    HeaderPtr:    POINTER TO PDBHeader;
    tFile:        HyperFile; (* for TDB *)
BEGIN
  IF NOT OpenBase(FileName) THEN RETURN FALSE END;

  HeaderLoc.PageNo := 0; HeaderLoc.Offset := 2;
  HeaderPtr := VMAccess(HeaderLoc);

  SavePoolInfo(HeaderPtr^.PoolData);

  loop := TRUE;
  NameChanged := FALSE;
  WHILE loop DO
    IF NOT VerifyTDBFile(HeaderPtr^.TFileName,TDBExtension,
       tFile, Yr, Mn, Dy) THEN
       MsgString( HeaderPtr^.TFileName, 0);
       PutResError( CannotUseMsg);
       RETURN FALSE;
    ELSIF (Yr <> HeaderPtr^.TYear) OR
    (Mn <> HeaderPtr^.TMonth) OR
    (Dy <> HeaderPtr^.TDay) THEN
       (*RES OLD MSG 154
       Your .TDB file ("%0") does not match your .GIX file.
       *)
       MsgString( HeaderPtr^.TFileName, 0);
       PutResError( (*RES REM INS*) 154);
       RETURN FALSE;
    ELSE
       Str.Copy(TDBFileName,HeaderPtr^.TFileName);
       InitializeFromTDB(tFile);
       loop := FALSE
    END;
  END;
  VirtToTACTList(HeaderPtr^.CListLoc, MainCatList);
  VMRelease(HeaderLoc);
  PDBOpen := TRUE;
  RETURN TRUE;
END OpenExistingPDB;

END PDBInit.
