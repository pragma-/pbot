#!/usr/bin/perl -w
#
# Lame-o-Nickometer backend
#
# (c) 1998 Adam Spiers <adam.spiers@new.ox.ac.uk>
#
# You may do whatever you want with this code, but give me credit.
#
# $Id: nickometer.pl,v 1.3 1999-02-20 04:19:10 tigger Exp $
#

use strict;
use Getopt::Std;
use Math::Trig;

use vars qw($VERSION $score $verbose);

$VERSION = '$Revision: 1.3 $';	# '
$VERSION =~ s/^.*?([\d.]+).*?$/$1/;

sub nickometer ($) {
  local $_ = shift;

  local $score = 0;

  # Deal with special cases (precede with \ to prevent de-k3wlt0k)
  my %special_cost = (
		      '__'			=> 200,
		      '69'			=> 500,
		      'dea?th'			=> 500,
		      'dark'			=> 400,
		      'n[i1]ght'		=> 300,
		      'n[i1]te'			=> 500,
		      'fuck'			=> 500,
		      'sh[i1]t'			=> 500,
		      'coo[l1]'			=> 500,
		      'kew[l1]'			=> 500,
          'sw[a4]g'     => 500,
		      'lame'			=> 500,
		      'dood'			=> 500,
		      'dude'			=> 500,
		      '[l1](oo?|u)[sz]er'	=> 500,
		      '[l1](ee|33)[t7]'		=> 500,
		      'e[l1]ite'		=> 500,
		      '[l1]ord'			=> 500,
		      's[e3]xy'			=> 700,
		      'h[o0]rny'		=> 700,
		      'pr[o0]n'			=> 1000,
		      'w[4a]r[e3]z'		=> 1000,
		      'xx'			=> 450,
		     );

  foreach my $special (keys %special_cost) {
    my $special_pattern = $special;
    my $raw = ($special_pattern =~ s/^\\//);
    my $nick = $_;
    unless ($raw) {
      $nick =~ tr/023457+8/ozeasttb/;
    }
    while($nick =~ /$special_pattern/ig) {
      &punish($special_cost{$special}, "matched special case /$special_pattern/")
    }
  }
  
  while(m/[A-Z]([^A-Z]+)\b/g) {
    &punish(250, "length 1 between capitals") if length $1 == 1;
  }

  # Allow Perl referencing
  s/^\\([A-Za-z])/$1/;
  
  # Keep me safe from Pudge ;-)
  s/\^(pudge)/$1/i;

  # C-- ain't so bad either
  s/^C--$/C/;
  
  # Punish consecutive non-alphas
  s/([^A-Za-z0-9]{2,})
   /my $consecutive = length($1);
    &punish(&slow_pow(10, $consecutive), 
	    "$consecutive total consecutive non-alphas")
      if $consecutive;
    $1
   /egx;

  # Remove balanced brackets and punish for unmatched
  while (s/^([^()]*)   (\() (.*) (\)) ([^()]*)   $/$1$3$5/x ||
	 s/^([^{}]*)   (\{) (.*) (\}) ([^{}]*)   $/$1$3$5/x ||
	 s/^([^\[\]]*) (\[) (.*) (\]) ([^\[\]]*) $/$1$3$5/x) 
  {
    print "Removed $2$4 outside parentheses; nick now $_\n" if $verbose;
  }
  my $parentheses = tr/(){}[]/(){}[]/;
  &punish(&slow_pow(10, $parentheses), 
	  "$parentheses unmatched " .
	    ($parentheses == 1 ? 'parenthesis' : 'parentheses'))
    if $parentheses;

  # Punish k3wlt0k
  my @k3wlt0k_weights = (5, 5, 2, 5, 2, 3, 1, 2, 2, 2);
  for my $digit (0 .. 9) {
    my $occurrences = s/$digit/$digit/g || 0;
    &punish($k3wlt0k_weights[$digit] * $occurrences * 30,
	    $occurrences . ' ' .
	      (($occurrences == 1) ? 'occurrence' : 'occurrences') .
	      " of $digit")
      if $occurrences;
  }

  # An alpha caps is not lame in middle or at end, provided the first
  # alpha is caps.
  my $orig_case = $_;
  s/^([^A-Za-z]*[A-Z].*[a-z].*?)[_-]?([A-Z])/$1\l$2/;
  
  # A caps first alpha is sometimes not lame
  s/^([^A-Za-z]*)([A-Z])([a-z])/$1\l$2$3/;
  
  # Punish uppercase to lowercase shifts and vice-versa, modulo 
  # exceptions above
  my $case_shifts = &case_shifts($orig_case);
  &punish(&slow_pow(5, $case_shifts),
	  $case_shifts . ' case ' .
	    (($case_shifts == 1) ? 'shift' : 'shifts'))
    if ($case_shifts > 1 && /[A-Z]/);

  # Punish lame endings (TorgoX, WraithX et al. might kill me for this :-)
  &punish(50, 'last alpha lame') if $orig_case =~ /[XZ][^a-zA-Z]*$/;

  # Punish letter to numeric shifts and vice-versa
  my $number_shifts = &number_shifts($_);
  &punish(&slow_pow(9, $number_shifts), 
	  $number_shifts . ' letter/number ' .
	    (($number_shifts == 1) ? 'shift' : 'shifts'))
    if $number_shifts > 1;

  # Punish extraneous caps
  my $caps = tr/A-Z/A-Z/;
  &punish(&slow_pow(7, $caps), "$caps extraneous caps") if $caps;

  # Now punish anything that's left
  my $remains = $_;
  $remains =~ tr/a-zA-Z0-9//d;
  my $remains_length = length($remains);

  &punish(150 * $remains_length + &slow_pow(9, $remains_length),
	  $remains_length . ' extraneous ' .
	    (($remains_length == 1) ? 'symbol' : 'symbols'))
    if $remains;

  print "\nRaw lameness score is $score\n" if $verbose;

  # Use an appropriate function to map [0, +inf) to [0, 100)
  my $percentage = 100 * 
                     (1 + tanh(($score-400)/400)) * 
                     (1 - 1/(1+$score/5)) / 2;

  my $digits = 2 * (2 - &round_up(log(100 - $percentage) / log(10)));

  return sprintf "%.${digits}f", $percentage;
}

sub case_shifts ($) {
  # This is a neat trick suggested by freeside.  Thanks freeside!

  my $shifts = shift;

  $shifts =~ tr/A-Za-z//cd;
  $shifts =~ tr/A-Z/U/s;
  $shifts =~ tr/a-z/l/s;

  return length($shifts) - 1;
}

sub number_shifts ($) {
  my $shifts = shift;

  $shifts =~ tr/A-Za-z0-9//cd;
  $shifts =~ tr/A-Za-z/l/s;
  $shifts =~ tr/0-9/n/s;

  return length($shifts) - 1;
}

sub slow_pow ($$) {
  my ($x, $y) = @_;

  return $x ** &slow_exponent($y);
}

sub slow_exponent ($) {
  my $x = shift;

  return 1.3 * $x * (1 - atan($x/6) *2/pi);
}

sub round_up ($) {
  my $float = shift;

  return int($float) + ((int($float) == $float) ? 0 : 1);
}

sub punish ($$) {
  my ($damage, $reason) = @_;

  return unless $damage;

  $score += $damage;
  print "$damage lameness points awarded: $reason\n" if $verbose;
}

my $nick = $ARGV[0];

if(not defined $nick) {
  print "Usage: nickometer <nick>\n";
  exit 1;
}

my $percentage = nickometer($nick);

if($percentage > 0) {
  print "$nick is $percentage% lame.\n";
} else {
  print "$nick isn't lame.\n";
}
