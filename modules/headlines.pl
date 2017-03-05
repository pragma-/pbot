#!/usr/bin/perl -w -I /home/msmud/lib/lib/perl5/site_perl/5.10.0/

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use XML::RSS;
use LWP::Simple;

# Note:  Some of these may no longer exist.
# http://radio.xmlstoragesystem.com/rcsPublic/rssHotlist and many other
# similiar URLS (try Google?) may be useful.

my %news_sites = (
  "jbad"       => [ "http://jalalabad.us/backend/geeklog.rdf",
                    "Jalalabad.us"    
                  ],
  "bbc"        => [ "http://news.bbc.co.uk/rss/newsonline_uk_edition/world/rss091.xml",
		    "news.bbc.co.uk"  
                  ],
  "cnn"        => [ "http://www.cnn.com/cnn.rss",
                    "CNN News"
                  ],
  "chealth"    => [ "http://www.cnn.com/health/health.rdf",
                    "CNN Health"
                  ],
  "ctech"      => [ "http://www.cnn.com/technology/tech.rdf",
                    "CNN Technology"
                  ],
  "csports"    => [ "http://www.cnn.com/sports/sports.rdf",
                    "CNN Sports"
                  ],
  "/."         => [ "http://slashdot.org/slashdot.rdf",
                    "Slashdot"
                  ],
  "nyttech"    => [ "http://xml.newsisfree.com/feeds/62/162.xml",
                    "New York Times Technology"
                  ],
  "morons"     => [ "http://www.morons.org/morons.rss",
                    "morons.org"
                  ]
);

my $args = join(' ', @ARGV);
my $links = 0;
my $key;
my $value;


if($args =~ /^links\s+(.*)/i) {
  $args = $1;
  $links = 1;
}

$args = quotemeta($args);

foreach $key (keys %news_sites) {
  $value = $news_sites{$key}->[0];

  if($key =~ /$args/i) {
    check_news($value, $links, $news_sites{$key}->[1]);
    exit(0);
  }
}

print "Invalid Headline.  Usage:  .headlines [links] <news server> - News servers are: ";

foreach $key (keys %news_sites) {
  print "$key => $news_sites{$key}->[1], ";
}

print "\n";



sub check_news {
  my ($site, $links, $headline) = @_;
  my $text = "$headline: ";

  my $rss = new XML::RSS;

  my $content = get($site);

  if($content) {
    eval {
      $rss->parse($content);
    };
    if(my $error = $@) {
       $error =~ s/\n//g;   
       print "Got error: $error\n";
       return 0;
     }   


    foreach my $item (@{$rss->{'items'}}) {
      next unless defined($item->{'title'}) && defined($item->{'link'});
  
      if($links == 1)
      {
        $text = " $item->{'title'} : ( $item->{'link'} )";
        $text =~ s/\n//g; 
        $text =~ s/\t//g;
        $text =~ s/\r//g;
        print "$text\n";
      }
      else
      {
        $text .= " $item->{'title'} -";
      }
    }
  }
  $text =~ s/\n//g;
  $text =~ s/\t//g;
  $text =~ s/\r//g;
  print "$text\n" if ($links == 0);
}

