# File: Interpreter.pm
#
# Purpose: Main entry point to parse and interpret a string into bot
# commands and dispatch the commands to registered interpreters.
# Handles argument processing, command piping, command substitution,
# command splitting, command output processing such as truncating long
# text to web paste sites, etc.

# SPDX-FileCopyrightText: 2001-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Interpreter;
use parent 'PBot::Core::Class', 'PBot::Core::Registerable';

use PBot::Imports;

use PBot::Core::MessageHistory::Constants ':all';
use PBot::Core::Utils::Indefinite;
use PBot::Core::Utils::ValidateString;

use Encode;
use Getopt::Long qw(GetOptionsFromArray);
use Time::Duration;
use Time::HiRes  qw(gettimeofday);
use Unicode::Truncate;

sub initialize($self, %conf) {
    # PBot::Core::Interpreter can register multiple interpreter subrefs.
    # See also: Commands::interpreter() and Factoids::interpreter()
    $self->PBot::Core::Registerable::initialize(%conf);

    # registry entry for maximum recursion depth
    $self->{pbot}->{registry}->add_default('text', 'interpreter', 'max_recursion', 10);
}

# this is the main entry point for a message to be parsed into commands
# and to execute those commands and process their output
sub process_line($self, $from, $nick, $user, $host, $text, $tags = '', $is_command = 0) {
    # lowercase `from` field for case-insensitivity
    $from = lc $from;

    # sanitize text a bit
    $text =~ s/^\s+|\s+$//g;
    $text = validate_string($text, 0);

    # context object maintains contextual information about the state and
    # processing of this message. this object is passed between various bot
    # functions and interfaces, which may themselves add more fields.
    my $context = {
        from     => $from,                 # source (channel, sender hostmask, 'stdin@pbot', etc)
        nick     => $nick,                 # nickname
        user     => $user,                 # username
        host     => $host,                 # hostname/ip address
        hostmask => "$nick!$user\@$host",  # full hostmask
        text     => $text,                 # message contents
        tags     => $tags,                 # message tags
    };

    # add hostmask to user/message tracking database and get their account id
    my $message_account = $self->{pbot}->{messagehistory}->get_message_account($nick, $user, $host);

    # add account id to context object
    $context->{message_account} = $message_account;

    # add message to message history as a chat message
    $self->{pbot}->{messagehistory}->add_message($message_account, $context->{hostmask}, $from, $text, MSG_CHAT);

    # look up channel-specific flood threshold settings from registry
    my $flood_threshold      = $self->{pbot}->{registry}->get_value($from, 'chat_flood_threshold');
    my $flood_time_threshold = $self->{pbot}->{registry}->get_value($from, 'chat_flood_time_threshold');

    # get general flood threshold settings if there are no channel-specific settings
    $flood_threshold       //= $self->{pbot}->{registry}->get_value('antiflood', 'chat_flood_threshold');
    $flood_time_threshold  //= $self->{pbot}->{registry}->get_value('antiflood', 'chat_flood_time_threshold');

    # perform anti-flood processing on this message
    $self->{pbot}->{antiflood}->check_flood(
        $from, $nick, $user, $host, $text,
        $flood_threshold, $flood_time_threshold,
        MSG_CHAT,
        $context
    );

    # get bot nickname
    my $botnick = $self->{pbot}->{conn}->nick;

    # get channel-specific bot trigger if available
    my $bot_trigger = $self->{pbot}->{registry}->get_value($from, 'trigger');

    # otherwise get general bot trigger
    $bot_trigger //= $self->{pbot}->{registry}->get_value('general', 'trigger');

    # get nick regex from registry entry
    my $nick_regex = $self->{pbot}->{registry}->get_value('regex', 'nickname');

    # preserve original text and parse $cmd_text for bot commands
    my $cmd_text = $text;
    $cmd_text =~ s/^\/me\s+//;  # remove leading /me

    # parse for bot command invocation
    my @commands;       # all commands parsed out of this text so far
    my $command;        # current command being parsed
    my $embedded = 0;   # was command embedded within a message, e.g.: "see the !{help xyz} about that"

    my $nick_prefix = undef;  # addressed nickname for prefixing output
    my $processed   = 0;      # counts how many commands were successfully processed

    # check if we should treat this entire text as a command
    # (i.e., it came from /msg or was otherwise flagged as a command)
    if ($is_command) {
        $command = $cmd_text;
        $command =~ s/^$bot_trigger//; # strip leading bot trigger, if any

        # restore command if stripping bot trigger makes command empty
        # (they wanted to invoke a command named after the trigger itself)
        # TODO: this could potentially be confusing when trying to invoke
        # commands that are sequential instances of the bot trigger, e.g.
        # attempting to invoke a factoid named `...` while the bot trigger
        # is `.` could now prove confusing via /msg or stdin. Might need
        # to rethink this and just require bot trigger all the time ...
        # but for now let's see how this goes and if people can figure it
        # out with minimal confusion.
        $command = $cmd_text if not length $command;
        $context->{addressed} = 1;
        goto CHECK_EMBEDDED_CMD;
    }

    # otherwise try to parse any potential commands
    if ($cmd_text =~ m/^\s*($nick_regex)[,:]?\s+$bot_trigger\{\s*(.+?)\s*\}\s*$/) {
        # "somenick: !{command}"
        $context->{addressed} = 1; # command explicitly invoked (output disambig/errors)
        goto CHECK_EMBEDDED_CMD;
    } elsif ($cmd_text =~ m/^\s*$bot_trigger\{\s*(.+?)\s*\}\s*$/) {
        # "!{command}"
        $context->{addressed} = 1;
        goto CHECK_EMBEDDED_CMD;
    } elsif ($cmd_text =~ m/^\s*($nick_regex)[,:]\s+$bot_trigger\s*(.+)$/) {
        # "somenick: !command"
        my $possible_nick_prefix = $1;
        $command = $2;

        # does somenick or similar exist in channel?
        my $recipient = $self->{pbot}->{nicklist}->is_present_similar($from, $possible_nick_prefix);

        if ($recipient) {
            $nick_prefix = $recipient;
        } else {
            # disregard command if no such nick is present.
            $self->{pbot}->{logger}->log("No similar nick for $possible_nick_prefix; disregarding command.\n");
            return 0;
        }
        $context->{addressed} = 1; # command explicitly invoked
    } elsif ($cmd_text =~ m/^$bot_trigger\s*(.+)$/) {
        # "!command"
        $command = $1;
        $context->{addressed} = 1; # command explicitly invoked
    } elsif ($cmd_text =~ m/^.?\s*$botnick\s*[,:]\s+(.+)$/i) {
        # "botnick: command"
        $command = $1;
        $context->{addressed} = 1; # command explicitly invoked
    } elsif ($cmd_text =~ m/^.?\s*$botnick\s+(.+)$/i) {
        # "botnick command"
        $command = $1;
        $context->{addressed} = 0; # command NOT explicitly invoked (silence disambig/errors)
    } elsif ($cmd_text =~ m/^(.+?),\s+$botnick[?!.]*$/i) {
        # "command, botnick?"
        $command = $1;
        $context->{addressed} = 1; # command explicitly invoked
    } elsif ($cmd_text =~ m/^(.+?)\s+$botnick[?!.]*$/i) {
        # "command botnick?"
        $command = $1;
        $context->{addressed} = 0; # command NOT explicitly invoked
    }

    # check for embedded commands
  CHECK_EMBEDDED_CMD:

    # if no command was parsed yet (or if we reached this point by one of the gotos above)
    # then look for embedded commands, e.g.: "today is !{date} and the weather is !{weather}"
    if (not defined $command or $command =~ m/^\{.*\}/) {

        # check for an addressed nickname
        if ($cmd_text =~ s/^\s*($nick_regex)[,:]\s+//) {
            my $possible_nick_prefix = $1;

            # does somenick or similar exist in channel?
            my $recipient = $self->{pbot}->{nicklist}->is_present_similar($from, $possible_nick_prefix);

            if ($recipient) {
                $nick_prefix = $recipient;
            }
        }

        # get max embed registry value
        my $max_embed = $self->{pbot}->{registry}->get_value('interpreter', 'max_embed') // 3;

        # extract embedded commands
        for (my $count = 0; $count < $max_embed; $count++) {
            my ($extracted, $rest) = $self->extract_bracketed($cmd_text, '{', '}', $bot_trigger);

            # nothing to extract found, all done.
            last if not length $extracted;

            # move command text buffer forwards past extracted text
            $cmd_text = $rest;

            # trim surrounding whitespace
            $extracted =~ s/^\s+|\s+$//g;

            # add command to parsed commands.
            push @commands, $extracted;

            # set embedded flag
            $embedded = 1;
        }
    } else {
        # otherwise a single command has already been parsed.
        # so, add the command to parsed commands.
        push @commands, $command;
    }

    # set $context's command output recipient field
    if ($nick_prefix) {
        $context->{nickprefix}        = $nick_prefix;
        $context->{nickprefix_forced} = 1;
    }

    # set $context object's embedded flag
    $context->{embedded} = $embedded;

    # interpret all parsed commands
    foreach $command (@commands) {
        # check if user is ignored
        # the `login` command gets a pass on the ignore filter
        if ($command !~ /^login / and $self->{pbot}->{ignorelist}->is_ignored($from, "$nick!$user\@$host")) {
            $self->{pbot}->{logger}->log("Disregarding command from ignored user $nick!$user\@$host in $from.\n");
            return 1;
        }

        # update $context command field
        $context->{command} = $command;

        # reset $context's interpreter recursion depth counter
        $context->{interpret_depth} = 0;

        # interpet this command
        $context->{result} = $self->interpret($context);

        # handle command output
        $self->handle_result($context);

        # increment processed counter
        $processed++;

        # reset context
        delete $context->{cmdstack};
        delete $context->{outq};
        delete $context->{pipe};
        delete $context->{pipe_next};
        delete $context->{add_nick};
    }

    # return number of commands processed
    return $processed;
}

