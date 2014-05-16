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
          $self->{pbot}->chanops->{unban_timeout}->hash->{$channel}->{$target}{timeout} = gettimeofday + 3600 * 2; # 2 hours
          $self->{pbot}->chanops->{unban_timeout}->save;
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

  my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);
  $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "JOIN", $self->{pbot}->{messagehistory}->{MSG_JOIN});
  $self->{pbot}->antiflood->check_flood($channel, $nick, $user, $host, "JOIN", 4, 60 * 30, $self->{pbot}->{messagehistory}->{MSG_JOIN});
}

sub on_kick {
  my ($self, $conn, $event) = @_;
  my ($nick, $user, $host, $target, $channel, $reason) = ($event->nick, $event->user, $event->host, $event->to, $event->{args}[0], $event->{args}[1]);

  $self->{pbot}->logger->log("$nick!$user\@$host kicked $target from $channel ($reason)\n");

  my ($message_account) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($target);

  if(defined $message_account) {
    my $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($message_account);

    my ($target_nick, $target_user, $target_host) = $hostmask =~ m/^([^!]+)!([^@]+)@(.*)/;
    my $text = "KICKED by $nick!$user\@$host ($reason)";

    $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, $text, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
    $self->{pbot}->antiflood->check_flood($channel, $target_nick, $target_user, $target_host, $text, 4, 60 * 30, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
  }
}

sub on_departure {
  my ($self, $conn, $event) = @_;
  my ($nick, $user, $host, $channel, $args) = ($event->nick, $event->user, $event->host, $event->to, $event->args);

  my $text = uc $event->type;
  $text .= " $args";

  my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);

  if($text =~ m/^QUIT/) {
    # QUIT messages must be dispatched to each channel the user is on
    my @channels = $self->{pbot}->{messagehistory}->{database}->get_channels($message_account);
    foreach my $chan (@channels) {
      next if $chan !~ m/^#/;
      $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $chan, $text, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
    }
  } else {
    $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, $text, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});
  }

  $self->{pbot}->antiflood->check_flood($channel, $nick, $user, $host, $text, 4, 60 * 30, $self->{pbot}->{messagehistory}->{MSG_DEPARTURE});

  my $admin = $self->{pbot}->admins->find_admin($channel, "$nick!$user\@$host");
  if(defined $admin and $admin->{loggedin}) {
    $self->{pbot}->logger->log("Whoops, $nick left while still logged in.\n");
    $self->{pbot}->logger->log("Logged out $nick.\n");
    delete $admin->{loggedin};
  }
}

sub on_nickchange {
  my ($self, $conn, $event) = @_;
  my ($nick, $user, $host, $newnick) = ($event->nick, $event->user, $event->host, $event->args);

  $self->{pbot}->logger->log("$nick!$user\@$host changed nick to $newnick\n");

  my $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($message_account);
  my @channels = $self->{pbot}->{messagehistory}->{database}->get_channels($message_account);
  foreach my $channel (@channels) {
    next if $channel !~ m/^#/;
    $self->{pbot}->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $channel, "NICKCHANGE $newnick", $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE});
  }

  my $newnick_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($newnick, $user, $host);
  $self->{pbot}->{messagehistory}->{database}->devalidate_all_channels($newnick_account);
  $self->{pbot}->{messagehistory}->{database}->update_hostmask_data($newnick_account, { last_seen => scalar gettimeofday });

  $self->{pbot}->antiflood->check_flood("$nick!$user\@$host", $nick, $user, $host, "NICKCHANGE $newnick", 3, 60 * 30, $self->{pbot}->{messagehistory}->{MSG_NICKCHANGE});
}

sub pbot {
  my $self = shift;
  return $self->{pbot};
}

1;
