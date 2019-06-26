#####################################################################
#                                                                   #
#   Net::IRC -- Object-oriented Perl interface to an IRC server     #
#                                                                   #
#   IRC.pm: A nifty little wrapper that makes your life easier.     #
#                                                                   #
#          Copyright (c) 1997 Greg Bacon & Dennis Taylor.           #
#                       All rights reserved.                        #
#                                                                   #
#      This module is free software; you can redistribute or        #
#      modify it under the terms of Perl's Artistic License.        #
#                                                                   #
#####################################################################
# $Id: IRC.pm,v 1.10 2004/04/30 18:02:51 jmuhlich Exp $


package PBot::IRC; # pragma_ 2011/01/21

BEGIN { require 5.004; }    # needs IO::* and $coderef->(@args) syntax

use PBot::IRC::Connection; # pragma_ 2011/01/21
use PBot::IRC::EventQueue; # pragma_ 2011/01/21
use IO::Select;
use Carp;


# grab the drop-in replacement for time() from Time::HiRes, if it's available
BEGIN {
   Time::HiRes->import('time') if eval "require Time::HiRes";
}


use strict;
use vars qw($VERSION);

$VERSION = "0.79";

sub new {
  my $proto = shift;

  my $self = {
    '_conn'             => [],
    '_connhash'         => {},
    '_error'            => IO::Select->new(),
    '_debug'            => 0,
    '_schedulequeue'    => new PBot::IRC::EventQueue(), # pragma_ 2011/01/21
    '_outputqueue'      => new PBot::IRC::EventQueue(), # pragma_ 2011/01/21
    '_read'             => IO::Select->new(),
    '_timeout'          => 1,
    '_write'            => IO::Select->new(),
  };

  bless $self, $proto;

  return $self;
}

sub outputqueue {
  my $self = shift;
  return $self->{_outputqueue};
}

sub schedulequeue {
  my $self = shift;
  return $self->{_schedulequeue};
}

# Front end to addfh(), below. Sets it to read by default.
# Takes at least 1 arg:  an object to add to the select loop.
#           (optional)   a flag string to pass to addfh() (see below)
sub addconn {
  my ($self, $conn) = @_;

  $self->addfh( $conn->socket, $conn->can('parse'), ($_[2] || 'r'), $conn);
}

