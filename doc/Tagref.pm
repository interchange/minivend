# Parse.pm - Parse MiniVend tags
# 
# $Id: Parse.pm,v 1.48 1999/02/15 08:51:10 mike Exp mike $
#
# Copyright 1997-1999 by Michael J. Heins <mikeh@iac.net>
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

package Vend::Parse;

# $Id: Parse.pm,v 1.48 1999/02/15 08:51:10 mike Exp mike $

require Vend::Parser;


$VERSION = sprintf("%d.%02d", q$Revision: 1.48 $ =~ /(\d+)\.(\d+)/);

use Safe;
use Vend::Util;
use Vend::Interpolate;
use Text::ParseWords;
# STATICPAGE
use Vend::PageBuild;
# END STATICPAGE
use Vend::Data qw/product_field/;

#require Exporter;

@ISA = qw(Exporter Vend::Parser);

$VERSION = substr(q$Revision: 1.48 $, 10);
@EXPORT = ();
@EXPORT_OK = qw(find_matching_end);

use strict;

use vars qw($VERSION);

my($CurrentSearch, $CurrentCode, $CurrentDB, $CurrentWith, $CurrentItem);
my(@SavedSearch, @SavedCode, @SavedDB, @SavedWith, @SavedItem);

my %PosNumber =	( qw!
                    
                accessories      2
                area             2
                areatarget       3
                body             2
                bounce           2
                buttonbar        1
                cart             1
                cgi              1
                checked          3
                currency         1
                data             6
                default          2
                discount         1
                description      2
				ecml			 2
                field            2
                file             2
                finish_order     1
                fly_list         2
                framebase        1
                goto             2
                help             1
                if               1
                import           2
                include          1
                input_filter     1
                index            1
                label            1
                last_page        2
                lookup           1
                loop             1
                mvasp            1
                nitems           1
                order            4
                page             2
                pagetarget       3
                perl             1
                price            4
                process_order    2
                process_search   1
                process_target   2
                rotate           2
                row              1
                salestax         2
                scratch          1
                search           1
                search_region    1
                selected         3
                set              1
                setlocale        3
                shipping         3
                shipping_desc    1
                sql              2
                subtotal         2
                tag              1
                total_cost       2
                userdb           1
                value            4
                value_extended   1

			! );

my %Optional =	(

		
    	import          => [qw(continue separator)],
		area			=> [qw(form)],

		);

my %Order =	(

				accessories		=> [qw( code arg )],
				area			=> [qw( href arg secure)],
				areatarget		=> [qw( href target arg secure)],
				body			=> [qw( type extra )],
				bounce			=> [qw( href if )],
				buttonbar		=> [qw( type  )],
				calc			=> [],
				cart			=> [qw( name  )],
				cgi				=> [qw( name  )],
				compat			=> [],
				'currency'		=> [qw( convert )],
				checked			=> [qw( name value multiple default)],
				data			=> [qw( table field key value increment append )],
				default			=> [qw( name default set)],
				description		=> [qw( code base )],
				discount		=> [qw( code  )],
				ecml			=> [qw( name function )],
				field			=> [qw( name code )],
				file			=> [qw( name type )],
				finish_order	=> [qw( href )],
				fly_list		=> [qw( code base )],
				framebase		=> [qw( target  )],
				frames_off		=> [],
				frames_on		=> [],
				'goto'			=> [qw( name if)],
				help			=> [qw( name  )],
				'if'			=> [qw( type term op compare )],
				'or'			=> [qw( type term op compare )],
				'and'			=> [qw( type term op compare )],
				index  			=> [qw( table )],
				import 			=> [qw( table type )],
				input_filter 	=> [qw( name )],
				include			=> [qw( file )],
				item_list		=> [qw( name )],
				label			=> [qw( name )],
				last_page		=> [qw( target arg )],
				lookup			=> [qw( table field key value )],
				loop			=> [qw( with arg search option)],
				loop_change		=> [qw( with arg )],
				nitems			=> [qw( name  )],
				order			=> [qw( code href base quantity )],
				page			=> [qw( href arg secure)],
				pagetarget		=> [qw( href target arg secure)],
				perl			=> [qw( arg )],
				mvasp			=> [qw( tables )],
				post			=> [],
				price			=> [qw( code quantity base noformat)],
				process_order	=> [qw( target secure )],
				process_search	=> [qw( target )],
				process_target	=> [qw( target secure )],
				random			=> [],
				read_cookie		=> [qw( name )],
				rotate			=> [qw( ceiling floor )],
				row				=> [qw( width )],
				'salestax'		=> [qw( name noformat)],
				scratch			=> [qw( name  )],
				search			=> [qw( arg   )],
				search_region	=> [qw( arg   )],
				selected		=> [qw( name value multiple )],
				set_cookie		=> [qw( name value expire )],
				setlocale		=> [qw( locale currency persist )],
				set				=> [qw( name  )],
				'shipping'		=> [qw( name cart noformat )],
				shipping_desc	=> [qw( name  )],
				sql				=> [qw( type query list false base)],
				strip			=> [],
				'subtotal'		=> [qw( name noformat )],
				tag				=> [qw( op base file type )],
				total_cost		=> [qw( name noformat )],
				userdb          => [qw( function ) ],
				value			=> [qw( name escaped set hide)],
				value_extended  => [qw( name )],

			);

my %InvalidateCache = (

			qw(
				cgi			1
				cart		1
				checked		1
				default		1
				discount	1
				frames_off	1
				frames_on	1
				item_list	1
				import		1
				index		1
				input_filter		1
				if          1
				last_page	1
				lookup		1
				mvasp		1
				nitems		1
				perl		1
				'salestax'	1
				scratch		1
				selected	1
				read_cookie 1
				set_cookie  1
				set			1
				'shipping'	1
				sql			1
				subtotal	1
				total_cost	1
				userdb		1
				value		1
				value_extended 1

			   )
			);

my %Implicit = (

			'data' =>		{ qw( increment increment ) },
			'value' =>		{ qw( escaped	escaped hide hide ) },
			'checked' =>	{ qw( multiple	multiple default	default ) },
			'area'    =>	{ qw( secure	secure ) },
			'page'    =>	{ qw( secure	secure ) },
			'areatarget'    =>	{ qw( secure	secure ) },
			'process_order' =>	{ qw( secure	secure ) },
			'process_target' =>	{ qw( secure	secure ) },
			'pagetarget'    =>	{ qw( secure	secure ) },

			'if' =>		{ qw(
								!=		op
								!~		op
								<=		op
								==		op
								=~		op
								>=		op
								eq		op
								gt		op
								lt		op
								ne		op
					   )},

			'and' =>		{ qw(
								!=		op
								!~		op
								<=		op
								==		op
								=~		op
								>=		op
								eq		op
								gt		op
								lt		op
								ne		op
					   )},

			'or' =>		{ qw(
								!=		op
								!~		op
								<=		op
								==		op
								=~		op
								>=		op
								eq		op
								gt		op
								lt		op
								ne		op
					   )},

			);

my %PosRoutineName = (
				'or'			=> q{sub { return &Vend::Interpolate::tag_if(@_, 1) }},
				'and'			=> q{sub { return &Vend::Interpolate::tag_if(@_, 1) }},
				'if'			=> q{\&Vend::Interpolate::tag_if},
				'tag'			=> q{\&Vend::Interpolate::do_tag},
				'sql'			=> q{\&Vend::Data::sql_query},
			);

my %RoutineName = (

				accessories		=> q{sub {
									&Vend::Interpolate::tag_accessories
										($_[0], '', $_[1])
									}},
				area			=> q{\&Vend::Interpolate::tag_area},
				areatarget		=> q{\&Vend::Interpolate::tag_areatarget},
				body			=> q{\&Vend::Interpolate::tag_body},
				bounce          => q{sub { return '' }},
				buttonbar		=> q{\&Vend::Interpolate::tag_buttonbar},
				calc			=> q{\&Vend::Interpolate::tag_calc},
				cart			=> q{\&Vend::Interpolate::tag_cart},
				cgi				=> q{\&Vend::Interpolate::tag_cgi},
				checked			=> q{\&Vend::Interpolate::tag_checked},
				'currency'		=> q{sub {
										my($convert,$amount) = @_;
										return &Vend::Util::currency(
														$amount,
														undef,
														$convert);
									}},
				compat			=> q{sub {
										&Vend::Interpolate::interpolate_html('[old]' . $_[0]);
									}},
				data			=> q{\&Vend::Interpolate::tag_data},
				default			=> q{\&Vend::Interpolate::tag_default},
				description		=> q{\&Vend::Data::product_description},
				discount		=> q{\&Vend::Interpolate::tag_discount},
				ecml			=> q{\&Vend::ECML::ecml},
				field			=> q{\&Vend::Data::product_field},
				file			=> q{\&Vend::Interpolate::tag_file},
				finish_order	=> q{\&Vend::Interpolate::tag_finish_order},
				fly_list		=> q{sub {
									$_[0] = $Vend::Session->{'arg'} unless $_[0];
									return &Vend::Interpolate::fly_page(@_);
									}},
				framebase		=> q{\&Vend::Interpolate::tag_frame_base},
				frames_off		=> q{\&Vend::Interpolate::tag_frames_off},
				frames_on		=> q{\&Vend::Interpolate::tag_frames_on},
				help			=> q{\&Vend::Interpolate::tag_help},
				index 			=> q{\&Vend::Data::index_database},
				import 			=> q{\&Vend::Data::import_text},
				include			=> q{sub {
									&Vend::Interpolate::interpolate_html(
										&Vend::Util::readfile
											($_[0], $Global::NoAbsolute)
										  );
									}},
				input_filter	=> q{\&Vend::Interpolate::input_filter},
				item_list		=> q{\&Vend::Interpolate::tag_item_list},
				'if'			=> q{\&Vend::Interpolate::tag_self_contained_if},
				'or'			=> q{sub { return &Vend::Interpolate::tag_self_contained_if(@_, 1) }},
				'and'			=> q{sub { return &Vend::Interpolate::tag_self_contained_if(@_, 1) }},
				'goto'			=> q{sub { return '' }},
				label			=> q{sub { return '' }},
				last_page		=> q{\&Vend::Interpolate::tag_last_page},
				lookup			=> q{\&Vend::Interpolate::tag_lookup},
				loop			=> q{sub {
									# Munge the args, UGHH. Fix this.
									my $option = splice(@_,3,1);
									return &Vend::Interpolate::tag_loop_list
										(@_, $option);
									}},
				nitems			=> q{\&Vend::Util::tag_nitems},
				order			=> q{\&Vend::Interpolate::tag_order},
				page			=> q{\&Vend::Interpolate::tag_page},
				pagetarget		=> q{\&Vend::Interpolate::tag_pagetarget},
				perl			=> q{\&Vend::Interpolate::tag_perl},
				mvasp			=> q{\&Vend::Interpolate::mvasp},
				post			=> q{sub { return $_[0] }},
				price        	=> q{\&Vend::Interpolate::tag_price},
				process_order	=> q{\&Vend::Interpolate::tag_process_order},
				process_search	=> q{\&Vend::Interpolate::tag_process_search},
				process_target	=> q{\&Vend::Interpolate::tag_process_target},
				random			=> q{\&Vend::Interpolate::tag_random},
				read_cookie     => q{\&Vend::Util::read_cookie},
				rotate			=> q{\&Vend::Interpolate::tag_rotate},
				row				=> q{\&Vend::Interpolate::tag_row},
				'salestax'		=> q{\&Vend::Interpolate::tag_salestax},
				scratch			=> q{\&Vend::Interpolate::tag_scratch},
				search			=> q{\&Vend::Interpolate::tag_search},
				search_region	=> q{\&Vend::Interpolate::tag_search_region},
				selected		=> q{\&Vend::Interpolate::tag_selected},
				setlocale		=> q{\&Vend::Util::setlocale},
				set_cookie		=> q{\&Vend::Util::set_cookie},
				rotate			=> q{\&Vend::Interpolate::tag_rotate},
				set				=> q{\&Vend::Interpolate::set_scratch},
				'shipping'		=> q{\&Vend::Interpolate::tag_shipping},
				shipping_desc	=> q{\&Vend::Interpolate::tag_shipping_desc},
				sql				=> q{\&Vend::Data::sql_query},
				'subtotal'		=> q{\&Vend::Interpolate::tag_subtotal},
				strip			=> q{sub {
										local($_) = shift;
										s/^\s+//;
										s/\s+$//;
										return $_;
									}},
				tag				=> q{\&Vend::Interpolate::do_parse_tag},
				total_cost		=> q{\&Vend::Interpolate::tag_total_cost},
				userdb			=> q{\&Vend::UserDB::userdb},
				value			=> q{\&Vend::Interpolate::tag_value},
				value_extended	=> q{\&Vend::Interpolate::tag_value_extended},

			);



my %PosRoutine = (
				'or'			=> sub { return &Vend::Interpolate::tag_if(@_, 1) },
				'and'			=> sub { return &Vend::Interpolate::tag_if(@_, 1) },
				'if'			=> \&Vend::Interpolate::tag_if,
				'tag'			=> \&Vend::Interpolate::do_tag,
				'sql'			=> \&Vend::Data::sql_query,
			);

my %Routine = (

				accessories		=> sub {
									&Vend::Interpolate::tag_accessories
										($_[0], '', $_[1])
									},
				area			=> \&Vend::Interpolate::tag_area,
				areatarget		=> \&Vend::Interpolate::tag_areatarget,
				body			=> \&Vend::Interpolate::tag_body,
				bounce          => sub { return '' },
				buttonbar		=> \&Vend::Interpolate::tag_buttonbar,
				calc			=> \&Vend::Interpolate::tag_calc,
				cart			=> \&Vend::Interpolate::tag_cart,
				cgi				=> \&Vend::Interpolate::tag_cgi,
				checked			=> \&Vend::Interpolate::tag_checked,
				'currency'		=> sub {
										my($convert,$amount) = @_;
										return &Vend::Util::currency(
														$amount,
														undef,
														$convert);
									},
				compat			=> sub {
										&Vend::Interpolate::interpolate_html('[old]' . $_[0]);
									},
				data			=> \&Vend::Interpolate::tag_data,
				default			=> \&Vend::Interpolate::tag_default,
				description		=> \&Vend::Data::product_description,
				discount		=> \&Vend::Interpolate::tag_discount,
				ecml			=> \&Vend::ECML::ecml,
				field			=> \&Vend::Data::product_field,
				file			=> \&Vend::Interpolate::tag_file,
				finish_order	=> \&Vend::Interpolate::tag_finish_order,
				fly_list		=> sub {
									$_[0] = $Vend::Session->{'arg'} unless $_[0];
									return &Vend::Interpolate::fly_page(@_);
									},
				framebase		=> \&Vend::Interpolate::tag_frame_base,
				frames_off		=> \&Vend::Interpolate::tag_frames_off,
				frames_on		=> \&Vend::Interpolate::tag_frames_on,
				help			=> \&Vend::Interpolate::tag_help,
				index 			=> \&Vend::Data::index_database,
				import 			=> \&Vend::Data::import_text,
				include			=> sub {
									&Vend::Interpolate::interpolate_html(
										&Vend::Util::readfile
											($_[0], $Global::NoAbsolute)
										  );
									},
				input_filter	=> \&Vend::Interpolate::input_filter,
				item_list		=> \&Vend::Interpolate::tag_item_list,
				'if'			=> \&Vend::Interpolate::tag_self_contained_if,
				'or'			=> sub { return &Vend::Interpolate::tag_self_contained_if(@_, 1) },
				'and'			=> sub { return &Vend::Interpolate::tag_self_contained_if(@_, 1) },
				'goto'			=> sub { return '' },
				label			=> sub { return '' },
				last_page		=> \&Vend::Interpolate::tag_last_page,
				lookup			=> \&Vend::Interpolate::tag_lookup,
				loop			=> sub {
									# Munge the args, UGHH. Fix this.
									my $option = splice(@_,3,1);
									return &Vend::Interpolate::tag_loop_list
										(@_, $option);
									},
				nitems			=> \&Vend::Util::tag_nitems,
				order			=> \&Vend::Interpolate::tag_order,
				page			=> \&Vend::Interpolate::tag_page,
				pagetarget		=> \&Vend::Interpolate::tag_pagetarget,
				perl			=> \&Vend::Interpolate::tag_perl,
				mvasp			=> \&Vend::Interpolate::mvasp,
				post			=> sub { return $_[0] },
				price        	=> \&Vend::Interpolate::tag_price,
				process_order	=> \&Vend::Interpolate::tag_process_order,
				process_search	=> \&Vend::Interpolate::tag_process_search,
				process_target	=> \&Vend::Interpolate::tag_process_target,
				random			=> \&Vend::Interpolate::tag_random,
				read_cookie     => \&Vend::Util::read_cookie,
				rotate			=> \&Vend::Interpolate::tag_rotate,
				row				=> \&Vend::Interpolate::tag_row,
				'salestax'		=> \&Vend::Interpolate::tag_salestax,
				scratch			=> \&Vend::Interpolate::tag_scratch,
				search			=> \&Vend::Interpolate::tag_search,
				search_region	=> \&Vend::Interpolate::tag_search_region,
				selected		=> \&Vend::Interpolate::tag_selected,
				setlocale		=> \&Vend::Util::setlocale,
				set_cookie		=> \&Vend::Util::set_cookie,
				rotate			=> \&Vend::Interpolate::tag_rotate,
				set				=> \&Vend::Interpolate::set_scratch,
				'shipping'		=> \&Vend::Interpolate::tag_shipping,
				shipping_desc	=> \&Vend::Interpolate::tag_shipping_desc,
				sql				=> \&Vend::Data::sql_query,
				'subtotal'		=> \&Vend::Interpolate::tag_subtotal,
				strip			=> sub {
										local($_) = shift;
										s/^\s+//;
										s/\s+$//;
										return $_;
									},
				tag				=> \&Vend::Interpolate::do_parse_tag,
				total_cost		=> \&Vend::Interpolate::tag_total_cost,
				userdb			=> \&Vend::UserDB::userdb,
				value			=> \&Vend::Interpolate::tag_value,
				value_extended	=> \&Vend::Interpolate::tag_value_extended,

			);


