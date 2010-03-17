# File: Interpreter.pm
# Authoer: pragma_
#
# Purpose: Parses a single line of input and takes appropriate action.

package PBot::Interpreter;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw($conn $MAX_FLOOD_MESSAGES $FLOOD_CHAT $logger %commands $botnick %admins %internal_commands
                  $max_msg_len $last_timestamp $flood_msg);
}

use vars @EXPORT_OK;

use Time::HiRes qw(gettimeofday);

*logger = \$PBot::PBot::logger;
*conn = \$PBot::PBot::conn;
*commands = \%PBot::FactoidStuff::commands;
*botnick = \$PBot::PBot::botnick;
*admins = \%PBot::BotAdminStuff::admins;
*internal_commands = \%PBot::InternalCommands::internal_commands;
*max_msg_len = \$PBot::PBot::max_msg_len;
*last_timestamp = \$PBot::AntiFlood::last_timestamp;
*flood_msg = \$PBot::AntiFlood::flood_msg;
*FLOOD_CHAT = \$PBot::AntiFlood::FLOOD_CHAT;
*MAX_FLOOD_MESSAGES = \$PBot::PBot::MAX_FLOOD_MESSAGES;

sub process_line {
  my ($from, $nick, $user, $host, $text) = @_;
  
  my ($command, $args, $result);
  my $has_url = undef;
  my $mynick = $conn->nick; 

  $from = lc $from if defined $from;

  PBot::AntiFlood::check_flood($from, $nick, $user, $host, $text, $MAX_FLOOD_MESSAGES, $FLOOD_CHAT) if defined $from;

  if($text =~ /^.?$mynick.?\s+(.*?)([\?!]*)$/i) {
    $command = "$1";
  } elsif($text =~ /^(.*?),?\s+$mynick([\?!]*)$/i) {
    $command = "$1";
  } elsif($text =~ /^!(.*?)(\?*)$/) {
    $command = "$1";
  } elsif($text =~ /http:\/\/([^\s]+)/i) {
    $has_url = $1;
  }

  if(defined $command || defined $has_url) {
    if((defined $command && $command !~ /^login/i) || defined $has_url) {
      $logger->log("ignored text: [$nick][$host][$from][$text]\n") and return if(defined $from && PBot::IgnoreList::check_ignore($nick, $user, $host, $from) && not PBot::BotAdminStuff::loggedin($nick, $host)); # ignored host
    }

    my $now = gettimeofday;
    
    if(defined $from) { # do not execute following if text is coming from STDIN ($from undef)
      if($from =~ /^#/) {
        $flood_msg++;
        $logger->log("flood_msg: $flood_msg\n");
      }

      if($flood_msg > 3) {
        $logger->log("flood_msg exceeded! [$flood_msg]\n");
        PBot::IgnoreList::ignore_user("", "floodcontrol", "", ".* $from 300");
        $flood_msg = 0;
        if($from =~ /^#/) {
          $conn->me($from, "has been overwhelmed.");
          $conn->me($from, "lies down and falls asleep."); 
          return;
        } 
      }

      if($now - $last_timestamp >= 15) {
        $last_timestamp = $now;
        if($flood_msg > 0) {
          $logger->log("flood_msg reset: (was $flood_msg)\n");
          $flood_msg = 0;
        }
      }
    }

    if(not defined $has_url) {
      $result = interpret_command($from, $nick, $user, $host, 1, $command);
    } else {
      $result = PBot::Modules::execute_module($from, undef, $nick, $user, $host, "title", "$nick http://$has_url");
    }
    
    $result =~ s/\$nick/$nick/g;

    # TODO add paging system?
    if(defined $result && length $result > 0) {
      my $len = length $result;
      if($len > $max_msg_len) {
        if(($len - $max_msg_len) > 10) {
          $logger->log("Message truncated.\n");
          $result = substr($result, 0, $max_msg_len);
          substr($result, $max_msg_len) = "... (" . ($len - $max_msg_len) . " more characters)";
        }
      }

      $logger->log("Final result: $result\n");
      
      if($result =~ s/^\/me\s+//i) {
        $conn->me($from, $result) if defined $from && $from !~ /\Q$botnick\E/i;
      } elsif($result =~ s/^\/msg\s+([^\s]+)\s+//i) {
        my $to = $1;
        if($to =~ /.*serv$/i) {
          $logger->log("[HACK] Possible HACK ATTEMPT /msg *serv: [$nick!$user\@$host] [$command] [$result]\n");
        }
        elsif($result =~ s/^\/me\s+//i) {
          $conn->me($to, $result) if $to !~ /\Q$botnick\E/i;
        } else {
          $result =~ s/^\/say\s+//i;
          $conn->privmsg($to, $result) if $to !~ /\Q$botnick\E/i;
        }
      } else {
        $conn->privmsg($from, $result) if defined $from && $from !~ /\Q$botnick\E/i;
      }
    }
    $logger->log("---------------------------------------------\n");
    exit if($PBot::Modules::child != 0); # if this process is a child, it must die now
  }
}

