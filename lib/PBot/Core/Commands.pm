# File: Commands.pm
#
# Purpose: Registers commands. Invokes commands with user capability
# validation.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands;
use parent 'PBot::Core::Class', 'PBot::Core::Registerable';

use PBot::Imports;

use PBot::Utils::LoadPackages qw/load_packages/;

sub initialize {
    my ($self, %conf) = @_;

    # PBot::Core::Commands can register subrefs
    $self->PBot::Core::Registerable::initialize(%conf);

    # command metadata stored as a HashObject
    $self->{metadata} = PBot::Storage::HashObject->new(pbot => $self->{pbot}, name => 'Command metadata', filename => $conf{filename});
    $self->{metadata}->load;
}

sub register_commands {
    my ($self) = @_;

    # register commands in Commands directory
    $self->{pbot}->{logger}->log("Registering commands:\n");
    load_packages($self, 'PBot::Core::Commands');
}

sub register {
    my ($self, $subref, $name, $requires_cap) = @_;

    if (not defined $subref or not defined $name) {
        Carp::croak("Missing parameters to Commands::register");
    }

    # register subref
    my $command = $self->PBot::Core::Registerable::register($subref);

    # update internal metadata
    $command->{name}         = lc $name;
    $command->{requires_cap} = $requires_cap // 0;

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

    return $command;
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
    foreach my $command (@{$self->{handlers}}) { return 1 if $command->{name} eq $keyword; }
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

# main entry point for PBot::Core::Interpreter to interpret a registered bot command
# see also PBot::Core::Factoids::interpreter() for factoid commands
sub interpreter {
    my ($self, $context) = @_;

    # debug flag to trace $context location and contents
    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("Commands::interpreter\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    # some convenient aliases
    my $keyword = lc $context->{keyword};
    my $from    = $context->{from};

    # set the channel the command is in reference to
    my ($cmd_channel) = $context->{arguments} =~ m/\B(#[^ ]+)/;    # assume command is invoked in regards to first channel-like argument
    $cmd_channel = $from if not defined $cmd_channel;              # otherwise command is invoked in regards to the channel the user is in

    $context->{channel} = $cmd_channel;

    # get the user's bot account
    my $user = $self->{pbot}->{users}->find_user($cmd_channel, $context->{hostmask});

    # check for a capability override
    my $cap_override;

    if (exists $context->{'cap-override'}) {
        $self->{pbot}->{logger}->log("Override cap to $context->{'cap-override'}\n");
        $cap_override = $context->{'cap-override'};
    }

    # go through all commands
    # TODO: maybe use a hash lookup
    foreach my $command (@{$self->{handlers}}) {

        # is this the command
        if ($command->{name} eq $keyword) {

            # does this command require capabilities
            my $requires_cap = $self->get_meta($keyword, 'requires_cap') // $command->{requires_cap};

            if ($requires_cap) {
                if (defined $cap_override) {
                    if (not $self->{pbot}->{capabilities}->has($cap_override, "can-$keyword")) {
                        return "/msg $context->{nick} The $keyword command requires the can-$keyword capability, which cap-override $cap_override does not have.";
                    }
                } else {
                    if (not defined $user) {
                        my ($found_chan, $found_mask) = $self->{pbot}->{users}->find_user_account($cmd_channel, $context->{hostmask}, 1);

                        if (not defined $found_chan) {
                            return "/msg $context->{nick} You must have a user account to use $keyword. You may use the `my` command to create a personal user account. See `help my`.";
                        } else {
                            return "/msg $context->{nick} You must have a user account in $cmd_channel to use $keyword. (You have an account in $found_chan.)";
                        }
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
                $context->{arglist}   = $self->{pbot}->{interpreter}->make_args($context->{arguments});
            }

            #            $self->{pbot}->{logger}->log("Disabling nickprefix\n");
            #$context->{nickprefix_disabled} = 1;

            if ($self->get_meta($keyword, 'background-process')) {
                # execute this command as a backgrounded process

                # set timeout to command metadata value
                my $timeout = $self->get_meta($keyword, 'process-timeout');

                # otherwise set timeout to default value
                $timeout //= $self->{pbot}->{registry}->get_value('processmanager', 'default_timeout');

                # execute command in background
                $self->{pbot}->{process_manager}->execute_process(
                    $context,
                    sub { $context->{result} = $command->{subref}->($context) },
                    $timeout,
                );

                # return no output since it will be handled by process manager
                return '';
            } else {
                # execute this command normally
                my $result = $command->{subref}->($context);

                # disregard undesired command output if command is embedded
                return undef if $context->{referenced} and $result =~ m/(?:usage:|no results)/i;

                # return command output
                return $result;
            }
        }
    }

    return undef;
}

1;
