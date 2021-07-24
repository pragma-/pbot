# File: DualIndexSQLiteObject.pm
#
# Purpose: Provides a dual-indexed SQLite object with an abstracted API that includes
# setting and deleting values, caching, displaying nearest matches, etc. Designed to
# be as compatible as possible with DualIndexHashObject; e.g. get_keys, get_data, etc.
#
# This class is ideal if you don't want to store the data in working memory. However,
# data is temporarily cached in working memory for lightning fast performance. The TTL
# value can be adjusted via the `dualindexsqliteobject.cache_timeout` registry entry.
#
# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Storage::DualIndexSQLiteObject;

use PBot::Imports;

use PBot::Core::Utils::SQLiteLogger;
use PBot::Core::Utils::SQLiteLoggerLayer;

use DBI;
use Text::Levenshtein qw(fastdistance);

sub new {
    my ($class, %args) = @_;
    Carp::croak("Missing pbot reference to " . __FILE__) unless exists $args{pbot};
    my $self = bless {}, $class;
    $self->{pbot} = delete $args{pbot};
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{name}     = $conf{name}     // 'Dual Index SQLite object';
    $self->{filename} = $conf{filename} // Carp::croak("Missing filename in " . __FILE__);

    $self->{dbh}   = undef;
    $self->{cache} = {};

    $self->{pbot}->{registry}->add_default('text', 'dualindexsqliteobject', "debug_$self->{name}", 0);
    $self->{pbot}->{registry}->add_trigger('dualindexsqliteobject', "debug_$self->{name}", sub { $self->sqlite_debug_trigger(@_) });

    $self->{pbot}->{atexit}->register(sub { $self->end });

    $self->begin;
}

sub sqlite_debug_trigger {
    my ($self, $section, $item, $newvalue) = @_;
    $self->{dbh}->trace($self->{dbh}->parse_trace_flags("SQL|$newvalue")) if defined $self->{dbh};
}

sub begin {
    my ($self) = @_;

    $self->{pbot}->{logger}->log("Opening $self->{name} database ($self->{filename})\n");

    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", undef, undef,
        { AutoCommit => 0, RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1, sqlite_unicode => 1 }
    ) or die $DBI::errstr;

    eval {
        my $sqlite_debug = $self->{pbot}->{registry}->get_value('dualindexsqliteobject', "debug_$self->{name}");
        open $self->{trace_layer}, '>:via(PBot::Core::Utils::SQLiteLoggerLayer)', PBot::Core::Utils::SQLiteLogger->new(pbot => $self->{pbot});
        $self->{dbh}->trace($self->{dbh}->parse_trace_flags("SQL|$sqlite_debug"), $self->{trace_layer});
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error initializing $self->{name} database: $@\n");
    }
}

sub end {
    my ($self) = @_;

    $self->{pbot}->{logger}->log("Closing $self->{name} database ($self->{filename})\n");

    if (defined $self->{dbh}) {
        $self->{dbh}->disconnect;
        close $self->{trace_layer};
        $self->{dbh} = undef;
    }

    $self->{pbot}->{event_queue}->dequeue("Trim $self->{name} cache");
}

sub load  {
    my ($self) = @_;
    $self->create_database;
    $self->create_cache;
}

sub save {
    my ($self) = @_;
    return if not $self->{dbh};

    eval { $self->{dbh}->commit };

    if ($@) {
        $self->{pbot}->{logger}->log("Error saving $self->{name}: $@");
    }
}

sub create_database {
    my ($self) = @_;

    eval {
        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Stuff (
    index1    TEXT COLLATE NOCASE,
    index2    TEXT COLLATE NOCASE
)
SQL

        $self->{dbh}->do('CREATE INDEX IF NOT EXISTS idx1 ON Stuff (index1, index2)');
    };

    $self->{pbot}->{logger}->log("Error creating $self->{name} databse: $@") if $@;
}

sub create_cache {
    my ($self) = @_;

    $self->{cache} = {};

    my ($index1_count, $index2_count) = (0, 0);

    foreach my $index1 ($self->get_keys(undef, undef, 1)) {
        my $lc_index1 = lc $index1;
        $index1_count++;

        foreach my $index2 ($self->get_keys($lc_index1, undef, 1)) {
            my $lc_index2 = lc $index2;
            $index2_count++;

            $self->{cache}->{$lc_index1}->{$lc_index2} = {};

            # _name contains original typographical case

            if ($index1 ne $lc_index1) {
                $self->{cache}->{$lc_index1}->{_name} = $index1;
            }

            if ($index2 ne $lc_index2) {
                $self->{cache}->{$lc_index1}->{$lc_index2}->{_name} = $index2;
            }
        }
    }

    $self->{pbot}->{logger}->log("Cached $index2_count $self->{name} objects in $index1_count groups.\n");
}

