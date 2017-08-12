# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Plugins::RemindMe;

use warnings;
use strict;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use Carp ();
use DBI;
use Time::Duration qw/duration/;
use Time::HiRes qw/gettimeofday/;
use Getopt::Long qw(GetOptionsFromString);
use PBot::Utils::ParseDate;

Getopt::Long::Configure ("bundling");

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

  $self->{pbot}->{commands}->register(sub { $self->remindme(@_) }, 'remindme', 0);

  $self->{filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/reminders.sqlite3';

  $self->{pbot}->{timer}->register(sub { $self->check_reminders(@_) }, 1, 'RemindMe');

  $self->dbi_begin;
  $self->create_database;
}

sub unload {
  my $self = shift;
  
  $self->dbi_end;

  $self->{pbot}->{commands}->unregister('remindme');
  $self->{pbot}->{timer}->unregister('RemindMe');
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
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", { RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1 }) or die $DBI::errstr;
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
  my ($self, $account, $target, $text, $alarm, $owner) = @_;

  eval {
    my $sth = $self->{dbh}->prepare('INSERT INTO Reminders (account, target, text, alarm, created_on, created_by) VALUES (?, ?, ?, ?, ?, ?)');
    $sth->execute($account, $target, $text, $alarm, scalar gettimeofday, $owner);
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Add reminder failed: $@");
    return 0;
  }

  return 1;
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

  return 1;
}

sub remindme {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  
  if (not $self->{dbh}) {
    return "Internal error.";
  }

  my $usage = "Usage: remindme [-c channel] <message> <-t time>";

  return $usage if not length $arguments;

  my ($target, $text, $alarm);

  my $getopt_error;
  local $SIG{__WARN__} = sub {
    $getopt_error = shift;
    chomp $getopt_error;
  };

  my ($ret, $args) = GetOptionsFromString($arguments,
    't=s' => \$alarm,
    'c=s' => \$target,
    'm=s' => \$text);

  return "$getopt_error -- $usage" if defined $getopt_error;

  $text = join ' ', @$args if not defined $text;

  return "Please specify a point in time for this reminder." if not defined $alarm;
  return "Please specify a reminder message." if not length $text;

  if (defined $target) {
    my $admininfo = $self->{pbot}->{admins}->loggedin($target, "$nick!$user\@$host");
    return "Only admins can create channel reminders." if not defined $admininfo;
  }

  my ($length, $error) = parsedate($alarm);
  return $error if $error;

  $alarm = gettimeofday + $length;

  my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);

  if ($self->add_reminder($account, $target, $text, $alarm, "$nick!$user\@$host")) {
    return "Reminder added.";
  } else {
    return "Failed to add reminder.";
  }
}

sub check_reminders {
  my $self = shift;

  return if not $self->{dbh};

  my $reminders = eval {
    my $sth = $self->{dbh}->prepare('SELECT * FROM Reminders WHERE alarm <= ?');
    $sth->execute(scalar gettimeofday);
    return $sth->fetchall_arrayref({});
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Check reminders failed: $@");
    return;
  }

  foreach my $reminder (@$reminders) {
    my $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($reminder->{account});
    my ($nick) = $hostmask =~ /^([^!]+)!/;

    next if not $self->{pbot}->{nicklist}->is_present_any_channel($nick);

    use Data::Dumper;
    print Dumper $reminder;
    print "nick: $nick\n";

    if (defined $reminder->{target}) {
      $self->{pbot}->{conn}->privmsg($reminder->{target}, "Reminder: " . $reminder->{text}); 
    } else {
      $self->{pbot}->{conn}->privmsg($nick, "Reminder: " . $reminder->{text}); 
    }

    $self->delete_reminder($reminder->{id});
  }
}

1;
