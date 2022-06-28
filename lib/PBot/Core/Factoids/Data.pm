# File: Data.pm
#
# Purpose: Implements factoid data-related functions.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Factoids::Data;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw(gettimeofday);

our %factoid_metadata = (
    'action'                => 'TEXT',
    'action_with_args'      => 'TEXT',
    'add_nick'              => 'INTEGER',
    'allow_empty_args'      => 'INTEGER',
    'background-process'    => 'INTEGER',
    'cap-override'          => 'TEXT',
    'created_on'            => 'NUMERIC',
    'dont-protect-self'     => 'INTEGER',
    'dont-replace-pronouns' => 'INTEGER',
    'edited_by'             => 'TEXT',
    'edited_on'             => 'NUMERIC',
    'enabled'               => 'INTEGER',
    'help'                  => 'TEXT',
    'interpolate'           => 'INTEGER',
    'keep-quotes'           => 'INTEGER',
    'keyword_override'      => 'TEXT',
    'last_referenced_in'    => 'TEXT',
    'last_referenced_on'    => 'NUMERIC',
    'locked'                => 'INTEGER',
    'locked_to_channel'     => 'INTEGER',
    'no_keyword_override'   => 'INTEGER',
    'noembed'               => 'INTEGER',
    'nooverride'            => 'INTEGER',
    'owner'                 => 'TEXT',
    'persist-key'           => 'INTEGER',
    'preserve_whitespace'   => 'INTEGER',
    'process-timeout'       => 'INTEGER',
    'rate_limit'            => 'INTEGER',
    'ref_count'             => 'INTEGER',
    'ref_user'              => 'TEXT',
    'require_explicit_args' => 'INTEGER',
    'requires_arguments'    => 'INTEGER',
    'type'                  => 'TEXT',
    'unquote_spaces'        => 'INTEGER',
    'usage'                 => 'TEXT',
    'use_output_queue'      => 'INTEGER',
    'workdir'               => 'TEXT',
);

sub initialize {
    my ($self, %conf) = @_;

    $self->{storage} = PBot::Core::Storage::DualIndexSQLiteObject->new(
        pbot     => $self->{pbot},
        name     => 'Factoids',
        filename => $conf{filename},
    );
}

sub load {
    my ($self) = @_;
    $self->{storage}->load;
    $self->{storage}->create_metadata(\%factoid_metadata);
}

sub save {
    my ($self, $export) = @_;
    $self->{storage}->save;
    $self->{pbot}->{factoids}->{exporter}->export if $export;
}

sub add {
    my ($self, $type, $channel, $owner, $trigger, $action, $dont_save) = @_;

    $type    = lc $type;
    $channel = '.*' if $channel !~ /^#/;

    my $data;
    if ($self->{storage}->exists($channel, $trigger)) {
        # only update action field if force-adding it through factadd -f
        $data = $self->{storage}->get_data($channel, $trigger);

        $data->{action} = $action;
        $data->{type}   = $type;
    } else {
        $data = {
            enabled    => 1,
            type       => $type,
            action     => $action,
            owner      => $owner,
            created_on => scalar gettimeofday,
            ref_count  => 0,
            ref_user   => "nobody",
            rate_limit => $self->{pbot}->{registry}->get_value('factoids', 'default_rate_limit'),
            last_referenced_in => '',
        };
    }

    $self->{storage}->add($channel, $trigger, $data, $dont_save);
}

sub remove {
    my $self = shift;
    my ($channel, $trigger) = @_;
    $channel = '.*' if $channel !~ /^#/;
    return $self->{storage}->remove($channel, $trigger);
}

sub get_meta {
    my ($self, $channel, $trigger, $key) = @_;
    return $self->{storage}->get_data($channel, $trigger, $key);
}

