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
  $self->{pbot}->logger->log("Connected!\n");
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

  $text =~ s/^\Q$self->{pbot}->{trigger}\E?(.*)/$self->{pbot}->{trigger}$1/;
  $event->{to}[0]   = $nick;
  $event->{args}[0] = $text;
  $self->on_public($conn, $event);
}

sub on_notice {
  my ($self, $conn, $event) = @_;
  my ($nick, $host) = ($event->nick, $event->host);
  my $text = $event->{args}[0];

  $self->{pbot}->logger->log("Received NOTICE from $nick $host '$text'\n");

  if($nick eq "NickServ" && $text =~ m/This nickname is registered/) {
    $self->{pbot}->logger->log("Identifying with NickServ . . .\n");
    $conn->privmsg("nickserv", "identify " . $self->pbot->identify_password);
  }
  
  if($nick eq "NickServ" && $text =~ m/You are now identified/) {
    foreach my $chan (keys %{ $self->{pbot}->channels->channels->hash }) {
      if($self->{pbot}->channels->channels->hash->{$chan}{enabled}) {
        $self->{pbot}->logger->log("Joining channel: $chan\n");
        $conn->join($chan);
      }
    }
    $self->{pbot}->{joined_channels} = 1;
  }
}

sub on_action {
  my ($self, $conn, $event) = @_;

  $event->{args}[0] = "/me " . $event->{args}[0];
  
  $self->on_public($conn, $event);
}

sub on_mode {
  my ($self, $conn, $event) = @_;
  my ($nick, $user, $host) = ($event->nick, $event->user, $event->host);
  my $mode_string = $event->{args}[0];
  my $channel = $event->{to}[0];
  $channel = lc $channel;

  my ($mode, $modifier);
  my $i = 0;
  my $target;

  while($mode_string =~ m/(.)/g) {
    my $char = $1;

    if($char eq '-' or $char eq '+') {
      $modifier = $char;
      next;
    }

    $mode = $modifier . $char;
    $target = $event->{args}[++$i];

    $self->{pbot}->logger->log("Got mode: source: $nick!$user\@$host, mode: $mode, target: " . (defined $target ? $target : "(undef)") . ", channel: $channel\n");

    if($mode eq "-b" or $mode eq "+b" or $mode eq "-q" or $mode eq "+q") {
      $self->{pbot}->bantracker->track_mode("$nick!$user\@$host", $mode, $target, $channel);
    }

    if(defined $target && $target eq $self->{pbot}->botnick) { # bot targeted
      if($mode eq "+o") {
        $self->{pbot}->logger->log("$nick opped me in $channel\n");
        $self->{pbot}->chanops->{is_opped}->{$channel}{timeout} = gettimeofday + 300; # 5 minutes
        $self->{pbot}->chanops->perform_op_commands($channel);
      } 
      elsif($mode eq "-o") {
        $self->{pbot}->logger->log("$nick removed my ops in $channel\n");
        delete $self->{pbot}->chanops->{is_opped}->{$channel};
      }
      elsif($mode eq "+b") {
        $self->{pbot}->logger->log("Got banned in $channel, attempting unban.");
        $conn->privmsg("chanserv", "unban $channel");
      }    
    } 
    else {  # bot not targeted
      if($mode eq "+b") {
        if($nick eq "ChanServ") {
          $self->{pbot}->chanops->{unban_timeout}->hash->{$target}{timeout} = gettimeofday + 3600 * 2; # 2 hours
          $self->{pbot}->chanops->{unban_timeout}->hash->{$target}{channel} = $channel;
          $self->{pbot}->chanops->{unban_timeout}->save_hash();
        }
      } 
      elsif($mode eq "+e" && $channel eq $self->{pbot}->botnick) {
        foreach my $chan (keys %{ $self->{pbot}->channels->channels->hash }) {
          if($self->channels->channels->hash->{$chan}{enabled}) {
            $self->{pbot}->logger->log("Joining channel: $chan\n");
            $self->{pbot}->conn->join($chan);
          }
        }

        $self->{pbot}->{joined_channels} = 1;
      }
    }
  }
}

sub on_join {
  my ($self, $conn, $event) = @_;
  my ($nick, $user, $host, $channel) = ($event->nick, $event->user, $event->host, $event->to);

  $self->{pbot}->antiflood->check_flood($channel, $nick, $user, $host, "JOIN", 4, 60 * 30, $self->{pbot}->antiflood->{FLOOD_JOIN});
}

sub on_departure {
  my ($self, $conn, $event) = @_;
  my ($nick, $user, $host, $channel, $args) = ($event->nick, $event->user, $event->host, $event->to, $event->args);

  my $text = uc $event->type;
  $text .= " $args";

  $self->{pbot}->antiflood->check_flood($channel, $nick, $user, $host, $text, 4, 60 * 30, $self->{pbot}->antiflood->{FLOOD_JOIN});

  my $admin = $self->{pbot}->admins->find_admin($channel, "$nick!$user\@$host");
  if(defined $admin and $admin->{loggedin}) {
    $self->{pbot}->logger->log("Whoops, $nick left while still logged in.\n");
    $self->{pbot}->logger->log("Logged out $nick.\n");
    delete $admin->{loggedin};
  }
}

sub pbot {
  my $self = shift;
  return $self->{pbot};
}

1;
