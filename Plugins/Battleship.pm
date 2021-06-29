# File: Battleship.pm
#
# Purpose: Simplified version of the Battleship board game.
#
# Note: This code was written circa 1993 for a DikuMUD fork. It was originally
# written in C, as I was teaching the language to myself in my early teens. Two
# decades or so later, I transliterated this code from C to Perl for PBot. Much
# of the "ugly" C-style design of this code has been preserved for personal
# historical reasons -- I was inspired by the IOCCC and I attempted to be clever
# with nested conditional operators and other silliness. Please be gentle if you
# read this code. :)

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Battleship;
use parent 'Plugins::Plugin';

use PBot::Imports;

use Time::Duration;
use Data::Dumper;

sub initialize {
    my ($self, %conf) = @_;

    # register `battleship` bot command
    $self->{pbot}->{commands}->register(sub { $self->cmd_battleship(@_) }, 'battleship', 0);

    # set the channel where to send game messages
    $self->{channel} = $self->{pbot}->{registry}->get_value('battleship', 'channel') // '##battleship';

    # set debugging flag
    $self->{debug}   = $self->{pbot}->{registry}->get_value('battleship', 'debug')   // 0;

    # set board tile symbols/characters
    $self->{player_one_vert}  = '|';
    $self->{player_one_horiz} = '—';
    $self->{player_two_vert}  = 'I';
    $self->{player_two_horiz} = '=';
    $self->{ocean}            = '~';
    $self->{player_one_miss}  = '*';
    $self->{player_one_hit}   = '1';
    $self->{player_two_miss}  = 'o';
    $self->{player_two_hit}   = '2';

    # create game state machine
    $self->create_states;
}

sub unload {
    my ($self) = @_;

    # unregister `battleship` bot command
    $self->{pbot}->{commands}->unregister('battleship');

    # remove battleship loop event from event queue
    $self->{pbot}->{event_queue}->dequeue_event('battleship loop');
}

