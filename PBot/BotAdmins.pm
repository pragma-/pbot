# File: BotAdmins.pm
# Author: pragma_
#
# Purpose: Manages list of bot admins and whether they are logged in.

package PBot::BotAdmins;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

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
  my ($name, $channel, $hostmask, $level, $password) = @_;

  $channel = lc $channel;
  $hostmask = lc $hostmask;

  ${ $self->admins }{$channel}{$hostmask}{name}     = $name;
  ${ $self->admins }{$channel}{$hostmask}{level}    = $level;
  ${ $self->admins }{$channel}{$hostmask}{password} = $password;

  $self->{pbot}->logger->log("Adding new level $level admin: [$name] [$hostmask] for channel [$channel]\n");
}

sub remove_admin {
  my $self = shift;
  my ($channel, $hostmask) = @_;

  my $admin = delete ${ $self->admins }{$channel}{$hostmask};
  if(defined $admin) {
    $self->{pbot}->logger->log("Removed level $admin->{level} admin [$admin->{name}] [$hostmask] from channel [$channel]\n");
    $self->save_admins;
    return 1;
  } else {
    $self->{pbot}->logger->log("Attempt to remove non-existent admin [$hostmask] from channel [$channel]\n");
    return 0;
  }
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

    my ($name, $channel, $hostmask, $level, $password) = split(/\s+/, $line, 5);
    
    if(not defined $name || not defined $channel || not defined $hostmask || not defined $level || not defined $password) {
         Carp::croak "Syntax error around line $i of $filename\n";
    }

    $self->add_admin($name, $channel, $hostmask, $level, $password);
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

  open(FILE, "> $filename") or Carp::croak "Couldn't open $filename: $!\n";

  foreach my $channel (sort keys %{ $self->{admins} }) {
    foreach my $hostmask (sort keys %{ $self->{admins}->{$channel} }) {
      my $admin = $self->{admins}->{$channel}{$hostmask};
      next if $admin->{name} eq $self->{pbot}->botnick;
      print FILE "$admin->{name} $channel $hostmask $admin->{level} $admin->{password}\n"; 
    }
  }
  close(FILE);
}

sub export_admins {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->export_path; }

  return if not defined $filename;
  return;
}

sub find_admin {
  my ($self, $from, $hostmask) = @_;

  $from = $self->{pbot}->botnick if not defined $from;
  $hostmask = '.*' if not defined $hostmask;

  my $result = eval {
    foreach my $channel_regex (keys %{ $self->{admins} }) {
      if($from !~ m/^#/) {
        # if not from a channel, make sure that nick portion of hostmask matches $from
        foreach my $hostmask_regex (keys %{ $self->{admins}->{$channel_regex} }) {
          my $nick;

          if($hostmask_regex =~ m/^([^!]+)!.*/) {
            $nick = $1;
          } else {
            $nick = $hostmask_regex;
          }

          return $self->{admins}{$channel_regex}{$hostmask_regex} if($from =~ m/$nick/i and $hostmask =~ m/$hostmask_regex/i);
        }
      } elsif($from =~ m/$channel_regex/i) {
        foreach my $hostmask_regex (keys %{ $self->{admins}->{$channel_regex} }) {
          return $self->{admins}{$channel_regex}{$hostmask_regex} if $hostmask =~ m/$hostmask_regex/i;
        }
      }
    }
    return undef;
  };

  if($@) {
    $self->{pbot}->logger->log("Error in find_admin parameters: $@\n");
  }

  return $result;
}

sub loggedin {
  my ($self, $channel, $hostmask) = @_;

  my $admin = $self->find_admin($channel, $hostmask);

  if(defined $admin && exists $admin->{loggedin}) {
    return $admin;
  } else {
    return undef;
  }
}

sub login {
  my ($self, $channel, $hostmask, $password) = @_;

  my $admin = $self->find_admin($channel, $hostmask);

  if(not defined $admin) {
    $self->{pbot}->logger->log("Attempt to login non-existent [$channel][$hostmask] failed\n");
    return "You do not have an account in $channel.";
  }

  if($admin->{password} ne $password) {
    $self->{pbot}->logger->log("Bad login password for [$channel][$hostmask]\n");
    return "I don't think so.";
  }

  $admin->{loggedin} = 1;

  $self->{pbot}->logger->log("$hostmask logged into $channel\n");

  return "Logged into $channel.";
}

sub logout {
  my ($self, $channel, $hostmask) = @_;

  my $admin = $self->find_admin($channel, $hostmask);

  delete $admin->{loggedin} if defined $admin;
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

1;
