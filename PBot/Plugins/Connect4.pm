# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Plugins::Connect4;

use warnings;
use strict;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use Carp ();
use Time::Duration qw/concise duration/;
use Data::Dumper;
$Data::Dumper::Useqq = 1;
$Data::Dumper::Sortkeys = 1;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = delete $conf{pbot};

  $self->{pbot}->{commands}->register(sub { $self->connect4_cmd(@_) }, 'connect4', 0);

  $self->{pbot}->{timer}->register(sub { $self->connect4_timer }, 1, 'connect4 timer');

  $self->{pbot}->{event_dispatcher}->register_handler('irc.part',    sub { $self->on_departure(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',    sub { $self->on_departure(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',    sub { $self->on_kick(@_) });

  $self->{channel} = '##connect4';
  $self->create_states;
}

sub unload {
  my $self = shift;
  $self->{pbot}->{commands}->unregister('connect4');
  $self->{pbot}->{timer}->unregister('connect4 timer');
}

sub on_kick {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);
  my ($victim, $reason) = ($event->{event}->to, $event->{event}->{args}[1]);
  my $channel = $event->{event}->{args}[0];
  return 0 if lc $channel ne $self->{channel};
  $self->player_left($nick, $user, $host);
  return 0;
}

sub on_departure {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);
  my $type = uc $event->{event}->type;
  return 0 if $type ne 'QUIT' and lc $channel ne $self->{channel};
  $self->player_left($nick, $user, $host);
  return 0;
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

  bold       => "\x02",
  italics    => "\x1D",
  underline  => "\x1F",
  reverse    => "\x16",

  reset      => "\x0F",
);

