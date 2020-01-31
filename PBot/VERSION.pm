# File: VERSION.pm
# Author: pragma_
#
# Purpose: Keeps track of bot version. Can compare current version against
# latest version on github or version.check_url site.

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

# These are set automatically by build/update_version.pl
use constant {
  BUILD_NAME     => "PBot",
  BUILD_REVISION => 3044,
  BUILD_DATE     => "2020-01-31",
};

sub new {
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->{pbot}  = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{commands}->register(sub { $self->version_cmd(@_) },  "version",  0);
  $self->{last_check} = { timestamp => 0, version => BUILD_REVISION, date => BUILD_DATE };
  return $self;
}

sub version {
  return BUILD_NAME . " version " . BUILD_REVISION . " " . BUILD_DATE;
}

sub version_cmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my $ratelimit = $self->{pbot}->{registry}->get_value('version', 'check_limit') // 300;

  if (time - $self->{last_check}->{timestamp} >= $ratelimit) {
    $self->{last_check}->{timestamp} = time;

    my $url = $self->{pbot}->{registry}->get_value('version', 'check_url') // 'https://raw.githubusercontent.com/pragma-/pbot/master/PBot/VERSION.pm';
    $self->{pbot}->{logger}->log("Checking $url for new version...\n");
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $response = $ua->get($url);

    return "Unable to get version information: " . $response->status_line if not $response->is_success;

    my $text = $response->decoded_content;
    my ($version, $date) = $text =~ m/^\s+BUILD_REVISION => (\d+).*^\s+BUILD_DATE\s+=> "([^"]+)"/ms;

    if (not defined $version or not defined $date) {
      return "Unable to get version information: data did not match expected format";
    }

    $self->{last_check} = { timestamp => time, version => $version, date => $date };
  }

  my $target_nick;
  $target_nick = $self->{pbot}->{nicklist}->is_present_similar($from, $arguments) if length $arguments;

  my $result = '/say ';
  $result .= "$target_nick: " if $target_nick;
  $result .= $self->version;

  if ($self->{last_check}->{version} > BUILD_REVISION) {
    $result .= "; new version available: $self->{last_check}->{version} $self->{last_check}->{date}!";
  }

  return $result;
}

1;
