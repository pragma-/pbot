# File: Spinach.pm
#
# Purpose: Trivial game engine with a twist. Game is played in rounds. Each
# round players choose a category of questions. Then a random question from
# that category is shown. All players then privately submit a "lie" to the
# bot. Then all "lies" are revealed along with the true answer. Players
# gain points every time another player picks their lie. Very fun!

# SPDX-FileCopyrightText: 2018-2024 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Spinach;
use parent 'PBot::Plugin::Base';

use PBot::Imports;
use PBot::Core::Storage::HashObject;

use PBot::Plugin::Spinach::Stats;
use PBot::Plugin::Spinach::Rank;

use JSON;

use Lingua::EN::Fractions qw/fraction2words/;
use Lingua::EN::Numbers qw/num2en num2en_ordinal/;
use Lingua::EN::Numbers::Years qw/year2en/;
use Lingua::Stem qw/stem/;
use Lingua::EN::ABC qw/b2a/;

use Time::Duration qw/concise duration/;

use Text::Unidecode;
use Encode;

use Text::Levenshtein::XS 'distance';

use Data::Dumper;

$Data::Dumper::Sortkeys = sub {
    my ($h) = @_; my @a = sort grep { not /^(?:seen_questions|alternativeSpellings)$/ } keys %$h; \@a;
};

$Data::Dumper::Useqq = 1;

