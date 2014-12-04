IMPLEMENTATION MODULE WWWUtils;
(* copyright (c) 1996 John Bradley, Geoffrey Rockwell, Lidio Presutti, University of Toronto *)

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

IMPORT Utils, FIO, Str, Storage;
FROM ResText IMPORT OutputTextItem;
FROM TACTInit IMPORT PathTDBName;
FROM ErrorBase IMPORT ProgramErrorAndHalt;
FROM HyperDataModel IMPORT HRecPntr;
FROM StringIO IMPORT SWriteString;

VAR
   ScriptName:  ARRAY[0..100] OF CHAR;


PROCEDURE CheckRequestMethod(): RequestMethodType;
VAR
  rslt:   ARRAY[0..10] OF CHAR;
BEGIN
(*
REQUEST_METHOD

     The method with which the request was made. For HTTP, this is "GET", "HEAD",
     "POST", etc.
*)
   Utils.GetEnv( 'REQUEST_METHOD', rslt);
   Utils.UpcaseStr(rslt,rslt);
   IF (rslt[0] = 0C) THEN RETURN POSTMethod END;
   IF (Str.Compare(rslt,'GET') = 0) THEN RETURN GETMethod END;
   IF (Str.Compare(rslt,'POST') = 0) THEN RETURN POSTMethod END;
   ProgramErrorAndHalt('Bad REQUEST_METHOD given');
END CheckRequestMethod;

(*
When a POST query is received, the REQUEST_METHOD environment
variable is set to POST, and httpd creates three environment
variables that are not otherwise present: 

  CONTENT_TYPE=application/x-www-form-urlencoded
  CONTENT_LENGTH=nnnn
  CONTENT_FILE=C:\TEMP\HSXXXXXX.INP

CONTENT_LENGTH is set to exactly the number of bytes in the
content file. The CONTENT_TYPE is as shown for Mosaic form
output. Other types may appear in the future.

*)

TYPE
   ParseData = POINTER TO ARRAY [0..32000] OF CHAR;

(* Procedure to create a ParseData element from a string *)

PROCEDURE CreateParseData(VAR PD: ParseData; str: ARRAY OF CHAR);
BEGIN
   Storage.ALLOCATE(PD, Str.Length(str)+1);
   Str.Copy(PD^,str);
END CreateParseData;

(* Procedures to read in ParseData element from a file *)

PROCEDURE ReadFromFile(f:  FIO.File; VAR PD: ParseData; sz: CARDINAL);
BEGIN
   Storage.ALLOCATE(PD, sz+1);
   sz := FIO.RdBin(f, PD^, sz);
   PD^[sz] := 0C;
END ReadFromFile;

PROCEDURE GetContentLength(): CARDINAL;
VAR
   work:   ARRAY[0..40] OF CHAR;
   OK:     BOOLEAN;
BEGIN
   Utils.GetEnv( 'CONTENT_LENGTH', work );
   Utils.TrimBlanks(work,work);
   RETURN CARDINAL(Str.StrToCard(work,10,OK));
END GetContentLength;

PROCEDURE File2ParseData(VAR PD: ParseData;
                              f: FIO.File;
                              l: BOOLEAN);
VAR
   sz:       CARDINAL;
   upd:      ParseData;
BEGIN
   IF l THEN ReadFromFile(f, PD, GetContentLength());
   ELSE
      Storage.ALLOCATE(upd, 32000);
      sz := FIO.RdBin(f, upd^,32000);
      upd^[sz] := 0C;
      Storage.ALLOCATE(PD, sz+1);
      Str.Copy(PD^, upd^);
      Storage.DEALLOCATE(upd, 32000);
   END;
END File2ParseData;

PROCEDURE InitialParseData(VAR PD: ParseData);
VAR
   work:    ARRAY[0..200] OF CHAR;
   fl:      FIO.File;
BEGIN
   Utils.GetEnv( 'CONTENT_FILE', work ); (* used by DOS CGI httpd for Win3.1 only *)
   IF work[0] = 0C THEN File2ParseData(PD, FIO.StandardInput, (* l = *) TRUE);
   ELSE
      Utils.TrimBlanks(work,work);
      fl := FIO.OpenRead(work);
      ReadFromFile(fl, PD, GetContentLength());
      FIO.Close(fl);
   END;
