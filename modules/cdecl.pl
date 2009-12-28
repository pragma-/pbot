#!/usr/bin/perl -w

# quick and dirty by :pragma


if ($#ARGV < 0) {
  print "For help with cdecl, see http://linux.die.net/man/1/cdecl\n";
  die;
}

my $command = join(' ', @ARGV);

$command = quotemeta($command);
$command =~ s/\\ / /g;
#print "[$command]\n";
my $result = `/usr/bin/cdecl -c $command`;

chomp $result;
$result =~ s/\n/, /g;

print $result;
