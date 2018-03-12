#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use warnings;
use strict;
use feature "switch";

no if $] >= 5.018, warnings => "experimental::smartmatch";

package _default;

use IPC::Open2;
use IO::Socket;
use LWP::UserAgent;
use Time::HiRes qw/gettimeofday/;
use Text::Balanced qw/extract_delimited/;
use JSON;

my $EXECUTE_PORT = '3333';

sub new {
  my ($class, %conf) = @_;
  my $self = bless {}, $class;

  $self->{debug}       = $conf{debug} // 0;
  $self->{nick}        = $conf{nick};
  $self->{channel}     = $conf{channel};
  $self->{lang}        = $conf{lang};
  $self->{code}        = $conf{code};
  $self->{max_history} = $conf{max_history} // 10000;
  $self->{arguments}   = $conf{arguments};
  $self->{factoid}     = $conf{factoid};
  $self->{'persist-key'} = $conf{'persist-key'};

  $self->{default_options} = '';
  $self->{cmdline}         = 'echo Hello, world!';

  # remove leading and trailing whitespace
  $self->{nick}    =~ s/^\s+|\s+$//g if defined $self->{nick};
  $self->{channel} =~ s/^\s+|\s+$//g if defined $self->{channel};
  $self->{lang}    =~ s/^\s+|\s+$//g if defined $self->{lang};
  $self->{code}    =~ s/^\s+|\s+$//g if defined $self->{code};

  if (defined $self->{arguments}) {
    $self->{arguments} = quotemeta $self->{arguments};
    $self->{arguments} =~ s/\\ / /g;
  }

  $self->initialize(%conf);

  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
}

sub pretty_format {
  my $self = shift;
  return $self->{code};
}

sub preprocess_code {
  my $self = shift;

  if ($self->{only_show}) {
    print "$self->{code}\n";
    exit;
  }

  unless($self->{got_run} and $self->{copy_code}) {
    open FILE, ">> log.txt";
    print FILE localtime() . "\n";
    print FILE "$self->{nick} $self->{channel}: " . $self->{cmdline_options} . "$self->{code}\n";
    close FILE;
  }

  # replace \n outside of quotes with literal newline
  my $new_code = "";

  use constant {
    NORMAL        => 0,
    DOUBLE_QUOTED => 1,
    SINGLE_QUOTED => 2,
  };

  my $state = NORMAL;
  my $escaped = 0;

  while($self->{code} =~ m/(.)/gs) {
    my $ch = $1;

    given ($ch) {
      when ('\\') {
        if($escaped == 0) {
          $escaped = 1;
          next;
        }
      }

      if($state == NORMAL) {
        when ($_ eq '"' and not $escaped) {
          $state = DOUBLE_QUOTED;
        }

        when ($_ eq "'" and not $escaped) {
          $state = SINGLE_QUOTED;
        }

        when ($_ eq 'n' and $escaped == 1) {
          $ch = "\n";
          $escaped = 0;
        }
      }

      if($state == DOUBLE_QUOTED) {
        when ($_ eq '"' and not $escaped) {
          $state = NORMAL;
        }
      }

      if($state == SINGLE_QUOTED) {
        when ($_ eq "'" and not $escaped) {
          $state = NORMAL;
        }
      }
    }

    $new_code .= '\\' and $escaped = 0 if $escaped;
    $new_code .= $ch;
  }

  $self->{code} = $new_code;
}

sub postprocess_output {
  my $self = shift;

  unless($self->{got_run} and $self->{copy_code}) {
    open FILE, ">> log.txt";
    print FILE "------------------------------------------------------------------------\n";
    print FILE localtime() . "\n";
    print FILE "$self->{output}\n";
    close FILE;
  }

  # backspace
  my $boutput = "";
  my $active_position = 0;
  $self->{output} =~ s/\n$//;
  while($self->{output} =~ /(.)/gms) {
    my $c = $1;
    if($c eq "\b") {
      if(--$active_position <= 0) {
        $active_position = 0;
      }
      next;
    }
    substr($boutput, $active_position++, 1) = $c;
  }
  $self->{output} = $boutput;

  my @beeps = qw/*BEEP* *BING* *DING* *DONG* *CLUNK* *BONG* *PING* *BOOP* *BLIP* *BOP* *WHIRR*/;

  $self->{output} =~ s/\007/$beeps[rand @beeps]/g;
}

