# File: AntiFlood.pm
# Author: pragma_
#
# Purpose: Keeps track of who has said what and when.  Used in
# conjunction with ChanOps and Quotegrabs for kick/ban on flood
# and grabbing quotes, respectively.

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
    Carp::croak("Options to AntiFlood should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to AntiFlood");
  }

  $self->{pbot} = $pbot;
  $self->{FLOOD_IGNORE} = -1;
  $self->{FLOOD_CHAT} = 0;
  $self->{FLOOD_JOIN} = 1;

  $self->{message_history} = {};

  my $filename = delete $conf{filename} // $self->{pbot}->{data_dir} . '/ban_whitelist';
  $self->{ban_whitelist} = PBot::DualIndexHashObject->new(name => 'BanWhitelist', filename => $filename);
  $self->{ban_whitelist}->load;

  $pbot->timer->register(sub { $self->prune_message_history }, 60 * 60 * 1);

  $pbot->commands->register(sub { return $self->unbanme(@_)   },  "unbanme",   0);
  $pbot->commands->register(sub { return $self->whitelist(@_) },  "whitelist", 10);
}

sub ban_whitelisted {
    my ($self, $channel, $mask) = @_;
    $channel = lc $channel;
    $mask = lc $mask;

    $self->{pbot}->logger->log("whitelist check: $channel, $mask\n");
    return defined $self->{ban_whitelist}->hash->{$channel}->{$mask}->{ban_whitelisted} ? 1 : 0;
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

sub get_flood_account {
  my ($self, $nick, $user, $host) = @_;

  return "$nick!$user\@$host" if exists $self->message_history->{"$nick!$user\@$host"};

  foreach my $mask (keys %{ $self->message_history }) {
    # check if foo!bar@baz matches foo!*@*; e.g., same nick, but possibly different user@host 
    # (usually logging into nickserv or a dynamic ip address, but could possibly be attempted nick hijacking)

    if($mask =~ m/^\Q$nick\E!.*/i) {
      $self->{pbot}->logger->log("anti-flood: [get-account] $nick!$user\@$host seen previously as $mask\n");
    }

    # check if foo!bar@baz matches *!bar@baz; e.g., same user@host, but different nick 
    # (usually alternate-nicks due to rejoining)
    if($mask =~ m/!\Q$user\E@\Q$host\E$/i) {
      $self->{pbot}->logger->log("anti-flood: [get-account] $nick!$user\@$host linked to $mask\n");
      $self->{message_history}->{"$nick!$user\@$host"} = $self->{message_history}->{$mask};

      if(defined $self->{message_history}->{$mask}->{nickserv_account}) {
        $self->check_nickserv_accounts($nick, $self->{message_history}->{$mask}->{nickserv_account}); 
      }

      return "$nick!$user\@$host";
    }
  }

  return undef;
}

sub add_message {
  my ($self, $account, $channel, $text, $mode) = @_;
  my $now = gettimeofday;

  return undef if $channel =~ /[@!]/; # ignore QUIT messages from nick!user@host channels

  #$self->{pbot}->logger->log("appending new message\n");
  push(@{ $self->message_history->{$account}->{channels}->{$channel}{messages} }, { timestamp => $now, msg => $text, mode => $mode });
  $self->message_history->{$account}->{channels}->{$channel}{last_spoken} = $now;

  my $length = $#{ $self->message_history->{$account}->{channels}->{$channel}{messages} } + 1;

  if($mode == $self->{FLOOD_JOIN}) {
    if($text =~ /^JOIN/) {
      $self->message_history->{$account}->{channels}->{$channel}{join_watch}++;
    } else {
      # PART or QUIT
      # check QUIT message for netsplits, and decrement joinwatch if found
      if($text =~ /^QUIT .*\.net .*\.split/) {
        $self->message_history->{$account}->{channels}->{$channel}{join_watch}--;
        $self->message_history->{$account}->{channels}->{$channel}{join_watch} = 0 if $self->message_history->{$account}->{channels}->{$channel}{join_watch} < 0;
        $self->{pbot}->logger->log("$account $channel joinwatch adjusted: " . $self->message_history->{$account}->{channels}->{$channel}{join_watch} . "\n");
        $self->message_history->{$account}->{channels}->{$channel}{messages}->[$length - 1]{mode} = $self->{FLOOD_IGNORE}; 
      }
      # check QUIT message for Ping timeout or Excess Flood
      elsif($text =~ /^QUIT Ping timeout/ or $text =~ /^QUIT Excess Flood/) {
        # ignore these (used to treat aggressively)
        $self->message_history->{$account}->{channels}->{$channel}{messages}->[$length - 1]{mode} = $self->{FLOOD_IGNORE};
      } else {
        # some other type of QUIT or PART
        $self->message_history->{$account}->{channels}->{$channel}{messages}->[$length - 1]{mode} = $self->{FLOOD_IGNORE};
      }
    }
  } elsif($mode == $self->{FLOOD_CHAT}) {
    # reset joinwatch if they send a message
    $self->message_history->{$account}->{channels}->{$channel}{join_watch} = 0;
  }

  # keep only MAX_NICK_MESSAGES message history per channel
  if($length >= $self->{pbot}->{MAX_NICK_MESSAGES}) {
    my %msg = %{ shift(@{ $self->message_history->{$account}->{channels}->{$channel}{messages} }) };
    #$self->{pbot}->logger->log("shifting message off top: $msg{msg}, $msg{timestamp}\n");
    $length--;
  }

  return $length;
}

sub check_flood {
  my ($self, $channel, $nick, $user, $host, $text, $max_messages, $max_time, $mode) = @_;

  $channel = lc $channel;
  my $mask = lc "$nick!$user\@$host";

  $self->{pbot}->logger->log(sprintf("%-14s | %-65s | %s\n", $channel eq $mask ? "QUIT" : $channel, $mask, $text));

  $nick = lc $nick;
  $user = lc $user;
  $host = lc $host;

  return if $nick eq lc $self->{pbot}->botnick;

  my $account = $self->get_flood_account($nick, $user, $host);

  if(not defined $account) {
    # new addition
    #$self->{pbot}->logger->log("brand new account addition\n");
    $self->message_history->{$mask}->{channels} = {};
    
    $self->{pbot}->conn->whois($nick);

    $account = $mask;
  }

  # handle QUIT events
  # (these events come from $channel nick!user@host, not a specific channel or nick,
  # so they need to be dispatched to all channels the bot exists on)
  if($mode == $self->{FLOOD_JOIN} and $text =~ /^QUIT/) {
    foreach my $chan (lc keys %{ $self->{pbot}->channels->channels->hash }) {

      next if $chan eq $channel;  # skip nick!user@host "channel"

      if(not exists $self->message_history->{$account}->{channels}->{$chan}) {
        #$self->{pbot}->logger->log("adding new channel for existing account\n");
        $self->message_history->{$account}->{channels}->{$chan}{offenses} = 0;
        $self->message_history->{$account}->{channels}->{$chan}{last_offense_timestamp} = 0;
        $self->message_history->{$account}->{channels}->{$chan}{join_watch} = 0;
        $self->message_history->{$account}->{channels}->{$chan}{messages} = [];
      }

      $self->add_message($account, $chan, $text, $mode);
    }

    # don't do flood processing for QUIT events
    return;
  }

  if(not exists $self->message_history->{$account}->{channels}->{$channel}) {
    #$self->{pbot}->logger->log("adding new channel for existing nick\n");
    $self->message_history->{$account}->{channels}->{$channel}{offenses} = 0;
    $self->message_history->{$account}->{channels}->{$channel}{last_offense_timestamp} = 0;
    $self->message_history->{$account}->{channels}->{$channel}{join_watch} = 0;
    $self->message_history->{$account}->{channels}->{$channel}{messages} = [];
  }

  my $length = $self->add_message($account, $channel, $text, $mode);
  return if not defined $length;
  
  # do not do flood processing if channel is not in bot's channel list or bot is not set as chanop for the channel
  return if ($channel =~ /^#/) and (not exists $self->{pbot}->channels->channels->hash->{$channel} or $self->{pbot}->channels->channels->hash->{$channel}{chanop} == 0);

  # do not do flood enforcement for this event if bot is lagging
  if($self->{pbot}->lagchecker->lagging) {
    $self->{pbot}->logger->log("Disregarding enforcement of anti-flood due to lag: " . $self->{pbot}->lagchecker->lagstring . "\n");
    return;
  } 

  if($max_messages > $self->{pbot}->{MAX_NICK_MESSAGES}) {
    $self->{pbot}->logger->log("Warning: max_messages greater than MAX_NICK_MESSAGES; truncating.\n");
    $max_messages = $self->{pbot}->{MAX_NICK_MESSAGES};
  }

  if($max_messages > 0 and $length >= $max_messages) {
      # $self->{pbot}->logger->log("More than $max_messages messages, comparing time differences ($max_time)\n") if $mode == $self->{FLOOD_JOIN};

    my %msg;
    if($mode == $self->{FLOOD_CHAT}) {
      %msg = %{ @{ $self->message_history->{$account}->{channels}->{$channel}{messages} }[$length - $max_messages] };
    } 
    elsif($mode == $self->{FLOOD_JOIN}) {
      my $count = 0;
      my $i = $length - 1;
      # $self->{pbot}->logger->log("Checking flood history, i = $i\n") if $self->message_history->{$account}->{channels}->{$channel}{join_watch} >= $max_messages;
      for(; $i >= 0; $i--) {
          # $self->{pbot}->logger->log($i . " " . $self->message_history->{$account}->{channels}->{$channel}{messages}->[$i]{mode} ." " . $self->message_history->{$account}->{channels}->{$channel}{messages}->[$i]{msg} .  " " . $self->message_history->{$account}->{channels}->{$channel}{messages}->[$i]{timestamp} . " [" . ago_exact(time - $self->message_history->{$account}->{channels}->{$channel}{messages}->[$i]{timestamp}) . "]\n") if $self->message_history->{$account}->{channels}->{$channel}{join_watch} >= $max_messages;
        next if $self->message_history->{$account}->{channels}->{$channel}{messages}->[$i]{mode} != $self->{FLOOD_JOIN};
        last if ++$count >= 4;
      }
      $i = 0 if $i < 0;
      %msg = %{ @{ $self->message_history->{$account}->{channels}->{$channel}{messages} }[$i] };
    }
    else {
      $self->{pbot}->logger->log("Unknown flood mode [$mode] ... aborting flood enforcement.\n");
      return;
    }

    my %last = %{ @{ $self->message_history->{$account}->{channels}->{$channel}{messages} }[$length - 1] };

    $self->{pbot}->logger->log("Comparing $nick!$user\@$host " . int($last{timestamp}) . " against " . int($msg{timestamp}) . ": " . (int($last{timestamp} - $msg{timestamp})) . " seconds [" . duration_exact($last{timestamp} - $msg{timestamp}) . "]\n") if $mode == $self->{FLOOD_JOIN};

    if($last{timestamp} - $msg{timestamp} <= $max_time && not $self->{pbot}->admins->loggedin($channel, "$nick!$user\@$host")) {
      if($mode == $self->{FLOOD_JOIN}) {
        if($self->message_history->{$account}->{channels}->{$channel}{join_watch} >= $max_messages) {
          $self->message_history->{$account}->{channels}->{$channel}{offenses}++;
          $self->message_history->{$account}->{channels}->{$channel}{last_offense_timestamp} = gettimeofday;
          
          my $timeout = (2 ** (($self->message_history->{$account}->{channels}->{$channel}{offenses} + 2) < 10 ? $self->message_history->{$account}->{channels}->{$channel}{offenses} + 2 : 10));

          my $banmask = address_to_mask($host);

          $self->{pbot}->chanops->ban_user_timed("*!$user\@$banmask\$##stop_join_flood", $channel, $timeout * 60 * 60);
          
          $self->{pbot}->logger->log("$nick!$user\@$banmask banned for $timeout hours due to join flooding (offense #" . $self->message_history->{$account}->{channels}->{$channel}{offenses} . ").\n");
          
          $timeout = "several" if($timeout > 8);

          $self->{pbot}->conn->privmsg($nick, "You have been banned from $channel for $timeout hours due to join flooding.  If your connection issues have been fixed, or this was an accident, you may request an unban at any time by responding to this message with: unbanme $channel");

          $self->message_history->{$account}->{channels}->{$channel}{join_watch} = $max_messages - 2; # give them a chance to rejoin 
        } 
      } elsif($mode == $self->{FLOOD_CHAT}) {
        # don't increment offenses again if already banned
        return if exists $self->{pbot}->chanops->{unban_timeout}->hash->{"*!$user\@$host"};

        $self->message_history->{$account}->{channels}->{$channel}{offenses}++;
        $self->message_history->{$account}->{channels}->{$channel}{last_offense_timestamp} = gettimeofday;
        
        my $length = $self->message_history->{$account}->{channels}->{$channel}{offenses} ** $self->message_history->{$account}->{channels}->{$channel}{offenses} * $self->message_history->{$account}->{channels}->{$channel}{offenses} * 30;

        if($channel =~ /^#/) { #channel flood (opposed to private message or otherwise)
          $self->{pbot}->chanops->ban_user_timed("*!$user\@$host", $channel, $length);

          $self->{pbot}->logger->log("$nick $channel flood offense " . $self->message_history->{$account}->{channels}->{$channel}{offenses} . " earned $length second ban\n");

          if($length  < 1000) {
            $length = "$length seconds";
          } else {
            $length = "a little while";
          }

          $self->{pbot}->conn->privmsg($nick, "You have been muted due to flooding.  Please use a web paste service such as http://codepad.org for lengthy pastes.  You will be allowed to speak again in $length.");
        } 
        else { # private message flood
          return if exists ${ $self->{pbot}->ignorelist->{ignore_list} }{"$nick!$user\@$host"}{$channel};

          $self->{pbot}->logger->log("$nick msg flood offense " . $self->message_history->{$account}->{channels}->{$channel}{offenses} . " earned $length second ignore\n");

          $self->{pbot}->{ignorelistcmds}->ignore_user("", "floodcontrol", "", "", "$nick!$user\@$host $channel $length");

          if($length  < 1000) {
            $length = "$length seconds";
          } else {
            $length = "a little while";
          }

          $self->{pbot}->conn->privmsg($nick, "You have used too many commands in too short a time period, you have been ignored for $length.");
        }
      }
    }
  }
}

sub message_history {
  my $self = shift;
  return $self->{message_history};
}

sub prune_message_history {
  my $self = shift;

  $self->{pbot}->logger->log("Pruning message history . . .\n");

  foreach my $mask (keys %{ $self->{message_history} }) {
    foreach my $channel (keys %{ $self->{message_history}->{$mask}->{channels} }) {

      my $length = $#{ $self->{message_history}->{$mask}->{channels}->{$channel}{messages} } + 1;
      next unless $length > 0;
      my %last = %{ @{ $self->{message_history}->{$mask}->{channels}->{$channel}{messages} }[$length - 1] };

      # delete channel key if no activity within 3 days
      if(gettimeofday - $last{timestamp} >= 60 * 60 * 24 * 90) {
        $self->{pbot}->logger->log("$mask in $channel hasn't spoken in ninety days; removing channel history.\n");
        delete $self->{message_history}->{$mask}->{channels}->{$channel};
        next;
      } 

      # decrease offenses counter if 24 hours of elapsed without any new offense
      elsif ($self->{message_history}->{$mask}->{channels}->{$channel}{offenses} > 0 and 
             $self->{message_history}->{$mask}->{channels}->{$channel}{last_offense_timestamp} > 0 and 
             (gettimeofday - $self->{message_history}->{$mask}->{channels}->{$channel}{last_offense_timestamp} >= 60 * 60 * 24)) {
        $self->{message_history}->{$mask}->{channels}->{$channel}{offenses}--;
        $self->{message_history}->{$mask}->{channels}->{$channel}{last_offense_timestamp} = gettimeofday;
        $self->{pbot}->logger->log("anti-flood: [$channel][$mask] 24 hours since last offense/decrease -- decreasing offenses to $self->{message_history}->{$mask}->{channels}->{$channel}{offenses}\n");
      }
    }

    # delete account for this $mask if all its channels have been deleted
    my $count = 0;
    foreach my $channel (keys %{ $self->{message_history}->{$mask} }) {
      $count++;
    }

    if($count == 0) {
      $self->{pbot}->logger->log("$mask has no more channels remaining; deleting history account.\n");
      delete $self->{message_history}->{$mask};
    }
  }
}

sub unbanme {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $channel = lc $arguments;
  $host = lc $host;
  $user = lc $user;

  if(not defined $arguments or not defined $channel) {
    return "/msg $nick Usage: unbanme <channel>";
  }

  my $banmask = address_to_mask($host);

  my $mask = lc "*!$user\@$banmask\$##stop_join_flood";

  if(not exists $self->{pbot}->{chanops}->{unban_timeout}->hash->{$mask}) {
    return "/msg $nick There is no temporary ban set for $mask in channel $channel.";
  }

  if(not $self->{pbot}->chanops->{unban_timeout}->hash->{$mask}{channel} eq $channel) {
    return "/msg $nick There is no temporary ban set for $mask in channel $channel.";
  }

  my $baninfo = $self->{pbot}->bantracker->get_baninfo(lc "$nick!$user\@$host");

  if(defined $baninfo) {
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

  my $account = $self->get_flood_account($nick, $user, $host);
  if(defined $account and $self->message_history->{$account}->{channels}->{$channel}{offenses} > 2) {
    return "/msg $nick You may only use unbanme for the first two offenses. You will be automatically unbanned in a few hours, and your offense counter will decrement once every 24 hours.";
  }

  $self->{pbot}->chanops->unban_user($mask, $channel);
  delete $self->{pbot}->chanops->{unban_timeout}->hash->{$mask};
  $self->{pbot}->chanops->{unban_timeout}->save_hash();

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

sub check_bans {
  my ($self, $bans, $mask) = @_;

  my $baninfo = $self->{pbot}->bantracker->get_baninfo($mask);

  if(defined $baninfo) {
    if($self->ban_whitelisted($baninfo->{channel}, $baninfo->{banmask})) {
      $self->{pbot}->logger->log("anti-flood: [check-bans] $mask evaded $baninfo->{banmask} in $baninfo->{channel}, but allowed through whitelist\n");
      return undef;
    } 
    
    if($baninfo->{type} eq '+b' and $baninfo->{banmask} =~ m/!\*@\*$/) {
      $self->{pbot}->logger->log("anti-flood: [check-bans] Disregarding generic nick ban\n");
      return undef;
    } 
    
    my $banmask_regex = quotemeta $baninfo->{banmask};
    $banmask_regex =~ s/\\\*/.*/g;
    $banmask_regex =~ s/\\\?/./g;

    if($baninfo->{type} eq '+q' and $mask =~ /^$banmask_regex$/i) {
      $self->{pbot}->logger->log("anti-flood: [check-bans] Hostmask matches quiet banmask, disregarding\n");
      return undef;
    }

    push @$bans, $baninfo;
    return $baninfo;
  }
  return undef;
}

sub check_nickserv_accounts {
  my ($self, $nick, $account) = @_;

  my ($account_mask, @bans);

  foreach my $mask (keys %{ $self->{message_history} }) {
    if(exists $self->{message_history}->{$mask}->{nickserv_account}) {
      # has nickserv account
      if(lc $self->{message_history}->{$mask}->{nickserv_account} eq lc $account) {
        # pre-existing mask found using this account previously, check for bans
        $self->{pbot}->logger->log("anti-flood: [check-account] $nick [nickserv: $account] seen previously as $mask.\n");
        $self->check_bans(\@bans, $mask);
      }
    }
    else {
      # no nickserv account set yet
      if($mask =~ m/^\Q$nick\E!/i) {
        # nick matches, must belong to account
        $self->{pbot}->logger->log("anti-flood: $mask: setting nickserv account to [$account]\n");
        $self->message_history->{$mask}->{nickserv_account} = $account;

        $account_mask = $mask;
        $self->check_bans(\@bans, $mask);
      }
    }
  }

  foreach my $baninfo (@bans) {
    $self->{pbot}->logger->log("anti-flood: [check-bans] $account_mask may have evaded $baninfo->{banmask} banned in $baninfo->{channel} by $baninfo->{owner}\n");
    #$self->{pbot}->conn->privmsg($nick, "You have been banned in $baninfo->{channel} for attempting to evade a ban on $baninfo->{banmask} set by $baninfo->{owner}");

    $account_mask =~ m/[^!]+\!(.*)/;
    my $banmask = "*!$1";

    $self->{pbot}->logger->log("anti-flood: [check-bans] Ban detected on account $account in $baninfo->{channel}, banning $banmask.\n");

    $self->{pbot}->chanops->ban_user_timed($banmask, $baninfo->{channel}, 60 * 60 * 5);
  }
}

sub on_whoisaccount {
  my ($self, $conn, $event) = @_;
  my $nick    = $event->{args}[1];
  my $account = $event->{args}[2];

  $self->{pbot}->logger->log("$nick is using NickServ account [$account]\n");
  $self->check_nickserv_accounts($nick, $account);
}

1;