# `battleship` bot command
sub cmd_battleship {
    my ($self, $context) = @_;

    my $usage = "Usage: battleship challenge|accept|decline|bomb|board|score|forfeit|quit|players|kick|abort; for more information about a command: battleship help <command>";

    # strip leading and trailing whitespace
    $context->{arguments} =~ s/^\s+|\s+$//g;

    my ($command, $arguments) = split / /, $context->{arguments}, 2;

    $command //= '';
    $command = lc $command;

    # shorter aliases
    my ($nick, $user, $host, $hostmask, $channel) = (
        $context->{nick},
        $context->{user},
        $context->{host},
        $context->{hostmask},
        $self->{channel},
    );

    given ($command) {
        # help doesn't do much yet
        when ('help') {
            given ($arguments) {
                when ('help') {
                    return "Seriously?";
                }

                default {
                    if (length $arguments) {
                        return "Battleship help is coming soon.";
                    } else {
                        return "Usage: battleship help <command>";
                    }
                }
            }
        }

        # issue a challenge to begin a game
        when ('challenge') {
            if ($self->{current_state} ne 'nogame') {
                return "There is already a game of Battleship underway.";
            }

            # `challenge` without arguments issues an open challenge
            if (not length $arguments) {
                $self->set_state('accept');

                # add player 1, the challenger, to the game
                my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

                my $player = {
                    id   => $id,
                    name => $nick,
                    missedinputs => 0
                };

                push @{$self->{state_data}->{players}}, $player;

                # add player 2, a placeholder for the challengee
                $player = {
                    id   => -1,
                    name => 'anybody',
                    missedinputs => 0
                };

                push @{$self->{state_data}->{players}}, $player;

                # start the battleship game loop
                $self->{pbot}->{event_queue}->enqueue_event(sub {
                        $self->run_one_state;
                    }, 1, 'battleship loop', 1
                );

                return "/msg $channel $nick has made an open challenge! Use `accept` to accept their challenge.";
            }

            # otherwise we're challenging a specific person

            # are they in the channel?
            my $challengee = $self->{pbot}->{nicklist}->is_present($channel, $arguments);

            if (not $challengee) {
                return "$arguments is not present in $channel. Invite them to the channel and try again!";
            }

            # set up next state of game
            $self->set_state('accept');

            # add player 1, the challenger, to the game
            my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

            my $player = {
                id   => $id,
                name => $nick,
                missedinputs => 0,
            };

            push @{$self->{state_data}->{players}}, $player;

            # add player 2, the challengee, to the game
            ($id) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($challengee);

            $player = {
                id   => $id,
                name => $challengee,
                missedinputs => 0,
            };

            push @{$self->{state_data}->{players}}, $player;

            # start the battleship game loop
            $self->{pbot}->{event_queue}->enqueue_event(sub {
                    $self->run_one_state;
                }, 1, 'battleship loop', 1
            );

            return "/msg $channel $nick has challenged $challengee to Battleship! Use `accept` to accept their challenge.";
        }

        # accept challenges
        when ('accept') {
            if ($self->{current_state} ne 'accept') {
                return "/msg $nick This is not the time to use `accept`.";
            }

            my $id     = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
            my $player = $self->{state_data}->{players}->[1];

            # accept an open challenge
            if ($player->{id} == -1) {
                $player->{id}   = $id;
                $player->{name} = $nick;
            }

            # confirm right user is accepting challenge
            if ($player->{id} == $id) {
                # accept the challenge
                $player->{accepted} = 1;
                return "/msg $channel $nick has accepted $self->{state_data}->{players}->[0]->{name}'s challenge!";
            } else {
                # wrong user tried to accept
                return "/msg $nick You have not been challenged to a game of Battleship.";
            }
        }

        # decline a challenge or forfeit/concede a game
        when (['decline', 'quit', 'forfeit', 'concede']) {
            my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

            my $removed = 0;

            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if ($self->{state_data}->{players}->[$i]->{id} == $id) {
                    $self->{state_data}->{players}->[$i]->{removed} = 1;
                    $removed = 1;
                }
            }

            if ($removed) {
                if ($self->{current_state} eq 'accept') {
                    $self->set_state('nogame');
                    $self->{state_data}->{players} = [];
                    return "/msg $channel $nick declined the challenge.";
                }
                else {
                    return "/msg $channel $nick has left the game!";
                }
            }
            else {
                return "$nick: But you are not even playing the game.";
            }
        }

        when ('abort') {
            if (not $self->{pbot}->{users}->loggedin_admin($channel, $hostmask)) {
                return "$nick: Only admins may abort the game.";
            }

            $self->set_state('gameover');

            return "/msg $channel $nick: The game has been aborted.";
        }

        when ('score') {
            if (@{$self->{state_data}->{players}} == 2) {
                $self->show_scoreboard;
                return '';
            } else {
                return "There is no game going on right now.";
            }
        }

        when ('players') {
            if ($self->{current_state} eq 'accept') {
                return "$self->{state_data}->{players}->[0]->{name} has challenged $self->{state_data}->{players}->[1]->{name}!";
            }
            elsif (@{$self->{state_data}->{players}} == 2) {
                return "$self->{state_data}->{players}->[0]->{name} is in battle with $self->{state_data}->{players}->[1]->{name}!";
            }
            else {
                return "There are no players playing right now. Start a game with `challenge <nick>`!";
            }
        }

        when ('kick') {
            if (not $self->{pbot}->{users}->loggedin_admin($channel, $hostmask)) {
                return "$nick: Only admins may kick people from the game.";
            }

            if (not length $arguments) {
                return "Usage: battleship kick <nick>";
            }

            my $removed = 0;

            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if (lc $self->{state_data}->{players}->[$i]->{name} eq $arguments) {
                    $self->{state_data}->{players}->[$i]->{removed} = 1;
                    $removed = 1;
                }
            }

            if ($removed) {
                return "/msg $channel $nick: $arguments has been kicked from the game.";
            } else {
                return "$nick: $arguments isn't even in the game.";
            }
        }

        when ('bomb') {
            if ($self->{current_state} ne 'playermove' and $self->{current_state} ne 'checkplayer') {
                return "$nick: It's not time to do that now.";
            }

            my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

            my $player;

            if ($self->{state_data}->{players}->[0]->{id} == $id) {
                $player = 0;
            }
            elsif ($self->{state_data}->{players}->[1]->{id} == $id) {
                $player = 1;
            }
            else {
                return "You are not playing in this game.";
            }

            # no arguments provided
            if (not length $arguments) {
                if (delete $self->{state_data}->{players}->[$player]->{location}) {
                    return "$nick: Attack location cleared.";
                } else {
                    return "$nick: Usage: bomb <location>";
                }
            }

            # validate arguments
            $arguments = uc $arguments;

            if ($arguments !~ m/^[A-Z][0-9]+$/) {
                return "$nick: Usage: bomb <location>; <location> must be in the form of A15, B3, C9, etc.";
            }

            # ensure arguments are within range of battlefield
            my ($x, $y) = $arguments =~ m/^(.)(.*)/;

            $x = ord($x) - 65;

            if ($x < 0 || $x > $self->{N_Y} || $y < 0 || $y > $self->{N_X}) {
                return "$nick: Target out of range, try again.";
            }

            # it's not this player's turn, go ahead and store their move
            # for when it is their turn
            if ($self->{state_data}->{current_player} != $player) {
                my $msg;
                if (not exists $self->{state_data}->{players}->[$player]->{location}) {
                    $msg = "$nick: You will attack $arguments when it is your turn.";
                }
                else {
                    $msg = "$nick: You will now attack $arguments instead of $self->{state_data}->{players}->[$player]->{location} when it is your turn.";
                }
                $self->{state_data}->{players}->[$player]->{location} = $arguments;
                return $msg;
            }

            # prevent player from attacking multiple times in one turn
            if ($self->{player}->[$player]->{done}) {
                return "$nick: You have already attacked this turn.";
            }

            # commence attack!
            if ($self->bomb($player, $arguments)) {
                if ($self->{player}->[$player]->{won}) {
                    $self->set_state('checkplayer');
                    $self->run_one_state;
                } else {
                    $self->{player}->[ $player]->{done} = 1;
                    $self->{player}->[!$player]->{done} = 0;

                    $self->{state_data}->{current_player} = !$player;

                    $self->{state_data}->{ticks}      = 1;
                    $self->{state_data}->{first_tock} = 1;
                    $self->{state_data}->{tocks}      = 0;
                }
            }

            # bomb() sent bombing output to channel
            return '';
        }

        when (['specboard', 'board']) {
            if (grep { $_ eq $self->{current_state} } qw/nogame accept genboard gameover/) {
                return "$nick: There is no board to show right now.";
            }

            # specifically show spectator board, even if invoked by a player
            if ($_ eq 'specboard') {
                $self->show_battlefield(2);
                return '';
            }

            my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

            # show player's personal board if `id` is playing
            for (my $i = 0; $i < 2; $i++) {
                if ($self->{state_data}->{players}->[$i]->{id} == $id) {
                    $self->send_message($channel, "$nick surveys the battlefield!");
                    $self->show_battlefield($i);
                    return '';
                }
            }

            # otherwise show spectator board
            $self->show_battlefield(2);
        }

        # this command shows both player's ships and all information
        when ('fullboard') {
            if (not $self->{pbot}->{users}->loggedin_admin($channel, $hostmask)) {
                return "$nick: Only admins may see the full board.";
            }

            if (grep { $_ eq $self->{current_state} } qw/nogame accept genboard gameover/) {
                return "$nick: There is no board to show right now.";
            }

            # show real board if admin is actually in the game ... no cheating!
            my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
            for (my $i = 0; $i < 2; $i++) {
                if ($self->{state_data}->{players}->[$i]->{id} == $id) {
                    $self->send_message($channel, "$nick surveys the battlefield!");
                    $self->show_battlefield($i);
                    return '';
                }
            }

            # show full board
            $self->show_battlefield(4, $nick);
        }

        default { return $usage; }
    }
}

