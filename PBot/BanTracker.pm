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
  $conn->sl("mode $channel +b");
  $conn->sl("mode $channel +q");
}

sub get_baninfo {
  my ($self, $mask, $channel, $account) = @_;
  my ($bans, $ban_account);

  $account = lc $account if defined $account;

  foreach my $mode (keys %{ $self->{banlist}{$channel} }) {
    foreach my $banmask (keys %{ $self->{banlist}{$channel}{$mode} }) {
      my $banmask_key = $banmask;
      $banmask = quotemeta $banmask;

      $banmask =~ s/\\\*/.*?/g;
      $banmask =~ s/\\\?/./g;

      if($banmask =~ m/^\$a:(.*)/) {
        $ban_account = lc $1;
      } else {
        $ban_account = "";
      }

      if((defined $account and $account eq $ban_account) or $mask =~ m/^$banmask$/i) {
        if(not defined $bans) {
          $bans = [];
        }

        my $baninfo = {};
        $baninfo->{banmask} = $banmask_key;
        $baninfo->{channel} = $channel;
        $baninfo->{owner} = $self->{banlist}{$channel}{$mode}{$banmask_key}[0];
        $baninfo->{when} = $self->{banlist}{$channel}{$mode}{$banmask_key}[1];
        $baninfo->{type} = $mode;
        $self->{pbot}->logger->log("get-baninfo: dump: " . Dumper($baninfo) . "\n");

        push @$bans, $baninfo;
      }
    }
  }

  return $bans;
}

sub on_quietlist_entry {
  my ($self, $conn, $event) = @_;
  my $channel   = lc $event->{args}[1];
  my $target    = lc $event->{args}[3];
  my $source    = lc $event->{args}[4];
  my $timestamp =    $event->{args}[5];

  my $ago = ago(gettimeofday - $timestamp);

  $self->{pbot}->logger->log("ban-tracker: [quietlist entry] $channel: $target quieted by $source $ago.\n");
  $self->{banlist}->{$channel}->{'+q'}->{$target} = [ $source, $timestamp ];
}

sub on_banlist_entry {
  my ($self, $conn, $event) = @_;
  my $channel   = lc $event->{args}[1];
  my $target    = lc $event->{args}[2];
  my $source    = lc $event->{args}[3];
  my $timestamp =    $event->{args}[4];

  my $ago = ago(gettimeofday - $timestamp);

  $self->{pbot}->logger->log("ban-tracker: [banlist entry] $channel: $target banned by $source $ago.\n");
  $self->{banlist}->{$channel}->{'+b'}->{$target} = [ $source, $timestamp ];
}

sub track_mode {
  my $self = shift;
  my ($source, $mode, $target, $channel) = @_;

  if($mode eq "+b" or $mode eq "+q") {
    $self->{pbot}->logger->log("ban-tracker: $target " . ($mode eq '+b' ? 'banned' : 'quieted') . " by $source in $channel.\n");
    $self->{banlist}->{$channel}->{$mode}->{$target} = [ $source, gettimeofday ];
  }
  elsif($mode eq "-b" or $mode eq "-q") {
    $self->{pbot}->logger->log("ban-tracker: $target " . ($mode eq '-b' ? 'unbanned' : 'unquieted') . " by $source in $channel.\n");
    delete $self->{banlist}->{$channel}->{$mode eq "-b" ? "+b" : "+q"}->{$target};

    if($self->{pbot}->chanops->{unban_timeout}->find_index($channel, $target)) {
      $self->{pbot}->chanops->{unban_timeout}->remove($channel, $target);
    }
  } else {
    $self->{pbot}->logger->log("BanTracker: Unknown mode '$mode'\n");
  }
}

1;
