// copyright 1994 (c) John Bradley

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

#include "config.h"
#include "tools.h"
#include "resource.h"
#include "utils.h"
#include <mem.h>
#include <string.h>
#include <ctype.h>
#include <fstream.h>
#include <stdio.h>
#include <stdlib.h> // for atoi
#include "charxlat.h"

extern far resfile *ResFile;

XlateTable *Ext2Int, *Alp2Int, *Int2FAlp, *Int2Alp;
XlateText *e2i;


#define NumberChars 193
#define CharNameLength 11
#define HighCharacterCode 255
#define HighLowSize 57

typedef struct{
	UNCH codept;
	UNCH cname[CharNameLength+1];
} BaseChDataType;

typedef struct{
	UNCH Name[CharNameLength+1];
} CharNameType;

BaseChDataType SortedCharNames[NumberChars];
CharNameType CharacterNameSet[HighCharacterCode+2];
UNCH UpperCharList[HighLowSize+1];
UNCH LowerCharList[HighLowSize+1];

UNCH INTERNALText[10];
UNCH FILEText[10];
UNCH MODEText[10];


#define MaxKeyNameLen 5
#define MaxBASICEntries 52
#define MaxALTEntries 48
#define MaxSHIFTEntries 11
#define MaxCTRLEntries 48

typedef struct{
	UNCH ext;
	UNCH cde;
	UNCH name[MaxKeyNameLen+1];
	} CHARENTRY;

class ResCHARENTRYCollection: public ResCollection{
public:
	ResCHARENTRYCollection(resfile & rs, int id):
			ResCollection(rs, DataArrRes, id){}
	void GetItem(CHARENTRY& rs);
};

void ResCHARENTRYCollection::GetItem(CHARENTRY& rs){
	int sz;
	void * s=Next(sz);
	memcpy(&rs, s, sz);
};

enum COMPCOND {OK, EndOfData, ErrorOccurred};

UNCH LookupHexCode(UNCH * s){
	if (ustrlen(s) != 2) return '\0';
	UNCH b, r = 0;
	for (int i = 0; i<=1; i++){
		if ((s[i] >= '0') && (s[i] <= '9')) b = '0';
		else {if ((s[i] >= 'A') && (s[i] <= 'F')) b = 'A' - 10;
		else return '\0';};
		r = r*16 + (s[i]-b);
	};
	return r;
}

COMPCOND GetName(UNCH * wi, UNCH * id, unsigned & pos, UNCH * rslt,
			unsigned rsl, ostream & s);

class ExtCodeNames{
private:
	CHARENTRY Btb[MaxBASICEntries];
/*	CHARENTRY Atb[MaxALTEntries];
	CHARENTRY Stb[MaxSHIFTEntries];
	CHARENTRY Ctb[MaxCTRLEntries];
	UNCH SHIFTText[10];
	UNCH ALTText[10];
	UNCH CTRLText[10];  */

public:
	ExtCodeNames();
	UNCH Lookup(UNCH * n);
	BOOLEAN ExtToSeq(UNCH * in, UNCH * id, UNCH * rslt, int nrslt,ostream &s);
};
	ExtCodeNames::ExtCodeNames(){
		ResCHARENTRYCollection rc(*ResFile, 5);
		for(int i=0; i<MaxBASICEntries; i++) rc.GetItem(Btb[i]);
/*		for(i=0; i<MaxALTEntries; i++) rc.GetItem(Atb[i]);
		for(i=0; i<MaxSHIFTEntries; i++) rc.GetItem(Stb[i]);
		for(i=0; i<MaxCTRLEntries; i++) rc.GetItem(Ctb[i]);

		ResStrCollection rc2(*ResFile, 2);
		rc2.NextC(SHIFTText); // first one is to be skipped
		rc2.NextC(SHIFTText);
		rc2.NextC(ALTText);
		rc2.NextC(CTRLText);   */
	}

	UNCH ExtCodeNames::Lookup(UNCH * n){
		int u = MaxBASICEntries - 1,i,l = 0,c;
		capstr(n);
		do {
			if (u < l) return '\0';
			i = (l+u)/2;
			c = ustrcmp(n,Btb[i].name);
			if (c < 0) u = i-1; else l = i+1;}
		while (c != 0);
		if (Btb[i].ext) return '\0';
		return Btb[i].cde;
	}

