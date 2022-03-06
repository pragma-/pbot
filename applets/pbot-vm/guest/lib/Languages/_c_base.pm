#!/usr/bin/perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package _c_base;
use parent '_default';

sub preprocess {
    my $self = shift;

    my $input = $self->{input} // '';

    open(my $fh, '>:encoding(UTF-8)', '.input');
    print $fh "$input\n";
    close $fh;

    my @cmd = $self->split_line($self->{cmdline}, strip_quotes => 1, preserve_escapes => 0);

    if ($self->{code} =~ m/print_last_statement\(.*\);$/m) {
        # remove print_last_statement wrapper in order to get warnings/errors from last statement line
        my $code = $self->{code};
        $code =~ s/print_last_statement\((.*)\);$/$1;/mg;
        open(my $fh, '>:encoding(UTF-8)', $self->{sourcefile}) or die $!;
        print $fh $code . "\n";
        close $fh;

        print STDERR "Executing [$self->{cmdline}] without print_last_statement\n";
        my ($retval, $stdout, $stderr) = $self->execute(60, undef, @cmd);
        $self->{output} = $stderr;
        $self->{output} .= ' ' if length $self->{output};
        $self->{output} .= $stdout;
        $self->{error}  = $retval;

        # now compile with print_last_statement intact, ignoring compile results
        if (not $self->{error}) {
            open(my $fh, '>:encoding(UTF-8)', $self->{sourcefile}) or die $!;
            print $fh $self->{code} . "\n";
            close $fh;

            print STDERR "Executing [$self->{cmdline}] with print_last_statement\n";
            $self->execute(60, undef, @cmd);
        }
    } else {
        open(my $fh, '>:encoding(UTF-8)', $self->{sourcefile}) or die $!;
        print $fh $self->{code} . "\n";
        close $fh;

        print STDERR "Executing [$self->{cmdline}]\n";
        my ($retval, $stdout, $stderr) = $self->execute(60, undef, @cmd);
        $self->{output} = $stderr;
        $self->{output} .= ' ' if length $self->{output};
        $self->{output} .= $stdout;
        $self->{error}  = $retval;
    }

    if ($self->{cmdline} =~ m/--(?:version|analyze)/) {
        $self->{done} = 1;
    }

    # set done instead of error to prevent "[Exit 1]" output for compiler error messages
    if ($self->{error}) {
        $self->{error} = 0;
        $self->{done}  = 1;
    }
}

sub postprocess {
    my $self = shift;

    $self->SUPER::postprocess;

    # no errors compiling, but if output contains something, it must be diagnostic messages
    if (length $self->{output}) {
        $self->{output} =~ s/^\s+//;
        $self->{output} =~ s/\s+$//;
        $self->{output} = "[$self->{output}]\n";
    }

    print STDERR "Executing gdb\n";
    my ($exitval, $stdout, $stderr);

    my $ulimits = "ulimit -f 2000; ulimit -t 8; ulimit -u 200";

    my @args = $self->split_line($self->{arguments}, strip_quotes => 1, preserve_escapes => 0);

    my $quoted_args = '';

    foreach my $arg (@args) {
        $arg =~ s/'/'"'"'/g;
        $quoted_args .= "'$arg' ";
    }

    if ($self->{cmdline} =~ /-fsanitize=(?:[^ ]+,)?address/) {
        # leak sanitizer doesn't work under ptrace/gdb
        # ASAN_OPTIONS=strict_string_checks=1:detect_stack_use_after_return=1:check_initialization_order=1:strict_init_order=1
        ($exitval, $stdout, $stderr) = $self->execute(60, "$ulimits; ./prog $quoted_args\n", '/bin/sh');
    } else {
        my $input = "$ulimits; guest-gdb ./prog $quoted_args";
        ($exitval, $stdout, $stderr) = $self->execute(60, $input, '/bin/sh');
    }

    $self->{error} = $exitval;

    my $result = $stderr;
    $result .= ' ' if length $result;
    $result .= $stdout;

    if (not length $result) {
        $self->{no_output} = 1;
    } elsif ($self->{code} =~ m/print_last_statement\(.*\);$/m
        && ($result =~ m/A syntax error in expression/ || $result =~ m/No symbol.*in current context/ || $result =~ m/has unknown return type; cast the call to its declared return/ || $result =~ m/Can't take address of.*which isn't an lvalue/)) {
        # strip print_last_statement and rebuild/re-run
        $self->{code} =~ s/print_last_statement\((.*)\);/$1;/mg;
        $self->preprocess;
        $self->postprocess;
    } else {
        $self->{output} .= $result;
    }
}

1;
