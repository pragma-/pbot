# File: GetUrl.pm
#
# Purpose: Retrieves text contents of a URL.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::GetUrl;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use LWP::UserAgent::Paranoid;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{registry}->add_default('text', 'geturl', 'enabled', 1);
    $self->{pbot}->{registry}->add_default('text', 'geturl', 'max_size', 1024 * 1024);

    $self->{pbot}->{commands}->register(sub { $self->cmd_geturl(@_) }, 'geturl', 0);
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{commands}->unregister('geturl');
}

sub cmd_geturl {
    my ($self, $context) = @_;

    return "Usage: geturl <url>\n" if not length $context->{arguments};

    my $enabled = $self->{pbot}->{registry}->get_value('geturl', 'enabled');

    if (not $enabled) {
        return "geturl is disabled. To enable, regset geturl.enabled 1";
    }

    # check channel-specific geturl_enabled registry setting
    $enabled = $self->{pbot}->{registry}->get_value($context->{from}, 'geturl_enabled') // 1;

    if (not $enabled) {
        return "geturl is disabled for $context->{from}. To enable, regset $context->{from}.geturl_enabled 1";
    }

    my $ua = LWP::UserAgent::Paranoid->new(agent => 'Mozilla/5.0', request_timeout => 10);

    my $max_size = $self->{pbot}->{registry}->get_value('geturl', 'max_size') // 1024 * 1024;
    $ua->max_size($max_size);

    my $response = $ua->get($context->{arguments});

    if ($response->is_success) {
        return $response->decoded_content;
    }
    else {
        return "[Failed to fetch page: " . $response->status_line . "]";
    }
}

1;