BOOLEAN ExtCodeNames::ExtToSeq(UNCH * in, UNCH * id, UNCH * rslt, int nrslt,ostream &s){
	unsigned pos = 0, rpos = 0;
	rslt[0] = '\0';
	UNCH wnme[9];
	COMPCOND status;
	while (OK == (status = GetName(in,INTERNALText,pos,wnme,9,s))){
		if (rpos >= nrslt) {
			/*RES OLD MSG 30
			There are Too Many Characters.
			*/
			ResFile->ResMessage(/*RES REM INS*/ 30, s);
			return FALSE; }
		if (!wnme[1]) rslt[rpos] = wnme[0];
		else if (rslt[rpos] = Lookup(wnme)){}
		else if (rslt[rpos] = LookupHexCode(wnme)){}
		else{
			/*RES OLD MSG 35
			Character Name "%0" is not Recognized for Device %1.
			*/
			ResFile->MsgData(wnme);
			ResFile->MsgData(id);
			ResFile->ResMessage(/*RES REM INS*/ 35, s);
			return FALSE;}
		rpos++;
	}
	rslt[rpos] = '\0';
	return status == EndOfData;
} ;

void InitCharTables(){
	ResStrCollection rc(*ResFile, 4);

	int sz;
	for(int i = 0; i < NumberChars; i++){
		BaseChDataType *p = (BaseChDataType *)rc.Next(sz);
		memcpy(&SortedCharNames[i], p, sz);
	};

	for(i = 0; i <= HighCharacterCode; i++){rc.NextC(CharacterNameSet[i].Name);};

	rc.NextC(UpperCharList);
	rc.NextC(LowerCharList);

/*RES OLD DTA 3
KEYBOARD SCREEN FILE PRINTER INTERNAL MODE
*/
	ResStrCollection rc2(*ResFile, 3);
	rc2.NextC(FILEText); // ignore first one: KEYBOARDText
	rc2.NextC(FILEText); // ditto 2nd one: SCREENText
	rc2.NextC(FILEText);
	rc2.NextC(INTERNALText); // ignore: PRINTER
	rc2.NextC(INTERNALText);
	rc2.NextC(MODEText);
};

UNCH LookupIntName(UNCH * n){
	int u = NumberChars - 1,i,l = 0,c;
	if (!n[0]) return '\0';
	UNCH n1[50];
	ustrcpy(n1,n);
	capstr(n1+1);
	do {
		if (u < l) return '\0';
		i = (l+u)/2;
		c = ustrcmp(n1,SortedCharNames[i].cname);
		if (c < 0) u = i-1; else l = i+1;}
	while (c != 0);
	return SortedCharNames[i].codept;
}

COMPCOND GetName(UNCH * wi, UNCH * id, unsigned & pos, UNCH * rslt,
						unsigned rsl, ostream & s){
	unsigned i;
	rslt[0] = '\0';
	while (wi[pos]==' ')pos++;
	if (!wi[pos]) return EndOfData;

	i = 0;
	while ((wi[pos] != ' ') && (wi[pos] != '\0') && (i < (rsl-1))) {
		rslt[i] = wi[pos];
		i++; pos++;
	}
	if (i <= rsl-1) rslt[i] = '\0';
	else {
		/*RES OLD MSG 29 (from GETSEQUE.MOD)
		Character Name "%0" is Too Long in %1 Specification.
		*/
		ResFile->MsgData(wi); ResFile->MsgData(id);
		ResFile->ResMessage(/*RES REM INS*/ 29, s);
		return ErrorOccurred;
	}
	return OK;
}

BOOLEAN IntToSeq(UNCH * in, UNCH * rslt, int nrslt,ostream &s){
	unsigned pos = 0, rpos = 0;
	rslt[0] = '\0';
	UNCH wnme[CharNameLength+1];
	COMPCOND status;
	while (OK == (status = GetName(in,INTERNALText,pos,wnme,CharNameLength+1,s))){
		if (rpos >= nrslt) {
			/*RES OLD MSG 30
			There are Too Many Characters.
			*/
			ResFile->ResMessage(/*RES REM INS*/ 30, s);
			return FALSE;
		}
		if (!(rslt[rpos] = LookupIntName(wnme))){
			/*RES OLD MSG 31
			Internal Character Name "%0" is not Recognized.
			*/
			ResFile->MsgData(wnme);
			ResFile->ResMessage(/*RES REM INS*/ 31, s);
			return FALSE;
		}
		rpos++;
	}
	rslt[rpos] = '\0';
	return (status == EndOfData);
};

