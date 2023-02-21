# File: Factoids.pm
#
# Purpose: Provides implementation of PBot factoids. Factoids provide the
# foundation for most user-submitted commands, as well as aliases, etc.

# SPDX-FileCopyrightText: 2001-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Factoids;
use parent 'PBot::Core::Class';

use PBot::Imports;

use PBot::Core::Factoids::Code;
use PBot::Core::Factoids::Data;
use PBot::Core::Factoids::Exporter;
use PBot::Core::Factoids::Interpreter;
use PBot::Core::Factoids::Modifiers;
use PBot::Core::Factoids::Selectors;
use PBot::Core::Factoids::Variables;

sub initialize {
    my ($self, %conf) = @_;

    $self->{data} = PBot::Core::Factoids::Data->new(%conf);
    $self->{data}->load;

    $self->{code}        = PBot::Core::Factoids::Code->new        (%conf);
    $self->{exporter}    = PBot::Core::Factoids::Exporter->new    (%conf);
    $self->{interpreter} = PBot::Core::Factoids::Interpreter->new (%conf);
    $self->{modifiers}   = PBot::Core::Factoids::Modifiers->new   (%conf);
    $self->{selectors}   = PBot::Core::Factoids::Selectors->new   (%conf);
    $self->{variables}   = PBot::Core::Factoids::Variables->new   (%conf);


    $self->{pbot}->{registry}->add_default('text', 'factoids', 'default_rate_limit', 15);
    $self->{pbot}->{registry}->add_default('text', 'factoids', 'max_name_length',    100);
    $self->{pbot}->{registry}->add_default('text', 'factoids', 'max_content_length', 1024 * 8);
    $self->{pbot}->{registry}->add_default('text', 'factoids', 'max_channel_length', 20);
}

1;
