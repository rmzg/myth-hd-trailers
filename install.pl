#!/usr/bin/perl

use strict;
use warnings;

#--------------------------------
# Add our menu item to the defaultmenu/mainmenu
my $default_menu_dir = $ARGV[0] // '/usr/local/share/mythtv/themes/defaultmenu';
my $default_menu = "$default_menu_dir/mainmenu.xml";
my $submenu = "hd-trailers-submenu.xml";

my $tmp_menu = "/tmp/newmainmenu.xml";

open my $fh, "<", $default_menu or die "Failed to open [$default_menu] for reading: $!\n";

open my $oh, ">", $tmp_menu or die "Failed to open [$tmp_menu] for writing (used to replace old menu): $!\n";

while( <$fh> ) {
	if( /\Q$submenu/i ) {
		# We've already been added to this menu, so bail out.
		close $oh;
		unlink $tmp_menu;
		warn "Skipping install: already been added to $default_menu\n";
		exit;
	}

	# If we've reached the closing menu tag without already finding ourselves, add ourself to the menu as the last item.
	if( m{</mythmenu>}i ) {
		print $oh "\t<button>\n\t\t<type>MOVIETIMES</type>\n\t\t<text>HD Movie Trailers</text>\n\t\t<action>MENU $submenu</action>\n\t</button>\n\n";

		print "Added HD Movie Trailers button to $default_menu\n";
	}

	print $oh $_;
}

rename $tmp_menu, $default_menu or die "Failed to replace [$default_menu] with [$tmp_menu]: $!\n";
#--------------------------------


# Install our Trailers Submenu

if( system( "cp", $submenu, $default_menu_dir ) != 0  ) { 
	warn "Failed to copy [$submenu] to [$default_menu_dir]: ", ($? >> 8), "\n";
}

print "Copied $submenu to $default_menu_dir\n";
	
