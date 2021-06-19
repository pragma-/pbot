# File: RegistryCommands.pm
#
# Purpose: Bot commands to manipulate Registry entries.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::RegistryCommands;
use parent 'PBot::Class';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->cmd_regset(@_) },       "regset",       1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_regunset(@_) },     "regunset",     1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_regshow(@_) },      "regshow",      0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_regsetmeta(@_) },   "regsetmeta",   1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_regunsetmeta(@_) }, "regunsetmeta", 1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_regchange(@_) },    "regchange",    1);
    $self->{pbot}->{commands}->register(sub { $self->cmd_regfind(@_) },      "regfind",      0);
}

sub cmd_regset {
    my ($self, $context) = @_;

    my $usage = "Usage: regset <section>.<item> [value]";

    # support "<section>.<key>" syntax in addition to "<section> <key>"
    my $section = $self->{pbot}->{interpreter}->shift_arg($context->{arglist}) // return $usage;
    my ($item, $value);

    if ($section =~ m/^(.+?)\.(.+)$/) {
        ($section, $item) = ($1, $2);
        ($value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 1);
    } else {
        ($item, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
    }

    if (not defined $section or not defined $item) {
        return $usage;
    }

    if (defined $value) {
        $self->{pbot}->{registry}->add('text', $section, $item, $value);
    } else {
        return $self->{pbot}->{registry}->set($section, $item, 'value');
    }

    $self->{pbot}->{logger}->log("$context->{hostmask} set registry entry $section.$item => $value\n");

    return "$section.$item set to $value";
}

sub cmd_regunset {
    my ($self, $context) = @_;

    my $usage = "Usage: regunset <section>.<item>";

    # support "<section>.<key>" syntax in addition to "<section> <key>"
    my $section = $self->{pbot}->{interpreter}->shift_arg($context->{arglist}) // return $usage;
    my $item;

    if ($section =~ m/^(.+?)\.(.+)$/) {
        ($section, $item) = ($1, $2);
    } else {
        ($item) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 1);
    }

    if (not defined $section or not defined $item) {
        return $usage;
    }

    if (not $self->{pbot}->{registry}->{registry}->exists($section)) {
        return "No such registry section $section.";
    }

    if (not $self->{pbot}->{registry}->{registry}->exists($section, $item)) {
        return "No such item $item in section $section.";
    }

    $self->{pbot}->{logger}->log("$context->{hostmask} removed registry entry $section.$item\n");

    $self->{pbot}->{registry}->remove($section, $item);

    return "$section.$item deleted from registry";
}

sub cmd_regsetmeta {
    my ($self, $context) = @_;

    my $usage = "Usage: regsetmeta <section>.<item> [key [value]]";

    # support "<section>.<key>" syntax in addition to "<section> <key>"
    my $section = $self->{pbot}->{interpreter}->shift_arg($context->{arglist}) // return $usage;
    my ($item, $key, $value);

    if ($section =~ m/^(.+?)\.(.+)$/) {
        ($section, $item)  = ($1, $2);
        ($key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
    } else {
        ($item, $key, $value) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 3);
    }

    if (not defined $section or not defined $item) {
        return $usage;
    }

    $key   = undef if not length $key;
    $value = undef if not length $value;

    return $self->{pbot}->{registry}->set($section, $item, $key, $value);
}

sub cmd_regunsetmeta {
    my ($self, $context) = @_;

    my $usage = "Usage: regunsetmeta <section>.<item> <key>";

    # support "<section>.<key>" syntax in addition to "<section> <key>"
    my $section = $self->{pbot}->{interpreter}->shift_arg($context->{arglist}) // return $usage;
    my ($item, $key);

    if ($section =~ m/^(.+?)\.(.+)$/) {
        ($section, $item) = ($1, $2);
        ($key) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 1);
    } else {
        ($item, $key) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
    }

    if (not defined $section or not defined $item or not defined $key) {
        return $usage;
    }

    return $self->{pbot}->{registry}->unset($section, $item, $key);
}

sub cmd_regshow {
    my ($self, $context) = @_;

    my $usage    = "Usage: regshow <section>.<item>";
    my $registry = $self->{pbot}->{registry}->{registry};

    # support "<section>.<key>" syntax in addition to "<section> <key>"
    my $section = $self->{pbot}->{interpreter}->shift_arg($context->{arglist}) // return $usage;
    my $item;

    if ($section =~ m/^(.+?)\.(.+)$/) {
        ($section, $item) = ($1, $2);
    } else {
        ($item) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 1);
    }

    if (not defined $section or not defined $item) {
        return $usage;
    }

    if (not $registry->exists($section)) {
        return "No such registry section $section.";
    }

    if (not $registry->exists($section, $item)) {
        return "No such registry item $item in section $section.";
    }

    if ($registry->get_data($section, $item, 'private')) {
        return "$section.$item: <private>";
    }

    my $result = "$section.$item: " . $registry->get_data($section, $item, 'value');

    if ($registry->get_data($section, $item, 'type') eq 'array') {
        $result .= ' [array]';
    }

    return $result;
}

