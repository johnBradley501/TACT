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
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "entity.h"
#include "adl.h"
#include "sgmlfnsm.h"
#include "sgmlmain.h"
#include "utils.h"
#include "vm.h"
#include "resource.h"
#include "proctext.h"
#include "dynamic.h"
#include "pgmbase.h"

extern int ts;                /* Index of current tag in stack. from sgmlxtrn.h*/

basevalue **RTVars;

void pgm::Append(pgmop *p){
	if (first == 0){first = last = p;}
	else{last->setNext(p); last = p;}
}

void pgm::Execute(){
	pgmop *p = first;
	while (p != 0) p = p->DoOp();
}

union {
	long   no;
	UNCH  *str;
} dstk[PGMSTACKSZ];
int stkp = 0;

pgmop *pgmintstk::DoOp(){
	dstk[stkp++].no = no;
	return Next();
};

pgmop *pgmbinop::DoOp(){
	long a = dstk[stkp-2].no, b = dstk[stkp-1].no, c;
	switch (bnop){
	  case add: c = a + b; break;
	  case subt:c = a - b; break;
	  case mult:c = a * b; break;
	  case adiv:c = a / b; break;
	  case land:c = a && b; break;
	  case lor: c = a || b; break;
	  case amax:c = a > b ? a:b; break;
	  case amin:c = a < b ? a:b; break;
	  case alt: c = a < b; break;
	  case agt: c = a > b; break;
	  case ale: c = a <= b; break;
	  case age: c = a >= b; break;
	  case aeq: c = a == b; break;
	  case ane: c = a != b; break;
	}
	dstk[(--stkp)-1].no = c;
	return Next();
}

pgmchpush::pgmchpush(UNCH *q){p = savestr(q);};
pgmop *pgmchpush::DoOp(){
	dstk[stkp++].str = savestr(p);
	return Next();
};

pgmchpush::~pgmchpush(){free(p);};

pgmop *pgmchbin::DoOp(){
	UNCH *p = dstk[stkp-2].str, *q = dstk[--stkp].str;
	switch (op){
	  case ccn:
		  UNCH t[256];
		  ustrcpy(t,p);
		  ustrcat(t,q);
		  dstk[stkp-1].str = savestr(t);
		  break;
	  case clt: dstk[stkp-1].no = ustrcmp(p,q) == -1; break;
	  case cgt: dstk[stkp-1].no = ustrcmp(p,q) == 1;  break;
	  case cle: dstk[stkp-1].no = ustrcmp(p,q) <= 0;  break;
	  case cge: dstk[stkp-1].no = ustrcmp(p,q) >= 0;  break;
	  case ceq: dstk[stkp-1].no = ustrcmp(p,q) == 0;   break;
	  case cne: dstk[stkp-1].no = ustrcmp(p,q) != 0;  break;
	}
	free(p); free(q);
	return Next();
}

pgmop *pgmunop::DoOp(){
	char *p, t[256];
	switch (op){
		case unneg: dstk[stkp-1].no = - dstk[stkp-1].no; break;
		case unlneg: dstk[stkp-1].no = ! dstk[stkp-1].no; break;
		case unc2i:
			dstk[stkp-1].no = atol(p = (char *)dstk[stkp-1].str);
			free(p);
			break;
		case uni2c:
			sprintf(t, "%d", dstk[stkp-1].no);
			dstk[stkp-1].str = savestr((UNCH *)t);
			break;
		case un2c2i:
			dstk[stkp-2].no = atol(p = (char *)dstk[stkp-2].str);
			free(p);
			break;
		case un2i2c:
			sprintf(t, "%d", dstk[stkp-2].no);
			dstk[stkp-2].str = savestr((UNCH *)t);
			break;
		case unupp:
			capstr(dstk[stkp-1].str);
			break;
		case unlen:
			dstk[stkp-1].no = strlen(p = (char *)dstk[stkp-1].str);
			free(p);
			break;
	}
	return Next();
};

pgmop *pgmsubstr::DoOp(){
   int len = dstk[stkp-1].no;
   UNCH *p,*q = dstk[stkp-3].str+(dstk[stkp-2].no - 1);
   if (len < ustrlen(q))q[len] = 0;
   p = savestr(q);
	free(dstk[stkp-3].str);
	dstk[stkp-3].str = p;
	stkp -= 2;
   return Next();
};

void MakePad(UNCH *w, UNCH *p, int l){
	int i = 0, j;
	for (j = 0; j < l; j++){w[j] = p[i++]; if (p[i] == 0)i = 0;}
	w[l] = 0;
};