sub connect4_cmd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  $arguments =~ s/^\s+|\s+$//g;

  my $usage = "Usage: connect4 challenge|accept|play|board|quit|players|kick|abort; for more information about a command: connect4 help <command>";
 
  my $options;
  my $command;
  ($command, $arguments, $options) = split / /, $arguments, 3;
  $command = lc $command;

  my ($channel, $result);

  given ($command) {
    when ('help') {
      given ($arguments) {
        when ('help') {
          return "Seriously?";
        }

        default {
          if (length $arguments) {
            return "connect4 has no such command '$arguments'. I can't help you with that.";
          } else {
            return "Usage: connect4 help <command>";
          }
        }
      }
    }

    when ('challenge') {
      if ($self->{current_state} ne 'nogame') {
        return "There is already a game of connect4 underway.";
      }

      if (not length $arguments || $arguments =~ m/^[4-9]$/) {
        $self->{current_state} = 'accept';
        $self->{state_data} = { players => [], counter => 0 };
	$self->{CONNECTIONS} = not length $arguments ? 4 : $arguments;

        my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
        my $player = { id => $id, name => $nick, missedinputs => 0 };
        push @{$self->{state_data}->{players}}, $player;

        $player = { id => -1, name => undef, missedinputs => 0 };
        push @{$self->{state_data}->{players}}, $player;
        return "/msg $self->{channel} $nick has made an open challenge (connect-$self->{CONNECTIONS})! Use `accept` to accept their challenge.";
      }

      my $challengee = $self->{pbot}->{nicklist}->is_present($self->{channel}, $arguments);

      if (not $challengee) {
        return "That nick is not present in this channel. Invite them to $self->{channel} and try again!";
      }

      $self->{current_state} = 'accept';
      $self->{state_data} = { players => [], counter => 0 };
      $self->{CONNECTIONS} = not length $options ? 4 : $options;

      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      my $player = { id => $id, name => $nick, missedinputs => 0 };
      push @{$self->{state_data}->{players}}, $player;

      ($id) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($challengee);
      $player = { id => $id, name => $challengee, missedinputs => 0 };
      push @{$self->{state_data}->{players}}, $player;

      return "/msg $self->{channel} $nick has challenged $challengee to Connect4! Use `accept` to accept their challenge.";
    }

    when ('accept') {
      if ($self->{current_state} ne 'accept') {
        return "/msg $nick This is not the time to use `accept`.";
      }

      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      my $player = $self->{state_data}->{players}->[1];

      # open challenge
      if ($player->{id} == -1) {
        $player->{id} = $id;
        $player->{name} = $nick;
      }

      if ($player->{id} == $id) {
        $player->{accepted} = 1;
        return "/msg $self->{channel} $nick has accepted $self->{state_data}->{players}->[0]->{name}'s challenge!";
      } else {
        return "/msg $nick You have not been challenged to a game of Connect4 yet.";
      }
    }

    when ($_ eq 'decline' or $_ eq 'quit' or $_ eq 'forfeit' or $_ eq 'concede') {
      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      my $removed = 0;

      for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
        if ($self->{state_data}->{players}->[$i]->{id} == $id) {
          splice @{$self->{state_data}->{players}}, $i--, 1;
          $removed = 1;
        }
      }

      if ($removed) {
        if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
          $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1
        }
        return "/msg $self->{channel} $nick has left the game!";
      } else {
        return "$nick: But you are not even playing the game.";
      }
    }

    when ('abort') {
      if (not $self->{pbot}->{admins}->loggedin($self->{channel}, "$nick!$user\@$host")) {
        return "$nick: Sorry, only admins may abort the game.";
      }

      $self->{current_state} = 'gameover';
      return "/msg $self->{channel} $nick: The game has been aborted.";
    }

    when ('stats') { # XXX
      if (@{$self->{state_data}->{players}} == 2) {
        return "soon.";
      } else {
        return "There is no game going on right now.";
      }
    }

    when ('players') {
      if ($self->{current_state} eq 'accept') {
        return "$self->{state_data}->{players}->[0]->{name} has challenged $self->{state_data}->{players}->[1]->{name}!";
      } elsif (@{$self->{state_data}->{players}} == 2) {
        return "$self->{state_data}->{players}->[0]->{name} is playing with $self->{state_data}->{players}->[1]->{name}!";
      } else {
        return "There are no players playing right now. Start a game with `connect4 challenge <nick>`!";
      }
    }

    when ('kick') {
      if (not $self->{pbot}->{admins}->loggedin($self->{channel}, "$nick!$user\@$host")) {
        return "$nick: Sorry, only admins may kick people from the game.";
      }

      if (not length $arguments) {
        return "Usage: connect4 kick <nick>";
      }

      my $removed = 0;

      for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
        if (lc $self->{state_data}->{players}->[$i]->{name} eq $arguments) {
          splice @{$self->{state_data}->{players}}, $i--, 1;
          $removed = 1;
        }
      }

      if ($removed) {
        if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
          $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1
        }
        return "/msg $self->{channel} $nick: $arguments has been kicked from the game.";
      } else {
        return "$nick: $arguments isn't even in the game.";
      }
    }

    when ('play') {
      $self->{pbot}->{logger}->log("Connect4: play state: $self->{current_state}\n" . Dumper $self->{state_data});

      if ($self->{current_state} ne 'playermove') {
        return "$nick: It's not time to do that now.";
      }

      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      my $player;

      if ($self->{state_data}->{players}->[0]->{id} == $id) {
        $player = 0;
      } elsif ($self->{state_data}->{players}->[1]->{id} == $id) {
        $player = 1;
      } else {
        return "You are not playing in this game.";
      }

      if ($self->{state_data}->{current_player} != $player) {
        return "$nick: It is not your turn to attack!";
      }

      if ($self->{player}->[$player]->{done}) {
        return "$nick: You have already played this turn.";
      }

      if ($arguments !~ m/^[1-7]$/) {
        return "$nick: Usage: connect4 play <location>; <location> must be in the 1..7 range etc.";
      }

      if ($self->play($player, uc $arguments)) {
        if ($self->{player}->[$player]->{won}) {
          $self->{previous_state} = $self->{current_state};
          $self->{current_state} = 'checkplayer';
          $self->run_one_state;
        } else {
          $self->{player}->[$player]->{done} = 1;
          $self->{player}->[!$player]->{done} = 0;
          $self->{state_data}->{current_player} = !$player;
          $self->{state_data}->{ticks} = 1;
          $self->{state_data}->{first_tock} = 1;
          $self->{state_data}->{counter} = 0;
        }
      }
    }

    when ($_ eq 'specboard' or $_ eq 'board') {
      if ($self->{current_state} eq 'nogame' or $self->{current_state} eq 'accept'
          or $self->{current_state} eq 'genboard' or $self->{current_state} eq 'gameover') {
        return "$nick: There is no board to show right now.";
      }

      if ($_ eq 'specboard') {
        $self->show_board;
        return;
      }

      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      for (my $i = 0; $i < 2; $i++) {
        if ($self->{state_data}->{players}->[$i]->{id} == $id) {
          $self->send_message($self->{channel}, "$nick surveys the board!");
          $self->show_board;
          return;
        }
      }
      $self->show_board;
    }

    default {
      return $usage;
    }
  }

  return $result;
}