UNCH *ProcessSDATA(UNCH * rslt, UNCH * t, unsigned l, unsigned &intl,ostream &ers){
	UNCH *rp, *rp2, *rtn;
	rp = (UNCH *)malloc(l + 1);
	memcpy(rp, t, l);
	rp[l] = 0;

	unsigned n=0, m;
	intl = 9999;
	while (rp[n] == ' ')n++;
	if (rp[n] == 0){free(rp);rslt[0] = 0;return rslt;}
	if ((rp[n] == '#') && (rp[n+1] >= '0') && (rp[n+1] <= '9')){
		m = n+1;
		while ((rp[m]!=' ')&&(rp[m] != 0))m++;
		rp[m] = 0;
		UNCH *nmb=&rp[n+1];
		intl = unsigned(atoi((char *)nmb));
		rp2 = &rp[m+1];
	}
	else rp2 = &rp[n];
	if (!IntToSeq(rp2, rslt,256,ers))rtn = 0;
	else {
		if (intl==9999)intl = ustrlen(rslt);
		rtn = rslt;
	}
	free(rp);
	return rtn;
};

#define COMMENTCHAR '#'
#define MAXCHARSINSEQ 7

class LineData {
private:
	UNCH * inp;
	unsigned ipos;
public:
	unsigned alen;
	UNCH * rslt;
	BOOLEAN lg;
	UNCH dir;
	UNCH md;

LineData(UNCH * p){inp = p; ipos = 0;}
COMPCOND GetItem(ostream & s);
BOOLEAN eol();
}; // end of LineData

BOOLEAN LineData::eol(){
	while (inp[ipos] == ' ') ipos++;
	return (('\0' == inp[ipos]) || (COMMENTCHAR == inp[ipos]));
}

COMPCOND LineData::GetItem(ostream & s)
{
	md = ' ';
	dir = ' ';
	alen = 0;
	lg = FALSE;
	BOOLEAN pinit = TRUE, gtmd = FALSE, gtdr = FALSE;
	while(pinit){
		if (eol()) return EndOfData;
		else if ((inp[ipos] == '*') || ((inp[ipos] >= '0') && (inp[ipos] <= '9'))){
			if (gtmd) {
				/*RES OLD MSG 224
				A Second MODE Character "%0" was Given.
				*/
				ResFile->MsgData(inp[ipos]);
				ResFile->ResMessage( /*RES REM INS*/ 224 , s);
				return ErrorOccurred;};
			md = inp[ipos++];
			gtmd = TRUE;}
		else if ((inp[ipos] == '<') || (inp[ipos] == '>')) {
			if (gtdr) {
				/*RES OLD MSG 210
				You Gave the Second Direction Character: "%0".
				*/
				ResFile->MsgData(inp[ipos]);
				ResFile->ResMessage( /*RES REM INS*/ 210 , s);
				return ErrorOccurred;}
			dir = inp[ipos++];
			gtdr = TRUE;}
		else if (inp[ipos] == '~') {
			dir = '~';
			ipos++;
			return OK;}
		else pinit = FALSE;
	}
	UNCH delim = inp[ipos++];
	rslt = inp + ipos;
	unsigned ilen = ipos;
	while ((inp[ipos]) && (inp[ipos] != delim)) ipos++;
	UNCH inphold = inp[ipos];
	inp[ipos] = '\0';
	ilen = ipos - ilen;
	if (!inphold) {
		/*RES OLD MSG 27
		Delimiter "%0" is Missing.
		*/
		ResFile->MsgData(delim);
		ResFile->ResMessage( /*RES REM INS*/ 27, s);
		return ErrorOccurred;
	}
	if ((inp[ipos+1]>='0') && (inp[ipos+1]<='9')){
		lg = TRUE;
		do {
			alen = alen*10 + inp[ipos+1] - '0';
			ipos++;
		}	while ((inp[ipos+1] >= '0') && (inp[ipos+1] <= '9'));
		if (alen > MAXCHARSINSEQ){
			/*RES OLD MSG 28
			Length of %0 is Too Large.
			*/
			ResFile->MsgData(alen);
			ResFile->ResMessage(/*RES REM INS*/ 28, s);
			alen = 0;
			lg = FALSE;
			return ErrorOccurred;}
	}
	ipos++;
	return OK ;
} // end of GetItem

struct ExtSeqData {
	UNCH seq[MAXCHARSINSEQ+1];
	unsigned actlen;
	UNCH dir;
	UNCH mode;
};

