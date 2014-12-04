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

/* main.cpp -
	Main program for sgml2tdb.
	Much of this code is taken directly from main.c for sgmls
	  which was written by James Clark (jjc@jclark.com).
										 -- john bradley 1994
*/
#include <strstrea.h>
#include "alloc.h" /* jb */
#include "config.h"
#include "std.h"
#include "getopt.h"
#include "entity.h"           /* Templates for entity control blocks. */
#include "adl.h"              /* Definitions for attribute list processing. */
#include "sgmlmain.h"         /* Main interface to SGML services. */
#include "proctext.h"
//#include "appl.h"	      // this line was instead of proctext.h in sgmls j.b.

#include "utils.h"            /* jb: utils for the nontact world */
#include "resource.h"         /* jb: access mechanisms for tact.res */
#include "charxlat.h"         /* jb: nontact translatioin mechanisms */
#include "vm.h"
#include "dynamic.h"          /* jb: contains procedure to finish TDB after text */

#define READCNT 512


/* Before using argv[0] in error messages, strip off everything up to and
including the last character in prog that occurs in PROG_PREFIX. */

#ifndef PROG_PREFIX
#define PROG_PREFIX "/"
#endif /* not PROG_PREFIX */

/* Message catalogue name. */
#define CAT_NAME "sgml2tdb"
/* Message set to use for application error messages. */
#define APP_SET 4

#ifdef HAVE_EXTENDED_PRINTF
#define xvfprintf vfprintf
#else
extern int xvfprintf P((FILE *, char *, va_list));
#endif

static VOID usage P((void));
static VOID fatal VP((int, ...));
static VOID do_error P((int, va_list));
static VOID swinit P((struct switches *));

static UNIV make_docent P((int, char **));
static char *munge_program_name P((char *, char *));
static VOID die P((void));
#ifdef SUPPORT_SUBDOC
static VOID build_subargv P((struct switches *));
static VOID cleanup P((void));
static char *create_subcap_file P((void));
#endif /* SUPPORT_SUBDOC */

static char *errlist[] = {
     0,
     "Out of memory",
     "Cannot open SGML document entity",
     "Cannot exec `%s': %s",
     "Cannot fork: %s",
     "Error waiting for process: %s",
     "Program %s got fatal signal %d",
     "Cannot open `%s': %s",
     "Subdocument capacity botch",
     "Non-existent subdocument entity `%s' not processed",
};

int suppsw = 0;			/* Non-zero means suppress output. */
int locsw = 0;			/* Non-zero means generate location info. */
static char *prog;		/* Program name (for error messages). */
static nl_catd catd;		/* Message catalogue descriptor. */
//extern char *version_string;

char options[] = {
	  'd', 'e', 'g', 'i', ':', 'l', 'o', ':', 'p', 'r', 's', 'u', 'x', ':',
#ifdef CANT_REDIRECT_STDERR
	  'f', ':',
#endif /* CANT_REDIRECT_STDERR */
#ifdef TRACE_IT
	  'y', ':', 'z', ':',
#endif /* TRACE_IT */
     '\0'
};

#ifdef SUPPORT_SUBDOC
int suberr = 0;			/* Error in subdocument. */
static char *subargv[sizeof(options)];
static int subargc = 0;
static char nopenbuf[sizeof(long)*3 + 1];
static char sgmldecl_file[L_tmpnam];
static char subcap_file[L_tmpnam];
#endif

UNCH *xfilename = 0;

void StartJBsStuff() /* this procedure is code from John Bradley */
{
	extern far char TACTPath[256];
	extern far resfile *ResFile;
	GetTACTpath(&*TACTPath); // from Utils.h
	UNCH trp[256];
	FindFileInList("TACTJB.RES", &*TACTPath, &*trp);
	if (trp[0] == 0){exit(10);}
	ResFile = new resfile(&*trp);
	InitialTranslation(xfilename);
	UNCH t[100]; t[1] = 0;
	ostrstream s;
	t[0] = ESCLEN1;
	Ext2Int->AddLitEscSeq('0',t, s);
	t[0] = ESCLEN0;
	Ext2Int->AddLitEscSeq('0',t, s);

	/*RES OLD DTA 37
	"SGML2TDB Version 1.0 Beta(a)"
	"containing the sgmls parser written by James Clark"
	"other SGML2TDB code written by John Bradley"
	*/
	ResStrCollection rs(*ResFile, /*RES REM INS*/ 37 );
	while (rs.NextC(t))printf("%s\n",t);
}

