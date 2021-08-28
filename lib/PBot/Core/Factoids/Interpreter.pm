# File: Interpreter.pm
#
# Purpose: Provides functionality for factoids.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Factoids::Interpreter;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Time::HiRes qw(gettimeofday);
use Time::Duration qw(duration);

sub initialize {}

# main entry point for PBot::Core::Interpreter to interpret a factoid command
sub interpreter {
    my ($self, $context) = @_;

    # trace context and context's contents
    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("Factoids::interpreter\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    if (not length $context->{keyword}) {
        $self->{pbot}->{logger}->log("Factoids: interpreter: no keyword.\n");
        return;
    }

    if ($context->{interpret_depth} > $self->{pbot}->{registry}->get_value('interpreter', 'max_recursion')) {
        $self->{pbot}->{logger}->log("Factoids: interpreter: max-recursion.\n");
        return;
    }

    my $strictnamespace = $self->{pbot}->{registry}->get_value($context->{from}, 'strictnamespace');

    $strictnamespace //= $self->{pbot}->{registry}->get_value('general', 'strictnamespace');

    # search for factoid against global channel and current channel (from unless ref_from is defined)
    my $original_keyword = $context->{keyword};

    my ($channel, $keyword) =
      $self->{pbot}->{factoids}->{data}->find(
          $context->{ref_from} ? $context->{ref_from} : $context->{from},
          $context->{keyword},
          arguments     => $context->{arguments},
          exact_channel => 1,
      );

    # determine if we prepend [channel] to factoid output
    if (not defined $context->{ref_from}
            or $context->{ref_from} eq '.*'
            or $context->{ref_from} eq $context->{from})
    {
        $context->{ref_from} = '';
    }

    if (defined $channel and not $channel eq '.*'
            and not $channel eq lc $context->{from})
    {
        $context->{ref_from} = $channel;
    }

    # factoid > nick redirection
    my $nick_regex = $self->{pbot}->{registry}->get_value('regex', 'nickname');

    if ($context->{arguments} =~ s/> ($nick_regex)$//) {
        my $rcpt = $1;
        if ($self->{pbot}->{nicklist}->is_present($context->{from}, $rcpt)) {
            $context->{nickprefix} = $rcpt;
            $context->{nickprefix_forced} = 1;
        } else {
            $context->{arguments} .= "> $rcpt";
        }
    }

    # if no match found, attempt to call factoid from another channel if it exists there
    if (not defined $keyword) {
        my $string = "$original_keyword $context->{arguments}";

        my @chanlist = ();
        my ($fwd_chan, $fwd_trig);

        unless ($strictnamespace) {
            # build list of which channels contain the keyword, keeping track of the last one and count
            foreach my $factoid ($self->{pbot}->{factoids}->{data}->{storage}->get_all("index2 = $original_keyword", 'index1', 'type')) {
                next if $factoid->{type} ne 'text' and $factoid->{type} ne 'module';
                push @chanlist, $self->{pbot}->{factoids}->{data}->{storage}->get_data($factoid->{index1}, '_name');
                $fwd_chan = $factoid->{index1};
                $fwd_trig = $original_keyword;
            }
        }

        my $ref_from = $context->{ref_from} ? "[$context->{ref_from}] " : '';

        # if multiple channels have this keyword, then ask user to disambiguate
        if (@chanlist> 1) {
            return if $context->{embedded};
            return $ref_from . "Factoid `$original_keyword` exists in " . join(', ', @chanlist) . "; use `fact <channel> $original_keyword` to choose one.";
        }

        # if there's just one other channel that has this keyword, trigger that instance
        elsif (@chanlist == 1) {
            $self->{pbot}->{logger}->log("Found '$original_keyword' as '$fwd_trig' in [$fwd_chan]\n");
            $context->{keyword} = $fwd_trig;
            $context->{interpret_depth}++;
            $context->{ref_from} = $fwd_chan;
            return $self->interpreter($context);
        }

        # otherwise keyword hasn't been found, display similiar matches for all channels
        else {
            my $namespace = $context->{from};
            $namespace = '.*' if $namespace !~ /^#/;

            my $namespace_regex = $namespace;
            if ($strictnamespace) { $namespace_regex = "(?:" . (quotemeta $namespace) . '|\\.\\*)'; }

            $context->{arguments} = quotemeta($original_keyword) . " -channel $namespace_regex";
            my $matches = $self->{pbot}->{commands}->{modules}->{Factoids}->cmd_factfind($context);

            # found factfind matches
            if ($matches !~ m/^No factoids/) {
                return if $context->{embedded};
                return "No such factoid '$original_keyword'; $matches";
            }

            # otherwise find levenshtein closest matches
            $matches = $self->{pbot}->{factoids}->{data}->{storage}->levenshtein_matches($namespace, lc $original_keyword, 0.50, $strictnamespace);

            # if a non-nick argument was supplied, e.g., a sentence using the bot's nick, /msg the error to the caller
            if (length $context->{arguments} and not $self->{pbot}->{nicklist}->is_present($context->{from}, $context->{arguments})) {
                $context->{send_msg_to_caller} = 1;
            }

            # /msg the caller if nothing similiar was found
            $context->{send_msg_to_caller} = 1 if $matches eq 'none';
            $context->{send_msg_to_caller} = 1 if $context->{embedded};

            my $msg_caller = '';
            $msg_caller = "/msg $context->{nick} " if $context->{send_msg_to_caller};

            my $ref_from = $context->{ref_from} ? "[$context->{ref_from}] " : '';

            if ($matches eq 'none') {
                return $msg_caller . $ref_from . "No such factoid '$original_keyword'; no similar matches.";
            } else {
                return $msg_caller . $ref_from . "No such factoid '$original_keyword'; did you mean $matches?";
            }
        }
    }

    my $channel_name = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, '_name');
    my $trigger_name = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, '_name');

    $channel_name = 'global'            if $channel_name eq '.*';
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    $context->{keyword}          = $keyword;
    $context->{trigger}          = $keyword;
    $context->{channel}          = $channel;
    $context->{original_keyword} = $original_keyword;
    $context->{channel_name}     = $channel_name;
    $context->{trigger_name}     = $trigger_name;

    if ($context->{embedded} and $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'noembed')) {
        $self->{pbot}->{logger}->log("Factoids: interpreter: ignoring $channel.$keyword due to noembed.\n");
        return;
    }

    if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'locked_to_channel')) {
        if ($context->{ref_from} ne '') { # called from another channel
            return "$trigger_name may be invoked only in $context->{ref_from}.";
        }
    }

    # rate-limiting
    if ($context->{interpret_depth} <= 1
            and $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'last_referenced_in') eq $context->{from})
    {
        my $ratelimit = $self->{pbot}->{registry}->get_value($context->{from}, 'ratelimit_override');

        $ratelimit //= $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'rate_limit');

        if (gettimeofday - $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'last_referenced_on') < $ratelimit) {
            my $ref_from = $context->{ref_from} ? "[$context->{ref_from}] " : '';

            unless ($self->{pbot}->{users}->loggedin_admin($channel, "$context->{nick}!$context->{user}\@$context->{host}")) {
                return "/msg $context->{nick} $ref_from'$trigger_name' is rate-limited; try again in "
                  . duration($ratelimit - int(gettimeofday - $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'last_referenced_on'))) . "."
            }
        }
    }

    # update factoid reference-related metadata
    my $ref_count = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'ref_count');

    my $update_data = {
        ref_count          => ++$ref_count,
        ref_user           => "$context->{nick}!$context->{user}\@$context->{host}",
        last_referenced_on => scalar gettimeofday,
        last_referenced_in => $context->{from} || 'stdin',
    };

    $self->{pbot}->{factoids}->{data}->{storage}->add($channel, $keyword, $update_data, 1);

    # show usage if usage metadata exists and context has no arguments
    if ($self->{pbot}->{factoids}->{data}->{storage}->exists($channel, $keyword, 'usage')
            and not length $context->{arguments})
    {
        my $usage = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'usage');
        $usage =~ s/(?<!\\)\$0|(?<!\\)\$\{0\}/$trigger_name/g;
        $context->{alldone} = 1;
        return $usage;
    }

    # tell PBot::Core::Interpreter to prepend caller's nick to output
    if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'add_nick')) {
        $context->{add_nick} = 1;
    }

    # factoid action
    my $action;

    # action_with_args or regular action?
    if (length $context->{arguments} and $self->{pbot}->{factoids}->{data}->{storage}->exists($channel, $keyword, 'action_with_args')) {
        $action = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'action_with_args');
    } else {
        $action = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'action');
    }

    # action is a code factoid
    if ($action =~ m{^/code\s+([^\s]+)\s+(.+)$}msi) {
        my ($lang, $code) = ($1, $2);
        $context->{lang} = $lang;
        $context->{code} = $code;
        $self->{pbot}->{factoids}->{code}->execute($context);
        return '';
    }

    # fork factoid if background-process is enabled
    if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'background-process')) {
        my $timeout = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'process-timeout');

        $timeout //= $self->{pbot}->{registry}->get_value('processmanager', 'default_timeout');

        $self->{pbot}->{process_manager}->execute_process(
            $context,
            sub { $context->{result} = $self->handle_action($context, $action); },
            $timeout,
        );

        return '';
    } else {
        return $self->handle_action($context, $action);
    }
}

