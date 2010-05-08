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

  $self->{factoids} = {};
  $self->{filename} = $filename;
  $self->{export_path} = $export_path;
  $self->{export_site} = $export_site;

  $self->{pbot} = $pbot;
  $self->{factoidmodulelauncher} = PBot::FactoidModuleLauncher->new(pbot => $pbot);
}


sub load_factoids_add {
  my ($self, $factoid, $i, $filename) = @_;

  if(defined $factoid) {
    my $trigger = delete $factoid->{trigger};

    if(not defined $trigger) {
      Carp::croak "Missing trigger around line $i of $filename\n";
    }

    if(exists $self->factoids->{$trigger}) {
      Carp::croak "Duplicate factoid '$trigger' found in $filename around line $i\n";
    }

    my $type = delete $factoid->{type};

    if(not defined $type) {
      Carp::croak "Missing type for factoid '$trigger' around line $i of $filename\n";
    }

    $type = lc $type;

    my $action = delete $factoid->{action};

    if(not defined $action) {
      Carp::croak "Missing action for factoid '$trigger' around line $i of $filename\n";
    }

    $self->factoids->{$trigger}{$type} = $action;

    foreach my $key (keys %$factoid) {
      $self->factoids->{$trigger}{$key} = $factoid->{$key};
    }
  }
}

sub load_factoids {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->filename; }

  if(not defined $filename) {
    Carp::carp "No factoids path specified -- skipping loading of factoids";
    return;
  }

  $self->{pbot}->logger->log("Loading factoids from $filename ...\n");

  open(FILE, "< $filename") or Carp::croak "Couldn't open $filename: $!\n";

  my $i = 0;
  my ($text, $regex, $modules, $factoid);

  foreach my $line (<FILE>) {
    $i++;

    $line =~ s/^\s+//;
    $line =~ s/\s+$//;

    if(not $line) {
      print "blank line at $i\n";
      next;
    }

    if($line eq '-') {
      # first store the old factoid, if there is one
      if($factoid) {
        my $type = lc $factoid->{type};
        if($type eq "text") {
          $text++;
        } elsif($type eq "regex") {
          $regex++;
        } elsif($type eq "module") {
          $modules++;
        } else {
          Carp::croak "Unknown type '$type' in $filename around line $i\n";
        }
        $self->load_factoids_add($factoid, $i, $filename);
      }

      # start a new factoid
      $factoid = {};
      next;
    }

    my ($key, $value) = split /\:/, $line, 2;

    $key =~ s/^\s+//;
    $key =~ s/\s+$//;
    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    $factoid->{$key} = $value;
  }

  close(FILE);

  if($factoid) {
    my $type = lc $factoid->{type};
    if($type eq "text") {
      $text++;
    } elsif($type eq "regex") {
      $regex++;
    } elsif($type eq "module") {
      $modules++;
    } else {
      Carp::croak "Unknown type '$type' in $filename around line $i\n";
    }
    $self->load_factoids_add($factoid, $i, $filename);
  }

  $self->{pbot}->logger->log("  " . ($text + $regex + $modules) . " factoids loaded ($text text, $regex regexs, $modules modules).\n");
  $self->{pbot}->logger->log("Done.\n");
}

sub save_factoids {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->filename; }

  if(not defined $filename) {
    Carp::carp "No factoids path specified -- skipping saving of factoids\n";
    return;
  }

  open(FILE, "> $filename") or die "Couldn't open $filename: $!\n";

  foreach my $trigger (sort keys %{ $self->factoids }) {
    next if $trigger eq "version";

    print FILE "-\n";
    print FILE "trigger: $trigger\n";

    my $type;

    if(defined ${ $self->factoids }{$trigger}{module}) {
      $type = 'module';
    } elsif(defined ${ $self->factoids }{$trigger}{text}) {
      $type = 'text';
    } elsif(defined ${ $self->factoids }{$trigger}{regex}) {
      $type = 'regex';
    } else {
      $self->{pbot}->logger->log("WARNING: save_factoids: skipping unknown trigger type for $trigger\n");
      #todo -- /msg logged in admins greater than level X 
      next;
    }

    print FILE "type: $type\n";
    print FILE "action: ${ $self->factoids }{$trigger}{$type}\n";

    foreach my $key (sort keys %{ ${ $self->factoids }{$trigger} }) {
      next if $key eq 'text' or $key eq 'module' or $key eq 'regex';
      print FILE "$key: ${ $self->factoids }{$trigger}{$key}\n";
    }
  }
  close(FILE);

  $self->export_factoids();
}

