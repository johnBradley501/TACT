IMPLEMENTATION MODULE Trace;
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


FROM SYSTEM IMPORT ADDRESS;
FROM GlobalDefs IMPORT StrAny;
IMPORT FIO ;
FROM Utils IMPORT
  (* proc *) PrintHex, InstallTermProc;

(* ----- File stuff doesn't seem to work ??? here
FROM Utils IMPORT
  (* type *) BFile, RWType, PrintHex,
  (* proc *) BClose, BCreate, WriteLine, InstallTermProc;
FROM UtilsTwo IMPORT IOErrorMessage;
----- *)

FROM ErrorBase IMPORT PutError;
FROM StringIO IMPORT
   SWriteString, SWriteCard, SWriteInt, SWriteChar;
FROM Str IMPORT CardToStr;

TYPE
   OpenStatus = (NotOpened, Opened, IOError);
   AddressParts = RECORD
      OFFSET:     CARDINAL;
      SEGMENT:    CARDINAL;
   END;

VAR
   TFile:   FIO.File;
   MPos:    CARDINAL;
   Message: ARRAY[0..132] OF CHAR;
   TFileOpen: OpenStatus;
   IOResult: CARDINAL;

PROCEDURE OpenTFile;
BEGIN
   TFile := FIO.Create(TFileName );
   IOResult := FIO.IOresult();
   IF IOResult <> 0 THEN
        MPos := 0;
        SWriteString(Message,MPos,'TRACE Error Opening TRACE.DMP: ',0);
        PutError(Message);
        TFileOpen := IOError;
   END;
   MPos := 0;
   TFileOpen := Opened;
END OpenTFile;

PROCEDURE TWriteLn;
BEGIN
   IF TFileOpen = NotOpened THEN OpenTFile END;
   IF TFileOpen = IOError THEN RETURN END;

   IF MPos > 0 THEN  (* there is something to write!! *)
	FIO.WrStr(TFile,Message);
	FIO.WrLn(TFile);
   END ;
   IOResult := FIO.IOresult();
   IF IOResult <> 0 THEN
        MPos := 0;
        SWriteString(Message,MPos,'TRACE Error WriteLn -- TRACE.DMP: ',0);
        PutError(Message);
        TFileOpen := IOError;
   END;
   MPos := 0;
END TWriteLn;

PROCEDURE TWriteString( s :ARRAY OF CHAR );
BEGIN
   SWriteString(Message,MPos,s,0);
END TWriteString;

PROCEDURE TWriteStrHex( s :ARRAY OF CHAR );
VAR T:   StrAny;
BEGIN
    PrintHex(s,T);
    SWriteString(Message,MPos,T,0);
END TWriteStrHex;

PROCEDURE TWriteChar(x : CHAR; n :CARDINAL);
BEGIN
   SWriteChar(Message,MPos,x,n);
END TWriteChar;

PROCEDURE TWriteInt( x :INTEGER; n :CARDINAL );
BEGIN
   SWriteInt(Message,MPos,x,n);
END TWriteInt;

PROCEDURE TWriteCard( x, n :CARDINAL );
BEGIN
   SWriteCard(Message,MPos,x,n);
END TWriteCard;

PROCEDURE TWriteAddr( x :ADDRESS );
VAR
   Temp:    AddressParts;
   Addr:    ARRAY[0..3] OF CHAR;
   dummy:   BOOLEAN;
BEGIN
   Temp := AddressParts(x);
   CardToStr(LONGCARD(Temp.SEGMENT),Addr,16,dummy);
   SWriteString(Message,MPos,Addr,0);
   SWriteChar(Message,MPos,':',0);
   CardToStr(LONGCARD(Temp.OFFSET),Addr,16,dummy);
   SWriteString(Message,MPos,Addr,0);
END TWriteAddr;

PROCEDURE CloseTFile;
BEGIN
   IF TFileOpen = Opened THEN
       IF MPos <> 0 THEN TWriteLn END;
       FIO.Close(TFile );
       TFileOpen := NotOpened;
	DoTrace := FALSE ; (* tracing if need be *)
   END;
END CloseTFile;

BEGIN
   TFileName := 'd:$$TRACE.DMP';
   MPos := 0;
   DoTrace := FALSE ;
   TFileOpen := NotOpened;
   InstallTermProc(CloseTFile);
END Trace.