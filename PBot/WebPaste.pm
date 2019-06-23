# File: WebPaste.pm
# Author: pragma_
#
# Purpose: Pastes text to web paste sites.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::WebPaste;

use warnings;
use strict;

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use LWP::UserAgent;
use Carp ();

sub new {
  if (ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{paste_sites} = [
    sub { $self->paste_ixio(@_) },
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
  my ($self, $text) = @_;

  $text =~ s/(.{120})\s/$1\n/g;
  my $result;

  for (my $tries = 5; $tries > 0; $tries--) {
    my $paste_site = $self->get_paste_site;
    $result = $paste_site->($text);

    if ($result !~ m/error pasting/) {
      last;
    }
  }

  return $result;
}

sub paste_ixio {
  my $self = shift;
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

  my $result = $response->content;
  $result =~ s/^\s+//;
  $result =~ s/\s+$//;
  return $result;
}

1;
