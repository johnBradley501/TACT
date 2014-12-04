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

#include "config.h"
#include "tools.h"
#include "etype.h"
#include "defines.h"
//This is a kludge:   j.b.
//#define PNE int
#include <iostream.h>
#include <classlib/binimp.h>
#include "entity.h"
#include "adl.h"
#include "sgmlfnsm.h"
//#include "sgmlxtrn.h"
#include "parserba.h"
#include "utils.h"
#include "charxlat.h"
#include "resource.h"
#include <stdio.h>
#include <string.h>
//#include "hyperdat.h"
#include "wordbase.h"
#include "hyperdat.h"
#include "vm.h"
#include "dynamic.h"
#include "proctext.h"
#include "grammer.h"
#include "pgmbase.h"

UNCH * dtdfilename;
UNCH * epmfilename;

extern resfile *ResFile;

class paramfile {
private:
	FILE      *f;
	UNCH       GivenLine[256];
	unsigned   lno;
	int /* as boolean */ eof, rline, sfound, GetLine();
public:
	paramfile(FILE *file);
	~paramfile();
	UNCH * Section();
	UNCH * Data();
	unsigned LineNo() {return lno;}
} ;

paramfile::paramfile(FILE *file){
	f = file;
	eof = 0;
	rline = 1;
	sfound = 1;
	lno = 0;
};

paramfile::~paramfile(){fclose(f);};

int paramfile::GetLine(){
	if (eof) return 0;
	if (!rline) return 1;
	if (NULL == fgets((char *)GivenLine,256,f)){
		eof = 1;
		return 0;
	}
	UNCH *p = ustrchr(GivenLine,'\n');
	if (NULL != p)p[0] = 0;
	lno++;
	return 1;
};

UNCH * paramfile::Section(){
	if (!sfound) return NULL;
	if (!GetLine()) return NULL;
	sfound = 0;
	if (GivenLine[0] != '['){
		rline = 0;
		return NULL;
	}
	rline = 1;
	capstr(GivenLine);
	return GivenLine;
};

UNCH * paramfile::Data(){
	if (sfound) return NULL;
	if (!GetLine()) return NULL;
	if (GivenLine[0] == '['){
		rline =  0;
		sfound = 1;
		return NULL;
	}
   rline = 1;
	return GivenLine;
};

paramfile *pfile;

class myitem: public parseritem{
private:
	unsigned lno;
	UNCH work[40];
public:
	myitem(unsigned nmb, UNCH *str, unsigned lineno):parseritem(nmb,str){lno = lineno;};
	~myitem() {};
	virtual UNCH *   DisplayPosition();
};

UNCH * myitem::DisplayPosition(){
	sprintf((char *)work, "File: %s, line: %u", (char *)epmfilename, lno);
	return work;
};

class etditem: public myitem{
private:
	etd *thisetd;
public:
	etditem(unsigned nmb, UNCH *str, unsigned lineno, etd *etdptr = 0):
			 myitem(nmb,str,lineno){thisetd = etdptr;};
	etd *MyEtd(){return thisetd;}
};

class myscanner: public scanner {
	private:
		unsigned State;
		UNCH     *GivenLine;
		unsigned pos, linelen;
		ResStringLookup *slup, *elup;
	public:
		myscanner();
		~myscanner();
		virtual parseritem * getitem();
} ;

/*RES OLD DTA 33
AND APPEND ARITH BACK BEGIN BLINES CENTRE CLOSE COLLECT COMPRESS DEC DECLARE DISPLAY
ELSE END ERROR FILL FIND FOLD FOR FORMAT FRONT IF IN INC INDENT INDEX IS LENGTH
LINENO MAX MIN NL NOT NUMBER OFF ON OPEN OR OUTPUT PAD POP PREPEND REMARK
REPLACE STACK STRING SUBSTR TACTID TDB THEN THISGI TO UPPER VERIFY WHILE WORD
*/
#define STRINGSRES /*RES REM INS*/ 33
//the following item should be 1 less than the actual starting
//position in ...SYL   ... jb
#define STRINGSSTART 21

#define SINGLESOFFSET 8
#define SINGLESSTR "@=|()><~*/+-,;"

// remember that "#" is reserved as a comment character

#define ANNOUNCEELE '$'
#define ANNOUNCEVAR '%'

UNCH singlesstr[40] = SINGLESSTR;

/*RES OLD DTA 34
"<ELEMENT NAME>" "<END OF FILE>" "<NUMBER>" "<STATEMENT END>" "<STRING>"
"<UNDECLARED NAME>" "<VARIABLE NAME>"
*/
#define SCANNERENTSRES /*RES REM INS*/ 34

#define ELEMENTNAME 1
#define ENDOFFILE 2
#define NUMBER 3
#define STATEMENTEND 4
#define STRING 5
#define UNDECLAREDNAME 6
#define VARIABLENAME 7

#define FINDSTART 1
#define SKIPBLANKS 2
#define WHATISIT 3
#define COLLECTALPHA 4
#define COLLECTSTRING 5
#define PASTEND 6
#define FILEEOF 7
#define CHECKALPHA 8
#define COLLECTNUMBER 9
#define MUSTBEALPHA 10

#define COMMENTID '#'

myscanner::myscanner(){
	State = FINDSTART;
	pos = 0;
	GivenLine = &zero;
	slup = new ResStringLookup(*ResFile, STRINGSRES);
	elup = new ResStringLookup(*ResFile, SCANNERENTSRES);
};

myscanner::~myscanner(){
	delete slup;
	delete elup;
}

