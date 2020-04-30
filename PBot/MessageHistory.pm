# File: MessageHistory.pm
# Author: pragma_
#
# Purpose: Keeps track of who has said what and when, as well as their
# nickserv accounts and alter-hostmasks.
#
# Used in conjunction with AntiFlood and Quotegrabs for kick/ban on
# flood/ban-evasion and grabbing quotes, respectively.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::MessageHistory;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use Getopt::Long qw(GetOptionsFromArray);
use Time::HiRes qw(gettimeofday tv_interval);
use Time::Duration;

use PBot::MessageHistory_SQLite;

sub initialize {
    my ($self, %conf) = @_;
    $self->{filename} = $conf{filename} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/message_history.sqlite3';

    $self->{database} = PBot::MessageHistory_SQLite->new(pbot => $self->{pbot}, filename => $self->{filename});
    $self->{database}->begin();
    $self->{database}->devalidate_all_channels();

    $self->{MSG_CHAT}       = 0;    # PRIVMSG, ACTION
    $self->{MSG_JOIN}       = 1;    # JOIN
    $self->{MSG_DEPARTURE}  = 2;    # PART, QUIT, KICK
    $self->{MSG_NICKCHANGE} = 3;    # CHANGED NICK

    $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'max_recall_time', $conf{max_recall_time} // 0);
    $self->{pbot}->{registry}->add_default('text', 'messagehistory', 'max_messages',    32);

    $self->{pbot}->{commands}->register(sub { $self->recall_message(@_) },     "recall",         0);
    $self->{pbot}->{commands}->register(sub { $self->list_also_known_as(@_) }, "aka",            0);
    $self->{pbot}->{commands}->register(sub { $self->rebuild_aliases(@_) },    "rebuildaliases", 1);
    $self->{pbot}->{commands}->register(sub { $self->aka_link(@_) },           "akalink",        1);
    $self->{pbot}->{commands}->register(sub { $self->aka_unlink(@_) },         "akaunlink",      1);

    $self->{pbot}->{capabilities}->add('admin', 'can-akalink',   1);
    $self->{pbot}->{capabilities}->add('admin', 'can-akaunlink', 1);

    $self->{pbot}->{atexit}->register(sub { $self->{database}->end(); return; });
}

sub get_message_account {
    my ($self, $nick, $user, $host) = @_;
    return $self->{database}->get_message_account($nick, $user, $host);
}

sub add_message {
    my ($self, $account, $mask, $channel, $text, $mode) = @_;
    $self->{database}->add_message($account, $mask, $channel, {timestamp => scalar gettimeofday, msg => $text, mode => $mode});
}

sub rebuild_aliases {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;

    $self->{database}->rebuild_aliases_table;
}

sub aka_link {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;

    my ($id, $alias, $type) = split /\s+/, $arguments;

    $type = $self->{database}->{alias_type}->{STRONG} if not defined $type;

    if (not $id or not $alias) { return "Usage: link <target id> <alias id> [type]"; }

    my $source = $self->{database}->find_most_recent_hostmask($id);
    my $target = $self->{database}->find_most_recent_hostmask($alias);

    if (not $source) { return "No such id $id found."; }

    if (not $target) { return "No such id $alias found."; }

    if ($self->{database}->link_alias($id, $alias, $type)) {
        return "/say $source " . ($type == $self->{database}->{alias_type}->{WEAK} ? "weakly" : "strongly") . " linked to $target.";
    } else {
        return "Link failed.";
    }
}

sub aka_unlink {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;

    my ($id, $alias) = split /\s+/, $arguments;

    if (not $id or not $alias) { return "Usage: unlink <target id> <alias id>"; }

    my $source = $self->{database}->find_most_recent_hostmask($id);
    my $target = $self->{database}->find_most_recent_hostmask($alias);

    if (not $source) { return "No such id $id found."; }

    if (not $target) { return "No such id $alias found."; }

    if   ($self->{database}->unlink_alias($id, $alias)) { return "/say $source unlinked from $target."; }
    else                                                { return "Unlink failed."; }
}

