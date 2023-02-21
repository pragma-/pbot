# File: AntiTwitter.pm
#
# Purpose: Warns people off from using @nick style addressing. Temp-bans
# if they persist.

# SPDX-FileCopyrightText: 2017-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::AntiTwitter;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Time::HiRes qw/gettimeofday/;
use Time::Duration qw/duration/;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public', sub { $self->on_public(@_) });
    $self->{offenses} = {};
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
    $self->{pbot}->{event_queue}->dequeue_event('antitwitter .*');
}

sub on_public {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $channel, $msg) = ($event->nick, $event->user, $event->host, $event->{to}[0], $event->args);

    return 0 if $event->{interpreted};

    $channel = lc $channel;
    return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

    my $u = $self->{pbot}->{users}->loggedin($channel, "$nick!$user\@$host");
    return 0 if $self->{pbot}->{capabilities}->userhas($u, 'is-whitelisted');

    while ($msg =~ m/\B[＠@]([a-z0-9_^{}\-\\\[\]\|]+)/ig) {
        my $n = $1;
        if ($self->{pbot}->{nicklist}->is_present_similar($channel, $n, 0.05)) {
            $self->{offenses}->{$channel}->{$nick}->{offenses}++;
            $self->{offenses}->{$channel}->{$nick}->{time} = gettimeofday;

            $self->{pbot}->{logger}->log("$nick!$user\@$host is a twit. ($self->{offenses}->{$channel}->{$nick}->{offenses} offenses) $channel: $msg\n");

            given ($self->{offenses}->{$channel}->{$nick}->{offenses}) {
                when (1) {
                    $event->{conn}->privmsg($nick, "Please do not use \@nick to address people. Drop the @ symbol; it's not necessary and it's ugly.");
                }

                when (2) {
                    $event->{conn}->privmsg($nick, "Please do not use \@nick to address people. Drop the @ symbol; it's not necessary and it's ugly. Doing this again will result in a temporary ban.");
                }

                default {
                    my $offenses = $self->{offenses}->{$channel}->{$nick}->{offenses} - 2;
                    my $length   = 60 * ($offenses * $offenses + 1);
                    $self->{pbot}->{banlist}->ban_user_timed(
                        $channel,
                        'b',
                        "*!*\@$host",
                        $length,
                        $self->{pbot}->{registry}->get_value('irc', 'botnick'),
                        'using @nick too much',
                    );
                    $self->{pbot}->{chanops}->gain_ops($channel);

                    $self->{pbot}->{event_queue}->enqueue_event(sub {
                            my ($event) = @_;
                            if (--$self->{offenses}->{$channel}->{$nick}->{offenses} <= 0) {
                                delete $self->{offenses}->{$channel}->{$nick};
                                delete $self->{offenses}->{$channel} if not keys %{$self->{offenses}->{$channel}};
                                $event->{repeating} = 0;
                            }
                        }, 60 * 60 * 24 * 2, "antitwitter $channel $nick", 1
                    );

                    $length = duration $length;
                    $event->{conn}->privmsg(
                        $nick,
                        "Please do not use \@nick to address people. Drop the @ symbol; it's not necessary and it's ugly. You were warned. You will be allowed to speak again in $length."
                    );
                }
            }
            last;
        }
    }
    return 0;
}

1;
