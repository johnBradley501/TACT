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
#define PNE int
#include "sgmlfnsm.h"
#include "sgmlaux.h"

#include <classlib/binimp.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <math.h>

#include "utils.h"
#include "wordbase.h"
#include "hyperdat.h"
#include "vm.h"
#include "dynamic.h"
#include "charxlat.h"
#include "pgmbase.h"

//=======================================================================
// the following code implements base utilities for the "dynamic" form
// of the TDB : balanced binary trees (See Knuth Vol 2), and Hash tables
// This class is used in several classes and procedures that follow
//=======================================================================

class BalTree{
private:
	va   header;
	void SRot(va &p, va r, va s, int a);
	void DRot(va &p, va r, va s, int a);
	void DoThisOne(va p, void (*f) (UNCH *key, va data));

public:
	BalTree();
	va Find(UNCH *key,va &p, va &s, va &t);
	va /* to BTData */ Add(UNCH *key, va &data, va &p, va &s, va &t);
	void Process(void (*f) (UNCH *key, va data));
};

struct BTData{
	va   ll, rl, data, next /*used within virthash functions j.b. */;
	char b; //as a 1-byte integer
	UNCH key[256];
};

va MakeBTData(UNCH *key, va &da, va type){
	va q;
	BTData *q1=(BTData *)AllocateSpace(q, type, 18 + ustrlen(key));
	q1->ll = VirtNil, q1->rl = VirtNil, q1->next = VirtNil;
	q1->data = da; q1->b = 0; ustrcpy(q1->key, key);
	ReleasePage(q);
	return q;
}

BalTree::BalTree(){
	header = MakeBTData((UNCH *)"", VirtNil, VirtNil /*was storage type, now unused j.b.*/);
};

#define RealBTD(n) (BTData *)MakeReal(n)

va BalTree::Find(UNCH *key,va &p, va &s, va &t){
	p = header; t = p;
	BTData *p1 = RealBTD(p), *q1;
	va q = p1->rl;
	s = q;
	if (s == VirtNil) { ReleasePage(p); return VirtNil;};
	q1 = RealBTD(q); ReleasePage(p);
	p = q; p1 = q1;
	do {
		int cr = ustrcmp(key, p1->key);
		if (cr == 0){
			va dta = p1->data;
			ReleasePage(p);
			return dta;
		}
		else if (cr < 0) {
			q = p1->ll;
			if (q == VirtNil){ReleasePage(p); return VirtNil;};
		}
		else {
			q = p1->rl;
			if (q == VirtNil){ReleasePage(p); return VirtNil;};
		}
		q1 = RealBTD(q);
		if (q1->b != 0){t = p; s = q;};
		ReleasePage(p);
		p = q; p1 = q1;
	} while (1);
};

  /* This routine is the 'single rotation' discussed by Knuth     */
  /* in his book 'The Art of Computer Programming' vol 3, pg      */
  /* 457 and 454.                                                 */

void BalTree::SRot(va &p, va r, va s, int a){
	p = r;
	BTData *r1 = RealBTD(r); MarkDirty(r); r1->b = 0;
	BTData *s1 = RealBTD(s); MarkDirty(s); s1->b = 0;
	if (a == 1){s1->rl = r1->ll; r1->ll = s;}
	else {s1->ll = r1->rl; r1->rl = s;}
	ReleasePage(r); ReleasePage(s);
}


  /* This routine is the 'double rotation' discussed by Knuth    */
  /* in his book 'The Art of Computer Programming  vol 3, pgs    */
  /* 457 and 454.                                                */

void BalTree::DRot(va &p, va r, va s, int a){
	BTData *r1 = RealBTD(r), *s1 = RealBTD(s), *p1;
	MarkDirty(r); MarkDirty(s);
	if (a == -1) {
		p = r1->rl;
		p1 = RealBTD(p); MarkDirty(p);
		r1->rl = p1->ll;
		p1->ll = r;
		s1->ll = p1->rl;
		p1->rl = s;
		s1->b = 0;
		r1->b = 0;
		if (p1->b == -1) s1->b = 1;
		if (p1->b == 1) r1->b = -1;
		p1->b = 0;
	}
	else {
		p = r1->ll;
		p1 = RealBTD(p); MarkDirty(p);
		r1->ll = p1->rl;
		p1->rl = r;
		s1->rl = p1->ll;
		p1->ll = s;
		s1->b = 0;
		r1->b = 0;
		if (p1->b == 1) s1->b = -1;
		if (p1->b == -1) r1->b = 1;
		p1->b = 0;
	}
	ReleasePage(p);
	ReleasePage(r);
	ReleasePage(s);
};

va BalTree::Add(UNCH *key, va &data, va &p, va &s, va &t){
	va q = MakeBTData(key, data, VirtNil /*was space type*/), r;

	BTData *p1 = RealBTD(p); MarkDirty(p);
	if (p == header){
		p1->rl = q;
		ReleasePage(p);
	}
	else {
		if (ustrcmp(key, p1->key) < 0)p1->ll = q;
		else p1->rl = q;
		ReleasePage(p);
// a6:
		int a;
		BTData *s1 = RealBTD(s), *r1;
		if (ustrcmp(key, s1->key) < 0){a = -1; r = s1->ll;}
		else {a = 1; r = s1->rl;}
		p = r;
		va pt;
		while (!(p == q)) {
			p1 = RealBTD(p); MarkDirty(p);
			if (ustrcmp(key, p1->key) < 0) {
				p1->b = -1;
				pt = p1->ll;
				ReleasePage(p);
				p = pt;
			}
			else {
				p1->b = 1;
				pt = p1->rl;
				ReleasePage(p);
				p = pt;
			}
		}
// a7:
		if (s1->b == 0){MarkDirty(s); s1->b = a;}
		else if(s1->b == (-a)){MarkDirty(s); s1->b = 0;}
		else {
			r1 = RealBTD(r);
			if (r1->b == a) SRot(p,r,s,a);
			else DRot(p,r,s,a);
			ReleasePage(r);
			BTData *t1 = RealBTD(t); MarkDirty(t);
			if (s == t1->rl) t1->rl = p;
			else t1->ll = p;
			ReleasePage(t);
		};
		ReleasePage(s);
	};
	p = q;
	return q;
};

void BalTree::DoThisOne(va p, void (*f) (UNCH *key, va data)){
	BTData *p1 = RealBTD(p);
	if (!(p1->ll == VirtNil))DoThisOne(p1->ll, f);
	f(p1->key,p1->data);
	if(!(p1->rl == VirtNil))DoThisOne(p1->rl, f);
	ReleasePage(p);
}

void BalTree::Process(void (*f) (UNCH *key, va data)){
	BTData *p1 = RealBTD(header);
	if (!(p1->rl == VirtNil))DoThisOne(p1->rl, f);
	ReleasePage(header);
};

//=======================================================================
// the following code to implement Hash tables on top of the virtual memory scheme
// is adapted from work done by Lidio Presutti -- reused with thanks.
//                           ... john bradley
//=======================================================================

//#define SEGMENTSIZE 1024
#define SEGMENTSIZE 1024L
#define DIRECTORYSIZE 64
struct segment{
	va     p[SEGMENTSIZE];
};
//  Segment = ARRAY[0..SegmentSize-1] OF VirtualAddrType (* BTDataPtr *) ;
//  SegmentPtr = POINTER TO Segment ;
class HashTable {
private:
	 unsigned   p;             // next bucket to split
	 unsigned   MaxP;          // upper bound on p during this expansion
	 unsigned   KeyCount;      // number of records in table
	 unsigned   CurrentSize;   // current number of buckets
	 unsigned   MaxLoadFactor; // upper bound on load factor
	 va         Directory[DIRECTORYSIZE];

