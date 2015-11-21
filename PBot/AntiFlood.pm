# File: AntiFlood.pm
# Author: pragma_
#
# Purpose: Tracks message and nickserv statistics to enforce anti-flooding and
# ban-evasion detection.
#
# The nickserv/ban-evasion stuff probably ought to be in BanTracker or some
# such suitable class.

package PBot::AntiFlood;

use warnings;
use strict;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use PBot::DualIndexHashObject;
use PBot::LagChecker;

use Time::HiRes qw(gettimeofday tv_interval);
use Time::Duration;
use Carp ();

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

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  # flags for 'validated' field
  $self->{NICKSERV_VALIDATED}       = (1<<0); 
  $self->{NEEDS_CHECKBAN}           = (1<<1); 

  $self->{channels}      = {}; # per-channel statistics, e.g. for optimized tracking of last spoken nick for enter-abuse detection, etc
  $self->{nickflood}     = {}; # statistics to track nickchange flooding
  $self->{whois_pending} = {}; # prevents multiple whois for nick joining multiple channels at once

  my $filename = delete $conf{banwhitelist_file} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/ban_whitelist';
  $self->{ban_whitelist} = PBot::DualIndexHashObject->new(name => 'BanWhitelist', filename => $filename);
  $self->{ban_whitelist}->load;

  $self->{pbot}->{timer}->register(sub { $self->adjust_offenses }, 60 * 60 * 1);

  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'enforce',                   $conf{enforce_antiflood}         //  1);

  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'join_flood_threshold',      $conf{join_flood_threshold}      //  4);
  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'join_flood_time_threshold', $conf{join_flood_time_threshold} //  60 * 30);
  $self->{pbot}->{registry}->add_default('array', 'antiflood', 'join_flood_punishment',     $conf{join_flood_punishment}     // '28800,3600,86400,604800,2419200,14515200');

  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'chat_flood_threshold',      $conf{chat_flood_threshold}      //  4);
  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'chat_flood_time_threshold', $conf{chat_flood_time_threshold} // 10);
  $self->{pbot}->{registry}->add_default('array', 'antiflood', 'chat_flood_punishment',     $conf{chat_flood_punishment}     // '60,300,3600,86400,604800,2419200');

  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'nick_flood_threshold',      $conf{nick_flood_threshold}      //  3);
  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'nick_flood_time_threshold', $conf{nick_flood_time_threshold} //  60 * 30);
  $self->{pbot}->{registry}->add_default('array', 'antiflood', 'nick_flood_punishment',     $conf{nick_flood_punishment}     // '60,300,3600,86400,604800,2419200');

  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'enter_abuse_threshold',      $conf{enter_abuse_threshold}      //  4);
  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'enter_abuse_time_threshold', $conf{enter_abuse_time_threshold} // 20);
  $self->{pbot}->{registry}->add_default('array', 'antiflood', 'enter_abuse_punishment',     $conf{enter_abuse_punishment}     // '60,300,3600,86400,604800,2419200');
  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'enter_abuse_max_offenses',   $conf{enter_abuse_max_offenses}   //  3);

  $self->{pbot}->{registry}->add_default('text',  'antiflood', 'debug_checkban',             $conf{debug_checkban}             //  0);

  $self->{pbot}->{commands}->register(sub { return $self->unbanme(@_)   },  "unbanme",   0);
  $self->{pbot}->{commands}->register(sub { return $self->whitelist(@_) },  "whitelist", 10);

  $self->{pbot}->{event_dispatcher}->register_handler('irc.whoisaccount', sub { $self->on_whoisaccount(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.endofwhois',   sub { $self->on_endofwhois(@_)   });
}

sub ban_whitelisted {
    my ($self, $channel, $mask) = @_;
    $channel = lc $channel;
    $mask = lc $mask;

    #$self->{pbot}->{logger}->log("whitelist check: $channel, $mask\n");
    return (exists $self->{ban_whitelist}->hash->{$channel}->{$mask} and defined $self->{ban_whitelist}->hash->{$channel}->{$mask}->{ban_whitelisted}) ? 1 : 0;
}

sub whitelist {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;
    $arguments = lc $arguments;

    my ($command, $args) = split / /, $arguments, 2;

    return "Usage: whitelist <command>, where commands are: list/show, add, remove" if not defined $command;

    given($command) {
        when($_ eq "list" or $_ eq "show") {
            my $text = "Ban whitelist:\n";
            my $entries = 0;
            foreach my $channel (keys %{ $self->{ban_whitelist}->hash }) {
                $text .= "  $channel:\n";
                foreach my $mask (keys %{ $self->{ban_whitelist}->hash->{$channel} }) {
                    $text .= "    $mask,\n";
                    $entries++;
                }
            }
            $text .= "none" if $entries == 0;
            return $text;
        }
        when("add") {
            my ($channel, $mask) = split / /, $args, 2;
            return "Usage: whitelist add <channel> <mask>" if not defined $channel or not defined $mask;

            $self->{ban_whitelist}->hash->{$channel}->{$mask}->{ban_whitelisted} = 1;
            $self->{ban_whitelist}->hash->{$channel}->{$mask}->{owner} = "$nick!$user\@$host";
            $self->{ban_whitelist}->hash->{$channel}->{$mask}->{created_on} = gettimeofday;

            $self->{ban_whitelist}->save;
            return "$mask whitelisted in channel $channel";
        }
        when("remove") {
            my ($channel, $mask) = split / /, $args, 2;
            return "Usage: whitelist remove <channel> <mask>" if not defined $channel or not defined $mask;

            if(not defined $self->{ban_whitelist}->hash->{$channel}) {
                return "No whitelists for channel $channel";
            }

            if(not defined $self->{ban_whitelist}->hash->{$channel}->{$mask}) {
                return "No such whitelist $mask for channel $channel";
            }

            delete $self->{ban_whitelist}->hash->{$channel}->{$mask};
            delete $self->{ban_whitelist}->hash->{$channel} if keys %{ $self->{ban_whitelist}->hash->{$channel} } == 0;
            $self->{ban_whitelist}->save;
            return "$mask whitelist removed from channel $channel";
        }
        default {
            return "Unknown command '$command'; commands are: list/show, add, remove";
        }
    }
}

sub update_join_watch {
  my ($self, $account, $channel, $text, $mode) = @_;

  return if $channel =~ /[@!]/; # ignore QUIT messages from nick!user@host channels

  my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'join_watch');

  if($mode == $self->{pbot}->{messagehistory}->{MSG_JOIN}) {
    $channel_data->{join_watch}++;
    $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
  } elsif($mode == $self->{pbot}->{messagehistory}->{MSG_DEPARTURE}) {
    # PART or QUIT
    # check QUIT message for netsplits, and decrement joinwatch to allow a free rejoin
    if($text =~ /^QUIT .*\.net .*\.split/) {
      if($channel_data->{join_watch} > 0) {
        $channel_data->{join_watch}--; 
        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
      }
    }
    # check QUIT message for Ping timeout or Excess Flood
    elsif($text =~ /^QUIT Ping timeout/ or $text =~ /^QUIT Excess Flood/) {
      # ignore these (used to treat aggressively)
    } else {
      # some other type of QUIT or PART
    }
  } elsif($mode == $self->{pbot}->{messagehistory}->{MSG_CHAT}) {
    # reset joinwatch if they send a message
    if($channel_data->{join_watch} > 0) {
      $channel_data->{join_watch} = 0;
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
    }
  }
}

sub check_flood {
  my ($self, $channel, $nick, $user, $host, $text, $max_messages, $max_time, $mode) = @_;
  $channel = lc $channel;

  my $mask = "$nick!$user\@$host";
  my $account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);
  my $oldnick = $nick;

  if($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
    $self->{pbot}->{logger}->log(sprintf("%-18s | %-65s | %s\n", "NICKCHANGE", $mask, $text));

    my ($newnick) = $text =~ m/NICKCHANGE (.*)/;
    $mask = "$newnick!$user\@$host";
    $account = $self->{pbot}->{messagehistory}->get_message_account($newnick, $user, $host);
    $nick = $newnick;
    $self->{nickflood}->{$account}->{changes}++;
  } else {
    $self->{pbot}->{logger}->log(sprintf("%-18s | %-65s | %s\n", lc $channel eq lc $mask ? "QUIT" : $channel, $mask, $text));
  }

  # do not do flood processing for bot messages
  if($nick eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
    $self->{channels}->{$channel}->{last_spoken_nick} = $nick;
    return;
  }

  # handle QUIT events
  # (these events come from $channel nick!user@host, not a specific channel or nick,
  # so they need to be dispatched to all channels the nick has been seen on)
  if($mode == $self->{pbot}->{messagehistory}->{MSG_DEPARTURE} and $text =~ /^QUIT/) {
    my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
    foreach my $chan (@$channels) {
      next if $chan !~ m/^#/;
      $self->update_join_watch($account, $chan, $text, $mode);
    }

    $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($account);
    # don't do flood processing for QUIT events
    return;
  }

  my $channels;

  if($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
    $channels = $self->{pbot}->{nicklist}->get_channels($nick);
  } else {
    $self->update_join_watch($account, $channel, $text, $mode);
    push @$channels, $channel;
  }

  foreach my $channel (@$channels) {
    # do not do flood processing if channel is not in bot's channel list or bot is not set as chanop for the channel
    next if $channel =~ /^#/ and not $self->{pbot}->{chanops}->can_gain_ops($channel);

    if($channel =~ /^#/ and $mode == $self->{pbot}->{messagehistory}->{MSG_DEPARTURE}) {
      # remove validation on PART or KICK so we check for ban-evasion when user returns at a later time
      my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'validated');
      if($channel_data->{validated} & $self->{NICKSERV_VALIDATED}) {
        $channel_data->{validated} &= ~$self->{NICKSERV_VALIDATED};
        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
      }
      next;
    }

    if($max_messages > $self->{pbot}->{registry}->get_value('messagehistory', 'max_messages')) {
      $self->{pbot}->{logger}->log("Warning: max_messages greater than max_messages limit; truncating.\n");
      $max_messages = $self->{pbot}->{registry}->get_value('messagehistory', 'max_messages');
    }

    # check for ban evasion if channel begins with # (not private message) and hasn't yet been validated against ban evasion
    if($channel =~ m/^#/) {
      my $validated = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'validated')->{'validated'};

      if($validated & $self->{NEEDS_CHECKBAN} or not $validated & $self->{NICKSERV_VALIDATED}) {
        if($mode == $self->{pbot}->{messagehistory}->{MSG_DEPARTURE}) {
          # don't check for evasion on PART/KICK
        } elsif ($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
          if (not exists $self->{whois_pending}->{$nick}) {
            $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($account, '');
            $self->{pbot}->{conn}->whois($nick);
            $self->{whois_pending}->{$nick} = gettimeofday;
          }
        } else {
          if (not exists $self->{whois_pending}->{$nick}) {
            $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($account, '');
            $self->{pbot}->{conn}->whois($nick);
            $self->{whois_pending}->{$nick} = gettimeofday;
          }
        }
      }
    }

    # do not do flood enforcement for this event if bot is lagging
    if($self->{pbot}->{lagchecker}->lagging) {
      $self->{pbot}->{logger}->log("Disregarding enforcement of anti-flood due to lag: " . $self->{pbot}->{lagchecker}->lagstring . "\n");
      $self->{channels}->{$channel}->{last_spoken_nick} = $nick;
      return;
    }

    # do not do flood enforcement for logged in bot admins
    if ($self->{pbot}->{registry}->get_value('antiflood', 'dont_enforce_admins') and $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host")) {
      $self->{channels}->{$channel}->{last_spoken_nick} = $nick;
      next;
    }

    # do not do flood enforcement for channels that do not want it
    if ($self->{pbot}->{registry}->get_value($channel, 'dont_enforce_antiflood')) {
      $self->{channels}->{$channel}->{last_spoken_nick} = $nick;
      next;
    }

    # check for chat/join/private message flooding
    if($max_messages > 0 and $self->{pbot}->{messagehistory}->{database}->get_max_messages($account, $channel) >= $max_messages) {
      my $msg;
      if($mode == $self->{pbot}->{messagehistory}->{MSG_CHAT}) {
        $msg = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($account, $channel, $max_messages - 1)
      }
      elsif($mode == $self->{pbot}->{messagehistory}->{MSG_JOIN}) {
        my $joins = $self->{pbot}->{messagehistory}->{database}->get_recent_messages($account, $channel, $max_messages, $self->{pbot}->{messagehistory}->{MSG_JOIN});
        $msg = $joins->[0];
      }
      elsif($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
        my $nickchanges = $self->{pbot}->{messagehistory}->{database}->get_recent_messages($account, $channel, $max_messages, $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE});
        $msg = $nickchanges->[0];
      }
      elsif($mode == $self->{pbot}->{messagehistory}->{MSG_DEPARTURE}) {
        # no flood checks to be done for departure events
        next;
      }
      else {
        $self->{pbot}->{logger}->log("Unknown flood mode [$mode] ... aborting flood enforcement.\n");
        return;
      }

      my $last = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($account, $channel, 0);

      #$self->{pbot}->{logger}->log(" msg: [$msg->{timestamp}] $msg->{msg}\n");
      #$self->{pbot}->{logger}->log("last: [$last->{timestamp}] $last->{msg}\n");
      #$self->{pbot}->{logger}->log("Comparing message timestamps $last->{timestamp} - $msg->{timestamp} = " . ($last->{timestamp} - $msg->{timestamp}) . " against max_time $max_time\n");

      if ($last->{timestamp} - $msg->{timestamp} <= $max_time) {
        if($mode == $self->{pbot}->{messagehistory}->{MSG_JOIN}) {
          my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'offenses', 'last_offense', 'join_watch');
          #$self->{pbot}->{logger}->log("$account offenses $channel_data->{offenses}, join watch $channel_data->{join_watch}, max messages $max_messages\n");
          if($channel_data->{join_watch} >= $max_messages) {
            $channel_data->{offenses}++;
            $channel_data->{last_offense} = gettimeofday;

            if($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
              my $timeout = $self->{pbot}->{registry}->get_array_value('antiflood', 'join_flood_punishment', $channel_data->{offenses} - 1);
              my $duration = duration($timeout);
              my $banmask = address_to_mask($host);

              $self->{pbot}->{chanops}->ban_user_timed("*!$user\@$banmask\$##stop_join_flood", $channel . '-floodbans', $timeout);
              $self->{pbot}->{logger}->log("$nick!$user\@$banmask banned for $duration due to join flooding (offense #" . $channel_data->{offenses} . ").\n");
              $self->{pbot}->{conn}->privmsg($nick, "You have been banned from $channel due to join flooding.  If your connection issues have been fixed, or this was an accident, you may request an unban at any time by responding to this message with: unbanme $channel, otherwise you will be automatically unbanned in $duration.");
            }
            $channel_data->{join_watch} = $max_messages - 2; # give them a chance to rejoin 
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
          } 
        } elsif($mode == $self->{pbot}->{messagehistory}->{MSG_CHAT}) {
          if($channel =~ /^#/) { #channel flood (opposed to private message or otherwise)
            # don't increment offenses again if already banned
            if ($self->{pbot}->{chanops}->has_ban_timeout($channel, "*!$user\@" . address_to_mask($host))) {
              $self->{pbot}->{logger}->log("$nick $channel flood offense disregarded due to existing ban\n");
              next;
            }

            my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'offenses', 'last_offense');
            $channel_data->{offenses}++;
            $channel_data->{last_offense} = gettimeofday;
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);

            if($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
              my $length = $self->{pbot}->{registry}->get_array_value('antiflood', 'chat_flood_punishment', $channel_data->{offenses} - 1);

              $self->{pbot}->{chanops}->ban_user_timed("*!$user\@" . address_to_mask($host), $channel, $length);
              $length = duration($length);
              $self->{pbot}->{logger}->log("$nick $channel flood offense " . $channel_data->{offenses} . " earned $length ban\n");
              $self->{pbot}->{conn}->privmsg($nick, "You have been muted due to flooding.  Please use a web paste service such as http://codepad.org for lengthy pastes.  You will be allowed to speak again in $length.");
            }
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
          }
          else { # private message flood
            my $hostmask = address_to_mask($host);
            $hostmask =~ s/\*/.*/g;
            next if exists $self->{pbot}->{ignorelist}->{ignore_list}->{".*!$user\@$hostmask"}->{$channel};

            my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'offenses', 'last_offense');
            $channel_data->{offenses}++;
            $channel_data->{last_offense} = gettimeofday;
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);

            my $length = $self->{pbot}->{registry}->get_array_value('antiflood', 'chat_flood_punishment', $channel_data->{offenses} - 1);

            $self->{pbot}->{ignorelist}->add(".*!$user\@$hostmask", $channel, $length);
            $length = duration($length);
            $self->{pbot}->{logger}->log("$nick msg flood offense " . $channel_data->{offenses} . " earned $length ignore\n");
            $self->{pbot}->{conn}->privmsg($nick, "You have used too many commands in too short a time period, you have been ignored for $length.");
          }
          next;
        } elsif($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE} and $self->{nickflood}->{$account}->{changes} >= $max_messages) {
          next if $channel !~ /^#/;
          ($nick) = $text =~ m/NICKCHANGE (.*)/;

          $self->{nickflood}->{$account}->{offenses}++;
          $self->{nickflood}->{$account}->{changes} = $max_messages - 2; # allow 1 more change (to go back to original nick)
          $self->{nickflood}->{$account}->{timestamp} = gettimeofday;

          if($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
            my $length = $self->{pbot}->{registry}->get_array_value('antiflood', 'nick_flood_punishment', $self->{nickflood}->{$account}->{offenses} - 1);
            $self->{pbot}->{chanops}->ban_user_timed("*!$user\@" . address_to_mask($host), $channel, $length);
            $length = duration($length);
            $self->{pbot}->{logger}->log("$nick nickchange flood offense " . $self->{nickflood}->{$account}->{offenses} . " earned $length ban\n");
            $self->{pbot}->{conn}->privmsg($nick, "You have been temporarily banned due to nick-change flooding.  You will be unbanned in $length.");
          }
        }
      }
    }

    # check for enter abuse
    if($mode == $self->{pbot}->{messagehistory}->{MSG_CHAT} and $channel =~ m/^#/) {
      my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'enter_abuse', 'enter_abuses', 'offenses');
      my $other_offenses = delete $channel_data->{offenses};
      my $debug_enter_abuse = $self->{pbot}->{registry}->get_value('antiflood', 'debug_enter_abuse');

      if(defined $self->{channels}->{$channel}->{last_spoken_nick} and $nick eq $self->{channels}->{$channel}->{last_spoken_nick}) {
        my $messages = $self->{pbot}->{messagehistory}->{database}->get_recent_messages($account, $channel, 2, $self->{pbot}->{messagehistory}->{MSG_CHAT});

        my $enter_abuse_threshold      = $self->{pbot}->{registry}->get_value($channel, 'enter_abuse_threshold');
        my $enter_abuse_time_threshold = $self->{pbot}->{registry}->get_value($channel, 'enter_abuse_time_threshold');
        my $enter_abuse_max_offenses   = $self->{pbot}->{registry}->get_value($channel, 'enter_abuse_max_offenses');

        $enter_abuse_threshold      = $self->{pbot}->{registry}->get_value('antiflood', 'enter_abuse_threshold') if not defined $enter_abuse_threshold;
        $enter_abuse_time_threshold = $self->{pbot}->{registry}->get_value('antiflood', 'enter_abuse_time_threshold') if not defined $enter_abuse_time_threshold;
        $enter_abuse_max_offenses   = $self->{pbot}->{registry}->get_value('antiflood', 'enter_abuse_max_offenses') if not defined $enter_abuse_max_offenses;

        if($messages->[1]->{timestamp} - $messages->[0]->{timestamp} <= $enter_abuse_time_threshold) {
          if(++$channel_data->{enter_abuse} >= $enter_abuse_threshold - 1) {
            $channel_data->{enter_abuse} = $enter_abuse_threshold / 2 - 1;
            $channel_data->{enter_abuses}++;
            if($channel_data->{enter_abuses} >= $enter_abuse_max_offenses) {
              if($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
                if ($self->{pbot}->{chanops}->has_ban_timeout($channel, "*!$user\@" . address_to_mask($host))) {
                  $self->{pbot}->{logger}->log("$nick $channel enter abuse offense disregarded due to existing ban\n");
                  next;
                }

                my $offenses = $channel_data->{enter_abuses} - $enter_abuse_max_offenses + 1 + $other_offenses;
                my $ban_length = $self->{pbot}->{registry}->get_array_value('antiflood', 'enter_abuse_punishment', $offenses - 1);
                $self->{pbot}->{chanops}->ban_user_timed("*!$user\@" . address_to_mask($host), $channel, $ban_length);
                $ban_length = duration($ban_length);
                $self->{pbot}->{logger}->log("$nick $channel enter abuse offense " . $channel_data->{enter_abuses} . " earned $ban_length ban\n");
                $self->{pbot}->{conn}->privmsg($nick, "You have been muted due to abusing the enter key.  Please do not split your sentences over multiple messages.  You will be allowed to speak again in $ban_length.");
                $channel_data->{last_offense} = gettimeofday;
                $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
                next;
              }
            } else {
              $self->{pbot}->{logger}->log("$nick $channel enter abuses counter incremented to " . $channel_data->{enter_abuses} . "\n") if $debug_enter_abuse;
              if ($channel_data->{enter_abuses} == $enter_abuse_max_offenses - 1 && $channel_data->{enter_abuse} == $enter_abuse_threshold / 2 - 1) {
                if($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
                  $self->{pbot}->{conn}->privmsg($channel, "$nick: Please stop abusing the enter key. Feel free to type longer messages and to take a moment to think of anything else to say before you hit that enter key.");
                }
              }
            }
          } else {
            $self->{pbot}->{logger}->log("$nick $channel enter abuse counter incremented to " . $channel_data->{enter_abuse} . "\n") if $debug_enter_abuse;
          }
          $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
        } else {
          if($channel_data->{enter_abuse} > 0) {
            $self->{pbot}->{logger}->log("$nick $channel more than $enter_abuse_time_threshold seconds since last message, enter abuse counter reset\n") if $debug_enter_abuse;
            $channel_data->{enter_abuse} = 0;
            $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
          }
        }
      } else {
        $self->{channels}->{$channel}->{last_spoken_nick} = $nick;
        $self->{pbot}->{logger}->log("last spoken nick set to $nick\n") if $debug_enter_abuse;
        if($channel_data->{enter_abuse} > 0) {
          $self->{pbot}->{logger}->log("$nick $channel enter abuse counter reset\n") if $debug_enter_abuse;
          $channel_data->{enter_abuse} = 0;
          $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
        }
      }
    }
  }
}

