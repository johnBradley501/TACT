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

enum valtype {valstr, valnumb, valline, valword};

#define ESCLEN0 1
#define ESCLEN1 2

class basevalue {
protected:
	short int nameid;
public:
	basevalue(short int id) { nameid = id;}
	virtual void push() = 0;
	virtual void pop() = 0;
	virtual valtype gettype() = 0;
	short int id() {return nameid;}
	virtual UNCH *getvalstr(){return 0;}
	virtual unsigned getvalnumb(){return 0;}
	virtual void setvalstr(UNCH *c){}
	virtual void setvalnumb(unsigned n){}
	virtual int /*boolean*/ restore(unsigned lvl){return 0;}
};


class curvalnum {
private:
	unsigned value;
	unsigned lvl;
	curvalnum *nxt;
public:
	curvalnum(unsigned val, unsigned level, curvalnum *next)
		{value = val; lvl = level; nxt = next;}
	unsigned getval() {return value;}
	void updateval(unsigned val){value = val;}
	curvalnum *next() {return nxt;}
	unsigned level() {return lvl;}
};

basevalue *newvalue(valtype v, int /*boolean*/ tactid);

class varnumb : public basevalue{
protected:
	curvalnum *top;
public:
	varnumb(unsigned int id, unsigned int val=0);
	~varnumb();
	void push();
	void pop();
	virtual valtype gettype(){return valnumb;}
	unsigned getvalnumb() {return top->getval();}
	virtual void setvalnumb(unsigned int val);
	virtual int restore(unsigned lvl);
};

class tactidnumb : public varnumb{
public:
	tactidnumb(unsigned int id, unsigned int val=0):varnumb(id,val){}
	void pop();
	virtual void setvalnumb(unsigned int val);
	virtual int restore(unsigned lvl);
};


//class tactidlineno : public basevalue{
//private:
//	unsigned value;
//public:
//	tactidlineno();
//	void push(){}
//	void pop() {}
//	valtype gettype(){return valline;}
//	void inc();
//	virtual unsigned getvalnumb() {return value;}
//	virtual void setvalnumb(unsigned n) {value = n;}
//};
//
//extern tactidlineno *lineno;

class curvalstr {
private:
	UNCH *value;
	unsigned lvl;
	curvalstr *nxt;
public:
	curvalstr(UNCH *val, unsigned level, curvalstr *next)
		{value = val; lvl = level; nxt = next;}
	~curvalstr(){free(value);}
	UNCH *getval() {return value;}
	void updateval(UNCH *val);
	curvalstr *next() {return nxt;}
	unsigned level() {return lvl;}
};

class BalTree;

struct strrangedata {
	UNCH strtrec,strtidx,endrec,endidx;
};

class varstr : public basevalue{
protected:
	curvalstr    *top;
public:
	varstr(unsigned int id, UNCH *val=0);
	~varstr();
	void push();
	void pop();
	virtual valtype gettype(){return valstr;}
	UNCH *getvalstr() {return top->getval();}
	virtual void setvalstr(UNCH *val); // val should be created by savestr j.b.
	int /*boolean*/ restore(unsigned lvl);
};

class tactidstr : public varstr{
public:
	tactidstr(unsigned int id, UNCH *val=0):varstr(id, val){}
	virtual void setvalstr(UNCH *val); // val should be created by savestr j.b.
	void pop();
	int /*boolean*/ restore(unsigned lvl);
};


class tactidname {
private:
	UNCH        *nme;
	unsigned int pref;
	basevalue   *dta;
public:
	tactidname() {nme = 0; pref = 0; dta = 0;}
	tactidname(UNCH *n, basevalue *d, unsigned int p);
//	tactidname(UNCH *n, valtype type=valstr, unsigned int p=1);
	tactidname(UNCH *n, valtype type=valstr, unsigned int p=0);
	tactidname(tactidname &v);
	~tactidname();

	UNCH *name() {return nme;}
	void setname(UNCH *name){nme = name;} // for use only in dynamic.cpp itself
	unsigned int preference() {return pref;}
	int id() {return dta->id();}
   int tactid(){if (dta->gettype() == valstr)return -dta->id(); else
                return dta->id();}
	basevalue *data() {return dta;}

	friend int operator < (tactidname &a, tactidname &b);
	friend int operator == (tactidname &a, tactidname &b);
};

//===============procedures to handle RefNames

void startidarray();

int addmainid(UNCH *name, valtype type);  // name in internal format

int addotherid(UNCH *name);    // name in internal format

tactidname *tactidpresent(UNCH *name); // name in "sort" form

void WriteNames();

void finishidarray();

void ResetTactIDs();

extern unsigned CurrentGILevel;

//==============text in TDB materials
 
#define formatcompress 0x01
#define formatfill     0x02
#define formatcentre   0x04
#define formatdisplay  0x08
#define formatcollect  0x10
#define formatwordpre  0x20
#define formatwordpost 0x40
#define formatwordrep  0x80
#define wpre 0
#define wpost 1
#define wrep 2
struct formatData {
	int     fold;
	int     indent;
	int     destid;
	UNCH    *wadj[3];
	char    formatoptions;
};

extern struct formatData *fdstk;  // will be set to be an array of structures j.b.
extern struct formatData *curfd; // set within proctext to point to current element

void  AddTextToTDB(unsigned l,UNCH * t); // t is in the External character set
void AddSDATAToTDB(unsigned intl,UNCH * t); // t is 0 terminated

void InsertBlankLines(int n);

void startdynamicdata(valtype *vtype);

//void HandleNumericTactID(int id, unsigned val);

//void HandleStringTactID(int id, UNCH *val);

//==============procedure to call at end of text, to finish TDB processing

void CompleteTDB();

