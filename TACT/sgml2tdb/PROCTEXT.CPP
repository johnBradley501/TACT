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

/* this module was originally based on lineout.c, written for sgmls
   but substantially changed to meet the more specific needs of sgml2tdb.
                                   ... john bradley

	  lineout.c had been written by James Clark (jjc@jclark.com).
*/

#include <strstrea.h>
#include "config.h"
#include "std.h"
#include "entity.h"           /* Templates for entity control blocks. */
#include "adl.h"              /* Definitions for attribute list processing. */
#include "sgmlmain.h"         /* Main interface to SGML services. */
#include "sgmlfnsm.h"
//#include "appl.h"
#include "proctext.h"
#include "pgmproc.h"          /* line added by j.b. -> to TACT modules*/
#include "sgmlaux.h"          /* line added by j.b. */
#include "source.h"           /* line added by j.b. */
#include "vm.h"               /* line added by j.b. */
#include "dynamic.h"          /* line added by j.b. */
#include "pgmbase.h"          /* line added by j.b. */
#include "utils.h"
#include "defines.h"
#include "charxlat.h"

extern int suppsw;
extern int locsw;
int firstelm=1;      // set to 0 after first element has been processed jb.
extern int ts;                // Index of current tag in stack. from sgmlxtrn.h

// these are temporary j.b. (from old lineout.h)
#define REFERENCE_ENTITY_CODE '&'
#define DEFINE_NOTATION_CODE 'N'
#define DEFINE_EXTERNAL_ENTITY_CODE 'E'
#define DEFINE_INTERNAL_ENTITY_CODE 'I'
#define PI_CODE '?'
#define DEFINE_SUBDOC_ENTITY_CODE 'S'
#define START_SUBDOC_CODE '{'
#define END_SUBDOC_CODE '}'
#define LOCATION_CODE 'L'
#define APPINFO_CODE '#'
#define PUBID_CODE 'p'
#define SYSID_CODE 's'
#define FILE_CODE 'f'
#define CONFORMING_CODE 'C'
// end of temporary things j.b.

static VOID flush_data P((void));
static VOID define_external_entity P((PNE));
static VOID define_entity P((UNCH *));
static VOID output_notation P((UNCH *, UNCH *, UNCH *));
static VOID output_internal_entity P((UNCH *, int, UNCH *));
static VOID output_external_entity P((UNCH *, int, UNIV, UNCH *, UNCH *,
						UNCH *));
static VOID output_subdoc P((UNCH *, UNIV, UNCH *, UNCH *));
#ifdef SUPPORT_SUBDOC
static VOID process_subdoc P((UNCH *, UNIV));
#endif /* SUPPORT_SUBDOC */
static VOID output_entity_reference P((UNCH *));
static VOID output_processing_instruction P((UNS, UNCH *));

static VOID print_string P((UNS, UNCH *, int));
static VOID print_id P((UNIV, UNCH *, UNCH *));
static VOID print_filename P((char *));
static VOID output_location P((void));
static VOID output_appinfo P((UNS, UNCH *));

static int have_data = 0;
static char *current_filename = 0;
static unsigned long current_lineno = 0;

struct attrlist{
	int     size;
	UNCH   *cgi;
	UNCH   *val[100];
};

// struct formatData *fdstk; declared in dynamic.cpp
struct attrlist **atstk;
UNCH **gistk;

void makemytagstk(){
	  fdstk = (struct formatData *)rmalloc((TAGLVL+1)*sizeof(struct formatData));
	  atstk = (struct attrlist **)rmalloc((TAGLVL+1)*sizeof(void *));
	  gistk = (UNCH **)rmalloc((TAGLVL+1)*sizeof(void *));
	  static formatData s = {72,0,0,(UNCH *)0,(UNCH *)0,(UNCH *)0,
                            formatdisplay | formatcollect};
	  fdstk[0] = s;
     gistk[0] = 0;
};
//============================================================================
UNCH attrempty[1] = {0};
struct ad *thisalptr;


UNCH *GetAttrVal(UNCH* l, int n){
	int p = ts;
	for(p = ts; p >= 1; p--){
		if (0==ustrcmp(atstk[p]->cgi,l)){
			if (atstk[p]->val[n-1] != 0)return atstk[p]->val[n-1];
//			if (atstk[p]->val[n] != 0)return atstk[p]->val[n];
			else return attrempty;
		}
	}
	return attrempty;
};

