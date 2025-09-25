# File: ProcessManager.pm
#
# Purpose: Handles forking and execution of applet/subroutine processes.
# Provides commands to list running processes and to kill them.

# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::ProcessManager;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw/gettimeofday/;
use POSIX qw/WNOHANG/;
use JSON;

sub initialize($self, %conf) {
    # hash of currently running bot-invoked processes
    $self->{processes} = {};

    # automatically reap children processes in background
    $SIG{CHLD} = sub {
        my $pid; do { $pid = waitpid(-1, WNOHANG); $self->remove_process($pid) if $pid > 0; } while $pid > 0;
    };
}

sub add_process($self, $pid, $context) {
    my $data = {
        start => scalar gettimeofday,
        command => $context->{command},
    };

    $self->{processes}->{$pid} = $data;

    $self->{pbot}->{logger}->log("Starting process $pid: $data->{command}\n");
}

sub remove_process($self, $pid) {
    if (exists $self->{processes}->{$pid}) {
        my $command = $self->{processes}->{$pid}->{command};

        my $duration = sprintf "%0.3f", gettimeofday - $self->{processes}->{$pid}->{start};

        $self->{pbot}->{logger}->log("Finished process $pid ($command): duration $duration seconds\n");

        delete $self->{processes}->{$pid};
    } else {
        $self->{pbot}->{logger}->log("External process finished $pid\n");
    }
}

sub execute_process($self, $context, $subref, $timeout = undef, $reader_subref = undef) {
    # debug flag to trace $context location and contents
    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Indent = 2;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("ProcessManager::execute_process\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    # don't fork again if we're already child
    if (defined $context->{pid} and $context->{pid} == 0) {
        $self->{pbot}->{logger}->log("execute_process: Re-using PID $context->{pid} for new process\n");
        $subref->($context);
        return $context->{result};
    }

    pipe(my $reader, my $writer);

    # fork new process
    $context->{pid} = fork;

    $self->{pbot}->{logger}->log("=-=-=-=-=-=-= FORK PID $context->{pid} =-=-=-=-=-=-=-=\n");

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
            local $SIG{ALRM} = sub { die "Process `$context->{command}` timed-out\n" };
            alarm ($timeout // 30);
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
        if (defined $reader_subref) {
            $self->{pbot}->{select_handler}->add_reader($reader, sub { $reader_subref->($context->{pid}, @_) });
        } else {
            $self->{pbot}->{select_handler}->add_reader($reader, sub { $self->process_pipe_reader($context->{pid}, @_) });
        }

        # return undef since reader will handle the output when child is finished
        return undef;
    }
}

sub process_pipe_reader($self, $pid, $buf) {
    # retrieve context object from child
    my $context = decode_json $buf or do {
        $self->{pbot}->{logger}->log("ProcessManager::process_pipe_reader: Failed to decode bad json: [$buf]\n");
        return;
    };

    # debug flag to trace $context location and contents
    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Indent = 2;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("ProcessManager::process_pipe_reader ($pid)\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    # context is no longer forked
    delete $context->{pid};

    # check for output
    if (not defined $context->{result} or not length $context->{result}) {
        $self->{pbot}->{logger}->log("No result from process.\n");
        if ($context->{suppress_no_output}) {
            $context->{result} = '';
        } else {
            $context->{result} = "No output.";
        }
    }

    # don't output unnecessary result if command was embedded within a message
    if ($context->{embedded}) {
        return if $context->{result} =~ m/(?:no results)/i;
    }

    $self->{pbot}->{logger}->log("process pipe handling result [$context->{result}]\n");

    # handle code factoid result
    if (exists $context->{special} and $context->{special}->{$context->{stack_depth}} eq 'code-factoid') {
        $context->{result} =~ s/\s+$//g;
        $context->{original_keyword} = $context->{root_keyword};
        $context->{result} = $self->{pbot}->{factoids}->{interpreter}->handle_action($context, $context->{result});
    }

    # send the result off to the bot to be handled
    $context->{checkflood} = 1;
    $self->{pbot}->{interpreter}->handle_result($context);
}

1;
