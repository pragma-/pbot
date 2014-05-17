# File: MessageHistory_SQLite.pm
# Author: pragma_
#
# Purpose: SQLite backend for storing/retreiving a user's message history

package PBot::MessageHistory_SQLite;

use warnings;
use strict;

use DBI;
use Carp qw(shortmess);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference in " . __FILE__);
  $self->{filename}  = delete $conf{filename} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/message_history.sqlite3';

  $self->{pbot}->timer->register(sub { $self->commit_message_history }, 5);
  $self->{new_entries} = 0;
}

sub begin {
  my $self = shift;

  $self->{pbot}->logger->log("Opening message history SQLite database: $self->{filename}\n");

  $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", { RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1 }) or die $DBI::errstr; 

  eval {
    #$self->{dbh}->trace($self->{dbh}->parse_trace_flags('SQL|1|test'));

    $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Hostmasks (
  hostmask    TEXT PRIMARY KEY UNIQUE,
  id          INTEGER,
  last_seen   NUMERIC
)
SQL

    $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Accounts (
  id           INTEGER PRIMARY KEY,
  hostmask     TEXT UNIQUE,
  nickserv     TEXT
)
SQL

    $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Nickserv (
  id         INTEGER, 
  nickserv   TEXT,
  timestamp  NUMERIC
)
SQL

    $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Channels (
  id              INTEGER,
  channel         TEXT,
  enter_abuse     INTEGER,
  enter_abuses    INTEGER,
  offenses        INTEGER,
  last_offense    NUMERIC,
  last_seen       NUMERIC,
  validated       INTEGER,
  join_watch      INTEGER
)
SQL

    $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Messages (
  id         INTEGER,
  channel    TEXT,
  msg        TEXT,
  timestamp  NUMERIC,
  mode       INTEGER
)
SQL

    $self->{dbh}->begin_work();
  };
  $self->{pbot}->logger->log($@) if $@;
}

sub end {
  my $self = shift;

  $self->{pbot}->logger->log("Closing message history SQLite database\n");

  if(exists $self->{dbh} and defined $self->{dbh}) {
    $self->{dbh}->commit() if $self->{new_entries};
    $self->{dbh}->disconnect();
    delete $self->{dbh};
  }
}

sub get_nickserv_accounts {
  my ($self, $id) = @_;

  my $nickserv_accounts = eval {
    my $sth = $self->{dbh}->prepare('SELECT nickserv FROM Nickserv WHERE ID = ?');
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchall_arrayref();
  };
  $self->{pbot}->logger->log($@) if $@;
  return map {$_->[0]} @$nickserv_accounts;
}

sub set_current_nickserv_account {
  my ($self, $id, $nickserv) = @_;

  eval {
    my $sth = $self->{dbh}->prepare('UPDATE Accounts SET nickserv = ? WHERE id = ?');
    $sth->bind_param(1, $nickserv);
    $sth->bind_param(2, $id);
    $sth->execute();
    $self->{new_entries}++;
  };
  $self->{pbot}->logger->log($@) if $@;
}

sub get_current_nickserv_account {
  my ($self, $id) = @_;

  my $nickserv = eval {
    my $sth = $self->{dbh}->prepare('SELECT nickserv FROM Accounts WHERE id = ?');
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchrow_hashref()->{'nickserv'};
  };
  $self->{pbot}->logger->log($@) if $@;
  return $nickserv;
}

sub create_nickserv {
  my ($self, $id, $nickserv) = @_;

  eval {
    my $sth = $self->{dbh}->prepare('INSERT INTO Nickserv SELECT ?, ?, 0 WHERE NOT EXISTS (SELECT 1 FROM Nickserv WHERE id = ? AND nickserv = ?)');
    $sth->bind_param(1, $id);
    $sth->bind_param(2, $nickserv);
    $sth->bind_param(3, $id);
    $sth->bind_param(4, $nickserv);
    my $rv = $sth->execute();
    $self->{new_entries}++ if $sth->rows;
  };
  $self->{pbot}->logger->log($@) if $@;
}

