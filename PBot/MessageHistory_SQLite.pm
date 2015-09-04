# File: MessageHistory_SQLite.pm
# Author: pragma_
#
# Purpose: SQLite backend for storing/retreiving a user's message history

package PBot::MessageHistory_SQLite;

use warnings;
use strict;

use DBI;
use Carp qw(shortmess);
use Time::HiRes qw(gettimeofday);

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
  $self->{new_entries} = 0;

  $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'debug_link',             0);
  $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'debug_aka',              0);
  $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'sqlite_commit_interval', 30);
  $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'sqlite_debug',           $conf{sqlite_debug} // 0);

  $self->{pbot}->{registry}->add_trigger('messagehistory', 'sqlite_commit_interval', sub { $self->sqlite_commit_interval_trigger(@_) });
  $self->{pbot}->{registry}->add_trigger('messagehistory', 'sqlite_debug',           sub { $self->sqlite_debug_trigger(@_) });

  $self->{pbot}->{timer}->register(
    sub { $self->commit_message_history },
    $self->{pbot}->{registry}->get_value('messagehistory', 'sqlite_commit_interval'),
    'messagehistory_sqlite_commit_interval'
  );

  $self->{alias_type}->{WEAK}   = 0;
  $self->{alias_type}->{STRONG} = 1;
}

sub sqlite_commit_interval_trigger {
  my ($self, $section, $item, $newvalue) = @_;
  $self->{pbot}->{timer}->update_interval('messagehistory_sqlite_commit_interval', $newvalue);
}

sub sqlite_debug_trigger {
  my ($self, $section, $item, $newvalue) = @_;
  $self->{dbh}->trace($self->{dbh}->parse_trace_flags("SQL|$newvalue")) if defined $self->{dbh};
  
}

sub begin {
  my $self = shift;

  $self->{pbot}->{logger}->log("Opening message history SQLite database: $self->{filename}\n");

  $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", { RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1 }) or die $DBI::errstr; 

  $self->{dbh}->sqlite_enable_load_extension(my $_enabled = 1);
  $self->{dbh}->prepare("SELECT load_extension('/usr/lib/sqlite3/pcre.so')");

  eval {
    my $sqlite_debug = $self->{pbot}->{registry}->get_value('messagehistory', 'sqlite_debug');
    use PBot::SQLiteLoggerLayer;
    use PBot::SQLiteLogger;
    open $self->{trace_layer}, '>:via(PBot::SQLiteLoggerLayer)', PBot::SQLiteLogger->new(pbot => $self->{pbot});
    $self->{dbh}->trace($self->{dbh}->parse_trace_flags("SQL|$sqlite_debug"), $self->{trace_layer});

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

    $self->{dbh}->begin_work();
  };
  $self->{pbot}->{logger}->log($@) if $@;
}

sub end {
  my $self = shift;

  $self->{pbot}->{logger}->log("Closing message history SQLite database\n");

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
  $self->{pbot}->{logger}->log($@) if $@;
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
  $self->{pbot}->{logger}->log($@) if $@;
}

sub get_current_nickserv_account {
  my ($self, $id) = @_;

  my $nickserv = eval {
    my $sth = $self->{dbh}->prepare('SELECT nickserv FROM Accounts WHERE id = ?');
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchrow_hashref()->{'nickserv'};
  };
  $self->{pbot}->{logger}->log($@) if $@;
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
  $self->{pbot}->{logger}->log($@) if $@;
}

sub update_nickserv_account {
  my ($self, $id, $nickserv, $timestamp) = @_;
  
  #$self->{pbot}->{logger}->log("Updating nickserv account for id $id to $nickserv with timestamp [$timestamp]\n");

  $self->create_nickserv($id, $nickserv);

  eval {
    my $sth = $self->{dbh}->prepare('UPDATE Nickserv SET timestamp = ? WHERE id = ? AND nickserv = ?');
    $sth->bind_param(1, $timestamp);
    $sth->bind_param(2, $id);
    $sth->bind_param(3, $nickserv);
    $sth->execute();
    $self->{new_entries}++;
  };
  $self->{pbot}->{logger}->log($@) if $@;
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

  $self->{pbot}->{logger}->log($@) if $@;
  return $id;
}