# main entry point to interpret/execute a bot command.
# takes a $context object containing contextual information about the
# command such as the channel, nick, user, host, command, etc.
sub interpret($self, $context) {
    # log command invocation
    $self->{pbot}->{logger}->log("=== [$context->{interpret_depth}] Got command: "
        . "($context->{from}) $context->{hostmask}: $context->{command}\n");

    # debug flag to trace $context location and contents
    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = sub { [sort grep { not /(?:cmdlist|arglist)/ } keys %$context] };
        $Data::Dumper::Indent = 2;
        $self->{pbot}->{logger}->log("Interpreter::interpret\n");
        $self->{pbot}->{logger}->log(Dumper $context);
        $Data::Dumper::Sortkeys = 1;
    }

    # enforce recursion limit
    if (++$context->{interpret_depth} > $self->{pbot}->{registry}->get_value('interpreter', 'max_recursion')) {
        return "Too many levels of recursion, aborted.";
    }

    # sanity check the context fields, none of these should be missing
    if (not defined $context->{nick} || not defined $context->{user} || not defined $context->{host} || not defined $context->{command}) {
        $self->{pbot}->{logger}->log("Error: Interpreter::interpret: missing field(s)\n");
        return '/me coughs weakly.'; # indicate that something went wrong
    }

    # check for a split command, e.g. "echo Hello ;;; echo world."
    if ($context->{command} =~ m/^(.*?)\s*(?<!\\);;;\s*(.*)/ms) {
        $context->{command} = $1;         # command is the first half of the split
        push @{$context->{cmdstack}}, $2; # store the rest of the split, potentially containing more splits
        push @{$context->{outq}}, [];     # add output queue to stack
    }

    # convert command string to list of arguments
    my $cmdlist = $self->make_args($context->{command}, preserve_escapes => 1);

    $context->{cmdlist} = $cmdlist;

    # create context command history if non-existent
    if (not exists $context->{commands}) {
        $context->{commands} = [];
    }

    # add command to context command history
    push @{$context->{commands}}, $context->{command};

    # parse the command into keyword, arguments and recipient
    my ($keyword, $arguments, $recipient) = ('', '', undef);

    if ($self->arglist_size($cmdlist) >= 4 and lc $cmdlist->[0] eq 'tell' and (lc $cmdlist->[2] eq 'about' or lc $cmdlist->[2] eq 'the')) {
        # tell nick about/the cmd [args]; e.g. "tell somenick about malloc" or "tell somenick the date"

        # split the list into two fields (keyword and remaining arguments)
        # starting at the 4th element and preserving quotes
        ($keyword, $arguments) = $self->split_args($cmdlist, 2, 3, 1);

        # 2nd element is the recipient
        $recipient = $cmdlist->[1];
    } elsif ($self->arglist_size($cmdlist) >= 3 and lc $cmdlist->[0] eq 'give') {
        # give nick cmd [args]; e.g. "give somenick date"

        # split the list into two fields (keyword and remaining arguments)
        # starting at the 3rd element and preserving quotes
        ($keyword, $arguments) = $self->split_args($cmdlist, 2, 2, 1);

        # 2nd element is the recipient
        $recipient = $cmdlist->[1];
    } else {
        # normal command, split into keywords and arguments while preserving quotes
        ($keyword, $arguments) = $self->split_args($cmdlist, 2, 0, 1);
    }

    # limit keyword length (in bytes)
    # TODO: make this a registry item
    {
        # lexical scope for use bytes
        use bytes;
        if (length $keyword > 128) {
            $keyword = truncate_egc $keyword, 128; # safely truncate unicode strings
            $self->{pbot}->{logger}->log("Truncating keyword to <= 128 bytes: $keyword\n");
        }
    }

    # strip any trailing newlines from keyword
    $keyword =~ s/\n+$//;

    # ensure we have a $keyword
    if (not defined $keyword or not length $keyword) {
        $self->{pbot}->{logger}->log("Error: Missing keyword; disregarding command\n");
        return undef;
    }

    # ensure $arguments is a string if none were given
    $arguments //= '';

    if (defined $recipient) {
        # ensure that the recipient is present in the channel
        $recipient = $self->{pbot}->{nicklist}->is_present_similar($context->{from}, $recipient);

        if ($recipient) {
            # if present then set and force the nickprefix
            $context->{nickprefix}        = $recipient;
            $context->{nickprefix_forced} = 1;
        } else {
            # otherwise discard nickprefix
            delete $context->{nickprefix};
            delete $context->{nickprefix_forced};
        }
    }

    # find factoid channel for dont-replace-pronouns metadata
    my ($fact_channel, $fact_trigger);
    my @factoids = $self->{pbot}->{factoids}->{data}->find($context->{from}, $keyword, exact_trigger => 1);

    if (@factoids == 1) {
        # found the factoid's channel
        ($fact_channel, $fact_trigger) = @{$factoids[0]};
    } else {
        # match the factoid in the current channel if it exists
        foreach my $f (@factoids) {
            if ($f->[0] eq $context->{from}) {
                ($fact_channel, $fact_trigger) = ($f->[0], $f->[1]);
                last;
            }
        }

        # and otherwise assume global if it doesn't exist (FIXME: what to do if there isn't a global one?)
        if (not defined $fact_channel) {
            ($fact_channel, $fact_trigger) = ('.*', $keyword);
        }
    }

    if ($self->{pbot}->{commands}->get_meta($keyword, 'suppress-no-output')
            or $self->{pbot}->{factoids}->{data}->get_meta($fact_channel, $fact_trigger, 'suppress-no-output'))
    {
        $context->{'suppress_no_output'} = 1;
    } else {
        delete $context->{'suppress_no_output'};
    }

    if ($self->{pbot}->{commands}->get_meta($keyword, 'dont-replace-pronouns')
            or $self->{pbot}->{factoids}->{data}->get_meta($fact_channel, $fact_trigger, 'dont-replace-pronouns'))
    {
        $context->{'dont-replace-pronouns'} = 1;
    }

    # replace pronouns like "i", "my", etc, with "nick", "nick's", etc
    if (not $context->{'dont-replace-pronouns'}) {
        # if command recipient is "me" then replace it with invoker's nick
        # e.g., "!tell me about date" or "!give me date", etc
        if (defined $context->{nickprefix} and lc $context->{nickprefix} eq 'me') {
            $context->{nickprefix} = $context->{nick};
        }

        # strip trailing sentence-ending punctuators from $keyword
        # TODO: why are we doing this? why here? why at all?
        $keyword =~ s/(\w+)[?!.]+$/$1/;

        # replace pronouns in $arguments.
        # but only on the top-level command (not on subsequent recursions).
        # all pronouns can be escaped to prevent replacement, e.g. "!give \me date"
        if (length $arguments and $context->{interpret_depth} <= 1) {
            $arguments =~ s/(?<![\w\/\-\\])i am\b/$context->{nick} is/gi;
            $arguments =~ s/(?<![\w\/\-\\])me\b/$context->{nick}/gi;
            $arguments =~ s/(?<![\w\/\-\\])my\b/$context->{nick}'s/gi;

            # unescape any escaped pronouns
            $arguments =~ s/\\i am\b/i am/gi;
            $arguments =~ s/\\my\b/my/gi;
            $arguments =~ s/\\me\b/me/gi;
        }
    }

    # parse out a substituted command
    if ($arguments =~ m/(?<!\\)&\s*\{/) {
        my ($command) = $self->extract_bracketed($arguments, '{', '}', '&', 1);

        # did we find a substituted command?
        if (length $command) {
            # replace it with a placeholder
            $arguments =~ s/&\s*\{\Q$command\E\}/&{subcmd}/;

            # add it to the command stack
            push @{$context->{cmdstack}}, "$keyword $arguments";

            # add output queue to stack
            push @{$context->{outq}}, [];

            # FIXME: quick-and-dirty hack to fix $0.
            # Without this hack `pet &{echo dog}` will output `You echo
            # the dog` instead of `You pet the dog`.
            if (not defined $context->{root_keyword}) {
                $context->{root_keyword} = $keyword;
            }

            # trim surrounding whitespace
            $command =~ s/^\s+|\s+$//g;

            # replace contextual command
            $context->{command} = $command;

            # interpret the substituted command
            $context->{result} = $self->interpret($context);

            # return the output
            return $context->{result};
        }
    }

    # parse out a pipe
    if ($arguments =~ m/(?<!\\)\|\s*\{\s*[^}]+\}\s*$/) {
        my ($pipe, $rest) = $self->extract_bracketed($arguments, '{', '}', '|', 1);

        # strip pipe and everything after it from arguments
        $arguments =~ s/\s*(?<!\\)\|\s*{(\Q$pipe\E)}.*$//s;

        # trim surrounding whitespace
        $pipe =~ s/^\s+|\s+$//g;

        # update contextual pipe data
        if (exists $context->{pipe}) {
            $context->{pipe_rest} = "$rest | { $context->{pipe} }$context->{pipe_rest}";
        } else {
            $context->{pipe_rest} = $rest;
        }

        $context->{pipe} = $pipe;
    }

    # unescape any escaped command splits
    $arguments =~ s/\\;;;/;;;/g;

    # unescape any escaped substituted commands
    $arguments =~ s/\\&\s*\{/&{/g;

    # unescape any escaped pipes
    $arguments =~ s/\\\|\s*\{/| {/g;

    # the bot doesn't like performing bot commands on itself
    # unless dont-protect-self is true
    if (not $self->{pbot}->{commands}->get_meta($keyword, 'dont-protect-self')
            and not $self->{pbot}->{factoids}->{data}->get_meta($fact_channel, $fact_trigger, 'dont-protect-self'))
    {
        my $botnick = $self->{pbot}->{conn}->nick;

        if ($arguments =~ m/^(your|him|her|its|it|them|their)(self|selves)$/i || $arguments =~ m/^$botnick$/i) {
            # build message structure
            my $message = {
                nick       => $context->{nick},
                user       => $context->{user},
                host       => $context->{host},
                hostmask   => $context->{hostmask},
                command    => $context->{command},
                checkflood => 1,
                message    => "$context->{nick}: Why would I want to do that to myself?",
            };

            # get a random delay
            my $delay = rand(10) + 5;

            # add message to output queue
            $self->add_message_to_output_queue($context->{from}, $message, $delay);

            # log upcoming message + delay
            $delay = duration($delay);
            $self->{pbot}->{logger}->log("($delay delay) $message->{message}\n");

            # end pipe/substitution processing
            $context->{alldone} = 1;

            # no output to return
            return undef;
        }
    }

    # set the contextual root root keyword.
    # this is the keyword first used to invoke this command. it is not updated
    # on subsequent command interpreter recursions.
    if (not exists $context->{root_keyword}) {
        $context->{root_keyword} = $keyword;
    }

    # update the contextual keyword field
    $context->{keyword} = $keyword;

    # update the contextual arguments field
    $context->{arguments} = $arguments;

    # update the original arguments field.
    # the actual arguments field may be manipulated/overridden by
    # the interpreters. the arguments field is reset with this
    # field after each interpreter finishes.
    $context->{original_arguments} = $arguments;

    # make the argument list
    $context->{arglist} = $self->make_args($arguments);

    # reset utf8 flag for arguments
    # arguments aren't a utf8 encoded string at this point
    delete $context->{args_utf8};

    # reset the special behavior
    $context->{special} = '';

    # execute all registered interpreters
    my $result;

    foreach my $func (@{$self->{handlers}}) {
        # call the interpreter
        $result = $func->{subref}->($context);

        # exit loop if interpreter returned output
        last if $context->{interpreted} || defined $result;

        # reset any manipulated/overridden arguments
        $context->{arguments} = $context->{original_arguments};
        delete $context->{args_utf8};
    }

    # return command output
    return $result;
}

# finalizes processing on a command.
# updates pipes, substitutions, splits. truncates to paste site.
# sends final command output to appropriate queues.
# use context result if no result argument given.
sub handle_result($self, $context, $result = $context->{result}) {
    # condensation of consecutive whitespace is disabled by default
    $context->{'condense-whitespace'} //= 0;

    # reset interpreted to allow pipes/command-substitutions to finish
    delete $context->{'interpreted'};

    # debug flag to trace $context location and contents
    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = sub { [sort grep { not /(?:cmdlist|arglist)/ } keys %$context] };
        $Data::Dumper::Indent = 2;
        $self->{pbot}->{logger}->log("Interpreter::handle_result [$result]\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    # ensure we have a command result to work with
    if (!defined $result || $context->{'skip-handle-result'}) {
        $self->{pbot}->{logger}->log("Skipping handle_result\n");
        delete $context->{'skip-handle-result'};
        return;
    }

    # strip and store /command prefixes
    # to be re-added after result processing
    if ($result =~ s!^(/say|/me|/msg \S+) !!) {
        $context->{result_prefix} = $1;
    } else {
        delete $context->{result_prefix};
    }

    # finish piping
    if (exists $context->{pipe}) {
        my ($pipe, $pipe_rest) = (
            delete $context->{pipe},
            delete $context->{pipe_rest}
        );

        if (not $context->{alldone}) {
            $context->{command} = "$pipe $result $pipe_rest";
            $context->{result}  = $self->interpret($context);
        }

        $self->handle_result($context);
        return 0;
    }

    # process next command in stack
    if (exists $context->{cmdstack}) {
        my $command = pop @{$context->{cmdstack}};

        if (@{$context->{cmdstack}} == 0 or $context->{alldone}) {
            delete $context->{cmdstack};
        }

        if ($command =~ m/&\{subcmd\}/) {
            # finish command substitution
            my $output = pop @{$context->{outq}};
            $output = join " ", @$output;

            if (length $output) {
                $result = "$output $result";
            }

            if ($command =~ s/\b(an?)(\s+)&\{subcmd\}/&{subcmd}/i) {
                # fix-up a/an article
                my ($article, $spaces) = ($1, $2);
                my $fixed_article = select_indefinite_article $result;

                if ($article eq 'AN') {
                    $fixed_article = uc $fixed_article;
                } elsif ($article eq 'An' or $article eq 'A') {
                    $fixed_article = ucfirst $fixed_article;
                }

                $command =~ s/&\{subcmd\}/$fixed_article$spaces$result/;
            } else {
                $command =~ s/&\{subcmd\}/$result/;
            }
        } else {
            if ($context->{result_prefix}) {
                $result = "$context->{result_prefix} $result";
            }

            # append output to queue
            push @{$context->{outq}->[$#{$context->{outq}}]}, $result;
        }

        if (not $context->{alldone}) {
            $context->{command} = $command;
            $context->{result}  = $self->interpret($context);
        }

        $self->handle_result($context);
        return 0;
    }

    # restore /command prefix
    if ($context->{result_prefix}) {
        $result = "$context->{result_prefix} $result";
    }

    # join output queue
    if (exists $context->{outq}) {
        my $botnick = $self->{pbot}->{conn}->nick;

        while (my $outq = pop @{$context->{outq}}) {
            $outq = join ' ', @$outq;

            # reformat result to be more suitable for joining together
            $result =~ s!^/say ! !i
            || $result =~ s!^/me ! * $botnick !i
            || $result =~ s!^! !;

            $result = "$outq$result";
            $result =~ s/^ +//;
        }
        delete $context->{outq};
    }

    # nothing more to do here if we have no result or keyword
    return 0 if not length $result or not exists $context->{keyword};

    my $preserve_newlines = $self->{pbot}->{registry}->get_value($context->{from}, 'preserve_newlines');

    my $original_result = $result;

    $context->{original_result} = $result;

    $result =~ s/[\n\r]/ /g unless $preserve_newlines;
    $result =~ s/[ \t]+/ /g if     $context->{'condense-whitespace'};

    my $max_lines = $self->{pbot}->{registry}->get_value($context->{from}, 'max_newlines') // 4;
    my $lines = 0;

    # split result into lines and go over each line
    foreach my $line (split /[\n\r]+/, $result) {
        # skip blank lines
        next if $line !~ /\S/;

        # paste everything if we've output the maximum lines
        if (++$lines >= $max_lines) {

            my $link = $self->{pbot}->{webpaste}->paste("$context->{from} <$context->{nick}> $context->{text}\n\n$original_result");

            my $message = "<truncated; $link>";

            if ($context->{use_output_queue}) {
                my $message = {
                    nick       => $context->{nick},
                    user       => $context->{user},
                    host       => $context->{host},
                    hostmask   => $context->{hostmask},
                    command    => $context->{command},
                    message    => $message,
                    checkflood => 1
                };

                $self->add_message_to_output_queue($context->{from}, $message, 0);
            } else {
                unless ($context->{from} eq 'stdin@pbot') {
                    $self->{pbot}->{conn}->privmsg($context->{from}, $message);
                }
            }

            last;
        }

        if ($context->{use_output_queue}) {
            my $delay   = rand(10) + 5;
            my $message = {
                nick       => $context->{nick},
                user       => $context->{user},
                host       => $context->{host},
                hostmask   => $context->{hostmask},
                command    => $context->{command},
                message    => $line,
                checkflood => 1,
            };
            $self->add_message_to_output_queue($context->{from}, $message, $delay);
            $delay = duration($delay);
            $self->{pbot}->{logger}->log("($delay delay) $line\n");
        } else {
            $context->{output} = $line;
            $self->output_result($context);
            $self->{pbot}->{logger}->log("$line\n");
        }
    }

    # log a separator bar after command finishes
    $self->{pbot}->{logger}->log("---------------------------------------------\n");

    # successful command completion
    return 1;
}

# truncates a message, optionally pasting to a web paste site.
# $paste_text is the version of text (e.g. with whitespace formatting preserved, etc)
# to send to the paste site.
sub truncate_result($self, $context, $text, $paste_text) {
    my $max_msg_len = $self->{pbot}->{registry}->get_value('irc', 'max_msg_len') // 510;

    # reduce max msg len by length of hostmask and PRIVMSG command
    $max_msg_len -= length ":$self->{pbot}->{hostmask} PRIVMSG $context->{from} :";

    # encode text to utf8 for byte length truncation
    $text       = encode('UTF-8', $text);
    $paste_text = encode('UTF-8', $paste_text);

    my $text_len = length $text;

    if ($text_len > $max_msg_len) {
        my $paste_result;

        if (defined $paste_text) {
            # limit pastes to 32k by default, overridable via paste.max_length
            my $max_paste_len = $self->{pbot}->{registry}->get_value('paste', 'max_length') // 1024 * 32;

            # truncate paste to max paste length
            $paste_text = truncate_egc $paste_text, $max_paste_len;

            # send text to paste site
            $paste_result = $self->{pbot}->{webpaste}->paste("$context->{from} <$context->{nick}> $context->{text}\n\n$paste_text");
        }

        my $trunc = '... <truncated';

        if (not defined $paste_result) {
            # no paste
            $trunc .= '>';
        } else {
            $trunc .= "; $paste_result>";
        }

        $paste_result //= 'not pasted';
        $self->{pbot}->{logger}->log("Message truncated -- $paste_result\n");

        # make room to append the truncation text to the message text
        # (third argument to truncate_egc is '' to prevent appending its own ellipsis)
        my $trunc_len = $text_len < $max_msg_len ? $text_len : $max_msg_len;

        $text = truncate_egc $text, $trunc_len - length $trunc, '';

        # append the truncation text
        $text .= $trunc;
    } else {
        # decode text from utf8
        $text = decode('UTF-8', $text);
    }

    return $text;
}

my @dehighlight_exclusions = qw/auto if unsigned break inline void case int volatile char long while const register _Alignas continue restrict _Alignof default return _Atomic do short _Bool double signed _Complex else sizeof _Generic enum static _Imaginary extern struct _Noreturn float switch _Static_assert for typedef _Thread_local goto union/;

sub dehighlight_nicks($self, $line, $channel) {
    return $line if $self->{pbot}->{registry}->get_value('general', 'no_dehighlight_nicks');

    my @tokens = split / /, $line;

    foreach my $token (@tokens) {
        my $potential_nick = $token;
        $potential_nick =~ s/^[^\w\[\]\-\\\^\{\}]+//;
        $potential_nick =~ s/[^\w\[\]\-\\\^\{\}]+$//;

        next if length $potential_nick == 1;
        next if grep { /\Q$potential_nick/i } @dehighlight_exclusions;
        next if not $self->{pbot}->{nicklist}->is_present($channel, $potential_nick);

        my $dehighlighted_nick = $potential_nick;
        $dehighlighted_nick =~ s/(.)/$1\x{feff}/;

        $token =~ s/\Q$potential_nick\E(?!:)/$dehighlighted_nick/;
    }

    return join ' ', @tokens;
}

sub output_result($self, $context) {
    # debug flag to trace $context location and contents
    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = sub { [sort grep { not /(?:cmdlist|arglist)/ } keys %$context] };
        $Data::Dumper::Indent = 2;
        $self->{pbot}->{logger}->log("Interpreter::output_result\n");
        $self->{pbot}->{logger}->log(Dumper $context);
        $Data::Dumper::Sortkeys = 1;
    }

    my $output = $context->{output};

    # nothing to do if we have nothing to do innit
    return if not defined $output or not length $output;

    # nothing more to do here if the command came from STDIN
    return if $context->{from} eq 'stdin@pbot';

    my $botnick = $self->{pbot}->{conn}->nick;
    my $to      = $context->{from};

    # log the message if requested
    if ($context->{checkflood}) {
        $self->{pbot}->{antiflood}->check_flood($to, $botnick, $self->{pbot}->{registry}->get_value('irc', 'username'), 'pbot', $output, 0, 0, 0);
    }

    # nothing more to do here if the output is going to the bot
    return if $to eq $botnick;

    # insert null-width spaces into nicknames to prevent IRC clients
    # from unncessarily highlighting people
    $output = $self->dehighlight_nicks($output, $to) unless $output =~ m|^/msg |;

    # handle various /command prefixes

    my $type = 'echo'; # will be set to 'echo' or 'action' depending on /command prefix

    if ($output =~ s/^\/say //i) {
        # /say stripped off
        $output = ' ' if not length $output;  # ensure we output something
    }
    elsif ($output =~ s/^\/me //i) {
        # /me stripped off
        $type = 'action';
    }
    elsif ($context->{keyword} ne 'vm-client' && $output =~ s/^\/msg\s+([^\s]+) //i) {
        # /msg somenick stripped off

        $to = $1;  # reset $to to output to somenick

        # don't allow /msg nick1,nick2,etc
        if ($to =~ /,/) {
            $self->{pbot}->{logger}->log("[HACK] Disregarding attempt to /msg multiple users. $context->{hostmask} [$context->{command}] $output\n");
            return;
        }

        # don't allow /msging any nicks that end with "serv" (e.g. ircd services; NickServ, ChanServ, etc)
        if ($to =~ /.*serv(?:@.*)?$/i) {
            $self->{pbot}->{logger}->log("[HACK] Disregarding attempt to /msg *serv. $context->{hostmask} [$context->{command}] $output]\n");
            return;
        }

        if ($output =~ s/^\/me //i) {
            # /me stripped off
            $type = 'action';
        }
        else {
            # strip off /say if present
            $output =~ s/^\/say //i;
        }
    }

    my $bot_nick     = $self->{pbot}->{conn}->nick;
    my $bot_hostmask = "$bot_nick!pbot3\@pbot";
    my $bot_account  = $self->{pbot}->{messagehistory}->get_message_account($bot_nick, 'pbot3', 'pbot');

    if ($type eq 'echo') {
        # prepend ref_from to output
        if ($context->{ref_from}) {
            $output = "[$context->{ref_from}] $output";
        }

        # prepend nickprefix to output
        if ($context->{nickprefix} && (! $context->{nickprefix_disabled} || $context->{nickprefix_forced})) {
            $output = "$context->{nickprefix}: $output";
        }
        elsif ($context->{add_nick}) {
            $output = "$context->{nick}: $output";
        }

        # truncate if necessary, pasting original result to a web paste site
        $output = $self->truncate_result($context, $output, $context->{original_result});

        # add bot's output to message history for recall/grab
        if ($to =~ /^#/) {
            $self->{pbot}->{messagehistory}->add_message($bot_account, $bot_hostmask, $to, $output, MSG_CHAT);
        }

        # send the message to the channel/user
        $self->{pbot}->{conn}->privmsg($to, $output);
    }
    elsif ($type eq 'action') {
        # append ref_from to output
        if ($context->{ref_from}) {
            $output = "$output [$context->{ref_from}]";
        }

        # truncate if necessary, pasting original result to a web paste site
        $output = $self->truncate_result($context, $output, $context->{original_result});

        # add bot's output to message history for recall/grab
        if ($to =~ /^#/) {
            $self->{pbot}->{messagehistory}->add_message($bot_account, $bot_hostmask, $to, "/me $output", MSG_CHAT);
        }

        # CTCP ACTION the message to the channel/user
        $self->{pbot}->{conn}->me($to, $output);
    }
}

sub add_message_to_output_queue($self, $channel, $message, $delay = 0) {
    $self->{pbot}->{event_queue}->enqueue_event(
        sub {
            my $context = {
                from       => $channel,
                nick       => $message->{nick},
                user       => $message->{user},
                host       => $message->{host},
                hostmask   => $message->{hostmask},
                output     => $message->{message},
                command    => $message->{command},
                keyword    => $message->{keyword},
                checkflood => $message->{checkflood}
            };

            $self->output_result($context);
        },
        $delay, "output $channel $message->{message}"
    );
}

sub add_to_command_queue($self, $channel, $command, $delay = 0, $repeating = 0) {
    $self->{pbot}->{event_queue}->enqueue_event(
        sub {
            my $context = {
                from                => $channel,
                nick                => $command->{nick},
                user                => $command->{user},
                host                => $command->{host},
                hostmask            => $command->{hostmask},
                command             => $command->{command},
                interpret_depth     => 0,
                checkflood          => 0,
            };

            if (exists $command->{'cap-override'}) {
                $self->{pbot}->{logger}->log("[command queue] Override command capability with $command->{'cap-override'}\n");
                $context->{'cap-override'} = $command->{'cap-override'};
            }

            $context->{result} = $self->interpret($context);
            $self->handle_result($context);
        },
        $delay, "command $channel $command->{command}", $repeating
    );
}

sub add_botcmd_to_command_queue($self, $channel, $command, $delay = 0) {
    my $botcmd = {
        nick     => $self->{pbot}->{conn}->nick,
        user     => 'stdin',
        host     => 'pbot',
        command  => $command
    };

    $botcmd->{hostmask} = "$botcmd->{nick}!stdin\@pbot";

    $self->add_to_command_queue($channel, $botcmd, $delay);
}

# extracts a bracketed substring, gracefully handling unbalanced quotes
# or brackets. opening and closing brackets may each be more than one character.
# optional prefix may be or begin with a character group.
sub extract_bracketed($self, $string, $open_bracket = '{', $close_bracket = '}', $optional_prefix = '', $allow_whitespace = 0) {
    my @prefix_group;
    if ($optional_prefix =~ s/^\[(.*?)\]//) { @prefix_group = split //, $1; }

    my @prefix;
    my $prefix_max;

    if (!@prefix_group && $optional_prefix ne '""' && $optional_prefix ne "''") {
        @prefix     = split //, $optional_prefix;
        $prefix_max = length $optional_prefix;
    }

    my @opens  = split //, $open_bracket;
    my @closes = split //, $close_bracket;

    my $prefix_index = 0;
    my $open_index   = 0;
    my $close_index  = 0;

    my $result     = '';
    my $rest       = '';
    my $extracting = 0;
    my $extracted  = 0;
    my $escaped    = 0;
    my $token      = '';
    my $ch         = ' ';
    my $last_ch;
    my $i = 0;
    my $bracket_pos;
    my $bracket_level      = 0;
    my $prefix_group_match = @prefix_group ? 0 : 1;
    my $prefix_match       = @prefix ? 0 : 1;
    my $match              = 0;

    my @chars = split //, $string;

    my $state = 'prefixgroup';

    while (1) {
        $last_ch = $ch;

        if ($i >= @chars) {
            if ($extracting) {
                # reached end, but unbalanced brackets... reset to beginning and ignore them
                $i             = $bracket_pos;
                $bracket_level = 0;
                $state         = 'prefixgroup';
                $extracting    = 0;
                $last_ch       = ' ';
                $token         = '';
                $result        = '';
            } else {
                # add final token and exit
                $token .= '\\' if $escaped;
                $rest .= $token if $extracted;
                last;
            }
        }

        $ch = $chars[$i++];

        if ($escaped) {
            $token .= "\\$ch" if $extracting or $extracted;
            $escaped = 0;
            next;
        }

        if ($ch eq '\\') {
            $escaped = 1;
            next;
        }

        if (not $extracted) {
            if ($state eq 'prefixgroup' and @prefix_group and not $extracting) {
                $prefix_group_match = 0;
                foreach my $prefix_ch (@prefix_group) {
                    if ($ch eq $prefix_ch) {
                        $prefix_group_match = 1;
                        $state = 'openbracket';
                        last;
                    }
                }
                next if $prefix_group_match;
            } elsif ($state eq 'prefixgroup' and not @prefix_group) {
                $state = 'prefix';
                $prefix_index = 0;
            }

            if ($state eq 'prefix') {
                if (@prefix and $prefix_index < $prefix_max and $ch eq $prefix[$prefix_index]) {
                    $token .= $ch if $extracting;
                    $prefix_match = 1;
                    $prefix_index++;
                    if ($prefix_index >= $prefix_max) {
                        $state = 'openbracket';
                    }
                    next;
                } elsif (@prefix) {
                    $prefix_match = 0;
                    $state = 'prefixgroup';
                } else {
                    $state = 'openbracket';
                }
            }

            if ($extracting or ($state eq 'openbracket' and $prefix_group_match and $prefix_match)) {
                $prefix_index = 0;
                if ($ch eq $opens[$open_index]) {
                    $match = 1;
                    $open_index++;
                } else {
                    if ($allow_whitespace and $ch eq ' ' and not $extracting) { next; }
                    elsif (not $extracting) {
                        $state = 'prefixgroup';
                        next;
                    }
                }
            }

            if ($match) {
                $state              = 'prefixgroup';
                $prefix_group_match = 0 unless not @prefix_group;
                $prefix_match       = 0 unless not @prefix;
                $match              = 0;
                $bracket_pos        = $i if not $extracting;
                if ($open_index == @opens) {
                    $extracting = 1;
                    $token .= $ch if $bracket_level > 0;
                    $bracket_level++;
                    $open_index = 0;
                }
                next;
            } else {
                $open_index = 0;
            }

            if ($ch eq $closes[$close_index]) {
                if ($extracting or $extracted) {
                    $close_index++;
                    if ($close_index == @closes) {
                        $close_index = 0;
                        if (--$bracket_level == 0) {
                            $extracting = 0;
                            $extracted  = 1;
                            $result .= $token;
                            $token = '';
                        } else {
                            $token .= $ch;
                        }
                    }
                }
                next;
            } else {
                $close_index = 0;
            }
        }

        if ($extracting or $extracted) { $token .= $ch; }
    }

    return ($result, $rest);
}

# splits line into arguments separated by unquoted whitespace.
# handles unbalanced quotes by treating them as part of the
# argument they were found within.
sub split_line($self, $line, %opts) {
    my %default_opts = (
        strip_quotes     => 0,
        keep_spaces      => 0,
        preserve_escapes => 0,
        strip_commas     => 0,
    );

    %opts = (%default_opts, %opts);

    return () if not length $line;

    my @chars = split //, $line;

    my @args;
    my $ch;
    my $pos;
    my $quote;
    my $escaped      = 0;
    my $token        = '';
    my $last_token   = '';
    my $i            = 0;
    my $ignore_quote = 0;
    my $spaces       = 0;
    my $add_token    = 0;
    my $got_ch       = 0;

    while (1) {
        if ($i >= @chars) {
            if (defined $quote) {
                # reached end, but unbalanced quote... reset to beginning of quote and ignore it
                $i            = $pos;
                $ignore_quote = 1;
                $quote        = undef;
                $token        = $last_token;
            } else {
                # add final token and exit
                $token .= '\\' if $escaped;
                push @args, $token;
                last;
            }
        }

        $ch = $chars[$i++];

        $spaces = 0 if $ch ne ' ';

        if ($escaped) {
            if ($add_token) {
                push @args, $token;
                $token = '';
                $add_token = 0;
            }

            if ($opts{preserve_escapes}) {
                $token .= "\\$ch";
            } else {
                $token .= $ch;
            }

            $escaped = 0;
            next;
        }

        if ($ch eq '\\') {
            $escaped = 1;
            $got_ch  = 1;
            next;
        }

        if (defined $quote) {
            if ($ch eq $quote) {
                # closing quote
                $token .= $ch unless $opts{strip_quotes};
                $quote = undef;
            } else {
                # still within quoted argument
                $token .= $ch;
            }
            next;
        }

        if (not defined $quote and ($ch eq "'" or $ch eq '"')) {
            $got_ch = 1;

            if ($add_token) {
                push @args, $token;
                $token = '';
                $add_token = 0;
            }

            if ($ignore_quote) {
                # treat unbalanced quote as part of this argument
                $token .= $ch;
                $ignore_quote = 0;
            } else {
                # begin potential quoted argument
                $pos        = $i - 1;
                $quote      = $ch;
                $last_token = $token;
                $token .= $ch unless $opts{strip_quotes};
            }
            next;
        }

        if ($ch eq ' ' or $ch eq "\n" or $ch eq "\t" or ($opts{strip_commas} and $ch eq ',')) {
            if (++$spaces > 1 and $opts{keep_spaces}) {
                $token .= $ch;
                next;
            } else {
                if ($opts{keep_spaces} && $ch eq "\n") {
                    $token .= $ch;
                }

                unless ($opts{strip_commas} and $token eq ',') {
                    $add_token = 1 if $got_ch;
                }
                next;
            }
        }

        if ($add_token) {
            push @args, $token;
            $token = '';
            $add_token = 0;
        }

        $got_ch = 1;
        $token .= $ch;
    }

    return @args;
}

# creates an array of arguments from a string
sub make_args($self, $string, %opts) {
    my %default_opts = (
        keep_spaces      => 0,
        preserve_escapes => 1,
    );

    %opts = (%default_opts, %opts);

    my @args = $self->split_line($string, keep_spaces => $opts{keep_spaces}, preserve_escapes => $opts{preserve_escapes});

    my @arglist;
    my @arglist_unstripped;

    while (@args) {
        my $arg = shift @args;

        # add argument with quotes and spaces preserved
        push @arglist_unstripped, $arg;

        # strip leading spaces from argument
        $arg =~ s/^\s+//;

        # strip quotes from argument
        if ($arg =~ m/^'.*'$/) {
            $arg =~ s/^'//;
            $arg =~ s/'$//;
        } elsif ($arg =~ m/^".*"$/) {
            $arg =~ s/^"//;
            $arg =~ s/"$//;
        }

        # add stripped argument
        push @arglist, $arg;
    }

    # copy unstripped arguments to end of arglist
    push @arglist, @arglist_unstripped;
    return \@arglist;
}

# returns size of array of arguments
sub arglist_size($self, $args) {
    return @$args / 2;
}

# unshifts new argument to front
sub unshift_arg($self, $args, $arg) {
    splice @$args, @$args / 2, 0, $arg;    # add quoted argument
    unshift @$args, $arg;                  # add first argument
    return @$args;
}

# shifts first argument off array of arguments
sub shift_arg($self, $args) {
    return undef if not @$args;
    splice @$args, @$args / 2, 1;          # remove original quoted argument
    return shift @$args;
}

# returns list of unquoted arguments
sub unquoted_args($self, $args) {
    return undef if not @$args;
    return @$args[0 .. @$args / 2 - 1];
}

# splits array of arguments into array with overflow arguments filling up last position
# split_args(qw/dog cat bird hamster/, 3) => ("dog", "cat", "bird hamster")
sub split_args($self, $args, $count, $offset = 0, $preserve_quotes = 0) {
    my @result;
    my $max = $self->arglist_size($args);

    my $i = $offset;
    unless ($count == 1) {
        do {
            my $arg = $args->[$i++];
            push @result, $arg;
        } while (--$count > 1 and $i < $max);
    }

    # join the get rest as a string
    my $rest = '';
    if ($preserve_quotes) {
        # get from second half of args, which contains quotes
        foreach my $arg (@$args[@$args / 2 + $i .. @$args - 1]) {
            $rest .= ' ' unless not length $rest;
            $rest .= $arg;
        }
    } else {
        $rest = join ' ', @$args[$i .. $max - 1];
    }

    push @result, $rest if length $rest;
    return @result;
}

# lowercases array of arguments
sub lc_args($self, $args) {
    for (my $i = 0; $i < @$args; $i++) { $args->[$i] = lc $args->[$i]; }
}

# getopt boilerplate in one place

# 99% of our getopt use is on a string
sub getopt($self, @args) {
    $self->getopt_from_string(@args);
}

# getopt_from_string() uses our split_line() function instead of
# Getopt::Long::GetOptionsFromString's Text::ParseWords
sub getopt_from_string($self, $string, $result, $config, @opts) {
    my @opt_args = $self->split_line($string, strip_quotes => 1);
    return $self->getopt_from_array(\@opt_args, $result, $config, @opts);
}

# the workhorse getopt function
sub getopt_from_array($self, $opt_args, $result, $config, @opts) {
    # emitting errors as Perl warnings instead of using die, weird.
    my $opt_error;
    local $SIG{__WARN__} = sub {
        $opt_error = shift;
        chomp $opt_error;
    };

    Getopt::Long::Configure(@$config);
    GetOptionsFromArray($opt_args, $result, @opts);
    return ($opt_args, $opt_error);
}

1;
