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
    $self->{users} = PBot::HashObject->new(name => 'Users', filename => $conf{filename}, pbot => $conf{pbot});

    $self->{pbot}->{commands}->register(sub { $self->cmd_login(@_) },     "login",     0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_logout(@_) },    "logout",    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_useradd(@_) },   "useradd",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_userdel(@_) },   "userdel",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_userset(@_) },   "userset",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_userunset(@_) }, "userunset", 1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_users(@_) },     "users",     0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_my(@_) },        "my",        0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_id(@_) },        "id",        0);

    $self->{pbot}->{capabilities}->add('admin',             'can-useradd',   1);
    $self->{pbot}->{capabilities}->add('admin',             'can-userdel',   1);
    $self->{pbot}->{capabilities}->add('admin',             'can-userset',   1);
    $self->{pbot}->{capabilities}->add('admin',             'can-userunset', 1);
    $self->{pbot}->{capabilities}->add('can-modify-admins', undef,           1);

    $self->{pbot}->{event_dispatcher}->register_handler('irc.join',  sub { $self->on_join(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.part',  sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',  sub { $self->on_departure(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',  sub { $self->on_kick(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.part', sub { $self->on_self_part(@_) });

    $self->{user_index} = {};
    $self->{user_cache} = {};

    $self->load;
}

sub on_join {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);
    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    my ($u, $name) = $self->find_user($channel, "$nick!$user\@$host");

    if (defined $u) {
        if ($self->{pbot}->{chanops}->can_gain_ops($channel)) {
            my $modes   = '+';
            my $targets = '';

            if ($u->{autoop}) {
                $self->{pbot}->{logger}->log("$nick!$user\@$host autoop in $channel\n");
                $modes   .= 'o';
                $targets .= "$nick ";
            }

            if ($u->{autovoice}) {
                $self->{pbot}->{logger}->log("$nick!$user\@$host autovoice in $channel\n");
                $modes   .= 'v';
                $targets .= "$nick ";
            }

            if (length $modes > 1) {
                $self->{pbot}->{chanops}->add_op_command($channel, "mode $channel $modes $targets");
                $self->{pbot}->{chanops}->gain_ops($channel);
            }
        }

        if ($u->{autologin}) {
            $self->{pbot}->{logger}->log("$nick!$user\@$host autologin to $name for $channel\n");
            $u->{loggedin} = 1;
        }
    }
    return 0;
}

sub on_departure {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);
    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);
    $self->decache_user($channel, "$nick!$user\@$host");
}

sub on_kick {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->{args}[0]);
    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);
    $self->decache_user($channel, "$nick!$user\@$host");
}

sub on_self_part {
    my ($self, $event_type, $event) = @_;
    delete $self->{user_cache}->{lc $event->{channel}};
}

sub cmd_login {
    my ($self, $context) = @_;
    my $channel = $context->{from};
    return "Usage: login [channel] password" if not $context->{arguments};

    my $arguments = $context->{arguments};

    if ($arguments =~ m/^([^ ]+)\s+(.+)/) {
        $channel   = $1;
        $arguments = $2;
    }

    my ($user_channel, $user_hostmask) = $self->find_user_account($channel, $context->{hostmask});
    return "/msg $context->{nick} You do not have a user account. You may use the `my` command to create a personal user account. See `help my`." if not defined $user_channel;

    my $name = $self->{user_index}->{$user_channel}->{$user_hostmask};

    my $u            = $self->{users}->get_data($name);
    my $channel_text = $user_channel eq 'global' ? '' : " for $user_channel";

    if ($u->{loggedin}) {
        return "/msg $context->{nick} You are already logged into " . $self->{users}->get_key_name($name) . " ($user_hostmask)$channel_text.";
    }

    my $result = $self->login($user_channel, $user_hostmask, $arguments);
    return "/msg $context->{nick} $result";
}

sub cmd_logout {
    my ($self, $context) = @_;
    $context->{from} = $context->{arguments} if length $context->{arguments};
    my ($user_channel, $user_hostmask) = $self->find_user_account($context->{from}, $context->{hostmask});
    return "/msg $context->{nick} You do not have a user account. You may use the `my` command to create a personal user account. See `help my`." if not defined $user_channel;

    my $name = $self->{user_index}->{$user_channel}->{$user_hostmask};

    my $u            = $self->{users}->get_data($name);
    my $channel_text = $user_channel eq 'global' ? '' : " for $user_channel";
    return "/msg $context->{nick} You are not logged into " . $self->{users}->get_key_name($name) . " ($user_hostmask)$channel_text." if not $u->{loggedin};

    $self->logout($user_channel, $user_hostmask);
    return "/msg $context->{nick} Logged out of " . $self->{users}->get_key_name($name) . " ($user_hostmask)$channel_text.";
}

