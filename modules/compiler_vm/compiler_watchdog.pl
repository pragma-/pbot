#!/usr/bin/perl

use warnings;
use strict;

use IPC::Open2;

my $stdin_input = (join ' ', @ARGV) || "Lorem ipsum dolor sit amet.\n";
open my $fh, '>', '.input' or die "Couldn't open .input: $!";
print $fh $stdin_input;
close $fh;

my $debug = 0; 

my $watching = 0;
my $got_output = 0;
my $local_vars = "";

sub flushall;
sub gdb;

sub execute {
    my ($cmdline) = @_;
    my ($ret, $result);

    my ($out, $in);
    open2($out, $in, "$cmdline 2>&1");

    while(my $line = <$out>) {
        chomp $line;
        print "--- got: [$line]\n" if $debug >= 1;

        my $ignore_response = 0;

        next if not length $line;
        <$out> and next if $line =~ m/^\(gdb\) No line \d+ in/;
        next if $line =~ m/^\(gdb\) Continuing/;
        next if $line =~ m/^\(gdb\) \$\d+ = "Ok\."/;
        next if $line =~ m/^(\(gdb\) )*Breakpoint \d+ at 0x/;
        next if $line =~ m/^\(gdb\) Breakpoint \d+ at 0x/;
        next if $line =~ m/^\(gdb\) Note: breakpoint \d+ also set/;
        next if $line =~ m/^(\(gdb\) )*Starting program/;
        next if $line =~ m/PRETTY_FUNCTION__ =/;
        next if $line =~ m/libc_start_main/;

        if($line =~ m/^\d+: (.*? = .*)/) {
            print "<$1>\n";
            $got_output = 1;
            next;
        }

        if($line =~ m/^Reading symbols from.*done\.$/) {
            gdb $in, "break gdb\n";

            gdb $in, "list main,9001\n";
            gdb $in, "print \"Ok.\"\n";
            my $break = 0;
            my $bracket = 0;
            my $main_ended = 0;
            while(my $line = <$out>) {
                chomp $line;
                print "list got: [$line]\n" if $debug >= 4;
                my ($line_number) = $line =~ m/^(\d+)/g;
                while($line =~ m/(.)/g) {
                    my $char = $1;
                    if($char eq '{') {
                        $bracket++;
                    } elsif($char eq '}') {
                        $bracket--;

                        if($bracket == 0 and not $main_ended) {
                            $break = $line_number;
                            $main_ended = 1;
                            last;
                        }
                    }
                }

                last if $line =~ m/^\(gdb\) \$\d+ = "Ok."/;
            }

            gdb $in, "break $break\n";
            gdb $in, "set width 0\n";
            gdb $in, "set height 0\n";
            gdb $in, "run < .input\n";
            next;
        }

        if($line =~ m/^Breakpoint \d+, main/) {
            my $line = <$out>;
            print "== got: $line\n" if $debug >= 5;
            if($line =~ m/^\d+\s+return.*?;\s*$/ or $line =~ m/^\d+\s+}\s*$/) {
                if($got_output == 0) {
                    print "no output, checking locals\n" if $debug >= 5;
                    gdb $in, "print \"Go.\"\ninfo locals\nprint \"Ok.\"\n";

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
            gdb $in, "cont\n";
            next;
        }


        if($line =~ m/Breakpoint \d+, gdb/) {
            gdb $in, "up\n";
            $line = <$out>;
            print "ignored $line\n" if $debug >= 2;
            $line = <$out>;
            print "ignored $line\n" if $debug >= 2;
            next;
        }

        if($line =~ m/^Breakpoint \d+, (.*?) at/) {
            my $func = $1;
            my $direction = "entered";
            my $return_value = "";
            my $nextline = <$out>;
            chomp $nextline;

            print "got bt nextline: <$nextline>\n" if $debug >= 5;

            if($nextline =~ m/^\d+\s+}$/) {
                $direction = "leaving";

                gdb $in, "finish\n";
                while(my $retval = <$out>) {
                    chomp $retval;
                    print "got retval line: <$retval>\n" if $debug >= 5;
                    $retval =~ s/^\(gdb\)\s+//;

                    if($retval =~ m/^Run till exit/) {
                        <$out>;
                        <$out>;
                        next;
                    }

                    if($retval =~ m/Value returned is \$\d+ = (.*)/) {
                        $return_value = ", returned $1";
                        last;
                    }
                    
                    next if not length $retval;
                    next if $retval =~ m/^\$\d+ = 0/;

                    print "$retval\n";
                    $got_output = 1;
                }
            }

            flushall $in, $out;

            my $indent = 0;
            gdb $in, "bt\n";
            while(my $bt = <$out>) {
                chomp $bt;
                print "got bt: <$bt>\n" if $debug >= 5;
                $bt =~ s/^\(gdb\) //;
                if($bt =~ m/^#(\d+) .* main .* at prog/) {
                    $indent = $1;
                    last;
                }
            } 

            $indent++ if $direction eq "leaving";
            
            print "<$direction [$indent]", ' ' x $indent, "$func$return_value>\n";
            gdb $in, "cont\n";
            next;
        }

        if($line =~ m/^\d+\s+.*\btrace\((.*)\)/) {
            $line = "1 gdb(\"break $1\");";
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

            print "got command [$command]\n" if $debug >= 10;

            if($cmd eq "break") {
                $ignore_response = 1;

                gdb $in, "list $args,9001\n";
                gdb $in, "print \"Ok.\"\n";
                my $break = 0;
                my $bracket = 0;
                my $func_ended = 0;
                while(my $line = <$out>) {
                    chomp $line;
                    print "list break got: [$line]\n" if $debug >= 4;
                    my ($line_number) = $line =~ m/^(\d+)/g;
                    while($line =~ m/(.)/g) {
                        my $char = $1;
                        if($char eq '{') {
                            $bracket++;
                        } elsif($char eq '}') {
                            $bracket--;

                            if($bracket == 0 and not $func_ended) {
                                gdb $in, "break $line_number\n"; 
                                print "func ended, breaking at $line_number\n" if $debug >= 5;
                                $func_ended = 1;
                                last;
                            }
                        }
                    }

                    last if $line =~ m/^\(gdb\) \$\d+ = "Ok."/;
                }
            }

            if($cmd eq "watch") {
                gdb $in, "display $args\n";
                <$out>;
                $watching++;
                $ignore_response = 1;
            }

            gdb $in, "$command\nprint \"Ok.\"\n";
            while(my $next_line = <$out>) {
                chomp $next_line;
                print "nextline: $next_line\n" if $debug >= 1;

                last if $next_line =~ m/\$\d+ = "Ok."/;
                $next_line =~ s/^\(gdb\)\s*\(gdb\)\s+\$\d+ = "Ok."//;
                $next_line =~ s/^\(gdb\)\s+\$\d+//;
                $next_line =~ s/^\(gdb\)\s+type//;
                $next_line =~ s/^\(gdb\)\s*//;

                next if not length $next_line;

                if(not $ignore_response) {
                    if($next_line =~ m/=/) {
                        $got_output = 1;
                        print "<$args$next_line>\n";
                    } else {
                        $got_output = 1; 
                        print "<$next_line>\n";
                    }
                }
            }

            gdb $in, "cont\n";
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
            gdb $in, "cont\n";
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
            my $output = "<$var changed: $val1 => $val2>\n";
            flushall $in, $out;
            print $output;
            gdb $in, "cont\n";
            next;
        }

        if($line =~ m/^Watchpoint \d+ deleted/) {
            my $ignore = <$out>;
            print "ignored $ignore\n" if $debug >= 5;
            gdb $in, "cont\n";
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
            my $output = "";
            my $line = <$out>;
            print "ignored $line\n" if $debug >= 5;
            $line = <$out>;
            print "ignored $line\n" if $debug >= 5;
            for(my $i = 0; $i < $watching; $i++) {
                $line = <$out>;
                chomp $line;
                $line =~ s/^\d+:\s//;
                $got_output = 1;
                $output .= "<$line>\n";
            }
            flushall $in, $out;
            print $output;
            gdb $in, "cont\n";
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
                $line =~ s/main \(.*?\)/main ()/g;

                print "signal got: [$line]\n" if $debug >= 5;

                next if $line =~ m/__PRETTY_FUNCTION__ =/;

                if($line =~ s/^(#\d+\s+)?0x[0-9A-Fa-f]+\s//) {
                    $line =~ s/\s+at .*:\d+//;
                    $line =~ s/\s+from \/lib.*//;

                    if($line =~ s/^\s*in\s+//) {
                        if(not length $result) {
                            $result .= "in $line ";
                        } else {
                            $result .= "called by $line ";
                        }
                        gdb $in, "info locals\n";
                    } else {
                        $result = "in $line from ";
                        gdb $in, "info locals\n";
                    }
                }
                elsif($line =~ m/^No symbol table info available/) {
                    gdb $in, "up\n";
                }
                elsif($line =~ s/^\d+\s+//) {
                    next if $line =~ /No such file/;

                    $result .= "at statement: $line ";
                    gdb $in, "up\n";
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

sub gdb {
    my ($in, $command) = @_;

    chomp $command;
    print "+++ gdb command [$command]\n" if $debug >= 2;
    print $in "$command\n";
}

sub flushall {
    my ($in, $out) = @_;

    gdb $in, "call fflush(0)\nprint \"Ok.\"\n";
    while(my $line = <$out>) {
        chomp $line;
        $line =~ s/^\(gdb\)\s*//;
        $line =~ s/\$\d+ = 0$//;
        last if $line =~ m/\$\d+ = "Ok."/;
        next unless length $line;
        $got_output = 1;
        print "$line\n";
    }
}

execute("LIBC_FATAL_STDERR=1 gdb -silent ./prog 2>&1");
