#define CGIUSER  65534
#define PERL     "/usr/bin/perl"
#define MAT      "/usr/local/lib/minivend/bin/mat"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#ifdef sun
int sys_nerr;
char* sys_errlist[];
#define NEED_STRERROR
#endif

#ifdef NEED_STRERROR
static char* strerror(e)
     int e;
{
  if (e == 0)
    return "System call failed but errno not set";
  else if (e < 1 || e >= sys_nerr)
    return "No description available for this error";
  else
    return sys_errlist[e];
}
#endif

int main(argc, argv)
     int argc;
     char** argv;
{
  uid_t euid;
  gid_t egid;
  int r;

  if (getuid() != CGIUSER) {
    printf("Content-type: text/plain\n\n");
    printf("MAT must be run from HTTPD.  (Check CGIUSER in mat.c)\n");
    exit(1);
  }

  euid = geteuid();
  r = setreuid( euid, euid );
  if (r == -1) {
    printf("Content-type: text/plain\n\n");
    printf("Could not set uid: %s\n", strerror(errno));
    exit(1);
  }

  egid = getegid();
  r = setregid( egid, egid );
  if (r == -1) {
    printf("Content-type: text/plain\n\n");
    printf("Could not set gid: %s\n", strerror(errno));
    exit(1);
  }

  execl(PERL, PERL, MAT, 0);
  printf("Content-type: text/plain\n\n");
  printf("Could not exec %s: %s", PERL, strerror(errno));
  exit(1);
}
