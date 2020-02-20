# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::ActionTrigger;
use parent 'Plugins::Plugin';

# purpose: provides interface to set/remove/modify regular expression triggers
# to execute a command.
#
# Examples:
#
# Greet a nick when they join the channel:
# actiontrigger add #channel none 0 ^(?i)([^!]+)![^\s]+.JOIN echo Hi $1, welcome to $channel!
#
# Same, but via private message (set capability to "admin" to use `msg` admin command):
# actiontrigger add #channel admin 0 ^(?i)([^!]+)![^\s]+.JOIN msg Hi $1, welcome to $channel!
#
# Kick a nick if they say a naughty thing. Set capability to "can-kick" to use `kick` admin command.
# actiontrigger add global can-kick 0 "^(?i)([^!]+)![^\s]+.PRIVMSG.*bad phrase" kick $1 Do you talk to your mother with that mouth?
#
# Say something when a keyword is seen, but only once every 5 minutes:
# actiontrigger add global none 300 "some phrase" echo Something!
#
# Capture a part of somebody's message.
# actiontrigger add #channel none 0 "(?i)how is the weather (?:in|for) (.*) today" weather $1
#
# These are basic examples; more complex examples can be crafted.

use warnings; use strict;
use feature 'unicode_strings';

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use DBI;
use Time::Duration qw/duration/;
use Time::HiRes qw/gettimeofday/;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->actiontrigger(@_) }, 'actiontrigger', 1);
    $self->{pbot}->{capabilities}->add('admin', 'can-actiontrigger', 1);

    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.join',    sub { $self->on_join(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.part',    sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',    sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',    sub { $self->on_kick(@_) });

    $self->{filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/triggers.sqlite3';

    $self->dbi_begin;
    $self->create_database;
    $self->update_database;
}

sub unload {
    my $self = shift;
    $self->dbi_end;
    $self->{pbot}->{commands}->unregister('actiontrigger');
    $self->{pbot}->{capabilities}->remove('can-actiontrigger');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.join');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.part');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.quit');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.kick');
}

sub create_database {
    my $self = shift;
    return if not $self->{dbh};

    eval {
        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Triggers (
  channel       TEXT,
  trigger       TEXT,
  action        TEXT,
  owner         TEXT,
  cap_override  TEXT,
  repeatdelay   INTEGER,
  lastused      NUMERIC
)
SQL
    };

    $self->{pbot}->{logger}->log("ActionTrigger create database failed: $@") if $@;
}

sub update_database {
    my $self = shift;
    return if not $self->{dbh};

    my %columns = ();

    eval {
        foreach my $col (@{$self->{dbh}->selectall_arrayref("PRAGMA TABLE_INFO(Triggers)")}) {
            $columns{$col->[1]} = 1;
        }

        if (not exists $columns{cap_override}) {
            $self->{dbh}->do("ALTER TABLE Triggers ADD COLUMN cap_override TEXT");
            $self->{dbh}->do("UPDATE Triggers SET cap_override='botowner', level=0 WHERE level >= 90");
            $self->{dbh}->do("UPDATE Triggers SET cap_override='admin', level=0 WHERE level >= 60");
            $self->{dbh}->do("UPDATE Triggers SET cap_override='chanop', level=0 WHERE level >= 10");
        }
    };

    $self->{pbot}->{logger}->log("ActionTrigger update database failed: $@") if $@;
}

