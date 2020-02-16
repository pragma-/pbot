# File: Date.pm
# Author: pragma-
#
# Purpose: Adds command to display time and date for timezones.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Date;
use parent 'Plugins::Plugin';

use warnings; use strict;
use feature 'unicode_strings';

use Getopt::Long qw(GetOptionsFromArray);

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{registry}->add_default('text', 'date', 'default_timezone', 'UTC');
    $self->{pbot}->{commands}->register(sub { $self->datecmd(@_) }, "date", 0);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("date");
}

sub datecmd {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;
    my $usage = "date [-u <user account>] [timezone]";
    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

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

    my $hostmask    = defined $user_override ? $user_override : "$nick!$user\@$host";
    my $tz_override = $self->{pbot}->{users}->get_user_metadata($from, $hostmask, 'timezone') // '';

    my $timezone = $self->{pbot}->{registry}->get_value('date', 'default_timezone') // 'UTC';
    $timezone = $tz_override if $tz_override;
    $timezone = $arguments   if length $arguments;

    if (defined $user_override and not length $tz_override) { return "No timezone set or user account does not exist."; }

    my $newstuff = {
        from    => $from,                   nick         => $nick, user         => $user, host => $host,
        command => "date_module $timezone", root_channel => $from, root_keyword => "date_module",
        keyword => "date_module", arguments => "$timezone"
    };

    $self->{pbot}->{modules}->execute_module($newstuff);
}

1;
