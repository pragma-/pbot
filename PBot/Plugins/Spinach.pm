# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Plugins::Spinach;

use warnings;
use strict;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use Carp ();
use DBI;
use JSON;

use Lingua::EN::Fractions qw/fraction2words/;
use Lingua::EN::Numbers qw/num2en num2en_ordinal/;
use Lingua::EN::Numbers::Years qw/year2en/;
use Lingua::Stem qw/stem/;
use Lingua::EN::ABC qw/b2a/;

use Data::Dumper;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{pbot}->{commands}->register(sub { $self->spinach_cmd(@_) }, 'spinach', 0);

  $self->{pbot}->{timer}->register(sub { $self->spinach_timer }, 1, 'spinach timer');

  $self->{pbot}->{event_dispatcher}->register_handler('irc.part',    sub { $self->on_departure(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',    sub { $self->on_departure(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',    sub { $self->on_kick(@_) });

  $self->{leaderboard_filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spinach/spinachlb.sqlite3';
  $self->{questions_filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spinach/spinachq.json';
  $self->{stopwords_filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spinach/stopwords';

  $self->create_database;
  $self->create_states;
  $self->load_questions;
  $self->load_stopwords;

  $self->{channel} = '##spinach';

  $self->{choosecategory_max_count} = 2;
  $self->{picktruth_max_count} = 4;
}

sub unload {
  my $self = shift;
  $self->{pbot}->{commands}->unregister('spinach');
  $self->{pbot}->{timer}->unregister('spinach timer');
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

sub load_questions {
  my $self = shift;

  my $contents = do {
    open my $fh, '<', $self->{questions_filename} or do {
      $self->{pbot}->{logger}->log("Spinach: Failed to open $self->{questions_filename}: $!\n");
      return;
    };
    local $/;
    <$fh>;
  };

  $self->{questions} = decode_json $contents;
  $self->{categories} = ();

  my $questions;
  foreach my $key (keys %{$self->{questions}}) {
    foreach my $question (@{$self->{questions}->{$key}}) {
      $question->{category} = uc $question->{category};
      $self->{categories}{$question->{category}}{$question->{id}} = $question;
      $questions++;
    }
  }

  my $categories;
  foreach my $category (sort { keys %{$self->{categories}{$b}} <=> keys %{$self->{categories}{$a}} } keys %{$self->{categories}}) {
    my $count = keys %{$self->{categories}{$category}};
    $self->{pbot}->{logger}->log("Category [$category]: $count\n");
    $categories++;
  }

  $self->{pbot}->{logger}->log("Spinach: Loaded $questions questions in $categories categories.\n");
}

sub load_stopwords {
  my $self = shift;

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

sub create_database {
  my $self = shift;

  eval {
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{leaderboard_filename}", "", "", { RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1 }) or die $DBI::errstr;

    $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Leaderboard (
  userid      NUMERIC,
  created_on  NUMERIC,
  wins        NUMERIC,
  highscore   NUMERIC,
  avgscore    NUMERIC
)
SQL

    $self->{dbh}->disconnect;
  };

  $self->{pbot}->{logger}->log("Spinach create database failed: $@") if $@;
}

sub dbi_begin {
  my ($self) = @_;
  eval {
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{leaderboard_filename}", "", "", { RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1 }) or die $DBI::errstr;
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Error opening Spinach database: $@");
    return 0;
  } else {
    return 1;
  }
}

sub dbi_end {
  my ($self) = @_;
  $self->{dbh}->disconnect;
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

sub spinach_cmd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  $arguments =~ s/^\s+|\s+$//g;

  my $usage = "Usage: spinach start|stop|abort|join|exit|ready|unready|kick|choose|lie|skip|score|show; for more information about a command: spinach help <command>";

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

        when ('start') {
          return "Help is coming soon.";
        }

        when ('join') {
          return "Help is coming soon.";
        }

        when ('ready') {
          return "Help is coming soon.";
        }

        when ('exit') {
          return "Help is coming soon.";
        }

        when ('skip') {
          return "Use `skip` to skip a question and return to the \"choose category\" stage. A majority of the players must agree to skip.";
        }

        when ('abort') {
          return "Help is coming soon.";
        }

        when ('stop') {
          return "Help is coming soon.";
        }

        when ('kick') {
          return "Help is coming soon.";
        }

        when ('players') {
          return "Help is coming soon.";
        }

        when ('score') {
          return "Help is coming soon.";
        }

        when ('leaderboard') {
          return "Help is coming soon.";
        }

        when ('choose') {
          return "Help is coming soon.";
        }

        when ('lie') {
          return "Help is coming soon.";
        }

        when ('truth') {
          return "Help is coming soon.";
        }

        when ('show') {
          return "Help is coming soon.";
        }

        default {
          if (length $arguments) {
            return "Spinach has no such command '$arguments'. I can't help you with that.";
          } else {
            return "Usage: spinach help <command>";
          }
        }
      }
    }

    when ('edit') {
      my $admin = $self->{pbot}->{admins}->loggedin($self->{channel}, "$nick!$user\@$host");

      if (not $admin) {
        return "$nick: Sorry, only admins may edit questions.";
      }

      my ($id, $key, $value) = split /\s+/, $arguments, 3;

      if (not defined $id) {
        return "Usage: spinach edit <question id> [key] [value]";
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
        return "$nick: No such question.";
      }

      if (not defined $key) {
        my $dump = Dumper $question;
        $dump =~ s/\$VAR\d+ = \{\s*//;
        $dump =~ s/ \};\s*$//;
        return "$nick: Question $id: $dump";
      }

      if (not defined $value) {
        my $v = $question->{$key} // 'unset';
        return "$nick: Question $id: $key => $v";
      }

      $question->{$key} = $value;

      my $json = encode_json $self->{questions};
      open my $fh, '>', $self->{questions_filename} or do {
        $self->{pbot}->{logger}->log("Failed to open Spinach file: $!\n");
        return;
      };
      print $fh "$json\n";
      close $fh;

      $self->load_questions;

      return "$nick: Question $id: $key set to $value";
    }

    when ('load') {
      my $admin = $self->{pbot}->{admins}->loggedin($self->{channel}, "$nick!$user\@$host");

      if (not $admin or $admin->{level} < 90) {
        return "$nick: Sorry, only very powerful admins may reload the questions.";
      }

      $self->load_questions;
    }

    when ('start') {
      if ($self->{current_state} eq 'nogame') {
        $self->{current_state} = 'getplayers';
        $self->{previous_state} = 'nogame';
        $self->{state_data} = { players => [], counter => 0 };
        return "/msg $self->{channel} Starting Spinach.";
      } else {
        return "Spinach is already started.";
      }
    }

    when ('leaderboard') {
      return "Coming soon.";
    }

    when ('join') {
      if ($self->{current_state} eq 'nogame') {
        $self->{state_data} = { players => [], counter => 0 };
        $self->{current_state} = 'getplayers';
      }

      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

      foreach my $player (@{$self->{state_data}->{players}}) {
        if ($player->{id} == $id) {
          return "$nick: You have already joined this game.";
        }
      }

      my $player = { id => $id, name => $nick, score => 0, ready => $self->{current_state} eq 'getplayers' ? 0 : 1, missedinputs => 0 };
      push @{$self->{state_data}->{players}}, $player;
      $self->{state_data}->{counter} = 0;
      return "/msg $self->{channel} $nick has joined the game!";
    }

    when ('ready') {
      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

      foreach my $player (@{$self->{state_data}->{players}}) {
        if ($player->{id} == $id) {
          if ($self->{current_state} ne 'getplayers') {
            return "/msg $nick This is not the time to use `ready`.";
          }

          if ($player->{ready} == 0) {
            $player->{ready} = 1;
            $player->{score} = 0;
            return "/msg $self->{channel} $nick is ready!";
          } else {
            return "/msg $nick You are already ready.";
          }
        }
      }

      return "$nick: You haven't joined this game yet. Use `j` to play now!";
    }

    when ('unready') {
      my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

      foreach my $player (@{$self->{state_data}->{players}}) {
        if ($player->{id} == $id) {
          if ($self->{current_state} ne 'getplayers') {
            return "/msg $nick This is not the time to use `unready`.";
          }

          if ($player->{ready} != 0) {
            $player->{ready} = 0;
            return "/msg $self->{channel} $nick is no longer ready!";
          } else {
            return "/msg $nick You are already not ready.";
          }
        }
      }

      return "$nick: You haven't joined this game yet. Use `j` to play now!";
    }

    when ('exit') {
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

      my $text = '';
      my $comma = '';
      foreach my $player (sort { $b->{score} <=> $a->{score} } @{$self->{state_data}->{players}}) {
        $text .= "$comma$player->{name}: " . $self->commify($player->{score});
        $comma = '; ';
      }
      return $text;
    }

    when ('stop') {
      if ($self->{current_state} ne 'getplayers') {
        return "This command can only be used during the 'Waiting for players' stage. To stop a game in progress, use the `abort` command.";
      }

      $self->{current_state} = 'nogame';
      return "/msg $self->{channel} $nick: The game has been stopped.";
    }

    when ('kick') {
      if (not $self->{pbot}->{admins}->loggedin($self->{channel}, "$nick!$user\@$host")) {
        return "$nick: Sorry, only admins may kick people from the game.";
      }

      if (not length $arguments) {
        return "Usage: spinach kick <nick>";
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

    when ('n') {
      return $self->normalize_text($arguments);
    }

    when ('v') {
      my ($truth, $lie) = split /;/, $arguments;
      return $self->validate_lie($self->normalize_text($truth), $self->normalize_text($lie));
    }

    when ('skip') {
      if ($self->{current_state} =~ /getlies$/) {
        my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

        my $player;
        my $skipped = 0;
        foreach my $i (@{$self->{state_data}->{players}}) {
          if ($i->{id} == $id) {
            $i->{skip} = 1;
            $skipped++;
            $player = $i;
          } elsif ($i->{skip}) {
            $skipped++;
          }
        }

        if (not $player) {
          return "$nick: You are not playing in this game. Use `j` to start playing now!";
        }

        my $needed = int (@{$self->{state_data}->{players}} / 2) + 1;
        $needed -= $skipped;

        my $votes_needed;
        if ($needed == 1) {
          $votes_needed = "$needed more vote to skip!";
        } elsif ($needed > 1) {
          $votes_needed = "$needed more votes to skip!";
        } else {
          $votes_needed = "Skipping...";
        }

        return "/msg $self->{channel} $color{red}$nick has voted to skip this question! $color{reset}$votes_needed";
      } else {
        return "$nick: This command can be used only during the \"submit lies\" stage.";
      }
    }

    when ($_ eq 'lie' or $_ eq 'truth' or $_ eq 'choose') {
      $arguments = lc $arguments;
      if ($self->{current_state} =~ /choosecategory$/) {
        if (not length $arguments) {
          return "Usage: spinach choose <integer>";
        }

        my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

        if (not @{$self->{state_data}->{players}} or $id != $self->{state_data}->{players}->[$self->{state_data}->{current_player}]->{id}) {
          return "$nick: It is not your turn to choose a category.";
        }

        if ($arguments !~ /^[0-9]+$/) {
          return "$nick: Please choose a category number. $self->{state_data}->{categories_text}";
        }

        $arguments--;

        if ($arguments < 0 or $arguments >= @{$self->{state_data}->{category_options}}) {
          return "$nick: Choice out of range. Please choose a valid category. $self->{state_data}->{categories_text}";
        }

        $self->{state_data}->{current_category} = $self->{state_data}->{category_options}->[$arguments];
        return "/msg $self->{channel} $nick has chosen $self->{state_data}->{current_category}!";
      }

      if ($self->{current_state} =~ /getlies$/) {
        if (not length $arguments) {
          return "Usage: spinach lie <text>";
        }

        my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

        my $player;
        foreach my $i (@{$self->{state_data}->{players}}) {
          if ($i->{id} == $id) {
            $player = $i;
            last;
          }
        }

        if (not $player) {
          return "$nick: You are not playing in this game. Use `j` to start playing now!";
        }

        $arguments = $self->normalize_text($arguments);

        my $found_truth = 0;

        if (not $self->validate_lie($self->{state_data}->{current_question}->{answer}, $arguments)) {
          $found_truth = 1;
        }

        foreach my $alt (@{$self->{state_data}->{current_question}->{alternativeSpellings}}) {
          if (not $self->validate_lie($alt, $arguments)) {
            $found_truth = 1;
            last;
          }
        }

        if ($found_truth) {
          return "$nick: Your lie is too similar to the truth! Please submit a different lie.";
        }

        my $changed = exists $player->{lie};
        $player->{lie} = $arguments;

        if ($changed) {
          return "/msg $self->{channel} $nick has changed their lie!";
        } else {
          return "/msg $self->{channel} $nick has submitted a lie!";
        }
      }

      if ($self->{current_state} =~ /findtruth$/) {
        if (not length $arguments) {
          return "Usage: spinach truth <integer>";
        }

        my $id = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

        my $player;
        foreach my $i (@{$self->{state_data}->{players}}) {
          if ($i->{id} == $id) {
            $player = $i;
            last;
          }
        }

        if (not $player) {
          return "$nick: You are not playing in this game. Use `j` to start playing now!";
        }

        if ($arguments !~ /^[0-9]+$/) {
          return "$nick: Please select a truth number. $self->{state_data}->{current_choices_text}";
        }

        $arguments--;

        if ($arguments < 0 or $arguments >= @{$self->{state_data}->{current_choices}}) {
          return "$nick: Selection out of range. Please select a valid truth: $self->{state_data}->{current_choices_text}";
        }

        my $changed = exists $player->{truth};
        $player->{truth} = uc $self->{state_data}->{current_choices}->[$arguments];

        if ($player->{truth} eq $player->{lie}) {
          delete $player->{truth};
          return "$nick: You cannot select your own lie!";
        }

        if ($changed) {
          return "/msg $self->{channel} $nick has selected a different truth!";
        } else {
          return "/msg $self->{channel} $nick has selected a truth!";
        }
      }

      return "$nick: It is not time to use this command.";
    }

    when ('show') {
      if ($self->{current_state} =~ /(?:getlies|findtruth|showlies)$/) {
        $self->showquestion($self->{state_data});
        return;
      }

      return "$nick: There is nothing to show right now.";
    }

    default {
      return $usage;
    }
  }

  return $result;
}

sub spinach_timer {
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
      $self->send_message($self->{channel}, "$color{bold}$nick has left the game!$color{reset}");
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
    nick => $botnick, user => 'spinach', host => 'localhost', command => 'spinach text', checkflood => 1,
    message => $text
  };
  $self->{pbot}->{interpreter}->add_message_to_output_queue($to, $message, $delay);
}

sub add_new_suggestions {
  my ($self, $state) = @_;

  my $question = undef;
  my $modified = 0;

  foreach my $player (@{$state->{players}}) {
    if ($player->{deceived}) {
      $self->{pbot}->{logger}->log("Adding new suggestion for $state->{current_question}->{id}: $player->{deceived}\n");

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

  if ($modified) {
    my $json = encode_json $self->{questions};
    open my $fh, '>', $self->{questions_filename} or do {
      $self->{pbot}->{logger}->log("Failed to open Spinach file: $!\n");
      return;
    };
    print $fh "$json\n";
    close $fh;
  }
}

sub run_one_state {
  my $self = shift;

  if ($self->{current_state} =~ /r\dq\d/) {
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

    if (not @{$self->{state_data}->{players}}) {
      $self->send_message($self->{channel}, "$color{bold}All players have left the game!$color{reset}");
      $self->{current_state} = 'nogame';
    }
  }

  my $current_state = $self->{current_state};
  my $state_data = $self->{state_data};

  if (not defined $current_state) {
    $self->{pbot}->{logger}->log("Spinach state broke.\n");
    return;
  }

  if ($self->{previous_state} ne $self->{current_state}) {
    $state_data->{newstate} = 1;
    $state_data->{ticks} = 1;
    $state_data->{first_tock} = 1;
  } else {
    $state_data->{newstate} = 0;
  }

  if ($state_data->{newstate}) {
    $self->{pbot}->{logger}->log("Spinach: New state: $self->{current_state}\n" . Dumper $state_data);
  }

  $state_data = $self->{states}{$current_state}{sub}($state_data);

  $state_data->{previous_result} = $state_data->{result};

  $self->{previous_state} = $self->{current_state};
  $self->{current_state} = $self->{states}{$current_state}{trans}{$state_data->{result}};
  $self->{state_data} = $state_data;

  $self->{state_data}->{ticks}++;
}

sub create_states {
  my $self = shift;

  $self->{pbot}->{logger}->log("Spinach: Creating game state machine\n");

  $self->{previous_state} = '';
  $self->{current_state} = 'nogame';
  $self->{state_data} = { players => [], ticks => 0, newstate => 1 };


  $self->{states}{'nogame'}{sub} = sub { $self->nogame(@_) };
  $self->{states}{'nogame'}{trans}{start} = 'getplayers';
  $self->{states}{'nogame'}{trans}{nogame} = 'nogame';


  $self->{states}{'getplayers'}{sub} = sub { $self->getplayers(@_) };
  $self->{states}{'getplayers'}{trans}{stop} = 'nogame';
  $self->{states}{'getplayers'}{trans}{wait} = 'getplayers';
  $self->{states}{'getplayers'}{trans}{allready} = 'round1';


  $self->{states}{'round1'}{sub} = sub { $self->round1(@_) };
  $self->{states}{'round1'}{trans}{next} = 'round1q1';

  $self->{states}{'round1q1'}{sub} = sub { $self->round1q1(@_) };
  $self->{states}{'round1q1'}{trans}{next} = 'r1q1choosecategory';
  $self->{states}{'r1q1choosecategory'}{sub} = sub { $self->r1q1choosecategory(@_) };
  $self->{states}{'r1q1choosecategory'}{trans}{wait} = 'r1q1choosecategory';
  $self->{states}{'r1q1choosecategory'}{trans}{next} = 'r1q1showquestion';
  $self->{states}{'r1q1showquestion'}{sub} = sub { $self->r1q1showquestion(@_) };
  $self->{states}{'r1q1showquestion'}{trans}{wait} = 'r1q1showquestion';
  $self->{states}{'r1q1showquestion'}{trans}{next} = 'r1q1getlies';
  $self->{states}{'r1q1getlies'}{sub} = sub { $self->r1q1getlies(@_) };
  $self->{states}{'r1q1getlies'}{trans}{skip} = 'round1q1';
  $self->{states}{'r1q1getlies'}{trans}{wait} = 'r1q1getlies';
  $self->{states}{'r1q1getlies'}{trans}{next} = 'r1q1findtruth';
  $self->{states}{'r1q1findtruth'}{sub} = sub { $self->r1q1findtruth(@_) };
  $self->{states}{'r1q1findtruth'}{trans}{wait} = 'r1q1findtruth';
  $self->{states}{'r1q1findtruth'}{trans}{next} = 'r1q1showlies';
  $self->{states}{'r1q1showlies'}{sub} = sub { $self->r1q1showlies(@_) };
  $self->{states}{'r1q1showlies'}{trans}{wait} = 'r1q1showlies';
  $self->{states}{'r1q1showlies'}{trans}{next} = 'r1q1showtruth';
  $self->{states}{'r1q1showtruth'}{sub} = sub { $self->r1q1showtruth(@_) };
  $self->{states}{'r1q1showtruth'}{trans}{wait} = 'r1q1showtruth';
  $self->{states}{'r1q1showtruth'}{trans}{next} = 'r1q1reveallies';
  $self->{states}{'r1q1reveallies'}{sub} = sub { $self->r1q1reveallies(@_) };
  $self->{states}{'r1q1reveallies'}{trans}{wait} = 'r1q1reveallies';
  $self->{states}{'r1q1reveallies'}{trans}{next} = 'r1q1showscore';
  $self->{states}{'r1q1showscore'}{sub} = sub { $self->r1q1showscore(@_) };
  $self->{states}{'r1q1showscore'}{trans}{wait} = 'r1q1showscore';
  $self->{states}{'r1q1showscore'}{trans}{next} = 'round1q2';

  $self->{states}{'round1q2'}{sub} = sub { $self->round1q2(@_) };
  $self->{states}{'round1q2'}{trans}{next} = 'r1q2choosecategory';
  $self->{states}{'r1q2choosecategory'}{sub} = sub { $self->r1q2choosecategory(@_) };
  $self->{states}{'r1q2choosecategory'}{trans}{wait} = 'r1q2choosecategory';
  $self->{states}{'r1q2choosecategory'}{trans}{next} = 'r1q2showquestion';
  $self->{states}{'r1q2showquestion'}{sub} = sub { $self->r1q2showquestion(@_) };
  $self->{states}{'r1q2showquestion'}{trans}{wait} = 'r1q2showquestion';
  $self->{states}{'r1q2showquestion'}{trans}{next} = 'r1q2getlies';
  $self->{states}{'r1q2getlies'}{sub} = sub { $self->r1q2getlies(@_) };
  $self->{states}{'r1q2getlies'}{trans}{skip} = 'round1q2';
  $self->{states}{'r1q2getlies'}{trans}{wait} = 'r1q2getlies';
  $self->{states}{'r1q2getlies'}{trans}{next} = 'r1q2findtruth';
  $self->{states}{'r1q2findtruth'}{sub} = sub { $self->r1q2findtruth(@_) };
  $self->{states}{'r1q2findtruth'}{trans}{wait} = 'r1q2findtruth';
  $self->{states}{'r1q2findtruth'}{trans}{next} = 'r1q2showlies';
  $self->{states}{'r1q2showlies'}{sub} = sub { $self->r1q2showlies(@_) };
  $self->{states}{'r1q2showlies'}{trans}{wait} = 'r1q2showlies';
  $self->{states}{'r1q2showlies'}{trans}{next} = 'r1q2showtruth';
  $self->{states}{'r1q2showtruth'}{sub} = sub { $self->r1q2showtruth(@_) };
  $self->{states}{'r1q2showtruth'}{trans}{wait} = 'r1q2showtruth';
  $self->{states}{'r1q2showtruth'}{trans}{next} = 'r1q2reveallies';
  $self->{states}{'r1q2reveallies'}{sub} = sub { $self->r1q2reveallies(@_) };
  $self->{states}{'r1q2reveallies'}{trans}{wait} = 'r1q2reveallies';
  $self->{states}{'r1q2reveallies'}{trans}{next} = 'r1q2showscore';
  $self->{states}{'r1q2showscore'}{sub} = sub { $self->r1q2showscore(@_) };
  $self->{states}{'r1q2showscore'}{trans}{wait} = 'r1q2showscore';
  $self->{states}{'r1q2showscore'}{trans}{next} = 'round1q3';

  $self->{states}{'round1q3'}{sub} = sub { $self->round1q3(@_) };
  $self->{states}{'round1q3'}{trans}{next} = 'r1q3choosecategory';
  $self->{states}{'r1q3choosecategory'}{sub} = sub { $self->r1q3choosecategory(@_) };
  $self->{states}{'r1q3choosecategory'}{trans}{wait} = 'r1q3choosecategory';
  $self->{states}{'r1q3choosecategory'}{trans}{next} = 'r1q3showquestion';
  $self->{states}{'r1q3showquestion'}{sub} = sub { $self->r1q3showquestion(@_) };
  $self->{states}{'r1q3showquestion'}{trans}{wait} = 'r1q3showquestion';
  $self->{states}{'r1q3showquestion'}{trans}{next} = 'r1q3getlies';
  $self->{states}{'r1q3getlies'}{sub} = sub { $self->r1q3getlies(@_) };
  $self->{states}{'r1q3getlies'}{trans}{skip} = 'round1q3';
  $self->{states}{'r1q3getlies'}{trans}{wait} = 'r1q3getlies';
  $self->{states}{'r1q3getlies'}{trans}{next} = 'r1q3findtruth';
  $self->{states}{'r1q3findtruth'}{sub} = sub { $self->r1q3findtruth(@_) };
  $self->{states}{'r1q3findtruth'}{trans}{wait} = 'r1q3findtruth';
  $self->{states}{'r1q3findtruth'}{trans}{next} = 'r1q3showlies';
  $self->{states}{'r1q3showlies'}{sub} = sub { $self->r1q3showlies(@_) };
  $self->{states}{'r1q3showlies'}{trans}{wait} = 'r1q3showlies';
  $self->{states}{'r1q3showlies'}{trans}{next} = 'r1q3showtruth';
  $self->{states}{'r1q3showtruth'}{sub} = sub { $self->r1q3showtruth(@_) };
  $self->{states}{'r1q3showtruth'}{trans}{wait} = 'r1q3showtruth';
  $self->{states}{'r1q3showtruth'}{trans}{next} = 'r1q3reveallies';
  $self->{states}{'r1q3reveallies'}{sub} = sub { $self->r1q3reveallies(@_) };
  $self->{states}{'r1q3reveallies'}{trans}{wait} = 'r1q3reveallies';
  $self->{states}{'r1q3reveallies'}{trans}{next} = 'r1q3showscore';
  $self->{states}{'r1q3showscore'}{sub} = sub { $self->r1q3showscore(@_) };
  $self->{states}{'r1q3showscore'}{trans}{wait} = 'r1q3showscore';
  $self->{states}{'r1q3showscore'}{trans}{next} = 'round2';


  $self->{states}{'round2'}{sub} = sub { $self->round2(@_) };
  $self->{states}{'round2'}{trans}{next} = 'round2q1';

  $self->{states}{'round2q1'}{sub} = sub { $self->round2q1(@_) };
  $self->{states}{'round2q1'}{trans}{next} = 'r2q1choosecategory';
  $self->{states}{'r2q1choosecategory'}{sub} = sub { $self->r2q1choosecategory(@_) };
  $self->{states}{'r2q1choosecategory'}{trans}{wait} = 'r2q1choosecategory';
  $self->{states}{'r2q1choosecategory'}{trans}{next} = 'r2q1showquestion';
  $self->{states}{'r2q1showquestion'}{sub} = sub { $self->r2q1showquestion(@_) };
  $self->{states}{'r2q1showquestion'}{trans}{wait} = 'r2q1showquestion';
  $self->{states}{'r2q1showquestion'}{trans}{next} = 'r2q1getlies';
  $self->{states}{'r2q1getlies'}{sub} = sub { $self->r2q1getlies(@_) };
  $self->{states}{'r2q1getlies'}{trans}{skip} = 'round2q1';
  $self->{states}{'r2q1getlies'}{trans}{wait} = 'r2q1getlies';
  $self->{states}{'r2q1getlies'}{trans}{next} = 'r2q1findtruth';
  $self->{states}{'r2q1findtruth'}{sub} = sub { $self->r2q1findtruth(@_) };
  $self->{states}{'r2q1findtruth'}{trans}{wait} = 'r2q1findtruth';
  $self->{states}{'r2q1findtruth'}{trans}{next} = 'r2q1showlies';
  $self->{states}{'r2q1showlies'}{sub} = sub { $self->r2q1showlies(@_) };
  $self->{states}{'r2q1showlies'}{trans}{wait} = 'r2q1showlies';
  $self->{states}{'r2q1showlies'}{trans}{next} = 'r2q1showtruth';
  $self->{states}{'r2q1showtruth'}{sub} = sub { $self->r2q1showtruth(@_) };
  $self->{states}{'r2q1showtruth'}{trans}{wait} = 'r2q1showtruth';
  $self->{states}{'r2q1showtruth'}{trans}{next} = 'r2q1reveallies';
  $self->{states}{'r2q1reveallies'}{sub} = sub { $self->r2q1reveallies(@_) };
  $self->{states}{'r2q1reveallies'}{trans}{wait} = 'r2q1reveallies';
  $self->{states}{'r2q1reveallies'}{trans}{next} = 'r2q1showscore';
  $self->{states}{'r2q1showscore'}{sub} = sub { $self->r2q1showscore(@_) };
  $self->{states}{'r2q1showscore'}{trans}{wait} = 'r2q1showscore';
  $self->{states}{'r2q1showscore'}{trans}{next} = 'round2q2';

  $self->{states}{'round2q2'}{sub} = sub { $self->round2q2(@_) };
  $self->{states}{'round2q2'}{trans}{next} = 'r2q2choosecategory';
  $self->{states}{'r2q2choosecategory'}{sub} = sub { $self->r2q2choosecategory(@_) };
  $self->{states}{'r2q2choosecategory'}{trans}{wait} = 'r2q2choosecategory';
  $self->{states}{'r2q2choosecategory'}{trans}{next} = 'r2q2showquestion';
  $self->{states}{'r2q2showquestion'}{sub} = sub { $self->r2q2showquestion(@_) };
  $self->{states}{'r2q2showquestion'}{trans}{wait} = 'r2q2showquestion';
  $self->{states}{'r2q2showquestion'}{trans}{next} = 'r2q2getlies';
  $self->{states}{'r2q2getlies'}{sub} = sub { $self->r2q2getlies(@_) };
  $self->{states}{'r2q2getlies'}{trans}{skip} = 'round2q2';
  $self->{states}{'r2q2getlies'}{trans}{wait} = 'r2q2getlies';
  $self->{states}{'r2q2getlies'}{trans}{next} = 'r2q2findtruth';
  $self->{states}{'r2q2findtruth'}{sub} = sub { $self->r2q2findtruth(@_) };
  $self->{states}{'r2q2findtruth'}{trans}{wait} = 'r2q2findtruth';
  $self->{states}{'r2q2findtruth'}{trans}{next} = 'r2q2showlies';
  $self->{states}{'r2q2showlies'}{sub} = sub { $self->r2q2showlies(@_) };
  $self->{states}{'r2q2showlies'}{trans}{wait} = 'r2q2showlies';
  $self->{states}{'r2q2showlies'}{trans}{next} = 'r2q2showtruth';
  $self->{states}{'r2q2showtruth'}{sub} = sub { $self->r2q2showtruth(@_) };
  $self->{states}{'r2q2showtruth'}{trans}{wait} = 'r2q2showtruth';
  $self->{states}{'r2q2showtruth'}{trans}{next} = 'r2q2reveallies';
  $self->{states}{'r2q2reveallies'}{sub} = sub { $self->r2q2reveallies(@_) };
  $self->{states}{'r2q2reveallies'}{trans}{wait} = 'r2q2reveallies';
  $self->{states}{'r2q2reveallies'}{trans}{next} = 'r2q2showscore';
  $self->{states}{'r2q2showscore'}{sub} = sub { $self->r2q2showscore(@_) };
  $self->{states}{'r2q2showscore'}{trans}{wait} = 'r2q2showscore';
  $self->{states}{'r2q2showscore'}{trans}{next} = 'round2q3';

  $self->{states}{'round2q3'}{sub} = sub { $self->round2q3(@_) };
  $self->{states}{'round2q3'}{trans}{next} = 'r2q3choosecategory';
  $self->{states}{'r2q3choosecategory'}{sub} = sub { $self->r2q3choosecategory(@_) };
  $self->{states}{'r2q3choosecategory'}{trans}{wait} = 'r2q3choosecategory';
  $self->{states}{'r2q3choosecategory'}{trans}{next} = 'r2q3showquestion';
  $self->{states}{'r2q3showquestion'}{sub} = sub { $self->r2q3showquestion(@_) };
  $self->{states}{'r2q3showquestion'}{trans}{wait} = 'r2q3showquestion';
  $self->{states}{'r2q3showquestion'}{trans}{next} = 'r2q3getlies';
  $self->{states}{'r2q3getlies'}{sub} = sub { $self->r2q3getlies(@_) };
  $self->{states}{'r2q3getlies'}{trans}{skip} = 'round2q3';
  $self->{states}{'r2q3getlies'}{trans}{wait} = 'r2q3getlies';
  $self->{states}{'r2q3getlies'}{trans}{next} = 'r2q3findtruth';
  $self->{states}{'r2q3findtruth'}{sub} = sub { $self->r2q3findtruth(@_) };
  $self->{states}{'r2q3findtruth'}{trans}{wait} = 'r2q3findtruth';
  $self->{states}{'r2q3findtruth'}{trans}{next} = 'r2q3showlies';
  $self->{states}{'r2q3showlies'}{sub} = sub { $self->r2q3showlies(@_) };
  $self->{states}{'r2q3showlies'}{trans}{wait} = 'r2q3showlies';
  $self->{states}{'r2q3showlies'}{trans}{next} = 'r2q3showtruth';
  $self->{states}{'r2q3showtruth'}{sub} = sub { $self->r2q3showtruth(@_) };
  $self->{states}{'r2q3showtruth'}{trans}{wait} = 'r2q3showtruth';
  $self->{states}{'r2q3showtruth'}{trans}{next} = 'r2q3reveallies';
  $self->{states}{'r2q3reveallies'}{sub} = sub { $self->r2q3reveallies(@_) };
  $self->{states}{'r2q3reveallies'}{trans}{wait} = 'r2q3reveallies';
  $self->{states}{'r2q3reveallies'}{trans}{next} = 'r2q3showscore';
  $self->{states}{'r2q3showscore'}{sub} = sub { $self->r2q3showscore(@_) };
  $self->{states}{'r2q3showscore'}{trans}{wait} = 'r2q3showscore';
  $self->{states}{'r2q3showscore'}{trans}{next} = 'round3';


  $self->{states}{'round3'}{sub} = sub { $self->round3(@_) };
  $self->{states}{'round3'}{trans}{next} = 'round3q1';

  $self->{states}{'round3q1'}{sub} = sub { $self->round3q1(@_) };
  $self->{states}{'round3q1'}{trans}{next} = 'r3q1choosecategory';
  $self->{states}{'r3q1choosecategory'}{sub} = sub { $self->r3q1choosecategory(@_) };
  $self->{states}{'r3q1choosecategory'}{trans}{wait} = 'r3q1choosecategory';
  $self->{states}{'r3q1choosecategory'}{trans}{next} = 'r3q1showquestion';
  $self->{states}{'r3q1showquestion'}{sub} = sub { $self->r3q1showquestion(@_) };
  $self->{states}{'r3q1showquestion'}{trans}{wait} = 'r3q1showquestion';
  $self->{states}{'r3q1showquestion'}{trans}{next} = 'r3q1getlies';
  $self->{states}{'r3q1getlies'}{sub} = sub { $self->r3q1getlies(@_) };
  $self->{states}{'r3q1getlies'}{trans}{skip} = 'round3q1';
  $self->{states}{'r3q1getlies'}{trans}{wait} = 'r3q1getlies';
  $self->{states}{'r3q1getlies'}{trans}{next} = 'r3q1findtruth';
  $self->{states}{'r3q1findtruth'}{sub} = sub { $self->r3q1findtruth(@_) };
  $self->{states}{'r3q1findtruth'}{trans}{wait} = 'r3q1findtruth';
  $self->{states}{'r3q1findtruth'}{trans}{next} = 'r3q1showlies';
  $self->{states}{'r3q1showlies'}{sub} = sub { $self->r3q1showlies(@_) };
  $self->{states}{'r3q1showlies'}{trans}{wait} = 'r3q1showlies';
  $self->{states}{'r3q1showlies'}{trans}{next} = 'r3q1showtruth';
  $self->{states}{'r3q1showtruth'}{sub} = sub { $self->r3q1showtruth(@_) };
  $self->{states}{'r3q1showtruth'}{trans}{wait} = 'r3q1showtruth';
  $self->{states}{'r3q1showtruth'}{trans}{next} = 'r3q1reveallies';
  $self->{states}{'r3q1reveallies'}{sub} = sub { $self->r3q1reveallies(@_) };
  $self->{states}{'r3q1reveallies'}{trans}{wait} = 'r3q1reveallies';
  $self->{states}{'r3q1reveallies'}{trans}{next} = 'r3q1showscore';
  $self->{states}{'r3q1showscore'}{sub} = sub { $self->r3q1showscore(@_) };
  $self->{states}{'r3q1showscore'}{trans}{wait} = 'r3q1showscore';
  $self->{states}{'r3q1showscore'}{trans}{next} = 'round3q2';

  $self->{states}{'round3q2'}{sub} = sub { $self->round3q2(@_) };
  $self->{states}{'round3q2'}{trans}{next} = 'r3q2choosecategory';
  $self->{states}{'r3q2choosecategory'}{sub} = sub { $self->r3q2choosecategory(@_) };
  $self->{states}{'r3q2choosecategory'}{trans}{wait} = 'r3q2choosecategory';
  $self->{states}{'r3q2choosecategory'}{trans}{next} = 'r3q2showquestion';
  $self->{states}{'r3q2showquestion'}{sub} = sub { $self->r3q2showquestion(@_) };
  $self->{states}{'r3q2showquestion'}{trans}{wait} = 'r3q2showquestion';
  $self->{states}{'r3q2showquestion'}{trans}{next} = 'r3q2getlies';
  $self->{states}{'r3q2getlies'}{sub} = sub { $self->r3q2getlies(@_) };
  $self->{states}{'r3q2getlies'}{trans}{skip} = 'round3q2';
  $self->{states}{'r3q2getlies'}{trans}{wait} = 'r3q2getlies';
  $self->{states}{'r3q2getlies'}{trans}{next} = 'r3q2findtruth';
  $self->{states}{'r3q2findtruth'}{sub} = sub { $self->r3q2findtruth(@_) };
  $self->{states}{'r3q2findtruth'}{trans}{wait} = 'r3q2findtruth';
  $self->{states}{'r3q2findtruth'}{trans}{next} = 'r3q2showlies';
  $self->{states}{'r3q2showlies'}{sub} = sub { $self->r3q2showlies(@_) };
  $self->{states}{'r3q2showlies'}{trans}{wait} = 'r3q2showlies';
  $self->{states}{'r3q2showlies'}{trans}{next} = 'r3q2showtruth';
  $self->{states}{'r3q2showtruth'}{sub} = sub { $self->r3q2showtruth(@_) };
  $self->{states}{'r3q2showtruth'}{trans}{wait} = 'r3q2showtruth';
  $self->{states}{'r3q2showtruth'}{trans}{next} = 'r3q2reveallies';
  $self->{states}{'r3q2reveallies'}{sub} = sub { $self->r3q2reveallies(@_) };
  $self->{states}{'r3q2reveallies'}{trans}{wait} = 'r3q2reveallies';
  $self->{states}{'r3q2reveallies'}{trans}{next} = 'r3q2showscore';
  $self->{states}{'r3q2showscore'}{sub} = sub { $self->r3q2showscore(@_) };
  $self->{states}{'r3q2showscore'}{trans}{wait} = 'r3q2showscore';
  $self->{states}{'r3q2showscore'}{trans}{next} = 'round3q3';

  $self->{states}{'round3q3'}{sub} = sub { $self->round3q3(@_) };
  $self->{states}{'round3q3'}{trans}{next} = 'r3q3choosecategory';
  $self->{states}{'r3q3choosecategory'}{sub} = sub { $self->r3q3choosecategory(@_) };
  $self->{states}{'r3q3choosecategory'}{trans}{wait} = 'r3q3choosecategory';
  $self->{states}{'r3q3choosecategory'}{trans}{next} = 'r3q3showquestion';
  $self->{states}{'r3q3showquestion'}{sub} = sub { $self->r3q3showquestion(@_) };
  $self->{states}{'r3q3showquestion'}{trans}{wait} = 'r3q3showquestion';
  $self->{states}{'r3q3showquestion'}{trans}{next} = 'r3q3getlies';
  $self->{states}{'r3q3getlies'}{sub} = sub { $self->r3q3getlies(@_) };
  $self->{states}{'r3q3getlies'}{trans}{skip} = 'round3q3';
  $self->{states}{'r3q3getlies'}{trans}{wait} = 'r3q3getlies';
  $self->{states}{'r3q3getlies'}{trans}{next} = 'r3q3findtruth';
  $self->{states}{'r3q3findtruth'}{sub} = sub { $self->r3q3findtruth(@_) };
  $self->{states}{'r3q3findtruth'}{trans}{wait} = 'r3q3findtruth';
  $self->{states}{'r3q3findtruth'}{trans}{next} = 'r3q3showlies';
  $self->{states}{'r3q3showlies'}{sub} = sub { $self->r3q3showlies(@_) };
  $self->{states}{'r3q3showlies'}{trans}{wait} = 'r3q3showlies';
  $self->{states}{'r3q3showlies'}{trans}{next} = 'r3q3showtruth';
  $self->{states}{'r3q3showtruth'}{sub} = sub { $self->r3q3showtruth(@_) };
  $self->{states}{'r3q3showtruth'}{trans}{wait} = 'r3q3showtruth';
  $self->{states}{'r3q3showtruth'}{trans}{next} = 'r3q3reveallies';
  $self->{states}{'r3q3reveallies'}{sub} = sub { $self->r3q3reveallies(@_) };
  $self->{states}{'r3q3reveallies'}{trans}{wait} = 'r3q3reveallies';
  $self->{states}{'r3q3reveallies'}{trans}{next} = 'r3q3showscore';
  $self->{states}{'r3q3showscore'}{sub} = sub { $self->r3q3showscore(@_) };
  $self->{states}{'r3q3showscore'}{trans}{wait} = 'r3q3showscore';
  $self->{states}{'r3q3showscore'}{trans}{next} = 'round4';


  $self->{states}{'round4'}{sub} = sub { $self->round4(@_) };
  $self->{states}{'round4'}{trans}{next} = 'round4q1';

  $self->{states}{'round4q1'}{sub} = sub { $self->round4q1(@_) };
  $self->{states}{'round4q1'}{trans}{next} = 'r4q1choosecategory';
  $self->{states}{'r4q1choosecategory'}{sub} = sub { $self->r4q1choosecategory(@_) };
  $self->{states}{'r4q1choosecategory'}{trans}{wait} = 'r4q1choosecategory';
  $self->{states}{'r4q1choosecategory'}{trans}{next} = 'r4q1showquestion';
  $self->{states}{'r4q1showquestion'}{sub} = sub { $self->r4q1showquestion(@_) };
  $self->{states}{'r4q1showquestion'}{trans}{wait} = 'r4q1showquestion';
  $self->{states}{'r4q1showquestion'}{trans}{next} = 'r4q1getlies';
  $self->{states}{'r4q1getlies'}{sub} = sub { $self->r4q1getlies(@_) };
  $self->{states}{'r4q1getlies'}{trans}{skip} = 'round4q1';
  $self->{states}{'r4q1getlies'}{trans}{wait} = 'r4q1getlies';
  $self->{states}{'r4q1getlies'}{trans}{next} = 'r4q1findtruth';
  $self->{states}{'r4q1findtruth'}{sub} = sub { $self->r4q1findtruth(@_) };
  $self->{states}{'r4q1findtruth'}{trans}{wait} = 'r4q1findtruth';
  $self->{states}{'r4q1findtruth'}{trans}{next} = 'r4q1showlies';
  $self->{states}{'r4q1showlies'}{sub} = sub { $self->r4q1showlies(@_) };
  $self->{states}{'r4q1showlies'}{trans}{wait} = 'r4q1showlies';
  $self->{states}{'r4q1showlies'}{trans}{next} = 'r4q1showtruth';
  $self->{states}{'r4q1showtruth'}{sub} = sub { $self->r4q1showtruth(@_) };
  $self->{states}{'r4q1showtruth'}{trans}{wait} = 'r4q1showtruth';
  $self->{states}{'r4q1showtruth'}{trans}{next} = 'r4q1reveallies';
  $self->{states}{'r4q1reveallies'}{sub} = sub { $self->r4q1reveallies(@_) };
  $self->{states}{'r4q1reveallies'}{trans}{wait} = 'r4q1reveallies';
  $self->{states}{'r4q1reveallies'}{trans}{next} = 'r4q1showscore';
  $self->{states}{'r4q1showscore'}{sub} = sub { $self->r4q1showscore(@_) };
  $self->{states}{'r4q1showscore'}{trans}{wait} = 'r4q1showscore';
  $self->{states}{'r4q1showscore'}{trans}{next} = 'gameover';


  $self->{states}{'gameover'}{sub} = sub { $self->gameover(@_) };
  $self->{states}{'gameover'}{trans}{next} = 'getplayers';
}

sub commify {
  my $self = shift;
  my $text = reverse $_[0];
  $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
  return scalar reverse $text;
}

sub normalize_text {
  my ($self, $text) = @_;

  $text=~ s/&/ AND /g;
  $text =~ s/^\s+|\s+$//g;
  $text =~ s/\s+/ /g;

  $text = lc substr($text, 0, 80);

  $text =~ s/\$\s+(\d)/\$$1/g;
  $text =~ s/\s*%$//;

  my @words = split / /, $text;
  my @result;

  foreach my $word (@words) {
    my $punct = $1 if $word =~ s/(\p{PosixPunct}+)$//;
    my $newword = $word;

    if ($word =~ m/^\d{4}$/ and $word >= 1700 and $word <= 2100) {
      $newword = year2en($word);
    } elsif ($word =~ m/^-?\d+$/) {
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
        $word = num2en($dollars);
        $newword = "$word " . (abs $dollars == 1 ? "dollar" : "dollars");
      }

      if (defined $cents) {
        $cents =~ s/^\.0*//;
        $cents = "$neg$cents" if defined $neg and not defined $dollars;
        $word = num2en($cents);
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

  $text = uc b2a join ' ', @result;

  $text =~ s/([A-Z])\./$1/g;
  $text =~ s/-/ /g;
  $text =~ s/["'?!]//g;

  return substr $text, 0, 80;
}

sub validate_lie {
  my ($self, $truth, $lie) = @_;

  my %truth_words = @{stem map { $_ => 1 } grep { /^\w+$/ and not exists $self->{stopwords}{lc $_} } split /\b/, $truth};
  my $truth_word_count = keys %truth_words;

  my %lie_words = @{stem map { $_ => 1 } grep { /^\w+$/ and not exists $self->{stopwords}{lc $_} } split /\b/, $lie};
  my $lie_word_count = keys %lie_words;

  my $count = 0;
  foreach my $word (keys %truth_words) {
    if (exists $lie_words{$word}) {
      $count++;
    }
  }

  if ($count == $truth_word_count) {
    return 0;
  }

  $count = 0;
  foreach my $word (keys %lie_words) {
    if (exists $truth_words{$word}) {
      $count++;
    }
  }

  if ($count >= 2 and $count == $lie_word_count) {
    return 0;
  }

  my $stripped_truth = $truth;
  $stripped_truth =~ s/(?:\s|\p{PosixPunct})+//g;
  my $stripped_lie = $lie;
  $stripped_lie =~ s/(?:\s|\p{PosixPunct})+//g;

  if ($stripped_truth eq $stripped_lie) {
    return 0;
  }

  return 1;
}

# generic state subroutines

sub choosecategory {
  my ($self, $state) = @_;

  if ($state->{init}) {
    delete $state->{current_category};
    $state->{current_player}++;

    if ($state->{current_player} >= @{$state->{players}}) {
      $state->{current_player} = 0;
    }

    my @choices;
    my @categories = keys %{$self->{categories}};

    my $no_infinite_loops = 0;
    while (1) {
      my $cat = $categories[rand @categories];

      my $count = keys %{$self->{categories}{$cat}};
      $self->{pbot}->{logger}->log("random cat: [$cat] $count questions\n");

      if (not grep { $_ eq $cat } @choices) {
        push @choices, $cat;
      }

      last if @choices == 8;
      last if ++$no_infinite_loops > 200;
    }

    $state->{categories_text} = '';
    my $i = 1;
    my $comma = '';
    foreach my $choice (@choices) {
      my $count = keys %{$self->{categories}{$choice}};
      $state->{categories_text} .= "$comma$i) " . $choice;
      $i++;
      $comma = "; ";
    }

    $state->{category_options} = \@choices;
    delete $state->{init};
  }

  if (exists $state->{current_category} or not @{$state->{players}}) {
    return 'next';
  }

  my $tock;
  if ($state->{first_tock}) {
    $tock = 3;
  } else {
    $tock = 15;
  }

  if ($state->{ticks} % $tock == 0) {
    delete $state->{first_tock};

    if (exists $state->{random_category}) {
      delete $state->{random_category};
      my $category = $state->{category_options}->[rand @{$state->{category_options}}];
      $self->send_message($self->{channel}, "$color{bold}Category: $category!$color{reset}");
      $state->{current_category} = $category;
      return 'next';
    }


    if (++$state->{counter} > $state->{max_count}) {
      $state->{players}->[$state->{current_player}]->{missedinputs}++;
      my $name = $state->{players}->[$state->{current_player}]->{name};
      my $category = $state->{category_options}->[rand @{$state->{category_options}}];
      $self->send_message($self->{channel}, "$color{bold}$name took too long to choose. Randomly choosing: $category!$color{reset}");
      $state->{current_category} = $category;
      return 'next';
    }

    my $name = $state->{players}->[$state->{current_player}]->{name};
    my $red = $state->{counter} == $state->{max_count} ? $color{red} : '';
    $self->send_message($self->{channel}, "$name: $red$color{bold}$state->{counter}/$state->{max_count} Choose a category via `/msg me c <number>`:$color{reset}");
    $self->send_message($self->{channel}, "$color{bold}$state->{categories_text}$color{reset}");
    return 'wait';
  }

  if (exists $state->{current_category}) {
    return 'next';
  } else {
    return 'wait';
  }
}

sub getnewquestion {
  my ($self, $state) = @_;

  if ($state->{ticks} % 3 == 0) {
    my @questions = keys %{$self->{categories}{$state->{current_category}}};
    $self->{pbot}->{logger}->log("current cat: $state->{current_category}: " . (scalar @questions) . " total questions\n");
    $state->{current_question} = $self->{categories}{$state->{current_category}}{$questions[rand @questions]};

    $state->{current_question}->{answer} = $self->normalize_text($state->{current_question}->{answer});

    my @alts = map { $self->normalize_text($_) } @{$state->{current_question}->{alternativeSpellings}};
    $state->{current_question}->{alternativeSpellings} = \@alts;

    foreach my $player (@{$state->{players}}) {
      delete $player->{lie};
      delete $player->{truth};
      delete $player->{deceived};
      delete $player->{skip};
    }
    return 'next';
  } else {
    return 'wait';
  }
}

sub showquestion {
  my ($self, $state) = @_;

  if (exists $state->{current_question}) {
    $self->send_message($self->{channel}, "$color{bold}$color{green}Current question:$color{reset}$color{bold} " . $self->commify($state->{current_question}->{id}) . ") $state->{current_question}->{question}$color{reset}");
  } else {
    $self->send_message($self->{channel}, "$color{bold}There is no current question.$color{reset}");
  }
}

sub getlies {
  my ($self, $state) = @_;

  my $tock;
  if ($state->{first_tock}) {
    $tock = 3;
  } else {
    $tock = 15;
  }

  my @nolies;
  foreach my $player (@{$state->{players}}) {
    if (not exists $player->{lie}) {
      push @nolies, $player->{name};
    }
  }

  return 'next' if not @nolies;

  my @skips;
  foreach my $player (@{$state->{players}}) {
    if ($player->{skip}) {
      push @skips, $player->{name};
    }
  }

  if (@skips) {
    my $needed = int (@{$state->{players}} / 2) + 1;
    $needed -= @skips;
    return 'skip' if $needed <= 0;
  }

  if ($state->{ticks} % $tock == 0) {
    delete $state->{first_tock};

    if (++$state->{counter} > $state->{max_count}) {
      my @missedinputs;
      foreach my $player (@{$state->{players}}) {
        if (not exists $player->{lie}) {
          push @missedinputs, $player->{name};
          $player->{missedinputs}++;
        }
      }

      if (@missedinputs) {
        my $missed = join ', ', @missedinputs;
        $self->send_message($self->{channel}, "$color{bold}$missed failed to submit a lie in time!$color{reset}");
      }
      return 'next';
    }

    my $players = join ', ', @nolies;
    my $red = $state->{counter} == $state->{max_count} ? $color{red} : '';
    $self->send_message($self->{channel}, "$players: $red$color{bold}$state->{counter}/$state->{max_count} Submit your lie now via `/msg me lie <your lie>`!$color{reset}");
  }

  return 'wait';
}

sub findtruth {
  my ($self, $state) = @_;

  my $tock;
  if ($state->{first_tock}) {
    $tock = 3;
  } else {
    $tock = 15;
  }

  my @notruth;
  foreach my $player (@{$state->{players}}) {
    if (not exists $player->{truth}) {
      push @notruth, $player->{name};
    }
  }

  return 'next' if not @notruth;

  if ($state->{ticks} % $tock == 0) {
    delete $state->{first_tock};
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
          my $random = rand @suggestions;
          my $suggestion = uc $suggestions[$random];
          push @choices, $suggestion if not grep { $_ eq $suggestion } @choices;
          splice @suggestions, $random, 1;
          next;
        }

        last;
      }

      splice @choices, rand @choices, 0, uc $state->{current_question}->{answer};
      $state->{correct_answer} = uc $state->{current_question}->{answer};

      my $i = 0;
      my $comma = '';
      my $text = '';
      foreach my $choice (@choices) {
        ++$i;
        $text .= "$comma$i) $choice";
        $comma = '; ';
      }

      $state->{current_choices_text} = $text;
      $state->{current_choices} = \@choices;
    }

    if (++$state->{counter} > $state->{max_count}) {
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
        $self->send_message($self->{channel}, "$color{bold}$missed failed to find the truth in time! They lose $state->{lie_points} points!$color{reset}");
      }
      return 'next';
    }

    my $players = join ', ', @notruth;
    my $red = $state->{counter} == $state->{max_count} ? $color{red} : '';
    $self->send_message($self->{channel}, "$players: $red$color{bold}$state->{counter}/$state->{max_count} Find the truth now via `/msg me c <number>`!$color{reset}");
    $self->send_message($self->{channel}, "$color{bold}$state->{current_choices_text}$color{reset}");
  }

  return 'wait';
}

sub showlies {
  my ($self, $state) = @_;

  my @liars;
  my $player;

  my $tock;
  if ($state->{first_tock}) {
    $tock = 3;
  } else {
    $tock = 6;
  }

  if ($state->{ticks} % $tock == 0) {
    delete $state->{first_tock};
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
        my $points = $state->{lie_points} * 0.25;
        $player->{score} -= $points;
        $self->send_message($self->{channel}, "$color{bold}$player->{name} fell for my lie: \"$player->{truth}\". -$points points!$color{reset}");
        $player->{deceived} = $player->{truth};
        if ($state->{current_lie_player} < @{$state->{players}}) {
          return 'wait';
        } else {
          return 'next';
        }
      }
    }

    if (@liars) {
      my $liars_text = '';
      my $liars_no_apostrophe = '';
      my $lie = $player->{truth};
      my $gains = @liars == 1 ? 'gains' : 'gain';
      my $comma = '';

      foreach my $liar (@liars) {
        $liars_text .= "$comma$liar->{name}'s";
        $liars_no_apostrophe .= "$comma$liar->{name}";
        $comma = ', ';
        $liar->{score} += $state->{lie_points};
      }

      $self->send_message($self->{channel}, "$color{bold}$player->{name} fell for $liars_text lie: \"$lie\". $liars_no_apostrophe $gains +$state->{lie_points} points!$color{reset}");
      $player->{deceived} = $lie;
    }

    return 'next' if $state->{current_lie_player} >= @{$state->{players}};
    return 'wait';
  }

  return 'wait';
}

sub showtruth {
  my ($self, $state) = @_;

  if ($state->{ticks} % 6 == 0) {
    my $players;
    my $comma = '';
    my $count = 0;
    foreach my $player (@{$state->{players}}) {
      next if exists $player->{deceived};
      if (exists $player->{truth} and $player->{truth} eq $state->{correct_answer}) {
        $count++;
        $players .= "$comma$player->{name}";
        $comma = ', ';
        $player->{score} += $state->{truth_points};
      }
    }

    if ($count) {
      $self->send_message($self->{channel}, "$color{bold}$players got the correct answer: \"$state->{correct_answer}\". +$state->{truth_points} points!$color{reset}");
    } else {
      $self->send_message($self->{channel}, "$color{bold}Nobody found the truth! The answer was: $state->{correct_answer}$color{reset}");
    }

    $self->add_new_suggestions($state);

    return 'next';
  } else {
    return 'wait';
  }
}

sub reveallies {
  my ($self, $state) = @_;

  if ($state->{ticks} % 3 == 0) {
    my $text = 'Revealing lies! ';
    my $comma = '';
    foreach my $player (@{$state->{players}}) {
      next if not exists $player->{lie};
      $text .= "$comma$player->{name}: $player->{lie}";
      $comma = '; ';
    }

    $self->send_message($self->{channel}, "$color{bold}$text$color{reset}");

    return 'next';
  } else {
    return 'wait';
  }
}

sub showscore {
  my ($self, $state) = @_;

  if ($state->{ticks} % 3 == 0) {
    my $text = '';
    my $comma = '';
    foreach my $player (sort { $b->{score} <=> $a->{score} } @{$state->{players}}) {
      $text .= "$comma$player->{name}: " . $self->commify($player->{score});
      $comma = '; ';
    }

    $text = "none" if not length $text;

    $self->send_message($self->{channel}, "$color{bold}$color{green}Scores: $color{reset}$color{bold}$text$color{reset}");
    return 'next';
  } else {
    return 'wait';
  }
}

# state subroutines

sub nogame {
  my ($self, $state) = @_;
  $state->{result} = 'nogame';
  return $state;
}

sub getplayers {
  my ($self, $state) = @_;

  my $players = $state->{players};

  my @names;
  my $unready = @$players ? @$players : 1;

  foreach my $player (@$players) {
    if (not $player->{ready}) {
      push @names, "$player->{name} $color{red}(not ready)$color{reset}$color{bold}";
    } else {
      $unready--;
      push @names, $player->{name};
    }
  }

  if (not $unready) {
    $self->send_message($self->{channel}, "$color{bold}All players ready!$color{reset}");
    $state->{result} = 'allready';
    return $state;
  }

  my $tock;
  if ($state->{first_tock}) {
    $tock = 2;
  } else {
    $tock = 90;
  }

  if ($state->{ticks} % $tock == 0) {
    delete $state->{first_tock};

    if (++$state->{counter} > 4) {
      $self->send_message($self->{channel}, "$color{bold}Not all players were ready in time. The game has been stopped.$color{reset}");
      $state->{result} = 'stop';
      $state->{players} = [];
      return $state;
    }

    $players = join ', ', @names;
    $players = 'none' if not @names;
    my $msg = "Waiting for more players or for all players to ready up. Current players: $players";
    $self->send_message($self->{channel}, "$color{bold}$msg$color{reset}");
  }

  $state->{result} = 'wait';
  return $state;
}

sub round1 {
  my ($self, $state) = @_;
  $state->{truth_points} = 500;
  $state->{lie_points} = 1000;
  $state->{my_lie_points} = $state->{lie_points} * 0.25;
  $state->{result} = 'next';
  return $state;
}

sub round1q1 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{counter} = 0;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}Round 1/3, question 1/3! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r1q1choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r1q1showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r1q1getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r1q1findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r1q1showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r1q1showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r1q1reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r1q1showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub round1q2 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{counter} = 0;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}Round 1/3, question 2/3! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r1q2choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r1q2showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r1q2getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r1q2findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r1q2showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r1q2showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r1q2reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r1q2showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub round1q3 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{counter} = 0;
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}Round 1/3, question 3/3! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r1q3choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r1q3showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r1q3getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r1q3findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r1q3showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r1q3showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r1q3reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r1q3showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub round2 {
  my ($self, $state) = @_;
  $state->{truth_points} = 750;
  $state->{lie_points} = 1500;
  $state->{my_lie_points} = $state->{lie_points} * 0.25;
  $state->{result} = 'next';
  return $state;
}

