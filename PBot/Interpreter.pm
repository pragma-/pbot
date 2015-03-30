# File: Interpreter.pm
# Author: pragma_
#
# Purpose: 

package PBot::Interpreter;

use warnings;
use strict;

use base 'PBot::Registerable';

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use LWP::UserAgent;
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->SUPER::initialize(%conf);

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  $self->{pbot}->{registry}->add_default('text',  'general', 'show_url_titles',                 $conf{show_url_titles}                 // 1);
  $self->{pbot}->{registry}->add_default('array', 'general', 'show_url_titles_channels',        $conf{show_url_titles_channels}        // '.*');
  $self->{pbot}->{registry}->add_default('array', 'general', 'show_url_titles_ignore_channels', $conf{show_url_titles_ignore_channels} // 'none');
  $self->{pbot}->{registry}->add_default('text',  'general', 'compile_blocks',                  $conf{compile_blocks}                  // 1);
  $self->{pbot}->{registry}->add_default('array', 'general', 'compile_blocks_channels',         $conf{compile_blocks_channels}         // '.*');
  $self->{pbot}->{registry}->add_default('array', 'general', 'compile_blocks_ignore_channels',  $conf{compile_blocks_ignore_channels}  // 'none');
  $self->{pbot}->{registry}->add_default('text',  'interpreter', 'max_recursion',  10);

  $self->{output_queue} = {};

  $self->{pbot}->{timer}->register(sub { $self->process_output_queue }, 1);
}

sub process_line {
  my $self = shift;
  my ($from, $nick, $user, $host, $text) = @_;

  my $command;
  my $has_url;
  my $has_code;
  my $nick_override;
  my $mynick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

  $from = lc $from if defined $from;

  my $pbot = $self->{pbot};

  my $message_account = $pbot->{messagehistory}->get_message_account($nick, $user, $host);
  $pbot->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $from, $text, $pbot->{messagehistory}->{MSG_CHAT});

  $pbot->{antiflood}->check_flood($from, $nick, $user, $host, $text,
    $pbot->{registry}->get_value('antiflood', 'chat_flood_threshold'),
    $pbot->{registry}->get_value('antiflood', 'chat_flood_time_threshold'),
    $pbot->{messagehistory}->{MSG_CHAT}) if defined $from;

  $text =~ s/^\s+//;
  $text =~ s/\s+$//;
  my $preserve_whitespace = 0;

  my $cmd_text = $text;
  $cmd_text =~ s/^\/me\s+//;

  # get channel-specific trigger if available
  my $bot_trigger = $pbot->{registry}->get_value($from, 'trigger');

  if (not defined $bot_trigger) {
    $bot_trigger = $pbot->{registry}->get_value('general', 'trigger');
  }

  if($cmd_text =~ /^$bot_trigger?\s*{\s*(.*)\s*}\s*$/) {
    $has_code = $1 if length $1;
    $preserve_whitespace = 1;
  } elsif($cmd_text =~ /^$bot_trigger(.*)$/) {
    $command = $1;
  } elsif($cmd_text =~ /^.?$mynick.?\s+(.*?)$/i) {
    $command = $1;
  } elsif($cmd_text =~ /^(.*?),?\s+$mynick[?!.]*$/i) {
    $command = $1;
  } elsif($cmd_text =~ /https?:\/\/([^\s]+)/i) {
    $has_url = $1;
  } elsif($cmd_text =~ /^\s*([^,:\(\)\+\*\/ ]+)[,:]*\s*{\s*(.*)\s*}\s*$/) {
    $nick_override = $1;
    $has_code = $2 if length $2 and $nick_override ne 'enum' and $nick_override ne 'struct';
    $preserve_whitespace = 1;
  }

  if(defined $command || defined $has_url || defined $has_code) {
    if((defined $command && $command !~ /^login/i) || defined $has_url || defined $has_code) {
      if(defined $from && $pbot->{ignorelist}->check_ignore($nick, $user, $host, $from) && not $pbot->{admins}->loggedin($from, "$nick!$user\@$host")) {
        # ignored hostmask
        $pbot->{logger}->log("ignored message: $from <$nick!$user\@$host> $text\n");
        return;
      }
    }

    if(defined $has_url) {
      if($self->{pbot}->{registry}->get_value('general', 'show_url_titles')
          and not grep { $from =~ /$_/i } $self->{pbot}->{registry}->get_value('general', 'show_url_titles_ignore_channels')
          and grep { $from =~ /$_/i } $self->{pbot}->{registry}->get_value('general', 'show_url_titles_channels')) {
        $self->{pbot}->{factoids}->{factoidmodulelauncher}->execute_module($from, undef, $nick, $user, $host, $text, "title", "$nick http://$has_url", $preserve_whitespace);
      }
    } elsif(defined $has_code) {
      if($self->{pbot}->{registry}->get_value('general', 'compile_blocks')
          and not grep { $from =~ /$_/i } $self->{pbot}->{registry}->get_value('general', 'compile_blocks_ignore_channels')
          and grep { $from =~ /$_/i } $self->{pbot}->{registry}->get_value('general', 'compile_blocks_channels')) {
        $self->{pbot}->{factoids}->{factoidmodulelauncher}->execute_module($from, undef, $nick, $user, $host, $text, "compiler_block", (defined $nick_override ? $nick_override : $nick) . " $from $has_code }", $preserve_whitespace);
      }
    } else {
      $self->handle_result($from, $nick, $user, $host, $text, $command, $self->interpret($from, $nick, $user, $host, 1, $command), 1, $preserve_whitespace); 
    }
  }
}

sub interpret {
  my $self = shift;
  my ($from, $nick, $user, $host, $count, $command, $tonick) = @_;
  my ($keyword, $arguments) = ("", "");
  my $text;
  my $pbot = $self->{pbot};

  $pbot->{logger}->log("=== Enter interpret_command: [" . (defined $from ? $from : "(undef)") . "][$nick!$user\@$host][$count][$command]\n");

  return "Too many levels of recursion, aborted." if(++$count > $self->{pbot}->{registry}->get_value('interpreter', 'max_recursion'));

  if(not defined $nick || not defined $user || not defined $host ||
     not defined $command) {
    $pbot->{logger}->log("Error 1, bad parameters to interpret_command\n");
    return undef;
  }

  if($command =~ /^tell\s+(.{1,20})\s+about\s+(.*?)\s+(.*)$/i) 
  {
    ($keyword, $arguments, $tonick) = ($2, $3, $1);
  } elsif($command =~ /^tell\s+(.{1,20})\s+about\s+(.*)$/i) {
    ($keyword, $tonick) = ($2, $1);
  } elsif($command =~ /^(.*?)\s+(.*)$/) {
    ($keyword, $arguments) = ($1, $2);
  } else {
    $keyword = $command;
  }

  if($keyword ne "factadd" 
      and $keyword ne "add"
      and $keyword ne "factfind"
      and $keyword ne "find"
      and $keyword ne "factshow"
      and $keyword ne "show"
      and $keyword ne "factset"
      and $keyword ne "factchange"
      and $keyword ne "change"
      and $keyword ne "msg") {
    $keyword =~ s/(\w+)([?!.]+)$/$1/;
    $arguments =~ s/(\w+)([?!.]+)$/$1/;
    $arguments =~ s/(?<![\w\/\-])me\b/$nick/gi if defined $arguments;
  }

  if(defined $arguments && $arguments =~ m/^(your|him|her|its|it|them|their)(self|selves)$/i) {
    my $delay = (rand 10) + 8;
    my $message = {
      nick => $nick, user => $user, host => $host, command => $command, checkflood => 1,
      message => "Why would I want to do that to myself?"
    };
    $self->add_message_to_output_queue($from, $message, $delay);
    return undef;
  }

  if(not defined $keyword) {
    $pbot->{logger}->log("Error 2, no keyword\n");
    return undef;
  }

  return $self->SUPER::execute_all($from, $nick, $user, $host, $count, $keyword, $arguments, $tonick);
}

sub truncate_result {
  my ($self, $from, $nick, $text, $original_result, $result, $paste) = @_;
  my $max_msg_len = $self->{pbot}->{registry}->get_value('irc', 'max_msg_len');

  if(length $result > $max_msg_len) {
    my $link;
    if($paste) {
      $link = paste_sprunge("[" . (defined $from ? $from : "stdin") . "] <$nick> $text\n\n$original_result");
    } else {
      $link = 'undef';
    }

    my $trunc = "... [truncated; see $link for full text.]";
    $self->{pbot}->{logger}->log("Message truncated -- pasted to $link\n") if $paste;

    my $trunc_len = length $result < $max_msg_len ? length $result : $max_msg_len;
    $result = substr($result, 0, $trunc_len);
    substr($result, $trunc_len - length $trunc) = $trunc;
  }

  return $result;
}

sub handle_result {
  my ($self, $from, $nick, $user, $host, $text, $command, $result, $checkflood, $preserve_whitespace) = @_;

  if (not defined $result or length $result == 0) {
    return;
  }

  my $original_result = $result;

  my $use_output_queue = 0;

  if (defined $command) {
    my ($cmd, $args) = split / /, $command, 2;
    my ($chan, $trigger) = $self->{pbot}->{factoids}->find_factoid($from, $cmd, $args, 0, 0, 1);
    if(defined $trigger) {
      if ($preserve_whitespace == 0) {
        $preserve_whitespace = $self->{pbot}->{factoids}->{factoids}->hash->{$chan}->{$trigger}->{preserve_whitespace};
        $preserve_whitespace = 0 if not defined $preserve_whitespace;
      }

      $use_output_queue = $self->{pbot}->{factoids}->{factoids}->hash->{$chan}->{$trigger}->{use_output_queue};
      $use_output_queue = 0 if not defined $use_output_queue;
    }
  }

  my $preserve_newlines = $self->{pbot}->{registry}->get_value($from, 'preserve_newlines');

  $result =~ s/[\n\r]/ /g unless $preserve_newlines;
  $result =~ s/[ \t]+/ /g unless $preserve_whitespace;

  my $max_lines = $self->{pbot}->{registry}->get_value($from, 'max_newlines');
  $max_lines = 4 if not defined $max_lines;
  my $lines = 0;

  my $stripped_line;
  foreach my $line (split /[\n\r]+/, $result) {
    $stripped_line = $line;
    $stripped_line =~ s/^\s+//;
    $stripped_line =~ s/\s+$//;
    next if not length $stripped_line;

    if (++$lines >= $max_lines) {
      my $link = paste_sprunge("[" . (defined $from ? $from : "stdin") . "] <$nick> $text\n\n$original_result");
      if ($use_output_queue) {
        my $message = {
          nick => $nick, user => $user, host => $host, command => $command,
          message => "And that's all I have to say about that. See $link for full text.",
          checkflood => $checkflood
        };
        $self->add_message_to_output_queue($from, $message, 0);
      } else {
        $self->{pbot}->{conn}->privmsg($from, "And that's all I have to say about that. See $link for full text.");
      }
      last;
    }

    if ($preserve_newlines) {
      $line = $self->truncate_result($from, $nick, $text, $line, $line, 1);
    } else {
      $line = $self->truncate_result($from, $nick, $text, $original_result, $line, 1);
    }

    if ($use_output_queue) {
      my $delay = (rand 10) + 5;    # initial delay for reading/processing user's message
      $delay += (length $line) / 7; # additional delay of 7 characters per second typing speed
      my $message = {
        nick => $nick, user => $user, host => $host, command => $command,
        message => $line, checkflood => $checkflood
      };
      $self->add_message_to_output_queue($from, $message, $delay);
      $delay = duration($delay);
      $self->{pbot}->{logger}->log("Final result ($delay delay) [$line]\n");
    } else {
      $self->output_result($from, $nick, $user, $host, $command, $line, $checkflood);
      $self->{pbot}->{logger}->log("Final result: [$line]\n");
    }
  }
  $self->{pbot}->{logger}->log("---------------------------------------------\n");
}

sub output_result {
  my ($self, $from, $nick, $user, $host, $command, $line, $checkflood) = @_;
  my ($pbot, $mynick) = ($self->{pbot}, $self->{pbot}->{registry}->get_value('irc', 'botnick'));

  if($line =~ s/^\/say\s+//i) {
    $pbot->{conn}->privmsg($from, $line) if defined $from && $from !~ /\Q$mynick\E/i;
    $pbot->{antiflood}->check_flood($from, $mynick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', $line, 0, 0, 0) if $checkflood;
  } elsif($line =~ s/^\/me\s+//i) {
    $pbot->{conn}->me($from, $line) if defined $from && $from !~ /\Q$mynick\E/i;
    $pbot->{antiflood}->check_flood($from, $mynick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', '/me ' . $line, 0, 0, 0) if $checkflood;
  } elsif($line =~ s/^\/msg\s+([^\s]+)\s+//i) {
    my $to = $1;
    if($to =~ /,/) {
      $pbot->{logger}->log("[HACK] Possible HACK ATTEMPT /msg multiple users: [$nick!$user\@$host] [$command] [$line]\n");
    }
    elsif($to =~ /.*serv$/i) {
      $pbot->{logger}->log("[HACK] Possible HACK ATTEMPT /msg *serv: [$nick!$user\@$host] [$command] [$line]\n");
    }
    elsif($line =~ s/^\/me\s+//i) {
      $pbot->{conn}->me($to, $line) if $to !~ /\Q$mynick\E/i;
      $pbot->{antiflood}->check_flood($to, $mynick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', '/me ' . $line, 0, 0, 0) if $checkflood;
    } else {
      $line =~ s/^\/say\s+//i;
      $pbot->{conn}->privmsg($to, $line) if $to !~ /\Q$mynick\E/i;
      $pbot->{antiflood}->check_flood($to, $mynick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', $line, 0, 0, 0) if $checkflood;
    }
  } else {
    $pbot->{conn}->privmsg($from, $line) if defined $from && $from !~ /\Q$mynick\E/i;
    $pbot->{antiflood}->check_flood($from, $mynick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', $line, 0, 0, 0) if $checkflood;
  }
}

sub add_message_to_output_queue {
  my ($self, $channel, $message, $delay) = @_;

  if (exists $self->{output_queue}->{$channel}) {
    my $last_when = $self->{output_queue}->{$channel}->[-1]->{when};
    $message->{when} = $last_when + $delay;
  } else {
    $message->{when} = gettimeofday + $delay;
  }

  push @{$self->{output_queue}->{$channel}}, $message;
}

sub process_output_queue {
  my $self = shift;

  foreach my $channel (keys %{$self->{output_queue}}) {
    for (my $i = 0; $i < @{$self->{output_queue}->{$channel}}; $i++) {
      my $message = $self->{output_queue}->{$channel}->[$i];
      if (gettimeofday >= $message->{when}) {
        $self->output_result($channel, $message->{nick}, $message->{user}, $message->{host}, $message->{command}, $message->{message}, $message->{checkflood});
        splice @{$self->{output_queue}->{$channel}}, $i--, 1;
      }
    }

    if (not @{$self->{output_queue}->{$channel}}) {
      delete $self->{output_queue}->{$channel};
    }
  }
}

sub paste_codepad {
  my $text = join(' ', @_);

  $text =~ s/(.{120})\s/$1\n/g;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Mozilla/5.0");
  push @{ $ua->requests_redirectable }, 'POST';

  my %post = ( 'lang' => 'Plain Text', 'code' => $text, 'private' => 'True', 'submit' => 'Submit' );
  my $response = $ua->post("http://codepad.org", \%post);

  if(not $response->is_success) {
    return $response->status_line;
  }

  return $response->request->uri;
}

sub paste_sprunge {
  my $text = join(' ', @_);

  $text =~ s/(.{120})\s/$1\n/g;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Mozilla/5.0");
  $ua->requests_redirectable([ ]);

  my %post = ( 'sprunge' => $text, 'submit' => 'Submit' );
  my $response = $ua->post("http://sprunge.us", \%post);

  if(not $response->is_success) {
    return $response->status_line;
  }

  my $result = $response->content;
  $result =~ s/^\s+//;
  $result =~ s/\s+$//;
  return $result;
}

1;
