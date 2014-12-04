IMPLEMENTATION MODULE ResComments;

(* copyright (c) 1987-96 John Bradley, University of Toronto *)

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

(* jpi version ... j.b. *)

IMPORT ASCII;
FROM SYSTEM IMPORT ADR;
IMPORT Lib;
IMPORT Str;

CONST
   OpenComment = '(*';
   CloseComment = '*)';

PROCEDURE FindPos(Data:   ARRAY OF CHAR;
                  Pat:    ARRAY OF CHAR): CARDINAL;
VAR
   i,j,k:   CARDINAL;
BEGIN
   i := 0;
   WHILE (i <= HIGH(Data)) AND (Data[i] <> 0C) DO
      IF Data[i] = Pat[0] THEN
         k := i + 1;
         j := 1;
         WHILE (Pat[j] <> 0C) AND (Data[k] = Pat[j]) DO
            INC(j);
            INC(k)
         END;
         IF Pat[j] = 0C THEN RETURN i END;
      END;
      INC(i);
   END;
   RETURN HIGH(Data) + 1;
END FindPos;

PROCEDURE FindOpenComment(LineIn:     ARRAY OF CHAR;
                      VAR LineBefore: ARRAY OF CHAR;
                      VAR LineAfter:  ARRAY OF CHAR): BOOLEAN;
VAR   l,j:    CARDINAL;
BEGIN
    LineBefore[0] := 0C;
    LineAfter[0] := 0C;
    l := Str.Length(LineIn);
    j := FindPos(LineIn,OpenComment);
    IF j > l THEN RETURN FALSE END;
    IF j > 0 THEN Lib.Move(ADR(LineIn[0]),ADR(LineBefore),j) END;
    LineBefore[j] := 0C;
    Lib.Move(ADR(LineIn[j+2]),ADR(LineAfter),l-j-2);
    LineAfter[l-j-2] := 0C;
    RETURN TRUE
END FindOpenComment;

PROCEDURE FindCloseComment(LineIn:     ARRAY OF CHAR;
                       VAR LineBefore: ARRAY OF CHAR;
                       VAR LineAfter:  ARRAY OF CHAR): BOOLEAN;
VAR   l,j:    CARDINAL;
BEGIN
    LineBefore[0] := 0C;
    LineAfter[0] := 0C;
    l := Str.Length(LineIn);
    j := FindPos(LineIn,CloseComment);
    IF j > l THEN RETURN FALSE END;
    IF j > 0 THEN Lib.Move(ADR(LineIn[0]),ADR(LineBefore),j) END;
    LineBefore[j] := 0C;
    Lib.Move(ADR(LineIn[j+2]),ADR(LineAfter),l-j-2);
    LineAfter[l-j-2] := 0C;
    RETURN TRUE
END FindCloseComment;

PROCEDURE FindNextThing(LineIn:     ARRAY OF CHAR;
                    VAR Thing:      ARRAY OF CHAR;
                    VAR LineBefore: ARRAY OF CHAR;
                    VAR LineAfter:  ARRAY OF CHAR): BOOLEAN;
VAR   len,l,j:    CARDINAL;
      loop:       BOOLEAN;
BEGIN
    len := Str.Length(LineIn);
    LineBefore[0] := 0C;
    LineAfter[0] := 0C;
    l := 0;
    WHILE (l <= HIGH(LineIn)) AND (LineIn[l] <> 0C) AND
    ((LineIn[l] = ' ') OR (LineIn[l] = ASCII.ht)) DO
       LineBefore[l] := LineIn[l];
       INC(l)
    END;
    IF (l > HIGH(LineIn)) OR (LineIn[l] = 0C) THEN RETURN FALSE END;
    LineBefore[l] := 0C;

    j := 0;
    loop := TRUE;
    WHILE (l <= HIGH(LineIn)) AND (LineIn[l] <> 0C) AND
    (LineIn[l] <> ' ') AND (LineIn[l] <> ASCII.ht) AND loop DO
       IF (l < HIGH(LineIn)) AND
       ((LineIn[l] = '*') AND (LineIn[l+1] = ')')) OR
       ((LineIn[l] = '(') AND (LineIn[l+1] = '*')) THEN
          loop := FALSE
       ELSE
          Thing[j] := LineIn[l];
          INC(j); INC(l)
       END;
    END;
    Thing[j] := 0C;
    IF len > l THEN Lib.Move(ADR(LineIn[l]),ADR(LineAfter[0]),len-l) END;
    LineAfter[len-l] := 0C;
    RETURN TRUE
END FindNextThing;

END ResComments.
