#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Spinach::Rank;

use warnings;
use strict;

use feature 'unicode_strings';

use FindBin;
use lib "$FindBin::RealBin/../../..";

use Plugins::Spinach::Stats;
use Math::Expression::Evaluator;

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
  $self->{channel} = $conf{channel} // Carp::croak("Missing channel reference to " . __FILE__);
  $self->{filename} = $conf{filename} // 'stats.sqlite';
  $self->{stats} = Plugins::Spinach::Stats->new(pbot => $self->{pbot}, filename => $self->{filename});
}

sub sort_generic {
  my ($self, $key) = @_;
  if ($self->{rank_direction} eq '+') {
    return $b->{$key} <=> $a->{$key};
  } else {
    return $a->{$key} <=> $b->{$key};
  }
}

sub print_generic {
  my ($self, $key, $player) = @_;
  return undef if $player->{games_played} == 0;
  return "$player->{nick}: $player->{$key}";
}

sub print_avg_score {
  my ($self, $player) = @_;
  return undef if $player->{games_played} == 0;
  my $result = int $player->{avg_score};
  return "$player->{nick}: $result";
}


sub sort_bad_lies {
  my ($self) = @_;
  if ($self->{rank_direction} eq '+') {
    return $b->{questions_played} - $b->{good_lies} <=> $a->{questions_played} - $a->{good_lies};
  } else {
    return $a->{questions_played} - $a->{good_lies} <=> $b->{questions_played} - $b->{good_lies};
  }
}

sub print_bad_lies {
  my ($self, $player) = @_;
  return undef if $player->{games_played} == 0;
  my $result = $player->{questions_played} - $player->{good_lies};
  return "$player->{nick}: $result";
}

sub sort_mentions {
  my ($self) = @_;
  if ($self->{rank_direction} eq '+') {
    return $b->{games_played} - $b->{times_first} - $b->{times_second} - $b->{times_third} <=>
      $a->{games_played} - $a->{times_first} - $a->{times_second} - $a->{times_third};
  } else {
    return $a->{games_played} - $a->{times_first} - $a->{times_second} - $a->{times_third} <=>
      $b->{games_played} - $b->{times_first} - $b->{times_second} - $b->{times_third};
  }
}

sub print_mentions {
  my ($self, $player) = @_;
  return undef if $player->{games_played} == 0;
  my $result = $player->{games_played} - $player->{times_first} - $player->{times_second} - $player->{times_third};
  return "$player->{nick}: $result";
}

sub sort_expr {
  my ($self) = @_;

  my $result = eval {
    my $result_a = $self->{expr}->val({
        highscore   => $a->{high_score},
        lowscore    => $a->{low_score},
        avgscore    => $a->{avg_score},
        goodlies    => $a->{good_lies},
        badlies     => $a->{questions_played} - $a->{good_lies},
        first       => $a->{times_first},
        second      => $a->{times_second},
        third       => $a->{times_third},
        mentions    => $a->{games_played} - $a->{times_first} - $a->{times_second} - $a->{times_third},
        games       => $a->{games_played},
        questions   => $a->{questions_played},
        goodguesses => $a->{good_guesses},
        badguesses  => $a->{bad_guesses},
        deceptions  => $a->{players_deceived}
      });

    my $result_b = $self->{expr}->val({
        highscore   => $b->{high_score},
        lowscore    => $b->{low_score},
        avgscore    => $b->{avg_score},
        goodlies    => $b->{good_lies},
        badlies     => $b->{questions_played} - $b->{good_lies},
        first       => $b->{times_first},
        second      => $b->{times_second},
        third       => $b->{times_third},
        mentions    => $b->{games_played} - $b->{times_first} - $b->{times_second} - $b->{times_third},
        games       => $b->{games_played},
        questions   => $b->{questions_played},
        goodguesses => $b->{good_guesses},
        badguesses  => $b->{bad_guesses},
        deceptions  => $b->{players_deceived}
      });

    if ($self->{rank_direction} eq '+') {
      return $result_b <=> $result_a;
    } else {
      return $result_a <=> $result_b;
    }
  };

  if ($@) {
    $self->{pbot}->{logger}->log("expr sort error: $@\n");
    return 0;
  }

  return $result;
}

