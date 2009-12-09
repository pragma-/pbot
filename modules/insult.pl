#!/usr/bin/perl -w -I /home/msmud/lib/lib/perl5/site_perl/5.10.0/
#
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
