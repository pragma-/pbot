# File: Wolfram.pm
#
# Purpose: Query Wolfram|Alpha's Short Answers API.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Wolfram;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use LWP::UserAgent::Paranoid;
use URI::Escape qw/uri_escape_utf8/;

sub initialize {
    my ($self, %conf) = @_;

    # add default registry entry for `wolfram.appid`
    $self->{pbot}->{registry}->add_default('text', 'wolfram', 'appid', '');

    # make `wolfram.appid` registry entry private by default
    $self->{pbot}->{registry}->set_default('wolfram', 'appid', 'private', 1);

    $self->{pbot}->{commands}->register(sub { $self->cmd_wolfram(@_) }, 'wolfram', 0);
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{commands}->unregister('wolfram');
}

sub cmd_wolfram {
    my ($self, $context) = @_;

    return "Usage: wolfram <query>\n" if not length $context->{arguments};

    my $appid = $self->{pbot}->{registry}->get_value('wolfram', 'appid');

    if (not length $appid) {
        return "$context->{nick}: Registry item wolfram.appid is not set. See https://developer.wolframalpha.com/portal/myapps to get an appid.";
    }

    my $question = uri_escape_utf8 $context->{arguments};
    my $units    = uri_escape_utf8 ($self->{pbot}->{users}->get_user_metadata($context->{from}, $context->{hostmask}, 'units') // 'metric');

    my $ua = LWP::UserAgent::Paranoid->new(agent => 'Mozilla/5.0', request_timeout => 10);

    my $response = $ua->get("https://api.wolframalpha.com/v1/result?appid=$appid&i=$question&units=$units&timeout=10");

    if ($response->is_success) {
        return "$context->{nick}: " . $response->decoded_content;
    }
    elsif ($response->code == 501) {
        return "$context->{nick}: I don't know what that means.";
    }
    else {
        return "$context->{nick}: Failed to query Wolfram|Alpha: " . $response->status_line;
    }
}

1;
