# File: NickList.pm
# Author: pragma_
#
# Purpose: Maintains lists of nicks currently present in channels.
# Used to retrieve list of channels a nick is present in or to 
# determine if a nick is present in a channel.

package PBot::NickList;

use warnings;
use strict;

use Data::Dumper;
use Carp ();

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot}    = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{nicklist} = {};

  $self->{pbot}->{registry}->add_default('text', 'nicklist', 'debug', '0');

  $self->{pbot}->{commands}->register(sub { $self->dumpnicks(@_) }, "dumpnicks", 60);

  $self->{pbot}->{event_dispatcher}->register_handler('irc.namreply', sub { $self->on_namreply(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.join',     sub { $self->on_join(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.part',     sub { $self->on_part(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',     sub { $self->on_quit(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',     sub { $self->on_kick(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.nick',     sub { $self->on_nickchange(@_) });
  
  # handlers for the bot itself joining/leaving channels
  $self->{pbot}->{event_dispatcher}->register_handler('pbot.join',    sub { $self->on_join_channel(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('pbot.part',    sub { $self->on_part_channel(@_) });
}

sub dumpnicks {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $nicklist = Dumper($self->{nicklist});
  return $nicklist;
}

sub remove_channel {
  my ($self, $channel) = @_;
  delete $self->{nicklist}->{lc $channel};
}

sub add_nick {
  my ($self, $channel, $nick) = @_;
  $self->{pbot}->{logger}->log("Adding nick '$nick' to channel '$channel'\n") if $self->{pbot}->{registry}->get_value('nicklist', 'debug');
  $self->{nicklist}->{lc $channel}->{lc $nick} = { nick => $nick };
}

sub remove_nick {
  my ($self, $channel, $nick) = @_;
  $self->{pbot}->{logger}->log("Removing nick '$nick' from channel '$channel'\n") if $self->{pbot}->{registry}->get_value('nicklist', 'debug');
  delete $self->{nicklist}->{lc $channel}->{lc $nick};
}

sub get_channels {
  my ($self, $nick) = @_;
  my @channels;

  $nick = lc $nick;

  foreach my $channel (keys $self->{nicklist}) {
    if (exists $self->{nicklist}->{$channel}->{$nick}) {
      push @channels, $channel;
    }
  }
  
  return \@channels;
}

sub is_present {
  my ($self, $channel, $nick) = @_;

  $channel = lc $channel;
  $nick = lc $nick;

  if (exists $self->{nicklist}->{$channel} and exists $self->{nicklist}->{$channel}->{$nick}) {
    return $self->{nicklist}->{$channel}->{$nick}->{nick};
  } else {
    return 0;
  }
}

sub random_nick {
  my ($self, $channel) = @_;

  $channel = lc $channel;

  if (exists $self->{nicklist}->{$channel}) {
    my @nicks = keys $self->{nicklist}->{$channel};
    my $nick = $nicks[rand @nicks];
    return $self->{nicklist}->{$channel}->{$nick}->{nick};
  } else {
    return undef;
  }
}

sub on_namreply {
  my ($self, $event_type, $event) = @_;
  my ($channel, $nicks) = ($event->{event}->{args}[2], $event->{event}->{args}[3]);
  
  foreach my $nick (split ' ', $nicks) {
    $nick =~ s/^[@+%]//; # remove OP/Voice/etc indicator from nick
    $self->add_nick($channel, $nick);
  }

  return 0;
}

sub on_join {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);
  $self->add_nick($channel, $nick);
  return 0;
}

sub on_part {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->to);
  $self->remove_nick($channel, $nick);
  return 0;
}

sub on_quit {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);

  foreach my $channel (keys $self->{nicklist}) {
    if ($self->is_present($channel, $nick)) {
      $self->remove_nick($channel, $nick);
    }
  }

  return 0;
}

sub on_kick {
  my ($self, $event_type, $event) = @_;
  my ($nick, $channel) = ($event->{event}->to, $event->{event}->{args}[0]);
  $self->remove_nick($channel, $nick);
  return 0;
}

sub on_nickchange {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $newnick) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);

  foreach my $channel (keys $self->{nicklist}) {
    if ($self->is_present($channel, $nick)) {
      $self->remove_nick($channel, $nick);
      $self->add_nick($channel, $newnick);
    }
  }

  return 0;
}

sub on_join_channel {
  my ($self, $event_type, $event) = @_;
  $self->remove_channel($event->{channel}); # clear nicklist to remove any stale nicks before repopulating with namreplies
  return 0;
}

sub on_part_channel {
  my ($self, $event_type, $event) = @_;
  $self->remove_channel($event->{channel});
  return 0;
}

1;
