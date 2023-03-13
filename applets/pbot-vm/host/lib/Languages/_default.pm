#!/usr/bin/perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use 5.020;

use warnings;
use strict;

use feature qw(switch unicode_strings signatures);
no warnings qw(experimental::smartmatch experimental::signatures);

package Languages::_default;

use Encode;
use JSON::XS;
use Getopt::Long qw(GetOptionsFromArray :config pass_through no_ignore_case no_auto_abbrev);
use Time::HiRes qw(gettimeofday);
use POSIX;

use FindBin qw($RealBin);

use InteractiveEdit;
use Paste;
use SplitLine;

sub new {
    my ($class, %conf) = @_;
    my $self = bless {}, $class;

    %$self = %conf;

    $self->{debug}           //= 0;
    $self->{arguments}       //= '';
    $self->{default_options} //= '';
    $self->{max_history}     //= 10000;

    $self->initialize(%conf);

    # remove leading and trailing whitespace
    $self->{nick}    =~ s/^\s+|\s+$//g;
    $self->{channel} =~ s/^\s+|\s+$//g;
    $self->{lang}    =~ s/^\s+|\s+$//g;

    return $self;
}

sub initialize($self, %conf) {}

sub process_interactive_edit($self) {
    return interactive_edit($self);
}

sub process_standard_options($self) {
    my @opt_args = split_line($self->{code}, preserve_escapes => 1, keep_spaces => 0);

    my $getopt_error;
    local $SIG{__WARN__} = sub {
        $getopt_error = shift;
        chomp $getopt_error;
    };

    my ($info, $arguments, $paste);
    GetOptionsFromArray(\@opt_args,
        'info!' => \$info,
        'args|arguments=s' => \$arguments,
        'paste!' => \$paste);

    if ($info) {
        my $cmdline = $self->{cmdline};
        if (length $self->{default_options}) {
            $cmdline =~ s/\$options/$self->{default_options}/;
        } else {
            $cmdline =~ s/\$options\s+//;
        }
        $cmdline =~ s/\$sourcefile/$self->{sourcefile}/g;
        $cmdline =~ s/\$execfile/$self->{execfile}/g;
        my $name = exists $self->{name} ? $self->{name} : $self->{lang};
        print "$name cmdline: $cmdline\n";
        $self->done;
        exit;
    }

    if (defined $arguments) {
        if (not $arguments =~ s/^"(.*)"$/$1/) {
            $arguments =~ s/^'(.*)'$/$1/;
        }
        $self->{arguments} = $arguments;
    }

    if ($paste) {
        $self->add_option("-paste");
    }

    $self->{code} = join ' ', @opt_args;

    if ($self->{code} =~ s/-stdin[ =]?(.*)$//) {
        $self->add_option("-stdin", $1);
    }
}

sub process_custom_options {}

sub process_cmdline_options($self) {
    my $code = $self->{code};

    $self->{cmdline_options} = "";

    while ($code =~ s/^\s*(-[^ ]+)\s*//) {
        $self->{cmdline_options} .= "$1 ";
        $self->add_option($1);
    }

    $self->{cmdline_options} =~ s/\s$//;

    $self->{code} = $code;
}

sub add_option($self, $option, $value = '') {
    $self->{options_order} //= [];
    $self->{options}->{$option} = $value;
    push @{$self->{options_order}}, $option;
}

sub pretty_format($self, $code) {
    return $code;
}

sub preprocess_code($self, %opts) {
    if ($self->{only_show}) {
        print "$self->{code}\n";
        $self->done;
        exit;
    }

    unless($self->{got_run} and $self->{copy_code}) {
        $self->debug("---- preprocess\n");
        $self->debug("$self->{nick} $self->{channel}: [$self->{arguments}] $self->{cmdline_options} $self->{code}\n", 0);
    }

    # replace \n outside of quotes with literal newline
    my $new_code = "";

    use constant {
        NORMAL        => 0,
        DOUBLE_QUOTED => 1,
        SINGLE_QUOTED => 2,
    };

    my $state = NORMAL;
    my $escaped = 0;

    my @chars = split //, $self->{code};
    foreach my $ch (@chars) {
        given ($ch) {
            when ('\\') {
                if ($escaped == 0) {
                    $escaped = 1;
                    next;
                }
            }

            if ($state == NORMAL) {
                when ($_ eq '"' and not $escaped) {
                    $state = DOUBLE_QUOTED;
                }

                when ($_ eq "'" and not $escaped) {
                    $state = SINGLE_QUOTED;
                }

                when ($_ eq 'n' and $escaped == 1) {
                    $ch = "\n";
                    $escaped = 0;
                }
            }

            if ($state == DOUBLE_QUOTED) {
                when ($_ eq '"' and not $escaped) {
                    $state = NORMAL;
                }
            }

            if ($state == SINGLE_QUOTED) {
                when ($_ eq "'" and not $escaped) {
                    $state = NORMAL;
                }
            }
        }

        $new_code .= '\\' and $escaped = 0 if $escaped;
        $new_code .= $ch;
    }

    if (!$opts{omit_prelude} && exists $self->{prelude}) {
        $self->{code} = "$self->{prelude}\n$self->{code}";
    }

    $self->{code} = $new_code;
}

