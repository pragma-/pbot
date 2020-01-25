# File: Users.pm
# Author: pragma_
#
# Purpose: Manages list of bot users/admins and their metadata.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Users;

use warnings;
use strict;

use feature 'unicode_strings';

use PBot::DualIndexHashObject;
use Carp ();

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot}     = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{users}   = PBot::DualIndexHashObject->new(name => 'Users', filename => $conf{filename}, pbot => $conf{pbot});
  $self->load;

  $self->{pbot}->{commands}->register(sub { return $self->logincmd(@_)   },  "login",       0);
  $self->{pbot}->{commands}->register(sub { return $self->logoutcmd(@_)  },  "logout",      0);
  $self->{pbot}->{commands}->register(sub { return $self->useradd(@_)    },  "useradd",    60);
  $self->{pbot}->{commands}->register(sub { return $self->userdel(@_)    },  "userdel",    60);
  $self->{pbot}->{commands}->register(sub { return $self->userset(@_)    },  "userset",    60);
  $self->{pbot}->{commands}->register(sub { return $self->userunset(@_)  },  "userunset",  60);
  $self->{pbot}->{commands}->register(sub { return $self->mycmd(@_)      },  "my",          0);

  $self->{pbot}->{event_dispatcher}->register_handler('irc.join',  sub { $self->on_join(@_) });
}

sub on_join {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);
  ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

  my $u = $self->find_user($channel, "$nick!$user\@$host");

  if (defined $u) {
    if ($self->{pbot}->{chanops}->can_gain_ops($channel)) {
      my $modes = '+';
      my $targets = '';

      if ($u->{autoop}) {
        $self->{pbot}->{logger}->log("$nick!$user\@$host autoop in $channel\n");
        $modes .= 'o';
        $targets .= "$nick ";
      }

      if ($u->{autovoice}) {
        $self->{pbot}->{logger}->log("$nick!$user\@$host autovoice in $channel\n");
        $modes .= 'v';
        $targets .= "$nick ";
      }

      if (length $modes > 1) {
        $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $modes $targets");
        $self->{pbot}->{chanops}->gain_ops($channel);
      }
    }

    if ($u->{autologin}) {
      $self->{pbot}->{logger}->log("$nick!$user\@$host autologin to $user->{name} ($user->{level}) for $channel\n");
      $user->{loggedin} = 1;
    }
  }
  return 0;
}

sub add_user {
  my ($self, $name, $channel, $hostmask, $level, $password, $dont_save) = @_;
  $channel = '.*' if $channel !~ m/^#/;

  $level //= 0;
  $password //= $self->{pbot}->random_nick(16);

  my $data = {
    name => $name,
    level => $level,
    password => $password
  };

  $self->{pbot}->{logger}->log("Adding new user (level $level): name: $name hostmask: $hostmask channel: $channel\n");
  $self->{users}->add($channel, $hostmask, $data, $dont_save);
  return $data;
}

sub remove_user {
  my ($self, $channel, $hostmask) = @_;
  return $self->{users}->remove($channel, $hostmask);
}

sub load {
  my $self = shift;
  my $filename;

  if (@_) { $filename = shift; } else { $filename = $self->{users}->{filename}; }

  if (not defined $filename) {
    Carp::carp "No users path specified -- skipping loading of users";
    return;
  }

  $self->{users}->load;

  my $i = 0;
  foreach my $channel (sort keys %{ $self->{users}->{hash} } ) {
    foreach my $hostmask (sort keys %{ $self->{users}->{hash}->{$channel} }) {
      next if $hostmask eq '_name';
      $i++;
      my $name = $self->{users}->{hash}->{$channel}->{$hostmask}->{name};
      my $level = $self->{users}->{hash}->{$channel}->{$hostmask}->{level};
      my $password = $self->{users}->{hash}->{$channel}->{$hostmask}->{password};

      if (not defined $name or not defined $level or not defined $password) {
        Carp::croak "A user in $filename is missing critical data\n";
      }
    }
  }

  $self->{pbot}->{logger}->log("  $i users loaded.\n");
}

sub save {
  my ($self) = @_;
  $self->{users}->save;
}

