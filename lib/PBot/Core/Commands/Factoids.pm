# File: Factoids.pm
#
# Purpose: Factoids command subroutines.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Factoids;

use PBot::Imports;
use parent 'PBot::Core::Class';

use Time::Duration;
use Time::HiRes qw(gettimeofday);
use Getopt::Long qw(GetOptionsFromArray);
use POSIX qw(strftime);
use Storable;
use LWP::UserAgent;
use JSON;

use PBot::Core::Utils::SafeFilename;

our %factoid_metadata_capabilities = (
    created_on                => 'botowner',
    enabled                   => 'chanop',
    last_referenced_in        => 'botowner',
    last_referenced_on        => 'botowner',
    owner                     => 'botowner',
    rate_limit                => 'chanop',
    ref_count                 => 'botowner',
    ref_user                  => 'botowner',
    type                      => 'botowner',
    edited_by                 => 'botowner',
    edited_on                 => 'botowner',
    locked                    => 'chanop',
    add_nick                  => 'chanop',
    nooverride                => 'chanop',
    'cap-override'            => 'botowner',
    'persist-key'             => 'admin',

    # all others are allowed to be factset by anybody
);

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{registry}->add_default('text', 'general', 'module_repo', $conf{module_repo}
        // 'https://github.com/pragma-/pbot/blob/master/modules/');

    $self->{pbot}->{commands}->register(sub { $self->cmd_factadd(@_) },      "learn",      0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factadd(@_) },      "factadd",    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factrem(@_) },      "forget",     0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factrem(@_) },      "factrem",    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factshow(@_) },     "factshow",   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factinfo(@_) },     "factinfo",   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factlog(@_) },      "factlog",    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factundo(@_) },     "factundo",   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factredo(@_) },     "factredo",   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factset(@_) },      "factset",    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factunset(@_) },    "factunset",  0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factchange(@_) },   "factchange", 0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factalias(@_) },    "factalias",  0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factmove(@_) },     "factmove",   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_call_factoid(@_) }, "fact",       0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_factfind(@_) },     "factfind",   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_top20(@_) },        "top20",      0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_histogram(@_) },    "histogram",  0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_count(@_) },        "count",      0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_add_regex(@_) },    "regex",      1);
}

sub cmd_call_factoid {
    my ($self, $context) = @_;
    my ($chan, $keyword, $args) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3, 0, 1);

    if (not defined $chan or not defined $keyword) { return "Usage: fact <channel> <keyword> [arguments]"; }

    my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $keyword, arguments => $args, exact_channel => 1, exact_trigger => 1);

    if (not defined $trigger) { return "No such factoid $keyword exists for $chan"; }

    $context->{keyword}      = $trigger;
    $context->{trigger}      = $trigger;
    $context->{ref_from}     = $channel;
    $context->{arguments}    = $args;
    $context->{root_keyword} = $trigger;

    return $self->{pbot}->{factoids}->interpreter($context);
}

sub cmd_factundo {
    my ($self, $context) = @_;
    my $usage = "Usage: factundo [-l [N]] [-r N] [channel] <keyword> (-l list undo history, optionally starting from N; -r jump to revision N)";

    my $arguments = $context->{arguments};

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    my ($list_undos, $goto_revision);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($arguments, strip_quotes => 1);
    GetOptionsFromArray(
        \@opt_args,
        'l:i' => \$list_undos,
        'r=i' => \$goto_revision
    );

    return "/say $getopt_error -- $usage" if defined $getopt_error;
    return $usage                         if @opt_args > 2;
    return $usage                         if not @opt_args;

    $arguments = join(' ', map { $_ = "'$_'" if $_ =~ m/ /; $_; } @opt_args);
    my $arglist = $self->{pbot}->{interpreter}->make_args($arguments);

    my ($channel, $trigger) = $self->find_factoid_with_optional_channel(
        $context->{from}, $context->{arguments}, 'factundo', explicit => 1, exact_channel => 1
    );

    my $deleted;

    if (not defined $trigger) {
        # factoid not found or some error, try to continue and load undo file if it exists
        $deleted = 1;
        ($channel, $trigger) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
        if (not defined $trigger) {
            $trigger = $channel;
            $channel = $context->{from};
        }
        $channel = '.*' if $channel !~ m/^#/;
    }

    my $channel_path = $channel;
    $channel_path = 'global' if $channel_path eq '.*';

    my $channel_path_safe = safe_filename $channel_path;
    my $trigger_safe      = safe_filename $trigger;

    my $path  = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factlog';
    my $undos = eval { retrieve("$path/$trigger_safe.$channel_path_safe.undo"); };

    my $channel_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, '_name');
    my $trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, '_name');

    $channel_name = 'global'            if $channel_name eq '.*';
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    if (not $undos) { return "There are no undos available for [$channel_name] $trigger_name."; }

    if (defined $list_undos) {
        $list_undos = 1 if $list_undos == 0;
        return $self->list_undo_history($undos, $list_undos);
    }

    my $factoids = $self->{pbot}->{factoids}->{storage};
    my $userinfo = $self->{pbot}->{users}->loggedin($channel, $context->{hostmask});
    if ($factoids->get_data($channel, $trigger, 'locked')) {
        return "/say $trigger_name is locked and cannot be reverted." if not $self->{pbot}->{capabilities}->userhas($userinfo, 'admin');

        if ($factoids->exists($channel, $trigger, 'cap-override') and not $self->{pbot}->{capabilities}->userhas($userinfo, 'botowner')) {
            return "/say $trigger_name is locked with a cap-override and cannot be reverted. Unlock the factoid first.";
        }
    }

    if (defined $goto_revision) {
        return "Don't be absurd." if $goto_revision < 1;
        if ($goto_revision > @{$undos->{list}}) {
            if   (@{$undos->{list}} == 1) { return "There is only one revision available for [$channel_name] $trigger_name."; }
            else                          { return "There are " . @{$undos->{list}} . " revisions available for [$channel_name] $trigger_name."; }
        }

        if ($goto_revision == $undos->{idx} + 1) { return "[$channel_name] $trigger_name is already at revision $goto_revision."; }

        $undos->{idx} = $goto_revision - 1;
        eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
        $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
    } else {
        unless ($deleted) {
            return "There are no more undos remaining for [$channel_name] $trigger_name." if not $undos->{idx};
            $undos->{idx}--;
            eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
            $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
        }
    }

    $self->{pbot}->{factoids}->{storage}->add($channel, $trigger, $undos->{list}->[$undos->{idx}], 0, 1);

    my $changes = $self->hash_differences_as_string($undos->{list}->[$undos->{idx} + 1], $undos->{list}->[$undos->{idx}]);
    $self->log_factoid($channel, $trigger, $context->{hostmask}, "reverted (undo): $changes", 1);
    return "[$channel_name] $trigger_name reverted (revision " . ($undos->{idx} + 1) . "): $changes\n";
}

