# File: ActionTrigger.pm
#
# Purpose: provides interface to set/remove/modify regular expression triggers
# which invoke bot commands when matched against IRC messages.
#
# Usage: actiontrigger add <#channel or global> <capability> <rate-limit (in seconds)> <regex trigger> <command>
#
# Note that ActionTrigger does not match on raw IRC lines. It matches on a
# simplified message format:
#
#    "<hostmask> <action> <arguments>"
#
# where <action> can be PRIVMSG, ACTION, KICK, JOIN, PART or QUIT.
#
# Examples:
#
# Greet a nick when they join the channel:
# actiontrigger add #channel none 0 ^(?i)([^!]+)![^\s]+.JOIN echo Hi $1, welcome to $channel!
#
# Same, but via private message (set capability to "admin" to use `msg` admin command):
# actiontrigger add #channel admin 0 ^(?i)([^!]+)![^\s]+.JOIN msg $1 Hi $1, welcome to $channel!
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

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::ActionTrigger;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use DBI;
use Time::Duration qw/duration/;
use Time::HiRes qw/gettimeofday/;

sub initialize {
    my ($self, %conf) = @_;

    # register bot command
    $self->{pbot}->{commands}->add(
        name => 'actiontrigger',
        help => 'Manages regular expression triggers to invoke bot commands',
        requires_cap => 1,
        subref => sub { $self->cmd_actiontrigger(@_) },
    );

    # add capability to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-actiontrigger', 1);

    # register IRC handlers
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.join',    sub { $self->on_join(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.part',    sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',    sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',    sub { $self->on_kick(@_) });

    # database file
    $self->{filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/triggers.sqlite3';

    # open and initialize database
    $self->dbi_begin;
    $self->create_database;
}

sub unload {
    my ($self) = @_;

    # close database
    $self->dbi_end;

    # unregister bot command
    $self->{pbot}->{commands}->remove('actiontrigger');

    # remove capability
    $self->{pbot}->{capabilities}->remove('can-actiontrigger');

    # remove IRC handlers
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.join');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.part');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.quit');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.kick');
}