sub find_user_account {
  my ($self, $channel, $hostmask) = @_;

  $channel = lc $channel;
  $hostmask = lc $hostmask;
  $channel = '.*' if $channel !~ /^#/;
  my ($found_channel, $found_hostmask) = ($channel, $hostmask);

  foreach my $chan (keys %{ $self->{users}->{hash} }) {
    if ($channel !~ m/^#/ or $channel =~ m/^$chan$/i) {
      if (not exists $self->{users}->{hash}->{$chan}->{$hostmask}) {
        my $last_level = 0;
        # find hostmask by account name or wildcard
        foreach my $mask (keys %{ $self->{users}->{hash}->{$chan} }) {
          next if $mask eq '_name';
          if (lc $self->{users}->{hash}->{$chan}->{$mask}->{name} eq $hostmask) {
            if ($last_level <= $self->{users}->{hash}->{$chan}->{$mask}->{level}) {
              $found_hostmask = $mask;
              $found_channel = $chan;
              $last_level = $self->{users}->{hash}->{$chan}->{$mask}->{level};
            }
          }

          if ($mask =~ /[*?]/) {
            # contains * or ? so it's converted to a regex
            my $mask_quoted = quotemeta $mask;
            $mask_quoted =~ s/\\\*/.*?/g;
            $mask_quoted =~ s/\\\?/./g;
            if ($hostmask =~ m/^$mask_quoted$/i) {
              if ($last_level <= $self->{users}->{hash}->{$chan}->{$mask}->{level}) {
                $found_hostmask = $mask;
                $found_channel = $chan;
                $last_level = $self->{users}->{hash}->{$chan}->{$mask}->{level};
              }
            }
          }
        }
      }
    }
  }
  return ($found_channel, $found_hostmask);
}

sub find_admin {
  my ($self, $channel, $hostmask, $min_level) = @_;
  $min_level //= 1;

  ($channel, $hostmask) = $self->find_user_account($channel, $hostmask);

  $channel = $self->{pbot}->{registry}->get_value('irc', 'botnick') if not defined $channel;
  $hostmask = '.*' if not defined $hostmask;
  $hostmask = lc $hostmask;

  my $result = eval {
    my $admin;
    foreach my $channel_regex (keys %{ $self->{users}->{hash} }) {
      if ($channel !~ m/^#/ or $channel =~ m/^$channel_regex$/i) {
        foreach my $hostmask_regex (keys %{ $self->{users}->{hash}->{$channel_regex} }) {
          next if $hostmask_regex eq '_name';
          if ($hostmask_regex =~ m/[*?]/) {
            # contains * or ? so it's converted to a regex
            my $hostmask_quoted = quotemeta $hostmask_regex;
            $hostmask_quoted =~ s/\\\*/.*?/g;
            $hostmask_quoted =~ s/\\\?/./g;
            if ($hostmask =~ m/^$hostmask_quoted$/i) {
              my $temp = $self->{users}->{hash}->{$channel_regex}->{$hostmask_regex};
              $admin = $temp if $temp->{level} >= $min_level and (not defined $admin or $admin->{level} <= $temp->{level});
            }
          } else {
            # direct comparison
            if ($hostmask eq lc $hostmask_regex) {
              my $temp = $self->{users}->{hash}->{$channel_regex}->{$hostmask_regex};
              $admin = $temp if $temp->{level} >= $min_level and (not defined $admin or $admin->{level} <= $temp->{level});
            }
          }
        }
      }
    }
    return $admin;
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Error in find_admin parameters: $@\n");
  }

  return $result;
}

sub find_user {
  my ($self, $from, $hostmask) = @_;
  return $self->find_admin($from, $hostmask, 0);
}

sub loggedin {
  my ($self, $channel, $hostmask) = @_;
  my $user = $self->find_user($channel, $hostmask);

  if (defined $user and $user->{loggedin}) {
    return $user;
  }
  return undef;
}

sub loggedin_admin {
  my ($self, $channel, $hostmask) = @_;
  my $user = $self->loggedin($channel, $hostmask);

  if (defined $user and $user->{level} > 0) {
    return $user;
  }
  return undef;
}

sub login {
  my ($self, $channel, $hostmask, $password) = @_;
  my $user = $self->find_user($channel, $hostmask);

  if (not defined $user) {
    $self->{pbot}->{logger}->log("Attempt to login non-existent [$channel][$hostmask] failed\n");
    return "You do not have an account in $channel.";
  }

  if (defined $password and $user->{password} ne $password) {
    $self->{pbot}->{logger}->log("Bad login password for [$channel][$hostmask]\n");
    return "I don't think so.";
  }

  $user->{loggedin} = 1;
  $self->{pbot}->{logger}->log("$hostmask logged into $channel\n");
  return "Logged into $channel.";
}

sub logout {
  my ($self, $channel, $hostmask) = @_;
  my $user = $self->find_user($channel, $hostmask);
  delete $user->{loggedin} if defined $user;
}

sub get_loggedin_user_metadata {
  my ($self, $channel, $hostmask, $key) = @_;
  my $user = $self->loggedin($channel, $hostmask);
  if ($user) {
    return $user->{lc $key};
  }
  return undef;
}

