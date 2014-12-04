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


//SGML2TDB runs under 32 bit addressing -- the virtual memory handling code
//is not needed there, and is "dummied out" here.  A braver man would probably
//have removed all references to it -- I leave it in so that it can be
//re-established if needed in the future for some reason or other.  Goodness
//knows it was hard enough to get it right in the days of 640K!

#include <stdlib.h>

class va{
public:
	void *p;
	int operator ==(va q){return q.p == p;}
};

extern va VirtNil; //defined in utils.cpp

inline void InitVirtualMemory(){};
inline void *AllocateSpace(va &rslt, va dummy, unsigned sze)
	{return rslt.p = malloc(sze);};
inline void MarkInUse(va &rslt){};
inline void*MakeReal(va &d){return d.p;};
inline void ReleasePage(va &v){};
inline void MarkDirty(va &v){};
inline void InitSpaceType(va &v){v = VirtNil;};
inline void endva(){};