sub initialize($self, %conf) {
    $self->{pbot}->{commands}->add(
        name   => 'spinach',
        help   => 'Trivia game based on Fibbage',
        subref => sub { $self->cmd_spinach(@_) },
    );

    $self->{pbot}->{event_dispatcher}->register_handler('irc.part', sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quit', sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick', sub { $self->on_kick(@_) });

    $self->{channel} = $self->{pbot}->{registry}->get_value('spinach', 'channel') // '##spinach';

    my $default_file = $self->{pbot}->{registry}->get_value('spinach', 'file') // 'trivia.json';
    $self->{questions_filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . "/spinach/$default_file";
    $self->{stopwords_filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spinach/stopwords';
    $self->{metadata_filename}  = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spinach/metadata';
    $self->{stats_filename}     = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spinach/stats.sqlite';

    $self->{metadata} = PBot::Core::Storage::HashObject->new(
        pbot     => $self->{pbot},
        name     => 'Spinach Metadata',
        filename => $self->{metadata_filename}
    );

    $self->{metadata}->load;
    $self->set_metadata_defaults;

    $self->{stats}   = PBot::Plugin::Spinach::Stats->new(
        pbot     => $self->{pbot},
        filename => $self->{stats_filename}
    );

    $self->{rankcmd} = PBot::Plugin::Spinach::Rank->new(
        pbot => $self->{pbot},
        filename => $self->{stats_filename},
        channel => $self->{channel}
    );

    $self->create_states;
    $self->load_questions;
    $self->load_stopwords;

    # seconds between tocks
    $self->{tock_duration} = 30;

    # total tocks for choosecategory/picktruth
    $self->{choosecategory_max_tocks} = 4;
    $self->{picktruth_max_tocks}      = 4;
}

sub unload($self) {
    $self->{pbot}->{commands}->remove('spinach');
    $self->{pbot}->{event_queue}->dequeue_event('spinach loop');
    $self->{stats}->end if $self->{stats_running};
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.part');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.quit');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.kick');
}

sub on_kick($self, $event_type, $event) {
    my ($nick, $user, $host) = ($event->nick, $event->user, $event->host);
    my $channel = $event->{args}[0];
    return 0 if lc $channel ne $self->{channel};
    $self->player_left($nick, $user, $host);
    return 0;
}

sub on_departure($self, $event_type, $event) {
    my ($nick, $user, $host) = ($event->nick, $event->user, $event->host);
    my ($channel, $type)     = (lc $event->to, uc $event->type);
    return 0 if $type ne 'QUIT' and $channel ne $self->{channel};
    $self->player_left($nick, $user, $host);
    return 0;
}

sub load_questions($self, $filename = undef) {
    if (not defined $filename) {
        $filename = exists $self->{loaded_filename} ? $self->{loaded_filename} : $self->{questions_filename};
    } else {
        $filename = $self->{pbot}->{registry}->get_value('general', 'data_dir') . "/spinach/$filename";
    }

    $self->{pbot}->{logger}->log("Spinach: Loading questions from $filename...\n");

    my $contents = do {
        open my $fh, '<', $filename or do {
            $self->{pbot}->{logger}->log("Spinach: Failed to open $filename: $!\n");
            return "Failed to load $filename";
        };
        local $/;
        my $text = <$fh>;
        close $fh;
        $text;
    };

    $self->{loaded_filename} = $filename;

    $self->{questions}  = decode_json $contents;
    $self->{categories} = ();

    my $questions;
    foreach my $key (keys %{$self->{questions}}) {
        foreach my $question (@{$self->{questions}->{$key}}) {
            $question->{category} = uc $question->{category};
            $self->{categories}{$question->{category}}{$question->{id}} = $question;

            $question->{seen_timestamp} //= 0;
            $question->{value}          //= 0;
            $questions++;
        }
    }

    my $categories;
    foreach my $category (sort { keys %{$self->{categories}{$b}} <=> keys %{$self->{categories}{$a}} } keys %{$self->{categories}}) {
        # my $count = keys %{$self->{categories}{$category}};
        # $self->{pbot}->{logger}->log("Category [$category]: $count\n");
        $categories++;
    }

    $self->{pbot}->{logger}->log("Spinach: Loaded $questions questions in $categories categories.\n");
    return "Loaded $questions questions in $categories categories.";
}

sub save_questions($self) {
    my $json      = JSON->new;
    my $json_text = $json->pretty->canonical->utf8->encode($self->{questions});
    my $filename  = exists $self->{loaded_filename} ? $self->{loaded_filename} : $self->{questions_filename};
    open my $fh, '>', $filename or do {
        $self->{pbot}->{logger}->log("Failed to open Spinach file $filename: $!\n");
        return;
    };
    print $fh "$json_text\n";
    close $fh;
}

sub load_stopwords($self) {
    open my $fh, '<', $self->{stopwords_filename} or do {
        $self->{pbot}->{logger}->log("Spinach: Failed to open $self->{stopwords_filename}: $!\n");
        return;
    };

    foreach my $word (<$fh>) {
        chomp $word;
        $self->{stopwords}{$word} = 1;
    }
    close $fh;
}

sub set_metadata_defaults($self) {
    my $defaults = {
        category_choices  => 7,
        category_autopick => 0,
        min_players       => 2,
        stats             => 1,
        seen_expiry       => 432000,
        min_difficulty    => 0,
        max_difficulty    => 25000,
        max_missed_inputs => 3,
        debug_state       => 0,
        rounds            => 3,
        questions         => 3,
        bonus_rounds      => 1,
    };

    foreach my $key (keys %$defaults) {
        if (not $self->{metadata}->exists('settings', $key)) {
            $self->{metadata}->set('settings', $key, $defaults->{$key}, 1);
        }
    }
}

my %color = (
    white      => "\x0300",
    black      => "\x0301",
    blue       => "\x0302",
    green      => "\x0303",
    red        => "\x0304",
    maroon     => "\x0305",
    purple     => "\x0306",
    orange     => "\x0307",
    yellow     => "\x0308",
    lightgreen => "\x0309",
    teal       => "\x0310",
    cyan       => "\x0311",
    lightblue  => "\x0312",
    magneta    => "\x0313",
    gray       => "\x0314",
    lightgray  => "\x0315",

    bold      => "\x02",
    italics   => "\x1D",
    underline => "\x1F",
    reverse   => "\x16",

    reset => "\x0F",
);

sub cmd_spinach($self, $context) {
    my $arguments = $context->{arguments};
    $arguments =~ s/^\s+|\s+$//g;

    my $usage = "Usage: spinach join|exit|ready|unready|choose|lie|reroll|skip|keep|score|show|rank|categories|filter|set|unset|load|state|edit|kick|abort; for more information about a command: spinach help <command>";

    my $command;
    ($command, $arguments) = split / /, $arguments, 2;
    $command = defined $command ? lc $command : '';

    my ($channel, $result);

    given ($command) {
        when ('help') {
            given ($arguments) {
                when ('help') { return "Seriously?"; }

                when ('join') { return "Use `join` to start/join a game. A on-going game can be joined at any time."; }

                when ('ready') { return "Use `ready` to ready-up for a game."; }

                when ('unready') { return "Use `unready` to no longer be ready for a game."; }

                when ('exit') { return "Use `exit` to leave a game."; }

                when ('skip') { return "Use `skip` to skip a question and return to the \"choose category\" stage. A majority of the players must agree to skip."; }

                when ('keep') { return "Use `keep` to vote to prevent the current question from being rerolled or skipped."; }

                when ('abort') { return "Use `abort` to immediately end a game."; }

                when ('load') { return "Use `load` to load a trivia database."; }

                when ('edit') { return "Use `edit` to view and edit question metadata."; }

                when ('state') { return "Use `state` to view and manipulate the game state machine."; }

                when ('reroll') { return "Use `reroll` to get a different question from the same category."; }

                when ('kick') { return "Use `kick` to forcefully remove a player."; }

                when ('players') { return "Use `players` to list players and their ready-state or scores."; }

                when ('score') { return "Use `score` to display player scores."; }

                when ('choose') { return "Use `choose` to choose category, submit lie, or select truth."; }

                when ('lie') { return "Use `lie` (or `choose`) to submit a lie."; }

                when ('truth') { return "Use `truth` (or `choose`) to select a truth."; }

                when ('show') { return "Show the current question again."; }

                when ('categories') { return "Use `categories` to list available categories."; }

                when ('filter') { return "Use `filter` to set category include/exclude filters."; }

                when ('set') { return "Use `set` to set game metadata values (e.g. rounds, questions per rounds, minimum players, etc; see `spinach set settings` for a list of values)."; }

                when ('unset') { return "Use `unset` to delete game metadata values."; }

                when ('rank') { return "Use `rank` to show ranking of player stats."; }

                default {
                    if (length $arguments) {
                        return "Spinach has no such command '$arguments'.";
                    } else {
                        return "Usage: spinach help <command>";
                    }
                }
            }
        }

        when ('edit') {
            my $admin = $self->{pbot}->{users}->loggedin_admin($self->{channel}, $context->{hostmask});

            if (not $admin) {
                return "$context->{nick}: Only admins may edit questions.";
            }

            my ($id, $key, $value) = split /\s+/, $arguments, 3;

            if (not defined $id) {
                return "Usage: spinach edit <question id> [key [value]]";
            }

            $id =~ s/,//g;

            my $question;
            foreach my $q (@{$self->{questions}->{questions}}) {
                if ($q->{id} == $id) {
                    $question = $q;
                    last;
                }
            }

            if (not defined $question) {
                return "$context->{nick}: No such question.";
            }

            if (not defined $key) {
                my $dump = Dumper $question;
                $dump =~ s/\$VAR\d+ = \{\s*//;
                $dump =~ s/ \};\s*$//;
                return "$context->{nick}: Question $id: $dump";
            }

            if (not defined $value) {
                my $v = $question->{$key} // 'unset';
                return "$context->{nick}: Question $id: $key => $v";
            }

            if ($key !~ m/^(?:question|answer|category)$/i) {
                return "$context->{nick}: You may not edit that key.";
            }

            $question->{$key} = $value;
            $self->save_questions;
            return "$context->{nick}: Question $id: $key set to $value";
        }

        when ('load') {
            my $u = $self->{pbot}->{users}->loggedin($self->{channel}, $context->{hostmask});

            if (not $u or not $self->{pbot}->{capabilities}->userhas($u, 'botowner')) {
                return "$context->{nick}: Only botowners may reload the questions.";
            }

            $arguments = undef if not length $arguments;
            return $self->load_questions($arguments);
        }

        when ('join') {
            if ($self->{current_state} eq 'nogame') {
                $self->start_game;
            }

            return $self->player_join($context->{nick}, $context->{user}, $context->{host});
        }

        when ('ready') {
            my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($context->{nick}, $context->{user}, $context->{host});

            foreach my $player (@{$self->{state_data}->{players}}) {
                if ($player->{id} == $id) {
                    if ($self->{current_state} ne 'getplayers') {
                        return "/msg $context->{nick} This is not the time to use `ready`.";
                    }

                    if ($player->{ready} == 0) {
                        $player->{ready} = 1;
                        $player->{score} = 0;
                        return "/msg $self->{channel} $context->{nick} is ready!";
                    } else {
                        return "/msg $context->{nick} You are already ready.";
                    }
                }
            }

            return "$context->{nick}: You haven't joined this game yet. Use `j` to play now!";
        }

        when ('unready') {
            my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($context->{nick}, $context->{user}, $context->{host});

            foreach my $player (@{$self->{state_data}->{players}}) {
                if ($player->{id} == $id) {
                    if ($self->{current_state} ne 'getplayers') {
                        return "/msg $context->{nick} This is not the time to use `unready`.";
                    }

                    if ($player->{ready} != 0) {
                        $player->{ready} = 0;
                        return "/msg $self->{channel} $context->{nick} is no longer ready!";
                    } else {
                        return "/msg $context->{nick} You are already not ready.";
                    }
                }
            }

            return "$context->{nick}: You haven't joined this game yet. Use `j` to play now!";
        }

        when ('exit') {
            my $id      = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($context->{nick}, $context->{user}, $context->{host});
            my $removed = 0;

            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if ($self->{state_data}->{players}->[$i]->{id} == $id) {
                    splice @{$self->{state_data}->{players}}, $i--, 1;
                    $removed = 1;
                }
            }

            if ($removed) {
                if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
                    $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1;
                }

                if (not @{$self->{state_data}->{players}}) {
                    $self->{current_state} = 'nogame';
                    $self->{pbot}->{event_queue}->update_repeating('spinach loop', 0);
                    return "/msg $self->{channel} $context->{nick} has left the game! All players have left. The game has been stopped.";
                } else {
                    return "/msg $self->{channel} $context->{nick} has left the game!";
                }
            } else {
                return "$context->{nick}: But you are not even playing the game.";
            }
        }

        when ('abort') {
            if (not $self->{pbot}->{users}->loggedin_admin($self->{channel}, $context->{hostmask})) {
                return "$context->{nick}: Only admins may abort the game.";
            }

            $self->{current_state} = 'gameover';
            return "/msg $self->{channel} $context->{nick}: The game has been aborted.";
        }

        when ($_ eq 'score' or $_ eq 'players') {
            if ($self->{current_state} eq 'getplayers') {
                my @names;
                foreach my $player (@{$self->{state_data}->{players}}) {
                    if (not $player->{ready}) {
                        push @names, "$player->{name} $color{red}(not ready)$color{reset}";
                    } else {
                        push @names, $player->{name};
                    }
                }

                my $players = join ', ', @names;
                $players = 'none' if not @names;
                return "Current players: $players";
            }

            # score
            if (not @{$self->{state_data}->{players}}) {
                return "There is nobody playing right now.";
            }

            my $text  = '';
            my $comma = '';
            foreach my $player (sort { $b->{score} <=> $a->{score} } @{$self->{state_data}->{players}}) {
                $text .= "$comma$player->{name}: " . $self->commify($player->{score});
                $comma = '; ';
            }
            return $text;
        }

        when ('kick') {
            if (not $self->{pbot}->{users}->loggedin_admin($self->{channel}, $context->{hostmask})) {
                return "$context->{nick}: Only admins may kick people from the game.";
            }

            if (not length $arguments) { return "Usage: spinach kick <nick>"; }

            my $removed = 0;

            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if (lc $self->{state_data}->{players}->[$i]->{name} eq $arguments) {
                    splice @{$self->{state_data}->{players}}, $i--, 1;
                    $removed = 1;
                }
            }

            if ($removed) {
                if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
                    $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1;
                }
                return "/msg $self->{channel} $context->{nick}: $arguments has been kicked from the game.";
            } else {
                return "$context->{nick}: $arguments isn't even in the game.";
            }
        }

        when ('n') {
            return $self->normalize_text($arguments);
        }

        when ('v') {
            my ($truth, $lie) = split /;/, $arguments;
            if (!defined $truth || !defined $lie) {
                return "Usage: spinach v <truth>;<lie>";
            }
            return $self->validate_lie($self->normalize_text($truth), $self->normalize_text($lie));
        }

        when ('reroll') {
            if ($self->{current_state} eq 'getlies') {
                my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($context->{nick}, $context->{user}, $context->{host});

                my $player;
                my $rerolled = 0;
                my $keep;
                foreach my $i (@{$self->{state_data}->{players}}) {
                    if ($i->{id} == $id) {
                        $i->{reroll} = 1;
                        delete $i->{keep};
                        $rerolled++;
                        $player = $i;
                    } elsif ($i->{reroll}) {
                        $rerolled++;
                    } elsif ($i->{keep}) {
                        $keep++;
                    }
                }

                if (not $player) {
                    return "$context->{nick}: You are not playing in this game. Use `j` to start playing now!";
                }

                my $needed = int(@{$self->{state_data}->{players}} / 2) + 1;
                $needed -= $rerolled;
                $needed += $keep;

                my $votes_needed;
                if    ($needed == 1) { $votes_needed = "$needed more vote to reroll!"; }
                elsif ($needed > 1)  { $votes_needed = "$needed more votes to reroll!"; }
                else                 { $votes_needed = "Rerolling..."; }

                return "/msg $self->{channel} $color{red}$context->{nick} has voted to reroll for another question from the same category! $color{reset}$votes_needed";
            } else {
                return "$context->{nick}: This command can be used only during the \"submit lies\" stage.";
            }
        }

        when ('skip') {
            if ($self->{current_state} eq 'getlies') {
                my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($context->{nick}, $context->{user}, $context->{host});

                my $player;
                my $skipped = 0;
                my $keep    = 0;
                foreach my $i (@{$self->{state_data}->{players}}) {
                    if ($i->{id} == $id) {
                        $i->{skip} = 1;
                        delete $i->{keep};
                        $skipped++;
                        $player = $i;
                    } elsif ($i->{skip}) {
                        $skipped++;
                    } elsif ($i->{keep}) {
                        $keep++;
                    }
                }

                if (not $player) { return "$context->{nick}: You are not playing in this game. Use `j` to start playing now!"; }

                my $needed = int(@{$self->{state_data}->{players}} / 2) + 1;
                $needed -= $skipped;
                $needed += $keep;

                my $votes_needed;
                if    ($needed == 1) { $votes_needed = "$needed more vote to skip!"; }
                elsif ($needed > 1)  { $votes_needed = "$needed more votes to skip!"; }
                else                 { $votes_needed = "Skipping..."; }

                return "/msg $self->{channel} $color{red}$context->{nick} has voted to skip this category! $color{reset}$votes_needed";
            } else {
                return "$context->{nick}: This command can be used only during the \"submit lies\" stage.";
            }
        }

        when ('keep') {
            if ($self->{current_state} eq 'getlies') {
                my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($context->{nick}, $context->{user}, $context->{host});

                my $player;
                foreach my $i (@{$self->{state_data}->{players}}) {
                    if ($i->{id} == $id) {
                        $i->{keep} = 1;
                        delete $i->{skip};
                        delete $i->{reroll};
                        $player = $i;
                        last;
                    }
                }

                if (not $player) {
                    return "$context->{nick}: You are not playing in this game. Use `j` to start playing now!";
                }

                return "/msg $self->{channel} $color{green}$context->{nick} has voted to keep playing the current question!";
            } else {
                return "$context->{nick}: This command can be used only during the \"submit lies\" stage.";
            }
        }

        when ($_ eq 'lie' or $_ eq 'truth' or $_ eq 'choose') {
            $arguments //= '';
            $arguments = lc $arguments;

            if ($self->{current_state} eq 'choosecategory') {
                if (not length $arguments) { return "Usage: spinach choose <integer>"; }

                my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($context->{nick}, $context->{user}, $context->{host});

                if (not @{$self->{state_data}->{players}} or $id != $self->{state_data}->{players}->[$self->{state_data}->{current_player}]->{id}) {
                    return "$context->{nick}: It is not your turn to choose a category.";
                }

                if ($arguments !~ /^[0-9]+$/) {
                    return "$context->{nick}: Please choose a category number. $self->{state_data}->{categories_text}";
                }

                $arguments--;

                if ($arguments < 0 or $arguments >= @{$self->{state_data}->{category_options}}) {
                    return "$context->{nick}: Choice out of range. Please choose a valid category. $self->{state_data}->{categories_text}";
                }

                if ($arguments == @{$self->{state_data}->{category_options}} - 2) {
                    $arguments = (@{$self->{state_data}->{category_options}} - 2) * rand;
                    $self->{state_data}->{current_category} = $self->{state_data}->{category_options}->[$arguments];
                    return "/msg $self->{channel} $context->{nick} has chosen RANDOM CATEGORY! Randomly choosing category: $self->{state_data}->{current_category}!";
                } elsif ($arguments == @{$self->{state_data}->{category_options}} - 1) {
                    $self->{state_data}->{reroll_category} = 1;
                    return "/msg $self->{channel} $context->{nick} has chosen REROLL CATEGORIES! Rerolling categories...";
                } else {
                    $self->{state_data}->{current_category} = $self->{state_data}->{category_options}->[$arguments];
                    return "/msg $self->{channel} $context->{nick} has chosen $self->{state_data}->{current_category}!";
                }
            }

            if ($self->{current_state} eq 'getlies') {
                if (not length $arguments) { return 'Usage: spinach lie <text>'; }

                my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($context->{nick}, $context->{user}, $context->{host});

                my $player;
                foreach my $i (@{$self->{state_data}->{players}}) {
                    if ($i->{id} == $id) {
                        $player = $i;
                        last;
                    }
                }

                if (not $player) {
                    return "$context->{nick}: You are not playing in this game. Use `j` to start playing now!";
                }

                if ($player->{lie_count} >= 2) {
                    return "/msg $context->{nick} You cannot change your lie again this round.";
                }

                $arguments = $self->normalize_text($arguments);

                my @truth_count = split /\s/, $self->{state_data}->{current_question}->{answer};
                my @lie_count   = split /\s/, $arguments;

                my $validate = $self->validate_lie($self->{state_data}->{current_question}->{answer}, $arguments);

                # check alternate answers if lie is not already too similar to default answer
                if ($validate == 1) {
                    # check alternative answers
                    foreach my $alt (@{$self->{state_data}->{current_question}->{alternativeSpellings}}) {
                        $validate = self->validate_lie($alt, $arguments);

                        # end loop if too similar to an alternative
                        last if $validate != 1;
                    }
                }

                if ($validate != 1) {
                    if ($validate == 0) {
                        $self->send_message($self->{channel}, "$color{yellow}$context->{nick} has found the truth!$color{reset}");
                        return "$context->{nick}: You have found the truth! Submit a different lie.";
                    } elsif ($validate == -1) {
                        $self->send_message($self->{channel}, "$color{cyan}$context->{nick} has found part of the truth!$color{reset}");
                    } else {
                        $self->send_message($self->{channel}, "$color{cyan}$context->{nick} has misspelled the truth!$color{reset}");
                    }
                    return "$context->{nick}: Your lie is too similar to the truth! Submit a different lie.";
                }

                $player->{lie_count}++;

                my $changed = exists $player->{lie};
                $player->{lie} = $arguments;

                if   ($changed) { return "/msg $self->{channel} $context->{nick} has changed their lie!"; }
                else            { return "/msg $self->{channel} $context->{nick} has submitted a lie!"; }
            }

            if ($self->{current_state} eq 'findtruth') {
                if (not length $arguments) { return 'Usage: spinach truth <integer>'; }

                my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($context->{nick}, $context->{user}, $context->{host});

                my $player;
                foreach my $i (@{$self->{state_data}->{players}}) {
                    if ($i->{id} == $id) {
                        $player = $i;
                        last;
                    }
                }

                if (not $player) {
                    return "$context->{nick}: You are not playing in this game. Use `j` to start playing now!";
                }

                if ($arguments !~ /^[0-9]+$/) {
                    return "$context->{nick}: Please select a truth number. $self->{state_data}->{current_choices_text}";
                }

                $arguments--;

                if ($arguments < 0 or $arguments >= @{$self->{state_data}->{current_choices}}) {
                    return "$context->{nick}: Selection out of range. Please select a valid truth. $self->{state_data}->{current_choices_text}";
                }

                my $changed = exists $player->{truth};
                $player->{truth} = uc $self->{state_data}->{current_choices}->[$arguments];

                if ($player->{truth} eq $player->{lie}) {
                    delete $player->{truth};
                    return "$context->{nick}: You cannot select your own lie!";
                }

                if   ($changed) { return "/msg $self->{channel} $context->{nick} has selected a different truth!"; }
                else            { return "/msg $self->{channel} $context->{nick} has selected a truth!"; }
            }

            return "$context->{nick}: It is not time to use this command.";
        }

        when ('show') {
            if ($self->{current_state} =~ /(?:getlies|findtruth|showlies)/) {
                $self->showquestion_helper($self->{state_data}, 1);
                return '';
            }

            return "$context->{nick}: There is nothing to show right now.";
        }

        when ('categories') {
            if (not length $arguments) { return "Usage: spinach categories <regex>"; }

            my $result = eval {
                use re::engine::RE2 -strict => 1;
                my @categories = grep { /$arguments/i } keys %{$self->{categories}};
                if (not @categories) { return "No categories found."; }

                my $text  = "";
                my $comma = "";
                foreach my $cat (sort @categories) {
                    $text .= "$comma$cat: " . keys %{$self->{categories}{$cat}};
                    $comma = ",\n";
                }
                return $text;
            };

            return "$arguments: $@" if $@;
            return $result;
        }

        when ('filter') {
            my ($cmd, $args) = split / /, $arguments, 2;
            $cmd = lc $cmd;

            if (not length $cmd) { return "Usage: spinach filter include <regex> | exclude <regex> | show | clear"; }

            given ($cmd) {
                when ($_ eq 'include' or $_ eq 'exclude') {
                    if (not length $args) { return "Usage: spinach filter $_ <regex>"; }

                    eval { "" =~ /$args/ };
                    return "Bad filter $args: $@" if $@;

                    my @categories = grep { /$args/i } keys %{$self->{categories}};
                    if (not @categories) { return "Bad filter: No categories match. Try again."; }

                    $self->{metadata}->set('filter', "category_" . $_ . "_filter", $args);
                    return "Spinach $_ filter set.";
                }

                when ('clear') {
                    $self->{metadata}->remove('filter');
                    return "Spinach filter cleared.";
                }

                when ('show') {
                    if (not $self->{metadata}->exists('filter', 'category_include_filter') and not $self->{metadata}->exists('filter', 'category_exclude_filter')) {
                        return "There is no Spinach filter set.";
                    }

                    my $text  = "Spinach ";
                    my $comma = "";

                    if ($self->{metadata}->exists('filter', 'category_include_filter')) {
                        $text .= "include filter set to: " . $self->{metadata}->get_data('filter', 'category_include_filter');
                        $comma = "; ";
                    }

                    if ($self->{metadata}->exists('filter', 'category_exclude_filter')) {
                        $text .= $comma . "exclude filter set to: " . $self->{metadata}->get_data('filter', 'category_exclude_filter');
                    }

                    return $text;
                }

                default { return "Unknown filter command '$cmd'."; }
            }
        }

        when ('state') {
            my ($command, $args) = split /\s+/, $arguments;

            if ($command eq 'show') {
                return "Previous state: $self->{previous_state}; current state: $self->{current_state}; previous result: $self->{state_data}->{previous_result}";
            }

            if ($command eq 'set') {
                if (not length $args) { return "Usage: spinach state set <new state>"; }

                my $u = $self->{pbot}->{users}->loggedin($self->{channel}, $context->{hostmask});
                if (not $self->{pbot}->{capabilities}->userhas($u, 'admin')) { return "$context->{nick}: Only admins may set game state."; }

                $self->{previous_state} = $self->{current_state};
                $self->{current_state}  = $args;
                return "State set to $args";
            }

            if ($command eq 'result') {
                if (not length $args) { return "Usage: spinach state result <current state result>"; }

                my $admin = $self->{pbot}->{users}->loggedin_admin($self->{channel}, $context->{hostmask});
                if (not $admin) { return "$context->{nick}: Only admins may set game state."; }

                $self->{state_data}->{previous_result} = $self->{state_data}->{result};
                $self->{state_data}->{result}          = $args;
                return "State result set to $args";
            }

            return "Usage: spinach state show | set <new state> | result <current state result>";
        }

        when ('set') {
            my ($index, $key, $value) = split /\s+/, $arguments;

            if (not defined $index) { return "Usage: spinach set <metadata> [key [value]]"; }

            if (lc $index eq 'settings' and $key and lc $key eq 'stats' and defined $value and $self->{current_state} ne 'nogame') {
                return "Spinach stats setting cannot be modified while a game is in progress.";
            }

            my $admin = $self->{pbot}->{users}->loggedin_admin($self->{channel}, $context->{hostmask});
            if (defined $value and not $admin) { return "$context->{nick}: Only admins may set game settings."; }

            return $self->{metadata}->set($index, $key, $value);
        }

        when ('unset') {
            my ($index, $key) = split /\s+/, $arguments;

            if (not defined $index or not defined $key) { return "Usage: spinach unset <metadata> <key>"; }

            if (lc $index eq 'settings' and lc $key eq 'stats' and $self->{current_state} ne 'nogame') {
                return "Spinach stats setting cannot be modified while a game is in progress.";
            }

            my $admin = $self->{pbot}->{users}->loggedin_admin($self->{channel}, $context->{hostmask});
            if (not $admin) { return "$context->{nick}: Only admins may set game settings."; }

            return $self->{metadata}->unset($index, $key);
        }

        when ('rank') {
            return $self->{rankcmd}->rank($arguments);
        }

        default { return $usage; }
    }

    return $result;
}