sub connect4_timer {
  my $self = shift;
  $self->run_one_state;
}

sub player_left {
  my ($self, $nick, $user, $host) = @_;

  my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  my $removed = 0;

  for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
    if ($self->{state_data}->{players}->[$i]->{id} == $id) {
      splice @{$self->{state_data}->{players}}, $i--, 1;
      $self->send_message($self->{channel}, "$nick has left the game!");
      $removed = 1;
    }
  }

  if ($removed) {
    if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
      $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1
    }
    return "/msg $self->{channel} $nick has left the game!";
  }
}

sub send_message {
  my ($self, $to, $text, $delay) = @_;
  $delay = 0 if not defined $delay;
  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
  my $message = {
    nick => $botnick, user => 'connect4', host => 'localhost', command => 'connect4 text', checkflood => 1,
    message => $text
  };
  $self->{pbot}->{interpreter}->add_message_to_output_queue($to, $message, $delay);
}

sub run_one_state {
  my $self = shift;

  # check for naughty or missing players
  if ($self->{current_state} =~ /(?:move|accept)/) {
    my $removed = 0;
    for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
      if ($self->{state_data}->{players}->[$i]->{missedinputs} >= 3) {
        $self->send_message($self->{channel}, "$color{red}$self->{state_data}->{players}->[$i]->{name} has missed too many prompts and has been ejected from the game!$color{reset}");
        splice @{$self->{state_data}->{players}}, $i--, 1;
        $removed = 1;
      }
    }

    if ($removed) {
      if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
        $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1
      }
    }

    if (not @{$self->{state_data}->{players}} == 2) {
      $self->send_message($self->{channel}, "A player has left the game! The game is now over.");
      $self->{current_state} = 'nogame';
    }
  }

  my $state_data = $self->{state_data};

  # this shouldn't happen
  if (not defined $self->{current_state}) {
    $self->{pbot}->{logger}->log("Connect4 state broke.\n");
    $self->{current_state} = 'nogame';
    return;
  }

  # transistioned to a brand new state; prepare first tock
  if ($self->{previous_state} ne $self->{current_state}) {
    $state_data->{newstate} = 1;
    $state_data->{ticks} = 1;

    if (exists $state_data->{tick_drift}) {
      $state_data->{ticks} += $state_data->{tick_drift};
      delete $state_data->{tick_drift};
    }

    $state_data->{first_tock} = 1;
    $state_data->{counter} = 0;
  } else {
    $state_data->{newstate} = 0;
  }

  # dump new state data for logging/debugging
  if ($state_data->{newstate}) {
    $self->{pbot}->{logger}->log("Connect4: New state: $self->{current_state}\n" . Dumper $state_data);
  }

  # run one state/tick
  $state_data = $self->{states}{$self->{current_state}}{sub}($state_data);

  if ($state_data->{tocked}) {
    delete $state_data->{tocked};
    delete $state_data->{first_tock};
    $state_data->{ticks} = 0;
  }

  # transform to next state
  $state_data->{previous_result} = $state_data->{result};
  $self->{previous_state} = $self->{current_state};
  $self->{current_state} = $self->{states}{$self->{current_state}}{trans}{$state_data->{result}};
  $self->{state_data} = $state_data;

  # next tick
  $self->{state_data}->{ticks}++;
}