sub unbanme {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $channel = lc $arguments;

  if(not $arguments or not $channel) {
    return "/msg $nick Usage: unbanme <channel>";
  }

  my %unbanned;

  my %aliases = $self->{pbot}->{messagehistory}->{database}->get_also_known_as($nick);

  foreach my $alias (keys %aliases) {
    next if $aliases{$alias}->{type} == $self->{pbot}->{messagehistory}->{database}->{alias_type}->{WEAK};

    my ($anick, $auser, $ahost) = $alias =~ m/([^!]+)!([^@]+)@(.*)/;
    my $banmask = address_to_mask($ahost);

    my $mask = "*!$auser\@$banmask\$##stop_join_flood";
    next if exists $unbanned{$mask};
    next if not $self->{pbot}->{chanops}->{unban_timeout}->find_index($channel . '-floodbans', $mask);

    my $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($anick, $auser, $ahost);
    my @nickserv_accounts = $self->{pbot}->{messagehistory}->{database}->get_nickserv_accounts($message_account);

    push @nickserv_accounts, undef;

    foreach my $nickserv_account (@nickserv_accounts) {
      my $baninfos = $self->{pbot}->{bantracker}->get_baninfo("$anick!$auser\@$ahost", $channel, $nickserv_account);

      if(defined $baninfos) {
        foreach my $baninfo (@$baninfos) {
          if($self->ban_whitelisted($baninfo->{channel}, $baninfo->{banmask})) {
            $self->{pbot}->{logger}->log("anti-flood: [unbanme] $anick!$auser\@$ahost banned as $baninfo->{banmask} in $baninfo->{channel}, but allowed through whitelist\n");
          } else {
            if($channel eq lc $baninfo->{channel}) {
              my $mode = $baninfo->{type} eq "+b" ? "banned" : "quieted";
              $self->{pbot}->{logger}->log("anti-flood: [unbanme] $anick!$auser\@$ahost $mode as $baninfo->{banmask} in $baninfo->{channel} by $baninfo->{owner}, unbanme rejected\n");
              return "/msg $nick You have been $mode as $baninfo->{banmask} by $baninfo->{owner}, unbanme will not work until it is removed.";
            }
          }
        }
      }
    }

    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'offenses');
    if($channel_data->{offenses} > 1) {
      return "/msg $nick You may only use unbanme for the first offense. You will be automatically unbanned in a few hours, and your offense counter will decrement once every 24 hours.";
    }

    $self->{pbot}->{chanops}->unban_user($mask, $channel . '-floodbans');
    $unbanned{$mask}++;
  }

  if (keys %unbanned) {
    return "/msg $nick You have been unbanned from $channel.";
  } else {
    return "/msg $nick There is no temporary join-flooding ban set for you in channel $channel.";
  }
}

