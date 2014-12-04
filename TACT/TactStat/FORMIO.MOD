(* Copyright (C) 1987..1991 Jensen & Partners International *)

IMPLEMENTATION MODULE FormIO ;

IMPORT SYSTEM,Str ;

CONST
  MaxStrSize = 511 ;
TYPE
  MaxStr = ARRAY [0..MaxStrSize] OF CHAR ;


(*

  FormatString   = { Alpha | FieldSpecifier | SwitchChar }

  Alpha          = any ascii char except '%' and '\'

  FieldSpecifier = '%' '%'
                 | '% ['-'] [WidthSpecifier] TypeSpecifier

  WidthSpecifier = DecimalNumber [ '.' DecimalNumber ]

  TypeSpecifier  = 'u'        (* Unsigned *)
                 | 'i'        (* Signed *)
                 | 'r'        (* Real *)
                 | 'c'        (* Character *)
                 | 's'        (* String *)
                 | 'x'        (* Hex String  *LP* *)
                 | 'h'        (* Hex (unsigned) *)
                 | 'b'        (* Boolean *)
                 | 'p'        (* Pointer / Address *)

  SwitchChar     = '\' SwitchOptions

  SwitchOptions  = '\'        (* \ *)
                 | '%'        (* % *)
                 | 'b'        (* BS  = CHR(8)          *)
                 | 'f'        (* FF  = CHR(12)         *)
                 | 'n'        (* NL  = CHR(13),CHR(10) *)
                 | 't'        (* Tab = CHR(9)          *)
                 | 'e'        (* Esc = CHR(27)         *)
                 | CharCode

  CharCode       = DecimalNumber

  DecimalNumber  = Digit [ Digit [ Digit ] ]

*)

TYPE ParamRec = RECORD
                  size  : CARDINAL ;
                  adr   : ADDRESS ;
                END ;


PROCEDURE Format ( VAR Res : ARRAY OF CHAR ;
                   Pat     : ARRAY OF CHAR ;
                   Params  : ARRAY OF ParamRec ) ;
TYPE
   HexType = ARRAY[0..15] OF CHAR ;
CONST
   HexChars = HexType ( '0123456789ABCDEF' );
VAR
  NP, NP2    : CARDINAL;
  buff       : MaxStr ;
  hb         : ARRAY [0..4] OF CHAR ;
  rjust      : BOOLEAN ;
  fwidth     : CARDINAL ;
  fnum       : CARDINAL ;
  fsize      : CARDINAL ;
  places     : CARDINAL ;
  lc         : LONGCARD ;
  lr         : LONGREAL ;
  li         : LONGINT ;
  i,j,h,l,p  : CARDINAL ;
  storechar  : BOOLEAN ;
  c          : CHAR ;
  Ok         : BOOLEAN ;
  base       : CARDINAL ;
  f          : POINTER TO
                   RECORD CASE : SHORTCARD OF
                            0 : si  : SHORTINT |
                            1 : i   : INTEGER |
                            2 : li  : LONGINT |
                            3 : sc  : SHORTCARD |
                            4 : c   : CARDINAL |
                            5 : lc  : LONGCARD |
                            6 : r   : REAL |
                            7 : lr  : LONGREAL |
                            8 : ch  : CHAR |
                            9 : a   : ADDRESS |
                           10 : b   : BOOLEAN |
                           11 : str : MaxStr ;
                          END ;
                    END ;

PROCEDURE GetNum (): CARDINAL;     (* leaves i and c changed *)

VAR
  n, nc: CARDINAL;

BEGIN
  n := 0 ;
  FOR nc := 0 TO 2 DO
    IF (c<'0')OR(c>'9') THEN RETURN n END ;
    n := n*10+ORD(c)-ORD('0');
    c := Pat[i] ;
    INC(i) ;
  END ;
  RETURN n ;
END GetNum ;

