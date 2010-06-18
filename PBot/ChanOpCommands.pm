# File: ChanOpCommands.pm
# Author: pragma_
#
# Purpose: Channel operator command subroutines.

package PBot::ChanOpCommands;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to ChanOpCommands should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to ChanOpCommands");
  }

  $self->{pbot} = $pbot;
  
  $pbot->commands->register(sub { return $self->ban_user(@_)      },       "ban",        10);
  $pbot->commands->register(sub { return $self->unban_user(@_)    },       "unban",      10);
  $pbot->commands->register(sub { return $self->kick_user(@_)     },       "kick",       10);
}

sub ban_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($target, $length) = split(/\s+/, $arguments);

   if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

 if(not $from =~ /^#/) { #not a channel
    return "/msg $nick This command must be used in the channel.";
  }

  if(not defined $target) {
    return "/msg $nick Usage: ban <mask> [timeout seconds (default: 3600 or 1 hour)]"; 
  }

  if(not defined $length) {
    $length = 60 * 60; # one hour
  }

  return "" if $target =~ /\Q$self->{pbot}->botnick\E/i;

  $self->{pbot}->chanops->ban_user_timed($target, $from, $length);    
}

sub unban_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

  my ($target, $channel) = split / /, $arguments;

  if(not defined $target) {
    return "/msg $nick Usage: unban <mask> [channel]";
  }

  $channel = $from if not defined $channel;
  
  return "/msg $nick Usage for /msg: !unban $target <channel>" if $channel !~ /^#/;

  $self->{pbot}->chanops->unban_user($arguments, $from);
  delete $self->{pbot}->chanops->{unban_timeout}->hash->{$arguments};
  $self->{pbot}->chanops->{unban_timeout}->save_hash();
  return "/msg $nick $arguments has been unbanned.";
}

sub kick_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

  if(not $from =~ /^#/) {
    $self->{pbot}->logger->log("$nick!$user\@$host attempted to /msg kick\n");
    return "/msg $nick Kick must be used in the channel.";
  }
  if(not $arguments =~ /(.*?) (.*)/) {
    $self->{pbot}->logger->log("$nick!$user\@$host: invalid arguments to kick\n");
    return "/msg $nick Usage: !kick <nick> <reason>";
  }
  unshift @{ $self->{pbot}->chanops->{op_commands} }, "kick $from $1 $2";
  $self->{pbot}->chanops->gain_ops($from);
}

1;
