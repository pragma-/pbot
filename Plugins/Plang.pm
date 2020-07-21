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

    # load Plang modules
    my $path = $self->{pbot}->{registry}->get_value('general', 'plang_dir') // 'Plang';
    unshift @INC, $path if not grep { $_ eq $path } @INC;

    # require all the Plang .pm modules so Module::Refresh can reload them without
    # needing to restart PBot
    require "$path/Interpreter.pm";
    require "$path/AstInterpreter.pm";
    require "$path/Grammar.pm";
    require "$path/Parser.pm";
    require "$path/Lexer.pm";

    # regset plang.debug 0-10 -- Plugin must be reloaded for this value to take effect.
    my $debug = $self->{pbot}->{registry}->get_value('plang', 'debug') // 0;

    # create our Plang interpreter object
    $self->{plang} = Plang::Interpreter->new(embedded => 1, debug => $debug);

    # register some PBot-specific built-in functions
    $self->{plang}->{interpreter}->add_builtin_function('factset',
        # parameters are [['param1 name', default arg], ['param2 name', default arg], ...]
        [['namespace', undef], ['keyword', undef], ['text', undef]],
        sub { $self->set_factoid(@_) });

    $self->{plang}->{interpreter}->add_builtin_function('factget',
        [['namespace', undef], ['keyword', undef], ['meta', ['STRING', 'action']]],
        sub { $self->get_factoid(@_) });

    $self->{plang}->{interpreter}->add_builtin_function('factappend',
        [['namespace', undef], ['keyword', undef], ['text', undef]],
        sub { $self->append_factoid(@_) });

    # override the built-in `print` function to send to our output buffer instead
    $self->{plang}->{interpreter}->add_builtin_function('print',
        [['stmt', undef], ['end', ['STRING', "\n"]]],
        sub { $self->print_override(@_) });

    # register the `plang` command
    $self->{pbot}->{commands}->register(sub { $self->cmd_plang(@_) }, "plang", 0);

    # register the `plangrepl` command (does not reset environment)
    $self->{pbot}->{commands}->register(sub { $self->cmd_plangrepl(@_) }, "plangrepl", 0);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("plang");
}

sub cmd_plang {
    my ($self, $context) = @_;

    my $usage = "Usage: plang <code>; see https://github.com/pragma-/Plang";
    return $usage if not length $context->{arguments};

    $self->{output} = "";  # collect output of the embedded Plang program
    my $result = $self->{plang}->interpret_string($context->{arguments});

    # check to see if we need to append final result to output
    $self->{output} .= $self->{plang}->{interpreter}->output_value($result) if defined $result->[1];

    # return the output
    return length $self->{output} ? $self->{output} : "No output.";
}

sub cmd_plangrepl {
    my ($self, $context) = @_;

    my $usage = "Usage: plangrepl <code>; see https://github.com/pragma-/Plang";
    return $usage if not length $context->{arguments};

    $self->{output} = "";  # collect output of the embedded Plang program
    my $result = $self->{plang}->interpret_string($context->{arguments}, repl => 1);

    # check to see if we need to append final result to output
    $self->{output} .= $self->{plang}->{interpreter}->output_value($result, repl => 1) if defined $result->[1];

    # return the output
    return length $self->{output} ? $self->{output} : "No output.";
}

# overridden `print` built-in

sub print_override {
    my ($self, $plang, $name, $arguments) = @_;
    my ($stmt, $end) = ($plang->output_value($arguments->[0]), $arguments->[1]->[1]);
    $self->{output} .= "$stmt$end";
    return ['NIL', undef];
}

# our custom PBot built-in functions for Plang

sub is_locked {
    my ($self, $channel, $keyword) = @_;
    return $self->{pbot}->{factoids}->get_meta($channel, $keyword, 'locked');
}

sub get_factoid {
    my ($self, $plang, $name, $arguments) = @_;
    my ($namespace, $keyword, $meta) = ($arguments->[0]->[1], $arguments->[1]->[1], $arguments->[2]->[1]);
    my $result = $self->{pbot}->{factoids}->get_meta($namespace, $keyword, $meta);
    return ['STRING', $result];
}

sub set_factoid {
    my ($self, $plang, $name, $arguments) = @_;
    my ($namespace, $keyword, $text) = ($arguments->[0]->[1], $arguments->[1]->[1], $arguments->[2]->[1]);
    return ['ERROR', "Factoid $namespace.$keyword is locked. Cannot set."] if $self->is_locked($namespace, $keyword);
    $self->{pbot}->{factoids}->add_factoid('text', $namespace, 'Plang', $keyword, $text);
    return ['STRING', $text];
}

sub append_factoid {
    my ($self, $plang, $name, $arguments) = @_;
    my ($namespace, $keyword, $text) = ($arguments->[0]->[1], $arguments->[1]->[1], $arguments->[2]->[1]);
    return ['ERROR', "Factoid $namespace.$keyword is locked. Cannot append."] if $self->is_locked($namespace, $keyword);
    my $action = $self->{pbot}->{factoids}->get_meta($namespace, $keyword, 'action');
    $action = "" if not defined $action;
    $action .= $text;
    $self->{pbot}->{factoids}->add_factoid('text', $namespace, 'Plang', $keyword, $action);
    return ['STRING', $action];
}

1;
