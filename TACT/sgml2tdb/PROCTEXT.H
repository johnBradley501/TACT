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

enum {
     E_NOMEM = 1,
     E_DOC,
     E_EXEC,
     E_FORK,
     E_WAIT,
     E_SIGNAL,
     E_OPEN,
     E_CAPBOTCH,
     E_SUBDOC
};


void makemytagstk();

VOID process_document P((int));
int /*boolean*/ was_conforming P((void));

UNCH *GetAttrVal(UNCH* l, int n);
int GetAttrNo(struct ad*adl, UNCH *n); // -1 mean value not present.
UNCH *GetAttrValForTop(UNCH *n); // 0 means no such attribute present

void SetWAdjs(int wtype1, char wtype2, UNCH *str);
// wtype1 is defined in dynamic.h as wpre, wpost or wrep
// wtype2 is defined in dynamic.h as formatwordpre ...
// str is not copied in SetWAdjs

int /*boolean*/ InElement(UNCH *gi /*pointer to GI*/);
UNCH *CurElement(); /* returns pointer to GI*/


UNIV xmalloc P((UNS));
UNIV xrealloc P((UNIV, UNS));
VOID appl_error VP((int, ...));

#ifdef SUPPORT_SUBDOC
int run_process P((char **));
char **make_argv P((UNIV));
VOID get_subcaps P((void));
#endif

#ifdef SUPPORT_SUBDOC
extern int suberr;
#endif

extern int suppsw;
extern int locsw;
