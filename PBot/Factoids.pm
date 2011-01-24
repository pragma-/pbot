# File: Factoids.pm
# Author: pragma_
#
# Purpose: Provides functionality for factoids and a type of external module execution.

package PBot::Factoids;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use HTML::Entities;
use Time::HiRes qw(gettimeofday);
use Carp ();

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

  my $filename = delete $conf{filename};
  my $export_path = delete $conf{export_path};
  my $export_site = delete $conf{export_site};

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
    Carp::croak("Missing pbot reference to Factoids");
  }

  $self->{factoids} = PBot::DualIndexHashObject->new(name => 'Factoids', filename => $filename);
  $self->{export_path} = $export_path;
  $self->{export_site} = $export_site;

  $self->{pbot} = $pbot;
  $self->{factoidmodulelauncher} = PBot::FactoidModuleLauncher->new(pbot => $pbot);
}

sub load_factoids {
  my $self = shift;

  $self->{pbot}->logger->log("Loading factoids from " . $self->factoids->filename . " ...\n");

  $self->factoids->load;

  my ($text, $regex, $modules);

  foreach my $channel (keys %{ $self->factoids->hash }) {
    foreach my $trigger (keys %{ $self->factoids->hash->{$channel} }) {
      $text++   if $self->factoids->hash->{$channel}->{$trigger}->{type} eq 'text';
      $regex++  if $self->factoids->hash->{$channel}->{$trigger}->{type} eq 'regex';
      $modules++ if $self->factoids->hash->{$channel}->{$trigger}->{type} eq 'module';
    }
  }

  $self->{pbot}->logger->log("  " . ($text + $regex + $modules) . " factoids loaded ($text text, $regex regexs, $modules modules).\n");
  $self->{pbot}->logger->log("Done.\n");
}

sub save_factoids {
  my $self = shift;

  $self->factoids->save;
  $self->export_factoids;
}

sub add_factoid {
  my $self = shift;
  my ($type, $channel, $owner, $trigger, $action) = @_;

  $type = lc $type;
  $channel = lc $channel;
  $trigger = lc $trigger;

  $self->factoids->hash->{$channel}->{$trigger}->{enabled}    = 1;
  $self->factoids->hash->{$channel}->{$trigger}->{type}       = $type;
  $self->factoids->hash->{$channel}->{$trigger}->{action}     = $action;
  $self->factoids->hash->{$channel}->{$trigger}->{owner}      = $owner;
  $self->factoids->hash->{$channel}->{$trigger}->{created_on} = gettimeofday;
  $self->factoids->hash->{$channel}->{$trigger}->{ref_count}  = 0;
  $self->factoids->hash->{$channel}->{$trigger}->{ref_user}   = "nobody";
  $self->factoids->hash->{$channel}->{$trigger}->{rate_limit} = 15;

  $self->save_factoids;
}

sub remove_factoid {
  my $self = shift;
  my ($channel, $trigger) = @_;

  $channel = lc $channel;
  $trigger = lc $trigger;

  delete $self->factoids->hash->{$channel}->{$trigger};
  $self->save_factoids;
}

sub export_factoids {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->export_path; }
  return if not defined $filename;

  open FILE, "> $filename" or return "Could not open export path.";

  my $time = localtime;
  print FILE "<html><body><i>Last updated at $time</i>\n";
  print FILE "<hr><h2>Candide's factoids</h2>\n";
  
  my $i = 0;

  foreach my $channel (sort keys %{ $self->factoids->hash }) {
    my $chan = $channel eq '.*' ? 'Global channel' : "Channel $channel";
    print FILE "<hr>\n<h3>$chan<h3>\n<hr>\n";
    print FILE "<table border=\"0\">\n";
    foreach my $trigger (sort keys %{ $self->factoids->hash->{$channel} }) {
      if($self->factoids->hash->{$channel}->{$trigger}->{type} eq 'text') {
        $i++;
        if($i % 2) {
          print FILE "<tr bgcolor=\"#dddddd\">\n";
        } else {
          print FILE "<tr>\n";
        }
        
        my $action = $self->factoids->hash->{$channel}->{$trigger}->{action};
        $action =~ s/(.*?)http(s?:\/\/[^ ]+)/encode_entities($1) . "<a href='http" . encode_entities($2) . "'>http" . encode_entities($2) . "<\/a>"/ge;
        $action =~ s/(.*)<\/a>(.*$)/"$1<\/a>" . encode_entities($2)/e;

        print FILE "<td width=100%><b>$trigger</b> is " . $action . "</td>\n"; 
        
        print FILE "<td align=\"right\" nowrap>- submitted by " . $self->factoids->hash->{$channel}->{$trigger}->{owner} . "<br><i>" . localtime($self->factoids->hash->{$channel}->{$trigger}->{created_on}) . "</i>\n</td>\n</tr>\n";
      }
    }
    print FILE "</table>\n";
  }

  print FILE "<hr>$i factoids memorized.<br>";
  print FILE "<hr><i>Last updated at $time</i>\n";
  
  close(FILE);
  
  #$self->{pbot}->logger->log("$i factoids exported to path: " . $self->export_path . ", site: " . $self->export_site . "\n");
  return "$i factoids exported to " . $self->export_site;
}

