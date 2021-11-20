# File: Date.pm
#
# Purpose: Adds command to display time and date for timezones.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Date;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;

    # add default registry entry for default timezone
    # this can be overridden via arguments or user metadata
    $self->{pbot}->{registry}->add_default('text', 'date', 'default_timezone', 'UTC');

    # register `date` bot command
    $self->{pbot}->{commands}->add(
        name   => 'date',
        help   => 'Show date and time',
        subref => sub { $self->cmd_date(@_) },
    );
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->remove('date');
}

sub cmd_date {
    my ($self, $context) = @_;

    my $usage = "Usage: date [-u <user account>] [timezone]";

    my %opts;

    my ($opt_args, $opt_error) = $self->{pbot}->{interpreter}->getopt(
        $context->{arguments},
        \%opts,
        ['bundling'],
        'u=s',
        'h',
    );

    return $usage                      if $opts{h};
    return "/say $opt_error -- $usage" if $opt_error;

    $context->{arguments} = "@$opt_args";

    my $user_override = $opts{u};
    my $tz_override;

    # check for user timezone metadata
    if (defined $user_override) {
        my $userdata = $self->{pbot}->{users}->{storage}->get_data($user_override);

        if (not defined $userdata) {
            return "No such user account $user_override. They may use the `my` command to create a user account and set their `timezone` user metadata."
        }

        if (not exists $userdata->{timezone}) {
            return "User account does not have `timezone` set. They may use the `my` command to set their `timezone` user metadata."
        }

        $tz_override = $userdata->{timezone};
    } else {
        $tz_override = $self->{pbot}->{users}->get_user_metadata($context->{from}, $context->{hostmask}, 'timezone') // '';
    }

    # set default timezone
    my $timezone = $self->{pbot}->{registry}->get_value('date', 'default_timezone') // 'UTC';

    # override timezone with user metadata
    $timezone = $tz_override if $tz_override;

    # override timezone with bot command arguments
    $timezone = $context->{arguments} if length $context->{arguments};

    if (defined $user_override and not length $tz_override) {
        return "No timezone set or user account does not exist.";
    }

    # execute `date_applet`
    my $newcontext = {
        from         => $context->{from},
        nick         => $context->{nick},
        user         => $context->{user},
        host         => $context->{host},
        hostmask     => $context->{hostmask},
        command      => "date_applet $timezone",
        root_channel => $context->{from},
        root_keyword => "date_applet",
        keyword      => "date_applet",
        arguments    => "$timezone"
    };

    $self->{pbot}->{applets}->execute_applet($newcontext);
}

1;
