# File: Wttr.pm
# Author: pragma-
#
# Purpose: Weather command using Wttr.in.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Wttr;

use warnings;
use strict;

use feature 'unicode_strings';
use utf8;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use LWP::UserAgent::WithCache;
use JSON;
use Getopt::Long qw(GetOptionsFromString);
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
  $self->{pbot}->{commands}->register(sub { $self->wttrcmd(@_) },  "wttr", 0);
}

sub unload {
  my $self = shift;
  $self->{pbot}->{commands}->unregister("wttr");
}

sub wttrcmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my @wttr_options = (
    "conditions",
    "forecast",
    "feelslike",
    "uvindex",
    "visibility",
    "dewpoint",
    "heatindex",
    "cloudcover",
    "wind",
    "sunrise|sunset",
    "moon",
    "chances",
    "sunhours",
    "snowfall",
    "location",
    "default",
    "all",
  );

  my $usage = "Usage: wttr [-u <user account>] [location] [" . join(' ', map { "-$_" } @wttr_options) . "]";
  Getopt::Long::Configure("bundling_override", "ignorecase_always");

  my $getopt_error;
  local $SIG{__WARN__} = sub {
    $getopt_error = shift;
    chomp $getopt_error;
  };

  my %options;
  my ($ret, $args) = GetOptionsFromString($arguments,
    \%options,
    'u=s',
    'h',
    @wttr_options
  );

  return "/say $getopt_error -- $usage" if defined $getopt_error;
  return $usage if exists $options{h};
  $arguments = "@$args";

  my $hostmask = defined $options{u} ? $options{u} : "$nick!$user\@$host";
  my $location_override = $self->{pbot}->{users}->get_loggedin_user_metadata($from, $hostmask, 'location') // '';
  $arguments = $location_override if not length $arguments;

  if (defined $options{u} and not length $location_override) {
    return "No location set or user account does not exist.";
  }

  if (not length $arguments) {
    return $usage;
  }

  $options{default} = 1 if not keys %options;

  if (defined $options{all}) {
    %options = ();
    map { my $opt = $_; $opt =~ s/\|.*$//; $options{$opt} = 1 } @wttr_options;
    delete $options{all};
    delete $options{default};
  }

  return $self->get_weather($arguments, %options);
}

