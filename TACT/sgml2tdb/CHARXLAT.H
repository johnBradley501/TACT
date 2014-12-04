// Copyright (c) 1994 John Bradley

#include <stdio.h>

#define EOLSYMBOL 0x13

void InitialTranslation(UNCH *xfilename);

UNCH LookupIntName(UNCH * n);

UNCH *ProcessSDATA(UNCH * rslt, UNCH * t, unsigned l, unsigned &intl, ostream &ers);

int /*as BOOLEAN */ PrepareError(char *erin, UNCH * fn, int ln);

enum DupHanType {GiveError, UpdateEntry, DiscardEntry};

class XlateTableRec;

class XlateTable {
protected:
	XlateTableRec* md[10];
private:
	BOOLEAN InsertForMode(UNCH mdin, UNCH mdout,
								 UNCH * seqin, UNCH * seqout,
								 unsigned glen,
								 DupHanType DupWhat,
								 ostream & s);
public:
   XlateTable();

	XlateTableRec* FindMode(UNCH md);
	XlateTableRec* CopyMode(UNCH mdc){return md[mdc-'0'];}

	BOOLEAN InsertXlateData(UNCH mdin, UNCH mdout,
									UNCH * seqin, UNCH * seqout,
									unsigned glen,
									DupHanType DupWhat,
									ostream & s);
	BOOLEAN InsertXlateMode(UNCH mdin, UNCH mdout,
									UNCH * seqin,
									DupHanType DupWhat,
									ostream & s);
	BOOLEAN AddLitEscSeq(UNCH mdin, UNCH *seqin, ostream &s);
	void EquateData();
	void AddIfAbsent(UNCH cin, UNCH * cout);
} ;

class XlateEntryData;

class XlateTableWriteBase: public XlateTable{
private:
	unsigned lvl;
	void DoItem( XlateEntryData *p, unsigned lvl );
	void DoNext( XlateEntryData *p );

public:
	virtual void WriteData(void *, unsigned sz) = 0;
	void WriteXlate(XlateTable *xt);
};

extern XlateTable *Ext2Int, *Alp2Int, *Int2FAlp, *Int2Alp;

class XlateBase {
private:
	XlateTable* xt;
	UNCH ch, bdstr[2], ltstr[2], CurMd, InMd, OutMd;
	UNCH * outstr, * inbp;
	unsigned hldsz, inbpos, inbsiz, outpos, lwp, crp, cwp;
	UNCH sc[20];
	BOOLEAN eod;
	XlateEntryData *cq,*keep;

protected:
	bit256   goodc;
	virtual UNCH * GetInBuf(unsigned & inbsiz) = 0;
	void StartXlate();
	void SetEOD(){eod = 1;}
public:
	XlateBase(XlateTable & xt, UNCH BC = '?', bit256 *gc=0);
	unsigned GetData(UNCH * out, unsigned outlen, unsigned &numbin);
} ;

class XlateOnInput: public XlateBase {
private:
	FILE * ff;
	UNCH * buf;
protected:
	virtual UNCH * GetInBuf(unsigned & inbsiz);
public:
	XlateOnInput(XlateTable & xt, UNCH BC = '?');
	~XlateOnInput();
	BOOLEAN Open(const UNCH * name);
	void Close();
} ;

class XlateText: public XlateBase {
private:
	UNCH * buf;
	unsigned bufsz;
	int /*as boolean*/ bufdone;
protected:
	virtual UNCH * GetInBuf(unsigned & inbsiz);
public:
	XlateText(XlateTable & xt, UNCH BC = '?',bit256 *gdc=0);
	void DataIn(UNCH * inbuf, unsigned bfsize);
	unsigned int Translate(UNCH * inbuf, UNCH * outbuf, unsigned inlen, unsigned outlen);
   unsigned int Ignore(UNCH * inbuf, unsigned inlen);
} ;

extern XlateText *e2i;

