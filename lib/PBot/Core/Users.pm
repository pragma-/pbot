# File: Users.pm
#
# Purpose: Manages list of bot users/admins and their metadata.

# SPDX-FileCopyrightText: 2005-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Users;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Crypt::SaltedHash;

sub initialize($self, %conf) {
    $self->{storage} = PBot::Core::Storage::HashObject->new(
        pbot     => $conf{pbot},
        name     => 'Users',
        filename => $conf{filename},
    );

    $self->{user_index} = {};
    $self->{user_cache} = {};

    $self->load;
}

sub add_user($self, $name, $channels, $hostmasks, $capabilities = 'none', $password = undef, $dont_save = 0) {
    $channels = 'global' if $channels !~ m/^#/;

    $password //= $self->{pbot}->random_nick(16);
    $password   = $self->digest_password($password);

    my $data = {
        channels  => $channels,
        hostmasks => $hostmasks,
        password  => $password
    };

    foreach my $cap (split /\s*,\s*/, lc $capabilities) {
        next if $cap eq 'none';
        $data->{$cap} = 1;
    }

    $self->{pbot}->{logger}->log("Adding new user (caps: $capabilities): name: $name hostmasks: $hostmasks channels: $channels\n");
    $self->{storage}->add($name, $data, $dont_save);
    $self->rebuild_user_index;
    return $data;
}

sub remove_user($self, $name) {
    my $result = $self->{storage}->remove($name);
    $self->rebuild_user_index;
    return $result;
}

sub load($self) {
    $self->{storage}->load;
    $self->rebuild_user_index;

    my $i = 0;
    foreach my $name (sort $self->{storage}->get_keys) {
        $i++;
        my $password  = $self->{storage}->get_data($name, 'password');
        my $channels  = $self->{storage}->get_data($name, 'channels');
        my $hostmasks = $self->{storage}->get_data($name, 'hostmasks');
        if (not defined $channels or not defined $hostmasks or not defined $password) {
            Carp::croak "User $name is missing critical data\n";
        }
    }
    $self->{pbot}->{logger}->log("  $i users loaded.\n");
}

sub save($self) {
    $self->{storage}->save;
}

sub rebuild_user_index($self) {
    $self->{user_index} = {};
    $self->{user_cache} = {};

    foreach my $name ($self->{storage}->get_keys) {
        my $channels  = $self->{storage}->get_data($name, 'channels');
        my $hostmasks = $self->{storage}->get_data($name, 'hostmasks');

        my @c = split /\s*,\s*/, $channels;
        my @h = split /\s*,\s*/, $hostmasks;

        foreach my $channel (@c) {
            foreach my $hostmask (@h) {
                $self->{user_index}->{lc $channel}->{lc $hostmask} = $name;
            }
        }
    }
}

sub cache_user($self, $channel, $hostmask, $username, $account_mask) {
    return if not length $username or not length $account_mask;
    $self->{user_cache}->{lc $channel}->{lc $hostmask} = [ $username, $account_mask ];
}

sub decache_user($self, $channel, $hostmask) {
    my $lc_channel = lc $channel;
    my $lc_hostmask = lc $hostmask;
    delete $self->{user_cache}->{$lc_channel}->{$lc_hostmask} if exists $self->{user_cache}->{$lc_channel};
    delete $self->{user_cache}->{global}->{$lc_hostmask};
}

