# File: VERSION.pm
# Author: pragma_
#
# Purpose: Keeps track of bot version.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::VERSION;

use strict;
use warnings;

use feature 'unicode_strings';

BEGIN {
  use Exporter;
  our @ISA = 'Exporter';
  our @EXPORT_OK = qw(version);
}

use LWP::UserAgent;

# These are set automatically by the build/commit script
use constant {
  BUILD_NAME     => "PBot",
  BUILD_REVISION => 2836,
  BUILD_DATE     => "2020-01-19",
};

sub new {
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->{pbot}  = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{pbot}->{commands}->register(sub { $self->version_cmd(@_) },  "version",  0);

  return $self;
}

sub version {
  return BUILD_NAME . " version " . BUILD_REVISION . " " . BUILD_DATE;
}

sub version_cmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  if (length $arguments) {
    if ($arguments eq '-check') {
      my $url = $self->{pbot}->{registry}->get_value('version', 'check_url') // 'https://raw.githubusercontent.com/pragma-/pbot/master/PBot/VERSION.pm';
      my $ua = LWP::UserAgent->new(timeout => 10);
      my $response = $ua->get($url);
      return "Unable to get version information: " . $response->status_line if (not $response->is_success);
      my $text = $response->decoded_content;
      my ($version, $date) = $text =~ m/^\s+BUILD_REVISION => (\d+).*^\s+BUILD_DATE\s+=> "([^"]+)"/ms;

      if ($version > BUILD_REVISION) {
        return "/say " . $self->version . "; new version available: $version $date!";
      } else {
        return "/say " . $self->version . "; you have the latest version.";
      }
    } else {
      my $nick = $self->{pbot}->{nicklist}->is_present_similar($from, $arguments);
      if ($nick) {
        return "/say $nick: " . $self->version;
      }
    }
  }
  return "/say " . $self->version;
}

1;