sub cache_remove {
    my ($self, $index1, $index2) = @_;

    if (not defined $index2) {
        # remove index1
        delete $self->{cache}->{$index1};
    } else {
        # remove index2
        delete $self->{cache}->{$index1}->{$index2};

        # remove index1 if it has no more keys left (aside from _name)
        if (not grep { $_ ne '_name' } keys %{$self->{cache}->{$index1}}) {
            delete $self->{cache}->{$index1};
        }
    }
}

sub enqueue_decache {
    my ($self, $index1, $index2) = @_;

    my $timeout = $self->{pbot}->{registry}->get_value('dualindexsqliteobject', 'cache_timeout') // 60 * 30;

    $self->{pbot}->{event_queue}->enqueue_event(
        sub {
            # save _name
            my $name = $self->{cache}->{$index1}->{$index2}->{_name};

            # clear cache
            $self->{cache}->{$index1}->{$index2} = {};

            # put _name back
            $self->{cache}->{$index1}->{$index2}->{_name} = $name if defined $name;
        }, $timeout, "Decache $self->{name} " . ($index1 eq '.*' ? 'global' : $index1) . ".$index2"
    );
}

sub create_metadata {
    my ($self, $columns) = @_;

    return if not $self->{dbh};

    $self->{columns} = $columns;

    eval {
        my %existing = ();
        foreach my $col (@{$self->{dbh}->selectall_arrayref("PRAGMA TABLE_INFO(Stuff)")}) {
            $existing{$col->[1]} = $col->[2];
        }

        foreach my $col (sort keys %$columns) {
            unless (exists $existing{$col}) {
                $self->{dbh}->do("ALTER TABLE Stuff ADD COLUMN \"$col\" $columns->{$col}");
            }
        }

        $self->{dbh}->commit;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error creating metadata for $self->{name}: $@");
        $self->{dbh}->rollback;
    }
}

sub levenshtein_matches {
    my ($self, $index1, $index2, $distance, $strictnamespace) = @_;

    $index1   //= '.*';
    $distance //= 0.60;

    my $output = 'none';

    if (not $index2) {
        my @matches;
        my $length_a = length $index1;

        foreach my $index (sort $self->get_keys) {
            my $distance_result = fastdistance($index1, $index);

            my $length_b = length $index;

            my $length = $length_a > $length_b ? $length_a : $length_b;

            if ($distance_result / $length < $distance) {
                my $name = $self->get_data($index, '_name');

                if ($name =~ / /) {
                    push @matches, "\"$name\"";
                } else {
                    push @matches, $name;
                }
            }
        }

        $output = join ', ', @matches;
    } else {
        if (not $self->exists($index1)) {
            return $output;
        }

        my %sections;
        my $section;
        my $length_a = length $index2;

        foreach my $i1 (sort $self->get_keys) {
            $section = $self->get_data($i1, '_name');
            $section = 'global' if $section eq '.*';

            if ($strictnamespace) {
                next unless $i1 eq '.*' or lc $i1 eq lc $index1;
            }

            foreach my $i2 (sort $self->get_keys($i1)) {
                my $distance_result = fastdistance($index2, $i2);

                my $length_b = length $i2;

                my $length = $length_a > $length_b ? $length_a : $length_b;

                if ($distance_result / $length < $distance) {
                    my $name = $self->get_data($i1, $i2, '_name');

                    if ($name =~ / /) {
                        push @{$sections{$section}}, "\"$name\"";
                    } else {
                        push @{$sections{$section}}, $name;
                    }
                }
            }
        }

        $output = '';

        foreach $section (sort keys %sections) {
            $output .= "[$section] ";
            $output .= join ', ', @{$sections{$section}};
            $output .= '; ';
        }

        $output =~ s/; $//;
    }

    $output =~ s/(.*), /$1 or /;
    return $output;
}

sub exists {
    my ($self, $index1, $index2, $data_index) = @_;
    return 0 if not defined $index1;
    $index1 = lc $index1;
    return 0 if not grep { $_ eq $index1 } $self->get_keys;
    return 1 if not defined $index2;
    $index2 = lc $index2;
    return 0 if not grep { $_ eq $index2 } $self->get_keys($index1);
    return 1 if not defined $data_index;
    return defined $self->get_data($index1, $index2, $data_index);
}