END InitialParseData;

PROCEDURE DestroyParseData(VAR PD: ParseData);
VAR
   sz:  CARDINAL;
BEGIN
   sz := Str.Length(PD^);
   Storage.DEALLOCATE(PD, sz+1 (*+1 added j.b. June 96*) );
   PD := NIL;
END DestroyParseData;

PROCEDURE ParseDataDefined(PD: ParseData): BOOLEAN;
BEGIN
   RETURN PD <> NIL;
END ParseDataDefined;

PROCEDURE HexToCard(c: CHAR): CARDINAL;
BEGIN
   IF (c >= '0') AND (c <= '9') THEN RETURN ORD(c) - ORD('0') END;
   IF (c >= 'A') AND (c <= 'F') THEN RETURN ORD(c) + 10 - ORD('A') END;
   RETURN 255;
END HexToCard;

PROCEDURE GetStringData(input: ParseData;
                    VAR next:  ParseData;
                        term:  CHAR;
                    VAR output: ARRAY OF CHAR);
VAR
   i,j,k:    CARDINAL;
BEGIN
   i := 0; j := 0;
   WHILE ((j <= HIGH(output)) AND (input^[i] <> term) AND (input^[i] <> 0C)) DO
      IF input^[i] = '+' THEN
         output[j] := ' ';
         INC(i);
      ELSIF input^[i] = '%' THEN
         output[j] := CHR(HexToCard(input^[i+1]) * 16 + HexToCard(input^[i+2]));
         INC(i,3);
      ELSE
         output[j] := input^[i];
         INC(i);
      END;
      INC(j);
   END;
   IF j <= HIGH(output) THEN output[j] := 0C END;
   WHILE (input^[i] <> term) AND (input^[i] <> 0C) DO INC(i) END;
   IF (input^[i] = term) THEN INC(i) END;
   next := ParseData(ADR(input^[i]));
END GetStringData;

PROCEDURE GetItem(Inp: ParseData;
              VAR Next: ParseData;
              VAR Name: ARRAY OF CHAR;
              VAR Value: ARRAY OF CHAR);
BEGIN
   GetStringData(Inp, Next, '=', Name);
   GetStringData(Next, Next, '&', Value);
END GetItem;

PROCEDURE FindItem(Inp: ParseData;
               VAR Next: ParseData;
                   Name: ARRAY OF CHAR;
               VAR Value: ARRAY OF CHAR): BOOLEAN;
VAR
   trial:  ARRAY[0..80] OF CHAR;
   rslt:   INTEGER;
BEGIN
   Next := Inp;
   REPEAT
      GetStringData(Next, Next, '=', trial);
      GetStringData(Next, Next, '&', Value);
      rslt := Str.Compare(trial, Name);
   UNTIL (rslt = 0) OR (Next^[0] = 0C);
   IF (rslt <> 0) THEN
      Value[0] := 0C;
      RETURN FALSE;
   ELSE RETURN TRUE END;
END FindItem;

PROCEDURE FindItemCard(Inp: ParseData;
                   VAR Next: ParseData;
                       Name: ARRAY OF CHAR;
                   VAR Value: CARDINAL): BOOLEAN;
VAR
   temp:  ARRAY[0..20] OF CHAR;
   OK:    BOOLEAN;
   rslt:  LONGCARD;
BEGIN
   IF NOT FindItem(Inp,Next,Name,temp) THEN RETURN FALSE END;
   Utils.TrimBlanks(temp,temp);
   rslt := Str.StrToCard(temp,10,OK);
   IF (NOT OK) THEN RETURN FALSE END;
   Value := CARDINAL(rslt);
   RETURN TRUE;
END FindItemCard;

PROCEDURE ConvertWWWData(Inp: ARRAY OF CHAR;
                     VAR Out: ARRAY OF CHAR);
VAR tmp1, tmp2: ParseData;
BEGIN
  tmp1 := ParseData(ADR(Inp));
  GetStringData(tmp1,tmp2,0C,Out);
END ConvertWWWData;

TYPE
   QString = RECORD
      CASE :BOOLEAN OF
        TRUE:
          type:  CHAR;
          hex:   ARRAY[0..8] OF CHAR; (* 8 allows a 0C at end j.b. *)
      | FALSE:
          chars: ARRAY[0..9] OF CHAR;
      END;
   END;

   QHRec = RECORD
     CASE :BOOLEAN OF
       TRUE:
          hrec:  HRecPntr;
     | FALSE:
          str:   ARRAY[0..3] OF CHAR;
     END;
   END;

