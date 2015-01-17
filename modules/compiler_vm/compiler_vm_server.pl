#!/usr/bin/env perl

use warnings;
use strict;

use File::Basename;

my $USE_LOCAL = defined $ENV{'CC_LOCAL'}; 

# uncomment the following if installed to the virtual machine
# use constant MOD_DIR => '/usr/local/share/compiler_vm/languages';

use constant MOD_DIR => 'languages/server';

use lib MOD_DIR;

my %languages;

sub load_modules {
  my @files = glob MOD_DIR . "/*.pm";
  foreach my $mod (@files){
    print "Loading module $mod\n";
    my $filename = basename($mod);
    require $filename;
    $filename =~ s/\.pm$//;
    $languages{$filename} = 1;
  }
}

sub run_server {
  my ($input, $output, $heartbeat);

  if(not defined $USE_LOCAL or $USE_LOCAL == 0) {
    open($input, '<', "/dev/ttyS0") or die $!;
    open($output, '>', "/dev/ttyS0") or die $!;
    open($heartbeat, '>', "/dev/ttyS1") or die $!;
  } else {
    open($input, '<', "/dev/stdin") or die $!;
    open($output, '>', "/dev/stdout") or die $!;
  }

  my $date;
  my $lang;
  my $sourcefile;
  my $execfile;
  my $code;
  my $cmdline;
  my $user_input;

  print "Waiting for input...\n";

  my $pid = fork;
  die "Fork failed: $!" if not defined $pid;

  if($pid == 0) {
    while(my $line = <$input>) {
      chomp $line;

      print "Got [$line]\n";

      if($line =~ m/^compile:\s*end/) {
        next if not defined $lang or not defined $code;

        print "Attempting compile [$lang] ...\n";

        my $result = interpret($lang, $sourcefile, $execfile, $code, $cmdline, $user_input, $date);

        print "Done compiling; result: [$result]\n";
        print $output "result:$result\n";
        print $output "result:end\n";

        if(not defined $USE_LOCAL or $USE_LOCAL == 0) {
          print "input: ";
          next;
        } else {
          exit;
        }
      }

      if($line =~ m/^compile:\s*(.*)/) {
        my $options = $1;
        $cmdline = undef;
        $user_input = undef;
        $lang = undef;
        $sourcefile = undef;
        $execfile = undef;

        ($lang, $sourcefile, $execfile, $cmdline, $user_input, $date) = split /:/, $options;

        $code = "";
        $sourcefile = "/dev/null" if not defined $sourcefile;
        $execfile = "/dev/null" if not defined $execfile;
        $lang = "unknown" if not defined $lang;
        $cmdline = "echo No cmdline specified!" if not defined $cmdline;
        $user_input = "" if not defined $user_input;

        print "Setting lang [$lang]; [$sourcefile]; [$cmdline]; [$user_input]; [$date]\n";
        next;
      }

      $code .= $line . "\n";
    }
  } else {
    while(1) {
      print $heartbeat "\n";
      sleep 1;
    }
  }

  close $input;
  close $output;
  close $heartbeat;
}

sub interpret {
  my ($lang, $sourcefile, $execfile, $code, $cmdline, $input, $date) = @_;

  print "lang: [$lang], sourcefile: [$sourcefile], execfile [$execfile], code: [$code], cmdline: [$cmdline], input: [$input], date: [$date]\n";

  $lang = '_default' if not exists $languages{$lang};

  system("chmod -R 755 /home/compiler");

  my $mod = $lang->new(sourcefile => $sourcefile, execfile => $execfile, code => $code, 
    cmdline => $cmdline, input => $input, date => $date);

  $mod->preprocess;

  if($cmdline =~ m/-?-version/) {
    # cmdline contained version request, so don't postprocess and just return the version output
    $mod->{output} =~ s/\s+\(Ubuntu.*-\d+ubuntu\d+\)//;
    return $mod->{output};
  }

  $mod->postprocess if not $mod->{error};

  if (exists $mod->{no_output} or not length $mod->{output}) {
    $mod->{output} .= "\n" if length $mod->{output};
    $mod->{output} .= "Success (no output).\n" if not $mod->{error};
    $mod->{output} .= "Success (exit code $mod->{error}).\n" if $mod->{error};
  }

  return $mod->{output};
}

load_modules;
run_server;