sub get_keys {
    my ($self, $index1, $index2, $nocache) = @_;

    my @keys;

    if (not defined $index1) {
        if (not $nocache) {
            return keys %{$self->{cache}};
        }

        @keys = eval {
            my $context = $self->{dbh}->selectall_arrayref('SELECT DISTINCT index1 FROM Stuff');

            if (@$context) {
                return map { $_->[0] } @$context;
            } else {
                return ();
            }
        };

        if ($@) {
            $self->{pbot}->{logger}->log($@);
            return undef;
        }

        return @keys;
    }

    $index1 = lc $index1;

    if (not defined $index2) {
        if (not $nocache) {
            return grep { $_ ne '_name' } keys %{$self->{cache}->{$index1}};
        }

        @keys = eval {
            my $sth = $self->{dbh}->prepare('SELECT index2 FROM Stuff WHERE index1 = ?');

            $sth->execute($index1);

            my $context = $sth->fetchall_arrayref;

            if (@$context) {
                return map { $_->[0] } @$context;
            } else {
                return ();
            }
        };

        if ($@) {
            $self->{pbot}->{logger}->log($@);
            return ();
        }

        return @keys;
    }

    $index2 = lc $index2;

    if (not $nocache) {
        @keys = grep { $_ ne '_name' } keys %{$self->{cache}->{$index1}->{$index2}};
        return @keys if @keys;
    }

    @keys = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Stuff WHERE index1 = ? AND index2 = ?');

        $sth->execute($index1, $index2);

        my $context = $sth->fetchall_arrayref({});

        my @k = ();
        return @k if not @{$context};

        my ($lc_index1, $lc_index2) = (lc $index1, lc $index2);

        foreach my $key (keys %{$context->[0]}) {
            next if $key eq 'index1' or $key eq 'index2';
            push @k, $key if defined $context->[0]->{$key};
            $self->{cache}->{$lc_index1}->{$lc_index2}->{$key} = $context->[0]->{$key};
        }

        $self->enqueue_decache($lc_index1, $lc_index2);

        return @k;
    };

    if ($@) {
        $self->{pbot}->{logger}->log($@);
        return ();
    }

    return @keys;
}

sub get_each {
    my ($self, @opts) = @_;

    my $sth = eval {
        my $sql    = 'SELECT ';
        my @keys   = ();
        my @values = ();
        my @where  = ();
        my @sort   = ();

        my $everything = 0;

        foreach my $expr (@opts) {
            my ($key, $op, $value) = $expr =~ /(.*?)\s+([!=<>]+)\s+(.*)/;

            if (not defined $key) {
                $key = $expr;
            }

            if ($key eq '_everything') {
                $everything = 1;
                push @keys, '*';
                next;
            }

            if ($key eq '_sort') {
                if ($value =~ s/^\-//) {
                    push @sort, "$value DESC";
                } else {
                    $value =~ s/^\+//; # optional
                    push @sort, "$value ASC";
                }
                next;
            }

            if (defined $op) {
                my $prefix = 'AND';

                if ($op eq '=' or $op eq '==') {
                    $op = '=';
                } elsif ($op eq '!=' or $op eq '<>') {
                    $op = '!=';
                }

                if ($key =~ s/^(OR|AND)\s+//) {
                    $prefix = $1;
                }

                $prefix = '' if not @where;
                push @where, [ $prefix, $key, $op ];
                push @values, $value;
            }

            push @keys, $key unless $everything or grep { $_ eq $key } @keys;
        }

        $sql .= join ', ', @keys;
        $sql .= ' FROM Stuff WHERE';

        my $in_or = 0;

        for (my $i = 0; $i < @where; $i++) {
            my ($prefix, $key, $op) = @{$where[$i]};

            my ($next_prefix, $next_key) = ('', '');

            if ($i < @where - 1) {
                ($next_prefix, $next_key) = @{$where[$i + 1]};
            }

            if ($next_prefix eq 'OR' and $next_key eq $key) {
                $sql .= "$prefix ";
                $sql .= '(' if not $in_or;
                $sql .= "\"$key\" $op ? ";
                $in_or = 1;
            } else {
                $sql .= "$prefix \"$key\" $op ? ";

                if ($in_or) {
                    $sql .= ') ';
                    $in_or = 0;
                }
            }
        }

        $sql .= ')' if $in_or;

        $sql .= ' ORDER BY ' . join(', ', @sort) if @sort;

        my $sth = $self->{dbh}->prepare($sql);

        my $param = 0;
        foreach my $value (@values) {
            $sth->bind_param(++$param, $value);
        }

        $sth->execute;
        return $sth;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error getting data: $@");
        return undef;
    }

    return $sth;
}

