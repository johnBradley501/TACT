// copyright (c) 1995 John Bradley

/* Licensed under the Apache License, Version 2.0 (the "License");             */
/* you may not use this file except in compliance with the License.            */
/* You may obtain a copy of the License at                                     */
/* http://www.apache.org/licenses/LICENSE-2.0                                  */
/*                                                                             */
/* Unless required by applicable law or agreed to in writing, software         */
/* distributed under the License is distributed on an "AS IS" BASIS,           */
/* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.    */
/* See the License for the specific language governing permissions and         */
/* limitations under the License.                                              */

#include <string.h>
#include <stdio.h>
#include <time.h>
#include "config.h"
#include "tools.h"
#include "etype.h"
//#include "defines.h"
#define PNE int //here's the kludge again
#include "sgmlfnsm.h"

#include "resource.h"
#include "utils.h"
#include "charxlat.h"
#include "wordbase.h"
#include "vm.h"
#include "dynamic.h"
#include "hyperdat.h"

// thanks to Lidio Presutti for the models (in Modula-II) for several
// procedures in here.

HRecPntr NilHRP = {0,0};

// packed string code
unsigned PackMask[9] = { 0x0000, 0x0001, 0x0003, 0x0007, 0x000F, 0x001F, 0x003F,
								 0x007F, 0x00FF };


void PackStr(UNCH *in, UNCH *out, unsigned short nbits){
	unsigned CurOut = 1, CurIn = 0, Limit = ustrlen(in), br = 0, code = 0;
//	out[0] = Limit;
	while(1){
		unsigned Need = 8, Result = 0;
		while(1){
			if (br >= Need) {
				if (Need == 0) break;
				br -= Need;
				Result = Result | (code >> br);
				code = code & PackMask[br];
				break;
			}
			if (br > 0) {
				Need -= br;
				code = code << Need;
				Result = Result | code;
			}
			if (CurIn >= Limit) { br = 0; if (Need == 8) Result = 0; break;}
			if (CurIn >= Limit) code = 0; else code = in[CurIn];
			CurIn++;
			br = nbits;
		}
	out[CurOut++] = Result & 255;
	if (((CurIn >= Limit) && (br == 0)) || (CurOut > 255)) break;
	}
	out[0] = CurOut-1;
	out[CurOut] = 0;
} ;

void UnpackStr(UNCH *in, UNCH *out, unsigned short bits){
	unsigned CurOut = 0,	Mask = PackMask[bits],	CurIn = 1, Limit = in[0];
	unsigned br = 8, code = in[CurIn++], Need, Result;
	while(1){
		Need = bits;
		Result = 0;
		while(1){
			if (br >= Need){
				if (Need == 0) break;
				br -= Need;
				Result = Result | (code >> br);
				code = code & PackMask[br];
			}
			if (CurIn >= Limit) { br = 0; if (Need == bits) Result = 0; break; }
			if (CurIn >= Limit) code = 0;
			else code = in[CurIn];
			CurIn++;
			br = 8;
		}
		out[CurOut++] = Result & Mask;
		if ((CurIn >= Limit)&& (br == 0)) break;
	}
	out[CurOut] = 0;
} ;

int PackedStrCompare(UNCH *a, UNCH *b){
	unsigned pa = a[0], pb = b[0],l;
	if (pa < pb) l = pa; else l = pb;
	int idx = memcmp(&a[1], &b[1], l);
	if (idx < l) return (a[idx] < b[idx]) ? -1 : 1;
	else if (pa == pb) return 0;
	else return pa < pb ? -1 : 1;
}

// Huffman code

#define N 256
struct NodeTypes {
	unsigned Left, Right;
};

//WriteHuff Output

