# File: Commands.pm
# Author: pragma_
#
# Purpose: Derives from Registerable class to provide functionality to
#          register subroutines, along with a command name and admin level.
#          Registered items will then be executed if their command name matches
#          a name provided via input.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Commands;

use warnings;
use strict;

use feature 'unicode_strings';

use base 'PBot::Registerable';

use Time::Duration qw/duration/;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->SUPER::initialize(%conf);
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{metadata} = PBot::HashObject->new(pbot => $self->{pbot}, name => 'Commands', filename => $conf{filename});
  $self->load_metadata;

  $self->register(sub { $self->cmdset(@_)   },  "cmdset",   90);
  $self->register(sub { $self->cmdunset(@_) },  "cmdunset", 90);
  $self->register(sub { $self->help(@_)     },  "help",      0);
  $self->register(sub { $self->uptime(@_)   },  "uptime",    0);
}

sub register {
  my ($self, $subref, $name, $level) = @_;

  if (not defined $subref or not defined $name or not defined $level) {
    Carp::croak("Missing parameters to Commands::register");
  }

  my $ref = $self->SUPER::register($subref);
  $ref->{name} = lc $name;
  $ref->{level} = $level;

  if (not $self->{metadata}->exists($name)) {
    $self->{metadata}->add($name, { level => $level, help => '' }, 1);
  } else {
    if (not defined $self->get_meta($name, 'level')) {
      $self->{metadata}->set($name, 'level', $level, 1);
    }
  }

  return $ref;
}

sub unregister {
  my ($self, $name) = @_;
  Carp::croak("Missing name parameter to Commands::unregister") if not defined $name;
  $name = lc $name;
  @{ $self->{handlers} } = grep { $_->{name} ne $name } @{ $self->{handlers} };
}

sub exists {
  my ($self, $keyword) = @_;
  $keyword = lc $keyword;
  foreach my $ref (@{ $self->{handlers} }) {
    return 1 if $ref->{name} eq $keyword;
  }
  return 0;
}

sub interpreter {
  my ($self, $stuff) = @_;
  my $result;

  if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
    use Data::Dumper;
    $Data::Dumper::Sortkeys  = 1;
    $self->{pbot}->{logger}->log("Commands::interpreter\n");
    $self->{pbot}->{logger}->log(Dumper $stuff);
  }

  my $from = exists $stuff->{admin_channel_override} ? $stuff->{admin_channel_override} : $stuff->{from};
  my ($admin_channel) = $stuff->{arguments} =~ m/\B(#[^ ]+)/; # assume first channel-like argument
  $admin_channel = $from if not defined $admin_channel;
  my $admin = $self->{pbot}->{admins}->loggedin($admin_channel, "$stuff->{nick}!$stuff->{user}\@$stuff->{host}");
  my $admin_level = defined $admin ? $admin->{level} : 0;
  my $keyword = lc $stuff->{keyword};

  if (exists $stuff->{'effective-level'}) {
    $self->{pbot}->{logger}->log("override level to $stuff->{'effective-level'}\n");
    $admin_level = $stuff->{'effective-level'};
  }

  foreach my $ref (@{ $self->{handlers} }) {
    if ($ref->{name} eq $keyword) {
      my $cmd_level = $self->get_meta($keyword, 'level') // $ref->{level};
      if ($admin_level >= $cmd_level) {
        $stuff->{no_nickoverride} = 1;
        my $result = &{ $ref->{subref} }($stuff->{from}, $stuff->{nick}, $stuff->{user}, $stuff->{host}, $stuff->{arguments}, $stuff);
        if ($stuff->{referenced}) {
          return undef if $result =~ m/(?:usage:|no results)/i;
        }
        return $result;
      } else {
        return undef if $stuff->{referenced};
        if ($admin_level == 0) {
          return "/msg $stuff->{nick} You must login to use this command.";
        } else {
          return "/msg $stuff->{nick} You are not authorized to use this command.";
        }
      }
    }
  }

  return undef;
}

