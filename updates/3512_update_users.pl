#!/usr/bin/env perl

# Updates user JSON file to a better format to support multiple hostmasks and
# easier channel management

use warnings; use strict;

BEGIN {
    use File::Basename;
    my $location = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, $location;
}

use lib3512::HashObject;
use lib3512::DualIndexHashObject;
use lib3503::PBot;

my ($data_dir, $version, $last_update) = @ARGV;

print "Updating users... version: $version, last_update: $last_update, data_dir: $data_dir\n";

my $pbot = lib3503::PBot->new();

my $users = lib3512::DualIndexHashObject->new(name => 'old users', filename => "$data_dir/users", pbot => $pbot);
$users->load;

my $users2 = lib3512::HashObject->new(name => 'new users', filename => "$data_dir/users_new", pbot => $pbot);

foreach my $channel (keys %{$users->{hash}}) {
    next if $channel eq '$metadata$';
    foreach my $hostmask (keys %{$users->{hash}->{$channel}}) {
        next if $hostmask eq '_name';

        my $data = $users->{hash}->{$channel}->{$hostmask};

        my $name = delete $data->{name};
        delete $data->{_name};
        my $channels = $channel;
        $channels = 'global' if $channels eq '.*';
        $data->{channels} = $channels;
        $data->{hostmasks} = $hostmask;

        $users2->add($name, $data, 1);
    }
}

$users2->add('$metadata$', { update_version => 3512 });

print "Overwriting users with user_new\n";

use File::Copy;
move("$data_dir/users_new", "$data_dir/users") or die "Failed to update users: $!";

exit 0;
