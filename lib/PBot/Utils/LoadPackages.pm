# File: LoadPackages.pm
#
# Purpose: Loads all Perl package files in a given directory.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Utils::LoadPackages;

use PBot::Imports;

use File::Basename;

# export load_packages subroutine
require Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/load_packages/;

sub load_packages {
    my ($self, $base) = @_;

    my $base_path = join '/', split '::', $base;

    foreach my $inc_path (@INC) {
        if (-d "$inc_path/$base_path") {
            my @packages = glob "$inc_path/$base_path/*.pm";

            foreach my $package (sort @packages) {
                $self->{pbot}->{refresher}->{refresher}->refresh_module($package);

                my $name = basename $package;
                $name =~ s/\.pm$//;

                $self->{pbot}->{logger}->log("  $name\n");

                eval {
                    require "$package";

                    my $class = $base . '::' . $name;
                    $self->{packages}->{$name} = $class->new(pbot => $self->{pbot});
                    $self->{pbot}->{refresher}->{refresher}->update_cache($package);
                };

                # error loading a package
                if (my $exception = $@) {
                    $self->{pbot}->{logger}->log("Error loading $package: $exception");
                    exit;
                }
            }
            # packages loaded successfully
            return 1;
        }
    }
    # no packages found
    return 0;
}

1;
