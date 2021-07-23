# File: ProcessManager.pm
#
# Purpose: Registers commands for listing and killing running PBot processes.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::ProcessManager;

use PBot::Imports;
use parent 'PBot::Core::Class';

use Time::Duration qw/concise duration/;
use Time::HiRes qw/gettimeofday/;
use Getopt::Long qw/GetOptionsFromArray/;

sub initialize {
    my ($self, %conf) = @_;

    # process manager bot commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_ps(@_) },   'ps',   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_kill(@_) }, 'kill', 1);

    # give admin capability group the can-kill capability
    $self->{pbot}->{capabilities}->add('admin', 'can-kill', 1);
}

sub cmd_ps {
    my ($self, $context) = @_;

    my $usage = 'Usage: ps [-atu]; -a show all information; -t show running time; -u show user/channel';

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling");

    my ($show_all, $show_user, $show_running_time);

    my @opt_args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);

    GetOptionsFromArray(
        \@opt_args,
        'all|a'  => \$show_all,
        'user|u' => \$show_user,
        'time|t' => \$show_running_time
    );

    return "$getopt_error; $usage" if defined $getopt_error;

    my @processes;

    foreach my $pid (sort keys %{$self->{pbot}->{process_manager}->{processes}}) {
        push @processes, $self->{pbot}->{process_manager}->{processes}->{$pid};
    }

    if (not @processes) {
        return "No running processes.";
    }

    my $result = @processes == 1 ? 'One process: ' : @processes . ' processes: ';

    my @entries;

    foreach my $process (@processes) {
        my $entry = "$process->{pid}: $process->{commands}->[0]";

        if ($show_running_time or $show_all) {
            my $duration = concise duration (gettimeofday - $process->{process_start});
            $entry .= " [$duration]";
        }

        if ($show_user or $show_all) {
            $entry .= " ($process->{nick} in $process->{from})";
        }

        push @entries, $entry;
    }

    $result .= join '; ', @entries;

    return $result;
}

sub cmd_kill {
    my ($self, $context) = @_;

    my $usage = 'Usage: kill [-a] [-t <seconds>] [-s <signal>]  [pids...]; -a kill all processes; -t <seconds> kill processes running longer than <seconds>; -s send <signal> to processes';

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling");

    my ($kill_all, $kill_time, $signal);

    my @opt_args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, preserve_escapes => 1, strip_quotes => 1);

    GetOptionsFromArray(
        \@opt_args,
        'all|a'      => \$kill_all,
        'time|t=i'   => \$kill_time,
        'signal|s=s' => \$signal,
    );

    return "$getopt_error; $usage" if defined $getopt_error;

    if (not $kill_all and not $kill_time and not @opt_args) {
        return "Must specify PIDs to kill unless options -a or -t are provided.";
    }

    if (defined $signal) {
        $signal = uc $signal;
    } else {
        $signal = 'INT';
    }

    my @pids;

    if (defined $kill_all or defined $kill_time) {
        my $now = time;

        foreach my $pid (sort keys %{$self->{pbot}->{process_manager}->{processes}}) {
            my $process = $self->{pbot}->{process_manager}->{processes}->{$pid};
            next if defined $kill_time and $now - $process->{process_start} < $kill_time;
            push @pids, $pid;
        }
    } else {
        foreach my $pid (@opt_args) {
            return "No such pid $pid." if not exists $self->{pbot}->{process_manager}->{processes}->{$pid};
            push @pids, $pid;
        }
    }

    return "No matching process." if not @pids;

    my $ret = eval { kill $signal, @pids };

    if ($@) {
        my $error = $@;
        $error =~ s/ at PBot.*//;
        return $error;
    }

    return "[$ret] Sent signal " . $signal . ' to ' . join ', ', @pids;
}

1;
