# File: NickList.pm
# Author: pragma_
#
# Purpose: Maintains lists of nicks currently present in channels.
# Used to retrieve list of channels a nick is present in or to 
# determine if a nick is present in a channel.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::NickList;

use warnings;
use strict;

use Text::Levenshtein qw/fastdistance/;
use Data::Dumper;
use Carp ();
use Time::HiRes qw/gettimeofday/;

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

  $self->{pbot}->{event_dispatcher}->register_handler('irc.namreply',  sub { $self->on_namreply(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.join',      sub { $self->on_join(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.part',      sub { $self->on_part(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.quit',      sub { $self->on_quit(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.kick',      sub { $self->on_kick(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.nick',      sub { $self->on_nickchange(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.public',    sub { $self->on_activity(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.caction',   sub { $self->on_activity(@_) });
  
  # handlers for the bot itself joining/leaving channels
  $self->{pbot}->{event_dispatcher}->register_handler('pbot.join',    sub { $self->on_join_channel(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('pbot.part',    sub { $self->on_part_channel(@_) });
}

sub dumpnicks {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my $nicklist = Dumper($self->{nicklist});
  return $nicklist;
}

sub update_timestamp {
  my ($self, $channel, $nick) = @_;
  my $orig_nick = $nick;
  $channel = lc $channel;
  $nick = lc $nick;

  if (exists $self->{nicklist}->{$channel} and exists $self->{nicklist}->{$channel}->{$nick}) {
    $self->{nicklist}->{$channel}->{$nick}->{timestamp} = gettimeofday;
  } else {
    $self->{pbot}->{logger}->log("Adding nick '$orig_nick' to channel '$channel'\n") if $self->{pbot}->{registry}->get_value('nicklist', 'debug');
    $self->{nicklist}->{$channel}->{$nick} = { nick => $orig_nick, timestamp => gettimeofday };
  }
}

sub remove_channel {
  my ($self, $channel) = @_;
  delete $self->{nicklist}->{lc $channel};
}

sub add_nick {
  my ($self, $channel, $nick) = @_;
  $self->{pbot}->{logger}->log("Adding nick '$nick' to channel '$channel'\n") if $self->{pbot}->{registry}->get_value('nicklist', 'debug');
  $self->{nicklist}->{lc $channel}->{lc $nick} = { nick => $nick, timestamp => 0 };
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

  foreach my $channel (keys %{ $self->{nicklist} }) {
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

sub is_present_similar {
  my ($self, $channel, $nick, $similar) = @_;

  $channel = lc $channel;
  $nick = lc $nick;

=cut
  use Devel::StackTrace;
  my $trace = Devel::StackTrace->new(indent => 1, ignore_class => ['PBot::PBot', 'PBot::IRC']);
  $self->{pbot}->{logger}->log("is_present_similar stacktrace: " . $trace->as_string() . "\n");
=cut

  return 0 if not exists $self->{nicklist}->{$channel};
  return $self->{nicklist}->{$channel}->{$nick}->{nick} if $self->is_present($channel, $nick);
  return 0 if $nick =~ m/(?:^\$|\s)/;  # not nick-like

  my $percentage = $self->{pbot}->{registry}->get_value('interpreter', 'nick_similarity');
  $percentage = 0.20 if not defined $percentage;

  $percentage = $similar if defined $similar;

  my $now = gettimeofday;
  foreach my $person (sort { $self->{nicklist}->{$channel}->{$b}->{timestamp} <=> $self->{nicklist}->{$channel}->{$a}->{timestamp} } keys %{ $self->{nicklist}->{$channel} }) {
    return 0 if $now - $self->{nicklist}->{$channel}->{$person}->{timestamp} > 3600; # 1 hour
    my $distance = fastdistance($nick, $person);
    my $length = length $nick > length $person ? length $nick : length $person;

=cut
    my $p = $length != 0 ? $distance / $length : 0;
    $self->{pbot}->{logger}->log("[$percentage] $nick <-> $person: $p %\n");
=cut

    if ($length != 0 && $distance / $length <= $percentage) {
      return $self->{nicklist}->{$channel}->{$person}->{nick};
    }
  }

  return 0;
}

sub random_nick {
  my ($self, $channel) = @_;

  $channel = lc $channel;

  if (exists $self->{nicklist}->{$channel}) {
    my $now = gettimeofday;
    my @nicks = grep { $now - $self->{nicklist}->{$channel}->{$_}->{timestamp} < 3600 * 2 } keys %{ $self->{nicklist}->{$channel} };
    
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

sub on_activity {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->{to}[0]);
  $self->update_timestamp($channel, $nick);
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

  foreach my $channel (keys %{ $self->{nicklist} }) {
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

  foreach my $channel (keys %{ $self->{nicklist} }) {
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
