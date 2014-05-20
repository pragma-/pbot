# File: SQLiteLogger
# Author: pragma_
#
# Purpose: Logs SQLite trace messages to Logger.pm with profiling of elapsed
# time between messages.

package PBot::SQLiteLogger;

use strict;
use warnings;

use Carp;
use Time::HiRes qw(gettimeofday);

sub new
{
  my ($class, %conf) = @_;
  my $self = {};
  $self->{buf} = '';
  $self->{timestamp} = gettimeofday;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference in " . __FILE__);
  return bless $self, $class;
}

sub log
{
  my $self = shift;
  $self->{buf} .= shift;

  # DBI feeds us pieces at a time, so accumulate a complete line
  # before outputing
  if($self->{buf} =~ tr/\n//) {
    $self->log_message;
    $self->{buf} = '';
  }
}

sub log_message {
  my $self = shift;
  my $now = gettimeofday;
  my $elapsed = $now - $self->{timestamp};
  $elapsed = sprintf '%10.4f', $elapsed;
  $self->{pbot}->{logger}->log("$elapsed : $self->{buf}");
  $self->{timestamp} = $now;
}

sub close {
  my $self = shift;
  if($self->{buf}) {
    $self->log_message;
    $self->{buf} = '';
  }
}

1;