sub get_weather {
  my ($self, $location, %options) = @_;

  my %cache_opt = (
    'namespace' => 'wttr',
    'default_expires_in' => 3600
  );

  $location = lc $location;

  my $ua = LWP::UserAgent::WithCache->new(\%cache_opt, timeout => 10);
  my $response = $ua->get("http://wttr.in/$location?format=j1");

  my $json;
  if ($response->is_success) {
    $json = $response->decoded_content;
  } else {
    return "Failed to fetch weather data: " . $response->status_line;
  }

  my $wttr = decode_json $json;

  # title-case location
  $location = ucfirst lc $location;
  $location =~ s/( |\.)(\w)/$1 . uc $2/ge;

  my $result = "Weather for $location: ";

  my $c = $wttr->{'current_condition'}->[0];
  my $w = $wttr->{'weather'}->[0];
  my $h = $w->{'hourly'}->[0];

  foreach my $option (sort keys %options) {
    given ($option) {
      when ('default') {
        $result .= "Currently: $c->{'weatherDesc'}->[0]->{'value'}: $c->{'temp_F'}F/$c->{'temp_C'}C; ";
        $result .= "Forecast: High: $w->{maxtempF}F/$w->{maxtempC}C Low: $w->{mintempF}F/$w->{mintempC}C ";

        my $last_condition = $c->{'weatherDesc'}->[0]->{'value'};
        my $sep = '';

        foreach my $hour (@{ $w->{'hourly'} }) {
          my $condition = $hour->{'weatherDesc'}->[0]->{'value'};

          if ($condition ne $last_condition) {
            $result .= "$sep$condition";
            $sep = ' -> ';
            $last_condition = $condition;
          }
        }

        if ($sep eq '') {
          $result .= $last_condition;
        }
        $result .= "; ";
      }

      when ('conditions') {
        $result .= "Currently: $c->{'weatherDesc'}->[0]->{'value'}: $c->{'temp_F'}F/$c->{'temp_C'}C (Feels like $c->{'FeelsLikeF'}F/$c->{'FeelsLikeC'}C); ";
        $result .= "Cloud cover: $c->{'cloudcover'}%; Visibility: $c->{'visibility'}km; ";
        $result .= "Wind: $c->{'windspeedMiles'}M/$c->{'windspeedKmph'}K $c->{'winddirDegree'}°/$c->{'winddir16Point'}; ";
        $result .= "Humidity: $c->{'humidity'}%; Precip: $c->{'precipMM'}mm; Pressure: $c->{'pressure'}hPa; UV Index: $c->{'uvIndex'}; ";
      }

      when ('forecast') {
        $result .= "Hourly forecast: ";
        my ($last_temp, $last_condition, $sep) = ('', '', '');
        foreach my $hour (@{ $wttr->{'weather'}->[0]->{'hourly'} }) {
          my $temp = "$hour->{FeelsLikeF}F/$hour->{FeelsLikeC}C";
          my $condition = $hour->{'weatherDesc'}->[0]->{'value'};
          my $text = '';

          if ($temp ne $last_temp) {
            $text .= $temp;
            $last_temp = $temp;
          }

          if ($condition ne $last_condition) {
            $text .= ' ' if length $text;
            $text .= $condition;
            $last_condition = $condition;
          }

          if (length $text) {
            $result .= "$sep " . (sprintf "%04d", $hour->{'time'}) . ": $text";
            $sep = ', ';
          }
        }
        $result .= "; ";
      }

      when ('chances') {
        $result .= "Chances of: ";
        $result .= "Fog: $h->{'chanceoffog'}%, " if $h->{'chanceoffog'};
        $result .= "Frost: $h->{'chanceoffrost'}%, " if $h->{'chanceoffrost'};
        $result .= "High temp: $h->{'chanceofhightemp'}%, " if $h->{'chanceofhightemp'};
        $result .= "Overcast: $h->{'chanceofovercast'}%, " if $h->{'chanceofovercast'};
        $result .= "Rain: $h->{'chanceofrain'}%, " if $h->{'chanceofrain'};
        $result .= "Remaining dry: $h->{'chanceofremdry'}%, " if $h->{'chanceofremdry'};
        $result .= "Snow: $h->{'chanceofsnow'}%, " if $h->{'chanceofsnow'};
        $result .= "Sunshine: $h->{'chanceofsunshine'}%, " if $h->{'chanceofsunshine'};
        $result .= "Thunder: $h->{'chanceofthunder'}%, " if $h->{'chanceofthunder'};
        $result .= "Windy: $h->{'chanceofwindy'}%, " if $h->{'chanceofwindy'};
        $result =~ s/,\s+$/; /;
      }

      when ('wind') {
        $result .= "Wind: $c->{'windspeedMiles'}M/$c->{'windspeedKmph'}K $c->{'winddirDegree'}°/$c->{'winddir16Point'}, ";
        $result .= "gust: $h->{'WindGustMiles'}M/$h->{'WindGustKmph'}K, chill: $h->{'WindChillF'}F/$h->{'WindChillC'}C; ";
      }

      when ('location') {
        my $l = $wttr->{'request'}->[0];
        $result .= "Location: $l->{'query'} ($l->{'type'}); ";
      }

      when ('dewpoint') {
        $result .= "Dew point: $h->{'DewPointF'}F/$h->{'DewPointC'}C; ";
      }

      when ('feelslike') {
        $result .= "Feels like: $h->{'FeelsLikeF'}F/$h->{'FeelsLikeC'}C; ";
      }

      when ('heatindex') {
        $result .= "Heat index: $h->{'HeatIndexF'}F/$h->{'HeatIndexC'}C; ";
      }

      when ('moon') {
        my $a = $w->{'astronomy'}->[0];
        $result .= "Moon: phase: $a->{'moon_phase'}, illumination: $a->{'moon_illumination'}, rise: $a->{'moonrise'}, set: $a->{'moonset'}; ";
      }

      when ('sunrise') {
        my $a = $w->{'astronomy'}->[0];
        $result .= "Sun: rise: $a->{'sunrise'}, set: $a->{'sunset'}; ";
      }

      when ('sunhours') {
        $result .= "Hours of sun: $w->{'sunHour'}; ";
      }

      when ('snowfall') {
        $result .= "Total snow: $w->{'totalSnow_cm'}cm; ";
      }

      when ('uvindex') {
        $result .= "UV Index: $c->{'uvIndex'}; ";
      }

      when ('visibility') {
        $result .= "Visibility: $c->{'visibility'}km; ";
      }

      when ('cloudcover') {
        $result .= "Cloud cover: $c->{'cloudcover'}%; ";
      }

      default {
        $result .= "Option $_ coming soon; ";
      }
    }
  }

  $result =~ s/;\s+$//;
  return $result;
}

1;