my %attrAlias = (
	 page          	=> { 'base' => 'arg' },
	 field          	=> { 
	 						'field' => 'name',
	 						'column' => 'name',
	 						'col' => 'name',
	 						'key' => 'code',
	 						'row' => 'code',
						},
	 index          	=> { 
	 						'database' => 'table',
	 						'base' => 'table',
						},
	 import          	=> { 
	 						'database' => 'table',
	 						'base' => 'table',
						},
	 input_filter          	=> { 
	 						'ops' => 'op',
	 						'var' => 'name',
	 						'variable' => 'name',
						},
	 data          	=> { 
	 						'database' => 'table',
	 						'base' => 'table',
	 						'name' => 'field',
	 						'column' => 'field',
	 						'col' => 'field',
	 						'code' => 'key',
	 						'row' => 'key',
						},
	 'or'			=> { 
	 						'comp' => 'compare',
	 						'operator' => 'op',
	 						'base' => 'type',
						},
	 'and'			=> { 
	 						'comp' => 'compare',
	 						'operator' => 'op',
	 						'base' => 'type',
						},
	 'userdb'		=> {
	 						'table' => 'db',
	 						'name' => 'nickname',
						},
	 'shipping'			=> { 'cart' => 'name', },
	 'salestax'			=> { 'cart' => 'name', },
	 'subtotal'			=> { 'cart' => 'name', },
	 'total_cost'		=> { 'cart' => 'name', },
	 'if'			=> { 
	 						'comp' => 'compare',
	 						'condition' => 'compare',
	 						'operator' => 'op',
	 						'base' => 'type',
						},
	 search_region	   	=> { params => 'arg',
	 						 args => 'arg', },
	 loop	          	=> { args => 'arg',
	 						 list => 'arg', },
	 item_list	       	=> { cart => 'name', },
	 lookup          	=> { 
	 						'database' => 'table',
	 						'base' => 'table',
	 						'name' => 'field',
	 						'code' => 'key',
						},
);

my %Alias = (

				qw(
						url			urldecode
						urld		urldecode
						href		area
						shipping_description shipping_desc
						a			pagetarget
				)
			);

my %canNest = (

				qw(
						if			1
						loop		1
				)
			);


my %addAttr = (
				qw(
					ecml      1
					userdb    1
					import    1
					input_filter  1
					index     1
					page	  1
					price	  1
					area	  1
					value_extended    1
				)
			);


my %replaceHTML = (
				qw(
					del .*
					pre .*
					xmp .*
					script .*
				)
			);

my %replaceAttr = (
					area			=> { qw/ a 	href			/},
					areatarget		=> { qw/ a 	href			/},
					process_target	=> { qw/ form action		/},
					process_order 	=> { qw/ form action		/},
					process_search	=> { qw/ form action		/},
					checked			=> { qw/ input checked		/},
					selected		=> { qw/ option selected	/},
			);

my %insertHTML = (
				qw(

				form	process_target|process_order|process_search|area
				a 		area|areatarget
				input	checked
				option  selected
				)
			);

my %lookaheadHTML = (
				qw(

				if 		then|elsif|else
				)
			);

my %rowfixHTML = (	qw/
						td	item_list|loop|sql_list
					/	 );
# Only for containers
my %insideHTML = (
				qw(
					select	loop|item_list|tag
				)

				);

# Only for containers
my %endHTML = (
				qw(

				tr 		.*
				td 		.*
				th 		.*
				del 	.*
				script 	.*
				table 	if
				object 	perl
				param 	perl
				font 	if
				a 		if
				)
			);

my %hasEndTag = (

				qw(
						calc		1
						compat		1
						currency	1
						discount	1
						fly_list	1
						if			1
						import		1
						item_list	1
						input_filter  1
						loop		1
						sql			1
						perl		1
						mvasp		1
						post		1
						row			1
						set			1
						search_region			1
						strip		1
						tag			1

				)
			);

my %Interpolate = (

				qw(
						buttonbar	1
						calc		1
						currency	1
						import		1
						random		1
						rotate		1
						row			1
				)
			);

my %Gobble = ( qw/ mvasp 1/ );

my %isEndAnchor = (

				qw(
						areatarget	1
						area		1
						pagetarget	1
						page		1
						order		1
						last_page	1
				)
			);

my $Tags_added = 0;

my $Initialized = 0;


sub global_init {
		add_tags($Global::UserTag);
}

sub new
{
    my $class = shift;
    my $self = new Vend::Parser;
	$self->{INVALID} = 0;
	$self->{INTERPOLATE} = shift || 0;

	add_tags($Vend::Cfg->{UserTag})
		unless $Tags_added;

	$self->{TOPLEVEL} = 1 if ! $Initialized;

	$self->{OUT} = '';
    bless $self, $class;
	$Initialized = $self;
}

my %myRefs = (
     Alias           => \%Alias,
     addAttr         => \%addAttr,
     attrAlias       => \%attrAlias,
	 canNest         => \%canNest,
	 endHTML         => \%endHTML,
	 hasEndTag       => \%hasEndTag,
	 Implicit        => \%Implicit,
	 insertHTML	     => \%insertHTML,
	 insideHTML	     => \%insideHTML,
	 Interpolate     => \%Interpolate,
	 InvalidateCache => \%InvalidateCache,
	 isEndAnchor     => \%isEndAnchor,
	 lookaheadHTML   => \%lookaheadHTML,
	 Order           => \%Order,
	 PosNumber       => \%PosNumber,
	 PosRoutine      => \%PosRoutine,
	 replaceAttr     => \%replaceAttr,
	 replaceHTML     => \%replaceHTML,
	 Routine         => \%Routine,
);

my %Documentation;

sub tag_reference {
	LOCAL: {
		local($/);
		my $text = <DATA>;
		my (@items) = grep /\S/, split /\n%%%\n/, $text;
		for(@items) {
			my ($k, $v) = split /\n%%\n/, $_, 2;
			$Documentation{$k} = $v;
		}
	}

	print $Documentation{BEGIN};

	for(sort keys %Routine) {
		my $tag = $_;
		print "\n\n=head2 $tag\n\n=over 4\n\n";
		print "=item CALL INFORMATION\n\n";
		my $val;
		my @alias = %Alias;
		my @val = ();
		for (my $i = 1; $i < @alias; $i += 2) {
			push @val, $alias[$i - 1] if $alias[$i] eq $tag;
		}


		if(@val) {
			print "Aliases for tag\n\n";
			print join "\n", @val;
			print "\n\n";
		}
		@val = ();

		my @parms = ();
		if(defined $Order{$tag} and @{$Order{$tag}}) {
			@parms = @{$Order{$tag}};
			print "Parameters: B<";
			print join " ", @parms;
			print ">\n\n";
			if($PosNumber{$tag} >= @parms) {
				print "Positional parameters in same order.\n";
			}
			elsif ($tag eq 'loop' || $PosRoutine{$tag}) {
				print "THIS TAG HAS SPECIAL POSITIONAL PARAMETER HANDLING.\n\n";
			}
			else {
				print "ONLY THE B<";
				print join " ", @parms[0 .. $PosNumber{$tag} - 1];
				print "> PARAMETERS ARE POSITIONAL.\n";
			}
			print "\n\n";
		}
		else {
			printf "No parameters.\n\n";
		}

		if(defined $addAttr{$tag}) {
			print <<EOF if defined $hasEndTag{$tag};
B<The attribute hash reference is passed> after the parameters but before
the container text argument.
B<This may mean that there are parameters not shown here.>

EOF
			print <<EOF if ! defined $hasEndTag{$tag};
B<The attribute hash reference is passed> to the subroutine after
the parameters as the last argument.
B<This may mean that there are parameters not shown here.>

EOF
		}
		else {
			print "Pass attribute hash as last to subroutine: B<no>\n\n";
		}

		if(! defined $Interpolate{$tag}) {
			print "Must pass named parameter interpolate=1 to cause interpolation.";
		}
		elsif($hasEndTag{$tag}) {
			print "Interpolates B<container text> by default>.";
		}
		elsif(!$Gobble{$tag}) {
			print "Interpolates B<its own output> by default.";
		}

		print "\n\n";

		if (defined $hasEndTag{$tag}) {
			my $nest = defined $canNest{$tag} ? 'YES' : 'NO';
			print "This is a container tag, i.e. [$tag] FOO [/$tag].\nNesting: $nest\n\n";
		}

		print "Invalidates cache: B<"							.
				(defined $InvalidateCache{$tag} ? 'YES' : 'no')	.
				">\n\n";
		print "This tag B<gobbles> all remaining page text if no end tag is passed.\n\n"
			if $Gobble{$tag};
		       

		print "Called Routine: $RoutineName{$tag}\n\n";
		print "Called Routine for positonal: $PosRoutineName{$tag}\n\n" if $PosRoutine{$tag};

		print "ASP/perl tag calls:\n\n";
		print '    $Tag->' . $tag . '(' ."\n        {\n";
		for (@parms) {
			print "         $_ => VALUE,\n";
		}
		print "        }";
		print ",\n        BODY" if defined $hasEndTag{$tag};
		print "\n    )\n  \n OR\n \n";
		push @parms, 'ATTRHASH'		if defined $addAttr{$tag};
		push @parms, 'BODY'			if defined $hasEndTag{$tag};
		print '    $Tag->' . $tag . '($' . join(', $', @parms) . ');' . "\n\n";

		if (defined $attrAlias{$tag}) {
			printf "Attribute aliases\n\n";
			for( sort keys %{$attrAlias{$tag}}) {
				print "            $_ ==> $attrAlias{$tag}{$_}\n";
			}
			print "\n\n";
		}
		print " \n\n";
		print "=item DESCRIPTION\n\n";
		print $Documentation{$tag} if defined $Documentation{$tag};
		print "B<NO DESCRIPTION>" if ! defined $Documentation{$tag};
		print "\n\n";
		print "=back\n\n";

	}

	print $Documentation{END};
}

sub do_tag {
	my $tag = shift;
	if (! defined $Routine{tag} and (not $tag = $Alias{$tag}) ) {
		::logError("Tag '$tag' not defined.");
		return undef;
	};
	if(ref $_[-1] && scalar @{$Order{$tag}}) {
		my $text;
		my $ref = pop(@_);
		$text = shift if $hasEndTag{$tag};
		my @args = @$ref{ @{$Order{$tag}} };
		push @args, $ref if $addAttr{$tag};
		return &{$Routine{$tag}}(@args, $text || undef);
	}
	else {
		return &{$Routine{$tag}}(@_);
	}
}

sub resolve_args {
	my $tag = shift;
	return @_ unless defined $Routine{$tag};
	my $ref = shift;
	my @list;
	if(defined $attrAlias{$tag}) {
		my ($k, $v);
		while (($k, $v) = each %{$attrAlias{$tag}} ) {
			next unless defined $ref->{$k};
			$ref->{$v} = $ref->{$k};
		}
	}
	@list = @{$ref}{@{$Order{$tag}}};
	push @list, $ref if defined $addAttr{$tag};
	push @list, (shift || $ref->{body} || '') if $hasEndTag{$tag};
	return @list;
}

sub add_tags {
	return unless @_;
	my $ref = shift;
	my $area;
	no strict 'refs';
	foreach $area (keys %myRefs) {
		next unless $ref->{$area};
# DEBUG
# Vend::Util::logDebug
# ("Adding $area = " . Vend::Util::uneval($ref->{$area}) . "\n")
#	if ::debug(0x2);
# END DEBUG
		if($area eq 'Routine') {
			for (keys %{$ref->{$area}}) {
				$myRefs{$area}->{$_} = $ref->{$area}->{$_};
			}
			next;
		}
		elsif ($area =~ /HTML$/) {
			for (keys %{$ref->{$area}}) {
				$myRefs{$area}->{$_} =
					defined $myRefs{$area}->{$_}
					? $ref->{$area}->{$_} .'|'. $myRefs{$area}->{$_}
					: $ref->{$area}->{$_};
			}
		}
		else {
			Vend::Util::copyref $ref->{$area}, $myRefs{$area};
		}
	}
}

sub eof
{
    shift->parse(undef);
}

sub text
{
    my($self, $text) = @_;
	$Vend::PageCacheCopy .= $text
		if defined $Vend::PageCacheCopy and $self->{TOPLEVEL};
	$self->{OUT} .= $text;
}

sub comment
{
    # my($self, $comment) = @_;
}

my %Monitor = ( qw( ) );