sub start_game($self) {
    $self->{state_data} = {
        players     => [],
        bonus_round => 0,
    };

    $self->{current_state} = 'getplayers';

    $self->{pbot}->{event_queue}->enqueue_event(
        sub {
            $self->run_one_state;
        }, 1, 'spinach loop', 1
    );
}

sub player_join($self, $nick, $user, $host) {
    my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($nick, $user, $host);

    foreach my $player (@{$self->{state_data}->{players}}) {
        if ($player->{id} == $id) {
            return "$nick: You have already joined this game.";
        }
    }

    my $player = {
        id           => $id,
        name         => $nick,
        score        => 0,
        ready        => $self->{current_state} eq 'getplayers' ? 0 : 1,
        missedinputs => 0
    };

    push @{$self->{state_data}->{players}}, $player;

    return "/msg $self->{channel} $nick has joined the game!";
}

sub player_left($self, $nick, $user, $host) {
    my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_ancestor($nick, $user, $host);

    for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
        if ($self->{state_data}->{players}->[$i]->{id} == $id) {
            splice @{$self->{state_data}->{players}}, $i--, 1;

            if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
                $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1;
            }

            $self->send_message($self->{channel}, "$nick has left the game!");
            last;
        }
    }
}

sub send_message($self, $to, $text, $delay = 0) {
    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
    my $message = {
        nick       => $botnick,
        user       => 'spinach',
        host       => 'localhost',
        hostmask   => "$botnick!spinach\@localhost",
        keyword    => 'spinach',
        command    => 'spinach',
        checkflood => 1,
        message    => $text
    };
    $self->{pbot}->{interpreter}->add_message_to_output_queue($to, $message, $delay);
}

