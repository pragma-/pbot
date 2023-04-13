# File: SQLite.pm
#
# Purpose: SQLite backend for storing and retreiving quotegrabs.

# SPDX-FileCopyrightText: 2021-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Quotegrabs::Storage::SQLite;

use PBot::Imports;

use DBI;
use Carp;

sub new($class, %conf) {
    my $self = bless {}, $class;
    $self->initialize(%conf);
    return $self;
}

sub initialize($self, %conf) {
    $self->{pbot}     = delete $conf{pbot} // Carp::croak("Missing pbot reference in " . __FILE__);
    $self->{filename} = delete $conf{filename};
}

sub begin($self) {
    $self->{pbot}->{logger}->log("Opening quotegrabs SQLite database: $self->{filename}\n");
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", {RaiseError => 1, PrintError => 0, sqlite_unicode => 1}) or die $DBI::errstr;

    eval {
        $self->{dbh}->do(<< 'SQL');
CREATE TABLE IF NOT EXISTS Quotegrabs (
  id         INTEGER PRIMARY KEY,
  nick       TEXT,
  channel    TEXT,
  grabbed_by TEXT,
  text       TEXT,
  timestamp  NUMERIC
)
SQL

        $self->{dbh}->do('CREATE TABLE IF NOT EXISTS Seen (id INTEGER UNIQUE)');
    };

    $self->{pbot}->{logger}->log($@) if $@;
}

sub end($self) {
    if (exists $self->{dbh} and defined $self->{dbh}) {
        $self->{pbot}->{logger}->log("Closing quotegrabs SQLite database\n");
        $self->{dbh}->disconnect();
        delete $self->{dbh};
    }
}

sub add_quotegrab($self, $quotegrab) {
    my $id = eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Quotegrabs VALUES (?, ?, ?, ?, ?, ?)');
        $sth->execute(
            undef,
            $quotegrab->{nick},
            $quotegrab->{channel},
            $quotegrab->{grabbed_by},
            $quotegrab->{text},
            $quotegrab->{timestamp},
        );
        return $self->{dbh}->sqlite_last_insert_rowid();
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return $id;
}

sub get_quotegrab($self, $id) {
    my $quotegrab = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Quotegrabs WHERE id == ?');
        $sth->bind_param(1, $id);
        $sth->execute();
        return $sth->fetchrow_hashref();
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return $quotegrab;
}

sub get_random_quotegrab($self, $nick, $channel, $text) {
    # convert from regex metachars to SQL LIKE metachars
    if (defined $nick) {
        $nick =~ s/\.?\*\??/%/g;
        $nick =~ s/\./_/g;
    }

    if (defined $channel) {
        $channel =~ s/\.?\*\??/%/g;
        $channel =~ s/\./_/g;
    }

    if (defined $text) {
        $text =~ s/\.?\*\??/%/g;
        $text =~ s/\./_/g;
    }

    my $quotegrab = eval {
        my $sql = 'SELECT * FROM Quotegrabs';
        my @params;
        my $joiner = ' WHERE';

        # multi-grabs have the nick separated by +'s so we must test for
        # nick, nick+*, *+nick, and *+nick+* to match each of these cases
        if (defined $nick) {
            $sql .= "$joiner (nick LIKE ? OR nick LIKE ? OR nick LIKE ? OR nick LIKE ?)";
            push @params,        $nick;
            push @params,        $nick . '+%';
            push @params, '%+' . $nick;
            push @params, '%+' . $nick . '+%';
            $joiner = ' AND';
        }

        if (defined $channel) {
            $sql .= "$joiner channel LIKE ?";
            push @params, $channel;
            $joiner = ' AND';
        }

        if (defined $text) {
            $sql .= "$joiner text LIKE ?";
            push @params, '%' . $text . '%';
            $joiner = ' AND';
        }
        # search for a random unseen quotegrab
        my $sth = $self->{dbh}->prepare("$sql $joiner id NOT IN Seen ORDER BY RANDOM() LIMIT 1");
        $sth->execute(@params);
        my $quotegrab = $sth->fetchrow_hashref();

        # no unseen quote found
        if (not defined $quotegrab) {
            # remove queried quotes from Seen table
            if (not $self->remove_seen($sql, \@params)) {
                # no matching quotes in Seen table ergo no quote found
                return undef;
            }

            # try again to search for random unseen quotegrab
            $sth->execute(@params);
            $quotegrab = $sth->fetchrow_hashref();
        }

        # mark quote as seen if found
        if (defined $quotegrab) {
            $self->add_seen($quotegrab->{id});
        }

        return $quotegrab;
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return $quotegrab;
}

sub remove_seen($self, $sql, $params) {
    $sql =~ s/^SELECT \*/SELECT id/;

    my $count = eval {
        my $sth = $self->{dbh}->prepare("DELETE FROM Seen WHERE id IN ($sql)");
        $sth->execute(@$params);
        return $sth->rows;
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return $count;
}

sub add_seen($self, $id) {
    eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Seen VALUES (?)');
        $sth->execute($id);
    };

    $self->{pbot}->{logger}->log($@) if $@;
}

sub get_all_quotegrabs($self) {
    my $quotegrabs = eval {
        my $sth = $self->{dbh}->prepare('SELECT * from Quotegrabs');
        $sth->execute();
        return $sth->fetchall_arrayref({});
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return $quotegrabs;
}

sub delete_quotegrab($self, $id) {
    eval {
        my $sth = $self->{dbh}->prepare('DELETE FROM Quotegrabs WHERE id == ?');
        $sth->execute($id);

        $sth = $self->{dbh}->prepare('DELETE FROM Seen WHERE id == ?');
        $sth->execute($id);
    };

    $self->{pbot}->{logger}->log($@) if $@;
}

1;
