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

  $self->{pbot} = $pbot;
}

sub execute_module {
  my ($self, $from, $tonick, $nick, $user, $host, $command, $keyword, $arguments, $preserve_whitespace) = @_;
  my $text;

  $arguments = "" if not defined $arguments;

  my ($channel, $trigger) = $self->{pbot}->factoids->find_factoid($from, $keyword);

  if(not defined $trigger) {
    $self->{pbot}->{interpreter}->handle_result($from, $nick, $user, $host, $command, "$keyword $arguments", "/msg $nick Failed to find module for '$keyword' in channel $from\n", 1, 0);
    return;
  }

  my $module = $self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{action};
  my $module_dir = $self->{pbot}->module_dir;

  $self->{pbot}->logger->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host: Executing module $module $arguments\n");

  $arguments =~ s/\$nick/$nick/g;
  $arguments =~ s/\$channel/$from/g;

  $arguments = quotemeta($arguments);

  if(exists $self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{unquote_spaces}) {
    $arguments =~ s/\\ / /g;
  }

  if(exists $self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{modulelauncher_subpattern}) {
    if($self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{modulelauncher_subpattern} =~ m/s\/(.*?)\/(.*)\/(.*)/) {
      my ($p1, $p2, $p3) = ($1, $2, $3);
      my ($a, $b, $c, $d, $e, $f, $g, $h, $i, $before, $after);
      if($p3 eq 'g') {
        $arguments =~ s/$p1/$p2/g;
        ($a, $b, $c, $d, $e, $f, $g, $h, $i, $before, $after) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $`, $');
      } else {
        $arguments =~ s/$p1/$p2/;
        ($a, $b, $c, $d, $e, $f, $g, $h, $i, $before, $after) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $`, $');
      }
      $arguments =~ s/\$1/$a/g if defined $a;
      $arguments =~ s/\$2/$b/g if defined $b;
      $arguments =~ s/\$3/$c/g if defined $c;
      $arguments =~ s/\$4/$d/g if defined $d;
      $arguments =~ s/\$5/$e/g if defined $e;
      $arguments =~ s/\$6/$f/g if defined $f;
      $arguments =~ s/\$7/$g/g if defined $g;
      $arguments =~ s/\$8/$h/g if defined $h;
      $arguments =~ s/\$9/$i/g if defined $i;
      $arguments =~ s/\$`/$before/g if defined $before;
      $arguments =~ s/\$'/$after/g if defined $after;
      #$self->{pbot}->logger->log("arguments subpattern: $arguments\n");
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

  pipe(my $reader, my $writer);
  my $pid = fork;

  if(not defined $pid) {
    $self->{pbot}->logger->log("Could not fork module: $!\n");
    close $reader;
    close $writer;
    $self->{pbot}->{interpreter}->handle_result($from, $nick, $user, $host, $command, "$keyword $arguments", "/me groans loudly.\n", 1, 0);
    return; 
  }

  # FIXME -- add check to ensure $module exists

  if($pid == 0) { # start child block
    close $reader;
    
    # don't quit the IRC client when the child dies
    no warnings;
    *PBot::IRC::Connection::DESTROY = sub { return; };
    use warnings;

    if(not chdir $module_dir) {
      $self->{pbot}->logger->log("Could not chdir to '$module_dir': $!\n");
      Carp::croak("Could not chdir to '$module_dir': $!");
    }

    # $self->{pbot}->logger->log("module arguments: [$arguments]\n");

    $text = `$module_dir/$module $arguments`;

    if(defined $tonick) {
      $self->{pbot}->logger->log("($from): $nick!$user\@$host) sent to $tonick\n");
      if(defined $text && length $text > 0) {
        # get rid of original caller's nick
        $text =~ s/^\/([^ ]+) \Q$nick\E:\s+/\/$1 /;
        $text =~ s/^\Q$nick\E:\s+//;

        print $writer "$from $tonick: $text\n";
        $self->{pbot}->{interpreter}->handle_result($from, $nick, $user, $host, $command, "$keyword $arguments", "$tonick: $text", 0, $preserve_whitespace);
      }
      exit 0;
    } else {
      if(exists $self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{add_nick} and $self->{pbot}->factoids->factoids->hash->{$channel}->{$trigger}->{add_nick} != 0) {
        print $writer "$from $nick: $text";
        $self->{pbot}->{interpreter}->handle_result($from, $nick, $user, $host, $command, "$keyword $arguments", "$nick: $text", 0, $preserve_whitespace);
      } else {
        print $writer "$from $text";
        $self->{pbot}->{interpreter}->handle_result($from, $nick, $user, $host, $command, "$keyword $arguments", $text, 0, $preserve_whitespace);
      }
      exit 0;
    }

    # er, didn't execute the module?
    print $writer "$from /me moans loudly.\n";
    $self->{pbot}->{interpreter}->handle_result($from, $nick, $user, $host, $command, "$keyword $arguments", "/me moans loudly.", 0, 0);
    exit 0;
  } # end child block
  else {
    close $writer;
    $self->{pbot}->{select_handler}->add_reader($reader, sub { $self->module_pipe_reader(@_) });
    return "";
  }
}

sub module_pipe_reader {
  my ($self, $buf) = @_;
  my ($channel, $text) = split / /, $buf, 2;
  return if not defined $text or not length $text;
  $text = $self->{pbot}->interpreter->truncate_result($channel, $self->{pbot}->{botnick}, 'undef', $text, $text, 0);
  $self->{pbot}->antiflood->check_flood($channel, $self->{pbot}->{botnick}, $self->{pbot}->{username}, 'localhost', $text, 0, 0, 0);
}

1;