PROCEDURE MakeBasicQuery(qtext: ARRAY OF CHAR;
                         ptext: ARRAY OF CHAR;
                         ltext: ARRAY OF CHAR;
                    VAR rslt:  ARRAY OF CHAR);
VAR
   lp:      CARDINAL;
BEGIN
   lp := 0;
   SWriteString(rslt, lp, 'ú<A HREF="', 0);
   SWriteString(rslt, lp, ScriptName, 0);
   IF PathTDBName[0] <> 0C THEN
      SWriteString(rslt, lp, '/', 0);
      SWriteString(rslt, lp, PathTDBName, 0);
   END;
   SWriteString(rslt, lp, '?', 0);
   SWriteString(rslt, lp, qtext, 0);
   IF ptext[0] <> 0C THEN
      SWriteString(rslt, lp, '#', 0);
      SWriteString(rslt, lp, ptext, 0);
   END;
   SWriteString(rslt, lp, '"ú>', 0);
   SWriteString(rslt, lp, ltext, 0);
   SWriteString(rslt, lp, 'ú</Aú>', 0);
END MakeBasicQuery;

PROCEDURE MakeQueryLink(in:    HRecPntr;
                        type:  CHAR;
                        ltext: ARRAY OF CHAR;
                    VAR rslt:  ARRAY OF CHAR);
VAR
   qstring: QString;
BEGIN
   Utils.PrintHexByte(in, qstring.hex);
   qstring.type := type;
   IF type = 'P' THEN MakeBasicQuery(qstring.chars, 'here', ltext, rslt);
   ELSE MakeBasicQuery(qstring.chars,'', ltext, rslt); END;
END MakeQueryLink;

PROCEDURE MakeQueryDest(ltext: ARRAY OF CHAR;
                    VAR rslt:  ARRAY OF CHAR);
VAR
   qstring: QString;
   lp:      CARDINAL;
BEGIN
   lp := 0;
   SWriteString(rslt, lp, 'ú<A NAME="here"ú>ú<Bú>', 0);
   SWriteString(rslt, lp, ltext, 0);
   SWriteString(rslt, lp, 'ú</Bú>ú</Aú>', 0);
END MakeQueryDest;

PROCEDURE Hex(in: ARRAY OF CHAR;
              pos: CARDINAL): CHAR;
BEGIN
   RETURN CHR(HexToCard(in[pos]) * 16 + HexToCard(in[pos+1]));
END Hex;

PROCEDURE ParseQueryString(in:   ARRAY OF CHAR;
                       VAR hrec: HRecPntr;
                       VAR type: CHAR);
VAR
   qstring: QString;
   qhrec:   QHRec;
BEGIN
   Str.Copy(qstring.chars,in);
   type := qstring.type;
   qhrec.str[0] := Hex(qstring.hex,0);
   qhrec.str[1] := Hex(qstring.hex,2);
   qhrec.str[2] := Hex(qstring.hex,4);
   qhrec.str[3] := Hex(qstring.hex,6);
   hrec := qhrec.hrec;
END ParseQueryString;

(*
PROCEDURE GetBatName(VAR rslt:  ARRAY OF CHAR);
VAR
   i,j:  CARDINAL;
   a:    ARRAY[0..50] OF CHAR;
BEGIN
   Utils.GetEnv('SCRIPT_NAME',a);
   i := Str.Length(a) - 1;
   WHILE (i > 0) AND (a[i] <> '/') DO DEC(i) END;
   INC(i);
   j := 0;
   WHILE (a[i] <> 0C) DO
      rslt[j] := a[i];
      INC(i); INC(j);
   END;
   rslt[j] := 0C;
END GetBatName;
*)

PROCEDURE DoStartPre();
BEGIN
   OutputTextItem( StartPre );
END DoStartPre;

PROCEDURE DoEndPre();
BEGIN
   OutputTextItem( EndPre );
END DoEndPre;

BEGIN
(*   GetBatName(ScriptName); *)
   Utils.GetEnv('SCRIPT_NAME',ScriptName);
   pd := NIL;
END WWWUtils.
