#!/usr/bin/perl

package _default;

use warnings;
use strict;

use feature "switch";
no if $] >= 5.018, warnings => "experimental::smartmatch";

use IPC::Run qw/run timeout/;
use Data::Dumper;

sub new {
  my ($class, %conf) = @_;
  my $self = bless {}, $class;

  $self->{debug}         = $conf{debug} // 0;
  $self->{sourcefile}    = $conf{sourcefile};
  $self->{execfile}      = $conf{execfile};
  $self->{code}          = $conf{code};
  $self->{cmdline}       = $conf{cmdline};
  $self->{input}         = $conf{input};
  $self->{date}          = $conf{date};
  $self->{arguments}     = $conf{arguments};
  $self->{factoid}       = $conf{factoid};
  $self->{'persist-key'} = $conf{'persist-key'};

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

  $self->execute(10, undef, 'date', '-s', "\@$self->{date}");

  print "Executing [$self->{cmdline}] with args [$self->{arguments}]\n";
  my @cmdline = $self->split_line($self->{cmdline}, strip_quotes => 1);
  push @cmdline, $self->split_line($self->{arguments}, strip_quotes => 1);

  my ($retval, $stdout, $stderr) = $self->execute(60, $self->{input}, @cmdline);
  $self->{output} = $stderr;
  $self->{output} .= ' ' if length $self->{output};
  $self->{output} .= $stdout;
  $self->{error}  = $retval;
}

sub postprocess {
  my $self = shift;
}

sub execute {
  my ($self, $timeout, $stdin, @cmdline) = @_;

  $stdin //= '';
  print "execute($timeout) [$stdin] ", Dumper \@cmdline, "\n";

  my ($exitval, $stdout, $stderr) = eval {
    my ($stdout, $stderr);
    run \@cmdline, \$stdin, \$stdout, \$stderr, timeout($timeout);
    my $exitval = $? >> 8;
    return ($exitval, $stdout, $stderr);
  };

  if ($@) {
    my $error = $@;
    $error = "[Timed-out]" if $error =~ m/timeout on timer/;
    ($exitval, $stdout, $stderr) = (-1, '', $error);
  }

  print "exitval $exitval stdout [$stdout]\nstderr [$stderr]\n";
  return ($exitval, $stdout, $stderr);
}

# splits line into quoted arguments while preserving quotes. handles
# unbalanced quotes gracefully by treating them as part of the argument
# they were found within.
sub split_line {
  my ($self, $line, %opts) = @_;

  my %default_opts = (
    strip_quotes => 0,
    keep_spaces => 0
  );

  %opts = (%default_opts, %opts);

  my @chars = split //, $line;

  my @args;
  my $escaped = 0;
  my $quote;
  my $token = '';
  my $ch = ' ';
  my $last_ch;
  my $i = 0;
  my $pos;
  my $ignore_quote = 0;
  my $spaces = 0;

  while (1) {
    $last_ch = $ch;

    if ($i >= @chars) {
      if (defined $quote) {
        # reached end, but unbalanced quote... reset to beginning of quote and ignore it
        $i = $pos;
        $ignore_quote = 1;
        $quote = undef;
        $last_ch = ' ';
        $token = '';
      } else {
        # add final token and exit
        push @args, $token if length $token;
        last;
      }
    }

    $ch = $chars[$i++];

    $spaces = 0 if $ch ne ' ';

    if ($escaped) {
      $token .= "\\$ch";
      $escaped = 0;
      next;
    }

    if ($ch eq '\\') {
      $escaped = 1;
      next;
    }

    if (defined $quote) {
      if ($ch eq $quote) {
        # closing quote
        $token .= $ch unless $opts{strip_quotes};
        push @args, $token;
        $quote = undef;
        $token = '';
      } else {
        # still within quoted argument
        $token .= $ch;
      }
      next;
    }

    if ($last_ch eq ' ' and not defined $quote and ($ch eq "'" or $ch eq '"')) {
      if ($ignore_quote) {
        # treat unbalanced quote as part of this argument
        $token .= $ch;
        $ignore_quote = 0;
      } else {
        # begin potential quoted argument
        $pos = $i - 1;
        $quote = $ch;
        $token .= $ch unless $opts{strip_quotes};
      }
      next;
    }

    if ($ch eq ' ') {
      if (++$spaces > 1 and $opts{keep_spaces}) {
        $token .= $ch;
        next;
      } else {
        push @args, $token if length $token;
        $token = '';
        next;
      }
    }

    $token .= $ch;
  }

  return @args;
}

1;
