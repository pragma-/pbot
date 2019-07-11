#####################################################################
#                                                                   #
#   Net::IRC -- Object-oriented Perl interface to an IRC server     #
#                                                                   #
#   DCC.pm: An object for Direct Client-to-Client connections.      #
#                                                                   #
#          Copyright (c) 1997 Greg Bacon & Dennis Taylor.           #
#                       All rights reserved.                        #
#                                                                   #
#      This module is free software; you can redistribute or        #
#      modify it under the terms of Perl's Artistic License.        #
#                                                                   #
#####################################################################
# $Id: DCC.pm,v 1.1.1.1 2002/11/14 17:32:15 jmuhlich Exp $

package PBot::IRC::DCC; # pragma_ 2011/21/01

use strict;

use feature 'unicode_strings';

# --- #perl was here! ---
#
# The comments scattered throughout this module are excerpts from a
# log saved from one particularly surreal night on #perl. Ahh, the
# trials of being young, single, and drunk...
#
# ---------------------
#           \merlyn has offered the shower to a randon guy he met in a bar.
#  fimmtiu: Shower?
#           \petey raises an eyebrow at \merlyn
#  \merlyn: but he seems like a nice trucker guy...
#   archon: you offered to shower with a random guy?


# Methods that can be shared between the various DCC classes.
package PBot::IRC::DCC::Connection; # pragma_ 2011/21/01

use Carp;
use Socket;  # need inet_ntoa...
use strict;

sub fixaddr {
    my ($address) = @_;

    chomp $address;     # just in case, sigh.
    if ($address =~ /^\d+$/) {
        return inet_ntoa(pack "N", $address);
    } elsif ($address =~ /^[12]?\d{1,2}\.[12]?\d{1,2}\.[12]?\d{1,2}\.[12]?\d{1,2}$/) {
        return $address;
    } elsif ($address =~ tr/a-zA-Z//) {                    # Whee! Obfuscation!
        return inet_ntoa(((gethostbyname($address))[4])[0]);
    } else {
        return;
    }
}

sub bytes_in {
    return shift->{_bin};
}

sub bytes_out {
    return shift->{_bout};
}

sub nick {
    return shift->{_nick};
}

sub socket {
    return shift->{_socket};
}

sub time {
    return time - shift->{_time};
}

sub debug {
    return shift->{_debug};
}

# Changes here 1998-04-01 by MJD
# Optional third argument `$block'.
# If true, don't break the input into lines... just process it in blocks.
sub _getline {
    my ($self, $sock, $block) = @_;
    my ($input, $line);
    my $frag = $self->{_frag};

    if (defined $sock->recv($input, 10240)) {
	$frag .= $input;
	if (length($frag) > 0) {

            warn "Got ". length($frag) ." bytes from $sock\n"
                if $self->{_debug};

	    if ($block) {          # Block mode (GET)
		return $input;

	    } else {               # Line mode (CHAT)
		# We're returning \n's 'cause DCC's need 'em
		my @lines = split /\012/, $frag, -1;
		$lines[-1] .= "\012";
		$self->{_frag} = ($frag !~ /\012$/) ? pop @lines : '';
		return (@lines);
	    }
	}
	else {
	    # um, if we can read, i say we should read more than 0
	    # besides, recv isn't returning undef on closed
	    # sockets.  getting rid of this connection...

            warn "recv() received 0 bytes in _getline, closing connection.\n"
                if $self->{_debug};

	    $self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
							   $self->{_nick},
							   $self->{_socket},
							   $self->{_type}));
	    $self->{_parent}->parent->removefh($sock);
	    $self->{_socket}->close;
	    $self->{_fh}->close if $self->{_fh};
	    return;
	}
    } else {
	# Error, lets scrap this connection

        warn "recv() returned undef, socket error in _getline()\n"
            if $self->{_debug};

        $self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self->{_socket},
						       $self->{_type}));
	$self->{_parent}->parent->removefh($sock);
	$self->{_socket}->close;
	$self->{_fh}->close if $self->{_fh};
	return;
    }
}

sub DESTROY {
    my $self = shift;

    # Only do the Disconnection Dance of Death if the socket is still
    # live. Duplicate dcc_close events would be a Bad Thing.

    if ($self->{_socket}->opened) {
	$self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self->{_socket},
						       $self->{_type}));
	$self->{_socket}->close;
	close $self->{_fh} if $self->{_fh};
	$self->{_parent}->{_parent}->parent->removeconn($self);
    }

}