sub find_message_account_by_nick {
  my ($self, $nick) = @_;

  my ($id, $hostmask) = eval {
    my $sth = $self->{dbh}->prepare('SELECT id, hostmask FROM Hostmasks WHERE hostmask LIKE ? ESCAPE "\" ORDER BY last_seen DESC LIMIT 1');
    my $qnick = quotemeta $nick;
    $qnick =~ s/_/\\_/g;
    $sth->bind_param(1, "$qnick!%");
    $sth->execute();
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
    $sth->bind_param(1, $nickserv);
    $sth->execute();
    return $sth->fetchall_arrayref();
  };
  $self->{pbot}->{logger}->log($@) if $@;
  return map {$_->[0]} @$accounts;
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
    $sth->bind_param(1, $qmask);
    $sth->execute();
    return $sth->fetchall_arrayref();
  };
  $self->{pbot}->{logger}->log($@) if $@;
  return map {$_->[0]} @$accounts;
}

sub get_message_account {
  my ($self, $nick, $user, $host, $link_nick) = @_;

  my $mask = "$nick!$user\@$host";
  my $id = $self->get_message_account_id($mask);
  return $id if defined $id;

  my $rows = eval {
    my $sth = $self->{dbh}->prepare('SELECT id, hostmask FROM Hostmasks WHERE hostmask LIKE ? ESCAPE "\" ORDER BY last_seen DESC');

    if ($host =~ m{^gateway/web/irccloud.com}) {
      $sth->bind_param(1, "%!$user\@gateway/web/irccloud.com/%");
      $sth->execute();
      my $rows = $sth->fetchall_arrayref({});
      if (defined $rows->[0]) {
        return $rows;
      }
    }

    my $qnick = quotemeta (defined $link_nick ? $link_nick : $nick);
    $qnick =~ s/_/\\_/g;
    $sth->bind_param(1, "$qnick!%");
    $sth->execute();
    my $rows = $sth->fetchall_arrayref({});

=cut
    foreach my $row (@$rows) {
      $self->{pbot}->{logger}->log("Found matching nick $row->{hostmask} with id $row->{id}\n");
    }
=cut

    if(not defined $rows->[0]) {
      $sth->bind_param(1, "%!$user\@$host");
      $sth->execute();
      $rows = $sth->fetchall_arrayref({});

=cut
      foreach my $row (@$rows) {
        $self->{pbot}->{logger}->log("Found matching user\@host mask $row->{hostmask} with id $row->{id}\n");
      }
=cut
    }
    return $rows;
  };
  $self->{pbot}->{logger}->log($@) if $@;

  if(defined $rows->[0]) {
    $self->{pbot}->{logger}->log("message-history: [get-account] $nick!$user\@$host linked to $rows->[0]->{hostmask} with id $rows->[0]->{id}\n");
    $self->add_message_account("$nick!$user\@$host", $rows->[0]->{id});
    $self->devalidate_all_channels($rows->[0]->{id});
    $self->update_hostmask_data("$nick!$user\@$host", { last_seen => scalar gettimeofday });
    my @nickserv_accounts = $self->get_nickserv_accounts($rows->[0]->{id});
    foreach my $nickserv_account (@nickserv_accounts) {
      $self->{pbot}->{logger}->log("$nick!$user\@$host [$rows->[0]->{id}] seen with nickserv account [$nickserv_account]\n");
      $self->{pbot}->{antiflood}->check_nickserv_accounts($nick, $nickserv_account, "$nick!$user\@$host"); 
    }
    return $rows->[0]->{id};
  }

  $self->{pbot}->{logger}->log("No account found for mask [$mask], adding new account\n");
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

    $sql .= ' WHERE hostmask LIKE ? ESCAPE "\"';

    my $sth = $self->{dbh}->prepare($sql);

    my $param = 1;
    foreach my $key (keys %$data) {
      $sth->bind_param($param++, $data->{$key});
    }

    my $qmask = quotemeta $mask;
    $qmask =~ s/_/\\_/g;
    $sth->bind_param($param, $qmask);
    $sth->execute();
    $self->{new_entries}++;
  };
  $self->{pbot}->{logger}->log($@) if $@;
}

