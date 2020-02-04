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
  return 1 if $cap eq $subcap and $cap_data->{$subcap};

  $depth //= 10;
  if (--$depth <= 0) {
    $self->{pbot}->{logger}->log("Max recursion reached for PBot::Capabilities->has($cap, $subcap)\n");
    return 0;
  }

  foreach my $c (keys %{$cap_data}) {
    next if $c eq '_name';
    return 1 if $c eq $subcap and $cap_data->{$c};
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
    next if not $user->{$key};
    return 1 if $self->has($key, $cap);
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
  my ($self, $cap, $subcap) = @_;
  $cap = lc $cap;

  if (not defined $subcap) {
    foreach my $c (keys %{$self->{caps}->{hash}}) {
      next if $c eq '_name';
      foreach my $sub_cap (keys %{$self->{caps}->{hash}->{$c}}) {
        delete $self->{caps}->{hash}->{$c}->{$sub_cap} if $sub_cap eq $cap;
      }
      if ($c eq $cap) {
        delete $self->{caps}->{hash}->{$c};
      }
    }
  } else {
    $subcap = lc $subcap;
    if (exists $self->{caps}->{hash}->{$cap}) {
      delete $self->{caps}->{hash}->{$cap}->{$subcap};
    }
  }
  $self->{caps}->save;
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
  $capability = lc $capability if defined $capability;
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
    return "Capability $capability has no sub-capabilities." if not @caps or @caps == 1;
    $result = "Sub-capabilities for $capability: ";
  }

  # first list all capabilities that have sub-capabilities (i.e. grouped capabilities)
  # then list stand-alone capabilities
  foreach my $cap (@caps) {
    next if $cap eq '_name';
    my $count = keys(%{$self->{caps}->{hash}->{$cap}}) - 1;
    if ($count > 0) {
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
      my ($hostmask, $cap) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);
      return "Usage: cap userhas <user> [capability]" if not defined $hostmask;
      $cap = lc $cap if defined $cap;

      my $u = $self->{pbot}->{users}->find_user('.*', $hostmask);
      return "No such user $hostmask." if not defined $u;

      if (defined $cap) {
        return "Try again. No such capability $cap." if not $self->exists($cap);
        if ($self->userhas($u, $cap)) {
          return "Yes. User $u->{name} has capability $cap.";
        } else {
          return "No. User $u->{name} does not have capability $cap.";
        }
      } else {
        my $result = "User $u->{name} has capabilities: ";
        my @groups;
        my @single;
        foreach my $key (sort keys %{$u}) {
          next if $key eq '_name';
          next if not $self->exists($key);
          my $count = keys (%{$self->{caps}->{hash}->{$key}}) - 1;
          if ($count > 0) {
            push @groups, "$key [$count]";
          } else {
            push @single, $key;
          }
        }
        if (@groups or @single) {
          $result .= join ', ', @groups, @single;
        } else {
          $result = "User $u->{name} has no capabilities.";
        }
        return $result;
      }
    }

    when ('add') {
      my $cap    = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      my $subcap = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      return "Usage: cap add <capability> [sub-capability]" if not defined $cap;

      if (not defined $subcap) {
        return "Capability $cap already exists. Did you mean to add a sub-capability to it? Usage: cap add <capability> [sub-capability]" if $self->exists($cap);
        $self->add($cap);
        return "Capability $cap added.";
      } else {
        return "You cannot add a capability to itself." if lc $cap eq lc $subcap;
        return "No such capability $subcap." if not $self->exists($subcap);
        $self->add($cap, $subcap);
        return "Capability $subcap added to $cap.";
      }
    }

    when ('remove') {
      my $cap    = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      my $subcap = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      return "Usage: cap remove <capability> [sub-capability]" if not defined $cap;
      return "No such capability $cap." if not $self->exists($cap);

      if (not defined $subcap) {
        $self->remove($cap);
        return "Capability $cap removed.";
      } else {
        return "Capability $cap does not have a $subcap sub-capability." if not $self->has($cap, $subcap);
        $self->remove($cap, $subcap);
        return "Capability $subcap removed from $cap.";
      }
    }

    default {
      $result = "Usage: cap list [capability] | cap add <capability> [sub-capability] | cap remove <capability> [sub-capability] | cap userhas <user> [capability]";
    }
  }
  return $result;
}

1;
