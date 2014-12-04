// Copyright (c) 1995 John Bradley

#include "config.h"
#include "tools.h"
#include "etype.h"
//#include "defines.h"
//This is a kludge:   j.b.
#define PNE int
#include <strstrea.h>
#include "resource.h"
#include "utils.h"
#include "charxlat.h"
#include "wordbase.h"

#define LETTERSYM 0
#define RETDIACSYM 1
#define NONRETDIACSYM 2
#define CONTCHARSYM 3
#define WORDSEPSYM 4

UNCH cdept = 2, savcdept;
unsigned ResetSCode = 0, InBracket = 0;

/*RES OLD MSG 66
The symbol "%0" appears twice.
*/
#define RESDUPMSG /*RES REM INS*/ 66

UNCH SimpAlphTable[256];
UNCH TypeOfChar[255]; // starting index is 1
unsigned SortNoBitsPerChar;
bit256 wordch;

unsigned NoBitsInCharSet(){
	UNCH ch = 0xFF, ch2 = 0x80;
	while ((TOC(ch) != LETTER) && (TOC(ch) != RETDIAC)) --ch;
	unsigned rslt = 8;
	while (!(ch & ch2)){--rslt; ch2 >>= 1;}
	return rslt;
} ;


int /*boolean*/ InsertToXlate(UNCH * seq, UNCH * iseq, unsigned bothalpha){
	ostrstream s;
	if (bothalpha) {
		if (!Int2Alp->InsertXlateData('0','0', seq,iseq,1,GiveError, s)){
			ResFile->MsgData(seq);
			ResFile->PutResError(RESDUPMSG);
			return 0 ;
		}
	}
	if (!Int2FAlp->InsertXlateData('0','0', seq,iseq,1,GiveError, s)){
		ResFile->MsgData(seq);
		ResFile->PutResError(RESDUPMSG);
		return 0 ;
	}
	return 1;
};

int /*boolean*/ InsertCode(UNCH * seq, unsigned symknd){
	UNCH aseq[2] = "a"; // "a" will be replaced!
	switch ( symknd ){
	case LETTERSYM :
		aseq[0] = ++cdept;
		wordch.on(cdept);
		TOC(cdept) = LETTER;
		if (ResetSCode)savcdept = cdept;
		if (InBracket && ResetSCode) ResetSCode = 0;
		SimpAlphTable[cdept] = savcdept;
		break;
	case RETDIACSYM :
		aseq[0] = ++cdept;
		wordch.on(cdept);
		TOC(cdept) = RETDIAC;
		SimpAlphTable[cdept] = 1;
		break;
	case NONRETDIACSYM :
		TOC(++cdept) = NONRETDIAC;
		aseq[0] = NONRETDIACCODE;
		break;
	case WORDSEPSYM :
		aseq[0] = ++cdept;
		TOC(cdept) = 0;
		break;
	case CONTCHARSYM :
		TOC(++cdept) = CONTINUATIONCHAR;
		aseq[0] = cdept;
		UNCH tmp[2]; tmp[0] = EOLSYMBOL; tmp[1] = 0;
		ustrcat(aseq, tmp);
		break;
	}
	if (!InsertToXlate(seq, aseq, 1)) return 0;
	if ((symknd != NONRETDIACSYM) && (symknd != CONTCHARSYM)){
		ostrstream s;
		if (!Alp2Int->InsertXlateData('0','0', aseq, seq,ustrlen(seq),GiveError, s)){
			/*RES OLD MSG 68
			There is an unexpected double occurrence of AlphaSeq!!  sequence: "%0".
			*/
			ResFile->MsgData(seq);
		   ResFile->PutResError( /*RES REM INS*/ 68);
		}
	}
	return 1;
};

