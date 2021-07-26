# File: RunCommand.pm
#
# Purpose: Runs a system command, streaming each line of output in real-time.
#
# WARNING: The `runcmd` command will allow a user to run any command on your
# system. Do not give out the `can-runcmd` capability to anyone you do not
# absolutely trust 100%.
#
# Consider instead making a locked-down factalias; i.e.:
#
#   factalias ls runcmd ls $args
#   factset ls cap-override can-runcmd
#   factset ls locked 1
#
# The above will create an `ls` alias that can only run `runcmd ls $args` and
# cannot be modified by anybody. The cap-override is necessary so the alias
# itself has permission to use `runcmd` regardless of whether the user has the
# `can-runcmd` capability.


# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::RunCommand;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use IPC::Run qw/start pump/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->register(sub { $self->cmd_runcmd(@_) }, "runcmd", 1);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("runcmd");
}

sub cmd_runcmd {
    my ($self, $context) = @_;

    my @args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);

    my ($in, $out, $err);

    my $h = start \@args, \$in, \$out, \$err;

    my $lines = 0;

    while (pump $h) {
        if ($out =~ s/^(.*?)\n//) {
            $self->{pbot}->{conn}->privmsg($context->{from}, $1);
            $lines++;
        }
    }

    finish $h;

    if (length $out) {
        my @lines = split /\n/, $out;

        foreach my $line (@lines) {
            $self->{pbot}->{conn}->privmsg($context->{from}, $line);
            $lines++;
        }
    }

    return "No output." if not $lines;
}

1;