etd *IsElementName(UNCH * str){
	UNCH tmp[40];
	tmp[0] = 2 + ustrlen(str);
	memcpy(&tmp[1], str, tmp[0]-1);
	return etdref(tmp);
}
//=======================================================================
// structures to handle variable names
//=======================================================================
class varname {
private:
	UNCH        *nme;
	unsigned int ps;
	valtype      typ;
public:
	varname() {nme = 0; ps = 0; typ = valstr;}
	varname(UNCH *n, unsigned p, valtype t=valstr);
	~varname();

	UNCH *name() {return nme;}
	int pos() {return ps;}
	valtype type() {return typ;}

	friend int operator < (varname &a, varname &b);
	friend int operator == (varname &a, varname &b);
};

varname::varname(UNCH *n, unsigned p, valtype t){
	ps = p;
	typ = t;
	nme = savestr(n);
};

varname::~varname(){free((UNIV)nme);};

int operator < (varname &a, varname &b){
	return 0 > ustrcmp(a.nme, b.nme);
};

int operator == (varname &a, varname &b){
	return 0 == ustrcmp(a.nme, b.nme);
};

typedef TIBinarySearchTreeImp<varname> varnamestype;
typedef TIBinarySearchTreeIteratorImp<varname> varnamesit;
varnamestype *globalvars, *localvars = 0;
unsigned nolocalvars = 0;

class varitem: public myitem{
private:
	varname  *vn;
public:
	varitem(unsigned nmb, UNCH *str, unsigned lineno, varname *n):
			 myitem(nmb,str,lineno){vn = n;}
	varname *Vardata(){return vn;}
};

varname *IsVarName(varnamestype *l, UNCH *n){
	varname *t = new varname(n,0),*r;
	r = l->Find(t);
	delete t;
	return r;
};

int /*boolean*/ IsNameChar(UNCH c){
    if (isalnum(c))return 1;
    if (c == '.')return 1;
    return c == '-';
};

parseritem * myscanner::getitem(){
	UNCH work[100], strch, *tch, s[2];
	unsigned workpos;
#define EXPECTELE 1
#define EXPECTVAR 2
#define EXPECTNOTHING 0
	int specchar = EXPECTNOTHING;
	while (1) {
		switch (State) {
		case FILEEOF:
			return new myitem(ENDOFFILE, (*elup)[ENDOFFILE], 0);
		case PASTEND:
			break;
		case FINDSTART:
			while ((GivenLine[pos] == 0) || (GivenLine[pos] == COMMENTID)) {
				if (NULL == (GivenLine = pfile->Data())){
					State = FILEEOF;
					return new myitem(ENDOFFILE, (*elup)[ENDOFFILE], 0);
				}
				pos = 0;
			}
		case SKIPBLANKS:
			if ((GivenLine[pos] != ' ')&&(GivenLine[pos] != '\t')) State = WHATISIT;
			else pos++;
			specchar = EXPECTNOTHING;
			break;
		case WHATISIT:
			if ((GivenLine[pos] == 0) || (GivenLine[pos] == COMMENTID)) {
				State = FINDSTART;
				if (NULL == (GivenLine = pfile->Data()))
					State = FILEEOF;
				pos = 0;
				return new myitem(STATEMENTEND, (*elup)[STATEMENTEND], pfile->LineNo()-1);
			}
			else if (GivenLine[pos] == ANNOUNCEELE) {
				strch = GivenLine[pos++];
				specchar = EXPECTELE;
				State = MUSTBEALPHA;
			}
			else if (GivenLine[pos] == ANNOUNCEVAR) {
				strch = GivenLine[pos++];
				specchar = EXPECTVAR;
				State = MUSTBEALPHA;
			}
			else if ((isalpha(GivenLine[pos]))||(GivenLine[pos]=='\\')) {
				State = COLLECTALPHA;
				workpos = 0;
			}
			else if ((GivenLine[pos] == '"')||(GivenLine[pos] == '\'')){
				State = COLLECTSTRING;
				workpos = 0;
				strch = GivenLine[pos++];
			}
			else if (NULL != (tch = ustrchr(singlesstr, GivenLine[pos]))){
				State = SKIPBLANKS;
				work[1] = 0; work[0] = GivenLine[pos++];
				return new myitem(SINGLESOFFSET + (tch - singlesstr), work, pfile->LineNo());
			}
			else if ((GivenLine[pos]>='0')&&(GivenLine[pos]<='9') ) {
				State = COLLECTNUMBER;
				workpos = 0;
			}
			else {
				/*RES OLD MSG 587
				File %0: Unrecognized character "%1" found in line %2.
				*/
				ResFile->MsgData(epmfilename);
				ResFile->MsgData((unsigned short)GivenLine[pos]);
				ResFile->MsgData(pfile->LineNo());
				ResFile->PutResError(/*RES REM INS*/ 587);
				s[1] = 0; s[0] = GivenLine[pos];
				return new myitem(9999, s, pfile->LineNo());
			}
			break;
		case MUSTBEALPHA:
			if ((isalpha(GivenLine[pos]))||(GivenLine[pos]=='\\')) {
				State = COLLECTALPHA;
				workpos = 0;
			}
			else {
				/*RES OLD MSG 599
				File %0: A name does not follow "%1" on in line %2.
				*/
				ResFile->MsgData(epmfilename);
				ResFile->MsgData(strch);
				ResFile->MsgData(pfile->LineNo());
				ResFile->PutResError(/*RES REM INS*/ 599);
				s[1] = 0; s[0] = strch;
				return new myitem(9999, s, pfile->LineNo());
			}
			break;
		case COLLECTALPHA:
			if (IsNameChar(GivenLine[pos]))work[workpos++] = toupper(GivenLine[pos++]);
         else if (GivenLine[pos] == '\\'){
            if (GivenLine[pos+1] != 0)pos++;
            work[workpos++] = GivenLine[pos++];
         }
			else {
				work[workpos] = 0;
				State = CHECKALPHA;
			}
			break;
		case CHECKALPHA:
			etd *fndetd;
  //		basevalue *fndid;
			int rslt;
			varname *vn;
			State = SKIPBLANKS;
			if (specchar == EXPECTELE){
				if ((fndetd = IsElementName(work)) != NULL)
					return new etditem(ELEMENTNAME, work, pfile->LineNo(), fndetd);
				/*RES OLD MSG 600
				File %0: "%1" is not an element name, on line %2.
				*/
				ResFile->MsgData(epmfilename);
				ResFile->MsgData(work);
				ResFile->MsgData(pfile->LineNo());
				ResFile->PutResError(/*RES REM INS*/ 600);
				return new myitem(9999, work, pfile->LineNo());
			}
			else if (specchar == EXPECTVAR){
				if ((vn = IsVarName(globalvars,work)) != NULL)
					return new varitem(VARIABLENAME, work, pfile->LineNo(), vn);
				/*RES OLD MSG 601
				File %0: "%1" is not a global variable or TACTid name, on line %2.
				*/
				ResFile->MsgData(epmfilename);
				ResFile->MsgData(work);
				ResFile->MsgData(pfile->LineNo());
				ResFile->PutResError(/*RES REM INS*/ 601);
				return new myitem(9999, work, pfile->LineNo());
			}
			if (0 != (rslt = slup->Lookup(work)))
				return new myitem(STRINGSSTART + rslt, work, pfile->LineNo());
			else
			if ((fndetd = IsElementName(work)) != NULL)
				return new etditem(ELEMENTNAME, work, pfile->LineNo(), fndetd);
			if ((vn = IsVarName(localvars,work)) != NULL)
				return new varitem(VARIABLENAME, work, pfile->LineNo(), vn);
			if ((vn = IsVarName(globalvars,work)) != NULL)
				return new varitem(VARIABLENAME, work, pfile->LineNo(), vn);
			else
				return new myitem(UNDECLAREDNAME, work, pfile->LineNo());
		case COLLECTSTRING:
			if ((GivenLine[pos] == COMMENTID)|(GivenLine[pos] == 0)) {
				/*RES OLD MSG 584
				File %0: A string without a closing character was found on line %1
				*/
				ResFile->MsgData(epmfilename);
				ResFile->MsgData(pfile->LineNo());
				ResFile->PutResError(/*RES REM INS*/ 584);
				return new myitem(9999, work, pfile->LineNo());
			}
			if (GivenLine[pos] == strch)
			{
				pos++;
				State = SKIPBLANKS;
				work[workpos] = 0;
				return new myitem(STRING, work, pfile->LineNo());
			}
			else work[workpos++] = GivenLine[pos++];
			break;
		case COLLECTNUMBER:
			if ((GivenLine[pos]>='0')&&(GivenLine[pos]<='9') ) work[workpos++] = GivenLine[pos++];
			else {
				State = SKIPBLANKS;
				work[workpos] = 0;
				return new myitem(NUMBER, work, pfile->LineNo());
			}
			break;
		}
	}
};