void EmptyAttrlist(attrlist *a){
	int i;
	if (a->size  == 0)return;
	for (i = 0;i<a->size;i++)
		{if(a->val[i] != 0)
			free(a->val[i]);
		};
};

UNCH *get_token_list(struct ad *al, int aln)
{
     UNCH *ptr;
     int i;
	  if (ADTYPE(al, aln) == AENTITYS) {
		 ptr = ADVAL(al, aln);
		 for (i = 0; i < ADNUM(al, aln); i++) {
	       /* Temporarily make token look like normal
				 name with length and EOS. */
			 UNCH c = ptr[*ptr + 1];
	       ptr[*ptr + 1] = '\0';
	       *ptr += 2;
			 define_entity(ptr);
			 *ptr -= 2;
	       ptr += *ptr + 1;
			 *ptr = c;
		 }
	  }
	  UNCH work[256],*p, first=1;
	  p = work;
	  ptr = ADVAL(al, aln);
	  for (i = 0; i < ADNUM(al, aln); i++) {
	  /* The first byte is a length NOT including the length
		  byte; the tokens are not EOS terminated. */
		 if (first)first = 0;
		 else {p[0] = ' ',p++;};
		 memcpy((void *)p,(void *)(ptr+1),*ptr);
		 p += *ptr + 1;
		 ptr += *ptr + 1;
	  }
	  p[0] = 0;
	  return savestr(work);
}

UNCH *makestr(int ln,UNCH *s)
{
     UNCH *rp;

	  rp = (UNCH *)rmalloc(ln + 1);
	  memcpy(rp, s, ln);
	  rp[ln] = 0;
     return rp;
}

UNCH * get_single_token(struct ad *al, int aln){
	  if (ADTYPE(al, aln) == ANOTEGRP && !DCNMARK(ADDATA(al, aln).x))
		  printf("**Warning** NOTATION found in get_single_token\n");
//		  output_notation(ADVAL(al, aln) + 1,
//			  ADDATA(al, aln).x->pubid,
//			  ADDATA(al, aln).x->sysid);
	  else if (ADTYPE(al, aln) == AENTITY)
		  define_entity(ADVAL(al, aln));
	  if (ADTYPE(al, aln) == ACHARS)
		  return makestr(ustrlen(ADVAL(al, aln)), ADVAL(al, aln));
	  return makestr(*ADVAL(al, aln) - 2, ADVAL(al, aln) + 1);
}

attrlist *get_attributes(UNCH *cgi,struct ad *al){
	int aln, sz=2 + sizeof(ad *) + ADN(al)*sizeof(UNCH *);
	attrlist *atl = (attrlist *)rmalloc(sz);
	atl->size = ADN(al);
	atl->cgi = cgi;
	for (aln = 1; aln <= ADN(al); aln++) {
		 if (GET(ADFLAGS(al, aln), AERROR)) atl->val[aln-1] = 0;
		 else if (GET(ADFLAGS(al, aln), AINVALID)) atl->val[aln-1] = 0;
		 else if (ADVAL(al, aln) == NULL) atl->val[aln-1] = savestr((UNCH *)""); // was "IMPLIED"
//			 get_implied_attribute(&val[aln-1], ADNAME(al, aln));
		 else if (ADTYPE(al, aln) >= ATKNLIST) atl->val[aln-1] = get_token_list(al, aln);
		 else atl->val[aln-1] = get_single_token(al, aln);
		 if (BITON(ADFLAGS(al, aln), AGROUP)) aln += ADNUM(al, aln);
	  }
	return atl;
};

#define cleanadj(n) 	if ((fdstk[ts].wadj[n]!=0)&&(fdstk[ts].wadj[n]!=fdstk[ts-1].wadj[n]))delete fdstk[ts].wadj[n]

void SetWAdjs(int wtype1, char wtype2, UNCH *str){
	cleanadj(wtype1);
	fdstk[ts].formatoptions |= wtype2;
	fdstk[ts-1].formatoptions |= wtype2;
	fdstk[ts].wadj[wtype1] = str;
};

