# File: SQLite.pm
#
# Purpose: SQLite backend for storing/retreiving a user's message history.
# Peforms intelligent hostmask and nickserv heuristics to link nicknames
# in order to ensure message history is stored in the right user account
# ids. This is also extremely useful for detecting ban-evasions and listing
# also-known-as data for a nickname (see the !aka bot command).

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::MessageHistory::Storage::SQLite;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Core::MessageHistory::Constants ':all';

use PBot::Core::Utils::SQLiteLogger;
use PBot::Core::Utils::SQLiteLoggerLayer;

use DBI;
use Carp              qw/shortmess/;
use Time::HiRes       qw/time/;
use Text::CSV;
use Text::Levenshtein qw/fastdistance/;
use Time::Duration;

sub initialize {
    my ($self, %conf) = @_;

    $self->{filename}    = $conf{filename} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/message_history.sqlite3';
    $self->{new_entries} = 0;

    $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'debug_link',             0);
    $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'debug_aka',              0);
    $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'sqlite_commit_interval', 30);
    $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'sqlite_debug',           $conf{sqlite_debug} // 0);

    $self->{pbot}->{registry}->add_trigger('messagehistory', 'sqlite_commit_interval',
        sub { $self->sqlite_commit_interval_trigger(@_) });

    $self->{pbot}->{registry}->add_trigger('messagehistory', 'sqlite_debug',
        sub { $self->sqlite_debug_trigger(@_) });

    $self->{pbot}->{event_queue}->enqueue(
        sub { $self->commit_message_history },
        $self->{pbot}->{registry}->get_value('messagehistory', 'sqlite_commit_interval'),
        'messagehistory commit');

    $self->{alias_type}->{WEAK}   = 0;
    $self->{alias_type}->{STRONG} = 1;
}

sub sqlite_commit_interval_trigger {
    my ($self, $section, $item, $newvalue) = @_;
    $self->{pbot}->{event_queue}->update_interval('messagehistory commit', $newvalue);
}

sub sqlite_debug_trigger {
    my ($self, $section, $item, $newvalue) = @_;

    if ($newvalue) {
        open $self->{trace_layer}, '>:via(PBot::Core::Utils::SQLiteLoggerLayer)', PBot::Core::Utils::SQLiteLogger->new(pbot => $self->{pbot});
    } else {
        close $self->{trace_layer} if $self->{trace_layer};
        delete $self->{trace_layer};
    }

    $self->{dbh}->trace($self->{dbh}->parse_trace_flags("SQL|$newvalue")) if defined $self->{dbh};
}

