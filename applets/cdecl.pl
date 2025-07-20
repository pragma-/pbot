#!/usr/bin/perl

# SPDX-FileCopyrightText: 2009-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

use Getopt::Long qw/GetOptionsFromString/;

my $usage = "Usage: cdecl <explain|declare|cast|set|...> <code>, see http://linux.die.net/man/1/cdecl (Don't use this command.  Use `english` instead.)\n";

my $command = join(' ', @ARGV);
$command = quotemeta($command);
$command =~ s/\\ / /g;
$command =~ s/^\s+|\s+$//g;
$command =~ s/\s+--\s+/ /g;

{
    my $opt_err;
    local $SIG{__WARN__} = sub {
        $opt_err = shift;
        chomp $opt_err;
    };

    Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case');

    my %h;
    my @allowed = qw/language=s x=s version v/;
    my ($ret, $rest) = GetOptionsFromString($command, \%h, @allowed);

    if ($opt_err) {
        print "$opt_err\n";
        exit 1;
    }

    if ($ret != 1) {
        print "Error parsing options.\n";
        exit 1;
    }

    if (not @$rest) {
        print $usage;
        exit 1;
    }

    my @commands = qw/cast declare expand define explain enum show/;
    push @commands, '#define';

    if (!grep { $rest->[0] eq $_ } @commands) {
        print $usage;
        exit 1;
    }
}

my $result = `cdecl $command`;

chomp $result;
$result =~ s/\n/, /g;
print "$result (Don't use this command. It can only handle C90 declarations -- poorly. Use `english` instead, which can translate any complete C11 code.)\n"
