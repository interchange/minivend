# MiniVend V3.05
# 
# Copyright 1996,1997 by Michael J. Heins <mikeh@minivend.com>
#

                   M I S C E L L A N E O U S
                         O S   N O T E S

OS          Recommended DBM    Tested on     Notes
--------   -----------------  ------------  -----------------------
Linux         GDBM             2.0.x & up    This is what MiniVend is
                                             developed on -- all features
                                             should work normally.
                                             Running with Linux 1.2.13
                                             or lower is not recommended.


Windows 95    DB_File          ?????         Initial port. Probably will
                                             not run well for high-use
                                             catalogs. Some features
                                             of MiniVend, notably SQL, will
                                             not work. Server will not stop
                                             from the keyboard, you must close
                                             the DOS window to stop.


Windows NT    DB_File          ?????         Initial port. Not tested
                                             by author, but reported to
                                             run. Probably will not run
                                             well for high-use catalogs.
                                             Some features of MiniVend,
                                             notably SQL, will not work.


FreeBSD       DB_File          2.1.0, 2.1.5  Many users run MiniVend on
                                             this OS.


BSDI          DB_File          2.1, 3.0      Many users run MiniVend on
                                             this OS. The vlink UNIX mode
                                             will not work with V3.x but
                                             tlink/INET works fine.


Solaris 2     GDBM             2.4,2.5       Many users run MiniVend on
                                             this OS, no known problems
                                             once you get it going.
                                             File::Lock not needed for
                                             Perl 5.004 -- using Perl 5.004
                                             is highly recommended.


SunOS 4.1.x   DB_File          4.1.x         Some users run MiniVend on
                                             this OS, no known problems.


DEC/OSF, aka  GDBM             3.0           Some users run MiniVend on
Digital UNIX                                 this OS, no known problems.
                                             

IRIX          GDBM             5.3,6.2       Server may be difficult to
                                             stop for re-configuration,
                                             setting HouseKeeping value
                                             to 10 or less is recommended.
                                             No other known problems.

HP/UX          -               10.1          A few users, may be some
                                             trouble with vlink/tlink
                                             compilation.

SCO            -               3.2           Should work fine as of 3.04

AIX            -               4.1           Reported to work with little
                                             difficulty

UNIXware       -               2.1           Should work fine as of 3.04

