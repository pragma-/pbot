# File: Registry.pm
# Author: pragma_
#
# Purpose: Provides a centralized registry of configuration settings that can
# easily be examined and updated via set/unset commands without restarting.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Registry;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use Time::HiRes qw(gettimeofday);
use PBot::RegistryCommands;

sub initialize {
    my ($self, %conf) = @_;
    my $filename = $conf{filename} // Carp::croak("Missing filename reference in " . __FILE__);
    $self->{registry} = PBot::DualIndexHashObject->new(name => 'Registry', filename => $filename, pbot => $self->{pbot});
    $self->{triggers} = {};
    $self->{pbot}->{atexit}->register(sub { $self->save; return; });
    PBot::RegistryCommands->new(pbot => $self->{pbot});
}

sub load {
    my $self = shift;
    $self->{registry}->load;
    foreach my $section ($self->{registry}->get_keys) {
        foreach my $item ($self->{registry}->get_keys($section)) { $self->process_trigger($section, $item, $self->{registry}->get_data($section, $item, 'value')); }
    }
}

sub save {
    my $self = shift;
    $self->{registry}->save;
}

sub add_default {
    my ($self, $type, $section, $item, $value) = @_;
    $self->add($type, $section, $item, $value, 1);
}

sub add {
    my $self = shift;
    my ($type, $section, $item, $value, $is_default) = @_;
    $type = lc $type;

    if ($is_default) { return if $self->{registry}->exists($section, $item); }

    if (not $self->{registry}->exists($section, $item)) {
        my $data = {
            value => $value,
            type  => $type,
        };
        $self->{registry}->add($section, $item, $data, 1);
    } else {
        $self->{registry}->set($section, $item, 'value', $value, 1);
        $self->{registry}->set($section, $item, 'type',  $type,  1) unless $self->{registry}->exists($section, $item, 'type');
    }
    $self->process_trigger($section, $item, $value) unless $is_default;
    $self->save unless $is_default;
}

sub remove {
    my $self = shift;
    my ($section, $item) = @_;
    $self->{registry}->remove($section, $item);
}

sub set_default {
    my ($self, $section, $item, $key, $value) = @_;
    $self->set($section, $item, $key, $value, 1);
}

sub set {
    my ($self, $section, $item, $key, $value, $is_default, $dont_save) = @_;
    $key = lc $key if defined $key;

    if ($is_default) { return if $self->{registry}->exists($section, $item, $key); }

    my $oldvalue = $self->get_value($section, $item, 1) if defined $value;
    $oldvalue = '' if not defined $oldvalue;

    my $result = $self->{registry}->set($section, $item, $key, $value, 1);

    if (defined $key and $key eq 'value' and defined $value and $oldvalue ne $value) { $self->process_trigger($section, $item, $value); }

    $self->save if !$dont_save && $result =~ m/set to/ && not $is_default;
    return $result;
}

sub unset {
    my ($self, $section, $item, $key) = @_;
    $key = lc $key;
    return $self->{registry}->unset($section, $item, $key);
}

sub get_value {
    my ($self, $section, $item, $as_text, $stuff) = @_;
    $section = lc $section;
    $item    = lc $item;
    my $key = $item;

    # TODO: use user-metadata for this
    if (defined $stuff and exists $stuff->{nick}) {
        my $stuff_nick = lc $stuff->{nick};
        if ($self->{registry}->exists($section, "$item.nick.$stuff_nick")) { $key = "$item.nick.$stuff_nick"; }
    }

    if ($self->{registry}->exists($section, $key)) {
        if (not $as_text and $self->{registry}->get_data($section, $key, 'type') eq 'array') { return split /\s*,\s*/, $self->{registry}->get_data($section, $key, 'value'); }
        else                                                                                 { return $self->{registry}->get_data($section, $key, 'value'); }
    }
    return undef;
}

sub get_array_value {
    my ($self, $section, $item, $index, $stuff) = @_;
    $section = lc $section;
    $item    = lc $item;
    my $key = $item;

    # TODO: use user-metadata for this
    if (defined $stuff and exists $stuff->{nick}) {
        my $stuff_nick = lc $stuff->{nick};
        if ($self->{registry}->exists($section, "$item.nick.$stuff_nick")) { $key = "$item.nick.$stuff_nick"; }
    }

    if ($self->{registry}->exists($section, $key)) {
        if ($self->{registry}->get_data($section, $key, 'type') eq 'array') {
            my @array = split /\s*,\s*/, $self->{registry}->get_data($section, $key, 'value');
            return $array[$index >= $#array ? $#array : $index];
        } else {
            return $self->{registry}->get_data($section, $key, 'value');
        }
    }
    return undef;
}

sub add_trigger {
    my ($self, $section, $item, $subref) = @_;
    $self->{triggers}->{lc $section}->{lc $item} = $subref;
}

sub process_trigger {
    my $self = shift;
    my ($section, $item) = @_;
    $section = lc $section;
    $item    = lc $item;
    if (exists $self->{triggers}->{$section} and exists $self->{triggers}->{$section}->{$item}) { return &{$self->{triggers}->{$section}->{$item}}(@_); }
    return undef;
}

1;
