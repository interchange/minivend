#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define CGIUSER  503
#define PERL     "/usr/bin/perl"
#define VEND     "/home/vend/vend.pl"

int main(argc, argv)
     int argc;
     char** argv;
{
  uid_t euid;
  gid_t egid;
  int r;

  if (getuid() != CGIUSER) {
    printf(
"Content-type: text/plain

SVEND must be run from HTTPD.  (Check CGIUSER in svend.c)
");
    exit(1);
  }

  euid = geteuid();
  r = setreuid( euid, euid );
  if (r == -1) {
    printf(
"Content-type: text/plain

Could not set uid: %s
",
	   strerror(errno));
    exit(1);
  }

  egid = getegid();
  r = setregid( egid, egid );
  if (r == -1) {
    printf(
"Content-type: text/plain

Could not set gid: %s
",
	   strerror(errno));
    exit(1);
  }

  execl(PERL, PERL, VEND);
  printf("
Content-type: text/plain

Could not exec %s: %s
",
	 PERL,
	 strerror(errno));
  exit(1);
}
