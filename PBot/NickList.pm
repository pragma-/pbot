# File: NickList.pm
# Author: pragma_
#
# Purpose: Maintains lists of nicks currently present in channels.
# Used to retrieve list of channels a nick is present in or to
# determine if a nick is present in a channel.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::NickList;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use Text::Levenshtein qw/fastdistance/;
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;
use Time::HiRes qw/gettimeofday/;
use Time::Duration qw/concise ago/;

use Getopt::Long qw/GetOptionsFromArray/;

sub initialize {
    my ($self, %conf) = @_;
    $self->{nicklist} = {};
    $self->{pbot}->{registry}->add_default('text', 'nicklist', 'debug', '0');

    $self->{pbot}->{commands}->register(sub { $self->cmd_nicklist(@_) }, "nicklist", 1);

    $self->{pbot}->{event_dispatcher}->register_handler('irc.namreply', sub { $self->on_namreply(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.join',     sub { $self->on_join(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.part',     sub { $self->on_part(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',     sub { $self->on_quit(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',     sub { $self->on_kick(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.nick',     sub { $self->on_nickchange(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',   sub { $self->on_activity(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction',  sub { $self->on_activity(@_) });

    # handlers for the bot itself joining/leaving channels
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.join', sub { $self->on_join_channel(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('pbot.part', sub { $self->on_part_channel(@_) });
}

sub cmd_nicklist {
    my ($self, $context) = @_;

    my $nicklist;
    my $usage = "Usage: nicklist (<channel [nick]> | <nick>) [-sort=nick|host|spoken|join] [-hostmask] [-join]; -hostmask to show hostmasks instead of nicks; -join to include join time";

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling_override");

    my $sort_method = 'nick';
    my $full_hostmask = 0;
    my $include_join = 0;

    my @args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);
    GetOptionsFromArray(
        \@args,
        'sort|s=s'     => \$sort_method,
        'hostmask|hm'  => \$full_hostmask,
        'join|j'       => \$include_join,
    );
    return "$getopt_error; $usage" if defined $getopt_error;

    return $usage if not length $args[0];

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
        return "Invalid sort method '$sort_method'; valid methods are (you may prefix with a - to invert the sort direction): " . join(', ', sort keys %sort);
    }

    if ($args[0] !~ /^#/) {
        unshift @args, $context->{from};
    }

    if (@args == 1) {
        if (not exists $self->{nicklist}->{lc $args[0]}) {
            return "No nicklist for channel $args[0].";
        }

        my $count = keys %{$self->{nicklist}->{lc $args[0]}};
        $nicklist = "$count nick" . ($count == 1 ? '' : 's') . " in $args[0]:\n";

        foreach my $entry (sort { $sort{$sort_method}->($self->{nicklist}->{lc $args[0]}, $sort_direction) } keys %{$self->{nicklist}->{lc $args[0]}}) {
            if ($full_hostmask) {
                $nicklist .= "  $self->{nicklist}->{lc $args[0]}->{$entry}->{hostmask}";
            } else {
                $nicklist .= "  $self->{nicklist}->{lc $args[0]}->{$entry}->{nick}";
            }

            my $sep = ': ';

            if ($self->{nicklist}->{lc $args[0]}->{$entry}->{timestamp} > 0) {
                my $duration = concise ago (gettimeofday - $self->{nicklist}->{lc $args[0]}->{$entry}->{timestamp});
                $nicklist .= "${sep}last spoken $duration";
                $sep = ', ';
            }

            if ($include_join and $self->{nicklist}->{lc $args[0]}->{$entry}->{join} > 0) {
                my $duration = concise ago (gettimeofday - $self->{nicklist}->{lc $args[0]}->{$entry}->{join});
                $nicklist .= "${sep}joined $duration";
                $sep = ', ';
            }

            foreach my $key (sort keys %{$self->{nicklist}->{lc $args[0]}->{$entry}}) {
                next if grep { $key eq $_ } qw/nick user host join timestamp hostmask/;
                if ($self->{nicklist}->{lc $args[0]}->{$entry}->{$key} == 1) {
                    $nicklist .= "$sep$key";
                } else {
                    $nicklist .= "$sep$key => $self->{nicklist}->{lc $args[0]}->{$entry}->{$key}";
                }
                $sep = ', ';
            }
            $nicklist .= "\n";
        }
    } else {
        if (not exists $self->{nicklist}->{lc $args[0]}) {
            return "No nicklist for channel $args[0].";
        } elsif (not exists $self->{nicklist}->{lc $args[0]}->{lc $args[1]}) {
            return "No such nick $args[1] in channel $args[0].";
        }

        $nicklist = "Nicklist information for $self->{nicklist}->{lc $args[0]}->{lc $args[1]}->{hostmask} in $args[0]: ";
        my $sep = '';

        if ($self->{nicklist}->{lc $args[0]}->{lc $args[1]}->{timestamp} > 0) {
            my $duration = concise ago (gettimeofday - $self->{nicklist}->{lc $args[0]}->{lc $args[1]}->{timestamp});
            $nicklist .= "last spoken $duration";
            $sep = ', ';
        }

        if ($self->{nicklist}->{lc $args[0]}->{lc $args[1]}->{join} > 0) {
            my $duration = concise ago (gettimeofday - $self->{nicklist}->{lc $args[0]}->{lc $args[1]}->{join});
            $nicklist .= "${sep}joined $duration";
            $sep = ', ';
        }

        foreach my $key (sort keys %{$self->{nicklist}->{lc $args[0]}->{lc $args[1]}}) {
            next if grep { $key eq $_ } qw/nick user host join timestamp hostmask/;
            $nicklist .= "$sep$key => $self->{nicklist}->{lc $args[0]}->{lc $args[1]}->{$key}";
            $sep = ', ';
        }

        $nicklist .= 'no details' if $sep eq '';
    }

    return $nicklist;
}

sub update_timestamp {
    my ($self, $channel, $nick) = @_;
    my $orig_nick = $nick;
    $channel = lc $channel;
    $nick    = lc $nick;

    if (exists $self->{nicklist}->{$channel} and exists $self->{nicklist}->{$channel}->{$nick}) { $self->{nicklist}->{$channel}->{$nick}->{timestamp} = gettimeofday; }
    else {
        $self->{pbot}->{logger}->log("Adding nick '$orig_nick' to channel '$channel'\n") if $self->{pbot}->{registry}->get_value('nicklist', 'debug');
        $self->{nicklist}->{$channel}->{$nick} = {nick => $orig_nick, timestamp => scalar gettimeofday};
    }
}

sub remove_channel {
    my ($self, $channel) = @_;
    delete $self->{nicklist}->{lc $channel};
}

sub add_nick {
    my ($self, $channel, $nick) = @_;
    if (not exists $self->{nicklist}->{lc $channel}->{lc $nick}) {
        $self->{pbot}->{logger}->log("Adding nick '$nick' to channel '$channel'\n") if $self->{pbot}->{registry}->get_value('nicklist', 'debug');
        $self->{nicklist}->{lc $channel}->{lc $nick} = {nick => $nick, timestamp => 0};
    }
}

sub remove_nick {
    my ($self, $channel, $nick) = @_;
    $self->{pbot}->{logger}->log("Removing nick '$nick' from channel '$channel'\n") if $self->{pbot}->{registry}->get_value('nicklist', 'debug');
    delete $self->{nicklist}->{lc $channel}->{lc $nick};
}

sub get_channels {
    my ($self, $nick) = @_;
    my @channels;

    $nick = lc $nick;

    foreach my $channel (keys %{$self->{nicklist}}) {
        if (exists $self->{nicklist}->{$channel}->{$nick}) { push @channels, $channel; }
    }

    return \@channels;
}

sub get_nicks {
    my ($self, $channel) = @_;
    $channel = lc $channel;
    my @nicks;
    return @nicks if not exists $self->{nicklist}->{$channel};
    foreach my $nick (keys %{$self->{nicklist}->{$channel}}) { push @nicks, $self->{nicklist}->{$channel}->{$nick}->{nick}; }
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
        if (exists $self->{nicklist}->{$channel}->{$nick}) { return $self->{nicklist}->{$channel}->{$nick}->{nick}; }
    }
    return 0;
}

sub is_present {
    my ($self, $channel, $nick) = @_;

    $channel = lc $channel;
    $nick    = lc $nick;

    if   (exists $self->{nicklist}->{$channel} and exists $self->{nicklist}->{$channel}->{$nick}) { return $self->{nicklist}->{$channel}->{$nick}->{nick}; }
    else                                                                                          { return 0; }
}

sub is_present_similar {
    my ($self, $channel, $nick, $similar) = @_;

    $channel = lc $channel;
    $nick    = lc $nick;

    return 0                                              if not exists $self->{nicklist}->{$channel};
    return $self->{nicklist}->{$channel}->{$nick}->{nick} if $self->is_present($channel, $nick);
    return 0                                              if $nick =~ m/(?:^\$|\s)/;                     # not nick-like

    my $percentage = $self->{pbot}->{registry}->get_value('interpreter', 'nick_similarity');
    $percentage = 0.20 if not defined $percentage;

    $percentage = $similar if defined $similar;

    my $now = gettimeofday;
    foreach my $person (sort { $self->{nicklist}->{$channel}->{$b}->{timestamp} <=> $self->{nicklist}->{$channel}->{$a}->{timestamp} } keys %{$self->{nicklist}->{$channel}})
    {
        return 0 if $now - $self->{nicklist}->{$channel}->{$person}->{timestamp} > 3600;                 # 1 hour
        my $distance = fastdistance($nick, $person);
        my $length   = length $nick > length $person ? length $nick : length $person;

        if ($length != 0 && $distance / $length <= $percentage) { return $self->{nicklist}->{$channel}->{$person}->{nick}; }
    }
    return 0;
}

sub random_nick {
    my ($self, $channel) = @_;

    $channel = lc $channel;

    if (exists $self->{nicklist}->{$channel}) {
        my $now   = gettimeofday;
        my @nicks = grep { $now - $self->{nicklist}->{$channel}->{$_}->{timestamp} < 3600 * 2 } keys %{$self->{nicklist}->{$channel}};

        my $nick = $nicks[rand @nicks];
        return $self->{nicklist}->{$channel}->{$nick}->{nick};
    } else {
        return undef;
    }
}

sub on_namreply {
    my ($self, $event_type, $event) = @_;
    my ($channel, $nicks) = ($event->{event}->{args}[2], $event->{event}->{args}[3]);

    foreach my $nick (split ' ', $nicks) {
        my $stripped_nick = $nick;
        $stripped_nick =~ s/^[@+%]//g;    # remove OP/Voice/etc indicator from nick
        $self->add_nick($channel, $stripped_nick);

        my ($account_id, $hostmask) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($stripped_nick);

        if (defined $hostmask) {
            my ($user, $host) = $hostmask =~ m/[^!]+!([^@]+)@(.*)/;
            $self->set_meta($channel, $stripped_nick, 'hostmask', $hostmask);
            $self->set_meta($channel, $stripped_nick, 'user',     $user);
            $self->set_meta($channel, $stripped_nick, 'host',     $host);
        }

        if ($nick =~ m/\@/) { $self->set_meta($channel, $stripped_nick, '+o', 1); }

        if ($nick =~ m/\+/) { $self->set_meta($channel, $stripped_nick, '+v', 1); }

        if ($nick =~ m/\%/) { $self->set_meta($channel, $stripped_nick, '+h', 1); }
    }
    return 0;
}

sub on_activity {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->{to}[0]);
    $self->update_timestamp($channel, $nick);
    return 0;
}

sub on_join {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);
    $self->add_nick($channel, $nick);
    $self->set_meta($channel, $nick, 'hostmask', "$nick!$user\@$host");
    $self->set_meta($channel, $nick, 'user',     $user);
    $self->set_meta($channel, $nick, 'host',     $host);
    $self->set_meta($channel, $nick, 'join',     gettimeofday);
    return 0;
}

sub on_part {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);
    $self->remove_nick($channel, $nick);
    return 0;
}

sub on_quit {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user,       $host)  = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);

    foreach my $channel (keys %{$self->{nicklist}}) {
        if ($self->is_present($channel, $nick)) { $self->remove_nick($channel, $nick); }
    }
    return 0;
}

sub on_kick {
    my ($self, $event_type, $event) = @_;
    my ($nick, $channel) = ($event->{event}->to, $event->{event}->{args}[0]);
    $self->remove_nick($channel, $nick);
    return 0;
}

sub on_nickchange {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $newnick) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);

    foreach my $channel (keys %{$self->{nicklist}}) {
        if ($self->is_present($channel, $nick)) {
            my $meta = delete $self->{nicklist}->{$channel}->{lc $nick};
            $meta->{nick}                                = $newnick;
            $meta->{timestamp}                           = gettimeofday;
            $self->{nicklist}->{$channel}->{lc $newnick} = $meta;
        }
    }
    return 0;
}

sub on_join_channel {
    my ($self, $event_type, $event) = @_;
    $self->remove_channel($event->{channel});    # clear nicklist to remove any stale nicks before repopulating with namreplies
    return 0;
}

sub on_part_channel {
    my ($self, $event_type, $event) = @_;
    $self->remove_channel($event->{channel});
    return 0;
}

1;
