# File: Capabilities.pm
#
# Purpose: Registers the capabilities `cap` command.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Commands::Capabilities;

use PBot::Imports;

sub new {
    my ($class, %args) = @_;

    # ensure class was passed a PBot instance
    if (not exists $args{pbot}) {
        Carp::croak("Missing pbot reference to $class");
    }

    my $self = bless { pbot => $args{pbot} }, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->register(sub { $self->cmd_cap(@_) }, "cap");
}

sub cmd_cap {
    my ($self, $context) = @_;

    my $command = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    given ($command) {
        when ('list') {
            my $cap = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});
            return $self->{pbot}->{capabilities}->list($cap);
        }

        when ('whohas') {
            my $cap = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

            if (not defined $cap) {
                return "Usage: cap whohas <capability>; Lists all users who have <capability>";
            }

            if (not $self->{pbot}->{capabilities}->exists($cap)) {
                return "No such capability $cap.";
            }

            my $result   = "Users with capability $cap: ";
            my $users = $self->{pbot}->{users}->{storage};
            my @matches;

            foreach my $name (sort $users->get_keys) {
                my $u = $users->get_data($name);

                if ($self->{pbot}->{capabilities}->userhas($u, $cap)) {
                    push @matches, $users->get_key_name($name);
                }
            }

            if (@matches) {
                $result .= join(', ', @matches);
            } else {
                $result .= 'nobody';
            }

            return $result;
        }

        when ('userhas') {
            my ($name, $cap) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

            if (not defined $name) {
                return "Usage: cap userhas <username> [capability]; Lists capabilities belonging to <user>";
            }

            $cap = lc $cap if defined $cap;

            my $u = $self->{pbot}->{users}->{storage}->get_data($name);

            if (not defined $u) {
                return "No such user $name.";
            }

            $name = $self->{pbot}->{users}->{storage}->get_key_name($name);

            if (defined $cap) {
                if (not $self->{pbot}->{capabilities}->exists($cap)) {
                    return "Try again. No such capability $cap.";
                }

                if ($self->{pbot}->{capabilities}->userhas($u, $cap)) {
                    return "Yes. User $name has capability $cap.";
                } else {
                    return "No. User $name  does not have capability $cap.";
                }
            } else {
                my @groups;
                my @single;

                foreach my $key (sort keys %{$u}) {
                    next if $key eq '_name';          # skip internal cached metadata
                    next if not $self->{pbot}->{capabilities}->exists($key);  # skip metadata that isn't a capability

                    my $count = $self->{pbot}->{capabilities}->{caps}->get_keys;

                    if ($count > 0) {
                        push @groups, "$key ($count cap" . ($count == 1 ? '' : 's') . ")";
                    } else {
                        push @single, $key;
                    }
                }

                if (@groups or @single) {
                    # first list all capabilities that have sub-capabilities (i.e. grouped capabilities)
                    # then list stand-alone (single) capabilities
                    return "User $name has capabilities: " . join ', ', @groups, @single;
                } else {
                    return "User $name has no capabilities.";
                }
            }
        }

        when ('group') {
            my ($cap, $subcaps) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

            if (not defined $cap or not defined $subcaps) {
                return "Usage: cap group <existing or new capability> <existing capabilities...>";
            }

            my $u = $self->{pbot}->{users}->loggedin($context->{from}, $context->{hostmask});

            if (not defined $u) {
                return "You must be logged into your user account to group capabilities together.";
            }

            if (not $self->{pbot}->{capabilities}->userhas($u, 'can-group-capabilities')) {
                return "You must have the can-group-capabilities capability to group capabilities together.";
            }

            my @caps = split /\s+|,\s*/, $subcaps; # split by spaces or comma

            foreach my $c (@caps) {
                if (not $self->{pbot}->{capabilities}->exists($c)) {
                    return "No such capability $c.";
                }

                if (lc $cap eq lc $c) {
                    return "You cannot group a capability with itself.";
                }

                $self->{pbot}->{capabilities}->add($cap, $c);
            }

            if (@caps > 1) {
                return "Capabilities " . join(', ', @caps) . " added to the $cap capability group.";
            } else {
                return "Capability $subcaps added to the $cap capability group.";
            }
        }

        when ('ungroup') {
            my ($cap, $subcaps) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

            if (not defined $cap or not defined $subcaps) {
                return "Usage: cap ungroup <existing capability group> <grouped capabilities...>";
            }

            if (not $self->{pbot}->{capabilities}->exists($cap)) {
                return "No such capability $cap.";
            }

            my $u = $self->{pbot}->{users}->loggedin($context->{from}, $context->{hostmask});

            if (not defined $u) {
                return "You must be logged into your user account to remove capabilities from groups.";
            }

            if (not $self->{pbot}->{capabilities}->userhas($u, 'can-group-capabilities')) {
                return "You must have the can-group-capabilities capability to remove capabilities from groups.";
            }

            my @caps = split /\s+|,\s*/, $subcaps; # split by spaces or comma

            foreach my $c (@caps) {
                if (not $self->{pbot}->{capabilities}->exists($c)) {
                    return "No such capability $c.";
                }

                if (not $self->{pbot}->{capabilities}->has($cap, $c)) {
                    return "Capability $c does not belong to the $cap capability group.";
                }

                $self->{pbot}->{capabilities}->remove($cap, $c);
            }

            if (@caps > 1) {
                return "Capabilities " . join(', ', @caps) . " removed from the $cap capability group.";
            } else {
                return "Capability $subcaps removed from the $cap capability group.";
            }
        }

        default {
            return "Usage: cap list [capability] | cap group <existing or new capability group> <existing capabilities...> "
                . "| cap ungroup <existing capability group> <grouped capabilities...> | cap userhas <user> [capability] "
                . "| cap whohas <capability>";
        }
    }
}

1;
