# File: NickList.pm
#
# Purpose: Maintains lists of nicks currently present in channels.
# Used to retrieve list of channels a nick is present in or to
# determine if a nick is present in a channel.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::NickList;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Text::Levenshtein qw/fastdistance/;
use Time::HiRes qw/gettimeofday/;

sub initialize {
    my ($self, %conf) = @_;

    # nicklist hashtable
    $self->{nicklist} = {};

    # nicklist debug registry entry
    $self->{pbot}->{registry}->add_default('text', 'nicklist', 'debug', '0');
}

sub update_timestamp {
    my ($self, $channel, $nick) = @_;

    my $orig_nick = $nick;

    $channel = lc $channel;
    $nick    = lc $nick;

    if (not exists $self->{nicklist}->{$channel} or not exists $self->{nicklist}->{$channel}->{$nick}) {
        $self->add_nick($channel, $orig_nick);
    }

    $self->{nicklist}->{$channel}->{$nick}->{timestamp} = gettimeofday;
}

sub remove_channel {
    my ($self, $channel) = @_;
    delete $self->{nicklist}->{lc $channel};
}

sub add_nick {
    my ($self, $channel, $nick) = @_;

    if (not exists $self->{nicklist}->{lc $channel}->{lc $nick}) {
        if ($self->{pbot}->{registry}->get_value('nicklist', 'debug')) {
            $self->{pbot}->{logger}->log("Adding nick '$nick' to channel '$channel'\n");
        }
        $self->{nicklist}->{lc $channel}->{lc $nick} = { nick => $nick, timestamp => 0, join => 0 };
    }
}

sub remove_nick {
    my ($self, $channel, $nick) = @_;

    if ($self->{pbot}->{registry}->get_value('nicklist', 'debug')) {
        $self->{pbot}->{logger}->log("Removing nick '$nick' from channel '$channel'\n");
    }
    delete $self->{nicklist}->{lc $channel}->{lc $nick};
}

sub get_channels {
    my ($self, $nick) = @_;

    $nick = lc $nick;

    my @channels;

    foreach my $channel (keys %{$self->{nicklist}}) {
        if (exists $self->{nicklist}->{$channel}->{$nick}) {
            push @channels, $channel;
        }
    }

    return \@channels;
}

sub get_nicks {
    my ($self, $channel) = @_;

    $channel = lc $channel;

    my @nicks;

    return @nicks if not exists $self->{nicklist}->{$channel};

    foreach my $nick (keys %{$self->{nicklist}->{$channel}}) {
        push @nicks, $self->{nicklist}->{$channel}->{$nick}->{nick};
    }

    return @nicks;
}

sub set_meta {
    my ($self, $channel, $nick, $key, $value) = @_;

    $channel = lc $channel;
    $nick    = lc $nick;

    if (not exists $self->{nicklist}->{$channel} or not exists $self->{nicklist}->{$channel}->{$nick}) {
        if (exists $self->{nicklist}->{$channel} and $nick =~ m/[*?]/) {
            my $regex = quotemeta $nick;

            $regex =~ s/\\\*/.*?/g;
            $regex =~ s/\\\?/./g;

            my $found = 0;

            foreach my $n (keys %{$self->{nicklist}->{$channel}}) {
                if (exists $self->{nicklist}->{$channel}->{$n}->{hostmask} and $self->{nicklist}->{$channel}->{$n}->{hostmask} =~ m/$regex/i) {
                    $self->{nicklist}->{$channel}->{$n}->{$key} = $value;
                    $found++;
                }
            }

            return $found;
        } else {
            $self->{pbot}->{logger}->log("Nicklist: Attempt to set invalid meta ($key => $value) for $nick in $channel.\n");
            return 0;
        }
    }

    $self->{nicklist}->{$channel}->{$nick}->{$key} = $value;
    return 1;
}

sub delete_meta {
    my ($self, $channel, $nick, $key) = @_;

    $channel = lc $channel;
    $nick    = lc $nick;

    if (not exists $self->{nicklist}->{$channel} or not exists $self->{nicklist}->{$channel}->{$nick} or not exists $self->{nicklist}->{$channel}->{$nick}->{$key}) {
        return undef;
    }

    return delete $self->{nicklist}->{$channel}->{$nick}->{$key};
}

sub get_meta {
    my ($self, $channel, $nick, $key) = @_;

    $channel = lc $channel;
    $nick    = lc $nick;

    if (not exists $self->{nicklist}->{$channel} or not exists $self->{nicklist}->{$channel}->{$nick} or not exists $self->{nicklist}->{$channel}->{$nick}->{$key}) {
        return undef;
    }

    return $self->{nicklist}->{$channel}->{$nick}->{$key};
}

sub is_present_any_channel {
    my ($self, $nick) = @_;

    $nick = lc $nick;

    foreach my $channel (keys %{$self->{nicklist}}) {
        if (exists $self->{nicklist}->{$channel}->{$nick}) {
            return $self->{nicklist}->{$channel}->{$nick}->{nick};
        }
    }

    return 0;
}

sub is_present {
    my ($self, $channel, $nick) = @_;

    $channel = lc $channel;
    $nick    = lc $nick;

    if (exists $self->{nicklist}->{$channel} and exists $self->{nicklist}->{$channel}->{$nick}) {
        return $self->{nicklist}->{$channel}->{$nick}->{nick};
    } else {
        return 0;
    }
}

sub is_present_similar {
    my ($self, $channel, $nick, $similarity) = @_;

    $channel = lc $channel;
    $nick    = lc $nick;

    return 0 if not exists $self->{nicklist}->{$channel};

    return $self->{nicklist}->{$channel}->{$nick}->{nick} if $self->is_present($channel, $nick);

    if ($nick =~ m/(?:^\$|\s)/) {
        # not nick-like
        # TODO: why do we have this check? added log message to find out when/if it happens
        $self->{pbot}->{logger}->log("NickList::is_present_similiar [$channel] [$nick] is not nick-like?\n");
        return 0;
    }

    my $percentage;

    if (defined $similarity) {
        $percentage = $similarity;
    } else {
        $percentage = $self->{pbot}->{registry}->get_value('interpreter', 'nick_similarity') // 0.20;
    }

    my $now = gettimeofday;

    foreach my $person (sort { $self->{nicklist}->{$channel}->{$b}->{timestamp} <=> $self->{nicklist}->{$channel}->{$a}->{timestamp} } keys %{$self->{nicklist}->{$channel}}) {
        if ($now - $self->{nicklist}->{$channel}->{$person}->{timestamp} > 3600) {
            # if it has been 1 hour since this person has last spoken, the similar nick
            # is probably not intended for them.
            return 0;
        }

        my $distance = fastdistance($nick, $person);
        my $length   = length $nick > length $person ? length $nick : length $person;

        if ($length != 0 && $distance / $length <= $percentage) {
            return $self->{nicklist}->{$channel}->{$person}->{nick};
        }
    }

    return 0;
}

sub random_nick {
    my ($self, $channel) = @_;

    $channel = lc $channel;

    if (exists $self->{nicklist}->{$channel}) {
        my $now   = gettimeofday;

        # build list of nicks that have spoken within the last 2 hours
        my @nicks = grep { $now - $self->{nicklist}->{$channel}->{$_}->{timestamp} < 3600 * 2 } keys %{$self->{nicklist}->{$channel}};

        # pick a random nick from tha list
        my $nick = $nicks[rand @nicks];

        # return its canonical name
        return $self->{nicklist}->{$channel}->{$nick}->{nick};
    } else {
        return undef;
    }
}

1;
