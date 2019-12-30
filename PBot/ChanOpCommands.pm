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

use feature 'unicode_strings';

use Carp ();
use Time::Duration;
use Time::HiRes qw/gettimeofday/;

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
  $pbot->{commands}->register(sub { return $self->checkban(@_)      },       "checkban",    0);
  $pbot->{commands}->register(sub { return $self->checkmute(@_)     },       "checkmute",   0);
  $pbot->{commands}->register(sub { return $self->mode(@_)          },       "mode",       40);
  $pbot->{commands}->register(sub { return $self->invite(@_)        },       "invite",     10);
}

sub invite {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (not length $arguments) {
    return "Usage: invite [channel] <nick>";
  }

  # add current channel as default channel
  if ($stuff->{arglist}[0] !~ m/^#/) {
    if ($from =~ m/^#/) {
      unshift @{$stuff->{arglist}}, $from;
    } else {
      return "Usage from private message: invite <channel> <nick>";
    }
  }

  my ($channel, $target) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);
  $self->{pbot}->{chanops}->add_op_command($channel, "sl invite $target $channel");
  $self->{pbot}->{chanops}->gain_ops($channel);
  return "";
}

sub mode {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (not length $arguments) {
    return "Usage: mode [channel] <arguments>";
  }

  # add current channel as default channel
  if ($stuff->{arglist}[0] !~ m/^#/) {
    if ($from =~ m/^#/) {
      unshift @{$stuff->{arglist}}, $from;
    } else {
      return "Usage from private message: mode <channel> <arguments>";
    }
  }

  my ($channel, $modes, $args) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);
  my @targets = split /\s+/, $args;
  my $modifier;
  my $i = 0;
  my $arg = 0;

  my ($new_modes, $new_targets) = ("", "");
  my $max_modes = $self->{pbot}->{ircd}->{MODES} // 1;

  while ($modes =~ m/(.)/g) {
    my $mode = $1;

    if ($mode eq '-' or $mode eq '+') {
      $modifier = $mode;
      $new_modes .= $mode;
      next;
    }

    my $target = $targets[$arg++] // "";

    if (($mode eq 'v' or $mode eq 'o') and $target =~ m/\*/) {
      # wildcard used; find all matching nicks; test against whitelist, etc
      my $q_target = lc quotemeta $target;
      $q_target =~ s/\\\*/.*/g;
      $channel = lc $channel;

      if (not exists $self->{pbot}->{nicklist}->{nicklist}->{$channel}) {
        return "I have no nicklist for channel $channel; cannot use wildcard.";
      }

      foreach my $n (keys %{$self->{pbot}->{nicklist}->{nicklist}->{$channel}}) {
        if ($n =~ m/^$q_target$/) {
          my $nick_data = $self->{pbot}->{nicklist}->{nicklist}->{$channel}->{$n};

          if ($modifier eq '-') {
            # removing mode -- check against whitelist, etc
            next if $n eq $self->{pbot}->{registry}->get_value('irc', 'botnick');
            next if $self->{pbot}->{antiflood}->whitelisted($channel, $nick_data->{hostmask});
            next if $self->{pbot}->{admins}->loggedin($channel, $nick_data->{hostmask});
          }

          # skip nick if already has mode set/unset
          if ($modifier eq '+') {
            next if exists $nick_data->{"+$mode"};
          } else {
            next unless exists $nick_data->{"+$mode"};
          }

          $new_modes = $modifier if not length $new_modes;
          $new_modes .= $mode;
          $new_targets .= "$self->{pbot}->{nicklist}->{nicklist}->{$channel}->{$n}->{nick} ";
          $i++;

          if ($i == $max_modes) {
            $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $new_modes $new_targets");
            $new_modes = "";
            $new_targets = "";
            $i = 0;
          }
        }
      }
    } else {
      # no wildcard used; explicit mode requested - no whitelist checking
      $new_modes .= $mode;
      $new_targets .= "$target " if length $target;
      $i++;

      if ($i == $max_modes) {
        $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $new_modes $new_targets");
        $new_modes = "";
        $new_targets = "";
        $i = 0;
      }
    }
  }

  if ($i) {
    $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $new_modes $new_targets");
  }

  $self->{pbot}->{chanops}->gain_ops($channel);

  if ($from !~ m/^#/) {
    return "Done.";
  }
}

sub checkban {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $target) {
    return "Usage: checkban <mask> [channel]";
  }

  if (not defined $channel) {
    $channel = $from;
  }

  if ($channel !~ /^#/) {
    return "Please specify a channel.";
  }

  $channel = lc $channel;
  $target = lc $target;

  my $mask = $self->{pbot}->{chanops}->nick_to_banmask($target);

  if (exists $self->{pbot}->{chanops}->{unban_timeout}->hash->{$channel}
    && exists $self->{pbot}->{chanops}->{unban_timeout}->hash->{$channel}->{$mask}) {
    my $timeout = $self->{pbot}->{chanops}->{unban_timeout}->hash->{$channel}->{$mask}{timeout};
    my $owner   = $self->{pbot}->{chanops}->{unban_timeout}->hash->{$channel}->{$mask}{owner};
    my $reason  = $self->{pbot}->{chanops}->{unban_timeout}->hash->{$channel}->{$mask}{reason};
    my $duration = concise duration($timeout - gettimeofday);

    my $result = "$mask banned in $channel ";
    $result .= "by $owner " if defined $owner;
    $result .= "for $reason " if defined $reason;
    $result .= "($duration remaining)";
    return $result;
  } else {
    return "$mask has no ban timeout";
  }
}

