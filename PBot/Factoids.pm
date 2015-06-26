# File: Factoids.pm
# Author: pragma_
#
# Purpose: Provides functionality for factoids and a type of external module execution.

package PBot::Factoids;

use warnings;
use strict;

use HTML::Entities;
use Time::HiRes qw(gettimeofday);
use Carp ();
use POSIX qw(strftime);
use Text::ParseWords;

use PBot::PBot qw($VERSION);
use PBot::FactoidCommands;
use PBot::FactoidModuleLauncher;
use PBot::DualIndexHashObject;

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Factoids should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $filename    = delete $conf{filename};
  my $export_path = delete $conf{export_path};
  my $export_site = delete $conf{export_site};

  my $pbot = delete $conf{pbot} // Carp::croak("Missing pbot reference to Factoids");

  $self->{factoids}    = PBot::DualIndexHashObject->new(name => 'Factoids', filename => $filename);
  $self->{export_path} = $export_path;
  $self->{export_site} = $export_site;

  $self->{pbot}                  = $pbot;
  $self->{commands}              = PBot::FactoidCommands->new(pbot => $pbot);
  $self->{factoidmodulelauncher} = PBot::FactoidModuleLauncher->new(pbot => $pbot);

  $self->{pbot}->{registry}->add_default('text', 'factoids', 'default_rate_limit', '15');

  $self->{pbot}->{atexit}->register(sub { $self->save_factoids; return; });

  $self->load_factoids;
  $self->add_factoid('text', '.*', $self->{pbot}->{registry}->get_value('irc', 'botnick'), 'version', "/say $VERSION", 1);
}

sub load_factoids {
  my $self = shift;

  $self->{pbot}->{logger}->log("Loading factoids from " . $self->{factoids}->filename . " ...\n");

  $self->{factoids}->load;

  my ($text, $regex, $modules);

  foreach my $channel (keys %{ $self->{factoids}->hash }) {
    foreach my $trigger (keys %{ $self->{factoids}->hash->{$channel} }) {
      $text++   if $self->{factoids}->hash->{$channel}->{$trigger}->{type} eq 'text';
      $regex++  if $self->{factoids}->hash->{$channel}->{$trigger}->{type} eq 'regex';
      $modules++ if $self->{factoids}->hash->{$channel}->{$trigger}->{type} eq 'module';
    }
  }

  $self->{pbot}->{logger}->log("  " . ($text + $regex + $modules) . " factoids loaded ($text text, $regex regexs, $modules modules).\n");
  $self->{pbot}->{logger}->log("Done.\n");
}

sub save_factoids {
  my $self = shift;

  $self->{factoids}->save;
  $self->export_factoids;
}

sub add_factoid {
  my $self = shift;
  my ($type, $channel, $owner, $trigger, $action, $dont_save) = @_;

  $type = lc $type;
  $channel = '.*' if $channel !~ /^#/;
  $channel = lc $channel;

  $self->{factoids}->hash->{$channel}->{$trigger}->{enabled}    = 1;
  $self->{factoids}->hash->{$channel}->{$trigger}->{type}       = $type;
  $self->{factoids}->hash->{$channel}->{$trigger}->{action}     = $action;
  $self->{factoids}->hash->{$channel}->{$trigger}->{owner}      = $owner;
  $self->{factoids}->hash->{$channel}->{$trigger}->{created_on} = gettimeofday;
  $self->{factoids}->hash->{$channel}->{$trigger}->{ref_count}  = 0;
  $self->{factoids}->hash->{$channel}->{$trigger}->{ref_user}   = "nobody";
  $self->{factoids}->hash->{$channel}->{$trigger}->{rate_limit} = $self->{pbot}->{registry}->get_value('factoids', 'default_rate_limit');

  $self->save_factoids unless $dont_save;
}