int /*boolean*/ ProcessAlphaLine(UNCH *inl, unsigned symknd){
	enum {CharLook, RestChar, DoString, IntNameLook, IntNameGet} s;
	UNCH inln[256]  ;
	ustrcpy(inln, inl);
	ustrcat(inln, " ");
	s = CharLook;
	unsigned pos,op = 0;
	UNCH endstr, charsq[15], *intnp;
	for (pos = 0; inln[pos] != 0; pos++){
		switch (s) {
			case CharLook:
				if (inln[pos] != ' ') {
					if ((inln[pos] == '\'') || (inln[pos] == '"')){
						s = DoString;
						endstr = inln[pos];
						memset(charsq, 0, 15);
						op = 0;
					}
					else if (inln[pos] == '(') {
						if (InBracket){
							/*RES OLD MSG 69
							Please remove nested brackets in the Alphabet.
							*/
							ResFile->PutResError( /*RES REM INS*/ 69 );
							return 0;
						} else InBracket = 1;
					}
					else if ((inln[pos] == ')') && (InBracket)) {
						ResetSCode = 1; InBracket = 0;
					}
					else if (inln[pos] == '\\') {
						s = IntNameLook;
						memset(charsq, 0, 15);
						op = 0;
					}
					else {
						memset(charsq, 0, 15);
						charsq[0] = inln[pos];
						s = RestChar;
						op = 1;
					}
				}
				break;
			case RestChar:
				if (((inln[pos] == ')') && (InBracket)) || (inln[pos] == ' ')){
					if (!InsertCode(charsq, symknd)) return 0;
					if (inln[pos] != ' '){InBracket = 0; ResetSCode = 1;}
					s = CharLook;
				}
				else charsq[op++] = inln[pos];
				break;
			case DoString:
				if (inln[pos] == endstr) {
					if (!InsertCode(charsq, symknd)) return 0;
					s = CharLook;
				}
				else charsq[op++] = inln[pos];
				break;
			case IntNameLook:
				if (inln[pos] == '\\') {
					if (op == 0) {
						/*RES OLD MSG 591
						SGML2TDB has found a null Internal Name sequence.
						*/
						ResFile->PutResError(/*RES REM INS*/ 591);
						return 0;
					}
					if (!InsertCode(charsq, symknd)) return 0;
					s = CharLook;
				}
				else if (inln[pos] != ' ') {
					s = IntNameGet;
					intnp = &inln[pos];
				}
				break;
			case IntNameGet:
				if ((inln[pos] == ' ') || (inln[pos] == '\\')){
					UNCH tmp = inln[pos];
					inln[pos] = 0;
					UNCH c =  LookupIntName(intnp);
					s = IntNameLook;
					if (c == 0){
						/*RES OLD MSG 592
						SGML2TDB has found an invalid Internal Name "%0".
						*/
						ResFile->MsgData(intnp);
						ResFile->PutResError( /*RES REM INS*/ 592 );
						return 0;
					}
					else charsq[op++] = c;
					inln[pos] = tmp;
				}
				if (inln[pos] == '\\'){
					s = CharLook;
					if (!InsertCode(charsq, symknd)) return 0;
				}
				break;
		}
	}
	if (s == DoString) {
		/*RES OLD MSG 77
		The closing quote is missing: %0.
		*/
		ResFile->MsgData(endstr);
		ResFile->PutResError( /*RES REM INS*/ 77);
		return 0;
	}
	if ((s == IntNameLook) || (s == IntNameGet)){
		/*RES OLD MSG 78
		The "\" that closes an Internal String definition is missing.
		*/
		ResFile->PutResError( /*RES REM INS*/ 78);
		return 0;
	}
	return 1;
};

void BuildAlphabetXlate(LineCollection *&Alphabet, LineCollection *&RetDiac,
							  LineCollection *&NonRetD, LineCollection *&ContChar,
							  LineCollection *&SepChar){
	wordch.off();
	wordch.on(NONRETDIACCODE);
	cdept = 2 ;  //first real value is 3C
	ResetSCode = 1 ;
	Int2FAlp = new XlateTable;
	Int2Alp = new XlateTable;
	Alp2Int = new XlateTable;
	memset(SimpAlphTable, 0, 256);
	memset(TypeOfChar, 0, 255);

	Alphabet->Start();
	InBracket = 0 ;
	UNCH *txt;
	while (NULL != (txt=Alphabet->GetLine())){
		if (!ProcessAlphaLine(txt, LETTERSYM)) exit(100);
	}
	if (InBracket) {
		/*RES OLD MSG 79
		The Alphabet is missing a closing bracket.
		*/
		ResFile->PutResError( /*RES REM INS*/ 79);
		exit(100);
	}

	RetDiac->Start();
	while (NULL != (txt=RetDiac->GetLine())){
		if (!ProcessAlphaLine(txt, RETDIACSYM)) exit(100);
	}

	NonRetD->Start();
	while (NULL != (txt=NonRetD->GetLine())){
		if (!ProcessAlphaLine(txt, NONRETDIACSYM)) exit(100);
	}

	ContChar->Start();
	while (NULL != (txt=ContChar->GetLine())){
		if (!ProcessAlphaLine(txt, CONTCHARSYM)) exit(100);
	}

	SepChar->Start();
	while (NULL != (txt=SepChar->GetLine())){
		if (!ProcessAlphaLine(txt, WORDSEPSYM)) exit(100);
	} 

	/* force the use of a high character for delimeter in sorting */
	TOC(HIGHKEYCODE) = HIGHKEYCHAR ;
	UNCH cseq[2];
	cseq[0] = HIGHKEYCODE ;
	cseq[1] = 0 ;
	if (!InsertToXlate( cseq,cseq, 1 )) exit(200);

	Int2Alp->EquateData();
	Int2FAlp->EquateData();

	SortNoBitsPerChar = NoBitsInCharSet() ;

	};

