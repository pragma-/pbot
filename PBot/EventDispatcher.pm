# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::EventDispatcher;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';
use utf8;

use IO::Select;

sub initialize {
    my ($self, %conf) = @_;
    $self->{handlers} = {any => []};
}

sub register_handler {
    my ($self, $event_type, $sub, $package_override) = @_;
    my ($package) = caller(0);
    $package = $package_override if defined $package_override;
    my $info = "$package\-\>$event_type";
    $self->{pbot}->{logger}->log("Adding handler: $info\n") if $self->{pbot}->{registry}->get_value('eventdispatcher', 'debug');
    push @{$self->{handlers}->{$event_type}}, [$sub, $info];
}

sub remove_handler {
    my ($self, $event_type, $package_override) = @_;
    my ($package) = caller(0);
    $package = $package_override if defined $package_override;
    my $info = "$package\-\>$event_type";

    if (exists $self->{handlers}->{$event_type}) {
        for (my $i = 0; $i < @{$self->{handlers}->{$event_type}}; $i++) {
            my $ref = @{$self->{handlers}->{$event_type}}[$i];
            if ($info eq $ref->[1]) {
                $self->{pbot}->{logger}->log("Removing handler: $info\n") if $self->{pbot}->{registry}->get_value('eventdispatcher', 'debug');
                splice @{$self->{handlers}->{$event_type}}, $i--, 1;
            }
        }
    }
}

sub dispatch_event {
    my ($self, $event_type, $event_data) = @_;
    my $ret = undef;

    if (exists $self->{handlers}->{$event_type}) {
        for (my $i = 0; $i < @{$self->{handlers}->{$event_type}}; $i++) {
            my $ref = @{$self->{handlers}->{$event_type}}[$i];
            my ($handler, $info) = ($ref->[0], $ref->[1]);
            my $debug = $self->{pbot}->{registry}->get_value('eventdispatcher', 'debug') // 0;
            $self->{pbot}->{logger}->log("Dispatching $event_type to handler $info\n") if $debug > 1;

            eval { $ret = $handler->($event_type, $event_data); };

            if ($@) {
                chomp $@;
                $self->{pbot}->{logger}->log("Error in event handler: $@\n");

                #$self->{pbot}->{logger}->log("Removing handler.\n");
                #splice @{$self->{handlers}->{$event_type}}, $i--, 1;
            }
            return $ret if $ret;
        }
    }

    for (my $i = 0; $i < @{$self->{handlers}->{any}}; $i++) {
        my $ref = @{$self->{handlers}->{any}}[$i];
        my ($handler, $info) = ($ref->[0], $ref->[1]);
        $self->{pbot}->{logger}->log("Dispatching any to handler $info\n") if $self->{pbot}->{registry}->get_value('eventdispatcher', 'debug');

        eval { $ret = $handler->($event_type, $event_data); };

        if ($@) {
            chomp $@;
            $self->{pbot}->{logger}->log("Error in event handler: $@\n");

            #$self->{pbot}->{logger}->log("Removing handler.\n");
            #splice @{$self->{handlers}->{any}}, $i--, 1;
        }
        return $ret if $ret;
    }
    return $ret;
}

1;
