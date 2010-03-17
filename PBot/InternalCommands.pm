package PBot::InternalCommands;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;

  @ISA = qw(Exporter);
  @EXPORT_OK = qw(%flood_watch $logger %commands $conn %admins $botnick %internal_commands);
}

use vars @EXPORT_OK;

*flood_watch     = \%PBot::AntiFlood::flood_watch;
*logger          = \$PBot::PBot::logger;
*commands        = \%PBot::FactoidStuff::commands;
*conn            = \$PBot::PBot::conn;
*admins          = \%PBot::BotAdminStuff::admins;
*botnick         = \$PBot::PBot::botnick;

use Time::HiRes qw(gettimeofday);

#internal commands
# TODO: Move commands to respective module files
%internal_commands = ( 
  alias     => { sub => \&alias,                 level=> 0  },
  add       => { sub => \&add_text,              level=> 0  },
  regex     => { sub => \&add_regex,             level=> 0  },
  learn     => { sub => \&add_text,              level=> 0  },
  grab      => { sub => \&PBot::Quotegrabs::quotegrab,             level=> 0  },
  delq      => { sub => \&PBot::Quotegrabs::delete_quotegrab,      level=> 40 },
  getq      => { sub => \&PBot::Quotegrabs::show_quotegrab,        level=> 0  },
  rq        => { sub => \&PBot::Quotegrabs::show_random_quotegrab, level=> 0  },
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
  quiet     => { sub => \&PBot::OperatorStuff::quiet,                 level=> 10 },
  unquiet   => { sub => \&PBot::OperatorStuff::unquiet,               level=> 10 },
  ignore    => { sub => \&PBot::IgnoreList::ignore_user,           level=> 10 }, 
  unignore  => { sub => \&PBot::IgnoreList::unignore_user,         level=> 10 },
  ban       => { sub => \&PBot::OperatorStuff::ban_user,              level=> 10 }, 
  unban     => { sub => \&PBot::OperatorStuff::unban_user,            level=> 10 }, 
  kick      => { sub => \&PBot::OperatorStuff::kick_nick,             level=> 10 },
  login     => { sub => \&login,                 level=> 0  },
  logout    => { sub => \&logout,                level=> 0  },
  join      => { sub => \&join_channel,          level=> 50 },
  part      => { sub => \&part_channel,          level=> 50 },
  addadmin  => { sub => \&add_admin,             level=> 40 },
  deladmin  => { sub => \&del_admin,             level=> 40 }, 
  die       => { sub => \&ack_die,               level=> 50 } 
);


