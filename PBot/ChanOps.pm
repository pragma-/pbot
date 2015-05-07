# File: ChanOps.pm
# Author: pragma_
#
# Purpose: Provides channel operator status tracking and commands.

package PBot::ChanOps;

use warnings;
use strict;

use PBot::ChanOpCommands;
use Time::HiRes qw(gettimeofday);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to ChanOps");

  $self->{unban_timeout} = PBot::DualIndexHashObject->new(
    pbot => $self->{pbot},
    name => 'Unban Timeouts',
    filename => $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/unban_timeouts'
  );

  $self->{unban_timeout}->load;

  $self->{op_commands} = {};
  $self->{is_opped} = {};
  $self->{op_requested} = {};

  $self->{commands} = PBot::ChanOpCommands->new(pbot => $self->{pbot});

  $self->{pbot}->{registry}->add_default('text', 'general', 'deop_timeout', $conf{'deop_timeout'} // 300);

  $self->{pbot}->{timer}->register(sub { $self->check_opped_timeouts }, 10);
  $self->{pbot}->{timer}->register(sub { $self->check_unban_timeouts }, 10);
}

sub gain_ops {
  my $self = shift;
  my $channel = shift;
  
  return if exists $self->{op_requested}->{$channel};
  return if not exists $self->{pbot}->{channels}->{channels}->hash->{$channel} or not $self->{pbot}->{channels}->{channels}->hash->{$channel}{chanop};

  if(not exists $self->{is_opped}->{$channel}) {
    $self->{pbot}->{conn}->privmsg("chanserv", "op $channel");
    $self->{op_requested}->{$channel} = scalar gettimeofday;
  } else {
    $self->perform_op_commands($channel);
  }
}

sub lose_ops {
  my $self = shift;
  my $channel = shift;
  $self->{pbot}->{conn}->privmsg("chanserv", "op $channel -" . $self->{pbot}->{registry}->get_value('irc', 'botnick'));
}

sub add_op_command {
  my ($self, $channel, $command) = @_;
  return if not exists $self->{pbot}->{channels}->{channels}->hash->{$channel} or not $self->{pbot}->{channels}->{channels}->hash->{$channel}{chanop};
  push @{ $self->{op_commands}->{$channel} }, $command;
}

sub perform_op_commands {
  my $self = shift;
  my $channel = shift;
  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

  $self->{pbot}->{logger}->log("Performing op commands...\n");
  while(my $command = shift @{ $self->{op_commands}->{$channel} }) {
    if($command =~ /^mode (.*?) (.*)/i) {
      $self->{pbot}->{conn}->mode($1, $2);
      $self->{pbot}->{logger}->log("  executing mode [$1] [$2]\n");
    } elsif($command =~ /^kick (.*?) (.*?) (.*)/i) {
      $self->{pbot}->{conn}->kick($1, $2, $3) unless $1 =~ /\Q$botnick\E/i;
      $self->{pbot}->{logger}->log("  executing kick on $1 $2 $3\n");
    }
  }
  $self->{pbot}->{logger}->log("Done.\n");
}

sub ban_user {
  my $self = shift;
  my ($mask, $channel) = @_;

  $self->add_op_command($channel, "mode $channel +b $mask");
  $self->gain_ops($channel);
}

sub unban_user {
  my $self = shift;
  my ($mask, $channel) = @_;
  $self->{pbot}->{logger}->log("Unbanning $channel $mask\n");
  if($self->{unban_timeout}->find_index($channel, $mask)) {
    $self->{unban_timeout}->hash->{$channel}->{$mask}{timeout} = gettimeofday + 7200; # try again in 2 hours if unban doesn't immediately succeed
    $self->{unban_timeout}->save;
  }
  $self->add_op_command($channel, "mode $channel -b $mask");
  $self->gain_ops($channel);
}

sub ban_user_timed {
  my $self = shift;
  my ($mask, $channel, $length) = @_;

  $mask .= '!*@*' if $mask !~ m/[\$!@]/;
  $self->ban_user($mask, $channel);
  if ($length > 0) {
    $self->{unban_timeout}->hash->{$channel}->{$mask}{timeout} = gettimeofday + $length;
    $self->{unban_timeout}->save;
  }
}

sub join_channel {
  my ($self, $channel) = @_;

  $self->{pbot}->{event_dispatcher}->dispatch_event('pbot.join', { channel => $channel });
  $self->{pbot}->{conn}->join($channel);

  delete $self->{is_opped}->{$channel};
  delete $self->{op_requested}->{$channel};

  if (exists $self->{pbot}->{channels}->{channels}->hash->{$channel} 
      and exists $self->{pbot}->{channels}->{channels}->hash->{$channel}{permop} 
      and $self->{pbot}->{channels}->{channels}->hash->{$channel}{permop}) {
    $self->gain_ops($channel);
  }
}

sub part_channel {
  my ($self, $channel) = @_;

  $self->{pbot}->{event_dispatcher}->dispatch_event('pbot.part', { channel => $channel });
  $self->{pbot}->{conn}->part($channel);

  delete $self->{is_opped}->{$channel};
  delete $self->{op_requested}->{$channel};
}

sub check_unban_timeouts {
  my $self = shift;

  return if not $self->{pbot}->{joined_channels};

  my $now = gettimeofday();

  foreach my $channel (keys %{ $self->{unban_timeout}->hash }) {
    foreach my $mask (keys %{ $self->{unban_timeout}->hash->{$channel} }) {
      if($self->{unban_timeout}->hash->{$channel}->{$mask}{timeout} < $now) {
        $self->unban_user($mask, $channel);
      }
    }
  }
}

sub check_opped_timeouts {
  my $self = shift;
  my $now = gettimeofday();

  foreach my $channel (keys %{ $self->{is_opped} }) {
    if($self->{is_opped}->{$channel}{timeout} < $now) {
      unless (exists $self->{pbot}->{channels}->{channels}->hash->{$channel} 
          and exists $self->{pbot}->{channels}->{channels}->hash->{$channel}{permop} 
          and $self->{pbot}->{channels}->{channels}->hash->{$channel}{permop}) {
        $self->lose_ops($channel);
        delete $self->{is_opped}->{$channel}; # assume chanserv is alive and deop will succeed
      }
    } else {
      # my $timediff = $self->{is_opped}->{$channel}{timeout} - $now;
      # $self->{pbot}->{logger}->log("deop $channel in $timediff seconds\n");
    }
  }

  foreach my $channel (keys %{ $self->{op_requested} }) {
    if ($now - $self->{op_requested}->{$channel} > 60 * 5) {
      $self->{pbot}->{logger}->log("5 minutes since OP request for $channel and no OP yet; trying again ...\n");
      delete $self->{op_requested}->{$channel};
      $self->gain_ops($channel);
    }
  }
}

1;
