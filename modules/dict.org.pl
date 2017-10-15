#!/usr/bin/perl -w

=cut
eval 'exec /usr/bin/perl -w -S $0 ${1+"$@"}'
    if 0; # not running under some shell
=cut
#
# dict - perl DICT client (for accessing network dictionary servers)
#
# $Id: dict,v 1.2 2003/05/05 23:55:00 neilb Exp $
#

# modified by pragma_ for pbot IRC Perl bot
# changed output to be more IRC-friendly
# set default database to wn
# created dict_hash subroutine to split definition string into hash table grouped by type (verb, noun, etc) and definition number
# added -t and -n options to display results with type (v, n, *, etc) and starting from number

use strict;
use Net::Dict;
use AppConfig;

use vars qw($VERSION);
$VERSION = sprintf("%d.%d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/);

#-----------------------------------------------------------------------
# Global variables
#-----------------------------------------------------------------------
my $PROGRAM;                     # The name we're running as, minus path
my $config;                      # Config object (AppConfig::Std)
my $dict;                        # Dictionary object (Net::Dict)

initialise();

#-----------------------------------------------------------------------
# Deal with any informational options
#-----------------------------------------------------------------------

=cut
print $dict->serverInfo(), "\n" if $config->serverinfo;
show_db_info($config->info) if $config->info;
list_databases() if $config->dbs;
list_strategies() if $config->strats;
=cut

if($config->database) {
  $dict->setDicts($config->database);
} else {
  $dict->setDicts('wn');
}

#-----------------------------------------------------------------------
# Perform define or match, if a word or pattern was given
#-----------------------------------------------------------------------
if (@ARGV > 0)
{
=cut
    if ($config->match)
    {
	match_word(shift @ARGV);
    }
    else
    {
=cut
	define_word(join ' ', @ARGV);
=cut
    }
=cut
} else {
      print "Usage: dict [-d database] [-n start from definition number] [-t abbreviation of word class type (n]oun, v]erb, adv]erb, adj]ective, etc)] [-search <regex> for definitions matching <regex>] <word>\n";
  exit 0;
}

exit 0;

#=======================================================================
#
# define_word()
#
# Look up definition(s) for the specified word.
#
#=======================================================================
sub define_word
{
  my $word = shift;
  my $eref;
  my $entry;
  my ($db, $def);


  $eref = $dict->define($word);

  if (@$eref == 0)
  {
    _no_definitions($word);
  }
  else
  {
    foreach $entry (@$eref)
    {
      ($db, $def) = @$entry;

      my $defs = dict_hash($def);
      print "$defs->{word}: ";

      my $comma = '';
      my $def_type = $config->def_type;
      my $def_contains = $config->def_contains;

      # normalize '*' to '.*'
      $def_type =~ s/\.\*/*/g;
      $def_type =~ s/\*/.*/g;

      # normalize '*' to '.*'
      $def_contains =~ s/\.\*/*/g;
      $def_contains =~ s/\*/.*/g;

      my $defined = 0;

      eval {
        foreach my $type (keys %$defs) {
          next if $type eq 'word';
          next unless $type =~ m/$def_type/i;
          print "$comma$type: " if length $type;
          foreach my $number (sort { $a <=> $b } keys %{ $defs->{$type} }) {
            next unless $number >= $config->def_number;
            next unless $defs->{$type}{$number} =~ m/$def_contains/i;
            print "$comma" unless $number == 1;
            print "$number) $defs->{$type}{$number}";
            $comma = ",\n\n";
            $defined = 1;
          }
        }
      };

      if($@) {
        print "Error in -t parameter.  Use v, n, *, etc.\n";
        exit 0;
      }

      if (not $defined && $def_type ne '*') {
        my $types = '';
        $comma = '';
        foreach my $type (sort keys %$defs) {
          next if $type eq 'word';
          $types .= "$comma$type";
          $comma = ', ';
        }
        if (length $types) {
          print "no `$def_type` definition found; available definitions: $types.\n";
        } else {
          print "no definition found.\n";
        }
      } elsif (not $defined) {
        print "no definition found.\n";
      }
    }
  }
}

sub dict_hash {
  my $def = shift;
  my $defs = {};

  $def =~ s/{([^}]+)}/$1/g;

  my @lines = split /[\n\r]/, $def;

  $defs->{word} = shift @lines;

  my ($type, $number, $text) = ('', 1, '');

  foreach my $line (@lines) {
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    $line =~ s/\s+/ /g;

    if($line =~ m/^([a-z]+) (\d+): (.*)/i) {
      ($type, $number, $text) = ($1, $2, $3);
    }
    elsif($line =~ m/^(\d+): (.*)/i) {
      ($number, $text) = ($1, $2);
    }
    else {
      $text = $line;
    }

    $text = " $text"  if exists $defs->{$type}{$number};
    $defs->{$type}{$number} .= $text;
  }

  return $defs;
}

