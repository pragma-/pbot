#!/usr/bin/perl

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

  $self->{default_options} = '';
  $self->{cmdline}         = 'echo Hello, world!';

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
    print "$self->{nick}: $self->{code}\n";
    exit;
  }

  unless($self->{got_run} and $self->{copy_code}) {
    open FILE, ">> log.txt";
    print FILE localtime() . "\n";
    print FILE "$self->{nick} $self->{channel}: " . $self->{cmdline_options} . "$self->{code}\n";
    close FILE;
  }
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
}

sub show_output {
  my $self = shift;
  my $output = $self->{output};

  unless($self->{got_run} and $self->{copy_code}) {
    open FILE, ">> log.txt";
    print FILE "------------------------------------------------------------------------\n";
    print FILE localtime() . "\n";
    print FILE "$output\n";
    print FILE "========================================================================\n";
    close FILE;
  }

  if(exists $self->{options}->{'-paste'}  or (defined $self->{got_run} and $self->{got_run} eq "paste")) {
    my $cmdline = $self->{cmdline};

    $cmdline =~ s/\$sourcefile/$self->{sourcefile}/g;
    $cmdline =~ s/\$execfile/$self->{execfile}/g;

    if (length $self->{cmdline_options}) {
      $cmdline =~ s/\$options/$self->{cmdline_options}/g;
    } else {
      if (length $self->{default_options}) {
        $cmdline =~ s/\$options/$self->{default_options}/g;
      } else {
        $cmdline =~ s/\$options\s+//g;
      }
    }

    my $pretty_code = $self->pretty_format($self->{code});

    $pretty_code .= "\n\n/************* CMDLINE *************\n$cmdline\n************** CMDLINE *************/\n"; 

    $output =~ s/\s+$//;
    $pretty_code .= "\n/************* OUTPUT *************\n$output\n************** OUTPUT *************/\n"; 

    my $uri = $self->paste_sprunge($pretty_code);

    print "$self->{nick}: $uri\n";
    exit 0;
  }

  if(length $output > 22 and open FILE, "< history/$self->{channel}-$self->{lang}.last-output") {
    my $last_output;
    my $time = <FILE>;

    if(gettimeofday - $time > 60 * 10) {
      close FILE;
    } else {
      while(my $line = <FILE>) {
        $last_output .= $line;
      }
      close FILE;

      if($last_output eq $output) {
        print "$self->{nick}: Same output.\n";
        exit 0;
      }
    }
  }

  print "$self->{nick}: $output\n";

  open FILE, "> history/$self->{channel}-$self->{lang}.last-output" or die "Couldn't open $self->{channel}-$self->{lang}.last-output: $!";
  my $now = gettimeofday;
  print FILE "$now\n";
  print FILE "$output";
  close FILE;
}