sub remove_factoid {
  my $self = shift;
  my ($channel, $trigger) = @_;

  $channel = '.*' if $channel !~ /^#/;
  $channel = lc $channel;

  delete $self->{factoids}->hash->{$channel}->{$trigger};

  if(not scalar keys $self->{factoids}->hash->{$channel}) {
    delete $self->{factoids}->hash->{$channel};
  }

  $self->save_factoids;
}

sub export_factoids {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->export_path; }
  return if not defined $filename;

  open FILE, "> $filename" or return "Could not open export path.";

  my $time = localtime;
  print FILE "<html><head>\n<link href='css/blue.css' rel='stylesheet' type='text/css'>\n";
  print FILE '<script type="text/javascript" src="js/jquery-latest.js"></script>' . "\n";
  print FILE '<script type="text/javascript" src="js/jquery.tablesorter.js"></script>' . "\n";
  print FILE '<script type="text/javascript" src="js/picnet.table.filter.min.js"></script>' . "\n";
  print FILE "</head>\n<body><i>Last updated at $time</i>\n";
  print FILE "<hr><h2>Candide's factoids</h2>\n";
  
  my $i = 0;
  my $table_id = 1;

  foreach my $channel (sort keys %{ $self->{factoids}->hash }) {
    next if not scalar keys %{ $self->{factoids}->hash->{$channel} };
    my $chan = $channel eq '.*' ? 'global' : $channel;

    print FILE "<a href='#" . $chan . "'>" . encode_entities($chan) . "</a><br>\n";
  }

  foreach my $channel (sort keys %{ $self->{factoids}->hash }) {
    next if not scalar keys %{ $self->{factoids}->hash->{$channel} };
    my $chan = $channel eq '.*' ? 'global' : $channel;
    print FILE "<a name='$chan'></a>\n";
    print FILE "<hr>\n<h3>$chan</h3>\n<hr>\n";
    print FILE "<table border=\"0\" id=\"table$table_id\" class=\"tablesorter\">\n";
    print FILE "<thead>\n<tr>\n";
    print FILE "<th>owner</th>\n";
    print FILE "<th>created on</th>\n";
    print FILE "<th>times referenced</th>\n";
    print FILE "<th>factoid</th>\n";
    print FILE "<th>last edited by</th>\n";
    print FILE "<th>edited date</th>\n";
    print FILE "<th>last referenced by</th>\n";
    print FILE "<th>last referenced date</th>\n";
    print FILE "</tr>\n</thead>\n<tbody>\n";
    $table_id++;

    foreach my $trigger (sort keys %{ $self->{factoids}->hash->{$channel} }) {
      if($self->{factoids}->hash->{$channel}->{$trigger}->{type} eq 'text') {
        $i++;
        if($i % 2) {
          print FILE "<tr bgcolor=\"#dddddd\">\n";
        } else {
          print FILE "<tr>\n";
        }
        
        print FILE "<td>" . $self->{factoids}->hash->{$channel}->{$trigger}->{owner} . "</td>\n";
        print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %H:%M:%S", localtime $self->{factoids}->hash->{$channel}->{$trigger}->{created_on}) . "</td>\n";

        print FILE "<td>" . $self->{factoids}->hash->{$channel}->{$trigger}->{ref_count} . "</td>\n";

        my $action = $self->{factoids}->hash->{$channel}->{$trigger}->{action};
        $action =~ s/(.*?)http(s?:\/\/[^ ]+)/encode_entities($1) . "<a href='http" . encode_entities($2) . "'>http" . encode_entities($2) . "<\/a>"/ge;
        $action =~ s/(.*)<\/a>(.*$)/"$1<\/a>" . encode_entities($2)/e;

        if(exists $self->{factoids}->hash->{$channel}->{$trigger}->{action_with_args}) {
          my $with_args = $self->{factoids}->hash->{$channel}->{$trigger}->{action_with_args};
          $with_args =~ s/(.*?)http(s?:\/\/[^ ]+)/encode_entities($1) . "<a href='http" . encode_entities($2) . "'>http" . encode_entities($2) . "<\/a>"/ge;
          $with_args =~ s/(.*)<\/a>(.*$)/"$1<\/a>" . encode_entities($2)/e;
          print FILE "<td width=100%><b>$trigger</b> is $action<br><br><b>with_args:</b> $with_args</td>\n"; 
        } else {
          print FILE "<td width=100%><b>$trigger</b> is $action</td>\n"; 
        }

        if(exists $self->{factoids}->hash->{$channel}->{$trigger}->{edited_by}) { 
          print FILE "<td>" . $self->{factoids}->hash->{$channel}->{$trigger}->{edited_by} . "</td>\n";
          print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %H:%M:%S", localtime $self->{factoids}->hash->{$channel}->{$trigger}->{edited_on}) . "</td>\n";
        } else {
          print FILE "<td></td>\n";
          print FILE "<td></td>\n";
        }

        print FILE "<td>" . $self->{factoids}->hash->{$channel}->{$trigger}->{ref_user} . "</td>\n";

        if(exists $self->{factoids}->hash->{$channel}->{$trigger}->{last_referenced_on}) {
          print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %H:%M:%S", localtime $self->{factoids}->hash->{$channel}->{$trigger}->{last_referenced_on}) . "</td>\n";
        } else {
          print FILE "<td></td>\n";
        }
 
        print FILE "</tr>\n";
      }
    }
    print FILE "</tbody>\n</table>\n";
  }

  print FILE "<hr>$i factoids memorized.<br>";
  print FILE "<hr><i>Last updated at $time</i>\n";

  print FILE "<script type='text/javascript'>\n";
  $table_id--;
  print FILE '$(document).ready(function() {' . "\n";
  while($table_id > 0) {
    print FILE '$("#table' . $table_id . '").tablesorter();' . "\n";
    print FILE '$("#table' . $table_id . '").tableFilter();' . "\n";
    $table_id--;
  }
  print FILE "});\n";
  print FILE "</script>\n";
  print FILE "</body>\n</html>\n";
  
  close(FILE);
  
  #$self->{pbot}->{logger}->log("$i factoids exported to path: " . $self->export_path . ", site: " . $self->export_site . "\n");
  return "$i factoids exported to " . $self->export_site;
}

