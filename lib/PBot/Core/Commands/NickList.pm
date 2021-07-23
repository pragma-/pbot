# File: NickList.pm
#
# Purpose: Registers command for viewing nick list and nick metadata.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::NickList;

use PBot::Imports;
use parent 'PBot::Core::Class';

use Time::HiRes qw/gettimeofday/;
use Time::Duration qw/concise ago/;

use Getopt::Long qw/GetOptionsFromArray/;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->cmd_nicklist(@_) }, "nicklist", 1);
}

sub cmd_nicklist {
    my ($self, $context) = @_;

    my $usage = "Usage: nicklist (<channel [nick]> | <nick>) [-sort <by>] [-hostmask] [-join]; -hostmask shows hostmasks instead of nicks; -join includes join time";

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling_override");

    my $sort_method   = 'nick';
    my $full_hostmask = 0;
    my $include_join  = 0;

    my @args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);

    GetOptionsFromArray(
        \@args,
        'sort|s=s'     => \$sort_method,
        'hostmask|hm'  => \$full_hostmask,
        'join|j'       => \$include_join,
    );

    return "$getopt_error; $usage" if defined $getopt_error;
    return "Too many arguments -- $usage" if @args > 2;
    return $usage if @args == 0 or not length $args[0];

    my %sort = (
        'spoken' => sub {
            if ($_[1] eq '+') {
                return $_[0]->{$b}->{timestamp} <=> $_[0]->{$a}->{timestamp};
            } else {
                return $_[0]->{$a}->{timestamp} <=> $_[0]->{$b}->{timestamp};
            }
        },

        'join' => sub {
            if ($_[1] eq '+') {
                return $_[0]->{$b}->{join} <=> $_[0]->{$a}->{join};
            } else {
                return $_[0]->{$a}->{join} <=> $_[0]->{$b}->{join};
            }
        },

        'host' => sub {
            if ($_[1] eq '+') {
                return lc $_[0]->{$a}->{host} cmp lc $_[0]->{$b}->{host};
            } else {
                return lc $_[0]->{$b}->{host} cmp lc $_[0]->{$a}->{host};
            }
        },

        'nick' => sub {
            if ($_[1] eq '+') {
                return lc $_[0]->{$a}->{nick} cmp lc $_[0]->{$b}->{nick};
            } else {
                return lc $_[0]->{$b}->{nick} cmp lc $_[0]->{$a}->{nick};
            }
        },
    );

    my $sort_direction = '+';

    if ($sort_method =~ s/^(\+|\-)//) {
        $sort_direction = $1;
    }

    if (not exists $sort{$sort_method}) {
        return "Invalid sort method '$sort_method'; valid methods are: "
          . join(', ', sort keys %sort) . "; prefix with - to invert sort direction.";
    }

    # insert from channel as first argument if first argument is not a channel
    if ($args[0] !~ /^#/) {
        unshift @args, $context->{from};
    }

    my $nicklist = $self->{pbot}->{nicklist}->{nicklist};

    # ensure channel has a nicklist
    if (not exists $nicklist->{lc $args[0]}) {
        return "No nicklist for channel $args[0].";
    }

    my $result;

    if (@args == 1) {
        # nicklist for a specific channel

        my $count = keys %{$nicklist->{lc $args[0]}};

        $result = "$count nick" . ($count == 1 ? '' : 's') . " in $args[0]:\n";

        foreach my $entry (
            sort {
                $sort{$sort_method}->($nicklist->{lc $args[0]}, $sort_direction)
            } keys %{$nicklist->{lc $args[0]}}
        ) {
            if ($full_hostmask) {
                $result .= "  $nicklist->{lc $args[0]}->{$entry}->{hostmask}";
            } else {
                $result .= "  $nicklist->{lc $args[0]}->{$entry}->{nick}";
            }

            my $sep = ': ';

            if ($nicklist->{lc $args[0]}->{$entry}->{timestamp} > 0) {
                my $duration = concise ago (gettimeofday - $nicklist->{lc $args[0]}->{$entry}->{timestamp});
                $result .= "${sep}last spoken $duration";
                $sep = ', ';
            }

            if ($include_join and $nicklist->{lc $args[0]}->{$entry}->{join} > 0) {
                my $duration = concise ago (gettimeofday - $nicklist->{lc $args[0]}->{$entry}->{join});
                $result .= "${sep}joined $duration";
                $sep = ', ';
            }

            foreach my $key (sort keys %{$nicklist->{lc $args[0]}->{$entry}}) {
                next if grep { $key eq $_ } qw/nick user host join timestamp hostmask/;
                if ($nicklist->{lc $args[0]}->{$entry}->{$key} == 1) {
                    $result .= "$sep$key";
                } else {
                    $result .= "$sep$key => $nicklist->{lc $args[0]}->{$entry}->{$key}";
                }
                $sep = ', ';
            }
            $result .= "\n";
        }
    } else {
        # nicklist for a specific user

        if (not exists $nicklist->{lc $args[0]}->{lc $args[1]}) {
            return "No such nick $args[1] in channel $args[0].";
        }

        $result = "Nicklist information for $nicklist->{lc $args[0]}->{lc $args[1]}->{hostmask} in $args[0]: ";
        my $sep = '';

        if ($nicklist->{lc $args[0]}->{lc $args[1]}->{timestamp} > 0) {
            my $duration = concise ago (gettimeofday - $nicklist->{lc $args[0]}->{lc $args[1]}->{timestamp});
            $result .= "last spoken $duration";
            $sep = ', ';
        }

        if ($nicklist->{lc $args[0]}->{lc $args[1]}->{join} > 0) {
            my $duration = concise ago (gettimeofday - $nicklist->{lc $args[0]}->{lc $args[1]}->{join});
            $result .= "${sep}joined $duration";
            $sep = ', ';
        }

        foreach my $key (sort keys %{$nicklist->{lc $args[0]}->{lc $args[1]}}) {
            next if grep { $key eq $_ } qw/nick user host join timestamp hostmask/;
            $result .= "$sep$key => $nicklist->{lc $args[0]}->{lc $args[1]}->{$key}";
            $sep = ', ';
        }

        $result .= 'no details' if $sep eq '';
    }

    return $result;
}

1;