sub get_nickserv_accounts_for_hostmask {
  my ($self, $hostmask) = @_;

  my $nickservs = eval {
    my $sth = $self->{dbh}->prepare('SELECT nickserv FROM Hostmasks, Nickserv WHERE nickserv.id = hostmasks.id AND hostmasks.hostmask = ?');
    $sth->bind_param(1, $hostmask);
    $sth->execute();
    return $sth->fetchall_arrayref();
  };

  $self->{pbot}->{logger}->log($@) if $@;
  return map {$_->[0]} @$nickservs;
}

sub get_hostmasks_for_channel {
  my ($self, $channel) = @_;

  my $hostmasks = eval {
    my $sth = $self->{dbh}->prepare('SELECT hostmasks.id, hostmask FROM Hostmasks, Channels WHERE channels.id = hostmasks.id AND channel = ?');
    $sth->bind_param(1, $channel);
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };
  
  $self->{pbot}->{logger}->log($@) if $@;
  return $hostmasks;
}

sub get_hostmasks_for_nickserv {
  my ($self, $nickserv) = @_;

  my $hostmasks = eval {
    my $sth = $self->{dbh}->prepare('SELECT hostmasks.id, hostmask, nickserv FROM Hostmasks, Nickserv WHERE nickserv.id = hostmasks.id AND nickserv = ?');
    $sth->bind_param(1, $nickserv);
    $sth->execute();
    return $sth->fetchall_arrayref({});
  };

  $self->{pbot}->{logger}->log($@) if $@;
  return $hostmasks;
}

sub add_message {
  my ($self, $id, $mask, $channel, $message) = @_;

  #$self->{pbot}->{logger}->log("Adding message [$id][$mask][$channel][$message->{msg}][$message->{timestamp}][$message->{mode}]\n");

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
  $self->{pbot}->{logger}->log($@) if $@;
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
  $self->{pbot}->{logger}->log($@) if $@;
  return $messages;
}