sub add_factoid {
  my $self = shift;
  my ($type, $channel, $owner, $command, $text) = @_;

  $type = lc $type;
  $channel = lc $channel;
  $command = lc $command;

  ${ $self->factoids }{$command}{enabled}   = 1;
  ${ $self->factoids }{$command}{$type}     = $text;
  ${ $self->factoids }{$command}{owner}     = $owner;
  ${ $self->factoids }{$command}{channel}   = $channel;
  ${ $self->factoids }{$command}{created_on} = gettimeofday;
  ${ $self->factoids }{$command}{ref_count} = 0;
  ${ $self->factoids }{$command}{ref_user}  = "nobody";
}

sub export_factoids {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->export_path; }
  return if not defined $filename;

  my $text;
  open FILE, "> $filename" or return "Could not open export path.";
  my $time = localtime;
  print FILE "<html><body><i>Generated at $time</i><hr><h3>Candide's factoids:</h3><br>\n";
  my $i = 0;
  print FILE "<table border=\"0\">\n";
  foreach my $command (sort keys %{ $self->factoids }) {
    if(exists ${ $self->factoids }{$command}{text}) {
      $i++;
      if($i % 2) {
        print FILE "<tr bgcolor=\"#dddddd\">\n";
      } else {
        print FILE "<tr>\n";
      }
      $text = "<td><b>$command</b> is " . encode_entities(${ $self->factoids }{$command}{text}) . "</td>\n"; 
      print FILE $text;
      my ($seconds, $minutes, $hours, $day_of_month, $month, $year, $wday, $yday, $isdst) = localtime(${ $self->factoids }{$command}{created_on});
      my $t = sprintf("%02d:%02d:%02d-%04d/%02d/%02d\n",
          $hours, $minutes, $seconds, $year+1900, $month+1, $day_of_month);
      print FILE "<td align=\"right\">- submitted by<br> ${ $self->factoids }{$command}{owner}<br><i>$t</i>\n";
      print FILE "</td></tr>\n";
    }
  }
  print FILE "</table>\n";
  print FILE "<hr>$i factoids memorized.<br>";
  close(FILE);
  #$self->{pbot}->logger->log("$i factoids exported to path: " . $self->export_path . ", site: " . $self->export_site . "\n");
  return "$i factoids exported to " . $self->export_site;
}

sub find_factoid {
  my ($self, $keyword, $arguments) = @_;

  my $string = "$keyword" . (defined $arguments ? " $arguments" : "");

  my $result = eval {
    foreach my $command (keys %{ $self->factoids }) {
      if(exists $self->factoids->{$command}{regex}) {
        if($string =~ m/$command/i) {
          return $command;
        }
      } else {
        my $command_quoted = quotemeta($command);
        if($keyword =~ m/^$command_quoted$/i) {
          return $command;
        }
      }
    }

    return undef;
  };

  if($@) {
    $self->{pbot}->logger->log("find_factoid: bad regex: $@\n");
    return undef;
  }

  return $result;
}

sub levenshtein_matches {
  my ($self, $keyword) = @_;
  my $comma = '';
  my $result = "I don't know about '$keyword'; did you mean ";
  
  foreach my $command (sort keys %{ $self->factoids }) {
    next if exists $self->factoids->{$command}{regex};
    my $distance = fastdistance($keyword, $command);

    # print "Distance $distance for $keyword (" , (length $keyword) , ") vs $command (" , length $command , ")\n";
    
    my $length = (length($keyword) > length($command)) ? length $keyword : length $command;

    # print "Percentage: ", $distance / $length, "\n";

    if($distance / $length < 0.50) {
      $result .= $comma . $command;
      $comma = ", ";
    }
  }

  $result =~ s/(.*), /$1 or /;
  $result =~ s/$/?/;
  $result = undef if $comma eq '';
  return $result;
}