//CodeTable:
/*RES OLD NAR 4
0 15 23 54 48 37 36 40 50 45
118 98 85 82 71 66 68 64 65 69
238 233 234 229 230 232 226 225 223 221
220 215 212 208 205 207 199 179 178 172
173 168 174 159 154 166 158 471 140 479
444 429 449 456 454 421 426 428 419 353
396 354 282 311 351 313 338 314 315 271
941 911 310 957 283 914 269 915 890 891
854 816 844 825 710 841 826 624 840 614
827 819 615 824 700 1673 1849 668 837 846
678 705 541 611 612 1821 1854 1710 1913 1852
1912 1422 1072 1408 1250 1358 1221 1339 1359 1216
3702 3761 1342 3382 6846 3762 3763 1251 3710 3381
3700 2440 3345 3180 3422 2804 6538 6778 3268 8592
14845 6779 6776 7406 6847 8593 8650 14358 4871 7407
2455 7178 6777 12724 6539 5354 6363 4297 14348 57439
5355 4321 6782 7423 2805 7176 2441 6356 2434 3380
2161 3271 3182 3584 7414 3183 3274 7177 3275 2436
5366 2818 12725 57438 28718 2149 7180 2682 7181 2437
4302 6783 6766 5367 4303 7280 6357 5372 6767 2452
6352 7281 5373 7415 7520 6353 8651 2453 2163 2819
3696 3706 3641 3697 2150 3177 6544 4294 8640 4295
6545 4324 7175 6358 2146 5362 2438 2680 2806 5363
7182 14349 8641 6359 7183 14844 6780 5692 5693 2439
3273 5352 3344 6781 2807 3701 3586 7170 4870 2454
3270 7171 2687 5353 7521 2847 
*/
unsigned      *CodeTable = 0;   // Huffman codes
#define CODETABLERES /*RES REM INS*/ 4

//CodeLen:
/*RES OLD NAR 5
1025 1541 1542 1542 1542 1799 1799 1799 1799 1799
2056 2056 2056 2056 2056 2056 2056 2056 2056 2056
2056 2056 2056 2312 2312 2313 2313 2313 2313 2313
2313 2313 2313 2313 2313 2570 2569 2569 2569 2570
2570 2570 2570 2570 2570 2570 2570 2826 2571 2570
2570 2570 2826 2827 2827 2827 2827 2827 2827 2827
3084 3083 3085 2828 3084 3084 3084 3084 3341 3596
3342 3341 3597 3598 3341 3340 3597 3341 3341 4110
3341 3341 3340 3340 3084 3084 3084 3085 3340 3084
3085 4110 3087 3085 3085 3341 3341 3341 3341 3085
3341 3341 3341 3086 3084 3084 3084 3084 3341 3342
3341 3341 3340 3084 3340 3597 3342 3597 3341 3085
3340 3340 3084 3340 3085 3340 3340 3085 
*/
unsigned char *CodeLen = 0;     // numb of bits to use from CodeTable
#define CODELENRES /*RES REM INS*/ 5

//DecodeTable:
/*RES OLD NAR 6
183 159 184 256 139 145 146 206 218 232
153 182 147 257 158 231 235 140 258 157
260 161 190 194 217 219 221 259 248 148
155 160 180 193 197 202 225 229 241 253
136 154 261 156 167 196 200 205 216 220
223 233 237 238 137 141 142 152 162 191
192 198 236 243 124 144 151 262 165 177
186 188 195 201 263 222 230 234 247 251
143 149 264 163 174 203 204 254 266 170
265 185 269 208 214 267 224 268 131 166
168 270 179 189 199 207 226 239 249 150
275 271 187 272 227 274 273 252 135 164
181 209 228 244 282 255 133 277 138 276
250 171 172 175 176 178 279 215 278 281
280 240 242 132 169 129 284 283 287 285
123 286 134 288 173 295 290 289 292 212
291 294 246 293 130 245 210 213 128 297
120 296 299 121 211 298 125 126 112 304
300 302 301 303 119 306 305 116 307 309
308 310 114 127 311 117 122 314 313 312
115 118 315 317 113 316 111 318 319 322
320 321 326 323 324 325 327 95 328 331
329 330 107 332 333 337 334 336 335 105
339 96 338 341 106 340 109 343 342 344
110 108 345 347 346 102 348 350 349 103
89 92 104 351 87 352 97 353 355 354
100 356 94 357 358 101 84 359 363 360
81 361 362 91 93 83 86 90 364 98
88 85 82 365 99 366 80 367 78 79
368 369 370 71 75 77 371 372 374 373
375 70 376 73 377 76 378 69 62 74
379 380 382 381 72 63 383 65 67 68
384 385 66 386 387 64 388 59 61 389
60 390 391 392 393 394 395 58 396 55
397 398 56 399 57 51 50 400 401 52
54 402 53 403 404 405 406 47 407 49
408 409 48 410 411 412 44 413 414 415
46 43 45 416 41 417 39 40 42 418
419 420 38 37 421 36 422 34 423 35
33 424 425 426 32 427 428 31 30 29
429 28 430 27 26 431 432 23 24 433
25 21 22 434 20 435 17 18 15 436
16 19 437 14 438 439 440 441 13 442
443 12 444 445 446 447 11 448 449 450
451 452 453 454 455 456 457 458 459 460
461 462 10 463 464 465 466 467 6 5
468 469 7 470 471 472 473 9 4 474
8 475 476 477 3 478 479 480 481 482
483 484 485 486 487 488 489 2 490 491
492 493 494 495 496 497 498 499 500 501
502 1 503 504 505 506 507 508 0 509
0 0 
*/
NodeTypes     *DecodeTable = 0; // originally N..2*N-1
#define NODETYPESRES /*RES REM INS*/ 6
#define DT(n) DecodeTable[n - 256]

