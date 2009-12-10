#!/usr/bin/perl 
#
# File: pbot2.pl
# Author: pragma_
#
# Purpose: IRC Bot (2nd generation)
#
# Version History:
########################

my $VERSION = "0.4.2";

########################
# todo! add support for admin management - needs support for adding/removing/saving!
# todo! multi-channel support pathetic (note 12/08/09, fixed multi-channel for anti-flood and for ignore)
# todo! most of this crap needs to be refactored (note 11/23/09, refactored execute_module)
# 
# 0.4.2 (12/09/09): added support for quotegrabs: !grab, !getq, and !rq
# 0.4.1 (12/08/09): improved anti-flood system to be significantly more accurate and per-channel
#                   added per-nick-per-channel message history using %flood_watch
#                   add per-channel support to ignore system
#                   automatically remove message history for nicks that haven't spoken in one day (run once per hour)
#                   do not ignore !login command
# 0.3.16(11/23/09): refactored module execution to execute_module() subroutine
#                   added trigger to execute get_title.pl module when URL is
#                   detected in regular untriggered chat
# 0.3.15(11/20/09): replace 'me' with '$nick' in arguments
# 0.3.14(07/03/07): do not expand escaped dollar-signs in factoids (adlib)
# 0.3.13(07/01/07): fork all modules
#                   added unload_module, enable_command, disable_command
#                   automatically export factoids every $export_factoids_timeout seconds
# 0.3.12(05/20/07): lol?  Prevent recursive aliasing infinite loop, x -> a, a -> x
# 0.3.11(05/20/07): added 'alias'
# 0.3.10(05/08/05): dont ban by nick, wait for nickserv response before joining chans
# 0.3.9 (05/06/05): stop logging joins, fixed join flood ban?
# 0.3.8 (04/28/05): changed 'top10' to 'top20' throughout
# 0.3.7 (04/28/05): 'top10 recent' command lists 10 most recent factoid additions
# 0.3.6 (04/15/05): join/part flood earns ban (broken, I'm lazy)
# 0.3.5 (03/24/05): fix bug in interpret_command re $commands and $keyword
#                   keeps track of op state in multi-channels (but not commands)
#                   added nick searching to top10
# 0.3.4 (03/22/05): added kick
#                   list also lists admins
#                   ban also kicks nick
#                   unban also modes -b in addition to ChanServ AUTOREM DEL
#                   oops, moved $is_opped = 0 from lose_ops() to on_mode()
# 0.3.3 (03/21/05): added ban, unban using ChanServ AUTOREM
# 0.3.2 (03/20/05): stays opped for a minimum of 5 minutes before deop
# 0.3.1 (03/18/05): log out departed admins
#                   implemented ignore and unignore
#                   flooding with commands triggers timed ignore
#                   no flood consequences for logged in admins
# 0.3.0 (03/17/05): Hi-res timer support.
#                   renamed %admin_commands to %internal_commands
#                   added admin levels to %admin_commands
#                   added access levels to internal commands
#                   interpret_command uses access levels and checks login status
#                   removed all extraneous loggedin() checks
#                   internal commands processed before bot commands
#                   added flood control
#                   flooding channel tiggers timed quiet
# 0.2.18(03/16/05): direct at $nick within channel
# 0.2.17(03/11/05): Most confirmation and warning messages sent via /msg
#                   restricted parsing to bot's name or ! only
# 0.2.16(03/02/05): added '/msg'
#                   /msg doesn't show ($nick) if admin
# 0.2.15(02/20/05): special variable lists, "adlibs"
# 0.2.14(02/19/05): added $botnick and $altbotnick
#                   added more rules to trigger interpret_command
#                   added '/me'
#                   added '$args', allowed factoids to take arguments    
# 0.2.13(02/19/05): added '/say' for no '<foo> is'
#                   added $nick expansion in factoids
#                   added 'show' command to display factoid literal          
# 0.2.12(02/16/05): improved html for export
#                   added 'commands' to list command
# 0.2.11(02/12/05): added popularity to 'info' command
#                   'top10' command for factoids
# 0.2.10(02/07/05): added histogram command
# 0.2.9 (02/03/05): info <factoid> || info <module>
#                   find <factoid keyword>
#                   use eval {} in change_text
#                   count <nick> returns # of factoids <nick> has submitted
# 0.2.8 (02/02/05): change_text: show result of change
#                   ... debugging prints throughout
#                   Allowed factoids to be appended using 'is also'
# 0.2.7 (01/27/05): Removed '<command> for <nick>' syntax to direct
#                   a command at a user.  Using 'tell <nick> about <command>'
#                   instead.
# 0.2.6 (01/22/05): Major source overhaul.
#                   Allowed any non-word character to be used
#                   as delimiter in change_text.
# 0.2.5 (01/18/05): Don't die in save_commands.
# 0.2.4 (01/18/05): Added 'change' command. 
# 0.2.3 (01/17/05): Allowed factoids to be added using '%foo is bar' 
# 0.2.2 (01/17/05): Responds only when addressed or explicitly triggered.
# 0.2.1 (01/17/05): Allowed trailing question marks.  
#                   Allowed 'is' for add_text.
#                   Some minor bug fixes.
#                   Aliased forget => remove.
# 0.2.0 (01/16/05): Revamped hash structures for factoids.
#                   All commands have a timestamp and owner.
#                   Added 'export' command and modifed 'list'.
# 0.1.4 (01/16/05): Minor tweaks and fixes for logging.
# 0.1.3 (01/16/05): Can direct commands at nicks.
#                   example: man fork for <nick>
# 0.1.2 (01/15/05): Added 'list' admin command.
# 0.1.1 (01/15/05): Some minor tweaks and fixes.
# 0.1.0 (01/15/05): Initial version

use Net::IRC;                        # for the main IRC engine
use HTML::Entities;                  # for exporting
use Time::HiRes qw(gettimeofday alarm);
use strict;

use POSIX 'WNOHANG';
# automatically reap children processes in background
$SIG{CHLD} = sub { while(waitpid(-1, WNOHANG) > 0) {} };
my $child = 0; # this process is not the child        

#unbuffer stdout
STDOUT->autoflush(1);

#signal handlers
$SIG{ALRM} = \&sig_alarm_handler;

# some configuration variables
my $home = $ENV{HOME};
my $channels_file     = "$home/pbot2/channels";
my $commands_file     = "$home/pbot2/commands";
my $quotegrabs_file   = "$home/pbot2/quotegrabs";
my $admins_file       = "$home/pbot2/admins";
my $module_dir        = "$home/pbot2/modules";
my $ircserver         = 'irc.freenode.net';
my $botnick           = 'candide';
my $altbotnick        = 'candide_';
my $identify_password = 'habernat21';
my $export_factoids_timeout = 300; # every 5 minutes
my $export_factoids_time = gettimeofday + $export_factoids_timeout;
my $export_factoids_path = "$home/htdocs/candide/factoids.html";

my $MAX_FLOOD_MESSAGES = 4;
my $MAX_NICK_MESSAGES = 8;

# do not modify FLOOD_*
my $FLOOD_CHAT = 0;
my $FLOOD_JOIN = 1;  # currently unused -- todo?

my %flood_watch = ();

# set some defaults ...
my $max_msg_len = 460;
my %commands   =  ( version => { 
                       enabled   => 1, 
                       owner     => "pragma_", 
                       text      => "pbot2 version $VERSION", 
                       timestamp => 0,
                       ref_count => 0, 
                       ref_user  => "nobody" } 
                 );

my @quotegrabs   =  ({ 
                       nick      => "candide",
                       text      => "Who's a bot?", 
                       channel   => "#pbot2", 
                       grabbed_by => "pragma_", 
                       timestamp => 0 
                     });

my %admins     = ( pragma_ => { 
                       password => '*', 
                       level    => 50, 
                       host => "unaffiliated/pragma/x-109842" },
                   _pragma => {
                       password => '*', 
                       level    => 50, 
                       host => ".*.tmcc.edu" }
                 );
                 
my %channels    = ();

#... and load the rest
load_channels();
load_quotegrabs();
load_commands();

sub plog;
my $irc = new Net::IRC;
plog "Connecting to $ircserver ...\n";
my $conn = $irc->newconn( Nick         => $botnick,
                          Username     => 'pbot2',
                          Ircname      => 'http://www.iso-9899.info/wiki/Candide',
                          Server       => $ircserver,
                          Port         => 6667)
  or die "$0: Can't connect to IRC server.\n";

