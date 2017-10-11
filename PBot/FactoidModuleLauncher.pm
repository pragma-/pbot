# File: FactoidModuleLauncher.pm
# Author: pragma_
#
# Purpose: Handles forking and execution of module processes

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::FactoidModuleLauncher;

use warnings;
use strict;

use POSIX qw(WNOHANG); # for children process reaping
use Carp ();
use Text::Balanced qw(extract_delimited);
use JSON;

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
  my ($self, $from, $tonick, $nick, $user, $host, $command, $root_channel, $root_keyword, $keyword, $arguments, $preserve_whitespace, $referenced) = @_;
  my $text;

  $arguments = "" if not defined $arguments;

  my %stuff = (from => $from, tonick => $tonick, nick => $nick, user => $user, host => $host, command => $command, root_channel => $root_channel,
    root_keyword => $root_keyword, keyword => $keyword, arguments => $arguments, preserve_whitespace => $preserve_whitespace, referenced => $referenced);

  $self->{pbot}->{logger}->log("enter fml: [$from] [$keyword] [$command] [$arguments] [$root_channel] [$root_keyword]\n");

  my @factoids = $self->{pbot}->{factoids}->find_factoid($from, $keyword, undef, 2, 2);

  if(not @factoids or not $factoids[0]) {
    $self->{pbot}->{interpreter}->handle_result($from, $nick, $user, $host, $command, "$keyword $arguments", "/msg $nick Failed to find module for '$keyword' in channel $from\n", 1, 0);
    return;
  }

  my ($channel, $trigger) = ($factoids[0]->[0], $factoids[0]->[1]);

  $stuff{channel} = $channel;
  $stuff{trigger} = $trigger;

  my $module = $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{action};
  my $module_dir = $self->{pbot}->{registry}->get_value('general', 'module_dir');

  $self->{pbot}->{logger}->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host: Executing module [$command] $module $arguments\n");

  $arguments = $self->{pbot}->{factoids}->expand_special_vars($from, $nick, $root_keyword, $arguments);
  $arguments = quotemeta($arguments);

  if($command eq 'code-factoid' or exists $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{unquote_spaces}) {
    $arguments =~ s/\\ / /g;
  }

  if(exists $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{modulelauncher_subpattern}) {
    if($self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{modulelauncher_subpattern} =~ m/s\/(.*?)\/(.*)\/(.*)/) {
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
      #$self->{pbot}->{logger}->log("arguments subpattern: $arguments\n");
    } else {
      $self->{pbot}->{logger}->log("Invalid module substitution pattern [" . $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{modulelauncher_subpattern}. "], ignoring.\n");
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
    $self->{pbot}->{logger}->log("Could not fork module: $!\n");
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
      $self->{pbot}->{logger}->log("Could not chdir to '$module_dir': $!\n");
      Carp::croak("Could not chdir to '$module_dir': $!");
    }

    if(exists $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{workdir}) {
      chdir $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{workdir};
    }


    $stuff{result} = `./$module $arguments 2>> $module-stderr`;
    chomp $stuff{result};

    my $json = encode_json \%stuff;
    print $writer "$json\n";
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

  my $stuff = decode_json $buf or return;

  if (not defined $stuff->{result} or not length $stuff->{result}) {
    $self->{pbot}->{logger}->log("No result from module.\n");
    return;
  }

  if ($stuff->{referenced}) {
    return if $stuff->{result} =~ m/(?:no results)/i;
  }

  if ($stuff->{command} eq 'code-factoid') {
    $stuff->{result} =~ s/\s+$//g;
    $self->{pbot}->{logger}->log("No text result from code-factoid.\n") and return if not length $stuff->{result};
    $self->{pbot}->{logger}->log("fml, cf: text: [$stuff->{result}]\n");

    $stuff->{result} = $self->{pbot}->{factoids}->handle_action($stuff->{nick}, $stuff->{user}, $stuff->{host},
        $stuff->{from}, $stuff->{root_channel}, $stuff->{root_keyword}, $stuff->{root_keyword}, $stuff->{arguments},
        $stuff->{result}, $stuff->{tonick}, 0, $stuff->{referenced}, undef, $stuff->{root_keyword});
    $self->{pbot}->{logger}->log("fml, after handle action: [$stuff->{result}]\n");
  }

  if (defined $stuff->{tonick}) {
    $self->{pbot}->{logger}->log("($stuff->{from}): $stuff->{nick}!$stuff->{user}\@$stuff->{host}) sent to $stuff->{tonick}\n");
      # get rid of original caller's nick
      $stuff->{result} =~ s/^\/([^ ]+) \Q$stuff->{nick}\E:\s+/\/$1 /;
      $stuff->{result} =~ s/^\Q$stuff->{nick}\E:\s+//;
      $self->{pbot}->{interpreter}->handle_result($stuff->{from}, $stuff->{nick}, $stuff->{user}, $stuff->{host}, $stuff->{command}, "$stuff->{keyword} $stuff->{arguments}", "$stuff->{tonick}: $stuff->{result}", 0, $stuff->{preserve_whitespace});
  } else {
    if ($stuff->{command} ne 'code-factoid' and exists $self->{pbot}->{factoids}->{factoids}->hash->{$stuff->{channel}}->{$stuff->{trigger}}->{add_nick} and $self->{pbot}->{factoids}->{factoids}->hash->{$stuff->{channel}}->{$stuff->{trigger}}->{add_nick} != 0) {
      $self->{pbot}->{interpreter}->handle_result($stuff->{from}, $stuff->{nick}, $stuff->{user}, $stuff->{host}, $stuff->{command}, "$stuff->{keyword} $stuff->{arguments}", "$stuff->{nick}: $stuff->{result}", 0, $stuff->{preserve_whitespace});
    } else {
      $self->{pbot}->{interpreter}->handle_result($stuff->{from}, $stuff->{nick}, $stuff->{user}, $stuff->{host}, $stuff->{command}, "$stuff->{keyword} $stuff->{arguments}", $stuff->{result}, 0, $stuff->{preserve_whitespace});
    }
  }

  my $text = $self->{pbot}->{interpreter}->truncate_result($stuff->{channel}, $self->{pbot}->{registry}->get_value('irc', 'botnick'), 'undef', $stuff->{result}, $stuff->{result}, 0);
  $self->{pbot}->{antiflood}->check_flood($stuff->{channel}, $self->{pbot}->{registry}->get_value('irc', 'botnick'), $self->{pbot}->{registry}->get_value('irc', 'username'), 'localhost', $text, 0, 0, 0);
}

1;
