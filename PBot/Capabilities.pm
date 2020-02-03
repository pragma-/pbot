# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Capabilities;

# purpose: provides interface to set/remove/modify/query user capabilities.
#
# Examples:
#

use warnings;
use strict;

use feature 'unicode_strings';

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use PBot::HashObject;
use Carp ();

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  my $filename = $conf{filename} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/capabilities';
  $self->{caps} = PBot::HashObject->new(name => 'Capabilities', filename => $filename, pbot => $self->{pbot});
  $self->{caps}->load;
  # 'cap' command registered in PBot.pm because $self->{pbot}->{commands} is not yet loaded.

  # add some basic capabilities
  $self->add('can-modify-capabilities', undef, 1);

  # add admin capabilities group
  $self->add('admin', 'chanop',        1); # add chanop capabilities group -- see ChanOpCommands.md
  $self->add('admin', 'can-useradd',   1);
  $self->add('admin', 'can-userdel',   1);
  $self->add('admin', 'can-userset',   1);
  $self->add('admin', 'can-userunset', 1);
  $self->add('admin', 'can-join',      1);
  $self->add('admin', 'can-part',      1);
}

sub has {
  my ($self, $cap, $subcap, $depth) = @_;
  my $cap_data = $self->{caps}->get_data($cap);
  return 0 if not defined $cap_data;

  $depth //= 2;
  if (--$depth <= 0) {
    $self->{pbot}->{logger}->log("Max recursion reached for PBot::Capabilities->has()\n");
    return 0;
  }

  foreach my $c (keys %{$cap_data}) {
    next if $c eq '_name';
    return 1 if $c eq $subcap;
    return 1 if $self->has($c, $subcap, $depth);
  }
  return 0;
}

sub userhas {
  my ($self, $user, $cap) = @_;
  return 0 if not defined $user;
  return 1 if $user->{$cap};
  foreach my $key (keys %{$user}) {
    next if $key eq '_name';
    return 1 if $self->has($key, $cap, 10);
  }
  return 0;
}

sub exists {
  my ($self, $cap) = @_;
  $cap = lc $cap;
  foreach my $c (keys %{$self->{caps}->{hash}}) {
    next if $c eq '_name';
    return 1 if $c eq $cap;
    foreach my $sub_cap (keys %{$self->{caps}->{hash}->{$c}}) {
      return 1 if $sub_cap eq $cap;
    }
  }
  return 0;
}

sub add {
  my ($self, $cap, $subcap, $dontsave) = @_;

  if (not defined $subcap) {
    if (not $self->{caps}->exists($cap)) {
      $self->{caps}->add($cap, {}, $dontsave);
    }
  } else {
    if ($self->{caps}->exists($cap)) {
      $self->{caps}->set($cap, $subcap, 1, $dontsave);
    } else {
      $self->{caps}->add($cap, { $subcap => 1 }, $dontsave);
    }
  }
}

sub remove {
}

sub rebuild_botowner_capabilities {
  my ($self) = @_;
  $self->{caps}->remove('botowner');
  foreach my $cap (keys %{$self->{caps}->{hash}}) {
    next if $cap eq '_name';
    $self->add('botowner', $cap, 1);
  }
}

sub list {
  my ($self, $capability) = @_;
  $capability = lc $capability;
  return "No such capability $capability." if defined $capability and not exists $self->{caps}->{hash}->{$capability};

  my @caps;
  my @cap_group;
  my @cap_standalone;
  my $result;

  if (not defined $capability) {
    @caps = sort keys %{$self->{caps}->{hash}};
    $result = 'Capabilities: ';
  } else {
    @caps = sort keys %{$self->{caps}->{hash}->{$capability}};
    return "Capability $capability has no sub-capabilities." if @caps == 1;
    $result = "Sub-capabilities for $capability: ";
  }

  # first list all capabilities that have sub-capabilities (i.e. grouped capabilities)
  # then list stand-alone capabilities
  foreach my $cap (@caps) {
    next if $cap eq '_name';
    my $count = keys(%{$self->{caps}->{hash}->{$cap}}) - 1;
    if ($count) {
      push @cap_group, "$cap [$count]" if $count;
    } else {
      push @cap_standalone, $cap;
    }
  }
  $result .= join ', ', @cap_group, @cap_standalone;
  return $result;
}

sub capcmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my $command = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
  my $result;
  given ($command) {
    when ('list') {
      my $cap = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      return $self->list($cap);
    }

    when ('userhas') {
    }

    when ('add') {
    }

    when ('remove') {
    }

    default {
      $result = "Usage: cap list [capability] | cap add <capability> [sub-capability] | cap remove <capability> [sub-capability] | cap userhas <user> <capability>";
    }
  }
  return $result;
}

1;