#define DecodeTableRoot 510

#define	RightBits(n, x)	((x) & ((1U << (n)) - 1U))

void putbits(int n, unsigned char nibble, int &putct, unsigned &bbuf, UNCH *out,
				 unsigned outl){
	while (n >= putct) {
		n -= putct;
		bbuf |= RightBits(putct, nibble >> n);
		out[outl++] = bbuf;
		bbuf = 0; putct = 8;
	}
	putct -= n;
	bbuf |= RightBits(n,nibble) << putct;
};

void HuffEncode( UNCH *in, UNCH *out, unsigned inl, unsigned &outl){
	if (!CodeTable) {
		unsigned sz;
		CodeTable = (unsigned *)ResFile->GetResNA(CODETABLERES,sz);
		CodeLen = (UNCH *)ResFile->GetResNA(CODELENRES,sz);
	}
	outl = 0;
	int putct = 8;
	unsigned bbuf = 0, i;
	for (i = 0; i < inl; i++)
		putbits(CodeLen[in[i]], CodeTable[in[i]], putct, bbuf, out, outl);
	putbits(7,0, putct, bbuf, out, outl);
};

unsigned getbit(int &getcount, UNCH *in, unsigned &inpos, unsigned &bbuf){
	if (0 < getcount--) return getcount & bbuf;
	getcount = 7;
	bbuf = in[inpos++];
	return getcount & bbuf;
}

void HuffDecode(UNCH *in, UNCH *out, unsigned outl){
	int getcount = 0;
	unsigned inpos = 0, bbuf = 0, i, j;
	if (!DecodeTable) {
		unsigned sz;
		DecodeTable = (NodeTypes *)ResFile->GetResNA(NODETYPESRES,sz);
	}
	for (i = 0; i < outl; i++){
		j = DecodeTableRoot;
		while (j >= N){
			if (getbit(getcount, in, inpos, bbuf)) j = DT(j).Right;
			else j = DT(j).Left;
		}
		out[i] = j;
	}
};

UNCH TDBIDModel[4] = {'T', 'D', 'B', '\032'};
UNCH PDBIDModel[4] = {'P', 'D', 'B', '\032'};

/*class HRecPntr {
	unsigned Rec, Idx; }; */

hfile::hfile(UNCH *name){
	memset(&data, 0, 1024);
	memset(&hdr, 0, sizeof(TDBHeaderType));
	pname = savestr(name);
	pos.Rec = 0; pos.Idx = 0;
	hfile = fopen((char *)name, "wb");
	if (hfile == 0){
		/*RES OLD MSG 593
		TDB File "%0" could not be created.
		*/
		ResFile->MsgData(name);
		ResFile->PutResError( /*RES REM INS*/ 593 );
		exit(200);
	}
};

void hfile::WriteRec(){
	unsigned amt = fwrite(&data, HYPERLENGTH, 1, hfile);
	if (amt != 1){
		/*RES OLD MSG 594
		SGML2TDB could not successfully write to file "%0"
		*/
		ResFile->MsgData(pname);
		ResFile->PutResError( /*RES REM INS*/ 594 );
		exit(200);
	}
	pos.Idx = 0; pos.Rec++;
	memset(&data,0,HYPERLENGTH);
};

unsigned hfile::FinishSection(){
	if (pos.Idx != 0) WriteRec();
	return pos.Rec;
};

