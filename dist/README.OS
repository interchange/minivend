# MiniVend V3.15
# 
# Copyright 1996-1999 by Michael J. Heins <mikeh@minivend.com>
#

                   M I S C E L L A N E O U S
                         O S   N O T E S


Operating   Recommended
System          DBM      Tested on     Notes
--------   -------------------------  -----------------------
Linux         GDBM       2.0.x & up    This is what MiniVend is
                                       developed on -- all features
                                       should work normally provided
                                       you have a good Perl. The
                                       best thing to do is install
                                       Perl 5.005 *without removing
                                       any RPM packages*.
                                      

    IMPORTANT NOTE FOR REDHAT 5.0:
    If MiniVend fails "make test" this usually means that the POSIX
    library is broken on the distributed Perl. You should update
    Perl.

    And RedHat 5.1 and earlier have *gaping* security holes,
    so you should update your operating system.

Windows 9x    DB_File    ?????         MiniVend may not stand up
                                       well for high-use
                                       catalogs. Some features
                                       cannot be used because
                                       of foreground operation;
                                       for instance modifying
                                       $Safe{config}.


Windows NT    DB_File    ?????         Some features of MiniVend
                                       will not work, mostly in
                                       support scripts. MiniVend
                                       will run as a service.
                                       Some features cannot be
                                       used because of foreground
                                       operation; for instance
                                       modifying $Safe{config}.


FreeBSD       DB_File     all          Many users run MiniVend on
                                       this OS. You need Perl 5.004,
                                       which not all BSD distributions
                                       provide (some have Perl 4 as
                                       the default Perl!).

BSDI          DB_File     all          Many users run MiniVend on
                                       this OS. You need Perl 5.004,
                                       which not all BSD distributions
                                       provide (some have Perl 4 as
                                       the default Perl!).

Solaris 2     GDBM       2.x           Many users run MiniVend on
                                       this OS, no known problems.
                                       Problems with installation
                                       are usually due to poor or
                                       missing development tools.

SunOS 4.1.x   DB_File    4.1.x         Has been known to run on
                                       this OS, no known problems.


DEC/OSF, aka  GDBM       3.0           Some users run MiniVend on
Digital UNIX                           this OS, no known problems.
                                       

IRIX          GDBM       5.3,6.2       Server may be difficult to
                                       stop for re-configuration,
                                       setting HouseKeeping value to
                                       10 or less is recommended. 
                                       Some reports of "zombie"
                                       processes probably due to
                                       signal handler problems.

HP/UX          -         10.1          A few users, may be some
                                       trouble with vlink/tlink
                                       compilation.

SCO            -         3.2           Should work fine as of MV3.05

AIX            -         4.1           Reported to work with little
                                       difficulty

UNIXware       -         2.1           Should work fine as of MV3.05

