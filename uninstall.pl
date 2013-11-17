#!/usr/bin/perl

use strict;
use warnings;

#TODO This shares some duplication with install.pl
my $default_menu_dir = $ARGV[0] // '/usr/local/share/mythtv/themes/defaultmenu';
	$default_menu_dir =~ s{/$}{}; #Strip trailing slash, mostly for aesthetics
my $default_menu = "$default_menu_dir/mainmenu.xml";
my $submenu = "hd-trailers-submenu.xml";


#--------------------------------
# Remove the buttom from the $default_menu
my $tmp_menu = "/tmp/newmainmenu.xml";

open my $fh, "<", $default_menu or die "Failed to open [$default_menu] for reading: $!\n";

open my $oh, ">", $tmp_menu or die "Failed to open [$tmp_menu] for writing (used to replace old menu): $!\n";

my @menu_lines = <$fh>;

my( $top_splice_idx, $bottom_splice_idx );
for my $i ( 0 .. $#menu_lines ) {
	local $_ = $menu_lines[$i];

	# If we've found a line (presumably containing <action>MENU $submenu) 
	# We then scan up and down to find the opening and closing <button> elements that surround this line
	# So we can splice them out.
	if( /\Q$submenu/ ) {

		#Scan upwards..
		my $j = $i;
		while( --$j > -1 ) {
			if( $menu_lines[$j] =~ /<button/i ) {
				$top_splice_idx = $j;
				last;
			}
		}

		#Scan downwards..
		my $k = $i;
		while( ++$k < @menu_lines ) {
			if( $menu_lines[$k] =~ m{</button>}i ) {
				$bottom_splice_idx = $k;
				last;
			}
		}

	}
}

# If only one of these is defined we've encountered something really strange..
if( defined $top_splice_idx and defined $bottom_splice_idx ) {
	splice @menu_lines, $top_splice_idx, ( 1 + $bottom_splice_idx - $top_splice_idx ); #1+ to make sure we get the closing line

	print $oh @menu_lines;
	close $oh;
	rename $tmp_menu, $default_menu or die "Failed to replace [$default_menu]: $!\n";

	print "Removed sub-menu button from [$default_menu]\n";
}
else {
	print "Failed to find sub-menu button in [$default_menu]\n";
	close $oh; unlink $tmp_menu or die "Failed to remove temporary menu file [$tmp_menu]\n"; #Failing should never be possible..
}

#----------------------------

#my $abs_submenu = "$default_menu_dir/$submenu";
#if( -f $abs_submenu ) {
	#unlink "$default_menu_dir/$submenu" or die "Failed to delete [$abs_submenu]: $!\n";
	#print "Removed $submenu\n";
#}

for( glob "$default_menu_dir/hd-trailers*.xml" ) { 
	if( -f $_ ) {
		unlink $_ or die "Failed to delete [$_]: $!\n";
		print "Removed $_\n";
	}
}
