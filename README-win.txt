# MiniVend V3.07
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

        * Windows 95 or Windows NT. Tested on Windows 95
          and NT 4.0 workstation.

        * Perl 5.004 for Win32 -- accept no substitutes. THIS
          PROGRAM WILL RUN ON NO EARLIER VERSION OF PERL. PERIOD.
          It will NOT run on the ActiveState port.

        * Web server. Almost any that has CGI capability
          should work. Tested on Microsoft Personal Web Server
          NT IIS, and OmniHTTPD.

        * Memory, memory, memory -- best guess is that things
          will not run well on less than 32 MB of RAM, but your
          mileage may vary. I don't trust the Windows system
          performance indicator, as it indicates 86% free RAM on
          my machine with 32M while MiniVend is running. I find
          it hard to believe. That is the smallest RAM machine
          I have, and MV runs fine on it -- it is a 486DX/100.

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

          MiniVend will run without OK without DB_File, but
          will be slower.

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

    1. Download the minivend-3.07.exe distribution file
    and run it in the normal Windows fashion.
    
    ( If you don't want to execute the self-extracting ZIP file,
      then you can obtain the standard minivend-3.07.tar.gz file and
      install that instead. )
      
      You will have to obtain the CYGWIN.DLL file if you want to
      use TLINK.EXE as your link CGI. The standard distribution .EXE
      file has it included -- the minivend-3.07-nodll.exe file
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

-------------------------------------------------------------

            W I N D O W S   D I F F E R E N C E S

      * ODBC is not implemented yet, though some work has
        been done with Win32::ODBC and the DBI interface.

      * No fork() on Windows means that only one server
        can run at a time. This means multiple requests
        will be queued. In any case, lack of file locking
        would mean big problems for multiple servers.

      * The support scripts are mostly untested, and
        some probably will not work. In particular, the
        expire script must not be run while the server
        is running, as no file locking is available.

      * You will need to close the DOS window to stop
        the server, at least on Win95. 

        If you obtain the excellent Cygnus GNU toolset
        for Windows 95/NT, you can run bash.exe, enabling
        you to start the server with:

           perl /minivend/mvend/bin/minivend -serve &

        You can then use the kill.exe program to kill the
        server.

      * Many features are not tested, but the minimal
        functionality as outlined in the demo seems to
        work well, particularly when DB_File is used.

      * Memory leaks in the Safe.pm module may mean that
        you will need to restart the server due to running
        out of memory. It is recommended that you shutdown
        and restart at least once a day.

