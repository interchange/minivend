# MiniVend V3.07
# 
# Copyright 1996-1998 by Michael J. Heins <mikeh@minivend.com>
#

                   M I S C E L L A N E O U S
                         O S   N O T E S

OS          Recommended DBM    Tested on     Notes
--------   -----------------  ------------  -----------------------
Linux         GDBM             2.0.x & up    This is what MiniVend is
                                             developed on -- all features
                                             should work normally.

    IMPORTANT NOTE FOR REDHAT 5.0:
    If MiniVend fails "make test" this usually means that the POSIX
    library is broken on the distributed Perl. You can update
    Perl or define the environment variable MINIVEND_BADPOSIX to 1.
	See the README file under "K N O W N   P R O B L E M S"

Windows 95    DB_File          ?????         MiniVend may not stand up
                                             well for high-use
                                             catalogs. Some features
                                             of MiniVend, notably SQL, may
                                             not work. Server will not stop
                                             from the keyboard, you must close
                                             the DOS window to stop.


Windows NT    DB_File          ?????         Probably will not run
                                             well for high-use catalogs.
                                             Some features of MiniVend,
                                             notably SQL, will not work.


FreeBSD       DB_File          2.1.0, 2.1.5  Many users run MiniVend on
                                             this OS. You need Perl 5.004.


BSDI          DB_File          2.1, 3.0      Many users run MiniVend on
                                             this OS. The vlink UNIX mode
                                             will not work with V3.x but
                                             tlink/INET works fine. You
											 need Perl 5.004 -- the
											 5.003_02 that comes with 3.x
											 probably will not work. 


Solaris 2     GDBM             2.4,2.5       Many users run MiniVend on
                                             this OS, no known problems
                                             once you get it going.
                                             File::Lock not needed for
                                             Perl 5.004 -- using Perl 5.004
                                             is mandatory. Problems with
                                             installation are usually due
											 to poor or missing development
											 tools.

SunOS 4.1.x   DB_File          4.1.x         Some users run MiniVend on
                                             this OS, no known problems.


DEC/OSF, aka  GDBM             3.0           Some users run MiniVend on
Digital UNIX                                 this OS, no known problems.
                                             

IRIX          GDBM             5.3,6.2       Server may be difficult to
                                             stop for re-configuration,
                                             setting HouseKeeping value to
											 10 or less is recommended. No
											 other known problems provided
											 you have good development
											 tools.


HP/UX          -               10.1          A few users, may be some
                                             trouble with vlink/tlink
                                             compilation.


SCO            -               3.2           Should work fine as of 3.05

AIX            -               4.1           Reported to work with little
                                             difficulty

UNIXware       -               2.1           Should work fine as of 3.05