sub add_new_suggestions($self, $state) {
    my $question = undef;
    my $modified = 0;

    foreach my $player (@{$state->{players}}) {
        if ($player->{deceived}) {
            $self->{pbot}->{logger}->log("Adding new suggestion for $state->{current_question}->{id}: $state->{current_question}->{question}: $player->{deceived}\n");

            if (not grep { lc $_ eq lc $player->{deceived} } @{$state->{current_question}->{suggestions}}) {
                if (not defined $question) {
                    foreach my $q (@{$self->{questions}->{questions}}) {
                        if ($q->{id} == $state->{current_question}->{id}) {
                            $question = $q;
                            last;
                        }
                    }
                }

                push @{$question->{suggestions}}, uc $player->{deceived};
                $modified = 1;
            }
        }
    }

    if ($modified) { $self->save_questions; }
}

sub commify($self, $value) {
    my $text = reverse $value;
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $text;
}

sub normalize_question($self, $text) {
    my @words = split / /, $text;
    my $uc    = 0;

    foreach my $word (@words) {
        if ($word =~ m/^[A-Z]/) { $uc++; }
    }

    if ($uc >= @words * .8) {
        $text = ucfirst lc $text;
    }

    return $text;
}

sub normalize_text($self, $text) {
    $text = unidecode $text;

    $text =~ s/^\s+|\s+$//g;
    $text =~ s/\s+/ /g;
    $text =~ s/^(the|a|an) //i;
    $text =~ s/&/ AND /g;

    $text = lc substr($text, 0, 80);

    $text =~ s/\$\s+(\d)/\$$1/g;
    $text =~ s/\s*%$//;
    $text =~ s/(\d),(\d\d\d)/$1$2/g;
    $text =~ s/(\D,)(\D)/$1 $2/g;

    my @words = split / /, $text;
    my @result;

    foreach my $word (@words) {
        my $punct   = $1 if $word =~ s/(\p{PosixPunct}+)$//;
        my $newword = $word;

        if ($word =~ m/^\d{4}$/ and $word >= 1700 and $word <= 2100) { $newword = year2en($word); }
        elsif ($word =~ m/^-?\d+$/) {
            $newword = num2en($word);

            if (defined $punct and $punct eq '%') {
                $newword .= " percent";
                $punct = undef;
            }
        } elsif ($word =~ m/^(-?\d+)(?:st|nd|rd|th)$/i) {
            $newword = num2en_ordinal($1);
        } elsif ($word =~ m/^(-)?\$(\d+)?(\.\d+)?$/i) {
            my ($neg, $dollars, $cents) = ($1, $2, $3);
            $newword = '';
            $dollars = "$neg$dollars" if defined $neg and defined $dollars;

            if (defined $dollars) {
                $word    = num2en($dollars);
                $newword = "$word " . (abs $dollars == 1 ? "dollar" : "dollars");
            }

            if (defined $cents) {
                $cents =~ s/^\.0*//;
                $cents = "$neg$cents" if defined $neg and not defined $dollars;
                $word  = num2en($cents);
                $newword .= " and " if defined $dollars;
                $newword .= (abs $cents == 1 ? "$word cent" : "$word cents");
            }
        } elsif ($word =~ m/^(-?\d*\.\d+)(?:st|nd|rd|th)?$/i) {
            $newword = num2en($1);
        } elsif ($word =~ m{^(-?\d+\s*/\s*-?\d+)(?:st|nd|rd|th)?$}i) {
            $newword = fraction2words($1);
        }

        $newword .= $punct if defined $punct;
        push @result, $newword;
    }

    $text = uc b2a("@result", s => 1);

    $text =~ s/([A-Z])\./$1/g;
    $text =~ s/-/ /g;
    $text =~ s/["'?!]//g;
    $text =~ s/\s+/ /g;
    $text =~ s/^\s+|\s+$//g;

    return substr $text, 0, 80;
}

sub validate_lie($self, $truth, $lie) {
    my %truth_words      = @{stem map { $_ => 1 } grep { /^\w+$/ and not exists $self->{stopwords}{lc $_} } split /\b/, $truth};
    my $truth_word_count = keys %truth_words;

    my %lie_words      = @{stem map { $_ => 1 } grep { /^\w+$/ and not exists $self->{stopwords}{lc $_} } split /\b/, $lie};
    my $lie_word_count = keys %lie_words;

    my $count = 0;

    foreach my $word (keys %lie_words) {
        if (exists $truth_words{$word}) {
            $count++;
        }
    }

    if ($count >= $lie_word_count) {
        if ($count == $truth_word_count) {
            # lie matches truth exactly
            return 0;
        } else {
            # lie is a proper subset of truth
            return -1;
        }
    }

    $count = 0;

    foreach my $word (keys %truth_words) {
        if (exists $lie_words{$word}) {
            $count++;
        }
    }

    if ($count >= $truth_word_count) {
        if ($count == $lie_word_count) {
            # truth matches lie exactly
            return 0;
        } else {
            # truth is a proper subset of lie
            return -1;
        }
    }

    my $stripped_truth = $truth;
    $stripped_truth =~ s/(?:\s|\p{PosixPunct})+//g;

    my $stripped_lie = $lie;
    $stripped_lie =~ s/(?:\s|\p{PosixPunct})+//g;

    if ($stripped_truth eq $stripped_lie) {
        return 0;
    }

    my $distance = distance($stripped_truth, $stripped_lie);
    my $length   = (length $stripped_truth > length $stripped_lie) ? length $stripped_truth : length $stripped_lie;

    # if difference is 20% or less then they're too similar
    if ($distance / $length <= 0.20) {
        return -2;
    }

    return 1;
}

sub showquestion_helper($self, $state, $show_category = undef) {
    return if $state->{reroll_category};

    if (exists $state->{current_question}) {
        my $category = '';
        my $value    = '';

        if ($show_category) { $category = "[$state->{current_category}] "; }

        if ($state->{current_question}->{value}) { $value = "[$state->{current_question}->{value}] "; }

        $self->send_message(
            $self->{channel},
            "$color{green}Current question:$color{reset} " . $self->commify($state->{current_question}->{id}) . ") $category$value$state->{current_question}->{question}"
        );
    } else {
        $self->send_message($self->{channel}, "There is no current question.");
    }
}

# state machine

sub run_one_state($self) {
    # check for naughty or missing players
    for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
        if ($self->{state_data}->{players}->[$i]->{missedinputs} >= $self->{metadata}->get_data('settings', 'max_missed_inputs')) {
            $self->send_message(
                $self->{channel},
                "$color{red}$self->{state_data}->{players}->[$i]->{name} has missed too many prompts and has been ejected from the game!$color{reset}"
            );

            splice @{$self->{state_data}->{players}}, $i--, 1;

            if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
                $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1;
            }
        }
    }

    if ($self->{current_state} ne 'nogame' && not @{$self->{state_data}->{players}}) {
        $self->send_message($self->{channel}, "All players have left the game!");
        $self->{current_state} = 'nogame';
        $self->{pbot}->{event_queue}->update_repeating('spinach loop', 0);
        return;
    }

    my $state_data = $self->{state_data};

    # transitioned to a brand new state; prepare first tock
    if ($self->{previous_state} ne $self->{current_state}) {
        $state_data->{newstate} = 1;
        $state_data->{ticks}    = 1;
        $state_data->{tocks}    = 0;

        if (exists $state_data->{tick_drift}) {
            $state_data->{ticks} += $state_data->{tick_drift};
            delete $state_data->{tick_drift};
        }

        $state_data->{first_tock} = 1;
    } else {
        $state_data->{newstate} = 0;
    }

    # dump new state data for logging/debugging
    if ($state_data->{newstate} and $self->{metadata}->get_data('settings', 'debug_state')) {
        $self->{pbot}->{logger}->log("Spinach: New state: $self->{previous_state} ($state_data->{previous_result}) --> $self->{current_state}\n" . Dumper($state_data) . "\n");
    }

    # run one state/tick
    my $should_trans = $self->{states}{$self->{current_state}}{sub}($state_data);

    if ($state_data->{tocked}) {
        delete $state_data->{tocked};
        delete $state_data->{first_tock};
        $state_data->{ticks} = 0;
    }

    # prepare to transition to next state
    $state_data->{previous_result} = $state_data->{result};
    $self->{previous_state}        = $self->{current_state};

    if ($should_trans) {
        # sanity check to ensure edits to state machine didn't break anything
        if (not exists $self->{states}{$self->{current_state}}{trans}{$state_data->{result}}) {
            $self->{pbot}->{logger}->log("Spinach: State broke: no such transition to $state_data->{result} for state $self->{current_state}\n");
            $self->send_message($self->{channel}, "Spinach state broke: no such transition to $state_data->{result} for state $self->{current_state}");
            $self->{current_state} = 'nogame';
            $self->{pbot}->{event_queue}->update_repeating('spinach loop', 0);
            return;
        }

        # transition to next state
        $self->{current_state} = $self->{states}{$self->{current_state}}{trans}{$state_data->{result}};

        # this shouldn't happen
        if (not defined $self->{current_state}) {
            $self->{pbot}->{logger}->log("Spinach state broke.\n");
            $self->send_message($self->{channel}, "Spinach state broke.");
            $self->{current_state} = 'nogame';
            $self->{pbot}->{event_queue}->update_repeating('spinach loop', 0);
            return;
        }
    }

    # next tick
    $self->{state_data}->{ticks}++;
}