sub cmd_factredo {
    my ($self, $context) = @_;

    my $usage = "Usage: factredo [-l [N]] [-r N] [channel] <keyword> (-l list undo history, optionally starting from N; -r jump to revision N)";

    my $arguments = $context->{arguments};

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    my ($list_undos, $goto_revision);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($arguments, strip_quotes => 1);
    GetOptionsFromArray(
        \@opt_args,
        'l:i' => \$list_undos,
        'r=i' => \$goto_revision
    );

    return "/say $getopt_error -- $usage" if defined $getopt_error;
    return $usage                         if @opt_args > 2;
    return $usage                         if not @opt_args;

    $arguments = join(' ', map { $_ = "'$_'" if $_ =~ m/ /; $_; } @opt_args);

    my ($channel, $trigger) = $self->find_factoid_with_optional_channel(
        $context->{from}, $context->{arguments}, 'factredo', explicit => 1, exact_channel => 1
    );

    return $channel if not defined $trigger;  # if $trigger is not defined, $channel is an error message

    my $channel_path = $channel;
    $channel_path = 'global' if $channel_path eq '.*';

    my $channel_path_safe = safe_filename $channel_path;
    my $trigger_safe      = safe_filename $trigger;

    my $channel_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, '_name');
    my $trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, '_name');
    $channel_name = 'global'            if $channel_name eq '.*';
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    my $path  = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factlog';
    my $undos = eval { retrieve("$path/$trigger_safe.$channel_path_safe.undo"); };

    if (not $undos) { return "There are no redos available for [$channel_name] $trigger_name."; }

    if (defined $list_undos) {
        $list_undos = 1 if $list_undos == 0;
        return $self->list_undo_history($undos, $list_undos);
    }

    my $factoids = $self->{pbot}->{factoids}->{storage};
    my $userinfo = $self->{pbot}->{users}->loggedin($channel, $context->{hostmask});
    if ($factoids->get_data($channel, $trigger, 'locked')) {
        return "/say $trigger_name is locked and cannot be reverted." if not defined $self->{pbot}->{capabilities}->userhas($userinfo, 'admin');

        if ($factoids->exists($channel, $trigger, 'cap-override') and not $self->{pbot}->{capabilities}->userhas($userinfo, 'botowner')) {
            return "/say $trigger_name is locked with a cap-override and cannot be reverted. Unlock the factoid first.";
        }
    }

    if (not defined $goto_revision and $undos->{idx} + 1 == @{$undos->{list}}) { return "There are no more redos remaining for [$channel_name] $trigger_name."; }

    if (defined $goto_revision) {
        return "Don't be absurd." if $goto_revision < 1;
        if ($goto_revision > @{$undos->{list}}) {
            if   (@{$undos->{list}} == 1) { return "There is only one revision available for [$channel_name] $trigger_name."; }
            else                          { return "There are " . @{$undos->{list}} . " revisions available for [$channel_name] $trigger_name."; }
        }

        if ($goto_revision == $undos->{idx} + 1) { return "[$channel_name] $trigger_name is already at revision $goto_revision."; }

        $undos->{idx} = $goto_revision - 1;
        eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
        $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
    } else {
        $undos->{idx}++;
        eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
        $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
    }

    $self->{pbot}->{factoids}->{storage}->add($channel, $trigger, $undos->{list}->[$undos->{idx}], 0, 1);

    my $changes = $self->hash_differences_as_string($undos->{list}->[$undos->{idx} - 1], $undos->{list}->[$undos->{idx}]);
    $self->log_factoid($channel, $trigger, $context->{hostmask}, "reverted (redo): $changes", 1);
    return "[$channel_name] $trigger_name restored (revision " . ($undos->{idx} + 1) . "): $changes\n";
}

sub cmd_factset {
    my ($self, $context) = @_;

    my ($channel, $trigger, $arguments) = $self->find_factoid_with_optional_channel(
        $context->{from}, $context->{arguments}, 'factset', usage => 'Usage: factset [channel] <factoid> [key [value]]', explicit => 1
    );

    return $channel if not defined $trigger;    # if $trigger is not defined, $channel is an error message

    my $trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, '_name');
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    my $arglist = $self->{pbot}->{interpreter}->make_args($arguments);
    my ($key, $value) = $self->{pbot}->{interpreter}->split_args($arglist, 2);

    $channel = '.*' if $channel !~ /^#/;
    my ($owner_channel, $owner_trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $trigger, exact_channel => 1, exact_trigger => 1);

    my $userinfo;
    if   (defined $owner_channel) { $userinfo = $self->{pbot}->{users}->loggedin($owner_channel, $context->{hostmask}); }
    else                          { $userinfo = $self->{pbot}->{users}->loggedin($channel,       $context->{hostmask}); }

    my $meta_cap;
    if (defined $key) {
        if (defined $factoid_metadata_capabilities{$key}) { $meta_cap = $factoid_metadata_capabilities{$key}; }

        if (defined $meta_cap) {
            if (not $self->{pbot}->{capabilities}->userhas($userinfo, $meta_cap)) { return "Your user account must have the $meta_cap capability to set $key."; }
        }

        if (defined $value and !$self->{pbot}->{capabilities}->userhas($userinfo, 'admin') and $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, 'locked')) {
            return "/say $trigger_name is locked; unlock before setting.";
        }

        if (lc $key eq 'cap-override' and defined $value) {
            if (not $self->{pbot}->{capabilities}->exists($value)) { return "No such capability $value."; }
            $self->{pbot}->{factoids}->{storage}->set($channel, $trigger, 'locked', '1');
        }

        if (lc $key eq 'locked' and $self->{pbot}->{factoids}->{storage}->exists($channel, $trigger, 'cap-override')) {
            if (not $self->{pbot}->{capabilities}->userhas($userinfo, 'botowner')) {
                return "/say $trigger_name has a cap-override and cannot be unlocked until the override is removed.";
            }
        }
    }

    if (defined $owner_channel) {
        my $factoid = $self->{pbot}->{factoids}->{storage}->get_data($owner_channel, $owner_trigger);

        my $owner;
        my $mask;
        if ($factoid->{'locked'}) {
            # check owner against full hostmask for locked factoids
            $owner = $factoid->{'owner'};
            $mask  = $context->{hostmask};
        } else {
            # otherwise just the nick
            ($owner) = $factoid->{'owner'} =~ m/([^!]+)/;
            $mask = $context->{nick};
        }

        if ((defined $value and $key ne 'action' and $key ne 'action_with_args') and lc $mask ne lc $owner and not $self->{pbot}->{capabilities}->userhas($userinfo, 'admin')) {
            return "You are not the owner of $trigger_name.";
        }
    }

    my $result = $self->{pbot}->{factoids}->{storage}->set($channel, $trigger, $key, $value);

    if (defined $value and $result =~ m/set to/) { $self->log_factoid($channel, $trigger, $context->{hostmask}, "set $key to $value"); }

    return $result;
}

sub cmd_factunset {
    my ($self, $context) = @_;
    my $usage = 'Usage: factunset [channel] <factoid> <key>';

    my ($channel, $trigger, $arguments) = $self->find_factoid_with_optional_channel(
        $context->{from}, $context->{arguments}, 'factunset', usage => $usage, explicit => 1
    );

    return $channel if not defined $trigger;    # if $trigger is not defined, $channel is an error message

    my ($key) = $self->{pbot}->{interpreter}->split_line($arguments, strip_quotes => 1);
    return $usage if not length $key;

    my ($owner_channel, $owner_trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $trigger, exact_channel => 1, exact_trigger => 1);
    my $userinfo;
    if   (defined $owner_channel) { $userinfo = $self->{pbot}->{users}->loggedin($owner_channel, $context->{hostmask}); }
    else                          { $userinfo = $self->{pbot}->{users}->loggedin($channel,       $context->{hostmask}); }

    my $meta_cap;
    if (exists $factoid_metadata_capabilities{$key}) { $meta_cap = $factoid_metadata_capabilities{$key}; }

    if (defined $meta_cap) {
        if (not $self->{pbot}->{capabilities}->userhas($userinfo, $meta_cap)) { return "Your user account must have the $meta_cap capability to unset $key."; }
    }

    if ($self->{pbot}->{factoids}->{storage}->exists($channel, $trigger, 'cap-override')) {
        if (lc $key eq 'locked') {
            if ($self->{pbot}->{capabilities}->userhas($userinfo, 'botowner')) { $self->{pbot}->{factoids}->{storage}->unset($channel, $trigger, 'cap-override', 1); }
            else                                                               { return "You cannot unlock this factoid because it has a cap-override. Remove the override first."; }
        }
    }

    my $channel_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, '_name');
    my $trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, '_name');
    $channel_name = 'global'            if $channel_name eq '.*';
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    my $oldvalue;
    if (defined $owner_channel) {
        my $factoid = $self->{pbot}->{factoids}->{storage}->get_data($owner_channel, $owner_trigger);
        my ($owner) = $factoid->{'owner'} =~ m/([^!]+)/;
        if ($key ne 'action_with_args' and lc $context->{nick} ne lc $owner and not $self->{pbot}->{capabilities}->userhas($userinfo, 'admin')) {
            return "You are not the owner of $trigger_name.";
        }
        $oldvalue = $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, $key);
    }

    return "[$channel_name] $trigger_name: key '$key' does not exist." if not defined $oldvalue;
    my $result = $self->{pbot}->{factoids}->{storage}->unset($channel, $trigger, $key);
    if ($result =~ m/unset/) { $self->log_factoid($channel, $trigger, $context->{hostmask}, "unset $key (value: $oldvalue)"); }
    return $result;
}

