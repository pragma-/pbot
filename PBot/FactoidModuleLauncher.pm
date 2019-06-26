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

use POSIX qw(WNOHANG);
use Carp ();
use Text::Balanced qw(extract_delimited);
use JSON;

# automatically reap children processes in background
$SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) {} };

sub new {
  if (ref($_[1]) eq 'HASH') {
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
  if (not defined $pbot) {
    Carp::croak("Missing pbot reference to PBot::FactoidModuleLauncher");
  }

  $self->{pbot} = $pbot;
}

sub execute_module {
  my ($self, $stuff) = @_;
  my $text;

  if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
    use Data::Dumper;
    $Data::Dumper::Sortkeys  = 1;
    $self->{pbot}->{logger}->log("FML::execute_module\n");
    $self->{pbot}->{logger}->log(Dumper $stuff);
  }

  $stuff->{arguments} = "" if not defined $stuff->{arguments};

  my @factoids = $self->{pbot}->{factoids}->find_factoid($stuff->{from}, $stuff->{keyword}, exact_channel => 2, exact_trigger => 2);

  if (not @factoids or not $factoids[0]) {
    $stuff->{checkflood} = 1;
    $self->{pbot}->{interpreter}->handle_result($stuff, "/msg $stuff->{nick} Failed to find module for '$stuff->{keyword}' in channel $stuff->{from}\n");
    return;
  }

  my ($channel, $trigger) = ($factoids[0]->[0], $factoids[0]->[1]);

  $stuff->{channel} = $channel;
  $stuff->{keyword} = $trigger;
  $stuff->{trigger} = $trigger;

  my $module = $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{action};
  my $module_dir = $self->{pbot}->{registry}->get_value('general', 'module_dir');

  $self->{pbot}->{logger}->log("(" . (defined $stuff->{from} ? $stuff->{from} : "(undef)") . "): $stuff->{nick}!$stuff->{user}\@$stuff->{host}: Executing module [$stuff->{command}] $module $stuff->{arguments}\n");

  $stuff->{arguments} = $self->{pbot}->{factoids}->expand_special_vars($stuff->{from}, $stuff->{nick}, $stuff->{root_keyword}, $stuff->{arguments});
  $stuff->{arguments} = quotemeta $stuff->{arguments};
  $stuff->{arguments} =~ s/\\ / /g;

  pipe(my $reader, my $writer);
  my $pid = fork;

  if (not defined $pid) {
    $self->{pbot}->{logger}->log("Could not fork module: $!\n");
    close $reader;
    close $writer;
    $stuff->{checkflood} = 1;
    $self->{pbot}->{interpreter}->handle_result($stuff, "/me groans loudly.\n");
    return;
  }

  # FIXME -- add check to ensure $module exists

  if ($pid == 0) { # start child block
    close $reader;

    # don't quit the IRC client when the child dies
    no warnings;
    *PBot::IRC::Connection::DESTROY = sub { return; };
    use warnings;

    if (not chdir $module_dir) {
      $self->{pbot}->{logger}->log("Could not chdir to '$module_dir': $!\n");
      Carp::croak("Could not chdir to '$module_dir': $!");
    }

    if (exists $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{workdir}) {
      chdir $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{workdir};
    }

    $stuff->{result} = `./$module $stuff->{arguments} 2>> $module-stderr`;
    chomp $stuff->{result};

    my $json = encode_json $stuff;
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

  my $stuff = decode_json $buf or do {
    $self->{pbot}->{logger}->log("Failed to decode bad json: [$buf]\n");
    return;
  };

  if (not defined $stuff->{result} or not length $stuff->{result}) {
    $self->{pbot}->{logger}->log("No result from module.\n");
    return;
  }

  if ($stuff->{referenced}) {
    return if $stuff->{result} =~ m/(?:no results)/i;
  }

  if (exists $stuff->{special} and $stuff->{special} eq 'code-factoid') {
    $stuff->{result} =~ s/\s+$//g;
    $self->{pbot}->{logger}->log("No text result from code-factoid.\n") and return if not length $stuff->{result};

    $stuff->{original_keyword} = $stuff->{root_keyword};

    $stuff->{result} = $self->{pbot}->{factoids}->handle_action($stuff, $stuff->{result});
  }

  $stuff->{checkflood} = 0;

  if (defined $stuff->{nickoverride}) {
    $self->{pbot}->{interpreter}->handle_result($stuff, $stuff->{result});
  } else {
    # don't override nick if already set
    if (exists $stuff->{special} and $stuff->{special} ne 'code-factoid' and exists $self->{pbot}->{factoids}->{factoids}->hash->{$stuff->{channel}}->{$stuff->{trigger}}->{add_nick} and $self->{pbot}->{factoids}->{factoids}->hash->{$stuff->{channel}}->{$stuff->{trigger}}->{add_nick} != 0) {
      $stuff->{nickoverride} = $stuff->{nick};
      $stuff->{no_nickoverride} = 0;
      $stuff->{force_nickoverride} = 1;
    } else {
      # extract nick-like thing from module result
      if ($stuff->{result} =~ s/^(\S+): //) {
        my $nick = $1;
        if (lc $nick eq "usage") {
          # put it back on result if it's a usage message
          $stuff->{result} = "$nick: $stuff->{result}";
        } else {
          my $present = $self->{pbot}->{nicklist}->is_present($stuff->{channel}, $nick);
          if ($present) {
            # nick is present in channel
            $stuff->{nickoverride} = $present;
          } else {
            # nick not present, put it back on result
            $stuff->{result} = "$nick: $stuff->{result}";
          }
        }
      }
    }
    $self->{pbot}->{interpreter}->handle_result($stuff, $stuff->{result});
  }

  my $text = $self->{pbot}->{interpreter}->truncate_result($stuff->{channel}, $self->{pbot}->{registry}->get_value('irc', 'botnick'), 'undef', $stuff->{result}, $stuff->{result}, 0);
  $self->{pbot}->{antiflood}->check_flood($stuff->{from}, $self->{pbot}->{registry}->get_value('irc', 'botnick'), $self->{pbot}->{registry}->get_value('irc', 'username'), 'localhost', $text, 0, 0, 0);
}

1;
