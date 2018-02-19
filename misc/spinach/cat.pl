#!/usr/bin/perl

use strict;
use warnings;

my %docs;
my @uncat;

open my $handle, '<dedup_questions' or die $@;
chomp(my @lines = <$handle>); close $handle;

my @rules = (
  { regex => qr/james bond/i, category => '007' },
  { regex => qr/^194\d /, category => "THE 1940'S" },
  { regex => qr/^195\d /, category => "THE 1950'S" },
  { regex => qr/^196\d /, category => "THE 1960'S" },
  { regex => qr/^197\d /, category => "THE 1970'S" },
  { regex => qr/^198\d /, category => "THE 1980'S" },
  { regex => qr/^199\d /, category => "THE 1990'S" },
  { regex => qr/^200\d /, category => "THE 2000'S" },
  { regex => qr/(?:Name The Year|In what year)/, category => 'NAME THE YEAR' },
  { regex => qr/baby names/i, category => 'BABY NAMES' },
  { regex => qr/what word mean/i, category => 'Definitions' },
  { regex => qr/What (?:one word|word links)/i, category => 'GUESS THE WORD' },
  { regex => qr/^(If [Yy]ou [Ww]ere [Bb]orn|Astrology)/i, category => 'Astrology' },
  { regex => qr/[Oo]lympics/, category => 'Olympics' },
  { regex => qr/^How many/, category => 'HOW MANY' },
  { regex => qr/(?:^What is a group|Group Nouns)/, category => 'animal groups' },
  { regex => qr/(?:[Ww]hat is the fear|phobia is (?:a|the) fear|Phobias)/, category => 'Phobias' },
  { regex => qr/who won the oscar/i, category => 'Oscars' },
  { regex => qr/(?:area code|country code)/, category => 'Phone COUNTRY Codes' },
  { regex => qr/17th century/i, category => "17TH CENTURY" },
  { regex => qr/18th century/i, category => "18TH CENTURY" },
  { regex => qr/19th century/i, category => "19TH CENTURY" },
  { regex => qr/shakespear/i, category => "SHAKESPEARE" },
  { regex => qr/world cup/i, category => "WORLD CUP" },
  { regex => qr/computer science/i, category => "COMPUTER SCIENCE" },
  { regex => qr/computer/i, category => "COMPUTERS" },
  { regex => qr/science/i, category => "SCIENCE" },
  { regex => qr/technolog/i, category => "TECHNOLOGY" },
  { regex => qr/^games /i, category => "GAMES" },
);

