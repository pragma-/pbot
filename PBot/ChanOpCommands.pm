# File: ChanOpCommands.pm
# Author: pragma_
#
# Purpose: Channel operator command subroutines.

package PBot::ChanOpCommands;

use warnings;
use strict;

use Carp ();
use Time::Duration;

use PBot::Utils::ParseDate;

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to ChanOpCommands should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to ChanOpCommands");
  }

  $self->{pbot} = $pbot;
  
  $pbot->{commands}->register(sub { return $self->ban_user(@_)      },       "ban",        10);
  $pbot->{commands}->register(sub { return $self->unban_user(@_)    },       "unban",      10);
  $pbot->{commands}->register(sub { return $self->mute_user(@_)     },       "mute",       10);
  $pbot->{commands}->register(sub { return $self->unmute_user(@_)   },       "unmute",     10);
  $pbot->{commands}->register(sub { return $self->kick_user(@_)     },       "kick",       10);
}

sub ban_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($target, $channel, $length) = split(/\s+/, $arguments, 3);

  if(not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  if ($channel !~ m/^#/) {
    $length = "$channel $length";
    $length = undef if $length eq ' ';
    $channel = $from;
  }

  $channel = $from if not defined $channel;

  if(not defined $target) {
    return "/msg $nick Usage: ban <mask> [channel [timeout (default: 24 hours)]]";
  }

  if(not defined $length) {
    $length = 60 * 60 * 24; # 24 hours
  } else {
    my $error;
    ($length, $error) = parsedate($length);
    return $error if defined $error;
  }

  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
  return "I don't think so." if $target =~ /^\Q$botnick\E!/i;

  $self->{pbot}->{chanops}->ban_user_timed($target, $channel, $length);

  if ($length > 0) {
    $length = duration($length);
  } else {
    $length = 'all eternity';
  }

  return "/msg $nick $target banned in $channel for $length";
}

sub unban_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  my ($target, $channel) = split / /, $arguments;

  if(not defined $target) {
    return "/msg $nick Usage: unban <mask> [channel]";
  }

  $channel = $from if not defined $channel;
  
  return "/msg $nick Usage for /msg: unban $target <channel>" if $channel !~ /^#/;

  $self->{pbot}->{chanops}->unban_user($target, $channel);
  return "/msg $nick $target has been unbanned from $channel.";
}

sub mute_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($target, $channel, $length) = split(/\s+/, $arguments, 3);

  if(not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  if (not defined $channel and $from !~ m/^#/) {
    return "/msg $nick Usage from private message: mute <mask> <channel> [timeout (default: 24 hours)]";
  }

  if ($channel !~ m/^#/) {
    $length = "$channel $length";
    $length = undef if $length eq ' ';
    $channel = $from;
  }

  $channel = $from if not defined $channel;

  if ($channel !~ m/^#/) {
    return "/msg $nick Please specify a channel.";
  }

  if(not defined $target) {
    return "/msg $nick Usage: mute <mask> [channel [timeout (default: 24 hours)]]";
  }

  if(not defined $length) {
    $length = 60 * 60 * 24; # 24 hours
  } else {
    my $error;
    ($length, $error) = parsedate($length);
    return $error if defined $error;
  }

  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
  return "I don't think so." if $target =~ /^\Q$botnick\E!/i;

  $self->{pbot}->{chanops}->mute_user_timed($target, $channel, $length);

  if ($length > 0) {
    $length = duration($length);
  } else {
    $length = 'all eternity';
  }

  return "/msg $nick $target muted in $channel for $length";
}

sub unmute_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  my ($target, $channel) = split / /, $arguments;

  if(not defined $target) {
    return "/msg $nick Usage: unmute <mask> [channel]";
  }

  $channel = $from if not defined $channel;

  return "/msg $nick Usage for /msg: unmute $target <channel>" if $channel !~ /^#/;

  $self->{pbot}->{chanops}->unmute_user($target, $channel);
  return "/msg $nick $target has been unmuted in $channel.";
}

sub kick_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  my ($channel, $victim, $reason);

  if(not $from =~ /^#/) {
    # used in private message
    if(not $arguments =~ s/^(^#\S+) (\S+)\s*//) {
      return "/msg $nick Usage from private message: kick <channel> <nick> [reason]";
    }
    ($channel, $victim) = ($1, $2);
  } else {
    # used in channel
    if(not $arguments =~ s/^(\S+)\s*//) {
      return "/msg $nick Usage: kick <nick> [reason]";
    }
    $victim = $1;
    $channel = $from;
  }

  $reason = $arguments;

  if (not length $reason) {
    if (open my $fh, '<',  $self->{pbot}->{registry}->get_value('general', 'module_dir') . '/insults.txt') {
      my @insults = <$fh>;
      close $fh;
      $reason = $insults[rand @insults];
      chomp $reason;
    } else {
      $reason = 'Bye!';
    }
  }

  $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $victim $reason");
  $self->{pbot}->{chanops}->gain_ops($channel);
  return "/msg $nick Kicking $victim channel $channel with reason '$reason'";
}

1;
