UserTag component Order component
UserTag component addAttr
UserTag component NoReparse 1
UserTag component Routine <<EOR
sub {
	my ($name, $opt) = @_;

	my %ignore = (
		qw/
			component    1
			comp_table   1
			comp_field   1
			comp_cache   1
			reparse      1
			interpolate  1
		/
	);
	my @override = grep ! $ignore{$_}, keys %$opt;

	my $control = $::Control->[$::Scratch->{control_index}];
	for(grep $_ !~ /^comp(?:onent)?_?/, keys %$opt) {
		$control->{$_} = $opt->{$_};
	}

	$name ||= $control->{component};

	if (! $name) {
		# Increment control_index so empty component has no side effect
		$::Scratch->{control_index}++;
		return;
	}

	my $t = $opt->{comp_table} || $::Variable->{MV_COMPONENT_TABLE} || 'component';
	my $ctab = $::Variable->{MV_COMPONENT_CACHE} || 'component_cache';

	my $record;
	my $db = database_exists_ref($t);
	my $nocache;

	if($db) {
		if(my $when = $Vend::Session->{teleport}) {
			$nocache = 1;
			my $q = qq{
				SELECT code from $t
				WHERE  base_code = '$name'
				AND    expiration_date < $when
				AND    show_date >= $when
				ORDER BY show_date DESC
			};
			my $ary = $db->query($q);
			if($ary and $ary->[0]) {
				$name = $ary->[0][0];
			}
		}
		$record = $db->row_hash($name);
	}

	$record ||= {};

	my $body = $record->{comptext};

	if(! length($body)) {
		my $dir = $opt->{comp_dir}
				|| $::Variable->{MV_COMPONENT_DIR}
				|| 'templates/components';
		$body = readfile("$dir/$name");
	}

	# Increment control_index so empty component has no side effect
	if (! length $body) {
		$::Scratch->{control_index}++;
		return;
	}

	my $cache_it;
	my $cdb;
	my $now;
	my $crecord;
	if (
		! $nocache
		and $record->{cache_interval}
		and $cdb = database_exists_ref($ctab)
		)
	{
		$cache_it = $name;

		# Cache based not only on name, but control values specified
		if($record->{cache_options}) {
			my @opts = split /[\s,\0]+/, $record->{cache_options};
			$cache_it .= '.';
			$cache_it .= generate_key( join "\0", @{$control}{@opts});
		}

		$crecord = $cdb->row_hash($cache_it) || {};
		$now = time;
		
		my $secs	= $record->{cache_interval} =~ /\D/
					? time_to_seconds($record->{cache_interval}) 
					: $record->{cache_interval};
		my $exp = $crecord->{cache_time} + $secs;
		
		if ($exp > $now) {
			# Increment control_index as not done below
			$::Scratch->{control_index}++;
			return $crecord->{compcache};
		}
	}

	my $result = interpolate_html($body);
	$::Scratch->{control_index}++;
	if($cache_it) {
		my $thing = {
						compcache => $result,
						cache_time => $now,
					};
		$cdb->set_slice($cache_it, $thing);
	}

	return $result;
}
EOR
