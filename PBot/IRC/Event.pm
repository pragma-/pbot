#####################################################################
#                                                                   #
#   Net::IRC -- Object-oriented Perl interface to an IRC server     #
#                                                                   #
#      Event.pm: The basic data type for any IRC occurrence.        #
#                                                                   #
#    Copyright (c) 2001 Pete Sergeant, Greg Bacon & Dennis Taylor.  #
#                       All rights reserved.                        #
#                                                                   #
#      This module is free software; you can redistribute or        #
#      modify it under the terms of Perl's Artistic License.        #
#                                                                   #
#####################################################################

# there used to be lots of cute little log quotes from #perl in here
#
# they're gone now because they made working on this already crappy
# code even more annoying... 'HI!!! I'm from #perl and so I don't
# write understandable, maintainable code!!! You see, i'm a perl
# badass, so I try to be as obscure as possible in everything I do!'
#
# Well, welcome to the real world, guys, where code needs to be
# maintainable and sane.

package PBot::IRC::Event;    # pragma_ 2011/21/01

use feature 'unicode_strings';
use utf8;

use strict;
our %_names;

# Constructor method for Net::IRC::Event objects.
# Takes at least 4 args:  the type of event
#                         the person or server that initiated the event
#                         the recipient(s) of the event, as arrayref or scalar
#                         the name of the format string for the event
#            (optional)   any number of arguments provided by the event
sub new {

    my $class = shift;

    my $type   = shift;
    my $from   = shift;
    my $to     = shift;
    my $format = shift;
    my $args   = \@_;

    my $self = {
        'type'   => $type,
        'from'   => undef,
        'to'     => ref($to) eq 'ARRAY' ? $to : [$to],
        'format' => $format,
        'args'   => [],
    };

    bless $self, $class;

    if   ($self->type !~ /\D/) { $self->type($self->trans($self->type)); }
    else                       { $self->type(lc($self->type)); }

    $self->from($from);    # sets nick, user, and host
    $self->args($args);    # strips colons from args

    return $self;
}

# Sets or returns an argument list for this event.
# Takes any number of args:  the arguments for the event.
sub args {
    my $self = shift;
    my $args = shift;

    if ($args) {
        my (@q, $i, $ct) = @{$args};    # This line is solemnly dedicated to \mjd.

        $self->{'args'} = [];
        while (@q) {
            $i = shift @q;
            next unless defined $i;

            if ($i =~ /^:/ and $ct) {    # Concatenate :-args.
                $i = join ' ', (substr($i, 1), @q);
                push @{$self->{'args'}}, $i;
                last;
            }
            push @{$self->{'args'}}, $i;
            $ct++;
        }
    }

    return @{$self->{'args'}};
}

# Dumps the contents of an event to STDERR so you can see what's inside.
# Takes no args.
sub dump {
    my ($self, $arg, $counter) = (shift, undef, 0);    # heh heh!

    printf STDERR "TYPE: %-30s    FORMAT: %-30s\n", $self->type, $self->format;
    print STDERR "FROM: ", $self->from, "\n";
    print STDERR "TO: ", join(", ", @{$self->to}), "\n";
    foreach $arg ($self->args) { print STDERR "Arg ", $counter++, ": ", $arg, "\n"; }
}

# Sets or returns the format string for this event.
# Takes 1 optional arg:  the new value for this event's "format" field.
sub format {
    my $self = shift;

    $self->{'format'} = $_[0] if @_;
    return $self->{'format'};
}

# Sets or returns the originator of this event
# Takes 1 optional arg:  the new value for this event's "from" field.
sub from {
    my $self = shift;
    my @part;

    if (@_) {
        # avoid certain irritating and spurious warnings from this line...
        {
            local $^W;
            @part = split /[\@!]/, $_[0], 3;
        }

        $self->nick(defined $part[0] ? $part[0] : '');
        $self->user(defined $part[1] ? $part[1] : '');
        $self->host(defined $part[2] ? $part[2] : '');
        defined $self->user ? $self->userhost($self->user . '@' . $self->host) : $self->userhost($self->host);
        $self->{'from'} = $_[0];
    }

    return $self->{'from'};
}

# Sets or returns the hostname of this event's initiator
# Takes 1 optional arg:  the new value for this event's "host" field.
sub host {
    my $self = shift;

    $self->{'host'} = $_[0] if @_;
    return $self->{'host'};
}