	 segment   *NewSegment(int dirno, va & vsa);
public:
	 HashTable();
	 ~HashTable();
	 long int Hash(UNCH *K);
	 void     ExpandTable();
	 void     Insert(long int id, va vnd);
	 va       Search(UNCH *K, long int &id);
};

HashTable   T;
va          VHashSpaceType;

segment *HashTable::NewSegment(int dirno, va& vsa){
  segment *ns = (segment *)AllocateSpace(Directory[dirno], VHashSpaceType, sizeof(segment));
  vsa = Directory[dirno];
  for (int i = 0; i < SEGMENTSIZE; i++) ns->p[i] = VirtNil;
  return ns;
}

long int HashTable::Hash(UNCH *K){
#define PRIME 1048583
	long int ConvertedKey = 0L;
	for (unsigned I=0; K[I] != 0; I++) ConvertedKey = 7L*ConvertedKey + K[I];
//	ConvertedKey *= 7L; // in original TACT code loop happened 1+Length of text
//	long int h = abs(ConvertedKey) % PRIME; // % is MOD
	long int h = labs(ConvertedKey) % PRIME; // % is MOD
	long int addr = h % MaxP;
	if (addr < p) addr = h % (2*MaxP);
	return addr;
}

void HashTable::ExpandTable(){
	if ((long int)MaxP + (long int)p < (long int)DIRECTORYSIZE * (long int)SEGMENTSIZE){
		va vos = Directory[p / (unsigned)SEGMENTSIZE];  // virtual address: old segment
		segment *os=(segment *)MakeReal(vos);
		unsigned osidx = p % (unsigned)SEGMENTSIZE;

		// expand address space, if necessary create a new segment
		unsigned na = MaxP + p;
		segment *ns;  // new segment pointer
		va vns;       // virtual address for new segment
		if (na % (unsigned)SEGMENTSIZE == 0)
			ns = NewSegment(na/(unsigned)SEGMENTSIZE, vns);
		else {
			vns = Directory[na / (unsigned)SEGMENTSIZE];
			ns = (segment *)MakeReal(vns);
		}
		unsigned nsidx = na % SEGMENTSIZE;
		// adjust the state variables
		if ((++p) == MaxP){MaxP *= 2; p = 0;}
		CurrentSize++;
		// relocate records to the new bucket
		BTData *prev = 0, *cur, *newlast = 0;
		va vnewlast = VirtNil, vcur = os->p[osidx], vprev = VirtNil;
		while (!(vcur == VirtNil)){
			cur = RealBTD(vcur);
			if (Hash(cur->key)==(long int)na){
				//attach it to end of the new chain
				if (newlast==0){ns->p[nsidx] = vcur; MarkDirty(vns);}
				else {newlast->next = vcur; MarkDirty(vnewlast);};
				if (prev == 0){os->p[osidx] = cur->next; MarkDirty(vos);}
				else {prev->next = cur->next; MarkDirty(vprev);};
				if (newlast != 0)ReleasePage(vnewlast);
				newlast = cur;
				vnewlast = vcur;
				vcur = cur->next;
				newlast->next = VirtNil;
				MarkDirty(vnewlast);
			}
			else {
				// leave it on the old chain
				if (prev != 0) ReleasePage(vprev);
				vprev = vcur;
				prev = cur;
				vcur = cur->next;
			}
		}
		if (newlast != 0) ReleasePage(vnewlast);
		if (prev != 0) ReleasePage(vprev);
		ReleasePage(vns);
		ReleasePage(vos);
	}
	else exit(1000);
}

void HashTable::Insert(long int id, va vnd){
	segment *csg;
	va      vcsg;
	if (CurrentSize == 0){++CurrentSize; csg = NewSegment(0,vcsg);}
	unsigned sidx = id % SEGMENTSIZE;
	vcsg=Directory[id/SEGMENTSIZE];
	csg = (segment *)MakeReal(vcsg);
	BTData *btnode = (BTData *)MakeReal(vnd);
	btnode->next = csg->p[sidx];
	csg->p[sidx] = vnd;
	MarkDirty(vnd);
	MarkDirty(vcsg);
	ReleasePage(vnd);
	ReleasePage(vcsg);
	if ((++KeyCount)*2 > CurrentSize*3) ExpandTable(); //MaxLoadFactor=1.5
};

//va *tmp = 0;       this, and commented out below, was for nasty bug j.b.
//segment *st = 0;

va HashTable::Search(UNCH *K, long int &id){
	id = Hash(K);
//	if ((!(Directory[1] == VirtNil))&&(tmp == 0)){
//		st = (segment *)MakeReal(Directory[1]);
//		tmp = &st->p[29];
//	}
	if (CurrentSize == 0)return VirtNil;
	va vcs = Directory[id / SEGMENTSIZE];
	int sidx = id % SEGMENTSIZE;
	segment *sg = (segment *)MakeReal(vcs);
	va VBTnode = sg->p[sidx], vtemp;
	while (!(VBTnode == VirtNil)){
		BTData *vtnode = RealBTD(VBTnode);
		if (0 == ustrcmp(K, vtnode->key)){
			vtemp = vtnode->data;
			ReleasePage(VBTnode);
			ReleasePage(vcs);
			return vtemp;
		}
		vtemp = vtnode->next;
		ReleasePage(VBTnode);
		VBTnode = vtemp;
	}
	ReleasePage(vcs);
	return VirtNil;
}

HashTable::~HashTable(){
	for (int i=0; i <DIRECTORYSIZE; i++)
	  if (!(Directory[i] ==VirtNil) /* & HasRealMem? */) ReleasePage(Directory[i]);
}

HashTable::HashTable(){
	InitSpaceType(VHashSpaceType);
	p = 0; MaxP = SEGMENTSIZE; KeyCount = 0, CurrentSize = 0; MaxLoadFactor = 2;
	for (int i = 0; i <DIRECTORYSIZE; i++)Directory[i] = VirtNil;
};

//=======================================================================
// this code manages tact ID names for eventual inclusion in the TDB
//=======================================================================

tactidname::tactidname(UNCH *n, basevalue *d, unsigned int p){
	pref = p;
	dta = d;
	nme = savestr(n);
};

int nxtid = 2;

tactidname::tactidname(UNCH *n, valtype type, unsigned int p){
	pref = p;
	nme = savestr(n);
	switch (type) {
//	  case valstr:   dta = new tactidstr(-(nxtid++)); break;
	  case valstr:   dta = new tactidstr(nxtid++); break;
	  case valnumb:  dta = new tactidnumb(nxtid++); break;
//	  case valline:  dta = new tactidlineno; break;
	  case valline:  dta = new tactidnumb(1); break;
	  case valword:  dta = new varnumb(0);
	}
};

tactidname::tactidname(tactidname &v){
	nme = savestr(v.name());
	pref = v.preference();
	dta = v.data(); // data deliberately not duplicated j.b.
};

tactidname::~tactidname()
{frem((UNIV)nme);} // "dta" must survive destruction j.b.

int operator < (tactidname &a, tactidname &b){
	return 0 > ustrcmp(a.nme, b.nme);
};

int operator == (tactidname &a, tactidname &b){
	return 0 == ustrcmp(a.nme, b.nme);
} ;

typedef TIBinarySearchTreeImp<tactidname> tactids;
typedef TIBinarySearchTreeIteratorImp<tactidname> tactidsiterator;

