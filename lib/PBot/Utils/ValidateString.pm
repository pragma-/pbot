# File: ValidateString.pm
#
# Purpose: ensures that a given string conforms to PBot's limitations
# for internal strings. This means ensuring the string is not too long,
# does not have undesired characters, etc.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Utils::ValidateString;

use PBot::Imports;

# export validate_string subroutine
require Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/validate_string/;

use JSON;
use Encode;
use Unicode::Truncate;

# validate_string converts a given string to one that conforms to
# PBot's limitations for internal strings. This means ensuring the
# string is not too long, does not have undesired characters, etc.
#
# If the given string contains a JSON structure, it will be parsed
# and each value will be validated. JSON structures must have a depth
# of one level only.
#
# Note that $max_length represents bytes, not characters. The string
# is encoded to utf8, validated, and then decoded back. Truncation
# uses Unicode::Truncate to find the longest Unicode string that can
# fit within $max_length bytes without corruption of the characters.
#
# if $max_length is undefined, it defaults to 8k.
#
# if $max_length is 0, no truncation occurs.

sub validate_string {
    my ($string, $max_length) = @_;

    if (not defined $string or not length $string) {
        # nothing to validate; return as-is.
        return $string;
    }

    # set default max length if none given
    $max_length //= 1024 * 8;

    local $@;
    eval {
        # attempt to decode as a JSON string
        # throws exception if fails
        my $data = decode_json($string);

        # no exception thrown, must be JSON.
        # so we validate all of its values.

        if (not defined $data) {
            # decode_json decodes "null" to undef. so we just
            # go ahead and return "null" as-is. otherwise, if we allow
            # encode_json to encode it back to a string, the string
            # will be "{}". bit weird.
            return 'null';
        }

        # validate values
        foreach my $key (keys %$data) {
            $data->{$key} = validate_this_string($data->{$key}, $max_length);
        }

        # encode back to a JSON string
        $string = encode_json($data);
    };

    if ($@) {
        # not a JSON string, so validate as a normal string.
        $string = validate_this_string($string, $max_length);
    }

    # all validated!
    return $string;
}

# validates the string.
# safely performs Unicode truncation given a byte length, handles
# unwanted characters, etc.
sub validate_this_string {
    my ($string, $max_length) = @_;

    # truncate safely
    if ($max_length > 0) {
        $string = encode('UTF-8', $string);
        $string = truncate_egc $string, $max_length;
    }

    # allow only these characters.
    # TODO: probably going to delete this code.
    # replace any extraneous characters with escaped-hexadecimal representation
    #  $string =~ s/(\P{PosixGraph})/
    #    my $ch = $1;
    #    if ($ch =~ m{[\s\x03\x02\x1d\x1f\x16\x0f]}) {
    #      $ch;
    #    } else {
    #      sprintf "\\x%02X", ord $ch;
    #    }/gxe;

    return $string;
}

1;
