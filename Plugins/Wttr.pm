# File: Wttr.pm
# Author: pragma-
#
# Purpose: Weather command using Wttr.in.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Wttr;

use parent 'Plugins::Plugin';

use warnings; use strict;
use feature 'unicode_strings';
use utf8;

use feature 'switch';

no if $] >= 5.018, warnings => "experimental::smartmatch";

use PBot::Utils::LWPUserAgentCached;
use JSON;
use URI::Escape qw/uri_escape_utf8/;
use Getopt::Long qw(GetOptionsFromString);

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->wttrcmd(@_) }, "wttr", 0);
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
    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling_override", "ignorecase_always");

    my %options;
    my ($ret, $args) = GetOptionsFromString(
        $arguments,
        \%options,
        'u=s',
        'h',
        @wttr_options
    );

    return "/say $getopt_error -- $usage" if defined $getopt_error;
    return $usage                         if exists $options{h};
    $arguments = "@$args";

    my $hostmask          = defined $options{u} ? $options{u} : "$nick!$user\@$host";
    my $location_override = $self->{pbot}->{users}->get_user_metadata($from, $hostmask, 'location') // '';
    $arguments = $location_override if not length $arguments;

    if (defined $options{u} and not length $location_override) { return "No location set or user account does not exist."; }

    delete $options{u};

    if (not length $arguments) { return $usage; }

    $options{default} = 1 if not keys %options;

    if (defined $options{all}) {
        %options = ();
        map { my $opt = $_; $opt =~ s/\|.*$//; $options{$opt} = 1 } @wttr_options;
        delete $options{all};
        delete $options{default};
    }

    return $self->get_wttr($arguments, %options);
}

sub get_wttr {
    my ($self, $location, %options) = @_;

    my %cache_opt = (
        'namespace'          => 'wttr',
        'default_expires_in' => 3600
    );

    my $location_uri = uri_escape_utf8 $location;

    my $ua       = PBot::Utils::LWPUserAgentCached->new(\%cache_opt, timeout => 30);
    my $response = $ua->get("http://wttr.in/$location_uri?format=j1&m");

    my $json;

    if ($response->is_success) { $json = $response->decoded_content; }
    else                       { return "Failed to fetch weather data: " . $response->status_line; }

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
                $result .= "Currently: $c->{'weatherDesc'}->[0]->{'value'}: $c->{'temp_C'}C/$c->{'temp_F'}F; ";
                $result .= "Forecast: High: $w->{maxtempC}C/$w->{maxtempF}F, Low: $w->{mintempC}C/$w->{mintempF}F; ";
                $result .= "Condition changes: ";

                my $last_condition = $c->{'weatherDesc'}->[0]->{'value'};
                my $sep            = '';

                foreach my $hour (@{$w->{'hourly'}}) {
                    my $condition = $hour->{'weatherDesc'}->[0]->{'value'};
                    my $temp      = "$hour->{FeelsLikeC}C/$hour->{FeelsLikeF}F";
                    my $time      = sprintf "%04d", $hour->{'time'};
                    $time =~ s/(\d{2})$/:$1/;

                    if ($condition ne $last_condition) {
                        $result .= "$sep$time: $condition ($temp)";
                        $sep            = '-> ';
                        $last_condition = $condition;
                    }
                }

                if ($sep eq '') { $result .= $last_condition; }
                $result .= "; ";
            }

            when ('conditions') {
                $result .= "Current conditions: $c->{'weatherDesc'}->[0]->{'value'}: $c->{'temp_C'}C/$c->{'temp_F'}F (Feels like $c->{'FeelsLikeC'}C/$c->{'FeelsLikeF'}F); ";
                $result .= "Cloud cover: $c->{'cloudcover'}%; Visibility: $c->{'visibility'}km; ";
                $result .= "Wind: $c->{'windspeedKmph'}kph/$c->{'windspeedMiles'}mph $c->{'winddirDegree'}°/$c->{'winddir16Point'}; ";
                $result .= "Humidity: $c->{'humidity'}%; Precip: $c->{'precipMM'}mm; Pressure: $c->{'pressure'}hPa; UV Index: $c->{'uvIndex'}; ";
            }

            when ('forecast') {
                $result .= "Hourly forecast: ";
                my ($last_temp, $last_condition, $sep) = ('', '', '');
                foreach my $hour (@{$wttr->{'weather'}->[0]->{'hourly'}}) {
                    my $temp      = "$hour->{FeelsLikeC}C/$hour->{FeelsLikeF}F";
                    my $condition = $hour->{'weatherDesc'}->[0]->{'value'};
                    my $text      = '';

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
                        my $time = sprintf "%04d", $hour->{'time'};
                        $time =~ s/(\d{2})$/:$1/;
                        $result .= "$sep $time: $text";
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
                $result .= "Wind: $c->{'windspeedKmph'}kph/$c->{'windspeedMiles'}mph $c->{'winddirDegree'}°/$c->{'winddir16Point'}, ";
                $result .= "gust: $h->{'WindGustKmph'}kph/$h->{'WindGustMiles'}mph, chill: $h->{'WindChillC'}C/$h->{'WindChillF'}F; ";
            }

            when ('location') {
                my $l = $wttr->{'request'}->[0];
                $result .= "Location: $l->{'query'} ($l->{'type'}); ";
            }

            when ('dewpoint') { $result .= "Dew point: $h->{'DewPointC'}C/$h->{'DewPointF'}F; "; }

            when ('feelslike') { $result .= "Feels like: $h->{'FeelsLikeC'}C/$h->{'FeelsLikeF'}F; "; }

            when ('heatindex') { $result .= "Heat index: $h->{'HeatIndexC'}C/$h->{'HeatIndexF'}F; "; }

            when ('moon') {
                my $a = $w->{'astronomy'}->[0];
                $result .= "Moon: phase: $a->{'moon_phase'}, illumination: $a->{'moon_illumination'}%, rise: $a->{'moonrise'}, set: $a->{'moonset'}; ";
            }

            when ('sunrise') {
                my $a = $w->{'astronomy'}->[0];
                $result .= "Sun: rise: $a->{'sunrise'}, set: $a->{'sunset'}; ";
            }

            when ('sunhours') { $result .= "Hours of sun: $w->{'sunHour'}; "; }

            when ('snowfall') { $result .= "Total snow: $w->{'totalSnow_cm'}cm; "; }

            when ('uvindex') { $result .= "UV Index: $c->{'uvIndex'}; "; }

            when ('visibility') { $result .= "Visibility: $c->{'visibility'}km; "; }

            when ('cloudcover') { $result .= "Cloud cover: $c->{'cloudcover'}%; "; }

            default { $result .= "Option $_ coming soon; " unless lc $_ eq 'u'; }
        }
    }

    $result =~ s/;\s+$//;
    return $result;
}

1;
