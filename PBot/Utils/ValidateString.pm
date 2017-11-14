package PBot::Utils::ValidateString;
use 5.010; use warnings;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/validate_string/;

sub validate_string {
  my ($string, $max_length) = @_;
  return $string if not defined $string or not length $string;
  $max_length = 2000 if not defined $max_length;
  $string = substr $string, 0, $max_length unless $max_length <= 0;
#  $string =~ s/(\P{PosixGraph})/my $ch = $1; if ($ch =~ m{[\s\x03\x02\x1d\x1f\x16\x0f]}) { $ch } else { sprintf "\\x%02X", ord $ch }/ge;
  $string = substr $string, 0, $max_length unless $max_length <= 0;
  return $string;
}

1;
