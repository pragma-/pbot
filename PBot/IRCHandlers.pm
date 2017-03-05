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

use Carp();
use Time::HiRes qw(gettimeofday);
use Data::Dumper;

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
 
  $self->{pbot} = delete $conf{pbot};
  Carp::croak("Missing pbot parameter to " . __FILE__) if not defined $self->{pbot};

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
}

sub default_handler {
  my ($self, $conn, $event) = @_;

  if(not defined $self->{pbot}->{event_dispatcher}->dispatch_event("irc.$event->{type}", { conn => $conn, event => $event })) {
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

  $self->{pbot}->{logger}->log("Identifying with NickServ . . .\n");
  $event->{conn}->privmsg("nickserv", "identify " . $self->{pbot}->{registry}->get_value('irc', 'botnick') . ' ' . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));

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

sub on_public {
  my ($self, $event_type, $event) = @_;
  
  my $from = $event->{event}->{to}[0];
  my $nick = $event->{event}->nick;
  my $user = $event->{event}->user;
  my $host = $event->{event}->host;
  my $text = $event->{event}->{args}[0];

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
 
  if($nick eq 'NickServ') {
    if($text =~ m/This nickname is registered/) {
      $self->{pbot}->{logger}->log("Identifying with NickServ . . .\n");
      $event->{conn}->privmsg("nickserv", "identify " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));
    } elsif($text =~ m/You are now identified/) {
      $event->{conn}->nick($self->{pbot}->{registry}->get_value('irc', 'botnick'));
    } elsif($text =~ m/has been ghosted/) {
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

sub on_mode {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);
  my $mode_string = $event->{event}->{args}[0];
  my $channel = $event->{event}->{to}[0];
  $channel = lc $channel;

  my ($mode, $modifier);
  my $i = 0;
  my $target;

  while($mode_string =~ m/(.)/g) {
    my $char = $1;

    if($char eq '-' or $char eq '+') {
      $modifier = $char;
      next;
    }

    $mode = $modifier . $char;
    $target = $event->{event}->{args}[++$i];

    $self->{pbot}->{logger}->log("Got mode: source: $nick!$user\@$host, mode: $mode, target: " . (defined $target ? $target : "(undef)") . ", channel: $channel\n");

    if($mode eq "-b" or $mode eq "+b" or $mode eq "-q" or $mode eq "+q") {
      $self->{pbot}->{bantracker}->track_mode("$nick!$user\@$host", $mode, $target, $channel);
    }

    if(defined $target && $target eq $event->{conn}->nick) { # bot targeted
      if($mode eq "+o") {
        $self->{pbot}->{logger}->log("$nick opped me in $channel\n");
        $self->{pbot}->{chanops}->{is_opped}->{$channel}{timeout} = gettimeofday + $self->{pbot}->{registry}->get_value('general', 'deop_timeout');;
        delete $self->{pbot}->{chanops}->{op_requested}->{$channel};
        $self->{pbot}->{chanops}->perform_op_commands($channel);
      } 
      elsif($mode eq "-o") {
        $self->{pbot}->{logger}->log("$nick removed my ops in $channel\n");
        delete $self->{pbot}->{chanops}->{is_opped}->{$channel};
      }
      elsif($mode eq "+b") {
        $self->{pbot}->{logger}->log("Got banned in $channel, attempting unban.");
        $event->{conn}->privmsg("chanserv", "unban $channel");
      }    
    } 
    else {  # bot not targeted
      if($mode eq "+b") {
        if($nick eq "ChanServ" or $target =~ m/##fix_your_connection$/i) {
          if ($self->{pbot}->{chanops}->can_gain_ops($channel)) {
            $self->{pbot}->{chanops}->{unban_timeout}->hash->{$channel}->{$target}{timeout} = gettimeofday + $self->{pbot}->{registry}->get_value('bantracker', 'chanserv_ban_timeout');
            $self->{pbot}->{chanops}->{unban_timeout}->save;
          }
        }
      } 
      elsif($mode eq "+q") {
        if($nick ne $event->{conn}->nick) {
          if ($self->{pbot}->{chanops}->can_gain_ops($channel)) {
            $self->{pbot}->{chanops}->{unmute_timeout}->hash->{$channel}->{$target}{timeout} = gettimeofday + $self->{pbot}->{registry}->get_value('bantracker', 'mute_timeout');
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

  $channel = lc $channel;

  my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);
  $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "JOIN", $self->{pbot}->{messagehistory}->{MSG_JOIN});

  $self->{pbot}->{messagehistory}->{database}->devalidate_channel($message_account, $channel);

  my $msg = 'JOIN';

  if (exists $self->{pbot}->{capabilities}->{'extended-join'}) {
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

  $self->{pbot}->{logger}->log("$nick!$user\@$host kicked $target from $channel ($reason)\n");

  my ($message_account) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($target);

  my $hostmask;
  if(defined $message_account) {
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
  
  if(defined $message_account) {
    my $text = "KICKED " . (defined $hostmask ? $hostmask : $target) . " from $channel ($reason)";
    $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, $text, $self->{pbot}->{messagehistory}->{MSG_CHAT});
  }
  return 0;
}

sub on_departure {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel, $args) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to, $event->{event}->args);
  $channel = lc $channel;

  my $text = uc $event->{event}->type;
  $text .= " $args";

  my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);

  if($text =~ m/^QUIT/) {
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

  my $admin = $self->{pbot}->{admins}->find_admin($channel, "$nick!$user\@$host");
  if(defined $admin and $admin->{loggedin} and not $admin->{stayloggedin}) {
    $self->{pbot}->{logger}->log("Whoops, $nick left while still logged in.\n");
    $self->{pbot}->{logger}->log("Logged out $nick.\n");
    delete $admin->{loggedin};
  }
  return 0;
}

sub on_cap {
  my ($self, $event_type, $event) = @_;

  if ($event->{event}->{args}->[0] eq 'ACK') {
    $self->{pbot}->{logger}->log("Client capabilities granted: " . $event->{event}->{args}->[1] . "\n");

    my @caps = split / /, $event->{event}->{args}->[1];
    foreach my $cap (@caps) {
      $self->{pbot}->{capabilities}->{$cap} = 1;
    }
  } else {
    $self->{pbot}->{logger}->log(Dumper $event->{event});
  }
  return 0;
}

sub on_nickchange {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $newnick) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);

  $self->{pbot}->{logger}->log("[NICKCHANGE] $nick!$user\@$host changed nick to $newnick\n");

  if ($newnick eq $self->{pbot}->{registry}->get_value('irc', 'botnick') and not $self->{pbot}->{joined_channels}) {
    my $chans;
    foreach my $chan (keys %{ $self->{pbot}->{channels}->{channels}->hash }) {
      if($self->{pbot}->{channels}->{channels}->hash->{$chan}{enabled}) {
        $chans .= "$chan,";
      }
    }
    $self->{pbot}->{logger}->log("Joining channels: $chans\n");
    $self->{pbot}->{chanops}->join_channel($chans);
    $self->{pbot}->{joined_channels} = 1;
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
  my ($unused, $nick, $msg) = $event->{event}->args;
  my $from = $event->{event}->from;

  $self->{pbot}->{logger}->log("Received nicknameinuse for nick $nick from $from: $msg\n");
  $event->{conn}->privmsg("nickserv", "ghost $nick " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));
  return 0;
}

1;
