#####################################################################
#                                                                   #
#   Net::IRC -- Object-oriented Perl interface to an IRC server     #
#                                                                   #
#   Connection.pm: The basic functions for a simple IRC connection  #
#                                                                   #
#                                                                   #
#    Copyright (c) 2001 Pete Sergeant, Greg Bacon & Dennis Taylor.  #
#                       All rights reserved.                        #
#                                                                   #
#      This module is free software; you can redistribute or        #
#      modify it under the terms of Perl's Artistic License.        #
#                                                                   #
#####################################################################

package PBot::IRC::Connection; # pragma_ 2011/21/01

use PBot::IRC::Event; # pragma_ 2011/21/01
use PBot::IRC::DCC; # pragma_ 2011/21/01
use IO::Socket;
use IO::Socket::INET;
use Symbol;
use Carp;

# all this junk below just to conditionally load a module
# sometimes even perl is braindead...

eval 'use Time::HiRes qw(time)';
if(!$@) {
  sub time ();
  use subs 'time';
  require Time::HiRes;
  Time::HiRes->import('time');
}

use strict;

use vars (
	'$AUTOLOAD',
);


# The names of the methods to be handled by &AUTOLOAD.
my %autoloaded = ( 'ircname'  => undef,
		   'port'     => undef,
		   'username' => undef,
		   'socket'   => undef,
		   'verbose'  => undef,
		   'parent'   => undef,
                   'hostname' => undef,
		   'pacing'   => undef,
                   'ssl'      => undef,
		 );

# This hash will contain any global default handlers that the user specifies.

my %_udef = ();

# Creates a new IRC object and assigns some default attributes.
sub new {
  my $proto = shift;
  
  my $self = {                # obvious defaults go here, rest are user-set
    _debug      => $_[0]->{_debug},
    _port       => 6667,
    # Evals are for non-UNIX machines, just to make sure.
    _username   => eval { scalar getpwuid($>) } || $ENV{USER} || $ENV{LOGNAME} || "japh",
    _ircname    => $ENV{IRCNAME} || eval { (getpwuid($>))[6] } || "Just Another Perl Hacker",
    _nick       => $ENV{IRCNICK} || eval { scalar getpwuid($>) } || $ENV{USER} || $ENV{LOGNAME} || "WankerBot",
    _ignore     => {},
    _handler    => {},
    _verbose    =>  0,       # Is this an OK default?
    _parent     =>  shift,
    _frag       =>  '',
    _connected  =>  0,
    _maxlinelen =>  510,     # The RFC says we shouldn't exceed this.
    _lastsl     =>  0,
    _pacing     =>  0,       # no pacing by default
    _ssl	=>  0,       # no ssl by default
    _format     => { 'default' => "[%f:%t]  %m  <%d>", },
  };
  
  bless $self, $proto;
  # do any necessary initialization here
  $self->connect(@_) if @_;
  
  return $self;
}

# Takes care of the methods in %autoloaded
# Sets specified attribute, or returns its value if called without args.
sub AUTOLOAD {
    my $self = @_;  ## can't modify @_ for goto &name
    my $class = ref $self;  ## die here if !ref($self) ?
    my $meth;

    # -- #perl was here! --
    #  <Teratogen> absolute power corrupts absolutely, but it's a helluva lot
    #              of fun.
    #  <Teratogen> =)
    
    ($meth = $AUTOLOAD) =~ s/^.*:://;  ## strip fully qualified portion

    unless (exists $autoloaded{$meth}) {
	croak "No method called \"$meth\" for $class object.";
    }
    
    eval <<EOSub;
sub $meth {
    my \$self = shift;
	
    if (\@_) {
	my \$old = \$self->{"_$meth"};
	
	\$self->{"_$meth"} = shift;
	
	return \$old;
    }
    else {
	return \$self->{"_$meth"};
    }
}
EOSub
    
    # no reason to play this game every time
    goto &$meth;
}

# This sub is the common backend to add_handler and add_global_handler
#
sub _add_generic_handler {
  my ($self, $event, $ref, $rp, $hash_ref, $real_name) = @_;
  my $ev;
  my %define = ( "replace" => 0, "before" => 1, "after" => 2 );
  
  unless (@_ >= 3) {
    croak "Not enough arguments to $real_name()";
  }
  unless (ref($ref) eq 'CODE') {
    croak "Second argument of $real_name isn't a coderef";
  }
  
  # Translate REPLACE, BEFORE and AFTER.
  if (not defined $rp) {
    $rp = 0;
  } elsif ($rp =~ /^\D/) {
    $rp = $define{lc $rp} || 0;
  }
  
  foreach $ev (ref $event eq "ARRAY" ? @{$event} : $event) {
    # Translate numerics to names
    if ($ev =~ /^\d/) {
      $ev = PBot::IRC::Event->trans($ev); # pragma_ 2011/21/01
      unless ($ev) {
        carp "Unknown event type in $real_name: $ev";
        return;
      }
    }
    
    $hash_ref->{lc $ev} = [ $ref, $rp ];
  }
  return 1;
}

# This sub will assign a user's custom function to a particular event which
# might be received by any Connection object.
# Takes 3 args:  the event to modify, as either a string or numeric code
#                   If passed an arrayref, the array is assumed to contain
#                   all event names which you want to set this handler for.
#                a reference to the code to be executed for the event
#    (optional)  A value indicating whether the user's code should replace
#                the built-in handler, or be called with it. Possible values:
#                   0 - Replace the built-in handlers entirely. (the default)
#                   1 - Call this handler right before the default handler.
#                   2 - Call this handler right after the default handler.
# These can also be referred to by the #define-like strings in %define.
sub add_global_handler {
  my ($self, $event, $ref, $rp) = @_;
  return $self->_add_generic_handler($event, $ref, $rp, \%_udef, 'add_global_handler');
}

# This sub will assign a user's custom function to a particular event which
# this connection might receive.  Same args as above.
sub add_handler {
  my ($self, $event, $ref, $rp) = @_;
  return $self->_add_generic_handler($event, $ref, $rp, $self->{_handler}, 'add_handler');
}

# Hooks every event we know about...
sub add_default_handler {
  my ($self, $ref, $rp) = @_;
  foreach my $eventtype (keys(%PBot::IRC::Event::_names)) { # pragma_ 2011/21/01
    $self->_add_generic_handler($eventtype, $ref, $rp, $self->{_handler}, 'add_default_handler');
  }
  return 1;
}