void CleanupWAdjs(){
	for (int i = 0; i < 3; i++){cleanadj(i);}
};

void HandleSDATA(int l, UNCH *t){
	char erc[100];
	ostrstream ers(erc, 100);
	UNCH tmp[256], *p;
	unsigned intl;
	if(0 == (p=ProcessSDATA(tmp, t, l, intl, ers))){
		char *fn;
		unsigned long ln;
		sgmlloc(&ln, &fn);
		PrepareError(ers.str(), (UNCH *)fn, (int)ln);
	}
	else AddSDATAToTDB(intl, p);
};

VOID process_document(int subdocsw)
{
	  enum sgmlevent rc;
	  struct rcbtag rcbtag;
     struct rcbdata rcbdaf;
	  static UNCH nl = '\n';

	  while ((rc = sgmlnext(&rcbdaf, &rcbtag)) != SGMLEOD) {
#ifdef SUPPORT_SUBDOC
		 if (rc == SGMLDAF && !CONTERSW(rcbdaf) && NDESW(rcbdaf)
	      && NEXTYPE(NEPTR(rcbdaf)) == ESNSUB) {
	       if (!suppsw && !sgmlment(NEENAME(NEPTR(rcbdaf))))
				 define_external_entity(NEPTR(rcbdaf));
	       process_subdoc(NEENAME(NEPTR(rcbdaf)) + 1,
			      NEID(NEPTR(rcbdaf)));
	       continue;
		 }
#endif /* SUPPORT_SUBDOC */
       pgm *pg;
		 if (!suppsw)
			 switch (rc) {
	       case SGMLDAF:
				if (CONTERSW(rcbdaf)) break;
				if (CDESW(rcbdaf))
				  AddTextToTDB(CDATALEN(rcbdaf), CDATA(rcbdaf));
				else if (SDESW(rcbdaf))
				  HandleSDATA(CDATALEN(rcbdaf), CDATA(rcbdaf));
				else if (NDESW(rcbdaf)) {
					assert(NEXTYPE(NEPTR(rcbdaf)) != ESNSUB);
					if (!sgmlment(NEENAME(NEPTR(rcbdaf))))
						define_external_entity(NEPTR(rcbdaf));
					output_entity_reference(NEENAME(NEPTR(rcbdaf)) + 1);
				}
				else AddTextToTDB(CDATALEN(rcbdaf), CDATA(rcbdaf));
				break;
			 case SGMLSTG:
				if (CONTERSW(rcbtag)) break;
				/* beginning of code added by j.b. */
				if (firstelm==1) {
					firstelm = 0;
					readsetupfiles(ioflid(SCBFCB));
					printf("-- SGML2TDB started reading the text.\n");
				}
				thisalptr = ALPTR(rcbtag);
				if (thisalptr)
					atstk[ts] = get_attributes(rcbtag.curgi,thisalptr);
				else atstk[ts] = 0;
				gistk[ts] = rcbtag.curgi;
				fdstk[ts] = fdstk[ts-1];
				curfd = &fdstk[ts];
				CurrentGILevel++;
				pg = (pgm *)*rcbtag.pgm;
				if (pg != 0)pg->Execute();
				break;
			 case SGMLETG:
				if (CONTERSW(rcbtag)) break;
				ts++;
			   pg = (pgm *)*rcbtag.pgm;
				if (pg != 0)pg->Execute();
				CleanupWAdjs();
				ts--;
				if (atstk[ts+1]!= 0){
					EmptyAttrlist(atstk[ts+1]);
					free(atstk[ts+1]);
				};
				curfd = &fdstk[ts];
				CurrentGILevel--;
				ResetRTVars(CurrentGILevel);
				break;
	       case SGMLPIS:
				if (CONTERSW(rcbdaf)) break;
				output_processing_instruction(PDATALEN(rcbdaf), PDATA(rcbdaf));
				break;
	       case SGMLREF:
				if (CONTERSW(rcbdaf)) break;
				AddTextToTDB(1, &nl);
				break;
			 case SGMLAPP:
				if (CONTERSW(rcbdaf)) break;
				if (!subdocsw)
					output_appinfo(ADATALEN(rcbdaf), ADATA(rcbdaf));
				break;
	       default:
				abort();
	       }
     }
}

