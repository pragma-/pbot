#!/usr/bin/env perl

# File: Guest.pm
#
# Purpose: Collection of functions to interface with the PBot VM Guest and
# execute VM commands.

# SPDX-FileCopyrightText: 2022-2024 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package Guest;

use 5.020;

use warnings;
use strict;

use feature qw/signatures/;
no warnings qw(experimental::signatures);

use English;
use Encode;
use File::Basename;
use JSON::XS;
use Time::HiRes qw/gettimeofday/;
use POSIX;

use Data::Dumper;
$Data::Dumper::Useqq = 1;
$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 0;

sub info($text, $maxlen = 255) {
    my $rest;
    ($text, $rest) = $text =~ m/^(.{0,$maxlen})(.*)/ms;
    $rest = length $rest;
    $text .= " [... $rest more]" if $rest;
    $text .= "\n" if $text !~ /\n$/;
    my ($sec, $usec) = gettimeofday;
    my $time = strftime "%a %b %e %Y %H:%M:%S", localtime $sec;
    $time .= sprintf ".%03d", $usec / 1000;
    print STDERR "$$ $time :: $text";
}

sub read_input($input, $buffer, $tag) {
    info("$tag waiting for input...\n");
    my $ret = sysread($input, my $buf, 4096);

    if (not defined $ret) {
        info("Error reading $tag: $!\n");
        return undef;
    }

    if ($ret == 0) {
        info("$tag input closed.\n");
        return 0;
    }

    info("$tag read $ret [" . (Dumper $buf) . "]\n");

    $$buffer .= $buf;

    # info("$tag buffer [" . (Dumper $$buffer) . "]\n", 8192);

    if ($$buffer !~ /\n\n/) {
        return undef;
    }

    my $line;
    ($line, $$buffer) = split /\n\n/, $$buffer, 2;
    $line =~ s/\n//g;

    info(("-" x 40) . "\n");

    # info("$tag got [" . (Dumper $line) . "]\n", 8192);
    # info("$tag buffer [" . (Dumper $$buffer) . "]\n", 8192);

    my $command = eval { decode_json($line) };

    if ($@) {
        info("Failed to decode JSON: $@\n", 1024);
        return {
            arguments  => '',
            cmdline    => 'sh prog.sh',
            code       => "echo 'Failed to decode JSON: $@'",
            date       => 0,
            execfile   => 'prog.sh',
            input      => '',
            lang       => 'sh',
            sourcefile => 'prog.sh'
        };
    }

    $command->{arguments} //= '';
    $command->{input}     //= '';

    info("command: " . Dumper($command), 2048);
    return $command;
}

sub process_command($command, $mod, $user, $tag) {
    my ($uid, $gid, $home) = (getpwnam $user)[2, 3, 7];

    if (not $uid and not $gid) {
        info("Could not find user $user: $!\n");
        return undef;
    }

    my $pid = fork;

    if (not defined $pid) {
        info("process_command: fork failed: $!\n");
        return undef;
    }

    if ($pid == 0) {
        if ($command->{'persist-key'}) {
            system ("rm -rf \"/home/$user/$command->{'persist-key'}\" 1>&2");
            system("mount /dev/vdb1 /root/factdata 1>&2");
            system("mkdir -p \"/root/factdata/$command->{'persist-key'}\" 1>&2");
            system("cp -R -p \"/root/factdata/$command->{'persist-key'}\" \"/home/$user/$command->{'persist-key'}\" 1>&2");
        }

        my $dir = "/home/$user/$$";

        system("mkdir -p $dir 1>&2");

        system("chmod -R 755 $dir 1>&2");
        system("chown -R $user $dir 1>&2");
        system("chgrp -R $user $dir 1>&2");

        if (time - $command->{date} > 60) {
            system("date -s \@$command->{date} 1>&2");
        }

        $ENV{USER}    = $user;
        $ENV{LOGNAME} = $user;
        $ENV{HOME}    = $home;

        chdir("/home/$user/$$");

        $GID = $gid;
        $EGID = "$gid $gid";
        $EUID = $UID = $uid;

        my $result = run_command($command, $mod);

        info(("=" x 40) . "\n");

        # ensure output is newline-terminated
        $result .= "\n" unless $result =~ /\n$/;

        return $result;
    } else {
        # wait for child to finish
        my $kid = waitpid($pid, 0);
        my $status = $?;

        if (WIFEXITED($status)) {
            info("child normal exit: " . WEXITSTATUS($status) . "\n");
        }

        if (WIFSIGNALED($status)) {
            info("child signaled exit: " . WTERMSIG($status) . "\n");
        }

        # clean up persistent factoid storage
        if ($command->{'persist-key'}) {
            system("cp -R -p \"/home/$user/$command->{'persist-key'}\" \"/root/factdata/$command->{'persist-key'}\"");
            system("umount /root/factdata");
            system ("rm -rf \"/home/$user/$command->{'persist-key'}\"");
        }

        # kill any left-over processes started by user
        system("pkill -P $pid");
        system("rm -rf /home/$user/$pid");
        return 0;
    }
}

sub run_command($command, $mod) {
    local $SIG{CHLD} = 'DEFAULT';

    $mod->preprocess;
    $mod->postprocess if not $mod->{error} and not $mod->{done};

    if (exists $mod->{no_output} or not length $mod->{output}) {
        if ($command->{factoid}) {
            $mod->{output} = '';
        } else {
            $mod->{output} .= "\n" if length $mod->{output};

            if (not $mod->{error}) {
                $mod->{output} .= "Success (no output).\n";
            } else {
                $mod->{output} .= "Exit $mod->{error}.\n";
            }
        }
    } elsif ($mod->{error}) {
        $mod->{output} .= " [Exit $mod->{error}]";
    }

    return $mod->{output};
}

sub send_output($output, $result, $tag) {
    my $json = encode_json({ result => $result });
    print $output "result:$json\n";
    print $output "result:end\n";
}

1;
