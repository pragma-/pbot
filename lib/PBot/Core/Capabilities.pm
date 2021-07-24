# File: Capabilites.pm
#
# Purpose: Fine-grained user permissions.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Capabilities;
use parent 'PBot::Core::Class';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;

    # capabilities file
    my $filename = $conf{filename} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/capabilities';

    # capabilities hash table
    $self->{caps} = PBot::Storage::HashObject->new(
        pbot     => $self->{pbot},
        name     => 'Capabilities',
        filename => $filename,
    );

    # load capabilities
    $self->{caps}->load;

    # add some capabilities used in this file
    $self->add('can-modify-capabilities',  undef, 1);
    $self->add('can-group-capabilities',   undef, 1);

    # add some misc capabilities
    $self->add('is-whitelisted', undef, 1);
}

sub has {
    my ($self, $cap, $subcap, $depth) = @_;
    my $cap_data = $self->{caps}->get_data($cap);

    return 0 if not defined $cap_data;

    if ($cap eq $subcap) {
        return 0 if exists $cap_data->{$subcap} and not $cap_data->{$subcap};
        return 1;
    }

    $depth //= 10;  # set depth to 10 if it's not defined

    if (--$depth <= 0) {
        $self->{pbot}->{logger}->log("Max recursion reached for PBot::Core::Capabilities->has($cap, $subcap)\n");
        return 0;
    }

    foreach my $c ($self->{caps}->get_keys($cap)) {
        return 1 if $c eq $subcap and $cap_data->{$c};
        return 1 if $self->has($c, $subcap, $depth);
    }

    return 0;
}

sub userhas {
    my ($self, $user, $cap) = @_;

    return 0 if not defined $user;
    return 1 if $user->{$cap};

    foreach my $key (keys %$user) {
        next     if $key eq '_name';
        next     if not $user->{$key};
        return 1 if $self->has($key, $cap);
    }

    return 0;
}

sub exists {
    my ($self, $cap) = @_;

    $cap = lc $cap;

    foreach my $c ($self->{caps}->get_keys) {
        return 1 if $c eq $cap;

        foreach my $sub_cap ($self->{caps}->get_keys($c)) {
            return 1 if $sub_cap eq $cap;
        }
    }

    return 0;
}

sub add {
    my ($self, $cap, $subcap, $dontsave) = @_;

    $cap = lc $cap;

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
        foreach my $c ($self->{caps}->get_keys) {
            foreach my $sub_cap ($self->{caps}->get_keys($c)) {
                $self->{caps}->remove($c, $sub_cap, 1) if $sub_cap eq $cap;
            }
            $self->{caps}->remove($c, undef, 1) if $c eq $cap;
        }
    } else {
        $self->{caps}->remove($cap, $subcap, 1) if $self->{caps}->exists($cap);
    }

    $self->{caps}->save;
}

sub rebuild_botowner_capabilities {
    my ($self) = @_;

    $self->{caps}->remove('botowner', undef, 1);

    foreach my $cap ($self->{caps}->get_keys) {
        $self->add('botowner', $cap, 1);
    }
}

sub list {
    my ($self, $capability) = @_;

    if (defined $capability and not $self->{caps}->exists($capability)) {
        return "No such capability $capability.";
    }

    my @caps;
    my @groups;
    my @standalones;
    my $result;

    if (not defined $capability) {
        @caps   = sort $self->{caps}->get_keys;
        $result = 'Capabilities: ';
    } else {
        @caps = sort $self->{caps}->get_keys($capability);

        if (not @caps) {
            return "Capability $capability has no grouped capabilities."
        }

        $result = "Grouped capabilities for $capability: ";
    }

    # first list all capabilities that have sub-capabilities (i.e. grouped capabilities)
    # then list stand-alone capabilities
    foreach my $cap (@caps) {
        my $count = $self->{caps}->get_keys($cap);

        if ($count > 0) {
            push @groups, "$cap ($count cap" . ($count == 1 ? '' : 's') . ")";
        } else {
            push @standalones, $cap;
        }
    }

    $result .= join ', ', @groups, @standalones;

    return $result;
}

1;