my @rename_rules = (
  { old => qr/^191\d/, new => "THE 1910'S" },
  { old => qr/^192\d/, new => "THE 1920'S" },
  { old => qr/^193\d/, new => "THE 1930'S" },
  { old => qr/^194\d/, new => "THE 1940'S" },
  { old => qr/^195\d/, new => "THE 1950'S" },
  { old => qr/^196\d/, new => "THE 1960'S" },
  { old => qr/^197\d/, new => "THE 1970'S" },
  { old => qr/^198\d/, new => "THE 1980'S" },
  { old => qr/^199\d/, new => "THE 1990'S" },
  { old => qr/^200\d/, new => "THE 2000'S" },
  { old => qr/19TH CENT ART/, new => "19TH CENTURY" },
  { old => qr/^20'S$/, new => "THE 1920'S" },
  { old => qr/^30'S$/, new => "THE 1930'S" },
  { old => qr/^40'S$/, new => "THE 1940'S" },
  { old => qr/^50'S$/, new => "THE 1950'S" },
  { old => qr/^60'S$/, new => "THE 1960'S" },
  { old => qr/^70'S$/, new => "THE 1970'S" },
  { old => qr/^80'S$/, new => "THE 1980'S" },
  { old => qr/^THE 50'S$/, new => "THE 1950'S" },
  { old => qr/^THE 60'S$/, new => "THE 1960'S" },
  { old => qr/^THE 70'S$/, new => "THE 1970'S" },
  { old => qr/^THE 80'S$/, new => "THE 1980'S" },
  { old => qr/^80'S TRIVIA$/, new => "THE 1980'S" },
  { old => qr/^90'S$/, new => "THE 1990'S" },
  { old => qr/(?:MOVIES|FILM) \/ TV/, new => "TV / MOVIES"},
  { old => qr/TV-MOVIES/, new => "TV / MOVIES"},
  { old => qr/MOVIE TRIVIA/, new => "MOVIES" },
  { old => qr/AT THE MOVIES/, new => "MOVIES" },
  { old => qr/^\d+ MOVIES/, new => "MOVIES" },
  { old => qr/^1993 THE YEAR/, new => "THE 1990'S" },
  { old => qr/TV \/ MOVIE/, new => "TV / MOVIES" },
  { old => qr/^TV (?:SITCOM|TRIVIA|SHOWS|HOSTS)/, new => "TV" },
  { old => qr/^TV:/, new => "TV" },
  { old => qr/TVS STTNG/, new => "STAR TREK" },
  { old => qr/ACRONYM/, new => "ACRONYM SOUP" },
  { old => qr/ANIMAL TRIVIA/, new => "ANIMAL KINGDOM" },
  { old => qr/^ANIA?MALS$/, new => "ANIMAL KINGDOM" },
  { old => qr/^ADS$/, new => "ADVERTISING" },
  { old => qr/^TELEVISION$/, new => "TV" },
  { old => qr/^QUICK QUICK$/, new => "QUICK! QUICK!" },
  { old => qr/^QUOTES$/, new => "QUOTATIONS" },
  { old => qr/^SHAKESPEAREAN CHARACTER$/, new => "SHAKESPEARE" },
  { old => qr/^USELESS INFO$/, new => "USELESS FACTS" },
  { old => qr/^WORLD CUP 2002$/, new => "WORLD CUP" },
  { old => qr/^AUTHOR$/, new => "AUTHORS" },
  { old => qr/^ART$/, new => "ARTS" },
  { old => qr/^BOOZE/, new => "BOOZE" },
  { old => qr/^SCIFI/, new => "SCI-FI" },
  { old => qr/^HITCHHIKER/, new => "HITCHHIKER'S GUIDE" },
  { old => qr/^SCIENCE FANTASY/, new => "SCI-FI" },
);

print STDERR "Categorizing documents\n";

for my $i (0 .. $#lines) {
  print STDERR "$i\n";

	# Remove/fix stupid things
	$lines[$i] =~ s/\s*Category:\s*//g;
  $lines[$i] =~ s/(\w:)(\w)/$1 $2/g;
  $lines[$i] =~ s{/}{ / }g;
  $lines[$i] =~ s{&}{ & }g;
  $lines[$i] =~ s/\s+/ /g;
  $lines[$i] =~ s/^Useless Trivia: What word means/Definitions: What word means/i;
  $lines[$i] =~ s/^useless triv \d+/Useless Trivia/;

  $lines[$i] =~ s/^sport\s*[:-]\s*(.*?)\s*[:-]/$1: /i;

  my @l = split /`/, $lines[$i];

	# If the question has an obvious category, use that
  if ($l[0] =~ m/^(.{4,}?)\s*[:-]/) {
		my $cat = $1;
		my $nspc = () = $cat =~ m/\s+/g;
		if ($nspc < 3) {
			if (length $cat >= 3 and $cat !~ m/(general|^A |_+)/i) {
				$cat =~ s/^\s+|\s+$//g;
				$cat = uc $cat;
        $cat =~ s/'//g;
        $cat =~ s/\.//g;
				$cat =~ s/(?:\s+$|\R|^"|"$|^-|^\[|\]$)//g;
				$cat =~ s/\s+/ /g;
        $cat =~ s/(\d+)S/$1'S/g;

        $cat =~ s/^SPORT(?!S)/SPORTS/;
				$cat =~ s/ (?:AND|N|'N) / & /;
        #$cat =~ s/\s*\/\s*/\//;

        $cat =~ s/^GEOGRAPH.*/GEOGRAPHY/;
				$cat = 'STAR TREK' if ($cat =~ m/^STAR TREK/);

        $cat = 'GUESS THE WORD' if $l[0] =~ m/.*: '.*\.'/;

        foreach my $rule (@rename_rules) {
          if ($cat =~ m/$rule->{old}/) {
            $cat = uc $rule->{new};
            last;
          }
        }

				print STDERR "Using obvious $cat for doc $i: $l[0] ($l[1])\n";
				push @{$docs{$cat}}, $i;
				next;
			}
		}
	}

  my $found = 0;
	foreach my $rule (@rules) {
		if ($l[0] =~ m/$rule->{regex}/) {
      my $cat = uc $rule->{'category'};
      push @{$docs{$cat}}, $i;
      $found = 1;
      print STDERR "Using rules $cat for doc $i: $l[0] ($l[1])\n";
			last;
		}
	}

  next if $found;

  print STDERR "Uncategorized doc $i: $l[0] ($l[1])\n";

  push @uncat, $i;
}

print STDERR "Done phase 1\n";
print STDERR "Generated ", scalar keys %docs, " categories.\n";

my $small = 0;
my $total = 0;
my @approved;

foreach my $cat (sort { @{$docs{$b}} <=> @{$docs{$a}} } keys %docs) {
  print STDERR "  $cat: ", scalar @{$docs{$cat}}, "\n";

  if (@{$docs{$cat}} < 10) {
    $small++ 
  } else {
    $total += @{$docs{$cat}};
    push @approved, $cat;
  }
}

print STDERR "-" x 80, "\n";
print STDERR "Small categories: $small; total cats: ", (scalar keys %docs) - $small, " with $total questions.\n";
print STDERR "-" x 80, "\n";

foreach my $cat (sort keys %docs) {
  print STDERR "  $cat: ", scalar @{$docs{$cat}}, "\n";
}

print STDERR "Uncategorized: ", scalar @uncat, "\n";

foreach my $i (@uncat) {
  print STDERR "uncategorized: $lines[$i]\n";
}

foreach my $cat (sort @approved) {
  print STDERR "Printing $cat ... ";

  my $count = 0;
  foreach my $i (@{$docs{$cat}}) {
    print "$cat`$lines[$i]\n";
    $count++;
  }

  print STDERR "$count questions.\n";
}