sub peer {
    return ( $_[0]->{_nick}, "DCC " . $_[0]->{_type} );
}

# -- #perl was here! --
#     orev: hehe...
# Silmaril: to, not with.
#   archon: heheh
# tmtowtdi: \merlyn will be hacked to death by a psycho
#   archon: yeah, but with is much more amusing


# Connection handling GETs
package PBot::IRC::DCC::GET; # pragma_ 2011/21/01

use IO::Socket;
use Carp;
use strict;

@PBot::IRC::DCC::GET::ISA = qw(Net::IRC::DCC::Connection); # pragma_ 2011/21/01

sub new {

    my ($class, $container, $nick, $address,
	$port, $size, $filename, $handle, $offset) = @_;
    my ($sock, $fh);

    # get the address into a dotted quad
    $address = &PBot::IRC::DCC::Connection::fixaddr($address); # pragma_ 2011/21/01
    return if $port < 1024 or not defined $address or $size < 1;

    $fh = defined $handle ? $handle : IO::File->new(">$filename");

    unless (defined $fh) {
        carp "Can't open $filename for writing: $!";
        $sock = new IO::Socket::INET( Proto    => "tcp",
				      PeerAddr => "$address:$port" ) and
        $sock->close();
        return;
    }

    binmode $fh;                     # I love this next line. :-)
    ref $fh eq 'GLOB' ? select((select($fh), $|++)[0]) : $fh->autoflush(1);

    $sock = new IO::Socket::INET( Proto    => "tcp",
				  PeerAddr => "$address:$port" );

    if (defined $sock) {
	$container->handler(PBot::IRC::Event->new('dcc_open', # pragma_ 2011/21/01
						 $nick,
						 $sock,
						 'get',
						 'get', $sock));

    } else {
        carp "Can't connect to $address: $!";
        close $fh;
        return;
    }

    $sock->autoflush(1);

    my $self = {
	_bin        =>  defined $offset ? $offset : 0, # bytes recieved so far
        _bout       =>  0,      # Bytes we've sent
        _connected  =>  1,
	_debug      =>  $container->debug,
        _fh         =>  $fh,    # FileHandle we will be writing to.
        _filename   =>  $filename,
	_frag       =>  '',
	_nick       =>  $nick,  # Nick of person on other end
        _parent     =>  $container,
        _size       =>  $size,  # Expected size of file
        _socket     =>  $sock,  # Socket we're reading from
        _time       =>  time,
	_type       =>  'GET',
        };

    bless $self, $class;

    return $self;
}

# -- #perl was here! --
#  \merlyn: we were both ogling a bartender named arley
#  \merlyn: I mean carle
#  \merlyn: carly
# Silmaril: man merlyn
# Silmaril: you should have offered HER the shower.
#   \petey: all three of them?

sub parse {
    my ($self) = shift;

    my $line = $self->_getline($_[0], 'BLOCKS');

    next unless defined $line;
    unless (print {$self->{_fh}} $line) {
	carp ("Error writing to " . $self->{_filename} . ": $!");
	close $self->{_fh};
	$self->{_parent}->parent->removeconn($self);
	$self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self->{_socket},
						       $self->{_type}));
	$self->{_socket}->close;
	return;
    }

    $self->{_bin} += length($line);


    # confirm the packet we've just recieved
    unless ( $self->{_socket}->send( pack("N", $self->{_bin}) ) ) {
	carp "Error writing to DCC GET socket: $!";
	close $self->{_fh};
	$self->{_parent}->parent->removeconn($self);
	$self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self->{_socket},
						       $self->{_type}));
	$self->{_socket}->close;
	return;
    }

    $self->{_bout} += 4;

    # The file is done.
    # If we close the socket, the select loop gets screwy because
    # it won't remove its reference to the socket.
    if ( $self->{_size} and $self->{_size} <= $self->{_bin} ) {
        close $self->{_fh};
        $self->{_parent}->parent->removeconn($self);
        $self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
                                                       $self->{_nick},
                                                       $self->{_socket},
                                                       $self->{_type}));
	$self->{_socket}->close;
        return;
    }

    $self->{_parent}->handler(PBot::IRC::Event->new('dcc_update', # pragma_ 2011/21/01
                                                   $self->{_nick},
                                                   $self,
                                                   $self->{_type},
                                                   $self ));
}

sub filename {
    return shift->{_filename};
}

sub size {
    return shift->{_size};
}