sub cmd_users {
    my ($self, $context) = @_;
    my $channel = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    my $include_global = '';
    if (not defined $channel) {
        $channel        = $context->{from};
        $include_global = 'global';
    } else {
        $channel = 'global' if $channel !~ /^#/;
    }

    my $text         = "Users: ";
    my $last_channel = "";
    my $sep          = "";
    foreach my $chan (sort keys %{$self->{user_index}}) {
        next if $context->{from} =~ m/^#/ and $chan ne $channel and $chan ne $include_global;
        next if $context->{from} !~ m/^#/ and $channel =~ m/^#/ and $chan ne $channel;

        if ($last_channel ne $chan) {
            $text .= "$sep$chan: ";
            $last_channel = $chan;
            $sep          = "";
        }

        my %seen_names;

        foreach my $hostmask (
            sort { $self->{user_index}->{$chan}->{$a} cmp $self->{user_index}->{$chan}->{$b} }
            keys %{$self->{user_index}->{$chan}}
        )
        {
            my $name = $self->{user_index}->{$chan}->{$hostmask};
            next if $seen_names{$name};
            $seen_names{$name} = 1;
            $text .= $sep;
            my $has_cap = 0;
            foreach my $key ($self->{users}->get_keys($name)) {
                if ($self->{pbot}->{capabilities}->exists($key)) {
                    $has_cap = 1;
                    last;
                }
            }
            $text .= '+' if $has_cap;
            $text .= $self->{users}->get_key_name($name);
            $sep = " ";
        }
        $sep = "; ";
    }
    return $text;
}

sub cmd_useradd {
    my ($self, $context) = @_;
    my ($name, $hostmasks, $channels, $capabilities, $password) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 5);
    $capabilities //= 'none';

    if (not defined $name or not defined $hostmasks) { return "Usage: useradd <username> <hostmasks> [channels [capabilities [password]]]"; }

    $channels = 'global' if $channels !~ /^#/;

    my $u;
    foreach my $channel (sort split /\s*,\s*/, lc $channels) {
        $u = $self->{pbot}->{users}->find_user($channel, $context->{hostmask});

        if (not defined $u) {
            return "You do not have a user account for $channel; cannot add users to that channel.\n";
        }
    }

    if ($capabilities ne 'none' and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-capabilities')) {
        return "Your user account does not have the can-modify-capabilities capability. You cannot create user accounts with capabilities.";
    }

    foreach my $cap (split /\s*,\s*/, lc $capabilities) {
        next if $cap eq 'none';

        return "There is no such capability $cap." if not $self->{pbot}->{capabilities}->exists($cap);

        if (not $self->{pbot}->{capabilities}->userhas($u, $cap)) { return "To set the $cap capability your user account must also have it."; }

        if ($self->{pbot}->{capabilities}->has($cap, 'admin') and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-admins')) {
            return "To set the $cap capability your user account must have the can-modify-admins capability.";
        }
    }

    $self->{pbot}->{users}->add_user($name, $channels, $hostmasks, $capabilities, $password);
    return "User added.";
}

sub cmd_userdel {
    my ($self, $context) = @_;

    if (not length $context->{arguments}) { return "Usage: userdel <username>"; }

    my $u = $self->find_user($context->{from}, $context->{hostmask});
    my $t = $self->{users}->get_data($context->{arguments});

    if ($self->{pbot}->{capabilities}->userhas($t, 'botowner') and not $self->{pbot}->{capabilities}->userhas($u, 'botowner')) {
        return "Only botowners may delete botowner user accounts.";
    }

    if ($self->{pbot}->{capabilities}->userhas($t, 'admin') and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-admins')) {
        return "To delete admin user accounts your user account must have the can-modify-admins capability.";
    }

    return $self->remove_user($context->{arguments});
}