# state transitions

sub create_states($self) {
    $self->{pbot}->{logger}->log("Spinach: Creating game state machine\n");

    $self->{state_data} = {
        players => []
    };

    $self->{previous_state}  = '';
    $self->{previous_result} = '';
    $self->{current_state}   = 'nogame';

    # no game running || game ended
    $self->{states}{'nogame'}{sub}                  = sub { $self->nogame(@_) };
    $self->{states}{'nogame'}{trans}{start}         = 'getplayers';

    # waiting for players to join/ready
    $self->{states}{'getplayers'}{sub}              = sub { $self->getplayers(@_) };
    $self->{states}{'getplayers'}{trans}{stop}      = 'nogame';
    $self->{states}{'getplayers'}{trans}{allready}  = 'roundinit';

    # initialize round scoring, etc
    $self->{states}{'roundinit'}{sub}               = sub { $self->roundinit(@_) };
    $self->{states}{'roundinit'}{trans}{finalscore} = 'finalscore';
    $self->{states}{'roundinit'}{trans}{next}       = 'roundstart';

    # start round (announce current round info)
    $self->{states}{'roundstart'}{sub}              = sub { $self->roundstart(@_) };
    $self->{states}{'roundstart'}{trans}{next}      = 'choosecategory';

    $self->{states}{'choosecategory'}{sub}          = sub { $self->choosecategory(@_) };
    $self->{states}{'choosecategory'}{trans}{next}  = 'showquestion';

    $self->{states}{'showquestion'}{sub}            = sub { $self->showquestion(@_) };
    $self->{states}{'showquestion'}{trans}{next}    = 'getlies';

    $self->{states}{'getlies'}{sub}                 = sub { $self->getlies(@_) };
    $self->{states}{'getlies'}{trans}{reroll}       = 'showquestion';
    $self->{states}{'getlies'}{trans}{skip}         = 'roundstart';
    $self->{states}{'getlies'}{trans}{next}         = 'findtruth';

    $self->{states}{'findtruth'}{sub}               = sub { $self->findtruth(@_) };
    $self->{states}{'findtruth'}{trans}{next}       = 'showlies';

    $self->{states}{'showlies'}{sub}                = sub { $self->showlies(@_) };
    $self->{states}{'showlies'}{trans}{next}        = 'showtruth';

    $self->{states}{'showtruth'}{sub}               = sub { $self->showtruth(@_) };
    $self->{states}{'showtruth'}{trans}{next}       = 'reveallies';

    $self->{states}{'reveallies'}{sub}              = sub { $self->reveallies(@_) };
    $self->{states}{'reveallies'}{trans}{next}      = 'showscore';

    $self->{states}{'showscore'}{sub}               = sub { $self->showscore(@_) };
    $self->{states}{'showscore'}{trans}{next}       = 'roundinit';

    $self->{states}{'finalscore'}{sub}              = sub { $self->finalscore(@_) };
    $self->{states}{'finalscore'}{trans}{next}      = 'gameover';

    $self->{states}{'gameover'}{sub}                = sub { $self->gameover(@_) };
    $self->{states}{'gameover'}{trans}{next}        = 'getplayers';
}

# state subroutines

sub nogame($self, $state) {
    if ($self->{stats_running}) {
        $self->{stats}->end;
        delete $self->{stats_running};
    }

    $self->{pbot}->{event_queue}->update_repeating('spinach loop', 0);
    $state->{result} = 'nogame';
    return 0;
}

sub getplayers($self, $state) {
    my $players = $state->{players};

    my @names;
    my $unready = @$players ? @$players : 1;

    foreach my $player (@$players) {
        if (not $player->{ready}) {
            push @names, "$player->{name} $color{red}(not ready)$color{reset}";
        } else {
            $unready--;
            push @names, $player->{name};
        }
    }

    my $min_players = $self->{metadata}->get_data('settings', 'min_players') // 2;

    if (@$players >= $min_players and not $unready) {
        $self->send_message($self->{channel}, "All players ready!");

        if ($self->{metadata}->get_data('settings', 'stats')) {
            $self->{stats}->begin;
            $self->{stats_running} = 1;
        }

        $self->{game} = {
            rounds    => $self->{metadata}->get_data('settings', 'rounds'),
            questions => $self->{metadata}->get_data('settings', 'questions'),
            round     => 1, # current round
            question  => 0, # current question
        };

        $self->{scoring} = {
            1 => {
                truth => 500,
                lie   => 1000,
            },
            2 => {
                truth => 750,
                lie   => 1500,
            },
            3 => { # rounds 3 and greater use this scoring
                truth => 1000,
                lie   => 2000,
            },
            bonus => { # bonus rounds are when round >= rounds + 1
                truth => 2000,
                lie   => 3000,
            }
        };

        $state->{result} = 'allready';
        return 1;
    }

    my $tock;

    if ($state->{first_tock}) {
        # first get-players announcement in default tock-duration seconds
        $tock = $self->{tock_duration};
    } else {
        # 5 minutes between get-players announcements
        $tock = 300;
    }

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        if (not $unready) {
            $self->send_message($self->{channel}, "Game cannot begin with one player.");
        }

        if (++$state->{tocks} > 6) {
            $self->send_message($self->{channel}, "Not all players were ready in time. The game has been stopped.");
            $state->{players} = [];
            $state->{result}  = 'stop';
            return 1;
        }

        $players = join ', ', @names;

        if (not @names) {
            $players = 'none';

            if ($state->{tocks} >= 0) {
                $self->send_message($self->{channel}, "All players have left the queue. The game has been stopped.");
                $self->{pbot}->{event_queue}->update_repeating('spinach loop', 0);
                $self->{current_state} = 'nogame';
                $self->{result}        = 'nogame';
                return;
            }
        }

        my $msg = "Waiting for more players or for all players to ready up. Current players: $players";
        $self->send_message($self->{channel}, $msg);
    }

    $state->{result} = 'wait';
    return 0;
}

