#!/usr/bin/env perl

# Convert unmute_timeouts and unban_timeouts to quietlist and banlist
# Rename bantracker to banlist in registry

use warnings; use strict;

BEGIN {
    use File::Basename;
    my $location = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, $location;
}

use lib3512::DualIndexHashObject;
use lib3503::PBot;

my ($data_dir, $version, $last_update) = @ARGV;

print "Updating ban list data... version: $version, last_update: $last_update, data_dir: $data_dir\n";

my $pbot = lib3503::PBot->new();

my $unmutes = lib3512::DualIndexHashObject->new(name => 'old unmute timeouts', filename => "$data_dir/unmute_timeouts", pbot => $pbot);
$unmutes->load;

$unmutes->set('$metadata$', '$metadata$', 'name', 'Quiet List', 1);
$unmutes->set('$metadata$', '$metadata$', 'update_version', '3536');

my $unbans = lib3512::DualIndexHashObject->new(name => 'old unban timeouts', filename => "$data_dir/unban_timeouts", pbot => $pbot);
$unbans->load;

$unbans->set('$metadata$', '$metadata$', 'name', 'Ban List', 1);
$unbans->set('$metadata$', '$metadata$', 'update_version', '3536');

use File::Copy;
move("$data_dir/unmute_timeouts", "$data_dir/quietlist") or die "Failed to move unmute_timeouts -> quietlist: $!";
move("$data_dir/unban_timeouts", "$data_dir/banlist") or die "Failed to move unban_timeouts -> banlist: $!";

my $registry = lib3512::DualIndexHashObject->new(name => 'Registry', filename => "$data_dir/registry", pbot => $pbot);
$registry->load;

my $data = $registry->get_data('bantracker');
$registry->remove('bantracker', undef, undef, 1);

foreach my $key (keys %{$data}) {
    $registry->add('banlist', $key, $data->{$key}, 1);
}

$registry->set('$metadata$', '$metadata$', 'update_version', '3536');

exit 0;
