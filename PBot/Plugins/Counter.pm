
package PBot::Plugins::Counter;

use warnings;
use strict;

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

  $self->{pbot}->{commands}->register(sub { $self->counteradd(@_)   }, 'counteradd',   0);
  $self->{pbot}->{commands}->register(sub { $self->counterdel(@_)   }, 'counterdel',   0);
  $self->{pbot}->{commands}->register(sub { $self->counterreset(@_) }, 'counterreset', 0);
  $self->{pbot}->{commands}->register(sub { $self->countershow(@_)  }, 'countershow',  0);
  $self->{pbot}->{commands}->register(sub { $self->counterlist(@_)  }, 'counterlist',  0);

  $self->{filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/counters.sqlite3';

  $self->create_database;
}

sub unload {
  my $self = shift;
  
  $self->{pbot}->{commands}->unregister('counteradd');
  $self->{pbot}->{commands}->unregister('counterdel');
  $self->{pbot}->{commands}->unregister('counterreset');
  $self->{pbot}->{commands}->unregister('countershow');
  $self->{pbot}->{commands}->unregister('counterlist');
}

sub create_database {
  my $self = shift;

  eval {
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", { RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1 }) or die $DBI::errstr;

    $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Counters (
  channel     TEXT,
  name        TEXT,
  description TEXT,
  timestamp   NUMERIC
)
SQL

    $self->{dbh}->disconnect;
  };

  $self->{pbot}->{logger}->log("Counter create database failed: $@") if $@;
}

sub dbi_begin {
  my ($self) = @_;
  eval {
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", { RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1 }) or die $DBI::errstr;
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Error opening Counters database: $@");
    return 0;
  } else {
    return 1;
  }
}

sub dbi_end {
  my ($self) = @_;
  $self->{dbh}->disconnect;
}

sub add_counter {
  my ($self, $channel, $name, $description) = @_;

  my ($desc, $timestamp) = $self->get_counter($channel, $name);
  if (defined $desc) {
    return 0;
  }

  my $sth = $self->{dbh}->prepare('INSERT INTO Counters (channel, name, description, timestamp) VALUES (?, ?, ?, ?)');
  $sth->bind_param(1, lc $channel);
  $sth->bind_param(2, lc $name);
  $sth->bind_param(3, $description);
  $sth->bind_param(4, scalar gettimeofday);
  $sth->execute();

  return 1;
}

sub reset_counter {
  my ($self, $channel, $name) = @_;

  my ($description, $timestamp) = $self->get_counter($channel, $name);
  if (not defined $description) {
    return (undef, undef);
  }

  my $sth = $self->{dbh}->prepare('UPDATE Counters SET timestamp = ? WHERE channel = ? AND name = ?');
  $sth->bind_param(1, scalar gettimeofday);
  $sth->bind_param(2, lc $channel);
  $sth->bind_param(3, lc $name);
  $sth->execute();

  return ($description, $timestamp);
}

sub delete_counter {
  my ($self, $channel, $name) = @_;

  my ($description, $timestamp) = $self->get_counter($channel, $name);
  if (not defined $description) {
    return 0;
  }

  my $sth = $self->{dbh}->prepare('DELETE FROM Counters WHERE channel = ? AND name = ?');
  $sth->bind_param(1, lc $channel);
  $sth->bind_param(2, lc $name);
  $sth->execute();

  return 1;
}

sub list_counters {
  my ($self, $channel) = @_;

  my $counters = eval {
    my $sth = $self->{dbh}->prepare('SELECT name FROM Counters WHERE channel = ?');
    $sth->bind_param(1, lc $channel);
    $sth->execute();
    return $sth->fetchall_arrayref();
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Get counter failed: $@");
  }

  return map { $_->[0] } @$counters;
}

sub get_counter {
  my ($self, $channel, $name) = @_;

  my ($description, $time) = eval {
    my $sth = $self->{dbh}->prepare('SELECT description, timestamp FROM Counters WHERE channel = ? AND name = ?');
    $sth->bind_param(1, lc $channel);
    $sth->bind_param(2, lc $name);
    $sth->execute();
    my $row = $sth->fetchrow_hashref();
    return ($row->{description}, $row->{timestamp});
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Get counter failed: $@");
    return undef;
  }

  return ($description, $time);
}

