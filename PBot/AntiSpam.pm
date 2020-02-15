# File: AntiSpam.pm
# Author: pragma_
#
# Purpose: Checks if a message is spam

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::AntiSpam;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use Time::HiRes qw(gettimeofday);
use POSIX qw/strftime/;

sub initialize {
    my ($self, %conf) = @_;
    my $filename = $conf{spamkeywords_file} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spam_keywords';
    $self->{keywords} = PBot::DualIndexHashObject->new(name => 'SpamKeywords', filename => $filename, pbot => $self->{pbot});
    $self->{keywords}->load;

    $self->{pbot}->{registry}->add_default('text', 'antispam', 'enforce', $conf{enforce_antispam} // 1);
    $self->{pbot}->{commands}->register(sub { $self->antispam_cmd(@_) }, "antispam", 1);
    $self->{pbot}->{capabilities}->add('admin', 'can-antispam', 1);
}

sub is_spam {
    my ($self, $namespace, $text, $all_namespaces) = @_;
    my $lc_namespace = lc $namespace;

    return 0 if not $self->{pbot}->{registry}->get_value('antispam', 'enforce');
    return 0 if $self->{pbot}->{registry}->get_value($namespace, 'dont_enforce_antispam');

    my $ret = eval {
        foreach my $space ($self->{keywords}->get_keys) {
            if ($all_namespaces or $lc_namespace eq $space) {
                foreach my $keyword ($self->{keywords}->get_keys($space)) { return 1 if $text =~ m/$keyword/i; }
            }
        }
        return 0;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error in is_spam: $@");
        return 0;
    }
    $self->{pbot}->{logger}->log("AntiSpam: spam detected!\n") if $ret;
    return $ret;
}

sub antispam_cmd {
    my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

    my $arglist = $stuff->{arglist};

    my $command = $self->{pbot}->{interpreter}->shift_arg($arglist);

    return "Usage: antispam <command>, where commands are: list/show, add, remove, set, unset" if not defined $command;

    given ($command) {
        when ($_ eq "list" or $_ eq "show") {
            my $text    = "Spam keywords:\n";
            my $entries = 0;
            foreach my $namespace ($self->{keywords}->get_keys) {
                $text .= ' ' . $self->{keywords}->get_data($namespace, '_name') . ":\n";
                foreach my $keyword ($self->{keywords}->get_keys($namespace)) {
                    $text .= '    ' . $self->{keywords}->get_data($namespace, $keyword, '_name') . ",\n";
                    $entries++;
                }
            }
            $text .= "none" if $entries == 0;
            return $text;
        }
        when ("set") {
            my ($namespace, $keyword, $flag, $value) = $self->{pbot}->{interpreter}->split_args($arglist, 4);
            return "Usage: antispam set <namespace> <regex> [flag [value]]" if not defined $namespace or not defined $keyword;

            if (not $self->{keywords}->exists($namespace)) { return "There is no such namespace `$namespace`."; }

            if (not $self->{keywords}->exists($namespace, $keyword)) {
                return "There is no such regex `$keyword` for namespace `" . $self->{keywords}->get_data($namespace, '_name') . '`.';
            }

            if (not defined $flag) {
                my $text  = "Flags:\n";
                my $comma = '';
                foreach $flag ($self->{keywords}->get_keys($namespace, $keyword)) {
                    if ($flag eq 'created_on') {
                        my $timestamp = strftime "%a %b %e %H:%M:%S %Z %Y", localtime $self->{keywords}->get_data($namespace, $keyword, $flag);
                        $text .= $comma . "created_on: $timestamp";
                    } else {
                        $value = $self->{keywords}->get_data($namespace, $keyword, $flag);
                        $text .= $comma . "$flag: $value";
                    }
                    $comma = ",\n  ";
                }
                return $text;
            }

            if (not defined $value) {
                $value = $self->{keywords}->get_data($namespace, $keyword, $flag);
                if   (not defined $value) { return "/say $flag is not set."; }
                else                      { return "/say $flag is set to $value"; }
            }
            $self->{keywords}->set($namespace, $keyword, $flag, $value);
            return "Flag set.";
        }
        when ("unset") {
            my ($namespace, $keyword, $flag) = $self->{pbot}->{interpreter}->split_args($arglist, 3);
            return "Usage: antispam unset <namespace> <regex> <flag>" if not defined $namespace or not defined $keyword or not defined $flag;

            if (not $self->{keywords}->exists($namespace)) { return "There is no such namespace `$namespace`."; }

            if (not $self->{keywords}->exists($namespace, $keyword)) { return "There is no such keyword `$keyword` for namespace `$namespace`."; }

            if (not $self->{keywords}->exists($namespace, $keyword, $flag)) { return "There is no such flag `$flag` for regex `$keyword` for namespace `$namespace`."; }
            return $self->{keywords}->remove($namespace, $keyword, $flag);
        }
        when ("add") {
            my ($namespace, $keyword) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
            return "Usage: antispam add <namespace> <regex>" if not defined $namespace or not defined $keyword;
            my $data = {
                owner      => "$nick!$user\@$host",
                created_on => scalar gettimeofday
            };
            $self->{keywords}->add($namespace, $keyword, $data);
            return "/say Added `$keyword`.";
        }
        when ("remove") {
            my ($namespace, $keyword) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
            return "Usage: antispam remove <namespace> <regex>" if not defined $namespace or not defined $keyword;
            return $self->{keywords}->remove($namespace, $keyword);
        }
        default { return "Unknown command '$command'; commands are: list/show, add, remove"; }
    }
}

1;
