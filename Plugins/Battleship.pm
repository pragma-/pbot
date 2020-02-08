# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Battleship;

use warnings;
use strict;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use feature 'unicode_strings';
use utf8;

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
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{pbot}->{commands}->register(sub { $self->battleship_cmd(@_) }, 'battleship', 0);

  $self->{pbot}->{timer}->register(sub { $self->battleship_timer }, 1, 'battleship timer');

  $self->{pbot}->{event_dispatcher}->register_handler('irc.part',    sub { $self->on_departure(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',    sub { $self->on_departure(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',    sub { $self->on_kick(@_) });

  $self->{channel} = $self->{pbot}->{registry}->get_value('battleship', 'channel') // '##battleship';
  $self->{debug} = $self->{pbot}->{registry}->get_value('battleship', 'debug') // 0;

  $self->{player_one_vert}  = '|';
  $self->{player_one_horiz} = '—';
  $self->{player_two_vert}  = 'I';
  $self->{player_two_horiz} = '=';

  $self->create_states;
}

sub unload {
  my $self = shift;
  $self->{pbot}->{commands}->unregister('battleship');
  $self->{pbot}->{timer}->unregister('battleship timer');
  $self->{pbot}->{event_dispatcher}->remove_handler('irc.part');
  $self->{pbot}->{event_dispatcher}->remove_handler('irc.quit');
  $self->{pbot}->{event_dispatcher}->remove_handler('irc.kick');
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

sub battleship_cmd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  $arguments =~ s/^\s+|\s+$//g;

  my $usage = "Usage: battleship challenge|accept|bomb|board|score|quit|players|kick|abort; for more information about a command: battleship help <command>";

  my $command;
  ($command, $arguments) = split / /, $arguments, 2;
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
            return "Battleship help is coming soon.";
          } else {
            return "Usage: battleship help <command>";
          }
        }
      }
    }

    when ('leaderboard') {
      return "Coming soon.";
    }

    when ('challenge') {
      if ($self->{current_state} ne 'nogame') {
        return "There is already a game of Battleship underway.";
      }

      if (not length $arguments) {
        $self->{current_state} = 'accept';
        $self->{state_data} = { players => [], counter => 0 };

        my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
        my $player = { id => $id, name => $nick, missedinputs => 0 };
        push @{$self->{state_data}->{players}}, $player;

        $player = { id => -1, name => undef, missedinputs => 0 };
        push @{$self->{state_data}->{players}}, $player;
        return "/msg $self->{channel} $nick has made an open challenge!  Use `accept` to accept their challenge.";
      }

      my $challengee = $self->{pbot}->{nicklist}->is_present($self->{channel}, $arguments);

      if (not $challengee) {
        return "That nick is not present in this channel. Invite them to $self->{channel} and try again!";
      }

      $self->{current_state} = 'accept';
      $self->{state_data} = { players => [], counter => 0 };

      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      my $player = { id => $id, name => $nick, missedinputs => 0 };
      push @{$self->{state_data}->{players}}, $player;

      ($id) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($challengee);
      $player = { id => $id, name => $challengee, missedinputs => 0 };
      push @{$self->{state_data}->{players}}, $player;

      return "/msg $self->{channel} $nick has challenged $challengee to Battleship! Use `accept` to accept their challenge.";
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
        return "/msg $nick You have not been challenged to a game of Battleship yet.";
      }
    }

    when ($_ eq 'decline' or $_ eq 'quit' or $_ eq 'forfeit' or $_ eq 'concede') {
      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      my $removed = 0;

      for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
        if ($self->{state_data}->{players}->[$i]->{id} == $id) {
          $self->{state_data}->{players}->[$i]->{removed} = 1;
          $removed = 1;
        }
      }

      if ($removed) {
        if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
          $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1
        }

        if (@{$self->{state_data}->{players}} == 2 and ($self->{state_data}->{players}->[1]->{id} == -1 || not $self->{state_data}->{players}->[1]->{accepted})) {
          return "/msg $self->{channel} $nick declined the challenge.";
        } else {
          return "/msg $self->{channel} $nick has left the game!";
        }
      } else {
        return "$nick: But you are not even playing the game.";
      }
    }

    when ('abort') {
      if (not $self->{pbot}->{users}->loggedin_admin($self->{channel}, "$nick!$user\@$host")) {
        return "$nick: Sorry, only admins may abort the game.";
      }

      $self->{current_state} = 'gameover';
      return "/msg $self->{channel} $nick: The game has been aborted.";
    }

    when ('score') {
      if (@{$self->{state_data}->{players}} == 2) {
        $self->show_scoreboard;
        return;
      } else {
        return "There is no game going on right now.";
      }
    }

    when ('players') {
      if ($self->{current_state} eq 'accept') {
        return "$self->{state_data}->{players}->[0]->{name} has challenged $self->{state_data}->{players}->[1]->{name}!";
      } elsif (@{$self->{state_data}->{players}} == 2) {
        return "$self->{state_data}->{players}->[0]->{name} is in battle with $self->{state_data}->{players}->[1]->{name}!";
      } else {
        return "There are no players playing right now. Start a game with `battleship challenge <nick>`!";
      }
    }

    when ('kick') {
      if (not $self->{pbot}->{users}->loggedin_admin($self->{channel}, "$nick!$user\@$host")) {
        return "$nick: Sorry, only admins may kick people from the game.";
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
        if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
          $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1
        }
        return "/msg $self->{channel} $nick: $arguments has been kicked from the game.";
      } else {
        return "$nick: $arguments isn't even in the game.";
      }
    }

    when ('bomb') {
      if ($self->{debug}) {
        $self->{pbot}->{logger}->log("Battleship: bomb state: $self->{current_state}\n" . Dumper $self->{state_data});
      }

      if ($self->{current_state} ne 'playermove' and $self->{current_state} ne 'checkplayer') {
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

      if (not length $arguments) {
        if (delete $self->{state_data}->{players}->[$player]->{location}) {
          return "$nick: Attack location cleared.";
        } else {
          return "$nick: Usage: bomb <location>";
        }
      }

      if ($arguments !~ m/^[a-zA-Z][0-9]+$/) {
        return "$nick: Usage: battleship bomb <location>; <location> must be in the form of A15, B3, C9, etc.";
      }

      $arguments = uc $arguments;

      my ($x, $y);
      ($x) = $arguments =~ m/^(.)/;
      ($y) = $arguments =~ m/^.(.*)/;

      $x = ord($x) - 65;;

      if ($x < 0 || $x > $self->{N_Y} || $y < 0 || $y > $self->{N_X}) {
        return "$nick: Target out of range, try again.";
      }


      if ($self->{state_data}->{current_player} != $player) {
        my $msg;
        if (not exists $self->{state_data}->{players}->[$player]->{location}) {
          $msg = "$nick: You will attack $arguments when it is your turn.";
        } else {
          $msg = "$nick: You will now attack $arguments instead of $self->{state_data}->{players}->[$player]->{location} when it is your turn.";
        }
        $self->{state_data}->{players}->[$player]->{location} = $arguments;
        return $msg;
      }

      if ($self->{player}->[$player]->{done}) {
        return "$nick: You have already attacked this turn.";
      }

      if ($self->bomb($player, uc $arguments)) {
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
        $self->show_battlefield(2);
        return;
      }

      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      for (my $i = 0; $i < 2; $i++) {
        if ($self->{state_data}->{players}->[$i]->{id} == $id) {
          $self->send_message($self->{channel}, "$nick surveys the battlefield!");
          $self->show_battlefield($i);
          return;
        }
      }
      $self->show_battlefield(2);
    }

    when ('fullboard') {
      if (not $self->{pbot}->{users}->loggedin_admin($self->{channel}, "$nick!$user\@$host")) {
        return "$nick: Sorry, only admins may see the full board.";
      }

      if ($self->{current_state} eq 'nogame' or $self->{current_state} eq 'accept'
          or $self->{current_state} eq 'genboard' or $self->{current_state} eq 'gameover') {
        return "$nick: There is no board to show right now.";
      }

      # show real board if admin is actually in the game ... no cheating!
      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      for (my $i = 0; $i < 2; $i++) {
        if ($self->{state_data}->{players}->[$i]->{id} == $id) {
          $self->send_message($self->{channel}, "$nick surveys the battlefield!");
          $self->show_battlefield($i);
          return;
        }
      }
      $self->show_battlefield(4, $nick);
    }

    default {
      return $usage;
    }
  }

  return $result;
}