sub update_nickserv_account {
  my ($self, $id, $nickserv, $timestamp) = @_;
  
  #$self->{pbot}->logger->log("Updating nickserv account for id $id to $nickserv with timestamp [$timestamp]\n");

  $self->create_nickserv($id, $nickserv);

  eval {
    my $sth = $self->{dbh}->prepare('UPDATE Nickserv SET timestamp = ? WHERE id = ? AND nickserv = ?');
    $sth->bind_param(1, $timestamp);
    $sth->bind_param(2, $id);
    $sth->bind_param(3, $nickserv);
    $sth->execute();
    $self->{new_entries}++;
  };
  $self->{pbot}->logger->log($@) if $@;
}

sub add_message_account {
  my ($self, $mask, $link_id) = @_;
  my $id;

  if(defined $link_id) {
    $id = $link_id;
  } else {
    $id = $self->get_new_account_id();
  }

  eval {
    my $sth = $self->{dbh}->prepare('INSERT INTO Hostmasks VALUES (?, ?, 0)');
    $sth->bind_param(1, $mask);
    $sth->bind_param(2, $id);
    $sth->execute();
    $self->{new_entries}++;

    if(not defined $link_id) {
      $sth = $self->{dbh}->prepare('INSERT INTO Accounts VALUES (?, ?, ?)');
      $sth->bind_param(1, $id);
      $sth->bind_param(2, $mask);
      $sth->bind_param(3, "");
      $sth->execute();
      $self->{new_entries}++;
    }
  };

  $self->{pbot}->logger->log($@) if $@;
  return $id;
}

sub find_message_account_by_nick {
  my ($self, $nick) = @_;

  my ($id, $hostmask) = eval {
    my $sth = $self->{dbh}->prepare('SELECT id,hostmask FROM Hostmasks WHERE hostmask LIKE ? LIMIT 1');
    $sth->bind_param(1, "$nick!%");
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return ($row->{id}, $row->{hostmask});
  };
  
  $self->{pbot}->logger->log($@) if $@;
  $hostmask =~ s/!.*$// if defined $hostmask;
  return ($id, $hostmask);
}

sub find_message_accounts_by_nickserv {
  my ($self, $nickserv) = @_;

  my $accounts = eval {
    my $sth = $self->{dbh}->prepare('SELECT id FROM Nickserv WHERE nickserv = ?');
    $sth->bind_param(1, $nickserv);
    $sth->execute();
    return $sth->fetchall_arrayref();
  };
  $self->{pbot}->logger->log($@) if $@;
  return map {$_->[0]} @$accounts;
}

sub find_message_accounts_by_mask {
  my ($self, $mask) = @_;

  $mask =~ s/\*/%/g;
  $mask =~ s/\?/_/g;
  $mask =~ s/\$.*$//;

  my $accounts = eval {
    my $sth = $self->{dbh}->prepare('SELECT id FROM Hostmasks WHERE hostmask LIKE ?');
    $sth->bind_param(1, $mask);
    $sth->execute();
    return $sth->fetchall_arrayref();
  };
  $self->{pbot}->logger->log($@) if $@;
  return map {$_->[0]} @$accounts;
}

