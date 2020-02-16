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

use Time::Duration qw/concise duration/;
use Getopt::Long qw/GetOptionsFromArray/;
use POSIX qw/WNOHANG/;
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
    my $usage = 'Usage: ps [-atu]; -a show all information; -t show running time; -u show user/channel';

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling");

    my ($show_all, $show_user, $show_running_time);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($arguments, preserve_escapes => 1, strip_quotes => 1);
    GetOptionsFromArray(
        \@opt_args,
        'all|a' => \$show_all,
        'user|u' => \$show_user,
        'time|t' => \$show_running_time
    );
    return "$getopt_error; $usage" if defined $getopt_error;

    my @processes;
    foreach my $pid (sort keys %{$self->{processes}}) { push @processes, $self->{processes}->{$pid}; }
    if (not @processes) { return "No running processes."; }

    my $result;
    if (@processes == 1) { $result = 'One process: '; } else { $result = @processes . ' processes: '; }

    my $sep = '';
    foreach my $process (@processes) {
        $result .= $sep;
        $result .= "$process->{pid}: $process->{commands}->[0]";

        if ($show_running_time or $show_all) {
            my $duration = concise duration (time - $process->{process_start});
            $result .= " [$duration]";
        }

        if ($show_user or $show_all) {
            $result .= " ($process->{nick} in $process->{from})";
        }

        $sep = '; ';
    }

    return $result;
}

sub kill_cmd {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
    my $usage = 'Usage: kill [-a] [-t <seconds>] [-s <signal>]  [pids...]; -a kill all processes; -t <seconds> kill processes running longer than <seconds>; -s send <signal> to processes';

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling");

    my ($kill_all, $kill_time, $signal);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($arguments, preserve_escapes => 1, strip_quotes => 1);
    GetOptionsFromArray(
        \@opt_args,
        'all|a' => \$kill_all,
        'time|t=i' => \$kill_time,
        'signal|s=s' => \$signal,
    );
    return "$getopt_error; $usage" if defined $getopt_error;
    return "Must specify PIDs to kill unless options -a or -t are provided." if not $kill_all and not $kill_time and not @opt_args;

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
            print "$pid: running time " . $now - $process->{process_start} . " and kill time: $kill_time\n";
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
    if ($@) { my $error = $@; $error =~ s/ at PBot.*//; return $error; }
    return "[$ret] Sent signal " . $signal . ' to ' . join ', ', @pids;
}

sub add_process {
    my ($self, $pid, $stuff) = @_;
    $stuff->{process_start} = time;
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
