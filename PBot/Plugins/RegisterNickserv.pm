
package PBot::Plugins::RegisterNickserv;

use warnings;
use strict;

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
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{event_dispatcher}->register_handler('irc.public', sub { $self->on_public(@_) });
  $self->{queue} = [];
  $self->{pbot}->{timer}->register(sub { $self->check_queue }, 1, 'RegisterNickserv');
}

sub unload {
  my $self = shift;
  $self->{pbot}->{timer}->unregister('RegisterNickserv');
}

sub on_public {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
  my $channel = lc $event->{event}->{to}[0];

  # exit if channel hasn't muted $~a
  return 0 if not exists $self->{pbot}->{bantracker}->{banlist}->{$channel}->{'+q'}->{'$~a'};

  my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($account);

  # debug
  # my $nickserv_text = $nickserv ? "is logged into $nickserv" : "is not logged in";
  # $self->{pbot}->{logger}->log("RegisterNickserv: $nick!$user\@$host ($account) $nickserv_text.\n");

  # exit if user is identified
  return 0 if defined $nickserv && length $nickserv;

  my @filters = (
    qr{https://bryanostergaard.com/},
    qr{https://encyclopediadramatica.rs/Freenodegate},
    qr{https://MattSTrout.com/},
    qr{Contact me on twitter},
    qr{At the beginning there was only Chaos},
    qr{https://williampitcock.com/},
    qr{efnet},
  );

  foreach my $filter (@filters) {
    if ($msg =~ m/$filter/i) {
      $self->{pbot}->{logger}->log("RegisterNickserv: Ignoring filtered message.\n");
      return 0;
    }
  }

  $self->{pbot}->{logger}->log("RegisterNickserv: Notifying $nick to register with NickServ in $channel.\n");
  $event->{conn}->privmsg($nick, "Please register your nick to speak in $channel. See https://freenode.net/kb/answer/registration and https://freenode.net/kb/answer/sasl");

  # don't relay unregistered chat unless enabled
  return 0 if not $self->{pbot}->{registry}->get_value($channel, 'relay_unregistered_chat');

  # add message to delay send queue to see if Sigyn kills them first (or if they leave)
  $self->{pbot}->{logger}->log("RegisterNickserv: Queuing unregistered message for $channel: <$nick> $msg\n");
  push @{$self->{queue}}, [gettimeofday + 10, $channel, $nick, $msg];

  return 0;
}

sub check_queue {
  my $self = shift;
  my $now = gettimeofday;

  return if not @{$self->{queue}};

  my ($time, $channel, $nick, $msg) = @{$self->{queue}->[0]};

  if ($now >= $time) {
    # if nick is still present in channel, send the message
    if ($self->{pbot}->{nicklist}->is_present($channel, $nick)) {
      $self->{pbot}->{conn}->privmsg($channel, "(unregistered) <$nick> $msg");
    }
    shift @{$self->{queue}};
  }
}

1;
