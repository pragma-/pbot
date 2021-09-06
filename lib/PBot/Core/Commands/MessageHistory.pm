# File: MessageHistory.pm
#
# Purpose: Registers commands related to a user's message history or aliases.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::MessageHistory;

use PBot::Imports;
use parent 'PBot::Core::Class';

use Time::HiRes qw(time tv_interval);
use Time::Duration;

sub initialize {
    my ($self, %conf) = @_;

    # unprivileged commands
    $self->{pbot}->{commands}->register(sub { $self->cmd_list_also_known_as(@_) }, "aka",            0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_recall_message(@_) },     "recall",         0);

    # commands with the can- capability set
    $self->{pbot}->{commands}->register(sub { $self->cmd_rebuild_aliases(@_) },    "rebuildaliases", 1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_aka_link(@_) },           "akalink",        1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_aka_unlink(@_) },         "akaunlink",      1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_aka_delete(@_) },         "akadelete",      1);

    # add capabilities to admin group
    $self->{pbot}->{capabilities}->add('admin', 'can-akalink',   1);
    $self->{pbot}->{capabilities}->add('admin', 'can-akaunlink', 1);
    $self->{pbot}->{capabilities}->add('admin', 'can-akadelete', 1);
}

sub cmd_list_also_known_as {
    my ($self, $context) = @_;

    my $usage = "Usage: aka [-hilngr] <nick> [-sort <by>]; -h show hostmasks; -i show ids; -l show last seen, -n show nickserv accounts; -g show gecos, -r show relationships";

    if (not length $context->{arguments}) {
        return $usage;
    }

    my ($show_hostmasks, $show_gecos, $show_nickserv, $show_id, $show_relationship, $show_weak, $show_last_seen, $dont_use_aliases_table, $sort_method);

    my %opts = (
        h    => \$show_hostmasks,
        i    => \$show_id,
        l    => \$show_last_seen,
        n    => \$show_nickserv,
        g    => \$show_gecos,
        r    => \$show_relationship,
        w    => \$show_weak,
        z    => \$dont_use_aliases_table,
        sort => \$sort_method,
    );

    my ($opt_args, $opt_error) = $self->{pbot}->{interpreter}->getopt(
        $context->{arguments},
        \%opts,
        ['bundling_override'],
        qw(h i l n g r w z sort|s=s),
    );

    return "/say $opt_error -- $usage"    if defined $opt_error;
    return "Too many arguments -- $usage" if @$opt_args > 1;
    return "Missing argument -- $usage"   if @$opt_args != 1;

    $sort_method = 'seen' if $show_last_seen and not defined $sort_method;
    $sort_method = 'nick' if not defined $sort_method;

    my %sort = (
        'id' => sub {
            if ($_[1] eq '+') {
                return $_[0]->{$a}->{id} <=> $_[0]->{$b}->{id};
            } else {
                return $_[0]->{$b}->{id} <=> $_[0]->{$a}->{id};
            }
        },

        'seen' => sub {
            if ($_[1] eq '+') {
                return $_[0]->{$b}->{last_seen} <=> $_[0]->{$a}->{last_seen};
            } else {
                return $_[0]->{$a}->{last_seen} <=> $_[0]->{$b}->{last_seen};
            }
        },

        'nickserv' => sub {
            if ($_[1] eq '+') {
                return lc $_[0]->{$a}->{nickserv} cmp lc $_[0]->{$b}->{nickserv};
            } else {
                return lc $_[0]->{$b}->{nickserv} cmp lc $_[0]->{$a}->{nickserv};
            }
        },

        'nick' => sub {
            if ($_[1] eq '+') {
                return lc $_[0]->{$a}->{nick} cmp lc $_[0]->{$b}->{nick};
            } else {
                return lc $_[0]->{$b}->{nick} cmp lc $_[0]->{$a}->{nick};
            }
        },

        'user' => sub {
            if ($_[1] eq '+') {
                return lc $_[0]->{$a}->{user} cmp lc $_[0]->{$b}->{user};
            } else {
                return lc $_[0]->{$b}->{user} cmp lc $_[0]->{$a}->{user};
            }
        },

        'host' => sub {
            if ($_[1] eq '+') {
                return lc $_[0]->{$a}->{host} cmp lc $_[0]->{$b}->{host};
            } else {
                return lc $_[0]->{$b}->{host} cmp lc $_[0]->{$a}->{host};
            }
        },

        'hostmask' => sub {
            if ($_[1] eq '+') {
                return lc $_[0]->{$a}->{hostmask} cmp lc $_[0]->{$b}->{hostmask};
            } else {
                return lc $_[0]->{$b}->{hostmask} cmp lc $_[0]->{$a}->{hostmask};
            }
        },

        'gecos' => sub {
            if ($_[1] eq '+') {
                return lc $_[0]->{$a}->{gecos} cmp lc $_[0]->{$b}->{gecos};
            } else {
                return lc $_[0]->{$b}->{gecos} cmp lc $_[0]->{$a}->{gecos};
            }
        },
    );

    my $sort_direction = '+';
    if ($sort_method =~ s/^(\+|\-)//) {
        $sort_direction = $1;
    }

    if (not exists $sort{$sort_method}) {
        return "Invalid sort method '$sort_method'; valid methods are: " . join(', ', sort keys %sort) . "; prefix with - to invert sort direction.";
    }

    my %akas = $self->{pbot}->{messagehistory}->{database}->get_also_known_as($opt_args->[0], $dont_use_aliases_table);

    if (%akas) {
        my $result = "$opt_args->[0] also known as:\n";

        my %nicks;
        my $sep = "";
        foreach my $aka (sort { $sort{$sort_method}->(\%akas, $sort_direction) } keys %akas) {
            next if $aka =~ /^Guest\d+(?:!.*)?$/;
            next if exists $akas{$aka}->{type} and $akas{$aka}->{type} == $self->{pbot}->{messagehistory}->{database}->{alias_type}->{WEAK} && not $show_weak;

            if (not $show_hostmasks) {
                my ($nick) = $aka =~ m/([^!]+)/;
                next if exists $nicks{$nick};
                $nicks{$nick}->{id} = $akas{$aka}->{id};
                $result .= "$sep$nick";
            } else {
                $result .= "$sep$aka";
            }

            $result .= "?"                          if $akas{$aka}->{nickchange} == 1;
            $result .= " ($akas{$aka}->{nickserv})" if $show_nickserv and exists $akas{$aka}->{nickserv};
            $result .= " {$akas{$aka}->{gecos}}"    if $show_gecos and exists $akas{$aka}->{gecos};

            if ($show_relationship) {
                if ($akas{$aka}->{id} == $akas{$aka}->{alias}) {
                    $result .= " [$akas{$aka}->{id}]";
                } else {
                    $result .= " [$akas{$aka}->{id} -> $akas{$aka}->{alias}]";
                }
            } elsif ($show_id) {
                $result .= " [$akas{$aka}->{id}]";
            }

            $result .= " [WEAK]" if exists $akas{$aka}->{type} and $akas{$aka}->{type} == $self->{pbot}->{messagehistory}->{database}->{alias_type}->{WEAK};

            if ($show_last_seen) {
                my $seen = concise ago (time - $akas{$aka}->{last_seen});
                $result .= " (seen $seen)";
            }

            if ($show_hostmasks or $show_nickserv or $show_gecos or $show_id or $show_relationship) {
                $sep = ",\n";
            } else {
                $sep = ", ";
            }
        }
        return $result;
    } else {
        return "I don't know anybody named $opt_args->[0].";
    }
}