sub interpreter {
  my $self = shift;
  my ($from, $nick, $user, $host, $count, $keyword, $arguments, $tonick) = @_;
  my $result;
  my $pbot = $self->{pbot};

  my $string = "$keyword" . (defined $arguments ? " $arguments" : "");
  my $lev = lc $keyword;
  $keyword = $self->find_factoid($keyword, $arguments);
  return $self->levenshtein_matches($lev) if not defined $keyword;

  my $type;
  $type = 'text' if exists $self->factoids->{$keyword}{text};
  $type = 'regex' if exists $self->factoids->{$keyword}{regex};
  $type = 'module' if exists $self->factoids->{$keyword}{module};

  # Check if it's an alias
  my $command;
  if($self->factoids->{$keyword}{$type} =~ /^\/call\s+(.*)$/) {
    if(defined $arguments) {
      $command = "$1 $arguments";
    } else {
      $command = $1;
    }
    $pbot->logger->log("[" . (defined $from ? $from : "(undef)") . "] ($nick!$user\@$host) [$keyword] aliased to: [$command]\n");

    $self->factoids->{$keyword}{ref_count}++;
    $self->factoids->{$keyword}{ref_user} = $nick;

    return $pbot->interpreter->interpret($from, $nick, $user, $host, $count, $command);
  }

  if(${ $self->factoids }{$keyword}{enabled} == 0) {
    $self->{pbot}->logger->log("$keyword disabled.\n");
    return "/msg $nick $keyword is currently disabled.";
  } elsif(exists ${ $self->factoids }{$keyword}{module}) {
    $self->{pbot}->logger->log("Found module\n");

    ${ $self->factoids }{$keyword}{ref_count}++;
    ${ $self->factoids }{$keyword}{ref_user} = $nick;

    return $self->{factoidmodulelauncher}->execute_module($from, $tonick, $nick, $user, $host, $keyword, $arguments);
  }
  elsif(exists ${ $self->factoids }{$keyword}{text}) {
    $self->{pbot}->logger->log("Found factoid\n");

    # Don't allow user-custom /msg factoids, unless factoid triggered by admin
    if((${ $self->factoids }{$keyword}{text} =~ m/^\/msg/i) and (not $self->{pbot}->admins->loggedin($from, "$nick!$user\@$host"))) {
      $self->{pbot}->logger->log("[HACK] Bad factoid (contains /msg): ${ $self->factoids }{$keyword}{text}\n");
      return "You must login to use this command."
    }

    ${ $self->factoids }{$keyword}{ref_count}++;
    ${ $self->factoids }{$keyword}{ref_user} = $nick;

    $self->{pbot}->logger->log("(" . (defined $from ? $from : "(undef)") . "): $nick!$user\@$host): $keyword: Displaying text \"${ $self->factoids }{$keyword}{text}\"\n");

    if(defined $tonick) { # !tell foo about bar
      $self->{pbot}->logger->log("($from): $nick!$user\@$host) sent to $tonick\n");
      my $fromnick = $self->{pbot}->admins->loggedin($from, "$nick!$user\@$host") ? "" : "$nick wants you to know: ";
      $result = ${ $self->factoids }{$keyword}{text};

      my $botnick = $self->{pbot}->botnick;

      if($result =~ s/^\/say\s+//i || $result =~ s/^\/me\s+/* $botnick /i
        || $result =~ /^\/msg\s+/i) {
        $result = "/msg $tonick $fromnick$result";
      } else {
        $result = "/msg $tonick $fromnick$keyword is $result";
      }

      $self->{pbot}->logger->log("text set to [$result]\n");
    } else {
      $result = ${ $self->factoids }{$keyword}{text};
    }

    if(defined $arguments) {
      $self->{pbot}->logger->log("got arguments: [$arguments]\n");

      # TODO - extract and remove $tonick from end of $arguments
      if(not $result =~ s/\$args/$arguments/gi) {
        $self->{pbot}->logger->log("factoid doesn't take argument, checking ...\n");
        # factoid doesn't take an argument
        if($arguments =~ /^[^ ]{1,20}$/) {
          # might be a nick
          $self->{pbot}->logger->log("could be nick\n");
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
        $self->{pbot}->logger->log("updated text: [$result]\n");
      }
      $self->{pbot}->logger->log("replaced \$args: [$result]\n");
    } else {
      # no arguments supplied
      $result =~ s/\$args/$nick/gi;
    }

    $result =~ s/\$nick/$nick/g;

    while ($result =~ /[^\\]\$([a-zA-Z0-9_\-]+)/g) { 
      my $var = $1;
      #$self->{pbot}->logger->log("adlib: got [$var]\n");
      #$self->{pbot}->logger->log("adlib: parsing variable [\$$var]\n");
      if(exists ${ $self->factoids }{$var} && exists ${ $self->factoids }{$var}{text}) {
        my $change = ${ $self->factoids }{$var}{text};
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
  } elsif(exists ${ $self->factoids }{$keyword}{regex}) {
    $result = eval {
      if($string =~ m/$keyword/i) {
        $self->{pbot}->logger->log("[$string] matches [$keyword] - calling [" . ${ $self->factoids }{$keyword}{regex}. "$']\n");
        my $cmd = "${ $self->factoids }{$keyword}{regex}$'";
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
