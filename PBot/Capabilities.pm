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

sub capcmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my $command = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
  my $result;
  given ($command) {
    when ('list') {
      my $cap = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      if (defined $cap) {
        $cap = lc $cap;
        return "No such capability $cap." if not exists $self->{caps}->{hash}->{$cap};
        return "Capability $cap has no sub-capabilities." if keys %{$self->{caps}->{hash}->{$cap}} == 1;

        $result = "Sub-capabilities for $cap: ";
        $result .= join(', ', grep { $_ ne '_name' } sort keys %{$self->{caps}->{hash}->{$cap}});
      } else {
        return "No capabilities defined." if keys(%{$self->{caps}->{hash}}) == 0;
        $result = "Capabilities: ";
        my @caps;

        # first list all capabilities that have sub-capabilities (i.e. grouped capabilities)
        foreach my $cap (sort keys %{$self->{caps}->{hash}}) {
          my $count = keys(%{$self->{caps}->{hash}->{$cap}}) - 1;
          push @caps, "$cap [$count]" if $count;
        }

        # then list stand-alone capabilities
        foreach my $cap (sort keys %{$self->{caps}->{hash}}) {
          next if keys(%{$self->{caps}->{hash}->{$cap}}) > 1;
          push @caps, $cap;
        }

        $result .= join ', ', @caps;
      }
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
