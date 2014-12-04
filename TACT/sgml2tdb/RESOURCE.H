// copyright (c) 1994 John Bradley

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

#if !defined(defines_here)
#define defines_here 0
#include "defines.h"
#endif

#include <stdio.h>
#include <classlib\arrays.h>
#include <iostream.h>

struct ResPos
{  unsigned high;
	unsigned low; };

BOOLEAN inline IsNullRes(const ResPos r) {return (!r.high) && (!r.low);}

class msgdatabase {
	protected:
		unsigned givsz;
		virtual void output(ostream &s) = 0;
	public:
		msgdatabase(int sz=0) {givsz = sz;}
		friend ostream &operator<<(ostream &s, msgdatabase &v);
		int operator==(const msgdatabase& c) const {return c.givsz;};
	};

typedef TIArrayAsVector<msgdatabase> msgarray;
class msgdataarray: public msgarray
{ public:
msgdataarray(): msgarray(20,0,5) {}
} ;

enum TResData {MessageRes, DataArrRes, MenuRes, HelpRes, ChoiceRes,
                  NumbArrRes};

class resfile
{ private:
   FILE *ResFile;
	ResPos ResPntrs[6 /* Number of items in TResData */ ];
	msgdataarray MsgDataArray;
//	TIArrayAsVector<msgdatabase> MsgDataArray(20,0,5);
	int MsgItemNo;

public:
	resfile(const UNCH *FName);

	ResPos FindRes(TResData rt, int in);

	BOOLEAN RdResBase(int numb, ResPos loc, void *dta, unsigned &got);
	void * RdResBase(int numb, ResPos loc, unsigned &got);

// messages from res file
	void MsgData(UNCH * s);
	void MsgData(unsigned d);
	void MsgData(long unsigned d);
	void MsgData(UNCH s);
	void ResMessage(int numb, ostream &s);

	void PutResError(int numb);
	void PutResWarning(int numb);
	void PutResMessage(int numb);

	void * GetResNA(unsigned id, unsigned &sz);
} ;

extern resfile *ResFile;

class ResCollection{
	private:
		unsigned mxsz;
		unsigned cp;
		UNCH * dt;
	public:
		ResCollection(resfile & rs, TResData tp, int id);
		~ResCollection(){free(dt);}

		void * Next(int &sz);
		void * Prev(int &sz);
		void ReStart(){cp = 0;};
} ;

class ResStrCollection: public ResCollection{
public:
	ResStrCollection(resfile & rs, int id): ResCollection(rs, DataArrRes, id){}
	BOOLEAN NextC(UNCH * r);
	BOOLEAN PrevC(UNCH * r);
} ;

class ResStringLookup: public ResCollection{
private:
	int num;
	void * dta;
public:
	ResStringLookup(resfile & rs, int id);
	unsigned Lookup(UNCH * r);
	UNCH * operator[](int index);
	} ;
