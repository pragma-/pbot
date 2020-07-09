# File: Plang.pm
# Author: pragma-
#
# Purpose: Simplified scripting language for creating advanced PBot factoids
# and interacting with various internal PBot APIs.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Plugins::Plang;
use parent 'Plugins::Plugin';

use warnings; use strict;
use feature 'unicode_strings';

use Getopt::Long qw(GetOptionsFromArray);

sub initialize {
    my ($self, %conf) = @_;

    my $path = $self->{pbot}->{registry}->get_value('general', 'plang_dir') // 'Plang';
    unshift @INC, $path if not grep { $_ eq $path } @INC;
    require "$path/Interpreter.pm";

    my $debug = $self->{pbot}->{registry}->get_value('plang', 'debug') // 0;
    $self->{plang} = Plang::Interpreter->new(embedded => 1, debug => $debug);

    $self->{pbot}->{commands}->register(sub { $self->cmd_plang(@_) }, "plang", 0);
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister("plang");
}

sub cmd_plang {
    my ($self, $context) = @_;

    my $usage = "plang <Plang code>; see https://github.com/pragma-/Plang";

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    my ($show_usage);
    my @opt_args = $self->{pbot}->{interpreter}->split_line($context->{arguments}, strip_quotes => 1);

    Getopt::Long::Configure("bundling");
    GetOptionsFromArray(
        \@opt_args,
        'h'   => \$show_usage
    );

    return $usage                         if $show_usage;
    return "/say $getopt_error -- $usage" if defined $getopt_error;
    $context->{arguments} = "@opt_args";

    my $result = $self->{plang}->interpret_string($context->{arguments});
    return "No output." if not defined $result;
    return "/say $result";
}

1;
