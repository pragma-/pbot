# File: BlackList.pm
#
# Purpose: Manages list of hostmasks that are not allowed to join a channel.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::BlackList;
use parent 'PBot::Class';

use PBot::Imports;

use Time::HiRes qw(gettimeofday);

sub initialize {
    my ($self, %conf) = @_;
    $self->{filename}  = $conf{filename};
    $self->{blacklist} = {};
    $self->{pbot}->{commands}->register(sub { $self->cmd_blacklist(@_) }, "blacklist", 1);
    $self->{pbot}->{capabilities}->add('admin', 'can-blacklist', 1);
    $self->load_blacklist;
}

sub cmd_blacklist {
    my ($self, $context) = @_;

    my $arglist = $context->{arglist};
    $self->{pbot}->{interpreter}->lc_args($arglist);

    my $command = $self->{pbot}->{interpreter}->shift_arg($arglist);

    return "Usage: blacklist <command>, where commands are: list/show, add, remove" if not defined $command;

    given ($command) {
        when ($_ eq "list" or $_ eq "show") {
            my $text    = "Blacklist:\n";
            my $entries = 0;
            foreach my $channel (sort keys %{$self->{blacklist}}) {
                if   ($channel eq '.*') { $text .= "  all channels:\n"; }
                else                    { $text .= "  $channel:\n"; }
                foreach my $mask (sort keys %{$self->{blacklist}->{$channel}}) {
                    $text .= "    $mask,\n";
                    $entries++;
                }
            }
            $text .= "none" if $entries == 0;
            return "/msg $context->{nick} $text";
        }
        when ("add") {
            my ($mask, $channel) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
            return "Usage: blacklist add <hostmask regex> [channel]" if not defined $mask;

            $channel = '.*' if not defined $channel;

            $self->{pbot}->{logger}->log("$context->{hostmask} added [$mask] to blacklist for channel [$channel]\n");
            $self->add($channel, $mask);
            return "/say $mask blacklisted in channel $channel";
        }
        when ("remove") {
            my ($mask, $channel) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
            return "Usage: blacklist remove <hostmask regex> [channel]" if not defined $mask;

            $channel = '.*' if not defined $channel;

            if (exists $self->{blacklist}->{$channel} and not exists $self->{blacklist}->{$channel}->{$mask}) {
                $self->{pbot}->{logger}->log("$context->{hostmask} attempt to remove nonexistent [$mask][$channel] from blacklist\n");
                return "/say $mask not found in blacklist for channel $channel (use `blacklist list` to display blacklist)";
            }

            $self->remove($channel, $mask);
            $self->{pbot}->{logger}->log("$context->{hostmask} removed [$mask] from blacklist for channel [$channel]\n");
            return "/say $mask removed from blacklist for channel $channel";
        }
        default { return "Unknown command '$command'; commands are: list/show, add, remove"; }
    }
}

sub add {
    my ($self, $channel, $hostmask) = @_;
    $self->{blacklist}->{lc $channel}->{lc $hostmask} = 1;
    $self->save_blacklist();
}

sub remove {
    my $self = shift;
    my ($channel, $hostmask) = @_;

    $channel  = lc $channel;
    $hostmask = lc $hostmask;

    if (exists $self->{blacklist}->{$channel}) {
        delete $self->{blacklist}->{$channel}->{$hostmask};

        if (keys %{$self->{blacklist}->{$channel}} == 0) { delete $self->{blacklist}->{$channel}; }
    }
    $self->save_blacklist();
}

sub clear_blacklist {
    my $self = shift;
    $self->{blacklist} = {};
}

sub load_blacklist {
    my $self = shift;
    my $filename;
    if   (@_) { $filename = shift; }
    else      { $filename = $self->{filename}; }

    if (not defined $filename) {
        $self->{pbot}->{logger}->log("No blacklist path specified -- skipping loading of blacklist");
        return;
    }

    $self->{pbot}->{logger}->log("Loading blacklist from $filename ...\n");

    open(FILE, "< $filename") or Carp::croak "Couldn't open $filename: $!\n";
    my @contents = <FILE>;
    close(FILE);

    my $i = 0;

    foreach my $line (@contents) {
        chomp $line;
        $i++;

        my ($channel, $hostmask) = split(/\s+/, $line);

        if (not defined $hostmask || not defined $channel) { Carp::croak "Syntax error around line $i of $filename\n"; }

        if (exists $self->{blacklist}->{$channel}->{$hostmask}) { Carp::croak "Duplicate blacklist entry [$hostmask][$channel] found in $filename around line $i\n"; }

        $self->{blacklist}->{$channel}->{$hostmask} = 1;
    }

    $self->{pbot}->{logger}->log("  $i entries in blacklist\n");
}

sub save_blacklist {
    my $self = shift;
    my $filename;

    if   (@_) { $filename = shift; }
    else      { $filename = $self->{filename}; }

    if (not defined $filename) {
        $self->{pbot}->{logger}->log("No blacklist path specified -- skipping saving of blacklist\n");
        return;
    }

    open(FILE, "> $filename") or die "Couldn't open $filename: $!\n";

    foreach my $channel (keys %{$self->{blacklist}}) {
        foreach my $hostmask (keys %{$self->{blacklist}->{$channel}}) { print FILE "$channel $hostmask\n"; }
    }

    close(FILE);
}

sub check_blacklist {
    my $self = shift;
    my ($hostmask, $channel, $nickserv, $gecos) = @_;

    return 0 if not defined $channel;

    my $result = eval {
        foreach my $black_channel (keys %{$self->{blacklist}}) {
            foreach my $black_hostmask (keys %{$self->{blacklist}->{$black_channel}}) {
                my $flag = '';
                $flag = $1 if $black_hostmask =~ s/^\$(.)://;

                next if $channel !~ /^$black_channel$/i;

                if ($flag eq 'a' && defined $nickserv && $nickserv =~ /^$black_hostmask$/i) {
                    $self->{pbot}->{logger}->log("$hostmask nickserv $nickserv blacklisted in channel $channel (matches [\$a:$black_hostmask] host and [$black_channel] channel)\n");
                    return 1;
                } elsif ($flag eq 'r' && defined $gecos && $gecos =~ /^$black_hostmask$/i) {
                    $self->{pbot}->{logger}->log("$hostmask GECOS $gecos blacklisted in channel $channel (matches [\$r:$black_hostmask] host and [$black_channel] channel)\n");
                    return 1;
                } elsif ($flag eq '' && $hostmask =~ /^$black_hostmask$/i) {
                    $self->{pbot}->{logger}->log("$hostmask blacklisted in channel $channel (matches [$black_hostmask] host and [$black_channel] channel)\n");
                    return 1;
                }
            }
        }
        return 0;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error in blacklist: $@\n");
        return 0;
    }

    return $result;
}

1;
