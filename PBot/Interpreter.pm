# File: Interpreter.pm
# Author: pragma_
#
# Purpose: 

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Interpreter;

use warnings;
use strict;

use base 'PBot::Registerable';

use Time::HiRes qw/gettimeofday/;
use Time::Duration;
use LWP::UserAgent;
use Carp ();

use PBot::Utils::ValidateString;

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

  $self->{pbot}->{registry}->add_default('text',  'general', 'compile_blocks',                  $conf{compile_blocks}                  // 1);
  $self->{pbot}->{registry}->add_default('array', 'general', 'compile_blocks_channels',         $conf{compile_blocks_channels}         // '.*');
  $self->{pbot}->{registry}->add_default('array', 'general', 'compile_blocks_ignore_channels',  $conf{compile_blocks_ignore_channels}  // 'none');
  $self->{pbot}->{registry}->add_default('text',  'general', 'paste_ratelimit',                 $conf{paste_ratelimit}                 // 60);
  $self->{pbot}->{registry}->add_default('text',  'interpreter', 'max_recursion',  10);

  $self->{output_queue}  = {};
  $self->{command_queue} = {};
  $self->{last_paste}    = 0;

  $self->{pbot}->{timer}->register(sub { $self->process_output_queue  }, 1);
  $self->{pbot}->{timer}->register(sub { $self->process_command_queue }, 1);
}

sub process_line {
  my $self = shift;
  my ($from, $nick, $user, $host, $text) = @_;

  my $command;
  my $has_code;
  my $nick_override;
  my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');
  my $processed = 0;

  $from = lc $from if defined $from;

  my $stuff = { from => $from, nick => $nick, user => $user, host => $host, text => $text };

  my $pbot = $self->{pbot};

  my $message_account = $pbot->{messagehistory}->get_message_account($nick, $user, $host);
  $pbot->{messagehistory}->add_message($message_account, "$nick!$user\@$host", $from, $text, $pbot->{messagehistory}->{MSG_CHAT});

  $stuff->{message_account} = $message_account;

  my $flood_threshold      = $pbot->{registry}->get_value($from, 'chat_flood_threshold');
  my $flood_time_threshold = $pbot->{registry}->get_value($from, 'chat_flood_time_threshold');

  $flood_threshold      = $pbot->{registry}->get_value('antiflood', 'chat_flood_threshold')      if not defined $flood_threshold;
  $flood_time_threshold = $pbot->{registry}->get_value('antiflood', 'chat_flood_time_threshold') if not defined $flood_time_threshold;

  $pbot->{antiflood}->check_flood($from, $nick, $user, $host, $text,
    $flood_threshold, $flood_time_threshold,
    $pbot->{messagehistory}->{MSG_CHAT}) if defined $from;

  my $preserve_whitespace = 0;

  $text =~ s/^\s+//;
  $text =~ s/\s+$//;
  $text = validate_string($text, 0);

  my $cmd_text = $text;
  $cmd_text =~ s/^\/me\s+//;

  # get channel-specific trigger if available
  my $bot_trigger = $pbot->{registry}->get_value($from, 'trigger');

  if (not defined $bot_trigger) {
    $bot_trigger = $pbot->{registry}->get_value('general', 'trigger');
  }

  my $referenced;
  my $count = 0;
  while (++$count <= 3) {
    $referenced = 0;
    $command = undef;
    $has_code = undef;

    if($cmd_text =~ s/^(?:$botnick.?)?\s*{\s*(.*)\s*}\s*$//) {
      $has_code = $1 if length $1;
      $preserve_whitespace = 1;
      $processed += 100;
    } elsif($cmd_text =~ s/^\s*([^!,:\(\)\+\*\/ ]+)[,:]*\s*{\s*(.*)\s*}\s*$//) {
      $nick_override = $1;
      $has_code = $2 if length $2 and $nick_override !~ /^(?:enum|struct|union)$/;
      $preserve_whitespace = 1;
      $nick_override = $self->{pbot}->{nicklist}->is_present($from, $nick_override);
      $processed += 100;
    } elsif($cmd_text =~ s/^\s*([^!,:\(\)\+\*\/ ]+)[,:]?\s+$bot_trigger[`\{](.+?)[\}`]\s*//) {
      $nick_override = $1;
      $command = $2;

      my $similar = $self->{pbot}->{nicklist}->is_present_similar($from, $nick_override);
      if ($similar) {
        $nick_override = $similar;
      } else {
        $self->{pbot}->{logger}->log("No similar nick for $nick_override\n");
        return 0;
      }

      $cmd_text = "$nick_override: $cmd_text";
      $processed += 100;
    } elsif($cmd_text =~ s/^\s*([^!,:\(\)\+\*\/ ]+)[,:]?\s+$bot_trigger(.+)$//) {
      $nick_override = $1;
      $command = $2;

      my $similar = $self->{pbot}->{nicklist}->is_present_similar($from, $nick_override);
      if ($similar) {
        $nick_override = $similar;
      } else {
        $self->{pbot}->{logger}->log("No similar nick for $nick_override\n");
        return 0;
      }

      $cmd_text = "$nick_override: $cmd_text";
      $processed += 100;
    } elsif($cmd_text =~ s/^$bot_trigger(.*)$//) {
      $command = $1;
      $processed += 100;
    } elsif ($cmd_text =~ s/$bot_trigger`([^`]+)`\s*// || $cmd_text =~ s/$bot_trigger\{([^}]+)\}\s*//) {
      my $cmd = $1;
      my ($nick) = $cmd_text =~ m/^([^ ,:;]+)/;
      $nick = $self->{pbot}->{nicklist}->is_present($from, $nick);
      if ($nick) {
        $command = "tell $nick about $cmd";
      } else {
        $command = $cmd;
      }
      $referenced = 1;
    } elsif($cmd_text =~ s/^.?$botnick.?\s*(.*?)$//i) {
      $command = $1;
      $processed += 100;
    } elsif($cmd_text =~ s/^(.*?),?\s*$botnick[?!.]*$//i) {
      $command = $1;
      $processed += 100;
    }

    last if not defined $command and not defined $has_code;

    if((!defined $command || $command !~ /^login /) && defined $from && $pbot->{ignorelist}->check_ignore($nick, $user, $host, $from)) {
      my $admin = $pbot->{admins}->loggedin($from, "$nick!$user\@$host");
      if (!defined $admin || $admin->{level} < 10) {
        # ignored hostmask
        return 1;
      }
    }

    if(defined $has_code) {
      $processed += 100; # ensure no other plugins try to parse this message
      if($pbot->{registry}->get_value('general', 'compile_blocks') and not $pbot->{registry}->get_value($from, 'no_compile_blocks')
          and not grep { $from =~ /$_/i } $pbot->{registry}->get_value('general', 'compile_blocks_ignore_channels')
          and grep { $from =~ /$_/i } $pbot->{registry}->get_value('general', 'compile_blocks_channels')) {
        if (not defined $nick_override or (defined $nick_override and $self->{pbot}->{nicklist}->is_present($from, $nick_override))) {
          $pbot->{factoids}->{factoidmodulelauncher}->execute_module($from, undef, $nick, $user, $host, $text, "compiler_block", $from, '{', (defined $nick_override ? $nick_override : $nick) . " $from $has_code }", $preserve_whitespace);
        }
      }
    } else {
      $stuff->{text} = $text;
      $stuff->{command} = $command;
      $stuff->{nickoverride} = $nick_override if $nick_override;
      $stuff->{referenced} = $referenced;
      $stuff->{interpret_depth} = 1;
      $stuff->{preserve_whitespace} = $preserve_whitespace;

      my $result = $self->interpret($stuff);
      $stuff->{result} = $result;
      $processed++ if $self->handle_result($stuff, $result);
    }
  }
  return $processed;
}

sub interpret {
  my ($self, $stuff) = @_;
  my ($keyword, $arguments) = ("", "");
  my $text;
  my $pbot = $self->{pbot};

  $pbot->{logger}->log("=== Enter interpret_command: [" . (defined $stuff->{from} ? $stuff->{from} : "(undef)") . "][$stuff->{nick}!$stuff->{user}\@$stuff->{host}][$stuff->{interpret_depth}][$stuff->{command}]\n");

  $stuff->{special} = "";

  if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
    use Data::Dumper;
    $Data::Dumper::Sortkeys  = 1;
    $self->{pbot}->{logger}->log("Interpreter::interpret\n");
    $self->{pbot}->{logger}->log(Dumper $stuff);
  }

  return "Too many levels of recursion, aborted." if(++$stuff->{interpret_depth} > $self->{pbot}->{registry}->get_value('interpreter', 'max_recursion'));

  if (not defined $stuff->{nick} || not defined $stuff->{user} || not defined $stuff->{host} || not defined $stuff->{command}) {
    $pbot->{logger}->log("Error 1, bad parameters to interpret_command\n");
    return undef;
  }

  if ($stuff->{command} =~ /^tell\s+(\p{PosixGraph}{1,20})\s+about\s+(.*?)\s+(.*)$/is) {
    ($keyword, $arguments, $stuff->{nickoverride}) = ($2, $3, $1);
    my $similar = $self->{pbot}->{nicklist}->is_present_similar($stuff->{from}, $stuff->{nickoverride});
    if ($similar) {
      $stuff->{nickoverride} = $similar;
      $stuff->{force_nickoverride} = 1;
    } else {
      delete $stuff->{nickoverride};
    }
  } elsif ($stuff->{command} =~ /^tell\s+(\p{PosixGraph}{1,20})\s+about\s+(.*)$/is) {
    ($keyword, $stuff->{nickoverride}) = ($2, $1);
    my $similar = $self->{pbot}->{nicklist}->is_present_similar($stuff->{from}, $stuff->{nickoverride});
    if ($similar) {
      $stuff->{nickoverride} = $similar;
      $stuff->{force_nickoverride} = 1;
    } else {
      delete $stuff->{nickoverride};
    }
  } elsif ($stuff->{command} =~ /^(.*?)\s+(.*)$/s) {
    ($keyword, $arguments) = ($1, $2);
  } else {
    $keyword = $stuff->{command};
  }

  if (length $keyword > 30) {
    $keyword = substr($keyword, 0, 30);
    $self->{pbot}->{logger}->log("Truncating keyword to 30 chars: $keyword\n");
  }

  # parse out a pipe unless escaped
  if (defined $arguments && $arguments =~ m/(?<!\\)\|\s*\{\s*[^}]+\}\s*$/) {
    $arguments =~ m/(.*?)\s*(?<!\\)\|\s*\{\s*([^}]+)\}(.*)/;
    my ($args, $pipe, $rest) = ($1, $2, $3);
    $pipe =~ s/\s+$//;

    $self->{pbot}->{logger}->log("piping: [$args][$pipe][$rest]\n");

    $stuff->{prepend} = '/say ' unless exists $self->{pipe};

    $arguments = $args;

    if (exists $stuff->{pipe}) {
      $stuff->{pipe_rest} = "$rest | { $stuff->{pipe} }$stuff->{pipe_rest}";
    } else {
      $stuff->{pipe_rest} = $rest;
    }
    $stuff->{pipe} = $pipe;
  }

  # unescape any escaped pipes
  $arguments =~ s/\\\|\s*\{/| {/g if defined $arguments;

  $stuff->{nickoverride} = $stuff->{nick} if defined $stuff->{nickoverride} and lc $stuff->{nickoverride} eq 'me';

  if ($keyword !~ /^(?:factrem|forget|set|factdel|factadd|add|factfind|find|factshow|show|forget|factdel|factset|factchange|change|msg|tell|cc|eval|u|udict|ud|actiontrigger|urban|perl)$/) {
    $keyword =~ s/(\w+)([?!.]+)$/$1/;
    $arguments =~ s/(?<![\w\/\-\\])me\b/$stuff->{nick}/gi if defined $arguments && $stuff->{interpret_depth} <= 2;
    $arguments =~ s/(?<![\w\/\-\\])my\b/$stuff->{nick}'s/gi if defined $arguments && $stuff->{interpret_depth} <= 2;
    $arguments =~ s/\\my\b/my/gi if defined $arguments && $stuff->{interpret_depth} <= 2;
    $arguments =~ s/\\me\b/me/gi if defined $arguments && $stuff->{interpret_depth} <= 2;

    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

    if (defined $arguments && ($arguments =~ m/^(your|him|her|its|it|them|their)(self|selves)$/i || $arguments =~ m/^$botnick$/i)) {
      my $delay = (rand 10) + 8;
      my $message = {
        nick => $stuff->{nick}, user => $stuff->{user}, host => $stuff->{host}, command => $stuff->{command}, checkflood => 1,
        message => "$stuff->{nick}: Why would I want to do that to myself?"
      };
      $self->add_message_to_output_queue($stuff->{from}, $message, $delay);
      $delay = duration($delay);
      $self->{pbot}->{logger}->log("Final result ($delay delay) [$message->{message}]\n");
      return undef;
    }
  }

  if(not defined $keyword) {
    $pbot->{logger}->log("Error 2, no keyword\n");
    return undef;
  }

  if (not exists $stuff->{root_keyword}) {
    $stuff->{root_keyword} = $keyword;
  }

  $stuff->{keyword} = $keyword;
  $stuff->{arguments} = $arguments;

  return $self->SUPER::execute_all($stuff);
}

sub truncate_result {
  my ($self, $from, $nick, $text, $original_result, $result, $paste) = @_;
  my $max_msg_len = $self->{pbot}->{registry}->get_value('irc', 'max_msg_len');

  if(length $result > $max_msg_len) {
    my $link;
    if($paste) {
      $original_result = substr $original_result, 0, 8000;
      $link = $self->paste("[" . (defined $from ? $from : "stdin") . "] <$nick> $text\n\n$original_result");
    } else {
      $link = 'undef';
    }

    my $trunc = "... [truncated; ";
    if ($link =~ m/^http/) {
      $trunc .= "see $link for full text.]";
    } else {
      $trunc .= "$link]";
    }

    $self->{pbot}->{logger}->log("Message truncated -- pasted to $link\n") if $paste;

    my $trunc_len = length $result < $max_msg_len ? length $result : $max_msg_len;
    $result = substr($result, 0, $trunc_len);
    substr($result, $trunc_len - length $trunc) = $trunc;
  }

  return $result;
}

sub handle_result {
  my ($self, $stuff, $result) = @_;

  $stuff->{preserve_whitespace} = 0 if not defined $stuff->{preserve_whitespace};

  if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
    use Data::Dumper;
    $Data::Dumper::Sortkeys  = 1;
    $self->{pbot}->{logger}->log("Interpreter::handle_result [$result]\n");
    $self->{pbot}->{logger}->log(Dumper $stuff);
  }

  $result = $stuff->{result} if not defined $result;

  if (not defined $result or length $result == 0) {
    return 0;
  }

  if ($stuff->{pipe} and not $stuff->{authorized}) {
    my ($pipe, $pipe_rest) = ($stuff->{pipe}, $stuff->{pipe_rest});

    delete $stuff->{pipe};
    delete $stuff->{pipe_rest};

    $self->{pbot}->{logger}->log("Handling pipe [$result][$pipe][$pipe_rest]\n");

    if ($result =~ s{^(/say |/me )}{}i) {
      $stuff->{prepend} = $1;
    }
=cut
    elsif ($result =~ s{^/msg ([^ ]+) }{}i) {
      $stuff->{prepend} = "/msg $1 ";
    }
=cut
    $stuff->{command} = "$pipe $result$pipe_rest";

    $result = $self->interpret($stuff);
    $stuff->{result} = $result;
    $self->handle_result($stuff, $result);
    return 0;
  }

  if ($stuff->{prepend}) {
    # FIXME: do this better
    if ($result =~ m{^(/say |/me )}i) {
#    } elsif ($result =~ m{^/msg ([^ ]+) }i) {
    } elsif ($result =~ m{^/kick }i) {
    } else {
      $result = "$stuff->{prepend}$result";
      $self->{pbot}->{logger}->log("Prepending [$stuff->{prepend}] to result [$result]\n");
    }
  }

  my $original_result = $result;

  my $use_output_queue = 0;

  if (defined $stuff->{command}) {
    my ($cmd, $args) = split /\s+/, $stuff->{command}, 2;
    if (not $self->{pbot}->{commands}->exists($cmd)) {
      my ($chan, $trigger) = $self->{pbot}->{factoids}->find_factoid($stuff->{from}, $cmd, $args, 1, 0, 1);
      if(defined $trigger) {
        if ($stuff->{preserve_whitespace} == 0) {
          $stuff->{preserve_whitespace} = $self->{pbot}->{factoids}->{factoids}->hash->{$chan}->{$trigger}->{preserve_whitespace};
          $stuff->{preserve_whitespace} = 0 if not defined $stuff->{preserve_whitespace};
        }

        $use_output_queue = $self->{pbot}->{factoids}->{factoids}->hash->{$chan}->{$trigger}->{use_output_queue};
        $use_output_queue = 0 if not defined $use_output_queue;
      }
    }
  }

  my $preserve_newlines = $self->{pbot}->{registry}->get_value($stuff->{from}, 'preserve_newlines');

  $result =~ s/[\n\r]/ /g unless $preserve_newlines;
  $result =~ s/[ \t]+/ /g unless $self->{preserve_whitespace};

  my $max_lines = $self->{pbot}->{registry}->get_value($stuff->{from}, 'max_newlines');
  $max_lines = 4 if not defined $max_lines;
  my $lines = 0;

  my $stripped_line;
  foreach my $line (split /[\n\r]+/, $result) {
    $stripped_line = $line;
    $stripped_line =~ s/^\s+//;
    $stripped_line =~ s/\s+$//;
    next if not length $stripped_line;

    if (++$lines >= $max_lines) {
      my $link = $self->paste("[" . (defined $stuff->{from} ? $stuff->{from} : "stdin") . "] <$stuff->{nick}> $stuff->{text}\n\n$original_result");
      if ($use_output_queue) {
        my $message = {
          nick => $stuff->{nick}, user => $stuff->{user}, host => $stuff->{host}, command => $stuff->{command},
          message => "And that's all I have to say about that. See $link for full text.",
          checkflood => $stuff->{checkflood}
        };
        $self->add_message_to_output_queue($stuff->{from}, $message, 0);
      } else {
        $self->{pbot}->{conn}->privmsg($stuff->{from}, "And that's all I have to say about that. See $link for full text.");
      }
      last;
    }

    if ($preserve_newlines) {
      $line = $self->truncate_result($stuff->{from}, $stuff->{nick}, $stuff->{text}, $line, $line, 1);
    } else {
      $line = $self->truncate_result($stuff->{from}, $stuff->{nick}, $stuff->{text}, $original_result, $line, 1);
    }

    if ($use_output_queue) {
      my $delay = (rand 5) + 5;     # initial delay for reading/processing user's message
      $delay += (length $line) / 7; # additional delay of 7 characters per second typing speed
      my $message = {
        nick => $stuff->{nick}, user => $stuff->{user}, host => $stuff->{host}, command => $stuff->{command},
        message => $line, checkflood => $stuff->{checkflood}
      };
      $self->add_message_to_output_queue($stuff->{from}, $message, $delay);
      $delay = duration($delay);
      $self->{pbot}->{logger}->log("Final result ($delay delay) [$line]\n");
    } else {
      $stuff->{line} = $line;
      $self->output_result($stuff);
      $self->{pbot}->{logger}->log("Final result: [$line]\n");
    }
  }
  $self->{pbot}->{logger}->log("---------------------------------------------\n");
  return 1;
}

sub output_result {
  my ($self, $stuff) = @_;
  my ($pbot, $botnick) = ($self->{pbot}, $self->{pbot}->{registry}->get_value('irc', 'botnick'));

  if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
    use Data::Dumper;
    $Data::Dumper::Sortkeys  = 1;
    $self->{pbot}->{logger}->log("Interpreter::output_result\n");
    $self->{pbot}->{logger}->log(Dumper $stuff);
  }

  my $line = $stuff->{line};

  return if not defined $line or not length $line;

  if ($line =~ s/^\/say\s+//i) {
    if (defined $stuff->{nickoverride}) {
      $line = "$stuff->{nickoverride}: $line";
    }
    $pbot->{conn}->privmsg($stuff->{from}, $line) if defined $stuff->{from} && $stuff->{from} !~ /\Q$botnick\E/i;
    $pbot->{antiflood}->check_flood($stuff->{from}, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', $line, 0, 0, 0) if $stuff->{checkflood};
  } elsif ($line =~ s/^\/me\s+//i) {
    if (defined $stuff->{nickoverride}) {
      $line = "$line (for $stuff->{nickoverride})";
    }
    $pbot->{conn}->me($stuff->{from}, $line) if defined $stuff->{from} && $stuff->{from} !~ /\Q$botnick\E/i;
    $pbot->{antiflood}->check_flood($stuff->{from}, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', '/me ' . $line, 0, 0, 0) if $stuff->{checkflood};
  } elsif ($line =~ s/^\/msg\s+([^\s]+)\s+//i) {
    my $to = $1;
    if ($to =~ /,/) {
      $pbot->{logger}->log("[HACK] Possible HACK ATTEMPT /msg multiple users: [$stuff->{nick}!$stuff->{user}\@$stuff->{host}] [$stuff->{command}] [$line]\n");
    } elsif ($to =~ /.*serv$/i) {
      $pbot->{logger}->log("[HACK] Possible HACK ATTEMPT /msg *serv: [$stuff->{nick}!$stuff->{user}\@$stuff->{host}] [$stuff->{command}] [$line]\n");
    } elsif ($line =~ s/^\/me\s+//i) {
      if (defined $stuff->{nickoverride}) {
        $line = "$line (for $stuff->{nickoverride})";
      }
      $pbot->{conn}->me($to, $line) if $to !~ /\Q$botnick\E/i;
      $pbot->{antiflood}->check_flood($to, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', '/me ' . $line, 0, 0, 0) if $stuff->{checkflood};
    } else {
      $line =~ s/^\/say\s+//i;
      if (defined $stuff->{nickoverride}) {
        $line = "$stuff->{nickoverride}: $line";
      }
      $pbot->{conn}->privmsg($to, $line) if $to !~ /\Q$botnick\E/i;
      $pbot->{antiflood}->check_flood($to, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', $line, 0, 0, 0) if $stuff->{checkflood};
    }
  } elsif ($stuff->{authorized} && $line =~ s/^\/kick\s+//) {
    $pbot->{antiflood}->check_flood($stuff->{from}, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', '/kick ' . $line, 0, 0, 0) if $stuff->{checkflood};
    my ($victim, $reason) = split /\s+/, $line, 2;

    if (not defined $reason) {
      if (open my $fh, '<',  $self->{pbot}->{registry}->get_value('general', 'module_dir') . '/insults.txt') {
        my @insults = <$fh>;
        close $fh;
        $reason = $insults[rand @insults];
        chomp $reason;
      } else {
        $reason = 'Bye!';
      }
    }

    if ($self->{pbot}->{chanops}->can_gain_ops($stuff->{from})) {
      $self->{pbot}->{chanops}->add_op_command($stuff->{from}, "kick $stuff->{from} $victim $reason");
      $self->{pbot}->{chanops}->gain_ops($stuff->{from});
    } else {
      $pbot->{conn}->privmsg($stuff->{from}, "$victim: $reason") if defined $stuff->{from} && $stuff->{from} !~ /\Q$botnick\E/i;
    }
  } else {
    if (defined $stuff->{nickoverride}) {
      $line = "$stuff->{nickoverride}: $line";
    }
    $pbot->{conn}->privmsg($stuff->{from}, $line) if defined $stuff->{from} && $stuff->{from} !~ /\Q$botnick\E/i;
    $pbot->{antiflood}->check_flood($stuff->{from}, $botnick, $pbot->{registry}->get_value('irc', 'username'), 'localhost', $line, 0, 0, 0) if $stuff->{checkflood};
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
        my $stuff = {
          from => $channel,
          nick => $message->{nick},
          user => $message->{user},
          host => $message->{host},
          line => $message->{message},
          command => $message->{command},
          checkflood => $message->{checkflood}
        };

        $self->output_result($stuff);
        splice @{$self->{output_queue}->{$channel}}, $i--, 1;
      }
    }

    if (not @{$self->{output_queue}->{$channel}}) {
      delete $self->{output_queue}->{$channel};
    }
  }
}

sub add_to_command_queue {
  my ($self, $channel, $command, $delay) = @_;

  $command->{when} = gettimeofday + $delay;

  push @{$self->{command_queue}->{$channel}}, $command;
}

sub add_botcmd_to_command_queue {
  my ($self, $channel, $command, $delay) = @_;

  my $botcmd = {
    nick => $self->{pbot}->{registry}->get_value('irc', 'botnick'),
    user => 'stdin',
    host => 'localhost',
    command => $command
  };

  $self->add_to_command_queue($channel, $botcmd, $delay);
}

sub process_command_queue {
  my $self = shift;

  foreach my $channel (keys %{$self->{command_queue}}) {
    for (my $i = 0; $i < @{$self->{command_queue}->{$channel}}; $i++) {
      my $command = $self->{command_queue}->{$channel}->[$i];
      if (gettimeofday >= $command->{when}) {
        my $stuff = {
          from => $channel,
          nick => $command->{nick},
          user => $command->{user},
          host => $command->{host},
          command => $command->{command},
          interpret_depth => 0,
          checkflood => 0,
          preserve_whitespace => 0
        };

        my $result = $self->interpret($stuff);
        $stuff->{result} = $result;
        $self->handle_result($stuff, $result);
        splice @{$self->{command_queue}->{$channel}}, $i--, 1;
      }
    }

    if (not @{$self->{command_queue}->{$channel}}) {
      delete $self->{command_queue}->{$channel};
    }
  }
}

sub paste {
  my $self = shift;

  my $rate_limit = $self->{pbot}->{registry}->get_value('general', 'paste_ratelimit');
  my $now = gettimeofday;

  if ($now - $self->{last_paste} < $rate_limit) {
    return "paste rate-limited, try again in " . ($rate_limit - int($now - $self->{last_paste})) . " seconds";
  }

  $self->{last_paste} = $now;

  my $text = join(' ', @_);
  $text =~ s/(.{120})\s/$1\n/g;

  my $result = $self->paste_ixio($text);

  if ($result =~ m/error pasting/) {
    $result = $self->paste_codepad($text);
  }

  return $result;
}

sub paste_ixio {
  my $self = shift;
  my $text = join(' ', @_);

  $text =~ s/(.{120})\s/$1\n/g;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Mozilla/5.0");
  push @{ $ua->requests_redirectable }, 'POST';
  $ua->timeout(10);

  my %post = ('f:1' => $text);
  my $response = $ua->post("http://ix.io", \%post);

  if(not $response->is_success) {
    return "error pasting: " . $response->status_line;
  }

  my $result = $response->content;
  $result =~ s/^\s+//;
  $result =~ s/\s+$//;
  return $result;
}

sub paste_codepad {
  my $self = shift;
  my $text = join(' ', @_);

  $text =~ s/(.{120})\s/$1\n/g;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Mozilla/5.0");
  push @{ $ua->requests_redirectable }, 'POST';
  $ua->timeout(10);

  my %post = ( 'lang' => 'Plain Text', 'code' => $text, 'private' => 'True', 'submit' => 'Submit' );
  my $response = $ua->post("http://codepad.org", \%post);

  if(not $response->is_success) {
    return "error pasting: " . $response->status_line;
  }

  return $response->request->uri;
}

sub paste_sprunge {
  my $self = shift;
  my $text = join(' ', @_);

  $text =~ s/(.{120})\s/$1\n/g;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Mozilla/5.0");
  $ua->requests_redirectable([ ]);
  $ua->timeout(10);

  my %post = ( 'sprunge' => $text, 'submit' => 'Submit' );
  my $response = $ua->post("http://sprunge.us", \%post);

  if(not $response->is_success) {
    return "error pasting: " . $response->status_line;
  }

  my $result = $response->content;
  $result =~ s/^\s+//;
  $result =~ s/\s+$//;
  return $result;
}

1;
