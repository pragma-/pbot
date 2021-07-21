# File: AntiSpam.pm
#
# Purpose: Checks if a message is spam

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::AntiSpam;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw(gettimeofday);
use POSIX qw/strftime/;

sub initialize {
    my ($self, %conf) = @_;
    my $filename = $conf{spamkeywords_file} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spam_keywords';
    $self->{keywords} = PBot::Storage::DualIndexHashObject->new(name => 'SpamKeywords', filename => $filename, pbot => $self->{pbot});
    $self->{keywords}->load;

    $self->{pbot}->{registry}->add_default('text', 'antispam', 'enforce', $conf{enforce_antispam} // 1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_antispam(@_) }, "antispam", 1);
    $self->{pbot}->{capabilities}->add('admin', 'can-antispam', 1);
}

sub cmd_antispam {
    my ($self, $context) = @_;

    my $arglist = $context->{arglist};

    my $command = $self->{pbot}->{interpreter}->shift_arg($arglist);

    return "Usage: antispam <command>, where commands are: list/show, add, remove, set, unset" if not defined $command;

    given ($command) {
        when ($_ eq "list" or $_ eq "show") {
            my $text    = "Spam keywords:\n";
            my $entries = 0;
            foreach my $namespace ($self->{keywords}->get_keys) {
                $text .= ' ' . $self->{keywords}->get_key_name($namespace) . ":\n";
                foreach my $keyword ($self->{keywords}->get_keys($namespace)) {
                    $text .= '    ' . $self->{keywords}->get_key_name($namespace, $keyword) . ",\n";
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
                return "There is no such regex `$keyword` for namespace `" . $self->{keywords}->get_key_name($namespace) . '`.';
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
                owner      => $context->{hostmask},
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

1;
