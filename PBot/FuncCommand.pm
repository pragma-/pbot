
# File: FuncCommand.pm
# Author: pragma_
#
# Purpose: Special `func` command that executes built-in functions with
# optional arguments. Usage: func <identifier> [arguments].
#
# Intended usage is with command-substitution (&{}). For example:
#
# factadd img /call echo https://google.com/search?q=&{func urlencode $args}&tbm=isch
#
# The above would invoke the function 'urlencode' on $args and then replace
# the command-substitution with the result, creating a simple Google Image
# Search factoid command.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::FuncCommand;

use warnings;
use strict;

use feature 'unicode_strings';

use Carp ();

sub new {
  if (ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to FactoidCommands");

  $self->{pbot}->{commands}->register(sub { return $self->do_func(@_) }, 'func', 0);

  $self->init_funcs;
}

sub init_funcs {
  my ($self) = @_;

  $self->{funcs} = {
    help => {
      desc   => 'provides help about a func',
      usage  => 'help [func]',
      subref => sub { $self->func_help(@_) }
    },
    list => {
      desc   => 'lists available funcs',
      usage  => 'list [regex]',
      subref => sub { $self->func_list(@_) }
    },
    uri_escape => {
      desc   => 'percent-encode unsafe URI characters',
      usage  => 'uri_escape <text>',
      subref => sub { $self->func_uri_escape(@_) }
    },
    sed => {
      desc   => 'a sed-like stream editor',
      usage  => 'sed s/<regex>/<replacement>/[Pig]; P preserve case; i ignore case; g replace all',
      subref => sub { $self->func_sed(@_) }
    },
  };
}

use URI::Escape qw/uri_escape/;

sub func_uri_escape {
  my $self = shift;
  my $text = "@_";
  return uri_escape($text);
}

sub func_help {
  my ($self, $func) = @_;

  if (not exists $self->{funcs}->{$func}) {
    return "No such func '$func'.";
  }

  return "$func: $self->{funcs}->{$func}->{desc}; usage: $self->{funcs}->{$func}->{usage}";
}

sub func_list {
  my ($self, $regex) = @_;

  $regex = '.*' if not defined $regex;

  my $result = eval {
    my $text = '';

    foreach my $func (sort keys %{$self->{funcs}}) {
      if ($func =~ m/$regex/i) {
        $text .=  "$func: $self->{funcs}->{$func}->{desc}.\n";
      }
    }

    if (not length $text) {
      if ($regex eq '.*') {
        $text = "No funcs yet.";
      } else {
        $text = "No matching func.";
      }
    }

    return $text;
  };

  if ($@) {
    my $error = $@;
    $error =~ s/at PBot.FuncCommand.*$//;
    return "Error: $error\n";
  }

  return $result;
}

# near-verbatim insertion of krok's `sed` factoid
no warnings;
sub func_sed {
  my $self = shift;
  my $text = "@_";

  if ($text =~ /^s(.)(.*?)(?<!\\)\1(.*?)(?<!\\)\1(\S*)\s+(.*)/p) {
    my ($a, $r, $g, $m, $t) = ($5,"'\"$3\"'", index($4,"g") != -1, $4, $2);

    if ($m=~/P/) {
      $r =~ s/^'"(.*)"'$/$1/;
      $m=~s/P//g;

      if($g) {
        $a =~ s|(?$m)($t)|$1=~/^[A-Z][^A-Z]/?ucfirst$r:($1=~/^[A-Z]+$/?uc$r:$r)|gie;
      } else {
        $a =~ s|(?$m)($t)|$1=~/^[A-Z][^A-Z]/?ucfirst$r:($1=~/^[A-Z]+$/?uc$r:$r)|ie;
      }
    } else {
      if ($g) {
        $a =~ s/(?$m)$t/$r/geee;
      } else {
        $a=~s/(?$m)$t/$r/eee;
      }
    }
    return $a;
  } else {
    return "sed: syntax error";
  }
}
use warnings;

sub do_func {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my $func = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});

  if (not defined $func) {
    return "Usage: func <keyword> [arguments]";
  }

  if (not exists $self->{funcs}->{$func}) {
    return "[No such func '$func']";
  }

  my @params;
  while (my $param = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist})) {
    push @params, $param;
  }

  return $self->{funcs}->{$func}->{subref}->(@params);
}

1;