sub get_message_context {
  my ($self, $message, $before, $after, $count, $text, $context_id) = @_;

  my ($messages_before, $messages_after, $messages_count);

  if (defined $count and $count > 1) {
    my $regex = '(?i)';
    $regex .= ($text =~ m/^\w/) ? '\b' : '\B';
    $regex .= quotemeta $text;
    $regex .= ($text =~ m/\w$/) ? '\b' : '\B';
    $regex =~ s/\\\*/.*?/g;

    $messages_count = eval {
      my $sth;
      if (defined $context_id) {
        $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE id = ? AND channel = ? AND msg REGEXP ? AND timestamp < ? AND mode = 0 ORDER BY timestamp DESC LIMIT ?');
        $sth->bind_param(1, $context_id);
        $sth->bind_param(2, $message->{channel});
        $sth->bind_param(3, $regex);
        $sth->bind_param(4, $message->{timestamp});
        $sth->bind_param(5, $count - 1);
      } else {
        $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE channel = ? AND msg REGEXP ? AND timestamp < ? AND mode = 0 ORDER BY timestamp DESC LIMIT ?');
        $sth->bind_param(1, $message->{channel});
        $sth->bind_param(2, $regex);
        $sth->bind_param(3, $message->{timestamp});
        $sth->bind_param(4, $count - 1);
      }
      $sth->execute();
      return [reverse @{$sth->fetchall_arrayref({})}];
    };
    $self->{pbot}->{logger}->log($@) if $@;
  }

  if (defined $before and $before > 0) {
    $messages_before = eval {
      my $sth;
      if (defined $context_id) {
        $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE id = ? AND channel = ? AND timestamp < ? AND mode = 0 ORDER BY timestamp DESC LIMIT ?');
        $sth->bind_param(1, $context_id);
        $sth->bind_param(2, $message->{channel});
        $sth->bind_param(3, $message->{timestamp});
        $sth->bind_param(4, $before);
      } else {
        $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE channel = ? AND timestamp < ? AND mode = 0 ORDER BY timestamp DESC LIMIT ?');
        $sth->bind_param(1, $message->{channel});
        $sth->bind_param(2, $message->{timestamp});
        $sth->bind_param(3, $before);
      }
      $sth->execute();
      return [reverse @{$sth->fetchall_arrayref({})}];
    };
    $self->{pbot}->{logger}->log($@) if $@;
  }

  if (defined $after and $after > 0) {
    $messages_after = eval {
      my $sth;
      if (defined $context_id) {
        $sth  = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE id = ? AND channel = ? AND timestamp > ? AND mode = 0 LIMIT ?');
        $sth->bind_param(1, $context_id);
        $sth->bind_param(2, $message->{channel});
        $sth->bind_param(3, $message->{timestamp});
        $sth->bind_param(4, $after);
      } else {
        $sth  = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE channel = ? AND timestamp > ? AND mode = 0 LIMIT ?');
        $sth->bind_param(1, $message->{channel});
        $sth->bind_param(2, $message->{timestamp});
        $sth->bind_param(3, $after);
      }
      $sth->execute();
      return $sth->fetchall_arrayref({});
    };
    $self->{pbot}->{logger}->log($@) if $@;
  }

  my @messages;
  push(@messages, @$messages_before) if defined $messages_before;
  push(@messages, @$messages_count) if defined $messages_count;
  push(@messages, $message);
  push(@messages, @$messages_after)  if defined $messages_after;

  my %nicks;
  foreach my $msg (@messages) {
    if (not exists $nicks{$msg->{id}}) {
      my $hostmask = $self->find_most_recent_hostmask($msg->{id});
      my ($nick) = $hostmask =~ m/^([^!]+)/;
      $nicks{$msg->{id}} = $nick;
    }
    $msg->{nick} = $nicks{$msg->{id}};
  }

  return \@messages;
}

sub recall_message_by_count {
  my ($self, $id, $channel, $count, $ignore_command) = @_;

  my $messages;

  if(defined $id) {
    $messages = eval {
      my $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE id = ? AND channel = ? ORDER BY timestamp DESC LIMIT 10 OFFSET ?');
      $sth->bind_param(1, $id);
      $sth->bind_param(2, $channel);
      $sth->bind_param(3, $count);
      $sth->execute();
      return $sth->fetchall_arrayref({});
    };
  } else {
    $messages = eval {
      my $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE channel = ? ORDER BY timestamp DESC LIMIT 10 OFFSET ?');
      $sth->bind_param(1, $channel);
      $sth->bind_param(2, $count);
      $sth->execute();
      return $sth->fetchall_arrayref({});
    };
  }

  $self->{pbot}->{logger}->log($@) if $@;

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
  
  my $regex = '(?i)';
  $regex .= ($text =~ m/^\w/) ? '\b' : '\B';
  $regex .= quotemeta $text;
  $regex .= ($text =~ m/\w$/) ? '\b' : '\B';
  $regex =~ s/\\\*/.*?/g;

  my $messages;

  if(defined $id) {
    $messages = eval {
      my $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE id = ? AND channel = ? AND msg REGEXP ? ORDER BY timestamp DESC LIMIT 10');
      $sth->bind_param(1, $id);
      $sth->bind_param(2, $channel);
      $sth->bind_param(3, $regex);
      $sth->execute();
      return $sth->fetchall_arrayref({});
    };
  } else {
    $messages = eval {
      my $sth = $self->{dbh}->prepare('SELECT id, msg, mode, timestamp, channel FROM Messages WHERE channel = ? AND msg REGEXP ? ORDER BY timestamp DESC LIMIT 10');
      $sth->bind_param(1, $channel);
      $sth->bind_param(2, $regex);
      $sth->execute();
      return $sth->fetchall_arrayref({});
    };
  }

  $self->{pbot}->{logger}->log($@) if $@;

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
  $self->{pbot}->{logger}->log($@) if $@;
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
  $self->{pbot}->{logger}->log($@) if $@;
}