sub dbi_begin {
    my ($self) = @_;
    eval {
        $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", {RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1, sqlite_unicode => 1})
          or die $DBI::errstr;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error opening ActionTrigger database: $@");
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

sub add_trigger {
    my ($self, $channel, $trigger, $action, $owner, $cap_override, $repeatdelay) = @_;

    return 0 if $self->get_trigger($channel, $trigger);

    eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Triggers (channel, trigger, action, owner, cap_override, repeatdelay, lastused) VALUES (?, ?, ?, ?, ?, ?, 0)');
        $sth->execute(lc $channel, $trigger, $action, $owner, $cap_override, $repeatdelay);
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Add trigger failed: $@");
        return 0;
    }
    return 1;
}

sub delete_trigger {
    my ($self, $channel, $trigger) = @_;
    return 0 if not $self->get_trigger($channel, $trigger);
    my $sth = $self->{dbh}->prepare('DELETE FROM Triggers WHERE channel = ? AND trigger = ?');
    $sth->execute(lc $channel, $trigger);
    return 1;
}

sub list_triggers {
    my ($self, $channel) = @_;

    my $triggers = eval {
        my $sth;

        if ($channel eq '*') {
            $sth     = $self->{dbh}->prepare('SELECT * FROM Triggers WHERE channel != ?');
            $channel = 'global';
        } else {
            $sth = $self->{dbh}->prepare('SELECT * FROM Triggers WHERE channel = ?');
        }
        $sth->execute(lc $channel);
        return $sth->fetchall_arrayref({});
    };

    if ($@) { $self->{pbot}->{logger}->log("List triggers failed: $@"); }

    $triggers = [] if not defined $triggers;
    return @$triggers;
}

sub update_trigger {
    my ($self, $channel, $trigger, $data) = @_;

    eval {
        my $sql = 'UPDATE Triggers SET ';

        my $comma = '';
        foreach my $key (keys %$data) {
            $sql .= "$comma$key = ?";
            $comma = ", ";
        }

        $sql .= "WHERE trigger = ? AND channel = ?";
        my $sth   = $self->{dbh}->prepare($sql);
        my $param = 1;
        foreach my $key (keys %$data) { $sth->bind_param($param++, $data->{$key}); }

        $sth->bind_param($param++, $trigger);
        $sth->bind_param($param,   $channel);
        $sth->execute();
    };

    $self->{pbot}->{logger}->log("Update trigger $channel/$trigger failed: $@\n") if $@;
}

sub get_trigger {
    my ($self, $channel, $trigger) = @_;

    my $row = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Triggers WHERE channel = ? AND trigger = ?');
        $sth->execute(lc $channel, $trigger);
        my $row = $sth->fetchrow_hashref();
        return $row;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Get trigger failed: $@");
        return undef;
    }

    return $row;
}

sub on_kick {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user,       $host)  = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);
    my ($victim, $reason) = ($event->{event}->to, $event->{event}->{args}[1]);
    my $channel = $event->{event}->{args}[0];
    return 0 if $event->{interpreted};
    $self->check_trigger($nick, $user, $host, $channel, "KICK $victim $reason");
    return 0;
}

sub on_action {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
    my $channel = $event->{event}->{to}[0];
    return 0 if $event->{interpreted};
    $msg =~ s/^\/me\s+//;
    $self->check_trigger($nick, $user, $host, $channel, "ACTION $msg");
    return 0;
}

sub on_public {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
    my $channel = $event->{event}->{to}[0];
    return 0 if $event->{interpreted};
    $self->check_trigger($nick, $user, $host, $channel, "PRIVMSG $msg");
    return 0;
}

sub on_join {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel, $args) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to, $event->{event}->args);
    $channel = lc $channel;
    $self->check_trigger($nick, $user, $host, $channel, "JOIN");
    return 0;
}

sub on_departure {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel, $args) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to, $event->{event}->args);
    $channel = lc $channel;
    $self->check_trigger($nick, $user, $host, $channel, (uc $event->{event}->type) . " $args");
    return 0;
}

sub check_trigger {
    my ($self, $nick, $user, $host, $channel, $text) = @_;
    return 0 if not $self->{dbh};

    my @triggers = $self->list_triggers($channel);
    my @globals  = $self->list_triggers('global');
    push @triggers, @globals;

    $text = "$nick!$user\@$host $text";
    my $now = gettimeofday;

    foreach my $trigger (@triggers) {
        eval {
            $trigger->{lastused}    = 0 if not defined $trigger->{lastused};
            $trigger->{repeatdelay} = 0 if not defined $trigger->{repeatdelay};
            if ($now - $trigger->{lastused} >= $trigger->{repeatdelay} and $text =~ m/$trigger->{trigger}/) {
                $trigger->{lastused} = $now;
                my $data = {lastused => $now};
                $self->update_trigger($trigger->{channel}, $trigger->{trigger}, $data);

                my $action = $trigger->{action};
                my @stuff  = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
                my $i;
                map { ++$i; $action =~ s/\$$i/$_/g; } @stuff;

                my $delay = 0;

                my ($n, $u, $h) = $trigger->{owner} =~ /^([^!]+)!([^@]+)\@(.*)$/;
                my $command = {
                    nick    => $n,
                    user    => $u,
                    host    => $h,
                    command => $action,
                };

                if (length $trigger->{cap_override} and $trigger->{cap_override} ne 'none') {
                    $command->{'cap-override'} = $trigger->{cap_override};
                }
                my $cap = '';
                $cap = " (capability=$command->{'cap-override'})" if exists $command->{'cap-override'};
                $self->{pbot}->{logger}->log("ActionTrigger: ($channel) $trigger->{trigger} -> $action$cap\n");
                $self->{pbot}->{interpreter}->add_to_command_queue($channel, $command, $delay);
            }
        };

        if ($@) { $self->{pbot}->{logger}->log("Skipping bad trigger $trigger->{trigger}: $@"); }
    }
    return 0;
}

