# File: Factoids.pm
# Author: pragma_
#
# Purpose: Provides functionality for factoids and a type of external module execution.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Factoids;
use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use HTML::Entities;
use Time::HiRes qw(gettimeofday);
use Time::Duration qw(duration);
use POSIX qw(strftime);
use Text::ParseWords;
use JSON;

use PBot::FactoidCommands;

use PBot::Utils::Indefinite;
use PBot::Utils::ValidateString;

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
    my $filename = $conf{filename};
    $self->{factoids} = PBot::DualIndexSQLiteObject->new(name => 'Factoids', filename => $filename, pbot => $self->{pbot});

    $self->{pbot}     = $self->{pbot};
    $self->{commands} = PBot::FactoidCommands->new(pbot => $self->{pbot});

    $self->{pbot}->{registry}->add_default('text', 'factoids', 'default_rate_limit', 15);
    $self->{pbot}->{registry}->add_default('text', 'factoids', 'max_name_length',    100);
    $self->{pbot}->{registry}->add_default('text', 'factoids', 'max_content_length', 1024 * 8);
    $self->{pbot}->{registry}->add_default('text', 'factoids', 'max_channel_length', 20);

    $self->{pbot}->{atexit}->register(sub { $self->save_factoids; return; });
    $self->load_factoids;
}

sub load_factoids {
    my $self = shift;
    $self->{factoids}->load;
    $self->{factoids}->create_metadata(\%factoid_metadata);
}

sub save_factoids {
    my $self = shift;
    $self->{factoids}->save;
    $self->export_factoids;
}

sub get_meta {
    my ($self, $channel, $trigger, $key) = @_;
    $channel = lc $channel;
    $trigger = lc $trigger;
    my ($chan, $trig) = $self->find_factoid($channel, $trigger, exact_channel => 1);
    return undef if not defined $chan;
    return $self->{factoids}->get_data($chan, $trig, $key);
}

sub add_factoid {
    my $self = shift;
    my ($type, $channel, $owner, $trigger, $action, $dont_save) = @_;
    $type    = lc $type;
    $channel = '.*' if $channel !~ /^#/;

    my $data;
    if ($self->{factoids}->exists($channel, $trigger)) {
        # only update action field if force-adding it through factadd -f
        $data           = $self->{factoids}->get_data($channel, $trigger);
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
            rate_limit => $self->{pbot}->{registry}->get_value('factoids', 'default_rate_limit')
        };
    }

    $self->{commands}->log_factoid($channel, $trigger, $owner, "created: $action") unless $dont_save;
    $self->{factoids}->add($channel, $trigger, $data, $dont_save);
}

sub remove_factoid {
    my $self = shift;
    my ($channel, $trigger) = @_;
    $channel = '.*' if $channel !~ /^#/;
    return $self->{factoids}->remove($channel, $trigger);
}

