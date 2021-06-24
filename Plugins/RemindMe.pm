# File: RemindMe.pm
#
# Purpose: Users can use `remindme` to set up reminders. Reminders are
# sent to the user (or channel, if -c and admin).

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::RemindMe;
use parent 'Plugins::Plugin';

use PBot::Imports;

use DBI;
use Time::Duration qw/concise duration/;
use Time::HiRes qw/time/;
use Getopt::Long qw(GetOptionsFromArray);

sub initialize {
    my ($self, %conf) = @_;

    # register `remindme` bot command
    $self->{pbot}->{commands}->register(sub { $self->cmd_remindme(@_) }, 'remindme', 0);

    # set location of sqlite database
    $self->{filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/reminders.sqlite3';

    # open the database
    $self->dbi_begin;

    # create tables, etc
    $self->create_database;

    # add saved reminders to event queue
    $self->enqueue_reminders;
}

sub unload {
    my ($self) = @_;

    # close database
    $self->dbi_end;

    # unregister `remindme` command
    $self->{pbot}->{commands}->unregister('remindme');

    # remove all reminder events from event queue
    $self->{pbot}->{event_queue}->dequeue_event('reminder .*');
}

# `remindme` bot command
sub cmd_remindme {
    my ($self, $context) = @_;

    if (not $self->{dbh}) {
        return "Internal error.";
    }

    my $usage = "Usage: remindme [-c channel] [-r count] message -t time | remindme -l [nick] | remindme -d id";

    return $usage if not length $context->{arguments};

    my ($channel, $repeats, $text, $alarm, $list_reminders, $delete_id);

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    my @opt_args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);

    Getopt::Long::Configure("bundling");
    GetOptionsFromArray(
        \@opt_args,
        'r:i' => \$repeats,
        't:s' => \$alarm,
        'c:s' => \$channel,
        'm:s' => \$text,
        'l:s' => \$list_reminders,
        'd:i' => \$delete_id
    );

    return "$getopt_error -- $usage" if defined $getopt_error;

    # option -l was provided; list reminders
    if (defined $list_reminders) {
        my $nick_override = $list_reminders if length $list_reminders;
        my $account;

        if ($nick_override) {
            my $hostmask;

            # look up account id and hostmask by nickname
            ($account, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick_override);

            if (not $account) {
                return "I don't know anybody named $nick_override.";
            }

            # capture nick portion of hostmask
            ($nick_override) = $hostmask =~ m/^([^!]+)!/;
        } else {
            $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
        }

        $account = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);

        my $reminders = $self->get_reminders($account);

        my $count = 0;
        my $text  = '';
        my $now   = time;

        foreach my $reminder (@$reminders) {
            my $interval = concise duration $reminder->{alarm} - $now;
            $text .= "$reminder->{id}) in $interval";

            if ($reminder->{repeats}) {
                $text .= " ($reminder->{repeats} repeat" . ($reminder->{repeats} == 1 ? '' : 's') . " left)";
            }

            $text .= ": $reminder->{text}\n";
            $count++;
        }

        if (not $count) {
            if ($nick_override) {
                return "$nick_override has no reminders.";
            } else {
                return "You have no reminders.";
            }
        }

        # reuse $reminders variable to store this text
        $reminders = $count == 1 ? 'reminder' : 'reminders';

        return "$count $reminders: $text";
    }

    # option -d was provided; delete a reminder
    if ($delete_id) {
        my $admininfo = $self->{pbot}->{users}->loggedin_admin($channel ? $channel : $context->{from}, $context->{hostmask});

        # admins can delete any reminders
        if ($admininfo) {
            my $reminder = $self->get_reminder($delete_id);

            if (not $reminder) {
                return "Reminder $delete_id does not exist.";
            }

            if ($self->delete_reminder($delete_id)) {
                return "Reminder $delete_id ($reminder->{text}) deleted.";
            } else {
                return "Could not delete reminder $delete_id.";
            }
        }

        my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
        $account = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);

        my $reminder = $self->get_reminder($delete_id);

        if (not $reminder) {
            return "Reminder $delete_id does not exist.";
        }

        if ($reminder->{account} != $account) {
            return "Reminder $delete_id does not belong to you.";
        }

        if ($self->delete_reminder($delete_id)) {
            return "Reminder $delete_id ($reminder->{text}) deleted.";
        } else {
            return "Could not delete reminder $delete_id.";
        }
    }

    # otherwise we're adding a reminder

    # if -t wasn't provided set text to ''
    $text //= '';

    # add to the reminder text anything left in the arguments
    if (@opt_args) {
        $text .= ' ' if length $text;
        $text .= join ' ', @opt_args;
    }

    return "Please use -t to specify a time for this reminder." if not $alarm;
    return "Please specify a reminder message."                 if not $text;

    my $admininfo = $self->{pbot}->{users}->loggedin_admin($channel ? $channel : $context->{from}, $context->{hostmask});

    # option -c was provided; ensure user is an admin and bot is in targeted channel
    if ($channel) {
        if (not defined $admininfo) {
            return "Only admins can create channel reminders.";
        }

        if (not $self->{pbot}->{channels}->is_active($channel)) {
            return "I'm not active in channel $channel.";
        }
    }

    # parse "5 minutes", "next week", "3pm", etc into seconds
    my ($seconds, $error) = $self->{pbot}->{parsedate}->parsedate($alarm);
    return $error if $error;

    if ($seconds > 31536000 * 10) {
        return "Come on now, I'll be dead by then.";
    }

    # set repeats to 0 if option -r was not provided
    $repeats //= 0;

    # prevent non-admins from abusing repeat
    if (not defined $admininfo and $repeats > 20) {
        return "You may only set up to 20 repeats.";
    }

    if ($repeats < 0) {
        return "Repeats must be 0 or greater.";
    }

    # set timestamp for alarm
    $alarm = time + $seconds;

    my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
    $account = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);

    # limit maximum reminders for non-admin users
    if (not defined $admininfo) {
        my $reminders = $self->get_reminders($account);
        if (@$reminders >= 50) {
            return "You may only set 50 reminders at a time. Use `remindme -d id` to remove a reminder.";
        }
    }

    my $id = $self->add_reminder(
        account  => $account,
        channel  => $channel,
        text     => $text,
        alarm    => $alarm,
        interval => $seconds,
        repeats  => $repeats,
        hostmask => $context->{hostmask},
    );

    if ($id) {
        return "Reminder $id added.";
    } else {
        return "Failed to add reminder.";
    }
}