# add a message to PBot output queue, optionally with a delay
sub send_message {
    my ($self, $to, $text, $delay) = @_;

    $delay //= 0;

    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

    my $message = {
        nick       => $botnick,
        user       => 'battleship',
        host       => 'localhost',
        hostmask   => "$botnick!battleship\@localhost",
        command    => 'battleship',
        checkflood => 1,
        message    => $text
    };

    $self->{pbot}->{interpreter}->add_message_to_output_queue($to, $message, $delay);
}

# some colors for IRC messages
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

    reset     => "\x0F",
);

# battleship stuff

sub init_game {
    my ($self, $nick1, $nick2) = @_;

    $self->{N_X}   = 15;
    $self->{N_Y}   = 8;
    $self->{SHIPS} = 6;

    for (my $ship = 0; $ship < $self->{SHIPS}; $ship++) {
        $self->{ship_length}->[$ship] = 0;
    }

    $self->{board} = [];

    $self->{player} = [
        { bombs => 0, hit => 0, miss => 0, sunk => 0, nick => $nick1, done => 0 },
        { bombs => 0, hit => 0, miss => 0, sunk => 0, nick => $nick2, done => 0 },
    ];

    $self->{horiz} = 0;

    $self->generate_battlefield;
}

sub count_ship_sections {
    my ($self, $player) = @_;

    my $sections = 0;

    for (my $x = 0; $x < $self->{N_Y}; $x++) {
        for (my $y = 0; $y < $self->{N_X}; $y++) {
            if ($player == 0) {
                if (   $self->{board}->[$x][$y] eq $self->{player_two_vert}
                    || $self->{board}->[$x][$y] eq $self->{player_two_horiz})
                {
                    $sections++;
                }
            } else {
                if (   $self->{board}->[$x][$y] eq $self->{player_one_vert}
                    || $self->{board}->[$x][$y] eq $self->{player_one_horiz})
                {
                    $sections++;
                }
            }
        }
    }

    return $sections;
}

sub check_ship {
    my ($self, $x, $y, $o, $d, $l) = @_;

    my ($xd, $yd, $i);

    if (!$o) {
        if (!$d) {
            $yd = -1;
            if ($y - $l < 0) {
                return 0;
            }
        } else {
            $yd = 1;
            if ($y + $l >= $self->{N_X}) {
                return 0;
            }
        }
        $xd = 0;
    } else {
        if (!$d) {
            $xd = -1;
            if ($x - $l < 0) {
                return 0;
            }
        } else {
            $xd = 1;
            if ($x + $l >= $self->{N_Y}) {
                return 0;
            }
        }
        $yd = 0;
    }

    for (my $i = 0; $i < $l; $i++) {
        if ($self->{board}->[$x += $o ? $xd : 0][$y += $o ? 0 : $yd] ne $self->{ocean}) {
            return 0;
        }
    }

    return 1;
}

sub number {
    my ($self, $lower, $upper) = @_;
    return int rand($upper - $lower) + $lower;
}

sub generate_ship {
    my ($self, $player, $ship) = @_;

    my ($x, $y, $o, $d, $i, $l);
    my ($yd, $xd) = (0, 0);

    my $fail = 0;

    while (1) {
        $x = $self->number(0, $self->{N_Y});
        $y = $self->number(0, $self->{N_X});

        $o = $self->number(1, 10) < 6;
        $d = $self->number(1, 10) < 6;

        if ($self->{ship_length}->[$ship]) {
            $l = $self->{ship_length}->[$ship];
        } else {
            $l = $self->number(3, 6);
        }

        if ($self->{debug}) {
            $self->{pbot}->{logger}->log("generate ships player $player: ship $ship x,y: $x,$y  o,d: $o,$d length: $l\n");
        }

        if ($self->check_ship($x, $y, $o, $d, $l)) {
            if (!$o) {
                if ($self->{horiz} < 2) {
                    next;
                }

                if (!$d) {
                    $yd = -1;
                } else {
                    $yd = 1;
                }

                $xd = 0;
            } else {
                $self->{horiz}++;

                if (!$d) {
                    $xd = -1;
                } else {
                    $xd = 1;
                }

                $yd = 0;
            }

            for (my $i = 0; $i < $l; $i++) {
                $self->{board}->[$x += $o ? $xd : 0][$y += $o ? 0 : $yd] =
                  $player ? ($o ? $self->{player_two_vert} : $self->{player_two_horiz}) : ($o ? $self->{player_one_vert} : $self->{player_one_horiz});
            }

            $self->{ship_length}->[$ship] = $l;
            return 1;
        }

        if (++$fail >= 5000) {
            $self->{pbot}->{logger}->log("Failed to generate ship\n");
            $self->send_message($self->{channel}, "Failed to place a ship. I cannot continue. Game over.");
            $self->set_state('nogame');
            return 0;
        }
    }
}

