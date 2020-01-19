# File: Commands.pm
# Author: pragma_
#
# Purpose: Derives from Registerable class to provide functionality to
#          register subroutines, along with a command name and admin level.
#          Registered items will then be executed if their command name matches
#          a name provided via input.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Commands;

use warnings;
use strict;

use feature 'unicode_strings';

use base 'PBot::Registerable';

use Carp ();
use PBot::HashObject;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->SUPER::initialize(%conf);
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{metadata} = PBot::HashObject->new(pbot => $self->{pbot}, name => 'Commands', filename => $conf{filename});
  $self->load_metadata;

  $self->register(sub { $self->set(@_);   },  "cmdset",   90);
  $self->register(sub { $self->unset(@_); },  "cmdunset", 90);
}

sub register {
  my ($self, $subref, $name, $level) = @_;

  if (not defined $subref or not defined $name or not defined $level) {
    Carp::croak("Missing parameters to Commands::register");
  }

  my $ref = $self->SUPER::register($subref);
  $ref->{name} = lc $name;
  $ref->{level} = $level;

  if (not $self->{metadata}->exists($name)) {
    $self->{metadata}->add($name, { level => $level, help => '' }, 1);
  }

  return $ref;
}

sub unregister {
  my ($self, $name) = @_;
  Carp::croak("Missing name parameter to Commands::unregister") if not defined $name;
  $name = lc $name;
  @{ $self->{handlers} } = grep { $_->{name} ne $name } @{ $self->{handlers} };
}

sub exists {
  my ($self, $keyword) = @_;
  $keyword = lc $keyword;
  foreach my $ref (@{ $self->{handlers} }) {
    return 1 if $ref->{name} eq $keyword;
  }
  return 0;
}

sub interpreter {
  my ($self, $stuff) = @_;
  my $result;

  if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
    use Data::Dumper;
    $Data::Dumper::Sortkeys  = 1;
    $self->{pbot}->{logger}->log("Commands::interpreter\n");
    $self->{pbot}->{logger}->log(Dumper $stuff);
  }

  my $from = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $stuff->{from};
  my ($admin_channel) = $stuff->{arguments} =~ m/\B(#[^ ]+)/; # assume first channel-like argument
  $admin_channel = $from if not defined $admin_channel;
  my $admin = $self->{pbot}->{admins}->loggedin($admin_channel, "$stuff->{nick}!$stuff->{user}\@$stuff->{host}");
  my $admin_level = defined $admin ? $admin->{level} : 0;
  my $keyword = lc $stuff->{keyword};

  if (exists $stuff->{'effective-level'}) {
    $self->{pbot}->{logger}->log("override level to $stuff->{'effective-level'}\n");
    $admin_level = $stuff->{'effective-level'};
  }

  foreach my $ref (@{ $self->{handlers} }) {
    if ($ref->{name} eq $keyword) {
      my $cmd_level = $self->get_meta($keyword, 'level') // $ref->{level};
      if ($admin_level >= $cmd_level) {
        $stuff->{no_nickoverride} = 1;
        my $result = &{ $ref->{subref} }($stuff->{from}, $stuff->{nick}, $stuff->{user}, $stuff->{host}, $stuff->{arguments}, $stuff);
        if ($stuff->{referenced}) {
          return undef if $result =~ m/(?:usage:|no results)/i;
        }
        return $result;
      } else {
        return undef if $stuff->{referenced};
        if ($admin_level == 0) {
          return "/msg $stuff->{nick} You must login to use this command.";
        } else {
          return "/msg $stuff->{nick} You are not authorized to use this command.";
        }
      }
    }
  }

  return undef;
}

sub set {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($command, $key, $value) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);
  return "Usage: cmdset <command> [key [value]]" if not defined $command;
  return $self->{metadata}->set($command, $key, $value);
}

sub unset {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($command, $key) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);
  return "Usage: cmdunset <command> <key>" if not defined $command or not defined $key;
  return $self->{metadata}->unset($command, $key);
}

sub get_meta {
  my ($self, $command, $key) = @_;
  $command = lc $command;
  return undef if not exists $self->{metadata}->{hash}->{$command};
  return $self->{metadata}->{hash}->{$command}->{$key};
}

sub load_metadata {
  my ($self) = @_;
  $self->{metadata}->load;
}

sub save_metadata {
  my ($self) = @_;
  $self->{metadata}->save;
}

1;
