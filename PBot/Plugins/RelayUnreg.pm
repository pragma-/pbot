
package PBot::Plugins::RelayUnreg;

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
  $self->{pbot}->{timer}->register(sub { $self->check_queue }, 1, 'RelayUnreg');
}

sub unload {
  my $self = shift;
  $self->{pbot}->{timer}->unregister('RelayUnreg');
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

  foreach my $filter (@filters) {
    if ($msg =~ m/$filter/i) {
      $self->{pbot}->{logger}->log("RelayUnreg: Ignoring filtered message.\n");
      return 0;
    }
  }

  return 0 if $self->{pbot}->{nicklist}->get_meta($channel, $nick, '+v');

  $self->{pbot}->{logger}->log("RelayUnreg: Notifying $nick to register with NickServ in $channel.\n");
  $event->{conn}->privmsg($nick, "Please register your nick to speak in $channel. See https://freenode.net/kb/answer/registration and https://freenode.net/kb/answer/sasl");

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

  return if not @{$self->{queue}};

  my ($time, $channel, $nick, $user, $host, $msg) = @{$self->{queue}->[0]};

  if ($now >= $time) {
    # if nick is still present in channel, send the message
    if ($self->{pbot}->{nicklist}->is_present($channel, $nick)) {
      # ensure they're not banned (+z allows us to see +q/+b messages as normal ones)
      my $message_account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
      my @nickserv_accounts = $self->{pbot}->{messagehistory}->{database}->get_nickserv_accounts($message_account);
      push @nickserv_accounts, undef;

      my $no_relay = 0;

      foreach my $nickserv_account (@nickserv_accounts) {
        my $baninfos = $self->{pbot}->{bantracker}->get_baninfo("$nick!$user\@$host", $channel, $nickserv_account);

        if(defined $baninfos) {
          foreach my $baninfo (@$baninfos) {
            if($self->{pbot}->{antiflood}->whitelisted($baninfo->{channel}, $baninfo->{banmask}, 'ban') || $self->{pbot}->{antiflood}->whitelisted($baninfo->{channel}, "$nick!$user\@$host", 'user')) {
              $self->{pbot}->{logger}->log("[RelayUnreg] $nick!$user\@$host banned as $baninfo->{banmask} in $baninfo->{channel}, but allowed through whitelist\n");
            } else {
              if($channel eq lc $baninfo->{channel}) {
                my $mode = $baninfo->{type} eq "+b" ? "banned" : "quieted";
                $self->{pbot}->{logger}->log("[RelayUnreg] $nick!$user\@$host $mode as $baninfo->{banmask} in $baninfo->{channel} by $baninfo->{owner}, not relaying unregistered message\n");
                $no_relay = 1;
                last;
              }
            }
          }
        }
      }

      $self->{pbot}->{conn}->privmsg($channel, "(unreg) <$nick> $msg") unless $no_relay;
    }
    shift @{$self->{queue}};
  }
}

1;