sub cmd_recall_message {
    my ($self, $context) = @_;

    my $usage = 'Usage: recall [nick [history [channel]]] [-c <channel>] [-t <text>] [-b <context before>] [-a <context after>] [-x <filter to nick>] [-n <count>] [-r raw mode] [+ ...]';

    my $arguments = $context->{arguments};

    if (not length $arguments) {
        return $usage;
    }

    $arguments = lc $arguments;

    my @recalls = split /\s\+\s/, $arguments;

    my $result = '';

    # global state
    my ($recall_channel, $raw, $random);

    foreach my $recall (@recalls) {
        my ($recall_nick, $recall_text, $recall_history, $recall_before, $recall_after, $recall_context, $recall_count);

        my %opts = (
            'channel'  => \$recall_channel,
            'history'  => \$recall_history,
            'text'     => \$recall_text,
            'before'   => \$recall_before,
            'after'    => \$recall_after,
            'count'    => \$recall_count,
            'context'  => \$recall_context,
            'raw'      => \$raw,
            'random'   => \$random,
        );

        my ($opt_args, $opt_error) = $self->{pbot}->{interpreter}->getopt(
            $recall,
            \%opts,
            ['bundling_override'],
            'channel|c=s',
            'history|h=s',
            'text|t=s',
            'before|b=i',
            'after|a=i',
            'count|n=i',
            'context|x=s',
            'raw|r',
            'random',
        );

        return "/say $opt_error -- $usage" if defined $opt_error;

        if (defined $recall_history and defined $recall_text) {
            return "/say $context->{nick}: The -h and -t options cannot be used together.";
        }

        # we swap these $recall variables around so much later on that we
        # need to remember which flags were explicitly set...
        my $channel_arg = 1 if defined $recall_channel;
        my $history_arg = 1 if defined $recall_history;

        $recall_nick    = shift @$opt_args if @$opt_args;
        $recall_history = shift @$opt_args if @$opt_args and not $history_arg and not defined $recall_text;

        if (not $channel_arg) {
            $recall_channel = "@$opt_args" if @$opt_args;
        } else {
            if (defined $recall_history) {
                $recall_history .= ' ';
            }
            $recall_history .= "@$opt_args" if @$opt_args;
        }

        if (defined $recall_text and not defined $recall_history) {
            $recall_history = $recall_text;
        }

        my $max_count = $self->{pbot}->{registry}->get_value('messagehistory', 'max_recall_count') // 50;

        if ((not defined $recall_count) || ($recall_count <= 0)) {
            $recall_count = 1;
        }

        if ($recall_count > $max_count) {
            return "You may only select a count of up to $max_count messages.";
        }

        $recall_before = 0 if not defined $recall_before;
        $recall_after  = 0 if not defined $recall_after;

        # imply -x if -n > 1 and -x isn't already set to somebody
        if ($recall_count > 1 and not defined $recall_context) {
            $recall_context = $recall_nick;
        }

        # make -n behave like -b if -n > 1 and no history is specified
        if (not defined $recall_history and $recall_count > 1) {
            $recall_before = $recall_count - 1;
            $recall_count  = 0;
        }

        if ($recall_before + $recall_after > 100) { return "You may only select up to 100 lines of surrounding context."; }

        if ($recall_count > 1 and ($recall_before > 0 or $recall_after > 0)) { return "The `count` and `before/after` options cannot be used together."; }

        # swap nick and channel if recall nick looks like channel and channel wasn't specified
        if (not $channel_arg and $recall_nick =~ m/^#/) {
            my $temp = $recall_nick;
            $recall_nick    = $recall_channel;
            $recall_channel = $temp;
        }

        $recall_history = 1 if not defined $recall_history;

        # swap history and channel if history looks like a channel and neither history or channel were specified
        if (not $channel_arg and not $history_arg and $recall_history =~ m/^#/) {
            my $temp = $recall_history;
            $recall_history = $recall_channel;
            $recall_channel = $temp;
        }

        # skip recall command if recalling self without arguments
        if (defined $recall_nick and not defined $recall_history) {
            $recall_history = $context->{nick} eq $recall_nick ? 2 : 1;
        }

        # set history to most recent message if not specified
        $recall_history = '1' if not defined $recall_history;

        # set channel to current channel if not specified
        $recall_channel = $context->{from} if not defined $recall_channel;

        # yet another sanity check for people using it wrong
        if ($recall_channel !~ m/^#/) {
            $recall_history = "$recall_history $recall_channel";
            $recall_channel = $context->{from};
        }

        # set nick argument to -x argument if no nick was provided but -x was
        if (not defined $recall_nick and defined $recall_context) {
            $recall_nick = $recall_context;
        }

        # message account and stored nickname with proper typographical casing
        my ($account, $found_nick);

        # get message account and found nick if a nick was provided
        if (defined $recall_nick) {
            # account and hostmask
            ($account, $found_nick) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($recall_nick);

            if (not defined $account) {
                return "I don't know anybody named $recall_nick.";
            }

            # keep only nick portion of hostmask
            $found_nick =~ s/!.*$//;
        }

        # matching message found in database, if any
        my $message;

        if ($random) {
            # get a random message
            $message = $self->{pbot}->{messagehistory}->{database}->get_random_message($account, $recall_channel, $recall_nick);
        } elsif ($recall_history =~ /^\d+$/ and not defined $recall_text) {
            # integral history

            # if a nick was given, ensure requested history is within range of nick's history count
            if (defined $account) {
                my $max_messages = $self->{pbot}->{messagehistory}->{database}->get_max_messages($account, $recall_channel, $recall_nick);
                if ($recall_history < 1 || $recall_history > $max_messages) {
                    if ($max_messages == 0) {
                        return "No messages for $recall_nick in $recall_channel yet.";
                    } else {
                        return "Please choose a history between 1 and $max_messages";
                    }
                }
            }

            $recall_history--;
            $message = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($account, $recall_channel, $recall_history, '(?:recall|mock|ftfy|fix|clapper)', $recall_nick);

            if (not defined $message) {
                if (defined $account) {
                    return "No message found at index $recall_history for $found_nick in $recall_channel.";
                } else {
                    return "No message found at index $recall_history in $recall_channel.";
                }
            }
        } else {
            # regex history
            $message = $self->{pbot}->{messagehistory}->{database}->recall_message_by_text($account, $recall_channel, $recall_history, '(?:recall|mock|ftfy|fix|clapper)', $recall_nick);

            if (not defined $message) {
                if (defined $account) {
                    return "No message for $found_nick in $recall_channel containing \"$recall_history\"";
                } else {
                    return "No message in $recall_channel containing \"$recall_history\".";
                }
            }
        }

        my ($context_account, $context_nick);

        if (defined $recall_context) {
            ($context_account, $context_nick) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($recall_context);

            if (not defined $context_account) {
                return "I don't know anybody named $recall_context.";
            }

            # keep only nick portion of hostmask
            $context_nick =~ s/!.*$//;
        }

        my $messages = $self->{pbot}->{messagehistory}->{database}->get_message_context($message, $recall_before, $recall_after, $recall_count, $recall_history, $context_account, $context_nick);

        my $max_recall_time = $self->{pbot}->{registry}->get_value('messagehistory', 'max_recall_time');

        foreach my $msg (@$messages) {
            # optionally limit messages by by a maximum recall duration from the current time, for privacy
            if ($max_recall_time && time - $msg->{timestamp} > $max_recall_time
                && not $self->{pbot}->{users}->loggedin_admin($context->{from}, $context->{hostmask}))
            {
                $max_recall_time = duration $max_recall_time;
                $result .= "Sorry, you can not recall messages older than $max_recall_time.";
                return $result;
            }

            my $text = $msg->{msg};
            my $ago  = concise ago (time - $msg->{timestamp});
            my $nick;

            if (not $raw) {
                if ($msg->{hostmask}) {
                    ($nick) = $msg->{hostmask} =~ /^([^!]+)!/;
                } else {
                    $nick = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($msg->{id});
                    ($nick) = $nick =~ m/^([^!]+)/;
                }
            }

            if (   $text =~ s/^(NICKCHANGE)\b/changed nick to/
                or $text =~ s/^(KICKED|QUIT)\b/lc "$1"/e
                or $text =~ s/^MODE ([^ ]+) (.*)/set mode $1 on $2/
                or $text =~ s/^(JOIN|PART)\b/lc "$1ed"/e)
            {
                $text =~ s/^(quit) (.*)/$1 ($2)/; # fix ugly "[nick] quit Quit: Leaving."
                $result .= $raw ? "$text\n" : "[$ago] $nick $text\n";
            }
            elsif ($text =~ s/^\/me\s+//) {
                $result .= $raw ? "$text\n" : "[$ago] * $nick $text\n";
            }
            else {
                $result .= $raw ? "$text\n" : "[$ago] <$nick> $text\n";
            }
        }
    }

    return $result;
}