class myparser: public parser {
public:
		myparser(unsigned StateDataRes, unsigned StatePntrRec, scanner *&sptr):
		   parser(StateDataRes, StatePntrRec, *&sptr) {};
		void displayerror(parseritem * item);
};

void myparser::displayerror(parseritem * item){
		  /*RES OLD MSG 585
		  %0: Parsing problems occurred when "%1" was found.
		  */
		  ResFile->MsgData(item->DisplayPosition());
		  ResFile->MsgData(item->IntStr());
		  ResFile->PutResError( /*RES REM INS*/ 585 );
}

void makefilename(UNCH *dest, UNCH *src, UNCH *ext){
	ustrcpy(dest, src);
	UNCH * e = ustrrchr(dest, '.');
	if (e != 0) ustrcpy(e,ext);
	else ustrcat(dest, ext);
}

void GetInputLines(LineCollection *&rslt){
	delete rslt;
	rslt = new LineCollection;
	UNCH *txt, inttxt[256];
	while (NULL != (txt = pfile->Data())){
		if (txt[0] != 0){
		e2i->Translate(txt, inttxt, 256 ,256);
			rslt->AddItem(inttxt);
		}}
}

void GetOneLine(LineCollection *&rslt){
	delete rslt;
	rslt = new LineCollection;
	UNCH *exttxt,dummy[256];
	do {
		if (NULL == (exttxt = pfile->Data())){
			/*RES OLD MSG 589
			File: %0, Line: %1: No data was found following a section header.
			*/
			ResFile->MsgData(epmfilename);
			ResFile->MsgData(pfile->LineNo());
			ResFile->PutResWarning( /*RES REM INS*/ 589 );
			return;
		}
	} while (exttxt[0] == 0);
	e2i->Translate(exttxt, dummy, 256,256);
	rslt->AddItem(dummy);
	while (NULL != (exttxt = pfile->Data())){
		if (exttxt[0] != 0){
			/*RES OLD MSG 590
			File: %0, Line: %1: More than one line of data found in one-line section.
			*/
			ResFile->MsgData(epmfilename);
			ResFile->MsgData(pfile->LineNo());
			ResFile->PutResWarning( /*RES REM INS*/ 590 );
		}
	}
}

valtype tstk[PGMSTACKSZ];
unsigned sp = 0;

