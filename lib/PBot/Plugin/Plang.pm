# File: Plang.pm
#
# Purpose: Scripting language for creating advanced PBot factoids
# and interacting with various internal PBot APIs.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Plang;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;

    # load Plang modules
    my $path = $self->{pbot}->{registry}->get_value('general', 'plang_dir') // 'Plang';
    unshift @INC, "$path/lib" if not grep { $_ eq "$path/lib" } @INC;

    # require all the Plang .pm modules for Module::Refresh
    require "$path/Interpreter.pm";
    require "$path/AstInterpreter.pm";
    require "$path/Grammar.pm"; # FIXME: Module::Refresh doesn't like this one
    require "$path/Parser.pm";
    require "$path/Lexer.pm";
    require "$path/Types.pm";
    require "$path/Validator.pm";

    # regset plang.debug <AST,VARS,FUNCS,etc>
    # Plugin must be reloaded for this value to take effect.
    my $debug = $self->{pbot}->{registry}->get_value('plang', 'debug') // '';

    # create our Plang interpreter object
    $self->{plang} = Plang::Interpreter->new(embedded => 1, debug => $debug);

    # register some PBot-specific built-in functions
    $self->{plang}->add_builtin_function('factset', # function name
        # parameters are [[type, param1 name, default arg], [type, param2 name, default arg], ...]
        [
            [['TYPE', 'String'], 'channel', undef], # param 1
            [['TYPE', 'String'], 'keyword', undef], # param 2
            [['TYPE', 'String'], 'text',    undef], # param 3
        ],
        ['TYPE', 'String'],                         # return type
        sub { $self->plang_builtin_factset(@_) },   # builtin subref
        sub { $self->plang_validate_builtin_factset(@_) } # type-checker subref
    );

    $self->{plang}->add_builtin_function('factget',
        [
            [['TYPE', 'String'], 'channel', undef],
            [['TYPE', 'String'], 'keyword', undef],
            [['TYPE', 'String'], 'meta', [['TYPE', 'String'], 'action']]
        ],
        ['TYPEUNION', [['TYPE', 'String'], ['TYPE', 'Null']]],
        sub { $self->plang_builtin_factget(@_) },
        sub { $self->plang_validate_builtin_factget(@_) },
    );

    $self->{plang}->add_builtin_function('factappend',
        [
            [['TYPE', 'String'], 'channel', undef],
            [['TYPE', 'String'], 'keyword', undef],
            [['TYPE', 'String'], 'text', undef]
        ],
        ['TYPE', 'String'],
        sub { $self->plang_builtin_factappend(@_) },
        sub { $self->plang_validate_builtin_factappend(@_) },
    );

    $self->{plang}->add_builtin_function('userget',
        [
            [['TYPE', 'String'], 'name', undef]
        ],
        ['TYPEUNION', [['TYPE', 'Map'], ['TYPE', 'Null']]],
        sub { $self->plang_builtin_userget(@_) },
        sub { $self->plang_validate_builtin_userget(@_) },
    );

    # override the built-in `print` function to send to our output buffer instead
    $self->{plang}->add_builtin_function('print',
        [
            [['TYPE', 'Any'], 'expr', undef],
            [['TYPE', 'String'], 'end', [['TYPE', 'String'], "\n"]]
        ],
        ['TYPE', 'Null'],
        sub { $self->plang_builtin_print(@_) },
        sub { $self->plang_validate_builtin_print(@_) },
    );

    # register the `plang` command
    $self->{pbot}->{commands}->register(sub { $self->cmd_plang(@_) }, "plang", 0);

    # register the `plangrepl` command (does not reset environment)
    $self->{pbot}->{commands}->register(sub { $self->cmd_plangrepl(@_) }, "plangrepl", 0);
}

# runs when plugin is unloaded
sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("plang");
}

sub cmd_plang {
    my ($self, $context) = @_;

    my $usage = "Usage: plang <code>; see https://github.com/pragma-/Plang and https://github.com/pragma-/pbot/blob/master/doc/Plugins/Plang.md";
    return $usage if not length $context->{arguments};

    $self->{output} = "";  # collect output of the embedded Plang program

    eval {
        my $result =  $self->{plang}->interpret_string($context->{arguments});

        # check to see if we need to append final result to output
        if (defined $result->[1]) {
            $self->{output} .= $self->{plang}->{interpreter}->output_value($result, literal => 1);
        }
    };

    if ($@) {
        $self->{output} .= $@;
    }

    # return the output
    return length $self->{output} ? $self->{output} : "No output.";
}