sub counteradd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  
  if (not $self->dbi_begin) {
    return "Internal error.";
  }

  my ($channel, $name, $description);

  if ($from !~ m/^#/) {
    ($channel, $name, $description) = split /\s+/, $arguments, 3;
    if (not defined $channel or not defined $name or not defined $description or $channel !~ m/^#/) {
      return "Usage from private message: counteradd <channel> <name> <description>";
    }
  } else {
    $channel = $from;
    ($name, $description) = split /\s+/, $arguments, 2;
    if (not defined $name or not defined $description) {
      return "Usage: counteradd <name> <description>";
    }
  }

  my $result;
  if ($self->add_counter($channel, $name, $description)) {
    $result = "Counter added.";
  } else {
    $result = "Counter '$name' already exists.";
  }

  $self->dbi_end;
  return $result;
}

sub counterdel {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if (not $self->dbi_begin) {
    return "Internal error.";
  }

  my ($channel, $name);

  if ($from !~ m/^#/) {
    ($channel, $name) = split /\s+/, $arguments, 2;
    if (not defined $channel or not defined $name or $channel !~ m/^#/) {
      return "Usage from private message: counterdel <channel> <name>";
    }
  } else {
    $channel = $from;
    ($name) = split /\s+/, $arguments, 1;
    if (not defined $name) {
      return "Usage: counterdel <name>";
    }
  }

  my $result;
  if ($self->delete_counter($channel, $name)) {
    $result = "Counter removed.";
  } else {
    $result = "No such counter.";
  }

  $self->dbi_end;
  return $result;
}

sub counterreset {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if (not $self->dbi_begin) {
    return "Internal error.";
  }

  my ($channel, $name);

  if ($from !~ m/^#/) {
    ($channel, $name) = split /\s+/, $arguments, 2;
    if (not defined $channel or not defined $name or $channel !~ m/^#/) {
      return "Usage from private message: counterreset <channel> <name>";
    }
  } else {
    $channel = $from;
    ($name) = split /\s+/, $arguments, 1;
    if (not defined $name) {
      return "Usage: counterreset <name>";
    }
  }

  my $result;
  my ($description, $timestamp) = $self->reset_counter($channel, $name);
  if (defined $description) {
    my $ago = duration gettimeofday - $timestamp;
    $result = "It had been $ago since $description.";
  } else {
    $result = "No such counter.";
  }

  $self->dbi_end;
  return $result;
}

sub countershow {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if (not $self->dbi_begin) {
    return "Internal error.";
  }

  my ($channel, $name);

  if ($from !~ m/^#/) {
    ($channel, $name) = split /\s+/, $arguments, 2;
    if (not defined $channel or not defined $name or $channel !~ m/^#/) {
      return "Usage from private message: countershow <channel> <name>";
    }
  } else {
    $channel = $from;
    ($name) = split /\s+/, $arguments, 1;
    if (not defined $name) {
      return "Usage: countershow <name>";
    }
  }

  my $result;
  my ($description, $timestamp) = $self->get_counter($channel, $name);
  if (defined $description) {
    my $ago = duration gettimeofday - $timestamp;
    $result = "It has been $ago since $description.";
  } else {
    $result = "No such counter.";
  }

  $self->dbi_end;
  return $result;
}

sub counterlist {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if (not $self->dbi_begin) {
    return "Internal error.";
  }

  my $channel;

  if ($from !~ m/^#/) {
    if (not length $arguments or $arguments !~ m/^#/) {
      return "Usage from private message: counterlist <channel>";
    }
    $channel = $arguments;
  } else {
    $channel = $from;
  }

  my @counters = $self->list_counters($channel);

  my $result;
  if (not @counters) {
    $result = "No counters available for $channel.";
  } else {
    my $comma = '';
    $result = "Counters for $channel: ";
    foreach my $counter (sort @counters) {
      $result .= "$comma$counter";
      $comma = ', ';
    }
  }

  $self->dbi_end;
  return $result;
}

1;
