/* mat.c:  runs as a cgi program and starts up MAT,
			 MiniVend Administration tool

   $Id: svend.c,v 1.1 1996/07/13 20:08:34 mike Exp mike $

   Copyright 1996 by Mike Heins <mikeh@iac.net>

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

   $Log: svend.c,v $
   Revision 1.1  1996/07/13 20:08:34  mike
   Initial revision

   Revision 1.1  1996/03/06 08:35:22  mike
   Initial revision


*/

#define CGIUSER  505
#define PERL     "/usr/bin/perl"
#define VEND     "/c/t/minivend.pl"

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
    printf("SVEND must be run from HTTPD.  (Check CGIUSER in svend.c)\n");
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

  execl(PERL, PERL, VEND, 0);
  printf("Content-type: text/plain\n\n");
  printf("Could not exec %s: %s", PERL, strerror(errno));
  exit(1);
}
