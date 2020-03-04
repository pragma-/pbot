# File: IgnoreList.pm
# Author: pragma_
#
# Purpose: Manages ignore list.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::IgnoreList;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use Time::Duration qw/concise duration/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{filename} = $conf{filename};

    $self->{ignorelist} = PBot::DualIndexHashObject->new(pbot => $self->{pbot}, name => 'IgnoreList', filename => $self->{filename});
    $self->{ignorelist}->load;

    $self->{pbot}->{commands}->register(sub { $self->ignore_cmd(@_) },   "ignore",   1);
    $self->{pbot}->{commands}->register(sub { $self->unignore_cmd(@_) }, "unignore", 1);

    $self->{pbot}->{capabilities}->add('admin', 'can-ignore',   1);
    $self->{pbot}->{capabilities}->add('admin', 'can-unignore', 1);

    $self->{pbot}->{capabilities}->add('chanop', 'can-ignore',   1);
    $self->{pbot}->{capabilities}->add('chanop', 'can-unignore', 1);

    $self->{pbot}->{timer}->register(sub { $self->check_ignore_timeouts }, 10);
}

sub add {
    my ($self, $channel, $hostmask, $length, $owner) = @_;

    if ($hostmask !~ /!/) {
        $hostmask .= '!*@*';
    } elsif ($hostmask !~ /@/) {
        $hostmask .= '@*';
    }

    my $regex = quotemeta $hostmask;
    $regex =~ s/\\\*/.*/g;
    $regex =~ s/\\\?/./g;

    my $data = {
        owner => $owner,
        created_on => time,
        regex => $regex,
    };

    if ($length < 0) {
        $data->{timeout} = -1;
    } else {
        $data->{timeout} = time + $length;
    }

    $self->{ignorelist}->add($channel, $hostmask, $data);

    my $duration = $data->{timeout} == -1 ? 'all eternity' : duration $length;
    return "$hostmask ignored for $duration";
}

sub remove {
    my ($self, $channel, $hostmask) = @_;
    return $self->{ignorelist}->remove($channel, $hostmask);
}

sub is_ignored {
    my ($self, $channel, $hostmask) = @_;

    return 0 if $self->{pbot}->{users}->loggedin_admin($channel, $hostmask);

    foreach my $chan ('.*', $channel) {
        foreach my $ignored ($self->{ignorelist}->get_keys($chan)) {
            my $regex = $self->{ignorelist}->get_data($chan, $ignored, 'regex');
            return 1 if $hostmask =~ /^$regex$/i;
        }
    }

    return 0;
}

sub check_ignore_timeouts {
    my ($self) = @_;
    my $now    = time;

    foreach my $channel ($self->{ignorelist}->get_keys) {
        foreach my $hostmask ($self->{ignorelist}->get_keys($channel)) {
            my $timeout = $self->{ignorelist}->get_data($channel, $hostmask, 'timeout');
            next if $timeout == -1; # permanent ignore

            if ($now >= $timeout) {
                $self->{pbot}->{logger}->log("Unignoring $hostmask in channel $channel.\n");
                $self->remove($channel, $hostmask);
            }
        }
    }
}

sub ignore_cmd {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

    my ($target, $channel, $length) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

    return "Usage: ignore <hostmask> [channel [timeout]] | ignore list" if not defined $target;

    if ($target =~ /^list$/i) {
        my $text = "Ignored: ";
        my $now  = time;
        my $ignored = 0;

        foreach my $channel (sort $self->{ignorelist}->get_keys) {
            $text .= $channel eq '.*' ? "global:\n" : "$channel:\n";
            my @list = ();
            foreach my $hostmask (sort $self->{ignorelist}->get_keys($channel)) {
                my $timeout = $self->{ignorelist}->get_data($channel, $hostmask, 'timeout');
                if ($timeout == -1) {
                    push @list, "  $hostmask";
                } else {
                    push @list, "  $hostmask (" . (concise duration $timeout - $now) . ')';
                }
                $ignored++;
            }
            $text .= join ";\n", @list;
        }
        return "Ignore list is empty." if not $ignored;
        return "/msg $nick $text";
    }

    if (not defined $channel) {
        $channel = ".*";    # all channels
    }

    if (not defined $length) {
        $length = -1;       # permanently
    } else {
        my $error;
        ($length, $error) = $self->{pbot}->{parsedate}->parsedate($length);
        return $error if defined $error;
    }

    return $self->add($channel, $target, $length, "$nick!$user\@$host");
}

sub unignore_cmd {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
    my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

    if (not defined $target) { return "Usage: unignore <hostmask> [channel]"; }

    if (not defined $channel) { $channel = '.*'; }

    return $self->remove($channel, $target);
}

1;
