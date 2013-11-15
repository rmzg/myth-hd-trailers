#!/usr/bin/perl

use strict;
use warnings;

use LWP::UserAgent;
use JSON qw/decode_json/;

############ CONFIG
my $hd_trailers_url = "http://www.hd-trailers.net/page/1/";
#TODO Figure out how to replace this with vlc..
my $play_command = "/usr/bin/mplayer -fs -zoom -quiet -user-agent NSPlayer -cache-min 75 -cache 16384";
############

my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0 (Windows NT 6.2; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/32.0.1667.0 Safari/537.36' );
my $resp = $ua->get( $hd_trailers_url );

if( not $resp->is_success ) {
	die "Failed to fetch [$hd_trailers_url]: ", $resp->code, " -- ", $resp->decoded_content, "\n";
}

# The new menu we're producing.
my $new_trailer_menu = '<mythmenu name="TRAILERS">' . "\n";

my %seen_movie;
# Parse the HTML using a regex to avoid an actual parser dependency. We may go to hell for this.
while( $resp->decoded_content =~ m{href="(/movie/[^"]+)"}g ) {
	my $movie_url = $1;
	next if $movie_url =~ /#autoplay/; #Skip the 'duplicate' links for each movie.
	next if $seen_movie{ $movie_url }++; #Skip URLs we've already seen

	my $abs_movie_url = URI->new_abs( $movie_url, $hd_trailers_url );

	my $resp = $ua->get( $abs_movie_url );

	if( not $resp->is_success ) {
		warn "Failed to fetch [$abs_movie_url]: ", $resp->code, " -- ", $resp->decoded_content, "\n";
		next;
	}

	# Attempt to find a movie title
	my $title = "Unnamed Trailer";
	# These regexes are super fragile. If we're getting unnamed trailers its probably because these stopped matching.
	#   Possible future problems: using ' instead of " to quote attributes, content attribute comes before property attribute, attribute name changes..
	if( $resp->decoded_content =~ m{<meta.*?property="og:title".*?content="([^"]+)"/>}i
		or $resp->decoded_content =~ m{<meta.*?name="twitter:title".*?content="([^"]+)"/>}i
		) {
			$title = $1;
	}


	# Match a "http://www.hd-trailers.net/yahoo-redir.php?id=a99df691-58d6-31d0-863e-79ba29b97896&amp;resolution=720" style url *somewhere* on the page.
	my( $movie_id ) = $resp->decoded_content =~ m{yahoo-redir.php\?id=.*?([a-zA-Z0-9-]+)};

	if( not defined $movie_id ) {
		warn "Failed to find a movie_id for [$abs_movie_url]!\n";
		next;
	}

	#TODO Figure out what plrs is supposed to be, heh.
	my $yql_query = "http://video.query.yahoo.com/v1/public/yql?callback=&q=SELECT * FROM yahoo.media.video.streams WHERE id='$movie_id' AND format='mp4' AND protocol='http' AND plrs='sdwpWXbKKUIgNzVhXSce__' AND region='US'&env=prod&format=json";

	my $yql_resp = $ua->get( $yql_query );

	if( not $yql_resp->is_success ) {
		warn "Failed to fetch yql for [$movie_id]: ", $resp->code, " -- ", $resp->decoded_content, "\n";
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

	my $stream_uri = $best_stream->{host} . $best_stream->{path};

	#print "$movie_url: $stream_uri\n";
	#last;

	$new_trailer_menu .= "\t<button>\n\t\t<type>VIDEO_BROWSER</type>\n\t\t<text>$title</text>\n\t\t<action>EXEC $play_command $stream_uri</action>\n\t</button>";
}

$new_trailer_menu .= "</mythmenu>";

# Check to see if we've actually generated a new file since we could have failed to parse/fetch every single trailer
if( length $new_trailer_menu  > 30 ) {
	open my $fh, ">", "hdmovietrailer.xml" or die "Failed to open hdmovietrailer.xml: $!\n";
	print $fh $new_trailer_menu;
}
else {
	warn "I think we failed on every single trailer:\n $new_trailer_menu\n";
}
