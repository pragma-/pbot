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
    $self->{pbot}->{commands}->register(sub { $self->cmd_date(@_) }, "date", 0);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("date");
}

sub cmd_date {
    my ($self, $context) = @_;
    my $usage = "date [-u <user account>] [timezone]";
    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling");

    my ($user_override, $show_usage);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);
    GetOptionsFromArray(
        \@opt_args,
        'u=s' => \$user_override,
        'h'   => \$show_usage
    );

    return $usage                         if $show_usage;
    return "/say $getopt_error -- $usage" if defined $getopt_error;
    $context->{arguments} = "@opt_args";

    my $tz_override;

    if (defined $user_override) {
        my $userdata = $self->{pbot}->{users}->{users}->get_data($user_override);
        return "No such user account $user_override. They may use the `my` command to create a user account and set their `timezone` user metadata." if not defined $userdata;
        return "User account does not have `timezone` set. They may use the `my` command to set their `timezone` user metadata." if not exists $userdata->{timezone};
        $tz_override = $userdata->{timezone};
    } else {
        $tz_override = $self->{pbot}->{users}->get_user_metadata($context->{from}, $context->{hostmask}, 'timezone') // '';
    }

    my $timezone = $self->{pbot}->{registry}->get_value('date', 'default_timezone') // 'UTC';
    $timezone = $tz_override if $tz_override;
    $timezone = $context->{arguments}   if length $context->{arguments};

    if (defined $user_override and not length $tz_override) { return "No timezone set or user account does not exist."; }

    my $newcontext = {
        from         => $context->{from},
        nick         => $context->{nick},
        user         => $context->{user},
        host         => $context->{host},
        command      => "date_module $timezone",
        root_channel => $context->{from},
        root_keyword => "date_module",
        keyword      => "date_module",
        arguments    => "$timezone"
    };

    $self->{pbot}->{modules}->execute_module($newcontext);
}

1;
