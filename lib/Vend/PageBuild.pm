# PageBuild.pm - Interpret MiniVend tags
# 
# $Id: PageBuild.pm,v 2.2 1996/10/30 04:22:28 mike Exp $
#
# Copyright 1996 by Michael J. Heins <mikeh@iac.net>
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

package Vend::PageBuild;
require Exporter;
@ISA = qw(Exporter);

$VERSION = substr(q$Revision: 2.2 $, 10);

@EXPORT = qw ( fake_html );

use Carp;
use strict;
use Vend::Util;
use Vend::Data;
use Vend::Server;
use Vend::ValidCC;
use Vend::Interpolate;
use Text::ParseWords;

my $Level;

my %NoBuild = qw( scan 1 search 1 order 1 process 1 obtain 1);

sub fake_buttonbar {
	my($buttonbar) = shift;
    if (defined $Vend::Cfg->{'ButtonBars'}->[$buttonbar]) {
		return $Vend::Cfg->{'ButtonBars'}->[$buttonbar];
	}
	else {
		return '';
	}
}

sub fake_page {
    my($page) = @_;

    '<a href="' . fakeUrl($page) . '">';
}

# Returns an href which will call up the specified PAGE with TARGET reference.
# If target ends with '__secure', will call the SecureURL

sub fake_pagetarget {
    my($page,$target) = @_;
    my($r);
	unless ($target =~ s/__secure$//i) {
    	$r  = '<a href="' . fakeUrl($page);
	}
	else {
    	$r  = '<a href="' . secure_vendUrl($page);
	}
	warn "pagetarget returning with no frames\n"
		unless $Vend::Session->{'frames'};
    $r .= '" TARGET="' . $target
        if $Vend::Session->{'frames'};
    $r .= '">';
}

# Returns an href which will call up the specified PAGE.

sub fake_area {
    my($area) = @_;

    fakeUrl($area);
}

# Returns an href which will call up the specified PAGE with TARGET reference.

sub fake_areatarget {
    my($area,$target) = @_;
	my($r);
    $r  = fakeUrl($area);
	$r .= '" TARGET="' . $target
		if $Vend::Session->{'frames'};
	$r;
}

# Returns an href to call up the last page visited.

sub fake_last_page {
    fake_page($Vend::Cfg->{Special}->{'catalog'});
}

# Evaluates the [...] tags.

sub fake_html {
    my($html,$level) = @_;
    my($codere) =  '[\w-_#/.]+';
    my($coderex) = '[\w-_:#=/.]+';
	
	$Level = '';
	if($level =~ m:^/:) {
		$Level = $level . '/';
	}
	else {
		while($level =~ s:/::) {
			$Level .= '../';
		}
	}

    $html =~ s:\[buttonbar\s+($codere)\]:fake_buttonbar($1):igoe;

    $html =~ s:\[pagetarget\s+($coderex)\s+($codere)\]:fake_pagetarget($1,$2):igeo;
    $html =~ s:\[/pagetarget\]:</a>:ig;

    $html =~ s:\[area\s+($coderex)\]:fake_area($1):igeo;

    $html =~ s:\[areatarget\s+($coderex)\s+($codere)\]:fake_areatarget($1,$2):igeo;

    $html =~ s:\[page\s+($coderex)\]:fake_page($1):igeo;
    $html =~ s:\[/page\]:</a>:ig;

    $html =~ s:\[last[-_]page\]:fake_last_page():ige;
    $html =~ s:\[/last[-_]page\]:</a>:ig;

	$html;

}

# Returns a fake URL which will give a real HREF for static pages.
# The session ID is blank -- the path is set by $Level

sub fakeUrl
{
    my($path, $arguments) = @_;
	my $name = $path;

	$name =~ s:/.*:: ;
	if(defined $NoBuild{$name}) {
		return vendUrl($path,$arguments);
	}

	if(defined $Vend::Cfg->{'AlwaysSecure'}->{$path}) {
		return secure_vendUrl(@_);
	}


	$arguments = '' unless defined $arguments;

	my $suffix = '';
	my $r = $Level;

	if($path =~ s:(#[^/])+$::) { 
		$suffix = $1;
	}
    $r .= $path . '.html' . $suffix;
}    


1;
