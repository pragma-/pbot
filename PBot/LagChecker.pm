# File: LagChecker.pm
# Author: pragma_
#
# Purpose: sends PING command to IRC server and times duration for PONG reply in
# order to maintain lag history and average.

package PBot::LagChecker;

use warnings;
use strict;

use feature 'switch';

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Time::HiRes qw(gettimeofday tv_interval);
use Time::Duration;
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to LagChecker should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to LagChecker");
  }

  $self->{pbot} = $pbot;

  $self->{LAG_HISTORY_MAX} = 3;        # maximum number of lag history entries to retain
  $self->{LAG_THRESHOLD} = 2;          # lagging is true if lag_average reaches or exceeds this threshold, in seconds
  $self->{LAG_HISTORY_INTERVAL} = 10;  # how often to send PING, in seconds

  $self->{lag_average} = undef;        # average of entries in lag history, in seconds
  $self->{lag_string} = undef;         # string representation of lag history and lag average
  $self->{lag_history} = [];           # history of previous PING/PONG timings
  $self->{pong_received} = undef;      # tracks pong replies; undef if no ping sent; 0 if ping sent but no pong reply yet; 1 if ping/pong completed

  $pbot->timer->register(sub { $self->send_ping }, $self->{LAG_HISTORY_INTERVAL});

  $pbot->commands->register(sub { return $self->lagcheck(@_) }, "lagcheck", 0);
}

sub send_ping {
  my $self = shift;

  return unless defined $self->{pbot}->conn;

  $self->{ping_send_time} = [gettimeofday];
  $self->{pong_received} = 0;
  $self->{pbot}->conn->sl("PING :lagcheck");
}

sub on_pong {
  my $self = shift;

  $self->{pong_received} = 1;

  my $elapsed = tv_interval($self->{ping_send_time});
  push @{ $self->{lag_history} }, [ $self->{ping_send_time}[0], $elapsed ];

  my $len = @{ $self->{lag_history} };

  if($len > $self->{LAG_HISTORY_MAX}) {
    shift @{ $self->{lag_history} };
    $len--;
  }

  $self->{lag_string} = "";
  my $comma = "";

  my $lag_total = 0;
  foreach my $entry (@{ $self->{lag_history} }) {
    my ($send_time, $lag_result) = @{ $entry };

    $lag_total += $lag_result;
    my $ago = ago(gettimeofday - $send_time);
    $self->{lag_string} .= $comma . "[$ago] $lag_result";
    $comma = "; ";
  }

  $self->{lag_average} = $lag_total / $len;
  $self->{lag_string} .= "; average: $self->{lag_average}";
}

sub lagging {
  my $self = shift;

  if(defined $self->{pong_received} and $self->{pong_received} == 0) {
      # a ping has been sent (pong_received is not undef) and no pong has been received yet
      my $elapsed = tv_interval($self->{ping_send_time});
      return $elapsed >= $self->{LAG_THRESHOLD};
  }

  return 0 if not defined $self->{lag_average};
  return $self->{lag_average} >= $self->{LAG_THRESHOLD};
}

sub lagstring {
  my $self = shift;

  my $lag = $self->{lag_string} || "initializing";
  return $lag;
}

sub lagcheck {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(defined $self->{pong_received} and $self->{pong_received} == 0) {
      # a ping has been sent (pong_received is not undef) and no pong has been received yet
      my $elapsed = tv_interval($self->{ping_send_time});
      my $lag_total = $elapsed;
      my $len = @{ $self->{lag_history} };

      my $lagstring = "";
      my $comma = "";

      foreach my $entry (@{ $self->{lag_history} }) {
          my ($send_time, $lag_result) = @{ $entry };

          $lag_total += $lag_result;
          my $ago = ago(gettimeofday - $send_time);
          $lagstring .= $comma . "[$ago] $lag_result";
          $comma = "; ";
      }

      $lagstring .= $comma . "[waiting for pong] $elapsed";

      my $average = $lag_total / ($len + 1);
      $lagstring .= "; average: $average}";
      return $lagstring;
  }

  return "My lag: " . $self->lagstring;
}

1;