sub cmd_rebuild_aliases {
    my ($self, $context) = @_;
    $self->{pbot}->{messagehistory}->{database}->rebuild_aliases_table;
}

sub cmd_aka_link {
    my ($self, $context) = @_;

    my ($id, $alias, $type) = split /\s+/, $context->{arguments};

    $type = $self->{pbot}->{messagehistory}->{database}->{alias_type}->{STRONG} if not defined $type;

    if (not $id or not $alias) {
        return "Usage: akalink <target id> <alias id> [type]";
    }

    my $source = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($id);
    my $target = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($alias);

    if (not $source) {
        return "No such id $id found.";
    }

    if (not $target) {
        return "No such id $alias found.";
    }

    if ($self->{pbot}->{messagehistory}->{database}->link_alias($id, $alias, $type)) {
        return "/say $source " . ($type == $self->{pbot}->{messagehistory}->{database}->{alias_type}->{WEAK} ? "weakly" : "strongly") . " linked to $target.";
    } else {
        return "Link failed.";
    }
}

sub cmd_aka_unlink {
    my ($self, $context) = @_;

    my ($id, $alias) = split /\s+/, $context->{arguments};

    if (not $id or not $alias) {
        return "Usage: akaunlink <target id> <alias id>";
    }

    my $source = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($id);
    my $target = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($alias);

    if (not $source) {
        return "No such id $id found.";
    }

    if (not $target) {
        return "No such id $alias found.";
    }

    if ($self->{pbot}->{messagehistory}->{database}->unlink_alias($id, $alias)) {
        return "/say $source unlinked from $target.";
    } else {
        return "Unlink failed.";
    }
}