sub execute {
    my ($self) = @_;

    my $input  = $self->{'vm-input'};
    my $output = $self->{'vm-output'};

    my $date = time;
    my $stdin = $self->{options}->{'-stdin'};

    if (not length $stdin) {
        $stdin = decode('UTF-8', `fortune -u -s`);
        $stdin =~ s/[\n\r\t]/ /msg;
        $stdin =~ s/:/ - /g;
        $stdin =~ s/\s+/ /g;
        $stdin =~ s/^\s+//;
        $stdin =~ s/\s+$//;
    }

    $stdin =~ s/(?<!\\)\\n/\n/mg;
    $stdin =~ s/(?<!\\)\\r/\r/mg;
    $stdin =~ s/(?<!\\)\\t/\t/mg;
    $stdin =~ s/(?<!\\)\\b/\b/mg;
    $stdin =~ s/(?<!\\)\\x([a-f0-9]+)/chr hex $1/igme;
    $stdin =~ s/(?<!\\)\\([0-7]+)/chr oct $1/gme;

    my $pretty_code = $self->pretty_format($self->{code});

    my $cmdline = $self->{cmdline};

    $cmdline =~ s/\$sourcefile/$self->{sourcefile}/g;
    $cmdline =~ s/\$execfile/$self->{execfile}/g;

    my $options = length $self->{cmdline_options} ? $self->{cmdline_options} : $self->{default_options};

    if ((not exists $self->{options}->{'-paste'}) and (not defined $self->{got_run} or $self->{got_run} ne 'paste')) {
        if (exists $self->{options_nopaste}) {
            $options .= ' ' if length $options;
            $options .= $self->{options_nopaste};
        }
    } else {
        if (exists $self->{options_paste}) {
            $options .= ' ' if length $options;
            $options .= $self->{options_paste};
        }
    }

    if (length $options) {
        $cmdline =~ s/\$options/$options/;
    } else {
        $cmdline =~ s/\$options\s+//;
    }

    $self->debug("---- executing\n");
    $self->debug("$cmdline\n$stdin\n$pretty_code\n", 0);

    my $compile_in = {
        lang       => $self->{lang},
        sourcefile => $self->{sourcefile},
        execfile   => $self->{execfile},
        cmdline    => $cmdline,
        input      => $stdin,
        date       => $date,
        arguments  => $self->{arguments},
        code       => $pretty_code
    };

    $compile_in->{'factoid'} = $self->{'factoid'} if length $self->{'factoid'};
    $compile_in->{'persist-key'} = $self->{'persist-key'} if length $self->{'persist-key'};

    my $compile_json = encode_json($compile_in);
    $compile_json .= "\n:end:\n";

    my $length = length $compile_json;
    my $sent = 0;
    my $chunk_max = 16384;
    my $chunk_size = $length < $chunk_max ? $length : $chunk_max;
    my $chunks_sent = 0;

    # $self->debug("Sending $length bytes [$compile_json] to vm_server\n");

    $chunk_size -= 1; # account for newline in syswrite

    while ($chunks_sent < $length) {
        my $chunk = substr $compile_json, $chunks_sent, $chunk_size;

        $chunks_sent += length $chunk;

        my $ret = syswrite($input, $chunk);

        if (not defined $ret) {
            my $error = $!;
            print STDERR "Error sending: $error\n";
            $self->debug("Error sending: $error\n");
            last;
        }

        if ($ret == 0) {
            print STDERR "Sent 0 bytes. Sleep 1 sec and try again\n";
            $self->debug("Sent 0 bytes. Sleep 1 sec and try again\n");
            sleep 1;
            next;
        }

        $sent += $ret;
    }

    my $result = "";
    my $got_result = 0;

    while (my $line = decode('UTF-8', <$output>)) {
        $line =~ s/[\r\n]+$//;
        last if $line =~ /^result:end$/;

        if ($line =~ /^result:/) {
            $line =~ s/^result://;

            $line = encode('UTF-8', $line);
            my $octets = decode('UTF-8', $line, sub { sprintf '\\\\x%02X', shift });
            $line = encode('UTF-8', $octets, Encode::FB_CROAK);

            my $compile_out = decode_json($line);
            $result .= "$compile_out->{result}\n";
            $got_result = 1;
            next;
        }

        if ($got_result) {
            $result .= "$line\n";
        }
    }

    close $input;

    $self->{output} = $result;

    return $result;
}

