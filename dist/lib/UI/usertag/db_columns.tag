UserTag db_columns  Order name columns joiner passed_order
UserTag db_columns  AttrAlias table name
UserTag db_columns  AttrAlias fields columns
UserTag db_columns  Routine <<EOR
sub {
	my ($table,$columns, $joiner, $passed_order) = @_;
	$table = $Values->{mv_data_table}
		unless $table;
	my $db = Vend::Data::database_exists_ref($table)
		or return undef;
	my $acl = UI::Primitive::get_ui_table_acl($table);
	$db = $db->ref() unless $Vend::Interpolate::Db{$table};
	my $key = $db->config('KEY');

	$joiner = "\n" unless defined $joiner;

	my @cols;
	if(! $columns || $columns =~ /^[\s,\0]*$/) {
		@cols = $db->columns();
	}
	else {
		@cols = grep /\S/, split /[\s,\0]+/, $columns;
		my (@allcols) =  $db->columns();

		my %col;
		if($passed_order) {
			@col{@allcols} = @allcols;
			@allcols = @cols;
			my $found;
			for(@cols) {
				next unless $_ eq $key;
				$found = 1;
				last;
			}
			unshift (@allcols, $key) if ! $found;
		}
		else {
			@col{@cols} = @cols;
		}

		$col{$key} = $key if ! defined $col{$key};

		@cols = grep defined $col{$_}, @cols;
	}

	if($acl) {
		@cols = UI::Primitive::ui_acl_grep( $acl, 'fields', @cols);
	}

	return join $joiner, @cols;
}
EOR

