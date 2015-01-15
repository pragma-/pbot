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

  $self->initialize(%conf);

  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
}

sub preprocess {
  my $self = shift;

  open(my $fh, '>', $self->{sourcefile}) or die $!;
  print $fh $self->{code} . "\n";
  close $fh;

  print "Executing [$self->{cmdline}]\n";
  my ($retval, $result) = $self->execute(60, $self->{cmdline});

  $self->{output} = $result;
  $self->{error}  = $retval;
}

sub postprocess {
  print "_default postprocessing\n";
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
