# File: FactoidsSQLite.pm
# Author: pragma_
#
# Purpose: SQLite backend for Factoids; adds factoid-specific functionality
# to DualIndexSQLiteObject parent class.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::FactoidsSQLite;

use parent 'PBot::DualIndexSQLiteObject';

use warnings; use strict;
use feature 'unicode_strings';

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    Carp::croak("Missing pbot reference to " . __FILE__) unless exists $conf{pbot};
    $self->{pbot} = $conf{pbot};
    $self->SUPER::initialize(%conf);
    return $self;
}

sub get_regex_by_channel {
    my ($self, $channel) = @_;

    my $data = eval {
        my $d = [];
        my $sth;
        if (defined $channel) {
            $sth = $self->{dbh}->prepare('SELECT index1, index2, action FROM Stuff WHERE index1 = ? AND type = "regex"');
            $sth->execute($channel);
            push @$d, @{$sth->fetchall_arrayref({})};

            if ($channel ne '.*') {
                $sth->execute('.*');
                push @$d, @{$sth->fetchall_arrayref({})};
            }
        } else {
            $sth = $self->{dbh}->prepare('SELECT index1, index2, action FROM Stuff WHERE type = "regex"');
            $sth->execute;
            push @$d, @{$sth->fetchall_arrayref({})};
        }

        return $d;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error in get_regex_by_channel: $@\n");
        return undef;
    }

    return $data;
}

1;
