# File: Migration.pm
# Author: pragma_
#
# Purpose: Migrates data/configration files to new locations/formats based
# on versioning information. Ensures data/configuration files are in the
# proper location and using the latest data structure.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Migration;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use File::Basename;

sub initialize {
    my ($self, %conf) = @_;
    $self->{data_dir}      = $conf{data_dir};
    $self->{migration_dir} = $conf{migration_dir};
}

sub migrate {
    my ($self) = @_;

    $self->{pbot}->{logger}->log("Checking if migration needed...\n");

    my $current_version        = $self->get_current_version;
    my $last_migration_version = $self->get_last_migration_version;

    $self->{pbot}->{logger}->log("Current version: $current_version; last migration version: $last_migration_version\n");

    if ($last_migration_version >= $current_version) {
        $self->{pbot}->{logger}->log("No migration necessary.\n");
        return 0;
    }

    my @migrations = $self->get_available_migrations($last_migration_version);

    if (not @migrations ) {
        $self->{pbot}->{logger}->log("No migrations available.\n");
        return 0;
    }

    foreach my $migration (@migrations) {
        $self->{pbot}->{logger}->log("Executing migration script: $migration\n");
        my $output = `$migration $self->{data_dir}`;
        my $exit = $? >> 8;
        $self->{pbot}->{logger}->log("Script completed. Exit $exit. Output: $output");
        return $exit if $exit != 0;
    }

    return $self->put_last_migration_version($current_version);
}

sub get_available_migrations {
    my ($self, $last_migration_version) = @_;
    my @migrations = sort glob "$self->{migration_dir}/*";
    return grep { my ($version) = split /_/, basename $_; $version > $last_migration_version ? 1 : 0 } @migrations;
}

sub get_current_version {
    return PBot::VERSION::BUILD_REVISION;
}

sub get_last_migration_version {
    my ($self) = @_;
    open(my $fh, '<', "$self->{data_dir}/last_migration") or return 0;
    chomp(my $last_migration = <$fh>);
    close $fh;
    return $last_migration;
}

sub put_last_migration_version {
    my ($self, $version) = @_;
    if (open(my $fh, '>', "$self->{data_dir}/last_migration")) {
        print $fh "$version\n";
        close $fh;
        return 0;
    } else {
        $self->{pbot}->{logger}->log("Could not save last migration to $self->{data_dir}/last_migration: $!\n");
        return 1;
    }
}

1;