sub find_factoid {
  my ($self, $from, $keyword, $arguments, $exact_channel, $exact_trigger, $find_alias) = @_;

  my $debug = 0;

  $self->{pbot}->{logger}->log("find_factoid: from: [$from], kw: [$keyword], args: [" . (defined $arguments ? $arguments : "undef") . "], " . (defined $exact_channel ? $exact_channel : "undef") . ", " . (defined $exact_trigger ? $exact_trigger : "undef") . "\n") if $debug;

  $from = '.*' if not defined $from or $from !~ /^#/;
  $from = lc $from;

  $self->{pbot}->{logger}->log("from: $from\n") if $debug;

  my $string = $keyword . (defined $arguments ? " $arguments" : "");

  $self->{pbot}->{logger}->log("string: $string\n") if $debug;

  my @result = eval {
    for (my $depth = 0; $depth < 5; $depth++) {
      if ($self->{pbot}->{commands}->exists($keyword)) {
        return undef;
      }

      # check factoids
      foreach my $channel (sort keys %{ $self->{factoids}->hash }) {
        if($exact_channel) {
          if($exact_trigger) {
            next unless $from eq lc $channel;
          } else {
            next unless $from eq lc $channel or $channel eq '.*';
          }
        }

        foreach my $trigger (keys %{ $self->{factoids}->hash->{$channel} }) {
          if($keyword =~ m/^\Q$trigger\E$/i) {
            $self->{pbot}->{logger}->log("return $channel: $trigger\n") if $debug;

            if($find_alias && $self->{factoids}->hash->{$channel}->{$trigger}->{action} =~ /^\/call\s+(.*)$/) {
              my $command;
              if(length $arguments) {
                $command = "$1 $arguments";
              } else {
                $command = $1;
              }
              ($keyword, $arguments) = split / /, $command, 2;
              goto NEXT_DEPTH;
            }

            return ($channel, $trigger);
          }
        }
      }

      # then check regex factoids
      if(not $exact_trigger) {
        foreach my $channel (sort keys %{ $self->{factoids}->hash }) {
          if($exact_channel) {
            next unless $from eq lc $channel or $channel eq '.*';
          }

          foreach my $trigger (sort keys %{ $self->{factoids}->hash->{$channel} }) {
            if($self->{factoids}->hash->{$channel}->{$trigger}->{type} eq 'regex') {
              $self->{pbot}->{logger}->log("checking regex $string =~ m/$trigger/i\n") if $debug;
              if($string =~ m/$trigger/i) {
                $self->{pbot}->{logger}->log("return regex $channel: $trigger\n") if $debug;

                if($find_alias) {
                  my $command = $self->{factoids}->hash->{$channel}->{$trigger}->{action};
                  ($keyword, $arguments) = split / /, $command, 2;
                  $string = $keyword . (length $arguments ? " $arguments" : "");
                  goto NEXT_DEPTH;
                }

                return ($channel, $trigger);
              }
            }
          }
        }
      }

      NEXT_DEPTH:
      last if not $find_alias;
    }

    $self->{pbot}->{logger}->log("find_factoid: no match\n") if $debug;
    return undef;
  };

  if($@) {
    $self->{pbot}->{logger}->log("find_factoid: bad regex: $@\n");
    return undef;
  }

  return @result;
}

