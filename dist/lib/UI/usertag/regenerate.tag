UserTag regenerate Order initial
UserTag regenerate PosNumber 1
UserTag regenerate Routine <<EOR
my @regen_messages;
my %regen_reject = qw/ ui 1 minimate 1 process 1 search 1 order 1 obtain 1 /;
my %force_build;
my %never_build;
my $regen_scan;
my $regen_out;
my $regen_arg;
my $initial;
sub regen_build {
	my $ref = shift;
	my $page;
	undef $regen_scan;
	undef $regen_arg;
	undef $regen_out;
	if($ref->[1]) {
		$initial = $ref->[1][0];
		$regen_arg = $ref->[1][1];
		$regen_out = $ref->[0];
	}
	else {
		$initial = $ref->[0];
		$regen_out = $ref->[0];
	}
	
	my ($action, $path) = split m:/:, $initial, 2;
	return undef if $regen_reject{$action};
	
	$Vend::Session = {
		'ohost'		=> 'REGENERA',
		'browser'	=> "Interchange $::VERSION regenerator",
		'scratch'	=> { %{$Vend::Cfg->{ScratchDefault}},
							mv_no_session_id => 1,
							mv_no_count => 1,
							},
		'values'	=> { %{$Vend::Cfg->{ValuesDefault}} },
		'carts'		=> {main => []},
	};
	my ($key, $value);
	while (($key, $value) = each (%{$Vend::Cfg->{StaticSessionDefault}})) {
        $Vend::Session->{$key} = $value;
	}
	$CGI::values = ();
	($Vend::Session->{arg} = $Vend::Argument = $CGI::values{mv_arg} = $regen_arg)
		if $regen_arg;

	if($action eq 'scan') {
		$regen_scan = 1;
		my $c = {};
		::find_search_params($c, $path);
		$c->{mv_more_id} = 'static';
		$Vend::SearchObject{''} = perform_search($c);
		$initial = $Vend::SearchObject{''}->{mv_search_page}
										|| find_special_page('search');
	}

	my $actual;

	$page = readin($initial);
	if(! defined $page) {
		$page = Vend::Interpolate::fly_page($initial);
		$actual = $Global::Variable->{MV_PAGE};
	}

	$actual = $initial unless $actual;

#::logDebug("checking for force of: $actual");
	if (defined $never_build{$actual}) {
		undef $Vend::ForceBuild;
		undef $Vend::CachePage;
	}
	elsif (defined $force_build{$actual}) {
		$Vend::ForceBuild = 1;
	}

	return unless defined $page;

	my $pageref;
	eval {
		($pageref) = ::cache_html($page, 1);
	};
#::logDebug(<<EOF);
#finished regen_build:
#	out=$regen_out
#	arg=$regen_arg
#	scan=$regen_scan 
#	page=$pageref
#	force=$Vend::ForceBuild
#	cache=$Vend::Cache
#EOF
	if($@) {
		push @regen_messages, "$ref->[0]: $@";
		undef $Vend::CachePage;
		undef $Vend::ForceBuild;
	}
	return $pageref;
}

