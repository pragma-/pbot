# File: Registry.pm
# Author: pragma_
#
# Purpose: Provides a centralized registry of configuration settings that can
# easily be examined and updated via getters and setters.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Registry;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';
use utf8;

use Time::HiRes qw(gettimeofday);
use PBot::RegistryCommands;

sub initialize {
    my ($self, %conf) = @_;

    # ensure we have a registry filename
    my $filename = $conf{filename} // Carp::croak("Missing filename configuration item in " . __FILE__);

    # registry is stored as a dual-index hash object
    $self->{registry} = PBot::DualIndexHashObject->new(name => 'Registry', filename => $filename, pbot => $self->{pbot});

    # registry triggers are processed when a registry entry is modified
    $self->{triggers} = {};

    # save registry data at bot exit
    $self->{pbot}->{atexit}->register(sub { $self->save; return; });

    # prepare registry-specific bot commands
    PBot::RegistryCommands->new(pbot => $self->{pbot});

    # load existing registry entries from file (if exists)
    if (-e $filename) {
        $self->load;
    } else {
        $self->{pbot}->{logger}->log("No registry found at $filename, using defaults.\n");
    }

    # add default registry items
    $self->add_default('text', 'general', 'data_dir',      $conf{data_dir});
    $self->add_default('text', 'general', 'module_dir',    $conf{module_dir});
    $self->add_default('text', 'general', 'plugin_dir',    $conf{plugin_dir});
    $self->add_default('text', 'general', 'update_dir',    $conf{update_dir});

    # bot trigger
    $self->add_default('text', 'general', 'trigger',       $conf{trigger}           // '!');

    # irc
    $self->add_default('text', 'irc', 'debug',             $conf{irc_debug}         // 0);
    $self->add_default('text', 'irc', 'show_motd',         $conf{show_motd}         // 1);
    $self->add_default('text', 'irc', 'max_msg_len',       $conf{max_msg_len}       // 425);
    $self->add_default('text', 'irc', 'server',            $conf{server}            // "irc.libera.chat");
    $self->add_default('text', 'irc', 'port',              $conf{port}              // 6667);
    $self->add_default('text', 'irc', 'sasl',              $conf{SASL}              // 0);
    $self->add_default('text', 'irc', 'ssl',               $conf{SSL}               // 0);
    $self->add_default('text', 'irc', 'ssl_ca_file',       $conf{SSL_ca_file}       // 'none');
    $self->add_default('text', 'irc', 'ssl_ca_path',       $conf{SSL_ca_path}       // 'none');
    $self->add_default('text', 'irc', 'botnick',           $conf{botnick}           // "");
    $self->add_default('text', 'irc', 'username',          $conf{username}          // "pbot3");
    $self->add_default('text', 'irc', 'realname',          $conf{realname}          // "https://github.com/pragma-/pbot");
    $self->add_default('text', 'irc', 'identify_password', $conf{identify_password} // '');
    $self->add_default('text', 'irc', 'log_default_handler', 1);

    # interpreter
    $self->add_default('text', 'interpreter', 'max_embed', 3);

    # make sensitive entries private
    $self->set_default('irc', 'SSL_ca_file',       'private', 1);
    $self->set_default('irc', 'SSL_ca_path',       'private', 1);
    $self->set_default('irc', 'identify_password', 'private', 1);

    # customizable regular expressions
    $self->add_default('text', 'regex', 'nickname', '[_a-zA-Z0-9\[\]{}`\\-]+');

    # update important paths
    $self->set('general', 'data_dir',   'value', $conf{data_dir},   0, 1);
    $self->set('general', 'module_dir', 'value', $conf{module_dir}, 0, 1);
    $self->set('general', 'plugin_dir', 'value', $conf{plugin_dir}, 0, 1);
    $self->set('general', 'update_dir', 'value', $conf{update_dir}, 0, 1);

    # override registry entries with command-line arguments, if any
    foreach my $override (keys %{$self->{pbot}->{overrides}}) {
        my $value = $self->{pbot}->{overrides}->{$override};
        my ($section, $key) = split /\./, $override;

        $self->{pbot}->{logger}->log("Overriding $section.$key to $value\n");

        $self->set($section, $key, 'value', $value, 0, 1);
    }

    # add triggers
    $self->add_trigger('irc', 'debug',   sub { $self->trigger_irc_debug(@_) });
    $self->add_trigger('irc', 'botnick', sub { $self->trigger_change_botnick(@_) });
}

# registry triggers fire when value changes

sub trigger_irc_debug {
    my ($self, $section, $item, $newvalue) = @_;

    $self->{pbot}->{irc}->debug($newvalue);

    if ($self->{pbot}->{connected}) {
        $self->{pbot}->{conn}->debug($newvalue);
    }
}

sub trigger_change_botnick {
    my ($self, $section, $item, $newvalue) = @_;

    if ($self->{pbot}->{connected}) {
        $self->{pbot}->{conn}->nick($newvalue)
    }
}

# registry api

sub load {
    my $self = shift;

    # load registry from file
    $self->{registry}->load;

    # fire off all registered triggers
    foreach my $section ($self->{registry}->get_keys) {
        foreach my $item ($self->{registry}->get_keys($section)) {
            $self->process_trigger($section, $item, $self->{registry}->get_data($section, $item, 'value'));
        }
    }
}

sub save {
    my $self = shift;

    $self->{registry}->save;
}

sub add_default {
    my ($self, $type, $section, $item, $value) = @_;

    $self->add($type, $section, $item, $value, 1);
}

sub add {
    my ($self, $type, $section, $item, $value, $is_default) = @_;

    $type = lc $type;

    if (not $self->{registry}->exists($section, $item)) {
        # registry entry does not exist

        my $data = {
            value => $value,
            type  => $type,
        };

        $self->{registry}->add($section, $item, $data, 1);
    } else {
        # registry entry already exists

        if ($is_default) {
            # don't replace existing registry values if we're just adding a default value
            return;
        }

        # update value
        $self->{registry}->set($section, $item, 'value', $value, 1);

        # update type only if it doesn't exist
        unless ($self->{registry}->exists($section, $item, 'type')) {
            $self->{registry}->set($section, $item, 'type', $type, 1);
        }
    }

    unless ($is_default) {
        $self->process_trigger($section, $item, $value);
        $self->save;
    }
}

sub remove {
    my ($self, $section, $item) = @_;

    $self->{registry}->remove($section, $item);
}

sub set_default {
    my ($self, $section, $item, $key, $value) = @_;

    $self->set($section, $item, $key, $value, 1);
}

sub set {
    my ($self, $section, $item, $key, $value, $is_default, $dont_save) = @_;

    $key = lc $key if defined $key;

    if ($is_default && $self->{registry}->exists($section, $item, $key)) {
        return;
    }

    my $oldvalue;

    if (defined $value) {
        $oldvalue = $self->get_value($section, $item, 1);
    }

    $oldvalue //= '';

    my $result = $self->{registry}->set($section, $item, $key, $value, 1);

    if (defined $key and $key eq 'value' and defined $value and $oldvalue ne $value) {
        $self->process_trigger($section, $item, $value);
    }

    $self->save if !$dont_save && $result =~ m/set to/ && not $is_default;

    return $result;
}

sub unset {
    my ($self, $section, $item, $key) = @_;

    $key = lc $key if defined $key;

    return $self->{registry}->unset($section, $item, $key);
}

sub get_value {
    my ($self, $section, $item, $as_text, $context) = @_;

    $section = lc $section;
    $item    = lc $item;

    my $key = $item;

    # TODO: use user-metadata for this
    if (defined $context and exists $context->{nick}) {
        my $context_nick = lc $context->{nick};
        if ($self->{registry}->exists($section, "$item.nick.$context_nick")) {
            $key = "$item.nick.$context_nick";
        }
    }

    if ($self->{registry}->exists($section, $key)) {
        if (not $as_text and $self->{registry}->get_data($section, $key, 'type') eq 'array') {
            return split /\s*,\s*/, $self->{registry}->get_data($section, $key, 'value');
        } else {
            return $self->{registry}->get_data($section, $key, 'value');
        }
    }

    return undef;
}

sub get_array_value {
    my ($self, $section, $item, $index, $context) = @_;

    $section = lc $section;
    $item    = lc $item;

    my $key = $item;

    # TODO: use user-metadata for this
    if (defined $context and exists $context->{nick}) {
        my $context_nick = lc $context->{nick};
        if ($self->{registry}->exists($section, "$item.nick.$context_nick")) {
            $key = "$item.nick.$context_nick";
        }
    }

    if ($self->{registry}->exists($section, $key)) {
        if ($self->{registry}->get_data($section, $key, 'type') eq 'array') {
            my @array = split /\s*,\s*/, $self->{registry}->get_data($section, $key, 'value');
            return $array[$index >= $#array ? $#array : $index];
        } else {
            return $self->{registry}->get_data($section, $key, 'value');
        }
    }

    return undef;
}

sub add_trigger {
    my ($self, $section, $item, $subref) = @_;

    $self->{triggers}->{lc $section}->{lc $item} = $subref;
}

sub process_trigger {
    my $self = shift;           # shift $self off of the top of @_
    my ($section, $item) = @_;  # but leave $section, $item and anything else (i.e. $value) in @_

    $section = lc $section;
    $item    = lc $item;

    if (exists $self->{triggers}->{$section} and exists $self->{triggers}->{$section}->{$item}) {
        return &{$self->{triggers}->{$section}->{$item}}(@_); # $section, $item, $value, etc in @_
    }

    return undef;
}

1;
