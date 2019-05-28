#!/usr/bin/perl -sw
use strict;
use List::Util qw[ reduce ]; $a=$b;

our $XLATE ||= 0;

sub rpn2exp {
  local $SIG{__WARN__} = sub {
    print "Malformed arguments.\n";
    exit 1;
  };
  my %tops = map{ $_ => undef } qw[ % MOD + ADD * MULT / DIV ** POW - SUB ];
  my @stack;
  my $expr;
  while ( @_ ) {
    my $item = shift @_;
    push( @stack, $item ), next
    unless exists $tops{ $item } or $item =~ m[\(\)$];
    if ( exists $tops{ $item } ) {
      my $arg2 = pop @stack;
      my $arg1 = pop @stack;
      push @stack, "($arg1 $item $arg2)";
    }
    elsif ( my( $func ) = $item =~ m[^(.*)\(\)$] ) {
      my $args = pop @stack;
      if ($args > 4) {
        print "Too many function arguments.\n";
        exit 1;
      }
      my @args = map{ pop @stack } 1 .. $args;
      push @stack, $func . '(' . join( ', ', reverse @args ) . ')';
    }
  }
  return "@stack";
}

sub nestedOk {
  index( $_[ 0 ], '(' ) <= index( $_[ 0 ], ')' ) and
  0 == reduce{
    $a + ( $b eq '(' ) - ( $b eq ')' )
  } 0, split'[^()]*', $_[ 0 ]
}

my $re_var   = qr[ [a-zA-Z]\w* ]x;
my $re_subex = qr[ \{\d+\} ]x;
my $re_func  = qr[ $re_var $re_subex ]x;
my $re_num   = qr[ -? \d+ (?: \. \d+ )? (?: [Ee] [+-]? \d+ )? ]x;
my $re_term  = qr[ $re_num | $re_func | $re_subex | $re_var ]x;
my $re_op    = qr[\*\*|[,*%+/^-]];
my %ops = ( qw[ % MOD + ADD * MULT / DIV ** POW - SUB ] );

my @varargs;
sub exp2rpn {
  my( $exp, $aStack, $aBits ) = @_;
  print "Unbalanced parens: '$exp'" and exit 1 unless nestedOk $exp;
  if ( $exp =~ m/^$re_term$/ and $exp !~ m/\{\d+\}/ ) {
    push @$aStack, $exp;
  }
  else {{
      my( $left, $op, $right, $rest ) = $exp =~ m[
        ^ (?: ( $re_term )? ( $re_op ) )? ( $re_term ) ( .* ) $
      ]x or print "malformed (sub)expression '$exp'" and exit 1;
#{ no warnings; print "'$exp' => L'$left' O'$op' R'$right' >'$rest'"; }

      $varargs[ -1 ]++ if $op and $op eq ',' and @varargs;

      for ( $left, $right ) {
        next unless $_;
        if ( my( $func, $subex ) = m[^ ( $re_var )? \{ ( \d+ ) \} $]x ) {
          push @varargs, 1 if $func;
          exp2rpn( $aBits->[ $subex ], $aStack, $aBits );
          push @$aStack, pop( @varargs ), "$func()" if $func;
        }
        else{
          push( @$aStack, $_  );
        }
      }
      push @$aStack, $XLATE ? $ops{ $op } : $op
      if $op and $op ne ',';
      $exp = $rest, redo if $rest;
    }}
  return $aStack;
}

sub parseExp {
  my( $exp ) = @_;
  print "Unbalanced parens: '$exp'" and exit 1 unless nestedOk $exp;
  $exp =~ s[\s+][]g;
  my( $n, @bits )= ( 1, $exp );

  for ( reverse @bits ) {
    s/\( ( [^()]* )  \)/ push @bits, $1; "{${ \( $n++ ) }}"; /ex while m/[()]/;
  }

  s/([^,]+)(,?)/push @bits, $1; "{${ \( $n++ ) }}$2" /eg for reverse @bits;

  for ( reverse @bits ) {
    1 while s/( $re_term (?:\*\*)          $re_term )/ push @bits, $1; "{${ \( $n++ ) }}"; /gex;
    1 while s/( $re_term (?:[*\/%])         $re_term )/ push @bits, $1; "{${ \( $n++ ) }}"; /gex;
    1 while s/( $re_term (?:(?<![eE])[+-]) $re_term )/ push @bits, $1; "{${ \( $n++ ) }}"; /gex;
  }
  return @{ exp2rpn $bits[ 0 ], [], \@bits };
}

my $mode = shift @ARGV;
my $args = join ' ', @ARGV;

if (not $args) {
  print "Missing arguments.\n";
  exit 1;
}

if ($mode eq 'rpn') {
  my @rpn = parseExp $args;
  print join(', ', @rpn), "\n";
} else {
  my $infix = rpn2exp split /\s*,\s*/, $args;
  print "$infix\n";
}