sub get_next {
    my ($self, $sth) = @_;

    my $data = eval {
        return $sth->fetchrow_hashref;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error getting next: $@");
        return undef;
    }

    return $data;
}

sub get_all {
    my ($self, @opts) = @_;

    my $sth = $self->get_each(@opts);

    my $data = eval {
        return $sth->fetchall_arrayref({});
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error getting all data: $@\n");
        return undef;
    }

    return @$data;
}

sub get_key_name {
    my ($self, $index1, $index2) = @_;

    my $lc_index1 = lc $index1;

    if (not exists $self->{cache}->{$lc_index1}) {
        return $lc_index1;
    }

    if (not defined $index2) {
        if (exists $self->{cache}->{$lc_index1}->{_name}) {
            return $self->{cache}->{$lc_index1}->{_name};
        } else {
            return $lc_index1;
        }
    }

    my $lc_index2 = lc $index2;

    if (not exists $self->{cache}->{$lc_index1}->{$lc_index2}) {
        return $lc_index2;
    }

    if (exists $self->{cache}->{$lc_index1}->{$lc_index2}->{_name}) {
        return $self->{cache}->{$lc_index1}->{$lc_index2}->{_name};
    } else {
        return $lc_index2;
    }
}

sub get_data {
    my ($self, $index1, $index2, $data_index) = @_;

    my $lc_index1 = lc $index1;
    my $lc_index2 = lc $index2;

    if (not exists $self->{cache}->{$lc_index1}) {
        return undef;
    }

    if (not exists $self->{cache}->{$lc_index1}->{$lc_index2} and $lc_index2 ne '_name') {
        return undef;
    }

    if (not defined $data_index) {
        # special case for compatibility with DualIndexHashObject
        if ($lc_index2 eq '_name') {
            if (exists $self->{cache}->{$lc_index1}->{_name}) {
                return $self->{cache}->{$lc_index1}->{_name};
            } else {
                return $lc_index1;
            }
        }

        my $data = eval {
            my $sth = $self->{dbh}->prepare('SELECT * FROM Stuff WHERE index1 = ? AND index2 = ?');
            $sth->execute($index1, $index2);
            my $context = $sth->fetchall_arrayref({});

            my $d = {};

            foreach my $key (keys %{$context->[0]}) {
                next if $key eq 'index1' or $key eq 'index2';

                if (defined $context->[0]->{$key}) {
                    $self->{cache}->{$lc_index1}->{$lc_index2}->{$key} = $context->[0]->{$key};
                    $d->{$key} = $context->[0]->{$key};
                }
            }

            $self->enqueue_decache($lc_index1, $lc_index2);

            return $d;
        };

        if ($@) {
            $self->{pbot}->{logger}->log("Error getting data for ($index1, $index2): $@\n");
            return undef;
        }

        return $data;
    }

    # special case for compatibility with DualIndexHashObject
    if ($data_index eq '_name') {
        if (exists $self->{cache}->{$lc_index1}->{$lc_index2}->{_name}) {
            return $self->{cache}->{$lc_index1}->{$lc_index2}->{_name};
        } else {
            return $lc_index2;
        }
    }

    if (exists $self->{cache}->{$lc_index1}->{$lc_index2}->{$data_index}) {
        return $self->{cache}->{$lc_index1}->{$lc_index2}->{$data_index};
    }

    my $value = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Stuff WHERE index1 = ? AND index2 = ?');
        $sth->execute($index1, $index2);
        my $context = $sth->fetchall_arrayref({});

        foreach my $key (keys %{$context->[0]}) {
            next if $key eq 'index1' or $key eq 'index2';
            $self->{cache}->{$lc_index1}->{$lc_index2}->{$key} = $context->[0]->{$key};
        }

        $self->enqueue_decache($lc_index1, $lc_index2);

        return $context->[0]->{$data_index};
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error getting data for ($index1, $index2, $data_index): $@\n");
        return undef;
    }

    return $value;
}

