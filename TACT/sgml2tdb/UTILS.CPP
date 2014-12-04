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

// Utils functions
 #include "config.h"
 #include "tools.h"
 #include <string.h>
 #include <stdio.h>
 #include <stdlib.h>
 #include <io.h>
 #include <dos.h>
 #include <ctype.h>
 #include "vm.h"
 #include "utils.h"


UNCH TACTPath[256];
UNCH zero = 0;
va VirtNil = {0};

inline int Exists(UNCH *filename)
 {
	return (access((char *)filename, 0) == 0);
 }
void FindFileInList(const UNCH *fn, const UNCH *l, UNCH *r)
{
	 ustrcpy(r, fn);
	 if (Exists(r)) return;
	 UNCH lc[256];
	 UNCH *p;
	 ustrcpy(lc, l);
	 for(p = strtok((char *)lc, ","); p != NULL; p = strtok(NULL, ","))
	 {
		 ustrcpy(r, p);
		 strcat((char *)r, "\\");
		 strcat((char *)r, (char *)fn);
		 if (Exists(r)) return;
	 }
	 r[0] = 0;
}

void GetTACTpath(UNCH *pt)
{
	UNCH *ptr;
	ptr = (UNCH *)getenv("TACTPATH");
	if (ptr != NULL) { ustrcpy(pt, ptr); return;}
	ptr = (UNCH *)getenv("PATH");
	ustrcpy(pt, ptr);
}

void capstr(UNCH *st)
{
	for (int i = 0; st[i] != 0; i++) st[i] = toupper(st[i]);
}

unsigned ustridx(UNCH *s, UNCH ch){
	unsigned p;
	for (p = 0; s[p] != 0; p++) if (s[p] == ch) return p;
	return 65535;
}

class RecordLine {
public:
	RecordLine*   nxt;
	UNCH          line[256];
}  ;

LineCollection::~LineCollection(){
	cur = first;
	while (cur != NULL){ first = cur; cur = cur->nxt; delete first;}
}

void LineCollection::AddItem(UNCH *txt){
	RecordLine *tmp = new RecordLine;
	tmp->nxt = NULL;
	ustrcpy(tmp->line,txt);
	if (first == NULL){ cur = first = last = tmp;}
	else {last->nxt = tmp; last = tmp;}
}

void LineCollection::Start() {cur = first;}

UNCH * LineCollection::GetLine(){
	if (cur == NULL) return NULL;
	RecordLine *tmp = cur;
	cur = cur->nxt;
	return tmp->line;
}

	bit256::bit256(){memset(&dta,0,32);}
	void bit256::on(){memset(&dta,0xFF,32);}
	void bit256::off(){memset(&dta,0,32);}

	bit256 operator ~(bit256 a){
		bit256 b;
		for(int i=0; i < 16;i++)b.dta[i] = ~a.dta[i];
		return b;
	};

UNCH *appendstr(UNCH *s, unsigned l, UNCH *t){
	int ls = ustrlen(s);
	UNCH *rp = (UNCH *)malloc(ls + l + 1);
	memcpy(rp, s, ls);
	memcpy(rp+ls, t, l);
	rp[ls+l] = 0;
   return rp;
};
