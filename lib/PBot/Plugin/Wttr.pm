# File: Wttr.pm
#
# Purpose: Weather command using Wttr.in.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Wttr;
use parent 'PBot::Plugin::Base';

use PBot::Imports;
use PBot::Core::Utils::LWPUserAgentCached;

use JSON;
use URI::Escape qw/uri_escape_utf8/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->add(
        name   => 'wttr',
        help   => 'Provides weather information via wttr.in',
        subref => sub { $self->cmd_wttr(@_) },
    );
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->remove('wttr');
}

sub cmd_wttr {
    my ($self, $context) = @_;

    my $arguments = $context->{arguments};

    my @wttr_options = (
        'default',
        'all',
        'conditions',
        'forecast',
        'feelslike',
        'uvindex',
        'visibility',
        'dewpoint',
        'heatindex',
        'cloudcover',
        'wind',
        'sun',
        'sunhours',
        'moon',
        'chances',
        'snowfall',
        'location',
        'qlocation',
        'time',
        'population',
    );

    my $usage = "Usage: wttr (<location> | -u <user account>) [" . join(' ', map { "-$_" } @wttr_options) . "]; to have me remember your location, use `my location <location>`.";

    my %options;

    my ($opt_args, $opt_error) = $self->{pbot}->{interpreter}->getopt(
        $arguments,
        \%options,
        ['bundling_override', 'ignorecase_always'],
        'u=s',
        'h',
        @wttr_options,
    );

    return "/say $opt_error -- $usage" if defined $opt_error;
    return $usage                      if exists $options{h};

    $arguments = "@$opt_args";

    if (defined $options{u}) {
        my $username = delete $options{u};

        my $userdata = $self->{pbot}->{users}->{storage}->get_data($username);
        return "No such user account $username." if not defined $userdata;
        return "User account does not have `location` set." if not exists $userdata->{location};
        $arguments = $userdata->{location};
    } else {
        if (not length $arguments) {
            $arguments = $self->{pbot}->{users}->get_user_metadata($context->{from}, $context->{hostmask}, 'location') // '';
        }
    }

    if (not length $arguments) { return $usage; }

    $options{default} = 1 if not keys %options;

    if (defined $options{all}) {
        %options = ();
        map { my $opt = $_; $opt =~ s/\|.*$//; $options{$opt} = 1 } @wttr_options;
        delete $options{all};
        delete $options{default};
    }

    my @opts = keys %options;

    return $self->get_wttr($arguments, \@opts, \@wttr_options);
}

sub get_wttr {
    my ($self, $location, $options, $order) = @_;

    my %cache_opt = (
        'namespace'          => 'wttr',
        'default_expires_in' => 3600
    );

    my $location_uri = uri_escape_utf8 $location;

    my $ua       = PBot::Core::Utils::LWPUserAgentCached->new(\%cache_opt, timeout => 30);
    my $response = $ua->get("http://wttr.in/$location_uri?format=j1&m");

    my $json;

    if ($response->is_success) {
        $json = $response->decoded_content;
    } else {
        return "Failed to fetch weather data: " . $response->status_line;
    }

    my $wttr = eval { decode_json $json };

    if ($@) {
        # error decoding json so it must not be json -- return as-is
        $@ = undef;
        my $error = $json;
        if ($error =~ /^Unknown location/) {
            $error = "Unknown location: $location";
        }
        return $error;
    }

    # title-case location
    $location = ucfirst lc $location;
    $location =~ s/( |\.)(\w)/$1 . uc $2/ge;

    $location =~ s/United States of America/USA/;

    my $result = "$location: ";

    my $c = $wttr->{'current_condition'}->[0];
    my $w = $wttr->{'weather'}->[0];
    my $h = $w->{'hourly'}->[0];

    my ($obsdate, $obstime) = split / /, $c->{'localObsDateTime'}, 2;
    my ($obshour, $obsminute) = split /:/, $obstime;
    if ($obsminute =~ s/ PM$//) {
        $obshour += 12;
    } else {
        $obsminute =~ s/ AM$//;
    }

    if (@$options == 1 and $options->[0] eq 'default') {
        push @$options, ('chances', 'time');
    }

    foreach my $option (@$order) {
        next if not grep { $_ eq $option } @$options;
        given ($option) {
            when ('default') {
                $result .= "Currently: $c->{'weatherDesc'}->[0]->{'value'}: $c->{'temp_C'}C/$c->{'temp_F'}F";

                if ($c->{'FeelsLikeC'} != $c->{'temp_C'}) {
                    $result .= " (Feels like $c->{'FeelsLikeC'}C/$c->{'FeelsLikeF'}F); ";
                } else {
                    $result .= '; ';
                }

                $result .= "Forecast: High: $w->{maxtempC}C/$w->{maxtempF}F, Low: $w->{mintempC}C/$w->{mintempF}F; ";

                my $conditions = "Condition changes: ";

                my $last_condition = $c->{'weatherDesc'}->[0]->{'value'};
                my $sep            = '';

                foreach my $hour (@{$w->{'hourly'}}) {
                    my $condition = $hour->{'weatherDesc'}->[0]->{'value'};
                    my $temp      = "$hour->{FeelsLikeC}C/$hour->{FeelsLikeF}F";
                    my $time      = sprintf "%04d", $hour->{'time'};
                    $time =~ s/(\d{2})$/:$1/;

                    if ($condition ne $last_condition) {
                        my ($hour, $minute) = split /:/, $time;
                        if (($hour > $obshour) or ($hour == $obshour and $minute >= $obsminute)) {
                            $conditions .= "$sep$time: $condition ($temp)";
                            $sep            = ' -> ';
                            $last_condition = $condition;
                        }
                    }
                }

                $result .= "$conditions; " if length $sep;

                $result .= "Cloud cover: $c->{'cloudcover'}%; Visibility: $c->{'visibility'}km; ";
                $result .= "Wind: $c->{'windspeedKmph'}kph/$c->{'windspeedMiles'}mph $c->{'winddirDegree'}°/$c->{'winddir16Point'}; ";
                $result .= "Humidity: $c->{'humidity'}%; Precip: $c->{'precipMM'}mm; Pressure: $c->{'pressure'}hPa; UV Index: $c->{'uvIndex'}";

                $result .= ";\n";
            }

            when ('conditions') {
                $result .= "Current conditions: $c->{'weatherDesc'}->[0]->{'value'}: $c->{'temp_C'}C/$c->{'temp_F'}F";
                if ($c->{'FeelsLikeC'} != $c->{'temp_C'}) {
                    $result .= " (Feels like $c->{'FeelsLikeC'}C/$c->{'FeelsLikeF'}F); ";
                } else {
                    $result .= '; ';
                }
                $result .= "Cloud cover: $c->{'cloudcover'}%; Visibility: $c->{'visibility'}km; ";
                $result .= "Wind: $c->{'windspeedKmph'}kph/$c->{'windspeedMiles'}mph $c->{'winddirDegree'}°/$c->{'winddir16Point'}; ";
                $result .= "Humidity: $c->{'humidity'}%; Precip: $c->{'precipMM'}mm; Pressure: $c->{'pressure'}hPa; UV Index: $c->{'uvIndex'};\n";
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
                        $text .= "($condition)";
                        $last_condition = $condition;
                    }

                    if (length $text) {
                        my $time = sprintf '%04d', $hour->{'time'};
                        $time =~ s/(\d{2})$/:$1/;
                        my ($hour, $minute) = split /:/, $time;
                        if (($hour > $obshour) or ($hour == $obshour and $minute >= $obsminute)) {
                            $result .= "$sep $time: $text";
                            $sep = ', ';
                        }
                    }
                }
                $result .= ";\n";
            }

            when ('chances') {
                $result .= 'Chances of: ';
                $result .= 'Fog: '           . $h->{'chanceoffog'}      . '%, '  if $h->{'chanceoffog'};
                $result .= 'Frost: '         . $h->{'chanceoffrost'}    . '%, '  if $h->{'chanceoffrost'};
                $result .= 'High temp: '     . $h->{'chanceofhightemp'} . '%, '  if $h->{'chanceofhightemp'};
                $result .= 'Overcast: '      . $h->{'chanceofovercast'} . '%, '  if $h->{'chanceofovercast'};
                $result .= 'Rain: '          . $h->{'chanceofrain'}     . '%, '  if $h->{'chanceofrain'};
                $result .= 'Remaining dry: ' . $h->{'chanceofremdry'}   . '%, '  if $h->{'chanceofremdry'};
                $result .= 'Snow: '          . $h->{'chanceofsnow'}     . '%, '  if $h->{'chanceofsnow'};
                $result .= 'Sunshine: '      . $h->{'chanceofsunshine'} . '%, '  if $h->{'chanceofsunshine'};
                $result .= 'Thunder: '       . $h->{'chanceofthunder'}  . '%, '  if $h->{'chanceofthunder'};
                $result .= 'Windy: '         . $h->{'chanceofwindy'}    . '%, '  if $h->{'chanceofwindy'};
                $result =~ s/,\s+$/;\n/;
            }

            when ('wind') {
                $result .= "Wind: $c->{'windspeedKmph'}kph/$c->{'windspeedMiles'}mph $c->{'winddirDegree'}°/$c->{'winddir16Point'}, ";
                $result .= "gust: $h->{'WindGustKmph'}kph/$h->{'WindGustMiles'}mph, chill: $h->{'WindChillC'}C/$h->{'WindChillF'}F;\n";
            }

            when ('qlocation') {
                my $l = $wttr->{'request'}->[0];
                $result .= "Query location: $l->{'query'} ($l->{'type'});\n";
            }

            when ('dewpoint') { $result .= "Dew point: $h->{'DewPointC'}C/$h->{'DewPointF'}F;\n"; }

            when ('feelslike') { $result .= "Feels like: $h->{'FeelsLikeC'}C/$h->{'FeelsLikeF'}F;\n"; }

            when ('heatindex') { $result .= "Heat index: $h->{'HeatIndexC'}C/$h->{'HeatIndexF'}F;\n"; }

            when ('moon') {
                my $a = $w->{'astronomy'}->[0];
                $result .= "Moon: phase: $a->{'moon_phase'}, illumination: $a->{'moon_illumination'}%, rise: $a->{'moonrise'}, set: $a->{'moonset'};\n";
            }

            when ('sun') {
                my $a = $w->{'astronomy'}->[0];
                $result .= "Sun: rise: $a->{'sunrise'}, set: $a->{'sunset'};\n";
            }

            when ('sunhours') { $result .= "Hours of sun: $w->{'sunHour'};\n"; }

            when ('snowfall') { $result .= "Total snow: $w->{'totalSnow_cm'}cm;\n"; }

            when ('uvindex') { $result .= "UV Index: $c->{'uvIndex'};\n"; }

            when ('visibility') { $result .= "Visibility: $c->{'visibility'}km;\n"; }

            when ('cloudcover') { $result .= "Cloud cover: $c->{'cloudcover'}%;\n"; }

            when ('time') { $result .= "Observed: $c->{'localObsDateTime'};\n"; }

            when ('location') {
                if (exists $wttr->{nearest_area}) {
                    my $areaName = $wttr->{nearest_area}->[0]->{areaName}->[0]->{value};
                    my $region   = $wttr->{nearest_area}->[0]->{region}->[0]->{value};
                    my $country  = $wttr->{nearest_area}->[0]->{country}->[0]->{value};

                    my $location = '';
                    $location .= "$areaName, " if length $areaName;
                    $location .= "$region, "   if length $region and $region ne $areaName;
                    $location .= "$country, "  if length $country;
                    $location =~ s/, $//;

                    $result .= "Observation location: $location;\n";
                } else {
                    $result .= "Query location: $location;\n";
                }
            }

            when ('population') {
                my $population = $wttr->{nearest_area}->[0]->{population};
                $population =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
                $result .= "Population: $population;\n";
            }

            default { $result .= "Option $_ coming soon;\n" unless lc $_ eq 'u'; }
        }
    }

    $result =~ s/;\s+$//;
    return $result;
}

1;
