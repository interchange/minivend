package Vend::Parser;

# $Id: Parser.pm,v 1.19 1999/08/13 18:26:16 mike Exp $

=head1 NAME

Vend::Parser - MiniVend parser class

=head1 SYNOPSIS

 require Vend::Parser;
 $p = Vend::Parser->new;  # should really a be subclass
 $p->parse($chunk1);
 $p->parse($chunk2);
 #...
 $p->eof;                 # signal end of document

 # Parse directly from file
 $p->parse_file("foo.html");
 # or
 open(F, "foo.html") || die;
 $p->parse_file(\*F);

=head1 DESCRIPTION

The C<Vend::Parser> will tokenize a MiniVend page when the $p->parse()
method is called.  The document to parse can be supplied in arbitrary
chunks.  Call $p->eof() the end of the document to flush any remaining
text.  The return value from parse() is a reference to the parser
object.

The $p->parse_file() method can be called to parse text from a file.
The argument can be a filename or an already opened file handle. The
return value from parse_file() is a reference to the parser object.

In order to make the parser do anything interesting, you must make a
subclass where you override one or more of the following methods as
appropriate:

=over 4

=item $self->start($tag, $attr, $attrseq, $origtext)

This method is called when a complete start tag has been recognized.
The first argument is the tag name (in lower case) and the second
argument is a reference to a hash that contain all attributes found
within the start tag.  The attribute keys are converted to lower case.
Entities found in the attribute values are already expanded.  The
third argument is a reference to an array with the lower case
attribute keys in the original order.  The fourth argument is the
original MiniVend page.

=item $self->end($tag)

This method is called when an end tag has been recognized.  The
argument is the lower case tag name.

=item $self->text($text)

This method is called when plain text in the document is recognized.
The text is passed on unmodified and might contain multiple lines.
Note that for efficiency reasons entities in the text are B<not>
expanded. 

=item $self->comment($comment)

This method is called as comments are recognized.  The leading and
trailing "--" sequences have been stripped off the comment text.

=back

The default implementation of these methods does nothing, I<i.e.,> the
tokens are just ignored.

=head1 BUGS

You can instruct the parser to parse comments the way Netscape does it
by calling the netscape_buggy_comment() method with a TRUE argument.
This means that comments will always be terminated by the first
occurence of "-->".

=head1 SEE ALSO

L<HTML::TreeBuilder>, L<HTML::HeadParser>, L<HTML::Entities>

=head1 COPYRIGHT

Copyright 1996 Gisle Aas. All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

Modified for use by MiniVend.

Copyright 1997-1998 Mike Heins.  

=head1 AUTHOR

Gisle Aas <aas@sn.no>
Modified by Mike Heins <mikeh@iac.net>  

=cut


use strict;

use HTML::Entities ();
use vars qw($VERSION);
$VERSION = sprintf("%d.%02d", q$Revision: 1.19 $ =~ /(\d+)\.(\d+)/);


sub new
{
	my $class = shift;
	my $self = bless { '_buf'              => '' }, $class;
	$self;
}

# How does Netscape do it: It parse <xmp> in the depreceated 'literal'
# mode, i.e. no tags are recognized until a </xmp> is found.
# 
# <listing> is parsed like <pre>, i.e. tags are recognized.  <listing>
# are presentend in smaller font than <pre>
#
# Netscape does not parse this comment correctly (it terminates the comment
# too early):
#
#    <! -- comment -- --> more comment -->
#
# Netscape does not allow space after the initial "<" in the start tag.
# Like this "<a href='gisle'>"
#
# Netscape ignore '<!--' and '-->' within the <SCRIPT> tag.  This is used
# as a trick to make non-script-aware browsers ignore the scripts.


sub eof
{
	shift->parse(undef);
}


