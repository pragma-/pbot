
# File: Functions.pm
# Author: pragma_
#
# Purpose: Special `func` command that executes built-in functions with
# optional arguments. Usage: func <identifier> [arguments].
#
# Intended usage is with command-substitution (&{}) or pipes (|{}).
#
# For example:
#
# factadd img /call echo https://google.com/search?q=&{func uri_escape $args}&tbm=isch
#
# The above would invoke the function 'uri_escape' on $args and then replace
# the command-substitution with the result, thus escaping $args to be safely
# used in the URL of this simple Google Image Search factoid command.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Functions;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot}->{commands}->register(sub { $self->do_func(@_) }, 'func', 0);

  $self->register(
    'help',
    {
      desc   => 'provides help about a func',
      usage  => 'help [func]',
      subref => sub { $self->func_help(@_) }
    }
  );

  $self->register(
    'list',
    {
      desc   => 'lists available funcs',
      usage  => 'list [regex]',
      subref => sub { $self->func_list(@_) }
    }
  );
}

sub register {
  my ($self, $func, $data) = @_;
  $self->{funcs}->{$func} = $data;
}

sub unregister {
  my ($self, $func) = @_;
  delete $self->{funcs}->{$func};
}

sub do_func {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my $func = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
  return "Usage: func <keyword> [arguments]; see also: func help" if not defined $func;
  return "[No such func '$func']" if not exists $self->{funcs}->{$func};

  my @params;
  while (my $param = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist})) {
    push @params, $param;
  }

  my $result = $self->{funcs}->{$func}->{subref}->(@params);
  $result =~ s/\x1/1/g;
  return $result;
}

sub func_help {
  my ($self, $func) = @_;
  return "func: invoke built-in functions; usage: func <keyword> [arguments]; to list available functions: func list [regex]" if not length $func;
  return "No such func '$func'." if not exists $self->{funcs}->{$func};
  return "$func: $self->{funcs}->{$func}->{desc}; usage: $self->{funcs}->{$func}->{usage}";
}

sub func_list {
  my ($self, $regex) = @_;
  $regex = '.*' if not defined $regex;
  my $result = eval {
    my $text = '';
    foreach my $func (sort keys %{$self->{funcs}}) {
      if ($func =~ m/$regex/i or $self->{funcs}->{$func}->{desc} =~ m/$regex/i) {
        $text .=  "$func, ";
      }
    }

    $text =~ s/,\s+$//;
    if (not length $text) {
      if ($regex eq '.*') {
        $text = "No funcs yet.";
      } else {
        $text = "No matching func.";
      }
    }
    return "Available funcs: $text; see also: func help <keyword>";
  };

  if ($@) {
    my $error = $@;
    $error =~ s/at PBot.Functions.*$//;
    return "Error: $error\n";
  }
  return $result;
}

1;
