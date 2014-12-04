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
	memcpy(&tdbdata.TDBStr[kl+1],sp->IntStr,istrl);
	tdbdata.TotalWords = sp->TotWords;
	sp->S = TDBFile->AddPtrData(&tdbdata,4+kl+istrl);
	sp->S.Rec -= strstrt.Rec;
};

strcollectiondata::~strcollectiondata(){
	delete vals;
};

strcollectiondata::strcollectiondata(){
	vals = new BalTree;
	vcur = VirtNil;
};

va strcollectiondata::AddValue(UNCH *key, UNCH *str,long int TokenNo){
	StringRec *strdta;
	if (!(vcur == VirtNil)){
		strdta = (StringRec *)MakeReal(vcur);
		strdta->TotWords += TokenNumber - rcur->CurWordNo;
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
	strdta->CurWordNo = TokenNumber;
	MarkDirty(vcur); ReleasePage(vcur);
	return vcur;
};

UNCH strcollectiondata::WriteToDB(){
  // set the final tally for the last (currently active) entry
  StringRec *strdta = (StringRec *) MakeReal(vcur);
  strdta->TotWords += TokenNumber - strdta->CurWordNo;
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
//======================================================

allstrings::allstrings(int n){
	 numb = n;
	 dat = malloc(4*n);
	 sidx = malloc(n);
	 for(int i = 0; i < n; i++){dat[i] = 0; sidx[i] = 0;}
};

allstrings::~allstrings(){
	for(int i = 0; i < numb; i++)
		if (dat[i] != 0)delete dat[i];
	free(dat);
	free(sidx);
};

va allstrings::AddValue(int id, UNCH *key, UNCH *str,long int TokenNo){
	if (dat[id] == 0)dat[id] = new strcollectiondata;
	return dat[id]->AddValue(key,str,TokenNo);
};

void allstrings::WriteToDB(){
  	TDBFile->Header()->BeginStr = TDBFile->InitPtrData();
	HRecPntr strend = TDBFile->FinishPtrData();
	for(int i = 0; i < numb; i++){
		if(dat[i] != 0){
			sidx[i] = dat[i]->WriteToDB() ;  /* start index */
		}
	};
	TDBFile->Header()->EndStr = strend.Rec;


	TDBFile->Header()->BeginStrRec = TDBFile->FinishSection();
	TDBFile->Header()->NoStrRecs = 0 ;
	TDBRefStringData d;
	for(int i = 0; i < numb; i++){
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


long unsigned TokenNumber = 0; ??


void TheLog::DoLogListBase(int id, long int TokenNumber){
	va ve, dummy;
	LogListEntry *e = (LogListEntry *)AllocateSpace( ve, dummy, sizeof(LogListEntry) ) ;
	if(CurLog!= 0)CurLog->next = ve;
	else VLog = ve;
	ReleasePage(VCurLog);
	e->id = -id;  // here's where sign indicates type of data (minus -> string data)
	e->tokenno = TokenNumber;
	e->next = VirtNil;
	VCurLog = ve;
	CurLog = e;
};

void TheLog::Add(int id, UNCH *str, long int TokenNo/*,int force?*/){
	static UNCH alphs[128];
	IntToSortWord(str, alphs);
	DoLogListBase(id, TokenNumber);
	CurLog->d.vstrptr = as.AddValue(id, alphs, str, TokenNo);
   return VCurLog;
};

void TheLog::WriteToDB(){
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

