// copyright 1994 John Bradley

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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "resource.h"
#include "utils.h"

resfile *ResFile;

const ResPos NullPos = {0,0};

/* ResourceArray = RECORD
		NextArray:       FilePos;
		ArraySize:       CARDINAL;
      Locations:       ARRAY[0..3000] OF FilePos;
   END;  */

resfile::resfile(const UNCH *FName)
{
	ResFile = fopen(FName, "rb");
	if (ResFile == NULL) exit(1);
	unsigned i;
	if (!RdResBase(sizeof(ResPntrs), NullPos,(void *)ResPntrs, i)) exit (1);
//	MsgDataArray = new msgdataarray(10,0,5);
	MsgItemNo = 0;
}

long int fpcvt(ResPos n)
{  struct twouns{unsigned low; unsigned high;};
	union {twouns tu; long int rslt;} temp;
	temp.tu.low = n.low;
	temp.tu.high = n.high;
	return temp.rslt;
}

BOOLEAN resfile::RdResBase(int numb, ResPos loc, void *dta, unsigned &got)
{
	got = 0;
	if (fseek(ResFile, fpcvt(loc), SEEK_SET)) return FALSE;
	unsigned size;
	if ( !fread(&size, sizeof(size), 1, ResFile)) return FALSE;
	if ((numb != 0) & (numb != size)) return FALSE;

	if (dta == NULL) return FALSE;
	return numb == (got = fread(dta, 1, size, ResFile));
}

void * resfile::RdResBase(int numb, ResPos loc, unsigned &got)
{
	got = 0;
	if (fseek(ResFile, fpcvt(loc), SEEK_SET)) return FALSE;
	unsigned size;
	if (1 != fread(&size, /* (size) */ 2, 1, ResFile)) return FALSE;
	if ((numb != 0) & (numb != size)) return FALSE;

	void * dta = malloc(size);
	got = fread(dta, 1, size, ResFile);
	return dta;
}

struct ResArr  {
	ResPos nxt;
	unsigned arrsz;
	ResPos locs[1000];} ;

ResPos resfile::FindRes(TResData rt, int in)
{
	int pos = in;
	unsigned size;
	ResPos fpos = ResPntrs[rt];
	while(1) {
		if (IsNullRes(fpos)) {return NullPos;}
		ResArr * lp = (ResArr *)RdResBase(0,fpos, size);
		if (lp->arrsz >= pos){
			ResPos loc = lp->locs[pos];
			free(lp);
			return loc;}
		else {
			pos -= lp->arrsz + 1;
			fpos = lp->nxt;
			free(lp);}
	}
};

ostream &operator<<(ostream &s, msgdatabase &v){v.output(s); return s;};

class msgdatastr: public msgdatabase {
	private:
		UNCH * p;
	public:
		msgdatastr(UNCH * p1) {p = p1;}
		void output(ostream &s){s << p;}
//		friend ostream &operator<<(ostream &s, msgdatastr &v);
	};
//ostream &operator<<(ostream &s, msgdatastr &v){return s << v.p;};

class msgdatauns: public msgdatabase {
	private:
		unsigned d;
	public:
		msgdatauns(unsigned n) {d = n;}
		void output(ostream &s){s << d;}
	};

class msgdatalong: public msgdatabase {
	private:
		long unsigned d;
	public:
		msgdatalong(long unsigned n, int gs=0) {d = n; givsz = gs;}
		void output(ostream &s){s << d;}
	};

class msgdatachar: public msgdatabase {
	private:
		UNCH d;
	public:
		msgdatachar(UNCH n, int gs=0) {d = n; givsz = gs;}
		void output(ostream &s){s << d;}
	};

void resfile::MsgData(UNCH * s)
	{MsgDataArray.Add(new msgdatastr(s)); MsgItemNo++;};
void resfile::MsgData(unsigned d)
	{MsgDataArray.Add(new msgdatauns(d)); MsgItemNo++;};
void resfile::MsgData(long unsigned d)
	{MsgDataArray.Add(new msgdatalong(d)); MsgItemNo++;};
