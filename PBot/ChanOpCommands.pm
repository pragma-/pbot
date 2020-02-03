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
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  # register commands
  $self->{pbot}->{commands}->register(sub { return $self->ban_user(@_)      },  "ban",        1);
  $self->{pbot}->{commands}->register(sub { return $self->unban_user(@_)    },  "unban",      1);
  $self->{pbot}->{commands}->register(sub { return $self->mute_user(@_)     },  "mute",       1);
  $self->{pbot}->{commands}->register(sub { return $self->unmute_user(@_)   },  "unmute",     1);
  $self->{pbot}->{commands}->register(sub { return $self->kick_user(@_)     },  "kick",       1);
  $self->{pbot}->{commands}->register(sub { return $self->checkban(@_)      },  "checkban",   0);
  $self->{pbot}->{commands}->register(sub { return $self->checkmute(@_)     },  "checkmute",  0);
  $self->{pbot}->{commands}->register(sub { return $self->op_user(@_)       },  "op",         1);
  $self->{pbot}->{commands}->register(sub { return $self->deop_user(@_)     },  "deop",       1);
  $self->{pbot}->{commands}->register(sub { return $self->voice_user(@_)    },  "voice",      1);
  $self->{pbot}->{commands}->register(sub { return $self->devoice_user(@_)  },  "devoice",    1);
  $self->{pbot}->{commands}->register(sub { return $self->mode(@_)          },  "mode",       1);
  $self->{pbot}->{commands}->register(sub { return $self->invite(@_)        },  "invite",     1);

  # allow commands to set modes
  $self->{pbot}->{capabilities}->add('can-ban',     'can-mode-b', 1);
  $self->{pbot}->{capabilities}->add('can-unban',   'can-mode-b', 1);
  $self->{pbot}->{capabilities}->add('can-mute',    'can-mode-q', 1);
  $self->{pbot}->{capabilities}->add('can-unmute',  'can-mode-q', 1);
  $self->{pbot}->{capabilities}->add('can-op',      'can-mode-o', 1);
  $self->{pbot}->{capabilities}->add('can-deop',    'can-mode-o', 1);
  $self->{pbot}->{capabilities}->add('can-voice',   'can-mode-v', 1);
  $self->{pbot}->{capabilities}->add('can-devoice', 'can-mode-v', 1);

  # create can-mode-any capabilities group
  foreach my $mode ("a" .. "z", "A" .. "Z") {
    $self->{pbot}->{capabilities}->add('can-mode-any', "can-mode-$mode", 1);
  }
  $self->{pbot}->{capabilities}->add('can-mode-any', 'can-mode', 1);

  # create chanop capabilities group
  $self->{pbot}->{capabilities}->add('chanop', 'can-ban',     1);
  $self->{pbot}->{capabilities}->add('chanop', 'can-unban',   1);
  $self->{pbot}->{capabilities}->add('chanop', 'can-mute',    1);
  $self->{pbot}->{capabilities}->add('chanop', 'can-unmute',  1);
  $self->{pbot}->{capabilities}->add('chanop', 'can-kick',    1);
  $self->{pbot}->{capabilities}->add('chanop', 'can-op',      1);
  $self->{pbot}->{capabilities}->add('chanop', 'can-deop',    1);
  $self->{pbot}->{capabilities}->add('chanop', 'can-voice',   1);
  $self->{pbot}->{capabilities}->add('chanop', 'can-devoice', 1);
  $self->{pbot}->{capabilities}->add('chanop', 'can-invite',  1);

  $self->{invites} = {}; # track who invited who in order to direct invite responses to them

  # handle invite responses
  $self->{pbot}->{event_dispatcher}->register_handler('irc.inviting', sub { return $self->on_inviting(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.useronchannel', sub { return $self->on_useronchannel(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.nosuchnick', sub { return $self->on_nosuchnick(@_) });
}

sub on_inviting {
  my ($self, $event_type, $event) = @_;
  my ($botnick, $target, $channel) = $event->{event}->args;
  $self->{pbot}->{logger}->log("User $target invited to channel $channel.\n");
  return 0 if not exists $self->{invites}->{lc $channel} or not exists $self->{invites}->{lc $channel}->{lc $target};
  $event->{conn}->privmsg($self->{invites}->{lc $channel}->{lc $target}, "$target invited to $channel.");
  delete $self->{invites}->{lc $channel}->{lc $target};
  return 1;
}

sub on_useronchannel {
  my ($self, $event_type, $event) = @_;
  my ($botnick, $target, $channel) = $event->{event}->args;
  $self->{pbot}->{logger}->log("User $target is already on channel $channel.\n");
  return 0 if not exists $self->{invites}->{lc $channel} or not exists $self->{invites}->{lc $channel}->{lc $target};
  $event->{conn}->privmsg($self->{invites}->{lc $channel}->{lc $target}, "$target is already on $channel.");
  delete $self->{invites}->{lc $channel}->{lc $target};
  return 1;
}

sub on_nosuchnick {
  my ($self, $event_type, $event) = @_;
  my ($botnick, $target, $msg) = $event->{event}->args;

  $self->{pbot}->{logger}->log("$target: $msg\n");

  my $nick;
  foreach my $channel (keys %{$self->{invites}}) {
    if (exists $self->{invites}->{$channel}->{lc $target}) {
      $nick = $self->{invites}->{$channel}->{lc $target};
      delete $self->{invites}->{$channel}->{lc $target};
      last;
    }
  }

  return 0 if not defined $nick;
  $event->{conn}->privmsg($nick, "$target: $msg");
  return 1;
}

sub invite {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($channel, $target);

  if ($from !~ m/^#/) {
    # from /msg
    my $usage = "Usage from /msg: invite <channel> [nick]; if you omit [nick] then you will be invited";
    return $usage if not length $arguments;
    ($channel, $target) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);
    return "$channel is not a channel; $usage" if $channel !~ m/^#/;
    $target = $nick if not defined $target;
  } else {
    # in channel
    return "Usage: invite [channel] <nick>" if not length $arguments;
    # add current channel as default channel
    $self->{pbot}->{interpreter}->unshift_arg($stuff->{arglist}, $from) if $stuff->{arglist}[0] !~ m/^#/;
    ($channel, $target) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);
  }

  $self->{invites}->{lc $channel}->{lc $target} = $nick;
  $self->{pbot}->{chanops}->add_op_command($channel, "sl invite $target $channel");
  $self->{pbot}->{chanops}->gain_ops($channel);
  return ""; # responses handled by events
}

