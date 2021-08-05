# File: RunCommand.pm
#
# Purpose: Runs a system command, streaming each line of output in real-time.
#
# WARNING: The `runcmd` command will allow a user to run any command on your
# system. Do not give out the `can-runcmd` capability to anyone you do not
# absolutely trust 100%. Instead, make a locked-down factoid; i.e.:
#
#   factalias ls runcmd ls $args
#   factset ls cap-override can-runcmd
#   factset ls locked 1
#
# The above will create an `ls` alias that can only run `runcmd ls $args` and
# cannot be modified by anybody. The cap-override is necessary so the factoid
# itself has permission to use `runcmd` regardless of whether the user has the
# `can-runcmd` capability.
#
# This plugin is not in data/plugin_autoload. Load at your own risk.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::RunCommand;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use IPC::Run qw/start pump finish/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->add(
        name => 'runcmd',
        help => 'Executes a system command and outputs each line in real-time',
        requires_cap => 1,
        subref => sub { $self->cmd_runcmd(@_) },
    );
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->remove('runcmd');
}

sub cmd_runcmd {
    my ($self, $context) = @_;

    my @args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);

    my ($in, $out, $err);

    my $h = start \@args, \$in, \$out, \$err;

    my $lines = 0;

    while (pump $h) {
        $lines += $self->send_lines($context, \$out);
    }

    finish $h;

    $lines += $self->send_lines($context, \$out);

    return "No output." if not $lines;
}

sub send_lines {
    my ($self, $context, $buffer) = @_;

    my ($line, $lines);

    while ($$buffer =~ s/(.{1,370})//) {
        $line = $1;
        $line =~ s/^\s+|\s+$//g;

        if (length $line) {
            $self->{pbot}->{conn}->privmsg($context->{from}, $line);
            $lines++;
        }
    }

    return $lines;
}

1;
