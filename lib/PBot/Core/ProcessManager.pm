# File: ProcessManager.pm
#
# Purpose: Handles forking and execution of module/subroutine processes.
# Provides commands to list running processes and to kill them.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::ProcessManager;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw/gettimeofday/;
use POSIX qw/WNOHANG/;
use JSON;

sub initialize {
    my ($self, %conf) = @_;

    # hash of currently running bot-invoked processes
    $self->{processes} = {};

    # automatically reap children processes in background
    $SIG{CHLD} = sub {
        my $pid; do { $pid = waitpid(-1, WNOHANG); $self->remove_process($pid) if $pid > 0; } while $pid > 0;
    };
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

    # ensure contextual command history list is available for add_process()
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
        *PBot::Core::IRC::Connection::DESTROY = sub { return; };
        use warnings;

        # remove atexit handlers
        $self->{pbot}->{atexit}->unregister_all;

        # execute the provided subroutine, results are stored in $context
        eval {
            local $SIG{ALRM} = sub { die "Process `$context->{commands}->[0]` timed-out\n" };
            alarm $timeout;
            $subref->($context);
            alarm 0;
        };

        # check for errors
        if ($@) {
            $context->{result} = $@;

            $context->{'timed-out'} = 1 if $context->{result} =~ /^Process .* timed-out/;

            $self->{pbot}->{logger}->log("Error executing process: $context->{result}\n");
        }

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

    # don't output unnecessary result if command was embedded within a message
    if ($context->{embedded}) {
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
        $context->{result} = $self->{pbot}->{factoids}->{interpreter}->handle_action($context, $context->{result});
    }

    # send the result off to the bot to be handled
    $context->{checkflood} = 1;
    $self->{pbot}->{interpreter}->handle_result($context);
}

1;