sub begin {
    my $self = shift;

    $self->{pbot}->{logger}->log("Opening message history SQLite database: $self->{filename}\n");

    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", {RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1, sqlite_unicode => 1})
      or die $DBI::errstr;

    eval {
        my $sqlite_debug = $self->{pbot}->{registry}->get_value('messagehistory', 'sqlite_debug');
        if ($sqlite_debug) {
            open $self->{trace_layer}, '>:via(PBot::Core::Utils::SQLiteLoggerLayer)', PBot::Core::Utils::SQLiteLogger->new(pbot => $self->{pbot});
            $self->{dbh}->trace($self->{dbh}->parse_trace_flags("SQL|$sqlite_debug"), $self->{trace_layer});
        }

        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Hostmasks (
  hostmask    TEXT PRIMARY KEY UNIQUE COLLATE NOCASE,
  id          INTEGER,
  last_seen   NUMERIC,
  nickchange  INTEGER,
  nick        TEXT COLLATE NOCASE,
  user        TEXT COLLATE NOCASE,
  host        TEXT COLLATE NOCASE
)
SQL

        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Accounts (
  id           INTEGER PRIMARY KEY,
  hostmask     TEXT UNIQUE COLLATE NOCASE,
  nickserv     TEXT COLLATE NOCASE
)
SQL

        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Nickserv (
  id         INTEGER,
  nickserv   TEXT COLLATE NOCASE,
  timestamp  NUMERIC,
  UNIQUE (id, nickserv)
)
SQL

        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Gecos (
  id         INTEGER,
  gecos      TEXT COLLATE NOCASE,
  timestamp  NUMERIC,
  UNIQUE (id, gecos)
)
SQL

        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Channels (
  id              INTEGER,
  channel         TEXT COLLATE NOCASE,
  enter_abuse     INTEGER,
  enter_abuses    INTEGER,
  offenses        INTEGER,
  last_offense    NUMERIC,
  last_seen       NUMERIC,
  validated       INTEGER,
  join_watch      INTEGER,
  unbanmes        INTEGER,
  UNIQUE (id, channel)
)
SQL

        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Messages (
  id         INTEGER,
  channel    TEXT COLLATE NOCASE,
  msg        TEXT COLLATE NOCASE,
  timestamp  NUMERIC,
  mode       INTEGER,
  hostmask   TEXT COLLATE NOCASE
)
SQL

        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Aliases (
  id          INTEGER,
  alias       INTEGER,
  type        INTEGER
)
SQL

        $self->{dbh}->do('CREATE INDEX IF NOT EXISTS MsgIdx1 ON Messages(id, channel, mode)');
        $self->{dbh}->do('CREATE INDEX IF NOT EXISTS AliasIdx1 ON Aliases(id, alias, type)');
        $self->{dbh}->do('CREATE INDEX IF NOT EXISTS AliasIdx2 ON Aliases(alias, id, type)');

        $self->{dbh}->do('CREATE INDEX IF NOT EXISTS hostmask_nick_idx on Hostmasks (nick)');
        $self->{dbh}->do('CREATE INDEX IF NOT EXISTS hostmask_host_idx on Hostmasks (host)');
        $self->{dbh}->do('CREATE INDEX IF NOT EXISTS hostmasks_id_idx on Hostmasks (id)');
        $self->{dbh}->do('CREATE INDEX IF NOT EXISTS gecos_id_idx on Gecos (id)');
        $self->{dbh}->do('CREATE INDEX IF NOT EXISTS nickserv_id_idx on Nickserv (id)');

        $self->{dbh}->begin_work();
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub end {
    my $self = shift;

    $self->{pbot}->{logger}->log("Closing message history SQLite database\n");

    if (exists $self->{dbh} and defined $self->{dbh}) {
        $self->{dbh}->commit;
        $self->{dbh}->disconnect;
        close $self->{trace_layer} if $self->{trace_layer};
        delete $self->{dbh};
    }
}

sub get_gecos {
    my ($self, $id) = @_;

    my $gecos = eval {
        my $sth = $self->{dbh}->prepare('SELECT gecos FROM Gecos WHERE ID = ?');
        $sth->execute($id);
        return $sth->fetchall_arrayref();
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return map { $_->[0] } @$gecos;
}

sub get_nickserv_accounts {
    my ($self, $id) = @_;

    my $nickserv_accounts = eval {
        my $sth = $self->{dbh}->prepare('SELECT nickserv FROM Nickserv WHERE ID = ?');
        $sth->execute($id);
        return $sth->fetchall_arrayref();
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return map { $_->[0] } @$nickserv_accounts;
}

sub set_current_nickserv_account {
    my ($self, $id, $nickserv) = @_;

    eval {
        my $sth = $self->{dbh}->prepare('UPDATE Accounts SET nickserv = ? WHERE id = ?');
        $sth->execute($nickserv, $id);
        $self->{new_entries}++;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub get_current_nickserv_account {
    my ($self, $id) = @_;

    my $nickserv = eval {
        my $sth = $self->{dbh}->prepare('SELECT nickserv FROM Accounts WHERE id = ?');
        $sth->execute($id);
        my $row = $sth->fetchrow_hashref();
        if   (defined $row) { return $row->{'nickserv'}; }
        else                { return undef; }
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return $nickserv;
}

sub create_nickserv {
    my ($self, $id, $nickserv) = @_;

    eval {
        my $sth = $self->{dbh}->prepare('INSERT OR IGNORE INTO Nickserv VALUES (?, ?, 0)');
        my $rv  = $sth->execute($id, $nickserv);
        $self->{new_entries}++;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub update_nickserv_account {
    my ($self, $id, $nickserv, $timestamp) = @_;

    #$self->{pbot}->{logger}->log("Updating nickserv account for id $id to $nickserv with timestamp [$timestamp]\n");

    $self->create_nickserv($id, $nickserv);

    eval {
        my $sth = $self->{dbh}->prepare('UPDATE Nickserv SET timestamp = ? WHERE id = ? AND nickserv = ?');
        $sth->execute($timestamp, $id, $nickserv);
        $self->{new_entries}++;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub create_gecos {
    my ($self, $id, $gecos) = @_;

    eval {
        my $sth = $self->{dbh}->prepare('INSERT OR IGNORE INTO Gecos VALUES (?, ?, 0)');
        my $rv  = $sth->execute($id, $gecos);
        $self->{new_entries}++ if $sth->rows;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub update_gecos {
    my ($self, $id, $gecos, $timestamp) = @_;

    $self->create_gecos($id, $gecos);

    eval {
        my $sth = $self->{dbh}->prepare('UPDATE Gecos SET timestamp = ? WHERE id = ? AND gecos = ?');
        $sth->execute($timestamp, $id, $gecos);
        $self->{new_entries}++;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub add_message_account {
    my ($self, $mask, $link_id, $link_type) = @_;
    my $id;
    my ($nick, $user, $host) = $mask =~ m/^([^!]+)!([^@]+)@(.*)/;

    if (defined $link_id and $link_type == $self->{alias_type}->{STRONG}) { $id = $link_id; }
    else {
        $id = $self->get_new_account_id();
        $self->{pbot}->{logger}->log("Got new account id $id\n");
    }

    eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Hostmasks VALUES (?, ?, ?, 0, ?, ?, ?)');
        $sth->execute($mask, $id, scalar time, $nick, $user, $host);
        $self->{new_entries}++;

        if ((not defined $link_id) || ((defined $link_id) && ($link_type == $self->{alias_type}->{WEAK}))) {
            $sth = $self->{dbh}->prepare('INSERT INTO Accounts VALUES (?, ?, ?)');
            $sth->execute($id, $mask, "");
            $self->{new_entries}++;

            $self->{pbot}->{logger}->log("Added new account $id for mask $mask\n");
        }
    };

    $self->{pbot}->{logger}->log($@) if $@;

    if (defined $link_id && $link_type == $self->{alias_type}->{WEAK}) {
        $self->{pbot}->{logger}->log("Weakly linking $id to $link_id\n");
        $self->link_alias($id, $link_id, $link_type);
    }

    return $id;
}

sub find_message_account_by_id {
    my ($self, $id) = @_;

    my $hostmask = eval {
        my $sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE id = ? ORDER BY last_seen DESC LIMIT 1');
        $sth->execute($id);
        my $row = $sth->fetchrow_hashref();
        return $row->{hostmask};
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return $hostmask;
}

sub find_message_account_by_nick {
    my ($self, $nick) = @_;

    my ($id, $hostmask) = eval {
        my $sth = $self->{dbh}->prepare('SELECT id, hostmask FROM Hostmasks WHERE nick = ? ORDER BY last_seen DESC LIMIT 1');
        $sth->execute($nick);
        my $row = $sth->fetchrow_hashref();
        return ($row->{id}, $row->{hostmask});
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return ($id, $hostmask);
}

sub find_message_accounts_by_nickserv {
    my ($self, $nickserv) = @_;

    my $accounts = eval {
        my $sth = $self->{dbh}->prepare('SELECT id FROM Nickserv WHERE nickserv = ?');
        $sth->execute($nickserv);
        return $sth->fetchall_arrayref();
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return map { $_->[0] } @$accounts;
}

sub find_message_accounts_by_mask {
    my ($self, $mask) = @_;

    my $qmask = quotemeta $mask;
    $qmask =~ s/_/\\_/g;
    $qmask =~ s/\\\*/%/g;
    $qmask =~ s/\\\?/_/g;
    $qmask =~ s/\\\$.*$//;

    my $accounts = eval {
        my $sth = $self->{dbh}->prepare('SELECT id FROM Hostmasks WHERE hostmask LIKE ? ESCAPE "\"');
        $sth->execute($qmask);
        return $sth->fetchall_arrayref();
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return map { $_->[0] } @$accounts;
}

sub get_message_account_ancestor {
    my $self = shift;
    my $id   = $self->get_message_account(@_);
    $id = $self->get_ancestor_id($id);
    return $id;
}

sub get_message_account {
    my ($self, $nick, $user, $host, $orig_nick) = @_;

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

=cut
  use Devel::StackTrace;
  my $trace = Devel::StackTrace->new(indent => 1, ignore_class => ['PBot::PBot', 'PBot::IRC']);
  $self->{pbot}->{logger}->log("get_message_account stacktrace: " . $trace->as_string() . "\n");
=cut

    my $mask = "$nick!$user\@$host";
    my $id   = $self->get_message_account_id($mask);
    return $id if defined $id;

    $self->{pbot}->{logger}->log("Getting new message account for $nick!$user\@$host\n");
    $self->{pbot}->{logger}->log("Nick-changing from $orig_nick\n") if defined $orig_nick;

    my $do_nothing = 0;
    my $sth;

    my ($rows, $link_type) = eval {
        my ($account1) = $host =~ m{/([^/]+)$};
        $account1 //= '';

        # extract ips from hosts like 75-42-36-105.foobar.com as 75.42.36.105
        my $hostip;

        if ($host =~ m/(\d+[[:punct:]]\d+[[:punct:]]\d+[[:punct:]]\d+)\D/) {
            $hostip = $1;
            $hostip =~ s/[[:punct:]]/./g;
        }

        # nick-change from $orig_nick to $nick
        if (defined $orig_nick) {
            # get original nick's account id
            my $orig_id = $self->get_message_account_id("$orig_nick!$user\@$host");

            # changing nick to a Guest
            if ($nick =~ m/^Guest\d+$/) {
                # find most recent *!user@host, if any
                $sth = $self->{dbh}->prepare('SELECT id, hostmask, last_seen FROM Hostmasks WHERE user = ? and host = ? ORDER BY last_seen DESC LIMIT 1');
                $sth->execute($user, $host);

                my $rows = $sth->fetchall_arrayref({});

                # found a probable match
                if (defined $rows->[0]) {
                    my $link_type = $self->{alias_type}->{STRONG};

                    # if 48 hours have elapsed since this *!user@host was seen
                    # then still link the Guest to this account, but weakly
                    if (time - $rows->[0]->{last_seen} > 60 * 60 * 48) {
                        $link_type = $self->{alias_type}->{WEAK};

                        $self->{pbot}->{logger}->log(
                            "Longer than 48 hours (" . concise duration(time - $rows->[0]->{last_seen}) . ")"
                            . " for $rows->[0]->{hostmask} for $nick!$user\@$host, degrading to weak link\n"
                        );
                    }

                    # log match and return link
                    $self->{pbot}->{logger}->log("6: nick-change guest match: $rows->[0]->{id}: $rows->[0]->{hostmask}\n");
                    $orig_nick = undef; # nick-change handled
                    return ($rows, $link_type);
                }
            }

            # find all accounts that match nick!*@*, sorted by last-seen
            $sth = $self->{dbh}->prepare('SELECT id, hostmask, last_seen FROM Hostmasks WHERE nick = ? ORDER BY last_seen DESC');
            $sth->execute($nick);
            my $rows = $sth->fetchall_arrayref({});

            # no nicks found, strongly link to original account
            if (not defined $rows->[0]) {
                $rows->[0] = { id => $orig_id, hostmask => "$orig_nick!$user\@$host" };
                $orig_nick = undef; # nick-change handled
                return ($rows, $self->{alias_type}->{STRONG});
            }

            # look up original nick's NickServ accounts outside of upcoming loop
            my @orig_nickserv_accounts = $self->get_nickserv_accounts($orig_id);

            # go over the list of nicks and see if any identifying details match
            my %processed_nicks;
            my %processed_akas;

            foreach my $row (@$rows) {
                $self->{pbot}->{logger}->log("Found matching nick-change account: [$row->{id}] $row->{hostmask}\n");
                my ($tnick) = $row->{hostmask} =~ m/^([^!]+)!/;

                # don't process duplicates
                next if exists $processed_nicks{lc $tnick};
                $processed_nicks{lc $tnick} = 1;

                # get all akas for this nick
                my %akas = $self->get_also_known_as($tnick);

                # check each aka for identifying details
                foreach my $aka (keys %akas) {
                    # skip dubious links
                    next if $akas{$aka}->{type} == $self->{alias_type}->{WEAK};
                    next if $akas{$aka}->{nickchange} == 1;

                    # don't process duplicates
                    next if exists $processed_akas{$akas{$aka}->{id}};
                    $processed_akas{$akas{$aka}->{id}} = 1;

                    $self->{pbot}->{logger}->log("Testing alias [$akas{$aka}->{id}] $aka\n");
                    my $match = 0;

                    # account ids or *!user@host matches
                    if ($akas{$aka}->{id} == $orig_id || $aka =~ m/^.*!\Q$user\E\@\Q$host\E$/i) {
                        $self->{pbot}->{logger}->log("1: match: $akas{$aka}->{id} vs $orig_id // $aka vs *!$user\@$host\n");
                        $match = 1;
                        goto MATCH;
                    }

                    # check if any nickserv accounts match
                    if (@orig_nickserv_accounts) {
                        my @nickserv_accounts = $self->get_nickserv_accounts($akas{$aka}->{id});
                        foreach my $ns1 (@orig_nickserv_accounts) {
                            foreach my $ns2 (@nickserv_accounts) {
                                if ($ns1 eq $ns2) {
                                    $self->{pbot}->{logger}->log("Got matching nickserv: $ns1\n");
                                    $match = 1;
                                    goto MATCH;
                                }
                            }
                        }
                    }

                    # check if hosts match
                    my ($thost) = $aka =~ m/@(.*)$/;

                    if ($thost =~ m{/}) {
                        my ($account2) = $thost =~ m{/([^/]+)$};

                        if ($account1 ne $account2) {
                            $self->{pbot}->{logger}->log("Skipping non-matching cloaked hosts: $host vs $thost\n");
                            next;
                        } else {
                            $self->{pbot}->{logger}->log("Cloaked hosts match: $host vs $thost\n");
                            $rows->[0] = {
                                id       => $self->get_ancestor_id($akas{$aka}->{id}),
                                hostmask => $aka,
                            };
                            return ($rows, $self->{alias_type}->{STRONG});
                        }
                    }

                    # fuzzy match hosts
                    my $distance = fastdistance($host, $thost);
                    my $length   = (length($host) > length($thost)) ? length $host : length $thost;

                    #$self->{pbot}->{logger}->log("distance: " . ($distance / $length) . " -- $host vs $thost\n") if $length != 0;

                    if ($length != 0 && $distance / $length < 0.50) {
                        $self->{pbot}->{logger}->log("2: distance match: $host vs $thost == " . ($distance / $length) . "\n");
                        $match = 1;
                    } else {
                        # handle cases like 99.57.140.149 vs 99-57-140-149.lightspeed.sntcca.sbcglobal.net
                        if (defined $hostip) {
                            if ($hostip eq $thost) {
                                $match = 1;
                                $self->{pbot}->{logger}->log("3: IP vs hostname match: $host vs $thost\n");
                            }
                        } elsif ($thost =~ m/(\d+[[:punct:]]\d+[[:punct:]]\d+[[:punct:]]\d+)\D/) {
                            my $thostip = $1;
                            $thostip =~ s/[[:punct:]]/./g;
                            if ($thostip eq $host) {
                                $match = 1;
                                $self->{pbot}->{logger}->log("4: IP vs hostname match: $host vs $thost\n");
                            }
                        }
                    }

                  MATCH:
                    if ($match) {
                        $self->{pbot}->{logger}->log("Using this match.\n");
                        $rows->[0] = {id => $self->get_ancestor_id($akas{$aka}->{id}), hostmask => $aka};
                        return ($rows, $self->{alias_type}->{STRONG});
                    }
                }
            }

            $self->{pbot}->{logger}->log("Creating new nickchange account!\n");

            my $new_id = $self->add_message_account($mask);
            $self->link_alias($orig_id, $new_id, $self->{alias_type}->{WEAK});
            $self->update_hostmask_data($mask, {nickchange => 1, last_seen => scalar time});

            $do_nothing = 1;
            $rows->[0] = {id => $new_id};
            return ($rows, 0);
        } # end nick-change

        if ($host =~ m{^gateway/web/irccloud.com}) {
            $sth = $self->{dbh}->prepare('SELECT id, hostmask, last_seen FROM Hostmasks WHERE host = ? ORDER BY last_seen DESC');
            $sth->execute("gateway/web/irccloud.com/x-$user");
            my $rows = $sth->fetchall_arrayref({});
            if (defined $rows->[0]) {
                $self->{pbot}->{logger}->log("5: irccloud match: $rows->[0]->{id}: $rows->[0]->{hostmask}\n");
                return ($rows, $self->{alias_type}->{STRONG});
            }
        }

        if ($host =~ m{^nat/([^/]+)/}) {
            my $nat = $1;
            $sth = $self->{dbh}->prepare('SELECT id, hostmask, last_seen FROM Hostmasks WHERE nick = ? AND host = ? ORDER BY last_seen DESC');
            $sth->execute($nick, "nat/$nat/x-$user");
            my $rows = $sth->fetchall_arrayref({});
            if (defined $rows->[0]) {
                $self->{pbot}->{logger}->log("6: nat match: $rows->[0]->{id}: $rows->[0]->{hostmask}\n");
                return ($rows, $self->{alias_type}->{STRONG});
            }
        }

        # cloaked hostmask
        if ($host =~ m{/}) {
            $sth = $self->{dbh}->prepare('SELECT id, hostmask, last_seen FROM Hostmasks WHERE host = ? ORDER BY last_seen DESC');
            $sth->execute($host);
            my $rows = $sth->fetchall_arrayref({});
            if (defined $rows->[0]) {
                $self->{pbot}->{logger}->log("6: cloak match: $rows->[0]->{id}: $rows->[0]->{hostmask}\n");
                return ($rows, $self->{alias_type}->{STRONG});
            }
        }

        # guests
        if ($nick =~ m/^Guest\d+$/) {
            $sth = $self->{dbh}->prepare('SELECT id, hostmask, last_seen FROM Hostmasks WHERE user = ? and host = ? ORDER BY last_seen DESC');
            $sth->execute($user, $host);
            my $rows = $sth->fetchall_arrayref({});
            if (defined $rows->[0]) {
                my $link_type = $self->{alias_type}->{STRONG};
                if (time - $rows->[0]->{last_seen} > 60 * 60 * 48) {
                    $link_type = $self->{alias_type}->{WEAK};
                    $self->{pbot}->{logger}->log(
                        "Longer than 48 hours (" . concise duration(time - $rows->[0]->{last_seen}) . ") for $rows->[0]->{hostmask} for $nick!$user\@$host, degrading to weak link\n");
                }
                $self->{pbot}->{logger}->log("6: guest match: $rows->[0]->{id}: $rows->[0]->{hostmask}\n");
                return ($rows, $link_type);
            }
        }

        $sth = $self->{dbh}->prepare('SELECT id, hostmask, last_seen FROM Hostmasks WHERE nick = ? ORDER BY last_seen DESC');
        $sth->execute($nick);
        my $rows = $sth->fetchall_arrayref({});

        my $link_type = $self->{alias_type}->{WEAK};
        my %processed_nicks;
        my %processed_akas;

        foreach my $row (@$rows) {
            $self->{pbot}->{logger}->log("Found matching nick $row->{hostmask} with id $row->{id}\n");
            my ($tnick) = $row->{hostmask} =~ m/^([^!]+)!/;

            next if exists $processed_nicks{lc $tnick};
            $processed_nicks{lc $tnick} = 1;

            my %akas = $self->get_also_known_as($tnick);
            foreach my $aka (keys %akas) {
                next if $akas{$aka}->{type} == $self->{alias_type}->{WEAK};
                next if $akas{$aka}->{nickchange} == 1;

                next if exists $processed_akas{$akas{$aka}->{id}};
                $processed_akas{$akas{$aka}->{id}} = 1;

                $self->{pbot}->{logger}->log("Testing alias [$akas{$aka}->{id}] $aka\n");

                my ($thost) = $aka =~ m/@(.*)$/;

                if ($thost =~ m{/}) {
                    my ($account2) = $thost =~ m{/([^/]+)$};

                    if ($account1 ne $account2) {
                        $self->{pbot}->{logger}->log("Skipping non-matching cloaked hosts: $host vs $thost\n");
                        next;
                    } else {
                        $self->{pbot}->{logger}->log("Cloaked hosts match: $host vs $thost\n");
                        $rows->[0] = {id => $self->get_ancestor_id($akas{$aka}->{id}), hostmask => $aka};
                        return ($rows, $self->{alias_type}->{STRONG});
                    }
                }

                my $distance = fastdistance($host, $thost);
                my $length   = (length($host) > length($thost)) ? length $host : length $thost;

                #$self->{pbot}->{logger}->log("distance: " . ($distance / $length) . " -- $host vs $thost\n") if $length != 0;

                my $match = 0;

                if ($length != 0 && $distance / $length < 0.50) {
                    $self->{pbot}->{logger}->log("7: distance match: $host vs $thost == " . ($distance / $length) . "\n");
                    $match = 1;
                } else {
                    # handle cases like 99.57.140.149 vs 99-57-140-149.lightspeed.sntcca.sbcglobal.net
                    if (defined $hostip) {
                        if ($hostip eq $thost) {
                            $match = 1;
                            $self->{pbot}->{logger}->log("8: IP vs hostname match: $host vs $thost\n");
                        }
                    } elsif ($thost =~ m/(\d+[[:punct:]]\d+[[:punct:]]\d+[[:punct:]]\d+)\D/) {
                        my $thostip = $1;
                        $thostip =~ s/[[:punct:]]/./g;
                        if ($thostip eq $host) {
                            $match = 1;
                            $self->{pbot}->{logger}->log("9: IP vs hostname match: $host vs $thost\n");
                        }
                    }
                }

                if ($match) {
                    $rows->[0] = {id => $self->get_ancestor_id($akas{$aka}->{id}), hostmask => $aka};
                    return ($rows, $self->{alias_type}->{STRONG});
                }
            }
        }

        if (not defined $rows->[0]) {
            $link_type = $self->{alias_type}->{STRONG};

            $sth = $self->{dbh}->prepare('SELECT id, hostmask, last_seen FROM Hostmasks WHERE user = ? AND host = ? ORDER BY last_seen DESC');
            $sth->execute($user, $host);
            $rows = $sth->fetchall_arrayref({});

            if (defined $rows->[0] and time - $rows->[0]->{last_seen} > 60 * 60 * 48) {
                $link_type = $self->{alias_type}->{WEAK};
                $self->{pbot}->{logger}->log(
                    "Longer than 48 hours (" . concise duration(time - $rows->[0]->{last_seen}) . ") for $rows->[0]->{hostmask} for $nick!$user\@$host, degrading to weak link\n");
            }

=cut
      foreach my $row (@$rows) {
        $self->{pbot}->{logger}->log("Found matching user\@host mask $row->{hostmask} with id $row->{id}\n");
      }
=cut

        }
        if (defined $rows->[0]) { $self->{pbot}->{logger}->log("10: matching *!user\@host: $rows->[0]->{id}: $rows->[0]->{hostmask}\n"); }

        return ($rows, $link_type);
    };

    if (my $exception = $@) {
        $self->{pbot}->{logger}->log("Exception getting account: $exception");
    }

    # nothing else to do here for nick-change, return id
    return $rows->[0]->{id} if $do_nothing;

    if (defined $rows->[0] and not defined $orig_nick) {
        if ($link_type == $self->{alias_type}->{STRONG}) {
            my $host1 = lc "$nick!$user\@$host";
            my $host2 = lc $rows->[0]->{hostmask};

            my ($nick1) = $host1 =~ m/^([^!]+)!/;
            my ($nick2) = $host2 =~ m/^([^!]+)!/;

            my $distance = fastdistance($nick1, $nick2);
            my $length   = (length $nick1 > length $nick2) ? length $nick1 : length $nick2;

            my $irc_cloak = $self->{pbot}->{registry}->get_value('irc', 'cloak') // 'user';

            if ($distance > 1 && ($nick1 !~ /^guest/ && $nick2 !~ /^guest/) && ($host1 !~ /$irc_cloak/ || $host2 !~ /$irc_cloak/)) {
                my $id = $rows->[0]->{id};
                $self->{pbot}->{logger}->log("[$nick1][$nick2] $distance / $length\n");
                $self->{pbot}->{logger}->log("Possible bogus account: ($id) $host1 vs ($id) $host2\n");
            }
        }

        $self->{pbot}->{logger}->log("message-history: [get-account] $nick!$user\@$host "
            . ($link_type == $self->{alias_type}->{WEAK} ? "weakly linked to" : "added to account")
            . " $rows->[0]->{hostmask} with id $rows->[0]->{id}\n"
        );

        $self->add_message_account("$nick!$user\@$host", $rows->[0]->{id}, $link_type);
        $self->devalidate_all_channels($rows->[0]->{id});
        $self->update_hostmask_data("$nick!$user\@$host", { last_seen => scalar time });

        my @nickserv_accounts = $self->get_nickserv_accounts($rows->[0]->{id});
        foreach my $nickserv_account (@nickserv_accounts) {
            $self->{pbot}->{logger}->log("$nick!$user\@$host [$rows->[0]->{id}] seen with nickserv account [$nickserv_account]\n");
            $self->{pbot}->{antiflood}->check_nickserv_accounts($nick, $nickserv_account, "$nick!$user\@$host");
        }

        return $rows->[0]->{id};
    }

    $self->{pbot}->{logger}->log("No account found for $mask, adding new account\n");
    return $self->add_message_account($mask);
}

sub find_most_recent_hostmask {
    my ($self, $id) = @_;

    my $hostmask = eval {
        my $sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE ID = ? ORDER BY last_seen DESC LIMIT 1');
        $sth->execute($id);
        return $sth->fetchrow_hashref()->{'hostmask'};
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return $hostmask;
}

sub update_hostmask_data {
    my ($self, $mask, $data) = @_;

    eval {
        my $sql = 'UPDATE Hostmasks SET ';

        my $comma = '';
        foreach my $key (keys %$data) {
            $sql .= "$comma$key = ?";
            $comma = ', ';
        }

        $sql .= ' WHERE hostmask == ?';

        my $sth = $self->{dbh}->prepare($sql);

        my $param = 1;
        foreach my $key (keys %$data) { $sth->bind_param($param++, $data->{$key}); }

        $sth->bind_param($param, $mask);
        $sth->execute();
        $self->{new_entries}++;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub get_nickserv_accounts_for_hostmask {
    my ($self, $hostmask) = @_;

    my $nickservs = eval {
        my $sth = $self->{dbh}->prepare('SELECT nickserv FROM Hostmasks, Nickserv WHERE nickserv.id = hostmasks.id AND hostmasks.hostmask = ?');
        $sth->execute($hostmask);
        return $sth->fetchall_arrayref();
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return map { $_->[0] } @$nickservs;
}

sub get_gecos_for_hostmask {
    my ($self, $hostmask) = @_;

    my $gecos = eval {
        my $sth = $self->{dbh}->prepare('SELECT gecos FROM Hostmasks, Gecos WHERE gecos.id = hostmasks.id AND hostmasks.hostmask = ?');
        $sth->execute($hostmask);
        return $sth->fetchall_arrayref();
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return map { $_->[0] } @$gecos;
}

sub get_hostmasks_for_channel {
    my ($self, $channel) = @_;

    my $hostmasks = eval {
        my $sth = $self->{dbh}->prepare('SELECT hostmasks.id, hostmask FROM Hostmasks, Channels WHERE channels.id = hostmasks.id AND channel = ?');
        $sth->execute($channel);
        return $sth->fetchall_arrayref({});
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return $hostmasks;
}

sub get_hostmasks_for_nickserv {
    my ($self, $nickserv) = @_;

    my $hostmasks = eval {
        my $sth = $self->{dbh}->prepare('SELECT hostmasks.id, hostmask, nickserv FROM Hostmasks, Nickserv WHERE nickserv.id = hostmasks.id AND nickserv = ?');
        $sth->execute($nickserv);
        return $sth->fetchall_arrayref({});
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return $hostmasks;
}

sub add_message {
    my ($self, $id, $hostmask, $channel, $message) = @_;

    eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Messages VALUES (?, ?, ?, ?, ?, ?)');
        $sth->execute($id, $channel, $message->{msg}, $message->{timestamp}, $message->{mode}, $hostmask);
        $self->{new_entries}++;
    };

    $self->{pbot}->{logger}->log($@) if $@;

    $self->update_channel_data($id, $channel, { last_seen => $message->{timestamp }});
    $self->update_hostmask_data($hostmask, { last_seen => $message->{timestamp }});
}

sub get_recent_messages {
    my ($self, $id, $channel, $limit, $mode, $nick) = @_;

    $limit //= 25;

    $channel = lc $channel;

    my $mode_query = '';
    $mode_query = "AND mode = $mode" if defined $mode;

    my $messages = eval {
        my $sql = "SELECT * FROM Messages WHERE ";

        my %seen_id;

        my %akas;
        if (defined $mode and $mode == MSG_NICKCHANGE) {
            %akas = $self->get_also_known_as($nick);
        } else {
            $akas{$id} = {
                id => $id,
                type => $self->{alias_type}->{STRONG},
                nickchange => 0,
            };
        }

        foreach my $aka (keys %akas) {
            next if $akas{$aka}->{type} == $self->{alias_type}->{WEAK};
            next if $akas{$aka}->{nickchange} == 1;
            next if exists $seen_id{$akas{$aka}->{id}};

            $seen_id{$akas{$aka}->{id}} = 1;
        }

        my $ids = join " OR ", map { "id = ?" } keys %seen_id;

        $sql .= "($ids) AND channel = ? $mode_query ORDER BY timestamp ASC LIMIT ? OFFSET (SELECT COUNT(*) FROM Messages WHERE ($ids) AND channel = ? $mode_query) - ?";

        my $sth = $self->{dbh}->prepare($sql);

        my $param = 1;
        map { $sth->bind_param($param++, $_) } keys %seen_id;
        $sth->bind_param($param++, $channel);
        $sth->bind_param($param++, $limit);
        map { $sth->bind_param($param++, $_) } keys %seen_id;
        $sth->bind_param($param++, $channel);
        $sth->bind_param($param,   $limit);
        $sth->execute;
        return $sth->fetchall_arrayref({});
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return $messages;
}

sub get_recent_messages_from_channel {
    my ($self, $channel, $limit, $mode, $direction) = @_;

    $limit     //= 25;
    $direction //= 'ASC';

    $channel = lc $channel;

    my $mode_query = '';
    $mode_query = "AND mode = $mode" if defined $mode;

    my $messages = eval {
        my $sql = "SELECT * FROM Messages WHERE channel = ? $mode_query ORDER BY timestamp $direction LIMIT ?";
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute($channel, $limit);
        return $sth->fetchall_arrayref({});
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return $messages;
}

sub get_message_context {
    my ($self, $message, $before, $after, $count, $text, $context_id, $context_nick) = @_;

    my %seen_id;
    my $ids = '';

    my $sql = 'SELECT * FROM Messages WHERE channel = ? ';

    if (defined $context_id) {
        my %akas;

        if (defined $context_nick) {
            %akas = $self->get_also_known_as($context_nick);
        } else {
            $akas{$context_id} = {
                id         => $context_id,
                type       => $self->{alias_type}->{STRONG},
                nickchange => 0,
            };
        }

        foreach my $aka (keys %akas) {
            next if $akas{$aka}->{type} == $self->{alias_type}->{WEAK};
            next if $akas{$aka}->{nickchange} == 1;
            next if exists $seen_id{$akas{$aka}->{id}};

            $seen_id{$akas{$aka}->{id}} = 1;
        }

        $ids = join " OR ", map { "id = ?" } keys %seen_id;
        $ids = "AND ($ids) ";
    }

    $sql .= $ids;

    my ($messages_before, $messages_after, $messages_count);

    if (defined $count and $count > 1) {
        my $search = "%$text%";
        $search =~ s/\*/%/g;
        $search =~ s/\?/_/g;

        $messages_count = eval {
            $sql .= 'AND msg LIKE ? ESCAPE "\" AND timestamp < ? AND mode = 0 ORDER BY timestamp DESC LIMIT ?';
            my $sth = $self->{dbh}->prepare($sql);
            my $param = 1;
            $sth->bind_param($param++, $message->{channel});
            map { $sth->bind_param($param++, $_) } keys %seen_id;
            $sth->bind_param($param++, $search);
            $sth->bind_param($param++, $message->{timestamp});
            $sth->bind_param($param++, $count - 1);
            $sth->execute;
            return [reverse @{$sth->fetchall_arrayref({})}];
        };

        $self->{pbot}->{logger}->log($@) if $@;
    }

    if (defined $before and $before > 0) {
        $messages_before = eval {
            $sql .= ' AND timestamp < ? AND mode = 0 ORDER BY timestamp DESC LIMIT ?';
            my $sth = $self->{dbh}->prepare($sql);
            my $param = 1;
            $sth->bind_param($param++, $message->{channel});
            map { $sth->bind_param($param++, $_) } keys %seen_id;
            $sth->bind_param($param++, $message->{timestamp});
            $sth->bind_param($param++, $before);
            $sth->execute;
            return [reverse @{$sth->fetchall_arrayref({})}];
        };

        $self->{pbot}->{logger}->log($@) if $@;
    }

    if (defined $after and $after > 0) {
        $messages_after = eval {
            $sql .= ' AND timestamp > ? AND mode = 0 ORDER BY timestamp ASC LIMIT ?';
            my $sth = $self->{dbh}->prepare($sql);
            my $param = 1;
            $sth->bind_param($param++, $message->{channel});
            map { $sth->bind_param($param++, $_) } keys %seen_id;
            $sth->bind_param($param++, $message->{timestamp});
            $sth->bind_param($param++, $after);
            $sth->execute;
            return $sth->fetchall_arrayref({});
        };

        $self->{pbot}->{logger}->log($@) if $@;
    }

    my @messages;
    push(@messages, @$messages_before) if defined $messages_before;
    push(@messages, @$messages_count)  if defined $messages_count;
    push(@messages, $message);
    push(@messages, @$messages_after) if defined $messages_after;

    return \@messages;
}

sub recall_message_by_count {
    my ($self, $id, $channel, $count, $ignore_command, $use_aliases) = @_;

    my $messages = eval {
        my $sql = 'SELECT * FROM Messages WHERE ';

        my %seen_id;

        if (defined $id) {
            my %akas;

            if (defined $use_aliases) {
                %akas = $self->get_also_known_as($use_aliases);
            } else {
                $akas{$id} = {
                    id         => $id,
                    type       => $self->{alias_type}->{STRONG},
                    nickchange => 0,
                };
            }

            foreach my $aka (keys %akas) {
                next if $akas{$aka}->{type} == $self->{alias_type}->{WEAK};
                next if $akas{$aka}->{nickchange} == 1;
                next if exists $seen_id{$akas{$aka}->{id}};

                $seen_id{$akas{$aka}->{id}} = 1;
            }

            my $ids = join " OR ", map { "id = ?" } keys %seen_id;

            $sql .= "($ids) AND ";
        }

        $sql .= 'channel = ? ORDER BY timestamp DESC LIMIT 10 OFFSET ?';

        my $sth   = $self->{dbh}->prepare($sql);

        my $param = 1;
        map { $sth->bind_param($param++, $_) } keys %seen_id;
        $sth->bind_param($param++, $channel);
        $sth->bind_param($param++, $count);
        $sth->execute;
        return $sth->fetchall_arrayref({});
    };

    $self->{pbot}->{logger}->log($@) if $@;

    if (defined $ignore_command) {
        my $botnick     = $self->{pbot}->{registry}->get_value('irc',     'botnick');
        my $bot_trigger = $self->{pbot}->{registry}->get_value('general', 'trigger');
        foreach my $message (@$messages) {
            next if $message->{msg} =~ m/^$botnick.? $ignore_command/ or $message->{msg} =~ m/^$bot_trigger$ignore_command/;
            return $message;
        }

        return undef;
    }

    return $messages->[0];
}

sub recall_message_by_text {
    my ($self, $id, $channel, $text, $ignore_command, $use_aliases) = @_;

    my $search = "%$text%";
    $search =~ s/(?<!\\)\.?\*/%/g;
    $search =~ s/(?<!\\)\?/_/g;

    my $messages = eval {
        my $sql = 'SELECT * FROM Messages WHERE channel = ? AND msg LIKE ? ESCAPE "\" ';

        my %seen_id;

        if (defined $id) {
            my %akas;

            if (defined $use_aliases) {
                %akas = $self->get_also_known_as($use_aliases);
            } else {
                $akas{$id} = {
                    id         => $id,
                    type       => $self->{alias_type}->{STRONG},
                    nickchange => 0,
                };
            }

            foreach my $aka (keys %akas) {
                next if $akas{$aka}->{type} == $self->{alias_type}->{WEAK};
                next if $akas{$aka}->{nickchange} == 1;
                next if exists $seen_id{$akas{$aka}->{id}};

                $seen_id{$akas{$aka}->{id}} = 1;
            }

            my $ids = join " OR ", map { "id = ?" } keys %seen_id;

            $sql .= "AND ($ids) ";
        }

        $sql .= 'ORDER BY timestamp DESC LIMIT 10';

        my $sth   = $self->{dbh}->prepare($sql);

        my $param = 1;
        $sth->bind_param($param++, $channel);
        $sth->bind_param($param++, $search);

        map { $sth->bind_param($param++, $_) } keys %seen_id;

        $sth->execute;
        return $sth->fetchall_arrayref({});
    };

    $self->{pbot}->{logger}->log($@) if $@;

    if (defined $ignore_command) {
        my $bot_trigger = $self->{pbot}->{registry}->get_value('general', 'trigger');
        my $botnick     = $self->{pbot}->{registry}->get_value('irc',     'botnick');
        foreach my $message (@$messages) {
            next
              if $message->{msg} =~ m/^$botnick.? $ignore_command/i
              or $message->{msg} =~ m/^(?:\s*[^,:\(\)\+\*\/ ]+[,:]?\s+)?$bot_trigger$ignore_command/i
              or $message->{msg} =~ m/^\s*$ignore_command.? $botnick$/i;
            return $message;
        }

        return undef;
    }

    return $messages->[0];
}

sub get_random_message {
    my ($self, $id, $channel, $use_aliases) = @_;

    my $message = eval {
        my $sql = 'SELECT * FROM Messages WHERE channel = ? AND mode = ? ';

        my %seen_id;

        if (defined $id) {
            my %akas;

            if (defined $use_aliases) {
                %akas = $self->get_also_known_as($use_aliases);
            } else {
                $akas{$id} = {
                    id         => $id,
                    type       => $self->{alias_type}->{STRONG},
                    nickchange => 0,
                };
            }

            foreach my $aka (keys %akas) {
                next if $akas{$aka}->{type} == $self->{alias_type}->{WEAK};
                next if $akas{$aka}->{nickchange} == 1;
                next if exists $seen_id{$akas{$aka}->{id}};

                $seen_id{$akas{$aka}->{id}} = 1;
            }

            my $ids = join " OR ", map { "id = ?" } keys %seen_id;

            $sql .= "AND ($ids) ";
        }

        $sql .= 'ORDER BY RANDOM() LIMIT 1';

        my $sth   = $self->{dbh}->prepare($sql);

        my $param = 1;
        $sth->bind_param($param++, $channel);
        $sth->bind_param($param++, MSG_CHAT);

        map { $sth->bind_param($param++, $_) } keys %seen_id;

        $sth->execute;

        return $sth->fetchrow_hashref;
    };

    $self->{pbot}->{logger}->log($@) if $@;

    return $message;
}

sub get_max_messages {
    my ($self, $id, $channel, $use_aliases) = @_;

    my $count = eval {
        my $sql = 'SELECT COUNT(*) FROM Messages WHERE channel = ? AND ';

        my %akas;

        if (defined $use_aliases) {
            %akas = $self->get_also_known_as($use_aliases);
        } else {
            $akas{$id} = {
                id         => $id,
                type       => $self->{alias_type}->{STRONG},
                nickchange => 0,
            };
        }

        my %seen_id;

        foreach my $aka (keys %akas) {
            next if $akas{$aka}->{type} == $self->{alias_type}->{WEAK};
            next if $akas{$aka}->{nickchange} == 1;
            next if exists $seen_id{$akas{$aka}->{id}};

            $seen_id{$akas{$aka}->{id}} = 1;
        }

        my $ids = join " OR ", map { "id = ?" } keys %seen_id;

        $sql .= "($ids)";

        my $sth   = $self->{dbh}->prepare($sql);
        my $param = 1;
        $sth->bind_param($param++, $channel);

        map { $sth->bind_param($param++, $_) } keys %seen_id;

        $sth->execute;
        return $sth->fetchrow_hashref->{'COUNT(*)'};
    };

    $self->{pbot}->{logger}->log($@) if $@;
    $count = 0 if not defined $count;
    return $count;
}

sub create_channel {
    my ($self, $id, $channel) = @_;

    eval {
        my $sth = $self->{dbh}->prepare('INSERT OR IGNORE INTO Channels VALUES (?, ?, 0, 0, 0, 0, 0, 0, 0, 0)');
        my $rv  = $sth->execute($id, $channel);
        $self->{new_entries}++;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub get_channels {
    my ($self, $id) = @_;

    my $channels = eval {
        my $sth = $self->{dbh}->prepare('SELECT channel FROM Channels WHERE id = ?');
        $sth->execute($id);
        return $sth->fetchall_arrayref();
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return map { $_->[0] } @$channels;
}

sub get_channel_data {
    my ($self, $id, $channel, @columns) = @_;

    $self->create_channel($id, $channel);

    my $channel_data = eval {
        my $sql = 'SELECT ';

        if (not @columns) { $sql .= '*'; }
        else {
            my $comma = '';
            foreach my $column (@columns) {
                $sql .= "$comma$column";
                $comma = ', ';
            }
        }

        $sql .= ' FROM Channels WHERE id = ? AND channel = ?';
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute($id, $channel);
        return $sth->fetchrow_hashref();
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return $channel_data;
}

sub update_channel_data {
    my ($self, $id, $channel, $data) = @_;

    $self->create_channel($id, $channel);

    eval {
        my $sql = 'UPDATE Channels SET ';

        my $comma = '';
        foreach my $key (keys %$data) {
            $sql .= "$comma$key = ?";
            $comma = ', ';
        }

        $sql .= ' WHERE id = ? AND channel = ?';

        my $sth = $self->{dbh}->prepare($sql);

        my $param = 1;
        foreach my $key (keys %$data) { $sth->bind_param($param++, $data->{$key}); }

        $sth->bind_param($param++, $id);
        $sth->bind_param($param,   $channel);
        $sth->execute();
        $self->{new_entries}++;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub get_channel_datas_where_last_offense_older_than {
    my ($self, $timestamp) = @_;

    my $channel_datas = eval {
        my $sth = $self->{dbh}->prepare('SELECT id, channel, offenses, last_offense, unbanmes FROM Channels WHERE last_offense > 0 AND last_offense <= ?');
        $sth->execute($timestamp);
        return $sth->fetchall_arrayref({});
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return $channel_datas;
}

sub get_channel_datas_with_enter_abuses {
    my ($self) = @_;

    my $channel_datas = eval {
        my $sth = $self->{dbh}->prepare('SELECT id, channel, enter_abuses, last_offense FROM Channels WHERE enter_abuses > 0');
        $sth->execute();
        return $sth->fetchall_arrayref({});
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return $channel_datas;
}

sub devalidate_channel {
    my ($self, $id, $channel, $mode) = @_;

    $mode = 0 if not defined $mode;

    eval {
        my $sth = $self->{dbh}->prepare("UPDATE Channels SET validated = ? WHERE id = ? AND channel = ?");
        $sth->execute($mode, $id, $channel);
        $self->{new_entries}++;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub devalidate_all_channels {
    my ($self, $id, $mode) = @_;

    $mode = 0 if not defined $mode;

    my $where = '';
    $where = 'WHERE id = ?' if defined $id;

    eval {
        my $sth = $self->{dbh}->prepare("UPDATE Channels SET validated = ? $where");
        $sth->bind_param(1, $mode);
        $sth->bind_param(2, $id) if defined $id;
        $sth->execute();
        $self->{new_entries}++;
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub link_aliases {
    my ($self, $account, $hostmask, $nickserv) = @_;

    my $debug_link = $self->{pbot}->{registry}->get_value('messagehistory', 'debug_link');

    $self->{pbot}->{logger}->log("Linking [$account][" . ($hostmask ? $hostmask : 'undef') . "][" . ($nickserv ? $nickserv : 'undef') . "]\n") if $debug_link >= 3;

    eval {
        my %ids;

        if ($hostmask) {
            my ($nick, $host) = $hostmask =~ /^([^!]+)![^@]+@(.*)$/;
            my $sth = $self->{dbh}->prepare('SELECT id, last_seen FROM Hostmasks WHERE host = ?');
            $sth->execute($host);
            my $rows = $sth->fetchall_arrayref({});

            my $now = time;

            foreach my $row (@$rows) {
                my $idhost = $self->find_most_recent_hostmask($row->{id}) if $debug_link >= 2 && $row->{id} != $account;
                if ($now - $row->{last_seen} <= 60 * 60 * 48) {
                    $ids{$row->{id}} = {id => $row->{id}, type => $self->{alias_type}->{STRONG}, force => 1};
                    $self->{pbot}->{logger}->log("found STRONG matching id $row->{id} ($idhost) for host [$host]\n") if $debug_link >= 2 && $row->{id} != $account;
                } else {
                    $ids{$row->{id}} = {id => $row->{id}, type => $self->{alias_type}->{WEAK}};
                    $self->{pbot}->{logger}->log("found WEAK matching id $row->{id} ($idhost) for host [$host]\n") if $debug_link >= 2 && $row->{id} != $account;
                }
            }

            unless ($nick =~ m/^Guest\d+$/) {
                my $sth = $self->{dbh}->prepare('SELECT id, hostmask FROM Hostmasks WHERE nick = ?');
                $sth->execute($nick);
                my $rows = $sth->fetchall_arrayref({});

                my ($account1) = $host =~ m{/([^/]+)$};
                $account1 = '' if not defined $account1;

                my $hostip = undef;
                if ($host =~ m/(\d+[[:punct:]]\d+[[:punct:]]\d+[[:punct:]]\d+)\D/) {
                    $hostip = $1;
                    $hostip =~ s/[[:punct:]]/./g;
                }

                foreach my $row (@$rows) {
                    next if $row->{id} == $account;
                    $self->{pbot}->{logger}->log("Processing row $row->{hostmask}\n");
                    my ($thost) = $row->{hostmask} =~ m/@(.*)$/;

                    if ($thost =~ m{/}) {
                        my ($account2) = $thost =~ m{/([^/]+)$};

                        if ($account1 ne $account2) {
                            $self->{pbot}->{logger}->log("Skipping non-matching cloaked hosts: $host vs $thost\n");
                            next;
                        } else {
                            $self->{pbot}->{logger}->log("Cloaked hosts match: $host vs $thost\n");
                            $ids{$row->{id}} = {id => $row->{id}, type => $self->{alias_type}->{STRONG}, force => 1};
                        }
                    }

                    my $distance = fastdistance($host, $thost);
                    my $length   = (length($host) > length($thost)) ? length $host : length $thost;

                    #$self->{pbot}->{logger}->log("distance: " . ($distance / $length) . " -- $host vs $thost\n") if $length != 0;

                    if ($length != 0 && $distance / $length < 0.50) {
                        $self->{pbot}->{logger}->log("11: distance match: $host vs $thost == " . ($distance / $length) . "\n");
                        $ids{$row->{id}} = {id => $row->{id}, type => $self->{alias_type}->{STRONG}};    # don't force linking
                        $self->{pbot}->{logger}->log("found STRONG matching id $row->{id} ($row->{hostmask}) for nick [$nick]\n") if $debug_link >= 2;
                    } else {
                        # handle cases like 99.57.140.149 vs 99-57-140-149.lightspeed.sntcca.sbcglobal.net
                        if (defined $hostip) {
                            if ($hostip eq $thost) {
                                $ids{$row->{id}} = {id => $row->{id}, type => $self->{alias_type}->{STRONG}};    # don't force linking
                                $self->{pbot}->{logger}->log("IP vs hostname match: $host vs $thost\n");
                            }
                        } elsif ($thost =~ m/(\d+[[:punct:]]\d+[[:punct:]]\d+[[:punct:]]\d+)\D/) {
                            my $thostip = $1;
                            $thostip =~ s/[[:punct:]]/./g;
                            if ($thostip eq $host) {
                                $ids{$row->{id}} = {id => $row->{id}, type => $self->{alias_type}->{STRONG}};    # don't force linking
                                $self->{pbot}->{logger}->log("IP vs hostname match: $host vs $thost\n");
                            }
                        }
                    }
                }
            }
        }

        if ($nickserv) {
            my $sth = $self->{dbh}->prepare('SELECT id FROM Nickserv WHERE nickserv = ?');
            $sth->execute($nickserv);
            my $rows = $sth->fetchall_arrayref({});

            foreach my $row (@$rows) {
                my $idhost = $self->find_most_recent_hostmask($row->{id}) if $debug_link >= 2 && $row->{id} != $account;
                $ids{$row->{id}} = {id => $row->{id}, type => $self->{alias_type}->{STRONG}, force => 1};
                $self->{pbot}->{logger}->log("12: found STRONG matching id $row->{id} ($idhost) for nickserv [$nickserv]\n") if $debug_link >= 2 && $row->{id} != $account;
            }
        }

        foreach my $id (sort keys %ids) {
            next if $account == $id;
            $self->link_alias($account, $id, $ids{$id}->{type}, $ids{$id}->{force});
        }
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub link_alias {
    my ($self, $id, $alias, $type, $force) = @_;

    my $debug_link = $self->{pbot}->{registry}->get_value('messagehistory', 'debug_link');

    $self->{pbot}->{logger}
      ->log("Attempting to " . ($force ? "forcefully " : "") . ($type == $self->{alias_type}->{STRONG} ? "strongly" : "weakly") . " link $id to $alias\n")
      if $debug_link >= 3;

    my $ret = eval {
        my $sth = $self->{dbh}->prepare('SELECT type FROM Aliases WHERE id = ? AND alias = ? LIMIT 1');
        $sth->execute($alias, $id);

        my $row = $sth->fetchrow_hashref();

        if (defined $row) {
            if ($force) {
                if ($row->{'type'} != $type) {
                    $self->{pbot}->{logger}->log("$id already " . ($row->{'type'} == $self->{alias_type}->{STRONG} ? "strongly" : "weakly") . " linked to $alias, forcing override\n")
                      if $debug_link >= 1;

                    $sth = $self->{dbh}->prepare('UPDATE Aliases SET type = ? WHERE alias = ? AND id = ?');
                    $sth->execute($type, $id,    $alias);
                    $sth->execute($type, $alias, $id);
                    return 1;
                } else {
                    $self->{pbot}->{logger}->log("$id already " . ($row->{'type'} == $self->{alias_type}->{STRONG} ? "strongly" : "weakly") . " linked to $alias, ignoring\n")
                      if $debug_link >= 4;
                    return 0;
                }
            } else {
                $self->{pbot}->{logger}->log("$id already " . ($row->{'type'} == $self->{alias_type}->{STRONG} ? "strongly" : "weakly") . " linked to $alias, ignoring\n")
                  if $debug_link >= 4;
                return 0;
            }
        }

        $sth = $self->{dbh}->prepare('INSERT INTO Aliases VALUES (?, ?, ?)');
        $sth->execute($alias, $id,    $type);
        $sth->execute($id,    $alias, $type);
        return 1;
    };
    $self->{pbot}->{logger}->log($@) if $@;

    my $host1 = $self->find_most_recent_hostmask($id);
    my $host2 = $self->find_most_recent_hostmask($alias);

    $self->{pbot}->{logger}->log(($type == $self->{alias_type}->{STRONG} ? "Strongly" : "Weakly") . " linked $id ($host1) to $alias ($host2).\n") if $ret and $debug_link;

    if ($ret) {
        $host1 = lc $host1;
        $host2 = lc $host2;
        my ($nick1) = $host1 =~ m/^([^!]+)!/;
        my ($nick2) = $host2 =~ m/^([^!]+)!/;
        my $distance = fastdistance($nick1, $nick2);
        my $length   = (length $nick1 > length $nick2) ? length $nick1 : length $nick2;
        my $irc_cloak = $self->{pbot}->{registry}->get_value('irc', 'cloak') // 'user';
        if ($distance > 1 && ($nick1 !~ /^guest/ && $nick2 !~ /^guest/) && ($host1 !~ /$irc_cloak/ || $host2 !~ /$irc_cloak/)) {
            $self->{pbot}->{logger}->log("[$nick1][$nick2] $distance / $length\n");
            $self->{pbot}->{logger}->log("Possible bogus link: ($id) $host1 vs ($alias) $host2\n");
        }
    }

    return $ret;
}

sub unlink_alias {
    my ($self, $id, $alias) = @_;

    my $ret = eval {
        my $ret = 0;
        my $sth = $self->{dbh}->prepare('DELETE FROM Aliases WHERE id = ? AND alias = ?');
        $sth->execute($id, $alias);
        if ($sth->rows) {
            $self->{new_entries}++;
            $ret = 1;
        }

        $sth->execute($alias, $id);
        if ($sth->rows) {
            $self->{new_entries}++;
            $ret = 1;
        } else {
            $ret = 0;
        }
        return $ret;
    };
    $self->{pbot}->{logger}->log($@) if $@;
    return $ret;
}

sub vacuum {
    my $self = shift;

    eval { $self->{dbh}->commit(); };

    $self->{pbot}->{logger}->log("SQLite error $@ when committing $self->{new_entries} entries.\n") if $@;

    $self->{dbh}->do("VACUUM");

    $self->{dbh}->begin_work();
    $self->{new_entries} = 0;
}

sub rebuild_aliases_table {
    my $self = shift;

    eval {
        $self->{dbh}->do('DELETE FROM Aliases');
        $self->vacuum;

        my $sth = $self->{dbh}->prepare('SELECT id, hostmask FROM Hostmasks ORDER BY id');
        $sth->execute();
        my $rows = $sth->fetchall_arrayref({});

        $sth = $self->{dbh}->prepare('SELECT nickserv FROM Nickserv WHERE id = ?');

        foreach my $row (@$rows) {
            $self->{pbot}->{logger}->log("Link [$row->{id}][$row->{hostmask}]\n");

            $self->link_aliases($row->{id}, $row->{hostmask});

            $sth->execute($row->{id});
            my $nrows = $sth->fetchall_arrayref({});

            foreach my $nrow (@$nrows) { $self->link_aliases($row->{id}, undef, $nrow->{nickserv}); }
        }
    };

    $self->{pbot}->{logger}->log($@) if $@;
}

sub get_also_known_as {
    my ($self, $nick, $dont_use_aliases_table) = @_;
    my $debug = $self->{pbot}->{registry}->get_value('messagehistory', 'debug_aka');

    $self->{pbot}->{logger}->log("Looking for AKAs for nick [$nick]\n") if $debug;

    my %akas = eval {
        my (%akas, %hostmasks, %ids);

        unless ($dont_use_aliases_table) {
            my ($id, $hostmask) = $self->find_message_account_by_nick($nick);

            if (not defined $id) { return %akas; }

            $ids{$id} = {id => $id, type => $self->{alias_type}->{STRONG}};
            $self->{pbot}->{logger}->log("Adding $id -> $id\n") if $debug;

            my $sth = $self->{dbh}->prepare('SELECT alias, type FROM Aliases WHERE id = ?');
            $sth->execute($id);
            my $rows = $sth->fetchall_arrayref({});

            foreach my $row (@$rows) {
                # next if $row->{type} == $self->{alias_type}->{WEAK};
                $ids{$row->{alias}} = {id => $id, type => $row->{type}};
                $self->{pbot}->{logger}->log("[$id] 1) Adding $row->{alias} -> $id [type $row->{type}]\n") if $debug;
            }

            my %seen_id;
            $sth = $self->{dbh}->prepare('SELECT id, type FROM Aliases WHERE alias = ?');

            while (1) {
                my $new_aliases = 0;
                foreach my $id (keys %ids) {
                    next if $ids{$id}->{type} == $self->{alias_type}->{WEAK};
                    next if exists $seen_id{$id};
                    $seen_id{$id} = $id;

                    $sth->execute($id);
                    my $rows = $sth->fetchall_arrayref({});

                    foreach my $row (@$rows) {
                        next if exists $ids{$row->{id}};

                        #next if $row->{type} == $self->{alias_type}->{WEAK};
                        $ids{$row->{id}} = {id => $id, type => $ids{$id}->{type} == $self->{alias_type}->{WEAK} ? $self->{alias_type}->{WEAK} : $row->{type}};
                        $new_aliases++;
                        $self->{pbot}->{logger}->log("[$id] 2) Adding $row->{id} -> $id [type $row->{type}]\n") if $debug;
                    }
                }
                last if not $new_aliases;
            }

            my $hostmask_sth = $self->{dbh}->prepare('SELECT hostmask, nickchange, last_seen FROM Hostmasks WHERE id = ?');
            my $nickserv_sth = $self->{dbh}->prepare('SELECT nickserv FROM Nickserv WHERE id = ?');
            my $gecos_sth    = $self->{dbh}->prepare('SELECT gecos FROM Gecos WHERE id = ?');

            my $csv = Text::CSV->new({binary => 1});

            foreach my $id (keys %ids) {
                $hostmask_sth->execute($id);
                $rows = $hostmask_sth->fetchall_arrayref({});

                foreach my $row (@$rows) {
                    my ($nick, $user, $host) = $row->{hostmask} =~ m/^([^!]+)!([^@]+)@(.*)/;
                    $akas{$row->{hostmask}} = {
                        id => $id,
                        alias => $ids{$id}->{id},
                        nick => $nick,
                        user => $user,
                        host => $host,
                        hostmask => $row->{hostmask},
                        type => $ids{$id}->{type},
                        nickchange => $row->{nickchange},
                        last_seen => $row->{last_seen},
                    };

                    $self->{pbot}->{logger}->log("[$id] Adding hostmask $row->{hostmask} -> $ids{$id}->{id} [type $ids{$id}->{type}]\n") if $debug;
                }

                $nickserv_sth->execute($id);
                $rows = $nickserv_sth->fetchall_arrayref({});

                foreach my $row (@$rows) {
                    foreach my $aka (keys %akas) {
                        if ($akas{$aka}->{id} == $id) {
                            if (exists $akas{$aka}->{nickserv}) { $akas{$aka}->{nickserv} .= ",$row->{nickserv}"; }
                            else                                { $akas{$aka}->{nickserv} = $row->{nickserv}; }
                        }
                    }
                }

                $gecos_sth->execute($id);
                $rows = $gecos_sth->fetchall_arrayref({});

                foreach my $row (@$rows) {
                    foreach my $aka (keys %akas) {
                        if ($akas{$aka}->{id} == $id) {
                            if (exists $akas{$aka}->{gecos}) {
                                $csv->parse($akas{$aka}->{gecos});
                                my @gecos = $csv->fields;
                                push @gecos, $row->{gecos};
                                $csv->combine(@gecos);
                                $akas{$aka}->{gecos} = $csv->string;
                            } else {
                                my @gecos = ($row->{gecos});
                                $csv->combine(@gecos);
                                $akas{$aka}->{gecos} = $csv->string;
                            }
                        }
                    }
                }
            }

            return %akas;
        }

        my $sth = $self->{dbh}->prepare('SELECT id, hostmask FROM Hostmasks WHERE nick = ? ORDER BY last_seen DESC');
        $sth->execute($nick);
        my $rows = $sth->fetchall_arrayref({});

        foreach my $row (@$rows) {
            $hostmasks{$row->{hostmask}} = $row->{id};
            $ids{$row->{id}}             = $row->{hostmask};
            $akas{$row->{hostmask}}      = {hostmask => $row->{hostmask}, id => $row->{id}};
            $self->{pbot}->{logger}->log("Found matching nick [$nick] for hostmask $row->{hostmask} with id $row->{id}\n");
        }

        foreach my $hostmask (keys %hostmasks) {
            my ($host) = $hostmask =~ /(\@.*)$/;
            $sth = $self->{dbh}->prepare('SELECT id FROM Hostmasks WHERE host = ?');
            $sth->execute($host);
            $rows = $sth->fetchall_arrayref({});

            foreach my $row (@$rows) {
                next if exists $ids{$row->{id}};
                $ids{$row->{id}} = $row->{id};

                $sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE id == ?');
                $sth->execute($row->{id});
                my $rows = $sth->fetchall_arrayref({});

                foreach my $nrow (@$rows) {
                    next if exists $akas{$nrow->{hostmask}};
                    $akas{$nrow->{hostmask}} = {hostmask => $nrow->{hostmask}, id => $row->{id}};
                    $self->{pbot}->{logger}->log("Adding matching host [$hostmask] and id [$row->{id}] AKA hostmask $nrow->{hostmask}\n");
                }
            }
        }

        my %nickservs;
        foreach my $id (keys %ids) {
            $sth = $self->{dbh}->prepare('SELECT nickserv FROM Nickserv WHERE id == ?');
            $sth->execute($id);
            $rows = $sth->fetchall_arrayref({});

            foreach my $row (@$rows) { $nickservs{$row->{nickserv}} = $id; }
        }

        foreach my $nickserv (sort keys %nickservs) {
            foreach my $aka (keys %akas) {
                if ($akas{$aka}->{id} == $nickservs{$nickserv}) {
                    if (exists $akas{$aka}->{nickserv}) { $akas{$aka}->{nickserv} .= ",$nickserv"; }
                    else                                { $akas{$aka}->{nickserv} = $nickserv; }
                }
            }

            $sth = $self->{dbh}->prepare('SELECT id FROM Nickserv WHERE nickserv == ?');
            $sth->execute($nickserv);
            $rows = $sth->fetchall_arrayref({});

            foreach my $row (@$rows) {
                next if exists $ids{$row->{id}};
                $ids{$row->{id}} = $row->{id};

                $sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE id == ?');
                $sth->execute($row->{id});
                my $rows = $sth->fetchall_arrayref({});

                foreach my $nrow (@$rows) {
                    if (exists $akas{$nrow->{hostmask}}) {
                        if (exists $akas{$nrow->{hostmask}}->{nickserv}) { $akas{$nrow->{hostmask}}->{nickserv} .= ",$nickserv"; }
                        else                                             { $akas{$nrow->{hostmask}}->{nickserv} = $nickserv; }
                    } else {
                        $akas{$nrow->{hostmask}} = {hostmask => $nrow->{hostmask}, id => $row->{id}, nickserv => $nickserv};
                        $self->{pbot}->{logger}->log("Adding matching nickserv [$nickserv] and id [$row->{id}] AKA hostmask $nrow->{hostmask}\n");
                    }
                }
            }
        }

        foreach my $id (keys %ids) {
            $sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE id == ?');
            $sth->execute($id);
            $rows = $sth->fetchall_arrayref({});

            foreach my $row (@$rows) {
                next if exists $akas{$row->{hostmask}};
                $akas{$row->{hostmask}} = {hostmask => $row->{hostmask}, id => $id};
                $self->{pbot}->{logger}->log("Adding matching id [$id] AKA hostmask $row->{hostmask}\n");
            }
        }

        return %akas;
    };

    $self->{pbot}->{logger}->log("bad aka: $@") if $@;
    return %akas;
}

sub get_ancestor_id {
    my ($self, $id) = @_;

    $id = 0 if not defined $id;

    my $ancestor = eval {
        my $sth = $self->{dbh}->prepare('SELECT id FROM Aliases WHERE alias = ? ORDER BY id LIMIT 1');
        $sth->execute($id);
        my $row = $sth->fetchrow_hashref();
        return defined $row ? $row->{id} : 0;
    };

    $self->{pbot}->{logger}->log($@) if $@;

    return $id if not $ancestor;
    return $ancestor < $id ? $ancestor : $id;
}

# End of public API, the remaining are internal support routines for this module

sub get_new_account_id {
    my $self = shift;

    my $id = eval {
        my $sth = $self->{dbh}->prepare('SELECT id FROM Accounts ORDER BY id DESC LIMIT 1');
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        return $row->{id};
    };

    $self->{pbot}->{logger}->log($@) if $@;
    return ++$id;
}

sub get_message_account_id {
    my ($self, $mask) = @_;

    my $id = eval {
        my $sth = $self->{dbh}->prepare('SELECT id FROM Hostmasks WHERE hostmask == ?');
        $sth->execute($mask);
        my $row = $sth->fetchrow_hashref();
        return $row->{id};
    };

    $self->{pbot}->{logger}->log($@) if $@;
    #$self->{pbot}->{logger}->log("get_message_account_id: returning id [". (defined $id ? $id: 'undef') . "] for mask [$mask]\n");
    return $id;
}

sub commit_message_history {
    my ($self) = @_;

    return if not $self->{dbh};
    return if $self->{pbot}->{child};  # don't commit() as child of fork()

    if ($self->{new_entries} > 0) {
        # $self->{pbot}->{logger}->log("Commiting $self->{new_entries} messages to SQLite\n");
        eval { $self->{dbh}->commit(); };

        $self->{pbot}->{logger}->log("SQLite error $@ when committing $self->{new_entries} entries.\n") if $@;

        $self->{dbh}->begin_work();
        $self->{new_entries} = 0;
    }
}

1;