# Sets or returns the nick of this event's initiator
# Takes 1 optional arg:  the new value for this event's "nick" field.
sub nick {
    my $self = shift;

    $self->{'nick'} = $_[0] if @_;
    return $self->{'nick'};
}

# Sets or returns the recipient list for this event
# Takes any number of args:  this event's list of recipients.
sub to {
    my $self = shift;

    $self->{'to'} = [@_] if @_;
    return wantarray ? @{$self->{'to'}} : $self->{'to'};
}

# Sets or returns the type of this event
# Takes 1 optional arg:  the new value for this event's "type" field.
sub type {
    my $self = shift;

    $self->{'type'} = $_[0] if @_;
    return $self->{'type'};
}

# Sets or returns the username of this event's initiator
# Takes 1 optional arg:  the new value for this event's "user" field.
sub user {
    my $self = shift;

    $self->{'user'} = $_[0] if @_;
    return $self->{'user'};
}

# Just $self->user plus '@' plus $self->host, for convenience.
sub userhost {
    my $self = shift;

    $self->{'userhost'} = $_[0] if @_;
    return $self->{'userhost'};
}

# Simple sub for translating server numerics to their appropriate names.
# Takes one arg:  the number to be translated.
sub trans {
    shift if (ref($_[0]) || $_[0]) =~ /^PBot::IRC/;    # pragma_ 2011/21/01
    my $ev = shift;

    return (exists $_names{$ev} ? $_names{$ev} : undef);
}