sub find {
    my ($self, $from, $keyword, %opts) = @_;

    my %default_opts = (
        arguments     => '',
        exact_channel => 0,
        exact_trigger => 0,
        find_alias    => 0
    );

    %opts = (%default_opts, %opts);

    my $debug = 0;

    $from    = '.*' if $from !~ /^#/;
    $from    = lc $from;
    $keyword = lc $keyword;

    my $arguments = $opts{arguments};

    my @result = eval {
        my @results;
        my ($channel, $trigger);

        for (my $depth = 0; $depth < 15; $depth++) {
            my $action;

            my $string = $keyword . (length $arguments ? " $arguments" : '');

            $self->{pbot}->{logger}->log("string: $string\n") if $debug;

            if ($opts{exact_channel} and $opts{exact_trigger}) {
                if ($self->{storage}->exists($from, $keyword)) {
                    ($channel, $trigger) = ($from, $keyword);
                    goto CHECK_ALIAS;
                }

                if ($opts{exact_trigger} > 1 and $self->{storage}->exists('.*', $keyword)) {
                    ($channel, $trigger) = ('.*', $keyword);
                    goto CHECK_ALIAS;
                }

                goto CHECK_REGEX;
            }

            if ($opts{exact_channel} and not $opts{exact_trigger}) {
                if (not $self->{storage}->exists($from, $keyword)) {
                    ($channel, $trigger) = ($from, $keyword);
                    goto CHECK_REGEX if $from eq '.*';
                    goto CHECK_REGEX if not $self->{storage}->exists('.*', $keyword);
                    ($channel, $trigger) = ('.*', $keyword);
                    goto CHECK_ALIAS;
                }
                ($channel, $trigger) = ($from, $keyword);
                goto CHECK_ALIAS;
            }

            if (not $opts{exact_channel}) {
                foreach my $factoid ($self->{storage}->get_all("index2 = $keyword", 'index1', 'action')) {
                    $channel = $factoid->{index1};
                    $trigger = $keyword;

                    if ($opts{find_alias} && $factoid->{action} =~ m{^/call\s+(.*)$}ms) {
                        goto CHECK_ALIAS;
                    }

                    push @results, [$channel, $trigger];
                }

                goto CHECK_REGEX;
            }

            CHECK_ALIAS:
            if ($opts{find_alias}) {
                $action = $self->{storage}->get_data($channel, $trigger, 'action') if not defined $action;

                if ($action =~ m{^/call\s+(.*)$}ms) {
                    my $command;
                    if (length $arguments) {
                        $command = "$1 $arguments";
                    } else {
                        $command = $1;
                    }
                    my $arglist = $self->{pbot}->{interpreter}->make_args($command);
                    ($keyword, $arguments) = $self->{pbot}->{interpreter}->split_args($arglist, 2, 0, 1);
                    goto NEXT_DEPTH;
                }
            }

            if ($opts{exact_channel} == 1) {
                return ($channel, $trigger);
            } else {
                push @results, [$channel, $trigger];
            }

            CHECK_REGEX:
            if (not $opts{exact_trigger}) {
                my @factoids;

                if ($opts{exact_channel}) {
                    if ($channel ne '.*') {
                        @factoids = $self->{storage}->get_all('type = regex', "index1 = $channel", 'OR index1 = .*', 'index2', 'action');
                    } else {
                        @factoids = $self->{storage}->get_all('type = regex', "index1 = $channel", 'index2', 'action');
                    }
                } else {
                    @factoids = $self->{storage}->get_all('type = regex', 'index1', 'index2', 'action');
                }

                foreach my $factoid (@factoids) {
                    $channel = $factoid->{index1};
                    $trigger = $factoid->{index2};
                    $action  = $factoid->{action};

                    if ($string =~ /$trigger/) {
                        if ($opts{find_alias}) {
                            my $command = $action;
                            my $arglist = $self->{pbot}->{interpreter}->make_args($command);
                            ($keyword, $arguments) = $self->{pbot}->{interpreter}->split_args($arglist, 2, 0, 1);
                            goto NEXT_DEPTH;
                        }

                        if ($opts{exact_channel} == 1) {
                            return ($channel, $trigger);
                        } else {
                            push @results, [$channel, $trigger];
                        }
                    }
                }
            }

            # match not found
            last;

          NEXT_DEPTH:
            last if not $opts{find_alias};
        }

        if ($debug) {
            if (not @results) {
                $self->{pbot}->{logger}->log("Factoids: find: no match\n");
            } else {
                $self->{pbot}->{logger}->log("Factoids: find: got results: " . (join ', ', map { "$_->[0] -> $_->[1]" } @results) . "\n");
            }
        }

        return @results;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Factoids: error in find: $@\n");
        return undef;
    }

    return @result;
}

1;