sub paste_codepad {
  my $self = shift;
  my $text = join(' ', @_);

  $text =~ s/(.{120})\s/$1\n/g;

  my $ua = LWP::UserAgent->new();
  $ua->agent("Mozilla/5.0");
  push @{ $ua->requests_redirectable }, 'POST';

  my %post = ( 'lang' => 'C', 'code' => $text, 'private' => 'True', 'submit' => 'Submit' );
  my $response = $ua->post("http://codepad.org", \%post);

  if(not $response->is_success) {
    return $response->status_line;
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

  my %post = ( 'sprunge' => $text, 'submit' => 'Submit' );
  my $response = $ua->post("http://sprunge.us", \%post);

  if(not $response->is_success) {
    return $response->status_line;
  }

  my $result = $response->content;
  $result =~ s/^\s+//;
  $result =~ s/\s+$/?c/;

  return $result;
}

sub execute {
  my ($self, $local) = @_;

  my ($compiler, $compiler_output, $pid);

  if(defined $local and $local != 0) {
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

  $input = `fortune -u -s` if not length $input;
  $input =~ s/[\n\r\t]/ /msg;
  $input =~ s/:/ - /g;
  $input =~ s/\s+/ /g;
  $input =~ s/^\s+//;
  $input =~ s/\s+$//;

  my $pretty_code = $self->pretty_format($self->{code});

  my $cmdline = $self->{cmdline};

  $cmdline =~ s/\$sourcefile/$self->{sourcefile}/g;
  $cmdline =~ s/\$execfile/$self->{execfile}/g;

  if (length $self->{cmdline_options}) {
    $cmdline =~ s/\$options/$self->{cmdline_options}/g;
  } else {
    $cmdline =~ s/\$options/$self->{default_options}/g;
  }

  open FILE, ">> log.txt";
  print FILE "------------------------------------------------------------------------\n";
  print FILE localtime() . "\n";
  print FILE "$cmdline\n$input\n$pretty_code\n";
  close FILE;

  print $compiler "compile:$self->{lang}:$self->{sourcefile}:$self->{execfile}:$cmdline:$input:$date\n";
  print $compiler "$pretty_code\n";
  print $compiler "compile:end\n";

  my $result = "";
  my $got_result = 0;

  while(my $line = <$compiler_output>) {
    $line =~ s/[\r\n]+$//;

    last if $line =~ /^result:end$/;

    if($line =~ /^result:/) {
      $line =~ s/^result://;
      $result .= "$line\n";
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
  push $self->{options_order}, $option;
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
    print "$self->{nick}: $self->{lang} cmdline: $cmdline\n";
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
  my (@last_code, $save_last_code, $unshift_last_code);

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
    print "$self->{nick}: No history for $copy.\n";
    exit 0;

    COPY_SUCCESS:
    $code = $copy_code;
    $self->{only_show} = 1;
    $self->{copy_code} = 1;
    $save_last_code = 1;
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
      print "$self->{nick}: $last_code[0]\n";
    } else {
      print "$self->{nick}: No recent code to show.\n"
    }
    exit 0;
  }

  if($subcode =~ m/^\s*(?:and\s+)?diff(?:\s+\S+)?\s*$/i) {
    if($#last_code < 1) {
      print "$self->{nick}: Not enough recent code to diff.\n"
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

      print "$self->{nick}: $diff\n";
    }
    exit 0;
  }

  if($subcode =~ m/^\s*(?:and\s+)?(run|paste)\s*$/i) {
    $self->{got_run} = lc $1;
    if(defined $last_code[0]) {
      $code = $last_code[0];
      $self->{only_show} = 0;
    } else {
      print "$self->{nick}: No recent code to $self->{got_run}.\n";
      exit 0;
    }
  } else { 
    my $got_undo = 0;
    my $got_sub = 0;

    while($subcode =~ s/^\s*(and)?\s*undo//) {
      splice @last_code, 0, 1;
      if(not defined $last_code[0]) {
        print "$self->{nick}: No more undos remaining.\n";
        exit 0;
      } else {
        $code = $last_code[0];
        $got_undo = 1;
      }
    }

    my @replacements;
    my $prevchange = $last_code[0];
    my $got_changes = 0;
    my $last_keyword;

    while(1) {
      $got_sub = 0;
      #$got_changes = 0;

      $subcode =~ s/^\s*and\s+'/and $last_keyword '/ if defined $last_keyword;

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
          print "$self->{nick}: Unbalanced single quotes.  Usage: cc remove [all, first, .., tenth, last] 'text' [and ...]\n";
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
            print "$self->{nick}: No recent code to prepend to.\n";
            exit 0;
          }

          $code = $prevchange;
          $code =~ s/^/$text /;
          $prevchange = $code;
        } else {
          print "$self->{nick}: Unbalanced single quotes.  Usage: cc prepend 'text' [and ...]\n";
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
            print "$self->{nick}: No recent code to append to.\n";
            exit 0;
          }

          $code = $prevchange;
          $code =~ s/$/ $text/;
          $prevchange = $code;
        } else {
          print "$self->{nick}: Unbalanced single quotes.  Usage: cc append 'text' [and ...]\n";
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
          $subcode = $r;
          $subcode =~ s/\s*with\s*//i;
        } else {
          print "$self->{nick}: Unbalanced single quotes.  Usage: cc replace 'from' with 'to' [and ...]\n";
          exit 0;
        }

        ($e, $r) = extract_delimited($subcode, "'");

        if(defined $e) {
          $to = $e;
          $to =~ s/^'//;
          $to =~ s/'$//;
          $subcode = $r;
        } else {
          print "$self->{nick}: Unbalanced single quotes.  Usage: cc replace 'from' with 'to' [and replace ... with ... [and ...]]\n";
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
          default { print "$self->{nick}: Bad replacement modifier '$modifier'; valid modifiers are 'all', 'first', 'second', ..., 'tenth', 'last'\n"; exit 0; }
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
          print "$self->{nick}: Unbalanced slashes.  Usage: cc s/regex/substitution/[gi] [and s/.../.../ [and ...]]\n";
          exit 0;
        }

        ($e, $r) = extract_delimited($subcode, '/');

        if(defined $e) {
          $to = $e;
          $to =~ s/^\///;
          $to =~ s/\/$//;
          $subcode = $r;
        } else {
          print "$self->{nick}: Unbalanced slashes.  Usage: cc s/regex/substitution/[gi] [and s/.../.../ [and ...]]\n";
          exit 0;
        }

        my $suffix;
        $suffix = $1 if $subcode =~ s/^([^ ]+)//;

        if(length $suffix and $suffix =~ m/[^gi]/) {
          print "$self->{nick}: Bad regex modifier '$suffix'.  Only 'i' and 'g' are allowed.\n";
          exit 0;
        }
        if(defined $prevchange) {
          $code = $prevchange;
        } else {
          print "$self->{nick}: No recent code to change.\n";
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
          print "$self->{nick}: $error\n";
          exit 0;
        }

        if($ret) {
          $got_changes = 1;
        }

        $prevchange = $code;
      }

      if($got_sub and not $got_changes) {
        print "$self->{nick}: No substitutions made.\n";
        exit 0;
      } elsif($got_sub and $got_changes) {
        next;
      }

      last;
    }

    if($#replacements > -1) {
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
          print "$self->{nick}: No recent code to change.\n";
          exit 0;
        }

        my $ret = eval {
          my $got_change;

          my ($first_char, $last_char, $first_bound, $last_bound);
          $first_char = $1 if $from =~ m/^(.)/;
          $last_char = $1 if $from =~ m/(.)$/;

          if($first_char =~ /\W/) {
            $first_bound = '.';
          } else {
            $first_bound = '\b';
          }

          if($last_char =~ /\W/) {
            $last_bound = '\B';
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
          print "$self->{nick}: $error\n";
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
        print "$self->{nick}: No replacements made.\n";
        exit 0;
      }
    }

    $save_last_code = 1;

    unless($got_undo and not $got_changes) {
      $unshift_last_code = 1 unless $copy_code and not $got_changes;
    }

    if($copy_code and $got_changes) {
      $self->{only_show} = 0;
    }

    if($got_undo and not $got_changes) {
      $self->{only_show} = 1;
    }
  }

  if($save_last_code) {
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

  $self->{code} = $code;
}

1;
