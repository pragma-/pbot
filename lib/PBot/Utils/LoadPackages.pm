# File: LoadPackages.pm
#
# Purpose: Loads all Perl package files in a given directory.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Utils::LoadPackages;

use PBot::Imports;

use Cwd;

# export load_packages subroutine
require Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/load_packages/;

sub load_packages {
    my ($self, $directory) = @_;

    use FindBin qw/$RealBin/;

    my $cwd = getcwd;

    chdir "$RealBin/../lib/PBot/Core";

    my @packages = glob "$directory/*.pm";

    chdir $cwd;

    foreach my $package (sort @packages) {
        $package = "PBot/Core/$package";

        my $class = $package;
        $class =~ s/\//::/g;
        $class =~ s/\.pm$//;

        my ($name) = $class =~ /.*::(.*)$/;

        $self->{pbot}->{logger}->log("  $name\n");

        $self->{pbot}->{refresher}->{refresher}->refresh_module($package);

        eval {
            require "$package";
            $self->{packages}->{$name} = $class->new(pbot => $self->{pbot});
            $self->{pbot}->{refresher}->{refresher}->update_cache($package);
        };

        if (my $exception = $@) {
            $self->{pbot}->{logger}->log("Error loading $package: $exception");
            exit;
        }
    }
}

1;
