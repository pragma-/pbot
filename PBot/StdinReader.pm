# File: StdinReader.pm
#
# Purpose: Reads input from STDIN.
#
# Note: To execute a command in a channel, use the `in` command:
#
#    in #foo echo hi
#
# The above will output "hi" in channel #foo.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::StdinReader;
use parent 'PBot::Class';

use PBot::Imports;

use POSIX qw(tcgetpgrp getpgrp);  # to check whether process is in background or foreground

use Encode;

sub initialize {
    my ($self, %conf) = @_;

    # create stdin bot-admin account for bot
    my $user = $self->{pbot}->{users}->find_user('.*', '*!stdin@pbot');

    if (not defined $user or not $self->{pbot}->{capabilities}->userhas($user, 'botowner')) {
        my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
        $self->{pbot}->{logger}->log("Adding stdin botowner *!stdin\@pbot...\n");
        $self->{pbot}->{users}->add_user($botnick, '.*', '*!stdin@pbot', 'botowner', undef, 1);
        $self->{pbot}->{users}->login($botnick, "$botnick!stdin\@pbot", undef);
        $self->{pbot}->{users}->save;
    }

    if (not $self->{pbot}->{registry}->get_value('general', 'daemon')) {
        # TTY is used to check whether process is in background or foreground
        open TTY, "</dev/tty" or die $!;
        $self->{tty_fd} = fileno(TTY);

        # add STDIN to select handler
        $self->{pbot}->{select_handler}->add_reader(\*STDIN, sub { $self->stdin_reader(@_) });
    } else {
        $self->{pbot}->{logger}->log("Starting in daemon mode.\n");
        # TODO: close STDIN, etc?
    }
}

sub stdin_reader {
    my ($self, $input) = @_;

    # make sure we're in the foreground first
    $self->{foreground} = (tcgetpgrp($self->{tty_fd}) == getpgrp()) ? 1 : 0;
    return if not $self->{foreground};

    # decode STDIN input from utf8
    $input = decode('UTF-8', $input);

    # remove newline
    chomp $input;

    $self->{pbot}->{logger}->log("---------------------------------------------\n");
    $self->{pbot}->{logger}->log("Got STDIN: $input\n");

    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

    # process input as a bot command
    return $self->{pbot}->{interpreter}->process_line($botnick, $botnick, "stdin", "pbot", $input, 1);
}

1;