sub cmd_aka_delete {
    my ($self, $context) = @_;

    my $usage = "Usage: akadelete [-hn] <account id or hostmask>; -h delete only hostmask; -n delete only nickserv";

    if (not length $context->{arguments}) {
        return $usage;
    }

    my ($delete_hostmask, $delete_nickserv);

    my %opts = (
        h  => \$delete_hostmask,
        n  => \$delete_nickserv,
    );

    my ($opt_args, $opt_error) = $self->{pbot}->{interpreter}->getopt(
        $context->{arguments},
        \%opts,
        ['bundling_override'],
        qw(h n),
    );

    return "/say $opt_error -- $usage"    if defined $opt_error;
    return "Too many arguments -- $usage" if @$opt_args > 1;
    return "Missing argument -- $usage"   if @$opt_args != 1;

    my $id = $opt_args->[0];

    my $hostmask;

    if ($id !~ /^\d+$/) {
        $hostmask = $id;
        $id = $self->{pbot}->{messagehistory}->{database}->get_message_account_id($hostmask);

        if (not defined $id) {
            return "No such hostmask $hostmask found.";
        }
    } else {
        $hostmask = $self->{pbot}->{messagehistory}->{database}->find_most_recent_hostmask($id);

        if (not defined $hostmask) {
            return "No such id $id found.";
        }
    }

    my @deletions;

    if ($delete_hostmask) {
        $self->{pbot}->{messagehistory}->{database}->delete_hostmask($id, $hostmask);
        push @deletions, 'hostmask';
    }

    if ($delete_nickserv) {
        $self->{pbot}->{messagehistory}->{database}->delete_nickserv_accounts($id);
        $self->{pbot}->{messagehistory}->{database}->set_current_nickserv_account($id, undef);
        push @deletions, 'NickServ accounts';
    }

    if ($delete_hostmask || $delete_nickserv) {
        return 'Deleted ' . (join ' and ', @deletions) . " from $hostmask ($id)";
    }

    $self->{pbot}->{messagehistory}->{database}->delete_account($id);

    return "/say Deleted $hostmask ($id).";
}

1;