void hfile::FinishTDB(){
	FinishSection();
	memcpy(&hdr, TDBIDModel, 4);
	fseek(hfile,0L,SEEK_SET);
	fwrite(&hdr,sizeof(TDBHeaderType), 1,hfile);
	fclose(hfile);
}

HRecPntr hfile::AppendSpn(void *dta, unsigned sze){
	HRecPntr hld = pos;
	UNCH *p = (UNCH *)dta;
	while ((sze + pos.Idx)>HYPERLENGTH){
		unsigned amt = HYPERLENGTH - pos.Idx;
		memcpy(&data.TextData[pos.Idx], p, amt);
		WriteRec();
		sze -= amt;
		p = &p[amt];
	}
	memcpy(&data.TextData[pos.Idx], p, sze);
	pos.Idx += sze;
	if (pos.Idx >= HYPERLENGTH) WriteRec();
	return hld;
};

void hfile::AppendChar(char c){
	data.TextData[pos.Idx++] = c;
	if (pos.Idx >= HYPERLENGTH) WriteRec();
};

HRecPntr hfile::Append(void *dta, unsigned sze){
	if ((sze + pos.Idx) > HYPERLENGTH) WriteRec();
	HRecPntr hld = pos;
	memcpy(&data.TextData[pos.Idx], dta, sze);
	pos.Idx += sze;
	if (pos.Idx >= HYPERLENGTH) WriteRec();
	return hld;
};

int hfile::InitPtrData(){
	FinishSection();
	TPtrLen = 4 ;
	TDataPos = HYPERLENGTH;
	data.dad.DataPntr[0] = HYPERLENGTH ;
	pos.Idx = 1 ; // next position to use
	return pos.Rec;
};

HRecPntr hfile::AddPtrData(void *inp, unsigned l){
	TPtrLen += 2;
	TDataPos -= l;
	if (TDataPos < TPtrLen){
		// this data will not fit on current HyperRec
		data.dad.NoDataPtrsUsed = pos.Idx - 1;
		WriteRec();
		data.dad.DataPntr[0] = HYPERLENGTH;
		TPtrLen = 6; TDataPos = HYPERLENGTH - l;
		pos.Idx = 1;
	}
	HRecPntr rslt = pos;
	data.dad.DataPntr[pos.Idx++] = TDataPos;
	memcpy(&data.TextData[TDataPos], inp, l);
	return rslt;
};

HRecPntr hfile::FinishPtrData(){
	data.dad.NoDataPtrsUsed = pos.Idx - 1;
	HRecPntr tmp = pos;
	WriteRec();
	return tmp;
} ;

HRecPntr hfile::AddToken( HRecPntr hwrd, HRecPntr text, HRecPntr logp){
	if (pos.Idx == 0){
		data.tod.BaseText = text;
		data.tod.BaseLog = logp;
	};
	HRecPntr rslt = pos;
	data.tod.TokenData[pos.Idx].HRecNo = hwrd.Rec;
	data.tod.TokenData[pos.Idx].HRecPos = (UNCH)hwrd.Idx;
	data.tod.TokenData[pos.Idx].TOffset =
						  (text.Rec - data.tod.BaseText.Rec) * HYPERLENGTH +
							text.Idx - data.tod.BaseText.Idx;
	data.tod.TokenData[pos.Idx].LOffset = (UNCH)
						  (logp.Rec - data.tod.BaseLog.Rec) * 256 +  // # Log Records +
						  logp.Idx - data.tod.BaseLog.Idx ;          // used as 1 byte number

	if ((++pos.Idx) >= HNOTOKENS)WriteRec();
	return rslt;
};

unsigned PrevHRec, NextHRec;

void hfile::AddOccur( HRecPntr d ){
	TDataPos -=OCCURRECSIZE;
	if ((TDataPos < TPtrLen) && ((pos.Idx > 1)||(TDataPos < 1))){
		data.dad.NoDataPtrsUsed = pos.Idx - 1 ;
		if (pos.Idx > 1){
			data.tyd.PrevHRec = PrevHRec ;
			data.tyd.NextHRec = NextHRec ;
			PrevHRec = pos.Rec - hdr.BeginType;
		}
		WriteRec();
		data.dad.DataPntr[0] = TYPEMAXDATAPOS;
		pos.Idx = 1;
		TPtrLen = 4; TDataPos = TYPEMAXDATAPOS - OCCURRECSIZE;
	}
	HOccurData *p = (HOccurData *)&data.TextData[TDataPos];
	p->TRecNo = d.Rec;
	p->TRecPos = d.Idx;
};

