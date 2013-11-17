#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use JSON qw/decode_json/;

############ CONFIG
#TODO Figure out how to replace this with vlc..
# Also should we always just be QuickTime?
my $play_command = "/usr/bin/mplayer -fs -zoom -quiet -user-agent QuickTime -cache-min 10 -cache 16384";
my $button_template = "\t<button>\n\t\t<type>VIDEO_BROWSER</type>\n\t\t<text>%s</text>\n\t\t<action>EXEC $play_command '%s'</action>\n\t</button>\n";
my $output_dir = ( $ARGV[0] // "/usr/local/share/mythtv/themes/defaultmenu" );
############

my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0 (Windows NT 6.2; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/32.0.1667.0 Safari/537.36' );

for my $trailer_page ( qw{page/1 coming-soon most-watched top-movies opening-this-week coming-soon netflix-new-releases} ) {

my $menu_file = "hd-trailers-$trailer_page.xml";
if( $trailer_page eq 'page/1' ) { $menu_file = "hd-trailers-latest.xml" }

my $hd_trailers_url = "http://www.hd-trailers.net/$trailer_page";


my $resp = $ua->get( $hd_trailers_url );

if( not $resp->is_success ) {
	die "Failed to fetch [$hd_trailers_url]: ", $resp->code, " -- ", $resp->decoded_content, "\n";
}

my $index_content = $resp->decoded_content;

# The new menu we're producing.
my $new_trailer_menu = '<mythmenu name="$trailer_page">' . "\n";

my %seen_movie;
# Parse the HTML using a regex to avoid an actual parser dependency. We may go to hell for this.
while( $index_content =~ m{href="(/movie/[^"]+)"}g ) {
	my $movie_url = $1;
	next if $movie_url =~ /#autoplay/; #Skip the 'duplicate' links for each movie.
	next if $seen_movie{ $movie_url }++; #Skip URLs we've already seen

	my $abs_movie_url = URI->new_abs( $movie_url, $hd_trailers_url );

	my $resp = $ua->get( $abs_movie_url );

	if( not $resp->is_success ) {
		warn "Failed to fetch [$abs_movie_url]: ", $resp->code, " -- ", $resp->decoded_content, "\n";
		next;
	}

	if( -t STDOUT ) {
		print "Parsing $movie_url\n";
	}

	my $movie_content = $resp->decoded_content;

	# Attempt to find a movie title
	my $title = "Unnamed Trailer";
	# These regexes are super fragile. If we're getting unnamed trailers its probably because these stopped matching.
	#   Possible future problems: using ' instead of " to quote attributes, content attribute comes before property attribute, attribute name changes..
	if( $movie_content =~ m{<meta.*?property="og:title".*?content="([^"]+)"/>}i
		or $movie_content =~ m{<meta.*?name="twitter:title".*?content="([^"]+)"/>}i
		) {
			$title = $1;
	}


	# Attempt to find a uri for this movie
	my $stream_uri;

	# Match a "http://www.hd-trailers.net/yahoo-redir.php?id=a99df691-58d6-31d0-863e-79ba29b97896&amp;resolution=720" style url *somewhere* on the page.
	if( $movie_content =~ m{yahoo-redir.php\?id=.*?([a-zA-Z0-9-]+)} ) {
		my $movie_id = $1;

		#TODO Figure out what plrs is supposed to be, heh.
		my $yql_query = "http://video.query.yahoo.com/v1/public/yql?callback=&q=SELECT * FROM yahoo.media.video.streams WHERE id='$movie_id' AND format='mp4' AND protocol='http' AND plrs='sdwpWXbKKUIgNzVhXSce__' AND region='US'&env=prod&format=json";

		my $yql_resp = $ua->get( $yql_query );

		if( not $yql_resp->is_success ) {
			warn "Failed to fetch yql for [$movie_id]: ", $resp->code, " -- $movie_content\n";
			next;
		}

		my $yql_data = eval { decode_json $yql_resp->decoded_content };
		if( $@ or not $yql_data ) {
			warn "Failed to receive a usable response from yql!\nQuery: $yql_query\nErr: $@\nContent: ", $yql_resp->decoded_content, "\n";
			next;
		}

		my $streams = $yql_data->{query}->{results}->{mediaObj}->[0]->{streams};

		if( not $streams or not @$streams ) {
			warn "Failed to get any streams for [$movie_id]!\n";
			next;
		}

		# Sort for highest bitrate
		my( $best_stream ) = sort { $b->{bitrate} <=> $a->{bitrate} } @$streams;

		$stream_uri = $best_stream->{host} . $best_stream->{path};
	}
	# Check for apple movie trailers
	# We prefer apple trailers to avoid using hd-trailer's bandwidth!
	#http://trailers.apple.com/movies/independent/frozen/frozen-tlr1_h1080p.mov
	#http://movietrailers.apple.com/movies/wb/thehobbit2/thehobbit2-sneakpeek_h1080p.mov
	elsif( $movie_content =~ m{http://(?:movie)?trailers.apple.com/movies/.+\.mov}i ) { 

		my @apple_uris;

		while( $movie_content =~ m{href="(http://(?:movie)?trailers.apple.com/movies/[^"]+\.mov)"}ig ) {
			my $uri = $1;
			my $res = 0;
			if( $uri =~ /(\d+)/ ) {
				$res = $1;
			}

			push @apple_uris, [$uri,$res];
		}

		( $stream_uri ) = map { $_->[0] } sort { $b->[1] <=> $a->[1] } @apple_uris;
	}
	# Check for 'locally' mirrored trailers
	elsif( $movie_content =~ m{href="http://videos.hd-trailers.net/\w+}i ) {
		
		my @trailer_uris;

		while( $movie_content =~ m{href="(http://videos.hd-trailers.net/[^"]+\.[a-z0-9]{2,4})"}ig ) {
			my $uri = $1;
			my $res = 0;
			if( $uri =~ /(\d+)/ ) {
				$res = $1;
			}

			push @trailer_uris, [$uri,$res];
		}

		( $stream_uri ) = map { $_->[0] } sort { $b->[1] <=> $a->[1] } @trailer_uris;
	}
	elsif( $movie_content =~ m{href="http://avideos.5min.com[^"]+\.mp4"}i ) {

		my @trailer_uris;
		while( $movie_content =~ m{href="(http://avideos.5min.com[^"]+?(?:_(\d+))?\.mp4)"}ig ) { 
			push @trailer_uris, [ $1, $2 // 0 ];
		}

		( $stream_uri ) = map { $_->[0] } sort { $b->[1] <=> $a->[1] } @trailer_uris;
		}
		elsif( $movie_content =~ m{href="http://www.youtube.com/watch\?}i ) { 
			#TODO Add support for youtube trailers!
			# Perhaps via youtube-dl?
			# mplayer -fs "$(youtube-dl '$stream_uri')" appears to work!
			# But will it work in an EXEC command?
			warn "Skipping $movie_url: youtube only.\n";
			next;
		}
		else {
			warn "Failed to find any kind of trailer uri for [$movie_url]\n";
			next;
		}

		$stream_uri =~ s/&/&amp;/g; #We're inserting this into XML but does mythtv actually care?
		$stream_uri =~ s/'/&apos;/g;
		$stream_uri =~ s/"/&quot;/g;
		$stream_uri =~ s/</&lt;/g;
		$stream_uri =~ s/>/&gt;/g;

		$new_trailer_menu .= sprintf $button_template, $title, $stream_uri;
	}

	$new_trailer_menu .= "</mythmenu>";

	# Check to see if we've actually generated a new file since we could have failed to parse/fetch every single trailer
	if( length $new_trailer_menu  > 30 ) {
		my $output_file = "$output_dir/$menu_file";
		open my $fh, ">", $output_file or die "Failed to open $output_file: $!\n";
		print $fh $new_trailer_menu;
	}
	else {
		warn "I think we failed on every single trailer:\n $new_trailer_menu\n";
	}
}
