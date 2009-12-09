#!/usr/bin/perl -w

# Quick and dirty by :pragma


my ($arguments, $response);

if ($#ARGV < 0)
{
  print "Dumbass.\n";
  die;
}

$arguments = join(" ", @ARGV);

if($arguments =~ m/[\$a-z]/i)
{
  print("Illegal characters, please only use numbers and valid operators (+, -, /, *, etc).");
  die();
}

$response = eval($arguments);
print "$arguments = $response";
