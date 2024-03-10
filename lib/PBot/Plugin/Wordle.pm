# File: Wordle.pm
#
# Purpose: Wordle game. Try to guess a word by submitting words for clues about
# which letters belong to the word.

# SPDX-FileCopyrightText: 2024 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Wordle;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize($self, %conf) {
    $self->{pbot}->{commands}->add(
        name => 'wordle',
        help => 'Wordle game! Guess target word by submitting words for clues about which letters belong to the word!',
        subref => sub { $self->wordle(@_) },
    );
}

sub unload($self) {
    $self->{pbot}->{commands}->remove('wordle');
}

use constant {
    USAGE => 'Usage: wordle start [word length] | custom <word> <channel> | guess <word> | letters | show | giveup',
    NO_WORDLE => 'There is no Wordle yet. Use `wordle start` to begin a game.',
    DEFAULT_LENGTH => 5,
    MIN_LENGTH => 3,
    MAX_LENGTH => 10,
    WORDLIST => '/usr/share/dict/words',
    LETTER_CORRECT => 1,
    LETTER_PRESENT => 2,
    LETTER_INVALID => 3,
};

sub wordle($self, $context) {
    my @args = $self->{pbot}->{interpreter}->split_line($context->{arguments});

    my $command = shift @args;

    if (not length $command) {
        return USAGE;
    }

    my $channel = $context->{from};

    given ($command) {
        when ('show') {
            if (not defined $self->{$channel}->{wordle}) {
                return NO_WORDLE;
            }

            return $self->show_wordle($channel);
        }

        when ('giveup') {
            if (not defined $self->{$channel}->{wordle}) {
                return NO_WORDLE;
            }

            my $wordle = join '', $self->{$channel}->{wordle}->@*;
            $self->{$channel}->{wordle} = undef;

            return "The word was $wordle. Better luck next time.";
        }

        when ('start') {
            if (@args > 1) {
                return "Invalid arguments; Usage: wordle start [word length]";
            }

            if (defined $self->{$channel}->{wordle} && $self->{$channel}->{correct} == 0) {
                return "There is already a Wordle underway! Use `wordle show` to see the current progress or `wordle giveup` to end it.";
            }

            my $length = DEFAULT_LENGTH;

            if (defined $args[0]) {
                if ($args[0] !~ m/^[0-9]+$/ || $args[0] < MIN_LENGTH || $args[0] > MAX_LENGTH) {
                    return "Invalid word length `$args[0]`; must be integer >= ".MIN_LENGTH." and <= ".MAX_LENGTH.".";
                }

                $length = $args[0];
            }

            return $self->make_wordle($channel, $length);
        }

        when ('custom') {
            if (@args != 2) {
                return "Usage: wordle custom <word> <channel>";
            }

            my $custom_word    = $args[0];
            my $custom_channel = $args[1];
            my $length         = length $custom_word;

            if ($custom_word !~ /[a-z]/) {
                return "Word must be all lowercase and cannot contain numbers or symbols.";
            }

            if ($length < MIN_LENGTH || $length > MAX_LENGTH) {
                return "Invalid word length; must be >= ".MIN_LENGTH." and <= ".MAX_LENGTH.".";
            }

            if (not $self->{pbot}->{channels}->is_active($custom_channel)) {
                return "I'm not on that channel!";
            }

            if (defined $self->{$custom_channel}->{wordle} && $self->{$custom_channel}->{correct} == 0) {
                return "There is already a Wordle underway! Use `wordle show` to see the current progress or `wordle giveup` to end it.";
            }

            my $result = $self->make_wordle($custom_channel, $length, uc $custom_word);

            if ($result !~ /^Wordle:/) {
                return $result;
            }

            my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

            my $message = {
                nick       => $botnick,
                user       => 'wordle',
                host       => 'localhost',
                hostmask   => "$botnick!wordle\@localhost",
                command    => 'wordle',
                keyword    => 'wordle',
                checkflood => 1,
                message    => "$context->{nick} started a custom $result",
            };

            $self->{pbot}->{interpreter}->add_message_to_output_queue($custom_channel, $message, 0);

            return "Custom Wordle started!";
        }

        when ('guess') {
            if (!@args || @args > 1) {
                return "Usage: wordle guess <word>";
            }

            if (not defined $self->{$channel}->{wordle}) {
                return NO_WORDLE;
            }

            if ($self->{$channel}->{correct}) {
                return "Wordle already solved. " . $self->show_wordle($channel);
            }

            return $self->guess_wordle($channel, $args[0]);
        }

        when ('letters') {
            if (@args > 1) {
                return "Usage: wordle letters";
            }

            if (not defined $self->{$channel}->{wordle}) {
                return NO_WORDLE;
            }

            my $result = 'Good/unknown letters: ';

            foreach my $letter (sort keys $self->{$channel}->{letters}->%*) {
                if ($self->{$channel}->{letters}->{$letter} == LETTER_CORRECT) {
                    $result .= "*$letter* ";
                } elsif ($self->{$channel}->{letters}->{$letter} == LETTER_PRESENT) {
                    $result .= "?$letter? ";
                } elsif ($self->{$channel}->{letters}->{$letter} == 0) {
                    $result .= "$letter ";
                }
            }

            return $result;
        }

        default {
            return "Unknown command `$command`; " . USAGE;
        }
    }
}

