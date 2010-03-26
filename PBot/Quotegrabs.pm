# File: Quotegrabs.pm
# Author: pragma_
#
# Purpose: Allows users to "grab" quotes from anti-flood history and store them for later retreival.

package PBot::Quotegrabs;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use HTML::Entities;

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Quotegrabs should be key/value pairs, not hash reference");
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
    Carp::croak("Missing pbot reference to Quotegrabs");
  }

  my $filename = delete $conf{filename};
  my $export_path = delete $conf{export_path};

  $self->{pbot} = $pbot;
  $self->{filename} = $filename;
  $self->{export_path} = $export_path;
  $self->{quotegrabs} = [];

  #-------------------------------------------------------------------------------------
  # The following could be in QuotegrabsCommands.pm, or they could be kept in here?
  #-------------------------------------------------------------------------------------
  $pbot->commands->register(sub { $self->grab_quotegrab(@_)        },  "grab",  0);
  $pbot->commands->register(sub { $self->show_quotegrab(@_)        },  "getq",  0);
  $pbot->commands->register(sub { $self->delete_quotegrab(@_)      },  "delq",  0);
  $pbot->commands->register(sub { $self->show_random_quotegrab(@_) },  "rq",    0);
}

sub load_quotegrabs {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->{filename}; }
  return if not defined $filename;

  $self->{pbot}->logger->log("Loading quotegrabs from $filename ...\n");
  
  open(FILE, "< $filename") or die "Couldn't open $filename: $!\n";
  my @contents = <FILE>;
  close(FILE);

  my $i = 0;
  foreach my $line (@contents) {
    chomp $line;
    $i++;
    my ($nick, $channel, $timestamp, $grabbed_by, $text) = split(/\s+/, $line, 5);
    if(not defined $nick || not defined $channel || not defined $timestamp
       || not defined $grabbed_by || not defined $text) {
      die "Syntax error around line $i of $self->{quotegrabs}_file\n";
    }

    my $quotegrab = {};
    $quotegrab->{nick} = $nick;
    $quotegrab->{channel} = $channel;
    $quotegrab->{timestamp} = $timestamp;
    $quotegrab->{grabbed_by} = $grabbed_by;
    $quotegrab->{text} = $text;
    $quotegrab->{id} = $i + 1;
    push @{ $self->{quotegrabs} }, $quotegrab;
  }
  $self->{pbot}->logger->log("  $i quotegrabs loaded.\n");
  $self->{pbot}->logger->log("Done.\n");
}

sub save_quotegrabs {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->{filename}; }
  return if not defined $filename;

  open(FILE, "> $filename") or die "Couldn't open $filename: $!\n";

  for(my $i = 0; $i <= $#{ $self->{quotegrabs} }; $i++) {
    my $quotegrab = $self->{quotegrabs}[$i];
    next if $quotegrab->{timestamp} == 0;
    print FILE "$quotegrab->{nick} $quotegrab->{channel} $quotegrab->{timestamp} $quotegrab->{grabbed_by} $quotegrab->{text}\n";
  }

  close(FILE);
  $self->export_quotegrabs();
}

