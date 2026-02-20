# File: FuncBuiltins.pm
#
# Purpose: Registers the basic built-in Functions

# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::FuncBuiltins;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use PBot::Core::Utils::Indefinite;

use Lingua::EN::Tagger;
use URI::Escape qw/uri_escape_utf8/;

use JSON::XS;

sub initialize($self, %conf) {
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
        'maybe-ucfirst',
        {
            desc   => 'Uppercases first character unless nick',
            usage  => 'maybe-ucfirst <text>',
            subref => sub { $self->func_maybe_ucfirst(@_) }
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
        'unescape',
        {
            desc   => 'removes unescaped escapes',
            usage  => 'unescape <text>',
            subref => sub { $self->func_unescape(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'shquote',
        {
            desc   => 'quotes text for sh invocation',
            usage  => 'shquote <text>',
            subref => sub { $self->func_shquote(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'quotemeta',
        {
            desc   => 'escapes/quotes metacharacters',
            usage  => 'quotemeta <text>',
            subref => sub { $self->func_quotemeta(@_) }
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
    $self->{pbot}->{functions}->register(
        'ana',
        {
            desc   => 'fix-up a/an article at front of text',
            usage  => 'ana <text>',
            subref => sub { $self->func_ana(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'maybe-the',
        {
            desc   => 'prepend "the" in front of text depending on the part-of-speech of the first word in text',
            usage  => 'maybe-the <text>',
            subref => sub { $self->func_maybe_the(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'maybe-to',
        {
            desc   => 'prepend "to" in front of text depending on the part-of-speech of the first word in text',
            usage  => 'maybe-to <text>',
            subref => sub { $self->func_maybe_to(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'maybe-on',
        {
            desc   => 'prepend "on" in front of text depending on the part-of-speech of the first word in text',
            usage  => 'maybe-on <text>',
            subref => sub { $self->func_maybe_on(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'length',
        {
            desc   => 'print length of text',
            usage  => 'length <text>',
            subref => sub { $self->func_length(@_) }
        }
    );
    $self->{pbot}->{functions}->register(
        'jsonval',
        {
            desc   => 'extract a JSON value from a JSON structure',
            usage  => 'jsonval <member> <json>; e.g. jsonval .a.b[1] {"a": {"b": [10, 20, 30]}}',
            subref => sub { $self->func_jsonval(@_) }
        }
    );

    $self->{tagger} = Lingua::EN::Tagger->new;
}

sub unload($self) {
    $self->{pbot}->{functions}->unregister('title');
    $self->{pbot}->{functions}->unregister('maybe-ucfirst');
    $self->{pbot}->{functions}->unregister('ucfirst');
    $self->{pbot}->{functions}->unregister('uc');
    $self->{pbot}->{functions}->unregister('lc');
    $self->{pbot}->{functions}->unregister('unquote');
    $self->{pbot}->{functions}->unregister('unescape');
    $self->{pbot}->{functions}->unregister('shquote');
    $self->{pbot}->{functions}->unregister('quotemeta');
    $self->{pbot}->{functions}->unregister('uri_escape');
    $self->{pbot}->{functions}->unregister('ana');
    $self->{pbot}->{functions}->unregister('maybe-the');
    $self->{pbot}->{functions}->unregister('maybe-to');
    $self->{pbot}->{functions}->unregister('maybe-on');
    $self->{pbot}->{functions}->unregister('length');
    $self->{pbot}->{functions}->unregister('jsonval');
}

sub func_unquote($self, @rest) {
    my $text = "@rest";
    $text =~ s/^"(.*?)(?<!\\)"$/$1/ || $text =~ s/^'(.*?)(?<!\\)'$/$1/;
    $text =~ s/(?<!\\)\\'/'/g;
    $text =~ s/(?<!\\)\\"/"/g;
    return $text;
}

sub func_unescape($self, @rest) {
    my $text = "@rest";
    $text =~ s/(?<!\\)\\//g;
    return $text;
}

sub func_title($self, @rest) {
    my $text = "@rest";
    $text = ucfirst lc $text;
    $text =~ s/ (\w)/' ' . uc $1/ge;
    return $text;
}

sub func_ucfirst($self, @rest) {
    return ucfirst "@rest";
}

sub func_maybe_ucfirst($self, @rest) {
    my $text = "@rest";

    my ($word) = $text =~ m/^\s*([^',.;: ]+)/;

    # don't ucfirst on nicks
    if ($self->{pbot}->{nicklist}->is_present_any_channel($word)) {
        return $text;
    }

    return ucfirst $text;
}

sub func_uc($self, @rest) {
    my $text = "@rest";
    return uc $text;
}

sub func_lc($self, @rest) {
    my $text = "@rest";
    return lc $text;
}

sub func_shquote($self, @rest) {
    my $text = "@rest";
    $text =~ s/'/'"'"'/g;
    return "'$text'";
}

sub func_quotemeta($self, @rest) {
    my $text = "@rest";
    return quotemeta $text;
}

sub func_uri_escape($self, @rest) {
    my $text = "@rest";
    return uri_escape_utf8($text);
}

sub func_ana($self, @rest) {
    my $text = "@rest";

    if ($text =~ s/\b(an?)(\s+)//i) {
        my ($article, $spaces) = ($1, $2);
        my $fixed_article = select_indefinite_article $text;

        if ($article eq 'AN') {
            $fixed_article = uc $fixed_article;
        } elsif ($article eq 'An' or $article eq 'A') {
            $fixed_article = ucfirst $fixed_article;
        }

        $text = $fixed_article . $spaces . $text;
    }

    return $text;
}

sub func_maybe_the($self, @rest) {
    my $text = "@rest";

    my ($word) = $text =~ m/^\s*([^',.;: ]+)/;

    # don't prepend if a proper-noun nick follows
    if ($self->{pbot}->{nicklist}->is_present_any_channel($word)) {
        return $text;
    }

    # special-case some indefinite nouns that Lingua::EN::Tagger treats as plain nouns
    if ($word =~ m/(some|any|every|no)(thing|one|body|how|way|where|when|time|place)/i) {
        return $text;
    }

    my $tagged = $self->{tagger}->add_tags($word);

    if ($tagged !~ m/^\s*<(?:det|prps?|cd|in|nnp|to|rb|wdt|rbr|jjr)>/) {
        $text = "the $text";
    }

    return $text;
}

sub func_maybe_to($self, @rest) {
    my $text = "@rest";
    $text =~ s/^to (?:the )?//;

    my ($word) = $text =~ m/^\s*([^',.;: ]+)/;

    if ($self->{pbot}->{nicklist}->is_present_any_channel($word)) {
        return "to $text";
    }

    # special-case some indefinite nouns that Lingua::EN::Tagger treats as plain nouns
    if ($word =~ m/(some|any|every|no)(thing|one|body|how|way|where|when|time|place)/i) {
        return "to $text";
    }

    my $tagged = $self->{tagger}->add_tags($word);

    if ($tagged !~ m/^\s*<(?:det|prps?|cd|in|nnp|to|rb|wdt|rbr|jjr)>/) {
        $text = "to the $text";
    } else {
        unless ($tagged =~ m/^\s*<(?:in)>/) {
            $text = "to $text";
        }
    }

    return $text;
}

sub func_maybe_on($self, @rest) {
    my $text = "@rest";
    $text =~ s/^on (?:the )?//;

    my ($word) = $text =~ m/^\s*([^',.;: ]+)/;

    if ($self->{pbot}->{nicklist}->is_present_any_channel($word)) {
        return "on $text";
    }

    # special-case some indefinite nouns that Lingua::EN::Tagger treats as plain nouns
    if ($word =~ m/(?:some|any|every|no)(?:thing|one|body|how|way|where|when|time|place)/i) {
        return "on $text";
    }

    my $tagged = $self->{tagger}->add_tags($word);

    if ($tagged !~ m/^\s*<(?:det|prps?|cd|in|nnp|to|rb|wdt|rbr|jjr)>/) {
        $text = "on the $text";
    } else {
        unless ($tagged =~ m/^\s*<(?:in)>/) {
            $text = "on $text";
        }
    }

    return $text;
}

sub func_length($self, @rest) {
    my $text = "@rest";
    my $count = 0;
    while ($text =~ /\X/g) { $count++ }; # count graphemes
    return $count;
}

sub func_jsonval($self, @rest) {
    my $member = shift @rest;
    my $text = "@rest";

    if (!defined $member || !length $member) {
        return 'Usage: jsonval <member> <json>; e.g. jsonval .a.b[1] {"a": {"b": [10, 20, 30]}}';
    }

    my $h = eval {
        my $decoder = JSON::XS->new;
        return $decoder->decode($text);
    };

    if (my $exception = $@) {
        $exception =~ s/(.*) at .*/$1/;
        return $exception;
    }

    my ($memb) = $member =~ m/^([^\[.]+)/;

    if (defined $memb && length $memb) {
        $h = eval {
            return $h->{$memb};
        };

        if (my $exception = $@) {
            $exception =~ s/(.*) at .*/$1/;
            return $exception;
        }
    }

    my $result = eval {
        while ($member =~ m/
            (?:
                  \['(?<key>(?:[^'\\]|\\.)*)'\]
                | \["(?<key>(?:[^"\\]|\\.)*)"\]
                | \[(?<index>[^\]]+)\]
                | \.'(?<key>(?:[^'\\]|\\.)*)'
                | \."(?<key>(?:[^"\\]|\\.)*)"
                | \.(?<key>[^\[\.]+)
                | (?<invalid>.)
            )
            /gx)
        {
            if (defined $+{invalid}) {
                return "Unexpected $+{invalid} at position $-[0]";
            }

            if (defined $+{index}) {
                my $index = $+{index};
                if ($index !~ /^\d+$/) {
                    return "Invalid index $index at position " . ($-[0] + 1);
                }
                $h = $h->[$index];
            }

            if (defined $+{key}) {
                my $key = $+{key};
                $key =~ s/(?<!\\)\\//g;
                $h = $h->{$key};
            }

            if (not defined $h) {
                return 'null';
            }
        }
    };

    if (my $exception = $@) {
        $exception =~ s/(.*) at .*/$1/;
        return $exception;
    }

    if (defined $result && length $result) {
        return $result;
    }

    if (not defined $h) {
        return 'null';
    }

    if (ref $h eq 'HASH' || ref $h eq 'ARRAY') {
        my $encoder = JSON::XS->new;
        return $encoder->space_after->encode($h);
    }

    return $h;
}

1;
