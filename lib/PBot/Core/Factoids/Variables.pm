# File: Variables.pm
#
# Purpose: Implements factoid variables, including $args, $nick, $channel, etc.

# SPDX-FileCopyrightText: 2005-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Factoids::Variables;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Core::Utils::Indefinite;
use PBot::Core::Utils::ValidateString;

use JSON;

sub initialize {}

sub expand_factoid_vars {
    my ($self, $context, $action, %opts) = @_;

    my %default_opts = (
        nested => 0,
        recursions => 0,
    );

    %opts = (%default_opts, %opts);

    if (++$opts{recursions} > 100) {
        return '!recursion limit reached!';
    }

    my $from         = length $context->{ref_from} ? $context->{ref_from} : $context->{from};
    my $nick         = $context->{nick};
    my $root_keyword = $context->{keyword_override} ? $context->{keyword_override} : $context->{root_keyword};

    $action = defined $action ? $action : $context->{action};

    my $interpolate = $self->{pbot}->{factoids}->{data}->{storage}->get_data($context->{channel}, $context->{keyword}, 'interpolate');
    return $action if defined $interpolate and not $interpolate;

    $interpolate = $self->{pbot}->{registry}->get_value($context->{channel}, 'interpolate_factoids');
    return $action if defined $interpolate and not $interpolate;

    $action = $self->{pbot}->{factoids}->{selectors}->expand_selectors($context, $action, %opts);

    my $depth = 0;

    if ($action =~ m/^\/call --keyword-override=([^ ]+)/i) {
        $root_keyword = $1;
    }

    my $result = '';
    my $rest   = $action;

    while (++$depth < 100) {
        $rest =~ s/(?<!\\)\$0/$root_keyword/g;

        my $matches    = 0;
        my $expansions = 0;

        while ($rest =~ s/(.*?)(?<!\\)\$([\w|{])/$2/ms) {
            $result .= $1;

            my $var;
            my $extract_method;

            if ($rest =~ /^\{.*?\}/) {
                ($var, $rest) = $self->{pbot}->{interpreter}->extract_bracketed($rest, '{', '}');

                if ($var =~ /:/) {
                    my @stuff = split /:/, $var, 2;
                    $var = $stuff[0];
                    $rest = ':' . $stuff[1] . $rest;
                }

                $extract_method = 'bracket';
            } else {
                $rest =~ s/^(\w+)//;
                $var = $1;
                $extract_method = 'regex';
            }

            if ($var =~ /^(?:_.*|[[:punct:]0-9]+|a|b|nick|channel|randomnick|arglen|args|arg\[.+\])$/i) {
                # skip identifiers with leading underscores, etc
                $result .= $extract_method eq 'bracket' ? '${' . $var . '}' : '$' . $var;
                next;
            }

            $matches++;

            # extract channel expansion modifier
            if ($rest =~ s/^:(#[^:]+|global)//i) {
                $from = $1;
                $from = '.*' if lc $from eq 'global';
            }

            my $recurse = 0;

          ALIAS:

            my @factoids = $self->{pbot}->{factoids}->{data}->find($from, $var, exact_channel => 2, exact_trigger => 2);

            if (not @factoids or not $factoids[0]) {
                $result .= $extract_method eq 'bracket' ? '${' . $var . '}' : '$' . $var;
                next;
            }

            my $var_chan;
            ($var_chan, $var) = ($factoids[0]->[0], $factoids[0]->[1]);

            if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($var_chan, $var, 'action') =~ m{^/call (.*)}ms) {
                $var = $1;

                if (++$recurse > 100) {
                    $self->{pbot}->{logger}->log("Factoids: variable expansion recursion limit reached\n");
                    $result .= $extract_method eq 'bracket' ? '${' . $var . '}' : '$' . $var;
                    next;
                }

                goto ALIAS;
            }

            my $copy = $rest;
            my %settings = $self->{pbot}->{factoids}->{modifiers}->parse(\$copy);

            if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($var_chan, $var, 'type') eq 'text') {
                my $change = $self->{pbot}->{factoids}->{data}->{storage}->get_data($var_chan, $var, 'action');
                my @list   = $self->{pbot}->{interpreter}->split_line($change);

                my @replacements;

                if (wantarray) {
                    @replacements = $self->{pbot}->{factoids}->{selectors}->select_item($context, join ('|', @list),  \$rest, %opts);
                    return @replacements;
                } else {
                    push @replacements, scalar $self->{pbot}->{factoids}->{selectors}->select_item($context, join ('|', @list), \$rest, %opts);
                }

                my $replacement = $opts{nested} ? join('|', @replacements) : "@replacements";

                if (not length $replacement) {
                    $result =~ s/\s+$//;
                } else {
                    $replacement = $self->{pbot}->{factoids}->{variables}->expand_factoid_vars($context, $replacement, %opts);
                }

                if ($settings{'uc'}) {
                    $replacement = uc $replacement;
                }

                if ($settings{'lc'}) {
                    $replacement = lc $replacement;
                }

                if ($settings{'ucfirst'}) {
                    $replacement = ucfirst $replacement;
                }

                if ($settings{'title'}) {
                    $replacement = ucfirst lc $replacement;
                    $replacement =~ s/ (\w)/' ' . uc $1/ge;
                }

                if ($settings{'json'}) {
                    $replacement = $self->escape_json($replacement);
                }

                if ($result =~ s/\b(a|an)(\s+)$//i) {
                    my ($article, $trailing) = ($1, $2);
                    my $fixed_article = select_indefinite_article $replacement;

                    if ($article eq 'AN') {
                        $fixed_article = uc $fixed_article;
                    } elsif ($article eq 'An' or $article eq 'A') {
                        $fixed_article = ucfirst $fixed_article;
                    }

                    $replacement = $fixed_article . $trailing . $replacement;
                }

                $result .= $replacement;

                $expansions++;
            } else {
                $result .= $extract_method eq 'bracket' ? '${' . $var . '}' : '$' . $var;
            }
        }

        last if $matches == 0 or $expansions == 0;

        if (not length $rest) {
            $rest = $result;
            $result = '';
        }
    }

    $result .= $rest;

    $result = $self->expand_special_vars($from, $nick, $root_keyword, $result);

    # unescape certain symbols
    $result =~ s/(?<!\\)\\([\$\:\|])/$1/g;

    return validate_string($result, $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));
}

