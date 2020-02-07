
package Plugins::RelayUnreg;

use warnings;
use strict;

use feature 'unicode_strings';

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
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{event_dispatcher}->register_handler('irc.public', sub { $self->on_public(@_) });
  $self->{queue} = [];
  $self->{notified} = {};
  $self->{pbot}->{timer}->register(sub { $self->check_queue }, 1, 'RelayUnreg');
}

sub unload {
  my $self = shift;
  $self->{pbot}->{timer}->unregister('RelayUnreg');
  $self->{pbot}->{event_dispatcher}->remove_handler('irc.public', __PACKAGE__);
}

sub on_public {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
  my $channel = lc $event->{event}->{to}[0];

  $msg =~ s/^\s+|\s+$//g;
  return 0 if not length $msg;

  # exit if channel hasn't muted $~a
  return 0 if not exists $self->{pbot}->{bantracker}->{banlist}->{$channel}->{'+q'}->{'$~a'};

  # exit if channel isn't +z
  my $chanmodes = $self->{pbot}->{channels}->get_meta($channel, 'MODE');
  return 0 if not defined $chanmodes or not $chanmodes =~ m/z/;

  my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($account);

  # debug
  # my $nickserv_text = $nickserv ? "is logged into $nickserv" : "is not logged in";
  # $self->{pbot}->{logger}->log("RelayUnreg: $nick!$user\@$host ($account) $nickserv_text.\n");

  # exit if user is identified
  return 0 if defined $nickserv && length $nickserv;

  my @filters = (
    qr{https://bryanostergaard.com/},
    qr{https://encyclopediadramatica.rs/Freenodegate},
    qr{https://MattSTrout.com/},
    qr{Contact me on twitter},
    qr{At the beginning there was only Chaos},
    qr{https://williampitcock.com/},
    qr{Achievement Method},
    qr{perceived death signal},
    qr{efnet},
    qr{https://evestigatorsucks.com},
    qr{eVestigator},
  );

  # don't notify/relay for spammers
  foreach my $filter (@filters) {
    if ($msg =~ m/$filter/i) {
      $self->{pbot}->{logger}->log("RelayUnreg: Ignoring filtered message.\n");
      return 0;
    }
  }

  # don't notify/relay for spammers
  return 0 if $self->{pbot}->{antispam}->is_spam($channel, $msg, 1);

  # don't notify/relay if user is voiced
  return 0 if $self->{pbot}->{nicklist}->get_meta($channel, $nick, '+v');

  unless (exists $self->{notified}->{lc $nick}) {
    $self->{pbot}->{logger}->log("RelayUnreg: Notifying $nick to register with NickServ in $channel.\n");
    $event->{conn}->privmsg($nick, "Please register your nick to speak in $channel. See https://freenode.net/kb/answer/registration and https://freenode.net/kb/answer/sasl");
    $self->{notified}->{lc $nick} = gettimeofday;
  }

  # don't relay unregistered chat unless enabled
  return 0 if not $self->{pbot}->{registry}->get_value($channel, 'relay_unregistered_chat');

  # add message to delay send queue to see if Sigyn kills them first (or if they leave)
  $self->{pbot}->{logger}->log("RelayUnreg: Queuing unregistered message for $channel: <$nick> $msg\n");
  push @{$self->{queue}}, [gettimeofday + 10, $channel, $nick, $user, $host, $msg];

  return 0;
}

sub check_queue {
  my $self = shift;
  my $now = gettimeofday;

  if (@{$self->{queue}}) {
    my ($time, $channel, $nick, $user, $host, $msg) = @{$self->{queue}->[0]};

    if ($now >= $time) {
      # if nick is still present in channel, send the message
      if ($self->{pbot}->{nicklist}->is_present($channel, $nick)) {
        # ensure they're not banned (+z allows us to see +q/+b messages as normal ones)
        my $banned = $self->{pbot}->{bantracker}->is_banned($nick, $user, $host, $channel);
        $self->{pbot}->{logger}->log("[RelayUnreg] $nick!$user\@$host $banned->{mode} as $banned->{banmask} in $banned->{channel} by $banned->{owner}, not relaying unregistered message\n") if $banned;
        $self->{pbot}->{conn}->privmsg($channel, "(unreg) <$nick> $msg") unless $banned;
      }
      shift @{$self->{queue}};
    }
  }

  # check notification timeouts here too, why not?
  if (keys %{$self->{notified}}) {
    my $timeout = gettimeofday - 60 * 15;
    foreach my $nick (keys %{$self->{notified}}) {
      if ($self->{notified}->{$nick} <= $timeout) {
        delete $self->{notified}->{$nick};
      }
    }
  }
}

1;
