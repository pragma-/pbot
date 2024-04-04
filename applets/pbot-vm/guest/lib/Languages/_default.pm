#!/usr/bin/perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package _default;

use warnings;
use strict;

use IPC::Run qw/run timeout/;
use Encode;

use Data::Dumper;
$Data::Dumper::Terse    = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Useqq    = 1;

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

    print STDERR "execute ($timeout) [$stdin] @cmdline\n";

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

    $Data::Dumper::Indent = 0;
    print STDERR "exitval $exitval stderr [", Dumper($stderr), "] stdout [", Dumper($stdout), "]\n";
    $Data::Dumper::Indent = 1;

    return ($exitval, $stdout, $stderr);
}

# splits line into quoted arguments while preserving quotes.
# a string is considered quoted only if they are surrounded by
# whitespace or json separators.
# handles unbalanced quotes gracefully by treating them as
# part of the argument they were found within.
sub split_line {
    my ($self, $line, %opts) = @_;

    my %default_opts = (
        strip_quotes => 0,
        keep_spaces => 0,
        preserve_escapes => 1,
    );

    %opts = (%default_opts, %opts);

    my @chars = split //, $line;

    my @args;
    my $escaped = 0;
    my $quote;
    my $token = '';
    my $ch = ' ';
    my $last_ch;
    my $next_ch;
    my $i = 0;
    my $pos;
    my $ignore_quote = 0;
    my $spaces = 0;

    while (1) {
        $last_ch = $ch;

        if ($i >= @chars) {
            if (defined $quote) {
                # reached end, but unbalanced quote... reset to beginning of quote and ignore it
                $i = $pos;
                $ignore_quote = 1;
                $quote = undef;
                $last_ch = ' ';
                $token = '';
            } else {
                # add final token and exit
                push @args, $token if length $token;
                last;
            }
        }

        $ch = $chars[$i++];
        $next_ch = $chars[$i];

        $spaces = 0 if $ch ne ' ';

        if ($escaped) {
            if ($opts{preserve_escapes}) {
                $token .= "\\$ch";
            } else {
                $token .= $ch;
            }
            $escaped = 0;
            next;
        }

        if ($ch eq '\\') {
            $escaped = 1;
            next;
        }

        if (defined $quote) {
            if ($ch eq $quote and (not defined $next_ch or $next_ch =~ /[\s,:;})\].+=]/)) {
                # closing quote
                $token .= $ch unless $opts{strip_quotes};
                push @args, $token;
                $quote = undef;
                $token = '';
            } else {
                # still within quoted argument
                $token .= $ch;
            }
            next;
        }

        if (($last_ch =~ /[\s:{(\[.+=]/) and not defined $quote and ($ch eq "'" or $ch eq '"')) {
            if ($ignore_quote) {
                # treat unbalanced quote as part of this argument
                $token .= $ch;
                $ignore_quote = 0;
            } else {
                # begin potential quoted argument
                $pos = $i - 1;
                $quote = $ch;
                $token .= $ch unless $opts{strip_quotes};
            }
            next;
        }

        if ($ch eq ' ') {
            if (++$spaces > 1 and $opts{keep_spaces}) {
                $token .= $ch;
                next;
            } else {
                push @args, $token if length $token;
                $token = '';
                next;
            }
        }

        $token .= $ch;
    }

    return @args;
}

sub quote_args {
    my ($self, $text) = @_;

    my @args = $self->split_line($text, strip_quotes => 1, preserve_escapes => 0);

    my $quoted = '';

    foreach my $arg (@args) {
        $arg =~ s/'/'"'"'/g;
        $quoted .= "'$arg' ";
    }

    return $quoted;
}

1;
