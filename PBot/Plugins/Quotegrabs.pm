# File: Quotegrabs.pm
# Author: pragma_
#
# Purpose: Allows users to "grab" quotes from message history and store them for later retrieval.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Plugins::Quotegrabs;

use warnings;
use strict;

use feature 'unicode_strings';

use HTML::Entities;
use Time::Duration;
use Time::HiRes qw(gettimeofday);
use Getopt::Long qw(GetOptionsFromArray);

use PBot::Plugins::Quotegrabs::Quotegrabs_SQLite;      # use SQLite backend for quotegrabs database
#use PBot::Plugins::Quotegrabs::Quotegrabs_Hashtable;  # use Perl hashtable backend for quotegrabs database
use PBot::Utils::ValidateString;

use POSIX qw(strftime);

sub new {
  if (ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Quotegrabs should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot}        = delete $conf{pbot} // Carp::croak("Missing pbot reference in Quotegrabs");
  $self->{filename}    = delete $conf{quotegrabs_file};
  $self->{export_path} = delete $conf{export_quotegrabs_path};
  $self->{export_site} = delete $conf{export_quotegrabs_site};

  $self->{database} = PBot::Plugins::Quotegrabs::Quotegrabs_SQLite->new(pbot => $self->{pbot}, filename => $self->{filename});
  #$self->{database} = PBot::Plugins::Quotegrabs::Quotegrabs_Hashtable->new(pbot => $self->{pbot}, filename => $self->{filename});
  $self->{database}->begin();

  $self->{pbot}->{atexit}->register(sub { $self->{database}->end(); return; });

  $self->{pbot}->{commands}->register(sub { $self->grab_quotegrab(@_)        },  "grab",  0);
  $self->{pbot}->{commands}->register(sub { $self->show_quotegrab(@_)        },  "getq",  0);
  $self->{pbot}->{commands}->register(sub { $self->delete_quotegrab(@_)      },  "delq",  0);
  $self->{pbot}->{commands}->register(sub { $self->show_random_quotegrab(@_) },  "rq",    0);
}

sub uniq { my %seen; grep !$seen{$_}++, @_ }

