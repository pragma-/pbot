# File: Refresher.pm
#
# Purpose: Refreshes/reloads module subroutines. Does not refresh/reload
# module member data, only subroutines. TODO: reinitialize modules in order
# to refresh member data too.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Refresher;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Module::Refresh;

sub initialize {
    my ($self, %conf) = @_;

    $self->{refresher} = Module::Refresh->new;
}

1;