%_names = (

    # suck!  these aren't treated as strings --
    # 001 ne 1 for the purpose of hash keying, apparently.
    '001' => "welcome",
    '002' => "yourhost",
    '003' => "created",
    '004' => "myinfo",
    '005' => "map",           # Undernet Extension, Kajetan@Hinner.com, 17/11/98
    '006' => "mapmore",       # Undernet Extension, Kajetan@Hinner.com, 17/11/98
    '007' => "mapend",        # Undernet Extension, Kajetan@Hinner.com, 17/11/98
    '008' => "snomask",       # Undernet Extension, Kajetan@Hinner.com, 17/11/98
    '009' => "statmemtot",    # Undernet Extension, Kajetan@Hinner.com, 17/11/98
    '010' => "statmem",       # Undernet Extension, Kajetan@Hinner.com, 17/11/98

    200 => "tracelink",
    201 => "traceconnecting",
    202 => "tracehandshake",
    203 => "traceunknown",
    204 => "traceoperator",
    205 => "traceuser",
    206 => "traceserver",
    208 => "tracenewtype",
    209 => "traceclass",
    211 => "statslinkinfo",
    212 => "statscommands",
    213 => "statscline",
    214 => "statsnline",
    215 => "statsiline",
    216 => "statskline",
    217 => "statsqline",
    218 => "statsyline",
    219 => "endofstats",
    220 => "statsbline",        # UnrealIrcd, Hendrik Frenzel
    221 => "umodeis",
    222 => "sqline_nick",       # UnrealIrcd, Hendrik Frenzel
    223 => "statsgline",        # UnrealIrcd, Hendrik Frenzel
    224 => "statstline",        # UnrealIrcd, Hendrik Frenzel
    225 => "statseline",        # UnrealIrcd, Hendrik Frenzel
    226 => "statsnline",        # UnrealIrcd, Hendrik Frenzel
    227 => "statsvline",        # UnrealIrcd, Hendrik Frenzel
    231 => "serviceinfo",
    232 => "endofservices",
    233 => "service",
    234 => "servlist",
    235 => "servlistend",
    241 => "statslline",
    242 => "statsuptime",
    243 => "statsoline",
    244 => "statshline",
    245 => "statssline",        # Reserved, Kajetan@Hinner.com, 17/10/98
    246 => "statstline",        # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    247 => "statsgline",        # Undernet Extension, Kajetan@Hinner.com, 17/10/98
### TODO: need numerics to be able to map to multiple strings
###           247 => "statsxline",             # UnrealIrcd, Hendrik Frenzel
    248 => "statsuline",        # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    249 => "statsdebug",        # Unspecific Extension, Kajetan@Hinner.com, 17/10/98
    250 => "luserconns",        # 1998-03-15 -- tkil
    251 => "luserclient",
    252 => "luserop",
    253 => "luserunknown",
    254 => "luserchannels",
    255 => "luserme",
    256 => "adminme",
    257 => "adminloc1",
    258 => "adminloc2",
    259 => "adminemail",
    261 => "tracelog",
    262 => "endoftrace",        # 1997-11-24 -- archon
    265 => "n_local",           # 1997-10-16 -- tkil
    266 => "n_global",          # 1997-10-16 -- tkil
    271 => "silelist",          # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    272 => "endofsilelist",     # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    275 => "statsdline",        # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    280 => "glist",             # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    281 => "endofglist",        # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    290 => "helphdr",           # UnrealIrcd, Hendrik Frenzel
    291 => "helpop",            # UnrealIrcd, Hendrik Frenzel
    292 => "helptlr",           # UnrealIrcd, Hendrik Frenzel
    293 => "helphlp",           # UnrealIrcd, Hendrik Frenzel
    294 => "helpfwd",           # UnrealIrcd, Hendrik Frenzel
    295 => "helpign",           # UnrealIrcd, Hendrik Frenzel

    300 => "none",
    301 => "away",
    302 => "userhost",
    303 => "ison",
    304 => "rpl_text",           # Bahamut IRCD
    305 => "unaway",
    306 => "nowaway",
    307 => "userip",             # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    308 => "rulesstart",         # UnrealIrcd, Hendrik Frenzel
    309 => "endofrules",         # UnrealIrcd, Hendrik Frenzel
    310 => "whoishelp",          # (July01-01)Austnet Extension, found by Andypoo <andypoo@secret.com.au>
    311 => "whoisuser",
    312 => "whoisserver",
    313 => "whoisoperator",
    314 => "whowasuser",
    315 => "endofwho",
    316 => "whoischanop",
    317 => "whoisidle",
    318 => "endofwhois",
    319 => "whoischannels",
    320 => "whoisvworld",        # (July01-01)Austnet Extension, found by Andypoo <andypoo@secret.com.au>
    321 => "liststart",
    322 => "list",
    323 => "listend",
    324 => "channelmodeis",
    329 => "channelcreate",      # 1997-11-24 -- archon
    330 => "whoisaccount",       # 2011-02-10 pragma_ for freenode
    331 => "notopic",
    332 => "topic",
    333 => "topicinfo",          # 1997-11-24 -- archon
    334 => "listusage",          # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    335 => "whoisbot",           # UnrealIrcd, Hendrik Frenzel
    341 => "inviting",
    342 => "summoning",
    346 => "invitelist",         # UnrealIrcd, Hendrik Frenzel
    347 => "endofinvitelist",    # UnrealIrcd, Hendrik Frenzel
    348 => "exlist",             # UnrealIrcd, Hendrik Frenzel
    349 => "endofexlist",        # UnrealIrcd, Hendrik Frenzel
    351 => "version",
    352 => "whoreply",
    353 => "namreply",
    354 => "whospcrpl",          # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    361 => "killdone",
    362 => "closing",
    363 => "closeend",
    364 => "links",
    365 => "endoflinks",
    366 => "endofnames",
    367 => "banlist",
    368 => "endofbanlist",
    369 => "endofwhowas",
    371 => "info",
    372 => "motd",
    373 => "infostart",
    374 => "endofinfo",
    375 => "motdstart",
    376 => "endofmotd",
    377 => "motd2",              # 1997-10-16 -- tkil
    378 => "austmotd",           # (July01-01)Austnet Extension, found by Andypoo <andypoo@secret.com.au>
    379 => "whoismodes",         # UnrealIrcd, Hendrik Frenzel
    381 => "youreoper",
    382 => "rehashing",
    383 => "youreservice",       # UnrealIrcd, Hendrik Frenzel
    384 => "myportis",
    385 => "notoperanymore",     # Unspecific Extension, Kajetan@Hinner.com, 17/10/98
    386 => "qlist",              # UnrealIrcd, Hendrik Frenzel
    387 => "endofqlist",         # UnrealIrcd, Hendrik Frenzel
    388 => "alist",              # UnrealIrcd, Hendrik Frenzel
    389 => "endofalist",         # UnrealIrcd, Hendrik Frenzel
    391 => "time",
    392 => "usersstart",
    393 => "users",
    394 => "endofusers",
    395 => "nousers",

    401 => "nosuchnick",
    402 => "nosuchserver",
    403 => "nosuchchannel",
    404 => "cannotsendtochan",
    405 => "toomanychannels",
    406 => "wasnosuchnick",
    407 => "toomanytargets",
    408 => "nosuchservice",        # UnrealIrcd, Hendrik Frenzel
    409 => "noorigin",
    411 => "norecipient",
    412 => "notexttosend",
    413 => "notoplevel",
    414 => "wildtoplevel",
    416 => "querytoolong",         # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    421 => "unknowncommand",
    422 => "nomotd",
    423 => "noadmininfo",
    424 => "fileerror",
    425 => "noopermotd",           # UnrealIrcd, Hendrik Frenzel
    431 => "nonicknamegiven",
    432 => "erroneusnickname",     # This iz how its speld in thee RFC.
    433 => "nicknameinuse",
    434 => "norules",              # UnrealIrcd, Hendrik Frenzel
    435 => "serviceconfused",      # UnrealIrcd, Hendrik Frenzel
    436 => "nickcollision",
    437 => "bannickchange",        # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    438 => "nicktoofast",          # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    439 => "targettoofast",        # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    440 => "servicesdown",         # Bahamut IRCD
    441 => "usernotinchannel",
    442 => "notonchannel",
    443 => "useronchannel",
    444 => "nologin",
    445 => "summondisabled",
    446 => "usersdisabled",
    447 => "nonickchange",         # UnrealIrcd, Hendrik Frenzel
    451 => "notregistered",
    455 => "hostilename",          # UnrealIrcd, Hendrik Frenzel
    459 => "nohiding",             # UnrealIrcd, Hendrik Frenzel
    460 => "notforhalfops",        # UnrealIrcd, Hendrik Frenzel
    461 => "needmoreparams",
    462 => "alreadyregistered",
    463 => "nopermforhost",
    464 => "passwdmismatch",
    465 => "yourebannedcreep",     # I love this one...
    466 => "youwillbebanned",
    467 => "keyset",
    468 => "invalidusername",      # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    469 => "linkset",              # UnrealIrcd, Hendrik Frenzel
    470 => "linkchannel",          # UnrealIrcd, Hendrik Frenzel
    471 => "channelisfull",
    472 => "unknownmode",
    473 => "inviteonlychan",
    474 => "bannedfromchan",
    475 => "badchannelkey",
    476 => "badchanmask",
    477 => "needreggednick",       # Bahamut IRCD
    478 => "banlistfull",          # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    479 => "secureonlychannel",    # pircd
### TODO: see above todo
###           479 => "linkfail",               # UnrealIrcd, Hendrik Frenzel
    480 => "cannotknock",          # UnrealIrcd, Hendrik Frenzel
    481 => "noprivileges",
    482 => "chanoprivsneeded",
    483 => "cantkillserver",
    484 => "ischanservice",        # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    485 => "killdeny",             # UnrealIrcd, Hendrik Frenzel
    486 => "htmdisabled",          # UnrealIrcd, Hendrik Frenzel
    489 => "secureonlychan",       # UnrealIrcd, Hendrik Frenzel
    491 => "nooperhost",
    492 => "noservicehost",

    501 => "umodeunknownflag",
    502 => "usersdontmatch",

    511 => "silelistfull",         # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    513 => "nosuchgline",          # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    513 => "badping",              # Undernet Extension, Kajetan@Hinner.com, 17/10/98
    518 => "noinvite",             # UnrealIrcd, Hendrik Frenzel
    519 => "admonly",              # UnrealIrcd, Hendrik Frenzel
    520 => "operonly",             # UnrealIrcd, Hendrik Frenzel
    521 => "listsyntax",           # UnrealIrcd, Hendrik Frenzel
    524 => "operspverify",         # UnrealIrcd, Hendrik Frenzel

    600 => "rpl_logon",            # Bahamut IRCD
    601 => "rpl_logoff",           # Bahamut IRCD
    602 => "rpl_watchoff",         # UnrealIrcd, Hendrik Frenzel
    603 => "rpl_watchstat",        # UnrealIrcd, Hendrik Frenzel
    604 => "rpl_nowon",            # Bahamut IRCD
    605 => "rpl_nowoff",           # Bahamut IRCD
    606 => "rpl_watchlist",        # UnrealIrcd, Hendrik Frenzel
    607 => "rpl_endofwatchlist",   # UnrealIrcd, Hendrik Frenzel
    610 => "mapmore",              # UnrealIrcd, Hendrik Frenzel
    640 => "rpl_dumping",          # UnrealIrcd, Hendrik Frenzel
    641 => "rpl_dumprpl",          # UnrealIrcd, Hendrik Frenzel
    642 => "rpl_eodump",           # UnrealIrcd, Hendrik Frenzel
    728 => "quietlist",            # freenode +q, pragma_ 12/12/2011
    729 => "endofquietlist",       # freenode +q, pragma_ 27/4/2020

    999 => "numericerror",         # Bahamut IRCD

    # add these events so that default handlers will kick in and handle them
    # pragma_ 10/30/2014
    'notice'     => 'notice',
    'public'     => 'public',
    'kick'       => 'kick',
    'mode'       => 'mode',
    'msg'        => 'msg',
    'disconnect' => 'disconnect',
    'part'       => 'part',
    'join'       => 'join',
    'caction'    => 'caction',
    'quit'       => 'quit',
    'nick'       => 'nick',
    'pong'       => 'pong',
    'invite'     => 'invite',
    'cap'        => 'cap',
    'account'    => 'account',
);