BEGIN
  fnum := 0 ;
  h := HIGH(Res) ;
  l := Str.Length(Pat);
  Res[0] := 0C ;
  i := 0 ; j := 0 ;
  LOOP
    IF i=l THEN EXIT END ;
    storechar := TRUE ;
    c := Pat[i] ; INC(i) ;
    IF c = '\' THEN
      c := Pat[i] ; INC(i) ;
      CASE CAP(c) OF
              'B':c:=CHR(8);
       |      'F':c:=CHR(12);
       |      'E':c:=CHR(27);
       |      'N':Res[j] := CHR(13); INC(j) ; c := CHR(10);
       |      'T':c:=CHR(9);
       | '0'..'9':DEC(i) ; c:= CHR(GetNum()) ;
      END ;
    ELSIF (c='%')AND(i<>l) THEN
      c := Pat[i] ; INC(i) ;
      (* pattern found *)
      rjust:=TRUE ; places:=5 ;
      storechar := FALSE ;
      IF c='-' THEN rjust := FALSE ; c := Pat[i] ; INC(i) ;
      END ;
      fwidth := GetNum() ;
      IF c='.' THEN
         c := Pat[i] ; INC(i) ;
         places := GetNum() ;
      END;
      IF fnum<=HIGH(Params) THEN
         WITH Params[fnum] DO
           fsize := size ;
           f := adr ;
         END ;
         INC(fnum) ;
         c := CAP(c) ;
         Ok := TRUE ;
         buff[0] := 0C ;
         CASE c OF
           'I': IF    fsize=1 THEN li := LONGINT(f^.si)
                ELSIF fsize=2 THEN li := LONGINT(f^.i)
                ELSIF fsize=4 THEN li := LONGINT(f^.li) ;
                ELSE Ok := FALSE ;
                END ;
                IF Ok THEN
                  Str.IntToStr(li,buff,10,Ok) ;
                END ;
         | 'U',
           'H': IF    fsize=1 THEN lc := LONGCARD(f^.sc)
                ELSIF fsize=2 THEN lc := LONGCARD(f^.c)
                ELSIF fsize=4 THEN lc := LONGCARD(f^.lc) ;
                ELSE Ok := FALSE  ;
                END ;
                IF Ok THEN
                  base := 10 ; IF c='H' THEN base := 16 END ;
                  Str.CardToStr(lc,buff,base,Ok) ;
                  IF (c='H') AND (buff[0] >= "A") THEN Str.Insert(buff,"0",0) END ;
                END ;
         | 'P': IF fsize <> 4 THEN Ok := FALSE END ;
                IF Ok THEN
                  Str.CardToStr(LONGCARD(SYSTEM.Seg(f^.a^)),buff,16,Ok) ;
                  Str.Append(buff,':') ;
                  Str.CardToStr(LONGCARD(SYSTEM.Ofs(f^.a^)),hb,16,Ok) ;
                  Str.Append(buff,hb) ;
                END ;
         | 'R': IF    fsize=4 THEN lr := LONGREAL(f^.r)
                ELSIF fsize=8 THEN lr := LONGREAL(f^.lr) ;
                ELSE Ok := FALSE ;
                END ;
                IF Ok THEN
                  Str.FixRealToStr(lr,places,buff,Ok) ;
                END ;
         | 'S': Str.Copy(buff,f^.str) ;
                IF fsize < SIZE(buff) THEN buff[fsize] := CHR(0) END ;
         | 'X':
		NP := 0;
		NP2 := 0;
		WHILE (NP <= HIGH(f^.str)) AND (f^.str[NP] <> 0C) AND (NP2 < HIGH(buff)) DO
		   buff[NP2]     := HexChars[ORD(f^.str[NP]) DIV 16];
		   buff[NP2 + 1] := HexChars[ORD(f^.str[NP]) MOD 16];
		   INC(NP);
		   INC(NP2,2);
		END;
                IF fsize < SIZE(buff) THEN buff[fsize] := CHR(0) END ;
         | 'C': buff[0] := f^.ch ; buff[1] := CHR(0) ;
         | 'B': IF fsize=1 THEN
                  IF f^.b THEN buff := 'TRUE' ELSE buff := 'FALSE' END ;
                END ;
         ELSE storechar := TRUE ;
         END;
         Res[j] := CHR(0) ;
         IF NOT Ok THEN buff := '????' END ;
         p := Str.Length(buff) ;
         IF rjust THEN
           WHILE (p<fwidth) DO
             Res[j] := ' ' ; INC(j) ; INC(p) ;
           END ;
           Res[j] := CHR(0) ;
           Str.Append(Res,buff) ;
           j := Str.Length(Res);
         ELSE
           Res[j] := CHR(0) ;
           Str.Append(Res,buff) ;
           j := Str.Length(Res);
           WHILE (p<fwidth) DO
             Res[j] := ' ' ; INC(j) ; INC(p) ;
           END ;
         END ;
      END ;
    END ;
    IF storechar THEN
       Res[j] := c ; INC(j) ;
    END ;
    IF (j>h) THEN EXIT END ;
  END ;
  IF (j<=h) THEN Res[j] := CHR(0) END ;