void MkN(pgm *ppgm){
	if (tstk[sp-1] == valnumb) return;
	ppgm->Append(new pgmunop(unc2i));
	tstk[sp-1] = valnumb;
};
void MkC(pgm *ppgm){
	if (tstk[sp-1] == valstr) return;
	ppgm->Append(new pgmunop(uni2c));
	tstk[sp-1] = valstr;
};
void Mk2N(pgm *ppgm){
	MkN(ppgm);
	if (tstk[sp-2] == valnumb) return;
	ppgm->Append(new pgmunop(un2c2i));
	tstk[sp-2] = valnumb;
};
void Mk2C(pgm *ppgm){
	MkC(ppgm);
	if (tstk[sp-2] == valstr) return;
	ppgm->Append(new pgmunop(un2i2c));
	tstk[sp-2] = valstr;
};

void StkN(){tstk[sp++] = valnumb;};
void StkC(){tstk[sp++] = valstr;};

int localstrs[100], nolstrs=0;

void cleanuplocals(pgm *ppgm){
//	varnamesit i(*localvars); // bug in iterators gives one item twice j.b.
//	while(i != 0){
//	  if (i.Current()->type() == valstr) ppgm->Append(new pgmclrlcl(i.Current()->pos()));
//	  i++;
//	}
   for (int i = 0; i < nolstrs; i++) ppgm->Append(new pgmclrlcl(localstrs[i]));
   nolstrs = 0;
};

void DoCompare(pgm *ppgm, binop nc, chbinop cc){
	if ((tstk[sp-1] == valnumb)||(tstk[sp-2] == valnumb))Mk2N(ppgm);
	if (tstk[(sp--)-1] == valnumb)ppgm->Append(new pgmbinop(nc));
	else ppgm->Append(new pgmchbin(cc));
   tstk[sp-1] = valnumb;
};

void BuildAttrRef(pgm *ppgm, etd *ep, UNCH *n){
  int rslt = GetAttrNo(ep->adl, n);
  if (rslt >= 0){ppgm->Append(new pgmattrref(ep->etdgi,rslt));StkC(); }
  else {
	  /*RES OLD MSG 596
	  File %0(%1): Attribute name "%2" was not found.
	  */
	  ResFile->MsgData(epmfilename);
	  ResFile->MsgData(pfile->LineNo());
	  ResFile->MsgData(n);
	  ResFile->PutResError( /*RES REM INS*/ 596 ); // used also in pgmbase.cpp
	  exit(200);
  }
};

void BuildAttrRef2(pgm *ppgm, UNCH *n){
  ppgm->Append(new pgmattrref2(savestr(n)));StkC();
};

/*RES OLD MSG 595
%0: The name "%1" is already in use.
*/
#define NAMEINUSE /*RES REM INS*/ 595

void HandleDeclare(parseritem *item, valtype idtype, varnamestype *txt, int pos){
	varname *t = new varname(item->IntStr(), pos, idtype);
	if (0 != txt->Find(t)) {
		ResFile->MsgData(item->DisplayPosition());
		ResFile->MsgData(item->IntStr());
		ResFile->PutResError( NAMEINUSE );
		exit(100);
//		delete t;
	}
	txt->Add(t);
};

int /*boolean*/ VerifyVarForOut(varname *i){
	return (i->type() == valstr) || (i->pos() <= NumbGlobalvars);
};

pgm *initpgm;
valtype vtype[128];