sub cmd_regfind {
    my ($self, $context) = @_;

    my $usage     = "Usage: regfind [-showvalues] [-section section] <regex>";
    my $registry  = $self->{pbot}->{registry}->{registry};

    my $arguments = $context->{arguments};

    return $usage if not defined $arguments;

    # TODO maybe use GetOptionsFromArray here
    my ($section, $showvalues);
    $section    = $1 if $arguments =~ s/-section\s+([^\b\s]+)//i;
    $showvalues = 1  if $arguments =~ s/-showvalues?//i;

    $arguments =~ s/^\s+|\s+$//g;
    $arguments =~ s/\s+/ /g;

    return $usage if not length $arguments;

    $section = lc $section if defined $section;

    my ($text, $last_item, $last_section, $count);
    $last_section = '';
    $count        = 0;

    eval {
        use re::engine::RE2 -strict => 1; # prevent user-defined regex from exploding

        foreach my $section_key (sort $registry->get_keys) {
            next if defined $section and $section_key ne $section;
            foreach my $item_key (sort $registry->get_keys($section_key)) {
                next if $item_key eq '_name'; # skip internal cached value

                if ($registry->get_data($section_key, $item_key, 'private')) {
                    # if private, match on key only -- do not match on value
                    next if $item_key !~ /$arguments/i;
                } else {
                    # otherwise check for match on key and value
                    next if $item_key !~ /$arguments/i and $registry->get_data($section_key, $item_key, 'value') !~ /$arguments/i;
                }

                $count++;

                if ($section_key ne $last_section) {
                    $text .= "[$section_key]\n";
                    $last_section = $section_key;
                }

                if ($showvalues) {
                    if ($registry->get_data($section_key, $item_key, 'private')) {
                        $text .= "  $item_key = <private>\n";
                    } else {
                        $text .= "  $item_key = " . $registry->get_data($section_key, $item_key, 'value')
                          . ($registry->get_data($section_key, $item_key, 'type') eq 'array' ? " [array]\n" : "\n");
                    }
                } else {
                    $text .= "  $item_key\n";
                }

                $last_item = $item_key;
            }
        }
    };

    return "/msg $context->{nick} $context->{arguments}: $@" if $@;

    if ($count == 1) {
        chomp $text;

        if ($registry->get_data($last_section, $last_item, 'private')) {
            return "Found one registry entry: [$last_section] $last_item: <private>";
        } else {
            return
                "Found one registry entry: [$last_section] $last_item: "
              . $registry->get_data($last_section, $last_item, 'value')
              . ($registry->get_data($last_section, $last_item, 'type') eq 'array' ? ' [array]' : '');
        }
    } elsif ($count > 1) {
        return "Found $count registry entries:\n$text";
    } else {
        my $sections = (defined $section ? "section $section" : 'any sections');
        return "No matching registry entries found in $sections.";
    }
}

sub cmd_regchange {
    my ($self, $context) = @_;

    my ($section, $item, $delim, $tochange, $changeto, $modifier);

    my $arguments = $context->{arguments};

    if (length $arguments) {
        if ($arguments =~ /^(.+?)\.([^\s]+)\s+s(.)/ or $arguments =~ /^([^\s]+) ([^\s]+)\s+s(.)/) {
            $section = $1;
            $item    = $2;
            $delim   = $3;
        }

        if ($arguments =~ /$delim(.*?)$delim(.*)$delim(.*)?$/) {
            $tochange = $1;
            $changeto = $2;
            $modifier = $3;
        }
    }

    if (not defined $section or not defined $item or not defined $changeto) {
        return "Usage: regchange <section>.<item> s/<pattern>/<replacement>/";
    }

    $section = lc $section;
    $item    = lc $item;

    my $registry = $self->{pbot}->{registry}->{registry};

    if (not $registry->exists($section)) {
        return "No such registry section $section.";
    }

    if (not $registry->exists($section, $item)) {
        return "No such registry item $item in section $section.";
    }

    my $result = eval {
        use re::engine::RE2 -strict => 1; # prevent user-defined regex from exploding

        my $value = $registry->get_data($section, $item, 'value');

        if (not $value =~ s|$tochange|$changeto|) {
            $self->{pbot}->{logger}->log("($context->{from}) $context->{hostmask}: failed to change $section.$item 's$delim$tochange$delim$changeto$delim$modifier\n");
            return "/msg $context->{nick} Change $section.$item failed.";
        } else {
            $registry->set($section, $item, 'value', $value, 1);

            $self->{pbot}->{logger}->log("($context->{from}) $context->{hostmask}: changed $section.$item 's/$tochange/$changeto/\n");
            $self->{pbot}->{registry}->process_trigger($section, $item, 'value', $value);
            $self->{pbot}->{registry}->save;
            return "$section.$item set to $value";
        }
    };

    return "/msg $context->{nick} Failed to change $section.$item: $@" if $@;

    return $result;
}

1;
