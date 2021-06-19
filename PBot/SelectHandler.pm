# File: SelectHandler.pm
#
# Purpose: Invokes select() system call and handles its events.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::SelectHandler;
use parent 'PBot::Class';

use PBot::Imports;

use IO::Select;

sub initialize {
    my ($self, %conf) = @_;
    $self->{select}  = IO::Select->new();
    $self->{readers} = {};
    $self->{buffers} = {};
}

sub add_reader {
    my ($self, $handle, $subref) = @_;
    $self->{select}->add($handle);
    $self->{readers}->{$handle} = $subref;
    $self->{buffers}->{$handle} = '';
}

sub remove_reader {
    my ($self, $handle) = @_;
    $self->{select}->remove($handle);
    delete $self->{readers}->{$handle};
    delete $self->{buffers}->{$handle};
}

sub do_select {
    my ($self) = @_;

    # maximum read length
    my $length = 8192;

    # check if any readers can read
    my @ready  = $self->{select}->can_read(.1);

    foreach my $fh (@ready) {
        # read from handle
        my $ret = sysread($fh, my $buf, $length);

        # error reading
        if (not defined $ret) {
            $self->{pbot}->{logger}->log("SelectHandler: Error reading $fh: $!\n");
            $self->remove_reader($fh);
            next;
        }

        # reader closed
        if ($ret == 0) {
            # is there anything in reader's buffer?
            if (length $self->{buffers}->{$fh}) {
                # send buffer to reader subref
                $self->{readers}->{$fh}->($self->{buffers}->{$fh});
            }

            # remove reader
            $self->remove_reader($fh);

            # skip to next reader
            next;
        }

        # sanity check for missing reader
        if (not exists $self->{readers}->{$fh}) {
            $self->{pbot}->{logger}->log("Error: no reader for $fh\n");

            # skip to next reader
            next;
        }

        # accumulate input into reader's buffer
        $self->{buffers}->{$fh} .= $buf;

        # if we read less than max length bytes then this is probably
        # a complete message so send it to reader now, otherwise we'll
        # continue to accumulate input into reader's buffer and then send
        # the buffer when reader closes.

        if ($ret < $length) {
            # send reader's buffer to reader subref
            $self->{readers}->{$fh}->($self->{buffers}->{$fh});

            # clear out reader's buffer
            $self->{buffers}->{$fh} = '';
        }
    }
}

1;
