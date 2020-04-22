# File: PBot.pm
# Author: pragma_
#
# Purpose: IRC Bot (3rd generation)

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package lib3503::PBot;

use strict; use warnings;
use feature 'unicode_strings';

# unbuffer stdout
STDOUT->autoflush(1);

use Carp ();
use lib3503::Logger;

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;
    $self->{logger} = lib3503::Logger->new(pbot => $self);
}

1;
