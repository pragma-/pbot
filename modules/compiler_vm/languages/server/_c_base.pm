#!/usr/bin/perl

use warnings;
use strict;

package _c_base; 
use parent '_default';

sub preprocess {
  my $self = shift;

  my $input = $self->{input};
  $input = "" if not defined $input;

  print "writing input [$input]\n";
  open(my $fh, '>', '.input');
  print $fh "$input\n";
  close $fh;

  $self->execute(10, undef, 'date', '-s', "\@$self->{date}");

  my @cmd = $self->split_line($self->{cmdline}, strip_quotes => 1);

  if ($self->{code} =~ m/print_last_statement\(.*\);$/m) {
    # remove print_last_statement wrapper in order to get warnings/errors from last statement line
    my $code = $self->{code};
    $code =~ s/print_last_statement\((.*)\);$/$1;/mg;
    open(my $fh, '>', $self->{sourcefile}) or die $!;
    print $fh $code . "\n";
    close $fh;

    print "Executing [$self->{cmdline}] without print_last_statement\n";
    my ($retval, $stdout, $stderr) = $self->execute(60, undef, @cmd);
    $self->{output} = $stderr;
    $self->{output} .= ' ' if length $self->{output};
    $self->{output} .= $stdout;
    $self->{error}  = $retval;

    # now compile with print_last_statement intact, ignoring compile results
    if (not $self->{error}) {
      open(my $fh, '>', $self->{sourcefile}) or die $!;
      print $fh $self->{code} . "\n";
      close $fh;

      print "Executing [$self->{cmdline}] with print_last_statement\n";
      $self->execute(60, undef, @cmd);
    }
  } else {
    open(my $fh, '>', $self->{sourcefile}) or die $!;
    print $fh $self->{code} . "\n";
    close $fh;

    print "Executing [$self->{cmdline}]\n";
    my ($retval, $stdout, $stderr) = $self->execute(60, undef, @cmd);
    $self->{output} = $stderr;
    $self->{output} .= ' ' if length $self->{output};
    $self->{output} .= $stdout;
    $self->{error}  = $retval;
  }

  if ($self->{cmdline} =~ m/--(?:version|analyze)/) {
    $self->{done} = 1;
  }
}

sub postprocess {
  my $self = shift;
  $self->SUPER::postprocess;

  # no errors compiling, but if output contains something, it must be diagnostic messages
  if(length $self->{output}) {
    $self->{output} =~ s/^\s+//;
    $self->{output} =~ s/\s+$//;
    $self->{output} = "[$self->{output}]\n";
  }

  print "Executing gdb\n";
  my @args = $self->split_line($self->{arguments}, strip_quotes => 1);
  my ($exitval, $stdout, $stderr) = $self->execute(60, undef, 'compiler_watchdog.pl', @args);

  my $result = $stderr;
  $result .= ' ' if length $result;
  $result .= $stdout;

  if (not length $result) {
    $self->{no_output} = 1;
  } elsif ($self->{code} =~ m/print_last_statement\(.*\);$/m
    && ($result =~ m/A syntax error in expression/ || $result =~ m/No symbol.*in current context/ || $result =~ m/has unknown return type; cast the call to its declared return/ || $result =~ m/Can't take address of.*which isn't an lvalue/)) {
    # strip print_last_statement and rebuild/re-run
    $self->{code} =~ s/print_last_statement\((.*)\);/$1;/mg;
    $self->preprocess;
    $self->postprocess;
  } else {
    $self->{output} .= $result;
  }
}

1;
