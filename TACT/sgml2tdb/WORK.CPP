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

#define FORMATFILL (curfd->formatoptions & formatfill)
#define FORMATCOMPRESS (curfd->formatoptions & formatcompress)
#define FORMATCENTRE (curfd->formatoptions & formatcentre)
#define FORMATDISPLAY (curfd->formatoptions & formatdisplay)
#define FORMATCOLLECT (curfd->formatoptions & formatcollect)

#define TABSIZE 5

class FormattingEvent {
protected:
	FormattingEvent   nxt;
public:
	FormattingEvent(){nxt = 0;}
	void SetNext(FormattingEvent *p){nxt = p;}
	FormattingEvent *GetNext(){return nxt;}
	virtual FormattingEvent *DoEvent(){return nxt;}
};

class SetCollectEvent: public FormattingEvent {
private:
	int val;
public:
	SetCollectEvent(int v){val = v;}
	FormattingEvent *DoEvent();
};

class FinishEventGroup: public FormattingEvent {
public:
	FormattingEvent *DoEvent(){return 0;}
};

class ValArrayEvent: public FormattingEvent {
private:
	valarray *cva;
public:
	ValArrayEvent(valarray *c){cva = c;}
	~ValArrayEvent(){delete cva;}
	FormattingEvent *DoEvent(){return nxt;}
};

//class FormattingEvent {
//private:
//	valarray *cva;
//	int      wcol;
//	FormattingEvent   nxt;
//public:
//	FormattingEvent(valarray *cur, int wordcollecting)
//		{cva = cur; wcol = wordcollecting; nxt = 0;}
//	~FormattingEvent(){delete cva;}
//	valarray *GetValarray(){return cva;}
//	int Getwordcollecting(){return wcol;}
//	void SetNext(FormattingEvent *p){nxt = p;}
//	FormattingEvent *GetNext(){return nxt;}
//};

class FormattingQueue {
private:
	FormattingEvent *start, *tail;
public:
	FormattingQueue(){start = 0; tail = 0;}
	void Add(FormattingEvent *evt){
		if (start == 0)start = tail = evt;
		else {tail->SetNext(evt); tail = evt;}
	}
//	valarray *GetValarray(){return start->GetValarray();)
//	int Getwordcollecting(){return start->Getwordcollecting();}
	void DoGroup(){
		FormattingEvent *tmp = start;
		while (tmp != 0){
			tmp = tmp->DoEvent();
			FormattingEvent *tmp2 = start->GetNext();
			delete start;
			start = tmp;
		};
	}
};

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


class formattext{
private:
	UNCH    txt[80], txt2[160];
//	int     tp,lp, indent, fold, sz2, colstrt, oldcoll /*this is boolean */,
//                lethimhaveit /*this is also boolean*/, lastblk;
	FormattingQueue fq;
	int      tp,tlen, btp, oldcoll, indent, fold,colnow;
	va       vpl; //log pointer value at previous entry to Text method.

	void    FinishLine();
	void    WriteTxt(char *txt2, int i, int j);
	void    CollectWords();
public:
	formattext()
	  {lp = 0;tp = 0;sz2 = 0;colstrt = 0; oldcoll = 0;
	  lethimhaveit=1; lastblk = 0; colnow = 1;

	  btp = tp = tlen = 0; vpl = VirtNil;
	  oldcoll = 0;}
	void Text(unsigned l,UNCH * t);
	void FinishText();
};

void formattext::Text(unsigned l,UNCH * t){
	if(FORMATDISPLAY == 0)return;
	if (oldcoll && (!FORMATCOLLECT))AddEvent(new CollectingOff);
	else
	if ((!oldcoll) && FORMATCOLLECT)AddEvent(new CollectingOn);
	oldcoll = FORMATCOLLECT;

	if (!(vpl == VCurLog)){vpl = VCurLog; AddEvent(new NewLog(VCurLog));}

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
				lastblk = 0;
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
			else {
				if ((tlen >= fold)&&(btp != 0)) {
					int hldtp = tp, j;
					UNCH hldch = txt[btp+1]; // FinishLine will set this to '\0'
					tp = btp;
					FinishLine();
					txt[btp+1] = hldch;
					lethimhaveit = 0==FORMATCOMPRESS;
					for (j = lastblk+1;j < hldtp; j++){
						txt[tp++]=txt[j];
						if (txt[j] != '\t')tlen++;
					}
				}
				txt[tp++] = ch;
				tlen++;
				if (ch == ' ') {btp = tp-1; lethimhaveit = 0==FORMATCOMPRESS;}
				else lethimhaveit = 1;
			}
		}
	}
};

void formattext::WriteTxt(char *txt2, int i, int j){
	for(int k = i; (k < j) && (txt2[k] != 0); k++){
		if (txt2[k] = '\t'){
			fq->DoGroup();
			if (j == 9999) return;
		}
		else TDBFile->AppendChar(txt2[k]);
	}
};

void formattext::CollectWords(){
	int i = 0,j;
	UNCH wd[100];
	while(txt2[i] != 0){
	  if (collecting){
		  j = i + FindNextSortWord(&txt2[i]);
		  WriteTxt(txt2, i, j);
		  i = j;
		  if ((collecting)&&txt2[i] != 0){
			  j = i + IntToNextSortWord(&txt2[i], wd);
			  HandleWord(wd, TDBfile->CurrentPos(), UsingLog);
			  WriteTxt(txt2, i, j);
			  i = j;
		  }
	  }
	  else {
		  WriteTxt(txt2, i, 9999);
	  }
	}
};

void formattext::FinishLine(){
	HRecPntr hr;
	if (tlen > 0){
		int noblks = indent;
		if (FORMATCENTRE)noblks += (fold - llen)/2;
		if ((tlen > 0) && (noblks > 0)){
			UNCH blks[80];
			memset(blks,' ',noblks); blnks[noblks] = 0;
			hr = TDBFile->AppendSpn(blks,noblks);
		}
		e2i->Translate(txt, txt2, 80, 160);
		CollectWords();
	}
	btp = tlen = tp = 0;
	TDBFile->AppendSpn("\r", 1);
	lineno->inc();
};

void formattext::FinishText(){
	if (tlen != 0) FinishLine();
}

