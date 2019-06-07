#!/usr/bin/env perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;

package PBot::Utils::ParseDate;

use DateTime;
use DateTime::Format::Flexible;
use DateTime::Format::Duration;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
}

# expands stuff like "7d3h" to "7 days and 3 hours"
sub unconcise {
  my ($input) = @_;
  my %word = (y => 'years', w => 'weeks', d => 'days', h => 'hours', m => 'minutes', s => 'seconds');
  $input =~ s/(\d+)([ywdhms])/"$1 " . $word{lc $2} . ' and '/ige;
  $input =~ s/ and $//;
  return $input;
}

# parses English natural language date strings into seconds
# does not accept times or dates in the past
sub parsedate {
  my ($self, $input) = @_;

  # expand stuff like 7d3h
  $input = unconcise($input);

  # some aliases
  $input =~ s/\bsecs?\b/seconds/g;
  $input =~ s/\bmins?\b/minutes/g;
  $input =~ s/\bhrs?\b/hours/g;
  $input =~ s/\bwks?\b/weeks/g;
  $input =~ s/\byrs?\b/years/g;

  # sanitizers
  $input =~ s/\b(\d+)\s+(am?|pm?)\b/$1$2/;        # remove leading spaces from am/pm
  $input =~ s/ (\d+)(am?|pm?)\b/ $1:00:00$2/;     # convert 3pm to 3:00:00pm
  $input =~ s/ (\d+:\d+)(am?|pm?)\b/ $1:00:00$2/; # convert 3:00pm to 3:00:00pm

  # split input on "and" or comma, then we'll add up the results
  # this allows us to parse things like "1 hour and 30 minutes"
  my @inputs = split /(?:,?\s+and\s+|\s*,\s*)/, $input;

  # adjust timezone to user-override if user provides a timezone
  # we won't know if a timezone was provided until it is parsed
  my $timezone;
  my $tz_override = 'UTC';

  ADJUST_TIMEZONE:
  $timezone = $tz_override;
  my $now = DateTime->now(time_zone => $timezone);

  my $seconds = 0;
  my $from_now_added = 0;

  foreach my $input (@inputs) {
    return -1 if $input =~ m/forever/i;
    $input .= ' seconds' if $input =~ m/^\s*\d+\s*$/;

    # DateTime::Format::Flexible doesn't support seconds, but that's okay;
    # we can take care of that easily here!
    if ($input =~ m/^\s*(\d+)\s+seconds$/) {
      $seconds += $1;
      next;
    }

    # First, attempt to parse as-is...
    my $to = eval { return DateTime::Format::Flexible->parse_datetime($input, lang => ['en'], base => $now); };

    # If there was an error, then append "from now" and attempt to parse as a relative time...
    if ($@) {
      $from_now_added = 1;
      $input .= ' from now';
      $to = eval { return DateTime::Format::Flexible->parse_datetime($input, lang => ['en'], base => $now); };

      # If there's still an error, it's bad input
      if ($@) {
        $@ =~ s/ from now at PBot.*$//;
        return (0, $@);
      }
    }

    # there was a timezone parsed, set the override and try again
    if ($to->time_zone_short_name ne 'floating' and $to->time_zone_short_name ne 'UTC' and $tz_override eq 'UTC') {
      $tz_override = $to->time_zone_long_name;
      goto ADJUST_TIMEZONE;
    }

    $to->set_time_zone('UTC');
    my $duration = $to->subtract_datetime_absolute($now);

    # If the time is in the past, prepend "tomorrow" and reparse
    if ($duration->is_negative) {
      $input = "tomorrow $input";
      $to = eval { return DateTime::Format::Flexible->parse_datetime($input, lang => ['en'], base => $now); };

      if ($@) {
        $@ =~ s/format: tomorrow /format: /;
        if ($from_now_added) {
          $@ =~ s/ from now at PBot.*//;
        } else {
          $@ =~ s/ at PBot.*//;
        }
        return (0, $@);
      }

      $to->set_time_zone('UTC');
      $duration = $to->subtract_datetime_absolute($now);
    }

    # add the seconds from this input chunk
    $seconds += $duration->seconds;
  }

  return $seconds;
}

1;
