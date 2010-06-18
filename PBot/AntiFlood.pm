# File: AntiFlood.pm
# Author: pragma_
#
# Purpose: Keeps track of which nick has said what and when.  Used in
# conjunction with OperatorStuff and Quotegrabs for kick/quiet on flood
# and grabbing quotes, respectively.

package PBot::AntiFlood;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Time::HiRes qw(gettimeofday);
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

sub check_flood {
  my ($self, $channel, $nick, $user, $host, $text, $max_messages, $max_time, $mode) = @_;
  my $now = gettimeofday;

  $channel = lc $channel;

  $self->{pbot}->logger->log(sprintf("%-14s | %-65s | %s\n", $channel, "$nick!$user\@$host", $text));

  return if $nick eq $self->{pbot}->botnick;

  my $account = $self->get_flood_account($nick, $user, $host);

  if(not defined $account) {
    # new addition
    #$self->{pbot}->logger->log("brand new nick addition\n");
    ${ $self->message_history }{$nick}{hostmask} = "$nick!$user\@$host";

    $account = $nick;
  }

  if(not exists ${ $self->message_history }{$account}{$channel}) {
    #$self->{pbot}->logger->log("adding new channel for existing nick\n");
    ${ $self->message_history }{$account}{$channel}{offenses} = 0;
    ${ $self->message_history }{$account}{$channel}{join_watch} = 0;
    ${ $self->message_history }{$account}{$channel}{messages} = [];
  }

  #$self->{pbot}->logger->log("appending new message\n");
  push(@{ ${ $self->message_history }{$account}{$channel}{messages} }, { timestamp => $now, msg => $text, mode => $mode });

  my $length = $#{ ${ $self->message_history }{$account}{$channel}{messages} } + 1;

  if($length >= $self->{pbot}->{MAX_NICK_MESSAGES}) {
    my %msg = %{ shift(@{ ${ $self->message_history }{$account}{$channel}{messages} }) };
    #$self->{pbot}->logger->log("shifting message off top: $msg{msg}, $msg{timestamp}\n");
    $length--;
  }

  return if ($channel =~ /^#/) and (not exists ${ $self->{pbot}->channels->channels }{$channel} or ${ $self->{pbot}->channels->channels }{$channel}{is_op} == 0);

  if($mode == $self->{FLOOD_JOIN}) {
    if($text =~ /^JOIN/) {
      ${ $self->message_history }{$account}{$channel}{join_watch}++;
      $self->{pbot}->logger->log("$nick $channel joinwatch adjusted: ${ $self->message_history }{$account}{$channel}{join_watch}\n");
    } else {
      # PART or QUIT

      # if QUIT, then assume they existed on any channel the bot exists on
      # this makes it possible to deal with ping timeout quits 
      foreach my $chan (keys %{ $self->{pbot}->channels->channels }) {
        if(not exists ${ $self->message_history }{$account}{$chan}) {
          ${ $self->message_history }{$account}{$chan}{offenses} = 0;
          ${ $self->message_history }{$account}{$chan}{join_watch} = 0;
          ${ $self->message_history }{$account}{$chan}{messages} = [];
        }
        push(@{ ${ $self->message_history }{$account}{$chan}{messages} }, { timestamp => $now, msg => $text, mode => $mode }) unless $chan eq $channel;
      }

      # check QUIT message for netsplits, and decrement joinwatch if found
      if($text =~ /^QUIT .*\.net .*\.split/) {
        foreach my $ch (keys %{ $self->message_history->{$account} }) {
          next if $ch eq 'hostmask'; # TODO: move channels into {channel} subkey
          next if $ch !~ /^#/;
          ${ $self->message_history }{$account}{$ch}{join_watch}--;
          ${ $self->message_history }{$account}{$ch}{join_watch} = 0 if ${ $self->message_history }{$account}{$ch}{join_watch} < 0;
          $self->{pbot}->logger->log("$nick $ch joinwatch adjusted: ${ $self->message_history }{$account}{$ch}{join_watch}\n");
        }
      } 
      # check QUIT message for Ping timeout
      elsif($text =~ /^QUIT Ping timeout/) {
        # deal with ping timeouts agressively
        foreach my $ch (keys %{ $self->message_history->{$account} }) {
          next if $ch eq 'hostmask'; # TODO: move channels into {channel} subkey
          next if $ch !~ /^#/;
          ${ $self->message_history }{$account}{$ch}{join_watch}++;
          $self->{pbot}->logger->log("$nick $ch joinwatch adjusted: ${ $self->message_history }{$account}{$ch}{join_watch}\n");
        }
      }
    }
  } elsif($mode == $self->{FLOOD_CHAT}) {
    # reset joinwatch if they send a message
    ${ $self->message_history }{$account}{$channel}{join_watch} = 0;
  }

  if($max_messages > $self->{pbot}->{MAX_NICK_MESSAGES}) {
    $self->{pbot}->logger->log("Warning: max_messages greater than MAX_NICK_MESSAGES; truncating.\n");
    $max_messages = $self->{pbot}->{MAX_NICK_MESSAGES};
  }

  if($max_messages > 0 and $length >= $max_messages) {
    $self->{pbot}->logger->log("More than $max_messages messages, comparing time differences ($max_time)\n") if $mode == $self->{FLOOD_JOIN};

    my %msg = %{ @{ ${ $self->message_history }{$account}{$channel}{messages} }[$length - $max_messages] };
    my %last = %{ @{ ${ $self->message_history }{$account}{$channel}{messages} }[$length - 1] };

    $self->{pbot}->logger->log("Comparing " . int($last{timestamp}) . " against " . int($msg{timestamp}) . ": " . (int($last{timestamp} - $msg{timestamp})) . " seconds\n") if $mode == $self->{FLOOD_JOIN};

    if($last{timestamp} - $msg{timestamp} <= $max_time && not $self->{pbot}->admins->loggedin($channel, "$nick!$user\@$host")) {
      if($mode == $self->{FLOOD_JOIN}) {
        if(${ $self->message_history }{$account}{$channel}{join_watch} >= $max_messages) {
          ${ $self->message_history }{$account}{$channel}{offenses}++;
          
          my $timeout = (2 ** (($self->message_history->{$account}{$channel}{offenses} + 6) < 10 ? ${ $self->message_history }{$account}{$channel}{offenses} + 6 : 10));
          
          $self->{pbot}->chanops->quiet_user_timed("*!$user\@$host\$##fix_your_connection", $channel, $timeout * 60 * 60);
          
          $self->{pbot}->logger->log("$nick!$user\@$host banned for $timeout hours due to join flooding (offense #${ $self->message_history }{$account}{$channel}{offenses}).\n");
          
          $timeout = "several" if($timeout > 8);

          my $captcha = generate_random_string(7);
          ${ $self->message_history }{$account}{$channel}{captcha} = $captcha;
          
          $self->{pbot}->conn->privmsg($nick, "You have been banned from $channel for $timeout hours due to join flooding.  If your connection issues have been fixed, or this was an accident, you may request an unban by responding to this message with: unbanme $channel $captcha");

          ${ $self->message_history }{$account}{$channel}{join_watch} = $max_messages - 2; # give them a chance to rejoin 
        } 
      } elsif($mode == $self->{FLOOD_CHAT}) {
        ${ $self->message_history }{$account}{$channel}{offenses}++;
        my $length = ${ $self->message_history }{$account}{$channel}{offenses} ** ${ $self->message_history }{$account}{$channel}{offenses} * ${ $self->message_history }{$account}{$channel}{offenses} * 30;
        if($channel =~ /^#/) { #channel flood (opposed to private message or otherwise)
          return if exists $self->{pbot}->chanops->{quieted_masks}->{"*!*\@$host"};
          if($mode == $self->{FLOOD_CHAT}) {
            $self->{pbot}->chanops->quiet_user_timed("*!$user\@$host", $channel, $length);

            $self->{pbot}->logger->log("$nick $channel flood offense ${ $self->message_history }{$account}{$channel}{offenses} earned $length second quiet\n");

            if($length  < 1000) {
              $length = "$length seconds";
            } else {
              $length = "a little while";
            }

            $self->{pbot}->conn->privmsg($nick, "You have been quieted due to flooding.  Please use a web paste service such as http://codepad.org for lengthy pastes.  You will be allowed to speak again in $length.");
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

  my ($channel, $captcha) = split / /, $arguments;

  if(not defined $channel or not defined $captcha) {
    return "/msg $nick Usage: unbanme <channel> <captcha>";
  }

  my $mask = "*!$user\@$host\$##fix_your_connection";

  if(not exists $self->{pbot}->{chanops}->{quieted_masks}->{$mask}) {
    return "/msg $nick There is no temporary ban set for $mask in channel $channel.";
  }

  if(not $self->{pbot}->chanops->{quieted_masks}->{$mask}{channel} eq $channel) {
    return "/msg $nick There is no temporary ban set for $mask in channel $channel.";
  }

  my $account = $self->get_flood_account($nick, $user, $host);

  if(not defined $account) {
    return "/msg $nick I do not remember you.";
  }

  if(not exists $self->{message_history}->{$account}{$channel}{captcha}) {
    return "/msg $nick I do not remember banning you in $channel.";
  }

  if(not $self->{message_history}->{$account}{$channel}{captcha} eq $captcha) {
    return "/msg $nick Incorrect captcha.";
  }

  # TODO: these delete statements need to be abstracted to methods on objects
  $self->{pbot}->chanops->unquiet_user($mask, $channel);
  delete $self->{pbot}->chanops->{quieted_masks}->{$mask};
  delete $self->{message_history}->{$account}{$channel}{captcha};

  return "/msg $nick You have been unbanned from $channel.";
}

# based on Guy Malachi's code
sub generate_random_string {
  my $length_of_randomstring = shift;

  my @chars=('a'..'z','A'..'Z','0'..'9','_');
  my $random_string;

  foreach (1..$length_of_randomstring) {
    $random_string .= $chars[rand @chars];
  }

  return $random_string;
}

1;
