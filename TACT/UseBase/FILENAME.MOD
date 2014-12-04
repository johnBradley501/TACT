IMPLEMENTATION MODULE FileNameBase;

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

(*--------------------------------------------------------------------------*)
(* Purpose:                                                                 *)
(*                                                                          *)
(* History:                                                                 *)
(*   4 Jan 90, Lidio Presutti                                               *)
(*     - added check for directory name in HandleFileNameField.             *)
(*                                                                          *)
(*--------------------------------------------------------------------------*)

IMPORT FIO, Str;
FROM FIO IMPORT (* Type *) FileAttr, directory ;
FROM ListData IMPORT
    DataItemPntr, MakeFileNameItem;
FROM TACTListModule IMPORT TACTList;
FROM StackWindows IMPORT
  (* types *) WindowType, WindowInfo;
FROM TACTListModule IMPORT
  (* types *) TACTList, TACTListType, TACTListItem,
  (* procs *) NewListItem, GetFirstItem, DiscardList,
              DisposeListItem, GetItemData, ReleaseItemHold;
FROM MemTACTList IMPORT
  (* procs *)  InitializeFileNameList, InsertListItem;

FROM Utils IMPORT UpcaseStr,ParseFilename, MakeFilename, AllowWildCards,
     StandardizeFileName, TrimBlanks ;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM SelectWindow IMPORT DoSelectWindow;
FROM ResMessages IMPORT
     MsgString, PutResError;
FROM VirtMem IMPORT VirtAddr, NILVirt, VMRelease, FreePool;
FROM MainLists IMPORT PoolNoForFileNameLists;

VAR
    FileNameSelectWind:    WindowInfo;

PROCEDURE BuildFileNameList(Pat:  ARRAY OF CHAR;
                        VAR List: TACTList): BOOLEAN;
VAR
   Rslt:   FIO.DirEntry;
   Pntr:   DataItemPntr;
   dummy:  BOOLEAN;
   OldIOcheck  : BOOLEAN ;
   VA:     VirtAddr;
BEGIN
   OldIOcheck := FIO.IOcheck ;
   FIO.IOcheck := FALSE ;
   IF NOT FIO.ReadFirstEntry(Pat,FIO.FileAttr{},Rslt) THEN
	FIO.IOcheck := OldIOcheck ;
	RETURN FALSE
   END;
   REPEAT
      MakeFileNameItem(Rslt.Name, PoolNoForFileNameLists, VA, Pntr);
      dummy := InsertListItem(VA, List);
      VMRelease(VA);
   UNTIL NOT FIO.ReadNextEntry(Rslt);
   FIO.IOcheck := OldIOcheck ;
   RETURN TRUE;
END BuildFileNameList;

PROCEDURE ChooseFromList(List:      TACTList;
                     VAR Rslt:      ARRAY OF CHAR): BOOLEAN;
VAR
   DummyList:  TACTList;
   DummyList2: TACTList;
   SelectItem: TACTListItem;
   FunctKey:   BOOLEAN;
   ch:         CHAR;
   BDummy:     BOOLEAN;
   DVA:        VirtAddr; (* for DataItem *)
   dummy:      DataItemPntr;

BEGIN
   IF NOT GetFirstItem(List,SelectItem) THEN
       ProgramErrorAndHalt('Error in ChooseFromList');
   END;

   IF NOT DoSelectWindow(FileNameSelectWind,
                        List, DummyList, DummyList2, 0 (* PoolNo not used *),
                        SelectItem, ch, FunctKey,BDummy,TRUE) THEN
	DisposeListItem( List, SelectItem );
	RETURN FALSE
   END;

   GetItemData(List,SelectItem,DVA,dummy);
   Str.Copy(Rslt, dummy^.FNameInt);
   ReleaseItemHold(List, SelectItem);

   DisposeListItem( List, SelectItem );
   RETURN TRUE;
END ChooseFromList;

PROCEDURE CheckIfDirectory( Pat : ARRAY OF CHAR ) : BOOLEAN ; (* >> should export << *)
   VAR
	DirEntryRec : FIO.DirEntry;
	OldIOcheck  : BOOLEAN ;
	rc	    : BOOLEAN ;
   BEGIN
	OldIOcheck := FIO.IOcheck ;
	FIO.IOcheck := FALSE ;
