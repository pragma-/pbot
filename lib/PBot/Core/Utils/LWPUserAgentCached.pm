# File: LWPUserAgentCached.pm
#
# Purpose: variant of LWP::UserAgent::WithCache. Instead of depending on
# the 'expires' or 'Last-Modified' attributes, we always cache for the
# specified duration.

# SPDX-FileCopyrightText: 2021-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Utils::LWPUserAgentCached;

use PBot::Imports;

use base qw/LWP::UserAgent/;
use Cache::FileCache;
use File::HomeDir;
use File::Spec;

our %default_cache_args = (
    'namespace'          => 'pbot-cached',
    'cache_root'         => File::Spec->catfile(File::HomeDir->my_home, '.cache'),
    'default_expires_in' => 600
);

sub new($class, @args) {
    my $cache_opt;
    my %lwp_opt;
    unless (scalar @args % 2) {
        %lwp_opt   = @args;
        $cache_opt = {};
        for my $key (qw(namespace cache_root default_expires_in)) { $cache_opt->{$key} = delete $lwp_opt{$key} if exists $lwp_opt{$key}; }
    } else {
        $cache_opt = shift @args || {};
        %lwp_opt   = @args;
    }
    my $self       = $class->SUPER::new(%lwp_opt);
    my %cache_args = (%default_cache_args, %$cache_opt);
    $self->{cache} = Cache::FileCache->new(\%cache_args);
    return $self;
}

sub request($self, @args) {
    my $request = $args[0];
    return $self->SUPER::request(@args) if $request->method ne 'GET';

    my $uri    = $request->uri->as_string;
    my $cached = $self->{cache}->get($uri);
    return HTTP::Response->parse($cached) if defined $cached;

    my $res = $self->SUPER::request(@args);
    $self->{cache}->set($uri, $res->as_string) if $res->code eq HTTP::Status::RC_OK;
    return $res;
}

1;
