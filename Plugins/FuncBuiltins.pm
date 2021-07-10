# File: FuncBuiltins.pm
#
# Purpose: Registers the basic built-in Functions

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package Plugins::FuncBuiltins;
use parent 'Plugins::Plugin';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{functions}->register(
        'title',
        {
            desc   => 'Title-cases text',
            usage  => 'title <text>',
            subref => sub { $self->func_title(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'ucfirst',
        {
            desc   => 'Uppercases first character',
            usage  => 'ucfirst <text>',
            subref => sub { $self->func_ucfirst(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'uc',
        {
            desc   => 'Uppercases all characters',
            usage  => 'uc <text>',
            subref => sub { $self->func_uc(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'lc',
        {
            desc   => 'Lowercases all characters',
            usage  => 'lc <text>',
            subref => sub { $self->func_lc(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'unquote',
        {
            desc   => 'removes unescaped surrounding quotes and strips escapes from escaped quotes',
            usage  => 'unquote <text>',
            subref => sub { $self->func_unquote(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'uri_escape',
        {
            desc   => 'percent-encode unsafe URI characters',
            usage  => 'uri_escape <text>',
            subref => sub { $self->func_uri_escape(@_) }
        }
    );
}

sub unload {
    my $self = shift;
    $self->{pbot}->{functions}->unregister('title');
    $self->{pbot}->{functions}->unregister('ucfirst');
    $self->{pbot}->{functions}->unregister('uc');
    $self->{pbot}->{functions}->unregister('lc');
    $self->{pbot}->{functions}->unregister('unquote');
    $self->{pbot}->{functions}->unregister('uri_escape');
}

sub func_unquote {
    my $self = shift;
    my $text = "@_";
    $text =~ s/^"(.*?)(?<!\\)"$/$1/ || $text =~ s/^'(.*?)(?<!\\)'$/$1/;
    $text =~ s/(?<!\\)\\'/'/g;
    $text =~ s/(?<!\\)\\"/"/g;
    return $text;
}

sub func_title {
    my $self = shift;
    my $text = "@_";
    $text = ucfirst lc $text;
    $text =~ s/ (\w)/' ' . uc $1/ge;
    return $text;
}

sub func_ucfirst {
    my $self = shift;
    my $text = "@_";
    return ucfirst $text;
}

sub func_uc {
    my $self = shift;
    my $text = "@_";
    return uc $text;
}

sub func_lc {
    my $self = shift;
    my $text = "@_";
    return lc $text;
}

use URI::Escape qw/uri_escape_utf8/;

sub func_uri_escape {
    my $self = shift;
    my $text = "@_";
    return uri_escape_utf8($text);
}

1;
