# File: Interpreter.pm
# Author: pragma_
#
# Purpose:

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Interpreter;

use parent 'PBot::Class', 'PBot::Registerable';

use warnings; use strict;
use feature 'unicode_strings';

use Time::HiRes qw/gettimeofday/;
use Time::Duration;

use PBot::Utils::ValidateString;

sub initialize {
    my ($self, %conf) = @_;
    $self->PBot::Registerable::initialize(%conf);

    $self->{pbot}->{registry}->add_default('text',  'general', 'compile_blocks',                 $conf{compile_blocks}                 // 1);
    $self->{pbot}->{registry}->add_default('array', 'general', 'compile_blocks_channels',        $conf{compile_blocks_channels}        // '.*');
    $self->{pbot}->{registry}->add_default('array', 'general', 'compile_blocks_ignore_channels', $conf{compile_blocks_ignore_channels} // 'none');
    $self->{pbot}->{registry}->add_default('text', 'interpreter', 'max_recursion', 10);
}

sub process_line {
    my $self = shift;
    my ($from, $nick, $user, $host, $text) = @_;
    $from = lc $from if defined $from;

    my $context = {from => $from, nick => $nick, user => $user, host => $host, hostmask => "$nick!$user\@$host", text => $text};
    my $pbot  = $self->{pbot};

    my $message_account = $pbot->{messagehistory}->get_message_account($nick, $user, $host);
    $pbot->{messagehistory}->add_message($message_account, $context->{hostmask}, $from, $text, $pbot->{messagehistory}->{MSG_CHAT});
    $context->{message_account} = $message_account;

    my $flood_threshold      = $pbot->{registry}->get_value($from, 'chat_flood_threshold');
    my $flood_time_threshold = $pbot->{registry}->get_value($from, 'chat_flood_time_threshold');

    $flood_threshold      = $pbot->{registry}->get_value('antiflood', 'chat_flood_threshold')      if not defined $flood_threshold;
    $flood_time_threshold = $pbot->{registry}->get_value('antiflood', 'chat_flood_time_threshold') if not defined $flood_time_threshold;

    if (defined $from and $from =~ m/^#/) {
        my $chanmodes = $self->{pbot}->{channels}->get_meta($from, 'MODE');
        if (defined $chanmodes and $chanmodes =~ m/z/) {
            $context->{'chan-z'} = 1;
            if ($self->{pbot}->{banlist}->{quietlist}->exists($from, '$~a')) {
                my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($message_account);
                if (not defined $nickserv or not length $nickserv) { $context->{unidentified} = 1; }
            }

            $context->{banned} = 1 if $self->{pbot}->{banlist}->is_banned($nick, $user, $host, $from);
        }
    }

    $pbot->{antiflood}->check_flood(
        $from,                               $nick, $user, $host, $text,
        $flood_threshold,                    $flood_time_threshold,
        $pbot->{messagehistory}->{MSG_CHAT}, $context
    ) if defined $from;

    if ($context->{banned} or $context->{unidentified}) {
        $self->{pbot}->{logger}->log("Disregarding banned/unidentified user message (channel $from is +z).\n");
        return 1;
    }

    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

    # get channel-specific trigger if available
    my $bot_trigger = $pbot->{registry}->get_value($from, 'trigger');

    # otherwise get general trigger
    if (not defined $bot_trigger) { $bot_trigger = $pbot->{registry}->get_value('general', 'trigger'); }

    my $nick_regex = qr/[^%!,:\(\)\+\*\/ ]+/;

    my $nick_override;
    my $processed           = 0;
    my $preserve_whitespace = 0;

    $text =~ s/^\s+//;
    $text =~ s/\s+$//;
    $text = validate_string($text, 0);

    my $cmd_text = $text;
    $cmd_text =~ s/^\/me\s+//;

    # check for bot command invocation
    my @commands;
    my $command;
    my $embedded = 0;

    if    ($cmd_text =~ m/^\s*($nick_regex)[,:]?\s+$bot_trigger\{\s*(.+?)\s*\}\s*$/) { goto CHECK_EMBEDDED_CMD; }
    elsif ($cmd_text =~ m/^\s*$bot_trigger\{\s*(.+?)\s*\}\s*$/)                      { goto CHECK_EMBEDDED_CMD; }
    elsif ($cmd_text =~ m/^\s*($nick_regex)[,:]\s+$bot_trigger\s*(.+)$/) {
        my $possible_nick_override = $1;
        $command = $2;

        my $similar = $self->{pbot}->{nicklist}->is_present_similar($from, $possible_nick_override);
        if ($similar) { $nick_override = $similar; }
        else {
            $self->{pbot}->{logger}->log("No similar nick for $possible_nick_override\n");
            return 0;
        }
    } elsif ($cmd_text =~ m/^$bot_trigger\s*(.+)$/) {
        $command = $1;
    } elsif ($cmd_text =~ m/^.?$botnick.?\s*(.+)$/i) {
        $command = $1;
    } elsif ($cmd_text =~ m/^(.+?),?\s*$botnick[?!.]*$/i) {
        $command = $1;
    }

    # check for embedded commands
  CHECK_EMBEDDED_CMD:
    if (not defined $command or $command =~ m/^\{.*\}/) {
        if ($cmd_text =~ s/^\s*($nick_regex)[,:]\s+//) {
            my $possible_nick_override = $1;
            my $similar                = $self->{pbot}->{nicklist}->is_present_similar($from, $possible_nick_override);
            if ($similar) { $nick_override = $similar; }
        }

        for (my $count = 0; $count < 3; $count++) {
            my ($extracted, $rest) = $self->extract_bracketed($cmd_text, '{', '}', $bot_trigger);
            last if not length $extracted;
            $cmd_text = $rest;
            $extracted =~ s/^\s+|\s+$//g;
            push @commands, $extracted;
            $embedded = 1;
        }
    } else {
        push @commands, $command;
    }

    foreach $command (@commands) {
        # check if user is ignored (and command isn't `login`)
        if ($command !~ /^login / && defined $from && $pbot->{ignorelist}->is_ignored($from, "$nick!$user\@$host")) {
            $self->{pbot}->{logger}->log("Disregarding command from ignored user $nick!$user\@$host in $from.\n");
            return 1;
        }

        $context->{text}    = $text;
        $context->{command} = $command;

        if ($nick_override) {
            $context->{nickoverride}       = $nick_override;
            $context->{force_nickoverride} = 1;
        }

        $context->{referenced}          = $embedded;
        $context->{interpret_depth}     = 0;
        $context->{preserve_whitespace} = $preserve_whitespace;

        $context->{result} = $self->interpret($context);
        $self->handle_result($context);
        $processed++;
    }
    return $processed;
}

sub interpret {
    my ($self, $context) = @_;
    my ($keyword, $arguments) = ('', '');
    my $text;
    my $pbot = $self->{pbot};

    $context->{interpret_depth}++;

    $pbot->{logger}->log("=== [$context->{interpret_depth}] Got command: ("
          . (defined $context->{from} ? $context->{from} : "undef")
          . ") $context->{hostmask}: $context->{command}\n");

    $context->{special} = "" unless exists $self->{special};

    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("Interpreter::interpret\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    return "Too many levels of recursion, aborted." if ($context->{interpret_depth} > $self->{pbot}->{registry}->get_value('interpreter', 'max_recursion'));

    if (not defined $context->{nick} || not defined $context->{user} || not defined $context->{host} || not defined $context->{command}) {
        $pbot->{logger}->log("Error 1, bad parameters to interpret_command\n");
        return undef;
    }

    # check for splitted commands
    if ($context->{command} =~ m/^(.*?)\s*(?<!\\);;;\s*(.*)/ms) {
        $context->{command}       = $1;
        $context->{command_split} = $2;
    }

    my $cmdlist = $self->make_args($context->{command});
    $context->{commands} = [] unless exists $context->{commands};
    push @{$context->{commands}}, $context->{command};

    if ($self->arglist_size($cmdlist) >= 4 and lc $cmdlist->[0] eq 'tell' and (lc $cmdlist->[2] eq 'about' or lc $cmdlist->[2] eq 'the')) {
        # tell nick about/the cmd [args]
        $context->{nickoverride} = $cmdlist->[1];
        ($keyword, $arguments) = $self->split_args($cmdlist, 2, 3, 1);
        $arguments = '' if not defined $arguments;
        my $similar = $self->{pbot}->{nicklist}->is_present_similar($context->{from}, $context->{nickoverride});
        if ($similar) {
            $context->{nickoverride}       = $similar;
            $context->{force_nickoverride} = 1;
        } else {
            delete $context->{nickoverride};
            delete $context->{force_nickoverride};
        }
    } else {
        # normal command
        ($keyword, $arguments) = $self->split_args($cmdlist, 2, 0, 1);
        $arguments = '' if not defined $arguments;
    }

    # FIXME: make this a registry item
    if (length $keyword > 128) {
        $keyword = substr($keyword, 0, 128);
        $self->{pbot}->{logger}->log("Truncating keyword to 128 chars: $keyword\n");
    }

    # parse out a substituted command
    if (defined $arguments && $arguments =~ m/(?<!\\)&\s*\{/) {
        my ($command) = $self->extract_bracketed($arguments, '{', '}', '&', 1);

        if (length $command) {
            $arguments =~ s/&\s*\{\Q$command\E\}/&{subcmd}/;
            push @{$context->{subcmd}}, "$keyword $arguments";
            $command =~ s/^\s+|\s+$//g;
            $context->{command}  = $command;
            $context->{commands} = [];
            push @{$context->{commands}}, $command;
            $context->{result} = $self->interpret($context);
            return $context->{result};
        }
    }

    # parse out a pipe
    if (defined $arguments && $arguments =~ m/(?<!\\)\|\s*\{\s*[^}]+\}\s*$/) {
        my ($pipe, $rest) = $self->extract_bracketed($arguments, '{', '}', '|', 1);

        $arguments =~ s/\s*(?<!\\)\|\s*{(\Q$pipe\E)}.*$//s;
        $pipe      =~ s/^\s+|\s+$//g;

        if   (exists $context->{pipe}) { $context->{pipe_rest} = "$rest | { $context->{pipe} }$context->{pipe_rest}"; }
        else                         { $context->{pipe_rest} = $rest; }
        $context->{pipe} = $pipe;
    }

    if (    not $self->{pbot}->{commands}->get_meta($keyword, 'dont-replace-pronouns')
        and not $self->{pbot}->{factoids}->get_meta($context->{from}, $keyword, 'dont-replace-pronouns'))
    {
        $context->{nickoverride} = $context->{nick} if defined $context->{nickoverride} and lc $context->{nickoverride} eq 'me';
        $keyword   =~ s/(\w+)([?!.]+)$/$1/;
        $arguments =~ s/(?<![\w\/\-\\])i am\b/$context->{nick} is/gi if defined $arguments && $context->{interpret_depth} <= 1;
        $arguments =~ s/(?<![\w\/\-\\])me\b/$context->{nick}/gi if defined $arguments && $context->{interpret_depth} <= 1;
        $arguments =~ s/(?<![\w\/\-\\])my\b/$context->{nick}'s/gi if defined $arguments && $context->{interpret_depth} <= 1;
        $arguments =~ s/\\my\b/my/gi if defined $arguments && $context->{interpret_depth} <= 1;
        $arguments =~ s/\\me\b/me/gi if defined $arguments && $context->{interpret_depth} <= 1;
        $arguments =~ s/\\i am\b/i am/gi if defined $arguments && $context->{interpret_depth} <= 1;
    }

    if (not $self->{pbot}->{commands}->get_meta($keyword, 'dont-protect-self') and not $self->{pbot}->{factoids}->get_meta($context->{from}, $keyword, 'dont-protect-self')) {
        my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
        if (defined $arguments && ($arguments =~ m/^(your|him|her|its|it|them|their)(self|selves)$/i || $arguments =~ m/^$botnick$/i)) {
            my $delay   = rand(10) + 5;
            my $message = {
                nick    => $context->{nick}, user => $context->{user}, host => $context->{host}, command => $context->{command}, checkflood => 1,
                message => "$context->{nick}: Why would I want to do that to myself?"
            };
            $self->add_message_to_output_queue($context->{from}, $message, $delay);
            $delay = duration($delay);
            $self->{pbot}->{logger}->log("($delay delay) $message->{message}\n");
            return undef;
        }
    }

    if (not defined $keyword) {
        $pbot->{logger}->log("Error 2, no keyword\n");
        return undef;
    }

    if (not exists $context->{root_keyword}) { $context->{root_keyword} = $keyword; }

    $context->{keyword}            = $keyword;
    $context->{original_arguments} = $arguments;

    # unescape any escaped command splits
    $arguments =~ s/\\;;;/;;;/g if defined $arguments;

    # unescape any escaped substituted commands
    $arguments =~ s/\\&\s*\{/&{/g if defined $arguments;

    # unescape any escaped pipes
    $arguments =~ s/\\\|\s*\{/| {/g if defined $arguments;

    $arguments = validate_string($arguments);

    # set arguments as a plain string
    $context->{arguments} = $arguments;
    delete $context->{args_utf8};

    # set arguments as an array
    $context->{arglist} = $self->make_args($arguments);

    # execute all registered interpreters
    my $result;
    foreach my $func (@{$self->{handlers}}) {
        $result = &{$func->{subref}}($context);
        last if defined $result;

        # reset any manipulated arguments
        $context->{arguments} = $context->{original_arguments};
        delete $context->{args_utf8};
    }

    return $result;
}

# extracts a bracketed substring, gracefully handling unbalanced quotes
# or brackets. opening and closing brackets may each be more than one character.
# optional prefix may be or begin with a character group.
sub extract_bracketed {
    my ($self, $string, $open_bracket, $close_bracket, $optional_prefix, $allow_whitespace) = @_;

    $open_bracket     = '{' if not defined $open_bracket;
    $close_bracket    = '}' if not defined $close_bracket;
    $optional_prefix  = ''  if not defined $optional_prefix;
    $allow_whitespace = 0   if not defined $allow_whitespace;

    my @prefix_group;

    if ($optional_prefix =~ s/^\[(.*?)\]//) { @prefix_group = split //, $1; }

    my @prefixes = split //, $optional_prefix;
    my @opens    = split //, $open_bracket;
    my @closes   = split //, $close_bracket;

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
    my $prefix_match       = @prefixes ? 0 : 1;
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
                foreach my $prefix_ch (@prefix_group) {
                    if ($ch eq $prefix_ch) {
                        $prefix_group_match = 1;
                        $state              = 'prefixes';
                        last;
                    } else {
                        $prefix_group_match = 0;
                    }
                }
                next if $prefix_group_match;
            } elsif ($state eq 'prefixgroup' and not @prefix_group) {
                $state        = 'prefixes';
                $prefix_index = 0;
            }

            if ($state eq 'prefixes') {
                if (@prefixes and $ch eq $prefixes[$prefix_index]) {
                    $token .= $ch if $extracting;
                    $prefix_match = 1;
                    $prefix_index++;
                    $state = 'openbracket';
                    next;
                } elsif ($state eq 'prefixes' and not @prefixes) {
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
                $prefix_match       = 0 unless not @prefixes;
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

# splits line into quoted arguments while preserving quotes.
# a string is considered quoted only if they are surrounded by
# whitespace or json separators.
# handles unbalanced quotes gracefully by treating them as
# part of the argument they were found within.
sub split_line {
    my ($self, $line, %opts) = @_;

    my %default_opts = (
        strip_quotes     => 0,
        keep_spaces      => 0,
        preserve_escapes => 1,
    );

    %opts = (%default_opts, %opts);

    my @chars = split //, $line;

    my @args;
    my $escaped = 0;
    my $quote;
    my $token      = '';
    my $last_token = '';
    my $ch         = ' ';
    my $last_ch;
    my $next_ch;
    my $i = 0;
    my $pos;
    my $ignore_quote = 0;
    my $spaces       = 0;

    while (1) {
        $last_ch = $ch;

        if ($i >= @chars) {
            if (defined $quote) {
                # reached end, but unbalanced quote... reset to beginning of quote and ignore it
                $i            = $pos;
                $ignore_quote = 1;
                $quote        = undef;
                $last_ch      = ' ';
                $token        = $last_token;
            } else {
                # add final token and exit
                push @args, $token if length $token;
                last;
            }
        }

        $ch      = $chars[$i++];
        $next_ch = $chars[$i];

        $spaces = 0 if $ch ne ' ';

        if ($escaped) {
            if   ($opts{preserve_escapes}) { $token .= "\\$ch"; }
            else                           { $token .= $ch; }
            $escaped = 0;
            next;
        }

        if ($ch eq '\\') {
            $escaped = 1;
            next;
        }

        if (defined $quote) {
            if ($ch eq $quote and (not defined $next_ch or $next_ch =~ /[\s,:;})\].+=]/)) {
                # closing quote
                $token .= $ch unless $opts{strip_quotes};
                push @args, $token;
                $quote = undef;
                $token = '';
            } else {
                # still within quoted argument
                $token .= $ch;
            }
            next;
        }

        if (($last_ch =~ /[\s:{(\[.+=]/) and not defined $quote and ($ch eq "'" or $ch eq '"')) {
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

        if ($ch eq ' ' or $ch eq "\n" or $ch eq "\t") {
            if (++$spaces > 1 and $opts{keep_spaces}) {
                $token .= $ch;
                next;
            } else {
                push @args, $token if length $token;
                $token = '';
                next;
            }
        }

        $token .= $ch;
    }

    return @args;
}

# creates an array of arguments from a string
sub make_args {
    my ($self, $string) = @_;

    my @args = $self->split_line($string, keep_spaces => 1);

    my @arglist;
    my @arglist_unstripped;

    while (@args) {
        my $arg = shift @args;

        # add argument with quotes and spaces preserved
        push @arglist_unstripped, $arg;

        # strip quotes from argument
        if ($arg =~ m/^'.*'$/) {
            $arg =~ s/^'//;
            $arg =~ s/'$//;
        } elsif ($arg =~ m/^".*"$/) {
            $arg =~ s/^"//;
            $arg =~ s/"$//;
        }

        # strip leading spaces from argument
        $arg =~ s/^\s+//;

        # add stripped argument
        push @arglist, $arg;
    }

    # copy unstripped arguments to end of arglist
    push @arglist, @arglist_unstripped;
    return \@arglist;
}

# returns size of array of arguments
sub arglist_size {
    my ($self, $args) = @_;
    return @$args / 2;
}

# unshifts new argument to front
sub unshift_arg {
    my ($self, $args, $arg) = @_;
    splice @$args, @$args / 2, 0, $arg;    # add quoted argument
    unshift @$args, $arg;                  # add first argument
    return @$args;
}

# shifts first argument off array of arguments
sub shift_arg {
    my ($self, $args) = @_;
    return undef if not @$args;
    splice @$args, @$args / 2, 1;          # remove original quoted argument
    return shift @$args;
}

# returns list of unquoted arguments
sub unquoted_args {
    my ($self, $args) = @_;
    return undef if not @$args;
    return @$args[0 .. @$args / 2 - 1];
}

# splits array of arguments into array with overflow arguments filling up last position
# split_args(qw/dog cat bird hamster/, 3) => ("dog", "cat", "bird hamster")
sub split_args {
    my ($self, $args, $count, $offset, $preserve_quotes) = @_;
    my @result;
    my $max = $self->arglist_size($args);

    $preserve_quotes //= 0;

    my $i = $offset // 0;
    unless ($count == 1) {
        do {
            my $arg = $args->[$i++];
            push @result, $arg;
        } while (--$count > 1 and $i < $max);
    }

    # join the get rest as a string
    my $rest;
    if ($preserve_quotes) {
        # get from second half of args, which contains quotes
        $rest = join ' ', @$args[@$args / 2 + $i .. @$args - 1];
    } else {
        $rest = join ' ', @$args[$i .. $max - 1];
    }
    push @result, $rest if length $rest;
    return @result;
}

# lowercases array of arguments
sub lc_args {
    my ($self, $args) = @_;
    for (my $i = 0; $i < @$args; $i++) { $args->[$i] = lc $args->[$i]; }
}

sub truncate_result {
    my ($self, $from, $nick, $text, $original_result, $result, $paste) = @_;
    my $max_msg_len = $self->{pbot}->{registry}->get_value('irc', 'max_msg_len');
    $max_msg_len -= length "PRIVMSG $from :" if defined $from;

    utf8::encode $result;
    utf8::encode $original_result;

    use bytes;

    if (length $result > $max_msg_len) {
        my $link;
        if ($paste) {
            my $max_paste_len = $self->{pbot}->{registry}->get_value('paste', 'max_length') // 1024 * 32;
            $original_result = substr $original_result, 0, $max_paste_len;
            $link            = $self->{pbot}->{webpaste}->paste("[" . (defined $from ? $from : "stdin") . "] <$nick> $text\n\n$original_result");
        } else {
            $link = 'undef';
        }

        my $trunc = "... [truncated; ";
        if   ($link =~ m/^http/) { $trunc .= "see $link for full text.]"; }
        else                     { $trunc .= "$link]"; }

        $self->{pbot}->{logger}->log("Message truncated -- pasted to $link\n") if $paste;
        my $trunc_len = length $result < $max_msg_len ? length $result : $max_msg_len;
        $result = substr($result, 0, $trunc_len);
        substr($result, $trunc_len - length $trunc) = $trunc;
    }

    utf8::decode $result;
    return $result;
}

sub handle_result {
    my ($self, $context, $result) = @_;
    $result                       = $context->{result} if not defined $result;
    $context->{preserve_whitespace} = 0                if not defined $context->{preserve_whitespace};

    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext') and length $context->{result}) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("Interpreter::handle_result [$result]\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    return 0 if not defined $result or length $result == 0;

    if    ($result =~ s#^(/say|/me) ##) { $context->{prepend} = $1; }
    elsif ($result =~ s#^(/msg \S+) ##) { $context->{prepend} = $1; }

    if ($context->{pipe}) {
        my ($pipe, $pipe_rest) = (delete $context->{pipe}, delete $context->{pipe_rest});
        if (not $context->{alldone}) {
            $context->{command} = "$pipe $result $pipe_rest";
            $result           = $self->interpret($context);
            $context->{result}  = $result;
        }
        $self->handle_result($context, $result);
        return 0;
    }

    if (exists $context->{subcmd}) {
        my $command = pop @{$context->{subcmd}};

        if (@{$context->{subcmd}} == 0 or $context->{alldone}) { delete $context->{subcmd}; }

        $command =~ s/&\{subcmd\}/$result/;

        if (not $context->{alldone}) {
            $context->{command} = $command;
            $result           = $self->interpret($context);
            $context->{result}  = $result;
        }
        $self->handle_result($context);
        return 0;
    }

    if ($context->{prepend}) { $result = "$context->{prepend} $result"; }

    if ($context->{command_split}) {
        my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
        $context->{command} = delete $context->{command_split};
        $result =~ s#^/say #\n#i;
        $result =~ s#^/me #\n* $botnick #i;
        if (not length $context->{split_result}) {
            $result =~ s/^\n//;
            $context->{split_result} = $result;
        } else {
            $context->{split_result} .= $result;
        }
        $result = $self->interpret($context);
        $self->handle_result($context, $result);
        return 0;
    }

    if ($context->{split_result}) {
        my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
        $result =~ s#^/say #\n#i;
        $result =~ s#^/me #\n* $botnick #i;
        $result = $context->{split_result} . $result;
    }

    my $original_result = $result;

    my $use_output_queue = 0;

    if (defined $context->{command}) {
        my $cmdlist = $self->make_args($context->{command});
        my ($cmd, $args) = $self->split_args($cmdlist, 2, 0, 1);
        if (not $self->{pbot}->{commands}->exists($cmd)) {
            my ($chan, $trigger) = $self->{pbot}->{factoids}->find_factoid($context->{from}, $cmd, arguments => $args, exact_channel => 1, exact_trigger => 0, find_alias => 1);
            if (defined $trigger) {
                if ($context->{preserve_whitespace} == 0) {
                    $context->{preserve_whitespace} = $self->{pbot}->{factoids}->{factoids}->get_data($chan, $trigger, 'preserve_whitespace') // 0;
                }

                $use_output_queue = $self->{pbot}->{factoids}->{factoids}->get_data($chan, $trigger, 'use_output_queue');
                $use_output_queue = 0 if not defined $use_output_queue;
            }
        }
    }

    my $preserve_newlines = $self->{pbot}->{registry}->get_value($context->{from}, 'preserve_newlines');

    $result =~ s/[\n\r]/ /g unless $preserve_newlines;
    $result =~ s/[ \t]+/ /g unless $context->{preserve_whitespace};

    my $max_lines = $self->{pbot}->{registry}->get_value($context->{from}, 'max_newlines');
    $max_lines = 4 if not defined $max_lines;
    my $lines = 0;

    my $stripped_line;
    foreach my $line (split /[\n\r]+/, $result) {
        $stripped_line = $line;
        $stripped_line =~ s/^\s+//;
        $stripped_line =~ s/\s+$//;
        next if not length $stripped_line;

        if (++$lines >= $max_lines) {
            my $link = $self->{pbot}->{webpaste}->paste("[" . (defined $context->{from} ? $context->{from} : "stdin") . "] <$context->{nick}> $context->{text}\n\n$original_result");
            if ($use_output_queue) {
                my $message = {
                    nick       => $context->{nick}, user => $context->{user}, host => $context->{host}, command => $context->{command},
                    message    => "And that's all I have to say about that. See $link for full text.",
                    checkflood => 1
                };
                $self->add_message_to_output_queue($context->{from}, $message, 0);
            } else {
                $self->{pbot}->{conn}->privmsg($context->{from}, "And that's all I have to say about that. See $link for full text.") unless $context->{from} eq 'stdin@pbot';
            }
            last;
        }

        if   ($preserve_newlines) { $line = $self->truncate_result($context->{from}, $context->{nick}, $context->{text}, $line,            $line, 1); }
        else                      { $line = $self->truncate_result($context->{from}, $context->{nick}, $context->{text}, $original_result, $line, 1); }

        if ($use_output_queue) {
            my $delay   = rand(10) + 5;
            my $message = {
                nick    => $context->{nick}, user       => $context->{user}, host => $context->{host}, command => $context->{command},
                message => $line,          checkflood => 1
            };
            $self->add_message_to_output_queue($context->{from}, $message, $delay);
            $delay = duration($delay);
            $self->{pbot}->{logger}->log("($delay delay) $line\n");
        } else {
            $context->{line} = $line;
            $self->output_result($context);
            $self->{pbot}->{logger}->log("$line\n");
        }
    }
    $self->{pbot}->{logger}->log("---------------------------------------------\n");
    return 1;
}

sub dehighlight_nicks {
    my ($self, $line, $channel) = @_;
    return $line if $self->{pbot}->{registry}->get_value('general', 'no_dehighlight_nicks');

    my @tokens = split / /, $line;
    foreach my $token (@tokens) {
        my $potential_nick = $token;
        $potential_nick =~ s/^[^\w\[\]\-\\\^\{\}]+//;
        $potential_nick =~ s/[^\w\[\]\-\\\^\{\}]+$//;

        next if length $potential_nick == 1;
        next if not $self->{pbot}->{nicklist}->is_present($channel, $potential_nick);

        my $dehighlighted_nick = $potential_nick;
        $dehighlighted_nick =~ s/(.)/$1\x{200b}/;

        $token =~ s/\Q$potential_nick\E(?!:)/$dehighlighted_nick/;
    }

    return join ' ', @tokens;
}

sub output_result {
    my ($self, $context)   = @_;
    my ($pbot, $botnick) = ($self->{pbot}, $self->{pbot}->{registry}->get_value('irc', 'botnick'));

    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("Interpreter::output_result\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    my $line = $context->{line};

    return   if not defined $line or not length $line;
    return 0 if $context->{from} eq 'stdin@pbot';

    $line = $self->dehighlight_nicks($line, $context->{from}) if $context->{from} =~ /^#/ and $line !~ /^\/msg\s+/i;

    if ($line =~ s/^\/say\s+//i) {
        if (defined $context->{nickoverride} and ($context->{no_nickoverride} == 0 or $context->{force_nickoverride} == 1)) { $line = "$context->{nickoverride}: $line"; }
        $pbot->{conn}->privmsg($context->{from}, $line) if defined $context->{from} && $context->{from} ne $botnick;
        $pbot->{antiflood}->check_flood($context->{from}, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'pbot', $line, 0, 0, 0) if $context->{checkflood};
    } elsif ($line =~ s/^\/me\s+//i) {
        $pbot->{conn}->me($context->{from}, $line) if defined $context->{from} && $context->{from} ne $botnick;
        $pbot->{antiflood}->check_flood($context->{from}, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'pbot', '/me ' . $line, 0, 0, 0) if $context->{checkflood};
    } elsif ($line =~ s/^\/msg\s+([^\s]+)\s+//i) {
        my $to = $1;
        if ($to =~ /,/) {
            $pbot->{logger}->log("[HACK] Possible HACK ATTEMPT /msg multiple users: [$context->{nick}!$context->{user}\@$context->{host}] [$context->{command}] [$line]\n");
        } elsif ($to =~ /.*serv(?:@.*)?$/i) {
            $pbot->{logger}->log("[HACK] Possible HACK ATTEMPT /msg *serv: [$context->{nick}!$context->{user}\@$context->{host}] [$context->{command}] [$line]\n");
        } elsif ($line =~ s/^\/me\s+//i) {
            $pbot->{conn}->me($to, $line)                                                                                                    if $to ne $botnick;
            $pbot->{antiflood}->check_flood($to, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'pbot', '/me ' . $line, 0, 0, 0) if $context->{checkflood};
        } else {
            $line =~ s/^\/say\s+//i;
            if (defined $context->{nickoverride} and ($context->{no_nickoverride} == 0 or $context->{force_nickoverride} == 1)) { $line = "$context->{nickoverride}: $line"; }
            $pbot->{conn}->privmsg($to, $line)                                                                                      if $to ne $botnick;
            $pbot->{antiflood}->check_flood($to, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'pbot', $line, 0, 0, 0) if $context->{checkflood};
        }
    } else {
        if (defined $context->{nickoverride} and ($context->{no_nickoverride} == 0 or $context->{force_nickoverride} == 1)) { $line = "$context->{nickoverride}: $line"; }
        $pbot->{conn}->privmsg($context->{from}, $line) if defined $context->{from} && $context->{from} ne $botnick;
        $pbot->{antiflood}->check_flood($context->{from}, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'pbot', $line, 0, 0, 0) if $context->{checkflood};
    }
}

sub add_message_to_output_queue {
    my ($self, $channel, $message, $delay) = @_;

    $self->{pbot}->{timer}->enqueue_event(
        sub {
            my $context = {
                from       => $channel,
                nick       => $message->{nick},
                user       => $message->{user},
                host       => $message->{host},
                line       => $message->{message},
                command    => $message->{command},
                checkflood => $message->{checkflood}
            };

            $self->output_result($context);
        },
        $delay, "output $channel $message->{message}"
    );
}

sub add_to_command_queue {
    my ($self, $channel, $command, $delay, $repeating) = @_;

    $self->{pbot}->{timer}->enqueue_event(
        sub {
            my $context = {
                from                => $channel,
                nick                => $command->{nick},
                user                => $command->{user},
                host                => $command->{host},
                command             => $command->{command},
                interpret_depth     => 0,
                checkflood          => 0,
                preserve_whitespace => 0
            };

            if (exists $command->{'cap-override'}) {
                $self->{pbot}->{logger}->log("[command queue] Override command capability with $command->{'cap-override'}\n");
                $context->{'cap-override'} = $command->{'cap-override'};
            }

            my $result = $self->interpret($context);
            $context->{result} = $result;
            $self->handle_result($context, $result);
        },
        $delay, "command $channel $command->{command}", $repeating
    );
}

sub add_botcmd_to_command_queue {
    my ($self, $channel, $command, $delay) = @_;

    my $botcmd = {
        nick    => $self->{pbot}->{registry}->get_value('irc', 'botnick'),
        user    => 'stdin',
        host    => 'pbot',
        command => $command
    };

    $self->add_to_command_queue($channel, $botcmd, $delay);
}

1;
