#!/usr/bin/perl -w -I /home/msmud/lib/lib/perl5/site_perl/5.10.0/

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use strict;
use LWP::Simple;
 
$_ = get("http://www.randominsults.net/");
if (/<strong><i>(.*?)<\/i><\/strong>/) {
        print @ARGV,': ' if @ARGV;
        print $1;
}
else {
        print "yo momma!";
}
