#!/usr/bin/env perl

package Scorekeeper;

use warnings;
use strict;

use DBI;
use Carp qw(shortmess);

sub new {
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{filename} = $conf{filename} // 'scores.sqlite';
}

sub begin {
  my $self = shift;

  print STDERR "Opening scores SQLite database: $self->{filename}\n";

  $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", { RaiseError => 1, PrintError => 0 }) or die $DBI::errstr;

  eval {
    $self->{dbh}->do(<< 'SQL');
CREATE TABLE IF NOT EXISTS Scores (
   id                               INTEGER PRIMARY KEY,
   nick                             TEXT NOT NULL,
   channel                          TEXT NOT NULL,
   correct_answers                  INTEGER DEFAULT 0,
   wrong_answers                    INTEGER DEFAULT 0,
   lifetime_correct_answers         INTEGER DEFAULT 0,
   lifetime_wrong_answers           INTEGER DEFAULT 0,
   correct_streak                   INTEGER DEFAULT 0,
   wrong_streak                     INTEGER DEFAULT 0,
   lifetime_highest_correct_streak  INTEGER DEFAULT 0,
   lifetime_highest_wrong_streak    INTEGER DEFAULT 0,
   highest_correct_streak           INTEGER DEFAULT 0,
   highest_wrong_streak             INTEGER DEFAULT 0,
   hints                            INTEGER DEFAULT 0,
   lifetime_hints                   INTEGER DEFAULT 0,
   last_wrong_timestamp             NUMERIC DEFAULT 0,
   last_correct_timestamp           NUMERIC DEFAULT 0,
   quickest_correct                 NUMERIC DEFAULT 0
)
SQL
  };

  print STDERR $@ if $@;
}

sub end {
  my $self = shift;

  print STDERR "Closing scores SQLite database\n";

  if(exists $self->{dbh} and defined $self->{dbh}) {
    $self->{dbh}->disconnect();
    delete $self->{dbh};
  }
}

sub add_player {
  my ($self, $nick, $channel) = @_;

  my $id = eval {
    my $sth = $self->{dbh}->prepare('INSERT INTO Scores (nick, channel) VALUES (?, ?)');
    $sth->bind_param(1, $nick) ;
    $sth->bind_param(2, $channel) ;
    $sth->execute();
    return $self->{dbh}->sqlite_last_insert_rowid();
  };

  print STDERR $@ if $@;
  return $id;
}

sub get_player_id {
  my ($self, $nick, $channel) = @_;

  my $id = eval {
    my $sth = $self->{dbh}->prepare('SELECT id FROM Scores WHERE nick = ? AND channel = ?');
    $sth->bind_param(1, $nick);
    $sth->bind_param(2, $channel);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return $row->{id};
  };

  print STDERR $@ if $@;

  $id = $self->add_player($nick, $channel) if not defined $id;
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

    $sql .= ' FROM Scores WHERE id = ?';
    my $sth = $self->{dbh}->prepare($sql);
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchrow_hashref();
  };
  return $player_data;
}

sub update_player_data {
  my ($self, $id, $data) = @_;

  eval {
    my $sql = 'UPDATE Scores SET ';

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
}

1;
