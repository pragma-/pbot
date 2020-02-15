package PBot::Utils::ValidateString;

use warnings;
use strict;

use feature 'unicode_strings';

require Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/validate_string/;

use JSON;

sub validate_string {
    my ($string, $max_length) = @_;

    return $string if not defined $string or not length $string;
    $max_length = 1024 * 8 if not defined $max_length;

    eval {
        my $h = decode_json($string);
        foreach my $k (keys %$h) { $h->{$k} = substr $h->{$k}, 0, $max_length unless $max_length <= 0; }
        $string = encode_json($h);
    };

    if ($@) {
        # not a json string
        $string = substr $string, 0, $max_length unless $max_length <= 0;
    }

    #  $string =~ s/(\P{PosixGraph})/my $ch = $1; if ($ch =~ m{[\s\x03\x02\x1d\x1f\x16\x0f]}) { $ch } else { sprintf "\\x%02X", ord $ch }/ge;
    #  $string = substr $string, 0, $max_length unless $max_length <= 0;

    return $string;
}

1;