END Format ;


PROCEDURE WrF1(  Pat : ARRAY OF CHAR ;
                 P1  : ARRAY OF BYTE ;
             VAR res : ARRAY OF CHAR) ;
VAR
  params : ARRAY [0..0] OF ParamRec ;
BEGIN
  params[0].size := SIZE(P1) ;
  params[0].adr  := ADR(P1) ;
  Format(res,Pat,params) ;
END WrF1 ;

PROCEDURE WrF2 ( Pat : ARRAY OF CHAR ;
                 P1,P2  : ARRAY OF BYTE ;
             VAR res : ARRAY OF CHAR) ;
VAR
  params : ARRAY [0..1] OF ParamRec ;
BEGIN
  params[0].size := SIZE(P1) ;
  params[0].adr  := ADR(P1) ;
  params[1].size := SIZE(P2) ;
  params[1].adr  := ADR(P2) ;
  Format(res,Pat,params) ;
END WrF2 ;

PROCEDURE WrF3 ( Pat : ARRAY OF CHAR ;
                 P1,P2,P3  : ARRAY OF BYTE ;
             VAR res : ARRAY OF CHAR) ;
VAR
  params : ARRAY [0..2] OF ParamRec ;
BEGIN
  params[0].size := SIZE(P1) ;
  params[0].adr  := ADR(P1) ;
  params[1].size := SIZE(P2) ;
  params[1].adr  := ADR(P2) ;
  params[2].size := SIZE(P3) ;
  params[2].adr  := ADR(P3) ;
  Format(res,Pat,params) ;
END WrF3 ;

PROCEDURE WrF4 ( Pat : ARRAY OF CHAR ;
                 P1,P2,P3,P4  : ARRAY OF BYTE ;
             VAR res : ARRAY OF CHAR) ;
VAR
  params : ARRAY [0..3] OF ParamRec ;
BEGIN
  params[0].size := SIZE(P1) ;
  params[0].adr  := ADR(P1) ;
  params[1].size := SIZE(P2) ;
  params[1].adr  := ADR(P2) ;
  params[2].size := SIZE(P3) ;
  params[2].adr  := ADR(P3) ;
  params[3].size := SIZE(P4) ;
  params[3].adr  := ADR(P4) ;
  Format(res,Pat,params) ;
END WrF4 ;

PROCEDURE WrF5 ( Pat : ARRAY OF CHAR ;
                 P1,P2,P3,P4,P5  : ARRAY OF BYTE ;
             VAR res : ARRAY OF CHAR) ;
VAR
  params : ARRAY [0..4] OF ParamRec ;
