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
use Text::Levenshtein qw(fastdistance);
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
  print FILE "<html><body><i>Generated at $time</i><hr><h3>Candide's factoids:</h3><br>\n";
  
  my $i = 0;

  foreach my $channel (sort keys %{ $self->factoids->hash }) {
    my $chan = $channel eq '.*' ? 'any' : $channel;
    print FILE "<hr>\nChannel $chan\n<hr>\n";
    print FILE "<table border=\"0\">\n";
    foreach my $trigger (sort keys %{ $self->factoids->hash->{$channel} }) {
      if($self->factoids->hash->{$channel}->{$trigger}->{type} eq 'text') {
        $i++;
        if($i % 2) {
          print FILE "<tr bgcolor=\"#dddddd\">\n";
        } else {
          print FILE "<tr>\n";
        }

        print FILE "<td><b>$trigger</b> is " . encode_entities($self->factoids->hash->{$channel}->{$trigger}->{action}) . "</td>\n"; 
        
        print FILE "<td align=\"right\">- submitted by<br> " . $self->factoids->hash->{$channel}->{$trigger}->{owner} . "<br><i>" . localtime($self->factoids->hash->{$channel}->{$trigger}->{created_on}) . "</i>\n</td>\n</tr>\n";
      }
    }
    print FILE "</table>\n";
  }

  print FILE "<hr>$i factoids memorized.<br>";
  
  close(FILE);
  
  #$self->{pbot}->logger->log("$i factoids exported to path: " . $self->export_path . ", site: " . $self->export_site . "\n");
  return "$i factoids exported to " . $self->export_site;
}

sub find_factoid {
  my ($self, $from, $keyword, $arguments, $exact_channel) = @_;

  $from = '.*' if not defined $from;

  my $string = "$keyword" . (defined $arguments ? " $arguments" : "");

  my @result = eval {
    foreach my $channel (sort keys %{ $self->factoids->hash }) {
      if($exact_channel) {
        next unless $from eq $channel;
      } else {
        next unless $from =~ m/$channel/i;
      }
      foreach my $trigger (keys %{ $self->factoids->hash->{$channel} }) {
        if($self->factoids->hash->{$channel}->{$trigger}->{type} eq 'regex') {
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

  my $original_keyword = $keyword;
  ($channel, $keyword) = $self->find_factoid($from, $keyword, $arguments);

  if(not defined $keyword) {
    my $matches = $self->factoids->levenshtein_matches($from, lc $original_keyword);

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

  if($self->factoids->hash->{$channel}->{$keyword}->{enabled} == 0) {
    $self->{pbot}->logger->log("$keyword disabled.\n");
    return "/msg $nick $keyword is currently disabled.";
  } elsif($self->factoids->hash->{$channel}->{$keyword}->{type} eq 'module') {
    $self->{pbot}->logger->log("Found module\n");

    $self->factoids->hash->{$channel}->{$keyword}->{ref_count}++;
    $self->factoids->hash->{$channel}->{$keyword}->{ref_user} = $nick;
    $self->factoids->hash->{$channel}->{$keyword}->{last_referenced_on} = gettimeofday;

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
          if($result !~ /^\/.+? /) {
            $result =~ s/^/\/say $keyword is / unless (defined $tonick);
          }                  
        }
      }
    } else {
      # no arguments supplied
      $result =~ s/\$args/$nick/gi;
    }

    $result =~ s/\$nick/$nick/g;

    while ($result =~ /[^\\]\$([a-zA-Z0-9_\-\.]+)/g) { 
      my ($var_chan, $var) = $self->find_factoid($from, $1);

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
      my $string = "$keyword" . (defined $arguments ? " $arguments" : "");
      if($string =~ m/$keyword/i) {
        $self->{pbot}->logger->log("[$string] matches [$keyword] - calling [" . $self->factoids->hash->{$channel}->{$keyword}->{action} . "$']\n");
        my $cmd = "${ $self->factoids }{$keyword}{regex}$'";
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
        $result = $pbot->interpreter->interpret($from, $nick, $user, $host, $count, $cmd);
        return $result;
      }
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
