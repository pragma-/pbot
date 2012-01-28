#!/usr/bin/perl

use warnings;
use strict;

use IPC::Open2;

my $stdin_input = join ' ', @ARGV;

sub execute {
    my ($cmdline) = @_;
    my ($ret, $result);

    my ($out, $in);
    open2($out, $in, "$cmdline 2>&1");
    #print $in "$stdin_input\n";
    while(my $line = <$out>) {
        chomp $line;
        #print "got: [$line]\n";
        if($line =~ m/^Reading symbols from.*done\.$/) {
            print $in "break gdb\n";
            print $in "run\n";
            next;
        }

        if($line =~ m/Breakpoint \d+, gdb/) {
            print $in "up\n";
            next;
        }

        if($line =~ m/^\d+\s+watch\((.*)\)/) {
            $line = "1 gdb(\"watch $1\");";
        }

        if($line =~ m/^\d+\s+dump\((.*)\)/) {
            $line = "1 gdb(\"print $1\");";
        }

        if($line =~ m/^\d+\s+ptype\((.*)\)/) {
            $line = "1 gdb(\"ptype $1\");";
        }

        if($line =~ m/^\d+\s+gdb\("(.*)"\);/) {
            my $command = $1;
            print $in "$command\n";
            my ($cmd, $args) = split / /, $command, 2;
            $args = "" if not defined $args;
            my $next_line = <$out>;
            chomp $next_line;
            $next_line =~ s/^\(gdb\)\s+\$\d+//;
            $next_line =~ s/^\(gdb\)\s+type//;
            print "$args$next_line\n" if $next_line =~ m/=/;
            print $in "cont\n";
            next;
        }

        if($line =~ m/^Hardware watchpoint \d+: (.*)/) {
            my $var = $1;

            my $ignore = <$out>;
            my $old = <$out>;
            my $new = <$out>;
            $ignore = <$out>;
            $ignore = <$out>;

            my ($val1) = $old =~ m/Old value = (.*)/;
            my ($val2) = $new =~ m/New value = (.*)/;

            print "<$var changed: $val1 => $val2>\n";
            print $in "cont\n";
            next;
        }

        if($line =~ m/^Watchpoint \d+ deleted/) {
            my $ignore = <$out>;
            $ignore = <$out>;
            print $in "cont\n";
            next;
        }

        if($line =~ m/^Program exited/) {
            exit 0;
        }

        if($line =~ m/Program received signal/) {
            my $result = "";
            my $vars = "";
            my $varsep = "";

            $line =~ s/\.$//;
            print "$line ";

            print $in "up\nup\nup\nup\nup\nup\nup\ninfo locals\nquit\ny\n";

            while(my $line = <$out>) {
                chomp $line;
                #print "got: [$line]\n";
                if($line =~ s/^0x[0-9A-Fa-f]+\s//) {
                    next if $line =~ /in main\s*\(/;

                    $line =~ s/\s+at .*:\d+//;

                    if($line !~ m/^\s*in\s+/) {
                        $result = "in $line from ";
                    } else {
                        $result .= "$line at ";
                    }
                }
                elsif($line =~ s/^\d+\s+//) {
                    next if $line =~ /No such file/;

                    $result .= "at " if not length $result;
                    $result .= "statement: $line";
                }
                elsif($line =~ m/([^=]+)=\s+(.*)/) {
                    $vars .= "$varsep$1= $2";
                    $varsep = "; ";
                }
            }

            $result =~ s/^\s+//;
            $result =~ s/\s+$//;

            $vars =~ s/\(gdb\)\s*//g;
            $vars = " [local variables: $vars]" if length $vars;

            print "$result$vars\n";
            exit 0;
        }

        if($line =~ m/^\(gdb\)/) {
            next;
        }

        next if $line =~ m/^\d+\s+void gdb\(\) {}/;

        next if not length $line;

        print "$line\n";
    }
}

execute("gdb -silent ./prog");