#internal commands
my %internal_commands = ( 
  alias     => { sub => \&alias,                 level=> 0  },
  add       => { sub => \&add_text,              level=> 0  },
  regex     => { sub => \&add_regex,             level=> 0  },
  learn     => { sub => \&add_text,              level=> 0  },
  grab      => { sub => \&quotegrab,             level=> 0  },
  getq      => { sub => \&show_quotegrab,        level=> 0  },
  rq        => { sub => \&show_random_quotegrab, level=> 0  },
  info      => { sub => \&info,                  level=> 0  },
  show      => { sub => \&show,                  level=> 0  },
  histogram => { sub => \&histogram,             level=> 0  },
  top20     => { sub => \&top20,                 level=> 0  },
  count     => { sub => \&count,                 level=> 0  },
  find      => { sub => \&find,                  level=> 0  },
  change    => { sub => \&change_text,           level=> 0  },
  remove    => { sub => \&remove_text,           level=> 0  },
  forget    => { sub => \&remove_text,           level=> 0  },
  export    => { sub => \&export,                level=> 20 },
  list      => { sub => \&list,                  level=> 0  },
  load      => { sub => \&load_module,           level=> 40 },
  unload    => { sub => \&unload_module,         level=> 40 },
  enable    => { sub => \&enable_command,        level=> 20 },
  disable   => { sub => \&disable_command,       level=> 20 },
  quiet     => { sub => \&quiet,                 level=> 10 },
  unquiet   => { sub => \&unquiet,               level=> 10 },
  ignore    => { sub => \&ignore_user,           level=> 10 }, 
  unignore  => { sub => \&unignore_user,         level=> 10 },
  ban       => { sub => \&ban_user,              level=> 10 }, 
  unban     => { sub => \&unban_user,            level=> 10 }, 
  kick      => { sub => \&kick_nick,             level=> 10 },
  login     => { sub => \&login,                 level=> 0  },
  logout    => { sub => \&logout,                level=> 0  },
  join      => { sub => \&join_channel,          level=> 50 },
  part      => { sub => \&part_channel,          level=> 50 },
  addadmin  => { sub => \&add_admin,             level=> 40 },
  deladmin  => { sub => \&del_admin,             level=> 40 }, 
  die       => { sub => \&ack_die,               level=> 50 } 
);

#set up handlers for the IRC engine
$conn->add_handler([ 251,252,253,254,302,255 ], \&on_init);
$conn->add_handler(376                        , \&on_connect    );
$conn->add_handler('disconnect'               , \&on_disconnect );
$conn->add_handler('caction'                  , \&on_action     );
$conn->add_handler('public'                   , \&on_public     );
$conn->add_handler('msg'                      , \&on_msg        );
$conn->add_handler('mode'                     , \&on_mode       );
$conn->add_handler('part'                     , \&on_departure  );
$conn->add_handler('join'                     , \&on_join       );
$conn->add_handler('quit'                     , \&on_departure  );

#start alarm timeout
alarm 10;

#start the main IRC engine (infinite loop)
$irc->start;

#not reached
exit 0;

# Internal command related subroutines
#################################################

sub loggedin {
  my ($nick, $host) = @_;

  if(exists $admins{$nick} && $host =~ /$admins{$nick}{host}/
     && exists $admins{$nick}{login}) {
    return 1;
  } else {
    return 0;
  }
}

sub export {
  my ($from, $nick, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "/msg $nick Usage: export <modules|factoids|admins>";
  }

  if($arguments =~ /^modules$/i) {
    return "/msg $nick Coming soon.";
  }

  if($arguments =~ /^factoids$/i) {
    return export_factoids(); 
  }

  if($arguments =~ /^admins$/i) {
    return "/msg $nick Coming soon.";
  }
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
  #plog "$i factoids exported.\n";
  return "$i factoids exported to http://blackshell.com/~msmud/candide/factoids.html";

}

sub list {
  my ($from, $nick, $host, $arguments) = @_;
  my $text;
  
  if(not defined $arguments) {
    return "/msg $nick Usage: list <modules|factoids|commands|admins>";
  }

  if($arguments =~/^messages\s+(.*?)\s+(.*)$/) {
    my $nick_search = $1;
    my $channel = $2;

    if(not exists $flood_watch{$nick}) {
      return "/msg $nick No messages for $nick_search yet.";
    }

    if(not exists $flood_watch{$nick}{$channel}) {
      return "/msg $nick No messages for $nick_search in $channel yet.";
    }

    my @messages = @{ $flood_watch{$nick}{$channel}{messages} };

    for(my $i = 0; $i <= $#messages; $i++) {
      $conn->privmsg($nick, "" . ($i + 1) . ": " . $messages[$i]->{msg} . "\n");
    }
    return "";
  }

  if($arguments =~ /^modules$/i) {
    $text = "Loaded modules: ";
    foreach my $command (sort keys %commands) {
      if(exists $commands{$command}{module}) {
        $text .= "$command ";
      }
    }
    return $text;
  }

  if($arguments =~ /^commands$/i) {
    $text = "Internal commands: ";
    foreach my $command (sort keys %internal_commands) {
      $text .= "$command ";
      $text .= "($internal_commands{$command}{level}) " 
        if $internal_commands{$command}{level} > 0;
    }
    return $text;
  }

  if($arguments =~ /^factoids$/i) {
    return "For a list of factoids see http://blackshell.com/~msmud/candide/factoids.html";
  }

  if($arguments =~ /^admins$/i) {
    $text = "Admins: ";
    foreach my $admin (sort { $admins{$b}{level} <=> $admins{$a}{level} } keys %admins) {
      $text .= "*" if exists $admins{$admin}{login};
      $text .= "$admin ($admins{$admin}{level}) ";
    }
    return $text;
  }
  return "/msg $nick Usage: list <modules|commands|factoids|admins>";
}

sub alias {
  my ($from, $nick, $host, $arguments) = @_;
  my ($alias, $command) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;
  
  if(not defined $command) {
    plog "alias: invalid usage\n";
    return "/msg $nick Usage: alias <keyword> <command>";
  }
  
  if(exists $commands{$alias}) {
    plog "attempt to overwrite existing command\n";
    return "/msg $nick '$alias' already exists";
  }
  
  $commands{$alias}{text}      = "/call $command";
  $commands{$alias}{owner}     = $nick;
  $commands{$alias}{timestamp} = time();
  $commands{$alias}{enabled}   = 1;
  $commands{$alias}{ref_count} = 0;
  $commands{$alias}{ref_user}  = "nobody";
  plog "$nick ($host) aliased $alias => $command\n";
  save_commands();
  return "/msg $nick '$alias' aliases '$command'";  
}

sub add_regex {
  my ($from, $nick, $host, $arguments) = @_;
  my ($keyword, $text) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if(not defined $keyword) {
    $text = "";
    foreach my $command (sort keys %commands) {
      if(exists $commands{$command}{regex}) {
        $text .= $command . " ";
      }
    }
    return "Stored regexs: $text";
  }

  if(not defined $text) {
    plog "add_regex: invalid usage\n";
    return "/msg $nick Usage: regex <regex> <command>";
  }

  if(exists $commands{$keyword}) {
    plog "$nick ($host) attempt to overwrite $keyword\n";
    return "/msg $nick $keyword already exists.";
  }

  $commands{$keyword}{regex}     = $text;
  $commands{$keyword}{owner}     = $nick;
  $commands{$keyword}{timestamp} = time();
  $commands{$keyword}{enabled}   = 1;
  $commands{$keyword}{ref_count} = 0;
  $commands{$keyword}{ref_user}  = "nobody";
  plog "$nick ($host) added [$keyword] => [$text]\n";
  save_commands();
  return "/msg $nick $keyword added.";
}