sub add {
    my ($self, $index1, $index2, $data, $quiet) = @_;

    my $name1 = $self->get_data($index1, '_name') // $index1;

    eval {
        my $sth;

        if (not $self->exists($index1, $index2)) {
            $sth = $self->{dbh}->prepare('INSERT INTO Stuff (index1, index2) VALUES (?, ?)');
            $sth->execute($name1, $index2);
        }

        my $sql = 'UPDATE Stuff SET ';

        my $comma = '';
        foreach my $key (sort keys %$data) {
            if (not exists $self->{columns}->{$key}) {
                next;
            }
            $sql .= "$comma\"$key\" = ?";
            $comma = ', ';
        }

        $sql .= ' WHERE index1 == ? AND index2 == ?';

        $sth = $self->{dbh}->prepare($sql);

        my $param = 1;
        foreach my $key (sort keys %$data) {
            next if not exists $self->{columns}->{$key};
            $sth->bind_param($param++, $data->{$key});
        }

        $sth->bind_param($param++, $index1);
        $sth->bind_param($param++, $index2);
        $sth->execute();

        # no errors updating SQL -- now we update cache
        my ($lc_index1, $lc_index2) = (lc $index1, lc $index2);

        if ($index1 ne $lc_index1 and not exists $self->{cache}->{$lc_index1}->{_name}) {
            $self->{cache}->{$lc_index1}->{_name} = $index1;
        }

        if (grep { $_ ne '_name' } keys %{$self->{cache}->{$lc_index1}->{$lc_index2}}) {
            foreach my $key (sort keys %$data) {
                next if not exists $self->{columns}->{$key};
                $self->{cache}->{$lc_index1}->{$lc_index2}->{$key} = $data->{$key};
            }
        } else {
            $self->{cache}->{$lc_index1}->{lc $index2} = {}
        }

        if (not exists $self->{cache}->{$lc_index1}->{$lc_index2}->{_name} and $index2 ne $lc_index2) {
            $self->{cache}->{$lc_index1}->{$lc_index2}->{_name} = $index2;
        }
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error adding $self->{name} $index2 to $index1: $@\n");
        $self->{dbh}->rollback;
        return "Error adding $index2 to $name1: $@\n";
    }

    $index1 = 'global'      if $index1 eq '.*';
    $index2 = "\"$index2\"" if $index2 =~ / /;

    $self->{pbot}->{logger}->log("$self->{name}: [$index1]: $index2 added.\n") unless $quiet;

    $self->save unless $quiet;

    return "$index2 added to $name1.";
}

sub remove {
    my ($self, $index1, $index2, $data_index, $dont_save) = @_;

    if (not $self->exists($index1)) {
        my $result = "$self->{name}: $index1 not found; similiar matches: ";
        $result .= $self->levenshtein_matches($index1);
        return $result;
    }

    my $name1 = $self->get_data($index1, '_name');
    $name1 = 'global' if $name1 eq '.*';

    my $lc_index1 = lc $index1;

    if (not defined $index2) {
        eval {
            my $sth = $self->{dbh}->prepare("DELETE FROM Stuff WHERE index1 = ?");
            $sth->execute($index1);

            $self->cache_remove($index1);
        };

        if ($@) {
            $self->{pbot}->{logger}->log("Error removing $index1 from $self->{name}: $@\n");
            return "Error removing $name1: $@";
        }

        $self->save unless $dont_save;

        return "$name1 removed.";
    }

    if (not $self->exists($index1, $index2)) {
        my $result = "$self->{name}: [$name1] $index2 not found; similiar matches: ";
        $result .= $self->levenshtein_matches($index1, $index2);
        return $result;
    }

    my $name2 = $self->get_data($index1, $index2, '_name');
    $name2 = "\"$name2\"" if $name2 =~ / /;

    my $lc_index2 = lc $index2;

    if (not defined $data_index) {
        eval {
            my $sth = $self->{dbh}->prepare("DELETE FROM Stuff WHERE index1 = ? AND index2 = ?");
            $sth->execute($index1, $index2);

            $self->cache_remove($index1, $index2);
        };

        if ($@) {
            $self->{pbot}->{logger}->log("Error removing $self->{name}: [$name1] $name2: $@\n");
            return "Error removing $name2 from $name1: $@";
        }

        $self->save unless $dont_save;
        return "$name2 removed from $name1.";
    }

    if (not exists $self->{columns}->{$data_index}) {
        return "$self->{name} have no such metadata $data_index.";
    }

    if (defined $self->get_data($lc_index1, $lc_index2, $data_index)) {
        eval {
            my $sth = $self->{dbh}->prepare("UPDATE Stuff SET '$data_index' = ? WHERE index1 = ? AND index2 = ?");
            $sth->execute(undef, $index1, $index2);

            $self->{cache}->{$index1}->{$index2}->{$data_index} = undef;
        };

        if ($@) {
            $self->{pbot}->{logger}->log("Error unsetting $self->{name}: $name1.$name2: $@\n");
            return "Error unsetting $data_index from $name2: $@";
        }

        $self->save unless $dont_save;
        return "$name2.$data_index unset.";
    }

    return "$name2.$data_index is not set.";
}

