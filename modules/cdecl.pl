#!/usr/bin/perl -w

# quick and dirty by :pragma

my $command = join(' ', @ARGV);

my @args = split(' ', $command); # because @ARGV may be one quoted argument
if (@args < 2) {
  print "Usage: cdecl <explain|declare|cast|set|...> <code>, see http://linux.die.net/man/1/cdecl\n";
  die;
}

$command = quotemeta($command);
$command =~ s/\\ / /g;

my $result = `/usr/bin/cdecl -c $command`;

chomp $result;
$result =~ s/\n/, /g;

print $result;
