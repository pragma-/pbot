# File: NickServ.pm
#
# Purpose: Handles NickServ-related IRC events.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::IRCHandlers::NickServ;

use PBot::Imports;

sub new {
    my ($class, %args) = @_;

    # ensure class was passed a PBot instance
    if (not exists $args{pbot}) {
        Carp::croak("Missing pbot reference to $class");
    }

    my $self = bless { pbot => $args{pbot} }, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    # NickServ-related IRC events get priority 10
    # priority is from 0 to 100 where 0 is highest and 100 is lowest
    $self->{pbot}->{event_dispatcher}->register_handler('irc.welcome',       sub { $self->on_welcome       (@_) }, 10);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.notice',        sub { $self->on_notice        (@_) }, 10);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.nicknameinuse', sub { $self->on_nicknameinuse (@_) }, 10);
}

sub on_welcome {
    my ($self, $event_type, $event) = @_;

    # if not using SASL, identify the old way by msging NickServ or some services bot
    if (not $self->{pbot}->{irc_capabilities}->{sasl}) {
        if (length $self->{pbot}->{registry}->get_value('irc', 'identify_password')) {
            my $nickserv = $self->{pbot}->{registry}->get_value('general', 'identify_nick')    // 'NickServ';
            my $command  = $self->{pbot}->{registry}->get_value('general', 'identify_command') // 'identify $nick $password';

            $self->{pbot}->{logger}->log("Identifying with $nickserv . . .\n");

            my $botnick  = $self->{pbot}->{registry}->get_value('irc', 'botnick');
            my $password = $self->{pbot}->{registry}->get_value('irc', 'identify_password');

            $command =~ s/\$nick\b/$botnick/g;
            $command =~ s/\$password\b/$password/g;

            $event->{conn}->privmsg($nickserv, $command);
        } else {
            $self->{pbot}->{logger}->log("No identify password; skipping identification to services.\n");
        }

        # auto-join channels unless general.autojoin_wait_for_nickserv is true
        if (not $self->{pbot}->{registry}->get_value('general', 'autojoin_wait_for_nickserv')) {
            $self->{pbot}->{logger}->log("Autojoining channels immediately; to wait for services set general.autojoin_wait_for_nickserv to 1.\n");
            $self->{pbot}->{channels}->autojoin;
        } else {
            $self->{pbot}->{logger}->log("Waiting for services identify response before autojoining channels.\n");
        }

        return 1;
    }

    # event not handled
    return undef;
}

sub on_notice {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host, $to, $text)  = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host,
        $event->{event}->to,
        $event->{event}->{args}->[0],
    );

    my $nickserv = $self->{pbot}->{registry}->get_value('general', 'identify_nick') // 'NickServ';

    # notice from NickServ
    if (lc $nick eq lc $nickserv) {
        # log notice
        $self->{pbot}->{logger}->log("NOTICE from $nick!$user\@$host to $to: $text\n");

        # if we have enabled NickServ GUARD protection and we're not identified yet,
        # NickServ will warn us to identify -- this is our cue to identify.
        if ($text =~ m/This nickname is registered/) {
            if (length $self->{pbot}->{registry}->get_value('irc', 'identify_password')) {
                $self->{pbot}->{logger}->log("Identifying with NickServ . . .\n");
                $event->{conn}->privmsg("nickserv", "identify " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));
            }
        }
        elsif ($text =~ m/You are now identified/) {
            # we have identified with NickServ
            if ($self->{pbot}->{registry}->get_value('irc', 'randomize_nick')) {
                # if irc.randomize_nicks was enabled, we go ahead and attempt to
                # change to our real botnick. we don't auto-join channels just yet in case
                # the nick change fails.
                $event->{conn}->nick($self->{pbot}->{registry}->get_value('irc', 'botnick'));
            } else {
                # otherwise go ahead and autojoin channels now
                $self->{pbot}->{channels}->autojoin;
            }
        }
        elsif ($text =~ m/has been ghosted/) {
            # we have ghosted someone using our botnick, let's attempt to regain it now
            $event->{conn}->nick($self->{pbot}->{registry}->get_value('irc', 'botnick'));
        }

        return 1;
    }

    # event not handled
    return undef;
}

sub on_nicknameinuse {
    my ($self, $event_type, $event) = @_;

    my (undef, $nick, $msg)   = $event->{event}->args;
    my $from = $event->{event}->from;

    $self->{pbot}->{logger}->log("Received nicknameinuse for nick $nick from $from: $msg\n");

    # attempt to use NickServ GHOST command to kick nick off
    $event->{conn}->privmsg("nickserv", "ghost $nick " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));

    return 1;
}

1;
