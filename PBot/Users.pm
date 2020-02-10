# File: Users.pm
# Author: pragma_
#
# Purpose: Manages list of bot users/admins and their metadata.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Users;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

sub initialize {
  my ($self, %conf) = @_;
  $self->{users} = PBot::DualIndexHashObject->new(name => 'Users', filename => $conf{filename}, pbot => $conf{pbot});
  $self->load;

  $self->{pbot}->{commands}->register(sub { $self->logincmd(@_)   },  "login",      0);
  $self->{pbot}->{commands}->register(sub { $self->logoutcmd(@_)  },  "logout",     0);
  $self->{pbot}->{commands}->register(sub { $self->useradd(@_)    },  "useradd",    1);
  $self->{pbot}->{commands}->register(sub { $self->userdel(@_)    },  "userdel",    1);
  $self->{pbot}->{commands}->register(sub { $self->userset(@_)    },  "userset",    1);
  $self->{pbot}->{commands}->register(sub { $self->userunset(@_)  },  "userunset",  1);
  $self->{pbot}->{commands}->register(sub { $self->users(@_)  },      "users",      0);
  $self->{pbot}->{commands}->register(sub { $self->mycmd(@_)      },  "my",         0);

  $self->{pbot}->{capabilities}->add('admin', 'can-useradd',   1);
  $self->{pbot}->{capabilities}->add('admin', 'can-userdel',   1);
  $self->{pbot}->{capabilities}->add('admin', 'can-userset',   1);
  $self->{pbot}->{capabilities}->add('admin', 'can-userunset', 1);
  $self->{pbot}->{capabilities}->add('can-modify-admins', undef, 1);

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
      $self->{pbot}->{logger}->log("$nick!$user\@$host autologin to $u->{name} for $channel\n");
      $u->{loggedin} = 1;
    }
  }
  return 0;
}