#=======================================================================
#
# _no_definitions()
#
# Called when no definitions were found for the given word.
# We use either 'lev' or 'soundex' matching to look for words
# which are "close" to the given word, in-case they've mis-spelled
# it, etc.
#
#=======================================================================
sub _no_definitions
{
    my $word = shift;

    my %strategies;
    my %words;
    my $strategy;


    %strategies = $dict->strategies;
    if (!exists($strategies{'lev'}) && !exists($strategies{'soundex'}))
    {
        print "no definition found for \"$word\"\n";
        return;
    }

    $strategy = exists $strategies{'lev'} ? 'lev' : 'soundex';
    foreach my $entry (@{ $dict->match($word, $strategy) })
    {
        $words{$entry->[1]}++;
    }
    if (keys %words == 0)
    {
        print "no definition found for \"$word\", ",
            "and no similar words found\n";
    }
    else
    {
        print "no definition found for \"$word\" - perhaps you meant: ", join(', ', keys %words), "\n";
    }
}

#=======================================================================
#
# match_word()
#
# Look for matches of the given word, using the strategy specified
# with the -strategy switch.
#
#=======================================================================
sub match_word
{
    my $word = shift;
    my $eref;
    my $entry;
    my ($db, $match);


    unless ($config->strategy)
    {
	die "you must specify -strategy when using -match\n";
    }
    $eref = $dict->match($word, $config->strategy);

    if (@$eref == 0)
    {
        print "no matches for \"$word\"\n";
    }
    else
    {
        foreach $entry (@$eref)
        {
            ($db, $match) = @$entry;
            print "$db : $match\n";
        }
    }
}

#=======================================================================
#
# list_databases()
#
# Query and display the list of available databases on the selected
# DICT server.
#
#=======================================================================
sub list_databases
{
    my %dbs = $dict->dbs();


    tabulate_hash(\%dbs, 'Database', 'Description');
}

#=======================================================================
#
# list_strategies()
#
# Query and display the list of matching strategies supported
# by the DICT server.
#
#=======================================================================
sub list_strategies
{
    my %strats = $dict->strategies();


    tabulate_hash(\%strats, 'Strategy', 'Description');
}

#=======================================================================
#
# show_db_info()
#
# Query the server for information about the specified database,
# and display the results.
#
# The information is typically several pages of text,
# describing the contents of the dictionary, where it came from,
# credits, etc.
#
#=======================================================================
sub show_db_info
{
    my $db  = shift;
    my %dbs = $dict->dbs();


    if (not exists $dbs{$config->info})
    {
        print "  dictionary \"$db\" not known\n";
        return;
    }

    print $dict->dbInfo($config->info);
}