/* provide an indication that the document was conforming. */

int /*boolean*/ was_conforming(){return (!suppsw) ;} // old was "output_conforming" j.b.

int /*boolean*/ InElement(UNCH *gi /*pointer to GI*/){
   for (int i = ts; i > 0; i--)
     if (gistk[i] == gi)return 1;
   return 0;
};

UNCH *CurElement(){
   return gistk[ts];
};

static VOID define_external_entity(PNE p)
{
     if (NEXTYPE(p) == ESNSUB)
		 output_subdoc(NEENAME(p) + 1, NEID(p), NEPUBID(p), NESYSID(p));
     else {
		 if (!NEDCNMARK(p))
			 output_notation(NEDCN(p) + 1, NEDCNPUBID(p), NEDCNSYSID(p));
		 output_external_entity(NEENAME(p) + 1, NEXTYPE(p), NEID(p),
				 NEPUBID(p), NESYSID(p), NEDCN(p) + 1);
		 if (NEAL(p))
			 printf("**warning** Handle-Attributes needed in define_external_entity");
//			 handle_attributes(NEENAME(p) + 1, NEAL(p));
     }
}

static VOID define_entity(UNCH *ename)
{
     int rc;
	  PNE np;
     UNCH *tp;
     
	  if (sgmlment(ename))		/* already defined it */
		 return;
     rc = sgmlgent(ename, &np, &tp);
     switch (rc) {
     case 1:
		  define_external_entity(np);
	  break;
     case 2:
     case 3:
		  output_internal_entity(ename + 1, rc == 3, tp);
	  break;
     }
}

static VOID output_notation(UNCH *name, UNCH *pubid, UNCH *sysid)
{
	  flush_data();
	  print_id((UNIV)0, pubid, sysid);
	  printf("%c%s\n", DEFINE_NOTATION_CODE, name);
}

static VOID output_internal_entity(UNCH *ename, int is_sdata, UNCH *text)
{
	  flush_data();
     printf("%c%s %s ", DEFINE_INTERNAL_ENTITY_CODE, ename,
	    is_sdata ? "SDATA" : "CDATA");
     print_string(text ? ustrlen(text) : 0, text, 0);
     putchar('\n');
}

static VOID output_subdoc(UNCH *nm, UNIV id, UNCH *pubid, UNCH *sysid)
{
	  flush_data();
     print_id(id, pubid, sysid);
     printf("%c%s\n", DEFINE_SUBDOC_ENTITY_CODE, nm);
}

#ifdef SUPPORT_SUBDOC

static VOID process_subdoc(UNCH *nm, UNIV id)
{
     if (!suppsw) {
		 flush_data();
		 output_location();
		 printf("%c%s\n", START_SUBDOC_CODE, nm);
		 fflush(stdout);
     }
     fflush(stderr);

     if (id) {
		 char **argv;
		 int ret;

		 argv = make_argv(id);
		 ret = run_process(argv);
		 if (ret != 0)
	       suberr++;
	  
		 current_filename = 0;
		 free(argv);
		 if (ret == 0)
	       get_subcaps();
     }
     else {
		 suberr++;
		 appl_error(E_SUBDOC, nm);
     }

     if (!suppsw)
		 printf("%c%s\n", END_SUBDOC_CODE, nm);
}

#endif /* SUPPORT_SUBDOC */

static VOID output_external_entity(UNCH *nm, int xtype, UNIV id,
											  UNCH *pubid, UNCH *sysid, UNCH *dcn)
{
     char *type;

	  flush_data();

     print_id(id, pubid, sysid);

     switch (xtype) {
     case ESNCDATA:
		 type = "CDATA";
		 break;
     case ESNNDATA:
		 type = "NDATA";
		 break;
     case ESNSDATA:
		 type = "SDATA";
		 break;
     default:
		 return;
     }
     printf("%c%s %s %s\n", DEFINE_EXTERNAL_ENTITY_CODE, nm, type, dcn);
}

static VOID output_entity_reference(UNCH *s)
{
     flush_data();
	  output_location();
	  printf("%c%s\n", REFERENCE_ENTITY_CODE, s);
}

