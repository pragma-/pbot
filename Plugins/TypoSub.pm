# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::TypoSub;
use parent 'Plugins::Plugin';

# purpose: Replaces "typos" with "corrections".
#
# Examples:
#
# <alice> i like dogs
# <bob> s/dogs/cats/
# <PBot> bob thinks alice meant to say: i like cats
#
# <alice> i like candy
# <alice> s/like/love/
# <PBot> alice meant to say: i love candy

use warnings; use strict;
use feature 'unicode_strings';

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_public(@_) });
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
}

sub on_public {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
    my $channel = lc $event->{event}->{to}[0];

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    my $nosubs = $self->{pbot}->{registry}->get_value($channel, 'notyposub');
    return 0 if defined $nosubs and not $nosubs;

    return 0 if $channel !~ m/^#/;
    return 0 if $event->{interpreted};

    if ($msg =~ m/^\s*s([[:punct:]])/) {
        my $separator = $1;
        my $sep       = quotemeta $separator;
        if ($msg =~ m/^\s*s${sep}(.*?)(?<!\\)${sep}(.*?)(?<!\\)${sep}([g]*).*$/ or $msg =~ m/^\s*s${sep}(.*?)(?<!\\)${sep}(.*)$/) {
            my ($regex, $replacement, $modifiers) = ($1, $2, $3);
            eval {

                my $rx = qr/$regex/;

                my $messages = $self->{pbot}->{messagehistory}->{database}->get_recent_messages_from_channel($channel, 50, $self->{pbot}->{messagehistory}->{MSG_CHAT}, 'DESC');

                my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

                my $bot_trigger = $self->{pbot}->{registry}->get_value($channel, 'trigger') // $self->{pbot}->{registry}->get_value('general', 'trigger');

                my $ignore_commands = $self->{pbot}->{registry}->get_value($channel, 'typosub_ignore_commands') // $self->{pbot}->{registry}->get_value('typosub', 'ignore_commands')
                  // 1;

                foreach my $message (@$messages) {
                    next if $ignore_commands and $message->{msg} =~ m/^(?:$bot_trigger|$botnick.?)/;
                    next if $message->{msg}                      =~ m/^\s*s[[:punct:]](.*?)[[:punct:]](.*?)[[:punct:]]?g?\s*$/;

                    if ($message->{msg} =~ /$rx/) {
                        my $hostmask = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_id($message->{id});
                        my ($target) = $hostmask =~ m/([^!]+)/;
                        my $result;
                        if   ($nick eq $target) { $result = "$nick meant to say: "; }
                        else                    { $result = "$nick thinks $target meant to say: "; }
                        my $text = $message->{msg};
                        if ($modifiers =~ m/g/) {
                            $text =~ s/$rx/$replacement/g;
                            my @stuff = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
                            my $i;
                            map { ++$i; $text =~ s/[\$\\]$i/$_/g; } @stuff;
                        } else {
                            $text =~ s/$rx/$replacement/;
                            my @stuff = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
                            my $i;
                            map { ++$i; $text =~ s/[\$\\]$i/$_/g; } @stuff;
                        }
                        $event->{conn}->privmsg($channel, "$result$text");
                        return 0;
                    }
                }
            };

            if ($@) {
                my $error = "Error in `s${separator}${regex}${separator}${replacement}${separator}${modifiers}`: $@";
                $error =~ s/ at .*$//;
                $event->{conn}->privmsg($nick, $error);
                return 0;
            }
        }
    }
    return 0;
}
1;
