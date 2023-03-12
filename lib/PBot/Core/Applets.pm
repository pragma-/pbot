# File: Applets.pm
#
# Purpose: Applets are command-line programs and scripts that can be loaded
# via PBot factoids. Command arguments are passed as command-line arguments.
# The standard output from the script is returned as the bot command result.
# The standard error output is stored in a file named <applet>-stderr in the
# applets/ directory.

# SPDX-FileCopyrightText: 2007-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Applets;
use parent 'PBot::Core::Class';

use PBot::Imports;

use IPC::Run qw/run timeout/;
use Encode;

sub initialize {
    # nothing to do here
}

sub execute_applet {
    my ($self, $context) = @_;

    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("execute_applet\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    $self->{pbot}->{process_manager}->execute_process($context, sub { $self->launch_applet(@_) });
}

sub launch_applet {
    my ($self, $context) = @_;

    $context->{arguments} //= '';

    my @factoids = $self->{pbot}->{factoids}->{data}->find($context->{from}, $context->{keyword}, exact_channel => 2, exact_trigger => 2);

    if (not @factoids or not $factoids[0]) {
        $context->{checkflood} = 1;
        $self->{pbot}->{interpreter}->handle_result($context, "/msg $context->{nick} Failed to find applet for '$context->{keyword}' in channel $context->{from}\n");
        return;
    }

    my ($channel, $trigger) = ($factoids[0]->[0], $factoids[0]->[1]);

    $context->{channel} = $channel;
    $context->{keyword} = $trigger;
    $context->{trigger} = $trigger;

    my $applet = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $trigger, 'action');

    $self->{pbot}->{logger}->log(
        '(' . (defined $context->{from} ? $context->{from} : "(undef)") . '): '
        . "$context->{hostmask}: Executing applet [$context->{command}] $applet $context->{arguments}\n"
    );

    $context->{arguments} = $self->{pbot}->{factoids}->{variables}->expand_factoid_vars($context, $context->{arguments});

    my $applet_dir = $self->{pbot}->{registry}->get_value('general', 'applet_dir');

    if (not chdir $applet_dir) {
        $self->{pbot}->{logger}->log("Could not chdir to '$applet_dir': $!\n");
        Carp::croak("Could not chdir to '$applet_dir': $!");
    }

    if ($self->{pbot}->{factoids}->{data}->{storage}->exists($channel, $trigger, 'workdir')) {
        chdir $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $trigger, 'workdir');
    }

    # FIXME -- add check to ensure $applet exists

    my ($exitval, $stdout, $stderr) = eval {
        my $args = $context->{arguments};

        my $strip_quotes = 1;

        $strip_quotes = 0 if $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $trigger, 'keep-quotes');

        my @cmdline = ("./$applet", $self->{pbot}->{interpreter}->split_line($args, strip_quotes => $strip_quotes));

        my $timeout = $self->{pbot}->{registry}->get_value('general', 'applet_timeout') // 30;

        my ($stdin, $stdout, $stderr);

        # encode as UTF-8 if not already encoded (e.g. by encode_json)
        if (not $context->{args_utf8}) {
            @cmdline = map { encode('UTF-8', $_) } @cmdline;
        }

        run \@cmdline, \$stdin, \$stdout, \$stderr, timeout($timeout);

        my $exitval = $? >> 8;

        $stdout = decode('UTF-8', $stdout);
        $stderr = decode('UTF-8', $stderr);

        return ($exitval, $stdout, $stderr);
    };

    if ($@) {
        my $error = $@;
        if ($error =~ m/timeout on timer/) {
            ($exitval, $stdout, $stderr) = (-1, "$context->{trigger}: timed-out", '');
        } else {
            ($exitval, $stdout, $stderr) = (-1, '', $error);
            $self->{pbot}->{logger}->log("$context->{trigger}: error executing applet: $error\n");
        }
    }

    if (length $stderr) {
        if (open(my $fh, '>>:encoding(UTF-8)', "$applet-stderr")) {
            print $fh $stderr;
            close $fh;
        } else {
            $self->{pbot}->{logger}->log("Failed to open $applet-stderr: $!\n");
        }
    }

    $context->{result} = $stdout;
    chomp $context->{result};
}

1;
