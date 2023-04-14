# File: Registry.pm
#
# Purpose: Provides a centralized registry of configuration settings that can
# easily be examined and updated via getters and setters.

# SPDX-FileCopyrightText: 2014-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Registry;
use parent 'PBot::Core::Class';

use PBot::Imports;

sub initialize($self, %conf) {
    # ensure we have a registry filename
    my $filename = $conf{filename} // Carp::croak("Missing filename configuration item in " . __FILE__);

    # registry is stored as a dual-index hash object
    $self->{storage} = PBot::Core::Storage::DualIndexHashObject->new(
        pbot     => $self->{pbot},
        name     => 'Registry',
        filename => $filename,
    );

    # registry triggers are processed when a registry entry is modified
    $self->{triggers} = {};

    # save registry data at bot exit
    $self->{pbot}->{atexit}->register(sub { $self->save });

    # load existing registry entries from file (if exists)
    if (-e $filename) {
        $self->load;
    } else {
        $self->{pbot}->{logger}->log("No registry found at $filename, using defaults.\n");
    }

    # add default registry items
    $self->add_default('text', 'general', 'data_dir',      $conf{data_dir});
    $self->add_default('text', 'general', 'applet_dir',    $conf{applet_dir});
    $self->add_default('text', 'general', 'update_dir',    $conf{update_dir});

    # bot trigger
    $self->add_default('text', 'general', 'trigger',       $conf{trigger}           // '!');

    # irc
    $self->add_default('text', 'irc', 'debug',             $conf{irc_debug}         // 0);
    $self->add_default('text', 'irc', 'show_motd',         $conf{show_motd}         // 1);
    $self->add_default('text', 'irc', 'max_msg_len',       $conf{max_msg_len}       // 460);
    $self->add_default('text', 'irc', 'server',            $conf{server}            // "irc.libera.chat");
    $self->add_default('text', 'irc', 'port',              $conf{port}              // 6667);
    $self->add_default('text', 'irc', 'sasl',              $conf{SASL}              // 0);
    $self->add_default('text', 'irc', 'tls',               $conf{TLS}               // 0);
    $self->add_default('text', 'irc', 'tls_ca_file',       $conf{TLS_ca_file}       // '');
    $self->add_default('text', 'irc', 'tls_ca_path',       $conf{TLS_ca_path}       // '');
    $self->add_default('text', 'irc', 'botnick',           $conf{botnick}           // "");
    $self->add_default('text', 'irc', 'username',          $conf{username}          // "pbot3");
    $self->add_default('text', 'irc', 'realname',          $conf{realname}          // "https://github.com/pragma-/pbot");
    $self->add_default('text', 'irc', 'identify_password', $conf{identify_password} // '');
    $self->add_default('text', 'irc', 'log_default_handler', 1);

    # interpreter
    $self->add_default('text', 'interpreter', 'max_embed', 3);

    # make sensitive entries private
    $self->set_default('irc', 'tls_ca_file',       'private', 1);
    $self->set_default('irc', 'tls_ca_path',       'private', 1);
    $self->set_default('irc', 'identify_password', 'private', 1);

    # customizable regular expressions
    $self->add_default('text', 'regex', 'nickname', '[_a-zA-Z0-9\[\]{}`\\-]+');

    # update important paths
    $self->set('general', 'data_dir',   'value', $conf{data_dir},   0, 1);
    $self->set('general', 'applet_dir', 'value', $conf{applet_dir}, 0, 1);
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

sub trigger_irc_debug($self, $section, $item, $newvalue) {
    $self->{pbot}->{irc}->debug($newvalue);

    if ($self->{pbot}->{conn}) {
        $self->{pbot}->{conn}->debug($newvalue);
    }
}

sub trigger_change_botnick($self, $section, $item, $newvalue) {
    if ($self->{pbot}->{conn}) {
        $self->{pbot}->{conn}->nick($newvalue)
    }
}

# registry api

sub load($self) {
    # load registry from file
    $self->{storage}->load;

    # fire off all registered triggers
    foreach my $section ($self->{storage}->get_keys) {
        foreach my $item ($self->{storage}->get_keys($section)) {
            $self->process_trigger($section, $item, $self->{storage}->get_data($section, $item, 'value'));
        }
    }
}

sub save($self) {
    $self->{storage}->save;
}

sub add_default($self, $type, $section, $item, $value) {
    $self->add($type, $section, $item, $value, 1);
}

sub add($self, $type, $section, $item, $value, $is_default = 0) {
    $type = lc $type;

    if (not $self->{storage}->exists($section, $item)) {
        # registry entry does not exist

        my $data = {
            value => $value,
            type  => $type,
        };

        $self->{storage}->add($section, $item, $data, 1);
    } else {
        # registry entry already exists

        if ($is_default) {
            # don't replace existing registry values if we're just adding a default value
            return;
        }

        # update value
        $self->{storage}->set($section, $item, 'value', $value, 1);

        # update type only if it doesn't exist
        unless ($self->{storage}->exists($section, $item, 'type')) {
            $self->{storage}->set($section, $item, 'type', $type, 1);
        }
    }

    unless ($is_default) {
        $self->process_trigger($section, $item, $value);
        $self->save;
    }
}

sub remove($self, $section, $item) {
    $self->{storage}->remove($section, $item);
}

sub set_default($self, $section, $item, $key, $value) {
    $self->set($section, $item, $key, $value, 1);
}

sub set($self, $section, $item, $key = undef, $value = undef, $is_default = 0, $dont_save = 0) {
    $key = lc $key if defined $key;

    if ($is_default && $self->{storage}->exists($section, $item, $key)) {
        return;
    }

    my $oldvalue;

    if (defined $value) {
        $oldvalue = $self->get_value($section, $item, 1);
    }

    $oldvalue //= '';

    my $result = $self->{storage}->set($section, $item, $key, $value, 1);

    if (defined $key and $key eq 'value' and defined $value and $oldvalue ne $value) {
        $self->process_trigger($section, $item, $value);
    }

    $self->save if !$dont_save && $result =~ m/set to/ && not $is_default;

    return $result;
}

sub unset($self, $section, $item, $key = undef) {
    $key = lc $key if defined $key;
    return $self->{storage}->unset($section, $item, $key);
}

sub get_value($self, $section, $item, $as_text = undef, $context = undef) {
    $section = lc $section;
    $item    = lc $item;

    my $key = $item;

    # TODO: use user-metadata for this
    if (defined $context and exists $context->{nick}) {
        my $context_nick = lc $context->{nick};
        if ($self->{storage}->exists($section, "$item.nick.$context_nick")) {
            $key = "$item.nick.$context_nick";
        }
    }

    if ($self->{storage}->exists($section, $key)) {
        if (not $as_text and $self->{storage}->get_data($section, $key, 'type') eq 'array') {
            return split /\s*,\s*/, $self->{storage}->get_data($section, $key, 'value');
        } else {
            return $self->{storage}->get_data($section, $key, 'value');
        }
    }

    return undef;
}

sub get_array_value($self, $section, $item, $index, $context = undef) {
    $section = lc $section;
    $item    = lc $item;

    my $key = $item;

    # TODO: use user-metadata for this
    if (defined $context and exists $context->{nick}) {
        my $context_nick = lc $context->{nick};
        if ($self->{storage}->exists($section, "$item.nick.$context_nick")) {
            $key = "$item.nick.$context_nick";
        }
    }

    if ($self->{storage}->exists($section, $key)) {
        if ($self->{storage}->get_data($section, $key, 'type') eq 'array') {
            my @array = split /\s*,\s*/, $self->{storage}->get_data($section, $key, 'value');
            return $array[$index >= $#array ? $#array : $index];
        } else {
            return $self->{storage}->get_data($section, $key, 'value');
        }
    }

    return undef;
}

sub add_trigger($self, $section, $item, $subref) {
    $self->{triggers}->{lc $section}->{lc $item} = $subref;
}

sub process_trigger($self, @args) {
    my ($section, $item) = @args;

    $section = lc $section;
    $item    = lc $item;

    if (exists $self->{triggers}->{$section} and exists $self->{triggers}->{$section}->{$item}) {
        return &{$self->{triggers}->{$section}->{$item}}(@args);
    }

    return undef;
}

1;
