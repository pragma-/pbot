# File: NewModule.pm
# Authoer: pragma_
#
# Purpose: New module skeleton

package PBot::AntiFlood;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw($logger $botnick %flood_watch $MAX_NICK_MESSAGES $FLOOD_CHAT $conn $last_timestamp $flood_msg
                  %channels);
}

use vars @EXPORT_OK;

use Time::HiRes qw(gettimeofday);

*logger = \$PBot::PBot::logger;
*botnick = \$PBot::PBot::botnick;
*conn = \$PBot::PBot::conn;
*MAX_NICK_MESSAGES = \$PBot::PBot::MAX_NICK_MESSAGES;
*channels = \%PBot::ChannelStuff::channels;

# do not modify
$FLOOD_CHAT = 0;
#$FLOOD_JOIN = 1;  # currently unused -- todo?

$last_timestamp = gettimeofday;
$flood_msg = 0;

%flood_watch = ();

sub check_flood {
  my ($channel, $nick, $user, $host, $text, $max, $mode) = @_;
  my $now = gettimeofday;

  $channel = lc $channel;

  $logger->log(sprintf("check flood %-48s %-16s %s\n", "$nick!$user\@$host", "[$channel]", $text));
  
  return if $nick eq $botnick;

  if(exists $flood_watch{$nick}) {
    #$logger->log("nick exists\n");

    if(not exists $flood_watch{$nick}{$channel}) {
      #$logger->log("adding new channel for existing nick\n");
      $flood_watch{$nick}{$channel}{offenses} = 0;
      $flood_watch{$nick}{$channel}{messages} = [];
    }

    #$logger->log("appending new message\n");
    
    push(@{ $flood_watch{$nick}{$channel}{messages} }, { timestamp => $now, msg => $text, mode => $mode });

    my $length = $#{ $flood_watch{$nick}{$channel}{messages} } + 1;

    #$logger->log("length: $length, max nick messages: $MAX_NICK_MESSAGES\n");

    if($length >= $MAX_NICK_MESSAGES) {
      my %msg = %{ shift(@{ $flood_watch{$nick}{$channel}{messages} }) };
      #$logger->log("shifting message off top: $msg{msg}, $msg{timestamp}\n");
      $length--;
    }

    return if not exists $channels{$channel} or $channels{$channel}{is_op} == 0;

    #$logger->log("length: $length, max: $max\n");

    if($length >= $max) {
      # $logger->log("More than $max messages spoken, comparing time differences\n");
      my %msg = %{ @{ $flood_watch{$nick}{$channel}{messages} }[$length - $max] };
      my %last = %{ @{ $flood_watch{$nick}{$channel}{messages} }[$length - 1] };

      #$logger->log("Comparing $last{timestamp} against $msg{timestamp}: " . ($last{timestamp} - $msg{timestamp}) . " seconds\n");

      if($last{timestamp} - $msg{timestamp} <= 10 && not PBot::BotAdminStuff::loggedin($nick, $host)) {
        $flood_watch{$nick}{$channel}{offenses}++;
        my $length = $flood_watch{$nick}{$channel}{offenses} * $flood_watch{$nick}{$channel}{offenses} * 30;
        if($channel =~ /^#/) { #channel flood (opposed to private message or otherwise)
          if($mode == $FLOOD_CHAT) {
            PBot::OperatorStuff::quiet_nick_timed($nick, $channel, $length);
            $conn->privmsg($nick, "You have been quieted due to flooding.  Please use a web paste service such as http://codepad.org for lengthy pastes.  You will be allowed to speak again in $length seconds.");
            $logger->log("$nick $channel flood offense $flood_watch{$nick}{$channel}{offenses} earned $length second quiet\n");
          }
        } else { # private message flood
          $logger->log("$nick msg flood offense $flood_watch{$nick}{$channel}{offenses} earned $length second ignore\n");
          PBot::IgnoreList::ignore_user("", "floodcontrol", "", "$nick" . '@' . "$host $channel $length");
        }
      }
    }
  } else {
    #$logger->log("brand new nick addition\n");
    # new addition
    $flood_watch{$nick}{$channel}{offenses}  = 0;
    $flood_watch{$nick}{$channel}{messages} = [];
    push(@{ $flood_watch{$nick}{$channel}{messages} }, { timestamp => $now, msg => $text, mode => $mode });
  }
}

1;