sub list {
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $text;
  
  if(not defined $arguments) {
    return "/msg $nick Usage: list <modules|factoids|commands|admins>";
  }

  if($arguments =~/^messages\s+(.*?)\s+(.*)$/) {
    my $nick_search = $1;
    my $channel = $2;

    if(not exists $flood_watch{$nick_search}) {
      return "/msg $nick No messages for $nick_search yet.";
    }

    if(not exists $flood_watch{$nick_search}{$channel}) {
      return "/msg $nick No messages for $nick_search in $channel yet.";
    }

    my @messages = @{ $flood_watch{$nick_search}{$channel}{messages} };

    for(my $i = 0; $i <= $#messages; $i++) {
      $conn->privmsg($nick, "" . ($i + 1) . ": " . $messages[$i]->{msg} . "\n") unless $nick =~ /\Q$botnick\E/i;
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
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($alias, $command) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;
  
  if(not defined $command) {
    $logger->log("alias: invalid usage\n");
    return "/msg $nick Usage: alias <keyword> <command>";
  }
  
  if(exists $commands{$alias}) {
    $logger->log("attempt to overwrite existing command\n");
    return "/msg $nick '$alias' already exists";
  }
  
  $commands{$alias}{text}      = "/call $command";
  $commands{$alias}{owner}     = $nick;
  $commands{$alias}{timestamp} = time();
  $commands{$alias}{enabled}   = 1;
  $commands{$alias}{ref_count} = 0;
  $commands{$alias}{ref_user}  = "nobody";
  $logger->log("$nick!$user\@$host aliased $alias => $command\n");
  PBot::FactoidStuff::save_commands();
  return "/msg $nick '$alias' aliases '$command'";  
}

sub add_regex {
  my ($from, $nick, $user, $host, $arguments) = @_;
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
    $logger->log("add_regex: invalid usage\n");
    return "/msg $nick Usage: regex <regex> <command>";
  }

  if(exists $commands{$keyword}) {
    $logger->log("$nick!$user\@$host attempt to overwrite $keyword\n");
    return "/msg $nick $keyword already exists.";
  }

  $commands{$keyword}{regex}     = $text;
  $commands{$keyword}{owner}     = $nick;
  $commands{$keyword}{timestamp} = time();
  $commands{$keyword}{enabled}   = 1;
  $commands{$keyword}{ref_count} = 0;
  $commands{$keyword}{ref_user}  = "nobody";
  $logger->log("$nick!$user\@$host added [$keyword] => [$text]\n");
  PBot::FactoidStuff::save_commands();
  return "/msg $nick $keyword added.";
}

sub add_text {
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($keyword, $text) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if(not defined $text) {
    $logger->log("add_text: invalid usage\n");
    return "/msg $nick Usage: add <keyword> <factoid>";
  }

  if(not defined $keyword) {
    $logger->log("add_text: invalid usage\n");
    return "/msg $nick Usage: add <keyword> <factoid>";
  }

  $text =~ s/^is\s+//;

  if(exists $commands{$keyword}) {
    $logger->log("$nick!$user\@$host attempt to overwrite $keyword\n");
    return "/msg $nick $keyword already exists.";
  }

  $commands{$keyword}{text}      = $text;
  $commands{$keyword}{owner}     = $nick;
  $commands{$keyword}{timestamp} = time();
  $commands{$keyword}{enabled}   = 1;
  $commands{$keyword}{ref_count} = 0;
  $commands{$keyword}{ref_user}  = "nobody";
  
  $logger->log("$nick!$user\@$host added $keyword => $text\n");
  
  PBot::FactoidStuff::save_commands();
  
  return "/msg $nick $keyword added.";
}

sub histogram {
  my ($from, $nick, $user, $host, $arguments) = @_;
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
  my ($from, $nick, $user, $host, $arguments) = @_;

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
  my ($from, $nick, $user, $host, $arguments) = @_;

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
    return "$arguments: Module loaded by $commands{$arguments}{owner} on $t -> http://code.google.com/p/pbot2-pl/source/browse/trunk/modules/$commands{$arguments}{module}, used $commands{$arguments}{ref_count} times (last by $commands{$arguments}{ref_user})"; 
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
  my ($from, $nick, $user, $host, $arguments) = @_;
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
  my ($from, $nick, $user, $host, $arguments) = @_;
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
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $i = 0;
  my $text;
  my $type;

  foreach my $command (sort keys %commands) {
    if(exists $commands{$command}{text} || exists $commands{$command}{regex}) {
      $type = 'text' if(exists $commands{$command}{text});
      $type = 'regex' if(exists $commands{$command}{regex});
      $logger->log("Checking [$command], type: [$type]\n");
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
  $logger->log("Enter change_text\n");
  my ($from, $nick, $user, $host, $arguments) = @_;
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
    $logger->log("($from) $nick!$user\@$host: improper use of change\n");
    return "/msg $nick Usage: change <keyword> s/<to change>/<change to>/";
  }

  if(not exists $commands{$keyword}) {
    $logger->log("($from) $nick!$user\@$host: attempted to change nonexistant '$keyword'\n");
    return "/msg $nick $keyword not found.";
  }

  my $type;
  $type = 'text' if exists $commands{$keyword}{text};
  $type = 'regex' if exists $commands{$keyword}{regex};

  $logger->log("keyword: $keyword, type: $type, tochange: $tochange, changeto: $changeto\n");

  my $ret = eval {
    my $regex = qr/$tochange/;
    if(not $commands{$keyword}{$type} =~ s|$regex|$changeto|) {
      $logger->log("($from) $nick!$user\@$host: failed to change '$keyword' 's$delim$tochange$delim$changeto$delim\n");
      return "/msg $nick Change $keyword failed.";
    } else {
      $logger->log("($from) $nick!$user\@$host: changed '$keyword' 's/$tochange/$changeto/\n");
      PBot::FactoidStuff::save_commands();
      return "Changed: $keyword is $commands{$keyword}{$type}";
    }
  };
  return "/msg $nick Change $keyword: $@" if $@;
  return $ret;
}

sub remove_text {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments) {
    $logger->log("remove_text: invalid usage\n");
    return "/msg $nick Usage: remove <keyword>";
  }

  $logger->log("Attempting to remove [$arguments]\n");
  if(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found.";
  }

  if(exists $commands{$arguments}{command} || exists $commands{$arguments}{module}) {
    $logger->log("$nick!$user\@$host attempted to remove $arguments [not factoid]\n");
    return "/msg $nick $arguments is not a factoid.";
  }

  if(($nick ne $commands{$arguments}{owner}) and (not PBot::BotAdminStuff::loggedin($nick, $host))) {
    $logger->log("$nick!$user\@$host attempted to remove $arguments [not owner]\n");
    return "/msg $nick You are not the owner of '$arguments'";
  }

  $logger->log("$nick!$user\@$host removed [$arguments][$commands{$arguments}{text}]\n") if(exists $commands{$arguments}{text});
  $logger->log("$nick!$user\@$host removed [$arguments][$commands{$arguments}{regex}]\n") if(exists $commands{$arguments}{regex});
  delete $commands{$arguments};
  PBot::FactoidStuff::save_commands();
  return "/msg $nick $arguments removed.";
}

sub load_module {
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($keyword, $module) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if(not defined $arguments) {
    return "/msg $nick Usage: load <command> <module>";
  }

  if(not exists($commands{$keyword})) {
    $commands{$keyword}{module} = $module;
    $commands{$keyword}{enabled} = 1;
    $commands{$keyword}{owner} = $nick;
    $commands{$keyword}{timestamp} = time();
    $logger->log("$nick!$user\@$host loaded $keyword => $module\n");
    PBot::FactoidStuff::save_commands();
    return "/msg $nick Loaded $keyword => $module";
  } else {
    return "/msg $nick There is already a command named $keyword.";
  }
}

sub unload_module {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "/msg $nick Usage: unload <module>";
  } elsif(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found.";
  } elsif(not exists $commands{$arguments}{module}) {
    return "/msg $nick $arguments is not a module.";
  } else {
    delete $commands{$arguments};
    PBot::FactoidStuff::save_commands();
    $logger->log("$nick!$user\@$host unloaded module $arguments\n");
    return "/msg $nick $arguments unloaded.";
  } 
}