# Adds a filehandle to the select loop. Tasty and flavorful.
# Takes 3 args:  a filehandle or socket to add
#                a coderef (can be undef) to pass the ready filehandle to for
#                  user-specified reading/writing/error handling.
#    (optional)  a string with r/w/e flags, similar to C's fopen() syntax,
#                  except that you can combine flags (i.e., "rw").
#    (optional)  an object that the coderef is a method of
sub addfh {
  my ($self, $fh, $code, $flag, $obj) = @_;
  my ($letter);

  die "Not enough arguments to IRC->addfh()" unless defined $code;

  if ($flag) {
    foreach $letter (split(//, lc $flag)) {
      if ($letter eq 'r') {
        $self->{_read}->add( $fh );
      } elsif ($letter eq 'w') {
        $self->{_write}->add( $fh );
      } elsif ($letter eq 'e') {
        $self->{_error}->add( $fh );
      }
    }
  } else {
    $self->{_read}->add( $fh );
  }

  $self->{_connhash}->{$fh} = [ $code, $obj ];
}

# Sets or returns the debugging flag for this object.
# Takes 1 optional arg: a new boolean value for the flag.
sub debug {
  my $self = shift;

  if (@_) {
    $self->{_debug} = $_[0];
  }
  return $self->{_debug};
}

# Goes through one iteration of the main event loop. Useful for integrating
# other event-based systems (Tk, etc.) with Net::IRC.
# Takes no args.
sub do_one_loop {
  my $self = shift;
  my ($ev, $sock, $time, $nexttimer, $timeout);
  my (undef, undef, undef, $caller) = caller(1);

  $time = time();             # no use calling time() all the time.

  if (!$self->outputqueue->is_empty) {
    my $outputevent = undef;
    while (defined($outputevent = $self->outputqueue->head)
          && $outputevent->time <= $time) {
      $outputevent = $self->outputqueue->dequeue();
      $outputevent->content->{coderef}->(@{$outputevent->content->{args}});
    }
    $nexttimer = $self->outputqueue->head->time if !$self->outputqueue->is_empty();
  }

  # we don't want to bother waiting on input or running
  # scheduled events if we're just flushing the output queue
  # so we bail out here
  return if $caller eq 'PBot::IRC::flush_output_queue'; # pragma_ 2011/01/21

  # Check the queue for scheduled events to run.
  if (!$self->schedulequeue->is_empty) {
    my $scheduledevent = undef;
    while (defined($scheduledevent = $self->schedulequeue->head) && $scheduledevent->time <= $time) {
      $scheduledevent = $self->schedulequeue->dequeue();
      $scheduledevent->content->{coderef}->(@{$scheduledevent->content->{args}});
    }
    if (!$self->schedulequeue->is_empty()
       && $nexttimer
       && $self->schedulequeue->head->time < $nexttimer) {
      $nexttimer = $self->schedulequeue->head->time;
    }
  }

  # Block until input arrives, then hand the filehandle over to the
  # user-supplied coderef. Look! It's a freezer full of government cheese!

  if ($nexttimer) {
    $timeout = $nexttimer - $time < $self->{_timeout}
    ? $nexttimer - $time : $self->{_timeout};
  } else {
    $timeout = $self->{_timeout};
  }
  foreach $ev (IO::Select->select($self->{_read},
                                  $self->{_write},
                                  $self->{_error},
                                  $timeout)) {
    foreach $sock (@{$ev}) {
      my $conn = $self->{_connhash}->{$sock};
      $conn or next;

      # $conn->[0] is a code reference to a handler sub.
      # $conn->[1] is optionally an object which the
      #    handler sub may be a method of.

      $conn->[0]->($conn->[1] ? ($conn->[1], $sock) : $sock);
    }
  }
}

sub flush_output_queue {
  my $self = shift;

  while (!$self->outputqueue->is_empty()) {
    $self->do_one_loop();
  }
}

# Creates and returns a new Connection object.
# Any args here get passed to Connection->connect().
sub newconn {
  my $self = shift;
  my $conn = PBot::IRC::Connection->new($self, @_); # pragma_ 2011/01/21

  return if $conn->error;
  return $conn;
}

# Takes the args passed to it by Connection->schedule()... see it for details.
sub enqueue_scheduled_event {
  my $self = shift;
  my $time = shift;
  my $coderef = shift;
  my @args = @_;

  return $self->schedulequeue->enqueue($time, { coderef => $coderef, args => \@args });
}

# Takes a scheduled event ID to remove from the queue.
# Returns the deleted coderef, if you actually care.
sub dequeue_scheduled_event {
  my ($self, $id) = @_;
  $self->schedulequeue->dequeue($id);
}

# Takes the args passed to it by Connection->schedule()... see it for details.
sub enqueue_output_event {
  my $self = shift;
  my $time = shift;
  my $coderef = shift;
  my @args = @_;

  return $self->outputqueue->enqueue($time, { coderef => $coderef, args => \@args });
}

# Takes a scheduled event ID to remove from the queue.
# Returns the deleted coderef, if you actually care.
sub dequeue_output_event {
  my ($self, $id) = @_;
  $self->outputqueue->dequeue($id);
}

# Front-end for removefh(), below.
# Takes 1 arg:  a Connection (or DCC or whatever) to remove.
sub removeconn {
  my ($self, $conn) = @_;

  $self->removefh( $conn->socket );
}

# Given a filehandle, removes it from all select lists. You get the picture.
sub removefh {
  my ($self, $fh) = @_;

  $self->{_read}->remove( $fh );
  $self->{_write}->remove( $fh );
  $self->{_error}->remove( $fh );
  delete $self->{_connhash}->{$fh};
}

# Begin the main loop. Wheee. Hope you remembered to set up your handlers
# first... (takes no args, of course)
sub start {
  my $self = shift;

  while (1) {
    $self->do_one_loop();
  }
}

# Sets or returns the current timeout, in seconds, for the select loop.
# Takes 1 optional arg:  the new value for the timeout, in seconds.
# Fractional timeout values are just fine, as per the core select().
sub timeout {
  my $self = shift;

  if (@_) { $self->{_timeout} = $_[0] }
  return $self->{_timeout};
}

1;


__END__


=head1 NAME

Net::IRC - DEAD SINCE 2004 Perl interface to the Internet Relay Chat protocol

=head1 USE THESE INSTEAD

This module has been abandoned and is no longer developed. This release serves
only to warn current and future users about this and to direct them to supported
and actively-developed libraries for connecting Perl to IRC. Most new users will
want to use L<Bot::BasicBot>, whereas more advanced users will appreciate the
flexibility offered by L<POE::Component::IRC>. We understand that porting code
to a new framework can be difficult. Please stop by #perl on irc.freenode.net
and we'll be happy to help you out with bringing your bots into the modern era.

=head1 SYNOPSIS

    use Net::IRC;

    $irc = new Net::IRC;
    $conn = $irc->newconn(Nick    => 'some_nick',
                          Server  => 'some.irc.server.com',
	                  Port    =>  6667,
			  Ircname => 'Some witty comment.');
    $irc->start;

=head1 DESCRIPTION

This module has been abandoned and deprecated since 2004. The original authors
have moved onto L<POE::Component::IRC> and more modern techniques. This
distribution is not maintained and only uploaded to present successively louder
"don't use this" warnings to those unaware.

Welcome to Net::IRC, a work in progress. First intended to be a quick tool
for writing an IRC script in Perl, Net::IRC has grown into a comprehensive
Perl implementation of the IRC protocol (RFC 1459), developed by several
members of the EFnet IRC channel #perl, and maintained in channel #net-irc.

There are 4 component modules which make up Net::IRC:

=over

=item *

Net::IRC

The wrapper for everything else, containing methods to generate
Connection objects (see below) and a connection manager which does an event
loop on all available filehandles. Sockets or files which are readable (or
writable, or whatever you want it to select() for) get passed to user-supplied
handler subroutines in other packages or in user code.

=item *

Net::IRC::Connection

The big time sink on this project. Each Connection instance is a
single connection to an IRC server. The module itself contains methods for
every single IRC command available to users (Net::IRC isn't designed for
writing servers, for obvious reasons), methods to set, retrieve, and call
handler functions which the user can set (more on this later), and too many
cute comments. Hey, what can I say, we were bored.

=item *

Net::IRC::Event

Kind of a struct-like object for storing info about things that the
IRC server tells you (server responses, channel talk, joins and parts, et
cetera). It records who initiated the event, who it affects, the event
type, and any other arguments provided for that event. Incidentally, the
only argument passed to a handler function.

=item *

Net::IRC::DCC

The analogous object to Connection.pm for connecting, sending and
retrieving with the DCC protocol. Instances of DCC.pm are invoked from
C<Connection-E<gt>new_{send,get,chat}> in the same way that
C<IRC-E<gt>newconn> invokes C<Connection-E<gt>new>. This will make more
sense later, we promise.

=back

The central concept that Net::IRC is built around is that of handlers
(or hooks, or callbacks, or whatever the heck you feel like calling them).
We tried to make it a completely event-driven model, a la Tk -- for every
conceivable type of event that your client might see on IRC, you can give
your program a custom subroutine to call. But wait, there's more! There are
3 levels of handler precedence:

=over

=item *

Default handlers

Considering that they're hardwired into Net::IRC, these won't do
much more than the bare minimum needed to keep the client listening on the
server, with an option to print (nicely formatted, of course) what it hears
to whatever filehandles you specify (STDOUT by default). These get called
only when the user hasn't defined any of his own handlers for this event.

=item *

User-definable global handlers

The user can set up his own subroutines to replace the default
actions for I<every> IRC connection managed by your program. These only get
invoked if the user hasn't set up a per-connection handler for the same
event.

=item *

User-definable per-connection handlers

Simple: this tells a single connection what to do if it gets an event of
this type. Supersedes global handlers if any are defined for this event.

=back

And even better, you can choose to call your custom handlers before
or after the default handlers instead of replacing them, if you wish. In
short, it's not perfect, but it's about as good as you can get and still be
documentable, given the sometimes horrendous complexity of the IRC protocol.


=head1 GETTING STARTED

=head2 Initialization

To start a Net::IRC script, you need two things: a Net::IRC object, and a
Net::IRC::Connection object. The Connection object does the dirty work of
connecting to the server; the IRC object handles the input and output for it.
To that end, say something like this:

    use Net::IRC;

    $irc = new Net::IRC;

    $conn = $irc->newconn(Nick    => 'some_nick',
                          Server  => 'some.irc.server.com');

...or something similar. Acceptable parameters to newconn() are:

=over

=item *

Nick

The nickname you'll be known by on IRC, often limited to a maximum of 9
letters. Acceptable characters for a nickname are C<[\w{}[]\`^|-]>. If
you don't specify a nick, it defaults to your username.

=item *

Server

The IRC server to connect to. There are dozens of them across several
widely-used IRC networks, but the oldest and most popular is EFNet (Eris
Free Net), home to #perl. See http://www.irchelp.org/ for lists of
popular servers, or ask a friend.

=item *

Port

The port to connect to this server on. By custom, the default is 6667.

=item *

Username

On systems not running identd, you can set the username for your user@host
to anything you wish. Note that some IRC servers won't allow connections from
clients which don't run identd.

=item *

Ircname

A short (maybe 60 or so chars) piece of text, originally intended to display
your real name, which people often use for pithy quotes and URLs. Defaults to
the contents of your GECOS field.

=item *

Password

If the IRC server you're trying to write a bot for is
password-protected, no problem. Just say "C<Password => 'foo'>" and
you're set.

=item *

SSL

If you wish to connect to an irc server which is using SSL, set this to a
true value.  Ie: "C<SSL => 1>".

=back

=head2 Handlers

Once that's over and done with, you need to set up some handlers if you want
your bot to do anything more than sit on a connection and waste resources.
Handlers are references to subroutines which get called when a specific event
occurs. Here's a sample handler sub:

    # What to do when the bot successfully connects.
    sub on_connect {
        my $self = shift;

        print "Joining #IRC.pm...";
        $self->join("#IRC.pm");
        $self->privmsg("#IRC.pm", "Hi there.");
    }

The arguments to a handler function are always the same:

=over

=item $_[0]:

The Connection object that's calling it.

=item $_[1]:

An Event object (see below) that describes what the handler is responding to.

=back

Got it? If not, see the examples in the irctest script that came with this
distribution. Anyhow, once you've defined your handler subroutines, you need
to add them to the list of handlers as either a global handler (affects all
Connection objects) or a local handler (affects only a single Connection). To
do so, say something along these lines:

    $self->add_global_handler('376', \&on_connect);     # global
    $self->add_handler('msg', \&on_msg);                # local

376, incidentally, is the server number for "end of MOTD", which is an event
that the server sends to you after you're connected. See Event.pm for a list
of all possible numeric codes. The 'msg' event gets called whenever someone
else on IRC sends your client a private message. For a big list of possible
events, see the B<Event List> section in the documentation for
Net::IRC::Event.

=head2 Getting Connected

When you've set up all your handlers, the following command will put your
program in an infinite loop, grabbing input from all open connections and
passing it off to the proper handlers:

    $irc->start;

Note that new connections can be added and old ones dropped from within your
handlers even after you call this. Just don't expect any code below the call
to C<start()> to ever get executed.

If you're tying Net::IRC into another event-based module, such as perl/Tk,
there's a nifty C<do_one_loop()> method provided for your convenience. Calling
C<$irc-E<gt>do_one_loop()> runs through the IRC.pm event loop once, hands
all ready filehandles over to the appropriate handler subs, then returns
control to your program.

=head1 METHOD DESCRIPTIONS

This section contains only the methods in IRC.pm itself. Lists of the
methods in Net::IRC::Connection, Net::IRC::Event, or Net::IRC::DCC are in
their respective modules' documentation; just C<perldoc Net::IRC::Connection>
(or Event or DCC or whatever) to read them. Functions take no arguments
unless otherwise specified in their description.

By the way, expect Net::IRC to use AutoLoader sometime in the future, once
it becomes a little more stable.

=over

=item *

addconn()

Adds the specified object's socket to the select loop in C<do_one_loop()>.
This is mostly for the use of Connection and DCC objects (and for pre-0.5
compatibility)... for most (read: all) purposes, you can just use C<addfh()>,
described below.

Takes at least 1 arg:

=over

=item 0.

An object whose socket needs to be added to the select loop

=item 1.

B<Optional:> A string consisting of one or more of the letters r, w, and e.
Passed directly to C<addfh()>... see the description below for more info.

=back

=item *

addfh()

This sub takes a user's socket or filehandle and a sub to handle it with and
merges it into C<do_one_loop()>'s list of select()able filehandles. This makes
integration with other event-based systems (Tk, for instance) a good deal
easier than in previous releases.

Takes at least 2 args:

=over

=item 0.

A socket or filehandle to monitor

=item 1.

A reference to a subroutine. When C<select()> determines that the filehandle
is ready, it passes the filehandle to this (presumably user-supplied) sub,
where you can read from it, write to it, etc. as your script sees fit.

=item 2.

B<Optional:> A string containing any combination of the letters r, w or e
(standing for read, write, and error, respectively) which determines what
conditions you're expecting on that filehandle. For example, this line
select()s $fh (a filehandle, of course) for both reading and writing:

    $irc->addfh( $fh, \&callback, "rw" );

=back

=item *

do_one_loop()

C<select()>s on all open filehandles and passes any ready ones to the
appropriate handler subroutines. Also responsible for executing scheduled
events from C<Net::IRC::Connection-E<gt>schedule()> on time.

=item *

new()

A fairly vanilla constructor which creates and returns a new Net::IRC object.

=item *

newconn()

Creates and returns a new Connection object. All arguments are passed straight
to C<Net::IRC::Connection-E<gt>new()>; examples of common arguments can be
found in the B<Synopsis> or B<Getting Started> sections.

=item *

removeconn()

Removes the specified object's socket from C<do_one_loop()>'s list of
select()able filehandles. This is mostly for the use of Connection and DCC
objects (and for pre-0.5 compatibility)... for most (read: all) purposes,
you can just use C<removefh()>, described below.

Takes 1 arg:

=over

=item 0.

An object whose socket or filehandle needs to be removed from the select loop

=back

=item *

removefh()

This method removes a given filehandle from C<do_one_loop()>'s list of
selectable filehandles.

Takes 1 arg:

=over

=item 0.

A socket or filehandle to remove

=back

=item *

start()

Starts an infinite event loop which repeatedly calls C<do_one_loop()> to
read new events from all open connections and pass them off to any
applicable handlers.

=item *

timeout()

Sets or returns the current C<select()> timeout for the main event loop, in
seconds (fractional amounts allowed). See the documentation for the
C<select()> function for more info.

Takes 1 optional arg:

=over

=item 0.

B<Optional:> A new value for the C<select()> timeout for this IRC object.

=back

=item *

flush_output_queue()

Flushes any waiting messages in the output queue if pacing is enabled. This
method will not return until the output queue is empty.

=over

=back

=head1 AUTHORS

=over

=item *

Conceived and initially developed by Greg Bacon E<lt>gbacon@adtran.comE<gt>
and Dennis Taylor E<lt>dennis@funkplanet.comE<gt>.

=item *

Ideas and large amounts of code donated by Nat "King" Torkington
E<lt>gnat@frii.comE<gt>.

=item *

Currently being hacked on, hacked up, and worked over by the members of the
Net::IRC developers mailing list. For details, see
http://www.execpc.com/~corbeau/irc/list.html .

=back

=head1 URL

Up-to-date source and information about the Net::IRC project can be found at
http://www.sourceforge.net/projects/net-irc/ .

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


