#!/usr/bin/env perl

# quick-and-dirty script to import greybot factoids

use warnings;
use strict;

use lib '.';

use File::Basename;
use PBot::DualIndexSQLiteObject;

my @skip = qw/bash ksh check/;

# PBot/Factoids.pm
my %factoid_metadata = (
    'action'                => 'TEXT',
    'action_with_args'      => 'TEXT',
    'add_nick'              => 'INTEGER',
    'allow_empty_args'      => 'INTEGER',
    'background-process'    => 'INTEGER',
    'cap-override'          => 'TEXT',
    'created_on'            => 'NUMERIC',
    'dont-protect-self'     => 'INTEGER',
    'dont-replace-pronouns' => 'INTEGER',
    'edited_by'             => 'TEXT',
    'edited_on'             => 'NUMERIC',
    'enabled'               => 'INTEGER',
    'help'                  => 'TEXT',
    'interpolate'           => 'INTEGER',
    'keyword_override'      => 'TEXT',
    'last_referenced_in'    => 'TEXT',
    'last_referenced_on'    => 'NUMERIC',
    'locked'                => 'INTEGER',
    'locked_to_channel'     => 'INTEGER',
    'no_keyword_override'   => 'INTEGER',
    'noembed'               => 'INTEGER',
    'nooverride'            => 'INTEGER',
    'owner'                 => 'TEXT',
    'persist-key'           => 'INTEGER',
    'preserve_whitespace'   => 'INTEGER',
    'process-timeout'       => 'INTEGER',
    'rate_limit'            => 'INTEGER',
    'ref_count'             => 'INTEGER',
    'ref_user'              => 'TEXT',
    'require_explicit_args' => 'INTEGER',
    'requires_arguments'    => 'INTEGER',
    'type'                  => 'TEXT',
    'unquote_spaces'        => 'INTEGER',
    'usage'                 => 'TEXT',
    'use_output_queue'      => 'INTEGER',
    'workdir'               => 'TEXT',
);

my $f = PBot::DualIndexSQLiteObject->new(name => 'Factoids', filename => './greybot.sqlite3');
$f->load;
$f->create_metadata(\%factoid_metadata);

$f->begin_work;

my @files = glob 'meta/*';

foreach my $file (sort @files) {
  my $factoid = basename $file;
  print "Reading $factoid ($file)\n";

  if (grep { $_ eq $factoid } @skip) {
      print "SKIPPING $file!\n";
      next;
  }

  open my $fh, '<', $file or die "Couldn't open $file: $!\n";

  my @lines = <$fh>;
  my $fact = $lines[$#lines];
  chomp $fact;
  print "  === Got factoid [$fact]\n";

  my ($nick, $timestamp, $command, $text) = split /\s/, $fact, 4;

  $text = '' if not defined $text;

  print "  nick: [$nick], timestamp: [$timestamp], cmd: [$command], text: [$text]\n";

  if (lc $command eq 'forget') {
    print "  --- skipping factoid (deleted)\n";
    next;
  }

  if ($text =~ m/^#redirect (.*)/i) {
    $text = "/call $1";
  } else {
    $text = "/say $text";
  }

  print "  +++ Adding factoid: $factoid is $text\n";

  my $data = {
      enabled => 1,
      type       => 'text',
      action     => $text,
      owner      => $nick,
      created_on => $timestamp,
      ref_count  => 0,
      ref_user   => "nobody",
  };

  $f->add('#bash', $factoid, $data);
}

$f->end;
