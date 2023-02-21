# File: Refresher.pm
#
# Purpose: Registers command to refresh PBot's Perl modules.

# SPDX-FileCopyrightText: 2015-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Refresher;

use PBot::Imports;
use parent 'PBot::Core::Class';

use File::Basename;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->register(sub { $self->cmd_refresh(@_) }, "refresh", 1);
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
            $self->{pbot}->{refresher}->{refresher}->refresh;
            return "Error refreshing: $refresh_error" if defined $refresh_error;
            return "Refreshed all modified modules.\n";
        } else {
            $self->{pbot}->{logger}->log("Refreshing module $context->{arguments}\n");
            $self->{pbot}->{refresher}->{refresher}->refresh_module($context->{arguments});
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
