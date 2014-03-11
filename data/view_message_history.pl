#!/usr/bin/perl

use warnings;
use strict;

use Storable;
use Time::HiRes qw/gettimeofday/;
use Data::Dumper;
use Time::Duration;

my $mh = retrieve('message_history');

sub view_message_history {
  foreach my $mask (sort { lc $a cmp lc $b } keys %{ $mh }) {
    print '-' x 80, "\n";
    print "Checking [$mask]\n";
    print Dumper($mh->{$mask}), "\n";

    if(exists $mh->{$mask}->{nickserv_accounts}) {
      print "  Multiple nickserv accounts for $mask (", scalar keys $mh->{$mask}->{nickserv_accounts}, "): ", (join ', ', keys $mh->{$mask}->{nickserv_accounts}), "\n" if scalar keys $mh->{$mask}->{nickserv_accounts} > 1;
      foreach my $account (keys $mh->{$mask}->{nickserv_accounts}) {
        print "  Nickserv account [$account] last identified ", ago_exact(gettimeofday - $mh->{$mask}->{nickserv_accounts}->{$account}), "\n";
      }
    }

    foreach my $channel (keys %{ $mh->{$mask}->{channels} }) {
      my $length = $#{ $mh->{$mask}->{channels}->{$channel}{messages} } + 1;
      if($length <= 0) {
        print "length <= 0 for $mask in $channel\n";
        next;
      }

      my %last = %{ @{ $mh->{$mask}->{channels}->{$channel}{messages} }[$length - 1] };

      print "  [$channel] Last seen ", ago_exact(gettimeofday - $last{timestamp}), "\n";

      if(gettimeofday - $last{timestamp} >= 60 * 60 * 24 * 90) {
        print("    $mask in $channel no activity in ninety days.\n");
      }
    }

    if(scalar keys %{ $mh->{$mask} } == 0) {
      print("  [$mask] has no channels\n");
    }
  }
  print "Done.\n";
}

view_message_history;