BOOLEAN Line2Sequences(UNCH * inp, BOOLEAN & bl, int wseq, ExtCodeNames ecn,
							  UNCH * iseq, ExtSeqData & eseq, int seqsz, ostream & s){
	bl = FALSE;

	LineData id(inp);
	COMPCOND Status = id.GetItem(s);
	if (Status != OK){
		if (Status == EndOfData) { bl = TRUE; return TRUE;}
		return FALSE;}
	if (id.md != ' ') {
		/*RES OLD MSG 225
		Please do not Use the Mode Character "%0" in front of Internal String.
		*/
		ResFile->MsgData(id.md);
		ResFile->ResMessage( /*RES REM INS*/ 225 , s);
		return FALSE; }
	else if (id.dir == '~') {
		/*RES OLD MSG 211
		The Unspecified Character Indicator "~" cannot be Used for an Internal String.
		*/
		ResFile->ResMessage( /*RES REM INS*/ 211 , s);
		return FALSE; }
	else if (id.dir != ' '){
		/*RES OLD MSG 212
		The Direction Character "%0" cannot Appear in front of Internal String.
		*/
		ResFile->MsgData(id.dir);
		ResFile->ResMessage( /*RES REM INS*/ 212 , s);
		return FALSE; }
	else if (id.lg){
		/*RES OLD MSG 37
		This Length Field is not Permitted with this Internal String.
		*/
		ResFile->ResMessage( /*RES REM INS*/ 37, s);
		return FALSE; }
	else if (!IntToSeq(id.rslt, iseq, seqsz, s)) return FALSE;

	for(int NSeq = 0; (Status == OK) && (NSeq < wseq); NSeq++){ Status = id.GetItem(s);};
	if (Status == ErrorOccurred) return FALSE;
	if (!ecn.ExtToSeq(id.rslt, FILEText, eseq.seq, MAXCHARSINSEQ, s)) return FALSE;
	eseq.actlen = (id.lg ? id.alen : ustrlen(eseq.seq));
	eseq.mode = (id.md == ' ') ? '0': id.md;
	eseq.dir = id.dir;
	if (!id.eol()) {
		/*RES OLD MSG 39
		Extra Text has been Found on Xlation File Line.
		*/
		ResFile->ResMessage( /*RES REM INS*/ 39, s);
		return FALSE;
	};
	return TRUE;
}

int /*as BOOLEAN */ PrepareError(char *ers, UNCH * fn, int ln){
	/*RES OLD MSG 41
	File %0 (%1) %2
	*/
	ResFile->MsgData(fn);
	ResFile->MsgData(unsigned(ln));
	ResFile->MsgData((UNCH *)ers);         // erin.str()
	ResFile->ResMessage( /*RES REM INS*/ 41,cerr);
	cerr << endl;
	return TRUE;

//	BClose(FileID,IOResult);
}

/*RES OLD MSG 221
TACT has found an Incorrectly-Formed MODE Command.
*/
const int MalFormedRes = /*RES REM INS*/ 221;

/* TRUE returned means LineIsMode handled it */
BOOLEAN LineIsMode(UNCH * inp, BOOLEAN & suc, UNCH & md, UNCH * seq,
						 ExtCodeNames ecn, BOOLEAN FOUNDXDT, ostream & s){
	suc = FALSE;
	int i = 0, j = 0; UNCH t[11]; UNCH * p;
	while (inp[i] == ' ') i++;
	if (!inp[i]) return FALSE;

	for (j = 0; (j < 11) && isalpha(inp[i]); j++) t[j] = toupper(inp[i++]);
	t[j] = '\0';
	if (ustrcmp(t, MODEText)!=0) return FALSE;
	if (!FOUNDXDT) return TRUE;
	while (inp[i] == ' ') i++;
	if (!isdigit(inp[i])){
		ResFile->ResMessage(MalFormedRes, s);
		return TRUE;
		}
	md = inp[i++];

	while (inp[i] == ' ') i++;
	if (!inp[i]) {
		ResFile->ResMessage(MalFormedRes, s);
		return TRUE;
		}
	p = &inp[i];
	suc = ecn.ExtToSeq(p,FILEText, seq, MAXCHARSINSEQ, s);
	return TRUE;
}

BOOLEAN ProcessTranslationLine(UNCH * seq, ExtSeqData & exdta, ostream & s){
	if (exdta.dir == '~'){
		/*RES OLD MSG 213
		Please do not Use the "no-translation" Character "~" here.
		*/
		ResFile->ResMessage( /*RES REM INS*/ 213 , s);
		return FALSE;
	};
	if ((exdta.dir == ' ') || (exdta.dir == '<')){
		return Ext2Int->InsertXlateData(exdta.mode,'0',exdta.seq,seq,
				 ustrlen(seq),GiveError,s);
	};
	return TRUE;
}
enum XETYPE {STR,MODE,LITCOPY};

struct XlateEntryData {
	XlateEntryData*    n;
	XlateEntryData*    f;
	UNCH               c;
	XETYPE             t;
	UNCH               m;
	UNCH               l;
	UNCH               s[8];

	XlateEntryData(UNCH ch);
	XlateEntryData(UNCH ch, XlateEntryData *p);

	} ;

int /* boolean */ EqXE(XlateEntryData *p1, XlateEntryData *p2){
	if (p1==p2) return 1;
	if ((p1 == 0) || (p2 == 0)) return 0;
	return ((0 == ustrcmp(p1->s,p2->s)) && (p1->n == p2->n));
	};

 class XlateTableRec {
 public:
	XlateEntryData* dat[256];

	XlateTableRec();
	XlateEntryData* InsertEntry(UNCH * gsq);
	void EquateData();
} ;