tactids *tids;
tactidname *curiddata;
unsigned int prefno;
unsigned int numbnames, gotline,gotword;

void startidarray() { tids = new tactids; numbnames = gotline = gotword = 0;};

int addmainid(UNCH *name, valtype type){
	UNCH w[256];
	IntToSortWord(name,w);
	curiddata = new tactidname (w, type);
	if (type == valline) {gotline = 1; /*lineno = (tactidlineno *)curiddata->data();*/}
	if (type == valword) gotword = 1;

	if (0 != tids->Find(curiddata)){
		delete curiddata;
		return 0;
	};
	tids->Add(curiddata);
	numbnames++;
//	prefno = 2;
	prefno = 1;
	return 1;
};

int addotherid(UNCH *name){
	UNCH t[256];
	IntToSortWord(name,t);
	tactidname* w = new tactidname (t, curiddata->data(), prefno++);
	if (0 != tids->Find(w)){delete w; return 0;};
	tids->Add(w);
	numbnames++;
	return 1;
};

tactidname *tactidpresent(UNCH *name){
	tactidname *w = new tactidname;
	w->setname(savestr(name));
	tactidname *tmp=tids->Find(w);
	delete w;
	return tmp;
}

void makewordlineids(){
	if (!gotline){
		addmainid((UNCH *)"LINES", valline);
		addotherid((UNCH *)"LINE");
	}
	if (!gotword){
		addmainid((UNCH *)"WORDS", valword);
		addotherid((UNCH *)"WORD");
	}
}

void WriteNames(){
//	Tactids = (tactvalptr *)malloc(sizeof(tactvalptr) * (nxtid));
	makewordlineids();
	TactidNameData  temp;
	TDBFile->AppendSpn((void *)&numbnames, 2);

	tactidsiterator it(*tids);
//	while (it != 0 ){
	for (int i = 1; i <= numbnames; i++){
		tactidname* item = it.Current();
		ustrcpy(temp.name, item->name());
		temp.pref = item->preference();
		temp.id = item->tactid();
//		if (temp.pref == 1){
//		if (temp.pref == 0){
//			if (temp.id < 0) Tactids[-temp.id].p =item->data();
//			else if (temp.id > 1) Tactids[temp.id].p = item->data();
//		}
		int len = ustrlen(item->name());
		TDBFile->AppendSpn( (void *)&temp, len+4); // INTEGER + CHAR + Name + 0C
		it++;
	}
};

void finishidarray(){ delete tids;};

//=======================================================================
// the following class definitions relate to the log and the maintenance
// of TACTid values.  See the method definitions after the section that
// defines methods for classes derived from basevalue and related to
// TACTids and global variables.
//=======================================================================

/* StrRec is used to contain information about a single value for a TACT string ID.
	StrRecs are stored in strcollectiondata types, in the BalTree "vals".  */

struct StringRec{
	HRecPntr S; // j.b.: must still subtract start rec to get correct value!
//	UNCH /*as 1-byte unsigned #s*/ SRecNo, SRecPos;
	long unsigned TotWords, CurWordNo;
	UNCH IntStr[256];
};

/* StrRecs are collected together into "strcollectiondata"s -- one for each
string oriented TACT ID*/

class strcollectiondata{
protected:
	BalTree      *vals;
	va           vcur;
	strrangedata rngdta;
public:
	strcollectiondata();
	~strcollectiondata();
	va AddValue(UNCH *key, UNCH *val, long int TokenNo);
//	void DoForAll(void (*f) (UNCH *key, va data)){
//		vals->Process(f);
//	}

	UNCH WriteToDB(long int TokenNo);
	strrangedata *getstrrangedata(){return &rngdta;}
};

/*
class allstrings keeps pointers to all the stringcollectiondata instances
for the log, and provides a method to write them to the TDB.
*/

class allstrings {
private:
	strcollectiondata **dat; //acting as an array of size "numb"
	UNCH *sidx; //acting as an array of size "numb"
	int numb;
public:
	allstrings();
	allstrings(int n);
	~allstrings();
	void InitId(int id){dat[id] = new strcollectiondata;}
	va AddValue(int id,UNCH *key, UNCH *str,long int TokenNo);
	void WriteToDB(long int TokenNo);
	UNCH StrStartIdx(int id){return sidx[id];}
};

/*
Finally, TheLog maintains all the information about the TDB log. The log
is a sequence of LogListEntrys, where each entry is (in the case of a
numeric type, the value, or in the case of a string, a pointer to a
StringRec which contains the value.
*/

struct LogListEntry{
	int           id; // when > 0 use Number, < 0 use String part
	va            next; // LogListEntry
	long unsigned tokenno;
	union {
		unsigned   number;   // for numeric type data
		va         vstrptr;  // to StringRec, for string data
		HRecPntr   hr;       // position in TDB
	} d;
};

class TheLog {
private:
	va VCurLog, VLog;
	LogListEntry *CurLog;
	allstrings as;

	void DoLogListBase(int id, long int TokenNo);
public:
	TheLog(valtype *vtype);
//	void InitId(int id){as.InitId(id);}

	va Add(int id, unsigned numb, long int TokenNo){
		DoLogListBase(id,TokenNo);
		CurLog->d.number = numb;
		return VCurLog;
	}
	va Add(int id, UNCH *str, long int TokenNo);
	va VaCurLog(){return VCurLog;}

	void WriteStrings(long int TokenNo){as.WriteToDB(TokenNo);}
	void WriteToDB(long int TokenNo);
};

TheLog *tl;

//=======================================================================
// classes arrayvalbase and the derived classes arrayvalnumb and arrayvalstr,
// and  the larger class valarray hold values for the TACTid strings and
// numbers between the time they are defined (during processing for beginning
// and ending of elements) and when they are needed (when words are
// collected -- for the log.  Class TheLog is defined below.
//=======================================================================

class arrayvalbase {
private:
	int temp;
public:
	virtual void updatelog(TheLog *log, int id, long int TokenNo) = 0;
};

class arrayvalnumb: public arrayvalbase{
private:
	unsigned numb;
public:
	arrayvalnumb(unsigned n){numb = n;}
	void updatelog(TheLog *log, int id, long int TokenNo){log->Add(id, numb, TokenNo);}
};

class arrayvalstr: public arrayvalbase{
private:
	UNCH *str;
public:
	arrayvalstr(UNCH *s){str = s;}
	~arrayvalstr(){free(str);}
	void updatelog(TheLog *log, int id, long int TokenNo){log->Add(id, str, TokenNo);}
};

class valarray{
private:
	arrayvalbase **vals; // used as an array
	int numb, any;
public:
   valarray();
	valarray(int n);
	~valarray();
	void Add(int id, unsigned numb);
	void Add(int id, UNCH *s); // string at "s" is copied using savestr.
	void DoLogging(TheLog *log, long int TokenNo);
	int AnySet(){return any;}
};

valarray::valarray(int n){
	vals = (arrayvalbase **)malloc(4 * n);
   for(int i=0;i<n;i++)vals[i] = 0;
	numb = n;
	any = 0;
};

valarray::valarray(){
	vals = (arrayvalbase **)malloc(4 * NumbTACTIds);
	numb = NumbTACTIds;
	for(int i=0;i < numb; i++)vals[i] = 0;
	any = 0;
};

valarray::~valarray(){
	for(int i=0;i < numb; i++)if (vals[i] != 0)delete vals[i];
   free(vals);
};

void valarray::Add(int id, unsigned numb){
	if (vals[id] != 0)delete vals[id];
	vals[id] = new arrayvalnumb(numb);
	any = 1;
};