sub battleship_timer {
  my $self = shift;
  $self->run_one_state;
}

sub player_left {
  my ($self, $nick, $user, $host) = @_;

  my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  my $removed = 0;

  for (my $i = 0; $i < @{$self->{state_data}->{players}}; $i++) {
    if ($self->{state_data}->{players}->[$i]->{id} == $id) {
      $self->{state_data}->{players}->[$i]->{removed} = 1;
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
    nick => $botnick, user => 'battleship', host => 'localhost', command => 'battleship text', checkflood => 1,
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
        $self->{state_data}->{players}->[$i]->{removed} = 1;
        $removed = 1;
      }
    }

    if ($removed) {
      if ($self->{state_data}->{current_player} >= @{$self->{state_data}->{players}}) {
        $self->{state_data}->{current_player} = @{$self->{state_data}->{players}} - 1
      }
    }

    if ($self->{state_data}->{players}->[0]->{removed} or $self->{state_data}->{players}->[1]->{removed}) {
      $self->{current_state} = 'gameover';
    }
  }

  my $state_data = $self->{state_data};

  # this shouldn't happen
  if (not defined $self->{current_state}) {
    $self->{pbot}->{logger}->log("Battleship state broke.\n");
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
  if ($self->{debug} and $state_data->{newstate}) {
    $self->{pbot}->{logger}->log("Battleship: New state: $self->{current_state}\n" . Dumper $state_data);
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

  $self->{pbot}->{logger}->log("Battleship: Creating game state machine\n");

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

# battleship stuff

sub init_game {
  my ($self, $nick1, $nick2) = @_;

  $self->{N_X} = 15;
  $self->{N_Y} = 8;
  $self->{SHIPS} = 6;

  for (my $x = 0; $x < $self->{SHIPS}; $x++) {
    $self->{ship_length}->[$x] = 0;
  }

  $self->{board} = [];

  $self->{player} = [
    { bombs => 0, hit => 0, miss => 0, sunk => 0, nick => $nick1, done => 0 },
    { bombs => 0, hit => 0, miss => 0, sunk => 0, nick => $nick2, done => 0 }
  ];

  $self->{turn} = 0;
  $self->{horiz} = 0;

  $self->generate_battlefield;
}

sub count_ship_sections {
  my ($self, $player) = @_;
  my ($x, $y, $sections);

  $sections = 0;

  for ($x = 0; $x < $self->{N_Y}; $x++) {
    for ($y = 0; $y < $self->{N_X}; $y++) {
      if ($player == 0) {
        if ($self->{board}->[$x][$y] eq $self->{player_two_vert} || $self->{board}->[$x][$y] eq $self->{player_two_horiz}) {
          $sections++;
        }
      } else {
        if ($self->{board}->[$x][$y] eq $self->{player_one_vert} || $self->{board}->[$x][$y] eq $self->{player_one_horiz}) {
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
      if ($y - $l < 0) { return 0; }
    } else {
      $yd = 1;
      if ($y + $l >= $self->{N_X}) { return 0; }
    }
    $xd = 0;
  } else {
    if (!$d) {
      $xd = -1;
      if ($x - $l < 0) { return 0; }
    } else {
      $xd = 1;
      if ($x + $l >= $self->{N_Y}) { return 0; }
    }
    $yd = 0;
  }

  for (my $i = 0; $i < $l; $i++) {
    if ($self->{board}->[$x += $o ? $xd : 0][$y += $o ? 0 : $yd] ne '~') {
      return 0;
    }
  }

  return 1;
}

sub number {
  my ($self, $lower, $upper) = @_;
  return int(rand($upper - $lower)) + $lower;
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

    if (not $self->{ship_length}->[$ship]) {
      $l = $self->number(3, 6);
    } else {
      $l = $self->{ship_length}->[$ship];
    }

    $self->{pbot}->{logger}->log("generate ships player $player: ship $ship x,y: $x,$y  o,d: $o,$d length: $l\n");

    if ($self->check_ship($x, $y, $o, $d, $l)) {
      if (!$o) {
        if ($self->{horiz} < 2) { next; }
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
        $self->{board}->[$x += $o ? $xd : 0][$y += $o ? 0 : $yd] = $player ? ($o ? $self->{player_two_vert} : $self->{player_two_horiz}) : ($o ? $self->{player_one_vert} : $self->{player_one_horiz});
      }

      $self->{ship_length}->[$ship] = $l;
      return 1;
    }

    if (++$fail >= 5000) {
      $self->{pbot}->{logger}->log("Failed to generate ship\n");
      $self->send_message($self->{channel}, "Failed to place a ship. I cannot continue. Game over.");
      $self->{current_state} = 'nogame';
      return 0;
    }
  }
}

sub generate_battlefield {
  my ($self) = @_;
  my ($x, $y);

  for ($y = 0; $y < $self->{N_Y}; $y++) {
    for ($x = 0; $x < $self->{N_X}; $x++) {
      $self->{board}->[$y][$x] = '~';
    }
  }

  for ($x = 0; $x < $self->{SHIPS}; $x++) {
    if (!$self->generate_ship(0, $x) || !$self->generate_ship(1, $x)) {
      return 0;
    }
  }
  return 1;
}

sub check_sunk {
  my ($self, $x, $y, $player) = @_;
  my ($i, $target);

  $target = $self->{board}->[$x][$y];

  given ($target) {
    when ($_ eq $self->{player_two_vert} or $_ eq $self->{player_one_vert}) {
      for ($i = $x + 1; $i < $self->{N_Y}; $i++) {
        if (($self->{board}->[$i][$y] eq $self->{player_one_vert} && $player) || ($self->{board}->[$i][$y] eq $self->{player_two_vert} && !$player)) {
          return 0;
        }

        if ($self->{board}->[$i][$y] eq '~' || $self->{board}->[$i][$y] eq '*' || $self->{board}->[$i][$y] eq 'o') {
          last;
        }
      }

      for ($i = $x - 1; $i >= 0; $i--) {
        if (($self->{board}->[$i][$y] eq $self->{player_one_vert} && $player) || ($self->{board}->[$i][$y] eq $self->{player_two_vert} && !$player)) {
          return 0;
        }

        if ($self->{board}->[$i][$y] eq '~' || $self->{board}->[$i][$y] eq '*' || $self->{board}->[$i][$y] eq 'o') {
          last;
        }
      }

      return 1;
    }

    when ($_ eq $self->{player_one_horiz} or $_ eq $self->{player_two_horiz}) {
      for ($i = $y + 1; $i < $self->{N_X}; $i++) {
        if (($self->{board}->[$x][$i] eq $self->{player_one_horiz} && $player) || ($self->{board}->[$x][$i] eq $self->{player_two_horiz} && !$player)) {
          return 0;
        }

        if ($self->{board}->[$x][$i] eq '~' || $self->{board}->[$x][$i] eq '*' || $self->{board}->[$x][$i] eq 'o') {
          last;
        }
      }

      for ($i = $y - 1; $i >= 0; $i--) {
        if (($self->{board}->[$x][$i] eq $self->{player_one_horiz} && $player) || ($self->{board}->[$x][$i] eq $self->{player_two_horiz} && !$player)) {
          return 0;
        }

        if ($self->{board}->[$x][$i] eq '~' || $self->{board}->[$x][$i] eq '*' || $self->{board}->[$x][$i] eq 'o') {
          last;
        }
      }

      return 1;
    }
  }
}

sub bomb {
  my ($self, $player, $location) = @_;
  my ($x, $y, $hit, $sections, $sunk) = (0, 0, 0, 0, 0);

  $location = uc $location;

  ($x) = $location =~ m/^(.)/;
  ($y) = $location =~ m/^.(.*)/;

  $x = ord($x) - 65;;

  $self->{pbot}->{logger}->log("bomb player $player   $x,$y  $self->{board}->[$x][$y]\n");

  if ($x < 0 || $x > $self->{N_Y} || $y < 0 || $y > $self->{N_X}) {
    $self->send_message($self->{channel}, "Target out of range, try again.");
    return 0;
  }

  $y--;

  if (!$player) {
    if ($self->{board}->[$x][$y] eq $self->{player_two_vert} || $self->{board}->[$x][$y] eq $self->{player_two_horiz}) {
      $hit = 1;
    }
  } else {
    if ($self->{board}->[$x][$y] eq $self->{player_one_vert} || $self->{board}->[$x][$y] eq $self->{player_one_horiz}) {
      $hit = 1;
    }
  }

  $sunk = $self->check_sunk($x, $y, $player);

  if ($hit) {
    if (!$player) {
      $self->{board}->[$x][$y] = '1';
    } else {
      $self->{board}->[$x][$y] = '2';
    }
    $self->{player}->[$player]->{hit}++;
  } else {
    if ($self->{board}->[$x][$y] eq '~') {
      if (!$player) {
        $self->{board}->[$x][$y] = '*';
      } else {
        $self->{board}->[$x][$y] = 'o';
      }
      $self->{player}->[$player]->{miss}++;
    }
  }

  my $nick1 = $self->{player}->[$player]->{nick};
  my $nick2 = $self->{player}->[$player ? 0 : 1]->{nick};

  my @attacks = ("launches torpedoes at", "launches nukes at", "fires cannons at", "fires torpedoes at", "fires nukes at",
    "launches tomahawk missiles at", "fires a gatling gun at", "launches ballistic missiles at");

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

  my $buf;
  my $p1sections = $self->count_ship_sections(1);
  my $p2sections = $self->count_ship_sections(0);

  my $p1win = "";
  my $p2win = "";

  if ($p1sections > $p2sections) {
    $p1win = "$color{bold}$color{lightgreen} * ";
    $p2win = "$color{red}   ";
  } elsif ($p1sections < $p2sections) {
    $p1win = "$color{red}   ";
    $p2win = "$color{bold}$color{lightgreen} * ";
  }

  my $length_a = length $self->{player}->[0]->{nick};
  my $length_b = length $self->{player}->[1]->{nick};
  my $longest = $length_a > $length_b ? $length_a : $length_b;

  my $bombslen = ($self->{player}->[0]->{bombs} > 10 || $self->{player}->[1]->{bombs} > 10) ? 2 : 1;
  my $hitlen = ($self->{player}->[0]->{hit} > 10 || $self->{player}->[1]->{hit} > 10) ? 2 : 1;
  my $misslen = ($self->{player}->[0]->{miss} > 10 || $self->{player}->[1]->{miss} > 10) ? 2 : 1;
  my $sunklen = ($self->{player}->[0]->{sunk} > 10 || $self->{player}->[1]->{sunk} > 10) ? 2 : 1;
  my $intactlen = ($p1sections > 10 || $p2sections > 10) ? 2 : 1;

  my $p1bombscolor = $self->{player}->[0]->{bombs} > $self->{player}->[1]->{bombs} ? $color{green} : $color{red};
  my $p1hitcolor = $self->{player}->[0]->{hit} > $self->{player}->[1]->{hit} ? $color{green} : $color{red};
  my $p1misscolor = $self->{player}->[0]->{miss} < $self->{player}->[1]->{miss} ? $color{green} : $color{red};
  my $p1sunkcolor = $self->{player}->[0]->{sunk} > $self->{player}->[1]->{sunk} ? $color{green} : $color{red};
  my $p1intactcolor = $p1sections > $p2sections ? $color{green} : $color{red};

  my $p2bombscolor = $self->{player}->[0]->{bombs} < $self->{player}->[1]->{bombs} ? $color{green} : $color{red};
  my $p2hitcolor = $self->{player}->[0]->{hit} < $self->{player}->[1]->{hit} ? $color{green} : $color{red};
  my $p2misscolor = $self->{player}->[0]->{miss} > $self->{player}->[1]->{miss} ? $color{green} : $color{red};
  my $p2sunkcolor = $self->{player}->[0]->{sunk} < $self->{player}->[1]->{sunk} ? $color{green} : $color{red};
  my $p2intactcolor = $p1sections < $p2sections ? $color{green} : $color{red};

  $buf = sprintf("$p1win%*s$color{reset}: bomb: $p1bombscolor%*d$color{reset}, hit: $p1hitcolor%*d$color{reset}, miss: $p1misscolor%*d$color{reset}, sunk: $p1sunkcolor%*d$color{reset}, sections left: $p1intactcolor%*d$color{reset}",
    $longest, $self->{player}->[0]->{nick}, $bombslen, $self->{player}->[0]->{bombs},
    $hitlen, $self->{player}->[0]->{hit}, $misslen, $self->{player}->[0]->{miss},
    $sunklen, $self->{player}->[0]->{sunk}, $intactlen, $p1sections);
  $self->send_message($self->{channel}, $buf);
  $buf = sprintf("$p2win%*s$color{reset}: bomb: $p2bombscolor%*d$color{reset}, hit: $p2hitcolor%*d$color{reset}, miss: $p2misscolor%*d$color{reset}, sunk: $p2sunkcolor%*d$color{reset}, sections left: $p2intactcolor%*d$color{reset}",
    $longest, $self->{player}->[1]->{nick}, $bombslen, $self->{player}->[1]->{bombs},
    $hitlen, $self->{player}->[1]->{hit}, $misslen, $self->{player}->[1]->{miss},
    $sunklen, $self->{player}->[1]->{sunk}, $intactlen, $p2sections);
  $self->send_message($self->{channel}, $buf);
}

sub show_battlefield {
  my ($self, $player, $nick) = @_;
  my ($x, $y, $buf);

  $self->{pbot}->{logger}->log("showing battlefield for player $player\n");

  $buf = "$color{cyan},01  ";

  for($x = 1; $x < $self->{N_X} + 1; $x++) {
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

  for ($y = 0; $y < $self->{N_Y}; $y++) {
    $buf .= sprintf("$color{cyan},01%c ", 97 + $y);
    for ($x = 0; $x < $self->{N_X}; $x++) {
      if ($player == 0) {
        if ($self->{board}->[$y][$x] eq $self->{player_two_vert} || $self->{board}->[$y][$x] eq $self->{player_two_horiz}) {
          $buf .= "$color{blue},01~ ";
          next;
        } else {
          if ($self->{board}->[$y][$x] eq '1' || $self->{board}->[$y][$x] eq '2') {
            $buf .= "$color{red},01";
          } elsif ($self->{board}->[$y][$x] eq 'o' || $self->{board}->[$y][$x] eq '*') {
            $buf .= "$color{cyan},01";
          } elsif ($self->{board}->[$y][$x] eq '~') {
            $buf .= "$color{blue},01~ ";
            next;
          } else {
            $buf .= "$color{white},01";
          }
          $buf .= "$self->{board}->[$y][$x] ";
          $self->{pbot}->{logger}->log("$y, $x: $self->{board}->[$y][$x]\n");
        }
      } elsif ($player == 1) {
        if ($self->{board}->[$y][$x] eq $self->{player_one_vert} || $self->{board}->[$y][$x] eq $self->{player_one_horiz}) {
          $buf .= "$color{blue},01~ ";
          next;
        } else {
          if ($self->{board}->[$y][$x] eq '1' || $self->{board}->[$y][$x] eq '2') {
            $buf .= "$color{red},01";
          } elsif ($self->{board}->[$y][$x] eq 'o' || $self->{board}->[$y][$x] eq '*') {
            $buf .= "$color{cyan},01";
          } elsif ($self->{board}->[$y][$x] eq '~') {
            $buf .= "$color{blue},01~ ";
            next;
          } else {
            $buf .= "$color{white},01";
          }
          $buf .= "$self->{board}->[$y][$x] ";
        }
      } elsif ($player == 2) {
        if ($self->{board}->[$y][$x] eq $self->{player_one_vert} || $self->{board}->[$y][$x] eq $self->{player_one_horiz}
          || $self->{board}->[$y][$x] eq $self->{player_two_vert} || $self->{board}->[$y][$x] eq $self->{player_two_horiz}) {
          $buf .= "$color{blue},01~ ";
          next;
        } else {
          if ($self->{board}->[$y][$x] eq '1' || $self->{board}->[$y][$x] eq '2') {
            $buf .= "$color{red},01";
          } elsif ($self->{board}->[$y][$x] eq 'o' || $self->{board}->[$y][$x] eq '*') {
            $buf .= "$color{cyan},01";
          } elsif ($self->{board}->[$y][$x] eq '~') {
            $buf .= "$color{blue},01~ ";
            next;
          } else {
            $buf .= "$color{white},01";
          }
          $buf .= "$self->{board}->[$y][$x] ";
        }
      } else {
        if ($self->{board}->[$y][$x] eq '1' || $self->{board}->[$y][$x] eq '2') {
          $buf .= "$color{red},01";
        } elsif ($self->{board}->[$y][$x] eq 'o' || $self->{board}->[$y][$x] eq '*') {
          $buf .= "$color{cyan},01";
        } elsif ($self->{board}->[$y][$x] eq '~') {
          $buf .= "$color{blue},01~ ";
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

  for($x = 1; $x < $self->{N_X} + 1; $x++) {
    if ($x % 10 == 0) {
      $buf .= $color{yellow},01 if $self->{N_X} > 10;
      $buf .= $x % 10;
      $buf .= ' ';
      $buf .= $color{cyan},01 if $self->{N_X} > 10;
    } else {
      $buf .= $x % 10;
      $buf .= ' ';
    }
  }

  $buf .= "\n";

  my $player1 = $self->{player}->[0]->{nick};
  my $player2 = $self->{player}->[1]->{nick};

  if ($player == 0) {
    $self->send_message($self->{player}->[$player]->{nick}, "Player One Legend: ships: [| -]  ocean: [$color{blue},01~$color{reset}]  $player1 miss: [$color{cyan},01*$color{reset}]  $player2 miss: [$color{cyan},01o$color{reset}]  $player1 hit: [$color{red},01"."1"."$color{reset}]  $player2 hit: [$color{red},012$color{reset}]");
  } elsif ($player == 1) {
    $self->send_message($self->{player}->[$player]->{nick}, "Player Two Legend: ships: [I =]  ocean: [$color{blue},01~$color{reset}]  $player1 miss: [$color{cyan},01*$color{reset}]  $player2 miss: [$color{cyan},01o$color{reset}]  $player1 hit: [$color{red},01"."1"."$color{reset}]  $player2 hit: [$color{red},012$color{reset}]");
  } elsif ($player == 2) {
    $self->send_message($self->{channel}, "Spectator Legend: ocean: [$color{blue},01~$color{reset}]  $player1 miss: [$color{cyan},01*$color{reset}]  $player2 miss: [$color{cyan},01o$color{reset}]  $player1 hit: [$color{red},01"."1"."$color{reset}]  $player2 hit: [$color{red},012$color{reset}]");
  } elsif ($player == 3) {
    $self->send_message($self->{channel}, "Final Board Legend: $player1 ships: [| -] $player2 ships: [I =]  ocean: [$color{blue},01~$color{reset}]  $player1 miss: [$color{cyan},01*$color{reset}]  $player2 miss: [$color{cyan},01o$color{reset}]  $player1 hit: [$color{red},01"."1"."$color{reset}]  $player2 hit: [$color{red},012$color{reset}]");
  } else {
    $self->send_message($nick, "Full Board Legend: $player1 ships: [| -] $player2 ships: [I =]  ocean: [$color{blue},01~$color{reset}]  $player1 miss: [$color{cyan},01*$color{reset}]  $player2 miss: [$color{cyan},01o$color{reset}]  $player1 hit: [$color{red},01"."1"."$color{reset}]  $player2 hit: [$color{red},012$color{reset}]");
  }

  foreach my $line (split /\n/, $buf) {
    if ($player == 0 || $player == 1) {
      $self->send_message($self->{player}->[$player]->{nick}, $line);
    } elsif ($player == 2 || $player == 3) {
      $self->send_message($self->{channel}, $line);
    } else {
      $self->send_message($nick, $line);
    }
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
  $state->{current_player} = 0;
  $state->{max_count} = 3;
  $state->{result} = 'next';
  return $state;
}

sub showboard {
  my ($self, $state) = @_;
  $self->send_message($self->{channel}, "Showing battlefield to $self->{player}->[0]->{nick}...");
  $self->show_battlefield(0);
  $self->send_message($self->{channel}, "Showing battlefield to $self->{player}->[1]->{nick}...");
  $self->show_battlefield(1);
  $self->send_message($self->{channel}, "Fight! Anybody (players and spectators) can use `board` at any time to see the battlefield.");
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

  my $player = $state->{current_player};
  my $location = delete $state->{players}->[$player]->{location};

  if (defined $location) {
    if ($self->bomb($player, uc $location)) {
      $self->{player}->[$player]->{done} = 1;
      $self->{player}->[!$player]->{done} = 0;
      $self->{state_data}->{current_player} = !$player;
      $state->{result} = 'next';
      return $state;
    }
  }

  if ($state->{ticks} % $tock == 0) {
    $state->{tocked} = 1;
    if (++$state->{counter} > $state->{max_count}) {
      $state->{players}->[$state->{current_player}]->{missedinputs}++;
      $self->send_message($self->{channel}, "$state->{players}->[$state->{current_player}]->{name} failed to launch an attack in time. They forfeit their turn!");
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

    $self->send_message($self->{channel}, "$state->{players}->[$state->{current_player}]->{name}: $red$remaining Launch an attack now via `bomb <location>`!$color{reset}");
  }

  $state->{result} = 'wait';
  return $state;
}

sub checkplayer {
  my ($self, $state) = @_;

  if ($self->{player}->[0]->{won} or $self->{player}->[1]->{won}) {
    $state->{result} = 'sunk';
  } else {
    $state->{result} = 'next';
  }
  return $state;
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
    $state->{counter} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

1;