sub address_to_mask {
  my $address = shift;
  my $banmask;

  if($address =~ m/^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/) {
    my ($a, $b, $c, $d) = ($1, $2, $3, $4);
    given($a) {
      when($_ <= 127) { $banmask = "$a.*"; }
      when($_ <= 191) { $banmask = "$a.$b.*"; }
      default { $banmask = "$a.$b.$c.*"; }
    }
  } elsif($address =~ m{^gateway/([^/]+)/([^/]+)/}) {
    $banmask = "gateway/$1/$2/*";
  } elsif($address =~ m{^nat/([^/]+)/}) {
    $banmask = "nat/$1/*";
  } elsif($address =~ m/^([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)$/) {
    $banmask = "$1:$2:*";
  } elsif($address =~ m/[^.]+\.([^.]+\.[a-zA-Z]+)$/) {
    $banmask = "*.$1";
  } else {
    $banmask = $address;
  }

  return $banmask;
}

sub devalidate_accounts {
  # remove validation on accounts in $channel that match a ban/quiet $mask
  my ($self, $mask, $channel) = @_;
  my @message_accounts;

  #$self->{pbot}->{logger}->log("Devalidating accounts for $mask in $channel\n");

  if($mask =~ m/^\$a:(.*)/) {
    my $ban_account = lc $1;
    @message_accounts = $self->{pbot}->{messagehistory}->{database}->find_message_accounts_by_nickserv($ban_account);
  } else {
    @message_accounts = $self->{pbot}->{messagehistory}->{database}->find_message_accounts_by_mask($mask);
  }

  foreach my $account (@message_accounts) {
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'validated');
    if(defined $channel_data and $channel_data->{validated} & $self->{NICKSERV_VALIDATED}) {
      $channel_data->{validated} &= ~$self->{NICKSERV_VALIDATED};
      #$self->{pbot}->{logger}->log("Devalidating account $account\n");
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
    }
  }
}

