# File: NewModule.pm
# Authoer: pragma_
#
# Purpose: New module skeleton

package PBot::OperatorStuff;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw($logger $conn $botnick %quieted_nicks %unban_timeout @op_commands %is_opped);
}

use vars @EXPORT_OK;

use Time::HiRes qw(gettimeofday);

*logger = \$PBot::PBot::logger;
*conn = \$PBot::PBot::conn;
*botnick = \$PBot::PBot::botnick;

%quieted_nicks = ();
%unban_timeout = ();
@op_commands = ();
%is_opped = ();

sub gain_ops {
  my $channel = shift;
  
  if(not exists $is_opped{$channel}) {
    $conn->privmsg("chanserv", "op $channel");
  } else {
    perform_op_commands();
  }
}

sub lose_ops {
  my $channel = shift;
  $conn->privmsg("chanserv", "op $channel -$botnick");
  if(exists $is_opped{$channel}) {
    $is_opped{$channel}{timeout} = gettimeofday + 60; # try again in 1 minute if failed
  }
}

sub perform_op_commands {
  $logger->log("Performing op commands...\n");
  foreach my $command (@op_commands) {
    if($command =~ /^mode (.*?) (.*)/i) {
      $conn->mode($1, $2);
      $logger->log("  executing mode $1 $2\n");
    } elsif($command =~ /^kick (.*?) (.*?) (.*)/i) {
      $conn->kick($1, $2, $3) unless $1 =~ /\Q$botnick\E/i;
      $logger->log("  executing kick on $1 $2 $3\n");
    }
    shift(@op_commands);
  }
  $logger->log("Done.\n");
}

# TODO: move internal commands to OperatorCommands.pm?

sub quiet {
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($target, $length) = split(/\s+/, $arguments);

   if(not defined $from) {
    $logger->log("Command missing ~from parameter!\n");
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

  return "" if $target =~ /\Q$botnick\E/i;

  quiet_nick_timed($target, $from, $length);    
  $conn->privmsg($target, "$nick has quieted you for $length seconds.");
}

sub unquiet {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $logger->log("Command missing ~from parameter!\n");
    return "";
  }

 if(not $from =~ /^#/) { #not a channel
    return "/msg $nick This command must be used in the channel.";
  }

  if(not defined $arguments) {
    return "/msg $nick Usage: unquiet nick";
  }

  unquiet_nick($arguments, $from);
  delete $quieted_nicks{$arguments};
  $conn->privmsg($arguments, "$nick has allowed you to speak again.") unless $arguments =~ /\Q$botnick\E/i;
}

sub quiet_nick {
  my ($nick, $channel) = @_;
  unshift @op_commands, "mode $channel +q $nick!*@*";
  gain_ops($channel);
}

sub unquiet_nick {
  my ($nick, $channel) = @_;
  unshift @op_commands, "mode $channel -q $nick!*@*";
  gain_ops($channel);
}

sub quiet_nick_timed {
  my ($nick, $channel, $length) = @_;

  quiet_nick($nick, $channel);
  $quieted_nicks{$nick}{time} = gettimeofday + $length;
  $quieted_nicks{$nick}{channel} = $channel;
}

# TODO: need to refactor ban_user() and unban_user() - mostly duplicate code
sub ban_user {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $logger->log("Command missing ~from parameter!\n");
    return "";
  }

 if(not $from =~ /^#/) { #not a channel
    if($arguments =~ /^(#.*?) (.*?) (.*)$/) {
      $conn->privmsg("ChanServ", "AUTOREM $1 ADD $2 $3");
      unshift @op_commands, "kick $1 $2 Banned";
      gain_ops($1);
      $logger->log("$nick!$user\@$host AUTOREM $2 ($3)\n");
      return "/msg $nick $2 added to auto-remove";
    } else {
      $logger->log("$nick!$user\@$host: bad format for ban in msg\n");
      return "/msg $nick Usage (in msg mode): !ban <channel> <hostmask> <reason>";  
    }
  } else { #in a channel
    if($arguments =~ /^(.*?) (.*)$/) {
      $conn->privmsg("ChanServ", "AUTOREM $from ADD $1 $2");
      $logger->log("AUTOREM [$from] ADD [$1] [$2]\n");
      $logger->log("kick [$from] [$1] Banned\n");
      unshift @op_commands, "kick $from $1 Banned";
      gain_ops($from);
      $logger->log("$nick ($from) AUTOREM $1 ($2)\n");
      return "/msg $nick $1 added to auto-remove";
    } else {
      $logger->log("$nick!$user\@$host: bad format for ban in channel\n");      
      return "/msg $nick Usage (in channel mode): !ban <hostmask> <reason>";
    }
  }
}

sub unban_user {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $logger->log("Command missing ~from parameter!\n");
    return "";
  }

 if(not $from =~ /^#/) { #not a channel
    if($arguments =~ /^(#.*?) (.*)$/) {
      $conn->privmsg("ChanServ", "AUTOREM $1 DEL $2");
      unshift @op_commands, "mode $1 -b $2"; 
      gain_ops($1);
      delete $unban_timeout{$2};
      $logger->log("$nick!$user\@$host AUTOREM DEL $2 ($3)\n");
      return "/msg $nick $2 removed from auto-remove";
    } else {
      $logger->log("$nick!$user\@$host: bad format for unban in msg\n");
      return "/msg $nick Usage (in msg mode): !unban <channel> <hostmask>";  
    }
  } else { #in a channel
    $conn->privmsg("ChanServ", "AUTOREM $from DEL $arguments");
    unshift @op_commands, "mode $from -b $arguments"; 
    gain_ops($from);
    delete $unban_timeout{$arguments};
    $logger->log("$nick!$user\@$host AUTOREM DEL $arguments\n");
    return "/msg $nick $arguments removed from auto-remove";
  }
}

sub kick_nick {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $logger->log("Command missing ~from parameter!\n");
    return "";
  }

  if(not $from =~ /^#/) {
    $logger->log("$nick!$user\@$host attempted to /msg kick\n");
    return "/msg $nick Kick must be used in the channel.";
  }
  if(not $arguments =~ /(.*?) (.*)/) {
    $logger->log("$nick!$user\@$host: invalid arguments to kick\n");
    return "/msg $nick Usage: !kick <nick> <reason>";
  }
  unshift @op_commands, "kick $from $1 $2";
  gain_ops($from);
}

1;
