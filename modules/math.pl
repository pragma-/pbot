#!/usr/bin/perl -w

# Quick and dirty by :pragma

my ($arguments, $response, $invalid);

my @valid_keywords = (
  'sin', 'cos', 'tan', 'atan', 'exp', 'int', 'hex', 'oct', 'log', 'sqrt', 
  'floor', 'ceil', 'asin', 'acos', 'log10', 'sinh', 'cosh', 'tanh', 'abs',
  'pi', 'deg2rad', 'rad2deg', 'atan2', 'cbrt'
);

if ($#ARGV < 0)
{
  print "Dumbass.\n";
  exit 0;
}

$arguments = join(' ', @ARGV);
my $orig_arguments = $arguments;

$arguments =~ s/(the )*answer.*question of life(,? the universe and everything)?\s?/42/gi;
$arguments =~ s/meaning of (life|existence|everything)?/42/gi;

if($arguments =~ m/([\$`\|{}"'#@=?\[\]])/ or $arguments =~ m/(~~)/) {
  $invalid = $1;
} else {
  while($arguments =~ /([a-zA-Z0-9]+)/g) {
    my $keyword = $1;
    next if $keyword =~ m/^[0-9]+$/;
    $invalid = $keyword and last if not grep { /^$keyword$/ } @valid_keywords;
  }
}

if($invalid) {
  print "Illegal symbol '$invalid' in equation\n";
  exit 1;
}

$response = eval("use POSIX qw/ceil floor/; use Math::Trig; use Math::Complex;" . $arguments);

if($@) {
  my $error = $@;
  $error =~ s/[\n\r]+//g;
  $error =~ s/ at \(eval \d+\) line \d+.//;
  $error =~ s/ at EOF$//;
  $error =~ s/Died at .*//;
  print $error;
  exit 1;
}

print "$orig_arguments = $response\n";
