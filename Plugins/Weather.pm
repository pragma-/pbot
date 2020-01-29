# File: Weather.pm
# Author: pragma-
#
# Purpose: Weather command.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Weather;

use warnings;
use strict;

use feature 'unicode_strings';

use LWP::UserAgent::WithCache;
use XML::LibXML;
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
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{commands}->register(sub { $self->weathercmd(@_) },  "weather", 0);
}

sub unload {
  my $self = shift;
  $self->{pbot}->{commands}->unregister("weather");
}

sub weathercmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my $location_override = $self->{pbot}->{users}->get_loggedin_user_metadata($from, "$nick!$user\@$host", 'location') // '';

  $arguments = $location_override if not length $arguments;

  if (not length $arguments) {
    return "Usage: weather <location>";
  }

  return $self->get_weather($arguments);
}

sub get_weather {
  my ($self, $location) = @_;

  my %cache_opt = (
    'namespace' => 'accuweather',
    'default_expires_in' => 3600
  );

  my $ua = LWP::UserAgent::WithCache->new(\%cache_opt, timeout => 10);
  my $response = $ua->get("http://rss.accuweather.com/rss/liveweather_rss.asp?metric=0&locCode=$location");

  my $xml;
  if ($response->is_success) {
    $xml = $response->decoded_content;
  } else {
    return "Failed to fetch weather date: " . $response->status_line;
  }

  my $dom = XML::LibXML->load_xml(string => $xml);

  my $result = '';

  foreach my $channel ($dom->findnodes('//channel')) {
    my $title = $channel->findvalue('./title');
    my $description = $channel->findvalue('./description');

    if ($description eq 'Invalid Location') {
      return "Location $location not found. Use \"<city>, <country abbrev>\" (e.g. \"paris, fr\") or a US Zip Code or \"<city>, <state abbrev>, US\" (e.g., \"austin, tx, us\").";
    }

    $title =~ s/ - AccuW.*$//;
    $result .= "Weather for $title: ";
  }

  foreach my $item ($dom->findnodes('//item')) {
    my $title = $item->findvalue('./title');
    my $description = $item->findvalue('./description');

    if ($title =~ m/^Currently:/) {
      $title = $self->fix_temps($title);
      $result .= "$title; ";
    }

    if ($title =~ m/Forecast$/) {
      $description =~ s/ <img.*$//;
      $description = $self->fix_temps($description);
      $result .= "Forecast: $description";
      last;
    }
  }

  return $result;
}

sub fix_temps {
  my ($self, $text) = @_;
  $text =~ s|(-?\d+)\s*F|my $f = $1; my $c = ($f - 32 ) * 5 / 9; $c = sprintf("%.1d", $c); "${f}F/${c}C"|eg;
  return $text;
}

1;
