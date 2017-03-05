# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::StdinReader;

use warnings;
use strict;

use POSIX qw(tcgetpgrp getpgrp);  # to check whether process is in background or foreground
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to StdinReader should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference in StdinReader");

  # used to check whether process is in background or foreground, for stdin reading
  open TTY, "</dev/tty" or die $!;
  $self->{tty_fd} = fileno(TTY);

  $self->{pbot}->{select_handler}->add_reader(\*STDIN, sub { $self->stdin_reader(@_) });
}

sub stdin_reader {
  my ($self, $input) = @_;

  # make sure we're in the foreground first
  $self->{foreground} = (tcgetpgrp($self->{tty_fd}) == getpgrp()) ? 1 : 0;
  return if not $self->{foreground};

  $self->{pbot}->{logger}->log("---------------------------------------------\n");
  $self->{pbot}->{logger}->log("Read '$input' from STDIN\n");

  my ($from, $text);

  if($input =~ m/^~([^ ]+)\s+(.*)/) {
    $from = $1;
    $text = $self->{pbot}->{registry}->get_value('irc', 'botnick') . " $2";
  } else {
    $from = $self->{pbot}->{registry}->get_value('irc', 'botnick') . "!stdin\@localhost";
    $text = $self->{pbot}->{registry}->get_value('irc', 'botnick') . " $input";
  }

  return $self->{pbot}->{interpreter}->process_line($from, $self->{pbot}->{registry}->get_value('irc', 'botnick'), "stdin", "localhost", $text);
}

1;
