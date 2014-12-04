IMPLEMENTATION MODULE BitOps ;
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


(*V1=Production *)
(*V2=Debug *)

IMPORT Str, Lib ;

TYPE  PackMaskType = ARRAY[0..8] OF CARDINAL ;
CONST PackMask = PackMaskType ( 0000H, 0001H, 0003H, 0007H, 000FH, 001FH, 003FH, 007FH, 00FFH );

CONST N = 256 ;
TYPE
   NodeTypes = RECORD
		Left : CARDINAL ;
		Right : CARDINAL ;
   END ;

VAR
   CodeTable		: ARRAY[0..N-1] OF CARDINAL ;	(* Huffman codes			*)
   CodeLen		: ARRAY[0..N-1] OF CARDINAL ;	(* number of bits to use from CodeTable *)
   DecodeTable		: ARRAY[N..2*N-1] OF NodeTypes ;
   DecodeTableRoot	: CARDINAL ;
(*<Debug*)
   TotalIn	: LONGCARD ;
   TotalOut	: LONGCARD ;
(*Debug>*)

PROCEDURE Pack( VAR InText : ARRAY OF CHAR;	(* VAR here for pass by ref usage *)
		VAR OutText: PackedStrType;
		    NoBits : CARDINAL ) ;
    VAR
	Need, Limit	: CARDINAL ;
	BitsRemaining	: CARDINAL ;  (* to use         *)
	CurIn, CurOut	: CARDINAL ;
	Result		: CARDINAL ;  (* used as a BYTE *)
	code		: CARDINAL ;  (* used as a BYTE *)
    BEGIN
	CurOut := 0 ;
	CurIn  := 0 ;
	Limit  := Str.Length( InText ) ;
	BitsRemaining := 0 ;  (* forces a read from InText array *)
	code := 0 ;
	LOOP
	   Need := 8 ;  (* number of bits to stuff into a byte *)
	   Result := 0 ;
	   LOOP
		IF BitsRemaining >= Need THEN
		   (* current code fullfills our need *)
		   IF Need = 0 THEN  EXIT  END ;
		   (* take what we need *)
		   DEC( BitsRemaining, Need ) ;
		   Result := CARDINAL(BITSET( Result ) + BITSET( code >> BitsRemaining )) ;
		   (* and leave the rest *)
		   code := CARDINAL(BITSET(code) * BITSET( PackMask[ BitsRemaining ])) ;
		   EXIT ;
		END ;
		(* we need more than current code *)
		IF BitsRemaining > 0 THEN
		   (* take what there is *)
		   DEC( Need, BitsRemaining ) ;
		   code := code << Need ;
		   Result := CARDINAL( BITSET( Result ) + BITSET( code ) ) ;
		END ;
		IF CurIn >= Limit THEN
		   (* end of buffer reached *)
		   BitsRemaining := 0 ;
		   IF Need = 8 THEN  Result := 0  END ;
		   EXIT ;
		END ;
		IF CurIn >= Limit THEN
		   code := 0 ;
		ELSE
		   code := ORD( InText[ CurIn ] )
		END ;
		INC( CurIn ) ;
		BitsRemaining := NoBits ;
	   END ;
	   OutText.PackedStr[ CurOut ] := VAL(CHAR, CARDINAL(BITSET(Result)*BITSET(00FFH)) ) ;
	   INC( CurOut ) ;
	   IF ((CurIn >= Limit) AND (BitsRemaining = 0)) OR (CurOut > HIGH(OutText.PackedStr)) THEN
		EXIT  (* done *)
	   END ;
	END ;
	OutText.PackedLen := SHORTCARD( CurOut ) ;
	IF CurOut <= HIGH(OutText.PackedStr) THEN
	   OutText.PackedStr[ CurOut ] := 0C ;  (* ensure an end of string *)
	END ;
    END Pack ;

PROCEDURE UnPack( VAR InText : PackedStrType;	(* VAR here for pass by ref usage *)
		  VAR OutText: ARRAY OF CHAR;
		      NoBits : CARDINAL  ) ;
    VAR
	Need, Limit	: CARDINAL ;
	BitsRemaining	: CARDINAL ;
	CurIn, CurOut	: CARDINAL ;
	Result		: CARDINAL ;  (* used as a BYTE *)
	code		: CARDINAL ;  (* used as a BYTE *)
	Mask		: CARDINAL ;

    TYPE  FinalMaskType = ARRAY[5..8] OF CARDINAL ;
    CONST FinalMask = FinalMaskType ( 001FH, 003FH, 007FH, 00FFH );

    BEGIN
	CurOut := 0 ;
	Mask   := FinalMask[ NoBits ] ;
	CurIn  := 0 ;
	Limit := CARDINAL( InText.PackedLen ) ;
	BitsRemaining := 8 ;
	code := ORD( InText.PackedStr[ CurIn ] ) ;
	INC( CurIn ) ;
	LOOP
	   Need := NoBits ;
	   Result := 0 ;
	   LOOP
		IF BitsRemaining >= Need THEN
		   (* current code fullfills our need *)
		   IF Need = 0 THEN  EXIT  END ;
		   (* take what we need *)
		   DEC( BitsRemaining, Need ) ;
		   Result := CARDINAL(BITSET( Result ) + BITSET( code >> BitsRemaining) ) ;
		   (* and leave the rest *)
		   code := CARDINAL( BITSET(code) * BITSET(PackMask[BitsRemaining]) ) ;
		   EXIT ;
		END ;
		(* we need more than current code *)
		IF BitsRemaining > 0 THEN
		   (* take what there is *)
		   DEC( Need, BitsRemaining ) ;
		   Result := CARDINAL( BITSET( Result ) + BITSET( code << Need ) ) ;
		END ;
		IF CurIn >= Limit THEN
		   (* end of buffer reached *)
		   BitsRemaining := 0 ;
		   IF Need = NoBits THEN  Result := 0  END ;
		   EXIT ;
		END ;
		IF CurIn >= Limit THEN
		   code := 0 ;
		ELSE
		   code := ORD( InText.PackedStr[ CurIn ] )
		END ;
		INC( CurIn ) ;
		BitsRemaining := 8 ;
	   END ;
	   OutText[ CurOut ] := VAL(CHAR, CARDINAL(BITSET(Result) * BITSET(Mask)) ) ;
	   INC( CurOut ) ;
	   IF ((CurIn >= Limit) AND (BitsRemaining = 0)) OR (CurOut > HIGH(OutText)) THEN
		EXIT  (* done *)
	   END ;
	END ;
	IF CurOut <= HIGH(OutText) THEN
	   OutText[ CurOut ] := 0C ;  (* ensure end of string *)
	END ;
    END UnPack ;

