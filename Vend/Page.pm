# Page.pm:  compiles and processes pages and placeholders
#
# $Id: Page.pm,v 1.12 1995/12/15 20:03:43 amw Exp $
#
package Vend::Page;

# Copyright 1995 by Andrew M. Wilcox <awilcox@world.std.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(page_code test_pages read_phds
             placeholder
             call_template
             define_placeholder
             canonical_ph_name
             compile_page
             load_ph_definition_files
             read_templates
             compile_action);

use strict;
use Carp;
use Vend::Directive qw(Page_directory Html_extension);
use Vend::Uneval;


my $Maximum_variable_name_length = 80;


## Safe filenames

my $Ok_in_filename = 
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:-_.$';
my $Ok_in_varname =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
my $Ok_first_letter =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

my (@Translate_to_filename, @Translate_to_varname);

sub setup {
    my ($i, $h);

    foreach $i (0..255) {
        $h = sprintf("%02X", $i);
        $Translate_to_filename[$i] = '%' . $h;
        $Translate_to_varname[$i] = '_' . $h;
    }
}
setup();

sub escape_to_filename {
    my ($str) = @_;

    $str =~ s/([^\Q$Ok_in_filename\E])/$Translate_to_filename[ord($1)]/geo;
    # untaint since safe now
    $str =~ m/(.*)/;
    $1;
}

sub unescape_from_filename {
    my ($filename) = @_;

    $filename =~ s/%(..)/chr(hex($1))/ge;
    $filename;
}

sub escape_to_varname {
    my ($str) = @_;

    my $first = substr($str, 0, 1);
    my $rest = substr($str, 1);

    $first =~ s/([^\Q$Ok_first_letter\E])/$Translate_to_varname[ord($1)]/geo;
    $rest =~ s/([^\Q$Ok_in_varname\E])/$Translate_to_varname[ord($1)]/geo;
    return $first . $rest;
}

sub unescape_from_varname {
    my ($varname) = @_;

    $varname =~ s/_(..)/chr(hex($1))/ge;
    $varname;
}


my %Page_subname;
my %Page_changed_date;

# Map a page name to a filename.  Handle .. by dropping the previous
# element of the pathname.  (A .. that would reference something outside
# the page directory is silently ignored.)  Dangerous characters in the
# page name are escaped.

