# File: LoadModules.pm
#
# Purpose: Loads all Perl modules in a given directory, nonrecursively
# (i.e. at one depth level).

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Utils::LoadModules;

use PBot::Imports;

use File::Basename;

require Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/load_modules/;

sub load_modules {
    my ($self, $base) = @_;

    my $base_path = join '/', split '::', $base;

    foreach my $inc_path (@INC) {
        if (-d "$inc_path/$base_path") {
            my @modules = glob "$inc_path/$base_path/*.pm";

            foreach my $module (sort @modules) {
                $self->{pbot}->{refresher}->{refresher}->refresh_module($module);

                my $name = basename $module;
                $name =~ s/\.pm$//;

                $self->{pbot}->{logger}->log("  $name\n");

                eval {
                    my $class = $base . '::' . $name;
                    require "$module";
                    $class->import(quiet => 1);
                    $self->{modules}->{$name} = $class->new(pbot => $self->{pbot});
                    $self->{pbot}->{refresher}->{refresher}->update_cache($module);
                };

                # error loading a module
                if (my $exception = $@) {
                    $self->{pbot}->{logger}->log("Error loading $module: $exception");
                    exit;
                }
            }
            # modules loaded successfully
            return 1;
        }
    }
    # no module found
    return 0;
}

1;