//========================================================================

void FullToSortWord(UNCH *sword, UNCH *fword){
	unsigned int spos = 0, fpos = 0, xcp = 0, nrd = 0, lch = WORDSEPCODE;
	UNCH ch, xcd[256];
	while (fword[fpos] != 0) {
		ch = fword[fpos];
		switch (TOC(ch)){
			case LETTER:
			case HIGHKEYCHAR:
				sword[spos++] = SimpAlphTable[ch];
				if (SimpAlphTable[ch] != ch){
					xcd[xcp++] = fpos - nrd + 2;
					xcd[xcp++] = ch;
				}
				break;
			case RETDIAC:
				xcd[xcp++] = fpos + 2 - (nrd++);
				xcd[xcp++] = ch;
			default:
				if ((ch == WORDSEPCODE) && (lch != WORDSEPCODE)){
					xcd[xcp++] = fpos + 2;
					xcd[xcp++] = ch;
				} // else ignore the character
		} // case TOC(ch) ...
	lch = ch;
	fpos++;
	} // while (fword[fpos] != 0) ...
	if (xcp > 0){
		xcd[xcp] = 0;
		sword[spos++] = EXTRACODESEP;
		ustrcpy(&sword[spos], xcd);
	}
	else sword[spos] = 0;
}

void SortToFullWord(UNCH *fword, UNCH *sword){
  unsigned int xcdp = ustridx(sword, EXTRACODESEP);
  if (xcdp == 65535u){
	  ustrcpy(fword, sword);
	  return;
  }
  int spos = 0, epos, ixcd = 0,dne = 0;
  unsigned int fpos = 0, swlen = (xcdp++) - 1;
  UNCH ch;
  do {
	  if (sword[xcdp] == 0){
		  epos = swlen;
		  dne = 1;
	  }
	  else{
		  epos = sword[xcdp++] - 3;
		  ch = sword[xcdp++];
		  ixcd = 1;
	  }
	  while (spos <= epos)fword[fpos++] = sword[spos++];
	  if (ixcd){
		  fword[fpos++] = ch;
		  if (TOC(ch) == LETTER) spos++;
		  ixcd = 0;
	  }
  } while ((spos > swlen) || (!dne));
  fword[fpos] = 0;
};

void IntToFullWord(UNCH *iword, UNCH *fword){
	XlateText xl(*Int2Alp,(UNCH)WORDSEPCODE);
	xl.Translate(iword,fword,256,256);
};

void IntToSortWord(UNCH *iword, UNCH *sword){
	UNCH t[256];
	IntToFullWord(iword,t);
	FullToSortWord(sword, t);
};

unsigned int IntToNextSortWord(UNCH *iword, UNCH *sword,
						  UNCH *pre, UNCH *post, UNCH *replace){
						  //pre, post are in "full" format, replace is in sort format
	XlateText xl(*Int2Alp,(UNCH)WORDSEPCODE, &wordch);
	UNCH t[256];
	int i = 0;
	if(pre!=0){ustrcpy(t,pre); i = ustrlen(pre);}
	unsigned numbin = xl.Translate(iword,&t[i],256,256);
	if(replace!=0)ustrcpy(sword, replace);
	else{
		if(post!=0)ustrcat(t,post);
		FullToSortWord(sword, t);
	}
	return numbin;
};

unsigned int FindNextSortWord(UNCH *itxt){
	XlateText xl(*Int2Alp,(UNCH)WORDSEPCODE, &wordch);
	return xl.Ignore(itxt,256);
};

void SortToIntWord(UNCH *sword, UNCH *iword){
	UNCH t[256];
	SortToFullWord(sword,t);
	XlateText xl(*Alp2Int);
	xl.Translate(t,iword,256,256);
}