sub cmd_factmove {
    my ($self, $context) = @_;
    my ($src_channel, $source, $target_channel, $target) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 5);
    my $usage = "Usage: factmove <source channel> <source factoid> <target channel/factoid> [target factoid]";
    return $usage if not defined $target_channel;

    if ($target_channel !~ /^#/ and $target_channel ne '.*') {
        if (defined $target) { return "Unexpected argument '$target' when renaming to '$target_channel'. Perhaps '$target_channel' is missing #s? $usage"; }
        $target         = $target_channel;
        $target_channel = $src_channel;
    } else {
        if (not defined $target) { $target = $source; }
    }

    if (length $target > $self->{pbot}->{registry}->get_value('factoids', 'max_name_length')) { return "/say $context->{nick}: I don't think the factoid name needs to be that long."; }

    if (length $target_channel > $self->{pbot}->{registry}->get_value('factoids', 'max_channel_length')) {
        return "/say $context->{nick}: I don't think the channel name needs to be that long.";
    }

    my ($found_src_channel, $found_source) = $self->{pbot}->{factoids}->find_factoid($src_channel, $source, exact_channel => 1, exact_trigger => 1);

    if (not defined $found_src_channel) { return "Source factoid $source not found in channel $src_channel"; }

    my $source_channel_name = $self->{pbot}->{factoids}->{storage}->get_data($found_src_channel, '_name');
    my $source_trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($found_src_channel, $found_source, '_name');
    $source_channel_name = 'global'                   if $source_channel_name eq '.*';
    $source_trigger_name = "\"$source_trigger_name\"" if $source_trigger_name =~ / /;

    my $factoids = $self->{pbot}->{factoids}->{storage};
    my ($owner) = $factoids->get_data($found_src_channel, $found_source, 'owner') =~ m/([^!]+)/;

    if ((lc $context->{nick} ne lc $owner) and (not $self->{pbot}->{users}->loggedin_admin($found_src_channel, $context->{hostmask}))) {
        $self->{pbot}->{logger}->log("$context->{hostmask} attempted to move [$found_src_channel] $found_source (not owner)\n");
        my $chan = ($found_src_channel eq '.*' ? 'the global channel' : $found_src_channel);
        return "You are not the owner of $source_trigger_name for $source_channel_name.";
    }

    if ($factoids->get_data($found_src_channel, $found_source, 'locked')) { return "/say $source_trigger_name is locked; unlock before moving."; }

    my ($found_target_channel, $found_target) = $self->{pbot}->{factoids}->find_factoid($target_channel, $target, exact_channel => 1, exact_trigger => 1);

    if (defined $found_target_channel) {
        my $target_channel_name = $factoids->get_data($found_target_channel, '_name');
        my $target_trigger_name = $factoids->get_data($found_target_channel, $found_target, '_name');
        $target_channel_name = 'global'                   if $target_channel_name eq '.*';
        $target_trigger_name = "\"$target_trigger_name\"" if $target_trigger_name =~ / /;
        return "Target factoid $target_trigger_name already exists in channel $target_channel_name.";
    }

    my ($overchannel, $overtrigger) = $self->{pbot}->{factoids}->find_factoid('.*', $target, exact_channel => 1, exact_trigger => 1);
    if (defined $overtrigger and $factoids->get_data('.*', $overtrigger, 'nooverride')) {
        my $override_channel_name = $factoids->get_data($overchannel, '_name');
        my $override_trigger_name = $factoids->get_data($overchannel, $overtrigger, '_name');
        $override_channel_name = 'global'                     if $override_channel_name eq '.*';
        $override_trigger_name = "\"$override_trigger_name\"" if $override_trigger_name =~ / /;
        $self->{pbot}->{logger}->log("$context->{hostmask} attempt to override $target\n");
        return
          "/say $override_trigger_name already exists for the global channel and cannot be overridden for "
          . ($target_channel eq '.*' ? 'the global channel' : $target_channel) . ".";
    }

    if ($self->{pbot}->{commands}->exists($target)) { return "/say $target already exists as a built-in command."; }

    $target_channel = '.*' if $target_channel !~ /^#/;

    my $data = $factoids->get_data($found_src_channel, $found_source);
    $factoids->remove($found_src_channel, $found_source, undef, 1);
    $factoids->add($target_channel, $target, $data, 0, 1);

    $found_src_channel = 'global' if $found_src_channel eq '.*';
    $target_channel    = 'global' if $target_channel eq '.*';

    if ($src_channel eq lc $target_channel) {
        $self->log_factoid($found_src_channel, $found_source, $context->{hostmask}, "renamed from $source_trigger_name to $target");
        $self->log_factoid($target_channel,    $target,       $context->{hostmask}, "renamed from $source_trigger_name to $target");
        return "[$source_channel_name] $source_trigger_name renamed to $target";
    } else {
        $self->log_factoid($found_src_channel, $found_source, $context->{hostmask}, "moved from $source_channel_name/$source_trigger_name to $target_channel/$target");
        $self->log_factoid($target_channel,    $target,       $context->{hostmask}, "moved from $source_channel_name/$source_trigger_name to $target_channel/$target");
        return "[$source_channel_name] $source_trigger_name moved to [$target_channel] $target";
    }
}

sub cmd_factalias {
    my ($self, $context) = @_;
    my ($chan, $alias, $command) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3, 0, 1);

    if (defined $chan and not($chan eq '.*' or $chan =~ m/^#/)) {
        # $chan doesn't look like a channel, so shift everything to the right
        # and replace $chan with $from
        if   (defined $command and length $command) { $command = "$alias $command"; }
        else                                        { $command = $alias; }
        $alias = $chan;
        $chan  = $context->{from};
    }

    $chan = '.*' if $chan !~ /^#/;
    return "Usage: factalias [channel] <keyword> <command>" if not length $alias or not length $command;

    if (length $alias > $self->{pbot}->{registry}->get_value('factoids', 'max_name_length')) { return "/say $context->{nick}: I don't think the factoid name needs to be that long."; }

    if (length $chan > $self->{pbot}->{registry}->get_value('factoids', 'max_channel_length')) { return "/say $context->{nick}: I don't think the channel name needs to be that long."; }

    my ($channel, $alias_trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $alias, exact_channel => 1, exact_trigger => 1);
    if (defined $alias_trigger) {
        my $alias_channel_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, '_name');
        my $alias_trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, $alias_trigger, '_name');
        $alias_channel_name = 'global'                  if $alias_channel_name eq '.*';
        $alias_trigger_name = "\"$alias_trigger_name\"" if $alias_trigger_name =~ / /;
        return "$alias_trigger_name already exists for $alias_channel_name.";
    }

    my ($overchannel, $overtrigger) = $self->{pbot}->{factoids}->find_factoid('.*', $alias, exact_channel => 1, exact_trigger => 1);
    if (defined $overtrigger and $self->{pbot}->{factoids}->{storage}->get_data('.*', $overtrigger, 'nooverride')) {
        my $override_trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($overchannel, $overtrigger, '_name');
        $override_trigger_name = "\"$override_trigger_name\"" if $override_trigger_name =~ / /;
        return "/say $override_trigger_name already exists for the global channel and cannot be overridden for " . ($chan eq '.*' ? 'the global channel' : $chan) . ".";
    }

    if ($self->{pbot}->{commands}->exists($alias)) { return "/say $alias already exists as a built-in command."; }

    $self->{pbot}->{factoids}->add_factoid('text', $chan, $context->{hostmask}, $alias, "/call $command");
    $self->{pbot}->{logger}->log("$context->{hostmask} [$chan] aliased $alias => $command\n");
    return "/say $alias aliases `$command` for " . ($chan eq '.*' ? 'the global channel' : $chan);
}

