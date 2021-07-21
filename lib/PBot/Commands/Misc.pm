# File: Misc.pm
#
# Purpose: Registers misc PBot commands that don't really belong in any
# other file.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Commands::Misc;

use PBot::Imports;

use Time::Duration qw/duration/;

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

    # misc commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_nop(@_) },        'nop',     0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_uptime(@_) },     'uptime',  0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_in_channel(@_) }, 'in',      0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_list(@_) },       'list',    0);

    # misc administrative commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_sl(@_) },         'sl',      1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_die(@_) },        'die',     1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_export(@_) },     'export',  1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_eval(@_) },       'eval',    1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_reload(@_) },     'reload',  1);

    # misc capabilities
    $self->{pbot}->{capabilities}->add('admin', 'can-in', 1);
}

sub cmd_nop {
    my ($self, $context) = @_;
    $self->{pbot}->{logger}->log("Disregarding NOP command.\n");
    return '';
}

sub cmd_uptime {
    my ($self, $context) = @_;
    return localtime($self->{pbot}->{startup_timestamp}) . ' [' . duration(time - $self->{pbot}->{startup_timestamp}) . ']';
}

sub cmd_in_channel {
    my ($self, $context) = @_;

    my $usage = 'Usage: in <channel> <command>';

    if (not length $context->{arguments}) {
        return $usage;
    }

    my ($channel, $command) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2, 0, 1);

    if (not defined $channel or not defined $command) {
        return $usage;
    }

    # invoker must be present in that channel
    if (not $self->{pbot}->{nicklist}->is_present($channel, $context->{nick})) {
        return "You must be present in $channel to do this.";
    }

    # update context with new channel and command
    $context->{from}    = $channel;
    $context->{command} = $command;

    # perform the command and return the result
    return $self->{pbot}->{interpreter}->interpret($context);
}

sub cmd_list {
    my ($self, $context) = @_;
    my $text;

    my $usage = 'Usage: list <modules|commands>';

    return $usage if not length $context->{arguments};

    if ($context->{arguments} =~ /^modules$/i) {
        $text = 'Loaded modules: ';
        foreach my $channel (sort $self->{pbot}->{factoids}->{storage}->get_keys) {
            foreach my $command (sort $self->{pbot}->{factoids}->{storage}->get_keys($channel)) {
                next if $command eq '_name';
                if ($self->{pbot}->{factoids}->{storage}->get_data($channel, $command, 'type') eq 'module') {
                    $text .= $self->{pbot}->{factoids}->{storage}->get_data($channel, $command, '_name') . ' ';
                }
            }
        }

        return $text;
    }

    if ($context->{arguments} =~ /^commands$/i) {
        $text = 'Registered commands: ';
        foreach my $command (sort { $a->{name} cmp $b->{name} } @{$self->{pbot}->{commands}->{handlers}}) {
            if ($command->{requires_cap}) {
                $text .= "+$command->{name} ";
            } else {
                $text .= "$command->{name} ";
            }
        }

        return $text;
    }

    return $usage;
}

sub cmd_sl {
    my ($self, $context) = @_;
    return "Usage: sl <ircd command>" if not length $context->{arguments};
    $self->{pbot}->{conn}->sl($context->{arguments});
    return "/msg $context->{nick} sl: command sent. See log for result.";
}

sub cmd_die {
    my ($self, $context) = @_;
    $self->{pbot}->{logger}->log("$context->{hostmask} made me exit.\n");
    $self->{pbot}->{conn}->privmsg($context->{from}, "Good-bye.") if $context->{from} ne 'stdin@pbot';
    $self->{pbot}->{conn}->quit("Departure requested.") if defined $self->{pbot}->{conn};
    $self->{pbot}->atexit();
    exit 0;
}

sub cmd_export {
    my ($self, $context) = @_;
    return "Usage: export <factoids>" if not length $context->{arguments};
    if ($context->{arguments} =~ /^factoids$/i) { return $self->{pbot}->{factoids}->export_factoids; }
}

sub cmd_eval {
    my ($self, $context) = @_;

    $self->{pbot}->{logger}->log("eval: $context->{from} $context->{hostmask} evaluating `$context->{arguments}`\n");

    my $ret    = '';
    my $result = eval $context->{arguments};
    if ($@) {
        if   (length $result) { $ret .= "[Error: $@] "; }
        else                  { $ret .= "Error: $@"; }
        $ret =~ s/ at \(eval \d+\) line 1.//;
    }
    $result = 'Undefined.' if not defined $result;
    $result = 'No output.' if not length $result;
    return "/say $ret $result";
}

sub cmd_reload {
    my ($self, $context) = @_;

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
            $self->{pbot}->{antiflood}->{'ban-exemptions'}->load;
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
            $self->{pbot}->{factoids}->load_factoids;
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
