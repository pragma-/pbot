#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Plugins::Spinach::Statskeeper;

use warnings;
use strict;

use DBI;
use Carp qw(shortmess);

my $debug = 0;

sub new {
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{filename} = $conf{filename} // 'stats.sqlite';
}

sub begin {
  my $self = shift;

  print STDERR "Opening stats SQLite database: $self->{filename}\n" if $debug;

  $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", { RaiseError => 1, PrintError => 0 }) or die $DBI::errstr;

  eval {
    $self->{dbh}->do(<< 'SQL');
CREATE TABLE IF NOT EXISTS Stats (
   id                                    INTEGER PRIMARY KEY,
   nick                                  TEXT NOT NULL COLLATE NOCASE,
   channel                               TEXT NOT NULL COLLATE NOCASE,
   high_score                            INTEGER DEFAULT 0,
   low_score                             INTEGER DEFAULT 0,
   avg_score                             INTEGER DEFAULT 0,
   times_first                           INTEGER DEFAULT 0,
   times_second                          INTEGER DEFAULT 0,
   times_third                           INTEGER DEFAULT 0,
   good_lies                             INTEGER DEFAULT 0,
   players_deceived                      INTEGER DEFAULT 0,
   questions_played                      INTEGER DEFAULT 0,
   games_played                          INTEGER DEFAULT 0,
   good_guesses                          INTEGER DEFAULT 0,
   bad_guesses                           INTEGER DEFAULT 0
)
SQL
  };

  print STDERR $@ if $@;
}

sub end {
  my $self = shift;

  print STDERR "Closing stats SQLite database\n" if $debug;

  if(exists $self->{dbh} and defined $self->{dbh}) {
    $self->{dbh}->disconnect();
    delete $self->{dbh};
  }
}

sub add_player {
  my ($self, $nick, $channel) = @_;

  my $id = eval {
    my $sth = $self->{dbh}->prepare('INSERT INTO Stats (nick, channel) VALUES (?, ?)');
    $sth->bind_param(1, $nick) ;
    $sth->bind_param(2, $channel) ;
    $sth->execute();
    return $self->{dbh}->sqlite_last_insert_rowid();
  };

  print STDERR $@ if $@;
  return $id;
}

sub get_player_id {
  my ($self, $nick, $channel, $dont_create_new) = @_;

  my $id = eval {
    my $sth = $self->{dbh}->prepare('SELECT id FROM Stats WHERE nick = ? AND channel = ?');
    $sth->bind_param(1, $nick);
    $sth->bind_param(2, $channel);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return $row->{id};
  };

  print STDERR $@ if $@;

  $id = $self->add_player($nick, $channel) if not defined $id and not $dont_create_new;
  return $id;
}

sub get_player_data {
  my ($self, $id, @columns) = @_;

  my $player_data = eval {
    my $sql = 'SELECT ';

    if(not @columns) {
      $sql .= '*';
    } else {
      my $comma = '';
      foreach my $column (@columns) {
        $sql .= "$comma$column";
        $comma = ', ';
      }
    }

    $sql .= ' FROM Stats WHERE id = ?';
    my $sth = $self->{dbh}->prepare($sql);
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchrow_hashref();
  };
  print STDERR $@ if $@;
  return $player_data;
}

sub update_player_data {
  my ($self, $id, $data) = @_;

  eval {
    my $sql = 'UPDATE Stats SET ';

    my $comma = '';
    foreach my $key (keys %$data) {
      $sql .= "$comma$key = ?";
      $comma = ', ';
    }

    $sql .= ' WHERE id = ?';

    my $sth = $self->{dbh}->prepare($sql);

    my $param = 1;
    foreach my $key (keys %$data) {
      $sth->bind_param($param++, $data->{$key});
    }

    $sth->bind_param($param, $id);
    $sth->execute();
  };
  print STDERR $@ if $@;
}

sub get_all_players {
  my ($self, $channel) = @_;

  my $players = eval {
    my $sth = $self->{dbh}->prepare('SELECT * FROM Stats WHERE channel = ?');
    $sth->bind_param(1, $channel);
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };
  print STDERR $@ if $@;
  return $players;
}

1;