sub add_text {
  my ($from, $nick, $host, $arguments) = @_;
  my ($keyword, $text) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if(not defined $text) {
    plog "add_text: invalid usage\n";
    return "/msg $nick Usage: add <keyword> <factoid>";
  }

  if(not defined $keyword) {
    plog "add_text: invalid usage\n";
    return "/msg $nick Usage: add <keyword> <factoid>";
  }

  $text =~ s/^is\s+//;

  if(exists $commands{$keyword}) {
    plog "$nick ($host) attempt to overwrite $keyword\n";
    return "/msg $nick $keyword already exists.";
  }

  $commands{$keyword}{text}      = $text;
  $commands{$keyword}{owner}     = $nick;
  $commands{$keyword}{timestamp} = time();
  $commands{$keyword}{enabled}   = 1;
  $commands{$keyword}{ref_count} = 0;
  $commands{$keyword}{ref_user}  = "nobody";
  plog "$nick ($host) added $keyword => $text\n";
  save_commands();
  return "/msg $nick $keyword added.";
}

sub histogram {
  my ($from, $nick, $host, $arguments) = @_;
  my %hash;
  my $factoids = 0;

  foreach my $command (keys %commands) {
    if(exists $commands{$command}{text}) {
      $hash{$commands{$command}{owner}}++;
      $factoids++;
    }
  }

  my $text;
  my $i = 0;

  foreach my $owner (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
    my $percent = int($hash{$owner} / $factoids * 100);
    $percent = 1 if $percent == 0;
    $text .= "$owner: $hash{$owner} ($percent". "%) ";  
    $i++;
    last if $i >= 10;
  }
  return "$factoids factoids, top 10 submitters: $text";
}

sub show {
  my ($from, $nick, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "/msg $nick Usage: show <factoid>";
  }

  if(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found";
  }

  if(exists $commands{$arguments}{command} || exists $commands{$arguments}{module}) {
    return "/msg $nick $arguments is not a factoid";
  }

  my $type;
  $type = 'text' if exists $commands{$arguments}{text};
  $type = 'regex' if exists $commands{$arguments}{regex};
  return "$arguments: $commands{$arguments}{$type}";
}

sub info {
  my ($from, $nick, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "/msg $nick Usage: info <factoid|module>";
  }

  if(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found";
  }

  # factoid
  if(exists $commands{$arguments}{text}) {
    my ($seconds, $minutes, $hours, $day_of_month, $month, $year, $wday, $yday, $isdst) = 
      localtime($commands{$arguments}{timestamp});
    my $t = sprintf("%02d:%02d:%02d-%04d/%02d/%02d",
              $hours, $minutes, $seconds, $year+1900, $month+1, $day_of_month);
    return "$arguments: Factoid submitted by $commands{$arguments}{owner} on $t, referenced $commands{$arguments}{ref_count} times (last by $commands{$arguments}{ref_user})";
  }

  # module
  if(exists $commands{$arguments}{module}) {
    my ($seconds, $minutes, $hours, $day_of_month, $month, $year, $wday, $yday, $isdst) = 
      localtime($commands{$arguments}{timestamp});
    my $t = sprintf("%02d:%02d:%02d-%04d/%02d/%02d",
              $hours, $minutes, $seconds, $year+1900, $month+1, $day_of_month);
    return "$arguments: Module loaded by $commands{$arguments}{owner} on $t -> http://pragma.homeip.net/stuff/scripts/$commands{$arguments}{module}, used $commands{$arguments}{ref_count} times (last by $commands{$arguments}{ref_user})"; 
  }

  # regex
  if(exists $commands{$arguments}{regex}) {
    my ($seconds, $minutes, $hours, $day_of_month, $month, $year, $wday, $yday, $isdst) = 
      localtime($commands{$arguments}{timestamp});
    my $t = sprintf("%02d:%02d:%02d-%04d/%02d/%02d",
              $hours, $minutes, $seconds, $year+1900, $month+1, $day_of_month);
    return "$arguments: Regex created by $commands{$arguments}{owner} on $t, used $commands{$arguments}{ref_count} times (last by $commands{$arguments}{ref_user})"; 
  }

  return "/msg $nick $arguments is not a factoid or a module";
}

sub top20 {
  my ($from, $nick, $host, $arguments) = @_;
  my %hash = ();
  my $text = "";
  my $i = 0;

  if(not defined $arguments) {
    foreach my $command (sort {$commands{$b}{ref_count} <=> $commands{$a}{ref_count}} keys %commands) {
      if($commands{$command}{ref_count} > 0 && exists $commands{$command}{text}) {
        $text .= "$command ($commands{$command}{ref_count}) ";
        $i++;
        last if $i >= 20;
      }
    }
    $text = "Top $i referenced factoids: $text" if $i > 0;
    return $text;
  } else {

    if(lc $arguments eq "recent") {
      foreach my $command (sort { $commands{$b}{timestamp} <=> $commands{$a}{timestamp} } keys %commands) {
        #my ($seconds, $minutes, $hours, $day_of_month, $month, $year, $wday, $yday, $isdst) = localtime($commands{$command}{timestamp});
        #my $t = sprintf("%04d/%02d/%02d", $year+1900, $month+1, $day_of_month);
                
        $text .= "$command ";
        $i++;
        last if $i >= 50;
      }
      $text = "$i most recent submissions: $text" if $i > 0;
      return $text;
    }

    my $user = lc $arguments;
    foreach my $command (sort keys %commands) {
      if($commands{$command}{ref_user} =~ /\Q$arguments\E/i) {
        if($user ne lc $commands{$command}{ref_user} && not $user =~ /$commands{$command}{ref_user}/i) {
          $user .= " ($commands{$command}{ref_user})";
        }
        $text .= "$command ";
        $i++;
        last if $i >= 20;
      }
    }
    $text = "$i factoids last referenced by $user: $text" if $i > 0;
    return $text;
  }
}

sub count {
  my ($from, $nick, $host, $arguments) = @_;
  my $i = 0;
  my $total = 0;

  if(not defined $arguments) {
    return "/msg $nick Usage:  count <nick|factoids>";
  }

  $arguments = ".*" if($arguments =~ /^factoids$/);

  eval {
    foreach my $command (keys %commands) {
      $total++ if exists $commands{$command}{text};
      my $regex = qr/^\Q$arguments\E$/;
      if($commands{$command}{owner} =~ /$regex/i && exists $commands{$command}{text}) {
        $i++;
      }
    }
  };
  return "/msg $nick $arguments: $@" if $@;

  return "I have $i factoids" if($arguments eq ".*");

  if($i > 0) {
    my $percent = int($i / $total * 100);
    $percent = 1 if $percent == 0;
    return "$arguments has submitted $i factoids out of $total ($percent"."%)";
  } else {
    return "$arguments hasn't submitted any factoids";
  }
}

sub find {
  my ($from, $nick, $host, $arguments) = @_;
  my $i = 0;
  my $text;
  my $type;

  foreach my $command (sort keys %commands) {
    if(exists $commands{$command}{text} || exists $commands{$command}{regex}) {
      $type = 'text' if(exists $commands{$command}{text});
      $type = 'regex' if(exists $commands{$command}{regex});
      plog "Checking [$command], type: [$type]\n";
      eval {
        my $regex = qr/$arguments/;
        if($commands{$command}{$type} =~ /$regex/i || $command =~ /$regex/i) 
        {
          $i++;
          $text .= "$command ";     
        }
      };
      return "/msg $nick $arguments: $@" if $@;
    }
  }
  
  if($i == 1) {
    chop $text;
    $type = 'text' if exists $commands{$text}{text};
    $type = 'regex' if exists $commands{$text}{regex};
    return "found one match: '$text' is '$commands{$text}{$type}'";
  } else {
    return "$i factoids contain '$arguments': $text" unless $i == 0;
    return "No factoids contain '$arguments'";
  }
}

sub change_text {
  plog "Enter change_text\n";
  my ($from, $nick, $host, $arguments) = @_;
  my ($keyword, $delim, $tochange, $changeto, $modifier);

  if(defined $arguments) {
    if($arguments =~ /^(.*?)\s+s(.)/) {
      $keyword = $1; 
      $delim = $2;
    }
    
    if($arguments =~ /$delim(.*?)$delim(.*)$delim(.*)?$/) {
      $tochange = $1; 
      $changeto = $2;
      $modifier  = $3;
    }
  }

  if(not defined $changeto) {
    plog "($from) $nick ($host): improper use of change\n";
    return "/msg $nick Usage: change <keyword> s/<to change>/<change to>/";
  }

  if(not exists $commands{$keyword}) {
    plog "($from) $nick ($host): attempted to change nonexistant '$keyword'\n";
    return "/msg $nick $keyword not found.";
  }

  my $type;
  $type = 'text' if exists $commands{$keyword}{text};
  $type = 'regex' if exists $commands{$keyword}{regex};

  plog "keyword: $keyword, type: $type, tochange: $tochange, changeto: $changeto\n";

  my $ret = eval {
    my $regex = qr/$tochange/;
    if(not $commands{$keyword}{$type} =~ s|$regex|$changeto|) {
      plog "($from) $nick ($host): failed to change '$keyword' 's$delim$tochange$delim$changeto$delim\n";
      return "/msg $nick Change $keyword failed.";
    } else {
      plog "($from) $nick ($host): changed '$keyword' 's/$tochange/$changeto/\n";
      save_commands();
      return "Changed: $keyword is $commands{$keyword}{$type}";
    }
  };
  return "/msg $nick Change $keyword: $@" if $@;
  return $ret;
}