sub expand_action_arguments {
  my ($self, $action, $input, $nick) = @_;

  my @args = shellwords($input);

  if (not defined $input or $input eq '') {
    $action =~ s/\$args/$nick/g;
  } else {
    $action =~ s/\$args/$input/g;
  }

  while ($action =~ m/\$arg\[([^]]+)]/g) {
    my $arg = $1;

    if ($arg eq '*') {
      if (not defined $input or $input eq '') {
        $action =~ s/\$arg\[\*\]/$nick/;
      } else {
        $action =~ s/\$arg\[\*\]/$input/;
      }
      next;
    }

    if ($arg =~ m/([^:]*):(.*)/) {
      my $arg1 = $1;
      my $arg2 = $2;

      my $arg1i = $arg1;
      my $arg2i = $arg2;

      $arg1i = 0 if $arg1i eq '';
      $arg2i = $#args if $arg2i eq '';
      $arg2i = $#args if $arg2i > $#args;

      my @values = eval {
        local $SIG{__WARN__} = sub {};
        return @args[$arg1i .. $arg2i];
      };

      if ($@) {
        next;
      } else {
        my $string = join(' ', @values);

        if ($string eq '') {
          $action =~ s/\s*\$arg\[$arg1:$arg2\]//;
        } else {
          $action =~ s/\$arg\[$arg1:$arg2\]/$string/;
        }
      }

      next;
    }

    my $value = eval {
      local $SIG{__WARN__} = sub {};
      return $args[$arg];
    };

    if ($@) {
      next;
    } else {

      if (not defined $value) {
        if ($arg == 0) {
          $action =~ s/\$arg\[$arg\]/$nick/;
        } else {
          $action =~ s/\s*\$arg\[$arg\]//;
        }
      } else {
        $action =~ s/\$arg\[$arg\]/$value/;
      }
    }
  }

  return $action;
}