sub export_quotegrabs {
  my $self = shift;
  return "Quotegrabs exporting not enabled." if not defined $self->{export_path};

  my $quotegrabs = $self->{database}->get_all_quotegrabs();

  my $text;
  my $table_id = 1;
  my $had_table = 0;
  open FILE, "> $self->{export_path}" or return "Could not open export path.";
  my $time = localtime;
  print FILE "<html>\n<head><link href=\"css/blue.css\" rel=\"stylesheet\" type=\"text/css\">\n";
  print FILE '<script type="text/javascript" src="js/jquery-latest.js"></script>' . "\n";
  print FILE '<script type="text/javascript" src="js/jquery.tablesorter.js"></script>' . "\n";
  print FILE '<script type="text/javascript" src="js/picnet.table.filter.min.js"></script>' . "\n";
  print FILE "</head>\n<body><i>Generated at $time</i><hr><h2>Candide's Quotegrabs</h2>\n";
  my $i = 0;

  my $last_channel = "";
  foreach my $quotegrab (sort { $$a{channel} cmp $$b{channel} or $$a{nick} cmp $$b{nick} } @$quotegrabs) {
    if (not $quotegrab->{channel} =~ /^$last_channel$/i) {
      print FILE "<a href='#" . encode_entities($quotegrab->{channel}) . "'>" . encode_entities($quotegrab->{channel}) . "</a><br>\n";
      $last_channel = $quotegrab->{channel};
    }
  }

  $last_channel = "";
  foreach my $quotegrab (sort { $$a{channel} cmp $$b{channel} or lc $$a{nick} cmp lc $$b{nick} } @$quotegrabs) {
    if (not $quotegrab->{channel} =~ /^$last_channel$/i) {
      print FILE "</tbody>\n</table>\n" if $had_table;
      print FILE "<a name='" . encode_entities($quotegrab->{channel}) . "'></a>\n";
      print FILE "<hr><h3>" . encode_entities($quotegrab->{channel}) . "</h3><hr>\n";
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

    if ($i % 2) {
      print FILE "<tr bgcolor=\"#dddddd\">\n";
    } else {
      print FILE "<tr>\n";
    }

    print FILE "<td>" . ($quotegrab->{id}) . "</td>";

    my @nicks = split /\+/, $quotegrab->{nick};
    $text = join ', ', uniq(@nicks);
    print FILE "<td>" . encode_entities($text) . "</td>";

    my $nick;
    $text = $quotegrab->{text};

    if ($text =~ s/^\/me\s+//) {
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
  while ($table_id > 0) {
    print FILE '$("#table' . $table_id . '").tablesorter();' . "\n";
    print FILE '$("#table' . $table_id . '").tableFilter();' . "\n";
    $table_id--;
  }
  print FILE "});\n";
  print FILE "</script>\n";
  print FILE "</body>\n</html>\n";
  close(FILE);
  return "$i quotegrabs exported to " . $self->{export_site};
}

sub grab_quotegrab {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if (not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  if (not defined $arguments or not length $arguments) {
    return "Usage: grab <nick> [history [channel]] [+ <nick> [history [channel]] ...] -- where [history] is an optional regex argument; e.g., to grab a message containing 'pizza', use `grab nick pizza`; you can chain grabs with + to grab multiple messages";
  }

  $arguments = lc $arguments;

  my @grabs = split /\s\+\s/, $arguments;

  my ($grab_nick, $grab_history, $channel, $grab_nicks, $grab_text);

  foreach my $grab (@grabs) {
    ($grab_nick, $grab_history, $channel) = $self->{pbot}->{interpreter}->split_line($grab, strip_quotes => 1);

    $grab_history = $nick eq $grab_nick ? 2 : 1 if not defined $grab_history; # skip grab command if grabbing self without arguments
    $channel = $from if not defined $channel;

    if (not $channel =~ m/^#/) {
      return "'$channel' is not a valid channel; usage: grab <nick> [[history] channel] (you must specify a history parameter before the channel parameter)";
    }

    my ($account, $found_nick) = $self->{pbot}->{messagehistory}->{database}->find_message_account_by_nick($grab_nick);

    if (not defined $account) {
      return "I don't know anybody named $grab_nick";
    }

    $found_nick =~ s/!.*$//;

    $grab_nick = $found_nick; # convert nick to proper casing

    my $message;

    if ($grab_history =~ /^\d+$/) {
      # integral history
      my $max_messages = $self->{pbot}->{messagehistory}->{database}->get_max_messages($account, $channel);
      if ($grab_history < 1 || $grab_history > $max_messages) {
        return "Please choose a history between 1 and $max_messages";
      }

      $grab_history--;

      $message = $self->{pbot}->{messagehistory}->{database}->recall_message_by_count($account, $channel, $grab_history, 'grab');
    } else {
      # regex history
      $message = $self->{pbot}->{messagehistory}->{database}->recall_message_by_text($account, $channel, $grab_history, 'grab');

      if (not defined $message) {
        return "No such message for nick $grab_nick in channel $channel containing text '$grab_history'";
      }
    }

    $self->{pbot}->{logger}->log("$nick ($from) grabbed <$grab_nick/$channel> $message->{msg}\n");

    if (not defined $grab_nicks) {
      $grab_nicks = $grab_nick;
    } else {
      $grab_nicks .= "+$grab_nick";
    }

    my $text = $message->{msg};

    if (not defined $grab_text) {
      $grab_text = $text;
    } else {
      if ($text =~ s/^\/me\s+//) {
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
  $quotegrab->{text} = validate_string($grab_text);
  $quotegrab->{id} = undef;

  $quotegrab->{id} = $self->{database}->add_quotegrab($quotegrab);

  if (not defined $quotegrab->{id}) {
    return "Failed to grab quote.";
  }

  $self->export_quotegrabs();

  my $text = $quotegrab->{text};
  ($grab_nick) = split /\+/, $grab_nicks, 2;

  if ($text =~ s/^(NICKCHANGE)\b/changed nick to/ or
      $text =~ s/^(KICKED|QUIT)\b/lc "$1"/e or
      $text =~ s/^(JOIN|PART)\b/lc "$1ed"/e) {
    # fix ugly "[nick] quit Quit: Leaving." messages
    $text =~ s/^(quit) (.*)/$1 ($2)/;
    return "Quote grabbed: $quotegrab->{id}: $grab_nick $text";
  } elsif ($text =~ s/^\/me\s+//) {
    return "Quote grabbed: $quotegrab->{id}: * $grab_nick $text";
  } else {
    return "Quote grabbed: $quotegrab->{id}: <$grab_nick> $text";
  }
}

sub delete_quotegrab {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  my $quotegrab = $self->{database}->get_quotegrab($arguments);

  if (not defined $quotegrab) {
    return "/msg $nick No quotegrab matching id $arguments found.";
  }

  if (not $self->{pbot}->{admins}->loggedin($from, "$nick!$user\@$host") and $quotegrab->{grabbed_by} ne "$nick!$user\@$host") {
    return "You are not the grabber of this quote.";
  }

  $self->{database}->delete_quotegrab($arguments);
  $self->export_quotegrabs();

  my $text = $quotegrab->{text};

  my ($first_nick) = split /\+/, $quotegrab->{nick}, 2;

  if ($text =~ s/^\/me\s+//) {
      return "Deleted $arguments: * $first_nick $text";
  } else {
      return "Deleted $arguments: <$first_nick> $text";
  }
}

sub show_quotegrab {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  my $quotegrab = $self->{database}->get_quotegrab($arguments);

  if (not defined $quotegrab) {
    return "/msg $nick No quotegrab matching id $arguments found.";
  }

  my $timestamp = $quotegrab->{timestamp};
  my $ago = ago(gettimeofday - $timestamp);
  my $text = $quotegrab->{text};
  my ($first_nick) = split /\+/, $quotegrab->{nick}, 2;

  if ($text =~ s/^\/me\s+//) {
      return "$arguments: grabbed by $quotegrab->{grabbed_by} in $quotegrab->{channel} on " . localtime($timestamp) . " [$ago] * $first_nick $text";
  } else {
      return "$arguments: grabbed by $quotegrab->{grabbed_by} in $quotegrab->{channel} on " . localtime($timestamp) . " [$ago] <$first_nick> $text";
  }
}

sub show_random_quotegrab {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  my @quotes = ();
  my ($nick_search, $channel_search, $text_search);

  if (not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  my $usage = 'Usage: rq [nick [channel [text]]] [-c <channel>] [-t <text>]';

  if (defined $arguments) {
    my $getopt_error;
    local $SIG{__WARN__} = sub {
      $getopt_error = shift;
      chomp $getopt_error;
    };

    my @opt_args = $self->{pbot}->{interpreter}->split_line($arguments, preserve_escapes => 1, strip_quotes => 1);
    my ($ret, $rest) = GetOptionsFromArray(\@opt_args,
      'channel|c=s' => \$channel_search,
      'text|t=s'    => \$text_search);

    return "$getopt_error -- $usage" if defined $getopt_error;

    $nick_search = shift @opt_args;
    $channel_search = shift @opt_args if not defined $channel_search;
    $text_search = shift @opt_args if not defined $text_search;

    if ($nick_search =~ m/^#/) {
      my $tmp = $channel_search;
      $channel_search = $nick_search;
      $nick_search = $tmp;
    }

    if (not defined $channel_search) {
      $channel_search = $from;
    }
  }

  if (defined $channel_search and $channel_search !~ /^#/) {
    if ($channel_search eq $nick) {
      $channel_search = undef;
    } elsif ($channel_search =~ m/^\./) {
      # do nothing
    } else {
      return "$channel_search is not a valid channel.";
    }
  }

  my $quotegrab = $self->{database}->get_random_quotegrab($nick_search, $channel_search, $text_search);

  if (not defined $quotegrab) {
    my $result = "No quotes grabbed ";

    if (defined $nick_search) {
      $result .= "for nick $nick_search ";
    }

    if (defined $channel_search) {
      $result .= "in channel $channel_search ";
    }

    if (defined $text_search) {
      $result .= "matching text '$text_search' ";
    }

    return $result . "yet ($usage).";;
  }

  my $text = $quotegrab->{text};
  my ($first_nick) = split /\+/, $quotegrab->{nick}, 2;

  if ($text =~ s/^\/me\s+//) {
      return "$quotegrab->{id}: " . (($channel_search eq '.*' or $quotegrab->{channel} ne $from) ? "[$quotegrab->{channel}] " : "") . "* $first_nick $text";
  } else {
      return "$quotegrab->{id}: " . (($channel_search eq '.*' or $quotegrab->{channel} ne $from) ? "[$quotegrab->{channel}] " : "") . "<$first_nick> $text";
  }
}

1;