pgmop *pgmpad::DoOp(){
/*
	dstk[stkp-1]:    fill pattern
	dstk[stkp-2]:    desired length
	dstk[stkp-3]:    input string
	dstk[stkp-4]:    0 = pad on back, 1 = pad on front
*/
	UNCH work[256], *s = dstk[stkp-3].str, *p = dstk[stkp-1].str;
	int i = 0, lin = ustrlen(s), lout = dstk[stkp-2].no, lpad;
	if (lin > lout){
		s[lout] = 0;
		dstk[stkp-4].str = savestr(s);
	}
	else{
		lpad = lout - lin;
		if (dstk[stkp-4].no == 1){MakePad(work, p, lpad); i = lpad;}
		ustrcpy(&work[i], s);
		if (dstk[stkp-4].no == 0)MakePad(&work[lin], p, lpad);
	   dstk[stkp-4].str = savestr(work);
	};
	stkp -= 3; free(s); free(p);
	return Next();
};

int DoFind(UNCH *s, UNCH *p){
	UNCH *q=p;
	int i = ustrlen(s),f=s[0];
	if (i == 0)return 1;
	while ((q=ustrchr(q,f))!= 0){
		if (0 == ustrncmp(q,s,i))return q-p+1;
		q++;
	}
	return 0;
};

pgmop *pgmfind::DoOp(){
/*
	dstk[stkp-1]:    search pattern
	dstk[stkp-2]:    input string
*/
	UNCH *s=dstk[stkp-1].str, *p=dstk[stkp-2].str;
	stkp--;
	dstk[stkp-1].no = DoFind(s,p);
	free(s); free(p);
	return Next();
};
//============================================================
pgmop *setpgmfmtopt::DoOp(){
	if (dstk[--stkp].no == 1) fdstk[ts].formatoptions |= opt;
	else fdstk[ts].formatoptions &= ~opt;
	return Next();
};

pgmop *setpgmfmtfold::DoOp(){
	fdstk[ts].fold = (int)dstk[--stkp].no;
	return Next();
};


pgmop *setpgmfmtindent::DoOp(){
	fdstk[ts].indent = (int)dstk[--stkp].no;
	return Next();
};

pgmop *setpgmfmtout::DoOp(){
	if (id != 0)RTVars[id]->setvalstr(savestr((UNCH *)""));
	fdstk[ts].destid = id;
	return Next();
};

pgmop *setpgmfmtwadj::DoOp(){
	UNCH *s;
	if (dstk[stkp-1].str[0] == 0){
		free (dstk[--stkp].str);
		s = 0;
	}
	else s = dstk[--stkp].str;
	SetWAdjs(wtype1, wtype2, s);
	return Next();
};

pgmop *pgminsblk::DoOp(){
   InsertBlankLines(dstk[--stkp].no);
   return Next();
};

//==================================================================
//program elements to handle variables
//==================================================================
//unsigned noglobalvars = 0;
unsigned NumbTACTIds, NumbGlobalvars, MaxNumbVars = 0;

void PgmSetup(){
    int j = 4 * MaxNumbVars;
	 RTVars = (basevalue * *)malloc(j);
    for(int i=0; i < MaxNumbVars; i++) RTVars[i] = 0;
};

pgmop *pgmvarld::DoOp(){
	if (vt==valnumb)dstk[stkp++].no = RTVars[varn]->getvalnumb();
	else dstk[stkp++].str = savestr(RTVars[varn]->getvalstr());
	return Next();
};
pgmop *pgmvarsv::DoOp(){
	if (RTVars[varn]->gettype()==valnumb) RTVars[varn]->setvalnumb(dstk[--stkp].no);
	else RTVars[varn]->setvalstr(dstk[--stkp].str);
	return Next();
};

pgmop *pgmclrlcl::DoOp(){
	delete RTVars[n];
	return Next();
};

pgmop *pgminitvarn::DoOp(){
	RTVars[n] = new varnumb(n);
	return Next();
};

pgmop *pgminitvars::DoOp(){
	RTVars[n] = new varstr(n);
	return Next();
};

pgmop *pgminittidn::DoOp(){
	RTVars[n] = new tactidnumb(n);
	return Next();
};

pgmop *pgminittids::DoOp(){
//	RTVars[n] = new tactidstr(-n);
	RTVars[n] = new tactidstr(n);
	return Next();
};

pgmop *pgmpush::DoOp(){
   RTVars[n]->push();
	return Next();
};

pgmop *pgmpop::DoOp(){
   RTVars[n]->pop();
	return Next();
};

pgmop *pgmattrref::DoOp(){
	dstk[stkp++].str = savestr(GetAttrVal(cgi, no));
	return Next();
};