sub export_quotegrabs() { 
  my $self = shift;
  return "Not enabled" if not defined $self->{export_path};
  my $text;
  my $last_channel = "";
  my $had_table = 0;
  open FILE, "> $self->{export_path}" or return "Could not open export path.";
  my $time = localtime;
  print FILE "<html><body><i>Generated at $time</i><hr><h1>Candide's Quotegrabs</h1>\n";
  my $i = 0;
  foreach my $quotegrab (sort { $$a{channel} cmp $$b{channel} or $$a{nick} cmp $$b{nick} } @{ $self->{quotegrabs} }) {
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
  close(FILE);
  return "$i quotegrabs exported to http://blackshell.com/~msmud/candide/quotegrabs.html";
}

# ----------------------------------------------------------------------------------------
# The following subroutines could be in QuotegrabCommands.pm . . . 
# ----------------------------------------------------------------------------------------

sub grab_quotegrab {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

  if(not defined $arguments) {
    return "Usage: !grab <nick> [history] [channel] -- where [history] is an optional argument that is an integer number of recent messages; e.g., to grab the 3rd most recent message for nick, use !grab nick 3";
  }

  my ($grab_nick, $grab_history, $channel) = split(/\s+/, $arguments, 3);

  if(not defined $grab_history) {
    $grab_history = $nick eq $grab_nick ? 2 : 1;
  }
  $channel = $from if not defined $channel;

  if($grab_history < 1 || $grab_history > $self->{pbot}->{MAX_NICK_MESSAGES}) {
    return "/msg $nick Please choose a history between 1 and $self->{pbot}->{MAX_NICK_MESSAGES}";
  }

  if(not exists $self->{pbot}->antiflood->message_history->{$grab_nick}) {
    return "No message history for $grab_nick.";
  }

  if(not exists $self->{pbot}->antiflood->message_history->{$grab_nick}{$channel}) {
    return "No message history for $grab_nick in $channel.";
  }
  
  my @messages = @{ $self->{pbot}->antiflood->message_history->{$grab_nick}{$channel}{messages} };

  $grab_history--;
  
  if($grab_history > $#messages) {
    return "$grab_nick has only " . ($#messages + 1) . " messages in the history.";
  }

  $grab_history = $#messages - $grab_history;

  $self->{pbot}->logger->log("$nick ($from) grabbed <$grab_nick/$channel> $messages[$grab_history]->{msg}\n");

  my $quotegrab = {};
  $quotegrab->{nick} = $grab_nick;
  $quotegrab->{channel} = $channel;
  $quotegrab->{timestamp} = $messages[$grab_history]->{timestamp};
  $quotegrab->{grabbed_by} = $nick;
  $quotegrab->{text} = $messages[$grab_history]->{msg};
  $quotegrab->{id} = $#{ $self->{quotegrabs} } + 2;
  
  push @{ $self->{quotegrabs} }, $quotegrab;
  
  $self->save_quotegrabs();
  
  my $msg = $messages[$grab_history]->{msg};
  $msg =~ s/(.{8}).*/$1.../;
  
  return "Quote grabbed: " . ($#{ $self->{quotegrabs} } + 1) . ": <$grab_nick> $msg";
}

sub add_quotegrab {
  my ($self, $nick, $channel, $timestamp, $grabbed_by, $text) = @_;

  my $quotegrab = {};
  $quotegrab->{nick} = $nick;
  $quotegrab->{channel} = $channel;
  $quotegrab->{timestamp} = $timestamp;
  $quotegrab->{grabbed_by} = $grabbed_by;
  $quotegrab->{text} = $text;
  $quotegrab->{id} = $#{ $self->{quotegrabs} } + 2;
  
  push @{ $self->{quotegrabs} }, $quotegrab;
} 

sub delete_quotegrab {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if($arguments < 1 || $arguments > $#{ $self->{quotegrabs} } + 1) {
    return "/msg $nick Valid range for !getq is 1 - " . ($#{ $self->{quotegrabs} } + 1);
  }

  my $quotegrab = $self->{quotegrabs}[$arguments - 1];
  splice @{ $self->{quotegrabs} }, $arguments - 1, 1;

  for(my $i = $arguments - 1; $i <= $#{ $self->{quotegrabs} }; $i++ ) {
    $self->{quotegrabs}[$i]->{id}--;
  }

  $self->save_quotegrabs();
  return "Deleted $arguments: <$quotegrab->{nick}> $quotegrab->{text}";
}

sub show_quotegrab {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if($arguments < 1 || $arguments > $#{ $self->{quotegrabs} } + 1) {
    return "/msg $nick Valid range for !getq is 1 - " . ($#{ $self->{quotegrabs} } + 1);
  }

  my $quotegrab = $self->{quotegrabs}[$arguments - 1];
  return "$arguments: <$quotegrab->{nick}> $quotegrab->{text}";
}

sub show_random_quotegrab {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my @quotes = ();
  my $nick_search = ".*";
  my $channel_search = $from;
  my $text_search = ".*";

  if(not defined $from) {
    $self->{pbot}->logger->log("Command missing ~from parameter!\n");
    return "";
  }

  if(defined $arguments) {
    ($nick_search, $channel_search, $text_search) = split /\s+/, $arguments;
    if(not defined $channel_search) {
      $channel_search = $from;
    }
  } 

  $nick_search = '.*' if not defined $nick_search;
  $channel_search = '.*' if not defined $channel_search;
  $text_search = '.*' if not defined $text_search;
  
  eval {
    for(my $i = 0; $i <= $#{ $self->{quotegrabs} }; $i++) {
      my $hash = $self->{quotegrabs}[$i];
      if($hash->{channel} =~ /$channel_search/i && $hash->{nick} =~ /$nick_search/i && $hash->{text} =~ /$text_search/i) {
        $hash->{id} = $i + 1;
        push @quotes, $hash;
      }
    }
  };

  if($@) {
    $self->{pbot}->logger->log("Error in show_random_quotegrab parameters: $@\n");
    return "/msg $nick Error in search parameters: $@"
  }
  
  if($#quotes < 0) {
    if($nick_search eq ".*") {
      return "No quotes grabbed in $channel_search yet.  Use !grab to grab a quote.";
    } else {
      return "No quotes grabbed for $nick_search in $channel_search yet.  Use !grab to grab a quote.";
    }
  }

  my $quotegrab = $quotes[int rand($#quotes + 1)];
  return "$quotegrab->{id}: <$quotegrab->{nick}> $quotegrab->{text}";
}

1;
