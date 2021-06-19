# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::GoogleSearch;
use parent 'Plugins::Plugin';

use PBot::Imports;

use WWW::Google::CustomSearch;
use HTML::Entities;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{registry}->add_default('text', 'googlesearch', 'api_key', '');
    $self->{pbot}->{registry}->add_default('text', 'googlesearch', 'context', '');

    $self->{pbot}->{registry}->set_default('googlesearch', 'api_key', 'private', 1);
    $self->{pbot}->{registry}->set_default('googlesearch', 'context', 'private', 1);

    $self->{pbot}->{commands}->register(sub { $self->cmd_googlesearch(@_) }, 'google', 0);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister('google');
}

sub cmd_googlesearch {
    my ($self, $context) = @_;
    return "Usage: google [number of results] query\n" if not length $context->{arguments};

    my $matches = 1;
    $matches = $1 if $context->{arguments} =~ s/^-n\s+([0-9]+)\s*//;

    my $api_key = $self->{pbot}->{registry}->get_value('googlesearch', 'api_key');    # https://developers.google.com/custom-search/v1/overview
    my $cx      = $self->{pbot}->{registry}->get_value('googlesearch', 'context');    # https://cse.google.com/all

    if (not length $api_key) {
        return "$context->{nick}: Registry item googlesearch.api_key is not set. See https://developers.google.com/custom-search/v1/overview to get an API key.";
    }

    if (not length $cx) { return "$context->{nick}: Registry item googlesearch.context is not set. See https://cse.google.com/all to set up a context."; }

    my $engine = WWW::Google::CustomSearch->new(api_key => $api_key, cx => $cx, quotaUser => $context->{hostmask});

    if ($context->{arguments} =~ m/(.*)\s+vs\s+(.*)/i) {
        my ($a, $b) = ($1, $2);
        my $result1 = $engine->search("\"$a\" -\"$b\"");
        my $result2 = $engine->search("\"$b\" -\"$a\"");

        if (not defined $result1 or not defined $result1->items or not @{$result1->items}) { return "$context->{nick}: No results for $a"; }

        if (not defined $result2 or not defined $result2->items or not @{$result2->items}) { return "$context->{nick}: No results for $b"; }

        my $title1 = $result1->items->[0]->title;
        my $title2 = $result2->items->[0]->title;

        utf8::decode $title1;
        utf8::decode $title2;

        return
            "$context->{nick}: $a: ("
          . $result1->formattedTotalResults . ") "
          . decode_entities($title1) . " <"
          . $result1->items->[0]->link
          . "> VS $b: ("
          . $result2->formattedTotalResults . ") "
          . decode_entities($title2) . " <"
          . $result2->items->[0]->link . ">";
    }

    my $result = eval { $engine->search($context->{arguments}) };

    if ($@) {
        my $error = $@;
        $error =~ s/^WWW::Google::CustomSearch::search\(\): /google: /;
        $error =~ s/file .*?$//;
        $error =~ s/Missing required arguments: totalResults.*/No results./;
        return $error;
    }

    if (not defined $result or not defined $result->items or not @{$result->items}) { return "$context->{nick}: No results found"; }

    my $output = "$context->{nick}: (" . $result->formattedTotalResults . " results) ";

    my $comma = "";
    foreach my $item (@{$result->items}) {
        my $title = $item->title;
        utf8::decode $title;
        $output .= $comma . decode_entities($title) . ': <' . $item->link . ">";
        $comma = " -- ";
        last if --$matches <= 0;
    }
    return $output;
}

1;
