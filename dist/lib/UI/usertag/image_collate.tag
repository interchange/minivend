UserTag image-collate Order archive
UserTag image-collate addAttr
UserTag image-collate Routine <<EOR
sub {
	my ($archive, $opt) = @_;

#Debug("Image collate called with archive=$archive" . ::uneval(\@_));

	my $thumb = $opt->{thumb};
	require File::Path;
	require File::Copy;

	sub tmp_die {
		my (@args) = @_;
		$args[0] = "image_collate: " . $args[0];
		my $msg = ::errmsg(@args);
		$Vend::Session->{ui_failure} = $msg;
#Debug($msg);
		chdir($Vend::Cfg->{VendRoot});
		return undef;
	}

	my $Exec;
	if($archive =~ /\.zip$/i) {
		$Exec = 'unzip -q -j';
	}
	elsif ($archive =~ /gz$/) {
		$Exec = 'tar -x -z -f';
	}
	elsif ($archive =~ /bz2?$/) {
		$Exec = 'tar -x -j -f';
	}
	else {
		my $tmp = $archive;
		$tmp =~ s/.*\.//;
		return tmp_die("unrecognized archive extension: %s", $tmp);
	}

	$archive =~ s:^upload/::;
	$archive = "upload/$archive";
	return undef unless -f $archive;

	my $tmpdir = "$Vend::Cfg->{ScratchDir}/img/$Vend::Session->{id}";
	File::Path::rmtree($tmpdir) if -d $tmpdir;
	File::Path::mkpath($tmpdir)
		or return tmp_die("cannot make directory %s: %s", $tmpdir, $!);
	File::Copy::copy($archive, $tmpdir)
		or return tmp_die("cannot copy archive %s to %s: %s", $archive, $tmpdir, $!);
	chdir $tmpdir
		or return tmp_die("cannot chdir to directory %s: %s", $tmpdir, $!);
	
	my $afile = $archive;
	$afile =~ s:.*/::;
	system("$Exec $afile");
	if($?) {
		my $status = $? >> 8;
		return tmp_die("error %s unarchiving %s: %s", $status, $afile, $!);
	}
	unlink $afile
		or return tmp_die("cannot unlink archive %s: %s", $afile, $!);
	sleep 1;
	
	opendir(IMGDIR, '.')
		or return tmp_die("couldn't open image directory?");
	my @ifiles = grep -f $_, readdir(IMGDIR);
	closedir(IMGDIR)
		or return tmp_die("couldn't close image directory?");
#Debug("image files: " . join ", ", @ifiles);
	my @unfound;
	my @did;
	my @do;

	my $i_f = $opt->{image_field} || 'image';
	my $t_f = $opt->{thumb_field} || 'thumb';
	my $s_f = $opt->{sku_field}   || 'sku';

	my $table = $opt->{table} || 'products';

	$Vend::WriteDatabase{$table} = 1;
	my $db = ::database_exists_ref($table)
		or return tmp_die("products table %s not found.", $table);

	my $fields = "$s_f, $i_f";
	$fields .= ", $t_f" if $thumb;

	for(@ifiles) {
		my (@parts) = split /\./, $_;
		my ($base, $ext);
		if(@parts < 2) {
			$base = $parts[0];
			$ext = '';
		}
		if(@parts == 2) {
			$base = $parts[0];
			$ext = ".$parts[1]";
		}
		else {
			$ext = "." . pop @parts;
			$base = join ".", @parts;
		}
		my $ary = $db->query("select $fields FROM $table WHERE $i_f = '$base$ext'");
		
		if($ary and @$ary) {
			for(@$ary) {
				my ($sku, $i_d, $t_d) = @$_;
				$t_d = $thumb ? "$base$ext" : $t_d;
				if($i_d ne "$base$ext" or $thumb) {
					push @do, [$sku, "$base$ext", "$base$ext"];
				}
			}
		}
		else {
			$ary = $db->query("select $s_f FROM $table WHERE $s_f = '$base'");
			if($ary) {
				for(@$ary) {
					my ($sku, $i_d, $t_d) = @$_;
					$t_d = $thumb ? "$base$ext" : $t_d;
					if($i_d ne "$base$ext" or $thumb) {
						push @do, [$sku, "$base$ext", $t_d];
					}
				}
			}
		}
		if(! $ary or !@$ary) {
			push @unfound, "$base$ext";
		}
	}

	mkdir 'items', 0777;
	mkdir 'thumb', 0777;

	for(@do) {
		my $sku = shift @$_;
		push (@did, $sku);
		$db->set_slice($sku, [$i_f, $t_f], $_)
			or return tmp_error("unable to set table=%s for sku=%s.", $table, $sku);
		File::Copy::copy($_->[0], 'items');
		File::Copy::copy($_->[0], 'thumb') if $thumb;
	}

	my @errors;

	if($thumb) {
		my $size = $opt->{thumb_size} || '60x60';
		chdir('thumb')
			or return tmp_die("cannot chdir to directory %s: %s", "$tmpdir/thumb", $!);
		system("/usr/X11R6/bin/mogrify -geometry $size *");
		if($?) {
			my $status = $? >> 8;
			undef $thumb;
			push @errors, errmsg("error %s creating thumbs: %s", $status, $!);
		}
		chdir '..';
	}

	my $save_mask = umask(2);

	foreach my $base (qw/ items thumb /) {
		my $imgbase = "$Vend::Cfg->{VendRoot}/images/$base";
		if(! -d $imgbase) {
			push @errors,
				::errmsg("No image directory for %s. Skipping image copy.", $base);
		}
		else {
#my $curr = `pwd`;
#chop $curr;
#Debug("found dir $imgbase, curr=$curr, globbing $base/$_");
			for( glob("$base/*") ) {
#Debug("copy $_ to $imgbase");
				chmod 0664, $_;
				File::Copy::copy($_, $imgbase)
					or push @errors,
						::errmsg("failed to copy %s to %s: %s", $_, $imgbase, $!);
			}
		}
	}

	umask $save_mask;

	chdir($Vend::Cfg->{VendRoot});
	return 1 if $opt->{return_status};
	return '' if $opt->{hide};
	my $out = '';

	if($opt->{verbose}) {
		$out .= "Files: <br><blockquote>" . join("<br>", @ifiles) . "</blockquote>\n";
		$out .= "Files found:<br><blockquote>";
		$out .= join("<BR>", @did);
		$out .= "</blockquote>\n";
	}

	if(@unfound) {
		$out .= "No item found for image file:<br><blockquote>";
		$out .= join("<BR>", @unfound);
		$out .= "</blockquote>Not copied.\n";
	}
	if(@errors) {
		$out .= "Errors:<br><blockquote>";
		$out .= join("<BR>", @errors);
		$out .= "</blockquote>\n";
	}
	return $out;
}
EOR