sub logincmd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $channel = $from;

  if (not $arguments) {
    return "Usage: login [channel] password";
  }

  if ($arguments =~ m/^([^ ]+)\s+(.+)/) {
    $channel = $1;
    $arguments = $2;
  }

  if ($self->loggedin($channel, "$nick!$user\@$host")) {
    return "/msg $nick You are already logged into channel $channel.";
  }

  my $result = $self->login($channel, "$nick!$user\@$host", $arguments);
  return "/msg $nick $result";
}

sub logoutcmd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  return "/msg $nick Uh, you aren't logged into channel $from." if (not $self->loggedin($from, "$nick!$user\@$host"));
  $self->logout($from, "$nick!$user\@$host");
  return "/msg $nick Good-bye, $nick.";
}

sub useradd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my ($name, $channel, $hostmask, $level, $password) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 5);
  $level //= 0;

  if (not defined $name or not defined $channel or not defined $hostmask) {
    return "/msg $nick Usage: useradd <account name> <channel> <hostmask> [level] [password]";
  }

  $channel = '.*' if $channel !~ /^#/;

  my $admin  = $self->{pbot}->{users}->find_admin($channel, "$nick!$user\@$host");

  if (not $admin) {
    $channel = 'global' if $channel eq '.*';
    return "You are not an admin for $channel; cannot add users to that channel.\n";
  }

  # don't allow non-bot-owners to add admins that can also add admins
  if ($admin->{level} < 90 and $level > 40) {
    return "You may not set admin level higher than 40.\n";
  }

  $self->{pbot}->{users}->add_user($name, $channel, $hostmask, $level, $password);
  return not $level ? "User added." : "Admin added.";
}

sub userdel {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my ($channel, $hostmask) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $channel or not defined $hostmask) {
    return "/msg $nick Usage: userdel <channel> <hostmask or account name>";
  }

  ($channel, $hostmask) = $self->find_user_account($channel, $hostmask);
  return $self->remove_user($channel, $hostmask);
}

sub userset {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($channel, $hostmask, $key, $value) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 4);

  if (not defined $channel or not defined $hostmask) {
    return "Usage: userset <channel> <hostmask or account name> [key] [value]";
  }

  my $admin  = $self->find_admin($channel, "$nick!$user\@$host");
  my $target = $self->find_user($channel, $hostmask);

  if (not $admin) {
    $channel = 'global' if $channel eq '.*';
    return "You are not an admin for $channel; cannot modify their users.";
  }

  if (not $target) {
    $channel = 'global' if $channel eq '.*';
    return "There is no user $hostmask in channel $channel.";
  }

  # don't allow non-bot-owners to add admins that can also add admins
  if (defined $key and $key eq 'level' and $admin->{level} < 90 and $value > 40) {
    return "You may not set user level higher than 40.\n";
  }

  if (defined $key and $target->{level} > $admin->{level}) {
    return "You may not modify users higher in level than you.";
  }

  ($channel, $hostmask) = $self->find_user_account($channel, $hostmask);
  my $result = $self->{users}->set($channel, $hostmask, $key, $value);
  $result =~ s/^password => .*;$/password => <private>;/m;
  return $result;
}

sub userunset {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($channel, $hostmask, $key) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  if (not defined $channel or not defined $hostmask) {
    return "Usage: userunset <channel> <hostmask or account name> <key>";
  }

  my $admin  = $self->find_admin($channel, "$nick!$user\@$host");
  my $target = $self->find_user($channel, $hostmask);

  if (not $admin) {
    $channel = 'global' if $channel eq '.*';
    return "You are not an admin for $channel; cannot modify their users.";
  }

  if (not $target) {
    $channel = 'global' if $channel eq '.*';
    return "There is no user $hostmask in channel $channel.";
  }

  if ($target->{level} > $admin->{level}) {
    return "You may not modify users higher in level than you.";
  }

  ($channel, $hostmask) = $self->find_user_account($channel, $hostmask);
  return $self->{users}->unset($channel, $hostmask, $key);
}

sub mycmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($key, $value) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $key) {
    return "Usage: my <key> [value]";
  }

  $key = lc $key;
  my $channel = $from;
  my $hostmask = "$nick!$user\@$host";

  my $u = $self->find_user($channel, $hostmask);

  if (not $u) {
    $channel = '.*';
    $hostmask = "$nick!*\@*";
    $u = $self->add_user("my_$nick", $channel, $hostmask);
    $u->{autologin} = 1;
    $u->{loggedin} = 1;
  }

  if (defined $value and $u->{level} == 0) {
    my @disallowed = qw/level autoop autovoice/;
    if (grep { $_ eq $key } @disallowed) {
      return "You must be an admin to set $key.";
    }
  }


  ($channel, $hostmask) = $self->find_user_account($channel, $hostmask);
  my $result = $self->{users}->set($channel, $hostmask, $key, $value);
  $result =~ s/^password => .*;$/password => <private>;/m;
  return $result;
}

1;
