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
  
  $pbot->commands->register(sub { return $self->quiet(@_)             },       "quiet",        10);
  $pbot->commands->register(sub { return $self->unquiet(@_)           },       "unquiet",      10);
  $pbot->commands->register(sub { return $self->ban_user(@_)          },       "ban",          10);
  $pbot->commands->register(sub { return $self->unban_user(@_)        },       "unban",        10);
  $pbot->commands->register(sub { return $self->kick_user(@_)         },       "kick",         10);
}

sub quiet {
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
    return "/msg $nick Usage: quiet <mask> [timeout seconds (default: 3600 or 1 hour)]"; 
  }

  if(not defined $length) {
    $length = 60 * 60; # one hour
  }

  return "" if $target =~ /\Q$self->{pbot}->botnick\E/i;

  $self->{pbot}->chanops->quiet_user_timed($target, $from, $length);    
}

sub unquiet {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

  my ($target, $channel) = split / /, $arguments;

  if(not defined $target) {
    return "/msg $nick Usage: unquiet <mask> [channel]";
  }

  $channel = $from if not defined $channel;
  
  return "/msg $nick Unquiet must be used against a channel.  Either use in channel, or specify !unquiet $target <channel>" if $channel !~ /^#/;

  $self->{pbot}->chanops->unquiet_user($arguments, $from);
  delete ${ $self->{pbot}->chanops->{quieted_masks} }{$arguments};
  $self->{pbot}->conn->privmsg($arguments, "$nick has allowed you to speak again.") unless $arguments =~ /\Q$self->{pbot}->botnick\E/i;
  return "Done.";
}

sub ban_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

 if(not $from =~ /^#/) { #not a channel
    if($arguments =~ /^(#.*?) (.*?) (.*)$/) {
      $self->{pbot}->conn->privmsg("ChanServ", "AUTOREM $1 ADD $2 $3");
      unshift @{ $self->{pbot}->chanops->{op_commands} }, "kick $1 $2 Banned";
      $self->{pbot}->chanops->gain_ops($1);
      $self->{pbot}->logger->log("$nick!$user\@$host AUTOREM $2 ($3)\n");
      return "/msg $nick $2 added to auto-remove";
    } else {
      $self->{pbot}->logger->log("$nick!$user\@$host: bad format for ban in msg\n");
      return "/msg $nick Usage (in msg mode): !ban <channel> <hostmask> <reason>";  
    }
  } else { #in a channel
    if($arguments =~ /^(.*?) (.*)$/) {
      $self->{pbot}->conn->privmsg("ChanServ", "AUTOREM $from ADD $1 $2");
      $self->{pbot}->logger->log("AUTOREM [$from] ADD [$1] [$2]\n");
      $self->{pbot}->logger->log("kick [$from] [$1] Banned\n");
      unshift @{ $self->{pbot}->chanops->{op_commands} }, "kick $from $1 Banned";
      $self->{pbot}->chanops->gain_ops($from);
      $self->{pbot}->logger->log("$nick ($from) AUTOREM $1 ($2)\n");
      return "/msg $nick $1 added to auto-remove";
    } else {
      $self->{pbot}->logger->log("$nick!$user\@$host: bad format for ban in channel\n");      
      return "/msg $nick Usage (in channel mode): !ban <hostmask> <reason>";
    }
  }
}

sub unban_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

 if(not $from =~ /^#/) { #not a channel
    if($arguments =~ /^(#.*?) (.*)$/) {
      $self->{pbot}->conn->privmsg("ChanServ", "AUTOREM $1 DEL $2");
      unshift @{ $self->{pbot}->chanops->{op_commands} }, "mode $1 -b $2"; 
      $self->{pbot}->chanops->gain_ops($1);
      delete ${ $self->{pbot}->chanops->{unban_timeouts} }{$2};
      $self->{pbot}->logger->log("$nick!$user\@$host AUTOREM DEL $2 ($3)\n");
      return "/msg $nick $2 removed from auto-remove";
    } else {
      $self->{pbot}->logger->log("$nick!$user\@$host: bad format for unban in msg\n");
      return "/msg $nick Usage (in msg mode): !unban <channel> <hostmask>";  
    }
  } else { #in a channel
    $self->{pbot}->conn->privmsg("ChanServ", "AUTOREM $from DEL $arguments");
    unshift @{ $self->{pbot}->chanops->{op_commands} }, "mode $from -b $arguments"; 
    $self->{pbot}->chanops->gain_ops($from);
    delete ${ $self->{pbot}->chanops->{unban_timeouts} }{$arguments};
    $self->{pbot}->logger->log("$nick!$user\@$host AUTOREM DEL $arguments\n");
    return "/msg $nick $arguments removed from auto-remove";
  }
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
