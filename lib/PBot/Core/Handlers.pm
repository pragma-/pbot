# File: Handlers.pm
#
# Purpose: Loads handlers in the Handlers directory.

# SPDX-FileCopyrightText: 2001-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers;
use parent 'PBot::Core::Class';

use PBot::Imports;
use PBot::Core::Utils::LoadModules qw/load_modules/;

sub initialize {
    my ($self, %conf) = @_;
    $self->load_handlers(%conf);
}

sub load_handlers {
    my ($self, %conf) = @_;
    $self->{pbot}->{logger}->log("Loading handlers:\n");
    load_modules($self, 'PBot::Core::Handlers');
}

1;