sub export_factoids {
    my $self = shift;
    my $filename;

    if   (@_) { $filename = shift; }
    else      { $filename = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factoids.html'; }
    return if not defined $filename;

    $self->{pbot}->{logger}->log("Exporting factoids to $filename\n");

    open FILE, "> $filename" or return "Could not open export path.";

    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
    my $time    = localtime;
    print FILE "<html><head>\n<link href='css/blue.css' rel='stylesheet' type='text/css'>\n";
    print FILE '<script type="text/javascript" src="js/jquery-latest.js"></script>' . "\n";
    print FILE '<script type="text/javascript" src="js/jquery.tablesorter.js"></script>' . "\n";
    print FILE '<script type="text/javascript" src="js/picnet.table.filter.min.js"></script>' . "\n";
    print FILE "</head>\n<body><i>Last updated at $time</i>\n";
    print FILE "<hr><h2>$botnick\'s factoids</h2>\n";

    my $i        = 0;
    my $table_id = 1;

    foreach my $channel (sort $self->{factoids}->get_keys) {
        next if not $self->{factoids}->get_keys($channel);
        my $chan = $self->{factoids}->get_data($channel, '_name');
        $chan = 'global' if $chan eq '.*';

        print FILE "<a href='#" . encode_entities($chan) . "'>" . encode_entities($chan) . "</a><br>\n";
    }

    foreach my $channel (sort $self->{factoids}->get_keys) {
        next if not $self->{factoids}->get_keys($channel);
        my $chan = $self->{factoids}->get_data($channel, '_name');
        $chan = 'global' if $chan eq '.*';
        print FILE "<a name='" . encode_entities($chan) . "'></a>\n";
        print FILE "<hr>\n<h3>" . encode_entities($chan) . "</h3>\n<hr>\n";
        print FILE "<table border=\"0\" id=\"table$table_id\" class=\"tablesorter\">\n";
        print FILE "<thead>\n<tr>\n";
        print FILE "<th>owner</th>\n";
        print FILE "<th>created on</th>\n";
        print FILE "<th>times referenced</th>\n";
        print FILE "<th>factoid</th>\n";
        print FILE "<th>last edited by</th>\n";
        print FILE "<th>edited date</th>\n";
        print FILE "<th>last referenced by</th>\n";
        print FILE "<th>last referenced date</th>\n";
        print FILE "</tr>\n</thead>\n<tbody>\n";
        $table_id++;

        foreach my $trigger (sort $self->{factoids}->get_keys($channel)) {
            my $trigger_name = $self->{factoids}->get_data($channel, $trigger, '_name');
            if ($self->{factoids}->get_data($channel, $trigger, 'type') eq 'text') {
                $i++;
                if   ($i % 2) { print FILE "<tr bgcolor=\"#dddddd\">\n"; }
                else          { print FILE "<tr>\n"; }

                print FILE "<td>" . encode_entities($self->{factoids}->get_data($channel, $trigger, 'owner')) . "</td>\n";
                print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %H:%M:%S", localtime $self->{factoids}->get_data($channel, $trigger, 'created_on')) . "</td>\n";

                print FILE "<td>" . $self->{factoids}->get_data($channel, $trigger, 'ref_count') . "</td>\n";

                my $action = $self->{factoids}->get_data($channel, $trigger, 'action');

                if ($action =~ m/https?:\/\/[^ ]+/) {
                    $action =~ s/(.*?)http(s?:\/\/[^ ]+)/encode_entities($1) . "<a href='http" . encode_entities($2) . "'>http" . encode_entities($2) . "<\/a>"/ge;
                    $action =~ s/(.*)<\/a>(.*$)/"$1<\/a>" . encode_entities($2)/e;
                } else {
                    $action = encode_entities($action);
                }

                if ($self->{factoids}->exists($channel, $trigger, 'action_with_args')) {
                    my $with_args = $self->{factoids}->get_data($channel, $trigger, 'action_with_args');
                    $with_args =~ s/(.*?)http(s?:\/\/[^ ]+)/encode_entities($1) . "<a href='http" . encode_entities($2) . "'>http" . encode_entities($2) . "<\/a>"/ge;
                    $with_args =~ s/(.*)<\/a>(.*$)/"$1<\/a>" . encode_entities($2)/e;
                    print FILE "<td width=100%><b>" . encode_entities($trigger_name) . "</b> is $action<br><br><b>with_args:</b> " . encode_entities($with_args) . "</td>\n";
                } else {
                    print FILE "<td width=100%><b>" . encode_entities($trigger_name) . "</b> is $action</td>\n";
                }

                if ($self->{factoids}->exists($channel, $trigger, 'edited_by')) {
                    print FILE "<td>" . $self->{factoids}->get_data($channel, $trigger, 'edited_by') . "</td>\n";
                    print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %H:%M:%S", localtime $self->{factoids}->get_data($channel, $trigger, 'edited_on')) . "</td>\n";
                } else {
                    print FILE "<td></td>\n";
                    print FILE "<td></td>\n";
                }

                print FILE "<td>" . encode_entities($self->{factoids}->get_data($channel, $trigger, 'ref_user')) . "</td>\n";

                if ($self->{factoids}->exists($channel, $trigger, 'last_referenced_on')) {
                    print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %H:%M:%S", localtime $self->{factoids}->get_data($channel, $trigger, 'last_referenced_on')) . "</td>\n";
                } else {
                    print FILE "<td></td>\n";
                }

                print FILE "</tr>\n";
            }
        }
        print FILE "</tbody>\n</table>\n";
    }

    print FILE "<hr>$i factoids memorized.<br>";
    print FILE "<hr><i>Last updated at $time</i>\n";

    print FILE "<script type='text/javascript'>\n";
    $table_id--;
    print FILE '$(document).ready(function() {' . "\n";
    while ($table_id > 0) {
        print FILE '$("#table' . $table_id . '").tablesorter();' . "\n";
        print FILE '$("#table' . $table_id . '").tableFilter();' . "\n";
        $table_id--;
    }
    print FILE "});\n";
    print FILE "</script>\n";
    print FILE "</body>\n</html>\n";

    close(FILE);

    return "/say $i factoids exported.";
}

sub find_factoid {
    my ($self, $from, $keyword, %opts) = @_;

    my %default_opts = (
        arguments     => '',
        exact_channel => 0,
        exact_trigger => 0,
        find_alias    => 0
    );

    %opts = (%default_opts, %opts);

    my $debug = 0;

    if ($debug) {
        use Data::Dumper;
        my $dump = Dumper \%opts;
        $self->{pbot}->{logger}->log("+" x 32 . "\n");
        use Devel::StackTrace;
        my $trace = Devel::StackTrace->new(indent => 1, ignore_class => ['PBot::PBot', 'PBot::IRC']);
        $self->{pbot}->{logger}->log("find_factoid stacktrace: " . $trace->as_string() . "\n");

        $self->{pbot}->{logger}->log("find_factiod: from: $from, kw: $keyword, opts: $dump\n");
    }

    $from    = '.*' if not defined $from or $from !~ /^#/;
    $from    = lc $from;
    $keyword = lc $keyword;

    my $arguments = $opts{arguments};

    my @result = eval {
        my @results;
        my ($channel, $trigger);
        for (my $depth = 0; $depth < 15; $depth++) {
            my $action;
            my $string = $keyword . (length $arguments ? " $arguments" : "");
            $self->{pbot}->{logger}->log("string: $string\n") if $debug;

            if ($opts{exact_channel} and $opts{exact_trigger}) {
                if ($self->{factoids}->exists($from, $keyword)) {
                    ($channel, $trigger) = ($from, $keyword);
                    goto CHECK_ALIAS;
                }

                if ($opts{exact_trigger} > 1 and $self->{factoids}->exists('.*', $keyword)) {
                    ($channel, $trigger) = ('.*', $keyword);
                    goto CHECK_ALIAS;
                }

                goto CHECK_REGEX;
            }

            if ($opts{exact_channel} and not $opts{exact_trigger}) {
                if (not $self->{factoids}->exists($from, $keyword)) {
                    goto CHECK_REGEX if $from eq '.*';
                    goto CHECK_REGEX if not $self->{factoids}->exists('.*', $keyword);
                    ($channel, $trigger) = ('.*', $keyword);
                    goto CHECK_ALIAS;
                }
                ($channel, $trigger) = ($from, $keyword);
                goto CHECK_ALIAS;
            }

            if (not $opts{exact_channel}) {
                foreach my $factoid ($self->{factoids}->get(index2 => $keyword, index1 => undef, action => undef)) {
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
                $action = $self->{factoids}->get_data($channel, $trigger, 'action') if not defined $action;
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
                    @factoids = $self->{factoids}->get(type => 'regex', index1 => $channel, index2 => undef, action => undef);
                    push @factoids, $self->{factoids}->get(type => 'regex', index1 => '.*', index2 => undef, action => undef);
                } else {
                    @factoids = $self->{factoids}->get(type => 'regex', index1 => undef, index2 => undef, action => undef);
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

                        if ($opts{exact_channel} == 1) { return ($channel, $trigger); }
                        else                           { push @results, [$channel, $trigger]; }
                    }
                }
            }

            # match not found
            last;

          NEXT_DEPTH:
            last if not $opts{find_alias};
        }

        if ($debug) {
            if (not @results) { $self->{pbot}->{logger}->log("find_factoid: no match\n"); }
            else {
                $self->{pbot}->{logger}->log("find_factoid: got results: " . (join ', ', map { "$_->[0] -> $_->[1]" } @results) . "\n");
            }
        }
        return @results;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error in find_factoid: $@\n");
        return undef;
    }

    return @result;
}