sub cmd_add_regex {
    my ($self, $context) = @_;
    my ($keyword, $text) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    my $channel = $context->{from};
    $channel = '.*' if not defined $channel or $channel !~ /^#/;

    if (not defined $keyword) { return "Usage: regex <regex> <command> | regex <channel>"; }

    if (not defined $text) {
        my @regexes;
        my $iter = $self->{pbot}->{factoids}->{storage}->get_each('type = regex', "index1 = $keyword", 'index2', '_sort = index2');
        while (defined (my $factoid = $self->{pbot}->{factoids}->{storage}->get_next($iter))) {
            push @regexes, $factoid->{index2};
        }
        $text = join '; ', @regexes;
        $text = 'none' if not length $text;
        return "Regex factoids for channel $keyword: $text";
    }

    my $trigger;
    ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $keyword, exact_channel => 1, exact_trigger => 1);

    if (defined $trigger) {
        return "/say $trigger already exists for channel $channel.";
    }

    $self->{pbot}->{factoids}->add_factoid('regex', $channel, $context->{hostmask}, $keyword, $text);
    $self->{pbot}->{logger}->log("$context->{hostmask} added regex [$keyword] => [$text]\n");
    return "/say $keyword added.";
}

sub cmd_factadd {
    my ($self, $context) = @_;
    my ($from_chan, $keyword, $text, $force);

    my @arglist = @{$context->{arglist}};

    if (@arglist) {
        # check for -f since we allow it to be before optional channel argument
        if ($arglist[0] eq '-f') {
            $force = 1;
            $self->{pbot}->{interpreter}->shift_arg(\@arglist);
        }

        # check if this is an optional channel argument
        if   ($arglist[0] =~ m/(?:^#|^global$|^\.\*$)/i) { $from_chan = $self->{pbot}->{interpreter}->shift_arg(\@arglist); }
        else                                             { $from_chan = $context->{from}; }

        # check for -f again since we also allow it to appear after the channel argument
        if ($arglist[0] eq '-f') {
            $force = 1;
            $self->{pbot}->{interpreter}->shift_arg(\@arglist);
        }

        # now this is the keyword
        $keyword = $self->{pbot}->{interpreter}->shift_arg(\@arglist);

        # check for -url
        if ($arglist[0] eq '-url') {
            # discard it
            $self->{pbot}->{interpreter}->shift_arg(\@arglist);

            # the URL is the remaining arguments
            my ($url) = $self->{pbot}->{interpreter}->split_args(\@arglist, 1);

            # FIXME: move this to registry
            if ($url !~ m/^https?:\/\/(?:sprunge.us|ix.io)\/\w+$/) { return "Invalid URL: acceptable URLs are: http://sprunge.us, http://ix.io"; }

            # create a UserAgent
            my $ua = LWP::UserAgent->new(timeout => 10);

            # get the factoid's text from the URL
            my $response = $ua->get($url);

            # process the response
            if ($response->is_success) { $text = $response->decoded_content; }
            else                       { return "Failed to get URL: " . $response->status_line; }
        } else {
            # check for optional "is" and discard
            if (lc $arglist[0] eq 'is') { $self->{pbot}->{interpreter}->shift_arg(\@arglist); }

            # and the text is the remaining arguments with quotes preserved
            ($text) = $self->{pbot}->{interpreter}->split_args(\@arglist, 1, 0, 1);
        }
    }

    if (not defined $from_chan or not defined $text or not defined $keyword) {
        return "Usage: factadd [-f] [channel] <keyword> (<factoid> | -url <paste site>); -f to force overwrite; -url to download from paste site";
    }

    $from_chan = '.*' if $from_chan !~ /^#/;

    if (length $keyword > $self->{pbot}->{registry}->get_value('factoids', 'max_name_length')) { return "/say $context->{nick}: I don't think the factoid name needs to be that long."; }

    if (length $from_chan > $self->{pbot}->{registry}->get_value('factoids', 'max_channel_length')) { return "/say $context->{nick}: I don't think the channel needs to be that long."; }

    $from_chan = '.*' if lc $from_chan eq 'global';
    $from_chan = '.*' if not $from_chan =~ m/^#/;

    my $keyword_text = $keyword =~ / / ? "\"$keyword\"" : $keyword;

    my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($from_chan, $keyword, exact_channel => 1, exact_trigger => 1);
    if (defined $trigger) {
        my $channel_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, '_name');
        my $trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, '_name');
        $channel_name = 'global'            if $channel_name eq '.*';
        $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

        if (not $force) {
            return "/say $trigger_name already exists for $channel_name.";
        } else {
            my $factoids = $self->{pbot}->{factoids}->{storage};
            if ($factoids->get_data($channel, $trigger, 'locked')) { return "/say $trigger_name is locked; unlock before overwriting."; }
        }
    }

    ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid('.*', $keyword, exact_channel => 1, exact_trigger => 1);
    if (defined $trigger and $self->{pbot}->{factoids}->{storage}->get_data('.*', $trigger, 'nooverride')) {
        my $trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, '_name');
        $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;
        return "/say $trigger_name already exists for the global channel and cannot be overridden for " . ($from_chan eq '.*' ? 'the global channel' : $from_chan) . ".";
    }

    if ($self->{pbot}->{commands}->exists($keyword)) { return "/say $keyword_text already exists as a built-in command."; }

    $self->{pbot}->{factoids}->add_factoid('text', $from_chan, $context->{hostmask}, $keyword, $text);
    $self->{pbot}->{logger}->log("$context->{hostmask} added [$from_chan] $keyword_text => $text\n");
    $self->log_factoid($channel, $trigger, $context->{hostmask}, "created");
    return "/say $keyword_text added to " . ($from_chan eq '.*' ? 'global channel' : $from_chan) . ".";
}

sub cmd_factrem {
    my ($self, $context) = @_;
    my $factoids = $self->{pbot}->{factoids}->{storage};

    my ($from_chan, $from_trig) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (not defined $from_trig) {
        $from_trig = $from_chan;
        $from_chan = $context->{from};
    }

    my ($channel, $trigger) = $self->find_factoid_with_optional_channel($context->{from}, $context->{arguments}, 'factrem', explicit => 1);
    return $channel if not defined $trigger;    # if $trigger is not defined, $channel is an error message

    $channel   = '.*' if $channel eq 'global';
    $from_chan = '.*' if $channel eq 'global';

    my $channel_name = $factoids->get_data($channel, '_name');
    my $trigger_name = $factoids->get_data($channel, $trigger, '_name');
    $channel_name = 'global'            if $channel_name eq '.*';
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    if ($factoids->get_data($channel, $trigger, 'type') eq 'module') { return "/say $trigger_name is not a factoid."; }

    if ($channel =~ /^#/ and $from_chan =~ /^#/ and lc $channel ne lc $from_chan) {
        return "/say $trigger_name belongs to $channel_name, but this is $from_chan. Please switch to $channel_name or use /msg to remove this factoid.";
    }

    my ($owner) = $factoids->get_data($channel, $trigger, 'owner') =~ m/([^!]+)/;

    if ((lc $context->{nick} ne lc $owner) and (not $self->{pbot}->{users}->loggedin_admin($channel, $context->{hostmask}))) {
        return "You are not the owner of $trigger_name for $channel_name.";
    }

    if ($factoids->get_data($channel, $trigger, 'locked')) { return "/say $trigger_name is locked; unlock before deleting."; }

    $self->{pbot}->{logger}->log("$context->{hostmask} removed [$channel][$trigger][" . $factoids->get_data($channel, $trigger, 'action') . "]\n");
    $self->log_factoid($channel, $trigger, $context->{hostmask}, "deleted", 1);
    return '/say '. $self->{pbot}->{factoids}->remove_factoid($channel, $trigger);
}