sub create_states {
  my $self = shift;

  $self->{pbot}->{logger}->log("Connect4: Creating game state machine\n");

  $self->{previous_state} = '';
  $self->{current_state} = 'nogame';
  $self->{state_data} = { players => [], ticks => 0, newstate => 1 };

  $self->{state_data}->{current_player} = 0;

  $self->{states}{'nogame'}{sub} = sub { $self->nogame(@_) };
  $self->{states}{'nogame'}{trans}{challenge} = 'accept';
  $self->{states}{'nogame'}{trans}{nogame} = 'nogame';

  $self->{states}{'accept'}{sub} = sub { $self->accept(@_) };
  $self->{states}{'accept'}{trans}{stop} = 'nogame';
  $self->{states}{'accept'}{trans}{wait} = 'accept';
  $self->{states}{'accept'}{trans}{accept} = 'genboard';

  $self->{states}{'genboard'}{sub} = sub { $self->genboard(@_) };
  $self->{states}{'genboard'}{trans}{next} = 'showboard';

  $self->{states}{'showboard'}{sub} = sub { $self->showboard(@_) };
  $self->{states}{'showboard'}{trans}{next} = 'playermove';

  $self->{states}{'playermove'}{sub} = sub { $self->playermove(@_) };
  $self->{states}{'playermove'}{trans}{wait} = 'playermove';
  $self->{states}{'playermove'}{trans}{next} = 'checkplayer';

  $self->{states}{'checkplayer'}{sub} = sub { $self->checkplayer(@_) };
  $self->{states}{'checkplayer'}{trans}{sunk} = 'gameover';
  $self->{states}{'checkplayer'}{trans}{next} = 'playermove';

  $self->{states}{'gameover'}{sub} = sub { $self->gameover(@_) };
  $self->{states}{'gameover'}{trans}{wait} = 'gameover';
  $self->{states}{'gameover'}{trans}{next} = 'nogame';
}

# connect4 stuff

sub init_game {
  my ($self, $nick1, $nick2) = @_;

  $self->{N_X} = 7;
  $self->{N_Y} = 6;
  $self->{chips} = 0;
  $self->{draw} = 0;

  $self->{adjacent} = [];

  $self->{board} = [];

  $self->{player} = [
    { bombs => 0, hit => 0, miss => 0, sunk => 0, nick => $nick1, done => 0 },
    { bombs => 0, hit => 0, miss => 0, sunk => 0, nick => $nick2, done => 0 }
  ];

  $self->{turn} = 0;
  $self->{horiz} = 0;

  $self->generate_board;
}

sub generate_board {
  my ($self) = @_;
  my ($x, $y);

  for ($y = 0; $y < $self->{N_Y}; $y++) {
    for ($x = 0; $x < $self->{N_X}; $x++) {
      $self->{board}->[$x][$y] = ' ';

      # down, down left, down right, left, right
      $self->{adjacent}->[$x][$y] = { 
	      d => 0, dl => 0, dr => 0, 
	      ul => 0, ur => 0, 
	      l => 0, r => 0
      };
    }
  }
}