void valarray::Add(int id, UNCH *s){
	if (vals[id] != 0)delete vals[id];
	vals[id] = new arrayvalstr(savestr(s));
	any = 1;
};

void valarray::DoLogging(TheLog *log, long int TokenNo){
	for(int i=0;i < numb; i++)
	  if(vals[i] != 0)vals[i]->updatelog(log, i, TokenNo);
};

valarray *CurValArray;

//=======================================================================
// this section handles data associated with TACTIDs and global variables
// method definitions for classes derived from basevalue are found here:
// varnum, tactidnumb, curvalstr, varstr and tactidstr.
//=======================================================================

//tactidlineno *lineno;
unsigned CurrentGILevel = 0;

basevalue *newvalue(valtype v, int /*boolean*/ tactid){
	if (tactid) {
	  switch (v) {
		 case valstr:   return new tactidstr(nxtid++);
		 case valnumb:  return new tactidnumb(nxtid++);
		 case valline:  return new tactidnumb(1);
		 case valword:  return new tactidnumb(0);
	  }
	}
	else {
	  switch (v) {
		 case valstr:   return new varstr(nxtid++);
		 case valnumb:  return new varnumb(nxtid++);
	  }
	}
	return 0;
};

//=========================varnum========================================

varnumb::varnumb(unsigned int id, unsigned int val): basevalue(id){
	top = new curvalnum(val, 0, 0);
};

varnumb::~varnumb(){
	curvalnum *tmp = top;
	while (top != 0){tmp = top->next(); delete top; top = tmp;}
};

void varnumb::push(){
	top = new curvalnum(top->getval(), CurrentGILevel, top);
};

void varnumb::setvalnumb(unsigned int val){
	top->updateval(val);
};

void varnumb::pop(){
	if (top->next() != 0){
		curvalnum *tmp = top->next();
		delete top;
		top = tmp;
	}
};

int varnumb::restore (unsigned lvl){
	int rslt = top->level() > lvl;
	while (top->level() > lvl)pop();
	return rslt;
};
//=========================tactidnumb====================================

//tactidnumb::tactidnumb(unsigned int id, unsigned int val): varnumb(id, val){
//	CurValArray->Add(id,val);
//};

void tactidnumb::setvalnumb(unsigned int val){
	CurValArray->Add(id(),val);
	varnumb::setvalnumb(val);
}

void tactidnumb::pop(){
	int tmp = top->getval();
	varnumb::pop();
	if (tmp != top->getval()) CurValArray->Add(id(),top->getval());
};

int tactidnumb::restore(unsigned lvl){
	int rslt = varnumb::restore(lvl);
	if (rslt) CurValArray->Add(id(),top->getval());
	return rslt;
};

//=========================tactidlineno==================================

//tactidlineno::tactidlineno(): basevalue(1){
//	value = 1;
//	CurValArray->Add(1,value);
//};

//void tactidlineno::inc() {CurValArray->Add(1,++value); };

//=========================curvalstr=====================================

void curvalstr::updateval(UNCH *val){
	if (value != 0)free(value);
	value = val;
};
//=========================varstr========================================

varstr::varstr(unsigned int id, UNCH *val): basevalue(id){
	if (val == 0) val = savestr((UNCH *)"");
	top = new curvalstr(val, 0, 0);
};

varstr::~varstr(){
	curvalstr *tmp = top;
	while (top != 0){tmp = top->next(); delete top; top = tmp;}
};

void varstr::push(){
//	top = new curvalstr(top->getval(), CurrentGILevel, top);
	top = new curvalstr(savestr(top->getval()), CurrentGILevel, top);
};

void varstr::setvalstr(UNCH *val){
	top->updateval(val);
};

void varstr::pop(){
	if (top->next() != 0){
	  curvalstr *tmp = top->next();
	  delete top;
	  top = tmp;
	}
};

int varstr::restore(unsigned lvl){
	int rslt = top->level() > lvl;
	while (top->level() > lvl)pop();
	return rslt;
};
//=========================tactidstr=====================================

//tactidstr::tactidstr(unsigned int id, UNCH *val): varstr(id, val){
//	tl->InitId(id);
//	CurValArray->Add(id,(UNCH *)"???",!!    1,(UNCH *)"");
//	AddToLog((UNCH *)"???",1,(UNCH *)"");
//};

void tactidstr::setvalstr(UNCH *val){
	CurValArray->Add(id(),val);
	varstr::setvalstr(val);
};

void tactidstr::pop(){
	UNCH *tmp = savestr(top->getval());
	varstr::pop();
	if (ustrcmp(tmp, top->getval()) != 0) CurValArray->Add(id(),top->getval());
	free(tmp);
};

int tactidstr::restore(unsigned lvl){
	int rslt = varstr::restore(lvl);
	if (rslt) CurValArray->Add(id(),top->getval());
	return rslt;
};

//=======================================================================
// here is the definitions of the methods associated with the log:
// classes and structures StringRec, strcollectiondata
//=======================================================================


/* DoStrForDB writes a single StringRec value to the TDB. Note the nasty use
	of strstrt!

	TDB string data contains both a "key" format (in the alphabetic format)
	and a value in the Internal Character set.  The Internal value comes from
	the StringRec IntStr, the key format comes from the BalTree entry and is
	passed to DoStrForDB through the parameter "k".
*/

HRecPntr strstrt; //see reference in DoStrForDB and strcollectiondata::WriteToDB.

void DoStrForDB(UNCH *k, va vstr){
	StringRec *sp = (StringRec *)MakeReal(vstr);
	unsigned kl = ustrlen(k),istrl = ustrlen(sp->IntStr) + 1;
	TDBString tdbdata;
	PackStr(k, tdbdata.TDBStr, SortNoBitsPerChar);
	if ((kl > 0) && (kl < tdbdata.TDBStr[0])){
		printf("DoStrToDB -- something wrong with bit packing");
		exit(1000);
	};
	kl = tdbdata.TDBStr[0];
//	memcpy(&tdbdata.TDBStr[kl+/*1*/2],sp->IntStr,istrl);
	memcpy(&tdbdata.TDBStr[kl+1],sp->IntStr,istrl);
	tdbdata.TotalWords = sp->TotWords;
//	sp->S = TDBFile->AddPtrData(&tdbdata,/*4*/ 5+kl+istrl);
	sp->S = TDBFile->AddPtrData(&tdbdata,4+kl+istrl);
	sp->S.Rec -= strstrt.Rec;
};

//=========================strcollectiondata====================================

strcollectiondata::~strcollectiondata(){
	delete vals;
};

strcollectiondata::strcollectiondata(){
	vals = new BalTree;
	vcur = VirtNil;
	AddValue((UNCH *)"", (UNCH *)"???",0);
};

va strcollectiondata::AddValue(UNCH *key, UNCH *str,long int TokenNo){
	StringRec *strdta;
	if (!(vcur == VirtNil)){
		strdta = (StringRec *)MakeReal(vcur);
		strdta->TotWords += TokenNo - strdta->CurWordNo;
		MarkDirty(vcur); ReleasePage(vcur);
	}
	va p,s,t,dummy;
	if (VirtNil == (vcur = vals->Find(key,p,s,t))){
		strdta = (StringRec *) AllocateSpace(vcur,dummy, 12+ustrlen(str)+1);
		ustrcpy(strdta->IntStr,str);
		strdta->TotWords = 0;
		vals->Add(key, vcur,p,s,t);
	}
	else strdta = (StringRec *)MakeReal(vcur);
	strdta->CurWordNo = TokenNo;
	MarkDirty(vcur); ReleasePage(vcur);
	return vcur;
};