pgmop *pgmattrref2::DoOp(){
   UNCH *tmp = GetAttrValForTop(atname);
   if (tmp == 0){
      ResFile->MsgData(atname);
      ResFile->PutResError( 596 ); // defined in PgmProc.Cpp j.b.
      exit(200);
   }
   dstk[stkp++].str = savestr(tmp);
   return Next();
};

//================================================================
pgmop *pgmoutput::DoOp(){
	UNCH *p =  dstk[--stkp].str;
	AddTextToTDB(ustrlen(p),p);
	free(p);
	return Next();
};

pgmop *pgmerror::DoOp(){
	char *filename;
	unsigned long lineno;
	if (sgmlloc(&lineno, &filename)) {
		ResFile->MsgData((UNCH *)filename);
		ResFile->MsgData(lineno);
	}
	else{ResFile->MsgData((UNCH *)"");ResFile->MsgData((UNCH *)"");};
	/*RES OLD MSG 597
	EPM Error (%0 %1): %2
	*/
	ResFile->MsgData(dstk[--stkp].str);
	ResFile->PutResError(/*RES REM INS*/ 597);
	exit(200);
};

pgmop *pgmremark::DoOp(){
	char *filename;
	unsigned long lineno;
	if (sgmlloc(&lineno, &filename)) {
		ResFile->MsgData((UNCH *)filename);
		ResFile->MsgData(lineno);
	}
	else{ResFile->MsgData((UNCH *)"");ResFile->MsgData((UNCH *)"");};
	/*RES OLD MSG 598
	EPM Message (%0 %1): %2
	*/
	UNCH *p =  dstk[--stkp].str;
	ResFile->MsgData(p);
	ResFile->PutResMessage(/*RES REM INS*/ 598);
	free(p);
	return Next();
};

pgmop *pgmnoop::DoOp(){return Next();};

pgmop * pgmtest::DoOp(){
	if (dstk[--stkp].no)return tpath;
	else return Next();
};

pgmop *pgminelem::DoOp(){
	dstk[stkp++].no = InElement(savedgi);
	return Next();
};

pgmop *pgmiselem::DoOp(){
   dstk[stkp++].no = savedgi == CurElement();
   return Next();
};

pgmop *pgmelename::DoOp(){
   dstk[stkp++].str = savestr(CurElement()+1);
   return Next();
};

//==============================================================================
class IfData: public ControlData {
public:
	pgmop *main, *tru;
   IfData(ControlData *nxt=0):ControlData(nxt){main = tru = 0;}
};

void pgm::StartIf(){
	IfData *ifd = new IfData(cds);
	cds = ifd;
	pgmop *tmp = new pgmnoop;
	Append(new pgmtest(tmp));
	ifd->main = last;
	last = tmp;
};

void pgm::StartElse(){
	IfData *ifd = (IfData *)cds;
	ifd->tru = last;
	last = ifd->main;
};

void pgm::EndIf(int numb){
	IfData *ifd;
	Append(new pgmnoop);
   while(0 != numb--){
		ifd = (IfData *)cds;
		cds = cds->Next();
		if (ifd->tru == 0) // IF had no else
			ifd->main->setNext(last);
		else
			ifd->tru->setNext(last);
		delete ifd;
	}
};

class WhileData: public ControlData {
public:
	pgmop *start, *fals;
   WhileData(ControlData *nxt=0):ControlData(nxt){start = fals = 0;}
};

void pgm::StartWhile(){
	WhileData *whd = new WhileData;
	cds = whd;
	whd->start = last;
};

void pgm::WhileCond(){
	WhileData *whd = (WhileData *)cds;
	pgmop *tmp= new pgmnoop;
	Append(new pgmtest(tmp));
	whd->fals = last;
	last = tmp;
};

void pgm::EndWhile(){
	WhileData *whd = (WhileData *)cds;
	cds = cds->Next();
	last->setNext(whd->start);
	last = whd->fals;
	delete whd;
};

//==============================================================================

void ResetRTVars(unsigned lvl){
	int i;
	for (i = 2; i < NumbGlobalvars; i++)
		RTVars[i]->restore(lvl);
};

void DoAllStrings(void (*f) (tactidstr *id)){
	int i;
	for (i = 2; i < NumbTACTIds; i++){
		if (RTVars[i]->gettype() == valstr)f((tactidstr *)RTVars[i]);
	}
};

void AppendTextToVar(int vn, unsigned l,UNCH * t){
	RTVars[vn]->setvalstr(appendstr(RTVars[vn]->getvalstr(),l,t));
};