1;

__END__

=head1 NAME

Net::IRC::Event - A class for passing event data between subroutines

=head1 SYNOPSIS

None yet. These docs are under construction.

=head1 DESCRIPTION

This documentation is a subset of the main Net::IRC documentation. If
you haven't already, please "perldoc Net::IRC" before continuing.

Net::IRC::Event defines a standard interface to the salient information for
just about any event your client may witness on IRC. It's about as close as
we can get in Perl to a struct, with a few extra nifty features thrown in.

=head1 METHOD DESCRIPTIONS

This section is under construction, but hopefully will be finally written up
by the next release. Please see the C<irctest> script and the source for
details about this module.

=head1 LIST OF EVENTS

Net::IRC is an entirely event-based system, which takes some getting used to
at first. To interact with the IRC server, you tell Net::IRC's server
connection to listen for certain events and activate your own subroutines when
they occur. Problem is, this doesn't help you much if you don't know what to
tell it to look for. Below is a list of the possible events you can pass to
Net::IRC, along with brief descriptions of each... hope this helps.

=head2 Common events

=over

=item *

nick

The "nick" event is triggered when the client receives a NICK message, meaning
that someone on a channel with the client has changed eir nickname.

=item *

quit

The "quit" event is triggered upon receipt of a QUIT message, which means that
someone on a channel with the client has disconnected.

