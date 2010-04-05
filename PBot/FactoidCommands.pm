# File: FactoidCommands.pm
# Author: pragma_
#
# Purpose: Administrative command subroutines.

# TODO: Add getter for factoids instead of directly accessing factoids

package PBot::FactoidCommands;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to FactoidCommands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
    Carp::croak("Missing pbot reference to FactoidCommands");
  }

  $self->{pbot} = $pbot;
  
  $pbot->commands->register(sub { return $self->list(@_)            },       "list",        0);
  $pbot->commands->register(sub { return $self->alias(@_)           },       "alias",       0);
  $pbot->commands->register(sub { return $self->add_regex(@_)       },       "regex",       0);
  $pbot->commands->register(sub { return $self->add_text(@_)        },       "add",         0);
  $pbot->commands->register(sub { return $self->add_text(@_)        },       "learn",       0);
  $pbot->commands->register(sub { return $self->histogram(@_)       },       "histogram",   0);
  $pbot->commands->register(sub { return $self->show(@_)            },       "show",        0);
  $pbot->commands->register(sub { return $self->info(@_)            },       "info",        0);
  $pbot->commands->register(sub { return $self->top20(@_)           },       "top20",       0);
  $pbot->commands->register(sub { return $self->count(@_)           },       "count",       0);
  $pbot->commands->register(sub { return $self->find(@_)            },       "find",        0);
  $pbot->commands->register(sub { return $self->change_text(@_)     },       "change",      0);
  $pbot->commands->register(sub { return $self->remove_text(@_)     },       "remove",      0);
  $pbot->commands->register(sub { return $self->remove_text(@_)     },       "forget",      0);
  $pbot->commands->register(sub { return $self->load_module(@_)     },       "load",        50);
  $pbot->commands->register(sub { return $self->unload_module(@_)   },       "unload",      50);
  $pbot->commands->register(sub { return $self->enable_command(@_)  },       "enable",      10);
  $pbot->commands->register(sub { return $self->disable_command(@_) },       "disable",     10);
}

sub list {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  my $botnick = $self->{pbot}->botnick;
  my $text;
  
  if(not defined $arguments) {
    return "/msg $nick Usage: list <modules|factoids|commands|admins>";
  }

  if($arguments =~/^messages\s+(.*)$/) {
    my ($nick_search, $channel_search, $text_search) = split / /, $1;

    return "/msg $nick Usage: !list messages <nick regex> <channel regex> [text regex]" if not defined $channel_search;
    $text_search = '.*' if not defined $text_search;

    my @results = eval {
      my @ret;
      foreach my $history_nick (keys %{ $self->{pbot}->antiflood->message_history }) {
        if($history_nick =~ m/$nick_search/i) {
          foreach my $history_channel (keys %{ $self->{pbot}->antiflood->message_history->{$history_nick} }) {
            if($history_channel =~ m/$channel_search/i) {
              my @messages = @{ ${ $self->{pbot}->antiflood->message_history }{$history_nick}{$history_channel}{messages} };

              for(my $i = 0; $i <= $#messages; $i++) {
                next if $messages[$i]->{msg} =~ /^!login/;
                push @ret, { text => $messages[$i]->{msg}, timestamp => $messages[$i]->{timestamp}, nick => $history_nick, channel => $history_channel } if $messages[$i]->{msg} =~ m/$text_search/i;
              }
            }
          }
        }
      }
      return @ret;
    };

    if($@) {
      $self->{pbot}->logger->log("Error in search parameters: $@\n");
      return "Error in search parameters: $@";
    }

    my @sorted = sort { $a->{timestamp} <=> $b->{timestamp} } @results;
    foreach my $msg (@sorted) {
      $self->{pbot}->logger->log("[$msg->{channel}] " . localtime($msg->{timestamp}) . " <$msg->{nick}> " . $msg->{text} . "\n");
      $self->{pbot}->conn->privmsg($nick, "[$msg->{channel}] " . localtime($msg->{timestamp}) . " <$msg->{nick}> " . $msg->{text} . "\n") unless $nick =~ /\Q$botnick\E/i;
    }
    return "";
  }

  if($arguments =~ /^modules$/i) {
    $text = "Loaded modules: ";
    foreach my $command (sort keys %{ $factoids }) {
      if(exists $factoids->{$command}{module}) {
        $text .= "$command ";
      }
    }
    return $text;
  }

  if($arguments =~ /^commands$/i) {
    $text = "Registered commands: ";
    foreach my $command (sort { $a->{name} cmp $b->{name} } @{ $self->{pbot}->commands->{handlers} }) {
      $text .= "$command->{name} ";
      $text .= "($command->{level}) " if $command->{level} > 0;
    }
    return $text;
  }

  if($arguments =~ /^factoids$/i) {
    return "For a list of factoids see " . $self->{pbot}->factoids->export_site;
  }

  if($arguments =~ /^admins$/i) {
    $text = "Admins: ";
    my $last_channel = "";
    my $sep = "";
    foreach my $channel (sort keys %{ $self->{pbot}->admins->admins }) {
      if($last_channel ne $channel) {
        print "texzt: [$text], sep: [$sep]\n";
        $text .= $sep . "Channel " . ($channel eq ".*" ? "all" : $channel) . ": ";
        $last_channel = $channel;
        $sep = "";
      }
      foreach my $hostmask (sort keys %{ $self->{pbot}->admins->admins->{$channel} }) {
        $text .= $sep;
        $text .= "*" if exists ${ $self->{pbot}->admins->admins }{$channel}{$hostmask}{loggedin};
        $text .= ${ $self->{pbot}->admins->admins }{$channel}{$hostmask}{name} . " (" . ${ $self->{pbot}->admins->admins }{$channel}{$hostmask}{level} . ")";
        $sep = "; ";
      }
    }
    return $text;
  }
  return "/msg $nick Usage: list <modules|commands|factoids|admins>";
}

