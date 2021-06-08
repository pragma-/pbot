# File: Commands.pm
#
# Author: pragma_
#
# Purpose: Registers commands. Invokes commands with user capability
# validation.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Commands;
use parent 'PBot::Class', 'PBot::Registerable';

use warnings; use strict;
use feature 'unicode_strings';
use utf8;

use Time::Duration qw/duration/;

sub initialize {
    my ($self, %conf) = @_;

    # PBot::Commands can register subrefs
    $self->PBot::Registerable::initialize(%conf);

    # command metadata stored as a HashObject
    $self->{metadata} = PBot::HashObject->new(pbot => $self->{pbot}, name => 'Command metadata', filename => $conf{filename});
    $self->{metadata}->load;

    # register commands to manipulate command metadata and obtain help
    $self->register(sub { $self->cmd_set(@_) },   "cmdset",   1);
    $self->register(sub { $self->cmd_unset(@_) }, "cmdunset", 1);
    $self->register(sub { $self->cmd_help(@_) },  "help",     0);
}

sub cmd_set {
    my ($self, $context) = @_;

    my ($command, $key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);

    if (not defined $command) {
        return "Usage: cmdset <command> [key [value]]";
    }

    return $self->{metadata}->set($command, $key, $value);
}

sub cmd_unset {
    my ($self, $context) = @_;

    my ($command, $key) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (not defined $command or not defined $key) {
        return "Usage: cmdunset <command> <key>";
    }

    return $self->{metadata}->unset($command, $key);
}

