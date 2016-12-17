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
use POSIX qw/strftime/;
use Text::CSV;
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
  $self->{changinghost}  = {}; # tracks nicks changing hosts/identifying to strongly link them

  my $filename = delete $conf{whitelist_file} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/whitelist';
  $self->{whitelist} = PBot::DualIndexHashObject->new(name => 'Whitelist', filename => $filename);
  $self->{whitelist}->load;

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

  $self->{pbot}->{event_dispatcher}->register_handler('irc.whoisaccount', sub { $self->on_whoisaccount(@_)  });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.whoisuser',    sub { $self->on_whoisuser(@_)     });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.endofwhois',   sub { $self->on_endofwhois(@_)    });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.account',      sub { $self->on_accountnotify(@_) });
}

sub whitelisted {
  my ($self, $channel, $hostmask, $mode) = @_;
  $channel = lc $channel;
  $hostmask = lc $hostmask;
  $mode = 'user' if not defined $mode;

  given ($mode) {
    when ('ban') {
      return 1 if exists $self->{whitelist}->hash->{$channel}
        and exists $self->{whitelist}->hash->{$channel}->{$hostmask}
        and $self->{whitelist}->hash->{$channel}->{$hostmask}->{ban};
      return 0;
    }

    default {
      my $ret = eval {
        foreach my $chan (keys %{ $self->{whitelist}->hash }) {
          next unless $channel =~ m/^$chan$/i;
          foreach my $mask (keys %{ $self->{whitelist}->hash->{$chan} }) {
            next if $self->{whitelist}->hash->{$chan}->{$mask}->{ban};
            return 1 if $hostmask =~ m/^$mask$/i and $self->{whitelist}->hash->{$chan}->{$mask}->{$mode};
          }
        }
        return 0;
      };

      if ($@) {
        $self->{pbot}->{logger}->log("Error in whitelist: $@");
        return 0;
      }

      return $ret;
    }
  }
}