sub roundinit($self, $state) {
    $self->{game}->{question}++;

    if ($self->{game}->{question} > $self->{game}->{questions}) {
        $self->{game}->{round}++;
        $self->{game}->{question} = 1;
    }

    my $round_scoring = $self->{game}->{round};

    if ($round_scoring >= $self->{game}->{rounds} + 1) {
        $state->{bonus_round}++;
        $round_scoring = 'bonus';
    } elsif ($round_scoring > 3) {
        $round_scoring = 3;
    }

    $state->{truth_points}  = $self->{scoring}->{$round_scoring}->{truth};
    $state->{lie_points}    = $self->{scoring}->{$round_scoring}->{lie};

    if ($state->{bonus_round} > $self->{metadata}->get_data('settings', 'bonus_rounds')) {
        $state->{result} = 'finalscore';
    } else {
        $state->{result} = 'next';
    }
    return 1;
}

sub roundstart($self, $state) {
    if ($state->{ticks} % 2 == 0 || $state->{reroll_category}) {
        $state->{init}  = 1;
        $state->{max_tocks} = $self->{choosecategory_max_tocks};

        unless ($state->{reroll_category}) {
            my $round     = $self->{game}->{round};
            my $rounds    = $self->{game}->{rounds};
            my $question  = $self->{game}->{question};
            my $questions = $self->{game}->{questions};
            my $announce;

            if ($round >= $rounds + 1) {
                $announce = 'BONUS ROUND! BONUS QUESTION!';
            } else {
                $announce = "Round $round/$rounds, question $question/$questions!";
            }

            $self->send_message($self->{channel}, "$announce $state->{lie_points} for each lie. $state->{truth_points} for the truth.")
        }

        $state->{result} = 'next';
        return 1;
    } else {
        $state->{result} = 'wait';
        return 0;
    }
}

sub choosecategory($self, $state) {
    if ($state->{init} or $state->{reroll_category}) {
        delete $state->{current_category};
        $state->{current_player}++ unless $state->{reroll_category};

        if ($state->{current_player} >= @{$state->{players}}) {
            $state->{current_player} = 0;
        }

        if ($self->{game}->{round} >= $self->{game}->{rounds} + 1) {
            $state->{random_category} = 1;
        }

        my @choices;
        my @categories;

        if ($self->{metadata}->exists('filter', 'category_include_filter') and length $self->{metadata}->get_data('filter', 'category_include_filter')) {
            my $filter = $self->{metadata}->get_data('filter', 'category_include_filter');
            @categories = grep { /$filter/i } keys %{$self->{categories}};
        } else {
            @categories = keys %{$self->{categories}};
        }

        if ($self->{metadata}->exists('filter', 'category_exclude_filter') and length $self->{metadata}->get_data('filter', 'category_exclude_filter')) {
            my $filter = $self->{metadata}->get_data('filter', 'category_exclude_filter');
            @categories = grep { $_ !~ /$filter/i } @categories;
        }

        my $attempts = 0;
        while (1) {
            last if ++$attempts > 10000;
            my $cat = $categories[rand @categories];

            my @questions = keys %{$self->{categories}{$cat}};

            if (not @questions) {
                $self->{pbot}->{logger}->log("No questions for category $cat\n");
                next;
            }

            if ($self->{metadata}->exists('settings', 'min_difficulty')) {
                @questions = grep { $self->{categories}{$cat}{$_}->{value} >= $self->{metadata}->get_data('settings', 'min_difficulty') } @questions;
            }

            if ($self->{metadata}->exists('settings', 'max_difficulty')) {
                @questions = grep { $self->{categories}{$cat}{$_}->{value} <= $self->{metadata}->get_data('settings', 'max_difficulty') } @questions;
            }

            if ($self->{metadata}->exists('settings', 'seen_expiry')) {
                my $now = time;
                @questions = grep { $now - $self->{categories}{$cat}{$_}->{seen_timestamp} >= $self->{metadata}->get_data('settings', 'seen_expiry') } @questions;
            }

            next if not @questions;

            if (not grep { $_ eq $cat } @choices) {
                push @choices, $cat;
            }

            last if @choices == $self->{metadata}->get_data('settings', 'category_choices')
                or @categories < $self->{metadata}->get_data('settings', 'category_choices');
        }

        if (not @choices) {
            $self->{pbot}->{logger}->log("Out of questions with current settings!\n");
            $self->send_message($self->{channel}, "Out of questions with current settings! This will probably break something.");
            # XXX: do something useful here
        }

        push @choices, 'RANDOM CATEGORY';
        push @choices, 'REROLL CATEGORIES';

        $state->{categories_text} = '';
        my $i     = 1;
        my $comma = '';
        foreach my $choice (@choices) {
            $state->{categories_text} .= "$comma$color{green}$i)$color{reset} " . $choice;
            $i++;
            $comma = "; ";
        }

        if ($state->{reroll_category} and not $self->{metadata}->get_data('settings', 'category_autopick')) {
            $self->send_message($self->{channel}, $state->{categories_text});
        }

        $state->{category_options} = \@choices;
        $state->{category_rerolls} = 0 if $state->{init};
        delete $state->{init};
        delete $state->{reroll_category};
    }

    if (exists $state->{current_category} or not @{$state->{players}}) {
        $state->{result} = 'next';
        return 1;
    }

    my $tock;

    if   ($state->{first_tock}) { $tock = 2; }
    else                        { $tock = $self->{tock_duration}; }

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        if (exists $state->{random_category} or $self->{metadata}->get_data('settings', 'category_autopick')) {
            delete $state->{random_category};
            my $category  = $state->{category_options}->[rand(@{$state->{category_options}} - 2)];
            my $questions = scalar keys %{$self->{categories}{$category}};
            $self->send_message($self->{channel}, "$color{green}Category:$color{reset} $category! ($questions questions)");
            $state->{current_category} = $category;
            $state->{result} = 'next';
            return 1;
        }

        if (++$state->{tocks} > $state->{max_tocks}) {
            # $state->{players}->[$state->{current_player}]->{missedinputs}++;
            my $name     = $state->{players}->[$state->{current_player}]->{name};
            my $category = $state->{category_options}->[rand(@{$state->{category_options}} - 2)];
            $self->send_message($self->{channel}, "$name took too long to choose. Randomly choosing: $category!");
            $state->{current_category} = $category;
            $state->{result} = 'next';
            return 1;
        }

        my $name = $state->{players}->[$state->{current_player}]->{name};
        my $warning;
        if    ($state->{tocks} == $state->{max_tocks})     { $warning = $color{red}; }
        elsif ($state->{tocks} == $state->{max_tocks} - 1) { $warning = $color{yellow}; }
        else                                               { $warning = ''; }

        my $remaining = $self->{tock_duration} * $state->{max_tocks};
        $remaining -= $self->{tock_duration} * ($state->{tocks} - 1);
        $remaining = "(" . (concise duration $remaining) . " remaining)";

        my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
        $self->send_message($self->{channel}, "$name: $warning$remaining Choose a category via `/msg $botnick c <number>`:$color{reset}");
        $self->send_message($self->{channel}, "$state->{categories_text}");
        $state->{result} = 'wait';
        return 0;
    }

    if (exists $state->{current_category}) {
        $state->{result} = 'next';
        return 1;
    } else {
        $state->{result} = 'wait';
        return 0;
    }
}

