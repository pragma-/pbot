#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package QuoteDB;

use v5.26;
use warnings;

use feature 'signatures';
no warnings 'experimental::signatures';

use DBI;

my $debug = 10;

sub new($class, %conf) {
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize($self, %conf) {
  $self->{filename} = $conf{filename} // 'quotes.sqlite';
}

sub begin($self) {
  print STDERR "Opening quotes SQLite database: $self->{filename}\n" if $debug;

  $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", undef, undef,
      { AutoCommit => 0, AutoInactiveDestroy => 1, RaiseError => 1, PrintError => 0, sqlite_unicode => 1 }) or die $DBI::errstr;

  eval {
    $self->{dbh}->do(<< 'SQL');
CREATE TABLE IF NOT EXISTS Quotes (
   id                                    INTEGER PRIMARY KEY,
   text                                  TEXT NOT NULL COLLATE NOCASE,
   author                                TEXT NOT NULL COLLATE NOCASE
)
SQL

    $self->{dbh}->do(<< 'SQL');
CREATE TABLE IF NOT EXISTS Seen (
    channel                              TEXT NOT NULL COLLATE NOCASE,
    id                                   INTEGER
)
SQL
  };

  die $@ if $@;
}

sub end($self) {
  print STDERR "Closing quotes SQLite database\n" if $debug;

  if(exists $self->{dbh} and defined $self->{dbh}) {
    $self->{dbh}->commit();
    $self->{dbh}->disconnect();
    delete $self->{dbh};
  }
}

sub add_quote($self, $text, $author) {
  my $id = eval {
    my $sth = $self->{dbh}->prepare('INSERT INTO Quotes (text, author) VALUES (?, ?)');
    $sth->bind_param(1, $text) ;
    $sth->bind_param(2, $author) ;
    $sth->execute();
    return $self->{dbh}->sqlite_last_insert_rowid();
  };

  die $@ if $@;
  return $id;
}

sub get_quote($self, $id) {
    my $quote = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Quotes WHERE id == ?');
        $sth->bind_param(1, $id);
        $sth->execute();
        return $sth->fetchrow_hashref();
    };

    die $@ if $@;
    return $quote;
}

sub count_random_quote($self, $channel, $text, $author) {
    # convert from regex metachars to SQL LIKE metachars
    if (defined $text) {
        $text =~ s/\.?\*\??/%/g;
        $text =~ s/\./_/g;
    }

    my $total = eval {
        my $sql = 'SELECT COUNT(*) FROM Quotes';
        my @params;
        my $joiner = ' WHERE';

        if (defined $text) {
            $sql .= "$joiner text LIKE ?";
            push @params, '%' . $text . '%';
            $joiner = ' AND';
        }

        if (defined $author) {
            $sql .= "$joiner author LIKE ?";
            push @params, '%' . $author. '%';
            $joiner = ' AND';
        }

        my $sth = $self->{dbh}->prepare("$sql");
        $sth->execute(@params);
        return $sth->fetchrow_hashref();
    };

    die $@ if $@;

    my $remaining = eval {
        my $sql = 'SELECT COUNT(*) FROM Quotes';
        my @params;
        my $joiner = ' WHERE';

        if (defined $text) {
            $sql .= "$joiner text LIKE ?";
            push @params, '%' . $text . '%';
            $joiner = ' AND';
        }

        if (defined $author) {
            $sql .= "$joiner author LIKE ?";
            push @params, '%' . $author. '%';
            $joiner = ' AND';
        }

        my $sth = $self->{dbh}->prepare("$sql $joiner id NOT IN (SELECT id FROM Seen WHERE channel = ?)");
        $sth->execute(@params, $channel);
        return $sth->fetchrow_hashref();
    };

    die $@ if $@;
    return ($total, $remaining);
}

sub get_random_quote($self, $channel, $text, $author) {
    # convert from regex metachars to SQL LIKE metachars
    if (defined $text) {
        $text =~ s/\.?\*\??/%/g;
        $text =~ s/\./_/g;
    }

    my $quote = eval {
        my $sql = 'SELECT * FROM Quotes';
        my @params;
        my $joiner = ' WHERE';

        if (defined $text) {
            $sql .= "$joiner text LIKE ?";
            push @params, '%' . $text . '%';
            $joiner = ' AND';
        }

        if (defined $author) {
            $sql .= "$joiner author LIKE ?";
            push @params, '%' . $author. '%';
            $joiner = ' AND';
        }

        # search for a random unseen quote
        my $sth = $self->{dbh}->prepare("$sql $joiner id NOT IN (SELECT id FROM Seen WHERE channel = ?) ORDER BY RANDOM() LIMIT 1");
        $sth->execute(@params, $channel);
        my $quote = $sth->fetchrow_hashref();

        # no unseen quote found
        if (not defined $quote) {
            # remove queried quotes from Seen table
            if (not $self->remove_seen($channel, $sql, \@params)) {
                # no matching quotes in Seen table ergo no quote found
                return undef;
            }

            # try again to search for random unseen quote
            $sth->execute(@params, $channel);
            $quote = $sth->fetchrow_hashref();
        }

        # mark quote as seen if found
        if (defined $quote) {
            $self->add_seen($channel, $quote->{id});
        }

        return $quote;
    };

    die $@ if $@;
    return $quote;
}

sub remove_seen($self, $channel, $sql, $params) {
    $sql =~ s/^SELECT \*/SELECT id/;

    my $count = eval {
        my $sth = $self->{dbh}->prepare("DELETE FROM Seen WHERE channel = ? AND id IN ($sql)");
        $sth->execute($channel, @$params);
        return $sth->rows;
    };

    die $@ if $@;
    return $count;
}

sub add_seen($self, $channel, $id) {
    eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Seen VALUES (?, ?)');
        $sth->execute($channel, $id);
    };

    die $@ if $@;
}

sub get_all_quotes($self) {
    my $quotes = eval {
        my $sth = $self->{dbh}->prepare('SELECT * from Quotes');
        $sth->execute();
        return $sth->fetchall_arrayref({});
    };

    die $@ if $@;
    return $quotes;
}

sub delete_quote($self, $id) {
    eval {
        my $sth = $self->{dbh}->prepare('DELETE FROM Quotes WHERE id == ?');
        $sth->execute($id);

        $sth = $self->{dbh}->prepare('DELETE FROM Seen WHERE id == ?');
        $sth->execute($id);
    };

    die $@ if $@;
}

1;