sub check_bans {
  my ($self, $message_account, $mask, $channel) = @_;

  return if not $self->{pbot}->{chanops}->can_gain_ops($channel);

  my $debug_checkban = $self->{pbot}->{registry}->get_value('antiflood', 'debug_checkban');

  $self->{pbot}->{logger}->log("anti-flood: [check-bans] checking for bans on $mask in $channel\n") if $debug_checkban >= 1;

  my $current_nickserv_account = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($message_account);

  if ($current_nickserv_account) {
    $self->{pbot}->{logger}->log("anti-flood: [check-bans] current nickserv [$current_nickserv_account] found for $mask\n") if $debug_checkban >= 2;
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
    if ($channel_data->{validated} & $self->{NEEDS_CHECKBAN}) {
      $channel_data->{validated} &= ~$self->{NEEDS_CHECKBAN};
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
    }
  } else {
    # mark this account as needing check-bans when nickserv account is identified
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
    if(not $channel_data->{validated} & $self->{NEEDS_CHECKBAN}) {
      $channel_data->{validated} |= $self->{NEEDS_CHECKBAN};
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
    }
    $self->{pbot}->{logger}->log("anti-flood: [check-bans] no account for $mask; marking for later validation\n") if $debug_checkban >= 1;
  }

  my ($nick) = $mask =~ m/^([^!]+)/;
  my %aliases = $self->{pbot}->{messagehistory}->{database}->get_also_known_as($nick);

  my ($do_not_validate, $bans);
  foreach my $alias (keys %aliases) {
    next if $alias =~ /^Guest\d+(?:!.*)?$/;

    if ($aliases{$alias}->{type} == $self->{pbot}->{messagehistory}->{database}->{alias_type}->{WEAK}) {
      $self->{pbot}->{logger}->log("anti-flood: [check-bans] skipping WEAK alias $alias in channel $channel\n") if $debug_checkban >= 2;
      next;
    }

    $self->{pbot}->{logger}->log("anti-flood: [check-bans] checking blacklist for $alias in channel $channel\n") if $debug_checkban >= 5;
    if ($self->{pbot}->{blacklist}->check_blacklist($alias, $channel)) {
      my $baninfo = {};
      $baninfo->{banmask} = $alias;
      $baninfo->{channel} = $channel;
      $baninfo->{owner} = 'blacklist';
      $baninfo->{when} = 0;
      $baninfo->{type} = 'blacklist';
      push @$bans, $baninfo;
      next;
    }

    my @nickservs;

    if (exists $aliases{$alias}->{nickserv}) {
      @nickservs = split /,/, $aliases{$alias}->{nickserv};
    } else {
      @nickservs = (undef);
    }

    foreach my $nickserv (@nickservs) {
      $self->{pbot}->{logger}->log("anti-flood: [check-bans] checking for bans in $channel on $alias using nickserv " . (defined $nickserv ? $nickserv : "[undefined]") . "\n") if $debug_checkban >= 2;
      my $baninfos = $self->{pbot}->{bantracker}->get_baninfo($alias, $channel, $nickserv);

      if(defined $baninfos) {
        foreach my $baninfo (@$baninfos) {
          if(time - $baninfo->{when} < 5) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask [$alias] evaded $baninfo->{banmask} in $baninfo->{channel}, but within 5 seconds of establishing ban; giving another chance\n");
            my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
            if($channel_data->{validated} & $self->{NICKSERV_VALIDATED}) {
              $channel_data->{validated} &= ~$self->{NICKSERV_VALIDATED};
              $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
            }
            $do_not_validate = 1;
            next;
          }

          if($self->ban_whitelisted($baninfo->{channel}, $baninfo->{banmask})) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask [$alias] evaded $baninfo->{banmask} in $baninfo->{channel}, but allowed through whitelist\n");
            next;
          } 

          my $banmask_regex = quotemeta $baninfo->{banmask};
          $banmask_regex =~ s/\\\*/.*/g;
          $banmask_regex =~ s/\\\?/./g;

          if($baninfo->{type} eq '+q' and $mask =~ /^$banmask_regex$/i) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] Hostmask ($mask) matches quiet banmask ($banmask_regex), disregarding\n");
            next;
          }

          if(defined $nickserv and $baninfo->{type} eq '+q' and $baninfo->{banmask} =~ /^\$a:(.*)/ and lc $1 eq $nickserv and $nickserv eq $current_nickserv_account) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] Hostmask ($mask) matches quiet on account ($nickserv), disregarding\n");
            next;
          }

          if(not defined $bans) {
            $bans = [];
          }

          $self->{pbot}->{logger}->log("anti-flood: [check-bans] Hostmask ($mask [$alias" . (defined $nickserv ? "/$nickserv" : "") . "]) matches $baninfo->{type} $baninfo->{banmask}, adding ban\n");
          push @$bans, $baninfo;
          goto GOT_BAN;
        }
      }
    }
  }

  GOT_BAN:
  if(defined $bans) {
    foreach my $baninfo (@$bans) {
      my $banmask;

      my ($user, $host) = $mask =~ m/[^!]+!([^@]+)@(.*)/;
      if ($host =~ m{^([^/]+)/.+} and $1 ne 'gateway' and $1 ne 'nat') {
        $banmask = "*!*\@$host";
      } elsif ($current_nickserv_account and $baninfo->{banmask} !~ m/^\$a:/i) {
        $banmask = "\$a:$current_nickserv_account";
      } else {
        $banmask = "*!$user@" . address_to_mask($host);
      }

      $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask evaded $baninfo->{banmask} banned in $baninfo->{channel} by $baninfo->{owner}, banning $banmask\n");
      my ($bannick) = $mask =~ m/^([^!]+)/;
      if($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
        if ($self->{pbot}->{chanops}->has_ban_timeout($baninfo->{channel}, $banmask)) {
          $self->{pbot}->{logger}->log("anti-flood: [check-bans] $banmask already banned in $channel, disregarding\n");
          return;
        }

        if ($baninfo->{type} eq 'blacklist') {
          $self->{pbot}->{chanops}->add_op_command($baninfo->{channel}, "kick $baninfo->{channel} $bannick I don't think so");
        } else {
          my $owner = $baninfo->{owner};
          $owner =~ s/!.*$//;
          $self->{pbot}->{chanops}->add_op_command($baninfo->{channel}, "kick $baninfo->{channel} $bannick Evaded $baninfo->{banmask} set by $owner");
        }
        $self->{pbot}->{chanops}->ban_user_timed($banmask, $baninfo->{channel}, 60 * 60 * 24 * 3);
      }
      my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
      if($channel_data->{validated} & $self->{NICKSERV_VALIDATED}) {
        $channel_data->{validated} &= ~$self->{NICKSERV_VALIDATED};
        $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
      }
      return;
    }
  }

  unless($do_not_validate) {
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
    if(not $channel_data->{validated} & $self->{NICKSERV_VALIDATED}) {
      $channel_data->{validated} |= $self->{NICKSERV_VALIDATED};
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
    }
  }
}

