# File: BlackList.pm
#
# Purpose: Manages list of hostmasks that are not allowed to join a channel.

# SPDX-FileCopyrightText: 2015-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::BlackList;
use parent 'PBot::Core::Class';

use PBot::Imports;

sub initialize($self, %conf) {
    $self->{filename} = $conf{filename};
    $self->{storage}  = {};
    $self->load;
}

sub add($self, $channel, $hostmask) {
    $self->{storage}->{lc $channel}->{lc $hostmask} = 1;
    $self->save;
}

sub remove($self, $channel, $hostmask) {
    $channel  = lc $channel;
    $hostmask = lc $hostmask;

    if (exists $self->{storage}->{$channel}) {
        delete $self->{storage}->{$channel}->{$hostmask};

        if (not keys %{$self->{storage}->{$channel}}) {
            delete $self->{storage}->{$channel};
        }
    }

    $self->save;
}

sub clear($self) {
    $self->{storage} = {};
}

sub load($self) {
    if (not $self->{filename}) {
        $self->{pbot}->{logger}->log("No blacklist path specified -- skipping loading of blacklist");
        return;
    }

    $self->{pbot}->{logger}->log("Loading blacklist from $self->{filename} ...\n");

    open(FILE, "< $self->{filename}") or Carp::croak "Couldn't open $self->{filename}: $!\n";
    my @contents = <FILE>;
    close(FILE);

    my $i = 0;

    foreach my $line (@contents) {
        chomp $line;
        $i++;

        my ($channel, $hostmask) = split(/\s+/, $line);

        if (not defined $hostmask || not defined $channel) {
            Carp::croak "Syntax error around line $i of $self->{filename}\n";
        }

        if (exists $self->{storage}->{$channel}->{$hostmask}) {
            Carp::croak "Duplicate blacklist entry $hostmask $channel found in $self->{filename} around line $i\n";
        }

        $self->{storage}->{$channel}->{$hostmask} = 1;
    }

    $self->{pbot}->{logger}->log("  $i entries in blacklist\n");
}

sub save($self) {
    if (not $self->{filename}) {
        $self->{pbot}->{logger}->log("No blacklist path specified -- skipping saving of blacklist\n");
        return;
    }

    open(FILE, "> $self->{filename}") or die "Couldn't open $self->{filename}: $!\n";

    foreach my $channel (keys %{$self->{storage}}) {
        foreach my $hostmask (keys %{$self->{storage}->{$channel}}) {
            print FILE "$channel $hostmask\n";
        }
    }

    close FILE;
}

sub is_blacklisted($self, $hostmask, $channel, $nickserv = undef, $gecos = undef) {
    return 0 if not defined $channel;

    my $result = eval {
        foreach my $black_channel (keys %{$self->{storage}}) {
            foreach my $black_hostmask (keys %{$self->{storage}->{$black_channel}}) {
                next if $channel !~ /^$black_channel$/i;

                my $flag = '';

                if ($black_hostmask =~ s/^\$(.)://) {
                    $flag = $1;
                }

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

    if (my $exception = $@) {
        $self->{pbot}->{logger}->log("Error in blacklist: $exception");
        return 0;
    }

    return $result;
}

1;
