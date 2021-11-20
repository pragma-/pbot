#!/usr/bin/env perl

# Rename modules to applets

use warnings; use strict;

BEGIN {
    use File::Basename;
    my $location = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, $location;
}

use lib4422::HashObject;
use lib4422::DualIndexHashObject;
use lib4422::DualIndexSQLiteObject;
use lib3503::PBot;

my ($data_dir, $version, $last_update) = @ARGV;

print "Adding version info... version: $version, last_update: $last_update, data_dir: $data_dir\n";

my $pbot = lib3503::PBot->new;
my $data;

# update registry
my $registry = lib4422::DualIndexHashObject->new(name => 'Registry', filename => "$data_dir/registry", pbot => $pbot);
$registry->load;

$data = $registry->get_data('general', 'module_dir');
$registry->remove('general', 'module_dir', undef, 1);
$data->{value} =~ s/modules/applets/g;
$registry->add('general', 'applet_dir', $data, 1);

$data = $registry->get_data('general', 'module_repo');
$registry->remove('general', 'module_repo', undef, 1);
$data->{value} =~ s|/modules/|/applets/|;
$registry->add('general', 'applet_repo', $data, 1);

$data = $registry->get_data('general', 'module_timeout');
$registry->remove('general', 'module_timeout', undef, 1);
$registry->add('general', 'applet_timeout', $data, 1);
$registry->save;

# update command help text
my $commands = lib4422::HashObject->new(name => 'Commands', filename => "$data_dir/commands", pbot => $pbot);
$commands->load;
$commands->set('load', 'help', 'This command loads an applet as a PBot command. See https://github.com/pragma-/pbot/blob/master/doc/Admin.md#load', 1);
$commands->set('unload', 'help', 'Unloads an applet and removes its associated command. See https://github.com/pragma-/pbot/blob/master/doc/Admin.md#unload', 1);
$commands->save;

# update factoids
my $factoids = lib4422::DualIndexSQLiteObject->new(name => 'Factoids', filename => "$data_dir/factoids.sqlite3", pbot => $pbot);
$factoids->load;
$factoids->load_metadata;

$data = $factoids->get_data('.*', 'cjeopardy_answer_module');
$factoids->remove('.*', 'cjeopardy_answer_module', undef, 1);
$factoids->add('.*', 'cjeopardy_answer_applet', $data, 1);

$data = $factoids->get_data('.*', 'cjeopardy_filter_module');
$factoids->remove('.*', 'cjeopardy_filter_module', undef, 1);
$factoids->add('.*', 'cjeopardy_filter_applet', $data, 1);

$data = $factoids->get_data('.*', 'cjeopardy_hint_module');
$factoids->remove('.*', 'cjeopardy_hint_module', undef, 1);
$factoids->add('.*', 'cjeopardy_hint_applet', $data, 1);

$data = $factoids->get_data('.*', 'cjeopardy_scores_module');
$factoids->remove('.*', 'cjeopardy_scores_module', undef, 1);
$factoids->add('.*', 'cjeopardy_scores_applet', $data, 1);

$data = $factoids->get_data('.*', 'cjeopardy_module');
$factoids->remove('.*', 'cjeopardy_module', undef, 1);
$factoids->add('.*', 'cjeopardy_applet', $data, 1);

$data = $factoids->get_data('.*', 'date_module');
$factoids->remove('.*', 'date_module', undef, 1);
$factoids->add('.*', 'date_applet', $data, 1);

$data = $factoids->get_data('.*', 'rpn_module');
$factoids->remove('.*', 'rpn_module', undef, 1);
$factoids->add('.*', 'rpn_applet', $data, 1);

$data = $factoids->get_data('.*', 'modules');
$factoids->remove('.*', 'modules', undef, 1);
$data->{action} = '/call list applets';
$factoids->add('.*', 'applets', $data, 1);

$factoids->save;

my @keys;

my $iter = $factoids->get_each('index1', 'index2', 'type = module');

while ($data = $factoids->get_next($iter), defined $data) {
    push @keys, [ $data->{index1}, $data->{index2} ];
}

foreach my $pair (@keys) {
    $factoids->set($pair->[0], $pair->[1], 'type', 'applet', 1);
}

$iter = $factoids->get_each('index1', 'index2', 'action ~ /call%_module%');

@keys = ();

while ($data = $factoids->get_next($iter), defined $data) {
    push @keys, [ $data->{index1}, $data->{index2} ];
}

foreach my $pair (@keys) {
    my ($index1, $index2) = ($pair->[0], $pair->[1]);
    $data = $factoids->get_data($index1, $index2, 'action');
    $data =~ s/_module/_applet/;
    $data = { action => $data };
    $factoids->add($index1, $index2, $data, 1);
}

$factoids->end;

exit 0;