sub show_output {
  my $self = shift;
  my $output = $self->{output};

  unless ($self->{got_run} and $self->{copy_code}) {
    open FILE, ">> log.txt";
    print FILE "------------------------------------------------------------------------\n";
    print FILE localtime() . "\n";
    print FILE "$output\n";
    print FILE "========================================================================\n";
    close FILE;
  }

  if (exists $self->{options}->{'-paste'} or (defined $self->{got_run} and $self->{got_run} eq 'paste')) {
    my $cmdline = $self->{cmdline};

    $cmdline =~ s/\$sourcefile/$self->{sourcefile}/g;
    $cmdline =~ s/\$execfile/$self->{execfile}/g;

    my $options;
    if (length $self->{cmdline_options}) {
      $options = $self->{cmdline_options};
    } else {
      $options = $self->{default_options};
    }

    if (exists $self->{options_paste}) {
      $options .= ' ' if length $options;
      $options .= $self->{options_paste};
    }

    if (length $options) {
      $cmdline =~ s/\$options/$options/;
    } else {
      $cmdline =~ s/\$options\s+//;
    }

    my $pretty_code = $self->pretty_format($self->{code});

    my $cmdline_opening_comment = $self->{cmdline_opening_comment} // "/************* CMDLINE *************\n";
    my $cmdline_closing_comment = $self->{cmdline_closing_comment} // "************** CMDLINE *************/\n";

    my $output_opening_comment = $self->{output_opening_comment} // "/************* OUTPUT *************\n";
    my $output_closing_comment = $self->{output_closing_comment} // "************** OUTPUT *************/\n";

    $pretty_code .= "\n\n";
    $pretty_code .= $cmdline_opening_comment;
    $pretty_code .= "$cmdline\n";
    $pretty_code .= $cmdline_closing_comment;

    $output =~ s/\s+$//;
    $pretty_code .= "\n";
    $pretty_code .= $output_opening_comment;
    $pretty_code .= "$output\n";
    $pretty_code .= $output_closing_comment;

    my $uri = $self->paste_ixio($pretty_code);

    if (not $uri =~ m/^http/) {
      $uri = $self->paste_ptpb($pretty_code);
    }

    print "$uri\n";
    exit 0;
  }

  if($self->{channel} =~ m/^#/ and length $output > 22 and open FILE, "< history/$self->{channel}-$self->{lang}.last-output") {
    my $last_output;
    my $time = <FILE>;

    if(gettimeofday - $time > 60 * 4) {
      close FILE;
    } else {
      while(my $line = <FILE>) {
        $last_output .= $line;
      }
      close FILE;

      if((not $self->{factoid}) and defined $last_output and $last_output eq $output) {
        print "Same output.\n";
        exit 0;
      }
    }
  }

  print "$output\n";

  open FILE, "> history/$self->{channel}-$self->{lang}.last-output" or die "Couldn't open $self->{channel}-$self->{lang}.last-output: $!";
  my $now = gettimeofday;
  print FILE "$now\n";
  print FILE "$output";
  close FILE;
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

sub paste_ptpb {
  my $self = shift;
  my $text = join(' ', @_);

  $text =~ s/(.{120})\s/$1\n/g;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Mozilla/5.0");
  $ua->requests_redirectable([ ]);
  $ua->timeout(10);

  my %post = ( 'c' => $text, 'submit' => 'Submit' );
  my $response = $ua->post("https://ptpb.pw/?u=1", \%post);

  if(not $response->is_success) {
    return "error pasting: " . $response->status_line;
  }

  my $result = $response->content;
  $result =~ s/^\s+//;
  $result =~ s/\s+$//;
  return $result;
}

sub execute {
  my ($self) = @_;

  my ($compiler, $compiler_output, $pid);

  delete $self->{local};
  if(exists $self->{local} and $self->{local} != 0) {
    print "Using local compiler instead of virtual machine\n";
    $pid = open2($compiler_output, $compiler, './compiler_vm_server.pl') || die "repl failed: $@\n";
    print "Started compiler, pid: $pid\n";
  } else {
    $compiler  = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $EXECUTE_PORT, Proto => 'tcp', Type => SOCK_STREAM);
    die "Could not create socket: $!" unless $compiler;
    $compiler_output = $compiler;
  }

  my $date = time;
  my $input = $self->{options}->{'-input'};

  if (not length $input) {
    $input = `fortune -u -s`;
    $input =~ s/[\n\r\t]/ /msg;
    $input =~ s/:/ - /g;
    $input =~ s/\s+/ /g;
    $input =~ s/^\s+//;
    $input =~ s/\s+$//;
  }

  my $pretty_code = $self->pretty_format($self->{code});

  my $cmdline = $self->{cmdline};

  $cmdline =~ s/\$sourcefile/$self->{sourcefile}/g;
  $cmdline =~ s/\$execfile/$self->{execfile}/g;

  my $options;
  if (length $self->{cmdline_options}) {
    $options = $self->{cmdline_options};
  } else {
    $options = $self->{default_options};
  }

  if ((not exists $self->{options}->{'-paste'}) and (not defined $self->{got_run} or $self->{got_run} ne 'paste')) {
    if (exists $self->{options_nopaste}) {
      $options .= ' ' if length $options;
      $options .= $self->{options_nopaste};
    }
  } else {
    if (exists $self->{options_paste}) {
      $options .= ' ' if length $options;
      $options .= $self->{options_paste};
    }
  }

  if (length $options) {
    $cmdline =~ s/\$options/$options/;
  } else {
    $cmdline =~ s/\$options\s+//;
  }

  open FILE, ">> log.txt";
  print FILE "------------------------------------------------------------------------\n";
  print FILE localtime() . "\n";
  print FILE "$cmdline\n$input\n$pretty_code\n";

  my $compile_in = { lang => $self->{lang}, sourcefile => $self->{sourcefile}, execfile => $self->{execfile},
    cmdline => $cmdline, input => $input, date => $date, arguments => $self->{arguments}, code => $pretty_code };

  $compile_in->{'factoid'} = $self->{'factoid'} if length $self->{'factoid'};
  $compile_in->{'persist-key'} = $self->{'persist-key'} if length $self->{'persist-key'};

  my $compile_json = encode_json($compile_in);
  $compile_json .= "\n:end:\n";

  my $length = length $compile_json;
  my $sent = 0;
  my $chunk_max = 4096;
  my $chunk_size = $length < $chunk_max ? $length : $chunk_max;
  my $chunks_sent;

  #print FILE "Sending $length bytes [$compile_json] to vm_server\n";

  $chunk_size -= 1; # account for newline in syswrite

  while ($chunks_sent < $length) {
    my $chunk = substr $compile_json, $chunks_sent, $chunk_size;
    #print FILE "Sending chunk [$chunk]\n";
    $chunks_sent += length $chunk;

    my $ret = syswrite($compiler, "$chunk\n");

    if (not defined $ret) {
      print FILE "Error sending: $!\n";
      last;
    }

    if ($ret == 0) {
      print FILE "Sent 0 bytes. Sleep 1 sec and try again\n";
      sleep 1;
      next;
    }

    $sent += $ret;
    print FILE "Sent $ret bytes, so far $sent ...\n";
  }

  #print FILE "Done sending!\n";
  close FILE;

  my $result = "";
  my $got_result = 0;

  while(my $line = <$compiler_output>) {

    #print STDERR "Read [$line]\n";

    $line =~ s/[\r\n]+$//;
    last if $line =~ /^result:end$/;

    if($line =~ /^result:/) {
      $line =~ s/^result://;
      my $compile_out = decode_json($line);
      $result .= "$compile_out->{result}\n";
      $got_result = 1;
      next;
    }

    if($got_result) {
      $result .= "$line\n";
    }
  }

  close $compiler;
  waitpid($pid, 0) if defined $pid;

  $self->{output} = $result;

  return $result;
}