#=======================================================================
#
# initialise()
#
# check config file and command-line
#
#=======================================================================
sub initialise
{
    #-------------------------------------------------------------------
    # Initialise misc global variables
    #-------------------------------------------------------------------
    ($PROGRAM = $0) =~ s!.*/!!;

    #-------------------------------------------------------------------
    # Create AppConfig::Std, define parameters, and parse command-line
    #-------------------------------------------------------------------
    $config = AppConfig->new({ CASE => 1 })
        || die "failed to create AppConfig::Std: $!\n";

    $config->define('host',       { ARGCOUNT => 1, ALIAS => 'h' });
    $config->define('port',       { ARGCOUNT => 1, ALIAS => 'p',
                                    DEFAULT => 2628 });
    $config->define('database',   { ARGCOUNT => 1, ALIAS => 'd' });
    $config->define('def_number',   { ARGCOUNT => 1, ALIAS => 'n', DEFAULT => 1 });
    $config->define('def_type',   { ARGCOUNT => 1, ALIAS => 't', DEFAULT => '*'});
    $config->define('def_contains',   { ARGCOUNT => 1, ALIAS => 'search', DEFAULT => '*'});

=cut
    $config->define('match',      { ARGCOUNT => 0, ALIAS => 'm' });
    $config->define('dbs',        { ARGCOUNT => 0, ALIAS => 'D' });
    $config->define('strategy',   { ARGCOUNT => 1, ALIAS => 's' });
    $config->define('strats',     { ARGCOUNT => 0, ALIAS => 'S' });
=cut
    $config->define('client',     { ARGCOUNT => 1, ALIAS => 'c',
				    DEFAULT => "$PROGRAM $VERSION ".
				"[using Net::Dict $Net::Dict::VERSION]",
				  });
=cut
    $config->define('info',       { ARGCOUNT => 1, ALIAS => 'i' });
    $config->define('serverinfo', { ARGCOUNT => 0, ALIAS => 'I' });
    $config->define('verbose',    { ARGCOUNT => 0 });
=cut

    if(not $config->args(\@ARGV)) {
      print "Usage : dict [-d database] [-n start from definition number] [-t abbreviation of word class type (n]oun, v]erb, adv]erb, adj]ective, etc)] [-search <regex> for definitions matching <regex>] <word>\n";
      exit;
    }

    #-------------------------------------------------------------------
    # Consistency checking, ensure we have required options, etc.
    #-------------------------------------------------------------------
    $config->host('dict.org') unless $config->host;

    print $config->client, "\n" if $config->verbose || $config->debug;

    #-------------------------------------------------------------------
    # Create connection to DICT server
    #-------------------------------------------------------------------
    $dict = Net::Dict->new($config->host,
                           Port   => $config->port,
                           Client => $config->client,
			   Debug  => $config->debug,
                          )
        || die "failed to create Net::Dict: $!\n";
}

#=======================================================================
#
# tabulate_hash()
#
# format a hash as a simple ascii table, for displaying lists
# of databases and strategies.
#
#=======================================================================
sub tabulate_hash
{
    my $hashref     = shift;
    my $keytitle    = shift;
    my $value_title = shift;

    my $width = length $keytitle;
    my ($key, $value);


    #-------------------------------------------------------------------
    # Find the length of the longest key, so we can right align
    # the column of keys
    #-------------------------------------------------------------------
    foreach $key (keys %$hashref)
    {
        $width = length($key) if length($key) > $width;
    }

    #-------------------------------------------------------------------
    # print out keys and values in a basic ascii formatted table view
    #-------------------------------------------------------------------
    printf("  %${width}s   $value_title\n", $keytitle);
    print '  ', '-' x $width, '   ', '-' x (length $value_title), "\n";
    while (($key, $value) = each %$hashref)
    {
	printf("  %${width}s : $value\n", $key);
    }
    print "\n";
}


__END__

=head1 NAME

dict - a perl client for accessing network dictionary servers

=head1 SYNOPSIS

B<dict> [OPTIONS] I<word>

=head1 DESCRIPTION

B<dict> is a client for the Dictionary server protocol (DICT),
which is used to query natural language dictionaries hosted on
a remote machine.  When used in the most simple way,

    % dict word