# Why do I even bother writing subs this simple? Sends an ADMIN command.
# Takes 1 optional arg:  the name of the server you want to query.
sub admin {
  my $self = shift;        # Thank goodness for AutoLoader, huh?
                           # Perhaps we'll finally use it soon.
  
  $self->sl("ADMIN" . ($_[0] ? " $_[0]" : ""));
}

# Toggles away-ness with the server.  Optionally takes an away message.
sub away {
    my $self = shift;
    $self->sl("AWAY" . ($_[0] ? " :$_[0]" : ""));
}

# Attempts to connect to the specified IRC (server, port) with the specified
#   (nick, username, ircname). Will close current connection if already open.
sub connect {
  my $self = shift;
  my ($password, $sock);
  
  if (@_) {
    my (%arg) = @_;
    
    $self->hostname($arg{'LocalAddr'}) if exists $arg{'LocalAddr'};
    $password = $arg{'Password'} if exists $arg{'Password'};
    $self->nick($arg{'Nick'}) if exists $arg{'Nick'};
    $self->port($arg{'Port'}) if exists $arg{'Port'};
    $self->server($arg{'Server'}) if exists $arg{'Server'};
    $self->ircname($arg{'Ircname'}) if exists $arg{'Ircname'};
    $self->username($arg{'Username'}) if exists $arg{'Username'};
    $self->pacing($arg{'Pacing'}) if exists $arg{'Pacing'};
    $self->ssl($arg{'SSL'}) if exists $arg{'SSL'};
  }
  
  # Lots of error-checking claptrap first...
  unless ($self->server) {
    unless ($ENV{IRCSERVER}) {
      croak "No server address specified in connect()";
    }
    $self->server( $ENV{IRCSERVER} );
  }
  unless ($self->nick) {
    $self->nick($ENV{IRCNICK} || eval { scalar getpwuid($>) }
                || $ENV{USER} || $ENV{LOGNAME} || "WankerBot");
  }
  unless ($self->port) {
    $self->port($ENV{IRCPORT} || 6667);
  }
  unless ($self->ircname)  {
    $self->ircname($ENV{IRCNAME} || eval { (getpwuid($>))[6] }
                   || "Just Another Perl Hacker");
  }
  unless ($self->username) {
    $self->username(eval { scalar getpwuid($>) } || $ENV{USER}
                    || $ENV{LOGNAME} || "japh");
  }
  
  # Now for the socket stuff...
  if ($self->connected) {
    $self->quit("Changing servers");
  }
  
  if($self->ssl) {
    require IO::Socket::SSL;
    
    $self->socket(IO::Socket::SSL->new(PeerAddr  => $self->server,
                                       PeerPort  => $self->port,
                                       Proto     => "tcp",
                                       LocalAddr => $self->hostname,
                                       ));
  } else {
    
    $self->socket(IO::Socket::INET->new(PeerAddr  => $self->server,
                                        PeerPort  => $self->port,
                                        Proto     => "tcp",
                                        LocalAddr => $self->hostname,
                                        ));
  }
  
  if(!$self->socket) {
    carp (sprintf "Can't connect to %s:%s!",
          $self->server, $self->port);
    $self->error(1);
    return;
  }
  
  # Send a PASS command if they specified a password. According to
  # the RFC, we should do this as soon as we connect.
  if (defined $password) {
    $self->sl("PASS $password");
  }
  
  # Now, log in to the server...
  unless ($self->sl('NICK ' . $self->nick()) and
          $self->sl(sprintf("USER %s %s %s :%s",
                            $self->username(),
                            "foo.bar.com",
                            $self->server(),
                            $self->ircname()))) {
    carp "Couldn't send introduction to server: $!";
    $self->error(1);
    $! = "Couldn't send NICK/USER introduction to " . $self->server;
    return;
  }
  
  $self->{_connected} = 1;
  $self->parent->addconn($self);
}

# Returns a boolean value based on the state of the object's socket.
sub connected {
  my $self = shift;
  
  return ( $self->{_connected} and $self->socket() );
}

# Sends a CTCP request to some hapless victim(s).
# Takes at least two args:  the type of CTCP request (case insensitive)
#                           the nick or channel of the intended recipient(s)
# Any further args are arguments to CLIENTINFO, ERRMSG, or ACTION.
sub ctcp {
  my ($self, $type, $target) = splice @_, 0, 3;
  $type = uc $type;
  
  unless ($target) {
    croak "Not enough arguments to ctcp()";
  }
  
  if ($type eq "PING") {
    unless ($self->sl("PRIVMSG $target :\001PING " . int(time) . "\001")) {
      carp "Socket error sending $type request in ctcp()";
      return;
    }
  } elsif (($type eq "CLIENTINFO" or $type eq "ACTION") and @_) {
    unless ($self->sl("PRIVMSG $target :\001$type " .
                      CORE::join(" ", @_) . "\001")) {
      carp "Socket error sending $type request in ctcp()";
      return;
    }
  } elsif ($type eq "ERRMSG") {
    unless (@_) {
      carp "Not enough arguments to $type in ctcp()";
      return;
    }
    unless ($self->sl("PRIVMSG $target :\001ERRMSG " .
                      CORE::join(" ", @_) . "\001")) {
      carp "Socket error sending $type request in ctcp()";
      return;
    }
  } else {
    unless ($self->sl("PRIVMSG $target :\001$type " . 
                      CORE::join(" ",@_) . "\001")) {
      carp "Socket error sending $type request in ctcp()";
      return;
    }
  }
}