sub cmd_factshow {
    my ($self, $context) = @_;
    my $factoids = $self->{pbot}->{factoids}->{storage};
    $context->{preserve_whitespace} = 1;
    my $usage = "Usage: factshow [-p] [channel] <keyword>; -p to paste";
    return $usage if not length $context->{arguments};

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    my ($paste);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);
    GetOptionsFromArray(
        \@opt_args,
        'p' => \$paste
    );

    return "/say $getopt_error -- $usage" if defined $getopt_error;
    return "Too many arguments -- $usage" if @opt_args > 2;
    return "Missing argument -- $usage"   if not @opt_args;

    my ($chan, $trig) = @opt_args;
    $chan = $context->{from} if not defined $trig;
    my $args = join(' ', map { $_ = "'$_'" if $_ =~ m/ /; $_; } @opt_args);

    my ($channel, $trigger) = $self->find_factoid_with_optional_channel($context->{from}, $args, 'factshow', usage => $usage);
    return $channel if not defined $trigger;    # if $trigger is not defined, $channel is an error message

    my $channel_name = $factoids->get_data($channel, '_name');
    my $trigger_name = $factoids->get_data($channel, $trigger, '_name');
    $channel_name = 'global'            if $channel_name eq '.*';
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    my $result = "$trigger_name: ";

    if ($paste) {
        $result .= $self->{pbot}->{webpaste}->paste($factoids->get_data($channel, $trigger, 'action'), no_split => 1);
        $result = "[$channel_name] $result" if $channel ne lc $chan;
        return $result;
    }

    $result .= $factoids->get_data($channel, $trigger, 'action');
    $result .= ' [module]' if $factoids->get_data($channel, $trigger, 'type') eq 'module';
    $result = "[$channel_name] $result" if $channel ne lc $chan;
    return $result;
}

sub cmd_factlog {
    my ($self, $context) = @_;

    my $usage = "Usage: factlog [-h] [-t] [channel] <keyword>; -h show full hostmask; -t show actual timestamp instead of relative";

    return $usage if not length $context->{arguments};

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    my ($show_hostmask, $actual_timestamp);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);
    GetOptionsFromArray(
        \@opt_args,
        'h' => \$show_hostmask,
        't' => \$actual_timestamp
    );

    return "/say $getopt_error -- $usage" if defined $getopt_error;
    return "Too many arguments -- $usage" if @opt_args > 2;
    return "Missing argument -- $usage"   if not @opt_args;

    my $args = join(' ', map { $_ = "'$_'" if $_ =~ m/ /; $_; } @opt_args);

    my ($channel, $trigger) = $self->find_factoid_with_optional_channel($context->{from}, $args, 'factlog', usage => $usage, exact_channel => 1);

    if (not defined $trigger) {
        # factoid not found or some error, try to continue and load factlog file if it exists
        my $arglist = $self->{pbot}->{interpreter}->make_args($args);
        ($channel, $trigger) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
        if (not defined $trigger) {
            $trigger = $channel;
            $channel = $context->{from};
        }
        $channel = '.*' if $channel !~ m/^#/;
    }

    my $path = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factlog';

    $channel = 'global' if $channel eq '.*';

    my $channel_safe = safe_filename $channel;
    my $trigger_safe = safe_filename $trigger;

    open my $fh, "< $path/$trigger_safe.$channel_safe" or do {
        $self->{pbot}->{logger}->log("Could not open $path/$trigger_safe.$channel_safe: $!\n");
        $channel = 'the global channel' if $channel eq 'global';
        return "No factlog available for $trigger in $channel.";
    };

    my @entries;
    while (my $line = <$fh>) {
        my ($timestamp, $hostmask, $msg);

        ($timestamp, $hostmask, $msg) = eval {
            my $h = decode_json $line;
            return ($h->{ts}, $h->{hm}, $h->{msg});
        };

        ($timestamp, $hostmask, $msg) = split /\s+/, $line, 3 if $@;
        $hostmask =~ s/!.*$// if not $show_hostmask;

        if ($actual_timestamp) { $timestamp = strftime "%a %b %e %H:%M:%S %Z %Y", localtime $timestamp; }
        else                   { $timestamp = concise ago gettimeofday - $timestamp; }
        push @entries, "[$timestamp] $hostmask $msg\n";
    }
    close $fh;
    my $result = join "", reverse @entries;
    return $result;
}

sub cmd_factinfo {
    my ($self, $context) = @_;
    my $factoids = $self->{pbot}->{factoids}->{storage};
    my ($chan, $trig) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (not defined $trig) {
        $trig = $chan;
        $chan = $context->{from};
    }

    my ($channel, $trigger) = $self->find_factoid_with_optional_channel($context->{from}, $context->{arguments}, 'factinfo');
    return $channel if not defined $trigger;    # if $trigger is not defined, $channel is an error message

    my $channel_name = $factoids->get_data($channel, '_name');
    my $trigger_name = $factoids->get_data($channel, $trigger, '_name');
    $channel_name = 'global'            if $channel_name eq '.*';
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    my $created_ago = concise ago(gettimeofday - $factoids->get_data($channel, $trigger, 'created_on'));
    my $ref_ago = concise ago(gettimeofday - $factoids->get_data($channel, $trigger, 'last_referenced_on')) if defined $factoids->get_data($channel, $trigger, 'last_referenced_on');

    # factoid
    if ($factoids->get_data($channel, $trigger, 'type') eq 'text') {
        return
            "/say $trigger_name: Factoid submitted by "
          . $factoids->get_data($channel, $trigger, 'owner')
          . " for $channel_name on "
          . localtime($factoids->get_data($channel, $trigger, 'created_on'))
          . " [$created_ago], "
          . (
            defined $factoids->get_data($channel, $trigger, 'edited_by')
            ? 'last edited by '
              . $factoids->get_data($channel, $trigger, 'edited_by') . ' on '
              . localtime($factoids->get_data($channel, $trigger, 'edited_on')) . " ["
              . concise ago(gettimeofday - $factoids->get_data($channel, $trigger, 'edited_on')) . "], "
            : ""
          )
          . "referenced "
          . $factoids->get_data($channel, $trigger, 'ref_count')
          . ' times (last by '
          . $factoids->get_data($channel, $trigger, 'ref_user')
          . ($factoids->exists($channel, $trigger, 'last_referenced_on') ? ' on ' . localtime($factoids->get_data($channel, $trigger, 'last_referenced_on')) . " [$ref_ago]" : '')
          . ')';
    }

    # module
    if ($factoids->get_data($channel, $trigger, 'type') eq 'module') {
        my $module_repo = $self->{pbot}->{registry}->get_value('general', 'module_repo');
        $module_repo .= $factoids->get_data($channel, $trigger, 'workdir') . '/' if $factoids->exists($channel, $trigger, 'workdir');
        return
            "/say $trigger_name: Module loaded by "
          . $factoids->get_data($channel, $trigger, 'owner')
          . " for $channel_name on "
          . localtime($factoids->get_data($channel, $trigger, 'created_on'))
          . " [$created_ago] -> $module_repo"
          . $factoids->get_data($channel, $trigger, 'action')
          . ', used '
          . $factoids->get_data($channel, $trigger, 'ref_count')
          . ' times (last by '
          . $factoids->get_data($channel, $trigger, 'ref_user')
          . ($factoids->exists($channel, $trigger, 'last_referenced_on') ? ' on ' . localtime($factoids->get_data($channel, $trigger, 'last_referenced_on')) . " [$ref_ago]" : '')
          . ')';
    }

    # regex
    if ($factoids->get_data($channel, $trigger, 'type') eq 'regex') {
        return
            "/say $trigger_name: Regex created by "
          . $factoids->get_data($channel, $trigger, 'owner')
          . " for $channel_name on "
          . localtime($factoids->get_data($channel, $trigger, 'created_on'))
          . " [$created_ago], "
          . (
            defined $factoids->get_data($channel, $trigger, 'edited_by')
            ? 'last edited by '
              . $factoids->get_data($channel, $trigger, 'edited_by') . ' on '
              . localtime($factoids->get_data($channel, $trigger, 'edited_on')) . " ["
              . concise ago(gettimeofday - $factoids->get_data($channel, $trigger, 'edited_on')) . "], "
            : ""
          )
          . ' used '
          . $factoids->get_data($channel, $trigger, 'ref_count')
          . ' times (last by '
          . $factoids->get_data($channel, $trigger, 'ref_user')
          . ($factoids->exists($channel, $trigger, 'last_referenced_on') ? ' on ' . localtime($factoids->get_data($channel, $trigger, 'last_referenced_on')) . " [$ref_ago]" : '')
          . ')';
    }

    return "/say $context->{arguments} is not a factoid or a module.";
}

