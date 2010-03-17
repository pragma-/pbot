# File: NewModule.pm
# Authoer: pragma_
#
# Purpose: New module skeleton

package PBot::IgnoreList;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw($logger %ignore_list);
}

use vars @EXPORT_OK;

*logger = \$PBot::PBot::logger;

use Time::HiRes qw(gettimeofday);

%ignore_list = ();

sub ignore_user {
  my ($from, $nick, $user, $host, $arguments) = @_;

  return "/msg $nick Usage: ignore nick!user\@host [channel] [timeout]" if not defined $arguments;

  my ($target, $channel, $length) = split /\s+/, $arguments;


  if(not defined $target) {
     return "/msg $nick Usage: ignore host [channel] [timeout]";
  }

  if($target =~ /^list$/i) {
    my $text = "Ignored: ";
    my $sep = "";

    foreach my $ignored (keys %ignore_list) {
      foreach my $channel (keys %{ $ignore_list{$ignored} }) {
        $text .= $sep . "[$ignored][$channel]" . int(gettimeofday - $ignore_list{$ignored}{$channel});
        $sep = "; ";
      }
    }
    return "/msg $nick $text";
  }

  if(not defined $channel) {
    $channel = ".*"; # all channels
  }
  
  if(not defined $length) {
    $length = 300; # 5 minutes
  }

  $logger->log("$nick added [$target][$channel] to ignore list for $length seconds\n");
  $ignore_list{$target}{$channel} = gettimeofday + $length;
  return "/msg $nick [$target][$channel] added to ignore list for $length seconds";
}

sub unignore_user {
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($target, $channel) = split /\s+/, $arguments;

  if(not defined $target) {
    return "/msg $nick Usage: unignore host [channel]";
  }

  if(not defined $channel) {
    $channel = ".*";
  }
  
  if(not exists $ignore_list{$target}{$channel}) {
    $logger->log("$nick attempt to remove nonexistent [$target][$channel] from ignore list\n");
    return "/msg $nick [$target][$channel] not found in ignore list (use '!ignore list' to list ignores";
  }
  
  delete $ignore_list{$target}{$channel};
  $logger->log("$nick removed [$target][$channel] from ignore list\n");
  return "/msg $nick [$target][$channel] unignored";
}

sub check_ignore {
  my ($nick, $user, $host, $channel) = @_;
  $channel = lc $channel;

  my $hostmask = "$nick!$user\@$host"; 

  foreach my $ignored (keys %ignore_list) {
    foreach my $ignored_channel (keys %{ $ignore_list{$ignored} }) {
      $logger->log("check_ignore: comparing '$hostmask' against '$ignored' for channel '$channel'\n");
      if(($channel =~ /$ignored_channel/i) && ($hostmask =~ /$ignored/i)) {
        $logger->log("$nick!$user\@$host message ignored in channel $channel (matches [$ignored] host and [$ignored_channel] channel)\n");
        return 1;
      }
    }
  }
}

1;
