# File: Exporter.pm
#
# Purpose: Exports factoids to HTML.

# SPDX-FileCopyrightText: 2005-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Factoids::Exporter;
use parent 'PBot::Core::Class';

use PBot::Imports;

use HTML::Entities;
use POSIX qw(strftime);

sub initialize {
}

sub export($self) {
    my $filename;

    if (@_) {
        $filename = shift;
    } else {
        $filename = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factoids.html';
    }

    if (not defined $filename) {
        $self->{pbot}->{logger}->log("Factoids: export: no filename, skipping export.\n");
        return "No file to export to.";
    }

    if (not defined $self->{pbot}->{factoids}->{data}->{storage}->{dbh}) {
        $self->{pbot}->{logger}->log("Factoids: export: database closed, skipping export.\n");
        return "Factoids database closed; can't export.";
    }

    $self->{pbot}->{logger}->log("Exporting factoids to $filename\n");

    if (not open FILE, "> $filename") {
        $self->{pbot}->{logger}->log("Could not open export file: $!\n");
        return "Could not open export file: $!";
    }

    my $botnick = $self->{pbot}->{registry}->get_value('irc', 'botnick');

    my $factoids = $self->{pbot}->{factoids}->{data}->{storage};

    my $time    = localtime;

    print FILE "<html><head>\n<link href='css/blue.css' rel='stylesheet' type='text/css'>\n";
    print FILE '<script type="text/javascript" src="js/jquery-latest.js"></script>' . "\n";
    print FILE '<script type="text/javascript" src="js/jquery.tablesorter.js"></script>' . "\n";
    print FILE '<script type="text/javascript" src="js/picnet.table.filter.min.js"></script>' . "\n";
    print FILE "</head>\n<body><i>Last updated at $time</i>\n";
    print FILE "<hr><h2>$botnick\'s factoids</h2>\n";

    my $i        = 0;
    my $table_id = 1;

    foreach my $channel (sort $factoids->get_keys) {
        next if not $factoids->get_keys($channel);

        my $chan = $factoids->get_data($channel, '_name');
        $chan = 'global' if $chan eq '.*';

        print FILE "<a href='#" . encode_entities($chan) . "'>" . encode_entities($chan) . "</a><br>\n";
    }

    foreach my $channel (sort $factoids->get_keys) {
        next if not $factoids->get_keys($channel);

        my $chan = $factoids->get_data($channel, '_name');
        $chan = 'global' if $chan eq '.*';

        print FILE "<a name='" . encode_entities($chan) . "'></a>\n";
        print FILE "<hr>\n<h3>" . encode_entities($chan) . "</h3>\n<hr>\n";
        print FILE "<table border=\"0\" id=\"table$table_id\" class=\"tablesorter\">\n";
        print FILE "<thead>\n<tr>\n";
        print FILE "<th>owner</th>\n";
        print FILE "<th>created on</th>\n";
        print FILE "<th>times referenced</th>\n";
        print FILE "<th>factoid</th>\n";
        print FILE "<th>last edited by</th>\n";
        print FILE "<th>edited date</th>\n";
        print FILE "<th>last referenced by</th>\n";
        print FILE "<th>last referenced date</th>\n";
        print FILE "</tr>\n</thead>\n<tbody>\n";

        $table_id++;

        my $iter = $factoids->get_each("index1 = $channel", '_everything', '_sort = index1');

        while (defined (my $factoid = $factoids->get_next($iter))) {
            my $trigger_name = $factoids->get_data($factoid->{index1}, $factoid->{index2}, '_name');

            if ($factoid->{type} eq 'text') {
               $i++;

                if ($i % 2) {
                    print FILE "<tr bgcolor=\"#dddddd\">\n";
                } else {
                    print FILE "<tr>\n";
                }

                print FILE "<td>" . encode_entities($factoid->{'owner'}) . "</td>\n";
                print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %H:%M:%S", localtime $factoid->{'created_on'}) . "</td>\n";

                print FILE "<td>" . $factoid->{'ref_count'} . "</td>\n";

                my $action = $factoid->{'action'};

                if ($action =~ m/https?:\/\/[^ ]+/) {
                    $action =~ s/(.*?)http(s?:\/\/[^ ]+)/encode_entities($1) . "<a href='http" . encode_entities($2) . "'>http" . encode_entities($2) . "<\/a>"/ge;
                    $action =~ s/(.*)<\/a>(.*$)/"$1<\/a>" . encode_entities($2)/e;
                } else {
                    $action = encode_entities($action);
                }

                if (defined $factoid->{'action_with_args'}) {
                    my $with_args = $factoid->{'action_with_args'};
                    $with_args =~ s/(.*?)http(s?:\/\/[^ ]+)/encode_entities($1) . "<a href='http" . encode_entities($2) . "'>http" . encode_entities($2) . "<\/a>"/ge;
                    $with_args =~ s/(.*)<\/a>(.*$)/"$1<\/a>" . encode_entities($2)/e;
                    print FILE "<td width=100%><b>" . encode_entities($trigger_name) . "</b> is $action<br><br><b>with_args:</b> " . encode_entities($with_args) . "</td>\n";
                } else {
                    print FILE "<td width=100%><b>" . encode_entities($trigger_name) . "</b> is $action</td>\n";
                }

                if (defined $factoid->{'edited_by'}) {
                    print FILE "<td>" . $factoid->{'edited_by'} . "</td>\n";
                    print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %H:%M:%S", localtime $factoid->{'edited_on'}) . "</td>\n";
                } else {
                    print FILE "<td></td>\n";
                    print FILE "<td></td>\n";
                }

                print FILE "<td>" . encode_entities($factoid->{'ref_user'}) . "</td>\n";

                if (defined $factoid->{'last_referenced_on'}) {
                    print FILE "<td>" . encode_entities(strftime "%Y/%m/%d %H:%M:%S", localtime $factoid->{'last_referenced_on'}) . "</td>\n";
                } else {
                    print FILE "<td></td>\n";
                }

                print FILE "</tr>\n";
            }
        }

        print FILE "</tbody>\n</table>\n";
    }

    print FILE "<hr>$i factoids memorized.<br>";
    print FILE "<hr><i>Last updated at $time</i>\n";

    print FILE "<script type='text/javascript'>\n";
    $table_id--;
    print FILE '$(document).ready(function() {' . "\n";

    while ($table_id > 0) {
        print FILE '$("#table' . $table_id . '").tablesorter();' . "\n";
        print FILE '$("#table' . $table_id . '").tableFilter();' . "\n";
        $table_id--;
    }

    print FILE "});\n";
    print FILE "</script>\n";
    print FILE "</body>\n</html>\n";

    close FILE;

    return "/say $i factoids exported.";
}

1;
