# File: NewModule.pm
# Authoer: pragma_
#
# Purpose: New module skeleton

package PBot::ChannelStuff;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw($channels_file $logger %channels);
}

use vars @EXPORT_OK;

*channels_file = \$PBot::PBot::channels_file;
*logger = \$PBot::PBot::logger;

%channels = ();

sub load_channels {
  open(FILE, "< $channels_file") or die "Couldn't open $channels_file: $!\n";
  my @contents = <FILE>;
  close(FILE);

  $logger->log("Loading channels from $channels_file ...\n");

  my $i = 0;
  foreach my $line (@contents) {
    $i++;
    chomp $line;
    my ($channel, $enabled, $is_op, $showall) = split(/\s+/, $line);
    if(not defined $channel || not defined $is_op || not defined $enabled) {
      die "Syntax error around line $i of $channels_file\n";
    }

    $channel = lc $channel;

    if(defined $channels{$channel}) {
      die "Duplicate channel $channel found in $channels_file around line $i\n";
    }
    
    $channels{$channel}{enabled} = $enabled;
    $channels{$channel}{is_op} = $is_op;
    $channels{$channel}{showall} = $showall;
    
    $logger->log("  Adding channel $channel (enabled: $enabled, op: $is_op, showall: $showall) ...\n");
  }
  
  $logger->log("Done.\n");
}

sub save_channels {
  open(FILE, "> $channels_file") or die "Couldn't open $channels_file: $!\n";
  foreach my $channel (keys %channels) {
    $channel = lc $channel;
    print FILE "$channel $channels{$channel}{enabled} $channels{$channel}{is_op} $channels{$channel}{showall}\n";
  }
  close(FILE);
}

1;
