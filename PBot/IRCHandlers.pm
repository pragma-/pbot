# File: IRCHandlers.pm
# Authoer: pragma_
#
# Purpose: Subroutines to handle IRC events

package PBot::IRCHandlers;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw($logger $identify_password %channels $botnick %is_opped %unban_timeout %admins);
}

use vars @EXPORT_OK;

*logger = \$PBot::PBot::logger;
*unban_timeout = \%PBot::OperatorStuff::unban_timeout;
*admins = \%PBot::BotAdminStuff::admins;
*channels = \%PBot::ChannelStuff::channels;
*identify_password = \$PBot::PBot::identify_password;
*botnick = \$PBot::PBot::botnick;
*is_opped = \%PBot::OperatorStuff::is_opped;

use Time::HiRes qw(gettimeofday);

# IRC related subroutines
#################################################

sub on_connect {
  my $conn = shift;
  $logger->log("Connected!  Identifying with NickServ . . .\n");
  $conn->privmsg("nickserv", "identify $identify_password");
  $conn->{connected} = 1;
}

sub on_disconnect {
  my ($self, $event) = @_;
  $logger->log("Disconnected, attempting to reconnect...\n");
  $self->connect();
  if(not $self->connected) {
    sleep(5);
    on_disconnect($self, $event) 
  }
}

sub on_init {
  my ($self, $event) = @_;
  my (@args) = ($event->args);
  shift (@args);
  $logger->log("*** @args\n");
}

sub on_public {
  my ($conn, $event) = @_;
  
  my $from = $event->{to}[0];
  my $nick = $event->nick;
  my $user = $event->user;
  my $host = $event->host;
  my $text = $event->{args}[0];

  PBot::Interpreter::process_line($from, $nick, $user, $host, $text);
}

sub on_msg {
  my ($conn, $event) = @_;
  my ($nick, $host) = ($event->nick, $event->host);
  my $text = $event->{args}[0];

  $text =~ s/^!?(.*)/\!$1/;
  $event->{to}[0]   = $nick;
  $event->{args}[0] = $text;
  on_public($conn, $event);
}

sub on_notice {
  my ($conn, $event) = @_;
  my ($nick, $host) = ($event->nick, $event->host);
  my $text = $event->{args}[0];

  $logger->log("Received NOTICE from $nick $host '$text'\n");

  if($nick eq "NickServ" && $text =~ m/You are now identified/i) {
    foreach my $chan (keys %channels) {
      if($channels{$chan}{enabled} != 0) {
        $logger->log("Joining channel:  $chan\n");
        $conn->join($chan);
      }
    }
  }
}

sub on_action {
  my ($conn, $event) = @_;
  
  on_public($conn, $event);
}

sub on_mode {
  my ($conn, $event) = @_;
  my ($nick, $host) = ($event->nick, $event->host);
  my $mode = $event->{args}[0];
  my $target = $event->{args}[1];
  my $channel = $event->{to}[0];
  $channel = lc $channel;

  $logger->log("Got mode:  nick: $nick, host: $host, mode: $mode, target: " . (defined $target ? $target : "") . ", channel: $channel\n");

  if(defined $target && $target eq $botnick) { # bot targeted
    if($mode eq "+o") {
      $logger->log("$nick opped me in $channel\n");
      if(exists $is_opped{$channel}) {
        $logger->log("warning: erm, I was already opped?\n");
      }
      $is_opped{$channel}{timeout} = gettimeofday + 300; # 5 minutes
      PBot::OperatorStuff::perform_op_commands();
    } elsif($mode eq "-o") {
      $logger->log("$nick removed my ops in $channel\n");
      if(not exists $is_opped{$channel}) {
        $logger->log("warning: erm, I wasn't opped?\n");
      }
      delete $is_opped{$channel};
    }    
  } else {  # bot not targeted
    if($mode eq "+b") {
      if($nick eq "ChanServ") {
        $unban_timeout{$target}{timeout} = gettimeofday + 3600 * 2; # 2 hours
        $unban_timeout{$target}{channel} = $channel;
      }
    } elsif($mode eq "+e" && $channel eq $botnick) {
      foreach my $chan (keys %channels) {
        if($channels{$chan}{enabled} != 0) {
          $logger->log("Joining channel:  $chan\n");
          $conn->join($chan);
        }
      }
    }
  }
}

sub on_join {
  my ($conn, $event) = @_;
  my ($nick, $host, $channel) = ($event->nick, $event->host, $event->to);

  #$logger->log("$nick!$user\@$host joined $channel\n");
  #check_flood($nick, $host, $channel, 3, $FLOOD_JOIN);
}

sub on_departure {
  my ($conn, $event) = @_;
  my ($nick, $host, $channel) = ($event->nick, $event->host, $event->to);

  #check_flood($nick, $host, $channel, 3, $FLOOD_JOIN);

  if(exists $admins{$nick} && exists $admins{$nick}{login}) { 
    $logger->log("Whoops, $nick left while still logged in.\n");
    $logger->log("Logged out $nick.\n");
    delete $admins{$nick}{login};
  }
}

1;
