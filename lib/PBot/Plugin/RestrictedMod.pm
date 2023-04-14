# File: RestrictedMod.pm
#
# Purpose: Provides restricted moderation abilities to voiced users.
# They are allowed to ban/mute/kick only users that are not admins,
# whitelisted, or autoop/autovoice. This is useful for, e.g., IRCnet
# configurations where +v users are recognized as "semi-trusted" in
# order to provide assistance in combating heavy spam and drone traffic.

# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::RestrictedMod;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Storable qw/dclone/;

sub initialize($self, %conf) {
    $self->{pbot}->{commands}->add(
        name   => 'mod',
        help   => 'Provides restricted moderation abilities to voiced users. They can kick/ban/etc only users that are not admins, whitelisted, voiced or opped.',
        subref => sub { $self->cmd_mod(@_) },
    );

    $self->{pbot}->{capabilities}->add('chanmod', 'can-mod',     1);
    $self->{pbot}->{capabilities}->add('chanmod', 'can-voice',   1);
    $self->{pbot}->{capabilities}->add('chanmod', 'can-devoice', 1);

    $self->{commands} = {
        'help'   => {subref => sub { $self->help(@_) },   help => "Provides help about this command. Usage: mod help <mod command>; see also: mod help list"},
        'list'   => {subref => sub { $self->list(@_) },   help => "Lists available mod commands. Usage: mod list"},
        'kick'   => {subref => sub { $self->kick(@_) },   help => "Kicks a nick from the channel. Usage: mod kick <nick>"},
        'ban'    => {subref => sub { $self->ban(@_) },    help => "Bans a nick from the channel. Cannot be used to set a custom banmask. Usage: mod ban <nick>"},
        'mute'   => {subref => sub { $self->mute(@_) },   help => "Mutes a nick in the channel. Usage: mod mute <nick>"},
        'unban'  => {subref => sub { $self->unban(@_) },  help => "Removes bans set by moderators. Cannot remove any other types of bans. Usage: mod unban <nick or mask>"},
        'unmute' => {subref => sub { $self->unmute(@_) }, help => "Removes mutes set by moderators. Cannot remove any other types of mutes. Usage: mod unmute <nick or mask>"},
        'kb'     => {subref => sub { $self->kb(@_) },     help => "Kickbans a nick from the channel. Cannot be used to set a custom banmask. Usage: mod kb <nick>"},
    };
}

sub unload($self) {
    $self->{pbot}->{commands}->remove('mod');
    $self->{pbot}->{capabilities}->remove('chanmod');
}

sub help($self, $context) {
    my $command = $self->{pbot}->{interpreter}->shift_arg($context->{arglist}) // 'help';

    if (exists $self->{commands}->{$command}) {
        return $self->{commands}->{$command}->{help};
    } else {
        return "No such mod command '$command'. I can't help you with that.";
    }
}

sub list($self, $context) {
    return "Available mod commands: " . join ', ', sort keys %{$self->{commands}};
}

