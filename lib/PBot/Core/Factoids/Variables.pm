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

sub expand_factoid_vars($self, $context, $action, %opts) {
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

    my $needs_save = 0;

    while (++$depth < 100) {
        $rest =~ s/(?<!\\)\$0/$root_keyword/g;

        my $matches    = 0;
        my $expansions = 0;

        while ($rest =~ s/(.*?)(?<!\\)\$([\w|{])/$2/ms) {
            $result .= $1;

            my ($var, $orig_var);
            my $modifiers = '';
            my $extract_method;

            if ($rest =~ /^\{.*?\}/) {
                ($var, $rest) = $self->{pbot}->{interpreter}->extract_bracketed($rest, '{', '}');
                $orig_var = $var;

                if ($var =~ /:/) {
                    my @stuff = split /:/, $var, 2;
                    $var = $stuff[0];
                    $modifiers = ':' . $stuff[1];
                }

                $extract_method = 'bracket';
            } else {
                $rest =~ s/^(\w+)//;
                $var = $orig_var = $1;
                $extract_method = 'regex';
            }

            if ($var =~ /^(?:_.*|[[:punct:]0-9]+|a|b|nick|channel|randomnick|arglen|args|arg\[.+\])$/i) {
                # skip identifiers with leading underscores, etc
                $result .= $extract_method eq 'bracket' ? '${' . $orig_var . '}' : '$' . $orig_var;
                next;
            }

            $matches++;

            # extract channel expansion modifier
            if ($var =~ s/:(#[^: ]+|global)//i || $rest =~ s/^:(#[^: ]+|global)//i) {
                $from = $1;
                $from = '.*' if lc $from eq 'global';
            }

            my $recurse = 0;

          ALIAS:

            my @factoids = $self->{pbot}->{factoids}->{data}->find($from, $var, exact_channel => 2, exact_trigger => 2);

            my $var_chan;
            if (@factoids && $factoids[0]) {
                ($var_chan, $var) = ($factoids[0]->[0], $factoids[0]->[1]);

                my $ref_count = $self->{pbot}->{factoids}->{data}->{storage}->get_data($var_chan, $var, 'ref_count');

                my $data = {
                    ref_count => $ref_count + 1,
                    ref_user => $context->{hostmask},
                    last_referenced_in => $context->{from},
                    last_referenced_on => time
                };

                $self->{pbot}->{factoids}->{data}->{storage}->add($var_chan, $var, $data, 1);
                $needs_save = 1;

                if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($var_chan, $var, 'action') =~ m{^/call (.*)}ms) {
                    $var = $1;

                    if (++$recurse > 100) {
                        $self->{pbot}->{logger}->log("Factoids: variable expansion recursion limit reached\n");
                        $result .= $extract_method eq 'bracket' ? '${' . $orig_var . '}' : '$' . $orig_var;
                        next;
                    }

                    goto ALIAS;
                }
            }

            my $copy;
            my $bracketed = 0;

            if ($extract_method eq 'bracket') {
                $copy = $modifiers;
                $bracketed = 1;
            } else {
                $copy = $rest;
            }

            my %settings = $self->{pbot}->{factoids}->{modifiers}->parse(\$copy, $bracketed);

            my $change;

            if (not @factoids or not $factoids[0]) {
                if (exists $settings{default} && length $settings{default}) {
                    $change = $settings{default};
                } else {
                    $result .= $extract_method eq 'bracket' ? '${' . $orig_var . '}' : '$' . $orig_var;
                    next;
                }
            } else {
                if ($self->{pbot}->{factoids}->{data}->{storage}->get_data($var_chan, $var, 'type') eq 'text') {
                    $change = $self->{pbot}->{factoids}->{data}->{storage}->get_data($var_chan, $var, 'action');
                }
            }

            if (defined $change) {
                my @list = $self->{pbot}->{interpreter}->split_line($change);
                my @replacements;
                my $ref;

                if ($extract_method eq 'bracket') {
                    $ref = \$modifiers;
                } else {
                    $ref = \$rest;
                }

                if (wantarray) {
                    @replacements = $self->{pbot}->{factoids}->{selectors}->select_item($context, join ('|', @list), $ref, %opts);
                    return @replacements;
                } else {
                    push @replacements, scalar $self->{pbot}->{factoids}->{selectors}->select_item($context, join ('|', @list), $ref, %opts);
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

                # prevent double-spaces when joining replacement to result
                if ($result =~ m/ $/ && (!length($replacement) || $replacement =~ m/^ /)) {
                    $result =~ s/ $//;
                }

                $result .= $replacement;

                $expansions++;
            } else {
                $result .= $extract_method eq 'bracket' ? '${' . $orig_var . '}' : '$' . $orig_var;
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

    if ($needs_save) {
        $self->{pbot}->{factoids}->{data}->{storage}->save;
    }

    return validate_string($result, $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));
}

sub expand_action_arguments($self, $context, $action, $input = '', $nick = '') {
    $action = validate_string($action, $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));
    $input  = validate_string($input,  $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));

    my @args = $self->{pbot}->{interpreter}->split_line($input);

    $action =~ s/\$arglen\b|\$\{arglen\}/scalar @args/eg;

    my $root_keyword = $context->{keyword_override} ? $context->{keyword_override} : $context->{root_keyword};

    if ($action =~ m/^\/call --keyword-override=([^ ]+)/i) {
        $root_keyword = $1;
    }

    my $depth        = 0;
    my $const_action = $action;

    my $result = '';
    my $rest   = $action;

    while (++$depth < 100) {
        $rest =~ s/(?<!\\)\$0/$root_keyword/g;

        my $matches = 0;
        my $expansions = 0;

        while ($rest =~ s/(.*?)(?<!\\)\$([\w|{])/$2/ms) {
            $result .= $1;

            my ($var, $orig_var);
            my $modifiers = '';
            my $extract_method;

            if ($rest =~ /^\{.*?\}/) {
                ($var, $rest) = $self->{pbot}->{interpreter}->extract_bracketed($rest, '{', '}');
                $orig_var = $var;

                if ($var =~ /:/) {
                    my @stuff = split /:/, $var, 2;
                    $var = $stuff[0];
                    $modifiers = ':' . $stuff[1];
                }

                $extract_method = 'bracket';
            } else {
                $rest =~ s/^(\w+)//;
                $var = $orig_var = $1;
                $extract_method = 'regex';
            }

            if ($var ne 'args' && $var ne 'arg') {
                $result .= $extract_method eq 'bracket' ? '${' . $orig_var . '}' : '$' . $orig_var;
                next;
            }

            $matches++;

            my $value;
            my $use_nick = 0;

            if ($var eq 'args') {
                if (!defined $input || !length $input) {
                    $value = undef;
                    $use_nick = 1;
                } else {
                    $value = $input;
                }
            } else {
                my $index;
                if ($rest =~ s/\[(.*?)\]//) {
                    $index = $1;
                } else {
                    $result .= $extract_method eq 'bracket' ? '${' . $orig_var . '}' : '$' . $orig_var;
                    next;
                }

                if ($index eq '*') {
                    if (!defined $input || !length $input) {
                        $value = undef;
                        $use_nick = 1;
                    } else {
                        $value = $input;
                    }
                } elsif ($index =~ m/([^:]*):(.*)/) {
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
                        $value = undef;
                    } else {
                        $value = join(' ', @values);
                    }
                } else {
                    $value = eval {
                        local $SIG{__WARN__} = sub { };
                        return $args[$index];
                    };

                    if ($@) {
                        if ($index == 0) {
                            $value = $nick;
                        } else {
                            $value = undef;
                        }
                    }

                    if (!defined $value) {
                        if ($index == 0) {
                            $use_nick = 1;
                        }
                    }
                }
            }

            my %settings;
            if ($extract_method eq 'bracket') {
                %settings = $self->{pbot}->{factoids}->{modifiers}->parse(\$modifiers, 1);
            } else {
                %settings = $self->{pbot}->{factoids}->{modifiers}->parse(\$rest);
            }

            my $change;

            if (!defined $value || !length $value) {
                if (exists $settings{default} && length $settings{default}) {
                    $change = $settings{default};
                } else {
                    if ($use_nick) {
                        $change = $nick;
                    } else {
                        $change = '';
                    }
                }
            } else {
                $change = $value;
            }

            if (defined $change) {
                if (not length $change) {
                    $result =~ s/\s+$//;
                }

                if ($settings{'uc'}) {
                    $change = uc $change;
                }

                if ($settings{'lc'}) {
                    $change = lc $change;
                }

                if ($settings{'ucfirst'}) {
                    $change = ucfirst $change;
                }

                if ($settings{'title'}) {
                    $change = ucfirst lc $change;
                    $change =~ s/ (\w)/' ' . uc $1/ge;
                }

                if ($settings{'json'}) {
                    $change = $self->escape_json($change);
                }

                if ($result =~ s/\b(a|an)(\s+)$//i) {
                    my ($article, $trailing) = ($1, $2);
                    my $fixed_article = select_indefinite_article $change;

                    if ($article eq 'AN') {
                        $fixed_article = uc $fixed_article;
                    } elsif ($article eq 'An' or $article eq 'A') {
                        $fixed_article = ucfirst $fixed_article;
                    }

                    $change = $fixed_article . $trailing . $change;
                }

                $result .= $change;

                $expansions++;
            }
        }

        last if $matches == 0 or $expansions == 0;

        if (not length $rest) {
            $rest = $result;
            $result = '';
        }
    }

    $result .= $rest;

    # unescape certain symbols
    $result =~ s/(?<!\\)\\([\$\:\|])/$1/g;

    return validate_string($result, $self->{pbot}->{registry}->get_value('factoids', 'max_content_length'));
}

sub escape_json($self, $text) {
    my $thing = {thing => $text};
    my $json  = to_json $thing;
    $json =~ s/^{".*":"//;
    $json =~ s/"}$//;
    return $json;
}

sub expand_special_vars($self, $from, $nick, $root_keyword, $action) {
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