sub generate_battlefield {
    my ($self) = @_;

    for (my $y = 0; $y < $self->{N_Y}; $y++) {
        for (my $x = 0; $x < $self->{N_X}; $x++) {
            $self->{board}->[$y][$x] = $self->{ocean};
        }
    }

    for (my $x = 0; $x < $self->{SHIPS}; $x++) {
        if (!$self->generate_ship(0, $x) || !$self->generate_ship(1, $x)) {
            return 0;
        }
    }

    return 1;
}

sub check_sunk {
    my ($self, $x, $y, $player) = @_;

    my $target = $self->{board}->[$x][$y];

    given ($target) {
        when ($_ eq $self->{player_two_vert} or $_ eq $self->{player_one_vert}) {
            for (my $i = $x + 1; $i < $self->{N_Y}; $i++) {
                if (   ($self->{board}->[$i][$y] eq $self->{player_one_vert} && $player)
                    || ($self->{board}->[$i][$y] eq $self->{player_two_vert} && !$player))
                {
                    return 0;
                }

                if (   $self->{board}->[$i][$y] eq $self->{ocean}
                    || $self->{board}->[$i][$y] eq $self->{player_one_miss}
                    || $self->{board}->[$i][$y] eq $self->{player_two_miss})
                {
                    last;
                }
            }

            for (my $i = $x - 1; $i >= 0; $i--) {
                if (   ($self->{board}->[$i][$y] eq $self->{player_one_vert} && $player)
                    || ($self->{board}->[$i][$y] eq $self->{player_two_vert} && !$player))
                {
                    return 0;
                }

                if (   $self->{board}->[$i][$y] eq $self->{ocean}
                    || $self->{board}->[$i][$y] eq $self->{player_one_miss}
                    || $self->{board}->[$i][$y] eq $self->{player_two_miss})
                {
                    last;
                }
            }

            return 1;
        }

        when ($_ eq $self->{player_one_horiz} or $_ eq $self->{player_two_horiz}) {
            for (my $i = $y + 1; $i < $self->{N_X}; $i++) {
                if (   ($self->{board}->[$x][$i] eq $self->{player_one_horiz} && $player)
                    || ($self->{board}->[$x][$i] eq $self->{player_two_horiz} && !$player))
                {
                    return 0;
                }

                if ($self->{board}->[$x][$i] eq $self->{ocean}
                    || $self->{board}->[$x][$i] eq $self->{player_one_miss}
                    || $self->{board}->[$x][$i] eq $self->{player_two_miss}) {
                    last;
                }
            }

            for (my $i = $y - 1; $i >= 0; $i--) {
                if (   ($self->{board}->[$x][$i] eq $self->{player_one_horiz} && $player)
                    || ($self->{board}->[$x][$i] eq $self->{player_two_horiz} && !$player))
                {
                    return 0;
                }

                if (   $self->{board}->[$x][$i] eq $self->{ocean}
                    || $self->{board}->[$x][$i] eq $self->{player_one_miss}
                    || $self->{board}->[$x][$i] eq $self->{player_two_miss})
                {
                    last;
                }
            }

            return 1;
        }
    }
}

sub bomb {
    my ($self, $player, $location) = @_;

    my ($hit, $sections, $sunk) = (0, 0, 0, 0, 0);

    my ($x, $y) = $location =~ /^(.)(.*)/;
    $x = ord($x) - 65;
    $y--;

    if (!$player) {
        if (   $self->{board}->[$x][$y] eq $self->{player_two_vert}
            || $self->{board}->[$x][$y] eq $self->{player_two_horiz})
        {
            $hit = 1;
        }
    } else {
        if (   $self->{board}->[$x][$y] eq $self->{player_one_vert}
            || $self->{board}->[$x][$y] eq $self->{player_one_horiz})
        {
            $hit = 1;
        }
    }

    $sunk = $self->check_sunk($x, $y, $player);

    if ($hit) {
        if (!$player) {
            $self->{board}->[$x][$y] = $self->{player_one_hit};
        } else {
            $self->{board}->[$x][$y] = $self->{player_two_hit};
        }

        $self->{player}->[$player]->{hit}++;
    } else {
        if ($self->{board}->[$x][$y] eq $self->{ocean}) {
            if (!$player) {
                $self->{board}->[$x][$y] = $self->{player_one_miss};
            } else {
                $self->{board}->[$x][$y] = $self->{player_two_miss};
            }

            $self->{player}->[$player]->{miss}++;
        }
    }

    my $nick1 = $self->{player}->[ $player]->{nick};
    my $nick2 = $self->{player}->[!$player]->{nick};

    my @attacks = (
        "launches torpedoes at",
        "launches nukes at",
        "fires cannons at",
        "fires torpedoes at",
        "fires nukes at",
        "launches tomahawk missiles at",
        "fires a gatling gun at",
        "launches ballistic missiles at",
    );

    my $attacked = $attacks[rand @attacks];

    if ($hit) {
        $self->send_message($self->{channel}, "$nick1 $attacked $nick2 at $location! $color{red}--- HIT! --- $color{reset}");

        $self->{player}->[$player]->{destroyed}++;

        if ($sunk) {
            $self->{player}->[$player]->{sunk}++;
            my $remaining = $self->count_ship_sections($player);
            $self->send_message($self->{channel}, "$color{red}$nick1 has sunk ${nick2}'s ship! $remaining ship section" . ($remaining != 1 ? 's' : '') . " remaining!$color{reset}");

            if ($remaining == 0) {
                $self->send_message($self->{channel}, "$nick1 has WON the game of Battleship!");
                $self->{player}->[$player]->{won} = 1;
            }
        }
    } else {
        $self->send_message($self->{channel}, "$nick1 $attacked $nick2 at $location! --- miss ---");
    }

    $self->{player}->[$player]->{bombs}++;
    return 1;
}