void resfile::MsgData(UNCH s)
	{MsgDataArray.Add(new msgdatachar(s)); MsgItemNo++;};

#define MC '%'

void resfile::ResMessage(int numb, ostream &s){
	ResPos loc=FindRes(MessageRes, numb);
	unsigned got;
	UNCH * dtxt, * htxt, * btxt = (UNCH *)RdResBase(0, loc, got);
	htxt = btxt;
	int itmmax = MsgItemNo;
	dtxt = btxt;
	while (*btxt != 0){
		if (NULL == (dtxt = ustrchr(btxt, MC)))
			{dtxt = btxt + ustrlen(btxt);
			 s << btxt;}
		else {
			* dtxt = '\0';
			s << btxt;
			dtxt++;
			if (*dtxt == MC){s << MC; dtxt++;}
			else {
				int itm = 0;
				while ((*dtxt >= '0') && (*dtxt <= '9')){
					itm = itm*10+(*dtxt-'0');
					dtxt++;
				}
				if (itm > itmmax){exit (1);};
				s << *MsgDataArray[itm];
			}
		}
		btxt = dtxt;
	}
	delete htxt;
	MsgDataArray.Flush();
	MsgItemNo = 0;
};

void resfile::PutResError(int numb)
{
	cerr << "Error: ";
	ResMessage(numb, cerr);
	cerr << endl ;
};
void resfile::PutResWarning(int numb)
{
	cerr << "Warning: ";
	ResMessage(numb, cerr);
	cerr << endl;
};
void resfile::PutResMessage(int numb)
{
	cerr << "Info: ";
	ResMessage(numb, cerr);
	cerr << endl;
};

void * resfile::GetResNA(unsigned id, unsigned &sz){
	ResPos loc=FindRes(NumbArrRes, id);
	return RdResBase(0, loc, sz);
};

ResCollection::ResCollection(resfile & rs, TResData tp, int id){
	dt = (UNCH *)rs.RdResBase(0, rs.FindRes(tp, id), mxsz);
	cp = 0;
};

void * ResCollection::Next(int &sz){
	if (cp >= mxsz) return NULL;
	sz = (int)dt[cp];
	void * p = (void *)&dt[cp+1];
	cp += sz + 2;
	return p;
}

void * ResCollection::Prev(int &sz){
	if (cp == 0) return NULL;
	--cp;
	sz = (int)dt[cp];
	if (cp <= sz+1) return NULL;
	cp -= sz + 1;

	int ft = cp - 1;
	sz = dt[ft];
	ft -= sz;
	return (void *)&dt[ft];
}

BOOLEAN ResStrCollection::NextC(UNCH * r) {
		int sz;
		void * s=Next(sz);
		if (!s) return FALSE;
		memcpy(r, s, sz);
		r[sz] = 0;
		return TRUE;
	}
BOOLEAN ResStrCollection::PrevC(UNCH * r)  {
		int sz;
		void * s=Prev(sz);
		if (!s) return FALSE;
		memcpy(r, s, sz);
		r[sz] = 0;
		return TRUE;
	}

typedef UNCH * CharPtr;

ResStringLookup::ResStringLookup(resfile & rs, int id):
	ResCollection(rs, DataArrRes, id){
	num = 0;
	int dmy;
	while (NULL != Next(dmy)) num++;
	ReStart();
	CharPtr *adta = new CharPtr[num];
	dta = (void *) adta;
	for (int n = 0; n<num; n++) {
		adta[n] = (UNCH *)Next(dmy);
		adta[n][dmy] = 0;
	}
};

unsigned ResStringLookup::Lookup(UNCH * r){
	int u = num - 1, i, l = 0, c;
	CharPtr *adta = (CharPtr *) dta;
	capstr(r);
   do {
      if (u < l) return 0;
		i = (l+u)/2;
		c = strcmp(r, adta[i]);
      if (c < 0) u = i - 1; else l = i + 1;}
   while (c != 0);
   return i + 1;
};

UNCH * ResStringLookup::operator[](int index){
	CharPtr* adta = (CharPtr *) dta;
	return adta[index-1];
};

