# File: IgnoreList.pm
# Authoer: pragma_
#
# Purpose: Manages ignore list.

package PBot::IgnoreList;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Time::HiRes qw(gettimeofday);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Commands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
    Carp::croak("Missing pbot reference to Channels");
  }

  $self->{pbot} = $pbot;
  $self->{ignore_list} = {};
  $self->{ignore_flood_counter} = 0;
  $self->{last_timestamp} = gettimeofday;
}

sub add {
  my $self = shift;
  my ($hostmask, $channel, $length) = @_;

  ${ $self->{ignore_list} }{$hostmask}{$channel} = gettimeofday + $length;
}

sub remove {
  my $self = shift;
  my ($hostmask, $channel) = @_;

  delete ${ $self->{ignore_list} }{$hostmask}{$channel};
}

sub check_ignore {
  my $self = shift;
  my ($nick, $user, $host, $channel) = @_;
  my $pbot = $self->{pbot};
  $channel = lc $channel;

  my $hostmask = "$nick!$user\@$host"; 

  my $now = gettimeofday;

  if(defined $channel) { # do not execute following if text is coming from STDIN ($channel undef)
    if($channel =~ /^#/) {
      $self->{ignore_flood_counter}++;  # TODO: make this per channel, e.g., ${ $self->{ignore_flood_counter} }{$channel}++
      $pbot->logger->log("flood_msg: $self->{ignore_flood_counter}\n");
    }

    if($self->{ignore_flood_counter} > 4) {
      $pbot->logger->log("flood_msg exceeded! [$self->{ignore_flood_counter}]\n");
      $self->{pbot}->{ignorelistcmds}->ignore_user("", "floodcontrol", "", "", ".* $channel 300");
      $self->{ignore_flood_counter} = 0;
      if($channel =~ /^#/) {
        $pbot->conn->me($channel, "has been overwhelmed.");
        $pbot->conn->me($channel, "lies down and falls asleep."); 
        return;
      } 
    }

    if($now - $self->{last_timestamp} >= 15) {
      $self->{last_timestamp} = $now;
      if($self->{ignore_flood_counter} > 0) {
        $pbot->logger->log("flood_msg reset: (was $self->{ignore_flood_counter})\n");
        $self->{ignore_flood_counter} = 0;
      }
    }
  }

  foreach my $ignored (keys %{ $self->{ignore_list} }) {
    foreach my $ignored_channel (keys %{ ${ $self->{ignore_list} }{$ignored} }) {
      $self->{pbot}->logger->log("check_ignore: comparing '$hostmask' against '$ignored' for channel '$channel'\n");
      if(($channel =~ /$ignored_channel/i) && ($hostmask =~ /$ignored/i)) {
        $self->{pbot}->logger->log("$nick!$user\@$host message ignored in channel $channel (matches [$ignored] host and [$ignored_channel] channel)\n");
        return 1;
      }
    }
  }
  return 0;
}

1;
