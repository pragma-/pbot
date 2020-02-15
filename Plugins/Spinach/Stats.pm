#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Spinach::Stats;

use warnings;
use strict;

use feature 'unicode_strings';

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
    $self->{pbot}     = $conf{pbot}     // Carp::croak("Missing pbot reference to " . __FILE__);
    $self->{filename} = $conf{filename} // 'stats.sqlite';
}

sub begin {
    my $self = shift;

    $self->{pbot}->{logger}->log("Opening Spinach stats SQLite database: $self->{filename}\n");

    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", {RaiseError => 1, PrintError => 0}) or die $DBI::errstr;

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

    $self->{pbot}->{logger}->log("Error creating database: $@\n") if $@;
}

sub end {
    my $self = shift;

    if (exists $self->{dbh} and defined $self->{dbh}) {
        $self->{pbot}->{logger}->log("Closing stats SQLite database\n");
        $self->{dbh}->disconnect();
        delete $self->{dbh};
    }
}

sub add_player {
    my ($self, $id, $nick, $channel) = @_;

    eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Stats (id, nick, channel) VALUES (?, ?, ?)');
        $sth->execute($id, $nick, $channel);
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Spinach stats: failed to add new player ($id, $nick $channel): $@\n");
        return 0;
    }

    return $id;
}

sub get_player_id {
    my ($self, $nick, $channel, $dont_create_new) = @_;

    my ($account_id) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick);
    $account_id = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account_id);

    return undef if not $account_id;

    my $id = eval {
        my $sth = $self->{dbh}->prepare('SELECT id FROM Stats WHERE id = ? AND channel = ?');
        $sth->execute($account_id, $channel);
        my $row = $sth->fetchrow_hashref();
        return $row->{id};
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Spinach stats: failed to get player id: $@\n");
        return undef;
    }

    $id = $self->add_player($account_id, $nick, $channel) if not defined $id and not $dont_create_new;
    return $id;
}

sub get_player_data {
    my ($self, $id, @columns) = @_;

    return undef if not $id;

    my $player_data = eval {
        my $sql = 'SELECT ';

        if (not @columns) { $sql .= '*'; }
        else {
            my $comma = '';
            foreach my $column (@columns) {
                $sql .= "$comma$column";
                $comma = ', ';
            }
        }

        $sql .= ' FROM Stats WHERE id = ?';
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute($id);
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
        foreach my $key (keys %$data) { $sth->bind_param($param++, $data->{$key}); }

        $sth->bind_param($param, $id);
        $sth->execute();
    };
    print STDERR $@ if $@;
}

sub get_all_players {
    my ($self, $channel) = @_;

    my $players = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Stats WHERE channel = ?');
        $sth->execute($channel);
        return $sth->fetchall_arrayref({});
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return $players;
}

1;
