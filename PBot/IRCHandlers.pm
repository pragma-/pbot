# File: IRCHandlers.pm
# Author: pragma_
#
# Purpose: Subroutines to handle IRC events

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::IRCHandlers;

use warnings;
use strict;

use feature 'unicode_strings';

use Carp();
use Time::HiRes qw(gettimeofday);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot parameter to " . __FILE__);

  $self->{pbot}->{event_dispatcher}->register_handler('irc.welcome',       sub { $self->on_connect(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.disconnect',    sub { $self->on_disconnect(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.motd',          sub { $self->on_motd(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.notice',        sub { $self->on_notice(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.public',        sub { $self->on_public(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.caction',       sub { $self->on_action(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.msg',           sub { $self->on_msg(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.mode',          sub { $self->on_mode(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.part',          sub { $self->on_departure(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.join',          sub { $self->on_join(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',          sub { $self->on_kick(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',          sub { $self->on_departure(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.nick',          sub { $self->on_nickchange(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.nicknameinuse', sub { $self->on_nicknameinuse(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.invite',        sub { $self->on_invite(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.cap',           sub { $self->on_cap(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.map',           sub { $self->on_map(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.whoreply',      sub { $self->on_whoreply(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.whospcrpl',     sub { $self->on_whospcrpl(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.endofwho',      sub { $self->on_endofwho(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.channelmodeis', sub { $self->on_channelmodeis(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.topic',         sub { $self->on_topic(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.topicinfo',     sub { $self->on_topicinfo(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.channelcreate', sub { $self->on_channelcreate(@_) });

  $self->{pbot}->{event_dispatcher}->register_handler('pbot.join',         sub { $self->on_self_join(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('pbot.part',         sub { $self->on_self_part(@_) });

  $self->{pbot}->{timer}->register(sub { $self->check_pending_whos }, 10);
}

sub default_handler {
  my ($self, $conn, $event) = @_;

  if (not defined $self->{pbot}->{event_dispatcher}->dispatch_event("irc.$event->{type}", { conn => $conn, event => $event })) {
    if ($self->{pbot}->{registry}->get_value('irc', 'log_default_handler')) {
      $self->{pbot}->{logger}->log(Dumper $event);
    }
  }
}

sub on_init {
  my ($self, $conn, $event) = @_;
  my (@args) = ($event->args);
  shift (@args);
  $self->{pbot}->{logger}->log("*** @args\n");
}

sub on_connect {
  my ($self, $event_type, $event) = @_;
  $self->{pbot}->{logger}->log("Connected!\n");
  $event->{conn}->{connected} = 1;

  $self->{pbot}->{logger}->log("Requesting account-notify and extended-join . . .\n");
  $event->{conn}->sl("CAP REQ :account-notify extended-join");

  if (length $self->{pbot}->{registry}->get_value('irc', 'identify_password')) {
    $self->{pbot}->{logger}->log("Identifying with NickServ . . .\n");

    my $nickserv = $self->{pbot}->{registry}->get_value('general', 'identify_nick')    // 'nickserv';
    my $command  = $self->{pbot}->{registry}->get_value('general', 'identify_command') // 'identify $nick $password';

    my $botnick  = $self->{pbot}->{registry}->get_value('irc', 'botnick');
    my $password = $self->{pbot}->{registry}->get_value('irc', 'identify_password');

    $command =~ s/\$nick\b/$botnick/g;
    $command =~ s/\$password\b/$password/g;

    $event->{conn}->privmsg($nickserv, $command);
  } else {
    $self->{pbot}->{logger}->log("No identify password; skipping identification to services.\n");
  }

  if (not $self->{pbot}->{registry}->get_value('general', 'autojoin_wait_for_nickserv')) {
    $self->{pbot}->{logger}->log("Autojoining channels immediately; to wait for services set general.autojoin_wait_for_nickserv to 1.\n");
    $self->{pbot}->{channels}->autojoin;
  } else {
    $self->{pbot}->{logger}->log("Waiting for services identify response before autojoining channels.\n");
  }

  return 0;
}

sub on_disconnect {
  my ($self, $event_type, $event) = @_;
  $self->{pbot}->{logger}->log("Disconnected...\n");
  $self->{pbot}->{connected} = 0;
  return 0;
}

sub on_motd {
  my ($self, $event_type, $event) = @_;

  if ($self->{pbot}->{registry}->get_value('irc', 'show_motd')) {
    my $server = $event->{event}->{from};
    my $msg    = $event->{event}->{args}[1];
    $self->{pbot}->{logger}->log("MOTD from $server :: $msg\n");
  }
  return 0;
}

sub on_self_join {
  my ($self, $event_type, $event) = @_;
  my $send_who = $self->{pbot}->{registry}->get_value('general', 'send_who_on_join') // 1;
  $self->send_who($event->{channel}) if $send_who;
  return 0;
}

sub on_self_part {
  my ($self, $event_type, $event) = @_;
  return 0;
}

sub on_public {
  my ($self, $event_type, $event) = @_;

  my $from = $event->{event}->{to}[0];
  my $nick = $event->{event}->nick;
  my $user = $event->{event}->user;
  my $host = $event->{event}->host;
  my $text = $event->{event}->{args}[0];

  ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

  $event->{interpreted} = $self->{pbot}->{interpreter}->process_line($from, $nick, $user, $host, $text);
  return 0;
}

sub on_msg {
  my ($self, $event_type, $event) = @_;
  my ($nick, $host) = ($event->{event}->nick, $event->{event}->host);
  my $text = $event->{event}->{args}[0];

  my $bot_trigger = $self->{pbot}->{registry}->get_value('general', 'trigger');
  my $bot_nick    = $self->{pbot}->{registry}->get_value('irc', 'botnick');

  $text =~ s/^$bot_trigger?\s*(.*)/$bot_nick $1/;
  $event->{event}->{to}[0]   = $nick;
  $event->{event}->{args}[0] = $text;
  $self->on_public($event_type, $event);
  return 0;
}

sub on_notice {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);
  my $text = $event->{event}->{args}[0];

  $self->{pbot}->{logger}->log("Received NOTICE from $nick!$user\@$host to $event->{event}->{to}[0] '$text'\n");

  return 0 if not length $host;

  if ($nick eq 'NickServ') {
    if ($text =~ m/This nickname is registered/) {
      if (length $self->{pbot}->{registry}->get_value('irc', 'identify_password')) {
        $self->{pbot}->{logger}->log("Identifying with NickServ . . .\n");
        $event->{conn}->privmsg("nickserv", "identify " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));
      }
    } elsif ($text =~ m/You are now identified/) {
      if ($self->{pbot}->{registry}->get_value('irc', 'randomize_nick')) {
        $event->{conn}->nick($self->{pbot}->{registry}->get_value('irc', 'botnick'));
      } else {
        $self->{pbot}->{channels}->autojoin;
      }
    } elsif ($text =~ m/has been ghosted/) {
      $event->{conn}->nick($self->{pbot}->{registry}->get_value('irc', 'botnick'));
    }
  } else {
    if ($event->{event}->{to}[0] eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
      $event->{event}->{to}[0] = $nick;
    }
    $self->on_public($event_type, $event);
  }
  return 0;
}

sub on_action {
  my ($self, $event_type, $event) = @_;

  $event->{event}->{args}[0] = "/me " . $event->{event}->{args}[0];

  $self->on_public($event_type, $event);
  return 0;
}

# FIXME: on_mode doesn't handle chanmodes that have parameters, e.g. +l

sub on_mode {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);
  my $mode_string = $event->{event}->{args}[0];
  my $channel = $event->{event}->{to}[0];
  $channel = lc $channel;

  ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

  my ($mode, $mode_char, $modifier);
  my $i = 0;
  my $target;

  while ($mode_string =~ m/(.)/g) {
    my $char = $1;

    if ($char eq '-' or $char eq '+') {
      $modifier = $char;
      next;
    }

    $mode = $modifier . $char;
    $mode_char = $char;
    $target = $event->{event}->{args}[++$i];

    $self->{pbot}->{logger}->log("Mode $channel [$mode" . (length $target ? " $target" : '') . "] by $nick!$user\@$host\n");

    if ($mode eq "-b" or $mode eq "+b" or $mode eq "-q" or $mode eq "+q") {
      $self->{pbot}->{bantracker}->track_mode("$nick!$user\@$host", $mode, $target, $channel);
    }

    if (defined $target and length $target) {
      my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);
      $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "MODE $mode $target", $self->{pbot}->{messagehistory}->{MSG_CHAT});

      if ($modifier eq '-') {
        $self->{pbot}->{nicklist}->delete_meta($channel, $target, "+$mode_char");
      } else {
        $self->{pbot}->{nicklist}->set_meta($channel, $target, $mode, 1);
      }
    } else {
      my $modes = $self->{pbot}->{channels}->get_meta($channel, 'MODE');
      if (defined $modes) {
        if ($modifier eq '+') {
          $modes = '+' if not length $modes;
          $modes .= $mode_char;
        } else {
          $modes =~ s/\Q$mode_char\E//g;
        }
        $self->{pbot}->{channels}->{channels}->set($channel, 'MODE', $modes, 1);
      }
    }

    if (defined $target && $target eq $event->{conn}->nick) { # bot targeted
      if ($mode eq "+o") {
        $self->{pbot}->{logger}->log("$nick opped me in $channel\n");
        my $timeout = $self->{pbot}->{registry}->get_value($channel, 'deop_timeout') // $self->{pbot}->{registry}->get_value('general', 'deop_timeout');
        $self->{pbot}->{chanops}->{is_opped}->{$channel}{timeout} = gettimeofday + $timeout;
        delete $self->{pbot}->{chanops}->{op_requested}->{$channel};
        $self->{pbot}->{chanops}->perform_op_commands($channel);
      }
      elsif ($mode eq "-o") {
        $self->{pbot}->{logger}->log("$nick removed my ops in $channel\n");
        delete $self->{pbot}->{chanops}->{is_opped}->{$channel};
      }
      elsif ($mode eq "+b") {
        $self->{pbot}->{logger}->log("Got banned in $channel, attempting unban.");
        $event->{conn}->privmsg("chanserv", "unban $channel");
      }
    }
    else {  # bot not targeted
      if ($mode eq "+b") {
        if ($nick eq "ChanServ" or $target =~ m/##fix_your_connection$/i) {
          if ($self->{pbot}->{chanops}->can_gain_ops($channel)) {
            $self->{pbot}->{chanops}->{unban_timeout}->{hash}->{lc $channel}->{lc $target}->{timeout} = gettimeofday + $self->{pbot}->{registry}->get_value('bantracker', 'chanserv_ban_timeout');
            $self->{pbot}->{chanops}->{unban_timeout}->save;
          }
        } elsif ($target =~ m/^\*!\*@/ or $target =~ m/^\*!.*\@gateway\/web/i) {
          my $timeout = 60 * 60 * 24 * 7;

          if ($target =~ m/\// and $target !~ m/\@gateway/) {
            $timeout = 0; # permanent bans for cloaks that aren't gateway
          }

          if ($timeout && $self->{pbot}->{chanops}->can_gain_ops($channel)) {
            if (not exists $self->{pbot}->{chanops}->{unban_timeout}->{hash}->{lc $channel}->{lc $target}) {
              $self->{pbot}->{logger}->log("Temp ban for $target in $channel.\n");
              $self->{pbot}->{chanops}->{unban_timeout}->{hash}->{lc $channel}->{lc $target}->{timeout} = gettimeofday + $timeout;
              $self->{pbot}->{chanops}->{unban_timeout}->save;
            }
          }
        }
      }
      elsif ($mode eq "+q") {
        if ($nick ne $event->{conn}->nick) { # bot muted
          if ($self->{pbot}->{chanops}->can_gain_ops($channel)) {
            $self->{pbot}->{chanops}->{unmute_timeout}->{hash}->{lc $channel}->{lc $target}->{timeout} = gettimeofday + $self->{pbot}->{registry}->get_value('bantracker', 'mute_timeout');
            $self->{pbot}->{chanops}->{unmute_timeout}->save;
          }
        }
      }
    }
  }
  return 0;
}

sub on_join {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);

  ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

  $channel = lc $channel;

  my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);
  $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "JOIN", $self->{pbot}->{messagehistory}->{MSG_JOIN});

  $self->{pbot}->{messagehistory}->{database}->devalidate_channel($message_account, $channel);

  my $msg = 'JOIN';

  if (exists $self->{pbot}->{irc_capabilities}->{'extended-join'}) {
    $msg .= " $event->{event}->{args}[0] :$event->{event}->{args}[1]";

    $self->{pbot}->{messagehistory}->{database}->update_gecos($message_account, $event->{event}->{args}[1], scalar gettimeofday);

    if ($event->{event}->{args}[0] ne '*') {
      $self->{pbot}->{messagehistory}->{database}->link_aliases($message_account, undef, $event->{event}->{args}[0]);
      $self->{pbot}->{antiflood}->check_nickserv_accounts($nick, $event->{event}->{args}[0]);
    } else {
      $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($message_account, '');
    }

    $self->{pbot}->{antiflood}->check_bans($message_account, $event->{event}->from, $channel);
  }

  $self->{pbot}->{antiflood}->check_flood($channel, $nick, $user, $host, $msg,
    $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_threshold'),
    $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_time_threshold'),
    $self->{pbot}->{messagehistory}->{MSG_JOIN});
  return 0;
}

sub on_invite {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $target, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to, $event->{event}->{args}[0]);

  ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

  $channel = lc $channel;

  $self->{pbot}->{logger}->log("$nick!$user\@$host invited $target to $channel!\n");

  if ($target eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
    if ($self->{pbot}->{channels}->is_active($channel)) {
      $self->{pbot}->{interpreter}->add_botcmd_to_command_queue($channel, "join $channel", 0);
    }
  }

  return 0;
}

sub on_kick {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $target, $channel, $reason) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to, $event->{event}->{args}[0], $event->{event}->{args}[1]);
  $channel = lc $channel;

  ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

  $self->{pbot}->{logger}->log("$nick!$user\@$host kicked $target from $channel ($reason)\n");

  my ($message_account) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($target);

  my $hostmask;
  if (defined $message_account) {
    $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($message_account);

    my ($target_nick, $target_user, $target_host) = $hostmask =~ m/^([^!]+)!([^@]+)@(.*)/;
    my $text = "KICKED by $nick!$user\@$host ($reason)";

    $self->{pbot}->{messagehistory}->add_message($message_account, $hostmask, $channel, $text, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
    $self->{pbot}->{antiflood}->check_flood($channel, $target_nick, $target_user, $target_host, $text,
      $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_threshold'),
      $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_time_threshold'),
      $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
  }

  $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account_id("$nick!$user\@$host");

  if (defined $message_account) {
    my $text = "KICKED " . (defined $hostmask ? $hostmask : $target) . " from $channel ($reason)";
    $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, $text, $self->{pbot}->{messagehistory}->{MSG_CHAT});
  }
  return 0;
}

sub on_departure {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel, $args) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to, $event->{event}->args);
  $channel = lc $channel;

  ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

  my $text = uc $event->{event}->type;
  $text .= " $args";

  my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);

  if ($text =~ m/^QUIT/) {
    # QUIT messages must be dispatched to each channel the user is on
    my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
    foreach my $chan (@$channels) {
      next if $chan !~ m/^#/;
      $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $chan, $text, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
    }
  } else {
    $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, $text, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
  }

  $self->{pbot}->{antiflood}->check_flood($channel, $nick, $user, $host, $text,
    $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_threshold'),
    $self->{pbot}->{registry}->get_value('antiflood', 'join_flood_time_threshold'),
    $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});

  # auto-logout admins but not users
  my $admin = $self->{pbot}->{users}->find_admin($channel, "$nick!$user\@$host");
  if (defined $admin and $admin->{loggedin} and not $admin->{stayloggedin}) {
    $self->{pbot}->{logger}->log("Logged out $nick.\n");
    delete $admin->{loggedin};
  }
  return 0;
}

sub on_map {
  my ($self, $event_type, $event) = @_;

  # remove and discard first and last elements
  shift @{ $event->{event}->{args} };
  pop @{ $event->{event}->{args} };

  foreach my $arg (@{ $event->{event}->{args} }) {
    my ($key, $value) = split /=/, $arg;
    $self->{pbot}->{ircd}->{$key} = $value;
    $self->{pbot}->{logger}->log("  $key\n")        if not defined $value;
    $self->{pbot}->{logger}->log("  $key=$value\n") if defined $value;
  }
}

sub on_cap {
  my ($self, $event_type, $event) = @_;

  if ($event->{event}->{args}->[0] eq 'ACK') {
    $self->{pbot}->{logger}->log("Client capabilities granted: " . $event->{event}->{args}->[1] . "\n");

    my @caps = split /\s+/, $event->{event}->{args}->[1];
    foreach my $cap (@caps) {
      $self->{pbot}->{irc_capabilities}->{$cap} = 1;
    }
  } else {
    $self->{pbot}->{logger}->log(Dumper $event->{event});
  }
  return 0;
}

sub on_nickchange {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $newnick) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);

  ($nick, $user, $host) = $self->normalize_hostmask($nick, $user, $host);

  $self->{pbot}->{logger}->log("[NICKCHANGE] $nick!$user\@$host changed nick to $newnick\n");

  if ($newnick eq $self->{pbot}->{registry}->get_value('irc', 'botnick') and not $self->{pbot}->{joined_channels}) {
    $self->{pbot}->{channels}->autojoin;
    return 0;
  }

  my $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($message_account, $self->{pbot}->{antiflood}->{NEEDS_CHECKBAN});
  my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
  foreach my $channel (@$channels) {
    next if $channel !~ m/^#/;
    $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "NICKCHANGE $newnick", $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE});
  }
  $self->{pbot}->{messagehistory}->{database}->update_hostmask_data("$nick!$user\@$host", { last_seen => scalar gettimeofday });

  my $newnick_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($newnick, $user, $host, $nick);
  $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($newnick_account, $self->{pbot}->{antiflood}->{NEEDS_CHECKBAN});
  $self->{pbot}->{messagehistory}->{database}->update_hostmask_data("$newnick!$user\@$host", { last_seen => scalar gettimeofday });

  $self->{pbot}->{antiflood}->check_flood("$nick!$user\@$host", $nick, $user, $host, "NICKCHANGE $newnick",
    $self->{pbot}->{registry}->get_value('antiflood', 'nick_flood_threshold'),
    $self->{pbot}->{registry}->get_value('antiflood', 'nick_flood_time_threshold'),
    $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE});

  return 0;
}

sub on_nicknameinuse {
  my ($self, $event_type, $event) = @_;
  my (undef, $nick, $msg) = $event->{event}->args;
  my $from = $event->{event}->from;

  $self->{pbot}->{logger}->log("Received nicknameinuse for nick $nick from $from: $msg\n");
  $event->{conn}->privmsg("nickserv", "ghost $nick " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));
  return 0;
}

sub on_channelmodeis {
  my ($self, $event_type, $event) = @_;
  my (undef, $channel, $modes) = $event->{event}->args;
  $self->{pbot}->{logger}->log("Channel $channel modes: $modes\n");
  $self->{pbot}->{channels}->{channels}->set($channel, 'MODE', $modes, 1);
}

sub on_channelcreate {
  my ($self, $event_type, $event) = @_;
  my ($owner, $channel, $timestamp) = $event->{event}->args;
  $self->{pbot}->{logger}->log("Channel $channel created by $owner on " . localtime ($timestamp) . "\n");
  $self->{pbot}->{channels}->{channels}->set($channel, 'CREATED_BY', $owner, 1);
  $self->{pbot}->{channels}->{channels}->set($channel, 'CREATED_ON', $timestamp, 1);
}

sub on_topic {
  my ($self, $event_type, $event) = @_;

  if (not length $event->{event}->{to}->[0]) {
    # on join
    my (undef, $channel, $topic) = $event->{event}->args;
    $self->{pbot}->{logger}->log("Topic for $channel: $topic\n");
    $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC', $topic, 1);
  } else {
    # user changing topic
    my ($nick, $user, $host) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);
    my $channel = $event->{event}->{to}->[0];
    my $topic = $event->{event}->{args}->[0];

    $self->{pbot}->{logger}->log("$nick!$user\@$host changed topic for $channel to: $topic\n");
    $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC', $topic, 1);
    $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC_SET_BY', "$nick!$user\@$host", 1);
    $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC_SET_ON', gettimeofday);
  }
}

sub on_topicinfo {
  my ($self, $event_type, $event) = @_;
  my (undef, $channel, $by, $timestamp) = $event->{event}->args;
  $self->{pbot}->{logger}->log("Topic for $channel set by $by on " . localtime ($timestamp) . "\n");
  $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC_SET_BY', $by, 1);
  $self->{pbot}->{channels}->{channels}->set($channel, 'TOPIC_SET_ON', $timestamp, 1);
}

sub normalize_hostmask {
  my ($self, $nick, $user, $host) = @_;

  if ($host =~ m{^(gateway|nat)/(.*)/x-[^/]+$}) {
    $host = "$1/$2/x-$user";
  }

  $host =~ s{/session$}{/x-$user};

  return ($nick, $user, $host);
}

my %who_queue;
my %who_cache;
my $last_who_id;
my $who_pending = 0;

sub on_whoreply {
  my ($self, $event_type, $event) = @_;

  my ($ignored, $id, $user, $host, $server, $nick, $usermodes, $gecos) = @{$event->{event}->{args}};
  ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);
  my $hostmask = "$nick!$user\@$host";
  my $channel;

  if ($id =~ m/^#/) {
    $id = lc $id;
    foreach my $x (keys %who_cache) {
      if ($who_cache{$x} eq $id) {
        $id = $x;
        last;
      }
    }
  }

  $last_who_id = $id;
  $channel = $who_cache{$id};
  delete $who_queue{$id};

  return 0 if not defined $channel;

  $self->{pbot}->{logger}->log("WHO id: $id [$channel], hostmask: $hostmask, $usermodes, $server, $gecos.\n");

  $self->{pbot}->{nicklist}->add_nick($channel, $nick);
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'hostmask', $hostmask);
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'user', $user);
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'host', $host);
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'server', $server);
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'gecos', $gecos);

  my $account_id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($hostmask, { last_seen => scalar gettimeofday });

  $self->{pbot}->{messagehistory}->{database}->link_aliases($account_id, $hostmask, undef);

  $self->{pbot}->{messagehistory}->{database}->devalidate_channel($account_id, $channel);
  $self->{pbot}->{antiflood}->check_bans($account_id, $hostmask, $channel);

  return 0;
}

