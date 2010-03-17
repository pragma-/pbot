# File: NewModule.pm
# Authoer: pragma_
#
# Purpose: New module skeleton

package PBot::TimerStuff;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw(%quieted_nicks $logger $conn %ignore_list %is_opped %unban_timeout $export_quotegrabs_path
                  $export_quotegrabs_time $export_quotegrabs_timeout $export_factoids_path $export_factoids_time
                  $export_factoids_timeout %flood_watch @op_commands);
}

use vars @EXPORT_OK;

use Time::HiRes qw(gettimeofday);

*logger = \$PBot::PBot::logger;
*conn = \$PBot::PBot::conn;
*ignore_list = \%PBot::IgnoreList::ignore_list;
*is_opped = \%PBot::OperatorStuff::is_opped;
*op_commands = \@PBot::OperatorStuff::op_commands;
*quieted_nicks = \%PBot::OperatorStuff::quieted_nicks;
*flood_watch = \%PBot::AntiFlood::flood_watch;
*unban_timeout = \%PBot::OperatorStuff::unban_timeout;
*export_quotegrabs_path = \$PBot::PBot::export_quotegrabs_path;
*export_quotegrabs_timeout = \$PBot::PBot::export_quotegrabs_timeout;
*export_quotegrabs_time = \$PBot::PBot::export_quotegrabs_time;
*export_factoids_path = \$PBot::PBot::export_factoids_path;
*export_factoids_timeout = \$PBot::PBot::export_factoids_timeout;
*export_factoids_time = \$PBot::PBot::export_factoids_time;

# alarm signal handler (poor-man's timer)
$SIG{ALRM} = \&sig_alarm_handler;

#start alarm timeout
alarm 10;

sub sig_alarm_handler {
  # check timeouts
  # TODO:  Make this module a class with registerable handlers/call-backs
  check_quieted_timeouts();
  check_ignore_timeouts();
  check_opped_timeout();
  check_unban_timeouts();
  check_export_timeout();
  check_message_history_timeout();
  alarm 10;
}

# TODO: Move these to their respective modules, and add handler support

sub check_quieted_timeouts {
  my $now = gettimeofday();

  foreach my $nick (keys %quieted_nicks) {
    if($quieted_nicks{$nick}{time} < $now) {
      $logger->log("Unquieting $nick\n");
      PBot::OperatorStuff::unquiet_nick($nick, $quieted_nicks{$nick}{channel});
      delete $quieted_nicks{$nick};
      $conn->privmsg($nick, "You may speak again.");
    } else {
      #my $timediff = $quieted_nicks{$nick}{time} - $now;
      #$logger->log "quiet: $nick has $timediff seconds remaining\n"
    }
  }
}

sub check_ignore_timeouts {
  my $now = gettimeofday();

  foreach my $hostmask (keys %ignore_list) {
    foreach my $channel (keys %{ $ignore_list{$hostmask} }) {
      next if($ignore_list{$hostmask}{$channel} == -1); #permanent ignore

      if($ignore_list{$hostmask}{$channel} < $now) {
        PBot::IgnoreList::unignore_user("", "floodcontrol", "", "$hostmask $channel");
        if($hostmask eq ".*") {
          $conn->me($channel, "awakens.");
        }
      } else {
        #my $timediff = $ignore_list{$host}{$channel} - $now;
        #$logger->log "ignore: $host has $timediff seconds remaining\n"
      }
    }
  }
}

sub check_opped_timeout {
  my $now = gettimeofday();

  foreach my $channel (keys %is_opped) {
    if($is_opped{$channel}{timeout} < $now) {
      PBot::OperatorStuff::lose_ops($channel);
    } else {
      # my $timediff = $is_opped{$channel}{timeout} - $now;
      # $logger->log("deop $channel in $timediff seconds\n");
    }
  }
}

sub check_unban_timeouts {
  my $now = gettimeofday();

  foreach my $ban (keys %unban_timeout) {
    if($unban_timeout{$ban}{timeout} < $now) {
      unshift @op_commands, "mode $unban_timeout{$ban}{channel} -b $ban";
      PBot::OperatorStuff::gain_ops($unban_timeout{$ban}{channel});
      delete $unban_timeout{$ban};
    } else {
      #my $timediff = $unban_timeout{$ban}{timeout} - $now;
      #$logger->log("$unban_timeout{$ban}{channel}: unban $ban in $timediff seconds\n");
    }
  }
}

sub check_export_timeout {
  my $now = gettimeofday();
  
  if($now > $export_quotegrabs_time && defined $export_quotegrabs_path) {
    PBot::Quotegrabs::export_quotegrabs();
    $export_quotegrabs_time = $now + $export_quotegrabs_timeout;
  }
  
  if($now > $export_factoids_time && defined $export_factoids_path) {
    PBot::FactoidStuff::export_factoids();
    $export_factoids_time = $now + $export_factoids_timeout;
  }
}


BEGIN {
  my $last_run = gettimeofday();
  
  sub check_message_history_timeout {
    my $now = gettimeofday();

    if($now - $last_run < 60 * 60) {
      return;
    } else {
      $logger->log("One hour has elapsed -- running check_message_history_timeout\n");
    }
    
    $last_run = $now;
    
    foreach my $nick (keys %flood_watch) {
      foreach my $channel (keys %{ $flood_watch{$nick} })
      {
        #$logger->log("Checking [$nick][$channel]\n");
        my $length = $#{ $flood_watch{$nick}{$channel}{messages} } + 1;
        my %last = %{ @{ $flood_watch{$nick}{$channel}{messages} }[$length - 1] };

        if($now - $last{timestamp} >= 60 * 60 * 24) {
          $logger->log("$nick in $channel hasn't spoken in 24 hours, removing message history.\n");
          delete $flood_watch{$nick}{$channel};
        }
      }
    }
  }
}

1;
