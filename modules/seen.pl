#!/usr/bin/perl -w

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use strict;

if ($#ARGV != 0)
{
  print "Usage: !seen nick\n";
  exit 0;
}

my $nick = $ARGV[0];

my $file = "/home/msmud/irclogs/freenode/##c.log";

open(FILE, "< $file")
  or die "Can't open $file for reading: $!\n";

seek(FILE, 0, 2); # seek to end of file

my $pos = tell(FILE) - 2;
my $char;
my $result;

while (seek(FILE, $pos--, 0))
{
  read(FILE, $char, 1);
  if ($char eq "\n")
  {
    my $line = <FILE>;
    chomp $line;

    next if not defined $line;

    if ($line =~ m/^(\d\d:\d\d) -!- $nick (.*?)$/i)
    {
      $result = "date at $1: $nick $2\n";
    }
    elsif ($line =~ m/^(\d\d:\d\d) <\s*$nick> (.*?)$/i)
    {
      $result = "date at $1: <$nick> $2\n";
    }
    elsif ($line =~ m/^(\d\d:\d\d)  * $nick (.*?)$/i)
    {
      $result = "date at $1: $nick $2\n";
    }
    last if defined $result;
  }
}

if (defined $result)
{
  my $date;

  while (seek(FILE, $pos--, 0))
  {
    read(FILE, $char, 1);
    if ($char eq "\n")
    {
      my $line = <FILE>;
      chomp($line);

      if ($line =~ m/^--- Log opened (.*?) \d\d:\d\d:\d\d(.*?)$/)
      {
        $date = $1 . $2;
        last;
      }
      elsif ($line =~ m/^--- Day changed (.*?)$/)
      {
        $date = $1;
        last;
      }
    }
  }

  $result =~ s/^date/$date/;
  print $result;
}
else
{
  print "I haven't seen $nick.\n";
}

close(FILE);