void XlateTable::AddIfAbsent(UNCH cin, UNCH * cout){
	XlateTableRec *xp2 = md[0];
	if (xp2->dat[cin] == 0) xp2->dat[cin] = new XlateEntryData(cin);
	XlateEntryData *p = xp2->dat[cin];
	if (p->s[0] != '\0') return;
	ustrcpy(p->s, cout);
	p->l = ustrlen(cout);
	p->m = '0';
}

class RecString {
public:
  UNCH lv;
  UNCH ch;
  UNCH ln;
  UNCH sq[9];
};

void XlateTableWriteBase::DoItem(XlateEntryData *p, unsigned lvl){
	RecString tmp;
	tmp.lv = lvl;
	tmp.ch = p->c;
	tmp.ln = p->l + 1; /* "+ 1" is in MAKEBASE j.b. */
	ustrcpy(tmp.sq, p->s);
	WriteData((void *)&tmp, 4+ustrlen(tmp.sq));  //4 = 3 char data, + 0 for sq term
};

void XlateTableWriteBase::DoNext( XlateEntryData *p ){
	lvl++;
	while (p != 0){
		DoItem(p, lvl);
		if ((p->f != 0) && (EqXE(p, p->f))){DoItem(p, 256); p= p->f;}
		if (p->n != 0) DoNext(p->n);
		p = p->f;
	}
	lvl--;
} ;

//UNCH c254[2] = {254,0};



void XlateTableWriteBase::WriteXlate(XlateTable *xt){
	unsigned i;
	for (i = 0; i < 10; i++)md[i] = xt->CopyMode('0'+i);
	lvl = 1;
	XlateTableRec *tb = md[0];
	int ch;
	for (ch = 1; ch <256; ch++){
		if (tb->dat[ch] != 0) {
			if (65535u != (i = ustridx(LowerCharList, ch))){
				if (!EqXE(tb->dat[ch], tb->dat[UpperCharList[i]])) {
					DoItem(tb->dat[ch], lvl);
					if (tb->dat[ch]->n != 0) DoNext(tb->dat[ch]->n);
				}
			}
			else {
				DoItem(tb->dat[ch],lvl);
				if (65535u != (i = ustridx(UpperCharList, ch))){
					if (EqXE(tb->dat[ch], tb->dat[LowerCharList[i]]))
						DoItem(tb->dat[LowerCharList[i]], 255);
				}
				if (tb->dat[ch]->n != 0) DoNext(tb->dat[ch]->n);
			}; // if (0 == (cpt ... else ...
		};  // if (tb-<dat[ch] != 0 ...
	}; // for (ch = 1 ...
//	WriteData(&c254, 1);
	UNCH tmp[2]; tmp[0] = 254; tmp[1] = 0;
	WriteData(tmp,2);
};