sub {
	$initial = shift || $CGI::values{ui_initial_page} || $Vend::Cfg->{SpecialPage}{catalog};
	my $verbose = $CGI::values{ui_build_verbose} || '';
	my $max_links = $CGI::values{ui_build_max} || '500';
	my $links_done = 0;
	if($CGI::values{ui_force_build}) {
		my @tmp = split /\0/, $CGI::values{ui_force_build};
#::logDebug("force build of: @tmp");
		@force_build{@tmp} = (@tmp);
	}
	if($CGI::values{ui_never_build}) {
		my @tmp = split /\0/, $CGI::values{ui_never_build};
#::logDebug("never build of: @tmp");
		@force_build{@tmp} = (@tmp);
	}
	my $save_session = $Vend::Session;
	my $save_status  = $Vend::StatusLine;
	my %save_cgi     = %CGI::values;
	my %done;
	my $start = (times)[0];
	require File::Path;

	$regen_reject{$Vend::Cfg->{UI_BASE}} = 1;
	for (keys %{$Vend::Cfg->{ActionMap}}) {
		$regen_reject{$_} = 1;
	}

	my $spacer = $::Scratch->{spacer} || '&nbsp;&nbsp;&nbsp;&nbsp;';
	my $output = <<EOF;
$Global::Variable->{UI_STD_HEAD}
Entry page $initial.

<br><p></p>
                                        </td>
                                </tr>
                        </table>
                </td>
        </tr>
</table>
</center>
EOF
	::response(::interpolate_html ($output));
	::response(" " x 1024);
	::response("<PRE>        Checking for links.....\n");

	my $suffix = $Vend::Cfg->{StaticSuffix} || '.html';
	$output = '';
	$Vend::Cookie = 'REGENERA';
	$Vend::AccumulatingLinks = 1;
	untie %Vend::StaticDBM;
	$Vend::Cfg->{Static} = 1;
	my @links = ( [ $initial, '' ] );;
	for my $force (keys %force_build) {
		push (@links, [ $force, '' ]);
	}
	my %found;
	%Vend::Links = ();
	%Vend::LinkFound = ();
#::logDebug( "default search=$::Variable->{MV_DEFAULT_SEARCH_FILE}");
	my ($page);
	while(@links) {
		if($links_done++ > $max_links) {
			::response("Reached maximum link count of $max_links, stopping.\n");
			last;
		}
		$output .= '.';
		my $ref = shift @links;
		next if exists $done{$ref->[0]};
		@Vend::Links = ();
		%Vend::LinkFound = (%found);
		undef $Vend::Argument;

		undef $Vend::CachePage;
		undef $Vend::ForceBuild;
		$verbose and ::response(qq{            Checking page $ref->[0]....});
		regen_build($ref);

		if($Vend::CachePage || $Vend::ForceBuild) {
			$verbose and ::response(qq{will build.\n});
			push (@links, @Vend::Links);
#::logDebug("links: @Vend::Links");
			for (keys %Vend::LinkFound) {
				::response("                Found link $_.\n")
					if $verbose and ! $found{$_};
#::logDebug("link: found $_");
				$found{$_} = 1;
			}
			#if($regen_scan) {
			#	$$pageref =~ s!($Vend::Cfg->{VendURL})/scan/MM=[^"]+!$1/$ref->[0]!g;
			#}
			if($regen_scan) {
				$regen_out = $ref->[0];
				$regen_out =~ s:^scan/::;
				$regen_out = Vend::Util::generate_key($regen_out);
				$regen_out = "scan/$regen_out$suffix";
			}
			elsif ($regen_arg) {
				$regen_arg =~ s:([^-\w/]):sprintf '%%%02x', ord($1):eg;
				$regen_out = "$initial/$regen_arg$suffix";
			}
			else {
				$regen_out = "$regen_out$suffix";
			}
			$Vend::StaticDBM{$ref->[0]} = $regen_out;
			$done{$ref->[0]} = $ref;
		}
		else {
			$verbose and ::response(qq{no.\n});
			$done{$ref->[0]} = 0;
		}
	}
	::response( "        done with link checks, $links_done checked.\n" );

	for(keys %done) {
		$output .= "$_ = $done{$_}<br>\n";
	}

	undef $Vend::AccumulatingLinks;

	::response("\n\n        Generating....\n");
	# we need to restore some settings from the original configuration
	# for static page building first
	my @confsafe = ('ImageDir', 'ImageDirSecure', 'VendURL');
	my %safehash;
	for (@confsafe) {$safehash{$_} = $Vend::Cfg->{$_}}
	$Vend::Cfg->{ImageDir} = $Vend::Cfg->{ImageDirOriginal}; 
	$Vend::Cfg->{ImageDirSecure} = $Vend::Cfg->{ImageDirSecureOriginal}; 
	$Vend::Cfg->{VendURL} = $Vend::Cfg->{VendURLOriginal}; 

	my $umask = umask(022);
	my $statpath = 'http://' . $::Variable->{SERVER_NAME} . $Vend::Cfg->{StaticPath};
	my @bad;
	my $base = $Vend::Cfg->{StaticDir};
	eval {
		File::Path::rmtree($base);
		File::Path::mkpath($base);
		my ($dir, $file);
		for(keys %Vend::StaticDBM) {
			my $ref = delete $done{$_};
			next unless $ref;
			$dir = $file = "$base/$Vend::StaticDBM{$_}";
			$dir =~ s:/[^/]+$::;
			if(! -d $dir) {
				die "Wild directory $dir" if -e $dir;
				File::Path::mkpath($dir);
			}
			open(REGENFILE, ">$file")
				or die "create $file: $!\n";
			my $pageref = regen_build($ref);
			if(! $pageref) {
				push (@regen_messages, "problem building $_.");
				push @bad, $_;
				close REGENFILE;
				unlink $file;
				next;
			}
			print REGENFILE $$pageref;
			close REGENFILE;
			my $dispfile = $file;
			$dispfile =~ s:^$base/::o;
			$dispfile = qq{<A HREF="$statpath/$dispfile"><U>$dispfile</U></A>};
			::response("            Generated $dispfile.\n")
				if $verbose;
		}
	};
	# get back to the UI configuration settings
	for (@confsafe) {$Vend::Cfg->{$_} = $safehash{$_}}

	my $success;
	if($@) {
		push (@regen_messages, "during file write: $@\n");
		::response("\n        Failed to write all files.\n</PRE>");
	}
	else {
		::response("\n        Finished writing files.\n</PRE>");
		$success = 1;
	}
	umask($umask);

	if($success) {
		my %my_static;
		%my_static = %Vend::StaticDBM;
		$Vend::Cfg->{StaticDBM} = $Vend::Cfg->{SaveStaticDBM}
			if ! $Vend::Cfg->{StaticDBM};
		if(::tie_static_dbm(1)) {
			my @del = keys %Vend::StaticDBM;
			for(@del) {
				delete $Vend::StaticDBM{$_};
			}
			my ($k, $v);
			while( ($k, $v) = each %my_static) {
				$Vend::StaticDBM{$k} = $v;
			}
		}
	}

	$Vend::Session = $save_session;
	$Vend::StatusLine = $save_status;
	%CGI::values = %save_cgi;
	if(@regen_messages) {
		my $out = "Messages during regen:<blockquote>";
		$out .= join "<br>", @regen_messages;
		$out .= "</blockquote>";
		::response($out);
	}
	my $end = (times)[0] - $start;
	$end = int($end);
	::response(::interpolate_html(<<EOF, 1));
<table cellpadding=2 cellspacing=0 width=__UI_OVERALL_WIDTH__ bgcolor=__UI_C_TITLEBARBG__ border=0>
<tr>
<td>
    <table cellpadding=0 cellspacing=0 width=100% bgcolor=__UI_T_BG__ border=0>
    <tr>
    <td colspan=2 align="center">
       <table width=90% cellpadding=0 cellspacing=0 border=0>
       <tr>
       <td>
          <br><br>
        <img src="icon_regen.gif"
            width=16 height=16 border=0 valign=top> &nbsp;
       <font size="+1" face="Verdana,arial,helvetica,sans-serif" color="#000000">Regeneration complete in $end seconds.&nbsp;<br></font></td></tr>
        </table>
        </td>
    </tr>
    <tr>
    <td colspan="2">
    <style type="text/css">
    <!--
     td{font-family:arial, helvetica, sans-serif}
       -->
   </style>
   <center>
$Global::Variable->{UI_STD_FOOTER};
EOF
	return;
}
EOR
