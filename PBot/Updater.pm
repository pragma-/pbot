# File: Updater.pm
# Author: pragma_
#
# Purpose: Updates data/configration files to new locations/formats based
# on versioning information. Ensures data/configuration files are in the
# proper location and using the latest data structure.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Updater;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use File::Basename;

sub initialize {
    my ($self, %conf) = @_;
    $self->{data_dir}   = $conf{data_dir};
    $self->{update_dir} = $conf{update_dir};
}

sub update {
    my ($self) = @_;

    $self->{pbot}->{logger}->log("Checking if update needed...\n");

    my $current_version        = $self->get_current_version;
    my $last_update_version = $self->get_last_update_version;

    $self->{pbot}->{logger}->log("Current version: $current_version; last update version: $last_update_version\n");

    if ($last_update_version >= $current_version) {
        $self->{pbot}->{logger}->log("No update necessary.\n");
        return $self->put_last_update_version($current_version);
    }

    my @updates = $self->get_available_updates($last_update_version);

    if (not @updates ) {
        $self->{pbot}->{logger}->log("No updates available.\n");
        return $self->put_last_update_version($current_version);
    }

    foreach my $update (@updates) {
        $self->{pbot}->{logger}->log("Executing update script: $update\n");
        my $output = `$update $self->{data_dir}`;
        my $exit = $? >> 8;
        $self->{pbot}->{logger}->log("Script completed. Exit $exit. Output: $output");
        return $exit if $exit != 0;
    }

    return $self->put_last_update_version($current_version);
}

sub get_available_updates {
    my ($self, $last_update_version) = @_;
    my @updates = sort glob "$self->{update_dir}/*.pl";
    return grep { my ($version) = split /_/, basename $_; $version > $last_update_version } @updates;
}

sub get_current_version {
    return PBot::VERSION::BUILD_REVISION;
}

sub get_last_update_version {
    my ($self) = @_;
    open(my $fh, '<', "$self->{data_dir}/last_update") or return 0;
    chomp(my $last_update = <$fh>);
    close $fh;
    return $last_update;
}

sub put_last_update_version {
    my ($self, $version) = @_;
    if (open(my $fh, '>', "$self->{data_dir}/last_update")) {
        print $fh "$version\n";
        close $fh;
        return 0;
    } else {
        $self->{pbot}->{logger}->log("Could not save last update version to $self->{data_dir}/last_update: $!\n");
        return 1;
    }
}

1;
