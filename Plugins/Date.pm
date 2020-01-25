# File: Date.pm
# Author: pragma-
#
# Purpose: Adds command to display time and date for timezones.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Date;

use warnings;
use strict;

use feature 'unicode_strings';

use Carp ();

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{registry}->add_default('text', 'date', 'default_timezone', 'UTC');
  $self->{pbot}->{commands}->register(sub { $self->datecmd(@_) },  "date", 0);
}

sub unload {
  my $self = shift;
  $self->{pbot}->{commands}->unregister("date");
}

sub datecmd {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my $timezone = $self->{pbot}->{registry}->get_value('date', 'default_timezone') // 'UTC';
  my $tz_override = $self->{pbot}->{users}->get_loggedin_user_metadata($from, "$nick!$user\@$host", 'timezone');
  $timezone = $tz_override if $tz_override;
  $timezone = $arguments if length $arguments;

  my $newstuff = {
    from => $from, nick => $nick, user => $user, host => $host,
    command => "date_module $timezone", root_channel => $from, root_keyword => "date_module",
    keyword => "date_module", arguments => "$timezone"
  };

  $self->{pbot}->{factoids}->{factoidmodulelauncher}->execute_module($newstuff);
}

1;
