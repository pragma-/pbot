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
use Text::Balanced qw(extract_delimited);

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

  my ($channel, $trigger) = $self->{pbot}->factoids->find_factoid($from, $keyword);

  if(not defined $trigger) {
    return "/msg $nick Failed to find module for '$keyword' in channel $from\n";
  }

  my $module = $self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{action};
  my $module_dir = $self->{pbot}->module_dir;

  $self->{pbot}->logger->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host: Executing module $module $arguments\n");

  $arguments =~ s/\$nick/$nick/g;

  $arguments = quotemeta($arguments);
  $arguments =~ s/\\\s/ /;

  if(exists $self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{modulelauncher_subpattern}) {
    if($self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{modulelauncher_subpattern} =~ m/s\/(.*?)\/(.*)\//) {
      my ($p1, $p2) = ($1, $2);
      $arguments =~ s/$p1/$p2/;
      my ($a, $b, $c, $d, $e, $f, $g, $h, $i, $before, $after) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $`, $');
      $arguments =~ s/\$1/$a/g;
      $arguments =~ s/\$2/$b/g;
      $arguments =~ s/\$3/$c/g;
      $arguments =~ s/\$4/$d/g;
      $arguments =~ s/\$5/$e/g;
      $arguments =~ s/\$6/$f/g;
      $arguments =~ s/\$7/$g/g;
      $arguments =~ s/\$8/$h/g;
      $arguments =~ s/\$9/$i/g;
      $arguments =~ s/\$`/$before/g;
      $arguments =~ s/\$'/$after/g;
    } else {
      $self->{pbot}->logger->log("Invalid module substitution pattern [" . $self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{modulelauncher_subpattern}. "], ignoring.\n");
    }
  }

  my $argsbuf = $arguments;
  $arguments = "";

  my $lr;
  while(1) {
    my ($e, $r, $p) = extract_delimited($argsbuf, "'", "[^']+");

    $lr = $r if not defined $lr;

    if(defined $e) {
      $e =~ s/\\([^\w])/$1/g;
      $e =~ s/'/'\\''/g;
      $e =~ s/^'\\''/'/;
      $e =~ s/'\\''$/'/;
      $arguments .= $p;
      $arguments .= $e;
      $lr = $r;
    } else {
      $arguments .= $lr;
      last;
    }
  }

  my $pid = fork;
  if(not defined $pid) {
    $self->{pbot}->logger->log("Could not fork module: $!\n");
    return "/me groans loudly.";
  }

  # FIXME -- add check to ensure $module} exists

  if($pid == 0) { # start child block
    $self->{child} = 1; # set to be killed after returning
    
    # don't quit the IRC client when the child dies
    no warnings;
    *PBot::IRC::Connection::DESTROY = sub { return; };
    use warnings;

    if(not chdir $module_dir) {
      $self->{pbot}->logger->log("Could not chdir to '$module_dir': $!\n");
      Carp::croak("Could not chdir to '$module_dir': $!");
    }

    print "module arguments: [$arguments]\n";

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