sub remove_text {
  my ($from, $nick, $host, $arguments) = @_;

  if(not defined $arguments) {
    plog "remove_text: invalid usage\n";
    return "/msg $nick Usage: remove <keyword>";
  }

  plog "Attempting to remove [$arguments]\n";
  if(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found.";
  }

  if(exists $commands{$arguments}{command} || exists $commands{$arguments}{module}) {
    plog "$nick ($host) attempted to remove $arguments [not factoid]\n";
    return "/msg $nick $arguments is not a factoid.";
  }

  if(($nick ne $commands{$arguments}{owner}) and (not loggedin($nick, $host))) {
    plog "$nick ($host) attempted to remove $arguments [not owner]\n";
    return "/msg $nick You are not the owner of '$arguments'";
  }

  plog "$nick ($host) removed [$arguments][$commands{$arguments}{text}]\n" if(exists $commands{$arguments}{text});
  plog "$nick ($host) removed [$arguments][$commands{$arguments}{regex}]\n" if(exists $commands{$arguments}{regex});
  delete $commands{$arguments};
  save_commands();
  return "/msg $nick $arguments removed.";
}

sub load_module {
  my ($from, $nick, $host, $arguments) = @_;
  my ($keyword, $module) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if(not defined $arguments) {
    return "/msg $nick Usage: load <command> <module>";
  }

  if(not exists($commands{$keyword})) {
    $commands{$keyword}{module} = $module;
    $commands{$keyword}{enabled} = 1;
    $commands{$keyword}{owner} = $nick;
    $commands{$keyword}{timestamp} = time();
    plog "$nick ($host) loaded $keyword => $module\n";
    save_commands();
    return "/msg $nick Loaded $keyword => $module";
  } else {
    return "/msg $nick There is already a command named $keyword.";
  }
}

sub unload_module {
  my ($from, $nick, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "/msg $nick Usage: unload <module>";
  } elsif(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found.";
  } elsif(not exists $commands{$arguments}{module}) {
    return "/msg $nick $arguments is not a module.";
  } else {
    delete $commands{$arguments};
    save_commands();
    plog "$nick ($host) unloaded module $arguments\n";
    return "/msg $nick $arguments unloaded.";
  } 
}

sub enable_command {
  my ($from, $nick, $host, $arguments) = @_;
  
  if(not defined $arguments) {
    return "/msg $nick Usage: enable <command>";
  } elsif(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found.";
  } else {
    $commands{$arguments}{enabled} = 1;
    save_commands();
    plog "$nick ($host) enabled $arguments\n";
    return "/msg $nick $arguments enabled.";
  }   
}

sub disable_command {
  my ($from, $nick, $host, $arguments) = @_;
 
  if(not defined $arguments) {
    return "/msg $nick Usage: disable <command>";
  } elsif(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found.";
  } else {
    $commands{$arguments}{enabled} = 0;
    save_commands();
    plog "$nick ($host) disabled $arguments\n";
    return "/msg $nick $arguments disabled.";
  }   
}

sub login {
  my ($from, $nick, $host, $arguments) = @_;

  if(loggedin($nick, $host)) {
    return "/msg $nick You are already logged in.";
  }

  if(not exists $admins{$nick}) {
    plog "$nick ($host) attempted to login without account.\n";
    return "/msg $nick You do not have an account.";
  }
 
  if($admins{$nick}{password} eq $arguments && $host =~ /$admins{$nick}{host}/i) {
    $admins{$nick}{login} = 1;
    plog "$nick ($host) logged in.\n";
    return "/msg $nick Welcome $nick, how may I help you?";
  } else {
    plog "$nick ($host) received wrong password.\n";
    return "/msg $nick I don't think so.";
  }
}

sub logout {
  my ($from, $nick, $host, $arguments) = @_;
  return "/msg $nick Uh, you aren't logged in." if(not loggedin($nick, $host));
  delete $admins{$nick}{login};
  plog "$nick ($host) logged out.\n";
  return "/msg $nick Good-bye, $nick.";
}

sub add_admin {
  my ($from, $nick, $host, $arguments) = @_;
  return "/msg $nick Coming soon.";
}

sub del_admin {
  my ($from, $nick, $host, $arguments) = @_;
  return "/msg $nick Coming soon.";
}

my %ignore_list = ();

sub ignore_user {
  my ($from, $nick, $host, $arguments) = @_;
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

  plog "$nick added [$target][$channel] to ignore list for $length seconds\n";
  $ignore_list{$target}{$channel} = gettimeofday + $length;
  return "/msg $nick [$target][$channel] added to ignore list for $length seconds";
}

sub unignore_user {
  my ($from, $nick, $host, $arguments) = @_;
  my ($target, $channel) = split /\s+/, $arguments;

  if(not defined $target) {
    return "/msg $nick Usage: unignore host [channel]";
  }

  if(not defined $channel) {
    $channel = ".*";
  }
  
  if(not exists $ignore_list{$target}{$channel}) {
    plog "$nick attempt to remove nonexistent [$target][$channel] from ignore list\n";
    return "/msg $nick [$target][$channel] not found in ignore list (use '!ignore list' to list ignores";
  }
  
  delete $ignore_list{$target}{$channel};
  plog "$nick removed [$target][$channel] from ignore list\n";
  return "/msg $nick [$target][$channel] unignored";
}

sub check_ignore {
  my ($nick, $host, $channel) = @_;

  my $hostmask = "$nick" . '@' . "$host";

  foreach my $ignored (keys %ignore_list) {
    foreach my $ignored_channel (keys %{ $ignore_list{$ignored} }) {
      if(($channel =~ /$ignored_channel/i) && ($hostmask =~ /$ignored/i)) {
        plog "$nick ($host) message ignored in channel $channel (matches [$ignored] host and [$ignored_channel] channel)\n";
        return 1;
      }
    }
  }
}

sub join_channel {
  my ($from, $nick, $host, $arguments) = @_;

  plog "$nick ($host) made me join $arguments\n";
  $conn->join($arguments);
  return "/msg $nick Joined $arguments";
}

sub part_channel {
  my ($from, $nick, $host, $arguments) = @_;

  plog "$nick ($host) made me part $arguments\n";
  $conn->part($arguments);
  return "/msg $nick Parted $arguments";
}

sub ack_die {
  my ($from, $nick, $host, $arguments) = @_;
  plog "$nick ($host) made me exit.\n";
  save_commands();
  $conn->privmsg($from, "Good-bye.");
  $conn->quit("Departure requested.");
  exit 0;
}

my %quieted_nicks = ();
my %unban_timeout = ();

sub quiet {
  my ($from, $nick, $host, $arguments) = @_;
  my ($target, $length) = split(/\s+/, $arguments);

  if(not $from =~ /^#/) { #not a channel
    return "/msg $nick This command must be used in the channel.";
  }

  if(not defined $target) {
    return "/msg $nick Usage: quiet nick [timeout seconds (default: 3600 or 1 hour)]"; 
  }

  if(not defined $length) {
    $length = 60 * 60; # one hour
  }
  quiet_nick_timed($target, $from, $length);    
  $conn->privmsg($target, "$nick has quieted you for $length seconds.");
}

sub unquiet {
  my ($from, $nick, $host, $arguments) = @_;

  if(not $from =~ /^#/) { #not a channel
    return "/msg $nick This command must be used in the channel.";
  }

  if(not defined $arguments) {
    return "/msg $nick Usage: unquiet nick";
  }

  unquiet_nick($arguments, $from);
  delete $quieted_nicks{$arguments};
  $conn->privmsg($arguments, "$nick has allowed you to speak again.");
}

my @op_commands = ();
my %is_opped = ();