sub check_nickserv_accounts {
  my ($self, $nick, $account, $hostmask) = @_;
  my $message_account;

  #$self->{pbot}->{logger}->log("Checking nickserv accounts for nick $nick with account $account and hostmask " . (defined $hostmask ? $hostmask : 'undef') . "\n");

  $account = lc $account;

  if(not defined $hostmask) {
    ($message_account, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);

    if(not defined $message_account) {
      $self->{pbot}->{logger}->log("No message account found for nick $nick.\n");
      ($message_account) = $self->{pbot}->{messagehistory}->{database}->find_message_accounts_by_nickserv($account);

      if(not $message_account) {
        $self->{pbot}->{logger}->log("No message account found for nickserv $account.\n");
        return;
      }
    }
  } else {
    ($message_account) = $self->{pbot}->{messagehistory}->{database}->find_message_accounts_by_mask($hostmask);
    if(not $message_account) {
      $self->{pbot}->{logger}->log("No message account found for hostmask $hostmask.\n");
      return;
    }
  }

  #$self->{pbot}->{logger}->log("anti-flood: $message_account: setting nickserv account to [$account]\n");
  $self->{pbot}->{messagehistory}->{database}->update_nickserv_account($message_account, $account, scalar gettimeofday);
  $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($message_account, $account);
}

