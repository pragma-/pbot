# File: AntiFlood.pm
# Author: pragma_
#
# Purpose: Keeps track of which nick has said what and when.  Used in
# conjunction with OperatorStuff and Quotegrabs for kick/ban on flood
# and grabbing quotes, respectively.

package PBot::AntiFlood;

use warnings;
use strict;

use feature 'switch';

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

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

  $self->{flood_msg_count} = 0;
  $self->{last_timestamp} = gettimeofday;
  $self->{message_history} = {};

  $pbot->timer->register(sub { $self->prune_message_history }, 60 * 60 * 1);

  $pbot->commands->register(sub { return $self->unbanme(@_) },  "unbanme",  0);
}

sub get_flood_account {
  my ($self, $nick, $user, $host) = @_;

  return $nick if exists ${ $self->message_history }{$nick};

  foreach my $n (keys %{ $self->{message_history} }) {
    my $userhost = "$user\@$host";
    if(${ $self->{message_history} }{$n}{hostmask} =~ /\Q$userhost\E/i) {
      $self->{pbot}->logger->log("Using existing hostmask found with nick $n\n");
      return $n;
    }
  }

  return undef;
}

sub add_message {
  my ($self, $account, $channel, $text, $mode) = @_;
  my $now = gettimeofday;

  return undef if $channel =~ /[@!]/; # ignore QUIT messages from nick!user@host channels

  #$self->{pbot}->logger->log("appending new message\n");
  push(@{ $self->message_history->{$account}{$channel}{messages} }, { timestamp => $now, msg => $text, mode => $mode });

  my $length = $#{ $self->message_history->{$account}{$channel}{messages} } + 1;

  if($mode == $self->{FLOOD_JOIN}) {
    if($text =~ /^JOIN/) {
      ${ $self->message_history }{$account}{$channel}{join_watch}++;
      $self->{pbot}->logger->log("$account $channel joinwatch adjusted: ${ $self->message_history }{$account}{$channel}{join_watch}\n");
    } else {
      # PART or QUIT
      # check QUIT message for netsplits, and decrement joinwatch if found
      if($text =~ /^QUIT .*\.net .*\.split/) {
        ${ $self->message_history }{$account}{$channel}{join_watch}--;
        ${ $self->message_history }{$account}{$channel}{join_watch} = 0 if ${ $self->message_history }{$account}{$channel}{join_watch} < 0;
        $self->{pbot}->logger->log("$account $channel joinwatch adjusted: ${ $self->message_history }{$account}{$channel}{join_watch}\n");
        $self->message_history->{$account}{$channel}{messages}->[$length - 1]{mode} = $self->{FLOOD_IGNORE}; 
      }
      # check QUIT message for Ping timeout or Excess Flood
      elsif($text =~ /^QUIT Ping timeout/ or $text =~ /^QUIT Excess Flood/) {
        # deal with these aggressively
        #${ $self->message_history }{$account}{$channel}{join_watch}++;
        #$self->{pbot}->logger->log("$account $channel joinwatch adjusted: ${ $self->message_history }{$account}{$channel}{join_watch}\n");
      } else {
        # some other type of QUIT or PART
        $self->message_history->{$account}{$channel}{messages}->[$length - 1]{mode} = $self->{FLOOD_IGNORE};
      }
    }
  } elsif($mode == $self->{FLOOD_CHAT}) {
    # reset joinwatch if they send a message
    ${ $self->message_history }{$account}{$channel}{join_watch} = 0;
  }

  if($length >= $self->{pbot}->{MAX_NICK_MESSAGES}) {
    my %msg = %{ shift(@{ $self->message_history->{$account}{$channel}{messages} }) };
    #$self->{pbot}->logger->log("shifting message off top: $msg{msg}, $msg{timestamp}\n");
    $length--;
  }

  return $length;
}

