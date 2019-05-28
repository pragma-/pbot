# File: ChanOpCommands.pm
# Author: pragma_
#
# Purpose: Channel operator command subroutines.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::ChanOpCommands;

use warnings;
use strict;

use Carp ();
use Time::Duration;

use PBot::Utils::ParseDate;

sub new {
  if (ref($_[1]) eq 'HASH') {
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
  if (not defined $pbot) {
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
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($target, $channel, $length) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  $channel = '' if not defined $channel;
  $length = '' if not defined $length;

  if (not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  if ($channel !~ m/^#/) {
    $length = "$channel $length";
    $length = undef if $length eq ' ';
    $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from;
  }

  $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from if not defined $channel or not length $channel;

  if (not defined $target) {
    return "/msg $nick Usage: ban <mask> [channel [timeout (default: 24 hours)]]";
  }

  if (not defined $length) {
    $length = 60 * 60 * 24; # 24 hours
  } else {
    my $error;
    ($length, $error) = parsedate($length);
    return $error if defined $error;
  }

  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
  return "I don't think so." if $target =~ /^\Q$botnick\E!/i;

  if (not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
    return "/msg $nick You are not an admin for $channel.";
  }

  my @targets = split /,/, $target;
  my $immediately = @targets > 1 ? 0 : 1;
  foreach my $t (@targets) {
    $self->{pbot}->{chanops}->ban_user_timed($t, $channel, $length, $immediately);
  }

  if (not $immediately) {
    $self->{pbot}->{chanops}->check_ban_queue;
  }

  if ($length > 0) {
    $length = duration($length);
  } else {
    $length = 'all eternity';
  }

  return "/msg $nick $target banned in $channel for $length";
}

sub unban_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  my ($target, $channel, $immediately) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  if (defined $target and defined $channel and $channel !~ /^#/) {
    my $temp = $target;
    $target = $channel;
    $channel = $temp;
  }

  if (not defined $target) {
    return "/msg $nick Usage: unban <nick/mask> [[channel] [false value to use unban queue]]";
  }

  $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from if not defined $channel;
  $immediately = 1 if not defined $immediately;

  return "/msg $nick Usage for /msg: unban <nick/mask> <channel> [false value to use unban queue]" if $channel !~ /^#/;

  if (not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
    return "/msg $nick You are not an admin for $channel.";
  }

  my @targets = split /,/, $target;
  $immediately = 0 if @targets > 1;

  foreach my $t (@targets) {
    $self->{pbot}->{chanops}->unban_user($t, $channel, $immediately);
  }

  if (@targets > 1) {
    $self->{pbot}->{chanops}->check_unban_queue;
  }

  return "/msg $nick $target has been unbanned from $channel.";
}

sub mute_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($target, $channel, $length) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  if (not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  if (not defined $channel and $from !~ m/^#/) {
    return "/msg $nick Usage from private message: mute <mask> <channel> [timeout (default: 24 hours)]";
  }

  if ($channel !~ m/^#/) {
    $length = "$channel $length";
    $length = undef if $length eq ' ';
    $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from;
  }

  $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from if not defined $channel;

  if ($channel !~ m/^#/) {
    return "/msg $nick Please specify a channel.";
  }

  if (not defined $target) {
    return "/msg $nick Usage: mute <mask> [channel [timeout (default: 24 hours)]]";
  }

  if (not defined $length) {
    $length = 60 * 60 * 24; # 24 hours
  } else {
    my $error;
    ($length, $error) = parsedate($length);
    return $error if defined $error;
  }

  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
  return "I don't think so." if $target =~ /^\Q$botnick\E!/i;

  if (not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
    return "/msg $nick You are not an admin for $channel.";
  }

  my @targets = split /,/, $target;
  my $immediately = @targets > 1 ? 0 : 1;
  foreach my $t (@targets) {
    $self->{pbot}->{chanops}->mute_user_timed($t, $channel, $length, $immediately);
  }

  if (not $immediately) {
    $self->{pbot}->{chanops}->check_ban_queue;
  }

  if ($length > 0) {
    $length = duration($length);
  } else {
    $length = 'all eternity';
  }

  return "/msg $nick $target muted in $channel for $length";
}

sub unmute_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  my ($target, $channel, $immediately) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  if (defined $target and defined $channel and $channel !~ /^#/) {
    my $temp = $target;
    $target = $channel;
    $channel = $temp;
  }

  if (not defined $target) {
    return "/msg $nick Usage: unmute <nick/mask> [[channel] [false value to use unban queue]]";
  }

  $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from if not defined $channel;
  $immediately = 1 if not defined $immediately;

  return "/msg $nick Usage for /msg: unmute <nick/mask> <channel> [false value to use unban queue]" if $channel !~ /^#/;

  if (not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
    return "/msg $nick You are not an admin for $channel.";
  }

  my @targets = split /,/, $target;
  $immediately = 0 if @targets > 1;

  foreach my $t (@targets) {
    $self->{pbot}->{chanops}->unmute_user($t, $channel, $immediately);
  }

  if (@targets > 1) {
    $self->{pbot}->{chanops}->check_unban_queue;
  }

  return "/msg $nick $target has been unmuted in $channel.";
}

sub kick_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  my ($channel, $victim, $reason);

  if (not $from =~ /^#/) {
    # used in private message
    if (not $arguments =~ s/^(^#\S+) (\S+)\s*//) {
      return "/msg $nick Usage from private message: kick <channel> <nick> [reason]";
    }
    ($channel, $victim) = ($1, $2);
  } else {
    # used in channel
    if ($arguments =~ s/^(#\S+)\s+(\S+)\s*//) {
      ($channel, $victim) = ($1, $2);
    } elsif ($arguments =~ s/^(\S+)\s*//) {
      ($victim, $channel) = ($1, exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from);
    } else {
      return "/msg $nick Usage: kick [channel] <nick> [reason]";
    }
  }

  $reason = $arguments;

  # If the user is too stupid to remember the order of the arguments,
  # we can help them out by seeing if they put the channel in the reason.
  if ($reason =~ s/^(#\S+)\s*//) {
    $channel = $1;
  }

  if (not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
    return "/msg $nick You are not an admin for $channel.";
  }

  my @insults;
  if (not length $reason) {
    if (open my $fh, '<',  $self->{pbot}->{registry}->get_value('general', 'module_dir') . '/insults.txt') {
      @insults = <$fh>;
      close $fh;
      $reason = $insults[rand @insults];
      $reason =~ s/\s+$//;
    } else {
      $reason = 'Bye!';
    }
  }

  my @nicks = split /,/, $victim;
  my $i = 0;
  foreach my $n (@nicks) {
    $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $n $reason");
    if (@insults) {
      $reason = $insults[rand @insults];
      $reason =~ s/\s+$//;
    }
    last if ++$i >= 5;
  }

  $self->{pbot}->{chanops}->gain_ops($channel);

  return "";
}

1;
