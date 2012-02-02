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
        next if $line =~ m/^\(gdb\) No line \d+ in file/;
        next if $line =~ m/^\(gdb\) Continuing/;
        next if $line =~ m/^\(gdb\) \$\d+ = "Ok\."/;
        next if $line =~ m/^(\(gdb\) )?Breakpoint \d+ at 0x/;
        next if $line =~ m/^(\(gdb\) )?Starting program/;

        if($line =~ m/^\d+: (.*? = .*)/) {
            print "<$1>\n";
            $got_output = 1;
            next;
        }

        if($line =~ m/^Reading symbols from.*done\.$/) {
            print $in "break gdb\n";

            print $in "list main,9001\n";
            print $in "print \"Ok.\"\n";
            my $break = 0;
            my $bracket = 0;
            my $main_ended = 0;
            while(my $line = <$out>) {
                chomp $line;
                print "list got: [$line]\n" if $debug >= 4;
                if(not $main_ended and $line =~ m/^(\d+)\s+return 0;/) {
                    $break = $1;
                } else {
                    my ($line_number) = $line =~ m/^(\d+)/g;
                    while($line =~ m/(.)/g) {
                        my $char = $1;
                        if($char eq '{') {
                            $bracket++;
                        } elsif($char eq '}') {
                            $bracket--;

                            if($bracket == 0) {
                                $break = $line_number;
                                $main_ended = 1;
                                last;
                            }
                        }
                    }
                }

                last if $line =~ m/^\(gdb\) \$\d+ = "Ok."/;
            }

            print $in "break $break\n";
            print $in "run\n";
            next;
        }

        if($line =~ m/^Breakpoint \d+, main/) {
            my $line = <$out>;
            print "== got: $line\n" if $debug >= 5;
            if($line =~ m/^\d+\s+return 0;\s*$/ or $line =~ m/^\d+\s+}\s*$/) {
                if($got_output == 0) {
                    print "no output, checking locals\n" if $debug >= 5;
                    print $in "print \"Go.\"\ninfo locals\nprint \"Ok.\"\n";

                    while(my $peep = <$out>) {
                        chomp $peep;
                        last if $peep =~ m/\(gdb\) \$\d+ = "Go."/;

                        # fix this
                        $peep =~ s/^\d+: (.*?) =/$1 =/;
                        print "<$peep>\n";
                        $got_output = 1;
                    }

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
                    $local_vars = "<no output: $vars>" if length $vars;
                }
            }
            print $in "cont\n";
            next;
        }

        if($line =~ m/Breakpoint \d+, gdb/) {
            print $in "up\n";
            $line = <$out>;
            print "ignored $line\n" if $debug >= 2;
            $line = <$out>;
            print "ignored $line\n" if $debug >= 2;
            next;
        }

        if($line =~ m/^\d+\s+.*\bwatch\((.*)\)/) {
            $line = "1 gdb(\"watch $1\");";
        }

        if($line =~ m/^\d+\s+.*\bdump\((.*)\)/) {
            $line = "1 gdb(\"print $1\");";
        }

        if($line =~ m/^\d+\s+.*\bprint\((.*)\)/) {
            $line = "1 gdb(\"print $1\");";
        }

        if($line =~ m/^\d+\s+.*\bptype\((.*)\)/) {
            $line = "1 gdb(\"ptype $1\");";
        }

        if($line =~ m/^\d+\s+.*\bgdb\("(.*)"\)/) {
            my $command = $1;
            my ($cmd, $args) = split / /, $command, 2;
            $args = "" if not defined $args;

            #print "got command [$command]\n";

            if($cmd eq "watch") {
                print $in "display $args\n";
                <$out>;
                $watching++;
                $ignore_response = 1;
            }

            print $in "$command\nprint \"Ok.\"\n";
            my $next_line = <$out>;
            chomp $next_line;
            print "nextline: $next_line\n" if $debug >= 1;

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

            while(my $line = <$out>) {
                chomp $line;
                $line =~ s/^\(gdb\)\s+//;
                $line =~ s/main \(.*?\)/main ()/;

                print "signal got: [$line]\n" if $debug >= 5;

                if($line =~ s/^(#\d+\s+)?0x[0-9A-Fa-f]+\s//) {
                    $line =~ s/\s+at .*:\d+//;
                    $line =~ s/\s+from \/lib.*//;

                    if($line =~ s/^\s*in\s+//) {
                        if(not length $result) {
                            $result .= "in $line ";
                        } else {
                            $result .= "called by $line ";
                        }
                        print $in "info locals\n";
                    } else {
                        $result = "in $line from ";
                        print $in "info locals\n";
                    }
                }
                elsif($line =~ m/^No symbol table info available/) {
                    print $in "up\n";
                }
                elsif($line =~ s/^\d+\s+//) {
                    next if $line =~ /No such file/;

                    $result .= "at statement: $line ";
                    print $in "up\n";
                }
                elsif($line =~ m/([^=]+)=\s+(.*)/) {
                    $vars .= "$varsep$1= $2";
                    $varsep = "; ";
                }
                elsif($line =~ m/^Initial frame selected; you cannot go up/) {
                    last;
                }
            }

            $result =~ s/^\s+//;
            $result =~ s/\s+$//;
            $result =~ s/in main \(\) //;

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
