#!/usr/bin/perl

use warnings;
use strict;

package perl;
use parent '_default';

use Text::ParseWords qw(shellwords);

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.pl';
  $self->{execfile}        = 'prog.pl';
  $self->{default_options} = '-w';
  $self->{cmdline}         = 'perl $options $sourcefile';

  if (length $self->{arguments}) {
    $self->{cmdline} .= " $self->{arguments}";
  }
}

sub preprocess_code {
  my $self = shift;
  $self->SUPER::preprocess_code;

  if (defined $self->{arguments}) {
    my @args = shellwords($self->{arguments});
    my $prelude .= "\nmy \$arglen = " . (scalar @args) . ";\n";

    if (@args) {
      $prelude .= "my \@args = (";

      my $comma = "";
      foreach my $arg (@args) {
        $arg = quotemeta $arg;
        $prelude .= "$comma\"$arg\"";
        $comma = ", ";
      }

      $prelude .= ");\n";
    } else {
      $prelude .= "my \@args;\n";
    }

    $self->{code} = "$prelude\n$self->{code}";
  }
}

sub postprocess_output {
  my $self = shift;
  $self->SUPER::postprocess_output;

  $self->{output} =~ s/\s+at $self->{sourcefile} line \d+, near ".*?"//;
  $self->{output} =~ s/\s*Execution of $self->{sourcefile} aborted due to compilation errors.//;

  $self->{cmdline_opening_comment} = "=cut =============== CMDLINE ===============\n";
  $self->{cmdline_closing_comment} = "=cut\n";

  $self->{output_opening_comment} = "=cut =============== OUTPUT ===============\n";
  $self->{output_closing_comment} = "=cut\n";
}

1;
