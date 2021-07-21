# File: Functions.pm
#
# Purpose: Special `func` command that executes built-in functions with
# optional arguments. Usage: func <identifier> [arguments].
#
# Intended usage is with command-substitution (&{}) or pipes (|{}).
#
# For example:
#
# factadd img /call echo https://google.com/search?q=&{func uri_escape $args}&tbm=isch
#
# The above would invoke the function 'uri_escape' on $args and then replace
# the command-substitution with the result, thus escaping $args to be safely
# used in the URL of this simple Google Image Search factoid command.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Functions;
use parent 'PBot::Core::Class';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->register(sub { $self->cmd_func(@_) }, 'func', 0);

    $self->register(
        'help',
        {
            desc   => 'provides help about a func',
            usage  => 'help [func]',
            subref => sub { $self->func_help(@_) }
        }
    );

    $self->register(
        'list',
        {
            desc   => 'lists available funcs',
            usage  => 'list [regex]',
            subref => sub { $self->func_list(@_) }
        }
    );
}

sub cmd_func {
    my ($self, $context) = @_;

    my $func = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    if (not defined $func) {
        return "Usage: func <keyword> [arguments]; see also: func help";
    }

    if (not exists $self->{funcs}->{$func}) {
        return "[No such func '$func']"
    }

    my @params;

    while (defined(my $param = $self->{pbot}->{interpreter}->shift_arg($context->{arglist}))) {
        push @params, $param;
    }

    my $result = $self->{funcs}->{$func}->{subref}->(@params);

    $result =~ s/\x1/1/g; # strip CTCP code

    return $result;
}

sub register {
    my ($self, $func, $data) = @_;
    $self->{funcs}->{$func} = $data;
}

sub unregister {
    my ($self, $func) = @_;
    delete $self->{funcs}->{$func};
}

sub func_help {
    my ($self, $func) = @_;

    if (not length $func) {
        return "func: invoke built-in functions; usage: func <keyword> [arguments]; to list available functions: func list [regex]";
    }

    if (not exists $self->{funcs}->{$func}) {
        return "No such func '$func'.";
    }

    return "$func: $self->{funcs}->{$func}->{desc}; usage: $self->{funcs}->{$func}->{usage}";
}

sub func_list {
    my ($self, $regex) = @_;

    $regex //= '.*';

    my $result = eval {
        my @funcs;

        foreach my $func (sort keys %{$self->{funcs}}) {
            if ($func =~ m/$regex/i or $self->{funcs}->{$func}->{desc} =~ m/$regex/i) {
                push @funcs, $func;
            }
        }

        my $result = join ', ', @funcs;

        if (not length $result) {
            if ($regex eq '.*') {
                $result = "No funcs yet.";
            } else {
                $result = "No matching func.";
            }
        }

        return "Available funcs: $result; see also: func help <keyword>";
    };

    if ($@) {
        my $error = $@;
        $error =~ s/at PBot.Functions.*$//;
        return "Error: $error\n";
    }

    return $result;
}

1;
