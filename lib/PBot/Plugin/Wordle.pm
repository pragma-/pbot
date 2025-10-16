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
    USAGE     => 'Usage: wordle start [length [wordlist [game-id]]] | custom <word> <channel> [wordlist [game-id]] | guess <word> [game-id] | select [game-id] | list | guesses [game-id] | letters [game-id] | show [game-id] | info [game-id] | hard [on|off] [game-id] | giveup [game-id]',

    NO_WORDLE => 'There is no Wordle yet. Use `wordle start` to begin a game.',
    NO_GAMEID => 'That game-id does not exist. Use `wordle start <length> <language> <gameid>` to begin a game with that id.',

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
            if (@args > 1) {
                return "Usage: wordle show [game-id]";
            }

            my $gameid = $self->gameid($args[0], $context);

            if (not defined $gameid) {
                return NO_GAMEID;
            }

            my $game = $gameid ne 'main' ? "($gameid) " : '';

            if (not defined $self->{$channel}->{$gameid}->{wordle}) {
                return $game . NO_WORDLE;
            }

            return $game . $self->show_wordle($channel, $gameid, 1);
        }

        when ('players') {
            my @players;
            foreach my $id (keys %{$self->{players}->{$channel}}) {
                my $h = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_id($id);
                my ($n) = $h =~ m/^([^!]+)/;
                $n =~ s/(.)/$1\x{feff}/;  # dehighlight
                push @players, "$n: " . $self->{players}->{$channel}->{$id}->{gameid};
            }

            if (not @players) {
                return "No players yet.";
            } else {
                return "Players: " . (join ', ', sort @players);
            }
        }

        when ('list') {
            if (@args != 0) {
                return "Usage: wordle list";
            }

            my @games;

            foreach my $gameid (keys $self->{$channel}->%*) {
                my $length = $self->{$channel}->{$gameid}->{length};
                my $wordlist = $self->{$channel}->{$gameid}->{wordlist};
                my $solved = $self->{$channel}->{$gameid}->{correct} ? ', solved' : '';
                my $givenup = $self->{$channel}->{$gameid}->{givenup} ? ', given up' : '';
                push @games, "$gameid ($wordlist:$length$solved$givenup)";

            }

            if (not @games) {
                push @games, 'none';
            }

            my $games = join ', ', sort @games;

            return "Available Wordles: $games";
        }

        when ('select') {
            if (@args > 1) {
                return "Usage: wordle select [game-id]";
            }

            my $gameid = $args[0];

            if (not defined $gameid) {
                $gameid = 'main';
            } else {
                if (not exists $self->{$channel}->{$gameid}) {
                    return "$context->{nick}: " . NO_GAMEID;
                }
            }

            $self->{players}->{$channel}->{$context->{message_account}}->{gameid} = $gameid;

            return "$context->{nick} is now playing the $gameid Wordle!";
        }

        when ('info') {
            if (@args > 1) {
                return "Usage: wordle info [game-id]";
            }

            my $gameid = $self->gameid($args[0], $context);

            if (not defined $gameid) {
                return NO_GAMEID;
            }

            my $game = $gameid ne 'main' ? "($gameid) " : '';

            if (not defined $self->{$channel}->{$gameid}->{wordle}) {
                return $game . NO_WORDLE;
            }

            my $started = concise ago time - $self->{$channel}->{$gameid}->{start_time};
            my $hard = $self->{$channel}->{$gameid}->{hard_mode} ? 'on' : 'off';
            my $result = "Current wordlist: $self->{$channel}->{$gameid}->{wordlist} ($self->{$channel}->{$gameid}->{length}); started $started by $self->{$channel}->{$gameid}->{start_nick}; hard mode: $hard; guesses: $self->{$channel}->{$gameid}->{guess_count}; nonwords: $self->{$channel}->{$gameid}->{nonword_count}; invalids: $self->{$channel}->{$gameid}->{invalid_count}";

            if ($self->{$channel}->{$gameid}->{correct}) {
                my $solved_on = concise ago (time - $self->{$channel}->{$gameid}->{solved_on});
                my $wordle = join '', $self->{$channel}->{$gameid}->{wordle}->@*;
                my $duration = concise duration $self->{$channel}->{$gameid}->{start_time} - $self->{$channel}->{$gameid}->{solved_on};
                $result .= "; solved by: $self->{$channel}->{$gameid}->{solved_by} in $duration ($solved_on); word was: $wordle";
            } elsif ($self->{$channel}->{$gameid}->{givenup}) {
                my $givenup_on = concise ago (time - $self->{$channel}->{$gameid}->{givenup_on});
                my $wordle = join '', $self->{$channel}->{$gameid}->{wordle}->@*;
                $result .= "; given up by: $self->{$channel}->{$gameid}->{givenup_by} ($givenup_on); word was: $wordle";
            } else {
                my $guess = $self->{$channel}->{$gameid}->{guesses}->[-1];
                $guess =~ s/[^\pL]//g;
                $result .= "; last guess: $guess";
            }

            return $game . $result;
         }

        when ('giveup') {
            if (@args > 1) {
                return "Usage: wordle giveup [game-id]";
            }

            my $gameid = $self->gameid($args[0], $context);

            if (not defined $gameid) {
                return NO_GAMEID;
            }

            my $game = $gameid ne 'main' ? "($gameid) " : '';

            if (not defined $self->{$channel}->{$gameid}->{wordle}) {
                return $game . NO_WORDLE;
            }

            if ($self->{$channel}->{$gameid}->{correct}) {
                my $solved_on = concise ago (time - $self->{$channel}->{$gameid}->{solved_on});
                return "${game}Wordle already solved by $self->{$channel}->{$gameid}->{solved_by} ($solved_on)";
            }

            if ($self->{$channel}->{$gameid}->{givenup}) {
                my $givenup_on = concise ago (time - $self->{$channel}->{$gameid}->{givenup_on});
                my $wordle = join '', $self->{$channel}->{$gameid}->{wordle}->@*;
                return "${game}The word was $wordle. It was already given up by $self->{$channel}->{$gameid}->{givenup_by} ($givenup_on).";
            }

            $self->{$channel}->{$gameid}->{givenup} = 1;
            $self->{$channel}->{$gameid}->{givenup_by} = $context->{nick};
            $self->{$channel}->{$gameid}->{givenup_on} = time;
            my $wordle = join '', $self->{$channel}->{$gameid}->{wordle}->@*;
            return "${game}The word was $wordle. Better luck next time.";
        }

        when ('start') {
            if (@args > 3) {
                return "Invalid arguments; Usage: wordle start [word length [wordlist [game-id]]]";
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

            my $gameid = $self->gameid($args[2], $context, 1) // 'main';
            my $game = $gameid ne 'main' ? "($gameid) " : '';

            $self->{players}->{$channel}->{$context->{message_account}}->{gameid} = $gameid;

            if (defined $self->{$channel}->{$gameid}->{wordle} && $self->{$channel}->{$gameid}->{correct} == 0 && $self->{$channel}->{$gameid}->{givenup} == 0) {
                return "${game}There is already a Wordle underway! Use `wordle show` to see the current progress or `wordle giveup` to end it.";
            }

            return $game . $self->make_wordle($context->{nick}, $channel, $length, $gameid, undef, $wordlist);
        }

        when ('custom') {
            if (@args < 2 || @args > 4) {
                return "Usage: wordle custom <word> <channel> [wordlist [game-id]]";
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

            my $gameid = $self->gameid($args[3], $context, 1) // 'main';
            my $game = $gameid ne 'main' ? "($gameid) " : '';

            if (defined $self->{$custom_channel}->{$gameid}->{wordle} && $self->{$custom_channel}->{$gameid}->{correct} == 0 && $self->{$custom_channel}->{$gameid}->{givenup} == 0) {
                return "${game}There is already a Wordle underway! Use `wordle show` to see the current progress or `wordle giveup` to end it.";
            }

            $custom_word =~ s/ß/ẞ/g; # avoid uppercasing to SS in German
            my $result = $game . $self->make_wordle($context->{nick}, $custom_channel, $length, $gameid, uc $custom_word, $wordlist);

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
            if (!@args || @args > 2) {
                return "Usage: wordle guess <word> [game-id]";
            }

            my $gameid = $self->gameid($args[1], $context);

            if (not defined $gameid) {
                return NO_GAMEID;
            }

            my $game = $gameid ne 'main' ? "($gameid) " : '';

            if (not defined $self->{$channel}->{$gameid}->{wordle}) {
                return $game . NO_WORDLE;
            }

            if ($self->{$channel}->{$gameid}->{correct}) {
                return "${game}Wordle already solved by $self->{$channel}->{$gameid}->{solved_by}. " . $self->show_wordle($channel, $gameid);
            }

            if ($self->{$channel}->{$gameid}->{givenup}) {
                return "${game}Wordle given up by $self->{$channel}->{$gameid}->{givenup_by}.";
            }

            my $result = $game . $self->guess_wordle($channel, $args[0], $gameid);

            if ($self->{$channel}->{$gameid}->{correct}) {
                $self->{$channel}->{$gameid}->{solved_by} = $context->{nick};
                $self->{$channel}->{$gameid}->{solved_on} = time;
            }

            return $result;
        }

        when ('hard') {
            my $gameid = $self->gameid($args[1], $context);

            if (not defined $gameid) {
                return NO_GAMEID;
            }

            my $game = $gameid ne 'main' ? "($gameid) " : '';

            if (!@args || @args > 2) {
                return "${game}Hard mode is " . ($self->{$channel}->{$gameid}->{hard_mode} ? "enabled." : "disabled.");
            }

            if (lc $args[0] eq 'on') {
                my $mode = $self->{$channel}->{$gameid}->{hard_mode} ? 'already' : 'now';
                $self->{$channel}->{$gameid}->{hard_mode} = 1;
                return "${game}Hard mode is $mode enabled.";
            } else {
                my $mode = $self->{$channel}->{$gameid}->{hard_mode} ? 'now' : 'already';
                $self->{$channel}->{$gameid}->{hard_mode} = 0;
                return "${game}Hard mode is $mode disabled.";
            }
        }

        when ('guesses') {
            if (@args > 1) {
                return "Usage: wordle guesses [game-id]";
            }

            my $gameid = $self->gameid($args[0], $context);

            if (not defined $gameid) {
                return NO_GAMEID;
            }

            my $game = $gameid ne 'main' ? "($gameid) " : '';

            if (not defined $self->{$channel}->{$gameid}->{wordle}) {
                return $game . NO_WORDLE;
            }

            if (not $self->{$channel}->{$gameid}->{guesses}->@*) {
                return $game . 'No guesses yet.';
            }

            return $game . join("$color{reset} ", $self->{$channel}->{$gameid}->{guesses}->@*) . "$color{reset}";
        }

        when ('letters') {
            if (@args > 1) {
                return "Usage: wordle letters [game-id]";
            }

            my $gameid = $self->gameid($args[0], $context);

            if (not defined $gameid) {
                return NO_GAMEID;
            }

            my $game = $gameid ne 'main' ? "($gameid) " : '';

            if (not defined $self->{$channel}->{$gameid}->{wordle}) {
                return $game . NO_WORDLE;
            }

            return $game . $self->show_letters($channel, $gameid);
        }

        default {
            return "Unknown command `$command`; " . USAGE;
        }
    }
}

