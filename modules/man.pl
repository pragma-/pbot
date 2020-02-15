#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# quick and dirty by :pragma

use LWP::Simple;

my ($result, $manpage, $section, $text, $name, $includes, $prototype, $conforms, $description);

if ($#ARGV < 0) {
    print "Which command would you like information about?\n";
    die;
}

$manpage = join("+", @ARGV);
$section = 8;
my $loop = 1;

if ($manpage =~ m/([0-9]+)\+(.*)/) {
    $section = $1;
    $manpage = $2;
    $loop    = 0;
}

$manpage =~ s/\+.*$//;

my $get_text;
do {
    #  $text = get("http://www.freebsd.org/cgi/man.cgi?query=$manpage&sektion=$section&apropos=0&manpath=FreeBSD+6.2-RELEASE&format=ascii");

    $get_text = get("http://www.freebsd.org/cgi/man.cgi?query=$manpage&sektion=$section&apropos=0&manpath=SuSE+Linux%2Fi386+11.3&format=ascii");

    $text = substr($get_text, 0, 5000);

    #  print '['.length($text).']'."\n";

    if ($text =~ m/Sorry, no data found/) {
        $section--;

        if ($section == 0 || $loop == 0) {
            $section++;
            if   ($section == 1 && $loop == 1) { print "No information found for $manpage in any of the sections.\n"; }
            else                               { print "No information found for $manpage in section $section.\n"; }
            exit 0;
        }
    } else {
        $loop = 0;
    }
} while ($loop);

$text =~ m/^\s+NAME/gsm;
if ($text =~ m/(.*?)SYNOPSIS/gsi) { $name = $1; }

my $i = 0;
while ($text =~ m/#include <(.*?)>/gsi) {
    if (not $includes =~ /$1/) {
        $includes .= ", " if ($i > 0);
        $includes .= "$1";
        $i++;
    }
}

$prototype = "$1 $2$manpage($3);" if ($text =~ m/SYNOPSIS.*^\s+(.*?)\s+(\*?)$manpage\s*\((.*?)\)\;?\n.*DESC/ms);

if ($text =~ m/DESCRIPTION(.*?)$manpage(.*?)\./si) {
    my $foo = $1;
    my $bar = $2;
    $foo =~ s/\r//g;
    $foo =~ s/\n//g;
    $foo =~ s/\s+/ /g;
    $foo =~ s/^\s+//;
    if   ($foo =~ /^NOTE/) { $description = "$foo$manpage$bar"; }
    else                   { $description = "$manpage$bar"; }
    $description =~ s/\-\s+//g;
}

if    ($get_text =~ m/^CONFORMING TO.*?^\s+The\s$manpage\s.*conforms to\s(.*?)$/ms)                       { $conforms = $1; }
elsif ($get_text =~ m/^CONFORMING TO.*?^\s+The\s+$manpage\s+.*?is\s+compatible\s+with\s+(.*?)$/ms)        { $conforms = "$1 ..."; }
elsif ($get_text =~ m/^CONFORMING TO.*?^\s+(.*?)\.\s/ms or $get_text =~ m/^CONFORMING TO.*?^\s+(.*?)$/ms) { $conforms = $1; }

$result = "";
$result .= "$name - "               if (not defined $includes and defined $name);
$result .= "Includes: $includes - " if (defined $includes);
$result .= "$prototype - "          if (defined $prototype);

$result .= $description;

if   ($section == 3) { $result .= " - http://www.iso-9899.info/man?$manpage"; }
else                 { $result .= " - http://www.freebsd.org/cgi/man.cgi?sektion=$section&query=$manpage"; }

$result .= " - $conforms" if (defined $conforms);

$result =~ s/^\s+//g;
$result =~ s/\s+/ /g;
$result =~ s/ANSI - C/ANSI C/g;
$result =~ s/\(these.*?appeared in .*?\)//g;
$result =~ s/(\w)- /$1/g;
$result =~ s/\n//g;
$result =~ s/\r//g;
$result =~ s/\<A HREF.*?>//g;
$result =~ s/\<\/A>//g;
$result =~ s/&quot;//g;

print "$result\n";