sub load_words($self, $length) {
    if (not -e WORDLIST) {
        die "Wordle database `" . WORDLIST . "` not available. Set WORDLIST to a valid location of a wordlist file.\n";
    }

    open my $fh, '<', WORDLIST or die "Failed to open Wordle database.";

    my %words;

    while (my $line = <$fh>) {
        chomp $line;
        next if $line !~ /^[a-z]+$/;

        if (length $line == $length) {
            $words{uc $line} = 1;
        }
    }

    close $fh;
    return \%words;
}

sub make_wordle($self, $channel, $length, $word = undef) {
    eval {
        $self->{$channel}->{words} = $self->load_words($length);
    };

    if ($@) {
        return "Failed to load words: $@";
    }

    my @wordle;

    if (defined $word) {
        if (not exists $self->{$channel}->{words}->{$word}) {
            return "I don't know that word.";
        }
        @wordle = split //, $word;
    } else {
        my @words = keys $self->{$channel}->{words}->%*;
        @wordle = split //, $words[rand @words];
    }

    $self->{$channel}->{wordle}      = \@wordle;
    $self->{$channel}->{guesses}     = [];
    $self->{$channel}->{correct}     = 0;
    $self->{$channel}->{guess_count} = 0;
    $self->{$channel}->{letters}     = {};

    foreach my $letter ('A'..'Z') {
        $self->{$channel}->{letters}->{$letter} = 0;
    }

    push $self->{$channel}->{guesses}->@*, '? ' x $self->{$channel}->{wordle}->@*;

    return "Wordle: " . $self->show_wordle($channel) . " (Guess the word! Legend: X not in word; ?X? wrong position; *X* correct position)";
}

sub show_wordle($self, $channel) {
    return join ' -> ', $self->{$channel}->{guesses}->@*;
}

sub guess_wordle($self, $channel, $guess) {
    if (length $guess != $self->{$channel}->{wordle}->@*) {
        return "The length of your guess does not match length of current Wordle. Try again.";
    }

    $guess = uc $guess;

    if (not exists $self->{$channel}->{words}->{$guess}) {
        return "I don't know that word. Try again."
    }

    $self->{$channel}->{guess_count}++;

    if ($self->{$channel}->{guess_count} == 1) {
        # remove initial "? ? ? ? ?"
        shift $self->{$channel}->{guesses}->@*;
    }

    my @guess  = split //, $guess;
    my @wordle = $self->{$channel}->{wordle}->@*;

    my %count;
    my %seen;
    my %correct;

    for (my $i = 0; $i < @wordle; $i++) {
        $count{$wordle[$i]}++;
        $seen{$wordle[$i]} = 0;
        $correct{$wordle[$i]} = 0 unless exists $correct{$wordle[$i]};

        if ($guess[$i] eq $wordle[$i]) {
            $correct{$guess[$i]}++;
        }
    }

    my @result;
    my $correct = 0;

    for (my $i = 0; $i < @wordle; $i++) {
        if ($guess[$i] eq $wordle[$i]) {
            $correct++;
            push @result, "*$guess[$i]*";
            $self->{$channel}->{letters}->{$guess[$i]} = LETTER_CORRECT;
        } else {
            my $present = 0;

            for (my $j = 0; $j < @wordle; $j++) {
                if ($wordle[$j] eq $guess[$i]) {
                    if ($seen{$wordle[$j]} + $correct{$wordle[$j]} < $count{$wordle[$j]}) {
                        $present = 1;
                    }

                    $seen{$wordle[$j]}++;
                    last;
                }
            }

            if ($present) {
                push @result, "?$guess[$i]?";
                $self->{$channel}->{letters}->{$guess[$i]} = LETTER_PRESENT;
            } else {
                push @result, "$guess[$i]";

                if ($self->{$channel}->{letters}->{$guess[$i]} == 0) {
                    $self->{$channel}->{letters}->{$guess[$i]} = LETTER_INVALID;
                }
            }
        }
    }

    push $self->{$channel}->{guesses}->@*, join ' ', @result;

    if ($correct == length $guess) {
        $self->{$channel}->{correct} = 1;

        my $guesses = $self->{$channel}->{guess_count};

        return "Correct in $guesses guess" . ($guesses != 1 ? 'es! ' : '! ') . $self->show_wordle($channel);
    } else {
        return $self->show_wordle($channel);
    }
}

1;