sub handle_action {
    my ($self, $context, $action) = @_;

    # trace context and context's contents
    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("Factoids::handle_action [$action]\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    if (not length $action) {
        $self->{pbot}->{logger}->log("Factoids: handle_action: no action.\n");
        return '';
    }

    my ($channel, $keyword) = ($context->{channel}, $context->{trigger});

    my ($channel_name, $trigger_name) = ($context->{channel_name}, $context->{trigger_name});

    my $ref_from = '';

    unless ($context->{pipe} or $context->{subcmd}) {
        $ref_from = $context->{ref_from} ? "[$context->{ref_from}] " : '';
    }

    my $interpolate = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'interpolate');

    if (defined $interpolate and not $interpolate) {
        $context->{interpolate} = 0;
    } else {
        $context->{interpolate} = 1;
    }

    if ($context->{interpolate}) {
        my ($root_channel, $root_keyword) = $self->{pbot}->{factoids}->{data}->find(
            $context->{ref_from} ? $context->{ref_from} : $context->{from},
            $context->{root_keyword},
            arguments     => $context->{arguments},
            exact_channel => 1,
        );

        if (not defined $root_channel or not defined $root_keyword) {
            $root_channel = $channel;
            $root_keyword = $keyword;
        }

        if (not length $context->{keyword_override}
                and length $self->{pbot}->{factoids}->{data}->{storage}->get_data($root_channel, $root_keyword, 'keyword_override'))
        {
            $context->{keyword_override} = $self->{pbot}->{factoids}->{data}->{storage}->get_data($root_channel, $root_keyword, 'keyword_override');
        }

        $action = $self->{pbot}->{factoids}->{variables}->expand_factoid_vars($context, $action);
    }

    # handle arguments
    if (length $context->{arguments}) {
        # arguments supplied
        if ($action =~ m/\$\{?args/ or $action =~ m/\$\{?arg\[/) {
            # factoid has $args, replace them
            if ($context->{interpolate}) {
                $action = $self->{pbot}->{factoids}->{variables}->expand_action_arguments($action, $context->{arguments}, $context->{nick});
            }

            $context->{arguments}          = '';
            $context->{original_arguments} = '';
        } else {
            # set nickprefix if args is a present nick and factoid action doesn't have $nick
            if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'type') eq 'text') {
                my $target = $self->{pbot}->{nicklist}->is_present_similar($context->{from}, $context->{arguments});

                if ($target and $action !~ /\$\{?nick\b/) {
                    $context->{nickprefix}          = $target unless $context->{nickprefix_forced};
                    $context->{nickprefix_disabled} = 0;
                }
            }
        }
    } else {
        # no arguments supplied
        if ($self->{pbot}->{factoids}->{data}->{storage}->exists($channel, $keyword, 'usage')) {
            # factoid has a usage message, show it
            $action = "/say " . $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'usage');
            $action =~ s/(?<!\\)\$0|(?<!\\)\$\{0\}/$trigger_name/g;
            $context->{alldone} = 1;
        } else {
            if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'allow_empty_args')) {
                $action = $self->{pbot}->{factoids}->{variables}->expand_action_arguments($action, undef, '');
            } else {
                $action = $self->{pbot}->{factoids}->{variables}->expand_action_arguments($action, undef, $context->{nick});
            }
        }

        $context->{nickprefix_disabled} = 0;
    }

    # Check if it's an alias
    if ($action =~ /^\/call\s+(.*)$/msi) {
        my $command = $1;
        $command =~ s/\n$//;

        unless ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'require_explicit_args')) {
            my $args = $context->{arguments};
            $command .= " $args" if length $args and not $context->{special} eq 'code-factoid';
            $context->{arguments} = '';
        }

        unless ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'no_keyword_override')) {
            if ($command =~ s/\s*--keyword-override=([^ ]+)\s*//) { $context->{keyword_override} = $1; }
        }

        $context->{command} = $command;
        $context->{aliased} = 1;

        $self->{pbot}->{logger}->log("$context->{from}: $context->{nick}!$context->{user}\@$context->{host}: $trigger_name aliased to: $command\n");

        if (defined $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'cap-override')) {
            if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'locked')) {
                $self->{pbot}->{logger}->log("Capability override set to " . $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'cap-override') . "\n");
                $context->{'cap-override'} = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'cap-override');
            } else {
                $self->{pbot}->{logger}->log("Ignoring cap-override of " . $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'cap-override') . " on unlocked factoid\n");
            }
        }

        return $self->{pbot}->{interpreter}->interpret($context);
    }

    $self->{pbot}->{logger}->log("$context->{from}: $context->{nick}!$context->{user}\@$context->{host}: $trigger_name: action: \"$action\"\n");

    my $enabled = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'enabled');

    if (defined $enabled and $enabled == 0) {
        $self->{pbot}->{logger}->log("$trigger_name disabled.\n");
        return "/msg $context->{nick} ${ref_from}$trigger_name is disabled.";
    }

    if ($context->{interpolate}) {
        my ($root_channel, $root_keyword) = $self->{pbot}->{factoids}->{data}->find(
            $context->{ref_from} ? $context->{ref_from} : $context->{from},
            $context->{root_keyword},
            arguments     => $context->{arguments},
            exact_channel => 1,
        );

        if (not defined $root_channel or not defined $root_keyword) {
            $root_channel = $channel;
            $root_keyword = $keyword;
        }

        if (not length $context->{keyword_override}
                and length $self->{pbot}->{factoids}->{data}->{storage}->get_data($root_channel, $root_keyword, 'keyword_override'))
        {
            $context->{keyword_override} = $self->{pbot}->{factoids}->{data}->{storage}->get_data($root_channel, $root_keyword, 'keyword_override');
        }

        $action = $self->{pbot}->{factoids}->{variables}->expand_factoid_vars($context, $action);

        if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'allow_empty_args')) {
            $action = $self->{pbot}->{factoids}->{variables}->expand_action_arguments($action, $context->{arguments}, '');
        } else {
            $action = $self->{pbot}->{factoids}->{variables}->expand_action_arguments($action, $context->{arguments}, $context->{nick});
        }
    }

    my $preserve_whitespace = $self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'preserve_whitespace');

    if (defined $preserve_whitespace) {
        $context->{preserve_whitespace} = $preserve_whitespace;
    }

    return $action if $context->{special} eq 'code-factoid';

    if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'type') eq 'module') {
        $context->{root_keyword} = $keyword unless defined $context->{root_keyword};
        $context->{root_channel} = $channel;

        my $result = $self->{pbot}->{modules}->execute_module($context);

        if (length $result) {
            return $ref_from . $result;
        } else {
            return '';
        }
    }
    elsif ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'type') eq 'text') {
        # Don't allow user-custom /msg factoids, unless invoked by admin
        if ($action =~ m/^\/msg/i) {
            if (not $self->{pbot}->{users}->loggedin_admin($context->{from}, $context->{hostmask})) {
                $self->{pbot}->{logger}->log("[ABUSE] Bad factoid (starts with /msg): $action\n");
                return "You must be an admin to use /msg.";
            }
        }

        if ($ref_from) {
            if (   $action =~ s/^\/say\s+/$ref_from/i
                || $action =~ s/^\/me\s+(.*)/\/me $1 $ref_from/i
                || $action =~ s/^\/msg\s+([^ ]+)/\/msg $1 $ref_from/i
            ) {
                return $action;
            } else {
                return $ref_from . "$trigger_name is $action";
            }
        } else {
            if ($action =~ m/^\/(?:say|me|msg)/i) {
                return $action;
            } else {
                return "/say $trigger_name is $action";
            }
        }
    }
    elsif ($self->{pbot}->{factoids}->{data}->{storage}->get_data($channel, $keyword, 'type') eq 'regex') {
        my $result = eval {
            my $string = "$context->{original_keyword}" . (length $context->{arguments} ? " $context->{arguments}" : '');
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

            $context->{command} = $cmd;
            return $self->{pbot}->{interpreter}->interpret($context);
        };

        if ($@) {
            $self->{pbot}->{logger}->log("Factoids: bad regex: $@\n");
            return '';
        }

        if (length $result) {
            return $ref_from . $result;
        } else {
            return '';
        }
    } else {
        $self->{pbot}->{logger}->log("$context->{from}: $context->{nick}!$context->{user}\@$context->{host}): bad type for $channel.$keyword\n");
        return "/me blinks. $ref_from";
    }
}

1;
