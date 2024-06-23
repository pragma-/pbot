#!/usr/bin/env perl

# Replaces user cleartext passwords with salted hashes.
#
# This was way overdue. User passwords are no longer stored as cleartext.
#
# Why did it take me so long to finally get around to hashing passwords
# properly, you might ask. The reason why this wasn't done sooner is because
# all of my users used hostmask-based `autologin`. The passwords that PBot
# randomly generated were ignored and never used.
#
# I do regret that it took me so long to get around to this, for those of you
# who might be using custom passwords instead of hostmask-based `autologin`.

use warnings;
use strict;

BEGIN {
    use File::Basename;
    my $location = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, $location;
}

use lib4422::HashObject;
use lib3503::PBot;

use Crypt::SaltedHash;

my ($data_dir, $version, $last_update) = @ARGV;

print "Hashing passwords ... version: $version, last_update: $last_update, data_dir: $data_dir\n";

my $pbot = lib3503::PBot->new();

my $users = lib4422::HashObject->new(name => 'Users', filename => "$data_dir/users", pbot => $pbot);

$users->load;

if (not keys $users->{hash}->%*) {
    die "No users loaded";
}

print "Updating users:\n";

foreach my $user (keys %{$users->{hash}}) {
    if ($user eq '$metadata$') {
        $users->{hash}->{$user}->{update_version} = 4762;
        next;
    }

    print "  $user ...";
    my $csh = Crypt::SaltedHash->new(algorithm => 'SHA-512');
    $csh->add($users->{hash}->{$user}->{password});
    $users->{hash}->{$user}->{password} = $csh->generate;
    print " done\n";
}

$users->save;
print "Done.\n";
exit 0;
