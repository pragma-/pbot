# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::RestrictedMod;

# purpose: provides restricted moderation abilities to voiced users.
# They are allowed to ban/mute/kick only users that are not admins,
# whitelisted, or autoop/autovoice. This is useful for, e.g., IRCnet
# configurations where +v users are recognized as "semi-trusted" in
# order to provide assistance in combating heavy spam and drone traffic.

use warnings;
use strict;

use feature 'unicode_strings';
use Carp ();

use Storable qw/dclone/;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{commands}->register(sub { $self->modcmd(@_) }, 'mod', 0);
  $self->{pbot}->{commands}->set_meta('mod', 'help', 'Provides restricted moderation abilities to voiced users.');

  $self->{commands} = {
    'help' => { subref => sub { $self->help(@_)  }, help => "Provides help about this command. Usage: mod help <mod command>; see also: mod help list" },
    'list' => { subref => sub { $self->list(@_)  }, help => "Lists available mod commands. Usage: mod list" },
    'kick' => { subref => sub { $self->kick(@_)  }, help => "Kicks a nick from the channel. Usage: mod kick <nick>" },
    'ban'  => { subref => sub { $self->ban(@_)   }, help => "Bans a nick from the channel. Cannot be used to set a custom banmask. Usage: mod ban <nick>" },
    'kb'   => { subref => sub { $self->kb(@_)    }, help => "Kickbans a nick from the channel. Cannot be used to set a custom banmask. Usage: mod kb <nick>" },
    'mute' => { subref => sub { $self->mute(@_)  }, help => "Mutes a nick in the channel. Usage: mod mute <nick>" },
  };
}

sub unload {
  my ($self) = @_;
  $self->{pbot}->{commands}->unregister('mod');
}

sub help {
  my ($self, $stuff) = @_;
  my $command = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist}) // 'help';

  if (exists $self->{commands}->{$command}) {
    return $self->{commands}->{$command}->{help};
  } else {
    return "No such mod command '$command'. I can't help you with that.";
  }
}

sub list {
  my ($self, $stuff) = @_;
  return "Available mod commands: " . join ', ', sort keys %{$self->{commands}};
}

sub generic_command {
  my ($self, $stuff, $command, $op_command) = @_;

  my $channel = $stuff->{from};
  if ($channel !~ m/^#/) {
    $channel = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});

    if (not defined $channel or $channel !~ /^#/) {
      return "Must specify channel from private message. Usage: mod $command <channel> <nick>";
    }
  }

  my $hostmask = "$stuff->{nick}!$stuff->{user}\@$stuff->{host}";
  my $admin = $self->{pbot}->{users}->loggedin_admin($channel, $hostmask);
  my $voiced = $self->{pbot}->{nicklist}->get_meta($channel, $stuff->{nick}, '+v');
  return "You must be voiced (usermode +v) or an admin to use this command." if not $voiced and not $admin;

  my $target = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist});

  if (not defined $target) {
    return "Missing target. Usage: mod $command <nick>";
  }

  my $target_nicklist;
  if (not $self->{pbot}->{nicklist}->is_present($channel, $target)) {
    return "$stuff->{nick}: I do not see anybody named $target in this channel.";
  } else {
    $target_nicklist = $self->{pbot}->{nicklist}->{nicklist}->{lc $channel}->{lc $target};
  }

  return "I do not have OPs for this channel. I cannot do any moderation here." if not $self->{pbot}->{chanops}->can_gain_ops($channel);

  my $target_user = $self->{pbot}->{users}->find_user($channel, $target_nicklist->{hostmask});

  if ((defined $target_user and $target_user->{level} > 0) or $target_user->{autoop} or $target_user->{autovoice}
      or $target_nicklist->{'+v'} or $target_nicklist->{'+o'}
      or $self->{pbot}->{antiflood}->whitelisted($channel, $target_nicklist->{hostmask})) {
    return "I don't think so."
  }

  $op_command =~ s/\$channel\b/$channel/g;
  $op_command =~ s/\$target\b/$target/g;

  if ($op_command =~ /\$mask\b/) {
    my $mask = "*!$target_nicklist->{user}\@" . $self->{pbot}->{antiflood}->address_to_mask($target_nicklist->{host});
    $op_command =~ s/\$mask\b/$mask/g;
  }

  $self->{pbot}->{chanops}->add_op_command($channel, $op_command);
  $self->{pbot}->{chanops}->gain_ops($channel);
  return "";
}

sub kick {
  my ($self, $stuff) = @_;
  return $self->generic_command($stuff, 'kick', 'kick $channel $target Good-bye!');
}

sub ban {
  my ($self, $stuff) = @_;
  return $self->generic_command($stuff, 'ban', 'mode $channel +b $mask');
}

sub kb {
  my ($self, $stuff) = @_;
  my $result = $self->ban(dclone $stuff); # note: using copy of $stuff
  return $result if length $result;
  return $self->kick($stuff);
}

sub mute {
  my ($self, $stuff) = @_;
  return $self->generic_command($stuff, 'mute', 'mode $channel +q $mask');
}

sub modcmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my $command = $self->{pbot}->{interpreter}->shift_arg($stuff->{arglist}) // '';
  $command = lc $command;

  if (grep { $_ eq $command } keys %{$self->{commands}}) {
    return $self->{commands}->{$command}->{subref}->($stuff);
  } else {
    my $commands = join ', ', sort keys %{$self->{commands}};
    if ($from !~ m/^#/) {
      return "Usage: mod <channel> <command> [arguments]; commands are: $commands; see `mod help <command>` for more information.";
    } else {
      return "Usage: mod <command> [arguments]; commands are: $commands; see `mod help <command>` for more information.";
    }
  }
}

1;