void hfile::InitTypes(){
	FinishSection(); // ensure on a new HyperRec boundary!
	data.dad.DataPntr[0] = TYPEMAXDATAPOS;
	TPtrLen  = 4 ; // will increment to proper value later
	TDataPos = TYPEMAXDATAPOS;
	pos.Idx = 1; // next position to use.
	PrevHRec = NextHRec = 0 ;
} ;

HRecPntr hfile::AddType(HTypeData &Data){
	TDBTypeData TDBtd;
	TDBtd.NoOccur = Data.NoOccur;
	PackStr(Data.Word, TDBtd.PackedWord, SortNoBitsPerChar);
	unsigned len =  TDBtd.PackedWord[0] + BASEHTYPELEN;
	TDataPos -= len;
	TPtrLen += 2;
	if(TDataPos < TPtrLen ){
		int FixUp = 1; // BOOLEAN
		// this data will not fit on current HyperRec
		data.dad.NoDataPtrsUsed = pos.Idx - 1 ;
		if(pos.Idx > 1){ // pointer values on this record
			data.tyd.PrevHRec = PrevHRec ;
			data.tyd.NextHRec = NextHRec ;
			PrevHRec = pos.Rec - hdr.BeginType ;
			FixUp = 0 ;
			WriteRec();
		}
		if(FixUp){
			// first jump back to record that needs fixing
			fseek(hfile,HYPERLENGTH * (long)(hdr.BeginType+PrevHRec),SEEK_SET);
			if ( !fread(&data, HYPERLENGTH, 1, hfile)) exit(1000);
			// fix the record and re-write
			data.tyd.NextHRec++;
			fseek(hfile,HYPERLENGTH * (long)(hdr.BeginType+PrevHRec),SEEK_SET);
			fwrite(&data, HYPERLENGTH, 1, hfile);
			// now advance again to the end, and clear data buffer.
			fseek(hfile,0,SEEK_END);
			memset(&data,0,HYPERLENGTH);
		}
		data.dad.DataPntr[0] = TYPEMAXDATAPOS;
		TPtrLen = 6; TDataPos = TYPEMAXDATAPOS - len;
		pos.Idx = 1;
	}
	long int splft = ((long int)TDataPos - (long int)TPtrLen) / OCCURRECSIZE * OCCURRECSIZE,
				spnd = ((long int)Data.NoOccur) * OCCURRECSIZE;
	NextHRec = pos.Rec - hdr.BeginType + 1;
	if( splft < spnd )
		NextHRec += ((unsigned) spnd - splft)/ MAXSPACEFOROCCURSINREC;
	HRecPntr rslt = pos;
	data.dad.DataPntr[pos.Idx++] = TDataPos;
	memcpy(&data.TextData[TDataPos],&TDBtd,len);
	return rslt;
};

HRecPntr hfile::FinishTypes(){
	data.dad.NoDataPtrsUsed = pos.Idx - 1;
	if (pos.Idx > 1){
		data.tyd.PrevHRec = PrevHRec ;
		data.tyd.NextHRec = NextHRec ;
	}
	HRecPntr rslt=pos; --rslt.Idx;
	WriteRec();
	return rslt;
} ;

hfile *TDBFile;

