# File: AntiTwitter.pm
# Author: pragma_
#
# Purpose: Warns people off from using @nick style addressing. Temp-bans if they
#          persist.

package PBot::Plugins::AntiTwitter;

use warnings;
use strict;

use Carp ();
use Time::HiRes qw/gettimeofday/;
use Time::Duration qw/duration/;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{event_dispatcher}->register_handler('irc.public', sub { $self->on_public(@_) });
  $self->{pbot}->{timer}->register(sub { $self->adjust_offenses }, 60 * 60 * 1, 'antitwitter');
  $self->{offenses} = {};
}

sub on_public {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $channel, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->{to}[0], $event->{event}->args);

  $channel = lc $channel;
  return 0 if not $self->{pbot}->{chanops}->can_gain_ops($channel);

  while ($msg =~ m/@([^,;: ]+)/g) {
    my $n = $1;
    if ($self->{pbot}->{nicklist}->is_present($channel, $n)) {
      $self->{offenses}->{$channel}->{$nick}->{offenses}++;
      $self->{offenses}->{$channel}->{$nick}->{time} = gettimeofday;

      given ($self->{offenses}->{$channel}->{$nick}->{offenses}) {
        when (1) {
          $event->{conn}->privmsg($nick, "$nick: Please do not use \@nick to address people. Drop the @ symbol; it's not necessary and it's ugly. Doing this again will result in a temporary ban.");
        }
        default {
          my $offenses = $self->{offenses}->{$channel}->{$nick}->{offenses} - 1;
          my $length = 60 * ($offenses * $offenses + 1);
          $self->{pbot}->{chanops}->ban_user_timed("*!*\@$host", $channel, $length);
          $self->{pbot}->{chanops}->gain_ops($channel);
          $length = duration $length;
          $event->{conn}->privmsg($nick, "$nick: Please do not use \@nick to address people. Drop the @ symbol; it's not necessary and it's ugly. You were warned. You will be allowed to speak again in $length.");
        }
      }
      last;
    }
  }
  return 0;
}

sub adjust_offenses {
  my $self = shift;
  my $now = gettimeofday;

  foreach my $channel (keys $self->{offenses}) {
    foreach my $nick (keys $self->{offenses}->{$channel}) {
      if ($now - $self->{offenses}->{$channel}->{$nick}->{time} >= 60 * 60 * 5) {
        if (--$self->{offenses}->{$channel}->{$nick}->{offenses} <= 0) {
          delete $self->{offenses}->{$channel}->{$nick};
          delete $self->{offenses}->{$channel} if not keys $self->{offenses}->{$channel};
        }
      }
    }
  }
}

1;
