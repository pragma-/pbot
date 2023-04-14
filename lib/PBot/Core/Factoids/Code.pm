# File: Code.pm
#
# Purpose: Launching pad for code factoids. Configures $context as a code
# factoid and executes the vm-client applet.

# SPDX-FileCopyrightText: 2007-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Factoids::Code;
use parent 'PBot::Core::Class';

use PBot::Imports;

use JSON;

sub initialize {}

sub execute($self, $context) {
    my $factoids = $self->{pbot}->{factoids}->{data}->{storage};

    my $interpolate = $factoids->get_data($context->{channel}, $context->{keyword}, 'interpolate');

    unless (defined $interpolate and not $interpolate) {
        if ($context->{code} =~ m/(?:\$\{?nick\b|\$\{?args\b|\$\{?arg\[)/ and length $context->{arguments}) {
            # disable nick overriding
            $context->{nickprefix_disabled} = 1;
        } else {
            # allow nick overriding
            $context->{nickprefix_disabled} = 0;
        }

        my $variables = $self->{pbot}->{factoids}->{variables};

        # expand factoid variables/selectors/etc in code
        $context->{code} = $variables->expand_factoid_vars($context, $context->{code});

        # expand factoid variables/selectors/etc in arguments
        $context->{arguments} = $variables->expand_factoid_vars($context, $context->{arguments});

        # expand factoid action $args
        if ($factoids->get_data($context->{channel}, $context->{keyword}, 'allow_empty_args')) {
            $context->{code} = $variables->expand_action_arguments($context->{code}, $context->{arguments}, '');
        } else {
            $context->{code} = $variables->expand_action_arguments($context->{code}, $context->{arguments}, $context->{nick});
        }
    } else {
        # otherwise allow nick overriding
        $context->{nickprefix_disabled} = 0;
    }

    # set up `vm-client` applet arguments
    my %args = (
        nick      => $context->{nick},
        channel   => $context->{from},
        lang      => $context->{lang},
        code      => $context->{code},
        arguments => $context->{arguments},
        factoid   => "$context->{channel}:$context->{keyword}",
    );

    # the vm can persist filesystem data to external storage identified by a key.
    # if the `persist-key` factoid metadata is set, then use this key.
    my $persist_key = $factoids->get_data($context->{channel}, $context->{keyword}, 'persist-key');

    if (defined $persist_key) {
        $args{'persist-key'} = $persist_key;
    }

    # encode args to utf8 json string
    my $json = encode_json \%args;

    # update context details
    $context->{special}      = 'code-factoid';      # ensure handle_result(), etc, process this as a code-factoid
    $context->{root_channel} = $context->{channel}; # override root channel to current channel
    $context->{keyword}      = 'vm-client';         # code-factoid uses `vm-client` command to invoke vm
    $context->{arguments}    = $json;               # set arguments to json string as `vm-client` expects
    $context->{args_utf8}    = 1;                   # arguments are utf8 encoded by encode_json

    # launch the `vm-client` applet
    $self->{pbot}->{applets}->execute_applet($context);

    # return empty string since the applet process reader will
    # pass the output along to the result handler
    return '';
}

1;
