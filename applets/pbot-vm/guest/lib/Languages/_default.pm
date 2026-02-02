#!/usr/bin/perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package _default;

use warnings;
use strict;

use feature qw/signatures/;
no warnings qw/experimental::signatures/;

use IPC::Run qw/run timeout/;
use Encode;

use SplitLine;

use Time::HiRes qw/gettimeofday/;
use POSIX;

use Data::Dumper;
$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq    = 1;
$Data::Dumper::Indent   = 0;

sub info($text, $maxlen = 255) {
    my $rest;
    ($text, $rest) = $text =~ m/^(.{0,$maxlen})(.*)/ms;
    $rest = length $rest;
    $text .= " [... $rest more]" if $rest;
    $text .= "\n" if $text !~ /\n$/;
    my ($sec, $usec) = gettimeofday;
    my $time = strftime "%a %b %e %Y %H:%M:%S", localtime $sec;
    $time .= sprintf ".%03d", $usec / 1000;
    print STDERR "[$$] $time :: $text";
}

sub new {
    my ($class, %conf) = @_;
    my $self = bless {}, $class;

    $self->{debug}         = $conf{debug} // 0;
    $self->{sourcefile}    = $conf{sourcefile};
    $self->{execfile}      = $conf{execfile};
    $self->{code}          = $conf{code};
    $self->{cmdline}       = $conf{cmdline};
    $self->{input}         = $conf{input} // '';
    $self->{date}          = $conf{date};
    $self->{arguments}     = $conf{arguments};
    $self->{factoid}       = $conf{factoid};
    $self->{'persist-key'} = $conf{'persist-key'};

    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;
}

sub preprocess {
    my $self = shift;

    open(my $fh, '>:encoding(UTF-8)', $self->{sourcefile}) or die $!;
    print $fh $self->{code} . "\n";
    close $fh;

    my $quoted_args = $self->quote_args($self->{arguments});

    my $stdin = 'ulimit -f 2000; ulimit -t 8; ulimit -u 200; ';

    if (length $self->{input}) {
        my $quoted_cmd = "$self->{cmdline} $quoted_args";
        $quoted_cmd =~ s/'/'"'"'/g;

        my $quoted_input = $self->{input};
        $quoted_input =~ s/'/'"'"'/g;

        $stdin .= "/bin/bash -c '$quoted_cmd' <<< '$quoted_input'";
    } else {
        $stdin .= "$self->{cmdline} $quoted_args";
    }

    my ($retval, $stdout, $stderr) = $self->execute(60, $stdin, '/bin/bash');

    $self->{output} = $stderr;
    $self->{output} .= ' ' if length $self->{output};
    $self->{output} .= $stdout;
    $self->{error}  = $retval;
}

sub postprocess {}

sub execute {
    my ($self, $timeout, $stdin, @cmdline) = @_;

    $stdin //= '';

    $stdin = encode('UTF-8', $stdin);
    @cmdline = map { encode('UTF-8', $_) } @cmdline;

    info("execute ($timeout) [$stdin] @cmdline\n");

    my ($exitval, $stdout, $stderr) = eval {
        my ($stdout, $stderr);
        run \@cmdline, \$stdin, \$stdout, \$stderr, timeout($timeout);
        my $exitval = $? >> 8;
        return ($exitval, decode('UTF-8', $stdout), decode('UTF-8', $stderr));
    };

    if (my $exception = $@) {
        $exception = "[Timed-out]" if $exception =~ m/timeout on timer/;
        ($exitval, $stdout, $stderr) = (-1, '', $exception);
    }

    info("exitval $exitval stderr [" . Dumper($stderr) . "] stdout [" . Dumper($stdout) . "]\n");
    return ($exitval, $stdout, $stderr);
}

sub quote_args {
    my ($self, $text) = @_;

    my @args = split_line($text, strip_quotes => 1, preserve_escapes => 1);

    my $quoted = '';

    foreach my $arg (@args) {
        $arg =~ s/'/'"'"'/g;
        $quoted .= "'$arg' ";
    }

    return $quoted;
}

1;