sub add_option {
  my $self = shift;
  my ($option, $value) = @_;

  $self->{options_order} = [] if not exists $self->{options_order};

  $self->{options}->{$option} = $value;
  push @{$self->{options_order}}, $option;
}

sub process_standard_options {
  my $self = shift;
  my $code = $self->{code};

  if ($code =~ s/(?:^|(?<=\s))-info\s*//i) {
    my $cmdline = $self->{cmdline};
    if (length $self->{default_options}) {
      $cmdline =~ s/\$options/$self->{default_options}/;
    } else {
      $cmdline =~ s/\$options\s+//;
    }
    $cmdline =~ s/\$sourcefile/$self->{sourcefile}/g;
    $cmdline =~ s/\$execfile/$self->{execfile}/g;
    my $name = exists $self->{name} ? $self->{name} : $self->{lang};
    print "$name cmdline: $cmdline\n";
    exit;
  }

  if ($code =~ s/-(?:input|stdin)=(.*)$//i) {
    $self->add_option("-input", $1);
  }

  if ($code =~ s/(?:^|(?<=\s))-paste\s*//i) {
    $self->add_option("-paste");
  }

  $self->{code} = $code;
}

sub process_custom_options {
}

sub process_cmdline_options {
  my $self = shift;
  my $code = $self->{code};

  $self->{cmdline_options} = "";

  while ($code =~ s/^\s*(-[^ ]+)\s*//) {
    $self->{cmdline_options} .= "$1 ";
    $self->add_option($1);
  }

  $self->{cmdline_options} =~ s/\s$//;

  $self->{code} = $code;
}