UNCH strcollectiondata::WriteToDB(long int TokenNo){
  // set the final tally for the last (currently active) entry
  StringRec *strdta = (StringRec *) MakeReal(vcur);
  strdta->TotWords += TokenNo - strdta->CurWordNo;
  MarkDirty(vcur); ReleasePage(vcur);

  // now start collecting rngdta.
  strstrt=TDBFile->CurrentPos();
  rngdta.strtrec = 0;
  rngdta.strtidx = strstrt.Idx;

  // process all items in the collection
  vals->Process(DoStrForDB);

  // add a dummy entry on the end.
  UNCH t[10] = "      ???";
  t[0]=t[1]=t[2]=t[3]=0; t[4]=1;t[5]=255;
  TDBFile->AddPtrData(&t,10);

  // collect ending position information for string data.
  HRecPntr end=TDBFile->CurrentPos();
  rngdta.endrec = end.Rec - strstrt.Rec;
  rngdta.endidx = end.Idx - 1;
  return rngdta.strtidx;
};

//=========================allstrings===========================================

allstrings::allstrings(int n){
	 numb = n;
	 dat = (strcollectiondata **)malloc(4*n);
	 sidx = (UNCH *)malloc(n);
	 for(int i = 0; i < n; i++){dat[i] = 0; sidx[i] = 0;}
};

allstrings::allstrings(){
	 numb = NumbTACTIds;
	 dat = (strcollectiondata **)malloc(4*numb);
	 sidx = (UNCH *)malloc(numb);
	 for(int i = 0; i < numb; i++){dat[i] = 0; sidx[i] = 0;}
};

allstrings::~allstrings(){
	for(int i = 0; i < numb; i++)
		if (dat[i] != 0)delete dat[i];
	free(dat);
	free(sidx);
};

va allstrings::AddValue(int id, UNCH *key, UNCH *str,long int TokenNo){
//	if (dat[id] == 0)dat[id] = new strcollectiondata;
	return dat[id]->AddValue(key,str,TokenNo);
};

void allstrings::WriteToDB(long int TokenNo){
  	TDBFile->Header()->BeginStr = TDBFile->InitPtrData();
	int i;
	for(i = 0; i < numb; i++){
		if(dat[i] != 0){
			sidx[i] = dat[i]->WriteToDB(TokenNo) ;  /* start index */
		}
	};
	HRecPntr strend = TDBFile->FinishPtrData();
	TDBFile->Header()->EndStr = strend.Rec;


	TDBFile->Header()->BeginStrRec = TDBFile->FinishSection();
	TDBFile->Header()->NoStrRecs = 0 ;
	TDBRefStringData d;
	for(i = 0; i < numb; i++){
		if(dat[i] != 0){
			++TDBFile->Header()->NoStrRecs;
			d.ID = -i;
			memcpy(&d.SRec,dat[i]->getstrrangedata(),4);
			TDBFile->Append(&d,sizeof(d));
		}
	};

	d.ID = 0; // j.b. ?????
	d.ERec = d.SRec = strend.Rec - TDBFile->Header()->BeginStr;
	d.EPos = d.SPos = strend.Idx;
	TDBFile->Append(&d,sizeof(TDBRefStringData));
	TDBFile->FinishSection();
};


//=========================TheLog=================================================

TheLog::TheLog(valtype *vtype){
	VCurLog = VirtNil; VLog = VirtNil; CurLog = 0;
	for (int i = 1; i<NumbTACTIds; i++){
		if (vtype[i] == valstr){as.InitId(i); Add(i,(UNCH *)"", 0);}
		else Add(i,(unsigned)0,0);
	}
};

void TheLog::DoLogListBase(int id, long int TokenNo){
	va ve, dummy;
	LogListEntry *e = (LogListEntry *)AllocateSpace( ve, dummy, sizeof(LogListEntry) ) ;
	if(CurLog!= 0)CurLog->next = ve;
	else VLog = ve;
	ReleasePage(VCurLog);
	e->id = id;
	e->tokenno = TokenNo;
	e->next = VirtNil;
	VCurLog = ve;
	CurLog = e;
};

va TheLog::Add(int id, UNCH *str, long int TokenNo/*,int force?*/){
	static UNCH alphs[128];
	IntToSortWord(str, alphs);
	DoLogListBase(-id, TokenNo); // here's where sign indicates type of data (minus -> string data)
	CurLog->d.vstrptr = as.AddValue(id, alphs, str, TokenNo);
   return VCurLog;
};

void TheLog::WriteToDB(long int TokenNo){
	HRecPntr tmp =  TDBFile->CurrentPos();
	TDBFile->Header()->BeginLog = tmp.Rec;
	ReleasePage(VCurLog); // ??
	int i;
	HLogData dl, *cv = (HLogData *)malloc(sizeof(dl) * nxtid);
	dl.StructID = 0; dl.TokenNoOffset = 255; dl.Count = 0;
	for (i = 0; i < nxtid; i++){cv[i].StructID = 0; cv[i].TokenNoOffset = 0;}
	va vle = VLog, vtle;
	i = 1; // Note: nxtid is zero based
	LogListEntry *le;
	unsigned astid;
	while ((!(vle == VirtNil)) && (i < nxtid)){  // was i <= nxtid j.b.
		le = (LogListEntry *)MakeReal( vle ) ;
		astid = abs(le->id);
		if (le->id >= 0) cv[astid].Count = 0;
		else {cv[astid].shr.SRecNo = 0; cv[astid].shr.SRecPos = as.StrStartIdx(astid);}
		if (cv[astid].StructID == 0) i++;
		cv[astid].StructID = le->id;
		vtle = le->next;
		ReleasePage(vle);
		vle = vtle;
	}

	long unsigned CurBaseTokenNo = 0;
	HRecPntr cp;
	while (!(vle == VirtNil)){
		le = (LogListEntry *)MakeReal( vle ) ;
		cp = TDBFile->CurrentPos();
		if (cp.Idx == 0){
			CurBaseTokenNo = le->tokenno;
			TDBFile->Append(&CurBaseTokenNo, sizeof(CurBaseTokenNo));
			for (i = 1;i < nxtid; i++){  // i was = 0 j.b.
				cv[i].TokenNoOffset = 0;
				TDBFile->Append(&cv[i], sizeof(cv[i]));
			}
		}
		astid = abs(le->id);
		if (le->id >= 0) cv[astid].Count = le->d.number;
		else {
			StringRec *s = (StringRec *)MakeReal( le->d.vstrptr);
			cv[astid].shr.SRecNo = s->S.Rec;
			cv[astid].shr.SRecPos = s->S.Idx;
			ReleasePage( le->d.vstrptr );
		}
		unsigned offset = le->tokenno - CurBaseTokenNo;
		if (offset > 255) {
			/* this will only happen if we allow long line folding       */
			/* which would permit more than 255 words per line.         */
			for (i = 1; i <= offset/256; i++)TDBFile->Append(&dl, sizeof(dl));
			cv[astid].TokenNoOffset = offset % 256;
		}
		else cv[astid].TokenNoOffset = offset;
		CurBaseTokenNo = le->tokenno; // for next relative offset value
		le->d.hr = TDBFile->Append(&cv[astid], sizeof(cv[astid]));
		le->d.hr.Idx = le->d.hr.Idx/4 - 1;
		MarkDirty(vle);

		vtle = le->next;
		ReleasePage(vle);
		vle = vtle;
	}
// the following handles exceptional case when last record is exactly full
//     thanks for the bug fix shown here from Michael Stairs   .. j.b.
	cp = TDBFile->CurrentPos();
	if (cp.Idx == 0){
		TDBFile->Append(&CurBaseTokenNo, sizeof(CurBaseTokenNo));
		for (i = 0;i <= nxtid; i++){
			cv[i].TokenNoOffset = 0;
			TDBFile->Append(&cv[i], sizeof(cv[i]));
		}
	}
	cp = TDBFile->CurrentPos();
	TDBFile->Header()->EndLog = cp.Rec;
	TDBFile->FinishSection();
};

