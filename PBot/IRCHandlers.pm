# File: IRCHandlers.pm
# Author: pragma_
#
# Purpose: Subroutines to handle IRC events

package PBot::IRCHandlers;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Carp();
use Time::HiRes qw(gettimeofday);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to IRCHandlers should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
 
  my $pbot = delete $conf{pbot};
  Carp::croak("Missing pbot parameter to IRCHandlers") if not defined $pbot;

  $self->{pbot} = $pbot;
}

# IRC related subroutines
#################################################

sub on_connect {
  my ($self, $conn) = @_;
  $self->{pbot}->logger->log("Connected!  Identifying with NickServ . . .\n");
  $conn->privmsg("nickserv", "identify " . $self->pbot->identify_password);
  $conn->{connected} = 1;
}

sub on_disconnect {
  my ($self, $conn, $event) = @_;
  $self->{pbot}->logger->log("Disconnected, attempting to reconnect...\n");
  $conn->connect();
  if(not $conn->connected) {
    sleep(5);
    $self->on_disconnect($self, $conn, $event);
  }
}

sub on_init {
  my ($self, $conn, $event) = @_;
  my (@args) = ($event->args);
  shift (@args);
  $self->{pbot}->logger->log("*** @args\n");
}

sub on_public {
  my ($self, $conn, $event) = @_;
  
  my $from = $event->{to}[0];
  my $nick = $event->nick;
  my $user = $event->user;
  my $host = $event->host;
  my $text = $event->{args}[0];

  $self->pbot->interpreter->process_line($from, $nick, $user, $host, $text);
}

sub on_msg {
  my ($self, $conn, $event) = @_;
  my ($nick, $host) = ($event->nick, $event->host);
  my $text = $event->{args}[0];

  $text =~ s/^!?(.*)/\!$1/;
  $event->{to}[0]   = $nick;
  $event->{args}[0] = $text;
  $self->on_public($conn, $event);
}

sub on_notice {
  my ($self, $conn, $event) = @_;
  my ($nick, $host) = ($event->nick, $event->host);
  my $text = $event->{args}[0];

  $self->{pbot}->logger->log("Received NOTICE from $nick $host '$text'\n");

  if($nick eq "NickServ" && $text =~ m/You are now identified/i) {
    foreach my $chan (keys %{ $self->{pbot}->channels->channels }) {
      if(${ $self->{pbot}->channels->channels }{$chan}{enabled} != 0) {
        $self->{pbot}->logger->log("Joining channel: $chan\n");
        $conn->join($chan);
      }
    }
  }
}

sub on_action {
  my ($self, $conn, $event) = @_;
  
  $self->on_public($conn, $event);
}

sub on_mode {
  my ($self, $conn, $event) = @_;
  my ($nick, $host) = ($event->nick, $event->host);
  my $mode = $event->{args}[0];
  my $target = $event->{args}[1];
  my $channel = $event->{to}[0];
  $channel = lc $channel;

  $self->{pbot}->logger->log("Got mode:  nick: $nick, host: $host, mode: $mode, target: " . (defined $target ? $target : "") . ", channel: $channel\n");

  if(defined $target && $target eq $self->{pbot}->botnick) { # bot targeted
    if($mode eq "+o") {
      $self->{pbot}->logger->log("$nick opped me in $channel\n");
      if(exists $self->{pbot}->chanops->{is_opped}->{$channel}) {
        $self->{pbot}->logger->log("erm, I was already opped?\n");
      }
      $self->{pbot}->chanops->{is_opped}->{$channel}{timeout} = gettimeofday + 300; # 5 minutes
      $self->{pbot}->chanops->perform_op_commands();
    } elsif($mode eq "-o") {
      $self->{pbot}->logger->log("$nick removed my ops in $channel\n");
      if(not exists $self->{pbot}->chanops->{is_opped}->{$channel}) {
        $self->{pbot}->logger->log("warning: erm, I wasn't opped?\n");
      }
      delete $self->{pbot}->chanops->{is_opped}->{$channel};
    }    
  } else {  # bot not targeted
    if($mode eq "+b") {
      if($nick eq "ChanServ") {
        $self->{pbot}->chanops->{unban_timeout}->{$target}{timeout} = gettimeofday + 3600 * 2; # 2 hours
        $self->{pbot}->chanops->{unban_timeout}->{$target}{channel} = $channel;
      }
    } elsif($mode eq "+e" && $channel eq $self->{pbot}->botnick) {
      foreach my $chan (keys %{ $self->{pbot}->channels->channels }) {
        if($self->channels->{channels}->{$chan}{enabled} != 0) {
          $self->{pbot}->logger->log("Joining channel: $chan\n");
          $self->{pbot}->conn->join($chan);
        }
      }
    }
  }
}

sub on_join {
  my ($self, $conn, $event) = @_;
  my ($nick, $user, $host, $channel) = ($event->nick, $event->user, $event->host, $event->to);

  #$self->{pbot}->logger->log("$nick!$user\@$host joined $channel\n");
  $self->{pbot}->antiflood->check_flood($channel, $nick, $user, $host, "JOIN", 3, 90, $self->{pbot}->{FLOOD_JOIN});
}

sub on_departure {
  my ($self, $conn, $event) = @_;
  my ($nick, $host, $channel) = ($event->nick, $event->host, $event->to);

=cut
  if(exists $admins{$nick} && exists $admins{$nick}{login}) { 
    $self->{pbot}->logger->log("Whoops, $nick left while still logged in.\n");
    $self->{pbot}->logger->log("Logged out $nick.\n");
    delete $admins{$nick}{login};
  }
=cut
}

sub pbot {
  my $self = shift;
  return $self->{pbot};
}

1;
