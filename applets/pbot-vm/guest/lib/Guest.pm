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
use Data::Dumper;

sub read_input($input, $buffer, $tag) {
    my $line;
    my $total_read = 0;

    print STDERR "$tag waiting for input...\n";
    my $ret = sysread($input, my $buf, 16384);

    if (not defined $ret) {
        print STDERR "Error reading $tag: $!\n";
        return undef;
    }

    if ($ret == 0) {
        print STDERR "$tag input closed.\n";
        return 0;
    }

    $total_read += $ret;

    print STDERR "$tag read $ret bytes [$total_read total] [$buf]\n";

    $$buffer .= $buf;

    return undef if $$buffer !~ s/\s*:end:\s*$//m;

    $line = $$buffer;
    chomp $line;

    $$buffer = '';
    $total_read = 0;

    print STDERR "-" x 40, "\n";
    print STDERR "$tag got [$line]\n";

    my $command = eval { decode_json($line) };

    if ($@) {
        print STDERR "Failed to decode JSON: $@\n";
        return undef;
    }

    $command->{arguments} //= '';
    $command->{input}     //= '';

    print STDERR Dumper($command), "\n";

    return $command;
}

sub process_command($command, $mod, $user, $tag) {
    my ($uid, $gid, $home) = (getpwnam $user)[2, 3, 7];

    if (not $uid and not $gid) {
        print STDERR "Could not find user $user: $!\n";
        return undef;
    }

    my $pid = fork;

    if (not defined $pid) {
        print STDERR "process_command: fork failed: $!\n";
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
        system("pkill -u $user 1>&2");

        system("date -s \@$command->{date} 1>&2");

        $ENV{USER}    = $user;
        $ENV{LOGNAME} = $user;
        $ENV{HOME}    = $home;

        chdir("/home/$user/$$");

        $GID = $gid;
        $EGID = "$gid $gid";
        $EUID = $UID = $uid;

        my $result = run_command($command, $mod);

        print STDERR "=" x 40, "\n";

        # ensure output is newline-terminated
        $result .= "\n" unless $result =~ /\n$/;

        return $result;
    } else {
        # wait for child to finish
        waitpid($pid, 0);

        # clean up persistent factoid storage
        if ($command->{'persist-key'}) {
            system("cp -R -p \"/home/$user/$command->{'persist-key'}\" \"/root/factdata/$command->{'persist-key'}\"");
            system("umount /root/factdata");
            system ("rm -rf \"/home/$user/$command->{'persist-key'}\"");
        }

        # kill any left-over processes started by $user
        system("pkill -u $user");
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