sub connect_cell {
  my ($self, $x, $y) = @_;
  my ($n, $i, $j);

  $n = 0;
  $self->{adjacent}->[$x][$y] = {
    d => 1, dl => 1, dr => 1, 
    ul => 1, ur => 1, l => 1, lr => 1,
  };

  # l
  $i = $x - 1; $j = $y;
  if ($i < $self->{N_X} && $i >= 0) {
	$n = $self->{adjacent}->[$x][$y]->{l} = 
		$self->{adjacent}->[$i][$j]->{l} + 1;
  }

  if ($n == $self->{CONNECTIONS}) {
	  return 1;
  }

  # r
  $i = $x + 1; $j = $y;
  if ($i < $self->{N_X} && $i >= 0) {
	$n = $self->{adjacent}->[$x][$y]->{r} = 
		$self->{adjacent}->[$i][$j]->{r} + 1;
  }

  if ($n == $self->{CONNECTIONS}) {
	  return 1;
  }

  # d
  $i = $x; $j = $y - 1;
  if ($j < $self->{N_Y} && $j >= 0) {
	$n = $self->{adjacent}->[$x][$y]->{d} =
		$self->{adjacent}->[$i][$j]->{d} + 1;
  }

  if ($n == $self->{CONNECTIONS}) {
	  return 1;
  }

  # dl
  $i = $x - 1; $j = $y - 1;
  if ($i < $self->{N_X} && $i >= 0 && $j < $self->{N_Y} && $j >= 0) {
	$n = $self->{adjacent}->[$x][$y]->{dl} =
		$self->{adjacent}->[$i][$j]->{dl} + 1;
  }

  if ($n == $self->{CONNECTIONS}) {
	  return 1;
  }
  
  # ul
  $i = $x - 1; $j = $y + 1;
  if ($i < $self->{N_X} && $i >= 0 && $j < $self->{N_Y} && $j >= 0) {
	$n = $self->{adjacent}->[$x][$y]->{ul} =
		$self->{adjacent}->[$i][$j]->{ul} + 1;
  }

  if ($n == $self->{CONNECTIONS}) {
	  return 1;
  }
 
  # ur
  $i = $x + 1; $j = $y + 1;
  if ($i < $self->{N_X} && $i >= 0 && $j < $self->{N_Y} && $j >= 0) {
	$n = $self->{adjacent}->[$x][$y]->{ur} =
		$self->{adjacent}->[$i][$j]->{ur} + 1;
  }
  if ($n == $self->{CONNECTIONS}) {
	  return 1;
  }

  # dr
  $i = $x + 1; $j = $y - 1;
  if ($i < $self->{N_X} && $i >= 0 && $j < $self->{N_Y} && $j >= 0) {
	$n = $self->{adjacent}->[$x][$y]->{dr} =
		$self->{adjacent}->[$i][$j]->{dr} + 1;
  }
  return $n == $self->{CONNECTIONS};
}

sub column_top {
  my ($self, $x) = @_;
  my $y;

  for ($y = 0; $y < $self->{N_Y}; $y++) {
	  if ($self->{board}->[$x][$y] == ' ') {
		return $y;
	  }
  }
  return -1; # shouldnt happen
}

sub play {
  my ($self, $player, $location) = @_;
  my ($draw, $c4, $x, $y);

  $x = $location - 1;

  $self->{pbot}->{logger}->log("play player $player: $x\n");

  if ($x < 0 || $x >= $self->{N_X} || $self->{board}[$x][0] != ' ') {
    $self->send_message($self->{channel}, "Target illegal/out of range, try again.");
    return 0;
  }

  $y = $self->column_top($x);
 
  $self->{board}->[$x][$y] = $player ? 'O' : 'X';
  $self->{chips}++;

  $c4 = $self->connect_cell($x, $y);
  $draw = $self->{chips} == $self->{N_X} * $self->{N_Y};
 
  my $nick1 = $self->{player}->[$player]->{nick};
  my $nick2 = $self->{player}->[$player ? 0 : 1]->{nick};

  $self->send_message($self->{channel}, "$nick1 placed piece at column: $location");

  if ($c4) {
    $self->send_message($self->{channel}, "$nick1 connected $self->{CONNECTIONS} pieces! $color{red}--- VICTORY! --- $color{reset}");
    $self->{player}->[$player]->{won} = 1;
  } elsif ($draw) {
    $self->send_message($self->{channel}, "$color{red}--- DRAW! --- $color{reset}");
    $self->{draw} = 1;
  }

  return 1;
}

sub show_board {
  my ($self) = @_;
  my ($x, $y, $buf, $chip, $c);

  $self->{pbot}->{logger}->log("showing board\n");

  $buf = "$color{cyan}";

  for($x = 1; $x < $self->{N_X} + 1; $x++) {
    if ($x % 10 == 0) {
      $buf .= $color{yellow};
      $buf .= ' ';
      $buf .= $x % 10;
      $buf .= ' ';
      $buf .= $color{cyan};
    } else {
      $buf .= " " . $x % 10 . " ";
    }
  }

  $buf .= "\n";

  for ($y = 0; $y < $self->{N_Y}; $y++) {
    for ($x = 0; $x < $self->{N_X}; $x++) {
	    $chip = $self->{board}->[$x][$y];
	    $c = $chip == 'O' ? $color{red} : $color{cyan};
	    $buf .= "[$c$chip$color{reset}]";
    }
    $buf .= "\n";
  }

  foreach my $line (split /\n/, $buf) {
      $self->send_message($self->{channel}, $line);
  }
}

