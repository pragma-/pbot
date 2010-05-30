# File: ChanOps.pm
# Author: pragma_
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
  $self->{quieted_masks} = {};
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
    $self->{is_opped}->{$channel}{timeout} = gettimeofday + 300; # assume we're going to be opped
    $self->{pbot}->{irc}->flush_output_queue();
    $self->{pbot}->{irc}->do_one_loop();
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
  $self->{pbot}->{irc}->flush_output_queue();
  $self->{pbot}->{irc}->do_one_loop();
  $self->{pbot}->logger->log("Done.\n");
}

sub quiet_user {
  my $self = shift;
  my ($mask, $channel) = @_;
  unshift @{ $self->{op_commands} }, "mode $channel +b $mask";
  $self->gain_ops($channel);
}

sub unquiet_user {
  my $self = shift;
  my ($mask, $channel) = @_;
  unshift @{ $self->{op_commands} }, "mode $channel -b $mask";
  $self->gain_ops($channel);
}

sub quiet_user_timed {
  my $self = shift;
  my ($mask, $channel, $length) = @_;

  $self->quiet_user($mask, $channel);
  ${ $self->{quieted_masks} }{$mask}{time} = gettimeofday + $length;
  ${ $self->{quieted_masks} }{$mask}{channel} = $channel;
}

sub check_quieted_timeouts {
  my $self = shift;
  my $now = gettimeofday();

  foreach my $mask (keys %{ $self->{quieted_masks} }) {
    if($self->{quieted_masks}->{$mask}{time} < $now) {
      $self->{pbot}->logger->log("Unquieting $mask\n");
      $self->unquiet_mask($mask, $self->{quieted_masks}->{$mask}{channel});
      delete $self->{quieted_masks}->{$mask};
    } else {
      #my $timediff = $quieted_masks{$mask}{time} - $now;
      #$logger->log "quiet: $mask has $timediff seconds remaining\n"
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