sub showquestion($self, $state) {
    if ($state->{ticks} % 2 == 0) {
        my @questions = keys %{$self->{categories}{$state->{current_category}}};

        if (exists $state->{seen_questions}->{$state->{current_category}}) {
            my @seen = keys %{$state->{seen_questions}->{$state->{current_category}}};
            my %seen = map { $_ => 1 } @seen;
            @questions = grep { !defined $seen{$_} } @questions;
        }

        @questions = sort { $self->{categories}{$state->{current_category}}{$a}->{seen_timestamp} <=> $self->{categories}{$state->{current_category}}{$b}->{seen_timestamp} } @questions;
        my $now = time;
        @questions = grep { $now - $self->{categories}{$state->{current_category}}{$_}->{seen_timestamp} >= $self->{metadata}->get_data('settings', 'seen_expiry') } @questions;

        if ($self->{metadata}->exists('settings', 'min_difficulty')) {
            @questions = grep { $self->{categories}{$state->{current_category}}{$_}->{value} >= $self->{metadata}->get_data('settings', 'min_difficulty') } @questions;
        }

        if ($self->{metadata}->exists('settings', 'max_difficulty')) {
            @questions = grep { $self->{categories}{$state->{current_category}}{$_}->{value} <= $self->{metadata}->get_data('settings', 'max_difficulty') } @questions;
        }

        if (not @questions) {
            $self->send_message($self->{channel}, "No more questions available in category $state->{current_category}! Picking new category...");
            delete $state->{seen_questions}->{$state->{current_category}};
            @questions = keys %{$self->{categories}{$state->{current_category}}};
            $state->{reroll_category} = 1;
        }

        if ($state->{reroll_question}) {
            delete $state->{reroll_question};

            unless ($state->{reroll_category}) {
                my $count = @questions;
                $self->send_message(
                    $self->{channel},
                    "Rerolling new question from $state->{current_category} (" . $self->commify($count) . " question" . ($count == 1 ? '' : 's') . " remaining)\n"
                );
            }
        }

        $state->{current_question}             = $self->{categories}{$state->{current_category}}{$questions[0]};
        $state->{current_question}->{question} = $self->normalize_question($state->{current_question}->{question});
        $state->{current_question}->{answer}   = $self->normalize_text($state->{current_question}->{answer});

        $state->{current_question}->{seen_timestamp} = time unless $state->{reroll_category};

        my @alts = map { $self->normalize_text($_) } @{$state->{current_question}->{alternativeSpellings}};
        $state->{current_question}->{alternativeSpellings} = \@alts;

        $state->{seen_questions}->{$state->{current_category}}->{$state->{current_question}->{id}} = 1;

        foreach my $player (@{$state->{players}}) {
            $player->{lie_count} = 0;
            delete $player->{lie};
            delete $player->{truth};
            delete $player->{good_lie};
            delete $player->{deceived};
            delete $player->{skip};
            delete $player->{reroll};
            delete $player->{keep};
        }

        $state->{current_choices_text} = '';

        $self->showquestion_helper($state);

        $state->{max_tocks}          = $self->{picktruth_max_tocks};
        $state->{init}               = 1;
        $state->{current_lie_player} = 0;

        $state->{result} = 'next';
        return 1;
    } else {
        $state->{result} = 'wait';
        return 0;
    }
}

sub getlies($self, $state) {
    if ($state->{reroll_category}) {
        $state->{result} = 'skip';
        return 1;
    }

    my $tock;

    if   ($state->{first_tock}) { $tock = 2; }
    else                        { $tock = $self->{tock_duration}; }

    my @nolies;
    my $reveallies = '. Revealing lies! ';
    my $lies       = 0;
    my $comma      = '';
    my @keeps;
    my @rerolls;
    my @skips;

    foreach my $player (@{$state->{players}}) {
        if (not exists $player->{lie}) {
            push @nolies, $player->{name};
        } else {
            $lies++;
            $reveallies .= "$comma$player->{name}: $player->{lie}";
            $comma = '; ';
        }

        if ($player->{reroll}) { push @rerolls, $player->{name}; }

        if ($player->{skip}) { push @skips, $player->{name}; }

        if ($player->{keep}) { push @keeps, $player->{name}; }
    }

    # advance to next state if everyone has submitted a lie
    if (not @nolies) {
        $state->{result} = 'next';
        return 1;
    }

    $reveallies = '' if not $lies;

    if (@rerolls) {
        my $needed = int(@{$state->{players}} / 2) + 1;
        $needed += @keeps;
        $needed -= @rerolls;
        if ($needed <= 0) {
            $state->{reroll_question} = 1;
            $self->send_message($self->{channel}, "The answer was: " . uc($state->{current_question}->{answer}) . $reveallies);
            $state->{result} = 'reroll';
            return 1;
        }
    }

    if (@skips) {
        my $needed = int(@{$state->{players}} / 2) + 1;
        $needed += @keeps;
        $needed -= @skips;
        if ($needed <= 0) {
            $self->send_message($self->{channel}, "The answer was: " . uc($state->{current_question}->{answer}) . $reveallies);
            $state->{result} = 'skip';
            return 1;
        }
    }

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        if (++$state->{tocks} > $state->{max_tocks}) {
            my @missedinputs;
            foreach my $player (@{$state->{players}}) {
                if (not exists $player->{lie}) {
                    push @missedinputs, $player->{name};
                    $player->{missedinputs}++;
                }
            }

            if (@missedinputs) {
                my $missed = join ', ', @missedinputs;
                $self->send_message($self->{channel}, "$missed failed to submit a lie in time!");
            }

            $state->{init}   = 1;
            $state->{result} = 'next';
            return 1;
        }

        my $players = join ', ', @nolies;

        my $warning;
        if    ($state->{tocks} == $state->{max_tocks})     { $warning = $color{red}; }
        elsif ($state->{tocks} == $state->{max_tocks} - 1) { $warning = $color{yellow}; }
        else                                               { $warning = ''; }

        my $remaining = $self->{tock_duration} * $state->{max_tocks};
        $remaining -= $self->{tock_duration} * ($state->{tocks} - 1);
        $remaining = "(" . (concise duration $remaining) . " remaining)";

        my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
        $self->send_message($self->{channel}, "$players: $warning$remaining Submit your lie now via `/msg $botnick lie <your lie>`!");
    }

    $state->{result} = 'wait';
    return 0;
}

sub findtruth($self, $state) {
    my $tock;

    if   ($state->{first_tock}) { $tock = 2; }
    else                        { $tock = $self->{tock_duration}; }

    my @notruth;

    foreach my $player (@{$state->{players}}) {
        if (not exists $player->{truth}) { push @notruth, $player->{name}; }
    }

    if (not @notruth) {
        # all players have selected a truth
        $state->{result} = 'next';
        return 1;
    }

    if ($state->{init}) {
        delete $state->{init};

        my @choices;
        my @suggestions = @{$state->{current_question}->{suggestions}};
        my @lies;

        foreach my $player (@{$state->{players}}) {
            if ($player->{lie}) {
                if (not grep { $_ eq $player->{lie} } @lies) {
                    push @lies, uc $player->{lie};
                }
            }
        }

        while (1) {
            my $limit = @{$state->{players}} < 5 ? 5 : @{$state->{players}};
            last if @choices >= $limit;

            if (@lies) {
                my $random = rand @lies;
                push @choices, $lies[$random];
                splice @lies, $random, 1;
                next;
            }

            if (@suggestions) {
                my $random     = rand @suggestions;
                my $suggestion = uc $suggestions[$random];
                push @choices, $suggestion if not grep { $_ eq $suggestion } @choices;
                splice @suggestions, $random, 1;
                next;
            }

            last;
        }

        splice @choices, rand @choices + 1, 0, $state->{current_question}->{answer};
        $state->{correct_answer} = $state->{current_question}->{answer};

        my $i     = 0;
        my $comma = '';
        my $text  = '';
        foreach my $choice (@choices) {
            ++$i;
            $text .= "$comma$color{green}$i) $color{reset}$choice";
            $comma = '; ';
        }

        $state->{current_choices_text} = $text;
        $state->{current_choices}      = \@choices;
    }

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        if (++$state->{tocks} > $state->{max_tocks}) {
            my @missedinputs;
            foreach my $player (@{$state->{players}}) {
                if (not exists $player->{truth}) {
                    push @missedinputs, $player->{name};
                    $player->{missedinputs}++;
                    $player->{score} -= $state->{lie_points};
                }
            }

            if (@missedinputs) {
                my $missed = join ', ', @missedinputs;
                $self->send_message($self->{channel}, "$missed failed to find the truth in time! They lose $state->{lie_points} points!");
            }

            $state->{result} = 'next';
            return 1;
        }

        my $players = join ', ', @notruth;

        my $warning;
        if    ($state->{tocks} == $state->{max_tocks})     { $warning = $color{red}; }
        elsif ($state->{tocks} == $state->{max_tocks} - 1) { $warning = $color{yellow}; }
        else                                               { $warning = ''; }

        my $remaining = $self->{tock_duration} * $state->{max_tocks};
        $remaining -= $self->{tock_duration} * ($state->{tocks} - 1);
        $remaining = "(" . (concise duration $remaining) . " remaining)";

        my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
        $self->send_message($self->{channel}, "$players: $warning$remaining Find the truth now via `/msg $botnick c <number>`!$color{reset}");
        $self->send_message($self->{channel}, "$state->{current_choices_text}");
    }

    $state->{result} = 'wait';
    return 0;
}

