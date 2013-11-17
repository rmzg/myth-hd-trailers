#!/usr/bin/perl

use strict;
use warnings;

my $default_menu = $ARGV[0] // '/usr/local/share/mythtv/themes/defaultmenu/mainmenu.xml';

my $tmp_menu = "/tmp/newmenu.xml";
my $trailermenu = "hdmovietrailers.xml";

open my $fh, "<", $default_menu or die "Failed to open [$default_menu] for reading: $!\n";

open my $oh, ">", $tmp_menu or die "Failed to open [$tmp_menu] for writing (used to replace old menu): $!\n";

while( <$fh> ) {
	if( /\Q$trailermenu/i ) {
		# We've already been added to this menu, so bail out.
		close $oh;
		unlink $tmp_menu;
		warn "Skipping install: already been added to $default_menu\n";
		exit;
	}

	# If we've reached the closing menu tag without already finding ourselves, add ourself to the menu as the last item.
	if( m{</mythmenu>}i ) {
		print $oh "\t<button>\n\t\t<type>MOVIETIMES</type>\n\t\t<text>HD Movie Trailers</text>\n\t\t<action>MENU $trailermenu</action>\n\t</button>\n";
	}

	print $oh $_;
}

rename $tmp_menu, $default_menu or die "Failed to replace [$default_menu] with [$tmp_menu]: $!\n";
