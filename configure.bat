@echo off
perl Makefile.PL
configure2
echo If you got a bad command or filename message, this means you
echo do not have Perl in your PATH (or maybe even installed on your
echo machine).  See www.perl.com for information.
echo ------------------------------------------------------------
echo IF YOU DO HAVE PERL 5.004 installed,
echo unzip the file to a directory and try:
echo ------------------------------------------------------------
echo    cd minivend-3.10
echo    c:\perl\bin\perl Makefile.PL
