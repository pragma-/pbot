# File: FuncBuiltins.pm
# Author: pragma-
#
# Purpose: Registers the basic built-in Functions

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::FuncBuiltins;
use parent 'Plugins::Plugin';

use warnings; use strict;
use feature 'unicode_strings';

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot}->{functions}->register(
    'title',
    {
      desc   => 'Title-cases text',
      usage  => 'title <text>',
      subref => sub { $self->func_title(@_) }
    }
  );
  $self->{pbot}->{functions}->register(
    'ucfirst',
    {
      desc   => 'Uppercases first character',
      usage  => 'ucfirst <text>',
      subref => sub { $self->func_ucfirst(@_) }
    }
  );
  $self->{pbot}->{functions}->register(
    'uc',
    {
      desc   => 'Uppercases all characters',
      usage  => 'uc <text>',
      subref => sub { $self->func_uc(@_) }
    }
  );
  $self->{pbot}->{functions}->register(
    'lc',
    {
      desc   => 'Lowercases all characters',
      usage  => 'lc <text>',
      subref => sub { $self->func_lc(@_) }
    }
  );
  $self->{pbot}->{functions}->register(
    'unquote',
    {
      desc   => 'removes unescaped surrounding quotes and strips escapes from escaped quotes',
      usage  => 'unquote <text>',
      subref => sub { $self->func_unquote(@_) }
    }
  );
}

sub unload {
  my $self = shift;
  $self->{pbot}->{functions}->unregister('title');
  $self->{pbot}->{functions}->unregister('ucfirst');
  $self->{pbot}->{functions}->unregister('uc');
  $self->{pbot}->{functions}->unregister('lc');
  $self->{pbot}->{functions}->unregister('unquote');
}

sub func_unquote {
  my $self = shift;
  my $text = "@_";
  $text =~ s/^"(.*?)(?<!\\)"$/$1/ || $text =~ s/^'(.*?)(?<!\\)'$/$1/;
  $text =~ s/(?<!\\)\\'/'/g;
  $text =~ s/(?<!\\)\\"/"/g;
  return $text;
}

sub func_title {
  my $self = shift;
  my $text = "@_";
  $text = ucfirst lc $text;
  $text =~ s/ (\w)/' ' . uc $1/ge;
  return $text;
}

sub func_ucfirst {
  my $self = shift;
  my $text = "@_";
  return ucfirst $text;
}

sub func_uc {
  my $self = shift;
  my $text = "@_";
  return uc $text;
}

sub func_lc {
  my $self = shift;
  my $text = "@_";
  return lc $text;
}

1;
