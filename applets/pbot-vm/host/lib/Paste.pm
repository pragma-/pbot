#!/usr/bin/env perl

package Paste;

use 5.020;

use warnings;
use strict;

use LWP::UserAgent;

use parent qw(Exporter);
our @EXPORT = qw(paste_ixio paste_0x0);

sub paste_ixio {
    my $text = join(' ', @_);

    $text =~ s/(.{120})\s/$1\n/g;

    my $ua = LWP::UserAgent->new();
    $ua->agent("Mozilla/5.0");
    push @{ $ua->requests_redirectable }, 'POST';
    $ua->timeout(10);

    my %post = ('f:1' => $text);
    my $response = $ua->post("http://ix.io", \%post);

    if (not $response->is_success) {
        return "error pasting: " . $response->status_line;
    }

    my $result = $response->decoded_content;
    $result =~ s/^\s+//;
    $result =~ s/\s+$//;
    return $result;
}

sub paste_0x0 {
    my $text = join ' ', @_;

    $text =~ s/(.{120})\s/$1\n/g;

    my $ua = LWP::UserAgent->new();
    $ua->agent("Mozilla/5.0");
    push @{ $ua->requests_redirectable }, 'POST';
    $ua->timeout(10);

    my $response =  $ua->post(
        "https://0x0.st",
        [ file => [ undef, "filename", Content => $text, 'Content-Type' => 'text/plain' ] ],
        Content_Type => 'form-data'
    );

    if (not $response->is_success) {
        return "error pasting: " . $response->status_line;
    }

    my $result = $response->decoded_content;
    $result =~ s/^\s+//;
    $result =~ s/\s+$//;
    return $result;
}

1;
