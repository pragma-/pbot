#!/usr/bin/env perl

# generate initial .undo file for existing factoids
# FIXME all paths throughout this file are hardcoded...

use warnings;
use strict;

use Storable;

require "../PBot/DualIndexHashObject.pm";


sub safe_filename {
  my $name = shift;
  my $safe = '';

  while ($name =~ m/(.)/gms) {
    if ($1 eq '&') {
      $safe .= '&amp;';
    } elsif ($1 eq '/') {
      $safe .= '&fslash;';
    } else {
      $safe .= $1;
    }
  }

  return $safe;
}


my $factoids = PBot::DualIndexHashObject->new(name => 'Factoids', filename => 'factoids');

$factoids->load;

foreach my $channel (sort keys %{ $factoids->hash }) {
  foreach my $trigger (sort keys %{ $factoids->hash->{$channel} }) {
    my $channel_path = $channel;
    $channel_path = 'global' if $channel_path eq '.*';

    print "Checking [$channel_path] [$trigger] ... ";
    
    my $channel_path_encoded = safe_filename $channel_path;
    my $trigger_encoded = safe_filename $trigger;

    my $undo = eval { retrieve("factlog/$trigger_encoded.$channel_path_encoded.undo"); };

    if (not $undo) {
      print "creating initial undo state to [$channel_path_encoded] [$trigger_encoded]\n";
      $undo = { idx => 0, list => [ $factoids->hash->{$channel}->{$trigger} ] };
      eval {
        store($undo, "factlog/$trigger_encoded.$channel_path_encoded.undo");
      };
      if ($@) {
        print "error: $@\n";
      }
    } else {
      print "good.\n";
    }
  }
}

print "Done.\n";