sub name_to_filename {
    my ($name) = @_;

    my ($elem, @nelem);
    foreach $elem (split(/\//, $name)) {
        if ($elem eq '..') {
            pop @nelem;
        }
        elsif ($elem eq '') {}
        else {
            push @nelem, escape_to_filename($elem);
        }
    }

    return undef unless @nelem;
    return Page_directory . "/" . join('/', @nelem) . Html_extension;
}


# Map from a filename back to the page name.

sub filename_to_name {
    my ($name) = @_;

    my $html = Html_extension;
    ($name =~ s/\Q$html\E$//o) or return undef;
    return join('/', map(unescape_from_filename($_), split(/\//, $name)));
}


# Reads in a page from the page directory.  Returns the entire
# contents of the page, or undef if the file could not be read.

sub readin_page {
    my ($name) = @_;
    local($/, $.);

    my $fn = name_to_filename($name);
    my $contents;
    if (open(Vend::Page::IN, $fn)) {
        $Page_changed_date{$name} = (stat(Vend::Page::IN))[9];
	undef $/;
	$contents = <Vend::Page::IN>;
	close(Vend::Page::IN);
    } else {
	$contents = undef;
    }
    ($fn, $contents);
}


# Returns the sub name for the page, or undef if this
# page does not exist.

# my $ii = 0;

sub page_subname {
    my ($name, $no_cache) = @_;
    $no_cache = 0;
    my ($subname, $fn, $content);

    $subname = $Page_subname{$name};
    if (not $no_cache and defined $subname) {
        $fn = name_to_filename($name);
        return undef unless defined $fn;
        return $subname if (stat($fn))[9] == $Page_changed_date{$name};
    }

    ($fn, $content) = readin_page($name);
    return undef unless defined $content;

    $subname = 'Page::' .
        join('::', map(escape_to_varname($_), split(/\//, $name)));
    return undef if length($subname) > $Maximum_variable_name_length;
    $Page_subname{$name} = $subname;
    compile_page($fn, $content, $subname);
    return $subname;
}

sub page_code {
    my ($pagename, $no_cache) = @_;

    my $subname = page_subname($pagename, $no_cache);
    return undef unless defined $subname;

    no strict 'refs';
    return \&{$subname};
}

sub page_changed_date {
    my ($pagename) = @_;
    $Page_changed_date{$pagename};
}

sub file_type {
    my ($original_fn) = @_;
    my $fn = $original_fn;
    my ($m, $link, $i);

    my $i;
    while (-l $fn) {
        die "Too many symbolic links for '$original_fn'\n" if ++$i > 20;
        $link = readlink($fn);
        if (not defined $link) {
            $m = "Could not read symbolic link '$fn'";
            $m .= " (pointed to by '$original_fn')" if $fn ne $original_fn;
            die "$m: $!\n";
        }
        $fn = $link;
    }

    if    (-d _) { return 'd'; }
    elsif (-f _) { return 'f'; }
    else         { return ''; }
}


## For testing, load in all pages.

sub recurse_pages {
    my ($base, $callback, $dir) = @_;
    my ($fn, $name, $t);
    local (*Vend::Page::DIR);

    my $d = (defined $dir ? "$base/$dir" : $base);
    opendir(Vend::Page::DIR, $d) or die "Could not read directory '$d': $!\n";
    while ($fn = readdir(Vend::Page::DIR)) {
        next if $fn =~ m/^\./;
        $t = file_type("$d/$fn");
        if ($t eq 'd') {
            recurse_pages($base, $callback, (defined $dir ? "$dir/$fn" : $fn));
        }
        elsif ($t eq 'f') {
            $name = filename_to_name(defined $dir ? "$dir/$fn" : $fn);
            next unless defined $name;
            &$callback("$d/$fn", $name) if defined $name;
            # (defined $dir ? "$base/$dir/$fn" : "$base/$fn")
        }
    }
    closedir(Vend::Page::DIR);
}

sub test_page {
    my ($fn, $name) = @_;

    print "  $name\n";
    page_subname($name)
        or die "Could not load page '$name' from file '$fn'\n";
}

sub test_pages {
    print "Testing pages:\n";
    recurse_pages(Page_directory, \&test_page);
}


## Read in placeholder definition files.

sub read_phds {
    my (@dirs) = @_;
    my ($dir, $file);

    my $files = [];

    foreach $dir (@dirs) {
        opendir(Vend::Page::DIR, $dir)
            or die "Could not read directory '$dir': $!\n";
        while ($file = readdir(Vend::Page::DIR)) {
            next if $file eq '.' or $file eq '..';
            next unless $file =~ m!\.phd$!;
            push @$files, "$dir/$file";
        }
        closedir(Vend::Page::DIR);
    }

    load_ph_definition_files($files);
}

##

sub read_templates {
    my (@dirs) = @_;
    my ($dir, $file);

    foreach $dir (@dirs) {
        opendir(DIR, $dir) or die "Couldn't read directory '$dir': $!\n";
        while ($file = readdir(DIR)) {
            next if $file eq '.' or $file eq '..';
            next unless $file =~ m!\.tpl$!;
            parse_template_file("$dir/$file");
        }
        closedir(DIR);
    }
}


##

my %Placeholder_list = ();


sub placeholder {
    my ($placeholder_name, @args) = @_;
    my $name = canonical_ph_name($placeholder_name);
    croak "There is no placeholder named '$placeholder_name' defined"
        unless defined $Placeholder_list{$name};
    no strict 'refs';
    my $code = \& {$Placeholder_list{$name}->{subname}};
    return &$code(@args);
}


## compile_page()

sub compile_page {
    my ($source_file, $page_text, $subname) = @_;

    return compile_text(\$page_text, undef, undef, $source_file, 0, $subname);
}


## Defining placeholders

# template '[bold $a] text [/bold]'
# arguments '$a $b'
# container  0 | 1
# name  canonical_name
# text_variable  'text'

# Called by modules to define Perl code placeholders

sub define_placeholder {
    my ($template, $code) = @_;
    croak "Code '$code' is not a code ref" unless ref($code) eq 'CODE';

    my $ph = {};
    my $error = parse_template($ph, $template);
    croak $error if $error;
    {
        no strict 'refs';
        * {$ph->{subname}} = $code;
    }
}


# called by modules to define a compile time action for a placeholder
# XXX needs a better name

sub compile_action {
    my ($name, $code) = @_;
    my $ph = $Placeholder_list{canonical_ph_name($name)};
    croak "Placeholder '$name' has not yet been defined"
        unless defined $ph;
    croak "Code '$code' is not a code ref" unless ref($code) eq 'CODE';

    $ph->{'compile_action'} = $code;
}

# # called by define_placeholder to install the placeholder code in
# # the application package as a sub
# 
# sub install_placeholder {
#     my ($ph, $code) = @_;
# 
#     my $subname = "Placeholder::" . escape_to_varname($ph->{name});
#     $ph->{subname} = $subname;
#     {
#         no strict 'refs';
#         * {$subname} = $code;
#     }
# }

sub load_ph_definition_files {
    my ($files) = @_;
    die "files argument is not an array ref" unless ref($files) eq 'ARRAY';
    my ($file, $ph);
    my $new_ph = [];

    # load all placeholder source text before parsing
    foreach $file (@$files) {
        parse_definition_file($file, $new_ph);
    }

    # parse placeholder source
    foreach $ph (@$new_ph) {
        define_text_placeholder($ph);
        undef $ph->{text};
    }
}

# loads placeholder source text from file $fn, and stores placeholder
# names in $new_ph

sub parse_definition_file {
    my ($fn, $new_ph) = @_;
    local ($_, $.);
    my ($line, $indentation, $text, $indent, $offset, $redo_line);

    open(Placeholder::IN, $fn) or croak "Could not open '$fn': $!\n";
    LINE: while(<Placeholder::IN>) {
        chomp;
        $line = $_;
        s/#.*//;
        s/\s+$//;
        next if $_ eq '';
        if (m/^\s/) {
            if (m/^\s+placeholder/i) {
                def_syntax_error("Do not indent placeholder", $fn, $., $_);
            }
            else {
                def_syntax_error("Use 'placeholder' to introduce a placeholder definition", $fn, $., $_);
            }
        }
        if (! s/^placeholder//i) {
            def_syntax_error("Use 'placeholder' to introduce a placeholder definition", $fn, $., $_);
        }
        s/^\s+//;

        my $ph = {};  # new Placeholder;
        my $error = parse_template($ph, $_);
        def_syntax_error($error, $fn, $., $line) if $error;
        push @$new_ph, $ph;

        $indentation = undef;
        $text = undef;
        $offset = undef;
        $redo_line = 0;
        while (<Placeholder::IN>) {
            $redo_line = 1, last if (! m/^\s/);
            chomp;
            s/\s+$//;
            next if $_ eq '';
            $offset = $. - 1 unless defined $offset;
            m/^(\s+)/;
            $indent = length($1);
            $indentation = $indent
                if (not defined $indentation or $indent < $indentation);
            substr($_, 0, $indentation) = '';
            $text .= "\n" if defined $text;
            $text .= $_;
        }
        $ph->{text} = $text;
        $ph->{source_file} = $fn;
        $ph->{source_offset} = $offset;
        redo LINE if $redo_line;
        last LINE;
    }
}

sub def_syntax_error {
    my ($msg, $file, $linenum, $line) = @_;

    die "$msg at line $linenum of $file:\n$line\n";
}


# parse and compile placeholder source

sub define_text_placeholder {
    my ($ph) = @_;
    my ($args, $code, $textvar);

    $args = $ph->{arguments};
    $textvar = $ph->{container} ? $ph->{text_variable} : undef;
    my $x = $ph->{name};
    compile_text(\$ph->{text},
                 $args,
                 $textvar,
                 $ph->{source_file},
                 $ph->{source_offset},
                 $ph->{subname});
}


##

my $Templates = {};

sub parse_template_file {
    my ($fn) = @_;
    local ($_, $.);

    open(IN, $fn) or croak "Couldn't open '$fn': $!\n";
    while (<IN>) {
        chomp;
        s/#.*//;
        next if m/^\s*$/;
        last;
    }
    m/^\s*template\s*/ or croak "'$fn' should start with a template statement\n";
    my ($name, $vars) = m/^\s*template\s+(\w+)(.*)/
        or croak "Syntax error on line $. of '$fn':\n$_\n";
    $vars =~ s/^\s+//;
    my @vars = split(/\s+/, $vars);
    my $var;
    foreach $var (@vars) {
        croak "Syntax error in template variable name:\n$_\n"
            unless $var =~ m/^\$\w+$/;
        $var =~ s/^\$//;
    }

    my $source;
    do {
        $source = <IN>;
    } while ($source =~ m/^\s*$/);

    while (<IN>) {
        $source .= $_;
    }

    my $subname = "Template::" . escape_to_varname($name);
    compile_text(\$source, [@vars], undef, $fn, 0, $subname);
    no strict 'refs';
    $Templates->{$name} = \&$subname;
}

sub call_template {
    my ($template_name, @args) = @_;
    my $sub = $Templates->{$template_name};
    croak "There is no template named '$template_name'" unless defined $sub;
    return &$sub(@args);
}

##

sub canonical_ph_name {
    my ($name) = @_;
    $name = lc($name);
    $name =~ s,-,_,g;
    $name;
}

$Placeholder::name_regex = '[\w\_\-\:]+';
# _ - : / % + .
$Placeholder::arg_regex = '[\w\_\-\:\/\%\+\.]+';


# fills in {name}, {arguments}, {container}, {text_variable}

sub parse_template {
    my ($ph, $template) = @_;
    my ($content, $rest, @fields, $name, $f, $next, $text, $container);

    $template =~ m/^ \[ /x
        or return "Template '$template' should start with a '['";
    ($content, $rest) = ($template =~ m/^\[ ([^\]]*) \] (.*)/x)
        or return "Template '$template' has no matching ']'";
    @fields = split(/\s+/, $content);
    shift @fields if $fields[0] eq '';

    $name = shift @fields;
    $name ne '' or return "Template name needs to be given in '$template'";
    $name =~ m/^ $Placeholder::name_regex $/ox
        or return "Syntax error in template name '$name'";
    $ph->{name} = canonical_ph_name($name);

    foreach $f (@fields) {
        $f =~ s/^ \$ //x
            or return "Template variable '$f' should start with a '\$'";
        $f =~ m/^ $Placeholder::arg_regex $/ox
            or return "Syntax error in template variable '$f'";
    }
    $ph->{arguments} = [@fields];

    if ($rest =~ m/^ \s* $/x) {
        $ph->{container} = 0;
    }
    else {
        ($text, $next) = ($rest =~ m/^ \s* ([^\[]+) \[ (.*)/ox)
            or return "Syntax error in template '$template'";
        $text =~ s/^\s+//;
        $text =~ s/\s+$//;
        $text =~ m/^ $Placeholder::arg_regex $/ox
            or return "Syntax error in text variable '$text'";
        $text = canonical_ph_name($text);
        $next =~ m!^ \s* / \Q$name\E \s* \] \s* $!x
            or return "Ending placeholder should be '[/$name]'";
        $ph->{container} = 1;
        $ph->{text_variable} = $text;
    }

    $Placeholder_list{$ph->{name}} = $ph;
    $ph->{template} = $template;
    $ph->{subname} = "Placeholder::" . escape_to_varname($ph->{name});
    return '';
}


## Compile text

sub eval_code {
    eval $Placeholder::Source_code;
}

# called from both compile_page (.html files) and define_text_placeholder
# (.phd files)
#
# $args and $textvar will be undefined for pages

sub gen_perl_source {
    my ($page_text, $args, $textvar, $source_file, $source_offset,
         $subname) = @_;
    die unless ref($page_text) eq 'SCALAR';
    die unless !defined($args) or ref($args) eq 'ARRAY';
    my ($mark, $parsed, @args, $resolved);

    $Placeholder::Source_file = $source_file;
    $Placeholder::Source_offset = $source_offset;

    $mark = 0;
    $parsed = parse_page($page_text, \$mark, defined($args), $textvar);
    $resolved = resolve_containers($parsed);
    # print "resolved: ", uneval($resolved), "\n\n";

    @args = defined $args ? @$args : ();
    push @args, $textvar if defined $textvar;
    
    "package application; use strict; " .
    "sub $subname { " .
        (@args ? "my (" . join(', ', map('$'.$_, @args)) . ") = \@_; "
               : "") .
        gencode($resolved) .
    "}";
}

sub compile_text {
    my ($page_text, $args, $textvar, $source_file, $source_offset, $subname) = @_;

    $Placeholder::Source_code =
        gen_perl_source($page_text, $args, $textvar, $source_file, $source_offset, $subname);

    # open(SRC, ">/tmp/src"), $x::s = 1 unless $x::s;
    # print SRC $Placeholder::Source_code, "\n\n";

    undef &{$subname};
    my $saved_eval_error = $@;
    {
        local $SIG{'__WARN__'} = sub { die $_[0] };
        eval_code();
    }
    undef $Placeholder::Source_code;
    my $eval_error = $@;
    $@ = $saved_eval_error;
    die "Error while compiling $source_file:\n$eval_error" if $eval_error;
    1;
}


## Compile text: syntax_error()

# $Placeholder::Input;

sub syntax_error {
    my ($msg, $pos) = @_;
    $pos = 0 unless defined $pos;
    my $in = \$Placeholder::Input;

    my $before = substr($$in, 0, $pos);
    my $linecnt = ($before =~ tr/\n//) + $Placeholder::Source_offset;
    my $linestart = rindex($before, "\n") + 1;
    my $lineend = index($$in, "\n", $linestart + 1);
    if ($lineend == -1) { $lineend = length($$in); }
    my $line = substr($$in, $linestart, $lineend - $linestart);
    my $posinline = $pos - $linestart;

    die "Syntax error on line ". ($linecnt + 1) .
	" of '$Placeholder::Source_file':\n$msg:\n" .
	"$line\n" . (" " x $posinline) . "^\n";
}


## Compile text: parse_placeholder()

# Attempts to match REGEX in the string ref STR at the position
# of integer ref MARK.  If successful, MARK is updated to point to
# the first character past the matching text.  Ref POS is set to the
# beginning of the matching text.  (Is this ever different than
# the original MARK?)  In array context, returns ( ) subexpressions
# in REGEX.

sub match {
    my ($regex, $str, $mark, $pos) = @_;

    pos($$str) = $$mark;
    ($$str =~ m/ \G ($regex) /gx) or return wantarray ? () : undef;
    $$mark = pos($$str);
    $$pos = $$mark - length($1) if defined $pos;
    wantarray ? ($2, $3, $4) : 1;
}


# Matches a placeholder name and looks it up in the placeholder table.

sub parse_ph_name {
    my ($str, $mark, $textname) = @_;
    my ($namepos, $name, $ph);

    $namepos = $$mark;
    ($name) = match "($Placeholder::name_regex)", $str, $mark
        or syntax_error("Expecting the name of a placeholder", $$mark);

    $name = canonical_ph_name($name);

    if (not defined $textname or $name ne $textname) {
        $ph = $Placeholder_list{$name};
        syntax_error("The placeholder '$name' is not defined", $namepos)
            unless defined $ph;
    }

    ($name, $namepos, $ph);
}

sub parse_string {
    my ($str, $mark) = @_;
    my $start = $$mark - 1;
    my $r = '';
    my $a;

    for (;;) {
        if (match '"', $str, $mark) {             # "
            return $r;
        }
        elsif (match '\\\\\\\\', $str, $mark) {   # \\
            $r .= "\\";
        }
        elsif (match '\\\\"', $str, $mark) {      # \"
            $r .= '"';
        }
                                                  # ([^\\\n"]+)
        elsif (($a) = match '([^\\\\\\n"]+)', $str, $mark) {
            $r .= $a;
        }
        else {
            syntax_error("Unmatched quote", $start);
        }
    }
}

sub parse_placeholder {
    my ($str, $mark, $parsevars, $textname) = @_;
    my ($var, $name, $arg, $pos, @arg, $namepos, $ph, $n, $varname);
    my ($is_textname, $tn);

    match '\[', $str, $mark or syntax_error("No left bracket", $$mark);
    match '\s*', $str, $mark;

    if (match '/', $str, $mark) {
        ($name, $namepos, $ph) = parse_ph_name($str, $mark);
        match '\s*', $str, $mark;
        match '\]', $str, $mark
            or syntax_error("Unexpected character", $$mark);
        return ["end-container", $name];
    }

    ($name, $namepos, $ph) = parse_ph_name($str, $mark, $textname);
    $is_textname = (defined $textname and $name eq $textname);
    @arg = ();
    for (;;) {
        match '\s*', $str, $mark;
        if ($parsevars and
            (($varname) = match "\\\$($Placeholder::arg_regex)", $str, $mark)) {
            # $variable 
            push @arg, ['variable', $varname];
            match '\s*', $str, $mark;
        }
        elsif (match '"', $str, $mark) {
            # "string"
            push @arg, parse_string($str, $mark);
            match '\s*', $str, $mark;
        }
        # elsif (($arg) = match "($Placeholder::arg_regex)", $str, $mark) {
        #     push @arg, $arg;
        #     match '\s*', $str, $mark;
        # }
        elsif (match '\\[', $str, $mark) {
            # [placholder...
            $$mark -= 1;
            push @arg, parse_placeholder($str, $mark, $parsevars, undef);
            match '\s*', $str, $mark;
        }
        else {
            last;
        }
    }

    match '\]', $str, $mark
        or syntax_error("Unexpected character", $$mark);

    if ($is_textname) {
        # XXX check for args
        return ["calltext", $name];
    }

    $n = @{ $ph->{arguments} };
    syntax_error("The placeholder '$name' takes $n argument" .
                 ($n == 1 ? '' : 's'), $namepos)
        unless @arg == $n;

    if ($ph->{container}) {
        return ["container", $name, @arg];
    }
    else {
        return ["call", $name, @arg];
    }
}	


## Compile text: parse_page()

sub substri {
    my ($str, $i, $j) = @_;
    substr($$str, $i, $j - $i + 1);
}

sub push_text {
    my ($out, $text) = @_;

    if ($text ne '') {
        if (@$out > 0 and not ref($out->[$#$out])) {
            $out->[$#$out] .= $text;
        }
        else {
            push @$out, $text;
        }
    }
}

sub find_token {
    my ($input, $mark, $parsevars, $token, $tpos) = @_;
    my ($success, $nextchar);

    pos($$input) = $$mark;
    $success = ($parsevars ? $$input =~ m/ ([\[\]\$\\]) /gx
                           : $$input =~ m/ ([\[\]\\]) /gx);
    return undef unless $success;
    if ($1 eq '[' or $1 eq ']' or $1 eq '$') {  #'{
        $$token = $1;
        $$mark = pos($$input);
        $$tpos = $$mark - 1;
        return 1;
    }
    else {
        $nextchar = substr($$input, pos($$input), 1);
        return undef if $nextchar eq '';
        $$token = '\\' . $nextchar;
        $$mark = pos($$input) + 1;
        $$tpos = pos($$input) - 1;
        return 1;
    }
}

sub find_matching_bracket {
    my ($input, $mark, $right) = @_;

    my $depth = 1;
    my ($success, $bracket, $token, $tpos);
    for (;;) {
        $success = find_token($input, $mark, 0, \$token, \$tpos);
        return undef if not $success;
        next if $token =~ m/^\\/;

        $bracket = $token;
        if ($bracket eq "[") {
            ++$depth;
        }
        else {
            --$depth;
            last if $depth == 0;
        }
    }

    $$right = $tpos;
    1;
}

sub find_var_name {
    my ($input, $mark, $varname, $vpos) = @_;
    my ($success);

    pos($$input) = $$mark;
    $success = ($$input =~ m/ \G (\w+) /gx);
    return 0 unless $success;
    $$varname = $1;
    $$mark = pos($$input);
    $$vpos = $$mark - length($1);
    return 1;
}

# ['concat', arg, arg]
# ['variable', name]
# ['call', placeholder, arg, arg]
# ['container', placeholder, arg, arg]
# ['calltext', placeholder]
# ['end-container', placeholder]

sub parse_page {
    my ($input, $mark, $parsevars, $textvar) = @_;
    die unless ref($input) eq 'SCALAR';
    die unless ref($mark) eq 'SCALAR';
    die unless $parsevars eq '' or $parsevars eq '1';

    my ($start, $bracket, $success, $left, $right, $token, $tpos);
    my ($varname, $vpos);

    $Placeholder::Input = $$input;
    my $out = [];

    for (;;) {
        $start = $$mark;
        $success = find_token($input, $mark, $parsevars, \$token, \$tpos);
        if (not $success) {               # no token
            push_text $out, substr($$input, $$mark);
            last;
        }
        elsif ($token =~ m/^\\(.)$/) {    # \x
            push_text $out, substri($input, $start, $tpos - 1) . $1;
        }
        elsif ($token eq ']') {           # ]
            syntax_error("Unmatched right bracket", $tpos);
        }
        elsif ($token eq '[') {           # [
            push_text $out, substri($input, $start, $tpos - 1);
            $left = $tpos;
            find_matching_bracket($input, $mark, \$right)
                or syntax_error("Left bracket with no matching right bracket",
                                $left);
            push @$out,
                  parse_placeholder($input, \$left, $parsevars, $textvar);
        }
        elsif ($token eq '$') {   # (unconfuse emacs) ' {
            push_text $out, substri($input, $start, $tpos - 1);
            find_var_name($input, $mark, \$varname, \$vpos)
                or syntax_error("A \$ should be followed by a variable name.".
                                "  (If you want a dollar\nsign itself, ".
                                "use \\\$)", $tpos);
            push @$out, ['variable', $varname];
        }
        else {
           die "Can't happen";
        }
    }

    unshift @$out, "concat";
    $out;
}


## Compile text: resolve_containers()

sub resolve_containers {
    my ($parsed) = @_;

    if (!ref($parsed)) { return $parsed; }

    my $type = $parsed->[0];
    if    ($type eq 'concat')        { return resolve_concat($parsed); }
    elsif ($type eq 'variable')      { return $parsed; }
    elsif ($type eq 'call')          { return no_containers_allowed($parsed); }
    elsif ($type eq 'container')     { die "Shouldn't happen"; }
    elsif ($type eq 'calltext')      { return $parsed; }
    elsif ($type eq 'end-container') { die "Shouldn't happen"; }
    else                             { die "Shouldn't happen"; }
}

sub resolve_concat {
    my ($p) = @_;
    my $parsed = [@$p[1 .. $#$p]];

    my @resolved = resolve_recurse($parsed);
    unshift @resolved, 'concat';
    return [@resolved];
}

sub resolve_recurse {
    my ($parsed) = @_;
    my @resolved = ();
    my ($i, $type, $name);

    while (defined($i = shift @$parsed)) {
        if (!ref($i)) {
            push @resolved, $i;
            next;
        }
        $type = $i->[0];
        if    ($type eq 'concat')        { die "Shouldn't happen"; }
        elsif ($type eq 'variable')      { push @resolved, $i; }
        elsif ($type eq 'calltext')      { push @resolved, $i; }
        elsif ($type eq 'call') {
            push @resolved, no_containers_allowed($i);
        }
        elsif ($type eq 'container') {
            push @resolved, encapsulate_contained($parsed, $i);
        }
        elsif ($type eq 'end-container') {
            $name = $i->[1];
            syntax_error("Unmatched ending placeholder '/$name'");
        }
        else {
            die "Unknown type '$type'";
        }
    }
    return @resolved;
}

sub encapsulate_contained {
    my ($parsed, $i) = @_;
    my $name = $i->[1];
    my @args = @$i[2 .. $#$i];
    my @block = lookfor_ending($parsed, $name);

    return ['call',
            $name,
            @args,
            ['block', @block]];
}

sub lookfor_ending {
    my ($parsed, $name) = @_;
    my $i;
    my @block = ();
    my $found = 0;

    while (defined($i = shift @$parsed)) {
        if (ref($i) and $i->[0] eq 'container') {
            push @block, encapsulate_contained($parsed, $i);
        }
        elsif (ref($i) and $i->[0] eq 'end-container') {
            syntax_error("Ending placeholder '/".$i->[1]."' does not match ".
                         "placeholder '$name'")
                if $name ne $i->[1];
            $found = 1;
            last;
        }
        else {
            push @block, $i;
        }
    }
    syntax_error("No matching ending placeholder for '$name'") unless $found;
    return @block;
}


sub no_containers_allowed {
    my ($parsed) = @_;
    return $parsed;
}

sub dumpp {
    my ($k, $v);
    while (($k, $v) = each %Placeholder_list) {
        print "   $k = $v\n";
    }
}

## Compile text: gencode()

sub gencode {
    my ($a) = @_;
    my ($type, $e, $r);

    # print "*** gencode\n";
    # dumpp();

    if (not ref $a) {
        return uneval($a);
    }
    else {
        $type = shift @$a;
        if    ($type eq 'concat')   { concat($a) }
        elsif ($type eq 'call')     { gencall($a) }
        elsif ($type eq 'variable') { genvar($a->[0]) }
        elsif ($type eq 'calltext') { gencalltext($a->[0]) }
        elsif ($type eq 'block')    { genblock($a) }
        else                        { die "Unexpected type '$type'" }
    }
}

sub concat {
    my ($a) = @_;

    if (@$a == 1) {
        return gencode($a->[0]);
    }
    else {
        return "join('', " . join(', ', map(gencode($_), @$a)) . ")";
    }
}

sub genblock {
    my ($a) = @_;

#    return "sub { " . concat($a) . " }";
    return concat($a);
}

sub gencall {
    my ($a) = @_;
    my $ph_name = shift @$a;

    $| = 1;

    my $ph = $Placeholder_list{$ph_name};
    my $compile_action = $ph->{'compile_action'};
    if (defined $compile_action) {
        &$compile_action(@$a);
    }

    return $ph->{subname} . "(" . join(', ', map(gencode($_), @$a)) . ")";
}

sub genvar {
    my ($varname) = @_;

    return '$' . $varname;
}

sub gencalltext {
    my ($varname) = @_;

#    return '&$' . $varname . '()';
    return '$' . $varname;
}

1;