sub actiontrigger {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
    return "Internal error." if not $self->{dbh};

    my $command = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
    my $result;
    given ($command) {
        when ('list') {
            my $channel = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
            if (not defined $channel) {
                if   ($from !~ /^#/) { $channel = 'global'; }
                else                 { $channel = $from; }
            } elsif ($channel !~ m/^#/ and $channel ne 'global') {
                return "Invalid channel $channel. Usage: actiontrigger list [#channel or global]";
            }

            my @triggers = $self->list_triggers($channel);

            if (not @triggers) { $result = "No action triggers set for $channel."; }
            else {
                $result = "Triggers for $channel:\n";
                my $comma = '';
                foreach my $trigger (@triggers) {
                    $trigger->{cap_override} //= 'none';
                    $trigger->{repeatdelay}  //= 0;
                    $result .= "$comma$trigger->{trigger} -> $trigger->{action}";
                    $result .= " (capability=$trigger->{cap_override})" if length $trigger->{cap_override} and $trigger->{cap_override} ne 'none';
                    $result .= " (repeatdelay=$trigger->{repeatdelay})" if $trigger->{repeatdelay} != 0;
                    $comma = ",\n";
                }
            }
        }

        # TODO: use GetOpt flags instead of positional arguments
        when ('add') {
            my $channel;
            if ($from =~ m/^#/) { $channel = $from; }
            else {
                $channel = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});

                if (not defined $channel) {
                    return
                      "To use this command from private message the <channel> argument is required. Usage: actiontrigger add <#channel or global> <capability> <repeat delay (in seconds)> <regex trigger> <command>";
                } elsif ($channel !~ m/^#/ and $channel ne 'global') {
                    return "Invalid channel $channel. Usage: actiontrigger add <#channel or global> <capability> <repeat delay (in seconds)> <regex trigger> <command>";
                }
            }

            my ($cap_override, $repeatdelay, $trigger, $action) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 4, 0, 1);

            if (not defined $trigger or not defined $action) {
                if ($from !~ m/^#/) {
                    $result =
                      "To use this command from private message the <channel> argument is required. Usage: actiontrigger add <#channel or global> <capability> <repeat delay (in seconds)> <regex trigger> <command>";
                } else {
                    $result = "Usage: actiontrigger add <capability> <repeat delay (in seconds)> <regex trigger> <command>";
                }
                return $result;
            }

            my $exists = $self->get_trigger($channel, $trigger);

            if (defined $exists) { return "Trigger already exists."; }

            if (not $self->{pbot}->{capabilities}->exists($cap_override)) { return "$nick: Capability '$cap_override' does not exist.\n"; }

            if ($repeatdelay !~ m/^\d+$/) { return "$nick: Missing repeat delay argument?\n"; }

            if ($cap_override ne 'none') {
                my $u = $self->{pbot}->{users}->find_user($channel, "$nick!$user\@$host");
                if (not $self->{pbot}->{capabilities}->userhas($u, $cap_override)) { return "You may not set a capability that you do not have."; }
            }

            if   ($self->add_trigger($channel, $trigger, $action, "$nick!$user\@$host", $cap_override, $repeatdelay)) { $result = "Trigger added."; }
            else                                                                                                      { $result = "Failed to add trigger."; }
        }

        when ('delete') {
            my $channel;
            if ($from =~ m/^#/) { $channel = $from; }
            else {
                $channel = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
                if ($channel !~ m/^#/ and $channel ne 'global') {
                    return "To use this command from private message the <channel> argument is required. Usage: actiontrigger delete <#channel or global> <regex trigger>";
                }
            }

            my ($trigger) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 1);

            if (not defined $trigger) {
                if ($from !~ m/^#/) {
                    $result = "To use this command from private message the <channel> argument is required. Usage: from private message: actiontrigger delete <channel> <regex trigger>";
                } else {
                    $result = "Usage: actiontrigger delete <regex trigger>";
                }
                return $result;
            }

            my $exists = $self->get_trigger($channel, $trigger);

            if (not defined $exists) { $result = "No such trigger."; }
            else {
                $self->delete_trigger($channel, $trigger);
                $result = "Trigger deleted.";
            }
        }

        default {
            if ($from !~ m/^#/) {
                $result =
                  "Usage from private message: actiontrigger list [#channel or global] | actiontrigger add <#channel or global> <capability> <repeat delay (in seconds)> <regex trigger> <command> | actiontrigger delete <#channel or global> <regex trigger>";
            } else {
                $result =
                  "Usage: actiontrigger list [#channel or global] | actiontrigger add <capability> <repeat delay (in seconds)> <regex trigger> <command> | actiontrigger delete <regex>";
            }
        }
    }
    return $result;
}

1;