static VOID output_processing_instruction(UNS n, UNCH *s)
{
	  flush_data();
     output_location();
     putchar(PI_CODE);
     print_string(n, s, 0);
     putchar('\n');
}

static VOID output_appinfo(UNS n, UNCH *s)
{
	  flush_data();
     output_location();
     putchar(APPINFO_CODE);
     print_string(n, s, 0);
     putchar('\n');
}

static VOID flush_data()
{
     if (have_data) {
	  putchar('\n');
	  have_data = 0;
     }
}

static VOID output_location()
{
	  char *filename;
     unsigned long lineno;
     int filename_changed = 0;

	  if (!locsw) return;
	  if (!sgmlloc(&lineno, &filename)) return;
	  if (!current_filename || strcmp(filename, current_filename) != 0)
		  filename_changed = 1;
     else if (lineno == current_lineno)
		  return;
     flush_data();
     printf("%c%lu", LOCATION_CODE, lineno);
     current_lineno = lineno;
     if (filename_changed) {
		 putchar(' ');
		 print_filename(filename);
		 current_filename = filename;
     }
     putchar('\n');
}

static VOID print_string(UNS slen, UNCH *s, int is_sdata)
{
	  if (is_sdata)
		  fputs("\\|", stdout);
	  while (slen > 0) {
		  UNCH ch = *s++;
		  slen--;
		  if (ch == DELSDATA) {
	       if (is_sdata)
		    ;		/* I don't think this should happen */
			 else fputs("\\|", stdout);
	       ;
		  }
		  else if (ch == DELCDATA)
	       ;
		  else {
			 if (ch == DELNONCH) {
				if (!slen) break;
				ch = UNSHIFTNON(*s);
				s++;
				slen--;
	       }
			 switch (ch) {
	       case RECHAR:
				fputs("\\n", stdout);
				break;
	       case '\\':
				fputs("\\\\", stdout);
				break;
	       default:
				if (ISASCII(ch) && isprint(ch))
				  putchar(ch);
				else
				  printf("\\%03o", ch);
				break;
	       }
	  }
     }
	  if (is_sdata)
	  fputs("\\|", stdout);
}
		    

static VOID print_id(UNIV id, UNCH *pubid, UNCH *sysid)
{

     if (pubid) {
		 putchar(PUBID_CODE);
		 print_string(ustrlen(pubid), pubid, 0);
		 putchar('\n');
     }

     if (sysid) {
		 putchar(SYSID_CODE);
		 print_string(ustrlen(sysid), sysid, 0);
		 putchar('\n');
     }

     if (id) {
		 char *p;

		 for (p = (char *)id; *p != '\0'; p++) {
	       putchar(FILE_CODE);
	       do {
				switch (*p) {
				case '\\':
					fputs("\\\\", stdout);
					break;
				case '\n':
				  fputs("\\n", stdout);
				  break;
				default:
				  if (ISASCII(*p) && isprint((UNCH)*p))
			      putchar(*p);
				  else
			      printf("\\%03o", (UNCH)*p);
				  break;
				}
	       } while (*++p);
	       putchar('\n');
	  }
     }
}

static VOID print_filename(char *s)
{
     for (; *s; s++)
	  switch (*s) {
	  case '\\':
	       fputs("\\\\", stdout);
	       break;
	  case '\n':
	       fputs("\\n", stdout);
	       break;
	  default:
	       if (ISASCII(*s) && isprint((UNCH)*s))
		    putchar(*s);
	       else
		    printf("\\%03o", (UNCH)*s);
	       break;
	  }
};

int GetAttrNo(struct ad*adl, UNCH *n){
  capstr(n);
  int aln;
  if (adl != 0){
	  for (aln = 1; aln <= ADN(adl); aln++){
		  if (ustrcmp(ADNAME(adl, aln),n)==0)return aln;
		  if (BITON(ADFLAGS(adl, aln), AGROUP)) aln += ADNUM(adl, aln);
	  }
  }
  return -1;
};

UNCH *GetAttrValForTop(UNCH *n){
  int no;
  if (thisalptr == 0)return 0;
  if (-1 == (no = GetAttrNo(thisalptr, n))) return 0;
  return atstk[ts]->val[no-1];
};