sub gameid($self, $gameid, $context, $newgame = 0) {
    my $channel = $context->{from};
    if (not defined $gameid) {
        if (exists $self->{players}->{$channel}->{$context->{message_account}}) {
            $gameid = $self->{players}->{$channel}->{$context->{message_account}}->{gameid};
            return $gameid if defined $gameid;
        }
    } else {
        if (!exists $self->{$channel}->{$gameid} && !$newgame) {
            return undef;
        }
    }

    return 'main' if !defined $gameid && !$newgame;
    return $gameid;
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

sub make_wordle($self, $nick, $channel, $length, $gameid = 'main', $word = undef, $wordlist = DEFAULT_LIST) {
    unless ($self->{$channel}->{$gameid}->{wordlist} eq $wordlist
            && $self->{$channel}->{$gameid}->{length} == $length
            && exists $self->{$channel}->{$gameid}->{words}) {
        eval {
            $self->{$channel}->{$gameid}->{words}     = $self->load_words($length, $wordlist);
            $self->{$channel}->{$gameid}->{guesslist} = dclone $self->{$channel}->{$gameid}->{words};
        };

        if ($@) {
            return "Failed to load words: $@";
        }
    }

    my @wordle;

    if (defined $word) {
        if (not exists $self->{$channel}->{$gameid}->{words}->{$word}) {
            return "I don't know that word.";
        }
        @wordle = split //, $word;
    } else {
        my @words = keys $self->{$channel}->{$gameid}->{words}->%*;
        @wordle = split //, $words[rand @words];
    }

    if (not @wordle) {
        return "Failed to find a suitable word.";
    }

    unless ($self->{$channel}->{$gameid}->{wordlist} eq $wordlist
            && $self->{$channel}->{$gameid}->{length} == $length
            && exists $self->{$channel}->{$gameid}->{words}) {
        if (exists $wordlists{$wordlist}->{glist}) {
            eval {
                foreach my $list ($wordlists{$wordlist}->{glist}->@*) {
                    $self->load_words($length, $list, $self->{$channel}->{$gameid}->{guesslist});
                }
            };

            if ($@) {
                return "Failed to load words: $@";
            }
        }
    }

    $self->{$channel}->{$gameid}->{wordlist}      = $wordlist;
    $self->{$channel}->{$gameid}->{length}        = $length;
    $self->{$channel}->{$gameid}->{wordle}        = \@wordle;
    $self->{$channel}->{$gameid}->{greens}        = [];
    $self->{$channel}->{$gameid}->{oranges}       = [];
    $self->{$channel}->{$gameid}->{whites}        = [];
    $self->{$channel}->{$gameid}->{letter_max}    = {};
    $self->{$channel}->{$gameid}->{guess}         = '';
    $self->{$channel}->{$gameid}->{guesses}       = [];
    $self->{$channel}->{$gameid}->{correct}       = 0;
    $self->{$channel}->{$gameid}->{givenup}       = 0;
    $self->{$channel}->{$gameid}->{guess_count}   = 0;
    $self->{$channel}->{$gameid}->{nonword_count} = 0;
    $self->{$channel}->{$gameid}->{invalid_count} = 0;
    $self->{$channel}->{$gameid}->{letters}       = {};
    $self->{$channel}->{$gameid}->{start_time}    = time;
    $self->{$channel}->{$gameid}->{start_nick}    = $nick;

    foreach my $letter ('A'..'Z') {
        $self->{$channel}->{$gameid}->{letters}->{$letter} = 0;
    }

    if (exists $wordlists{$wordlist}->{accents}) {
        foreach my $letter (split //, $wordlists{$wordlist}->{accents}) {
            $letter =~ s/ß/ẞ/g; # avoid uppercasing to SS in German
            $letter = uc $letter;
            $self->{$channel}->{$gameid}->{letters}->{$letter} = 0;
        }
    }

    $self->{$channel}->{$gameid}->{guess}  = $color{invalid};
    $self->{$channel}->{$gameid}->{guess} .= ' ? ' x $self->{$channel}->{$gameid}->{wordle}->@*;
    $self->{$channel}->{$gameid}->{guess} .= $color{reset};

    return $self->show_wordle($channel, $gameid) . " $wordlists{$wordlist}->{prompt} Legend: $color{invalid}X $color{reset} not in word; $color{present}X$color{present_a}?$color{reset} wrong position; $color{correct}X$color{correct_a}*$color{reset} correct position";
}

sub show_letters($self, $channel, $gameid = 'main') {
    my $result = 'Letters: ';

    foreach my $letter (sort keys $self->{$channel}->{$gameid}->{letters}->%*) {
        if ($self->{$channel}->{$gameid}->{letters}->{$letter} == LETTER_CORRECT) {
            $result .= "$color{correct}$letter$color{correct_a}*";
            $result .= "$color{reset} ";
        } elsif ($self->{$channel}->{$gameid}->{letters}->{$letter} == LETTER_PRESENT) {
            $result .= "$color{present}$letter$color{present_a}?";
            $result .= "$color{reset} ";
        } elsif ($self->{$channel}->{$gameid}->{letters}->{$letter} == 0) {
            $result .= "$letter ";
        }
    }

    return $result . "$color{reset}";
}

sub show_wordle($self, $channel, $gameid = 'main', $with_letters = 0) {
	if ($with_letters) {
		return $self->{$channel}->{$gameid}->{guess} . "$color{reset} " . $self->show_letters($channel, $gameid);
	} else {
		return $self->{$channel}->{$gameid}->{guess} . "$color{reset}";
	}
}

sub guess_wordle($self, $channel, $guess, $gameid = 'main') {
    $guess =~ s/ß/ẞ/g; # avoid uppercasing to SS in German
    $guess = uc $guess;

    if (length $guess != $self->{$channel}->{$gameid}->{wordle}->@*) {
        my $guess_length  = length $guess;
        my $wordle_length = $self->{$channel}->{$gameid}->{wordle}->@*;
        $self->{$channel}->{$gameid}->{invalid_count}++;
        return "Guess length ($guess_length) unequal to Wordle length ($wordle_length). Try again.";
    }

    my @guess  = split //, $guess;
    my @wordle = $self->{$channel}->{$gameid}->{wordle}->@*;

    if ($self->{$channel}->{$gameid}->{hard_mode}) {
        my %greens;
        my @greens = $self->{$channel}->{$gameid}->{greens}->@*;

        for (my $i = 0; $i < @guess; $i++) {
            if ($self->{$channel}->{$gameid}->{letters}->{$guess[$i]} == LETTER_INVALID) {
                $self->{$channel}->{$gameid}->{invalid_count}++;
                return "Hard mode is enabled. $guess[$i] is not in the Wordle. Try again.";
            }

            if ($greens[$i]) {
                if ($guess[$i] ne $greens[$i]) {
                    $self->{$channel}->{$gameid}->{invalid_count}++;
                    return "Hard mode is enabled. Position " . ($i + 1) . " must be $greens[$i]. Try again.";
                }
                $greens{$greens[$i]}++;
            }

            foreach my $orange ($self->{$channel}->{$gameid}->{oranges}->@*) {
                if ($guess[$i] eq $orange->[$i]) {
                    $self->{$channel}->{$gameid}->{invalid_count}++;
                    return "Hard mode is enabled. Position " . ($i + 1) . " can't be $guess[$i]. Try again.";
                }
            }
        }

        my %oranges;
        my $last_orange = $self->{$channel}->{$gameid}->{oranges}->[$self->{$channel}->{$gameid}->{oranges}->@* - 1];

        if ($last_orange) {
            $_ && $oranges{$_}++ foreach @$last_orange;

            foreach my $o (keys %oranges) {
                my $count = 0;
                $_ eq $o && $count++ foreach @guess;
                if ($count < $oranges{$o} + $greens{$o}) {
                    $self->{$channel}->{$gameid}->{invalid_count}++;
                    return "Hard mode is enabled. There must be " . ($oranges{$o} + $greens{$o}) . " $o. Try again.";
                }
            }
        }

        foreach my $white ($self->{$channel}->{$gameid}->{whites}->@*) {
            for (my $i = 0; $i < @guess; $i++) {
                if ($guess[$i] eq $white->[$i]) {
                    $self->{$channel}->{$gameid}->{invalid_count}++;
                    return "Hard mode is enabled. Position " . ($i + 1) . " can't be $guess[$i]. Try again.";
                }

                if (not $self->{$channel}->{$gameid}->{letter_max}->{$white->[$i]}) {
                    my $count = $greens{$white->[$i]} + $oranges{$white->[$i]};

                    if ($count) {
                        $self->{$channel}->{$gameid}->{letter_max}->{$white->[$i]} = $count;
                    }
                }
            }
        }

        my %count;
        $count{$_}++ foreach @guess;

        foreach my $c (keys %count) {
            if ($self->{$channel}->{$gameid}->{letter_max}->{$c} && $count{$c} > $self->{$channel}->{$gameid}->{letter_max}->{$c}) {
                $self->{$channel}->{$gameid}->{invalid_count}++;
                return "Hard mode is enabled. There can't be more than $self->{$channel}->{$gameid}->{letter_max}->{$c} $c. Try again.";
            }
        }
    }

    if (not exists $self->{$channel}->{$gameid}->{guesslist}->{$guess}) {
        $self->{$channel}->{$gameid}->{nonword_count}++;
        return "I don't know that word. Try again.";
    }

    $self->{$channel}->{$gameid}->{guess_count}++;

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
            $self->{$channel}->{$gameid}->{letters}->{$guess[$i]} = LETTER_CORRECT;
            $self->{$channel}->{$gameid}->{greens}->[$i] = $guess[$i];
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
                if ($self->{$channel}->{$gameid}->{letters}->{$guess[$i]} != LETTER_CORRECT) {
                    $self->{$channel}->{$gameid}->{letters}->{$guess[$i]} = LETTER_PRESENT;
                }
                $oranges[$i] = $guess[$i];
            } else {
                $result .= "$color{invalid} $guess[$i] ";

                if ($self->{$channel}->{$gameid}->{letters}->{$guess[$i]} == 0) {
                    $self->{$channel}->{$gameid}->{letters}->{$guess[$i]} = LETTER_INVALID;
                }
                $whites[$i] = $guess[$i];
            }
        }
    }

    $self->{$channel}->{$gameid}->{guess} = $result;

    push $self->{$channel}->{$gameid}->{guesses}->@*, $result;
    push $self->{$channel}->{$gameid}->{oranges}->@*, \@oranges;
    push $self->{$channel}->{$gameid}->{whites}->@*, \@whites;

    if ($correct == length $guess) {
        $self->{$channel}->{$gameid}->{correct} = 1;

        my $guesses = $self->{$channel}->{$gameid}->{guess_count};
        $guesses = " Correct in $guesses guess" . ($guesses != 1 ? 'es! ' : '! ');

        my $duration = concise duration $self->{$channel}->{$gameid}->{start_time} - time;

        $guesses .= "($duration) ";

        my $nonwords = $self->{$channel}->{$gameid}->{nonword_count};
        my $invalids = $self->{$channel}->{$gameid}->{invalid_count};

        if ($nonwords || $invalids) {
            $guesses .= '(plus ';

            if ($nonwords) {
                $guesses .= "$nonwords nonword";
                $guesses .= '; ' if $invalids;
            }

            if ($invalids) {
                $guesses .= "$invalids invalid";
            }
            $guesses .= ') ';
        }

        return $self->show_wordle($channel, $gameid) . $guesses;
    } else {
        return $self->show_wordle($channel, $gameid, 1);
    }
}

1;