sub cmd_factfind {
    my ($self, $context) = @_;

    my $arguments = $context->{arguments};

    my $usage = "Usage: factfind [-channel channel] [-owner regex] [-editby regex] [-refby regex] [-regex] [text]";
    return $usage if not length $arguments;

    my $factoids = $self->{pbot}->{factoids}->{storage};
    my ($channel, $owner, $refby, $editby, $use_regex);
    $channel   = $1 if $arguments =~ s/\s*-channel\s+([^\b\s]+)//i;
    $owner     = $1 if $arguments =~ s/\s*-owner\s+([^\b\s]+)//i;
    $refby     = $1 if $arguments =~ s/\s*-refby\s+([^\b\s]+)//i;
    $editby    = $1 if $arguments =~ s/\s*-editby\s+([^\b\s]+)//i;
    $use_regex = 1  if $arguments =~ s/\s*-regex\b//i;

    $arguments =~ s/^\s+//;
    $arguments =~ s/\s+$//;
    $arguments =~ s/\s+/ /g;

    $arguments = substr($arguments, 0, 30);
    my $argtype = undef;

    $argtype = "owned by $owner" if defined $owner and $owner ne '.*';

    if (defined $refby) {
        if (not defined $argtype) { $argtype = "last referenced by $refby"; }
        else                      { $argtype .= " and last referenced by $refby"; }
    }

    if (defined $editby) {
        if (not defined $argtype) { $argtype = "last edited by $editby"; }
        else                      { $argtype .= " and last edited by $editby"; }
    }

    if ($arguments ne "") {
        my $unquoted_args = $arguments;
        $unquoted_args =~ s/(?:\\(?!\\))//g;
        $unquoted_args =~ s/(?:\\\\)/\\/g;
        if (not defined $argtype) { $argtype = "containing '$unquoted_args'"; }
        else                      { $argtype .= " and containing '$unquoted_args'"; }
    }

    if (not defined $argtype) { return $usage; }

    my ($text, $last_trigger, $last_chan, $i);
    $last_chan = "";
    $i         = 0;
    eval {
        use re::engine::RE2 -strict => 1;
        my $regex;
        if ($use_regex) { $regex = $arguments; }
        else {
            $regex = ($arguments =~ m/^\w/) ? '\b' : '\B';
            $regex .= quotemeta $arguments;
            $regex .= ($arguments =~ m/\w$/) ? '\b' : '\B';
        }

        foreach my $chan (sort $factoids->get_keys) {
            next if defined $channel and $chan !~ /^$channel$/i;
            foreach my $factoid ($factoids->get_all("index1 = $chan", 'index2', 'owner', 'ref_user', 'edited_by', 'action')) {
                my $match = 0;

                if (defined $owner) {
                    $match = 1 if $factoid->{owner} =~ /^$owner/i;
                }

                if (defined $refby) {
                    $match = 1 if $factoid->{ref_user} =~ /^$refby/i;
                }

                if (defined $editby) {
                    $match = 1 if $factoid->{edited_by} =~ /^$editby/i;
                }

                if ($arguments ne "" && ($factoid->{action} =~ /$regex/i || $factoid->{index2} =~ /$regex/i)) {
                    $match = 1;
                }

                if ($match) {
                    $i++;
                    if ($chan ne $last_chan) {
                        $text .= $chan eq '.*' ? '[global channel] ' : '[' . $factoids->get_data($chan, '_name') . '] ';
                        $last_chan = $chan;
                    }
                    my $trigger_name = $factoids->get_data($chan, $factoid->{index2}, '_name');
                    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;
                    $text .= "$trigger_name ";
                    $last_trigger = $trigger_name;
                }
            }
        }
    };

    return "/msg $context->{nick} $context->{arguments}: $@" if $@;

    if ($i == 1) {
        chop $text;
        return
            "Found one factoid in "
          . ($last_chan eq '.*' ? 'global' : $factoids->get_data($last_chan, '_name')) . ' '
          . $argtype
          . ": $last_trigger is "
          . $factoids->get_data($last_chan, $last_trigger, 'action');
    } else {
        return "Found $i factoids " . $argtype . ": $text" unless $i == 0;
        my $chans = (defined $channel ? ($channel eq '.*' ? 'global' : $channel) : 'any channels');
        return "No factoids " . $argtype . " submitted for $chans.";
    }
}

