# File: Timer.pm
# Author: pragma_
#
# Purpose: Provides functionality to register and execute one or more subroutines every X seconds.
#
# Caveats: Uses ALARM signal and all its issues.

package PBot::Timer;

use warnings;
use strict;

use Carp ();

our $min_timeout = 10;
our $max_seconds = 1000000;
our $seconds = 0;
our @timer_funcs;

$SIG{ALRM} = sub { 
  $seconds += $min_timeout; 
  alarm $min_timeout; 

  # print "ALARM! $seconds $min_timeout\n"; 
  
  # call timer func subroutines
  foreach my $func (@timer_funcs) { &$func; }
  
  # prevent $seconds over-flow
  $seconds -= $max_seconds if $seconds > $max_seconds; 
};

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Timer should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $timeout = delete $conf{timeout};
  $timeout = 10 unless defined $timeout;

  my $name = delete $conf{name};
  $name = "Unnamed $timeout Second Timer" unless defined $name;

  my $self = {
    handlers => [],

    name => $name,
    timeout => $timeout,
    enabled => 0,
  };

  bless $self, $class;

  $min_timeout = $timeout if $timeout < $min_timeout;

  # alarm signal handler (poor-man's timer)
  $self->{timer_func} = sub { on_tick_handler($self) };

  return $self;
}

sub start {
  my $self = shift;
  # print "Starting Timer $self->{name} $self->{timeout} $self->{enabled}\n";
  $self->{enabled} = 1;
  push @timer_funcs, $self->{timer_func};
  alarm $min_timeout;
}

sub stop {
  my $self = shift;
  # print "Stopping timer $self->{name}\n";
  $self->{enabled} = 0;
  @timer_funcs = grep { $_ != $self->{timer_func} } @timer_funcs;
}

sub on_tick_handler {
  my $self = shift;
  my $elapsed = 0;

  # print "-----\n";
  # print "on tick handler for $self->{name}\n";

  if($self->{enabled}) {
    if($#{ $self->{handlers} } > -1) {
      # call handlers supplied via register() if timeout for each has elapsed
      foreach my $func (@{ $self->{handlers} }) {
        if(defined $func->{last}) {
          $func->{last} -= $max_seconds if $seconds < $func->{last}; # handle wrap-around of $seconds

          if($seconds - $func->{last} >= $func->{timeout}) {
            $func->{last} = $seconds;
            $elapsed = 1;
          }
        } else {
          $func->{last} = $seconds;
          $elapsed = 1;
        }

        if($elapsed) {
          &{ $func->{subref} }($self);
          $elapsed = 0;
        }
      }
    } else {
      # call default overridable handler if timeout has elapsed
      if(defined $self->{last}) {
        # print "$self->{name} last = $self->{last}, seconds: $seconds, timeout: $self->{timeout} " . ($seconds - $self->{last}) . "\n";

        $self->{last} -= $max_seconds if $seconds < $self->{last}; # handle wrap-around

        if($seconds - $self->{last} >= $self->{timeout}) {
          $elapsed = 1;
          $self->{last} = $seconds;
        }
      } else {
        # print "New addition for $self->{name}\n";
        $elapsed = 1;
        $self->{last} = $seconds;
      }

      if($elapsed) {
        $self->on_tick();
        $elapsed = 0;
      }
    }
  }
  # print "-----\n";
}

# overridable method, executed whenever timeout is triggered
sub on_tick {
  my $self = shift;

  print "Tick! $self->{name} $self->{timeout} $self->{last} $seconds\n";
}

sub register {
  my $self = shift;
  my ($ref, $timeout, $id) = @_;

  Carp::croak("Must pass subroutine reference to register()") if not defined $ref;

  # TODO: Check if subref already exists in handlers?

  $timeout = 300 if not defined $timeout; # set default value of 5 minutes if not defined
  $id = 'timer' if not defined $id;

  my $h = { subref => $ref, timeout => $timeout, id => $id };
  push @{ $self->{handlers} }, $h;

  # print "-- Registering timer $ref [$id] at $timeout seconds\n";

  if($timeout < $min_timeout) {
    $min_timeout = $timeout;
  }

  if($self->{enabled}) {
    alarm $min_timeout;
  }
}

sub unregister {
  my $self = shift;
  my $id;

  if(@_) {
    $id = shift;
  } else {
    Carp::croak("Must pass timer id to unregister()");
  }

  @{ $self->{handlers} } = grep { $_->{id} ne $id } @{ $self->{handlers} };
}

sub update_interval {
  my ($self, $id, $interval) = @_;

  foreach my $h (@{ $self->{handlers} }) {
    if($h->{id} eq $id) {
      $h->{timeout} = $interval;
      last;
    }
  }
}

1;
