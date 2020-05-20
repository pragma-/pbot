# File: Weather.pm
# Author: pragma-
#
# Purpose: Weather command.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Weather;

use parent 'Plugins::Plugin';

use warnings; use strict;
use feature 'unicode_strings';

use PBot::Utils::LWPUserAgentCached;
use XML::LibXML;
use Getopt::Long qw(GetOptionsFromArray);

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->cmd_weather(@_) }, "weather", 0);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("weather");
}

sub cmd_weather {
    my ($self, $context) = @_;
    my $usage = "Usage: weather (<location> | -u <user account>)";
    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    my $arguments = $context->{arguments};

    Getopt::Long::Configure("bundling");

    my ($user_override, $show_usage);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($arguments, strip_quotes => 1);
    GetOptionsFromArray(
        \@opt_args,
        'u=s' => \$user_override,
        'h'   => \$show_usage
    );

    return $usage                         if $show_usage;
    return "/say $getopt_error -- $usage" if defined $getopt_error;
    $arguments = "@opt_args";

    my $hostmask          = defined $user_override ? $user_override : $context->{hostmask};
    my $location_override = $self->{pbot}->{users}->get_user_metadata($context->{from}, $hostmask, 'location') // '';
    $arguments = $location_override if not length $arguments;

    if (defined $user_override and not length $location_override) { return "No location set or user account does not exist."; }

    if (not length $arguments) { return $usage; }
    return $self->get_weather($arguments);
}

sub get_weather {
    my ($self, $location) = @_;

    my %cache_opt = (
        'namespace'          => 'accuweather',
        'default_expires_in' => 3600
    );

    my $ua       = PBot::Utils::LWPUserAgentCached->new(\%cache_opt, timeout => 10);
    my $response = $ua->get("http://rss.accuweather.com/rss/liveweather_rss.asp?metric=0&locCode=$location");

    my $xml;

    if ($response->is_success) { $xml = $response->decoded_content; }
    else                       { return "Failed to fetch weather data: " . $response->status_line; }

    my $dom = XML::LibXML->load_xml(string => $xml);

    my $result = '';

    foreach my $channel ($dom->findnodes('//channel')) {
        my $title       = $channel->findvalue('./title');
        my $description = $channel->findvalue('./description');

        if ($description eq 'Invalid Location') {
            return
              "Location $location not found. Use \"<city>, <country abbrev>\" (e.g. \"paris, fr\") or a US Zip Code or \"<city>, <state abbrev>, US\" (e.g., \"austin, tx, us\").";
        }

        $title =~ s/ - AccuW.*$//;
        $result .= "Weather for $title: ";
    }

    foreach my $item ($dom->findnodes('//item')) {
        my $title       = $item->findvalue('./title');
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
    $text =~ s|(-?\d+)\s*F|my $f = $1; my $c = ($f - 32 ) * 5 / 9; $c = sprintf("%.1d", $c); "${c}C/${f}F"|eg;
    return $text;
}

1;