sub show_scoreboard {
    my ($self) = @_;

    my $p1sections = $self->count_ship_sections(1);
    my $p2sections = $self->count_ship_sections(0);

    my $p1win = '';
    my $p2win = '';

    if ($p1sections > $p2sections) {
        $p1win = "$color{bold}$color{lightgreen} * ";
        $p2win = "$color{red}   ";
    } elsif ($p1sections < $p2sections) {
        $p1win = "$color{red}   ";
        $p2win = "$color{bold}$color{lightgreen} * ";
    }

    my $length_a = length $self->{player}->[0]->{nick};
    my $length_b = length $self->{player}->[1]->{nick};
    my $longest  = $length_a > $length_b ? $length_a : $length_b;

    my $bombslen  = ($self->{player}->[0]->{bombs} > 10 || $self->{player}->[1]->{bombs} > 10) ? 2 : 1;
    my $hitlen    = ($self->{player}->[0]->{hit}   > 10 || $self->{player}->[1]->{hit}   > 10) ? 2 : 1;
    my $misslen   = ($self->{player}->[0]->{miss}  > 10 || $self->{player}->[1]->{miss}  > 10) ? 2 : 1;
    my $sunklen   = ($self->{player}->[0]->{sunk}  > 10 || $self->{player}->[1]->{sunk}  > 10) ? 2 : 1;
    my $intactlen = ($p1sections                   > 10 || $p2sections                   > 10) ? 2 : 1;

    my $p1bombscolor  = $self->{player}->[0]->{bombs} > $self->{player}->[1]->{bombs} ? $color{green} : $color{red};
    my $p1hitcolor    = $self->{player}->[0]->{hit}   > $self->{player}->[1]->{hit}   ? $color{green} : $color{red};
    my $p1misscolor   = $self->{player}->[0]->{miss}  < $self->{player}->[1]->{miss}  ? $color{green} : $color{red};
    my $p1sunkcolor   = $self->{player}->[0]->{sunk}  > $self->{player}->[1]->{sunk}  ? $color{green} : $color{red};
    my $p1intactcolor = $p1sections                   > $p2sections                   ? $color{green} : $color{red};

    my $p2bombscolor  = $self->{player}->[0]->{bombs} < $self->{player}->[1]->{bombs} ? $color{green} : $color{red};
    my $p2hitcolor    = $self->{player}->[0]->{hit}   < $self->{player}->[1]->{hit}   ? $color{green} : $color{red};
    my $p2misscolor   = $self->{player}->[0]->{miss}  > $self->{player}->[1]->{miss}  ? $color{green} : $color{red};
    my $p2sunkcolor   = $self->{player}->[0]->{sunk}  < $self->{player}->[1]->{sunk}  ? $color{green} : $color{red};
    my $p2intactcolor = $p1sections                   < $p2sections                   ? $color{green} : $color{red};

    my $buf;

    $buf = sprintf(
        "$p1win%*s$color{reset}: bomb: $p1bombscolor%*d$color{reset}, hit: $p1hitcolor%*d$color{reset}, miss: $p1misscolor%*d$color{reset}, sunk: $p1sunkcolor%*d$color{reset}, sections left: $p1intactcolor%*d$color{reset}",
        $longest, $self->{player}->[0]->{nick}, $bombslen,  $self->{player}->[0]->{bombs},
        $hitlen,  $self->{player}->[0]->{hit},  $misslen,   $self->{player}->[0]->{miss},
        $sunklen, $self->{player}->[0]->{sunk}, $intactlen, $p1sections
    );

    $self->send_message($self->{channel}, $buf);

    $buf = sprintf(
        "$p2win%*s$color{reset}: bomb: $p2bombscolor%*d$color{reset}, hit: $p2hitcolor%*d$color{reset}, miss: $p2misscolor%*d$color{reset}, sunk: $p2sunkcolor%*d$color{reset}, sections left: $p2intactcolor%*d$color{reset}",
        $longest, $self->{player}->[1]->{nick}, $bombslen,  $self->{player}->[1]->{bombs},
        $hitlen,  $self->{player}->[1]->{hit},  $misslen,   $self->{player}->[1]->{miss},
        $sunklen, $self->{player}->[1]->{sunk}, $intactlen, $p2sections
    );

    $self->send_message($self->{channel}, $buf);
}

