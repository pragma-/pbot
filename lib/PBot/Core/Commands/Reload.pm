# File: Reload.pm
#
# Purpose: Command to reload various PBot storage files.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Reload;

use PBot::Imports;
use parent 'PBot::Core::Class';

sub initialize($self, %conf) {
    $self->{pbot}->{commands}->register(sub { $self->cmd_reload(@_) }, 'reload',  1);
}

sub cmd_reload($self, $context) {
    my %reloadables = (
        'capabilities' => sub {
            $self->{pbot}->{capabilities}->{caps}->load;
            return "Capabilities reloaded.";
        },

        'commands' => sub {
            $self->{pbot}->{commands}->{metadata}->load;
            return "Commands metadata reloaded.";
        },

        'blacklist' => sub {
            $self->{pbot}->{blacklist}->clear_blacklist;
            $self->{pbot}->{blacklist}->load_blacklist;
            return "Blacklist reloaded.";
        },

        'ban-exemptions' => sub {
            $self->{pbot}->{banlist}->{'ban-exemptions'}->load;
            return "Ban exemptions reloaded.";
        },

        'ignores' => sub {
            $self->{pbot}->{ignorelist}->{storage}->load;
            return "Ignore list reloaded.";
        },

        'users' => sub {
            $self->{pbot}->{users}->load;
            return "Users reloaded.";
        },

        'channels' => sub {
            $self->{pbot}->{channels}->{storage}->load;
            return "Channels reloaded.";
        },

        'banlist' => sub {
            $self->{pbot}->{event_queue}->dequeue_event('unban #.*');
            $self->{pbot}->{event_queue}->dequeue_event('unmute #.*');
            $self->{pbot}->{banlist}->{banlist}->load;
            $self->{pbot}->{banlist}->{quietlist}->load;
            $self->{pbot}->{banlist}->enqueue_timeouts($self->{pbot}->{banlist}->{banlist},   'b');
            $self->{pbot}->{banlist}->enqueue_timeouts($self->{pbot}->{banlist}->{quietlist}, 'q');
            return "Ban list reloaded.";
        },

        'registry' => sub {
            $self->{pbot}->{registry}->load;
            return "Registry reloaded.";
        },

        'factoids' => sub {
            $self->{pbot}->{factoids}->{data}->load;
            return "Factoids reloaded.";
        }
    );

    if (not length $context->{arguments} or not exists $reloadables{$context->{arguments}}) {
        my $usage = 'Usage: reload <';
        $usage .= join '|', sort keys %reloadables;
        $usage .= '>';
        return $usage;
    }

    return $reloadables{$context->{arguments}}();
}

1;
