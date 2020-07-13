# File: Plang.pm
# Author: pragma-
#
# Purpose: Simplified scripting language for creating advanced PBot factoids
# and interacting with various internal PBot APIs.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Plang;
use parent 'Plugins::Plugin';

use warnings; use strict;
use feature 'unicode_strings';

use Getopt::Long qw(GetOptionsFromArray);

sub initialize {
    my ($self, %conf) = @_;

    my $path = $self->{pbot}->{registry}->get_value('general', 'plang_dir') // 'Plang';
    unshift @INC, $path if not grep { $_ eq $path } @INC;
    require "$path/Interpreter.pm";

    # regset plang.debug 0-10 -- Plugin must be reloaded for this value to take effect.
    my $debug = $self->{pbot}->{registry}->get_value('plang', 'debug') // 0;

    # create our Plang interpreter object
    $self->{plang} = Plang::Interpreter->new(embedded => 1, debug => $debug);

    # register some built-in functions
    $self->{plang}->{interpreter}->add_function_builtin('factset',
        # parameters are [['param1 name', default arg], ['param2 name', default arg], ...]
        [['channel', undef], ['keyword', undef], ['text', undef]],
        sub { $self->set_factoid(@_) });

    $self->{plang}->{interpreter}->add_function_builtin('factget',
        [['channel', undef], ['keyword', undef], ['meta', ['STRING', 'action']]],
        sub { $self->get_factoid(@_) });

    $self->{plang}->{interpreter}->add_function_builtin('factappend',
        [['channel', undef], ['keyword', undef], ['text', undef]],
        sub { $self->append_factoid(@_) });

    # register the `plang` command
    $self->{pbot}->{commands}->register(sub { $self->cmd_plang(@_) }, "plang", 0);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("plang");
}

sub cmd_plang {
    my ($self, $context) = @_;

    my $usage = "Usage: plang <code>; see https://github.com/pragma-/Plang";

    return $usage if not length $context->{arguments};

    # run() returns result of the final statement
    my $result = $self->run($context->{arguments});

    # check to see if we need to append final result to output
    $self->{output} .= $result->[1] if defined $result->[1];

    # return the output
    return length $self->{output} ? $self->{output} : "No output.";
}

# run an embedded plang program
# TODO this is just a proof-of-concept at this stage; 90% of this stuff will be moved into Plang::Interpreter
sub run {
    my ($self, $code) = @_;

    # reset output buffer
    $self->{output} = "";  # collect output of the embedded Plang program

    # parse the code into an ast
    my $ast = $self->{plang}->parse_string($code);

    # check for parse errors
    my $errors = $self->{plang}->handle_parse_errors;
    return ['ERROR', $errors] if defined $errors;

    # return if no program
    return if not defined $ast;

    # create a new environment for a Plang program
    my $context = $self->{plang}->{interpreter}->init_program;

    # grab our program's statements
    my $program    = $ast->[0];
    my $statements = $program->[1];

    my $result;            # result of the final statement

    eval {
        # interpret the statements
        foreach my $node (@$statements) {
            my $ins = $node->[0];

            if ($ins eq 'STMT') {
                $result = $self->{plang}->{interpreter}->statement($context, $node->[1]);

                $self->{output} .= $result->[1] if $result->[0] eq 'STDOUT';

                if ($result->[0] eq 'ERROR') {
                    $self->{output} .= "Error: $result->[1]";
                    $result = undef;
                    last;
                }
            }
        }
    };

    if ($@) {
        $self->{output} .= $@;
        return;
    }

    return $result; # return result of the final statement
}

# our custom PBot built-in functions for Plang

sub is_locked {
    my ($self, $channel, $keyword) = @_;
    return $self->{pbot}->{factoids}->get_meta($channel, $keyword, 'locked');
}

sub get_factoid {
    my ($self, $plang, $name, $arguments) = @_;
    my ($channel, $keyword, $meta) = ($arguments->[0]->[1], $arguments->[1]->[1], $arguments->[2]->[1]);
    my $result = $self->{pbot}->{factoids}->get_meta($channel, $keyword, $meta);
    return ['STRING', $result];
}

sub set_factoid {
    my ($self, $plang, $name, $arguments) = @_;
    my ($channel, $keyword, $text) = ($arguments->[0]->[1], $arguments->[1]->[1], $arguments->[2]->[1]);
    return ['ERROR', "Factoid $channel.$keyword is locked. Cannot set."] if $self->is_locked($channel, $keyword);
    $self->{pbot}->{factoids}->add_factoid('text', $channel, 'Plang', $keyword, $text);
    return ['STRING', $text];
}

sub append_factoid {
    my ($self, $plang, $name, $arguments) = @_;
    my ($channel, $keyword, $text) = ($arguments->[0]->[1], $arguments->[1]->[1], $arguments->[2]->[1]);
    return ['ERROR', "Factoid $channel.$keyword is locked. Cannot append."] if $self->is_locked($channel, $keyword);
    my $action = $self->{pbot}->{factoids}->get_meta($channel, $keyword, 'action');
    $action = "" if not defined $action;
    $action .= $text;
    $self->{pbot}->{factoids}->add_factoid('text', $channel, 'Plang', $keyword, $action);
    return ['STRING', $action];
}

1;