sub cmd_actiontrigger {
    my ($self, $context) = @_;

    # database not available
    return "Internal error." if not $self->{dbh};

    my $command = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    given ($command) {
        when ('list') {
            my $channel = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

            if (not defined $channel) {
                if ($context->{from} !~ /^#/) {
                    # used from /msg
                    $channel = 'global';
                } else {
                    # used in channel
                    $channel = $context->{from};
                }
            }
            elsif ($channel !~ m/^#/ and $channel ne 'global') {
                return "Invalid channel $channel. Usage: actiontrigger list [#channel or global]";
            }

            my @triggers = $self->list_triggers($channel);

            if (not @triggers) {
                return "No action triggers set for $channel.";
            }
            else {
                my $result = "Triggers for $channel:\n";
                my @items;

                foreach my $trigger (@triggers) {
                    $trigger->{cap_override} //= 'none';
                    $trigger->{ratelimit}    //= 0;

                    my $item = "$trigger->{trigger} -> $trigger->{action}";

                    if ($trigger->{cap_override} and $trigger->{cap_override} ne 'none') {
                        $item .= " (capability=$trigger->{cap_override})";
                    }

                    if ($trigger->{ratelimit} != 0) {
                        $item .= " (ratelimit=$trigger->{ratelimit})";
                    }

                    push @items, $item;
                }

                $result .= join ",\n", @items;
                return $result;
            }
        }

        when ('add') {
            # TODO: use GetOpt flags instead of positional arguments

            my $channel;

            if ($context->{from} =~ m/^#/) {
                $channel = $context->{from};
            }
            else {
                $channel = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

                if (not defined $channel) {
                    return
                      "To use this command from private message the <channel> argument is required. Usage: actiontrigger add <#channel or global> <capability> <rate-limit (in seconds)> <regex trigger> <command>";
                }
                elsif ($channel !~ m/^#/ and $channel ne 'global') {
                    return "Invalid channel $channel. Usage: actiontrigger add <#channel or global> <capability> <rate-limit (in seconds)> <regex trigger> <command>";
                }
            }

            # split into 4 arguments, offset 0, preserving quotes
            my ($cap_override, $ratelimit, $trigger, $action) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 4, 0, 1);

            if (not defined $trigger or not defined $action) {
                if ($context->{from} !~ m/^#/) {
                    return
                      "To use this command from private message the <channel> argument is required. Usage: actiontrigger add <#channel or global> <capability> <rate-limit (in seconds)> <regex trigger> <command>";
                } else {
                    return "Usage: actiontrigger add <capability> <rate-limit (in seconds)> <regex trigger> <command>";
                }
            }

            if (defined $self->get_trigger($channel, $trigger)) {
                return "Trigger already exists.";
            }

            if ($ratelimit !~ m/^\d+$/) {
                return "$context->{nick}: Missing rate-limit argument?\n";
            }

            if ($cap_override ne 'none') {
                if (not $self->{pbot}->{capabilities}->exists($cap_override)) {
                    return "$context->{nick}: Capability '$cap_override' does not exist. Use 'none' to omit.\n";
                }

                my $u = $self->{pbot}->{users}->find_user($channel, $context->{hostmask});

                if (not $self->{pbot}->{capabilities}->userhas($u, $cap_override)) {
                    return "You may not set a capability that you do not have.";
                }
            }

            if ($self->add_trigger($channel, $trigger, $action, $context->{hostmask}, $cap_override, $ratelimit)) {
                return "Trigger added.";
            } else {
                return "Failed to add trigger.";
            }
        }

        when ('delete') {
            my $channel;

            if ($context->{from} =~ m/^#/) {
                $channel = $context->{from};
            }
            else {
                $channel = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

                if ($channel !~ m/^#/ and $channel ne 'global') {
                    return "To use this command from private message the <channel> argument is required. Usage: actiontrigger delete <#channel or global> <regex trigger>";
                }
            }

            my ($trigger) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 1);

            if (not defined $trigger) {
                if ($context->{from} !~ m/^#/) {
                    return "To use this command from private message the <channel> argument is required. Usage: from private message: actiontrigger delete <channel> <regex trigger>";
                } else {
                    return "Usage: actiontrigger delete <regex trigger>";
                }
            }

            if (not defined $self->get_trigger($channel, $trigger)) {
                return "No such trigger.";
            } else {
                $self->delete_trigger($channel, $trigger);
                return "Trigger deleted.";
            }
        }

        default {
            if ($context->{from} !~ m/^#/) {
                return
                  "Usage from private message: actiontrigger list [#channel or global] | actiontrigger add <#channel or global> <capability> <rate-limit (in seconds)> <regex trigger> <command> | actiontrigger delete <#channel or global> <regex trigger>";
            } else {
                return
                  "Usage: actiontrigger list [#channel or global] | actiontrigger add <capability> <rate-limit (in seconds)> <regex trigger> <command> | actiontrigger delete <regex>";
            }
        }
    }
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
  ratelimit   INTEGER,
  lastused      NUMERIC
)
SQL
    };

    $self->{pbot}->{logger}->log("ActionTrigger create database failed: $@") if $@;
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
    my ($self, $channel, $trigger, $action, $owner, $cap_override, $ratelimit) = @_;

    return 0 if $self->get_trigger($channel, $trigger);

    eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Triggers (channel, trigger, action, owner, cap_override, ratelimit, lastused) VALUES (?, ?, ?, ?, ?, ?, 0)');
        $sth->execute(lc $channel, $trigger, $action, $owner, $cap_override, $ratelimit);
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
            $channel = 'global';
            $sth = $self->{dbh}->prepare('SELECT * FROM Triggers WHERE channel != ?');
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

        my @triggers;
        foreach my $key (keys %$data) {
            push @triggers, "$key = ?";
        }

        $sql .= join ', ', @triggers;
        $sql .= "WHERE trigger = ? AND channel = ?";

        my $sth = $self->{dbh}->prepare($sql);

        my $param = 1;
        foreach my $key (keys %$data) { $sth->bind_param($param++, $data->{$key}); }

        $sth->bind_param($param++, $trigger);
        $sth->bind_param($param,   $channel);
        $sth->execute;
    };

    $self->{pbot}->{logger}->log("Update trigger $channel/$trigger failed: $@\n") if $@;
}