sub round2q1 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{counter} = 0;
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}Round 2/3, question 1/3! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r2q1choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r2q1showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r2q1getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r2q1findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r2q1showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r2q1showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r2q1reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r2q1showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub round2q2 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{counter} = 0;
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}Round 2/3, question 2/3! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r2q2choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r2q2showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r2q2getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r2q2findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r2q2showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r2q2showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r2q2reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r2q2showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub round2q3 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{counter} = 0;
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}Round 2/3, question 3/3! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r2q3choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r2q3showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r2q3getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r2q3findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r2q3showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r2q3showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r2q3reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r2q3showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub round3 {
  my ($self, $state) = @_;
  $state->{truth_points} = 1000;
  $state->{lie_points} = 2000;
  $state->{my_lie_points} = $state->{lie_points} * 0.25;
  $state->{result} = 'next';
  return $state;
}

sub round3q1 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{counter} = 0;
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}Round 3/3, question 1/3! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r3q1choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r3q1showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r3q1getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r3q1findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r3q1showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r3q1showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r3q1reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r3q1showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub round3q2 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{counter} = 0;
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}Round 3/3, question 2/3! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r3q2choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r3q2showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r3q2getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r3q2findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r3q2showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r3q2showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r3q2reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r3q2showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub round3q3 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{counter} = 0;
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}Round 3/3, question 3/3! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r3q3choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r3q3showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r3q3getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r3q3findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r3q3showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r3q3showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r3q3reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r3q3showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub round4 {
  my ($self, $state) = @_;
  $state->{truth_points} = 2000;
  $state->{lie_points} = 4000;
  $state->{my_lie_points} = $state->{lie_points} * 0.25;
  $state->{result} = 'next';
  return $state;
}

