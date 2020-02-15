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

use POSIX qw(WNOHANG);
use JSON;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->ps_cmd(@_) },   'ps',   0);
    $self->{pbot}->{commands}->register(sub { $self->kill_cmd(@_) }, 'kill', 1);
    $self->{pbot}->{capabilities}->add('admin', 'can-kill');
    $self->{processes} = {};

    # automatically reap children processes in background
    $SIG{CHLD} = sub {
        my $pid; do { $pid = waitpid(-1, WNOHANG); $self->remove_process($pid) if $pid > 0; } while $pid > 0;
    };
}

sub ps_cmd {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
    my @processes;
    foreach my $pid (sort keys %{$self->{processes}}) { push @processes, "$pid: $self->{processes}->{$pid}->{commands}->[0]"; }
    if (@processes) { return "Running processes: " . join '; ', @processes; }
    else            { return "No running processes."; }
}

sub kill_cmd {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
    my $usage = "Usage: kill <pids...>";
    my @pids;
    while (1) {
        my $pid = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist}) // last;
        return "No such pid $pid." if not exists $self->{processes}->{$pid};
        push @pids, $pid;
    }
    return $usage if not @pids;
    kill 'INT', @pids;
    return "Killed.";
}

sub add_process {
    my ($self, $pid, $stuff) = @_;
    $self->{processes}->{$pid} = $stuff;
}

sub remove_process {
    my ($self, $pid) = @_;
    delete $self->{processes}->{$pid};
}

sub execute_process {
    my ($self, $stuff, $subref, $timeout) = @_;
    $timeout //= 30;

    if (not exists $stuff->{commands}) { $stuff->{commands} = [$stuff->{command}]; }

    pipe(my $reader, my $writer);
    $stuff->{pid} = fork;

    if (not defined $stuff->{pid}) {
        $self->{pbot}->{logger}->log("Could not fork process: $!\n");
        close $reader;
        close $writer;
        $stuff->{checkflood} = 1;
        $self->{pbot}->{interpreter}->handle_result($stuff, "/me groans loudly.\n");
        return;
    }

    if ($stuff->{pid} == 0) {
        # child
        close $reader;

        # don't quit the IRC client when the child dies
        no warnings;
        *PBot::IRC::Connection::DESTROY = sub { return; };
        use warnings;

        # remove atexit handlers
        $self->{pbot}->{atexit}->unregister_all;

        # execute the provided subroutine, results are stored in $stuff
        eval {
            local $SIG{ALRM} = sub { die "PBot::Process `$stuff->{commands}->[0]` timed-out" };
            alarm $timeout;
            $subref->($stuff);
            die if $@;
        };
        alarm 0;

        # check for errors
        if ($@) {
            $stuff->{result} = $@;
            $self->{pbot}->{logger}->log("Error executing process: $stuff->{result}\n");
            $stuff->{result} =~ s/ at PBot.*$//ms;
        }

        # print $stuff to pipe
        my $json = encode_json $stuff;
        print $writer "$json\n";

        # end child
        exit 0;
    } else {
        # parent
        close $writer;
        $self->add_process($stuff->{pid}, $stuff);
        $self->{pbot}->{select_handler}->add_reader($reader, sub { $self->process_pipe_reader($stuff->{pid}, @_) });
        # return empty string since reader will handle the output when child is finished
        return "";
    }
}

sub process_pipe_reader {
    my ($self, $pid, $buf) = @_;
    my $stuff = decode_json $buf or do {
        $self->{pbot}->{logger}->log("Failed to decode bad json: [$buf]\n");
        return;
    };

    if (not defined $stuff->{result} or not length $stuff->{result}) {
        $self->{pbot}->{logger}->log("No result from process.\n");
        return;
    }

    if ($stuff->{referenced}) { return if $stuff->{result} =~ m/(?:no results)/i; }

    if (exists $stuff->{special} and $stuff->{special} eq 'code-factoid') {
        $stuff->{result} =~ s/\s+$//g;
        $self->{pbot}->{logger}->log("No text result from code-factoid.\n") and return if not length $stuff->{result};
        $stuff->{original_keyword} = $stuff->{root_keyword};
        $stuff->{result}           = $self->{pbot}->{factoids}->handle_action($stuff, $stuff->{result});
    }

    $stuff->{checkflood} = 0;

    if (defined $stuff->{nickoverride}) { $self->{pbot}->{interpreter}->handle_result($stuff, $stuff->{result}); }
    else {
        # don't override nick if already set
        if (    exists $stuff->{special}
            and $stuff->{special} ne 'code-factoid'
            and $self->{pbot}->{factoids}->{factoids}->exists($stuff->{channel}, $stuff->{trigger}, 'add_nick')
            and $self->{pbot}->{factoids}->{factoids}->get_data($stuff->{channel}, $stuff->{trigger}, 'add_nick') != 0)
        {
            $stuff->{nickoverride}       = $stuff->{nick};
            $stuff->{no_nickoverride}    = 0;
            $stuff->{force_nickoverride} = 1;
        } else {
            # extract nick-like thing from module result
            if ($stuff->{result} =~ s/^(\S+): //) {
                my $nick = $1;
                if (lc $nick eq "usage") {
                    # put it back on result if it's a usage message
                    $stuff->{result} = "$nick: $stuff->{result}";
                } else {
                    my $present = $self->{pbot}->{nicklist}->is_present($stuff->{channel}, $nick);
                    if ($present) {
                        # nick is present in channel
                        $stuff->{nickoverride} = $present;
                    } else {
                        # nick not present, put it back on result
                        $stuff->{result} = "$nick: $stuff->{result}";
                    }
                }
            }
        }
        $self->{pbot}->{interpreter}->handle_result($stuff, $stuff->{result});
    }

    my $text = $self->{pbot}->{interpreter}
      ->truncate_result($stuff->{channel}, $self->{pbot}->{registry}->get_value('irc', 'botnick'), 'undef', $stuff->{result}, $stuff->{result}, 0);
    $self->{pbot}->{antiflood}
      ->check_flood($stuff->{from}, $self->{pbot}->{registry}->get_value('irc', 'botnick'), $self->{pbot}->{registry}->get_value('irc', 'username'), 'pbot', $text, 0, 0, 0);
}

1;