void HandleElemProcs(){
   vtype[1] = valnumb; // ID 1 is the line number
	startidarray();
	valtype idtype;
	myscanner *scnr=new myscanner;;
	myparser prsr(3,2, scnr);

	prsr.startparser();
	parseritem *item;
	unsigned prod, thisidpos, idpos = 2, startlocalids = 0;
	pgm *ppgm = new pgm;
	initpgm = ppgm;
	etd *segetd = 0, *thisetd, *fetd;
	varitem *w;
	unsigned asgnno;
	int /*boolean*/ itspop, segisopen, numbeles;
	int /*boolean*/ doingglobals = 1;
   int ifstk[24], ifptr=0;
	do {
		prod = prsr.doparse(item);
//		printf("Prod: %u, Item: %u, %s\n", prod, item->ItemNo(), item->IntStr());
		switch (prod){
/* 11 <tactid type ::=> */
/* 12 <tactid type ::=> STRING */
			case TACTIDTYPESTR1:
			case VARTYPESTR1:
			case TACTIDTYPESTR2:
				  idtype = valstr; thisidpos = idpos++; break;
/* 13 <tactid type ::=> NUMBER */
			case TACTIDTYPENUMB: idtype = valnumb; thisidpos = idpos++;  break;
/* 14 <tactid type ::=> LINENO */
			case TACTIDTYPELINE: idtype = valline; thisidpos = 1; break;
/* 15 <tactid type ::=> WORD */
			case TACTIDTYPEWORD: idtype = valword; thisidpos = 0; break;

			case TACTIDMAINNAME:
				 NumbTACTIds = NumbGlobalvars = MaxNumbVars = idpos;
				 if (!addmainid(item->IntStr(), idtype)){
					 ResFile->MsgData(item->DisplayPosition());
					 ResFile->MsgData(item->IntStr());
					 ResFile->PutResError( NAMEINUSE );
					 exit(100);
				 }
				 HandleDeclare(item, idtype, globalvars, thisidpos);
				 vtype[thisidpos] = idtype;
				 if (idtype==valstr)ppgm->Append(new pgminittids(thisidpos));
				 else ppgm->Append(new pgminittidn(thisidpos));
				 break;
/* 19 <alt name list ::=> <alt name list> , <name> */
			case TACTIDALTNAME1:
/* 20 <alt name list ::=> <name> */
			case TACTIDALTNAME2:
				 if (!addotherid(item->IntStr())){
					 ResFile->MsgData(item->DisplayPosition());
					 ResFile->MsgData(item->IntStr());
					 ResFile->PutResError( NAMEINUSE );
					 exit(100);
				 }
				 HandleDeclare(item, idtype, globalvars, thisidpos);
				 break;
/* 30 <declare name ::=> <name> */
			case DECLAREDGLOBALNAME:
				 varnamestype *tvt;
				 if (doingglobals){tvt = globalvars; NumbGlobalvars = idpos;}
				 else tvt = localvars;
				 if (idpos > MaxNumbVars) MaxNumbVars = idpos;
				 HandleDeclare(item, idtype, tvt, thisidpos);
				 vtype[thisidpos] = idtype;
				 if (idtype==valstr){
                ppgm->Append(new pgminitvars(thisidpos));
                if(!doingglobals)localstrs[nolstrs++] = thisidpos;
             }
				 else ppgm->Append(new pgminitvarn(thisidpos));
				 break;
/* 36 <segment type ::=> OPEN */
			case SEGMENTISOPEN: segisopen = 1; break;
/* 36 <segment type ::=> CLOSE */
         case SEGMENTISCLOSE: segisopen = 0; break;
/* 37 <element list ::=> <element name> */
         case FIRSTELEMENTNAME:
				 if (!doingglobals)cleanuplocals(ppgm); // cleans up >previous< segment.
				 doingglobals = 0;
				 ppgm = new pgm; // break is intentionally missing here.  j.b.
				 numbeles = 0;
/* 38 <element list ::=> <element list> , <element name> */
         case OTHERELEMENTNAMES:
				 segetd = ((etditem *)item)->MyEtd();
				 if (segisopen)segetd->startpgm = (void *)ppgm;
				 else segetd->endpgm = (void *)ppgm;
				 if (startlocalids == 0)startlocalids = idpos; else idpos = startlocalids;
				 delete localvars;
				 localvars = new varnamestype;
				 numbeles++;
				 break;
/* 34 <actions ::=> <actions> <action statement> */
/* 35 <actions ::=> <action statement> */
			case ACTIONSTATEMENT1:
			case ACTIONSTATEMENT2:
				if (sp != 0)
					printf("*program warning* sp = %d",sp);
				break;
/* 66 <word op ::=> collect <logical expression> */
			case HANDLECOLLECTCOMMAND:  MkN(ppgm);sp--;ppgm->Append(new setpgmfmtopt(formatcollect));break;
/* 67 <word op ::=> append <char expression> */
			case HANDLEAPPENDCOMMAND:
				MkC(ppgm);sp--;ppgm->Append(new setpgmfmtwadj(wpost,formatwordpost));
				break;
/* 68 <word op ::=> prepend <char expression> */
			case HANDLEPREPENDCOMMAND:
				MkC(ppgm);sp--;ppgm->Append(new setpgmfmtwadj(wpre,formatwordpre));
				break;
/* 69 <word op ::=> replace <char expression> */
			case HANDLEREPLACECOMMAND:
				MkC(ppgm);sp--;ppgm->Append(new setpgmfmtwadj(wrep,formatwordrep));
				break;
/* 45 <simple action statement ::=> inc <declared name> */
/* 46 <simple action statement ::=> dec <declared name> */
			case HANDLEINC:
			case HANDLEDEC:
				w = (varitem *)item;
				asgnno = w->Vardata()->pos();
				ppgm->Append(new pgmvarld(asgnno,tstk[sp++]=w->Vardata()->type()));
				MkN(ppgm); StkN();ppgm->Append(new pgmintstk(1));
				sp--;
				if (prod == HANDLEINC)ppgm->Append(new pgmbinop(add));
				else ppgm->Append(new pgmbinop(subt));
				if (vtype[asgnno]==valstr)MkC(ppgm);
				sp--;
				ppgm->Append(new pgmvarsv(asgnno));
				break;
/* 42 <simple action statement ::=> output <char expression> */
			case HANDLEOUTPUTCOMMAND: MkC(ppgm); sp--; ppgm->Append(new pgmoutput);break;
/* 46 <simple action statement ::=> output blines <arith expression> */
         case DOBLANKLINES: MkN(ppgm); sp--;ppgm->Append(new pgminsblk);break;
/* 43 <simple action statement ::=> error <char expression> */
			case HANDLEERRORCOMMAND:  MkC(ppgm); sp--; ppgm->Append(new pgmerror);break;
/* 44 <simple action statement ::=> remark <char expression> */
			case HANDLEREMARKCOMMAND:  MkC(ppgm); sp--; ppgm->Append(new pgmremark);break;
/* 38 <format option ::=> compress <logical expression> */
			case SETFORMATCOMPRESS: MkN(ppgm);sp--;ppgm->Append(new setpgmfmtopt(formatcompress));break;
/* 39 <format option ::=> centre <logical expression> */
			case SETFORMATCENTRE: MkN(ppgm);sp--;ppgm->Append(new setpgmfmtopt(formatcentre));break;
/* 40 <format option ::=> display <logical expression> */
			case SETFORMATDISPLAY: MkN(ppgm);sp--;ppgm->Append(new setpgmfmtopt(formatdisplay));break;
/* 41 <format option ::=> fill <logical expression> */
			case SETFORMATFILL: MkN(ppgm);sp--;ppgm->Append(new setpgmfmtopt(formatfill));break;
/* 42 <format option ::=> fold <arith expression> */
			case SETFORMATFOLD: MkN(ppgm);sp--;ppgm->Append(new setpgmfmtfold);break;
/* 43 <format option ::=> indent <arith expression> */
			case SETFORMATINDENT: MkN(ppgm);sp--;ppgm->Append(new setpgmfmtindent);break;
/* 75 <format option ::=> to <var name> */
			case SETOUTTOVAR:
				w = (varitem *)item;
				if (VerifyVarForOut(w->Vardata()))
					ppgm->Append(new setpgmfmtout(w->Vardata()->pos()));
				else {
					/*RES OLD MSG 603
					%0: Variable %1 has an incorrect type for "format to".
					*/
					ResFile->MsgData(w->DisplayPosition());
					ResFile->MsgData(w->IntStr());
					ResFile->PutResError(/*RES REM INS*/ 603);
					exit(100);
				}
				break;
/* 76 <format option ::=> to tdb */
			case SETOUTTOTDB: ppgm->Append(new setpgmfmtout(0)); break;

/* 54 <popstack which ::=> POP */
			case ITSPOP: itspop=1; break;
/* 55 <popstack which ::=> STACK */
			case ITSSTACK: itspop=0; break;
/* 58 <ps item ::=> <var name> */
			case POPSTACKVAR:
				w = (varitem *)item;
				if (itspop)ppgm->Append(new pgmpop(w->Vardata()->pos()));
				else ppgm->Append(new pgmpush(w->Vardata()->pos()));
				break;
/* 54 <let statement ::=> let <destination> = <let expression> */
			case DOTHEASSIGN:
				if ((vtype[asgnno]==valnumb)&&(tstk[sp-1] == valstr))MkN(ppgm);
				else
				if ((vtype[asgnno]==valstr)&&(tstk[sp-1] == valnumb))MkC(ppgm);
				sp--;
				ppgm->Append(new pgmvarsv(asgnno));
				break;
/* 55 <destination ::=> <var name> */
			case GETASSIGNID:
				w = (varitem *)item;
				asgnno = w->Vardata()->pos();
				break;
/* 58 <char expression ::=> <char expression> | <char item> */
			case CHAREXPAPPEND: Mk2C(ppgm); sp--;ppgm->Append(new pgmchbin(ccn));break;
/* 60 <char item ::=> <string> */
			case CHAREXPSTRING: StkC();ppgm->Append(new pgmchpush(item->IntStr()));break;
/* 61 <char item ::=> nl */
			case CHAREXPNEWLINE: StkC();ppgm->Append(new pgmchpush((UNCH *)"\n"));break;
/* 64 <char item ::=> UPPER ( <char expression> ) */
			case CHAREXPUPPER: MkC(ppgm);ppgm->Append(new pgmunop(unupp));break;
/* 87 <char item ::=> THISGI */
         case CHARTHISGI: StkC();ppgm->Append(new pgmelename);break;
/* 89 <char item ::=> SUBSTR ( <sub operands> ) */
			case CHARSUBSTR:  sp -= 2; ppgm->Append(new pgmsubstr); break;
/* 90 <char item ::=> PAD ( <pad operands> ) */
			case CHARPAD: sp -= 4; StkC(); ppgm->Append(new pgmpad); break;
/* 94 <main sub ops ::=> <sub item> , <start numb> */
			case SUBSTRMISSLEN:  StkN();ppgm->Append(new pgmintstk(9999));break;
/* 95 <sub item ::=> <char expression> */
			case SUBSTRITEM: MkC(ppgm); break;
/* 96 <start numb ::=> <arith expression> */
			case SUBSTRSTART: MkN(ppgm); break;
/* 97 <len numb ::=> <arith expression> */
			case SUBSTRLEN: MkN(ppgm); break;
/* 98 <pad item ::=> <char expression> */
			case PADITEM: MkC(ppgm); break;
/* 99 <pad length ::=> <arith expression> */
			case PADLEN: MkN(ppgm); break;
/* 100 <pad pattern ::=> */
			case PADNOPATTERN: StkC();ppgm->Append(new pgmchpush((UNCH *)" "));break;
/* 101 <pad pattern ::=> , <char expression> */
			case PADPATTERN: MkC(ppgm); break;
/* 102 <pad position ::=> */
			case PADBACK1: StkN();ppgm->Append(new pgmintstk(0)); break;
/* 103 <pad position ::=> FRONT , */
			case PADFRONT: StkN();ppgm->Append(new pgmintstk(1)); break;
/* 104 <pad position ::=> BACK , */
			case PADBACK2: StkN();ppgm->Append(new pgmintstk(0)); break;
//* 67 <arith expression ::=> <arith expression> + <arith term> */
			case ARITHEXPPLUS: Mk2N(ppgm); sp--;ppgm->Append(new pgmbinop(add));break;
/* 68 <arith expression ::=> <arith expression> - <arith term> */
			case ARITHEXPMINUS: Mk2N(ppgm); sp--;ppgm->Append(new pgmbinop(subt));break;
/* 70 <signed term ::=> - <arith term> */
			case ARITHEXPUMINUS: MkN(ppgm);ppgm->Append(new pgmunop(unneg));break;
/* 73 <arith term ::=> <arith term> * <arith primary> */
			case ARITHEXPTIMES: Mk2N(ppgm); sp--;ppgm->Append(new pgmbinop(mult));break;
/* 74 <arith term ::=> <arith term> / <arith primary> */
			case ARITHEXPDIV: Mk2N(ppgm); sp--;ppgm->Append(new pgmbinop(adiv));break;
/* 77 <arith item ::=> <number> */
			case ARITHEXPNUMB: StkN();ppgm->Append(new pgmintstk(atoi((char *)item->IntStr())));break;
/* 121 <arith item ::=> FIND ( <char expression> , <char expression> ) */
			case ARITHEXPFIND: Mk2C(ppgm); sp-=2; StkN();ppgm->Append(new pgmfind); break;
/* 82 <arith item ::=> MAX ( <arith expression> , <arith expression> ) */
			case ARITHEXPMAX: Mk2N(ppgm);sp--;ppgm->Append(new pgmbinop(amax));break;
/* 83 <arith item ::=> MIN ( <arith expression> , <arith expression> ) */
			case ARITHEXPMIN: Mk2N(ppgm);sp--;ppgm->Append(new pgmbinop(amin));break;
/* 85 <arith item ::=> LENGTH ( <char expression> ) */
			case ARITHEXPLEN: MkC(ppgm);tstk[sp-1] = valnumb;ppgm->Append(new pgmunop(unlen));break;
/* 98 <name or attrib ::=> <var name> */
			case GETTACTGLOBAL:
				w = (varitem *)item;
				ppgm->Append(new pgmvarld(w->Vardata()->pos(),tstk[sp++]=w->Vardata()->type()));
				break;
/* 100 <attribute ::=> . <name> */
			case LOADLOCALATTRIB:
				if (numbeles == 1)BuildAttrRef(ppgm, segetd, item->IntStr());
				else BuildAttrRef2(ppgm, item->IntStr());
				break;
/* 101 <attribute ::=> <the element> . <name> */
			case LOADELEMATTRIB:
				BuildAttrRef(ppgm, thisetd, item->IntStr());
				break;
/* 102 <the element ::=> <element name> */
			case SAVEELEMENT: thisetd = ((etditem *)item)->MyEtd(); break;
/* 124 <if start ::=> IF <logical expression> THEN <statement end> */
			case IFSTART:
				ppgm->StartIf(); sp--;
				ifstk[++ifptr] = 1; // note first ifstk element is not used
				break;
/* 132 <elsif line ::=> <elsif id> <logical expression> THEN <statement end> */
			case ELSEIFCOND: ppgm->StartIf(); sp--; break;
/* 133 <elsif id ::=> ELSE IF */
			case ELSEIFSTART: ppgm->StartElse(); ++ifstk[ifptr]; break;
/* 126 <ELSE ID ::=> ELSE <statement end> */
			case IFELSESTART: ppgm->StartElse(); break;
/* 127 <end if ::=> END <statement end> */
         case IFEND: ppgm->EndIf(ifstk[ifptr--]); break;
/* 129 <while test ::=> <WHILE ID> <logical expression> <statement end> */
         case WHILECOND: ppgm->WhileCond(); sp--; break;
/* 130 <WHILE ID ::=> WHILE */
         case WHILESTART: ppgm->StartWhile(); break;
/* 131 <end while ::=> END <statement end> */
         case WHILEEND: ppgm->EndWhile(); break;
/* 113 <logical expression ::=> <logical expression> OR <logical term> */
			case LOGOR: Mk2N(ppgm);sp--;ppgm->Append(new pgmbinop(lor));break;
/* 115 <logical term ::=> <logical term> AND <signed logical term> */
			case LOGAND: Mk2N(ppgm);sp--;ppgm->Append(new pgmbinop(land));break;
/* 117 <signed logical term ::=> NOT <logical primary> */
			case LOGNOT: MkN(ppgm);ppgm->Append(new pgmunop(unlneg));break;
/* 107 <logical primary ::=> ON */
			case LOGEXPON: StkN();ppgm->Append(new pgmintstk(1));break;
/* 108 <logical primary ::=> OFF */
			case LOGEXPOFF: StkN();ppgm->Append(new pgmintstk(0));break;
/* 166 <in funct elem ::=> <element name> */
			case DOINFUNCT:
/* 167 <is funct elem ::=> <element name> */
         case DOISFUNCT:
				StkN();
				fetd = ((etditem *)item)->MyEtd();
				if (prod == DOINFUNCT)ppgm->Append(new pgminelem(fetd->etdgi));
				else ppgm->Append(new pgmiselem(fetd->etdgi));
				break;
/* 122 <compare ::=> <exp 1> = <exp 2> */
			case COMPEQU: DoCompare(ppgm,aeq,ceq); break;
/* 123 <compare ::=> <exp 1> ~ = <exp 2> */
			case COMPNOTEQU: DoCompare(ppgm,ane,cne); break;
/* 124 <compare ::=> <exp 1> "> <exp 2> */
			case COMPGT: DoCompare(ppgm,agt,cgt); break;
/* 125 <compare ::=> <exp 1> "< <exp 2> */
			case COMPLT: DoCompare(ppgm,alt,clt); break;
/* 126 <compare ::=> <exp 1> "> = <exp 2> */
			case COMPGE: DoCompare(ppgm,age,cge); break;
/* 127 <compare ::=> <exp 1> "< = <exp 2> */
			case COMPLE: DoCompare(ppgm,ale,cle); break;
		}
	} while ((prod != 1)&&(prod <= 1000));
	if (prod > 1000) exit(1);
	delete scnr;
};