sub cmd_factchange {
    my ($self, $context) = @_;
    my $factoids_data = $self->{pbot}->{factoids}->{storage};
    my ($channel, $trigger, $keyword, $delim, $tochange, $changeto, $modifier, $url);

    $context->{preserve_whitespace} = 1;

    my $needs_disambig;

    if (length $context->{arguments}) {
        my $args = $context->{arglist};
        my $sub;

        my $arg_count = $self->{pbot}->{interpreter}->arglist_size($args);

        if ($arg_count >= 4 and ($args->[0] =~ m/^#/ or $args->[0] eq '.*' or lc $args->[0] eq 'global') and ($args->[2] eq '-url')) {
            $channel        = $args->[0];
            $keyword        = $args->[1];
            $url            = $args->[3];
            $needs_disambig = 0;
        } elsif ($arg_count >= 3 and $args->[1] eq '-url') {
            $keyword        = $args->[0];
            $url            = $args->[2];
            $channel        = $context->{from};
            $needs_disambig = 1;
        } elsif ($arg_count >= 3 and ($args->[0] =~ m/^#/ or $args->[0] eq '.*' or lc $args->[0] eq 'global') and ($args->[2] =~ m/^s([[:punct:]])/)) {
            $delim   = $1;
            $channel = $args->[0];
            $keyword = $args->[1];
            ($sub) = $self->{pbot}->{interpreter}->split_args($args, 1, 2, 1);
            $needs_disambig = 0;
        } elsif ($arg_count >= 2 and $args->[1] =~ m/^s([[:punct:]])/) {
            $delim   = $1;
            $keyword = $args->[0];
            $channel = $context->{from};
            ($sub) = $self->{pbot}->{interpreter}->split_args($args, 1, 1, 1);
            $needs_disambig = 1;
        }

        if (defined $sub) {
            $delim = quotemeta $delim;

            if ($sub =~ /^s$delim(.*?)$delim(.*)$delim(.*)$/) {
                $tochange = $1;
                $changeto = $2;
                $modifier = $3;
            } elsif ($sub =~ /^s$delim(.*?)$delim(.*)$/) {
                $tochange = $1;
                $changeto = $2;
                $modifier = '';
            }
        }
    }

    if (not defined $channel or (not defined $changeto and not defined $url)) {
        return "Usage: factchange [channel] <keyword> (s/<pattern>/<replacement>/ | -url <paste site>)";
    }

    my ($from_trigger, $from_chan) = ($keyword, $channel);
    my @factoids = $self->{pbot}->{factoids}->find_factoid($from_chan, $keyword, exact_trigger => 1);

    if (not @factoids or not $factoids[0]) {
        $from_chan = 'global channel' if $from_chan eq '.*';
        return "/say $keyword not found in $from_chan";
    }

    if (@factoids > 1) {
        if (not grep { lc $_->[0] eq $from_chan } @factoids) {
            return
                "/say $from_trigger found in multiple channels: "
              . (join ', ', sort map { $_->[0] eq '.*' ? 'global' : $_->[0] } @factoids)
              . "; use `factchange <channel> $from_trigger` to disambiguate.";
        } else {
            foreach my $factoid (@factoids) {
                if ($factoid->[0] eq $from_chan) {
                    ($channel, $trigger) = ($factoid->[0], $factoid->[1]);
                    last;
                }
            }
        }
    } else {
        ($channel, $trigger) = ($factoids[0]->[0], $factoids[0]->[1]);
    }

    if (not defined $trigger) { return "/say $keyword not found in channel $from_chan."; }

    my $channel_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, '_name');
    my $trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, '_name');
    $channel_name = 'global'            if $channel_name eq '.*';
    $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;

    $from_chan = '.*' if $from_chan eq 'global';

    if ($channel =~ /^#/ and $from_chan =~ /^#/ and lc $channel ne lc $from_chan) {
        return "/say $trigger_name belongs to $channel_name, but this is $from_chan. Please switch to $channel_name or use /msg to change this factoid.";
    }

    my $userinfo = $self->{pbot}->{users}->loggedin($channel, $context->{hostmask});
    if ($factoids_data->get_data($channel, $trigger, 'locked')) {
        return "/say $trigger_name is locked and cannot be changed." if not $self->{pbot}->{capabilities}->userhas($userinfo, 'admin');

        if ($factoids_data->exists($channel, $trigger, 'cap-override') and not $self->{pbot}->{capabilities}->userhas($userinfo, 'botowner')) {
            return "/say $trigger_name is locked with a cap-override set and cannot be changed until the override is removed.";
        }
    }

    my $action = $factoids_data->get_data($channel, $trigger, 'action');

    if (defined $url) {
        # FIXME: move this to registry
        if ($url !~ m/^https?:\/\/(?:sprunge.us|ix.io)\/\w+$/) { return "Invalid URL: acceptable URLs are: http://sprunge.us, http://ix.io"; }

        my $ua       = LWP::UserAgent->new(timeout => 10);
        my $response = $ua->get($url);

        if ($response->is_success) { $action = $response->decoded_content; }
        else                       { return "Failed to get URL: " . $response->status_line; }
    } else {
        my $ret = eval {
            use re::engine::RE2 -strict => 1;
            my $changed;

            if ($modifier eq 'gi' or $modifier eq 'ig' or $modifier eq 'g') {
                my @chars = ("A" .. "Z", "a" .. "z", "0" .. "9");
                my $magic = '';
                $magic .= $chars[rand @chars] for 1 .. (10 * rand) + 10;
                my $insensitive = index($modifier, 'i') + 1;
                my $count       = 0;
                my $max         = 50;

                while (1) {
                    if ($count == 0) {
                        if   ($insensitive) { $changed = $action =~ s|$tochange|$changeto$magic|i; }
                        else                { $changed = $action =~ s|$tochange|$changeto$magic|; }
                    } else {
                        if   ($insensitive) { $changed = $action =~ s|$tochange|$1$changeto$magic|i; }
                        else                { $changed = $action =~ s|$tochange|$1$changeto$magic|; }
                    }

                    if ($changed) {
                        $count++;
                        if ($count == $max) {
                            $action =~ s/$magic//;
                            last;
                        }
                        $tochange = "$magic(.*?)$tochange" if $count == 1;
                    } else {
                        $changed = $count;
                        $action =~ s/$magic// if $changed;
                        last;
                    }
                }
            } elsif ($modifier eq 'i') {
                $changed = $action =~ s|$tochange|$changeto|i;
            } else {
                $changed = $action =~ s|$tochange|$changeto|;
            }

            if (not $changed) {
                $self->{pbot}->{logger}->log("($context->{from}) $context->{hostmask}: failed to change '$trigger' 's$delim$tochange$delim$changeto$delim\n");
                return "Change $trigger failed.";
            }
            return "";
        };

        if ($@) {
            my $err = $@;
            $err =~ s/ at PBot\/.*$//;
            return "/msg $context->{nick} Change $trigger_name failed: $err";
        }
        return $ret if length $ret;
    }

    if (length $action > 8000 and not $self->{pbot}->{capabilities}->userhas($userinfo, 'admin')) { return "Change $trigger_name failed; result is too long."; }

    if (not length $action) { return "Change $trigger_name failed; factoids cannot be empty."; }

    $self->{pbot}->{logger}->log("($context->{from}) $context->{hostmask} changed '$trigger' 's/$tochange/$changeto/\n");

    $factoids_data->set($channel, $trigger, 'action',    $action,              1);
    $factoids_data->set($channel, $trigger, 'edited_by', $context->{hostmask}, 1);
    $factoids_data->set($channel, $trigger, 'edited_on', gettimeofday);
    $self->log_factoid($channel, $trigger, $context->{hostmask}, "changed to $action");
    return "Changed: $trigger_name is $action";
}

sub cmd_top20 {
    my ($self, $context) = @_;
    my $factoids = $self->{pbot}->{factoids}->{storage};
    my %hash     = ();
    my $text     = "";
    my $i        = 0;

    my ($channel, $args) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);

    if (not defined $channel) { return "Usage: top20 <channel> [nick or 'recent']"; }

    if (not defined $args) {
        my $iter = $factoids->get_each('type = text', "index1 = $channel", 'index2', 'ref_count > 0', '_sort = -ref_count');
        while (defined (my $factoid = $factoids->get_next($iter))) {
            $text .= $factoids->get_data($factoid->{index1}, $factoid->{index2}, '_name') . " ($factoid->{ref_count}) ";
            $i++;
            last if $i >= 20;
        }

        $channel = "the global channel"                             if $channel eq '.*';
        if ($i > 0) {
            return "Top $i referenced factoids for $channel: $text";
        } else {
            return "No factoids referenced in $channel.";
        }
    }

    if (lc $args eq "recent") {
        my $iter = $factoids->get_each('type = text', "index1 = $channel", 'index2', 'created_on', 'owner', '_sort = -created_on');
        while (defined (my $factoid = $factoids->get_next($iter))) {
            my $ago   = concise ago gettimeofday - $factoid->{'created_on'};
            my ($owner) = $factoid->{'owner'} =~ /^([^!]+)/;
            $text .= '   ' . $factoids->get_data($factoid->{index1}, $factoid->{index2}, '_name') . " [$ago by $owner]\n";
            $i++;
            last if $i >= 50;
        }

        $channel = "global channel"                                if $channel eq '.*';
        $text    = "$i most recent $channel submissions:\n\n$text" if $i > 0;
        return $text;
    }

    my $iter = $factoids->get_each('type = text', "index1 = $channel", 'index2', 'ref_user', 'last_referenced_on', '_sort = -last_referenced_on');
    while (defined (my $factoid = $factoids->get_next($iter))) {
        my ($ref_user) = $factoid->{ref_user} =~ /^([^!]+)/;
        if ($ref_user =~ /^\Q$args\E/i) {
            my $ago = $factoid->{'last_referenced_on'} ? concise ago(gettimeofday - $factoid->{'last_referenced_on'}) : "unknown";
            $text .= '   ' . $factoids->get_data($factoid->{index1}, $factoid->{index2}, '_name') . " [$ago]\n";
            $i++;
            last if $i >= 20;
        }
    }

    if ($i > 0) {
        return "$i $channel factoids last referenced by $args:\n\n$text";
    } else {
        return "No factoids last referenced by $args in $channel.";
    }
}

sub cmd_histogram {
    my ($self, $context) = @_;
    my $factoids = $self->{pbot}->{factoids}->{storage};
    my %owners;
    my $factoid_count = 0;

    my $iter = $factoids->get_each('type = text', 'owner');
    while (defined (my $factoid = $factoids->get_next($iter))) {
        my ($owner) = $factoid->{owner} =~ m/^([^!]+)/;
        $owners{$owner}++;
        $factoid_count++;
    }

    my $top = 15;
    my $text;
    my $i = 0;
    foreach my $owner (sort { $owners{$b} <=> $owners{$a} } keys %owners) {
        my $percent = int($owners{$owner} / $factoid_count * 100);
        $text .= "$owner: $owners{$owner} ($percent" . "%)\n";
        $i++;
        last if $i >= $top;
    }
    return "/say $factoid_count factoids, top $top submitters:\n$text";
}

