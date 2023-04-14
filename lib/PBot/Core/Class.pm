# File: Class.pm
#
# Purpose: Base class for PBot classes. This prevents each PBot class from
# needing to define the new() constructor and other boilerplate.
#
# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Class;

use PBot::Imports;

my %import_opts;

sub import($package, %opts) {
    if (%opts) {
        # set import options for package
        $import_opts{$package} = \%opts;
    }
}

sub new($class, %args) {
    # ensure class was passed a PBot instance
    if (not exists $args{pbot}) {
        my ($package, $filename, $line) = caller(0);
        my (undef, undef, undef, $subroutine) = caller(1);
        Carp::croak("Missing pbot reference to $class, created by $subroutine at $filename:$line");
    }

    # create class instance
    my $self = bless { pbot => $args{pbot} }, $class;

    # log class initialization unless quieted
    unless (exists $import_opts{$class} and $import_opts{$class}{quiet}) {
        $self->{pbot}->{logger}->log("Initializing $class\n")
    }

    $self->initialize(%args);

    return $self;
}

sub initialize {
    # ensure class has an initialize() subroutine
    my ($package, $filename, $line) = caller(0);
    my (undef, undef, undef, $subroutine) = caller(1);
    Carp::croak("Missing initialize subroutine in $subroutine at $filename:$line");
}

1;