// elements below must be in alphabetical order j.b.
	/*RES OLD DTA 35
	'[ALPHA]' '[CONTINUATION]' '[DIACNON]' '[DIACRET]' '[WORDSEPSEQ]'
	*/
#define ALPSECTIONNAMES /*RES REM INS*/ 35
#define ALPHA 1
#define CONTINUATION 2
#define DIACNON 3
#define DIACRET 4
#define WORDSEPSEQ 5

// elements below must be in alphabetical order j.b.
	/*RES OLD DTA 36
	'[ELEMPROCS]' '[REFTEMPLATE]' '[TITLE]'
	*/
#define EPMSECTIONNAMES /*RES REM INS*/ 36
#define ELEMPROCS 1
#define REFTEMPLATE 2
#define TITLE 3

LineCollection *AlphaLines;
LineCollection *DiacRetLines;
LineCollection *DiacNonLines;
LineCollection *WordSepSeq;
LineCollection *TitleText;
LineCollection *RefTemText;
LineCollection *ContinuText;

void initialalpData(){
/*RES OLD DTA 6
   'a b c d e f g h i j k l m n o p q r s t u v w x y z'
   '0 1 2 3 4 5 6 7 8 9' !00 !00
   -!20!\Acute\!20!\Grave\!20!\Circumflex\!20!\Cedilla\!20!\Umlaut\!20!\Tilde\!20!"'"
   !00
   !00 !00
   !00
*/
	ResStrCollection rs(*ResFile, /*RES REM INS*/ 6);
	AlphaLines = new LineCollection;
	UNCH exttxt[256];
	rs.NextC(exttxt);	AlphaLines->AddItem(exttxt);
	rs.NextC(exttxt);	AlphaLines->AddItem(exttxt);
	rs.NextC(exttxt); rs.NextC(exttxt);

	DiacRetLines = new LineCollection;
	rs.NextC(exttxt);	DiacRetLines->AddItem(exttxt);

	DiacNonLines = new LineCollection;
	WordSepSeq = new LineCollection;
	TitleText = new LineCollection;
	RefTemText = new LineCollection;
	ContinuText = new LineCollection;
} ;