sub quiet_nick {
  my ($nick, $channel) = @_;
  unshift @op_commands, "mode $channel +q $nick!*@*";
  gain_ops($channel);
}

sub unquiet_nick {
  my ($nick, $channel) = @_;
  unshift @op_commands, "mode $channel -q $nick!*@*";
  gain_ops($channel);
}

#need to refactor ban_user() and unban_user() - mostly duplicate code
sub ban_user {
  my ($from, $nick, $host, $arguments) = @_;

  if(not $from =~ /^#/) { #not a channel
    if($arguments =~ /^(#.*?) (.*?) (.*)$/) {
      $conn->privmsg("ChanServ", "AUTOREM $1 ADD $2 $3");
      unshift @op_commands, "kick $1 $2 Banned";
      gain_ops($1);
      plog "$nick ($host) AUTOREM $2 ($3)\n";
      return "/msg $nick $2 added to auto-remove";
    } else {
      plog "$nick ($host): bad format for ban in msg\n";
      return "/msg $nick Usage (in msg mode): !ban <channel> <hostmask> <reason>";  
    }
  } else { #in a channel
    if($arguments =~ /^(.*?) (.*)$/) {
      $conn->privmsg("ChanServ", "AUTOREM $from ADD $1 $2");
      plog "AUTOREM [$from] ADD [$1] [$2]\n";
      plog "kick [$from] [$1] Banned\n";
      unshift @op_commands, "kick $from $1 Banned";
      gain_ops($from);
      plog "$nick ($from) AUTOREM $1 ($2)\n";
      return "/msg $nick $1 added to auto-remove";
    } else {
      plog "$nick ($host): bad format for ban in channel\n";      
      return "/msg $nick Usage (in channel mode): !ban <hostmask> <reason>";
    }
  }
}

sub unban_user {
  my ($from, $nick, $host, $arguments) = @_;

  if(not $from =~ /^#/) { #not a channel
    if($arguments =~ /^(#.*?) (.*)$/) {
      $conn->privmsg("ChanServ", "AUTOREM $1 DEL $2");
      unshift @op_commands, "mode $1 -b $2"; 
      gain_ops($1);
      delete $unban_timeout{$2};
      plog "$nick ($host) AUTOREM DEL $2 ($3)\n";
      return "/msg $nick $2 removed from auto-remove";
    } else {
      plog "$nick ($host): bad format for unban in msg\n";
      return "/msg $nick Usage (in msg mode): !unban <channel> <hostmask>";  
    }
  } else { #in a channel
    $conn->privmsg("ChanServ", "AUTOREM $from DEL $arguments");
    unshift @op_commands, "mode $from -b $arguments"; 
    gain_ops($from);
    delete $unban_timeout{$arguments};
    plog "$nick ($host) AUTOREM DEL $arguments\n";
    return "/msg $nick $arguments removed from auto-remove";
  }
}

sub kick_nick {
  my ($from, $nick, $host, $arguments) = @_;

  if(not $from =~ /^#/) {
    plog "$nick ($host) attempted to /msg kick\n";
    return "/msg $nick Kick must be used in the channel.";
  }
  if(not $arguments =~ /(.*?) (.*)/) {
    plog "$nick ($host): invalid arguments to kick\n";
    return "/msg $nick Usage: !kick <nick> <reason>";
  }
  unshift @op_commands, "kick $from $1 $2";
  gain_ops($from);
}

sub gain_ops {
  my $channel = shift;
  
  if(not exists $is_opped{$channel}) {
    $conn->privmsg("chanserv", "op $channel");
  } else {
    perform_op_commands();
  }
}

sub lose_ops {
  my $channel = shift;
  $conn->privmsg("chanserv", "op $channel -$botnick");
  if(exists $is_opped{$channel}) {
    $is_opped{$channel}{timeout} = gettimeofday + 60; # try again in 1 minute if failed
  }
}

sub perform_op_commands {
  plog "Performing op commands...\n";
  foreach my $command (@op_commands) {
    if($command =~ /^mode (.*?) (.*)/i) {
      $conn->mode($1, $2);
      plog "  executing mode $1 $2\n";
    } elsif($command =~ /^kick (.*?) (.*?) (.*)/i) {
      $conn->kick($1, $2, $3);
      plog "  executing kick on $1 $2 $3\n";
    }
    shift(@op_commands);
  }
  plog "Done.\n";
}

# Bot related subroutines
#################################################

sub plog {
  my $text = shift;
  my $time = localtime;
  print "$time :: $text";
}

sub execute_module {
  my ($from, $nick, $tonick, $host, $keyword, $arguments) = @_;
  my $text;
  
  my $pid = fork;
  if(not defined $pid) {
    plog "Could not fork: $!\n";
    return "/me groans loudly.";
  }

  if($pid == 0) {
    $child = 1; # set to be killed after returning
    if(defined $arguments) {
      plog "($from): $nick ($host): Executing module $commands{$keyword}{module} $arguments\n";
      $arguments = quotemeta($arguments);
      $arguments =~ s/\\\s+/ /;

      if(defined $tonick) {
        plog "($from): $nick ($host) sent to $tonick\n";
        $text = `$module_dir/$commands{$keyword}{module} $arguments`;
        my $fromnick = loggedin($nick, $host) ? "" : " ($nick)";
        #return "/msg $tonick $text$fromnick"; # send private message to user
        if(defined $text && length $text > 0) {
          return "$tonick: $text";
        } else {
          return "";
        }
      } else {
        return `$module_dir/$commands{$keyword}{module} $arguments`;
      }
    } else {
      plog "($from): $nick ($host): Executing module $commands{$keyword}{module}\n";
      if(defined $tonick) {
        plog "($from): $nick ($host) sent to $tonick\n";
        $text = `$module_dir/$commands{$keyword}{module}`;
        my $fromnick = loggedin($nick, $host) ? "" : " ($nick)";
        #return "/msg $tonick $text$fromnick"; # send private message to user
        if(defined $text && length $text > 0) {
          return "$tonick: $text";
        } else {
          return "";
        }
      } else {
        # XXX extract $tonick from end of $arguments
        return `$module_dir/$commands{$keyword}{module}`;
      }
    } #end if($arguments)
    return "/me moans loudly."; # er, didn't execute the module?
  } #end if($pid == 0)
  plog "returning blank\n";
  return "";
}

sub interpret_command {  
  my ($from, $nick, $host, $count, $command) = @_;
  my ($keyword, $arguments, $tonick);
  my $text;

  plog "Enter interpret_command\n";
  plog "[$from][$nick][$host][$count]command[$command]\n";

  return "Too many levels of recursion, aborted." if(++$count > 5);

  if(not defined $from || not defined $nick || not defined $host ||
     not defined $command) {
    plog "Error 1, bad parameters to interpret_command\n";
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
  
  $arguments =~ s/\bme\b/\$nick/gi;
  $arguments =~ s/\/\$nick/\/me/gi;

  if($arguments =~ m/\b(your|him|her|its|it|them|their)(self|selves)\b/i) {
    return "Why would I want to do that to myself?";
  }
  
  plog "keyword: [$keyword], arguments: [$arguments], tonick: [$tonick]\n";

  if(not defined $keyword) {
    plog "Error 2, no keyword\n";
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
      plog "[$from] $nick ($host) aliased to: [$command]\n";

      $commands{$keyword}{ref_count}++;
      $commands{$keyword}{ref_user} = $nick;

      return interpret_command($from, $nick, $host, $count, $command);
    }
  }

  plog "Checking internal commands\n";
  
  # First, we check internal commands
  foreach $command (keys %internal_commands) {
    if($keyword =~ /^$command$/i) {
      $keyword = lc $keyword;
      if($internal_commands{$keyword}{level} > 0) {
        return "/msg $nick You must login to use this command." 
          if not loggedin($nick, $host);
        return "/msg $nick Your access level of $admins{$nick}{level} is not sufficent to use this command."
          if $admins{$nick}{level} < $internal_commands{$keyword}{level};
      }
      plog "($from): $nick ($host) Executing internal command: [$from][$nick][$host][$keyword][$arguments]\n";
      return $internal_commands{$keyword}{sub}($from, $nick, $host, $arguments);
    }
  }

  plog "Checking bot commands\n";

  # Then, we check bot commands
  foreach $command (keys %commands) {
    if(lc $keyword =~ /^\Q$command\E$/i) {
      
      plog "=======================\n";
      plog "[$keyword] == [$command]\n";
      
      if(exists $commands{$keyword} && $commands{$keyword}{enabled} == 0) {
        plog "$keyword disabled.\n";
        return "$keyword is currently disabled.";
      } elsif(exists $commands{$keyword} && exists $commands{$keyword}{module}) {
        plog "Found module\n";
        $commands{$keyword}{ref_count}++;
        $commands{$keyword}{ref_user} = $nick;

        $text = execute_module($from, $nick, $tonick, $host, $keyword, $arguments);
      }

      # Now we check to see if it's a factoid 
      elsif(exists $commands{$keyword} && exists $commands{$keyword}{text}) {
        plog "Found factoid\n";

        # Don't allow user-custom /msg factoids, unless factoid triggered by admin
        if(($commands{$keyword}{text} =~ m/^\/msg/i) and (not loggedin($nick, $host))) {
          plog "/MSG FACTOID NOT ALLOWED!\n";
          return "You must login to use this command."
        }
        
        $commands{$keyword}{ref_count}++;
        $commands{$keyword}{ref_user} = $nick;
        plog "($from): $nick ($host): $keyword: Displaying text \"$commands{$keyword}{text}\"\n";
        if(defined $tonick) { # !tell foo about bar
          plog "($from): $nick ($host) sent to $tonick\n";
          my $fromnick = loggedin($nick, $host) ? "" : " ($nick)";
          # $text = "/msg $tonick $commands{$keyword}{text}$fromnick";
          $text = "$tonick: $keyword is $commands{$keyword}{text}";
        } else {
          $text = $commands{$keyword}{text};
        }
        plog "text set to [$text]\n";
        if(defined $arguments) {
          plog "got arguments: [$arguments]\n";
          
          # XXX - extract and remove $tonick from end of $arguments
          if(not $text =~ s/\$args/$arguments/gi) {
            plog "factoid doesn't take argument, checking ...\n";
            # factoid doesn't take an argument
            if($arguments =~ /^[^ ]{1,20}$/) {
              # might be a nick
              plog "could be nick\n";
              if($text =~ /^\/.+? /) {
                $text =~ s/^(\/.+?) /$1 $arguments: /;
              } else {
                $text =~ s/^/\/say $arguments: $keyword is / unless (defined $tonick);
              }                  
            } else {
              if($text =~ /^\/.+? /) {
                $text =~ s/^(\/.+?) /$1 /;
              } else {
                $text =~ s/^/\/say $keyword is / unless (defined $tonick);
              }                  
            }
            plog "unknown1: [$text]\n";
          }
          plog "replaced \$args: [$text]\n";
        } else {
          # no arguments supplied
          # plog "No arguments supplised\n";
          $text =~ s/\$args/$nick/gi;
          # plog "[$text]\n";
        }
        $text =~ s/\$nick/$nick/g;
        # plog "subbed nick: [$text]\n";
        while($text =~ /[^\\]\$([^\s!+.$\/\\,;=&]+)/g) { 
          my $var = $1;
          #plog "adlib: got [$var]\n";
          #plog "adlib: parsing variable [\$$var]\n";
          if(exists $commands{$var} && exists $commands{$var}{text}) {
            my $change = $commands{$var}{text};
            my @list = split(/\s|(".*?")/, $change);
            my @mylist;
            #plog "adlib: list [". join(':', @mylist) ."]\n";
            for(my $i = 0; $i <= $#list; $i++) {
              #plog "adlib: pushing $i $list[$i]\n";
              push @mylist, $list[$i] if $list[$i];
            }
            my $line = int(rand($#mylist + 1));
            $mylist[$line] =~ s/"//g;
            $text =~ s/\$$var/$mylist[$line]/;
            #plog "adlib: found: change: $text\n";
          } else {
            $text =~ s/\$$var/$var/g;
            #plog "adlib: not found: change: $text\n";
          }
        }
        $text =~ s/\\\$/\$/g;
        # plog "finally... [$text]\n";
        if($text =~ s/^\/say\s+//i || $text =~ /^\/me\s+/i
          || $text =~ /^\/msg\s+/i) {
          # plog "ret1\n";
          return $text;
        } else {
          # plog "ret2\n";
          return "$keyword is $text";
        }
        plog "unknown3: [$text]\n";
      } else {
        plog "($from): $nick ($host): Unknown command type: $command\n"; 
        return "/me blinks.";
      }
      plog "unknown4: [$text]\n";
    } # else no match
  } # end foreach
  
  # plog "attemping regex [$text]\n";

  # Otherwise, the command was not found.
  # Lets try regexp factoids ...
  my $string = "$keyword $arguments";
  my $found = 0;
  
  foreach my $command (sort keys %commands) {
    if(exists $commands{$command}{regex}) {
      eval {
        my $regex = qr/$command/i;
        # plog "testing $string =~ $regex\n";
        if($string =~ $regex) {
          plog "[$string] matches [$command][$regex] - calling [" . $commands{$command}{regex}. "$']\n";
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
          $text = interpret_command($from, $nick, $host, $count, "$cmd");
          $found = 1;
        }
      };
      if($@) {
        plog "Regex fail: $@\n";
        return "/msg $nick Fail.";
      }
      last if $found;
    }
  }
  
  plog "[$keyword] not found.\n" if $text ne "";
  return "$text";
}

sub load_channels {
  open(FILE, "< $channels_file") or die "Couldn't open $channels_file: $!\n";
  my @contents = <FILE>;
  close(FILE);

  plog "Loading channels from $channels_file ...\n";

  my $i = 0;
  foreach my $line (@contents) {
    $i++;
    chomp $line;
    my ($channel, $enabled, $is_op, $showall) = split(/\s+/, $line);
    if(not defined $channel || not defined $is_op || not defined $enabled) {
      die "Syntax error around line $i of $channels_file\n";
    }
    if(defined $channels{$channel}) {
      die "Duplicate channel $channel found in $channels_file around line $i\n";
    }
    $channels{$channel}{enabled} = $enabled;
    $channels{$channel}{is_op} = $is_op;
    $channels{$channel}{showall} = $showall;
    plog "  Adding channel $channel ...\n";
  }
  plog "Done.\n";
}

sub save_channels {
  open(FILE, "> $channels_file") or die "Couldn't open $channels_file: $!\n";
  foreach my $channel (keys %channels) {
    print FILE "$channel $channels{$channel}{enabled} $channels{$channel}{is_op} $channels{$channel}{showall}\n";
  }
  close(FILE);
}

sub load_commands {
  plog "Loading commands from $commands_file ...\n";
  
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
#    plog "  Adding command $command ($type): $owner, $timestamp...\n";
  }
  plog "  $i commands loaded.\n";
  plog "Done.\n";
}

sub save_commands {
  open(FILE, "> $commands_file") or die "Couldn't open $commands_file: $!\n";

  foreach my $command (sort keys %commands) {
    next if $command eq "version";
    if(defined $commands{$command}{module} || defined $commands{$command}{text} || defined $commands{$command}{regex}) {
      print FILE "$command ";
    } else {
      plog "save_commands: unknown command type $command\n";
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
      plog "save_commands: skipping unknown command type for $command\n";
    }
  }
  close(FILE);
  system("cp $commands_file /home/msmud/pbot2/commands.bak");
}

sub load_admins {
}

sub save_admins {
}

sub check_flood {
  my ($nick, $host, $channel, $max, $mode, $msg) = @_;
  my $now = gettimeofday;

  # plog "check flood $nick $host [$channel] $max $mode $msg\n";

  return if $nick eq $botnick;

  if(exists $flood_watch{$nick}) {
    # plog "nick exists\n";

    if(not exists $flood_watch{$nick}{$channel}) {
      # plog "adding new channel for existing nick\n";
      $flood_watch{$nick}{$channel}{offenses} = 0;
      $flood_watch{$nick}{$channel}{messages} = [];
    }

    # plog "appending new message\n";
    push(@{ $flood_watch{$nick}{$channel}{messages} }, { timestamp => $now, msg => $msg, mode => $mode });

    my $length = $#{ $flood_watch{$nick}{$channel}{messages} } + 1;

    # plog "length: $length, max nick messages: $MAX_NICK_MESSAGES\n";

    if($length >= $MAX_NICK_MESSAGES) {
      my %msg = %{ shift(@{ $flood_watch{$nick}{$channel}{messages} }) };
      #plog "shifting message off top: $msg{msg}, $msg{timestamp}\n";
      $length--;
    }

    return if $channels{$channel}{is_op} == 0;

    if($length >= $max) {
      #plog "More than $max messages spoken, comparing time differences\n";
      my %msg = %{ @{ $flood_watch{$nick}{$channel}{messages} }[$length - $max] };
      my %last = %{ @{ $flood_watch{$nick}{$channel}{messages} }[$length - 1] };

      #plog "Comparing $last{timestamp} against $msg{timestamp}\n";

      if($last{timestamp} - $msg{timestamp} <= 10 && not loggedin($nick, $host)) {
        $flood_watch{$nick}{$channel}{offenses}++;
        my $length = $flood_watch{$nick}{$channel}{offenses} * $flood_watch{$nick}{$channel}{offenses} * 30;
        if($channel =~ /^#/) { #channel flood (opposed to private message or otherwise)
          if($mode == $FLOOD_CHAT) {
            quiet_nick_timed($nick, $channel, $length);
            $conn->privmsg($nick, "You have been quieted due to flooding.  Please use a web paste service such as http://codepad.org for lengthy pastes.  You will be allowed to speak again in $length seconds.");
            plog "$nick $channel flood offense $flood_watch{$nick}{$channel}{offenses} earned $length second quiet\n";
          }
        } else { # private message flood
          plog "$nick msg flood offense $flood_watch{$nick}{$channel}{offenses} earned $length second ignore\n";
          ignore_user("", "floodcontrol", "", "$nick" . '@' . "$host $channel $length");
        }
      }
    }
  } else {
    # plog "brand new nick addition\n";
    # new addition
    $flood_watch{$nick}{$channel}{offenses}  = 0;
    $flood_watch{$nick}{$channel}{messages} = [];
    push(@{ $flood_watch{$nick}{$channel}{messages} }, { timestamp => $now, msg => $msg, mode => $mode });
  }
}

sub quotegrab {
  my ($from, $nick, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "Usage: !grab <nick> [history] -- where [history] is an optional argument that is an integer number of recent messages; e.g., to grab the 3rd most recent message for nick, use !grab nick 3";
  }

  my ($grab_nick, $grab_history) = split(/\s+/, $arguments, 2);

  $grab_history = 1 if not defined $grab_history;

  if($grab_history < 1 || $grab_history > $MAX_NICK_MESSAGES) {
    return "/msg $nick Please choose a history between 1 and $MAX_NICK_MESSAGES";
  }

  if(not exists $flood_watch{$grab_nick}) {
    return "No message history for $grab_nick.";
  }

  if(not exists $flood_watch{$grab_nick}{$from}) {
    return "No message history for $grab_nick in $from.";
  }
  
  my @messages = @{ $flood_watch{$grab_nick}{$from}{messages} };

  $grab_history--;
  
  if($grab_history > $#messages) {
    return "$grab_nick has only " . ($#messages + 1) . " messages in the history.";
  }

  $grab_history = $#messages - $grab_history;

  plog "$nick ($from) grabbed <$grab_nick> $messages[$grab_history]->{msg}\n";

  my $quotegrab = {};
  $quotegrab->{nick} = $grab_nick;
  $quotegrab->{channel} = $from;
  $quotegrab->{timestamp} = $messages[$grab_history]->{timestamp};
  $quotegrab->{grabbed_by} = $nick;
  $quotegrab->{text} = $messages[$grab_history]->{msg};
  push @quotegrabs, $quotegrab;
  save_quotegrabs();
  my $msg = $messages[$grab_history]->{msg};
  $msg =~ s/(.{8}).*/$1.../;
  return "Quote grabbed: " . ($#quotegrabs + 1) . ": <$grab_nick> $msg";
}

sub show_quotegrab {
  my ($from, $nick, $host, $arguments) = @_;

  if($arguments < 1 || $arguments > $#quotegrabs + 1) {
    return "/msg $nick Valid range for !getq is 1 - " . ($#quotegrabs + 1);
  }

  my $quotegrab = $quotegrabs[$arguments - 1];
  return "$arguments: <$quotegrab->{nick}> $quotegrab->{text}";
}

sub show_random_quotegrab {
  my ($from, $nick, $host, $arguments) = @_;
  my @quotes = ();
  my $nick_search = ".*";
  my $channel_search = $from;
  my $channel_search_quoted = quotemeta($channel_search);

  if(defined $arguments) {
    ($nick_search, $channel_search) = split(/\s+/, $arguments, 2);
    if(not defined $channel_search) {
      $channel_search = $from;
      $channel_search_quoted = quotemeta($channel_search);
    }
  } 

  eval {
    for(my $i = 0; $i <= $#quotegrabs; $i++) {
      my $hash = $quotegrabs[$i];
      if($hash->{channel} =~ /$channel_search_quoted/i && $hash->{nick} =~ /$nick_search/) {
        $hash->{id} = $i + 1;
        push @quotes, $hash;
      }
    }
  };

  if($@) {
    plog "Error in show_random_quotegrab parameters: $@\n";
    return "/msg $nick Error: $@"
  }
  
  if($#quotes < 0) {
    if($nick_search eq ".*") {
      return "No quotes grabbed for $channel_search yet.  Use !grab to grab a quote.";
    } else {
      return "No quotes grabbed for $nick_search in $channel_search yet.  Use !grab to grab a quote.";
    }
  }

  my $quotegrab = $quotes[int rand($#quotes + 1)];
  return "$quotegrab->{id}: <$quotegrab->{nick}> $quotegrab->{text}";
}

sub load_quotegrabs {
  plog "Loading quotegrabs from $quotegrabs_file ...\n";
  
  open(FILE, "< $quotegrabs_file") or die "Couldn't open $quotegrabs_file: $!\n";
  my @contents = <FILE>;
  close(FILE);

  my $i = 0;
  foreach my $line (@contents) {
    chomp $line;
    $i++;
    my ($nick, $channel, $timestamp, $grabbed_by, $text) = split(/\s+/, $line, 5);
    if(not defined $nick || not defined $channel || not defined $timestamp
       || not defined $grabbed_by || not defined $text) {
      die "Syntax error around line $i of $quotegrabs_file\n";
    }

    my $quotegrab = {};
    $quotegrab->{nick} = $nick;
    $quotegrab->{channel} = $channel;
    $quotegrab->{timestamp} = $timestamp;
    $quotegrab->{grabbed_by} = $grabbed_by;
    $quotegrab->{text} = $text;
    push @quotegrabs, $quotegrab;
  }
  plog "  $i quotegrabs loaded.\n";
  plog "Done.\n";
}

sub save_quotegrabs {
  open(FILE, "> $quotegrabs_file") or die "Couldn't open $quotegrabs_file: $!\n";

  for(my $i = 0; $i <= $#quotegrabs; $i++) {
    my $quotegrab = $quotegrabs[$i];
    next if $quotegrab->{timestamp} == 0;
    print FILE "$quotegrab->{nick} $quotegrab->{channel} $quotegrab->{timestamp} $quotegrab->{grabbed_by} $quotegrab->{text}\n";
  }

  close(FILE);
  system("cp $quotegrabs_file $quotegrabs_file.bak");
}

sub quiet_nick_timed {
  my ($nick, $channel, $length) = @_;

  quiet_nick($nick, $channel);
  $quieted_nicks{$nick}{time} = gettimeofday + $length;
  $quieted_nicks{$nick}{channel} = $channel;
}

sub check_quieted_timeouts {
  my $now = gettimeofday;

  foreach my $nick (keys %quieted_nicks) {
    if($quieted_nicks{$nick}{time} < $now) {
      plog "Unquieting $nick\n";
      unquiet_nick($nick, $quieted_nicks{$nick}{channel});
      delete $quieted_nicks{$nick};
      $conn->privmsg($nick, "You may speak again.");
    } else {
      #my $timediff = $quieted_nicks{$nick}{time} - $now;
      #plog "quiet: $nick has $timediff seconds remaining\n"
    }
  }
}

sub check_ignore_timeouts {
  my $now = gettimeofday;

  foreach my $host (keys %ignore_list) {
    foreach my $channel (keys %{ $ignore_list{$host} }) {
      next if($ignore_list{$host}{$channel} == -1); #permanent ignore

      if($ignore_list{$host}{$channel} < $now) {
        unignore_user("", "floodcontrol", "", "$host $channel");
        if($host eq ".*") {
          $conn->me($channel, "awakens.");
        }
      } else {
        #my $timediff = $ignore_list{$host}{$channel} - $now;
        #plog "ignore: $host has $timediff seconds remaining\n"
      }
    }
  }
}

sub check_opped_timeout {
  my $now = gettimeofday;

  foreach my $channel (keys %is_opped) {
    if($is_opped{$channel}{timeout} < $now) {
      lose_ops($channel);
    } else {
      # my $timediff = $is_opped{$channel}{timeout} - $now;
      # plog "deop $channel in $timediff seconds\n";
    }
  }
}

sub check_unban_timeouts {
  my $now = gettimeofday;

  foreach my $ban (keys %unban_timeout) {
    if($unban_timeout{$ban}{timeout} < $now) {
      unshift @op_commands, "mode $unban_timeout{$ban}{channel} -b $ban";
      gain_ops($unban_timeout{$ban}{channel});
      delete $unban_timeout{$ban};
    } else {
      #my $timediff = $unban_timeout{$ban}{timeout} - $now;
      #plog "$unban_timeout{$ban}{channel}: unban $ban in $timediff seconds\n";
    }
  }
}

sub check_export_timeout {
  my $now = gettimeofday;
  if($now > $export_factoids_time) {
    export_factoids;
    $export_factoids_time = $now + $export_factoids_timeout;
  }
}


BEGIN {
  my $last_run = gettimeofday;
  
  sub check_message_history_timeout {
    my $now = gettimeofday;

    if($now - $last_run < 60 * 60) {
      return;
    } else {
      plog "One hour has elapsed -- running check_message_history_timeout\n";
    }
    
    $last_run = $now;
    
    foreach my $nick (keys %flood_watch) {
      foreach my $channel (keys %{ $flood_watch{$nick} })
      {
        plog "Checking [$nick][$channel]\n";
        my $length = $#{ $flood_watch{$nick}{$channel}{messages} } + 1;
        my %last = %{ @{ $flood_watch{$nick}{$channel}{messages} }[$length - 1] };

        if($now - $last{timestamp} >= 60 * 60 * 24) {
          plog "$nick in $channel hasn't spoken in 24 hours, removing message history.\n";
          delete $flood_watch{$nick}{$channel};
        }
      }
    }
  }
}
sub sig_alarm_handler {
  # check timeouts
  check_quieted_timeouts;
  check_ignore_timeouts;
  check_opped_timeout;
  check_unban_timeouts;
  check_export_timeout;
  check_message_history_timeout;
  alarm 10;
}

# IRC related subroutines
#################################################

sub on_connect {
  my $conn = shift;
  $conn->privmsg("nickserv", "identify $identify_password");
  $conn->{connected} = 1;
}

sub on_disconnect {
  my ($self, $event) = @_;
  my $text = "Disconnected, attempting to reconnect...\n";
  plog $text;
  $self->connect();
  if(not $self->connected) {
    sleep(5);
    on_disconnect($self, $event) 
  }
}

sub on_init {
  my ($self, $event) = @_;
  my (@args) = ($event->args);
  shift (@args);
  plog "*** @args\n";
}

my $last_timestamp = gettimeofday;
my $flood_msg = 0;

sub on_public {
  my ($conn, $event) = @_;
  my $mynick = $conn->nick; 
  my $nick = $event->nick;
  my $host = $event->host;
  my $text = $event->{args}[0];
  my $from = $event->{to}[0];
  my ($command, $args, $result);
  my $has_url = undef;

  plog "------------------------------------------------------\n($from): $nick ($host): $text\n"
    if((exists $channels{$from} && $channels{$from}{showall} == 1) || not $from =~ /^#/);

  check_flood($nick, $host, $from, $MAX_FLOOD_MESSAGES, $FLOOD_CHAT, $text);

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
    if(defined $command && $command !~ /^login/i) {
      plog "ignored text: [$nick][$host][$from][$text]\n" and return if(check_ignore($nick, $host, $from) && not loggedin($nick, $host)); # ignored host
    }

    my $now = gettimeofday;
    
    if($from =~ /^#/) {
      $flood_msg++;
      plog "flood_msg: $flood_msg\n";
    }

    if($flood_msg > 3) {
      plog "flood_msg exceeded! [$flood_msg]\n";
      ignore_user("", "floodcontrol", "", ".* $from 300");
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
        plog "flood_msg reset: (was $flood_msg)\n";
        $flood_msg = 0;
      }
    }

    if(not defined $has_url) {
      $result = interpret_command($from, $nick, $host, 1, $command);
    } else {
      $result = execute_module($from, $nick, undef, $host, "title", "$nick http://$has_url");
    }

    if(defined $result && length $result > 0) {
      my $len = length $result;
      if($len > $max_msg_len) {
        if(($len - $max_msg_len) > 10) {
          plog "Message truncated.\n";
          $result = substr($result, 0, $max_msg_len);
          substr($result, $max_msg_len) = "... (" . ($len - $max_msg_len) . " more characters)";
        }
      }
      
      if($result =~ s/^\/me\s+//i) {
        $conn->me($from, $result);
      } elsif($result =~ s/^\/msg\s+([^\s]+)\s+//i) {
        my $to = $1;
        if($to =~ /.*serv$/i) {
          plog "Possible HACK ATTEMPT /msg *serv: [$nick] [$host] [$command] [$result]\n";
        }
        elsif($result =~ s/^\/me\s+//i) {
          $conn->me($to, $result);
        } else {
          $result =~ s/^\/say\s+//i;
          $conn->privmsg($to, $result);
        }
      } else {
        $conn->privmsg($from, $result);
      }
    }
    exit if($child != 0); # if this process is a child, it must die now
  }
}

sub on_msg {
  my ($conn, $event) = @_;
  my ($nick, $host) = ($event->nick, $event->host);
  my $text = $event->{args}[0];

  $text =~ s/^!?(.*)/\!$1/;
  $event->{to}[0]   = $nick;
  $event->{args}[0] = $text;
  on_public($conn, $event);
}

sub on_action {
  my ($conn, $event) = @_;
  
  on_public($conn, $event);
}

sub on_mode {
  my ($conn, $event) = @_;
  my ($nick, $host) = ($event->nick, $event->host);
  my $mode = $event->{args}[0];
  my $target = $event->{args}[1];
  my $from = $event->{to}[0];

  plog "Got mode:  nick: $nick, host: $host, mode: $mode, target: $target, from: $from\n";

  if($target eq $botnick) {
    if($mode eq "+o") {
      plog "$nick opped me in $from\n";
      if(exists $is_opped{$from}) {
        plog "warning: erm, I was already opped?\n";
      }
      $is_opped{$from}{timeout} = gettimeofday + 300; # 5 minutes
      perform_op_commands();
    } elsif($mode eq "-o") {
      plog "$nick removed my ops in $from\n";
      if(not exists $is_opped{$from}) {
        plog "warning: erm, I wasn't opped?\n";
      }
      delete $is_opped{$from};
    }    
  } else {  # bot not targeted
    if($mode eq "+b") {
      if($nick eq "ChanServ") {
        $unban_timeout{$target}{timeout} = gettimeofday + 3600 * 2; # 2 hours
        $unban_timeout{$target}{channel} = $from;
      }
    } elsif($mode eq "+e" && $from eq $botnick) {
      foreach my $chan (keys %channels) {
        if($channels{$chan}{enabled} != 0) {
          plog "Joining channel:  $chan\n";
          $conn->join($chan);
        }
      }
    }
  }
}

sub on_join {
  my ($conn, $event) = @_;
  my ($nick, $host, $channel) = ($event->nick, $event->host, $event->to);

  #plog "$nick ($host) joined $channel\n";
  #check_flood($nick, $host, $channel, 3, $FLOOD_JOIN);
}

sub on_departure {
  my ($conn, $event) = @_;
  my ($nick, $host, $channel) = ($event->nick, $event->host, $event->to);

  #check_flood($nick, $host, $channel, 3, $FLOOD_JOIN);

  if(exists $admins{$nick} && exists $admins{$nick}{login}) { 
    plog "Whoops, $nick disconnected while still logged in.\n";
    plog "Logged out $nick.\n";
    delete $admins{$nick}{login};
  }
}