//=======================================================================
//This code handles the saving of tokens, as they are found in the text
//This results, of course, in construction of headword lists etc etc
//=======================================================================

long unsigned TokenNumber = 0;
//long unsigned TokenNumber = 0; ??

struct typedata {
  HRecPntr   hwrd;
  unsigned   NoOccurs;
  va         voccur; // occurrence list pointer
  va         voccurend; // occurrence list pointer
};

struct tokendata {
	va         vlog;
	HRecPntr   text;
	va         hwrd;
};

#define NUMBTOKENSINLIST 16
#define NUMBOCCURSINLIST 8

struct tokenlist {
	tokendata  tokena[NUMBTOKENSINLIST];
	va         next; // pointer to another tokenlist
};

tokenlist *MakeTokenList(va &vp){
	va dummy;
	tokenlist *p = (tokenlist *)AllocateSpace(vp,dummy, sizeof(tokenlist));
	p->next = VirtNil;
	memset(p,0,sizeof(tokenlist));
	return p;
};

struct occurrencelist {
	HRecPntr     occura[NUMBOCCURSINLIST];
	va           next; // pointer to another occurrencelist
};

long unsigned Numberoccurs = 0;

occurrencelist *MakeOccurList(va &np){
	va dummy;
	occurrencelist *p = (occurrencelist *)AllocateSpace(np, dummy, sizeof(occurrencelist));
	Numberoccurs++;
	p->next = VirtNil;
	HRecPntr val = {65535u,65535u};
	for(int i=0;i<NUMBOCCURSINLIST;i++) p->occura[i] = val;
	return p;
};

long unsigned TypeNumber = 0;

typedata *MakeTypeData(va &vtp){
	va dummy;
	typedata *p = (typedata *)AllocateSpace(vtp, dummy, sizeof(typedata));
	p->NoOccurs = 0;
	p->hwrd = NilHRP;
	p->voccur =	p->voccurend = VirtNil;
	TypeNumber++;
	return p;
};

BalTree typelist;

typedata *LocateHWType(UNCH *wd, va &vtp){
	long int id;
	vtp = T.Search(wd,id);
	if (!(VirtNil == vtp))return (typedata *)MakeReal(vtp);
	typedata *rslt = MakeTypeData(vtp);
	va p,s,t,q;
	if (!(VirtNil == typelist.Find(wd,p,s,t))){
		printf("**Fatal error** in LocateHWType");
		exit(100);
	}
	q = typelist.Add(wd, vtp, p,s,t) ;
	T.Insert(id, q);
	return rslt;
};

int CurrTokenPos = 0;
HRecPntr CurToken = {0,0};
tokenlist *CurrTokenArray, *bta;
va         VCurrTokenArray;
va         VHeldTokenArray;
va         VBeginTokenArray;
int        HeldTokenPos;

void HandleWord(UNCH * wd, HRecPntr tpos){
// if "word" contains no letters, ignore it and return immediately
	if ((wd[0] == WORDSEPCODE) || (wd[0] == EXTRACODESEP)) return;
	va vtt;
// first, locate or create the headword record, and mark dirty, we'll be updating it
	typedata *tt = LocateHWType(wd, vtt);
	MarkDirty(vtt);
// get token number of this new word
	CurrTokenPos++;
// if necessary, create a new token array
	if (CurrTokenPos > NUMBTOKENSINLIST){
		va vp;
		tokenlist *p = MakeTokenList(vp);
		CurrTokenArray->next = vp;
		ReleasePage(vp);
		VCurrTokenArray = vp;
		CurrTokenArray = p;
		CurrTokenPos = 1;
	}
// save token data (pointers to text (to be updated later), headword and log
	tokendata *q = &CurrTokenArray->tokena[CurrTokenPos-1];
	q->hwrd = vtt;
	q->text = tpos;
	q->vlog = tl->VaCurLog();
// find right position in occurrence list data
	int pos = (tt->NoOccurs++) % NUMBOCCURSINLIST;
	occurrencelist *olp;
	va volp;
// if position is zero, new occurrence list record is needed.
	if (pos == 0){
		if (tt->NoOccurs != 1)
			pos = 0;
		olp = MakeOccurList(volp);
		if (tt->voccur == VirtNil)tt->voccur = tt->voccurend = volp;
		else {
 			((occurrencelist *)MakeReal(tt->voccurend))->next = volp;
			ReleasePage(tt->voccurend);
			tt->voccurend = volp;
		}
	}
	else olp = (occurrencelist *)MakeReal(volp = tt->voccurend);
// CurToken counts (in HRecPntr terms) the number of tokens so far
	olp->occura[pos] = CurToken;
	MarkDirty(volp);
	CurToken.Idx++;
	if (CurToken.Idx >= HNOTOKENS){CurToken.Idx = 0; CurToken.Rec++;}
	ReleasePage(volp);
	ReleasePage(vtt);
	TokenNumber++;
};
//=======================================================================
// The formattext class handles the formatting of the text as it is provided
// from sgmls, and handles the various "events" that mark changes that arise
// from the programs associated with the SGML elements
//=======================================================================

struct formatData *fdstk;
struct formatData *curfd;

#define FORMATFILL (curfd->formatoptions & formatfill)
#define FORMATCOMPRESS (curfd->formatoptions & formatcompress)
#define FORMATCENTRE (curfd->formatoptions & formatcentre)
#define FORMATDISPLAY (curfd->formatoptions & formatdisplay)
#define FORMATCOLLECT (curfd->formatoptions & formatcollect)
#define FORMATWORDPRE (curfd->formatoptions & formatwordpre)
#define FORMATWORDPOST (curfd->formatoptions & formatwordpost)
#define FORMATWORDREP (curfd->formatoptions & formatwordrep)

#define TABSIZE 5

/*
	Perhaps the trickiest part of the following code is based on the handling of
	"Events" -- situations which must be noted at the entry to method Text, but not
	dealt with then.  Each time one of these occurs two things happen: (1) an event
	is added to the event queue, and (2) a marker (the tab character) is inserted
	into the text stored in variable txt.  Because of this inserted marker character
	which will, eventually, be removed, the actual length (character position in the
	text variable -- stored in variable tp) will be sometimes different from the
	visual line length as it will be stored in the tdb (visual length stored in tlen).
*/

class FormattingEvent {
protected:
	FormattingEvent   *nxt;
public:
	FormattingEvent(){nxt = 0;}
	void SetNext(FormattingEvent *p){nxt = p;}
	FormattingEvent *GetNext(){return nxt;}
	virtual int DoEvent(){return 1;}
};

class FormattingQueue {
private:
	FormattingEvent *start, *tail;
public:
	FormattingQueue(){start = 0; tail = 0;}
	void Add(FormattingEvent *evt);
//	valarray *GetValarray(){return start->GetValarray();)
//	int Getwordcollecting(){return start->Getwordcollecting();}
	void DoGroup(){
		int loop = 1;
		while (loop){
			loop = start->DoEvent();
			FormattingEvent *tmp = start->GetNext();
			delete start;
			start = tmp;
		};
	}
};

