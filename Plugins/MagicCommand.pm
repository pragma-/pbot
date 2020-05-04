# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# This module is intended to provide a "magic" command that allows
# the bot owner to trigger special arbitrary code (by editing this
# module and refreshing loaded modules before running the magical
# command).

package Plugins::MagicCommand;
use parent 'Plugins::Plugin';

use warnings; use strict;
use feature 'unicode_strings';

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { return $self->cmd_magic(@_) }, "mc", 90);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("mc");
}

sub cmd_magic {
    my ($self, $context) = @_;

    # do something magical!
    return "Did something magical.";
}

1;
