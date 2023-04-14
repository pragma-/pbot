# File: SelectHandler.pm
#
# Purpose: Adds/removes file handles to/from PBot::Core::IRC's select loop
# and contains handlers for select events.

# SPDX-FileCopyrightText: 2014-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::SelectHandler;
use parent 'PBot::Core::Class';

use PBot::Imports;

sub initialize {
    # nothing to initialize
}

sub add_reader($self, $handle, $subref) {
    # add file handle to PBot::Core::IRC's select loop
    $self->{pbot}->{irc}->addfh($handle, sub { $self->on_select_read($handle, $subref) }, 'r');

    # create read buffer for this handle
    $self->{buffers}->{$handle} = '';
}

sub remove_reader($self, $handle) {
    # remove file handle from PBot::Core::IRC's select loop
    $self->{pbot}->{irc}->removefh($handle);

    # delete this handle's read buffer
    delete $self->{buffers}->{$handle};
}

sub on_select_read($self, $handle, $subref) {
    # maximum read length
    my $length = 8192;

    # read from handle
    my $ret = sysread($handle, my $buf, $length);

    # error reading
    if (not defined $ret) {
        $self->{pbot}->{logger}->log("SelectHandler: Error reading $handle: $!\n");
        $self->remove_reader($handle);
        return;
    }

    # reader closed
    if ($ret == 0) {
        # is there anything in reader's buffer?
        if (length $self->{buffers}->{$handle}) {
            # send buffer to reader's consumer subref
            $subref->($self->{buffers}->{$handle});
        }

        # remove reader
        $self->remove_reader($handle);
        return;
    }

    # accumulate input into reader's buffer
    $self->{buffers}->{$handle} .= $buf;

    # if we read less than max length bytes then this is probably
    # a complete message so send it to reader now, otherwise we'll
    # continue to accumulate input into reader's buffer and then send
    # the buffer when reader closes.
    #
    # FIXME: this should be line-based or some protocol.

    if ($ret < $length) {
        # send reader's buffer to reader's consumer subref
        $subref->($self->{buffers}->{$handle});

        # clear out reader's buffer
        $self->{buffers}->{$handle} = '';
    }
}

1;