sub get_message_account {
  my ($self, $nick, $user, $host) = @_;

  my $mask = "$nick!$user\@$host";
  my $id = $self->get_message_account_id($mask);
  return $id if defined $id;

  my $rows = eval {
    my $sth = $self->{dbh}->prepare('SELECT id,hostmask FROM Hostmasks WHERE hostmask LIKE ? ORDER BY last_seen DESC');
    $sth->bind_param(1, "$nick!%");
    $sth->execute();
    my $rows = $sth->fetchall_arrayref({});

    foreach my $row (@$rows) {
      $self->{pbot}->logger->log("Found matching nick $row->{hostmask} with id $row->{id}\n");
    }

    if(not defined $rows->[0]) {
      $sth->bind_param(1, "%!$user\@$host");
      $sth->execute();
      $rows = $sth->fetchall_arrayref({});

      foreach my $row (@$rows) {
        $self->{pbot}->logger->log("Found matching user\@host mask $row->{hostmask} with id $row->{id}\n");
      }
    }
    return $rows;
  };
  $self->{pbot}->logger->log($@) if $@;

  if(defined $rows->[0]) {
    $self->{pbot}->logger->log("message-history: [get-account] $nick!$user\@$host linked to $rows->[0]->{hostmask} with id $rows->[0]->{id}\n");
    $self->add_message_account("$nick!$user\@$host", $rows->[0]->{id});
    $self->devalidate_all_channels($rows->[0]->{id});
    my @nickserv_accounts = $self->get_nickserv_accounts($rows->[0]->{id});
    foreach my $nickserv_account (@nickserv_accounts) {
      $self->{pbot}->logger->log("$nick!$user\@$host [$rows->[0]->{id}] seen with nickserv account [$nickserv_account]\n");
      $self->{pbot}->antiflood->check_nickserv_accounts($nick, $nickserv_account, "$nick!$user\@$host"); 
    }
    return $rows->[0]->{id};
  }

  $self->{pbot}->logger->log("No account found for mask [$mask], adding new account\n");
  return $self->add_message_account($mask);
}

sub find_most_recent_hostmask {
  my ($self, $id) = @_;

  my $hostmask = eval {
    my $sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE ID = ? ORDER BY last_seen DESC LIMIT 1');
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchrow_hashref()->{'hostmask'};
  };
  $self->{pbot}->logger->log($@) if $@;
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

    $sql .= ' WHERE hostmask LIKE ?';

    my $sth = $self->{dbh}->prepare($sql);

    my $param = 1;
    foreach my $key (keys %$data) {
      $sth->bind_param($param++, $data->{$key});
    }

    $sth->bind_param($param, $mask);
    $sth->execute();
    $self->{new_entries}++;
  };
  $self->{pbot}->logger->log($@) if $@;
}

sub get_hostmasks_for_channel {
  my ($self, $channel) = @_;

  my $hostmasks = eval {
    my $sth = $self->{dbh}->prepare('SELECT hostmasks.id, hostmask FROM Hostmasks, Channels WHERE channels.id = hostmasks.id AND channel = ?');
    $sth->bind_param(1, $channel);
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };
  
  $self->{pbot}->logger->log($@) if $@;
  return $hostmasks;
}

sub add_message {
  my ($self, $id, $mask, $channel, $message) = @_;

  #$self->{pbot}->logger->log("Adding message [$id][$mask][$channel][$message->{msg}][$message->{timestamp}][$message->{mode}]\n");

  eval {
    my $sth = $self->{dbh}->prepare('INSERT INTO Messages VALUES (?, ?, ?, ?, ?)');
    $sth->bind_param(1, $id);
    $sth->bind_param(2, $channel);
    $sth->bind_param(3, $message->{msg});
    $sth->bind_param(4, $message->{timestamp});
    $sth->bind_param(5, $message->{mode});
    $sth->execute();
    $self->{new_entries}++;
  };
  $self->{pbot}->logger->log($@) if $@;
  $self->update_channel_data($id, $channel, { last_seen => $message->{timestamp} });
  $self->update_hostmask_data($mask, { last_seen => $message->{timestamp} });
}

sub get_recent_messages {
  my ($self, $id, $channel, $limit, $mode) = @_;
  $limit = 25 if not defined $limit;

  my $mode_query = '';
  $mode_query = "AND mode = $mode" if defined $mode;

  my $messages = eval {
    my $sth = $self->{dbh}->prepare(<<SQL);
SELECT msg, mode, timestamp
FROM Messages
WHERE id = ? AND channel = ? $mode_query
ORDER BY timestamp ASC 
LIMIT ? OFFSET (SELECT COUNT(*) FROM Messages WHERE id = ? AND channel = ? $mode_query) - ?
SQL
    $sth->bind_param(1, $id);
    $sth->bind_param(2, $channel);
    $sth->bind_param(3, $limit);
    $sth->bind_param(4, $id);
    $sth->bind_param(5, $channel);
    $sth->bind_param(6, $limit);
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };
  $self->{pbot}->logger->log($@) if $@;
  return $messages;
}