/*RES OLD MSG 588
An improper section name %0 was found in file %1, line %2
*/
#define IMPROPERSECTION /*RES REM INS*/ 588

void processalpfile(UNCH *filename, FILE *f){
	pfile = new paramfile(f);
	ResStringLookup seclup( *ResFile, ALPSECTIONNAMES);
	UNCH *secnam = pfile->Section();
	do {
		unsigned secno = seclup.Lookup(secnam);
		if (secno == 0){
			ResFile->MsgData(secnam);
			ResFile->MsgData(filename);
			ResFile->MsgData(pfile->LineNo());
			ResFile->PutResError( IMPROPERSECTION );
			exit(100);
		}
		else {
			switch (secno) {
				case ALPHA: GetInputLines(AlphaLines); break;
				case DIACRET: GetInputLines(DiacRetLines); break;
				case DIACNON: GetInputLines(DiacNonLines); break;
				case CONTINUATION: GetOneLine(ContinuText); break;
				case WORDSEPSEQ: GetInputLines(WordSepSeq); break;
			}
		}
	} while (NULL != (secnam = pfile->Section())) ;
delete pfile;
};

void processepmfile(UNCH *filename, FILE *f){
   epmfilename = filename;
   printf("-- SGML2TDB is processing EPM file: %s\n", filename);
	pfile = new paramfile(f);
	ResStringLookup seclup( *ResFile, EPMSECTIONNAMES);
	UNCH *secnam = pfile->Section();
	if (NULL == secnam) secnam = seclup[ELEMPROCS];
	do {
		unsigned secno = seclup.Lookup(secnam);
		if (secno == 0){
			/*RES OLD MSG 588
			An improper section name %0 was found in file %1, line %2
			*/
			ResFile->MsgData(secnam);
			ResFile->MsgData(epmfilename);
			ResFile->MsgData(pfile->LineNo());
			ResFile->PutResError( /*RES REM INS*/ 588 );
			exit(100);
		}
		else {
			switch (secno) {
				case TITLE: GetOneLine(TitleText); break;
				case REFTEMPLATE: GetOneLine(RefTemText); break;
				case ELEMPROCS: HandleElemProcs(); break;
			}
		}
	} while (NULL != (secnam = pfile->Section())) ;


	delete pfile;
}