=item *

join

The "join" event is triggered upon receipt of a JOIN message, which means that
someone has entered a channel that the client is on.

=item *

part

The "part" event is triggered upon receipt of a PART message, which means that
someone has left a channel that the client is on.

=item *

mode

The "mode" event is triggered upon receipt of a MODE message, which means that
someone on a channel with the client has changed the channel's parameters.

=item *

topic

The "topic" event is triggered upon receipt of a TOPIC message, which means
that someone on a channel with the client has changed the channel's topic.

=item *

kick

The "kick" event is triggered upon receipt of a KICK message, which means that
someone on a channel with the client (or possibly the client itself!) has been
forcibly ejected.

=item *

public

The "public" event is triggered upon receipt of a PRIVMSG message to an entire
channel, which means that someone on a channel with the client has said
something aloud.

=item *

msg

The "msg" event is triggered upon receipt of a PRIVMSG message which is
addressed to one or more clients, which means that someone is sending the
client a private message. (Duh. :-)

=item *

notice

The "notice" event is triggered upon receipt of a NOTICE message, which means
that someone has sent the client a public or private notice. (Is that
sufficiently vague?)

=item *

ping

The "ping" event is triggered upon receipt of a PING message, which means that
the IRC server is querying the client to see if it's alive. Don't confuse this
with CTCP PINGs, explained later.

=item *

other

The "other" event is triggered upon receipt of any number of unclassifiable
miscellaneous messages, but you're not likely to see it often.

=item *

invite

The "invite" event is triggered upon receipt of an INVITE message, which means
that someone is permitting the client's entry into a +i channel.

=item *

kill

The "kill" event is triggered upon receipt of a KILL message, which means that
an IRC operator has just booted your sorry arse offline. Seeya!

=item *

disconnect

The "disconnect" event is triggered when the client loses its
connection to the IRC server it's talking to. Don't confuse it with
the "leaving" event. (See below.)

=item *

leaving

The "leaving" event is triggered just before the client deliberately
closes a connection to an IRC server, in case you want to do anything
special before you sign off.