sub add_user {
  my ($self, $name, $channel, $hostmask, $capabilities, $password, $dont_save) = @_;
  $channel = '.*' if $channel !~ m/^#/;

  $capabilities //= 'none';
  $password //= $self->{pbot}->random_nick(16);

  my $data = {
    name => $name,
    password => $password
  };

  foreach my $cap (split /\s*,\s*/, lc $capabilities) {
    next if $cap eq 'none';
    $data->{$cap} = 1;
  }

  $self->{pbot}->{logger}->log("Adding new user (caps: $capabilities): name: $name hostmask: $hostmask channel: $channel\n");
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
      my $password = $self->{users}->{hash}->{$channel}->{$hostmask}->{password};

      if (not defined $name or not defined $password) {
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

  my $sort;
  if ($channel =~ m/^#/) {
    $sort = sub { $a cmp $b };
  } else {
    $sort = sub { $b cmp $a };
  }

  foreach my $chan (sort $sort keys %{ $self->{users}->{hash} }) {
    if ($channel !~ m/^#/ or $channel =~ m/^$chan$/i) {
      if (not exists $self->{users}->{hash}->{$chan}->{$hostmask}) {
        # find hostmask by account name or wildcard
        foreach my $mask (keys %{ $self->{users}->{hash}->{$chan} }) {
          next if $mask eq '_name';
          if (lc $self->{users}->{hash}->{$chan}->{$mask}->{name} eq $hostmask) {
            return ($chan, $mask);
          }

          if ($mask =~ /[*?]/) {
            # contains * or ? so it's converted to a regex
            my $mask_quoted = quotemeta $mask;
            $mask_quoted =~ s/\\\*/.*?/g;
            $mask_quoted =~ s/\\\?/./g;
            if ($hostmask =~ m/^$mask_quoted$/i) {
              return ($chan, $mask);
            }
          }
        }
      } else {
        return ($chan, $hostmask);
      }
    }
  }
  return (undef, $hostmask);
}

sub find_user {
  my ($self, $channel, $hostmask) = @_;
  ($channel, $hostmask) = $self->find_user_account($channel, $hostmask);

  $channel = '.*' if not defined $channel;
  $hostmask = '.*' if not defined $hostmask;
  $hostmask = lc $hostmask;

  my $sort;
  if ($channel =~ m/^#/) {
    $sort = sub { $a cmp $b };
  } else {
    $sort = sub { $b cmp $a };
  }

  my $user = eval {
    foreach my $channel_regex (sort $sort keys %{ $self->{users}->{hash} }) {
      if ($channel !~ m/^#/ or $channel =~ m/^$channel_regex$/i) {
        foreach my $hostmask_regex (keys %{ $self->{users}->{hash}->{$channel_regex} }) {
          next if $hostmask_regex eq '_name';
          if ($hostmask_regex =~ m/[*?]/) {
            # contains * or ? so it's converted to a regex
            my $hostmask_quoted = quotemeta $hostmask_regex;
            $hostmask_quoted =~ s/\\\*/.*?/g;
            $hostmask_quoted =~ s/\\\?/./g;
            if ($hostmask =~ m/^$hostmask_quoted$/i) {
              return $self->{users}->{hash}->{$channel_regex}->{$hostmask_regex};
            }
          } else {
            # direct comparison
            if ($hostmask eq lc $hostmask_regex) {
              return $self->{users}->{hash}->{$channel_regex}->{$hostmask_regex};
            }
          }
        }
      }
    }
    return undef;
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Error in find_user parameters: $@\n");
  }
  return $user;
}

sub find_admin {
  my ($self, $from, $hostmask) = @_;
  my $user = $self->find_user($from, $hostmask);
  return undef if not defined $user;
  return undef if not $self->{pbot}->{capabilities}->userhas($user, 'admin');
  return $user;
}

sub loggedin {
  my ($self, $channel, $hostmask) = @_;
  my $user = $self->find_user($channel, $hostmask);
  return $user if defined $user and $user->{loggedin};
  return undef;
}

sub loggedin_admin {
  my ($self, $channel, $hostmask) = @_;
  my $user = $self->loggedin($channel, $hostmask);
  return $user if defined $user and $self->{pbot}->{capabilities}->userhas($user, 'admin');
  return undef;
}

sub login {
  my ($self, $channel, $hostmask, $password) = @_;
  my $user = $self->find_user($channel, $hostmask);
  my $channel_text = $channel eq '.*' ? '' : " for $channel";

  if (not defined $user) {
    $self->{pbot}->{logger}->log("Attempt to login non-existent [$channel][$hostmask] failed\n");
    return "You do not have a user account$channel_text.";
  }

  if (defined $password and $user->{password} ne $password) {
    $self->{pbot}->{logger}->log("Bad login password for [$channel][$hostmask]\n");
    return "I don't think so.";
  }

  $user->{loggedin} = 1;
  $self->{pbot}->{logger}->log("$hostmask logged into $user->{name} ($hostmask)$channel_text.\n");
  return "Logged into $user->{name} ($hostmask)$channel_text.";
}

sub logout {
  my ($self, $channel, $hostmask) = @_;
  my $user = $self->find_user($channel, $hostmask);
  delete $user->{loggedin} if defined $user;
}

sub get_loggedin_user_metadata {
  my ($self, $channel, $hostmask, $key) = @_;
  my $user = $self->loggedin($channel, $hostmask);
  return $user->{lc $key} if $user;
  return undef;
}

sub logincmd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $channel = $from;
  return "Usage: login [channel] password" if not $arguments;

  if ($arguments =~ m/^([^ ]+)\s+(.+)/) {
    $channel = $1;
    $arguments = $2;
  }

  my ($user_channel, $user_hostmask) = $self->find_user_account($channel, "$nick!$user\@$host");
  return "/msg $nick You do not have a user account." if not defined $user_channel;

  my $u = $self->{users}->{hash}->{$user_channel}->{$user_hostmask};
  my $channel_text = $user_channel eq '.*' ? '' : " for $user_channel";

  if ($u->{loggedin}) {
    return "/msg $nick You are already logged into $u->{name} ($user_hostmask)$channel_text.";
  }

  my $result = $self->login($user_channel, $user_hostmask, $arguments);
  return "/msg $nick $result";
}

sub logoutcmd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  $from = $arguments if length $arguments;
  my ($user_channel, $user_hostmask) = $self->find_user_account($from, "$nick!$user\@$host");
  return "/msg $nick You do not have a user account." if not defined $user_channel;

  my $u = $self->{users}->{hash}->{$user_channel}->{$user_hostmask};
  my $channel_text = $user_channel eq '.*' ? '' : " for $user_channel";
  return "/msg $nick You are not logged into $u->{name} ($user_hostmask)$channel_text." if not $u->{loggedin};

  $self->logout($user_channel, $user_hostmask);
  return "/msg $nick Logged out of $u->{name} ($user_hostmask)$channel_text.";
}

