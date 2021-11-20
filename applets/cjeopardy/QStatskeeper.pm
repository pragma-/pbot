#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package QStatskeeper;

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
  $self->{filename} = $conf{filename} // 'qstats.sqlite';
}

sub begin {
  my $self = shift;

  print STDERR "Opening QStats SQLite database: $self->{filename}\n" if $debug;

  $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", { RaiseError => 1, PrintError => 0 }) or die $DBI::errstr;

  eval {
    $self->{dbh}->do(<< 'SQL');
CREATE TABLE IF NOT EXISTS QStats (
   id                    INTEGER PRIMARY KEY,
   asked_count           INTEGER DEFAULT 0,
   last_asked            NUMERIC DEFAULT 0,
   last_touched          NUMERIC DEFAULT 0,
   correct               INTEGER DEFAULT 0,
   last_correct_time     NUMERIC DEFAULT 0,
   last_correct_nick     TEXT COLLATE NOCASE DEFAULT NULL,
   wrong                 INTEGER DEFAULT 0,
   wrong_streak          INTEGER DEFAULT 0,
   highest_wrong_streak  INTEGER DEFAULT 0,
   hints                 INTEGER DEFAULT 0,
   quickest_answer_time  NUMERIC DEFAULT 0,
   quickest_answer_date  NUMERIC DEFAULT 0,
   quickest_answer_nick  TEXT COLLATE NOCASE DEFAULT NULL,
   longest_answer_time   NUMERIC DEFAULT 0,
   longest_answer_date   NUMERIC DEFAULT 0,
   longest_answer_nick   TEXT COLLATE NOCASE DEFAULT NULL,
   average_answer_time   NUMERIC DEFAULT 0
)
SQL

    $self->{dbh}->do(<< 'SQL');
CREATE TABLE IF NOT EXISTS WrongAnswers (
   id        INTEGER,
   answer    TEXT NOT NULL COLLATE NOCASE,
   nick      TEXT NOT NULL COLLATE NOCASE,
   count     INTEGER DEFAULT 1
)
SQL
  };

  print STDERR $@ if $@;
}

sub end {
  my $self = shift;

  print STDERR "Closing QStats SQLite database\n" if $debug;

  if(exists $self->{dbh} and defined $self->{dbh}) {
    $self->{dbh}->disconnect();
    delete $self->{dbh};
  }
}

sub find_question {
  my ($self, $id) = @_;

  my $exists = eval {
    my $sth = $self->{dbh}->prepare('SELECT 1 FROM QStats WHERE id = ?');
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchrow_hashref();
  };
  print STDERR $@ if $@;
  return $exists;
}

sub add_question {
  my ($self, $id) = @_;

  eval {
    my $sth = $self->{dbh}->prepare('INSERT OR IGNORE INTO QStats (id) VALUES (?)');
    $sth->bind_param(1, $id);
    $sth->execute();
  };

  print STDERR $@ if $@;
}

sub get_question_data {
  my ($self, $id, @columns) = @_;

  $self->add_question($id);

  my $qdata = eval {
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

    $sql .= ' FROM QStats WHERE id = ?';
    my $sth = $self->{dbh}->prepare($sql);
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchrow_hashref();
  };
  print STDERR $@ if $@;
  return $qdata;
}

sub update_question_data {
  my ($self, $id, $data) = @_;

  eval {
    my $sql = 'UPDATE QStats SET ';

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

sub get_wrong_answers {
  my ($self, $id) = @_;

  my $answers = eval {
    my $sth = $self->{dbh}->prepare("SELECT * FROM WrongAnswers WHERE id = ?");
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };
  print STDERR $@ if $@;
  return $answers;
}

sub add_wrong_answer {
  my ($self, $id, $answer, $nick) = @_;

  $answer = lc $answer;
  $answer =~ s/^\s+|\s+$//g;

  my $answers = $self->get_wrong_answers($id);

  my $found_ans;
  foreach my $ans (@$answers) {
    if ($ans->{answer} eq $answer) {
      $found_ans = $ans;
      last;
    }
  }

  if (not $found_ans) {
    eval {
      my $sth = $self->{dbh}->prepare("INSERT INTO WrongAnswers (id, answer, nick) VALUES (?, ?, ?)");
      $sth->bind_param(1, $id);
      $sth->bind_param(2, $answer);
      $sth->bind_param(3, $nick);
      $sth->execute();
    };
    print STDERR $@ if $@;
  } else {
    $found_ans->{count}++;
    eval {
      my $sth = $self->{dbh}->prepare("UPDATE WrongAnswers SET count = ?, nick = ? WHERE id = ? AND answer = ?");
      $sth->bind_param(1, $found_ans->{count});
      $sth->bind_param(2, $nick);
      $sth->bind_param(3, $id);
      $sth->bind_param(4, $answer);
      $sth->execute();
    };
    print STDERR $@ if $@;
  }
}

sub get_all_questions {
  my ($self) = @_;

  my $qdatas = eval {
    my $sth = $self->{dbh}->prepare('SELECT * FROM QStats');
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };
  print STDERR $@ if $@;
  return $qdatas;
}

1;