B<dict> will look for definitions of I<word> in the dictionaries
hosted at B<dict.org>. If no definitions are found, then dict
will look for words which are similar, and list them:

    % dict bonana
      no definition for "bonana" - perhaps you meant:
        banana, bonanza, Banana, Bonanza, Bonasa

This feature is only available if the remote DICT server supports
the I<soundex> or I<Levenshtein> matching strategies.
You can use the B<-stats> switch to find out for yourself.

You can specify the hostname of the DICT server using the B<-h> option:

    % dict -h dict.org dictionary

A DICT server can support a number of databases;
you can use the B<-d> option to specify a particular database.
For example, you can look up computer-related terms
in the Free On-line Dictionary Of Computing (FOLDOC) using:

    % dict -h dict.org -d foldoc byte

To find out what databases (dictionaries) are available on
a server, use the B<-dbs> option:

    % dict -dbs

There are many dictionaries hosted on other servers around the net;
a list of some of them can be found at

    http://www.dict.org/links.html

=head2 MATCHING

Instead of requesting word definitions, you can use dict
to request a list of words which match a pattern.
For example, to look for four-letter words starting in 'b'
and ending in 'p', you would use:

    % dict -match -strategy re '^b..p$'

The B<-match> option says you want a list of matching words rather
than a definition.
The B<-strategy re> says to use POSIX regular expressions
when matching the pattern B<^b..p$>.

Most DICT servers support a number of matching strategies;
you can get a list of the strategies provided by a server
using the B<-strats> switch:

    % dict -h dict.org -strats

=head1 OPTIONS

=over 4

=item B<-h> I<server> or B<-host> I<server>

The hostname for the DICT server. If one isn't specified
then defaults to B<dict.org>.

=item B<-p> I<port> or B<-port> I<port>

Specify the port for connections (default is 2628, from RFC 2229).

=item B<-d> I<dbname> or B<-database> I<dbname>

The name of a specific database (dictionary) to query.

=item B<-m> or B<-match>

Look for words which match the pattern (using the specified strategy).

=item B<-i> I<dbname> or B<-info> I<dbname>

Request information on the specified database.
Typically results in a couple of pages of text.

=item B<-c> I<string> or B<-client> I<string>

Specify the CLIENT identification string sent to the DICT server.

=item B<-D> or B<-dbs>

List the available databases (dictionaries) on the DICT server.

=item B<-s> I<strategy> or B<-strategy> I<strategy>

Specify a matching strategy. Used in combination with B<-match>.

=item B<-S> or B<-strats>

List the matching strategies (used in -strategy) supported
by the DICT server.

=item B<-I> or B<-serverinfo>

Request information on the selected DICT server.

=item B<-help>

Display a short help message including command-line options.

=item B<-doc>

Display the full documentation for B<dict>.

=item B<-version>

Display the version of B<dict>

=item B<-verbose>

Display verbose information as B<dict> runs.

=item B<-debug>

Display debugging information as B<dict> runs.
Useful mainly for developers.

=back

=head1 KNOWN BUGS AND LIMITATIONS

=over 4

=item *

B<dict> doesn't know how to handle firewalls.

=item *

The authentication aspects of RFC 2229 aren't currently supported.

=item *

Display of list results (eg from B<-strats> and B<-dbs>) could be better.

=item *

B<dict> isn't very smart at handling combinations of options.

=item *

Currently no support for a configuration file - will add one soon.

=back

=head1 SEE ALSO

=over 4

=item www.dict.org

The DICT home page, with all sorts of useful information.
There are a number of other DICT clients available.

=item dict

The C dict client written by Rik Faith;
the options are pretty much lifted from Rik's client.

=item RFC 2229

The document which defines the DICT network protocol.

http://www.cis.ohio-state.edu/htbin/rfc/rfc2229.html

=item Net::Dict

The perl module which implements the client API for RFC 2229.

=back

=head1 VERSION

$Revision: 1.2 $

=head1 AUTHOR

Neil Bowers <neil@bowers.com>

=head1 COPYRIGHT

Copyright (C) 2002 Neil Bowers. All rights reserved.

This script is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

