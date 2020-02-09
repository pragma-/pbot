# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::AntiRepeat;
use parent 'Plugins::Plugin';

use warnings; use strict;
use feature 'unicode_strings';

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use String::LCSS qw/lcss/;
use Time::HiRes qw/gettimeofday/;
use POSIX qw/strftime/;

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot}->{registry}->add_default('text', 'antiflood', 'antirepeat',           $conf{antirepeat}           // 1);
  $self->{pbot}->{registry}->add_default('text', 'antiflood', 'antirepeat_threshold', $conf{antirepeat_threshold} // 2.5);
  $self->{pbot}->{registry}->add_default('text', 'antiflood', 'antirepeat_match',     $conf{antirepeat_match}     // 0.5);
  $self->{pbot}->{registry}->add_default('text', 'antiflood', 'antirepeat_allow_bot', $conf{antirepeat_allow_bot} // 1);

  $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_public(@_) });

  $self->{pbot}->{timer}->register(sub { $self->adjust_offenses }, 60 * 60 * 1, 'antirepeat');
  $self->{offenses} = {};
}

sub unload {
  my $self = shift;
  $self->{pbot}->{timer}->unregister('antirepeat');
  $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
  $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
}

sub on_public {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
  my $channel = lc $event->{event}->{to}[0];

  ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

  return 0 if not $self->{pbot}->{registry}->get_value('antiflood', 'antirepeat');

  my $antirepeat = $self->{pbot}->{registry}->get_value($channel, 'antirepeat');
  return 0 if defined $antirepeat and not $antirepeat;

  return 0 if $self->{pbot}->{registry}->get_value($channel, 'dont_enforce_antiflood');

  return 0 if $channel !~ m/^#/;
  return 0 if $event->{interpreted};
  return 0 if $self->{pbot}->{antiflood}->whitelisted($channel, "$nick!$user\@$host", 'antiflood');
  return 0 if $self->{pbot}->{users}->loggedin_admin($channel, "$nick!$user\@$host");

  my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

  # don't enforce anti-repeat for unreg spam
  my $chanmodes = $self->{pbot}->{channels}->get_meta($channel, 'MODE');
  if (defined $chanmodes and $chanmodes =~ m/z/ and exists $self->{pbot}->{bantracker}->{banlist}->{$channel}->{'+q'}->{'$~a'}) {
    my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($account);
    return 0 if not defined $nickserv or not length $nickserv;
  }

  my $messages = $self->{pbot}->{messagehistory}->{database}->get_recent_messages($account, $channel, 6, $self->{pbot}->{messagehistory}->{MSG_CHAT});

  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

  my $bot_trigger = $self->{pbot}->{registry}->get_value($channel, 'trigger')
    // $self->{pbot}->{registry}->get_value('general', 'trigger');

  my $allow_bot = $self->{pbot}->{registry}->get_value($channel, 'antirepeat_allow_bot')
    // $self->{pbot}->{registry}->get_value('antiflood', 'antirepeat_allow_bot');

  my $match = $self->{pbot}->{registry}->get_value($channel, 'antirepeat_match')
    // $self->{pbot}->{registry}->get_value('antiflood', 'antirepeat_match');

  my %matches;
  my $now = gettimeofday;

  foreach my $string1 (@$messages) {
    next if $now - $string1->{timestamp} > 60 * 60 * 2;
    next if $allow_bot and $string1->{msg} =~ m/^(?:$bot_trigger|$botnick.?)/;
    $string1->{msg} =~ s/^[^;,:]{1,20}[;,:]//; # remove nick-like prefix if one exists
    next if length $string1->{msg} <= 5;  # allow really short messages since "yep" "ok" etc are so common

    if (exists $self->{offenses}->{$account} and exists $self->{offenses}->{$account}->{$channel}) {
      next if $self->{offenses}->{$account}->{$channel}->{last_offense} >= $string1->{timestamp};
    }

    foreach my $string2 (@$messages) {
      next if $now - $string2->{timestamp} > 60 * 60 * 2;
      next if $allow_bot and $string2->{msg} =~ m/^(?:$bot_trigger|$botnick.?)/;
      $string2->{msg} =~ s/^[^;,:]{1,20}[;,:]//; # remove nick-like prefix if one exists
      next if length $string2->{msg} <= 5;  # allow really short messages since "yep" "ok" etc are so common

      if (exists $self->{offenses}->{$account} and exists $self->{offenses}->{$account}->{$channel}) {
        next if $self->{offenses}->{$account}->{$channel}->{last_offense} >= $string2->{timestamp};
      }

      my $string = lcss(lc $string1->{msg}, lc $string2->{msg});

      if (defined $string) {
        my $length = length $string;
        my $length1 = $length / length $string1->{msg};
        my $length2 = $length / length $string2->{msg};

        if ($length1 >= $match && $length2 >= $match) {
          $matches{$string}++;
        }
      }
    }
  }

  my $threshold = $self->{pbot}->{registry}->get_value($channel, 'antirepeat_threshold')
    // $self->{pbot}->{registry}->get_value('antiflood', 'antirepeat_threshold');

  foreach my $match (keys %matches) {
    if (sqrt $matches{$match} > $threshold) {
      $self->{offenses}->{$account}->{$channel}->{last_offense} = gettimeofday;
      $self->{offenses}->{$account}->{$channel}->{last_adjustment} = gettimeofday;
      $self->{offenses}->{$account}->{$channel}->{offenses}++;

      $self->{pbot}->{logger}->log("$nick!$user\@$host triggered anti-repeat; offense $self->{offenses}->{$account}->{$channel}->{offenses}\n");

      given ($self->{offenses}->{$account}->{$channel}->{offenses}) {
        when (1) {
          $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $nick Stop repeating yourself");
          $self->{pbot}->{chanops}->gain_ops($channel);
        }
        when (2) {
          $self->{pbot}->{chanops}->ban_user_timed($botnick, 'repeating messages', "*!*\@$host", $channel, 60);
        }
        when (3) {
          $self->{pbot}->{chanops}->ban_user_timed($botnick, 'repeating messages', "*!*\@$host", $channel, 60 * 15);
        }
        default {
          $self->{pbot}->{chanops}->ban_user_timed($botnick, 'repeating messages', "*!*\@$host", $channel, 60 * 60);
        }
      }
      return 0;
    }
  }
  return 0;
}

sub adjust_offenses {
  my $self = shift;
  my $now = gettimeofday;

  foreach my $account (keys %{ $self->{offenses} }) {
    foreach my $channel (keys %{ $self->{offenses}->{$account} }) {
      if ($self->{offenses}->{$account}->{$channel}->{offenses} > 0 and $now - $self->{offenses}->{$account}->{$channel}->{last_adjustment} > 60 * 60 * 3) {
        $self->{offenses}->{$account}->{$channel}->{offenses}--;

        if ($self->{offenses}->{$account}->{$channel}->{offenses} <= 0) {
          delete $self->{offenses}->{$account}->{$channel};
          if (keys %{ $self->{offenses}->{$account} } == 0) {
            delete $self->{offenses}->{$account};
          }
        } else {
          $self->{offenses}->{$account}->{$channel}->{last_adjustment} = $now;
        }
      }
    }
  }
}

1;