sub show_battlefield {
    my ($self, $player, $nick) = @_;

    $self->{pbot}->{logger}->log("Showing battlefield for player $player\n");

    my $buf = "$color{cyan},01  ";

    for (my $x = 1; $x < $self->{N_X} + 1; $x++) {
        if ($x % 10 == 0) {
            $buf .= "$color{yellow},01" if $self->{N_X} > 10;
            $buf .= $x % 10;
            $buf .= ' ';
            $buf .= "$color{cyan},01" if $self->{N_X} > 10;
        } else {
            $buf .= $x % 10;
            $buf .= ' ';
        }
    }

    $buf .= "\n";

    for (my $y = 0; $y < $self->{N_Y}; $y++) {

        $buf .= sprintf("$color{cyan},01%c ", 97 + $y);

        for (my $x = 0; $x < $self->{N_X}; $x++) {

            if ($player == 0) {
                if ($self->{board}->[$y][$x] eq $self->{player_two_vert}
                    || $self->{board}->[$y][$x] eq $self->{player_two_horiz})
                {
                    $buf .= "$color{blue},01$self->{ocean} ";
                    next;
                } else {
                    if ($self->{board}->[$y][$x] eq $self->{player_one_hit}
                        || $self->{board}->[$y][$x] eq $self->{player_two_hit})
                    {
                        $buf .= "$color{red},01";
                    }
                    elsif ($self->{board}->[$y][$x] eq $self->{player_two_miss}
                        || $self->{board}->[$y][$x] eq $self->{player_one_miss})
                    {
                        $buf .= "$color{cyan},01";
                    }
                    elsif ($self->{board}->[$y][$x] eq $self->{ocean})
                    {
                        $buf .= "$color{blue},01$self->{ocean} ";
                        next;
                    } else {
                        $buf .= "$color{white},01";
                    }

                    $buf .= "$self->{board}->[$y][$x] ";
                }
            } elsif ($player == 1) {
                if ($self->{board}->[$y][$x] eq $self->{player_one_vert}
                    || $self->{board}->[$y][$x] eq $self->{player_one_horiz})
                {
                    $buf .= "$color{blue},01$self->{ocean} ";
                    next;
                } else {
                    if ($self->{board}->[$y][$x] eq $self->{player_one_hit}
                        || $self->{board}->[$y][$x] eq $self->{player_two_hit})
                    {
                        $buf .= "$color{red},01";
                    }
                    elsif ($self->{board}->[$y][$x] eq $self->{player_two_miss}
                        || $self->{board}->[$y][$x] eq $self->{player_one_miss})
                    {
                        $buf .= "$color{cyan},01";
                    }
                    elsif ($self->{board}->[$y][$x] eq $self->{ocean})
                    {
                        $buf .= "$color{blue},01$self->{ocean} ";
                        next;
                    } else {
                        $buf .= "$color{white},01";
                    }

                    $buf .= "$self->{board}->[$y][$x] ";
                }
            } elsif ($player == 2) {
                if ($self->{board}->[$y][$x] eq $self->{player_one_vert}
                    || $self->{board}->[$y][$x] eq $self->{player_one_horiz}
                    || $self->{board}->[$y][$x] eq $self->{player_two_vert}
                    || $self->{board}->[$y][$x] eq $self->{player_two_horiz})
                {
                    $buf .= "$color{blue},01$self->{ocean} ";
                    next;
                } else {
                    if ($self->{board}->[$y][$x] eq $self->{player_one_hit}
                        || $self->{board}->[$y][$x] eq $self->{player_two_hit})
                    {
                        $buf .= "$color{red},01";
                    }
                    elsif ($self->{board}->[$y][$x] eq $self->{player_two_miss}
                        || $self->{board}->[$y][$x] eq $self->{player_one_miss})
                    {
                        $buf .= "$color{cyan},01";
                    }
                    elsif ($self->{board}->[$y][$x] eq $self->{ocean})
                    {
                        $buf .= "$color{blue},01$self->{ocean} ";
                        next;
                    } else {
                        $buf .= "$color{white},01";
                    }

                    $buf .= "$self->{board}->[$y][$x] ";
                }
            } else {
                if ($self->{board}->[$y][$x] eq $self->{player_one_hit}
                    || $self->{board}->[$y][$x] eq $self->{player_two_hit})
                {
                    $buf .= "$color{red},01";
                }
                elsif ($self->{board}->[$y][$x] eq $self->{player_two_miss}
                    || $self->{board}->[$y][$x] eq $self->{player_one_miss})
                {
                    $buf .= "$color{cyan},01";
                }
                elsif ($self->{board}->[$y][$x] eq $self->{ocean})
                {
                    $buf .= "$color{blue},01$self->{ocean} ";
                    next;
                } else {
                    $buf .= "$color{white},01";
                }

                $buf .= "$self->{board}->[$y][$x] ";
            }
        }

        $buf .= sprintf("$color{cyan},01%c", 97 + $y);
        $buf .= "$color{reset}\n";
    }

    # bottom border
    $buf .= "$color{cyan},01  ";

    for (my $x = 1; $x < $self->{N_X} + 1; $x++) {
        if ($x % 10 == 0) {
            $buf .= $color{yellow}, 01 if $self->{N_X} > 10;
            $buf .= $x % 10;
            $buf .= ' ';
            $buf .= $color{cyan}, 01 if $self->{N_X} > 10;
        } else {
            $buf .= $x % 10;
            $buf .= ' ';
        }
    }

    $buf .= "\n";

    my $player1 = $self->{player}->[0]->{nick};
    my $player2 = $self->{player}->[1]->{nick};

    if ($player == 0) {
        $self->send_message(
            $self->{player}->[$player]->{nick},
            "Player One Legend: ships: [$self->{player_one_vert} $self->{player_one_horiz}]  ocean: [$color{blue},01$self->{ocean}$color{reset}]  $player1 miss: [$color{cyan},01$self->{player_one_miss}$color{reset}]  $player2 miss: [$color{cyan},01$self->{player_two_miss}$color{reset}]  $player1 hit: [$color{red},01"
              . $self->{player_one_hit}
              . "$color{reset}]  $player2 hit: [$color{red},01$self->{player_two_hit}$color{reset}]"
        );
    } elsif ($player == 1) {
        $self->send_message(
            $self->{player}->[$player]->{nick},
            "Player Two Legend: ships: [$self->{player_two_vert} $self->{player_two_horiz}]  ocean: [$color{blue},01$self->{ocean}$color{reset}]  $player1 miss: [$color{cyan},01$self->{player_one_miss}$color{reset}]  $player2 miss: [$color{cyan},01$self->{player_two_miss}$color{reset}]  $player1 hit: [$color{red},01"
              . $self->{player_one_hit}
              . "$color{reset}]  $player2 hit: [$color{red},01$self->{player_two_hit}$color{reset}]"
        );
    } elsif ($player == 2) {
        $self->send_message(
            $self->{channel},
            "Spectator Legend: ocean: [$color{blue},01$self->{ocean}$color{reset}]  $player1 miss: [$color{cyan},01$self->{player_one_miss}$color{reset}]  $player2 miss: [$color{cyan},01$self->{player_two_miss}$color{reset}]  $player1 hit: [$color{red},01"
              . $self->{player_one_hit}
              . "$color{reset}]  $player2 hit: [$color{red},01$self->{player_two_hit}$color{reset}]"
        );
    } elsif ($player == 3) {
        $self->send_message(
            $self->{channel},
            "Final Board Legend: $player1 ships: [$self->{player_one_vert} $self->{player_one_horiz}] $player2 ships: [$self->{player_two_vert} $self->{player_two_horiz}]  ocean: [$color{blue},01$self->{ocean}$color{reset}]  $player1 miss: [$color{cyan},01$self->{player_one_miss}$color{reset}]  $player2 miss: [$color{cyan},01$self->{player_two_miss}$color{reset}]  $player1 hit: [$color{red},01"
              . $self->{player_one_hit}
              . "$color{reset}]  $player2 hit: [$color{red},01$self->{player_two_hit}$color{reset}]"
        );
    } else {
        $self->send_message(
            $nick,
            "Full Board Legend: $player1 ships: [$self->{player_one_vert} $self->{player_one_horiz}] $player2 ships: [$self->{player_two_vert} $self->{player_two_horiz}]  ocean: [$color{blue},01$self->{ocean}$color{reset}]  $player1 miss: [$color{cyan},01$self->{player_one_miss}$color{reset}]  $player2 miss: [$color{cyan},01$self->{player_two_miss}$color{reset}]  $player1 hit: [$color{red},01"
              . $self->{player_one_hit}
              . "$color{reset}]  $player2 hit: [$color{red},01$self->{player_two_hit}$color{reset}]"
        );
    }

    foreach my $line (split /\n/, $buf) {
        if ($player == 0 || $player == 1) {
            $self->send_message($self->{player}->[$player]->{nick}, $line);
        }
        elsif ($player == 2 || $player == 3) {
            $self->send_message($self->{channel}, $line);
        }
        else {
            $self->send_message($nick, $line);
        }
    }
}

