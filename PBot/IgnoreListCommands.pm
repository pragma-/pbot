# File: IgnoreListCommands.pm
# Author: pragma_
#
# Purpose: Bot commands for interfacing with ignore list.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::IgnoreListCommands;

use warnings;
use strict;

use feature 'unicode_strings';

use Time::HiRes qw(gettimeofday);
use Time::Duration;
use Carp ();

sub new {
  if (ref($_[1]) eq 'HASH') {
    Carp::croak("Options to IgnoreListCommands should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to IgnoreListCommands");
  }

  $self->{pbot} = $pbot;

  $pbot->{commands}->register(sub { return $self->ignore_user(@_)    },    "ignore",    10);
  $pbot->{commands}->register(sub { return $self->unignore_user(@_)  },    "unignore",  10);
}

sub ignore_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;

  return "Usage: ignore <hostmask> [channel [timeout]]" if not defined $arguments;

  my ($target, $channel, $length) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  if (not defined $target) {
     return "Usage: ignore <hostmask> [channel [timeout]]";
  }

  if ($target =~ /^list$/i) {
    my $text = "Ignored: ";
    my $sep = "";

    foreach my $ignored (sort keys %{ $self->{pbot}->{ignorelist}->{ignore_list} }) {
      foreach my $channel (sort keys %{ ${ $self->{pbot}->{ignorelist}->{ignore_list} }{$ignored} }) {
        $text .= $sep . "$ignored [$channel] " . ($self->{pbot}->{ignorelist}->{ignore_list}->{$ignored}->{$channel} < 0 ? "perm" : duration($self->{pbot}->{ignorelist}->{ignore_list}->{$ignored}->{$channel} - gettimeofday));
        $sep = ";\n";
      }
    }
    return "/msg $nick $text";
  }

  if (not defined $channel) {
    $channel = ".*"; # all channels
  }

  if (not defined $length) {
    $length = -1; # permanently
  } else {
    my $error;
    ($length, $error) = $self->{pbot}->{parsedate}->parsedate($length);
    return $error if defined $error;
  }

  $self->{pbot}->{ignorelist}->add($target, $channel, $length);

  if ($length >= 0) {
    $length = "for " . duration($length);
  } else {
    $length = "permanently";
  }

  $self->{pbot}->{logger}->log("$nick added [$target][$channel] to ignore list $length\n");
  return "/msg $nick [$target][$channel] added to ignore list $length";
}

sub unignore_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $target) {
    return "Usage: unignore <hostmask> [channel]";
  }

  if (not defined $channel) {
    $channel = ".*";
  }

  if (exists $self->{pbot}->{ignorelist}->{ignore_list}->{$target} and not exists $self->{pbot}->{ignorelist}->{ignore_list}->{$target}->{$channel}) {
    $self->{pbot}->{logger}->log("$nick attempt to remove nonexistent [$target][$channel] from ignore list\n");
    return "/msg $nick [$target][$channel] not found in ignore list (use `ignore list` to list ignores)";
  }

  $self->{pbot}->{ignorelist}->remove($target, $channel);
  $self->{pbot}->{logger}->log("$nick removed [$target][$channel] from ignore list\n");
  return "/msg $nick [$target][$channel] unignored";
}

1;