sub checkmute {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $target) {
    return "Usage: checkmute <mask> [channel]";
  }

  if (not defined $channel) {
    $channel = $from;
  }

  if ($channel !~ /^#/) {
    return "Please specify a channel.";
  }

  $channel = lc $channel;
  $target = lc $target;

  my $mask = $self->{pbot}->{chanops}->nick_to_banmask($target);

  if (exists $self->{pbot}->{chanops}->{unmute_timeout}->hash->{$channel}
    && exists $self->{pbot}->{chanops}->{unmute_timeout}->hash->{$channel}->{$mask}) {
    my $timeout = $self->{pbot}->{chanops}->{unmute_timeout}->hash->{$channel}->{$mask}{timeout};
    my $owner   = $self->{pbot}->{chanops}->{unmute_timeout}->hash->{$channel}->{$mask}{owner};
    my $reason  = $self->{pbot}->{chanops}->{unmute_timeout}->hash->{$channel}->{$mask}{reason};
    my $duration = concise duration($timeout - gettimeofday);

    my $result = "$mask muted in $channel ";
    $result .= "by $owner " if defined $owner;
    $result .= "for $reason " if defined $reason;
    $result .= "($duration remaining)";

    return "$mask has $duration remaining on their $channel mute";
  } else {
    return "$mask has no mute timeout";
  }
}

sub ban_user {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
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

  my $no_length = 0;
  if (not defined $length) {
    $length = $self->{pbot}->{registry}->get_value($channel, 'default_ban_timeout', 0, $stuff) //
      $self->{pbot}->{registry}->get_value('general', 'default_ban_timeout', 0, $stuff) // 60 * 60 * 24; # 24 hours
    $no_length = 1;
  } else {
    my $error;
    ($length, $error) = $self->{pbot}->{parsedate}->parsedate($length);
    return $error if defined $error;
  }

  $channel = lc $channel;
  $target = lc $target;

  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
  return "I don't think so." if $target =~ /^\Q$botnick\E!/i;

  if (not $stuff->{'effective-level'} and not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
    return "/msg $nick You are not an admin for $channel.";
  }

  my $result = '';
  my $sep = '';
  my @targets = split /,/, $target;
  my $immediately = @targets > 1 ? 0 : 1;
  foreach my $t (@targets) {
    my $mask = $self->{pbot}->{chanops}->nick_to_banmask($t);

    if ($no_length && exists $self->{pbot}->{chanops}->{unban_timeout}->hash->{$channel}
      && exists $self->{pbot}->{chanops}->{unban_timeout}->hash->{$channel}->{$mask}) {
      my $timeout = $self->{pbot}->{chanops}->{unban_timeout}->hash->{$channel}->{$mask}{timeout};
      my $duration = duration($timeout - gettimeofday);

      $result .= "$sep$mask has $duration remaining on their $channel ban";
      $sep = '; ';
    } else {
      $self->{pbot}->{chanops}->ban_user_timed("$nick!$user\@$host", undef, $mask, $channel, $length, $immediately);

      my $duration;
      if ($length > 0) {
        $duration = duration($length);
      } else {
        $duration = 'all eternity';
      }

      $result .= "$sep$mask banned in $channel for $duration";
      $sep = '; ';
    }
  }

  if (not $immediately) {
    $self->{pbot}->{chanops}->check_ban_queue;
  }

  $result = "/msg $nick $result" if $result !~ m/remaining on their/;
  return $result;
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

  if (not $stuff->{'effective-level'} and not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
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
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
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

  my $no_length = 0;
  if (not defined $length) {
    $length = $self->{pbot}->{registry}->get_value($channel, 'default_mute_timeout', 0, $stuff) //
      $self->{pbot}->{registry}->get_value('general', 'default_mute_timeout', 0, $stuff) // 60 * 60 * 24; # 24 hours
    $no_length = 1;
  } else {
    my $error;
    ($length, $error) = $self->{pbot}->{parsedate}->parsedate($length);
    return $error if defined $error;
  }

  $channel = lc $channel;
  $target = lc $target;

  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
  return "I don't think so." if $target =~ /^\Q$botnick\E!/i;

  if (not $stuff->{'effective-level'} and not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
    return "/msg $nick You are not an admin for $channel.";
  }

  my $result = '';
  my $sep = '';
  my @targets = split /,/, $target;
  my $immediately = @targets > 1 ? 0 : 1;
  foreach my $t (@targets) {
    my $mask = $self->{pbot}->{chanops}->nick_to_banmask($t);

    if ($no_length && exists $self->{pbot}->{chanops}->{unmute_timeout}->hash->{$channel}
      && exists $self->{pbot}->{chanops}->{unmute_timeout}->hash->{$channel}->{$mask}) {
      my $timeout = $self->{pbot}->{chanops}->{unmute_timeout}->hash->{$channel}->{$mask}{timeout};
      my $duration = duration($timeout - gettimeofday);

      $result .= "$sep$mask has $duration remaining on their $channel mute";
      $sep = '; ';
    } else {
      $self->{pbot}->{chanops}->mute_user_timed("$nick!$user\@$host", undef, $t, $channel, $length, $immediately);

      my $duration;
      if ($length > 0) {
        $duration = duration($length);
      } else {
        $duration = 'all eternity';
      }

      $result .= "$sep$mask muted in $channel for $duration";
      $sep = '; ';
    }
  }

  if (not $immediately) {
    $self->{pbot}->{chanops}->check_ban_queue;
  }

  $result = "/msg $nick $result" if $result !~ m/remaining on their/;
  return $result;
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

  if (not $stuff->{'effective-level'} and not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
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

  if (not $stuff->{'effective-level'} and not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
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
