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
use Time::Duration;
use Time::HiRes qw(gettimeofday);

use POSIX qw(strftime);

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
  $pbot->commands->register(sub { $self->delete_quotegrab(@_)      },  "delq", 10);
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
  my $table_id = 1;
  my $last_channel = "";
  my $had_table = 0;
  open FILE, "> $self->{export_path}" or return "Could not open export path.";
  my $time = localtime;
  print FILE "<html>\n<head><link href=\"css/blue.css\" rel=\"stylesheet\" type=\"text/css\">\n";
  print FILE '<script type="text/javascript" src="js/jquery-latest.js"></script>' . "\n";
  print FILE '<script type="text/javascript" src="js/jquery.tablesorter.js"></script>' . "\n";
  print FILE "<body><i>Generated at $time</i><hr><h1>Candide's Quotegrabs</h1>\n";
  my $i = 0;
  foreach my $quotegrab (sort { $$a{channel} cmp $$b{channel} or $$a{nick} cmp $$b{nick} } @{ $self->{quotegrabs} }) {
    if(not $quotegrab->{channel} =~ /^$last_channel$/i) {
      print FILE "</tbody>\n</table>\n" if $had_table;
      print FILE "<hr><h2>$quotegrab->{channel}</h2><hr>\n";
      print FILE "<table border=\"0\" id=\"table$table_id\" class=\"tablesorter\">\n";
      print FILE "<thead>\n<tr>\n";
      print FILE "<th>id&nbsp;&nbsp;&nbsp;&nbsp;</th>\n";
      print FILE "<th>author(s)</th>\n";
      print FILE "<th>quote</th>\n";
      print FILE "<th>date</th>\n";
      print FILE "<th>grabbed by</th>\n";
      print FILE "</tr>\n</thead>\n<tbody>\n";
      $had_table = 1;
      $table_id++;
    }

    $last_channel = $quotegrab->{channel};
    $i++;

    if($i % 2) {
      print FILE "<tr bgcolor=\"#dddddd\">\n";
    } else {
      print FILE "<tr>\n";
    }

    print FILE "<td>" . ($quotegrab->{id}) . "</td>";

    my @nicks = split /\+/, $quotegrab->{nick};
    $text = join ', ', sort @nicks;
    print FILE "<td>" . encode_entities($text) . "</td>";

    my $nick;
    $text = $quotegrab->{text};

    if($text =~ s/^\/me\s+//) {
      $nick = "* $nicks[0]";
    } else {
      $nick = "<$nicks[0]>";
    }

    $text = "<td><b>". encode_entities($nick) . "</b> " . encode_entities($text) . "</td>\n"; 
    print FILE $text;
    

    print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %a %H:%M:%S", localtime $quotegrab->{timestamp}) . "</td>\n";
    print FILE "<td>" . encode_entities($quotegrab->{grabbed_by}) . "</td>\n";
    print FILE "</tr>\n";
  }

  print FILE "</tbody>\n</table>\n" if $had_table;
  print FILE "<script type='text/javascript'>\n";
  $table_id--;
  print FILE '$(document).ready(function() {' . "\n";
  while($table_id > 0) {
    print FILE '$("#table' . $table_id . '").tablesorter();' . "\n";
    $table_id--;
  }
  print FILE "});\n";
  print FILE "</script>\n";
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

  if(not defined $arguments or not length $arguments) {
    return "Usage: grab <nick> [history [channel]] -- where [history] is an optional argument that is either an integral number of recent messages or a regex (without whitespace) of the text within the message; e.g., to grab the 3rd most recent message for nick, use `grab nick 3` or to grab a message containing 'pizza', use `grab nick pizza`; and [channel] is an optional channel, so you can use it from /msg (you will need to also specify [history] in this case)";
  }

  $arguments = lc $arguments;

  my @grabs = split /\s\+\s/, $arguments;

  my ($grab_nick, $grab_history, $channel, $grab_nicks, $grab_text);

  foreach my $grab (@grabs) {
    ($grab_nick, $grab_history, $channel) = split(/\s+/, $grab, 3);

    if(not defined $grab_history) {
      $grab_history = $nick eq $grab_nick ? 2 : 1;
    }
    $channel = $from if not defined $channel;

    if($grab_history =~ /^\d+$/ and ($grab_history < 1 || $grab_history > $self->{pbot}->{MAX_NICK_MESSAGES})) {
      return "/msg $nick Please choose a history between 1 and $self->{pbot}->{MAX_NICK_MESSAGES}";
    }

    my $found_mask = undef;
    my $last_spoken = 0;
    foreach my $mask (keys %{ $self->{pbot}->antiflood->message_history }) {
      if($mask =~ m/^\Q$grab_nick\E!/i) {
        if(defined $self->{pbot}->antiflood->message_history->{$mask}->{channels}->{$channel}{last_spoken}
            and $self->{pbot}->antiflood->message_history->{$mask}->{channels}->{$channel}{last_spoken} > $last_spoken) {
          $last_spoken = $self->{pbot}->antiflood->message_history->{$mask}->{channels}->{$channel}{last_spoken};
          $found_mask = $mask;
        }
      }
    }

    if(not defined $found_mask) {
      return "No message history for $grab_nick.";
    }

    if(not exists $self->{pbot}->antiflood->message_history->{$found_mask}->{channels}->{$channel}) {
      return "No message history for $grab_nick in $channel.";
    }

    my @messages = @{ $self->{pbot}->antiflood->message_history->{$found_mask}->{channels}->{$channel}{messages} };

    if($grab_history =~ /^\d+$/) {
      # integral history
      $grab_history--;

      if($grab_history > $#messages) {
        return "$grab_nick has only " . ($#messages + 1) . " messages in the history.";
      }

      $grab_history = $#messages - $grab_history;
    } else {
      # regex history
      my $ret = eval {
        my $i = $#messages;
        $i-- if($nick =~ /^\Q$grab_nick\E$/i); # skip 'grab' command if grabbing own nick
        my $found = 0;
        while($i >= 0) {
          if($messages[$i]->{msg} =~ m/$grab_history/i) {
            $grab_history = $i;
            $found = 1;
            last;
          }
          $i--;
        }

        if($found == 0) {
          return "/msg $nick No message containing regex '$grab_history' found for $grab_nick";
        } else {
          return undef;
        }
      };
      return "/msg $nick Bad grab regex: $@" if $@;
      if(defined $ret) {
        return $ret;
      }
    }

    $self->{pbot}->logger->log("$nick ($from) grabbed <$grab_nick/$channel> $messages[$grab_history]->{msg}\n");

    if(not defined $grab_nicks) {
      $grab_nicks = $grab_nick;
    } else {
      $grab_nicks .= "+$grab_nick";
    }

    my $text = $messages[$grab_history]->{msg};

    if(not defined $grab_text) {
      $grab_text = $text;
    } else {
      if($text =~ s/^\/me\s+//) {
        $grab_text .= "   * $grab_nick $text";
      } else {
        $grab_text .= "   <$grab_nick> $text";
      }
    }
  }

  my $quotegrab = {};
  $quotegrab->{nick} = $grab_nicks;
  $quotegrab->{channel} = $channel;
  $quotegrab->{timestamp} = gettimeofday;
  $quotegrab->{grabbed_by} = "$nick!$user\@$host";
  $quotegrab->{text} = $grab_text;
  $quotegrab->{id} = $#{ $self->{quotegrabs} } + 2;
  
  push @{ $self->{quotegrabs} }, $quotegrab;
  
  $self->save_quotegrabs();
  
  my $text = $quotegrab->{text};
  ($grab_nick) = split /\+/, $grab_nicks, 2;

  if($text =~ s/^\/me\s+//) {
      return "Quote grabbed: " . ($#{ $self->{quotegrabs} } + 1) . ": * $grab_nick $text";
  } else {
      return "Quote grabbed: " . ($#{ $self->{quotegrabs} } + 1) . ": <$grab_nick> $text";
  }
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
    return "/msg $nick Valid range for `getq` is 1 - " . ($#{ $self->{quotegrabs} } + 1);
  }

  my $quotegrab = $self->{quotegrabs}[$arguments - 1];
  splice @{ $self->{quotegrabs} }, $arguments - 1, 1;

  for(my $i = $arguments - 1; $i <= $#{ $self->{quotegrabs} }; $i++ ) {
    $self->{quotegrabs}[$i]->{id}--;
  }

  $self->save_quotegrabs();

  my $text = $quotegrab->{text};

  my ($first_nick) = split /\+/, $quotegrab->{nick}, 2;

  if($text =~ s/^\/me\s+//) {
      return "Deleted $arguments: * $first_nick $text";
  } else {
      return "Deleted $arguments: <$first_nick> $text";
  }
}

sub show_quotegrab {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if($arguments < 1 || $arguments > $#{ $self->{quotegrabs} } + 1) {
    return "/msg $nick Valid range for !getq is 1 - " . ($#{ $self->{quotegrabs} } + 1);
  }

  my $quotegrab = $self->{quotegrabs}[$arguments - 1];
  my $timestamp = $quotegrab->{timestamp};
  my $ago = ago(gettimeofday - $timestamp);
  my $text = $quotegrab->{text};
  my ($first_nick) = split /\+/, $quotegrab->{nick}, 2;

  if($text =~ s/^\/me\s+//) {
      return "$arguments: grabbed by $quotegrab->{grabbed_by} on " . localtime($timestamp) . " [$ago] * $first_nick $text";
  } else {
      return "$arguments: grabbed by $quotegrab->{grabbed_by} on " . localtime($timestamp) . " [$ago] <$first_nick> $text";
  }
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
      return "No quotes grabbed in $channel_search yet (use `rq [nick [channel]]` to specify the correct channel).  Use `grab` to grab a quote.";
    } else {
      return "No quotes grabbed for $nick_search in $channel_search yet (use `rq [nick [channel]]` to specify the correct channel)..  Use `grab` to grab a quote.";
    }
  }

  my $quotegrab = $quotes[int rand($#quotes + 1)];
  my $text = $quotegrab->{text};
  my ($first_nick) = split /\+/, $quotegrab->{nick}, 2;

  if($text =~ s/^\/me\s+//) {
      return "$quotegrab->{id}: * $first_nick $text";
  } else {
      return "$quotegrab->{id}: <$first_nick> $text";
  }
}

1;