sub on_endofwhois {
  my ($self, $event_type, $event) = @_;
  my $nick = $event->{event}->{args}[1];

  delete $self->{whois_pending}->{$nick};

  my ($id, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);
  # $self->{pbot}->{logger}->log("endofwhois: Found [$id][$hostmask] for [$nick]\n");
  $self->{pbot}->{messagehistory}->{database}->link_aliases($id, $hostmask) if $id;

  # check to see if any channels need check-ban validation
  my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
  foreach my $channel (@$channels) {
    next unless $channel =~ /^#/;
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($id, $channel, 'validated');
    if ($channel_data->{validated} & $self->{NEEDS_CHECKBAN} or not $channel_data->{validated} & $self->{NICKSERV_VALIDATED}) {
      $self->check_bans($id, $hostmask, $channel);
    }
  }

  return 0;
}

sub on_whoisaccount {
  my ($self, $event_type, $event) = @_;
  my $nick    =    $event->{event}->{args}[1];
  my $account = lc $event->{event}->{args}[2];

  if ($self->{pbot}->{registry}->get_value('antiflood', 'debug_checkban')) {
    $self->{pbot}->{logger}->log("$nick is using NickServ account [$account]\n");
  }

  my ($id, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);
  # $self->{pbot}->{logger}->log("whoisaccount: Found [$id][$hostmask][$account] for [$nick]\n");
  $self->{pbot}->{messagehistory}->{database}->link_aliases($id, undef, $account) if $id;

  $self->check_nickserv_accounts($nick, $account);

  return 0;
}

