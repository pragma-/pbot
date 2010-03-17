# File: NewModule.pm
# Authoer: pragma_
#
# Purpose: New module skeleton

package PBot::Quotegrabs;

use warnings;
use strict;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = $PBot::PBot::VERSION;
  @ISA = qw(Exporter);
  @EXPORT_OK = qw(@quotegrabs $logger $MAX_NICK_MESSAGES %flood_watch $quotegrabs_file $export_quotegrabs_path $export_quotegrabs_timeout);
}

use vars @EXPORT_OK;

*logger = \$PBot::PBot::logger;
*quotegrabs_file = \$PBot::PBot::quotegrabs_file;
*export_quotegrabs_path = \$PBot::PBot::export_quotegrabs_path;
*export_quotegrabs_timeout = \$PBot::PBot::export_quotegrabs_timeout;

@quotegrabs = ();

sub quotegrab {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $logger->log("Command missing ~from parameter!\n");
    return "";
  }

  if(not defined $arguments) {
    return "Usage: !grab <nick> [history] [channel] -- where [history] is an optional argument that is an integer number of recent messages; e.g., to grab the 3rd most recent message for nick, use !grab nick 3";
  }

  my ($grab_nick, $grab_history, $channel) = split(/\s+/, $arguments, 3);

  $grab_history = 1 if not defined $grab_history;
  $channel = $from if not defined $channel;

  if($grab_history < 1 || $grab_history > $MAX_NICK_MESSAGES) {
    return "/msg $nick Please choose a history between 1 and $MAX_NICK_MESSAGES";
  }

  if(not exists $flood_watch{$grab_nick}) {
    return "No message history for $grab_nick.";
  }

  if(not exists $flood_watch{$grab_nick}{$channel}) {
    return "No message history for $grab_nick in $channel.";
  }
  
  my @messages = @{ $flood_watch{$grab_nick}{$channel}{messages} };

  $grab_history--;
  
  if($grab_history > $#messages) {
    return "$grab_nick has only " . ($#messages + 1) . " messages in the history.";
  }

  $grab_history = $#messages - $grab_history;

  $logger->log("$nick ($from) grabbed <$grab_nick/$channel> $messages[$grab_history]->{msg}\n");

  my $quotegrab = {};
  $quotegrab->{nick} = $grab_nick;
  $quotegrab->{channel} = $channel;
  $quotegrab->{timestamp} = $messages[$grab_history]->{timestamp};
  $quotegrab->{grabbed_by} = $nick;
  $quotegrab->{text} = $messages[$grab_history]->{msg};
  $quotegrab->{id} = $#quotegrabs + 2;
  
  push @quotegrabs, $quotegrab;
  
  save_quotegrabs();
  
  my $msg = $messages[$grab_history]->{msg};
  $msg =~ s/(.{8}).*/$1.../;
  
  return "Quote grabbed: " . ($#quotegrabs + 1) . ": <$grab_nick> $msg";
}

sub delete_quotegrab {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if($arguments < 1 || $arguments > $#quotegrabs + 1) {
    return "/msg $nick Valid range for !getq is 1 - " . ($#quotegrabs + 1);
  }

  my $quotegrab = $quotegrabs[$arguments - 1];
  splice @quotegrabs, $arguments - 1, 1;
  save_quotegrabs();
  return "Deleted $arguments: <$quotegrab->{nick}> $quotegrab->{text}";
}

sub show_quotegrab {
  my ($from, $nick, $user, $host, $arguments) = @_;

  if($arguments < 1 || $arguments > $#quotegrabs + 1) {
    return "/msg $nick Valid range for !getq is 1 - " . ($#quotegrabs + 1);
  }

  my $quotegrab = $quotegrabs[$arguments - 1];
  return "$arguments: <$quotegrab->{nick}> $quotegrab->{text}";
}

sub show_random_quotegrab {
  my ($from, $nick, $user, $host, $arguments) = @_;
  my @quotes = ();
  my $nick_search = ".*";
  my $channel_search = $from;

  if(not defined $from) {
    $logger->log("Command missing ~from parameter!\n");
    return "";
  }

  if(defined $arguments) {
    ($nick_search, $channel_search) = split(/\s+/, $arguments, 2);
    # $logger->log("[ns: $nick_search][cs: $channel_search]\n");
    if(not defined $channel_search) {
      $channel_search = $from;
    }
  } 
  
  my $channel_search_quoted = quotemeta($channel_search);
  $logger->log("[ns: $nick_search][cs: $channel_search][csq: $channel_search_quoted]\n");

  eval {
    for(my $i = 0; $i <= $#quotegrabs; $i++) {
      my $hash = $quotegrabs[$i];
      if($hash->{channel} =~ /$channel_search_quoted/i && $hash->{nick} =~ /$nick_search/i) {
        $hash->{id} = $i + 1;
        push @quotes, $hash;
      }
    }
  };

  if($@) {
    $logger->log("Error in show_random_quotegrab parameters: $@\n");
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
  $logger->log("Loading quotegrabs from $quotegrabs_file ...\n");
  
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
    $quotegrab->{id} = $i + 1;
    push @quotegrabs, $quotegrab;
  }
  $logger->log("  $i quotegrabs loaded.\n");
  $logger->log("Done.\n");
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

sub export_quotegrabs() { 
  return "Not enabled" if not defined $export_quotegrabs_path;
  my $text;
  my $last_channel = "";
  my $had_table = 0;
  open FILE, "> $export_quotegrabs_path" or return "Could not open export path.";
  my $time = localtime;
  print FILE "<html><body><i>Generated at $time</i><hr><h1>Candide's Quotegrabs</h1>\n";
  my $i = 0;
  foreach my $quotegrab (sort { $$a{channel} cmp $$b{channel} or $$a{nick} cmp $$b{nick} } @quotegrabs) {
    if(not $quotegrab->{channel} =~ /^$last_channel$/i) {
      print FILE "</table>\n" if $had_table;
      print FILE "<hr><h2>$quotegrab->{channel}</h2><hr>\n";
      print FILE "<table border=\"0\">\n";
      $had_table = 1;
    }

    $last_channel = $quotegrab->{channel};
    $i++;

    if($i % 2) {
      print FILE "<tr bgcolor=\"#dddddd\">\n";
    } else {
      print FILE "<tr>\n";
    }
    print FILE "<td>" . ($quotegrab->{id}) . "</td>";
    $text = "<td><b>&lt;$quotegrab->{nick}&gt;</b> " . encode_entities($quotegrab->{text}) . "</td>\n"; 
    print FILE $text;
    my ($seconds, $minutes, $hours, $day_of_month, $month, $year, $wday, $yday, $isdst) = localtime($quotegrab->{timestamp});
    my $t = sprintf("%02d:%02d:%02d-%04d/%02d/%02d\n",
      $hours, $minutes, $seconds, $year+1900, $month+1, $day_of_month);
    print FILE "<td align=\"right\">- grabbed by<br> $quotegrab->{grabbed_by}<br><i>$t</i>\n";
    print FILE "</td></tr>\n";
  }

  print FILE "</table>\n";
  print FILE "<hr>$i quotegrabs grabbed.<br>This page is automatically generated every $export_quotegrabs_timeout seconds.</body></html>";
  close(FILE);
  return "$i quotegrabs exported to http://blackshell.com/~msmud/candide/quotegrabs.html";
}

1;