int main(int argc, char * argv[])
{
     static char stderr_buf[BUFSIZ];
     int opt;
#ifdef CANT_REDIRECT_STDERR
	  char *errfile = 0;
#endif
	  struct sgmlcap cap;
     struct switches sw;
	  int nincludes = 0;	      /* number of -i options */
	  setbuf(stderr, stderr_buf);
	  StartJBsStuff();

     /* Define MAIN_HOOK in config.h if some function needs to be called here. */
#ifdef MAIN_HOOK
	  MAIN_HOOK(argc, argv);
#endif
#ifdef SUPPORT_SUBDOC
	  subargv[subargc++] = argv[0];
#endif

	  prog = argv[0] = munge_program_name(argv[0], "sgml2tdb");

	  catd = catopen(CAT_NAME, 0);
     swinit(&sw);

     while ((opt = getopt(argc, argv, options)) != EOF) {
	  switch (opt) {
	  case 'l':	      /* Generate location information. */
	       locsw = 1;
	       break;
	  case 's':	      /* Suppress output. */
	       suppsw = 1;
	       break;
	  case 'd':           /* Report duplicate entity declarations. */
	       sw.swdupent = 1;
	       break;
	  case 'e':           /* Provide entity stack trace in error msg. */
	       sw.swenttr = 1;
	       break;
#ifdef CANT_REDIRECT_STDERR
	  case 'f':	      /* Redirect errors. */
			 errfile = optarg;
			 break;
#endif /* CANT_REDIRECT_STDERR */
	  case 'g':           /* Provide GI stack trace in error messages. */
			 sw.sweltr = 1;
	       break;
	  case 'p':	      /* Parse only the prolog. */
	       sw.onlypro = 1;
	       suppsw = 1;
	       break;
	  case 'r':           /* Give warning for defaulted references. */
	       sw.swrefmsg = 1;
	       break;
	  case 'u':
	       sw.swundef = 1;
			 break;
	  case 'x':
	  		 xfilename = appendstr(optarg, 4, (UNCH *)".XDT");
			 break;
#ifdef TRACE_IT
	  case 'y':	       /* Trace options for the document body. */
			 sw.trace = optarg;
			 break;
	  case 'z':	       /* Trace options for the prolog. */
	       sw.ptrace =  optarg;
	       break;
#endif /* TRACE_IT */
//	  case 'v':	       /* Print the version number. */
//			 fprintf(stderr, "sgml2tdb version %s\n", version_string);
//			 fprintf(stderr, "based on sgmls version %s\n", "1.1");
//			 fflush(stderr);
//	       break;
	  case 'o':
	       sw.nopen = atol(optarg);
	       if (sw.nopen <= 0)
		    usage();
	       break;
	  case 'i':	      /* Define parameter entity as "INCLUDE". */
	       sw.includes = (char **)xrealloc((UNIV)sw.includes,
					       (nincludes + 2)*sizeof(char *));
	       sw.includes[nincludes++] = optarg;
	       sw.includes[nincludes] = 0;
	       break;
	  case '?':
	       usage();
	  default:
			 abort();
	  }
     }
//	  StartJBsStuff();

#ifdef CANT_REDIRECT_STDERR
     if (errfile) {
	  FILE *fp;
	  errno = 0;
	  fp = fopen(errfile, "w");
	  if (!fp)
	       fatal(E_OPEN, errfile, strerror(errno));
	  fclose(fp);
	  errno = 0;
	  if (!freopen(errfile, "w", stderr)) {
	       /* Can't use fatal() since stderr is now closed */
	       printf("%s: ", prog);
	       printf(errlist[E_OPEN], errfile, strerror(errno));
	       putchar('\n');
	       exit(EXIT_FAILURE);
	  }
     }
#endif /* CANT_REDIRECT_STDERR */

     (void)sgmlset(&sw);

#ifdef SUPPORT_SUBDOC
     build_subargv(&sw);
#endif
     if (sgmlsdoc(make_docent(argc - optind, argv + optind)))
	  fatal(E_DOC);

     process_document(sw.nopen > 0);
/* jb added below
     fprintf(stderr, "Coreleft after doc processing: %ld\n",coreleft());

	jb added above */
     sgmlend(&cap);
#ifdef SUPPORT_SUBDOC
     cleanup();
     if (suberr)
	  exit(EXIT_FAILURE);
#endif /* SUPPORT_SUBDOC */
     if (sgmlgcnterr() > 0)
	  exit(EXIT_FAILURE);
// following line changed by j.b. because sgml2tdb has more to do after parsing sgml!
	  if ((!sw.nopen) && was_conforming()){
		  printf("-- SGML2TDB finished reading the text.\n");
		  CompleteTDB();
/* jb added below
                  fprintf(stderr, "Coreleft after TDB creation: %ld\n",coreleft());
   jb added above */
	          printf("-- SGML2TDB completed normally.\n");
	  }
	  else {
		  printf("SGML2TDB stops -- input text was not conforming");
		  return EXIT_FAILURE;
	  }
	  return EXIT_SUCCESS; // jb: was "exit(EXIT_SUCCESS);"
}