sub get_channels {
  my ($self, $id) = @_;

  my $channels = eval {
    my $sth = $self->{dbh}->prepare('SELECT channel FROM Channels WHERE id = ?');
    $sth->bind_param(1, $id);
    $sth->execute();
    return $sth->fetchall_arrayref();
  };
  $self->{pbot}->{logger}->log($@) if $@;
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
    foreach my $key (keys %$data) {
      $sth->bind_param($param++, $data->{$key});
    }

    $sth->bind_param($param++, $id);
    $sth->bind_param($param, $channel);
    $sth->execute();
    $self->{new_entries}++;
  };
  $self->{pbot}->{logger}->log($@) if $@;
}

sub get_channel_datas_where_last_offense_older_than {
  my ($self, $timestamp) = @_;

  my $channel_datas = eval {
    my $sth = $self->{dbh}->prepare('SELECT id, channel, offenses, last_offense FROM Channels WHERE last_offense > 0 AND last_offense <= ?');
    $sth->bind_param(1, $timestamp);
    $sth->execute();
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

  $self->{pbot}->{logger}->log("Linking [$account][" . ($hostmask?$hostmask:'undef') . "][" . ($nickserv?$nickserv:'undef') . "]\n") if $debug_link;

  eval {
    my %ids;

    if ($hostmask) {
      my ($host) = $hostmask =~ /(\@.*)$/;
      my $sth = $self->{dbh}->prepare('SELECT id, last_seen FROM Hostmasks WHERE hostmask LIKE ?');
      $sth->bind_param(1, "\%$host");
      $sth->execute();
      my $rows = $sth->fetchall_arrayref({});

      my $now = gettimeofday;

      foreach my $row (@$rows) {
        if ($now - $row->{last_seen} <= 60 * 60 * 48) {
          $ids{$row->{id}} = { id => $row->{id}, type => $self->{alias_type}->{STRONG} };
          $self->{pbot}->{logger}->log("found STRONG matching id $row->{id} for host [$host]\n") if $debug_link;
        } else {
          $ids{$row->{id}} = { id => $row->{id}, type => $self->{alias_type}->{WEAK} };
          $self->{pbot}->{logger}->log("found WEAK matching id $row->{id} for host [$host]\n") if $debug_link;
        }
      }

      my ($nick) = $hostmask =~ m/([^!]+)/;
      unless ($nick =~ m/^Guest\d+$/) {
        my $qnick = quotemeta $nick;
        $qnick =~ s/_/\\_/g;

        my $sth = $self->{dbh}->prepare('SELECT id FROM Hostmasks WHERE hostmask LIKE ? ESCAPE "\"');
        $sth->bind_param(1, "$qnick!%");
        $sth->execute();
        my $rows = $sth->fetchall_arrayref({});

        foreach my $row (@$rows) {
          $ids{$row->{id}} = { id => $row->{id}, type => $self->{alias_type}->{STRONG} };
          $self->{pbot}->{logger}->log("found STRONG matching id $row->{id} for nick [$qnick]\n") if $debug_link;
        }
      }
    }

    if ($nickserv) {
      my $sth = $self->{dbh}->prepare('SELECT id FROM Nickserv WHERE nickserv = ?');
      $sth->bind_param(1, $nickserv);
      $sth->execute();
      my $rows = $sth->fetchall_arrayref({});

      foreach my $row (@$rows) {
        $ids{$row->{id}} = { id => $row->{id}, type => $self->{alias_type}->{STRONG} };
        $self->{pbot}->{logger}->log("found STRONG matching id $row->{id} for nickserv [$nickserv]\n") if $debug_link;
      }
    }

    my $sth = $self->{dbh}->prepare('REPLACE INTO Aliases (id, alias, type) VALUES (?, ?, ?)');

    foreach my $id (sort keys %ids) {
      next if $account == $id;
      $sth->bind_param(1, $account);
      $sth->bind_param(2, $id);
      $sth->bind_param(3, $ids{$id}->{type});
      $sth->execute();
      if ($sth->rows) {
        $self->{pbot}->{logger}->log("Linked $account to $id [$ids{$id}->{type}]\n") if $debug_link;
        $self->{new_entries}++;
      }

      $sth->bind_param(1, $id);
      $sth->bind_param(2, $account);
      $sth->bind_param(3, $ids{$id}->{type});
      $sth->execute();
      if ($sth->rows) {
        $self->{pbot}->{logger}->log("Linked $id to $account [$ids{$id}->{type}]\n") if $debug_link;
        $self->{new_entries}++;
      }
    }
  };
  $self->{pbot}->{logger}->log($@) if $@;
}

sub link_alias {
  my ($self, $id, $alias, $type) = @_;

  my $ret = eval {
    my $ret = 0;

    my $sth = $self->{dbh}->prepare('INSERT INTO Aliases SELECT ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM Aliases WHERE id = ? AND alias = ?)');
    $sth->bind_param(1, $alias);
    $sth->bind_param(2, $id);
    $sth->bind_param(3, $type);
    $sth->bind_param(4, $alias);
    $sth->bind_param(5, $id);
    $sth->execute();
    if ($sth->rows) {
      $self->{new_entries}++;
      $ret = 1;
    } else {
      $sth = $self->{dbh}->prepare('UPDATE Aliases SET type = ? WHERE id = ? AND alias = ?');
      $sth->bind_param(1, $type);
      $sth->bind_param(2, $id);
      $sth->bind_param(3, $alias);
      $sth->execute();
      if ($sth->rows) {
        $self->{new_entries}++;
        $ret = 1;
      }
    }

    $sth = $self->{dbh}->prepare('INSERT INTO Aliases SELECT ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM Aliases WHERE id = ? AND alias = ?)');
    $sth->bind_param(1, $id);
    $sth->bind_param(2, $alias);
    $sth->bind_param(3, $type);
    $sth->bind_param(4, $id);
    $sth->bind_param(5, $alias);
    $sth->execute();
    if ($sth->rows) {
      $self->{new_entries}++;
      $ret = 1;
    } else {
      $sth = $self->{dbh}->prepare('UPDATE Aliases SET type = ? WHERE id = ? AND alias = ?');
      $sth->bind_param(1, $type);
      $sth->bind_param(2, $alias);
      $sth->bind_param(3, $id);
      $sth->execute();
      if ($sth->rows) {
        $self->{new_entries}++;
        $ret = 1;
      } else {
        $ret = 0;
      }
    }
    return $ret;
  };
  $self->{pbot}->{logger}->log($@) if $@;
  return $ret;
}

sub unlink_alias {
  my ($self, $id, $alias) = @_;

  my $ret = eval {
    my $ret = 0;
    my $sth = $self->{dbh}->prepare('DELETE FROM Aliases WHERE id = ? AND alias = ?');
    $sth->bind_param(1, $id);
    $sth->bind_param(2, $alias);
    $sth->execute();
    if ($sth->rows) {
      $self->{new_entries}++;
      $ret = 1;
    }

    $sth->bind_param(1, $alias);
    $sth->bind_param(2, $id);
    $sth->execute();
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

  eval {
    $self->{dbh}->commit();
  };

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

      $sth->bind_param(1, $row->{id});
      $sth->execute();
      my $nrows = $sth->fetchall_arrayref({});

      foreach my $nrow (@$nrows) {
        $self->link_aliases($row->{id}, undef, $nrow->{nickserv});
      }
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

      if (not defined $id) {
        return %akas;
      }

      $ids{$id} = { id => $id, type => $self->{alias_type}->{STRONG} };
      $self->{pbot}->{logger}->log("Adding $id -> $id\n") if $debug;


      my $sth = $self->{dbh}->prepare('SELECT alias, type FROM Aliases WHERE id = ?');
      $sth->bind_param(1, $id);
      $sth->execute();
      my $rows = $sth->fetchall_arrayref({});

      foreach my $row (@$rows) {
        next if $row->{type} == $self->{alias_type}->{WEAK};
        $ids{$row->{alias}} = { id => $id, type => $row->{type} };
        $self->{pbot}->{logger}->log("[$id] 1) Adding $row->{alias} -> $id [type $row->{type}]\n") if $debug;
      }

      my %seen_id;
      $sth = $self->{dbh}->prepare('SELECT id, type FROM Aliases WHERE alias = ?');

      while (1) {
        my $new_aliases = 0;
        foreach my $id (keys %ids) {
          next if exists $seen_id{$id};
          $seen_id{$id} = $id;

          $sth->bind_param(1, $id);
          $sth->execute();
          my $rows = $sth->fetchall_arrayref({});

          foreach my $row (@$rows) {
            next if exists $ids{$row->{id}};
            next if $row->{type} == $self->{alias_type}->{WEAK};
            $ids{$row->{id}} = { id => $id, type => $row->{type} };
            $new_aliases++;
            $self->{pbot}->{logger}->log("[$id] 2) Adding $row->{id} -> $id [type $row->{type}]\n") if $debug;
          }
        }
        last if not $new_aliases;
      }

      my $hostmask_sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE id = ?');
      my $nickserv_sth = $self->{dbh}->prepare('SELECT nickserv FROM Nickserv WHERE id = ?');

      foreach my $id (keys %ids) {
        $hostmask_sth->bind_param(1, $id);
        $hostmask_sth->execute();
        $rows = $hostmask_sth->fetchall_arrayref({});

        foreach my $row (@$rows) {
          $akas{$row->{hostmask}} = { hostmask => $row->{hostmask}, id => $id, alias => $ids{$id}->{id}, type => $ids{$id}->{type} };
          $self->{pbot}->{logger}->log("[$id] Adding hostmask $row->{hostmask} -> $ids{$id}->{id} [type $ids{$id}->{type}]\n") if $debug;
        }

        $nickserv_sth->bind_param(1, $id);
        $nickserv_sth->execute();
        $rows = $nickserv_sth->fetchall_arrayref({});

        foreach my $row (@$rows) {
          foreach my $aka (keys %akas) {
            if ($akas{$aka}->{id} == $id) {
              if (exists $akas{$aka}->{nickserv}) {
                $akas{$aka}->{nickserv} .= ",$row->{nickserv}";
              } else {
                $akas{$aka}->{nickserv} = $row->{nickserv};
              }
            }
          }
        }
      }

      return %akas;
    }

    my $sth = $self->{dbh}->prepare('SELECT id, hostmask FROM Hostmasks WHERE hostmask LIKE ? ESCAPE "\" ORDER BY last_seen DESC');
    my $qnick = quotemeta $nick;
    $qnick =~ s/_/\\_/g;
    $sth->bind_param(1, "$qnick!%");
    $sth->execute();
    my $rows = $sth->fetchall_arrayref({});

    foreach my $row (@$rows) {
      $hostmasks{$row->{hostmask}} = $row->{id};
      $ids{$row->{id}} = $row->{hostmask};
      $akas{$row->{hostmask}} = { hostmask => $row->{hostmask}, id => $row->{id} };
      $self->{pbot}->{logger}->log("Found matching nick [$nick] for hostmask $row->{hostmask} with id $row->{id}\n");
    }

    foreach my $hostmask (keys %hostmasks) {
      my ($host) = $hostmask =~ /(\@.*)$/;
      $sth = $self->{dbh}->prepare('SELECT id FROM Hostmasks WHERE hostmask LIKE ?');
      $sth->bind_param(1, "\%$host");
      $sth->execute();
      $rows = $sth->fetchall_arrayref({});

      foreach my $row (@$rows) {
        next if exists $ids{$row->{id}};
        $ids{$row->{id}} = $row->{id};

        $sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE id == ?');
        $sth->bind_param(1, $row->{id});
        $sth->execute();
        my $rows = $sth->fetchall_arrayref({});

        foreach my $nrow (@$rows) {
          next if exists $akas{$nrow->{hostmask}};
          $akas{$nrow->{hostmask}} = { hostmask => $nrow->{hostmask}, id => $row->{id} };
          $self->{pbot}->{logger}->log("Adding matching host [$hostmask] and id [$row->{id}] AKA hostmask $nrow->{hostmask}\n");
        }
      }
    }

    my %nickservs;
    foreach my $id (keys %ids) {
      $sth = $self->{dbh}->prepare('SELECT nickserv FROM Nickserv WHERE id == ?');
      $sth->bind_param(1, $id);
      $sth->execute();
      $rows = $sth->fetchall_arrayref({});

      foreach my $row (@$rows) {
        $nickservs{$row->{nickserv}} = $id;
      }
    }

    foreach my $nickserv (sort keys %nickservs) {
      foreach my $aka (keys %akas) {
        if ($akas{$aka}->{id} == $nickservs{$nickserv}) {
          if (exists $akas{$aka}->{nickserv}) {
            $akas{$aka}->{nickserv} .= ",$nickserv";
          } else {
            $akas{$aka}->{nickserv} = $nickserv;
          }
        }
      }

      $sth = $self->{dbh}->prepare('SELECT id FROM Nickserv WHERE nickserv == ?');
      $sth->bind_param(1, $nickserv);
      $sth->execute();
      $rows = $sth->fetchall_arrayref({});

      foreach my $row (@$rows) {
        next if exists $ids{$row->{id}};
        $ids{$row->{id}} = $row->{id};

        $sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE id == ?');
        $sth->bind_param(1, $row->{id});
        $sth->execute();
        my $rows = $sth->fetchall_arrayref({});

        foreach my $nrow (@$rows) {
          if (exists $akas{$nrow->{hostmask}}) {
            if (exists $akas{$nrow->{hostmask}}->{nickserv}) {
              $akas{$nrow->{hostmask}}->{nickserv} .= ",$nickserv";
            } else {
              $akas{$nrow->{hostmask}}->{nickserv} = $nickserv;
            }
          } else {
            $akas{$nrow->{hostmask}} = { hostmask => $nrow->{hostmask}, id => $row->{id}, nickserv => $nickserv };
            $self->{pbot}->{logger}->log("Adding matching nickserv [$nickserv] and id [$row->{id}] AKA hostmask $nrow->{hostmask}\n");
          }
        }
      }
    }

    foreach my $id (keys %ids) {
      $sth = $self->{dbh}->prepare('SELECT hostmask FROM Hostmasks WHERE id == ?');
      $sth->bind_param(1, $id);
      $sth->execute();
      $rows = $sth->fetchall_arrayref({});

      foreach my $row (@$rows) {
        next if exists $akas{$row->{hostmask}};
        $akas{$row->{hostmask}} = { hostmask => $row->{hostmask}, id => $id };
        $self->{pbot}->{logger}->log("Adding matching id [$id] AKA hostmask $row->{hostmask}\n");
      }
    }

    return %akas;
  };

  $self->{pbot}->{logger}->log($@) if $@;
  return %akas;
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
    $sth->bind_param(1, $mask);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return $row->{id};
  };

  $self->{pbot}->{logger}->log($@) if $@;
  #$self->{pbot}->{logger}->log("get_message_account_id: returning id [". (defined $id ? $id: 'undef') . "] for mask [$mask]\n");
  return $id;
}

sub commit_message_history {
  my $self = shift;

  if($self->{new_entries} > 0) {
    # $self->{pbot}->{logger}->log("Commiting $self->{new_entries} messages to SQLite\n");
    eval {
      $self->{dbh}->commit();
    };

    $self->{pbot}->{logger}->log("SQLite error $@ when committing $self->{new_entries} entries.\n") if $@;

    $self->{dbh}->begin_work();
    $self->{new_entries} = 0;
  }
}

1;