sub cmd_count {
    my ($self, $context) = @_;
    my $factoids = $self->{pbot}->{factoids}->{storage};
    my $i        = 0;
    my $total    = 0;

    my $arguments = $context->{arguments};

    if (not length $arguments) { return "Usage: count <nick|factoids>"; }

    $arguments = ".*" if ($arguments =~ /^factoids$/);

    eval {
        my $iter = $factoids->get_each('type = text', 'owner');
        while (defined (my $factoid = $factoids->get_next($iter))) {
            $total++;
            my ($owner) = $factoid->{owner} =~ /^([^!]+)/;
            if ($owner =~ /^$arguments$/i) { $i++; }
        }
    };
    return "/msg $context->{nick} Error counting $context->{arguments}: $@" if $@;

    return "I have $i text factoids." if $arguments eq ".*";

    if ($i > 0) {
        my $percent = int($i / $total * 100);
        $percent = 1 if $percent == 0;
        return "/say $arguments has submitted $i factoids out of $total ($percent" . "%)";
    } else {
        return "/say $arguments hasn't submitted any factoids";
    }
}

sub log_factoid {
    my ($self, $channel, $trigger, $hostmask, $msg, $dont_save_undo) = @_;

    $channel = lc $channel;
    $trigger = lc $trigger;

    my $channel_path = $channel;
    $channel_path = 'global' if $channel_path eq '.*';

    my $channel_path_safe = safe_filename $channel_path;
    my $trigger_safe      = safe_filename $trigger;

    my $path = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factlog';
    open my $fh, ">> $path/$trigger_safe.$channel_path_safe" or do {
        $self->{pbot}->{logger}->log("Failed to open factlog for $channel/$trigger: $!\n");
        return;
    };

    my $now  = gettimeofday;
    my $h    = {ts => $now, hm => $hostmask, msg => $msg};
    my $json = encode_json $h;
    print $fh "$json\n";
    close $fh;

    return if $dont_save_undo;

    my $undos = eval { retrieve("$path/$trigger_safe.$channel_path_safe.undo"); };

    if (not $undos) {
        $undos = {
            idx  => -1,
            list => []
        };
    }

    my $max_undos = $self->{pbot}->{registry}->get_value('factoids', 'max_undos') // 20;
    if (@{$undos->{list}} > $max_undos) {
        shift @{$undos->{list}};
        $undos->{idx}--;
    }

    if ($undos->{idx} > -1 and @{$undos->{list}} > $undos->{idx} + 1) { splice @{$undos->{list}}, $undos->{idx} + 1; }

    push @{$undos->{list}}, $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger);
    $undos->{idx}++;

    eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
    $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
}

sub find_factoid_with_optional_channel {
    my ($self, $from, $arguments, $command, %opts) = @_;

    my %default_opts = (
        usage         => undef,
        explicit      => 0,
        exact_channel => 0
    );

    %opts = (%default_opts, %opts);
    my $arglist = $self->{pbot}->{interpreter}->make_args($arguments);
    my ($from_chan, $from_trigger, $remaining_args) = $self->{pbot}->{interpreter}->split_args($arglist, 3, 0, 1);

    if (not defined $from_chan or (not defined $from_chan and not defined $from_trigger)) {
        return "Usage: $command [channel] <keyword>" if not $opts{usage};
        return $opts{usage};
    }

    my $needs_disambig;
    if (not defined $from_trigger) {
        # cmd arg1, so insert $from as channel
        $from_trigger   = $from_chan;
        $from_chan      = $from;
        $remaining_args = "";

        #$needs_disambig = 1;
    } else {
        # cmd arg1 arg2 [...?]
        if ($from_chan !~ /^#/ and lc $from_chan ne 'global' and $from_chan ne '.*') {
            # not a channel or global, so must be a keyword
            my $keyword = $from_chan;
            $from_chan    = $from;
            $from_trigger = $keyword;
            (undef, $remaining_args) = $self->{pbot}->{interpreter}->split_args($arglist, 2, 0, 1);
        }
    }

    $from_chan = '.*' if $from_chan !~ /^#/;
    $from_chan = lc $from_chan;

    my ($channel, $trigger);

    if ($opts{exact_channel} == 1) {
        ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($from_chan, $from_trigger, exact_channel => 1, exact_trigger => 1);

        if (not defined $channel) {
            $from_chan = 'the global channel' if $from_chan eq '.*';
            return "/say $from_trigger not found in $from_chan.";
        }
    } else {
        my @factoids = $self->{pbot}->{factoids}->find_factoid($from_chan, $from_trigger, exact_trigger => 1);

        if (not @factoids or not $factoids[0]) {
            if ($needs_disambig) { return "/say $from_trigger not found"; }
            else {
                $from_chan = 'global channel' if $from_chan eq '.*';
                return "/say $from_trigger not found in $from_chan";
            }
        }

        if (@factoids > 1) {
            if ($needs_disambig or not grep { lc $_->[0] eq $from_chan } @factoids) {
                unless ($opts{explicit}) {
                    foreach my $factoid (@factoids) {
                        if ($factoid->[0] eq '.*') { ($channel, $trigger) = ($factoid->[0], $factoid->[1]); }
                    }
                }
                if (not defined $channel) {
                    return
                        "/say $from_trigger found in multiple channels: "
                      . (join ', ', sort map { $_->[0] eq '.*' ? 'global' : $_->[0] } @factoids)
                      . "; use `$command <channel> $from_trigger` to disambiguate.";
                }
            } else {
                foreach my $factoid (@factoids) {
                    if (lc $factoid->[0] eq $from_chan) {
                        ($channel, $trigger) = ($factoid->[0], $factoid->[1]);
                        last;
                    }
                }
            }
        } else {
            ($channel, $trigger) = ($factoids[0]->[0], $factoids[0]->[1]);
        }
    }

    $channel   = '.*' if $channel eq 'global';
    $from_chan = '.*' if $channel eq 'global';

    if ($opts{explicit} and $channel =~ /^#/ and $from_chan =~ /^#/ and lc $channel ne $from_chan) {
        my $channel_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, '_name');
        my $trigger_name = $self->{pbot}->{factoids}->{storage}->get_data($channel, $trigger, '_name');
        $channel_name = 'global'            if $channel_name eq '.*';
        $trigger_name = "\"$trigger_name\"" if $trigger_name =~ / /;
        return "/say $trigger_name belongs to $channel_name, not $from_chan. Please switch to or explicitly specify $channel_name.";
    }
    return ($channel, $trigger, $remaining_args);
}

sub hash_differences_as_string {
    my ($self, $old, $new) = @_;
    my @exclude = qw/created_on last_referenced_in last_referenced_on ref_count ref_user edited_by edited_on/;
    my %diff;

    foreach my $key (keys %$new) {
        next if grep { $key eq $_ } @exclude;
        if (not exists $old->{$key} or $old->{$key} ne $new->{$key}) { $diff{$key} = $new->{$key}; }
    }

    foreach my $key (keys %$old) {
        next if grep { $key eq $_ } @exclude;
        if (not exists $new->{$key}) { $diff{"deleted $key"} = undef; }
    }

    return "No change." if not keys %diff;

    my $changes = "";
    my $comma   = "";
    foreach my $key (sort keys %diff) {
        if   (defined $diff{$key}) { $changes .= "$comma$key => $diff{$key}"; }
        else                       { $changes .= "$comma$key"; }
        $comma = ", ";
    }
    return $changes;
}

sub list_undo_history {
    my ($self, $undos, $start_from) = @_;

    $start_from-- if defined $start_from;
    $start_from = 0 if not defined $start_from or $start_from < 0;

    my $result = "";
    if ($start_from > @{$undos->{list}}) {
        if   (@{$undos->{list}} == 1) { return "But there is only one revision available."; }
        else                          { return "But there are only " . @{$undos->{list}} . " revisions available."; }
    }

    if ($start_from == 0) {
        if   ($undos->{idx} == 0) { $result .= "*1*: "; }
        else                      { $result .= "1: "; }
        $result .= $self->hash_differences_as_string({}, $undos->{list}->[0]) . ";\n\n";
        $start_from++;
    }

    for (my $i = $start_from; $i < @{$undos->{list}}; $i++) {
        if   ($i == $undos->{idx}) { $result .= "*" . ($i + 1) . "*: "; }
        else                       { $result .= ($i + 1) . ": "; }
        $result .= $self->hash_differences_as_string($undos->{list}->[$i - 1], $undos->{list}->[$i]);
        $result .= ";\n\n";
    }
    return $result;
}

1;