BEGIN
  params[0].size := SIZE(P1) ;
  params[0].adr  := ADR(P1) ;
  params[1].size := SIZE(P2) ;
  params[1].adr  := ADR(P2) ;
  params[2].size := SIZE(P3) ;
  params[2].adr  := ADR(P3) ;
  params[3].size := SIZE(P4) ;
  params[3].adr  := ADR(P4) ;
  params[4].size := SIZE(P5) ;
  params[4].adr  := ADR(P5) ;
  Format(res,Pat,params) ;
END WrF5 ;

PROCEDURE WrF6 ( Pat : ARRAY OF CHAR ;
                 P1,P2,P3,P4,P5,P6 : ARRAY OF BYTE ;
             VAR res : ARRAY OF CHAR) ;
VAR
  params : ARRAY [0..5] OF ParamRec ;
BEGIN
  params[0].size := SIZE(P1) ;
  params[0].adr  := ADR(P1) ;
  params[1].size := SIZE(P2) ;
  params[1].adr  := ADR(P2) ;
  params[2].size := SIZE(P3) ;
  params[2].adr  := ADR(P3) ;
  params[3].size := SIZE(P4) ;
  params[3].adr  := ADR(P4) ;
  params[4].size := SIZE(P5) ;
  params[4].adr  := ADR(P5) ;
  params[5].size := SIZE(P6) ;
  params[5].adr  := ADR(P6) ;
  Format(res,Pat,params) ;
END WrF6 ;

PROCEDURE WrF7 ( Pat : ARRAY OF CHAR ;
                 P1,P2,P3,P4,P5,P6,P7 : ARRAY OF BYTE ;
             VAR res : ARRAY OF CHAR) ;
VAR
  params : ARRAY [0..6] OF ParamRec ;
BEGIN
  params[0].size := SIZE(P1) ;
  params[0].adr  := ADR(P1) ;
  params[1].size := SIZE(P2) ;
  params[1].adr  := ADR(P2) ;
  params[2].size := SIZE(P3) ;
  params[2].adr  := ADR(P3) ;
  params[3].size := SIZE(P4) ;
  params[3].adr  := ADR(P4) ;
  params[4].size := SIZE(P5) ;
  params[4].adr  := ADR(P5) ;
  params[5].size := SIZE(P6) ;
  params[5].adr  := ADR(P6) ;
  params[6].size := SIZE(P7) ;
  params[6].adr  := ADR(P7) ;
  Format(res,Pat,params) ;
END WrF7 ;

PROCEDURE WrF8 ( Pat : ARRAY OF CHAR ;
                 P1,P2,P3,P4,P5,P6,P7,P8 : ARRAY OF BYTE ;
             VAR res : ARRAY OF CHAR) ;
VAR
  params : ARRAY [0..7] OF ParamRec ;
BEGIN
  params[0].size := SIZE(P1) ;
  params[0].adr  := ADR(P1) ;
  params[1].size := SIZE(P2) ;
  params[1].adr  := ADR(P2) ;
  params[2].size := SIZE(P3) ;
  params[2].adr  := ADR(P3) ;
  params[3].size := SIZE(P4) ;
  params[3].adr  := ADR(P4) ;
  params[4].size := SIZE(P5) ;
  params[4].adr  := ADR(P5) ;
  params[5].size := SIZE(P6) ;
  params[5].adr  := ADR(P6) ;
  params[6].size := SIZE(P7) ;
  params[6].adr  := ADR(P7) ;
  params[7].size := SIZE(P8) ;
  params[7].adr  := ADR(P8) ;
  Format(res,Pat,params) ;
END WrF8 ;

PROCEDURE WrF ( Pat : ARRAY OF CHAR ;
            VAR res : ARRAY OF CHAR) ;
VAR
  c : CARDINAL ;
BEGIN
  c := 0 ;
  WrF1(Pat,c, res) ;
END WrF ;


END FormIO.