void FormattingQueue::Add(FormattingEvent *evt){
	if (start == 0)start = tail = evt;
	else {tail->SetNext(evt); tail = evt;}
};

class formattext{
private:
	UNCH    txt[256], txt2[256];
	FormattingQueue fq;
	int      tp,tlen, btp, indent, fold,oldcoll /*this is boolean */,
				lethimhaveit /*this is also boolean*/, wordCollect /* this is also boolean*/,
            lineno, noblklines;

	void    FinishLine();
	int     WriteTxt(UNCH *txt2, int i, int j);
	void    CollectWords();
public:
	formattext(){
	  btp = tp = tlen = 0;// vpl = VirtNil;
	  lethimhaveit=1; fold = 1;
	  oldcoll = 0; wordCollect = 0; lineno = 1;
     noblklines = -1;}
	void Text(unsigned l,UNCH * t);
	void FinishText();
	void SetWordCollect(int i){wordCollect = i;}
   void InsertBlankLines(int n);
};

formattext ft;
UNCH *wordprefix=0, *wordpostfix=0, *wordreplace=0;

void AddTextToTDB(unsigned l,UNCH * t){ // t is in the External character set
	 if (curfd->destid == 0)ft.Text(l,t);
	 else AppendTextToVar(curfd->destid,l,t);
};

void AddSDATAToTDB(unsigned intl,UNCH * t){
	 unsigned l = ustrlen(t), n;
	 UNCH *w = (UNCH *)malloc(l*2+1), x = ESCLEN1;
	 for (n = 0; n < l; n++){
		 if (intl == 0) x = ESCLEN0; else intl--;
		 w[2*n] = x; w[2*n+1] = t[n];
	 }
	 AddTextToTDB(l*2, w);
	 free(w);
};

class SetCollectEvent: public FormattingEvent {
private:
	int val;
public:
	SetCollectEvent(int v);
	int DoEvent();
};

SetCollectEvent::SetCollectEvent(int v)
{val = v;};

int SetCollectEvent::DoEvent(){
	ft.SetWordCollect(val); return 1;}

class FinishEventGroup: public FormattingEvent {
public:
	int DoEvent(){return 0;}
};

class UpdateLogEvent: public FormattingEvent {
private:
	valarray *cva;
public:
	UpdateLogEvent(valarray *c){cva = c;}
	~UpdateLogEvent(){delete cva;}
	int DoEvent(){cva->DoLogging(tl, TokenNumber); return 1;}
};

class UpdateWordAdjustEvent: public FormattingEvent {
private:
  UNCH *str;
  int type;
public:
  UpdateWordAdjustEvent(UNCH *s, int t);
  ~UpdateWordAdjustEvent(){if (str !=0)delete str;}
  int DoEvent();
};

UpdateWordAdjustEvent::UpdateWordAdjustEvent(UNCH *s, int t){
	if (s == 0)str = 0;
	else str = savestr(s);
	type = t;
};

void UpdateWordAdjustments(UNCH **t, UNCH *str){
	if ((*t) != 0)delete (*t);
	(*t) = savestr(str);
};

int UpdateWordAdjustEvent::DoEvent(){
	UNCH t[256];
	if ((type == formatwordpre)||(type == formatwordpost))
		 IntToFullWord(str, t);
	else IntToSortWord(str, t);
	if (type == formatwordpre)	UpdateWordAdjustments(&wordprefix,t);
	else if (type == formatwordpost) UpdateWordAdjustments(&wordpostfix,t);
	else UpdateWordAdjustments(&wordreplace,t);
	return 1;
};

void formattext::Text(unsigned l,UNCH * t){
	if(FORMATDISPLAY == 0)return;
	int anyevents = 0;
	if (oldcoll != (FORMATCOLLECT)){
		oldcoll = FORMATCOLLECT;
		anyevents = 1;
		fq.Add(new SetCollectEvent(oldcoll));
	}

	if (FORMATWORDPRE){
		anyevents = 1;
		fq.Add(new UpdateWordAdjustEvent(curfd->wadj[wpre], formatwordpre));
		curfd->formatoptions &= ~formatwordpre;
	}

	if (FORMATWORDPOST){
		anyevents = 1;
		fq.Add(new UpdateWordAdjustEvent(curfd->wadj[wpost], formatwordpost));
		curfd->formatoptions &= ~formatwordpost;
	}

	if (FORMATWORDREP){
		anyevents = 1;
		fq.Add(new UpdateWordAdjustEvent(curfd->wadj[wrep], formatwordrep));
		curfd->formatoptions &= ~formatwordrep;
	}

//	if (!(vpl == VCurLog))
   if (CurValArray->AnySet()){
		anyevents = 1;
		fq.Add(new UpdateLogEvent(CurValArray));
		CurValArray = new valarray(NumbTACTIds);
	};

	if (anyevents){
		fq.Add(new FinishEventGroup);
		txt[tp++] = '\t';
	};

	fold = curfd->fold;
	indent = curfd->indent;
	if (fold > 80) fold = 80;
	if (fold < 30) fold = 30;
	if (indent + 20 > fold) indent = fold - 20;
	fold -=indent;

	for (int i = 0; i < l; i++){
		UNCH ch = t[i];
		switch (ch){
		case '\n':
			if (FORMATFILL) ch = ' ';
			else {
//				lastblk = 0;
				lethimhaveit = 1;}
			break;
		case ' ': break;
		case '\t':
			if (FORMATCOMPRESS) ch = ' ';
			else if (tlen + TABSIZE> fold) ch = '\n';
			else {for (;tlen%TABSIZE != TABSIZE-2;tlen++)txt[tp++] = ' ';}
			break;
		default: lethimhaveit = 1;
		}
		if (lethimhaveit){
			if (ch == '\n')FinishLine();
			if ((ch == ESCLEN1)||(ch == ESCLEN0)){
				if(ch == ESCLEN1)tlen++;
				txt[tp++] = ch;
				txt[tp++] = t[++i];
			}
			else {
				if ((tlen >= fold)&&(btp != 0)) {
					int hldtp = tp, j;
					UNCH hldch = txt[btp+1]; // FinishLine will set this to '\0'
					tp = btp;
					FinishLine();
					txt[btp+1] = hldch;
					lethimhaveit = 0==FORMATCOMPRESS;
					for (j = btp+1;j < hldtp; j++){
						txt[tp++]=txt[j];
						if (txt[j] != '\t')tlen++;
					}
				}
				txt[tp++] = ch;
				noblklines = -1;
				tlen++;
				if (ch == ' ') {btp = tp-1; lethimhaveit = 0==FORMATCOMPRESS;}
				else lethimhaveit = 1;
			}
		}
	}
};

void formattext::InsertBlankLines(int n){
	if(FORMATDISPLAY == 0)return;
   if(tp != 0)FinishLine();
   if(n > noblklines){
      noblklines = n;
      for(int i = noblklines; i <= n; i++)TDBFile->AppendChar('\r');
   }
};

void InsertBlankLines(int n){if (curfd->destid == 0)ft.InsertBlankLines(n);};

int formattext::WriteTxt(UNCH *txt2, int i, int j){
   int k;
	for(k = i; (k < j) && (txt2[k] != 0); k++){
		if (txt2[k] == '\t'){
			fq.DoGroup();
			if (j == 9999) return k+1;
		}
		else TDBFile->AppendChar(txt2[k]);
	}
// return j;
   return k;
};

