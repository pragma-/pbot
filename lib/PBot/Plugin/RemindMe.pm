# File: RemindMe.pm
#
# Purpose: Users can use `remindme` to set up reminders. Reminders are
# sent to the user (or to a channel, if option -c is used).

# SPDX-FileCopyrightText: 2017-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::RemindMe;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use DBI;
use Time::Duration qw(ago concise duration);
use Time::HiRes    qw(time);

sub initialize($self, %conf) {
    # register `remindme` bot command
    $self->{pbot}->{commands}->add(
        name   => 'remindme',
        help   => 'Manage personal reminder notifications',
        subref => sub { $self->cmd_remindme(@_) },
    );

    # set location of sqlite database
    $self->{filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/reminders.sqlite3';

    # open the database
    $self->dbi_begin;

    # create tables, etc
    $self->create_database;

    # add saved reminders to event queue
    $self->enqueue_reminders;
}

sub unload($self) {
    # close database
    $self->dbi_end;

    # unregister `remindme` command
    $self->{pbot}->{commands}->remove('remindme');

    # remove all reminder events from event queue
    $self->{pbot}->{event_queue}->dequeue_event('reminder .*');
}

# `remindme` bot command
sub cmd_remindme($self, $context) {
    if (not $self->{dbh}) {
        return "Internal error.";
    }

    my $usage = "Usage: remindme -t <time> <message> [-r <repeat count>] [-c <channel>] | remindme -l [nick] | remindme -d <id>";

    return $usage if not length $context->{arguments};

    my ($channel, $repeats, $text, $time, $list_reminders, $delete_id);

    my %opts = (
        c => \$channel,
        r => \$repeats,
        m => \$text,
        t => \$time,
        l => \$list_reminders,
        d => \$delete_id,
    );

    my ($opt_args, $opt_error) = $self->{pbot}->{interpreter}->getopt(
        $context->{arguments},
        \%opts,
        ['bundling'],
        'r=i',
        't=s',
        'c=s',
        'm=s',
        'l:s',
        'd=i',
    );

    return "$opt_error -- $usage" if defined $opt_error;

    # option -l was provided; list reminders
    if (defined $list_reminders) {
        # unique internal account id for a hostmask
        my $account;

        # if arg was provided to -l, list reminders belonging to args
        my $nick_override = $list_reminders if length $list_reminders;

        if ($nick_override) {
            # look up account id and hostmask for -l argument
            my $hostmask;

            ($account, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($nick_override);

            if (not $account) {
                return "I don't know anybody named $nick_override.";
            }

            # capture nick portion of hostmask
            ($nick_override) = $hostmask =~ m/^([^!]+)!/;
        } else {
            # look up caller's account id
            $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
        }

        # get the root parent account id (consolidates nick-changes, etc)
        $account = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);

        # get the reminders
        my $reminders = $self->get_reminders($account);

        # list the reminders
        my $count = 0;
        my $text  = '';
        my $now   = time;

        foreach my $reminder (@$reminders) {
            my $interval = $reminder->{alarm} - $now;

            if ($interval < 0) {
                $interval = 'missed ' . concise ago -$interval;
            } else {
                $interval = 'in ' . concise duration $interval;
            }

            $text .= "$reminder->{id}) $interval";

            if ($reminder->{repeats}) {
                $text .= " (repeats every $reminder->{interval}, $reminder->{repeats} more time" . ($reminder->{repeats} == 1 ? '' : 's') . ')';
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
        my $reminder = $self->get_reminder($delete_id);

        if (not $reminder) {
            return "Reminder $delete_id does not exist.";
        }

        # admins can delete any reminder
        my $admin = $self->{pbot}->{users}->loggedin_admin($channel ? $channel : $context->{from}, $context->{hostmask});

        if (not $admin) {
            # not an admin, check if they own this reminder
            my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
            $account = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);

            if ($reminder->{account} != $account) {
                return "Reminder $delete_id does not belong to you.";
            }
        }

        # delete reminder
        if ($self->delete_reminder($delete_id)) {
            return "Reminder $delete_id ($reminder->{text}) deleted.";
        } else {
            return "Could not delete reminder $delete_id.";
        }
    }

    # otherwise we're adding a reminder

    # if -m wasn't provided set text to ''
    $text //= '';

    # add to the reminder text anything left in the arguments
    if (@$opt_args) {
        $text .= ' ' if length $text;
        $text .= "@$opt_args";
    }

    return "Please use -t to specify a time for this reminder." if not $time;
    return "Please specify a reminder message."                 if not $text;

    # ensure option -c is a channel
    if (defined $channel and $channel !~ /^#/) {
        return "Option -c must be a channel.";
    }

    # option -c was provided; ensure bot is in channel
    if ($channel and not $self->{pbot}->{channels}->is_active($channel)) {
        return "I'm not active in channel $channel.";
    }

    # parse "5 minutes", "next week", "3pm", etc into seconds
    my ($seconds, $error) = $self->{pbot}->{parsedate}->parsedate($time);
    return $error if $error;

    if ($seconds > 31536000 * 10) {
        return "Come on now, I'll be dead by then.";
    }

    # set repeats to 0 if option -r was not provided
    $repeats //= 0;

    # get user account if user is an admin, undef otherwise
    my $admin = $self->{pbot}->{users}->loggedin_admin($channel ? $channel : $context->{from}, $context->{hostmask});

    # prevent non-admins from abusing repeat
    if (not defined $admin and $repeats > 20) {
        return "You may only set up to 20 repeats.";
    }

    if ($repeats < 0) {
        return "Repeats cannot be negative.";
    }

    # set timestamp for alarm
    my $alarm = time + $seconds;

    my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($context->{nick}, $context->{user}, $context->{host});
    $account = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($account);

    # limit maximum reminders for non-admin users
    if (not defined $admin) {
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
        interval => $time,
        seconds  => $seconds,
        repeats  => $repeats,
        owner    => $context->{hostmask},
    );

    my $duration = concise duration $seconds;

    if ($repeats) {
        $duration .= " repeating $repeats time" . ($repeats == 1 ? '' : 's');
    }

    if ($id) {
        return "Reminder $id added (in $duration).";
    } else {
        return "Failed to add reminder.";
    }
}

# invoked whenever a reminder event is ready
sub do_reminder($self, $id, $event) {
    my $reminder = $self->get_reminder($id);

    if (not defined $reminder) {
        $self->{pbot}->{logger}->log("Queued reminder $id no longer exists.\n");

        # unset `repeating` flag for event item in PBot event queue
        $event->{repeating} = 0;

        # nothing to do
        return;
    }

    # ensures we get the current nick of the person being reminded
    my $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($reminder->{account});
    my ($nick) = $hostmask =~ /^([^!]+)!/;

    # try again in 30 seconds if the person isn't around yet
    if (not $self->{pbot}->{nicklist}->is_present_any_channel($nick)) {
        $event->{interval}  = 30;
        $event->{repeating} = 1;
        return;
    }

    # send reminder text to person
    my $target = $reminder->{channel} || $nick;
    my $text = $reminder->{text};

    # if sending reminder to channel, highlight person being reminded
    if ($target =~ /^#/) {
        $text = "$nick: $text";
    }

    $self->{pbot}->{conn}->privmsg($target, $text);

    # log event
    $self->{pbot}->{logger}->log("Reminded $target about \"$text\"; interval: $reminder->{interval}\n");

    # update repeats or delete reminder
    if ($reminder->{repeats} > 0) {
        # update reminder
        $reminder->{repeats}--;

        # parse interval again to get correct offset in seconds
        # e.g., if it's 12 pm and they set a repeating reminder for 3 pm then
        # the interval would be 3h. we don't want the reminder to repeat every
        # 3h but instead every day at 3 pm. so when this reminder fires at 3 pm,
        # we reparse the interval "3 pm" again to get 24h, instead of storing 3h.
        my ($seconds) = $self->{pbot}->{parsedate}->parsedate($reminder->{interval});

        # if timeout is 0 or less, prepend "next" and try again.
        # e.g., if interval is "10 pm" then at 10:00:00 pm the interval will
        # parse to 0 seconds, i.e. right now, until it is 10:00:01 pm. we really
        # want the next 10 pm, 24 hours from right now.
        if ($seconds <= 0) {
            my $override;
            if ($reminder->{interval} =~ m/^\d/) {
                $override = "tomorrow ";
            } else {
                $override = "next ";
            }

            ($seconds) = $self->{pbot}->{parsedate}->parsedate("$override $reminder->{interval}");
        }

        # update alarm timestamp
        $reminder->{alarm} = time + $seconds;

        # update reminder in SQLite database
        my $data = { repeats => $reminder->{repeats}, alarm => $reminder->{alarm} };
        $self->update_reminder($reminder->{id}, $data);

        # update reminder event in PBot event queue
        $event->{interval} = $seconds;
        $event->{repeating} = 1;
    } else {
        # delete reminder from SQLite database
        $self->delete_reminder($reminder->{id}, 1);

        # tell PBot event queue not to reschedule this reminder
        $event->{repeating} = 0;
    }
}

# add a single reminder to the PBot event queue
sub enqueue_reminder($self, $reminder, $timeout) {
    $self->{pbot}->{event_queue}->enqueue_event(
        sub {
            my ($event) = @_;
            $self->do_reminder($reminder->{id}, $event);
        },
        $timeout, "reminder $reminder->{id}", $reminder->{repeats}
    );
}

# load all reminders from SQLite database and add them
# to PBot's event queue. typically used once at PBot start-up.
sub enqueue_reminders($self) {
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

        # delete this reminder if it's expired by approximately 1 year
        if ($timeout <= -(86400 * 31 * 12)) {
            $self->{pbot}->{logger}->log("Deleting expired reminder: $reminder->{id}) $reminder->{text} set by $reminder->{created_by}\n");
            $self->delete_reminder($reminder->{id});
            next;
        }

        $self->enqueue_reminder($reminder, $timeout);
    }
}

sub create_database($self) {
    return if not $self->{dbh};

    eval {
        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Reminders (
  id          INTEGER PRIMARY KEY,
  account     TEXT,
  channel     TEXT,
  text        TEXT,
  alarm       NUMERIC,
  repeats     INTEGER,
  interval    TEXT,
  created_on  NUMERIC,
  created_by  TEXT
)
SQL
    };

    $self->{pbot}->{logger}->log("RemindMe: create database failed: $@") if $@;
}

sub dbi_begin($self) {
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

sub dbi_end($self) {
    return if not $self->{dbh};
    $self->{dbh}->disconnect;
    delete $self->{dbh};
}

# add a reminder, to SQLite and the PBot event queue
sub add_reminder($self, %args) {
    # add reminder to SQLite database
    my $id = eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Reminders (account, channel, text, alarm, interval, repeats, created_on, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');

        $sth->execute(
            $args{account},
            $args{channel},
            $args{text},
            $args{alarm},
            $args{interval},
            $args{repeats},
            scalar time,
            $args{owner},
        );

        return $self->{dbh}->sqlite_last_insert_rowid;
    };

    # check for exception
    if ($@) {
        $self->{pbot}->{logger}->log("Add reminder failed: $@");
        return 0;
    }

    my $reminder = {
        id      => $id,
        repeats => $args{repeats},
    };

    # add reminder to event queue.
    $self->enqueue_reminder($reminder, $args{seconds});

    # return reminder id
    return $id;
}

# delete a reminder by its id, from SQLite and the PBot event queue
sub delete_reminder($self, $id, $dont_dequeue = 0) {
    return if not $self->{dbh};

    # remove from SQLite database
    eval {
        my $sth = $self->{dbh}->prepare('DELETE FROM Reminders WHERE id = ?');
        $sth->execute($id);
    };

    # check for exeption
    if ($@) {
        $self->{pbot}->{logger}->log("Delete reminder $id failed: $@");
        return 0;
    }

    unless ($dont_dequeue) {
        # remove from event queue
        my $removed = $self->{pbot}->{event_queue}->dequeue_event("reminder $id");
        $self->{pbot}->{logger}->log("RemindMe: dequeued events: $removed\n");
    }

    return 1;
}

# update a reminder's data, in SQLite
sub update_reminder($self, $id, $data) {
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

# get a single reminder by its id, from SQLite
sub get_reminder($self, $id) {
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

# get all reminders belonging to an account id, from SQLite
sub get_reminders($self, $account) {
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
