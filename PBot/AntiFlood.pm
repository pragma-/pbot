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

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

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

  $self->{ENTER_ABUSE_MAX_LINES}    = 4;
  $self->{ENTER_ABUSE_MAX_OFFENSES} = 3;
  $self->{ENTER_ABUSE_MAX_SECONDS}  = 20;

  $self->{channels} = {};  # per-channel statistics, e.g. for optimized tracking of last spoken nick for enter-abuse detection, etc
  $self->{nickflood} = {}; # statistics to track nickchange flooding

  my $filename = delete $conf{banwhitelist_file} // $self->{pbot}->{data_dir} . '/ban_whitelist';
  $self->{ban_whitelist} = PBot::DualIndexHashObject->new(name => 'BanWhitelist', filename => $filename);
  $self->{ban_whitelist}->load;

  $self->{pbot}->timer->register(sub { $self->adjust_offenses }, 60 * 60 * 1);

  $self->{pbot}->commands->register(sub { return $self->unbanme(@_)   },  "unbanme",   0);
  $self->{pbot}->commands->register(sub { return $self->whitelist(@_) },  "whitelist", 10);
}

sub ban_whitelisted {
    my ($self, $channel, $mask) = @_;
    $channel = lc $channel;
    $mask = lc $mask;

    #$self->{pbot}->logger->log("whitelist check: $channel, $mask\n");
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

sub check_join_watch {
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

  if($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
    $self->{pbot}->logger->log(sprintf("%-14s | %-65s | %s\n", "NICKCHANGE", $mask, $text));

    my ($newnick) = $text =~ m/NICKCHANGE (.*)/;
    if($newnick =~ m/^Guest\d+$/) {
      # Don't enforce for services-mandated change to guest account
    } else {
      $self->{nickflood}->{$account}->{changes}++;
    }
  } else {
    $self->{pbot}->logger->log(sprintf("%-14s | %-65s | %s\n", $channel eq $mask ? "QUIT" : $channel, $mask, $text));
  }

  # handle QUIT events
  # (these events come from $channel nick!user@host, not a specific channel or nick,
  # so they need to be dispatched to all channels the nick has been seen on)
  if($mode == $self->{pbot}->{messagehistory}->{MSG_DEPARTURE} and $text =~ /^QUIT/) {
    my @channels = $self->{pbot}->{messagehistory}->{database}->get_channels($account);
    foreach my $chan (@channels) {
      next if $chan !~ m/^#/;
      $self->check_join_watch($account, $chan, $text, $mode);
    }

    $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($account);
    # don't do flood processing for QUIT events
    return;
  }

  if($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE}) {
    my @channels = $self->{pbot}->{messagehistory}->{database}->get_channels($account);
    return if not @channels;
    $channel = undef;
    foreach my $chan (@channels) {
      if($chan =~ m/^#/) {
        $channel = $chan;
        last;
      }
    }
    return if not defined $channel;
  } else {
    $self->check_join_watch($account, $channel, $text, $mode);
  }
  
  # do not do flood processing for bot messages
  if($nick eq $self->{pbot}->botnick) {
    $self->{channels}->{$channel}->{last_spoken_nick} = $nick;
    return;
  }

  # do not do flood processing if channel is not in bot's channel list or bot is not set as chanop for the channel
  return if ($channel =~ /^#/) and (not exists $self->{pbot}->channels->channels->hash->{$channel} or $self->{pbot}->channels->channels->hash->{$channel}{chanop} == 0);

  if($channel =~ /^#/ and $mode == $self->{pbot}->{messagehistory}->{MSG_DEPARTURE}) {
    # remove validation on PART so we check for ban-evasion when user returns at a later time
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'validated');
    if($channel_data->{validated} & $self->{NICKSERV_VALIDATED}) {
      $channel_data->{validated} &= ~$self->{NICKSERV_VALIDATED};
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
    }
  }

  if($max_messages > $self->{pbot}->{MAX_NICK_MESSAGES}) {
    $self->{pbot}->logger->log("Warning: max_messages greater than MAX_NICK_MESSAGES; truncating.\n");
    $max_messages = $self->{pbot}->{MAX_NICK_MESSAGES};
  }

  # check for ban evasion if channel begins with # (not private message) and hasn't yet been validated against ban evasion
  if($channel =~ m/^#/ and not $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'validated')->{'validated'} & $self->{NICKSERV_VALIDATED}) {
    if($mode == $self->{pbot}->{messagehistory}->{MSG_DEPARTURE}) {
      # don't check for evasion on PART/KICK
    } else {
      $self->{pbot}->conn->whois($nick);
      $self->check_bans($account, $mask, $channel);
    }
  }

  # do not do flood enforcement for this event if bot is lagging
  if($self->{pbot}->lagchecker->lagging) {
    $self->{pbot}->logger->log("Disregarding enforcement of anti-flood due to lag: " . $self->{pbot}->lagchecker->lagstring . "\n");
    return;
  } 

  # check for enter abuse
  if($mode == $self->{pbot}->{messagehistory}->{MSG_CHAT} and $channel =~ m/^#/) {
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'enter_abuse', 'enter_abuses');

    if(defined $self->{channels}->{$channel}->{last_spoken_nick} and $nick eq $self->{channels}->{$channel}->{last_spoken_nick}) {
      my $messages = $self->{pbot}->{messagehistory}->{database}->get_recent_messages($account, $channel, 2, $self->{pbot}->{messagehistory}->{MSG_CHAT});

      if($messages->[1]->{timestamp} - $messages->[0]->{timestamp} <= $self->{ENTER_ABUSE_MAX_SECONDS}) {
        if(++$channel_data->{enter_abuse} >= $self->{ENTER_ABUSE_MAX_LINES} - 1) {
          $channel_data->{enter_abuse} = $self->{ENTER_ABUSE_MAX_LINES} / 2 - 1;
          if(++$channel_data->{enter_abuses} >= $self->{ENTER_ABUSE_MAX_OFFENSES}) {
            my $offenses = $channel_data->{enter_abuses} - $self->{ENTER_ABUSE_MAX_OFFENSES} + 1;
            my $ban_length = $offenses ** $offenses * $offenses * 30;
            $self->{pbot}->chanops->ban_user_timed("*!$user\@$host", $channel, $ban_length);
            $ban_length = duration($ban_length);
            $self->{pbot}->logger->log("$nick $channel enter abuse offense " . $channel_data->{enter_abuses} . " earned $ban_length ban\n");
            $self->{pbot}->conn->privmsg($nick, "You have been muted due to abusing the enter key.  Please do not split your sentences over multiple messages.  You will be allowed to speak again in $ban_length.");
          } else {
            #$self->{pbot}->logger->log("$nick $channel enter abuses counter incremented to " . $channel_data->{enter_abuses} . "\n");
          }
        } else {
          #$self->{pbot}->logger->log("$nick $channel enter abuse counter incremented to " . $channel_data->{enter_abuse} . "\n");
        }
        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
      } else {
        if($channel_data->{enter_abuse} > 0) {
          #$self->{pbot}->logger->log("$nick $channel more than $self->{ENTER_ABUSE_MAX_SECONDS} seconds since last message, enter abuse counter reset\n");
          $channel_data->{enter_abuse} = 0;
          $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
        }
      }
    } else {
      $self->{channels}->{$channel}->{last_spoken_nick} = $nick;
      if($channel_data->{enter_abuse} > 0) {
        #$self->{pbot}->logger->log("$nick $channel enter abuse counter reset\n"); 
        $channel_data->{enter_abuse} = 0;
        $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
      }
    }
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
      return;
    }
    else {
      $self->{pbot}->logger->log("Unknown flood mode [$mode] ... aborting flood enforcement.\n");
      return;
    }

    my $last = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($account, $channel, 0);

    #$self->{pbot}->logger->log(" msg: [$msg->{timestamp}] $msg->{msg}\n");
    #$self->{pbot}->logger->log("last: [$last->{timestamp}] $last->{msg}\n");
    #$self->{pbot}->logger->log("Comparing message timestamps $last->{timestamp} - $msg->{timestamp} = " . ($last->{timestamp} - $msg->{timestamp}) . " against max_time $max_time\n");

    if($last->{timestamp} - $msg->{timestamp} <= $max_time && not $self->{pbot}->admins->loggedin($channel, "$nick!$user\@$host")) {
      if($mode == $self->{pbot}->{messagehistory}->{MSG_JOIN}) {
        my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'offenses', 'last_offense', 'join_watch');
        #$self->{pbot}->{logger}->log("$account offenses $channel_data->{offenses}, join watch $channel_data->{join_watch}, max messages $max_messages\n");
        if($channel_data->{join_watch} >= $max_messages) {
          $channel_data->{offenses}++;
          $channel_data->{last_offense} = gettimeofday;

          my $timeout = (2 ** (($channel_data->{offenses} + 2) < 10 ? $channel_data->{offenses} + 2 : 10));
          my $banmask = address_to_mask($host);
          
          $self->{pbot}->chanops->ban_user_timed("*!$user\@$banmask\$##stop_join_flood", $channel, $timeout * 60 * 60);
          $self->{pbot}->logger->log("$nick!$user\@$banmask banned for $timeout hours due to join flooding (offense #" . $channel_data->{offenses} . ").\n");
          $self->{pbot}->conn->privmsg($nick, "You have been banned from $channel due to join flooding.  If your connection issues have been fixed, or this was an accident, you may request an unban at any time by responding to this message with: unbanme $channel, otherwise you will be automatically unbanned in $timeout hours.");
          $channel_data->{join_watch} = $max_messages - 2; # give them a chance to rejoin 
          $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
        } 
      } elsif($mode == $self->{pbot}->{messagehistory}->{MSG_CHAT}) {
        if($channel =~ /^#/) { #channel flood (opposed to private message or otherwise)
          # don't increment offenses again if already banned
          return if $self->{pbot}->chanops->{unban_timeout}->find_index($channel, "*!$user\@$host");

          my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'offenses', 'last_offense');
          $channel_data->{offenses}++;
          $channel_data->{last_offense} = gettimeofday;
          $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);

          my $length = $channel_data->{offenses} ** $channel_data->{offenses} * $channel_data->{offenses} * 30;

          $self->{pbot}->chanops->ban_user_timed("*!$user\@$host", $channel, $length);
          $length = duration($length);
          $self->{pbot}->logger->log("$nick $channel flood offense " . $channel_data->{offenses} . " earned $length ban\n");
          $self->{pbot}->conn->privmsg($nick, "You have been muted due to flooding.  Please use a web paste service such as http://codepad.org for lengthy pastes.  You will be allowed to speak again in $length.");
          $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
        } 
        else { # private message flood
          return if exists ${ $self->{pbot}->ignorelist->{ignore_list} }{"$nick!$user\@$host"}{$channel};

          my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($account, $channel, 'offenses', 'last_offense');
          $channel_data->{offenses}++;
          $channel_data->{last_offense} = gettimeofday;
          $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);

          my $length = $channel_data->{offenses} ** $channel_data->{offenses} * $channel_data->{offenses} * 30;

          $self->{pbot}->{ignorelistcmds}->ignore_user("", "floodcontrol", "", "", "$nick!$user\@$host $channel $length");
          $length = duration($length);
          $self->{pbot}->logger->log("$nick msg flood offense " . $channel_data->{offenses} . " earned $length ignore\n");
          $self->{pbot}->conn->privmsg($nick, "You have used too many commands in too short a time period, you have been ignored for $length.");
        }
      } elsif($mode == $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE} and $self->{nickflood}->{$account}->{changes} >= $max_messages) {
        ($nick) = $text =~ m/NICKCHANGE (.*)/;

        $self->{nickflood}->{$account}->{offenses}++;
        $self->{nickflood}->{$account}->{changes} = $max_messages - 2; # allow 1 more change (to go back to original nick)
        $self->{nickflood}->{$account}->{timestamp} = gettimeofday;

        my $length = $self->{nickflood}->{$account}->{offenses} ** $self->{nickflood}->{$account}->{offenses} * $self->{nickflood}->{$account}->{offenses} * 60 * 4;

        my @channels = $self->{pbot}->{messagehistory}->{database}->get_channels($account);
        foreach my $chan (@channels) {
          $self->{pbot}->chanops->ban_user_timed("*!$user\@$host", $chan, $length);
        }

        $length = duration($length);
        $self->{pbot}->logger->log("$nick nickchange flood offense " . $self->{nickflood}->{$account}->{offenses} . " earned $length ban\n");
        $self->{pbot}->conn->privmsg($nick, "You have been temporarily banned due to nick-change flooding.  You will be unbanned in $length.");
      }
    }
  }
}