sub set {
    my ($self, $index1, $index2, $key, $value) = @_;

    if (not $self->exists($index1)) {
        my $result = "$self->{name}: $index1 not found; similiar matches: ";
        $result .= $self->levenshtein_matches($index1);
        return $result;
    }

    if (not $self->exists($index1, $index2)) {
        my $secondary_text = $index2 =~ / / ? "\"$index2\"" : $index2;
        my $result = "$self->{name}: [" . $self->get_data($index1, '_name') . "] $secondary_text not found; similiar matches: ";
        $result .= $self->levenshtein_matches($index1, $index2);
        return $result;
    }

    my $name1 = $self->get_data($index1, '_name');
    my $name2 = $self->get_data($index1, $index2, '_name');

    $name1 = 'global'     if $name1 eq '.*';
    $name2 = "\"$name2\"" if $name2 =~ / /;

    if (not defined $key) {
        my $result   = "[$name1] $name2 keys:\n";
        my @metadata = ();

        foreach my $key (sort $self->get_keys($index1, $index2)) {
            my $value = $self->get_data($index1, $index2, $key);
            push @metadata, "$key => $value" if defined $value;
        }

        if (not @metadata) {
            $result .= "none";
        } else {
            $result .= join ";\n", @metadata;
        }

        return $result;
    }

    if (not exists $self->{columns}->{$key}) {
        return "$self->{name} have no such metadata $key.";
    }

    if (not defined $value) {
        $value = $self->get_data($index1, $index2, $key);
    }
    else {
        eval {
            my $sth = $self->{dbh}->prepare("UPDATE Stuff SET '$key' = ? WHERE index1 = ? AND index2 = ?");

            $sth->execute($value, $index1, $index2);

            my ($lc_index1, $lc_index2) = (lc $index1, lc $index2);

            if (exists $self->{cache}->{$lc_index1}
                    and exists $self->{cache}->{$lc_index1}->{$lc_index2}
                    and exists $self->{cache}->{$lc_index1}->{$lc_index2}->{$key}) {
                $self->{cache}->{$lc_index1}->{$lc_index2}->{$key} = $value;
            }

            $self->save;
        };

        if ($@) {
            $self->{pbot}->{logger}->log("Error setting $self->{name} $index1 $index2.$key: $@\n");
            return "Error setting $name2.$key: $@";
        }
    }

    return "[$name1] $name2.$key " . (defined $value ? "set to $value" : "is not set.");
}

sub unset {
    my ($self, $index1, $index2, $key) = @_;

    if (not $self->exists($index1)) {
        my $result = "$self->{name}: $index1 not found; similiar matches: ";
        $result .= $self->levenshtein_matches($index1);
        return $result;
    }

    my $name1 = $self->get_data($index1, '_name');
    $name1 = 'global' if $name1 eq '.*';

    if (not $self->exists($index1, $index2)) {
        my $result = "$self->{name}: [$name1] $index2 not found; similiar matches: ";
        $result .= $self->levenshtein_matches($index1, $index2);
        return $result;
    }

    my $name2 = $self->get_data($index1, $index2, '_name');
    $name2 = "\"$name2\"" if $name2 =~ / /;

    if (not exists $self->{columns}->{$key}) {
        return "$self->{name} have no such metadata $key.";
    }

    eval {
        my $sth = $self->{dbh}->prepare("UPDATE Stuff SET '$key' = ? WHERE index1 = ? AND index2 = ?");

        $sth->execute(undef, $index1, $index2);

        my ($lc_index1, $lc_index2) = (lc $index1, lc $index2);

        if (exists $self->{cache}->{$lc_index1}
                and exists $self->{cache}->{$lc_index1}->{$lc_index2}
                and exists $self->{cache}->{$lc_index1}->{$lc_index2}->{$key}) {
            $self->{cache}->{$lc_index1}->{$lc_index2}->{$key} = undef;
        }

        $self->save;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error unsetting key: $@\n");
        return "Error unsetting key: $@";
    }

    return "[$name1] $name2.$key unset.";
}

# nothing to do here for SQLite
# kept for compatibility with DualIndexHashObject
sub clear { }

1;
