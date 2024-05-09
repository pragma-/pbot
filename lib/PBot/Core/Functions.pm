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
#
# See also: Plugin/FuncBuiltins.pm, Plugin/FuncGrep.pm and Plugin/FuncSed.pm

# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Functions;
use parent 'PBot::Core::Class';

use PBot::Imports;

sub initialize($self, %conf) {
    # register `list` and `help` functions used to list
    # functions and obtain help about them

    $self->register(
        'list',
        {
            desc   => 'lists available funcs',
            usage  => 'list [regex]',
            subref => sub { $self->func_list(@_) }
        }
    );

    $self->register(
        'help',
        {
            desc   => 'provides help about a func',
            usage  => 'help [func]',
            subref => sub { $self->func_help(@_) }
        }
    );
}

sub register($self, $func, $data) {
    $self->{funcs}->{$func} = $data;
}

sub unregister($self, $func) {
    delete $self->{funcs}->{$func};
}

sub func_list($self, $regex = '.*') {
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

sub func_help($self, $func = undef) {
    if (not length $func) {
        return "func: invoke built-in functions; usage: func <keyword> [arguments]; to list available functions: func list [regex]";
    }

    if (not exists $self->{funcs}->{$func}) {
        return "No such func '$func'.";
    }

    return "$func: $self->{funcs}->{$func}->{desc}; usage: $self->{funcs}->{$func}->{usage}";
}

1;