sub unbanme {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $channel = lc $arguments;

  if(not defined $arguments or not defined $channel) {
    return "/msg $nick Usage: unbanme <channel>";
  }

  my $banmask = address_to_mask($host);

  my $mask = "*!$user\@$banmask\$##stop_join_flood";

  if(not $self->{pbot}->{chanops}->{unban_timeout}->find_index($channel, $mask)) {
    return "/msg $nick There is no temporary ban set for $mask in channel $channel.";
  }

  my $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  my @nickserv_accounts = $self->{pbot}->{messagehistory}->{database}->get_nickserv_accounts($message_account);

  foreach my $nickserv_account (@nickserv_accounts) {
    my $baninfos = $self->{pbot}->bantracker->get_baninfo("$nick!$user\@$host", $channel, $nickserv_account);

    if(defined $baninfos) {
      foreach my $baninfo (@$baninfos) {
        if($self->ban_whitelisted($baninfo->{channel}, $baninfo->{banmask})) {
          $self->{pbot}->logger->log("anti-flood: [unbanme] $nick!$user\@$host banned as $baninfo->{banmask} in $baninfo->{channel}, but allowed through whitelist\n");
        } else {
          if($channel eq lc $baninfo->{channel}) {
            my $mode = $baninfo->{type} eq "+b" ? "banned" : "quieted";
            $self->{pbot}->logger->log("anti-flood: [unbanme] $nick!$user\@$host $mode as $baninfo->{banmask} in $baninfo->{channel} by $baninfo->{owner}, unbanme rejected\n");
            return "/msg $nick You have been $mode as $baninfo->{banmask} by $baninfo->{owner}, unbanme will not work until it is removed.";
          }
        }
      }
    }
  }

  my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'offenses');
  if($channel_data->{offenses} > 2) {
    return "/msg $nick You may only use unbanme for the first two offenses. You will be automatically unbanned in a few hours, and your offense counter will decrement once every 24 hours.";
  }

  $self->{pbot}->chanops->unban_user($mask, $channel);

  return "/msg $nick You have been unbanned from $channel.";
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
  } elsif($address =~ m/[^.]+\.([^.]+\.[^.]+)$/) {
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

  #$self->{pbot}->logger->log("Devalidating accounts for $mask in $channel\n");

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
      #$self->{pbot}->logger->log("Devalidating account $account\n");
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($account, $channel, $channel_data);
    }
  }
}

