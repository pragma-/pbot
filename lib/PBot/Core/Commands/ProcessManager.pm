# File: ProcessManager.pm
#
# Purpose: Registers commands for listing and killing running PBot processes.

# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::ProcessManager;

use PBot::Imports;
use parent 'PBot::Core::Class';

use Time::Duration qw/concise duration/;
use Time::HiRes qw/gettimeofday/;

sub initialize($self, %conf) {
    # process manager bot commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_ps(@_) },   'ps',   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_kill(@_) }, 'kill', 1);

    # give admin capability group the can-kill capability
    $self->{pbot}->{capabilities}->add('admin', 'can-kill', 1);
}

sub cmd_ps($self, $context) {
    my $usage = 'Usage: ps [-atu]; -a show all information; -t show running time; -u show user/channel';

    my ($show_all, $show_user, $show_running_time);

    my %opts = (
        all  => \$show_all,
        user => \$show_user,
        time => \$show_running_time,
    );

    my ($opt_args, $opt_error) = $self->{pbot}->{interpreter}->getopt(
        $context->{arguments},
        \%opts,
        ['bundling'],
        'all|a',
        'user|u',
        'time|t',
    );

    return "$opt_error; $usage" if defined $opt_error;

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

sub cmd_kill($self, $context) {
    my $usage = 'Usage: kill [-a] [-t <seconds>] [-s <signal>]  [pids...]; -a kill all processes; -t <seconds> kill processes running longer than <seconds>; -s send <signal> to processes';

    my ($kill_all, $kill_time, $signal);

    my %opts = (
        all    => \$kill_all,
        time   => \$kill_time,
        signal => \$signal,
    );

    my ($opt_args, $opt_error) = $self->{pbot}->{interpreter}->getopt(
        $context->{arguments},
        \%opts,
        ['bundling'],
        'all|a',
        'time|t=i',
        'signal|s=s',
    );

    return "$opt_error; $usage" if defined $opt_error;

    if (not $kill_all and not $kill_time and not @$opt_args) {
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
        foreach my $pid (@$opt_args) {
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
