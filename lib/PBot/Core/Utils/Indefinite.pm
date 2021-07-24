# File: Indefinite.pm
#
# Purpose: Implements a/an inflexion for nouns.

package PBot::Core::Utils::Indefinite;

use PBot::Imports;

require Exporter;
our @ISA    = qw/Exporter/;
our @EXPORT = qw/prepend_indefinite_article select_indefinite_article/;

# This module implements A/AN inflexion for nouns...

# Special cases of A/AN...
my $ORDINAL_AN  = qr{\A [aefhilmnorsx]   -?th \Z}ix;
my $ORDINAL_A   = qr{\A [bcdgjkpqtuvwyz] -?th \Z}ix;
my $EXPLICIT_AN = qr{\A (?: euler | hour(?!i) | heir | honest | hono )}ix;
my $SINGLE_AN   = qr{\A [aefhilmnorsx]   \Z}ix;
my $SINGLE_A    = qr{\A [bcdgjkpqtuvwyz] \Z}ix;

# This pattern matches strings of capitals (i.e. abbreviations) that
# start with a "vowel-sound" consonant followed by another consonant,
# and which are not likely to be real words
# (oh, all right then, it's just magic!)...

my $ABBREV_AN = qr{
    \A
    (?! FJO | [HLMNS]Y.  | RY[EO] | SQU
    |   ( F[LR]? | [HL] | MN? | N | RH? | S[CHKLMNPTVW]? | X(YL)?) [AEIOU]
    )
    [FHLMNRSX][A-Z]
}xms;

# This pattern codes the beginnings of all english words begining with a
# 'Y' followed by a consonant. Any other Y-consonant prefix therefore
# implies an abbreviation...

my $INITIAL_Y_AN = qr{\A y (?: b[lor] | cl[ea] | fere | gg | p[ios] | rou | tt)}xi;

sub prepend_indefinite_article {
    my ($word) = @_;
    return select_indefinite_article($word) . " $word";
}

sub select_indefinite_article {
    my ($word) = @_;

    # Handle ordinal forms...
    return "a"  if $word =~ $ORDINAL_A;
    return "an" if $word =~ $ORDINAL_AN;

    # Handle special cases...
    return "an" if $word =~ $EXPLICIT_AN;
    return "an" if $word =~ $SINGLE_AN;
    return "a"  if $word =~ $SINGLE_A;

    # Handle abbreviations...
    return "an" if $word =~ $ABBREV_AN;
    return "an" if $word =~ /\A [aefhilmnorsx][.-]/xi;
    return "a"  if $word =~ /\A [a-z][.-]/xi;

    # Handle consonants

    return "a" if $word =~ /\A [^aeiouy] /xi;

    # Handle special vowel-forms

    return "a"  if $word =~ /\A e [uw] /xi;
    return "a"  if $word =~ /\A onc?e \b /xi;
    return "a"  if $word =~ /\A uni (?: [^nmd] | mo) /xi;
    return "an" if $word =~ /\A ut[th] /xi;
    return "a"  if $word =~ /\A u [bcfhjkqrst] [aeiou] /xi;

    # Handle special capitals

    return "a" if $word =~ /\A U [NK] [AIEO]? /x;

    # Handle vowels

    return "an" if $word =~ /\A [aeiou]/xi;

    # Handle Y... (before certain consonants implies (unnaturalized) "I.." sound)
    return "an" if $word =~ $INITIAL_Y_AN;

    # Otherwise, guess "A"
    return "a";
}

1;    # Magic true value required at end of module
__END__

=head1 NAME

Lingua::EN::Inflexion::Indefinite - Implements classes of LEI objects


=head1 VERSION

This document describes Lingua::EN::Inflexion::Indefinite version 0.000001


=head1 DESCRIPTION

This module contains implementation code only.
See the documentation of Lingua::EN::Inflexion instead.


=head1 AUTHOR

Damian Conway  C<< <DCONWAY@cpan.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2014, Damian Conway C<< <DCONWAY@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

