# File: VERSION.pm
# Author: pragma_
#
# Purpose: Keeps track of bot version. Can compare current version against
# latest version on github or version.check_url site.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::VERSION;
use parent 'PBot::Class';

use strict; use warnings;
use feature 'unicode_strings';

use LWP::UserAgent;

# These are set automatically by the misc/update_version script
use constant {
    BUILD_NAME     => "PBot",
    BUILD_REVISION => 3832,
    BUILD_DATE     => "2020-07-20",
};

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->cmd_version(@_) }, "version", 0);
    $self->{last_check} = {timestamp => 0, version => BUILD_REVISION, date => BUILD_DATE};
}

sub cmd_version {
    my ($self, $context) = @_;

    my $ratelimit = $self->{pbot}->{registry}->get_value('version', 'check_limit') // 300;

    if (time - $self->{last_check}->{timestamp} >= $ratelimit) {
        $self->{last_check}->{timestamp} = time;

        my $url = $self->{pbot}->{registry}->get_value('version', 'check_url') // 'https://raw.githubusercontent.com/pragma-/pbot/master/PBot/VERSION.pm';
        $self->{pbot}->{logger}->log("Checking $url for new version...\n");
        my $ua       = LWP::UserAgent->new(timeout => 10);
        my $response = $ua->get($url);

        return "Unable to get version information: " . $response->status_line if not $response->is_success;

        my $text = $response->decoded_content;
        my ($version, $date) = $text =~ m/^\s+BUILD_REVISION => (\d+).*^\s+BUILD_DATE\s+=> "([^"]+)"/ms;

        if (not defined $version or not defined $date) { return "Unable to get version information: data did not match expected format"; }

        $self->{last_check} = {timestamp => time, version => $version, date => $date};
    }

    my $target_nick;
    $target_nick = $self->{pbot}->{nicklist}->is_present_similar($context->{from}, $context->{arguments}) if length $context->{arguments};

    my $result = '/say ';
    $result .= "$target_nick: " if $target_nick;
    $result .= $self->version;

    if ($self->{last_check}->{version} > BUILD_REVISION) { $result .= "; new version available: $self->{last_check}->{version} $self->{last_check}->{date}!"; }
    return $result;
}

sub version { return BUILD_NAME . " version " . BUILD_REVISION . " " . BUILD_DATE; }

1;