void ProcessFile(void (*funct)(UNCH *n, FILE *f), UNCH *e, UNCH *fln){
   UNCH s[100], s2[100]; s2[0] = 0;
	makefilename(s, fln,e);
   if(dtdfilename != 0)makefilename(s2, dtdfilename,e);
	FILE *f = fopen((char *)s, "r");
	if (f != 0) funct(s, f);
   else if(s2[0] != 0){
		f = fopen((char *)s2, "r");
		if (f) funct(s2, f);
	   }
   else {
		/*RES OLD MSG 586
		Neither %0 file "%1" or "%2" was found.  SGML2TDB will stop.
		*/
		ResFile->MsgData(e);
		ResFile->MsgData(s);
		ResFile->MsgData(s2);
		ResFile->PutResError( /*RES REM INS*/ 586);
		exit(100);
	}
};

void readsetupfiles(UNCH * fln){
	initialalpData();
	globalvars = new varnamestype;
	localvars = new varnamestype;
   ProcessFile(processalpfile, ".alp", fln);
	BuildAlphabetXlate(AlphaLines, DiacRetLines,DiacNonLines, ContinuText, WordSepSeq);

   ProcessFile(processepmfile, ".epm", fln);
	delete globalvars;
	delete localvars;

	UNCH s[100];
	makefilename(s, fln,(UNCH *)".tdb");
	StartTDBFile(s, TitleText, RefTemText);
	makemytagstk();
	PgmSetup();
	startdynamicdata(vtype);
	initpgm->Execute();
	delete initpgm;
};
