# File: Wordle.pm
#
# Purpose: Wordle game. Try to guess a word by submitting words for clues about
# which letters belong to the word.

# SPDX-FileCopyrightText: 2024 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Wordle;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use utf8;

sub initialize($self, %conf) {
    $self->{pbot}->{commands}->add(
        name => 'wordle',
        help => 'Wordle game! Guess target word by submitting words for clues about which letters belong to the word!',
        subref => sub { $self->wordle(@_) },
    );

    $self->{datadir} = $self->{pbot}->{registry}->get_value('general', 'data_dir');
}

sub unload($self) {
    $self->{pbot}->{commands}->remove('wordle');
}

use constant {
    USAGE     => 'Usage: wordle start [length [wordlist]] | custom <word> <channel> [wordlist] | guess <word> | letters | show | giveup',
    NO_WORDLE => 'There is no Wordle yet. Use `wordle start` to begin a game.',

    DEFAULT_LIST       => 'american',
    DEFAULT_LENGTH     => 5,
    DEFAULT_MIN_LENGTH => 3,
    DEFAULT_MAX_LENGTH => 22,

    LETTER_CORRECT => 1,
    LETTER_PRESENT => 2,
    LETTER_INVALID => 3,
};

my %wordlists = (
    american => {
        name    => 'American English',
        prompt  => 'Guess the American English word!',
        list    => '/wordle/american',
        supp    => 'insane',
    },
    insane => {
        name    => 'American English (Insanely Huge List)',
        prompt  => 'Guess the American English (Insanely Huge List) word!',
        list    => '/wordle/american-insane',
    },
    british => {
        name    => 'British English',
        prompt  => 'Guess the British English word!',
        list    => '/wordle/british',
        supp    => 'insane',
    },
    canadian => {
        name    => 'Canadian English',
        prompt  => 'Guess the Canadian English word!',
        list    => '/wordle/canadian',
        supp    => 'insane',
    },
    finnish => {
        name    => 'Finnish',
        prompt  => 'Arvaa suomenkielinen sana!',
        list    => '/wordle/finnish',
        accents => 'åäöšž',
        min_len => 5,
        max_len => 8,
    },
    french => {
        name    => 'French',
        prompt  => 'Devinez le mot Français !',
        list    => '/wordle/french',
        accents => 'éàèùçâêîôûëïü',
    },
    german => {
        name    => 'German',
        prompt  => 'Erraten Sie das Deutsches Wort!',
        list    => '/wordle/german',
        accents => 'äöüß',
    },
    italian   => {
        name    => 'Italian',
        prompt  => 'Indovina la parola italiana!',
        list    => '/wordle/italian',
        accents => 'èéìòù',
    },
    polish => {
        name    => 'Polish',
        prompt  => 'Odgadnij polskie słowo!',
        list    => '/wordle/polish',
        accents => 'ćńóśźżąęł',
        min_len => 5,
        max_len => 8,
    },
    spanish => {
        name    => 'Spanish',
        prompt  => '¡Adivina la palabra en español!',
        list    => '/wordle/spanish',
        accents => 'áéíóúüñ',
    },
    urban => {
        name    => 'Urban Dictionary',
        prompt  => 'Guess the Urban Dictionary word!',
        list    => '/wordle/urban',
        supp    => 'insane',
    },
);

my %color = (
    correct   => "\x0301,03",
    correct_a => "\x0303,03",

    present   => "\x0301,07",
    present_a => "\x0307,07",

    invalid   => "\x0301,15",

    reset     => "\x0F",
);

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

            return $self->show_wordle($channel, 1);
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
            if (@args > 2) {
                return "Invalid arguments; Usage: wordle start [word length [wordlist]]";
            }

            if (defined $self->{$channel}->{wordle} && $self->{$channel}->{correct} == 0) {
                return "There is already a Wordle underway! Use `wordle show` to see the current progress or `wordle giveup` to end it.";
            }

            my $length = DEFAULT_LENGTH;

            my $wordlist = $args[1] // DEFAULT_LIST;

            if (not exists $wordlists{$wordlist}) {
                return 'Invalid wordlist; options are: ' . (join ', ', sort keys %wordlists);
            }

            if (defined $args[0]) {
                my $min = $wordlists{$wordlist}->{min_len} // DEFAULT_MIN_LENGTH;
                my $max = $wordlists{$wordlist}->{max_len} // DEFAULT_MAX_LENGTH;

                if ($args[0] !~ m/^[0-9]+$/ || $args[0] < $min || $args[0] > $max) {
                    return "Invalid word length `$args[0]` for $wordlists{$wordlist}->{name} words; must be integer >= $min and <= $max.";
                }

                $length = $args[0];
            }

            return $self->make_wordle($channel, $length, undef, $wordlist);
        }

        when ('custom') {
            if (@args < 2 || @args > 3) {
                return "Usage: wordle custom <word> <channel> [wordlist]";
            }

            my $custom_word     = $args[0];
            my $custom_channel  = $args[1];
            my $custom_wordlist = $args[2];
            my $length          = length $custom_word;

            my $wordlist = $custom_wordlist // DEFAULT_LIST;

            if (not exists $wordlists{$wordlist}) {
                return 'Invalid wordlist; options are: ' . (join ', ', sort keys %wordlists);
            }

            my $min = $wordlists{$wordlist}->{min_len} // DEFAULT_MIN_LENGTH;
            my $max = $wordlists{$wordlist}->{max_len} // DEFAULT_MAX_LENGTH;

            if ($length < $min || $length > $max) {
                return "Invalid word length for $wordlists{$wordlist}->{name} words; must be >= $min and <= $max.";
            }

            if (not $self->{pbot}->{channels}->is_active($custom_channel)) {
                return "I'm not on that channel!";
            }

            if (defined $self->{$custom_channel}->{wordle} && $self->{$custom_channel}->{correct} == 0) {
                return "There is already a Wordle underway! Use `wordle show` to see the current progress or `wordle giveup` to end it.";
            }

            $custom_word =~ s/ß/ẞ/g; # avoid uppercasing to SS in German
            my $result = $self->make_wordle($custom_channel, $length, uc $custom_word, $wordlist);

            if ($result !~ /Legend: /) {
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
                message    => "$result (started by $context->{nick})",
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

            return $self->show_letters($channel);
        }

        default {
            return "Unknown command `$command`; " . USAGE;
        }
    }
}