sub generic_mode_user {
  my ($self, $mode_flag, $mode_name, $channel, $nick, $stuff) = @_;
  my $result = '';

  my ($flag, $mode_char) = $mode_flag =~ m/(.)(.)/;

  if ($channel !~ m/^#/) {
    # from message
    $channel = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
    if (not defined $channel) {
      return "Usage from message: $mode_name <channel> [nick]";
    } elsif ($channel !~ m/^#/) {
      return "$channel is not a channel. Usage from message: $mode_name <channel> [nick]";
    }
  }

  $channel = lc $channel;
  if (not $self->{pbot}->{chanops}->can_gain_ops($channel)) {
    return "I am not configured as an OP for $channel. See `chanset` command for more information.";
  }

  # add $nick to $args if no argument
  if (not $self->{pbot}->{interpreter}->arglist_size($stuff->{arglist})) {
    $self->{pbot}->{interpreter}->unshift_arg($stuff->{arglist}, $nick);
  }

  my $max_modes = $self->{pbot}->{ircd}->{MODES} // 1;
  my $mode = $flag;
  my $list = '';
  my $i = 0;

  foreach my $targets ($self->{pbot}->{interpreter}->unquoted_args($stuff->{arglist})) {
    foreach my $target (split /,/, $targets) {
      $mode .= $mode_char;
      $list .= "$target ";
      $i++;

      if ($i >= $max_modes) {
        my $args = "$channel $mode $list";
        $stuff->{arglist} = $self->{pbot}->{interpreter}->make_args($args);
        $result = $self->mode($channel, $nick, $stuff->{user}, $stuff->{host}, $args, $stuff);
        $mode = $flag;
        $list = '';
        $i = 0;
        last if $result ne '' and $result ne 'Done.';
      }
    }
  }

  if ($i) {
    my $args = "$channel $mode $list";
    $stuff->{arglist} = $self->{pbot}->{interpreter}->make_args($args);
    $result = $self->mode($channel, $nick, $stuff->{user}, $stuff->{host}, $args, $stuff);
  }

  return $result;
}

sub op_user {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  return $self->generic_mode_user('+o', 'op', $from, $nick, $stuff);
}

sub deop_user {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  return $self->generic_mode_user('-o', 'deop', $from, $nick, $stuff);
}

sub voice_user {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  return $self->generic_mode_user('+v', 'voice', $from, $nick, $stuff);
}

sub devoice_user {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  return $self->generic_mode_user('-v', 'devoice', $from, $nick, $stuff);
}