sub close {
    my ($self, $sock) = @_;
    $self->{_fh}->close;
    $self->{_parent}->parent->removeconn($self);
    $self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
                                                  $self->{_nick},
                                                  $self->{_socket},
                                                  $self->{_type}));
    $self->{_socket}->close;
    return;
}

# -- #perl was here! --
#  \merlyn: I can't type... she created a numbner of very good drinks
#  \merlyn: She's still at work
#           \petey resists mentioning that there's "No manual entry
#           for merlyn."
# Silmaril: Haven't you ever seen swingers?
#  \merlyn: she's off tomorrow... will meet me at the bar at 9:30
# Silmaril: AWWWWwwww yeeeaAAHH.
#   archon: waka chica waka chica


# Connection handling SENDs
package PBot::IRC::DCC::SEND; # pragma_ 2011/21/01
@PBot::IRC::DCC::SEND::ISA = qw(Net::IRC::DCC::Connection); # pragma_ 2011/21/01

use IO::File;
use IO::Socket;
use Carp;
use strict;

sub new {

    my ($class, $container, $nick, $filename, $blocksize) = @_;
    my ($size, $port, $fh, $sock, $select);

    $blocksize ||= 1024;

    # Shell-safe DCC filename stuff. Trying to prank-proof this
    # module is rather difficult.
    $filename =~ tr/a-zA-Z.+0-9=&()[]%\-\\\/:,/_/c;
    $fh = new IO::File $filename;

    unless (defined $fh) {
        carp "Couldn't open $filename for reading: $!";
	return;
    }

    binmode $fh;
    $fh->seek(0, SEEK_END);
    $size = $fh->tell;
    $fh->seek(0, SEEK_SET);

    $sock = new IO::Socket::INET( Proto     => "tcp",
                                  Listen    => 1);

    unless (defined $sock) {
        carp "Couldn't open DCC SEND socket: $!";
        $fh->close;
        return;
    }

    $container->ctcp('DCC SEND', $nick, $filename,
                     unpack("N",inet_aton($container->hostname())),
		     $sock->sockport(), $size);

    $sock->autoflush(1);

    my $self = {
        _bin        =>  0,         # Bytes we've recieved thus far
        _blocksize  =>  $blocksize,
        _bout       =>  0,         # Bytes we've sent
	_debug      =>  $container->debug,
        _fh         =>  $fh,       # FileHandle we will be reading from.
        _filename   =>  $filename,
	_frag       =>  '',
	_nick       =>  $nick,
        _parent     =>  $container,
        _size       =>  $size,     # Size of file
        _socket     =>  $sock,     # Socket we're writing to
        _time       =>  0,         # This gets set by Accept->parse()
	_type       =>  'SEND',
    };

    bless $self, $class;

    $sock = PBot::IRC::DCC::Accept->new($sock, $self); # pragma_ 2011/21/01

    unless (defined $sock) {
        carp "Error in accept: $!";
        $fh->close;
        return;
    }

    return $self;
}

# -- #perl was here! --
#  fimmtiu: So a total stranger is using your shower?
#  \merlyn: yes... a total stranger is using my hotel shower
#           Stupid coulda sworn \merlyn was married...
#   \petey: and you have a date.
#  fimmtiu: merlyn isn't married.
#   \petey: not a bad combo......
#  \merlyn: perhaps a adate
#  \merlyn: not maerried
#  \merlyn: not even sober. --)

sub parse {
    my ($self, $sock) = @_;
    my $size = ($self->_getline($sock, 1))[0];
    my $buf;

    # i don't know how useful this is, but let's stay consistent
    $self->{_bin} += 4;

    unless (defined $size) {
	# Dang! The other end unexpectedly canceled.
        carp (($self->peer)[1] . " connection to " .
	      ($self->peer)[0] . " lost");
	$self->{_fh}->close;
	$self->{_parent}->parent->removefh($sock);
        $self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self->{_socket},
						       $self->{_type}));
	$self->{_socket}->close;
	return;
    }

    $size = unpack("N", $size);

    if ($size >= $self->{_size}) {

	if ($self->{_debug}) {
	    warn "Other end acknowledged entire file ($size >= ",
		$self->{_size}, ")";
	}
        # they've acknowledged the whole file,  we outtie
        $self->{_fh}->close;
        $self->{_parent}->parent->removeconn($self);
        $self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self->{_socket},
						       $self->{_type}));
	$self->{_socket}->close;
        return;
    }

    # we're still waiting for acknowledgement,
    # better not send any more
    return if $size < $self->{_bout};

    unless (defined $self->{_fh}->read($buf,$self->{_blocksize})) {

	if ($self->{_debug}) {
	    warn "Failed to read from source file in DCC SEND!";
	}
	$self->{_fh}->close;
        $self->{_parent}->parent->removeconn($self);
	$self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self->{_socket},
						       $self->{_type}));
	$self->{_socket}->close;
        return;
    }

    unless ($self->{_socket}->send($buf)) {

	if ($self->{_debug}) {
	    warn "send() failed horribly in DCC SEND"
	}
        $self->{_fh}->close;
        $self->{_parent}->parent->removeconn($self);
        $self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self->{_socket},
						       $self->{_type}));
	$self->{_socket}->close;
	return;
    }

    $self->{_bout} += length($buf);

    $self->{_parent}->handler(PBot::IRC::Event->new('dcc_update', # pragma_ 2011/21/01
						   $self->{_nick},
						   $self,
						   $self->{_type},
						   $self ));

    return 1;
}