sub adjust_offenses {
  my $self = shift;

  #$self->{pbot}->{logger}->log("Adjusting offenses . . .\n");

  # decrease offenses counter if 24 hours have elapsed since latest offense
  my $channel_datas = $self->{pbot}->{messagehistory}->{database}->get_channel_datas_where_last_offense_older_than(gettimeofday - 60 * 60 * 24);
  foreach my $channel_data (@$channel_datas) {
    if($channel_data->{offenses} > 0) {
      my $id = delete $channel_data->{id};
      my $channel = delete $channel_data->{channel};
      $channel_data->{offenses}--;
      $channel_data->{last_offense} = gettimeofday;
      #$self->{pbot}->{logger}->log("[adjust-offenses] [$id][$channel] 24 hours since last offense/decrease -- decreasing offenses to $channel_data->{offenses}\n");
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($id, $channel, $channel_data);
    }
  }

  $channel_datas = $self->{pbot}->{messagehistory}->{database}->get_channel_datas_with_enter_abuses();
  foreach my $channel_data (@$channel_datas) {
    my $id = delete $channel_data->{id};
    my $channel = delete $channel_data->{channel};
    my $last_offense = delete $channel_data->{last_offense};
    if(gettimeofday - $last_offense >= 60 * 60 * 2) {
      $channel_data->{enter_abuses}--;
      #$self->{pbot}->{logger}->log("[adjust-offenses] [$id][$channel] decreasing enter abuse offenses to $channel_data->{enter_abuses}\n");
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($id, $channel, $channel_data);
    }
  }

  foreach my $account (keys %{ $self->{nickflood} }) {
    if($self->{nickflood}->{$account}->{offenses} and gettimeofday - $self->{nickflood}->{$account}->{timestamp} >= 60 * 60 * 3) {
      $self->{nickflood}->{$account}->{offenses}--;

      if($self->{nickflood}->{$account}->{offenses} == 0) {
        delete $self->{nickflood}->{$account};
      } else {
        $self->{nickflood}->{$account}->{timestamp} = gettimeofday;
      }
    }
  }
}

1;