sub escape_json {
    my ($self, $text) = @_;
    my $thing = {thing => $text};
    my $json  = encode_json $thing;
    $json =~ s/^{".*":"//;
    $json =~ s/"}$//;
    return $json;
}

sub expand_special_vars {
    my ($self, $from, $nick, $root_keyword, $action) = @_;

    $action =~ s/\$nick:json|\$\{nick:json\}/$self->escape_json($nick)/ge;
    $action =~ s/\$channel:json|\$\{channel:json\}/$self->escape_json($from)/ge;
    $action =~
      s/\$randomnick:json|\$\{randomnick:json\}/my $random = $self->{pbot}->{nicklist}->random_nick($from); $random ? $self->escape_json($random) : $self->escape_json($nick)/ge;
    $action =~ s/\$0:json|\$\{0:json\}/$self->escape_json($root_keyword)/ge;

    $action =~ s/\$nick|\$\{nick\}/$nick/g;
    $action =~ s/\$channel|\$\{channel\}/$from/g;
    $action =~ s/\$randomnick|\$\{randomnick\}/my $random = $self->{pbot}->{nicklist}->random_nick($from); $random ? $random : $nick/ge;
    $action =~ s/\$0\b|\$\{0\}\b/$root_keyword/g;

    return validate_string($action, $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));
}