sub list_also_known_as {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;

    my $usage = "Usage: aka [-hingr] <nick>; -h show hostmasks; -i show ids; -n show nickserv accounts; -g show gecos, -r show relationships";

    if (not length $arguments) { return $usage; }

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    Getopt::Long::Configure("bundling");

    my ($show_hostmasks, $show_gecos, $show_nickserv, $show_id, $show_relationship, $show_weak, $dont_use_aliases_table);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($arguments, strip_quotes => 1);
    GetOptionsFromArray(
        \@opt_args,
        'h'  => \$show_hostmasks,
        'n'  => \$show_nickserv,
        'r'  => \$show_relationship,
        'g'  => \$show_gecos,
        'w'  => \$show_weak,
        'nt' => \$dont_use_aliases_table,
        'i'  => \$show_id
    );

    return "/say $getopt_error -- $usage" if defined $getopt_error;
    return "Too many arguments -- $usage" if @opt_args > 1;
    return "Missing argument -- $usage"   if @opt_args != 1;

    my %akas = $self->{database}->get_also_known_as($opt_args[0], $dont_use_aliases_table);

    if (%akas) {
        my $result = "$opt_args[0] also known as:\n";

        my %nicks;
        my $sep = "";
        foreach my $aka (sort keys %akas) {
            next if $aka =~ /^Guest\d+(?:!.*)?$/;
            next if $akas{$aka}->{type} == $self->{database}->{alias_type}->{WEAK} && not $show_weak;

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
                if   ($akas{$aka}->{id} == $akas{$aka}->{alias}) { $result .= " [$akas{$aka}->{id}]"; }
                else                                             { $result .= " [$akas{$aka}->{id} -> $akas{$aka}->{alias}]"; }
            } elsif ($show_id) {
                $result .= " [$akas{$aka}->{id}]";
            }

            $result .= " [WEAK]" if $akas{$aka}->{type} == $self->{database}->{alias_type}->{WEAK};

            if   ($show_hostmasks or $show_nickserv or $show_gecos or $show_id or $show_relationship) { $sep = ",\n"; }
            else                                                                                      { $sep = ", "; }
        }
        return $result;
    } else {
        return "I don't know anybody named $opt_args[0].";
    }
}

