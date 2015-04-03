# File: Commands.pm
# Author: pragma_
#
# Purpose: Derives from Registerable class to provide functionality to
#          register subroutines, along with a command name and admin level.
#          Registered items will then be executed if their command name matches
#          a name provided via input.

package PBot::Commands;

use warnings;
use strict;

use base 'PBot::Registerable';

use Carp ();
use Text::ParseWords qw(shellwords);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Commands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->SUPER::initialize(%conf);

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
    Carp::croak("Missing pbot reference to PBot::Commands");
  }

  $self->{pbot} = $pbot;
  $self->{name} = undef;
  $self->{level} = undef;
}

sub register {
  my $self = shift;

  my ($subref, $name, $level) = @_;

  if((not defined $subref) || (not defined $name) || (not defined $level)) {
    Carp::croak("Missing parameters to Commands::register");
  }

  $name = lc $name;

  my $ref = $self->SUPER::register($subref);

  $ref->{name} = $name;
  $ref->{level} = $level;

  return $ref;
}

sub unregister_by_name {
  my ($self, $name) = @_;

  if(not defined $name) {
    Carp::croak("Missing name parameter to Commands::unregister");
  }

  $name = lc $name;

  @{ $self->{handlers} } = grep { $_->{name} ne $name } @{ $self->{handlers} };
}

sub exists {
  my $self = shift;
  my ($keyword) = @_;

  foreach my $ref (@{ $self->{handlers} }) {
    return 1 if $ref->{name} eq $keyword;
  }
  return 0;
}

sub interpreter {
  my $self = shift;
  my ($from, $nick, $user, $host, $depth, $keyword, $arguments, $tonick) = @_;
  my $result;

  my $pbot = $self->{pbot};

  my $admin = $pbot->{admins}->loggedin($from, "$nick!$user\@$host");

  my $level = defined $admin ? $admin->{level} : 0;

  foreach my $ref (@{ $self->{handlers} }) {
    if($ref->{name} eq $keyword) {
      if($level >= $ref->{level}) {
        return &{ $ref->{subref} }($from, $nick, $user, $host, $arguments);
      } else {
        if($level == 0) {
          return "/msg $nick You must login to use this command.";
        } else {
          return "/msg $nick You are not authorized to use this command.";
        }
      }
    }
  }

  return undef;
}

sub parse_arguments {
  my ($self, $arguments) = @_;
  return shellwords($arguments);
}

1;
