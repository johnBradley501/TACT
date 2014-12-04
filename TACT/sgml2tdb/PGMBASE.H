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

class pgmop {
private:
	pgmop *next;
public:
	pgmop(){next = 0;}
	pgmop *Next(){return next;}
	void setNext(pgmop *nxt){next = nxt;}
	virtual pgmop *DoOp() = 0;
};

class ControlData {
private:
	ControlData *next;
public:
	ControlData(){next = 0;};
	ControlData(ControlData *nxt){next = nxt;}
	void setNext(ControlData *nxt){next = nxt;}
   ControlData *Next(){return next;};
};

class pgm {
private:
	pgmop *first, *last;
	ControlData *cds;
public:
	pgm() {first = 0; last = 0; cds=0;}
	void Append(pgmop *p);

	void StartIf();
	void StartElse();
	void EndIf(int numb);
	void StartWhile();
	void WhileCond();
	void EndWhile();

	void Execute();
};

class pgmintstk: public pgmop {
private:
  long   no;
public:
	pgmintstk(int n){no = (long)n;};
	virtual pgmop *DoOp();
};

enum binop {add, subt, mult, adiv, land, lor, amax, amin,
				alt, agt, ale, age, aeq, ane};
class pgmbinop: public pgmop {
private:
	binop bnop;
public:
	pgmbinop(binop b){bnop = b;}
	virtual pgmop *DoOp();
};

class pgmchpush: public pgmop {
private:
	UNCH * p;
public:
	pgmchpush(UNCH * q);
	~pgmchpush();
	virtual pgmop *DoOp();
};

enum chbinop {ccn, clt, cgt, cle, cge, ceq, cne};

class pgmchbin: public pgmop {
private:
	chbinop op;
public:
	pgmchbin(chbinop o){op = o;}
	virtual pgmop *DoOp();
};

class pgmsubstr: public pgmop{
public:
	virtual pgmop *DoOp();
};

class pgmpad: public pgmop{
public:
	virtual pgmop *DoOp();
};

class pgmfind: public pgmop{
public:
	virtual pgmop *DoOp();
};

enum unops {unneg, unlneg, unc2i, uni2c, un2c2i, un2i2c,unupp,
				unlen};

class pgmunop: public pgmop {
private:
	unops op;
public:
	pgmunop(unops o){op = o;}
	virtual pgmop *DoOp();
};

class setpgmfmtopt: public pgmop {
private:
	UNCH opt;
public:
	setpgmfmtopt(UNCH o){opt = o;}
	virtual pgmop *DoOp();
};

class setpgmfmtfold: public pgmop {
public:
	virtual pgmop *DoOp();
};

class setpgmfmtindent: public pgmop {
public:
	virtual pgmop *DoOp();
};

class setpgmfmtout: public pgmop {
private:
	int   id;
public:
	setpgmfmtout(int i){id = i;}
	virtual pgmop *DoOp();
};

class setpgmfmtwadj: public pgmop {
private:
	int wtype1;
	char wtype2;
public:
	setpgmfmtwadj(int i, char j){wtype1 = i; wtype2 = j;}
// wtype1 is defined in dynamic.h as wpre, wpost or wrep
// wtype2 is defined in dynamic.h as formatwordpre ...
	virtual pgmop *DoOp();
};

extern basevalue *vars[100];

class pgmvarld: public pgmop { // loads value stack from variable
private:
	unsigned varn;
//	int /*boolean*/  lcl;
	valtype  vt;  // from dynamic.h: valstr, valnumb
public:
	pgmvarld(unsigned n,valtype v){varn= n;vt = v;}
	virtual pgmop *DoOp();
};

class pgmvarsv: public pgmop { // loads variable from value stack
private:
	unsigned varn;
//	int /*boolean*/  lcl;
public:
	pgmvarsv(unsigned n){varn= n;}
	virtual pgmop *DoOp();
};

class pgmclrlcl: public pgmop { // clears local var on value stack
private:
	unsigned n;
public:
	pgmclrlcl(unsigned m){n = m;}
	virtual pgmop *DoOp();
};

class pgminitvarn: public pgmop { // initializes num var in var list
private:
	unsigned n;
public:
	pgminitvarn(unsigned m){n = m;}
	virtual pgmop *DoOp();
};

class pgminitvars: public pgmop { // initializes str var in var list
private:
	unsigned n;
public:
	pgminitvars(unsigned m){n = m;}
	virtual pgmop *DoOp();
};

class pgminittidn: public pgmop { // initializes num var in var list
private:
	unsigned n;
public:
	pgminittidn(unsigned m){n = m;}
	virtual pgmop *DoOp();
};

class pgminittids: public pgmop { // initializes str var in var list
private:
	unsigned n;
public:
	pgminittids(unsigned m){n = m;}
	virtual pgmop *DoOp();
};

class pgmpush: public pgmop { // pushes new instance for var on value stack
private:
	unsigned n;
public:
	pgmpush(unsigned m){n = m;}
	virtual pgmop *DoOp();
};

class pgmpop: public pgmop { // pops old instance for var on value stack
private:
	unsigned n;
public:
	pgmpop(unsigned m) {n = m;}
	virtual pgmop *DoOp();
};

//extern unsigned noglobalvars;

#define PGMSTACKSZ 100

//=============================================================================

class pgmattrref: public pgmop {  // put attr ref value onto the stack
private:
	UNCH *cgi;
	int   no;
public:
	pgmattrref(UNCH *a, int n){cgi = a; no = n;}
	virtual pgmop *DoOp();
};

class pgmattrref2: public pgmop { // to be used when element name not known
private:
   UNCH *atname;
public:
   pgmattrref2(UNCH *n){atname = n;}
   virtual pgmop *DoOp();
};

//=============================================================================

class pgmoutput: public pgmop {  // output top of stack to "text" stream
public:
	virtual pgmop *DoOp();
};

class pgmerror: public pgmop {   // output top of stack as an error message
public:
	virtual pgmop *DoOp();
};

class pgmremark: public pgmop {  // output top of stack as a remark message
public:
	virtual pgmop *DoOp();
};

class pgminsblk: public pgmop {
public:
  virtual pgmop *DoOp();
};

class pgminelem: public pgmop {
private:
   UNCH *savedgi;
public:
   pgminelem(UNCH *gi){savedgi = gi;}
   virtual pgmop *DoOp();
};

class pgmiselem: public pgmop {
private:
   UNCH *savedgi;
public:
   pgmiselem(UNCH *gi){savedgi = gi;}
   virtual pgmop *DoOp();
};

class pgmelename: public pgmop {
public:
   virtual pgmop *DoOp();
};

class pgmnoop: public pgmop {
public:
	virtual pgmop *DoOp();
};

class pgmtest: public pgmop { // check top of stack, if true, take path in "tpath"
private:
	pgmop *tpath;
public:
	pgmtest(pgmop *n){tpath = n;}
	virtual pgmop *DoOp();
};

extern unsigned NumbTACTIds, NumbGlobalvars, MaxNumbVars;

void ResetRTVars(unsigned lvl);

void DoAllStrings(void (*f) (tactidstr *id));

void AppendTextToVar(int vn, unsigned l,UNCH * t);

void PgmSetup();
