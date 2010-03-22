package PBot::StdinReader;

use warnings;
use strict;

use vars qw($VERSION);

$VERSION = '1.0.0';

use IO::Select;
use POSIX qw(tcgetpgrp getpgrp);  # to check whether process is in background or foreground

# used to listen for STDIN in non-blocking mode
my $stdin = IO::Select->new();
$stdin->add(\*STDIN);

# used to check whether process is in background or foreground, for stdin reading
open TTY, "</dev/tty" or die $!;
my $tty_fd = fileno(TTY);
my $foreground = (tcgetpgrp($tty_fd) == getpgrp()) ? 1 : 0;

sub check_stdin {
  # make sure we're in the foreground first
  $foreground = (tcgetpgrp($tty_fd) == getpgrp()) ? 1 : 0;
  return if not $foreground;
  
  if ($stdin->can_read(.5)) {
    sysread(STDIN, my $input, 1024);
    chomp $input;
    return $input;
  }
}

1;
