# File: ChanOps.pm
# Authoer: pragma_
#
# Purpose: Provides channel operator status tracking and commands.

package PBot::ChanOps;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Time::HiRes qw(gettimeofday);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to ChanOps should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to ChanOps");
  }

  $self->{pbot} = $pbot;
  $self->{quieted_nicks} = {};
  $self->{unban_timeouts} = {};
  $self->{op_commands} = [];
  $self->{is_opped} = {};
}


sub gain_ops {
  my $self = shift;
  my $channel = shift;
  
  if(not exists ${ $self->{is_opped} }{$channel}) {
    $self->{pbot}->conn->privmsg("chanserv", "op $channel");
  } else {
    $self->perform_op_commands();
  }
}

sub lose_ops {
  my $self = shift;
  my $channel = shift;
  $self->{pbot}->conn->privmsg("chanserv", "op $channel -$self->{pbot}->botnick");
  if(exists ${ $self->{is_opped} }{$channel}) {
    ${ $self->{is_opped} }{$channel}{timeout} = gettimeofday + 60; # try again in 1 minute if failed
  }
}

sub perform_op_commands {
  my $self = shift;
  $self->{pbot}->logger->log("Performing op commands...\n");
  foreach my $command (@{ $self->{op_commands} }) {
    if($command =~ /^mode (.*?) (.*)/i) {
      $self->{pbot}->conn->mode($1, $2);
      $self->{pbot}->logger->log("  executing mode $1 $2\n");
    } elsif($command =~ /^kick (.*?) (.*?) (.*)/i) {
      $self->{pbot}->conn->kick($1, $2, $3) unless $1 =~ /\Q$self->{pbot}->botnick\E/i;
      $self->{pbot}->logger->log("  executing kick on $1 $2 $3\n");
    }
    shift(@{ $self->{op_commands} });
  }
  $self->{pbot}->logger->log("Done.\n");
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
    return "/msg $nick Usage: quiet nick [timeout seconds (default: 3600 or 1 hour)]"; 
  }

  if(not defined $length) {
    $length = 60 * 60; # one hour
  }

  return "" if $target =~ /\Q$self->{pbot}->botnick\E/i;

  quiet_nick_timed($target, $from, $length);    
  $self->{pbot}->conn->privmsg($target, "$nick has quieted you for $length seconds.");
}

sub unquiet {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

 if(not $from =~ /^#/) { #not a channel
    return "/msg $nick This command must be used in the channel.";
  }

  if(not defined $arguments) {
    return "/msg $nick Usage: unquiet nick";
  }

  unquiet_nick($arguments, $from);
  delete ${ $self->{quieted_nicks} }{$arguments};
  $self->{pbot}->conn->privmsg($arguments, "$nick has allowed you to speak again.") unless $arguments =~ /\Q$self->{pbot}->botnick\E/i;
}

sub quiet_nick {
  my $self = shift;
  my ($nick, $channel) = @_;
  unshift @{ $self->{op_commands} }, "mode $channel +q $nick!*@*";
  gain_ops($channel);
}

sub unquiet_nick {
  my $self = shift;
  my ($nick, $channel) = @_;
  unshift @{ $self->{op_commands} }, "mode $channel -q $nick!*@*";
  gain_ops($channel);
}

sub quiet_nick_timed {
  my $self = shift;
  my ($nick, $channel, $length) = @_;

  quiet_nick($nick, $channel);
  ${ $self->{quieted_nicks} }{$nick}{time} = gettimeofday + $length;
  ${ $self->{quieted_nicks} }{$nick}{channel} = $channel;
}

# TODO: need to refactor ban_user() and unban_user() - mostly duplicate code
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
      unshift @{ $self->{op_commands} }, "kick $1 $2 Banned";
      gain_ops($1);
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
      unshift @{ $self->{op_commands} }, "kick $from $1 Banned";
      gain_ops($from);
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
      unshift @{ $self->{op_commands} }, "mode $1 -b $2"; 
      $self->gain_ops($1);
      delete ${ $self->{unban_timeouts} }{$2};
      $self->{pbot}->logger->log("$nick!$user\@$host AUTOREM DEL $2 ($3)\n");
      return "/msg $nick $2 removed from auto-remove";
    } else {
      $self->{pbot}->logger->log("$nick!$user\@$host: bad format for unban in msg\n");
      return "/msg $nick Usage (in msg mode): !unban <channel> <hostmask>";  
    }
  } else { #in a channel
    $self->{pbot}->conn->privmsg("ChanServ", "AUTOREM $from DEL $arguments");
    unshift @{ $self->{op_commands} }, "mode $from -b $arguments"; 
    $self->gain_ops($from);
    delete ${ $self->{unban_timeouts} }{$arguments};
    $self->{pbot}->logger->log("$nick!$user\@$host AUTOREM DEL $arguments\n");
    return "/msg $nick $arguments removed from auto-remove";
  }
}

sub kick_nick {
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
  unshift @{ $self->{op_commands} }, "kick $from $1 $2";
  $self->gain_ops($from);
}

1;