sub recall_message_by_count {
  my ($self, $id, $channel, $count, $ignore_command) = @_;

  my $messages;

  if(defined $id) {
    $messages = eval {
      my $sth = $self->{dbh}->prepare('SELECT msg, mode, timestamp FROM Messages WHERE id = ? AND channel = ? ORDER BY timestamp DESC LIMIT 10 OFFSET ?');
      $sth->bind_param(1, $id);
      $sth->bind_param(2, $channel);
      $sth->bind_param(3, $count);
      $sth->execute();
      return $sth->fetchall_arrayref({});
    };
  } else {
    $messages = eval {
      my $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp FROM Messages WHERE channel = ? ORDER BY timestamp DESC LIMIT 10 OFFSET ?');
      $sth->bind_param(1, $channel);
      $sth->bind_param(2, $count);
      $sth->execute();
      return $sth->fetchall_arrayref({});
    };
  }

  $self->{pbot}->logger->log($@) if $@;

  if(defined $ignore_command) {
    my $botnick     = $self->{pbot}->{registry}->get_value('irc',     'botnick');
    my $bot_trigger = $self->{pbot}->{registry}->get_value('general', 'trigger');
    foreach my $message (@$messages) {
      next if $message->{msg} =~ m/^$botnick. $ignore_command/ or $message->{msg} =~ m/^$bot_trigger$ignore_command/;
      return $message;
    }
    return undef;
  }
  return $messages->[0];
}

sub recall_message_by_text {
  my ($self, $id, $channel, $text, $ignore_command) = @_;
  
  $text =~ s/\.\*\?/%/g;
  $text =~ s/\.\*/%/g;
  $text =~ s/\*/%/g;
  $text =~ s/\?/_/g;

  my $messages;

  if(defined $id) {
    $messages = eval {
      my $sth = $self->{dbh}->prepare('SELECT msg,mode,timestamp FROM Messages WHERE id = ? AND channel = ? AND msg LIKE ? ORDER BY timestamp DESC LIMIT 10');
      $sth->bind_param(1, $id);
      $sth->bind_param(2, $channel);
      $sth->bind_param(3, "%$text%");
      $sth->execute();
      return $sth->fetchall_arrayref({});
    };
  } else {
    $messages = eval {
      my $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp FROM Messages WHERE channel = ? AND msg LIKE ? ORDER BY timestamp DESC LIMIT 10');
      $sth->bind_param(1, $channel);
      $sth->bind_param(2, "%$text%");
      $sth->execute();
      return $sth->fetchall_arrayref({});
    };
  }

  $self->{pbot}->logger->log($@) if $@;

  if(defined $ignore_command) {
    my $bot_trigger = $self->{pbot}->{registry}->get_value('general', 'trigger');
    my $botnick     = $self->{pbot}->{registry}->get_value('irc',     'botnick');
    foreach my $message (@$messages) {
      next if $message->{msg} =~ m/^$botnick. $ignore_command/ or $message->{msg} =~ m/^$bot_trigger$ignore_command/;
      return $message;
    }
    return undef;
  }
  return $messages->[0];
}

sub get_max_messages {
  my ($self, $id,  $channel) = @_;

  my $count = eval {
    my $sth = $self->{dbh}->prepare('SELECT COUNT(*) FROM Messages WHERE id = ? AND channel = ?');
    $sth->bind_param(1, $id);
    $sth->bind_param(2, $channel);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    return $row->{'COUNT(*)'};
  };
  $self->{pbot}->logger->log($@) if $@;
  $count = 0 if not defined $count;
  return $count;
}

