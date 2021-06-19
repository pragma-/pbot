# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::RemindMe;
use parent 'Plugins::Plugin';

use PBot::Imports;

use DBI;
use Time::Duration qw/concise duration/;
use Time::HiRes qw/gettimeofday/;
use Getopt::Long qw(GetOptionsFromArray);

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->cmd_remindme(@_) }, 'remindme', 0);
    $self->{filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/reminders.sqlite3';
    $self->dbi_begin;
    $self->create_database;
    $self->enqueue_reminders;
}

sub unload {
    my $self = shift;
    $self->dbi_end;
    $self->{pbot}->{commands}->unregister('remindme');
    $self->{pbot}->{timer}->dequeue_event('reminder .*');
}

sub enqueue_reminders {
    my ($self) = @_;

    return if not $self->{dbh};

    my $reminders = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Reminders');
        $sth->execute;
        return $sth->fetchall_arrayref({});
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Enqueue reminders failed: $@");
        return;
    }

    foreach my $reminder (@$reminders) {
        # delete this reminder if it's expired by 31 days
        if (gettimeofday - $reminder->{alarm} >= 86400 * 31) {
            $self->{pbot}->{logger}->log("Deleting expired reminder: $reminder->{id}) $reminder->{text} set by $reminder->{created_by}\n");
            $self->delete_reminder($reminder->{id});
            next;
        }

        my $timeout = $reminder->{alarm} - gettimeofday;
        $timeout = 10 if $timeout < 10;
        my $repeating = $reminder->{repeat};

        $self->{pbot}->{timer}->enqueue_event(
            sub {
                my ($event) = @_;
                $self->do_reminder($reminder->{id}, $event);
            },
            $timeout, "reminder $reminder->{id}", $repeating
        );
    }
}

sub create_database {
    my $self = shift;
    return if not $self->{dbh};

    eval {
        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Reminders (
  id          INTEGER PRIMARY KEY,
  account     TEXT,
  target      TEXT,
  text        TEXT,
  alarm       NUMERIC,
  repeat      INTEGER,
  duration    NUMERIC,
  created_on  NUMERIC,
  created_by  TEXT
)
SQL
    };

    $self->{pbot}->{logger}->log("RemindMe: create database failed: $@") if $@;
}

sub dbi_begin {
    my ($self) = @_;
    eval {
        $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", {RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1, sqlite_unicode => 1})
          or die $DBI::errstr;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error opening RemindMe database: $@");
        delete $self->{dbh};
        return 0;
    } else {
        return 1;
    }
}

sub dbi_end {
    my ($self) = @_;
    return if not $self->{dbh};
    $self->{dbh}->disconnect;
    delete $self->{dbh};
}

sub add_reminder {
    my ($self, $account, $target, $text, $alarm, $duration, $repeat, $owner) = @_;

    my $id = eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Reminders (account, target, text, alarm, duration, repeat, created_on, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
        $sth->execute($account, $target, $text, $alarm, $duration, $repeat, scalar gettimeofday, $owner);
        return $self->{dbh}->sqlite_last_insert_rowid;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Add reminder failed: $@");
        return 0;
    }

    $self->{pbot}->{timer}->enqueue_event(
        sub {
            my ($event) = @_;
            $self->do_reminder($id, $event);
        },
        $duration, "reminder $id", $repeat
    );

    return $id;
}

sub delete_reminder {
    my ($self, $id) = @_;
    return if not $self->{dbh};

    eval {
        my $sth = $self->{dbh}->prepare('DELETE FROM Reminders WHERE id = ?');
        $sth->execute($id);
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Delete reminder $id failed: $@");
        return 0;
    }

    $self->{pbot}->{timer}->dequeue_event("reminder $id");
    return 1;
}

sub update_reminder {
    my ($self, $id, $data) = @_;

    eval {
        my $sql = 'UPDATE Reminders SET ';

        my $comma = '';
        foreach my $key (keys %$data) {
            $sql .= "$comma$key = ?";
            $comma = ', ';
        }

        $sql .= ' WHERE id = ?';

        my $sth = $self->{dbh}->prepare($sql);

        my $param = 1;
        foreach my $key (keys %$data) { $sth->bind_param($param++, $data->{$key}); }

        $sth->bind_param($param++, $id);
        $sth->execute();
    };
    $self->{pbot}->{logger}->log($@) if $@;
}

sub get_reminder {
    my ($self, $id) = @_;

    my $reminder = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Reminders WHERE id = ?');
        $sth->execute($id);
        return $sth->fetchrow_hashref();
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Get reminder failed: $@");
        return undef;
    }
    return $reminder;
}

sub get_reminders {
    my ($self, $account) = @_;

    my $reminders = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Reminders WHERE account = ? ORDER BY id');
        $sth->execute($account);
        return $sth->fetchall_arrayref({});
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Get reminders failed: $@");
        return [];
    }

    return $reminders;
}