sub process_interactive_edit {
  my $self = shift;
  my $code = $self->{code};
  my (@last_code, $unshift_last_code);

  print "      code: [$code]\n" if $self->{debug};

  my $subcode = $code;
  while ($subcode =~ s/^\s*(-[^ ]+)\s*//) {}

  my $copy_code;
  if($subcode =~ s/^\s*copy\s+(\S+)\s*//) {
    my $copy = $1;

    if(open FILE, "< history/$copy-$self->{lang}.hist") {
      $copy_code = <FILE>;
      close FILE;
      goto COPY_ERROR if not $copy_code;;
      chomp $copy_code;
    } else {
      goto COPY_ERROR;
    }

    goto COPY_SUCCESS;

    COPY_ERROR:
    print "No history for $copy.\n";
    exit 0;

    COPY_SUCCESS:
    $code = $copy_code;
    $self->{only_show} = 1;
    $self->{copy_code} = 1;
  }

  if($subcode =~ m/^\s*(?:and\s+)?(?:diff|show)\s+(\S+)\s*$/) {
    $self->{channel} = $1;
  }

  if(open FILE, "< history/$self->{channel}-$self->{lang}.hist") {
    while(my $line = <FILE>) {
      chomp $line;
      push @last_code, $line;
    }
    close FILE;
  }

  unshift @last_code, $copy_code if defined $copy_code;

  if($subcode =~ m/^\s*(?:and\s+)?show(?:\s+\S+)?\s*$/i) {
    if(defined $last_code[0]) {
      print "$last_code[0]\n";
    } else {
      print "No recent code to show.\n"
    }
    exit 0;
  }

  my $prevchange = $last_code[0];
  my @replacements;
  my $got_changes = 0;
  my $got_sub = 0;
  my $got_diff = 0;
  my $got_undo = 0;
  my $last_keyword;

  while($subcode =~ s/^\s*(and)?\s*undo//) {
    splice @last_code, 0, 1;
    if(not defined $last_code[0]) {
      print "No more undos remaining.\n";
      exit 0;
    } else {
      $code = $last_code[0];
      $prevchange = $last_code[0];
      $got_undo = 1;
    }
  }

  while(1) {
    $got_sub = 0;

    $subcode =~ s/^\s*and\s+'/and $last_keyword '/ if defined $last_keyword;

    if($subcode =~ m/^\s*(?:and\s+)?diff\b/i) {
      $got_diff = 1;
      last;
    }

    if($subcode =~ m/^\s*(?:and\s+)?(again|run|paste)\b/i) {
      $self->{got_run} = lc $1;
      $self->{only_show} = 0;
      if ($prevchange) {
        $code = $prevchange;
      } else {
        print "No recent code to $self->{got_run}.\n";
        exit 0;
      }
    } 

    if($subcode =~ m/^\s*(and)?\s*remove \s*([^']+)?\s*'/) {
      $last_keyword = 'remove';
      my $modifier = 'first';

      $subcode =~ s/^\s*(and)?\s*//;
      $subcode =~ s/remove\s*([^']+)?\s*//i;
      $modifier = $1 if defined $1;
      $modifier =~ s/\s+$//;

      my ($e, $r) = extract_delimited($subcode, "'");

      my $text;

      if(defined $e) {
        $text = $e;
        $text =~ s/^'//;
        $text =~ s/'$//;
        $subcode = "replace $modifier '$text' with ''$r";
      } else {
        print "Unbalanced single quotes.  Usage: cc remove [all, first, .., tenth, last] 'text' [and ...]\n";
        exit 0;
      }
      next;
    }

    if($subcode =~ s/^\s*(and)?\s*prepend '//) {
      $last_keyword = 'prepend';
      $subcode = "'$subcode";

      my ($e, $r) = extract_delimited($subcode, "'");

      my $text;

      if(defined $e) {
        $text = $e;
        $text =~ s/^'//;
        $text =~ s/'$//;
        $subcode = $r;

        $got_sub = 1;
        $got_changes = 1;

        if(not defined $prevchange) {
          print "No recent code to prepend to.\n";
          exit 0;
        }

        $code = $prevchange;
        $code =~ s/^/$text /;
        $prevchange = $code;
      } else {
        print "Unbalanced single quotes.  Usage: cc prepend 'text' [and ...]\n";
        exit 0;
      }
      next;
    }

    if($subcode =~ s/^\s*(and)?\s*append '//) {
      $last_keyword = 'append';
      $subcode = "'$subcode";

      my ($e, $r) = extract_delimited($subcode, "'");

      my $text;

      if(defined $e) {
        $text = $e;
        $text =~ s/^'//;
        $text =~ s/'$//;
        $subcode = $r;

        $got_sub = 1;
        $got_changes = 1;

        if(not defined $prevchange) {
          print "No recent code to append to.\n";
          exit 0;
        }

        $code = $prevchange;
        $code =~ s/$/ $text/;
        $prevchange = $code;
      } else {
        print "Unbalanced single quotes.  Usage: cc append 'text' [and ...]\n";
        exit 0;
      }
      next;
    }

    if($subcode =~ m/^\s*(and)?\s*replace\s*([^']+)?\s*'.*'\s*with\s*'.*?'/i) {
      $last_keyword = 'replace';
      $got_sub = 1;
      my $modifier = 'first';

      $subcode =~ s/^\s*(and)?\s*//;
      $subcode =~ s/replace\s*([^']+)?\s*//i;
      $modifier = $1 if defined $1;
      $modifier =~ s/\s+$//;

      my ($from, $to);
      my ($e, $r) = extract_delimited($subcode, "'");

      if(defined $e) {
        $from = $e;
        $from =~ s/^'//;
        $from =~ s/'$//;
        $from = quotemeta $from;
        $from =~ s/\\ / /g;
        $subcode = $r;
        $subcode =~ s/\s*with\s*//i;
      } else {
        print "Unbalanced single quotes.  Usage: cc replace 'from' with 'to' [and ...]\n";
        exit 0;
      }

      ($e, $r) = extract_delimited($subcode, "'");

      if(defined $e) {
        $to = $e;
        $to =~ s/^'//;
        $to =~ s/'$//;
        $subcode = $r;
      } else {
        print "Unbalanced single quotes.  Usage: cc replace 'from' with 'to' [and replace ... with ... [and ...]]\n";
        exit 0;
      }

      given($modifier) {
        when($_ eq 'all'    ) {}
        when($_ eq 'last'   ) {}
        when($_ eq 'first'  ) { $modifier = 1; }
        when($_ eq 'second' ) { $modifier = 2; }
        when($_ eq 'third'  ) { $modifier = 3; }
        when($_ eq 'fourth' ) { $modifier = 4; }
        when($_ eq 'fifth'  ) { $modifier = 5; }
        when($_ eq 'sixth'  ) { $modifier = 6; }
        when($_ eq 'seventh') { $modifier = 7; }
        when($_ eq 'eighth' ) { $modifier = 8; }
        when($_ eq 'nineth' ) { $modifier = 9; }
        when($_ eq 'tenth'  ) { $modifier = 10; }
        default { print "Bad replacement modifier '$modifier'; valid modifiers are 'all', 'first', 'second', ..., 'tenth', 'last'\n"; exit 0; }
      }

      my $replacement = {};
      $replacement->{'from'} = $from;
      $replacement->{'to'} = $to;
      $replacement->{'modifier'} = $modifier;

      push @replacements, $replacement;
      next;
    }

    if($subcode =~ m/^\s*(and)?\s*s\/.*\//) {
      $last_keyword = undef;
      $got_sub = 1;
      $subcode =~ s/^\s*(and)?\s*s//;

      my ($regex, $to);
      my ($e, $r) = extract_delimited($subcode, '/');

      if(defined $e) {
        $regex = $e;
        $regex =~ s/^\///;
        $regex =~ s/\/$//;
        $subcode = "/$r";
      } else {
        print "Unbalanced slashes.  Usage: cc s/regex/substitution/[gi] [and s/.../.../ [and ...]]\n";
        exit 0;
      }

      ($e, $r) = extract_delimited($subcode, '/');

      if(defined $e) {
        $to = $e;
        $to =~ s/^\///;
        $to =~ s/\/$//;
        $subcode = $r;
      } else {
        print "Unbalanced slashes.  Usage: cc s/regex/substitution/[gi] [and s/.../.../ [and ...]]\n";
        exit 0;
      }

      my $suffix;
      $suffix = $1 if $subcode =~ s/^([^ ]+)//;

      if(length $suffix and $suffix =~ m/[^gi]/) {
        print "Bad regex modifier '$suffix'.  Only 'i' and 'g' are allowed.\n";
        exit 0;
      }
      if(defined $prevchange) {
        $code = $prevchange;
      } else {
        print "No recent code to change.\n";
        exit 0;
      }

      my $ret = eval {
        my ($ret, $a, $b, $c, $d, $e, $f, $g, $h, $i, $before, $after);

        if(not length $suffix) {
          $ret = $code =~ s|$regex|$to|;
          ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
          $before = $`;
          $after = $';
        } elsif($suffix =~ /^i$/) {
          $ret = $code =~ s|$regex|$to|i; 
          ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
          $before = $`;
          $after = $';
        } elsif($suffix =~ /^g$/) {
          $ret = $code =~ s|$regex|$to|g;
          ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
          $before = $`;
          $after = $';
        } elsif($suffix =~ /^ig$/ or $suffix =~ /^gi$/) {
          $ret = $code =~ s|$regex|$to|gi;
          ($a, $b, $c, $d, $e, $f, $g, $h, $i) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
          $before = $`;
          $after = $';
        }

        if($ret) {
          $code =~ s/\$1/$a/g;
          $code =~ s/\$2/$b/g;
          $code =~ s/\$3/$c/g;
          $code =~ s/\$4/$d/g;
          $code =~ s/\$5/$e/g;
          $code =~ s/\$6/$f/g;
          $code =~ s/\$7/$g/g;
          $code =~ s/\$8/$h/g;
          $code =~ s/\$9/$i/g;
          $code =~ s/\$`/$before/g;
          $code =~ s/\$'/$after/g;
        }

        return $ret;
      };

      if($@) {
        my $error = $@;
        $error =~ s/ at .* line \d+\.\s*$//;
        print "$error\n";
        exit 0;
      }

      if ($ret) {
        $got_changes = 1;
      }

      $prevchange = $code;
    }

    if ($got_sub and not $got_changes) {
      print "No substitutions made.\n";
      exit 0;
    } elsif ($got_sub and $got_changes) {
      next;
    }

    last;
  }

  if (@replacements) {
    use re::engine::RE2 -strict => 1;
    @replacements = sort { $a->{'from'} cmp $b->{'from'} or $a->{'modifier'} <=> $b->{'modifier'} } @replacements;

    my ($previous_from, $previous_modifier);

    foreach my $replacement (@replacements) {
      my $from = $replacement->{'from'};
      my $to = $replacement->{'to'};
      my $modifier = $replacement->{'modifier'};

      if(defined $previous_from) {
        if($previous_from eq $from and $previous_modifier =~ /^\d+$/) {
          $modifier -= $modifier - $previous_modifier;
        }
      }

      if(defined $prevchange) {
        $code = $prevchange;
      } else {
        print "No recent code to change.\n";
        exit 0;
      }

      my $ret = eval {
        my $got_change;

        my ($first_char, $last_char, $first_bound, $last_bound);
        $first_char = $1 if $from =~ m/^(.)/;
        $last_char = $1 if $from =~ m/(.)$/;

        if($first_char =~ /\W/) {
          $first_bound = '.?';
        } else {
          $first_bound = '\b';
        }

        if($last_char =~ /\W/) {
          $last_bound = '.?';
        } else {
          $last_bound = '\b';
        }

        if($modifier eq 'all') {
          if($code =~ s/($first_bound)$from($last_bound)/$1$to$2/g) {
            $got_change = 1;
          }
        } elsif($modifier eq 'last') {
          if($code =~ s/(.*)($first_bound)$from($last_bound)/$1$2$to$3/) {
            $got_change = 1;
          }
        } else {
          my $count = 0;
          my $unescaped = $from;
          $unescaped =~ s/\\//g;
          if($code =~ s/($first_bound)$from($last_bound)/if(++$count == $modifier) { "$1$to$2"; } else { "$1$unescaped$2"; }/ge) {
            $got_change = 1;
          }
        }
        return $got_change;
      };

      if($@) {
        my $error = $@;
        $error =~ s/ at .* line \d+\.\s*$//;
        print "$error\n";
        exit 0;
      }

      if($ret) {
        $got_sub = 1;
        $got_changes = 1;
      }

      $prevchange = $code;
      $previous_from = $from;
      $previous_modifier = $modifier;
    }

    if(not $got_changes) {
      print "No replacements made.\n";
      exit 0;
    }
  }

  unless($got_undo and not $got_changes) {
    $unshift_last_code = 1 unless $copy_code and not $got_changes;
  }

  if ($copy_code and $got_changes) {
    $self->{only_show} = 0;
  }

  if ($got_undo and not $got_changes) {
    $self->{only_show} = 1;
  }

  unless (($self->{got_run} or $got_diff) and not $got_changes) {
    if($unshift_last_code) {
      unshift @last_code, $code;
    }

    open FILE, "> history/$self->{channel}-$self->{lang}.hist";

    my $i = 0;
    foreach my $line (@last_code) {
      last if(++$i > $self->{max_history});
      print FILE "$line\n";
    }

    close FILE;
  }

  if ($got_diff) {
    if($#last_code < 1) {
      print "Not enough recent code to diff.\n"
    } else {
      use Text::WordDiff;
      my $diff = word_diff(\$last_code[1], \$last_code[0], { STYLE => 'Diff' });

      if($diff !~ /(?:<del>|<ins>)/) {
        $diff = "No difference.";
      } else {
        $diff =~ s/<del>(.*?)(\s+)<\/del>/<del>$1<\/del>$2/g;
        $diff =~ s/<ins>(.*?)(\s+)<\/ins>/<ins>$1<\/ins>$2/g;
        $diff =~ s/<del>((?:(?!<del>).)*)<\/del>\s*<ins>((?:(?!<ins>).)*)<\/ins>/`replaced $1 with $2`/g;
        $diff =~ s/<del>(.*?)<\/del>/`removed $1`/g;
        $diff =~ s/<ins>(.*?)<\/ins>/`inserted $1`/g;
      }

      print "$diff\n";
    }
    exit 0;
  }

  $self->{code} = $code;
}

1;