# game state machine stuff

# do one loop of the game engine
sub run_one_state {
    my ($self) = @_;

    # check for naughty or missing players
    for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
        if ($self->{state_data}->{players}->[$i]->{missedinputs} >= 3) {
            # remove player if they have missed 3 inputs
            $self->send_message(
                $self->{channel},
                "$color{red}$self->{state_data}->{players}->[$i]->{name} has missed too many prompts and has been ejected from the game!$color{reset}"
            );

            $self->{state_data}->{players}->[$i]->{removed} = 1;
        }

        if ($self->{state_data}->{players}->[$i]->{removed}) {
            # end game if a player has been removed
            $self->set_state('gameover');
            last;
        }
    }

    # transitioned to a brand new state; prepare first tock
    if ($self->{previous_state} ne $self->{current_state}) {
        $self->{state_data}->{ticks}      = 1;
        $self->{state_data}->{first_tock} = 1;
        $self->{state_data}->{tocks}      = 0;

        # dump new state data for logging/debugging
        if ($self->{debug}) {
            $Data::Dumper::Useqq    = 1;
            $Data::Dumper::Sortkeys = 1;
            $self->{pbot}->{logger}->log("Battleship: New state: $self->{current_state}\n" . Dumper $self->{state_data});
        }
    }

    # run one state/tick
    $self->{states}->{$self->{current_state}}->{sub}->($self->{state_data});

    # transition to next state
    $self->{previous_state} = $self->{current_state};
    $self->{current_state}  = $self->{states}->{$self->{current_state}}->{trans}->{$self->{state_data}->{trans}};

    # reset tick-tock once we've tocked
    if ($self->{state_data}->{tocked}) {
        $self->{state_data}->{tocked}     = 0;
        $self->{state_data}->{ticks}      = 0;
        $self->{state_data}->{first_tock} = 0;
    }

    # next tick
    $self->{state_data}->{ticks}++;
}

# skip directly to a state
sub set_state {
    my ($self, $newstate) = @_;
    $self->{previous_state} = $self->{current_state};
    $self->{current_state}  = $newstate;
    $self->{state_data}->{ticks} = 0;
}