sub postprocess_output($self) {
    unless($self->{got_run} and $self->{copy_code}) {
        $self->debug("---- post-processing\n");
        $self->debug("$self->{output}\n", 0);
    }

    # backspace
    my $boutput = "";
    my $active_position = 0;
    $self->{output} =~ s/\n$//;
    while ($self->{output} =~ /(.)/gms) {
        my $c = $1;
        if ($c eq "\b") {
            if (--$active_position <= 0) {
                $active_position = 0;
            }
            next;
        }
        substr($boutput, $active_position++, 1) = $c;
    }
    $self->{output} = $boutput;

    # bell
    my @beeps = qw/*BEEP* *BING* *DING* *DONG* *CLUNK* *BONG* *PING* *BOOP* *BLIP* *BOP* *WHIRR*/;
    $self->{output} =~ s/\007/$beeps[rand @beeps]/g;

    # known control characters
    my %escapes = (
        "\e" => '<esc>',
        "\f" => '<ff>',

        # \r and \n are disabled so the bot itself processes them, e.g. when
        # web-pasting, etc. feel free to uncomment them if you like (add them
        # to the group in the substitution regex as well).

        # "\r" => '<cr>',
        # "\n" => '<nl>',

        # \t is left alone
    );

    $self->{output} =~ s/([\e\f])/$escapes{$1}/gs;

    # other unprintables
    my %disregard = ( "\n" => 1, "\r" => 1, "\t" => 1, "\x03" => 1 );
    $self->{output} =~ s/([\x00-\x1f])/$disregard{$1} ? $1 : sprintf('\x%02X', ord $1)/gse;
}

sub show_output($self) {
    my $output = $self->{output};

    unless ($self->{got_run} and $self->{copy_code}) {
        $self->debug("---- show output\n");
        $self->debug("$output\n", 0);
        $self->debug("=========================\n", 0);
    }

    if (exists $self->{options}->{'-paste'} or (defined $self->{got_run} and $self->{got_run} eq 'paste')) {
        my $cmdline = "$self->{cmdline}\n";

        $cmdline =~ s/\$sourcefile/$self->{sourcefile}/g;
        $cmdline =~ s/\$execfile/$self->{execfile}/g;

        my $options;
        if (length $self->{cmdline_options}) {
            $options = $self->{cmdline_options};
        } else {
            $options = $self->{default_options};
        }

        if (exists $self->{options_paste}) {
            $options .= ' ' if length $options;
            $options .= $self->{options_paste};
        }

        if (length $options) {
            $cmdline =~ s/\$options/$options/;
        } else {
            $cmdline =~ s/\$options\s+//;
        }

        if (length $self->{arguments}) {
            $cmdline .= "arguments: $self->{arguments}\n";
        }

        if ($self->{options}->{'-stdin'}) {
            $cmdline .= "stdin: $self->{options}->{'-stdin'}\n";
        }

        my $pretty_code = $self->pretty_format($self->{code});

        my $cmdline_opening_comment = $self->{cmdline_opening_comment} // "/************* CMDLINE *************\n";
        my $cmdline_closing_comment = $self->{cmdline_closing_comment} // "************** CMDLINE *************/\n";

        my $output_opening_comment = $self->{output_opening_comment} // "/************* OUTPUT *************\n";
        my $output_closing_comment = $self->{output_closing_comment} // "************** OUTPUT *************/\n";

        $pretty_code .= "\n\n";
        $pretty_code .= $cmdline_opening_comment;
        $pretty_code .= "$cmdline";
        $pretty_code .= $cmdline_closing_comment;

        $output =~ s/\s+$//;
        $pretty_code .= "\n";
        $pretty_code .= $output_opening_comment;
        $pretty_code .= "$output\n";
        $pretty_code .= $output_closing_comment;

        my $uri = paste_0x0(encode('UTF-8', $pretty_code));
        print "$uri\n";
        $self->done;
        exit 0;
    }

    if ($self->{channel} =~ m/^#/ and length $output > 22 and open my $fh, '<:encoding(UTF-8)', "$RealBin/../history/$self->{channel}-$self->{lang}.last-output") {
        my $last_output;
        my $time = <$fh>;

        if (gettimeofday - $time > 60 * 4) {
            close $fh;
        } else {
            while (my $line = <$fh>) {
                $last_output .= $line;
            }
            close $fh;

            if ((not $self->{factoid}) and defined $last_output and $last_output eq $output) {
                print "Same output.\n";
                $self->done;
                exit 0;
            }
        }
    }

    print encode('UTF-8', "$output\n");

    my $file = "$RealBin/../history/$self->{channel}-$self->{lang}.last-output";
    open my $fh, '>:encoding(UTF-8)', $file or die "Couldn't open $file: $!";
    my $now = gettimeofday;
    print $fh "$now\n";
    print $fh "$output";
    close $fh;
}

sub debug($self, $text, $timestamp = 1) {
    if (not exists $self->{logh}) {
        open $self->{logh}, '>>:encoding(UTF-8)', "$RealBin/../log.txt" or die "Could not open log file: $!";
    }

    if ($timestamp) {
        my ($sec, $usec) = gettimeofday;
        my $time = strftime "%a %b %e %Y %H:%M:%S", localtime $sec;
        $time .= sprintf ".%03d", $usec / 1000;
        print { $self->{logh} } "$time :: $text";
    } else {
        print { $self->{logh} } $text;
    }
}

sub done($self) {
    if ($self->{logh}) {
        close $self->{logh};
        delete $self->{logh};
    }
}

1;
