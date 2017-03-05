#!/usr/bin/perl -w -I /home/msmud/lib/lib/perl5/site_perl/5.10.0/

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use LWP::Simple;

my $html;

$html = get("http://www.google.com/press/zeitgeist.html");

defined $html or die "Oops, couldn't get the data.";


print "Top 10 Google search queries: ";

while($html =~ m/<td class="bodytext2" .*?<a class="style10".*?>(.*?)<\/a>/g)
{
  print "$1, ";
}