# set up game state machine
sub create_states {
    my ($self) = @_;

    $self->{pbot}->{logger}->log("Battleship: Creating game state machine\n");

    # initialize default state
    $self->{previous_state} = '';
    $self->{current_state}  = 'nogame';

    # initialize state data
    $self->{state_data} = {
        players        => [], # array of player data
        ticks          => 0,  # number of ticks elapsed
        current_player => 0,  # whose turn is it?
    };

    $self->{states} = {
        nogame => {
            sub => sub { $self->nogame(@_) },

            trans => {
                challenge => 'accept',
                nogame    => 'nogame',
            }
        },

        accept => {
            sub => sub { $self->accept(@_) },

            trans => {
                stop   => 'nogame',
                wait   => 'accept',
                accept => 'genboard',
            }
        },

        genboard => {
            sub => sub { $self->genboard(@_) },

            trans => {
                next => 'showboard',
            }
        },

        showboard => {
            sub => sub { $self->showboard(@_) },

            trans => {
                next => 'playermove',
            }
        },

        playermove => {
            sub => sub { $self->playermove(@_) },

            trans => {
                wait => 'playermove',
                next => 'checkplayer',
            }
        },

        checkplayer => {
            sub => sub { $self->checkplayer(@_) },

            trans => {
                gotwinner => 'gameover',
                next      => 'playermove',
            }
        },

        gameover => {
            sub => sub { $self->gameover(@_) },

            trans => {
                wait => 'gameover',
                next => 'nogame',
            }
        },
    };
}

# game states

sub nogame {
    my ($self, $state) = @_;
    $state->{trans} = 'nogame';
    $self->{pbot}->{event_queue}->update_repeating('battleship loop', 0);
}

sub accept {
    my ($self, $state) = @_;

    $state->{tock_limit} = 3;

    if ($state->{players}->[1]->{accepted}) {
        $state->{trans} = 'accept';
        return;
    }

    my $tock = 15;

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        if (++$state->{tocks} > $state->{tock_limit}) {
            if ($state->{players}->[1]->{id} == -1) { $self->send_message($self->{channel}, "Nobody has accepted $state->{players}->[0]->{name}'s challenge."); }
            else { $self->send_message($self->{channel}, "$state->{players}->[1]->{name} has failed to accept $state->{players}->[0]->{name}'s challenge."); }
            $state->{trans}   = 'stop';
            $state->{players} = [];
            return;
        }

        if ($state->{players}->[1]->{id} == -1) {
            $self->send_message($self->{channel}, "$state->{players}->[0]->{name} has made an open challenge! Use `accept` to accept their challenge.");
        } else {
            $self->send_message($self->{channel}, "$state->{players}->[1]->{name}: $state->{players}->[0]->{name} has challenged you! Use `accept` to accept their challenge.");
        }
    }

    $state->{trans} = 'wait';
}

sub genboard {
    my ($self, $state) = @_;
    $self->init_game($state->{players}->[0]->{name}, $state->{players}->[1]->{name});
    $state->{current_player} = 0;
    $state->{tock_limit}     = 3;
    $state->{trans}          = 'next';
}

sub showboard {
    my ($self, $state) = @_;
    $self->send_message($self->{channel}, "Showing battlefield to $self->{player}->[0]->{nick}...");
    $self->show_battlefield(0);
    $self->send_message($self->{channel}, "Showing battlefield to $self->{player}->[1]->{nick}...");
    $self->show_battlefield(1);
    $self->send_message($self->{channel}, "Fight! Anybody (players and spectators) can use `board` at any time to see the battlefield.");
    $state->{trans} = 'next';
}

sub playermove {
    my ($self, $state) = @_;

    my $tock = 15;

    if ($state->{first_tock}) {
        $tock = 3;
    }

    if ($self->{player}->[$state->{current_player}]->{done}) {
        $state->{trans} = 'next';
        return;
    }

    my $player   = $state->{current_player};
    my $location = delete $state->{players}->[$player]->{location};

    if (defined $location) {
        if ($self->bomb($player, $location)) {
            $self->{player}->[$player]->{done}    = 1;
            $self->{player}->[!$player]->{done}   = 0;
            $self->{state_data}->{current_player} = !$player;
            $state->{trans}                       = 'next';
            return;
        }
    }

    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        if (++$state->{tocks} > $state->{tock_limit}) {
            $state->{players}->[$state->{current_player}]->{missedinputs}++;
            $self->send_message($self->{channel}, "$state->{players}->[$state->{current_player}]->{name} failed to launch an attack in time. They forfeit their turn!");

            $self->{player}->[$state->{current_player}]->{done}  = 1;
            $self->{player}->[!$state->{current_player}]->{done} = 0;
            $state->{current_player}                             = !$state->{current_player};
            $state->{trans}                                      = 'next';
            return;
        }

        my $red = $state->{tocks} == $state->{tock_limit} ? $color{red} : '';

        my $remaining = 15 * $state->{tock_limit};
        $remaining   -= 15 * ($state->{tocks} - 1);
        $remaining    = "(" . (concise duration $remaining) . " remaining)";

        $self->send_message($self->{channel}, "$state->{players}->[$state->{current_player}]->{name}: $red$remaining Launch an attack now via `bomb <location>`!$color{reset}");
    }

    $state->{trans} = 'wait';
}

sub checkplayer {
    my ($self, $state) = @_;

    if ($self->{player}->[0]->{won} or $self->{player}->[1]->{won}) {
        $state->{trans} = 'gotwinner';
    } else {
        $state->{trans} = 'next';
    }
}

sub gameover {
    my ($self, $state) = @_;

    if ($state->{ticks} % 5 == 0) {
        if ($state->{players}->[1]->{id} != -1 && $state->{players}->[1]->{accepted}) {
            $self->show_battlefield(3);
            $self->show_scoreboard;
            $self->send_message($self->{channel}, "Game over!");
        }

        $state->{players} = [];
        $state->{tocks}   = 0;
        $state->{trans}   = 'next';
    } else {
        $state->{trans}   = 'wait';
    }
}

1;