sub whitelist {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  $arguments = lc $arguments;

  my ($command, $args) = split / /, $arguments, 2;

  return "Usage: whitelist <command>, where commands are: list/show, add, remove, set, unset" if not defined $command;

  given ($command) {
    when ($_ eq "list" or $_ eq "show") {
      my $text = "Whitelist:\n";
      my $entries = 0;
      foreach my $channel (keys %{ $self->{whitelist}->hash }) {
        $text .= "  $channel:\n";
        foreach my $mask (keys %{ $self->{whitelist}->hash->{$channel} }) {
          my $mode = '';
          $mode .= 'u' if $self->{whitelist}->hash->{$channel}->{$mask}->{user};
          $mode .= 'b' if $self->{whitelist}->hash->{$channel}->{$mask}->{ban};
          $mode .= 'a' if $self->{whitelist}->hash->{$channel}->{$mask}->{antiflood};
          $mode = '?' if not length $mode;
          $text .= "    $mask [$mode],\n";
          $entries++;
        }
      }
      $text .= "none" if $entries == 0;
      return $text;
    }
    when ("set") {
      my ($channel, $mask, $flag, $value) = split / /, $args, 4;
      return "Usage: whitelist set <channel> <mask> [flag] [value]" if not defined $channel or not defined $mask;

      if (not exists $self->{whitelist}->hash->{$channel}) {
        return "There is no such channel `$channel` in the whitelist.";
      }

      if (not exists $self->{whitelist}->hash->{$channel}->{$mask}) {
        return "There is no such mask `$mask` for channel `$channel` in the whitelist.";
      }

      if (not defined $flag) {
        my $text = "Flags:\n";
        my $comma = '';
        foreach $flag (keys %{ $self->{whitelist}->hash->{$channel}->{$mask} }) {
          if ($flag eq 'created_on') {
            my $timestamp = strftime "%a %b %e %H:%M:%S %Z %Y", localtime $self->{whitelist}->hash->{$channel}->{$mask}->{$flag};
            $text .= $comma . "created_on: $timestamp";
          } else {
            $value = $self->{whitelist}->hash->{$channel}->{$mask}->{$flag};
            $text .= $comma .  "$flag: $value";
          }
          $comma = ",\n  ";
        }
        return $text;
      }

      if (not defined $value) {
        $value = $self->{whitelist}->hash->{$channel}->{$mask}->{$flag};
        if (not defined $value) {
          return "$flag is not set.";
        } else {
          return "$flag is set to $value";
        }
      }

      $self->{whitelist}->hash->{$channel}->{$mask}->{$flag} = $value;
      $self->{whitelist}->save;
      return "Flag set.";
    }
    when ("unset") {
      my ($channel, $mask, $flag) = split / /, $args, 3;
      return "Usage: whitelist unset <channel> <mask> <flag>" if not defined $channel or not defined $mask or not defined $flag;

      if (not exists $self->{whitelist}->hash->{$channel}) {
        return "There is no such channel `$channel` in the whitelist.";
      }

      if (not exists $self->{whitelist}->hash->{$channel}->{$mask}) {
        return "There is no such mask `$mask` for channel `$channel` in the whitelist.";
      }

      if (not exists $self->{whitelist}->hash->{$channel}->{$mask}->{$flag}) {
        return "There is no such flag `$flag` for mask `$mask` for channel `$channel` in the whitelist.";
      }

      delete $self->{whitelist}->hash->{$channel}->{$mask}->{$flag};
      $self->{whitelist}->save;
      return "Flag unset.";
    }
    when ("add") {
      my ($channel, $mask, $mode) = split / /, $args, 3;
      return "Usage: whitelist add <channel> <mask> [mode (user or ban, default: user)]" if not defined $channel or not defined $mask;

      $mode = 'user' if not defined $mode;

      if ($mode eq 'user') {
        $self->{whitelist}->hash->{$channel}->{$mask}->{user} = 1;
      } else {
        $self->{whitelist}->hash->{$channel}->{$mask}->{ban} = 1;
      }
      $self->{whitelist}->hash->{$channel}->{$mask}->{owner} = "$nick!$user\@$host";
      $self->{whitelist}->hash->{$channel}->{$mask}->{created_on} = gettimeofday;

      $self->{whitelist}->save;
      return "$mask whitelisted in channel $channel";
    }
    when ("remove") {
      my ($channel, $mask) = split / /, $args, 2;
      return "Usage: whitelist remove <channel> <mask>" if not defined $channel or not defined $mask;

      if(not defined $self->{whitelist}->hash->{$channel}) {
        return "No whitelists for channel $channel";
      }

      if(not defined $self->{whitelist}->hash->{$channel}->{$mask}) {
        return "No such whitelist $mask for channel $channel";
      }

      delete $self->{whitelist}->hash->{$channel}->{$mask};
      delete $self->{whitelist}->hash->{$channel} if keys %{ $self->{whitelist}->hash->{$channel} } == 0;
      $self->{whitelist}->save;
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
    elsif($text =~ /^QUIT Excess Flood/ or $text =~ /^QUIT Max SendQ exceeded/) {
      # treat these as an extra join so they're snagged more quickly since these usually will keep flooding
      $channel_data->{join_watch}++;
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
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
  my $oldnick = $nick;
  my $account;

  if ($mode == $self->{pbot}->{messagehistory}->{MSG_JOIN} and exists $self->{changinghost}->{$nick}) {
    $self->{pbot}->{logger}->log("Finalizing changinghost for $nick!\n");
    $account = delete $self->{changinghost}->{$nick};

    my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_id($mask);
    if (defined $id) {
      if ($id != $account) {
        $self->{pbot}->{logger}->log("Linking $mask [$id] to account $account\n");
        $self->{pbot}->{messagehistory}->{database}->link_alias($account, $id, $self->{pbot}->{messagehistory}->{database}->{alias_type}->{STRONG}, 1);
      } else {
        $self->{pbot}->{logger}->log("New hostmask already belongs to original account.\n");
      }
      $account = $id;
    } else {
      $self->{pbot}->{logger}->log("Adding $mask to account $account\n");
      $self->{pbot}->{messagehistory}->{database}->add_message_account($mask, $account, $self->{pbot}->{messagehistory}->{database}->{alias_type}->{STRONG});
    }

    $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($account);
    my @nickserv_accounts = $self->{pbot}->{messagehistory}->{database}->get_nickserv_accounts($account);
    foreach my $nickserv_account (@nickserv_accounts) {
      $self->{pbot}->{logger}->log("$nick!$user\@$host [$account] seen with nickserv account [$nickserv_account]\n");
      $self->check_nickserv_accounts($nick, $nickserv_account, "$nick!$user\@$host");
    }
  } else {
    $account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);
  }

  $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($mask, { last_seen => scalar gettimeofday });

  if($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
    $self->{pbot}->{logger}->log(sprintf("%-18s | %-65s | %s\n", "NICKCHANGE", $mask, $text));

    my ($newnick) = $text =~ m/NICKCHANGE (.*)/;
    $mask = "$newnick!$user\@$host";
    $account = $self->{pbot}->{messagehistory}->get_message_account($newnick, $user, $host);
    $nick = $newnick;
  } else {
    $self->{pbot}->{logger}->log(sprintf("%-18s | %-65s | %s\n", lc $channel eq lc $mask ? "QUIT" : $channel, $mask, $text));
  }

  # do not do flood processing for bot messages
  if($nick eq $self->{pbot}->{registry}->get_value('irc', 'botnick')) {
    $self->{channels}->{$channel}->{last_spoken_nick} = $nick;
    return;
  }

  my $ancestor = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);
  $self->{pbot}->{logger}->log("Processing anti-flood account $account " . ($ancestor != $account ? "[ancestor $ancestor] " : '') . "for mask $mask\n") if $self->{pbot}->{registry}->get_value('antiflood', 'debug_account');

  if ($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
    $self->{nickflood}->{$ancestor}->{changes}++;
    $self->{pbot}->{logger}->log("account $ancestor has $self->{nickflood}->{$ancestor}->{changes} nickchanges\n");
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

    if ($text eq 'QUIT Changing host') {
      $self->{pbot}->{logger}->log("$mask [$account] changing host!\n");
      $self->{changinghost}->{$nick} = $account;
    }

    # don't do flood processing for QUIT events
    return;
  }

  my $channels;

  if($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
    $channels = $self->{pbot}->{nicklist}->get_channels($oldnick);
  } else {
    $self->update_join_watch($account, $channel, $text, $mode);
    push @$channels, $channel;
  }

  foreach my $channel (@$channels) {
    $channel = lc $channel;
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

    if($self->whitelisted($channel, "$nick!$user\@$host", 'antiflood')) {
      next;
    }

    if($max_messages > $self->{pbot}->{registry}->get_value('messagehistory', 'max_messages')) {
      $self->{pbot}->{logger}->log("Warning: max_messages greater than max_messages limit; truncating.\n");
      $max_messages = $self->{pbot}->{registry}->get_value('messagehistory', 'max_messages');
    }

    # check for ban evasion if channel begins with # (not private message) and hasn't yet been validated against ban evasion
    if($channel =~ m/^#/) {
      my $validated = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'validated')->{'validated'};

      if ($validated & $self->{NEEDS_CHECKBAN} or not $validated & $self->{NICKSERV_VALIDATED}) {
        if($mode == $self->{pbot}->{messagehistory}->{MSG_DEPARTURE}) {
          # don't check for evasion on PART/KICK
        } elsif ($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
          if (not exists $self->{whois_pending}->{$nick}) {
            $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($account, '');
            $self->{pbot}->{conn}->whois($nick);
            $self->{whois_pending}->{$nick} = gettimeofday;
          }
        } else {
          if ($mode == $self->{pbot}->{messagehistory}->{MSG_JOIN} && exists $self->{pbot}->{capabilities}->{'extended-join'}) {
            # don't WHOIS joins if extended-join capability is active
          } elsif (not exists $self->{pbot}->{capabilities}->{'account-notify'}) {
            if (not exists $self->{whois_pending}->{$nick}) {
              $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($account, '');
              $self->{pbot}->{conn}->whois($nick);
              $self->{whois_pending}->{$nick} = gettimeofday;
            }
          } else {
            $self->{pbot}->{logger}->log("Not validated; checking bans...\n");
            $self->check_bans($account, "$nick!$user\@$host", $channel);
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
    if($max_messages > 0 and $self->{pbot}->{messagehistory}->{database}->get_max_messages($account, $channel, $mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE} ? $nick : undef) >= $max_messages) {
      my $msg;
      if($mode == $self->{pbot}->{messagehistory}->{MSG_CHAT}) {
        $msg = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($account, $channel, $max_messages - 1)
      }
      elsif($mode == $self->{pbot}->{messagehistory}->{MSG_JOIN}) {
        my $joins = $self->{pbot}->{messagehistory}->{database}->get_recent_messages($account, $channel, $max_messages, $self->{pbot}->{messagehistory}->{MSG_JOIN});
        $msg = $joins->[0];
      }
      elsif($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
        my $nickchanges = $self->{pbot}->{messagehistory}->{database}->get_recent_messages($ancestor, $channel, $max_messages, $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}, $nick);
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

      my $last;
      if ($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
        $last = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($ancestor, $channel, 0, undef, $nick);
      } else {
        $last = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($account, $channel, 0);
      }

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

              if ($self->{pbot}->{channels}->is_active_op("${channel}-floodbans")) {
                $self->{pbot}->{chanops}->ban_user_timed("*!$user\@$banmask\$##stop_join_flood", $channel . '-floodbans', $timeout);
                $self->{pbot}->{logger}->log("$nick!$user\@$banmask banned for $duration due to join flooding (offense #" . $channel_data->{offenses} . ").\n");
                $self->{pbot}->{conn}->privmsg($nick, "You have been banned from $channel due to join flooding.  If your connection issues have been fixed, or this was an accident, you may request an unban at any time by responding to this message with: unbanme $channel, otherwise you will be automatically unbanned in $duration.");
              } else {
                $self->{pbot}->{logger}->log("[anti-flood] I am not an op for ${channel}-floodbans, disregarding join-flood.\n");
              }
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
        } elsif($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE} and $self->{nickflood}->{$ancestor}->{changes} >= $max_messages) {
          next if $channel !~ /^#/;
          ($nick) = $text =~ m/NICKCHANGE (.*)/;

          $self->{nickflood}->{$ancestor}->{offenses}++;
          $self->{nickflood}->{$ancestor}->{changes} = $max_messages - 2; # allow 1 more change (to go back to original nick)
          $self->{nickflood}->{$ancestor}->{timestamp} = gettimeofday;

          if($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
            my $length = $self->{pbot}->{registry}->get_array_value('antiflood', 'nick_flood_punishment', $self->{nickflood}->{$ancestor}->{offenses} - 1);
            $self->{pbot}->{chanops}->ban_user_timed("*!$user\@" . address_to_mask($host), $channel, $length);
            $length = duration($length);
            $self->{pbot}->{logger}->log("$nick nickchange flood offense " . $self->{nickflood}->{$ancestor}->{offenses} . " earned $length ban\n");
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

  my $warning = '';
  my %unbanned;

  my %aliases = $self->{pbot}->{messagehistory}->{database}->get_also_known_as($nick);

  foreach my $alias (keys %aliases) {
    next if $aliases{$alias}->{type} == $self->{pbot}->{messagehistory}->{database}->{alias_type}->{WEAK};
    next if $aliases{$alias}->{nickchange} == 1;

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
          if($self->whitelisted($baninfo->{channel}, $baninfo->{banmask}, 'ban') || $self->whitelisted($baninfo->{channel}, "$nick!$user\@$host", 'user')) {
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

    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'unbanmes');
    if ($channel_data->{unbanmes} > 1) {
      return "/msg $nick You may only use unbanme for the first two offenses. You will be automatically unbanned in a few hours, and your offense counter will decrement once every 24 hours.";
    }

    $channel_data->{unbanmes}++;

    $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);

    if ($channel_data->{unbanmes} == 1) {
      $warning = ' You may use `unbanme` one more time today; please ensure that your client or connection issues are resolved before using your final `unbanme`.';
    } else {
      $warning = ' You may not use `unbanme` again for several hours; ensure that your client or connection issues are resolved, otherwise leave the channel until they are or you will be temporarily banned for several hours if you join-flood.';
    }

    if ($self->{pbot}->{channels}->is_active_op("${channel}-floodbans")) {
      $self->{pbot}->{chanops}->unban_user($mask, $channel . '-floodbans');
      $unbanned{$mask}++;
    }
  }

  if (keys %unbanned) {
    return "/msg $nick You have been unbanned from $channel.$warning";
  } else {
    return "/msg $nick There is no temporary join-flooding ban set for you in channel $channel.";
  }
}

sub address_to_mask {
  my $address = shift;
  my $banmask;

  if($address =~ m/^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$/) {
    my ($a, $b, $c, $d) = ($1, $2, $3, $4);
    given ($a) {
      when ($_ <= 127) { $banmask = "$a.*"; }
      when ($_ <= 191) { $banmask = "$a.$b.*"; }
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
  my ($self, $message_account, $mask, $channel, $dry_run) = @_;

  $channel = lc $channel;

  if (not $self->{pbot}->{chanops}->can_gain_ops($channel)) {
    $self->{pbot}->{logger}->log("anti-flood: [check-ban] I do not have ops for $channel.\n");
    return;
  }

  my $debug_checkban = $self->{pbot}->{registry}->get_value('antiflood', 'debug_checkban');

  my $current_nickserv_account = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($message_account);

  $self->{pbot}->{logger}->log("anti-flood: [check-bans] checking for bans on $mask " . (defined $current_nickserv_account and length $current_nickserv_account ? "[$current_nickserv_account] " : "") .  "in $channel\n");

  my ($do_not_validate, $bans);

  if (defined $current_nickserv_account and length $current_nickserv_account) {
    $self->{pbot}->{logger}->log("anti-flood: [check-bans] current nickserv [$current_nickserv_account] found for $mask\n") if $debug_checkban >= 2;
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
    if ($channel_data->{validated} & $self->{NEEDS_CHECKBAN}) {
      $channel_data->{validated} &= ~$self->{NEEDS_CHECKBAN};
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
    }
  } else {
    if (not exists $self->{pbot}->{capabilities}->{'account-notify'}) {
      # mark this account as needing check-bans when nickserv account is identified
      my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
      if(not $channel_data->{validated} & $self->{NEEDS_CHECKBAN}) {
        $channel_data->{validated} |= $self->{NEEDS_CHECKBAN};
        $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
      }
      $self->{pbot}->{logger}->log("anti-flood: [check-bans] no account for $mask; marking for later validation\n") if $debug_checkban >= 1;
    } else {
      $do_not_validate = 1;
    }
  }

  my ($nick) = $mask =~ m/^([^!]+)/;
  my %aliases = $self->{pbot}->{messagehistory}->{database}->get_also_known_as($nick);

  my $csv = Text::CSV->new({binary => 1});

  foreach my $alias (keys %aliases) {
    next if $alias =~ /^Guest\d+(?:!.*)?$/;

    if ($aliases{$alias}->{type} == $self->{pbot}->{messagehistory}->{database}->{alias_type}->{WEAK}) {
      $self->{pbot}->{logger}->log("anti-flood: [check-bans] skipping WEAK alias $alias in channel $channel\n") if $debug_checkban >= 2;
      next;
    }

    my @nickservs;

    if (exists $aliases{$alias}->{nickserv}) {
      @nickservs = split /,/, $aliases{$alias}->{nickserv};
    } else {
      @nickservs = (undef);
    }

    foreach my $nickserv (@nickservs) {
      my @gecoses;
      if (exists $aliases{$alias}->{gecos}) {
        $csv->parse($aliases{$alias}->{gecos});
        @gecoses = $csv->fields;
      } else {
        @gecoses = (undef);
      }

      foreach my $gecos (@gecoses) {
        my $tgecos = defined $gecos ? $gecos : "[undefined]";
        my $tnickserv = defined $nickserv ? $nickserv : "[undefined]";
        $self->{pbot}->{logger}->log("anti-flood: [check-bans] checking blacklist for $alias in channel $channel using gecos '$tgecos' and nickserv '$tnickserv'\n") if $debug_checkban >= 5;
        if ($self->{pbot}->{blacklist}->check_blacklist($alias, $channel, $nickserv, $gecos)) {
          if($self->whitelisted($channel, $mask, 'user')) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask [$alias] blacklisted in $channel, but allowed through whitelist\n");
            next;
          }

          my $baninfo = {};
          $baninfo->{banmask} = $alias;
          $baninfo->{channel} = $channel;
          $baninfo->{owner} = 'blacklist';
          $baninfo->{when} = 0;
          $baninfo->{type} = 'blacklist';
          push @$bans, $baninfo;
          next;
        }
      }

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

          if($self->whitelisted($baninfo->{channel}, $baninfo->{banmask}, 'ban') || $self->whitelisted($baninfo->{channel}, $mask, 'user')) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask [$alias] evaded $baninfo->{banmask} in $baninfo->{channel}, but allowed through whitelist\n");
            next;
          } 

          # special case for twkm clone bans
          if ($baninfo->{banmask} =~ m/\?\*!\*@\*$/) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask [$alias] evaded $baninfo->{banmask} in $baninfo->{channel}, but disregarded due to clone ban\n");
            next;
          }

          my $banmask_regex = quotemeta $baninfo->{banmask};
          $banmask_regex =~ s/\\\*/.*/g;
          $banmask_regex =~ s/\\\?/./g;

          if($mask =~ /^$banmask_regex$/i) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] Hostmask ($mask) matches $baninfo->{type} banmask ($banmask_regex), disregarding\n");
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
      } elsif ($current_nickserv_account and $baninfo->{banmask} !~ m/^\$a:/i and not exists $self->{pbot}->{bantracker}->{banlist}->{$baninfo->{channel}}->{'+b'}->{"\$a:$current_nickserv_account"}) {
        $banmask = "\$a:$current_nickserv_account";
      } else {
        if ($host =~ m{^gateway/web/irccloud.com/}) {
          $banmask = "*!$user\@gateway/web/irccloud.com/*";
        } elsif ($host =~ m{^nat/([^/]+)/}) {
          $banmask = "*!$user\@nat/$1/*";
        } else {
          $banmask = "*!*\@$host";
          #$banmask = "*!$user@" . address_to_mask($host);
        }
      }

      $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask evaded $baninfo->{banmask} banned in $baninfo->{channel} by $baninfo->{owner}, banning $banmask\n");
      my ($bannick) = $mask =~ m/^([^!]+)/;
      if($self->{pbot}->{registry}->get_value('antiflood', 'enforce')) {
        if ($self->{pbot}->{chanops}->has_ban_timeout($baninfo->{channel}, $banmask)) {
          $self->{pbot}->{logger}->log("anti-flood: [check-bans] $banmask already banned in $channel, disregarding\n");
          return;
        }

        my $ancestor = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($message_account);
        if (exists $self->{nickflood}->{$ancestor} and $self->{nickflood}->{$ancestor}->{offenses} > 0 and $baninfo->{type} ne 'blacklist') {
          if (gettimeofday - $self->{nickflood}->{$ancestor}->{timestamp} < 60 * 15) {
            $self->{pbot}->{logger}->log("anti-flood: [check-bans] $mask evading nick-flood ban, disregarding\n");
            return;
          }
        }

        if (defined $dry_run && $dry_run != 0) {
          $self->{pbot}->{logger}->log("Skipping ban due to dry-run.\n");
          return;
        }

        if ($baninfo->{type} eq 'blacklist') {
          $self->{pbot}->{chanops}->add_op_command($baninfo->{channel}, "kick $baninfo->{channel} $bannick I don't think so");
        } else {
          my $owner = $baninfo->{owner};
          $owner =~ s/!.*$//;
          $self->{pbot}->{chanops}->add_op_command($baninfo->{channel}, "kick $baninfo->{channel} $bannick Evaded $baninfo->{banmask} set by $owner");
        }
        $self->{pbot}->{chanops}->ban_user_timed($banmask, $baninfo->{channel}, 60 * 60 * 24 * 31);
      }
      my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
      if($channel_data->{validated} & $self->{NICKSERV_VALIDATED}) {
        $channel_data->{validated} &= ~$self->{NICKSERV_VALIDATED};
        $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
      }
      return;
    }
  }

  unless ($do_not_validate) {
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

sub on_whoisuser {
  my ($self, $event_type, $event) = @_;
  my $nick    =    $event->{event}->{args}[1];
  my $gecos   = lc $event->{event}->{args}[5];

  my ($id) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);

  if ($self->{pbot}->{registry}->get_value('antiflood', 'debug_checkban') >= 2) {
    $self->{pbot}->{logger}->log("Got gecos for $nick ($id): '$gecos'\n");
  }

  $self->{pbot}->{messagehistory}->{database}->update_gecos($id, $gecos, scalar gettimeofday);
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

sub on_accountnotify {
  my ($self, $event_type, $event) = @_;

  $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($event->{event}->{from}, { last_seen => scalar gettimeofday });

  if ($event->{event}->{args}[0] eq '*') {
    $self->{pbot}->{logger}->log("$event->{event}->{from} logged out of NickServ\n");
  } else {
    $self->{pbot}->{logger}->log("$event->{event}->{from} logged into NickServ account $event->{event}->{args}[0]\n");

    my $nick = $event->{event}->nick;
    my ($id, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);
    $self->{pbot}->{messagehistory}->{database}->link_aliases($id, undef, $event->{event}->{args}[0]) if $id;
    $self->check_nickserv_accounts($nick, $event->{event}->{args}[0]);

    $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($id);

    my $channels = $self->{pbot}->{nicklist}->get_channels($nick);
    foreach my $channel (@$channels) {
      next unless $channel =~ /^#/;
      $self->check_bans($id, $hostmask, $channel);
    }
  }
  return 0;
}

sub adjust_offenses {
  my $self = shift;

  #$self->{pbot}->{logger}->log("Adjusting offenses . . .\n");

  # decrease offenses counter if 24 hours have elapsed since latest offense
  my $channel_datas = $self->{pbot}->{messagehistory}->{database}->get_channel_datas_where_last_offense_older_than(gettimeofday - 60 * 60 * 24);
  foreach my $channel_data (@$channel_datas) {
    my $id = delete $channel_data->{id};
    my $channel = delete $channel_data->{channel};
    my $update = 0;

    if ($channel_data->{offenses} > 0) {
      $channel_data->{offenses}--;
      $update = 1;
    }

    if (defined $channel_data->{unbanmes} and $channel_data->{unbanmes} > 0) {
      $channel_data->{unbanmes}--;
      $update = 1;
    }

    if ($update) {
      $channel_data->{last_offense} = gettimeofday;
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($id, $channel, $channel_data);
    }
  }

  $channel_datas = $self->{pbot}->{messagehistory}->{database}->get_channel_datas_with_enter_abuses();
  foreach my $channel_data (@$channel_datas) {
    my $id = delete $channel_data->{id};
    my $channel = delete $channel_data->{channel};
    my $last_offense = delete $channel_data->{last_offense};
    if(gettimeofday - $last_offense >= 60 * 60 * 3) {
      $channel_data->{enter_abuses}--;
      #$self->{pbot}->{logger}->log("[adjust-offenses] [$id][$channel] decreasing enter abuse offenses to $channel_data->{enter_abuses}\n");
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($id, $channel, $channel_data);
    }
  }

  foreach my $account (keys %{ $self->{nickflood} }) {
    if($self->{nickflood}->{$account}->{offenses} and gettimeofday - $self->{nickflood}->{$account}->{timestamp} >= 60 * 60) {
      $self->{nickflood}->{$account}->{offenses}--;

      if($self->{nickflood}->{$account}->{offenses} <= 0) {
        delete $self->{nickflood}->{$account};
      } else {
        $self->{nickflood}->{$account}->{timestamp} = gettimeofday;
      }
    }
  }
}

1;