void InitialTranslation(UNCH *xfilename){
	InitCharTables();
	ExtCodeNames ecn;
	extern far UNCH TACTPath[256];
	UNCH trp[256];
	BOOLEAN FOUNDXDT;
	int fldno;
//	if (xfilename==0)xfilename=savestr((UNCH *)"SGML2TDB.XDT");
	if (xfilename==0)xfilename=(UNCH *)"SGML2TDB.XDT";
	FindFileInList(xfilename, &*TACTPath, &*trp);
	if (trp[0]) { FOUNDXDT = TRUE; fldno = 1;} else {
	fprintf(stderr, "sgml2tdb could not find %s\n", xfilename);exit(1);}
//	else {
//		FindFileInList((UNCH *)"XLATTABL.DAT", &*TACTPath, &*trp);
//		if (trp[0]) { FOUNDXDT = FALSE; fldno = 2;}
//		else exit(1);
//	}
	ifstream f((char *)trp);
	int NumbModes = 0, ln = 0;
	BOOLEAN WasError = FALSE, mdhere[10];
	for (NumbModes = 0; NumbModes <= 9; NumbModes++) mdhere[NumbModes] = FALSE;
	NumbModes = 0;
	UNCH inp[256], erc[100], md, seq[MAXCHARSINSEQ];
	ExtSeqData eseq;

	Ext2Int = new XlateTable;
	while (f && f.getline(inp,256)) {
		ostrstream ers(erc, 100);
		ln++;
		BOOLEAN suc,bl;
		if (LineIsMode(inp,suc,md,seq,ecn,FOUNDXDT, ers)){
			if (!suc) WasError =PrepareError(ers.str(),trp,ln);
			else {
				if (mdhere[md - '0']) {
					/*RES OLD MSG 223
					A Second Definition for MODE "%0" was given.
					*/
					ResFile->ResMessage( /*RES REM INS*/ 223, ers);
					WasError =PrepareError(ers.str(), trp,ln);
				}
				else {
					mdhere[md - '0'] = TRUE;
					NumbModes++;
					if (!Ext2Int->InsertXlateMode(md, '0', seq, GiveError, ers))
						WasError =PrepareError(ers.str(), trp,ln);
				}
			}
		}
		else if (Line2Sequences(inp, bl, fldno, ecn, seq, eseq, MAXCHARSINSEQ, ers)){
			if ((!bl) && (!ProcessTranslationLine(seq, eseq, ers)))
				WasError =PrepareError(ers.str(),trp,ln);
		}
		else WasError = PrepareError(ers.str(),trp, ln);
	}
	if (WasError) exit(1);
	UNCH ca[2];
	ca[1] = '\0';
	for (UNCH c = ' '; c <= '~'; c++) {ca[0] = c;Ext2Int->AddIfAbsent(c, ca);}
	ca[0] = '\r';
	Ext2Int->AddIfAbsent('\n',ca); // end of line in Int is CR character
	ca[0] = '\t';
	Ext2Int->AddIfAbsent('\t',ca); // special use for tab character in dynamic.cpp

	ca[0] = '\0';
	Ext2Int->AddIfAbsent(0, ca);
// from STANDARD.CDF file 253 = 375c
//#define IntEnhOn  252
//#define IntEnhOff 253
//	Ext2Int->AddIfAbsent(IntEnhOn, ca);
//	Ext2Int->AddIfAbsent(IntEnhOff, ca);

	e2i = new XlateText(*Ext2Int);
}

/*RES OLD MSG 40
Character  Specifications Conflict.
*/
#define CONFLICTMSGRESOURCE  /*RES REM INS*/ 40


XlateEntryData::XlateEntryData(UNCH ch){
	t = STR; s[0] = '\0'; m = ' '; l = 0; n = 0; f = 0;
	c = ch;
}
XlateEntryData::XlateEntryData(UNCH ch, XlateEntryData *p){
	t = p->t; ustrcpy(s, p->s); m = p->m; l = p->l; n = p->n; f = p->f;
	c = ch;
}

XlateTableRec::XlateTableRec(){for(int ch = 0; ch <= 255; ch++) dat[ch] = 0;}

XlateTableRec* XlateTable::FindMode(UNCH mdc){
	int mdno = mdc - '0';
	if (md[mdno] == 0)
		 md[mdno] = new XlateTableRec;
	return md[mdno];
}

XlateEntryData* XlateTableRec::InsertEntry(UNCH * gsq){
	UNCH ch = gsq[0];
	XlateEntryData* p, * p1;
	if (dat[ch] == 0) {p = new XlateEntryData(ch); dat[ch] = p;}
	else p = dat[ch];
	for (int i = 1; gsq[i] != '\0'; i++){
		ch = gsq[i];
		if (p->n==0) {p1 = new XlateEntryData(ch); p = p->n = p1;}
		else p = p->n;
		while ((p->c != ch) && (p->f != 0)) p = p->f;
		if (p->c != ch) {p1 = new XlateEntryData(ch); p = p->f = p1;}
	}
	return p;
}

BOOLEAN XlateTable::InsertXlateMode(UNCH mdin, UNCH mdout,
												UNCH * seqin,
												DupHanType DupWhat,
												ostream & s){
	XlateTableRec* trc = FindMode(mdin);
	XlateEntryData* p = trc->InsertEntry(seqin);
	if ((p->s[0] == '\0') || (DupWhat == UpdateEntry)) {
		p->t = MODE;
		ustrcpy(p->s, seqin);
		p->m = mdout;}
	else if (((p->t == MODE)||(p->s[0] != '\0')) && (DupWhat == GiveError)) {
		ResFile->ResMessage(CONFLICTMSGRESOURCE, s);
		return FALSE;
		}
	return TRUE;
}

BOOLEAN XlateTable::AddLitEscSeq(UNCH mdin, UNCH *seqin, ostream &s){
	XlateTableRec* trc = FindMode(mdin);
	XlateEntryData* p = trc->InsertEntry(seqin);
	if (p->s[0] == '\0') {p->t = LITCOPY; p->s[0] = 0;}
	else {
		ResFile->ResMessage(CONFLICTMSGRESOURCE, s);
		return FALSE;
	}
	return TRUE;
};

