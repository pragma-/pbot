# File: BotAdminCommands.pm
# Author: pragma_
#
# Purpose: Administrative command subroutines.

package PBot::BotAdminCommands;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to BotAdminCommands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
    Carp::croak("Missing pbot reference to BotAdminCommands");
  }

  $self->{pbot} = $pbot;
  
  $pbot->commands->register(sub { return $self->login(@_)        },       "login",         0);
  $pbot->commands->register(sub { return $self->logout(@_)       },       "logout",        0);
  $pbot->commands->register(sub { return $self->join_channel(@_) },       "join",          45);
  $pbot->commands->register(sub { return $self->part_channel(@_) },       "part",          45);
  $pbot->commands->register(sub { return $self->ack_die(@_)      },       "die",           50);
  $pbot->commands->register(sub { return $self->add_admin(@_)    },       "addadmin",      60);
  $pbot->commands->register(sub { return $self->del_admin(@_)    },       "deladmin",      60);
}

sub login {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  if($self->{pbot}->admins->loggedin($from, "$nick!$user\@$host")) {
    return "/msg $nick You are already logged into channel $from.";
  }

  my $result = $self->{pbot}->admins->login($from, "$nick!$user\@$host", $arguments);
  return "/msg $nick $result";
}

sub logout {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  return "/msg $nick Uh, you aren't logged into channel $from." if(not $self->{pbot}->admins->loggedin($from, "$nick!$user\@$host"));
  $self->{pbot}->admins->logout($from, "$nick!$user\@$host");
  return "/msg $nick Good-bye, $nick.";
}

sub add_admin {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  my ($name, $channel, $hostmask, $level, $password) = split / /, $arguments, 5;

  if(not defined $name or not defined $channel or not defined $hostmask or not defined $level
    or not defined $password) {
    return "/msg $nick Usage: addadmin name channel hostmask level password";
  }

  $self->{pbot}->{admins}->add_admin($name, $channel, $hostmask, $level, $password);
  $self->{pbot}->{admins}->save_admins;
  return "Admin added.";
}

sub del_admin {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  my ($channel, $hostmask) = split / /, $arguments, 2;

  if(not defined $channel or not defined $hostmask) {
    return "/msg $nick Usage: deladmin channel hostmask";
  }

  if($self->{pbot}->{admins}->remove_admin($channel, $hostmask)) {
    return "Admin removed.";
  } else {
    return "No such admin found.";
  }
}

sub join_channel {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  # FIXME -- update %channels hash?
  $self->{pbot}->logger->log("$nick!$user\@$host made me join $arguments\n");
  $self->{pbot}->conn->join($arguments);
  return "/msg $nick Joining $arguments";
}

sub part_channel {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  # FIXME -- update %channels hash?
  $self->{pbot}->logger->log("$nick!$user\@$host made me part $arguments\n");
  $self->{pbot}->conn->part($arguments);
  return "/msg $nick Parting $arguments";
}

sub ack_die {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  $self->{pbot}->logger->log("$nick!$user\@$host made me exit.\n");
  $self->{pbot}->factoids->save_factoids();
  $self->{pbot}->ignorelist->save_ignores();
  $self->{pbot}->conn->privmsg($from, "Good-bye.") if defined $from;
  $self->{pbot}->conn->quit("Departure requested.");
  exit 0;
}

sub export {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "/msg $nick Usage: export <modules|factoids|admins>";
  }

  if($arguments =~ /^modules$/i) {
    return "/msg $nick Coming soon.";
  }

  if($arguments =~ /^quotegrabs$/i) {
    return PBot::Quotegrabs::export_quotegrabs(); 
  }

  if($arguments =~ /^factoids$/i) {
    return PBot::Factoids::export_factoids(); 
  }

  if($arguments =~ /^admins$/i) {
    return "/msg $nick Coming soon.";
  }
}

1;
