# File: EventQueue.pm
#
# Purpose: Registers command for manipulating PBot event queue.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::EventQueue;

use PBot::Imports;
use parent 'PBot::Core::Class';

use Time::Duration;

sub initialize {
    my ($self, %conf) = @_;

    # register `eventqueue` bot command
    $self->{pbot}->{commands}->register(sub { $self->cmd_eventqueue(@_) }, 'eventqueue', 1);

    # add `can-eventqueue` capability to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-eventqueue', 1);
}

sub cmd_eventqueue {
    my ($self, $context) = @_;

    my $usage = "Usage: eventqueue list [filter regex] | add <relative time> <command> [-repeat] | remove <regex>";

    my $command = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

    if (not defined $command) {
        return $usage;
    }

    if ($command eq 'list') {
        return "No events queued." if not $self->{pbot}->{event_queue}->count;

        my $result = eval {
            my $text = "Queued events:\n";

            my ($regex) = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});

            my $i = 0;
            my $events = 0;
            foreach my $event ($self->{pbot}->{event_queue}->entries) {
                $i++;

                if ($regex) {
                    next unless $event->{id} =~ /$regex/i;
                }

                $events++;

                my $duration = $event->{priority} - time;

                if ($duration < 0) {
                    # current time has passed an event's time but the
                    # event hasn't left the queue yet. we'll show these
                    # as, e.g., "pending 5s ago"
                    $duration = 'pending ' . concise ago -$duration;
                } else {
                    $duration = 'in ' . concise duration $duration;
                }

                $text .= "  $i) $duration: $event->{id}";
                $text .= ' [R]' if $event->{repeating};
                $text .= ";\n";
            }

            return "No events found." if $events == 0;

            return $text . "$events events.\n";
        };

        if (my $error = $@) {
            # strip source information to prettify error for non-developer consumption
            $error =~ s/ at PBot.*//;
            return "Bad regex: $error";
        }

        return $result;
    }

    if ($command eq 'add') {
        my ($duration, $command) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

        if (not defined $duration or not defined $command) {
            return "Usage: eventqueue add <relative time> <command> [-repeat]";
        }

        # convert text like "5 minutes" or "1 week" or "next tuesday" to seconds
        my ($seconds, $error) = $self->{pbot}->{parsedate}->parsedate($duration);
        return $error if defined $error;

        # check for `-repeating` at front or end of command
        my $repeating = $command =~ s/^-repeat\s+|\s+-repeat$//g;

        my $cmd = {
            nick     => $context->{nick},
            user     => $context->{user},
            host     => $context->{host},
            hostmask => $context->{hostmask},
            command  => $command,
        };

        $self->{pbot}->{interpreter}->add_to_command_queue($context->{from}, $cmd, $seconds, $repeating);

        return "Command added to event queue.";
    }

    if ($command eq 'remove') {
        my ($regex) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 1);
        return "Usage: eventqueue remove <regex>" if not defined $regex;
        $regex =~ s/(?<!\.)\*/.*?/g;
        return $self->{pbot}->{event_queue}->dequeue_event($regex);
    }

    return "Unknown command '$command'. $usage";
}

1;