sub mode {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (not length $arguments) {
    return "Usage: mode [channel] <arguments>";
  }

  # add current channel as default channel
  if ($stuff->{arglist}[0] !~ m/^#/) {
    if ($from =~ m/^#/) {
      $self->{pbot}->{interpreter}->unshift_arg($stuff->{arglist}, $from);
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

  my $u = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");

  while ($modes =~ m/(.)/g) {
    my $mode = $1;

    if ($mode eq '-' or $mode eq '+') {
      $modifier = $mode;
      $new_modes .= $mode;
      next;
    }

    if (not $self->{pbot}->{capabilities}->userhas($u, "can-mode-$mode")) {
      return "/msg $nick Your user account does not have the can-mode-$mode capability required to set this mode.";
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
            next if $nick_data->{nick} eq $self->{pbot}->{registry}->get_value('irc', 'botnick');
            next if $self->{pbot}->{antiflood}->whitelisted($channel, $nick_data->{hostmask});
            next if $self->{pbot}->{users}->loggedin_admin($channel, $nick_data->{hostmask});
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
  } else {
    return "";
  }
}

sub checkban {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  return "Usage: checkban <mask> [channel]" if not defined $target;
  $channel = $from if not defined $channel;

  return "Please specify a channel." if $channel !~ /^#/;
  return $self->{pbot}->{chanops}->checkban($channel, $target);
}

sub checkmute {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  return "Usage: checkmute <mask> [channel]" if not defined $target;
  $channel = $from if not defined $channel;

  return "Please specify a channel." if $channel !~ /^#/;
  return $self->{pbot}->{chanops}->checkmute($channel, $target);
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
    return "Usage: ban <mask> [channel [timeout (default: 24 hours)]]";
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

  my $result = '';
  my $sep = '';
  my @targets = split /,/, $target;
  my $immediately = @targets > 1 ? 0 : 1;
  foreach my $t (@targets) {
    my $mask = lc $self->{pbot}->{chanops}->nick_to_banmask($t);

    if ($no_length && exists $self->{pbot}->{chanops}->{unban_timeout}->{hash}->{$channel}
      && exists $self->{pbot}->{chanops}->{unban_timeout}->{hash}->{$channel}->{$mask}) {
      my $timeout = $self->{pbot}->{chanops}->{unban_timeout}->{hash}->{$channel}->{$mask}->{timeout};
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
    return "Usage: unban <nick/mask> [channel [false value to use unban queue]]";
  }

  $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from if not defined $channel;
  $immediately = 1 if not defined $immediately;

  return "Usage for /msg: unban <nick/mask> <channel> [false value to use unban queue]" if $channel !~ /^#/;

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
    return "Usage from private message: mute <mask> <channel> [timeout (default: 24 hours)]";
  }

  if ($channel !~ m/^#/) {
    $length = "$channel $length";
    $length = undef if $length eq ' ';
    $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from;
  }

  $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from if not defined $channel;

  if ($channel !~ m/^#/) {
    return "Please specify a channel.";
  }

  if (not defined $target) {
    return "Usage: mute <mask> [channel [timeout (default: 24 hours)]]";
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

  my $result = '';
  my $sep = '';
  my @targets = split /,/, $target;
  my $immediately = @targets > 1 ? 0 : 1;
  foreach my $t (@targets) {
    my $mask = lc $self->{pbot}->{chanops}->nick_to_banmask($t);

    if ($no_length && exists $self->{pbot}->{chanops}->{unmute_timeout}->{hash}->{$channel}
      && exists $self->{pbot}->{chanops}->{unmute_timeout}->{hash}->{$channel}->{$mask}) {
      my $timeout = $self->{pbot}->{chanops}->{unmute_timeout}->{hash}->{$channel}->{$mask}->{timeout};
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
    return "Usage: unmute <nick/mask> [channel [false value to use unban queue]]";
  }

  $channel = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from if not defined $channel;
  $immediately = 1 if not defined $immediately;

  return "Usage for /msg: unmute <nick/mask> <channel> [false value to use unban queue]" if $channel !~ /^#/;

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
      return "Usage from private message: kick <channel> <nick> [reason]";
    }
    ($channel, $victim) = ($1, $2);
  } else {
    # used in channel
    if ($arguments =~ s/^(#\S+)\s+(\S+)\s*//) {
      ($channel, $victim) = ($1, $2);
    } elsif ($arguments =~ s/^(\S+)\s*//) {
      ($victim, $channel) = ($1, exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $from);
    } else {
      return "Usage: kick [channel] <nick> [reason]";
    }
  }

  $reason = $arguments;

  # If the user is too stupid to remember the order of the arguments,
  # we can help them out by seeing if they put the channel in the reason.
  if ($reason =~ s/^(#\S+)\s*//) {
    $channel = $1;
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
  foreach my $n (@nicks) {
    if ($n =~ m/\*/) {
      # wildcard used; find all matching nicks; test against whitelist, etc
      my $q_target = lc quotemeta $n;
      $q_target =~ s/\\\*/.*/g;
      $channel = lc $channel;

      if (not exists $self->{pbot}->{nicklist}->{nicklist}->{$channel}) {
        return "I have no nicklist for channel $channel; cannot use wildcard.";
      }

      foreach my $nl (keys %{$self->{pbot}->{nicklist}->{nicklist}->{$channel}}) {
        if ($nl =~ m/^$q_target$/) {
          my $nick_data = $self->{pbot}->{nicklist}->{nicklist}->{$channel}->{$nl};

          next if $nick_data->{nick} eq $self->{pbot}->{registry}->get_value('irc', 'botnick');
          next if $self->{pbot}->{antiflood}->whitelisted($channel, $nick_data->{hostmask});
          next if $self->{pbot}->{users}->loggedin_admin($channel, $nick_data->{hostmask});

          $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $nl $reason");
        }
      }
    } else {
      # no wildcard used, explicit kick
      $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $n $reason");
    }

    # randomize next kick reason
    if (@insults) {
      $reason = $insults[rand @insults];
      $reason =~ s/\s+$//;
    }
  }

  $self->{pbot}->{chanops}->gain_ops($channel);
  return "";
}

1;