sub parse
{
	my $self = shift;
	my $buf = \ $self->{'_buf'};
	unless (defined $_[0]) {
		# signals EOF (assume rest is plain text)
		$self->text($$buf) if length $$buf;
		$$buf = '';
		return $self;
	}
	$$buf .= $_[0];

	# Parse html text in $$buf.  The strategy is to remove complete
	# tokens from the beginning of $$buf until we can't deside whether
	# it is a token or not, or the $$buf is empty.
	while (1) {  # the loop will end by returning when text is parsed
		# First we try to pull off any plain text (anything before a "<" char)
		if ($$buf =~ s|^([^\[<]+)||) {
			$self->text($1);
			return $self unless length $$buf;
		# Netscapes buggy comments are easy to handle
		} elsif ($self->{'_netscape_comment'} && $$buf =~ m|^(<!--)|) {
			if ($$buf =~ s|^<!--(.*?)-->||s) {
				$self->comment($1);
			} else {
				return $self;  # must wait until we see the end of it
			}
		# Then, markup declarations (usually either <!DOCTYPE...> or a comment)
		} elsif ($$buf =~ s|^\[/||) {
			# end tag
			if ($$buf =~ s|^\s*([a-z][-a-z0-9._]*)\s*\]||i) {
				$self->end(lc($1));
			} elsif ($$buf =~ m|^\s*[a-z]*[-a-z0-9._]*\s*$|i) {
				$$buf = "\[/" . $$buf;  # need more data to be sure
				return $self;
			} else {
				# it is plain text after all
				$self->text($$buf);
				$$buf = "";
			}
		# Find the most common tags
		} elsif ($$buf =~ s|^(\[([-a-z0-9A-Z_]+)[^"'=\]>]*\])||) {
#::logDebug("tag='$tag' eat='$eat'\n");
				undef $self->{HTML};
				$self->start($2, {}, [], $1);
		# Then, finally we look for a start tag
		} elsif ($$buf =~ s|^([<\[])||) {
			# start tag
			my $eaten = $1;
			my $end_brack;
			if($eaten eq '[') {
				$self->{HTML} = 0;
				$end_brack = '[^\]]'
			}
			else {
				$self->{HTML} = 1;
				$end_brack = '[^>]'
			}


			# This first thing we must find is a tag name.  RFC1866 says:
			#   A name consists of a letter followed by letters,
			#   digits, periods, or hyphens. The length of a name is
			#   limited to 72 characters by the `NAMELEN' parameter in
			#   the SGML declaration for HTML, 9.5, "SGML Declaration
			#   for HTML".  In a start-tag, the element name must
			#   immediately follow the tag open delimiter `<'.
			if ($$buf =~ s|^(([a-zA-Z][-a-zA-Z0-9._]*)((?:\s+$end_brack+)?\s+[Mm][Vv]\s*=)?\s*)||) {
				$eaten .= $1;

				my ($tag, $end_tag);
				my %attr;
				my @attrseq;
				my $old;

				if(! $3) {
					$tag = lc $2;
					($self->text($eaten), next)
						if $self->{HTML};
				}
				else {
					$end_tag = $2;
					( $$buf =~ s|^((['"])(.*?)\2\s*)||s and $tag = $3 )
					or
					( $$buf =~ s|^(([a-zA-Z][-a-zA-Z0-9._]*)\s*)|| and $tag = $2)
					or ($self->text($eaten), next);
					$eaten .= $1;
					if( index($tag, " ") != -1 ) {
						($tag, $attr{OLD}) = split /\s+/, $tag, 2;
						$old = 1;
					}
					$tag = lc $tag;
				}
				my $nopush;
				my $urldecode = ($tag =~ s/^urld?(?:ecode)?$/urldecode/) ? 1 : 0;

				# Then we would like to find some attributes
				#
				# Arrgh!! Since stupid Netscape violates RCF1866 by
				# using "_" in attribute names (like "ADD_DATE") of
				# their bookmarks.html, we allow this too.
				while (	$$buf =~ s|^(([a-zA-Z][-a-zA-Z0-9._]*)\s*)|| or
					 	! $self->{HTML} && $$buf =~ s|^(([=!<>][=~]?)\s+)||) {
					$eaten .= $1;
					my $attr = lc $2;
					$attr =~ s/^[Mm][Vv]\.?// || undef $attr
						if $self->{HTML} and ! $urldecode;
						
					my $val;
					
					# The attribute might take an optional value (first we
					# check for an unquoted value)
					if ($$buf =~ s~(^=\s*([^\!\|\@\"\'\`\]\s][^\]>\s]*)\s*)~~) {
						$eaten .= $1;
						next unless defined $attr;
						$val = $2;
						HTML::Entities::decode($val);
					# or quoted by " or ' or # or $ or |
					} elsif ($$buf =~ s~(^=\s*(["\'\`])(.*?)\2\s*)~~s) {
						$eaten .= $1;
						next unless defined $attr;
						$val = $3;
						HTML::Entities::decode($val);
					# or quoted by `` to send to [calc]
					} elsif ($$buf =~ s~(^=\s*([\`\!\@\|])(.*?)\2\s*)~~s) {
						$eaten .= $1;
						if    ($2 eq '`') { $val = "[calc]${3}[/calc]" }
						elsif ($2 eq '|') {
								$val = $3;
								$val =~ s/^\s+//;
								$val =~ s/\s+$//;
						}
						elsif ($2 eq '~') { $val = $::Scratch->{$3}   }
						elsif ($2 eq '!') {
							$val = $3;
							my($var, $op) = split /:+/, $val, 2;
							Vend::Interpolate::input_filter($var, { op => $op });
							$val = $var;
						}
					# truncated just after the '=' or inside the attribute
					} elsif ($$buf =~ m|^(=\s*)$|s or
							 $$buf =~ m|^(=\s*[\"\'].*)|s) {
						$$buf = "$eaten$1";
						return $self;
					} elsif (!$old) {
						# assume attribute with implicit value, but
						# if not,no value is set and the
						# eaten value is grown
						undef $nopush;
						($attr,$val,$nopush) = $self->implicit($tag,$attr);
						$old = 1 unless $val || $self->{HTML};

					} else {
# DEBUG
#Vend::Util::logDebug
#("Abort attribute parsing, attr='$attr'.\n")
#	if ::debug(0x2);
# END DEBUG
						$old = 1;
					}
					next if $old and !$self->{HTML};
					if(! $attr) {
						$attr->{OLD} = $val if defined $attr;
						next;
					}
					$attr{$attr} = $val;
					push(@attrseq, $attr) unless $nopush;
				}

				# At the end there should be a closing "\] or >"
				if ($$buf =~ s|^\]|| ) {
					$self->text("$eaten]"), next
						if $self->{HTML};
					$self->start($tag, \%attr, \@attrseq, "$eaten]");
				} elsif ($$buf =~ s|^>|| ) {
					$self->text("$eaten>"), next
						unless $self->{HTML};
					$self->start($tag, \%attr, \@attrseq, "$eaten>", $end_tag);
				} elsif ($$buf =~ s|^([^\]\n]+\])||) {
					$eaten .= $1;
					$self->start($tag, {}, [], $eaten, $end_tag);
				} elsif (length $$buf) {
					# Not a conforming start tag, regard it as normal text
					$self->text($eaten);
				} else {
					$$buf = $eaten;  # need more data to know
					return $self;
				}

			} elsif (length $$buf) {
				$self->text($eaten);
			} else {
				$$buf = $eaten . $$buf;  # need more data to parse
				return $self;
			}

		} elsif (length $$buf) {
			die; # This should never happen
		} else {
			# The buffer is empty now
			return $self;
		}
		return $self if $self->{SEND};
	}
	$self;
}


sub comment
{
	# my($self, $comment) = @_;
}

1;
__END__