sub cmd_plangrepl {
    my ($self, $context) = @_;

    my $usage = "Usage: plangrepl <code>; see https://github.com/pragma-/Plang and https://github.com/pragma-/pbot/blob/master/doc/Plugins/Plang.md";
    return $usage if not length $context->{arguments};

    $self->{output} = "";  # collect output of the embedded Plang program

    eval {
        my $result = $self->{plang}->interpret_string($context->{arguments}, repl => 1);

        # check to see if we need to append final result to output
        $self->{output} .= $self->{plang}->{interpreter}->output_value($result, repl => 1) if defined $result->[1];
    };

    if ($@) {
        $self->{output} .= $@;
    }

    # return the output
    return length $self->{output} ? $self->{output} : "No output.";
}

# overridden `print` built-in
sub plang_builtin_print {
    my ($self, $plang, $context, $name, $arguments) = @_;
    my ($expr, $end) = ($plang->output_value($arguments->[0]), $arguments->[1]->[1]);
    $self->{output} .= "$expr$end";
    return [['TYPE', 'Null'], undef];
}

sub plang_validate_builtin_print {
    return [['TYPE', 'Null'], undef];
}

# our custom PBot built-in functions for Plang

sub is_locked {
    my ($self, $channel, $keyword) = @_;
    return $self->{pbot}->{factoids}->{data}->get_meta($channel, $keyword, 'locked');
}

sub plang_builtin_factget {
    my ($self, $plang, $context, $name, $arguments) = @_;
    my ($channel, $keyword, $meta) = ($arguments->[0]->[1], $arguments->[1]->[1], $arguments->[2]->[1]);
    my $result = $self->{pbot}->{factoids}->{data}->get_meta($channel, $keyword, $meta);
    if (defined $result) {
        return [['TYPE', 'String'], $result];
    } else {
        return [['TYPE', 'Null'], undef];
    }
}

sub plang_validate_builtin_factget {
    return [['TYPE', 'String'], ""];
}

sub plang_builtin_factset {
    my ($self, $plang, $context, $name, $arguments) = @_;
    my ($channel, $keyword, $text) = ($arguments->[0]->[1], $arguments->[1]->[1], $arguments->[2]->[1]);
    die "Factoid $channel.$keyword is locked. Cannot set.\n" if $self->is_locked($channel, $keyword);
    $self->{pbot}->{factoids}->{data}->add_factoid('text', $channel, 'Plang', $keyword, $text);
    return [['TYPE', 'String'], $text];
}

sub plang_validate_builtin_factset {
    return [['TYPE', 'String'], ""];
}

sub plang_builtin_factappend {
    my ($self, $plang, $context, $name, $arguments) = @_;
    my ($channel, $keyword, $text) = ($arguments->[0]->[1], $arguments->[1]->[1], $arguments->[2]->[1]);
    die "Factoid $channel.$keyword is locked. Cannot append.\n" if $self->is_locked($channel, $keyword);
    my $action = $self->{pbot}->{factoids}->{data}->get_meta($channel, $keyword, 'action');
    $action = "" if not defined $action;
    $action .= $text;
    $self->{pbot}->{factoids}->{data}->add_factoid('text', $channel, 'Plang', $keyword, $action);
    return [['TYPE', 'String'], $action];
}

sub plang_validate_builtin_factappend {
    return [['TYPE', 'String'], ""];
}

sub plang_builtin_userget {
    my ($self, $plang, $context, $name, $arguments) = @_;
    my ($username) = ($arguments->[0], $arguments->[1]);

    my $user = $self->{pbot}->{users}->{storage}->get_data($username->[1]);

    if (not defined $user) {
        return [['TYPE', 'Null'], undef];
    }

    my $hash = { %$user };
    $hash->{password} = '<private>';

    while (my ($key, $value) = each %$hash) {
        $hash->{$key} = [['TYPE', 'String'], $value];
    }

    return [['TYPE', 'Map'], $hash];
}

sub plang_validate_builtin_userget {
    return [['TYPE', 'Map'], {}];
}

1;