sub build_html_tag {
	my ($orig, $attr, $attrseq) = @_;
	$orig =~ s/\s+.*//s;
	for (@$attrseq) {
		$orig .= qq{ \U$_="} ;
		$attr->{$_} =~ s/"/\\"/g;
		$orig .= $attr->{$_};
		$orig .= '"';
	}
	$orig .= ">";
}

my %implicitHTML = (qw/checked CHECKED selected SELECTED/);

sub format_html_attribute {
	my($attr, $val) = @_;
	if(defined $implicitHTML{$attr}) {
		return $implicitHTML{$attr};
	}
	$val =~ s/"/&quot;/g;
	return qq{$attr="$val"};
}

sub goto_buf {
	my ($name, $buf) = @_;
	if(! $name) {
		$$buf = '';
		return;
	}
	while($$buf =~ s!  .+?
							(
								(?:
								\[ label \s+ (?:name \s* = \s* ["']?)?	|
								<[^>]+? \s+ mv.label \s*=\s*["']?		|
								<[^>]+? \s+
									mv \s*=\s*["']? label
									[^>]*? \s+ mv.name\s*=\s*["']?		|
								<[^>]+? \s+ mv \s*=\s*["']? label  \s+  |
								)
								(\w+)
							|
								</body\s*>
							)
					!$1!ixs )
	{
			last if $name eq $2;
	}
	return;
}

sub html_start {
    my($self, $tag, $attr, $attrseq, $origtext, $end_tag) = @_;
	$tag =~ tr/-/_/;   # canonical
	$end_tag = lc $end_tag;
	my $buf = \$self->{_buf};
#::logGlobal("tag=$tag end_tag=$end_tag buf length " . length($$buf)) if $Monitor{$tag};
#::logGlobal("attributes: ", %{$attr}) if $Monitor{$tag};
	my($tmpbuf);
    # $attr is reference to a HASH, $attrseq is reference to an ARRAY
	my($return_html);

	unless (defined $Routine{$tag}) {
		if(defined $Alias{$tag}) {
			my ($rest, $text);
			($tag, $rest) = split /\s+/, $Alias{$tag}, 2;
			_find_tag (\$rest, $attr, $attrseq);
		}
		elsif ($tag eq 'urldecode') {
			$attr->{urldecode} = 1;
			$return_html = $origtext;
			$return_html =~ s/\s+.*//s;
		}
		else {
			$self->{OUT} .= $origtext;
			return 1;
		}
	}

	if(defined $InvalidateCache{$tag} and !$attr->{cache}) {
		$self->{INVALID} = 1;
	}

	$attr->{interpolate} = $self->{INTERPOLATE}
		unless defined $attr->{interpolate};

	my $trib;
	foreach $trib (@$attrseq) {
		# Attribute aliases
		if(defined $attrAlias{$tag} and $attrAlias{$tag}{$trib}) {
			my $new = $attrAlias{$tag}{$trib} ;
			$attr->{$new} = delete $attr->{$trib};
			$trib = $new;
		}
		elsif (0 and defined $Alias{$trib}) {
			my $new = $Alias{$trib} ;
			$attr->{$new} = delete $attr->{$trib};
			$trib = $new;
		}
		# Parse tags within tags, only works if the [ is the
		# first character.
		$attr->{$trib} =~ s/%([A-Fa-f0-9]{2})/chr(hex($1))/eg if $attr->{urldecode};
		next unless $attr->{$trib} =~ /\[\w+[-\w]*\s*[\000-\377]*\]/;

		my $p = new Vend::Parse;
		$p->parse($attr->{$trib});
		$attr->{$trib} = $p->{OUT};
		$self->{INVALID} += $p->{INVALID};
	}

	if($tag eq 'urldecode') {
		$self->{OUT} .= build_html_tag($return_html, $attr, $attrseq);
		return 1;
	}

	$attr->{'decode'} = 1 unless defined $attr->{'decode'};
	$attr->{'reparse'} = 1 unless defined $attr->{'reparse'};
	$attr->{'true'} = 1;
	$attr->{'false'} = 0;
	$attr->{'undef'} = undef;

	my ($routine,@args);

	if ($attr->{OLD}) {
	# HTML old-style tag
		$attr->{interpolate} = 0 if $hasEndTag{$tag} and $canNest{$tag};
		$attr->{interpolate} = 1 if defined $Interpolate{$tag};
		@args = $attr->{OLD};
		if(defined $PosNumber{$tag} and $PosNumber{$tag} > 1) {
			@args = split /\s+/, $attr->{OLD}, $PosNumber{$tag};
			push(@args, undef) while @args < $PosNumber{$tag};
		}
		$routine =  $PosRoutine{$tag} || $Routine{$tag};
	}
	else {
	# New style tag, HTML or otherwise
		$routine = $Routine{$tag};
		$attr->{interpolate} = 1
			if defined $Interpolate{$tag} and ! defined $attr->{interpolate};
		@args = @{$attr}{ @{ $Order{$tag} } };
		push(@args, $attr) if $addAttr{$tag};
	}

	if($tag =~ /^[gb]o/) {
		if($tag eq 'goto') {
			return 1 if defined $attr->{'if'} and
						(! $attr->{'if'} or $attr->{'if'} =~ /^\s*[\s0]\s*$/); 
			if(! $args[0]) {
				$$buf = '';
				$$Initialized->{_buf} = '';
				$Initialized->{_buf} = '';
				$self->{ABORT} = 1
					if $attr->{abort};
				return ($self->{SEND} = 1);
			}
			goto_buf($args[0], \$Initialized->{_buf});
			$self->{ABORT} = 1;
			return 1;
		}
		elsif($tag eq 'bounce') {
			return 1 if defined $attr->{'if'} and
						(! $attr->{'if'} or $attr->{'if'} =~ /^\s*[\s0]\s*$/); 
			$Vend::StatusLine = '' if ! $Vend::StatusLine;
			$Vend::StatusLine .= <<EOF;
Status: 302 moved
Location: $attr->{href}
EOF
			$$buf = '';
			$Initialized->{_buf} = '';
			return ($self->{SEND} = 1);
		}
	}

#::logGlobal("tag=$tag end_tag=$end_tag attributes:\n" . Vend::Util::uneval($attr)) if$Monitor{$tag};

	my $prefix = '';
	my $midfix = '';
	my $postfix = '';
	my @out;

	if($insertHTML{$end_tag}
		and ! $attr->{noinsert}
		and $tag =~ /^($insertHTML{$end_tag})$/) {
		$origtext =~ s/>\s*$//;
		@out = Text::ParseWords::shellwords($origtext);
		shift @out;
		@out = grep $_ !~ /^[Mm][Vv][=.]/, @out
			unless $attr->{showmv};
		if (defined $replaceAttr{$tag}
			and $replaceAttr{$tag}->{$end_tag}
			and	! $attr->{noreplace})
		{
			my $t = $replaceAttr{$tag}->{$end_tag};
			@out = grep $_ !~ /^($t)\b/i, @out;
			unless(defined $implicitHTML{$t}) {
				$out[0] .= qq{ \U$t="};
				$out[1] = defined $out[1] ? qq{" } . $out[1] : '"';
			}
			else { $midfix = ' ' }
		}
		else {
			$out[0] = " " . $out[0] . " "
				if $out[0];
		}
		if (@out) {
			$out[$#out] .= '>';
		}
		else {
			@out = '>';
		}
#::logGlobal("inserted " . join "|", @out);
	}

	if($hasEndTag{$tag}) {
		my $rowfix;
		# Handle embedded tags, but only if interpolate is 
		# defined (always if using old tags)
		if (defined $replaceHTML{$end_tag}
			and $tag =~ /^($replaceHTML{$end_tag})$/
			and ! $attr->{noreplace} )
		{
			$origtext = '';
			$tmpbuf = find_html_end($end_tag, $buf);
			$tmpbuf =~ s:</$end_tag\s*>::;
			HTML::Entities::decode($tmpbuf) if $attr->{decode};
			$tmpbuf =~ tr/\240/ /;
		}
		else {
			@out = Text::ParseWords::shellwords($origtext);
			($attr->{showmv} and
					@out = map {s/^[Mm][Vv]\./mv-/} @out)
				or @out = grep ! /^[Mm][Vv][=.]/, @out;
			$out[$#out] =~ s/([^>\s])\s*$/$1>/;
			$origtext = join " ", @out;

			if (defined $lookaheadHTML{$tag} and ! $attr->{nolook}) {
				$tmpbuf = $origtext . find_html_end($end_tag, $buf);
				while($$buf =~ s~^\s*(<([A-Za-z][-A-Z.a-z0-9]*)[^>]*)\s+
								[Mm][Vv]\s*=\s*
								(['"]) \[?
									($lookaheadHTML{$tag})\b(.*?)
								\]?\3~~ix ) 
				{
					my $orig = $1;
					my $enclose = $4;
					my $adder = $5;
					my $end = lc $2;
					$tmpbuf .= "[$enclose$adder]"	.  $orig	.
								find_html_end($end, $buf)	.
								"[/$enclose]";
				}
			}
			# GACK!!! No table row attributes in some editors????
			elsif (defined $rowfixHTML{$end_tag}
				and $tag =~ /^($rowfixHTML{$end_tag})$/
				and $attr->{rowfix} )
			{
				$rowfix = 1;
				$tmpbuf = '<tr>' . $origtext . find_html_end('tr', $buf);
#::logGlobal("Tmpbuf: $tmpbuf");
			}
			elsif (defined $insideHTML{$end_tag}
					and ! $attr->{noinside}
					and $tag =~ /^($insideHTML{$end_tag})$/i) {
				$prefix = $origtext;
				$tmpbuf = find_html_end($end_tag, $buf);
				$tmpbuf =~ s:</$end_tag\s*>::;
				$postfix = "</$end_tag>";
				HTML::Entities::decode($tmpbuf) if $attr->{'decode'};
				$tmpbuf =~ tr/\240/ / if $attr->{'decode'};
			}
			else {
				$tmpbuf = $origtext . find_html_end($end_tag, $buf);
			}
		}

		$tmpbuf =~ s/%([A-Fa-f0-9]{2})/chr(hex($1))/eg if $attr->{urldecode};

		if ($attr->{interpolate}) {
			my $p = new Vend::Parse;
			$p->parse($tmpbuf);
			$tmpbuf =  $p->{OUT};
		}

		$tmpbuf =  $attr->{prepend} . $tmpbuf if defined $attr->{prepend};
		$tmpbuf .= $attr->{append}            if defined $attr->{append};

		if (! $attr->{reparse}) {
			$self->{OUT} .= $prefix . &{$routine}(@args,$tmpbuf) . $postfix;
		}
		elsif (! defined $rowfix) {
			$$buf = $prefix . &{$routine}(@args,$tmpbuf) . $postfix . $$buf
		}
		else {
			$tmpbuf = &{$routine}(@args,$tmpbuf);
			$tmpbuf =~ s|<tr>||i;
			$$buf = $prefix . $tmpbuf . $postfix . $$buf;
		}


	}
	else {
		if(! @out and $attr->{prepend} or $attr->{append}) {
			my @tmp;
			@tmp = Text::ParseWords::shellwords($origtext);
			shift @tmp;
			@tmp = grep $_ !~ /^[Mm][Vv][=.]/, @tmp
				unless $attr->{showmv};
			$postfix = $attr->{prepend} ? "<\U$end_tag " . join(" ", @tmp) : '';
			$prefix = $attr->{append} ? "<\U$end_tag " . join(" ", @tmp) : '';
		}
		if(! $attr->{interpolate}) {
			if(@out) {
				$self->{OUT} .= "<\U$end_tag ";
				if 		($out[0] =~ / > \s*$ /x ) { }   # End of tag, do nothing
				elsif	($out[0] =~ / ^[^"]*"$/x ) {     # End of tag
					$self->{OUT} .= shift(@out);
				}
				else {
					unshift(@out, '');
				}
			}
			$self->{OUT} .= $prefix . &$routine( @args ) . $midfix;
			$self->{OUT} .= join(" ", @out) . $postfix;
		}
		else {
			if(@out) {
				$$buf = "<\U$end_tag " . &$routine( @args ) . $midfix . join(" ", @out) . $$buf;
			}
			else {
				$$buf = $prefix . &$routine( @args ) . $postfix . $$buf;
			}
		}
	}

	$self->{SEND} = $attr->{'send'} || undef;
#::logGlobal("Returning from $tag");
	return 1;

}

sub start {
	return html_start(@_) if $_[0]->{HTML};
    my($self, $tag, $attr, $attrseq, $origtext) = @_;
	$tag =~ tr/-/_/;   # canonical
	my $buf = \$self->{_buf};
#::logGlobal("tag=$tag buf length " . length($$buf));
#::logGlobal("tag=$tag Interp='$Interpolate{$tag}' attributes:\n" . Vend::Util::uneval($attr)) if$Monitor{$tag};
	my($tmpbuf);
    # $attr is reference to a HASH, $attrseq is reference to an ARRAY
	unless (defined $Routine{$tag}) {
		if(defined $Alias{$tag}) {
			my ($rest, $text);
			($tag, $rest) = split /\s+/, $Alias{$tag}, 2;
			$text = _find_tag (\$rest, $attr, $attrseq);
			$text = " $text" if $text;
			$origtext =~ s:^(\[\S+):[$tag$text:;
		}
		else {
			$self->{OUT} .= $origtext;
			return 1;
		}
	}

	if(defined $InvalidateCache{$tag} and !$attr->{cache}) {
		$self->{INVALID} = 1;
	}

	$attr->{interpolate} = $self->{INTERPOLATE}
		unless $Interpolate{$tag} or defined $attr->{interpolate};

	my $trib;
	foreach $trib (@$attrseq) {
		# Attribute aliases
		if(defined $attrAlias{$tag} and $attrAlias{$tag}{$trib}) {
			my $new = $attrAlias{$tag}{$trib} ;
			$attr->{$new} = delete $attr->{$trib};
			$trib = $new;
		}
		# Parse tags within tags, only works if the [ is the
		# first character.
		next unless $attr->{$trib} =~ /\[\w+[-\w]*\s*[\000-\377]*\]/;

		my $p = new Vend::Parse;
		$p->parse($attr->{$trib});
		$attr->{$trib} = $p->{OUT};
		$self->{INVALID} += $p->{INVALID};
	}

	$attr->{'reparse'} = 1 unless defined $Gobble{$tag} || defined $attr->{'reparse'};
	$attr->{'true'} = 1;
	$attr->{'false'} = 0;
	$attr->{'undef'} = undef;

	my ($routine,@args);

	# Check for old-style positional tag
	if(!@$attrseq and $origtext =~ s/\[[-\w]+\s+//i) {
			$origtext =~ s/\]$//;
			$attr->{interpolate} = 0 if $hasEndTag{$tag} and $canNest{$tag};
			$attr->{interpolate} = 1 if defined $Interpolate{$tag};
			@args = ($origtext);
			if(defined $PosNumber{$tag} and $PosNumber{$tag} > 1) {
				@args = split /\s+/, $origtext, $PosNumber{$tag};
				push(@args, undef) while @args < $PosNumber{$tag};
			}
			$routine =  $PosRoutine{$tag} || $Routine{$tag};
	}
	else {
		$routine = $Routine{$tag};
		$attr->{interpolate} = 1
			if  defined $Interpolate{$tag} and ! defined $attr->{interpolate};
		@args = @{$attr}{ @{ $Order{$tag} } };
		push(@args, $attr) if $addAttr{$tag};
	}

#::logGlobal("Interpolate value now='$attr->{interpolate}'") if$Monitor{$tag};


#::logGlobal(<<EOF) if $Monitor{$tag};
#tag=$tag
#routine=$routine
#has_end=$hasEndTag{$tag}
#attributes=@args
#interpolate=$attr->{interpolate}
#EOF

	if($tag =~ /^[gb]o/) {
		if($tag eq 'goto') {
			return 1 if defined $attr->{'if'} and
						(! $attr->{'if'} or $attr->{'if'} =~ /^\s*[\s0]\s*$/); 
			if(! $args[0]) {
				$$buf = '';
				$Initialized->{_buf} = '';
				$self->{ABORT} = 1
					if $attr->{abort};
				return ($self->{SEND} = 1);
			}
			goto_buf($args[0], \$Initialized->{_buf});
			$self->{ABORT} = 1;
			$self->{SEND} = 1 if ! $Initialized->{_buf};
			return 1;
		}
		elsif($tag eq 'bounce') {
			return 1 if defined $attr->{'if'} and
						(! $attr->{'if'} or $attr->{'if'} =~ /^\s*[\s0]\s*$/); 
			$Vend::StatusLine = '' if ! $Vend::StatusLine;
			$Vend::StatusLine .= <<EOF;
Status: 302 moved
Location: $attr->{href}
EOF
			$$buf = '';
			$Initialized->{_buf} = '';
			$self->{SEND} = 1;
			return 1;
		}
	}

	if($hasEndTag{$tag}) {
		# Handle embedded tags, but only if interpolate is 
		# defined (always if using old tags)
#::logGlobal("look end for $tag, buf=" . length($$buf) );
		$tmpbuf = find_matching_end($tag, $buf);
#::logGlobal("FOUND end for $tag\nBuf " . length($$buf) . ":\n" . $$buf . "\nTmpbuf:\n$tmpbuf\n");
		if ($attr->{interpolate}) {
			my $p = new Vend::Parse;
			$p->parse($tmpbuf);
			$tmpbuf = $p->{ABORT} ? '' : $p->{OUT};
		}
		if($attr->{reparse} ) {
			my $intermediate = &$routine(@args,$tmpbuf);
			$$buf = $intermediate . $$buf;
		}
		else {
			$self->{OUT} .= &{$routine}(@args,$tmpbuf);
		}
	}
	elsif(! $attr->{interpolate}) {
		$self->{OUT} .= &$routine( @args );
	}
	else {
		$$buf = &$routine( @args ) . $$buf;
	}

	$self->{SEND} = $attr->{'send'} || undef;
#::logGlobal("Returning from $tag");
	return 1;
}

sub end
{
    my($self, $tag) = @_;
	my $save = $tag;
	$tag =~ tr/-/_/;   # canonical
	
# DEBUG
#Vend::Util::logDebug
#("called Vend::Parse::end with $tag\n")
#	if ::debug(0x2);
# END DEBUG

	$self->{OUT} .= $isEndAnchor{$tag} ? '</a>' : "[/$save]";

}

sub find_html_end {
    my($tag, $buf) = @_;
    my $out;
	my $canon;

    my $open  = "<$tag ";
    my $close = "</$tag>";
	($canon = $tag) =~ s/_/[-_]/g;

    $$buf =~ s!<$canon\s!<$tag !ig;
    $$buf =~ s!</$canon\s*>!</$tag>!ig;
    my $first = index($$buf, $close);
    return undef if $first < 0;
    my $int = index($$buf, $open);
    my $pos = 0;
#::logGlobal("find_html_end: tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
    while( $int > -1 and $int < $first) {
        $pos   = $int + 1;
        $first = index($$buf, $close, $first + 1);
        $int   = index($$buf, $open, $pos);
#::logGlobal("find_html_end: tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
    }
#::logGlobal("find_html_end: tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
	return undef if $first < 0;
    $first += length($close);
#::logGlobal("find_html_end (add close): tag=$tag open=$open close=$close $first=$first pos=$pos int=$int");
    $out = substr($$buf, 0, $first);
    substr($$buf, 0, $first) = '';
    return $out;
}

sub find_matching_end {
    my($tag, $buf) = @_;
    my $out;
	my $canon;

    my $open  = "[$tag ";
    my $close = "[/$tag]";
	($canon = $tag) =~ s/_/[-_]/g;

    $$buf =~ s!\[$canon\s![$tag !ig;
    $$buf =~ s!\[/$canon\]![/$tag]!ig;
    my $first = index($$buf, $close);
    if ($first < 0) {
		if($Gobble{$tag}) {
			$out = $$buf;
			$$buf = '';
			return $out;
		}
		return undef;
	}
    my $int = index($$buf, $open);
    my $pos = 0;
    while( $int > -1 and $int < $first) {
        $pos   = $int + 1;
        $first = index($$buf, $close, $first + 1);
        $int   = index($$buf, $open, $pos);
    }
    $out = substr($$buf, 0, $first);
    $first = $first < 0 ? $first : $first + length($close);
    substr($$buf, 0, $first) = '';
    return $out;
}

# Passed some string that might be HTML-style attributes
# or might be positional parameters, does the right thing
sub _find_tag {
	my ($buf, $attrhash, $attrseq) = (@_);
	my $old = 0;
	my $eaten = '';
	my %attr;
	my @attrseq;
	while ($$buf =~ s|^(([a-zA-Z][-a-zA-Z0-9._]*)\s*)||) {
		$eaten .= $1;
		my $attr = lc $2;
		my $val;
		$old = 0;
		# The attribute might take an optional value (first we
		# check for an unquoted value)
		if ($$buf =~ s|(^=\s*([^\"\'\]\s][^\]\s]*)\s*)||) {
			$eaten .= $1;
			$val = $2;
			HTML::Entities::decode($val);
		# or quoted by " or '
		} elsif ($$buf =~ s|(^=\s*([\"\'])(.*?)\2\s*)||s) {
			$eaten .= $1;
			$val = $3;
			HTML::Entities::decode($val);
		# truncated just after the '=' or inside the attribute
		} elsif ($$buf =~ m|^(=\s*)$| or
				 $$buf =~ m|^(=\s*[\"\'].*)|s) {
			$eaten = "$eaten$1";
			last;
		} else {
			# assume attribute with implicit value, which 
			# means in MiniVend no value is set and the
			# eaten value is grown. Note that you should
			# never use an implicit tag when setting up an Alias.
			$old = 1;
		}
		next if $old;
		$attrhash->{$attr} = $val;
		push(@attrseq, $attr);
	}
	unshift(@$attrseq, @attrseq);
	return ($eaten);
}

# checks for implicit tags
# INT is special in that it doesn't get pushed on @attrseq
sub implicit {
	my($self, $tag, $attr) = @_;
# DEBUG
Vend::Util::logDebug
("check tag='$tag' attr='$attr'...")
	if ::debug(0x2);
# END DEBUG
	return ('interpolate', 1, 1) if $attr eq 'int';
	return ($attr, undef) unless defined $Implicit{$tag} and $Implicit{$tag}{$attr};
	my $imp = $Implicit{$tag}{$attr};
	return ($attr, $imp) if $imp =~ s/^$attr=//i;
	return ( $Implicit{$tag}{$attr}, $attr );
}

if (! $Global::VendRoot) {
	tag_reference();
}

1;
__END__
accessories
%%

The C<[accessories ...]> tag allows you to access MiniVend's option
attribute facility in any of several ways.

If passed any of the optional arguments, initiates special processing
of item attributes based on entries in the product database.

MiniVend allows item attributes to be set for each ordered item. This
allows a size, color, or other modifier to be attached to a line
item in the shopping cart. Previous attribute values can be resubmitted
by means of a hidden field on a form.

The C<catalog.cfg> file directive I<UseModifier> is used to set
the name of the modifier or modifiers. For example

    UseModifier        size color

will attach both a size and color attribute to each item code that
is ordered.

B<IMPORTANT NOTE:> You may not use the following names for attributes:

    item  group  quantity  code  mv_ib  mv_mi  mv_si

You can also set it in scratch with the mv_UseModifier
scratch variable -- C<[set mv_UseModifier]size color[/set]> has the
same effect as above. This allows multiple options to be set for
products. Whichever one is in effect at order time will be used.
Be careful, you cannot set it more than once on the same page.
Setting the C<mv_separate_items> or global directive I<SeparateItems>
places each ordered item on a separate line, simplifying attribute
handling. The scratch setting for C<mv_separate_items> has the same
effect.

The modifier value is accessed in the C<[item-list]> loop with the
C<[item-modifier attribute]> tag, and form input fields are placed with the
C<[modifier-name attribute]> tag. This is similar to the way that quantity
is handled.

NOTE: You must be sure that no fields in your forms have digits appended to
their names if the variable is the same name as the attribute name you
select, as the C<[modifier-name size]> variables will be placed in the
user session as the form variables size0, size1, size2, etc.

You can use the C<[loop arg="attribute attribute"]> list to reference
multiple display or selection fields for modifiers (in MiniVend 3.0,
you can have it automatically generated --see below). The modifier value
can then be used to select data from an arbitrary database for attribute
selection and display.

MiniVend 3.0 will automatically generate the above select box
when the C<[accessories <code> size]> or C<[item-accessories size]>
tags are called. They have the syntax:

   [item_accessories attribute*, type*, field*, database*, name*, outboard*]
  
   [accessories code attribute*, type*, field*, database*, name*, outboard*]

=over 4

=item code

Not needed for item-accessories, this is the product code of the item to
reference.
 
=item attribute

The item attribute as specified in the UseModifier configuration
directive. Typical are C<size> or C<color>.

=item type

The action to be taken. One of:

  select          Builds a dropdown <SELECT> menu for the attribute.
                  NOTE: This is the default.
 
  multiple        Builds a multiple dropdown <SELECT> menu for the
                  attribute.  The size is equal to the number of
                  option choices.
                   
  display         Shows the label text for *only the selected option*.
   
  show            Shows the option choices (no labels) for the option.
   
  radio           Builds a radio box group for the item, with spaces
                  separating the elements.
                   
  radio nbsp      Builds a radio box group for the item, with &nbsp;
                  separating the elements.
                   
  radio left n    Builds a radio box group for the item, inside a
                  table, with the checkbox on the left side. If "n"
                  is present and is a digit from 2 to 9, it will align
                  the options in that many columns.
                   
  radio right n   Builds a radio box group for the item, inside a
                  table, with the checkbox on the right side. If "n"
                  is present and is a digit from 2 to 9, it will align
                  the options in that many columns.

   
  check           Builds a checkbox group for the item, with spaces
                  separating the elements.
                   
  check nbsp      Builds a checkbox group for the item, with &nbsp;
                  separating the elements.
                   
  check left n    Builds a checkbox group for the item, inside a
                  table, with the checkbox on the left side. If "n"
                  is present and is a digit from 2 to 9, it will align
                  the options in that many columns.
                   
  check right n   Builds a checkbox group for the item, inside a
                  table, with the checkbox on the right side. If "n"
                  is present and is a digit from 2 to 9, it will align
                  the options in that many columns.

The default is 'select', which builds an HTML select form entry for
the attribute.  Also recognized is 'multiple', which generates a
multiple-selection drop down list, 'show', which shows the list of
possible attributes, and 'display', which shows the label text for the
selected option only.

=item field

The database field name to be used to build the entry (usually a field
in the products database).  Defaults to a field named the same as the
attribute.

=item database

The database to find B<field> in, defaults to the first products file
where the item code is found.

=item name

Name of the form variable to use if a form is being built. Defaults to
mv_order_B<attribute> -- i.e.  if the attribute is B<size>, the form
variable will be named B<mv_order_size>.

=item outboard

If calling the item-accessories tag, and you wish to select from an
outboard database, you can pass the key to use to find the accessory
data.

=back

When called with an attribute, the database is consulted and looks for
a comma-separated list of attribute options. They take the form:

    name=Label Text, name=Label Text*

The label text is optional -- if none is given, the B<name> will
be used.

If an asterisk is the last character of the label text, the item is
the default selection. If no default is specified, the first will be
the default. An example:

    [item_accessories color]

This will search the product database for a field named "color". If
an entry "beige=Almond, gold=Harvest Gold, White*, green=Avocado" is found,
a select box like this will be built:

    <SELECT NAME="mv_order_color">
    <OPTION VALUE="beige">Almond
    <OPTION VALUE="gold">Harvest Gold
    <OPTION SELECTED>White
    <OPTION VALUE="green">Avocado
    </SELECT>

In combination with the C<mv_order_item> and C<mv_order_quantity> variables
this can be used to allow entry of an attribute at time of order.

If used in an item list, and the user has changed the value, the generated
select box will automatically retain the current value the user has selected.

The value can then be displayed with C<[item-modifier size]> on the
order report, order receipt, or any other page containing an
C<[item-list]>. 


When called with an attribute, the database is consulted and looks for
a comma-separated list of attribute options. They take the form:

    name=Label Text, name=Label Text*

The label text is optional -- if none is given, the B<name> will
be used.

If an asterisk is the last character of the label text, the item is
the default selection. If no default is specified, the first will be
the default. An example:

    [accessories TK112 color]

This will search the product database for a field named "color". If
an entry "beige=Almond, gold=Harvest Gold, White*, green=Avocado" is found,
a select box like this will be built:

    <SELECT NAME="mv_order_color">
    <OPTION VALUE="beige">Almond
    <OPTION VALUE="gold">Harvest Gold
    <OPTION SELECTED>White
    <OPTION VALUE="green">Avocado
    </SELECT>

In combination with the I<mv_order_item> and I<mv_order_quantity> variables
this can be used to allow entry of an attribute at time of order.

=over 4

=item EMULATING WITH LOOP

Below is a fragment from a shopping basket display form which 
shows a selectable size with "sticky" setting. Note that this
would always be contained within the C<[item_list]> C<[/item-list]>
pair.

    <SELECT NAME="[modifier-name size]">
    <OPTION  [selected [modifier-name size] S]> S
    <OPTION  [selected [modifier-name size] M]> M
    <OPTION  [selected [modifier-name size] L]> L
    <OPTION [selected [modifier-name size] XL]> XL
    </SELECT>

It could just as easily be done with a radio button group combined
with the C<[checked ...]> tag.

The above is essentially the same as would be output with the
[item-accessories size] tag if the product database field C<size>
contained the value C<S, M, L, XL>. (The [item-accessories size] tag
is much more efficient.)

=item DEPRECATED BEHAVIOR

If not given one of the optional arguments, expands into the value of
the accessories database entry for the product identified by I<code>
as found in the products database.

=back

%%%
area
%%

Named call example:

    <A HREF="[area href=scan arg="
                                     se=Impressionists
                                     sf=category
                                "
                            ]">Impressionists</A>

Positional call example:

    <A HREF="[area ord/basket]">Check basket</A>

HTML example:

    <A MV="area dir/page" HREF="dir/page.html">

Produces the URL to call a MiniVend page, without the surrounding
A HREF notation. This can be used to get control of your HREF items,
perhaps to place an ALT string or a Javascript construct.

It was originally named C<area> because it also can be used in a
client-side image map, and has an alias of C<href>. The two links below
are identical in operation:

   <A HREF="[area href=catalog]" ALT="Main catalog page">Catalog Home</A>
   <A HREF="[href href=catalog]" ALT="Main catalog page">Catalog Home</A>

The optional I<arg> is used just as in the I<page> tag.

The optional C<form> argument allows you to encode a form in the link.

        <A HREF="[area form="
                mv_order_item=99-102
                mv_order_size=L
                mv_order_quantity=1
                mv_separate_items=1
                mv_todo=refresh"
        ]"> Order t-shirt in Large size </A>

The two form values I<mv_session_id> and I<mv_arg> are automatically added
when appropriate. (I<mv_arg> is the C<arg> parameter for the tag.)

If the parameter C<href> is not supplied, I<process> is used, causing
normal MiniVend form processing.

This would generate a form that ordered item number 99-102 on
a separate line (C<mv_separate_items> being set), with size C<L>,
in quantity 2. Since the page is not set, you will go to the default
shopping cart page -- equally you could set C<mv_orderpage=yourpage>
to go to C<yourpage>.

You must have TolerateGet set (which is the default) and 
all normal MiniVend form caveats apply -- you must have an action,
you must supply a page if you don't want to go to the default,
etc.

You can theoretically submit any form with this, though none of the
included values can have newlines or trailing whitespace. If you want
to do something like that you will have to write a UserTag.

%%%
areatarget
%%

Inserts a Vend URL in a format to provide a targeted reference for a
client-side imagemap. You set up the <AREA> tag with:

      <AREA COORDS="220,0,270,20" HREF="[areatarget page frame]">

If frames are enabled, this will expand to:

      <AREA COORDS="220,0,270,20"
         HREF="http://machine.company.com/vlink/page?ErTxVV8l;;38" TARGET="frame">

If frames are I<not> enabled, this will expand to:

      <AREA COORDS="220,0,270,20"
         HREF="http://machine.company.com/vlink/page?ErTxVV8l;;38">

B<IMPORTANT NOTE:> This tag is DEPRECATED and may disappear in future
versions of MiniVend. Don't use it!

%%%
body
%%

Selects from the predefined color schemes and/or backgrounds set with
C<Mv_LinkColor>, C<Mv_BgColor>, etc., and just becomes a <BODY> tag
if none are defined. The C<extra> parameter is always appended. See
I<CONTROLLING PAGE APPEARANCE>.

This tag is mildly deprecated in that it will not be further enhanced;
It should remain in some form through future versions of MiniVend.

%%%
buttonbar
%%

Selects from the predefined buttonbars, and is stripped if it
doesn't exist. See I<CONTROLLING PAGE APPEARANCE>. This is somewhat 
superceded by Variable and [include filename].

B<IMPORTANT NOTE:> This tag is DEPRECATED and may disappear in future
versions of MiniVend. Don't use it!

%%%
calc
%%

syntax: [calc] EXPRESSION [/calc]

Starts a region where the arguments are calculated according to normal
arithmetic symbols. For instance:

    [calc] 2 + 2 [/calc]

will display:

    4

The [calc] tag is really the same as the [perl] tag, except
that it doesn't accept arguments, is more efficient to parse, and
is interpolated at a higher precedence.

TIP: The [calc] tag will remember variable values inside one page, so
you can do the equivalent of a memory store and memory recall for a loop.

ASP NOTE: There is almost no reason to use this tag in a [perl] or ASP section.

%%%
cart
%%

Sets the name of the current shopping cart for display of shipping, price,
total, subtotal, and nitems tags. (The C<shipping> tag doesn't use the cart.)
If you wish to use a different price for the cart, all of the above except
[shipping] will reflect the normal price field.

%%%
checked
%%

You can provide a "memory" for drop-down menus, radio buttons, and
checkboxes with the [checked] and [selected] tags.

    <INPUT TYPE=radio NAME=foo
            VALUE=on [checked name=foo value=on default=1]>
    <INPUT TYPE=radio NAME=foo
            VALUE=off [checked name=foo value=off]>

This will output CHECKED if the variable C<var_name> is equal to
C<value>. Not case sensitive.

The C<default> parameter, if true (non-zero and non-blank), will cause
the box to be checked if the variable has never been defined.

Note that CHECKBOX items will never submit their value if not checked,
so the box will not be reset. You must do something like:

    <INPUT TYPE=checkbox NAME=foo
            VALUE=1 [checked name=foo value=1 default=1]>
    [value name=foo set=""]

%%%
comment
%%

syntax: [comment] code [/comment]

Comments out MiniVend tags (and anything else) from a page. The contents
are not displayed unless DisplayComments is set in minivend.cfg.

%%%
currency
%%

When passed a value of a single number, formats it according to the
currency specification. For instance:

    [currency]4[/currency]

will display:

    4.00

Uses the I<Locale> and I<PriceCommas> settings as appropriate, and can
contain a [calc] region. If the optional "convert" parameter is set,
it will convert the value according to PriceDivide> for the current
locale. If Locale is set to C<fr_FR>, and F<PriceDivide> for C<fr_FR>
is 0.167, the following sequence

    [currency convert=1] [calc] 500.00 + 1000.00 [/calc] [/currency]

will cause the number 8.982,04 to be displayed.

%%%
data
%%

Returns the value of the field in a database table, or from the C<session>
namespace. If the optional B<value> is supplied, the entry will be
changed to that value.  If the option increment* is present, the field
will be atomically incremented with the value in B<value>. Use negative
numbers in C<value> to decrement.

If a DBM-based database is to be modified, it must be flagged writable
on the page calling the write tag. Use [tag flag write]products[/tag]
to mark the C<products> database writable, for example.
B<This must be done before any access to that table.>

In addition, the C<[data ...]> tag can access a number of elements in
the MiniVend session database:

    accesses           Accesses within the last 30 seconds
    arg                The argument passed in a [page ...] or [area ...] tag
    browser            The user browser string
    cybercash_error    Error from last CyberCash operation
    cybercash_result   Hash of results from CyberCash (access with usertag)
    host               MiniVend's idea of the host (modified by DomainTail)
    last_error         The last error from the error logging
    last_url           The current MiniVend path_info
    logged_in          Whether the user is logged in (add-on UserDB feature)
    pageCount          Number of unique URLs generated
    prev_url           The previous path_info
    referer            HTTP_REFERER string
    ship_message       The last error messages from shipping
    source             Source of original entry to MiniVend
    time               Time (seconds since Jan 1, 1970) of last access
    user               The REMOTE_USER string
    username           User name logged in as (UserDB feature)

NOTE: Databases will hide session values, so don't name a database "session".
or you won't be able to use the [data ...] tag to read them. Case is
sensitive, so in a pinch you could call the database "Session", but it
would be better not to.

%%%
default
%%

Returns the value of the user form variable C<variable> if it is non-empty.
Otherwise returns C<default>, which is the string "default" if there is no
default supplied. Got that?

%%%
description
%%

Expands into the description of the product identified by code as found in the
products database. This is the value of the database field that corresponds to
the C<catalog.cfg> directive C<DescriptionField>. If there is more than one
products file defined, they will be searched in order unless constrained by the
optional argument B<base>.

%%%
discount
%%

Product discounts can be set upon display of any page. The discounts
apply only to the customer receiving them, and are of one of three types:

    1. A discount for one particular item code (code/key is the item-code)
    2. A discount applying to all item codes (code/key is ALL_ITEMS)
    3. A discount applied after all items are totaled
       (code/key is ENTIRE_ORDER)

The discounts are specified via a formula. The formula is scanned for
the variables $q and $s, which are substituted for with the item
I<quantity> and I<subtotal> respectively. In the case of the item and
all items discount, the formula must evaluate to a new subtotal for all
items I<of that code> that are ordered. The discount for the entire
order is applied to the entire order, and would normally be a monetary
amount to subtract or a flat percentage discount.

Discounts are applied to the effective price of the product, including
any quantity discounts.

To apply a straight 20% discount to all items:

    [discount ALL_ITEMS] $s * .8 [/discount]

or with named attributes:

    [discount code=ALL_ITEMS] $s * .8 [/discount]

To take 25% off of only item 00-342:

    [discount 00-342] $s * .75 [/discount]

To subtract $5.00 from the customer's order:

    [discount ENTIRE_ORDER] $s - 5 [/discount]

To reset a discount, set it to the empty string: 

    [discount ALL_ITEMS][/discount]

Perl code can be used to apply the discounts. Here is an example of a
discount for item code 00-343 which prices the I<second> one ordered at
1 cent:

    [discount 00-343]
    return $s if $q == 1;
    my $p = $s/$q;
    my $t = ($q - 1) * $p;
    $t .= 0.01;
    return $t;
    [/discount]

If you want to display the discount amount, use the [item-discount] tag.

    [item-list]
    Discount for [item-code]: [item-discount]
    [/item-list]

Finally, if you want to display the discounted subtotal in a way that
doesn't correspond to a standard MiniVend tag, you can use the [calc] tag:

    [item-list]
    Discounted subtotal for [item-code]: [currency][calc]
                                            [item-price noformat] * [item-quantity]
                                            [/calc][/currency]
    [/item-list]

%%%
field
%%

HTML example: <PARAM MV=field MV.COL=column MV.ROW=key>

Expands into the value of the field I<name> for the product
identified by I<code> as found by searching the products database.
It will return the first entry found in the series of I<Product Files>.
the products database. If you want to constrain it to a particular
database, use the [data base name code] tag.

Note that if you only have one ProductFile C<products>, which is the default,
C<[field column key]> is the same as C<[data products column key]>.

%%%
file
%%

Inserts the contents of the named file. The file should normally
be relative to the catalog directory -- file names beginning with
/ or .. are not allowed if the MiniVend server administrator
has set I<NoAbsolute> to C<Yes>.

The optional C<type> parameter will do an appropriate ASCII translation
on the file before it is sent.

%%%
fly_list
%%

Defines an area in a random page which performs the flypage lookup
function, implementing the tags below.

   [fly-list]
    (contents of flypage.html)
   [/fly-list]

If you place the above around the contents of the demo flypage, 
in a file named C<flypage2.html>, it will make these two calls
display identical pages:

    [page 00-0011] One way to display the Mona Lisa [/page]
    [page flypage2 00-0011] Another way to display the Mona Lisa [/page]

%%%
framebase
%%

Outputs a <BASE FRAME="name"> tag only if MiniVend is in frames mode.
It should be used within the HTML <HEAD> section.

=head2 frames_off

Turns off the frames processing option. This can be used to disable
frames, perhaps as a clickable option for users. It is persistent for
the entire session, or until counteracted with a [frames_on] tag.

B<IMPORTANT NOTE:> This tag is DEPRECATED and may disappear in future
versions of MiniVend. Don't use it!

IMPORTANT NOTE:  This doesn't turn of frames in your browser! If
you let a TARGET tag escape, it will probably cause a new window
to be opened, or other types of anomalous operation.

=head2 frames_on

Turns on the frames processing option, which is disabled by default.
The proper way to use this is to put it ONLY in the first page which
is loaded by frame-based browsers, as part of the initial frame load.
It is persistent for the entire session, or until counteracted with a
[frames_off] tag.

B<IMPORTANT NOTE:> This tag is DEPRECATED and may disappear in future
versions of MiniVend. Don't use it!

%%%
if
%%

Named call example: [if type="type" term="field" op="op" compare="compare"]

Positional call example: [if type field op compare]

negated: [if type="!type" term="field" op="op" compare="compare"]

Positional call example: [if !type field op compare]

Allows conditional building of HTML based on the setting of various MiniVend
session and database values. The general form is:

    [if type term op compare]
    [then]
                                If true, this is printed on the document.
                                The [then] [/then] is optional in most
                                cases. If ! is prepended to the type
                                setting, the sense is reversed and
                                this will be output for a false condition.
    [/then]
    [elsif type term op compare]
                                Optional, tested when if fails
    [/elsif] 
    [else]
                                Optional, printed when all above fail
    [/else]
    [/if]

The C<[if]> tag can also have some variants:

    [if explicit][condition] CODE [/condition]
                Displayed if valid Perl CODE returns a true value.
    [/if]

You can do some Perl-style regular expressions:

    [if value name =~ /^mike/]
                                This is the if with Mike.
    [elsif value name =~ /^sally/]
                                This is an elsif with Sally.
    [/elsif]
    [elsif value name =~ /^pat/]
                                This is an elsif with Pat.
    [/elsif]
    [else]
                                This is the else, no name I know.
    [/else]
    [/if]

While the new tag syntax works for C<[if ...]>, it is more convenient
to use the old in most cases.  It will work fine with both parsers.
The only exception is if you are planning on doing a test on the 
results of another tag sequence:
    
    [if value name =~ /[value b_name]/]
        Shipping name matches billing name.
    [/if]

Oops!  This will not work with the new parser. You must do instead

    [compat]
    [if value name =~ /[value b_name]/]
        Shipping name matches billing name.
    [/if]
    [/compat]

or

    [if type=value term=name op="=~" compare="/[value b_name]/"]
        Shipping name matches billing name.
    [/if]

The latter has the advantage of working with any tag:

    [if type=value term=high_water op="<" compare="[shipping]"]
        Shipping cost is too high, charter a truck.
    [/if]

If you wish to do AND and OR operations, you will have to use 
C<[if explicit]>. This allows complex testing and parsing of
values.

There are many test targets available:

=over 4

=item config Directive

The MiniVend configuration variables. These are set
by the directives in your MiniVend configuration file (or
the defaults).

    [if config CreditCardAuto]
    Auto credit card validation is enabled.
    [/if]

=item data  database::field::key

The MiniVend databases. Retrieves a field in the database and
returns true or false based on the value.

    [if data products::size::99-102]
    There is size information.
    [else]
    No size information.
    [/else]
    [/if]

    [if data products::size::99-102 =~ /small/i]
    There is a small size available.
    [else]
    No small size available.
    [/else]
    [/if]

=item discount

Checks to see if a discount is present for an item.

    [if discount 99-102]
    Item is discounted.
    [/if]

=item explicit

A test for an explicit value. If perl code is placed between
a [condition] [/condition] tag pair, it will be used to make
the comparison. Arguments can be passed to import data from
user space, just as with the [perl] tag.

    [if explicit]
    [condition]
        $country = '[value country]';
        return 1 if $country =~ /u\.?s\.?a?/i;
        return 0;
    [/condition]
    You have indicated a US address.
    [else]
    You have indicated a non-US address. 
    [/else]
    [/if]

This example is a bit contrived, as the same thing could be
accomplished with [if value country =~ /u\.?s\.?a?/i], but
you will run into many situations where it is useful.

This will work for I<Variable> values:

    [if type=explicit compare="__MYVAR__"] .. [/if]

=item file

Tests for existence of a file. Useful for placing image
tags only if the image is present.

    [if file /home/user/www/images/[item-code].gif]
    <IMG SRC="[item-code].gif">
    [/if]

The C<file> test requires that the I<SafeUntrap> directive contains
C<ftfile> (which is the default).

=item items

The MiniVend shopping carts. If not specified, the cart
used is the main cart. Usually used as a litmus test to
see if anything is in the cart, for example:

  [if items]You have items in your shopping cart.[/if]
  
  [if items layaway]You have items on layaway.[/if]

=item ordered

Order status of individual items in the MiniVend shopping
carts. If not specified, the cart used is the main cart.
The following items refer to a part number of 99-102.

  [if ordered 99-102] ... [/if]
    Checks the status of an item on order, true if item
    99-102 is in the main cart.

  [if ordered 99-102 layaway] ... [/if]
    Checks the status of an item on order, true if item
    99-102 is in the layaway cart.

  [if ordered 99-102 main size] ... [/if]
    Checks the status of an item on order in the main cart,
    true if it has a size attribute.

  [if ordered 99-102 main size =~ /large/i] ... [/if]
    Checks the status of an item on order in the main cart,
    true if it has a size attribute containing 'large'.
    THE CART NAME IS REQUIRED IN THE OLD SYNTAX. The new
    syntax for that one would be:

    [if type=ordered term="99-102" compare="size =~ /large/i"]

    To make sure it is exactly large, you could use:

    [if ordered 99-102 main size eq 'large'] ... [/if]

  [if ordered 99-102 main lines] ... [/if]
      Special case -- counts the lines that the item code is
      present on. (Only useful, of course, when mv_separate_items
      or SeparateItems is defined.)

=item scratch

The MiniVend scratchpad variables, which can be set
with the [set name]value[/set] element. 

    [if scratch mv_separate_items]
    Ordered items will be placed on a separate line.
    [else]
    Ordered items will be placed on the same line.
    [/else]
    [/if]

=item session

The MiniVend session variables. Of particular interest
are I<login>, I<frames>, I<secure>, and I<browser>.

=item validcc

A special case, takes the form [if validcc no type exp_date].
Evaluates to true if the supplied credit card number, type
of card, and expiration date pass a validity test. Does
a LUHN-10 calculation to weed out typos or phony 
card numbers.

=item value

The MiniVend user variables, typically set in search,
control, or order forms. Variables beginning with C<mv_>
are MiniVend special values, and should be tested/used
with caution.

=back

The I<field> term is the specifier for that area. For example, [if session
frames] would return true if the C<frames> session parameter was set.

As an example, consider buttonbars for frame-based setups. It would be
nice to display a different buttonbar (with no frame targets) for sessions
that are not using frames:

    [if session frames]
        [buttonbar 1]
    [else]
        [buttonbar 2]
    [/else]
    [/if]

Another example might be the when search matches are displayed. If
you use the string '[value mv_match_count] titles found', it will display
a plural for only one match. Use:

    [if value mv_match_count != 1]
        [value mv_match_count] matches found.
    [else]
        Only one match was found.
    [/else]
    [/if]

The I<op> term is the compare operation to be used. Compare operations are
as in Perl:

    ==  numeric equivalence
    eq  string equivalence
    >   numeric greater-than
    gt  string greater-than
    <   numeric less-than
    lt  string less-than
    !=  numeric non-equivalence
    ne  string equivalence

Any simple perl test can be used, including some limited regex matching.
More complex tests are best done with C<[if explicit]>.

=over 4

=item [then] text [/then]

This is optional if you are not nesting if conditions, as the text
immediately following the [if ..] tag is used as the conditionally
substituted text. If nesting [if ...] tags you should use a [then][/then]
on any outside conditions to ensure proper interpolation.

=item [elsif type field op* compare*]

named attributes: [elsif type="type" term="field" op="op" compare="compare"]

Additional conditions for test, applied if the initial C<[if ..]> test
fails.

=item [else] text [/else]

The optional else-text for an if or if_field conditional.

=item [condition] text [/condition]

Only used with the [if explicit] tag. Allows an arbitrary expression
B<in Perl> to be placed inside, with its return value interpreted as
the result of the test. If arguments are added to [if explicit args],
those will be passed as arguments are in the I<[perl]> construct.

=back

%%%
import
%%

Named attributes:

    [import table=table_name
            type=(TAB|PIPE|CSV|%%|LINE)
            continue=(NOTES|UNIX|DITTO)
            separator=c]

Import one or more records into a database. The C<type> is any
of the valid MiniVend delimiter types, with the default being defined
by the setting of I<Delimiter>. The table must already be a defined
MiniVend database table; it cannot be created on the fly. (If you need
that, it is time to use SQL.)

The C<type> of C<LINE> and C<continue> setting of C<NOTES> is particularly
useful, for it allows you to name your fields and not have to remember
the order in which they appear in the database. The following two imports
are identical in effect:

    [import table=orders]
    code: [value mv_order_number]
    shipping_mode: [shipping-description]
    status: pending
    [/import]
  
    [import table=orders]
    shipping_mode: [shipping-description]
    status: pending
    code: [value mv_order_number]
    [/import]

The C<code> or key must always be present, and is always named C<code>.

If you do not use C<NOTES> mode, you must import the fields in the
same order as they appear in the ASCII source file.

The C<[import ....] TEXT [/import]> region may contain multiple records.
If using C<NOTES> mode, you must use a separator, which by default is
a form-feed character (^L).

%%%
include
%%

Same as C<[file name]> except interpolates for all MiniVend tags
and variables.

%%%
item_accessories
%%

MiniVend allows item attributes to be set for each ordered item. This
allows a size, color, or other modifier to be attached to a common
part number. If multiple attributes are set, then they should be
separated by commas. Previous attribute values can be saved by means
of a hidden field on a form, and multiple attributes for each item
can be I<stacked> on top of each other.

The configuration file directive I<UseModifier> is used to set
the name of the modifier or modifiers. For example

    UseModifier        size,color

will attach both a size and color attribute to each item code that
is ordered.

B<IMPORTANT NOTE:> You may not use the following names for attributes:

    item  group  quantity  code  mv_ib  mv_mi  mv_si

You can also set it in scratch with the mv_UseModifier
scratch variable -- [set mv_UseModifier]size color[/set] has the
same effect as above. This allows multiple options to be set for
products. Whichever one is in effect at order time will be used.
Be careful, you cannot set it more than once on the same page.
Setting the I<mv_separate_items> or global directive I<SeparateItems>
places each ordered item on a separate line, simplifying attribute
handling. The scratch setting for C<mv_separate_items> has the same
effect.

The modifier value is accessed in the [item-list] loop with the
[item-modifier attribute] tag, and form input fields are placed with the
[modifier-name attribute] tag. This is similar to the way that quantity
is handled, except that attributes can be "stacked" by setting multiple
values in an input form.

You cannot define a modifier name of I<code> or I<quantity>, as they
are already used. You must be sure that no fields in your forms
have digits appended to their names if the variable is the same name
as the attribute name you select, as the [modifier-name size] variables
will be placed in the user session as the form variables size0, size1,
size2, etc. 

You can use the [loop item,item,item] list to reference multiple display
or selection fields for modifiers (in MiniVend 3.0, you can have it
automatically generated --see below). The modifier value can then be
used to select data from an arbitrary database for attribute selection
and display.

Below is a fragment from a shopping basket display form which 
shows a selectable size with "sticky" setting. Note that this
would always be contained within the [item_list] [/item-list]
pair.

    <SELECT NAME="[modifier-name size]">
    <OPTION  [selected [modifier-name size] S]> S
    <OPTION  [selected [modifier-name size] M]> M
    <OPTION  [selected [modifier-name size] L]> L
    <OPTION [selected [modifier-name size] XL]> XL
    </SELECT>

It could just as easily be done with a radio button group combined
with the [checked ...] tag.

MiniVend 3.0 will automatically generate the above select box
when the [accessories <code> size] or [item-accessories size]
tags are called. They have the syntax:

   [item_accessories attribute*, type*, field*, database*, name*, outboard*]
  
   [accessories code attribute*, type*, field*, database*, name*, outboard*]

=over 4

=item code

Not needed for item-accessories, this is the product code of the item to
reference.
 
=item attribute

The item attribute as specified in the UseModifier configuration
directive. Typical are C<size> or C<color>.

=item type

The action to be taken. One of:

  select          Builds a dropdown <SELECT> menu for the attribute.
                  NOTE: This is the default.
 
  multiple        Builds a multiple dropdown <SELECT> menu for the
                  attribute.  The size is equal to the number of
                  option choices.
                   
  display         Shows the label text for *only the selected option*.
   
  show            Shows the option choices (no labels) for the option.
   
  radio           Builds a radio box group for the item, with spaces
                  separating the elements.
                   
  radio nbsp      Builds a radio box group for the item, with &nbsp;
                  separating the elements.
                   
  radio left n    Builds a radio box group for the item, inside a
                  table, with the checkbox on the left side. If "n"
                  is present and is a digit from 2 to 9, it will align
                  the options in that many columns.
                   
  radio right n   Builds a radio box group for the item, inside a
                  table, with the checkbox on the right side. If "n"
                  is present and is a digit from 2 to 9, it will align
                  the options in that many columns.

   
  check           Builds a checkbox group for the item, with spaces
                  separating the elements.
                   
  check nbsp      Builds a checkbox group for the item, with &nbsp;
                  separating the elements.
                   
  check left n    Builds a checkbox group for the item, inside a
                  table, with the checkbox on the left side. If "n"
                  is present and is a digit from 2 to 9, it will align
                  the options in that many columns.
                   
  check right n   Builds a checkbox group for the item, inside a
                  table, with the checkbox on the right side. If "n"
                  is present and is a digit from 2 to 9, it will align
                  the options in that many columns.

The default is 'select', which builds an HTML select form entry for
the attribute.  Also recognized is 'multiple', which generates a
multiple-selection drop down list, 'show', which shows the list of
possible attributes, and 'display', which shows the label text for the
selected option only.

=item field

The database field name to be used to build the entry (usually a field
in the products database).  Defaults to a field named the same as the
attribute.

=item database

The database to find B<field> in, defaults to the first products file
where the item code is found.

=item name

Name of the form variable to use if a form is being built. Defaults to
mv_order_B<attribute> -- i.e.  if the attribute is B<size>, the form
variable will be named B<mv_order_size>.

=item outboard

If calling the item-accessories tag, and you wish to select from an
outboard database, you can pass the key to use to find the accessory
data.

=back

When called with an attribute, the database is consulted and looks for
a comma-separated list of attribute options. They take the form:

    name=Label Text, name=Label Text*

The label text is optional -- if none is given, the B<name> will
be used.

If an asterisk is the last character of the label text, the item is
the default selection. If no default is specified, the first will be
the default. An example:

    [item_accessories color]

This will search the product database for a field named "color". If
an entry "beige=Almond, gold=Harvest Gold, White*, green=Avocado" is found,
a select box like this will be built:

    <SELECT NAME="mv_order_color">
    <OPTION VALUE="beige">Almond
    <OPTION VALUE="gold">Harvest Gold
    <OPTION SELECTED>White
    <OPTION VALUE="green">Avocado
    </SELECT>

In combination with the I<mv_order_item> and I<mv_order_quantity> variables
this can be used to allow entry of an attribute at time of order.

If used in an item list, and the user has changed the value, the generated
select box will automatically retain the current value the user has selected.

The value can then be displayed with [item-modifier size] on the
order report, order receipt, or any other page containing an
[item_list]. 

%%%
item_list
%%

Within any page, the [item_list cart*] element shows a list of all the
items ordered by the customer so far. It works by repeating the source
between [item_list] and [/item_list] once for each item ordered.

NOTE: The special tags that reference item within the list are not normal
MiniVend tags, do not take named attributes, and cannot be contained in
an HTML tag (other than to substitute for one of its values or provide
a conditional container). They are interpreted only inside their
corresponding list container. Normal MiniVend tags can be interspersed,
though they will be interpreted I<after> all of the list-specific tags.

Between the item_list markers the following elements will return
information for the current item:

=over 4

=item [if-data table column]

If the database field C<column> in table I<table> is non-blank, the
following text up to the [/if_data] tag is substituted. This can be
used to substitute IMG or other tags only if the corresponding source
item is present. Also accepts a [else]else text[/else] pair for the
opposite condition.

=item [if-data ! table column]

Reverses sense for [if-data].

=item [/if-data]

Terminates an [if_data table column] element.

=item [if-field fieldname]

If the products database field I<fieldname> is non-blank, the following
text up to the [/if_field] tag is substituted. If you have more than
one products database table (see I<ProductFiles>), it will check
them in order until a matching key is found. This can be used to
substitute IMG or other tags only if the corresponding source
item is present. Also accepts a [else]else text[/else] pair
for the opposite condition.

=item [if-field ! fieldname]

Reverses sense for [if-field].

=item [/if-field]

Terminates an [if_field fieldname] element.

=item [item-accessories attribute*, type*, field*, database*, name*]

Evaluates to the value of the Accessories database entry for the item.
If passed any of the optional arguments, initiates special processing
of item attributes based on entries in the product database.

=item [item-code]

Evaluates to the product code for the current item.

=item [item-data database fieldname]

Evaluates to the field name I<fieldname> in the arbitrary database
table I<database>, for the current item.

=item [item-description]

Evaluates to the product description (from the products file)
for the current item.

=item [item-field fieldname]

Evaluates to the field name I<fieldname> in the products database,
for the current item. If the item is not found in the first of the
I<ProductFiles>, all will be searched in sequence.

=item [item-increment]

Evaluates to the number of the item in the match list. Used
for numbering search matches or order items in the list.

=item [item-last]tags[/item-last]

Evaluates the output of the MiniVend tags encased inside the tags,
and if it evaluates to a numerical non-zero number (i.e. 1, 23, or -1)
then the list iteration will terminate. If the evaluated number is
B<negative>, then the item itself will be skipped. If the evaluated
number is B<positive>, then the item itself will be shown but will be
last on the list.

      [item-last][calc]
        return -1 if '[item-field weight]' eq '';
        return 1 if '[item-field weight]' < 1;
        return 0;
        [/calc][/item-last]

If this is contained in your C<[item-list]> (or C<[search-list]> or
flypage) and the weight field is empty, then a numerical C<-1> will
be output from the [calc][/calc] tags; the list will end and the item
will B<not> be shown. If the product's weight field is less than 1,
a numerical 1 is output.  The item will be shown, but will be the last
item shown. (If it is an C<[item-list]>, any price for the item will
still be added to the subtotal.) NOTE: no HTML style.

=item [item-modifier attribute]

Evaluates to the modifier value of C<attribute> for the current item.

=item [item-next]tags[/item_next]

Evaluates the output of the MiniVend tags encased inside, and
if it evaluates to a numerical non-zero number (i.e. 1, 23, or -1) then
the item will be skipped with no output. Example:

      [item-next][calc][item-field weight] < 1[/calc][/item-next]

If this is contained in your C<[item-list]> (or C<[search-list]> or flypage)
and the product's weight field is less than 1, then a numerical C<1> will
be output from the [calc][/calc] operation. The item will not be shown. (If
it is an C<[item-list]>, any price for the item will still be added to the
subtotal.)

=item [item-price n* noformat*]

Evaluates to the price for quantity C<n> (from the products file)
of the current item, with currency formatting. If the optional "noformat"
is set, then currency formatting will not be applied.

=item [discount-price n* noformat*]

Evaluates to the discount price for quantity C<n> (from the products file)
of the current item, with currency formatting. If the optional "noformat"
is set, then currency formatting will not be applied. Returns regular
price if not discounted.

=item [item-discount]

Returns the difference between the regular price and the discounted price.

=item [item-quantity]

Evaluates to the quantity ordered for the current item.

=item [item-subtotal]

Evaluates to the subtotal (quantity * price) for the current item.
Quantity price breaks are taken into account.

=item [modifier-name attribute]

Evaluates to the name to give an input box in which the
customer can specify the modifier to the ordered item.

=item [quantity-name]

Evaluates to the name to give an input box in which the
customer can enter the quantity to order.

=back

%%%
lookup
%%

This is essentially same as the following:

    [if value name]
    [then][value name][/then]
    [else][data database column row][/else]
    [/if]

%%%
loop
%%

HTML example: 

    <TABLE><TR MV="loop 1 2 3"><TD>[loop-code]</TD></TR></TABLE>

Returns a string consisting of the LIST, repeated for every item in a
comma-separated or space-separated list. Operates in the same fashion
as the [item-list] tag, except for order-item-specific values. Intended
to pull multiple attributes from an item modifier -- but can be useful
for other things, like building a pre-ordained product list on a page.

Loop lists can be nested reliably in MiniVend 3.06 by using the 
with="tag" parameter. New syntax:

    [loop arg="A B C"]
        [loop with="-a" arg="[loop-code]1 [loop-code]2 [loop-code]3"]
            [loop with="-b" arg="X Y Z"]
                [loop-code-a]-[loop-code-b]
            [/loop]
        [/loop]
    [/loop]

An example in the old syntax:

    [compat]
    [loop 1 2 3]   
        [loop-a 1 2 3 ]
        [loop-b 1 2 3]
            [loop-code].[loop-code-a].[loop-code-b]
        [/loop-b]
        [/loop-a]
    [/loop]
    [/compat]

All loop items in the inner loop-a loop need to have the C<with> value
appended, i.e. C<[loop-field-a name]>, C<[loop-price-a]>, etc. Nesting
is arbitrarily large, though it will be slow for many levels.

You can do an arbitrary search with the search="args" parameter, just
as in a one-click search:

    [loop search="se=Americana/sf=category"]
        [loop-code] [loop-field title]
    [/loop]

The above will show all items with a category containing the whole world
"Americana", and will work the same in both old and new syntax.

=over 4

=item [if-loop-data table field] IF [else] ELSE [/else][/if-loop-field]

Outputs the IF if the C<field> in C<table> is non-empty, and the ELSE (if any)
otherwise.

=item [if-loop-field field] IF [else] ELSE [/else][/if-loop-field]

Outputs the B<IF> if the C<field> in the C<products> table is non-empty,
and the B<ELSE> (if any) otherwise.

=item [loop-accessories]

Evaluates to the value of the Accessories database entry for
the item.

=item [loop-change marker]

Same as I<[on_change]> but within loop lists.

=item [loop-code]

Evaluates to the product code for the current item.

=item [loop-data database fieldname]

Evaluates to the field name I<fieldname> in the arbitrary database
table I<database>, for the current item.

=item [loop-description]

Evaluates to the product description (from the products file)
for the current item.

=item [loop-field fieldname]

Evaluates to the field name I<fieldname> in the database,  for
the current item.

=item [loop-increment]

Evaluates to the number of the item in the list. Used
for numbering items in the list.

=item [loop-last]tags[/loop-last]

Evaluates the output of the MiniVend tags encased inside,
and if it evaluates to a numerical non-zero number (i.e. 1, 23, or -1)
then the loop iteration will terminate. If the evaluated number is
B<negative>, then the item itself will be skipped. If the evaluated
number is B<positive>, then the item itself will be shown but will be
last on the list.

      [loop-last][calc]
        return -1 if '[loop-field weight]' eq '';
        return 1 if '[loop-field weight]' < 1;
        return 0;
        [/calc][/loop-last]

If this is contained in your C<[loop list]> and the weight field is empty,
then a numerical C<-1> will be output from the [calc][/calc] tags; the
list will end and the item will B<not> be shown. If the product's weight
field is less than 1, a numerical 1 is output.  The item will be shown,
but will be the last item shown.

=item [loop-next]tags[/loop-next]

Evaluates the output of the MiniVend tags encased inside, and
if it evaluates to a numerical non-zero number (i.e. 1, 23, or -1) then
the loop will be skipped with no output. Example:

      [loop-next][calc][loop-field weight] < 1[/calc][/loop-next]

If this is contained in your C<[loop list]> and the product's weight
field is less than 1, then a numerical C<1> will be output from the
[calc][/calc] operation. The item will not be shown.

=item [loop-price n* noformat*]

Evaluates to the price for optional quantity n (from the products file)
of the current item, with currency formatting. If the optional "noformat"
is set, then currency formatting will not be applied.

=back

%%%
nitems
%%

Expands into the total number of items ordered so far. Takes an
optional cart name as a parameter.

%%%
order
%%

Expands into a hypertext link which will include the specified
code in the list of products to order and display the order page. B<code>
should be a product code listed in one of the "products" databases. The
optional argument B<cart/page> selects the shopping cart the item will be
placed in (begin with / to use the default cart C<main>) and the order page
that will display the order. The optional argument B<database> constrains
the order to a particular products file -- if not specified, all databases
defined as products files will be searched in sequence for the item.

Example: 

  Order a [order TK112]Toaster[/order] today.

%%%
page
%%

Insert a hyperlink to the specified catalog page pg. For
example, [page shirts] will expand into <
a href="http://machine.company.com/cgi-bin/vlink/shirts?WehUkATn;;1">. The
catalog page displayed will come from "shirts.html" in the
pages directory.

The additional argument will be passed to MiniVend and placed in the
{arg} session parameter. This allows programming of a conditional page
display based on where the link came from. The argument is then available
with the tag [data session arg], or the embedded Perl session variable
$Safe{'session'}->{arg}. If you set the catalog configuration option
I<NewEscape>, which is the default, then spaces and some other characters
will be escaped with the %NN HTTP-style notation and unescaped when the
argument is read back into the session.

A bit of magic occurs if MiniVend has built a static plain HTML page
for the target page. Instead of generating a normal MiniVend-parsed
page reference, a static page reference will be inserted if the user
has accepted and sent back a cookie with the session ID.

The optional C<form> argument allows you to encode a form in the link.

        [page form="
                mv_order_item=99-102
                mv_order_size=L
                mv_order_quantity=1
                mv_separate_items=1
                mv_todo=refresh"] Order t-shirt in Large size </A>

The two form values I<mv_session_id> and I<mv_arg> are automatically added
when appropriate. (I<mv_arg> is the C<arg> parameter for the tag.)

If the parameter C<href> is not supplied, I<process> is used, causing
normal MiniVend form processing. If the C<href> points to an http://
link no MiniVend URL processing will be done, but the mv_session_id

This would generate a form that ordered item number 99-102 on
a separate line (C<mv_separate_items> being set), with size C<L>,
in quantity 2. Since the page is not set, you will go to the default
shopping cart page -- equally you could set C<mv_orderpage=yourpage>
to go to C<yourpage>.

You must have TolerateGet set (which is the default) and
all normal MiniVend form caveats apply -- you must have an action,
you must supply a page if you don't want to go to the default,
etc.

You can theoretically submit any form with this, though none of the
included values can have newlines or trailing whitespace. If you want
to do something like that you will have to write a UserTag.

%%%
pagetarget
%%

Same as the page element above, except it specifies an output frame to
target if frames are turned on. The name B<is> case-sensitive, and if
it doesn't exist a new window will be popped up. This is the same as
the [page ...] tag if frames are not activated.
For example, [pagetarget shirts main] will expand into a link like <a
href="http://machine.company.com/cgi-bin/vlink/shirts?WehUkATn;;1" TARGET="main">. The
catalog page displayed will come from C<shirts.html> in the
pages directory, and be output to the C<main> frame. Be careful,
frame names are case-sensitive.

MiniVend allows you to pass a search in a URL. Just specify the
search with the special page reference C<scan>. Here is an
example:

     [page scan
            se=Impressionists
            sf=category]
        Impressionist Paintings
     [/page]

Here is the same thing from a home page (assuming /cgi-bin/vlink is
the CGI path for MiniVend's vlink):

     <A HREF="/cgi-bin/vlink/scan/se=Impressionists/sf=category">
        Impressionist Paintings
     </A>

The two-letter abbreviations are mapped with these letters:

  DL  mv_raw_dict_look
  MM  mv_more_matches
  SE  mv_raw_searchspec
  ac  mv_all_chars
  bd  mv_base_directory
  bs  mv_begin_string
  co  mv_coordinate
  cs  mv_case
  de  mv_dict_end
  df  mv_dict_fold
  di  mv_dict_limit
  dl  mv_dict_look
  do  mv_dict_order
  dp  mv_delay_page
  dr  mv_record_delim
  em  mv_exact_match
  er  mv_spelling_errors
  fi  mv_search_file
  fm  mv_first_match
  fn  mv_field_names
  hs  mv_head_skip
  id  mv_index_delim
  lr  mv_line_return
  ml  mv_matchlimit
  mm  mv_max_matches
  mp  mv_profile
  ms  mv_min_string
  ne  mv_negate
  nu  mv_numeric
  op  mv_column_op
  os  mv_orsearch
  ra  mv_return_all
  rd  mv_return_delim
  rf  mv_return_fields
  rg  mv_range_alpha
  rl  mv_range_look
  rm  mv_range_min
  rn  mv_return_file_name
  rs  mv_return_spec
  rx  mv_range_max
  se  mv_searchspec
  sf  mv_search_field
  sp  mv_search_page
  sq  mv_sql_query
  st  mv_searchtype
  su  mv_substring_match
  tc  mv_sort_command
  tf  mv_sort_field
  to  mv_sort_option
  ty  mv_sort_crippled

They can be treated just the same as form variables on the
page, except that they can't contain spaces, '/' in a file
name, or quote marks. These characters can be used
in URL hex encoding, i.e. %20 is a space, %2F is a
C</>, etc. -- C<&sp;> or C<&#32;> will not be recognized.
If you use one of the methods below to escape these "unsafe"
characters, you won't have to worry about this.

Beginning in MiniVend 3.08, you may specify a one-click search in
three different ways. The first is as used in previous versions, with
the scan URL being specified completely as the page name.  The second
two use the "argument" parameter to the C<[page ...]> or C<[area ...]>
tags to specify the search (an argument to a scan is never valid anyway).

=over 4

=item Original

If you wish to do an OR search on the fields category and artist
for the strings "Surreal" and "Gogh", while matching substrings,
you would do:

 [page scan se=Surreal/se=Gogh/os=yes/su=yes/sf=artist/sf=category]
    Van Gogh -- compare to surrealists
 [/page]

In this method of specification, to replace a / (slash) in a file name
(for the sp, bd, or fi parameter) you must use the shorthand of ::,
i.e. sp=results::standard. (This may not work for some browsers, so you
should probably either put the page in the main pages directory or define
the page in a search profile.)

=item Ampersand

You can substitute & for / in the specification and be able to use / and
quotes and spaces in the specification.

 [page scan se="Van Gogh"&sp=lists/surreal&os=yes&su=yes&sf=artist&sf=category]
    Van Gogh -- compare to surrealists
 [/page]

Any "unsafe" characters will be escaped. 

=item Multi-line

You can specify parameters one to a line, as well. 

    [page scan
        se="Van Gogh"
        sp=lists/surreal
        os=yes
        su=yes
        sf=artist
        sf=category
    ] Van Gogh -- compare to surrealists [/page]

Any "unsafe" characters will be escaped. You may not search for trailing
spaces in this method; it is allowed in the other notations.

=back

New syntax and old syntax handle the tags the same, though if by some
odd chance you wanted to be able to search for a C<]> (right square bracket)
you would need to use new syntax.

The optional I<arg> is used just as in the I<page> tag.

=head2 [/page]

Expands into </a>. Used with the page element, such as:

  [page shirts]Our shirt collection[/page]. 

TIP: A small efficiency boost in large pages is to just use the </A>
tag.

%%%
perl
%%

HTML example:

    <PRE mv=perl mv.arg="values browser">
        $name = $Safe{'values'}{'name'};
        $name = $Safe{'browser'};
        return "Hi, $name! How do you like your $browser?
    </PRE>

Perl code can be directly embedded in MiniVend pages. The code
is specified as [perl arguments*] any_legal_perl_code [/perl]. The
value returned by the code will be inserted on the page.

Using MiniVend variables with embedded Perl capability is not recommended
unless you are thoroughly familiar with Perl 5 references. You can insert
Minivend tags inside the Perl code, though when using the new syntax,
you will need to pass an INTERPOLATE=1 parameter to have tags inside
[perl] and [/perl] interpreted. (In the old syntax, most tags are evaluated
before [perl], though there are exceptions.)

More often you will want to use the tag access routine B<&safe_tag>, which
takes the tag name and any arguments as parameters. This has the advantage
of only performing the operation when the code is executed. (A few tags can't
be used with safe_tag, notably ones accessing a database that has not
previously been accessed on the page.)

Examples:

    # Simple example, old syntax
    [perl]
    $comments = '[value comments]';
    [/perl]

    # New syntax
    # If the item might contain a single quote
    [perl interpolate=1]
    $comments = '[value comments escaped]';
    [/perl]

    # Another method to avoid escape problems
    $comments = q{[value comments]};

    # Works with all, only executed if code is reached
    $comments = safe_tag('value', 'comments');

This allows you to pass user-space variables for most needed
operations. You can pass whole lists of items with constructs
like:

    # Perl ignores the trailing comma
    my(%prices) = ( [item_list]
                    '[item_code]', '[item-price]',
                    [/item_list]);

Even easier is the definition of a subroutine:

    [set Thanks]
    my($name, $number) = @_;
    "Thanks, $name, for your order! The order number is $number.\n";
    [/set]

    # New syntax
    [perl arg=sub interpolate=1]
        Thanks ('[value name escaped]', '[value mv_order_number escaped]')
    [/perl]

    # Old syntax, depends on [value ...] interpolated before [perl]
    [perl sub]
        Thanks ('[value name escaped]', '[value mv_order_number escaped]')
    [/perl]

(The C<escaped> causes any single quotes which might be contained in the
values to be escaped, preventing syntax errors in the case of a name like
"O'Reilly".)

The arguments that can be passed are any to all of:

=over 4

=item browser

The browser string from the users browser, read-only. Referred
to in your code as $Safe{browser}.

=item carts

Gives read-write access to all of the shopping carts. on order. This
is an array of hashes, and includes the product code, quantity, and any
modifiers you have specified.  Referred to in your code as a reference
to the array, $Safe{items} or @{$Safe{items}}.

    # Move contents of 'layaway' cart to main cart
    $Safe{carts}->{main} = $Safe{carts}->{layaway};
    $Safe{carts}->{main} = [];

Careful with this -- you can lose the items on order with improper
code, though syntax errors will be caught before the code is run.

=item cgi

Gives read-only access to the actual variables that were passed
in the current CGI session. This is useful for testing what the
user actually placed on the form, not just what MiniVend placed
in the session. Called with

  # Set if the user had a value for name in the *current* form
  $name = $Safe{'cgi'}->{name};

=item config

Gives read-write access to the configuration of the catalog. USE WITH
EXTREME CAUTION -- many of the variables are references to anonymous
arrays and hashes. You can crash your catalog if you modify the wrong
thing. Referred to in your code as $Safe{config}, a reference to the
hash containing the configuration structure. If you use this, it
is recommended that you refer frequently to the MiniVend source code.

=item discount

Gives read-write access to session discounts, an
anonymous hash. Referred to in your code as $Safe->{discounts}.

=item file

If specified, the anchor text is a file name to read the Perl code from.
This allows code to be maintained in separate files, though you need
to remember that any MiniVend tags contained will generally not be
interpolated (depending on interpolation order and use of the [[any]]
and [post] modifiers). The file name is relative to the MiniVend base
directory unless specified as an absolute path.

=item frames

The true/false value determining whether frames processing is
enabled. Read-only -- you can set the value with [frames-off] or
[frames-on]. Referred to in your code as $Safe{frames}.

=item items

Gives read-only access to the items on order, I<for the current cart>.
This is an array of hashes, and includes the product code, quantity,
and any modifiers you have specified. Referred to in your code as a
reference to the array, $Safe{items} or @{$Safe{items}}.

    # Product code of first item in cart
    $item_code = $Safe{items}->[0]->{code};  

    # Quantity for third item in cart
    $item_code = $Safe{items}->[2]->{quantity};  

    # Color of second item in cart
    $item_code = $Safe{items}->[2]->{color};  

=item scratch

Gives read-write access to the scratch variables, a reference to an
anonymous hash. Referred to in your code as $Safe{scratch}.

=item sub

If specified, the anchor text is a subroutine name and optional
parameters to be passed. The subroutine can be defined in three
ways; as a global subroutine (works for entire server); as a
catalog-wide pre-defined subroutine; or in a scratchpad variable.
All are called with the same syntax -- the arguments are passed
in via the @_ argument array.

B<IMPORTANT NOTE:> Global subroutines are not subject to the stringent
security checking of the I<Safe> module, so almost anything goes
there. The subroutine will be able to modify any variable in MiniVend,
and will be able to write to read and write any file that the MiniVend
daemon has permission to write. Though this gives great power, it should
be used with caution. Careful! They are defined in the main minivend.cfg
file, so should be safe from individual users in a multi-catalog system.

Global subroutines are defined in I<minivend.cfg> with the
I<GlobalSub> directive, or in user catalogs which have been
enabled via I<AllowGlobal>. Global subroutines are much faster
than the others as they are pre-compiled. (Faster still are I<UserTag>
definitions.)

Catalog subroutines are defined in I<catalog.cfg>, with
the I<Sub> directive. They are subject to the stringent I<Safe.pm>
security restrictions that are controlled by I<SafeUntrap>. If you
wish to have default arguments supplied to them, use the I<SubArgs>
directive.

Scratch subroutines are defined in the pages, and are also subject
to F<Safe.pm> checking. See the beginning of this section for an
example of a subroutine definition. There is no "sub name { }" that
surrounds it -- the subroutine is named from the name of the 
scratch variable.

=item values

Gives read-write access to the user variables, including the MiniVend
special variables, an anonymous hash. Referred to in your code as
%{Safe{'values'}} or $Safe{'values'}->{variable}.

    # Read the user's selected shipping mode
    my $shipmode = $Safe{values}->{mv_shipmode};

=back

The code can be as complex as desired, but cannot use any operators
that modify the file system or use "unsafe" operations like "system",
"exec", or backticks. These constraints are enforced with the default
permissions of the standard Perl module I<Safe> -- operations may
be untrapped on a system-wide basis with the I<SafeUntrap> directive.

The result of the tag will be the result of the last expression
evaluated, just as in a subroutine. If there is a syntax error
or other problem with the code, there will be no output.

Here is a simple one which does the equivalent of the classic
hello.pl program:

    [perl] my $tmp = "Hello, world!"; $tmp; [/perl]

Of course you wouldn't need to set the variable -- it is just there
to show the capability.

To echo the user's browser, but within some HTML tags:

    [perl browser]
    my $html = '<H5>';
    $html .= $Safe{'browser'};
    $html .= '</H5>';
    $html;
    [/perl]

To show the user their name, and the current time:

    [perl values]

    my $string = "Hi, " . $Safe{values}->{'name'} ". The time is now ";
    $string .= localtime;
    $string;

    [/perl]

%%%
post
%%

syntax: [post] DELAYED TAGS [/post]

B<NOTE:> This is ignored if using the new syntax.

Selects an area that will not be interpolated until after the rest of
the page is interpolated. If followed by a number, will match a terminating
[/post] tag with the corresponding number.

%%%
price
%%

Expands into the price of the product identified by code as found in
the products database. If there is more than one products file defined,
they will be searched in order unless constrained by the optional
argument B<base>. The optional argument B<quantity> selects an entry
from the quantity price list. To receive a raw number, with no currency
formatting, use the option C<noformat=1>.

MiniVend maintains a price in its database for every product. The price
field is the one required field in the product database -- it is necessary
to build the price routines.

For speed, MiniVend builds the code that is used to determine a product's
price at catalog configuration time. If you choose to change a directive
that affects product pricing you must reconfigure the catalog.

There are several ways that MiniVend can modify the price of a product during 
normal catalog operation. Several of them require that the I<pricing.asc>
file be present, and that you define a pricing database. You do that by
placing the following directive in I<catalog.cfg>:

  Database  pricing pricing.asc 1

Configurable directives and tags with regard to pricing:

=over 4

=item *

Quantity price breaks are configured by means of the I<PriceBreaks> and
I<MixMatch> directives. They require a field named specifically C<price>
in the pricing database. The B<price> field contains a space-separated
list of prices that correspond to the quantity levels defined in the
F<PriceBreaks> directive. If quantity is to be applied to all items in
the shopping cart (as opposed to quantity of just that item) then the
I<MixMatch> directive should be set to B<Yes>.

=item *

Individual line-item prices can be adjusted according to the value of
their attributes. See I<PriceAdjustment> and I<CommonAdjust>. The
pricing database B<must> be defined unless you define the F<CommonAdjust>
behavior.

=item *

Product discounts for specific products, all products, or the entire
order can be configured with the [discount ...] tag. Discounts are applied
on a per-user basis -- you can gate the discount based on membership in a
club or other arbitrary means. See I<Product Discounts>.

=back

For example, if you decided to adjust the price of T-shirt part number
99-102 up 1.00 when the size is extra large and down 1.00 when the size is small,
you would have the following directives defined in <catalog.cfg>:

  Database          pricing pricing.asc 1
  UseModifier       size
  PriceAdjustment   size

To enable the automatic modifier handling of MiniVend 3.0, you would
define a size field in products.asc:

  code    description   price    size
  99-102  T-Shirt       10.00    S=Small, M=Medium, L=Large*, XL=Extra Large

You would place the proper tag within your [item-list] on the shopping-basket
or order page:

    [item-accessories size]

In the pricing.asc database source, you would need:

  code      S       XL
  99-102    -1.00   1.00

As of MiniVend 3.06, if you want to assign a price based on the option,
precede the number with an equals sign:

  code    S       M       L       XL
  99-102  =9.00   =10     =10     =11

IMPORTANT NOTE: Price adjustments occur AFTER quantity price breaks, so
the above would negate anything set with the I<PriceBreaks> directive/option.

Numbers that begin with an equals sign (C<=>) are used as absolute
prices and are I<interpolated for MiniVend tags first>, so you can
use subroutines to set the price. To facilite coordination with the
subroutine, the session variables C<item_code> and C<item_quantity> are
set to the code and quantity of the item being evaluated. They would
be accessed in a global subroutine with C<$Vend::Session->>C<{item_code}>
and C<$Vend::Session->>C<{item_quantity}>.

The pricing information must always come from a database because
of security.

See I<CommonAdjust> for another scheme that makes the same adjustment
for any item having the attribute -- both schemes cannot be used at the
same time. (This is true even if you were to change the value of 
$Vend::Cfg->{CommonAdjust} in a subroutine -- the pricing algorithm
is built at catalog configuration time.)

%%%
random
%%

Selects from the predefined random messages, and is stripped if none
exist. See I<CONTROLLING PAGE APPEARANCE> in the MiniVend documentation.

%%%
rotate
%%

Selects from the predefined rotating banner messages, and is stripped if
none exist. The optional C<ceiling> sets the highest number that will be
selected -- likewise C<floor> sets the lowest. The default is to sequence
through all defined rotating banners. Each user has a separate rotation
pattern, and each floor/ceiling combination has a separate rotation
value.

%%%
row
%%

Formats text in tables. Intended for use in emailed reports or <PRE></PRE> HTML
areas. The parameter I<nn> gives the number of columns to use. Inside the
row tag, [col param=value ...] tags may be used. 

=over 4

=item [col width=nn wrap=yes|no gutter=n align=left|right|input spacing=n]

Sets up a column for use in a [row]. This parameter can only be contained
inside a [row nn] [/row] tag pair. Any number of columns (that fit within
the size of the row) can be defined.

The parameters are:

    width=nn        The column width, I<including the gutter>. Must be
                    supplied, there is no default. A shorthand method
                    is to just supply the number as the I<first> parameter,
                    as in [col 20].
        
    gutter=n        The number of spaces used to separate the column (on
                    the right-hand side) from the next. Default is 2.
        
    spacing=n       The line spacing used for wrapped text. Default is 1,
                    or single-spaced.
        
    wrap=(yes|no)   Determines whether text that is greater in length than
                    the column width will be wrapped to the next line. Default
                    is I<yes>.
        
    align=(L|R|I)   Determines whether text is aligned to the left (the default),
                    the right, or in a way that might display an HTML text
                    input field correctly.

=item [/col]

Terminates the column field.

=back

%%%
salestax
%%

Expands into the sales tax on the subtotal of all the items ordered so
far for the cart, default cart is C<main>. If there is no key field to
derive the proper percentage, such as state or zip code, it is set to
0. If the noformat tag is present and non-zero, the raw number with no
currency formatting will be given.

%%%
scratch
%%

Returns the contents of a scratch variable to the page.

%%%
selected
%%

You can provide a "memory" for drop-down menus, radio buttons, and
checkboxes with the [checked] and [selected] tags.

This will output SELECTED if the variable C<var_name> is equal to
C<value>. If the optional MULTIPLE argument is present, it will
look for any of a variety of values. Not case sensitive.

Here is a drop-down menu that remembers an item-modifier
color selection:

    <SELECT NAME="color">
    <OPTION [selected color blue]> Blue
    <OPTION [selected color green]> Green
    <OPTION [selected color red]> Red
    </SELECT>

Here is the same thing, but for a shopping-basket color
selection

    <SELECT NAME="[modifier-name color]">
    <OPTION [selected [modifier-name color] blue]> Blue
    <OPTION [selected [modifier-name color] green]> Green
    <OPTION [selected [modifier-name color] red]> Red
    </SELECT>

%%%
set
%%

Sets a scratchpad variable to I<value>.

Most of the mv_* variables that are used for search and order conditionals are
in another namespace -- they can be set by means of hidden fields in a
form.

You can set an order profile with:

  [set checkout]
  name=required
  address=required
  [/set]
  <INPUT TYPE=hidden NAME=mv_order_profile VALUE="checkout">

A search profile would be set with:

  [set substring_case]
  mv_substring_match=yes
  mv_case=yes
  [/set]
  <INPUT TYPE=hidden NAME=mv_profile VALUE="substring_case">

%%%
shipping
%%

The shipping cost of the items in the basket via C<mode> -- the default
mode is the shipping mode currently selected in the C<mv_shipmode>
variable. See I<SHIPPING>.

%%%
shipping_description
%%

mandatory: NONE

optional: B<name> is the shipping mode identifier, i.e. C<upsg>.

The text description of B<mode> -- the default is the 
shipping mode currently selected.

%%%
sql
%%

A complete array of arrays, suitable for I<eval> by Perl, can be returned
by this query. This tag pair encloses any valid SQL query, and returns
the results (if any) as a string representing rows and columns, in Perl
array syntax. If placed in an embedded Perl area as:

 [perl]

    my $string =<<'EOF';
 [sql array]select * from arbitrary where code <= '19'[/sql arbitrary]

 EOF
    my $ary = eval $string;
    my $out = '';
    my $i;
    foreach $i (@$ary) {
        $out .= $i->[0];
        $out .= "<BR>";
    }
    $out;

 [/perl]

NOTE: The 'EOF' string terminator must START the line, and not
have trailing characters. DOS users, beware of carriage returns!

=head2 [sql ...]

A complete hash of hashes, suitable for I<eval> by Perl, can be returned
by this query. This tag pair encloses any valid SQL query, and returns
the results (if any) as a string representing rows and columns, in Perl
associative array, or hash, syntax. If placed in an embedded Perl area as:

 [perl]

    my $string =<<'EOF';
 [sql hash]select * from arbitrary where code <= '19'[/sql]

 EOF
    my $hash = eval $string;
    my $out = '';
    my $key;
    foreach $key (keys %$hash) {
        $out .= $key->{field1};
        $out .= "<BR>";
    }
    $out;

 [/perl]

=head2 [sql ...]

This tag returns a set of HTML table rows with B<bold> field names at
the top, followed by each row in a set of table cells. The <TABLE>
and </TABLE> tags are not supplied, so you can set your own border
and shading options. Example:

  <TABLE BORDER=2>
  [sql html]select * from arbitrary where code > '19' order by field2[/sql]
  </TABLE>

=head2 [sql ...]

This tag differs from the rest in that it passes the query enclosed
inside the tag itself. The enclosed text is then evaluated with the
same method as with a loop list, with data items (in columns) iterated
over for the contents of a list. The following snippet will place
a three-column list in an HTML table:

  <TABLE BORDER=2>
  <TR><TH><B>SKU</B></TH><TH><B>Description</B></TH><TH><B>Price</B></TH>
  [sql list
    select * from arbitrary where code > '19' order by field2 ]
  <TR>
    <TD>[page [sql-code]][sql-code]</A></TD>
    <TD>[sql-param 1]</TD>
    <TD>[sql-param 2]</TD>
  </TR>
  [/sql]
  </TABLE>

It uses the same tags as in the [loop_list], except prefixed
with C<sql>. Available are the following, in order of interpolation:

  [sql_param n]        Field n of the returned query (in the row)
  [if_sql_field fld]   Returns enclosed text only product field not empty
  [/if_sql_field]      Terminator for above
  [if_sql_data db fld] Returns enclosed text only if data field not empty
  [/if_sql_field]      Terminator for above
  [sql_increment]      Returns integer count of row
  [sql_code]           The first field of each row returned
  [sql_data db fld]    Database field for [sql_code]
  [sql_description]    Product description for [sql_code]
  [sql_field fld]      Product field for [sql_code]
  [sql_link]           Same as item-link
  [sql_price q*]       Price for [sql_code], optional quantity q

=head2 [sql ...]

A list of keys, or in fact any SQL fields, can be returned as a set of
parameters suitable for passing to a program or list primitive. This tag pair
encloses any valid SQL query, and returns the results (if any) as a series of
space separated fields, enclosed in quotes. This folds the entire return
into a single row, so it may be used as a list of keys.

=head2 [sql ...]

Any arbitrary SQL query can be passed with this method. No return
text will be sent. This might be used for passing an order to an 
order database, perhaps on the order report or receipt page. An
example might be:

 [sql set]
     insert into orders
     values
      ('[value mv_order_number]',
       '[value name escape]',
       '[value address escape]',
       '[value city escape]',
       '[value state escape]',
       '[value zip escape]',
       '[value phone escape]',
       '[item-list]
         Item: [item-code] Quan: [item-quantity] Price: [item-price]
        [/item-list]'
      )
 [/sql orders]

The values entered by the user are escaped, which prevents errors if
quote characters have slipped into their entry.

%%%
subtotal
%%


old: [subtotal cart* noformat*]

mandatory: NONE

optional: cart noformat

Expands into the subtotal cost, exclusive of sales tax, of
all the items ordered so far for the optional C<cart>. If the noformat
tag is present and non-zero, the raw number with no currency formatting
will be given.

%%%
tag
%%

Performs any of a number of operations, based on the presence of C<arg>.
The arguments that may be given are:

=over 4

=item each database

Returns a loop-list with every key in C<database> evaluated
as the [loop-code]. This will return the key and field C<name>
for every record in the C<products> database:

    [tag each products][loop-code]  [loop-field name]<BR>[/tag]

=item export database file* type*

Exports a complete MiniVend database to its text source file (or any
specified file). The integer C<n>, if specified, will select export in
one of the enumerated MiniVend export formats. The following tag will
export the products database to products.txt (or whatever you have
defined its source file as), in the format specified by the
I<Database> directive:

    [tag export products][/tag]

Same thing, except to the file products/new_products.txt:

    [tag export products products/newproducts.txt][/tag]

Same thing, except the export is done with a PIPE delimiter:

    [tag export products products/newproducts.txt 5][/tag]

The file is relative to the catalog directory, and only may be
an absolute path name if I<NoAbsolute> is set to C<No>.

=item flag arg

Sets a MiniVend condition.

The following enables writes on the C<products> and C<sizes> databases
held in MiniVend internal DBM format:

    [tag flag write]products sizes[/tag]

SQL databases are always writable if allowed by the SQL database itself --
in-memory databases will never be written.

The [tag flag build][/tag] combination forces static build of a page, even
if dynamic elements are contained. Similarly, the [tag flag cache][/tag]
forces search or page caching (not usually wise).

=item log dir/file

Logs a message to a file, fully interpolated for MiniVend tags.
The following tag will send every item code and description in the user's
shopping cart to the file logs/transactions.txt:

    [tag log logs/transactions.txt]
    [item_list][item-code]  [item-description]
    [/item_list][/tag]

The file is relative to the catalog directory, and only may be
an absolute path name if I<NoAbsolute> is set to C<No>.

=item mime description_string

Returns a MIME-encapsulated message with the boundary as employed
in the other mime tags, and the C<description_string> used as the 
Content-Description. For example

   [tag mime My Plain Text]Your message here.[/tag]

will return

  Content-Type: TEXT/PLAIN; CHARSET=US-ASCII
  Content-ID: [sequential, lead as in mime boundary]
  Content-Description: My Plain Text
  
  Your message here.

When used in concert with [tag mime boundary], [tag mime header], and
[tag mime id], allows MIME attachments to be included -- typically with
PGP-encrypted credit card numbers. See the demo page ord/report.html
for an example.

=item mime boundary

Returns a MIME message boundary with unique string keyed on
session ID, page count, and time.

=item mime header

Returns a MIME message header with the proper boundary for that
session ID, page count, and time.

=item mime id

Returns a MIME message id with the proper boundary for that
session ID, page count, and time.

=item show_tags

The encased text will not be substituted for with MiniVend tags, 
with < and [ characters changed to C<&>#lt; and C<&>#91; respectively.

    [tag show_tags][value whatever][/tag]

=item time

Formats the current time according to POSIX strftime arguments.
The following is the string for Thursday, April 30, 1997.

    [tag time]%A, %B %d, %Y[/tag]

=item touch 

Touches a database to allow use of the tag_data() routine in 
user-defined subroutines.  If this is not done, the routine
will error out if the database has not previously been accessed
on the page.

    [tag touch products][/tag]

=back

%%%
total_cost
%%

Expands into the total cost of all the items in the current shopping cart,
including sales tax (if any).

%%%
userdb
%%

MiniVend provides a C<[userdb ...]> tag to access the UserDB functions.

 [userdb
        function=function_name
        username="username"*
        password="password"*
        verify="password"*
        oldpass="old password"*
        shipping="fields for shipping save"
        billing="fields for billing save"
        preferences="fields for preferences save"
        force_lower=1
        param1=value*
        param2=value*
        ...
        ]

* Optional

It is normally called in an C<mv_click> or C<mv_check> setting, as in:

    [set Login]
    mv_todo=return
    mv_nextpage=welcome
    [userdb function=login]
    [/set]

    <FORM ACTION="[process-target]" METHOD=POST>
    <INPUT TYPE=hidden NAME=mv_click VALUE=Login>
    Username <INPUT NAME=mv_username SIZE=10>
    Password <INPUT NAME=mv_password SIZE=10>
    </FORM>

There are several global parameters that apply to any use of
the C<userdb> functions. Most importantly, by default the database
table is set to be I<userdb>. If you must use another table name,
then you should include a C<database=table> parameter with any
call to C<userdb>. The global parameters (default in parens):

    database     Sets user database table (userdb)
    show         Show the return value of certain functions
                 or the error message, if any (0)
    force_lower  Force possibly upper-case database fields
                 to lower case session variable names (0)
    billing      Set the billing fields (see Accounts)
    shipping     Set the shipping fields (see Address Book)
    preferences  Set the preferences fields (see Preferences)
    bill_field   Set field name for accounts (accounts)
    addr_field   Set field name for address book (address_book)
    pref_field   Set field name for preferences (preferences)
    cart_field   Set field name for cart storage (carts)
    pass_field   Set field name for password (password)
    time_field   Set field for storing last login time (time)
    expire_field Set field for expiration date (expire_date)
    acl          Set field for simple access control storage (acl)
    file_acl     Set field for file access control storage (file_acl)
    db_acl       Set field for database access control storage (db_acl)

%%%
value
%%

HTML examples:

   <PARAM MV="value name">
   <INPUT TYPE="text" NAME="name" VALUE="[value name]">

Expands into the current value of the customer/form input field named
by field. If C<flag> is present, single quotes will be escaped with a
backslash; this allows you to contain the C<[value ...]> tag within
single quotes. (It is somewhat better to use other quoting methods.)
When the value is returned, any MiniVend tags present in the value will
be escaped. This prevents users from entering MiniVend tags in form values,
which would be a serious security risk.

If the C<set> value is present, the form variable value will be set
to it and the empty string returned. Use this to "uncheck" a checkbox
or set other form variable values to defaults. B<NOTE:> This is only
available in new-style tags, for safety reasons.

%%%
value_extended
%%

Named call example:

   [value-extended 
            name=formfield
            outfile=filename*
            ascii=1*
            yes="Yes"*
            no="No"*
            joiner="char|string"*
            test="isfile|length|defined"*
            index="N|N..N|*"
            file_contents=1*
            elements=1*]

Expands into the current value of the customer/form input field named
by field. If there are multiple elements of that variable, it will return
the value at C<index>; by default all joined together with a space.

If the variable is a file variable coming from a multipart/form-data
file upload, then the contents of that upload can be returned to the 
page or optionally written to the C<outfile>.

=over 4

=item name

The form variable NAME. If no other parameters are present, then the 
value of the variable will be returned. If there are multiple elements,
then by default they will all be returned joined by a space. If C<joiner>
is present, then they will be joined by its value.

In the special case of a file upload, the value returned is the name
of the file as passed for upload.

=item joiner

The character or string that will join the elements of the array. Will
accept string literals such as "\n" or "\r".

=item test

Three tests -- C<isfile> returns true if the variable is a file upload.
C<length> returns the length. C<defined> returns whether the value
has ever been set at all on a form.

=item index

The index of the element to return if not all are wanted. This is
useful especially for pre-setting multiple search variables. If set
to C<*>, will return all (joined by C<joiner>). If a range, such
as C<0 .. 2>, will return multiple elements.

=item file_contents

Returns the contents of a file upload if set to a non-blank, non-zero value.
If the variable is not a file, returns nothing.

=item outfile

Names a file to write the contents of a file upload to. It will not
accept an absolute file name; the name must be relative to the catalog
directory. If you wish to write images or other files that would go to
HTML space, you must use the HTTP server's C<Alias> facilities or 
make a symbolic link.

=item ascii

To do an auto-ASCII translation before writing the C<outfile>, set
the C<ascii> parameter to a non-blank, non-zero value. Default is no
translation.

=item yes

The value that will be returned if a test is true or a file is
written successfully. Defaults to C<1> for tests and the empty
string for uploads.

=item no

The value that will be returned if a test is false or a file write
fails. Defaults to the empty string.

=back

%%%
BEGIN
%%

=head1 MINIVEND TAG REFERENCE

There are dozens of MiniVend pre-defined tag functions. If you don't see
just what you need, you can use C<USER DEFINED TAGS> to create tags just as
powerful as the pre-defined ones.

There are two styles of tag -- HTML/new, and old. Old style is a legacy
from prior versions of MiniVend and is no longer in standard use, but
its positional syntax can I<usually> still be used in New/HTML mode
for convenience.

In the new style, you can specify constructs inside an HTML tag:

    <TABLE MV="if items">
    <TR MV="item-list">
    <TD> [item-code] </TD>
    <TD> [item-description] </TD>
    <TD> [item-price] </TD>
    </TR></TABLE>

The above will loop over any items in the shopping cart, displaying
their part number, description, and price, but only IF there are items
in the cart.

The same thing can be achieved with:

    [if items]
    <TABLE>
    [item-list]
    <TR>
    <TD> [item-code] </TD>
    <TD> [item-description] </TD>
    <TD> [item-price] </TD>
    </TR>
    [/item-list]</TABLE>
    [/if]

To use the new more regular syntax by default, set the I<NewTags>
directive to C<Yes>. The demo catalog is distributed with C<NewTags Yes>
starting at MiniVend 3.07.

In most cases, tags specified in the old positional fashion will work
the same in the new style. The only time you will need to modify them
is when there is some ambiguity as to which parameter is which (usually
due to whitespace), or when you need to use the output of a tag as the
attribute parameter for another tag.

B<TIP:> This will not work in the new style as it did in the old:

    [page scan se=[scratch somevar]]

To get the output of the C<[scratch somevar]> interpreted, you must
place it within a named and quoted attribute:

    [page href=scan arg="se=[scratch somevar]"]

What is done with the results of the tag depends on whether it is a
I<container> or I<standalone> tag. A container tag is one which has
an end tag, i.e. C<[tag] stuff [/tag]>. A standalone tag has no end
tag, as in [area href=somepage].  (Note that [page ...] and [order ..]
are B<not> container tags.)

A container tag will have its output re-parsed for more MiniVend tags
by default. If you wish to inhibit this behavior, you must explicitly
set the attribute B<reparse> to 0. (Prior to MiniVend 3.09, B<reparse>
did not exist.) Note that you will almost always wish the default action.

With some exceptions ([include], [calc], [currency], and [buttonbar ..]
among them) the output of a standalone tag will not be re-interpreted
for MiniVend tag constructs. All tags accept the INTERPOLATE=1 tag
modifier, which causes the interpretation to take place. It is frequent
that you will B<not> want to interpret the contents of a [set variable]
TAGS [/set] pair, as that might contain tags which should only be upon
evaluating an order profile, search profile, or I<mv_click> operation. If
you wish to perform the evaluation at the time a variable is set, you
would use [set name=variable interpolate=1] TAGS [/set].

To use the new syntax only on a particular page, place B<one> C<[new]>
tag in your page. Likewise, to use old syntax when new is the default,
place B<one> C<[old]> tag in the page.

If you have regions of the page which work under the old style and fail
with the new style, you can surround them with [compat] [/compat] tag
pair. This will evaluate that region only with the old style repeated
interpolation.

=head1 TAGS

Each MiniVend tag is show below. Calling information is defined
for the main tag. Certain tags are not standalone, i.e.:

    [if-data ... ]
    [if-field ... ]
    [on-change ... ]
    [item-... ]            --> [item-list], [fly-list], [search-list]
 
    [quantity-name ... ]
    [modifier-name ... ]   --> [item-list]
     
    [on-change ... ]       --> [search-list]
                          
    [if-loop-... ]        
    [loop-... ]            --> [loop]
                          
    [if-sql-... ]         
    [sql-... ]             --> [sql]
                          
    [if-loop-... ]        
    [loop-... ]            --> [loop]
                          
    [if-sql-... ]         
    [sql-... ]             --> [sql]

They are only interpreted within their container and are
defined within the container.


%%%
END
%%

=head1 User-defined Tags

MiniVend 3.04 allows the definition of user tags when using the new
parsed HTML syntax (a [new] tag is on the page).  They will not work
with the old syntax. 3.06 adds the tags on a server-wide basis, defined
in C<minivend.cfg>.

To define a tag that is catalog-specific, place I<UserTag> directives in
your catalog.cfg file. For server-wide tags, define them in minivend.cfg.
Catalog-specific tags take precedence if both are defined -- in fact,
you can override the base MiniVend tag set with them. The directive
takes the form:

   UserTag  tagname  property  value

where C<tagname> is the name of the tag, C<property> is the attribute
(described below), and C<value> is the value of the property for that
tagname.

The user tags can either be based on Perl subroutines or just be
aliases for existing tags. Some quick examples are below.

An alias:

    UserTag product_name Alias     data products title

This will change [product_name 99-102] into [data products title 99-102],
which will output the C<title> database field for product code C<99-102>.
Don't use this with C<[item-data ...]> and C<[item-field ...]>, as they
are parsed separately.  You can do C<[product-name [item-code]]>, though.

A simple subroutine:

    UserTag company_name Routine   sub { "Your company name" }

When you place a [company-name] tag in a MiniVend page, the text 
C<Your company name> will be substituted.

A subroutine with a passed text as an argument:

    UserTag caps   Routine   sub { return "\U@_" }
    UserTag caps   HasEndTag 

The tag [caps]This text should be all upper case[/caps] will become
C<THIS TEXT SHOULD BE ALL UPPER CASE>.

Here is a useful one you might wish to use:

    UserTag quick_table HasEndTag
    UserTag quick_table Interpolate
    UserTag quick_table Order   border
    UserTag quick_table Routine <<EOF
    sub {
        my ($border,$input) = @_;
        $border = " BORDER=$border" if $border;
        my $out = "<TABLE ALIGN=LEFT$border>";
        my @rows = split /\n+/, $input;
        my ($left, $right);
        for(@rows) {
            $out .= '<TR><TD ALIGN=RIGHT VALIGN=TOP>';
            ($left, $right) = split /\s*:\s*/, $_, 2;
            $out .= '<B>' unless $left =~ /</;
            $out .= $left;
            $out .= '</B>' unless $left =~ /</;
            $out .= '</TD><TD VALIGN=TOP>';
            $out .= $right;
            $out .= '</TD></TR>';
            $out .= "\n";
        }
        $out .= '</TABLE>';
    }
    EOF

Called with:

    [quick-table border=2]
    Name: [value name]
    City: [value city][if value state], [value state][/if] [value country]
    [/quick_table]

The properties for UserTag are are:

=over 4

=item Alias

An alias for an existing (or other user-defined) tag. It takes the
form:

    UserTag tagname Alias    tag to insert

An Alias is the only property that does not require a I<Routine>
to process the tag.

=item attrAlias

An alias for an existing attribute for defined tag. It takes the
form:

    UserTag tagname attrAlias   alias attr

As an example, the standard MiniVend C<value> tag takes a named
attribute of C<name> for the variable name, meaning that C<[value name=var]>
will display the value of form field C<var>. If you put this line
in catalog.cfg:

    UserTag value attrAlias   identifier name

then C<[value identifier=var]> will be an equivalent tag.

=item CanNest

Notifies MiniVend that this tag must be checked for nesting.
Only applies to tags that have I<HasEndTag> defined, of course.
NOTE: Your routine must handle the subtleties of nesting, so
don't use this unless you are quite conversant with parsing
routines.  See the routines C<tag_loop_list> and C<tag_if> in 
lib/Vend/Interpolate.pm for an example of a nesting tag.

    UserTag tagname CanNest

=item HasEndTag

Defines an ending [/tag] to encapsulate your text -- the text in
between the beginning C<[tagname]> and ending C<[/tagname]> will
be the last argument sent to the defined subroutine.

    UserTag tagname HasEndTag

=item Implicit

This defines a tag as implicit, meaning it can just be an C<attribute> 
instead of an C<attribute=value> pair. It must be a recognized attribute
in the tag definition, or there will be big problems. Use this with caution!

    UserTag tagname Implicit attribute value

If you want to set a standard include file to a fixed value by default,
but don't want to have to specify C<[include file="/long/path/to/file"]>
every time, you can just put:

    UserTag include Implicit file file=/long/path/to/file

and C<[include file]> will be the equivalent. You can still specify
another value with C[include file="/another/path/to/file"]

=item InsertHTML

This attribute makes HTML tag output be inserted into the containing
tag, in effect adding an attribute=value pair (or pairs).

    UserTag tagname InsertHTML   htmltag  mvtag|mvtag2|mvtagN

In MiniVend's standard tags, among others, the <OPTION ...> tag has the
[selected ..] and [checked ...] tags included with them, so
that you can do:

   <INPUT TYPE=checkbox
        MV="checked mvshipmode upsg" NAME=mv_shipmode> UPS Ground shipping

to expand to this:

   <INPUT TYPE=checkbox CHECKED NAME=mv_shipmode> UPS Ground shipping

Providing, of course, that C<mv_shipmode> B<is> equal to C<upsg>.
If you want to turn off this behavior on a per-tag basis, add the
attribute mv.noinsert=1 to the tag on your page.

=item InsideHTML

To make a container tag be placed B<after> the containing
HTML tag, use the InsideHTML setting.

    UserTag tagname InsideHTML   htmltag  mvtag|mvtag2|mvtagN

In MiniVend's standard tags, the only InsideHTML tag is the
<SELECT> tag when used with I<loop>, which causes this:

   <SELECT MV="loop upsg upsb upsr" NAME=mv_shipmode>
   <OPTION VALUE="[loop-code]"> [shipping-desc [loop-code]]
   </SELECT>

to expand to this:

   <SELECT NAME=mv_shipmode>
   [loop upsg upsb upsr]
   <OPTION VALUE="[loop-code]"> [shipping-desc [loop-code]]
   [/loop]
   </SELECT>

Without the InsideHTML setting, the [loop ...] would have been B<outside>
of the select -- not what you want.  If you want to turn off this
behavior on a per-tag basis, add the attribute mv.noinside=1 to the tag
on your page.

=item Interpolate

The behavior for this attribute depends on whether the tag is a container
(i.e. C<HasEndTag> is defined). If it is not a container, the C<Interpolate>
attribute causes the B<the resulting HTML> from the C<UserTag> will be
re-parsed for more MiniVend tags.  If it is a container, C<Interpolate>
causes the contents of the tag to be parsed B<before> the tag routine
is run.

    UserTag tagname Interpolate

=item InvalidateCache

If this is defined, the presence of the tag on a page will prevent
search cache, page cache, and static builds from operating on the
page.

    UserTag tagname InvalidateCache

It does not override [tag flag build][/tag], though.

=item Order

The optional arguments that can be sent to the tag. This defines not only
the order in which they will be passed to I<Routine>, but the name of
the tags. If encapsulated text is appropriate (I<HasEndTag> is set),
it will be the last argument.

    UserTag tagname Order param1 param2

=item PosRoutine

Identical to the Routine argument -- a subroutine that will be called when
the new syntax is not used for the call, i.e. C<[usertag argument]> instead
of C<[usertag ARG=argument]>. If not defined, I<Routine> is used, and MiniVend
will usually do the right thing.

=item ReplaceAttr

Works in concert with InsertHTML, defining a B<single> attribute which
will be replaced in the insertion operation..

  UserTag tagname ReplaceAttr  htmltag attr

An example is the standard HTML <A HREF=...> tag. If you want to use the
MiniVend tag C<[area pagename]> inside of it, then you would normally
want to replace the HREF attribute. So the equivalent to the following
is defined within MiniVend:

  UserTag  area  ReplaceAttr  a  href

Causing this

    <A MV="area pagename" HREF="a_test_page.html">

to become

    <A HREF="http://yourserver/cgi/simple/pagename?X8sl2lly;;44">
 
when intepreted.
    
=item ReplaceHTML

For HTML-style tag use only. Causes the tag containing the MiniVend tag to
be stripped and the result of the tag to be inserted, for certain tags.
For example:

  UserTag company_name Routine sub { my $l = shift; return "$l: XYZ Company" }
  UserTag company_name HasEndTag
  UserTag company_name ReplaceHTML  b    company_name

<BR> is the HTML tag, and "company_name" is the MiniVend tag.
At that point, the usage:

    <B MV="company-name"> Company </B>  --->>  Company: XYZ Company

Tags not in the list will not be stripped:

    <I MV="company-name"> Company </I> --->>  <I>Company: XYZ Company</I>

=item Routine

An inline subroutine that will be used to process the arguments of the tag. It
must not be named, and will be allowed to access unsafe elements only if
the C<minivend.cfg> parameter I<AllowGlobal> is set for the catalog.

    UserTag tagname Routine  sub { "your perl code here!" }

The routine may use a "here" document for readability:

    UserTag tagname Routine <<EOF
    sub {
        my ($param1, $param2, $text) = @_;
        return "Parameter 1 is $param1, Parameter 2 is $param2";
    }
    EOF

The usual I<here documents> caveats apply.

Parameters defined with the I<Order> property will be sent to the routine
first, followed by any encapsulated text (I<HasEndTag> is set).

=back

Note that the UserTag facility, combined with AllowGlobal, allows the
user to define tags just as powerful as the standard MiniVend tags.
This is not recommended for the novice, though -- keep it simple. 8-)

