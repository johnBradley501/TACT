IMPLEMENTATION MODULE GetParams;

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

IMPORT Lib, Str;
FROM Utils IMPORT ALLOCATE, DEALLOCATE;

TYPE
   LegalParamPntr = POINTER TO LegalParamData;
   LegalParamData = RECORD
      Next:     LegalParamPntr;
      Code:     CHAR;
      TakesP:   BOOLEAN;
   END;

VAR
   LGD:     LegalParamPntr;

PROCEDURE LegalParameter(code: CHAR; TakesParameter: BOOLEAN);
   VAR t:    LegalParamPntr;
BEGIN
(* NEW(t); *)
   ALLOCATE(t,SIZE(LegalParamData));
   t^.Next := LGD;
   t^.Code := CAP(code);
   t^.TakesP := TakesParameter;
   LGD := t;
END LegalParameter;

PROCEDURE GetParameters(VAR Rslt:     ParameterResult;
                        VAR BadParam: ARRAY OF CHAR): GetParametersStatus;
VAR
   PNo,NoP:   CARDINAL;
   CP:      ARRAY[0..80] OF CHAR;
   str:     ARRAY[0..80] OF CHAR;
   p:       ParameterResult;
   last:    ParameterResult;
   sz:      CARDINAL;
   lgp:     LegalParamPntr;
   cd:      CHAR;

PROCEDURE GetNextParam(VAR str: ARRAY OF CHAR): BOOLEAN;
VAR
   temp :   ARRAY[0..80] OF CHAR;
   p:       CARDINAL;
BEGIN
   IF CP[0] = 0C THEN
      INC(PNo);
      IF PNo > NoP THEN RETURN FALSE END;
      Lib.ParamStr(CP,PNo);
   END;
   p := Str.Pos(CP,'"');
   IF p = 0 THEN
      Str.Delete(CP,0,1);
      p := Str.Pos(CP,'"');
      WHILE (p = MAX(CARDINAL)) DO
         INC(PNo);
         IF PNo > NoP THEN
            p := MAX(CARDINAL) - 1
         ELSE
            Lib.ParamStr(temp,PNo);
            Str.Append(CP,' ');
            Str.Append(CP,temp);
            p := Str.Pos(CP,'"');
         END;
      END;
      Str.Slice(str,CP,0,p);
      Str.Delete(CP,0,p+1);
      Str.Insert(str,'"',0);
      RETURN TRUE;
   ELSIF p < MAX(CARDINAL) THEN
      Str.Slice(str,CP,0,p);
      Str.Delete(CP,0,p);
      RETURN TRUE;
   END;
   Str.Copy(str,CP);
   CP[0] := 0C;
   RETURN TRUE;
END GetNextParam;

PROCEDURE DiscardLegals;
BEGIN
   WHILE LGD <> NIL DO
      lgp := LGD^.Next;
(*    DISPOSE(LGD); *)
      DEALLOCATE(LGD,SIZE(LegalParamData));
      LGD := lgp
   END;
END DiscardLegals;

BEGIN
   NoP := Lib.ParamCount();
   PNo := 0;
   CP[0] := 0C;
   Rslt := NIL;
   BadParam[0] := 0C;
   last := NIL;
   WHILE GetNextParam(str) DO
      IF (str[0] = '-') AND (str[1] <> 0C) AND (LGD <> NIL) THEN
         lgp := LGD;
         WHILE (lgp <> NIL) AND (lgp^.Code <> CAP(str[1])) DO lgp := lgp^.Next END;
         IF lgp = NIL THEN
            Str.Copy(BadParam,str);
            DiscardLegals;
            RETURN GPSBadParameter;
         END;
         cd := CAP(str[1]);
         IF NOT lgp^.TakesP THEN
            str[0] := 0C
         ELSIF str[2] <> 0C THEN
            Str.Delete(str,0,2)
         ELSIF NOT GetNextParam(str) THEN
            Str.Copy(BadParam,str);
            DiscardLegals;
            RETURN GPSMissingValue;
         END;
      ELSE
         cd := ' ';
      END;
      IF str[0] = '"' THEN Str.Delete(str,0,1) END;
      sz := Str.Length(str) + (* for 0C*) 1 + (* size of ParameterData *) 7;
      ALLOCATE(p,sz);
      WITH p^ DO
         Size := sz;
         Code := cd;
         Str.Copy(Strg,str);
      END;
      IF last = NIL THEN Rslt := p
      ELSE last^.Next := p END;
      p^.Next := NIL;
      last := p;
   END;
   DiscardLegals;
   RETURN GPSOk;
END GetParameters;

PROCEDURE InitialParams;
BEGIN
   LGD := NIL;
END InitialParams;

END GetParams.
