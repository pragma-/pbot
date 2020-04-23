#!/usr/bin/env perl

# Adds version metadata to HashObject and DualIndexHashObject JSON files.

use warnings; use strict;

BEGIN {
    use File::Basename;
    my $location = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, $location;
}

use lib3503::HashObject;
use lib3503::DualIndexHashObject;
use lib3503::PBot;

my ($data_dir, $version, $last_update) = @ARGV;

print "Adding version info... version: $version, last_update: $last_update, data_dir: $data_dir\n";

my @hashobjects = qw/channels commands capabilities/;
my @dualindex = qw/unban_timeouts unmute_timeouts ban-exemptions ignorelist registry spam_keywords users/;

my $pbot = lib3503::PBot->new();

foreach my $hashobject (@hashobjects) {
    print "Updating $data_dir/$hashobject ...\n";
    my $obj = lib3503::HashObject->new(name => $hashobject, filename => "$data_dir/$hashobject", pbot => $pbot);
    $obj->load;

    my $ver = $obj->get_data('$metadata$', 'update_version');

    if (defined $ver) {
        print "$hashobject last update version $ver; ";
        if ($ver >= 3503) {
            print "no update needed\n";
            next;
        } else {
            print "updating...\n";
        }
    }

    print "Adding version info\n";
    $obj->add('$metadata$', { update_version => 3503 });
}

foreach my $hashobject (@dualindex) {
    print "Updating $data_dir/$hashobject ...\n";
    my $obj = lib3503::DualIndexHashObject->new(name => $hashobject, filename => "$data_dir/$hashobject", pbot => $pbot);
    $obj->load;

    my $ver = $obj->get_data('$metadata$', '$metadata$', 'update_version');

    if (defined $ver) {
        print "$hashobject last update version $ver; ";
        if ($ver >= 3503) {
            print "no update needed\n";
            next;
        } else {
            print "updating...\n";
        }
    }

    print "Adding version info\n";
    $obj->add('$metadata$', '$metadata$', { update_version => 3503 });
}

exit 0;