# state subroutines

sub nogame {
  my ($self, $state) = @_;
  $state->{result} = 'nogame';
  return $state;
}

sub accept {
  my ($self, $state) = @_;

  $state->{max_count} = 3;

  if ($state->{players}->[1]->{accepted}) {
    $state->{result} = 'accept';
    return $state;
  }

  my $tock = 15;

  if ($state->{ticks} % $tock == 0) {
    $state->{tocked} = 1;

    if (++$state->{counter} > $state->{max_count}) {
      if ($state->{players}->[1]->{id} == -1) {
        $self->send_message($self->{channel}, "Nobody has accepted $state->{players}->[0]->{name}'s challenge.");
      } else {
        $self->send_message($self->{channel}, "$state->{players}->[1]->{name} has failed to accept $state->{players}->[0]->{name}'s challenge.");
      }
      $state->{result} = 'stop';
      $state->{players} = [];
      return $state;
    }

    if ($state->{players}->[1]->{id} == -1) {
      $self->send_message($self->{channel}, "$state->{players}->[0]->{name} has made an open challenge! Use `accept` to accept their challenge.");
    } else {
      $self->send_message($self->{channel}, "$state->{players}->[1]->{name}: $state->{players}->[0]->{name} has challenged you! Use `accept` to accept their challenge.");
    }
  }

  $state->{result} = 'wait';
  return $state;
}

sub genboard {
  my ($self, $state) = @_;
  $self->init_game($state->{players}->[0]->{name}, $state->{players}->[1]->{name});
  $state->{max_count} = 3;
  $state->{result} = 'next';
  return $state;
}

sub showboard {
  my ($self, $state) = @_;
  $self->send_message($self->{channel}, "Showing board ...");
  $self->show_board;
  $self->send_message($self->{channel}, "Fight! Anybody (players and spectators) can use `board` at any time to see latest version of the board!");
  $state->{result} = 'next';
  return $state;
}

sub playermove {
  my ($self, $state) = @_;

  my $tock;
  if ($state->{first_tock}) {
    $tock = 3;
  } else {
    $tock = 15;
  }

  if ($self->{player}->[$state->{current_player}]->{done}) {
    $self->{pbot}->{logger}->log("playermove: player $state->{current_player} done, nexting\n");
    $state->{result} = 'next';
    return $state;
  }

  if ($state->{ticks} % $tock == 0) {
    $state->{tocked} = 1;
    if (++$state->{counter} > $state->{max_count}) {
      $state->{players}->[$state->{current_player}]->{missedinputs}++;
      $self->send_message($self->{channel}, "$state->{players}->[$state->{current_player}]->{name} failed to play in time. They forfeit their turn!");
      $self->{player}->[$state->{current_player}]->{done} = 1;
      $self->{player}->[!$state->{current_player}]->{done} = 0;
      $state->{current_player} = !$state->{current_player};
      $state->{result} = 'next';
      return $state;
    }

    my $red = $state->{counter} == $state->{max_count} ? $color{red} : '';

    my $remaining = 15 * $state->{max_count};
    $remaining -= 15 * ($state->{counter} - 1);
    $remaining = "(" . (concise duration $remaining) . " remaining)";

    $self->send_message($self->{channel}, "$state->{players}->[$state->{current_player}]->{name}: $red$remaining Play now via `play <location>`!$color{reset}");
  }

  $state->{result} = 'wait';
  return $state;
}

sub checkplayer {
  my ($self, $state) = @_;

  if ($self->{player}->[$state->{current_player}]->{won} || $self->{draw}) {
    $state->{result} = 'sunk'; # XXX won
  } else {
    $state->{result} = 'next';
  }
  return $state;
}

sub gameover {
  my ($self, $state) = @_;
  my $buf;
  if ($state->{ticks} % 2 == 0) {
    $self->show_board;
    $self->send_message($self->{channel}, $buf);
    $self->send_message($self->{channel}, "Game over!");
    $state->{players} = [];
    $state->{counter} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

1;