sub users {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my $channel = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});
  $channel = $from if not defined $channel;

  my $text = "Users: ";
  my $last_channel = "";
  my $sep = "";
  foreach my $chan (sort keys %{ $self->{users}->{hash} }) {
    next if $from =~ m/^#/ and $chan ne $channel and $chan ne '.*';
    next if $from !~ m/^#/ and $channel =~ m/^#/ and $chan ne $channel;

    if ($last_channel ne $chan) {
      $text .= $sep . ($chan eq ".*" ? "global" : $chan) . ": ";
      $last_channel = $chan;
      $sep = "";
    }

    foreach my $hostmask (sort { return 0 if $a eq '_name' or $b eq '_name'; $self->{users}->{hash}->{$chan}->{$a}->{name} cmp $self->{users}->{hash}->{$chan}->{$b}->{name} } keys %{ $self->{users}->{hash}->{$chan} }) {
      next if $hostmask eq '_name';
      $text .= $sep;
      my $has_cap = 0;
      foreach my $key (keys %{$self->{users}->{hash}->{$chan}->{$hostmask}}) {
        next if $key eq '_name';
        if ($self->{pbot}->{capabilities}->exists($key)) {
          $has_cap = 1;
          last;
        }
      }
      $text .= '+' if $has_cap;
      $text .= $self->{users}->{hash}->{$chan}->{$hostmask}->{name};
      $sep = " ";
    }
    $sep = "; ";
  }
  return $text;
}

sub useradd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($name, $channel, $hostmask, $capabilities, $password) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 5);
  $capabilities //= 'none';

  if (not defined $name or not defined $channel or not defined $hostmask) {
    return "Usage: useradd <account name> <channel> <hostmask> [capabilities [password]]";
  }

  $channel = '.*' if $channel !~ /^#/;

  my $u = $self->{pbot}->{users}->find_user($channel, "$nick!$user\@$host");

  if (not defined $u) {
    $channel = 'global' if $channel eq '.*';
    return "You do not have a user account for $channel; cannot add users to that channel.\n";
  }

  if ($capabilities ne 'none' and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-capabilities')) {
    return "Your user account does not have the can-modify-capabilities capability. You cannot create user accounts with capabilities.";
  }

  foreach my $cap (split /\s*,\s*/, lc $capabilities) {
    next if $cap eq 'none';
    return "There is no such capability $cap." if not $self->{pbot}->{capabilities}->exists($cap);
    if (not $self->{pbot}->{capabilities}->userhas($u, $cap)) {
      return "To set the $cap capability your user account must also have it.";
    }
    if ($self->{pbot}->{capabilities}->has($cap, 'admin') and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-admins')) {
      return "To set the $cap capability your user account must have the can-modify-admins capability.";
    }
  }
  $self->{pbot}->{users}->add_user($name, $channel, $hostmask, $capabilities, $password);
  return "User added.";
}

sub userdel {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($channel, $hostmask) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $channel or not defined $hostmask) {
    return "Usage: userdel <channel> <hostmask or account name>";
  }

  my $u = $self->find_user($channel, "$nick!$user\@$host");
  my $t = $self->find_user($channel, $hostmask);

  if ($self->{pbot}->{capabilities}->userhas($t, 'botowner') and not $self->{pbot}->{capabilities}->userhas($u, 'botowner')) {
    return "Only botowners may delete botowner user accounts.";
  }

  if ($self->{pbot}->{capabilities}->userhas($t, 'admin') and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-admins')) {
    return "To delete admin user accounts your user account must have the can-modify-admins capability.";
  }

  my ($found_channel, $found_hostmask) = $self->find_user_account($channel, $hostmask);
  $found_channel = $channel if not defined $found_channel; # let DualIndexHashObject disambiguate
  return $self->remove_user($found_channel, $found_hostmask);
}

sub userset {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (length $arguments and $stuff->{arglist}[0] !~ m/^(#|\.\*$|global$)/) {
    $self->{pbot}->{interpreter}->unshift_arg($stuff->{arglist}, $from)
  }

  my ($channel, $hostmask, $key, $value) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 4);

  if (not defined $hostmask) {
    return "Usage: userset [channel] <hostmask or account name> [key [value]]";
  }

  my $u = $self->find_user($channel, "$nick!$user\@$host");
  my $target = $self->find_user($channel, $hostmask);

  if (not $u) {
    $channel = 'global' if $channel eq '.*';
    return "You do not have a user account for $channel; cannot modify their users.";
  }

  if (not $target) {
    if ($channel !~ /^#/) {
      return "There is no user account $hostmask.";
    } else {
      return "There is no user account $hostmask for $channel.";
    }
  }

  if (defined $value and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-capabilities')) {
    if ($key =~ m/^can-/i or $self->{pbot}->{capabilities}->exists($key)) {
      return "The $key metadata requires the can-modify-capabilities capability, which your user account does not have.";
    }
  }

  if (defined $value and $self->{pbot}->{capabilities}->userhas($target, 'admin') and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-admins')) {
    return "To modify admin user accounts your user account must have the can-modify-admins capability.";
  }

  if (defined $key and $self->{pbot}->{capabilities}->exists($key) and not $self->{pbot}->{capabilities}->userhas($u, $key)) {
    return "To set the $key capability your user account must also have it." unless $self->{pbot}->{capabilities}->userhas($u, 'botowner');
  }

  my ($found_channel, $found_hostmask) = $self->find_user_account($channel, $hostmask);
  $found_channel = $channel if not defined $found_channel; # let DualIndexHashObject disambiguate
  my $result = $self->{users}->set($found_channel, $found_hostmask, $key, $value);
  $result =~ s/^password => .*;?$/password => <private>;/m;
  return $result;
}

