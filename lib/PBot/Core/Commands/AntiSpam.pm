# File: AntiSpam.pm
#
# Purpose: Command to manipulate anti-spam list.

# SPDX-FileCopyrightText: 2018-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::AntiSpam;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw/gettimeofday/;
use POSIX       qw/strftime/;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->register(sub { $self->cmd_antispam(@_) }, "antispam", 1);

    # add capability to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-antispam', 1);
}

sub cmd_antispam {
    my ($self, $context) = @_;

    my $arglist = $context->{arglist};

    my $command = $self->{pbot}->{interpreter}->shift_arg($arglist);

    if (not defined $command) {
        return "Usage: antispam <command>, where commands are: list/show, add, remove, set, unset";
    }

    my $keywords = $self->{pbot}->{antispam}->{keywords};

    given ($command) {
        when ($_ eq "list" or $_ eq "show") {
            my $text    = "Spam keywords:\n";
            my $entries = 0;

            foreach my $namespace ($keywords->get_keys) {
                $text .= ' ' . $keywords->get_key_name($namespace) . ":\n";

                foreach my $keyword ($keywords->get_keys($namespace)) {
                    $text .= '    ' . $keywords->get_key_name($namespace, $keyword) . ",\n";
                    $entries++;
                }
            }

            $text .= "none" if $entries == 0;
            return $text;
        }

        when ("set") {
            my ($namespace, $keyword, $flag, $value) = $self->{pbot}->{interpreter}->split_args($arglist, 4);

            if (not defined $namespace or not defined $keyword) {
                return "Usage: antispam set <namespace> <regex> [flag [value]]"
            }

            if (not $keywords->exists($namespace)) {
                return "There is no such namespace `$namespace`.";
            }

            if (not $keywords->exists($namespace, $keyword)) {
                return "There is no such regex `$keyword` for namespace `" . $keywords->get_key_name($namespace) . '`.';
            }

            if (not defined $flag) {
                my @flags;

                foreach $flag ($keywords->get_keys($namespace, $keyword)) {
                    if ($flag eq 'created_on') {
                        my $timestamp = strftime "%a %b %e %H:%M:%S %Z %Y", localtime $keywords->get_data($namespace, $keyword, $flag);
                        push @flags, "created_on: $timestamp";
                    } else {
                        $value = $keywords->get_data($namespace, $keyword, $flag);
                        push @flags, "$flag: $value";
                    }

                }

                my $text = "Flags: ";

                if (@flags) {
                    $text .= join ",\n", @flags;
                } else {
                    $text .= 'none';
                }

                return $text;
            }

            if (not defined $value) {
                $value = $keywords->get_data($namespace, $keyword, $flag);

                if (not defined $value) {
                    return "/say $flag is not set.";
                } else {
                    return "/say $flag is set to $value";
                }
            }

            $keywords->set($namespace, $keyword, $flag, $value);
            return "Flag set.";
        }

        when ("unset") {
            my ($namespace, $keyword, $flag) = $self->{pbot}->{interpreter}->split_args($arglist, 3);

            if (not defined $namespace or not defined $keyword or not defined $flag) {
                return "Usage: antispam unset <namespace> <regex> <flag>"
            }

            if (not $keywords->exists($namespace)) {
                return "There is no such namespace `$namespace`.";
            }

            if (not $keywords->exists($namespace, $keyword)) {
                return "There is no such keyword `$keyword` for namespace `$namespace`.";
            }

            if (not $keywords->exists($namespace, $keyword, $flag)) {
                return "There is no such flag `$flag` for regex `$keyword` for namespace `$namespace`.";
            }

            return $keywords->remove($namespace, $keyword, $flag);
        }

        when ("add") {
            my ($namespace, $keyword) = $self->{pbot}->{interpreter}->split_args($arglist, 2);

            if (not defined $namespace or not defined $keyword) {
                return "Usage: antispam add <namespace> <regex>";
            }

            my $data = {
                owner      => $context->{hostmask},
                created_on => scalar gettimeofday
            };

            $keywords->add($namespace, $keyword, $data);
            return "/say Added `$keyword`.";
        }

        when ("remove") {
            my ($namespace, $keyword) = $self->{pbot}->{interpreter}->split_args($arglist, 2);

            if (not defined $namespace or not defined $keyword) {
                return "Usage: antispam remove <namespace> <regex>";
            }

            return $keywords->remove($namespace, $keyword);
        }

        default {
            return "Unknown command '$command'; commands are: list/show, add, remove";
        }
    }
}

1;
