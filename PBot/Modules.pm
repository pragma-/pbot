# File: Modules.pm
# Authoer: pragma_
#
# Purpose: Handles forking and execution of module processes

package PBot::Modules;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw($child %commands $logger $module_dir);
}

use vars @EXPORT_OK;

*commands = \%PBot::InternalCommands::commands;
*logger = \$PBot::PBot::logger;
*module_dir = \$PBot::PBot::module_dir;

use POSIX qw(WNOHANG); # for children process reaping

# automatically reap children processes in background
$SIG{CHLD} = sub { while(waitpid(-1, WNOHANG) > 0) {} };

$child = 0; # determines whether process is child

sub execute_module {
  my ($from, $tonick, $nick, $user, $host, $keyword, $arguments) = @_;
  my $text;

  $arguments = "" if not defined $arguments;

  $logger->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host: Executing module $commands{$keyword}{module} $arguments\n");

  $arguments = quotemeta($arguments);
  $arguments =~ s/\\\s+/ /;
  
  my $pid = fork;
  if(not defined $pid) {
    $logger->log("Could not fork module: $!\n");
    return "/me groans loudly.";
  }

  # FIXME -- add check to ensure $commands{$keyword}{module} exists

  if($pid == 0) { # start child block
    $child = 1; # set to be killed after returning
    
    if(defined $tonick) {
      $logger->log("($from): $nick!$user\@$host) sent to $tonick\n");
      $text = `$module_dir/$commands{$keyword}{module} $arguments`;
      my $fromnick = PBot::BotAdminStuff::loggedin($nick, $host) ? "" : " ($nick)";
      #return "/msg $tonick $text$fromnick"; # send private message to user
      if(defined $text && length $text > 0) {
        return "$tonick: $text";
      } else {
        return "";
      }
    } else {
      return `$module_dir/$commands{$keyword}{module} $arguments`;
    }

    return "/me moans loudly."; # er, didn't execute the module?
  } # end child block
  
  return ""; # child returns bot command, not parent -- so return blank/no command
}

1;
