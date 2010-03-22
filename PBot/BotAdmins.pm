# File: BotAdmins.pm
# Authoer: pragma_
#
# Purpose: Manages list of bot admins and whether they are logged in.

package PBot::BotAdmins;

use warnings;
use strict;

BEGIN {
  use vars qw($VERSION);
  $VERSION = $PBot::PBot::VERSION;
}

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to BotAdmins should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $filename = delete $conf{filename};
  my $export_path = delete $conf{export_path};
  my $export_site = delete $conf{export_site};

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
    Carp::croak("Missing pbot reference to BotAdmins");
  }

  my $export_timeout = delete $conf{export_timeout};
  if(not defined $export_timeout) {
    if(defined $export_path) {
      $export_timeout = 300; # every 5 minutes
    } else {
      $export_timeout = -1;
    }
  }

  $self->{admins} = {};
  $self->{filename} = $filename;
  $self->{export_path} = $export_path;
  $self->{export_site} = $export_site;
  $self->{export_timeout} = $export_timeout;

  $self->{pbot} = $pbot;
}

sub add_admin {
  my $self = shift;
  my ($channel, $hostmask, $level, $password) = @_;

  $channel = lc $channel;
  $hostmask = lc $hostmask;

  $channel =~ s/\*/.*/g;
  $hostmask =~ s/\*/.*/g;

  ${ $self->admins}{$channel}{$hostmask}{level}    = $level;
  ${ $self->admins}{$channel}{$hostmask}{password} = $password;

  $self->{pbot}->logger->log("Adding new level $level admin: [$hostmask]\n");
}

sub remove_admin {
  my $self = shift;
  my ($channel, $hostmask) = @_;

  delete ${ $self->admins }{$channel}{$hostmask};
}

sub load_admins {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->filename; }

  if(not defined $filename) {
    Carp::carp "No admins path specified -- skipping loading of admins";
    return;
  }

  $self->{pbot}->logger->log("Loading admins from $filename ...\n");
  
  open(FILE, "< $filename") or Carp::croak "Couldn't open $filename: $!\n";
  my @contents = <FILE>;
  close(FILE);

  my $i = 0;

  foreach my $line (@contents) {
    chomp $line;
    $i++;

    my ($channel, $hostmask, $level, $password) = split(/\s+/, $line, 4);
    
    if(not defined $channel || not defined $hostmask || not defined $level || not defined $password) {
         Carp::croak "Syntax error around line $i of $filename\n";
    }

    $self->add_admin($channel, $hostmask, $level, $password);
  }

  $self->{pbot}->logger->log("  $i admins loaded.\n");
  $self->{pbot}->logger->log("Done.\n");
}

sub save_admins {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->filename; }

  if(not defined $filename) {
    Carp::carp "No admins path specified -- skipping saving of admins\n";
    return;
  }
}

sub export_admins {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->export_path; }

  return if not defined $filename;
  return;
}

sub interpreter {
  my $self = shift;
  my ($from, $nick, $user, $host, $count, $keyword, $arguments, $tonick) = @_;
  my $result;

  my $pbot = $self->{pbot};
  return undef;  
}

sub export_path {
  my $self = shift;

  if(@_) { $self->{export_path} = shift; }
  return $self->{export_path};
}

sub export_timeout {
  my $self = shift;

  if(@_) { $self->{export_timeout} = shift; }
  return $self->{export_timeout};
}

sub logger {
  my $self = shift;
  if(@_) { $self->{logger} = shift; }
  return $self->{logger};
}

sub export_site {
  my $self = shift;
  if(@_) { $self->{export_site} = shift; }
  return $self->{export_site};
}

sub admins {
  my $self = shift;
  return $self->{admins};
}

sub filename {
  my $self = shift;

  if(@_) { $self->{filename} = shift; }
  return $self->{filename};
}

sub loggedin {
  my ($self, $channel, $hostmask) = @_;

  $channel = '*' if not defined $channel;

  $channel =~ s/\*/.*/g;
  $hostmask =~ s/\*/.*/g;

  if(exists ${ $self->{admins} }{$channel}{$hostmask}{loggedin}) {
    return { hostmask => $hostmask, level => ${ $self->{admins} }{$channel}{$hostmask}{level} };
  } else {
    return undef;
  }
}

sub login {
  my ($self, $channel, $hostmask, $password) = @_;

  $channel = '*' if not defined $channel;

  $channel =~ s/\*/.*/g;
  $hostmask =~ s/\*/.*/g;

  if((not exists ${ $self->{admins}}{$channel}) && (not exists ${ $self->{admins}}{$channel}{$hostmask})) {
    $self->{pbot}->logger->log("Attempt to login non-existent [$channel][$hostmask] failed\n");
    return "You do not have an account.";
  }

  if(${ $self->{admins} }{$channel}{$hostmask}{password} ne $password) {
    $self->{pbot}->logger->log("Bad login password for [$channel][$hostmask]\n");
    return "I don't think so.";
  }

  ${ $self->{admins}}{$channel}{$hostmask}{loggedin} = 1;

  $self->{pbot}->logger->log("$hostmask logged-in in $channel\n");

  return "Logged in.";
}

sub logout {
  my ($self, $channel, $hostmask) = @_;

  $channel = '*' if not defined $channel;

  $channel =~ s/\*/.*/g;
  $hostmask =~ s/\*/.*/g;

  delete ${ $self->{admins} }{$channel}{$hostmask}{loggedin};
}

1;
