# MiniVend V3.12
# 
# Copyright 1996-1998 by Michael J. Heins <mikeh@iac.net>
#
# Largely based on Vend 0.2
# Copyright 1995 by Andrew M. Wilcox
#
# Portions from Vend 0.3
# Copyright 1995,1996 by Andrew M. Wilcox
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

-------------------------------------------------------------
          M I N I V E N D   O N   W I N D O W S

    System Requirements:

        * Windows 95, 98 or Windows NT. Tested on Windows 95 OSR2.

        * Perl 5.004 for Win32 or higher -- accept no substitutes. THIS
          PROGRAM WILL RUN ON NO EARLIER VERSION OF PERL. PERIOD.  It
          will not run on the ActiveState port build 3xx series; it
          does appear to run very well with the "Merge" of the build
          500 series. The version you probably want is also variously
          known as the "CORE", "Standard", or "Gurusamy Sarathy" version.

        * Web server. Almost any that has CGI capability
          should work. Tested on Microsoft Personal Web Server,
          NT IIS, and OmniHTTPD.

        * Memory, memory, memory -- best guess is that things
          will not run well on less than 32 MB of RAM, but your
          mileage may vary. I don't trust the Windows system
          performance indicator, as it indicates 86% free RAM on
          my machine with 32M while MiniVend is running. I find
          it hard to believe. That is the smallest RAM machine
          I have, and MV ran fine on it -- it is a 486DX/100.

    IMPORTANT NOTE:

        If you use the Windows notepad or other editor which
        willy-nilly adds carriage returns, and you edit
        configuration files that may contain Perl code, or
        that use EOF markers, or have data, you may have to
        remove carriage returns before running MiniVend. If
        you have problems, perform the following commands from the
        DOS prompt:

            perl -npi.bak -e "s:\r::g" <file-you-edited>

        The error "illegal character \015" would be an indication
        of this problem.

        There are also reports that using DOS edit causes problems
        with profiles.

    Prior to Installation:

       1. Make sure Perl 5.004 is fully installed. Perl 5.004
          is mandatory -- you can get it at:

             http://www.perl.com/CPAN/ports/win32/Standard/x86/

          A list of CPAN sites is always available at:

             http://www.perl.com/CPAN

       2. From the same place you obtained Perl 5.004, get the
          DB_File module, latest version of which is 1.54
          at this writing. Install it according to the 
          instructions in the README.NOW file.

          If you have the ActiveState Perl 5.005, it should
          work OK once you use the PPM (find it in your 
          /perl/5.005XX/bin/ppm.pl) and get the following
          modules:
            
                DB_File
                MIME-Base64
                libwww

          The last two are to allow the new internal HTTP
          server to work and provide a semi-GUI installation.

          MiniVend might run without OK without DB_File, but
          the user database will not be persistent and there
          will be other anomalies.

       3. Obtain and install BLAT if you wish to 
          send emailed orders.

            http://gepasi.dbs.aber.ac.uk/softw/Blat.html

          Adjust the catalog.cfg parameter SendMailProgram
          according to the path that you install it at -- MiniVend
          should find it if it is in your path, and append the
          right options. An example of a SendMailProgram:

          SendMailProgram  blat - -t

          (You must run 'blat -install' before it will work. Try
          testing blat from the command line if your order is
          not sent.)
  
    Installation:

    1. Download the minivend-3.12.exe distribution file
    and run it in the normal Windows fashion.
    
    ( If you don't want to execute the self-extracting ZIP file,
      then you can obtain the standard minivend-3.12.tar.gz file and
      install that instead. )
      
      You will have to obtain the CYGWIN.DLL file if you want to
      use TLINK.EXE as your link CGI. The standard distribution .EXE
      file has it included -- the minivend-3.12-nodll.exe file
      eliminates it.

    2. Select a directory to install MiniVend in -- it defaults
    to /mvend on the default hard drive but you may put it anywhere.

    3. You will need to know where your Web document root and
    CGI directories are located.  The defaults are set for
    Microsoft personal web server.

    4. If your catalog is for testing purposes, you can
    use the server name "127.0.0.1". If you want the catalog
    to be accessible from the outside world, you will have
    to enter a valid IP address or server name.

    5. MiniVend will run as a service if you set it up with
    srvany.exe or a similar program. Because the server
    is single-tasked, it is recommended that you set up
    a system agent to shut down the MV server, expire the
    session database, and restart at least once per day.
    (Expiration will always be needed to prevent the DBM files
    or session directories from getting too big, and possible
    memory leaks in Safe.pm make this a good idea anyway.)

    6. Be careful of long-running searches -- because the server
    will not handle multiple simultaneous requests as it does
    on UNIX, searches will hold off user access. It is recommended
    that you break your results pages into small (less than the
    default 50-result) chunks by setting mv_matchlimit.

-------------------------------------------------------------

            W I N D O W S   D I F F E R E N C E S

      * ODBC works fine, but you will need to have the
        DBI::ODBC module properly installed. DBI also works
        with MS SQL Server according to user reports.

      * No fork() on Windows means that only one server
        can run at a time. This means multiple requests
        will be queued. In any case, lack of file locking
        would mean big problems for multiple servers. Perl's
        threading is too experimental to do the work required
        to make MV thread-safe.

      * Since the server runs in the foreground, if you change
        global variables in your embedded Perl you must be careful
        to reset them. In particular, the FRAMES version of the 
        3.12 demo will not work correctly.

      * Some of the support scripts will not work, and some
        might not behave as in the documentation. In particular,
        the expire script must not be run while the server
        is running, as no file locking is available.

      * You will need to hit Ctrl-C twice to stop the server
        with some ports of Perl. If you can't stop the server,
        close the DOS box.

      * Memory leaks in the Safe.pm module may mean that
        you will need to restart the server due to running
        out of memory. It is recommended that you shutdown
        and restart at least once a day.

