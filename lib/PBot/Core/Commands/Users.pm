# File: Users.pm
#
# Purpose: Commands to manage list of bot users/admins and their metadata.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Users;

use PBot::Imports;
use parent 'PBot::Core::Class';

sub initialize {
    my ($self, %conf) = @_;

    # register commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_login(@_) },     "login",     0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_logout(@_) },    "logout",    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_useradd(@_) },   "useradd",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_userdel(@_) },   "userdel",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_usershow(@_) },  "usershow",  0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_userset(@_) },   "userset",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_userunset(@_) }, "userunset", 1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_users(@_) },     "users",     0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_my(@_) },        "my",        0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_id(@_) },        "id",        0);

    # add capabilities to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-useradd',   1);
    $self->{pbot}->{capabilities}->add('admin', 'can-userdel',   1);
    $self->{pbot}->{capabilities}->add('admin', 'can-userset',   1);
    $self->{pbot}->{capabilities}->add('admin', 'can-userunset', 1);

    # create capability (it will get added to botowner group when Core is done loading)
    $self->{pbot}->{capabilities}->add('can-modify-admins', undef, 1);
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

    my ($user_channel, $user_hostmask) = $self->{pbot}->{users}->find_user_account($channel, $context->{hostmask});
    return "/msg $context->{nick} You do not have a user account. You may use the `my` command to create a personal user account. See `help my`." if not defined $user_channel;

    my $name = $self->{pbot}->{users}->{user_index}->{$user_channel}->{$user_hostmask};

    my $u            = $self->{pbot}->{users}->{storage}->get_data($name);
    my $channel_text = $user_channel eq 'global' ? '' : " for $user_channel";

    if ($u->{loggedin}) {
        return "/msg $context->{nick} You are already logged into " . $self->{pbot}->{users}->{storage}->get_key_name($name) . " ($user_hostmask)$channel_text.";
    }

    my $result = $self->{pbot}->{users}->login($user_channel, $user_hostmask, $arguments);
    return "/msg $context->{nick} $result";
}