# -- #perl was here! --
#  fimmtiu: Man, merlyn, you must be drunk to type like that. :)
#  \merlyn: too many longislands.
#  \merlyn: she made them strong
#   archon: it's a plot
#  \merlyn: not even a good amoun tof coke
#   archon: she's in league with the guy in your shower
#   archon: she gets you drunk and he takes your wallet!


# handles CHAT connections
package PBot::IRC::DCC::CHAT; # pragma_ 2011/21/01
@PBot::IRC::DCC::CHAT::ISA = qw(Net::IRC::DCC::Connection); # pragma_ 2011/21/01

use IO::Socket;
use Carp;
use strict;

sub new {

    my ($class, $container, $type, $nick, $address, $port) = @_;
    my ($sock, $self);

    if ($type) {
        # we're initiating

        $sock = new IO::Socket::INET( Proto     => "tcp",
                                      Listen    => 1);

        unless (defined $sock) {
            carp "Couldn't open DCC CHAT socket: $!";
            return;
        }

	$sock->autoflush(1);
        $container->ctcp('DCC CHAT', $nick, 'chat',
                         unpack("N",inet_aton($container->hostname)),
						        $sock->sockport());

	$self = {
	    _bin        =>  0,      # Bytes we've recieved thus far
	    _bout       =>  0,      # Bytes we've sent
	    _connected  =>  1,
	    _debug      =>  $container->debug,
	    _frag       =>  '',
	    _nick       =>  $nick,  # Nick of the client on the other end
	    _parent     =>  $container,
	    _socket     =>  $sock,  # Socket we're reading from
	    _time       =>  0,      # This gets set by Accept->parse()
	    _type       =>  'CHAT',
	};

	bless $self, $class;

        $sock = PBot::IRC::DCC::Accept->new($sock, $self); # pragma_ 2011/21/01

	unless (defined $sock) {
	    carp "Error in DCC CHAT connect: $!";
	    return;
	}

    } else {      # we're connecting

        $address = &PBot::IRC::DCC::Connection::fixaddr($address); # pragma_ 2011/21/01
	return if $port < 1024 or not defined $address;

        $sock = new IO::Socket::INET( Proto    => "tcp",
				      PeerAddr => "$address:$port");

        if (defined $sock) {
	    $container->handler(PBot::IRC::Event->new('dcc_open', # pragma_ 2011/21/01
						     $nick,
						     $sock,
						     'chat',
						     'chat', $sock));
	} else {
	    carp "Error in DCC CHAT connect: $!";
	    return;
	}

	$sock->autoflush(1);

	$self = {
	    _bin        =>  0,      # Bytes we've recieved thus far
	    _bout       =>  0,      # Bytes we've sent
	    _connected  =>  1,
	    _nick       =>  $nick,  # Nick of the client on the other end
	    _parent     =>  $container,
	    _socket     =>  $sock,  # Socket we're reading from
	    _time       =>  time,
	    _type       =>  'CHAT',
	};

	bless $self, $class;

	$self->{_parent}->parent->addfh($self->socket,
					$self->can('parse'), 'r', $self);
    }

    return $self;
}

# -- #perl was here! --
#  \merlyn: tahtd be coole
#           KTurner bought the camel today, so somebody can afford one
#           more drink... ;)
# tmtowtdi: I've heard of things like this...
#  \merlyn: as an experience. that is.
#   archon: i can think of cooler things (;
#  \merlyn: I don't realiy have that mch in my wallet.