sub print_expr {
  my ($self, $player) = @_;

  return undef if $player->{games_played} == 0;

  my $result = eval {
    $self->{expr}->val({
        highscore   => $player->{high_score},
        lowscore    => $player->{low_score},
        avgscore    => $player->{avg_score},
        goodlies    => $player->{good_lies},
        badlies     => $player->{questions_played} - $player->{good_lies},
        first       => $player->{times_first},
        second      => $player->{times_second},
        third       => $player->{times_third},
        mentions    => $player->{games_played} - $player->{times_first} - $player->{times_second} - $player->{times_third},
        games       => $player->{games_played},
        questions   => $player->{questions_played},
        goodguesses => $player->{good_guesses},
        badguesses  => $player->{bad_guesses},
        deceptions  => $player->{players_deceived}
      });
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Error in expr print: $@\n");
    return undef;
  }

  return "$player->{nick}: $result";
}

sub rank {
  my ($self, $arguments) = @_;

  my %ranks = (
    highscore     => { sort => sub { $self->sort_generic('high_score', @_) },        print => sub { $self->print_generic('high_score', @_) },       title => 'high score' },
    lowscore      => { sort => sub { $self->sort_generic('low_score', @_) },         print => sub { $self->print_generic('low_score', @_) },        title => 'low score' },
    avgscore      => { sort => sub { $self->sort_generic('avg_score', @_) },         print => sub { $self->print_avg_score(@_) },                   title => 'average score' },
    goodlies      => { sort => sub { $self->sort_generic('good_lies', @_) },         print => sub { $self->print_generic('good_lies', @_) },        title => 'good lies' },
    badlies       => { sort => sub { $self->sort_bad_lies(@_) },                     print => sub { $self->print_bad_lies(@_) },                    title => 'bad lies' },
    first         => { sort => sub { $self->sort_generic('times_first', @_) },       print => sub { $self->print_generic('times_first', @_) },      title => 'first place' },
    second        => { sort => sub { $self->sort_generic('times_second', @_) },      print => sub { $self->print_generic('times_second', @_) },     title => 'second place' },
    third         => { sort => sub { $self->sort_generic('times_third', @_) },       print => sub { $self->print_generic('times_third', @_) },      title => 'third place' },
    mentions      => { sort => sub { $self->sort_mentions(@_) },                     print => sub { $self->print_mentions(@_) },                    title => 'mentions' },
    games         => { sort => sub { $self->sort_generic('games_played', @_) },      print => sub { $self->print_generic('games_played', @_) },     title => 'games played' },
    questions     => { sort => sub { $self->sort_generic('questions_played', @_) },  print => sub { $self->print_generic('questions_played', @_) }, title => 'questions played' },
    goodguesses   => { sort => sub { $self->sort_generic('good_guesses', @_) },      print => sub { $self->print_generic('good_guesses', @_) },     title => 'good guesses' },
    badguesses    => { sort => sub { $self->sort_generic('bad_guesses', @_) },       print => sub { $self->print_generic('bad_guesses', @_) },      title => 'bad guesses' },
    deceptions    => { sort => sub { $self->sort_generic('players_deceived', @_) },  print => sub { $self->print_generic('players_deceived', @_) }, title => 'players deceived' },
    expr          => { sort => sub { $self->sort_expr(@_) },                         print => sub { $self->print_expr(@_) },                        title => 'expr' },
  );

  my @order = qw/highscore lowscore avgscore first second third mentions games questions goodlies badlies deceptions goodguesses badguesses expr/;

  if (not $arguments) {
    my $result = "Usage: rank [-]<keyword> [offset] or rank [-]<nick>; available keywords: ";
    $result .= join ', ', @order;
    $result .= ".\n";
    $result .= "Prefix with a dash to invert sort.\n";
    return $result;
  }

  $arguments = lc $arguments;

  if ($arguments =~ s/^([+-])//) {
    $self->{rank_direction} = $1;
  } else {
    $self->{rank_direction} = '+';
  }

  my $offset = 1;
  if ($arguments =~ s/\s+(\d+)$//) {
    $offset = $1;
  }

  my $opt_arg;
  if ($arguments =~ /^expr/) {
    if ($arguments =~ s/^expr (.+)$/expr/) {
      $opt_arg = $1;
    } else {
      return "Usage: spinach rank expr <expression>";
    }
  }

  if (not exists $ranks{$arguments}) {
    $self->{stats}->begin;
    my $player_id = $self->{stats}->get_player_id($arguments, $self->{channel}, 1);
    my $player_data = $self->{stats}->get_player_data($player_id);

    if (not defined $player_id) {
      $self->{stats}->end;
      return "I don't know anybody named $arguments.";
    }

    my $players = $self->{stats}->get_all_players($self->{channel});
    my @rankings;

    foreach my $key (@order) {
      next if $key eq 'expr';
      my $sort_method = $ranks{$key}->{sort};
      @$players = sort $sort_method @$players;

      my $rank = 0;
      my $stats;
      my $last_value = -1;
      foreach my $player (@$players) {
        $stats = $ranks{$key}->{print}->($player);

        if (defined $stats) {
          my ($value) = $stats =~ /[^:]+:\s+(.*)/;
          $rank++ if $value ne $last_value;
          $last_value = $value;
        } else {
          $rank++ if lc $player->{nick} eq $arguments;
        }

        last if lc $player->{nick} eq $arguments;
      }

      if (not $rank) {
        push @rankings, "$ranks{key}->{title}: N/A";
      } else {
        if (not $stats) {
          push @rankings, "$ranks{$key}->{title}: N/A";
        } else {
          $stats =~ s/[^:]+:\s+//;
          push @rankings, "$ranks{$key}->{title}: #$rank ($stats)";
        }
      }
    }

    my $result = "$player_data->{nick}'s rankings: ";
    $result .= join ', ', @rankings;
    $self->{stats}->end;
    return $result;
  }

  $self->{stats}->begin;
  my $players = $self->{stats}->get_all_players($self->{channel});

  if ($arguments eq 'expr') {
    $self->{expr} = eval { Math::Expression::Evaluator->new($opt_arg) };
    if ($@) {
      my $error = $@;
      $error =~ s/ at .*//ms;
      return "Bad expression: $error";
    }
    $self->{expr}->optimize;
  }

  my $sort_method = $ranks{$arguments}->{sort};
  @$players = sort $sort_method @$players;

  my @ranking;
  my $rank = 0;
  my $last_value = -1;
  foreach my $player (@$players) {
    my $entry = $ranks{$arguments}->{print}->($player);
    if (defined $entry) {
      my ($value) = $entry =~ /[^:]+:\s+(.*)/;
      $rank++ if $value ne $last_value;
      $last_value = $value;
      next if $rank < $offset;
      push @ranking, "#$rank $entry" if defined $entry;
      last if scalar @ranking >= 15;
    }
  }

  my $result;

  if (not scalar @ranking) {
    if ($offset > 1) {
      $result = "No rankings available for $self->{channel} at offset #$offset.\n";
    } else {
      $result = "No rankings available for $self->{channel} yet.\n";
    }
  } else {
    if ($arguments eq 'expr') {
      $result = "Rankings for $opt_arg: ";
    } else {
      $result = "Rankings for $ranks{$arguments}->{title}: ";
    }
    $result .= join ', ', @ranking;
  }

  $self->{stats}->end;
  return $result;
}

1;
