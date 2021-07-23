# File: BanList.pm
#
# Purpose: Registers commands related to bans/quiets.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::BanList;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use POSIX qw/strftime/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->register(sub { $self->cmd_banlist(@_) },   "banlist",   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_checkban(@_) },  "checkban",  0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_checkmute(@_) }, "checkmute", 0);
}

sub cmd_banlist {
    my ($self, $context) = @_;

    if (not length $context->{arguments}) {
        return "Usage: banlist <channel>";
    }

    my $result = "Ban list for $context->{arguments}:\n";

    if ($self->{pbot}->{banlist}->{banlist}->exists($context->{arguments})) {
        my $count = $self->{pbot}->{banlist}->{banlist}->get_keys($context->{arguments});
        $result .= "$count ban" . ($count == 1 ? '' : 's') . ":\n";
        foreach my $mask ($self->{pbot}->{banlist}->{banlist}->get_keys($context->{arguments})) {
            my $data = $self->{pbot}->{banlist}->{banlist}->get_data($context->{arguments}, $mask);
            $result .= "  $mask banned ";

            if (defined $data->{timestamp}) {
                my $date = strftime "%a %b %e %H:%M:%S %Y %Z", localtime $data->{timestamp};
                my $ago = concise ago (time - $data->{timestamp});
                $result .= "on $date ($ago) ";
            }

            $result .= "by $data->{owner} "   if defined $data->{owner};
            $result .= "for $data->{reason} " if defined $data->{reason};
            if (defined $data->{timeout} and $data->{timeout} > 0) {
                my $duration = concise duration($data->{timeout} - gettimeofday);
                $result .= "($duration remaining)";
            }
            $result .= ";\n";
        }
    } else {
        $result .= "bans: none;\n";
    }

    if ($self->{pbot}->{banlist}->{quietlist}->exists($context->{arguments})) {
        my $count = $self->{pbot}->{banlist}->{quietlist}->get_keys($context->{arguments});
        $result .= "$count mute" . ($count == 1 ? '' : 's') . ":\n";
        foreach my $mask ($self->{pbot}->{banlist}->{quietlist}->get_keys($context->{arguments})) {
            my $data = $self->{pbot}->{banlist}->{quietlist}->get_data($context->{arguments}, $mask);
            $result .= "  $mask muted ";

            if (defined $data->{timestamp}) {
                my $date = strftime "%a %b %e %H:%M:%S %Y %Z", localtime $data->{timestamp};
                my $ago = concise ago (time - $data->{timestamp});
                $result .= "on $date ($ago) ";
            }

            $result .= "by $data->{owner} "   if defined $data->{owner};
            $result .= "for $data->{reason} " if defined $data->{reason};
            if (defined $data->{timeout} and $data->{timeout} > 0) {
                my $duration = concise duration($data->{timeout} - gettimeofday);
                $result .= "($duration remaining)";
            }
            $result .= ";\n";
        }
    } else {
        $result .= "quiets: none\n";
    }

    $result =~ s/ ;/;/g;
    return $result;
}

sub cmd_checkban {
    my ($self, $context) = @_;
    my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    return "Usage: checkban <mask> [channel]" if not defined $target;
    $channel = $context->{from} if not defined $channel;

    return "Please specify a channel." if $channel !~ /^#/;
    return $self->{pbot}->{banlist}->checkban($channel, 'b', $target);
}

sub cmd_checkmute {
    my ($self, $context) = @_;
    my ($target, $channel) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    return "Usage: checkmute <mask> [channel]" if not defined $target;
    $channel = $context->{from} if not defined $channel;

    return "Please specify a channel." if $channel !~ /^#/;
    return $self->{pbot}->{banlist}->checkban($channel, $self->{pbot}->{registry}->get_value('banlist', 'mute_mode_char'), $target);
}

1;
