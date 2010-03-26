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
}

sub check_flood {
  my ($self, $channel, $nick, $user, $host, $text, $max, $mode) = @_;
  my $now = gettimeofday;

  $channel = lc $channel;

  $self->{pbot}->logger->log(sprintf("%-14s | %-65s | %s\n", $channel, "$nick!$user\@$host", $text));
  
  return if $nick eq $self->{pbot}->botnick;

  if(exists ${ $self->message_history }{$nick}) {
    #$self->{pbot}->logger->log("nick exists\n");

    if(not exists ${ $self->message_history }{$nick}{$channel}) {
      #$self->{pbot}->logger->log("adding new channel for existing nick\n");
      ${ $self->message_history }{$nick}{$channel}{offenses} = 0;
      ${ $self->message_history }{$nick}{$channel}{messages} = [];
    }

    #$self->{pbot}->logger->log("appending new message\n");
    
    push(@{ ${ $self->message_history }{$nick}{$channel}{messages} }, { timestamp => $now, msg => $text, mode => $mode });

    my $length = $#{ ${ $self->message_history }{$nick}{$channel}{messages} } + 1;

    #$self->{pbot}->logger->log("length: $length, max nick messages: $MAX_NICK_MESSAGES\n");

    if($length >= $self->{pbot}->{MAX_NICK_MESSAGES}) {
      my %msg = %{ shift(@{ ${ $self->message_history }{$nick}{$channel}{messages} }) };
      #$self->{pbot}->logger->log("shifting message off top: $msg{msg}, $msg{timestamp}\n");
      $length--;
    }

    return if ($channel =~ /^#/) and (not exists ${ $self->{pbot}->channels->channels }{$channel} or ${ $self->{pbot}->channels->channels }{$channel}{is_op} == 0);

    #$self->{pbot}->logger->log("length: $length, max: $max\n");

    if($length >= $max) {
      # $self->{pbot}->logger->log("More than $max messages spoken, comparing time differences\n");
      my %msg = %{ @{ ${ $self->message_history }{$nick}{$channel}{messages} }[$length - $max] };
      my %last = %{ @{ ${ $self->message_history }{$nick}{$channel}{messages} }[$length - 1] };

      #$self->{pbot}->logger->log("Comparing $last{timestamp} against $msg{timestamp}: " . ($last{timestamp} - $msg{timestamp}) . " seconds\n");

      if($last{timestamp} - $msg{timestamp} <= 10 && not $self->{pbot}->admins->loggedin($channel, "$nick!$user\@$host")) {
        ${ $self->message_history }{$nick}{$channel}{offenses}++;
        my $length = ${ $self->message_history }{$nick}{$channel}{offenses} * ${ $self->message_history }{$nick}{$channel}{offenses} * 30;
        if($channel =~ /^#/) { #channel flood (opposed to private message or otherwise)
          if($mode == $self->{FLOOD_CHAT}) {
            $self->{pbot}->chanops->quiet_nick_timed($nick, $channel, $length);
            $self->{pbot}->conn->privmsg($nick, "You have been quieted due to flooding.  Please use a web paste service such as http://codepad.org for lengthy pastes.  You will be allowed to speak again in $length seconds.");
            $self->{pbot}->logger->log("$nick $channel flood offense ${ $self->message_history }{$nick}{$channel}{offenses} earned $length second quiet\n");
          }
        } else { # private message flood
          $self->{pbot}->logger->log("$nick msg flood offense ${ $self->message_history }{$nick}{$channel}{offenses} earned $length second ignore\n");
          $self->{pbot}->{ignorelistcmds}->ignore_user("", "floodcontrol", "", "", "$nick!$user\@$host $channel $length");
        }
      }
    }
  } else {
    #$self->{pbot}->logger->log("brand new nick addition\n");
    # new addition
    ${ $self->message_history }{$nick}{$channel}{offenses}  = 0;
    ${ $self->message_history }{$nick}{$channel}{messages} = [];
    push(@{ ${ $self->message_history }{$nick}{$channel}{messages} }, { timestamp => $now, msg => $text, mode => $mode });
  }
}

sub message_history {
  my $self = shift;
  return $self->{message_history};
}

sub prune_message_history {
  my $self = shift;

  $self->{pbot}->logger->log("Pruning message history . . .\n");
  foreach my $nick (keys %{ $self->{flood_watch} }) {
    foreach my $channel (keys %{ $self->{flood_watch}->{$nick} })
    {
      $self->{pbot}->logger->log("Checking [$nick][$channel]\n");
      my $length = $#{ $self->{flood_watch}->{$nick}{$channel}{messages} } + 1;
      my %last = %{ @{ $self->{flood_watch}->{$nick}{$channel}{messages} }[$length - 1] };

      if(gettimeofday - $last{timestamp} >= 60 * 60 * 24) {
        $self->{pbot}->logger->log("$nick in $channel hasn't spoken in 24 hours, removing message history.\n");
        delete $self->{flood_watch}->{$nick}{$channel};
      }
    }
  }
}

1;