sub alias {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  my ($alias, $command) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;
  
  if(not defined $command) {
    $self->{pbot}->logger->log("alias: invalid usage\n");
    return "/msg $nick Usage: alias <keyword> <command>";
  }
  
  if(exists $factoids->{$alias}) {
    $self->{pbot}->logger->log("attempt to overwrite existing command\n");
    return "/msg $nick '$alias' already exists";
  }
  
  $factoids->{$alias}{text}      = "/call $command";
  $factoids->{$alias}{owner}     = $nick;
  $factoids->{$alias}{timestamp} = time();
  $factoids->{$alias}{enabled}   = 1;
  $factoids->{$alias}{ref_count} = 0;
  $factoids->{$alias}{ref_user}  = "nobody";
  $self->{pbot}->logger->log("$nick!$user\@$host aliased $alias => $command\n");
  $self->{pbot}->factoids->save_factoids();
  return "/msg $nick '$alias' aliases '$command'";  
}

sub add_regex {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  my ($keyword, $text) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if(not defined $keyword) {
    $text = "";
    foreach my $command (sort keys %{ $factoids }) {
      if(exists $factoids->{$command}{regex}) {
        $text .= $command . " ";
      }
    }
    return "Stored regexs: $text";
  }

  if(not defined $text) {
    $self->{pbot}->logger->log("add_regex: invalid usage\n");
    return "/msg $nick Usage: regex <regex> <command>";
  }

  if(exists $factoids->{$keyword}) {
    $self->{pbot}->logger->log("$nick!$user\@$host attempt to overwrite $keyword\n");
    return "/msg $nick $keyword already exists.";
  }

  $factoids->{$keyword}{regex}     = $text;
  $factoids->{$keyword}{owner}     = $nick;
  $factoids->{$keyword}{timestamp} = time();
  $factoids->{$keyword}{enabled}   = 1;
  $factoids->{$keyword}{ref_count} = 0;
  $factoids->{$keyword}{ref_user}  = "nobody";
  $self->{pbot}->logger->log("$nick!$user\@$host added [$keyword] => [$text]\n");
  $self->{pbot}->factoids->save_factoids();
  return "/msg $nick $keyword added.";
}

