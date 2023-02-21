# File: Battleship.pm
#
# Purpose: Simplified version of the Battleship board game. In this variant,
# there is one game grid/board and every player's ships share it without
# overlapping. This adds an element of strategy: everybody knows where their
# own ships are located, ergo they know where NOT to aim. This helps to speed
# games up by removing some randomness.
#
# Note: This code was written circa 1993 for a DikuMUD fork. It was originally
# written in C, as I was teaching the language to myself in my early teens. Two
# decades or so later, I transliterated this code from C to Perl for PBot. Much
# of the "ugly" C-style design of this code has been preserved for personal
# historical reasons -- I was inspired by the IOCCC and I attempted to be clever
# with nested conditional operators and other silliness. Please be gentle if you
# read this code. :)
#
# Update: Much of this code has now been refactored to support more than two
# players on a single board. The board grows in size for each additional player,
# to accomodate their ships. Whirlpools have also been added. They are initially
# hidden by the ocean. When shot, they reveal themselves on the map and deflect
# the shot to a random tile. Much of the IOCCC silliness has been removed so that
# I can maintain this code without going insane.

# SPDX-FileCopyrightText: 1993-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Battleship;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Time::Duration;
use Data::Dumper;

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

    bold       => "\x02",
    italics    => "\x1D",
    underline  => "\x1F",
    reverse    => "\x16",

    reset      => "\x0F",
);

sub initialize {
    my ($self, %conf) = @_;

    # register `battleship` bot command
    $self->{pbot}->{commands}->add(
        name   => 'battleship',
        help   => 'Battleship board game, simplified for IRC',
        subref => sub { $self->cmd_battleship(@_) },
    );

    # set the channel where to send game messages
    $self->{channel} = $self->{pbot}->{registry}->get_value('battleship', 'channel') // '##battleship';

    # debugging flag
    $self->{debug}   = $self->{pbot}->{registry}->get_value('battleship', 'debug')   // 0;

    # player limit per game
    $self->{MAX_PLAYERS} = 5;

    # max missed moves before player is ejected from game
    $self->{MAX_MISSED_MOVES} = 5;

    # types of board tiles
    $self->{TYPE_OCEAN}      = 0;
    $self->{TYPE_WHIRLPOOL}  = 1;
    $self->{TYPE_SHIP}       = 2;

    # battleship tile symbols
    $self->{TILE_HIT}        = ['1' .. $self->{MAX_PLAYERS}];
    $self->{TILE_OCEAN}      = "$color{blue}~";
    $self->{TILE_MISS}       = "$color{cyan}o";
    $self->{TILE_WHIRLPOOL}  = "$color{cyan}@";

    # personal ship tiles shown on player board
    $self->{TILE_SHIP_VERT}  = "$color{white}|";
    $self->{TILE_SHIP_HORIZ} = "$color{white}—";

    # all player ship tiles shown on final/full board
    $self->{TILE_SHIP}  = ['A' .. chr ord('A') + $self->{MAX_PLAYERS} - 1];

    # default board dimensions
    $self->{BOARD_X}         = 12;
    $self->{BOARD_Y}         = 8;

    # number of ships per player
    $self->{SHIP_COUNT}      = 6;

    # modifiers for show_battlefield()
    $self->{BOARD_SPECTATOR} = -1;
    $self->{BOARD_FINAL}     = -2;
    $self->{BOARD_FULL}      = -3;

    # ship orientation
    $self->{ORIENT_VERT}     = 0;
    $self->{ORIENT_HORIZ}    = 1;

    # paused state (0 is unpaused)
    $self->{PAUSED_BY_PLAYER}        = 1;
    $self->{PAUSED_FOR_OUTPUT_QUEUE} = 2;

    # create game state machine
    $self->create_states;

    # receive notification when all messages in IRC output queue have been sent
    $self->{pbot}->{event_dispatcher}->register_handler(
        'pbot.output_queue_empty', sub { $self->on_output_queue_empty(@_) }
    );
}

sub unload {
    my ($self) = @_;

    # unregister `battleship` bot command
    $self->{pbot}->{commands}->remove('battleship');

    # remove battleship loop event from event queue
    $self->end_game_loop;

    # remove event handler
    $self->{pbot}->{event_dispatcher}->remove_handler('pbot.output_queue_empty');
}

# the game is paused at the beginning when sending the player boards to all
# the players and then resumed when the output queue has depleted. this prevents
# game events from queuing up while the board messages are being slowly
# trickled out to the ircd to avoid filling up its message queue (and getting
# disconnected with 'excess flood'). this event handler resumes the game once
# the boards have finished transmitting, unless the game was manually paused
# by a player.
sub on_output_queue_empty {
    my ($self) = @_; # we don't care about the other event arguments

    # if we're paused waiting for the output queue, go ahead and unpause
    if ($self->{state_data}->{paused} == $self->{PAUSED_FOR_OUTPUT_QUEUE}) {
        $self->{state_data}->{paused} = 0;
    }

    return 0;
}