sub interpret_command {  
  my ($from, $nick, $user, $host, $count, $command) = @_;
  my ($keyword, $arguments, $tonick);
  my $text;

  $logger->log("=== Enter interpret_command: [" . (defined $from ? $from : "(undef)") . "][$nick!$user\@$host][$count][$command]\n");

  return "Too many levels of recursion, aborted." if(++$count > 5);

  if(not defined $nick || not defined $user || not defined $host ||
     not defined $command) {
    $logger->log("Error 1, bad parameters to interpret_command\n");
    return "";
  }

  if($command =~ /^tell\s+(.{1,20})\s+about\s+(.*?)\s+(.*)$/i) 
  {
    ($keyword, $arguments, $tonick) = ($2, $3, $1);
  } elsif($command =~ /^tell\s+(.{1,20})\s+about\s+(.*)$/) {
    ($keyword, $tonick) = ($2, $1);
  } elsif($command =~ /^([^ ]+)\s+is\s+also\s+(.*)$/) {
    ($keyword, $arguments) = ("change", "$1 s,\$, ; $2,");
  } elsif($command =~ /^([^ ]+)\s+is\s+(.*)$/) {
    ($keyword, $arguments) = ("add", join(' ', $1, $2)) unless exists $commands{$1};
    ($keyword, $arguments) = ($1, "is $2") if exists $commands{$1};
  } elsif($command =~ /^(.*?)\s+(.*)$/) {
    ($keyword, $arguments) = ($1, $2);
  } else {
    $keyword = $1 if $command =~ /^(.*)$/;
  }
  
  $arguments =~ s/\bme\b/\$nick/gi if defined $arguments;
  $arguments =~ s/\/\$nick/\/me/gi if defined $arguments;

  $logger->log("keyword: [$keyword], arguments: [" . (defined $arguments ? $arguments : "(undef)") . "], tonick: [" . (defined $tonick ? $tonick : "(undef)") . "]\n");

  if(defined $arguments && $arguments =~ m/\b(your|him|her|its|it|them|their)(self|selves)\b/i) {
    return "Why would I want to do that to myself?";
  }

  if(not defined $keyword) {
    $logger->log("Error 2, no keyword\n");
    return "";
  }

  # Check if it's an alias
  if(exists $commands{$keyword} and exists $commands{$keyword}{text}) {
    if($commands{$keyword}{text} =~ /^\/call\s+(.*)$/) {
      if(defined $arguments) {
        $command = "$1 $arguments";
      } else {
        $command = $1;
      }
      
      $logger->log("Command aliased to: [$command]\n");

      $commands{$keyword}{ref_count}++;
      $commands{$keyword}{ref_user} = $nick;

      return interpret_command($from, $nick, $user, $host, $count, $command);
    }
  }

  #$logger->log("Checking internal commands\n");

  # First, we check internal commands
  foreach $command (keys %internal_commands) {
    if($keyword =~ /^$command$/i) {
      $keyword = lc $keyword;
      if($internal_commands{$keyword}{level} > 0) {
        return "/msg $nick You must login to use this command." 
          if not PBot::BotAdminStuff::loggedin($nick, $host);
        return "/msg $nick Your access level of $admins{$nick}{level} is not sufficent to use this command."
          if $admins{$nick}{level} < $internal_commands{$keyword}{level};
      }
      $logger->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host Executing internal command: $keyword " . (defined $arguments ? $arguments : "") . "\n");
      return $internal_commands{$keyword}{sub}($from, $nick, $user, $host, $arguments);
    }
  }

  #$logger->log("Checking bot commands\n");

  # Then, we check bot commands
  foreach $command (keys %commands) {
    my $lc_command = lc $command;
    if(lc $keyword =~ m/^\Q$lc_command\E$/i) {
      
      $logger->log("=======================\n");
      $logger->log("[$keyword] == [$command]\n");
      
      if($commands{$command}{enabled} == 0) {
        $logger->log("$command disabled.\n");
        return "$command is currently disabled.";
      } elsif(exists $commands{$command}{module}) {
        $logger->log("Found module\n");
        
        $commands{$keyword}{ref_count}++;
        $commands{$keyword}{ref_user} = $nick;

        $text = PBot::Modules::execute_module($from, $tonick, $nick, $user, $host, $keyword, $arguments);
        return $text;
      }
      elsif(exists $commands{$command}{text}) {
        $logger->log("Found factoid\n");

        # Don't allow user-custom /msg factoids, unless factoid triggered by admin
        if(($commands{$command}{text} =~ m/^\/msg/i) and (not PBot::BotAdminStuff::loggedin($nick, $host))) {
          $logger->log("[HACK] Bad factoid (contains /msg): $commands{$command}{text}\n");
          return "You must login to use this command."
        }
        
        $commands{$command}{ref_count}++;
        $commands{$command}{ref_user} = $nick;
        
        $logger->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host): $command: Displaying text \"$commands{$command}{text}\"\n");
        
        if(defined $tonick) { # !tell foo about bar
          $logger->log("($from): $nick!$user\@$host) sent to $tonick\n");
          my $fromnick = PBot::BotAdminStuff::loggedin($nick, $host) ? "" : "$nick wants you to know: ";
          $text = $commands{$command}{text};

          if($text =~ s/^\/say\s+//i || $text =~ s/^\/me\s+/* $botnick /i
            || $text =~ /^\/msg\s+/i) {
            $text = "/msg $tonick $fromnick$text";
          } else {
            $text = "/msg $tonick $fromnick$command is $text";
          }

          $logger->log("text set to [$text]\n");
        } else {
          $text = $commands{$command}{text};
        }
        
        if(defined $arguments) {
          $logger->log("got arguments: [$arguments]\n");
          
          # TODO - extract and remove $tonick from end of $arguments
          if(not $text =~ s/\$args/$arguments/gi) {
            $logger->log("factoid doesn't take argument, checking ...\n");
            # factoid doesn't take an argument
            if($arguments =~ /^[^ ]{1,20}$/) {
              # might be a nick
              $logger->log("could be nick\n");
              if($text =~ /^\/.+? /) {
                $text =~ s/^(\/.+?) /$1 $arguments: /;
              } else {
                $text =~ s/^/\/say $arguments: $command is / unless (defined $tonick);
              }                  
            } else {
              if($text !~ /^\/.+? /) {
                $text =~ s/^/\/say $command is / unless (defined $tonick);
              }                  
            }
            $logger->log("updated text: [$text]\n");
          }
          $logger->log("replaced \$args: [$text]\n");
        } else {
          # no arguments supplied
          $text =~ s/\$args/$nick/gi;
        }
        
        $text =~ s/\$nick/$nick/g;
        
        while($text =~ /[^\\]\$([^\s!+.$\/\\,;=&]+)/g) { 
          my $var = $1;
          #$logger->log("adlib: got [$var]\n");
          #$logger->log("adlib: parsing variable [\$$var]\n");
          if(exists $commands{$var} && exists $commands{$var}{text}) {
            my $change = $commands{$var}{text};
            my @list = split(/\s|(".*?")/, $change);
            my @mylist;
            #$logger->log("adlib: list [". join(':', @mylist) ."]\n");
            for(my $i = 0; $i <= $#list; $i++) {
              #$logger->log("adlib: pushing $i $list[$i]\n");
              push @mylist, $list[$i] if $list[$i];
            }
            my $line = int(rand($#mylist + 1));
            $mylist[$line] =~ s/"//g;
            $text =~ s/\$$var/$mylist[$line]/;
            #$logger->log("adlib: found: change: $text\n");
          } else {
            $text =~ s/\$$var/$var/g;
            #$logger->log("adlib: not found: change: $text\n");
          }
        }
        
        $text =~ s/\\\$/\$/g;
        
        # $logger->log("finally... [$text]\n");
        if($text =~ s/^\/say\s+//i || $text =~ /^\/me\s+/i
          || $text =~ /^\/msg\s+/i) {
          # $logger->log("ret1\n");
          return $text;
        } else {
          # $logger->log("ret2\n");
          return "$command is $text";
        }
        
        $logger->log("unknown3: [$text]\n");
      } else {
        $logger->log("($from): $nick!$user\@$host): Unknown command type for '$command'\n"); 
        return "/me blinks.";
      }
      $logger->log("unknown4: [$text]\n");
    } # else no match
  } # end foreach
  
  #$logger->log("Checking regex factoids\n");

  # Otherwise, the command was not found.
  # Lets try regexp factoids ...
  my $string = "$keyword" . (defined $arguments ? " $arguments" : "");
  
  foreach my $command (sort keys %commands) {
    if(exists $commands{$command}{regex}) {
      eval {
        my $regex = qr/$command/i;
        # $logger->log("testing $string =~ $regex\n");
        if($string =~ $regex) {
          $logger->log("[$string] matches [$command][$regex] - calling [" . $commands{$command}{regex}. "$']\n");
          my $cmd = "$commands{$command}{regex}$'";
          my $a = $1;
          my $b = $2;
          my $c = $3;
          my $d = $4;
          my $e = $5;
          my $f = $6;
          my $g = $7;
          my $h = $8;
          my $i = $9;
          my $before = $`;
          my $after = $';
          $cmd =~ s/\$1/$a/g;
          $cmd =~ s/\$2/$b/g;
          $cmd =~ s/\$3/$c/g;
          $cmd =~ s/\$4/$d/g;
          $cmd =~ s/\$5/$e/g;
          $cmd =~ s/\$6/$f/g;
          $cmd =~ s/\$7/$g/g;
          $cmd =~ s/\$8/$h/g;
          $cmd =~ s/\$9/$i/g;
          $cmd =~ s/\$`/$before/g;
          $cmd =~ s/\$'/$after/g;
          $cmd =~ s/^\s+//;
          $cmd =~ s/\s+$//;
          $text = interpret_command($from, $nick, $user, $host, $count, $cmd);
          return $text;
        }
      };
      if($@) {
        $logger->log("Regex fail: $@\n");
        return "/msg $nick Fail.";
      }
    }
  }
  
  $logger->log("[$keyword] not found.\n");
  return ""; 
}

1;