sub showlies($self, $state) {
    my @liars;
    my $player;

    my $tock;
    if   ($state->{first_tock}) { $tock = 2; }
    else                        { $tock = 3; }

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        while ($state->{current_lie_player} < @{$state->{players}}) {
            $player = $state->{players}->[$state->{current_lie_player}];
            $state->{current_lie_player}++;
            next if not exists $player->{truth};

            foreach my $liar (@{$state->{players}}) {
                next if $liar->{id} == $player->{id};
                next if not exists $liar->{lie};

                if ($liar->{lie} eq $player->{truth}) {
                    push @liars, $liar;
                }
            }

            last if @liars;

            if ($player->{truth} ne $state->{correct_answer}) {
                if ($self->{metadata}->get_data('settings', 'stats')) {
                    my $player_id   = $self->{stats}->get_player_id($player->{name}, $self->{channel});
                    my $player_data = $self->{stats}->get_player_data($player_id);
                    $player_data->{bad_guesses}++;
                    $self->{stats}->update_player_data($player_id, $player_data);
                }

                $player->{score} -= $state->{lie_points};
                $player->{deceived} = $player->{truth};
                $self->send_message($self->{channel}, "$player->{name} fell for my lie: \"$player->{truth}\". -$state->{lie_points} points!");

                if ($state->{current_lie_player} < @{$state->{players}}) {
                    $state->{result} = 'wait';
                    return 0;
                } else {
                    $state->{result} = 'next';
                    return 1;
                }
            }
        }

        if (@liars) {
            my $liars_text          = '';
            my $liars_no_apostrophe = '';
            my $lie                 = $player->{truth};
            my $gains               = @liars == 1 ? 'gains' : 'gain';
            my $comma               = '';

            foreach my $liar (@liars) {
                if ($self->{metadata}->get_data('settings', 'stats')) {
                    my $player_id   = $self->{stats}->get_player_id($liar->{name}, $self->{channel});
                    my $player_data = $self->{stats}->get_player_data($player_id);
                    $player_data->{players_deceived}++;
                    $self->{stats}->update_player_data($player_id, $player_data);
                }

                $liars_text          .= "$comma$liar->{name}'s";
                $liars_no_apostrophe .= "$comma$liar->{name}";
                $comma = ', ';
                $liar->{score} += $state->{lie_points};
                $liar->{good_lie} = 1;
            }

            if ($self->{metadata}->get_data('settings', 'stats')) {
                my $player_id   = $self->{stats}->get_player_id($player->{name}, $self->{channel});
                my $player_data = $self->{stats}->get_player_data($player_id);
                $player_data->{bad_guesses}++;
                $self->{stats}->update_player_data($player_id, $player_data);
            }

            $self->send_message($self->{channel}, "$player->{name} fell for $liars_text lie: \"$lie\". $liars_no_apostrophe $gains +$state->{lie_points} points!");
            $player->{deceived} = $lie;
        }

        if ($state->{current_lie_player} >= @{$state->{players}}) {
            if   (@liars) { delete $state->{tick_drift}; }
            else          { $state->{tick_drift} = $tock - 1; }
            $state->{result} = 'next';
            return 1;
        } else {
            $state->{result} = 'wait';
            return 0;
        }
    }

    $state->{result} = 'wait';
    return 0;
}

sub showtruth($self, $state) {
    if ($state->{ticks} % 3 == 0) {
        my $player_id;
        my $player_data;
        my $players;
        my $comma = '';
        my $count = 0;

        foreach my $player (@{$state->{players}}) {
            if ($self->{metadata}->get_data('settings', 'stats')) {
                $player_id   = $self->{stats}->get_player_id($player->{name}, $self->{channel});
                $player_data = $self->{stats}->get_player_data($player_id);

                $player_data->{questions_played}++;
                # update nick in stats database once per question (nick changes, etc)
                $player_data->{nick} = $player->{name};
            }

            if (exists $player->{deceived}) {
                if ($self->{metadata}->get_data('settings', 'stats')) {
                    $self->{stats}->update_player_data($player_id, $player_data);
                }
                next;
            }

            if (exists $player->{truth} and $player->{truth} eq $state->{correct_answer}) {
                if ($self->{metadata}->get_data('settings', 'stats')) {
                    $player_data->{good_guesses}++;
                    $self->{stats}->update_player_data($player_id, $player_data);
                }
                $count++;
                $players .= "$comma$player->{name}";
                $comma = ', ';
                $player->{score} += $state->{truth_points};
            }
        }

        if ($count) {
            $self->send_message($self->{channel}, "$players got the correct answer: \"$state->{correct_answer}\". +$state->{truth_points} points!");
        } else {
            $self->send_message($self->{channel}, "Nobody found the truth! The answer was: $state->{correct_answer}");
        }

        $self->add_new_suggestions($state);
        $state->{result} = 'next';
        return 1;
    } else {
        $state->{result} = 'wait';
        return 0;
    }
}

sub reveallies($self, $state) {
    if ($state->{ticks} % 3 == 0) {
        my $text  = 'Revealing lies! ';
        my $comma = '';
        foreach my $player (@{$state->{players}}) {
            next if not exists $player->{lie};
            $text .= "$comma$player->{name}: $player->{lie}";
            $comma = '; ';

            if ($player->{good_lie}) {
                if ($self->{metadata}->get_data('settings', 'stats')) {
                    my $player_id   = $self->{stats}->get_player_id($player->{name}, $self->{channel});
                    my $player_data = $self->{stats}->get_player_data($player_id);
                    $player_data->{good_lies}++;
                    $self->{stats}->update_player_data($player_id, $player_data);
                }
            }
        }

        $self->send_message($self->{channel}, "$text");
        $state->{result} = 'next';
        return 1;
    } else {
        $state->{result} = 'wait';
        return 0;
    }
}

sub showscore($self, $state) {
    # skip showing scores if bonus round so finalscore state does it
    if ($self->{game}->{round} >= $self->{game}->{rounds} + 1) {
        $state->{result} = 'next';
        return 1;
    }

    # skip showing scores if no bonus round and final round/question
    if ($self->{metadata}->get_data('settings', 'bonus_rounds') == 0
        && $self->{game}->{round} >= $self->{game}->{rounds}
        && $self->{game}->{question} >= $self->{game}->{questions})
    {
        $state->{result} = 'next';
        return 1;
    }

    if ($state->{ticks} % 3 == 0) {
        my $text  = '';
        my $comma = '';
        foreach my $player (sort { $b->{score} <=> $a->{score} } @{$state->{players}}) {
            $text .= "$comma$player->{name}: " . $self->commify($player->{score});
            $comma = '; ';
        }

        $text = 'none' if not length $text;

        $self->send_message($self->{channel}, "$color{green}Scores:$color{reset} $text");
        $state->{result} = 'next';
        return 1;
    } else {
        $state->{result} = 'wait';
        return 0;
    }
}

sub finalscore($self, $state) {
    if ($state->{newstate}) {
        my $player_id;

        my $player_data;
        my $mentions = '';
        my $text     = '';
        my $comma    = '';
        my $i        = @{$state->{players}};

        $state->{finalscores} = [];

        foreach my $player (sort { $a->{score} <=> $b->{score} } @{$state->{players}}) {
            if ($self->{metadata}->get_data('settings', 'stats')) {
                $player_id   = $self->{stats}->get_player_id($player->{name}, $self->{channel});
                $player_data = $self->{stats}->get_player_data($player_id);

                $player_data->{games_played}++;
                $player_data->{avg_score} *= $player_data->{games_played} - 1;
                $player_data->{avg_score} += $player->{score};
                $player_data->{avg_score} /= $player_data->{games_played};
                $player_data->{low_score} = $player->{score} if $player_data->{low_score} == 0;

                if ($player->{score} > $player_data->{high_score}) {
                    $player_data->{high_score} = $player->{score};
                } elsif ($player->{score} < $player_data->{low_score}) {
                    $player_data->{low_score} = $player->{score};
                }
            }

            if ($i >= 4) {
                $mentions = "$player->{name}: " . $self->commify($player->{score}) . "$comma$mentions";
                $comma    = "; ";

                if ($i == 4) {
                    $mentions = "Honorable mentions: $mentions";
                }

                if ($self->{metadata}->get_data('settings', 'stats')) {
                    $self->{stats}->update_player_data($player_id, $player_data);
                }

                $i--;
                next;
            } elsif ($i == 3) {
                $player_data->{times_third}++;
                $text = sprintf("%15s%-13s%7s", "Third place: ", $player->{name}, $self->commify($player->{score}));
            } elsif ($i == 2) {
                $player_data->{times_second}++;
                $text = sprintf("%15s%-13s%7s", "Second place: ", $player->{name}, $self->commify($player->{score}));
            } elsif ($i == 1) {
                $player_data->{times_first}++;
                $text = sprintf("%15s%-13s%7s", "WINNER: ", $player->{name}, $self->commify($player->{score}));
            }

            if ($self->{metadata}->get_data('settings', 'stats')) {
                $self->{stats}->update_player_data($player_id, $player_data);
            }

            push @{$state->{finalscores}}, $text;
            $i--;
        }
        push @{$state->{finalscores}}, $mentions if length $mentions;
    }

    my $tock;

    if ($state->{first_tock}) {
        $tock = 2;
    } else {
        $tock = 3;
    }

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        if (not @{$state->{finalscores}}) {
            $self->send_message($self->{channel}, "$color{green}Final scores: $color{reset}none");
            $state->{result} = 'next';
            return 1;
        }

        if ($state->{first_tock}) {
            $self->send_message($self->{channel}, "$color{green}Final scores:$color{reset}");
            $state->{result} = 'wait';
            return 0;
        }

        my $text = shift @{$state->{finalscores}};
        $self->send_message($self->{channel}, "$text");

        if (not @{$state->{finalscores}}) {
            $state->{result} = 'next';
            return 1;
        }
    }
    $state->{result} = 'wait';
    return 0;
}

sub gameover($self, $state) {
    if ($state->{ticks} % 3 == 0) {
        $self->send_message($self->{channel}, 'Game over!');

        my $players = $state->{players};
        foreach my $player (@$players) {
            $player->{ready}        = 0;
            $player->{missedinputs} = 0;
        }

        # save updated seen_timestamps
        $self->save_questions;

        # reset some state data
        delete $state->{random_category};
        $state->{bonus_round} = 0;
        $state->{result}  = 'next';
        return 1;
    } else {
        $state->{result} = 'wait';
        return 0;
    }
}

1;