sub recall_message {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;

    if (not defined $from) {
        $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
        return "";
    }

    my $usage =
      'Usage: recall [nick [history [channel]]] [-c <channel>] [-t <text>] [-b <context before>] [-a <context after>] [-x <filter to nick>] [-n <count>] [-r raw mode] [+ ...]';

    if (not defined $arguments or not length $arguments) { return $usage; }

    $arguments = lc $arguments;

    my @recalls = split /\s\+\s/, $arguments;

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    my $recall_text = '';
    Getopt::Long::Configure("bundling_override");

    # global state
    my ($recall_channel, $raw, $random);

    foreach my $recall (@recalls) {
        my ($recall_nick, $recall_history, $recall_before, $recall_after, $recall_context, $recall_count);

        my @opt_args = $self->{pbot}->{interpreter}->split_line($recall, strip_quotes => 1);
        GetOptionsFromArray(
            \@opt_args,
            'channel|c:s'        => \$recall_channel,
            'text|t|history|h:s' => \$recall_history,
            'before|b:i'         => \$recall_before,
            'after|a:i'          => \$recall_after,
            'count|n:i'          => \$recall_count,
            'context|x:s'        => \$recall_context,
            'raw|r'              => \$raw,
            'random'             => \$random,
        );

        return "/say $getopt_error -- $usage" if defined $getopt_error;

        my $channel_arg = 1 if defined $recall_channel;
        my $history_arg = 1 if defined $recall_history;

        $recall_nick    = shift @opt_args if @opt_args;
        $recall_history = shift @opt_args if @opt_args and not $history_arg;
        $recall_channel = "@opt_args" if @opt_args and not $channel_arg;

        $recall_count = 1 if (not defined $recall_count) || ($recall_count <= 0);
        return "You may only select a count of up to 100 messages." if $recall_count > 100;

        $recall_before = 0 if not defined $recall_before;
        $recall_after  = 0 if not defined $recall_after;

        # imply -x if -n > 1 and no history and -x isn't already set to somebody
        if ($recall_count > 1 and not defined $recall_history and not defined $recall_context) { $recall_context = $recall_nick; }

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
        $recall_history = $nick eq $recall_nick ? 2 : 1 if defined $recall_nick and not defined $recall_history;

        # set history to most recent message if not specified
        $recall_history = '1' if not defined $recall_history;

        # set channel to current channel if not specified
        $recall_channel = $from if not defined $recall_channel;

        # yet another sanity check for people using it wrong
        if ($recall_channel !~ m/^#/) {
            $recall_history = "$recall_history $recall_channel";
            $recall_channel = $from;
        }

        if (not defined $recall_nick and defined $recall_context) { $recall_nick = $recall_context; }

        my ($account, $found_nick);

        if (defined $recall_nick) {
            ($account, $found_nick) = $self->{database}->find_message_account_by_nick($recall_nick);

            if (not defined $account) { return "I don't know anybody named $recall_nick."; }

            $found_nick =~ s/!.*$//;
        }

        my $message;

        if ($random) {
            $message = $self->{database}->get_random_message($account, $recall_channel);
        } elsif ($recall_history =~ /^\d+$/) {
            # integral history
            if (defined $account) {
                my $max_messages = $self->{database}->get_max_messages($account, $recall_channel);
                if ($recall_history < 1 || $recall_history > $max_messages) {
                    if ($max_messages == 0) {
                        return "No messages for $recall_nick in $recall_channel yet.";
                    } else {
                        return "Please choose a history between 1 and $max_messages";
                    }
                }
            }

            $recall_history--;
            $message = $self->{database}->recall_message_by_count($account, $recall_channel, $recall_history, '(?:recall|mock|ftfy|fix|clapper)');

            if (not defined $message) { return "No message found at index $recall_history in channel $recall_channel."; }
        } else {
            # regex history
            $message = $self->{database}->recall_message_by_text($account, $recall_channel, $recall_history, '(?:recall|mock|ftfy|fix|clapper)');

            if (not defined $message) {
                if   (defined $account) { return "No message for nick $found_nick in channel $recall_channel containing \"$recall_history\""; }
                else                    { return "No message in channel $recall_channel containing \"$recall_history\"."; }
            }
        }

        my $context_account;

        if (defined $recall_context) {
            ($context_account) = $self->{database}->find_message_account_by_nick($recall_context);

            if (not defined $context_account) { return "I don't know anybody named $recall_context."; }
        }

        if ($from =~ /^#/ and ($recall_count > 5 or $recall_after > 5 or $recall_before > 5)) {
            return "Please use `recall` from private message when recalling multiple messages. Just add \"-c $from\" to the command and /msg it to me.";
        }

        my $messages = $self->{database}->get_message_context($message, $recall_before, $recall_after, $recall_count, $recall_history, $context_account);

        my $max_recall_time = $self->{pbot}->{registry}->get_value('messagehistory', 'max_recall_time');

        foreach my $msg (@$messages) {
            if ($max_recall_time && gettimeofday - $msg->{timestamp} > $max_recall_time && not $self->{pbot}->{users}->loggedin_admin($from, "$nick!$user\@$host")) {
                $max_recall_time = duration($max_recall_time);
                $recall_text .= "Sorry, you can not recall messages older than $max_recall_time.";
                return $recall_text;
            }

            my $text = $msg->{msg};
            my $ago  = concise ago(gettimeofday - $msg->{timestamp});

            if (   $text =~ s/^(NICKCHANGE)\b/changed nick to/
                or $text =~ s/^(KICKED|QUIT)\b/lc "$1"/e
                or $text =~ s/^MODE ([^ ]+) (.*)/set mode $1 on $2/
                or $text =~ s/^(JOIN|PART)\b/lc "$1ed"/e)
            {
                $text =~ s/^(quit) (.*)/$1 ($2)/;    # fix ugly "[nick] quit Quit: Leaving."
                $recall_text .= $raw ? "$text\n" : "[$ago] $msg->{nick} $text\n";
            } elsif ($text =~ s/^\/me\s+//) {
                $recall_text .= $raw ? "$text\n" : "[$ago] * $msg->{nick} $text\n";
            } else {
                $recall_text .= $raw ? "$text\n" : "[$ago] <$msg->{nick}> $text\n";
            }
        }
    }

    return $recall_text;
}

1;
