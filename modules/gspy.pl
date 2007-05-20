#!/usr/bin/perl -w

use strict;
use LWP::Simple;

my $html;

$html = get("http://www.metaspy.com/info.metac.spy/metaspy/unfiltered.htm");

defined $html or die "Oops, couldn't get the data.";


print "Recent search queries: ";

while($html =~ m/redir\.htm\?qkw\=(.*?)\"/g)
{
  print "$1, ";
}
