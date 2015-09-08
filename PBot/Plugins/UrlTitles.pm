# File: UrlTitles.pm
# Author: pragma-
#
# Purpose: Display titles of URLs in channel messages.

package PBot::Plugins::UrlTitles;

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

  $self->{pbot}->{registry}->add_default('text',  'general', 'show_url_titles',                 $conf{show_url_titles}                 // 1);
  $self->{pbot}->{registry}->add_default('array', 'general', 'show_url_titles_channels',        $conf{show_url_titles_channels}        // '.*');
  $self->{pbot}->{registry}->add_default('array', 'general', 'show_url_titles_ignore_channels', $conf{show_url_titles_ignore_channels} // 'none');

  $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->show_url_titles(@_) });
  $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->show_url_titles(@_) });
}

sub unload {
  my $self = shift;
}

sub show_url_titles {
  my ($self, $event_type, $event) = @_;
  my $channel = $event->{event}->{to}[0];
  my ($nick, $user, $host) = ($event->{event}->nick, $event->{event}->user, $event->{event}->host);
  my $msg = $event->{event}->{args}[0];

  return 0 if not $msg =~ m/https?:\/\/[^\s]/;

  if ($self->{pbot}->{ignorelist}->check_ignore($nick, $user, $host, $channel)) {
    my $admin = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
    if (!defined $admin || $admin->{level} < 10) {
      return 0;
    }
  }

  if($self->{pbot}->{registry}->get_value('general', 'show_url_titles')
      and not $self->{pbot}->{registry}->get_value($channel, 'no_url_titles')
      and not grep { $channel =~ /$_/i } $self->{pbot}->{registry}->get_value('general', 'show_url_titles_ignore_channels')
      and grep { $channel =~ /$_/i } $self->{pbot}->{registry}->get_value('general', 'show_url_titles_channels')) {

    while ($msg =~ s/(https?:\/\/[^\s]+)//i && ++$event->{interpreted} <= 3) {
      $self->{pbot}->{factoids}->{factoidmodulelauncher}->execute_module($channel, undef, $nick, $user, $host, $msg, "title", "$nick $1");
    }
  }

  return 0;
}

1;
