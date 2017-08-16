# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Plugins::ActionTrigger;

use warnings;
use strict;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use Carp ();
use DBI;
use Time::Duration qw/duration/;
use Time::HiRes qw/gettimeofday/;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{pbot}->{commands}->register(sub { $self->actiontrigger(@_) }, 'actiontrigger', 10);

  $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_action(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.join',    sub { $self->on_join(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.part',    sub { $self->on_departure(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',    sub { $self->on_departure(@_) });

  $self->{filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/triggers.sqlite3';

  $self->dbi_begin;
  $self->create_database;
}

sub unload {
  my $self = shift;
  $self->dbi_end;
  $self->{pbot}->{commands}->unregister('actiontrigger');
}

sub create_database {
  my $self = shift;

  return if not $self->{dbh};

  eval {
    $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Triggers (
  channel     TEXT,
  trigger     TEXT,
  action      TEXT,
  owner       TEXT
)
SQL

  };

  $self->{pbot}->{logger}->log("ActionTrigger create database failed: $@") if $@;
}

sub dbi_begin {
  my ($self) = @_;
  eval {
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", { RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1 }) or die $DBI::errstr;
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
  my ($self, $channel, $trigger, $action, $owner) = @_;

  return 0 if $self->get_trigger($channel, $trigger);

  eval {
    my $sth = $self->{dbh}->prepare('INSERT INTO Triggers (channel, trigger, action, owner) VALUES (?, ?, ?, ?)');
    $sth->bind_param(1, lc $channel);
    $sth->bind_param(2, $trigger);
    $sth->bind_param(3, $action);
    $sth->bind_param(4, $owner);
    $sth->execute();
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
  $sth->bind_param(1, lc $channel);
  $sth->bind_param(2, $trigger);
  $sth->execute();

  return 1;
}

sub list_triggers {
  my ($self, $channel) = @_;

  my $triggers = eval {
    my $sth = $self->{dbh}->prepare('SELECT * FROM Triggers WHERE channel = ?');
    $sth->bind_param(1, lc $channel);
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };

  if ($@) {
    $self->{pbot}->{logger}->log("List triggers failed: $@");
  }

  return @$triggers;
}

sub get_trigger {
  my ($self, $channel, $trigger) = @_;

  my $row = eval {
    my $sth = $self->{dbh}->prepare('SELECT * FROM Triggers WHERE channel = ? AND trigger = ?');
    $sth->bind_param(1, lc $channel);
    $sth->bind_param(2, $trigger);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return $row;
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Get trigger failed: $@");
    return undef;
  }

  return $row;
}

sub actiontrigger {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if (not $self->{dbh}) {
    return "Internal error.";
  }

  my $command;
  ($command, $arguments) = split / /, $arguments, 2;

  my ($channel, $result);

  given ($command) {
    when ('list') {
      if ($from =~ m/^#/) {
        $channel = $from;
      } else {
        ($channel) = split / /, $arguments, 1;
        if ($channel !~ m/^#/) {
          return "Usage from private message: actiontrigger list <channel>";
        }
      }

      my @triggers = $self->list_triggers($channel);

      if (not @triggers) {
        $result = "No counter triggers set for $channel.";
      } else {
        $result = "Triggers for $channel: ";
        my $comma = '';
        foreach my $trigger (@triggers) {
          $result .= "$comma$trigger->{trigger} -> $trigger->{action}";
          $comma = ', ';
        }
      }
    }

    when ('add') {
      if ($from =~ m/^#/) {
        $channel = $from;
      } else {
        ($channel, $arguments) = split / /, $arguments, 2;
        if ($channel !~ m/^#/) {
          return "Usage from private message: actiontrigger add <channel> <regex> <action>";
        }
      }


      my ($trigger, $action) = split / /, $arguments, 2;

      if (not defined $trigger or not defined $action) {
        if ($from !~ m/^#/) {
          $result = "Usage from private message: actiontrigger add <channel> <regex> <action>";
        } else {
          $result = "Usage: actiontrigger add <regex> <action>";
        }
        return $result;
      }

      my $exists = $self->get_trigger($channel, $trigger);

      if (defined $exists) {
        return "Trigger already exists.";
      }

      if ($self->add_trigger($channel, $trigger, $action, "$nick!$user\@$host")) {
        $result = "Trigger added.";
      } else {
        $result = "Failed to add trigger.";
      }
    }

    when ('delete') {
      if ($from =~ m/^#/) {
        $channel = $from;
      } else {
        ($channel, $arguments) = split / /, $arguments, 2;
        if ($channel !~ m/^#/) {
          return "Usage from private message: actiontrigger delete <channel> <regex>";
        }
      }

      my ($trigger) = split / /, $arguments, 1;

      if (not defined $trigger) {
        if ($from !~ m/^#/) {
          $result = "Usage from private message: actiontrigger delete <channel> <regex>";
        } else {
          $result = "Usage: actiontrigger delete <regex>";
        }
        return $result;
      }

      my $exists = $self->get_trigger($channel, $trigger);

      if (not defined $exists) {
        $result = "No such trigger.";
      } else {
        $self->delete_trigger($channel, $trigger);
        $result = "Trigger deleted.";
      }
    }

    default {
      $result = "Usage: actiontrigger <list/add/delete> [arguments]";
    }
  }

  return $result;
}

sub on_action {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
  my $channel = $event->{event}->{to}[0];
  return 0 if $event->{interpreted};
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

  if (not $self->{dbh}) {
    return 0;
  }

  my @triggers = $self->list_triggers($channel);

  $text = "$nick!$user\@$host $text";

  foreach my $trigger (@triggers) {
    eval {
      if ($text  =~ m/$trigger->{trigger}/i) {
        my $action = $trigger->{action};
        my @stuff = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
        my $i;
        map { ++$i; $action =~ s/\$$i/$_/g; } @stuff; 
        
        my $delay = 0;

        my ($n, $u, $h) = $trigger->{owner} =~ /^([^!]+)!([^@]+)\@(.*)$/;
        my $command = { 
          nick => $n,
          user => $u,
          host => $h,
          command => $action
        };
        $self->{pbot}->{logger}->log("ActionTrigger: ($channel) $trigger->{trigger} -> $action\n");
        $self->{pbot}->{interpreter}->add_to_command_queue($channel, $command, $delay);
      }
    };

    if ($@) {
      $self->{pbot}->{logger}->log("Skipping bad trigger $trigger->{trigger}: $@");
    }
  }


  return 0;
}

1;
