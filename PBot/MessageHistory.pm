# File: MessageHistory.pm
# Author: pragma_
#
# Purpose: Keeps track of who has said what and when, as well as their
# nickserv accounts and alter-hostmasks.  
#
# Used in conjunction with AntiFlood and Quotegrabs for kick/ban on
# flood/ban-evasion and grabbing quotes, respectively.

package PBot::MessageHistory;

use warnings;
use strict;

use Time::HiRes qw(gettimeofday tv_interval);
use Time::Duration;
use Carp ();

use PBot::MessageHistory_SQLite;

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
  $self->{filename} = delete $conf{filename} // $self->{pbot}->{data_dir} . '/message_history.sqlite3';

  $self->{database} = PBot::MessageHistory_SQLite->new(pbot => $self->{pbot}, filename => $self->{filename});
  $self->{database}->begin();
  $self->{database}->devalidate_all_channels();

  $self->{MSG_CHAT}   =  0;
  $self->{MSG_JOIN}   =  1;

  $self->{pbot}->commands->register(sub { $self->recall_message(@_) },  "recall",  0);
}

sub get_message_account {
  my ($self, $nick, $user, $host) = @_;
  return $self->{database}->get_message_account($nick, $user, $host);
}

sub add_message {
  my ($self, $account, $mask, $channel, $text, $mode) = @_;
  $self->{database}->add_message($account, $mask, $channel, { timestamp => scalar gettimeofday, msg => $text, mode => $mode });
}

sub recall_message {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

  if(not defined $arguments or not length $arguments) {
    return "Usage: recall <nick> [history [channel]] -- where [history] is an optional argument that is either an integral number of recent messages or a regex (without whitespace) of the text within the message; e.g., to recall the 3rd most recent message for nick, use `recall nick 3` or to recall a message containing 'pizza', use `recall nick pizza`; and [channel] is an optional channel, so you can use it from /msg (you will need to also specify [history] in this case)";
  }

  $arguments = lc $arguments;

  my @recalls = split /\s\+\s/, $arguments;

  my ($recall_nick, $recall_history, $channel, $recall_nicks, $recall_text);

  foreach my $recall (@recalls) {
    ($recall_nick, $recall_history, $channel) = split(/\s+/, $recall, 3);

    $recall_history = $nick eq $recall_nick ? 2 : 1 if not defined $recall_history; # skip recall command if recalling self without arguments
    $channel = $from if not defined $channel;

    my ($account, $found_nick) = $self->{database}->find_message_account_by_nick($recall_nick);

    if(not defined $account) {
      return "I don't know anybody named $recall_nick.";
    }

    my $message;

    if($recall_history =~ /^\d+$/) {
      # integral history
      my $max_messages = $self->{database}->get_max_messages($account, $channel);
      if($recall_history < 1 || $recall_history > $max_messages) {
        return "Please choose a history between 1 and $max_messages";
      }

      $recall_history--;

      $message = $self->{database}->recall_message_by_count($account, $channel, $recall_history, 'recall');
    } else {
      # regex history
      $message = $self->{database}->recall_message_by_text($account, $channel, $recall_history, 'recall');
      
      if(not defined $message) {
        return "No such message for nick $found_nick in channel $channel containing text '$recall_history'";
      }
    }

    $self->{pbot}->logger->log("$nick ($from) recalled <$recall_nick/$channel> $message->{msg}\n");

    my $text = $message->{msg};
    my $ago = ago(gettimeofday - $message->{timestamp});

    if(not defined $recall_text) {
      if($text =~ s/^\/me\s+//) {
        $recall_text = "[$ago] * $found_nick $text";
      } else {
        $recall_text = "[$ago] <$found_nick> $text";
      }
    } else {
      if($text =~ s/^\/me\s+//) {
        $recall_text .= " [$ago] * $found_nick $text";
      } else {
        $recall_text .= " [$ago] <$found_nick> $text";
      }
    }
  }

  return $recall_text;
}

1;