# Sends replies to CTCP queries. Simple enough, right?
# Takes 2 args:  the target person or channel to send a reply to
#                the text of the reply
sub ctcp_reply {
  my $self = shift;
  
  $self->notice($_[0], "\001" . $_[1] . "\001");
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


# Dequotes CTCP messages according to ctcp.spec. Nothing special.
# Then it breaks them into their component parts in a flexible, ircII-
# compatible manner. This is not quite as trivial. Oh, well.
# Takes 1 arg:  the line to be dequoted.
sub dequote {
  my $line = shift;
  my ($order, @chunks) = (0, ());    # CHUNG! CHUNG! CHUNG!
  
  # Filter misplaced \001s before processing... (Thanks, Tom!)
  substr($line, rindex($line, "\001"), 1) = '\\a'
      unless ($line =~ tr/\001//) % 2 == 0;
  
  # Thanks to Abigail (abigail@fnx.com) for this clever bit.
  if (index($line, "\cP") >= 0) {    # dequote low-level \n, \r, ^P, and \0.
    my (%h) = (n => "\012", r => "\015", 0 => "\0", "\cP" => "\cP");
    $line =~ s/\cP([nr0\cP])/$h{$1}/g;
  }
  $line =~ s/\\([^\\a])/$1/g;  # dequote unnecessarily quoted characters.
  
  # If true, it's in odd order... ctcp commands start with first chunk.
  $order = 1 if index($line, "\001") == 0;
  @chunks = map { s/\\\\/\\/g; $_ } (split /\cA/, $line);
  
  return ($order, @chunks);
}

# Standard destructor method for the GC routines. (HAHAHAH! DIE! DIE! DIE!)
sub DESTROY {
  my $self = shift;
  $self->handler("destroy", "nobody will ever use this");
  $self->quit();
  # anything else?
}


# Disconnects this Connection object cleanly from the server.
# Takes at least 1 arg:  the format and args parameters to Event->new().
sub disconnect {
  my $self = shift;
  
  $self->{_connected} = 0;
  $self->parent->removeconn($self);
  $self->socket( undef );
  $self->handler(PBot::IRC::Event->new( "disconnect", # pragma_ 2011/21/01
                                       $self->server,
                                       '',
                                       @_  ));
}


# Tells IRC.pm if there was an error opening this connection. It's just
# for sane error passing.
# Takes 1 optional arg:  the new value for $self->{'iserror'}
sub error {
  my $self = shift;
  
  $self->{'iserror'} = $_[0] if @_;
  return $self->{'iserror'};
}

# Lets the user set or retrieve a format for a message of any sort.
# Takes at least 1 arg:  the event whose format you're inquiring about
#           (optional)   the new format to use for this event
sub format {
  my ($self, $ev) = splice @_, 0, 2;
  
  unless ($ev) {
    croak "Not enough arguments to format()";
  }
  
  if (@_) {
    $self->{'_format'}->{$ev} = $_[0];
  } else {
    return ($self->{'_format'}->{$ev} ||
            $self->{'_format'}->{'default'});
  }
}

# Calls the appropriate handler function for a specified event.
# Takes 2 args:  the name of the event to handle
#                the arguments to the handler function
sub handler {
  my ($self, $event) = splice @_, 0, 2;
  
  unless (defined $event) {
    croak 'Too few arguments to Connection->handler()';
  }
  
  # Get name of event.
  my $ev;
  if (ref $event) {
    $ev = $event->type;
  } elsif (defined $event) {
    $ev = $event;
    $event = PBot::IRC::Event->new($event, '', '', ''); # pragma_ 2011/21/01
  } else {
    croak "Not enough arguments to handler()";
  }
  
  print "Trying to handle event '$ev'.\n" if $self->{_debug};
  
  my $handler = undef;
  if (exists $self->{_handler}->{$ev}) {
    $handler = $self->{_handler}->{$ev};
  } elsif (exists $_udef{$ev}) {
    $handler = $_udef{$ev};
  } else {
    return $self->_default($event, @_);
  }
  
  my ($code, $rp) = @{$handler};
  
  # If we have args left, try to call the handler.
  if ($rp == 0) {                      # REPLACE
    &$code($self, $event, @_);
  } elsif ($rp == 1) {                 # BEFORE
    &$code($self, $event, @_);
    $self->_default($event, @_);
  } elsif ($rp == 2) {                 # AFTER
    $self->_default($event, @_);
    &$code($self, $event, @_);
  } else {
    confess "Bad parameter passed to handler(): rp=$rp";
  }
  
  print "Handler for '$ev' called.\n" if $self->{_debug};
  
  return 1;
}

# Lets a user set hostmasks to discard certain messages from, or (if called
# with only 1 arg), show a list of currently ignored hostmasks of that type.
# Takes 2 args:  type of ignore (public, msg, ctcp, etc)
#    (optional)  [mask(s) to be added to list of specified type]
sub ignore {
  my $self = shift;
  
  unless (@_) {
    croak "Not enough arguments to ignore()";
  }
  
  if (@_ == 1) {
    if (exists $self->{_ignore}->{$_[0]}) {
      return @{ $self->{_ignore}->{$_[0]} };
    } else {
      return ();
    }
  } elsif (@_ > 1) {     # code defensively, remember...
    my $type = shift;
    
    # I moved this part further down as an Obsessive Efficiency
    # Initiative. It shouldn't be a problem if I do _parse right...
    # ... but those are famous last words, eh?
    unless (grep {$_ eq $type}
            qw(public msg ctcp notice channel nick other all)) {	    
      carp "$type isn't a valid type to ignore()";
      return;
    }
    
    if ( exists $self->{_ignore}->{$type} )  {
      push @{$self->{_ignore}->{$type}}, @_;
    } else  {
      $self->{_ignore}->{$type} = [ @_ ];
    }
  }
}


# Yet Another Ridiculously Simple Sub. Sends an INFO command.
# Takes 1 optional arg: the name of the server to query.
sub info {
  my $self = shift;
  
  $self->sl("INFO" . ($_[0] ? " $_[0]" : ""));
}


# Invites someone to an invite-only channel. Whoop.
# Takes 2 args:  the nick of the person to invite
#                the channel to invite them to.
# I hate the syntax of this command... always seemed like a protocol flaw.
sub invite {
  my $self = shift;
  
  unless (@_ > 1) {
    croak "Not enough arguments to invite()";
  }
  
  $self->sl("INVITE $_[0] $_[1]");
}

# Checks if a particular nickname is in use.
# Takes at least 1 arg:  nickname(s) to look up.
sub ison {
  my $self = shift;
  
  unless (@_) {
    croak 'Not enough args to ison().';
  }
  
  $self->sl("ISON " . CORE::join(" ", @_));
}

# Joins a channel on the current server if connected, eh?.
# Corresponds to /JOIN command.
# Takes 2 args:  name of channel to join
#                optional channel password, for +k channels
sub join {
  my $self = shift;
  
  unless ( $self->connected ) {
    carp "Can't join() -- not connected to a server";
    return;
  }
  
  unless (@_) {
    croak "Not enough arguments to join()";
  }
  
  return $self->sl("JOIN $_[0]" . ($_[1] ? " $_[1]" : ""));

}

# Takes at least 2 args:  the channel to kick the bastard from
#                         the nick of the bastard in question
#             (optional)  a parting comment to the departing bastard
sub kick {
  my $self = shift;
  
  unless (@_ > 1) {
    croak "Not enough arguments to kick()";
  }
  return $self->sl("KICK $_[0] $_[1]" . ($_[2] ? " :$_[2]" : ""));
}

# Gets a list of all the servers that are linked to another visible server.
# Takes 2 optional args:  it's a bitch to describe, and I'm too tired right
#                         now, so read the RFC.
sub links {
  my ($self) = (shift, undef);
  
  $self->sl("LINKS" . (scalar(@_) ? " " . CORE::join(" ", @_[0,1]) : ""));
}


# Requests a list of channels on the server, or a quick snapshot of the current
# channel (the server returns channel name, # of users, and topic for each).
sub list {
  my $self = shift;
  
  $self->sl("LIST " . CORE::join(",", @_));
}

# Sends a request for some server/user stats.
# Takes 1 optional arg: the name of a server to request the info from.
sub lusers {
  my $self = shift;
  
  $self->sl("LUSERS" . ($_[0] ? " $_[0]" : ""));
}

# Gets and/or sets the max line length.  The value previous to the sub
# call will be returned.
# Takes 1 (optional) arg: the maximum line length (in bytes)
sub maxlinelen {
  my $self = shift;
  
  my $ret = $self->{_maxlinelen};
  
  $self->{_maxlinelen} = shift if @_;
  
  return $ret;
}

# Sends an action to the channel/nick you specify. It's truly amazing how
# many IRCers have no idea that /me's are actually sent via CTCP.
# Takes 2 args:  the channel or nick to bother with your witticism
#                the action to send (e.g., "weed-whacks billn's hand off.")
sub me {
  my $self = shift;
  
  $self->ctcp("ACTION", $_[0], $_[1]);
}

# Change channel and user modes (this one is easy... the handler is a bitch.)
# Takes at least 1 arg:  the target of the command (channel or nick)
#             (optional)  the mode string (i.e., "-boo+i")
#             (optional)  operands of the mode string (nicks, hostmasks, etc.)
sub mode {
  my $self = shift;
  
  unless (@_ >= 1) {
    croak "Not enough arguments to mode()";
  }
  $self->sl("MODE $_[0] " . CORE::join(" ", @_[1..$#_]));
}

# Sends a MOTD command to a server.
# Takes 1 optional arg:  the server to query (defaults to current server)
sub motd {
  my $self = shift;
  
  $self->sl("MOTD" . ($_[0] ? " $_[0]" : ""));
}

# Requests the list of users for a particular channel (or the entire net, if
# you're a masochist).
# Takes 1 or more optional args:  name(s) of channel(s) to list the users from.
sub names {
  my $self = shift;
  
  $self->sl("NAMES " . CORE::join(",", @_));
  
}   # Was this the easiest sub in the world, or what?

# Creates and returns a DCC CHAT object, analogous to IRC.pm's newconn().
# Takes at least 1 arg:   An Event object for the DCC CHAT request.
#                    OR   A list or listref of args to be passed to new(),
#                         consisting of:
#                           - A boolean value indicating whether or not
#                             you're initiating the CHAT connection.
#                           - The nick of the chattee
#                           - The address to connect to
#                           - The port to connect on
sub new_chat {
  my $self = shift;
  my ($init, $nick, $address, $port);
  
  if (ref($_[0]) =~ /Event/) {
    # If it's from an Event object, we can't be initiating, right?
    ($init, undef, undef, undef, $address, $port) = (0, $_[0]->args);
    $nick = $_[0]->nick;
    
  } elsif (ref($_[0]) eq "ARRAY") {
    ($init, $nick, $address, $port) = @{$_[0]};
  } else {
    ($init, $nick, $address, $port) = @_;
  }
  
  PBot::IRC::DCC::CHAT->new($self, $init, $nick, $address, $port); # pragma_ 2011/21/01
}

# Creates and returns a DCC GET object, analogous to IRC.pm's newconn().
# Takes at least 1 arg:   An Event object for the DCC SEND request.
#                    OR   A list or listref of args to be passed to new(),
#                         consisting of:
#                           - The nick of the file's sender
#                           - The name of the file to receive
#                           - The address to connect to
#                           - The port to connect on
#                           - The size of the incoming file
# For all of the above, an extra argument should be added at the end:
#                         An open filehandle to save the incoming file into,
#                         in globref, FileHandle, or IO::* form.
# If you wish to do a DCC RESUME, specify the offset in bytes that you
# want to start downloading from as the last argument.
sub new_get {
  my $self = shift;
  my ($nick, $name, $address, $port, $size,  $offset, $handle);
  
  if (ref($_[0]) =~ /Event/) {
    (undef, undef, $name, $address, $port, $size) = $_[0]->args;
    $nick = $_[0]->nick;
    $handle = $_[1] if defined $_[1];
  } elsif (ref($_[0]) eq "ARRAY") {
    ($nick, $name, $address, $port, $size) = @{$_[0]};
    $handle = $_[1] if defined $_[1];
  } else {
    ($nick, $name, $address, $port, $size, $handle) = @_;
  }
  
  unless (defined $handle and ref $handle and
          (ref $handle eq "GLOB" or $handle->can('print')))
  {
    carp ("Filehandle argument to Connection->new_get() must be ".
          "a glob reference or object");
    return;                                # is this behavior OK?
  }
  
  my $dcc = PBot::IRC::DCC::GET->new( $self, $nick, $address, $port, $size, # pragma_ 2011/21/01
                                     $name, $handle, $offset );
  
  $self->parent->addconn($dcc) if $dcc;
  return $dcc;
}

# Creates and returns a DCC SEND object, analogous to IRC.pm's newconn().
# Takes at least 2 args:  The nickname of the person to send to
#                         The name of the file to send
#             (optional)  The blocksize for the connection (default 1k)
sub new_send {
  my $self = shift;
  my ($nick, $filename, $blocksize);
  
  if (ref($_[0]) eq "ARRAY") {
    ($nick, $filename, $blocksize) = @{$_[0]};
  } else {
    ($nick, $filename, $blocksize) = @_;
  }
  
  PBot::IRC::DCC::SEND->new($self, $nick, $filename, $blocksize); # pragma_ 2011/21/01
}

# Selects nick for this object or returns currently set nick.
# No default; must be set by user.
# If changed while the object is already connected to a server, it will
# automatically try to change nicks.
# Takes 1 arg:  the nick. (I bet you could have figured that out...)
sub nick {
  my $self = shift;
  
  if (@_)  {
    $self->{'_nick'} = shift;
    if ($self->connected) {
      return $self->sl("NICK " . $self->{'_nick'});
    }
  } else {
    return $self->{'_nick'};
  }
}

# Sends a notice to a channel or person.
# Takes 2 args:  the target of the message (channel or nick)
#                the text of the message to send
# The message will be chunked if it is longer than the _maxlinelen 
# attribute, but it doesn't try to protect against flooding.  If you
# give it too much info, the IRC server will kick you off!
sub notice {
  my ($self, $to) = splice @_, 0, 2;
  
  unless (@_) {
    croak "Not enough arguments to notice()";
  }
  
  my ($buf, $length, $line) = (CORE::join("", @_), $self->{_maxlinelen});
  
  while(length($buf) > 0) {
    ($line, $buf) = unpack("a$length a*", $buf);
    $self->sl("NOTICE $to :$line");
  }
}

# Makes you an IRCop, if you supply the right username and password.
# Takes 2 args:  Operator's username
#                Operator's password
sub oper {
  my $self = shift;
  
  unless (@_ > 1) {
    croak "Not enough arguments to oper()";
  }
  
  $self->sl("OPER $_[0] $_[1]");
}

# This function splits apart a raw server line into its component parts
# (message, target, message type, CTCP data, etc...) and passes it to the
# appropriate handler. Takes no args, really.
sub parse {
  my ($self) = shift;
  my ($from, $type, $message, @stuff, $itype, $ev, @lines, $line);
  
  if (defined ($self->ssl ?
               $self->socket->read($line, 10240) :
               $self->socket->recv($line, 10240, 0))
      and
      (length($self->{_frag}) + length($line)) > 0)  {
    # grab any remnant from the last go and split into lines
    my $chunk = $self->{_frag} . $line;
    @lines = split /\012/, $chunk;
    
    # if the last line was incomplete, pop it off the chunk and
    # stick it back into the frag holder.
    $self->{_frag} = (substr($chunk, -1) ne "\012" ? pop @lines : '');
    
  } else {	
    # um, if we can read, i say we should read more than 0
    # besides, recv isn't returning undef on closed
    # sockets.  getting rid of this connection...
    $self->disconnect('error', 'Connection reset by peer');
    return;
  }
  
 PARSELOOP: foreach $line (@lines) {
   
   # Clean the lint filter every 2 weeks...
   $line =~ s/[\012\015]+$//;
   next unless $line;
   
   print "<<< $line\n" if $self->{_debug};
   
   # Like the RFC says: "respond as quickly as possible..."
   if ($line =~ /^PING/) {
     $ev = (PBot::IRC::Event->new( "ping", # pragma_ 2011/21/01
                                  $self->server,
                                  $self->nick,
                                  "serverping",   # FIXME?
                                  substr($line, 5)
                                  ));
     
     # Had to move this up front to avoid a particularly pernicious bug.
   } elsif ($line =~ /^NOTICE/) {
     $ev = PBot::IRC::Event->new( "snotice", # pragma_ 2011/21/01
                                 $self->server,
                                 '',
                                 'server',
                                 (split /:/, $line, 2)[1] );
     
     
     # Spurious backslashes are for the benefit of cperl-mode.
     # Assumption:  all non-numeric message types begin with a letter
   } elsif ($line =~ /^:?
            (?:[][}{\w\\\`^|\-]+?    # The nick (valid nickname chars)
             !                       # The nick-username separator
             .+?                     # The username
             \@)?                    # Umm, duh...
            \S+                      # The hostname
            \s+                      # Space between mask and message type
            [A-Za-z]                 # First char of message type
            [^\s:]+?                 # The rest of the message type
            /x)                      # That ought to do it for now...
   {
     $line = substr $line, 1 if $line =~ /^:/;
     
     # Patch submitted for v.0.72
     # Fixes problems with IPv6 hostnames.
     # ($from, $line) = split ":", $line, 2;
     ($from, $line) = $line =~ /^(?:|)(\S+\s+[^:]+):?(.*)/;
     
     ($from, $type, @stuff) = split /\s+/, $from;
     $type = lc $type;
     # This should be fairly intuitive... (cperl-mode sucks, though)
     
     if (defined $line and index($line, "\001") >= 0) {
       $itype = "ctcp";
       unless ($type eq "notice") {
         $type = (($stuff[0] =~ tr/\#\&//) ? "public" : "msg");
       }
     } elsif ($type eq "privmsg") {
       $itype = $type = (($stuff[0] =~ tr/\#\&//) ? "public" : "msg");
     } elsif ($type eq "notice") {
       $itype = "notice";
     } elsif ($type eq "join" or $type eq "part" or
              $type eq "mode" or $type eq "topic" or
              $type eq "kick") {
       $itype = "channel";
     } elsif ($type eq "nick") {
       $itype = "nick";
     } else {
       $itype = "other";
     }
     
     # This goes through the list of ignored addresses for this message
     # type and drops out of the sub if it's from an ignored hostmask.
     
     study $from;
     foreach ( $self->ignore($itype), $self->ignore("all") ) {
       $_ = quotemeta; s/\\\*/.*/g;
       next PARSELOOP if $from =~ /$_/i;
     }
     
     # It used to look a lot worse. Here was the original version...
     # the optimization above was proposed by Silmaril, for which I am
     # eternally grateful. (Mine still looks cooler, though. :)
     
     # return if grep { $_ = join('.*', split(/\\\*/,
     #                  quotemeta($_)));  /$from/ }
     # ($self->ignore($type), $self->ignore("all"));
     
     # Add $line to @stuff for the handlers
     push @stuff, $line if defined $line;
     
     # Now ship it off to the appropriate handler and forget about it.
     if ( $itype eq "ctcp" ) {       # it's got CTCP in it!
       $self->parse_ctcp($type, $from, $stuff[0], $line);
       next;
       
     }  elsif ($type eq "public" or $type eq "msg"   or
               $type eq "notice" or $type eq "mode"  or
               $type eq "join"   or $type eq "part"  or
               $type eq "topic"  or $type eq "invite" or $type eq "whoisaccount" ) {
       
       $ev = PBot::IRC::Event->new( $type, # pragma_ 2011/21/01
                                   $from,
                                   shift(@stuff),
                                   $type,
                                   @stuff,
                                   );
     } elsif ($type eq "quit" or $type eq "nick") {
       
       $ev = PBot::IRC::Event->new( $type, # pragma_ 2011/21/01
                                   $from,
                                   $from,
                                   $type,
                                   @stuff,
                                   );
     } elsif ($type eq "kick") {
       
       $ev = PBot::IRC::Event->new( $type, # pragma_ 2011/21/01
                                   $from,
                                   $stuff[1],
                                   $type,
                                   @stuff[0,2..$#stuff],
                                   );
       
     } elsif ($type eq "kill") {
       $ev = PBot::IRC::Event->new($type, # pragma_ 2011/21/01
                                  $from,
                                  '',
                                  $type,
                                  $line);   # Ahh, what the hell.
     } elsif ($type eq "wallops") {
       $ev = PBot::IRC::Event->new($type, # pragma_ 2011/21/01
                                  $from,
                                  '',
                                  $type,
                                  $line);  
     } elsif ($type eq "pong") {
       $ev = PBot::IRC::Event->new($type, # pragma_ 2011/21/01
                                  $from,
                                  '',
                                  $type,
                                  $line);  
     } else {
       carp "Unknown event type: $type";
     }
   }
   elsif ($line =~ /^:?       # Here's Ye Olde Numeric Handler!
          \S+?                 # the servername (can't assume RFC hostname)
          \s+?                # Some spaces here...
          \d+?                # The actual number
          \b/x                # Some other crap, whatever...
          ) {
     $ev = $self->parse_num($line);
     
   } elsif ($line =~ /^:(\w+) MODE \1 /) {
     $ev = PBot::IRC::Event->new( 'umode', # pragma_ 2011/21/01
                                 $self->server,
                                 $self->nick,
                                 'server',
                                 substr($line, index($line, ':', 1) + 1));
     
   } elsif ($line =~ /^:?       # Here's Ye Olde Server Notice handler!
            .+?                 # the servername (can't assume RFC hostname)
            \s+?                # Some spaces here...
            NOTICE              # The server notice
            \b/x                # Some other crap, whatever...
            ) {
     $ev = PBot::IRC::Event->new( 'snotice', # pragma_ 2011/21/01
                                 $self->server,
                                 '',
                                 'server',
                                 (split /\s+/, $line, 3)[2] );
     
     
   } elsif ($line =~ /^ERROR/) {
     if ($line =~ /^ERROR :Closing [Ll]ink/) {   # is this compatible?
       
       $ev = 'done';
       $self->disconnect( 'error', ($line =~ /(.*)/) );
       
     } else {
       $ev = PBot::IRC::Event->new( "error", # pragma_ 2011/21/01
                                   $self->server,
                                   '',
                                   'error',
                                   (split /:/, $line, 2)[1]);
     }
   } elsif ($line =~ /^Closing [Ll]ink/) {
     $ev = 'done';
     $self->disconnect( 'error', ($line =~ /(.*)/) );
     
   }
   
   if ($ev) {
     
     # We need to be able to fall through if the handler has
     # already been called (i.e., from within disconnect()).
     
     $self->handler($ev) unless $ev eq 'done';
     
   } else {
     # If it gets down to here, it's some exception I forgot about.
     carp "Funky parse case: $line\n";
   }
 }
}

# The backend that parse() sends CTCP requests off to. Pay no attention
# to the camel behind the curtain.
# Takes 4 arguments:  the type of message
#                     who it's from
#                     the first bit of stuff
#                     the line from the server.
sub parse_ctcp {
  my ($self, $type, $from, $stuff, $line) = @_;
  
  my ($one, $two);
  my ($odd, @foo) = (&dequote($line));
  
  while (($one, $two) = (splice @foo, 0, 2)) {
    
    ($one, $two) = ($two, $one) if $odd;
    
    my ($ctype) = $one =~ /^(\w+)\b/;
    my $prefix = undef;
    if ($type eq 'notice') {
      $prefix = 'cr';
    } elsif ($type eq 'public' or
             $type eq 'msg'   ) {
      $prefix = 'c';
    } else {
      carp "Unknown CTCP type: $type";
      return;
    }
    
    if ($prefix) {
      my $handler = $prefix . lc $ctype;   # unit. value prob with $ctype
      
      $one =~ s/^$ctype //i;  # strip the CTCP type off the args
      $self->handler(PBot::IRC::Event->new( $handler, $from, $stuff, # pragma_ 2011/21/01
                                           $handler, $one ));
    }
    
    $self->handler(PBot::IRC::Event->new($type, $from, $stuff, $type, $two)) # pragma_ 2011/21/01
        if $two;
  }
  return 1;
}

# Does special-case parsing for numeric events. Separate from the rest of
# parse() for clarity reasons (I can hear Tkil gasping in shock now. :-).
# Takes 1 arg:  the raw server line
sub parse_num {
  my ($self, $line) = @_;

  # Figlet protection?  This seems to be a bit closer to the RFC than
  # the original version, which doesn't seem to handle :trailers quite
  # correctly. 
  
  my ($from, $type, $stuff) = split(/\s+/, $line, 3);
  my ($blip, $space, $other, @stuff);
  while ($stuff) {
    ($blip, $space, $other) = split(/(\s+)/, $stuff, 2);
    $space = "" unless $space;
    $other = "" unless $other;       # Thanks to jack velte...
    if ($blip =~ /^:/) {
      push @stuff, $blip . $space . $other;
      last;
    } else {
      push @stuff, $blip;
      $stuff = $other;
    }
  }
  
  $from = substr $from, 1 if $from =~ /^:/;
  
  return PBot::IRC::Event->new( $type, # pragma_ 2011/21/01
                               $from,
                               '',
                               'server',
                               @stuff );
}

# Helps you flee those hard-to-stand channels.
# Takes at least one arg:  name(s) of channel(s) to leave.
sub part {
  my $self = shift;
  
  unless (@_) {
    croak "No arguments provided to part()";
  }
  $self->sl("PART " . CORE::join(",", @_));    # "A must!"
}


# Tells what's on the other end of a connection. Returns a 2-element list
# consisting of the name on the other end and the type of connection.
# Takes no args.
sub peer {
  my $self = shift;
  
  return ($self->server(), "IRC connection");
}


# Prints a message to the defined error filehandle(s).
# No further description should be necessary.
sub printerr {
  shift;
  print STDERR @_, "\n";
}

# Prints a message to the defined output filehandle(s).
sub print {
  shift;
  print STDOUT @_, "\n";
}

# Sends a message to a channel or person.
# Takes 2 args:  the target of the message (channel or nick)
#                the text of the message to send
# Don't use this for sending CTCPs... that's what the ctcp() function is for.
# The message will be chunked if it is longer than the _maxlinelen 
# attribute, but it doesn't try to protect against flooding.  If you
# give it too much info, the IRC server will kick you off!
sub privmsg {
  my ($self, $to) = splice @_, 0, 2;
  
  unless (@_) {
    croak 'Not enough arguments to privmsg()';
  }
  
  my $buf = CORE::join '', @_;
  my $length = $self->{_maxlinelen} - 11 - length($to);
  my $line;
  
  if (ref($to) =~ /^(GLOB|IO::Socket)/) {
    while(length($buf) > 0) {
      ($line, $buf) = unpack("a$length a*", $buf);
      send($to, $line . "\012", 0);
    } 
  } else {
    while(length($buf) > 0) {
      ($line, $buf) = unpack("a$length a*", $buf);
      if (ref $to eq 'ARRAY') {
        $self->sl("PRIVMSG ", CORE::join(',', @$to), " :$line");
      } else {
        $self->sl("PRIVMSG $to :$line");
      }
    }
  }
}


# Closes connection to IRC server.  (Corresponding function for /QUIT)
# Takes 1 optional arg:  parting message, defaults to "Leaving" by custom.
sub quit {
  my $self = shift;
  
  # Do any user-defined stuff before leaving
  $self->handler("leaving");
  
  unless ( $self->connected ) {  return (1)  }
  
  # Why bother checking for sl() errors now, after all?  :)
  # We just send the QUIT command and leave. The server will respond with
  # a "Closing link" message, and parse() will catch it, close the
  # connection, and throw a "disconnect" event. Neat, huh? :-)
  
  $self->sl("QUIT :" . (defined $_[0] ? $_[0] : "Leaving"));
  
  # since the quit sends a line to the server, we need to flush the
  # output queue to make sure it gets there so the disconnect
  $self->parent->flush_output_queue();
  
  return 1;
}

# As per the RFC, ask the server to "re-read and process its configuration
# file."  Your server may or may not take additional arguments.  Generally
# requires IRCop status.
sub rehash {
  my $self = shift;
  $self->sl("REHASH" . CORE::join(" ", @_));
}


# As per the RFC, "force a server restart itself."  (Love that RFC.)  
# Takes no arguments.  If it succeeds, you will likely be disconnected,
# but I assume you already knew that.  This sub is too simple...
sub restart {
  my $self = shift;
  $self->sl("RESTART");
}

# Schedules an event to be executed after some length of time.
# Takes at least 2 args:  the number of seconds to wait until it's executed
#                         a coderef to execute when time's up
# Any extra args are passed as arguments to the user's coderef.
sub schedule {
  my $self = shift;
  my $time = shift;
  my $coderef = shift;

  unless($coderef) {
    croak 'Not enough arguments to Connection->schedule()';
  }
  unless(ref($coderef) eq 'CODE') {
    croak 'Second argument to schedule() isn\'t a coderef';
  }

  $time += time;
  $self->parent->enqueue_scheduled_event($time, $coderef, $self, @_);
}

sub schedule_output_event {
  my $self = shift;
  my $time = shift;
  my $coderef = shift;

  unless($coderef) {
    croak 'Not enough arguments to Connection->schedule()';
  }
  unless(ref($coderef) eq 'CODE') {
    croak 'Second argument to schedule() isn\'t a coderef';
  }

  $time += time;
  $self->parent->enqueue_output_event($time, $coderef, $self, @_);
}

# Lets J. Random IRCop connect one IRC server to another. How uninteresting.
# Takes at least 1 arg:  the name of the server to connect your server with
#            (optional)  the port to connect them on (default 6667)
#            (optional)  the server to connect to arg #1. Used mainly by
#                          servers to communicate with each other.
sub sconnect {
  my $self = shift;
  
  unless (@_) {
    croak "Not enough arguments to sconnect()";
  }
  $self->sl("CONNECT " . CORE::join(" ", @_));
}

# Sets/changes the IRC server which this instance should connect to.
# Takes 1 arg:  the name of the server (see below for possible syntaxes)
#                                       ((syntaxen? syntaxi? syntaces?))
sub server {
  my ($self) = shift;
  
  if (@_)  {
    # cases like "irc.server.com:6668"
    if (index($_[0], ':') > 0) {
      my ($serv, $port) = split /:/, $_[0];
      if ($port =~ /\D/) {
        carp "$port is not a valid port number in server()";
        return;
      }
      $self->{_server} = $serv;
      $self->port($port);
      
      # cases like ":6668"  (buried treasure!)
    } elsif (index($_[0], ':') == 0 and $_[0] =~ /^:(\d+)/) {
      $self->port($1);
      
      # cases like "irc.server.com"
    } else {
      $self->{_server} = shift;
    }
    return (1);
    
  } else {
    return $self->{_server};
  }
}


# sends a raw IRC line to the server, possibly with pacing
sub sl {
  my $self = shift;
  my $line = CORE::join '', @_;
  
  unless (@_) {
    croak "Not enough arguments to sl()";
  }
  
  if (! $self->pacing) {
    return $self->sl_real($line);
  }
  
  # calculate how long to wait before sending this line
  my $time = time;
  if ($time - $self->{_lastsl} > $self->pacing) {
    $self->{_lastsl} = $time;
  } else {
    $self->{_lastsl} += $self->pacing;
  }
  my $seconds = $self->{_lastsl} - $time;
  
  ### DEBUG DEBUG DEBUG
  if ($self->{_debug}) {
    print "S-> $seconds $line\n";
  }
  
  $self->schedule_output_event($seconds, \&sl_real, $line);
}


# Sends a raw IRC line to the server.
# Corresponds to the internal sirc function of the same name.
# Takes 1 arg:  string to send to server. (duh. :)
sub sl_real {
  my $self = shift;
  my $line = shift;
  
  unless ($line) {
    croak "Not enough arguments to sl_real()";
  }
  
  ### DEBUG DEBUG DEBUG
  if ($self->{_debug}) {
    print ">>> $line\n";
  }
  
  # RFC compliance can be kinda nice...
  my $rv = $self->ssl ?
      $self->socket->print("$line\015\012") :
      $self->socket->send("$line\015\012", 0);
  unless ($rv) {
    $self->handler("sockerror");
    return;
  }
  return $rv;
}

# Tells any server that you're an oper on to disconnect from the IRC network.
# Takes at least 1 arg:  the name of the server to disconnect
#            (optional)  a comment about why it was disconnected
sub squit {
  my $self = shift;
  
  unless (@_) {
    croak "Not enough arguments to squit()";
  }
  
  $self->sl("SQUIT $_[0]" . ($_[1] ? " :$_[1]" : ""));
}

# Gets various server statistics for the specified host.
# Takes at least 2 arg: the type of stats to request [chiklmouy]
#            (optional) the server to request from (default is current server)
sub stats {
  my $self = shift;
  
  unless (@_) {
    croak "Not enough arguments passed to stats()";
  }
  
  $self->sl("STATS $_[0]" . ($_[1] ? " $_[1]" : ""));
}

# If anyone still has SUMMON enabled, this will implement it for you.
# If not, well...heh.  Sorry.  First arg mandatory: user to summon.  
# Second arg optional: a server name.
sub summon {
  my $self = shift;
  
  unless (@_) {
    croak "Not enough arguments passed to summon()";
  }
  
  $self->sl("SUMMON $_[0]" . ($_[1] ? " $_[1]" : ""));
}

# Requests timestamp from specified server. Easy enough, right?
# Takes 1 optional arg:  a server name/mask to query
# renamed to not collide with things... -- aburke
sub timestamp {
  my ($self, $serv) = (shift, undef);
  
  $self->sl("TIME" . ($_[0] ? " $_[0]" : ""));
}

# Sends request for current topic, or changes it to something else lame.
# Takes at least 1 arg:  the channel whose topic you want to screw around with
#            (optional)  the new topic you want to impress everyone with
sub topic {
  my $self = shift;
  
  unless (@_) {
    croak "Not enough arguments to topic()";
  }
  
  # Can you tell I've been reading the Nethack source too much? :)
  $self->sl("TOPIC $_[0]" . ($_[1] ? " :$_[1]" : ""));
}

# Sends a trace request to the server. Whoop.
# Take 1 optional arg:  the server or nickname to trace.
sub trace {
  my $self = shift;
  
  $self->sl("TRACE" . ($_[0] ? " $_[0]" : ""));
}

# This method submitted by Dave Schmitt <dschmi1@umbc.edu>. Thanks, Dave!
sub unignore {
  my $self = shift;
  
  croak "Not enough arguments to unignore()" unless @_;
  
  if (@_ == 1) {
    if (exists $self->{_ignore}->{$_[0]}) {
      return @{ $self->{_ignore}->{$_[0]} };
    } else {
      return ();
    }
  } elsif (@_ > 1) {     # code defensively, remember...
    my $type = shift;
    
    # I moved this part further down as an Obsessive Efficiency
    # Initiative. It shouldn't be a problem if I do _parse right...
    # ... but those are famous last words, eh?
    unless (grep {$_ eq $type}
            qw(public msg ctcp notice channel nick other all)) {
      carp "$type isn't a valid type to unignore()";
      return;                                                    
       }
    
    if ( exists $self->{_ignore}->{$type} )  {
      # removes all specifed entries ala _Perl_Cookbook_ recipe 4.7
      my @temp = @{$self->{_ignore}->{$type}};
      @{$self->{_ignore}->{$type}}= ();
      my %seen = ();
      foreach my $item (@_) { $seen{$item}=1 }
      foreach my $item (@temp) {
        push(@{$self->{_ignore}->{$type}}, $item)
            unless ($seen{$item});
      }
    } else  {
      carp "no ignore entry for $type to remove";
    }
  }
}


# Requests userhost info from the server.
# Takes at least 1 arg: nickname(s) to look up.
sub userhost {
  my $self = shift;
  
  unless (@_) {
    croak 'Not enough args to userhost().';
  }
  
  $self->sl("USERHOST " . CORE::join (" ", @_));
}

# Sends a users request to the server, which may or may not listen to you.
# Take 1 optional arg:  the server to query.
sub users {
  my $self = shift;
  
  $self->sl("USERS" . ($_[0] ? " $_[0]" : ""));
}

# Asks the IRC server what version and revision of ircd it's running. Whoop.
# Takes 1 optional arg:  the server name/glob. (default is current server)
sub version {
  my $self = shift;
  
  $self->sl("VERSION" . ($_[0] ? " $_[0]" : ""));
}

# Sends a message to all opers on the network. Hypothetically.
# Takes 1 arg:  the text to send.
sub wallops {
  my $self = shift;
  
  unless ($_[0]) {
    croak 'No arguments passed to wallops()';
  }
  
  $self->sl("WALLOPS :" . CORE::join("", @_));
}

# Asks the server about stuff, you know. Whatever. Pass the Fritos, dude.
# Takes 2 optional args:  the bit of stuff to ask about
#                         an "o" (nobody ever uses this...)
sub who {
  my $self = shift;
  
  # Obfuscation!
  $self->sl("WHO" . (@_ ? " @_" : ""));
}

# If you've gotten this far, you probably already know what this does.
# Takes at least 1 arg:  nickmasks or channels to /whois
sub whois {
  my $self = shift;
  
  unless (@_) {
    croak "Not enough arguments to whois()";
  }
  return $self->sl("WHOIS " . CORE::join(",", @_));
}

# Same as above, in the past tense.
# Takes at least 1 arg:  nick to do the /whowas on
#            (optional)  max number of hits to display
#            (optional)  server or servermask to query
sub whowas {
  my $self = shift;
  
  unless (@_) {
    croak "Not enough arguments to whowas()";
  }
  return $self->sl("WHOWAS $_[0]" . ($_[1] ? " $_[1]" : "") .
                   (($_[1] && $_[2]) ? " $_[2]" : ""));
}

# This sub executes the default action for an event with no user-defined
# handlers. It's all in one sub so that we don't have to make a bunch of
# separate anonymous subs stuffed in a hash.
sub _default {
  my ($self, $event) = @_;
  my $verbose = $self->verbose;
  
  # Users should only see this if the programmer (me) fucked up.
  unless ($event) {
    croak "You EEEEEDIOT!!! Not enough args to _default()!";
  }
  
  # Reply to PING from server as quickly as possible.
  if ($event->type eq "ping") {
    $self->sl("PONG " . (CORE::join ' ', $event->args));
    
  } elsif ($event->type eq "disconnect") {
    
    # I violate OO tenets. (It's consensual, of course.)
    unless (keys %{$self->parent->{_connhash}} > 0) {
      die "No active connections left, exiting...\n";
    }
  }
  
  return 1;
}

1;


__END__

=head1 NAME

Net::IRC::Connection - Object-oriented interface to a single IRC connection

=head1 SYNOPSIS

Hard hat area: This section under construction.

=head1 DESCRIPTION

This documentation is a subset of the main Net::IRC documentation. If
you haven't already, please "perldoc Net::IRC" before continuing.

Net::IRC::Connection defines a class whose instances are individual
connections to a single IRC server. Several Net::IRC::Connection objects may
be handled simultaneously by one Net::IRC object.

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

