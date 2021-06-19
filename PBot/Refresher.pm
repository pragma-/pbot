# File: Refresher.pm
#
# Purpose: Refreshes/reloads module subroutines. Does not refresh/reload
# module member data, only subroutines. TODO: reinitialize modules in order
# to refresh member data too.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Refresher;
use parent 'PBot::Class';

use PBot::Imports;

use Module::Refresh;
use File::Basename;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->register(sub { $self->cmd_refresh(@_) }, "refresh", 1);

    $self->{refresher} = Module::Refresh->new;
}

sub cmd_refresh {
    my ($self, $context) = @_;

    my $last_update = $self->{pbot}->{updater}->get_last_update_version;
    my @updates     = $self->{pbot}->{updater}->get_available_updates($last_update);

    if (@updates) {
        return "Update available; cannot refresh. Please restart PBot to begin update of " . join(', ', map { basename $_ } @updates);
    }

    my $refresh_error;
    local $SIG{__WARN__} = sub {
        my $warning = shift;
        warn $warning and return if $warning =~ /Can't undef active/;
        warn $warning and return if $warning =~ /subroutine .* redefined/i;
        $refresh_error = $warning;
        $refresh_error =~ s/\s+Compilation failed in require at \/usr.*//;
        $refresh_error =~ s/in \@INC.*/in \@INC/;
        $self->{pbot}->{logger}->log("Error refreshing: $refresh_error\n");
    };

    my $result = eval {
        if (not $context->{arguments}) {
            $self->{pbot}->{logger}->log("Refreshing all modified modules\n");
            $self->{refresher}->refresh;
            return "Error refreshing: $refresh_error" if defined $refresh_error;
            return "Refreshed all modified modules.\n";
        } else {
            $self->{pbot}->{logger}->log("Refreshing module $context->{arguments}\n");
            $self->{refresher}->refresh_module($context->{arguments});
            return "Error refreshing: $refresh_error" if defined $refresh_error;
            $self->{pbot}->{logger}->log("Refreshed module.\n");
            return "Refreshed module.\n";
        }
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error refreshing: $@\n");
        return $@;
    }

    return $result;
}

1;