sub check_bans {
  my ($self, $message_account, $mask, $channel) = @_;

  #$self->{pbot}->logger->log("anti-flood: [check-bans] checking for bans on $mask in $channel\n"); 

  my @nickserv_accounts = $self->{pbot}->{messagehistory}->{database}->get_nickserv_accounts($message_account);
  my $current_nickserv_account = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($message_account);

  if($current_nickserv_account) {
    #$self->{pbot}->logger->log("anti-flood: [check-bans] current nickserv [$current_nickserv_account] found for $mask\n");
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
    if($channel_data->{validated} & $self->{NEEDS_CHECKBAN}) {
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
    #$self->{pbot}->logger->log("anti-flood: [check-bans] no account for $mask; marking for later validation\n");
  }

  my ($nick, $host) = $mask =~ m/^([^!]+)![^@]+\@(.*)$/;

  my $hostmasks = $self->{pbot}->{messagehistory}->{database}->get_hostmasks_for_channel($channel);

  my ($do_not_validate, $bans);
  foreach my $hostmask (@$hostmasks) {
    my @hostmask_nickserv_accounts = $self->{pbot}->{messagehistory}->{database}->get_nickserv_accounts($hostmask->{id});
    my $check_ban = 0;

    # check if nickserv accounts match
    foreach my $nickserv_account (@nickserv_accounts) {
      foreach my $key (@hostmask_nickserv_accounts) {
        if($key eq $nickserv_account) {
          #$self->{pbot}->logger->log("anti-flood: [check-bans] nickserv account for $hostmask->{hostmask} matches $nickserv_account\n");
          $check_ban = 1;
          goto CHECKBAN;
        }
      }
    }

    # check if hosts match
    my ($account_host) = $hostmask->{hostmask} =~ m/\@(.*)$/;
    if($host eq $account_host) {
      #$self->{pbot}->logger->log("anti-flood: [check-bans] host for $hostmask->{hostmask} matches $mask\n");
      $check_ban = 1;
      goto CHECKBAN;
    }

    # check if nicks match
    my ($account_nick) = $hostmask->{hostmask} =~ m/^([^!]+)/;
    if($nick eq $account_nick) {
      #$self->{pbot}->logger->log("anti-flood: [check-bans] nick for $hostmask->{hostmask} matches $mask\n");
      $check_ban = 1;
      goto CHECKBAN;
    }

    CHECKBAN:
    if($check_ban) {
      if(not @hostmask_nickserv_accounts) {
        push @hostmask_nickserv_accounts, -1;
      }

      foreach my $target_nickserv_account (@hostmask_nickserv_accounts) {
        #$self->{pbot}->logger->log("anti-flood: [check-bans] checking for bans in $channel on $hostmask->{hostmask} using $target_nickserv_account\n");
        my $baninfos = $self->{pbot}->bantracker->get_baninfo($hostmask->{hostmask}, $channel, $target_nickserv_account);

        if(defined $baninfos) {
          foreach my $baninfo (@$baninfos) {
            if(time - $baninfo->{when} < 5) {
              $self->{pbot}->logger->log("anti-flood: [check-bans] $mask evaded $baninfo->{banmask} in $baninfo->{channel}, but within 5 seconds of establishing ban; giving another chance\n");
              my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
              if($channel_data->{validated} & $self->{NICKSERV_VALIDATED}) {
                $channel_data->{validated} &= ~$self->{NICKSERV_VALIDATED};
                $self->{pbot}->{messagehistory}->{database}->update_channel_data($message_account, $channel, $channel_data);
              }
              $do_not_validate = 1;
              next;
            }

            if($self->ban_whitelisted($baninfo->{channel}, $baninfo->{banmask})) {
              $self->{pbot}->logger->log("anti-flood: [check-bans] $mask evaded $baninfo->{banmask} in $baninfo->{channel}, but allowed through whitelist\n");
              next;
            } 

            if($baninfo->{type} eq '+b' and $baninfo->{banmask} =~ m/!\*@\*$/) {
              $self->{pbot}->logger->log("anti-flood: [check-bans] Disregarding generic nick ban\n");
              next;
            } 

            my $banmask_regex = quotemeta $baninfo->{banmask};
            $banmask_regex =~ s/\\\*/.*/g;
            $banmask_regex =~ s/\\\?/./g;

            if($baninfo->{type} eq '+q' and $mask =~ /^$banmask_regex$/i) {
              $self->{pbot}->logger->log("anti-flood: [check-bans] Hostmask ($mask) matches quiet banmask ($banmask_regex), disregarding\n");
              next;
            }

            my $skip_quiet_nickserv_mask = 0;
            foreach my $nickserv_account (@nickserv_accounts) {
              if($baninfo->{type} eq '+q' and $baninfo->{banmask} =~ /^\$a:(.*)/ and lc $1 eq $nickserv_account and $nickserv_account eq $current_nickserv_account) {
                $self->{pbot}->logger->log("anti-flood: [check-bans] Hostmask ($mask) matches quiet on account ($nickserv_account), disregarding\n");
                $skip_quiet_nickserv_mask = 1;
              } elsif($baninfo->{type} eq '+b' and $baninfo->{banmask} =~ /^\$a:(.*)/ and lc $1 eq $nickserv_account) {
                $skip_quiet_nickserv_mask = 0;
                last;
              }
            }
            next if $skip_quiet_nickserv_mask;

            if(not defined $bans) {
              $bans = [];
            }

            $self->{pbot}->logger->log("anti-flood: [check-bans] Hostmask ($mask) matches $baninfo->{type} $baninfo->{banmask}, adding ban\n");
            push @$bans, $baninfo;
            next;
          }
        }
      }
    }
  }

  if(defined $bans) {
    $mask =~ m/[^!]+!([^@]+)@(.*)/;
    my $banmask = "*!$1@" . address_to_mask($2);

    foreach my $baninfo (@$bans) {
      $self->{pbot}->logger->log("anti-flood: [check-bans] $mask evaded $baninfo->{banmask} banned in $baninfo->{channel} by $baninfo->{owner}, banning $banmask\n");
      my ($bannick) = $mask =~ m/^([^!]+)/;
      $self->{pbot}->chanops->add_op_command($baninfo->{channel}, "kick $baninfo->{channel} $bannick Ban evasion");
      $self->{pbot}->chanops->ban_user_timed($banmask, $baninfo->{channel}, 60 * 60 * 12);
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
  my $force_validation = 0;
  my $message_account;

  #$self->{pbot}->logger->log("Checking nickserv accounts for nick $nick with account $account and hostmask " . (defined $hostmask ? $hostmask : 'undef') . "\n");

  $account = lc $account;

  if(not defined $hostmask) {
    ($message_account, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);

    if(not defined $message_account) {
      $self->{pbot}->logger->log("No message account found for nick $nick.\n");
      ($message_account) = $self->{pbot}->{messagehistory}->{database}->find_message_accounts_by_nickserv($account);

      if(not $message_account) {
        $self->{pbot}->logger->log("No message account found for nickserv $account.\n");
        return;
      }
    }
  } else {
    ($message_account) = $self->{pbot}->{messagehistory}->{database}->find_message_accounts_by_mask($hostmask);
    if(not $message_account) {
      $self->{pbot}->logger->log("No message account found for hostmask $hostmask.\n");
      return;
    }
    $force_validation = 1;
  }

  #$self->{pbot}->logger->log("anti-flood: $message_account: setting nickserv account to [$account]\n");
  $self->{pbot}->{messagehistory}->{database}->update_nickserv_account($message_account, $account, scalar gettimeofday);
  $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($message_account, $account);

  # check to see if any channels need check-ban validation
  $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($message_account);
  my @channels = $self->{pbot}->{messagehistory}->{database}->get_channels($message_account);
  foreach my $channel (@channels) {
    my $channel_data = $self->{pbot}->{messagehistory}->{database}->get_channel_data($message_account, $channel, 'validated');
    if($force_validation or $channel_data->{validated} & $self->{NEEDS_CHECKBAN}) {
      $self->{pbot}->logger->log("anti-flood: [check-account] $nick [nickserv: $account] needs check-ban validation for $hostmask in $channel.\n");
      $self->check_bans($message_account, $hostmask, $channel);
    }
  }
}

sub on_whoisaccount {
  my ($self, $conn, $event) = @_;
  my $nick    = $event->{args}[1];
  my $account = lc $event->{args}[2];

  $self->{pbot}->logger->log("$nick is using NickServ account [$account]\n");
  $self->check_nickserv_accounts($nick, $account);
}

sub adjust_offenses {
  my $self = shift;

  #$self->{pbot}->logger->log("Adjusting offenses . . .\n");

  # decrease offenses counter if 24 hours have elapsed since latest offense
  my $channel_datas = $self->{pbot}->{messagehistory}->{database}->get_channel_datas_where_last_offense_older_than(gettimeofday - 60 * 60 * 24);
  foreach my $channel_data (@$channel_datas) {
    if($channel_data->{offenses} > 0) {
      my $id = delete $channel_data->{id};
      my $channel = delete $channel_data->{channel};
      $channel_data->{offenses}--;
      $channel_data->{last_offense} = gettimeofday;
      #$self->{pbot}->logger->log("[adjust-offenses] [$id][$channel] 24 hours since last offense/decrease -- decreasing offenses to $channel_data->{offenses}\n");
      $self->{pbot}->{messagehistory}->{database}->update_channel_data($id, $channel, $channel_data);
    }
  }

  $channel_datas = $self->{pbot}->{messagehistory}->{database}->get_channel_datas_with_enter_abuses();
  foreach my $channel_data (@$channel_datas) {
    my $id = delete $channel_data->{id};
    my $channel = delete $channel_data->{channel};
    $channel_data->{enter_abuses}--;
    #$self->{pbot}->logger->log("[adjust-offenses] [$id][$channel] decreasing enter abuse offenses to $channel_data->{enter_abuses}\n");
    $self->{pbot}->{messagehistory}->{database}->update_channel_data($id, $channel, $channel_data);
  }

  foreach my $account (keys %{ $self->{nickflood} }) {
    if($self->{nickflood}->{$account}->{offenses} > 0 and gettimeofday - $self->{nickflood}->{$account}->{timestamp} >= 60 * 60 * 24) {
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