sub find_factoid {
  my ($self, $from, $keyword, $arguments, $exact_channel, $exact_trigger) = @_;

  $from = '.*' if not defined $from or $from !~ /^#/;

  my $string = "$keyword" . (defined $arguments ? " $arguments" : "");

  my @result = eval {
    foreach my $channel (sort keys %{ $self->factoids->hash }) {
      if($exact_channel) {
        next unless $from eq $channel;
      } else {
        next unless $from =~ m/$channel/i;
      }

      foreach my $trigger (keys %{ $self->factoids->hash->{$channel} }) {
        if(not $exact_trigger and $self->factoids->hash->{$channel}->{$trigger}->{type} eq 'regex') {
          if($string =~ m/$trigger/i) {
            return ($channel, $trigger);
          }
        } else {
          if($keyword =~ m/^\Q$trigger\E$/i) {
            return ($channel, $trigger);
          }
        }
      }
    }

    return undef;
  };

  if($@) {
    $self->{pbot}->logger->log("find_factoid: bad regex: $@\n");
    return undef;
  }

  return @result;
}

sub interpreter {
  my $self = shift;
  my ($from, $nick, $user, $host, $count, $keyword, $arguments, $tonick) = @_;
  my ($result, $channel);
  my $pbot = $self->{pbot};

  $from = lc $from;

  # (COMMENTED OUT) remove trailing comma or colon from keyword if keyword has other characters beforehand 
  # $keyword =~ s/^(.+)[:,]$/$1/;

  return undef if not length $keyword;

  my $original_keyword = $keyword;
  ($channel, $keyword) = $self->find_factoid($from, $keyword, $arguments);

  if(not defined $keyword) {
    my $matches = $self->factoids->levenshtein_matches('.*', lc $original_keyword);

    return undef if $matches eq 'none';

    return "No such factoid '$original_keyword'; did you mean $matches?";
  }

  my $type = $self->factoids->hash->{$channel}->{$keyword}->{type};

  # Check if it's an alias
  if($self->factoids->hash->{$channel}->{$keyword}->{action} =~ /^\/call\s+(.*)$/) {
    my $command;
    if(defined $arguments) {
      $command = "$1 $arguments";
    } else {
      $command = $1;
    }

    $pbot->logger->log("[" . (defined $from ? $from : "(undef)") . "] ($nick!$user\@$host) [$keyword] aliased to: [$command]\n");

    $self->factoids->hash->{$channel}->{$keyword}->{ref_count}++;
    $self->factoids->hash->{$channel}->{$keyword}->{ref_user} = $nick;
    $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_on} = gettimeofday;

    return $pbot->interpreter->interpret($from, $nick, $user, $host, $count, $command);
  }

  my $last_ref_in = 0;

  if(exists $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_on}) {
    if(exists $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_in}) {
      if($self->factoids->hash->{$channel}->{$keyword}->{last_referenced_in} eq $from) {
        $last_ref_in = 1;
      }
    }

    if(($last_ref_in == 1) and (gettimeofday - $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_on} < $self->factoids->hash->{$channel}->{$keyword}->{rate_limit})) {
      return "/msg $nick '$keyword' is rate-limited; try again in " . ($self->factoids->hash->{$channel}->{$keyword}->{rate_limit} - int(gettimeofday - $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_on})) . " seconds.";
    }
  }

  if($self->factoids->hash->{$channel}->{$keyword}->{enabled} == 0) {
    $self->{pbot}->logger->log("$keyword disabled.\n");
    return "/msg $nick $keyword is currently disabled.";
  } 
  elsif($self->factoids->hash->{$channel}->{$keyword}->{type} eq 'module') {
    $self->{pbot}->logger->log("Found module\n");

    $self->factoids->hash->{$channel}->{$keyword}->{ref_count}++;
    $self->factoids->hash->{$channel}->{$keyword}->{ref_user} = $nick;
    $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_on} = gettimeofday;
    $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_in} = $from || "stdin";

    return $self->{factoidmodulelauncher}->execute_module($from, $tonick, $nick, $user, $host, $keyword, $arguments);
  }
  elsif($self->factoids->hash->{$channel}->{$keyword}->{type} eq 'text') {
    $self->{pbot}->logger->log("Found factoid\n");

    # Don't allow user-custom /msg factoids, unless factoid triggered by admin
    if(($self->factoids->hash->{$channel}->{$keyword}->{action} =~ m/^\/msg/i) and (not $self->{pbot}->admins->loggedin($from, "$nick!$user\@$host"))) {
      $self->{pbot}->logger->log("[HACK] Bad factoid (contains /msg): " . $self->factoids->hash->{$channel}->{$keyword}->{action} . "\n");
      return "You must login to use this command."
    }

    $self->factoids->hash->{$channel}->{$keyword}->{ref_count}++;
    $self->factoids->hash->{$channel}->{$keyword}->{ref_user} = $nick;
    $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_on} = gettimeofday;
    $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_in} = $from || "stdin";

    $self->{pbot}->logger->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host): $keyword: Displaying text \"" . $self->factoids->hash->{$channel}->{$keyword}->{action} . "\"\n");

    if(defined $tonick) { # !tell foo about bar
      $self->{pbot}->logger->log("($from): $nick!$user\@$host) sent to $tonick\n");
      my $fromnick = $self->{pbot}->admins->loggedin($from, "$nick!$user\@$host") ? "" : "$nick wants you to know: ";
      $result = $self->factoids->hash->{$channel}->{$keyword}->{action};

      my $botnick = $self->{pbot}->botnick;

      if($result =~ s/^\/say\s+//i || $result =~ s/^\/me\s+/* $botnick /i
        || $result =~ /^\/msg\s+/i) {
        $result = "/msg $tonick $fromnick$result";
      } else {
        $result = "/msg $tonick $fromnick$keyword is $result";
      }

      $self->{pbot}->logger->log("text set to [$result]\n");
    } else {
      $result = $self->factoids->hash->{$channel}->{$keyword}->{action};
    }

    if(defined $arguments) {
      # TODO - extract and remove $tonick from end of $arguments
      if(not $result =~ s/\$args/$arguments/gi) {
        # factoid doesn't take an argument
        if($arguments =~ /^[^ ]{1,20}$/) {
          # might be a nick
          if($result =~ /^\/.+? /) {
            $result =~ s/^(\/.+?) /$1 $arguments: /;
          } else {
            $result =~ s/^/\/say $arguments: $keyword is / unless (defined $tonick);
          }                  
        } else {
          # return undef;
        }
      }
    } else {
      # no arguments supplied
      $result =~ s/\$args/$nick/gi;
    }

    $result =~ s/\$nick/$nick/g;

    while ($result =~ /[^\\]\$([a-zA-Z0-9_\-]+)/g) { 
      my ($var_chan, $var) = $self->find_factoid($from, $1, undef, 0, 1);

      if(defined $var && $self->factoids->hash->{$var_chan}->{$var}->{type} eq 'text') {
        my $change = $self->factoids->hash->{$var_chan}->{$var}->{action};
        my @list = split(/\s|(".*?")/, $change);
        my @mylist;
        #$self->{pbot}->logger->log("adlib: list [". join(':', @mylist) ."]\n");
        for(my $i = 0; $i <= $#list; $i++) {
          #$self->{pbot}->logger->log("adlib: pushing $i $list[$i]\n");
          push @mylist, $list[$i] if $list[$i];
        }
        my $line = int(rand($#mylist + 1));
        $mylist[$line] =~ s/"//g;
        $result =~ s/\$$var/$mylist[$line]/;
        #$self->{pbot}->logger->log("adlib: found: change: $result\n");
      } else {
        $result =~ s/\$$var/$var/g;
        #$self->{pbot}->logger->log("adlib: not found: change: $result\n");
      }
    }

    $result =~ s/\\\$/\$/g;

    if($result =~ s/^\/say\s+//i || $result =~ /^\/me\s+/i
      || $result =~ /^\/msg\s+/i) {
      return $result;
    } else {
      return "$keyword is $result";
    }
  } elsif($self->factoids->hash->{$channel}->{$keyword}->{type} eq 'regex') {
    $result = eval {
      my $string = "$original_keyword" . (defined $arguments ? " $arguments" : "");
      my $cmd;
      if($string =~ m/$keyword/i) {
        $self->{pbot}->logger->log("[$string] matches [$keyword] - calling [" . $self->factoids->hash->{$channel}->{$keyword}->{action} . "$']\n");
        $cmd = $self->factoids->hash->{$channel}->{$keyword}->{action} . $';
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
        $cmd = $self->factoids->hash->{$channel}->{$keyword}->{action}; 
      }

      $result = $pbot->interpreter->interpret($from, $nick, $user, $host, $count, $cmd);
      return $result;
    };

    if($@) {
      $self->{pbot}->logger->log("Regex fail: $@\n");
      return "/msg $nick Fail.";
    }

    return $result;
  } else {
    $self->{pbot}->logger->log("($from): $nick!$user\@$host): Unknown command type for '$keyword'\n"); 
    return "/me blinks.";
  }
  return "/me wrinkles her nose.";
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