sub expand_factoid_vars {
    my ($self, $stuff, @exclude) = @_;

    my $from         = length $stuff->{ref_from} ? $stuff->{ref_from} : $stuff->{from};
    my $nick         = $stuff->{nick};
    my $root_keyword = $stuff->{keyword_override} ? $stuff->{keyword_override} : $stuff->{root_keyword};
    my $action       = $stuff->{action};

    my $debug = 0;
    my $depth = 0;

    if ($debug) {
        $self->{pbot}->{logger}->log("enter expand_factoid_vars\n");
        use Data::Dumper;
        $self->{pbot}->{logger}->log(Dumper $stuff);
    }

    if ($action =~ m/^\/call --keyword-override=([^ ]+)/i) { $root_keyword = $1; }

    while (1) {
        last if ++$depth >= 1000;

        my $offset     = 0;
        my $matches    = 0;
        my $expansions = 0;
        $action =~ s/\$0/$root_keyword/g;
        my $const_action = $action;

        $self->{pbot}->{logger}->log("action: $const_action\n") if $debug;

        while ($const_action =~ /(\ba\s*|\ban\s*)?(?<!\\)\$(?:(\{[a-zA-Z0-9_:#]+\}|[a-zA-Z0-9_:#]+))/gi) {
            my ($a, $v) = ($1, $2);
            $a = '' if not defined $a;
            next if not defined $v;

            my $original_v = $v;
            my $test_v     = $v;

            $test_v =~ s/(.):$/$1/;    # remove trailing : only if at least one character precedes it
            next if $test_v =~ m/^_/;                                                                      # special character prefix skipped for shell/code-factoids/etc
            next if $test_v =~ m/^(?:nick|channel|randomnick|arglen|args|arg\[.+\]|[_0])(?:\:json)*$/i;    # don't override special variables
            next if @exclude && grep { $test_v =~ m/^\Q$_\E$/i } @exclude;
            last if ++$depth >= 1000;

            $self->{pbot}->{logger}->log("v: [$original_v], test v: [$test_v]\n") if $debug;

            $matches++;

            $test_v =~ s/\{(.+)\}/$1/;

            my $modifier = '';
            if ($test_v =~ s/(:.*)$//) { $modifier = $1; }

            if ($modifier =~ m/^:(#[^:]+|global)/i) {
                $from = $1;
                $from = '.*' if lc $from eq 'global';
            }

            my $recurse = 0;
          ALIAS:
            my @factoids = $self->find_factoid($from, $test_v, exact_channel => 2, exact_trigger => 2);
            next if not @factoids or not $factoids[0];

            my ($var_chan, $var) = ($factoids[0]->[0], $factoids[0]->[1]);

            if ($self->{factoids}->get_data($var_chan, $var, 'action') =~ m{^/call (.*)}ms) {
                $test_v = $1;
                next if ++$recurse > 100;
                goto ALIAS;
            }

            if ($self->{factoids}->get_data($var_chan, $var, 'type') eq 'text') {
                my $change = $self->{factoids}->get_data($var_chan, $var, 'action');
                my @list   = $self->{pbot}->{interpreter}->split_line($change);
                my @mylist;
                for (my $i = 0; $i <= $#list; $i++) { push @mylist, $list[$i] if defined $list[$i] and length $list[$i]; }
                my $line = int(rand($#mylist + 1));
                if (not $mylist[$line] =~ s/^"(.*)"$/$1/) { $mylist[$line] =~ s/^'(.*)'$/$1/; }

                foreach my $mod (split /:/, $modifier) {
                    next if not length $mod;

                    if ($mylist[$line] =~ /^\$\{\$([a-zA-Z0-9_:#]+)\}(.*)$/) {
                        $mylist[$line] = "\${\$$1:$mod}$2";
                        next;
                    } elsif ($mylist[$line] =~ /^\$\{([a-zA-Z0-9_:#]+)\}(.*)$/) {
                        $mylist[$line] = "\${$1:$mod}$2";
                        next;
                    } elsif ($mylist[$line] =~ /^\$\$([a-zA-Z0-9_:#]+)(.*)$/) {
                        $mylist[$line] = "\${\$$1:$mod}$2";
                        next;
                    } elsif ($mylist[$line] =~ /^\$([a-zA-Z0-9_:#]+)(.*)$/) {
                        $mylist[$line] = "\${$1:$mod}$2";
                        next;
                    }

                    given ($mod) {
                        when ('uc')      { $mylist[$line] = uc $mylist[$line]; }
                        when ('lc')      { $mylist[$line] = lc $mylist[$line]; }
                        when ('ucfirst') { $mylist[$line] = ucfirst $mylist[$line]; }
                        when ('title') {
                            $mylist[$line] = ucfirst lc $mylist[$line];
                            $mylist[$line] =~ s/ (\w)/' ' . uc $1/ge;
                        }
                        when ('json') { $mylist[$line] = $self->escape_json($mylist[$line]); }
                    }
                }

                my $replacement = $mylist[$line];

                if ($a) {
                    my $fixed_a = select_indefinite_article $mylist[$line];
                    $fixed_a     = ucfirst $fixed_a if $a =~ m/^A/;
                    $replacement = "$fixed_a $mylist[$line]";
                }

                if ($debug and $offset == 0) { $self->{pbot}->{logger}->log(("-" x 40) . "\n"); }

                $original_v = quotemeta $original_v;
                $original_v =~ s/\\:/:/g;

                if (not length $mylist[$line]) {
                    $self->{pbot}->{logger}->log("No length!\n") if $debug;
                    if ($debug) {
                        $self->{pbot}->{logger}->log("before: v: $original_v, offset: $offset\n");
                        $self->{pbot}->{logger}->log("$action\n");
                        $self->{pbot}->{logger}->log((" " x $offset) . "^\n");
                    }

                    substr($action, $offset) =~ s/$a\$$original_v ?/$replacement/;
                    $offset += $-[0] + length $replacement;

                    if ($debug) {
                        $self->{pbot}->{logger}->log("after: r: EMPTY \$-[0]: $-[0], offset: $offset\n");
                        $self->{pbot}->{logger}->log("$action\n");
                        $self->{pbot}->{logger}->log((" " x $offset) . "^\n");
                    }
                } else {
                    if ($debug) {
                        $self->{pbot}->{logger}->log("before: v: $original_v, offset: $offset\n");
                        $self->{pbot}->{logger}->log("$action\n");
                        $self->{pbot}->{logger}->log((" " x $offset) . "^\n");
                    }

                    substr($action, $offset) =~ s/$a\$$original_v/$replacement/;
                    $offset += $-[0] + length $replacement;

                    if ($debug) {
                        $self->{pbot}->{logger}->log("after: r: $replacement, \$-[0]: $-[0], offset: $offset\n");
                        $self->{pbot}->{logger}->log("$action\n");
                        $self->{pbot}->{logger}->log((" " x $offset) . "^\n");
                    }
                }
                $expansions++;
            }
        }
        last if $matches == 0 or $expansions == 0;
    }

    $action =~ s/\\\$/\$/g;

    unless (@exclude) { $action = $self->expand_special_vars($from, $nick, $root_keyword, $action); }

    return validate_string($action, $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));
}

sub expand_action_arguments {
    my ($self, $action, $input, $nick) = @_;

    $action = validate_string($action, $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));
    $input  = validate_string($input,  $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));

    my %h;
    if   (not defined $input or $input eq '') { %h = (args => $nick); }
    else                                      { %h = (args => $input); }

    my $jsonargs = encode_json \%h;
    $jsonargs =~ s/^{".*":"//;
    $jsonargs =~ s/"}$//;

    if (not defined $input or $input eq '') {
        $input = "";
        $action =~ s/\$args:json|\$\{args:json\}/$jsonargs/ge;
        $action =~ s/\$args(?![[\w])|\$\{args(?![[\w])\}/$nick/g;
    } else {
        $action =~ s/\$args:json|\$\{args:json\}/$jsonargs/g;
        $action =~ s/\$args(?![[\w])|\$\{args(?![[\w])\}/$input/g;
    }

    my @args = $self->{pbot}->{interpreter}->split_line($input);
    $action =~ s/\$arglen\b|\$\{arglen\}/scalar @args/eg;

    my $depth        = 0;
    my $const_action = $action;
    while ($const_action =~ m/\$arg\[([^]]+)]|\$\{arg\[([^]]+)]\}/g) {
        my $arg = defined $2 ? $2 : $1;

        last if ++$depth >= 100;

        if ($arg eq '*') {
            if   (not defined $input or $input eq '') { $action =~ s/\$arg\[\*\]|\$\{arg\[\*\]\}/$nick/; }
            else                                      { $action =~ s/\$arg\[\*\]|\$\{arg\[\*\]\}/$input/; }
            next;
        }

        if ($arg =~ m/([^:]*):(.*)/) {
            my $arg1 = $1;
            my $arg2 = $2;

            my $arg1i = $arg1;
            my $arg2i = $arg2;

            $arg1i = 0      if $arg1i eq '';
            $arg2i = $#args if $arg2i eq '';
            $arg2i = $#args if $arg2i > $#args;

            my @values = eval {
                local $SIG{__WARN__} = sub { };
                return @args[$arg1i .. $arg2i];
            };

            if ($@) { next; }
            else {
                my $string = join(' ', @values);

                if   ($string eq '') { $action =~ s/\s*\$\{arg\[$arg1:$arg2\]\}//     || $action =~ s/\s*\$arg\[$arg1:$arg2\]//; }
                else                 { $action =~ s/\$\{arg\[$arg1:$arg2\]\}/$string/ || $action =~ s/\$arg\[$arg1:$arg2\]/$string/; }
            }

            next;
        }

        my $value = eval {
            local $SIG{__WARN__} = sub { };
            return $args[$arg];
        };

        if ($@) { next; }
        else {
            if (not defined $value) {
                if   ($arg == 0) { $action =~ s/\$\{arg\[$arg\]\}/$nick/ || $action =~ s/\$arg\[$arg\]/$nick/; }
                else             { $action =~ s/\s*\$\{arg\[$arg\]\}//   || $action =~ s/\s*\$arg\[$arg\]//; }
            } else {
                $action =~ s/\$arg\{\[$arg\]\}/$value/ || $action =~ s/\$arg\[$arg\]/$value/;
            }
        }
    }

    return $action;
}

sub execute_code_factoid_using_vm {
    my ($self, $stuff) = @_;

    unless ($self->{factoids}->exists($stuff->{channel}, $stuff->{keyword}, 'interpolate')
        and $self->{factoids}->get_data($stuff->{channel}, $stuff->{keyword}, 'interpolate') eq '0')
    {
        if   ($stuff->{code} =~ m/(?:\$\{?nick\b|\$\{?args\b|\$\{?arg\[)/ and length $stuff->{arguments}) { $stuff->{no_nickoverride} = 1; }
        else                                                                                              { $stuff->{no_nickoverride} = 0; }

        $stuff->{action} = $stuff->{code};
        $stuff->{code}   = $self->expand_factoid_vars($stuff);

        if ($self->{factoids}->get_data($stuff->{channel}, $stuff->{keyword}, 'allow_empty_args')) {
            $stuff->{code} = $self->expand_action_arguments($stuff->{code}, $stuff->{arguments}, '');
        } else {
            $stuff->{code} = $self->expand_action_arguments($stuff->{code}, $stuff->{arguments}, $stuff->{nick});
        }
    } else {
        $stuff->{no_nickoverride} = 0;
    }

    my %h = (
        nick    => $stuff->{nick}, channel => $stuff->{from}, lang => $stuff->{lang}, code => $stuff->{code}, arguments => $stuff->{arguments},
        factoid => "$stuff->{channel}:$stuff->{keyword}"
    );

    if ($self->{factoids}->exists($stuff->{channel}, $stuff->{keyword}, 'persist-key')) {
        $h{'persist-key'} = $self->{factoids}->get_data($stuff->{channel}, $stuff->{keyword}, 'persist-key');
    }

    my $json = encode_json \%h;

    $stuff->{special}      = 'code-factoid';
    $stuff->{root_channel} = $stuff->{channel};
    $stuff->{keyword}      = 'compiler';
    $stuff->{arguments}    = $json;
    $stuff->{args_utf8}    = 1;

    $self->{pbot}->{modules}->execute_module($stuff);
    return "";
}

sub execute_code_factoid {
    my ($self, @args) = @_;
    return $self->execute_code_factoid_using_vm(@args);
}

sub interpreter {
    my ($self, $stuff) = @_;
    my $pbot = $self->{pbot};

    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("Factoids::interpreter\n");
        $self->{pbot}->{logger}->log(Dumper $stuff);
    }

    return undef if not length $stuff->{keyword} or $stuff->{interpret_depth} > $self->{pbot}->{registry}->get_value('interpreter', 'max_recursion');

    $stuff->{from} = lc $stuff->{from};

    my $strictnamespace = $self->{pbot}->{registry}->get_value($stuff->{from}, 'strictnamespace');

    if (not defined $strictnamespace) { $strictnamespace = $self->{pbot}->{registry}->get_value('general', 'strictnamespace'); }

    # search for factoid against global channel and current channel (from unless ref_from is defined)
    my $original_keyword = $stuff->{keyword};
    my ($channel, $keyword) =
      $self->find_factoid($stuff->{ref_from} ? $stuff->{ref_from} : $stuff->{from}, $stuff->{keyword}, arguments => $stuff->{arguments}, exact_channel => 1);

    if (not $stuff->{ref_from} or $stuff->{ref_from} eq '.*' or $stuff->{ref_from} eq $stuff->{from}) { $stuff->{ref_from} = ""; }

    if (defined $channel and not $channel eq '.*' and not $channel eq lc $stuff->{from}) { $stuff->{ref_from} = $channel; }

    $stuff->{arguments} = "" if not defined $stuff->{arguments};

    # if no match found, attempt to call factoid from another channel if it exists there
    if (not defined $keyword) {
        my $string = "$original_keyword $stuff->{arguments}";

        my @chanlist   = ();
        my ($fwd_chan, $fwd_trig);

        # build list of which channels contain the keyword, keeping track of the last one and count
        foreach my $factoid ($self->{factoids}->get(index2 => $original_keyword, index1 => undef, type => undef)) {
            next if $factoid->{type} ne 'text' and $factoid->{type} ne 'module';
            push @chanlist, $self->{factoids}->get_data($factoid->{index1}, '_name');
            $fwd_chan = $factoid->{index1};
            $fwd_trig = $original_keyword;
        }

        my $ref_from = $stuff->{ref_from} ? "[$stuff->{ref_from}] " : "";

        # if multiple channels have this keyword, then ask user to disambiguate
        if (@chanlist> 1) {
            return undef if $stuff->{referenced};
            return $ref_from . "Ambiguous keyword '$original_keyword' exists in multiple channels (use 'fact <channel> $original_keyword' to choose one): " . join(', ', @chanlist);
        }

        # if there's just one other channel that has this keyword, trigger that instance
        elsif (@chanlist == 1) {
            $pbot->{logger}->log("Found '$original_keyword' as '$fwd_trig' in [$fwd_chan]\n");
            $stuff->{keyword} = $fwd_trig;
            $stuff->{interpret_depth}++;
            $stuff->{ref_from} = $fwd_chan;
            return $pbot->{factoids}->interpreter($stuff);
        }

        # otherwise keyword hasn't been found, display similiar matches for all channels
        else {
            # if a non-nick argument was supplied, e.g., a sentence using the bot's nick, don't say anything
            return undef if length $stuff->{arguments} and not $self->{pbot}->{nicklist}->is_present($stuff->{from}, $stuff->{arguments});

            my $namespace = $strictnamespace ? $stuff->{from} : '.*';
            $namespace = '.*' if $namespace !~ /^#/;

            my $namespace_regex = $namespace;
            if ($strictnamespace) { $namespace_regex = "(?:" . (quotemeta $namespace) . '|\\.\\*)'; }

            my $matches = $self->{commands}->factfind($stuff->{from}, $stuff->{nick}, $stuff->{user}, $stuff->{host}, quotemeta($original_keyword) . " -channel $namespace_regex");

            # found factfind matches
            if ($matches !~ m/^No factoids/) {
                return undef if $stuff->{referenced};
                return "No such factoid '$original_keyword'; $matches";
            }

            # otherwise find levenshtein closest matches
            $matches = $self->{factoids}->levenshtein_matches($namespace, lc $original_keyword, 0.50, $strictnamespace);

            # don't say anything if nothing similiar was found
            return undef if $matches eq 'none';
            return undef if $stuff->{referenced};

            my $ref_from = $stuff->{ref_from} ? "[$stuff->{ref_from}] " : "";
            return $ref_from . "No such factoid '$original_keyword'; did you mean $matches?";
        }
    }

    my $channel_name = $self->{factoids}->get_data($channel, '_name');
    my $trigger_name = $self->{factoids}->get_data($channel, $keyword, '_name');
    $channel_name = 'global'            if $channel_name eq '.*';
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    $stuff->{keyword}          = $keyword;
    $stuff->{trigger}          = $keyword;
    $stuff->{channel}          = $channel;
    $stuff->{original_keyword} = $original_keyword;
    $stuff->{channel_name}     = $channel_name;
    $stuff->{trigger_name}     = $trigger_name;

    return undef if $stuff->{referenced} and $self->{factoids}->get_data($channel, $keyword, 'noembed');

    if ($self->{factoids}->get_data($channel, $keyword, 'locked_to_channel')) {
        if ($stuff->{ref_from} ne "") {    # called from another channel
            return "$trigger_name may be invoked only in $stuff->{ref_from}.";
        }
    }

    if ($self->{factoids}->exists($channel, $keyword, 'last_referenced_on')) {
        if ($self->{factoids}->exists($channel, $keyword, 'last_referenced_in')) {
            if ($self->{factoids}->get_data($channel, $keyword, 'last_referenced_in') eq $stuff->{from}) {
                my $ratelimit = $self->{pbot}->{registry}->get_value($stuff->{from}, 'ratelimit_override');
                $ratelimit = $self->{factoids}->get_data($channel, $keyword, 'rate_limit') if not defined $ratelimit;
                if (gettimeofday - $self->{factoids}->get_data($channel, $keyword, 'last_referenced_on') < $ratelimit) {
                    my $ref_from = $stuff->{ref_from} ? "[$stuff->{ref_from}] " : "";
                    return
                      "/msg $stuff->{nick} $ref_from'$trigger_name' is rate-limited; try again in "
                      . duration($ratelimit - int(gettimeofday - $self->{factoids}->get_data($channel, $keyword, 'last_referenced_on'))) . "."
                      unless $self->{pbot}->{users}->loggedin_admin($channel, "$stuff->{nick}!$stuff->{user}\@$stuff->{host}");
                }
            }
        }
    }

    my $ref_count = $self->{factoids}->get_data($channel, $keyword, 'ref_count');
    my $update_data = {
        ref_count          => ++$ref_count,
        ref_user           => "$stuff->{nick}!$stuff->{user}\@$stuff->{host}",
        last_referenced_on => scalar gettimeofday,
        last_referenced_in => $stuff->{from} || 'stdin',
    };
    $self->{factoids}->add($channel, $keyword, $update_data, 1, 1);

    my $action;

    if ($self->{factoids}->exists($channel, $keyword, 'usage') and not length $stuff->{arguments} and $self->{factoids}->get_data($channel, $keyword, 'requires_arguments')) {
        $stuff->{alldone} = 1;
        my $usage = $self->{factoids}->get_data($channel, $keyword, 'usage');
        $usage =~ s/\$0|\$\{0\}/$trigger_name/g;
        return $usage;
    }

    if (length $stuff->{arguments} and $self->{factoids}->exists($channel, $keyword, 'action_with_args')) {
        $action = $self->{factoids}->get_data($channel, $keyword, 'action_with_args');
    } else {
        $action = $self->{factoids}->get_data($channel, $keyword, 'action');
    }

    if ($action =~ m{^/code\s+([^\s]+)\s+(.+)$}msi) {
        my ($lang, $code) = ($1, $2);

        if ($self->{factoids}->exists($channel, $keyword, 'usage') and not length $stuff->{arguments}) {
            $stuff->{alldone} = 1;
            my $usage = $self->{factoids}->get_data($channel, $keyword, 'usage');
            $usage =~ s/\$0|\$\{0\}/$trigger_name/g;
            return $usage;
        }

        $stuff->{lang} = $lang;
        $stuff->{code} = $code;
        $self->execute_code_factoid($stuff);
        return "";
    }

    if ($self->{factoids}->get_data($channel, $keyword, 'background-process')) {
        my $timeout = $self->{factoids}->get_data($channel, $keyword, 'process-timeout') // $self->{pbot}->{registry}->get_value('processmanager', 'default_timeout');
        $self->{pbot}->{process_manager}->execute_process(
            $stuff,
            sub { $stuff->{result} = $self->handle_action($stuff, $action); },
            $timeout
        );
        return "";
    } else {
        return $self->handle_action($stuff, $action);
    }
}

sub handle_action {
    my ($self, $stuff, $action) = @_;

    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("Factoids::handle_action [$action]\n");
        $self->{pbot}->{logger}->log(Dumper $stuff);
    }

    return "" if not length $action;

    my ($channel,      $keyword)      = ($stuff->{channel},      $stuff->{trigger});
    my ($channel_name, $trigger_name) = ($stuff->{channel_name}, $stuff->{trigger_name});
    my $ref_from = $stuff->{ref_from} ? "[$stuff->{ref_from}] " : "";

    unless ($self->{factoids}->exists($channel, $keyword, 'interpolate') and $self->{factoids}->get_data($channel, $keyword, 'interpolate') eq '0') {
        my ($root_channel, $root_keyword) =
          $self->find_factoid($stuff->{ref_from} ? $stuff->{ref_from} : $stuff->{from}, $stuff->{root_keyword}, arguments => $stuff->{arguments}, exact_channel => 1);
        if (not defined $root_channel or not defined $root_keyword) {
            $root_channel = $channel;
            $root_keyword = $keyword;
        }
        if (not length $stuff->{keyword_override} and length $self->{factoids}->get_data($root_channel, $root_keyword, 'keyword_override')) {
            $stuff->{keyword_override} = $self->{factoids}->get_data($root_channel, $root_keyword, 'keyword_override');
        }
        $stuff->{action} = $action;
        $action = $self->expand_factoid_vars($stuff);
    }

    if (length $stuff->{arguments}) {
        if ($action =~ m/\$\{?args/ or $action =~ m/\$\{?arg\[/) {
            unless (defined $self->{factoids}->get_data($channel, $keyword, 'interpolate') and $self->{factoids}->get_data($channel, $keyword, 'interpolate') eq '0') {
                $action = $self->expand_action_arguments($action, $stuff->{arguments}, $stuff->{nick});
                $stuff->{no_nickoverride} = 1;
            } else {
                $stuff->{no_nickoverride} = 0;
            }
            $stuff->{arguments}          = "";
            $stuff->{original_arguments} = "";
        } else {
            if ($self->{factoids}->get_data($channel, $keyword, 'type') eq 'text') {
                my $target = $self->{pbot}->{nicklist}->is_present_similar($stuff->{from}, $stuff->{arguments});

                if ($target and $action !~ /\$\{?(?:nick|args)\b/) {
                    $stuff->{nickoverride}    = $target unless $stuff->{force_nickoverride};
                    $stuff->{no_nickoverride} = 0;
                } else {
                    $stuff->{no_nickoverride} = 1;
                }
            }
        }
    } else {
        # no arguments supplied, replace $args with $nick/$tonick, etc
        if ($self->{factoids}->exists($channel, $keyword, 'usage')) {
            $action = "/say " . $self->{factoids}->get_data($channel, $keyword, 'usage');
            $action =~ s/\$0|\$\{0\}/$trigger_name/g;
            $stuff->{alldone} = 1;
        } else {
            if   ($self->{factoids}->get_data($channel, $keyword, 'allow_empty_args')) { $action = $self->expand_action_arguments($action, undef, ''); }
            else                                                                       { $action = $self->expand_action_arguments($action, undef, $stuff->{nick}); }
        }
        $stuff->{no_nickoverride} = 0;
    }

    # Check if it's an alias
    if ($action =~ /^\/call\s+(.*)$/msi) {
        my $command = $1;
        $command =~ s/\n$//;
        unless ($self->{factoids}->get_data($channel, $keyword, 'require_explicit_args')) {
            my $args = $stuff->{arguments};
            $command .= " $args" if length $args and not $stuff->{special} eq 'code-factoid';
            $stuff->{arguments} = '';
        }

        unless ($self->{factoids}->get_data($channel, $keyword, 'no_keyword_override')) {
            if ($command =~ s/\s*--keyword-override=([^ ]+)\s*//) { $stuff->{keyword_override} = $1; }
        }

        $stuff->{command} = $command;
        $stuff->{aliased} = 1;

        $self->{pbot}->{logger}
          ->log("[" . (defined $stuff->{from} ? $stuff->{from} : "stdin") . "] ($stuff->{nick}!$stuff->{user}\@$stuff->{host}) $trigger_name aliased to: $command\n");

        if (defined $self->{factoids}->get_data($channel, $keyword, 'cap-override')) {
            if ($self->{factoids}->get_data($channel, $keyword, 'locked')) {
                $self->{pbot}->{logger}->log("Capability override set to " . $self->{factoids}->get_data($channel, $keyword, 'cap-override') . "\n");
                $stuff->{'cap-override'} = $self->{factoids}->get_data($channel, $keyword, 'cap-override');
            } else {
                $self->{pbot}->{logger}->log("Ignoring cap-override of " . $self->{factoids}->get_data($channel, $keyword, 'cap-override') . " on unlocked factoid\n");
            }
        }

        return $self->{pbot}->{interpreter}->interpret($stuff);
    }

    $self->{pbot}->{logger}
      ->log("(" . (defined $stuff->{from} ? $stuff->{from} : "(undef)") . "): $stuff->{nick}!$stuff->{user}\@$stuff->{host}: $trigger_name: action: \"$action\"\n");

    if ($self->{factoids}->get_data($channel, $keyword, 'enabled') == 0) {
        $self->{pbot}->{logger}->log("$trigger_name disabled.\n");
        return "/msg $stuff->{nick} ${ref_from}$trigger_name is currently disabled.";
    }

    unless ($self->{factoids}->exists($channel, $keyword, 'interpolate') and $self->{factoids}->get_data($channel, $keyword, 'interpolate') eq '0') {
        my ($root_channel, $root_keyword) =
          $self->find_factoid($stuff->{ref_from} ? $stuff->{ref_from} : $stuff->{from}, $stuff->{root_keyword}, arguments => $stuff->{arguments}, exact_channel => 1);
        if (not defined $root_channel or not defined $root_keyword) {
            $root_channel = $channel;
            $root_keyword = $keyword;
        }
        if (not length $stuff->{keyword_override} and length $self->{factoids}->get_data($root_channel, $root_keyword, 'keyword_override')) {
            $stuff->{keyword_override} = $self->{factoids}->get_data($root_channel, $root_keyword, 'keyword_override');
        }
        $stuff->{action} = $action;
        $action = $self->expand_factoid_vars($stuff);

        if   ($self->{factoids}->get_data($channel, $keyword, 'allow_empty_args')) { $action = $self->expand_action_arguments($action, $stuff->{arguments}, ''); }
        else                                                                       { $action = $self->expand_action_arguments($action, $stuff->{arguments}, $stuff->{nick}); }
    }

    return $action if $stuff->{special} eq 'code-factoid';

    if ($self->{factoids}->get_data($channel, $keyword, 'type') eq 'module') {
        my $preserve_whitespace = $self->{factoids}->get_data($channel, $keyword, 'preserve_whitespace');
        $preserve_whitespace = 0 if not defined $preserve_whitespace;

        $stuff->{preserve_whitespace} = $preserve_whitespace;
        $stuff->{root_keyword}        = $keyword unless defined $stuff->{root_keyword};
        $stuff->{root_channel}        = $channel;

        my $result = $self->{pbot}->{modules}->execute_module($stuff);
        if   (length $result) { return $ref_from . $result; }
        else                  { return ""; }
    } elsif ($self->{factoids}->get_data($channel, $keyword, 'type') eq 'text') {
        # Don't allow user-custom /msg factoids, unless factoid triggered by admin
        if ($action =~ m/^\/msg/i) {
            my $admin = $self->{pbot}->{users}->loggedin_admin($stuff->{from}, "$stuff->{nick}!$stuff->{user}\@$stuff->{host}");
            if (not $admin) {
                $self->{pbot}->{logger}->log("[ABUSE] Bad factoid (contains /msg): $action\n");
                return "You must be an admin to use /msg in a factoid.";
            }
        }

        if ($ref_from) {
            if ($action =~ s/^\/say\s+/$ref_from/i || $action =~ s/^\/me\s+(.*)/\/me $1 $ref_from/i || $action =~ s/^\/msg\s+([^ ]+)/\/msg $1 $ref_from/i) { return $action; }
            else { return $ref_from . "$trigger_name is $action"; }
        } else {
            if   ($action =~ m/^\/(?:say|me|msg)/i) { return $action; }
            else                                    { return "/say $trigger_name is $action"; }
        }
    } elsif ($self->{factoids}->get_data($channel, $keyword, 'type') eq 'regex') {
        my $result = eval {
            my $string = "$stuff->{original_keyword}" . (defined $stuff->{arguments} ? " $stuff->{arguments}" : "");
            my $cmd;
            if ($string =~ m/$keyword/i) {
                $self->{pbot}->{logger}->log("[$string] matches [$keyword] - calling [" . $action . "$']\n");
                $cmd = $action . $';
                my ($a, $b, $c, $d, $e, $f, $g, $h, $i, $before, $after) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $`, $');
                $cmd =~ s/\$1/$a/g;
                $cmd =~ s/\$2/$b/g;
                $cmd =~ s/\$3/$c/g;
                $cmd =~ s/\$4/$d/g;
                $cmd =~ s/\$5/$e/g;
                $cmd =~ s/\$6/$f/g;
                $cmd =~ s/\$7/$g/g;
                $cmd =~ s/\$8/$h/g;
                $cmd =~ s/\$9/$i/g;
                $cmd =~ s/\$`/$before/g;
                $cmd =~ s/\$'/$after/g;
                $cmd =~ s/^\s+//;
                $cmd =~ s/\s+$//;
            } else {
                $cmd = $action;
            }

            $stuff->{command} = $cmd;
            return $self->{pbot}->{interpreter}->interpret($stuff);
        };

        if ($@) {
            $self->{pbot}->{logger}->log("Regex fail: $@\n");
            return "";
        }

        if   (length $result) { return $ref_from . $result; }
        else                  { return ""; }
    } else {
        $self->{pbot}->{logger}->log("($stuff->{from}): $stuff->{nick}!$stuff->{user}\@$stuff->{host}): Unknown command type for '$trigger_name'\n");
        return "/me blinks." . " $ref_from";
    }
}

1;