sub cmd_userset {
    my ($self, $context) = @_;

    my ($name, $key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    if (not defined $name) { return "Usage: userset <username> [key [value]]"; }

    my $channel = $context->{from};

    my $u      = $self->find_user($channel, $context->{hostmask}, 1);
    my $target = $self->{users}->get_data($name);

    if (not $u) {
        $channel = 'global' if $channel !~ /^#/;
        return "You do not have a user account for $channel; cannot modify their users.";
    }

    if (not $target) {
        return "There is no user account $name.";
    }

    $key = lc $key if defined $key;

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

    my $result = $self->{users}->set($name, $key, $value);
    print "result [$result]\n";
    $result =~ s/^password: .*;?$/password: <private>;/m;

    if (defined $key and ($key eq 'channels' or $key eq 'hostmasks') and defined $value) {
        $self->rebuild_user_index;
    }

    return $result;
}

sub cmd_userunset {
    my ($self, $context) = @_;

    my ($name, $key) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (not defined $name or not defined $key) { return "Usage: userunset <username> <key>"; }

    $key = lc $key;

    my @disallowed = qw/channels hostmasks password/;
    if (grep { $_ eq $key } @disallowed) {
        return "The $key metadata cannot be unset. Use the `userset` command to modify it.";
    }

    my $channel = $context->{from};

    my $u      = $self->find_user($channel, $context->{hostmask}, 1);
    my $target = $self->{users}->get_data($name);

    if (not $u) {
        $channel = 'global' if $channel !~ /^#/;
        return "You do not have a user account for $channel; cannot modify their users.";
    }

    if (not $target) {
        return "There is no user account $name.";
    }

    if (not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-capabilities')) {
        if ($key =~ m/^can-/i or $self->{pbot}->{capabilities}->exists($key)) {
            return "The $key metadata requires the can-modify-capabilities capability, which your user account does not have.";
        }
    }

    if ($self->{pbot}->{capabilities}->userhas($target, 'admin') and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-admins')) {
        return "To modify admin user accounts your user account must have the can-modify-admins capability.";
    }

    if ($self->{pbot}->{capabilities}->exists($key) and not $self->{pbot}->{capabilities}->userhas($u, $key)) {
        return "To unset the $key capability your user account must also have it." unless $self->{pbot}->{capabilities}->userhas($u, 'botowner');
    }

    return $self->{users}->unset($name, $key);
}

sub cmd_my {
    my ($self, $context) = @_;
    my ($key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (defined $value) {
        $value =~ s/^is\s+//;
        $value = undef if not length $value;
    }

    my $channel  = $context->{from};
    my $hostmask = $context->{hostmask};

    my ($u, $name) = $self->find_user($channel, $hostmask, 1);

    if (not $u) {
        $channel  = 'global';
        $hostmask = "$context->{nick}!$context->{user}\@" . $self->{pbot}->{antiflood}->address_to_mask($context->{host});
        $name = $context->{nick};

        $u = $self->{users}->get_data($name);
        if ($u) {
            $self->{pbot}->{logger}->log("Adding additional hostmask $hostmask to user account $name\n");
            $u->{hostmasks} .= ",$hostmask";
            $self->rebuild_user_index;
        } else {
            $u                 = $self->add_user($name, $channel, $hostmask, undef, undef, 1);
            $u->{loggedin}     = 1;
            $u->{stayloggedin} = 1;
            $u->{autologin}    = 1;
            $self->save;
        }
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
                my @disallowed = qw/can-modify-admins botowner can-modify-capabilities channels/;
                if (grep { $_ eq $key } @disallowed) {
                    return "The $key metadata requires the botowner capability to set, which your user account does not have.";
                }
            }

            if (not $self->{pbot}->{capabilities}->userhas($u, 'admin')) {
                my @disallowed = qw/name autoop autovoice chanop admin hostmasks/;
                if (grep { $_ eq $key } @disallowed) {
                    return "The $key metadata requires the admin capability to set, which your user account does not have.";
                }
            }
        }
    } else {
        $result = "Usage: my <key> [value]; ";
    }

    $result .= $self->{users}->set($name, $key, $value);
    $result =~ s/^password: .*;?$/password: <private>;/m;
    return $result;
}

