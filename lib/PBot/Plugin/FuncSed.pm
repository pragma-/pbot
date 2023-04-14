# File: FuncSed.pm
#
# Purpose: Registers the sed Function

# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::FuncSed;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize($self, %conf) {
    $self->{pbot}->{functions}->register(
        'sed',
        {
            desc   => 'a sed-like stream editor',
            usage  => 'sed s/<regex>/<replacement>/[Pig]; P preserve case; i ignore case; g replace all',
            subref => sub { $self->func_sed(@_) }
        }
    );
}

sub unload($self) {
    $self->{pbot}->{functions}->unregister('sed');
}

# near-verbatim insertion of krok's `sed` factoid
no warnings;
sub func_sed($self, @rest) {
    my $text = "@rest";

    my $result = eval {
        if ($text =~ /^s(.)(.*?)(?<!\\)\1(.*?)(?<!\\)\1(\S*)\s+(.*)/p) {
            my ($a, $r, $g, $m, $t) = ($5, "'\"$3\"'", index($4, "g") != -1, $4, $2);

            #print "a: $a, r: $r, g: $g, m: $m, t: $t\n";
            #print "text: [$text]\n";

            if ($m =~ /P/) {
                $r =~ s/^'"(.*)"'$/$1/;
                $m =~ s/P//g;

                if   ($g) { $a =~ s|(?$m)($t)|$1=~/^[A-Z][^A-Z]/?ucfirst$r:($1=~/^[A-Z]+$/?uc$r:$r)|gie; }
                else      { $a =~ s|(?$m)($t)|$1=~/^[A-Z][^A-Z]/?ucfirst$r:($1=~/^[A-Z]+$/?uc$r:$r)|ie; }
            } else {
                if   ($g) { $a =~ s/(?$m)$t/$r/geee; }
                else      { $a =~ s/(?$m)$t/$r/eee; }
            }
            return $a;
        } else {
            return 'sed: syntax error; usage: sed s/<regex>/<replacement>/[Pig]; P preserve case; i ignore case; g replace all';
        }
    };

    if (my $e = $@) {
        $e =~ s/ at .*$//;
        return "sed: syntax error: $e";
    }

    return $result;
}
use warnings;

1;