sub get_meta {
  my ($self, $command, $key) = @_;
  $command = lc $command;
  return undef if not exists $self->{metadata}->{hash}->{$command};
  return $self->{metadata}->{hash}->{$command}->{$key};
}

sub load_metadata {
  my ($self) = @_;
  $self->{metadata}->load;
}

sub save_metadata {
  my ($self) = @_;
  $self->{metadata}->save;
}

sub cmdset {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($command, $key, $value) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);
  return "Usage: cmdset <command> [key [value]]" if not defined $command;
  return $self->{metadata}->set($command, $key, $value);
}

sub cmdunset {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($command, $key) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);
  return "Usage: cmdunset <command> <key>" if not defined $command or not defined $key;
  return $self->{metadata}->unset($command, $key);
}

sub help {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (not length $arguments) {
    return "For general help, see <https://github.com/pragma-/pbot/tree/master/doc>. For help about a specific command or factoid, use `help <keyword> [channel]`.";
  }

  my $keyword = lc $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});

  # check built-in commands first
  if ($self->exists($keyword)) {
    if (exists $self->{metadata}->{hash}->{$keyword}) {
      my $name = $self->{metadata}->{hash}->{$keyword}->{_name};
      my $level = $self->{metadata}->{hash}->{$keyword}->{level};
      my $help = $self->{metadata}->{hash}->{$keyword}->{help};
      my $result = "/say $name: ";

      if (defined $level and $level > 0) {
        $result .= "[Level $level admin command] ";
      }

      if (not defined $help or not length $help) {
        $result .= "I have no help for this command yet.";
      } else {
        $result .= $help;
      }
      return $result;
    }
    return "$keyword is a built-in command, but I have no help for it yet.";
  }

  # then factoids
  my $channel_arg = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
  $channel_arg = $from if not defined $channel_arg or not length $channel_arg;
  $channel_arg = '.*' if $channel_arg !~ m/^#/;

  my @factoids = $self->{pbot}->{factoids}->find_factoid($channel_arg, $keyword, exact_trigger => 1);

  if (not @factoids or not $factoids[0]) {
    return "I don't know anything about $keyword.";
  }

  my ($channel, $trigger);

  if (@factoids > 1) {
    if (not grep { $_->[0] eq $channel_arg } @factoids) {
      return "/say $keyword found in multiple channels: " . (join ', ', sort map { $_->[0] eq '.*' ? 'global' : $_->[0] } @factoids) . "; use `help $keyword <channel>` to disambiguate.";
    } else {
      foreach my $factoid (@factoids) {
        if ($factoid->[0] eq $channel_arg) {
          ($channel, $trigger) = ($factoid->[0], $factoid->[1]);
          last;
        }
      }
    }
  } else {
    ($channel, $trigger) = ($factoids[0]->[0], $factoids[0]->[1]);
  }

  my $channel_name = $self->{pbot}->{factoids}->{factoids}->{hash}->{$channel}->{_name};
  my $trigger_name = $self->{pbot}->{factoids}->{factoids}->{hash}->{$channel}->{$trigger}->{_name};
  $channel_name = 'global channel' if $channel_name eq '.*';
  $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

  my $result = "/say ";
  $result .= "[$channel_name] " if $channel ne $from and $channel ne '.*';
  $result .= "$trigger_name: ";

  my $help = $self->{pbot}->{factoids}->{factoids}->{hash}->{$channel}->{$trigger}->{help};

  if (not defined $help or not length $help) {
    return "/say $trigger_name is a factoid for $channel_name, but I have no help for it yet.";
  }

  $result .= $help;
  return $result;
}

sub uptime {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  return localtime ($self->{pbot}->{startup_timestamp}) . " [" . duration (time - $self->{pbot}->{startup_timestamp}) . "]";
}

1;
