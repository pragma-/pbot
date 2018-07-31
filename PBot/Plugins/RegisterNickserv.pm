
package PBot::Plugins::RegisterNickserv;

use warnings;
use strict;

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
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{event_dispatcher}->register_handler('irc.public', sub { $self->on_public(@_) });
}

sub unload {
  my $self = shift;
}

sub on_public {
  my ($self, $event_type, $event) = @_;
  my ($nick, $user, $host, $msg) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host, $event->{event}->args);
  my $channel = lc $event->{event}->{to}[0];

  if ($self->{pbot}->{ignorelist}->check_ignore($nick, $user, $host, $channel, 1)) {
    my $admin = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
    if (!defined $admin || $admin->{level} < 10) {
      return 0;
    }
  }

  # exit if channel hasn't muted $~a
  return 0 if not exists $self->{pbot}->{bantracker}->{banlist}->{$channel}->{'+q'}->{'$~a'};

  my $account = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
  my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($account);

  my $nickserv_text = $nickserv ? "is logged into $nickserv" : "is not logged in";
  $self->{pbot}->{logger}->log("RegisterNickserv: $nick!$user\@$host ($account) $nickserv_text.\n");

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
  $event->{conn}->privmsg($nick, "Please register your nick to speak in $channel. https://freenode.net/kb/answer/registration");

  # don't relay unregistered chat unless enabled
  return 0 if not $self->{pbot}->{registry}->get_value($channel, 'relay_unregistered_chat');

  $self->{pbot}->{logger}->log("RegisterNickserv: Relaying unregistered message to $channel: <$nick> $msg\n");
  $event->{conn}->privmsg($channel, "(unregistered) <$nick> $msg");

  return 0;
}

1;
