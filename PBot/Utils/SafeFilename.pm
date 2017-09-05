package PBot::Utils::SafeFilename;
use 5.010; use warnings;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/safe_filename/;

sub safe_filename {
  my $name = shift;
  my $safe = '';

  while ($name =~ m/(.)/gms) {
    if ($1 eq '&') {
      $safe .= '&amp;';
    } elsif ($1 eq '/') {
      $safe .= '&fslash;';
    } else {
      $safe .= $1;
    }
  }

  return $safe;
}

1;
