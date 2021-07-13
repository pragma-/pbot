#!/usr/bin/env perl

# Add hostmask field to Messages table of Message History database

use warnings; use strict;

BEGIN {
    use File::Basename;
    my $location = -l __FILE__ ? dirname readlink __FILE__ : dirname __FILE__;
    unshift @INC, $location;
}

my ($data_dir, $version, $last_update) = @ARGV;

print "Updating message history database... version: $version, last_update: $last_update, data_dir: $data_dir\n";

use DBI;

my $dbh = DBI->connect("dbi:SQLite:dbname=$data_dir/message_history.sqlite3", "", "", {RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1, sqlite_unicode => 1})
    or die $DBI::errstr;

eval {
    my %existing = ();
    foreach my $col (@{$dbh->selectall_arrayref("PRAGMA TABLE_INFO(Messages)")}) {
        $existing{$col->[1]} = $col->[2];
    }

    $dbh->begin_work;

    if (not exists $existing{'hostmask'}) {
        $dbh->do('ALTER TABLE Messages ADD COLUMN hostmask TEXT COLLATE NOCASE');
    }

    $dbh->commit;
};

if ($@) {
    print "Error updating: $@";
    $dbh->rollback;
    exit 1;
}

$dbh->disconnect;


exit 0;
