// copyright (c) 1996 John Bradley

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

extern UNCH zero;

void FindFileInList(const UNCH *fn, const UNCH *l, UNCH *r);

void GetTACTpath(UNCH *pt);

void capstr(UNCH *st);

UNCH *appendstr(UNCH *s, unsigned l, UNCH *t); // similar to savestr

unsigned ustridx(UNCH *s, UNCH ch); // returns 65535 if failed

class RecordLine;

class LineCollection {
private:
	RecordLine   *first, *last, *cur;
public:
	LineCollection(){first = NULL; last = NULL;}
	~LineCollection();
	void AddItem(UNCH * txt);
	void Start();
	UNCH *GetLine();
} ;

class bit256 {
private:
	unsigned int  dta[16];
public:
	bit256();
	void on();
	void off();
	void on(unsigned i){dta[i>>4] |= (0x0001<<(i&0x000F));}
	void off(unsigned i){dta[i>>4] &= ~(0x0001<<(i&0x000F));}
	int operator [](unsigned i){return dta[i>>4] & (0x0001<<(i&0x000F));}
	friend bit256 operator ~(bit256 a);
};


