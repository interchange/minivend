UserTag display Order table column key
UserTag display addAttr 1
UserTag display Interpolate 1
UserTag display posNumber 3
UserTag display Routine <<EOR
sub {
	my ($table,$column,$key,$opt) = @_;
	
	my $text;
	my $size;
	my $widget;
	my $label;
	my $help;
	my $help_url;

	my $template = $opt->{type} eq 'hidden' ? '' : $opt->{template};
	if($template and $template !~ /\s/) {
		$template = <<'EOF';
<TR>
<TD>
	<B>$LABEL$</B>
</TD>
<TD VALIGN=TOP>
	<TABLE CELLSPACING=0 CELLMARGIN=0><TR><TD>$WIDGET$</TD><TD><I>$HELP$</I>{HELPURL}<BR><A HREF="$HELP_URL$">help</A>{/HELPURL}</TD></TR></TABLE>
</TD>
</TR>
EOF
		$opt->{template} = 1;
	}

#::logDebug("meta call: table=$table col=$column key=$key text=$text");
	$text = tag_data($table, $column, $key) if $table and $column and $key;
	if($opt->{override}) {
		$text = $opt->{default};
	}
	elsif (not defined $text) {
		$text = length($opt->{default}) ? $opt->{default} : $CGI::values{$column};
	}
#::logDebug("data call failed: $@") if $@;

	if(! $CGI::values{ui_no_meta_display}) {
#::logDebug("meta call: table=$table col=$column key='$key' text=$text");
		($widget, $label, $help, $help_url) = UI::Primitive::meta_display($table,$column,$key,$text,undef,undef,$opt);
#::logDebug("past meta_display, help=$help url=$help_url label=$label");
		$widget =~ s/<(input|select)\s+/<$1 $opt->{js} /i
			if $opt->{js};
	}

	if(! $widget and $opt->{type} ne 'value') {
		my $iname = $opt->{name} || $column;
		my $DECODE_CHARS = qq{[<"\000-\037\177-\377};

		# Count lines for textarea
		my $count;
		$count = $text =~ s/(\r\n|\r|\n)/$1/g;

		HTML::Entities::encode($text, '&');
		HTML::Entities::encode($text, $DECODE_CHARS);
		if ($count) {
			$count++;
			$count = 20 if $count > 20;
			$widget = <<EOF;
	<TEXTAREA NAME="$iname" COLS=60 ROWS=$count>$text</TEXTAREA>
EOF
		}
		elsif ($text =~ /^\d+$/) {
			$size = 8;
		}
		else {
			$size = 60;
		}
			$widget = <<EOF;
	<INPUT NAME="$iname" SIZE=$size VALUE="$text">
EOF
	}
	return $widget unless $template;
	$label = $column if ! $label;
	my %sub = (
		WIDGET		=> $widget,
		HELP		=> $Tag->loc('',$help),
		HELP_URL	=> $help_url,
		LABEL		=> $Tag->loc('',$label),
	);
	# Strip the {TAG} {/TAG} pairs if nothing there
	$template =~ s#{([A-Z_]+)}(.*?){/\1}#$sub{$1} ? $2: '' #ges;
	# Insert the TAG
	$template =~ s/\$([A-Z_]+)\$/$sub{$1}/g;
	return $template;
}
EOR