sub expand_action_arguments {
    my ($self, $action, $input, $nick) = @_;

    $action = validate_string($action, $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));
    $input  = validate_string($input,  $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));

    my %h;

    if (not defined $input or $input eq '') {
        %h = (args => $nick);
    } else {
        %h = (args => $input);
    }

    my $jsonargs = to_json \%h;
    $jsonargs =~ s/^{".*":"//;
    $jsonargs =~ s/"}$//;

    if (not defined $input or $input eq '') {
        $input = "";
        $action =~ s/\$args:json|\$\{args:json\}/$jsonargs/ge;
        $action =~ s/\$args(?![[\w])|\$\{args(?![[\w])\}/$nick/g;
    } else {
        $action =~ s/\$args:json|\$\{args:json\}/$jsonargs/g;
        $action =~ s/\$args(?![[\w])|\$\{args(?![[\w])\}/$input/g;
    }

    my @args = $self->{pbot}->{interpreter}->split_line($input);

    $action =~ s/\$arglen\b|\$\{arglen\}/scalar @args/eg;

    my $depth        = 0;
    my $const_action = $action;

    while ($const_action =~ m/\$arg\[([^]]+)]|\$\{arg\[([^]]+)]\}/g) {
        my $arg = defined $2 ? $2 : $1;

        last if ++$depth >= 100;

        if ($arg eq '*') {
            if (not defined $input or $input eq '') {
                $action =~ s/\$arg\[\*\]|\$\{arg\[\*\]\}/$nick/;
            } else {
                $action =~ s/\$arg\[\*\]|\$\{arg\[\*\]\}/$input/;
            }

            next;
        }

        if ($arg =~ m/([^:]*):(.*)/) {
            my $arg1 = $1;
            my $arg2 = $2;

            my $arg1i = $arg1;
            my $arg2i = $arg2;

            $arg1i = 0      if $arg1i eq '';
            $arg2i = $#args if $arg2i eq '';
            $arg2i = $#args if $arg2i > $#args;

            my @values = eval {
                local $SIG{__WARN__} = sub { };
                return @args[$arg1i .. $arg2i];
            };

            if ($@) {
                next;
            } else {
                my $string = join(' ', @values);

                if ($string eq '') {
                    $action =~ s/\s*\$\{arg\[$arg1:$arg2\]\}//     || $action =~ s/\s*\$arg\[$arg1:$arg2\]//;
                } else {
                    $action =~ s/\$\{arg\[$arg1:$arg2\]\}/$string/ || $action =~ s/\$arg\[$arg1:$arg2\]/$string/;
                }
            }

            next;
        }

        my $value = eval {
            local $SIG{__WARN__} = sub { };
            return $args[$arg];
        };

        if ($@) {
            next;
        } else {
            if (not defined $value) {
                if ($arg == 0) {
                    $action =~ s/\$\{arg\[$arg\]\}/$nick/ || $action =~ s/\$arg\[$arg\]/$nick/;
                } else {
                    $action =~ s/\s*\$\{arg\[$arg\]\}//   || $action =~ s/\s*\$arg\[$arg\]//;
                }
            } else {
                $action =~ s/\$arg\{\[$arg\]\}/$value/    || $action =~ s/\$arg\[$arg\]/$value/;
            }
        }
    }

    return $action;
}

sub escape_json {
    my ($self, $text) = @_;
    my $thing = {thing => $text};
    my $json  = to_json $thing;
    $json =~ s/^{".*":"//;
    $json =~ s/"}$//;
    return $json;
}

sub expand_special_vars {
    my ($self, $from, $nick, $root_keyword, $action) = @_;

    $action =~ s/(?<!\\)\$nick:json|(?<!\\)\$\{nick:json\}/$self->escape_json($nick)/ge;
    $action =~ s/(?<!\\)\$channel:json|(?<!\\)\$\{channel:json\}/$self->escape_json($from)/ge;
    $action =~
      s/(?<!\\)\$randomnick:json|(?<!\\)\$\{randomnick:json\}/my $random = $self->{pbot}->{nicklist}->random_nick($from); $random ? $self->escape_json($random) : $self->escape_json($nick)/ge;
    $action =~ s/(?<!\\)\$0:json|(?<!\\)\$\{0:json\}/$self->escape_json($root_keyword)/ge;

    $action =~ s/(?<!\\)\$nick|(?<!\\)\$\{nick\}/$nick/g;
    $action =~ s/(?<!\\)\$channel|(?<!\\)\$\{channel\}/$from/g;
    $action =~ s/(?<!\\)\$randomnick|(?<!\\)\$\{randomnick\}/my $random = $self->{pbot}->{nicklist}->random_nick($from); $random ? $random : $nick/ge;
    $action =~ s/(?<!\\)\$0\b|(?<!\\)\$\{0\}\b/$root_keyword/g;

    return validate_string($action, $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));
}

1;
