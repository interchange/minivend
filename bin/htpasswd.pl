#!/usr/bin/perl
#
# htpasswd by Nem W Schlecht
#
#  Modified 1/7/96 by Mark Solomon to include checking for current 
#   	users - the original just appended each successive new password for 
#	the same person as a new line, not deleting the old.
#
# Modified 1/8/96 by Mike Heins to make salt more random and turn off
# echo
# Modified 2/8/96 by Mike Heins to forgive -c option

&GetArgs;               # Get Command line args or die
&LoadPwFile;            # Load current passwordfile 
                        # (I'll add file locking later)
print &Prompt;          # Prompt for password
system("stty -echo");   # Turn off echo
chop($pass=<>);         # Get new password
system("stty echo");    # Turn on echo again
print "\n";             # Our enter wasn't echoed, print one now
&MakeNewPassword;       # Encrypt the newly entered password with "salt".
$list{$name} = $cpw;    # Load new crypt pw into passwordfile array
&WriteNewFile;          # Write the amended array as the passwordfile

####################################################################
####                                                            ####
####            Start of subs                                   ####
####                                                            ####
####################################################################

sub GetArgs {
		shift(@ARGV) if $ARGV[0] eq '-c';
        $file=shift(@ARGV);
        $name=shift(@ARGV);
        if ( (!$file) | (!$name) ) { 
                die "Usage: $0 htpasswdfile username\n"; 
        }
}
sub MakeNewPassword {
        srand($$ ^ time);                                       # random seed
        @saltchars=('a'..'z','A'..'Z',0..9,'.','/');            # valid salt chars
        $salt=$saltchars[int(rand($#saltchars+1))];     # first random salt char
        $salt.=$saltchars[int(rand($#saltchars+1))];    # second random salt char
        $cpw = crypt($pass,$salt);
}
sub LoadPwFile {
        open(HP, "$file") || open(HP, ">$file");
        while (<HP>) {
                chop;
                ($tname,$tpw) = split(':',$_);
                $list{$tname} = $tpw;
        }
}
sub Prompt {
        local($text);
        if ($list{$name}) {
                $text = "Changing password for $name\nEnter new password: ";  
        }
        else {
                $text = "Enter password for $name: "; 
        }
        return($text);
}
sub WriteNewFile {
        open(HTPASSWD, ">$file");
                foreach $key (sort keys(%list)) {
                        print HTPASSWD "$key:$list{$key}\n";  # print it
                }
        close(HTPASSWD);
}
