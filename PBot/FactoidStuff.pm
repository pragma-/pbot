# File: NewModule.pm
# Authoer: pragma_
#
# Purpose: New module skeleton

package PBot::FactoidStuff;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw($logger %commands $commands_file $export_factoids_path $export_factoids_timeout);
}

use vars @EXPORT_OK;

*logger = \$PBot::PBot::logger;
*commands_file = \$PBot::PBot::commands_file;
*export_factoids_path = \$PBot::PBot::export_factoids_path;
*export_factoids_timeout = \$PBot::PBot::export_factoids_timeout;

# TODO: move into pbot object, or make FactoidStuff an object and move this into it
%commands = ();

sub load_commands {
  $logger->log("Loading commands from $commands_file ...\n");
  
  open(FILE, "< $commands_file") or die "Couldn't open $commands_file: $!\n";
  my @contents = <FILE>;
  close(FILE);

  my $i = 0;
  foreach my $line (@contents) {
    chomp $line;
    $i++;
    my ($command, $type, $enabled, $owner, $timestamp, $ref_count, $ref_user, $value) = split(/\s+/, $line, 8);
    if(not defined $command || not defined $enabled || not defined $owner || not defined $timestamp
       || not defined $type || not defined $ref_count
       || not defined $ref_user || not defined $value) {
      die "Syntax error around line $i of $commands_file\n";
    }
    if(exists $commands{$command}) {
      die "Duplicate command $command found in $commands_file around line $i\n";
    }
    $commands{$command}{enabled} = $enabled;
    $commands{$command}{$type}   = $value;
    $commands{$command}{owner}   = $owner;
    $commands{$command}{timestamp} = $timestamp;
    $commands{$command}{ref_count} = $ref_count;
    $commands{$command}{ref_user} = $ref_user;
#    $logger->log("  Adding command $command ($type): $owner, $timestamp...\n");
  }
  $logger->log("  $i commands loaded.\n");
  $logger->log("Done.\n");
}

sub save_commands {
  open(FILE, "> $commands_file") or die "Couldn't open $commands_file: $!\n";

  foreach my $command (sort keys %commands) {
    next if $command eq "version";
    if(defined $commands{$command}{module} || defined $commands{$command}{text} || defined $commands{$command}{regex}) {
      print FILE "$command ";
    } else {
      $logger->log("save_commands: unknown command type $command\n");
      next;
    }
    #bleh, this is ugly - duplicated
    if(defined $commands{$command}{module}) {
      print FILE "module ";
      print FILE "$commands{$command}{enabled} $commands{$command}{owner} $commands{$command}{timestamp} ";
      print FILE "$commands{$command}{ref_count} $commands{$command}{ref_user} ";
      print FILE "$commands{$command}{module}\n";
    } elsif(defined $commands{$command}{text}) {
      print FILE "text ";
      print FILE "$commands{$command}{enabled} $commands{$command}{owner} $commands{$command}{timestamp} ";
      print FILE "$commands{$command}{ref_count} $commands{$command}{ref_user} ";
      print FILE "$commands{$command}{text}\n";
    } elsif(defined $commands{$command}{regex}) {
      print FILE "regex ";
      print FILE "$commands{$command}{enabled} $commands{$command}{owner} $commands{$command}{timestamp} ";
      print FILE "$commands{$command}{ref_count} $commands{$command}{ref_user} ";
      print FILE "$commands{$command}{regex}\n";
    } else {
      $logger->log("save_commands: skipping unknown command type for $command\n");
    }
  }
  close(FILE);
}

sub export_factoids() {
  my $text;
  open FILE, "> $export_factoids_path" or return "Could not open export path.";
  my $time = localtime;
  print FILE "<html><body><i>Generated at $time</i><hr><h3>Candide's factoids:</h3><br>\n";
  my $i = 0;
  print FILE "<table border=\"0\">\n";
  foreach my $command (sort keys %commands) {
    if(exists $commands{$command}{text}) {
      $i++;
      if($i % 2) {
        print FILE "<tr bgcolor=\"#dddddd\">\n";
      } else {
        print FILE "<tr>\n";
      }
      $text = "<td><b>$command</b> is " . encode_entities($commands{$command}{text}) . "</td>\n"; 
      print FILE $text;
      my ($seconds, $minutes, $hours, $day_of_month, $month, $year, $wday, $yday, $isdst) = localtime($commands{$command}{timestamp});
      my $t = sprintf("%02d:%02d:%02d-%04d/%02d/%02d\n",
          $hours, $minutes, $seconds, $year+1900, $month+1, $day_of_month);
      print FILE "<td align=\"right\">- submitted by<br> $commands{$command}{owner}<br><i>$t</i>\n";
      print FILE "</td></tr>\n";
    }
  }
  print FILE "</table>\n";
  print FILE "<hr>$i factoids memorized.<br>This page is automatically generated every $export_factoids_timeout seconds.</body></html>";
  close(FILE);
  #$logger->log("$i factoids exported.\n");
  return "$i factoids exported to http://blackshell.com/~msmud/candide/factoids.html";
}

1;
