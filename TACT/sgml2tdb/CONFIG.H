/* dos.cfg: Configuration file for sgmls on MS-DOS. */

/* Define this if your compiler supports prototypes. */
#define USE_PROTOTYPES 1

/* Define this if you do not have strerror(). */
/* Borland C++ has strerror(), but it adds a newline to the end of the
message, so don't use it. */
//#define STRERROR_MISSING 1

/* Define this if you have getopt(). */
/* #define HAVE_GETOPT 1 */

#ifndef HAVE_GETOPT
/* #define OPTION_CHAR '/' */
/* Use MS-DOS (undocumented) system call to get switch character. */
#define SWITCHAR 1
#define REORDER_ARGS 1
/* #define CASE_INSENSITIVE_OPTIONS 1 */
#endif

/* A list of filename templates to use for searching for external entities.
See sgmls.man for details. */
#define DEFAULT_PATH "C:\\SGML\\%N.%X;%N.%X;%N.%D"
/* The character that separates the filenames templates. */
#define PATH_FILE_SEP ';'
/* The character that separates filenames in a system identifier.
Usually the same as PATH_FILE_SEP. */
#define SYSID_FILE_SEP ';'
/* The environment variable that contains the list of filename templates. */
#define PATH_ENV_VAR "SGML_PATH"

/* Define this if open() understands the O_NOINHERIT flag.  This tells
DOS that subprocesses should not inherit the file descriptor. */
#define HAVE_O_NOINHERIT 1

/* When turning a minimum literal into a filename, each character in
MIN_DAT_SUBS_FROM will be replaced by the character at the
corresponding position in MIN_DATA_SUBS_TO.  If there is no such
character, then the character will be stripped. */

#define MIN_DAT_SUBS_FROM " +,./:=?"
#define MIN_DAT_SUBS_TO   ""

/* Define this if you have access(). */
#define HAVE_ACCESS 1

/* Define this if you have <unistd.h>. */
/* #define HAVE_UNISTD_H 1 */

/* Define this if you have a Unix-style <sys/stat.h>. */
#define HAVE_SYS_STAT_H 1

/* Define this to strip an extension off the program name in argv[0],
   before using it in error messsages. */
#define PROG_STRIP_EXTENSION 1

/* Define this to fold the program name in argv[0] to lower case,
   before using it in error messsages. */
#define PROG_FOLD 1

/* Before using argv[0] in error messages, strip off everything up to and
including the last character in prog that occurs in PROG_PREFIX. */
#define PROG_PREFIX "\\/:"

/* Define this to allow tracing.*/
/* #define TRACE_IT 1 */
/* j.b. name changed to TRACE_IT to avoid conflicting use of TRACE by Borland */

/* Define this you want support for subdocuments.  This is implemented
using features that are not part of Standard C. */
//j.b. was: #define SUPPORT_SUBDOC 1

/* Define this if your shell does not allow you conveniently to
redirect errors to a file.  Then sgmls will provide an option (-f)
that does this. */
#define CANT_REDIRECT_STDERR 1

typedef void *UNIV;           /* Universal (i.e., undefined) pointer type. */
typedef void VOID;            /* void as a function return type */

/* If you don't have <limits.h>, define CHAR_SIGNED as 1 or 0
according to whether the `char' type is signed. */
/* #define CHAR_SIGNED 1 */
/* #define CHAR_SIGNED 0 */
#ifndef CHAR_SIGNED
#include <limits.h>
#if CHAR_MIN < 0
#define CHAR_SIGNED 1
#else
#define CHAR_SIGNED 0
#endif
#endif /* not CHAR_SIGNED */

/* Assume the system character set is ISO Latin-1. */
#include "latin1.h"
