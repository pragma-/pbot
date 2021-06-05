# File: WebPaste.pm
# Author: pragma_
#
# Purpose: Pastes text to a cycling list of web paste sites.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::WebPaste;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use LWP::UserAgent::Paranoid;
use Encode;

sub initialize {
    my ($self, %conf) = @_;

    # There used to be many more paste sites in this list but one by one
    # many have died off. :-(

    $self->{paste_sites} = [
        sub { $self->paste_0x0st(@_) },
        # sub { $self->paste_ixio(@_) }, # removed due to being too slow (temporarily hopefully)
    ];

    $self->{current_site} = 0;
}

sub get_paste_site {
    my ($self) = @_;

    my $subref = $self->{paste_sites}->[$self->{current_site}];

    if (++$self->{current_site} >= @{$self->{paste_sites}}) {
        $self->{current_site} = 0;
    }

    return $subref;
}

sub paste {
    my ($self, $text, %opts) = @_;

    my %default_opts = (
        no_split => 0,
    );

    %opts = (%default_opts, %opts);

    $text =~ s/(.{120})\s/$1\n/g unless $opts{no_split};

    my $response;

    for (my $tries = 3; $tries > 0; $tries--) {
        my $paste_site = $self->get_paste_site;

        $response = $paste_site->($text);

        last if $response->is_success;
    }

    if (not $response->is_success) {
        return "error pasting: " . $response->status_line;
    }

    my $result = $response->decoded_content;

    $result =~ s/^\s+|\s+$//g;

    alarm 1; # LWP::UserAgent::Paranoid kills alarm

    return $result;
}

sub paste_0x0st {
    my ($self, $text) = @_;

    my $ua = LWP::UserAgent::Paranoid->new(request_timeout => 10);

    push @{$ua->requests_redirectable}, 'POST';

    return $ua->post(
        "https://0x0.st",
        [ file => [ undef, "file", Content => $text ] ],
        Content_Type => 'form-data'
    );
}

sub paste_ixio {
    my ($self, $text) = @_;

    my $ua = LWP::UserAgent::Paranoid->new(request_timeout => 10);

    push @{$ua->requests_redirectable}, 'POST';

    my %post = ('f:1' => $text);

    return $ua->post("http://ix.io", \%post);
}

1;
