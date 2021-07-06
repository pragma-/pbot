# File: Wolfram.pm
#
# Purpose: Query Wolfram|Alpha's Short Answers API.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Wolfram;
use parent 'Plugins::Plugin';

use PBot::Imports;

use LWP::UserAgent::Paranoid;
use URI::Escape qw/uri_escape_utf8/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{registry}->add_default('text', 'wolfram', 'api_key', '');

    $self->{pbot}->{registry}->set_default('wolfram', 'api_key', 'private', 1);

    $self->{pbot}->{commands}->register(sub { $self->cmd_wolfram(@_) }, 'wolfram', 0);
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{commands}->unregister('wolfram');
}

sub cmd_wolfram {
    my ($self, $context) = @_;

    return "Usage: wolfram <query>\n" if not length $context->{arguments};

    my $api_key = $self->{pbot}->{registry}->get_value('wolfram', 'api_key');

    if (not length $api_key) {
        return "$context->{nick}: Registry item wolfram.api_key is not set. See https://developer.wolframalpha.com/portal/myapps to get an API key.";
    }

    my $ua = LWP::UserAgent::Paranoid->new(agent => 'Mozilla/5.0', request_timeout => 10);

    my $question = uri_escape_utf8 $context->{arguments};
    my $units = uri_escape_utf8($self->{pbot}->{users}->get_user_metadata($context->{from}, $context->{hostmask}, 'units') // 'metric');
    my $response = $ua->get("https://api.wolframalpha.com/v1/result?appid=$api_key&i=$question&units=$units&timeout=10");

    if ($response->is_success) {
        return "$context->{nick}: " . $response->decoded_content;
    }
    elsif ($response->code eq 501) {
        return "I don't know what that means.";
    }
    else {
        return "Failed to query Wolfram|Alpha: " . $response->status_line;
    }
}

1;