static char *munge_program_name(char *arg, char *dflt)
{
	  char *p;
#ifdef PROG_STRIP_EXTENSION
     char *ext;
#endif
     if (!arg || !*arg)
	  return dflt;
     p = strchr(arg, '\0');
     for (;;) {
	  if (p == arg)
	       break;
	  --p;
	  if (strchr(PROG_PREFIX, *p)) {
	       p++;
	       break;
	  }
     }
     arg = p;
#ifdef PROG_STRIP_EXTENSION
     ext = strrchr(arg, '.');
     if (ext) {
	  p = (char *)xmalloc(ext - arg + 1);
	  memcpy(p, arg, ext - arg);
	  p[ext - arg] = '\0';
	  arg = p;
     }
#endif /* PROG_STRIP_EXTENSION */
#ifdef PROG_FOLD
#ifdef PROG_STRIP_EXTENSION
     if (!ext) {
#endif
	  p = (char *)xmalloc(strlen(arg) + 1);
	  strcpy(p, arg);
	  arg = p;
#ifdef PROG_STRIP_EXTENSION
     }
#endif
     for (p = arg; *p; p++)
	  if (ISASCII((unsigned char)*p) && isupper((unsigned char)*p))
	       *p = tolower((unsigned char)*p);
#endif /* PROG_FOLD */
     return arg;
}

static UNIV make_docent(int argc, char * argv[])
{
     UNS len = 1;
     int i;
     UNIV res;
     char *ptr;
     static char *stdinname = STDINNAME;

     if (argc == 0) {
	  argv = &stdinname;
	  argc = 1;
     }

     for (i = 0; i < argc; i++)
	  len += strlen(argv[i]) + 1;
     
     res = xmalloc(len);
     ptr = (char *)res;
     for (i = 0; i < argc; i++) {
	  strcpy(ptr, argv[i]);
	  ptr = strchr(ptr, '\0') + 1;
     }
     *ptr = '\0';
     return res;
}


static VOID usage()
{
     /* Don't mention -o since this are for internal use only. */
     fprintf(stderr, "Usage: %s [-deglprsu]%s [-c file] [-i entity]%s [filename ...]\n",
	     prog,
#ifdef CANT_REDIRECT_STDERR
	     " [-f file]",
#else /* not CANT_REDIRECT_STDERR */
	     "",
#endif /* not CANT_REDIRECT_STDERR */
#ifdef TRACE_IT
	     " [-x flags] [-y flags]"
#else /* not TRACE_IT */
	     ""
#endif /* not TRACE_IT */
	     );
     exit(EXIT_FAILURE);
}

static VOID die()
{
#ifdef SUPPORT_SUBDOC
     cleanup();
#endif /* SUPPORT_SUBDOC */
     exit(EXIT_FAILURE);
}

static VOID swinit(struct switches *swp)
{
     swp->swenttr = 0;
     swp->sweltr = 0;
     swp->swbufsz = READCNT+2;
     swp->prog = prog;
     swp->swdupent = 0;
     swp->swrefmsg = 0;
#ifdef TRACE_IT
     swp->trace = 0;
     swp->ptrace = 0;
#endif /* TRACE_IT */
     swp->catd = catd;
     swp->swambig = 1;	      /* Always check for ambiguity. */
     swp->swundef = 0;
     swp->nopen = 0;
     swp->onlypro = 0;
     swp->includes = 0;
     swp->die = die;
}

#ifdef SUPPORT_SUBDOC

static VOID build_subargv(struct switches *swp)
{
     if (suppsw)
	  subargv[subargc++] = "-s";
     if (locsw)
	  subargv[subargc++] = "-l";
     if (swp->swdupent)
	  subargv[subargc++] = "-d";
     if (swp->swenttr)
	  subargv[subargc++] = "-e";
     if (swp->sweltr)
	  subargv[subargc++] = "-g";
     if (swp->swrefmsg)
	  subargv[subargc++] = "-r";
#ifdef TRACE_IT
     if (swp->trace) {
	  subargv[subargc++] = "-x";
	  subargv[subargc++] = swp->trace;
     }
     if (swp->ptrace) {
	  subargv[subargc++] = "-y";
	  subargv[subargc++] = swp->ptrace;
     }
#endif /* TRACE_IT */
     subargv[subargc++] = "-o";
     sprintf(nopenbuf, "%ld", swp->nopen + 1);
     subargv[subargc++] = nopenbuf;
}


static
VOID handler(int sig)
{
     signal(sig, SIG_DFL);
     cleanup();
     raise(sig);
}