sub generic_command($self, $context, $command) {
    my $channel = $context->{from};
    if ($channel !~ m/^#/) {
        $channel = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

        if (not defined $channel or $channel !~ /^#/) { return "Must specify channel from private message. Usage: mod $command <channel> <nick>"; }
    }

    return "I do not have OPs for this channel. I cannot do any moderation here." if not $self->{pbot}->{chanops}->can_gain_ops($channel);
    return "Voiced moderation is not enabled for this channel. Use `regset $channel.restrictedmod 1` to enable."
      if not $self->{pbot}->{registry}->get_value($channel, 'restrictedmod');

    my $hostmask = $context->{hostmask};
    my $user     = $self->{pbot}->{users}->loggedin($channel, $hostmask) // {admin => 0, chanmod => 0};
    my $voiced   = $self->{pbot}->{nicklist}->get_meta($channel, $context->{nick}, '+v');

    if (not $voiced and not $self->{pbot}->{capabilities}->userhas($user, 'admin') and not $self->{pbot}->{capabilities}->userhas($user, 'chanmod')) {
        return "You must be voiced (usermode +v) or have the admin or chanmod capability to use this command.";
    }

    my $target = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});
    return "Missing target. Usage: mod $command <nick>" if not defined $target;

    if ($command eq 'unban') {
        my $reason = $self->{pbot}->{banlist}->checkban($channel, 'b', $target);
        if ($reason =~ m/moderator ban/) {
            $self->{pbot}->{banlist}->unban_user($channel, 'b', $target, 1);
            return "";
        } else {
            return "I don't think so. That ban was not set by a moderator.";
        }
    } elsif ($command eq 'unmute') {
        my $reason = $self->{pbot}->{banlist}->checkban($channel, 'q', $target);
        if ($reason =~ m/moderator mute/) {
            $self->{pbot}->{banlist}->unban_user($channel, 'q', $target, 1);
            return "";
        } else {
            return "I don't think so. That mute was not set by a moderator.";
        }
    }

    my $target_nicklist;
    if   (not $self->{pbot}->{nicklist}->is_present($channel, $target)) { return "$context->{nick}: I do not see anybody named $target in this channel."; }
    else                                                                { $target_nicklist = $self->{pbot}->{nicklist}->{nicklist}->{lc $channel}->{lc $target}; }

    my $target_user = $self->{pbot}->{users}->loggedin($channel, $target_nicklist->{hostmask});

    if (   (defined $target_user and $target_user->{autoop} or $target_user->{autovoice})
        or $target_nicklist->{'+v'}
        or $target_nicklist->{'+o'}
        or $self->{pbot}->{capabilities}->userhas($target_user, 'is-whitelisted'))
    {
        return "I don't think so.";
    }

    if ($command eq 'kick') {
        $self->{pbot}->{chanops}->add_op_command($channel, "kick $channel $target Have a nice day!");
        $self->{pbot}->{chanops}->gain_ops($channel);
    } elsif ($command eq 'ban') {
        $self->{pbot}->{banlist}->ban_user_timed(
            $channel,
            'b',
            $target,
            3600 * 24,
            "$context->{nick}!$context->{user}\@$context->{host}",
            "doing something naughty (moderator ban)",
            1
        );
    } elsif ($command eq 'mute') {
        $self->{pbot}->{banlist}->ban_user_timed(
            $channel,
            'q',
            $target,
            3600 * 24,
            "$context->{nick}!$context->{user}\@$context->{host}",
            "doing something naughty (moderator mute)",
            1
        );
    }
    return "";
}

sub kick($self, $context) {
    return $self->generic_command($context, 'kick');
}

sub ban($self, $context) {
    return $self->generic_command($context, 'ban');
}

sub mute($self, $context) {
    return $self->generic_command($context, 'mute');
}

sub unban($self, $context) {
    return $self->generic_command($context, 'unban');
}

sub unmute($self, $context) {
    return $self->generic_command($context, 'unmute');
}

sub kb($self, $context) {
    my $result = $self->ban(dclone $context);    # note: using copy of $context to preserve $context->{arglist} for $self->kick($context)
    return $result if length $result;
    return $self->kick($context);
}

sub cmd_mod($self, $context) {
    my $command = $self->{pbot}->{interpreter}->shift_arg($context->{arglist}) // '';
    $command = lc $command;

    if (grep { $_ eq $command } keys %{$self->{commands}}) {
        return $self->{commands}->{$command}->{subref}->($context);
    } else {
        my $commands = join ', ', sort keys %{$self->{commands}};
        if   ($context->{from} !~ m/^#/) {
            return "Usage: mod <channel> <command> [arguments]; commands are: $commands; see `mod help <command>` for more information.";
        } else {
            return "Usage: mod <command> [arguments]; commands are: $commands; see `mod help <command>` for more information.";
        }
    }
}

1;
