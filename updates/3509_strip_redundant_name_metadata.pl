#!/usr/bin/env perl

# Strips redundant _name metadata from HashObject and DualIndexHashObject JSON files

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

print "Stripping redundant _name metadata... version: $version, last_update: $last_update, data_dir: $data_dir\n";

my @hashobjects = qw/channels commands capabilities/;
my @dualindex = qw/unban_timeouts unmute_timeouts ban-exemptions ignorelist registry spam_keywords users/;

my $pbot = lib3503::PBot->new();

foreach my $hashobject (@hashobjects) {
    print "Updating $data_dir/$hashobject ...\n";
    my $obj = lib3503::HashObject->new(name => $hashobject, filename => "$data_dir/$hashobject", pbot => $pbot);
    $obj->load;

    foreach my $index (keys %{$obj->{hash}}) {
        if ($index eq lc $index) {
            if (exists $obj->{hash}->{$index}->{_name}) {
                if ($obj->{hash}->{$index}->{_name} eq lc $obj->{hash}->{$index}->{_name}) {
                    delete $obj->{hash}->{$index}->{_name};
                }
            }
        } else {
            print "error: $index expected to be all-lowercased; cannot continue\n";
            exit 1;
        }
    }

    $obj->save;
}

foreach my $hashobject (@dualindex) {
    print "Updating $data_dir/$hashobject ...\n";
    my $obj = lib3503::DualIndexHashObject->new(name => $hashobject, filename => "$data_dir/$hashobject", pbot => $pbot);
    $obj->load;

    foreach my $index1 (keys %{$obj->{hash}}) {
        if ($index1 ne lc $index1) {
            print "error: primary index $index1 expected to be all-lowercased; cannot continue\n";
            exit 1;
        }

        if (exists $obj->{hash}->{$index1}->{_name}) {
            if ($obj->{hash}->{$index1}->{_name} eq lc $obj->{hash}->{$index1}->{_name}) {
                delete $obj->{hash}->{$index1}->{_name};
            }
        }

        foreach my $index2 (keys %{$obj->{hash}->{$index1}}) {
            next if $index2 eq '_name';

            if ($index2 ne lc $index2) {
                print "error: $index1.$index2 expected to be all-lowercased; cannot continue\n";
                exit 1;
            }

            if (exists $obj->{hash}->{$index1}->{$index2}->{_name}) {
                if ($obj->{hash}->{$index1}->{$index2}->{_name} eq lc $obj->{hash}->{$index1}->{$index2}->{_name}) {
                    delete $obj->{hash}->{$index1}->{$index2}->{_name};
                }
            }
        }
    }

    $obj->save;
}

exit 0;
