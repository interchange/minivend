UserTag save_cart Order nickname recurring
UserTag save_cart Routine <<EOR
sub {
	my($nickname,$recurring) = @_;

	my $add = 0;
	my %names = ();

	$nickname =~ s/://g;
	$recurring = ($recurring?"r":"c");

	foreach(split("\n",$Tag->value('carts'))) {
		my($n,$t,$r) = split(':',$_);
		$names{$n} = $r;
		if($r eq $recurring) {
			if($n eq $nickname) {
				#$Tag->userdb({function => 'delete_cart', nickname => $_});
				$add = 1;
			}
		}
	}
	if($add) {
		while($names{"$nickname,$add"} eq $recurring) {
			$add++;
		}
		$nickname .= ",$add";
	}

	my $nn = join(':',$nickname,time(),$recurring);

	$Tag->userdb({function => 'set_cart', nickname => $nn});

	$Carts->{main} = [];

	return '';
}
EOR
