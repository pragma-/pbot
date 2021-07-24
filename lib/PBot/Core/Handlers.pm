# File: Handlers.pm
#
# Purpose: Loads handlers in the Handlers directory.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Utils::LoadModules qw/load_modules/;

sub initialize {
    my ($self, %conf) = @_;

    # register all the handlers in the Handlers directory
    $self->register_handlers(%conf);
}

# registers all the handler files in the Handlers directory

sub register_handlers {
    my ($self, %conf) = @_;

    $self->{pbot}->{logger}->log("Registering handlers:\n");
    load_modules($self, 'PBot::Core::Handlers');
}

1;