BOOLEAN XlateTable::InsertForMode(UNCH mdin, UNCH mdout,
												UNCH * seqin, UNCH * seqout,
												unsigned glen,
												DupHanType DupWhat,
												ostream & s){
	XlateTableRec* trc = FindMode(mdin);
	XlateEntryData* p = trc->InsertEntry(seqin);
	if ((p->s[0] == '\0') || (DupWhat == UpdateEntry)) {
		p->t = STR;
		ustrcpy(p->s, seqout);
		p->m = mdout;
		p->l = glen; }
	else if ((0 != ustrcmp(p->s, seqout)) && (DupWhat == GiveError)) {
		ResFile->ResMessage(CONFLICTMSGRESOURCE, s);
		return FALSE;
		}
	return TRUE;
}

XlateTable::XlateTable(){
	for(int i = 0; i <= 9; i++) md[i] = 0;
}

BOOLEAN XlateTable::InsertXlateData(UNCH mdin, UNCH mdout,
												UNCH * seqin, UNCH * seqout,
												unsigned glen,
												DupHanType DupWhat,
												ostream & s){
	if (mdin == '*'){
		for (UNCH mode = '0'; mode <= '9'; mode++){
			if (md[mode-'0']){
				if (!InsertForMode(mode, mdout, seqin, seqout, glen, DupWhat, s))
					return FALSE;
			}
		}
	}
	else return InsertForMode(mdin, mdout, seqin, seqout, glen, DupWhat, s);
	return TRUE;
}

void HandleSub(XlateEntryData * xp){
	XlateEntryData* p = xp;
	UNCH /* boolean */ ccol[256];
	memset(ccol, FALSE, 256);
// for (int oc = 0; oc <= 255; oc++) ccol[oc] = FALSE;
	while (p != 0){ccol[p->c] = TRUE; p = p->f;}
	p = xp;
	while (p != 0) {
		UNCH * upos = ustrchr(UpperCharList, p->c),
			  * lpos = ustrchr(LowerCharList, p->c), ox;
		if ((upos != 0) || (lpos != 0)) {
			if (upos != 0) ox = *upos;
			else ox = *lpos;
		}
		if (!ccol[ox]){
			XlateEntryData* np = new XlateEntryData(ox, p);
			p->f = np;
			p = np;
			if (p->n != 0) HandleSub(p->n);
		}
		p = p->f;
	}
}

void XlateTableRec::EquateData(){
	for (int lt = 1; lt <= 255; lt++) if (dat[lt] != 0) HandleSub(dat[lt]->n);
	for (lt = 0; lt < HighLowSize; lt++){
		UNCH llt = LowerCharList[lt];
		UNCH ult = UpperCharList[lt];
		if ((dat[llt] != 0) && (dat[ult] == 0))
			dat[ult] = new XlateEntryData(ult,dat[llt]);
		else if ((dat[ult] != 0) && (dat[llt] == 0))
			dat[llt] = new XlateEntryData(llt,dat[ult]);
	}
}

void XlateTable::EquateData(){
	for (UNCH i = 0; i <= 9; i++)if (md[i] != 0) md[i]->EquateData();
}


XlateBase::XlateBase(XlateTable & XT, UNCH BC, bit256 *gdc)
{
	xt = &XT;
	bdstr[0] = BC;
	bdstr[1] = 0;
	ltstr[1] = 0;
	if (gdc==0)goodc.on(); else goodc = *gdc;
	StartXlate();
}

void XlateBase::StartXlate(){
	cq = 0;
	keep = 0;
	eod = FALSE;
	InMd = ' '; OutMd = '0'; CurMd = '0';
	hldsz = inbpos = inbsiz = outpos = lwp =crp =cwp = 0;
	outstr = &bdstr[1];
};