sub parse {
    my ($self, $sock) = @_;

    foreach my $line ($self->_getline($sock)) {
	return unless defined $line;

	$self->{_bin} += length($line);

	return undef if $line eq "\012";
	$self->{_bout} += length($line);

	$self->{_parent}->handler(PBot::IRC::Event->new('chat', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self->{_socket},
						       'chat',
						       $line));

	$self->{_parent}->handler(PBot::IRC::Event->new('dcc_update', # pragma_ 2011/21/01
						       $self->{_nick},
						       $self,
						       $self->{_type},
						       $self ));
    }
}

# Sends a message to a channel or person.
# Takes 2 args:  the target of the message (channel or nick)
#                the text of the message to send
sub privmsg {
    my ($self) = shift;

    unless (@_) {
	croak 'Not enough arguments to privmsg()';
    }

    # Don't send a CR over DCC CHAT -- it's not wanted.
    $self->socket->send(join('', @_) . "\012");
}


# -- #perl was here! --
#  \merlyn: this girl carly at the bar is aBABE
#   archon: are you sure? you don't sound like you're in a condition to
#           judge such things (;
# *** Stupid has set the topic on channel #perl to \merlyn is shit-faced
#     with a trucker in the shower.
# tmtowtdi: uh, yeah...
#  \merlyn: good topic


# Sockets waiting for accept() use this to shoehorn into the select loop.
package PBot::IRC::DCC::Accept; # pragma_ 2011/21/01

@PBot::IRC::DCC::Accept::ISA = qw(Net::IRC::DCC::Connection); # pragma_ 2011/21/01
use Carp;
use Socket;   # we use a lot of Socket functions in parse()
use strict;


sub new {
    my ($class, $sock, $parent) = @_;
    my ($self);

    $self = { _debug    =>  $parent->debug,
	      _nonblock =>  1,
	      _socket   =>  $sock,
	      _parent   =>  $parent,
	      _type     =>  'accept',
	  };

    bless $self, $class;

    # Tkil's gonna love this one. :-)   But what the hell... it's safe to
    # assume that the only thing initiating DCCs will be Connections, right?
    # Boy, we're not built for extensibility, I guess. Someday, I'll clean
    # all of the things like this up.
    $self->{_parent}->{_parent}->parent->addconn($self);
    return $self;
}

sub parse {
    my ($self) = shift;
    my ($sock);

    $sock = $self->{_socket}->accept;
    $self->{_parent}->{_socket} = $sock;
    $self->{_parent}->{_time} = time;

    if ($self->{_parent}->{_type} eq 'SEND') {
	# ok, to get the ball rolling, we send them the first packet.
	my $buf;
	unless (defined $self->{_parent}->{_fh}->
		read($buf, $self->{_parent}->{_blocksize})) {
	    return;
	}
	unless (defined $sock->send($buf)) {
	    $sock->close;
	    $self->{_parent}->{_fh}->close;
	    $self->{_parent}->{_parent}->parent->removefh($sock);
	    $self->{_parent}->handler(PBot::IRC::Event->new('dcc_close', # pragma_ 2011/21/01
							   $self->{_nick},
							   $self->{_socket},
							   $self->{_type}));
	    $self->{_socket}->close;
	    return;
	}
    }

    $self->{_parent}->{_parent}->parent->addconn($self->{_parent});
    $self->{_parent}->{_parent}->parent->removeconn($self);

    $self->{_parent}->{_parent}->handler(PBot::IRC::Event-> # pragma_ 2011/21/01
					 new('dcc_open',
					     $self->{_parent}->{_nick},
					     $self->{_parent}->{_socket},
					     $self->{_parent}->{_type},
					     $self->{_parent}->{_type},
					     $self->{_parent}->{_socket})
					 );
}



1;


__END__

=head1 NAME

Net::IRC::DCC - Object-oriented interface to a single DCC connection

=head1 SYNOPSIS

Hard hat area: This section under construction.

=head1 DESCRIPTION

This documentation is a subset of the main Net::IRC documentation. If
you haven't already, please "perldoc Net::IRC" before continuing.

Net::IRC::DCC defines a few subclasses that handle DCC CHAT, GET, and SEND
requests for inter-client communication. DCC objects are created by
C<Connection-E<gt>new_{chat,get,send}()> in much the same way that
C<IRC-E<gt>newconn()> creates a new connection object.

=head1 METHOD DESCRIPTIONS

This section is under construction, but hopefully will be finally written up
by the next release. Please see the C<irctest> script and the source for
details about this module.

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