=item *

umode

The "umode" event is triggered when the client changes its personal mode flags.

=item *

error

The "error" event is triggered when the IRC server complains to you about
anything. Sort of the evil twin to the "other" event, actually.

=back

=head2 CTCP Requests

=over

=item *

cping

The "cping" event is triggered when the client receives a CTCP PING request
from another user. See the irctest script for an example of how to properly
respond to this common request.

=item *

cversion

The "cversion" event is triggered when the client receives a CTCP VERSION
request from another client, asking for version info about its IRC client
program.

=item *

csource

The "csource" event is triggered when the client receives a CTCP SOURCE
request from another client, asking where it can find the source to its
IRC client program.

=item *

ctime

The "ctime" event is triggered when the client receives a CTCP TIME
request from another client, asking for the local time at its end.

=item *

cdcc

The "cdcc" event is triggered when the client receives a DCC request of any
sort from another client, attempting to establish a DCC connection.

=item *

cuserinfo

The "cuserinfo" event is triggered when the client receives a CTCP USERINFO
request from another client, asking for personal information from the client's
user.

=item *

cclientinfo

The "cclientinfo" event is triggered when the client receives a CTCP CLIENTINFO
request from another client, asking for whatever the hell "clientinfo" means.

=item *

cerrmsg

The "cerrmsg" event is triggered when the client receives a CTCP ERRMSG
request from another client, notifying it of a protocol error in a preceding
CTCP communication.

=item *

cfinger

The "cfinger" event is triggered when the client receives a CTCP FINGER
request from another client. How to respond to this should best be left up
to your own moral stance.

=item *

caction

The "caction" event is triggered when the client receives a CTCP ACTION
message from another client. I should hope you're getting the hang of how
Net::IRC handles CTCP requests by now...

=back

=head2 CTCP Responses

=over

=item *

crping

The "crping" event is triggered when the client receives a CTCP PING response
from another user. See the irctest script for an example of how to properly
respond to this common event.

=item *

crversion

The "crversion" event is triggered when the client receives a CTCP VERSION
response from another client.

=item *

crsource

The "crsource" event is triggered when the client receives a CTCP SOURCE
response from another client.

=item *

crtime

The "crtime" event is triggered when the client receives a CTCP TIME
response from another client.

=item *

cruserinfo

The "cruserinfo" event is triggered when the client receives a CTCP USERINFO
response from another client.

=item *

crclientinfo

The "crclientinfo" event is triggered when the client receives a CTCP
CLIENTINFO response from another client.

=item *

crfinger

The "crfinger" event is triggered when the client receives a CTCP FINGER
response from another client. I'm not even going to consider making a joke
about this one.

=back

=head2 DCC Events

=over

=item *

dcc_open

The "dcc_open" event is triggered when a DCC connection is established between
the client and another client.

=item *

dcc_update

The "dcc_update" event is triggered when any data flows over a DCC connection.
Useful for doing things like monitoring file transfer progress, for instance.

=item *

dcc_close

The "dcc_close" event is triggered when a DCC connection closes, whether from
an error or from natural causes.

=item *

chat

The "chat" event is triggered when the person on the other end of a DCC CHAT
connection sends you a message. Think of it as the private equivalent of "msg",
if you will.

=back

=head2 Numeric Events

=over

=item *

There's a whole lot of them, and they're well-described elsewhere. Please see
the IRC RFC (1495, at http://cs-ftp.bu.edu/pub/irc/support/IRC_RFC ) for a
detailed description, or the Net::IRC::Event.pm source code for a quick list.

=back

=head1 AUTHORS

Conceived and initially developed by Greg Bacon E<lt>gbacon@adtran.comE<gt> and
Dennis Taylor E<lt>dennis@funkplanet.comE<gt>.

Ideas and large amounts of code donated by Nat "King" Torkington E<lt>gnat@frii.comE<gt>.

Currently being hacked on, hacked up, and worked over by the members of the
Net::IRC developers mailing list. For details, see
http://www.execpc.com/~corbeau/irc/list.html .

=head1 URL

Up-to-date source and information about the Net::IRC project can be found at
http://netirc.betterbox.net/ .

=head1 SEE ALSO

=over

=item *

perl(1).

=item *

RFC 1459: The Internet Relay Chat Protocol

=item *

http://www.irchelp.org/, home of fine IRC resources.

=back

=cut