void formattext::CollectWords(){
	int i = 0,j;
	UNCH wd[100];
	while(txt2[i] != 0){
	  if (wordCollect){
		  j = i + FindNextSortWord(&txt2[i]);
		  i = WriteTxt(txt2, i, j);
		  if ((wordCollect)&&txt2[i] != 0){
			  j = i + IntToNextSortWord(&txt2[i], wd,wordprefix, wordpostfix, wordreplace);
			  HandleWord(wd, TDBFile->CurrentPos());
			  i = WriteTxt(txt2, i, j);
		  }
	  }
	  else {
		  i = WriteTxt(txt2, i, 9999);
	  }
	}
};

void formattext::FinishLine(){
	HRecPntr hr;
   txt[tp] = 0;
	if (tlen > 0){
		int noblks = indent;
		if (FORMATCENTRE)noblks += (fold - tlen)/2;
		if ((tlen > 0) && (noblks > 0)){
			UNCH blks[80];
			memset(blks,' ',noblks); blks[noblks] = 0;
			hr = TDBFile->AppendSpn(blks,noblks);
		}
	}
	e2i->Translate(txt, txt2, 80, 160);
   tl->Add(1,lineno++,TokenNumber);
	CollectWords();
	/* btp = */ tlen = tp = 0;
	TDBFile->AppendChar('\r');
//	lineno->inc();
   noblklines++;
   lethimhaveit = 0==FORMATCOMPRESS;
};

void formattext::FinishText(){
	if (tlen != 0) FinishLine();
}

//==============================================================================

void startdynamicdata(valtype *vtype){
	bta = CurrTokenArray = MakeTokenList(VCurrTokenArray);
	VBeginTokenArray = VHeldTokenArray = VCurrTokenArray;
	HeldTokenPos = 0;
	tl = new TheLog(vtype);
	CurValArray = new valarray(NumbTACTIds);
};


HRecPntr   curhp;
int TPtrLen,     // pos in HyperRec from start
	 TDataPos;    // pos in HyperRec from end
//long unsigned Count;

void CalcTypeDataSpace(UNCH *key, va vwt){
	typedata *p = (typedata *)MakeReal(vwt);
	unsigned NBits = ustrlen(key)*SortNoBitsPerChar ,NBytes = (NBits+7) / 8 ;
	unsigned TypeLen = BASEHTYPELEN + NBytes ;  // <<< compress Key later >>>
	TPtrLen += 2; TDataPos -= TypeLen;
	if (TDataPos < TPtrLen){
	  ++curhp.Rec; curhp.Idx = 1;
	  TPtrLen = 6; TDataPos = TYPEMAXDATAPOS - TypeLen;
	}
	p->hwrd = curhp;
	curhp.Idx++;
	long signed occursp = p->NoOccurs * OCCURRECSIZE;
	if (((long signed)(TDataPos - TPtrLen)) < occursp) {
		// will not fit on a single record
		occursp -= ((long signed)(TDataPos - TPtrLen)) / OCCURRECSIZE * OCCURRECSIZE;
		curhp.Rec += 1 + occursp / MAXSPACEFOROCCURSINREC;
		occursp = occursp % MAXSPACEFOROCCURSINREC;
		curhp.Idx = 1;
		TDataPos = TYPEMAXDATAPOS;
		TPtrLen = 4;
	}
	TDataPos -= (unsigned) occursp;
	MarkDirty(vwt);
	ReleasePage(vwt);
};

void AssignTypePos(){
	curhp.Rec = 0;
	curhp.Idx = 2; // was: 1, account for 1st dummy type
	TDataPos = TYPEMAXDATAPOS - BASEHTYPELEN - 1; // account for 1st rec
	TPtrLen = 6 ;  // = NoDataPntrUsed + 0th ptr + 1st ptr = 2 + 2 + 2 *)
//	Count = 0L;
//	TotCount = TypeNumber;
//	LastPercentage := 0 ;
	typelist.Process(CalcTypeDataSpace);
};

void WriteTokenData(){
	HRecPntr tmp = TDBFile->CurrentPos();
	TDBFile->Header()->BeginToken = tmp.Rec;
	VCurrTokenArray = VBeginTokenArray;
	while (!(VCurrTokenArray == VirtNil)){
		CurrTokenArray = (tokenlist *)MakeReal(VCurrTokenArray);
		for (int i = 0; i < NUMBTOKENSINLIST; i++){
			tokendata *p = &CurrTokenArray->tokena[i];
			if (!(p->hwrd == VirtNil)){
				typedata *wtp = (typedata *)MakeReal(p->hwrd);
				LogListEntry *llp = (LogListEntry *)MakeReal(p->vlog);
				TDBFile->AddToken( wtp->hwrd ,p->text, llp->d.hr);
				ReleasePage(p->hwrd);
				ReleasePage(p->vlog);
			}
		}
		va tmpva = CurrTokenArray->next;
		ReleasePage(VCurrTokenArray);
		VCurrTokenArray = tmpva;
	};
	tmp = TDBFile->CurrentPos();
	if (tmp.Idx == 0){tmp.Rec--; tmp.Idx = HNOTOKENS;}
	else tmp.Idx--;
	TDBFile->Header()->EndToken = tmp;
	TDBFile->FinishSection();
};

unsigned NoTypes = 0;

void ProcessThisOL(va vp) {
	while (!(vp == VirtNil)){
		occurrencelist *p = (occurrencelist *)MakeReal(vp);
		for (int i = 0; i < NUMBOCCURSINLIST; i++){
			if (p->occura[i].Rec != 0xFFFF)TDBFile->AddOccur( p->occura[i] );
		}
		va vpnext = p->next;
		ReleasePage(vp);
		vp = vpnext;
	}
};
	
void DoType(UNCH *Key, va vp){
	typedata *p = (typedata *)MakeReal(vp);
	HTypeData r;
	ustrcpy(r.Word, Key);
	//PackStr(Key, r.Word, SortNoBitsPerChar);
	r.NoOccur = p->NoOccurs;
	TDBFile->AddType(r);
	NoTypes++;
	ProcessThisOL(p->voccur);
	ReleasePage(vp);
};

void WriteTypeData(){
	HRecPntr tmp = TDBFile->CurrentPos();
	TDBFile->Header()->BeginType = tmp.Rec;
	TDBFile->InitTypes();
	// write out first (dummy) header record
	HTypeData td;
	td.NoOccur = 0; td.Word[0] = 0;
	// write out real data
	TDBFile->AddType(td);
	typelist.Process(DoType);
	// write out trailer record
	td.Word[0] = 255; td.Word[1] = 0;
	TDBFile->AddType(td);
//	TDBFile->Header()->EndType = TDBFile->CurrentPos();
//	TDBFile->Header()->EndType.Idx--;
//	TDBFile->FinishTypes();
	TDBFile->Header()->EndType = TDBFile->FinishTypes();
	TDBFile->Header()->NoTypes = NoTypes;
};

void CompleteTDB(){
	ft.FinishText();
	TDBFile->Header()->EndText = TDBFile->CurrentPos();
	TDBFile->FinishSection();
	tl->WriteStrings(TokenNumber);
	tl->WriteToDB(TokenNumber);
	printf("-- SGML2TDB finished writing structural data.\n");
	AssignTypePos();
	printf("-- SGML2TDB finished preparing index pointers.\n");
	WriteTokenData();
	printf("-- SGML2TDB finished writing word-token data.\n");
	WriteTypeData();
	printf("-- SGML2TDB finished writing word-type data.\n");

	TDBFile->FinishTDB();
};