(*	IF (Pat[Str.Length(Pat)-1] = ':') (* OR (Pat[Str.Length(Pat)-1] = '\') *) THEN
	   rc := TRUE *)
	IF (Str.Pos(Pat,'*') < MAX(CARDINAL)) OR (Str.Pos(Pat,'?') < MAX(CARDINAL)) THEN
	   rc := FALSE	(* if have wild chars -- assume not a directory; ReadFirst may return TRUE! *)
	ELSIF FIO.ReadFirstEntry(Pat, FileAttr{directory},DirEntryRec) AND
	      ( directory IN DirEntryRec.attr) THEN
	   rc := TRUE
	ELSE
	   rc := FALSE
	END;
	FIO.IOcheck := OldIOcheck ;
	RETURN rc
   END CheckIfDirectory ;


PROCEDURE HandleFileNameField(VAR Field:     ARRAY OF CHAR;
                                  Exten:     ARRAY OF CHAR;
                              VAR ReDisplay: BOOLEAN;
                              VAR ReEdit:    BOOLEAN);
VAR
     Drv:    ARRAY[0..4] OF CHAR;
     Pth:    ARRAY[0..100] OF CHAR;
     Name:   ARRAY[0..8] OF CHAR;
     Ext:    ARRAY[0..3] OF CHAR;
     Pat:    ARRAY[0..100] OF CHAR;
     Dummy:  ARRAY[0..2] OF CHAR;
     Rslt:   ARRAY[0..15] OF CHAR;
     DoMenu: BOOLEAN;
     i:      CARDINAL;
     tList:  TACTList;
     PatLen: CARDINAL;
BEGIN
   Str.Copy(Pat, Field);
   UpcaseStr(Pat,Pat);
   ReDisplay := TRUE;
   ReEdit := FALSE;

   DoMenu := FALSE;
   TrimBlanks( Pat, Pat ) ;

   IF Pat[0] = 0C THEN	(* empty *)
      Drv[0] := 0C;
      Pth[0] := 0C;
      Pat := '*';
      IF Exten[0] <> '.' THEN
         Str.Append(Pat,'.')
      END;
      Str.Append(Pat,Exten);
      DoMenu := TRUE;
   ELSE
      AllowWildCards := TRUE;
      IF CheckIfDirectory( Pat ) THEN  Str.Append( Pat, '\*' )  END;
      PatLen := Str.Length(Pat)-1 ;
      IF (Pat[ PatLen ] = '\') OR (Pat[ PatLen ] = ':') THEN  Str.Append( Pat, '*' )  END ;
      IF NOT StandardizeFileName(Pat,Exten) THEN
          (*RES OLD MSG 318
          "%0" cannot be used as a File Name or Pattern.
          *)
          AllowWildCards := FALSE;
          MsgString(Pat,0);
          PutResError( (*RES REM INS*) 318 );
          ReEdit := TRUE;
          RETURN
      END;
      AllowWildCards := FALSE;
      IF NOT ParseFilename(Pat,Drv,Pth,Name,Ext) THEN
         ProgramErrorAndHalt('Unexpected error from ParseFilename');
      END;
      IF (Str.Pos(Name,'*') < MAX(CARDINAL)) OR (Str.Pos(Name,'?') < MAX(CARDINAL)) OR
	 (Str.Pos(Ext,'*') < MAX(CARDINAL)) OR (Str.Pos(Ext,'?') < MAX(CARDINAL))
      THEN DoMenu := TRUE END;
   END;
   IF DoMenu THEN
      tList := InitializeFileNameList();
      IF NOT BuildFileNameList(Pat, tList) THEN
         (*RES OLD MSG 319
         Your File Pattern "%0" selected nothing.
         *)
         MsgString(Pat,0);
         PutResError( (*RES REM INS*) 319 );
         ReEdit := TRUE;
         FreePool(PoolNoForFileNameLists);  (* frees list quickly *)
         RETURN;
      END;
      IF NOT ChooseFromList(tList,Rslt) THEN
         ReEdit := TRUE;
         FreePool(PoolNoForFileNameLists);  (* frees list quickly *)
         RETURN;
      END;
      FreePool(PoolNoForFileNameLists);  (* frees list quickly *)
      IF NOT ParseFilename(Rslt,Dummy,Dummy,Name,Ext) THEN
         ProgramErrorAndHalt('Unexpected error (2) from ParseFilename');
      END;
      MakeFilename(Drv,Pth,Name,Ext,Field)
   END;
END HandleFileNameField;

BEGIN
    WITH FileNameSelectWind DO
        XPos :=   45;
        YPos :=   4;
        XSize := 25;
        YSize := 9;
        MxYSize := 9;
        Type := Dialog;
        AllowMove := TRUE;
        AllowResize := TRUE;
    END;
END FileNameBase.
