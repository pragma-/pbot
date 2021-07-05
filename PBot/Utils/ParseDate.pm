# File: ParseDate.pm
#
# Purpose: Intelligently parses strings like "1h30m", "5 minutes", "next week",
# "3:30 am pdt", "11 pm utc", etc, into seconds.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Utils::ParseDate;

use PBot::Imports;

use DateTime;
use DateTime::Format::Flexible;
use DateTime::Format::Duration;

sub new {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
}

# expands stuff like "7d3h" to "7 days and 3 hours"
sub unconcise {
    my ($input) = @_;
    my %word = (y => 'years', w => 'weeks', d => 'days', h => 'hours', m => 'minutes', s => 'seconds');
    $input =~ s/(\d+)([ywdhms])(?![a-z])/"$1 " . $word{lc $2} . ' and '/ige;
    $input =~ s/ and $//;
    return $input;
}

# parses English natural language date strings into seconds
# does not accept times or dates in the past
sub parsedate {
    my ($self, $input) = @_;

    my $examples = "Try `30s`, `1h30m`, `tomorrow`, `next monday`, `9:30am pdt`, `11pm utc`, etc.";

    my $attempts = 0;
    my $original_input = $input;

    my $override = "";
  TRY_AGAIN:
    $input = "$override$input" if length $override;

    return (0, "Could not parse `$original_input`. $examples") if ++$attempts > 10;

    # expand stuff like 7d3h
    $input = unconcise($input);

    # some aliases
    $input =~ s/\bsecs?\b/seconds/g;
    $input =~ s/\bmins?\b/minutes/g;
    $input =~ s/\bhrs?\b/hours/g;
    $input =~ s/\bwks?\b/weeks/g;
    $input =~ s/\byrs?\b/years/g;
    $input =~ s/\butc\b/gmt/g;

    # sanitizers
    $input =~ s/\b(\d+)\s+(am?|pm?)\b/$1$2/;        # remove leading spaces from am/pm
    $input =~ s/ (\d+)(am?|pm?)\b/ $1:00:00$2/;     # convert 3pm to 3:00:00pm
    $input =~ s/ (\d+:\d+)(am?|pm?)\b/ $1:00$2/;    # convert 4:20pm to 4:20:00pm
    $input =~
      s/next (jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept(?:ember)?|oct(?:ober)?|nov(?:ember)|dec(?:ember)?) (\d+)(?:st|nd|rd|th)?(.*)/"next $1 and " . ($2 - 1) . " days" . (length $3 ? " and $3" : "")/ie;

    # split input on "and" or comma, then we'll add up the results
    # this allows us to parse things like "1 hour and 30 minutes"
    my @inputs = split /(?:,?\s+and\s+|\s*,\s*|\s+at\s+)/, $input;

    # adjust timezone to user-override if user provides a timezone
    # we won't know if a timezone was provided until it is parsed
    my $timezone;
    my $tz_override = 'UTC';

  ADJUST_TIMEZONE:
    $timezone = $tz_override;
    my $now = DateTime->now(time_zone => $timezone);

    my $seconds = 0;
    my ($to, $base);

    foreach my $input (@inputs) {
        return -1 if $input =~ m/forever/i;
        $input .= ' seconds' if $input =~ m/^\s*\d+\s*$/;

        # DateTime::Format::Flexible doesn't support seconds, but that's okay;
        # we can take care of that easily here!
        if ($input =~ m/^\s*(\d+)\s+seconds$/) {
            $seconds += $1;
            next;
        }

        # adjust base
        if (defined $to) {
            $base = $to->clone;
            $base->set_time_zone($timezone);
        } else {
            $base = $now;
        }

        # First, attempt to parse as-is...
        $to = eval { return DateTime::Format::Flexible->parse_datetime($input, lang => ['en'], base => $base); };

        # If there was an error, then append "from now" and attempt to parse as a relative time...
        if ($@) {
            $input .= ' from now';
            $to = eval { return DateTime::Format::Flexible->parse_datetime($input, lang => ['en'], base => $base); };

            # If there's still an error, it's bad input
            if (my $error = $@) {
                $error =~ s/ ${override}from now at .*$//;
                $error =~ s/\s*$/. $examples/;
                return (0, $error);
            }
        }

        # there was a timezone parsed, set the tz override and try again
        if ($to->time_zone_short_name ne 'floating' and $to->time_zone_short_name ne 'UTC' and $tz_override eq 'UTC') {
            $tz_override = $to->time_zone_long_name;
            $to = undef;
            goto ADJUST_TIMEZONE;
        }

        $to->set_time_zone('UTC');
        $base->set_time_zone('UTC');
        my $duration = $to->subtract_datetime_absolute($base);

        # If the time is in the past, prepend "tomorrow" or "next" and reparse
        if ($duration->is_negative) {
            if ($input =~ m/^\d/) {
                $override = "tomorrow ";
            } else {
                $override = "next ";
            }
            $to = undef;
            goto TRY_AGAIN;
        }

        # add the seconds from this input chunk
        $seconds += $duration->seconds;
    }

    return $seconds;
}

1;