sub round4q1 {
  my ($self, $state) = @_;
  $state->{init} = 1;
  $state->{random_category} = 1;
  $state->{max_count} = $self->{choosecategory_max_count};
  $state->{counter} = 0;
  $state->{result} = 'next';
  $self->send_message($self->{channel}, "$color{bold}FINAL ROUND! FINAL QUESTION! $state->{lie_points} for each lie. $state->{truth_points} for the truth.$color{reset}");
  return $state;
}

sub r4q1choosecategory {
  my ($self, $state) = @_;
  $state->{result} = $self->choosecategory($state);
  return $state;
}

sub r4q1showquestion {
  my ($self, $state) = @_;
  my $result = $self->getnewquestion($state);

  if ($result eq 'next') {
    $self->showquestion($state);
    $state->{max_count} = $self->{picktruth_max_count};
    $state->{counter} = 0;
    $state->{init} = 1;
    $state->{current_lie_player} = 0;
    $state->{result} = 'next';
  } else {
    $state->{result} = 'wait';
  }
  return $state;
}

sub r4q1getlies {
  my ($self, $state) = @_;
  $state->{result} = $self->getlies($state);

  if ($state->{result} eq 'next') {
    $state->{counter} = 0;
    $state->{init} = 1;
  }

  return $state;
}

sub r4q1findtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->findtruth($state);
  return $state;
}

sub r4q1showlies {
  my ($self, $state) = @_;
  $state->{result} = $self->showlies($state);
  return $state;
}

sub r4q1showtruth {
  my ($self, $state) = @_;
  $state->{result} = $self->showtruth($state);
  return $state;
}

sub r4q1reveallies {
  my ($self, $state) = @_;
  $state->{result} = $self->reveallies($state);
  return $state;
}

sub r4q1showscore {
  my ($self, $state) = @_;
  $state->{result} = $self->showscore($state);
  return $state;
}

sub gameover {
  my ($self, $state) = @_;

  $self->send_message($self->{channel}, "$color{bold}Game over!$color{reset}");

  my $players = $state->{players};
  foreach my $player (@$players) {
    $player->{ready} = 0;
    $player->{missedinputs} = 0;
  }

  $state->{counter} = 0;

  $state->{result} = 'next';
  return $state;
}

1;