# `battleship` bot command
sub cmd_battleship {
    my ($self, $context) = @_;

    my $usage = "Usage: battleship challenge|accept|decline|ready|unready|bomb|board|score|players|pause|quit|kick|abort; see also: battleship help <command>";

    # strip leading and trailing whitespace
    $context->{arguments} =~ s/^\s+|\s+$//g;

    my ($command, $arguments) = split / /, $context->{arguments}, 2;

    $command //= '';
    $command = lc $command;

    $arguments //= '';
    $arguments = lc $arguments;

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

            # set game to the `challenge` state to begin accepting challenge
            $self->set_state('challenge');

            # add player 0, the challenger, to the game
            my $id = $self->get_player_id($nick, $user, $host);

            my $player = $self->new_player($id, $nick);

            # clear out player data
            $self->{state_data}->{players} = [];

            # add player 0
            push @{$self->{state_data}->{players}}, $player;

            # start the battleship game loop
            $self->begin_game_loop;

            return "/msg $channel $nick has issued a Battleship challenge! Use `accept` to accept their challenge.";
        }

        # accept a challenge
        when (['accept', 'join']) {
            if ($self->{current_state} ne 'challenge') {
                return "This is not the time to use `$command`.";
            }

            if (@{$self->{state_data}->{players}} >= $self->{MAX_PLAYERS}) {
                return "/msg $channel $nick: The player limit has been reached. Try again next game.";
            }

            my $id = $self->get_player_id($nick, $user, $host);

            # check that player hasn't already accepted/joined
            if (grep { $_->{id} == $id } @{$self->{state_data}->{players}}) {
                return "$nick: You have already joined this Battleship game.";
            }

            # add another player
            my $player = $self->new_player($id, $nick);

            $player->{index} = @{$self->{state_data}->{players}};

            push @{$self->{state_data}->{players}}, $player;

            return "/msg $channel $nick has joined the game. Use `ready` to ready-up.";
        }

        # ready/unready
        when (['ready', 'unready']) {
            if ($self->{current_state} ne 'challenge') {
                return "This is not the time to use `$command`.";
            }

            my $id = $self->get_player_id($nick, $user, $host);

            my ($player) = grep { $_->{id} == $id } @{$self->{state_data}->{players}};

            if (not defined $player) {
                return "$nick: You have not joined this game of Battleship. Use `accept` to join the game.";
            }

            if ($command eq 'ready') {
                $player->{ready} = 1;
                return "/msg $channel $nick is ready!";
            } else {
                $player->{ready} = 0;
                return "/msg $channel $nick is no longer ready.";
            }
        }

        # decline a challenge or forfeit/concede a game
        when (['decline', 'quit', 'forfeit', 'concede']) {
            my $id = $self->get_player_id($nick, $user, $host);

            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if ($self->{state_data}->{players}->[$i]->{id} == $id) {
                    if ($self->{current_state} eq 'challenge') {
                        # remove from player list now since this is only the accept
                        # stage and a game hasn't yet begun
                        splice @{$self->{state_data}->{players}}, $i, 1;
                    } else {
                        # there is an on-going game, just mark them as removed
                        $self->{state_data}->{players}->[$i]->{removed} = 1;
                    }

                    return "/msg $channel $nick has left the game!";
                }
            }

            return "There is nothing to $command.";
        }

        when ('abort') {
            if (not $self->{pbot}->{users}->loggedin_admin($channel, $hostmask)) {
                return "$nick: Only admins may abort the game.";
            }

            if ($self->{current_state} eq 'nogame') {
                return "/msg $channel $nick: There is no ongoing game to abort.";
            }

            # jump directly to the `gameover` state to
            # show the final board and reset the game
            $self->set_state('gameover');

            return "/msg $channel $nick: The game has been aborted.";
        }

        when (['pause', 'unpause']) {
            if ($command eq 'pause') {
                $self->{state_data}->{paused} = $self->{PAUSED_BY_PLAYER};
            } else {
                $self->{state_data}->{paused} = 0;
            }

            return "/msg $channel $nick has " . ($self->{state_data}->{paused} ? 'paused' : 'unpaused') . " the game!";
        }

        when ('score') {
            if ($self->{current_state} ne 'move' and $self->{current_state} ne 'attack') {
                return "There is no Battleship score to show right now.";
            }

            $self->show_scoreboard;
            return '';
        }

        when ('players') {
            if (not @{$self->{state_data}->{players}}) {
                return "There are no players playing Battleship right now. Start a game with the `challenge` command!";
            }

            $self->list_players;
            return '';
        }

        when ('kick') {
            if (not $self->{pbot}->{users}->loggedin_admin($channel, $hostmask)) {
                return "$nick: Only admins may kick players from the game.";
            }

            if (not length $arguments) {
                return "Usage: battleship kick <nick>";
            }

            # get the id associated with this nick, in case the current player has changed nick while playing
            my ($id) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($arguments);

            if (not defined $id) {
                return "I don't know anybody named $arguments.";
            }

            $id = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($id);

            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if (lc $self->{state_data}->{players}->[$i]->{id} == $id) {
                    $self->{state_data}->{players}->[$i]->{removed} = 1;
                    return "/msg $channel $nick: $arguments has been kicked from the game.";
                }
            }

            return "$nick: $arguments isn't even in the game.";
        }

        when ('bomb') {
            if ($self->{current_state} ne 'move' and $self->{current_state} ne 'attack') {
                return "$nick: It's not time to do that now.";
            }

            my $id = $self->get_player_id($nick, $user, $host);

            my ($player) = grep { $_->{id} == $id } @{$self->{state_data}->{players}};

            if (not defined $player) {
                return "You are not playing in this game.";
            }

            # no arguments provided
            if (not length $arguments) {
                if (delete $player->{location}) {
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

            my $msg;
            if (not exists $player->{location}) {
                $msg = "/msg $channel $nick aims somewhere.";
            }
            elsif (lc $player->{location} eq lc $arguments) {
                return '';
            }
            else {
                $msg = "/msg $channel $nick aims somewhere else.";
            }
            $player->{location} = $arguments;
            return $msg;
        }

        when (['specboard', 'board']) {
            if (grep { $_ eq $self->{current_state} } qw/nogame challenge genboard gameover/) {
                return "$nick: There is no board to show right now.";
            }

            # specifically show spectator board, even if invoked by a player
            if ($_ eq 'specboard') {
                $self->show_battlefield($self->{BOARD_SPECTATOR});
                return '';
            }

            my $id = $self->get_player_id($nick, $user, $host);

            # show player's personal board if playing
            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if ($self->{state_data}->{players}->[$i]->{id} == $id) {
                    if ($self->{state_data}->{players}->[$i]->{removed}) {
                        return "$nick: You have been removed from this game. Try again next game.";
                    }

                    $self->send_message($channel, "$nick surveys the battlefield!");
                    $self->show_battlefield($i);
                    return '';
                }
            }

            # otherwise show spectator board
            $self->show_battlefield($self->{BOARD_SPECTATOR});
            return '';
        }

        # this command shows the entire battlefield
        when ('fullboard') {
            if (not $self->{pbot}->{users}->loggedin_admin($channel, $hostmask)) {
                return "$nick: Only admins may see the full board.";
            }

            if (grep { $_ eq $self->{current_state} } qw/nogame challenge genboard gameover/) {
                return "$nick: There is no board to show right now.";
            }

            # show real board if admin is in the game ... no cheating!
            my $id = $self->get_player_id($nick, $user, $host);
            for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
                if ($self->{state_data}->{players}->[$i]->{id} == $id) {
                    $self->send_message($channel, "$nick surveys the battlefield!");
                    $self->show_battlefield($i);
                    return '';
                }
            }

            # show full board
            $self->show_battlefield($self->{BOARD_FULL}, $nick);
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

# get unambiguous internal id for player hostmask
sub get_player_id {
    my ($self, $nick, $user, $host) = @_;
    my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
    return   $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($id);
}

# create a new player hash
sub new_player {
    my ($self, $id, $nick) = @_;

    return {
        id           => $id,
        name         => $nick,
        index        => 0,
        ready        => 0,
        health       => 0,
        ships        => 0,
        shots        => 0,
        hit          => 0,
        miss         => 0,
        sunk         => 0,
        lost         => 0,
        missedinputs => 0,
    };
}

# get a random number interval [lower, upper)
sub number {
    my ($self, $lower, $upper) = @_;
    return int rand($upper - $lower) + $lower;
}

# battleship stuff

sub begin_game_loop {
    my ($self) = @_;
    # add `battleship loop` event repeating at 1s interval
    $self->{pbot}->{event_queue}->enqueue_event(
        sub {
            $self->run_one_state;
        },
        1, 'battleship loop', 1
    );
}

sub end_game_loop {
    my ($self) = @_;
    # remove `battleship loop` event

    # repeating events get added back to event queue if we attempt to
    # dequeue_event() from within the event itself. we turn repeating
    # off to ensure the event gets removed when it completes.
    $self->{pbot}->{event_queue}->update_repeating('battleship loop', 0);

    # dequeue event.
    $self->{pbot}->{event_queue}->dequeue_event('battleship loop', 0);
}

sub init_game {
    my ($self, $state) = @_;

    # default board dimensions
    $self->{N_X}   = $self->{BOARD_X};
    $self->{N_Y}   = $self->{BOARD_Y};

    # increase board width by player count
    $self->{N_X} += @{$state->{players}} * 2;

    # default count of ships per player
    $self->{SHIPS} = $self->{SHIP_COUNT};

    # initialize ship length fields
    for (my $ship = 0; $ship < $self->{SHIPS}; $ship++) {
        $self->{ship_length}->[$ship] = 0;
    }

    # the battleship board/grid. all ships share the same grid to add an
    # element of strategy (namely, ships cannot overlap thus you know
    # where your enemy ships are NOT located, which narrows the battle
    # field and helps speed games up)
    $self->{board} = [];

    # reset winner flag
    $self->{got_winner} = 0;

    # place ships and ocean tiles
    return $self->generate_battlefield;
}

# ensures a ship can be placed at this location (all desired tiles are ocean)
sub check_ship_placement {
    my ($self, $x, $y, $o, $l) = @_;

    my ($xd, $yd, $i);

    if ($o == $self->{ORIENT_VERT}) {
        if ($y + $l >= $self->{N_Y}) {
            return 0;
        }
        $xd = 0;
        $yd = 1;
    } else {
        if ($x + $l >= $self->{N_X}) {
            return 0;
        }
        $xd = 1;
        $yd = 0;
    }

    for (my $i = 0; $i < $l; $i++) {
        if ($self->{board}->[$x += $o == $self->{ORIENT_HORIZ} ? $xd : 0][$y += $o == $self->{ORIENT_HORIZ} ? 0 : $yd]->{type} != $self->{TYPE_OCEAN}) {
            return 0;
        }
    }

    return 1;
}

# attempt to place a ship on the battlefield
sub place_ship {
    my ($self, $player_id, $player_index, $ship) = @_;

    my ($x, $y, $o, $i, $l);
    my ($yd, $xd) = (0, 0);

    for (my $attempt = 0; $attempt < 1000; $attempt++) {
        $x = $self->number(0, $self->{N_X});
        $y = $self->number(0, $self->{N_Y});

        $o = $self->number(1, 10) < 6;

        if ($self->{ship_length}->[$ship]) {
            # reuse saved length so all players have equal sized ships.
            # perfectly balanced as all things must be.
            $l = $self->{ship_length}->[$ship];
        } else {
            # generate a random length ship
            # TODO: perhaps use a fixed array of guaranteed ship lengths?
            # i think random is more exciting because you never know what
            # kinds of ships are going to be out there.
            $l = $self->number(2, 6);
        }

        if ($self->{debug}) {
            $self->{pbot}->{logger}->log("attempt to place ship for player $player_index: ship $ship x,y: $x,$y o: $o length: $l\n");
        }

        if ($self->check_ship_placement($x, $y, $o, $l)) {
            if (!$o) {
                $self->{vert}++;

                if ($self->{horiz} < $self->{SHIPS} / 2) {
                    # generate a battlefield with half vertical and half horizontal ships
                    # perfectly balanced as all things must be.
                    next;
                }

                $yd = 1;
                $xd = 0;
            } else {
                $self->{horiz}++;

                if ($self->{vert} < $self->{SHIPS} / 2) {
                    # generate a battlefield with half vertical and half horizontal ships
                    # perfectly balanced as all things must be.
                    next;
                }

                $xd = 1;
                $yd = 0;
            }

            for (my $i = 0; $i < $l; $i++) {
                my $tile_data = {
                    type         => $self->{TYPE_SHIP},
                    player_id    => $player_id,
                    player_index => $player_index,
                    orientation  => $o,
                    length       => $l,
                    index        => $i,
                    hit_by       => 0,
                };

                $self->{board}->[$x += $o == $self->{ORIENT_HORIZ} ? $xd : 0][$y += $o == $self->{ORIENT_HORIZ} ? 0 : $yd] = $tile_data;
            }

            $self->{ship_length}->[$ship] = $l;
            $self->{state_data}->{players}->[$player_index]->{health} += $l;
            $self->{state_data}->{players}->[$player_index]->{ships}  += 1;
            return 1;
        }
    }

    return 0;
}

sub place_whirlpool {
    my ($self) = @_;

    for (my $attempt = 0; $attempt < 1000; $attempt++) {
        my $x = $self->number(0, $self->{N_X});
        my $y = $self->number(0, $self->{N_Y});

        # skip non-ocean tiles
        if ($self->{board}->[$x][$y]->{type} != $self->{TYPE_OCEAN}) {
            next;
        }

        # replace ocean tile with whirlpool
        $self->{board}->[$x][$y]->{type} = $self->{TYPE_WHIRLPOOL};
        $self->{board}->[$x][$y]->{tile} = $self->{TILE_OCEAN}; # whirlpools hidden initially, until shot
        return 1;
    }

    $self->{pbot}->{logger}->log("Failed to place whirlpool.\n");
    return 0;
}

sub generate_battlefield {
    my ($self) = @_;

    # fill board with ocean
    for (my $x = 0; $x < $self->{N_X}; $x++) {
        for (my $y = 0; $y < $self->{N_Y}; $y++) {
            $self->{board}->[$x][$y] = {
                type => $self->{TYPE_OCEAN},
                tile => $self->{TILE_OCEAN},
            };
        }
    }

    # place ships
    for (my $player_index = 0; $player_index < @{$self->{state_data}->{players}}; $player_index++) {
        # counts how many horizontal/vertical ships have been placed so far
        $self->{horiz} = 0;
        $self->{vert}  = 0;
        for (my $ship = 0; $ship < $self->{SHIPS}; $ship++) {
            if (!$self->place_ship($self->{state_data}->{players}->[$player_index]->{id}, $player_index, $ship)) {
                return 0;
            }
        }
    }

    # place whirlpools (2 whirlpools per player)
    for (my $whirlpool = 0; $whirlpool < @{$self->{state_data}->{players}} * 2; $whirlpool++) {
        if (!$self->place_whirlpool) {
            return 0;
        }
    }

    return 1;
}

# we hit a ship; check if the ship has sunk
sub check_sunk {
    my ($self, $x, $y) = @_;

    # alias to the tile we hit
    my $tile = $self->{board}->[$x][$y];

    if ($tile->{orientation} == $self->{ORIENT_VERT}) {
        my $top    = $y - $tile->{index};
        my $bottom = $y + ($tile->{length} - ($tile->{index} + 1));

        for (my $i = $bottom; $i >= $top; $i--) {
            if (not $self->{board}->[$x][$i]->{hit_by}) {
                return 0;
            }
        }

        return 1;
    } else {
        my $left   = $x - $tile->{index};
        my $right  = $x + ($tile->{length} - ($tile->{index} + 1));

        for (my $i = $right; $i >= $left; $i--) {
            if (not $self->{board}->[$i][$y]->{hit_by}) {
                return 0;
            }
        }

        return 1;
    }
}

sub get_attack_text {
    my ($self) = @_;

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

    return $attacks[rand @attacks];
}

# checks if we hit whirlpool, ocean, ship, etc
# reveals struck whirlpools
sub check_hit {
    my ($self, $state, $player, $location_data) = @_;

    my ($x, $y, $location) = (
        $location_data->{x},
        $location_data->{y},
        $location_data->{location},
    );

    # check if we hit a whirlpool. if so, reveal whirlpool on the
    # battlefield and deflect the shot
    if ($self->{board}->[$x][$y]->{type} == $self->{TYPE_WHIRLPOOL}) {
        # reveal this whirlpool
        $self->{board}->[$x][$y]->{tile} = $self->{TILE_WHIRLPOOL};

        my $attack = $self->get_attack_text;

        # keep trying until we don't hit another whirlpool
        while (1) {
            $self->send_message($self->{channel}, "$player->{name} $attack $location! $color{cyan}--- SPLASH! ---$color{reset}");

            $x = $self->number(0, $self->{N_X});
            $y = $self->number(0, $self->{N_Y});

            $location = ('A' .. 'Z')[$y] . ($x + 1);

            $self->send_message($self->{channel}, "$player->{name} hit a whirlpool! It deflects their attack to $location!");

            if ($self->{board}->[$x][$y]->{type} == $self->{TYPE_WHIRLPOOL}) {
                # hit another whirlpool
                next;
            }

            # update new location for caller
            $location_data->{x} = $x;
            $location_data->{y} = $y;
            $location_data->{location} = $location;

            last;
        }
    }

    # hit a ship, damage self or enemy alike
    if ($self->{board}->[$x][$y]->{type} == $self->{TYPE_SHIP}) {
        my $player_index = $self->{board}->[$x][$y]->{player_index};

        if ($state->{players}->[$player_index]->{removed}) {
            # removed players no longer exist
            return 0;
        }

        if ($self->{board}->[$x][$y]->{hit_by}) {
            # this piece has already been struck
            return 0;
        } else {
            # a hit! a very palpable hit.
            return 1;
        }
    }

    # no hit
    return 0;
}

sub perform_attack {
    my ($self, $state, $player) = @_;

    $player->{shots}++;

    # random attack verb
    my $attack = $self->get_attack_text;

    # attack location
    my $location = delete $player->{location};

    # convert attack location to board coordinates
    my ($y, $x) = $location =~ /^(.)(.*)/;
    $y = ord($y) - 65;
    $x--;

    # set location data reference so check_hit can update values
    my $location_data = {
        x => $x,
        y => $y,
        location => $location,
    };

    # launch a shot and see if it hit a ship (handles hitting whirlpools, ocean, etc)
    my $hit_ship = $self->check_hit($state, $player, $location_data);

    # location_data can be updated by whirlpools, etc
    $x = $location_data->{x};
    $y = $location_data->{y};
    $location = $location_data->{location};

    if ($hit_ship) {
        # player hit a ship!
        $self->send_message($self->{channel}, "$player->{name} $attack $location! $color{red}--- HIT! --- $color{reset}");

        $player->{hit}++;

        # place hit marker
        $self->{board}->[$x][$y]->{tile}   = $color{red} . $self->{TILE_HIT}->[$player->{index}];
        $self->{board}->[$x][$y]->{hit_by} = $player->{id};

        my $victim = $self->{state_data}->{players}->[$self->{board}->[$x][$y]->{player_index}];

        # deduct hit points from victim
        $victim->{health} -= 1;

        # check if ship has sunk (reveal what kind and whose ship it is)
        if ($self->check_sunk($x, $y)) {
            $player->{sunk}++;
            $victim->{ships}--;

            my $length = $self->{board}->[$x][$y]->{length};

            my %ship_names = (
                5 => 'battleship',
                4 => 'destroyer',
                3 => 'submarine',
                2 => 'patrol boat',
            );

            my $ships_left    = $victim->{ships};
            my $sections_left = $victim->{health};

            my $ships    = 'ship'    . ($ships_left    != 1 ? 's' : '');
            my $sections = 'section' . ($sections_left != 1 ? 's' : '');

            if ($sections_left > 0) {
                $self->send_message($self->{channel}, "$color{red}$player->{name} has sunk $victim->{name}'s $ship_names{$length}! $victim->{name} has $ships_left $ships and $sections_left $sections remaining!$color{reset}");
            } else {
                $self->send_message($self->{channel}, "$color{red}$player->{name} has sunk $victim->{name}'s final $ship_names{$length}! $victim->{name} is out of the game!$color{reset}");
                $victim->{lost} = 1;

                # check if there is only one player still standing
                my $still_alive = 0;
                my $winner;
                foreach my $p (@{$state->{players}}) {
                    next if $p->{removed} or $p->{lost};
                    $still_alive++;
                    $winner = $p;
                }

                if ($still_alive == 1) {
                    $self->send_message($self->{channel}, "$color{yellow}$winner->{name} has won the game of Battleship!$color{reset}");
                    $self->{got_winner} = 1;
                }
            }
        }
    } else {
        # player missed
        $self->send_message($self->{channel}, "$player->{name} $attack $location! --- miss ---");

        $player->{miss}++;

        # place miss marker
        if ($self->{board}->[$x][$y]->{type} == $self->{TYPE_OCEAN}) {
            $self->{board}->[$x][$y]->{tile} = $self->{TILE_MISS};
            $self->{board}->[$x][$y]->{missed_by} = $player->{id};
        }
    }
}

sub list_players {
    my ($self) = @_;

    my @players;

    foreach my $player (@{$self->{state_data}->{players}}) {
        push @players, $player->{name} . ($player->{ready} ? '' : " $color{red}(not ready)$color{reset}");
    }

    if (@players) {
        $self->send_message($self->{channel}, "Current players: " . (join ', ', @players) . ". Use `ready` when you are.");
    }
}

sub show_scoreboard {
    my ($self) = @_;

    foreach my $player (sort { $b->{health} <=> $a->{health} } @{$self->{state_data}->{players}}) {
        next if $player->{removed};

        my $buf = sprintf("%-10s shots: %2d, hit: %2d, miss: %2d, acc: %3d%%, sunk: %2d, ships left: %d, sections left: %2d",
            "$player->{name}:",
            $player->{shots},
            $player->{hit},
            $player->{miss},
            int (($player->{hit} / ($player->{shots} ? $player->{shots} : 1)) * 100),
            $player->{sunk},
            $player->{ships},
            $player->{health},
        );

        $self->send_message($self->{channel}, $buf);
    }
}

sub show_battlefield {
    my ($self, $player_index, $nick) = @_;

    $self->{pbot}->{logger}->log("Showing battlefield for player $player_index\n");

    my $player;

    if ($player_index >= 0) {
        $player = $self->{state_data}->{players}->[$player_index];
    }

    my $output;

    # player hit markers, for legend
    my $hits;
    foreach my $p (@{$self->{state_data}->{players}}) {
        $hits .= "$p->{name} hit: $color{red}" . ($p->{index} + 1) . "$color{reset} ";
    }

    # render legend
    if ($player) {
        $output .= "Legend: Your ships: $self->{TILE_SHIP_VERT} $self->{TILE_SHIP_HORIZ}$color{reset} ${hits}ocean: $self->{TILE_OCEAN}$color{reset} miss: $self->{TILE_MISS}$color{reset} whirlpool: $self->{TILE_WHIRLPOOL}$color{reset}\n";
    }
    elsif ($player_index == $self->{BOARD_FULL} or $player_index == $self->{BOARD_FINAL}) {
        my $ships;
        foreach my $p (@{$self->{state_data}->{players}}) {
            $ships .= "$p->{name}: $self->{TILE_SHIP}->[$p->{index}] ";
        }

        $output .= "Legend: ${ships}${hits}ocean: $self->{TILE_OCEAN}$color{reset} miss: $self->{TILE_MISS}$color{reset} whirlpool: $self->{TILE_WHIRLPOOL}$color{reset}\n";
    }
    else {
        # spectator
        $output .= "Legend: ${hits}ocean: $self->{TILE_OCEAN}$color{reset} miss: $self->{TILE_MISS}$color{reset} whirlpool: $self->{TILE_WHIRLPOOL}$color{reset}\n";
    }

    # render top column coordinates
    $output .= "$color{cyan},01  ";

    for (my $x = 1; $x < $self->{N_X} + 1; $x++) {
        if ($x % 10 == 0) {
            $output .= "$color{yellow},01" if $self->{N_X} > 10;
            $output .= $x % 10;
            $output .= ' ';
            $output .= "$color{cyan},01" if $self->{N_X} > 10;
        } else {
            $output .= $x % 10;
            $output .= ' ';
        }
    }

    $output .= "\n";

    # render battlefield row by row
    for (my $y = 0; $y < $self->{N_Y}; $y++) {
        # left row coordinates
        $output .= sprintf("$color{cyan},01%c ", 97 + $y);

        # render a row of the board column by column
        for (my $x = 0; $x < $self->{N_X}; $x++) {
            my $tile = $self->{board}->[$x][$y];

            # render ocean/whirlpool, miss, but not hits or ships yet
            if ($tile->{type} != $self->{TYPE_SHIP}) {
                # reveal whirlpools on full/final boards
                if ($player_index == $self->{BOARD_FULL} || $player_index == $self->{BOARD_FINAL}) {
                    if ($tile->{type} == $self->{TYPE_WHIRLPOOL}) {
                        $output .= $self->{TILE_WHIRLPOOL} . ' ';
                    } else {
                        # render normal tile (ocean, miss)
                        $output .= $tile->{tile} . ' ';
                    }
                } else {
                    # render normal tile (ocean, revealed/hidden whirlpools, miss)
                    $output .= $tile->{tile} . ' ';
                }
                next;
            }

            # render hits
            if ($tile->{hit_by}) {
                $output .= $tile->{tile} . ' ';
                next;
            }

            # render ships

            # render player's view
            if ($player) {
                # not player's ship
                if ($tile->{player_id} != $player->{id}) {
                    # ship not found yet, show ocean
                    $output .= $self->{TILE_OCEAN} . ' ';
                    next;
                }

                if ($tile->{orientation} == $self->{ORIENT_VERT}) {
                    # vertical ship
                    $output .= $self->{TILE_SHIP_VERT};
                } else {
                    # horizontal ship
                    $output .= $self->{TILE_SHIP_HORIZ};
                }

                $output .= ' ';
                next;
            }

            # otherwise render spectator, full or final board

            # spectators are not allowed to see ships unless hit
            if ($player_index == $self->{BOARD_SPECTATOR}) {
                # ship not found yet, show ocean
                $output .= $self->{TILE_OCEAN} . ' ';
                next;
            }

            # full or final board, show all ships
            $output .= $color{white} . $self->{TILE_SHIP}->[$tile->{player_index}] . ' ';
        }

        # right row coordinates
        $output .= sprintf("$color{cyan},01%c", 97 + $y);
        $output .= "$color{reset}\n";
    }

    # bottom column coordinates
    $output .= "$color{cyan},01  ";

    for (my $x = 1; $x < $self->{N_X} + 1; $x++) {
        if ($x % 10 == 0) {
            $output .= $color{yellow}, 01 if $self->{N_X} > 10;
            $output .= $x % 10;
            $output .= ' ';
            $output .= $color{cyan}, 01 if $self->{N_X} > 10;
        } else {
            $output .= $x % 10;
            $output .= ' ';
        }
    }

    $output .= "\n";

    # send output, one message per line
    foreach my $line (split /\n/, $output) {
        if ($player) {
            # player
            $self->send_message($player->{name}, $line);
        }
        elsif ($player_index == $self->{BOARD_FULL}) {
            # full
            $self->send_message($nick, $line);
        }
        else {
            # spectator, final
            $self->send_message($self->{channel}, $line);
        }
    }
}

# game state machine stuff

# do one loop of the game engine
sub run_one_state {
    my ($self) = @_;

    # don't run a game loop if we're paused
    if ($self->{state_data}->{paused}) {
        return;
    }

    # check for naughty or missing players
    my $players = 0;

    foreach my $player (@{$self->{state_data}->{players}}) {
        next if $player->{removed} or $player->{lost};

        # remove player if they have missed 3 inputs
        if ($player->{missedinputs} >= $self->{MAX_MISSED_MOVES}) {
            $self->send_message(
                $self->{channel},
                "$color{red}$player->{name} has missed too many moves and has been ejected from the game!$color{reset}"
            );

            $player->{removed} = 1;
            next;
        }

        # count players still in the game
        $players++;
    }

    # ensure there are at least 2 players still playing
    if ($self->{current_state} eq 'move' or $self->{current_state} eq 'attack') {
        if ($players < 2 and not $self->{got_winner}) {
            $self->send_message($self->{channel}, "Not enough players left in the game. Aborting...");
            $self->set_state('gameover');
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
        players          => [], # array of player data
        ticks            => 0,  # number of ticks elapsed
        paused           => 0,  # is the game paused?
    };

    $self->{states} = {
        nogame => {
            sub => sub { $self->state_nogame(@_) },
            trans => {
                challenge => 'challenge',
                nogame    => 'nogame',
            }
        },
        challenge => {
            sub => sub { $self->state_challenge(@_) },
            trans => {
                stop   => 'nogame',
                wait   => 'challenge',
                ready  => 'genboard',
            }
        },
        genboard => {
            sub => sub { $self->state_genboard(@_) },
            trans => {
                fail => 'nogame',
                next => 'showboard',
            }
        },
        showboard => {
            sub => sub { $self->state_showboard(@_) },
            trans => {
                next => 'move',
            }
        },
        move => {
            sub => sub { $self->state_move(@_) },
            trans => {
                wait => 'move',
                next => 'attack',
            }
        },
        attack => {
            sub => sub { $self->state_attack(@_) },
            trans => {
                gotwinner => 'gameover',
                next      => 'move',
            }
        },
        gameover => {
            sub => sub { $self->state_gameover(@_) },
            trans => {
                next => 'nogame',
            }
        },
    };
}

# game states

sub state_nogame {
    my ($self, $state) = @_;
    $self->end_game_loop;
    $state->{trans} = 'nogame';
}

sub state_challenge {
    my ($self, $state) = @_;

    # max number of times to perform tock action
    $state->{tock_limit} = 5;

    # tock every 60 ticks
    my $tock = 60;

    # every tick we check if all players have readied yet
    my $ready = 0;

    foreach my $player (@{$state->{players}}) {
        $ready++ if $player->{ready};
    }

    # is it time for a tock?
    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;  # we've tocked

        # reached maximum number of tocks
        if (++$state->{tocks} > $state->{tock_limit}) {
            $self->send_message($self->{channel}, "Not all players have readied in time. The game has been aborted.");
            $state->{trans}   = 'stop';
            $state->{players} = [];
            return;
        }

        my $max   = $self->{MAX_PLAYERS};
        my $avail = $max - @{$self->{state_data}->{players}};
        my $slots = 'slot' . ($avail == 1 ? '' : 's');

        $self->send_message($self->{channel}, "There is a game of Battleship available! Use `accept` to enter the fray ($avail/$max $slots open).");

        $self->list_players;

        if ($ready == 1 && @{$self->{state_data}->{players}} == 1) {
            $self->send_message($self->{channel}, "Cannot begin game with one player.");
        }
    }

    if ($ready >= 2 && $ready == @{$state->{players}}) {
        # all players ready (min 2 players to start)
        $self->send_message($self->{channel}, "All players ready!");
        $state->{trans} = 'ready';
    } else {
        # wait another tick
        $state->{trans} = 'wait';
    }
}

sub state_genboard {
    my ($self, $state) = @_;

    if (!$self->init_game($state)) {
        $self->{pbot}->{logger}->log("Failed to generate battlefield\n");
        $self->send_message($self->{channel}, "Failed to generate a suitable battlefield. Please try again.");
        $state->{trans} = 'fail';
    } else {
        $state->{tock_limit} = 3;
        $state->{trans} = 'next';
    }
}

sub state_showboard {
    my ($self, $state) = @_;

    # pause the game to send the boards to all the players.
    # this is due to output pacing; the messages are trickled out slowly
    # to avoid overflowing the ircd's receive queue. we do not want the
    # game state to advance while the messages are being sent out. the
    # game will resume when the `pbot.output_queue_empty` notification
    # is received.
    $state->{paused} = $self->{PAUSED_FOR_OUTPUT_QUEUE};

    for (my $player = 0; $player < @{$state->{players}}; $player++) {
        $self->send_message($self->{channel}, "Showing battlefield to $state->{players}->[$player]->{name}...");
        $self->show_battlefield($player);
    }

    $self->send_message($self->{channel}, "Fight! Anybody (players and spectators) can use `board` at any time to see the battlefield.");
    $state->{trans} = 'next';
}

sub state_move {
    my ($self, $state) = @_;

    # allow 5 tocks before players have missed their move
    $state->{tock_limit} = 5;

    # tock every 15 ticks
    my $tock = 15;

    # tock sooner if this is the first
    if ($state->{first_tock}) {
        $tock = 2;
    }

    # every tick, check if all players have moved
    my $moved   = 0;
    my $players = 0;

    foreach my $player (@{$state->{players}}) {
        next if $player->{removed} or $player->{lost};
        $moved++ if $player->{location};
        $players++;
    }

    if ($moved == $players) {
        # all players have moved
        $state->{trans} = 'next';
        return;
    }

    # tock!
    if ($state->{ticks} % $tock == 0) {
        $state->{tocked} = 1;

        if (++$state->{tocks} > $state->{tock_limit}) {
            # tock limit reached, flag all players who haven't moved
            my @missed;

            foreach my $player (@{$state->{players}}) {
                next if $player->{removed} or $player->{lost};

                if (not $player->{location}) {
                    $player->{missedinputs}++;
                    push @missed, $player->{name};
                }
            }

            my $msg = join ', ', @missed;

            $msg .= " failed to launch an attack in time. They forfeit their turn!";

            $self->send_message($self->{channel}, $msg);

            $state->{trans} = 'next';
            return;
        }

        # notify all players who haven't moved yet
        my @pending;

        foreach my $player (@{$state->{players}}) {
            next if $player->{removed} or $player->{lost};

            if (not $player->{location}) {
                push @pending, $player->{name};
            }
        }

        my $players = join ', ', @pending;

        my $warning = $state->{tocks} == $state->{tock_limit} ? $color{red} : '';

        my $remaining  = 15 * $state->{tock_limit};
        $remaining    -= 15 * ($state->{tocks} - 1);
        $remaining     = "(" . (concise duration $remaining) . " remaining)";

        $self->send_message($self->{channel}, "$players: $warning$remaining Launch an attack now via `bomb <location>`!$color{reset}");
    }

    $state->{trans} = 'wait';
}

sub state_attack {
    my ($self, $state) = @_;

    my $trans = 'next';

    foreach my $player (@{$state->{players}}) {
        # skip removed players
        next if $player->{removed};

        # skip players who haven't moved
        next if not $player->{location};

        # launch attack
        $self->perform_attack($state, $player);

        # transition to gameover if someone won
        $trans = 'gotwinner' if $self->{got_winner};
    }

    $state->{trans} = $trans;
}

sub state_gameover {
    my ($self, $state) = @_;

    if (@{$state->{players}} >= 2) {
        $self->show_battlefield($self->{BOARD_FINAL});
        $self->show_scoreboard;
        $self->send_message($self->{channel}, "Game over!");
    }

    $state->{players} = [];
    $state->{trans}   = 'next';
}

1;
