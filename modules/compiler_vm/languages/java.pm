#!/usr/bin/env perl

use warnings;
use strict;

package java;
use parent '_default';

use Text::Balanced qw/extract_bracketed/;

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.java';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '';
  $self->{cmdline}         = 'javac $options $sourcefile';

  $self->{prelude} = <<'END';
import java.*;

END
}

sub process_custom_options {
  my $self = shift;
  $self->{code} = $self->{code};

  $self->add_option("-nomain") if $self->{code} =~ s/(?:^|(?<=\s))-nomain\s*//i;
  $self->add_option("-noheaders") if $self->{code} =~ s/(?:^|(?<=\s))-noheaders\s*//i;

  $self->{code} = $self->{code};
}

sub pretty_format {
  my $self = shift;
  my $code = join '', @_;
  my $result;

  $code = $self->{code} if not defined $code;

  open my $fh, ">$self->{sourcefile}" or die "Couldn't write $self->{sourcefile}: $!";
  print $fh $code;
  close $fh;

  system("astyle", "-A3 -UHpnfq", $self->{sourcefile});

  open $fh, "<$self->{sourcefile}" or die "Couldn't read $self->{sourcefile}: $!";
  $result = join '', <$fh>;
  close $fh;

  return $result;
}

sub preprocess_code {
  my $self = shift;
  $self->SUPER::preprocess_code;

  my $default_prelude = exists $self->{options}->{'-noheaders'} ? '' : $self->{prelude};

  print "code before: [$self->{code}]\n" if $self->{debug};

  # add newlines to ends of statements and #includes
  my $single_quote = 0;
  my $double_quote = 0;
  my $parens = 0;
  my $escaped = 0;

  while($self->{code} =~ m/(.)/msg) {
    my $ch = $1;
    my $pos = pos $self->{code};

    print "adding newlines, ch = [$ch], parens: $parens, single: $single_quote, double: $double_quote, escaped: $escaped, pos: $pos\n" if $self->{debug} >= 10;

    if($ch eq '\\') {
      $escaped = not $escaped;
    } elsif($ch eq '"') {
      $double_quote = not $double_quote unless $escaped or $single_quote;
      $escaped = 0;
    } elsif($ch eq '(' and not $single_quote and not $double_quote) {
      $parens++;
    } elsif($ch eq ')' and not $single_quote and not $double_quote) {
      $parens--;
      $parens = 0 if $parens < 0;
    } elsif($ch eq ';' and not $single_quote and not $double_quote and $parens == 0) {
      if(not substr($self->{code}, $pos, 1) =~ m/[\n\r]/) {
        substr ($self->{code}, $pos, 0) = "\n";
        pos $self->{code} = $pos + 1;
      }
    } elsif($ch eq "'") {
      $single_quote = not $single_quote unless $escaped or $double_quote;
      $escaped = 0;
    } elsif($ch eq 'n' and $escaped) {
      if(not $single_quote and not $double_quote) {
        print "added newline\n" if $self->{debug} >= 10;
        substr ($self->{code}, $pos - 2, 2) = "\n";
        pos $self->{code} = $pos;
      }
      $escaped = 0;
    } elsif($ch eq '{' and not $single_quote and not $double_quote) {
      if(not substr($self->{code}, $pos, 1) =~ m/[\n\r]/) {
        substr ($self->{code}, $pos, 0) = "\n";
        pos $self->{code} = $pos + 1;
      }
    } elsif($ch eq '}' and not $single_quote and not $double_quote) {
      if(not substr($self->{code}, $pos, 1) =~ m/[\n\r;]/) {
        substr ($self->{code}, $pos, 0) = "\n";
        pos $self->{code} = $pos + 1;
      }
    } else {
      $escaped = 0;
    }
  }

  print "code after \\n additions: [$self->{code}]\n" if $self->{debug};

  # white-out contents of quoted literals so content within literals aren't parsed as code
  my $white_code = $self->{code};
  $white_code =~ s/(?:\"((?:\\\"|(?!\").)*)\")/'"' . ('-' x length $1) . '"'/ge;
  $white_code =~ s/(?:\'((?:\\\'|(?!\').)*)\')/"'" . ('-' x length $1) . "'"/ge;

  my $precode;

  if($white_code =~ m/\bimport\s/) {
    $precode = $self->{code};
  } else {
    $precode = $default_prelude . $self->{code};
  }

  $self->{code} = '';

  print "--- precode: [$precode]\n" if $self->{debug};

  $self->{warn_unterminated_define} = 0;

  my $has_main = 0;

  my $prelude = '';
  while($precode =~ s/^\s*(import .*\n{1,2})//g) {
    $prelude .= $1;
  }

  print "*** prelude: [$prelude]\n   precode: [$precode]\n" if $self->{debug};

  my $preprecode = $precode;

  # white-out contents of quoted literals
  $preprecode =~ s/(?:\"((?:\\\"|(?!\").)*)\")/'"' . ('-' x length $1) . '"'/ge;
  $preprecode =~ s/(?:\'((?:\\\'|(?!\').)*)\')/"'" . ('-' x length $1) . "'"/ge;

  # strip comments
  $preprecode =~ s#|//([^\\]|[^\n][\n]?)*?\n|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $2 ? $2 : ""#gse;
  $preprecode =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/# #gs;

  print "preprecode: [$preprecode]\n" if $self->{debug};

  print "looking for functions, has main: $has_main\n" if $self->{debug} >= 2;

  my $func_regex = qr/^([ *\w]+)\s+([ ()*\w:]+)\s*\(([^;{]*)\s*\)\s*({.*|<%.*|\?\?<.*)/ims;

  # look for potential functions to extract
  while($preprecode =~ /$func_regex/ms) {
    my ($pre_ret, $pre_ident, $pre_params, $pre_potential_body) = ($1, $2, $3, $4);
    my $precode_code;

    print "looking for functions, found [$pre_ret][$pre_ident][$pre_params][$pre_potential_body], has main: $has_main\n" if $self->{debug} >= 1;

    # find the pos at which this function lives, for extracting from precode
    $preprecode =~ m/(\Q$pre_ret\E\s+\Q$pre_ident\E\s*\(\s*\Q$pre_params\E\s*\)\s*\Q$pre_potential_body\E)/g;
    my $extract_pos = (pos $preprecode) - (length $1);

    # now that we have the pos, substitute out the extracted potential function from preprecode
    $preprecode =~ s/$func_regex//ms;

    # create tmpcode object that starts from extract pos, to skip any quoted code
    my $tmpcode = substr($precode, $extract_pos);
    print "tmpcode: [$tmpcode]\n" if $self->{debug};

    $precode = substr($precode, 0, $extract_pos);
    print "precode: [$precode]\n" if $self->{debug};
    $precode_code = $precode;

    $tmpcode =~ m/$func_regex/ms;
    my ($ret, $ident, $params, $potential_body) = ($1, $2, $3, $4);

    print "1st extract: [$ret][$ident][$params][$potential_body]\n" if $self->{debug};

    $ret =~ s/^\s+//;
    $ret =~ s/\s+$//;

    if(not length $ret or $ret eq "else" or $ret eq "while" or $ret eq "if" or $ret eq "for" or $ident eq "for" or $ident eq "while" or $ident eq "if") {
      $precode .= "$ret $ident ($params) $potential_body";
      next;
    } else {
      $tmpcode =~ s/$func_regex//ms;
    }

    $potential_body =~ s/^\s*<%/{/ms;
    $potential_body =~ s/%>\s*$/}/ms;
    $potential_body =~ s/^\s*\?\?</{/ms;
    $potential_body =~ s/\?\?>$/}/ms;

    my @extract = extract_bracketed($potential_body, '{}');
    my $body;
    if(not defined $extract[0]) {
      if($self->{debug} == 0) {
        print "error: unmatched brackets\n";
      } else {
        print "error: unmatched brackets for function '$ident';\n";
        print "body: [$potential_body]\n";
      }
      exit;
    } else {
      $body = $extract[0];
      $preprecode = $extract[1];
      $precode = $extract[1];
    }

    print "final extract: [$ret][$ident][$params][$body]\n" if $self->{debug};
    $self->{code} .= "$precode_code\n$ret $ident($params) $body\n";

    if($self->{debug} >= 2) { print '-' x 20 . "\n" }
    print "     code: [$self->{code}]\n" if $self->{debug} >= 2;
    if($self->{debug} >= 2) { print '-' x 20 . "\n" }
    print "  precode: [$precode]\n" if $self->{debug} >= 2;

    $has_main = 1 if $ident =~ m/^\s*\(?\s*main\s*\)?\s*$/;
  }

  $precode =~ s/^\s+//;
  $precode =~ s/\s+$//;

  $precode =~ s/^{(.*)}$/$1/s;

  if(not $has_main and not exists $self->{options}->{'-nomain'}) {
    if ($precode =~ s/^(};?)//) {
      $self->{code} .= $1;
    }

    $self->{code} = "$prelude\nclass prog {\n$self->{code}\n" . "public static void main(String[] args) {\n$precode\n;\n}\n}\n";
  } else {
    $self->{code} = "$prelude\n$self->{code}\n";
  }

  print "after func extract, code: [$self->{code}]\n" if $self->{debug};

  $self->{code} =~ s/\|n/\n/g;
  $self->{code} =~ s/^\s+//;
  $self->{code} =~ s/\s+$//;
  $self->{code} =~ s/;\s*;\n/;\n/gs;
  $self->{code} =~ s/;(\s*\/\*.*?\*\/\s*);\n/;$1/gs;
  $self->{code} =~ s/;(\s*\/\/.*?\s*);\n/;$1/gs;
  $self->{code} =~ s/({|})\n\s*;\n/$1\n/gs;
  $self->{code} =~ s/(?:\n\n)+/\n\n/g;

  print "final code: [$self->{code}]\n" if $self->{debug};
}

1;