sub load_words($self, $length, $wordlist = DEFAULT_LIST, $words = undef) {
    $wordlist = $self->{datadir} . $wordlists{$wordlist}->{list};

    if (not -e $wordlist) {
        die "Wordle database `" . $wordlist . "` not available.\n";
    }

    open my $fh, '<:encoding(UTF-8)', $wordlist or die "Failed to open Wordle database.";

    $words //= {};

    while (my $line = <$fh>) {
        chomp $line;
        if (length $line == $length) {
            $line =~ s/ß/ẞ/g; # avoid uppercasing to SS in German
            $words->{uc $line} = 1;
        }
    }

    close $fh;
    return $words;
}

sub make_wordle($self, $channel, $length, $word = undef, $wordlist = DEFAULT_LIST) {
    eval {
        $self->{$channel}->{words} = $self->load_words($length, $wordlist);
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

    if (not @wordle) {
        return "Failed to find a suitable word.";
    }

    if (exists $wordlists{$wordlist}->{supp}) {
        eval {
            $self->load_words($length, $wordlists{$wordlist}->{supp}, $self->{$channel}->{words});
        };

        if ($@) {
            return "Failed to load words: $@";
        }
    }

    $self->{$channel}->{wordle}      = \@wordle;
    $self->{$channel}->{guess}       = '';
    $self->{$channel}->{correct}     = 0;
    $self->{$channel}->{guess_count} = 0;
    $self->{$channel}->{letters}     = {};

    foreach my $letter ('A'..'Z') {
        $self->{$channel}->{letters}->{$letter} = 0;
    }

    if (exists $wordlists{$wordlist}->{accents}) {
        foreach my $letter (split //, $wordlists{$wordlist}->{accents}) {
            $letter =~ s/ß/ẞ/g; # avoid uppercasing to SS in German
            $letter = uc $letter;
            $self->{$channel}->{letters}->{$letter} = 0;
        }
    }

    $self->{$channel}->{guess}  = $color{invalid};
    $self->{$channel}->{guess} .= ' ? ' x $self->{$channel}->{wordle}->@*;
    $self->{$channel}->{guess} .= $color{reset};

    return $self->show_wordle($channel) . " $wordlists{$wordlist}->{prompt} Legend: $color{invalid}X $color{reset} not in word; $color{present}X$color{present_a}?$color{reset} wrong position; $color{correct}X$color{correct_a}*$color{reset} correct position";
}

sub show_letters($self, $channel) {
    my $result = 'Letters: ';

    foreach my $letter (sort keys $self->{$channel}->{letters}->%*) {
        if ($self->{$channel}->{letters}->{$letter} == LETTER_CORRECT) {
            $result .= "$color{correct}$letter$color{correct_a}*";
            $result .= "$color{reset} ";
        } elsif ($self->{$channel}->{letters}->{$letter} == LETTER_PRESENT) {
            $result .= "$color{present}$letter$color{present_a}?";
            $result .= "$color{reset} ";
        } elsif ($self->{$channel}->{letters}->{$letter} == 0) {
            $result .= "$letter ";
        }
    }

    return $result . "$color{reset}";
}

sub show_wordle($self, $channel, $with_letters = 0) {
	if ($with_letters) {
		return $self->{$channel}->{guess} . "$color{reset} " . $self->show_letters($channel);
	} else {
		return $self->{$channel}->{guess} . "$color{reset}";
	}
}

sub guess_wordle($self, $channel, $guess) {
    $guess =~ s/ß/ẞ/g; # avoid uppercasing to SS in German
    $guess = uc $guess;

    if (length $guess != $self->{$channel}->{wordle}->@*) {
        my $guess_length  = length $guess;
        my $wordle_length = $self->{$channel}->{wordle}->@*;
        return "Guess length ($guess_length) unequal to Wordle length ($wordle_length). Try again.";
    }

    if (not exists $self->{$channel}->{words}->{$guess}) {
        return "I don't know that word. Try again."
    }

    $self->{$channel}->{guess_count}++;

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

    my $result = '';
    my $correct = 0;

    for (my $i = 0; $i < @wordle; $i++) {
        if ($guess[$i] eq $wordle[$i]) {
            $correct++;
            $result .= "$color{correct} $guess[$i]$color{correct_a}*";
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
                $result .= "$color{present} $guess[$i]$color{present_a}?";
                $self->{$channel}->{letters}->{$guess[$i]} = LETTER_PRESENT;
            } else {
                $result .= "$color{invalid} $guess[$i] ";

                if ($self->{$channel}->{letters}->{$guess[$i]} == 0) {
                    $self->{$channel}->{letters}->{$guess[$i]} = LETTER_INVALID;
                }
            }
        }
    }

    $self->{$channel}->{guess} = $result;

    if ($correct == length $guess) {
        $self->{$channel}->{correct} = 1;
        my $guesses = $self->{$channel}->{guess_count};
        return $self->show_wordle($channel) . " Correct in $guesses guess" . ($guesses != 1 ? 'es! ' : '! ');
    } else {
        return $self->show_wordle($channel, 1);
    }
}

1;
