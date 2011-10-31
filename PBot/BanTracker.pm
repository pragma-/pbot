# File: BanTracker.pm
# Author: pragma_
#
# Purpose: Populates and maintains channel banlists by checking mode +b on
# joining channels and by tracking modes +b and -b in channels.
#
# Does NOT do banning or unbanning.

package PBot::BanTracker;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use Data::Dumper;
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to BanTracker should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot} // Carp::croak("Missing pbot reference to BanTracker");
  $self->{pbot} = $pbot;

  $self->{banlist} = {};

  $pbot->commands->register(sub { return $self->dumpbans(@_) }, "dumpbans", 60);
}

sub dumpbans {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  my $bans = Dumper($self->{banlist});
  return $bans;
}

sub get_banlist {
  my ($self, $conn, $event) = @_;
  my $channel = lc $event->{args}[1];

  delete $self->{banlist}->{$channel};

  $self->{pbot}->logger->log("Retrieving banlist for $channel.\n");
  $conn->sl("mode $channel +bq");
}

sub get_baninfo {
  my ($self, $mask) = @_;

  foreach my $channel (keys %{ $self->{banlist} }) {
    foreach my $banmask (keys %{ $self->{banlist}{$channel} }) {
      my $banmask_key = $banmask;
      $banmask = quotemeta $banmask;

      $banmask =~ s/\\\*/.*?/g;
      $banmask =~ s/\\\?/./g;

      if($mask =~ m/^$banmask$/i) {
        my $baninfo = {};
        $baninfo->{banmask} = $banmask_key;
        $baninfo->{channel} = $channel;
        $baninfo->{owner} = $self->{banlist}{$channel}{$banmask_key}[0];
        $baninfo->{when} = $self->{banlist}{$channel}{$banmask_key}[1];
        $self->{pbot}->logger->log("get-baninfo: dump: " . Dumper($baninfo) . "\n");
        return $baninfo;
      }
    }
  }

  return undef;
}

sub on_banlistentry {
  my ($self, $conn, $event) = @_;
  my $channel   = lc $event->{args}[1];
  my $target    = lc $event->{args}[2];
  my $source    = lc $event->{args}[3];
  my $timestamp =    $event->{args}[4];

  my $ago = ago(gettimeofday - $timestamp);

  $self->{pbot}->logger->log("ban-tracker: [banlist entry] $channel: $target banned by $source $ago.\n");
  $self->{banlist}->{$channel}->{$target} = [ $source, $timestamp ];
}

sub track_mode {
  my $self = shift;
  my ($source, $mode, $target, $channel) = @_;

  if($mode eq "+b" or $mode eq "+q") {
    $self->{pbot}->logger->log("ban-tracker: $target banned by $source in $channel.\n");
    $self->{banlist}->{$channel}->{$target} = [ $source, gettimeofday ];
  }
  elsif($mode eq "-b" or $mode eq "-q") {
    $self->{pbot}->logger->log("ban-tracker: $target unbanned by $source in $channel.\n");
    delete $self->{banlist}->{$channel}->{$target};
  } else {
    $self->{pbot}->logger->log("BanTracker: Unknown mode '$mode'\n");
  }
}

1;
