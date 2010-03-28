# File: FactoidModuleLauncher.pm
# Author: pragma_
#
# Purpose: Handles forking and execution of module processes

package PBot::FactoidModuleLauncher;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use POSIX qw(WNOHANG); # for children process reaping
use Carp ();

# automatically reap children processes in background
$SIG{CHLD} = sub { while(waitpid(-1, WNOHANG) > 0) {} };

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Commands should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to PBot::FactoidModuleLauncher");
  }

  $self->{child} = 0;
  $self->{pbot} = $pbot;
}

sub execute_module {
  my ($self, $from, $tonick, $nick, $user, $host, $keyword, $arguments) = @_;
  my $text;

  $arguments = "" if not defined $arguments;

  my $module = $self->{pbot}->factoids->factoids->{$keyword}{module};
  my $module_dir = $self->{pbot}->module_dir;

  $self->{pbot}->logger->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host: Executing module $module $arguments\n");

  $arguments = quotemeta($arguments);
  $arguments =~ s/\\\s+/ /g;
  $arguments =~ s/\-/-/g;

  print "args: $arguments\n";
  
  my $pid = fork;
  if(not defined $pid) {
    $self->{pbot}->logger->log("Could not fork module: $!\n");
    return "/me groans loudly.";
  }

  # FIXME -- add check to ensure $module} exists

  if($pid == 0) { # start child block
    $self->{child} = 1; # set to be killed after returning
    
    if(defined $tonick) {
      $self->{pbot}->logger->log("($from): $nick!$user\@$host) sent to $tonick\n");
      $text = `$module_dir/$module $arguments`;
      if(defined $text && length $text > 0) {
        return "$tonick: $text";
      } else {
        return "";
      }
    } else {
      return `$module_dir/$module $arguments`;
    }

    return "/me moans loudly."; # er, didn't execute the module?
  } # end child block
  else {
    $self->{child} = 0;
  }
  
  return ""; # child returns bot command, not parent -- so return blank/no command
}

1;