sub add_text {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  my ($keyword, $text) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if(not defined $text) {
    $self->{pbot}->logger->log("add_text: invalid usage\n");
    return "/msg $nick Usage: add <keyword> <factoid>";
  }

  if(not defined $keyword) {
    $self->{pbot}->logger->log("add_text: invalid usage\n");
    return "/msg $nick Usage: add <keyword> <factoid>";
  }

  $text =~ s/^is\s+//;

  if(exists $factoids->{$keyword}) {
    $self->{pbot}->logger->log("$nick!$user\@$host attempt to overwrite $keyword\n");
    return "/msg $nick $keyword already exists.";
  }

  $factoids->{$keyword}{text}      = $text;
  $factoids->{$keyword}{owner}     = $nick;
  $factoids->{$keyword}{timestamp} = time();
  $factoids->{$keyword}{enabled}   = 1;
  $factoids->{$keyword}{ref_count} = 0;
  $factoids->{$keyword}{ref_user}  = "nobody";
  
  $self->{pbot}->logger->log("$nick!$user\@$host added $keyword => $text\n");
  
  $self->{pbot}->factoids->save_factoids();
  
  return "/msg $nick $keyword added.";
}

sub histogram {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  my %hash;
  my $factoid_count = 0;

  foreach my $command (keys %{ $factoids }) {
    if(exists $factoids->{$command}{text}) {
      $hash{$factoids->{$command}{owner}}++;
      $factoid_count++;
    }
  }

  my $text;
  my $i = 0;

  foreach my $owner (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
    my $percent = int($hash{$owner} / $factoid_count * 100);
    $percent = 1 if $percent == 0;
    $text .= "$owner: $hash{$owner} ($percent". "%) ";  
    $i++;
    last if $i >= 10;
  }
  return "$factoid_count factoids, top 10 submitters: $text";
}

sub show {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;

  if(not defined $arguments) {
    return "/msg $nick Usage: show <factoid>";
  }

  if(not exists $factoids->{$arguments}) {
    return "/msg $nick $arguments not found";
  }

  if(exists $factoids->{$arguments}{command} || exists $factoids->{$arguments}{module}) {
    return "/msg $nick $arguments is not a factoid";
  }

  my $type;
  $type = 'text' if exists $factoids->{$arguments}{text};
  $type = 'regex' if exists $factoids->{$arguments}{regex};
  return "$arguments: $factoids->{$arguments}{$type}";
}

sub info {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;

  if(not defined $arguments) {
    return "/msg $nick Usage: info <factoid|module>";
  }

  if(not exists $factoids->{$arguments}) {
    return "/msg $nick $arguments not found";
  }

  # factoid
  if(exists $factoids->{$arguments}{text}) {
    return "$arguments: Factoid submitted by $factoids->{$arguments}{owner} on " . localtime($factoids->{$arguments}{timestamp}) . ", referenced $factoids->{$arguments}{ref_count} times (last by $factoids->{$arguments}{ref_user})";
  }

  # module
  if(exists $factoids->{$arguments}{module}) {
    return "$arguments: Module loaded by $factoids->{$arguments}{owner} on " . localtime($factoids->{$arguments}{timestamp}) . " -> http://code.google.com/p/pbot2-pl/source/browse/trunk/modules/$factoids->{$arguments}{module}, used $factoids->{$arguments}{ref_count} times (last by $factoids->{$arguments}{ref_user})"; 
  }

  # regex
  if(exists $factoids->{$arguments}{regex}) {
    return "$arguments: Regex created by $factoids->{$arguments}{owner} on " . localtime($factoids->{$arguments}{timestamp}) . ", used $factoids->{$arguments}{ref_count} times (last by $factoids->{$arguments}{ref_user})"; 
  }

  return "/msg $nick $arguments is not a factoid or a module";
}

