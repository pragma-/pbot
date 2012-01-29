#!/usr/bin/perl

use warnings;
use strict;

use IPC::Open2;

my $stdin_input = join ' ', @ARGV;

my $debug = 0; 

my $watching = 0;
my $got_output = 0;
my $local_vars = "";

sub execute {
    my ($cmdline) = @_;
    my ($ret, $result);

    my ($out, $in);
    open2($out, $in, "$cmdline 2>&1");

    while(my $line = <$out>) {
        chomp $line;
        print "-- got: [$line]\n" if $debug >= 1;

        my $ignore_response = 0;

        next if not length $line;
        next if $line =~ m/^\(gdb\) Continuing/;
        next if $line =~ m/^\(gdb\) \$\d+ = "Ok\."/;
        next if $line =~ m/^(\(gdb\) )?Breakpoint \d+ at 0x/;
        next if $line =~ m/^(\(gdb\) )?Starting program/;
        next if $line =~ m/^\d+: .*? =/;

        if($line =~ m/^Reading symbols from.*done\.$/) {
            print $in "break gdb\n";
            #<$out>;

            print $in "list main\n";
            print $in "print \"Ok.\"\n";
            while(my $line = <$out>) {
                chomp $line;
                print "list got: [$line]\n" if $debug >= 4;
                if($line =~ m/^(\d+)\s+return 0;/) {
                    print $in "break $1\n";
                }

                last if $line =~ m/^\(gdb\) \$\d+ = "Ok."/;
            }

            print $in "run\n";
            next;
        }

        if($line =~ m/^Breakpoint \d+, main/) {
            my $line = <$out>;
            print "== got: $line\n" if $debug >= 5;
            if($line =~ m/^\d+\s+return 0;$/) {
                if($got_output == 0) {
                    print "no output, checking locals\n" if $debug >= 5;
                    print $in "info locals\nprint \"Ok.\"\n";
                    my $result = "";
                    my $vars = "";
                    my $varsep = "";

                    while(my $line = <$out>) {
                        chomp $line;
                        print "got: [$line]\n" if $debug >= 5;
                        last if $line =~ m/\(gdb\) \$\d+ = "Ok."/;
                        if($line =~ m/([^=]+)=\s+(.*)/) {
                            $vars .= "$varsep$1= $2";
                            $varsep = "; ";
                        }
                    }

                    $result =~ s/^\s+//;
                    $result =~ s/\s+$//;

                    $vars =~ s/\(gdb\)\s*//g;
                    $local_vars = "<local variables: $vars>" if length $vars;

                    print $in "cont\n";
                    next;
                } else {
                    print $in "cont\n";
                    next;
                } 
            } else {
                print $in "cont\n";
                next;
            }
        }


        if($line =~ m/Breakpoint \d+, gdb/) {
            print $in "up\n";
            $line = <$out>;
            print "ignored $line\n" if $debug >= 2;
            $line = <$out>;
            print "ignored $line\n" if $debug >= 2;
            next;
        }

        if($line =~ m/^\d+\s+watch\((.*)\)/) {
            $line = "1 gdb(\"watch $1\");";
        }

        if($line =~ m/^\d+\s+dump\((.*)\)/) {
            $line = "1 gdb(\"print $1\");";
        }

        if($line =~ m/^\d+\s+print\((.*)\)/) {
            $line = "1 gdb(\"print $1\");";
        }

        if($line =~ m/^\d+\s+ptype\((.*)\)/) {
            $line = "1 gdb(\"ptype $1\");";
        }

        if($line =~ m/^\d+\s+.*gdb\("(.*)"\)/) {
            my $command = $1;
            my ($cmd, $args) = split / /, $command, 2;
            $args = "" if not defined $args;

            #print "got command [$command]\n";

            if($cmd eq "watch") {
                print $in "display $args\n";
                #<$out>;
                $watching++;
                $ignore_response = 1;
            }

            print $in "$command\nprint \"Ok.\"\n";
            my $next_line = <$out>;
            chomp $next_line;
            #print "nextline: $next_line\n";

            $next_line =~ s/^\(gdb\)\s*\(gdb\)\s+\$\d+ = "Ok."//;
            $next_line =~ s/^\(gdb\)\s+\$\d+//;
            $next_line =~ s/^\(gdb\)\s+type//;

            if(not $ignore_response) {
                if($next_line =~ m/=/) {
                    $got_output = 1;
                    print "<$args$next_line>\n";
                } else {
                    print "<$next_line>\n" if length $next_line;
                    $got_output = 1 if length $next_line;
                }
            }

            print $in "cont\n";
            next;
        }

        if($line =~ m/^Watchpoint \d+: (.*)/) {
            my $var = $1;

            my $ignore = <$out>;
            print "ignored $ignore\n" if $debug >= 5;
            my $old = <$out>;
            my $new = <$out>;
            $ignore = <$out>;
            print "ignored $ignore\n" if $debug >= 5;
            $ignore = <$out>;
            print "ignored $ignore\n" if $debug >= 5;

            my ($val1) = $old =~ m/Old value = (.*)/;
            my ($val2) = $new =~ m/New value = (.*)/;

            $got_output = 1;
            print "<$var = $val2>\n";
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

            $got_output = 1;
            print "<$var changed: $val1 => $val2>\n";
            print $in "cont\n";
            next;
        }

        if($line =~ m/^Watchpoint \d+ deleted/) {
            my $ignore = <$out>;
            print "ignored $ignore\n" if $debug >= 5;
            $ignore = <$out>;
            print "ignored $ignore\n" if $debug >= 5;
            print $in "cont\n";
            next;
        }

        if($line =~ m/^Program exited/) {
            print " $local_vars\n" if length $local_vars and not $got_output;
            exit 0;
        }

        if($line =~ s/\[Inferior .* exited with code (\d+)\]//) {
            print "$line\n";
            print "<Exit $1>\n";
            print " $local_vars\n" if length $local_vars and not $got_output;
            exit 0;
        }

        if($line =~ s/\[Inferior .* exited normally\]//) {
            print "$line\n" if length $line;
            $got_output = 1 if length $line;
            print " $local_vars\n" if length $local_vars and not $got_output;
            exit 0;
        }

        if($line =~ m/Program received signal SIGTRAP/) { 
            my $line = <$out>;
            print "ignored $line\n" if $debug >= 5;
            $line = <$out>;
            print "ignored $line\n" if $debug >= 5;
            for(my $i = 0; $i < $watching; $i++) {
                $line = <$out>;
                chomp $line;
                $line =~ s/^\d+:\s//;
                $got_output = 1;
                print "<$line>\n";
            }
            print $in "cont\n";
            next;
        }

        if($line =~ m/Program received signal/) {
            my $result = "";
            my $vars = "";
            my $varsep = "";

            $line =~ s/\.$//;
            $got_output = 1;
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
            $vars = " <local variables: $vars>" if length $vars;

            print "$result$vars\n";
            exit 0;
        }

        if($line =~ s/^\(gdb\)\s*//) {
            $got_output = 1;
            print "<$line>\n";
            next;
        }

        next if $line =~ m/^\d+\s+void gdb\(\) {}/;

        next if not length $line;

        $got_output = 1;
        print "$line\n";
    }
}

execute("gdb -silent ./prog");
