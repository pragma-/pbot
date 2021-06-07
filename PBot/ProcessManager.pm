# File: ProcessManager.pm
# Author: pragma_
#
# Purpose: Handles forking and execution of module/subroutine processes

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::ProcessManager;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';
use utf8;

use Time::Duration qw/concise duration/;
use Time::HiRes qw/gettimeofday/;
use Getopt::Long qw/GetOptionsFromArray/;
use POSIX qw/WNOHANG/;
use JSON;

sub initialize {
    my ($self, %conf) = @_;

    # process manager bot commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_ps(@_) },   'ps',   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_kill(@_) }, 'kill', 1);

    # give admin capability group the can-kill capability
    $self->{pbot}->{capabilities}->add('admin', 'can-kill', 1);

    # hash of currently running bot-invoked processes
    $self->{processes} = {};

    # automatically reap children processes in background
    $SIG{CHLD} = sub {
        my $pid; do { $pid = waitpid(-1, WNOHANG); $self->remove_process($pid) if $pid > 0; } while $pid > 0;
    };
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

    foreach my $pid (sort keys %{$self->{processes}}) {
        push @processes, $self->{processes}->{$pid};
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

        foreach my $pid (sort keys %{$self->{processes}}) {
            my $process = $self->{processes}->{$pid};
            next if defined $kill_time and $now - $process->{process_start} < $kill_time;
            push @pids, $pid;
        }
    } else {
        foreach my $pid (@opt_args) {
            return "No such pid $pid." if not exists $self->{processes}->{$pid};
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

sub add_process {
    my ($self, $pid, $context) = @_;

    $context->{process_start} = gettimeofday;

    $self->{processes}->{$pid} = $context;

    $self->{pbot}->{logger}->log("Starting process $pid: $context->{commands}->[0]\n");
}

sub remove_process {
    my ($self, $pid) = @_;

    if (exists $self->{processes}->{$pid}) {
        my $command = $self->{processes}->{$pid}->{commands}->[0];

        my $duration = gettimeofday - $self->{processes}->{$pid}->{process_start};
        $duration = sprintf "%0.3f", $duration;

        $self->{pbot}->{logger}->log("Finished process $pid ($command): duration $duration seconds\n");

        delete $self->{processes}->{$pid};
    } else {
        $self->{pbot}->{logger}->log("Finished process $pid\n");
    }
}

sub execute_process {
    my ($self, $context, $subref, $timeout) = @_;

    $timeout //= 30; # default timeout 30 seconds

    if (not exists $context->{commands}) {
        $context->{commands} = [$context->{command}];
    }

    # don't fork again if we're already a forked process
    if (defined $context->{pid} and $context->{pid} == 0) {
        $subref->($context);
        return $context->{result};
    }

    pipe(my $reader, my $writer);

    # fork new process
    $context->{pid} = fork;

    if (not defined $context->{pid}) {
        # fork failed
        $self->{pbot}->{logger}->log("Could not fork process: $!\n");

        close $reader;
        close $writer;

        delete $context->{pid};

        # groan to let the users know something went wrong
        $context->{checkflood} = 1;
        $self->{pbot}->{interpreter}->handle_result($context, "/me groans loudly.\n");

        return;
    }

    if ($context->{pid} == 0) {
        # child

        close $reader;

        # flag this instance as child
        $self->{pbot}->{child} = 1;

        # don't quit the IRC client when the child dies
        no warnings;
        *PBot::IRC::Connection::DESTROY = sub { return; };
        use warnings;

        # remove atexit handlers
        $self->{pbot}->{atexit}->unregister_all;

        # FIXME: close databases and files too? Or just set everything to check for $self->{pbot}->{child} == 1 or $context->{pid} == 0?

        # execute the provided subroutine, results are stored in $context
        eval {
            local $SIG{ALRM} = sub { die "Process `$context->{commands}->[0]` timed-out" };
            alarm $timeout;
            $subref->($context);
        };

        # check for errors
        if ($@) {
            $context->{result} = $@;

            $context->{'timed-out'} = 1 if $context->{result} =~ /^Process .* timed-out at PBot\/ProcessManager/;

            $self->{pbot}->{logger}->log("Error executing process: $context->{result}\n");

            # strip internal PBot source data for IRC output
            $context->{result} =~ s/ at PBot.*$//ms;
            $context->{result} =~ s/\s+...propagated at .*$//ms;
        }

        # turn alarm back on for PBot::Timer
        alarm 1;

        # print $context to pipe
        my $json = encode_json $context;
        print $writer "$json\n";
        close $writer;

        # end child
        exit 0;
    } else {
        # parent

        # nothing to write to child
        close $writer;

        # add process
        $self->add_process($context->{pid}, $context);

        # add reader handler
        $self->{pbot}->{select_handler}->add_reader($reader, sub { $self->process_pipe_reader($context->{pid}, @_) });

        # return empty string since reader will handle the output when child is finished
        return '';
    }
}

sub process_pipe_reader {
    my ($self, $pid, $buf) = @_;

    # retrieve context object from child
    my $context = decode_json $buf or do {
        $self->{pbot}->{logger}->log("Failed to decode bad json: [$buf]\n");
        return;
    };

    # context is no longer forked
    delete $context->{pid};

    # check for output
    if (not defined $context->{result} or not length $context->{result}) {
        $self->{pbot}->{logger}->log("No result from process.\n");
        return if $context->{suppress_no_output};
        $context->{result} = "No output.";
    }

    # don't output unnecessary result if command was referenced within a message
    if ($context->{referenced}) {
        return if $context->{result} =~ m/(?:no results)/i;
    }

    # handle code factoid result
    if (exists $context->{special} and $context->{special} eq 'code-factoid') {
        $context->{result} =~ s/\s+$//g;

        if (not length $context->{result}) {
            $self->{pbot}->{logger}->log("No text result from code-factoid.\n");
            return;
        }

        $context->{original_keyword} = $context->{root_keyword};
        $context->{result} = $self->{pbot}->{factoids}->handle_action($context, $context->{result});
    }

    # if nick isn't overridden yet, check for a potential nick prefix
    if (not defined $context->{nickoverride}) {
        # if add_nick is set on the factoid, set the nick override to the caller's nick
        if (exists $context->{special} and $context->{special} ne 'code-factoid'
            and $self->{pbot}->{factoids}->{factoids}->exists($context->{channel}, $context->{trigger}, 'add_nick')
            and $self->{pbot}->{factoids}->{factoids}->get_data($context->{channel}, $context->{trigger}, 'add_nick') != 0)
        {
            $context->{nickoverride}       = $context->{nick};
            $context->{no_nickoverride}    = 0;
            $context->{force_nickoverride} = 1;
        } else {
            # extract nick-like thing from process result
            if ($context->{result} =~ s/^(\S+): //) {
                my $nick = $1;

                if (lc $nick eq "usage") {
                    # put it back on result if it's a usage message
                    $context->{result} = "$nick: $context->{result}";
                } else {
                    my $present = $self->{pbot}->{nicklist}->is_present($context->{channel}, $nick);

                    if ($present) {
                        # nick is present in channel
                        $context->{nickoverride} = $present;
                    } else {
                        # nick not present, put it back on result
                        $context->{result} = "$nick: $context->{result}";
                    }
                }
            }
        }
    }

    # send the result off to the bot to be handled
    $context->{checkflood} = 1;
    $self->{pbot}->{interpreter}->handle_result($context, $context->{result});
}

1;