sub cmd_help {
    my ($self, $context) = @_;

    if (not length $context->{arguments}) {
        return "For general help, see <https://github.com/pragma-/pbot/tree/master/doc>. For help about a specific command or factoid, use `help <keyword> [channel]`.";
    }

    my $keyword = lc $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    # check built-in commands first
    if ($self->exists($keyword)) {

        # check for command metadata
        if ($self->{metadata}->exists($keyword)) {
            my $name         = $self->{metadata}->get_key_name($keyword);
            my $requires_cap = $self->{metadata}->get_data($keyword, 'requires_cap');
            my $help         = $self->{metadata}->get_data($keyword, 'help');

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
    my @factoids = $self->{pbot}->{factoids}->find_factoid($channel_arg, $keyword, exact_trigger => 1);

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
    my $channel_name = $self->{pbot}->{factoids}->{factoids}->get_key_name($channel);
    my $trigger_name = $self->{pbot}->{factoids}->{factoids}->get_key_name($channel, $trigger);

    # prettify channel name if it's ".*"
    if ($channel_name eq '.*') {
        $channel_name = 'global channel';
    }

    # prettify trigger name with double-quotes if it contains spaces
    if ($trigger_name =~ / /) {
        $trigger_name = "\"$trigger_name\"";
    }

    # get factoid's `help` metadata
    my $help = $self->{pbot}->{factoids}->{factoids}->get_data($channel, $trigger, 'help');

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

sub register {
    my ($self, $subref, $name, $requires_cap) = @_;

    if (not defined $subref or not defined $name) {
        Carp::croak("Missing parameters to Commands::register");
    }

    # register subref
    my $ref = $self->PBot::Registerable::register($subref);

    # update internal metadata
    $ref->{name}         = lc $name;
    $ref->{requires_cap} = $requires_cap // 0;

    # update command metadata
    if (not $self->{metadata}->exists($name)) {
        $self->{metadata}->add($name, { requires_cap => $requires_cap, help => '' }, 1);
    } else {
        # metadata already exists, just update requires_cap unless it's already set.
        if (not defined $self->get_meta($name, 'requires_cap')) {
            $self->{metadata}->set($name, 'requires_cap', $requires_cap, 1);
        }
    }

    # add can-<command> capability to PBot capabilities if required
    if ($requires_cap) {
        $self->{pbot}->{capabilities}->add("can-$name", undef, 1);
    }

    return $ref;
}

sub unregister {
    my ($self, $name) = @_;
    Carp::croak("Missing name parameter to Commands::unregister") if not defined $name;
    $name = lc $name;
    @{$self->{handlers}} = grep { $_->{name} ne $name } @{$self->{handlers}};
}

sub exists {
    my ($self, $keyword) = @_;
    $keyword = lc $keyword;
    foreach my $ref (@{$self->{handlers}}) { return 1 if $ref->{name} eq $keyword; }
    return 0;
}

sub set_meta {
    my ($self, $command, $key, $value, $save) = @_;
    return undef if not $self->{metadata}->exists($command);
    $self->{metadata}->set($command, $key, $value, !$save);
    return 1;
}

sub get_meta {
    my ($self, $command, $key) = @_;
    return $self->{metadata}->get_data($command, $key);
}

# main entry point for PBot::Interpreter to interpret a registered bot command
# see also PBot::Factoids::interpreter() for factoid commands
sub interpreter {
    my ($self, $context) = @_;
    my $result;

    # debug flag to trace $context location and contents
    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("Commands::interpreter\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    my $keyword = lc $context->{keyword};
    my $from    = $context->{from};

    my ($cmd_channel) = $context->{arguments} =~ m/\B(#[^ ]+)/;    # assume command is invoked in regards to first channel-like argument
    $cmd_channel = $from if not defined $cmd_channel;              # otherwise command is invoked in regards to the channel the user is in

    $context->{channel} = $cmd_channel;

    my $user = $self->{pbot}->{users}->find_user($cmd_channel, "$context->{nick}!$context->{user}\@$context->{host}");

    my $cap_override;
    if (exists $context->{'cap-override'}) {
        $self->{pbot}->{logger}->log("Override cap to $context->{'cap-override'}\n");
        $cap_override = $context->{'cap-override'};
    }

    foreach my $ref (@{$self->{handlers}}) {
        if ($ref->{name} eq $keyword) {
            my $requires_cap = $self->get_meta($keyword, 'requires_cap') // $ref->{requires_cap};
            if ($requires_cap) {
                if (defined $cap_override) {
                    if (not $self->{pbot}->{capabilities}->has($cap_override, "can-$keyword")) {
                        return "/msg $context->{nick} The $keyword command requires the can-$keyword capability, which cap-override $cap_override does not have.";
                    }
                } else {
                    if (not defined $user) {
                        my ($found_chan, $found_mask) = $self->{pbot}->{users}->find_user_account($cmd_channel, "$context->{nick}!$context->{user}\@$context->{host}", 1);
                        if   (not defined $found_chan) { return "/msg $context->{nick} You must have a user account to use $keyword. You may use the `my` command to create a personal user account. See `help my`."; }
                        else                           { return "/msg $context->{nick} You must have a user account in $cmd_channel to use $keyword. (You have an account in $found_chan.)"; }
                    } elsif (not $user->{loggedin}) {
                        return "/msg $context->{nick} You must be logged into your user account to use $keyword.";
                    }

                    if (not $self->{pbot}->{capabilities}->userhas($user, "can-$keyword")) {
                        return "/msg $context->{nick} The $keyword command requires the can-$keyword capability, which your user account does not have.";
                    }
                }
            }

            if ($self->get_meta($keyword, 'preserve_whitespace')) {
                $context->{preserve_whitespace} = 1;
            }

            unless ($self->get_meta($keyword, 'dont-replace-pronouns')) {
                $context->{arguments} = $self->{pbot}->{factoids}->expand_factoid_vars($context, $context->{arguments});
                $context->{arglist} = $self->{pbot}->{interpreter}->make_args($context->{arguments});
            }

            $context->{no_nickoverride} = 1;
            if ($self->get_meta($keyword, 'background-process')) {
                my $timeout = $self->get_meta($keyword, 'process-timeout') // $self->{pbot}->{registry}->get_value('processmanager', 'default_timeout');
                $self->{pbot}->{process_manager}->execute_process(
                    $context,
                    sub { $context->{result} = $ref->{subref}->($context) },
                    $timeout
                );
                return "";
            } else {
                my $result = $ref->{subref}->($context);
                return undef if $context->{referenced} and $result =~ m/(?:usage:|no results)/i;
                return $result;
            }
        }
    }
    return undef;
}

1;
