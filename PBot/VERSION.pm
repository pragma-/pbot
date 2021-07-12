# File: VERSION.pm
#
# Purpose: Keeps track of bot version. Can compare current version against
# latest version on github or URL in `version.check_url` registry entry.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::VERSION;
use parent 'PBot::Class';

use PBot::Imports;

use LWP::UserAgent;

# These are set automatically by the misc/update_version script
use constant {
    BUILD_NAME     => "PBot",
    BUILD_REVISION => 4176,
    BUILD_DATE     => "2021-07-11",
};

sub initialize {
    my ($self, %conf) = @_;

    # register `version` command
    $self->{pbot}->{commands}->register(sub { $self->cmd_version(@_) }, "version", 0);

    # initialize last_check version data
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

        if (not $response->is_success) {
            return "Unable to get version information: " . $response->status_line;
        }

        my $text = $response->decoded_content;
        my ($version, $date) = $text =~ m/^\s+BUILD_REVISION => (\d+).*^\s+BUILD_DATE\s+=> "([^"]+)"/ms;

        if (not defined $version or not defined $date) {
            return "Unable to get version information: data did not match expected format";
        }

        $self->{last_check} = {timestamp => time, version => $version, date => $date};
    }

    my $target_nick;
    if (length $context->{arguments}) {
        $target_nick = $self->{pbot}->{nicklist}->is_present_similar($context->{from}, $context->{arguments});
    }

    my $result = '/say ';
    $result .= "$target_nick: " if $target_nick;
    $result .= $self->version;

    if ($self->{last_check}->{version} > BUILD_REVISION) {
        $result .= "; new version available: $self->{last_check}->{version} $self->{last_check}->{date}!";
    }

    return $result;
}

sub version {
    return BUILD_NAME . " version " . BUILD_REVISION . " " . BUILD_DATE;
}

1;
