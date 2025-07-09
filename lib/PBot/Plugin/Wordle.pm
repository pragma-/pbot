# File: Wordle.pm
#
# Purpose: Wordle game. Try to guess a word by submitting words for clues about
# which letters belong to the word.

# SPDX-FileCopyrightText: 2024 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Wordle;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Storable qw(dclone);
use Time::Duration;
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
    USAGE     => 'Usage: wordle start [length [wordlist]] | custom <word> <channel> [wordlist] | guess <word> | guesses | letters | show | info | hard [on|off] | giveup',
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
        wlist   => '/wordle/american',
        glist   => ['insane', 'british', 'urban'],
    },
    insane => {
        name    => 'American English (Insanely Huge List)',
        prompt  => 'Guess the American English (Insanely Huge List) word!',
        wlist   => '/wordle/american-insane',
    },
    uncommon => {
        name    => 'American English (Uncommon)',
        prompt  => 'Guess the American English (Uncommon) word!',
        wlist   => '/wordle/american-uncommon',
        glist   => ['insane', 'british', 'urban'],
    },
    british => {
        name    => 'British English',
        prompt  => 'Guess the British English word!',
        wlist   => '/wordle/british',
        glist   => ['insane', 'british', 'urban'],
    },
    canadian => {
        name    => 'Canadian English',
        prompt  => 'Guess the Canadian English word!',
        wlist   => '/wordle/canadian',
        glist   => ['insane', 'british', 'urban'],
    },
    finnish => {
        name    => 'Finnish',
        prompt  => 'Arvaa suomenkielinen sana!',
        wlist   => '/wordle/finnish',
        accents => 'åäöšž',
        min_len => 5,
        max_len => 8,
    },
    french => {
        name    => 'French',
        prompt  => 'Devinez le mot Français !',
        wlist   => '/wordle/french',
        accents => 'éàèùçâêîôûëïü',
    },
    german => {
        name    => 'German',
        prompt  => 'Errate das deutsche Wort!',
        wlist   => '/wordle/german',
        accents => 'äöüß',
    },
    italian   => {
        name    => 'Italian',
        prompt  => 'Indovina la parola italiana!',
        wlist   => '/wordle/italian',
        accents => 'àèéìòù',
    },
    polish => {
        name    => 'Polish',
        prompt  => 'Odgadnij polskie słowo!',
        wlist   => '/wordle/polish',
        accents => 'ćńóśźżąęł',
        min_len => 5,
        max_len => 8,
    },
    spanish => {
        name    => 'Spanish',
        prompt  => '¡Adivina la palabra en español!',
        wlist   => '/wordle/spanish',
        accents => 'áéíóúüñ',
    },
    urban => {
        name    => 'Urban Dictionary',
        prompt  => 'Guess the Urban Dictionary word!',
        wlist   => '/wordle/urban',
        glist   => ['insane', 'british'],
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

        when ('info') {
            if (not defined $self->{$channel}->{wordle}) {
                return NO_WORDLE;
            }

            my $result = "Current wordlist: $self->{$channel}->{wordlist} ($self->{$channel}->{length}); guesses: $self->{$channel}->{guess_count}; nonwords: $self->{$channel}->{nonword_count}; invalids: $self->{$channel}->{invalid_count}";

            if ($self->{$channel}->{correct}) {
                my $solved_on = concise ago (time - $self->{$channel}->{solved_on});
                my $wordle = join '', $self->{$channel}->{wordle}->@*;
                $result .= "; solved by: $self->{$channel}->{solved_by} ($solved_on); word was: $wordle";
            } elsif ($self->{$channel}->{givenup}) {
                my $givenup_on = concise ago (time - $self->{$channel}->{givenup_on});
                my $wordle = join '', $self->{$channel}->{wordle}->@*;
                $result .= "; given up by: $self->{$channel}->{givenup_by} ($givenup_on); word was: $wordle";
            } else {
                my $guess = $self->{$channel}->{guesses}->[-1];
                $guess =~ s/[^\pL]//g;
                $result .= "; last guess: $guess";
            }

            return $result;
         }

        when ('giveup') {
            if (not defined $self->{$channel}->{wordle}) {
                return NO_WORDLE;
            }

            if ($self->{$channel}->{correct}) {
                my $solved_on = concise ago (time - $self->{$channel}->{solved_on});
                return "Wordle already solved by $self->{$channel}->{solved_by} ($solved_on)";
            }

            if ($self->{$channel}->{givenup}) {
                my $givenup_on = concise ago (time - $self->{$channel}->{givenup_on});
                my $wordle = join '', $self->{$channel}->{wordle}->@*;
                return "The word was $wordle. It was already given up by $self->{$channel}->{givenup_by} ($givenup_on).";
            }

            $self->{$channel}->{givenup} = 1;
            $self->{$channel}->{givenup_by} = $context->{nick};
            $self->{$channel}->{givenup_on} = time;
            my $wordle = join '', $self->{$channel}->{wordle}->@*;
            return "The word was $wordle. Better luck next time.";
        }

        when ('start') {
            if (@args > 2) {
                return "Invalid arguments; Usage: wordle start [word length [wordlist]]";
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

            if (defined $self->{$channel}->{wordle} && $self->{$channel}->{correct} == 0 && $self->{$channel}->{givenup} == 0) {
                return "There is already a Wordle underway! Use `wordle show` to see the current progress or `wordle giveup` to end it.";
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

            if (defined $self->{$custom_channel}->{wordle} && $self->{$custom_channel}->{correct} == 0 && $self->{$custom_channel}->{givenup} == 0) {
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
                return "Wordle already solved by $self->{$channel}->{solved_by}. " . $self->show_wordle($channel);
            }

            if ($self->{$channel}->{givenup}) {
                return "Wordle given up by $self->{$channel}->{givenup_by}.";
            }

            my $result = $self->guess_wordle($channel, $args[0]);

            if ($self->{$channel}->{correct}) {
                $self->{$channel}->{solved_by} = $context->{nick};
                $self->{$channel}->{solved_on} = time;
            }

            return $result;
        }

        when ('hard') {
            if (!@args || @args > 1) {
                return "Hard mode is " . ($self->{$channel}->{hard_mode} ? "enabled." : "disabled.");
            }

            if (lc $args[0] eq 'on') {
                $self->{$channel}->{hard_mode} = 1;
                return "Hard mode is now enabled.";
            } else {
                $self->{$channel}->{hard_mode} = 0;
                return "Hard mode is now disabled.";
            }
        }

        when ('guesses') {
            if (not defined $self->{$channel}->{wordle}) {
                return NO_WORDLE;
            }

            if (not $self->{$channel}->{guesses}->@*) {
                return 'No guesses yet.';
            }

            return join("$color{reset} ", $self->{$channel}->{guesses}->@*) . "$color{reset}";
        }

        when ('letters') {
            if (@args > 0) {
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
    $wordlist = $self->{datadir} . $wordlists{$wordlist}->{wlist};

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
    unless ($self->{$channel}->{wordlist} eq $wordlist
            && $self->{$channel}->{length} == $length
            && exists $self->{$channel}->{words}) {
        eval {
            $self->{$channel}->{words}     = $self->load_words($length, $wordlist);
            $self->{$channel}->{guesslist} = dclone $self->{$channel}->{words};
        };

        if ($@) {
            return "Failed to load words: $@";
        }
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

    unless ($self->{$channel}->{wordlist} eq $wordlist
            && $self->{$channel}->{length} == $length
            && exists $self->{$channel}->{words}) {
        if (exists $wordlists{$wordlist}->{glist}) {
            eval {
                foreach my $list ($wordlists{$wordlist}->{glist}->@*) {
                    $self->load_words($length, $list, $self->{$channel}->{guesslist});
                }
            };

            if ($@) {
                return "Failed to load words: $@";
            }
        }
    }

    $self->{$channel}->{wordlist}      = $wordlist;
    $self->{$channel}->{length}        = $length;
    $self->{$channel}->{wordle}        = \@wordle;
    $self->{$channel}->{greens}        = [];
    $self->{$channel}->{oranges}       = [];
    $self->{$channel}->{whites}        = [];
    $self->{$channel}->{letter_max}    = {};
    $self->{$channel}->{guess}         = '';
    $self->{$channel}->{guesses}       = [];
    $self->{$channel}->{correct}       = 0;
    $self->{$channel}->{givenup}       = 0;
    $self->{$channel}->{guess_count}   = 0;
    $self->{$channel}->{nonword_count} = 0;
    $self->{$channel}->{invalid_count} = 0;
    $self->{$channel}->{letters}       = {};

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
        $self->{$channel}->{invalid_count}++;
        return "Guess length ($guess_length) unequal to Wordle length ($wordle_length). Try again.";
    }

    my @guess  = split //, $guess;
    my @wordle = $self->{$channel}->{wordle}->@*;

    if ($self->{$channel}->{hard_mode}) {
        my %greens;
        my @greens = $self->{$channel}->{greens}->@*;

        for (my $i = 0; $i < @guess; $i++) {
            if ($self->{$channel}->{letters}->{$guess[$i]} == LETTER_INVALID) {
                $self->{$channel}->{invalid_count}++;
                return "Hard mode is enabled. $guess[$i] is not in the Wordle. Try again.";
            }

            if ($greens[$i]) {
                if ($guess[$i] ne $greens[$i]) {
                    $self->{$channel}->{invalid_count}++;
                    return "Hard mode is enabled. Position " . ($i + 1) . " must be $greens[$i]. Try again.";
                }
                $greens{$greens[$i]}++;
            }

            foreach my $orange ($self->{$channel}->{oranges}->@*) {
                if ($guess[$i] eq $orange->[$i]) {
                    $self->{$channel}->{invalid_count}++;
                    return "Hard mode is enabled. Position " . ($i + 1) . " can't be $guess[$i]. Try again.";
                }
            }
        }

        my %oranges;
        my $last_orange = $self->{$channel}->{oranges}->[$self->{$channel}->{oranges}->@* - 1];

        if ($last_orange) {
            $_ && $oranges{$_}++ foreach @$last_orange;

            foreach my $o (keys %oranges) {
                my $count = 0;
                $_ eq $o && $count++ foreach @guess;
                if ($count < $oranges{$o} + $greens{$o}) {
                    $self->{$channel}->{invalid_count}++;
                    return "Hard mode is enabled. There must be " . ($oranges{$o} + $greens{$o}) . " $o. Try again.";
                }
            }
        }

        foreach my $white ($self->{$channel}->{whites}->@*) {
            for (my $i = 0; $i < @guess; $i++) {
                if ($guess[$i] eq $white->[$i]) {
                    $self->{$channel}->{invalid_count}++;
                    return "Hard mode is enabled. Position " . ($i + 1) . " can't be $guess[$i]. Try again.";
                }

                if (not $self->{$channel}->{letter_max}->{$white->[$i]}) {
                    my $count = $greens{$white->[$i]} + $oranges{$white->[$i]};

                    if ($count) {
                        $self->{$channel}->{letter_max}->{$white->[$i]} = $count;
                    }
                }
            }
        }

        my %count;
        $count{$_}++ foreach @guess;

        foreach my $c (keys %count) {
            if ($self->{$channel}->{letter_max}->{$c} && $count{$c} > $self->{$channel}->{letter_max}->{$c}) {
                $self->{$channel}->{invalid_count}++;
                return "Hard mode is enabled. There can't be more than $self->{$channel}->{letter_max}->{$c} $c. Try again.";
            }
        }
    }

    if (not exists $self->{$channel}->{guesslist}->{$guess}) {
        $self->{$channel}->{nonword_count}++;
        return "I don't know that word. Try again.";
    }

    $self->{$channel}->{guess_count}++;

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
    my @oranges;
    my @whites;

    for (my $i = 0; $i < @wordle; $i++) {
        if ($guess[$i] eq $wordle[$i]) {
            $correct++;
            $result .= "$color{correct} $guess[$i]$color{correct_a}*";
            $self->{$channel}->{letters}->{$guess[$i]} = LETTER_CORRECT;
            $self->{$channel}->{greens}->[$i] = $guess[$i];
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
                if ($self->{$channel}->{letters}->{$guess[$i]} != LETTER_CORRECT) {
                    $self->{$channel}->{letters}->{$guess[$i]} = LETTER_PRESENT;
                }
                $oranges[$i] = $guess[$i];
            } else {
                $result .= "$color{invalid} $guess[$i] ";

                if ($self->{$channel}->{letters}->{$guess[$i]} == 0) {
                    $self->{$channel}->{letters}->{$guess[$i]} = LETTER_INVALID;
                }
                $whites[$i] = $guess[$i];
            }
        }
    }

    $self->{$channel}->{guess} = $result;

    push $self->{$channel}->{guesses}->@*, $result;
    push $self->{$channel}->{oranges}->@*, \@oranges;
    push $self->{$channel}->{whites}->@*, \@whites;

    if ($correct == length $guess) {
        $self->{$channel}->{correct} = 1;

        my $guesses = $self->{$channel}->{guess_count};
        $guesses = " Correct in $guesses guess" . ($guesses != 1 ? 'es! ' : '! ');

        my $nonwords = $self->{$channel}->{nonword_count};
        my $invalids = $self->{$channel}->{invalid_count};

        if ($nonwords || $invalids) {
            $guesses .= '(';

            if ($nonwords) {
                $guesses .= "$nonwords nonword";
                $guesses .= '; ' if $invalids;
            }

            if ($invalids) {
                $guesses .= "$invalids invalid";
            }
            $guesses .= ') ';
        }

        return $self->show_wordle($channel) . $guesses;
    } else {
        return $self->show_wordle($channel, 1);
    }
}

1;
