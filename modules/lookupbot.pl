#!/usr/bin/perl -T

use strict;
use LWP::Simple;
use LWP::UserAgent;
use Encode qw/ decode is_utf8 /;
use CGI qw/escape unescapeHTML/;
use utf8;
use HTML::Entities;

my $VERSION = '1.0.2';

my %IRSSI = (
    'authors' => 'Craig Andrews',
    'contact' => 'craig@simplyspiffing.com',
    'name'    => 'lookupbot',
    'description' => 'Some kind of magical internet searcher',
    'license' => 'Craig\'s Magical Freebie License');

## Changes ##
# 0.0.1 - Initial version, not very good
# 1.0.0 - Finished!
# 1.0.1 - Added 'pre' and 'escape' options to give more flexibility
#         Added tinyurl and !cndb
# 1.0.2 - Changed privmsg handling
#         Removed !dict and !thes because they're too badly broken
#         Added !memetic, !horoscope, !cricket
#         Added different handling for public/private responders
# 1.0.3 - Added !tdm
#         Split request processing away from event handling
#         Added the start of a simple cache
# 1.1.0 - Completion of refactoring, so officially a new version!

##
# Clean up the input data and separate the
# trigger and parameter portions
##
sub get_data {
    my $data = shift;

    my @params = split / +/, $data;
    my $trigger = shift @params;

    $data = join ' ', @params;
    $data =~ s/[^[:print:]]/ /g;
    $data =~ s/  */ /g;

    return $trigger, $data;
}

##
# Retrieve the content from a url
# Params:
#  $url - The URL to query
#  $data - If defined, data to insert into the URL using sprintf
#  $escape - URL encode the data before insertion? 1 = true, 0 = false
##
my %url_cache;
sub get_content {
    my ($url, $data, $escape, $cache) = @_;

    $data = escape($data) unless $escape == 0;
    $url = sprintf($url, $data) if defined $data;

    # Use the cache if requested
    my $timeout = time() - $cache;
    if (defined $cache &&
        $cache > 0 && 
	exists $url_cache{$url} &&
	$url_cache{$url}->{'time'} > $timeout) {

	return $url_cache{$url}->{'content'};
    }

    my $ua = LWP::UserAgent->new(agent => "ME");
    my $result = $ua->get($url, ('Accept-Charset' => 'utf-8,iso-8859-1,*'));

    my $content;
    if ($result->is_success)
    {
        my $encoding = $result->content_encoding;
        if ($encoding eq "") {
            $encoding = is_utf8($result->content)?'utf-8':'iso-8859-1';
        }
        $content = decode($encoding, $result->content()) if $result->is_success;
	$url_cache{$url} = {'time' => time(), 'content' => $content};
    }

    return $content;
}

##
# Google image search
##
sub image_search {
    my $content = shift;

    my $lines = join ' ', $content =~ /imgurl=(.*?)\&/is;
    return $lines;
}

##
# Basic google search
##
sub google_search {
    my $content = shift;

    my ($calcs) = $content =~ /<td nowrap><h2 class=r><font size=\+1><b>(.+?)<\/b>/sm;
    return $calcs if defined $calcs and length $calcs;

    my $lines = join ' ', $content =~ /<div class=g><a href="(.+?)"/is;
    return $lines;
}

##
# Google definition search
##
sub define_search {
    my $content = shift;

    my $lines = join ' ', $content =~ /(?<=<li>)(.+?)(?=<br>|<li>)/is;
    return $lines;
}

