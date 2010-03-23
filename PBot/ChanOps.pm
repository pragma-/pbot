# File: ChanOps.pm
# Authoer: pragma_
#
# Purpose: Provides channel operator status tracking and commands.

package PBot::ChanOps;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Time::HiRes qw(gettimeofday);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to ChanOps should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to ChanOps");
  }

  $self->{pbot} = $pbot;
  $self->{quieted_nicks} = {};
  $self->{unban_timeouts} = {};
  $self->{op_commands} = [];
  $self->{is_opped} = {};

  $pbot->timer->register(sub { $self->check_opped_timeouts   }, 10);
  $pbot->timer->register(sub { $self->check_quieted_timeouts }, 10);
  $pbot->timer->register(sub { $self->check_unban_timeouts   }, 10);
}

sub gain_ops {
  my $self = shift;
  my $channel = shift;
  
  if(not exists ${ $self->{is_opped} }{$channel}) {
    $self->{pbot}->conn->privmsg("chanserv", "op $channel");
  } else {
    $self->perform_op_commands();
  }
}

sub lose_ops {
  my $self = shift;
  my $channel = shift;
  $self->{pbot}->conn->privmsg("chanserv", "op $channel -" . $self->{pbot}->botnick);
  if(exists ${ $self->{is_opped} }{$channel}) {
    ${ $self->{is_opped} }{$channel}{timeout} = gettimeofday + 60; # try again in 1 minute if failed
  }
}

sub perform_op_commands {
  my $self = shift;
  $self->{pbot}->logger->log("Performing op commands...\n");
  foreach my $command (@{ $self->{op_commands} }) {
    if($command =~ /^mode (.*?) (.*)/i) {
      $self->{pbot}->conn->mode($1, $2);
      $self->{pbot}->logger->log("  executing mode $1 $2\n");
    } elsif($command =~ /^kick (.*?) (.*?) (.*)/i) {
      $self->{pbot}->conn->kick($1, $2, $3) unless $1 =~ /\Q$self->{pbot}->botnick\E/i;
      $self->{pbot}->logger->log("  executing kick on $1 $2 $3\n");
    }
    shift(@{ $self->{op_commands} });
  }
  $self->{pbot}->logger->log("Done.\n");
}

sub quiet_nick {
  my $self = shift;
  my ($nick, $channel) = @_;
  unshift @{ $self->{op_commands} }, "mode $channel +q $nick!*@*";
  $self->gain_ops($channel);
}

sub unquiet_nick {
  my $self = shift;
  my ($nick, $channel) = @_;
  unshift @{ $self->{op_commands} }, "mode $channel -q $nick!*@*";
  $self->gain_ops($channel);
}

sub quiet_nick_timed {
  my $self = shift;
  my ($nick, $channel, $length) = @_;

  $self->quiet_nick($nick, $channel);
  ${ $self->{quieted_nicks} }{$nick}{time} = gettimeofday + $length;
  ${ $self->{quieted_nicks} }{$nick}{channel} = $channel;
}

sub check_quieted_timeouts {
  my $self = shift;
  my $now = gettimeofday();

  foreach my $nick (keys %{ $self->{quieted_nicks} }) {
    if($self->{quieted_nicks}->{$nick}{time} < $now) {
      $self->{pbot}->logger->log("Unquieting $nick\n");
      $self->unquiet_nick($nick, $self->{quieted_nicks}->{$nick}{channel});
      delete $self->{quieted_nicks}->{$nick};
      $self->{pbot}->conn->privmsg($nick, "You may speak again.");
    } else {
      #my $timediff = $quieted_nicks{$nick}{time} - $now;
      #$logger->log "quiet: $nick has $timediff seconds remaining\n"
    }
  }
}

sub check_opped_timeouts {
  my $self = shift;
  my $now = gettimeofday();

  foreach my $channel (keys %{ $self->{is_opped} }) {
    if($self->{is_opped}->{$channel}{timeout} < $now) {
      $self->lose_ops($channel);
    } else {
      # my $timediff = $is_opped{$channel}{timeout} - $now;
      # $logger->log("deop $channel in $timediff seconds\n");
    }
  }
}

sub check_unban_timeouts {
  my $self = shift;
  my $now = gettimeofday();

  foreach my $ban (keys %{ $self->{unban_timeouts} }) {
    if($self->{unban_timeouts}->{$ban}{timeout} < $now) {
      unshift @{ $self->{op_commands} }, "mode " . $self->{unban_timeout}->{$ban}{channel} . " -b $ban";
      $self->gain_ops($self->{unban_timeouts}->{$ban}{channel});
      delete $self->{unban_timeouts}->{$ban};
    } else {
      #my $timediff = $unban_timeout{$ban}{timeout} - $now;
      #$logger->log("$unban_timeout{$ban}{channel}: unban $ban in $timediff seconds\n");
    }
  }
}

1;