/*

PROCEDURE WriteMKSInfo ;  (* m.s. - March 93 - this procedure dumps mks info to
                           header record of tdb for retrieval in USEBASE *)
  VAR
    MKSFileName, InputLine : StrAny ;
    EndCode: ARRAY[0..1] OF CHAR ;
    FileID : XFileType ;
    ErrorMsg, Mode: StrAny ;
    Enough : BOOLEAN ;
    IOResult : CARDINAL ;
  BEGIN
   IF DefaultMKSUsed THEN
      Str.Copy( MKSFileName, DefaultMKSFileName ) ;
   ELSE
      Str.Copy( MKSFileName, FileData.SetupFileName ) ;
   END ;
   Utils.GetXlationType( MKSFileName, Mode ) ;
   IF Mode[0] = 0C THEN
      Str.Copy( Mode, FILEText ) ;
   END ;
   IF NOT XOpenInput( MKSFileName, MKSExtension, Mode, FileID, ErrorMsg ) THEN
      MsgString( MKSFileName, 0 ) ;
      MsgString( ErrorMsg, 0 ) ;
      PutResError( FileHeaderResource ) ;

      XClose( FileID ) ;
      RETURN ;
   END ;
   WHILE XReadLine(FileID,'!',InputLine,Enough,IOResult) DO
      EndCode[0] := 'M';
      EndCode[1] := 'K';
      AddTextToDB( EndCode, 2 );
      AddTextToDB( InputLine, 1 + Str.Length(InputLine));
   END ;
(*   EndCode[0] := 'E' ;   (* m.s. - mark end of mks info in tdb. Needed? *)
   EndCode[1] := 'M' ;
   AddtextToDB( EndCode, 2) ;
*)
   IF IOResult <> UtilsTwo.InsufficientData THEN
     UtilsTwo.IOErrorMessage(IOResult, ErrorMsg) ;
     MsgString( MKSFileName, 0 ) ;
	  MsgString( ErrorMsg, 0 ) ;
     PutResError( FileHeaderResource ) ;
   END ;
   XClose(FileID);
END WriteMKSInfo ;
*/

void VerifyRefTemplate(UNCH *in){
// I confess it -- the reftemplate checking in Makebase is more complete! j.b.
	UNCH *p = in, *q, s[256];
	int foundref = 0;
	while (0 != (q = ustrchr(p,REFDELIMID))){
		foundref = 1;
		q++;
		unsigned isz = IntToNextSortWord(q, s);
		if (tactidpresent(s) == 0){
			/*RES OLD MSG 289
			Your Reference Template contains an ill-formed Reference Name:"%0".
			*/
			q[isz] = 0;
			ResFile->MsgData( q);
			ResFile->PutResError( /*RES REM INS*/ 289 );
			exit(100);
		}
		p = q+isz;
	}
	if (!foundref){
		ResFile->MsgData(in);
		ResFile->MsgData((UNCH)REFDELIMID);
		ResFile->PutResError( /*from RefValBase */ 264 );
		exit(100);
	}
}

class XlateTableWrite: public XlateTableWriteBase{
public:
	virtual void WriteData(void * dta, unsigned sz);
};

void XlateTableWrite::WriteData(void * dta, unsigned sz){
	TDBFile->Append(dta, sz);
};

void StartTDBFile(UNCH *fname, LineCollection *&title, LineCollection *&reftemp){
	TDBFile = new hfile(fname);

	time_t t;
	time(&t);
	tm s = *localtime(&t);
	TDBHeaderType *hdr = TDBFile->Header();
	hdr->Year = s.tm_year + 1900;
	hdr->Month = s.tm_mon+1;
	hdr->Day = s.tm_mday;

	title->Start();
	UNCH *ti;
//	if (0 != (ti = title->GetLine()))ustrcpy(hdr->Title, ti);
	if (0 != (ti = title->GetLine()))memcpy(hdr->Title, ti,MAXDBTITLELENGTH);

	hdr->TDBVersion = THISTDBVERSION;

	TDBFile->AppendSpn((void *)hdr, sizeof(TDBHeaderType));

	TDBFile->AppendSpn((void *)&SimpAlphTable, sizeof(SimpAlphTable));
	TDBFile->AppendSpn((void *)&TypeOfChar, sizeof(TypeOfChar));

	XlateTableWrite xtw;
	xtw.WriteXlate(Int2Alp);
	xtw.WriteXlate(Alp2Int);

	WriteNames();

	UNCH endcode[3];
	reftemp->Start();
	if (0 != (ti = reftemp->GetLine())){
		VerifyRefTemplate(ti);
		ustrcpy(endcode,(UNCH *)"RF");
		TDBFile->AppendSpn((void *)&endcode,2);
		TDBFile->AppendSpn((void *)ti, ustrlen(ti)+1);
	}
	ustrcpy(endcode,(UNCH *)"EN");
	TDBFile->AppendSpn((void *)&endcode,2);
	TDBFile->Header()->BeginText = TDBFile->FinishSection();
} ;