PROCEDURE Encode( VAR InBytes : ARRAY OF BYTE;		(* not modified -- pass by value *)
		  VAR OutBytes: ARRAY OF BYTE;
		      InLen   : CARDINAL;
		  VAR OutLen  : CARDINAL ) ;
   VAR
	I, J : CARDINAL ;
	putcount : INTEGER ;
	bitbuf	 : CARDINAL;

(* #define	RightBits(n, x)	((x) & ((1U << (n)) - 1U)) *)
PROCEDURE RightBits(n : INTEGER; x : CARDINAL) : BITSET ;
    BEGIN
	RETURN  BITSET(x) * BITSET( (1 << n) - 1)
    END RightBits ;

PROCEDURE putbits( n : INTEGER; nibble : CARDINAL) ;
    BEGIN
	WHILE ( n >= putcount ) DO
		DEC( n, putcount );
		bitbuf := CARDINAL( BITSET(bitbuf) + RightBits( putcount, nibble >> CARDINAL(n) ) );
		OutBytes[ OutLen ] := BYTE(bitbuf) ;
		bitbuf := 0;
		putcount := 8;
		INC( OutLen );
	END ;
	DEC( putcount, n );
	bitbuf := CARDINAL( BITSET(bitbuf) + BITSET(CARDINAL(RightBits(n,nibble)) << CARDINAL(putcount)) );
    END putbits ;

   BEGIN
   	OutLen := 0 ;
	putcount := 8;
	bitbuf := 0;
	FOR I := 0 TO InLen-1 DO
	    J := ORD( InBytes[I] ) ;
	    putbits( CodeLen[J], CodeTable[J] ) ;
	END ;
	putbits( 7, 0 ) ;	(* flush out last bits *)

(*<Debug*)
	INC(TotalIn, LONGCARD(InLen)) ;
	INC(TotalOut, LONGCARD(OutLen));
(*Debug>*)
   END Encode ;

PROCEDURE Decode( VAR InBytes : ARRAY OF BYTE;		(* not modified -- pass by value *)
		  VAR OutBytes: ARRAY OF BYTE;
		      OutLen  : CARDINAL ) ;
   VAR
	I, J     : CARDINAL ;
	InPos    : CARDINAL ;
	getcount : INTEGER ;
	bitbuf	 : CARDINAL;
	Bits	 : POINTER TO BITSET ;

PROCEDURE getbit() : BOOLEAN ;
    BEGIN
	DEC(getcount);
	IF ( getcount >= 0 ) THEN
		RETURN CARDINAL(getcount) IN Bits^
	END ;
	getcount := 7;
	bitbuf := CARDINAL( InBytes[InPos] ) ;
	INC( InPos ) ;

	RETURN CARDINAL(getcount) IN Bits^
    END getbit ;

   BEGIN
	getcount := 0;
	InPos    := 0;
	bitbuf   := 0;
	Bits     := ADR( bitbuf ) ;
	FOR I := 0 TO OutLen-1 DO
	   J := DecodeTableRoot;
	   WHILE ( J >= N ) DO
		IF ( getbit() ) THEN
			J := DecodeTable[J].Right;
		ELSE
			J := DecodeTable[J].Left;
		END ;
	   END ;
	   OutBytes[I] := BYTE(J) ;
	END ;
   END Decode ;

(*----------------------------------------------------------------------------
IMPORTANT:
procedures InitHuffCodeTable and InitHuffDecodeTable are generated by the
program  BUILDHUF.

Usage of BUILDHUF:    BUILDHUF <datafile> <resultfile>

The <datafile> is a collection of statistics that has two columns,
the first is the byte code and the second is the frequency count.
----------------------------------------------------------------------------*)

PROCEDURE InitHuffCodeTable ;
   BEGIN
	CodeTable[  0] :=    0H;	CodeLen[  0] :=  1;
	CodeTable[  1] :=   0FH;	CodeLen[  1] :=  4;
	CodeTable[  2] :=   17H;	CodeLen[  2] :=  5;
	CodeTable[  3] :=   36H;	CodeLen[  3] :=  6;
	CodeTable[  4] :=   30H;	CodeLen[  4] :=  6;
	CodeTable[  5] :=   25H;	CodeLen[  5] :=  6;
	CodeTable[  6] :=   24H;	CodeLen[  6] :=  6;
	CodeTable[  7] :=   28H;	CodeLen[  7] :=  6;
	CodeTable[  8] :=   32H;	CodeLen[  8] :=  6;
	CodeTable[  9] :=   2DH;	CodeLen[  9] :=  6;
	CodeTable[ 10] :=   76H;	CodeLen[ 10] :=  7;
	CodeTable[ 11] :=   62H;	CodeLen[ 11] :=  7;
	CodeTable[ 12] :=   55H;	CodeLen[ 12] :=  7;
	CodeTable[ 13] :=   52H;	CodeLen[ 13] :=  7;
	CodeTable[ 14] :=   47H;	CodeLen[ 14] :=  7;
	CodeTable[ 15] :=   42H;	CodeLen[ 15] :=  7;
	CodeTable[ 16] :=   44H;	CodeLen[ 16] :=  7;
	CodeTable[ 17] :=   40H;	CodeLen[ 17] :=  7;
	CodeTable[ 18] :=   41H;	CodeLen[ 18] :=  7;
	CodeTable[ 19] :=   45H;	CodeLen[ 19] :=  7;
	CodeTable[ 20] :=  0EEH;	CodeLen[ 20] :=  8;
	CodeTable[ 21] :=  0E9H;	CodeLen[ 21] :=  8;
	CodeTable[ 22] :=  0EAH;	CodeLen[ 22] :=  8;
	CodeTable[ 23] :=  0E5H;	CodeLen[ 23] :=  8;
	CodeTable[ 24] :=  0E6H;	CodeLen[ 24] :=  8;
	CodeTable[ 25] :=  0E8H;	CodeLen[ 25] :=  8;
	CodeTable[ 26] :=  0E2H;	CodeLen[ 26] :=  8;
	CodeTable[ 27] :=  0E1H;	CodeLen[ 27] :=  8;
	CodeTable[ 28] :=  0DFH;	CodeLen[ 28] :=  8;
	CodeTable[ 29] :=  0DDH;	CodeLen[ 29] :=  8;
	CodeTable[ 30] :=  0DCH;	CodeLen[ 30] :=  8;
	CodeTable[ 31] :=  0D7H;	CodeLen[ 31] :=  8;
	CodeTable[ 32] :=  0D4H;	CodeLen[ 32] :=  8;
	CodeTable[ 33] :=  0D0H;	CodeLen[ 33] :=  8;
	CodeTable[ 34] :=  0CDH;	CodeLen[ 34] :=  8;
	CodeTable[ 35] :=  0CFH;	CodeLen[ 35] :=  8;
	CodeTable[ 36] :=  0C7H;	CodeLen[ 36] :=  8;
	CodeTable[ 37] :=  0B3H;	CodeLen[ 37] :=  8;
	CodeTable[ 38] :=  0B2H;	CodeLen[ 38] :=  8;
	CodeTable[ 39] :=  0ACH;	CodeLen[ 39] :=  8;
	CodeTable[ 40] :=  0ADH;	CodeLen[ 40] :=  8;
	CodeTable[ 41] :=  0A8H;	CodeLen[ 41] :=  8;
	CodeTable[ 42] :=  0AEH;	CodeLen[ 42] :=  8;
	CodeTable[ 43] :=   9FH;	CodeLen[ 43] :=  8;
	CodeTable[ 44] :=   9AH;	CodeLen[ 44] :=  8;
	CodeTable[ 45] :=  0A6H;	CodeLen[ 45] :=  8;
	CodeTable[ 46] :=   9EH;	CodeLen[ 46] :=  8;
	CodeTable[ 47] :=  1D7H;	CodeLen[ 47] :=  9;
	CodeTable[ 48] :=   8CH;	CodeLen[ 48] :=  8;
	CodeTable[ 49] :=  1DFH;	CodeLen[ 49] :=  9;
	CodeTable[ 50] :=  1BCH;	CodeLen[ 50] :=  9;
	CodeTable[ 51] :=  1ADH;	CodeLen[ 51] :=  9;
	CodeTable[ 52] :=  1C1H;	CodeLen[ 52] :=  9;
	CodeTable[ 53] :=  1C8H;	CodeLen[ 53] :=  9;
	CodeTable[ 54] :=  1C6H;	CodeLen[ 54] :=  9;
	CodeTable[ 55] :=  1A5H;	CodeLen[ 55] :=  9;
	CodeTable[ 56] :=  1AAH;	CodeLen[ 56] :=  9;
	CodeTable[ 57] :=  1ACH;	CodeLen[ 57] :=  9;
	CodeTable[ 58] :=  1A3H;	CodeLen[ 58] :=  9;
	CodeTable[ 59] :=  161H;	CodeLen[ 59] :=  9;
	CodeTable[ 60] :=  18CH;	CodeLen[ 60] :=  9;
	CodeTable[ 61] :=  162H;	CodeLen[ 61] :=  9;
	CodeTable[ 62] :=  11AH;	CodeLen[ 62] :=  9;
	CodeTable[ 63] :=  137H;	CodeLen[ 63] :=  9;
	CodeTable[ 64] :=  15FH;	CodeLen[ 64] :=  9;
	CodeTable[ 65] :=  139H;	CodeLen[ 65] :=  9;
	CodeTable[ 66] :=  152H;	CodeLen[ 66] :=  9;
	CodeTable[ 67] :=  13AH;	CodeLen[ 67] :=  9;
	CodeTable[ 68] :=  13BH;	CodeLen[ 68] :=  9;
	CodeTable[ 69] :=  10FH;	CodeLen[ 69] :=  9;
	CodeTable[ 70] :=  3ADH;	CodeLen[ 70] := 10;
	CodeTable[ 71] :=  38FH;	CodeLen[ 71] := 10;
	CodeTable[ 72] :=  136H;	CodeLen[ 72] :=  9;
	CodeTable[ 73] :=  3BDH;	CodeLen[ 73] := 10;
	CodeTable[ 74] :=  11BH;	CodeLen[ 74] :=  9;
	CodeTable[ 75] :=  392H;	CodeLen[ 75] := 10;
	CodeTable[ 76] :=  10DH;	CodeLen[ 76] :=  9;
	CodeTable[ 77] :=  393H;	CodeLen[ 77] := 10;
	CodeTable[ 78] :=  37AH;	CodeLen[ 78] := 10;
	CodeTable[ 79] :=  37BH;	CodeLen[ 79] := 10;
	CodeTable[ 80] :=  356H;	CodeLen[ 80] := 10;
	CodeTable[ 81] :=  330H;	CodeLen[ 81] := 10;
	CodeTable[ 82] :=  34CH;	CodeLen[ 82] := 10;
	CodeTable[ 83] :=  339H;	CodeLen[ 83] := 10;
	CodeTable[ 84] :=  2C6H;	CodeLen[ 84] := 10;
	CodeTable[ 85] :=  349H;	CodeLen[ 85] := 10;
	CodeTable[ 86] :=  33AH;	CodeLen[ 86] := 10;
	CodeTable[ 87] :=  270H;	CodeLen[ 87] := 10;
	CodeTable[ 88] :=  348H;	CodeLen[ 88] := 10;
	CodeTable[ 89] :=  266H;	CodeLen[ 89] := 10;
	CodeTable[ 90] :=  33BH;	CodeLen[ 90] := 10;
	CodeTable[ 91] :=  333H;	CodeLen[ 91] := 10;
	CodeTable[ 92] :=  267H;	CodeLen[ 92] := 10;
	CodeTable[ 93] :=  338H;	CodeLen[ 93] := 10;
	CodeTable[ 94] :=  2BCH;	CodeLen[ 94] := 10;
	CodeTable[ 95] :=  689H;	CodeLen[ 95] := 11;
	CodeTable[ 96] :=  739H;	CodeLen[ 96] := 11;
	CodeTable[ 97] :=  29CH;	CodeLen[ 97] := 10;
	CodeTable[ 98] :=  345H;	CodeLen[ 98] := 10;
	CodeTable[ 99] :=  34EH;	CodeLen[ 99] := 10;
	CodeTable[100] :=  2A6H;	CodeLen[100] := 10;
	CodeTable[101] :=  2C1H;	CodeLen[101] := 10;
	CodeTable[102] :=  21DH;	CodeLen[102] := 10;
	CodeTable[103] :=  263H;	CodeLen[103] := 10;
	CodeTable[104] :=  264H;	CodeLen[104] := 10;
	CodeTable[105] :=  71DH;	CodeLen[105] := 11;
	CodeTable[106] :=  73EH;	CodeLen[106] := 11;
	CodeTable[107] :=  6AEH;	CodeLen[107] := 11;
	CodeTable[108] :=  779H;	CodeLen[108] := 11;
	CodeTable[109] :=  73CH;	CodeLen[109] := 11;
	CodeTable[110] :=  778H;	CodeLen[110] := 11;
	CodeTable[111] :=  58EH;	CodeLen[111] := 11;
	CodeTable[112] :=  430H;	CodeLen[112] := 11;
	CodeTable[113] :=  580H;	CodeLen[113] := 11;
	CodeTable[114] :=  4E2H;	CodeLen[114] := 11;
	CodeTable[115] :=  54EH;	CodeLen[115] := 11;
	CodeTable[116] :=  4C5H;	CodeLen[116] := 11;
	CodeTable[117] :=  53BH;	CodeLen[117] := 11;
	CodeTable[118] :=  54FH;	CodeLen[118] := 11;
	CodeTable[119] :=  4C0H;	CodeLen[119] := 11;
	CodeTable[120] := 0E76H;	CodeLen[120] := 12;
	CodeTable[121] := 0EB1H;	CodeLen[121] := 12;
	CodeTable[122] :=  53EH;	CodeLen[122] := 11;
	CodeTable[123] := 0D36H;	CodeLen[123] := 12;
	CodeTable[124] := 1ABEH;	CodeLen[124] := 13;
	CodeTable[125] := 0EB2H;	CodeLen[125] := 12;
	CodeTable[126] := 0EB3H;	CodeLen[126] := 12;
	CodeTable[127] :=  4E3H;	CodeLen[127] := 11;
	CodeTable[128] := 0E7EH;	CodeLen[128] := 12;
	CodeTable[129] := 0D35H;	CodeLen[129] := 12;
	CodeTable[130] := 0E74H;	CodeLen[130] := 12;
	CodeTable[131] :=  988H;	CodeLen[131] := 12;
	CodeTable[132] := 0D11H;	CodeLen[132] := 12;
	CodeTable[133] := 0C6CH;	CodeLen[133] := 12;
	CodeTable[134] := 0D5EH;	CodeLen[134] := 12;
	CodeTable[135] := 0AF4H;	CodeLen[135] := 12;
	CodeTable[136] := 198AH;	CodeLen[136] := 13;
	CodeTable[137] := 1A7AH;	CodeLen[137] := 13;
	CodeTable[138] := 0CC4H;	CodeLen[138] := 12;
	CodeTable[139] := 2190H;	CodeLen[139] := 14;
	CodeTable[140] := 39FDH;	CodeLen[140] := 14;
	CodeTable[141] := 1A7BH;	CodeLen[141] := 13;
	CodeTable[142] := 1A78H;	CodeLen[142] := 13;
	CodeTable[143] := 1CEEH;	CodeLen[143] := 13;
	CodeTable[144] := 1ABFH;	CodeLen[144] := 13;
	CodeTable[145] := 2191H;	CodeLen[145] := 14;
	CodeTable[146] := 21CAH;	CodeLen[146] := 14;
	CodeTable[147] := 3816H;	CodeLen[147] := 14;
	CodeTable[148] := 1307H;	CodeLen[148] := 13;
	CodeTable[149] := 1CEFH;	CodeLen[149] := 13;
	CodeTable[150] :=  997H;	CodeLen[150] := 12;
	CodeTable[151] := 1C0AH;	CodeLen[151] := 13;
	CodeTable[152] := 1A79H;	CodeLen[152] := 13;
	CodeTable[153] := 31B4H;	CodeLen[153] := 14;
	CodeTable[154] := 198BH;	CodeLen[154] := 13;
	CodeTable[155] := 14EAH;	CodeLen[155] := 13;
	CodeTable[156] := 18DBH;	CodeLen[156] := 13;
	CodeTable[157] := 10C9H;	CodeLen[157] := 13;
	CodeTable[158] := 380CH;	CodeLen[158] := 14;
	CodeTable[159] := 0E05FH;	CodeLen[159] := 16;
	CodeTable[160] := 14EBH;	CodeLen[160] := 13;
	CodeTable[161] := 10E1H;	CodeLen[161] := 13;
	CodeTable[162] := 1A7EH;	CodeLen[162] := 13;
	CodeTable[163] := 1CFFH;	CodeLen[163] := 13;
	CodeTable[164] := 0AF5H;	CodeLen[164] := 12;
	CodeTable[165] := 1C08H;	CodeLen[165] := 13;
	CodeTable[166] :=  989H;	CodeLen[166] := 12;
	CodeTable[167] := 18D4H;	CodeLen[167] := 13;
	CodeTable[168] :=  982H;	CodeLen[168] := 12;
	CodeTable[169] := 0D34H;	CodeLen[169] := 12;
	CodeTable[170] :=  871H;	CodeLen[170] := 12;
	CodeTable[171] := 0CC7H;	CodeLen[171] := 12;
	CodeTable[172] := 0C6EH;	CodeLen[172] := 12;
	CodeTable[173] := 0E00H;	CodeLen[173] := 12;
	CodeTable[174] := 1CF6H;	CodeLen[174] := 13;
	CodeTable[175] := 0C6FH;	CodeLen[175] := 12;
	CodeTable[176] := 0CCAH;	CodeLen[176] := 12;
	CodeTable[177] := 1C09H;	CodeLen[177] := 13;
	CodeTable[178] := 0CCBH;	CodeLen[178] := 12;
	CodeTable[179] :=  984H;	CodeLen[179] := 12;
	CodeTable[180] := 14F6H;	CodeLen[180] := 13;
	CodeTable[181] := 0B02H;	CodeLen[181] := 12;
	CodeTable[182] := 31B5H;	CodeLen[182] := 14;
	CodeTable[183] := 0E05EH;	CodeLen[183] := 16;
	CodeTable[184] := 702EH;	CodeLen[184] := 15;
	CodeTable[185] :=  865H;	CodeLen[185] := 12;
	CodeTable[186] := 1C0CH;	CodeLen[186] := 13;
	CodeTable[187] := 0A7AH;	CodeLen[187] := 12;
	CodeTable[188] := 1C0DH;	CodeLen[188] := 13;
	CodeTable[189] :=  985H;	CodeLen[189] := 12;
	CodeTable[190] := 10CEH;	CodeLen[190] := 13;
	CodeTable[191] := 1A7FH;	CodeLen[191] := 13;
	CodeTable[192] := 1A6EH;	CodeLen[192] := 13;
	CodeTable[193] := 14F7H;	CodeLen[193] := 13;
	CodeTable[194] := 10CFH;	CodeLen[194] := 13;
	CodeTable[195] := 1C70H;	CodeLen[195] := 13;
	CodeTable[196] := 18D5H;	CodeLen[196] := 13;
	CodeTable[197] := 14FCH;	CodeLen[197] := 13;
	CodeTable[198] := 1A6FH;	CodeLen[198] := 13;
	CodeTable[199] :=  994H;	CodeLen[199] := 12;
	CodeTable[200] := 18D0H;	CodeLen[200] := 13;
	CodeTable[201] := 1C71H;	CodeLen[201] := 13;
	CodeTable[202] := 14FDH;	CodeLen[202] := 13;
	CodeTable[203] := 1CF7H;	CodeLen[203] := 13;
	CodeTable[204] := 1D60H;	CodeLen[204] := 13;
	CodeTable[205] := 18D1H;	CodeLen[205] := 13;
	CodeTable[206] := 21CBH;	CodeLen[206] := 14;
	CodeTable[207] :=  995H;	CodeLen[207] := 12;
	CodeTable[208] :=  873H;	CodeLen[208] := 12;
	CodeTable[209] := 0B03H;	CodeLen[209] := 12;
	CodeTable[210] := 0E70H;	CodeLen[210] := 12;
	CodeTable[211] := 0E7AH;	CodeLen[211] := 12;
	CodeTable[212] := 0E39H;	CodeLen[212] := 12;
	CodeTable[213] := 0E71H;	CodeLen[213] := 12;
	CodeTable[214] :=  866H;	CodeLen[214] := 12;
	CodeTable[215] := 0C69H;	CodeLen[215] := 12;
	CodeTable[216] := 1990H;	CodeLen[216] := 13;
	CodeTable[217] := 10C6H;	CodeLen[217] := 13;
	CodeTable[218] := 21C0H;	CodeLen[218] := 14;
	CodeTable[219] := 10C7H;	CodeLen[219] := 13;
	CodeTable[220] := 1991H;	CodeLen[220] := 13;
	CodeTable[221] := 10E4H;	CodeLen[221] := 13;
	CodeTable[222] := 1C07H;	CodeLen[222] := 13;
	CodeTable[223] := 18D6H;	CodeLen[223] := 13;
	CodeTable[224] :=  862H;	CodeLen[224] := 12;
	CodeTable[225] := 14F2H;	CodeLen[225] := 13;
	CodeTable[226] :=  986H;	CodeLen[226] := 12;
	CodeTable[227] := 0A78H;	CodeLen[227] := 12;
	CodeTable[228] := 0AF6H;	CodeLen[228] := 12;
	CodeTable[229] := 14F3H;	CodeLen[229] := 13;
	CodeTable[230] := 1C0EH;	CodeLen[230] := 13;
	CodeTable[231] := 380DH;	CodeLen[231] := 14;
	CodeTable[232] := 21C1H;	CodeLen[232] := 14;
	CodeTable[233] := 18D7H;	CodeLen[233] := 13;
	CodeTable[234] := 1C0FH;	CodeLen[234] := 13;
	CodeTable[235] := 39FCH;	CodeLen[235] := 14;
	CodeTable[236] := 1A7CH;	CodeLen[236] := 13;
	CodeTable[237] := 163CH;	CodeLen[237] := 13;
	CodeTable[238] := 163DH;	CodeLen[238] := 13;
	CodeTable[239] :=  987H;	CodeLen[239] := 12;
	CodeTable[240] := 0CC9H;	CodeLen[240] := 12;
	CodeTable[241] := 14E8H;	CodeLen[241] := 13;
	CodeTable[242] := 0D10H;	CodeLen[242] := 12;
	CodeTable[243] := 1A7DH;	CodeLen[243] := 13;
	CodeTable[244] := 0AF7H;	CodeLen[244] := 12;
	CodeTable[245] := 0E75H;	CodeLen[245] := 12;
	CodeTable[246] := 0E02H;	CodeLen[246] := 12;
	CodeTable[247] := 1C02H;	CodeLen[247] := 13;
	CodeTable[248] := 1306H;	CodeLen[248] := 13;
	CodeTable[249] :=  996H;	CodeLen[249] := 12;
	CodeTable[250] := 0CC6H;	CodeLen[250] := 12;
	CodeTable[251] := 1C03H;	CodeLen[251] := 13;
	CodeTable[252] := 0A7FH;	CodeLen[252] := 12;
	CodeTable[253] := 14E9H;	CodeLen[253] := 13;
	CodeTable[254] := 1D61H;	CodeLen[254] := 13;
	CodeTable[255] := 0B1FH;	CodeLen[255] := 12;
(*<Debug*)
	TotalIn	:= 0 ;
	TotalOut:= 0 ;
(*Debug>*)
    END InitHuffCodeTable ;

PROCEDURE InitHuffDecodeTable ;
   BEGIN
	DecodeTableRoot := 510;
	Lib.Fill(ADR(DecodeTable), SIZE(DecodeTable), 0);

	DecodeTable[256].Left :=  183 ;	DecodeTable[256].Right :=  159;
	DecodeTable[257].Left :=  184 ;	DecodeTable[257].Right :=  256;
	DecodeTable[258].Left :=  139 ;	DecodeTable[258].Right :=  145;
	DecodeTable[259].Left :=  146 ;	DecodeTable[259].Right :=  206;
	DecodeTable[260].Left :=  218 ;	DecodeTable[260].Right :=  232;
	DecodeTable[261].Left :=  153 ;	DecodeTable[261].Right :=  182;
	DecodeTable[262].Left :=  147 ;	DecodeTable[262].Right :=  257;
	DecodeTable[263].Left :=  158 ;	DecodeTable[263].Right :=  231;
	DecodeTable[264].Left :=  235 ;	DecodeTable[264].Right :=  140;
	DecodeTable[265].Left :=  258 ;	DecodeTable[265].Right :=  157;
	DecodeTable[266].Left :=  260 ;	DecodeTable[266].Right :=  161;
	DecodeTable[267].Left :=  190 ;	DecodeTable[267].Right :=  194;
	DecodeTable[268].Left :=  217 ;	DecodeTable[268].Right :=  219;
	DecodeTable[269].Left :=  221 ;	DecodeTable[269].Right :=  259;
	DecodeTable[270].Left :=  248 ;	DecodeTable[270].Right :=  148;
	DecodeTable[271].Left :=  155 ;	DecodeTable[271].Right :=  160;
	DecodeTable[272].Left :=  180 ;	DecodeTable[272].Right :=  193;
	DecodeTable[273].Left :=  197 ;	DecodeTable[273].Right :=  202;
	DecodeTable[274].Left :=  225 ;	DecodeTable[274].Right :=  229;
	DecodeTable[275].Left :=  241 ;	DecodeTable[275].Right :=  253;
	DecodeTable[276].Left :=  136 ;	DecodeTable[276].Right :=  154;
	DecodeTable[277].Left :=  261 ;	DecodeTable[277].Right :=  156;
	DecodeTable[278].Left :=  167 ;	DecodeTable[278].Right :=  196;
	DecodeTable[279].Left :=  200 ;	DecodeTable[279].Right :=  205;
	DecodeTable[280].Left :=  216 ;	DecodeTable[280].Right :=  220;
	DecodeTable[281].Left :=  223 ;	DecodeTable[281].Right :=  233;
	DecodeTable[282].Left :=  237 ;	DecodeTable[282].Right :=  238;
	DecodeTable[283].Left :=  137 ;	DecodeTable[283].Right :=  141;
	DecodeTable[284].Left :=  142 ;	DecodeTable[284].Right :=  152;
	DecodeTable[285].Left :=  162 ;	DecodeTable[285].Right :=  191;
	DecodeTable[286].Left :=  192 ;	DecodeTable[286].Right :=  198;
	DecodeTable[287].Left :=  236 ;	DecodeTable[287].Right :=  243;
	DecodeTable[288].Left :=  124 ;	DecodeTable[288].Right :=  144;
	DecodeTable[289].Left :=  151 ;	DecodeTable[289].Right :=  262;
	DecodeTable[290].Left :=  165 ;	DecodeTable[290].Right :=  177;
	DecodeTable[291].Left :=  186 ;	DecodeTable[291].Right :=  188;
	DecodeTable[292].Left :=  195 ;	DecodeTable[292].Right :=  201;
	DecodeTable[293].Left :=  263 ;	DecodeTable[293].Right :=  222;
	DecodeTable[294].Left :=  230 ;	DecodeTable[294].Right :=  234;
	DecodeTable[295].Left :=  247 ;	DecodeTable[295].Right :=  251;
	DecodeTable[296].Left :=  143 ;	DecodeTable[296].Right :=  149;
	DecodeTable[297].Left :=  264 ;	DecodeTable[297].Right :=  163;
	DecodeTable[298].Left :=  174 ;	DecodeTable[298].Right :=  203;
	DecodeTable[299].Left :=  204 ;	DecodeTable[299].Right :=  254;
	DecodeTable[300].Left :=  266 ;	DecodeTable[300].Right :=  170;
	DecodeTable[301].Left :=  265 ;	DecodeTable[301].Right :=  185;
	DecodeTable[302].Left :=  269 ;	DecodeTable[302].Right :=  208;
	DecodeTable[303].Left :=  214 ;	DecodeTable[303].Right :=  267;
	DecodeTable[304].Left :=  224 ;	DecodeTable[304].Right :=  268;
	DecodeTable[305].Left :=  131 ;	DecodeTable[305].Right :=  166;
	DecodeTable[306].Left :=  168 ;	DecodeTable[306].Right :=  270;
	DecodeTable[307].Left :=  179 ;	DecodeTable[307].Right :=  189;
	DecodeTable[308].Left :=  199 ;	DecodeTable[308].Right :=  207;
	DecodeTable[309].Left :=  226 ;	DecodeTable[309].Right :=  239;
	DecodeTable[310].Left :=  249 ;	DecodeTable[310].Right :=  150;
	DecodeTable[311].Left :=  275 ;	DecodeTable[311].Right :=  271;
	DecodeTable[312].Left :=  187 ;	DecodeTable[312].Right :=  272;
	DecodeTable[313].Left :=  227 ;	DecodeTable[313].Right :=  274;
	DecodeTable[314].Left :=  273 ;	DecodeTable[314].Right :=  252;
	DecodeTable[315].Left :=  135 ;	DecodeTable[315].Right :=  164;
	DecodeTable[316].Left :=  181 ;	DecodeTable[316].Right :=  209;
	DecodeTable[317].Left :=  228 ;	DecodeTable[317].Right :=  244;
	DecodeTable[318].Left :=  282 ;	DecodeTable[318].Right :=  255;
	DecodeTable[319].Left :=  133 ;	DecodeTable[319].Right :=  277;
	DecodeTable[320].Left :=  138 ;	DecodeTable[320].Right :=  276;
	DecodeTable[321].Left :=  250 ;	DecodeTable[321].Right :=  171;
	DecodeTable[322].Left :=  172 ;	DecodeTable[322].Right :=  175;
	DecodeTable[323].Left :=  176 ;	DecodeTable[323].Right :=  178;
	DecodeTable[324].Left :=  279 ;	DecodeTable[324].Right :=  215;
	DecodeTable[325].Left :=  278 ;	DecodeTable[325].Right :=  281;
	DecodeTable[326].Left :=  280 ;	DecodeTable[326].Right :=  240;
	DecodeTable[327].Left :=  242 ;	DecodeTable[327].Right :=  132;
	DecodeTable[328].Left :=  169 ;	DecodeTable[328].Right :=  129;
	DecodeTable[329].Left :=  284 ;	DecodeTable[329].Right :=  283;
	DecodeTable[330].Left :=  287 ;	DecodeTable[330].Right :=  285;
	DecodeTable[331].Left :=  123 ;	DecodeTable[331].Right :=  286;
	DecodeTable[332].Left :=  134 ;	DecodeTable[332].Right :=  288;
	DecodeTable[333].Left :=  173 ;	DecodeTable[333].Right :=  295;
	DecodeTable[334].Left :=  290 ;	DecodeTable[334].Right :=  289;
	DecodeTable[335].Left :=  292 ;	DecodeTable[335].Right :=  212;
	DecodeTable[336].Left :=  291 ;	DecodeTable[336].Right :=  294;
	DecodeTable[337].Left :=  246 ;	DecodeTable[337].Right :=  293;
	DecodeTable[338].Left :=  130 ;	DecodeTable[338].Right :=  245;
	DecodeTable[339].Left :=  210 ;	DecodeTable[339].Right :=  213;
	DecodeTable[340].Left :=  128 ;	DecodeTable[340].Right :=  297;
	DecodeTable[341].Left :=  120 ;	DecodeTable[341].Right :=  296;
	DecodeTable[342].Left :=  299 ;	DecodeTable[342].Right :=  121;
	DecodeTable[343].Left :=  211 ;	DecodeTable[343].Right :=  298;
	DecodeTable[344].Left :=  125 ;	DecodeTable[344].Right :=  126;
	DecodeTable[345].Left :=  112 ;	DecodeTable[345].Right :=  304;
	DecodeTable[346].Left :=  300 ;	DecodeTable[346].Right :=  302;
	DecodeTable[347].Left :=  301 ;	DecodeTable[347].Right :=  303;
	DecodeTable[348].Left :=  119 ;	DecodeTable[348].Right :=  306;
	DecodeTable[349].Left :=  305 ;	DecodeTable[349].Right :=  116;
	DecodeTable[350].Left :=  307 ;	DecodeTable[350].Right :=  309;
	DecodeTable[351].Left :=  308 ;	DecodeTable[351].Right :=  310;
	DecodeTable[352].Left :=  114 ;	DecodeTable[352].Right :=  127;
	DecodeTable[353].Left :=  311 ;	DecodeTable[353].Right :=  117;
	DecodeTable[354].Left :=  122 ;	DecodeTable[354].Right :=  314;
	DecodeTable[355].Left :=  313 ;	DecodeTable[355].Right :=  312;
	DecodeTable[356].Left :=  115 ;	DecodeTable[356].Right :=  118;
	DecodeTable[357].Left :=  315 ;	DecodeTable[357].Right :=  317;
	DecodeTable[358].Left :=  113 ;	DecodeTable[358].Right :=  316;
	DecodeTable[359].Left :=  111 ;	DecodeTable[359].Right :=  318;
	DecodeTable[360].Left :=  319 ;	DecodeTable[360].Right :=  322;
	DecodeTable[361].Left :=  320 ;	DecodeTable[361].Right :=  321;
	DecodeTable[362].Left :=  326 ;	DecodeTable[362].Right :=  323;
	DecodeTable[363].Left :=  324 ;	DecodeTable[363].Right :=  325;
	DecodeTable[364].Left :=  327 ;	DecodeTable[364].Right :=   95;
	DecodeTable[365].Left :=  328 ;	DecodeTable[365].Right :=  331;
	DecodeTable[366].Left :=  329 ;	DecodeTable[366].Right :=  330;
	DecodeTable[367].Left :=  107 ;	DecodeTable[367].Right :=  332;
	DecodeTable[368].Left :=  333 ;	DecodeTable[368].Right :=  337;
	DecodeTable[369].Left :=  334 ;	DecodeTable[369].Right :=  336;
	DecodeTable[370].Left :=  335 ;	DecodeTable[370].Right :=  105;
	DecodeTable[371].Left :=  339 ;	DecodeTable[371].Right :=   96;
	DecodeTable[372].Left :=  338 ;	DecodeTable[372].Right :=  341;
	DecodeTable[373].Left :=  106 ;	DecodeTable[373].Right :=  340;
	DecodeTable[374].Left :=  109 ;	DecodeTable[374].Right :=  343;
	DecodeTable[375].Left :=  342 ;	DecodeTable[375].Right :=  344;
	DecodeTable[376].Left :=  110 ;	DecodeTable[376].Right :=  108;
	DecodeTable[377].Left :=  345 ;	DecodeTable[377].Right :=  347;
	DecodeTable[378].Left :=  346 ;	DecodeTable[378].Right :=  102;
	DecodeTable[379].Left :=  348 ;	DecodeTable[379].Right :=  350;
	DecodeTable[380].Left :=  349 ;	DecodeTable[380].Right :=  103;
	DecodeTable[381].Left :=   89 ;	DecodeTable[381].Right :=   92;
	DecodeTable[382].Left :=  104 ;	DecodeTable[382].Right :=  351;
	DecodeTable[383].Left :=   87 ;	DecodeTable[383].Right :=  352;
	DecodeTable[384].Left :=   97 ;	DecodeTable[384].Right :=  353;
	DecodeTable[385].Left :=  355 ;	DecodeTable[385].Right :=  354;
	DecodeTable[386].Left :=  100 ;	DecodeTable[386].Right :=  356;
	DecodeTable[387].Left :=   94 ;	DecodeTable[387].Right :=  357;
	DecodeTable[388].Left :=  358 ;	DecodeTable[388].Right :=  101;
	DecodeTable[389].Left :=   84 ;	DecodeTable[389].Right :=  359;
	DecodeTable[390].Left :=  363 ;	DecodeTable[390].Right :=  360;
	DecodeTable[391].Left :=   81 ;	DecodeTable[391].Right :=  361;
	DecodeTable[392].Left :=  362 ;	DecodeTable[392].Right :=   91;
	DecodeTable[393].Left :=   93 ;	DecodeTable[393].Right :=   83;
	DecodeTable[394].Left :=   86 ;	DecodeTable[394].Right :=   90;
	DecodeTable[395].Left :=  364 ;	DecodeTable[395].Right :=   98;
	DecodeTable[396].Left :=   88 ;	DecodeTable[396].Right :=   85;
	DecodeTable[397].Left :=   82 ;	DecodeTable[397].Right :=  365;
	DecodeTable[398].Left :=   99 ;	DecodeTable[398].Right :=  366;
	DecodeTable[399].Left :=   80 ;	DecodeTable[399].Right :=  367;
	DecodeTable[400].Left :=   78 ;	DecodeTable[400].Right :=   79;
	DecodeTable[401].Left :=  368 ;	DecodeTable[401].Right :=  369;
	DecodeTable[402].Left :=  370 ;	DecodeTable[402].Right :=   71;
	DecodeTable[403].Left :=   75 ;	DecodeTable[403].Right :=   77;
	DecodeTable[404].Left :=  371 ;	DecodeTable[404].Right :=  372;
	DecodeTable[405].Left :=  374 ;	DecodeTable[405].Right :=  373;
	DecodeTable[406].Left :=  375 ;	DecodeTable[406].Right :=   70;
	DecodeTable[407].Left :=  376 ;	DecodeTable[407].Right :=   73;
	DecodeTable[408].Left :=  377 ;	DecodeTable[408].Right :=   76;
	DecodeTable[409].Left :=  378 ;	DecodeTable[409].Right :=   69;
	DecodeTable[410].Left :=   62 ;	DecodeTable[410].Right :=   74;
	DecodeTable[411].Left :=  379 ;	DecodeTable[411].Right :=  380;
	DecodeTable[412].Left :=  382 ;	DecodeTable[412].Right :=  381;
	DecodeTable[413].Left :=   72 ;	DecodeTable[413].Right :=   63;
	DecodeTable[414].Left :=  383 ;	DecodeTable[414].Right :=   65;
	DecodeTable[415].Left :=   67 ;	DecodeTable[415].Right :=   68;
	DecodeTable[416].Left :=  384 ;	DecodeTable[416].Right :=  385;
	DecodeTable[417].Left :=   66 ;	DecodeTable[417].Right :=  386;
	DecodeTable[418].Left :=  387 ;	DecodeTable[418].Right :=   64;
	DecodeTable[419].Left :=  388 ;	DecodeTable[419].Right :=   59;
	DecodeTable[420].Left :=   61 ;	DecodeTable[420].Right :=  389;
	DecodeTable[421].Left :=   60 ;	DecodeTable[421].Right :=  390;
	DecodeTable[422].Left :=  391 ;	DecodeTable[422].Right :=  392;
	DecodeTable[423].Left :=  393 ;	DecodeTable[423].Right :=  394;
	DecodeTable[424].Left :=  395 ;	DecodeTable[424].Right :=   58;
	DecodeTable[425].Left :=  396 ;	DecodeTable[425].Right :=   55;
	DecodeTable[426].Left :=  397 ;	DecodeTable[426].Right :=  398;
	DecodeTable[427].Left :=   56 ;	DecodeTable[427].Right :=  399;
	DecodeTable[428].Left :=   57 ;	DecodeTable[428].Right :=   51;
	DecodeTable[429].Left :=   50 ;	DecodeTable[429].Right :=  400;
	DecodeTable[430].Left :=  401 ;	DecodeTable[430].Right :=   52;
	DecodeTable[431].Left :=   54 ;	DecodeTable[431].Right :=  402;
	DecodeTable[432].Left :=   53 ;	DecodeTable[432].Right :=  403;
	DecodeTable[433].Left :=  404 ;	DecodeTable[433].Right :=  405;
	DecodeTable[434].Left :=  406 ;	DecodeTable[434].Right :=   47;
	DecodeTable[435].Left :=  407 ;	DecodeTable[435].Right :=   49;
	DecodeTable[436].Left :=  408 ;	DecodeTable[436].Right :=  409;
	DecodeTable[437].Left :=   48 ;	DecodeTable[437].Right :=  410;
	DecodeTable[438].Left :=  411 ;	DecodeTable[438].Right :=  412;
	DecodeTable[439].Left :=   44 ;	DecodeTable[439].Right :=  413;
	DecodeTable[440].Left :=  414 ;	DecodeTable[440].Right :=  415;
	DecodeTable[441].Left :=   46 ;	DecodeTable[441].Right :=   43;
	DecodeTable[442].Left :=   45 ;	DecodeTable[442].Right :=  416;
	DecodeTable[443].Left :=   41 ;	DecodeTable[443].Right :=  417;
	DecodeTable[444].Left :=   39 ;	DecodeTable[444].Right :=   40;
	DecodeTable[445].Left :=   42 ;	DecodeTable[445].Right :=  418;
	DecodeTable[446].Left :=  419 ;	DecodeTable[446].Right :=  420;
	DecodeTable[447].Left :=   38 ;	DecodeTable[447].Right :=   37;
	DecodeTable[448].Left :=  421 ;	DecodeTable[448].Right :=   36;
	DecodeTable[449].Left :=  422 ;	DecodeTable[449].Right :=   34;
	DecodeTable[450].Left :=  423 ;	DecodeTable[450].Right :=   35;
	DecodeTable[451].Left :=   33 ;	DecodeTable[451].Right :=  424;
	DecodeTable[452].Left :=  425 ;	DecodeTable[452].Right :=  426;
	DecodeTable[453].Left :=   32 ;	DecodeTable[453].Right :=  427;
	DecodeTable[454].Left :=  428 ;	DecodeTable[454].Right :=   31;
	DecodeTable[455].Left :=   30 ;	DecodeTable[455].Right :=   29;
	DecodeTable[456].Left :=  429 ;	DecodeTable[456].Right :=   28;
	DecodeTable[457].Left :=  430 ;	DecodeTable[457].Right :=   27;
	DecodeTable[458].Left :=   26 ;	DecodeTable[458].Right :=  431;
	DecodeTable[459].Left :=  432 ;	DecodeTable[459].Right :=   23;
	DecodeTable[460].Left :=   24 ;	DecodeTable[460].Right :=  433;
	DecodeTable[461].Left :=   25 ;	DecodeTable[461].Right :=   21;
	DecodeTable[462].Left :=   22 ;	DecodeTable[462].Right :=  434;
	DecodeTable[463].Left :=   20 ;	DecodeTable[463].Right :=  435;
	DecodeTable[464].Left :=   17 ;	DecodeTable[464].Right :=   18;
	DecodeTable[465].Left :=   15 ;	DecodeTable[465].Right :=  436;
	DecodeTable[466].Left :=   16 ;	DecodeTable[466].Right :=   19;
	DecodeTable[467].Left :=  437 ;	DecodeTable[467].Right :=   14;
	DecodeTable[468].Left :=  438 ;	DecodeTable[468].Right :=  439;
	DecodeTable[469].Left :=  440 ;	DecodeTable[469].Right :=  441;
	DecodeTable[470].Left :=   13 ;	DecodeTable[470].Right :=  442;
	DecodeTable[471].Left :=  443 ;	DecodeTable[471].Right :=   12;
	DecodeTable[472].Left :=  444 ;	DecodeTable[472].Right :=  445;
	DecodeTable[473].Left :=  446 ;	DecodeTable[473].Right :=  447;
	DecodeTable[474].Left :=   11 ;	DecodeTable[474].Right :=  448;
	DecodeTable[475].Left :=  449 ;	DecodeTable[475].Right :=  450;
	DecodeTable[476].Left :=  451 ;	DecodeTable[476].Right :=  452;
	DecodeTable[477].Left :=  453 ;	DecodeTable[477].Right :=  454;
	DecodeTable[478].Left :=  455 ;	DecodeTable[478].Right :=  456;
	DecodeTable[479].Left :=  457 ;	DecodeTable[479].Right :=  458;
	DecodeTable[480].Left :=  459 ;	DecodeTable[480].Right :=  460;
	DecodeTable[481].Left :=  461 ;	DecodeTable[481].Right :=  462;
	DecodeTable[482].Left :=   10 ;	DecodeTable[482].Right :=  463;
	DecodeTable[483].Left :=  464 ;	DecodeTable[483].Right :=  465;
	DecodeTable[484].Left :=  466 ;	DecodeTable[484].Right :=  467;
	DecodeTable[485].Left :=    6 ;	DecodeTable[485].Right :=    5;
	DecodeTable[486].Left :=  468 ;	DecodeTable[486].Right :=  469;
	DecodeTable[487].Left :=    7 ;	DecodeTable[487].Right :=  470;
	DecodeTable[488].Left :=  471 ;	DecodeTable[488].Right :=  472;
	DecodeTable[489].Left :=  473 ;	DecodeTable[489].Right :=    9;
	DecodeTable[490].Left :=    4 ;	DecodeTable[490].Right :=  474;
	DecodeTable[491].Left :=    8 ;	DecodeTable[491].Right :=  475;
	DecodeTable[492].Left :=  476 ;	DecodeTable[492].Right :=  477;
	DecodeTable[493].Left :=    3 ;	DecodeTable[493].Right :=  478;
	DecodeTable[494].Left :=  479 ;	DecodeTable[494].Right :=  480;
	DecodeTable[495].Left :=  481 ;	DecodeTable[495].Right :=  482;
	DecodeTable[496].Left :=  483 ;	DecodeTable[496].Right :=  484;
	DecodeTable[497].Left :=  485 ;	DecodeTable[497].Right :=  486;
	DecodeTable[498].Left :=  487 ;	DecodeTable[498].Right :=  488;
	DecodeTable[499].Left :=  489 ;	DecodeTable[499].Right :=    2;
	DecodeTable[500].Left :=  490 ;	DecodeTable[500].Right :=  491;
	DecodeTable[501].Left :=  492 ;	DecodeTable[501].Right :=  493;
	DecodeTable[502].Left :=  494 ;	DecodeTable[502].Right :=  495;
	DecodeTable[503].Left :=  496 ;	DecodeTable[503].Right :=  497;
	DecodeTable[504].Left :=  498 ;	DecodeTable[504].Right :=  499;
	DecodeTable[505].Left :=  500 ;	DecodeTable[505].Right :=  501;
	DecodeTable[506].Left :=  502 ;	DecodeTable[506].Right :=    1;
	DecodeTable[507].Left :=  503 ;	DecodeTable[507].Right :=  504;
	DecodeTable[508].Left :=  505 ;	DecodeTable[508].Right :=  506;
	DecodeTable[509].Left :=  507 ;	DecodeTable[509].Right :=  508;
	DecodeTable[510].Left :=    0 ;	DecodeTable[510].Right :=  509;
    END InitHuffDecodeTable ;

END BitOps .