##
# Urban dictionary search
##
sub urban_search {
    my $content = shift;
    my $term = shift;

    my @rawlines = $content =~ /<div class=["'](meaning|definition|example|def_p)["']>(.+?)<\/?div/gism;
    my @lines;
    foreach (@rawlines) {
        my @s = split /(?:\n|<br\/?>)/;
        push @lines, $_ for @s;
    }

    my $definition;
    my $def_word = 0;
    my $paragraphs = 0;

    while ($def_word <= 1 &&
           $paragraphs <= 4 &&
           scalar(@lines) > 0) {

        my $s = shift(@lines);
        $s =~ s/^\s*//;
        $s =~ s/\s*$//;
        $s =~ s/<.+?>//g;

        if ($s =~ /(meaning|definition|def_p)/) {
            $def_word++;
        } elsif ($s =~ /example/) {
# Do nothing
        } elsif (length $s > 0) {
            $definition .= "$s\n";
            $paragraphs++;
        }
    }

    return decode_entities($definition);
}

##
# Profanisaurus search
##
sub profan_search {
    my $content = shift;

    my @matches = $content =~ /<a href="(profan_results.php\?profan=searchstory.+?)">(.+?)</gsi;
    return '' unless @matches;

    my %definitions;
    my $ix;
    for ($ix = 0; $ix < @matches; $ix+=2) {
        my $key = $matches[$ix+1];
        $key =~ tr/A-Z/a-z/;
        $definitions{$key} = $matches[$ix];
    }

    my @keys = sort keys %definitions;

    $content = get_content('http://www.viz.co.uk/profanisaurus/'.$definitions{$keys[0]}, 1);
    @matches = $content =~ /class=profandefinition>(.+)/;

    return join "\n", @matches;
}

##
# Urban word of the day
##
sub uwotd_search {
    my $content = shift;

    my ($word) = $content =~ /(<item .+?<\/item>)/s;
    my ($title, $description) = $word =~ /<(?:title|description)>(.+?)<\//gs;
    
    $description = unescapeHTML($description);
    $description =~ s/<br\s*\/?>/\n/g;

    my @lines = $description =~ /<p>(.+?)<\/p>/gs;
    unshift @lines, $title;

    return join("\n", @lines);
}

##
# Worthless word of the day
##
sub wwotd_search {
    my $content = shift;

    my ($matches) = $content =~ m|(?<=<PRE>\s)(the worthless word for the day is:.+?)(?=</PRE>)|ism;
    my @lines = split "\n", $matches;
    return if length @lines == 0;

    my $blanks = 2;
    my @result;
    while ($blanks > 0 && scalar(@lines)) {
        my $line = shift @lines;
        if (length $line) {
            push @result, $line;
        } else {
            $blanks --;
        }
    }
    
    return join "\n", @result;
}

##
# Dictionary.com word of the day
##
=cut
sub wotd_search {
    my $content = shift;

    my @lines = $content =~ m|(?<=<span class="hw">).+?(?=</p>)|igosm;
    return if length @lines == 0;
    s/<.+?>//g foreach (@lines);
    @lines = grep { /^.+$/ } split (/\n/, @lines[0]);
    
    return join ("\n", @lines);
}
=cut
##
# Sloganizer
##
sub slogan_search {
    my $content = shift;

    my ($lines) = $content =~ /<div class="slogan" id="slogan">.<b>(.*?)<\/b>.<\/div>/is;
    return $lines;
}

##
# Compliment generator
##
sub compliment_search {
    my $content = shift;

    my $lines = join ' ', $content =~ /<h2>(.*?)<\/h2>/is;
    $lines =~ s/[\r\n]/ /g;
    return $lines;
}

##
# Insult generator
##
sub insult_search {
    my $content = shift;

    my $lines = join ' ', $content =~ /<div class="insult" id="insult">(.+?)<\/div>/is;
    $lines =~ s/[\r\n]/ /g;
    return $lines;
}

##
# Limerick DB search
##
sub limerick_preprocessor {
    my $parameter = shift;

    if (!defined($parameter) || $parameter == 0) {
        $parameter = 'random';
    }

    return $parameter;
}

sub limerick_search {
    my $content = shift;

    my $lines = join ' ', $content =~ /<div class="quote_output">(.*?)<\/div>/is;
    $lines =~ s/\t//g;
    $lines =~ s/<br\s*\/?>/\n/g;

    return $lines;
}

##
# Bash.org ID search
##
sub bash_preprocessor {
    my $parameter = shift;

    if (!defined($parameter) || $parameter == 0) {
        $parameter = 'random';
    }

    return $parameter;
}

sub bash_search {
    my $content = shift;

    my $lines = join ' ', $content =~ /<p class="qt">(.*?)<\/p>/is;
    $lines =~ s/<br\/?>/\n/g;
    return $lines;
}

##
# Memetic.org ID search
# Preprocessor converts empty parameter to 'random' search
##
sub memetic_preprocessor {
    my $parameter = shift;

    if (!defined($parameter) || $parameter == 0) {
        $parameter = 'random';
    }

    return $parameter;
}

sub memetic_search {
    my $content = shift;

    my @lines = $content =~ /<font size='-1' face='Courier New, Courier, mono'>(.*?)<\/font>/isg;
    my $lines = $lines[1];
    $lines =~ s/<br\/?>/\n/g;
    return $lines;
}

##
# Generate a tinyurl for a given URL
# Only really useful as a privmsg
##
sub tinyurl_search {
    my $content = shift;
    my $term = shift;
    my $server = shift;
    my $nick = shift;

    my @lines = $content =~ /<blockquote><b>(.+?)</gism;

    my $result = '';
    if (scalar(@lines)) {
        $result = $lines[1];
    }

    return $result;
}

##
# Get the current England game score, if any
##
sub cricket_search {
    my $content = shift;

    my @lines = grep {/England/} split /$/m, $content;

    return $lines[0];
}

##
# Celebrity Nude Database search
# Preprocessor switches "Forename Surname" to
# "Surname, Forename" format
##
sub cndb_search {
    my $content = shift;

    my ($name) = $content =~ /<title>CNdb: (.+?)<\/title>/igosm;
    return "" unless defined $name && length $name;

    my @raw = $content =~ m/class="bold">(.+?)<\/td>/gosm;
    return "" unless scalar(@raw);
    my @lines;
    while (scalar(@raw) &&
        $raw[0] !~ /(was this review helpful|login to rate this review|^\s*$)/i) {

        my $l = shift @raw;
        push @lines, $l if $l !~ /\&nbsp;/;
    }

    my $output = "$name has appeared nude in:\n";
    $output .= join "\n", @lines;

    return $output;
}

sub cndb_preprocessor {
    my $parameter = shift;

    $parameter =~ s/(?<=\b)(\w)/\u$1/g;
    my @parts = split /\s+/, $parameter;
    my $last = pop @parts;
    $last .= "," if scalar(@parts);
    unshift @parts, $last;

    return join " ", @parts;
}

##
# Horoscope search
##
sub horoscope_search {
    my $content = shift;
    my $term = shift;

    $content =~ s/[\r\n]/ /gsm;
    my ($line) = $content =~ m|CHANGE $term HERE -->(.+)<!-- END $term HERE|i;
    $line =~ s/  +/ /g;

    if($line eq "") {
      return "No results found; signs of the Zodiac are Aquarius, Pisces, Aries, Taurus, Gemini, Cancer, Leo, Virgo, Libra, Scorpio, Sagittarius, Capricorn";
    }

    return $line;
}

##
# Horoscope search
##
sub horrorscope_search {
    my $content = shift;
    my $term = shift;

    if($term eq"") {
      return "Usage: horrorscope sign; signs of the Zodiac are Aquarius, Pisces, Aries, Taurus, Gemini, Cancer, Leo, Virgo, Libra, Scorpio, Sagittarius, Capricorn";
    }

    $content =~ s/[\r\n]/ /gsm;
    my ($line) = $content =~ m|<tr>.*?$term.*?</td>(.*?)</tr>|i;
    $line =~ s/  +/ /g;

    if($line eq "") {
      return "No results found; signs of the Zodiac are Aquarius, Pisces, Aries, Taurus, Gemini, Cancer, Leo, Virgo, Libra, Scorpio, Sagittarius, Capricorn";
    }

    return $line;
}

##
# Bored.com entertainment provider
##
sub bored_search {
    my $content = shift;

    my @stuff = $content =~ /<b><a href="(.+?)" target="_blank"><font .+?>(.+?)<\/font><\/a> - <\/b> *(.+?)<br>/g;
    my @lines;
    while (scalar(@stuff) > 0) {
        my $url = shift @stuff;
        my $title = shift @stuff;
        my $desc = shift @stuff;

        $url = 'http://www.bored.com'.$url unless $url =~ /^http/;

        my $line = "$title - $url\n$desc";
        push @lines, $line;
    }

    my $pick = rand(scalar(@lines));
    return $lines[$pick];
}

##
# Sickipedia - Sick jokes for all
##

sub sick_search {
    my $content = shift;

    my @stuff = $content =~ /<description><!\[CDATA\[(.+?)]]><\/description>/gosm;

# Try and pick one with less than 5 lines ...
    my $pick = 0;
    my $brs = 0;
    my $count = 3;
    do {
        $pick = rand(scalar(@stuff));
        my @brs = $stuff[$pick] =~ /<br\/>/g;
        $brs = @brs;
        $count--;
    } while ($count > 0 && $brs > 4);
    my $line = $stuff[$pick];

    $line =~ s/<br\/>/\n/g;
    return $line;
}

##
# Random joke
##

sub joke_search {
    my $content = shift;

    my ($line) = $content =~ /<div class="chiste">(.+?)<\/div>/gosm;
    return $line;
}

##
# The Daily Mash random headline
##

sub tdm_search {
    my $content = shift;
    my $term = shift;

    my @lines = $content =~ /<item>(.+?)<\/item>/gosm;

    my $id = rand(scalar(@lines));
    if ($term =~ /^\d+$/ &&
        $term > 0 &&
        $term <= scalar(@lines)) {
	
	$id = $term - 1;
    }

    my @item = grep { /<(title|description|link)>/ } split /\n/, $lines[$id];
    foreach (@item) {
		s/^\s*//;
		$_ = unescapeHTML($_);
	}

    $item[1] =~ s/<.+?>//g;
    my ($url) = process_request('tinyurl', $item[1]);

    return "$item[0]\n$item[2]\n$url";
}


##
# Random proverbs
##

sub proverb_search {
    my $content = shift;

    $content =~ s/\n/ /g;
    my ($line) = $content =~ /<h2>(.+?)<\/h2>/sm;
    return $line;
}

###
# Many different lookerupperers
# Basic structure is:
#   '!triger' => { detail }
# Where the detail hash can have the following keys
#  'url' (mandatory) - The URL to search, optionally with %s for insertion of parameter
#  'sub' (mandatory) - Reference to sub to call with URL content
#  'pre' - Preprocessor to mangle the parameter before being passed to URL
#  'escape' - URL encode the parameter (1 - true, 0 - false). Defaults to true
#  'cache' - Cache individual URLs for 'cache' seconds (e.g. 3600 = 1 hr)
# All triggers can be called via privmsg. To be able to respond to public
# messages (i.e. 'in channel') the trigger must be prefixed by !
# The only 'private only' responder at the moment is tinyurl
###
my %ENGINES = ('!image' =>      {'url' => 'http://images.google.co.uk/images?hl=en&safe=off&q=%s',
                                 'sub' => \&image_search,
				 'cache' => 600},
               '!google' =>     {'url' => 'http://www.google.co.uk/search?hl=en&q=%s',
                                 'sub' => \&google_search},
               '!define' =>     {'url' => 'http://www.google.co.uk/search?hl=en&q=define%%3A%%20%s',
                                 'sub' => \&define_search},
               '!urban' =>      {'url' => 'http://www.urbandictionary.com/define.php?term=%s',
                                 'sub' => \&urban_search,
				 'cache' => 60},
               '!profan' =>     {'url' => 'http://www.viz.co.uk/profanisaurus/profan_results.php?profan=search&prof_search=%s',
                                 'sub' => \&profan_search},
               '!uwotd' =>      {'url' => 'http://feeds.urbandictionary.com/UrbanWordOfTheDay',
                                 'sub' => \&uwotd_search,
				 'cache' => 3600},
               '!wwotd' =>      {'url' => 'http://home.comcast.net/~wwftd/Frame1.html',
                                 'sub' => \&wwotd_search,
				 'cache' => 3600},
               '!wotd' =>       {'url' => 'http://dictionary.reference.com/wordoftheday/',
                                 'sub' => \&wotd_search,
				 'cache' => 3600},
               '!slogan' =>     {'url' => 'http://www.sloganizer.net/en/?slogan=%s',
                                'sub' => \&slogan_search},
               '!insult' => {'url' => 'http://www.webinsult.com/',
                                 'sub' => \&insult_search},
               '!compliment' => {'url' => 'http://www.madsci.org/cgi-bin/cgiwrap/~lynn/jardin/SCG/',
                                 'sub' => \&compliment_search},
               '!limerick' =>       {'url' => 'http://limerickdb.com/?%s',
                                 'sub' => \&limerick_search,
                                 'pre' => \&limerick_preprocessor},
               '!bash' =>       {'url' => 'http://bash.org/?%s',
                                 'sub' => \&bash_search,
                                 'pre' => \&bash_preprocessor},
               '!memetic' =>    {'url' => 'http://www.memetic.org/%s',
                                 'sub' => \&memetic_search,
                                 'pre' => \&memetic_preprocessor},
               '!cricket' =>    {'url' => 'http://www.cricinfo.com/rss/livescores.xml',
                                 'sub' => \&cricket_search},
               'tinyurl' =>     {'url' => 'http://tinyurl.com/create.php?url=%s',
                                 'sub' => \&tinyurl_search,
                                 'escape' => 0,
				 'cache' => 3600},
               '!cndb' =>       {'url' => 'http://cndb.com/actor.html?name=%s',
                                 'sub' => \&cndb_search,
                                 'pre' => \&cndb_preprocessor,
				 'cache' => 3600},
               '!horoscope' =>  {'url' => 'http://www.astrology-online.com/daily.htm',
                                 'sub' => \&horoscope_search,
				 'cache' => 3600},
               '!horrorscope' =>  {'url' => 'http://www.emilystrange.com/beware/horrorscopes.cfm',
                                 'sub' => \&horrorscope_search,
				 'cache' => 3600},
               '!bored' =>      {'url' => 'http://www.bored.com/',
                                 'sub' => \&bored_search,
				 'cache' => 3600},
               '!procrastinate' =>      {'url' => 'http://www.bored.com/',
                                 'sub' => \&bored_search,
				 'cache' => 3600},
               #'!sick' =>       {'url' => 'http://sickipedia.org/feeds/?1195996408.xml',
               #                  'sub' => \&sick_search},
               '!joke' =>       {'url' => 'http://www.ajokeaday.com/ChisteAlAzar.asp',
                                 'sub' => \&joke_search},
	       '!tdm' =>        {'url' => 'http://www.thedailymash.co.uk/rss.xml',
	                         'sub' => \&tdm_search,
				 'cache' => 3600},
                 '!proverb' => {'url' => 'http://server52204.uk2net.com/b3taproverbs/',
                                'sub' => \&proverb_search});

sub process_request {
    my ($trigger, $term, $server, $nick, $target) = @_;

    my $result = '';
    if (exists $ENGINES{$trigger}) {

        my $url = $ENGINES{$trigger}->{'url'};
        my $sub = $ENGINES{$trigger}->{'sub'};
        my $pre = exists $ENGINES{$trigger}->{'pre'} ?
            $ENGINES{$trigger}->{'pre'} : undef;
        my $escape = exists $ENGINES{$trigger}->{'escape'} ?
            $ENGINES{$trigger}->{'escape'} : 1;
        my $cache = exists $ENGINES{$trigger}->{'cache'} ?
            $ENGINES{$trigger}->{'cache'} : 0;

# Pre-process the parameter if a pre function is defined
        $term = $pre->($term) if defined $pre;

# Get the content from the URL
        my $content = get_content($url, $term, $escape, $cache);

# Get the results of the search
        $result = $sub->($content, $term, $server, $nick, $target) if defined $content;
    }
    else
    {
# Quit if this isn't for us
        return undef;
    }

# Split the resulting lines at linebreaks or
# whitespace delimited lines up to 400 characters long
# to prevent IRSSI truncating the output lines
	my @lines = $result =~ /(.{0,400})(?:\r|\n|\s+|$)/g;
	@lines = () unless @lines;

	my @output = ();
	foreach my $text (@lines) {
		next if $text =~ /^\s*$/;

# Strip HTML
        $text =~ s/<(.*?)>/ /g;
        $text = unescapeHTML($text);

# Strip non-printable characters
        $text =~ s/[^[:print:]]/ /g;

# Sort out whitespace
        $text =~ s/ +/ /g;
        $text =~ s/^ *//;
        $text =~ s/ *$//;

	push @output, $text;
	}

    @output = ('No results found') unless scalar(@output) > 0;

    return @output;
}

# Private responder, for privmsg functionality
##
sub private_responder {
    my ($server, $data, $nick, $mask) = @_;
    public_responder($server, $data, $nick, $mask, $nick);
}

##
# Public responder, where all the work gets done
##
sub public_responder {
    my ($server, $data, $nick, $mask, $target) = @_;
    $data =~ s/`//gosm;

    my ($trigger, $term) = get_data($data);
    $trigger =~ y/A-Z/a-z/;

    my $result;
    my $func;

# If this is a public message and the trigger has no !, silently ignore it
    return if ($nick ne $target && $trigger !~ /^!/);

# If the trigger exists, call the URL and process the result
    my @lines = process_request($trigger, $term, $server, $nick, $target);

# Display if necessary
    if (@lines) {
        $server->command("msg $target -!- $_")
            for grep { /./ } @lines;
    }
}

sub main {
  my ($trigger, $term);

  $trigger = shift(@ARGV);
  $term = join(' ', @ARGV);

  if(not defined $trigger) {
    print "Usage: $0 <trigger> [terms]";
    exit 1;
  }

  if($trigger eq "list") {
    my $comma = "Triggers: ";
    foreach my $key (sort keys(%ENGINES)) {
      print "$comma$key";
      $comma = ", ";
    }
    print "\n";
    exit 1;
  }

  $trigger =~ s/^/!/;

  my @lines = process_request($trigger, $term, "server", "nick", "target");

  my $result = join(' ', @lines);

  if($term ne "") {
    print "$term: ";
  }

  print $result . "\n";
}

main;
