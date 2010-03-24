# File: IgnoreListCommands.pm
# Author: pragma_
#
# Purpose: Bot commands for interfacing with ignore list.

package PBot::IgnoreListCommands;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Time::HiRes qw(gettimeofday);
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to IgnoreListCommands should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to IgnoreListCommands");
  }

  $self->{pbot} = $pbot;

  $pbot->commands->register(sub { return $self->ignore_user(@_)    },    "ignore",    10);
  $pbot->commands->register(sub { return $self->unignore_user(@_)  },    "unignore",  10);
}

sub ignore_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  return "/msg $nick Usage: ignore nick!user\@host [channel] [timeout]" if not defined $arguments;

  my ($target, $channel, $length) = split /\s+/, $arguments;

  if(not defined $target) {
     return "/msg $nick Usage: ignore host [channel] [timeout]";
  }

  if($target =~ /^list$/i) {
    my $text = "Ignored: ";
    my $sep = "";

    foreach my $ignored (keys %{ $self->{pbot}->ignorelist->{ignore_list} }) {
      foreach my $channel (keys %{ ${ $self->{pbot}->ignorelist->{ignore_list} }{$ignored} }) {
        $text .= $sep . "[$ignored][$channel]" . int(gettimeofday - ${ $self->{pbot}->ignorelist->{ignore_list} }{$ignored}{$channel});
        $sep = "; ";
      }
    }
    return "/msg $nick $text";
  }

  if(not defined $channel) {
    $channel = ".*"; # all channels
  }
  
  if(not defined $length) {
    $length = 300; # 5 minutes
  }

  $self->{pbot}->logger->log("$nick added [$target][$channel] to ignore list for $length seconds\n");
  $self->{pbot}->ignorelist->add($target, $channel, $length);
  return "/msg $nick [$target][$channel] added to ignore list for $length seconds";
}

sub unignore_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($target, $channel) = split /\s+/, $arguments if defined $arguments;

  if(not defined $target) {
    return "/msg $nick Usage: unignore host [channel]";
  }

  if(not defined $channel) {
    $channel = ".*";
  }
  
  if(not exists ${ $self->{pbot}->ignorelist->{ignore_list} }{$target}{$channel}) {
    $self->{pbot}->logger->log("$nick attempt to remove nonexistent [$target][$channel] from ignore list\n");
    return "/msg $nick [$target][$channel] not found in ignore list (use '!ignore list' to list ignores";
  }
  
  $self->{pbot}->ignorelist->remove($target, $channel);
  $self->{pbot}->logger->log("$nick removed [$target][$channel] from ignore list\n");
  return "/msg $nick [$target][$channel] unignored";
}

1;