sub interpreter {
  my $self = shift;
  my ($from, $nick, $user, $host, $depth, $keyword, $arguments, $tonick, $ref_from) = @_;
  my ($result, $channel);
  my $pbot = $self->{pbot};

  #$self->{pbot}->{logger}->log("enter factoid interpreter [$keyword][" . (defined $arguments ? $arguments : '') . "]\n");
  return undef if not length $keyword or $depth > $self->{pbot}->{registry}->get_value('interpreter', 'max_recursion');

  $from = lc $from;

  #$self->{pbot}->{logger}->log("factoids interpreter: kw: [$keyword] args: [$arguments] from: [$from], ref_from: [" . (defined $ref_from ? $ref_from : "undef") . "]\n");

  # search for factoid against global channel and current channel (from unless ref_from is defined)
  my $original_keyword = $keyword;
  #$self->{pbot}->{logger}->log("calling find_factoid in Factoids.pm, interpreter() to search for factoid against global/current\n");
  ($channel, $keyword) = $self->find_factoid($ref_from ? $ref_from : $from, $keyword, $arguments, 1);

  if(not defined $ref_from or $ref_from eq '.*') {
    $ref_from = "";
  } else {
    $ref_from = "[$ref_from] "; 
  }

  if(defined $channel and not $channel eq '.*' and not lc $channel eq $from) {
    $ref_from = "[$channel] ";
  }

  $arguments = "" if not defined $arguments;

  # if no match found, attempt to call factoid from another channel if it exists there
  if(not defined $keyword) {
    my $string = "$original_keyword $arguments";
    my $lc_keyword = lc $original_keyword;
    my $comma = "";
    my $found = 0;
    my $chans = "";
    my ($fwd_chan, $fwd_trig);

    # build string of which channels contain the keyword, keeping track of the last one and count
    foreach my $chan (keys %{ $self->{factoids}->hash }) {
      foreach my $trig (keys %{ $self->{factoids}->hash->{$chan} }) {
        my $type = $self->{factoids}->hash->{$chan}->{$trig}->{type};
        if(($type eq 'text' or $type eq 'module') and lc $trig eq $lc_keyword) {
          $chans .= $comma . $chan;
          $comma = ", ";
          $found++;
          $fwd_chan = $chan;
          $fwd_trig = $trig;
          last;
        }
      }
    }

    # if multiple channels have this keyword, then ask user to disambiguate
    if($found > 1) {
      return $ref_from . "Ambiguous keyword '$original_keyword' exists in multiple channels (use 'fact <channel> <keyword>' to choose one): $chans";
    } 
    # if there's just one other channel that has this keyword, trigger that instance
    elsif($found == 1) {
      $pbot->{logger}->log("Found '$original_keyword' as '$fwd_trig' in [$fwd_chan]\n");
      return $pbot->{factoids}->interpreter($from, $nick, $user, $host, ++$depth, $fwd_trig, $arguments, $tonick, $fwd_chan);
    } 
    # otherwise keyword hasn't been found, display similiar matches for all channels
    else {
      # if a non-nick argument was supplied, e.g., a sentence using the bot's nick, don't say anything
      return "" if length $arguments and not $self->{pbot}->{nicklist}->is_present($from, $arguments);
      
      my $matches = $self->{commands}->factfind($from, $nick, $user, $host, quotemeta $original_keyword);

      # found factfind matches
      if($matches !~ m/^No factoids/) {
        return "No such factoid '$original_keyword'; $matches";
      }

      # otherwise find levenshtein closest matches from all channels
      $matches = $self->{factoids}->levenshtein_matches('.*', lc $original_keyword);

      # don't say anything if nothing similiar was found
      return undef if $matches eq 'none';

      return $ref_from . "No such factoid '$original_keyword'; did you mean $matches?";
    }
  }

  if(exists $self->{factoids}->hash->{$channel}->{$keyword}->{last_referenced_on}) {
    if(exists $self->{factoids}->hash->{$channel}->{$keyword}->{last_referenced_in}) {
      if($self->{factoids}->hash->{$channel}->{$keyword}->{last_referenced_in} eq $from) {
        if(gettimeofday - $self->{factoids}->hash->{$channel}->{$keyword}->{last_referenced_on} < $self->{factoids}->hash->{$channel}->{$keyword}->{rate_limit}) {
          return "/msg $nick $ref_from'$keyword' is rate-limited; try again in " . ($self->{factoids}->hash->{$channel}->{$keyword}->{rate_limit} - int(gettimeofday - $self->{factoids}->hash->{$channel}->{$keyword}->{last_referenced_on})) . " seconds." unless $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
        }
      }
    }
  }

  my $type = $self->{factoids}->hash->{$channel}->{$keyword}->{type};

  $self->{factoids}->hash->{$channel}->{$keyword}->{ref_count}++;
  $self->{factoids}->hash->{$channel}->{$keyword}->{ref_user} = "$nick!$user\@$host";
  $self->{factoids}->hash->{$channel}->{$keyword}->{last_referenced_on} = gettimeofday;
  $self->{factoids}->hash->{$channel}->{$keyword}->{last_referenced_in} = $from || "stdin";

  my $action = $self->{factoids}->hash->{$channel}->{$keyword}->{action};

  if(length $arguments) {
    if(exists $self->{factoids}->hash->{$channel}->{$keyword}->{action_with_args}) {
      $action = $self->{factoids}->hash->{$channel}->{$keyword}->{action_with_args};
    }

    if ($action =~ m/\$args/ or $action =~ m/\$arg\[/) {
      $action = $self->expand_action_arguments($action, $arguments, defined $tonick ? $tonick : $nick);
      $arguments = "";
    } else {
      if($action !~ /^\/.+? /) {
        if ($self->{pbot}->{nicklist}->is_present($from, $arguments)) {
          $action =~ s/^/\/say $arguments: $keyword is / unless defined $tonick;
        } else {
          $action =~ s/^/\/say $keyword is / unless defined $tonick;
        }
      }
    }
  } else {
    # no arguments supplied
    if(defined $tonick) {
      $action = $self->expand_action_arguments($action, undef, $tonick);
    } else {
      $action = $self->expand_action_arguments($action, undef, $nick);
    }
  }

  # Check if it's an alias
  if($action =~ /^\/call\s+(.*)$/) {
    my $command;
    if(length $arguments) {
      $command = "$1 $arguments";
    } else {
      $command = $1;
    }

    $pbot->{logger}->log("[" . (defined $from ? $from : "stdin") . "] ($nick!$user\@$host) [$keyword] aliased to: [$command]\n");
    return $pbot->{interpreter}->interpret($from, $nick, $user, $host, $depth, $command, $tonick);
  }

  if(defined $tonick) { # !tell foo about bar
    $self->{pbot}->{logger}->log("($from): $nick!$user\@$host) sent to $tonick\n");
    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

    # get rid of original caller's nick
    $action =~ s/^\/([^ ]+) \Q$nick\E:\s+/\/$1 /;
    $action =~ s/^\Q$nick\E:\s+//;

    if($action =~ s/^\/say\s+//i || $action =~ s/^\/me\s+/* $botnick /i
      || $action =~ /^\/msg\s+/i) {
      $action = "/say $tonick: $action";
    } else {
      $action = "/say $tonick: $keyword is $action";
    }

    $self->{pbot}->{logger}->log("result set to [$action]\n");
  }

  $self->{pbot}->{logger}->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host: $keyword: action: \"$action\"\n");

  $action =~ s/\$nick/$nick/g;
  $action =~ s/\$channel/$from/g;
  $action =~ s/\$randomnick/my $random = $self->{pbot}->{nicklist}->random_nick($from); $random ? $random : $nick/ge;

  while ($action =~ /(?<!\\)\$([a-zA-Z0-9_\-]+)/g) {
    my $v = $1;
    next if $v =~ m/^[0-9]+$/;
    my ($var_chan, $var) = $self->find_factoid($from, $v, undef, 0, 1);

    if(defined $var && $self->{factoids}->hash->{$var_chan}->{$var}->{type} eq 'text') {
      my $change = $self->{factoids}->hash->{$var_chan}->{$var}->{action};
      my @list = split(/\s|(".*?")/, $change);
      my @mylist;
      for(my $i = 0; $i <= $#list; $i++) {
        push @mylist, $list[$i] if $list[$i];
      }
      my $line = int(rand($#mylist + 1));
      $mylist[$line] =~ s/"//g;
      $action =~ s/\$$var/$mylist[$line]/;
    } else {
      $action =~ s/(?<!\\)\$$var/$var/;
    }
  }

  $action =~ s/\\\$/\$/g;

  if($self->{factoids}->hash->{$channel}->{$keyword}->{enabled} == 0) {
    $self->{pbot}->{logger}->log("$keyword disabled.\n");
    return "/msg $nick $ref_from$keyword is currently disabled.";
  }

  if($self->{factoids}->hash->{$channel}->{$keyword}->{type} eq 'module') {
    my $preserve_whitespace = $self->{factoids}->hash->{$channel}->{$keyword}->{preserve_whitespace};
    $preserve_whitespace = 0 if not defined $preserve_whitespace;

    return $ref_from . $self->{factoidmodulelauncher}->execute_module($from, $tonick, $nick, $user, $host, "$keyword $arguments", $keyword, $arguments, $preserve_whitespace);
  }
  elsif($self->{factoids}->hash->{$channel}->{$keyword}->{type} eq 'text') {
    $self->{pbot}->{logger}->log("Found factoid\n");

    # Don't allow user-custom /msg factoids, unless factoid triggered by admin
    if(($action =~ m/^\/msg/i) and (not $self->{pbot}->{admins}->loggedin($from, "$nick!$user\@$host"))) {
      $self->{pbot}->{logger}->log("[ABUSE] Bad factoid (contains /msg): $action\n");
      return "You must login to use this command."
    }

    if($ref_from) {
      if($action =~ s/^\/say\s+/$ref_from/i || $action =~ s/^\/me\s+(.*)/\/me $1 $ref_from/i
        || $action =~ s/^\/msg\s+([^ ]+)/\/msg $1 $ref_from/i) {
        return $action;
      } else {
        return $ref_from . "$keyword is $action";
      }
    } else {
      if($action =~ m/^\/say/i || $action =~ m/^\/me/i || $action =~ m/^\/msg/i) {
        return $action;
      } else {
        return "$keyword is $action";
      }
    }
  } elsif($self->{factoids}->hash->{$channel}->{$keyword}->{type} eq 'regex') {
    $result = eval {
      my $string = "$original_keyword" . (defined $arguments ? " $arguments" : "");
      my $cmd;
      if($string =~ m/$keyword/i) {
        $self->{pbot}->{logger}->log("[$string] matches [$keyword] - calling [" . $action . "$']\n");
        $cmd = $action . $';
        my ($a, $b, $c, $d, $e, $f, $g, $h, $i, $before, $after) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $`, $');
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
      } else {
        $cmd = $action;
      }

      $result = $pbot->{interpreter}->interpret($from, $nick, $user, $host, $depth, $cmd, $tonick);
      return $result;
    };

    if($@) {
      $self->{pbot}->{logger}->log("Regex fail: $@\n");
      return "";
    }

    return $ref_from . $result;
  } else {
    $self->{pbot}->{logger}->log("($from): $nick!$user\@$host): Unknown command type for '$keyword'\n"); 
    return "/me blinks." . " $ref_from";
  }
}

sub export_path {
  my $self = shift;

  if(@_) { $self->{export_path} = shift; }
  return $self->{export_path};
}

sub logger {
  my $self = shift;
  if(@_) { $self->{logger} = shift; }
  return $self->{logger};
}

sub export_site {
  my $self = shift;
  if(@_) { $self->{export_site} = shift; }
  return $self->{export_site};
}

sub factoids {
  my $self = shift;
  return $self->{factoids};
}

sub filename {
  my $self = shift;

  if(@_) { $self->{filename} = shift; }
  return $self->{filename};
}

1;