sub check_flood {
  my ($self, $channel, $nick, $user, $host, $text, $max_messages, $max_time, $mode) = @_;
  my $now = gettimeofday;

  $self->{pbot}->logger->log(sprintf("%-14s | %-65s | %s\n", $channel, "$nick!$user\@$host", $text));

  $nick = lc $nick;
  $user = lc $user;
  $host = lc $host;
  $channel = lc $channel;

  return if $nick eq lc $self->{pbot}->botnick;

  my $account = $self->get_flood_account($nick, $user, $host);

  if(not defined $account) {
    # new addition
    #$self->{pbot}->logger->log("brand new nick addition\n");
    ${ $self->message_history }{$nick}{hostmask} = "$nick!$user\@$host";

    $account = $nick;
  }

  # handle QUIT events
  # (these events come from $channel nick!user@host, not a specific channel or nick,
  # so they need to be dispatched to all channels the bot exists on)
  if($mode == $self->{FLOOD_JOIN} and $text =~ /^QUIT/) {
    foreach my $chan (keys %{ $self->{pbot}->channels->channels->hash }) {
      $chan = lc $chan;

      next if $chan eq $channel;  # skip nick!user@host "channel"

      if(not exists ${ $self->message_history }{$account}{$chan}) {
        #$self->{pbot}->logger->log("adding new channel for existing nick\n");
        ${ $self->message_history }{$account}{$chan}{offenses} = 0;
        ${ $self->message_history }{$account}{$chan}{join_watch} = 0;
        ${ $self->message_history }{$account}{$chan}{messages} = [];
      }

      $self->add_message($account, $chan, $text, $mode);
    }

    # don't do flood processing for QUIT messages
    return;
  }

  if(not exists ${ $self->message_history }{$account}{$channel}) {
    #$self->{pbot}->logger->log("adding new channel for existing nick\n");
    ${ $self->message_history }{$account}{$channel}{offenses} = 0;
    ${ $self->message_history }{$account}{$channel}{join_watch} = 0;
    ${ $self->message_history }{$account}{$channel}{messages} = [];
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
    $self->{pbot}->logger->log("More than $max_messages messages, comparing time differences ($max_time)\n") if $mode == $self->{FLOOD_JOIN};

    my %msg;
    if($mode == $self->{FLOOD_CHAT}) {
      %msg = %{ @{ ${ $self->message_history }{$account}{$channel}{messages} }[$length - $max_messages] };
    } else {
      my $count = 0;
      my $i = $length - 1;
      $self->{pbot}->logger->log("Checking flood history, i = $i\n") if ${ $self->message_history }{$account}{$channel}{join_watch} >= $max_messages;
      for(; $i >= 0; $i--) {
        $self->{pbot}->logger->log($i . " " . $self->message_history->{$account}{$channel}{messages}->[$i]{mode} ." " . $self->message_history->{$account}{$channel}{messages}->[$i]{msg} .  " " . $self->message_history->{$account}{$channel}{messages}->[$i]{timestamp} . " [" . ago_exact(time - $self->message_history->{$account}{$channel}{messages}->[$i]{timestamp}) . "]\n") if ${ $self->message_history }{$account}{$channel}{join_watch} >= $max_messages;
        next if $self->message_history->{$account}{$channel}{messages}->[$i]{mode} != $self->{FLOOD_JOIN};
        last if ++$count >= 4;
      }
      $i = 0 if $i < 0;
      %msg = %{ @{ ${ $self->message_history }{$account}{$channel}{messages} }[$i] };
    }

    my %last = %{ @{ ${ $self->message_history }{$account}{$channel}{messages} }[$length - 1] };

    $self->{pbot}->logger->log("Comparing $nick!$user\@$host " . int($last{timestamp}) . " against " . int($msg{timestamp}) . ": " . (int($last{timestamp} - $msg{timestamp})) . " seconds [" . duration_exact($last{timestamp} - $msg{timestamp}) . "]\n") if $mode == $self->{FLOOD_JOIN};

    if($last{timestamp} - $msg{timestamp} <= $max_time && not $self->{pbot}->admins->loggedin($channel, "$nick!$user\@$host")) {
      if($mode == $self->{FLOOD_JOIN}) {
        if(${ $self->message_history }{$account}{$channel}{join_watch} >= $max_messages) {
          ${ $self->message_history }{$account}{$channel}{offenses}++;
          
          my $timeout = (2 ** (($self->message_history->{$account}{$channel}{offenses} + 2) < 10 ? ${ $self->message_history }{$account}{$channel}{offenses} + 2 : 10));

          my $banmask = address_to_mask($host);

          $self->{pbot}->chanops->ban_user_timed("*!$user\@$banmask\$##stop_join_flood", $channel, $timeout * 60 * 60);
          
          $self->{pbot}->logger->log("$nick!$user\@$banmask banned for $timeout hours due to join flooding (offense #${ $self->message_history }{$account}{$channel}{offenses}).\n");
          
          $timeout = "several" if($timeout > 8);

          $self->{pbot}->conn->privmsg($nick, "You have been banned from $channel for $timeout hours due to join flooding.  If your connection issues have been fixed, or this was an accident, you may request an unban at any time by responding to this message with: unbanme $channel");

          ${ $self->message_history }{$account}{$channel}{join_watch} = $max_messages - 2; # give them a chance to rejoin 
        } 
      } elsif($mode == $self->{FLOOD_CHAT}) {
        ${ $self->message_history }{$account}{$channel}{offenses}++;
        my $length = ${ $self->message_history }{$account}{$channel}{offenses} ** ${ $self->message_history }{$account}{$channel}{offenses} * ${ $self->message_history }{$account}{$channel}{offenses} * 30;
        if($channel =~ /^#/) { #channel flood (opposed to private message or otherwise)
          # don't ban again if already banned
          return if exists $self->{pbot}->chanops->{unban_timeout}->hash->{"*!$user\@$host"};

          if($mode == $self->{FLOOD_CHAT}) {
            $self->{pbot}->chanops->ban_user_timed("*!$user\@$host", $channel, $length);

            $self->{pbot}->logger->log("$nick $channel flood offense ${ $self->message_history }{$account}{$channel}{offenses} earned $length second ban\n");

            if($length  < 1000) {
              $length = "$length seconds";
            } else {
              $length = "a little while";
            }

            $self->{pbot}->conn->privmsg($nick, "You have been muted due to flooding.  Please use a web paste service such as http://codepad.org for lengthy pastes.  You will be allowed to speak again in $length.");
          }
        } else { # private message flood
          return if exists $self->{pbot}->ignorelist->{ignore_list}->{"$nick!$user\@$host"}{$channel};
          $self->{pbot}->logger->log("$nick msg flood offense ${ $self->message_history }{$account}{$channel}{offenses} earned $length second ignore\n");
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
  foreach my $nick (keys %{ $self->{message_history} }) {
    foreach my $channel (keys %{ $self->{message_history}->{$nick} })
    {
      next if $channel eq 'hostmask'; # TODO: move channels into {channel} subkey

      #$self->{pbot}->logger->log("Checking [$nick][$channel]\n");
      my $length = $#{ $self->{message_history}->{$nick}{$channel}{messages} } + 1;
      my %last = %{ @{ $self->{message_history}->{$nick}{$channel}{messages} }[$length - 1] };

      if(gettimeofday - $last{timestamp} >= 60 * 60 * 24 * 3) {
        $self->{pbot}->logger->log("$nick in $channel hasn't spoken in three days, removing message history.\n");
        delete $self->{message_history}->{$nick}{$channel};
      }
    }
  }
}

sub unbanme {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $channel = lc $arguments;
  $host = lc $host;
  $user = lc $user;

  if(not defined $channel) {
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

1;