sub cmd_id {
    my ($self, $context) = @_;

    my $target = length $context->{arguments} ? $context->{arguments} : $context->{nick};

    my ($message_account, $hostmask);

    if ($target =~ m/^\d+$/) {
        $hostmask = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_id($target);
        return "I don't know anybody with id $target." if not $hostmask;
        $message_account = $target;
    } else {
        ($message_account, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($target);
        return "I don't know anybody named $target." if not $message_account;
    }

    my $ancestor_id = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($message_account);
    my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($message_account);

    my ($u, $name) = $self->find_user($context->{from}, $hostmask, 1);

    my $result = "$target ($hostmask): user id: $message_account; ";

    if ($message_account != $ancestor_id) {
        my $ancestor_hostmask = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_id($ancestor_id);
        $ancestor_hostmask = 'undefined' if not $ancestor_hostmask;
        $result .= "parent user id: $ancestor_id ($ancestor_hostmask); ";
    }

    if (defined $u) {
        $result .= "user account: $name (";
        $result .= ($u->{loggedin} ? "logged in" : "not logged in") . '); ';
    }

    if (defined $nickserv and length $nickserv) {
        $result .= "NickServ: $nickserv";
    }

    return $result;
}

sub add_user {
    my ($self, $name, $channels, $hostmasks, $capabilities, $password, $dont_save) = @_;
    $channels = 'global' if $channels !~ m/^#/;

    $capabilities //= 'none';
    $password     //= $self->{pbot}->random_nick(16);

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
    $self->{users}->add($name, $data, $dont_save);
    $self->rebuild_user_index;
    return $data;
}

sub remove_user {
    my ($self, $name) = @_;
    my $result = $self->{users}->remove($name);
    $self->rebuild_user_index;
    return $result;
}

sub load {
    my $self = shift;

    $self->{users}->load;
    $self->rebuild_user_index;

    my $i = 0;
    foreach my $name (sort $self->{users}->get_keys) {
        $i++;
        my $password  = $self->{users}->get_data($name, 'password');
        my $channels  = $self->{users}->get_data($name, 'channels');
        my $hostmasks = $self->{users}->get_data($name, 'hostmasks');
        if (not defined $channels or not defined $hostmasks or not defined $password) {
            Carp::croak "User $name is missing critical data\n";
        }
    }
    $self->{pbot}->{logger}->log("  $i users loaded.\n");
}

sub save {
    my ($self) = @_;
    $self->{users}->save;
}

sub rebuild_user_index {
    my ($self) = @_;

    $self->{user_index} = {};
    $self->{user_cache} = {};

    foreach my $name ($self->{users}->get_keys) {
        my $channels  = $self->{users}->get_data($name, 'channels');
        my $hostmasks = $self->{users}->get_data($name, 'hostmasks');

        my @c = split /\s*,\s*/, $channels;
        my @h = split /\s*,\s*/, $hostmasks;

        foreach my $channel (@c) {
            foreach my $hostmask (@h) {
                $self->{user_index}->{lc $channel}->{lc $hostmask} = $name;
            }
        }
    }
}

sub cache_user {
    my ($self, $channel, $hostmask, $username, $account_mask) = @_;
    return if not length $username or not length $account_mask;
    $self->{user_cache}->{lc $channel}->{lc $hostmask} = [ $username, $account_mask ];
}

sub decache_user {
    my ($self, $channel, $hostmask) = @_;
    my $lc_channel = lc $channel;
    my $lc_hostmask = lc $hostmask;
    delete $self->{user_cache}->{$lc_channel}->{$lc_hostmask} if exists $self->{user_cache}->{$lc_channel};
    delete $self->{user_cache}->{global}->{$lc_hostmask};
}

sub find_user_account {
    my ($self, $channel, $hostmask, $any_channel) = @_;
    $channel  = lc $channel;
    $hostmask = lc $hostmask;
    $any_channel //= 0;

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

sub find_user {
    my ($self, $channel, $hostmask, $any_channel) = @_;
    $any_channel //= 0;
    my ($found_channel, $found_hostmask) = $self->find_user_account($channel, $hostmask, $any_channel);
    return undef if not defined $found_channel;
    my $name = $self->{user_index}->{$found_channel}->{$found_hostmask};
    $self->cache_user($found_channel, $hostmask, $name, $found_hostmask);
    return wantarray ? ($self->{users}->get_data($name), $name) : $self->{users}->get_data($name);
}

sub find_admin {
    my ($self, $from, $hostmask) = @_;
    my $user = $self->find_user($from, $hostmask);
    return undef if not defined $user;
    return undef if not $self->{pbot}->{capabilities}->userhas($user, 'admin');
    return $user;
}

sub login {
    my ($self, $channel, $hostmask, $password) = @_;
    my $user         = $self->find_user($channel, $hostmask);
    my $channel_text = $channel eq 'global' ? '' : " for $channel";

    if (not defined $user) {
        $self->{pbot}->{logger}->log("Attempt to login non-existent $channel $hostmask failed\n");
        return "You do not have a user account$channel_text.";
    }

    if (defined $password and $user->{password} ne $password) {
        $self->{pbot}->{logger}->log("Bad login password for $channel $hostmask\n");
        return "I don't think so.";
    }

    $user->{loggedin} = 1;
    my ($user_chan, $user_hostmask) = $self->find_user_account($channel, $hostmask);
    my $name = $self->{user_index}->{$user_chan}->{$user_hostmask};
    $self->{pbot}->{logger}->log("$hostmask logged into " . $self->{users}->get_key_name($name) . " ($hostmask)$channel_text.\n");
    return "Logged into " . $self->{users}->get_key_name($name) . " ($hostmask)$channel_text.";
}

sub logout {
    my ($self, $channel, $hostmask) = @_;
    my $user = $self->find_user($channel, $hostmask);
    delete $user->{loggedin} if defined $user;
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

sub get_user_metadata {
    my ($self, $channel, $hostmask, $key) = @_;
    my $user = $self->find_user($channel, $hostmask, 1);
    return $user->{lc $key} if $user;
    return undef;
}

sub get_loggedin_user_metadata {
    my ($self, $channel, $hostmask, $key) = @_;
    my $user = $self->loggedin($channel, $hostmask);
    return $user->{lc $key} if $user;
    return undef;
}

1;