# invoked whenever a reminder event is ready
sub do_reminder {
    my ($self, $id, $event) = @_;

    my $reminder = $self->get_reminder($id);

    if (not defined $reminder) {
        $self->{pbot}->{logger}->log("Queued reminder $id no longer exists.\n");

        # unset `repeating` flag for event item in PBot event queue
        $event->{repeating} = 0;

        # nothing to do
        return;
    }

    # nick of person being reminded
    my $nick;

    # ensure person is available to receive reminder
    if (not defined $reminder->{target}) {
        # ensures we get the current nick of the person
        my $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($reminder->{account});
        ($nick) = $hostmask =~ /^([^!]+)!/;

        # try again in 30 seconds if the person isn't around yet
        if (not $self->{pbot}->{nicklist}->is_present_any_channel($nick)) {
            $event->{interval}  = 30;
            $event->{repeating} = 1;
            return;
        }
    }

    # send reminder text to person
    my $target = $reminder->{target} // $nick;
    my $text = $reminder->{text};

    # if sending reminder to channel, highlight person being reminded
    if ($target =~ /^#/) {
        $text = "$nick: $text";
    }

    $self->{pbot}->{conn}->privmsg($target, $reminder->{text});

    # log event
    $self->{pbot}->{logger}->log("Reminded $target about \"$reminder->{text}\"\n");

    # update repeats or delete reminder
    if ($reminder->{repeats} > 0) {
        # update reminder
        $reminder->{repeats}--;
        $reminder->{alarm} = time + $reminder->{interval};

        # update reminder in SQLite database
        my $data = { repeats => $reminder->{repeats}, alarm => $reminder->{alarm} };
        $self->update_reminder($reminder->{id}, $data);

        # update reminder event in PBot event queue
        $event->{interval} = $reminder->{interval};
        $event->{repeating} = 1;
    } else {
        # delete reminder
        $self->delete_reminder($reminder->{id});
        $event->{repeating} = 0;
    }
}

# load all reminders from SQLite database and add them
# to PBot's event queue. typically used once at PBot start-up.
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
        my $timeout = $reminder->{alarm} - time;

        # delete this reminder if it's expired by 31 days
        if ($timeout <= 86400 * 31) {
            $self->{pbot}->{logger}->log("Deleting expired reminder: $reminder->{id}) $reminder->{text} set by $reminder->{created_by}\n");
            $self->delete_reminder($reminder->{id});
            next;
        }

        $self->{pbot}->{event_queue}->enqueue_event(
            sub {
                my ($event) = @_;
                $self->do_reminder($reminder->{id}, $event);
            },
            $timeout, "reminder $reminder->{id}", $reminder->{repeats}
        );
    }
}

sub create_database {
    my ($self) = @_;

    return if not $self->{dbh};

    eval {
        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Reminders (
  id          INTEGER PRIMARY KEY,
  account     TEXT,
  target      TEXT,
  text        TEXT,
  alarm       NUMERIC,
  repeats     INTEGER,
  interval    NUMERIC,
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

# add a reminder
sub add_reminder {
    my ($self, %args) = @_;

    my $id = eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Reminders (account, target, text, alarm, interval, repeats, created_on, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');

        $sth->execute(
            $args{account},
            $args{target},
            $args{text},
            $args{alarm},
            $args{interval},
            $args{repeats},
            scalar time,
            $args{owner},
        );

        return $self->{dbh}->sqlite_last_insert_rowid;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Add reminder failed: $@");
        return 0;
    }

    $self->{pbot}->{event_queue}->enqueue_event(
        sub {
            my ($event) = @_;
            $self->do_reminder($id, $event);
        },
        $args{interval}, "reminder $id", $args{repeats}
    );

    return $id;
}

# delete a reminder by its id
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

    $self->{pbot}->{event_queue}->dequeue_event("reminder $id");
    return 1;
}

# update a reminder's metadata
sub update_reminder {
    my ($self, $id, $data) = @_;

    eval {
        my $sql = 'UPDATE Reminders SET ';

        my @fields;

        foreach my $key (keys %$data) {
            push @fields, "$key = ?";
        }

        $sql .= join ', ', @fields;

        $sql .= ' WHERE id = ?';

        my $sth = $self->{dbh}->prepare($sql);

        my $param = 1;
        foreach my $key (keys %$data) {
            $sth->bind_param($param++, $data->{$key});
        }

        $sth->bind_param($param++, $id);
        $sth->execute;
    };

    $self->{pbot}->{logger}->log($@) if $@;
}

# get a single reminder by its id
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

# get all reminders belonging to a user
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

1;