sub userunset {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (length $arguments and $stuff->{arglist}[0] !~ m/^(#|\.\*$|global$)/) {
    $self->{pbot}->{interpreter}->unshift_arg($stuff->{arglist}, $from)
  }

  my ($channel, $hostmask, $key) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  if (not defined $hostmask) {
    return "Usage: userunset [channel] <hostmask or account name> <key>";
  }

  my $u = $self->find_user($channel, "$nick!$user\@$host");
  my $target = $self->find_user($channel, $hostmask);

  if (not $u) {
    $channel = 'global' if $channel eq '.*';
    return "You do not have a user account for $channel; cannot modify their users.";
  }

  if (not $target) {
    if ($channel !~ /^#/) {
      return "There is no user account $hostmask.";
    } else {
      return "There is no user account $hostmask for $channel.";
    }
  }

  if (defined $key and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-capabilities')) {
    if ($key =~ m/^can-/i or $self->{pbot}->{capabilities}->exists($key)) {
      return "The $key metadata requires the can-modify-capabilities capability, which your user account does not have.";
    }
  }

  if (defined $key and $self->{pbot}->{capabilities}->userhas($target, 'admin') and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-admins')) {
    return "To modify admin user accounts your user account must have the can-modify-admins capability.";
  }

  if (defined $key and $self->{pbot}->{capabilities}->exists($key) and not $self->{pbot}->{capabilities}->userhas($u, $key)) {
    return "To unset the $key capability your user account must also have it." unless $self->{pbot}->{capabilities}->userhas($u, 'botowner');
  }

  my ($found_channel, $found_hostmask) = $self->find_user_account($channel, $hostmask);
  $found_channel = $channel if not defined $found_channel; # let DualIndexHashObject disambiguate
  return $self->{users}->unset($found_channel, $found_hostmask, $key);
}

sub mycmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($key, $value) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (defined $value) {
    $value =~ s/^is\s+//;
    $value = undef if not length $value;
  }

  my $channel = $from;
  my $hostmask = "$nick!$user\@$host";

  my $u = $self->find_user($channel, $hostmask);

  if (not $u) {
    $channel = '.*';
    $hostmask = "$nick!$user\@" . $self->{pbot}->{antiflood}->address_to_mask($host);
    my $name = $nick;

    my ($existing_channel, $existing_hostmask) = $self->find_user_account($channel, $name);
    if ($existing_hostmask ne lc $name) {
      # user exists by name
      return "There is already an user account named $name but its hostmask ($existing_hostmask) does not match your hostmask ($hostmask). Ask an admin for help.";
    }

    $u = $self->add_user($name, $channel, $hostmask, undef, undef, 1);
    $u->{loggedin} = 1;
    $u->{stayloggedin} = 1;
    $u->{autologin} = 1;
    $self->save;
  }

  my $result = '';

  if (defined $key) {
    $key = lc $key;
    if (defined $value) {
      if (not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-capabilities')) {
        if ($key =~ m/^is-/ or $key =~ m/^can-/ or $self->{pbot}->{capabilities}->exists($key)) {
          return "The $key metadata requires the can-modify-capabilities capability, which your user account does not have.";
        }
      }

      if (not $self->{pbot}->{capabilities}->userhas($u, 'botowner')) {
        my @disallowed = qw/can-modify-admins botowner can-modify-capabilities/;
        if (grep { $_ eq $key } @disallowed) {
          return "The $key metadata requires the botowner capability to set, which your user account does not have.";
        }
      }

      if (not $self->{pbot}->{capabilities}->userhas($u, 'admin')) {
        my @disallowed = qw/name autoop autovoice chanop admin/;
        if (grep { $_ eq $key } @disallowed) {
          return "The $key metadata requires the admin capability to set, which your user account does not have.";
        }
      }
    }
  } else {
    $result = "Usage: my <key> [value]; ";
  }

  my ($found_channel, $found_hostmask) = $self->find_user_account($channel, $hostmask);
  ($found_channel, $found_hostmask) = $self->find_user_account('.*', $hostmask) if not defined $found_channel;
  return "No user account found in $channel." if not defined $found_channel;
  $result .= $self->{users}->set($found_channel, $found_hostmask, $key, $value);
  $result =~ s/^password => .*;?$/password => <private>;/m;
  return $result;
}

1;