static
VOID cleanup()
{
     if (sgmldecl_file[0]) {
	  (void)remove(sgmldecl_file);
	  sgmldecl_file[0] = '\0';
     }
     if (subcap_file[0]) {
	  (void)remove(subcap_file);
	  subcap_file[0] = '\0';
     }
}

static
char *store_sgmldecl()
{
     if (!sgmldecl_file[0]) {
	  FILE *fp;
	  if (signal(SIGINT, SIG_IGN) != SIG_IGN)
	       signal(SIGINT, handler);
#ifdef SIGTERM
	  if (signal(SIGTERM, SIG_IGN) != SIG_IGN)
	       signal(SIGTERM, handler);
#endif /* SIGTERM */
#ifdef SIGPIPE
	  if (signal(SIGPIPE, SIG_IGN) != SIG_IGN)
	       signal(SIGPIPE, handler);
#endif
#ifdef SIGHUP
	  if (signal(SIGHUP, SIG_IGN) != SIG_IGN)
	       signal(SIGHUP, handler);
#endif
	  tmpnam(sgmldecl_file);
	  errno = 0;
	  fp = fopen(sgmldecl_file, "w");
	  if (!fp)
	       fatal(E_OPEN, sgmldecl_file, strerror(errno));
	  sgmlwrsd(fp);
	  fclose(fp);
     }
     return sgmldecl_file;
}

static
char *create_subcap_file()
{
     if (subcap_file[0] == '\0') {
	  FILE *fp;
	  tmpnam(subcap_file);
	  fp = fopen(subcap_file, "w");
	  if (!fp)
	       fatal(E_OPEN, subcap_file, strerror(errno));
	  fclose(fp);
     }
     return subcap_file;
}

char ** make_argv(UNIV id)
{
     int nfiles;
     char *p;
     char **argv;
     int i;

     for (p = (char *)id, nfiles = 0; *p; p = strchr(p, '\0') + 1)
	  nfiles++;
     
     argv = (char **)xmalloc((subargc + 2 + 1 + nfiles + 1)*sizeof(char *));
     memcpy((UNIV)argv, (UNIV)subargv, subargc*sizeof(char *));
     
     i = subargc;

     argv[i++] = "-c";
     argv[i++] = create_subcap_file();

	  argv[i++] = store_sgmldecl();

     for (p = (char *)id; *p; p = strchr(p, '\0') + 1)
	  argv[i++] = p;
     argv[i] = 0;
     return argv;
}

VOID get_subcaps()
{
     long cap[NCAPACITY];
     FILE *fp;
     int i;

     if (!subcap_file[0])
	  return;
     errno = 0;
     fp = fopen(subcap_file, "r");
     if (!fp)
	  fatal(E_OPEN, subcap_file, strerror(errno));
     for (i = 0; i < NCAPACITY; i++)
	  if (fscanf(fp, "%*s %ld", cap + i) != 1)
	       fatal(E_CAPBOTCH);
     fclose(fp);
     sgmlsubcap(cap);
}


#endif /* SUPPORT_SUBDOC */

UNIV xmalloc(UNS n)
{
     UNIV p = malloc(n);
     if (!p)
	  fatal(E_NOMEM);
     return p;
}

UNIV xrealloc(UNIV s, UNS n)
{
	  s = s ? realloc(s, n) : malloc(n);
     if (!s)
	  fatal(E_NOMEM);
     return s;
}

static
#ifdef VARARGS
VOID fatal(va_alist) va_dcl
#else
VOID fatal(int errnum,...)
#endif
{
#ifdef VARARGS
     int errnum;
#endif
     va_list ap;
     
#ifdef VARARGS
     va_start(ap);
     errnum = va_arg(ap, int);
#else
     va_start(ap, errnum);
#endif
     do_error(errnum, ap);
     va_end(ap);
     exit(EXIT_FAILURE);
}

#ifdef VARARGS
VOID appl_error(va_alist) va_dcl
#else
VOID appl_error(int errnum,...)
#endif
{
#ifdef VARARGS
     int errnum;
#endif
     va_list ap;
     
#ifdef VARARGS
     va_start(ap);
     errnum = va_arg(ap, int);
#else
     va_start(ap, errnum);
#endif
     do_error(errnum, ap);
     va_end(ap);
}

static
VOID do_error(int errnum, va_list ap)
{
     char *text;
     fprintf(stderr, "%s: ", prog);
     assert(errnum > 0);
     assert(errnum < sizeof(errlist)/sizeof(errlist[0]));
     text = catgets(catd, APP_SET, errnum, errlist[errnum]);
     assert(text != 0);
     xvfprintf(stderr, text, ap);
     fputc('\n', stderr);
     fflush(stderr);
}

/*
Local Variables:
c-indent-level: 5
c-continued-statement-offset: 5
c-brace-offset: -5
c-argdecl-indent: 0
c-label-offset: -5
comment-column: 30
End:
*/
