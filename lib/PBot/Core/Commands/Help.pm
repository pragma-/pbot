# File: Help.pm
#
# Purpose: Registers `help` command.

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Help;

use PBot::Imports;
use parent 'PBot::Core::Class';

sub initialize($self, %conf) {
    $self->{pbot}->{commands}->register(sub { $self->cmd_help(@_) }, 'help');
}

sub cmd_help($self, $context) {
    if (not length $context->{arguments}) {
        return "For general help, see <https://github.com/pragma-/pbot/tree/master/doc#table-of-contents>. For help about a specific command or factoid, use `help <keyword> [channel]`.";
    }

    my $keyword = lc $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    # check built-in commands first
    if ($self->{pbot}->{commands}->exists($keyword)) {

        # check for command metadata
        if ($self->{pbot}->{commands}->{metadata}->exists($keyword)) {
            my $name         = $self->{pbot}->{commands}->{metadata}->get_key_name($keyword);
            my $requires_cap = $self->{pbot}->{commands}->{metadata}->get_data($keyword, 'requires_cap');
            my $help         = $self->{pbot}->{commands}->{metadata}->get_data($keyword, 'help');

            my $result = "/say $name: ";

            # prefix help text with required capability
            if ($requires_cap) {
                $result .= "[Requires can-$keyword] ";
            }

            if (not defined $help or not length $help) {
                $result .= "I have no help text for this command yet. To add help text, use the command `cmdset $keyword help <text>`.";
            } else {
                $result .= $help;
            }

            return $result;
        }

        # no command metadata available
        return "$keyword is a built-in command, but I have no help for it yet.";
    }

    # then factoids
    my $channel_arg = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    if (not defined $channel_arg or not length $channel_arg) {
        # set channel argument to from if no argument was passed
        $channel_arg = $context->{from};
    }

    if ($channel_arg !~ /^#/) {
        # set channel argument to global if it's not channel-like
        $channel_arg = '.*';
    }

    # find factoids
    my @factoids = $self->{pbot}->{factoids}->{data}->find($channel_arg, $keyword, exact_trigger => 1);

    if (not @factoids or not $factoids[0]) {
        # nothing found
        return "I don't know anything about $keyword.";
    }

    my ($channel, $trigger);

    if (@factoids > 1) {
        # ask to disambiguate factoids if found in multiple channels
        if (not grep { $_->[0] eq $channel_arg } @factoids) {
            return
                "/say $keyword found in multiple channels: "
              . (join ', ', sort map { $_->[0] eq '.*' ? 'global' : $_->[0] } @factoids)
              . "; use `help $keyword <channel>` to disambiguate.";
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

    # get canonical channel and trigger names with original typographical casing
    my $channel_name = $self->{pbot}->{factoids}->{data}->{storage}->get_key_name($channel);
    my $trigger_name = $self->{pbot}->{factoids}->{data}->{storage}->get_key_name($channel, $trigger);

    # prettify channel name if it's ".*"
    if ($channel_name eq '.*') {
        $channel_name = 'global channel';
    }

    # prettify trigger name with double-quotes if it contains spaces
    if ($trigger_name =~ / /) {
        $trigger_name = "\"$trigger_name\"";
    }

    # get factoid's `help` metadata
    my $help = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $trigger, 'help');

    # return immediately if no help text
    if (not defined $help or not length $help) {
        return "/say $trigger_name is a factoid for $channel_name, but I have no help text for it yet."
           . " To add help text, use the command `factset $trigger_name help <text>`.";
    }

    my $result = "/say ";

    # if factoid doesn't belong to invoked or global channel,
    # then prefix with the factoid's channel name.
    if ($channel ne $context->{from} and $channel ne '.*') {
        $result .= "[$channel_name] ";
    }

    $result .= "$trigger_name: $help";

    return $result;
}

1;