sub on_whospcrpl {
  my ($self, $event_type, $event) = @_;

  my ($ignored, $id, $user, $host, $nick, $nickserv, $gecos) = @{$event->{event}->{args}};
  ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);
  $last_who_id = $id;
  my $hostmask = "$nick!$user\@$host";
  my $channel = $who_cache{$id};
  delete $who_queue{$id};

  return 0 if not defined $channel;

  $self->{pbot}->{logger}->log("WHO id: $id [$channel], hostmask: $hostmask, $nickserv, $gecos.\n");

  $self->{pbot}->{nicklist}->add_nick($channel, $nick);
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'hostmask', $hostmask);
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'user', $user);
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'host', $host);
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'nickserv', $nickserv) if $nickserv ne '0';
  $self->{pbot}->{nicklist}->set_meta($channel, $nick, 'gecos', $gecos);

  my $account_id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($hostmask, { last_seen => scalar gettimeofday });

  if ($nickserv ne '0') {
    $self->{pbot}->{messagehistory}->{database}->link_aliases($account_id, undef, $nickserv);
    $self->{pbot}->{antiflood}->check_nickserv_accounts($nick, $nickserv);
  }

  $self->{pbot}->{messagehistory}->{database}->link_aliases($account_id, $hostmask, undef);

  $self->{pbot}->{messagehistory}->{database}->devalidate_channel($account_id, $channel);
  $self->{pbot}->{antiflood}->check_bans($account_id, $hostmask, $channel);

  return 0;
}

sub on_endofwho {
  my ($self, $event_type, $event) = @_;
  $self->{pbot}->{logger}->log("WHO session $last_who_id ($who_cache{$last_who_id}) completed.\n");
  delete $who_cache{$last_who_id};
  delete $who_queue{$last_who_id};
  $who_pending = 0;
  return 0;
}

sub send_who {
  my ($self, $channel) = @_;
  $channel = lc $channel;
  $self->{pbot}->{logger}->log("pending WHO to $channel\n");

  for (my $id = 1; $id < 99; $id++) {
    if (not exists $who_cache{$id}) {
      $who_cache{$id} = $channel;
      $who_queue{$id} = $channel;
      $last_who_id = $id;
      last;
    }
  }
}

sub check_pending_whos {
  my $self = shift;
  return if $who_pending;
  foreach my $id (keys %who_queue) {
    $self->{pbot}->{logger}->log("sending WHO to $who_queue{$id} [$id]\n");
    $self->{pbot}->{conn}->sl("WHO $who_queue{$id} %tuhnar,$id");
    $who_pending = 1;
    $last_who_id = $id;
    last;
  }
}

1;
