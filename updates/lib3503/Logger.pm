# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package lib3503::Logger;

use warnings; use strict;
use feature 'unicode_strings';

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    Carp::croak("Missing pbot reference to " . __FILE__) unless exists $conf{pbot};
    $self->{pbot} = $conf{pbot};
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;
    return $self;
}

sub log {
    my ($self, $text) = @_;
    print $text;
}

1;