sub enable_command {
  my ($from, $nick, $user, $host, $arguments) = @_;
  
  if(not defined $arguments) {
    return "/msg $nick Usage: enable <command>";
  } elsif(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found.";
  } else {
    $commands{$arguments}{enabled} = 1;
    PBot::FactoidStuff::save_commands();
    $logger->log("$nick!$user\@$host enabled $arguments\n");
    return "/msg $nick $arguments enabled.";
  }   
}

sub disable_command {
  my ($from, $nick, $user, $host, $arguments) = @_;
 
  if(not defined $arguments) {
    return "/msg $nick Usage: disable <command>";
  } elsif(not exists $commands{$arguments}) {
    return "/msg $nick $arguments not found.";
  } else {
    $commands{$arguments}{enabled} = 0;
    PBot::FactoidStuff::save_commands();
    $logger->log("$nick!$user\@$host disabled $arguments\n");
    return "/msg $nick $arguments disabled.";
  }   
}

sub login {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(PBot::BotAdminStuff::loggedin($nick, $host)) {
    return "/msg $nick You are already logged in.";
  }

  if(not exists $admins{$nick}) {
    $logger->log("$nick!$user\@$host attempted to login without account.\n");
    return "/msg $nick You do not have an account.";
  }
 
  if($admins{$nick}{password} eq $arguments && $host =~ /$admins{$nick}{host}/i) {
    $admins{$nick}{login} = 1;
    $logger->log("$nick!$user\@$host logged in.\n");
    return "/msg $nick Welcome $nick, how may I help you?";
  } else {
    $logger->log("$nick!$user\@$host received wrong password.\n");
    return "/msg $nick I don't think so.";
  }
}

sub logout {
  my ($from, $nick, $user, $host, $arguments) = @_;
  return "/msg $nick Uh, you aren't logged in." if(not PBot::BotAdminStuff::loggedin($nick, $host));
  delete $admins{$nick}{login};
  $logger->log("$nick!$user\@$host logged out.\n");
  return "/msg $nick Good-bye, $nick.";
}

sub add_admin {
  my ($from, $nick, $user, $host, $arguments) = @_;
  return "/msg $nick Coming soon.";
}

sub del_admin {
  my ($from, $nick, $user, $host, $arguments) = @_;
  return "/msg $nick Coming soon.";
}

sub join_channel {
  my ($from, $nick, $user, $host, $arguments) = @_;

  # FIXME -- update %channels hash?
  $logger->log("$nick!$user\@$host made me join $arguments\n");
  $conn->join($arguments);
  return "/msg $nick Joined $arguments";
}

sub part_channel {
  my ($from, $nick, $user, $host, $arguments) = @_;

  # FIXME -- update %channels hash?
  $logger->log("$nick!$user\@$host made me part $arguments\n");
  $conn->part($arguments);
  return "/msg $nick Parted $arguments";
}

sub ack_die {
  my ($from, $nick, $user, $host, $arguments) = @_;
  $logger->log("$nick!$user\@$host made me exit.\n");
  PBot::FactoidStuff::save_commands();
  $conn->privmsg($from, "Good-bye.") if defined $from;
  $conn->quit("Departure requested.");
  exit 0;
}

sub export {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $arguments) {
    return "/msg $nick Usage: export <modules|factoids|admins>";
  }

  if($arguments =~ /^modules$/i) {
    return "/msg $nick Coming soon.";
  }

  if($arguments =~ /^quotegrabs$/i) {
    return PBot::Quotegrabs::export_quotegrabs(); 
  }

  if($arguments =~ /^factoids$/i) {
    return PBot::Factoids::export_factoids(); 
  }

  if($arguments =~ /^admins$/i) {
    return "/msg $nick Coming soon.";
  }
}

1;