sub find_user_account($self, $channel, $hostmask, $any_channel = 0) {
    $channel  = lc $channel;
    $hostmask = lc $hostmask;

    # first try to find an exact match

    if (exists $self->{user_cache}->{$channel} and exists $self->{user_cache}->{$channel}->{$hostmask}) {
        my ($username, $account_mask) = @{$self->{user_cache}->{$channel}->{$hostmask}};
        return ($channel, $account_mask);
    }

    if (exists $self->{user_cache}->{global} and exists $self->{user_cache}->{global}->{$hostmask}) {
        my ($username, $account_mask) = @{$self->{user_cache}->{global}->{$hostmask}};
        return ('global', $account_mask);
    }

    if (exists $self->{user_index}->{$channel} and exists $self->{user_index}->{$channel}->{$hostmask}) {
        return ($channel, $hostmask);
    }

    if (exists $self->{user_index}->{global} and exists $self->{user_index}->{global}->{$hostmask}) {
        return ('global', $hostmask);
    }

    # no exact matches found -- check for wildcard matches

    my @search_channels;

    if ($any_channel) {
        @search_channels = keys %{$self->{user_index}};
    } else {
        @search_channels = ($channel, 'global');
    }

    foreach my $search_channel (@search_channels) {
        if (exists $self->{user_index}->{$search_channel}) {
            foreach my $mask (keys %{$self->{user_index}->{$search_channel}}) {
                my $mask_quoted = quotemeta $mask;
                $mask_quoted =~ s/\\\*/.*?/g;
                $mask_quoted =~ s/\\\?/./g;
                if ($hostmask =~ m/^$mask_quoted$/i) {
                    return ($search_channel, $mask);
                }
            }
        }
    }

    return (undef, $hostmask);
}

sub find_user($self, $channel, $hostmask, $any_channel = 0) {
    my ($found_channel, $found_hostmask) = $self->find_user_account($channel, $hostmask, $any_channel);
    return undef if not defined $found_channel;
    my $name = $self->{user_index}->{$found_channel}->{$found_hostmask};
    $self->cache_user($found_channel, $hostmask, $name, $found_hostmask);
    return wantarray ? ($self->{storage}->get_data($name), $name) : $self->{storage}->get_data($name);
}

sub find_admin($self, $from, $hostmask) {
    my $user = $self->find_user($from, $hostmask);
    return undef if not defined $user;
    return undef if not $self->{pbot}->{capabilities}->userhas($user, 'admin');
    return $user;
}

sub login($self, $channel, $hostmask, $password = undef) {
    my $user         = $self->find_user($channel, $hostmask);
    my $channel_text = $channel eq 'global' ? '' : " for $channel";

    if (not defined $user) {
        $self->{pbot}->{logger}->log("Attempt to login non-existent $channel $hostmask failed\n");
        return "You do not have a user account$channel_text.";
    }

    if (defined $password and !Crypt::SaltedHash->validate($user->{password}, $password)) {
        $self->{pbot}->{logger}->log("Bad login password for $channel $hostmask\n");
        return "I don't think so.";
    }

    $user->{loggedin} = 1;
    my ($user_chan, $user_hostmask) = $self->find_user_account($channel, $hostmask);
    my $name = $self->{user_index}->{$user_chan}->{$user_hostmask};
    $self->{pbot}->{logger}->log("$hostmask logged into " . $self->{storage}->get_key_name($name) . " ($hostmask)$channel_text.\n");
    return "Logged into " . $self->{storage}->get_key_name($name) . " ($hostmask)$channel_text.";
}

sub logout($self, $channel, $hostmask) {
    my $user = $self->find_user($channel, $hostmask);
    delete $user->{loggedin} if defined $user;
}

sub loggedin($self, $channel, $hostmask) {
    my $user = $self->find_user($channel, $hostmask);
    return $user if defined $user and $user->{loggedin};
    return undef;
}

sub loggedin_admin($self, $channel, $hostmask) {
    my $user = $self->loggedin($channel, $hostmask);
    return $user if defined $user and $self->{pbot}->{capabilities}->userhas($user, 'admin');
    return undef;
}

sub get_user_metadata($self, $channel, $hostmask, $key) {
    my $user = $self->find_user($channel, $hostmask, 1);
    return $user->{lc $key} if $user;
    return undef;
}

sub get_loggedin_user_metadata($self, $channel, $hostmask, $key) {
    my $user = $self->loggedin($channel, $hostmask);
    return $user->{lc $key} if $user;
    return undef;
}

sub digest_password($self, $password) {
    my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-512');
    $csh->add($password);
    return $csh->generate;
}

1;
