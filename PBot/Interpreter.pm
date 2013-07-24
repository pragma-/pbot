# File: Interpreter.pm
# Author: pragma_
#
# Purpose: 

package PBot::Interpreter;

use warnings;
use strict;

use base 'PBot::Registerable';

use LWP::UserAgent;
use Carp ();

use vars qw($VERSION);
$VERSION = '1.0.0';

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Interpreter should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->SUPER::initialize(%conf);

  my $pbot = delete $conf{pbot};

  if(not defined $pbot) {
    Carp::croak("Missing pbot reference to PBot::Interpreter");
  }

  $self->{pbot} = $pbot;
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

sub process_line {
  my $self = shift;
  my ($from, $nick, $user, $host, $text) = @_;

  my ($command, $args, $result);
  my $has_url;
  my $has_code;
  my $nick_override;
  my $mynick = $self->pbot->botnick;

  $from = lc $from if defined $from;

  my $pbot = $self->pbot;

  $pbot->antiflood->check_flood($from, $nick, $user, $host, $text, $pbot->{MAX_FLOOD_MESSAGES}, 10, $pbot->antiflood->{FLOOD_CHAT}) if defined $from;

  $text =~ s/^\s+//;
  $text =~ s/\s+$//;
  my $preserve_whitespace = 0;

  my $cmd_text = $text;
  $cmd_text =~ s/^\/me\s+//;

  if($cmd_text =~ /^\Q$pbot->{trigger}\E(.*)$/) {
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
  } elsif($cmd_text =~ /^\s*{\s*(.*)\s*}\s*$/) {
    $has_code = $1 if length $1;
    $preserve_whitespace = 1;
  }

  if(defined $command || defined $has_url || defined $has_code) {
    if((defined $command && $command !~ /^login/i) || defined $has_url || defined $has_code) {
      if(defined $from && $pbot->ignorelist->check_ignore($nick, $user, $host, $from) && not $pbot->admins->loggedin($from, "$nick!$user\@$host")) {
        # ignored hostmask
        $pbot->logger->log("ignored text: [$from][$nick!$user\@$host\[$text\]\n");
        return;
      }
    }

    if(defined $has_url) {
      $result = $self->{pbot}->factoids->{factoidmodulelauncher}->execute_module($from, undef, $nick, $user, $host, "title", "$nick http://$has_url");
    } elsif(defined $has_code) {
      $result = $self->{pbot}->factoids->{factoidmodulelauncher}->execute_module($from, undef, $nick, $user, $host, "compiler_block", (defined $nick_override ? $nick_override : $nick) . " $has_code }");
    } else {
      $result = $self->interpret($from, $nick, $user, $host, 1, $command);
    }

    if(defined $result && length $result > 0) {
      my $original_result = $result;
      $result =~ s/[\n\r]+/ /g;

      if($preserve_whitespace == 0 && defined $command) {
        my ($cmd, $args) = split / /, $command, 2;
        #$self->{pbot}->logger->log("calling find_factoid in Interpreter.pm, process_line() for preserve_whitespace\n");
        my ($chan, $trigger) = $self->{pbot}->factoids->find_factoid($from, $cmd, $args, 0, 1);
        if(defined $trigger) {
          $preserve_whitespace = $self->{pbot}->factoids->factoids->hash->{$chan}->{$trigger}->{preserve_whitespace};
          $preserve_whitespace = 0 if not defined $preserve_whitespace;
        }
      }

      $result =~ s/\s+/ /g unless $preserve_whitespace;

      if(length $result > $pbot->max_msg_len) {
        my $link = paste_sprunge("[" . (defined $from ? $from : "stdin") . "] <$nick> $text\n\n$original_result");
        my $trunc = "... [truncated; see $link for full text.]";
        $pbot->logger->log("Message truncated -- pasted to $link\n");
        
        my $trunc_len = length $result < $pbot->max_msg_len ? length $result : $pbot->max_msg_len;
        $result = substr($result, 0, $trunc_len);
        substr($result, $trunc_len - length $trunc) = $trunc;
      }

      $pbot->logger->log("Final result: $result\n");
      
      if($result =~ s/^\/me\s+//i) {
        $pbot->conn->me($from, $result) if defined $from && $from !~ /\Q$mynick\E/i;
      } elsif($result =~ s/^\/msg\s+([^\s]+)\s+//i) {
        my $to = $1;
        if($to =~ /.*serv$/i) {
          $pbot->logger->log("[HACK] Possible HACK ATTEMPT /msg *serv: [$nick!$user\@$host] [$command] [$result]\n");
        }
        elsif($result =~ s/^\/me\s+//i) {
          $pbot->conn->me($to, $result) if $to !~ /\Q$mynick\E/i;
        } else {
          $result =~ s/^\/say\s+//i;
          $pbot->conn->privmsg($to, $result) if $to !~ /\Q$mynick\E/i;
        }
      } else {
        $pbot->conn->privmsg($from, $result) if defined $from && $from !~ /\Q$mynick\E/i;
      }
    }
    $pbot->logger->log("---------------------------------------------\n");

    # TODO: move this to FactoidModuleLauncher somehow, completely out of Interpreter!
    if($pbot->factoids->{factoidmodulelauncher}->{child} != 0) {
      # if this process is a child, it must die now
      $pbot->logger->log("Terminating module.\n");
      exit 0;
    }
  }
}