sub cmd_logout {
    my ($self, $context) = @_;
    $context->{from} = $context->{arguments} if length $context->{arguments};
    my ($user_channel, $user_hostmask) = $self->{pbot}->{users}->find_user_account($context->{from}, $context->{hostmask});
    return "/msg $context->{nick} You do not have a user account. You may use the `my` command to create a personal user account. See `help my`." if not defined $user_channel;

    my $name = $self->{pbot}->{users}->{user_index}->{$user_channel}->{$user_hostmask};

    my $u            = $self->{pbot}->{users}->{storage}->get_data($name);
    my $channel_text = $user_channel eq 'global' ? '' : " for $user_channel";
    return "/msg $context->{nick} You are not logged into " . $self->{pbot}->{users}->{storage}->get_key_name($name) . " ($user_hostmask)$channel_text." if not $u->{loggedin};

    $self->{pbot}->{users}->logout($user_channel, $user_hostmask);
    return "/msg $context->{nick} Logged out of " . $self->{pbot}->{users}->{storage}->get_key_name($name) . " ($user_hostmask)$channel_text.";
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
    foreach my $chan (sort keys %{$self->{pbot}->{users}->{user_index}}) {
        next if $context->{from} =~ m/^#/ and $chan ne $channel and $chan ne $include_global;
        next if $context->{from} !~ m/^#/ and $channel =~ m/^#/ and $chan ne $channel;

        if ($last_channel ne $chan) {
            $text .= "$sep$chan: ";
            $last_channel = $chan;
            $sep          = "";
        }

        my %seen_names;

        foreach my $hostmask (
            sort { $self->{pbot}->{users}->{user_index}->{$chan}->{$a} cmp $self->{pbot}->{users}->{user_index}->{$chan}->{$b} }
            keys %{$self->{pbot}->{users}->{user_index}->{$chan}}
        )
        {
            my $name = $self->{pbot}->{users}->{user_index}->{$chan}->{$hostmask};
            next if $seen_names{$name};
            $seen_names{$name} = 1;
            $text .= $sep;
            my $has_cap = 0;
            foreach my $key ($self->{pbot}->{users}->{storage}->get_keys($name)) {
                if ($self->{pbot}->{capabilities}->exists($key)) {
                    $has_cap = 1;
                    last;
                }
            }
            $text .= '+' if $has_cap;
            $text .= $self->{pbot}->{users}->{storage}->get_key_name($name);
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

    $channels = 'global' if !$channels or $channels !~ /^#/;

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

    my $u = $self->{pbot}->{users}->find_user($context->{from}, $context->{hostmask});
    my $t = $self->{pbot}->{users}->{storage}->get_data($context->{arguments});

    if ($self->{pbot}->{capabilities}->userhas($t, 'botowner') and not $self->{pbot}->{capabilities}->userhas($u, 'botowner')) {
        return "Only botowners may delete botowner user accounts.";
    }

    if ($self->{pbot}->{capabilities}->userhas($t, 'admin') and not $self->{pbot}->{capabilities}->userhas($u, 'can-modify-admins')) {
        return "To delete admin user accounts your user account must have the can-modify-admins capability.";
    }

    return $self->{pbot}->{users}->remove_user($context->{arguments});
}

sub cmd_usershow {
    my ($self, $context) = @_;

    my ($name, $key) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (not defined $name) { return "Usage: usershow <username> [key]"; }

    my $channel = $context->{from};

    my $target = $self->{pbot}->{users}->{storage}->get_data($name);

    if (not $target) {
        return "There is no user account $name.";
    }

    if (lc $key eq 'password') {
        return "I don't think so.";
    }

    my $result = $self->{pbot}->{users}->{storage}->set($name, $key, undef);
    $result =~ s/^password: .*;?$/password: <private>;/m;
    return $result;
}

sub cmd_userset {
    my ($self, $context) = @_;

    my ($name, $key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    if (not defined $name) { return "Usage: userset <username> [key [value]]"; }

    my $channel = $context->{from};

    my $u      = $self->{pbot}->{users}->find_user($channel, $context->{hostmask}, 1);
    my $target = $self->{pbot}->{users}->{storage}->get_data($name);

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

    my $result = $self->{pbot}->{users}->{storage}->set($name, $key, $value);
    $result =~ s/^password: .*;?$/password: <private>;/m;

    if (defined $key and ($key eq 'channels' or $key eq 'hostmasks') and defined $value) {
        $self->{pbot}->{users}->rebuild_user_index;
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

    my $u      = $self->{pbot}->{users}->find_user($channel, $context->{hostmask}, 1);
    my $target = $self->{pbot}->{users}->{storage}->get_data($name);

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

    return $self->{pbot}->{users}->{storage}->unset($name, $key);
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

    my ($u, $name) = $self->{pbot}->{users}->find_user($channel, $hostmask, 1);

    if (not $u) {
        $channel  = 'global';
        $hostmask = "$context->{nick}!$context->{user}\@" . $self->{pbot}->{antiflood}->address_to_mask($context->{host});
        $name = $context->{nick};

        $u = $self->{pbot}->{users}->{storage}->get_data($name);
        if ($u) {
            $self->{pbot}->{logger}->log("Adding additional hostmask $hostmask to user account $name\n");
            $u->{hostmasks} .= ",$hostmask";
            $self->{pbot}->{users}->rebuild_user_index;
        } else {
            $u                 = $self->{pbot}->{users}->add_user($name, $channel, $hostmask, undef, undef, 1);
            $u->{loggedin}     = 1;
            $u->{stayloggedin} = 1;
            $u->{autologin}    = 1;
            $self->{pbot}->{users}->save;
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

    $result .= $self->{pbot}->{users}->{storage}->set($name, $key, $value);
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
    } elsif ($target =~ m/[!@]/) {
        my @accounts = $self->{pbot}->{messagehistory}->{database}->find_message_accounts_by_mask($target, 20);

        my %seen;
        @accounts = grep !$seen{$_}++, @accounts;

        if (not @accounts) {
            return "I don't know anybody matching hostmask $target.";
        } elsif (@accounts > 1) {
            # found more than one account, list them
            my @hostmasks;

            foreach my $account (@accounts) {
                my $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($account);
                push @hostmasks, "$hostmask ($account)";
            }

            return "Found multiple accounts: " . (join ', ', sort @hostmasks);
        } else {
            # found just one account, we'll use it
            $message_account = $accounts[0];
            $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($accounts[0]);
        }
    } else {
        ($message_account, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($target);
        return "I don't know anybody named $target." if not $message_account;
    }

    my $ancestor_id = $self->{pbot}->{messagehistory}->{database}->get_ancestor_id($message_account);
    my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($message_account);

    my ($u, $name) = $self->{pbot}->{users}->find_user($context->{from}, $hostmask, 1);

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

1;
