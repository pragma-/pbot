# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::StdinReader;

use warnings;
use strict;

use feature 'unicode_strings';

use POSIX qw(tcgetpgrp getpgrp);  # to check whether process is in background or foreground
use Carp ();

sub new {
  Carp::croak("Options to StdinReader should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference in StdinReader");

  # create implicit bot-admin account for bot
  my $user = $self->{pbot}->{users}->find_user('.*', '*!stdin@pbot');
  if (not defined $user or not $self->{pbot}->{capabilities}->userhas($user, 'botowner')) {
    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
    $self->{pbot}->{logger}->log("Adding stdin botowner *!stdin\@pbot...\n");
    $self->{pbot}->{users}->add_user($botnick, '.*', '*!stdin@pbot', 'botowner', undef, 1);
    $self->{pbot}->{users}->login($botnick, "$botnick!stdin\@pbot", undef);
    $self->{pbot}->{users}->save;
  }

  # used to check whether process is in background or foreground, for stdin reading
  if (not $self->{pbot}->{registry}->get_value('general', 'daemon')) {
    open TTY, "</dev/tty" or die $!;
    $self->{tty_fd} = fileno(TTY);
    $self->{pbot}->{select_handler}->add_reader(\*STDIN, sub { $self->stdin_reader(@_) });
  } else {
    $self->{pbot}->{logger}->log("Starting in daemon mode.\n");
  }
}

sub stdin_reader {
  my ($self, $input) = @_;
  chomp $input;

  # make sure we're in the foreground first
  $self->{foreground} = (tcgetpgrp($self->{tty_fd}) == getpgrp()) ? 1 : 0;
  return if not $self->{foreground};

  $self->{pbot}->{logger}->log("---------------------------------------------\n");
  $self->{pbot}->{logger}->log("Got STDIN: $input\n");

  my ($from, $text);

  if ($input =~ m/^~([^ ]+)\s+(.*)/) {
    $from = $1;
    $text = $self->{pbot}->{registry}->get_value('irc', 'botnick') . " $2";
  } else {
    $from = 'stdin@pbot';
    $text = $self->{pbot}->{registry}->get_value('irc', 'botnick') . " $input";
  }
  return $self->{pbot}->{interpreter}->process_line($from, $self->{pbot}->{registry}->get_value('irc', 'botnick'), "stdin", "pbot", $text);
}

1;