sub interpret {
  my $self = shift;
  my ($from, $nick, $user, $host, $count, $command, $tonick) = @_;
  my ($keyword, $arguments) = ("", "");
  my $text;
  my $pbot = $self->pbot;

  $pbot->logger->log("=== Enter interpret_command: [" . (defined $from ? $from : "(undef)") . "][$nick!$user\@$host][$count][$command]\n");

  return "Too many levels of recursion, aborted." if(++$count > 5);

  if(not defined $nick || not defined $user || not defined $host ||
     not defined $command) {
    $pbot->logger->log("Error 1, bad parameters to interpret_command\n");
    return undef;
  }

  if($command =~ /^tell\s+(.{1,20})\s+about\s+(.*?)\s+(.*)$/i) 
  {
    ($keyword, $arguments, $tonick) = ($2, $3, $1);
  } elsif($command =~ /^tell\s+(.{1,20})\s+about\s+(.*)$/i) {
    ($keyword, $tonick) = ($2, $1);
  } elsif($command =~ /^([^ ]+)\s+is\s+also\s+(.*)$/i) {
    ($keyword, $arguments) = ("change", "$1 s|\$| - $2|");
  } elsif($command =~ /^([^ ]+)\s+is\s+(.*)$/i) {
    my ($k, $a) = ($1, $2);

    $self->{pbot}->logger->log("calling find_factoid in Interpreter.pm, interpret() for factadd\n");
    my ($channel, $trigger) = $pbot->factoids->find_factoid($from, $k, $a, 1);
    
    if(defined $trigger) {
      ($keyword, $arguments) = ($k, "is $a");
    } else {
      ($keyword, $arguments) = ("factadd", (defined $from ? $from : '.*' ) . " $k is $a");
    }
  } elsif($command =~ /^(.*?)\s+(.*)$/) {
    ($keyword, $arguments) = ($1, $2);
  } else {
    $keyword = $command;
  }

  if($keyword ne "factadd" and $keyword ne "add" and $keyword ne "msg") {
    $keyword =~ s/(\w+)([?!.]+)$/$1/;
    $arguments =~ s/(\w+)([?!.]+)$/$1/;
    $arguments =~ s/(?<![\w\/\-])me\b/$nick/gi if defined $arguments;
  }

  if(defined $arguments && $arguments =~ m/^(your|him|her|its|it|them|their)(self|selves)$/i) {
    return "Why would I want to do that to myself?";
  }

  if(not defined $keyword) {
    $pbot->logger->log("Error 2, no keyword\n");
    return undef;
  }

  return $self->SUPER::execute_all($from, $nick, $user, $host, $count, $keyword, $arguments, $tonick);
}

sub pbot {
  my $self = shift;
  if(@_) { $self->{pbot} = shift; }
  return $self->{pbot};
}

1;
