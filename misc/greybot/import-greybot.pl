#!/usr/bin/env perl

# quick-and-dirty script to import greybot factoids.
#
# http://wooledge.org/~greybot/
#
# Disclaimer: this import script really IS quick-and-dirty. some bits
# of code are copied out of the PBot tree. ideally, we would instead update
# the code in the PBot tree to be more library-like.
#
# but that's a task for another day. right now i just want to get these
# greybot factoids imported As-Soon-As-Possible. isn't technical debt fun?
#
# if this script is used again in the future, ensure the PBot snippets
# that were copied over are not out-dated. time-permitting, implement
# all the TODOs in this script.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

use File::Basename;

# TODO: DualIndexSQLiteObject is the current factoids database API. It expects
# a PBot instance. We have "temporarily" copied it out of the PBot source tree
# and modified it for this import script. Ideally we should instead modify the
# file in the PBot tree.
use lib '.';
use PBot::DualIndexSQLiteObject;

# skip these factoids since they are used by
# candide for other purposes.
my @skip = qw/bash ksh check bashfaq bashpf faq pf/;

# dirtily copied from PBot/Factoids.pm for now.
# TODO: we should use PBot::Factoids instead.
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

my $factoids = PBot::DualIndexSQLiteObject->new(name => 'Factoids', filename => './greybot.sqlite3');

$factoids->load;
$factoids->create_metadata(\%factoid_metadata);

$factoids->begin_work;

my @files = glob 'meta/*';

foreach my $file (sort @files) {
  my $factoid = basename $file;

  if (grep { $_ eq $factoid } @skip) {
      print "$factoid: skipping factoid.\n";
      next;
  }

  open my $fh, '< :encoding(UTF-8)', $file or die "Couldn't open $file: $!\n";

  my @lines = <$fh>;
  my $data = $lines[$#lines];
  chomp $data;

  my ($nick, $timestamp, $command, $text) = split /\s/, $data, 4;

  if (not defined $nick or not defined $timestamp or not defined $command) {
      print "$factoid: could not parse: $data\n";
      die;
  }

  if (lc $command eq 'forget') {
    print "$factoid: skipping deleted factoid\n";
    next;
  }

  if (not defined $text) {
      print "$factoid: missing text\n";
      die;
  }

  print "nick: $nick, timestamp: $timestamp, cmd: $command, text: [$text]\n" if $ENV{DEBUG};

  if ($text =~ m/^#redirect (.*)/i) {
    $text = "/call $1";
  } else {
    $text = "/say $text";
  }

  print "adding factoid: $factoid is \"$text\"\n" if $ENV{DEBUG};

  $data = {
      enabled => 1,
      type       => 'text',
      action     => $text,
      owner      => $nick,
      created_on => $timestamp,
      ref_count  => 0,
      ref_user   => "nobody",
  };

  $factoids->add('#bash', $factoid, $data);
}

$factoids->end;