sub do_reminder {
    my ($self, $id, $event) = @_;

    my $reminder = $self->get_reminder($id);

    if (not defined $reminder) {
        $self->{pbot}->{logger}->log("Queued reminder $id no longer exists.\n");
        $event->{repeating} = 0;
        return;
    }

    my $nick;
    if (not defined $reminder->{target}) {
        # ensures we get the current nick of the person
        my $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($reminder->{account});
        ($nick) = $hostmask =~ /^([^!]+)!/;

        # try again if the person isn't around yet
        if (not $self->{pbot}->{nicklist}->is_present_any_channel($nick)) {
            $event->{interval} = 300;
            $event->{repeating} = 1;
            return;
        }
    }

    my $text = "Reminder: $reminder->{text}";
    my $target = $reminder->{target} // $nick;
    $self->{pbot}->{conn}->privmsg($target, $text);

    $self->{pbot}->{logger}->log("Reminded $target about \"$text\"\n");

    if ($reminder->{repeat} > 0) {
        $reminder->{repeat}--;
        $reminder->{alarm} = gettimeofday + $reminder->{duration};
        my $data = { repeat => $reminder->{repeat}, alarm => $reminder->{alarm} };
        $self->update_reminder($reminder->{id}, $data);
        $event->{interval} = $reminder->{duration};
        $event->{repeating} = 1;
    } else {
        $self->delete_reminder($reminder->{id});
        $event->{repeating} = 0;
    }
}

sub cmd_remindme {
    my ($self, $context) = @_;

    if (not $self->{dbh}) { return "Internal error."; }

    my $usage = "Usage: remindme [-c channel] [-r count]  message -t time | remindme -l [nick] | remindme -d id";

    return $usage if not length $context->{arguments};

    my ($target, $repeat, $text, $alarm, $list_reminders, $delete_id);

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling");

    my @opt_args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);
    use Data::Dumper;
    print "args: [$context->{arguments}]\n";
    print Dumper \@opt_args;
    GetOptionsFromArray(
        \@opt_args,
        'r:i' => \$repeat,
        't:s' => \$alarm,
        'c:s' => \$target,
        'm:s' => \$text,
        'l:s' => \$list_reminders,
        'd:i' => \$delete_id
    );

    return "$getopt_error -- $usage" if defined $getopt_error;

    if (defined $list_reminders) {
        my $nick_override = $list_reminders if length $list_reminders;
        my $account;
        if ($nick_override) {
            my $hostmask;
            ($account, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick_override);

            if (not $account) { return "I don't know anybody named $nick_override."; }

            ($nick_override) = $hostmask =~ m/^([^!]+)!/;
        } else {
            $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
        }
        $account = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);

        my $reminders = $self->get_reminders($account);
        my $count     = 0;
        my $text      = '';
        my $now       = scalar gettimeofday;

        foreach my $reminder (@$reminders) {
            my $duration = concise duration $reminder->{alarm} - $now;
            $text .= "$reminder->{id}) [in $duration]";
            $text .= " ($reminder->{repeat} repeats left)" if $reminder->{repeat};
            $text .= " $reminder->{text}\n";
            $count++;
        }

        if (not $count) {
            if   ($nick_override) { return "$nick_override has no reminders."; }
            else                  { return "You have no reminders."; }
        }

        $reminders = $count == 1 ? 'reminder' : 'reminders';
        return "$count $reminders: $text";
    }

    if ($delete_id) {
        my $admininfo = $self->{pbot}->{users}->loggedin_admin($target ? $target : $context->{from}, $context->{hostmask});

        # admins can delete any reminders (perhaps check admin levels against owner level?)
        if ($admininfo) {
            if (not $self->get_reminder($delete_id)) { return "Reminder $delete_id does not exist."; }

            if   ($self->delete_reminder($delete_id)) { return "Reminder $delete_id deleted."; }
            else                                      { return "Could not delete reminder $delete_id."; }
        }

        my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
        $account = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);
        my $reminder = $self->get_reminder($delete_id);

        if (not $reminder) { return "Reminder $delete_id does not exist."; }

        if ($reminder->{account} != $account) { return "Reminder $delete_id does not belong to you."; }

        if   ($self->delete_reminder($delete_id)) { return "Reminder $delete_id deleted."; }
        else                                      { return "Could not delete reminder $delete_id."; }
    }

    $text = join ' ', @opt_args if not defined $text;

    return "Please specify a point in time for this reminder." if not $alarm;
    return "Please specify a reminder message."                if not $text;

    my $admininfo = $self->{pbot}->{users}->loggedin_admin($target ? $target : $context->{from}, $context->{hostmask});

    if ($target) {
        if (not defined $admininfo) { return "Only admins can create channel reminders."; }

        if (not $self->{pbot}->{channels}->is_active($target)) { return "I'm not active in channel $target."; }
    }

    my ($length, $error) = $self->{pbot}->{parsedate}->parsedate($alarm);
    return $error if $error;

    if ($length > 31536000 * 10) { return "Come on now, I'll be dead by then."; }

    if (not defined $admininfo and $length < 60) { return "Time must be a minimum of 60 seconds."; }

    if (not defined $admininfo and $repeat > 10) { return "You may only set up to 10 repeats."; }

    if ($repeat < 0) { return "Repeats must be 0 or greater."; }

    $alarm = gettimeofday + $length;

    my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
    $account = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);

    if (not defined $admininfo) {
        my $reminders = $self->get_reminders($account);
        if (@$reminders >= 3) { return "You may only set 3 reminders at a time. Use `remindme -d id` to remove a reminder."; }
    }

    if   (my $id = $self->add_reminder($account, $target, $text, $alarm, $length, $repeat, $context->{hostmask})) { return "Reminder $id added."; }
    else                                                                                                          { return "Failed to add reminder."; }
}

1;