unsigned XlateBase::GetData(UNCH * out, unsigned outlen, unsigned &numbin)
{
	 numbin = 0;
	 if (eod) {if(out != 0) out[0] = 0; return 0;}
	 unsigned outbpos = 0, stpos = inbpos, endpos = inbpos;
	 while (outstr[outpos] != 0) {
		 if (outbpos >= outlen) return outlen;
		 if (!goodc[outstr[outpos]]) {if(out != 0)out[outbpos] = 0; return outbpos;}
		 if(out != 0)out[outbpos] = outstr[outpos];
		 outbpos++;outpos++;
	 }
/* sc: XXXXXXXXXXXXXX
						  | last written position: lwp
                | current reading position: crp
          | current writing position: cwp */

	 XlateEntryData *cqhld;
	 while(1){ /* see RETURNs below */
		if(crp < lwp) ch = sc[crp++]; // reprocessing characters received earlier
		else {
			if (crp==lwp)crp=lwp=cwp=0;
			if (inbpos >= inbsiz){
				if (0 == (inbp = GetInBuf(inbsiz))){ inbp = &zero; inbsiz = 1;}
				inbpos = 0;
            // following if was before above if in earlier version j.b.
				if (eod) {
					if ((outbpos < outlen)&&(out != 0))out[outbpos] = 0;
               numbin = endpos - stpos;
   			   return ++outbpos;
				}
			}
			ch = inbp[inbpos++];
//			numbin++;
      }
		sc[cwp++] = ch; // save character in case it needs reprocessing

/* now process the character we've just got */

		if((cq == 0) && (keep == 0)) {
         /* we're going to try to start a new chain */
			if(InMd != ' ') CurMd = InMd;
			cq = xt->FindMode(CurMd)->dat[ch];
			endpos = inbpos;
      }
		else while((cq != 0) && (ch != cq->c)) cq = cq->f;
		cqhld = cq;
		if((cq == 0) || (cq->n == 0)){
		  if ((cq != 0) && ((cq->t==LITCOPY) || (cq->t == MODE) || (cq->m != ' '))){
		  /* character was recognized within translate table, but no continuation */
			  keep = cq;
			  cwp = 0;
			  cq = 0;
		  }

		  /* We get here for
        one of two reasons: (1) no legal continuation of current
		  string from this point or (2) no legal string at all */

		  if(keep == 0){
           /* if we get here -- given ch cannot be translated */
			  crp = 1; /* try to reread, skipping one UNCH */
           /* append "bad UNCH" */
			  outstr = bdstr;
			  }
		  else if (keep->t == LITCOPY){
			  ltstr[0] = inbp[inbpos++];
			  outstr = ltstr;
			  keep = 0;
			  crp = 0;
		  }
        else {
           /* if we get here -- given ch cannot be added to current
           translation chain -- try again, asking routine to
           try re-read of all characters that haven't lead, so far,
           to a possible translation (and ending with keep UNCH we've
           just read */
			  crp = 0; /* try to reread from end of last successful match */

			  /* prepare to write out, based on this info */
			  outstr = keep->s;
			  keep = 0;
		  }
		  lwp = cwp;
		  outpos = 0;
		  while (outstr[outpos] != '\0') {
			  numbin = endpos - stpos - 1;
			  if (outbpos >= outlen) return outlen;
			  if (!goodc[outstr[outpos]]) {
				  if(out != 0)out[outbpos] = 0;
				  return outbpos;}
			  if(out != 0)out[outbpos] = outstr[outpos];
			  outbpos++; outpos++;
			  }
		  }
		else {

		  /* character was recognized within translate table */

		  if ((cq->t == MODE) || (cq->m != ' ')){
			  keep = cq;
			  cwp = 0;
			  }

		  /* now, get ready for possible next UNCH in current chain */
		  cq = cq->n;
        }
      }
	}


XlateOnInput::XlateOnInput(XlateTable & xt, UNCH BC)
	 : XlateBase(xt, BC) {ff = 0; buf = 0;}

XlateOnInput::~XlateOnInput(){
	 if (ff != 0) fclose(ff);
	 if (buf != 0) free(buf);
}

BOOLEAN XlateOnInput::Open(const UNCH * name){
	if (ff == 0) fopen((char *)name, "rb"); else return FALSE;
	if (ff == 0) return FALSE;
	if (buf == 0) buf = (UNCH *) malloc(4096);
	return TRUE;
}

UNCH * XlateOnInput::GetInBuf(unsigned & inbsize){
	inbsize = fread(buf, 1,4096, ff);
	return buf;
}

void XlateOnInput::Close(){
	if (ff != 0) fclose(ff);
}

XlateText::XlateText(XlateTable & xt, UNCH BC, bit256* gdc): XlateBase(xt, BC, gdc)
  {bufdone = 1;};

UNCH * XlateText::GetInBuf(unsigned & inbsiz)
{
	if (bufdone) {inbsiz = 0; SetEOD(); return 0;}
	inbsiz = ustrlen(buf);
	bufdone = 1;
	return buf;
};


void XlateText::DataIn(UNCH * inbuf, unsigned bfsize){
	buf = inbuf;
	bufdone = 0;
	bufsz = bfsize;
   StartXlate();
	};

unsigned int XlateText::Translate(UNCH * inbuf, UNCH * outbuf,
	  unsigned inlen, unsigned outlen)
{
	DataIn(inbuf, inlen);
	unsigned int numbin;
	GetData(outbuf, outlen, numbin);
	return numbin;
};

unsigned int XlateText::Ignore(UNCH * inbuf, unsigned inlen){
	DataIn(inbuf, inlen);
	goodc = ~goodc;
	unsigned int numbin;
	UNCH *p = 0;
	GetData(p, 32000, numbin);
	goodc = ~goodc;
	return numbin;
};