sub top20 {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  my %hash = ();
  my $text = "";
  my $i = 0;

  if(not defined $arguments) {
    foreach my $command (sort {$factoids->{$b}{ref_count} <=> $factoids->{$a}{ref_count}} keys %{ $factoids }) {
      if($factoids->{$command}{ref_count} > 0 && exists $factoids->{$command}{text}) {
        $text .= "$command ($factoids->{$command}{ref_count}) ";
        $i++;
        last if $i >= 20;
      }
    }
    $text = "Top $i referenced factoids: $text" if $i > 0;
    return $text;
  } else {

    if(lc $arguments eq "recent") {
      foreach my $command (sort { $factoids->{$b}{timestamp} <=> $factoids->{$a}{timestamp} } keys %{ $factoids }) {
        #my ($seconds, $minutes, $hours, $day_of_month, $month, $year, $wday, $yday, $isdst) = localtime($factoids->{$command}{timestamp});
        #my $t = sprintf("%04d/%02d/%02d", $year+1900, $month+1, $day_of_month);
                
        $text .= "$command ";
        $i++;
        last if $i >= 50;
      }
      $text = "$i most recent submissions: $text" if $i > 0;
      return $text;
    }

    my $user = lc $arguments;
    foreach my $command (sort keys %{ $factoids }) {
      if($factoids->{$command}{ref_user} =~ /\Q$arguments\E/i) {
        if($user ne lc $factoids->{$command}{ref_user} && not $user =~ /$factoids->{$command}{ref_user}/i) {
          $user .= " ($factoids->{$command}{ref_user})";
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
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  my $i = 0;
  my $total = 0;

  if(not defined $arguments) {
    return "/msg $nick Usage:  count <nick|factoids>";
  }

  $arguments = ".*" if($arguments =~ /^factoids$/);

  eval {
    foreach my $command (keys %{ $factoids }) {
      $total++ if exists $factoids->{$command}{text};
      my $regex = qr/^\Q$arguments\E$/;
      if($factoids->{$command}{owner} =~ /$regex/i && exists $factoids->{$command}{text}) {
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
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  my $text;
  my $type;

  if(not defined $arguments) {
    return "/msg $nick Usage: !find [-owner nick] [-by nick] [text]";
  }

  my ($owner, $by);

  $owner = $1 if $arguments =~ s/-owner\s+([^\b\s]+)//i;
  $by = $1 if $arguments =~ s/-by\s+([^\b\s]+)//i;

  $owner = '.*' if not defined $owner;
  $by = '.*' if not defined $by;

  $arguments =~ s/^\s+//;
  $arguments =~ s/\s+$//;
  $arguments =~ s/\s+/ /g;

  my $argtype = undef;

  if($owner ne '.*') {
    $argtype = "owned by $owner";
  }

  if($by ne '.*') {
    if(not defined $argtype) {
      $argtype = "last referenced by $by";
    } else {
      $argtype .= " and last referenced by $by";
    }
  }

  if($arguments ne "") {
    if(not defined $argtype) {
      $argtype = "with text matching '$arguments'";
    } else {
      $argtype .= " and with text matching '$arguments'";
    }
  }

  if(not defined $argtype) {
    return "/msg $nick Usage: !find [-owner nick] [-by nick] [text]";
  }

  my $i = 0;
  eval {
    foreach my $command (sort keys %{ $factoids }) {
      if(exists $factoids->{$command}{text} || exists $factoids->{$command}{regex}) {
        $type = 'text' if(exists $factoids->{$command}{text});
        $type = 'regex' if(exists $factoids->{$command}{regex});

        if($factoids->{$command}{owner} =~ /$owner/i && $factoids->{$command}{ref_user} =~ /$by/i) {
          next if($arguments ne "" && $factoids->{$command}{$type} !~ /$arguments/i && $command !~ /$arguments/i);
          $i++;
          $text .= "$command ";
        }
      }
    }
  };

  return "/msg $nick $arguments: $@" if $@;

  if($i == 1) {
    chop $text;
    $type = 'text' if exists $factoids->{$text}{text};
    $type = 'regex' if exists $factoids->{$text}{regex};
    return "found one factoid " . $argtype . ": '$text' is '$factoids->{$text}{$type}'";
  } else {
    return "$i factoids " . $argtype . ": $text" unless $i == 0;
    return "No factoids " . $argtype;
  }
}

sub change_text {
  my $self = shift;
  $self->{pbot}->logger->log("Enter change_text\n");
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
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
    $self->{pbot}->logger->log("($from) $nick!$user\@$host: improper use of change\n");
    return "/msg $nick Usage: change <keyword> s/<to change>/<change to>/";
  }

  if(not exists $factoids->{$keyword}) {
    $self->{pbot}->logger->log("($from) $nick!$user\@$host: attempted to change nonexistant '$keyword'\n");
    return "/msg $nick $keyword not found.";
  }

  my $type;
  $type = 'text' if exists $factoids->{$keyword}{text};
  $type = 'regex' if exists $factoids->{$keyword}{regex};

  $self->{pbot}->logger->log("keyword: $keyword, type: $type, tochange: $tochange, changeto: $changeto\n");

  my $ret = eval {
    my $regex = qr/$tochange/;
    if(not $factoids->{$keyword}{$type} =~ s|$regex|$changeto|) {
      $self->{pbot}->logger->log("($from) $nick!$user\@$host: failed to change '$keyword' 's$delim$tochange$delim$changeto$delim\n");
      return "/msg $nick Change $keyword failed.";
    } else {
      $self->{pbot}->logger->log("($from) $nick!$user\@$host: changed '$keyword' 's/$tochange/$changeto/\n");
      $self->{pbot}->factoids->save_factoids();
      return "Changed: $keyword is $factoids->{$keyword}{$type}";
    }
  };
  return "/msg $nick Change $keyword: $@" if $@;
  return $ret;
}

sub remove_text {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;

  if(not defined $arguments) {
    $self->{pbot}->logger->log("remove_text: invalid usage\n");
    return "/msg $nick Usage: remove <keyword>";
  }

  $self->{pbot}->logger->log("Attempting to remove [$arguments]\n");
  if(not exists $factoids->{$arguments}) {
    return "/msg $nick $arguments not found.";
  }

  if(exists $factoids->{$arguments}{command} || exists $factoids->{$arguments}{module}) {
    $self->{pbot}->logger->log("$nick!$user\@$host attempted to remove $arguments [not factoid]\n");
    return "/msg $nick $arguments is not a factoid.";
  }

  if(($nick ne $factoids->{$arguments}{owner}) and (not $self->{pbot}->admins->loggedin($from, "$nick!$user\@$host"))) {
    $self->{pbot}->logger->log("$nick!$user\@$host attempted to remove $arguments [not owner]\n");
    return "/msg $nick You are not the owner of '$arguments'";
  }

  $self->{pbot}->logger->log("$nick!$user\@$host removed [$arguments][$factoids->{$arguments}{text}]\n") if(exists $factoids->{$arguments}{text});
  $self->{pbot}->logger->log("$nick!$user\@$host removed [$arguments][$factoids->{$arguments}{regex}]\n") if(exists $factoids->{$arguments}{regex});
  delete $factoids->{$arguments};
  $self->{pbot}->factoids->save_factoids();
  return "/msg $nick $arguments removed.";
}

sub load_module {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  my ($keyword, $module) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if(not defined $module) {
    return "/msg $nick Usage: load <command> <module>";
  }

  if(not exists($factoids->{$keyword})) {
    $factoids->{$keyword}{module} = $module;
    $factoids->{$keyword}{enabled} = 1;
    $factoids->{$keyword}{owner} = $nick;
    $factoids->{$keyword}{timestamp} = time();
    $self->{pbot}->logger->log("$nick!$user\@$host loaded $keyword => $module\n");
    $self->{pbot}->factoids->save_factoids();
    return "/msg $nick Loaded $keyword => $module";
  } else {
    return "/msg $nick There is already a command named $keyword.";
  }
}

sub unload_module {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;

  if(not defined $arguments) {
    return "/msg $nick Usage: unload <module>";
  } elsif(not exists $factoids->{$arguments}) {
    return "/msg $nick $arguments not found.";
  } elsif(not exists $factoids->{$arguments}{module}) {
    return "/msg $nick $arguments is not a module.";
  } else {
    delete $factoids->{$arguments};
    $self->{pbot}->factoids->save_factoids();
    $self->{pbot}->logger->log("$nick!$user\@$host unloaded module $arguments\n");
    return "/msg $nick $arguments unloaded.";
  } 
}

sub enable_command {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;
  
  if(not defined $arguments) {
    return "/msg $nick Usage: enable <command>";
  } elsif(not exists $factoids->{$arguments}) {
    return "/msg $nick $arguments not found.";
  } else {
    $factoids->{$arguments}{enabled} = 1;
    $self->{pbot}->factoids->save_factoids();
    $self->{pbot}->logger->log("$nick!$user\@$host enabled $arguments\n");
    return "/msg $nick $arguments enabled.";
  }   
}

sub disable_command {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->factoids->factoids;

  if(not defined $arguments) {
    return "/msg $nick Usage: disable <command>";
  } elsif(not exists $factoids->{$arguments}) {
    return "/msg $nick $arguments not found.";
  } else {
    $factoids->{$arguments}{enabled} = 0;
    $self->{pbot}->factoids->save_factoids();
    $self->{pbot}->logger->log("$nick!$user\@$host disabled $arguments\n");
    return "/msg $nick $arguments disabled.";
  }   
}

1;