sub get_trigger {
    my ($self, $channel, $trigger) = @_;

    my $row = eval {
        my $sth = $self->{dbh}->prepare('SELECT * FROM Triggers WHERE channel = ? AND trigger = ?');
        $sth->execute(lc $channel, $trigger);
        my $row = $sth->fetchrow_hashref;
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

    # don't handle this event if it was caused by a bot command
    return 0 if $event->{interpreted};

    my ($nick, $user, $host) = (
        $event->nick,
        $event->user,
        $event->host
    );

    my ($victim, $reason) = (
        $event->to,
        $event->{args}[1]
    );

    my $channel = $event->{args}[0];

    $self->check_trigger($nick, $user, $host, $channel, "KICK $victim $reason");
    return 0;
}

sub on_action {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $msg) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->args
    );

    my $channel = $event->{to}[0];

    $msg =~ s/^\/me\s+//;

    $self->check_trigger($nick, $user, $host, $channel, "ACTION $msg");
    return 0;
}

sub on_public {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $msg) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->args);

    my $channel = $event->{to}[0];

    $self->check_trigger($nick, $user, $host, $channel, "PRIVMSG $msg");
    return 0;
}

sub on_join {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $channel, $args) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->to,
        $event->args
    );

    $self->check_trigger($nick, $user, $host, $channel, "JOIN");
    return 0;
}

sub on_departure {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $channel, $args) = (
        $event->nick,
        $event->user,
        $event->host,
        $event->to,
        $event->args
    );

    $self->check_trigger($nick, $user, $host, $channel, (uc $event->type) . " $args");
    return 0;
}

sub check_trigger {
    my ($self, $nick, $user, $host, $channel, $text) = @_;

    # database not available
    return 0 if not $self->{dbh};

    $channel = lc $channel;

    # TODO: cache these instead of loading them again every message
    my @triggers = $self->list_triggers($channel);
    my @globals  = $self->list_triggers('global');
    push @triggers, @globals;

    $text = "$nick!$user\@$host $text";
    my $now = gettimeofday;

    foreach my $trigger (@triggers) {
        eval {
            $trigger->{lastused}  //= 0;
            $trigger->{ratelimit} //= 0;

            if ($now - $trigger->{lastused} >= $trigger->{ratelimit} and $text =~ m/$trigger->{trigger}/) {
                my @stuff  = ($1, $2, $3, $4, $5, $6, $7, $8, $9);

                $trigger->{lastused} = $now;

                $self->update_trigger($trigger->{channel}, $trigger->{trigger}, { lastused => $now });

                my $action = $trigger->{action};
                my $i;
                map { ++$i; $action =~ s/\$$i/$_/g; } @stuff;

                my ($n, $u, $h) = $trigger->{owner} =~ /^([^!]+)!([^@]+)\@(.*)$/;

                my $command = {
                    nick     => $n,
                    user     => $u,
                    host     => $h,
                    hostmask => "$n!$u\@$host",
                    command  => $action,
                };

                if ($trigger->{cap_override} and $trigger->{cap_override} ne 'none') {
                    $command->{'cap-override'} = $trigger->{cap_override};
                }

                my $cap = '';
                $cap = " (capability=$command->{'cap-override'})" if exists $command->{'cap-override'};
                $self->{pbot}->{logger}->log("ActionTrigger: ($channel) $trigger->{trigger} -> $action$cap\n");

                $self->{pbot}->{interpreter}->add_to_command_queue($channel, $command);
            }
        };

        if ($@) { $self->{pbot}->{logger}->log("Skipping bad trigger $trigger->{trigger}: $@"); }
    }

    return 0;
}

1;
