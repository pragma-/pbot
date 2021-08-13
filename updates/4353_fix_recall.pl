#!/usr/bin/env perl

# Remove `background-process` metadata from `recall` command.

use warnings; use strict;

BEGIN {
    use File::Basename;
    my $location = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, $location;
}

use lib3512::HashObject;
use lib3503::PBot;

my ($data_dir, $version, $last_update) = @ARGV;

print "Updating recall command; version: $version, last_update: $last_update, data_dir: $data_dir\n";

my $pbot = lib3503::PBot->new();

my $commands = lib3512::HashObject->new(name => 'Command metadata', filename => "$data_dir/commands", pbot => $pbot);
$commands->load;

$commands->unset('recall', 'background-process');

exit 0;
