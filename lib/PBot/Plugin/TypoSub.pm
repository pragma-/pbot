# File: TypoSub.pm
#
# Purpose: Replaces "typos" with "corrections".
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

# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::TypoSub;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize($self, %conf) {
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->on_public(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->on_public(@_) });
}

sub unload($self) {
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
}

sub on_public($self, $event_type, $event) {
    my ($nick, $user, $host, $msg) = ($event->nick, $event->user, $event->host, $event->args);

    my $channel = lc $event->{to}[0];

    ($nick, $user, $host) = $self->{pbot}->{irchandlers}->normalize_hostmask($nick, $user, $host);

    return 0 if $self->{pbot}->{ignorelist}->is_ignored($channel, "$nick!$user\@$host");

    my $nosubs = $self->{pbot}->{registry}->get_value($channel, 'notyposub');
    return 0 if defined $nosubs and $nosubs;

    return 0 if $self->{pbot}->{users}->get_loggedin_user_metadata($channel, "$nick!$user\@$host", 'notyposub');

    return 0 if $channel !~ m/^#/;
    return 0 if $event->{interpreted};

    if ($msg =~ m/^\s*s([[:punct:]])/) {
        my $separator = $1;
        my $sep       = quotemeta $separator;
        if ($msg =~ m/^\s*s${sep}(.*?)(?<!\\)${sep}(.*?)(?<!\\)${sep}([g]*).*$/ or $msg =~ m/^\s*s${sep}(.*?)(?<!\\)${sep}(.*)$/) {
            my ($regex, $replacement, $modifiers) = ($1, $2, $3);
            eval {
                use re::engine::RE2 -strict => 1;
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
                        if ($modifiers and $modifiers =~ m/g/) {
                            $text =~ s{$rx}
                            {
                                my @stuff = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
                                my $t = $replacement;
                                my $i = 0;
                                defined $_ || last, ++$i, $t =~ s|[\$\\]$i|$_|g for @stuff;
                                $t
                            }gxe;
                            $text = substr($text, 0, 350);
                        } else {
                            $text =~ s{$rx}
                            {
                                my $i = 0;
                                my @stuff = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
                                my $t = $replacement;
                                defined $_ || last, ++$i, $t =~ s|[\$\\]$i|$_|g for @stuff;
                                $t
                            }xe;
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
