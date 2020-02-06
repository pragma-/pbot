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
  $self->add('can-modify-capabilities',  undef, 1);
  $self->add('can-group-capabilities',   undef, 1);
  $self->add('can-ungroup-capabilities', undef, 1);

  # add capabilites to admin capabilities group
  $self->add('admin', 'chanop',        1); # add chanop capabilities group to admin group -- see ChanOpCommands.md
  $self->add('admin', 'can-useradd',   1);
  $self->add('admin', 'can-userdel',   1);
  $self->add('admin', 'can-userset',   1);
  $self->add('admin', 'can-userunset', 1);
  $self->add('admin', 'can-mode',      1);
  $self->add('admin', 'can-mode-any',  1);
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

    if (keys %{$self->{caps}->{hash}->{$cap}} == 1) {
      delete $self->{caps}->{hash}->{$cap};
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
  my @groups;
  my @standalones;
  my $result;

  if (not defined $capability) {
    @caps = sort keys %{$self->{caps}->{hash}};
    $result = 'Capabilities: ';
  } else {
    @caps = sort keys %{$self->{caps}->{hash}->{$capability}};
    return "Capability $capability has no grouped capabilities." if not @caps or @caps == 1;
    $result = "Grouped capabilities for $capability: ";
  }

  # first list all capabilities that have sub-capabilities (i.e. grouped capabilities)
  # then list stand-alone capabilities
  foreach my $cap (@caps) {
    next if $cap eq '_name';
    my $count = keys(%{$self->{caps}->{hash}->{$cap}}) - 1;
    if ($count > 0) {
      push @groups, "$cap ($count cap" . ($count == 1 ? '' : 's') . ")" if $count;
    } else {
      push @standalones, $cap;
    }
  }
  $result .= join ', ', @groups, @standalones;
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
            push @groups, "$key ($count cap" . ($count == 1 ? '' : 's') . ")";
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

    when ('group') {
      my $cap    = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      my $subcap = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      return "Usage: cap group <existing or new capability> <existing capability>" if not defined $cap or not defined $subcap;
      return "No such capability $subcap." if not $self->exists($subcap);
      return "You cannot group a capability with itself." if lc $cap eq lc $subcap;

      my $u = $self->{pbot}->{users}->loggedin($from, "$nick!$user\@$host");
      return "You must be logged into your user account to group capabilities together." if not defined $u;
      return "You must have the can-group-capabilities capability to group capabilities together." if not $self->userhas($u, 'can-group-capabilities');

      $self->add($cap, $subcap);
      return "Capability $subcap added to the $cap capability group.";
    }

    when ('ungroup') {
      my $cap    = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      my $subcap = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
      return "Usage: cap ungroup <existing capability group> <grouped capability>" if not defined $cap or not defined $subcap;
      return "No such capability $cap." if not $self->exists($cap);
      return "No such capability $subcap." if not $self->exists($subcap);

      my $u = $self->{pbot}->{users}->loggedin($from, "$nick!$user\@$host");
      return "You must be logged into your user account to remove capabilities from groups." if not defined $u;
      return "You must have the can-ungroup-capabilities capability to remove capabilities from groups." if not $self->userhas($u, 'can-ungroup-capabilities');

      return "Capability $subcap does not belong to the $cap capability group." if not $self->has($cap, $subcap);
      $self->remove($cap, $subcap);
      return "Capability $subcap removed from the $cap capability group.";
    }

    default {
      $result = "Usage: cap list [capability] | cap group <existing or new capability group> <existing capability> | cap ungroup <existing capability group> <grouped capability> | cap userhas <user> [capability]";
    }
  }
  return $result;
}

1;
