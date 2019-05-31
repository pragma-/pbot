#!/usr/bin/perl

use warnings;
use strict;
use feature "switch";

no if $] >= 5.018, warnings => "experimental::smartmatch";

package _default;

sub new {
  my ($class, %conf) = @_;
  my $self = bless {}, $class;

  $self->{debug}       = $conf{debug} // 0;
  $self->{sourcefile}  = $conf{sourcefile};
  $self->{execfile}    = $conf{execfile};
  $self->{code}        = $conf{code};
  $self->{cmdline}     = $conf{cmdline};
  $self->{input}       = $conf{input};
  $self->{date}        = $conf{date};
  $self->{arguments}   = $conf{arguments};
  $self->{factoid}     = $conf{factoid};
  $self->{'persist-key'} = $conf{'persist-key'};

  $self->initialize(%conf);

  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
}

sub preprocess {
  my $self = shift;

  my $input = $self->{input};
  $input = "" if not defined $input;

  print "writing input [$input]\n";

  $input =~ s/(?<!\\)\\n/\n/mg;
  $input =~ s/(?<!\\)\\r/\r/mg;
  $input =~ s/(?<!\\)\\t/\t/mg;
  $input =~ s/(?<!\\)\\b/\b/mg;

  open(my $fh, '>', '.input');
  print $fh "$input\n";
  close $fh;

  if ($self->{code} =~ m/print_last_statement\(.*\);$/m) {
    # remove print_last_statement wrapper in order to get warnings/errors from last statement line
    my $code = $self->{code};
    $code =~ s/print_last_statement\((.*)\);$/$1;/mg;
    open(my $fh, '>', $self->{sourcefile}) or die $!;
    print $fh $code . "\n";
    close $fh;

    print "Executing [$self->{cmdline}] without print_last_statement\n";
    my ($retval, $result) = $self->execute(60, "date -s \@$self->{date} > /dev/null; ulimit -t 5; $self->{cmdline}");
    $self->{output} = $result;
    $self->{error}  = $retval;

    # now compile with print_last_statement intact, ignoring compile results
    if (not $self->{error}) {
      open(my $fh, '>', $self->{sourcefile}) or die $!;
      print $fh $self->{code} . "\n";
      close $fh;

      print "Executing [$self->{cmdline}] with print_last_statement\n";
      my ($retval, $result) = $self->execute(60, "date -s \@$self->{date} > /dev/null; ulimit -t 5; $self->{cmdline}");
    }
  } else {
    open(my $fh, '>', $self->{sourcefile}) or die $!;
    print $fh $self->{code} . "\n";
    close $fh;

    print "Executing [$self->{cmdline}]\n";
    my ($retval, $result) = $self->execute(60, "date -s \@$self->{date} > /dev/null; ulimit -t 5; $self->{cmdline} < .input");
    $self->{output} = $result;
    $self->{error}  = $retval;
  }
}

sub postprocess {
  my $self = shift;
}

sub execute {
  my $self = shift;
  my $timeout = shift;
  my ($cmdline) = @_;

  my ($ret, $result);

  ($ret, $result) = eval {
    print "eval\n";

    my $result = '';

    my $pid = open(my $fh, '-|', "$cmdline 2>&1");

    local $SIG{ALRM} = sub { print "Time out\n"; kill 'TERM', $pid; die "$result [Timed-out]\n"; };
    local $SIG{CHLD} = 'IGNORE';
    alarm($timeout);

    while(my $line = <$fh>) {
      $result .= $line;
    }

    close $fh;
    my $ret = $? >> 8;
    alarm 0;
    return ($ret, $result);
  };

  print "done eval\n";
  alarm 0;

  if($@ =~ /Timed-out/) {
    return (-1, $@);
  }

  print "[$ret, $result]\n";
  return ($ret, $result);
}

1;
