# File: WordMorph.pm
#
# Purpose: Word morph game. Solve a path between two words by changing one
# letter at a time. love > shot = love > lose > lost > loot > soot > shot.

# SPDX-FileCopyrightText: 2022 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::WordMorph;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Storable;
use Text::Levenshtein::XS 'distance';

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->add(
        name => 'wordmorph',
        help => 'Word Morph game! Solve a path between two words by changing one letter at a time: love > shot = love > lose > lost > loot > soot > shot.',
        subref => sub { $self->wordmorph(@_) },
    );

    $self->{db_path} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/wordmorph.db';

    $self->{db} = eval { $self->load_db() }
        or $self->{pbot}->{logger}->log($@);
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{commands}->remove('wordmorph');
}

use constant {
    USAGE => 'Usage: wordmorph start [steps to solve [word length]] | custom <word1> <word2> | solve <solution> | show | hint | giveup',
    NO_MORPH_AVAILABLE => "There is no word morph available. Use `wordmorph start [steps to solve [word length]]` to create one.",
    DB_UNAVAILABLE => "Word morph database not available.",
};

sub wordmorph {
    my ($self, $context) = @_;

    my @args = $self->{pbot}->{interpreter}->split_line($context->{arguments});

    my $command = shift @args;

    if (not length $command) {
        return USAGE;
    }

    my $channel = $context->{from};

    given ($command) {
        when ('hint') {
            if (not defined $self->{$channel}->{morph}) {
                return NO_MORPH_AVAILABLE;
            }

            $self->{$channel}->{hint}++;

            if ($self->{$channel}->{hint} > @{$self->{$channel}->{morph}} - 2) {
                $self->{$channel}->{hint} = @{$self->{$channel}->{morph}} - 2;
            }

            my @hints;

            for (my $i = 0; $i < $self->{$channel}->{hint}; $i++) {
                my $hint = '';

                if ($i > 0) {
                    my $word1 = $self->{$channel}->{morph}->[$i - 1];
                    my $word2 = $self->{$channel}->{morph}->[$i];

                    for (0 .. length $word1) {
                        if (substr($word1, $_, 1) eq substr($word2, $_, 1)) {
                            $hint .= substr($word1, $_, 1);
                        } else {
                            $hint .= "?";
                        }
                    }
                } else {
                    $hint = $self->{$channel}->{morph}->[$i];
                }

                push @hints, $hint;
            }

            my $hint = '_' x length $self->{$channel}->{morph}->[0];

            for (my $i = $self->{$channel}->{hint}; $i < @{$self->{$channel}->{morph}} - 1; $i++) {
                push @hints, $hint;
            }

            push @hints, $self->{$channel}->{morph}->[@{$self->{$channel}->{morph}} -1];

            return "Hint: " . join(' > ', @hints);
        }

        when ('show') {
            if (not defined $self->{$channel}->{morph}) {
                return NO_MORPH_AVAILABLE;
            }

            return "Current word morph: " . $self->show_morph_with_blanks($channel) . " (Fill in the blanks)";
        }

        when ('giveup') {
            if (not defined $self->{$channel}->{morph}) {
                return NO_MORPH_AVAILABLE;
            }

            my $solution = join ' > ', @{$self->{$channel}->{morph}};
            $self->{$channel}->{morph} = undef;
            return "The solution was $solution. Better luck next time.";
        }

        when ('start') {
            if (@args > 2) {
                return "Invalid arguments; Usage: wordmorph start [steps to solve [word length]]";
            }

            my $steps = 3;
            my $length = undef;

            if (defined $args[0]) {
                if ($args[0] !~ m/^[0-9]+$/ || $args[0] < 2 || $args[0] > 8) {
                    return "Invalid number of steps `$args[0]`; must be integer >= 2 and <= 8."
                }

                $steps = $args[0];
            }

            if (defined $args[1]) {
                if ($args[1] !~ m/^[0-9]+$/ || $args[1] < 3 || $args[1] > 8) {
                    return "Invalid word length `$args[1]`; must be integer >= 3 and <= 8."
                }

                $length = $args[1];
            }

            return DB_UNAVAILABLE if not $self->{db};

            my $attempts = 100;

            while (--$attempts > 0) {
                $self->{$channel}->{morph} = eval {
                    $self->make_morph_by_steps($self->{db}, $steps + 2, $length)
                };

                if (my $err = $@) {
                    next if $err eq "Too many attempts\n";
                    $self->{$channel}->{morph} = undef;
                    return $err;
                }

                last if @{$self->{$channel}->{morph}};
            }

            $self->set_up_new_morph($channel);
            return "New word morph: " . $self->show_morph_with_blanks($channel) . " (Fill in the blanks)";
        }

        when ('custom') {
            if (@args != 2) {
                return "Usage: wordmorph custom <word1> <word2>";
            }

            return DB_UNAVAILABLE if not $self->{db};
            my $morph = eval { makemorph($self->{db}, $args[0], $args[1]) } or return $@;
            $self->{$channel}->{morph} = $morph;
            $self->set_up_new_morph($channel);
            return "New word morph: " . $self->show_morph_with_blanks($channel) . " (Fill in the blanks)";
        }

        when ('solve') {
            if (not @args) {
                return "Usage: wordmorph solve <solution>";
            }

            if (not defined $self->{$channel}->{morph}) {
                return NO_MORPH_AVAILABLE;
            }

            my @solution = grep { length > 0 } split /\W/, join(' ', @args);

            if ($solution[0] ne $self->{$channel}->{word1}) {
                unshift @solution, $self->{$channel}->{word1};
            }

            if ($solution[$#solution] ne $self->{$channel}->{word2}) {
                push @solution, $self->{$channel}->{word2};
            }

            my $i = 0;

            my $last_word = $solution[$i];
            my $word;

            return DB_UNAVAILABLE if not $self->{db};

            if (not exists $self->{db}->{length $last_word}->{$last_word}) {
                return "I do not know this word `$last_word`.";
            }

            for ($i = 1; $i < @solution; $i++) {
                $word = $solution[$i];

                if (not exists $self->{db}->{length $word}->{$word}) {
                    return "I do not know this word `$word`.";
                }

                if (distance($word, $last_word) != 1) {
                    return "Wrong. `$word` does not follow from `$last_word`.";
                }

                $last_word = $word;
            }

            my $expected_steps = @{$self->{$channel}->{morph}};

            if (@solution > $expected_steps) {
                return "Almost! " . join(' > ', @solution) . " is too long.";
            }

            if (@solution == $expected_steps) {
                return "Correct! " . join(' > ', @solution);
            }

            if (@solution < $expected_steps) {
                return "Correct! " . join(' > ', @solution) . " is shorter than the expected solution. Congratulations!";
            }
        }

        default {
            return "Unknown command `$command`; " . USAGE;
        }
    }
}

sub load_db {
    my ($self) = @_;

    if (not -e $self->{db_path}) {
        die "Word morph database not available; run `wordmorph_gendb` to build it.\n";
    }

    return retrieve($self->{db_path});
}

sub show_morph_with_blanks {
    my ($self, $channel) = @_;

    my @middle;
    for (1 .. @{$self->{$channel}->{morph}} - 2) {
        push @middle, '_' x length $self->{$channel}->{word1};
    }

    return "$self->{$channel}->{word1} > " . join(' > ', @middle) . " > $self->{$channel}->{word2}";
}

sub set_up_new_morph {
    my ($self, $channel) = @_;
    $self->{$channel}->{word1} = $self->{$channel}->{morph}->[0];
    $self->{$channel}->{word2} = $self->{$channel}->{morph}->[$#{$self->{$channel}->{morph}}];
    $self->{$channel}->{hint} = 1;
}

sub make_morph_by_steps {
    my ($self, $db, $steps, $length) = @_;

    $length //= int(rand(3)) + 4;

    my @words = keys %{$db->{$length}};
    my $word  = $words[rand $#words];
    my $morph = [];

    push @$morph, $word;

    my $attempts = 100;

    while (--$attempts > 0) {
        my @list = @{$db->{$length}->{$word}};

        $word = $list[rand $#list];

        if (grep { $_ eq $word } @$morph) {
            next;
        }

        my $try = eval {
            my $left = $morph->[0];
            [transform($left, $word, $db->{length $left})]
        } or next;

        $morph = [];
        my $curr_steps = $steps;

        foreach my $word (@$try) {
            push @$morph, $word;

            if (--$curr_steps <= 0) {
                return $morph;
            }
        }
    }

    die "Too many attempts\n";
}

# the following subs are based on https://www.perlmonks.org/?node_id=558123

sub makemorph {
    my ($db, $left, $right) = @_;

    die "The length of given words are not equal.\n" if length($left) != length($right);

    $left  = lc $left;
    $right = lc $right;

    my $list = $db->{length $left};
    my $morph = eval { [transform($left, $right, $list)] } or die $@;
    return $morph;
}

sub transform {
    my ($left, $right, $list) = @_;

    my (@left, %left, @right, %right);      # @left and @right- arrays containing word relation trees: ([foo], [0, foe], [0, fou], [0, 1, fie] ...)
                                            # %left and %right - indices containing word offsets in arrays @left and @right

    $left[0] = [$left];
    $right[0] = [$right];
    $left{$left} = 0;
    $right{$right} = 0;

    my $leftstart  = 0;
    my $rightstart = 0;

    my @path;
    my (%leftstarts, %rightstarts);

    SEARCH:
    for (;;) {
        my @left_ids = $leftstart..$#left;                        # choose array of indices of new words
        $leftstart = $#left;
        die "Cannot create word morph! Bad word '$left' :(\n" if $leftstarts{$leftstart}++ > 2;  # finish search if the path could not be found
        for my $id (@left_ids) {                                  # come through all new words
            my @prefix   = @{$left[$id]};
            my $searched = pop @prefix;
            push @prefix, $id;
            foreach my $word (@{$list->{$searched}}) {
                next if $left{$word};                             # skip words which are already in the tree
                push @left, [@prefix, $word];
                $left{$word} = $#left;                            # add new word to array and index
                if ( defined(my $r_id = $right{$word}) ) {        # and check if the word appears in right index. if yes...
                    my @end = reverse(print_rel($r_id, \@right));
                    shift @end;
                    @path = (print_rel($#left, \@left), @end);    # build the path between the words
                    last SEARCH;                                  # and finish the search

                }
            }
        }

        my @right_ids = $rightstart..$#right;                     # all the same :) the tree is build from both ends to speed up the process
        $rightstart = $#right;
        die "Cannot create word morph! Bad word '$right'\n" if $rightstarts{$rightstart}++ > 2;
        for my $id (@right_ids) {                                 # build right relational table
            my @prefix   = @{$right[$id]};
            my $searched = pop @prefix;
            push @prefix, $id;
            foreach my $word (@{$list->{$searched}}) {
                next if $right{$word};
                push @right, [@prefix, $word];
                $right{$word} = $#right;
                if ( defined(my $l_id = $left{$word}) ) {
                    my @end = reverse print_rel($#right, \@right);
                    shift @end;
                    @path = (print_rel($l_id, \@left), @end);
                    last SEARCH;
                }
            }
        }
    }
    return @path;
}

sub print_rel {
    my ($id, $ary) = @_;

    my @rel = @{$ary->[$id]};
    my @line;

    push @line, (pop @rel);

    foreach my $ref_id (reverse @rel) {
        unshift @line, $ary->[$ref_id]->[-1];
    }

    return wantarray ? @line : join "\n", @line, "";
}

1;