sub create_channel {
  my ($self, $id, $channel) = @_;

  eval {
    my $sth = $self->{dbh}->prepare('INSERT INTO Channels SELECT ?, ?, 0, 0, 0, 0, 0, 0, 0 WHERE NOT EXISTS (SELECT 1 FROM Channels WHERE id = ? AND channel = ?)');
    $sth->bind_param(1, $id);
    $sth->bind_param(2, $channel);
    $sth->bind_param(3, $id);
    $sth->bind_param(4, $channel);
    my $rv = $sth->execute();
    $self->{new_entries}++ if $sth->rows;
  };
  $self->{pbot}->logger->log($@) if $@;
}

sub get_channels {
  my ($self, $id) = @_;

  my $channels = eval {
    my $sth = $self->{dbh}->prepare('SELECT channel FROM Channels WHERE id = ?');
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchall_arrayref();
  };
  $self->{pbot}->logger->log($@) if $@;
  return map {$_->[0]} @$channels;
}

sub get_channel_data {
  my ($self, $id, $channel, @columns) = @_;

  $self->create_channel($id, $channel);

  my $channel_data = eval {
    my $sql = 'SELECT ';

    if(not @columns) {
      $sql .= '*';
    } else {
      my $comma = '';
      foreach my $column (@columns) {
        $sql .= "$comma$column";
        $comma = ', ';
      }
    }

    $sql .= ' FROM Channels WHERE id = ? AND channel = ?';
    my $sth = $self->{dbh}->prepare($sql);
    $sth->bind_param(1, $id);
    $sth->bind_param(2, $channel);
    $sth->execute();
    return $sth->fetchrow_hashref();
  };
  $self->{pbot}->logger->log($@) if $@;
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
    foreach my $key (keys %$data) {
      $sth->bind_param($param++, $data->{$key});
    }

    $sth->bind_param($param++, $id);
    $sth->bind_param($param, $channel);
    $sth->execute();
    $self->{new_entries}++;
  };
  $self->{pbot}->logger->log($@) if $@;
}

sub get_channel_datas_where_last_offense_older_than {
  my ($self, $timestamp) = @_;

  my $channel_datas = eval {
    my $sth = $self->{dbh}->prepare('SELECT id, channel, offenses, last_offense FROM Channels WHERE last_offense > 0 AND last_offense <= ?');
    $sth->bind_param(1, $timestamp);
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };
  $self->{pbot}->logger->log($@) if $@;
  return $channel_datas;
}

sub get_channel_datas_with_enter_abuses {
  my ($self) = @_;

  my $channel_datas = eval {
    my $sth = $self->{dbh}->prepare('SELECT id, channel, enter_abuses FROM Channels WHERE enter_abuses > 0');
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };
  $self->{pbot}->logger->log($@) if $@;
  return $channel_datas;
}

sub devalidate_all_channels {
  my ($self, $id) = @_;

  my $where = '';
  $where = 'WHERE id = ?' if defined $id;

  eval {
    my $sth = $self->{dbh}->prepare("UPDATE Channels SET validated = 0 $where");
    $sth->bind_param(1, $id) if defined $id;
    $sth->execute();
    $self->{new_entries}++;
  };
  $self->{pbot}->logger->log($@) if $@;
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

  $self->{pbot}->logger->log($@) if $@;
  return ++$id;
}

sub get_message_account_id {
  my ($self, $mask) = @_;

  my $id = eval {
    my $sth = $self->{dbh}->prepare('SELECT id FROM Hostmasks WHERE hostmask == ?');
    $sth->bind_param(1, $mask);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return $row->{id};
  };

  $self->{pbot}->logger->log($@) if $@;
  #$self->{pbot}->logger->log("get_message_account_id: returning id [". (defined $id ? $id: 'undef') . "] for mask [$mask]\n");
  return $id;
}

sub commit_message_history {
  my $self = shift;

  if($self->{new_entries} > 0) {
    #$self->{pbot}->logger->log("Commiting $self->{new_entries} messages to SQLite\n");
    eval {
      $self->{dbh}->commit();
    };

    $self->{pbot}->logger->log("SQLite error $@ when committing $self->{new_entries} entries.\n") if $@;

    $self->{dbh}->begin_work();
    $self->{new_entries} = 0;
  }
}

1;
